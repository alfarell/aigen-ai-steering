# Plan: iSourcing Transfer Recovery and Parity Fixes (R-1 … R-3)

- Created: 2026-08-24 15:07:02 +07:00
- Status: Implemented and unit-verified 2026-08-24. Migration still unapplied (KI-015).
- Primary repository: `aigen-backend`
- Target branch at planning time: `develop-dot`
- Baseline: Phases 0-4 of the iSourcing transfer driver, uncommitted in the working tree
- Runtime source files: 7 (1 new, 6 modified) plus the 2 unapplied migration files
- Test files: 1 new, 4 updated
- Database mutation authorized: No for production. Migration edits only; still unapplied.
- Source of findings: code review of 2026-08-24, findings R-1, R-2, R-3
- Specification: `aigen-ai/specs/active/isourcing-transfer-driver/spec.md`
- Preceding plan: `aigen-tasks/20260824-031739-feat-isourcing-api-contract-v1/plan.md`

## Sequencing constraint — read first

`migrations/aigen/20260823202433-create-isourcing-transfer-requests` has **never been applied**
(blocked by KI-015). While that remains true, R-1 and R-2 can change the table by editing that
migration in place. The moment anyone applies it, the same changes cost a second migration and a
backfill.

**Do this work before unblocking KI-015**, or accept the extra migration.

## Objective

Remove the permanent stuck state R-1 describes, close the `status_dic` divergence in R-2, and put
the caller-side `pending` logic behind tests as R-3 requires. Nothing else about the transfer
driver changes, and `database` stays the default.

## Findings being fixed

| ID | Finding | Severity |
|---|---|---|
| R-1 | A stored `failed` attempt-0 row permanently blocks resubmission and makes the expiry handler fail every run forever | High |
| R-2 | `status_dic` is never set on the API path, diverging from the database driver | Medium |
| R-3 | The six caller-side `pending` branches have no test coverage | Medium |

## R-1 — Root cause

The idempotency key is versioned by `attempt`, but only `reconcileRequest` ever increments it, and
only when the API itself reports `failed`. Every expiry handler calls the transfer with `attempt: 0`.

Once the attempt-0 row is `failed` — either from exhausting the two re-sends or from the
`RECONCILE_TIMEOUT` escalation — the driver's `findByIdempotencyKey` short-circuits to that stored
failure without ever calling the API. The token stays active, so the handler retries next run, hits
the same stored failure, and loops. `findQueued` only returns `queued` rows, so reconciliation never
touches it again. Recovery today requires editing the table by hand.

### Design

Attempt selection moves out of the caller and into the driver, derived from stored state rather
than defaulted:

1. Add a `business_key` column — `pr_number:server_group:<sorted line items>`, no attempt — with an
   index. The existing `idempotency_key` stays as-is and keeps its unique constraint.
2. Before building the key, the driver looks up the latest row for that `business_key`:
   - none → `attempt = 0`, submit.
   - `queued` → return `pending` from the stored row, no API call. (unchanged behavior)
   - `succeeded` → return success, no API call. (unchanged behavior)
   - `failed` and `attempt < ISOURCING_API_MAX_RESEND` → `attempt + 1`, submit.
   - `failed` and attempts exhausted → mark the row `exhausted` and return a terminal failure.
3. Add `exhausted` to the `status` ENUM. `findQueued` already filters on `queued`, so exhausted rows
   stay out of the poll set, and the driver refuses to resubmit them.
4. Emit the alert once, on the transition into `exhausted` — not on every subsequent run. This is
   what stops the churn while keeping the work visible.
5. `escalateStaleRequests` routes through the same decision instead of writing `failed` directly, so
   a stale attempt-0 row can still escalate to attempt 1 rather than dead-ending.

The token deliberately stays active for an `exhausted` transfer. Closing it would silently discard
converted work; leaving it active with a distinct status and a single alert is the honest state.
Releasing it is an operator decision, which is why step 6 gives them a query rather than a button.

### Steps

1. Edit the unapplied migration: add `business_key VARCHAR(255) NULL` plus
   `KEY idx_isourcing_transfer_business_key (business_key)`, and extend the `status` ENUM to
   `('queued','succeeded','failed','exhausted')`. Mirror both in
   `src/models/default/isourcingTransferRequest.js`.
2. `isourcingTransferRequest.repository.js`: add `buildBusinessKey({ prNumber, serverGroup,
   lineItems })`, reuse it inside `buildIdempotencyKey`, add `findLatestByBusinessKey`, and add
   `markExhausted`. Delete `findLatestByPr` — it is dead code today and is superseded.
3. `api.driver.js`: replace the `options.attempt ?? 0` default and the `findByIdempotencyKey`
   short-circuit with the decision in the design above. Persist `business_key` on create. Return
   `ISOURCING_TRANSFER_FAILED` with an `exhausted` marker in the message when attempts are spent.
4. `isourcingReconciliation.service.js`: `resendFailedTransfer` stops passing an explicit `attempt`
   and lets the driver decide; `escalateStaleRequests` calls the same path.
