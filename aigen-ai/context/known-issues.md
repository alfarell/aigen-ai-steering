# Known issues and risks

## High priority

### KI-001 — Import transaction helper is bypassed

- **Verified:** `AigenSourcingService` constructs `this.db` with logical key `isearch`. `syncRFQData()` and `_getAigenNextRFQNumber()` call `this.db.transaction(...)`, so the transaction connection is opened for iSearch. Their callbacks ignore the provided connection, while nested Aigen operations call `this.db.connection('aigen').query(...)` through another pool.
- **Impact:** rollback/atomicity assumptions for RFQ inserts, counter updates, and staging cleanup are not guaranteed.
- **Evidence:** `aigen-import-pr/services/aigen.js`, `aigen-import-pr/lib/database.js`.
- **Recommended next step:** specify and test connection-bound transaction propagation before changing import behavior.

### KI-002 — Import concurrency/idempotency is unprotected

- **Verified:** `pr_library` is truncated after the sync path, RFQ counter work is performed in a helper with the same connection-bypass pattern, and no application/distributed lock is visible.
- **Inferred impact:** overlapping cron/Kafka/CLI runs can race, duplicate work, lose staging rows, or allocate counters unsafely.
- **Evidence:** `aigen-import-pr/services/aigen.js`.

### KI-003 — Import worker has no automated tests

- **Verified:** no test files/framework/script are present.
- **Impact:** the highest-risk cross-schema pipeline lacks regression protection for assignment, transaction, idempotency, and notification paths.

### KI-012 - Auto manual sourcing transfer needs rollout verification

- **Mitigated in code:** Delivery 2 now uses one `database_isourcing`
  transaction for all target writes, creates/reconciles the required active
  card before item insertion, treats consistent retries as success, retries
  deadlocks, and verifies a lifecycle postcondition before commit.
- **Verified by tests:** write-failure rollback, exact active-item orphan
  repair, terminal guard, idempotency, target connection usage, and structured
  errors pass focused unit/repository tests.
- **Mitigated in code:** Delivery 3 resolves every newly discovered item from
  its own material group, uses exact active category/CL card identities, and
  verifies item/export/history/PR-log assignment alignment before commit.
- **Residual risk:** no database uniqueness migration was added; concurrency
  safety depends on serializable PR-range locking and deadlock retry.
- **Residual risk:** transaction behavior has not been exercised against an
  isolated real MySQL test schema, and no production-like cron was run.
- **Residual risk:** Delivery 3 has not yet been exercised through a
  production-like cron window or a mutating real-schema integration test.
- **Mitigated in code:** Delivery 4 adds safe operation/stage result summaries,
  non-zero failure behavior, Sentry tags, read-only lifecycle health metrics,
  and a ten-class SELECT-only reconciliation CLI.
- **Mitigated in code:** Delivery 5 preparation adds a separate SELECT-only,
  fingerprinted repair-review report for seven lifecycle tables. It routes
  active unassigned rows to the established workflow, prohibits active repair
  for terminal-only PRs, and rejects mutation flags.
- **Verified locally:** the guarded local executor repaired only
  `B1200027667` item `66245`; postcondition classifies that item as
  `CONSISTENT`, while evidence hashes prove the other two supplied PRs were
  unchanged.
- **Residual risk:** broad local health metrics include historical/imported
  lifecycle states and must not be treated as an automatic repair queue.
- **Residual risk:** no production mutation is authorized or implemented;
  authoritative UI workflow execution, maintenance window, backup reference,
  and per-PR lifecycle decisions still require operational approval.
- **Evidence:** active spec
  `aigen-ai/specs/active/auto-manual-sourcing-header-integrity/spec.md` and the
  phased task plan.

### KI-013 - Legacy sparse header path remains concurrency-limited

- **Mitigated on branch `fix/qcf-controller-param-checking`:** the legacy
  controller transfer now rejects incomplete source header data and repairs or
  creates a valid active Admin header before initial or existing PR items are
  inserted. Source selection is deterministic and postconditions are re-read.
