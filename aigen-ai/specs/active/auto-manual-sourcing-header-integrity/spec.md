# Auto Manual Sourcing Header Integrity

## Status

- Delivery 1: Implemented and locally verified on 2026-07-30
- Delivery 2: Implemented and locally verified on 2026-07-30
- Delivery 3: Implemented and locally verified on 2026-07-30
- Delivery 4: Implemented and locally verified on 2026-07-30
- Delivery 5: Repair-review and first local canary implemented and verified;
  non-local database mutation remains gated
- Primary repository: `aigen-backend`
- Production data mutation: Not performed

## Problem

The manual-sourcing action is shared by authenticated HTTP routes and cron
expiry handlers. Cron callers currently construct partial Express request and
response mocks, while HTTP-only item-scope validation reads `req.params`.

The current uncommitted controller guard avoids reading absent cron params, but
the RFQ/vendor variables needed by the shared iSourcing path are no longer
declared. This causes a runtime failure before the task-board transfer.

Failures returned through the mock response are also not consistently
propagated to cron orchestration.

## Delivery 1 Goal

Provide separate, trusted HTTP and system invocation adapters while preserving
the existing sourcing, transaction, assignment, notification, and status
behavior.

## Behavioral Contract

### HTTP invocation

1. `sendActionToCS` treats all route requests as untrusted HTTP input.
2. `req.body.is_system_action` cannot bypass authorization or change the log
   actor to System.
3. iSourcing requests require route RFQ and vendor-batch scope.
4. Every submitted item ID must exist and belong to that route scope before
   any iSourcing or Aigen mutation.
5. Existing role/QCF manual-sourcing policy remains enforced.
6. Surrogate and OE routes preserve their existing behavior and do not acquire
   new task-board writes.

### System invocation

1. Cron code calls `executeSystemManualSourcing()` with item IDs, reason,
   notes, and a server-owned actor.
2. Trust is carried by a module-private invocation marker, not request data.
3. System invocation does not require Express route params.
4. Unknown item IDs fail before task-board transfer.
5. A non-2xx controller result becomes a structured
   `ManualSourcingInvocationError`.
6. The error includes safe status, code, and message metadata without tokens or
   credentials.

## Acceptance Criteria

1. Cron iSourcing invocation succeeds without `req.params`.
2. The undefined `rfqNumberForCheck` / `vendorCodeForCheck` failure is removed.
3. HTTP iSourcing without route scope fails with `ITEM_SCOPE_REQUIRED`.
4. HTTP foreign/unknown items fail with `ITEM_SCOPE_MISMATCH`.
5. A client-provided `is_system_action` does not produce a trusted system
   invocation.
6. Internal invocation failure rejects with structured metadata.
7. DIC, CS, OE, CL, and Management expiry callers use the system adapter.
8. Existing HTTP route contracts remain unchanged.
9. No Delivery 1 code changes the ordering or connection used for
   `board_card`, `item_card`, export, log, or status writes.

## Verification

- `tests/services/manualSourcingInvocationService.test.js`: 8/8 tests pass.
- Covered invocation normalization, private trusted-marker behavior, client
  body-flag rejection, HTTP/system item scope, structured success/failure,
  nine-day transfer normalization, and cron-stage failure aggregation.
- `node --check` passes for all changed runtime and test files.
- The full in-band suite completes with 6/8 suites and 53/64 tests passing.
  The two failing suites are pre-existing DIC reminder mock/model-association
  failures recorded in `aigen-ai/context/known-issues.md`.
- `git diff --check` is required at final Delivery 1 review.

## Delivery 1 Implementation

- Added `manualSourcingInvocationService` as the only adapter that can create
  a trusted cron invocation.
- Restored the database-derived RFQ/vendor variables used by the shared
  iSourcing path.
- Kept HTTP route scope and QCF policy validation in `sendActionToCS`.
- Replaced DIC, CS, OE, CL, and Management cron request mocks with the system
  adapter.
- Made per-RFQ adapter failures reject each cron stage as a structured
  `ManualSourcingStageError`.
- Routed the nine-day direct transfer through the same structured-result
  adapter.
