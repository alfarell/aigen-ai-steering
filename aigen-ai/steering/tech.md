# Technology

## Runtime matrix

| Repository | Verified runtime and stack | Version evidence |
|---|---|---|
| `aigen-backend` | Node.js CommonJS, Express 4, Sequelize 6, MySQL 8-compatible driver, Joi, JWT, Nodemailer, Multer, Sentry, Jest 29 | `.nvmrc`, `package.json`, `Dockerfile` |
| `aigen-frontend` | Vue 3.5, Vite 5, Vuetify 3, Vue Router 4, Pinia, TanStack Vue Query, Axios, ApexCharts, Sentry | `package.json`, `vite.config.mjs` |
| `aigen-import-pr` | Node.js CommonJS, KafkaJS, mysql2/promise, Axios, date-fns, JWT, Pino, Sentry | `.nvmrc`, `package.json` |

- Backend Node: **Verified** `v22.14.0`.
- Frontend Node/package manager: **Verified from README** Node `v20.19.6`, pnpm `10.22.0`; no engine constraint exists in `package.json`.
- Import worker Node: **Verified** `v24.9.0`.
- MySQL: **Verified from backend README** version 8.0; exact deployed patch versions are **Unknown**.

## Storage and infrastructure

- Three logical MySQL schemas share connection settings:
  - `aigen`: main application, workflow, ACL, configuration, RFQ/QCF, logs.
  - `task_board`/iSourcing: users and board/card data consumed by backend; importer treats it as read-only.
  - `prpo`/iSearch: SAP-derived PR search data; importer treats it as read-only.
- Kafka triggers the import worker with an import event.
- Backend exposes HTTP and static uploads, sends SMTP/Mailtrap email, calls SAP and iFlow endpoints, and reports to Sentry.
- Frontend is a static SPA with hash routing and a configured API base URL.
- Docker artifacts exist in all repositories. Local backend compose provisions MySQL and mail testing; import compose provisions worker-related development services.

Evidence: `aigen-backend/config.js`, `aigen-backend/docker-compose.yml`, `aigen-import-pr/config/database.config.js`, `aigen-import-pr/config/kafka.config.js`, `aigen-frontend/src/utils/http-common.js`.

## Verified package scripts

### Backend

| Command | Script/source | Purpose |
|---|---|---|
| `npm start` | `node app.js` | HTTP API |
| `npm run dev` | `nodemon app.js` | Development API |
| `npm test` | `jest` | Jest suite |
| `npm run migrate -- up --db=<aigen|task_board|prpo>` | `node cli/migrate.js` | Apply SQL migrations |
| `npm run migrate:create -- --db=<db> --name=<name>` | `node cli/migrate-create.js` | Create migration pair |
| `npm run seed -- --db=<db>` | `node cli/seed.js` | Apply seeders |
| `npm run run:cron` | `node src/cron.js` | Run reminder/expiry workflows |
| `npm run run:sync` | `node src/sync.js` | Run SAP PO sync |
| `npm run reconcile:isourcing -- [filters]` | `node cli/reconcile-isourcing.js` | Read-only iSourcing lifecycle reconciliation report |
| `npm run review:isourcing-repair -- [required review references]` | `node cli/review-isourcing-repair.js` | Read-only before/after repair evidence and lifecycle decision gate |
| `npm run apply:isourcing-repair-local -- [guarded repair arguments]` | `node cli/apply-isourcing-repair-local.js` | Local-only, fingerprint-gated transactional repair; mutates task-board state |

### Frontend

| Command | Script/source | Purpose |
|---|---|---|
| `pnpm run dev` | `vite` | Development server |
| `pnpm run build` | `eslint . --max-warnings=0 && vite build` | Validate and build `dist/` |
| `pnpm run preview` | `vite preview` | Preview built SPA |
| `pnpm run lint` | `eslint . --fix` | Mutating lint/fix |
| `pnpm exec eslint . --max-warnings=0` | ESLint dependency/config | Non-mutating lint verification |

### Import worker

| Command | Script/source | Purpose |
|---|---|---|
| `npm run start:worker` | `node worker.js` | Kafka consumer |
| `npm run dev:worker` | `nodemon worker.js` | Reloading consumer |
| `npm run aigen:import-pr -- --last-period-days=<days>` | `node app.js aigen import-pr-data` | One-shot import/sync |
| `npm run lint` | `eslint . --ext .js` | Non-mutating lint |
| `npm run lint:fix` | `eslint . --ext .js --fix` | Mutating lint/fix |
| `npm run format` | `prettier --write "**/*.js"` | Mutating format |

## Environment variable names

Values must never be copied into documentation.

- Backend: `NODE_ENV`, `PORT`, `APP_URL`, `FRONTEND_URL`, `UPLOAD_DIR`, `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_DATABASE`, `DB_DATABASE2`, `DB_DATABASE3`, DB pool settings, `JWT_SECRET`, `JWT_EXP`, mail/SMTP settings, SAP/iFlow settings, Google OAuth settings, Sentry settings, pagination/timezone, and GEMS manual-PO settings.
- Frontend: `BASE_URL`, `VITE_API_URL`, Google Sign-In client ID, and Sentry build/runtime settings.
- Import worker: DB/schema settings, Kafka client/group/topic settings, `AIGEN_API_URL`, `AIGEN_JWT_SECRET`, `ASSIGN_CS_CL_METHOD`, `LAST_PERIOD_SYNC`, logging, timezone, and Sentry settings.

Canonical lists are the three `.env.example` files plus runtime config validators/loaders.

## Tooling gaps and conflicts

- **Verified:** Frontend has both `pnpm-lock.yaml` and `bun.lockb`; README mandates pnpm. Treat pnpm as canonical until ownership confirms otherwise.
- **Verified:** Frontend `CLAUDE.md` documents `lint:fix` and `type-check`, but those scripts do not exist.
- **Verified:** Backend has Prettier configuration but no formatting/lint script.
- **Verified:** Import worker has no `test` script.
