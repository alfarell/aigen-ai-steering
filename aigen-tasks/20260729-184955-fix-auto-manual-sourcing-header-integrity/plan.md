# Plan: Auto Manual Sourcing Header Integrity

- Created: 2026-07-29 18:49:55 +07:00
- Status: Delivery 1-4 implemented and locally verified; Delivery 5
  repair-review and the first local canary are verified, while non-local
  mutation remains gated by the listed production repair approvals
- Primary repository: `aigen-backend`
- Data stores: `aigen`, `prpo`, `task_board`
- Source evidence: `aigen-issues/pr-ex-aigen.xlsx`
- Production mutation authorized: No

## Implementation Progress

| Delivery | Status | Result |
|---|---|---|
| 1. Characterization and safe invocation | Implemented, locally verified | Trusted cron adapter, HTTP scope enforcement, runtime blocker fix, structured failure propagation, 8 focused tests |
| 2. Atomic transfer and active-card integrity | Implemented, locally verified | One target transaction, card-before-item, orphan repair, idempotency, locking/retry, terminal guard, and postcondition; no migration or production mutation |
| 3. Per-item routing parity | Implemented, locally verified | Per-item current-matrix resolver, deterministic active category/CL cards, aligned item/export/history/log artifacts, explicit unmapped/terminal results |
| 4. Reconciliation and observability | Implemented, locally verified | Safe per-stage cron summaries, non-zero failure contract, Sentry tags, read-only health metrics, and ten-class reconciliation CLI |
| 5. Reviewed data repair | Local canary completed; non-local execution gated | SELECT-only review plus fingerprinted backup/transaction/after-report for `B1200027667`; production approval remains required |

Delivery 2 prevents a successful Aigen transfer from committing a touched
active item without its lifecycle-required card. Delivery 3 adds per-item
routing parity for new and existing PRs. Historical scanning and reviewed data
repair remain separate deliveries.

## Objective

Make auto/manual sourcing reliable and idempotent so that:

1. a transfer cannot create an active `item_card` without a lifecycle-
   appropriate `board_card` that makes it reachable by the intended role;
2. repeated cron or manual requests repair incomplete state instead of treating
   it as a terminal failure;
3. Aigen status is updated only after the iSourcing write reaches a verified
   consistent state;
4. per-PR failures are observable and cause the cron stage to report a partial
   or failed result;
5. existing inconsistent data can be identified and repaired through an
   auditable dry-run-first procedure.

## Scope

### In scope

- Runtime blocker in `qcfController.sendActionToCS`.
- DIC, CS, OE, CL, and Management expiry paths that internally invoke manual
  sourcing.
- `prosesToIsourcing()` and its `board_card` / `item_card` persistence helpers.
- Transaction propagation for writes within `task_board`.
- Idempotency and header-item consistency checks.
- Read-only reconciliation and separately authorized repair tooling.
- Regression tests for cron context, manual HTTP context, rollback, retry, and
  incomplete existing state.
- Updates to the active specification, indexes, known issues/project state, and
  manual-sourcing documentation during implementation.

### Out of scope unless separately approved

- Executing `npm run run:cron` against production-like data.
- Sending email or invoking SAP/iFlow as verification.
- Automatically repairing production data.
- Refactoring unrelated QCF workflows.
- Changing the iSourcing application outside this workspace.
- Adding database migrations before the ownership and compatibility impact is
  confirmed.

## Current Evidence

### Workbook

`pr-ex-aigen.xlsx` contains 20 reported item rows:

| Source PR | Reported rows |
|---|---:|
| `1200027605` | 13 |
| `1200027666` | 6 |
| `1200027667` | 1 |

The blank PR cells in continuation rows are merged/forward-filled from the
preceding PR value.

### Local database reconciliation

Queries were executed in read-only transactions against the local replicas.
No database data was changed.

| iSourcing PR | Current item rows | Any matching `board_card` | Main header `(1,1,1)` | Interpretation |
|---|---:|---:|---:|---|
| `B1200027605` | 18 | 2 | 0 | Same-title split cards remain, but this alone does not link them to the reported items |
| `B1200027666` | 14 | 3 | 1 | Shared active Admin entry card currently exists |
| `B1200027667` | 8 | 3 | 1 | Shared active Admin entry card currently exists |

For `B1200027605`, the two remaining headers are split cards:

- both were created on 2026-03-16;
- both are `split_for = 'CS'`;
- both currently have `complete = '9'` (`autoClosed`);
- their latest update is 2026-06-05, the same date as the 13 reported item
  rows were created in the current `item_card` snapshot.

Important qualification:

- Using the loose invariant `board_card.card_title = item_card.pr_number`, all
  20 reported rows currently have at least one same-title card.
- This is only a PR-level join and is not proof that a card belongs to, shows,
  or preserves the lifecycle of a specific item.
- Using the canonical main-header invariant
  `board_id = 1 AND user_id = 1 AND list_id = 1`, the 13 reported rows for
  `B1200027605` do not have a main header.
- iSourcing source review confirms this canonical card is not a permanent
  invariant: an origin card can be deleted after all items are split.

### Wider integrity scan

- 76 PR numbers currently have `item_card` rows with no matching
  `board_card.card_title` at all.
- Those 76 PR numbers contain 323 item rows.
- No foreign key connects `item_card.pr_number` to a header.
- `item_card` has no uniqueness constraint on `(pr_number, item_code)`.
- No database trigger protects `board_card` / `item_card` consistency.
- `board_card.card_title` indexes are non-unique because split cards share the
  same title.

The much larger population without a `(1,1,1)` main card must not be treated
as corrupt until the iSourcing lifecycle semantics are confirmed. Many PRs
legitimately retain only split or assigned cards after moving through the
board.

### Item-level comparison against rows not listed in the workbook

The iSourcing Laravel source confirms that item visibility is not determined
only by `item_card.pr_number = board_card.card_title`. Card-detail queries also
filter on:

- the active `board_card` selected for the current board/list/user;
- `item_card.item_complete = '0'`;
- assignment fields such as `assigned_to_cl`, `assigned_to_cs`, and
  `send_email_to`;
- the current user's level and assigned board list.

