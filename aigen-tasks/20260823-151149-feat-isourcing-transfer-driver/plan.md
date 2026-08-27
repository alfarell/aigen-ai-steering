# Plan: iSourcing Transfer Driver (Database ↔ Public API)

- Created: 2026-08-23 15:11:49 +07:00
- Revised: 2026-08-23 — baseline changed from a branch merge to `develop-dot` as-is
- Status: Phases 0-3 implemented and verified 2026-08-23. Phase 4 unblocked and re-scoped 2026-08-24
  against iSourcing API contract v1.0; not started. Phase 5 not started.
- Contract: `isourcing/isourcing-docs/public-api-contract-pr-transfer.md` v1.0
- Phase 4 executor plan: `aigen-tasks/20260824-031739-feat-isourcing-api-contract-v1/plan.md`
- Primary repository: `aigen-backend`
- Target branch at planning time: `develop-dot`
- Target commit at planning time: `4d30f82d`
- Baseline dependency: **none.** `feat/enhancement-on-cron` (`af3d9d50`) is not adopted
- Runtime source files: 10 (5 new, 5 modified) plus `.env.example`
- Test files to add: 4
- Database mutation authorized: No for production. Phase 4b introduces one migration, to be run
  against a local database only.
- Specification: `aigen-ai/specs/active/isourcing-transfer-driver/spec.md`
- Phase checklist: `aigen-ai/specs/active/isourcing-transfer-driver/tasks.md`

> **Document relationship.** `spec.md` holds the behavioral contract and acceptance criteria.
> `tasks.md` holds the phase checklist. This `plan.md` is the executor's working document: exact
> file list, ordered steps, verification commands, and the completion report. All three must stay
> consistent — when a phase boundary changes, update `tasks.md` and this file together, and treat
> `spec.md` as authoritative for the contract.

## Objective

Introduce a driver layer so that PR transfers to iSourcing can be switched between direct
`task_board` database writes and the iSourcing public API by changing one `.env` value, without a
code change, rebuild, or data migration.

Keep the existing transfer behavior untouched: the current logic is moved into a driver module
verbatim. Do not change cron orchestration, do not add a migration, and do not refactor unrelated
QCF behavior.

## Confirmed Problem

`aigen-backend` writes PR headers and items directly into the `task_board` MySQL schema. The target
is moving to isourcing-vanilla, which exposes a public API, and direct database writes must stop.
The cutover date is not fixed, so both mechanisms must coexist in the codebase indefinitely and the
switch must be operational, not editorial.

## Baseline (`develop-dot` @ `4d30f82d`, verified)

```
sendActionToCS                     (qcfController.js:256)   ← HTTP routes + 5 cron stages
handleNineDayRfqFollowUp           (qcfController.js:3187)  ← dormant, cron call commented out
        └──────────────┬───────────────┘
                       ▼
     prosesToIsourcing(pr_number, server_groups, itemsToUpdate)   (qcfController.js:1103)
                       ▼
              task_board (6 tables, one transaction)
```

| Aspect | Value |
|---|---|
| Definition | `qcfController.js:1103`, ±425 lines, module-private, not exported |
| Call sites | Two: `qcfController.js:256` and `qcfController.js:3187` |
| Success result | `{ success: true, card_title, message }` |
| Failure result | `{ success: false, card_title, code, missing, message }` |
| Failure codes | `ISOURCING_SOURCE_HEADER_INCOMPLETE`, `ISOURCING_VALID_HEADER_NOT_FOUND`, `ISOURCING_HEADER_REPAIR_FAILED`, `ISOURCING_HEADER_VERIFICATION_FAILED`, `ISOURCING_TRANSFER_FAILED` |
| Transaction | One plain `database_isourcing` transaction; no `SERIALIZABLE`, no deadlock retry |
| Idempotency | `COUNT`-based skips; a repeated transfer returns success with `Missing items added: 0` |

This result shape is the canonical contract for both drivers, because `sendActionToCS` reads
`success`, `message`, `code`, and `missing`, and `handleNineDayRfqFollowUp` reads `success` and
`card_title`.

