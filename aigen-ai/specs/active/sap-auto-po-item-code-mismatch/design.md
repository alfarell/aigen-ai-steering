# Design — SAP Auto-PO: item_code format mismatch and missing request-payload persistence

## Current behavior

Verified by reading the source; every claim below is cited.

1. `qcfController.approveByCL` (`aigen-backend/src/controllers/qcfController.js:1432`)
   handles Category Leader approval and calls
   `rfqLibraryRepo.syncAutoPO(cl_id, cl_name, qcf_number)` at `:1510`.
2. `syncAutoPO` (`aigen-backend/src/repository/rfqLibrary.repository.js:1772`):
   - Skips when the QCF is already synced (`:1777-1786`).
   - Selects the QCF lines joined to `rfq_library` and `master_vendor`,
     including `qcf.id` (`:1788-1815`).
   - Builds `requisitionLines` as `{ pr_number, item_code }` pairs (`:1816-1819`).
   - Builds `items` with `line_item: data.item_code` (`:1825`) and the header
     (`:1846-1859`).
   - Logs the payload with `console.log` only (`:1860`).
   - Resolves the endpoint and Basic-auth token via `getSapAutoPoConnection`
     (`:1862`, helper at `aigen-backend/src/helper/sapAutoPo.js`).
   - POSTs to SAP with a 10 s timeout; the token is placed in the
     `Authorization` header, never in the body (`:1869-1879`).
   - Logs the response with `console.log` only (`:1880`).
   - Success branch (`:1885-1906`): for each `dt` in `response.data.DATA`, runs
     `qcfLibrary.update({ is_sync: true, po_number: dt.PO_NUMBER, sync_message,
     status_milestone: SAP_SYNC_COMPLETE }, { where: { qcf_number, pr_number:
     dt.PR_NUMBER, item_code: dt.PR_ITEM, [Op.or]: [...] } })`. The return value
     is discarded.
   - Failure branch (`:1946-1965`): writes `is_sync: false`, `po_number: null`,
     `sync_message: respMessage`, then returns
     `classifySapFailure(respMessage, requisitionLines)`.
3. `qcfController.approveByCL` re-reads the sync status at `:1513` and, when
   `is_sync` is falsy, rolls the approval back to
   `STATUS_MILESTONE.QCF_WAITING_APPROVAL` (17) and returns HTTP 500 with
   `error_reason_code` and `user_message` (`:1515-1540`).
4. `classifySapFailure` (`aigen-backend/src/helper/sapFailureClassifier.js:62`)
   parses `pr_number` and `item_code` pairs out of the SAP message
   (`ORDERED_IN_FULL_LINE_PATTERN`, `:10`), keys both sides with
   `toKey` (`:19-21`) as `pr_number::item_code`, and compares scope in
   `compareOrderedInFullScope` (`:47-60`).
5. The cron path `getSyncSAP`
   (`aigen-backend/src/repository/PurchaseRequest.repository.js:2094`) builds an
   equivalent payload (`~:2155-2181`), `console.log`s it (`:2183-2185`), and on
   success updates **all** lines of the QCF by `qcf_number` plus
   `status_milestone` (`:2212-2226`) with no per-item correspondence to the SAP
   response. It never calls `classifySapFailure`.
6. Milestone constants: `QCF_WAITING_APPROVAL: 17`, `CL_APPROVAL: 18`,
   `SAP_SYNC_COMPLETE: 20` (`aigen-backend/src/const/status-milestone.js:90,95,105`).
7. `grep -rn "padStart" aigen-backend/src` finds no `item_code` normalization
   anywhere — only date and document-number formatting.

### Failure mechanism

`item_code` is stored unpadded (`"60"`), SAP refers to the item padded
(`"00060"`). Step 2's success-branch `where` and step 4's `toKey` both use exact
string equality across that boundary:

- The success update matches zero rows and Sequelize returns normally, so a PO
  that SAP actually created is never recorded. `is_sync` stays false, step 3
  rolls the approval back, the user re-approves, and SAP rejects the retry with
  "alr. ordered in full" — the exact contradiction reported in the incident.
- The classifier's scope comparison finds no key overlap, returns `null`, and
  degrades to `SAP_SYNC_FAILURE`, so the dedicated already-ordered reason codes
  never surface.

Neither the request payload nor the raw response is persisted anywhere, so the
incident's payload cannot be reconstructed for the SAP team.

## Proposed behavior

Five changes, smallest complete set.

