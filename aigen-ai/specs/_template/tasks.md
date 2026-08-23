# Tasks — [feature or fix]

Use checkboxes and keep repository boundaries explicit.

## Discovery

- [ ] Verify current behavior and reproduction/evidence.
- [ ] Confirm requirements, actors, rules, and unknowns.
- [ ] Check Git status in each affected repository.
- [ ] Identify interfaces, data, security, jobs, and integrations.

## Implementation

- [ ] Backend: [small complete task].
- [ ] Frontend: [small complete task].
- [ ] Import worker: [small complete task].
- [ ] API/OpenAPI/event contract: [task].
- [ ] Data migration/backfill/rollback: [task or N/A].
- [ ] Observability/security: [task].

Delete or mark N/A only with a short reason.

## Tests

- [ ] Add/update tests for success paths.
- [ ] Add/update tests for failures, authorization, and edge cases.
- [ ] Add transaction/idempotency/concurrency coverage where relevant.
- [ ] Complete the acceptance-criteria mapping in `test-plan.md`.

## Verification and handoff

- [ ] Run relevant backend commands and record results.
- [ ] Run relevant frontend commands and record results.
- [ ] Run relevant import-worker commands and record results.
- [ ] Update `aigen-ai/index/` and project state.
- [ ] Review final diffs for unrelated changes and secrets.
- [ ] Record unverified behavior, rollout order, and rollback.
- [ ] Move this specification to `completed/` only after acceptance criteria are met.

