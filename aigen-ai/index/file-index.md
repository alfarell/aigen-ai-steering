# Important file index

This is intentionally selective. Generated files, assets, and trivial helpers are excluded.

| File | Purpose | Module | Important dependencies |
|---|---|---|---|
| `aigen-backend/app.js` | Compose/start Express API | Backend entry | config, Sentry, routes, error middleware, OpenAPI |
| `aigen-backend/config.js` | Validate/map backend environment | Backend config | Joi, environment |
| `aigen-backend/src/cron.js` | Run reminder and stage-expiry work | Backend jobs | Sequelize, PR/QCF services/controllers |
| `aigen-backend/src/sync.js` | Run SAP PO sync | Backend jobs | primary DB, RFQ controller |
| `aigen-backend/src/services/isourcing/isourcingTransfer.port.js` | Single route into iSourcing; resolve driver, guard result shape, log | Backend iSourcing transfer | feature flag helper, drivers, Sentry |
| `aigen-backend/src/services/isourcing/drivers/database.driver.js` | Write task_board directly in one transaction (moved from `qcfController.js`) | Backend iSourcing transfer | iSourcing DB, QCF repository |
| `aigen-backend/src/services/isourcing/drivers/api.driver.js` | Transfer through the iSourcing public API (contract stubbed) | Backend iSourcing transfer | iSourcing API client, QCF repository |
| `aigen-backend/src/api/isourcing.api.js` | Axios client for the iSourcing public API, Basic Auth and redaction | Backend iSourcing transfer | axios, config |
| `aigen-backend/src/const/isourcing-transfer.js` | Driver names, outcomes, canonical and contract error codes | Backend iSourcing transfer | none |
| `aigen-backend/src/services/isourcing/isourcingReconciliation.service.js` | Poll queued transfers, finish deferred Aigen work, re-send or escalate | Backend iSourcing transfer | status client, transfer-request repository, QCF repository, token stores |
| `aigen-backend/src/repository/isourcingTransferRequest.repository.js` | Persist and query submitted transfers; build idempotency keys | Backend iSourcing transfer | `isourcingTransferRequest` model |
| `aigen-backend/src/models/default/isourcingTransferRequest.js` | Model for `isourcing_transfer_requests` | Backend iSourcing transfer | primary DB |
| `aigen-backend/src/routes/purchaseRoutes.js` | Main PR/RFQ/QCF HTTP contract | Backend workflow | auth/token middleware, workflow controllers |
| `aigen-backend/src/routes/authRoutes.js` | Login/OAuth/reset/profile contract | Backend identity | auth controller, authentication |
| `aigen-backend/src/routes/masterDataRoutes.js` | Master-data HTTP contract | Backend admin | auth, permissions, validators/controllers |
| `aigen-backend/src/controllers/prController.js` | PR/RFQ request orchestration | Backend workflow | repositories, email, uploads, status helpers |
| `aigen-backend/src/controllers/qcfController.js` | QCF and reminder orchestration | Backend workflow | QCF/RFQ repositories, tokens, email |
| `aigen-backend/src/controllers/rfqController.js` | RFQ list/detail and SAP sync | Backend workflow | RFQ repository, SAP client/config |
| `aigen-backend/src/services/prService.js` | PR/RFQ expiration and business logic | Backend workflow | repositories, transactions, email |
| `aigen-backend/src/services/qcfService.js` | QCF expiration/approval logic | Backend workflow | QCF repositories, policy/email |
| `aigen-backend/src/services/authService.js` | JWT, login, OAuth, roles | Backend identity | user repositories/models, JWT, Google APIs |
| `aigen-backend/src/repository/rfqLibrary.repository.js` | RFQ persistence and workflow queries | Backend data | Sequelize, primary DB |
| `aigen-backend/src/repository/qcfLibrary.repository.js` | QCF and iSourcing persistence/queries | Backend data | primary/iSourcing models and DBs |
| `aigen-backend/src/services/isourcingRepairReviewService.js` | Build lifecycle-aware before/after repair evidence and recommendations | Backend operations | reconciliation service, repair evidence repository |
| `aigen-backend/src/repository/isourcingRepair.repository.js` | SELECT-only repair evidence across seven legacy task-board tables | Backend data | iSourcing connection |
| `aigen-backend/cli/review-isourcing-repair.js` | Run guarded read-only repair review and after-state comparison | Backend operations | repair review service, primary/iSourcing connections |
| `aigen-backend/cli/apply-isourcing-repair-local.js` | Execute one reviewed local repair with fingerprint, backup, confirmation, and after-report gates | Backend operations | transfer service, repair review/repository, primary/iSourcing connections |
| `aigen-backend/src/utils/prepareCliEnvironment.js` | Load CLI environment and supply a non-routable Sentry fallback only for local CLI validation | Backend operations | env loader |
| `aigen-backend/src/repository/PurchaseRequest.repository.js` | PR/RFQ data access | Backend data | three schema connections/models |
| `aigen-backend/src/helper/qcfWorkflowPolicy.js` | GEMS/manual-PO approval policy | Backend policy | feature flags, status/role constants |
| `aigen-backend/src/helper/date.js` | Business-day/date calculations | Shared backend | Moment/timezone |
| `aigen-backend/src/middleware/tokenMiddleware.js` | Validate token-linked RFQ access | Backend security | JWT, persisted token model |
| `aigen-backend/docs/openapi/openapi.bundle.yaml` | Bundled API description | API contract | live route/controller parity |
| `aigen-frontend/src/main.js` | Bootstrap Vue and Sentry | Frontend entry | plugins, router |
| `aigen-frontend/src/router/index.js` | Route table and role guard | Frontend navigation | auth store, role/domain constants |
| `aigen-frontend/src/router/interceptor.js` | Global HTTP error navigation | Frontend navigation | Axios, auth store, notifications |
| `aigen-frontend/src/utils/http-common.js` | Axios base client/Bearer header | Frontend API | environment, auth store |
| `aigen-frontend/src/stores/useAuthStore.js` | Persisted login/session/role state | Frontend identity | Pinia, AuthService, JWT helpers |
| `aigen-frontend/src/services/AuthService.js` | Basic/OAuth/reset API mapping | Frontend identity | shared Axios |
| `aigen-frontend/src/services/form/cl/QuotationSummaryCLService.js` | CL/Management/CS QCF calls | Frontend QCF | shared Axios |
| `aigen-frontend/src/services/form/vendor/VendorQuotationService.js` | Vendor quotation/upload API calls | Frontend RFQ | shared Axios |
| `aigen-frontend/src/services/master-data/material-assignment/MaterialAssignmentService.js` | Material-assignment CRUD/options | Frontend admin | shared Axios |
| `aigen-import-pr/worker.js` | Start Kafka consumer and shutdown hooks | Import entry | Kafka config/consumer, handler, Sentry |
| `aigen-import-pr/app.js` | Parse and run one-shot import CLI | Import entry | AigenSourcingService |
| `aigen-import-pr/handlers/import-pr.handler.js` | Dispatch import event | Import events | service, Sentry |
| `aigen-import-pr/services/aigen.js` | Import, assignment, RFQ creation, email calls | Import domain | Database, query modules, backend Axios |
| `aigen-import-pr/lib/database.js` | mysql2 pools/query/transaction helper | Import data | database config, Sentry |
| `aigen-import-pr/lib/kafka-consumer.js` | Subscribe/parse/dispatch messages | Import events | KafkaJS, Sentry |
| `aigen-import-pr/config/database.config.js` | Map logical schema connections | Import config | environment |
| `aigen-import-pr/queries/isearch/search-library.js` | Select import candidates | Import query | iSearch schema |
| `aigen-import-pr/queries/aigen/material_assignment.js` | Resolve hierarchy assignment | Import query | Aigen schema |
| `aigen-import-pr/queries/aigen/rfq-library.js` | Detect/insert RFQ rows | Import query | Aigen schema |