- Did not change task-board transaction boundaries, write ordering, routing,
  assignment, or historical data.

## Delivery 2 Contract

1. `transferToISourcing()` is the single persistence path for HTTP, expiry
   cron, and nine-day transfers.
2. Target state is read and written in one managed `database_isourcing`
   `SERIALIZABLE` transaction.
3. Card and requested item rows are locked before state classification.
4. Deadlock and lock-timeout failures retry the whole target transaction up to
   three attempts.
5. A lifecycle-required active card is created before a missing active item.
6. Existing active item orphans can repair their card without inserting a
   duplicate item.
7. An existing consistent transfer returns successful
   `already_consistent`.
8. A terminal-only PR cannot receive a new active item without an approved
   reopen and returns `TERMINAL_PR_NEW_ITEM`.
9. `board_card`, `item_card`, `counter_split_pr_items`, `exports_data`,
   `pr_logs`, and `history_log_assign` writes receive the same target
   transaction.
10. A postcondition re-reads cards/items before commit and requires exactly one
    lifecycle card for each touched active item.
11. Aigen status/token updates run only after the target transaction commits.
    If the primary update fails, a rerun converges through
    `already_consistent` instead of duplicating target rows.

## Delivery 2 Verification

- `tests/services/manualSourcingTransferService.test.js`: 17 tests pass.
- `tests/repository/qcfLibrary.isourcingTransaction.test.js`: 3 tests pass.
- Delivery 1 invocation tests: 8 tests pass.
- Focused total: 29/29 tests pass.
- Failure injection covers board, split board, split counter/update, item,
  export, PR log, and history writes; every injected failure rolls back the
  managed target transaction.
- Covered new transfer, existing-card repair, exact active-item orphan repair,
  terminal guard, idempotent rerun, postcondition failure, assigned-card
  validation, deadlock classification/retry, and target connection usage.
- Full in-band suite: 8/10 suites and 74/85 tests pass. The same two
  pre-existing DIC reminder suites account for all 11 failures.
- No cron, migration, or database-mutating integration test was run.

## Delivery 3 Contract

1. New-PR and existing-PR missing items use the same pure per-item resolver.
2. Every item resolves iSearch metadata and the current iSourcing matrix from
   its own `pr_material_group_number`.
3. Missing metadata returns `SOURCE_PR_NOT_FOUND`; missing category/CL route
   returns `UNMAPPED_CATEGORY` before target writes.
4. Existing active cards are reused only when board, user, list, category
   color, material group, split role, and active status match.
5. Terminal cards are never reused as active category/CL cards.
6. `assigned_to_cl`, `send_email_to`, `is_updated`, material group, export
   assignment, history, and PR-log timestamp are derived from the same plan.
7. `exports_data.board_id` points to the exact assigned CL `board_card`, not
   an arbitrary card sharing the PR title.
8. Split updates target the newly created card ID instead of every card with a
   matching title/color.
9. Before commit, the postcondition requires exactly one category card and one
   assigned CL card and re-reads export/history/PR-log alignment.
10. Existing consistent items keep their historical assignment; only newly
    discovered items use the current matrix.
11. Terminal late items retain the Delivery 2
    `TERMINAL_PR_NEW_ITEM` behavior.

## Delivery 3 Verification

- Focused invocation, transfer, and repository tests: 37/37 pass.
- Covered pure two-material-group resolution, new multi-group transfer,
  existing-PR new-group parity, exact active-card reuse, terminal-card
  non-reuse, unmapped rollback, item/export/history/log alignment, artifact
  postcondition rollback, and all target write failure points.
- Read-only local replica audit found no duplicate
  `(server, material_group)` matrix rows and no mapped category missing its
  self-assigned CL list.
- Full in-band suite: 8/10 suites and 82/93 tests pass. The same two
  pre-existing DIC reminder suites account for all 11 failures.
- No cron, migration, production mutation, or database-mutating integration
  test was run.

## Delivery 4 Contract

1. Every expiry stage runs under an operation ID and returns a safe stage
   summary with selected RFQs, attempted transfers, classification counts, and
   failure codes.
