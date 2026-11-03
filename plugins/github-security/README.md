# `github-security`

Security work on GitHub repositories you maintain: keep dependencies free of known
vulnerabilities, keep secrets out of the code, configure code scanning, and harden GitHub Actions
workflows. It brings together GitHub's own
[Advanced Security plugin](https://github.com/github/copilot-advanced-security-plugin) and
security skills from [`github/awesome-copilot`](https://github.com/github/awesome-copilot).

| Skill | Use it to |
|---|---|
| `dependency-scanning` | Check Dependabot alerts, look up a package version in the GitHub Advisory Database, or check the dependencies a branch adds before it merges |
| `dependabot` | Write or tune `dependabot.yml`, group updates, and drive Dependabot pull requests with its comment commands |
| `secret-scanning` | Configure secret scanning, push protection and custom patterns, resolve a blocked push, and triage secret alerts |
| `codeql` | Set up or fix CodeQL code scanning workflows, run the CodeQL CLI, and read SARIF output |
| `github-actions-hardening` | Review a workflow for script injection, privileged triggers, unpinned actions and over-scoped tokens |

`dependency-scanning` runs only when asked, and asks again before it downloads the Dependabot CLI
or audits a whole repository.

Install it from the `devantler-plugins` marketplace ([all tools](../../docs/installation.md)):

```sh
/plugin install github-security@devantler-plugins        # Claude Code
copilot plugin install github-security@devantler-plugins  # GitHub Copilot CLI
```

## The bundled MCP server

The plugin starts `github-ghas-tools`, GitHub's remote MCP server at
`https://api.githubcopilot.com/mcp/`, limited to the `code_security`, `secret_protection`,
`security_advisories` and `dependabot` toolsets. Every tool those toolsets expose is read-only:
listing and reading alerts and advisories, and `check_dependency_vulnerabilities`, which looks up
package versions in the GitHub Advisory Database. When an agent uses it, the repository owner and
name, and any package names and versions it checks, go to GitHub.

How the server signs in depends on the tool:

- **GitHub Copilot CLI and VS Code** sign in automatically with your Copilot session.
- **Claude Code** signs in with your GitHub CLI login. The plugin's
  [`scripts/github-mcp-headers.sh`](scripts/github-mcp-headers.sh) runs as the server's
  `headersHelper` and sends the token from `gh auth token`, because GitHub's sign-in service does
  not offer the automatic client registration Claude Code would otherwise use. Run `gh auth login`
  first. To use a narrower token instead, set `GITHUB_SECURITY_MCP_TOKEN` in the environment
  Claude Code starts in. If neither is available, Claude Code reports a failed connection for
  this server; the same alerts and advisories stay reachable through `gh api`.
- **Other tools** that do not run `headersHelper` need their own `Authorization: Bearer <token>`
  header for this server.

GitHub's Advanced Security plugin also requests the `run_secret_scanning` tool, which scans file
contents for secrets before you commit. GitHub's server rejects that request for a GitHub CLI
token, and asking for it makes the whole connection fail, so this plugin does not request it. The
`secret-scanning` skill still mentions that tool; it is available only through GitHub's own
Advanced Security plugin in Copilot.

## Licenses

The skills keep their upstream MIT licenses; see
[`resources/THIRD-PARTY-NOTICES.md`](resources/THIRD-PARTY-NOTICES.md). Version history is in the
[changelog](CHANGELOG.md).
