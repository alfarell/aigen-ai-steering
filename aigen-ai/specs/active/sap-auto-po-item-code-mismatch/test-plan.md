# Test plan — SAP Auto-PO: item_code format mismatch and missing request-payload persistence

## Acceptance-criteria mapping

| Acceptance criterion | Test/verification | Level | Repository/file | Expected result | Status |
|---|---|---|---|---|---|
| AC-1 | Success response with padded `DATA[].PR_ITEM` against an unpadded local `item_code` updates the correct row | Unit (mocked) | `aigen-backend/tests/repository/rfqLibrary.syncAutoPO.test.js` | `qcfLibrary.update` called with `where.id` equal to the matched row's id; payload sets `is_sync: true`, `po_number`, `status_milestone: 20` | Planned |
| AC-2 | Padded-`PR_ITEM` success does not trigger the approval rollback | Unit (mocked) | `aigen-backend/tests/controllers/qcfController.approveByClAutoPo.test.js` (extend) | No update to `QCF_WAITING_APPROVAL` (17); response is not `SAP_SYNC_FAILED` | Planned |
| AC-3 | `DATA` entry matching no local row is reported, not swallowed | Unit (mocked) | `aigen-backend/tests/repository/rfqLibrary.syncAutoPO.test.js` | `console.error` and `logActivity` called with qcf number, PR number, PR item, PO number; function resolves without throwing | Planned |
| AC-4 | Matched row whose milestone fails the `Op.or` guard yields `affectedCount === 0` and is reported | Unit (mocked) | same file | Same reporting as AC-3 | Planned |
| AC-5 | Incident message against unpadded `requisitionLines` classifies as all-ordered | Unit | `aigen-backend/tests/helper/sapFailureClassifier.test.js` (extend) | `error_reason_code === 'SAP_ALL_ITEMS_ALREADY_ORDERED'` | Planned |
| AC-6 | Mixed-padding subset of lines classifies as partial | Unit | same file | `error_reason_code === 'SAP_PARTIAL_ITEMS_ALREADY_ORDERED'` | Planned |
| AC-7 | Existing padded-fixture cases unchanged | Unit | same file, existing cases | All current assertions pass without modification | Planned |
| AC-8 | Non-numeric `item_code` falls back to strict equality | Unit | `aigen-backend/tests/helper/itemCode.test.js` | `"60"` matches `"00060"`; `"ABC"` matches only `"ABC"`; `null`/`undefined`/number inputs do not throw | Planned |
| AC-9 | One log row per `syncAutoPO` attempt across success, rejection, transport error | Unit (mocked) | `aigen-backend/tests/repository/rfqLibrary.syncAutoPO.test.js` | `logSapSyncAttempt` called exactly once per attempt with `source: 'cl_approval_sync'`, request payload, response or error detail, http status, success flag | Planned |
| AC-10 | Same persistence from the cron path | Unit (mocked) | `aigen-backend/tests/repository/PurchaseRequest.getSyncSAP.test.js` | `logSapSyncAttempt` called once per attempt with `source: 'cron_sync'` | Planned |
| AC-11 | No credential in any persisted payload | Unit (mocked) | both repository test files | `requestPayload` serialized contains no `Authorization`, `tokenAuth`, or `Basic ` substring | Planned |
| AC-12 | Migration applies and rolls back cleanly | Manual | `aigen-backend/migrations/aigen/<ts>-create-log-sap-sync.{up,down}.sql` | `log_sap_sync` created with its indexes, then dropped; no other table affected | Planned |

Every acceptance criterion in `requirements.md` appears at least once above.

## Automated coverage

### Backend

- Test files:
  - `aigen-backend/tests/helper/itemCode.test.js` (new)
  - `aigen-backend/tests/helper/sapFailureClassifier.test.js` (extend — existing
    fixtures use pre-padded values such as `'00010'` and therefore never
    reproduced this bug; the new cases must use unpadded local lines)
  - `aigen-backend/tests/repository/rfqLibrary.syncAutoPO.test.js` (new — no test
    file exists for this repository today)
  - `aigen-backend/tests/repository/PurchaseRequest.getSyncSAP.test.js` (new)
  - `aigen-backend/tests/controllers/qcfController.approveByClAutoPo.test.js`
    (extend — existing file)