**1. Shared normalization helper.** New `aigen-backend/src/helper/itemCode.js`
exporting `normalizeItemCode(value)` and `itemCodesMatch(a, b)`. A purely numeric
string has its leading zeros stripped so `"60"` and `"00060"` normalize to `"60"`;
any other value is trimmed and compared by strict string equality. Numeric
normalization is chosen over `padStart(5, '0')` because SAP's `PR_ITEM` response
format is unconfirmed (requirements BR-5), so a fixed pad width would encode an
assumption we cannot verify. Satisfies FR-1, FR-2, FR-8-adjacent safety for FR-8
is handled separately.

**2. Classifier keying.** `toKey` in
`aigen-backend/src/helper/sapFailureClassifier.js:19-21` becomes
`` `${line.pr_number}::${normalizeItemCode(line.item_code)}` ``. No other symbol
in the file changes and the exported surface is identical. Satisfies FR-7.

**3. Primary-key matching in the success branch.** `syncAutoPO` builds a lookup
map from the already-fetched `getdata` rows keyed by
`` `${pr_number}::${normalizeItemCode(item_code)}` ``; each row already carries
`qcf.id` (selected at `:1789`). For each `dt`, the matching row is found by the
normalized key and the update's `where` changes from
`{ qcf_number, pr_number: dt.PR_NUMBER, item_code: dt.PR_ITEM, [Op.or]: [...] }`
to `{ qcf_number, id: matchedRow.id, [Op.or]: [...] }`. Keying by the row's own
primary key removes the string-format dependency from this path entirely rather
than merely making it tolerant. Satisfies FR-3.

**4. Zero-match detection.** The update result is captured as
`const [affectedCount] = await qcfLibrary.update(...)`. A lookup miss, or
`affectedCount === 0` after a successful lookup (a legitimate race where the row
no longer satisfies the `Op.or` milestone guard), triggers a `console.error` and a
`logActivity` entry naming `qcf_number`, `dt.PR_NUMBER`, `dt.PR_ITEM`, and
`dt.PO_NUMBER`. The function continues and does not throw. `console.error` plus
`logActivity` matches the conventions already used in this file; no new logging
dependency is introduced. Satisfies FR-4.

**5. Payload persistence.** A new append-only table `log_sap_sync`, a Sequelize
model, and a thin repository function `logSapSyncAttempt(...)`. Both
`syncAutoPO` and `getSyncSAP` call it at three points each: after a success
response, after a non-success response, and in the `catch` block. Every attempt
is logged, not only failures, because this incident shows a "successful" SAP
response can still correspond to a local mismatch, and the SAP team needs the
payload for any `qcf_number` regardless of how AiGen classified it. Satisfies
FR-5, FR-6.

### Resulting flow

1. CL approves, `syncAutoPO` builds the same payload as today and POSTs it — the
   outbound `line_item` stays unpadded.
2. The request and response are persisted to `log_sap_sync` regardless of outcome.
3. On `SUCCESS = true`, each `DATA` entry is matched by normalized key and updated
   by primary key, so padding differences no longer cause a zero-row update.
4. Any residual unmatched entry or zero-row update is reported loudly instead of
   leaving `is_sync` false in silence.
5. `approveByCL` reads a now-correct `is_sync`, so the rollback no longer fires
   for this class of mismatch.
6. On `SUCCESS = false` with "alr. ordered in full", `classifySapFailure` resolves
   the specific reason code, surfaced through the existing
   `error_reason_code` and `user_message` response fields.

## Affected components

| Repository/component | Current symbol/path | Proposed change |
|---|---|---|
| backend / helper | `aigen-backend/src/helper/itemCode.js` | **New.** `normalizeItemCode`, `itemCodesMatch`. |
| backend / helper | `aigen-backend/src/helper/sapFailureClassifier.js:19-21` `toKey` | Normalize `item_code` before keying. |
| backend / migration | `aigen-backend/migrations/aigen/<ts>-create-log-sap-sync.{up,down}.sql` | **New.** Create and drop `log_sap_sync`. |
| backend / model | `aigen-backend/src/models/default/logSapSync.js` | **New.** Sequelize model, `timestamps: false`, following `models/default/logSap.js`. |
| backend / repository | `aigen-backend/src/repository/sapSyncLog.repository.js` | **New.** `logSapSyncAttempt(...)` insert wrapper, styled after `logActivity` in `src/helper/log.js:47`. |
| backend / repository | `aigen-backend/src/repository/rfqLibrary.repository.js:1772` `syncAutoPO` | Normalized lookup map, primary-key update, zero-match reporting, three `log_sap_sync` writes. |
| backend / repository | `aigen-backend/src/repository/PurchaseRequest.repository.js:2094` `getSyncSAP` | Three `log_sap_sync` writes only. Matching logic untouched. |
| backend / controller | `aigen-backend/src/controllers/qcfController.js:1432` `approveByCL` | **No change.** Benefits from the corrected `is_sync`. |
| backend / const | `aigen-backend/src/const/sap-error-code.js` | **No change.** `SAP_ALL_ITEMS_ALREADY_ORDERED` and `SAP_PARTIAL_ITEMS_ALREADY_ORDERED` already exist with Indonesian user messages. |

