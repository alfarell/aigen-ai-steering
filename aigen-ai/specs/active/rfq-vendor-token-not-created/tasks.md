# Tasks — RFQ vendor token not created on launch

Primary repository: `aigen-backend`. Baseline `develop-dot` @ `7b694635` (clean at spec time).
`aigen-frontend` and `aigen-import-pr` are not modified.

## Discovery

- [x] Verify current behavior and reproduction evidence — done read-only 2026-09-02; defects
      D-1..D-6 recorded in `design.md` with file:line.
- [x] Check Git status in each affected repository — all three clean on `develop-dot`.
- [x] Identify interfaces, data, security, jobs, and integrations — see `design.md`.
- [ ] Resolve **OI-1**: is path A ever auto-triggered after launch, or is CS action required?
- [x] Resolve **OI-2**: intended behavior when `WAITING_VENDOR_EXPIRY` is missing/inactive.
      **Decided 2026-09-02 (owner):** keep blocking, but surface it as a typed
      `BadRequestError` naming the config key instead of crashing with `ReferenceError`.
      I-4 approved for implementation.
- [ ] Resolve **OI-4**: determine whether `RFQ0002052` went through path A or path B, using the
      read-only queries in `test-plan.md`. Requires owner-approved database access.
- [x] Resolve **OI-6**: should a lvl1 dispatch failure abort lvl2 in `prService.js:164`?
      **Decided 2026-09-02 (owner):** keep the current abort behavior. **I-7 is not implemented.**
      `prService.js` stays untouched. OI-6 may be revisited separately.

Blocking gate: OI-2 and OI-6 change observable behavior. Do not start I-4 or I-7 until answered.
I-1, I-2, I-3, I-5 and all test tasks are safe to proceed without them.
**Gate cleared 2026-09-02** by the owner decisions recorded above: I-4 proceeds, I-7 is dropped
from this delivery.

## Implementation

Ordered by dependency. Each item is independently revertable.

- [x] **I-1 (D-1, FR-1) — applied, but fixes no behaviour.** D-1 was later proven not to be a
      defect (see `design.md`); the change is code hygiene only. `src/services/emailServices.js:735` — change
      `clause.item_code = { [Op.in]: [item_codes] }` to `{ [Op.in]: item_codes }`.
      Keep the surrounding `Array.isArray(item_codes)` guard so the clause is omitted when absent.
- [x] **I-2 (D-2, FR-2):** `src/services/emailServices.js:759` — add an empty-set guard before
      `getdata[0]` is read; return a structured `{ sent: false, reason: 'NO_ELIGIBLE_ITEMS' }`.
- [x] **I-3 (D-3, FR-3):** `src/services/emailServices.js:709` and `:774` — remove both
      `sendResponse(res, ...)` calls. Replace with a typed error or the structured outcome from
      I-2. Confirm `sendResponse` has no other unreferenced use in this function.
- [x] **I-4 (D-4, FR-4):** `src/services/emailServices.js:743-757` — move the
      `rfqLibrary.update` status mutation to after successful token creation and email dispatch.
      Apply the same reordering to `src/controllers/emailController.js:447-461` relative to `:570`.
- [x] **I-5 (D-5, FR-5, FR-6):** `src/services/emailServices.js:796-826` — replace the inline
      `jwt.sign` + `rfqTokenEmail.create()` with
      `EmailHelper.generateVendorQutationLink({...}, { saveTokenToDB: true })`.
      **Before switching, diff the two token payloads field by field** (`emailServices.js:788-795`
      vs `emailHelper.js:16-88`) and record any difference in `test-plan.md` under
      "Unverified behavior". Do not silently change the payload shape.
- [x] **I-6:** Audit all six `resendEmailVendors` call sites for the new return value —
      `emailController.js:535`, `prController.js:1856`, `qcfController.js:990`, `:995`, `:2237`,
      `prService.js:166`. All currently ignore it; confirm none breaks.
- [ ] **I-7 (design item 6, FR-7) — gated on OI-6:** `src/services/prService.js:164-175` —
      per-vendor failure containment in the `for await` loop. Skip if OI-6 is unresolved.
- [x] **I-8 (FR-7):** Add structured failure logging with `rfq_number`, `vendor_code`,
      `vendor_batch`, and cause. Never log the JWT or `jwtConfig.secret`.