- Mocks and fixtures: mock `axios.post`, the `qcfLibrary` model, `logActivity`,
  and `sapSyncLog.repository`. No database and no network. Use synthetic
  identifiers only — for example PR `8100099999`, QCF `QCF0009999`, vendor
  `100000`. Do not copy the production vendor code, prices, or quotation numbers
  into fixtures.
- Fixture message for AC-5, mirroring the incident's shape with a synthetic PR
  number: `", [E], No instance of object type PurchaseOrder has been created.
  External reference:, [E], PO header data still faulty, [E], Materials of
  requisition 8100099999 item 00060 alr. ordered in full"` paired with
  `requisitionLines = [{ pr_number: '8100099999', item_code: '60' }]`.
- Command: `npm test` from `aigen-backend`. Focused run:
  `npx jest tests/helper/itemCode.test.js tests/helper/sapFailureClassifier.test.js tests/repository/rfqLibrary.syncAutoPO.test.js tests/repository/PurchaseRequest.getSyncSAP.test.js`

### Frontend

- Test files/harness: N/A. No frontend change is in scope — see `requirements.md`.
- Command: N/A.

### Import worker

- Test files/harness: N/A. `item_code` ingestion is intentionally unchanged.
- Transaction/idempotency cases: N/A.
- Command: N/A.

## Contract and integration checks

- HTTP/OpenAPI: none. No route, request body, response shape, or status code
  changes. The values inside the existing `error_reason_code` and `user_message`
  fields become more specific for already-ordered failures; confirm the client
  tolerates `SAP_ALL_ITEMS_ALREADY_ORDERED` and
  `SAP_PARTIAL_ITEMS_ALREADY_ORDERED`, which already exist in
  `aigen-backend/src/const/sap-error-code.js`.
- Kafka/command: none.
- Database migration/rollback: `npm run migrate -- up --db=aigen` then
  `npm run migrate -- down --db=aigen 1` on a scratch database. Verify the table,
  its two indexes, and the clean drop.
- Cross-repository compatibility: none affected. `item_code` storage format is
  unchanged, so `aigen-import-pr`, `isourcing-laravel`, and `isourcing-vanilla`
  are unaffected.

## Manual scenarios

| Scenario | Preconditions/test data | Steps | Expected result |
|---|---|---|---|
| Padded-`PR_ITEM` success is recorded | Staging QCF with a single line, unpadded `item_code`, against a SAP stub returning padded `PR_ITEM` | Approve as Category Leader | `po_number` populated, `is_sync = 1`, `status_milestone = 20`, approval not rolled back, one `log_sap_sync` row with `success = 1` |
| Already-ordered rejection surfaces the specific reason | Staging QCF whose PR item is already fully ordered in the SAP test client | Approve as Category Leader | HTTP 500 with `error_reason_code = SAP_ALL_ITEMS_ALREADY_ORDERED` and the Indonesian message "PO sudah terbuat di luar sistem AIGEN."; approval rolled back to 17; one `log_sap_sync` row with `success = 0` |
| Payload is retrievable for the SAP team | Any staging attempt, success or failure | `SELECT request_payload, response_payload, http_status, created_at FROM log_sap_sync WHERE qcf_number = ?` | Full request body and raw response returned, with no credential present |
| SAP unreachable | Point the SAP base URL at an unroutable host in staging | Approve as Category Leader | Sync fails with `SAP_CONNECTION_FAILURE`; one `log_sap_sync` row with the request payload, null `response_payload`, and a populated `error_message`; approval rolled back |
| Duplicate approval is refused | Staging QCF already at `is_sync = 1` | Approve again | Short-circuits before any SAP call; no new `log_sap_sync` row (BR-2) |

Use staging or a SAP test client only. Do not re-run the production incident.

## Security and failure cases

- Unauthorized/forbidden role: unchanged. No new endpoint; existing approval
  authorization is untouched and is covered by the existing controller suite.
- Missing/expired/revoked token: a SAP Basic-auth rejection returns a non-2xx
  response; it must be persisted with its HTTP status and must not leak the
  credential into `log_sap_sync`.
