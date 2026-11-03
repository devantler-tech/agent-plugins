# Plugin catalogue

A **skill** teaches an assistant a task. An **agent** gives it a specialized role; an **MCP server** connects it to external tools through the Model Context Protocol.

[Install a plugin](installation.md) · [Back to the overview](../README.md)

| Plugin | Resources | Description |
|--------|-----------|-------------|
| [`gitops-kubernetes`](../plugins/gitops-kubernetes/) | `gitops-cluster-debug`, `gitops-knowledge`, `gitops-tenant-onboarding` (skills) · `flux-operator-mcp` (MCP server) · `flux-troubleshooter` (agent) | Flux CD debugging, knowledge, and tenant onboarding — bundles the Flux MCP server and a read-only Flux troubleshooter agent for live-cluster debugging |
| [`github`](../plugins/github/) | `gh-cli`, `github-actions-docs`, `github-actions-efficiency`, `github-issues` | GitHub CLI, Actions docs and efficiency, and issue management |
| [`github-security`](../plugins/github-security/) | `codeql`, `dependabot`, `dependency-scanning`, `github-actions-hardening`, `secret-scanning` (skills) · `github-ghas-tools` (MCP server) | Dependabot and dependency vulnerability checks, secret scanning, CodeQL, and GitHub Actions hardening — bundles GitHub's read-only security MCP tools, signed in through your GitHub CLI login in Claude Code |
| [`agentic-engineering`](../plugins/agentic-engineering/) | `agent-improvement`, `agent-instructions`, `find-skills`, `grilling`, `portfolio-maintenance`, `product-documentation`, `product-engineering`, `prototype`, `self-improvement` (skills) · `agent-improver`, `agentic-engineer`, `portfolio-surveyor` (agents) | The autonomous engineering system for a whole repository portfolio — engineer, read-only surveyor, and meta-engineer agents, operating and improvement workflows, product documentation, and selected Matt Pocock discovery and prototyping techniques; configured by the consumer's `AGENTS.md` |
| [`go`](../plugins/go/) | `golang-pro` | Go best practices, concurrency, generics, interfaces, and testing |
| [`engineering-practices`](../plugins/engineering-practices/) | `conventional-release`, `git-commit`, `refactor`, `test-driven-development`, `ways-of-working`, `write-contributing`, `write-docs-introduction`, `write-readme` | Git commits, conventional releases, refactoring, TDD, engineering ways of working, and newcomer-facing documentation |
| [`frontend-design`](../plugins/frontend-design/) | `astro`, `frontend-design`, `web-design-guidelines` | Astro, frontend design, and web design guidelines |
| [`vibe-coding`](../plugins/vibe-coding/) | `needs-stack-mapping`, `allowed-stack-guardrail`, `jargon-free-voice` (skills) · `vibe-coding-companion` (agent) | Build a product by conversation alone — plain-language companion agent + guardrailed needs-to-stack skills for people with no technical background |
| [`ksail`](../plugins/ksail/) | `ksail` (skill) · `ksail` (MCP server) | Create and operate Kubernetes clusters and GitOps workloads with the KSail CLI — needs `ksail` on `PATH`; PolyForm Shield licensed |

## Skill licenses

Every bundled skill keeps its own license. The plugin bundles themselves are licensed under the
repository's [Apache-2.0 license](../LICENSE). A plugin that bundles third-party skills ships each
skill's copyright notice in its `resources/THIRD-PARTY-NOTICES.md`, with the license text or a link to the
license file the plugin ships; keep both when you copy or redistribute those skills.

| Skill | Plugin | Upstream | License |
|-------|--------|----------|---------|
| `agent-improvement` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `agent-instructions` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `find-skills` | `agentic-engineering` | vercel-labs/skills | MIT |
| `grilling` | `agentic-engineering` | mattpocock/skills | MIT |
| `portfolio-maintenance` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `product-documentation` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `product-engineering` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `prototype` | `agentic-engineering` | mattpocock/skills | MIT |
| `self-improvement` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `conventional-release` | `engineering-practices` | devantler-tech/agent-plugins | Apache-2.0 |
| `git-commit` | `engineering-practices` | github/awesome-copilot | MIT |
| `refactor` | `engineering-practices` | github/awesome-copilot | MIT |
| `test-driven-development` | `engineering-practices` | obra/superpowers | MIT |
| `ways-of-working` | `engineering-practices` | devantler-tech/agent-plugins | Apache-2.0 |
| `write-contributing` | `engineering-practices` | devantler-tech/agent-plugins | Apache-2.0 |
| `write-docs-introduction` | `engineering-practices` | devantler-tech/agent-plugins | Apache-2.0 |
| `write-readme` | `engineering-practices` | devantler-tech/agent-plugins | Apache-2.0 |
| `astro` | `frontend-design` | astrolicious/agent-skills | MIT |
| `frontend-design` | `frontend-design` | anthropics/skills | Apache-2.0 |
| `web-design-guidelines` | `frontend-design` | vercel-labs/agent-skills | MIT |
| `gh-cli` | `github` | github/awesome-copilot | MIT |
| `github-actions-docs` | `github` | xixu-me/skills | MIT |
| `github-actions-efficiency` | `github` | github/awesome-copilot | MIT |
| `github-issues` | `github` | github/awesome-copilot | MIT |
| `codeql` | `github-security` | github/awesome-copilot | MIT |
| `dependabot` | `github-security` | github/awesome-copilot | MIT |
| `dependency-scanning` | `github-security` | github/copilot-advanced-security-plugin | MIT |
| `github-actions-hardening` | `github-security` | github/awesome-copilot | MIT |
| `secret-scanning` | `github-security` | github/awesome-copilot | MIT |
| `gitops-cluster-debug` | `gitops-kubernetes` | fluxcd/agent-skills | Apache-2.0 |
| `gitops-knowledge` | `gitops-kubernetes` | fluxcd/agent-skills | Apache-2.0 |
| `gitops-tenant-onboarding` | `gitops-kubernetes` | devantler-tech/agent-plugins | Apache-2.0 |
| `golang-pro` | `go` | Jeffallan/claude-skills | MIT |
| `ksail` | `ksail` | devantler-tech/ksail | PolyForm-Shield-1.0.0 |
| `allowed-stack-guardrail` | `vibe-coding` | devantler-tech/agent-plugins | Apache-2.0 |
| `jargon-free-voice` | `vibe-coding` | devantler-tech/agent-plugins | Apache-2.0 |
| `needs-stack-mapping` | `vibe-coding` | devantler-tech/agent-plugins | Apache-2.0 |