5. Add `ISOURCING_API_MAX_RESEND` (default 2) to `config.js` and `.env.example`, replacing the
   hard-coded `MAX_RESEND_ATTEMPTS` so the cap is tunable alongside `ISOURCING_API_MAX_RETRY`.
6. Document the operator query for `status = 'exhausted'` in the spec's verification section — with
   no reconciliation CLI (D-9 void), a query is the only way to find them.

**Exit criteria.** A failed attempt-0 row no longer blocks resubmission; attempts escalate to the
cap and then stop calling the API; the alert fires once; `npm test` green.

## R-2 — Root cause

The database driver's DIC path sets `status_dic = PENDING` immediately after conversion. On the API
path the handler returns early on `pending`, and `finalizeSucceededTransfer` never replicates it,
so the field stays `null`.

The items are still excluded from re-pickup because `excludeFinishedItems` filters on
`tipe_rfq = isourcing`, so this is a data divergence rather than a workflow leak — but it is
undocumented and would mislead anyone reading `status_dic` for reporting.

### Design

The deferred finalization needs to know which stage produced the transfer. Carry it on the row
rather than inferring it.

### Steps

1. Add `origin_stage VARCHAR(20) NULL` to the unapplied migration and the model.
2. Each expiry handler adds `origin_stage` to the `req.body` it already builds: `dic`, `cs`, `oe`,
   `cl`, `management`.
3. `sendActionToCS` forwards `req.body.origin_stage` into the transfer options; `api.driver.js`
   persists it.
4. `finalizeSucceededTransfer` applies the stage-specific follow-up after the shared work — for
   `dic`, `rfqLibrary.update({ status_dic: STATUS_DIC.PENDING })` scoped to the stored `item_ids`,
   inside the existing transaction. Other stages have no extra follow-up today; the switch makes
   that explicit rather than implicit.
5. The nine-day path stays out of scope: its cron invocation is commented out. Record in the spec
   that its post-success work is not replicated on the API driver, so nobody re-enables it assuming
   parity.

**Exit criteria.** A DIC transfer reconciled as `succeeded` leaves `status_dic = PENDING`, matching
the database driver.

## R-3 — Tests for the caller-side pending logic

The five expiry suites mock `executeSystemManualSourcing` as an empty `jest.fn()`, so the `pending`
branches never execute. The mock has to start writing to the `ResMocker` it is handed.

### Steps

1. In each of `prService.handleExpiredDICReview`, `prService.handleExpiredCSReview`,
   `prService.handleExpiredOERevision` (new suite needed), and `qcfService.expiredApprovals`, change
   the manual-sourcing mock so it can populate the passed response object, then add cases:
   - pending → token **not** deactivated, no status mutation, loop continues to the next token.
   - success → today's behavior, unchanged.
2. New `tests/controllers/qcfController.pendingTransfer.test.js`: `sendActionToCS` with a driver
   returning `pending` responds `200` with `transfer_status: 'pending'` and a `request_id`, and
   calls neither `bulkUpdateStatusRFQ` nor either token store.
3. Extend `isourcingApiDriver.test.js` for R-1: no stored row → attempt 0; stored `failed` below the
   cap → attempt incremented and the API called; stored `failed` at the cap → no API call, row
   marked `exhausted`, terminal failure returned; stored `exhausted` → no API call.
4. Extend `isourcingReconciliation.test.js`: a stale attempt-0 row escalates to a new attempt rather
   than dead-ending; the exhausted alert fires once, not per run.

**Exit criteria.** Every one of the six caller sites has a pending assertion, and R-1's escalation
is covered at both the driver and reconciliation level.

## Strict Scope

### Files to modify

| File | Change |
|---|---|
| `migrations/aigen/20260823202433-…up.sql` | `business_key`, `origin_stage`, `exhausted` in the ENUM, one index |
| `src/models/default/isourcingTransferRequest.js` | Mirror the three schema changes |
| `src/repository/isourcingTransferRequest.repository.js` | `buildBusinessKey`, `findLatestByBusinessKey`, `markExhausted`; remove `findLatestByPr` |
| `src/services/isourcing/drivers/api.driver.js` | Attempt derived from stored state; persist the two new columns |
| `src/services/isourcing/isourcingReconciliation.service.js` | Stage-specific follow-up; escalation through the shared path |
| `src/services/prService.js`, `src/services/qcfService.js` | `origin_stage` in the request body |
| `src/controllers/qcfController.js` | Forward `origin_stage` |
| `config.js`, `.env.example` | `ISOURCING_API_MAX_RESEND` |

### Out of scope

| Item | Reason |
|---|---|
| The `database` driver | Untouched throughout this work |
| KI-015 duplicate `rfq_library` rows | A data decision; it only gates applying the migration |
| Nine-day follow-up parity | Its cron invocation is commented out; documented instead |
| Releasing an `exhausted` transfer from the app | Operator decision; a query is provided, not a button |
| `aigen-frontend`, `aigen-import-pr` | No contract change reaches them |

