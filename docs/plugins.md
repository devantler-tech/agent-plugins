# Plugin catalogue

A **skill** teaches an assistant a task. An **agent** gives it a specialized role; an **MCP server** connects it to external tools through the Model Context Protocol.

[Install a plugin](installation.md) · [Back to the overview](../README.md)

| Plugin | Resources | Description |
|--------|-----------|-------------|
| [`agentic-engineering`](../plugins/agentic-engineering/) | `accessibility-review`, `agent-improvement`, `agent-instructions`, `application-security`, `architecture`, `audit-support`, `autofix`, `brand-review`, `campaign-plan`, `check-skills`, `close-management`, `code-review`, `codeql`, `competitive-brief`, `connector-setup`, `content-creation`, `context7-mcp`, `conventional-release`, `danish-business-rules`, `debug`, `dependabot`, `dependency-scanning`, `deploy-checklist`, `design-critique`, `design-handoff`, `design-system`, `documentation`, `draft-content`, `email-sequence`, `financial-statements`, `find-skills`, `frontend-design`, `gh-cli`, `gh-stack`, `git-commit`, `github-actions-docs`, `github-actions-efficiency`, `github-actions-hardening`, `github-issues`, `gitops-cluster-debug`, `gitops-knowledge`, `gitops-tenant-onboarding`, `golang-pro`, `grilling`, `incident-response`, `journal-entry`, `journal-entry-prep`, `memory-management`, `metrics-review`, `performance-report`, `portfolio-maintenance`, `privacy-engineering`, `product-brainstorming`, `product-documentation`, `product-engineering`, `prometheus`, `promql`, `prototype`, `reconciliation`, `refactor`, `research-synthesis`, `roadmap-update`, `secret-scanning`, `self-improvement`, `seo-audit`, `siderolabs`, `skill-lifecycle`, `sox-testing`, `sprint-planning`, `stakeholder-update`, `standup`, `start`, `stripe-best-practices`, `stripe-docs`, `svelte-core-bestpractices`, `synthesize-research`, `system-design`, `task-management`, `tech-debt`, `test-driven-development`, `testing-strategy`, `update`, `upgrade-stripe`, `user-research`, `ux-copy`, `variance-analysis`, `ways-of-working`, `web-design-guidelines`, `workspace-conventions`, `write-contributing`, `write-docs-introduction`, `write-readme`, `write-spec` (skills) · `agent-improver`, `agentic-engineer`, `flux-troubleshooter`, `portfolio-surveyor` (agents) · `aws-knowledge`, `cloudflare-docs`, `context7`, `coroot`, `flux-operator-mcp`, `github`, `github-ghas-tools`, `kubescape`, `numina`, `siderolabs-docs`, `stripe`, `svelte`, `terraform-registry` (MCP servers) | The autonomous engineering system for a whole repository portfolio, and everything its agents need — engineer, read-only surveyor, meta-engineer and Flux troubleshooter agents; operating, product, spend and improvement workflows; GitHub, CodeRabbit review, security, library documentation, Go, Kubernetes, Flux, Talos, SvelteKit frontend, Stripe payments, engineering-practice, design, product-management, marketing, finance and productivity skills; and the MCP servers they use. Configured by the consumer's `AGENTS.md` |
| [`vibe-coding`](../plugins/vibe-coding/) | `needs-stack-mapping`, `allowed-stack-guardrail`, `jargon-free-voice` (skills) · `vibe-coding-companion` (agent) | Build a product by conversation alone — plain-language companion agent + guardrailed needs-to-stack skills for people with no technical background |
| [`ksail`](../plugins/ksail/) | `ksail` (skill) · `ksail` (MCP server) | Create and operate Kubernetes clusters and GitOps workloads with the KSail CLI — needs `ksail` on `PATH`; PolyForm Shield licensed |

## Skill licenses