**`feat/enhancement-on-cron` is not adopted.** Its hardening (`SERIALIZABLE`, deadlock retry,
postcondition assertions) and its `reconcile:isourcing` CLI are therefore unavailable. Decision D-9
is void. KI-012 and KI-013 remain open, unchanged by this work.

## Strict Scope

### Runtime files to add

| File | Purpose |
|---|---|
| `src/services/isourcing/drivers/database.driver.js` | Receives `prosesToIsourcing` and its owned helpers by a pure move |
| `src/services/isourcing/isourcingTransfer.port.js` | Resolver, input validation, result-shape guard, structured logging |
| `src/services/isourcing/drivers/api.driver.js` | API driver: request builder, idempotency key, retry classification, error mapping |
| `src/api/isourcing.api.js` | Axios instance — base URL, timeout, Basic Auth, credential redaction |
| `src/const/isourcing-transfer.js` | Frozen `TRANSFER_DRIVER` and the canonical error-code set |

### Runtime files to modify

| File | Change |
|---|---|
| `src/controllers/qcfController.js` | Remove the moved function and its owned helpers; route both call sites through the port |
| `config.js` | Joi schema for 7 variables plus an `isourcing` config block |
| `src/helper/featureFlag.js` | Single read point for the driver value, following the `GEMS_MANUAL_PO_FLOW` precedent |
| `app.js` | Log the active driver once at boot |
| `src/cron.js` | Log the active driver once at boot |

`.env.example` gains a documented section with placeholder values only.

### Test files to add

| File | Covers |
|---|---|
| `tests/config/isourcingDriverConfig.test.js` | Default, both valid values, unknown value, missing conditional configuration |
| `tests/services/isourcingTransferPort.test.js` | Delegation, input validation, result-shape guard, log emission |
| `tests/services/isourcingApiDriver.test.js` | Success, already-exists, 4xx, 5xx, 429, timeout, retry bounds, idempotency key, credential redaction |
| `tests/services/isourcingDriverParity.test.js` | Both drivers return the same result shape |

### Regression net for the extraction

These two existing files must pass **unchanged** through Phases 0–2:

- `tests/controllers/qcfController.manualSourcingHeader.test.js`
- `tests/repository/qcfLibrary.isourcingTransaction.test.js`

### Required knowledge-base updates

- `aigen-ai/specs/active/isourcing-transfer-driver/spec.md` — status per phase.
- `aigen-ai/specs/active/isourcing-transfer-driver/tasks.md` — checkboxes.
- `aigen-ai/specs/active/isourcing-transfer-driver/test-plan.md` — created during implementation,
  mapping each acceptance criterion to a concrete test file.
- `aigen-ai/index/file-index.md`, `function-index.md`, `test-index.md` — new modules.
- `aigen-ai/context/project-state.md` — driver layer status and the active `.env` value per
  environment.
- `aigen-ai/context/known-issues.md` — record the two-mode data non-parity (OI-6) and the absence
  of a reconciliation tool (OI-7).

### Explicitly out of scope

| Item | Reason |
|---|---|
| Adopting `feat/enhancement-on-cron` | Reviewed and judged unnecessary |
| Behavior of the moved transfer logic | Spec contract item 9; it becomes the `database` driver unchanged |
| `AGENTS.md` command list correction | Real but separate; it documents CLIs that exist only on the abandoned branch |
| `task_board` schema and unique constraints | KI-012 / KI-013 residual risk is unchanged by this work |
| `aigen-frontend` | The `sendActionToCS` HTTP contract does not change |
| `aigen-import-pr` | Verified read-only against `task_board` |
| Historical data migration or backfill | Not required by the switch |

## Behavioral Contract

The full contract is spec items 1–18. The points that constrain implementation ordering:

1. Unset value resolves to `database`; an unrecognized value fails at boot; there is no silent
   fallback.
2. The value is read once per process, through one helper. No `process.env` read for this value
   outside that helper.
