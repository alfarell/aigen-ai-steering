# Plan: Fix Auto Manual Sourcing Sparse Header (Option B)

- Created: 2026-08-03 13:42:15 +07:00
- Status: Completed with engineering-review corrections
- Primary repository: `aigen-backend`
- Target branch at planning time: `fix/qcf-controller-param-checking`
- Target commit at planning time: `b26da8c1901784d568e51cf4cc1246363be8b774`
- Runtime source files: 4 (2 transfer files plus 2 trusted cron call sites)
- Test files: 2
- Database mutation authorized: No

## Objective

Apply the smallest localized fix to the existing auto/manual-sourcing transfer
so that Aigen never creates or preserves an active iSourcing `board_card` with
missing critical header metadata, and never inserts a new active `item_card`
before a valid header is available.

Keep the current controller/repository structure. Do not introduce a new
service, change cron orchestration, add a migration, or refactor unrelated QCF
behavior.

## Confirmed Problem

The production-replica evidence for the affected PRs shows:

| Prefixed PR | Admin card | Current release date | Other sparse fields |
|---|---:|---|---|
| `B1200027605` | No active Admin card remains | Remaining terminal cards contain a release date | Current absence is lifecycle/status-related, not the same active sparse-header state |
| `B1200027666` | `115505` | `NULL` | Value, currency, material/service group, creator/requestor, and purchase-group metadata are incomplete |
| `B1200027667` | `115704` | `NULL` | Same broad sparse-header signature as `B1200027666` |

For `B1200027666` and `B1200027667`, Aigen RFQ rows changed to manual
sourcing at the same second that the sparse Admin cards were created. The card
and split-counter ID sequence is consistent with the material-group loop in
`prosesToIsourcing()`.

iSourcing excludes cards with a null release date from its board query. The
direct display symptom is therefore explained by the sparse header even though
matching `item_card` rows exist and contain valid release dates.

## Root Causes in Scope

1. `getMaterialGroupData()` groups source rows while selecting non-grouped
   metadata, so the chosen metadata can depend on an arbitrary source row.
2. A row with an empty material group can fall back to Admin list `1` and
   create an unintended sparse Admin card.
3. `prosesToIsourcing()` initializes header fields to null and does not reject
   incomplete data before `insertBoardCard()`.
4. The existing-PR branch inserts an `item_card` before ensuring that its
   active Admin header exists and is complete.
5. `findCompletedCardByTitle()` uses an unordered `findOne()` and can copy an
   arbitrary sparse card.
6. An already-existing sparse Admin card is treated as present, so a retry
   does not repair it.
7. Success is returned without a focused postcondition proving that the
   requested active items have a valid same-PR header.

## Strict Scope

### Runtime files to change

1. `aigen-backend/src/controllers/qcfController.js`
2. `aigen-backend/src/repository/qcfLibrary.repository.js`

### Test file to add

1. `aigen-backend/tests/controllers/qcfController.manualSourcingHeader.test.js`

The executor may use a different test filename only if an existing nearby test
is a demonstrably better fit. Do not add a new test framework or dependency.

### Required knowledge-base updates

These are documentation changes required by `AGENTS.md`, not runtime
refactors:

- update `aigen-ai/specs/active/auto-manual-sourcing-header-integrity/spec.md`;
- update affected entries in `aigen-ai/index/function-index.md` and/or
  `aigen-ai/index/codebase-map.md` only where behavior or symbols changed;
- update `aigen-ai/context/project-state.md`;
- update `aigen-ai/context/known-issues.md` with verified mitigation and
  residual risk.

### Explicitly out of scope

- `src/cron.js`;
- `src/services/qcfService.js`;
- `src/services/prService.js`;
- frontend or import-worker changes;
- iSourcing Laravel changes;
- migrations, schema constraints, or dependency changes;
- creating `manualSourcingTransferService.js` or moving the transfer out of
  `qcfController.js`;
- broad task-board transaction refactoring;
- automatic or manual mutation of replicated/production data;
- running `npm run run:cron`, `npm run run:sync`, migrations, seeds, or repair
  commands as verification.

## Behavioral Contract

### Critical header fields

Treat the following as blocking for a new or repaired active card:

- `card_title`;
- `pr_release_date`;
- `pr_company_groups`;
- `company`, where null and source sentinel `0` are invalid;
- `pr_material_group_number`;
- source PR value, checked for null/undefined rather than truthiness;
- source currency.

The validator must not reject numeric zero solely because it is falsy. Fields
such as creator, requestor, purchase group, and service group should be copied
when available and included in safe diagnostics, but they must not be promoted
to blocking fields without confirming that all valid source systems populate
them.

### New PR

