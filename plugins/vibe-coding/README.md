# `vibe-coding`

A plugin for a **non-technical person building a product by conversation alone** — the fourth,
non-engineering audience of this marketplace (design:
[ADR 0003](../../docs/adr/0003-vibe-coding-plugin-design.md)).

It bundles the **`vibe-coding-companion`** agent (plain-language elicitation, outcome-first
reporting, conversational approval instead of code review) and three skills with their canonical
home in [devantler-tech/agent-skills](https://github.com/devantler-tech/agent-skills):
`needs-stack-mapping` (plain-language needs → the deployment's building blocks, behind the
scenes), `allowed-stack-guardrail` (build only inside the deployment's allowed stack; decline
kindly + offer to file a request otherwise; fail closed without a map), and `jargon-free-voice`
(the conversational register).

## Consumer setup: the Stack map

The allowed stack is **deployment-owned configuration, not plugin content**. Before the guardrail
can approve anything, the consuming deployment's canonical instructions file (`AGENTS.md`) must
carry a **`## Stack map`** section: a table with **Building block** / **Good for** / **Owning
repo** columns plus a **default intake repo** for unmapped needs. Without it the plugin fails
closed (declines every build). See ADR 0003 D3 for the pinned contract.

## VS Code delivery step

Claude Code and Copilot CLI load the bundled `agents/` directory automatically when the plugin is
installed. **VS Code does not** — copy the companion agent into your workspace as
`.github/agents/vibe-coding-companion.agent.md` to use it there.
