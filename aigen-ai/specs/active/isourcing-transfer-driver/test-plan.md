# Test plan — iSourcing Transfer Driver (Database ↔ Public API)

Last run: 2026-08-23 on `develop-dot`, Node v24.12.0 (`.nvmrc` pins v22.14.0 — the suite was not
run on the pinned version).

## Acceptance-criteria mapping

| Acceptance criterion | Test/verification | Level | Repository/file | Expected result | Status |
|---|---|---|---|---|---|
| AC-1 backward-compatible default | `resolves to database when the value is unset`; full pre-existing suite unchanged | Unit | `tests/config/isourcingDriverConfig.test.js`, `tests/controllers/qcfController.manualSourcingHeader.test.js` | Driver resolves to `database`; existing transfer behavior unchanged | Passed |
| AC-2 switch without code change | `api driver exposes a transfer function`; driver selection through the port | Unit | `tests/services/isourcingDriverParity.test.js`, `tests/services/isourcingTransferPort.test.js` | Selecting `api` routes to the API driver | Passed (operational confirmation deferred to Phase 5) |
| AC-3 invalid value fails fast | `rejects an unknown driver and names the valid values` | Unit | `tests/config/isourcingDriverConfig.test.js` | Boot guard throws naming `database, api` | Passed |
| AC-4 missing API config fails at boot | `rejects api when required values are missing and names them`, `rejects api when the api block is absent entirely` | Unit | `tests/config/isourcingDriverConfig.test.js` | Boot guard throws naming the missing variables | Passed |
| AC-5 callers are driver-agnostic | `grep -rln "drivers/database.driver\|drivers/api.driver" src app.js` | Manual | `aigen-backend` | Only `isourcingTransfer.port.js` matches | Passed |
| AC-6 identical contract across drivers | `success shape parity`, `failure shape parity` | Unit | `tests/services/isourcingDriverParity.test.js` | Both drivers return identical key sets and codes | Passed |
| AC-7 no Aigen mutation on failure | `reports a business failure to Sentry tagged with the driver`; existing cron handler suites | Unit | `tests/services/isourcingTransferPort.test.js`, `tests/services/prService.*.test.js` | Failure returned, Aigen state untouched, token left active | Passed |
| AC-8 idempotency | `is stable across two identical calls`, `changes when the item set changes`, `maps an already-complete PR to success with zero added items` | Unit | `tests/services/isourcingApiDriver.test.js` | Deterministic key; repeat transfer reports `Missing items added: 0` | Passed (revisit in Phase 4 against the real contract) |
| AC-9 retry classification | `does not retry a 400`, `does not retry a 401`, `retries a 500 up to the configured maximum then fails` | Unit | `tests/services/isourcingApiDriver.test.js` | 4xx not retried, 5xx/429/network retried within bounds | Passed |
| AC-10 timeout honored | `retries a network error with no response` | Unit | `tests/services/isourcingApiDriver.test.js` | Timeout classified transient and bounded | Partially covered — the axios timeout itself is configured, not exercised |
| AC-11 no dual write | Code review plus database-side privilege check | Manual | `aigen-backend` | No INSERT/UPDATE to `task_board` in `api` mode | Not started (Phase 5) |
| AC-12 rollback to database mode | Rehearsal in non-production | Manual | deployment | Transfers resume on `database` after restart | Not started (Phase 5) |
| AC-13 credential confidentiality | `never puts credential material in the returned failure` | Unit | `tests/services/isourcingApiDriver.test.js` | No credential material in the returned failure | Passed |
| AC-14 traceability | `emits one structured line naming the driver on success` | Unit | `tests/services/isourcingTransferPort.test.js` | One line with driver, card title, item count, result, duration | Passed |

## Automated coverage

### Backend

- Test files added:
  - `tests/config/isourcingDriverConfig.test.js` — 9 tests
  - `tests/services/isourcingTransferPort.test.js` — 15 tests
  - `tests/services/isourcingApiDriver.test.js` — 17 tests
  - `tests/services/isourcingDriverParity.test.js` — 5 tests
