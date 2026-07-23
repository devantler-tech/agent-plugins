# `agentic-engineering`

The primary autonomous-engineering plugin for a repository portfolio. It carries the engineer that
operates and advances the portfolio, the read-only surveyor that gathers current state, and the
meta-engineer that improves the system from measured evidence. The generic role lives here; each
consumer supplies its organization-specific configuration through its canonical `AGENTS.md`.

Version 2 consolidates the former `automated-ai-engineer` plugin into `agentic-engineering`. The
autonomous engineering system is now the center of this plugin. From the earlier
`agentic-engineering` bundle it retains only the tool-neutral `agent-instructions` and `find-skills`
skills; the provider-specific SDK and instruction-blueprint skills were removed. See
[ADR 0004](../../docs/adr/0004-consolidate-agentic-engineering.md).

## Migrating from `automated-ai-engineer`

Version 2 deliberately replaces the old marketplace identity instead of keeping a second alias
bundle. The marketplace's append-only rename history maps `automated-ai-engineer` to
`agentic-engineering`. Claude Code 2.1.193 and later automatically migrates the persisted installed
plugin key when the marketplace refreshes; restart Claude Code or run `/reload-plugins`, then continue
with step 2 below.

For older Claude Code versions and runtimes that do not implement marketplace rename migration,
complete the plugin-name change manually before the next scheduled run:

1. Remove the installed `automated-ai-engineer` plugin with the runtime's native plugin control, then
   install `agentic-engineering@devantler-plugins` from `devantler-tech/agent-plugins`.
2. Change persisted qualified agent references from the `automated-ai-engineer` plugin namespace to
   `agentic-engineering`. The agent entrypoint itself remains `automated-ai-engineer`.
3. Copy the [provider-neutral desired state](resources/provider-neutral.desired-state.json) into the
   consumer workspace and reconcile its native agents and schedules. Preserve the consumer's
   canonical `AGENTS.md`; do not copy its organization-specific facts into this plugin.
4. Before re-enabling unattended writes, verify that the installed plugin reports version `2.0.0`,
   exposes `automated-ai-engineer`, `portfolio-surveyor`, and `agent-improver`, and that every
   plugin-backed schedule points to `plugin:agentic-engineering/<entrypoint>`. Run the required
   read-only preflight and record the installed source revision and any unsupported capability.

The migration is complete only after the old plugin identity no longer resolves in the runtime and
the read-only preflight loads the new namespace successfully.

## What it includes

Three agents:

- **`automated-ai-engineer`** — the actor that runs the survey → select → act → report loop, operates
  the portfolio, and advances the oldest actionable issue.
- **`portfolio-surveyor`** — a delegated, read-only agent that returns a compact current-state digest.
- **`agent-improver`** — a meta-engineer that evaluates deployed instances and improves their shared
  definition from evidence.

Six skills:

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

## Copy-paste onboarding

[`resources/provider-neutral.desired-state.json`](resources/provider-neutral.desired-state.json) is
the provider-neutral desired state for a new assistant. Copy the complete JSON document into the new
assistant while it is opened in the consumer repository. The embedded onboarding instruction tells it
to install or load this plugin, validate the consumer contract, map the roles and permissions onto its
native capabilities, reconcile three thin scheduled dispatches from `AGENTS.md`, and report any
capability it cannot safely implement.

The manifest exposes one provider-neutral bootstrap prompt for each scheduled role under
`spec.runtime.scheduler.schedules`:

- **`automated-ai-engineer`** loads this plugin's primary engineer entrypoint.
- **`agent-improver`** loads this plugin's meta-engineer entrypoint after verifying the additional
  definition-location and authority contract.
- **`finops-engineer`** resolves the consumer-owned FinOps definition, run loop, lifestyle floor, and
  evidence source through `AGENTS.md#The FinOps engineer` before invoking it.

FinOps remains consumer-owned because its financial boundaries and evidence wiring are deployment
facts. The schedule prompt is portable precisely because it points to those reviewed sources instead
of duplicating sensitive or fast-changing details.

The manifest deliberately contains no organization inventory, account identifiers, secrets, fixed
schedule, or provider-specific setup. Those facts remain in the consumer's version-controlled
`AGENTS.md`; the manifest points to them so improvements land in one canonical place and future runs
refresh the latest reviewed plugin definition before starting.

## Consumer contract

The consuming repository's canonical `AGENTS.md` must define five named sections. The agents and core
skills fail closed when any are absent:

- **Portfolio map** — repositories in scope and each product's `## Maintenance` card, including
  validate commands, labels, protected/generated files, roadmap home, and the standard
  **feature-flag mechanism** required for non-trivial feature work.
- **Trust gate** — trusted identities, reviewer-only identities, and repository merge mechanics.
- **Cadence** — run frequency, run budget, and rotation intervals.
- **Memory** — durable-store location, schema, and cross-run cursors.
- **Maintainer channels** — active decision channels and the canonical AI-disclosure line.

Enabling `agent-improver` adds two required sections:

- **Agent definition locations** — every definition surface it may change and whether that surface is
  version-controlled or runtime-local.
- **Authority model** — the separate boundaries for tightening and loosening prose and enforcement
  guardrails.

Enabling the FinOps schedule additionally requires **The FinOps engineer**, whose links resolve the
reviewed role definition, run loop, lifestyle floor, and evidence source.

The `Memory` section must also name the scorecard and open verification-hypothesis store used by the
improvement loop. The role/configuration boundary remains the one established by
[ADR 0002](../../docs/adr/0002-automated-ai-engineer-plugin-boundary.md): portable decision logic lives
in this plugin; consumer-owned facts live in `AGENTS.md`.

## Delivery ownership

Every write-capable role owns selected engineering work from claim through exact-head review and
merge. Discovery remains read-only, but once the primary engineer, Agent Improver, or FinOps Engineer
chooses an implementable change, it does not stop at an issue, recommendation, or draft pull request.
It follows the consumer's **Trust gate**, branch-claim protocol, review gates, and merge mechanics until
the work lands. Issue-only handoff is reserved for a named external blocker or authority the consumer
contract genuinely withholds. Financial actions remain outside the FinOps role: it drives the
engineering pull request to merge and routes only the purchase, cancellation, commitment, or other
money-moving step to the maintainer.

## Runtime guard note

The surveyor's read-only discipline is declared in its definition, but deployments should enforce the
same boundary in their permission layer. Scheduled instances should use fresh per-run worktrees, unique
branch namespaces, least privilege, and a non-interactive execution policy. The desired-state resource
records those requirements without assuming a particular runtime.

Tools that implement this marketplace's plugin layout auto-discover the `agents/` and `skills/`
directories. On surfaces without full plugin support, load the same canonical agent and skill files
from this repository; do not fork or paste copies into the consumer repository.
