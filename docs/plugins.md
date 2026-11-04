# Plugin catalogue

A **skill** teaches an assistant a task. An **agent** gives it a specialized role; an **MCP server** connects it to external tools through the Model Context Protocol.

[Install a plugin](installation.md) · [Back to the overview](../README.md)

| Plugin | Resources | Description |
|--------|-----------|-------------|
| [`agentic-engineering`](../plugins/agentic-engineering/) | `agent-improvement`, `agent-instructions`, `autofix`, `code-review`, `codeql`, `context7-mcp`, `conventional-release`, `dependabot`, `dependency-scanning`, `find-skills`, `frontend-design`, `gh-cli`, `gh-stack`, `git-commit`, `github-actions-docs`, `github-actions-efficiency`, `github-actions-hardening`, `github-issues`, `gitops-cluster-debug`, `gitops-knowledge`, `gitops-tenant-onboarding`, `golang-pro`, `grilling`, `portfolio-maintenance`, `product-documentation`, `product-engineering`, `prototype`, `refactor`, `secret-scanning`, `self-improvement`, `siderolabs`, `stripe-best-practices`, `stripe-docs`, `svelte-core-bestpractices`, `test-driven-development`, `upgrade-stripe`, `ways-of-working`, `web-design-guidelines`, `write-contributing`, `write-docs-introduction`, `write-readme` (skills) · `agent-improver`, `agentic-engineer`, `flux-troubleshooter`, `portfolio-surveyor` (agents) · `context7`, `flux-operator-mcp`, `github`, `github-ghas-tools`, `siderolabs-docs`, `stripe`, `svelte` (MCP servers) | The autonomous engineering system for a whole repository portfolio, and everything its agents need — engineer, read-only surveyor, meta-engineer and Flux troubleshooter agents; operating, product, spend and improvement workflows; GitHub, CodeRabbit review, security, library documentation, Go, Kubernetes, Flux, Talos, SvelteKit frontend, Stripe payments and engineering-practice skills; and the MCP servers they use. Configured by the consumer's `AGENTS.md` |
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
| `autofix` | `agentic-engineering` | coderabbitai/skills | MIT |
| `code-review` | `agentic-engineering` | coderabbitai/skills | MIT |
| `codeql` | `agentic-engineering` | github/awesome-copilot | MIT |
| `context7-mcp` | `agentic-engineering` | upstash/context7 | MIT |
| `conventional-release` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `dependabot` | `agentic-engineering` | github/awesome-copilot | MIT |
| `dependency-scanning` | `agentic-engineering` | github/copilot-advanced-security-plugin | MIT |
| `find-skills` | `agentic-engineering` | vercel-labs/skills | MIT |
| `frontend-design` | `agentic-engineering` | anthropics/skills | Apache-2.0 |
| `gh-cli` | `agentic-engineering` | github/awesome-copilot | MIT |
| `gh-stack` | `agentic-engineering` | github/gh-stack | MIT |
| `git-commit` | `agentic-engineering` | github/awesome-copilot | MIT |
| `github-actions-docs` | `agentic-engineering` | xixu-me/skills | MIT |
| `github-actions-efficiency` | `agentic-engineering` | github/awesome-copilot | MIT |
| `github-actions-hardening` | `agentic-engineering` | github/awesome-copilot | MIT |
| `github-issues` | `agentic-engineering` | github/awesome-copilot | MIT |
| `gitops-cluster-debug` | `agentic-engineering` | fluxcd/agent-skills | Apache-2.0 |
| `gitops-knowledge` | `agentic-engineering` | fluxcd/agent-skills | Apache-2.0 |
| `gitops-tenant-onboarding` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `golang-pro` | `agentic-engineering` | Jeffallan/claude-skills | MIT |
| `grilling` | `agentic-engineering` | mattpocock/skills | MIT |
| `ksail` | `ksail` | devantler-tech/ksail | PolyForm-Shield-1.0.0 |
| `portfolio-maintenance` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `product-documentation` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `product-engineering` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `prototype` | `agentic-engineering` | mattpocock/skills | MIT |
| `refactor` | `agentic-engineering` | github/awesome-copilot | MIT |
| `secret-scanning` | `agentic-engineering` | github/awesome-copilot | MIT |
| `self-improvement` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `siderolabs` | `agentic-engineering` | siderolabs/docs | Apache-2.0 |
| `stripe-best-practices` | `agentic-engineering` | stripe/ai | MIT |
| `stripe-docs` | `agentic-engineering` | stripe/ai | MIT |
| `svelte-core-bestpractices` | `agentic-engineering` | sveltejs/ai-tools | MIT |
| `test-driven-development` | `agentic-engineering` | obra/superpowers | MIT |
| `upgrade-stripe` | `agentic-engineering` | stripe/ai | MIT |
| `ways-of-working` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `web-design-guidelines` | `agentic-engineering` | vercel-labs/agent-skills | MIT |
| `write-contributing` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `write-docs-introduction` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `write-readme` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `allowed-stack-guardrail` | `vibe-coding` | devantler-tech/agent-plugins | Apache-2.0 |
| `jargon-free-voice` | `vibe-coding` | devantler-tech/agent-plugins | Apache-2.0 |
| `needs-stack-mapping` | `vibe-coding` | devantler-tech/agent-plugins | Apache-2.0 |
