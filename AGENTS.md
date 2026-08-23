# Aigen Engineering Guide

This workspace contains three independently versioned repositories that together implement Aigen:

- `aigen-backend/`: Express API, scheduled workflow processing, persistence, email, and SAP integration.
- `aigen-frontend/`: Vue web application for internal roles and token-based vendor/DIC journeys.
- `aigen-import-pr/`: Kafka/CLI worker that imports released PR data and creates RFQ staging records.

The shared project knowledge base is `aigen-ai/` (intentionally not `.ai/`). Source code and executable configuration remain authoritative.

## Required workflow

Before editing:

1. Read this file and the relevant documents under `aigen-ai/`.
2. Inspect the actual affected source; never rely on an index alone.
3. Check `git status --short` inside every affected repository and preserve existing changes.
4. Identify affected repositories, modules, interfaces, data stores, jobs, security boundaries, and tests.
5. For any behavioral change, create or update a specification under `aigen-ai/specs/active/<feature>/`.
6. Write a concise implementation and verification plan before changing code.

During and after implementation:

7. Implement the smallest complete change consistent across affected repositories.
8. Add or update tests at the closest useful level. If no test harness exists, state the gap and add one only when it is in scope.
9. Run every relevant available local verification command. Never substitute an invented command.
10. Update affected files in `aigen-ai/index/`, `aigen-ai/context/project-state.md`, and the active specification.
11. Review each repository's final diff. Report commands, results, blockers, and unverified behavior.

Do not change dependencies, environments, migrations, CI/CD, or production behavior unless the task explicitly requires it. Do not expose values from `.env`, `.env.*`, credentials, tokens, or private API documentation.

## Repository commands

Run commands from the named repository directory.

### Backend (`aigen-backend/`)

Node is pinned to `v22.14.0` in `.nvmrc`.

```text
npm install
npm run dev
npm start
npm test
npm run migrate -- up --db=aigen
npm run migrate -- up --db=task_board
npm run migrate -- up --db=prpo
npm run migrate:create -- --db=aigen --name=<name>
npm run seed -- --db=aigen
npm run run:cron
npm run run:sync
npm run reconcile:isourcing -- --pr=<prefixed-pr>[,<prefixed-pr>]
npm run review:isourcing-repair -- --pr=<prefixed-pr>[,<prefixed-pr>] --environment=<environment> --operator=<operator-ref> --backup-ref=<backup-ref>
npm run apply:isourcing-repair-local -- --pr=<prefixed-pr> --item-card-ids=<id>[,<id>] --environment=local --operator=<operator-ref> --backup-ref=<backup-ref> --before-report=<before.json> --backup-output=<private-backup.json> --after-output=<after.json> --confirm=APPLY_LOCAL_ISOURCING_REPAIR
```

The migration, seeding, cron, sync, and `apply:isourcing-repair-local` commands mutate external state; use them only when the task explicitly calls for that action and the target environment is confirmed. `apply:isourcing-repair-local` rejects every runtime except `NODE_ENV=local` and requires reviewed evidence, a private backup path, and the exact confirmation phrase. `reconcile:isourcing` and `review:isourcing-repair` are read-only and reject repair/apply flags. There is no lint or build script in `package.json`.

### Frontend (`aigen-frontend/`)

The README requires Node `v20.19.6` and pnpm `10.22.0`.

```text
pnpm install
pnpm run dev
pnpm run build
pnpm run preview
pnpm run lint
```

`pnpm run lint` invokes ESLint with `--fix` and therefore modifies files. For read-only verification use `pnpm exec eslint . --max-warnings=0`. There is no test or type-check script.

### Import worker (`aigen-import-pr/`)

Node is pinned to `v24.9.0` in `.nvmrc`.

```text
npm install
npm run start:worker
npm run dev:worker
npm run aigen:import-pr -- --last-period-days=<days>
npm run lint
npm run lint:fix
npm run format
```

The worker and one-shot import mutate databases and may send emails. Do not run them as verification. There is no automated test script.

## Project-specific rules

- Treat `aigen-backend/docs/openapi/openapi.bundle.yaml` and active route files as the HTTP contract; report disagreements between them.
- Backend code is CommonJS and generally follows route → controller → service → repository/model. Preserve transaction boundaries and pass a transaction explicitly through all queries that must be atomic.
- The backend uses three MySQL schemas: primary Aigen, iSourcing/task board, and iSearch/PR-PO search. Confirm the intended connection before any data change.
- Frontend code is feature-oriented. Put screen-specific components, hooks, context, and providers under the owning `src/features/` module; put HTTP calls under `src/services/`.
- Frontend routing uses hash history, route metadata, Pinia authentication state, and an Axios interceptor. Keep frontend role checks aligned with backend authentication/authorization.
- The import worker uses parameterized raw SQL organized by logical database under `queries/`. `pr_library` is staging data and is truncated after a successful sync path.
- Do not assume the import worker's `Database.transaction()` covers calls made through `this.db.connection(...).query(...)`; inspect and test the actual connection used.
- Use existing response/error helpers, validation schemas, Sentry reporting, and timestamped logging patterns where present.
- Never edit generated dependencies, build output, coverage output, caches, or large assets as part of normal feature work.

## Context entry points

- Product and domain: `aigen-ai/steering/product.md`, `aigen-ai/context/domain-glossary.md`
- Stack and commands: `aigen-ai/steering/tech.md`
- Architecture and data flow: `aigen-ai/steering/architecture.md`, `aigen-ai/index/codebase-map.md`
- Placement and conventions: `aigen-ai/steering/structure.md`, `aigen-ai/steering/conventions.md`
- Tests and current risks: `aigen-ai/steering/testing.md`, `aigen-ai/context/known-issues.md`
- Feature/bug workflow: `aigen-ai/workflows/` and `aigen-ai/prompts/`