- Mocks/fixtures: `jest.doMock('../../config')` for the config seam, module mocks for
  `qcfLibrary.repository`, `database_isourcing`, `helper/log`, `api/isourcing.api`, and
  `@sentry/node`. No test touches a real database or a real endpoint.
- Command: `npm test`

### Frontend

Not applicable — no frontend change.

### Import worker

Not applicable — verified read-only against `task_board`.

## Suite results

| Point | Suites | Tests |
|---|---|---|
| After Phase 4 (contract v1.0) | 23 passed, 2 failed | 232 passed, 11 failed, 243 total |
| Baseline before Phase 0 | 17 passed, 2 failed | 141 passed, 11 failed, 152 total |
| After Phase 0 | 17 passed, 2 failed | 141 passed, 11 failed, 152 total |
| After Phase 1 | 18 passed, 2 failed | 150 passed, 11 failed, 161 total |
| After Phase 2 | 19 passed, 2 failed | 165 passed, 11 failed, 176 total |
| After Phase 3 | 21 passed, 2 failed | 187 passed, 11 failed, 198 total |

The two failing suites are `tests/controllers/qcfController.dicReminder.test.js` and
`tests/repository/rfqLibrary.dicReminder.test.js`. They fail identically before and after this
work and are recorded in `known-issues.md`.

## Phase 4 coverage (contract v1.0, 2026-08-24)

| Criterion | Test | Status |
|---|---|---|
| AC-15 contract-shaped payload | `isourcingApiDriver.test.js` — payload shape group | Passed |
| AC-16 `202` is not success | `isourcingApiDriver.test.js`, `isourcingTransferPort.test.js` — pending group | Passed |
| AC-17 reconciliation completes once | `isourcingReconciliation.test.js` — succeeded group | Passed |
| AC-18 re-send uses a fresh key | `isourcingReconciliation.test.js`, `isourcingTransferRequest.test.js` | Passed |
| AC-19 retry classification | `isourcingApiDriver.test.js` — retry classification group | Passed |
| AC-20 assignment gaps visible | `isourcingApiDriver.test.js` — assignment gaps group | Passed |

New suites: 27 driver tests, 21 port tests, 13 reconciliation tests, 17 repository tests, 7 parity
tests.

## Migration status (2026-08-24)

Applied on local. `isourcing_transfer_requests` verified read-only: 22 columns, `business_key`,
`origin_stage`, `status enum('queued','succeeded','failed','exhausted')`, unique index on
`idempotency_key`. The repository suite still runs against a mocked model, so the schema is now
verified by inspection rather than by the tests themselves. The `.down.sql` rollback is untested.

## Live connectivity probe (2026-08-24, non-production)

First contact with a real iSourcing endpoint, using the project's own HTTP clients so the Basic
Auth header, timeout, and base-URL joining were exercised as the driver builds them.

| Probe | Expected | Actual |
|---|---|---|
| `GET {statusPath}/aigen-connectivity-probe` | 404 `REQUEST_NOT_FOUND` | Matched |
| `POST {transferPath}` with a one-property body | 400 `PAYLOAD_INVALID` (auth and path correct, nothing written) | Matched |

Both are gate rejections, so no PR was created. The live error body shape (`{ error: { code } }`)
matches what `errorCodeOf()` in the API driver parses, and `classifyError` treats both as
non-retryable, as intended.

Still unexercised: a successful `202`, the status endpoint returning a real terminal state, and the
reconciliation stage against live data.

## Not covered

- The axios timeout path is configured but not exercised against a slow endpoint.
- The real iSourcing endpoint, its payload names, and its error codes (OI-1).
- Concurrent transfers against a real MySQL schema; KI-012 and KI-013 remain open.
- Boot behavior of `app.js` and `src/cron.js` was syntax-checked and the config module was loaded
  against the real `.env`, but neither process was started.