1. Resolve source material-group rows before any task-board write.
2. Exclude null/blank material-group rows.
3. Select one deterministic, most-complete source row per material group.
4. Validate every row that would create a card before creating any card or
   item.
5. If a material group is valid but has no category mapping, preserve the
   existing Admin fallback only when the header is complete; emit a safe
   `CATEGORY_MAPPING_NOT_FOUND` diagnostic.
6. If source metadata is incomplete, return a structured failure and perform
   no task-board writes.

### Existing PR

1. Determine whether the active Admin `(board_id=1,user_id=1,list_id=1)` card
   is absent, valid, or sparse before inserting missing items.
2. If absent, construct it from a deterministically selected complete sibling
   card for the same PR.
3. If sparse, repair that existing card in place from the complete sibling;
   do not insert a duplicate Admin card.
4. Preserve identity, lifecycle, assignment, split, and status columns when
   repairing. Update only header metadata and `updated_at`.
5. If no complete source/sibling card exists, fail before inserting any new
   item.
6. Create or repair the valid Admin card before `item_card`, export, PR-log,
   and assignment-history writes.
7. A retry that repairs only a sparse header is a successful result even if no
   new item is inserted.

### Postcondition

Before returning success for an iSourcing transfer:

1. re-read the relevant card state;
2. require at least one valid same-PR header for the requested active items;
3. for the existing-PR unassigned-item path, require the active Admin card to
   pass the critical-header validator;
4. verify every newly inserted requested item uses the expected prefixed PR;
5. return `ISOURCING_HEADER_VERIFICATION_FAILED` when the postcondition fails;
6. do not allow the caller to update Aigen RFQ status to successful iSourcing
   when the transfer result is unsuccessful.

## Detailed Implementation Steps

### Phase 0: Executor preflight

1. Read root `AGENTS.md`, the active specification, and this plan.
2. Run `git status --short` in all three Aigen repositories and preserve every
   pre-existing change.
3. Confirm the backend branch and commit. The previous broad task plan claims
   a separate transfer service was implemented, but that implementation is not
   present on the planning branch. Do not copy or recreate that broad design.
4. Re-read the live implementations of:
   - `prosesToIsourcing()`;
   - `getMaterialGroupData()`;
   - `findExistingCard()`;
   - `findCompletedCardByTitle()`;
   - `insertBoardCard()` and `insertItemCard()`.
5. If concurrent changes now alter these exact symbols, stop and report the
   conflict rather than overwriting them.

### Phase 1: Add failing characterization tests

Use the public `sendActionToCS` path with Jest module mocks where practical.
Do not export private production internals solely for testing and do not add a
test-only dependency.

Add failing tests for:

1. source row with null release date produces no card or item;
2. source row with null/blank material group produces no fallback Admin card;
3. source row missing another critical header field produces a structured
   failure and no writes;
4. complete multi-material-group input preserves one valid card path per
   material group;
5. existing PR with no Admin card chooses a complete sibling instead of an
   arbitrary sparse sibling, and creates the header before the item;
6. existing PR with a sparse Admin card repairs that row before inserting a
   missing item;
7. existing item plus sparse Admin card repairs the header and returns success
   without duplicating the item;
8. no complete sibling/source card means no new item is inserted;
9. postcondition failure prevents successful iSourcing status propagation;
10. valid existing behavior remains successful.

Assert call order for header-before-item behavior. Use synthetic PRs and
metadata; do not embed production personal data.

### Phase 2: Make source selection safe in the repository

Modify `getMaterialGroupData()` only as much as necessary:

1. retain `pr_release_date IS NOT NULL`;
2. require `pr_material_group_number IS NOT NULL` and non-blank;
3. require a non-null/non-zero source company;
4. replace arbitrary grouped non-aggregate selection with deterministic
   selection of the most-complete row per material group;
5. preserve existing item/material-number scope and parameterized
   replacements;
6. preserve existing return field names consumed by `qcfController.js`.

Prefer an ordered query followed by repository-level de-duplication when that
is clearer and more compatible than introducing database-version-specific
window functions. The deterministic order must prioritize rows with complete
critical metadata and use a stable final tie-breaker such as source ID.

Add a repository method dedicated to metadata copying, for example
`findValidHeaderCardByTitle(cardTitle)`. It must:

1. require the critical persisted card fields to be present;
2. select deterministically;
3. prefer a valid active card, then a valid historical sibling;
4. never change the semantics of `findCompletedCardByTitle()` used for
   lifecycle/status checks.

Add the smallest repository update helper needed to repair one Admin card by
primary key. It must accept only the reviewed header metadata fields and must
not update lifecycle, assignment, split, owner, list, or completion columns.

