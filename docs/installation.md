# Installation

## VS Code

Add the marketplace to your settings:

```jsonc
// settings.json
"chat.plugins.marketplaces": [
    "devantler-tech/agent-plugins"
]
```

Then open **Extensions**, search `@agentPlugins`, and install a plugin from this marketplace. Review the source when VS Code asks you to trust it. See the [VS Code plugin guide](https://code.visualstudio.com/docs/agent-customization/agent-plugins).

## Copilot CLI

Run these in your terminal; `devantler-plugins` is the marketplace name registered by the first command. See the [Copilot plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference).

```sh
# Register the marketplace
copilot plugin marketplace add devantler-tech/agent-plugins

# Browse available plugins
copilot plugin marketplace browse devantler-plugins

# Install a plugin
copilot plugin install agentic-engineering@devantler-plugins
```

## Claude Code

Add the marketplace, then install a plugin — run these inside Claude Code ([official guide](https://code.claude.com/docs/en/discover-plugins)):

```text
/plugin marketplace add devantler-tech/agent-plugins
/plugin install agentic-engineering@devantler-plugins
```

Browse everything on offer with `/plugin` (**Discover** tab) or list it with `/plugin list`. The bundled [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) is also discovered automatically when this repo is added as a plugin source.

Claude Desktop can add the same GitHub repository from **Plugins → Personal**. That path validates the marketplace remotely in strict mode; every plugin therefore includes the canonical `.claude-plugin/plugin.json` manifest it requires.

## Codex

Add the marketplace, then install a plugin, from a terminal:

```bash
codex plugin marketplace add https://github.com/devantler-tech/agent-plugins.git
codex plugin add agentic-engineering@devantler-plugins
```

Codex reads a plugin's `.codex-plugin/plugin.json` before its `.claude-plugin/plugin.json`. The
`agentic-engineering` plugin ships one so that it can also offer the official Codex apps its agents
use: iCloud Mail, iCloud Calendar, LinkedIn and Codex Security Cloud, all optional, listed in its
[`.app.json`](../plugins/agentic-engineering/.app.json). Each still needs your own sign-in.
The `ksail` plugin ships one for its OpenAI plugin directory listing; it offers no apps.
`scripts/validate-manifests.sh` keeps each Codex manifest identical to the portable one apart from its
component paths, app list and listing, and `scripts/bump-plugin-version.sh` moves its version
with the others.

## Any other agent — skills only, via `npx skills`

[`npx skills`](https://github.com/vercel-labs/skills) reads this repo's [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) and installs the bundled **skills** into its supported agents — useful when your agent isn't one of the three above:

```sh
# Browse the bundled skills without installing
npx skills add devantler-tech/agent-plugins --list

# Install specific skills for a specific agent
npx skills add devantler-tech/agent-plugins --skill gitops-knowledge --agent cursor
```

> [!IMPORTANT]
> This is a **partial** install path. The example installs only `gitops-knowledge` for Cursor. Use
> `--all` to install every bundled skill across detected agents, or choose another skill by name
> with `--skill <name>` and `--agent cursor` to target that agent. None of these skills-only forms
> install the [MCP servers](resources.md#mcp-servers) or [custom agents](resources.md#custom-agents). To get everything a
> plugin bundles, install it as a plugin in **VS Code**, **Copilot CLI**, or **Claude Code** above —
> all three load a plugin's bundled `.mcp.json` and `agents/` automatically.

## Moving from the retired category plugins

The `github`, `go`, `gitops-kubernetes`, `engineering-practices` and `frontend-design` plugins were
folded into `agentic-engineering` 6.8.0 ([ADR 0017](adr/0017-agentic-engineering-bundles-the-agents-toolbox.md)).
If you installed any of them, install `agentic-engineering@devantler-plugins` with the command for
your tool above, enable it, and uninstall the retired plugins. The marketplace records each retired
name as a rename, but Claude Code may report the migrated plugin as not cached until you install it
once, and other tools may not read renames at all.

The move widens what you run. Besides the skills you had, you get the engineering agents and three
MCP servers: Flux (read-only), GitHub's read-only security tools signed in with your github.com
login, and Sidero Labs' public documentation search. The
[bundled servers and agents](resources.md) guide describes each, and your tool permissions can deny
any you do not want.


[Plugin catalogue](plugins.md) · [Bundled servers and agents](resources.md)