2. Manual-sourcing observations contain RFQ, prefixed PR, stage,
   `created`/`repaired`/`already_consistent`, and error code only; request
   bodies, tokens, notes, and private links are excluded.
3. All selected stages continue running after a stage failure. The direct
   command exits non-zero after completion if any stage or health query failed.
4. Unexpected support/stage/health errors are captured through Sentry with
   operation ID and stage tags.
5. Cron reports read-only aggregate health metrics for exact no-card items,
   source-marked iSourcing rows missing a lifecycle postcondition, and possible
   primary-update retries.
6. `reconcile:isourcing` accepts optional PR/date/server/RFQ/limit filters and
   emits a JSON report with source/target IDs.
7. The scanner implements all ten lifecycle classifications in the task plan.
8. Scanner repository methods execute `SELECT` only.
9. `--repair` and `--apply` are rejected; no Delivery 4 repair path exists.
10. Delivery 5 remains the only authorized historical mutation phase.

## Delivery 4 Verification

- Combined Delivery 1-4 focused suite: 49/49 tests pass.
- Tests cover safe cron summaries, non-zero failure contract, Sentry tagging,
  all ten scanner classifications, CLI filter parsing/mutation rejection, and
  repository SELECT-only enforcement.
- Read-only scanner execution against `B1200027605`, `B1200027666`, and
  `B1200027667` completed successfully: 18 terminal split-only findings, 15
  ambiguous terminal/active lifecycle findings, 6 structurally consistent
  active Admin items, and 1 stale export reference for item 8 of
  `B1200027667`.
- Unfiltered local-replica health snapshot: 323 exact item rows with no card in
  any state, 127 source-marked iSourcing item keys missing a lifecycle
  postcondition, and 7 possible primary-update retry candidates. These are
  broad scanner metrics, not approved repair targets.
- Full in-band suite: 13/15 suites and 94/105 tests pass. The same two
  pre-existing DIC reminder suites account for all 11 failures.
- No cron workflow, migration, repair, email, or production mutation was run.

## Delivery 5 Repair-Review Contract

1. Repair preparation is exposed through a separate read-only command; the
   Delivery 4 reconciliation command remains unchanged.
2. Every repair review requires an explicit prefixed PR list, target
   environment label, operator reference, and backup/rollback reference.
3. The evidence snapshot contains only identifiers, lifecycle/assignment
   fields, and timestamps from `board_card`, `item_card`, `exports_data`,
   `counter_split_pr_items`, `pr_logs`, `history_log_assign`, and `report_cs`.
   Item text, descriptions, notes, user email, and credentials are excluded.
4. Recommendations are lifecycle-aware:
   - active unassigned items require the established iSourcing assignment
     workflow;
   - stale active export references require review and may be resolved by the
     same assignment workflow;
   - terminal-only PRs prohibit active-card reconstruction;
   - missing/ambiguous active lifecycle state blocks automatic repair.
5. The command produces a deterministic evidence fingerprint and supports an
   after-state comparison against a reviewed before report. `--output` writes
   UTF-8 JSON directly so reports remain machine-readable on Windows.
6. `--apply`, `--repair`, raw SQL mutation, and implicit terminal reopen are
   rejected. This implementation does not authorize production mutation.
7. A later mutation checkpoint requires review of the generated report,
   deployment of Deliveries 1-4, a confirmed maintenance window, an approved
   lifecycle decision per PR, and execution through the authoritative
   iSourcing workflow or a separately reviewed transactional repair.

## Delivery 5 Repair-Review Verification

- Delivery 5 focused tests: 12/12 pass; combined Delivery 1-5 focused suite:
  61/61 pass.
- Repository contract tests verify all seven evidence-table operations execute
  `SELECT` only.
- The local before report is stored at
  `aigen-tasks/20260729-184955-fix-auto-manual-sourcing-header-integrity/evidence/20260730-local-before.json`
  with fingerprint
  `a6ecbe76e84117b66897fd4b78e12cae7efd768f92a81bf1378af752506bb6eb`.
- Local recommendations:
  - `B1200027666`: `WORKFLOW_ASSIGNMENT_REQUIRED` for six active items;
  - `B1200027667`: `WORKFLOW_ASSIGNMENT_REQUIRED` for item `66245`, with a
    stale export-reference verification warning;
  - `B1200027605`: `TERMINAL_NO_ACTIVE_REPAIR` for all 18 target items.
