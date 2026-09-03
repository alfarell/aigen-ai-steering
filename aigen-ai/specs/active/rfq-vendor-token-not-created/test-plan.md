# Test plan — RFQ vendor token not created on launch

Harness: Jest 29 (`aigen-backend/package.json`, `"test": "jest"`). Existing service tests under
`tests/services/` provide the mocking pattern to follow.

## Acceptance-criteria mapping

| Acceptance criterion | Test/verification | Level | Repository/file | Expected result | Status |
|---|---|---|---|---|---|
| AC-1 | T-1 dispatch with `item_codes` selects rows and writes one active token | Unit | `aigen-backend/tests/services/emailServices.resendEmailVendors.test.js` | Correct rows selected; exactly one active `rfq_token_email`; email carries that token | **Pass** |
| AC-2 | T-2 dispatch without `item_codes` | Unit | same file | `item_code` absent from clause; behavior unchanged | **Pass** |
| AC-3 | T-3 empty eligible set | Unit | same file | Structured outcome returned; no token, no email, no status mutation, no `TypeError` | **Pass** |
| AC-4 | T-4 missing/inactive SLA config | Unit | same file | Typed error naming `WAITING_VENDOR_EXPIRY`; **not** `ReferenceError: res is not defined` | **Pass** |
| AC-5 | T-5 token/email failure leaves status clean | Unit | same file | No item at `RFQ_SENT_TO_VENDOR` after the failed attempt | **Pass** (both paths; RG-1 fixed 2026-09-02) |
| AC-6 | T-6 repeat dispatch for same scope | Unit | same file | Existing token row updated, not duplicated | **Pass** |
| AC-7 | T-7 vendor opens detail with the produced token | API | `aigen-backend/tests/controllers/` (new or extended) | `tokenMiddleware` accepts; `listItemRFQVendor` returns scoped items | **Not implemented (T-7 deferred)** |
| AC-8 | T-8 existing expiry-guard regression | Unit | `aigen-backend/tests/services/prService.vendorExpiryGuard.test.js` | All 4 existing tests still pass, unmodified | **Pass** |

Every acceptance criterion appears at least once.

## Automated coverage

### Backend

- Test files:
  - New: `tests/services/emailServices.resendEmailVendors.test.js` (T-1..T-6)
  - New or extended: vendor token access test for T-7
  - Unmodified regression: `tests/services/prService.vendorExpiryGuard.test.js` (T-8)
- Mocks/fixtures: mock `getPRDetails`, `rfqLibrary.update`, `getConfigDetail`,
  `rfqTokenEmailStoreRepository`, `sendEmailRequestForQuotation`, and `jwt.sign`.
  Follow the mocking style already used in `prService.vendorExpiryGuard.test.js` and
  `prService.handleExpiredCSReview.test.js`.
  Fixtures use synthetic identifiers only — e.g. `RFQTEST0001`, `PRTEST0001`, vendor `V0001`,
  `vendor@example.test`. Never reproduce `RFQ0002052`, `8100020736`, real vendor codes, or real
  email addresses.
- Command: `npx jest tests/services/emailServices.resendEmailVendors.test.js`
- Full suite: `npm test`

### Frontend

- Test files/harness: **N/A.** No frontend change in this spec. The vendor route
  `/#/vendor/quotation/{token}` and its components are untouched.
- Command: N/A.

### Import worker

- Test files/harness: **N/A.** `aigen-import-pr` is not involved in RFQ token creation.
- Command: N/A.

## Contract and integration checks

- HTTP/OpenAPI: no route, payload, or status-code change. Confirm by diffing
  `src/routes/emailRoutes.js` and `src/routes/purchaseRoutes.js` — both must be unchanged.
- Internal contract: `resendEmailVendors` gains a structured return value where it previously
  returned `undefined`. Verify all six call sites still behave correctly (task I-6).
- Kafka/command: N/A.
- Database migration/rollback: none. `rfq_token_email` and `rfq_library` schemas are unchanged.
- Cross-repository compatibility: none required; backend-only deploy.

## Production diagnostic queries (read-only, owner approval required)

These confirm which defect produced the reported symptom (OI-4). **Run read-only, against a
replica where possible. Do not mutate. Do not paste results containing vendor emails into this
spec.**

Does the token row exist?

```sql
SELECT id, rfq_number, vendor_code, vendor_batch, date_expired, is_active, created_at
FROM rfq_token_email
WHERE rfq_number = 'RFQ0002052' AND user_type = 'vendor';
```

What state are the RFQ rows in?

```sql
SELECT id, rfq_number, pr_number, vendor_code, vendor_batch,
       status_vendor, status_milestone, server_groups
FROM rfq_library
WHERE rfq_number = 'RFQ0002052';
```

Interpretation:

| Observation | Indicated cause |
|---|---|
| No token row, `status_milestone = 1` | Dispatch never ran, or aborted before the status update. (Originally attributed to D-1 + D-2; the D-1 half is void — see the correction below.) |
| No token row, `status_milestone = 2` | Dispatch ran and mutated status but died before the token write — confirms D-4, cause likely D-3 via missing SLA config |
| Token row exists but `is_active = 0` or `date_expired` in the past | Not this bug; investigate revocation/expiry instead |
| Multiple active token rows | Confirms D-5 is already producing duplicates in production (OI-5) |