This explains why items with the same PR number can follow different website
visibility paths.

Read-only comparison of the 20 workbook rows against the other items in each
PR found:

| PR | Workbook items | Other items | Material difference |
|---|---:|---:|---|
| `B1200027605` | 13 | 5 | Workbook items are assigned to CL 4 / CS 54 and all have `item_complete = '9'` (`autoClosed`); other items are unassigned and all have `item_complete = '1'` |
| `B1200027666` | 6 | 8 | Workbook items are unassigned, `item_complete = '0'`, and have no matching material-group split card; all other items are `item_complete = '1'`, with six assigned to the existing `5100` category cards |
| `B1200027667` | 1 | 7 | Workbook item is unassigned, `item_complete = '0'`, and material group `2800` has no split card; all other items are assigned to CL 4 / CS 72 and map to the existing `8000` category cards |

Additional lifecycle evidence:

- Every workbook item for `B1200027666` and `B1200027667` has only a
  `New Item` history entry. The assigned comparison items have later
  `Auto Assign`, `Assign`, and/or completion history.
- Their `exports_data` rows remain `NotAssign`, with `cl_user_id = 0`,
  no CS user, and `pr_status = 'PR On Progress'`.
- The six workbook items for `B1200027666` span material groups other than the
  only existing split category (`5100`).
- The workbook item for `B1200027667` is material group `2800`, while both
  existing split cards are material group `8000`.
- For `B1200027605`, the current data represents a later lifecycle state:
  workbook items are `PR Close` / `autoClosed`, the only remaining cards are
  also complete `9`, and the canonical main card is absent. The comparison
  items are `PR Complete` (`item_complete = '1'`).

Interpretation:

- For `B1200027666` and `B1200027667`, the primary item-level defect is not a
  missing PR header in the local snapshot. The items were inserted by the
  existing-board path but were never auto-assigned or given a category/split
  card for their own material group. They are therefore visible only through
  the Admin/main-card path, subject to the board page's date and role filters,
  and do not appear on the CL/CS cards where the other items appear.
- For `B1200027605`, the supplied rows are not equivalent to the other items:
  they have been assigned and then auto-closed. Their item-specific card IDs
  have been deleted, while the surviving same-PR cards belong to a different
  split. This must be analyzed as a terminal lifecycle/reference defect.
- A repair that only recreates a main header is incomplete. It can make the
  PR discoverable to Admin while leaving new items unassigned and invisible
  to the intended CL/CS users.

The iSourcing source also confirms that deleting an origin/main card can be a
normal result of assigning all items to split cards. Therefore, the absence of
the `(1,1,1)` card is not sufficient by itself to classify a PR as corrupt.

### How iSourcing relates `board_card` and `item_card`

There is no direct foreign key or `item_id` column on `board_card`. The
application uses three different relationship concepts:

1. Board-list eligibility uses a loose join:
   `board_card.card_title = item_card.pr_number`. This can make a card appear
   because of any item in the same PR.
2. Card-detail visibility is calculated dynamically:
   - shared Admin/main card: active unassigned items with the same PR;
   - CL card: active items whose `assigned_to_cl` matches the destination list;
   - CS card: active items whose `assigned_to_cs` matches the destination list;
   - frontend rendering further checks `item_complete`, `send_email_to`,
     `split_for`, the current list assignee, and user level.
3. `counter_split_pr_items.card_id/item_id` and
   `exports_data.board_id/item_id` record operational/history references, but
   card deletion can leave these references stale. The card-detail endpoint
   does not use either table as its primary item lookup.

Relevant production-source paths:

- `isourcing-laravel/app/Http/Controllers/BoardController.php`;
- `isourcing-laravel/app/Http/Controllers/CardController.php`;
- `isourcing-laravel/public/js/board.js`;
- `isourcing-laravel/app/Http/Controllers/CardAssignController.php`.

Use these terms in reconciliation:

- `SAME_PR_CARD`: card and item share a PR number only;
- `FUNCTIONAL_ADMIN_CARD`: the item is active/unassigned and the Admin detail
  query will return it for that card;
- `FUNCTIONAL_ASSIGNED_CARD`: assignment/list/user rules return the item for a
  CL/CS card;
- `HISTORICAL_ITEM_CARD`: counter/export history points to the exact card ID;
- `STALE_ITEM_CARD_REFERENCE`: the exact referenced card ID no longer exists.

Updated interpretation of the supplied rows:

- `B1200027605`: the two current cards are split number 3. The 13 reported
  items have counter references to split numbers 2, 4, 10, 14, and 17, and
  those referenced card IDs no longer exist. The surviving same-title cards
  therefore cannot be claimed as their item-level headers.
- `B1200027666`: the two completed split cards are for another assigned item
  flow. However, shared Admin card `115505` is a functional entry card for the
  six reported active/unassigned items; all six export rows also currently
  reference `115505`.
- `B1200027667`: the completed split cards belong to the material-group-8000
  assigned flow, not reported item 8. Shared Admin card `115704` is still a
  functional entry card for active/unassigned item 8, but its export row
  references deleted card `115702`, which is a stale historical reference.

## Root-Cause Assessment

### Finding 1: Current runtime blocker

The uncommitted `qcfController.js` change guards HTTP-only authorization with
`req.params`, but also removes the declarations of `rfqNumberForCheck` and
`vendorCodeForCheck`. Both variables are still referenced before
`prosesToIsourcing()` is called.

Impact:

- current manual HTTP sourcing fails at runtime;
- current cron-driven sourcing fails at runtime;
- the failure happens before new `board_card` or `item_card` writes.

The committed `HEAD` has a different cron-specific blocker: it always
destructures `req.params` for iSourcing, while internal cron request objects do
not provide route params.

Conclusion:

- this issue must be fixed first;
- it does not explain historical item-without-header records because it stops
  the transfer before item creation;
- the relevant authorization change was introduced after the March-July
  evidence in the supplied sample.

### Finding 2: Existing-board branch writes the item before ensuring its active entry card

When `boardCount >= 1`, the current order is:

1. insert `item_card`;
2. insert `exports_data`;
3. insert `pr_logs`;
4. insert `history_log_assign`;
5. check whether the main `(user_id=1, list_id=1)` card exists;
6. create the main header if absent.

