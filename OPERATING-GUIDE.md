# Operating Guide: Claude Code + Codex

## 1. Choose the installation method

### Existing project

Use this for a repository that already has application code but weak or outdated AI context.

1. Open the repository root in Claude Code or Codex.
2. Copy the entire contents of `bootstrap-existing-project.md` into the agent.
3. Let the agent inspect the repository and create the AI-native structure.
4. Review the generated documents before allowing feature implementation.
5. Commit the context setup separately from application changes.

If the repository already has `AGENTS.md`, `CLAUDE.md`, or an `.ai/` directory, instruct the agent to merge useful content. Do not overwrite existing rules without reviewing them.

### New project

1. Copy everything inside `template/` into the repository root.
2. Replace every `[PLACEHOLDER]` in `.ai/steering/` and `.ai/context/`.
3. Add the real install, development, formatting, linting, type-checking, build, and test commands to `AGENTS.md`.
4. Create the first feature specification under `.ai/specs/active/`.

## 2. Validate the initial analysis

Before trusting the generated context, confirm these files:

| File | What to validate |
|---|---|
| `.ai/steering/product.md` | Users, purpose, main flows, business rules |
| `.ai/steering/tech.md` | Actual stack, versions, dependencies, commands |
| `.ai/steering/architecture.md` | Entry points, modules, data flow, integrations |
| `.ai/context/project-state.md` | What is implemented, incomplete, risky, or unknown |
| `.ai/index/codebase-map.md` | Important modules and where changes belong |
| `.ai/index/function-index.md` | Important symbols and related tests |
| `.ai/index/api-index.md` | APIs, events, jobs, webhooks, or other interfaces |
| `.ai/steering/testing.md` | Real test tools and commands; no invented commands |

Ask the responsible developer or analyst to correct business terminology and hidden operational rules that cannot be discovered from source code.

## 3. Daily feature workflow

Start a feature with:

```text
Follow .ai/prompts/feature-task.md.

Feature:
[DESCRIBE THE REQUEST]

Business context:
[ADD ONLY CONTEXT THAT IS NOT ALREADY IN THE REPOSITORY]

Done when:
[LIST OBSERVABLE ACCEPTANCE CONDITIONS]
```

The agent should:

1. Read `AGENTS.md` and the relevant `.ai/` context.
2. Verify indexes against the source.
3. Create or update a feature specification.
4. Plan the change.
5. Implement code and tests.
6. Run local verification.
7. Update indexes and project state.
8. Report what was and was not verified.

## 4. Daily bug-fix workflow

Start a bug fix with:

```text
Follow .ai/prompts/bug-fix.md.

Bug:
[DESCRIBE ACTUAL BEHAVIOR]

Expected:
[DESCRIBE EXPECTED BEHAVIOR]

Evidence:
[ERROR, LOG, RECORD ID, SCREENSHOT, OR REPRODUCTION STEPS]
```

Do not ask the agent to edit code immediately. The workflow requires it to reproduce or trace the issue, state the likely cause with evidence, and then implement the smallest verified fix.

## 5. Working without CI/CD

The repository cannot mechanically guarantee compliance without CI. Use this manual gate before accepting work:

- relevant tests were added or updated;
- the agent showed the exact verification commands and results;
- failures and unverified behavior were disclosed;
- `.ai/index/` matches the changed code;
- the active specification matches the final behavior;
- `project-state.md` was updated when status changed;
- the final diff contains no unrelated changes;
- another human or AI review pass was completed for risky changes.

For significant work, use a second session or the other tool for review. Example:

```text
Review the current uncommitted changes against AGENTS.md and the applicable
.ai/specs/active specification. Focus on correctness, regression risks,
missing tests, documentation drift, and unsupported claims. Do not modify
files. Return findings ordered by severity with file references.
```

## 6. Keep context healthy

Run `.ai/prompts/refresh-context.md` when:

- several features were added without updating documentation;
- the stack or architecture changed;
- indexes point to missing or renamed files;
- the agent repeatedly misunderstands the project;
- a new team takes ownership;
- before a major release or handover.

Do not rewrite all documentation after every small task. Update only affected files.

## 7. Context priority

When information conflicts, use this order:

1. Current source code and executable configuration.
2. Database migrations, schemas, and API contracts.
3. Active feature specification.
4. `.ai/context/project-state.md`.
5. `.ai/steering/`.
6. `.ai/index/`.
7. Old tickets, notes, or historical documentation.

The agent must report conflicts instead of silently choosing convenient information.

## 8. Claude Code usage

Claude Code receives its entry instructions from `CLAUDE.md`. This package keeps that file short and directs Claude to `AGENTS.md` and `.ai/`.

Recommended task request:

```text
Read CLAUDE.md and follow the applicable workflow in .ai/prompts/.
Do not start editing until you have inspected the affected implementation and
shown a concise plan.

Task: [TASK]
```

## 9. Codex usage

Codex uses `AGENTS.md` as the durable repository instruction file. Start tasks from the repository root so the correct project context is discovered.

Recommended task request:

```text
Follow AGENTS.md and .ai/prompts/feature-task.md.

Task: [TASK]
Done when: [ACCEPTANCE CONDITIONS]
```

Use Plan mode first when requirements, scope, or business behavior are unclear.

## 10. What still belongs in the prompt

You should only need to provide information that is new or task-specific:

- requested change;
- current versus expected behavior;
- new business decision;
- screenshots, logs, sample data, or reproduction steps;
- acceptance criteria;
- temporary constraints or deadlines.

Do not repeatedly paste the stack, architecture, commands, directory structure, or general conventions. Those belong in `.ai/` and `AGENTS.md`.