### Phase 3: Add localized controller guards

Inside `qcfController.js` near `prosesToIsourcing()`:

1. add a small local critical-header validator;
2. return both validity and a safe list of missing field names;
3. do not log full source rows, request bodies, names, emails, or credentials;
4. validate the complete material-group plan before the first task-board
   write;
5. treat invalid source state as a structured unsuccessful transfer;
6. preserve current prefixes, category mapping, card color, assignment, and
   item construction for valid data.

Suggested safe failure codes:

- `ISOURCING_SOURCE_HEADER_INCOMPLETE`;
- `ISOURCING_VALID_HEADER_NOT_FOUND`;
- `ISOURCING_HEADER_REPAIR_FAILED`;
- `ISOURCING_HEADER_VERIFICATION_FAILED`.

Use existing response/result conventions. Do not introduce a new error
framework for this patch.

### Phase 4: Reorder and repair the existing-PR path

Before entering the missing-item insertion loop:

1. load the active Admin card once;
2. validate it;
3. if absent or sparse, load a deterministic complete sibling;
4. create the absent Admin card or repair the sparse card;
5. re-read and validate the resulting Admin card;
6. only then process missing items and their export/log/history artifacts.

Move the current header-copy logic out of `if (itemCount < 1)` so a retry can
repair an existing item/header gap without inserting a duplicate item.

When copying metadata:

- copy release date, PR value/currencies, company/server group, material and
  service group, creator/requestor, purchase group, risk/permit metadata, and
  description;
- keep Admin card identity `(1,1,1)` and `card_color = null` behavior;
- do not copy `complete`, PO, split, assignment, board/list/user identity, or
  unrelated timestamps from the sibling;
- update `updated_at` explicitly.

### Phase 5: Add the postcondition and success semantics

1. Re-read the card after creation/repair.
2. Reuse the same validator so validation rules cannot drift.
3. Fail if the active Admin card remains sparse in the existing-PR path.
4. Confirm requested newly created items have the same prefixed PR.
5. Return success when:
   - items were inserted and the postcondition passed;
   - a sparse header was repaired and no duplicate item was needed;
   - the requested state was already complete and valid.
6. Preserve failure propagation so `sendActionToCS()` does not mark Aigen rows
   successful after a failed transfer.

### Phase 6: Documentation and final review

1. Update the existing active specification with this narrow branch-local
   implementation and distinguish it from the previously documented broad
   transfer-service implementation.
2. Update only affected indexes and project-state/known-issue entries.
3. Review the final diff and confirm no changes outside the approved runtime,
   test, and knowledge-base files.
4. Report any discrepancy between the planning branch and the actual deployed
   production revision as unverified, not as a resolved fact.

## Acceptance Criteria

1. Null-release source data cannot create a `board_card` or `item_card`.
2. Null/blank material group cannot create an Admin fallback card.
3. Other missing critical header metadata produces a structured failure before
   target writes.
4. Valid multi-material-group transfers retain their current routing and
   assignment behavior.
5. Existing PR missing an Admin card receives a complete header before a new
   unassigned item is inserted.
6. Existing sparse Admin card is repaired in place, not duplicated.
7. Existing item plus sparse header can be repaired by retry without duplicate
   item creation.
8. Header source selection is deterministic and cannot select an incomplete
   sibling when a complete sibling exists.
9. A failed header postcondition prevents successful Aigen manual-sourcing
   status propagation.
10. Existing valid/already-consistent transfer returns success.
11. `cron.js`, cron services, frontend, import worker, iSourcing Laravel,
    dependencies, and database schema remain unchanged.
12. No real cron, email, SAP, migration, sync, seed, or repair action is run as
    verification.

## Verification Commands

Run targeted tests first from `aigen-backend`:

```text
npx jest tests/controllers/qcfController.manualSourcingHeader.test.js --runInBand
```

Run syntax checks for the changed runtime files:

```text
node --check src/controllers/qcfController.js
node --check src/repository/qcfLibrary.repository.js
```

Run the full backend suite:

```text
npm test -- --runInBand
```

Run final diff checks:

```text
git diff --check
git status --short
git diff -- src/controllers/qcfController.js src/repository/qcfLibrary.repository.js tests/controllers/qcfController.manualSourcingHeader.test.js
```

Known suite failures must be compared against
`aigen-ai/context/known-issues.md` and reported separately. Do not classify an
existing failure as caused by this patch without evidence.

## Read-Only Verification for the Reported PRs

If the executor has local replica access, use only read-only queries or the
existing read-only reconciliation command. Do not print personal metadata or
environment values.

Expected pre-repair observations:

