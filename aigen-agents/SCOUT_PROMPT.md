# Scout Repository Prompt

Paste this into Claude Code or Codex from the repository root.

```text
Use the Scout agent to perform a read-only investigation of this repository.

Do not modify, create, delete, rename, format, commit, push, deploy, or migrate anything.

Objective:
Understand the repository structure, architecture, important workflows, data layer, integrations, development setup, validation commands, and likely ownership boundaries so another agent can safely plan changes.

Investigate:
- repository purpose and type;
- languages, frameworks, runtimes, and package manager;
- entry points, routes, modules, services, jobs, and major boundaries;
- database configuration, migrations, models, schemas, and important tables;
- authentication, authorisation, external APIs, queues, storage, email, and environment variables;
- test, lint, type-check, build, Docker, and deployment configuration;
- important end-to-end execution and data flows;
- missing tests, stale documentation, unclear ownership, and meaningful risks.

Rules:
- Read AGENTS.md, CLAUDE.md, README files, manifests, and only relevant documentation.
- Search before reading full files.
- Ignore dependencies, generated files, caches, coverage, and build output unless directly relevant.
- Base findings on repository evidence.
- Include file paths and symbols.
- Separate confirmed facts from assumptions.
- Mark unconfirmed behaviour as Unknown.
- Do not invent commands, business rules, APIs, or data structures.
- Do not propose broad refactors.

Return:
1. Repository summary.
2. Active instruction sources.
3. Concise directory map.
4. Application entry points.
5. Architecture and module ownership.
6. Main end-to-end flows.
7. Data layer.
8. External integrations.
9. Authentication and authorisation.
10. Confirmed development and validation commands.
11. Test coverage map.
12. Risks and unknowns.
13. Recommended next step.
```

For a specific task, append:

```text
Focus task:
[paste task]

Prioritise files, symbols, flows, tests, and repositories directly related to this task.
```
