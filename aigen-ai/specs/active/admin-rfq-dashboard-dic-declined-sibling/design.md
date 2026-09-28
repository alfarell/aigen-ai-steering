# Design — Admin RFQ dashboard hides re-sent parallel batch behind a DIC-declined sibling

## Current behavior

`listRfqAdmin` (`aigen-backend/src/repository/rfqLibrary.repository.js` ~L833) calls `listRfqDashboard` with:

- `buildDataExtraJoins`, which LEFT JOINs a derived table `sibling_active` (~L900-907):

  ```sql
  SELECT DISTINCT rfq_number, item_code
  FROM rfq_library
  WHERE vendor_sequence = 3 /* PARALLEL */
    AND status_milestone NOT IN (1, 2, 22) /* RFQ_LAUNCHED, RFQ_SENT_TO_VENDOR, RFQ_NOT_SUBMITTED */
    AND status_vendor != 2 /* REJECTED */
  ```

- `buildDataSelect` (~L878-886): `JSON_ARRAYAGG` emits `NULL` for an item when the row is PARALLEL, `sibling_active` matched, and the row's milestone is 1/2/22.
- `rowHavingFilter` (~L845-851): `SUM(CASE WHEN <same condition> THEN 0 ELSE 1 END) > 0` drops a grouped row when every item is suppressed.
- `listRfqDashboard` (~L385-405) builds both the count query and the data query from the same `dataFrom` and `HAVING`, so both are affected.

History: `sibling_active` replaced `any_accepted` in commit `7d1771d3` ("filter parallel RFQ items where sibling vendor is actively processing"). The `HAVING` move came in `db9b61e9` (pagination count fix). Neither commit considered `status_dic`.

For `RFQ0002235`, the batch-2 rows (vendor 108357, `DIC_REVIEWED`, `ACCEPTED`, `status_dic = DECLINED`) satisfy the `sibling_active` predicate for item codes 60/70/80/90. The batch-3 rows (vendor 103716, `RFQ_SENT_TO_VENDOR`) are therefore all suppressed and the row is removed. The result was replicated by calling `listRfqAdmin` against the production-copy DB.

The CS dashboard (`listRfqNew`, ~L541-598) already guards the equivalent sibling checks with `(sib5.status_dic IS NULL OR sib5.status_dic != ${STATUS_DIC.DECLINED})`.

## Proposed behavior

Add a NULL-safe DIC-declined exclusion to the `sibling_active` derived table:

```js
LEFT JOIN (
    SELECT DISTINCT rfq_number, item_code
    FROM rfq_library
    WHERE vendor_sequence = ${VENDOR_SEQUENCE.PARALLEL}
      AND status_milestone NOT IN (${STATUS_MILESTONE.RFQ_LAUNCHED}, ${STATUS_MILESTONE.RFQ_SENT_TO_VENDOR}, ${STATUS_MILESTONE.RFQ_NOT_SUBMITTED})
      AND status_vendor != ${STATUS_VENDOR.REJECTED}
      AND (status_dic IS NULL OR status_dic != ${STATUS_DIC.DECLINED})
) sibling_active ON sibling_active.rfq_number = t.rfq_number
                 AND sibling_active.item_code = t.item_code
```

Requirement coverage:

- FR-1/FR-2: the new predicate, written NULL-safe in the same form as `listRfqNew`.
- FR-3: only `dataFrom` changes, and both the count query and the data query use it.
- FR-4: non-declined siblings still match, so existing suppression is unchanged.

`STATUS_DIC` is already imported in `rfqLibrary.repository.js` (L20), so no new import is needed.

## Affected components

| Repository/component | Current symbol/path | Proposed change |
|---|---|---|
| aigen-backend | `listRfqAdmin` → `buildDataExtraJoins` → `sibling_active` in `src/repository/rfqLibrary.repository.js` | Add `AND (status_dic IS NULL OR status_dic != ${STATUS_DIC.DECLINED})` |
| aigen-backend | `tests/repository/` | New test `rfqLibrary.listRfqAdmin.siblingActive.test.js` |

## Interface changes

None. The `GET` Admin RFQ dashboard route and response shape are unchanged. Affected RFQs may return additional rows.

## Data design

- Schemas/tables/models: none. The query reads `rfq_library.status_dic`, an existing column.
- Migration/seed/backfill: none.
- Transaction boundary: not applicable (read-only).
- Idempotency/concurrency: not applicable.
- Data retention/rollback: code revert only.

## UI and state

- Routes and role metadata: unchanged.
- Feature components/hooks/services: no change. Verified path: `TableAdminRFQ.vue` → `useActionButtonAdminRFQ.isAction` (status `Waiting Vendor`, action non-null) → `useRedirectAdminRFQ` (`'waiting vendor'` → `/cs/not-submitted-items/:rfq/:batch`) → `NotSubmittedItemsCS.vue` → `useManualSourcing` Case 5 (Admin + `BID Submitted` + `Waiting Vendor`).
- Loading/empty/error/success behavior: unchanged.
- Accessibility: unchanged.

## Security

- Backend authorization: unchanged.
- Token lifetime/purpose/revocation: not affected.
- Validation: not affected.
- Logging/redaction: not affected.

## Integrations and failure handling

None. Manual Sourcing execution (`POST /pr/cs/send_isourcing/...` → `qcfController.sendActionToCS`) is unchanged. See requirements U-3.

## Alternatives considered

| Alternative | Reason accepted/rejected |
|---|---|
| Add `status_dic` exclusion to `sibling_active` (NULL-safe) | **Accepted.** Smallest change, matches the `listRfqNew` precedent, and fixes count and data together. |
| Also correlate on `vendor_code != t.vendor_code` (as `sib5` in `listRfqNew`) | Deferred (U-4). The derived table is keyed by `(rfq_number, item_code)` with `DISTINCT`. Adding `vendor_code` would fan out join rows and could duplicate `JSON_ARRAYAGG` items and skew `SUM` in `HAVING`. It would need a rewrite to `EXISTS`, which is out of scope for this incident. |
| Rewrite `sibling_active` as a correlated `EXISTS` identical to `listRfqNew` | Rejected for now. Larger blast radius on a query recently tuned for pagination (`db9b61e9`). |
| Data fix for `RFQ0002235` only | Rejected. The same state recurs for any parallel RFQ where DIC declines one vendor and the other is re-sent. |
| Frontend workaround | Rejected. The row never reaches the frontend. |

## Risks and mitigations

| Risk | Likelihood/impact | Mitigation |
|---|---|---|
| `status_dic != 2` written without the NULL guard would drop undecided siblings and un-hide rows unintentionally | Medium / Medium | NULL-safe predicate (FR-2) plus a test asserting the exact predicate text (AC-3) |
| More rows appear for Admin on RFQs with a DIC-declined sibling, including the declined row still labelled `Waiting CL` | High / Low | Expected. The declined-row label is tracked separately (U-2). |

## Rollout and rollback

- Deploy order: aigen-backend only. No frontend or import-worker dependency.
- Monitoring: check the Admin RFQ dashboard for `RFQ0002235` after deploy, and watch Sentry/console for `Error fetching RFQ data (Admin)`.
- Rollback: revert the backend commit. There is no data change.
