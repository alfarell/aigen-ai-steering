# Workflow Prompts

## Full feature or cross-module fix

```text
Use the orchestrated agent workflow for this task.

Task:
[paste task]

Normalise requirements when needed, Scout the actual repository, create a minimal file-level plan, use one implementation agent, run focused verification, and review the actual final diff.

Do not modify unrelated files. Do not commit, push, deploy, modify external systems, or run destructive operations. Report exact validation commands, results, risks, and scope deviations.
```

Claude Code can use `/orchestrate-change`. Codex can use `$orchestrate-change` or be asked to use the skill directly.

## Small bug

```text
Use Scout to confirm the root cause and smallest change surface. Then use Implementer for the minimal fix, Test Verifier for focused checks, and Code Reviewer for the actual final diff.

Do not refactor unrelated code or change public contracts.
```

## Investigation only

```text
Use Scout in read-only mode.

Investigate:
[paste question]

Return repository ownership, relevant files and symbols, current execution/data flow, evidence, likely causes, existing tests, and risks. Do not modify files or propose broad refactors.
```

## Requirements only

```text
Use Requirements Analyst.

Convert the following input into objective, scope, actors, current condition, expected behaviour, numbered business rules, data requirements, Given/When/Then acceptance criteria, repository ownership hypothesis, assumptions, and blocking decisions.

Input:
[paste notes]
```

## Plan only

```text
Use Scout first when code locations are not confirmed, then use Implementation Planner. Do not edit files.

Return an ordered plan with repository, file, symbol, behavioural change, dependencies, acceptance criteria, tests, migration/deployment order, rollback, risks, and assumptions.
```

## Verification and review

```text
Use Test Verifier against the actual current diff. Then use Code Reviewer against the requirements, diff, and verification output.

Do not modify files. Lead with failures or actionable findings. A clean review is acceptable; do not invent issues.
```
