# Design — Token deadline valid until end of day, landing pages read-only for inactive tokens

Revised 2026-10-13. The 2026-10-12 proposal to switch the vendor landing GET to `decodeTokenFromParams`
(401 → Page Expired) was **rejected** by BA in favour of a read-only landing page (requirements FR-5..FR-7).

## Current behavior (before this change)

- `src/helper/date.js` `addBusinessDays` → `moment(start).startOf('day')` + N Mon–Fri days in the **process**
  timezone. Production runs in UTC, so every stored `date_expired` is 07:00:00 WIB.
- `src/helper/slaCalculator.js` `calculateSubmissionDeadlineAndSla` returns that date, a `DD MMM YYYY` label
  and `sla = '<N>d'` for the JWT.
- Writers of `date_expired`: `emailHelper.js` link generators (10×), `emailController.js` CS resend (2×) via
  `calculateSubmissionDeadlineAndSla`; `prController.generateTokenRFQ` and the qcf DIC single-submission
  reminder token via `addBusinessDays` directly (JWT signed with `'Nd'`).
- Expiry selection (`rfqTokenEmail.query.repository.js` ×2, `qcfTokenEmail.query.repository.js` ×1):
  `date_expired <= moment().endOf('day')`, run by the ≈ 08:00 WIB cron (`src/cron.js`).
- Landing GETs `/pr/vendor/get_item_list_rfq/:token` and `/pr/dic/get_item_list_rfq/:token` use
  `decodeTokenWithForbiddenException` (JWT only); action PUTs use `authService.authenticateTokenEmail`
  (DB `is_active` + `date_expired`, 401). The pages always render action buttons.

## Implemented behavior

1. **End-of-day deadline (FR-1..FR-3, FR-7a).**
   - `date.js`: `addBusinessDaysEndOfDay(start, days, tz = 'Asia/Jakarta')` and exported
     `BUSINESS_TIMEZONE`. `addBusinessDays` unchanged (delivery dates, mock data).
   - `slaCalculator.js`: deadline = 23:59:59.999 WIB, label formatted in WIB, `sla` = seconds until the
     deadline (≥ 1). Uses the fixed `BUSINESS_TIMEZONE`, **not** `config.tz` (= `process.env.TZ`), because a
     production `TZ=UTC` would otherwise re-introduce the bug.
   - `prController.generateTokenRFQ` and `qcfController` DIC single-submission token use
     `calculateSubmissionDeadlineAndSla` for both `date_expired` and `expiresIn`.
2. **Cron cut-off (FR-4).** The three expiry queries use `date_expired <= new Date()`.
3. **Token state (FR-5).** `tokenMiddleware.js` adds `isTokenRecordActive(record, now)`, `getTokenActive(token)`
   and middleware `attachTokenState` (sets `req.tokenActive`; 500 on DB error, token never logged).
   Both landing routes chain `decodeTokenWithForbiddenException → attachTokenState → controller`;
   `listItemRFQVendor` / `listItemRFQDIC` add `token_active` only when `req.tokenActive !== undefined`
   (internal `prService` calls with a mocked `req` keep their payload).
4. **Re-check endpoint (FR-7).** `GET /pr/token/status/:token` → `prController.getTokenStatus`, always 200
   `{ token_active }` (false for JWT errors / missing / inactive / expired rows), 400 when the param is
   missing, 500 on unexpected errors. 200-with-false avoids the frontend 401 interceptor (toast + redirect).
5. **Frontend read-only (FR-6, FR-7).**
   - `services/form/TokenStatusService.js` `getTokenStatus(token)`; missing field ⇒ active.
   - `hooks/useTokenActiveGuard.js` → `{ tokenActive, readOnly, setTokenActive, recheck, ensureActive }`;
     `visibilitychange` listener (added on mount, removed on unmount), de-duplicated in-flight calls,
     read-only is sticky; a failed status request keeps the state and lets the action proceed.
   - Vendor (`VendorQuotation.vue`, `TableQuotationItems.vue`) and DIC (`ConfirmationItemDIC.vue`,
     `TableConfirmationItems.vue`): footer buttons hidden, editable controls disabled, image viewers and
     table scroll kept; pre-action `ensureActive()` on submit/handleSubmit (both pages), vendor
     actuallySubmit, reset, document remove and DECLINE image cleanup. On inactive the open popups close.
     No new toast/Swal/banner.
   - `PopupConfirmation.vue` (vendor and DIC) expose `close`; shared `FileInput.vue` no longer opens the
     picker when `readonly`.

## Interface changes

| Endpoint | Change |
|---|---|
| `GET /pr/vendor/get_item_list_rfq/:token` | `data.token_active: boolean` added; status codes unchanged (403 JWT, 400 no items) |
| `GET /pr/dic/get_item_list_rfq/:token` | same |
| `GET /pr/token/status/:token` | **new**, 200 `{ data: { token_active } }` |
| `PUT /pr/vendor/submit_penawaran`, `PUT /pr/dic/konfirmasi_penawaran` | unchanged |

OpenAPI: `docs/openapi/paths/pr_vendor_get_item_list_rfq_{token}.yaml`, `pr_dic_get_item_list_rfq_{token}.yaml`,
new `pr_token_status_{token}.yaml`, `openapi.yaml`, `openapi.bundle.yaml` (hand-mirrored).

## Data design

No schema change, migration or back-fill. Tokens issued before deploy keep their 07:00 `date_expired`.

## Alternatives considered

| Alternative | Decision |
|---|---|
| Change `addBusinessDays` itself | Rejected: also used for delivery dates and mock data |
| Keep `<= endOf('day')` | Rejected: the 08:00 cron would still close same-day tokens |
| Landing GET → `decodeTokenFromParams` (401, Page Expired) | Rejected by BA 2026-10-13: page must stay, without buttons and without the "Token is not active" message |
| Re-check by re-calling the landing GET | Rejected: DIC landing returns 400 once the milestone moves (→ Page Expired), vendor landing deletes orphan images on load, heavy payload |
| Use `config.tz` for the business timezone | Rejected: equals `process.env.TZ` |

## Risks

| Risk | Mitigation |
|---|---|
| Follow-up actions move to the morning after the deadline (BR-4) | Business confirmation pending |
| Race between pre-action re-check and the action | Accepted; existing dialog may still appear |
| `rfq_token` is `TEXT`, likely unindexed; one more lookup per landing/re-check | Same query `authenticateTokenEmail` runs per action; check `EXPLAIN` if load grows |
| User-triggered image upload/delete inside shared child components is not pre-checked | Controls are disabled once read-only; action endpoints remain authoritative |
| `qcfController.sendDicConfirmationReminders` skipped the deadline day (day granularity) | Fixed in review: instant comparison |
| `mockRfqService.js` mock tokens still use `addBusinessDays` (07:00) | Excluded: mock data only (`/mock`, authenticated) |

## Rollout and rollback

- Deploy backend first (API and cron together), then frontend. Old frontend ignores `token_active`; new
  frontend against old backend treats a missing flag as active and the status call fails silently.
- Rollback: revert code. Tokens issued while live keep 23:59:59 and would be closed by the old query on
  that day's 08:00 run (today's behaviour).
