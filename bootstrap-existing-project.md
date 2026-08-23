# Bootstrap an Existing Repository for Claude Code and Codex

Analyze this existing repository and establish an accurate AI-native context system for future work with Claude Code and Codex.

## Goal

Create a persistent project knowledge base so future tasks do not require the team to repeatedly explain the stack, structure, architecture, commands, conventions, functions, APIs, tests, and current implementation status.

## Safety and scope

- This is a repository analysis and documentation task only.
- Do not change application behavior or refactor production code.
- Do not install, update, or remove dependencies.
- Do not configure CI/CD.
- Do not change environment values, credentials, or secrets.
- Never reproduce secret values in documentation or output.
- Preserve unrelated working-tree changes.
- Inspect existing `AGENTS.md`, `CLAUDE.md`, `.ai/`, README files, and other project documentation before writing.
- Merge useful existing instructions; do not blindly overwrite them.
- Exclude generated dependencies, build output, caches, coverage output, and large binary assets from indexing.
- Source code and executable configuration are authoritative when documentation conflicts with implementation.
- Label uncertain findings as `Inferred`, `Unknown`, or `Planned`. Do not present them as implemented facts.

## Required structure

Create and populate:

```text
AGENTS.md
CLAUDE.md
.ai/
├── README.md
├── steering/
│   ├── product.md
│   ├── tech.md
│   ├── architecture.md
│   ├── structure.md
│   ├── conventions.md
│   └── testing.md
├── context/
│   ├── project-state.md
│   ├── domain-glossary.md
│   └── known-issues.md
├── index/
│   ├── codebase-map.md
│   ├── file-index.md
│   ├── function-index.md
│   ├── api-index.md
│   └── test-index.md
├── specs/
│   ├── active/
│   ├── completed/
│   └── _template/
│       ├── requirements.md
│       ├── design.md
│       ├── tasks.md
│       └── test-plan.md
├── decisions/
│   ├── README.md
│   └── ADR-template.md
├── workflows/
│   ├── feature-development.md
│   ├── bug-fix.md
│   └── completion-checklist.md
└── prompts/
    ├── feature-task.md
    ├── bug-fix.md
    ├── refresh-context.md
    └── handoff.md
```

## Phase 1: Inspect before writing

Inspect the repository for:

- languages, versions, frameworks, and package managers;
- application entry points and runtime processes;
- important modules and domain boundaries;
- routes, APIs, GraphQL operations, events, jobs, queues, commands, and webhooks;
- databases, schemas, migrations, repositories, and external integrations;
- authentication, authorization, validation, logging, and error handling;
- environment variable names without reading or recording secret values;
- development, formatting, linting, type-checking, build, and test commands;
- test frameworks, test placement, fixtures, and coverage gaps;
- existing documentation and AI instruction files;
- TODOs, FIXME comments, incomplete work, and obvious technical risks;
- the current git status so existing user changes are preserved.

Use fast repository search and language-aware inspection where available. Focus the index on important first-party files and symbols, not every trivial helper.

## Phase 2: Create evidence-backed steering

Populate each file with project-specific information:

- `product.md`: purpose, users, capabilities, journeys, business rules, scope, and unknowns.
- `tech.md`: actual stack, versions, dependencies, infrastructure, environment requirements, and verified commands.
- `architecture.md`: components, module boundaries, entry points, data flow, persistence, integrations, and constraints.
- `structure.md`: directory map, placement rules, naming, and test locations.
- `conventions.md`: conventions demonstrated by the repository, including errors, validation, state, database access, and logging.
- `testing.md`: current test strategy, tools, commands, levels, gaps, and the required test update policy.

Add file-path evidence for material conclusions. Do not fill files with generic advice that is not specific to this project.

## Phase 3: Record current state

Populate:

- `project-state.md`: implemented capabilities, partially implemented work, deprecated areas, current risks, and unknowns.
- `domain-glossary.md`: project terminology, acronyms, entities, and status meanings.
- `known-issues.md`: verified defects, TODOs, technical debt, blockers, and their evidence.

Use the labels `Verified`, `Inferred`, `Unknown`, and `Planned` consistently.

## Phase 4: Build navigation indexes

Populate:

### codebase-map.md

Map major modules, responsibilities, entry points, dependencies, and important data flows.

### file-index.md

```text
| File | Purpose | Module | Important Dependencies |
```

### function-index.md

Index important exported functions, services, classes, handlers, repositories, hooks, commands, and domain operations:

```text
| Symbol | Type | File | Responsibility | Used By | Tests |
```

### api-index.md

Index REST/GraphQL interfaces, events, queues, jobs, commands, and webhooks:

```text
| Interface | Method/Type | Handler | Auth | Input | Output | Tests |
```

### test-index.md

```text
| Module/Feature | Test File | Level | Covered Behavior | Known Gaps |
```

Indexes must reference real paths and symbols. If usage or coverage cannot be confirmed, mark it `Unknown`.

## Phase 5: Configure shared agent operation

Create or update `AGENTS.md` as the canonical engineering workflow. It must require future agents to:

1. Read the relevant `.ai/` context before editing.
2. Inspect actual source code instead of relying only on indexes.
3. Identify affected modules, APIs, data, and tests.
4. Create or update an active feature specification for behavioral changes.
5. Plan before implementation.
6. Implement the smallest complete change.
7. Add or update relevant tests.
8. Run every available local verification command relevant to the change.
9. Update affected indexes and project state.
10. Review the final diff and report anything unverified.

Include the repository's real commands. If a command cannot be verified, label it as unknown rather than inventing one.

Create `CLAUDE.md` as a thin Claude Code adapter. It must direct Claude to read and follow `AGENTS.md` and the applicable `.ai/` files. Do not duplicate the entire knowledge base inside `CLAUDE.md`.

## Phase 6: Create reusable templates and workflows

Create feature templates covering:

- background and problem;
- goal, scope, and non-scope;
- actors and functional requirements;
- business rules and acceptance criteria;
- current and proposed design;
- affected components, APIs, data, and UI;
- security, migration, risks, and rollback;
- checkable implementation tasks;
- acceptance-criteria-to-test mapping.

Create workflows for feature implementation, bug fixes, completion checks, context refresh, and handoff. They must work without CI/CD and require explicit reporting of commands executed, results, blockers, and unverified behavior.

## Verification

After creating the structure:

1. Re-read all generated files.
2. Verify referenced paths and symbols exist.
3. Verify documented commands against package scripts, task runners, or build configuration.
4. Verify `AGENTS.md` and `CLAUDE.md` point to existing files.
5. Confirm production source code and application behavior were not changed.
6. Review the final diff for accidental changes and secrets.

## Final response

Return:

1. Repository summary.
2. Files created and existing files updated.
3. Important architecture findings.
4. Current testing condition and gaps.
5. Missing or uncertain business context.
6. Technical risks and documentation conflicts.
7. Commands verified.
8. Recommended first feature or bug to document.
9. Confirmation that production behavior was not changed.
