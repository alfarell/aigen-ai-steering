# Design — RFQ vendor token not created on launch

## Current behavior

Verified on `aigen-backend` @ `develop-dot` (`7b694635`), read-only, 2026-09-02.

### Launch does not create a token

`prController.submitRFQ` (`src/controllers/prController.js:67`) calls
`prLibrary.addRFQTables` (`src/repository/PurchaseRequest.repository.js:157`),
which performs `rfqLibrary.findOrCreate` at line 174 with
`status_milestone = 1` (RFQ_LAUNCHED) and `status_vendor = null`.
**No token is written on this path** — `addRFQTables` contains no token logic.

Token creation happens only on a subsequent dispatch call. This split is
existing intended design, not the defect (see OI-1).

### Two divergent dispatch paths

**Path A — `emailController.sendRequestForQuotation` (`src/controllers/emailController.js:390`)**

Reached from `POST /send-request-for-quotation/:token` (`src/routes/emailRoutes.js:12`)
and `POST /cs/resend_rfq/:rfq_number/:vendor_batch` (`src/routes/purchaseRoutes.js:273`).

1. `getPRDetails(clause)` — guarded: returns 400 when empty (`emailController.js:437`).
2. Mutates `status_vendor = PENDING`, `status_milestone = RFQ_SENT_TO_VENDOR` (`:447-461`).
3. SLA config lookup; returns 400 when missing/inactive (`:478-489`).
4. `EmailHelper.generateVendorQutationLink({...}, { saveTokenToDB: true })` (`:570`).
5. Email dispatch (`:620`), activity log (`:618`).

`generateVendorQutationLink` (`src/helper/emailHelper.js:16`) signs the JWT (`:40`),
looks up an existing token (`:45-49`), then **updates** (`:52`) or **creates** (`:65`),
and returns `/#/vendor/quotation/{token}` (`:86`).

**Path B — `emailService.resendEmailVendors` (`src/services/emailServices.js:704`)**

Reached from `prService.js:166` (vendor expiry escalation to lvl1 + lvl2),
`qcfController.js:990`, `:995`, `:2237`, `emailController.js:535`, `prController.js:1856`.

It reimplements the same flow inline and **does not** use `generateVendorQutationLink`.
It signs its own JWT (`:796`) and calls `rfqTokenEmail.create()` (`:802`) unconditionally.

### Confirmed defects in path B

> ## ⚠ CORRECTION (2026-09-02): D-1 IS NOT A DEFECT
>
> D-1 was the anchor of the original root-cause analysis. It is **wrong**, and everything in this
> document that depends on it is void.
>
> Sequelize normalises a nested array passed to `Op.in`. Both clause shapes emit **identical SQL**,
> verified by capturing the generated statement against a production copy:
>
> ```
> OLD (nested)  ... item_code IN ('10', '20', '30');
> NEW (flat)    ... item_code IN ('10', '20', '30');
> ```
>
> Checked on scopes of 1, 2 and 3 item codes — the row counts match in every case. The nested array
> never suppressed a single row, so it never emptied `getdata`, never triggered D-2, and never
> aborted the vendor loop.
>
> An earlier partial correction in `test-plan.md` claimed D-1 was harmless only for single-item
> RFQs because MySQL flattens `IN (('10'))`. **That was also wrong** — the flattening happens in
> Sequelize, before SQL is generated, and applies at any cardinality.
>
> Changing the clause to `{ [Op.in]: item_codes }` remains correct as code hygiene, but it fixes
> no behaviour. **The root cause of the reported issue is still unexplained** — see the RG-6 and
> "Local replication" sections of `test-plan.md`. D-2..D-5 below are unaffected by this correction
> and remain real; D-4 and D-5 are the two with measured production impact.

