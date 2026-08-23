# Completion checklist

## Scope and correctness

- [ ] Acceptance criteria are current and satisfied.
- [ ] Actual source was inspected; no conclusion relies only on an index.
- [ ] All affected repositories, callers, routes/events/commands, data, jobs, and integrations were considered.
- [ ] Backend authorization and validation match frontend visibility.
- [ ] Transactions, idempotency, retries, and partial failure are addressed where relevant.

## Tests and verification

- [ ] Relevant automated tests were added/updated.
- [ ] Acceptance criteria map to tests or explicit manual checks.
- [ ] Exact commands and results are recorded.
- [ ] Failures and pre-existing failures are distinguished.
- [ ] Unverified behavior and environment blockers are listed.

## Documentation

- [ ] OpenAPI/event/command documentation matches behavior.
- [ ] Affected `aigen-ai/index/` files are updated.
- [ ] Project state/known issues are updated.
- [ ] Active spec reflects final design; ADR exists for durable decisions.

## Diff and safety

- [ ] Git status/diff reviewed independently in each repository.
- [ ] Pre-existing user changes are preserved.
- [ ] No secrets, `.env` values, production records, generated dependencies, build output, or unrelated formatting are included.
- [ ] Migration/deploy order, monitoring, and rollback are documented.
- [ ] Production behavior was not changed outside approved scope.

