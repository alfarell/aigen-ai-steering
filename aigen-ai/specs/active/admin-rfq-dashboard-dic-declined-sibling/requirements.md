# Requirements — Admin RFQ dashboard hides re-sent parallel batch behind a DIC-declined sibling

Status: Planned  
Owner: Unknown  
Repositories: aigen-backend  
Created: 2026-09-28  
Last updated: 2026-09-28

## Background and problem

Production incident: for `RFQ0002235`, Admin cannot perform Manual Sourcing from the RFQ dashboard/detail flow.

Verified against a local copy of the production database (read-only replication, 2026-09-28):

| Vendor batch | Vendor (matrix level) | `vendor_type` | `vendor_sequence` | `status_vendor` | `status_dic` | `status_milestone` |
|---|---|---|---|---|---|---|
| 2 | 108357 (level 2) | agregator | 3 (PARALLEL) | 1 ACCEPTED | **2 DECLINED** | 8 DIC_REVIEWED |
| 3 | 103716 (level 1) | direct | 3 (PARALLEL) | 0 PENDING | 3 | 2 RFQ_SENT_TO_VENDOR |

DIC declined the batch-2 quotation, and the RFQ was re-sent to vendor 103716 as batch 3 (active `Waiting_vendor_expiry` token until 2026-09-29). Both batches cover item codes 60/70/80/90.

Output of `listRfqAdmin` for this RFQ:

- Only the batch-2 row is returned. `toAdminRfqFlatRow` labels it `Waiting CL` / `DIC Reject` with `action = null`, so the frontend shows only **View**.
- The batch-3 row (which `ADMIN_RFQ_LABEL_MAP[RFQ_SENT_TO_VENDOR]` would label `Waiting Vendor` with action `Manual Sourcing`) is missing.

Root cause (confirmed): the `sibling_active` derived table in `listRfqAdmin` (`aigen-backend/src/repository/rfqLibrary.repository.js`, joined at ~L900-907 and used in `rowHavingFilter` ~L845-851 and `JSON_ARRAYAGG` ~L878-886) treats any PARALLEL row that is past milestones 1/2/22 and not vendor-REJECTED as an "active sibling". It does not look at `status_dic`. A DIC-declined sibling therefore still counts as active. Every item of the re-sent batch-3 row becomes `NULL` in `items`, and the `HAVING` clause drops the row. The same `FROM` feeds the count query, so pagination totals are also affected.

The CS dashboard (`listRfqNew`) is not affected. Its parallel-coverage checks already exclude DIC-declined siblings with `(status_dic IS NULL OR status_dic != DECLINED)` (L551, L557, L583, L589).

## Goal

A PARALLEL RFQ row that is waiting for a vendor (milestones 1/2/22) stays visible on the Admin RFQ dashboard when its only processed sibling for the same item was declined by DIC. Admin can then open it and perform Manual Sourcing.

## Scope

- Included:
  - The `sibling_active` definition in `listRfqAdmin` (data query and count query, which share the same `FROM`).
  - Regression tests for the generated SQL.
- Excluded:
  - CS, User, Vendor, CL, and Management dashboards.
  - Labelling of the DIC-declined batch-2 row on the Admin dashboard, which still shows as `Waiting CL` (see Unknowns U-2).
  - `getNotSubmittedItems` not returning `is_manual_sourcing` (separate, non-blocking gap).
  - `sendActionToCS` behaviour of pulling the other vendor level's items into the iSourcing transfer (see Unknowns U-3).
  - Frontend changes. None are needed: the Admin `Waiting Vendor` row routes to `/cs/not-submitted-items/:rfq/:batch` (`useRedirectAdminRFQ.js`), and `useManualSourcing` Case 5 (Admin + `BID Submitted` + `Waiting Vendor`) shows the button.

## Actors

| Actor/system | Need or responsibility |
|---|---|
| Admin | Sees every actionable RFQ row and can trigger Manual Sourcing while a vendor is still pending. |
| DIC | Declines a vendor quotation. This must not suppress the remaining vendor's pending row. |
| Backend `listRfqAdmin` | Returns correct rows and pagination totals for the Admin RFQ dashboard. |

## Functional requirements