| ID | Line | Defect |
|---|---|---|
| ~~D-1~~ | ~~`emailServices.js:735`~~ | **VOID — not a defect.** See the correction above. `{ [Op.in]: [item_codes] }` is normalised by Sequelize to the same SQL as the flat form. |
| D-2 | `emailServices.js:759-761` | `const firstItem = getdata[0]` with no empty guard, immediately destructured at `:761`. Throws `TypeError: Cannot destructure property 'cs_id' of 'undefined'` whenever the eligibility filter genuinely matches nothing — e.g. every item for that vendor already submitted. (The original text attributed the empty set to D-1; that attribution is void, but the missing guard is real and reachable on its own.) Path A has this guard (`emailController.js:437`); path B does not. |
| D-3 | `emailServices.js:709`, `:774` | `sendResponse(res, ...)` references `res`, which is **not a parameter** — the signature is `(request)` (`:704`). Both guard branches throw `ReferenceError: res is not defined` instead of returning. This masks the real cause (missing `rfq_number`, missing SLA config) behind a misleading error. |
| D-4 | `emailServices.js:743-757` vs `:802` | Status is mutated to `RFQ_SENT_TO_VENDOR` **before** the token is created, with no transaction. Anything throwing in between (D-2, D-3, SLA lookup, JWT) leaves the RFQ marked "sent to vendor" with no token and no email — the exact reported symptom. Path A has the same ordering hazard (`emailController.js:447` before `:570`). |
| D-5 | `emailServices.js:802` | `rfqTokenEmail.create()` is unconditional. Repeated dispatch accumulates multiple active rows for one `(rfq_number, vendor_batch, vendor_code)`, unlike path A which updates in place. **Harm restated 2026-09-02:** the original text implied duplicate *usable links*. Measured against a production copy, that never happens — **zero** scopes hold more than one token that is both active and unexpired. The real harm is duplicate **work items**: `getExpiredRFQTokenEmailByConfig` selects `is_active = true` AND `date_expired <= now` as expiry-cron work, and **198 of 199** duplicate scopes hold two such rows, so those RFQs are escalated twice. |
| D-6 | `emailServices.js:856` | The catch logs and rethrows. `prService.js:166` awaits inside a `for await` loop over `[vendorLvl1, vendorLvl2]`, so a throw for lvl1 aborts lvl2 as well. |

### ~~Failure chain that reproduces the report~~ — VOID (2026-09-02)

**This chain cannot occur.** Its first step is D-1, which is not a defect (see the correction
above): the nested array does not match zero rows, so `getdata` is never emptied by it and the
TypeError is never reached from this direction. The chain is kept only so the retraction is
traceable.

```
prService.js:166  resendEmailVendors({ ..., item_codes: [...] })
        ↓
emailServices.js:735   item_code IN (('A','B'))        ← D-1: WRONG, Sequelize flattens this
        ↓                                                to IN ('A','B') and matches normally
emailServices.js:738   getdata = []                    ← does NOT happen
        ↓
emailServices.js:743   itemIdsToUpdate = []  → no status update this iteration
        ↓
emailServices.js:759   firstItem = undefined
emailServices.js:761   destructure                     ← D-2, TypeError
        ↓
emailServices.js:856   rethrow  → aborts the vendor loop in prService.js:164
        ↓
rfqTokenEmail row never created → vendor link 404/invalid
```

**What the evidence actually supports.** D-4 (status mutated before the token is written) is the
mechanism that produces the reported "marked as sent, no working link" state, and it is measurable:
12 scopes sit at `status_milestone = 2` with no active vendor token in the production copy. D-5
(unconditional `create`) is likewise measurable: 199 scopes hold more than one active vendor token.
Neither explains `RFQ0002052` specifically, whose `status_vendor = null` alongside milestone 2
cannot be produced by any dispatch path in the codebase.

D-4 explains the state where status *is* already `RFQ_SENT_TO_VENDOR` but no token exists — a
throw occurring after the status update, e.g. missing SLA config via D-3. This is the mechanism
with measured production impact (12 scopes), and it does not depend on the void D-1.

## Proposed behavior

Smallest complete change, confined to `resendEmailVendors` plus the shared helper it
adopts. No schema change, no migration, no new endpoint.

1. ~~**Fix the scope filter (D-1 → FR-1).**~~ **Code hygiene only, fixes no behaviour** — see the
   D-1 correction above. `clause.item_code = { [Op.in]: item_codes }` emits the same SQL as the
   nested form. Keep the `Array.isArray` guard so the key is omitted when `item_codes` is absent
   (AC-2) — that guard is what actually matters here, and it was already correct.
