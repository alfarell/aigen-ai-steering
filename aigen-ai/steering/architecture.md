# Architecture

## System context

```text
SAP-derived PR snapshot (prpo/iSearch)
               |
               v
aigen-import-pr (Kafka event or CLI)
  | reads iSearch + iSourcing + Aigen config
  | writes Aigen pr_library/rfq_library/counter/logs
  | calls backend notification endpoints
               |
               v
aigen-backend (Express API + cron + SAP sync)
  | reads/writes Aigen, iSourcing, iSearch
  | email / Google OAuth / Sentry / SAP / iFlow / uploads
               |
               v
aigen-frontend (Vue SPA)
  internal authenticated roles + token-linked Vendor/DIC/CS journeys
```

Evidence: `aigen-import-pr/app.js`, `aigen-import-pr/worker.js`, `aigen-import-pr/services/aigen.js`, `aigen-backend/app.js`, `aigen-frontend/src/main.js`.

## Runtime components

### Backend API

`aigen-backend/app.js` loads environment/Sentry first, configures Express, body parsing, query normalization, static uploads, Swagger UI, route groups, 404 handling, and the final error middleware.

HTTP flow is generally:

```text
route -> auth/token/permission/validation middleware -> controller
      -> service -> repository/Sequelize model -> MySQL
```

Legacy/large workflow controllers sometimes call repositories and integrations directly, so the layering is not uniform. `purchaseRoutes.js` is the primary procurement interface and delegates to PR, RFQ, QCF, dashboard, and cron controllers.

### Backend background entry points

- `server.js` invokes `src/cron.js`.
- `src/cron.js` runs legacy reminders plus staged expiry handlers for Vendor Direct, Vendor, DIC, CS, OE, CL, and Management.
- `src/sync.js` invokes SAP PO synchronization through `rfqController.getSyncSAPPO()`.

These entry points connect to the primary database and are operational/mutating commands.

### Frontend

`src/main.js` creates the Vue app, initializes Sentry, registers plugins, and mounts `App.vue`. `src/router/index.js` lazy-loads feature pages and uses hash history. Authentication state is persisted in `src/stores/useAuthStore.js`; `src/utils/http-common.js` attaches Bearer tokens, while `src/router/interceptor.js` handles session and token-link errors.

The feature pattern is:

```text
route page -> feature provider/context -> hooks -> service -> Axios -> backend
```

Not every feature uses every layer, but new work should follow the local feature's pattern.

### Import worker

- `worker.js` subscribes to the configured Kafka topic.
- `handlers/import-pr.handler.js` accepts `AIGEN_IMPORT_PR_REQUEST`.
- `app.js` exposes the same two-step process as a one-shot CLI.
- `services/aigen.js` implements `importPRData()` then `syncRFQData()`.
- `queries/<logical-db>/` contains parameterized SQL strings.
- `lib/database.js` owns mysql2 pools and transaction helpers.

## Persistence boundaries

| Schema | Backend | Import worker | Important evidence |
|---|---|---|---|
| Aigen | Read/write through Sequelize and repositories; migrations/seeders | Read/write with mysql2 raw SQL | `aigen-backend/src/config/database.js`, `aigen-import-pr/queries/aigen/` |
| iSourcing/task board | Read/write in selected backend workflows | Read-only in current worker queries | `aigen-backend/src/config/database_isourcing.js`, `aigen-import-pr/queries/isourcing/` |
| iSearch/prpo | Search/read plus migration support | Reads `search_library` | `aigen-backend/src/config/database_isearch.js`, `aigen-import-pr/queries/isearch/search-library.js` |

Backend migrations are grouped under `migrations/aigen`, `migrations/task_board`, and `migrations/prpo`.

## Important data flows

### PR to RFQ

1. Importer reads released search rows for a configured lookback.
2. It skips existing RFQ/item-card/staging rows and applies Auto PO config.
3. It resolves vendor/CS using either material assignment or the legacy vendor matrix method.
4. It writes eligible rows to `pr_library`.
5. It groups rows by server group, PR, vendor, and CS; below-threshold groups receive RFQ records.
6. It sends backend notification requests and clears staging on the successful path.

### RFQ/QCF lifecycle

Vendor responses and attachments enter through `/pr/vendor/*` and `/upload/*`. DIC and CS review routes update status/milestone fields and send notifications. CL and Management approve QCFs according to configuration and the GEMS feature policy. Some successful QCF flows create/update iSourcing board data or proceed toward SAP sync.

### Authentication and authorization

- Internal users: basic login or Google OAuth → backend JWT → Pinia persisted session → Bearer header.
- Vendor/DIC links: JWT in route parameter → token middleware and persisted token-table checks.
- Backend ACL: authenticated user permission slugs for ACL/master-data operations; workflow routes use a mixture of auth, token, and domain checks.
- Frontend role metadata is navigation/UI enforcement, not a substitute for backend authorization.

## Constraints

- The three repositories use different Node versions and two package managers.
- Database-configured states, thresholds, and role mappings are runtime data, so source alone cannot describe every transition.
- Background processes can send real emails and mutate shared state; do not use them as routine verification.
- Import staging and RFQ-number generation require concurrency-safe, connection-bound Aigen transactions. Current importer calls open a transaction from an `isearch`-keyed helper while Aigen queries use another pool; this is detailed in `../context/known-issues.md`.
