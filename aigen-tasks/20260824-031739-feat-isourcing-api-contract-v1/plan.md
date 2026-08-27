# Plan: iSourcing API Contract v1.0 — Phase 4 Implementation

- Created: 2026-08-24 03:17:39 +07:00
- Status: Implemented and unit-verified 2026-08-24. Migration written but not applied — see the
  completion report.
- Primary repository: `aigen-backend`
- Target branch at planning time: `develop-dot`
- Baseline: Phases 0-3 of the transfer driver, present in the working tree, uncommitted
- Runtime source files: 15 (5 new, 10 modified) plus 2 migration files and `.env.example`
- Test files: 3 new, 3 updated
- Database mutation authorized: No for production. One migration, local database only.
- Specification: `aigen-ai/specs/active/isourcing-transfer-driver/spec.md`
- Phase checklist: `aigen-ai/specs/active/isourcing-transfer-driver/tasks.md` (Phase 4)
- Umbrella plan: `aigen-tasks/20260823-151149-feat-isourcing-transfer-driver/plan.md`
- Contract: `isourcing/isourcing-docs/public-api-contract-pr-transfer.md` v1.0

> This plan covers **Phase 4 only**. Phases 0-3 are done; Phase 5 stays in the umbrella plan.
> `spec.md` remains authoritative for the behavioral contract.

## Objective

Make the `api` driver conform to contract v1.0 so it can be switched on by changing one `.env`
value. The contract is asynchronous, so this is not a mapping exercise: it adds persistence, a cron
reconciliation stage, a third outcome on the canonical result, and one migration.

The `database` driver stays untouched and remains the default everywhere.

## What changed since the umbrella plan

The umbrella plan assumed Phase 4 would fill in field names and an error table. Contract v1.0
invalidates four assumptions (spec amendments A-1 to A-8). The three that drive this plan:

1. `202 Accepted` means queued, not stored. The terminal result comes from a separate status
   endpoint, so the transfer can no longer report a final answer in one call.
2. There is no upsert. A PR that already exists cannot receive later items (`501`); a new key over
   an existing PR returns `409 PR_ALREADY_EXISTS`.
3. Auto-assignment needs three item fields together. All three exist on `rfq_library`
   (`pr_material_group_number`, `external_material_group`, `sap_material_number`, verified
   2026-08-24) and all three are nullable.

## Strict Scope

### Runtime files to add

| File | Purpose |
|---|---|
| `migrations/aigen/<ts>-create-isourcing-transfer-requests.up.sql` / `.down.sql` | Table for the two-step protocol |
| `src/models/default/isourcingTransferRequest.js` | Sequelize model for that table |
| `src/repository/isourcingTransferRequest.repository.js` | Insert, lookup by status, update |
| `src/services/isourcing/isourcingReconciliation.service.js` | Poll the status endpoint, complete or re-send |

### Runtime files to modify

| File | Change |
|---|---|
| `src/services/isourcing/drivers/api.driver.js` | Body rewritten to contract shape; retry classification corrected; `pending` returned on `202` |
| `src/api/isourcing.api.js` | Add an unauthenticated client for the status endpoint |
| `src/services/isourcing/isourcingTransfer.port.js` | Accept `pending` in the result-shape guard and in the log line |
| `src/const/isourcing-transfer.js` | Add the outcome vocabulary and the contract error codes |
| `src/controllers/qcfController.js` | `sendActionToCS` stops before the Aigen transaction on `pending`; nine-day path likewise |
| `src/services/prService.js` | DIC, CS, OE handlers skip status mutation and token deactivation on `pending` |
| `src/services/qcfService.js` | CL and Management handlers, same |
| `src/cron.js` | Register and run the reconciliation stage |
| `src/const/cron-stages.js` | Add `RECONCILE` |
| `config.js` | Default transfer path; add status path; keep max retry at 2 |
| `.env.example` | Document the new and defaulted variables |

### Test files

