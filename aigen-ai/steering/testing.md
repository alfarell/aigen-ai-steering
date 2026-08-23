# Testing

## Current condition

### Backend

- **Verified:** Jest 29 is configured through the `npm test` script.
- **Verified:** Seven test files exist under `tests/`.
- **Verified coverage areas:** business-day utilities, calendar-day log helper, GEMS QCF workflow policy, CS QCF token middleware, DIC reminder controller/repository behavior, and material-assignment update behavior.
- **Verified on 2026-07-29:** a full in-band Jest run completed with 5 of 7 suites passing and 45 of 56 tests passing. The DIC reminder controller suite failed during model association setup, and the DIC reminder repository tests no longer match the two-server-group configuration lookup. Some passing suites also initiated Sequelize authentication at module import and logged after Jest teardown.
- **Known gaps:** broad route/API integration, auth/OAuth, most PR/RFQ/QCF transitions, email/upload behavior, migrations, SAP sync, cron stage orchestration, and database integration.

Command:

```text
cd aigen-backend
npm test
```

Use `npm test -- --runInBand` when isolating shared mocks or diagnosing order-sensitive tests.

### Frontend

- **Verified:** No test dependency, test script, or test files were found.
- **Verified:** `pnpm run build` first runs non-fixing ESLint and then Vite.
- **Gap:** route guards, stores, services, composables, tables, forms, role-specific redirects, and token error flows have no automated regression suite in this repository.

Non-mutating static check:

```text
cd aigen-frontend
pnpm exec eslint . --max-warnings=0
```

Build check:

```text
pnpm run build
```

Build may require valid non-secret environment configuration. Sentry upload behavior must be reviewed before running with production credentials.

### Import worker

- **Verified:** No automated tests or `test` script exist.
- **Verified:** ESLint is available through `npm run lint`.
- **Critical gaps:** assignment cascade, eligibility filtering, RFQ counter concurrency, transaction boundaries, idempotency, staging cleanup, Kafka retry/offset behavior, and backend notification failures.

Command:

```text
cd aigen-import-pr
npm run lint
```

Do not use the worker/CLI as a test: both write databases and can send notifications.

## Required test update policy

Every behavioral change must:

1. map each acceptance criterion to at least one automated or explicitly manual verification;
2. update existing tests in affected repositories;
3. add regression coverage for the failure path being fixed;
4. test authorization at the backend boundary, not only frontend visibility;
5. cover transaction rollback/idempotency for multi-row or cross-system changes;
6. state why an automated test was not added when a repository lacks a harness;
7. report exact commands and results, including pre-existing failures;
8. avoid real email, SAP, Kafka, and production-like database side effects.

For cross-repository features, test the contract at both ends: backend route/input/output plus frontend or worker caller mapping.
