# Project state

Snapshot date: 2026-07-30.

## Repository state

| Repository | Status |
|---|---|
| `aigen-backend` | **Verified:** working tree already had user changes in `package-lock.json` and `src/controllers/qcfController.js` before this bootstrap. They are not part of the steering work. |
| `aigen-frontend` | **Verified:** clean at bootstrap inspection. |
| `aigen-import-pr` | **Verified:** clean at bootstrap inspection. |

## Implemented capabilities

- **Verified:** Internal basic/Google authentication, persisted JWT session, role switching, ACL roles/permissions, and master-data administration.
- **Verified:** Role-specific dashboards for CS, User/DIC, CL, Management, Vendor, and Admin.
- **Verified:** Vendor quotation, DIC confirmation/sourcing, CS exception handling, CL/Management QCF approval, attachments, and notification flows.
- **Verified:** Scheduled reminders and stage-expiry processing through backend cron code.
- **Verified:** SAP Auto PO sync entry point.
- **Verified:** Kafka and CLI PR import with configurable assignment strategy, RFQ creation, backend notification calls, and three-schema reads.
- **Verified:** GEMS QCF manual-PO pilot logic is feature-flagged in backend and represented in frontend route/approval behavior.
- **Verified:** Admin master data includes users, divisions, roles, categories, category matrices, material hierarchy, and material assignment.
- **Verified (2026-08-23):** iSourcing transfer runs behind a driver layer. `ISOURCING_TRANSFER_DRIVER` selects `database` (default, current production behavior) or `api`. Both app and cron environments must carry the same value; each logs its active driver at boot. The `api` driver is a structurally complete skeleton whose payload and error mapping stay provisional until the iSourcing contract is published.

## Partially implemented or weakly verified

- **Verified:** Frontend README contains an old numbered TODO list for screens that now have routes/services/components. Completion of every edge case is **Unknown**; the list should not be treated as current scope.
- **Verified:** Frontend has no automated tests, so implemented role/token/UI journeys are weakly protected.
- **Verified:** Import worker has no automated tests and its transaction helper is not used consistently by service queries.
- **Verified:** Backend Jest is currently red: the 2026-08-23 run on `develop-dot` passed 21/23 suites and 187/198 tests. All 11 failures belong to the two pre-existing DIC reminder suites, unchanged from the run taken before the iSourcing driver work. Module loading still opens database connections during unit tests.
- **Inferred:** OpenAPI is intended as the external API contract, but route/OpenAPI drift has not been fully diffed.
- **Unknown:** Production deployment topology, Kafka retry/dead-letter policy, database backup/restore, release process, and operational ownership.

## Recent implementation signals

- **Verified:** Auto manual sourcing Delivery 1 now separates trusted cron
  invocation from untrusted HTTP input, restores the shared runtime variables,
  and propagates structured per-RFQ failures from DIC/CS/OE/CL/Management
  stages. Focused tests pass 8/8. Atomic task-board writes, active-card
  integrity, idempotency, and postcondition checks were completed in Delivery
  2. Delivery 3 now applies current-matrix routing per item for both new and
  existing PRs and verifies card/export/history/log alignment. The combined
  focused suite passes 37/37. Delivery 4 adds operation-scoped cron summaries,
  non-zero failure behavior, Sentry tags, health metrics, and a SELECT-only
  lifecycle reconciliation CLI. The Delivery 1-4 focused suite passes 49/49.
  Delivery 5 now has a SELECT-only, fingerprinted seven-table repair-review
  report with lifecycle recommendations and before/after comparison. A
  guarded local-only executor then repaired the `B1200027667` item `66245`
  canary with private backup, serializable transaction, and after-report.
  The combined focused suite passes 79/79; non-local historical mutation
  remains approval-gated.
- **Verified on 2026-08-03:** the branch-local sparse-header mitigation on
  `fix/qcf-controller-param-checking` validates critical source metadata,
  deterministically selects one source row per material group, and repairs or
  creates the active Admin header before a missing item is written on both
  initial and existing-PR paths. The legacy transfer now uses one
  `database_isourcing` transaction for all target reads/writes, verifies the
  Admin header and inserted items before commit, and updates primary RFQ/QCF
  state only after target commit. Cron callers use the controller-owned
  trusted entry point while HTTP callers require complete route scope. The 20
  focused controller/repository regressions pass. This branch does not contain
  the previously documented transfer-service implementation, so production
  deployment behavior remains unverified.
- **Verified from Git history:** recent work includes GEMS manual-PO pilot behavior, material hierarchy/assignment corrections, dashboard analytics/list corrections, and frontend route proxying.
- **Verified:** backend migrations exist for Aigen, task-board, and PRPO schemas.
- **Verified:** the import worker retains both `material_assignment` and legacy `vendor_matriks_assign` resolution paths, selected by environment.

## Deprecated or legacy areas

- **Verified:** `aigen-backend/server.js` is an alternate cron launcher while `app.js` is the HTTP entry.
- **Verified:** `aigen-backend/package.json` script name `xxx` invokes `server.js`; the name is legacy/non-descriptive.
- **Verified:** import worker comments and README identify `vendor_matriks_assign` as the legacy assignment method.
- **Inferred:** large PR/QCF controllers and mixed validation paths represent transitional architecture; do not refactor without feature scope and regression coverage.
