# Interface index

The bundled OpenAPI document is `aigen-backend/docs/openapi/openapi.bundle.yaml`. The live Express route files remain authoritative when they disagree. This index groups related endpoints and operational interfaces; inspect the route and OpenAPI schema for exact fields.

| Interface | Method/Type | Handler | Auth | Input | Output | Tests |
|---|---|---|---|---|---|---|
| `/health/` | GET | `healthController.healthCheck` | Public | none | health data | Unknown |
| `/auth/login`, `/auth/login/basic` | POST | `authController.usersLogin` / `basicLogin` | Public credentials | login body | JWT/user context | Unknown |
| `/auth/login/oauth/google` | GET/POST | OAuth URL/authenticate handlers | Public OAuth | callback/code body | auth result/JWT | Unknown |
| `/auth/basic/forgot-password`, `/auth/basic/reset-password` | POST | auth handlers | Public token flow | email or reset token/password | status | Unknown |
| `/auth/me`, `/auth/switch-role` | GET/PUT | auth handlers | Bearer | session / role selection | current/switched context | Unknown |
| `/acl/roles*`, `/acl/permissions*` | REST CRUD | `aclController` | Bearer + permission | page/DTO/IDs | role/permission records | Unknown |
| `/master/users*`, `/master/users/matrices*` | REST/bulk | user/user-matrix controllers | Bearer + permission | pagination/bulk DTO | user/matrix data | Unknown |
| `/master/divisions*` | REST/bulk | `divisionController` | Bearer + permission | pagination/bulk DTO | division data | Unknown |
| `/master/master-hierarchy*` | REST/bulk | `materialHierarchyController` | Bearer + permission | hierarchy DTO | hierarchy data | Unknown |
| `/master/material-assignments*` | GET/PUT/DELETE | `materialAssignmentController` | Bearer + permission | filters/bulk DTO | assignment tree/data | service partial |
| `/master/categories*`, `/master/category-matrices*`, `/master/vendors*` | REST/bulk | domain controllers | Bearer + permission | filters/bulk DTO | master data | Unknown |
| `/autopo/*` | GET/POST | `configController`, `configValueController` | Bearer | settings/config params | config/available values | Unknown |
| `/pr/dashboard-{cs,user,cl,management,vendor,admin-rfq,admin-qcf}` | GET | `dashboardController` | Bearer | filters/pagination | dashboard analytics/list data | Unknown |
| `/pr/listPR`, `/pr/getDetailPR` | GET/POST | `prController` | Bearer | pagination/PR number | PR list/detail | Unknown |
| `/pr/listRFQ*`, `/pr/detail`, `/pr/listQCF` | GET | PR/RFQ/QCF controllers | mostly Bearer | filters/identifiers | lists/detail | Unknown |
| `/pr/vendor/get_item_list_rfq/*` | GET | `prController` | token or internal path | token or vendor/RFQ/batch | quotation items | Unknown |
| `/pr/vendor/submit_penawaran` | PUT | `prController` | token/Bearer context | quotation DTO | workflow result | Unknown |
| `/pr/dic/get_item_list_rfq*`, `/pr/dic/konfirmasi_penawaran` | GET/PUT | `prController` | token or Bearer | token/RFQ and confirmation DTO | items/result | Unknown |
| `/pr/cs/{declined_items,not_submitted_items,price_not_match,oe_revision,surrogate_items}/*` | GET | PR controller | Bearer or purpose token | RFQ/batch/token | exception items | Unknown |
| `/pr/cs/{send_surrogate,send_revisi_oe,send_isourcing,send_to_qcf}/*` | POST | PR/QCF controller | Bearer | RFQ/batch/action DTO | transition result; iSourcing lifecycle failures include `error_code` | iSourcing invocation/transfer service tests |
| `/pr/cl/need_approval_qcf/*`, `/pr/cl/approve_qcf/*` | GET/PUT | QCF controller | Bearer or purpose token | QCF/token/comment | QCF detail/result | Policy unit tests only |
| `/pr/management/need_approval_qcf/*`, `/pr/management/approve_qcf/*` | GET/PUT | QCF controller | Bearer or token | QCF/token/comment | QCF detail/result | Policy unit tests only |
| `/upload/{image,images,document,evidence,evidences,files}` | POST/DELETE | `uploadController` | No router-wide auth; caller policy varies | multipart or file paths | stored paths/delete result | Unknown |
| `/email/send-request-for-quotation/:token` | POST | `emailController.sendRequestForQuotation` | signed token without DB validation | JWT path | send result | Unknown |
| `/email/send-pr-received/:token` | POST | `emailController.sendReceived` | signed token without DB validation | JWT path | send result | Unknown |
| `/email/resend-*` | POST | email handlers | mixed Bearer/public | RFQ/vendor IDs or failed-email state | resend result | Unknown |
| `/pr/rfq/run-cron` | POST | `cronController.runCron` | inspect route before use | stage/RFQ filters | cron summary | Unknown |
| `/pr/rfq/send-*-reminders`, `/pr/rfq/handle-*` | POST | QCF/cron handlers | mixed/manual operational | optional days/filter | processing summary | DIC reminder partial |
| `AIGEN_IMPORT_PR_REQUEST` | Kafka event | `handleImportPREvent` | Kafka infrastructure | `{eventType,timestamp,payload:{requestId,lastPeriodDays}}` | side effects/logs | None |
| `node app.js aigen import-pr-data --last-period-days=N` | CLI command | importer `app.js` | host/process access | optional lookback | side effects/exit code | None |
| `npm run run:cron` | scheduled command | backend `src/cron.js` | host/process access | optional direct function filters | DB/email side effects | Partial components |
| `npm run run:sync` | scheduled command | backend `src/sync.js` | host/process access | none | SAP/DB side effects | None |

Two route-string caveats visible in callers/source should be checked before changing contracts:

- Frontend uses both case variants such as `/upload/evidences` and `/upload/Evidences`; Express routing defaults may hide this locally.
- Endpoint naming uses both underscores and hyphens. Do not normalize paths without a coordinated migration.
