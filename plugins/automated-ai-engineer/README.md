# `automated-ai-engineer`

A plugin for running an **autonomous AI engineer over a whole portfolio of repositories** — the
role/actor itself, not tools for building agents (design:
[ADR 0002](../../docs/adr/0002-automated-ai-engineer-plugin-boundary.md)). The engineer both
**operates** the portfolio (hotfixes breakage, drives trusted-author PRs to merge, triages, keeps
CI and dependencies healthy) and **advances** it (strategy and roadmaps, oldest-actionable-first
issue resolution, coverage, performance, refactoring, docs), shipping everything as human-gated
draft PRs.

It bundles three agents — **`automated-ai-engineer`** (the actor: the survey → select → act → report
run loop), **`portfolio-surveyor`** (a read-only subagent that returns one compact survey
digest), and **`agent-improver`** (a meta-engineer that improves the engineer itself from measured
evidence) — and skills with their canonical home in
[devantler-tech/agent-skills](https://github.com/devantler-tech/agent-skills):
`portfolio-maintenance` (the run loop), `product-engineering` (the advance playbook),
`self-improvement` (the guard-railed definition-improvement procedure), and `agent-improvement`
(the outside-in meta-improvement loop).

**Why both `self-improvement` and `agent-improvement`?** They work at different vantage points and are
complementary, not alternatives. `self-improvement` is one run reflecting on its own memory, banking a
learning per run and distilling on a slow cadence. `agent-improvement` is an **external observer** over
the whole session corpus and every deployed instance at once — which is where failures that no single
run can see actually live: errors recurring across hundreds of runs, waste that looks normal from inside
one run, divergence between sibling instances, and drift between a non-version-controlled bootstrap
entry and the contract it points at. Deployments running a single instance with no separate meta-run can
use `self-improvement` alone.

## Consumer setup: the contract sections

The plugin carries the generic **role**; every deployment-specific fact is **consumer-owned
configuration**. The consuming repository's canonical instructions file (`AGENTS.md`) must define
five named contract sections (ADR 0002 D2) — the agents and skills fail closed on any missing one:

- **Portfolio map** — the repositories in scope, plus each product's `## Maintenance` card
  (validate commands, labels, protected/generated files, roadmap home, and the product's standard
  **feature-flag mechanism** — `product-engineering` requires one for every non-trivial feature).
- **Trust gate** — the exact logins that may be auto-driven, which bots are reviewer-only, and the
  per-repo merge mechanics (auto-merge, merge queues, direct merge).
- **Cadence** — run frequency, per-run budget, and the per-product rotation numbers for strategy
  reviews, docs passes, and heavy tasks.
- **Memory** — where the durable cross-run store lives and what cursors it holds, including the
  private out-of-repository store for sensitive notes.
- **Maintainer channels** — how a human decision is actively reached (e.g. an ask-tool prompt or
  draft-PR steering), any last-resort blocked-only channel, and the deployment's canonical
  **AI-disclosure line** — the stable prefix the agents place on everything they author and use to
  tell their own prior output apart from human comments under the same login.

## Runtime guard note

The surveyor's read-only discipline is **prompt-level**; its tool set still includes the shell it
needs to run the source-forge CLI's read verbs. Deployments should **enforce** the non-mutation
boundary in their runtime's permission/guard layer (e.g. an allowlist of read-only commands for
subagents), so a prompt-injected survey cannot escalate to writes even in principle.

## Delivery

Installing the plugin makes both bundled agents available automatically — Claude Code, Copilot CLI,
and VS Code all discover the plugin's `agents/` directory on install (VS Code surfaces
plugin-provided agents in chat alongside your locally defined ones). No manual copy into
`.github/agents` is required.