3. The port is the only route to iSourcing; both drivers return the identical result shape and the
   identical canonical error codes.
4. The API driver sends one request per PR carrying header plus all items, keyed by a deterministic
   idempotency key derived from `card_title` plus the sorted `item_code` list.
5. Retries cover transient failures only — timeout, network, 5xx, 429 — with bounded backoff.
6. Partial success is treated as failure.
7. There is no automatic fallback between drivers. A failed transfer leaves Aigen status, milestone
   log, and token untouched.
8. In `api` mode there is no `task_board` write, no category/CL resolution, no `exports_data`, and
   no `milestone_config` read.
9. Credentials never reach logs, error messages, Sentry payloads, or HTTP responses.

## Detailed Implementation Steps

### Phase 0 — Extraction (pure move, no behavior change)

1. Create `src/services/isourcing/drivers/database.driver.js`.
2. Move `prosesToIsourcing` (`qcfController.js:1103`) into it verbatim, together with the helpers it
   owns: `hasHeaderValue`, `validateISourcingHeader`, `buildHeaderMetadata`,
   `failedISourcingTransfer`, `ensureActiveAdminHeader`.
3. Keep the positional signature `(pr_number, server_groups, itemsToUpdate)` and the result shape
   exactly as they are.
4. Update both call sites to import the moved function: `qcfController.js:256` and
   `qcfController.js:3187`.
5. Confirm no other module referenced the removed helpers.
6. Review the diff: `qcfController.js` should show removal and re-import only, with no altered logic
   inside the moved block.

**Exit criteria.** `npm test` green with no edits to existing test expectations. A required test
edit means the move was not pure — revert and redo rather than adjusting the test.

### Phase 1 — Configuration seam (no behavior change)

1. Add `src/const/isourcing-transfer.js` with the frozen driver and error-code constants.
2. Extend the Joi schema in `config.js`: `ISOURCING_TRANSFER_DRIVER` valid `database`/`api`
   defaulting to `database`; `ISOURCING_API_BASE_URL`, `ISOURCING_API_TRANSFER_PATH`,
   `ISOURCING_API_USERNAME`, `ISOURCING_API_PASSWORD` required **only when** the driver is `api`;
   `ISOURCING_API_TIMEOUT_MS` default `10000`; `ISOURCING_API_MAX_RETRY` default `2`.
3. Add the `isourcing` block to the `config.js` export with a comment stating it must be identical
   in the app and cron environments.
4. Add the single read point beside `src/helper/featureFlag.js`.
5. Document the seven variables in `.env.example`.
6. Log the active driver once at boot in `app.js` and `src/cron.js`.
7. Add `tests/config/isourcingDriverConfig.test.js`.

**Exit criteria.** `npm test` green. No runtime path consumes the value. Deployable with zero
behavioral effect.

### Phase 2 — Port with a single registered driver

1. Add `src/services/isourcing/isourcingTransfer.port.js`: validate the input and preserve the
   existing failure behavior; resolve the driver, accepting an optional `scope` argument that is
   currently ignored per decision D-8; guard the returned result shape; emit one structured log line
   with driver, `card_title`, item count, result or code, and duration; tag Sentry with the driver
   on failure.
2. Point both call sites at the port instead of importing the driver directly.
3. Grep-verify that only the port imports a driver.
4. Add `tests/services/isourcingTransferPort.test.js`.

**Exit criteria.** `npm test` green **with no edits to existing test expectations**.

### Phase 3 — API driver skeleton, contract stubbed

1. Add `src/api/isourcing.api.js`: axios instance with base URL, timeout, and Basic Auth built from
   username and password at runtime, plus an explicit redaction step for error serialization.
2. Add `src/services/isourcing/drivers/api.driver.js`: request builder for `header` + `items`
   following §3.3 and §3.4 of
   `aigen-reports/20260822-234523-isourcing-public-api-requirements-for-insert.md`; deterministic
   idempotency key; retry classification honoring `Retry-After`; response mapper to the canonical
   result shape including the "already exists" message form; error mapping table with unresolved
   entries marked `TODO-CONTRACT`.