- `B1200027666`: active Admin card exists but fails critical-header validation;
- `B1200027667`: active Admin card exists but fails critical-header validation;
- `B1200027605`: current cards are terminal and must not be reopened by this
  patch.

Do not execute the cron or mutate these rows as part of implementation
verification. Historical data repair requires a separately authorized action.

## Residual Risks

1. This localized patch does not make all task-board writes atomic. A failure
   after header creation can leave a header without an item, although it
   prevents the more harmful item-before-valid-header ordering in the scoped
   existing-PR path.
2. No database uniqueness or foreign-key protection is added.
3. Concurrent cron/HTTP execution is not fully locked by this patch.
4. iSourcing can delete/move cards later as part of its lifecycle. This patch
   governs Aigen transfer-time integrity only.
5. The exact production Git revision used on 2026-05-11 and 2026-05-12 remains
   unverified. The fix must be validated against the deployment candidate
   revision before release.
6. Existing sparse production data is not automatically repaired by deploying
   code. Repair-on-retry only applies when an authorized workflow processes the
   PR again; explicit historical repair remains separate.

## Executor Completion Report

The executor must report:

1. exact files changed;
2. branch and commit used;
3. tests/checks run and their results;
4. pre-existing test failures;
5. whether all acceptance criteria are covered;
6. any deviations from the two-runtime-file scope;
7. unverified production behavior;
8. confirmation that no database mutation or real cron was executed.

## Executor Completion Report (2026-08-03)

- Branch/commit: `fix/qcf-controller-param-checking` /
  `b26da8c1901784d568e51cf4cc1246363be8b774`.
- Runtime changes: `src/controllers/qcfController.js` and
  `src/repository/qcfLibrary.repository.js` only.
- Test added: `tests/controllers/qcfController.manualSourcingHeader.test.js`.
- Targeted regression result: 10/10 tests pass.
- Syntax checks pass for both runtime files.
- Full suite: 7/9 suites and 62/73 tests pass. The remaining 11 failures are
  the existing DIC reminder config/mock drift documented in
  `aigen-ai/context/known-issues.md`.
- Acceptance coverage includes source rejection, deterministic multi-group
  headers, Admin header create/repair before item, retry idempotency,
  postcondition failure propagation, and valid existing behavior.
- No changes were made to cron, services, frontend, import worker, schema,
  dependencies, or production configuration.
- No cron, sync, migration, seed, repair command, or database mutation ran.
- Production deployment behavior remains unverified because the historical
  production Git revision was not available on this branch.

## Engineering Review Correction Report (2026-08-03)

The attached engineering review supersedes the earlier completion report and
required a narrow scope adjustment.

### Implemented corrections

1. The category-mapped initial-import path creates or repairs the active Admin
   `(board_id=1,user_id=1,list_id=1,complete='0')` card before item insertion,
   then re-reads it as a blocking postcondition.
2. `prosesToIsourcing()` creates one transaction from
   `database_isourcing`. Every scoped target card, item, export, PR-log,
   history, category, counter, and split read/write receives that transaction.
3. Exceptions and failed postconditions roll back the target transaction.
   Aigen RFQ/QCF state and tokens are changed only after target commit, inside
   a separate caller-owned primary transaction.
4. `executeSystemManualSourcing()` is a controller-owned trusted entry point.
   HTTP calls cannot bypass scope/policy checks with `is_system_action`; both
   route values are required.
5. Retry behavior is statefully tested to retain exactly one Admin header and
   one item per item code.

### Approved scope deviation

The review's explicit trust-boundary requirement made two call-site-only
changes necessary in `src/services/prService.js` and
`src/services/qcfService.js`. They now call the trusted controller entry point
and no longer send a body-controlled system flag. Cron orchestration, grouping,
timing, and business decisions were not refactored.

One repository test was also added beyond the original single test-file scope
to verify transaction propagation at the repository boundary. No dependency,
migration, schema, frontend, import-worker, or iSourcing Laravel change was
made.

### Verification result

- Focused controller/repository tests: 20/20 passing.
- Runtime syntax checks: passing.
- `git diff --check`: passing.
- Full backend Jest: 8/10 suites and 72/83 tests passing. The 11 failures are
  the pre-existing DIC reminder config/mock drift; no corrected sourcing test
  fails.
- No cron, sync, migration, seed, repair command, email, SAP action, or
  database mutation was executed.

### Residual risk

- No uniqueness/FK migration or explicit concurrency lock was introduced.
- Transaction behavior is covered with failure-injection and repository
  propagation tests, but not a mutating isolated real-MySQL integration test.
- Existing production sparse rows are not repaired automatically by this code
  change; they still require the separately reviewed repair workflow.
- The exact historical production revision remains unverified.