Any exception between steps 1 and 6 can leave a newly active, unassigned item
without an active Admin entry card, even if terminal split cards still exist.

This is a direct code-level mechanism for the reported state.

### Finding 3: Active-card repair is incorrectly nested under "new item"

The main-header check only runs inside `if (itemCount < 1)`.

Consequences:

- if an active item already exists and its required card is missing, a retry
  does not repair the card;
- if a prior partial attempt created the item but failed before active-card
  recreation, all later retries skip the repair;
- an incomplete PR can remain permanently inconsistent while the cron appears
  to have nothing new to add.

### Finding 4: The opened transaction does not protect iSourcing writes

`prosesToIsourcing()` opens a transaction using the primary Aigen Sequelize
connection. The `boardCard`, `itemCard`, `prLogs`, and `historyLogAssign`
models use the separate iSourcing connection, and repository calls do not
receive the opened transaction.

Consequences:

- `commit()` / `rollback()` in `prosesToIsourcing()` do not atomically control
  `task_board` writes;
- item, header, export, and logs can persist partially;
- the later Aigen status transaction is also separate from the iSourcing
  transfer.

### Finding 5: Existing-card success semantics are not idempotent

When the board and all requested items already exist, the function returns
`success: false` because `insertedItemCount === 0`.

Consequences:

- an already-correct target state is reported as failure;
- Aigen status/token cleanup may be skipped;
- cron retries can continue indefinitely;
- reconciliation and repair cannot safely reuse the transfer path.

### Finding 6: Database permits orphan and duplicate state

There is no FK, trigger, or uniqueness rule that enforces the business
invariant. A direct FK to `board_card.card_title` is not currently possible
because `card_title` is intentionally non-unique across split cards.

Application-level lifecycle consistency is therefore mandatory unless a
separate durable PR identity is introduced.

### Finding 7: Downstream iSourcing lifecycle is a confirmed contributor

The iSourcing Laravel application has multiple assignment, move, reject,
restore, and approval paths that delete `board_card` rows. In particular,
assignment paths delete the origin card when all selected or remaining items
have moved to split cards.

This means:

- a missing main card can be valid after a complete split;
- exact no-card orphans can be created later if the last split card is also
  deleted without a lifecycle-safe terminal representation;
- Aigen must not assume the canonical main card is permanent;
- reconciliation must distinguish active-item orphan state from terminal
  lifecycle history.

For `B1200027605`, the March Aigen status updates and June `item_card` creation
timestamps do not align for all reported rows. One reported description is
also not present in the current `aigen.rfq_library` snapshot. This weakens the
claim that the current June item rows were all created directly by the Aigen
auto-manual-sourcing call.

Conclusion:

- the Aigen existing-board branch is unsafe and can create the symptom;
- the supplied local snapshot also suggests a downstream lifecycle or data
  reconstruction contribution;
- production logs or iSourcing audit history are needed before assigning a
  single historical root cause.

## Relationship Between the Two Issues

The runtime blocker and the production integrity issue are related to the same
manual-sourcing entry point, but they are not the same failure mode.

| Issue | Expected effect |
|---|---|
| Missing `req.params` / undefined variables | No transfer; fails before creating header or item |
| Existing-board ordering and ineffective transaction | Partial transfer; active item can persist without its required workflow card |
| External board lifecycle/delete | Header can disappear after a previously successful transfer |

Therefore, repairing only the undefined variables will restore execution but
will not prevent future partial/orphan states.

## Required Lifecycle Invariant

Do not use the canonical main card as a permanent invariant. Use the following
state-aware rules:

| Item state | Required workflow representation |
|---|---|
| Active and unassigned | An active Admin/main card from which the item can be assigned |
| Active and assigned to CL only | An active CL card for `assigned_to_cl`, plus assignment/export/history consistency |
| Active and assigned to CS | An active CS card for `assigned_to_cs`, plus assignment/export/history consistency |
| Terminal (`complete`, `close`, `autoClose`, or cancel) | Do not recreate an active card automatically; require consistent terminal report/export/history and at least one auditable lifecycle reference |
| Unknown or contradictory state | Classify as `AMBIGUOUS_LIFECYCLE`; do not mutate automatically |

For every item created or changed by Aigen, the required active card must exist
before the target transaction commits.

The `(1,1,1)` main card is a valid entry card for an unassigned active item,
but it may be deleted after all items are split. Reconciliation must therefore
report `MISSING_ACTIVE_CARD` separately from `MAIN_CARD_ABSENT_AFTER_SPLIT`.

Coverage guarantee after Delivery 2 and Delivery 3:

- every active item created or touched by Aigen has a reachable
  lifecycle-appropriate card at commit;
- retries repair an incomplete active card/item state;
- assignment and card routing agree for each item;
- terminal items are not accidentally reopened.

This plan does not guarantee that every terminal `item_card` retains a physical
`board_card` forever because current iSourcing lifecycle paths deliberately
delete origin/split cards. If the product requires a literal permanent
header-for-every-item invariant, create a separate cross-repository iSourcing
work package to introduce a durable PR-header identity or change every
delete/archive path. That change must not be hidden inside the Aigen transfer
fix.

## Delivery Phases

The complete scope is too broad for one implementation and release. Deliver it
through the following independently verifiable phases.

| Delivery phase | Scope | Depends on | Production behavior risk |
|---|---|---|---|
| 1. Characterization and safe invocation | Tests, trusted cron/HTTP adapters, runtime blocker, structured result | None | Low |
| 2. Atomic transfer and active-card integrity | Target transaction, idempotency, header/card-before-item, postcondition | Phase 1 | Medium |
| 3. Per-item routing parity | Material-group mapping per item, existing-PR auto-assignment/card creation parity | Phase 2 | Medium-high |
| 4. Reconciliation and observability | Dry-run scanner, metrics, failure classifications, no automatic mutation | Phase 2; Phase 3 preferred | Low |
| 5. Reviewed data repair | Canary repair of supplied PRs, before/after evidence, explicit approval | Phase 4 | High and tightly scoped |

### Phase 1 release gate

