# Conventions

## Shared

- Treat source and executable configuration as authoritative; mark documentation-only claims as unverified.
- Preserve the Node/package-manager choice of each repository.
- Pass IDs, status values, and server-group values through existing constants rather than adding string variants.
- Never log or document credentials, full tokens, reset links, or environment values.
- Use existing Sentry integration for unexpected failures and avoid swallowing operational errors without an explicit retry/alert policy.

## Backend

- CommonJS (`require`, `module.exports`) is the dominant module format.
- Prettier configuration uses single quotes, trailing commas, and four-space indentation. Existing files are not fully uniform; keep diffs local.
- Route wiring typically uses `routeAsyncWrapper` for promise rejection and ends in `errorHandlerMiddleware`.
- New request validation belongs in `src/validations/` and is applied with `validatorMiddleware`; some older controllers retain local Joi validation.
- Use `HttpError` subclasses or `ValidationError` for expected failures and `sendResponse()` for established response shape.
- Authenticate with `authService.authenticateToken`; add `permissionValidator()` where a permission slug exists. Token-link routes must use the correct token purpose and persisted-token validation.
- Data access may use Sequelize models, Sequelize query primitives, or repository-owned raw SQL. The existing `CLAUDE.md` claim that all operations use Sequelize and raw SQL should be avoided is contradicted by current repositories.
- Multi-step writes must share the same Sequelize transaction object/connection all the way down. Do not assume a helper name alone guarantees atomicity.
- Use business-day helpers for workflow deadlines where existing policy does; do not silently replace them with calendar-day arithmetic.
- Use `console.logtime()`/existing logging helpers in backend code where the subsystem already initializes them.

Evidence: `aigen-backend/.prettierrc.json`, `src/helper/routeAsyncWrapper.js`, `src/middleware/errorHandler.js`, `src/helper/date.js`, `src/repository/`.

## Frontend

- Use Vue 3 Composition API and `<script setup>` in feature components.
- Keep server state in TanStack Query hooks and global/session state in Pinia; do not duplicate server caches in a store without a reason.
- Put HTTP calls in `src/services/` using the shared Axios clients, and keep page components focused on rendering/orchestration.
- Reuse feature provider/context/hook patterns for complex tables and forms.
- Route access uses `meta.roles` and `publicPages`; new routes must also be protected by the corresponding backend policy.
- API errors normally surface through `useNotification` and the central response interceptor. Preserve token-link redirects separately from expired authenticated sessions.
- Follow the existing ESLint/Prettier configuration. `pnpm run lint` is a fixer; use the non-mutating command during review.

## Import worker

- CommonJS and four-space formatting are enforced by ESLint/Prettier config.
- Keep event dispatch in `handlers/`, orchestration in `services/`, and SQL text in `queries/<logical-db>/`.
- Use mysql2 placeholders/binds; never interpolate untrusted values into SQL identifiers or predicates.
- Initialize Sentry before other application modules in entry points.
- Re-throw handler failures so Kafka failure semantics can apply; verify retry/offset behavior before changing the consumer.
- Treat `pr_library` as transient staging. Any new concurrency, retry, or cleanup behavior needs an explicit design and database-backed test plan.

## Documentation maintenance

For behavioral changes, update:

1. the active specification;
2. affected code/API/test indexes;
3. `project-state.md` or `known-issues.md` when status/risk changes;
4. an ADR if the change establishes a durable cross-repository or data-ownership decision.

