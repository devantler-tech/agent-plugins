# Changelog — `ksail`

## 1.0.1 — 2026-11-04

- Add the KSail app icon at `.claude-plugin/icon.png` (1024 × 1024 PNG, copied from
  `desktop/resources/icon.png` in `devantler-tech/ksail`), so the Claude plugin directory can show
  it as the listing icon.
- Add a Codex manifest at `.codex-plugin/plugin.json`. It repeats the portable manifest, loads the
  skill and the `ksail` MCP server, and gives the OpenAI plugin directory its listing: name, short
  and long descriptions, the Developer Tools category, website and support links, three example
  prompts, brand colours and the same icon.