New: `tests/services/isourcingReconciliation.test.js`,
`tests/repository/isourcingTransferRequest.test.js`, plus a contract-shape suite folded into the
rewritten driver tests.
Updated: `tests/services/isourcingApiDriver.test.js` (rebuilt from the contract),
`tests/services/isourcingDriverParity.test.js` (`pending` asserted api-only),
`tests/config/isourcingDriverConfig.test.js` (new variables).

Regression net that must keep passing unchanged:
`tests/controllers/qcfController.manualSourcingHeader.test.js`,
`tests/repository/qcfLibrary.isourcingTransaction.test.js`, and the five expiry-handler suites.

### Explicitly out of scope

| Item | Reason |
|---|---|
| `database` driver behavior | Spec contract item 9 |
| `aigen-frontend` | See the open decision in step 4c — additive response field only |
| `aigen-import-pr` | Read-only against `task_board` |
| Production migration run | Local only; Phase 5 owns deployment |
| Manual procedure for late-arriving items | OI-9, a process document, not code |

## Detailed Implementation Steps

### 4a — Payload and mapping rewrite

1. Extend `src/const/isourcing-transfer.js`: outcome vocabulary (`success`, `pending`, `failed`)
   and the contract's own codes (`IDEMPOTENCY_KEY_MISSING`, `PAYLOAD_INVALID`,
   `INVALID_CREDENTIALS`, `GROUP_SCOPE_VIOLATION`, `CONFIG_NOT_FOUND`, `REQUEST_NOT_FOUND`,
   `PR_ALREADY_EXISTS`, `PAYLOAD_TOO_LARGE`, `CONFIGURATION_INVALID`, `KAFKA_UNAVAILABLE`) plus the
   terminal set (`KAFKA_PUBLISH_FAILED`, `ASSIGNMENT_ERROR`, `PERSIST_ERROR`, `REQUEST_FAILED`).
2. Rewrite `buildHeaderPayload` to emit `pr_library` with contract §3.4 names. `pr_number` without
   prefix, `server_group`, `company_code` as a string, `release_date`, `src_value`, `src_currency`,
   `convert_value`, `convert_currency`, `description`, `requestor_user`, `requestor_email`,
   `creator_user`, `creator_email`, `purchase_group_code`, `purchase_group_name`, `risk`,
   `permit1`-`permit3`, `notes`.
3. Rewrite `buildItemsPayload` to emit `pr_items` with contract §3.5 names, sourcing the three
   assignment fields from `rfq_library`. `line_item` is an integer parsed from `item_code`; every
   item repeats the header's `server_group`.
4. Log one line per item that is missing any of the three assignment fields, naming which are
   missing. Not an error — iSourcing still creates the PR, without a Category Leader.
5. Remove `source`, `idempotency_key`, `aigen_item_id`, and the `header`/`items` property names
   from the body. Send the key as the `Idempotency-Key` header. Never send `is_oa`,
   `partial_status`, or `acc_assign`.
6. Reject a serialized payload above 512,000 bytes before sending, as a canonical failure.
7. Rewrite `classifyError`: retryable is network, timeout, and `503` only. `400`, `401`, `403`,
   `404`, `413`, and `500` are terminal. Keep `Retry-After` handling harmless but do not depend on
   it — the application never emits `429`.
8. **Superseded 2026-08-24 — the configured paths are `/api/public/isourcing/aigen-import-pr` and
   `/api/public/isourcing/status`; the values below came from the contract's illustrative example.**
   `config.js`: default `ISOURCING_API_TRANSFER_PATH` to `/api/public/isourcing/aigen/import-pr`,
   add `ISOURCING_API_STATUS_PATH` defaulting to `/api/public/isourcing/aigen/status`, keep
   `ISOURCING_API_MAX_RETRY` at 2 (D-17). Update `.env.example`.
9. Remove every `TODO-CONTRACT` marker this step touches.

**Exit criteria.** Driver unit tests rebuilt from the contract pass. No production behavior change:
the switch is still `database`.

### 4b — Persistence