Is the SLA config present for this server group?

```sql
SELECT server_group, config_condition, config_value, is_active
FROM config_validation
WHERE server_group = :server_groups_from_query_above
  AND config_condition = 'WAITING_VENDOR_EXPIRY';
```

Fleet-wide detection of the same failure (scope of impact beyond `RFQ0002052`):

```sql
SELECT rl.rfq_number, rl.vendor_code, rl.vendor_batch, COUNT(*) AS items
FROM rfq_library rl
LEFT JOIN rfq_token_email rte
  ON rte.rfq_number = rl.rfq_number
 AND rte.vendor_code = rl.vendor_code
 AND rte.vendor_batch = rl.vendor_batch
 AND rte.user_type = 'vendor'
 AND rte.is_active = 1
WHERE rl.status_milestone = 2
  AND rte.id IS NULL
GROUP BY rl.rfq_number, rl.vendor_code, rl.vendor_batch;
```

Duplicate active tokens (OI-5):

```sql
SELECT rfq_number, vendor_code, vendor_batch, COUNT(*) AS active_tokens
FROM rfq_token_email
WHERE user_type = 'vendor' AND is_active = 1
GROUP BY rfq_number, vendor_code, vendor_batch
HAVING COUNT(*) > 1;
```

## Manual scenarios

| Scenario | Preconditions/test data | Steps | Expected result |
|---|---|---|---|
| Expiry escalation produces a working link | Non-production env; synthetic RFQ with 2 eligible items, vendor lvl1 + lvl2, active `WAITING_VENDOR_EXPIRY` config | Trigger the vendor-expiry path that calls `resendEmailVendors` with `item_codes` | Both vendors receive an email; one active token per vendor/batch; both links open the RFQ detail |
| CS manual resend still works | Same env, synthetic RFQ | `POST /cs/resend_rfq/:rfq_number/:vendor_batch` as an authenticated CS user | Token updated in place, not duplicated; link opens the detail |
| Missing SLA config is diagnosable | Same env; deactivate `WAITING_VENDOR_EXPIRY` for the test server group | Trigger dispatch | Typed error naming the config key in logs; RFQ **not** left at `RFQ_SENT_TO_VENDOR`; no email sent |
| ~~Email-burst check before deploy~~ | **VOID 2026-09-02** | The `item_code` clause matched the same rows before and after the fix, so no backlog of undispatched RFQs exists and no burst is possible. This scenario is retired. |

## Security and failure cases

- Unauthorized/forbidden role: CS resend route still requires `authenticateToken`
  (`purchaseRoutes.js:273`) — unchanged, verify not weakened.
- Missing/expired/revoked token: vendor opening a link whose row is inactive or past
  `date_expired` is rejected by `tokenMiddleware`.
- Invalid input: `item_codes` that is not an array of strings must not reach the `Op.in` clause.
- Dependency timeout/failure: email transport failure must not leave a status mutation behind (AC-5).
- Duplicate/retry/concurrent request: repeat dispatch converges to one active token (AC-6).
  Concurrent dispatch for the same scope is **not** made atomic by this change — recorded below.
- Partial database/integration failure: token written but email failed is the accepted safe
  direction; the RFQ can be resent. Email sent but token missing is the bug being fixed.
- Secrets: assert no test or log output contains the JWT value or `jwtConfig.secret`.

## Commands and results

| Command | Date | Result | Notes |
|---|---|---|---|
| `npm install` | 2026-09-02 | Pass (exit 0) | `node_modules` was absent; required before any test could run |
| `npx jest tests/services/emailServices.resendEmailVendors.test.js` | 2026-09-02 | **Pass — 7/7** | New file, T-1..T-6 (T-5 has two variants) |
| `npx jest tests/services/prService.vendorExpiryGuard.test.js` | 2026-09-02 | **Pass — 8/8** | Unmodified regression gate (AC-8) |
| `npx jest tests/repository/rfqLibrary.dicReminder.test.js tests/controllers/qcfController.dicReminder.test.js` at **pristine HEAD** | 2026-09-02 | **11 failed / 1 passed** | Baseline proof that these failures pre-date the change |
| `npm test` (post-change, round 1) | 2026-09-02 | **285 passed, 11 failed, 296 total** (27/29 suites) | The 11 failures are exactly the pre-existing ones above — no new regression |
| `npx jest tests/controllers/emailController.handleSendTemplateEmail.test.js` | 2026-09-02 | **Pass — 5/5** | RG-1 follow-up: opt-in strict-false contract + default-path regression |
| `npx jest tests/controllers/emailController.sendRequestForQuotation.test.js` | 2026-09-02 | **Pass — 3/3** | RG-1 follow-up: proves the actual status-update gating |
| `npx jest tests/controllers/emailController.resendFailedEmails.test.js` | 2026-09-02 | **Pass — 4/4** | RG-5: strict-false retry bookkeeping, MAX_RETRIES flip, undefined-still-success regression, throw path |
| `npx jest tests/helper/resendEmailVendorsResult.test.js` | 2026-09-02 | **Pass** | RG-3: classifier unit tests |
| `npx jest tests/controllers/qcfController.resendEmailVendorsOutcome.test.js` | 2026-09-02 | **Pass — 6/6** | RG-3: sent/skipped/failed/unknown classification + activity-log gating + sendLvl1andLvl2 `ok` |
| `npx jest tests/services/emailServices.sendEmailTransportPropagation.test.js` | 2026-09-02 | **Pass — 8/8** | RG-2: 4 of the 12 wrappers propagate true/false from the transport |
| `npm test` (post-change, final) | 2026-09-02 | **328 passed, 11 failed, 339 total** (36/38 suites) | +43 tests over the 296 baseline, all passing; the same 11 pre-existing failures throughout every round |

