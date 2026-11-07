# Privacy

The `agentic-engineering` plugin is a set of files that runs inside your own AI coding tool:
skills, agents, helper scripts and MCP server definitions. Devantler Tech runs no service for it.
The plugin has no backend and sends no telemetry, and Devantler Tech collects, stores, shares and
sells no personal data through it.

What the plugin's servers send, and to whom, is set out below. Your conversation, including what
those servers return, also goes to the model provider your AI tool uses, under that provider's
terms rather than this policy.

## On your machine

- **Skills and agents** are instructions your tool loads. Anything they do, such as running `gh`
  or `git`, runs through your tool's own tools and permissions.
- **GitHub sign-in (Claude Code only).**
  [`scripts/github-mcp-headers.sh`](scripts/github-mcp-headers.sh) reads a GitHub token from a
  `github-token` file you create in the plugin's data directory, or else from your GitHub CLI
  login. It hands the token to Claude Code, which sends it only to GitHub's MCP server as the
  `Authorization` header of the bundled `github` and `github-ghas-tools` servers. The script stores
  the token nowhere and never writes it to an error message or a log.
- **Cluster servers.** [`scripts/flux-operator-mcp.sh`](scripts/flux-operator-mcp.sh) and
  [`scripts/kubescape-mcp.sh`](scripts/kubescape-mcp.sh) start the Flux and Kubescape servers against
  the clusters in your kubeconfig. They talk to your clusters, and Kubescape also downloads its
  released policy bundle from GitHub each time it starts. Kubescape's scans would also send a
  version check to Kubescape's update service, carrying a cluster ID, the node count, the
  frameworks scanned and the client version. The launcher turns that check off by setting
  `KS_SKIP_UPDATE_CHECK=true`, unless you set that variable yourself.
- **Coroot (Claude Code only).** `coroot` connects to your own Coroot instance at the address in
  `COROOT_URL`. [`scripts/coroot-mcp-headers.sh`](scripts/coroot-mcp-headers.sh) reads that
  instance's address from `coroot-url` and a service-account API key from `coroot-api-key`, both
  files you create in the plugin's data directory. It hands the key to Claude Code as a bearer
  token only when Claude Code is connecting to that pinned address followed by `/mcp`. What the
  agents ask Coroot, and what it answers, stays between your tool and your Coroot.
- **Terraform Registry server.** `terraform-registry` runs locally and looks providers and modules
  up in HashiCorp's public Terraform Registry.

## Hosted servers

Every other bundled server is hosted by a third party. When an agent calls one of its tools, the
request goes to that service, together with what the agent passes it: a search, a repository or
package name, a version, or code. Each service handles it under its own privacy policy.

| Server | Operated by |
|---|---|
| `aws-knowledge` | Amazon Web Services |
| `cloudflare-docs` | Cloudflare |
| `context7` | Upstash |
| `github`, `github-ghas-tools` | GitHub |
| `siderolabs-docs` | Sidero Labs |
| `stripe` | Stripe, once you sign in to it |
| `svelte` | The Svelte maintainers |

In Codex, the plugin also offers optional app connectors for iCloud Mail, iCloud Calendar,
LinkedIn and Codex Security. None connects unless you choose it. Each then works under its
operator's terms.

## Your choices

- Disable any server in your tool's MCP settings to stop it contacting its service. Denying single
  tools does not stop the connection.
- The only files the plugin reads that you create are the optional `github-token`, `coroot-url`
  and `coroot-api-key` in its data directory. Delete them at any time. Claude Code removes that
  directory when you uninstall the plugin from the last place it is installed, unless you pass
  `--keep-data`.
- Uninstalling the plugin stops all of the above.

## Changes and contact

Changes to this policy ship with the plugin and are listed in [`CHANGELOG.md`](CHANGELOG.md).
Ask questions in the repository's
[issues](https://github.com/devantler-tech/agent-plugins/issues). Report a privacy or security
problem privately through the repository's
[security advisories](https://github.com/devantler-tech/agent-plugins/security/advisories/new).