3. Omit everything decisions D-4 and D-5 removed: no board placement fields, no split counter, no
   category/CL resolution, no `exports_data`, no `milestone_config` read.
4. Register the driver in the resolver.
5. Confirm that selecting `api` with incomplete configuration fails at boot, not at transfer time.
6. Add `tests/services/isourcingApiDriver.test.js` and `tests/services/isourcingDriverParity.test.js`,
   always against a mocked HTTP layer — never a real endpoint.

**Exit criteria.** `npm test` green. `database` remains the default in every environment.

### Phase 4 — Contract v1.0 implementation

Unblocked 2026-08-24. The contract is asynchronous, so this is no longer a mapping exercise: it
adds a migration, a persistence layer, a new cron stage, and a third outcome on the canonical
result. Four steps, each shippable while the switch stays on `database`.

**4a — Payload and mapping rewrite.** Rebuild `buildHeaderPayload` as `pr_library` and
`buildItemsPayload` as `pr_items` using iSourcing's own field names (contract §3.4, §3.5). Source
the three assignment fields from `rfq_library`: `pr_material_group_number`,
`external_material_group`, `sap_material_number` — all verified present on 2026-08-24, all
nullable, so log per item when any is missing. Send `pr_number` without a prefix, `company_code`
as a string, `line_item` as an integer, and repeat `server_group` on every item. Drop `source`,
`idempotency_key`, `aigen_item_id`, and the `header`/`items` property names from the body; the key
moves to the `Idempotency-Key` header. Never send `is_oa`, `partial_status`, or `acc_assign`.
Reject payloads above 512,000 bytes before sending. Rewrite `classifyError`: retry only network,
timeout, and `503`; never `400`, `401`, `403`, `404`, `413`, or `500`. Default the transfer path to
`/api/public/isourcing/aigen/import-pr`.

**4b — Persistence.** Migration for `isourcing_transfer_requests` on the primary schema with a
unique index on `idempotency_key`, plus a repository for insert, lookup by status, and update.
Derive the key from `pr_number` + `server_group` + sorted line items + `attempt`.

**4c — Pending outcome and reconciliation stage.** Add `pending` to the canonical result and the
port's shape guard. `202` returns `pending` and persists the request without touching Aigen state.
Teach `sendActionToCS` and the five cron handlers to stop on `pending` and leave the token active.
Add a reconciliation cron stage that polls the status endpoint for stored `queued` requests:
`succeeded` performs the deferred Aigen mutation and token deactivation exactly once, `failed`
records the code and re-sends with a fresh key when transient (max 2), `queued` waits. Register it
in `CRON_STAGES` and `runCronTasks`. Map `409 PR_ALREADY_EXISTS` to idempotent success with its own
log marker.

**4d — Tests.** Rebuild the API driver suite from the contract, add reconciliation-stage tests,
update the parity suite so `pending` is asserted as api-only, and add repository tests for the new
table.

**Exit criteria.** `npm test` green. No `TODO-CONTRACT` markers remain. `database` still the
default everywhere. The migration has been run only against a local database.

**Note on scope.** This step touches `sendActionToCS` and the five cron handlers — the callers
every earlier phase deliberately left alone. That is unavoidable: an asynchronous transfer cannot
report a terminal result, so the decision to defer the Aigen mutation has to live in the caller.

### Phase 5 — Rollout and cutover (DevOps + backend, no code change expected)

1. Confirm OI-6 with the owners of the legacy iSourcing dashboard: PRs transferred through the API
   will have no `exports_data` row. Cutover does not proceed without this confirmation.
2. Resolve OI-7: agree a read-only verification query set with the DBA, since no reconciliation CLI
   exists on this baseline. Capture a pre-cutover snapshot with it.
3. Switch a non-production environment to `api` and exercise the five cron stages plus the HTTP
   route.
4. Production switch: change the value in **both** the app and cron environments, then restart
   both. A partial switch puts the two processes on different mechanisms.
