# 0018. The agentic-engineering plugin covers the agents' whole workspace

## Context

[ADR 0017](0017-agentic-engineering-bundles-the-agents-toolbox.md) made `agentic-engineering` the one
plugin carrying the agents' engineering toolbox. On 2026-11-04 the maintainer asked for Anthropic's
Engineering, Design, Product Management, Marketing, Finance and Productivity skills, iCloud Mail and
Calendar, LinkedIn and Codex Security as well. They considered a separate productivity plugin, then
chose to keep one plugin and split it later only if that proves troublesome.

Three facts shaped how. Most of Anthropic's skills use the `argument-hint` and `user-invocable`
frontmatter fields that Claude Code and VS Code read, which the Agent Skills specification this
marketplace enforces does not define. The Productivity skills keep their state in `CLAUDE.md`, a `memory/` folder,
`TASKS.md` and a dashboard file in the working folder. Mail, calendar, LinkedIn and Codex Security
reach the agents through the providers' own connectors, which need the user's sign-in and which a
Claude Code plugin manifest cannot declare.

## Decision

- **One plugin.** `agentic-engineering` also carries the design, product-management, marketing,
  finance and productivity skills, installed unmodified with `gh skill install`. Their connectors
  are not bundled.
- **Two runtime fields are accepted.** The spec check judges each skill through a copy without
  `argument-hint` and `user-invocable`, and still rejects every other unknown field. Upstream skills
  are still never rewritten.
- **The plugin steers, it does not rewrite.** A maintained `workspace-conventions` skill sends the
  Productivity skills' state to `AGENTS.md`, the agent's native memory and the project's issue
  tracker. The dashboard template is not bundled.
- **Official connectors are requested, never improvised.** A maintained `connector-setup` skill
  names the official connector for each need, and how to ask the user to enable it: in Claude
  through the connector directory, in Codex as a plugin from OpenAI's catalogue. It says plainly
  when none exists, as for iCloud in Claude, and forbids unofficial servers, scraping and passwords.
- **Name clashes keep the first owner.** CodeRabbit's `code-review` and Product Management's
  `competitive-brief` keep their names; Anthropic's Engineering `code-review` and Marketing's
  `competitive-brief` are not bundled.

## Consequences

- The plugin is no longer engineering-only. Its description, README and catalogue say so, and
  `vibe-coding` and `ksail` stay separate as before.
- The bundle grows to 89 skills, so a session lists many more skill descriptions. If that crowds
  out the engineering ones, splitting off a productivity plugin is the planned next step.
- Mail, calendar and LinkedIn need one sign-in each by the user, and unattended runs never wait
  for one. Codex can install the iCloud and Codex Security plugins; Claude has no iCloud connector
  yet.
- The two accepted fields are not Claude-only. VS Code documents both for Copilot agent skills, and
  Codex's skill parser reads only `name`, `description` and `metadata.short-description`, ignoring
  any other field. Each field only adds an input hint or a menu switch, so a runtime that ignores
  them still runs the skill.
