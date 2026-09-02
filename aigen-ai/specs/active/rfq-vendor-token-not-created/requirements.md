# Requirements — RFQ vendor token not created on launch

Status: Planned
Owner: Unknown
Repositories: `aigen-backend` (primary). `aigen-frontend` consumes the link only; no change expected.
Created: 2026-09-02
Last updated: 2026-09-02

## Background and problem

Production report: on PR `8100020736` / RFQ `RFQ0002052` the vendor RFQ token was
not created, so the vendor could not open the RFQ detail from the emailed link.

Terminology correction, confirmed by code: `rfq_library` has **no** token column
(`aigen-backend/src/models/default/rfqLibrary.js`). Vendor tokens live in
`rfq_token_email` (`aigen-backend/src/models/default/rfqTokenEmail.js:18`,
column `rfq_token`). The reported symptom is a missing row in `rfq_token_email`.

Two independent implementations create that row:

| Path | Location | Token write |
|---|---|---|
| A — HTTP/CS | `emailController.sendRequestForQuotation` (`src/controllers/emailController.js:390`) | `EmailHelper.generateVendorQutationLink({ saveTokenToDB: true })` (`src/helper/emailHelper.js:16`), which checks-then-updates-or-creates |
| B — system/expiry | `emailService.resendEmailVendors` (`src/services/emailServices.js:704`) | `rfqTokenEmail.create()` (`src/services/emailServices.js:802`), unconditional |

Path B contains defects that abort execution **before** line 802 is reached, and
it mutates RFQ status **before** the token exists. That produces exactly the
reported state: an RFQ that looks sent, with no token and no working vendor link.

## Goal

An RFQ that has been launched and dispatched to a vendor always has a usable,
active `rfq_token_email` row, and the vendor can open the RFQ detail from the
emailed link. When dispatch cannot complete, the RFQ must not be left displaying
`RFQ_SENT_TO_VENDOR`.

## Scope

- Included:
  - Fix the defects in `resendEmailVendors` that prevent token creation.
  - Make status mutation and token creation consistent, so "sent" implies "token exists".
  - Converge path B onto the same token-persistence helper used by path A.
  - Regression tests for token creation, the item-scope filter, and the failure paths.
- Excluded:
  - Any production data mutation or backfill for `RFQ0002052` (needs separate approval; see OI-3).
  - Redesign of the RFQ launch/dispatch split (`submitRFQ` intentionally stays separate from dispatch).
  - Frontend changes.
  - Broad refactor of `emailServices.js` beyond the functions named here.

## Actors

| Actor/system | Need or responsibility |
|---|---|
| Vendor | Opens RFQ detail via `/#/vendor/quotation/{token}` and submits a quotation |
| CS user | Sends/resends the RFQ manually (path A) |
| Expiry cron / `prService` | Escalates to vendor lvl1+lvl2 on expiry (path B, `src/services/prService.js:166`) |
| `rfq_token_email` | Single source of truth for vendor link validity |

## Functional requirements

- ~~**FR-1:**~~ **WITHDRAWN 2026-09-02.** This requirement was written on the belief that the
  nested `Op.in` array returned an empty set. It does not — Sequelize normalises it and the SQL is
  identical either way (see the correction in `design.md`). The scope filter was never broken.
  What must hold, and already did, is that an absent `item_codes` omits the clause entirely (AC-2).
- **FR-2:** When the resolved item set is empty, `resendEmailVendors` must return a structured,
  logged outcome to its caller instead of throwing on `undefined`.
- **FR-3:** Guard clauses inside `resendEmailVendors` must not reference an undefined `res`;
  the function is a service, not an Express handler, and must signal failure through its return
  value or a typed error.
- **FR-4:** An RFQ item must not be left at `status_milestone = RFQ_SENT_TO_VENDOR` when token
  creation or email dispatch failed for that item.
- **FR-5:** Token persistence in path B must reuse `EmailHelper.generateVendorQutationLink`
  so that both paths share one check-then-update-or-create behavior.
- **FR-6:** Re-sending an RFQ to the same `(rfq_number, vendor_batch, vendor_code, user_type)`
  must not accumulate multiple active token rows.
- **FR-7:** Failures in the dispatch path must be recorded with enough context
  (`rfq_number`, `vendor_code`, `vendor_batch`, cause) to diagnose without production access.

## Business rules

- **BR-1:** A vendor link is valid only while a matching `rfq_token_email` row exists with
  `is_active = true` and `date_expired` in the future. Source: `src/middleware/tokenMiddleware.js`. **Confirmed.**
