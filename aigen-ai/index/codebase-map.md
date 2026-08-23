# Codebase map

## Major modules

| Component | Entry points | Main modules | Depends on |
|---|---|---|---|
| Backend HTTP | `aigen-backend/app.js` | `src/routes/`, controllers, services, repositories/models | Three MySQL schemas, email, Google OAuth, Sentry, SAP/iFlow, filesystem uploads |
| Backend workflow cron | `aigen-backend/server.js`, `src/cron.js` | `prService`, `qcfService`, `manualSourcingInvocationService`, `manualSourcingTransferService`, `qcfController` | Primary DB, task-board DB, email, workflow configuration |
| Backend iSourcing reconciliation | `aigen-backend/cli/reconcile-isourcing.js` | `isourcingReconciliationService`, `isourcingReconciliation.repository` | Read-only Aigen and task-board queries |
| Backend iSourcing repair review | `aigen-backend/cli/review-isourcing-repair.js` | `isourcingRepairReviewService`, `isourcingRepair.repository`, reconciliation service | Read-only task-board evidence and before/after comparison |
| Backend local iSourcing repair | `aigen-backend/cli/apply-isourcing-repair-local.js` | `manualSourcingTransferService`, `isourcingRepairReviewService`, repair/QCF repositories | Local-only guarded task-board transaction and private backup |
| Backend SAP sync | `aigen-backend/src/sync.js` | `rfqController.getSyncSAPPO` | Primary DB, SAP API |
| Frontend SPA | `aigen-frontend/src/main.js` | router, features, services, stores | Backend API, Google Sign-In, Sentry |
| PR import Kafka worker | `aigen-import-pr/worker.js` | event handler, `AigenSourcingService` | Kafka, three MySQL schemas, backend HTTP |
| PR import CLI | `aigen-import-pr/app.js` | `AigenSourcingService` | Three MySQL schemas, backend HTTP |

## Backend route ownership

| Prefix | Route file | Primary responsibility |
|---|---|---|
| `/health` | `src/routes/healthRoutes.js` | service/database health |
| `/auth` | `src/routes/authRoutes.js` | basic login/reset, Google OAuth, session profile, role switching |
| `/pr` | `src/routes/purchaseRoutes.js` | PR/RFQ/QCF dashboards and workflow actions |
| `/autopo` | `src/routes/configRoutes.js` | Auto PO settings and available values |
| `/upload` | `src/routes/uploadRoutes.js` | document/image/evidence lifecycle |
| `/email` | `src/routes/emailRoutes.js` | notifications and resend operations |
| `/acl` | `src/routes/aclRoutes.js` | roles and permissions |
| `/master` | `src/routes/masterDataRoutes.js` | users, matrices, divisions, hierarchy, assignments, categories, vendors |
| `/mock` | `src/routes/mockRoutes.js` | authenticated mock RFQ/search setup |

## Backend domain layers

- **PR/RFQ/QCF workflow:** `prController.js`, `rfqController.js`, `qcfController.js`, `prService.js`, `qcfService.js`, `manualSourcingInvocationService.js`, `manualSourcingTransferService.js`, `cronObservabilityService.js`, `isourcingReconciliationService.js`, `isourcingRepairReviewService.js`, `PurchaseRequest.repository.js`, `rfqLibrary.repository.js`, `qcfLibrary.repository.js`, `isourcingReconciliation.repository.js`, `isourcingRepair.repository.js`. Cron manual sourcing enters through a server-owned trusted adapter; HTTP retains route/item/policy checks; both converge on an atomic task-board transfer service. Cron emits safe stage reports, one CLI scans lifecycle state, and a separate read-only CLI produces repair evidence without providing a mutation path.
- **Sparse-header branch note:** `fix/qcf-controller-param-checking` still executes the legacy `qcfController.prosesToIsourcing()` path. Its localized guard selects source metadata deterministically, establishes and verifies a valid active Admin header for initial and existing PRs, and wraps all scoped target reads/writes in one `database_isourcing` transaction. `prService` and `qcfService` call a controller-owned trusted entry point; HTTP requests retain explicit route scope and policy validation.
- **Dashboards:** `dashboardController.js` → `dashboardService.js` → query helpers/repositories.
- **Identity and ACL:** `authController.js`, `authService.js`, `aclController.js`, `aclService.js`, user/role/permission repositories and models.
- **Master data:** user matrix, division, hierarchy, assignment, category, category matrix, and vendor controller/service/repository sets.
- **Notifications:** `emailController.js`, `emailServices.js`, `emailHelper.js`, template files, Nodemailer configuration.
- **Cross-cutting:** middleware, `src/helper/date.js`, response/log helpers, error classes, constants, validation schemas.

## Frontend feature ownership

- `features/auth/`: login, reset, OAuth callback.
- `features/dashboard/`: role-specific dashboards and RFQ/QCF list routing.
- `features/form/vendor/`: quotation and preview.
- `features/form/dic/`: confirmation, preview, and sourcing continuation.
- `features/form/cs/`: declined/not-submitted/OE mismatch/surrogate/manual-sourcing/preview paths.
- `features/form/cl/`: QCF summary approval and preview, also reused for Management/token read-only flows.
- `features/master-data/`: users, user matrix, divisions, hierarchy, assignment, categories, category matrix.
- `features/settings/`: Auto PO configuration.

Most feature data flows are `provider/context -> hooks -> src/services/<domain> -> shared Axios`.

## Import worker ownership

```text
Kafka message
  -> worker.js / lib/kafka-consumer.js
  -> handlers/import-pr.handler.js
  -> AigenSourcingService.importPRData()
       -> queries/isearch + queries/isourcing + queries/aigen
       -> aigen.pr_library
  -> AigenSourcingService.syncRFQData()
       -> assignment/config/counter queries
       -> aigen.rfq_library
       -> backend email endpoints
       -> clear aigen.pr_library
```

## Change routing

| Change | Start inspection at |
|---|---|
| New/changed API | backend route → controller/service/repository; bundled OpenAPI; corresponding frontend/worker service |
| Workflow status or approval | backend constants/policy/service/repositories; frontend route/action mapping; cron; tests |
| PR import/assignment | importer service/query modules; backend material-assignment models/services; importer transaction risk |
| New master data | backend schema/migration/model/repository/service/controller/route; frontend service/provider/table/form |
| Role/permission change | backend ACL/auth/middleware; frontend role constants/router/sidebar; token paths |
| Email/link change | backend email controller/service/template/token storage; frontend target route and error handling |
| Dashboard mismatch | backend dashboard query/helper/service plus matching frontend query params/table mapping |
| SAP/Auto PO | backend config/controller/repository/sync; importer `config_auto_po` reads; server-group behavior |
