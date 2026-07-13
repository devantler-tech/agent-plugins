# `automated-ai-engineer`

A plugin for running an **autonomous AI engineer over a whole portfolio of repositories** — the
role/actor itself, not tools for building agents (design:
[ADR 0002](../../docs/adr/0002-automated-ai-engineer-plugin-boundary.md)). The engineer both
**operates** the portfolio (hotfixes breakage, drives trusted-author PRs to merge, triages, keeps
CI and dependencies healthy) and **advances** it (strategy and roadmaps, oldest-actionable-first
issue resolution, coverage, performance, refactoring, docs), shipping everything as human-gated
draft PRs.

It bundles two agents — **`automated-ai-engineer`** (the actor: the survey → select → act → report
run loop) and **`portfolio-surveyor`** (a read-only subagent that returns one compact survey
digest) — and three skills with their canonical home in
[devantler-tech/agent-skills](https://github.com/devantler-tech/agent-skills):
`portfolio-maintenance` (the run loop), `product-engineering` (the advance playbook), and
`self-improvement` (the guard-railed definition-improvement procedure).

## Consumer setup: the contract sections

The plugin carries the generic **role**; every deployment-specific fact is **consumer-owned
configuration**. The consuming repository's canonical instructions file (`AGENTS.md`) must define
five named contract sections (ADR 0002 D2) — the agents and skills fail closed on any missing one:

- **Portfolio map** — the repositories in scope, plus each product's `## Maintenance` card
  (validate commands, labels, protected/generated files, roadmap home).
- **Trust gate** — the exact logins that may be auto-driven, which bots are reviewer-only, and the
  per-repo merge mechanics (auto-merge, merge queues, direct merge).
- **Cadence** — run frequency, per-run budget, and the per-product rotation numbers for strategy
  reviews, docs passes, and heavy tasks.
- **Memory** — where the durable cross-run store lives and what cursors it holds, including the
  private out-of-repository store for sensitive notes.
- **Maintainer channels** — how a human decision is actively reached (e.g. an ask-tool prompt or
  draft-PR steering) and any last-resort blocked-only channel.

## VS Code delivery step

Claude Code and Copilot CLI load the bundled `agents/` directory automatically when the plugin is
installed. **VS Code does not** — copy the agents into your workspace as
`.github/agents/automated-ai-engineer.agent.md` and `.github/agents/portfolio-surveyor.agent.md`
to use them there.