- Evidence contains 8 board cards, 40 item cards, 41 export rows, 25 split
  counters, 41 PR logs, 98 assignment-history rows, and 23 CS reports. A key
  scan found no item text, description, notes, email, password, or token fields.
- Full in-band suite: 16/18 suites and 106/117 tests pass. The same two
  pre-existing DIC reminder suites account for all 11 failures.
- No cron, email, migration, repair, or database mutation was run.

## Delivery 5 Local Canary Repair Contract

1. The first mutating execution is limited to one explicitly selected PR on
   `NODE_ENV=local`; staging and production are rejected by the command.
2. The command requires:
   - one prefixed PR;
   - exact target `item_card` IDs;
   - a single-PR before report whose current fingerprint still matches;
   - operator and backup references;
   - a full private backup output path;
   - an after-report output path;
   - the exact confirmation phrase `APPLY_LOCAL_ISOURCING_REPAIR`.
3. Only active unassigned items with a
   `WORKFLOW_ASSIGNMENT_REQUIRED` review may be repaired. Terminal items,
   existing foreign assignments, missing/duplicate artifacts, and stale
   before reports stop before commit.
4. Current `matrix_auto_assign` routing is resolved per item. Existing terminal
   cards are not reused.
5. Route-card creation, item assignment, export alignment, PR-log assignment
   timestamp, and one CL `Auto Assign` history entry execute in one
   serializable `database_isourcing` transaction.
6. The transaction re-reads and verifies the item, active category/CL cards,
   export, history, and PR log before commit. No email, cron, Aigen status
   update, or terminal reopen is invoked.
7. A rerun against an already consistent item is a no-op. A target write or
   postcondition failure rolls back the complete target transaction.
8. After commit, the command writes a read-only after report and a primary-key
   comparison against the reviewed before report.
9. Initial canary scope is only `B1200027667` / `item_card.id = 66245`.
   `B1200027666` and `B1200027605` remain untouched.

## Delivery 5 Local Canary Verification

- Combined Delivery 1-5 plus local-canary focused suite: 79/79 tests pass.
- Full in-band suite: 18/20 suites and 124/135 tests pass. The same two
  pre-existing DIC reminder suites account for all 11 failures.
- Runtime target was confirmed from `.env` as `NODE_ENV=local` without
  exposing environment values.
- Single-PR before fingerprint:
  `29be015cc5179a90362f321b2abf9d9c87c5844e450b67c8a35748a7cc1dd891`.
- Operation ID: `3e191f03-b879-4bbc-b0fe-a2e156a76e98`.
- The private full backup was written before mutation. Its SHA-256 is
  `14108df3d70dea073a8ddf2655ece635d2d2a915ba7d8015e07441738c457a38`.
  Its contents must not be committed or quoted because it contains full
  legacy rows.
- The serializable transaction repaired item `66245`, created two active MRR
  route cards and one CL split counter, updated export `1100031028` and PR log
  `95456`, and inserted assignment-history row `109698`.
- Postcondition confirmed active item `66245` is assigned to CL `65`, export
  points to active CL card `123944`, material group is `2800`, and exactly one
  CL `Auto Assign` history plus one assigned PR log exists.
- Reconciliation now classifies item 8 as `CONSISTENT`. The PR-level review
  remains `BLOCKED_LIFECYCLE_REVIEW` only because older terminal sibling
  lifecycle rows are still ambiguous.
- After fingerprint:
  `b7c1d46d85ab97b1645262fbe4bdfcad88a162a5c8ec08503f6700070dd40a3d`.
- Per-PR evidence hashes for `B1200027666` and `B1200027605` are unchanged;
  neither PR was mutated.
- No email, cron, migration, Aigen status update, or terminal reopen ran.

## Deferred

- Execution of reviewed historical data repair.
- Database uniqueness migrations, pending duplicate audit and approval.
- Production-like transaction integration testing and rollout observation.

## Sparse Header Branch-Local Fix (2026-08-03)

