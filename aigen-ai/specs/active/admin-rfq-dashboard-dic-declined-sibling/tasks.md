# Tasks — Admin RFQ dashboard hides re-sent parallel batch behind a DIC-declined sibling

## Discovery

- [x] Verify current behavior and reproduction/evidence (`listRfqAdmin` replicated on production-copy DB for `RFQ0002235`, 2026-09-28).
- [ ] Confirm requirements, actors, rules, and unknowns (U-1 reporter role, U-2 declined-row label, U-3 `sendActionToCS` cross-level items).
- [x] Check Git status in aigen-backend before editing (clean on `develop-dot`; a pre-existing unfinished interactive rebase was left untouched).
- [x] Identify interfaces, data, security, jobs, and integrations (read-only query change; no interface/data/integration change).

## Implementation

- [x] Backend: in `src/repository/rfqLibrary.repository.js` → `listRfqAdmin` → `buildDataExtraJoins`, add `AND (status_dic IS NULL OR status_dic != ${STATUS_DIC.DECLINED})` to the `sibling_active` derived table.
- [x] Backend: confirm `STATUS_DIC` is imported in `rfqLibrary.repository.js` (already imported at L20).
- [ ] Frontend: N/A. The row routes to `NotSubmittedItemsCS` and `useManualSourcing` Case 5 already allows Admin.
- [ ] Import worker: N/A. Not involved.
- [ ] API/OpenAPI/event contract: N/A. The response shape is unchanged.
- [ ] Data migration/backfill/rollback: N/A. There is no schema or data change.
- [ ] Observability/security: N/A.

## Tests

- [x] Add `tests/repository/rfqLibrary.listRfqAdmin.siblingActive.test.js` (mock `sequelize.query`, following `rfqLibrary.listRfqUser.hasPoPublished.test.js`):
  - [x] the data query contains the NULL-safe `status_dic` predicate inside `sibling_active` (AC-1, AC-3);
  - [x] the count query contains the same predicate (AC-4);
  - [x] the existing `status_milestone` / `status_vendor` predicates are still present (AC-3).
- [x] Complete the acceptance-criteria mapping in `test-plan.md`.

## Verification and handoff

- [x] Run `npm test -- tests/repository/rfqLibrary.listRfqAdmin.siblingActive.test.js` and the existing `tests/repository/` and `tests/helper/dashboardHelper*` suites.
- [x] Re-run the read-only replication (`listRfqAdmin({ search: 'RFQ0002235' })`) on the production-copy DB and confirm the batch-3 row appears (AC-5).
- [ ] Manually verify, as Admin: dashboard → Action → Not Submitted Items → Manual Sourcing button visible (AC-2). Do not submit against production data.
- [ ] Update `aigen-ai/index/` if the function/test index lists `listRfqAdmin` tests.
- [x] Review the final diff for unrelated changes and secrets (code-reviewer: approve with notes, 2026-09-28).
- [ ] Record unverified behavior, rollout order (backend only), and rollback (revert).
- [ ] Move this specification to `completed/` only after acceptance criteria are met.