5. Post-cutover verification against the pre-cutover snapshot.
6. After a stabilization period, revoke `INSERT`/`UPDATE` grants on `task_board` for the
   `aigen-backend` account. **Preserve read access for `aigen-import-pr`**, which still selects
   from `item_card`, `category_group`, and `users`.

**Rollback.** Set `ISOURCING_TRANSFER_DRIVER=database` and restart both processes. No deploy, no
migration, no data repair. Rollback stops being a single step once write grants are revoked, so
keep the grants until confidence is established.

## Acceptance Criteria

Spec criteria AC-1 through AC-14, verified as follows:

| AC | Phase | Verification |
|---|---|---|
| AC-1 backward-compatible default | 0, 1, 2 | Unchanged existing transfer tests plus the config unit test |
| AC-2 switch without code change | 3 | Driver selection test; confirmed operationally in Phase 5 |
| AC-3 invalid value fails fast | 1 | Config unit test |
| AC-4 missing API config fails at boot | 1, 3 | Config unit test |
| AC-5 callers are driver-agnostic | 2 | Grep verification plus code review |
| AC-6 identical contract across drivers | 3 | Parity test |
| AC-7 no Aigen mutation on failure | 3 | Cron handler tests with a failing driver |
| AC-8 idempotency | 3, 4 | Idempotency key test; reconfirmed in Phase 4 |
| AC-9 retry classification | 3 | Mocked HTTP tests |
| AC-10 timeout honored | 3 | Mocked HTTP test |
| AC-11 no dual write | 5 | Code review plus a database-side privilege check (no CLI available) |
| AC-12 rollback to database mode | 5 | Rehearsed in non-production |
| AC-13 credential confidentiality | 3 | Redaction test plus diff review |
| AC-14 traceability | 2 | Port log emission test |

## Verification Commands

Run from `aigen-backend`. Node pinned to `v22.14.0` per `.nvmrc`.

| Command | Purpose |
|---|---|
| `npm test` | The only automated verification available; there is no lint or build script |
| `git diff --check` | Required at final review |

Do not run `npm run run:cron`, `npm run run:sync`, migrations, or seeds as verification — all of
them mutate external state. `reconcile:isourcing` does not exist on this baseline.

## Residual Risks

| Risk | Mitigation |
|---|---|
| The Phase 0 move silently alters behavior | Pure move only; the two existing test files must pass unchanged, and the diff is reviewed for logic changes inside the moved block |
| `feat/enhancement-on-cron` is merged later and clobbers the extraction | Close or delete the branch now that it is judged unnecessary |
| No automated post-cutover reconciliation | OI-7: agree a read-only DBA query set before Phase 5 |
| Concurrency residual risk stays open | Unchanged by this work; KI-012 and KI-013 remain recorded as-is |
| The published API contract does not support single-request atomicity | Decision D-3 states it does. If not, Phase 4 stops and the atomicity decision reopens — a compensation strategy is a design change, not an implementation detail |
| App and cron environments drift to different driver values | Boot logging in Phase 1; both restarts performed in one step in Phase 5 |
| Two-mode data non-parity (`exports_data`, assignment) | OI-6 confirmation is a hard gate before Phase 5 |
| Rollback becomes multi-step after grants are revoked | Grant revocation is deliberately the last task, after a stabilization period |
| A request stays `queued` forever and its token never closes | The reconciliation stage needs a maximum age after which the request is escalated rather than polled indefinitely — decide the threshold in Phase 4c |
| Items arriving after a PR exists are silently never transferred | Contract I-3 returns `501`; covered by the manual procedure in OI-9, which must be written and owned before cutover |
| PRs land without a Category Leader | The three assignment fields are nullable; Phase 4a logs every gap, and OI-8 measures real completeness before cutover |
| The bound path proves to be different from contract §3.1 | `ISOURCING_API_TRANSFER_PATH` keeps it overridable per environment; OI-10 asks iSourcing which document wins |
| Deferring the Aigen mutation to reconciliation widens the window where a token is still active | Accepted consequence of the asynchronous contract; the token stays active by design until `succeeded` |