## Interface changes

None. No HTTP route, request body, response shape, status code, Kafka event, or
OpenAPI document changes. The SAP request payload shape is deliberately unchanged.
The values carried in the existing `error_reason_code` and `user_message` response
fields become more specific for already-ordered failures, which is the intended
behavior of code that already shipped.

## Data design

- Schemas, tables, models: new table `log_sap_sync`, named to match the existing
  `log_activity` and `log_sla` convention.

  | Column | Type | Notes |
  |---|---|---|
  | `id` | INT AUTO_INCREMENT PK | |
  | `qcf_number` | VARCHAR(20) NOT NULL | Indexed. |
  | `pr_number` | VARCHAR(15) NULL | Header PR number when known. |
  | `source` | VARCHAR(20) NOT NULL | `cl_approval_sync` or `cron_sync`. |
  | `request_payload` | JSON NOT NULL | The `requestData` object verbatim. Body only, never headers. |
  | `response_payload` | JSON NULL | Raw SAP response, or `error.response?.data` on a transport error. |
  | `http_status` | INT NULL | From the axios response or `error.response?.status`. |
  | `success` | TINYINT(1) NOT NULL DEFAULT 0 | SAP's `SUCCESS == 'true'`. |
  | `error_message` | TEXT NULL | `error.message` when no response body exists. |
  | `created_at` | DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP | Indexed, for future pruning. |

- Migration, seed, backfill: one raw-SQL up/down pair under
  `aigen-backend/migrations/aigen/`, following the existing convention seen in
  `20260823202433-create-isourcing-transfer-requests.{up,down}.sql`. Created with
  `npm run migrate:create -- --db=aigen --name=create-log-sap-sync`. No backfill —
  the table starts empty and no existing row is modified by this fix, because the
  defect was in comparison logic, not in stored data.
- Transaction boundary: unchanged. The log insert is deliberately outside any
  transaction around the `qcf_library` update, so a diagnostic write can never
  roll back or block the business outcome.
- Idempotency and concurrency: the table is append-only with no unique
  constraint. Multiple rows per `qcf_number` are expected and desirable.
- Data retention and rollback: no pruning job exists for any `log_*` table in
  this repository today; building one here would be premature. `created_at` is
  indexed so a retention job can be added later. The down migration drops the
  table; nothing else reads it.

## UI and state

Not applicable. No route, component, hook, or service changes. The only
user-visible difference is a more specific failure message text, already present
in `src/const/sap-error-code.js`, reaching the approver more often.

## Security

- Backend authorization: unchanged. No new endpoint is introduced and the new
  table is not exposed through any API by this change.
- Token lifetime, purpose, revocation: unchanged. The SAP Basic-auth credential
  continues to be resolved per `server_groups` at call time by
  `getSapAutoPoConnection`.
- Validation: `normalizeItemCode` must tolerate `null`, `undefined`, numbers, and
  non-numeric strings without throwing, because `item_code` is a free-form
  `STRING(10)`.
- Logging and redaction: `request_payload` stores the `requestData` object only.
  This is safe because `tokenAuth` is placed exclusively in the HTTP
  `Authorization` header (`rfqLibrary.repository.js:1873-1876`) and never appears
  in the `requestData` literal (`:1846-1859`) — both verified by reading the
  source. Request headers must not be logged. AC-11 asserts this and must be
  enforced by test, not by convention alone.

## Integrations and failure handling

- SAP: the 10 s axios timeout (`rfqLibrary.repository.js:1878`) is unchanged, as
  is the absence of automatic retry. The `catch` block must use the
  `error.response?.data ?? error.message` guard so that a transport error with no
  response body still produces a usable log row rather than throwing inside the
  logger.
- The `log_sap_sync` insert must not mask a SAP outcome. If the insert itself
  fails, it is caught and reported via `console.error`; the sync continues and the
  business result is unaffected.
- Sentry: `rfqLibrary.repository.js` has no existing Sentry import, so the
  zero-match reporting uses `console.error` plus `logActivity` to stay consistent
  with the file rather than introducing a new dependency for one call site.
