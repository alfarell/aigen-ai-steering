# Test plan — Admin RFQ dashboard hides re-sent parallel batch behind a DIC-declined sibling

## Acceptance-criteria mapping

| Acceptance criterion | Test/verification | Level | Repository/file | Expected result | Status |
|---|---|---|---|---|---|
| AC-1 | `data query sibling_active subquery excludes DIC-declined siblings (AC-1, AC-3)` checks that the data SQL contains `status_dic IS NULL OR status_dic != 2` inside the `sibling_active` subquery | Unit | aigen-backend `tests/repository/rfqLibrary.listRfqAdmin.siblingActive.test.js` | Predicate present | Done |
| AC-1 | Local replication on the production-copy DB with `RFQ0002235` (vendor 108357 declined, vendor 103716 pending); no synthetic fixture was created | Manual (local DB) | aigen-backend | Vendor B row returned, `Waiting Vendor` / `Manual Sourcing` | Done |
| AC-2 | Admin dashboard → Action → Not Submitted Items page | Manual (UI) | aigen-frontend (no change) | Manual Sourcing button visible | Planned |
| AC-3 | `existing status_milestone/status_vendor/vendor_sequence predicates are preserved (AC-3)` checks that the predicate is NULL-safe and the milestone/vendor predicates are unchanged | Unit | same test file | `status_dic IS NULL` branch present; existing predicates present | Done |
| AC-4 | `count query applies the same sibling_active rule (AC-4)` checks that the count `sequelize.query` call (identified by `COUNT(*) AS total`) contains the predicate | Unit | same test file | Predicate present in count SQL | Done |
| AC-5 | Read-only replication script calls `listRfqAdmin({ search: 'RFQ0002235' })` | Manual (production-copy DB) | scratch script (not committed) | Batch-3 / vendor 103716 row returned | Done |

## Automated coverage

### Backend

- Test files: `tests/repository/rfqLibrary.listRfqAdmin.siblingActive.test.js` (new).
- Mocks/fixtures: follow `tests/repository/rfqLibrary.listRfqUser.hasPoPublished.test.js`. Mock `src/config/database` (`query: jest.fn()`), models, and `dashboardHelper` builders. Resolve the count query with `[{ total: 0 }]` and the data query with `[]`, then assert on the captured SQL strings.
- Command: `npm test -- tests/repository/rfqLibrary.listRfqAdmin.siblingActive.test.js`

### Frontend

- Test files/harness: N/A. No frontend change.
- Command: N/A.
- Manual substitute: AC-2 UI check.

### Import worker

- N/A. Not involved.

## Contract and integration checks

- HTTP/OpenAPI: response shape unchanged. No OpenAPI update.
- Kafka/command: N/A.
- Database migration/rollback: N/A.
- Cross-repository compatibility: frontend consumes the same fields.

## Manual scenarios

| Scenario | Preconditions/test data | Steps | Expected result |
|---|---|---|---|
| DIC-declined sibling, other vendor re-sent | Synthetic PARALLEL RFQ: vendor A rows `status_milestone=8`, `status_vendor=1`, `status_dic=2`; vendor B rows same item codes, `status_milestone=2`, `status_vendor=0` | Login as Admin → RFQ dashboard → search RFQ | Vendor B row shown as `Waiting Vendor`, action `Manual Sourcing` |
| Undecided sibling (regression) | Same as above but vendor A `status_dic=NULL` | Same | Vendor B row still hidden |
| Accepted sibling (regression) | Vendor A `status_dic=1` | Same | Vendor B row still hidden |
| Incident RFQ | Production-copy DB, `RFQ0002235` | Admin dashboard → search → Action | Batch 3 row visible, Manual Sourcing button on Not Submitted Items page. **Do not submit.** |

## Security and failure cases

- Unauthorized/forbidden role: unchanged route guards. Not in scope.
- Missing/expired/revoked token: not affected.
- Invalid input: not affected.
- Dependency timeout/failure: an existing `listRfqDashboard` catch returns empty data. Behaviour is unchanged.
- Duplicate/retry/concurrent request: N/A (read-only).
- Partial database/integration failure: N/A.

## Commands and results

| Command | Date | Result | Notes |
|---|---|---|---|
| Read-only replication of `listRfqAdmin` / `listRfqNew` / `getHeaderInformationCSForm` for `RFQ0002235` | 2026-09-28 | Reproduced | Admin: only batch 2 (`Waiting CL`, action null). CS: batch 3 `Waiting Vendor`, action null (token active until 2026-09-29, by design). |
| `npx jest tests/repository/rfqLibrary.listRfqAdmin.siblingActive.test.js` (before fix) | 2026-09-28 | 2 failed, 1 passed | Confirms the test fails pre-fix: `sibling_active` subquery lacked `status_dic IS NULL OR status_dic != 2` in both the data and count SQL; the pre-existing `status_milestone`/`status_vendor`/`vendor_sequence` predicates already passed. |
| Applied fix: added `AND (status_dic IS NULL OR status_dic != ${STATUS_DIC.DECLINED})` to `sibling_active` in `src/repository/rfqLibrary.repository.js` | 2026-09-28 | Applied | Matches design.md proposed diff exactly. |
| `npx jest tests/repository/rfqLibrary.listRfqAdmin.siblingActive.test.js` (after fix) | 2026-09-28 | 3 passed, 3 total | AC-1, AC-3, AC-4 unit coverage green. |
| `npx jest tests/repository tests/helper` | 2026-09-28 | 23 suites / 166 tests passed, 0 failed | No pre-existing failures observed; ran on top of clean pre-fix baseline plus the fix, so no failures needed to be separated out. `tests/repository/rfqLibrary.syncAutoPO.taxCode.test.js` and `tests/helper/log.test.js` print expected `console.error`/DB-connection-refused noise as part of their own intentional error-path/teardown assertions, not new failures. |
| `git diff --check -- src/repository/rfqLibrary.repository.js` | 2026-09-28 | Clean | No whitespace errors. |
| Lint | 2026-09-28 | Skipped | No `lint` script defined in `package.json`. |
| Read-only replication of `listRfqAdmin` / `listRfqNew` for `RFQ0002235` (after fix) | 2026-09-28 | Pass (AC-1, AC-5) | Admin list now includes batch 3 / vendor 103716 as `Waiting Vendor`, action `Manual Sourcing`. CS list unchanged (batch 3 `Waiting Vendor`, action null). |
| Read-only regression check with `listRfqAdmin` on `RFQ0002334` and `RFQ0002329` | 2026-09-28 | Pass (AC-3) | The pending milestone-2 batch stays hidden behind an active sibling at milestone 3 (`status_dic` NULL). |
| Blast-radius SELECT (PARALLEL items with a DIC-declined sibling and another non-rejected vendor on the same item) | 2026-09-28 | 39 RFQs | Upper bound of RFQs whose Admin visibility may change. Individual rows were not checked. The change can only make rows visible, never hide them. |

## Unverified behavior

- Manual Sourcing submission (`POST /pr/cs/send_isourcing/RFQ0002235/3`) was not executed because it mutates data and calls iSourcing. The cross-level item inclusion in `sendActionToCS` is tracked as U-3.
- Whether the incident was reported by Admin or CS (U-1).