1. `npm run migrate:create -- --db=aigen --name=create-isourcing-transfer-requests`, then fill the
   generated `.up.sql` / `.down.sql` pair. Columns per the specification's Persistence section.
   Unique index on `idempotency_key`; index on `status`.
2. Add the Sequelize model under `src/models/default/`.
3. Add the repository: `create`, `findByStatus`, `findByIdempotencyKey`, `markSucceeded`,
   `markFailed`, `incrementAttempt`.
4. Build `idempotency_key` as `pr_number:server_group:<sorted line items>:<attempt>`. The
   deterministic part keeps network retries safe; `attempt` is what allows a genuine re-send, since
   replaying a key over a failed request only returns the stored failure (contract §6).
5. Run the migration against a local database only. Record the command and result.

**Exit criteria.** Repository tests pass. Migration applies and rolls back cleanly on local.

### 4c — Pending outcome and reconciliation stage

1. Port: accept `pending` in the result-shape guard, require `request_id` on it, and include the
   outcome in the structured log line.
2. API driver: on `202`, persist the request through the repository and return `pending`. On `409
   PR_ALREADY_EXISTS`, return idempotent success with its own log marker (D-12).
3. `sendActionToCS`: on `pending`, skip the Aigen transaction entirely — no `bulkUpdateStatusRFQ`,
   no milestone log, no token deactivation.
4. **Open decision, resolve before coding this step.** `ResMocker` throws for any code other than
   200/201, and all five cron handlers construct it with the throwing default. Two ways to signal
   `pending`:
   - **(a) Recommended.** Respond `200` with an additive `transfer_status: 'pending'` field in the
     response data. `ResMocker` is untouched; handlers read the field. The HTTP contract stays
     backward compatible, and `aigen-frontend` can adopt the field later without breaking today.
   - (b) Respond `202`. Semantically correct for HTTP, but every handler must switch to a
     non-throwing `ResMocker` and branch on the code, and the frontend starts receiving a status it
     does not understand.
   Option (a) is assumed by the steps below. Changing it changes steps 5 and 6.
5. The five expiry handlers (`prService`: DIC, CS, OE; `qcfService`: CL, Management): after the
   invocation, check the pending marker. When pending, log it, leave the token active, and skip the
   status update. Every other path keeps today's behavior.
6. `handleNineDayRfqFollowUp`: same treatment on its own result branch.
7. New `isourcingReconciliation.service.js`: for every stored `queued` request, call
   `GET {statusPath}/{requestId}` without credentials.
   - `succeeded` → perform the deferred Aigen mutation and token deactivation exactly once, then
     mark the row `succeeded`.
   - `failed` → record `errorCode`; if it is in the transient terminal set and `attempt < 2`,
     re-send with an incremented `attempt` and a fresh key; otherwise stop and leave it for a human.
   - `queued` → update `last_checked_at` and leave it.
   - `404 REQUEST_NOT_FOUND` → mark failed; the request is unrecoverable.
8. Register `RECONCILE` in `src/const/cron-stages.js`, add it to `VALID_STAGES`, and run it from
   `runCronTasks` so `--stage=reconcile` works for a single-stage rehearsal.
9. Decide and implement a maximum age after which a `queued` request stops being polled and is
   escalated instead. Without it a stuck request is polled forever and its token never closes.
   Propose the threshold with the change; do not leave it unbounded.

**Exit criteria.** Reconciliation tests pass. A `pending` transfer leaves `rfq_library` and the
token untouched, and only the reconciliation stage completes it.

### 4d — Tests

1. Rebuild `isourcingApiDriver.test.js` from the contract: exact body shape, header-only
   idempotency key, `202` → `pending`, both `409` variants, `400`/`401`/`403`/`413`/`500` without
   retry, `503` and network with retry, oversized payload rejected before sending, assignment-gap
   logging, credential redaction.
2. New `isourcingReconciliation.test.js`: `queued` stays queued; `succeeded` mutates exactly once
   and a rerun does not repeat it; transient `failed` re-sends with an incremented attempt and stops
   after two; `404` marks failed; the age threshold escalates.
