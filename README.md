# devantler-tech/agent-plugins

A tool-neutral [agent-plugin marketplace](https://code.visualstudio.com/docs/copilot/customization/agent-plugins) that bundles curated agent skills — sourced from across the agent-skill ecosystem — into category-based plugins.

Supports **VS Code**, **GitHub Copilot CLI**, and **Claude Code** via dual marketplace manifests.

## Scope

This is a **tool-neutral plugin marketplace**, not a skills-only bundler. Every plugin published today bundles [agent skills](https://github.com/devantler-tech/agent-skills), but a plugin may bundle **any agent resource** — skills, [MCP](https://modelcontextprotocol.io) servers, and custom agents — so the marketplace can grow with the cross-tool agent ecosystem instead of being pinned to one tool or one resource type. Additional resource types are added as they prove out across the supported tools.

## Plugins

| Plugin | Resources | Description |
|--------|-----------|-------------|
| [`gitops-kubernetes`](plugins/gitops-kubernetes/) | `gitops-cluster-debug`, `gitops-knowledge`, `gitops-repo-audit`, `gitops-tenant-onboarding` (skills) · `flux-operator-mcp` (MCP server) | Flux CD debugging, knowledge, repository auditing, and tenant onboarding — bundles the Flux MCP server for live-cluster debugging |
| [`github`](plugins/github/) | `gh-cli`, `gh-stack`, `github-actions-docs`, `github-issues` | GitHub CLI, stacked PRs, Actions docs, and issue management |
| [`agentic-engineering`](plugins/agentic-engineering/) | `agent-instructions`, `copilot-instructions-blueprint-generator`, `copilot-sdk`, `find-skills` | Agentic AI framework SDKs, AI-assistant instruction authoring, and skill discovery |
| [`go`](plugins/go/) | `golang-pro` | Go best practices, concurrency, generics, interfaces, and testing |
| [`engineering-practices`](plugins/engineering-practices/) | `conventional-release`, `git-commit`, `refactor`, `test-driven-development`, `ways-of-working` | Git commits, conventional releases, refactoring, TDD, and engineering ways of working |
| [`frontend-design`](plugins/frontend-design/) | `astro`, `frontend-design`, `web-design-guidelines` | Astro, frontend design, and web design guidelines |

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

## MCP servers

A plugin may bundle [MCP](https://modelcontextprotocol.io) servers as well as skills. The
[`gitops-kubernetes`](plugins/gitops-kubernetes/) plugin bundles the **Flux MCP server**
([`flux-operator-mcp`](https://github.com/controlplaneio-fluxcd/flux-operator/tree/main/cmd/mcp))
so its `gitops-cluster-debug` skill — which `Requires flux-operator-mcp` — works against a live
cluster out of the box.

The server is authored once as the plugin's [`.mcp.json`](plugins/gitops-kubernetes/.mcp.json)
(`mcpServers` map). How each tool consumes it differs (per [ADR 0001](docs/adr/0001-bundling-mcp-servers-and-custom-agents.md)):

- **Claude Code** and **Copilot CLI** — the bundled `.mcp.json` is loaded automatically when the
  plugin is installed; no extra configuration is needed.
- **VS Code** consumes MCP but does not bundle it from a plugin. Add the equivalent entry to your
  workspace `.vscode/mcp.json` (note the key is `servers`, not `mcpServers`):

  ```json
  {
    "servers": {
      "flux-operator-mcp": { "command": "flux-operator-mcp", "args": ["serve"] }
    }
  }
  ```

All three paths invoke the same `flux-operator-mcp` binary, so install it first — e.g.
`brew install controlplaneio-fluxcd/tap/flux-operator-mcp` or `go install
github.com/controlplaneio-fluxcd/flux-operator/cmd/mcp@latest` (it reads your kubeconfig from
`KUBECONFIG` / `~/.kube/config`). See the
[Flux MCP docs](https://fluxcd.control-plane.io/operator/mcp/) for read-only mode and remote
transport.

## How it works

Skills are installed from their upstream repositories using [`gh skill install`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/). A [daily update workflow](.github/workflows/update-agent-skills.yaml) runs [`gh skill update --all`](https://github.com/devantler-tech/actions/tree/main/update-agent-skills) via the [`update-agent-skills`](https://github.com/devantler-tech/reusable-workflows/blob/main/.github/workflows/update-agent-skills.yaml) reusable workflow and opens a PR when upstream content has drifted.

Each plugin directory is self-contained with a `plugin.json` manifest and its bundled resources — a `skills/` subdirectory holding the installed `SKILL.md` files (plus any supporting assets), and optionally an `.mcp.json` declaring bundled MCP servers. Each `SKILL.md` contains `metadata.github-*` frontmatter for upstream provenance — no lockfile needed.

Each bundled skill is pulled from its own upstream (recorded in its `SKILL.md` `metadata.github-*` frontmatter), spanning many sources — including our in-house sibling library [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills).

## Contributing

See the [devantler-tech organisation guidelines](https://github.com/devantler-tech/.github) for PR/issue templates and contribution rules.

## License

Apache 2.0 — see [`LICENSE`](LICENSE).