- [ ] **API/OpenAPI/event contract:** N/A — no external contract changes (`design.md`,
      "Interface changes").
- [ ] **Data migration/backfill/rollback:** N/A for this change. Remediation of `RFQ0002052`
      (OI-3) and any duplicate active tokens (OI-5) are explicitly out of scope and require
      separate owner approval. **Do not mutate production data under this spec.**

## Tests

Write the failing regression tests **before** the corresponding fix. There is currently no test
covering `resendEmailVendors` at all — confirmed by grep across `tests/`.

- [x] **T-1 (AC-1):** New `tests/services/emailServices.resendEmailVendors.test.js` —
      with `item_codes` supplied, the correct rows are selected and exactly one active
      `rfq_token_email` row results. Must fail before I-1.
- [x] **T-2 (AC-2):** Without `item_codes`, the clause omits `item_code` and behavior is unchanged.
- [x] **T-3 (AC-3):** Empty eligible set returns the structured outcome; asserts no token write,
      no email send, no status mutation, and no `TypeError`. Must fail before I-2.
- [x] **T-4 (AC-4):** Missing/inactive SLA config produces a typed error naming the config key,
      not `ReferenceError`. Must fail before I-3.
- [x] **T-5 (AC-5):** Token creation or email dispatch throwing leaves no item at
      `RFQ_SENT_TO_VENDOR`. Must fail before I-4.
- [x] **T-6 (AC-6):** Second dispatch for the same scope updates rather than duplicates the token
      row. Must fail before I-5.
- [ ] **T-7 (AC-7):** `tokenMiddleware` + `prController.listItemRFQVendor` accept a token produced
      by the fixed path and return the scoped items.
- [x] **T-8 (AC-8):** Existing `tests/services/prService.vendorExpiryGuard.test.js` (4 tests)
      still passes unchanged (the file actually contains 8 tests, not 4 — earlier count was a documentation slip).
- [x] Complete the acceptance-criteria mapping table in `test-plan.md`.

Use synthetic RFQ/vendor identifiers in fixtures. Never copy `RFQ0002052`, `8100020736`, real
vendor codes, or real email addresses into test data.

## Verification and handoff

- [x] Run `npx jest tests/services/emailServices.resendEmailVendors.test.js` — **7/7 passed** (2026-09-02).
- [x] Run `npx jest tests/services/prService.vendorExpiryGuard.test.js` — **8/8 passed**, unmodified (2026-09-02).
- [x] Run the full `npm test` in `aigen-backend` — **285 passed, 11 failed, 296 total**. The 11
      failures were proven pre-existing by re-running those two suites at pristine HEAD
      (identical 11 failures). No new regression.
- [x] Frontend: N/A — no change. `aigen-frontend` working tree untouched and clean.
- [x] Import worker: N/A — no change. `aigen-import-pr` working tree untouched and clean.
- [x] ~~Confirm the email-burst risk before deploy~~ — **VOID 2026-09-02.** The risk assumed D-1
      had been suppressing dispatches. It never did (see `design.md`), so there is no backlog and
      no burst. This is no longer a release gate.
- [x] Check whether any dashboard query depends on `RFQ_SENT_TO_VENDOR` ordering
      (`src/helper/dashboardHelper.js`) before shipping I-4 — **verdict: safe to reorder.**
      Every reference is `status_milestone IN (...)` list membership, never an ordering or
      timestamp comparison against `rfq_token_email`; all token joins are LEFT JOINs that already
      treat a missing token row as "not expired". Residual caveat: if the status update itself
      fails after a successful send, the dashboard undercounts "sent" — cosmetic, and strictly
      safer than the original bug.
- [ ] Update `aigen-ai/index/` and project state.
- [x] Review final diffs for unrelated changes and secrets — `git diff --check` clean; only the 2 modified files + 1 new test file; no secrets; `prService.js` confirmed untouched.
- [x] Record unverified behavior, rollout order, and rollback in `test-plan.md` — see "Residual gaps" RG-1..RG-4.
- [x] Report which open items remain unresolved at handoff — **OI-1, OI-3, OI-4, OI-5 still open.**
      OI-2 and OI-6 were decided by the owner on 2026-09-02. New: RG-1..RG-4 in `test-plan.md`.
- [ ] Move this specification to `completed/` only after every acceptance criterion is met and
      OI-3 has an owner decision.