- **BR-2:** The submission deadline is derived from the `WAITING_VENDOR_EXPIRY` SLA config for the
  item's `server_groups`, in business days. Source: `src/services/emailServices.js:768`. **Confirmed.**
- **BR-3:** Only items with `status_vendor` in {`REJECTED`, `PENDING`, `null`} are eligible for
  dispatch. Source: `src/services/emailServices.js:718-731`. **Confirmed.**
- **BR-4:** Whether a launched RFQ should auto-dispatch to the vendor, or always wait for a CS
  action, is **Unknown** — no automatic caller of path A was found. See OI-1.
- **BR-5:** Expected behavior when the SLA config is missing/inactive — block dispatch, or fall back
  to a default SLA — is **Unknown**. Current code blocks. See OI-2.

## Security and permissions

- Authentication mechanism: JWT signed with `jwtConfig.secret`, carried in the URL path segment.
- Required roles/permissions/token purpose: `user_type = VENDOR`; grants read of the scoped RFQ
  items and the right to submit a quotation for them.
- Sensitive data/logging constraints: never log the JWT itself, `jwtConfig.secret`, vendor email
  addresses, or production identifiers in test fixtures. Log token presence/absence, not value.
- Abuse or replay considerations: FR-6 exists partly for security — multiple simultaneously active
  tokens for one vendor/batch widen the revocation surface. Deactivating a token must reliably
  revoke access.

## Acceptance criteria

- **AC-1:** Given an RFQ with eligible items and a valid SLA config, when `resendEmailVendors` is
  called with `item_codes` listing those items, then the matching rows are selected, exactly one
  active `rfq_token_email` row exists for the vendor/batch, and the email carries that token.
- **AC-2:** Given the same call **without** `item_codes`, then behavior is unchanged from today
  (all eligible items for the scope are dispatched).
- **AC-3:** Given a scope that resolves to zero eligible items, when `resendEmailVendors` is called,
  then it returns a structured "nothing to send" outcome, writes no token, sends no email, mutates
  no status, and does not throw a `TypeError`.
- **AC-4:** Given a missing or inactive `WAITING_VENDOR_EXPIRY` config, when `resendEmailVendors`
  is called, then it fails with a typed, logged error naming the config key — not
  `ReferenceError: res is not defined` — and no item is left at `RFQ_SENT_TO_VENDOR`.
- **AC-5:** Given token creation or email dispatch throws, when the call completes, then no item in
  that scope remains at `status_milestone = RFQ_SENT_TO_VENDOR` / `status_vendor = PENDING`
  attributable to this attempt.
- **AC-6:** Given a vendor/batch that already has an active token, when the RFQ is resent, then the
  existing row is updated rather than duplicated, and the previously issued link stops working only
  if the token value actually changed.
- **AC-7:** Given a successfully dispatched RFQ, when the vendor opens `/#/vendor/quotation/{token}`,
  then `tokenMiddleware` accepts it and `prController.listItemRFQVendor` returns the scoped items.
- **AC-8:** Regression: the four existing `prService.vendorExpiryGuard` tests still pass.

## Non-functional requirements

- Performance/concurrency: no additional round-trips per item; the dispatch loop in
  `prService.js:164` runs per vendor and must not become N+1 per item.
- Reliability/idempotency: repeated dispatch for the same scope converges to one active token
  (FR-6) and is safe to retry after a partial failure.
- Observability: every dispatch failure emits a log line with `rfq_number`, `vendor_code`,
  `vendor_batch`, and cause. Sentry capture preserved.
- Accessibility/UX: none (no UI change).
- Compatibility: `rfq_token_email` schema unchanged; no migration expected.

## Dependencies and unknowns

| Item | Status | Owner/evidence |
|---|---|---|
| OI-1: Is path A ever triggered automatically after launch, or is CS action always required? | Unknown | No automatic caller found; routes are `emailRoutes.js:12`, `purchaseRoutes.js:273` |
| OI-2: Desired behavior when SLA config is missing/inactive | Unknown | `emailServices.js:768-780` |
| OI-3: Remediation for the already-affected `RFQ0002052` | Unknown / needs approval | Production data; out of scope here |
| OI-4: Was `RFQ0002052` dispatched via path A or path B? | Unknown | Requires the production queries in `test-plan.md` |
| OI-5: Are duplicate active tokens already present in production? | Unknown | Consequence of `emailServices.js:802` |
