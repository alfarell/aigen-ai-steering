# Important symbol index

| Symbol | Type | File | Responsibility | Used By | Tests |
|---|---|---|---|---|---|
| Express `app` composition | entry | `aigen-backend/app.js` | HTTP middleware/routes/startup | deployed API | Unknown |
| `runCronTasks` | function | `aigen-backend/src/cron.js` | Select/run expiry and reminder stages | `cronJob`, manual cron controller | Unknown |
| `cronJob` | function | `aigen-backend/src/cron.js` | Authenticate DB and run cron work | direct script, `server.js` | Unknown |
| `cronSync` | function | `aigen-backend/src/sync.js` | Run SAP PO synchronization | direct script | Unknown |
| `usersLogin` | handler | `aigen-backend/src/controllers/authController.js` | Legacy/dashboard login adapter | `/auth/login` | Unknown |
| `basicLogin` | handler | `aigen-backend/src/controllers/authController.js` | Basic-login adapter | `/auth/login/basic` | Unknown |
| `authenticateToken` | middleware | `aigen-backend/src/services/authService.js` | Verify internal Bearer session | protected routes | Unknown |
| `switchRole` | service/handler | `aigen-backend/src/services/authService.js`, controller | Resolve active user matrix/role | `/auth/switch-role` | Unknown |
| `decodeTokenFromParams` | middleware | `aigen-backend/src/middleware/tokenMiddleware.js` | Verify JWT and active RFQ token row | token-linked routes | Unknown |
| `decodeGemsManualPoToken` | middleware | `aigen-backend/src/middleware/qcfCsTokenMiddleware.js` | Validate stored CS manual-PO QCF token | QCF token route | `qcfCsTokenMiddleware.test.js` |
| `sendResponse` | helper | `aigen-backend/src/helper/log.js` | Standard backend JSON response | controllers/middleware | Partial: `log.test.js` covers another export |
| `routeAsyncWrapper` | helper | `aigen-backend/src/helper/routeAsyncWrapper.js` | Forward async errors to Express middleware | route modules | Unknown |
| `calculateBusinessDays` / `addBusinessDays` / `subtractBusinessDays` | helpers | `aigen-backend/src/helper/date.js` | Workflow deadline arithmetic | token/SLA/reminder logic | Partial: `date.test.js` |
| `canApproveQcfAsCL` | policy | `aigen-backend/src/helper/qcfWorkflowPolicy.js` | Gate CL approval | QCF workflow | `qcfWorkflowPolicy.test.js` |
| `canApproveQcfAsManagement` | policy | same | Gate Management approval | QCF workflow | `qcfWorkflowPolicy.test.js` |
| `canManualSource` | policy | same | Gate post-QCF manual sourcing | QCF workflow | `qcfWorkflowPolicy.test.js` |
| `sendDicConfirmationReminders` | handler | `aigen-backend/src/controllers/qcfController.js` | Token reuse/creation and DIC reminders | cron/manual route | `qcfController.dicReminder.test.js` |
| `findPendingDicConfirmationRfqs` | repository function | `aigen-backend/src/repository/rfqLibrary.repository.js` | Select interval-matching DIC reminder RFQs | QCF controller | `rfqLibrary.dicReminder.test.js` |
| `handleExpiredVendor` | service function | `aigen-backend/src/services/prService.js` | Progress expired vendor stage | cron | Unknown |
| `handleExpiredCLReview` | service function | `aigen-backend/src/services/qcfService.js` | Progress expired CL stage | cron | Unknown |
| `sendActionToCS` | handler | `aigen-backend/src/controllers/qcfController.js` | Validate HTTP RFQ sourcing actions and require complete route scope for iSourcing | purchase routes, trusted controller entry point | `qcfController.manualSourcingHeader.test.js` |
| `executeSystemManualSourcing` | trusted controller entry | `aigen-backend/src/controllers/qcfController.js` | Mark only in-process cron calls as trusted without accepting a body-controlled bypass | `prService`, `qcfService` expiry handlers | `qcfController.manualSourcingHeader.test.js` |
| `prosesToIsourcing` / header validator | controller-local workflow | `aigen-backend/src/controllers/qcfController.js` | Atomically build/repair/verify the active Admin header and requested iSourcing items before target commit | `sendActionToCS` | `qcfController.manualSourcingHeader.test.js` |
| `getMaterialGroupData` / `findActiveAdminCard` / `findValidHeaderCardByTitle` / `updateAdminCardHeader` | repository functions | `aigen-backend/src/repository/qcfLibrary.repository.js` | Deterministically select source metadata and propagate the target transaction through Admin header reads/repairs | `prosesToIsourcing` | `qcfController.manualSourcingHeader.test.js`, `qcfLibrary.isourcingTransaction.test.js` |
| `executeSystemManualSourcing` | service function | `aigen-backend/src/services/manualSourcingInvocationService.js` | Create a trusted server-owned manual-sourcing invocation and normalize its result | DIC/CS/OE/CL/Management expiry handlers | `manualSourcingInvocationService.test.js` |
| `validateManualSourcingItemScope` | service function | `aigen-backend/src/services/manualSourcingInvocationService.js` | Reject missing, unknown, or foreign iSourcing item scope before writes | `sendActionToCS` | `manualSourcingInvocationService.test.js` |
| `throwIfManualSourcingFailures` | service function | `aigen-backend/src/services/manualSourcingInvocationService.js` | Aggregate per-RFQ transfer failures so cron stages reject | expiry handlers | `manualSourcingInvocationService.test.js` |
| `transferToISourcing` | service function | `aigen-backend/src/services/manualSourcingTransferService.js` | Atomically reconcile task-board card/item state and verify lifecycle postcondition | `qcfController`, nine-day adapter | `manualSourcingTransferService.test.js` |
| `resolveTransferPlan` | pure service function | `aigen-backend/src/services/manualSourcingTransferService.js` | Resolve each missing item from its own iSearch material metadata and current iSourcing category/CL route | `transferToISourcing` | `manualSourcingTransferService.test.js` |
| `assertTransferPostcondition` | service function | `aigen-backend/src/services/manualSourcingTransferService.js` | Require one reachable active card for each touched active item before target commit | `transferToISourcing` | `manualSourcingTransferService.test.js` |
| `findCardsByTitle` / `findItemCardsByCodes` | repository functions | `aigen-backend/src/repository/qcfLibrary.repository.js` | Deterministically lock target PR card/item state on the iSourcing transaction | transfer service | `qcfLibrary.isourcingTransaction.test.js` |
| `getISourcingRoutes` / `findTransferArtifactsByItemIds` | repository functions | `aigen-backend/src/repository/qcfLibrary.repository.js` | Resolve deterministic current category/CL routes and re-read export/history/PR-log assignment artifacts on the target transaction | transfer service | `qcfLibrary.isourcingTransaction.test.js` |
| `observeCronStage` / `createCronReport` | service functions | `aigen-backend/src/services/cronObservabilityService.js` | Collect safe operation-scoped selected/transfer/failure summaries and drive cron failure status | `src/cron.js`, manual-sourcing adapter | `cronObservabilityService.test.js`, `cron.test.js` |
| `classifyReconciliationState` / `runReconciliationScan` | service functions | `aigen-backend/src/services/isourcingReconciliationService.js` | Classify item/card/export lifecycle integrity and orchestrate filtered read-only reports | reconciliation CLI | `isourcingReconciliationService.test.js` |
| `getCronHealthMetrics` | repository function | `aigen-backend/src/repository/isourcingReconciliation.repository.js` | Return aggregate no-card, missing-postcondition, and possible primary-retry metrics via SELECT queries | cron | `isourcingReconciliation.readOnly.test.js` |
| `createRepairReview` / `compareRepairReviews` | service functions | `aigen-backend/src/services/isourcingRepairReviewService.js` | Build fingerprinted lifecycle-aware repair evidence and compare reviewed before/after snapshots | repair-review CLI | `isourcingRepairReviewService.test.js` |
| `findRepairEvidence` | repository function | `aigen-backend/src/repository/isourcingRepair.repository.js` | Read safe identifiers, lifecycle fields, and timestamps from seven task-board tables | repair-review service | `isourcingRepair.readOnly.test.js` |
| `repairExistingActiveAssignments` | service function | `aigen-backend/src/services/manualSourcingTransferService.js` | Atomically route and repair reviewed existing active unassigned item artifacts | local repair CLI | `manualSourcingTransferService.test.js` |
| `findFullRepairBackup` | repository function | `aigen-backend/src/repository/isourcingRepair.repository.js` | Read full selected-PR task-board rows for a private local rollback artifact | local repair CLI | `isourcingRepair.readOnly.test.js` |
| `findItemCardsByIds` / `updateItemAssignment` / `updateExportAssignment` / `updatePrLogAssignment` | repository functions | `aigen-backend/src/repository/qcfLibrary.repository.js` | Lock reviewed item scope and align assignment artifacts on the target transaction | repair transfer service | `qcfLibrary.isourcingTransaction.test.js` |
| `updateMaterialAssignmentFromMasterHierarchy` | service function | `aigen-backend/src/services/materialAssignmentService.js` | Reconcile assignment rows after hierarchy changes | hierarchy workflows | `materialAssignmentService.test.js` |
| `createDashboardHandler` | handler factory | `aigen-backend/src/controllers/dashboardController.js` | Adapt role context to dashboard service | dashboard routes | Unknown |
| `useAuthStore` | Pinia store | `aigen-frontend/src/stores/useAuthStore.js` | Persist auth, user, role, return URL | router, Axios, screens | None |
| router `beforeEach` guard | navigation guard | `aigen-frontend/src/router/index.js` | Require session and role metadata | all frontend routes | None |
| `RegisterInterceptor` | function | `aigen-frontend/src/router/interceptor.js` | Map HTTP failures to login/expired page | frontend bootstrap/router | None |
| `http` | Axios instance | `aigen-frontend/src/utils/http-common.js` | API base and auth header | frontend services | None |
| `getQuotation`, `approveQuotation`, `getManagementQuotation`, `approveManagementQuotation` | service functions | `aigen-frontend/src/services/form/cl/QuotationSummaryCLService.js` | QCF view/approve calls for CL/Management/token | CL feature hooks | None |
| `saveQuotation` | service function | `aigen-frontend/src/services/form/vendor/VendorQuotationService.js` | Submit vendor quotation | Vendor quotation feature | None |
| `useTableFilter` | composable | `aigen-frontend/src/hooks/filters/useTableFilter.js` | Shared reactive table filtering | data tables | None |
| `AigenSourcingService` | class | `aigen-import-pr/services/aigen.js` | Own the import and RFQ pipeline | CLI/event handler | None |
| `AigenSourcingService.importPRData` | method | same | Read/filter/assign/stage PRs | CLI/event handler | None |
| `AigenSourcingService._getMaterialAssignment` | method | same | Resolve most-specific assignment/manual sourcing | import and RFQ sync | None |
| `AigenSourcingService.syncRFQData` | method | same | Convert staged PR groups to RFQ and clear staging | CLI/event handler | None |
| `AigenSourcingService._getAigenNextRFQNumber` | method | same | Allocate RFQ counter/format number | `_submitRFQ` | None |
| `handleImportPREvent` | handler | `aigen-import-pr/handlers/import-pr.handler.js` | Dispatch and report Kafka import event | Kafka consumer | None |
| `subscribe` | function | `aigen-import-pr/lib/kafka-consumer.js` | Connect, parse JSON, invoke handler | `worker.js` | None |
| `Database.transaction` | method | `aigen-import-pr/lib/database.js` | Begin/commit/rollback on one pool connection | importer | None; callers may bypass connection |

“Unknown” under Tests means no direct test was confirmed, not that the symbol is unused.