2. **Guard the empty set (D-2 → FR-2, AC-3).** After `getPRDetails`, return a structured
   outcome (e.g. `{ sent: false, reason: 'NO_ELIGIBLE_ITEMS' }`) before touching `getdata[0]`.
3. **Remove the `res` references (D-3 → FR-3, AC-4).** Replace both `sendResponse(res, ...)`
   branches with a typed error or the same structured outcome. Use `BadRequestError` from
   `src/errors/HttpError.js` for the SLA-config failure — verified present and exported
   alongside `HttpError`, `UnauthorizedError`, `ForbiddenError`, `NotFoundError`,
   `InternalServerError`.

   > **Correction (2026-09-02).** An earlier revision of this line cited a
   > `ManualSourcingInvocationError` precedent from the `auto-manual-sourcing-header-integrity`
   > spec. That class **does not exist in code** — it is a design-document term only, confirmed
   > by a repository-wide search. Do not introduce it. No new error class is warranted here.
4. **Reorder so status follows success (D-4 → FR-4, AC-5).** Create the token and send the
   email first, mutate `status_vendor`/`status_milestone` only after both succeed; or wrap
   the status update and token creation in one transaction and roll back on failure. The
   reorder is preferred — it is smaller and needs no transaction plumbing across the email
   side effect, which cannot be rolled back anyway.
5. **Reuse the shared helper (D-5 → FR-5, FR-6, AC-6).** Replace the inline JWT sign +
   `rfqTokenEmail.create()` (`:796-826`) with
   `EmailHelper.generateVendorQutationLink({...}, { saveTokenToDB: true })`, which already
   implements check-then-update-or-create. This deletes the duplicated logic rather than
   fixing it twice.
6. **Contain per-vendor failures (D-6 → FR-7).** Decide, with the owner, whether a lvl1
   failure should abort lvl2 in `prService.js:164`. Default proposal: log and continue to the
   next vendor, returning an aggregate outcome, so one vendor's misconfiguration does not
   silently drop the other. Flagged as a behavior change — see OI-6.

## Affected components

| Repository/component | Current symbol/path | Proposed change |
|---|---|---|
| aigen-backend | `resendEmailVendors` — `src/services/emailServices.js:704-857` | Fix D-2..D-5 (D-1 is void — hygiene only); delegate token persistence to the shared helper; return a structured outcome |
| aigen-backend | `EmailHelper.generateVendorQutationLink` — `src/helper/emailHelper.js:16-88` | Reused as-is. Change only if path B needs a parameter it does not expose |
| aigen-backend | `prService.js:164-175` | Consume the structured outcome; decide loop-continuation policy (OI-6) |
| aigen-backend | `emailController.sendRequestForQuotation` — `src/controllers/emailController.js:390` | Apply the D-4 reordering only. No other change |
| aigen-backend | `tests/services/` | New regression tests (see `test-plan.md`) |

## Interface changes

None. No HTTP route, payload, status code, or event contract changes.
`resendEmailVendors` is an internal service function; its **return value** becomes
structured where it was previously `undefined`. All six call sites currently ignore the
return value, so this is backward compatible — but each must be checked (task I-6).

## Data design

- Schemas/tables/models: `rfq_token_email` and `rfq_library`, both unchanged.
- Migration/seed/backfill: **None in this change.** Remediation of `RFQ0002052` and any
  pre-existing duplicate token rows is deliberately excluded (OI-3, OI-5).
- Transaction boundary: `generateVendorQutationLink` accepts an optional `transaction`
  (`emailHelper.js:65`). Preferred design avoids a new transaction by reordering (item 4);
  if reordering proves insufficient, wrap status update + token write in one transaction.
  The email send must stay outside any transaction.
- Idempotency/concurrency: check-then-update-or-create in the helper is not atomic under
  concurrent dispatch for the same scope. Acceptable at current volume; noted as a risk.
- Data retention/rollback: none. No destructive operation is introduced.

## UI and state

- Routes and role metadata: unchanged. Vendor route `/#/vendor/quotation/{token}` in
  `aigen-frontend/src/router/index.js`.
