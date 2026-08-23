# AI-Native Engineering Starter Pack

Reusable repository context and operating prompts for teams using Claude Code and Codex.

## Package contents

- `OPERATING-GUIDE.md` — installation and daily operating notes.
- `TRIGGER.md` — one-line selector for initiating or working with an existing project.
- `bootstrap-existing-project.md` — one-time prompt for analyzing and documenting an existing repository.
- `template/` — fixed AI-native directory structure for a new repository.
- `template/.ai/prompts/` — reusable prompts for features, bugs, context refresh, and handoff.

## Canonical context model

- `.ai/` is the shared project knowledge base.
- `AGENTS.md` is the canonical engineering workflow and Codex entry point.
- `CLAUDE.md` is a thin Claude Code adapter that directs Claude to the same instructions.
- Source code remains authoritative when documentation is outdated.

Start with `OPERATING-GUIDE.md`.
