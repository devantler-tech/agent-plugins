# 0019. A Codex manifest offers the official apps the agents use

## Context

The maintainer wants the agents' mail, calendar, LinkedIn and Codex Security connections enabled
automatically wherever possible ([ADR 0018](0018-agentic-engineering-covers-the-agents-workspace.md)).
A Claude Code plugin manifest cannot declare a claude.ai connector, so in Claude the plugin can
only tell the agents what to ask for. Codex plugins can: a `.codex-plugin/plugin.json` names an
`.app.json` whose apps Codex offers with the plugin. Codex already loaded this marketplace's
plugins through their `.claude-plugin/plugin.json`.

Codex's own source settles how the files interact. It reads `.codex-plugin/plugin.json` before
`.claude-plugin/plugin.json`, and resolves skills, MCP servers and apps only from the paths that
manifest declares. Installing a branch build into a throwaway `CODEX_HOME` showed Codex loading the
plugin's skills and every bundled MCP server through the new manifest. The connector ids were read
from the official iCloud Mail, iCloud Calendar and LinkedIn plugins after installing them; the Codex
Security Cloud id comes from OpenAI's published `codex-security` plugin.

## Decision

- `agentic-engineering` ships a `.codex-plugin/plugin.json` and an `.app.json`. The manifest
  repeats the portable `plugin.json` exactly and adds only `skills`, `mcpServers`, `apps` and an
  `interface` listing.
- Every app is optional (`"required": false`): installing the plugin never forces a connector the
  user has not chosen.
- `validate-manifests.sh` enforces that shape and refuses an `.app.json` no Codex manifest
  declares. `bump-plugin-version.sh` moves the Codex manifest's version with the other four.

## Consequences

- Codex users see the four apps offered with the plugin and still sign in to each themselves.
- A new bundled resource directory or file must also be named in the Codex manifest, or Codex will
  not load it; the validator catches a missing `skills` or `mcpServers` path.
- Connector ids are Codex's internal identifiers. If OpenAI changes one, the app silently stops
  being offered until the id is updated, so re-read it from the installed plugin when in doubt.
