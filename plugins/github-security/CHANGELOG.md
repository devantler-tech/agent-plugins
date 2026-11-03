# Changelog — `github-security`

## 1.0.0 — 2026-11-03

**Added** — the plugin, with five skills and GitHub's read-only security MCP tools:

- `dependency-scanning` from `https://github.com/github/copilot-advanced-security-plugin` at `refs/heads/main`.
- `codeql`, `dependabot`, `github-actions-hardening` and `secret-scanning` from
  `https://github.com/github/awesome-copilot` at `refs/heads/main`.
- `github-ghas-tools`, GitHub's remote MCP server limited to the `code_security`,
  `secret_protection`, `security_advisories` and `dependabot` toolsets. In Claude Code it signs in
  through `scripts/github-mcp-headers.sh`, which sends the GitHub CLI login token or
  `GITHUB_SECURITY_MCP_TOKEN`.
