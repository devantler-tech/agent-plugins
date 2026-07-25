# ADR 0005 — Merge spend stewardship into the `automated-ai-engineer` entrypoint

- **Status:** Accepted
- **Date:** 2026-07-25
- **Deciders:** devantler-tech maintainer
- **Supersedes:** [ADR 0004](0004-consolidate-agentic-engineering.md) points 5 and 8, where FinOps was
  a separate consumer-owned role with its own schedule prompt

## Context

ADR 0004 kept FinOps as a separate role: a consumer-owned definition, its own desired-state role
entry, and its own thin schedule prompt resolving `AGENTS.md#The FinOps engineer`. The reasoning was
sound and is still sound — a deployment's financial boundaries, price sources, and protected-outcomes
floor are deployment facts that must not be copied into a public plugin.

What that split also produced, however, is a second writer over one portfolio. Running cost is not a
separate subject from the code that incurs it: rightsizing a workload, changing a node pool shape,
fixing a drifting price table, and retiring an orphaned volume are all ordinary engineering changes on
repositories the primary engineer already owns. Two roles over that surface means two schedules
selecting from overlapping work, two claim lanes that can converge on the same issue, and two
definitions carrying the same delivery, review, and merge discipline — while the deployment's writer
namespace table already had to record that both roles share one provider instance, because they were
never independent writers in the first place.

The separation also weakened the cost work itself. A cost pass that runs on its own schedule sees the
spend but not what the engineer is about to change; the engineer sees the change but not its cost.
The evidence, the floor check, and the fix belong in one loop.

## Decision

1. **Spend stewardship is a dimension of `automated-ai-engineer`, not a role.** The entrypoint absorbs
   the mandate: measure where the money goes, attribute it, raise value per unit cost, and never trade
   away a protected outcome.
2. **The generic money boundaries live in the plugin.** Value per unit cost over cost reduction, the
   protected-outcomes floor as a veto rather than a weight, "low utilisation is evidence about capacity,
   never about value", never move money, no personalised investment advice, no private financial data in
   a public artifact, read-only against production, and never weaken a measurement to improve a number.
   None of these is deployment-specific, and all of them are load-bearing safety properties, so they are
   stated once in the reviewed definition rather than re-derived per consumer.
3. **The deployment's money facts stay consumer-owned**, which preserves ADR 0004 point 8's actual
   intent. A new conditionally-required contract section, **`Spend contract`**, supplies the cost
   evidence sources and which are wired, the protected-outcomes floor and who may change it, the run
   procedure for a cost pass, the private channel a financial decision goes to, and the cost-pass
   cadence.
4. **Absent that section, the engineer fails closed on the cost dimension only.** It performs operate
   and advance work normally and does no spend analysis. It never infers a floor, a price, or a
   channel — an invented floor is how an agent optimises its way through something the maintainer
   cared about.
5. **Remove the separate role and schedule from the desired state**, and rename
   `requiredWhenFinOpsEnabled` to `requiredWhenSpendStewardshipEnabled`. The manifest validator
   rejects a resurrected `finops-engineer` role or schedule, so the old two-writer shape fails closed
   instead of being silently redeployed alongside the merged one.
6. **The validator pins the merged boundary to the entrypoint.** It asserts the definition carries the
   spend section, its conditional contract section, the never-move-money limit, and the
   no-private-financial-data-in-public limit. Merging a mandate into a larger definition is exactly
   where a boundary gets quietly dropped in a later edit; the guard makes that a CI failure.
7. **A cost finding is ordinary delivery work.** The engineer claims it, ships the pull request, and
   drives it to merge under the consumer's existing trust, review, and merge mechanics. Only the
   money-moving step — purchase, cancellation, plan change, commitment, transfer — routes to the
   maintainer, and that step is missing authority rather than a blocker on the surrounding engineering.
8. **Version 3.0.0.** Removing a role and schedule and renaming a validated schema key is a breaking
   migration for consumers that copied the version 2 desired state.

## Consequences

### Positive

- One writer, one claim lane, and one definition over one portfolio; cost stops being a parallel queue
  that can duplicate the engineer's work.
- A cost finding reaches merge through the delivery path the engineer already proves every run,
  instead of a second copy of that discipline.
- Cost evidence and the change that acts on it are available in the same loop.
- The money boundaries are reviewed in one public place and mechanically enforced, which is stronger
  than the same prose living only in each consumer's private definition.
- One fewer schedule to keep in sync with cadence.

### Costs and migration

- Consumers must retire the `finops-engineer` schedule and rename the contract section and
  desired-state key; the validator fails closed until they do.
- A stale copy of the version 2 desired state no longer validates.
- The engineer's definition is longer. This is the real cost of the merge, accepted because the
  alternative — a boundary summarised rather than stated — is how safety properties erode.
- Spend work now competes for the engineer's run budget with operate and advance work, so the cost
  pass is explicitly cadence-gated and ordered behind breakage and trusted-author pull requests.

## Rejected alternatives

- **Keep the separate FinOps role.** Rejected: it is the two-writer shape this decision removes, and
  the consumer contract already had to declare that the two roles share one provider instance.
- **Bundle a generic FinOps run-loop skill into the plugin.** Rejected for now: every bundled skill
  must carry upstream provenance from its own source repository, so a generic cost skill belongs in the
  skills upstream first. The run procedure stays consumer-owned and is resolved through the
  `Spend contract` section, which is also where the deployment's evidence wiring already lives.
- **Put the deployment's price sources, floor, or private channel in the plugin.** Rejected on ADR
  0004 point 8's original reasoning: those are volatile, deployment-specific, and in part sensitive.
- **Make the `Spend contract` section unconditionally required.** Rejected because it would stop a
  consumer that does not want cost work from using the engineer at all. Failing closed on one dimension
  is the correct granularity.
- **Let the engineer execute approved financial actions.** Rejected outright, and not a trade-off this
  merge is permitted to revisit. The boundary between an engineer that optimises spend and one that
  spends is the whole reason unattended operation is safe.
