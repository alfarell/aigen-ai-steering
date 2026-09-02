# Claude Code adapter

Read and follow `AGENTS.md` as the canonical engineering workflow.

Before changing code, read the relevant project knowledge in `aigen-ai/`, verify it against the affected source in `aigen-backend/`, `aigen-frontend/`, and/or `aigen-import-pr/`, and check the Git status of each affected repository.

Use the applicable workflow and prompt under `aigen-ai/workflows/` and `aigen-ai/prompts/`. For behavioral changes, maintain a specification under `aigen-ai/specs/active/`. Source code and executable configuration override stale documentation; report conflicts and unverified claims.

## Project subagents

Project subagents are available in `.claude/agents/`:

- `requirements-analyst`
- `scout`
- `implementation-planner`
- `implementer`
- `test-verifier`
- `code-reviewer`

For non-trivial changes, use the applicable sequence:

```text
requirements-analyst → scout → implementation-planner
→ implementer → test-verifier → code-reviewer
```

Use one implementation agent at a time. Parallelise only independent read-heavy work. Ask subagents to return distilled evidence rather than raw search or command output.

The reusable orchestration skill is available at `.claude/skills/orchestrate-change/SKILL.md`.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
