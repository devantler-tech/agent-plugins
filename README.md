# devantler-tech/plugins

A tool-neutral [agent-plugin marketplace](https://code.visualstudio.com/docs/copilot/customization/agent-plugins) that bundles the curated agent skills from [`devantler-tech/skills`](https://github.com/devantler-tech/skills) into category-based plugins.

Supports **VS Code**, **GitHub Copilot CLI**, and **Claude Code** via dual marketplace manifests.

## Plugins

| Plugin | Skills | Description |
|--------|--------|-------------|
| [`gitops-kubernetes`](plugins/gitops-kubernetes/) | `gitops-cluster-debug`, `gitops-knowledge`, `gitops-repo-audit` | Flux CD debugging, knowledge, and repository auditing |
| [`github`](plugins/github/) | `gh-cli`, `gh-stack`, `github-actions-docs`, `github-issues` | GitHub CLI, stacked PRs, Actions docs, and issue management |
| [`copilot`](plugins/copilot/) | `copilot-instructions-blueprint-generator`, `copilot-sdk`, `find-skills` | Copilot customisation and skill discovery |
| [`go`](plugins/go/) | `golang-pro` | Go best practices, concurrency, generics, interfaces, and testing |
| [`engineering-practices`](plugins/engineering-practices/) | `git-commit`, `refactor`, `test-driven-development` | Git commits, refactoring, and TDD |
| [`frontend-design`](plugins/frontend-design/) | `astro`, `frontend-design`, `web-design-guidelines` | Astro, frontend design, and web design guidelines |

## Installation

### VS Code

Add the marketplace to your settings:

```jsonc
// settings.json
"chat.plugins.marketplaces": [
    "devantler-tech/plugins"
]
```

Then browse **Extensions → Agent Plugins** (`@agentPlugins` search) to install individual plugins.

### Copilot CLI

```sh
# Browse available plugins
copilot plugin marketplace browse devantler-tech/plugins

# Install a plugin
copilot plugin install gitops-kubernetes@devantler-plugins
```

### Claude Code

The repo includes a `.claude-plugin/marketplace.json` for automatic discovery.

## How it works

Skills are installed from their upstream repositories using [`gh skill install`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/). A [daily update workflow](.github/workflows/update-copilot-skills.yaml) runs [`gh skill update --all`](https://github.com/devantler-tech/actions/tree/main/update-copilot-skills) via the [`update-copilot-skills`](https://github.com/devantler-tech/reusable-workflows/blob/main/.github/workflows/update-copilot-skills.yaml) reusable workflow and opens a PR when upstream content has drifted.

Each plugin directory is self-contained with a `plugin.json` manifest and a `skills/` subdirectory holding the installed `SKILL.md` files (plus any supporting assets). Each `SKILL.md` contains `metadata.github-*` frontmatter for upstream provenance — no lockfile needed.

See [`devantler-tech/skills`](https://github.com/devantler-tech/skills) for the curated skill index and upstream links.

## Contributing

See the [devantler-tech organisation guidelines](https://github.com/devantler-tech/.github) for PR/issue templates and contribution rules.

## License

Apache 2.0 — see [`LICENSE`](LICENSE).