Baseline method: the two modified source files were copied aside, restored to `HEAD` with
`git checkout HEAD --`, the two failing suites re-run, then the modified files restored. This
proved pre-existence without stashing. The pre-existing failures are a `DIC_Email_Reminder_interval`
config-mock issue, a `mysql2`/`iconv-lite` `cesu8` encoding error, and a
`UserMatrix.belongsTo is not a function` association-wiring failure — none touch
`emailServices.js` or `emailController.js`.

Environment deviation: Node in use is `v24.20.0`; `.nvmrc` pins `v22.14.0`. Tests ran successfully
regardless, but the `cesu8` failure may be version-related. Re-run on the pinned version before
release.

## Residual gaps found during implementation (2026-09-02)

Surfaced by code review of the actual diff. **RG-1 was subsequently fixed** in a follow-up pass on
the same day; **RG-5**, **RG-3**, **RG-4** and **RG-2** were fixed in further passes. All five are
now resolved.

- **RG-1 (High) — RESOLVED 2026-09-02 (follow-up pass).** Originally: AC-5 was only cosmetically
  met in `emailController.js`.
  `handleSendTemplateEmail` (`src/controllers/emailController.js:58`) is invoked **without
  `await`** at `:606` and swallows its own errors internally, so it never rejects to the caller.
  The I-4 reorder therefore protects path A against SLA-lookup and token-creation failures, but
  **not** against the email dispatch step itself: an SMTP failure still leaves the item at
  `RFQ_SENT_TO_VENDOR`. Closing this requires changing `handleSendTemplateEmail`'s error contract,
  which affects all of its call sites — deliberately out of the approved scope at the time.

  **Fix applied.** `sendEmailRequestForQuotation` now returns the `sendEmail(...)` boolean it
  previously discarded. `handleSendTemplateEmail` gained an **opt-in** fifth parameter
  `{ failOnTransportFalse }`: when set, a strict `false` is treated as a failure (FailedEmail row
  + 500) and the helper returns `{ ok: false }`. `sendRequestForQuotation` awaits the helper and
  gates the `rfqLibrary.update` on `ok === true`; its outer catch is guarded with
  `res.headersSent` to prevent a double response.

  The flag is passed at **exactly one** call site (`emailController.js:642`, verified by grep).
  All other `handleSendTemplateEmail` call sites — including `resendRFQVendor` and
  `resendRFQVendorSpesific`, which share `sendEmailRequestForQuotation` — keep their original
  behavior. An earlier revision of this fix changed those two endpoints from 200 to 500 on SMTP
  failure; that was an unrequested behavior change to live authenticated endpoints and was
  withdrawn in favour of the opt-in flag, per `AGENTS.md` ("Preserve behaviour outside the
  requested scope").
- **RG-2 (Medium) — RESOLVED 2026-09-02. Real SMTP failures never reached the new failure path.**
  `sendEmail` (`src/services/emailServices.js:95-137`, pre-existing and unmodified) catches
  `transporter.sendMail` failures, records them in the `Email` table, and returns `false` rather
  than throwing. `resendEmailVendors` awaits it but does not inspect the return value, so a real
  transport failure still yields `{ sent: true }` and a status update. The new T-5 test therefore
  exercises a template-render failure instead, and says so inline. FR-7's failure signal did not
  cover the most likely production failure mode.

  **Fix applied, in two passes.** `sendEmail` itself is deliberately unchanged — it still swallows
  the transport error, records it in the `Email` table, and returns `false` rather than throwing.
  What changed is that the signal is no longer discarded by its wrappers.

  Pass 1 (with RG-1) propagated it from `sendEmailRequestForQuotation` and consumed it in
  `resendEmailVendors` (returns `{ sent: false, reason: 'EMAIL_DISPATCH_FAILED' }` and skips the
  status update) and in `sendRequestForQuotation` (gates the status update via the opt-in flag).

  Pass 2 propagated it from the remaining **12** wrapper functions, each changed from a bare
  `await sendEmail(...)` to `return sendEmail(...)`:
  `sendEmailApprovalQuotationSummary`, `sendEmailBidPriceExceedsOe`, `sendEmailNeedDicConfirmation`,
  `sendEmailNeedManagementApproval`, `sendEmailPendingDicConfirmation`,
  `sendEmailPrRevisedProceedToQcf`, `sendEmailQuotationDeclined`,
  `sendEmailQuotationNotYetSubmitted`, `sendEmailQuotationStatusUpdate`, `sendEmailReceived`,
  `sendEmailRequestForPrRevision`, `sendEmailRequestForRevision`.
  No wrapper now discards the boolean. (`sendEmailGemsQcfApprovedManualPo` and
  `sendEmailGemsManualPoAlert` already returned it.)

  Caller safety was verified before editing: none of the 12 has a caller that inspects its result
  — every invocation is a bare `await` statement, a function reference handed to
  `handleSendTemplateEmail` / `emailTypeToServiceFunction`, or a deferred `emailTasks` closure
  whose resolved value is discarded. The single pre-existing return-value consumer in the
  repository (`qcfController.js:1529`) consumes `sendEmailGemsQcfApprovedManualPo`, which was
  already returning a boolean and is unchanged.

  **Consequential behavior change, intended:** `resendFailedEmails`'s strict `sent === false`
  check is unconditional, so RG-5's fix now applies to **all** registry email types rather than
  only `Request for Quotation`. A retry that still fails at the transport level increments
  `retry_count` and stays `pending_retry` instead of being wrongly marked `success`. Still bounded
  by `MAX_RETRIES = 5`.

  **Deliberately NOT changed:** the `failOnTransportFalse` default stays `false`. Now that every
  wrapper propagates, flipping it would turn a silent 200 into a 500 on ~11 routes at once. That
  is a separate owner decision, newly unlocked by this work — see the note below.

  **Known remaining limitation.** Five wrappers dispatched through `prController`'s deferred
  `emailTasks` mechanism (`sendEmailQuotationDeclined`, `sendEmailApprovalQuotationSummary`,
  `sendEmailNeedManagementApproval`, `sendEmailBidPriceExceedsOe`, `sendEmailRequestForRevision`)
  resolve a bare boolean, and that drain's guard tests `result.value?.sent === false` — which is
  `undefined === false` for a primitive, so it never matches. Their transport failures are still
  discarded at that drain, exactly as before. RG-2's scope was to stop the wrappers swallowing the
  signal, not to make every consumer inspect it; surfacing these is a separate follow-up.
- **RG-3 (Medium) — RESOLVED 2026-09-02. The structured return was not consumed anywhere.**
  Originally: all five non-`prService` call sites ignored the return value, so
  `{ sent: false, reason: 'NO_ELIGIBLE_ITEMS' }` was indistinguishable from success. In particular
  `qcfController` recorded `status: 'sent'` — and wrote "RFQ Launched - Email Sent" activity
  logs — for a vendor that was a no-op.

  **Fix applied.** A shared classifier `classifyResendEmailVendorsResult` in
  `src/helper/resendEmailVendorsResult.js` maps a result to `sent` / `skipped` / `failed` /
  `unknown`. `NO_ELIGIBLE_ITEMS` is **skipped** (a benign no-op — never an error, never
  Sentry-captured); `EMAIL_DISPATCH_FAILED` and `MISSING_RFQ_NUMBER` are **failed**. Anything
  else, notably `undefined`, is `unknown` and preserves prior behavior exactly — this matters
  because ~10 other email functions still resolve `undefined`.

  Consumed at the five non-`prService` call sites:
  - `qcfController` reminder loop — pushes `sent`/`skipped`/`failed` with the reason, and the two
    `addLogQuotationByDataItems` calls are now gated on an actual send, closing the
    data-integrity problem of logging "Email Sent" for an email that never went out.
  - `qcfController.sendLvl1andLvl2` — adds an additive `results` field; `ok` is false only on a
    genuine failure and the HTTP status stays 200. No frontend consumer exists (its route in
    `emailRoutes.js:27` is commented out), verified by search.
  - `emailController` vendorLvl2 aggregator site — observability only; no HTTP response change,
    the vendorLvl1 flow is not aborted.
  - `prController` `Promise.allSettled` drain — strict `result.value?.sent === false` check, so
    the ~6 sibling tasks resolving `undefined` are untouched. The second drain in that file has
    no `resendEmailVendors` task and was left alone.

  The sixth caller, `prService.js:166`, is deliberately excluded — `prService.js` stays untouched
  under the OI-6 decision.

  Test-coverage note: the `prController` drain branch has **no direct automated test**. Its
  enclosing `bulkUpdateRfqStatusVendor` is a ~1150-line function requiring JWT verification, a
  full transaction lifecycle and deep conditional setup, with no existing `prController` test
  file to use as a template. A harness was judged disproportionate and skipped rather than faked.
  The classifier it relies on is unit-tested directly and exercised identically at two other,
  tested call sites.
- **RG-4 (Low) — RESOLVED 2026-09-02. Mislabeled catch logs.**
  `resendEmailVendors` logged `'Error in sendRequestForQuotation:'` in its catch, naming the wrong
  function, directly beside a correctly labelled structured log. The two were merged into one
  `console.error('resendEmailVendors failed', { rfq_number, vendor_code, vendor_batch, cause }, error)`
  — the redundant line is gone and the error object is retained so the stack survives.

  A search for the same defect found a second instance: `resendRFQVendor`
  (`src/controllers/emailController.js:1175`) carried the same wrong label and now reads
  `'Error in resendRFQVendor:'`. Two other occurrences were checked and left alone because they
  are already correct — `emailController.js:701` really is inside `sendRequestForQuotation`, and
  `resendRFQVendorSpesific` (`:1413`) was already labelled correctly.

  Logging-only change; no control flow, no behavior, no test impact.

- **RG-5 (Medium, pre-existing) — RESOLVED 2026-09-02. The retry loop treated a failed send as success.**
  `resendFailedEmails` (`src/controllers/emailController.js`, around `:1504`) does
  `await emailServiceFunction(...)` then unconditionally marks the row `success`, inspecting only
  thrown exceptions. Because `sendEmail` resolves `false` rather than throwing, a retry that still
  fails at the transport level is marked succeeded and never retried again. This predates the
  change, and the RG-1 fix makes `FailedEmail` rows for `Request for Quotation` more common, so
  this sink was being exercised more often.

  **Fix applied.** The retry loop now captures the service function's result; a strict `false`
  is routed through the same failure bookkeeping as a thrown error via a shared local
  `markRetryFailed(errorMessage)` helper — `retry_count` is incremented, `last_error` recorded,
  and `status` flipped to `failed` once `retry_count >= MAX_RETRIES` — and the row is no longer
  marked `success`. Strict `=== false` again preserves behavior for the other 10 registry
  functions, which resolve `undefined`.

  Retry remains bounded: `MAX_RETRIES` is 5, the selecting query requires
  `status = 'pending_retry'` and `retry_count < MAX_RETRIES`, and both failure paths increment,
  so a permanently failing row stops being selected. No infinite-retry path exists.

  Note (accepted, not fixed): if `email.save()` itself throws inside the new `false` branch, the
  inner `catch` runs `markRetryFailed` a second time. Nothing is persisted in that case — the
  second save fails too and propagates to the outer handler — so there is no data corruption,
  only a redundant in-memory increment.

**All five residual gaps (RG-1 through RG-5) are resolved**, and both follow-ups that were left
open after RG-2 were completed on 2026-09-02:

1. **`failOnTransportFalse` default flipped to `true`.** Every template-email route now reports a
   transport failure honestly (`FailedEmail` row + 500) instead of returning 200. The parameter is
   kept so a route can still opt out with `{ failOnTransportFalse: false }`; the now-redundant
   explicit `true` at the RFQ dispatch site was removed. Of the 13 call sites, only six are
   actually reachable — the routes for `sendApprovalQuotationSummary`, `sendBidPriceExceedsOe`,
   `sendNeedDicConfirmation`, `sendPendingDicConfirmation`, `sendQuotationDeclined`,
   `sendQuotationStatusUpdate` and `sendRequestForPrRevision` are commented out in
   `emailRoutes.js`, so the flip is inert for them.
2. **Both `prController` `emailTasks` drains** now surface a bare-boolean `false` from a wrapper,
   alongside the existing structured `{ sent: false }` branch. The two branches are mutually
   exclusive (`false?.sent` is `undefined`), and `true`/`undefined` produce no log noise. The
   second drain correctly received only the bare-boolean branch, since it dispatches no
   `resendEmailVendors` task.

Registry check performed at the same time: all 11 `emailTypeToServiceFunction` keys exactly match
the `emailName` strings passed at every `handleSendTemplateEmail` call site, so no `FailedEmail`
row can be stranded as permanently `failed` by a missing registry key.

## RG-6 (High, PRE-EXISTING) — RESOLVED 2026-09-02. State was mutated before dispatch on three routes

Surfaced by the code review of the default flip. **This is a pre-existing defect, not one this
work introduced** — verified against `HEAD`, where `resendRFQVendor` already performed its
`rfqLibrary.update`, then deactivated every existing active token (`is_active: false`), then
created a fresh active token, and only afterwards called `handleSendTemplateEmail`. Our diff does
not touch that ordering.

Affected: `resendRFQVendor` and `resendRFQVendorSpesific` (`src/controllers/emailController.js`),
and to a lesser degree `sendPrRevisedProceedToQcf`, which commits `status_milestone: 15` before an
un-awaited, un-gated send.

The consequence, both before and after the flip: on an SMTP failure the RFQ is left marked as sent
with the vendor's SLA clock started, the previous link already revoked, and the new link never
delivered — stranding a vendor who held the old link.

What the flip changed is **only the reporting**, and it changed it for the better: that failure
used to return 200 with no record, and now returns 500 and writes a retryable `FailedEmail` row.
The code review characterised the flip as "reactivating" this mismatch; that overstates it — the
data state is identical either way, and the failure is now visible instead of silent.

**Fix applied.** All three routes now `await handleSendTemplateEmail(...)`, capture its `{ ok }`,
and run their status mutation only when `ok === true`:
`resendRFQVendor` gates the `rfqLibrary.update` writing `RFQ_SENT_TO_VENDOR`;
`resendRFQVendorSpesific` gates the same update writing `RESEND_RFQ` (the two milestone constants
were verified not to have been conflated); `sendPrRevisedProceedToQcf` gates
`bulkUpdateStatusOE(RFQ_TYPE.REVISI_OE, oeItems)`. Outer catches that call `sendResponse` are
guarded with `res.headersSent`; `sendPrRevisedProceedToQcf`'s catch only logs and captures, so it
needs none.

**Token handling was deliberately NOT moved.** The new token must be created before the send
because the email body embeds its link, and on failure it must stay active so the `FailedEmail`
retry — whose stored params carry that same link — can still deliver it. This is also required by
`getRFQTokenEmailDetail` (`src/repository/rfqTokenEmail.query.repository.js:9-36`), which does a
`findOne` on `(rfq_number, vendor_batch, is_active: true, …)` ordered by `updated_at DESC`: it
assumes a single canonical active row, so the existing deactivate-then-create ordering had to stay
intact. `tokenMiddleware` looks up by the literal token string and does not rely on that
assumption.

`oeItems` was hoisted to function scope so it survives past its original `if` block; the deferred
call is guarded by `if (oeItems)`, so the branch where the `if` never ran behaves exactly as
before. `bulkUpdateStatusOE` opens, commits and rolls back its own transaction entirely within the
awaited call (`src/repository/qcfLibrary.repository.js:2766-2799`), so deferring it leaves no
dangling transaction and cannot double-commit.

Success-path state is unchanged — same fields, same values, same where-clauses. The only
difference is that a failed send no longer advances status.

Covered by three new test files (`emailController.resendRFQVendor.test.js`,
`.resendRFQVendorSpesific.test.js`, `.sendPrRevisedProceedToQcf.test.js`, 6 tests): a failed send
leaves the token rotated but the status untouched with exactly one response sent; a successful send
performs the mutation with the exact pre-existing arguments.

**Accepted residual (inherited from the `sendRequestForQuotation` pattern, not new here):**
`handleSendTemplateEmail` sends the success response *before* the caller performs the status
mutation. If that mutation then throws, the client has already received a success response and the
outer catch cannot report it — the write is lost silently. Closing this would require restructuring
the response handling across all four routes and is out of scope.

While fixing this, one further mislabeled catch log was found and corrected in the same class as
RG-4: `sendPrRevisedProceedToQcf` logged `'Error in sendRequestForPrRevision:'`; it now names its
own function.

## Local replication against a production copy (2026-09-02)

Run against a local duplicate of the production `aigen` / `prpo` / `task_board` schemas.
`NODE_ENV=development`, mail transport is Mailtrap, `DB_HOST` is localhost — verified before any
code was run. `RFQ0002052` itself was never modified; a synthetic copy `RFQTEST9052` was used.

**Symptom reproduced.** `RFQ0002052` has one `rfq_library` row (item `10`, vendor `106412`, batch 1,
GEMS) at `status_milestone = 2`, `status_vendor = null`, and **zero** `rfq_token_email` rows.

**~~D-1 is NOT the cause of this particular RFQ~~ — this correction was itself WRONG. Superseded
2026-09-02.** It claimed the nested array was harmless only for single-item RFQs because MySQL
flattens `IN (('10'))`, and estimated a 31% impact across 1,042 multi-item scopes. Both claims are
false. **D-1 is not a defect at any cardinality.** Re-tested on scopes of 1, 2 and 3 item codes,
the old and fixed clause shapes return the same rows, and capturing the generated SQL shows why —
Sequelize normalises the nested array before the statement is built:

```
OLD (nested)  ... item_code IN ('10', '20', '30');
NEW (flat)    ... item_code IN ('10', '20', '30');
```

The flattening is in Sequelize, not MySQL, and there is no cardinality at which the two differ.
The estimated 31% impact is withdrawn entirely: the real impact is zero. See the correction banner
in `design.md`.

**The SLA-config hypothesis is also ruled out**: `Waiting_vendor_expiry = 3` exists and is active
for GEMS.

**What the data does say.** Every dispatch path writes `status_vendor: PENDING` in the same update
as `status_milestone: 2`, and `addRFQTables` creates rows at milestone 1. The observed combination
— milestone 2 with `status_vendor` still `null`, and `createdAt` equal to `updatedAt` — cannot be
produced by any current dispatch path. The dispatch most likely never ran for this RFQ and the
milestone was advanced by something else (direct SQL, or a path changed since 2026-08-27).
**This remains unexplained and is the open question for OI-4.**

**Fleet-wide, in the same copy:** 12 scopes sit at milestone 2 with no active vendor token, and
**199 scopes have more than one active vendor token** — independent confirmation that D-5
(the unconditional `rfqTokenEmail.create`) was causing real, widespread duplication.

### End-to-end test on the synthetic copy

`resendEmailVendors({ rfq_number: 'RFQTEST9052', vendor_code: '106412', vendor_batch: 1, item_codes: ['10'] })`
was run twice against the fixed code.

| Check | Result |
|---|---|
| Token created | Yes — one `rfq_token_email` row, `is_active = 1`, `config_condition = Waiting_vendor_expiry`, `rfq_item_ids = [5898]` |
| Expiry derivation | `date_expired = 2026-09-06`, i.e. 3 business days, matching the config value |
| Two dispatches → duplicates? | **No.** Still exactly one row, updated in place (`created_at` 10:19:05, `updated_at` 10:19:07). AC-6 / FR-6 confirmed against real data |
| JWT valid | Verifies against the configured secret; payload carries `rfq_number`, `vendor_code`, `items` |
| `tokenMiddleware.decodeTokenFromParams` | Passed |
| `prController.listItemRFQVendor` | HTTP 200, scoped items returned — the vendor can open the detail |
| `RFQ0002052` | Unchanged: still milestone 2, still zero token rows |

**Unplanned but valuable:** the local SMTP transport failed (two `emails` rows with `status = 0`),
so `sendEmail` returned `false`. The RFQ correctly **stayed at milestone 1 with `status_vendor`
null** — a live demonstration of the RG-1/RG-2 gating. Under the pre-fix code the status would
have been advanced to `RFQ_SENT_TO_VENDOR` before the send was even attempted, producing exactly
the reported "marked as sent, no working link" state.

**Not yet observed:** because the transport failed, the success path end-to-end (status advancing
to 2 plus a delivered message) was not exercised. Re-run once Mailtrap credentials work from the
test machine.

**Environment note:** `SENTRY_DSN` is empty in `.env` and the Joi schema rejects an empty string,
so `npm run dev` cannot boot as configured. The diagnostics bypassed validation via `NODE_ENV=test`.

## Unverified behavior

Everything below is unverified at spec time and must be resolved or restated at handoff.

- **OI-1** — no automatic caller of path A was found; whether launch is *supposed* to auto-dispatch
  is unconfirmed. If it is, a separate defect exists that this spec does not address.
- **OI-2** — intended behavior when the SLA config is missing/inactive (block versus default).
- **OI-3** — remediation for `RFQ0002052` itself. No production data mutation is authorized here.
- **OI-4** — whether `RFQ0002052` failed via path A or path B; requires the queries above.
- **OI-5** — whether duplicate active tokens already exist in production.
- **OI-6** — whether a lvl1 dispatch failure should abort lvl2 in `prService.js:164`.
- Token payload equivalence between the inline path-B implementation (`emailServices.js:788-795`)
  and `generateVendorQutationLink` (`emailHelper.js:16-88`) is **not yet diffed**. Task I-5
  requires this before switching; any difference must be recorded here.
- Concurrent dispatch for the same scope remains non-atomic (check-then-update-or-create).
  Accepted at current volume; not covered by any test.
- No production log or Sentry evidence for `RFQ0002052` was available during investigation.
  The failure chain in `design.md` is derived from code reading, not from an observed stack trace.

## Second implementation: the `production` branch (2026-09-02)

The first implementation targeted `develop-dot`. It was ported to `production` as commit
`c7a64994` and then removed by the owner, because the two codebases diverge materially and the
port dragged in a `require('../const/isourcing-transfer')` for a file the revert `133a4fd6` had
deleted on `production` — the app failed to boot with `MODULE_NOT_FOUND`.

The fix was therefore re-implemented from scratch against `production`, on branch
`fix/rfq-vendor-token-production` (from `production` @ `a978fdbb`). It is a separate
implementation, not a cherry-pick.

**What differs on `production`:**
- `resendEmailVendors` carries the same D-2..D-5 defects at different lines (`emailServices.js:668`).
  D-1 is present too but is **not a defect** — see the correction in `design.md`; the change made
  for it on this branch is code hygiene only.
- **13** wrapper functions discard `sendEmail`'s boolean, not 12 — no wrapper already returned it.
- Seven of the routes that flow through `handleSendTemplateEmail` are commented out in
  `emailRoutes.js`; six are live. That sizing is why the `failOnTransportFalse` default stays
  `false` here.
- `src/const/isourcing-transfer.js` does not exist on this branch and `prService.js` does not
  require it, so the branch boots.

**Scope delivered:** D-1 (hygiene only, no behavioural effect) and D-2..D-5; the boolean propagated out of all 13 wrappers; an opt-in
`failOnTransportFalse` on `handleSendTemplateEmail` defaulting to `false`; status mutations gated
on dispatch success in `sendRequestForQuotation`, `resendRFQVendor`, `resendRFQVendorSpesific` and
`sendPrRevisedProceedToQcf`, all four opting in to the flag; `res.headersSent` guards; strict
`false` handled in `resendFailedEmails`; the structured outcome consumed at the five non-`prService`
call sites with the activity logs gated on a real send.

**Deliberately NOT done here:** the `failOnTransportFalse` default is NOT flipped, so the other
non-gated routes keep their existing HTTP contract.

**Behaviour change to note before release:** the four gated routes now respond 500 (and write a
`FailedEmail` row) when the transport reports failure, where they previously returned 200. Three of
them — `resendRFQVendor`, `resendRFQVendorSpesific`, `sendPrRevisedProceedToQcf` — are live routes.

**Two defects caught in review and fixed:**
1. The gate was initially a no-op at three of the four sites: `sendEmail` never throws, so without
   the opt-in flag `ok` was always `true` on a silent SMTP failure. All four now opt in.
2. Making `resendEmailVendors` non-throwing introduced a regression in `prService.js`: the skip and
   failure paths used to throw and abort before the logging block, so `addLogQuotationByDataItems`
   now ran unconditionally and wrote false "RFQ Launched - Email Sent" entries. Those two calls are
   now gated on a `sent` or `unknown` classification. This is the only change made to
   `prService.js`; its abort-on-throw loop behaviour is unchanged.

Three failure tests were also rewritten: they simulated `mockRejectedValue`, a path production
cannot take, and now use `mockResolvedValue(false)` — the real failure mode — with the thrown-error
case kept alongside.

**Validation on this branch:** baseline before the change was 148 passed / 20 failed / 168 total.
After: **199 passed, 20 failed, 219 total** — the same 20 pre-existing failures in
`tests/repository/rfqLibrary.dicReminder.test.js` and `tests/controllers/qcfController.dicReminder.test.js`.
51 tests added across 11 new files. `git diff --check` clean.

## D-7 — premature link invalidation on resend (found and fixed 2026-09-02)

Raised by an independent analysis in another session and confirmed here.

`EmailHelper.generateVendorQutationLink` always signed a fresh JWT and, when an active row already
existed, `updateToken` **overwrote `rfq_token` in place**. The link already emailed to the vendor
then matched no row, and `tokenMiddleware` (`src/middleware/tokenMiddleware.js:25`) answered 401
`Token not found in database.` — precisely "the vendor cannot open the RFQ detail from the link
that was sent". The function has always accepted an `old_token` parameter for exactly this, and no
caller ever passed it.

**This work made it worse before it made it better.** Converging path B onto the shared helper
(the D-5 fix) replaced `rfqTokenEmail.create()` — which left the previous row active until its own
`date_expired`, so the older emailed link kept working — with an in-place overwrite that kills the
older link immediately. The dedupe was still right for the expiry pipeline, but it traded a
harmless overlap for an immediate invalidation on the very symptom this spec exists to fix.

**Fix applied** in `src/helper/emailHelper.js`. The two cases separate cleanly on the existing
row's expiry:

| Existing row | Behaviour |
|---|---|
| Unexpired **and** same item scope | Reuse the stored token. `rfq_token` and `date_expired` are left untouched, so the emailed link keeps working |
| Expired | Issue a new token — the old link was already dead, so rotation costs nothing |
| Item scope changed | Issue a new token |
| `old_token` supplied explicitly | Honoured, unchanged |
| No row | Create, unchanged |

Exactly one active row is preserved in every branch, so the expiry-cron work-item semantics that
D-5 protects are unaffected.

Two constraints shaped this and must not be undone:

- `date_expired` is deliberately **not** extended when the token is reused. A JWT's `exp` cannot be
  extended without re-signing, and a row claiming validity past its own JWT's `exp` would produce a
  confusing `Token has expired` 401.
- Reuse requires an unchanged item set because `prController.listItemRFQVendor` scopes its query by
  the `items` array carried **inside** the JWT (`params.id = { [Op.in]: items }`). Reusing a token
  whose scope has changed would show the vendor the wrong items.

Covered by `tests/helper/emailHelper.generateVendorQutationLink.test.js` (7 tests), including a
defensive case for `rfq_item_ids` arriving as a JSON string and an assertion that no token value is
logged. Suite after the fix: **206 passed, 20 failed, 226 total** — the same 20 pre-existing
`dicReminder` failures.

Scope note: only `generateVendorQutationLink` was changed. The sibling `generate*Link` helpers
(DIC, OE revision, not-submitted) share the same rotate-in-place shape and were left alone.

## How a PR reaches iSourcing, and the token's role

Investigated because the business goal moved to getting `RFQ0002052` transferred into the
`task_board` schema.

**The path.** `POST /pr/cs/send_isourcing/:rfq_number/:vendor_batch`
(`src/routes/purchaseRoutes.js:198`), behind `authenticateToken` plus roles CS/CL/ADMIN, reaching
`qcfController.sendActionToCS`. `rfq_tipe` is read from the **request body**, not from a column, so
an RFQ does not need `tipe_rfq` preset. When it is `isourcing`, the handler calls
`prosesToIsourcing(pr_number, server_groups, itemsToUpdate)` (`qcfController.js:1103`), which writes
the `task_board` schema. On success, in one transaction, `bulkUpdateStatusRFQ` moves the items to
`status_milestone = 12` (ISOURCING) and `rfqTokenStoreRepository.deactivateTokens` closes the vendor
token. 1,225 RFQs / 3,398 items already sit at milestone 12, so the path works.

**The token's role — it is not an input.** The transfer never reads the token value; the only
`rfq_token` references in `qcfController.js` belong to DIC tokens. The vendor token is a *pipeline
marker*: active means the RFQ is still with the vendor (awaiting a quotation, or awaiting expiry
escalation); deactivating it on a successful transfer takes the RFQ out of that flow. This is why
the D-7 rotation fix is safe for iSourcing — changing the token string cannot break a transfer
lookup, because no such lookup exists.

**What `RFQ0002052` is missing.** `tipe_rfq` null, `sourcing_reason`/`sourcing_notes` null,
`status_milestone = 2`, and no `qcf_library` row for item `5713`. The absent vendor token is **not**
a blocker — the transfer does not require one. What it needs is the CS action above with
`rfq_tipe: 'isourcing'` and `items: [5713]`.

**Unverified, and the one thing that could block it:** `qcfWorkflowPolicy.canManualSource` is
evaluated against the `qcf_library` rows for the submitted items, and item `5713` has none. Whether
an empty set is permitted or rejected was not traced. Check this before attempting the transfer.