- **Mitigated on branch:** all scoped task-board reads and writes use one
  `database_isourcing` transaction. Target failure rolls back card, item,
  export, log, history, counter, and split work; primary status/token work only
  begins after target commit. HTTP input cannot spoof the cron trust marker.
- **Verified:** 20 synthetic controller/repository regressions pass, covering
  category-mapped first import, same/different-list multi-group routing,
  stateful retries, target transaction propagation, partial-write rollback,
  token/status suppression, route-scope spoof rejection, and valid retries.
- **Residual risk:** no schema constraint or concurrency lock was added.
- **Residual risk:** no production revision or real task-board workflow was
  exercised; deploying the patch does not repair historical sparse headers.

## Medium priority

### KI-004 — Frontend has no automated tests

- **Verified:** no test script, test dependency, or test files.
- **Impact:** role-based routing, token journeys, form mappings, and API contracts can regress undetected.

### KI-005 — Backend coverage is narrow

- **Verified:** focused coverage now includes auto-manual-sourcing invocation,
  atomic transfer, routing, cron observability, and reconciliation in addition
  to selected helpers/policies/reminders and material assignment.
- **Verified:** the 2026-07-31 full run passes 18/20 suites and 124/135 tests.
  The controller reminder suite fails because mocked Sequelize models do not
  provide an association method expected by `src/models/default/index.js`;
  reminder repository tests expect one configuration lookup while
  implementation now requires BCG and GEMS configurations.
- **Verified:** importing database configuration triggers asynchronous authentication during unit tests, causing timezone/connection and post-teardown logging noise.
- **Impact:** most HTTP interfaces, auth, workflow transitions, uploads, email, cron orchestration, and SAP sync are not covered.

### KI-006 — Authentication exposure requires review

- **Verified:** upload routes do not apply a router-wide authentication middleware; several email/system endpoints are also mounted without standard Bearer authentication. Some are intentionally token/system-driven.
- **Unknown:** whether compensating gateway/network controls exist.
- **Evidence:** `aigen-backend/src/routes/uploadRoutes.js`, `aigen-backend/src/routes/emailRoutes.js`.
- **Action:** document intended callers and add explicit authentication/purpose checks per route.

### KI-007 — CORS configuration may conflict with credentialed browser requests

- **Verified:** backend uses wildcard origin and `credentials: true`.
- **Impact:** browsers do not permit wildcard `Access-Control-Allow-Origin` for credentialed requests; exact impact depends on whether cookies/credentials are actually used.
- **Evidence:** `aigen-backend/app.js`.

### KI-008 — Insecure configuration fallbacks exist

- **Verified:** backend config includes permissive/example fallbacks for sensitive settings, including an administrator override value and integration endpoints.
- **Impact:** an incomplete environment can start with unsafe defaults in some modes.
- **Evidence:** `aigen-backend/config.js`.
- Secret values are intentionally not reproduced here.

## Documentation and maintenance

### KI-009 — Existing AI/readme instructions drift from code

- **Verified:** frontend `CLAUDE.md` names scripts and store paths that do not exist; frontend README TODOs overlap implemented modules; backend AI text says to avoid raw SQL although repositories and migrations use it; import documentation contains historical cross-repository references outside this workspace.
- **Action:** use `AGENTS.md` and `aigen-ai/` as the shared entry point and verify every claim against source.

### KI-010 — Frontend lockfile ambiguity

- **Verified:** both `pnpm-lock.yaml` and `bun.lockb` exist while README mandates pnpm.
- **Impact:** dependency resolution can drift if contributors use different managers.
- **Action:** product/team owner should select one canonical lockfile; do not remove either without explicit approval.

### KI-011 — OpenAPI/route parity is not mechanically enforced

- **Verified:** a large bundled OpenAPI file and live Express route modules coexist; no contract test was found.
- **Unknown:** current drift count.
- **Action:** add a read-only route/contract comparison or integration tests.

## Current workspace caution

- **Verified:** pre-existing uncommitted backend changes exist in `package-lock.json` and `src/controllers/qcfController.js`. Preserve them and distinguish them from future work.
