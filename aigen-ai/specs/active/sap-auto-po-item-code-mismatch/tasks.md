# Tasks — SAP Auto-PO: item_code format mismatch and missing request-payload persistence

All work is in `aigen-backend`. No frontend, mobile, or `aigen-import-pr` change
is required — see `requirements.md` Scope for why.

## Discovery

- [x] Verify current behavior and reproduction evidence. Call chain traced from
      `qcfController.approveByCL` (`aigen-backend/src/controllers/qcfController.js:1432`)
      through `syncAutoPO` (`aigen-backend/src/repository/rfqLibrary.repository.js:1772`)
      to the `qcf_library` update and the milestone-17 rollback (`:1515-1525`).
- [x] Confirm requirements, actors, rules, and unknowns. See `requirements.md`.
- [ ] Check Git status in `aigen-backend` and preserve any pre-existing work
      before starting.
- [x] Identify interfaces, data, security, jobs, and integrations. Two SAP call
      sites confirmed: `syncAutoPO` and `getSyncSAP`
      (`aigen-backend/src/repository/PurchaseRequest.repository.js:2094`). No API
      contract change. The Basic-auth token is header-only
      (`rfqLibrary.repository.js:1873-1876`).
- [x] Confirm `SAP_ERROR_REASON_CODE` and `SAP_ERROR_USER_MESSAGE` already
      contain `SAP_ALL_ITEMS_ALREADY_ORDERED` and
      `SAP_PARTIAL_ITEMS_ALREADY_ORDERED`
      (`aigen-backend/src/const/sap-error-code.js`) — no constant changes needed.
- [ ] Confirm with the SAP team the actual `PR_ITEM` format in a success
      response. Does not block implementation — the fix is format-tolerant by
      design — but it closes the largest unknown.

## Implementation

Execute in this order; each step lists what it depends on.

- [ ] **Backend 1 — normalization helper.** Create
      `aigen-backend/src/helper/itemCode.js` exporting `normalizeItemCode(value)`
      and `itemCodesMatch(a, b)`. Strip leading zeros from purely numeric
      strings; trim and strictly compare anything else. Must tolerate `null`,
      `undefined`, and numbers without throwing. Depends on: nothing.
      Covers FR-1, FR-2.
- [ ] **Backend 2 — classifier keying.** In
      `aigen-backend/src/helper/sapFailureClassifier.js:19-21`, change `toKey` to
      normalize `item_code` before building the key. Do not change
      `parseOrderedInFullLines`, `compareOrderedInFullScope`,
      `classifySapFailure`, or the module exports. Depends on: Backend 1.
      Covers FR-7.
- [ ] **Backend 3 — migration.** Run
      `npm run migrate:create -- --db=aigen --name=create-log-sap-sync` and fill
      in the up/down SQL for `log_sap_sync` per the Data design table in
      `design.md`, following the raw-SQL convention of
      `aigen-backend/migrations/aigen/20260823202433-create-isourcing-transfer-requests.{up,down}.sql`.
      Index `qcf_number` and `created_at`. Depends on: nothing.
- [ ] **Backend 4 — model.** Create
      `aigen-backend/src/models/default/logSapSync.js` with
      `tableName: 'log_sap_sync'` and `timestamps: false`, following
      `aigen-backend/src/models/default/logSap.js`. Depends on: Backend 3.
- [ ] **Backend 5 — log repository.** Create
      `aigen-backend/src/repository/sapSyncLog.repository.js` exporting
      `logSapSyncAttempt({ qcf_number, pr_number, source, requestPayload,
      responsePayload, httpStatus, success, errorMessage })`. Guard the insert so
      a logging failure is reported via `console.error` and never propagates to
      the caller. Style it after `logActivity` in
      `aigen-backend/src/helper/log.js:47`. Depends on: Backend 4.
      Covers FR-5.
- [ ] **Backend 6 — `syncAutoPO` matching and reporting.** In
      `aigen-backend/src/repository/rfqLibrary.repository.js:1772`:
      build a lookup map from the already-fetched `getdata` rows keyed by
      `pr_number` plus `normalizeItemCode(item_code)`; in the success branch
      (`:1885-1906`) resolve each `dt` through that map and change the update
      `where` from `{ qcf_number, pr_number, item_code, [Op.or]: [...] }` to
      `{ qcf_number, id: matchedRow.id, [Op.or]: [...] }`; capture
      `const [affectedCount] = await qcfLibrary.update(...)`; on a lookup miss or
      `affectedCount === 0`, emit `console.error` and a `logActivity` entry naming
      `qcf_number`, `dt.PR_NUMBER`, `dt.PR_ITEM`, and `dt.PO_NUMBER`, and continue
      without throwing. Do not change the outbound payload or the SELECT.
      Depends on: Backend 1. Covers FR-3, FR-4.
- [ ] **Backend 7 — `syncAutoPO` payload persistence.** Call
      `logSapSyncAttempt` with `source: 'cl_approval_sync'` at three points:
      after a success response (`~:1880-1907`), after a non-success response
      (`~:1946-1965`), and in the `catch` block (`~:1994-2019`). In the catch, use
      `error.response?.status` and `error.response?.data ?? error.message` so a
      transport error with no response body still produces a usable row. Store the
      request body only — never headers. Depends on: Backend 5.
      Covers FR-5, FR-6, FR-8.