- No target schema write behavior changes.
- HTTP `isourcing`, `surrogate`, and `oe` routes retain their existing
  authorization and response contracts.
- Internal cron callers no longer construct incomplete Express requests.
- Direct nine-day follow-up and DIC/CS/OE/CL/Management expiry callers receive
  structured transfer results.
- Existing unrelated vendor/reminder cron stages remain unchanged.

### Phase 2 release gate

- Local implementation status: passed 29 focused tests on 2026-07-30; real
  MySQL integration and production-like cron remain unexecuted.
- Every task-board write uses one `database_isourcing` transaction.
- The lifecycle-required active card is created/reconciled before item insert.
- Failure injection after every target write proves full rollback.
- An existing consistent transfer returns `already_consistent`.
- Terminal PRs are never reopened merely because a main card is absent.
- Routing fields remain behaviorally unchanged in this phase, so orphan
  prevention can be validated separately from assignment changes.

### Phase 3 release gate

- A pure per-item transfer plan resolves material group, category, CL, and
  required card before persistence.
- New-PR and existing-PR item paths use the same resolver.
- Existing active cards are reused only when user/category/status match.
- Completed or auto-closed cards are not silently reused as active cards.
- Missing matrix mapping returns `UNMAPPED_CATEGORY` without partial writes.
- Late items for a terminal PR return `TERMINAL_PR_NEW_ITEM` unless an explicit
  reopen policy is approved.

### Phase 4 release gate

- Scanner is read-only by default and lifecycle-aware.
- It distinguishes exact no-card orphans, active items on the wrong role card,
  valid split-only terminal states, and stale export/history references.
- Results are reviewed over at least one cron window before repair mode exists.

### Phase 5 release gate

- Only explicitly listed PR/item IDs are mutable.
- Each PR runs in its own target transaction.
- Repair uses current category matrix only after business confirmation.
- Existing iSourcing UI/workflow is preferred over direct SQL because it also
  updates split counters, logs, exports, notifications, and card lifecycle.
- Production mutation requires separate approval, backup/reference, dry-run,
  and a reviewed before/after report.

## Change Isolation

The orphan-prevention and routing fixes share the same transfer service but
must remain separate concerns:

1. `resolveTransferPlan()` is pure and determines intended item/card state.
2. `persistTransferPlan()` enforces ordering and transaction integrity.
3. Phase 2 initially uses legacy routing output while changing persistence
   safety only.
4. Phase 3 replaces legacy routing with per-item matrix resolution without
   changing transaction semantics.
5. The postcondition validator checks both concerns independently:
   - structural result: required active card and item exist;
   - routing result: assignment, card owner/category, export, and history agree.

Regression boundaries:

- `RFQ_TYPE.ISOURCING` is the only `sendActionToCS` branch that invokes the
  task-board transfer; surrogate and OE branches must be covered but must not
  acquire new iSourcing writes.
- Cron paths include DIC, CS (all four subpaths), OE, CL, Management, and the
  separate nine-day direct call to `prosesToIsourcing()`.
- Aigen status/token updates remain after verified target success.
- Email and SAP/iFlow side effects are mocked in tests and are not invoked as
  local verification.
- iSourcing card deletion/move behavior remains owned by iSourcing; this task
  does not remove or bypass those lifecycle operations.

## Detailed Work Packages

### Delivery 1 / Work package 1.1: Preserve and specify

1. Resolve ownership of the existing uncommitted changes in:
   - `aigen-backend/package-lock.json`;
   - `aigen-backend/src/controllers/qcfController.js`.
2. Do not overwrite or revert those changes.
3. Create/update an active specification under:
   `aigen-ai/specs/active/auto-manual-sourcing-header-integrity/`.
4. Record:
   - chosen lifecycle/card invariant;
   - cron system-actor authorization rules;
   - idempotency contract;
   - failure/retry behavior;
   - data-repair boundaries.
5. Map the specification to tests and rollout checks.

### Delivery 1 / Work package 1.2: Fix the runtime entry point

1. Restore the derivation of `rfqNumberForCheck` and `vendorCodeForCheck` from
   the database-loaded first item.
2. Separate HTTP route-scope validation from internal system execution.
3. Do not authorize internal execution merely because
   `req.body.is_system_action` is true.
4. Introduce an explicit trusted invocation context, for example:
   - HTTP adapter validates route params and user policy;
   - cron service calls a domain service with a server-created system actor.
5. Ensure both adapters call the same domain service without constructing
   incomplete Express request/response mocks.
6. Make a failed child transfer propagate a structured failure to
   `runCronTasks()`.

Acceptance:

- HTTP manual sourcing retains existing role and item-scope checks.
- Cron execution does not require `req.params`.
- Unknown/foreign item IDs are rejected before target writes.
- Per-RFQ failure cannot be reported as an overall successful cron stage.

### Delivery 1-2 / Work package 1.3: Extract a transfer service

Move iSourcing orchestration out of the large controller into a focused
service, for example:

```text
src/services/manualSourcingTransferService.js
```

Suggested interface:

```js
transferToISourcing({
    actor,
    rfqItems,
    reason,
    notes,
    invocation,
})
```

Responsibilities:

1. re-read and validate Aigen RFQ items;
2. calculate the prefixed PR/card title;
3. load PR/header metadata;
4. reconcile target header state;
5. insert missing target items;
6. verify the postcondition;
7. return an idempotent result:
   - `created`;
   - `repaired`;
   - `already_consistent`;
   - `failed`.

The controller and cron handlers should only adapt input/output and should not
call one another.

### Delivery 2 / Work package 2.1: Reconcile active card before item creation

For every transfer:

1. determine the prefixed PR/card title;
2. query all matching board cards;
3. classify the PR/item lifecycle state;
4. create or reconstruct only the lifecycle-required active card before
   processing any active item;
5. only then insert missing item rows and related logs.

Move active-card reconciliation outside `if (itemCount < 1)` so retries can
repair an incomplete active item even when its `item_card` row already exists.

For the existing-board case:

- select the source board deterministically with an explicit ordering and
  eligibility rule;
- do not use an unordered `findOne()` across completed/split cards;
- reject ambiguous reconstruction when source cards disagree on critical PR
  metadata;
