# ADR 0004 — Consolidate the autonomous engineering system as `agentic-engineering`

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** devantler-tech maintainer
- **Supersedes:** [ADR 0002](0002-automated-ai-engineer-plugin-boundary.md) where it required a separate plugin identity

## Context

The marketplace has two adjacent bundles:

- `automated-ai-engineer` contains the actual autonomous engineering system: the engineer, read-only
  surveyor, meta-engineer, and the portfolio, product, and improvement workflows they use.
- `agentic-engineering` contains instruction-authoring and discovery skills alongside two
  provider-specific skills for an SDK and an instruction blueprint.

The distinction recorded in ADR 0002 was useful during extraction, but it no longer matches how the
portfolio is operated. The autonomous engineering system is the thing intended to drive every agent,
while the SDK-oriented material is not part of the current operating model. Keeping two installable
identities makes onboarding ambiguous and lets the generic role, supporting instructions, and schedule
bootstrap drift independently.

The deployment also needs a version-controlled, provider-neutral way to express desired state. Native
schedulers and agent registration remain runtime-specific, but the intent they reconcile can be a
portable document: canonical source, entrypoint, consumer contract, role boundaries, schedule source,
isolation, memory, permissions, model policy, and fail-closed onboarding steps.

## Decision

1. **`agentic-engineering` is the single plugin identity.** It is versioned as `2.0.0` because removing
   the `automated-ai-engineer` marketplace entry and changing the installed namespace is a breaking
   migration.
2. **The autonomous system is the plugin's center.** Move the `automated-ai-engineer`,
   `portfolio-surveyor`, and `agent-improver` agents plus `portfolio-maintenance`,
   `product-engineering`, `self-improvement`, and `agent-improvement` skills into
   `agentic-engineering`.
3. **Keep only relevant support skills from the earlier bundle.** Retain the provider-neutral
   `agent-instructions` and `find-skills` skills. Remove the SDK and provider-specific instruction
   blueprint skills.
4. **Retire the separate marketplace entry without an alias bundle.** A duplicate compatibility
   plugin would keep two names alive and recreate the drift this decision removes. Existing consumers
   migrate their installation and any qualified agent references to `agentic-engineering`.
5. **Ship a provider-neutral desired-state document.** The ancillary
   `resources/provider-neutral.desired-state.json` is copy-pasteable into a new assistant. It directs
   the runtime to reconcile its native plugin, roles, schedules, memory, permission, and model controls;
   it reports unsupported capabilities rather than inventing a weaker substitute. It carries separate
   thin prompts for the Automated AI Engineer and Agent Improver plugin entrypoints and for the
   consumer-owned FinOps Engineer definition.
6. **Keep the role/configuration split from ADR 0002.** Generic decision logic remains in the plugin.
   The consuming repository's canonical `AGENTS.md` remains the source for portfolio, trust, cadence,
   memory, maintainer channels, and optional meta-engineer authority. The scheduled dispatch is a thin
   pointer to those two reviewed sources, never another copy of the role.
7. **Refresh between runs, not during one.** A deployment loads the latest reviewed default-branch
   definition before starting a run and holds that definition stable until the run completes.
8. **FinOps stays consumer-owned.** Its schedule prompt resolves the role definition, run loop,
   lifestyle floor, evidence source, and cadence from the consumer's `AGENTS.md`; it does not copy
   financial boundaries or deployment-specific data into this public plugin.

## Consequences

### Positive

- One plugin answers both “what drives the agents?” and “what should a new runtime install?”
- The main bundle is smaller and aligned with the currently used operating model.
- Organization configuration remains declarative in Git, while runtime-local scheduler registration is
  reconciled from that source instead of becoming the source of truth.
- The desired-state document makes unsupported portability gaps explicit and testable.

### Costs and migration

- Existing `automated-ai-engineer` installs must be replaced with `agentic-engineering`.
- Qualified agent names change to the surviving plugin namespace; the `automated-ai-engineer` agent
  entrypoint name itself remains stable.
- Consumers of the removed SDK or instruction-blueprint skills must install their upstream skill
  independently if they still need it.
- The marketplace validator now owns an additional schema contract for ancillary desired-state files.

## Rejected alternatives

- **Keep both plugins and cross-reference them.** Rejected because onboarding still has two roots and
  changes can drift across releases.
- **Rename the agent entrypoint too.** Rejected because the entrypoint still accurately describes its
  role and retaining it reduces migration cost without retaining a duplicate plugin.
- **Store concrete schedules, repositories, accounts, or secrets in the desired-state document.**
  Rejected because those are consumer-owned, volatile, or sensitive facts. The manifest resolves them
  from the consumer contract and runtime.
- **Generate runtime-specific scheduler configuration in this repository.** Rejected because it would
  make one provider's control plane the canonical format and would still require UI or API
  reconciliation elsewhere.