- Email, Kafka, filesystem, cross-schema: not involved.

## Alternatives considered

| Alternative | Reason accepted/rejected |
|---|---|
| Normalize `item_code` at comparison time via a shared helper | **Accepted.** Touches only the SAP boundary, cannot regress the many unrelated consumers of `item_code`. |
| Zero-pad `item_code` in the outbound payload (`line_item`) | **Rejected.** SAP accepts the unpadded form today in non-incident cases; changing the wire format on an unconfirmed assumption risks breaking working traffic. |
| Change the stored `item_code` format to padded | **Rejected.** Requires auditing every join, filter, and `GROUP BY` on `item_code` across at least `rfqLibrary.repository.js` and `PurchaseRequest.repository.js`, plus the ingestion path. Far beyond a minimal fix. |
| `padStart(5, '0')` on both sides instead of stripping zeros | **Rejected.** Encodes an unverified pad width. Stripping leading zeros is tolerant of any width. |
| Keep the `item_code` filter in the success-branch `where` but normalized | **Rejected.** Primary-key matching is strictly narrower and unambiguous, and the `id` is already in hand from the same query. |
| Reuse `log_activity` for the payload | **Rejected.** It stores a single free-text message with no structure for request, response, or HTTP status, and mixing large JSON blobs into it would degrade an existing operational log. |
| Log only failed attempts | **Rejected.** The incident's root cause is a *successful* SAP response that AiGen mishandled. Failure-only logging would not have captured it. |
| Fix `getSyncSAP`'s per-item matching in the same change | **Rejected here.** A genuine but separate defect, not exercised by this incident. Recorded as a follow-up so this fix stays minimal and reviewable. |

## Risks and mitigations

| Risk | Likelihood/impact | Mitigation |
|---|---|---|
| SAP's success `PR_ITEM` format is something other than padded or unpadded numeric | Low / High | The normalizer is width-agnostic, and the success update is keyed by primary key rather than by the string at all, so this path no longer depends on the format. |
| A production `item_code` is non-numeric and normalization changes its meaning | Low / Medium | Non-numeric values fall back to trimmed strict equality — identical to current behavior. Covered by AC-8. |
| The new insert fails in production and breaks a sync that would otherwise succeed | Low / High | The insert is outside the business transaction and is individually guarded; a logging failure is reported but never propagated. |
| Deploying code before running the migration | Medium / Medium | Migration is an explicit blocking pre-deploy step; see Rollout. The insert failing loudly is preferable to silently skipping. |
| `log_sap_sync` grows unbounded | Medium / Low | `created_at` is indexed so a retention job can be added; volume is bounded by PO creation volume, which is low. Recorded as a follow-up. |
| The primary-key change misses a row that the old string filter would have caught | Low / Medium | The lookup map is built from the same `getdata` rows used to construct the payload, so every sent line has a corresponding entry. Any miss is now reported by FR-4 instead of being silent. |

## Rollout and rollback

Feature flags: none. The change is corrective and additive; a flag would leave the
known-broken comparison live.

Deploy order:

1. Create the migration pair with
   `npm run migrate:create -- --db=aigen --name=create-log-sap-sync` and fill in
   the SQL.
2. Run `npm run migrate -- up --db=aigen` in the target environment **before**
   deploying the code that writes to `log_sap_sync`. This is a blocking step.
3. Deploy the backend code as a single release — the helper, the classifier fix,
   the `syncAutoPO` change, and the `getSyncSAP` logging. Splitting them would
   leave a partially corrected comparison with no functional benefit.
4. No frontend, mobile, or `aigen-import-pr` deployment is required.
5. No backfill.

Monitoring after release:

- Watch for the new zero-match `console.error` and its `logActivity` entries — any
  occurrence means an unmatched SAP response line and warrants investigation.
- Confirm `log_sap_sync` receives rows from both `cl_approval_sync` and
  `cron_sync`.
- Spot-check one persisted `request_payload` to confirm no credential is present
  (AC-11).
- Watch whether `SAP_ALL_ITEMS_ALREADY_ORDERED` starts appearing where
  `SAP_SYNC_FAILURE` was previously recorded; that confirms FR-7 took effect.

Rollback:

- Code: revert the release. `syncAutoPO`, `getSyncSAP`, and `sapFailureClassifier`
  return to current behavior; the logging additions are pure side effects and are
  safe to remove.
- Migration: `npm run migrate -- down --db=aigen 1` drops `log_sap_sync`. Safe
  because nothing else reads the table — it has no foreign keys and no other code
  path depends on it.
- No data migration to undo.
