---
name: orchestrate-change
description: Use for non-trivial repository changes that benefit from structured requirements analysis, read-only exploration, planning, implementation, verification, and final review. Do not use for a tiny, fully understood edit.
---

# Orchestrate Change

Read `AGENTS.md` first.

For the requested change, use the smallest applicable workflow:

1. Spawn `requirements_analyst` when business behaviour or acceptance criteria are incomplete.
2. Spawn `scout` when relevant files, symbols, execution paths, schemas, integrations, or tests are not confirmed.
3. Spawn `implementation_planner` for cross-module, migration, integration, or multi-file work.
4. Spawn one `implementer` after behaviour and the change surface are grounded.
5. Spawn `test_verifier` after implementation.
6. Spawn `code_reviewer` against the actual final diff and test evidence.

Rules:

- Parallelise only independent read-heavy tasks.
- Use one writer at a time.
- Do not allow overlapping concurrent edits.
- Give each subagent a bounded task and relevant prior findings.
- Ask every subagent for concise evidence, not raw logs.
- Skip unnecessary phases for small, well-understood tasks.
- Do not commit, push, deploy, modify external systems, or run destructive operations.

The main agent must consolidate the final response with changes, files, validation, acceptance-criteria coverage, risks, and scope deviations.
