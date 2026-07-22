# devantler-tech/agent-plugins

A tool-neutral [agent-plugin marketplace](https://code.visualstudio.com/docs/copilot/customization/agent-plugins) that bundles curated agent skills — sourced from across the agent-skill ecosystem — into category-based plugins.

Supports **VS Code**, **GitHub Copilot CLI**, and **Claude Code** via dual marketplace manifests.

## Scope

This is a **tool-neutral plugin marketplace**, not a skills-only bundler. Every plugin published today bundles [agent skills](https://github.com/devantler-tech/agent-skills), but a plugin may bundle **any agent resource** — skills, [MCP](https://modelcontextprotocol.io) servers, and custom agents — so the marketplace can grow with the cross-tool agent ecosystem instead of being pinned to one tool or one resource type. Additional resource types are added as they prove out across the supported tools.

## Plugins

| Plugin | Resources | Description |
|--------|-----------|-------------|
| [`gitops-kubernetes`](plugins/gitops-kubernetes/) | `gitops-cluster-debug`, `gitops-knowledge`, `gitops-repo-audit`, `gitops-tenant-onboarding` (skills) · `flux-operator-mcp` (MCP server) · `flux-troubleshooter` (agent) | Flux CD debugging, knowledge, repository auditing, and tenant onboarding — bundles the Flux MCP server and a read-only Flux troubleshooter agent for live-cluster debugging |
| [`github`](plugins/github/) | `gh-cli`, `gh-stack`, `github-actions-docs`, `github-issues` | GitHub CLI, stacked PRs, Actions docs, and issue management |
| [`agentic-engineering`](plugins/agentic-engineering/) | `agent-improvement`, `agent-instructions`, `find-skills`, `portfolio-maintenance`, `product-engineering`, `self-improvement` (skills) · `agent-improver`, `automated-ai-engineer`, `portfolio-surveyor` (agents) | The autonomous engineering system for a whole repository portfolio — engineer, read-only surveyor, and meta-engineer agents plus their operating and improvement workflows; configured by the consumer's `AGENTS.md` |
| [`go`](plugins/go/) | `golang-pro` | Go best practices, concurrency, generics, interfaces, and testing |
| [`engineering-practices`](plugins/engineering-practices/) | `conventional-release`, `git-commit`, `refactor`, `test-driven-development`, `ways-of-working` | Git commits, conventional releases, refactoring, TDD, and engineering ways of working |
| [`frontend-design`](plugins/frontend-design/) | `astro`, `frontend-design`, `web-design-guidelines` | Astro, frontend design, and web design guidelines |
| [`vibe-coding`](plugins/vibe-coding/) | `needs-stack-mapping`, `allowed-stack-guardrail`, `jargon-free-voice` (skills) · `vibe-coding-companion` (agent) | Build a product by conversation alone — plain-language companion agent + guardrailed needs-to-stack skills for people with no technical background |

## Installation

### VS Code

Add the marketplace to your settings:

```jsonc
// settings.json
"chat.plugins.marketplaces": [
    "devantler-tech/agent-plugins"
]
```

Then browse **Extensions → Agent Plugins** (`@agentPlugins` search) to install individual plugins.

### Copilot CLI

```sh
# Browse available plugins
copilot plugin marketplace browse devantler-tech/agent-plugins

# Install a plugin
copilot plugin install gitops-kubernetes@devantler-plugins
```

### Claude Code

Add the marketplace, then install a plugin — run these inside Claude Code:

```text
/plugin marketplace add devantler-tech/agent-plugins
/plugin install gitops-kubernetes@devantler-plugins
```

Browse everything on offer with `/plugin` (**Discover** tab) or list it with `/plugin list`. The bundled [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) is also discovered automatically when this repo is added as a plugin source.

### Any other agent — skills only, via `npx skills`

[`npx skills`](https://github.com/vercel-labs/skills) reads this repo's [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) and installs the bundled **skills** into any of its 70+ supported agents — useful when your agent isn't one of the three above:

```sh
# Browse the bundled skills without installing
npx skills add devantler-tech/agent-plugins --list

# Install specific skills for a specific agent
npx skills add devantler-tech/agent-plugins --skill gitops-knowledge --agent cursor
```

> [!IMPORTANT]
> This is a **partial** install path. The example installs only `gitops-knowledge` for Cursor. Use
> `--all` to install every bundled skill across detected agents, or combine a pattern such as
> `--skill gitops-*` with `--agent cursor` to target that agent. None of these skills-only forms
> install the [MCP servers](#mcp-servers) or [custom agents](#custom-agents). To get everything a
> plugin bundles, install it as a plugin in **VS Code**, **Copilot CLI**, or **Claude Code** above —
> all three load a plugin's bundled `.mcp.json` and `agents/` automatically.

## Copy-paste agent onboarding

The [`agentic-engineering` desired-state manifest](plugins/agentic-engineering/resources/provider-neutral.desired-state.json)
is a provider-neutral, copy-paste onboarding document for a new assistant. Open the assistant in the
consumer repository, paste the complete JSON, and ask it to reconcile the desired state. It points to
the latest reviewed plugin for generic role logic and to the consumer's `AGENTS.md` for organization,
trust, cadence, memory, and maintainer-channel configuration. It also requires the assistant to report
unsupported native capabilities instead of silently weakening the deployment. The manifest carries
separate thin schedule prompts for the Automated AI Engineer, Agent Improver, and consumer-owned FinOps
Engineer; each resolves its cadence and deployment facts from the canonical consumer instructions.
Existing `automated-ai-engineer` plugin installations should follow the
[version 2 migration checklist](plugins/agentic-engineering/README.md#migrating-from-automated-ai-engineer)
before their next scheduled run.

## MCP servers

A plugin may bundle [MCP](https://modelcontextprotocol.io) servers as well as skills. The
[`gitops-kubernetes`](plugins/gitops-kubernetes/) plugin bundles the **Flux MCP server**
([`flux-operator-mcp`](https://github.com/controlplaneio-fluxcd/flux-operator/tree/main/cmd/mcp))
so its `gitops-cluster-debug` skill — which `Requires flux-operator-mcp` — works against a live
cluster out of the box.

The server is authored once as the plugin's [`.mcp.json`](plugins/gitops-kubernetes/.mcp.json)
(`mcpServers` map). How each tool consumes it differs (per [ADR 0001](docs/adr/0001-bundling-mcp-servers-and-custom-agents.md)):

- **Claude Code**, **Copilot CLI**, and **VS Code** — the bundled `.mcp.json` is loaded automatically
  when the plugin is installed; no extra configuration is needed. In VS Code the server starts and
  stops with the plugin and needs no separate trust prompt, because installing the plugin is what
  grants the trust.

You only need to write MCP config by hand if you are **not** installing this as a plugin — then add the
server to your workspace `.vscode/mcp.json` (note the key there is `servers`, not `mcpServers`):

```json
{
  "servers": {
    "flux-operator-mcp": { "command": "flux-operator-mcp", "args": ["serve"] }
  }
}
```

Every path invokes the same `flux-operator-mcp` binary, so install it first — e.g.
`brew install controlplaneio-fluxcd/tap/flux-operator-mcp` or `go install
github.com/controlplaneio-fluxcd/flux-operator/cmd/mcp@latest` (it reads your kubeconfig from
`KUBECONFIG` / `~/.kube/config`). See the
[Flux MCP docs](https://fluxcd.control-plane.io/operator/mcp/) for read-only mode and remote
transport.

## Custom agents

A plugin may also bundle **custom agents** (subagents). The
[`gitops-kubernetes`](plugins/gitops-kubernetes/) plugin bundles
[`flux-troubleshooter`](plugins/gitops-kubernetes/agents/flux-troubleshooter.agent.md) — a **read-only**
Flux CD triage agent that traces the GitOps dependency chain (source → Kustomization/HelmRelease →
workloads), reads status conditions and controller logs via the bundled `flux-operator-mcp` server,
and returns a root-cause diagnosis plus the human-applied fix. It has no apply/reconcile/suspend/
delete tool by design, so it never mutates the cluster.

The agent is authored once as `agents/<name>.agent.md` (Markdown + YAML frontmatter, with the neutral
`name`/`description`/`tools`/`model` core). The `.agent.md` filename is what VS Code and Copilot
discover inside a plugin's `agents/` directory; Claude Code is filename-agnostic (it reads any
Markdown in `agents/` and takes the agent's name from frontmatter), so one file serves all three
tools. The same goes for the `tools:` allowlist: MCP tools are listed in both spellings — Claude
Code's `mcp__<server>__<tool>` and VS Code / Copilot's `<server>/<tool>` — because each tool
ignores entries it does not recognise (per
[ADR 0001](docs/adr/0001-bundling-mcp-servers-and-custom-agents.md)):

- **Claude Code**, **Copilot CLI**, and **VS Code** — the bundled `agents/` directory is loaded
  automatically when the plugin is installed; in Claude Code the agent is namespaced
  `gitops-kubernetes:flux-troubleshooter`.

As with MCP, hand-placing an agent at `.github/agents/<name>.agent.md` is only for setups that aren't
installing this as a plugin.

The [`vibe-coding`](plugins/vibe-coding/) plugin bundles
[`vibe-coding-companion`](plugins/vibe-coding/agents/vibe-coding-companion.agent.md) — a plain-language
build companion for a non-technical audience (design:
[ADR 0003](docs/adr/0003-vibe-coding-plugin-design.md)). Same delivery rules. Its guardrail requires
the consuming deployment to author a `## Stack map` section in its `AGENTS.md` (see the
[plugin README](plugins/vibe-coding/README.md)).

The [`agentic-engineering`](plugins/agentic-engineering/) plugin bundles three agents —
[`automated-ai-engineer`](plugins/agentic-engineering/agents/automated-ai-engineer.agent.md) (the
autonomous portfolio-engineer actor),
[`portfolio-surveyor`](plugins/agentic-engineering/agents/portfolio-surveyor.agent.md) (its read-only
survey subagent), and
[`agent-improver`](plugins/agentic-engineering/agents/agent-improver.agent.md) (a meta-engineer that
improves the engineer itself from measured evidence) — alongside its engineering skills (design:
[ADR 0002](docs/adr/0002-automated-ai-engineer-plugin-boundary.md), consolidation:
[ADR 0004](docs/adr/0004-consolidate-agentic-engineering.md)). Same delivery rules; the
consuming deployment must define the five contract sections (Portfolio map, Trust gate, Cadence,
Memory, Maintainer channels) in its `AGENTS.md` — plus **Agent definition locations** and
**Authority model** if it enables `agent-improver` (see the
[plugin README](plugins/agentic-engineering/README.md)).

## How it works

Skills are installed from their upstream repositories using [`gh skill install`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/). A [daily update workflow](.github/workflows/update-agent-skills.yaml) runs [`gh skill update --all`](https://github.com/devantler-tech/actions/tree/main/update-agent-skills) via the [`update-agent-skills`](https://github.com/devantler-tech/actions/blob/main/.github/workflows/update-agent-skills.yaml) reusable workflow and opens a PR when upstream content has drifted.

Each plugin directory is self-contained with a `plugin.json` manifest and its bundled resources — a `skills/` subdirectory holding the installed `SKILL.md` files (plus any supporting assets), and optionally an `.mcp.json` declaring bundled MCP servers and an `agents/` directory holding custom agents. A plugin may also carry ancillary, human-consumed assets under `resources/`, such as a desired-state document; these are linked explicitly rather than treated as auto-discovered runtime components. Each `SKILL.md` contains `metadata.github-*` frontmatter for upstream provenance — no lockfile needed.

Each bundled skill is pulled from its own upstream (recorded in its `SKILL.md` `metadata.github-*` frontmatter), spanning many sources — including our in-house sibling library [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills).

## Contributing

See the [devantler-tech organisation guidelines](https://github.com/devantler-tech/.github) for PR/issue templates and contribution rules.

## License

Apache 2.0 — see [`LICENSE`](LICENSE).