- do not reconstruct an active main card from terminal-only cards unless the
  transfer explicitly represents an approved late-item/reopen operation;
- log which board row was used as the reconstruction source.

Postcondition:

```text
for every touched active item:
    lifecycle-required Admin/CL/CS card exists and is reachable

for every touched terminal item:
    no active card is created unless an approved restore/reopen transition runs
```

If the postcondition fails, the transfer must fail and must not update Aigen
to a successful manual-sourcing state.

### Delivery 2 / Work package 2.2: Correct transaction boundaries

1. Start the target transaction from `database_isourcing`.
2. Pass the same transaction explicitly through:
   - header lookup/create;
   - item lookup/create;
   - `exports_data`;
   - `pr_logs`;
   - `history_log_assign`;
   - any split counters/history required by the transfer.
3. Roll back all target writes when any target step fails.
4. Commit the target transaction only after the card-item postcondition
   passes.
5. Update `aigen.rfq_library`, `aigen.qcf_library`, and token state in a
   separate primary transaction after the target commit.
6. If the primary update fails after target commit:
   - record a retryable reconciliation state;
   - preserve idempotency so rerun recognizes the committed target state;
   - emit an operational error rather than duplicating target data.

Do not describe separate Sequelize connections as one atomic transaction.

### Delivery 2 / Work package 2.3: Make the transfer idempotent and concurrency-safe

1. Treat `already_consistent` as success.
2. Re-read target state inside the target transaction.
3. Use transaction-level locking appropriate to the chosen key.
4. Prevent duplicate item creation for `(pr_number, item_code)`.
5. Prevent duplicate active cards for the same PR, role, user, category, and
   split identity.
6. Re-check the invariant after all writes.
7. Ensure overlapping cron/manual invocations converge to one valid state.

Optional migration decision:

- add a unique index on `item_card(pr_number, item_code)` only after a duplicate
  audit and cleanup plan;
- add a unique active-card constraint only if it can represent iSourcing split
  and lifecycle semantics without blocking valid history;
- consider a separate durable PR identity if a true FK is required.

No migration should be created or applied without explicit approval.

### Delivery 3 / Work package 3.1: Correct multi-material-group behavior

The new-board branch loops material groups but currently processes the full
item list inside each group and uses the outer group's metadata. Refactor the
mapping so every item receives metadata from its own material group.

The existing-board branch must also process each newly discovered item through
the same assignment policy as an initial item:

1. resolve category assignment from the item's own material group;
2. set `assigned_to_cl`, `send_email_to`, and `is_updated` consistently;
3. create or reuse the required category/split card deterministically;
4. keep `exports_data` assignment fields aligned with `item_card`;
5. create the expected auto-assignment history and PR-log timestamps;
6. verify that the item is reachable from the target Admin/CL/CS board query,
   not merely that a row exists in `item_card`.

Acceptance:

- a PR spanning multiple material groups creates correctly mapped item rows;
- board/split creation is deterministic;
- no item inherits the first material group's assignment accidentally.
- adding a new material group to an existing PR creates the required
  assignment/card path or returns an explicit `UNMAPPED_CATEGORY` result;
- an item inserted into an existing PR is visible to the intended role under
  the same rules as an equivalent item inserted with a new PR.

Implementation outcome (2026-07-30):

- implemented `resolveTransferPlan()` as a pure per-item resolver;
- selected the current iSourcing matrix at transfer time for newly discovered
  items in both new and existing PRs;
- retained `TERMINAL_PR_NEW_ITEM` rather than implicitly reopening a PR;
- reused active cards only on exact route identity and never reused terminal
  cards;
- aligned item, exact export card/category/CL, assignment history, PR log, and
  split counter writes under the Delivery 2 transaction;
- extended the postcondition to re-read category/CL cards and all assignment
  artifacts before commit;
- verified 37 focused tests and a read-only matrix integrity audit;
- full suite remains at the known baseline shape: 8/10 suites and 82/93 tests
  pass, with all 11 failures in the two pre-existing DIC reminder suites;
- did not run cron, migrations, production mutation, or mutating integration
  tests.

### Delivery 4 / Work package 4.1: Improve cron result and observability

1. Return a per-stage result containing:
   - selected RFQs;
   - created/repaired/already-consistent counts;
   - failed RFQs and error codes.
2. Make command exit non-zero for an unhandled stage failure or an agreed
   failure threshold.
3. Include safe correlation fields:
   - RFQ number;
   - prefixed PR number;
   - stage;
   - operation ID;
   - result classification.
4. Do not log credentials, tokens, full request bodies, or private links.
5. Capture unexpected errors through Sentry.
6. Add a read-only health/reconciliation metric for:
   - item without any same-PR card;
   - active item without a functional Admin/CL/CS card;
   - terminal item with a stale/missing item-specific card reference;
   - transfer marked successful but target postcondition missing;
   - retryable primary-update failures.

### Delivery 4 / Work package 4.2: Build a dry-run reconciliation tool

Create a read-only-by-default CLI/report that classifies:

1. `NO_CARD_ANY_STATE`: item exists, no matching card title;
2. `MISSING_ACTIVE_CARD`: active item has no reachable Admin/CL/CS card;
3. `VALID_TERMINAL_HISTORY`: main card is absent, but item-specific terminal
   lifecycle references remain valid;
4. `ROUTING_MISMATCH`: assignment/category/card owner disagree;
5. `HEADER_ONLY`: card exists, expected items are missing;
6. `DUPLICATE_ITEM`;
7. `DUPLICATE_ACTIVE_CARD`;
8. `STALE_ITEM_CARD_REFERENCE`: counter/export points to a deleted card;
9. `MISSING_TERMINAL_ITEM_CARD_REFERENCE`: terminal item has only an unrelated
   same-PR card;
10. `CONSISTENT`;
11. `AMBIGUOUS_LIFECYCLE`.

Inputs:

- optional PR list;
- optional date range;
- optional server group;
- optional RFQ number.

Output must include enough source IDs and timestamps for review without
including secrets.

Repair mode must be a separate, explicitly authorized command with:

- dry-run output reviewed first;
- target environment confirmation;
- backup/rollback reference;
- per-PR transaction;
- deterministic reconstruction source;
- audit record;
- post-repair verification.

Do not repair all 76 exact orphans automatically. Historical/imported rows may
have different ownership or lifecycle rules.

Implementation outcome (2026-07-30):

- cron stages now emit operation-scoped selected/attempted/result summaries;
- any failed support, expiry, or health stage produces a non-zero direct
  command result after remaining stages finish;
- unexpected failures are sent to Sentry with safe operation/stage tags;
- reconciliation health is queried read-only after every cron run;
- `reconcile:isourcing` supports optional PR/date/server/RFQ/limit filters and
  rejects `--repair`/`--apply`;
- classifier covers all ten planned states and reports source RFQ item IDs,
  target item/card/export IDs, RFQ numbers, and reasons;
- repository contract tests prove scanner methods use `SELECT` only;
- combined focused suite passes 49/49;
- full suite remains at the known baseline shape: 13/15 suites and 94/105
  tests pass, with all 11 failures in the two pre-existing DIC reminder
  suites;
- read-only execution for the three supplied PRs completed without mutation;
- unfiltered local metrics are broad health signals and are not an approved
  repair list.

### Delivery 5 / Work package 5.1: Data-repair procedure for supplied PRs

#### Implementation plan

1. Add a SELECT-only evidence repository for the seven lifecycle tables listed
   below, selecting only identifiers, assignment/lifecycle fields, and
   timestamps.
2. Add a repair-review service that combines reconciliation findings and
   evidence into a deterministic per-PR recommendation.
3. Add a separate CLI that requires PR, environment, operator, and
   backup/rollback references; emit a fingerprinted before report and support
   comparison with a reviewed before report.
4. Reject `--apply` and `--repair`. Do not introduce direct row mutation,
   terminal reopen, email, or cron execution in this work package.
5. Verify the three supplied PRs against the local replica, then update the
   active spec, indexes, project state, and this plan.

#### Implementation outcome (2026-07-30)

- Added `review:isourcing-repair`, a separate read-only CLI requiring
  prefixed PRs, environment, operator, and backup/rollback references.
- Added SELECT-only evidence collection for `board_card`, `item_card`,
  `exports_data`, `counter_split_pr_items`, `pr_logs`,
  `history_log_assign`, and `report_cs`.
- Added deterministic evidence fingerprints and before/after comparison with
  added, removed, and updated row IDs. `--output` writes UTF-8 JSON directly
  to avoid PowerShell native-redirection encoding drift.
- Added lifecycle-aware recommendations that require the established
  assignment workflow for active unassigned items and prohibit active repair
  for terminal-only PRs.
- `--repair` and `--apply` remain rejected; no mutation path, raw update,
  implicit reopen, cron, or email action was added.
- Delivery 5 focused tests pass 12/12; the combined Delivery 1-5 focused suite
  passes 61/61.
- Full suite passes 16/18 suites and 106/117 tests. The same 11 failures remain
  in the two pre-existing DIC reminder suites.
- The local before report is preserved at
  `evidence/20260730-local-before.json`; its evidence fingerprint is
  `a6ecbe76e84117b66897fd4b78e12cae7efd768f92a81bf1378af752506bb6eb`.
- Local recommendations are workflow assignment for the six supplied active
  items of `B1200027666`, workflow assignment plus stale-export verification
  for item `66245` of `B1200027667`, and no active repair for all 18 terminal
  items of `B1200027605`.

#### Local canary implementation plan (2026-07-31)

1. Scope the first mutation to local `B1200027667`, item `66245`; do not touch
   `B1200027666` or terminal `B1200027605`.
2. Require a fresh single-PR before report, matching fingerprint, private full
   backup, explicit operator/backup references, and an exact local-only
   confirmation phrase.
3. Add a serializable repair operation that:
   - locks the PR cards and selected item;
   - resolves the current MRR/CL route from item material group `2800`;
   - creates or reuses exact active category and assigned CL cards;
   - updates item assignment and the one existing export;
   - updates the one existing PR log and inserts one idempotent CL
     `Auto Assign` history event;
   - verifies every artifact before commit.
4. Add tests for local/environment guards, stale fingerprint, terminal and
   foreign-assignment rejection, rollback at each write boundary,
   postcondition, and idempotent rerun.
5. Execute the canary only after tests pass, save the after report, compare it
   to before state, and rerun reconciliation.

#### Local canary outcome (2026-07-31)

- Target confirmed as local from `.env`; no application/cron Node process was
  running.
- Focused suite passed 75/75 before execution and 79/79 after final CLI
  environment/fingerprint hardening.
- Full suite passes 18/20 suites and 124/135 tests. The same 11 failures remain
  in the two pre-existing DIC reminder suites.
- Before fingerprint:
  `29be015cc5179a90362f321b2abf9d9c87c5844e450b67c8a35748a7cc1dd891`.
- Operation `3e191f03-b879-4bbc-b0fe-a2e156a76e98` repaired only
  `B1200027667` item `66245` in one serializable target transaction.
- Two active MRR route cards, one CL counter, and one CL `Auto Assign` history
  were created; item, export `1100031028`, and PR log `95456` were updated.
- Postcondition and direct target query both confirm CL `65`, material group
  `2800`, active CL card `123944`, and exactly one matching history/log.
- After fingerprint:
  `b7c1d46d85ab97b1645262fbe4bdfcad88a162a5c8ec08503f6700070dd40a3d`.
- Private backup SHA-256:
  `14108df3d70dea073a8ddf2655ece635d2d2a915ba7d8015e07441738c457a38`.
- Evidence hashes prove `B1200027666` and `B1200027605` were unchanged.
- No email, cron, migration, Aigen status update, or terminal reopen ran.

#### Common preparation

1. Deploy or backport the prevention fix before repairing historical rows, so
   the next retry cannot recreate the same state.
2. Run during a controlled window with no concurrent cron/manual action for
   the selected PRs.
3. Re-run the lifecycle-aware scanner against production; do not assume the
   local snapshot still matches production.