- Feature components/hooks/services: unchanged.
- Loading/empty/error/success behavior: unchanged.
- Accessibility: N/A.

## Security

- Backend authorization: unchanged. `tokenMiddleware` remains the sole gate for vendor access.
- Token lifetime/purpose/revocation: unchanged expiry derivation (BR-2). FR-6 keeps one active row
  per scope. **Rationale corrected 2026-09-02:** this is not primarily about revocation surface —
  no scope ever held two simultaneously usable tokens. It is about the expiry cron, which treats an
  active-but-expired row as a work item, so a second row means the RFQ is escalated twice.
- Validation: `item_codes` must be validated as an array of strings before entering the
  `Op.in` clause.
- Logging/redaction: log token presence and expiry, never the JWT value or the signing secret.

## Integrations and failure handling

- Email: `sendEmailRequestForQuotation` (`emailServices.js:852`) is a non-rollbackable side
  effect. Order it after token persistence so a token always exists for any link that was
  actually sent; a token without a sent email is the safe failure direction (the RFQ can be
  resent), whereas an email without a token is the reported bug.
- Sentry: preserve existing capture; add `rfq_number` / `vendor_code` / `vendor_batch` context.
- SAP / Kafka / filesystem: not involved.

## Alternatives considered

| Alternative | Reason accepted/rejected |
|---|---|
| ~~Fix only D-1 (the `Op.in` bug)~~ | **Moot (2026-09-02).** D-1 is not a bug, so this alternative would have fixed nothing at all. The real value of this change sits in D-4 and D-5. |
| Create the token during `submitRFQ` (at launch) | **Rejected.** Changes intended launch/dispatch separation and would issue tokens for RFQs never dispatched; expiry is derived at dispatch time |
| Add a reconciliation cron that backfills missing tokens | **Rejected as the primary fix.** Treats the symptom; may still be worth proposing separately for already-affected RFQs (OI-3) |
| Wrap everything in one DB transaction | **Partially rejected.** The email send cannot participate; reordering achieves the goal with less plumbing |
| Delete path B and route all callers through path A | **Rejected for this change.** Path A is an Express handler needing `req`/`res`; converting six call sites exceeds the smallest-fix scope. Sharing the helper (item 5) captures most of the benefit |

## Risks and mitigations

| Risk | Likelihood/impact | Mitigation |
|---|---|---|
| ~~Fixing D-1 makes the expiry path actually dispatch emails that never sent before, causing a burst of vendor emails on first deploy~~ | **VOID (2026-09-02)** | This risk depended on D-1 having suppressed rows. It never did — the clause matched normally all along, so no backlog of undispatched RFQs was accumulating and no burst is possible. The "count eligible rows before deploy" step this risk generated is no longer a release gate. |
| Reordering status updates changes what dashboards show mid-flight | Medium / Medium | Confirm no dashboard query depends on `RFQ_SENT_TO_VENDOR` being set before the email; check `dashboardHelper.js` |
| Switching to the shared helper changes token expiry or payload shape versus the inline version | Medium / High | Diff the two payloads field by field before switching (task I-5); assert payload equivalence in a unit test |
| Existing production rows already have duplicate active tokens | Unknown / Medium | Detect via the OI-5 query; remediate separately |
| Per-vendor loop policy change (item 6) alters escalation behavior | Medium / Medium | Gate behind owner confirmation (OI-6); keep current abort behavior if unconfirmed |
| No existing test covers `resendEmailVendors` | Confirmed / Medium | Tests are part of this change, written before the fix |

## Rollout and rollback

- Feature flags: none proposed. The email-burst risk that previously motivated a flag is void
  (see Risks) — D-1 never suppressed dispatches, so there is no backlog to release at once.
- Deploy order: `aigen-backend` only. No frontend or importer coordination required.
- Migration order: N/A.
- Monitoring after deploy: watch dispatch-failure log lines (FR-7), Sentry volume, outbound
  email volume, and the count of RFQs at `RFQ_SENT_TO_VENDOR` with no active token row.
- Rollback: revert the commit. No schema or data change to undo. Tokens created while the fix
  was live remain valid and are unaffected by the revert.