3. New `isourcingTransferRequest.test.js` for the repository, with a mocked Sequelize model.
4. Update `isourcingDriverParity.test.js`: `success` and `failed` shapes stay identical across
   drivers; `pending` is asserted as api-only and never produced by the database driver.
5. Update `isourcingDriverConfig.test.js` for the new and defaulted variables.
6. Confirm the regression net still passes with no test edits.

**Exit criteria.** `npm test` green apart from the two pre-existing DIC reminder suites. No
`TODO-CONTRACT` markers remain.

## Acceptance Criteria

Spec AC-15 to AC-20 are introduced by this phase; AC-1 to AC-14 must not regress.

| AC | Step | Verification |
|---|---|---|
| AC-15 contract-shaped payload | 4a | Driver body-shape tests |
| AC-16 `202` is not success | 4c | Driver test plus handler tests asserting no Aigen mutation |
| AC-17 reconciliation completes once | 4c, 4d | Reconciliation tests including rerun |
| AC-18 re-send uses a fresh key | 4b, 4c | Attempt-increment test |
| AC-19 retry classification | 4a | Per-status driver tests |
| AC-20 assignment gaps visible | 4a | Log assertion with missing fields named |
| AC-1 to AC-14 | all | Existing suites unchanged |

## Verification Commands

Run from `aigen-backend`. Node pinned to `v22.14.0` per `.nvmrc`; this environment currently has
v24.12.0.

| Command | Purpose |
|---|---|
| `npm test` | The only automated verification available |
| `npm run migrate:create -- --db=aigen --name=create-isourcing-transfer-requests` | Generate the migration pair |
| `npm run migrate -- up --db=aigen` | **Local database only** |
| `npm run migrate -- down --db=aigen 1` | Verify the rollback |
| `git diff --check` | Required at final review |

Do not run `npm run run:cron` or `npm run run:sync` as verification — both mutate external state.
There is no lint or build script.

## Residual Risks

| Risk | Mitigation |
|---|---|
| A request stays `queued` forever and its token never closes | Step 4c.9 makes the age threshold mandatory, not optional |
| Deferring the Aigen mutation widens the window where a token stays active | Accepted consequence of the asynchronous contract |
| The pending marker leaks into the frontend response | Step 4c.4 option (a) is additive; the frontend ignores unknown fields today |
| Items arriving after a PR exists are silently never transferred | Contract returns `501`; OI-9 manual procedure must exist before cutover |
| PRs land without a Category Leader | Step 4a.4 logs every gap; OI-8 measures real completeness before cutover |
| The bound path differs from contract §3.1 | Path stays overridable per environment; OI-10 asks which document wins |
| Touching the five expiry handlers regresses expiry behavior | Their five suites are part of the regression net and must pass unedited |

## Unverified at Planning Time

- Real completeness of `external_material_group` and `sap_material_number` on transfer-path items
  (OI-8).
- The non-production base URL (OI-5) — D-16 makes it a hard gate before any real call.
- Whether contract §3.1's path or §13's "set at configuration time" governs (OI-10).
- Behavior of the live endpoint; every test in this plan uses a mocked HTTP layer.

## Executor Completion Report (2026-08-24)

Steps 4a, 4c, and 4d complete. Step 4b is complete in code but **the migration was not applied**.
No git operation was performed; the changes sit uncommitted in the working tree.

### Suite results

| Point | Suites | Tests |
|---|---|---|
| Baseline before Phase 4 | 21 passed, 2 failed | 187 passed, 11 failed, 198 total |
| After Phase 4 | 23 passed, 2 failed | 232 passed, 11 failed, 243 total |

The two failing suites are the pre-existing DIC reminder ones, unchanged. No pre-existing test was
edited at any point; the three suites that briefly failed mid-phase were the Phase 3 tests this
plan explicitly rewrites.

### What was built