4. Export before-state rows for:
   - `board_card`;
   - `item_card`;
   - `exports_data`;
   - `counter_split_pr_items`;
   - `pr_logs`;
   - `history_log_assign`;
   - `report_cs` and lifecycle history tables where present.
5. Confirm current `matrix_auto_assign` output with the iSourcing/category
   owner. Matrix changes must not silently rewrite historical ownership.
6. Prefer the existing Admin assignment workflow for active unassigned items.
   Do not repair these PRs with ad-hoc `UPDATE item_card` statements because
   that would omit board, split, export, history, and notification behavior.

#### `B1200027666`: assign six active unassigned items

Current local state:

- shared active Admin/main card: `board_card.id = 115505`;
- all six affected items are `item_complete = '0'`;
- all six have no CL/CS assignment and only `New Item` history;
- all six export rows point to shared Admin card `115505`;
- current BCG matrix resolves all six items successfully.

Expected assignment groups:

| Item code | Item ID | Material group | Target category / CL |
|---:|---:|---:|---|
| 3 | 66247 | 2600 | MRR / CL user 65 |
| 4 | 69872 | 5300 | MRR / CL user 65 |
| 9 | 66403 | 8700 | GSL / CL user 4 |
| 10 | 66400 | 9900 | GSL / CL user 4 |
| 13 | 66401 | 8300 | GSL / CL user 4 |
| 14 | 66402 | 7600 | GSL / CL user 4 |

Procedure:

1. In iSourcing Admin, search explicitly for `B1200027666`; the default board
   date filter may hide the old main card.
2. Open the active main card and verify the six item IDs/texts against the
   reviewed before-state.
3. Assign item codes 3 and 4 to the MRR/CL-65 destination.
4. Assign item codes 9, 10, 13, and 14 to the GSL/CL-4 destination.
5. Do not reuse a completed card merely because the same user/category had an
   older card. The workflow must create/reuse an active compatible split card.
6. Do not assign CS automatically; that remains the normal subsequent
   iSourcing action.
7. Verify:
   - each item now has the expected `assigned_to_cl`, `send_email_to`, and
     `is_updated`;
   - an active CL card exists for each target category/user;
   - `exports_data` CL fields agree with `item_card`;
   - `Auto Assign`/`Assign` and PR-log timestamps exist once;
   - no duplicate `(pr_number, item_code)` was created;
   - both CL users can retrieve their intended items.

#### `B1200027667`: assign one active unassigned item

Current local state:

- shared active Admin/main card: `board_card.id = 115704`;
- affected item: code 8, `item_card.id = 66245`;
- material group `2800`;
- current BCG matrix target: MRR / CL user 65;
- item is active, unassigned, and has only `New Item` history;
- its export row points to deleted card `115702`, so export/card history is
  stale even though the Admin detail query can functionally return the item
  from card `115704`.

Procedure:

1. Search explicitly for `B1200027667` in iSourcing Admin.
2. Open card `115704` and validate item 8/text against the before-state.
3. Assign item 8 to MRR/CL-65 through the normal Admin assignment action.
4. Ensure the existing completed GSL cards for material group `8000` are not
   reused for this MRR item.
5. Apply the same item/card/export/history/duplicate/role-visibility checks as
   for `B1200027666`.

#### `B1200027605`: terminal lifecycle review, not automatic header repair

Current local state:

- no canonical main card;
- two remaining CS split cards, IDs `109020` and `109021`;
- both surviving cards are split number 3;
- both cards are `complete = '9'`;
- all 13 workbook items are assigned but `item_complete = '9'`;
- their export status is `PR Close`;
- their item-specific counter rows point to split numbers 2, 4, 10, 14, and
  17, whose card IDs have been deleted;
- therefore the two surviving same-PR cards cannot be treated as headers for
  these 13 items. This is a terminal item/card-reference defect, not an active
  unassigned-item defect.

Do not create an active `(1,1,1)` card or set the items back to
`item_complete = '0'` merely to make them appear. That would reopen a closed PR
and may restart sourcing, notification, SLA, and assignment behavior.

Decision path:

1. If the PR is legitimately closed:
   - make no active-board data change;
   - confirm whether completed/history/report screens require the missing
     item-specific cards or can use terminal export/history data;
   - if repair is required, reconstruct only a terminal/audit relationship
     from authoritative backup/audit evidence;
   - do not attach the items to surviving split number 3 merely because the PR
     number is equal.
2. If the PR must be reopened:
   - obtain procurement and iSourcing owner approval;
   - use an approved restore/reopen transition, not a raw header insert;
   - note that the existing restore helper expects a waiting-restore state
     (`complete = '7'`), while this PR is auto-closed (`9`), so the transition
     must be validated in a test copy first;
   - after restore produces an active unassigned Admin card, route each item
     through normal assignment.
3. If production has no matching `board_card` at all, unlike the local replica:
   - reconstruct a terminal/audit representation only from a reviewed backup
     or authoritative lifecycle source;
   - do not reconstruct it as an active `complete = '0'` main card;
   - verify report/history visibility without triggering workflow actions.

If an approved reopen is required, current BCG matrix grouping is:

| Target category / CL | Item codes | Item IDs |
|---|---|---|
| GSL / CL user 4 | 1, 4, 9, 11, 17 | 62846, 62849, 62848, 62847, 62746 |
| MRR / CL user 65 | 6, 7, 8, 10, 12, 14, 16, 18 | 62832, 62109, 62635, 62831, 62741, 62636, 62633, 62634 |

The historical rows currently assign all 13 items to CL user 4. Do not rewrite
that closed history in place. If reopened, create new assignment events through
the approved workflow using the confirmed current or explicitly selected
historical matrix policy.

#### Repair completion evidence

For each PR, preserve:

1. reviewed before-state export;
2. operator, timestamp, environment, and approved decision;
3. UI/workflow action or repair operation ID;
4. after-state export;
5. lifecycle-aware scanner result;
6. role-level visibility result;
7. confirmation that no email/SLA/workflow side effect was triggered for a
   terminal PR unless reopening was explicitly approved.

## Test Plan

### Unit tests

Add focused tests for:

1. cron invocation without `req.params`;
2. HTTP invocation with route/item scope validation;
3. undefined/foreign item IDs;
4. no board and no item;
5. terminal item has valid item-specific history while the main card is
   validly absent;