- Invalid input: `normalizeItemCode` must tolerate `null`, `undefined`, numbers,
  empty strings, and non-numeric strings without throwing (AC-8).
- Dependency timeout/failure: the 10 s axios timeout
  (`aigen-backend/src/repository/rfqLibrary.repository.js:1878`) still applies;
  the `catch` path must persist a log row using
  `error.response?.data ?? error.message`.
- Duplicate/retry/concurrent request: the already-synced guard
  (`:1777-1786`) must still short-circuit before any SAP call or log write.
  Multiple `log_sap_sync` rows per QCF across separate attempts are expected and
  intentional.
- Partial database/integration failure: a failing `logSapSyncAttempt` insert must
  be caught and reported without changing the business outcome; assert this
  explicitly.
- Redaction: assert no persisted `request_payload` contains `Authorization`,
  `tokenAuth`, or a `Basic ` prefix (AC-11). This is enforced by test rather than
  by convention, because the safety argument rests on the token being
  header-only (`:1873-1876`), which a future edit could break.

## Commands and results

| Command | Date | Result | Notes |
|---|---|---|---|
| `npm test` (in `aigen-backend`) | | Planned | Full Jest suite |
| `npx jest tests/helper/itemCode.test.js` | | Planned | AC-8 |
| `npx jest tests/helper/sapFailureClassifier.test.js` | | Planned | AC-5, AC-6, AC-7 |
| `npx jest tests/repository/rfqLibrary.syncAutoPO.test.js` | | Planned | AC-1, AC-3, AC-4, AC-9, AC-11 |
| `npx jest tests/repository/PurchaseRequest.getSyncSAP.test.js` | | Planned | AC-10, AC-11 |
| `npx jest tests/controllers/qcfController.approveByClAutoPo.test.js` | | Planned | AC-2 |
| `npm run migrate -- up --db=aigen` (scratch DB) | | Planned | AC-12 |
| `npm run migrate -- down --db=aigen 1` (scratch DB) | | Planned | AC-12 |

## Unverified behavior

- **The actual format of `PR_ITEM` in a SAP success response is unknown.** Only
  the padded form inside an error message has been observed. Tests therefore
  assert tolerance of both forms rather than asserting one true format, and the
  success-branch update is keyed by primary key so it does not depend on the
  format at all.
- **The root cause of the production incident is not proven.** The leading
  hypothesis is that SAP created a PO, AiGen's zero-row update silently discarded
  it, the approval was rolled back, and the retry was rejected as already ordered.
  Confirming this requires SAP-side EBAN/EKPO history for PR 8100020706 item
  00060 — specifically whether a PO ever existed and was later deleted. This fix
  is correct and necessary regardless of the answer, because the silent zero-row
  update is a real defect either way, but the spec must not claim the incident is
  explained until SAP confirms.
- **Whether the quantity AiGen sent exceeded the PR's open quantity has not been
  ruled out.** AiGen performs no open-quantity validation before sending
  (`aigen-backend/src/repository/rfqLibrary.repository.js:1820-1858`). If SAP
  confirms a quantity overrun, that is a separate requirement not covered here.
- **The precise line structure of SAP's "alr. ordered in full" message is
  inferred.** `aigen-backend/src/helper/sapFailureClassifier.js:7-10` already
  records that the regex was written without a real SAP sample. The tests use the
  one observed message shape; other shapes may still fall through to
  `SAP_SYNC_FAILURE`.
- **Whether any production `item_code` is non-numeric is unknown.** The column is
  a free-form `STRING(10)`. The normalizer's strict-equality fallback preserves
  current behavior for such values, so this cannot regress, but it is untested
  against real data.
- **`getSyncSAP`'s per-item matching remains unverified and unfixed.** It updates
  every line of a QCF by `qcf_number` plus `status_milestone` with no
  correspondence to the SAP response
  (`aigen-backend/src/repository/PurchaseRequest.repository.js:2212-2226`).
  Explicitly out of scope; a follow-up ticket is required.
- **No retention job exists for `log_sap_sync` or any other `log_*` table.**
  Growth is bounded by PO creation volume, which is low, but this is untested at
  scale.