## Unverified at Planning Time

- The exact diff size of the Phase 0 move.
- Everything behind OI-1 through OI-7 in `spec.md`.

## Executor Completion Report (2026-08-23)

Phases 0-3 complete. Phase 4 blocked by OI-1. Phase 5 not started. No git operation was performed;
the changes sit uncommitted in the working tree.

### Baseline

`npm test` before any change: 17 suites passed, 2 failed; 141 tests passed, 11 failed, 152 total.
The two failing suites are `qcfController.dicReminder.test.js` and `rfqLibrary.dicReminder.test.js`,
already recorded in `known-issues.md`. Node in this environment is v24.12.0 while `.nvmrc` pins
v22.14.0 — the suite was not run on the pinned version.

### Phase 0 — Extraction

`prosesToIsourcing` and its five helpers moved to `src/services/isourcing/drivers/database.driver.js`
using `sed` rather than retyping, so the block is byte-identical. Result:
`git diff --stat` on `qcfController.js` showed **1 insertion, 571 deletions**, and the single added
line is the new import. `npm test` was identical to baseline with no test file edited.

### Phase 1 — Configuration seam

Added `src/const/isourcing-transfer.js`, seven Joi rules plus an `isourcing` block in `config.js`,
`getIsourcingTransferDriver` / `assertIsourcingTransferConfig` in `src/helper/featureFlag.js`, an
`.env.example` section, and a boot log in `app.js` and `src/cron.js`. Suite: 18 passed, 150 tests.

### Phase 2 — Port

Added `src/services/isourcing/isourcingTransfer.port.js` and pointed both call sites at it. Suite:
19 passed, 165 tests, existing expectations untouched.

### Phase 3 — API driver skeleton

Added `src/api/isourcing.api.js` and `src/services/isourcing/drivers/api.driver.js`, registered in
the port. Suite: 21 passed, 187 tests. Payload and error mapping carry `TODO-CONTRACT` markers.

### Deviations from the plan

1. **`Sentry.withScope` replaced with `Sentry.captureException(error, { tags })`.** The first port
   implementation used `withScope`, which broke `qcfController.manualSourcingHeader.test.js`: its
   Sentry mock exposes only `captureException`, matching the codebase where `captureException`
   accounts for all 100 existing calls. The port was changed to the established API rather than the
   existing test. No pre-existing test was edited at any point.
2. **Drivers are loaded lazily** inside `resolveDriver` instead of being required at module load,
   so only the selected driver's dependencies are pulled in.
3. **`database.driver.js` exports a `transfer` alias** alongside the original name, so both drivers
   present the same interface. This is a footer-only addition; the moved block was not touched.

### Verification performed

- `npm test` after every phase — see `test-plan.md` for the per-phase table.
- `node --check` on every changed and added runtime file.
- `git diff --check` — clean.
- `node -e "require('./src/utils/envLoader'); require('./config')"` against the real `.env`:
  config loads, driver resolves to `database`, API block unconfigured.
- `grep -rln "drivers/database.driver\|drivers/api.driver" src app.js` — only the port matches.

### Left unverified

- The real iSourcing endpoint, payload field names, and error codes (OI-1).
- The axios timeout path against a genuinely slow endpoint.
- Boot behavior of `app.js` and `src/cron.js` as running processes; neither was started.
- The suite on the pinned Node version.
- Anything requiring a real database: no cron, migration, or mutating integration test was run.

### Finding worth recording

In `api` mode the iSourcing **database connection is still opened**, because
`src/repository/qcfLibrary.repository.js` imports `src/config/database_isourcing` at module load and
the API driver needs that repository for its source reads. Only writes stop, not the connection.
Phase 5's grant revocation removes `INSERT`/`UPDATE` but leaves `SELECT`, so this does not block
cutover — but "no task_board access in api mode" is not accurate as stated. Recorded as KI-014.