- **FR-1:** A PARALLEL row counts as an active sibling in `listRfqAdmin` only when all of these hold: `status_milestone NOT IN (RFQ_LAUNCHED, RFQ_SENT_TO_VENDOR, RFQ_NOT_SUBMITTED)`, `status_vendor != REJECTED`, and `status_dic` is `NULL` or not `DECLINED`.
- **FR-2:** The `status_dic` check is NULL-safe. Siblings with `status_dic IS NULL` (DIC has not decided yet) still count as active.
- **FR-3:** The count query and the data query apply the same rule, so `pagination.totalItems` matches the rows returned.
- **FR-4:** Existing suppression behaviour for non-declined active siblings is unchanged. A pending PARALLEL row is still hidden when another vendor's row for the same item is progressing and not DIC-declined.

## Business rules

- **BR-1 (Inferred from `listRfqNew` precedent and commit `7d1771d3`):** In parallel sourcing, a vendor's pending row is hidden only while another vendor is actively progressing on the same item. A DIC-declined vendor is no longer progressing.
- **BR-2 (Confirmed, `ADMIN_RFQ_LABEL_MAP`):** Admin gets action `Manual Sourcing` for rows at `RFQ_SENT_TO_VENDOR`, `RESEND_RFQ`, and `QUOTATION_RESEND_RFQ` (`Waiting Vendor`).

## Security and permissions

- Authentication mechanism: unchanged (dashboard JWT via `authService.authenticateToken`).
- Required roles/permissions/token purpose: unchanged. `listRfqAdmin` has no user filter, which is intended for Admin.
- Sensitive data/logging constraints: no new data exposed. The change only affects which existing rows are returned.
- Abuse or replay considerations: none. The change is read-only.

## Acceptance criteria

- **AC-1:** Given a PARALLEL RFQ where vendor A's rows are `DIC_REVIEWED` / `status_vendor = ACCEPTED` / `status_dic = DECLINED` and vendor B's rows for the same item codes are `RFQ_SENT_TO_VENDOR` / `PENDING`, when Admin loads the RFQ dashboard, then vendor B's row is returned with status `Waiting Vendor` and action `Manual Sourcing`.
- **AC-2:** Given the same data, when Admin clicks **Action** on vendor B's row, then the Not Submitted Items page shows the **Manual Sourcing** button (no frontend change; verified manually).
- **AC-3:** Given a PARALLEL RFQ where vendor A's rows are past milestone 2 with `status_dic IS NULL` (or `ACCEPTED`/`REQUEST_REVISION`) and vendor B is `RFQ_SENT_TO_VENDOR`, when Admin loads the dashboard, then vendor B's row is still hidden (existing behaviour preserved).
- **AC-4:** Given any filter/search/page combination, when Admin loads the dashboard, then `pagination.totalItems` equals the number of rows the unpaginated data query would return (count and data share the rule).
- **AC-5:** Given `RFQ0002235` on the production-copy database, when `listRfqAdmin({ search: 'RFQ0002235' })` runs, then it returns the batch-3 / vendor 103716 row as `Waiting Vendor` with action `Manual Sourcing`.

## Non-functional requirements

- Performance/concurrency: one added predicate inside an existing derived table. There is no new join or fan-out, and no measurable impact is expected.
- Reliability/idempotency: read-only query, not applicable.
- Observability: none required.
- Accessibility/UX: unchanged.
- Compatibility: response shape unchanged. The Admin dashboard may show more rows than before for affected RFQs.

## Dependencies and unknowns

| Item | Status | Owner/evidence |
|---|---|---|
| U-1: Was the incident reported by Admin or CS? CS behaviour (`Waiting Vendor`, `action = null` until the vendor token expires) is by design. | Unknown | Reporter |
| U-2: Should the Admin dashboard hide or relabel DIC-declined rows (batch 2 now shows `Waiting CL` / `DIC Reject`), as `listRfqNew` does via `NOT (MAX(status_dic) = DECLINED AND has_sibling_need_action = 0)`? | Unknown, product decision | Product/Business |
| U-3: When Manual Sourcing runs for vendor level 1, `sendActionToCS` (`qcfController.js` ~L214-241) also includes the level-2 vendor's items for the same item codes, including DIC-declined rows. Is this intended? | Unknown | Product/Business; `qcfController.sendActionToCS` |
| U-4: Should `sibling_active` also require a different `vendor_code` (the CS query uses `sib5.vendor_code != t.vendor_code`)? | Deferred, see design alternatives | Engineering |