- **4a.** `api.driver.js` rebuilt: `pr_library` + `pr_items` bodies with iSourcing's field names,
  `pr_number` without prefix, `company_code` as a string, integer `line_item`, `server_group`
  repeated per item, the three assignment fields sourced from `rfq_library`, absent optional values
  omitted rather than sent as null, `Idempotency-Key` as a header, 512,000-byte pre-send check, and
  a retry classifier that retries only network, timeout, and `503`.
- **4b.** Migration pair `20260823202433-create-isourcing-transfer-requests`, the
  `isourcingTransferRequest` model, and its repository with a `pr_number:server_group:items:attempt`
  key builder.
- **4c.** `pending` added to the canonical result and the port's guard; `202` persists the request
  and returns `pending`; `409 PR_ALREADY_EXISTS` maps to idempotent success; `sendActionToCS`
  returns `200` with `transfer_status: 'pending'` and skips the Aigen transaction; all six cron
  invocation sites leave their token active on pending; new `reconcile` stage wired into
  `CRON_STAGES`, `VALID_STAGES`, and `runCronTasks`, and it only runs on the `api` driver.
- **4d.** 27 driver tests, 21 port tests, 13 reconciliation tests, 17 repository tests, 7 parity
  tests.

### Deviations from the plan

1. **`notes` is carried through an options argument, not the positional signature.** The port's
   fourth parameter became `options` (`scope`, `notes`, `reason`, `itemIds`, `rfqNumber`,
   `vendorBatch`, `attempt`). Callers that pass nothing are unaffected.
2. **The reconciliation service needed more stored context than the plan listed.** Finishing the
   deferred Aigen work requires the item ids and the sourcing reason/notes, so `item_ids`,
   `sourcing_reason`, and `sourcing_notes` were added to the table before it was ever applied.
3. **`getItemsByCardTitle` is reused instead of adding a repository function.** It already returns
   full `rfq_library` rows, which carry all three assignment fields. `getDetailItemCard` does not —
   it projects a fixed attribute list that omits them.
4. **The stale-request threshold is configurable, not hard-coded** — `ISOURCING_QUEUED_MAX_AGE_HOURS`,
   default 48. Step 4c.9 required a bound; making it an env value keeps it tunable without a deploy.

### Verification performed

- `npm test` after each step; final 23/25 suites, 232/243 tests.
- `node --check` on every changed and added runtime file.
- `git diff --check` — clean.
- `grep -rn "TODO-CONTRACT" src tests` — none remain.
- Read-only database check confirming `isourcing_transfer_requests` does **not** exist and the
  failed migration attempt left the schema unchanged.

> **Update 2026-08-24:** resolved. The team handled the blocking duplicate data and the migration
> ran on local; the applied schema was verified read-only and matches the current file, including
> the later R-1/R-2 columns. The section below is kept as the record of what was blocked and why.

### Migration not applied — blocking Phase 5 (resolved 2026-08-24)

`npm run migrate -- up --db=aigen` stops before reaching this migration. The runner first tries the
older pending `20260813153052-add-unique-index-rfq-library-pr-item-vendor`, which fails with
`ER_DUP_ENTRY` on `rfq_library.uniq_rfq_pr_item_vendor` for
`1100013946-1-100194` — pre-existing duplicate data in this local database, unrelated to this work.

Consequences:

- The table SQL is **unverified against a real database**. Column types, the unique index, and the
  rollback have never executed.
- The repository and the reconciliation stage are only unit-verified against mocks.
- Resolving the duplicate rows is a data decision, not an implementation one, so it was left alone.
  Someone who knows whether those `rfq_library` rows are legitimate duplicates has to decide.

### Left unverified

- The migration, per above.
- The live iSourcing endpoint. Every test uses a mocked HTTP layer.
- Real completeness of `external_material_group` and `sap_material_number` on transfer-path items
  (OI-8) — the driver logs each gap, but no measurement was taken.
- `app.js` and `src/cron.js` as running processes; neither was started.
- The suite on the pinned Node version — this environment runs v24.12.0 against a pinned v22.14.0,
  and the mysql2 `cesu8` handshake noise in the logs is a symptom of that mismatch.
