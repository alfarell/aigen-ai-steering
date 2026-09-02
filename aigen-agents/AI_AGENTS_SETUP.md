# Claude Code + Codex Agent Pack

This is a drop-in, repository-scoped configuration. No installer is required.

## Install

1. Back up or merge any existing `AGENTS.md`, `CLAUDE.md`, `.claude/`, `.codex/`, or `.agents/` configuration.
2. Extract or copy **all contents of this pack**, including hidden directories, into the repository root.
3. Start a new Claude Code or Codex session from that repository root.

Expected structure:

```text
repo/
├── AGENTS.md
├── CLAUDE.md
├── .claude/
│   ├── agents/
│   └── skills/orchestrate-change/
├── .codex/
│   ├── config.toml
│   └── agents/
├── .agents/
│   └── skills/orchestrate-change/
├── SCOUT_PROMPT.md
└── WORKFLOW_PROMPTS.md
```

## Verify Claude Code

Run Claude Code from the repository root, then use:

```text
List the project subagents available for this repository and summarise AGENTS.md.
```

You may also run `/agents` to inspect loaded agents. Files added manually are loaded on a new session.

Example:

```text
Use the scout subagent to map this repository. Do not modify files. Follow SCOUT_PROMPT.md.
```

## Verify Codex

Run Codex from the repository root, then use:

```text
List the custom agents and instruction files active in this repository.
```

Example:

```text
Use the scout agent to map this repository. Do not modify files. Follow SCOUT_PROMPT.md.
```

For a full change:

```text
Use the orchestrate-change skill for this task:
[paste task]
```

## Included agents

| Purpose | Claude Code | Codex | Access |
|---|---|---|---|
| Requirement specification | `requirements-analyst` | `requirements_analyst` | Read-only |
| Repository exploration | `scout` | `scout` | Read-only |
| Implementation planning | `implementation-planner` | `implementation_planner` | Read-only |
| Code implementation | `implementer` | `implementer` | Workspace write |
| Test and build verification | `test-verifier` | `test_verifier` | Commands; no intentional source edits |
| Final diff review | `code-reviewer` | `code_reviewer` | Read-only |

## Recommended usage

Use all agents only for non-trivial changes. For a small, well-understood fix, use Scout → Implementer → Test Verifier → Code Reviewer.

Use no more than one writing agent at a time. The Codex concurrency cap is four so independent exploration and verification can run in parallel without encouraging overlapping edits.

## Existing instruction files

Do not blindly overwrite mature project instructions. Merge the durable project-specific facts and commands from an existing `AGENTS.md` or `CLAUDE.md` into the supplied files, while preserving the agent workflow and safety boundaries.
