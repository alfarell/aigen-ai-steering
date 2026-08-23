# Feature development workflow

1. Read `AGENTS.md`, relevant steering/state/index files, and actual source.
2. Check Git status in every affected repository.
3. Create `aigen-ai/specs/active/<feature>/` from `_template/`.
4. Confirm problem, actors, scope/non-scope, business rules, security, and acceptance criteria.
5. Trace all affected HTTP/event/command contracts, schemas/tables, jobs, integrations, UI routes, and tests.
6. Design the smallest complete cross-repository change. Define deploy order and backward compatibility.
7. Plan implementation in checkable repository-specific tasks.
8. Implement while preserving local conventions and unrelated changes.
9. Add tests and map every acceptance criterion in `test-plan.md`.
10. Run relevant non-mutating checks first; run builds/tests appropriate to risk.
11. Update OpenAPI and `aigen-ai/` indexes/state where affected.
12. Review each final diff for secrets, accidental formatting, generated output, and missing callers.
13. Report exact commands/results, failures, blockers, rollout/rollback, and unverified behavior.
14. Move the specification to `completed/` only when criteria are met and status is recorded.

Do not run migrations, workers, cron, sync, real email, or external-system mutations merely to “verify” a feature.

