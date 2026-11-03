# 0017. The agentic-engineering plugin bundles everything its agents need

## Context

The marketplace shipped the engineer's role as `agentic-engineering` and the tools its agents work
with as six category plugins: `github`, `go`, `gitops-kubernetes`, `engineering-practices`,
`frontend-design` and `ksail`. A deployment had to install and enable seven plugins in every runtime
to give its agents their full toolbox, and each runtime drifted on its own: one had the role but not
the KSail plugin, another ran a retired KSail source. Adding upstream resources as further category
plugins would have repackaged other projects' plugins under new names.

The maintainer directed on 2026-11-03 that `agentic-engineering` become one simple wrapper for
everything the agents need.

## Decision

`agentic-engineering` bundles the skills, agents and MCP servers its agents use, in one plugin.
The six category plugins are retired. Their names stay in the append-only `renames` map, pointing
at `agentic-engineering`, so runtimes that honour it migrate existing installs.

`vibe-coding` stays separate. It serves a person with no technical background building a product
by conversation, not the engineering agents.

Upstream resources join as parts of this plugin, never as repackaged copies of another project's
plugin: a curated skill installed with `gh skill install`, or an MCP server definition the agents
need. Where an upstream plugin's own configuration does not work for these agents, the plugin
carries a working equivalent and says how it differs.

## Consequences

- One install and one enablement give a deployment's agents their whole toolbox, in every runtime.
- Every upstream skill update now changes `agentic-engineering` and moves its version, so the
  reviewed definition refresh that [ADR 0002](0002-automated-ai-engineer-plugin-boundary.md) D3
  expected to be rare happens with each skill sync. ADR 0002's split of role from deployment
  configuration still holds; its assumption that the plugin changes slowly does not.
- Interactive users who wanted only one category can no longer install it alone.
- Skill names share one namespace (`agentic-engineering:<skill>`), so a curated skill whose name
  collides with an existing one needs a decision before it can join.