## Verification

| Item | Method |
|---|---|
| R-1 | Driver and reconciliation unit tests covering every branch of the attempt decision |
| R-2 | Reconciliation test asserting the DIC follow-up runs inside the same transaction |
| R-3 | Six caller-site pending assertions plus the controller test |
| No regression | The two pre-existing DIC reminder suites stay the only failures; no existing test edited except the four mocks named above |
| Command | `npm test` |

The migration stays unapplied, so its SQL remains unverified. That is unchanged by this work and
still tracked as KI-015.

## Residual Risks

| Risk | Mitigation |
|---|---|
| The migration gets applied before these edits land | Stated as the sequencing constraint at the top; otherwise a second migration plus backfill |
| An `exhausted` transfer leaves its token active indefinitely | Deliberate — closing it would discard work silently. The operator query in R-1 step 6 makes the backlog visible |
| Editing the four existing test mocks masks a real regression | Only the mock's response-writing behavior changes; existing assertions stay untouched and must keep passing |
| `origin_stage` is set at five call sites and easy to miss at a sixth | The switch in `finalizeSucceededTransfer` defaults to no follow-up and logs an unknown stage rather than failing silently |

## Unverified at Planning Time

- Whether any environment has already applied the transfer-requests migration.
- Real behavior of the iSourcing status endpoint under repeated failure; the escalation path is
  designed against the contract, not against observed behavior.

## Executor Completion Report (2026-08-24)

R-1, R-2, and R-3 implemented. No git operation was performed; the changes sit uncommitted in the
working tree.

### Suite results

| Point | Suites | Tests |
|---|---|---|
| Before this work | 23 passed, 2 failed | 232 passed, 11 failed, 243 total |
| After R-1 … R-3 | 24 passed, 2 failed | 258 passed, 11 failed, 269 total |

The two failing suites remain the pre-existing DIC reminder ones, with the same 11 tests. The
sequencing constraint held: the migration was still unapplied, so the three schema changes were
edits to the existing migration rather than a second one.

### R-1 — attempt derived from stored state

`business_key` (`pr:server:items`, no attempt) and an `exhausted` status were added to the
unapplied migration and the model. The driver now looks up the latest row by business key and
decides: `succeeded` → success, `queued` → pending, `failed` below the budget → attempt + 1,
`failed` at the budget → `markExhausted` plus a one-time alert, `exhausted` → terminal failure with
no API call and no re-alert. `escalateStaleRequests` routes through the same path, so a stale
attempt-0 row can still escalate instead of dead-ending. The budget moved to
`ISOURCING_API_MAX_RESEND` (default 2), and `reconcileRequest` no longer owns it.

The RFQ token is still left active for an exhausted transfer. That is deliberate and documented:
closing it would discard unfinished work silently. `findExhausted` gives the operator the backlog.

### R-2 — stage-specific follow-up

`origin_stage` was added to the migration, the model, and the five handler request bodies, and is
forwarded by `sendActionToCS` (defaulting to `http` for a plain HTTP caller).
`finalizeSucceededTransfer` applies a `STAGE_FOLLOW_UP` entry inside the same transaction — for
`dic`, `status_dic = PENDING`. An unmapped stage logs `RECONCILE_NO_FOLLOW_UP` rather than failing
silently.

### R-3 — caller-side coverage

New `tests/controllers/qcfController.pendingTransfer.test.js` (5 tests). Pending and origin-stage
cases added to the DIC, CS, and CL/Management suites, plus a new `handleExpiredOERevision` describe
inside the CS suite. Driver tests gained an `attempt escalation (R-1)` group; the reconciliation
suite gained follow-up and stale-escalation cases.

### Deviations from the plan

1. **`findLatestByPr` was removed as planned, but `findExhausted` was added** rather than only
   documenting an operator query — the repository is where that query belongs.
2. **The OE tests live in `prService.handleExpiredCSReview.test.js`**, not a new suite: that file
   already carries the prService mock scaffold. `getOERevisionByCS` is attached inside the OE
   `describe` rather than to `mockCtrl`, because `mockCtrl` is enumerated by a `test.each` that
   covers only the CS handler's lookups — adding a key there invented a failing case.
3. **Pending mocks use `mockImplementationOnce`.** `jest.clearAllMocks()` clears calls but not
   implementations, so a persistent pending mock leaked into the next test in the same suite.

### Verification performed

- `npm test` after each finding; final 24/26 suites, 258/269 tests.
- `node --check` on every changed runtime file.
- `git diff --check` — clean.
- Grep confirming no `findLatestByPr` or `MAX_RESEND_ATTEMPTS` references remain.

### Left unverified

- ~~The migration is still unapplied.~~ **Applied on local 2026-08-24** and verified read-only:
  `business_key`, `origin_stage`, and the widened `status` ENUM are present as written. The
  `.down.sql` rollback remains untested, and other environments are still unmigrated.
- The live iSourcing endpoint; every test uses a mocked HTTP layer.
- Behavior of an exhausted transfer end to end in a running cron.
