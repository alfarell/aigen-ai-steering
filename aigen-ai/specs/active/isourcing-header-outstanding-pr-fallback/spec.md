# iSourcing Header Fallback For Outstanding PR Rows

## Status

- Implemented in the `aigen-backend` working tree on 2026-10-05; not committed.
- Primary repository: `aigen-backend` (`production` branch)
- Related spec: `auto-manual-sourcing-header-integrity`
- Production data mutation: Not performed

## Problem

CS manual sourcing to iSourcing fails with `ISOURCING_SOURCE_HEADER_INCOMPLETE`
when the PR has no board card yet. This applies to the HTTP route and to the
cron `handleExpiredCSReview` in `src/services/prService.js`, which reaches the
same code through `qcfController.executeSystemManualSourcing` ->
`sendActionToCS` -> `prosesToIsourcing`. The cron retries on every run and the
item stays at milestone 14.

## Evidence

Confirmed against the local database copy.

- PR 1100014042 / RFQ0002342 / `rfq_library` id 6655 (item 6, BCG). The
  `prpo.search_library` DETAIL row id 153578 has `status = 'Outstanding'` and
  `pr_release_date = NULL`. `company` 2100, `pr_material_group_number` 8000,
  `src_value` 4170000 and `src_currency` IDR are present.
  `rfq_library.pr_release_date` is 2026-09-17 16:54:00.
- RFQ0001963 / `rfq_library` id 5522 (PR 8100020501, item 10, GEMS). Same
  stuck shape, but its `search_library` row 148889 has `is_delete = 1` (line
  deleted in SAP), so this fix intentionally does not transfer it. It stays
  rejected and needs a separate decision (close the item and token).
- Token 8973 remains active because the item never leaves the stuck milestone.
- The local `search_library` has 6,098 `tipe = 'PR'` DETAIL rows with
  `status = 'Outstanding'`. All of them have a NULL `pr_release_date`, and 4,765
  of them have `is_delete = 1` (deleted or cancelled SAP lines).
- 24,264 `Full Release` PR DETAIL rows also have a NULL `pr_release_date`. They
  were excluded by the strict query and will now use the fallback when the strict
  query is empty.

## Root Cause

`getMaterialGroupData` in `src/repository/qcfLibrary.repository.js` only reads
`search_library` DETAIL rows with `status = 'Full Release'` and
`pr_release_date IS NOT NULL`. After a PR is partially converted to PO, the
remaining PR DETAIL rows become `Outstanding` with a NULL release date. The
query returns nothing, the header is built without source data, and
`validateISourcingHeader` rejects it.

## Scope

Only `getMaterialGroupData`:

1. The strict query and the per-material-group dedupe are unchanged. If the
   strict query returns rows, behavior is identical to before.
2. If the strict query returns 0 rows, run a fallback query over the same
   `search_library` rows. It keeps the same filters (`tipe_data = 'DETAIL'`,
   PR number, server group, `material_number IN`, non-empty
   `pr_material_group_number`, `company IS NOT NULL AND company <> 0`) except
   that the `status` and `pr_release_date IS NOT NULL` filters are dropped.
   `tipe = 'PR'` is added, because PO rows share `pr_number`, and
   `(is_delete IS NULL OR is_delete = 0)` is added, because the strict
   `Full Release` filter implicitly excluded deleted lines but the fallback does
   not. The strict SQL is unchanged and has no `is_delete` filter.
3. Fallback ordering prefers `Full Release` rows, then non-NULL release date,
   then the existing completeness ordering.
4. Fallback rows with a NULL `pr_release_date` take the earliest non-NULL
   `rfq_library.pr_release_date` of the requested item ids. The first
   `rfq_library` query now also selects `pr_release_date`. If none exists the
   value stays NULL, so `validateISourcingHeader` still rejects it with the same
   error code.
5. The same per-material-group dedupe is applied to fallback rows. The SELECT
   column list, common filters and ordering are shared between both queries.

## Non-Goals

- Changing the upstream ETL that flips PR rows to `Outstanding`.
- Observability or a user-visible message for the header error.
- The mismatch between `log_sla` and `status_milestone` for stuck items.
- `getFirstSearchLibraryItem`; its caller already falls back to the item text.
- `validateISourcingHeader`, `buildHeaderMetadata`, the cron, and callers.
- Backfilling or retrying already stuck items by script; the cron retries them.

## Acceptance Criteria

1. When the strict query returns rows, no fallback query runs and the result is
   unchanged.
2. When the strict query is empty, Outstanding PR rows are used and a NULL
   release date is filled from `rfq_library.pr_release_date`.
3. Fallback rows are deduped to one per `pr_material_group_number`.
4. A fallback row with a NULL release date and no `rfq_library` release date
   keeps NULL, so header validation still fails with the same error code.
5. An existing non-NULL release date on a fallback row is not overwritten.
6. The fallback excludes PO rows (`tipe = 'PR'`) and deleted rows
   (`is_delete IS NULL OR is_delete = 0`), and keeps the company, material group
   and `material_number` guards. The strict SQL is unchanged.
7. With no item codes, `[]` is returned and `search_library` is not queried.
8. All queries use Sequelize `replacements`.

## Test Plan

Automated, `aigen-backend/tests/repository/qcfLibrary.getMaterialGroupData.test.js`
(mocks `sequelize.query`):

- strict rows returned: one `search_library` query, fallback not run;
- strict empty: fallback row filled from `rfq_library`, deduped per group,
  fallback SQL and replacements asserted;
- existing release date preserved;
- NULL stays NULL without an `rfq_library` date;
- no item codes: `[]`, no `search_library` query;
- strict and fallback both empty: `[]`;
- the fallback SQL contains the `is_delete` guard and the strict SQL does not;
- the strict SQL and replacements are pinned (company, group, material group
  and ordering fragments).

Regression: `tests/controllers/qcfController.manualSourcingHeader.test.js`,
`tests/services/prService.handleExpiredCSReview.test.js`, `tests/repository`.

Manual, read-only against the local database copy (2026-10-05):

- `getMaterialGroupData('1100014042', 'BCG', [{ id: 6655 }])` returns source
  row 153578 with `pr_release_date` 2026-09-17 16:54:00 (+07:00), company 2100,
  material group 8000, 4170000 IDR.
- `getMaterialGroupData('8100020501', 'GEMS', [{ id: 5522 }])` returns `[]`
  because the only source row is `is_delete = 1`, as intended.
- `getMaterialGroupData('1100014048', 'BCG', [{ id: 6853 }])` (normal
  Full Release) returns its strict row 154319 unchanged.

Not yet performed: confirm in a non-production environment that the cron moves
token 8973 / rfq 6655 past milestone 14.

## Rollout And Rollback

- Backend-only, no schema, data, API or frontend change. Deploy `aigen-backend`
  alone.
- After deploy, stuck items are picked up by the next `handleExpiredCSReview`
  cron run.
- Rollback: revert the `getMaterialGroupData` change. Items return to the
  previous stuck behavior; no data cleanup is needed.

## Risks

- A fallback row may carry stale `src_value` or `src_currency` from an
  Outstanding row. These fields were already used from Full Release rows and are
  still validated by `validateISourcingHeader`.
- Mixed batches (some items `Full Release`, some `Outstanding`) still drop the
  Outstanding material groups, because the fallback only runs when the strict
  query returns 0 rows. This is pre-existing behavior and out of scope.
- The release date written to the header is the RFQ's date rather than the
  search library's, which is the only source available when the library value is
  NULL.
