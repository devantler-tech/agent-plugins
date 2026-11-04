# `agentic-engineering`

The primary autonomous-engineering plugin for a repository portfolio, and the one install its agents
need. It carries the engineer that operates and advances the portfolio, the read-only surveyor that
gathers current state, and the meta-engineer that improves the system from measured evidence, plus
the [engineering toolbox](#the-engineering-toolbox) and [MCP servers](#bundled-mcp-servers) those
agents work with. The generic role lives here; each consumer supplies its organization-specific
configuration through its canonical `AGENTS.md`.

Released versions and the upgrade steps each breaking release needs are in the
[changelog](CHANGELOG.md). A plugin's version is its cache key, so an install that never moves off an
old version keeps serving that version's definitions — check what a deployment actually loaded before
assuming it has a change the changelog lists.

## What it includes

Four agents:

- **`agentic-engineer`** — the actor that runs the survey → select → act → report loop, operates
  the portfolio, finishes started work and pulls important Ready work within Kanban capacity, and — after explicit maintainer opt-in and a
  resolving **Spend contract** — stewards the portfolio's running cost in the same loop.
- **`portfolio-surveyor`** — a delegated, read-only agent that returns a compact current-state digest.
- **`agent-improver`** — a meta-engineer that evaluates deployed instances and improves their shared
  definition from evidence.
- **`flux-troubleshooter`** — a delegated, read-only Flux CD triage agent that diagnoses a failing
  live cluster through the bundled `flux-operator-mcp` server and hands the fix back.

Six core skills:

- **`portfolio-maintenance`** — the autonomous run loop and portfolio operating discipline.
- **`product-engineering`** — strategy, issue delivery, quality, performance, and secure product
  advancement.
- **`self-improvement`** — evidence-led improvement by an engineer reflecting on its own runs.
- **`agent-improvement`** — outside-in evaluation across the session corpus and deployed instances.
- **`agent-instructions`** — one canonical cross-tool instruction architecture with thin shims.
- **`find-skills`** — discovery of additional reusable skills when the current bundle is insufficient.

`self-improvement` and `agent-improvement` are complementary. The former lets one run bank and verify
its own learnings. The latter is an external observer that can identify recurrence, cross-instance
drift, and dispatch failures that no single run can see.

### Product documentation

The supplemental [`product-documentation`](skills/product-documentation/SKILL.md) skill helps the
Engineer build and maintain user documentation sites: practical tutorials, task guides, reference,
explanations and checks of the built and published result. It works with the product's existing
framework guidance, such as the bundled Svelte skill and documentation server. The Engineer loads it
when that work applies; it is not part of the three skills preloaded for every run.

### Matt Pocock's engineering techniques

Two supplemental skills are curated from [Matt Pocock's skills](https://github.com/mattpocock/skills).
They add focused discovery and prototyping techniques to the core
delivery workflow. Each complete skill directory retains its native `gh skill` source metadata and
supporting resources; normal upstream updates remain enabled.

| Skill | Use it for |
|---|---|
| [`grilling`](skills/grilling/SKILL.md) | Stress-test a plan through a decision-tree interview when the user asks to explore it. |
| [`prototype`](skills/prototype/SKILL.md) | Answer a design question with a throwaway logic demo or alternative UI layouts. |

Select a skill through the runtime's native skill picker or invocation mechanism. Where plugin
skills use qualified names, the name is `agentic-engineering:<skill>`; for example,
`agentic-engineering:grilling`. Both prototype guides are included.

These techniques supplement the engineer rather than introduce another operating contract. The
consumer's canonical `AGENTS.md`, existing authorization and core delivery rules govern repository
scope, privacy, tooling, delegation, issue handling, tests, review and merge.
Prototypes stay separate from production delivery and do not
waive its checks. Interview skills serve user-requested design discussions, not unattended dispatches.

The bundle excludes Matt's setup and Git hooks, tracker-specific triage/spec/implementation flows,
experimental skills and separate PR/review policies. Those would introduce competing configuration
or lifecycle conventions. Entry points whose upstream frontmatter is incompatible with this
marketplace's required skill-spec validator are also excluded; upstream skills are never rewritten
to bypass that gate.
`diagnosing-bugs` is also excluded: its Bash template has no adjacent self-test, which this
marketplace requires for bundled helpers. Its upstream tree is not modified to add one.
`tdd` is excluded because its review skill dependency is not bundled; `domain-modeling` is
excluded because its fixed documentation paths can conflict with consumer conventions.
`codebase-design` is deferred because its alternative-design guide assumes a root `GLOSSARY.md`
that consumers need not have. It can be reconsidered after a portable upstream version is available.

The imported material is Copyright (c) 2026 Matt Pocock and licensed under MIT. The complete upstream
copyright and permission notice is distributed in
[`resources/matt-pocock-LICENSE.txt`](resources/matt-pocock-LICENSE.txt); retain it when redistributing
these skills, including when copying individual directories. This is an independently curated
bundle and does not imply Matt Pocock's endorsement. When updating the imported skills, re-check the
upstream license and retain the applicable notice from the same source revision. Required package
validation resolves each imported skill's upstream ref, verifies its recorded tree and compares this
notice with LICENSE from that exact commit. A changed notice or incomplete upstream observation
refuses the update; a licensing change requires a reviewed curation update.

### The engineering toolbox

The skills the agents use to do the work itself. The Engineer loads one when its task matches; none
is preloaded for every run. Most are curated from their upstreams and keep updating from there;
`conventional-release`, `gitops-tenant-onboarding`, `ways-of-working` and the three `write-*` skills
are maintained here.

| Area | Skills |
|---|---|
| GitHub | `gh-cli`, `github-issues`, `gh-stack` (stacked pull requests), `github-actions-docs`, `github-actions-efficiency` |
| Code review (CodeRabbit) | `code-review` (a local review with the CodeRabbit CLI), `autofix` (work through CodeRabbit's review threads on a pull request) |
| Repository security | `dependency-scanning`, `dependabot`, `secret-scanning`, `codeql`, `github-actions-hardening`, `check-skills` (review a skill before installing it) |
| Library documentation | `context7-mcp` (current documentation for any library or framework, through the `context7` server) |
| Go | `golang-pro` |
| Kubernetes and GitOps | `gitops-cluster-debug`, `gitops-knowledge`, `gitops-tenant-onboarding`, `siderolabs` (Talos Linux and Omni) |
| Frontend (SvelteKit) | `svelte-core-bestpractices`, `frontend-design`, `web-design-guidelines` |
| Payments (Stripe) | `stripe-best-practices`, `stripe-docs`, `upgrade-stripe` |
| Engineering practices | `conventional-release`, `git-commit`, `refactor`, `test-driven-development`, `ways-of-working`, `write-contributing`, `write-docs-introduction`, `write-readme`, `architecture`, `debug`, `deploy-checklist`, `documentation`, `incident-response`, `standup`, `system-design`, `tech-debt`, `testing-strategy` |
| Design | `accessibility-review`, `design-critique`, `design-handoff`, `design-system`, `research-synthesis`, `user-research`, `ux-copy` |
| Product management | `competitive-brief`, `metrics-review`, `product-brainstorming`, `roadmap-update`, `sprint-planning`, `stakeholder-update`, `synthesize-research`, `write-spec` |
| Marketing | `brand-review`, `campaign-plan`, `content-creation`, `draft-content`, `email-sequence`, `performance-report`, `seo-audit` |
| Finance | `audit-support`, `close-management`, `financial-statements`, `journal-entry`, `journal-entry-prep`, `reconciliation`, `sox-testing`, `variance-analysis` |
| Productivity | `memory-management`, `start`, `task-management`, `update`, `workspace-conventions` (where their notes and tasks go) |
| Connectors | `connector-setup` (which official mail, calendar, LinkedIn or security connector to ask for) |

`dependency-scanning` runs only when asked, and asks again before it downloads the Dependabot CLI or
audits a whole repository. KSail has its own [`ksail`](../ksail/) plugin, made for KSail's users;
enable it alongside this one when your agents create or operate clusters with KSail.

`code-review` runs the [CodeRabbit CLI](https://www.coderabbit.ai/cli), so it needs `coderabbit`
installed and signed in (`coderabbit auth login`), and it sends the diff to CodeRabbit. It can
start on its own when the agent decides a review is needed, so keep it off repositories whose code
must not reach CodeRabbit. Its result is a local review: it is not a review on the pull request.
`autofix` needs `gh`, `git` and `jq`, and treats every review comment as a report to check, never
as instructions to run. CodeRabbit's
`code-reviewer` agent and `/coderabbit-review` command come only with CodeRabbit's own plugin, so
they are not bundled. `stripe-docs` reads Stripe's documentation through the
[Stripe CLI](https://docs.stripe.com/cli/install)'s `stripe docs` command. Stripe's skills that pay
other businesses, buy services or find businesses to pay (`stripe-pay`, `stripe-projects` and
`stripe-directory`) are not bundled, nor are its specialist Connect, Metronome and Stripe Apps
skills or its plugin's hooks; install [Stripe's plugin](https://docs.stripe.com/agents/plugin) for
those. Context7's `find-docs` and `context7-cli` skills are not bundled because they run the
`ctx7` CLI through `npx`; `context7-mcp` does the same lookups through the bundled server.

The design, product-management, marketing, finance and productivity skills, and the
`architecture` to `testing-strategy` engineering skills, come from the Engineering, Design,
Product Management, Marketing, Finance and Productivity plugins in
[`anthropics/knowledge-work-plugins`](https://github.com/anthropics/knowledge-work-plugins). Their
connectors (Asana, Atlassian, Linear, Notion, Slack, Figma, HubSpot, Snowflake and others) are not
bundled. The skills name them as `~~category` placeholders, such as `~~project tracker`, and work
with whichever server in that category the session has, or without one. Anthropic's Engineering
`code-review` skill is not bundled because CodeRabbit's `code-review` has the same name, and
Marketing's `competitive-brief` is not bundled because Product Management's has the same name. The
four productivity skills keep their state in `CLAUDE.md`, a `memory/` folder, `TASKS.md` and a
`dashboard.html` viewer. `workspace-conventions` sends that state to `AGENTS.md`, the agent's
native memory and the project's issue tracker instead, and the dashboard template is not bundled.
The finance skills prepare accounting work such as journal entries and reconciliations; they move
no money and give no investment advice. OpenAI's `check-skills` is the one skill from
[Codex Security](https://github.com/openai/codex-security) that works outside that plugin: its
other skills need the plugin's own server and files.

Many of these skills use the `argument-hint` and `user-invocable` frontmatter fields, which
Claude Code and VS Code read but the Agent Skills specification does not define. This marketplace's spec check accepts
exactly those two fields and still rejects every other unknown field; see
[Validation](../../docs/validation.md).

Mail, calendar, LinkedIn and Codex Security's cloud scans come from the providers' own connectors,
which a plugin cannot switch on: each needs the user's sign-in. In Codex, this plugin's
[`.codex-plugin/plugin.json`](.codex-plugin/plugin.json) offers iCloud Mail, iCloud Calendar,
LinkedIn and Codex Security Cloud as optional apps through its [`.app.json`](.app.json), so Codex
lists them with the plugin. Claude Code has no such field, so there `connector-setup` tells the
agents which connector to ask for, through the connector directory, and to say so when none
exists, as for iCloud in Claude today.

When the Engineer splits a change into dependent pull requests, the
[stacked pull requests guide](skills/product-engineering/references/stacked-pull-requests.md) decides
whether a stack pays off and governs how its layers are reviewed and merged. Where it differs from
the bundled `gh-stack` skill, it wins.

The license, copyright notice and license text of every third-party skill in this plugin are
recorded in [`resources/THIRD-PARTY-NOTICES.md`](resources/THIRD-PARTY-NOTICES.md).

## Bundled MCP servers

| Server | What it connects to | Needs |
|---|---|---|
| `aws-knowledge` | AWS's hosted knowledge server: AWS documentation, regional availability and AWS's own guidance, read-only | Nothing; it works without an AWS account |
| `cloudflare-docs` | Cloudflare's hosted documentation search: DNS, certificates, R2 and the rest of Cloudflare, read-only | Nothing; it is public |
| `context7` | Upstash's Context7: current documentation and code examples for libraries and frameworks, read-only | Nothing; it works without an account |
| `flux-operator-mcp` | A live cluster's Flux resources, read-only, for `gitops-cluster-debug` and `flux-troubleshooter` | The [`flux-operator-mcp`](https://fluxcd.control-plane.io/operator/mcp/) binary, a POSIX `sh`, and cluster access through `KUBECONFIG` or `~/.kube/config` |
| `github` | GitHub's everyday tools: repositories, issues, pull requests, Actions, labels and projects, read, and issue, label, comment, branch, new pull request and project writes; merging, pull request edits, reviews, file writes and workflow runs are excluded | A GitHub sign-in, below |
| `github-ghas-tools` | GitHub's read-only security tools | A GitHub sign-in, below |
| `kubescape` | A live cluster's Kubescape results, read-only: vulnerabilities, configuration scans, SBOMs, network and RBAC exposure | The [`kubescape`](https://kubescape.io/docs/install-cli/) CLI (v4 or later), a POSIX `sh`, and cluster access through `KUBECONFIG` or `~/.kube/config` |
| `siderolabs-docs` | Sidero Labs' search of the Talos Linux and Omni documentation | Nothing; it is public |
| `stripe` | Stripe's hosted server: Stripe documentation, reads and writes on your Stripe account, analytics, and money movement | A Stripe sign-in, below |
| `svelte` | The Svelte team's hosted server: Svelte 5 and SvelteKit documentation, the `svelte-autofixer` and playground links, all read-only | Nothing; it is public |
| `terraform-registry` | HashiCorp's Terraform server limited to its `registry` toolset: provider and module documentation from the public Terraform Registry, read-only | The [`terraform-mcp-server`](https://github.com/hashicorp/terraform-mcp-server) binary |

`flux-operator-mcp` talks only to your clusters. `kubescape` also downloads Kubescape's released
policy bundle from GitHub each time it starts, falling back to a local cache, and
`terraform-registry` runs locally but looks providers and modules up in the public Terraform
Registry. Every other server is
hosted by a third party, so every call to one, including a documentation search, reaches that
service. If your agents must not contact a third party, disable its server in your tool's MCP
settings; denying single tools does not stop the connection.

`kubescape` runs `kubescape mcpserver` from the Kubescape CLI, through the same `sh` wrapper as
the Flux server, so it reads every cluster in your kubeconfig the same way. Its tools read the
cluster and the results the in-cluster Kubescape operator stores. Its only write-shaped calls are
server-side dry-run patches, which change nothing; its remediation tool never applies a fix, and
its admission-policy tool only drafts YAML. Its stored results exist only on a cluster that runs
the Kubescape operator. `terraform-registry` needs no token in
the `registry` toolset; the plugin leaves HashiCorp's HCP Terraform and Terraform Enterprise
toolsets off. `cloudflare-docs` and `aws-knowledge` only search documentation. Install the two
local binaries with, for example, `brew install kubescape terraform-mcp-server`; until then each
reports a failed connection.

`svelte` is the Svelte team's official MCP server at `https://mcp.svelte.dev/mcp`, from
[`sveltejs/ai-tools`](https://github.com/sveltejs/ai-tools). The plugin uses the hosted server rather
than the `npx -y @sveltejs/mcp` command the Svelte plugin runs, so nothing is downloaded or executed
locally. The `svelte-autofixer` and playground tools send the code you pass them to Svelte's
service, and `playground-link` puts that code in the link it returns, so anyone who sees the link
can read the code; only pass code that may leave your machine. The Svelte plugin's
`svelte-code-writer` skill is not bundled because it drives the same tools through `npx`, and its
`svelte-mcp-feedback` skill is not bundled because it files reports with the Svelte team.

`context7` is Upstash's hosted [Context7](https://context7.com) server at
`https://mcp.context7.com/mcp`, the endpoint Context7's own plugin uses. It works without an
account, at Context7's anonymous rate limit, and the library names and questions an agent sends go
to Upstash.

`stripe` is Stripe's hosted MCP server at `https://mcp.stripe.com`, as Stripe's own plugin
configures it. It signs in through OAuth: in Claude Code, run `/mcp` and choose `stripe`. Stripe's
consent page lets you grant one or more live accounts or sandboxes, with separate permissions for
each, and you can revoke the session in Stripe's Dashboard. Until you sign in, the server reports
that it needs authentication and the rest keep working. Every tool is offered, including
`stripe_api_write`, which can call any Stripe API write such as refunds, invoices, payment links and
subscriptions, and the Treasury tools `send_money`, `transfer_money` and `convert_currency`. Stripe
asks for confirmation in its Dashboard before refunds and money transfers, but most writes run
without one. Grant only the accounts and permissions your agents need, a sandbox unless they must
read live data, and deny
`stripe_api_write` and the Treasury tools in your tool permissions if your agents must never change
your Stripe account. The Stripe skills work without the server.

A local server whose binary is missing reports a failed connection and leaves the rest working.
The Flux server starts with `--read-only`, so it can read, trace and diff but never apply, delete,
reconcile, suspend or resume; hand fixes to your GitOps delivery instead. `flux-operator-mcp`
refuses to start unless the `KUBECONFIG` environment variable is set, so the plugin starts it
through `sh`, which sets `KUBECONFIG` to `$HOME/.kube/config` when your environment leaves it
unset or empty and passes any non-empty value unchanged. It can read every cluster in that
kubeconfig, not only the current context: its read-only `set_kubeconfig_context` tool switches
between them, and it can read workload logs (Secret values are masked by default). Every session
that loads this plugin gets that read access, including unattended runs. To narrow it, point
`KUBECONFIG` at a file holding only the contexts the agents may read, or deny or disable the
server in your tool permissions. `siderolabs-docs` offers `submit_feedback`, which sends a
report to Sidero Labs, and `stripe` offers `send_stripe_feedback`, which sends one to Stripe; deny
them in your tool permissions if your agents must not file reports. The Svelte tools write
nothing, but their autofixer and playground tools send code to Svelte, so deny those too if no code
may leave your machine. `github` and `stripe` are the servers whose tools change things.

`github-ghas-tools` is GitHub's remote MCP server at its read-only endpoint,
`https://api.githubcopilot.com/mcp/readonly`, limited to the `code_security`, `secret_protection`,
`security_advisories` and `dependabot` toolsets — the server definition from GitHub's
[Advanced Security plugin](https://github.com/github/copilot-advanced-security-plugin). It also
sends `X-MCP-Readonly: true`, so GitHub offers only read tools: listing and reading alerts and
advisories, and `check_dependency_vulnerabilities`, which looks up package versions in the GitHub
Advisory Database. When an agent uses it, the repository owner and name, and any package names and
versions it checks, go to GitHub. Its URL differs from `github`'s on purpose: Claude Code loads
only the first of two plugin servers with the same URL, whatever their headers.

`github` is the same GitHub server at `https://api.githubcopilot.com/mcp/` with its everyday
toolsets instead: `context`, `repos`, `issues`, `pull_requests`, `users`, `actions`, `labels` and
`projects`, the tools the bundled `github-issues` skill uses. Its `X-MCP-Exclude-Tools` header
removes the tools that merge, edit or promote a pull request, write or resolve reviews, update a
pull request branch, create or fork repositories, write files and run workflows:
`merge_pull_request`, `update_pull_request`, `pull_request_review_write`,
`add_comment_to_pending_review`, `update_pull_request_branch`, `create_repository`,
`fork_repository`, `push_files`, `create_or_update_file`, `delete_file` and `actions_run_trigger`.
Do those through `gh` and git, where a consumer's merge, readiness, review, signing and repository
rules apply. What stays can still write as the signed-in account: issues and sub-issues (including
closing them), labels (including deleting them), comments and replies, branches, new pull requests
and project items. A consumer that guards any of those on the command line should deny the matching
tool as well. The security toolsets stay on the read-only `github-ghas-tools`, so
neither server repeats the other's tools.

Both servers sign in the same way, with the same token, depending on the tool:

- **GitHub Copilot CLI and VS Code** sign in automatically with your Copilot session. That they
  ignore the Claude-only `headersHelper` key is expected but not yet verified on each tool.
- **Claude Code** signs in through the plugin's
  [`scripts/github-mcp-headers.sh`](scripts/github-mcp-headers.sh), which runs as each server's
  `headersHelper`, because GitHub's sign-in service does not offer the automatic client registration
  Claude Code would otherwise use. It sends your GitHub CLI's github.com login
  (`gh auth token --hostname github.com`), so run `gh auth login --hostname github.com` first. To
  use a narrower token for both servers instead, write it to `github-token` in this plugin's data
  directory (`${CLAUDE_PLUGIN_DATA}`), which for an install from this marketplace is
  `plugins/data/agentic-engineering-devantler-plugins/github-token` under your Claude configuration
  directory (`${CLAUDE_CONFIG_DIR:-~/.claude}`). Once that file exists the helper never falls back to
  your CLI login: an unreadable, empty or malformed file, a dangling link or an unsearchable
  directory fails the connection instead. The file is found only on a Claude Code version that
  substitutes `${CLAUDE_PLUGIN_DATA}` in a plugin's `headersHelper` (2.1.317 does); on one that does
  not, the helper receives no data directory and uses your CLI login. Claude Code runs a plugin's
  helper without any credential-named environment variable, so a token in your environment is never
  used. If no token is available, Claude Code reports a failed connection for both servers; the
  same data stays reachable through `gh`. With a read-only token, `github`'s write tools fail when
  called.
- **Other tools** that do not run `headersHelper` need their own `Authorization: Bearer <token>`
  header for these servers.

GitHub's Advanced Security plugin also requests the `run_secret_scanning` tool, which scans file
contents for secrets before you commit. GitHub's server rejects that request for a GitHub CLI token,
and asking for it makes the whole connection fail, so this plugin does not request it. The
`secret-scanning` skill still mentions that tool; it is available only through GitHub's own Advanced
Security plugin in Copilot.

## Validation choices

The Engineer's [proportionate validation guidance](agents/agentic-engineer.agent.md#proportionate-validation)
requires a meaningful testing purpose and expected result before adding tests. It prefers applicable
official frameworks and established repository tools, rejects redundant harnesses around existing
test infrastructure, and records the limits of feasible validation while preserving required checks.

## Copy-paste onboarding

[`resources/provider-neutral.desired-state.json`](resources/provider-neutral.desired-state.json) is
the provider-neutral desired state for a new assistant. Copy the complete JSON document into the new
assistant while it is opened in the consumer repository. The embedded onboarding instruction tells it
to install or load this plugin, validate the consumer contract, map the roles and permissions onto its
native capabilities, reconcile two thin scheduled dispatches from `AGENTS.md`, and report any
capability it cannot safely implement.

For the improver, follow the [worked consumer setup](resources/agent-improver-onboarding.md).
It includes an illustrative contract, conservative approval boundaries, evidence-store bindings,
and the first-run and later-verification checks. Application discovery and native permission
enforcement must be observed on the chosen runtime before scheduling it.

The manifest exposes one provider-neutral bootstrap prompt for each scheduled role under
`spec.runtime.scheduler.schedules`:

- **`agentic-engineer`** loads this plugin's primary engineer entrypoint.
- **`agent-improver`** loads this plugin's meta-engineer entrypoint after verifying the additional
  definition-location and authority contract.

**Spend stewardship has no schedule of its own.** It is a dimension of the primary engineer rather
than a separate role, so the cost pass runs inside the engineer's loop on the consumer's declared
cadence. The generic mandate and its money boundaries — value per unit cost, the protected-outcomes
veto, never move money, no personalised investment advice, and no private financial data in a public
artifact — live in the entrypoint definition. The deployment's own money facts stay consumer-owned in
`AGENTS.md#Spend contract`, which is why the plugin stays portable without duplicating sensitive or
fast-changing details. See [ADR 0005](../../docs/adr/0005-merge-spend-stewardship-into-the-engineer.md).

The manifest deliberately contains no organization inventory, account identifiers, secrets, fixed
schedule, or provider-specific setup. Those facts remain in the consumer's version-controlled
`AGENTS.md`; the manifest points to them so improvements land in one canonical place and future runs
refresh the latest reviewed plugin definition before starting.

## Optional offline autonomy assessment

The [offline autonomy assessor](AUTONOMY.md) compares consumer-owned classifications and scoped
replacement, runtime and recovery reports. It is disabled by default, makes advisory recommendations
only and never grants execution or authenticates supplied evidence. Its packaged synthetic example
and copied-installation tests demonstrate that boundary. Native admission remains consumer-owned.

## Consumer contract

The consuming repository's canonical `AGENTS.md` must define five named sections. The agents and core
skills fail closed when any are absent:

- **Portfolio map** — repositories in scope and each product's `## Maintenance` card, including
  validate commands, labels, protected/generated files, roadmap home, and the standard
  **feature-flag mechanism** required for non-trivial feature work.
- **Trust gate** — trusted identities, reviewer-only identities, repository merge mechanics, and the
  **maintainer-PR driving** fact. `hands-off` (the default when it is absent) lets the engineer drive
  a PR under the maintainer's own login only when it created that PR and the maintainer has not
  taken it over interactively. `attribution-only` gives it every such PR under the deployment's own
  active-work rules, and uses the interactive-session marker only to tell whose comments are whose.
- **Cadence** — run frequency, run budget, and rotation intervals.
- **Memory** — durable-store location, schema, and cross-run cursors.
- **Maintainer channels** — active decision channels, the canonical AI-disclosure line, and the
  maintainer's interactive-session marker (the literal a PR body carries when it came from the
  maintainer's own hand-driven session, so the surveyor can tell that PR from the engineer's own).

The surveyor also reads **Writer namespaces** for cross-instance claim discovery. Deployments with
expiring claims must declare their lease duration and authoritative start/renewal timestamp source
there, or link a **Claim protocol** that supplies both. Missing policy makes a claimed candidate's
actionability unknown; claim-free candidates do not require an expiration policy.

Enabling `agent-improver` adds two required sections:

- **Agent definition locations** — every definition surface it may change and whether that surface is
  version-controlled or runtime-local.
- **Authority model** — the separate boundaries for tightening and loosening prose and enforcement
  guardrails.

Enabling the engineer's spend stewardship requires literal `true` in
`spec.roles["agentic-engineer"].spendStewardshipEnabled` and **Spend contract**, which names the
single effective desired-state document,
cost evidence sources and which are actually wired, the protected-outcomes floor and who may change
it, the run procedure for a cost pass, the private channel a financial decision goes to, and the
cadence a cost pass runs on. Disabled or unresolved, the engineer runs normally with the **cost dimension failed
closed** — it does no spend analysis rather than guessing a floor, a price, or a channel.

An optional **Inference routing** section resolves a consumer-owned policy for task classes,
model aliases, billing restrictions, runtime registrations, and experiments. The
[routing contract and evaluator](resources/inference-routing.md) describe its input, output, and
enforcement boundary. Model names belong in the consumer, never in portable agent frontmatter.

The `Memory` section must also name the scorecard and open verification-hypothesis store used by the
improvement loop. The role/configuration boundary remains the one established by
[ADR 0002](../../docs/adr/0002-automated-ai-engineer-plugin-boundary.md): portable decision logic lives
in this plugin; consumer-owned facts live in `AGENTS.md`.

The [surveyor coverage guide](../../docs/surveyor-contract-coverage.md) identifies the generic
structural guards, the checks that stay in the consumer, and separate model-behavior scenarios.

## Delivery ownership

Every write-capable role owns selected engineering work from claim through exact-head review and
merge. Discovery remains read-only, but once the primary engineer or the Agent Improver chooses an
implementable change, it does not stop at an issue, recommendation, or draft pull request. It follows
the consumer's **Trust gate**, branch-claim protocol, review gates, and merge mechanics until the work
lands. Issue-only handoff is reserved for a named external blocker or authority the consumer contract
genuinely withholds. A cost finding is no exception: the engineer drives the measurement, manifest, or
configuration pull request to merge itself, and routes only the purchase, cancellation, commitment, or
other money-moving step to the maintainer — that single step is missing authority, never a reason to
leave the surrounding engineering work undone.

## Improving the plugin

**A generic improvement belongs here, not in your own copy of the role.** Every deployment installs
the same role definitions, so a sharpened rule, a repaired procedure, or a blind spot one portfolio
closes is worth the same to every other portfolio — and an improvement kept local is one every other
consumer has to rediscover for itself. Contributions are welcome on that basis.

Route a change by asking what it is a fact about:

| The change describes… | It belongs… |
|---|---|
| **How to decide or act** — the run loop, a guardrail, a review or merge rule, a surveyor field, a bundled script, a decision threshold | **upstream, in this plugin** |
| **A deployment-owned fact** — which repositories are in scope, which logins are trusted, cadence numbers, memory locations, channels, product cards | **in the consumer's own `AGENTS.md`** |

The test is whether the change would have to be rewritten to install the role on a different
portfolio. If it would, it is configuration and stays with the consumer; if it would not, it is role
behaviour and every consumer benefits from it landing here. That is the boundary
[ADR 0002](../../docs/adr/0002-automated-ai-engineer-plugin-boundary.md) already sets, stated as a
contribution rule.

**A local copy of a plugin-authored definition is drift, not customisation.** A consumer-side fork or
overlay of an agent shipped here stops inheriting upstream fixes, grows the definition every dispatch
loads, and reads as current to any check that compares an install against its reviewed source. Where
an overlay is genuinely needed — a provider capability this plugin does not model yet — keep it to
that named delta and upstream the generic part, so the overlay can be retired rather than accumulate.

To send one:

1. Open an issue or pull request on
   [`devantler-tech/agent-plugins`](https://github.com/devantler-tech/agent-plugins) with the
   behaviour you changed and the evidence behind it — what a role did, what it should have done, and
   how often. Measured behaviour is what this repository reviews against; a preference is not
   evidence.
2. **Check where the file is authored before editing it.** The three `agents/*.agent.md` definitions,
   the desired-state resource, the bundled scripts, and this README are authored in this repository.
   The maintained first-party skills are authored here as well, without install provenance. An external skill names its upstream in `metadata.github-repo` and is re-synced automatically; send its changes to that owner.
3. Where a fix spans this plugin and a deployment, land the upstream change first, then move the
   consumer to the reviewed revision that carries it. Bumping the consumer first pins a revision that
   does not have the fix.
4. Keep guardrail changes one-directional. A tightening ships on evidence; a loosening ships alone,
   naming the protection removed and what now covers that risk.
5. Move the plugin version in the same pull request — a content change that leaves the version alone
   never reaches consumers that already installed it.

The bundled roles carry this routing themselves: the engineer sends a generic improvement upstream
instead of growing its own deployment's files, and the Agent Improver delivers the upstream change
before the consumer that points at it.

## Runtime guard note

The surveyor's read-only discipline is declared in its definition, but deployments should enforce the
same boundary in their permission layer. Scheduled instances should use fresh per-run worktrees, unique
branch namespaces, least privilege, and a non-interactive execution policy. The desired-state resource
records those requirements without assuming a particular runtime.

### Enforcing the boundary: `scripts/forge-readonly-guard.sh`

[`scripts/forge-readonly-guard.sh`](scripts/forge-readonly-guard.sh) is the decision procedure that
layer calls. It answers one question about one candidate command — is this provably a read against the
source forge — and it is tool-neutral: a Claude Code `PreToolUse` hook, a Codex approval guard, and a
plain wrapper all ask it the same way.

```sh
forge-readonly-guard.sh --command '<command>'   # exit 0 allow · 1 deny (prints `deny: <reason>`) · 2 usage
<command> | forge-readonly-guard.sh --stdin
```

`forge-readonly-guard.sh --command` is the whole portable contract. A runtime whose pre-execution
interface hands you the candidate command calls the guard directly and needs nothing else.

The wrapper [`scripts/surveyor-forge-readonly.sh`](scripts/surveyor-forge-readonly.sh) exists only for
runtimes that present the candidate command as structured JSON on stdin rather than as an argument. It
is not a second classifier and not a second policy: it reads `tool_input.command` and asks
`forge-readonly-guard.sh --command`. It is installed everywhere, like every other required runtime
asset; wire it in where that shape matches, and call the guard directly where it does not. A deployment that has installed neither, or has not wired one of them onto the surveyor
agent, fails closed: forge reads are `QUERY-UNKNOWN`.

#### The wiring is the consumer's, and it cannot be shipped from here

**A plugin cannot wire this onto the surveyor for you, and this plugin does not pretend to.** Two
mechanisms exist and neither reaches an agent-scoped hook from inside a plugin:

- **Plugin-wide hooks** (`hooks/hooks.json`, or inline in `plugin.json`) are auto-discovered for
  *every* agent in the plugin and cannot be scoped to one. A plugin-wide `Bash` matcher would deny the
  engineer's own write path, so this plugin deliberately ships no such file.
- **Agent-scoped hooks in agent frontmatter** are supported for project and user agents, but *not* for
  plugin-shipped ones: `hooks`, `mcpServers`, and `permissionMode` are unsupported in a plugin agent's
  frontmatter and are ignored when the agent is loaded from a plugin. Adding a `hooks:` block to
  `agents/portfolio-surveyor.agent.md` would therefore be silently inert — the appearance of
  enforcement with none of it.

So the enforcement is **consumer-side by construction**. A consumer that wants it registers the guard
at its own surveyor-only pre-execution point — for a runtime with agent frontmatter hooks, by taking
its own copy of the surveyor agent under the consumer's agent directory and adding the `PreToolUse`
`Bash` hook there. Keep the hook path out of desired-state JSON, which stays provider-neutral.

**Until a consumer does that, the deployment is incomplete for forge reads.** It must treat forge
reads as `QUERY-UNKNOWN` and must not permit them until it installs and registers a supported
surveyor-scoped read-only path. The wiring being consumer-side is a statement about *which layer
owns the mechanism* — it is not permission to run the surveyor unguarded, and the guard is not
optional defence in depth.

A consumer runtime that wires `gh` through the guard must also `export GH_TELEMETRY=0` (or `false`) in the process environment before any `gh` read. GitHub CLI 2.96.0 otherwise writes `gh/device-id` on a certified `gh api` GET. The guard denies every `gh` segment unless that export is already in the environment; putting `GH_TELEMETRY=0` on the command line is itself denied as an env-prefixed `gh`. The bundled `classify-default-branch-ci-runs.sh` and `count-unresolved-review-threads.sh` helpers export `GH_TELEMETRY=0` before their remote `gh api` reads so those compound reads stay allowed.

Because the guard denies by default, run your own deployment's survey vocabulary through it before
turning it on: a read it does not yet recognise fails closed, which is the intended direction but is
better discovered deliberately than mid-run.

The bundled compound reads are two helpers in remote mode, and no other bundled local program runs
under the guard:

- `scripts/classify-default-branch-ci-runs.sh` judges default-branch CI. The guard accepts only
  `--repo`, `--branch`, and a full `--head-sha`, and refuses the helper's offline `--input` mode.
  The helper rejects unrecognized outcomes, contradictory status/conclusion pairs, repeated run
  identities and invalid numeric identifiers before selecting the latest workflow result.
  Each selector is accepted once; repeated or empty values refuse before collection.
- `scripts/count-unresolved-review-threads.sh` supplies the surveyor's unresolved-thread count. The
  guard accepts only `--repo` and a positive `--pr`, and only when the helper runs alone: its
  verdict is its exit status (0 none, 1 some, 2 unknown), so a pipeline around it is denied.
  A complete count requires the requested repository and PR on every page, unique thread IDs,
  consistent totals and a pagination chain that ends with `hasNextPage=false`. Missing or
  contradictory evidence returns `UNKNOWN` (exit 2).

Both remote helpers bind their GitHub CLI reads to `github.com`, independently of `GH_HOST` in the
calling environment,
and require the bundled `scripts/json-stream.lib.sh` asset. Before semantic parsing they refuse
repeated decoded object keys across the complete retained JSON stream, including later pages.

Each has a provider-neutral desired-state entry pinning its plugin-relative path, reviewed SHA-256,
and executable requirement, and the guard accepts only the exact helper beside itself. Resolve the
guard and both helpers from the same installed, reviewed plugin directory. Preflight may supply a
helper's literal absolute path. Otherwise, one bare probe of the helper's file name through the
active guard is a denied discovery request: it executes nothing and returns `classifier-path-json:`
with a JSON string naming the guard's own executable sibling of that name. The adapter preserves
this record in its denial reason and stderr. Decode it as data, quote the decoded path as one
literal shell argument, and submit the remote-mode command through the same guard. Never evaluate
the record or use JSON double quotes as shell quoting. Missing JSON tooling, a missing executable,
or an absent, malformed, ambiguous, or unusable hint leaves that evidence `QUERY-UNKNOWN`; directory
searches and fallback roots are not part of discovery. Each helper captures its fixed paginated
read in memory, so these exceptions neither write an intermediate file nor permit an arbitrary local
executable.

**Three residues the guard cannot close from argv alone — the calling runtime must.** They are stated
here rather than left implicit, because a guard whose limits are undocumented gets trusted for things
it never claimed:

- **`core.pager`.** A surveyed repository can name a pager program, and git runs it only when
  standard output is a terminal. The guard refuses `--paginate` and allows `--no-pager`, but it
  cannot see whether a TTY is attached. **Run the guarded command non-interactively** (no TTY on
  stdout), which is already how a scheduled agent executes.
- **Parameter expansion.** A named expansion such as `$REPO` is allowed, so the word the shell builds
  depends on the environment the runtime provides. Positional and special parameters are refused
  precisely because they are removable, but named ones are a deliberate convenience. **Do not
  interpolate untrusted text into the environment** of the shell that runs a guarded command.
- **`GH_TELEMETRY`.** GitHub CLI's default telemetry writes `gh/device-id` before the API result
  exists. The guard denies any `gh` segment unless a disabling value (`0` or `false`) is already in
  the process environment; argv cannot carry it. **`export GH_TELEMETRY=0` before any `gh` read.**
  The bundled classifier does that before its own `gh` call. Git-only commands do not need it.
- **`GIT_NO_LAZY_FETCH`.** Partial clones can contact a configured transport during a local
  object read. **Export `GIT_NO_LAZY_FETCH=1` in the runtime process before guarded Git reads.**
  The guard requires that exact setting; a missing object then fails locally and stays unknown.

Tools that implement this marketplace's plugin layout auto-discover the `agents/` and `skills/`
directories. On surfaces without full plugin support, load the same canonical agent and skill files
from this repository; do not fork or paste copies into the consumer repository.
