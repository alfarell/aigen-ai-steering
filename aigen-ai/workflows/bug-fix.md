# Bug-fix workflow

1. Record actual behavior, expected behavior, evidence, environment, frequency, and impact.
2. Check Git status and preserve pre-existing work.
3. Reproduce safely or trace the failing path from entry point to data/integration boundary.
4. State the likely root cause with file/symbol/data evidence. Separate confirmed cause from hypotheses.
5. Create/update `aigen-ai/specs/active/<bug>/` with regression acceptance criteria.
6. Assess whether the symptom spans frontend/backend/importer contracts or runtime configuration.
7. Add a failing regression test when a harness exists. When it does not, design the smallest safe test seam or document manual verification.
8. Implement the smallest complete root-cause fix; avoid unrelated refactors.
9. Verify success, failure, authorization, retry/duplicate, and rollback paths relevant to the bug.
10. Run exact repository checks and review final diffs.
11. Update indexes/state/known issues and report everything not verified.

For production-data symptoms, never copy secrets or personal data into the spec. Use redacted identifiers and synthetic fixtures.

