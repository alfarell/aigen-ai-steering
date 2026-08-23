# Aigen AI context

This directory is the shared AI steering and project knowledge base for the three Aigen repositories in the parent workspace. It replaces the `.ai/` path used by the bootstrap template.

## Read order

1. `../AGENTS.md`
2. Relevant files in `steering/`
3. `context/project-state.md` and `context/known-issues.md`
4. Relevant navigation in `index/`
5. The applicable specification and workflow
6. The actual source code

## Status labels

- **Verified**: directly supported by current source, executable configuration, or a command result.
- **Inferred**: strongly suggested by implementation but not confirmed by product ownership.
- **Unknown**: cannot be established from the workspace.
- **Planned**: described as future work and not represented as implemented.

## Directory purpose

- `steering/`: stable product, stack, architecture, structure, conventions, and testing guidance.
- `context/`: current implementation state, terminology, and known risks.
- `index/`: navigation to important files, symbols, interfaces, and tests.
- `specs/`: active/completed behavioral change records and reusable templates.
- `decisions/`: architecture decision records.
- `workflows/`: repeatable engineering procedures.
- `prompts/`: task starters for AI-assisted work.

Refresh only the affected documents after a change. Do not reproduce secrets or environment values.