- [ ] **Backend 8 — `getSyncSAP` payload persistence.** Call
      `logSapSyncAttempt` with `source: 'cron_sync'` at the three equivalent
      points in `aigen-backend/src/repository/PurchaseRequest.repository.js:2094`
      (success `~:2205-2226`, failure `~:2281-2296`, catch `~:2307-2334`).
      **Do not** change this function's update matching — that is a separate
      defect, explicitly out of scope. Depends on: Backend 5.
      Covers FR-6.
- [ ] Frontend: N/A — no UI, route, or contract change. The more specific failure
      message is already present in `aigen-backend/src/const/sap-error-code.js`
      and reaches the client through existing response fields.
- [ ] Import worker: N/A — `item_code` ingestion
      (`aigen-import-pr/services/aigen.js:194`) is intentionally unchanged; the
      stored format stays unpadded per BR-4.
- [ ] API/OpenAPI/event contract: N/A — no interface change.
- [ ] Data migration/backfill/rollback: covered by Backend 3. No backfill; the
      defect was in comparison logic, not in stored data.
- [ ] Observability/security: covered by Backend 5, 6, 7, 8. Confirm by test that
      no persisted payload contains the Basic-auth token.

## Tests

- [ ] Create `aigen-backend/tests/helper/itemCode.test.js` covering the
      padded/unpadded equivalence, the non-numeric fallback, and `null`,
      `undefined`, and numeric inputs. Covers AC-8.
- [ ] Extend `aigen-backend/tests/helper/sapFailureClassifier.test.js` with the
      incident's message shape against **unpadded** `requisitionLines`. The
      existing fixtures use pre-padded values and therefore never exercised this
      bug. Covers AC-5.
- [ ] Add a mixed-padding partial-scope case to the same file. Covers AC-6.
- [ ] Keep the existing padded-fixture tests in that file passing unchanged.
      Covers AC-7.
- [ ] Create `aigen-backend/tests/repository/rfqLibrary.syncAutoPO.test.js`
      (no test file for this repository exists today). Mock `axios.post` and
      `qcfLibrary`. Assert the success-branch update targets `where.id` equal to
      the matched row's id when `dt.PR_ITEM` is padded and the local `item_code`
      is not. Covers AC-1.
- [ ] In the same file, assert the unmatched-entry and zero-`affectedCount` cases
      log through `console.error` and `logActivity` and do not throw.
      Covers AC-3, AC-4.
- [ ] In the same file, assert exactly one `logSapSyncAttempt` call per attempt
      across success, business rejection, and thrown transport error, with
      `source: 'cl_approval_sync'`, and assert the persisted `requestPayload`
      contains no `Authorization` or `tokenAuth` key. Covers AC-9, AC-11.
- [ ] Create `aigen-backend/tests/repository/PurchaseRequest.getSyncSAP.test.js`
      asserting the equivalent persistence with `source: 'cron_sync'` across the
      same three outcomes. Covers AC-10.
- [ ] Confirm AC-2 through the existing controller suite
      `aigen-backend/tests/controllers/qcfController.approveByClAutoPo.test.js` —
      extend it so a padded-`PR_ITEM` success does not trigger the milestone-17
      rollback. Covers AC-2.
- [ ] Transaction, idempotency, and concurrency coverage: assert the already-synced
      guard (`rfqLibrary.repository.js:1777-1786`) still short-circuits before any
      SAP call or log write (BR-2), and that a thrown `logSapSyncAttempt` does not
      change the business outcome.
- [ ] Complete the acceptance-criteria mapping in `test-plan.md` with actual
      results.

## Verification and handoff

- [ ] Run `npm test` in `aigen-backend` and record the result in `test-plan.md`.
- [ ] Run the focused suites:
      `npx jest tests/helper/itemCode.test.js tests/helper/sapFailureClassifier.test.js tests/repository/rfqLibrary.syncAutoPO.test.js tests/repository/PurchaseRequest.getSyncSAP.test.js`.
- [ ] Run `npm run migrate -- up --db=aigen` then
      `npm run migrate -- down --db=aigen 1` against a scratch database and record
      both results. Covers AC-12.
- [ ] Frontend commands: N/A — no frontend change.
- [ ] Import-worker commands: N/A — no import-worker change.
- [ ] Inspect one persisted `log_sap_sync` row in a non-production environment and
      confirm no credential is present. Covers AC-11.
- [ ] Update `aigen-ai/index/` and `aigen-ai/context/project-state.md` with the new
      helper, model, repository, migration, and test files.
- [ ] Review the final diff for unrelated changes and secrets.
- [ ] Record unverified behavior, rollout order, and rollback in `test-plan.md`
      under "Unverified behavior".
- [ ] Open a follow-up ticket for `getSyncSAP`'s per-item matching
      (`aigen-backend/src/repository/PurchaseRequest.repository.js:2212-2226`),
      which updates every line of a QCF with no correspondence to the SAP
      response. Explicitly out of scope here.
- [ ] Open a follow-up ticket for a retention or pruning job for `log_sap_sync`
      and the other `log_*` tables — none exists today.
- [ ] Send the SAP team the payload captured on the next failed attempt, together
      with the open questions in `requirements.md` under Dependencies and unknowns.
- [ ] Move this specification to `aigen-ai/specs/completed/` only after all
      acceptance criteria are met.