Every bundled skill keeps its own license. The plugin bundles themselves are licensed under the
repository's [Apache-2.0 license](../LICENSE). A plugin that bundles third-party skills ships each
skill's copyright notice in its `resources/THIRD-PARTY-NOTICES.md`, with the license text or a link to the
license file the plugin ships; keep both when you copy or redistribute those skills.

| Skill | Plugin | Upstream | License |
|-------|--------|----------|---------|
| `accessibility-review` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `agent-improvement` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `agent-instructions` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `application-security` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `architecture` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `audit-support` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `autofix` | `agentic-engineering` | coderabbitai/skills | MIT |
| `brand-review` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `campaign-plan` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `check-skills` | `agentic-engineering` | openai/codex-security | Apache-2.0 |
| `close-management` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `code-review` | `agentic-engineering` | coderabbitai/skills | MIT |
| `codeql` | `agentic-engineering` | github/awesome-copilot | MIT |
| `competitive-brief` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `connector-setup` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `content-creation` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `context7-mcp` | `agentic-engineering` | upstash/context7 | MIT |
| `conventional-release` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `danish-business-rules` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `debug` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `dependabot` | `agentic-engineering` | github/awesome-copilot | MIT |
| `dependency-scanning` | `agentic-engineering` | github/copilot-advanced-security-plugin | MIT |
| `deploy-checklist` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `design-critique` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `design-handoff` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `design-system` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `documentation` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `draft-content` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `email-sequence` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `financial-statements` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
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
| `incident-response` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `journal-entry-prep` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `journal-entry` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `ksail` | `ksail` | devantler-tech/ksail | PolyForm-Shield-1.0.0 |
| `memory-management` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `metrics-review` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `performance-report` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `portfolio-maintenance` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `privacy-engineering` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `product-brainstorming` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `product-documentation` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `product-engineering` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `prometheus` | `agentic-engineering` | grafana/skills | Apache-2.0 |
| `promql` | `agentic-engineering` | grafana/skills | Apache-2.0 |
| `prototype` | `agentic-engineering` | mattpocock/skills | MIT |
| `reconciliation` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `refactor` | `agentic-engineering` | github/awesome-copilot | MIT |
| `research-synthesis` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `roadmap-update` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `secret-scanning` | `agentic-engineering` | github/awesome-copilot | MIT |
| `self-improvement` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `seo-audit` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `siderolabs` | `agentic-engineering` | siderolabs/docs | Apache-2.0 |
| `skill-lifecycle` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `sox-testing` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `sprint-planning` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `stakeholder-update` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `standup` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `start` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `stripe-best-practices` | `agentic-engineering` | stripe/ai | MIT |
| `stripe-docs` | `agentic-engineering` | stripe/ai | MIT |
| `svelte-core-bestpractices` | `agentic-engineering` | sveltejs/ai-tools | MIT |
| `synthesize-research` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `system-design` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `task-management` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `tech-debt` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `test-driven-development` | `agentic-engineering` | obra/superpowers | MIT |
| `testing-strategy` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `update` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `upgrade-stripe` | `agentic-engineering` | stripe/ai | MIT |
| `user-research` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `ux-copy` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `variance-analysis` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `ways-of-working` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `web-design-guidelines` | `agentic-engineering` | vercel-labs/agent-skills | MIT |
| `workspace-conventions` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `write-contributing` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `write-docs-introduction` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `write-readme` | `agentic-engineering` | devantler-tech/agent-plugins | Apache-2.0 |
| `write-spec` | `agentic-engineering` | anthropics/knowledge-work-plugins | Apache-2.0 |
| `allowed-stack-guardrail` | `vibe-coding` | devantler-tech/agent-plugins | Apache-2.0 |
| `jargon-free-voice` | `vibe-coding` | devantler-tech/agent-plugins | Apache-2.0 |
| `needs-stack-mapping` | `vibe-coding` | devantler-tech/agent-plugins | Apache-2.0 |
