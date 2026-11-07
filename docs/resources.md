# Bundled servers and agents

[Plugin catalogue](plugins.md) · [Installation](installation.md)

The [tool ownership assessment](tool-ownership.md) records the callers and owners of marketplace
maintenance tools, installed agent helpers and copied skill resources, with explicit limits on
what those observations establish.

## Copy-paste agent onboarding

The [`agentic-engineering` desired-state manifest](../plugins/agentic-engineering/resources/provider-neutral.desired-state.json)
is a provider-neutral, copy-paste onboarding document for a new assistant. Open the assistant in the
consumer repository, paste the complete JSON, and ask it to reconcile the desired state. It points to
the latest reviewed plugin for generic role logic and to the consumer's `AGENTS.md` for organization,
trust, cadence, memory, and maintainer-channel configuration. It also requires the assistant to report
unsupported native capabilities instead of silently weakening the deployment. The manifest carries
separate thin schedule prompts for the Agentic Engineer and the Agent Improver; each resolves its
cadence and deployment facts from the canonical consumer instructions. Spend stewardship has no
schedule of its own. It runs inside the engineer's loop only after explicit maintainer opt-in through
`spec.roles["agentic-engineer"].spendStewardshipEnabled` and a resolving `Spend contract`.
Existing installations must complete every upgrade step that lies between their installed version and
the current one before their next scheduled run, in ascending order —
[2.0.0](../plugins/agentic-engineering/CHANGELOG.md#upgrading-to-200) (plugin identity),
[3.0.0](../plugins/agentic-engineering/CHANGELOG.md#upgrading-to-300) (retire the `finops-engineer`
schedule and adopt the `Spend contract` section),
[4.0.0](../plugins/agentic-engineering/CHANGELOG.md#upgrading-to-400) (the `automated-ai-engineer` →
`agentic-engineer` entrypoint rename), then
[5.0.0](../plugins/agentic-engineering/CHANGELOG.md#upgrading-to-500) (explicit default-off spend
enablement). Stopping early would resume unattended writes with the retired FinOps schedule still
armed, or with a schedule pointing at an entrypoint that no longer resolves. The
[changelog](../plugins/agentic-engineering/CHANGELOG.md) carries every released version.

## MCP servers

A plugin may bundle [MCP](https://modelcontextprotocol.io) servers as well as skills. The
[`agentic-engineering`](../plugins/agentic-engineering/) plugin bundles twelve, authored once in its
[`.mcp.json`](../plugins/agentic-engineering/.mcp.json) (`mcpServers` map), and the
[`ksail`](../plugins/ksail/) plugin bundles the KSail server, which needs `ksail` on `PATH`:

| Server | What it connects to | Needs |
|---|---|---|
| `aws-knowledge` | AWS's hosted knowledge server: AWS documentation and regional availability, read-only | Nothing; it works without an AWS account |
| `cloudflare-docs` | Cloudflare's hosted documentation search, read-only | Nothing; it is public |
| `context7` | Upstash's Context7: current documentation and code examples for libraries and frameworks, read-only | Nothing; it works without an account |
| `coroot` | Your own Coroot instance's `/mcp` endpoint: topology, alerts, incidents, traces, metrics and logs; a Viewer key cannot resolve alerts, and in the Enterprise Edition can save an investigation onto an incident | `COROOT_URL`, a pinned address and a service-account API key; see the plugin README |
| `flux-operator-mcp` | A live cluster's Flux resources, read-only (`serve --read-only`), for the `gitops-cluster-debug` skill and the `flux-troubleshooter` agent | The `flux-operator-mcp` binary, a POSIX `sh`, and cluster access through `KUBECONFIG` (default `~/.kube/config`) |
| `github` | GitHub's everyday tools: repositories, issues, pull requests, Actions, labels and projects, read, and issue, label, comment, branch, new pull request and project writes; merging, pull request edits, reviews, repository creation and deletion, file writes and workflow runs are excluded | A GitHub sign-in; see below |
| `github-ghas-tools` | GitHub's security tools, read-only (`X-MCP-Readonly`): alerts, advisories and dependency vulnerability lookups | A GitHub sign-in; see below |
| `kubescape` | A live cluster's Kubescape results, read-only (`kubescape mcpserver`): vulnerabilities, configuration scans, SBOMs and exposure checks | The `kubescape` CLI (v4 or later), a POSIX `sh`, and cluster access through `KUBECONFIG` (default `~/.kube/config`) |
| `siderolabs-docs` | Sidero Labs' search of the Talos Linux and Omni documentation | Nothing; it is public |
| `stripe` | Stripe's hosted server at `https://mcp.stripe.com`: Stripe documentation, reads and writes on your Stripe account, analytics and money movement | A Stripe sign-in through OAuth |
| `svelte` | The Svelte team's hosted server at `https://mcp.svelte.dev/mcp`: Svelte 5 and SvelteKit documentation, the `svelte-autofixer` and playground links, all read-only | Nothing; it is public |
| `terraform-registry` | HashiCorp's Terraform server, `registry` toolset only: public provider and module documentation, read-only | The `terraform-mcp-server` binary |

`flux-operator-mcp` talks only to your clusters, and `coroot` only to the Coroot instance you point
it at. `kubescape` also downloads Kubescape's released policy bundle from GitHub each time it
starts, and `terraform-registry` runs locally but queries the public Terraform Registry. Every
other server is hosted by a third party, so every call to one, including a documentation search,
reaches that service. If your agents must not contact a third party, disable its server in your
tool's MCP settings; denying single tools does not stop the connection. Among
the servers you keep, `github` and `stripe` can change things: `github` writes to GitHub as the
signed-in account, and `stripe` writes to your Stripe account and can move money. With a Viewer
key, `coroot`'s Enterprise Edition `investigate_anomaly` can save its analysis onto an incident.
The
`siderolabs-docs` `submit_feedback` and `stripe` `send_stripe_feedback` tools send reports to Sidero
Labs and Stripe. The Svelte autofixer and playground tools send the code they are given to Svelte's
service, and the playground link carries that code. The
[plugin README](../plugins/agentic-engineering/README.md#bundled-mcp-servers) covers each server's
sign-in and what to deny.

How each tool consumes the file differs (per [ADR 0001](../docs/adr/0001-bundling-mcp-servers-and-custom-agents.md)):

- **Claude Code**, **Copilot CLI**, and **VS Code** — the bundled `.mcp.json` is loaded automatically
  when the plugin is installed. Local servers' binaries must be installed separately; the Flux
  server also needs access to the intended cluster.

You only need to write MCP config by hand if you are **not** installing this as a plugin — then add the
server to your workspace `.vscode/mcp.json` (note the key there is `servers`, not `mcpServers`):

```json
{
  "servers": {
    "flux-operator-mcp": {
      "command": "flux-operator-mcp",
      "args": ["serve", "--read-only"],
      "env": { "KUBECONFIG": "${userHome}/.kube/config" }
    }
  }
}
```

Every path invokes the same `flux-operator-mcp` binary, so install it first — e.g.
`brew install controlplaneio-fluxcd/tap/flux-operator-mcp` or `go install
github.com/controlplaneio-fluxcd/flux-operator/cmd/mcp@latest`. It refuses to start unless the
`KUBECONFIG` environment variable is set, which is why the hand-written entry sets it; the bundled
plugin's `sh` wrapper sets it to `$HOME/.kube/config` when it is unset or empty. It can read every
context in that kubeconfig, starting at the current one, because its read-only
`set_kubeconfig_context` tool switches between them. See the
[Flux MCP docs](https://fluxcd.control-plane.io/operator/mcp/) for read-only mode and remote
transport.

`github` and `github-ghas-tools` are both GitHub's remote MCP server, so nothing needs installing:
`github` with its everyday toolsets and most write tools, `github-ghas-tools` on the read-only
endpoint with only its security toolsets. Copilot CLI and VS Code sign in to them with your Copilot
session; Claude Code
runs the plugin's `headersHelper`, which sends your GitHub CLI login token. The
[plugin README](../plugins/agentic-engineering/README.md#bundled-mcp-servers) covers sign-in for
each tool and the optional narrower token.

## Custom agents

A plugin may also bundle **custom agents** (subagents). Besides its engineer, surveyor and improver
roles, the [`agentic-engineering`](../plugins/agentic-engineering/) plugin bundles
[`flux-troubleshooter`](../plugins/agentic-engineering/agents/flux-troubleshooter.agent.md) — a **read-only**
Flux CD triage agent that traces the GitOps dependency chain (source → Kustomization/HelmRelease →
workloads), reads status conditions and controller logs via the bundled `flux-operator-mcp` server,
and returns a root-cause diagnosis plus the human-applied fix. It has no apply/reconcile/suspend/
delete tool by design, so it never mutates the cluster.

The agent is authored once as `agents/<name>.agent.md` (Markdown + YAML frontmatter, with the neutral
`name`/`description`/`tools`/`model` core). The `.agent.md` filename is what VS Code and Copilot
discover inside a plugin's `agents/` directory; Claude Code is filename-agnostic (it reads any
Markdown in `agents/` and takes the agent's name from frontmatter), so one file serves all three
tools. The same goes for the `tools:` allowlist: MCP tools are listed in three spellings — Claude
Code's `mcp__plugin_<plugin>_<server>__<tool>` for the server this plugin bundles, its
`mcp__<server>__<tool>` for a server you configure by hand, and VS Code / Copilot's
`<server>/<tool>` — because each tool ignores entries it does not recognise (per
[ADR 0001](../docs/adr/0001-bundling-mcp-servers-and-custom-agents.md)):

- **Claude Code**, **Copilot CLI**, and **VS Code** — the bundled `agents/` directory is loaded
  automatically when the plugin is installed; in Claude Code the agent is namespaced
  `agentic-engineering:flux-troubleshooter`.

As with MCP, hand-placing an agent at `.github/agents/<name>.agent.md` is only for setups that aren't
installing this as a plugin.

The [`vibe-coding`](../plugins/vibe-coding/) plugin bundles
[`vibe-coding-companion`](../plugins/vibe-coding/agents/vibe-coding-companion.agent.md) — a plain-language
build companion for a non-technical audience (design:
[ADR 0003](../docs/adr/0003-vibe-coding-plugin-design.md)). Same delivery rules. Its guardrail requires
the consuming deployment to author a `## Stack map` section in its `AGENTS.md` (see the
[plugin README](../plugins/vibe-coding/README.md)).

The [`agentic-engineering`](../plugins/agentic-engineering/) plugin bundles three agents —
[`agentic-engineer`](../plugins/agentic-engineering/agents/agentic-engineer.agent.md) (the
autonomous portfolio-engineer actor),
[`portfolio-surveyor`](../plugins/agentic-engineering/agents/portfolio-surveyor.agent.md) (its read-only
survey subagent), and
[`agent-improver`](../plugins/agentic-engineering/agents/agent-improver.agent.md) (a meta-engineer that
improves the engineer itself from measured evidence) — alongside its engineering skills (design:
[ADR 0002](../docs/adr/0002-automated-ai-engineer-plugin-boundary.md), consolidation:
[ADR 0004](../docs/adr/0004-consolidate-agentic-engineering.md), spend stewardship:
[ADR 0005](../docs/adr/0005-merge-spend-stewardship-into-the-engineer.md)). Same delivery rules; the
consuming deployment must define the five contract sections (Portfolio map, Trust gate, Cadence,
Memory, Maintainer channels) in its `AGENTS.md` — plus **Agent definition locations** and
**Authority model** if it enables `agent-improver`, and **Spend contract** plus explicit maintainer
opt-in if it wants the engineer to steward spend (see the
[plugin README](../plugins/agentic-engineering/README.md)).
