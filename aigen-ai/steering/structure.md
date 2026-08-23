# Repository structure

## Workspace

```text
AGENTS.md                 canonical shared workflow
CLAUDE.md                 thin Claude Code adapter
aigen-ai/                 shared steering, state, indexes, specs, and workflows
aigen-backend/            independent Git repository
aigen-frontend/           independent Git repository
aigen-import-pr/          independent Git repository
```

Run Git and package commands inside the relevant child repository.

## Backend placement

| Path | Responsibility |
|---|---|
| `app.js` | HTTP entry point and route composition |
| `server.js`, `src/cron.js`, `src/sync.js` | background entry points |
| `src/routes/` | Express endpoint and middleware wiring |
| `src/controllers/` | HTTP adaptation and legacy workflow orchestration |
| `src/services/` | reusable business logic |
| `src/repository/` | Sequelize/raw-query data access |
| `src/models/default/` | primary Aigen Sequelize models |
| `src/models/isourcing/`, `src/models/isearch/` | external-schema models |
| `src/validations/`, `src/controllers/validation/` | Joi and legacy request validation |
| `src/middleware/` | auth, tokens, permissions, uploads, normalization, errors |
| `src/helper/`, `src/const/`, `src/errors/`, `src/utils/` | cross-cutting logic |
| `migrations/<db>/`, `seeders/<db>/` | timestamped SQL pairs/data |
| `tests/` | Jest tests grouped by source concern |
| `docs/openapi/` | bundled OpenAPI contract |

Place new domain behavior in a service when practical, keep controllers thin, and keep all data access transaction-aware in repositories. Follow an existing nearby module when legacy code differs.

## Frontend placement

| Path | Responsibility |
|---|---|
| `src/main.js`, `src/App.vue` | application bootstrap/root |
| `src/router/` | route table, role metadata, response handling |
| `src/features/<domain>/` | feature pages, components, hooks, context/providers, utilities |
| `src/services/<domain>/` | backend API calls and response mapping |
| `src/components/` | genuinely cross-feature UI |
| `src/stores/` | persisted/global Pinia state |
| `src/hooks/` | cross-feature composables |
| `src/utils/` | framework-light utilities and Axios client |
| `src/plugins/` | Vuetify, Pinia, Query, and other app plugins |
| `src/const/`, `src/types/` | shared constants/types |

The codebase mixes `.js`, `.ts`, and `.vue`. Do not convert neighboring files merely for consistency. New feature-specific tests should live beside the feature or in a documented test tree once a harness is selected.

## Import-worker placement

| Path | Responsibility |
|---|---|
| `worker.js` | Kafka consumer entry |
| `app.js` | one-shot CLI entry |
| `handlers/` | event validation/dispatch |
| `services/aigen.js` | import, assignment, RFQ creation, notification orchestration |
| `queries/aigen/` | primary-schema SQL |
| `queries/isearch/`, `queries/isourcing/` | external-schema reads |
| `lib/` | DB pools/transactions, Kafka, Sentry |
| `config/`, `const/` | environment mapping and domain constants |
| `utils/` | small pure helpers |

Add new SQL to the appropriate logical-database query module. Do not embed credentials, physical environment-specific schema names, or multi-statement SQL.

## Naming observed

- JavaScript functions/variables: camelCase.
- Classes/components: PascalCase; Vue component files are PascalCase.
- Backend files are mixed camelCase and descriptive dot-suffix names (for example `*.query.repository.js`); follow the owning module.
- Frontend composables begin with `use`; providers/contexts live under explicit `provider/` and `context/` folders.
- SQL migrations and seeders use sortable timestamp prefixes and paired `.up.sql`/`.down.sql` where applicable.