This implementation applies to branch `fix/qcf-controller-param-checking` at
`b26da8c1901784d568e51cf4cc1246363be8b774`. That branch retains the legacy
`qcfController.prosesToIsourcing()` transfer rather than the transfer-service
implementation described in Deliveries 2-5 above.

1. `getMaterialGroupData()` excludes null/blank material groups and invalid
   source companies, orders candidate source rows deterministically, then
   keeps one most-complete row per material group.
2. The controller validates card title, release date, server group, company,
   material group, source PR value, and source currency before the first
   task-board write. Numeric zero remains valid for PR value.
3. An existing PR first requires an active valid Admin card. A missing card is
   created from a deterministic valid sibling; a sparse one is repaired in
   place. Both operations precede any missing `item_card` insertion.
4. The repair updates only header metadata and timestamp, preserving the
   existing card identity, lifecycle, assignment, split, and status fields.
5. New and existing paths re-read their header postcondition. Existing paths
   also verify newly inserted item cards retain the expected prefixed PR.
6. Structured safe failures use `ISOURCING_SOURCE_HEADER_INCOMPLETE`,
   `ISOURCING_VALID_HEADER_NOT_FOUND`,
   `ISOURCING_HEADER_REPAIR_FAILED`, or
   `ISOURCING_HEADER_VERIFICATION_FAILED`; `sendActionToCS()` does not
   propagate a failed transfer as successful iSourcing status.

### Verification

- `tests/controllers/qcfController.manualSourcingHeader.test.js`: 10/10 pass.
- `node --check src/controllers/qcfController.js` and
  `node --check src/repository/qcfLibrary.repository.js`: pass.
- Full local backend suite: 7/9 suites and 62/73 tests pass. The 11 failures
  remain the documented DIC reminder mock/config drift; no new sparse-header
  test failed.
- No cron, sync, migration, seed, repair command, or database mutation ran.

### Residual Risk

This narrow fix keeps the legacy task-board write boundaries. It prevents an
item from being inserted before a valid Admin header in the existing-PR path,
but it does not add a cross-schema transaction, database constraint, or
concurrency lock. The deployed production revision remains unverified.

## Sparse Header Review Corrections (2026-08-03)

Engineering review found that the branch-local fix is not merge-ready. The
following corrections are required on the same legacy transfer path:

1. Initial imports must create or repair and then verify the active Admin
   `(board_id=1,user_id=1,list_id=1,complete='0')` card even when category
   routing sends material-group cards to another list.
2. All task-board reads and writes that classify or persist the transfer must
   use one transaction created by `database_isourcing`; the default Aigen
   transaction cannot roll back iSourcing models.
3. Transfer exceptions and failed postconditions must roll back Admin,
   category/CL, item, export, PR-log, history, counter, and split changes.
4. Aigen RFQ/QCF status and token updates happen only after the iSourcing
   transaction commits. Failed target transfers leave successful sourcing
   state and tokens unchanged.
5. HTTP trust is never inferred from the presence or absence of `req.params`.
   HTTP calls require both route-scope values; cron callers use a module-owned
   trusted internal entry point.
6. Retries remain idempotent and must not duplicate headers or item codes.

Required regression coverage includes category-mapped first import, stateful
duplicate detection, transaction propagation, rollback after injected partial
writes, same-list and different-list multi-group routing, HTTP scope rejection,
and trusted cron invocation without route params.

### Review Correction Result

- The initial and existing-PR paths now establish and verify the active Admin
  card before committing requested items.
- One `database_isourcing` transaction is passed through all scoped target
  reads/writes, including raw category/export queries. Exceptions and failed
  postconditions roll back the target stage.
- Primary RFQ/QCF state and token changes begin only after target commit and
  execute in their own caller-owned primary transaction.
- `executeSystemManualSourcing()` is the controller-owned in-process trust
  boundary used by `prService` and `qcfService`; body flags cannot bypass HTTP
  route-scope and workflow-policy checks.
- Focused verification passes 20/20 tests. Full Jest passes 8/10 suites and
  72/83 tests; all 11 failures remain in the documented DIC reminder suites.
- No real cron, database mutation, migration, sync, seed, or repair command was
  executed.
