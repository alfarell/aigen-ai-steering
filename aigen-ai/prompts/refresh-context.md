# Refresh-context prompt

Refresh only stale Aigen AI context.

1. Read `AGENTS.md` and `aigen-ai/README.md`.
2. Check Git status and recent relevant history in each repository.
3. Compare affected steering, state, and indexes to current source/config/OpenAPI/tests.
4. Mark claims Verified, Inferred, Unknown, or Planned.
5. Update only documents affected by real drift.
6. Verify every changed path, symbol, interface, command, and test reference.
7. Review the documentation diff for secrets and accidental application changes.

Return changed files, conflicts found, command results, and remaining unknowns. Do not modify production code or dependencies.