6. active item already exists but its required role card is missing;
7. board and item already exist (`already_consistent`);
8. failure after item insert rolls back the target transaction;
9. failure creating export/log rows rolls back header and item;
10. primary Aigen update fails after target commit and rerun reconciles safely;
11. concurrent duplicate invocations;
12. multiple material groups;
13. two-vendor sibling item expansion;
14. token deactivation only after verified target success;
15. cron aggregate result reports partial failures;
16. existing PR receives a new item in an already-present material group;
17. existing PR receives a new item in a different material group;
18. new item receives the same assignment/export/history semantics as an
    equivalent initial item;
19. role-level card-detail query can retrieve the newly inserted item;
20. HTTP surrogate and OE routes do not acquire task-board writes;
21. each DIC/CS/OE/CL/Management cron caller propagates transfer failure;
22. nine-day direct transfer uses the same service and postcondition;
23. active late item on a terminal PR returns `TERMINAL_PR_NEW_ITEM`;
24. unmapped material group returns `UNMAPPED_CATEGORY` with no writes;
25. terminal-card deletion does not cause automatic active-card recreation.

### Repository/transaction tests

Use isolated test schemas or transaction-aware repository mocks to assert that
the exact `database_isourcing` transaction is passed to every target write.

Do not rely only on method names or mocked commits. Assert the connection and
transaction object used by each repository call.

### Integration test

Seed lifecycle scenarios with:

- a new multi-material-group PR;
- an active existing PR with one missing item;
- an active item missing its required role card;
- a terminal PR with valid item-specific card/history references;
- a terminal PR receiving an unexpected late item.

Run the domain service and assert:

- required active card exists before active item commit;
- both items exist exactly once;
- export/log records exist exactly once;
- Aigen statuses are correct;
- rerun returns `already_consistent`;
- forced failure leaves no partial target rows;
- valid terminal state remains terminal;
- late terminal item is rejected for review without reopening the PR.

### Existing suite

Run:

```text
cd aigen-backend
npm test -- --runInBand
```

Also run targeted tests first while iterating. Report the known pre-existing
suite failures separately from new regressions.

Static checks:

```text
node --check src/cron.js
node --check src/services/prService.js
node --check src/services/qcfService.js
node --check src/controllers/qcfController.js
node --check src/services/manualSourcingTransferService.js
git diff --check
```

Do not run `npm run run:cron` as a routine test.

## Verification Matrix

| Acceptance criterion | Automated verification | Manual/read-only verification |
|---|---|---|
| Cron works without route params | Service/controller unit test | Targeted non-mutating invocation with mocked integrations |
| Lifecycle-required card exists before active item commit | Transaction failure tests | Lifecycle-aware postcondition report |
| Retry repairs active-card gap | Idempotency unit/integration test | Run reconciliation before/after in test schema |
| Terminal split-only PR is not reopened | Lifecycle unit/integration test | Confirm no new active card |
| Per-item routing matches category matrix | Resolver and role-query tests | Compare item/card/export/history |
| No duplicate items | Concurrent invocation test | Duplicate audit query |
| Aigen status follows verified target success | Failure-order integration test | Cross-schema reconciliation |
| Cron exposes failures | Cron orchestration test | Review exit code and structured logs |
| Existing data repair is safe | Repair-tool dry-run tests | Reviewed before/after primary-key report |

## Rollout Plan

1. Release Delivery 1 and verify invocation behavior.
2. Release Delivery 2 with lifecycle scanner in read-only mode.
3. Observe at least one normal cron window before routing changes.
4. Release Delivery 3 to a controlled/canary server group if supported.
5. Compare:
   - transfer attempts;
   - consistent/already-consistent results;
   - failed operations;
   - new exact orphans;
   - routing mismatches;
   - terminal PR reopen attempts.
6. Release Delivery 4 and review reconciliation results.
7. Enable Delivery 5 only for reviewed PRs.
8. Repair `B1200027667` as the smallest active canary before
   `B1200027666`.
9. Re-run postcondition and role-visibility checks.
10. Handle `B1200027605` only after its close/reopen decision is approved.

Rollback:

- disable repair mode;
- restore the previous application version if transfer errors increase;
- do not delete newly created headers/items automatically;
- use the operation audit to identify any rows requiring manual rollback.

## Documentation Updates During Implementation

Update:

- `aigen-ai/specs/active/auto-manual-sourcing-header-integrity/`;
- `aigen-ai/index/codebase-map.md`;
- `aigen-ai/index/function-index.md`;
- `aigen-ai/index/api-index.md` if cron/manual contracts change;
- `aigen-ai/context/known-issues.md`;
- `aigen-ai/context/project-state.md`;
- `aigen-backend/docs/manual-sourcing/manual-sourcing-flow.md`.

Create an ADR if the work establishes a durable PR identity or a cross-database
consistency strategy.

## Completion Criteria

The task is complete when:

1. both cron and HTTP manual sourcing pass their authorization and invocation
   tests;
2. the iSourcing transaction contains every target write;
3. the lifecycle-required card invariant is checked before and after active
   item persistence;
4. retries repair incomplete state and treat already-correct state as success;
5. no new orphan is produced by injected failures or concurrent tests;
6. the supplied PRs are rechecked against the target environment;
7. any data repair has an approved dry-run and verified before/after report;
8. all relevant commands and pre-existing failures are reported;
9. final diffs preserve unrelated user changes.

## Open Decisions

1. **Resolved for Delivery 3:** late items stop as
   `TERMINAL_PR_NEW_ITEM`; no implicit reopen.
2. **Resolved for Delivery 3:** newly discovered existing-PR items auto-assign
   immediately using the current matrix, matching new-PR behavior.
3. For historical repair, should routing use the current matrix or the matrix
   effective at the original processing date?
4. Is a database migration for item uniqueness or active-card identity
   acceptable after the duplicate audit?
5. **Resolved for Delivery 4:** cron exits non-zero for any failed stage/PR;
   no configurable threshold is introduced.
6. Are production iSourcing audit logs available for 2026-03-16 through
   2026-06-05 for `B1200027605`?
