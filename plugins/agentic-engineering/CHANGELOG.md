# Changelog — `agentic-engineering`

Every released version of this plugin, newest first, with the upgrade steps each breaking release
needs. The [plugin README](README.md) describes the plugin as it is today; its history and its
version-to-version upgrade paths live here.

A plugin's **version is its cache key** — runtimes cache plugins by
`<marketplace>/<plugin>/<version>`, so an install that never moves off an old version keeps serving
that version's definitions with no error and no drift signal. Confirm which version a deployment
actually loaded before assuming it has a change listed below.

Only versions that reached `main` are listed; a version number bumped in a pull request that was
superseded before merge was never published and does not appear.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the plugin follows
[semantic versioning](https://semver.org/spec/v2.0.0.html).

**Crossing a breaking release?** Apply the upgrade sections in ascending order —
[2.0.0](#upgrading-to-200) → [3.0.0](#upgrading-to-300) → [4.0.0](#upgrading-to-400) →
[5.0.0](#upgrading-to-500) — and complete every one that lies between the installed version and the
new one before re-enabling unattended writes. Stopping early resumes writes with the retired FinOps
schedule still armed, or with a schedule pointing at an entrypoint that no longer resolves.

## 5.5.2 — 2026-09-25

**Changed** — sync `portfolio-maintenance` from `https://github.com/devantler-tech/agent-skills` at `refs/tags/v1.17.0`.

## 5.5.1 — 2026-09-25

**Fixed** — the surveyor no longer reports the engineer's own review findings as maintainer
instructions. A review round puts its disclosure on the review body and not on each inline comment,
so the surveyor now attributes an inline review comment by the review it belongs to. Only a top-level
comment inherits that attribution: a reply is judged on its own, so the maintainer's reply inside a
thread the engineer opened still reaches the orchestrator, as does any comment under an undisclosed
review.
([devantler-tech/monorepo#2835](https://github.com/devantler-tech/monorepo/issues/2835))

## 5.5.0 — 2026-09-25

**Added** — the **Trust gate** can declare a **maintainer-PR driving** fact, `hands-off` or
`attribution-only`, and the engineer reads it before updating, rebasing, pushing to, promoting,
merging or closing a PR under the maintainer's own login.

- `hands-off` is the default when the fact is absent or unreadable. The engineer drives such a PR
  only when it created that PR **and** the body carries no interactive-session marker, so a PR the
  maintainer took over interactively is no longer driven just because the engineer opened it.
- `attribution-only` gives the engineer every such PR under the deployment's own active-work rules.
  The creation record and the marker then only decide whose comments are whose, and an actionable
  maintainer comment on a PR the engineer did not create stays a named blocker until it is resolved.

The surveyor's `disclosure` rule now names the same fact, so neither definition reads as settling
the question alone. **A deployment that already lets the engineer drive every PR in its portfolio
should declare `attribution-only`**; without it, the engineer leaves interactive PRs alone.
([#201](https://github.com/devantler-tech/agent-plugins/issues/201))

## 5.4.0 — 2026-09-25

**Added** — the Agentic Engineer's remote-wait rule now covers the waits it used to leave open. A
sleep-and-re-query loop moved into a backgrounded or detached command is still a busy-wait and counts
as the run's one watcher. A watcher whose completion re-invokes the session keeps that session open,
so the run must stop it before ending, or not arm it when nothing depends on it. The engineer never
arms a watcher and then ends its turn with nothing else to do: it either works on something else
while the watcher runs or ends the run and leaves the target to the next invocation.
([devantler-tech/monorepo#3003](https://github.com/devantler-tech/monorepo/issues/3003))

## 5.3.1 — 2026-09-25

**Changed** — sync `product-engineering` from `https://github.com/devantler-tech/agent-skills` at `refs/tags/v1.14.0`.

## 5.3.0 — 2026-09-24

**Added** — the bundled `agent-improvement` skill moves to upstream `v1.13.0`, and the Agent Improver now
scores prioritization and flow on every run, separately from throughput. It counts easy,
substantive and unclassified work, and records how old the oldest actionable issue was whenever easier
work was chosen instead. The entrypoint's scorecard lists the new parameter, and a reference and an
optional offline calculator (`measure-flow.jq`) describe the measurement.

## 5.2.4 — 2026-09-24

**Docs** — the plugin README gives a worked onboarding for the Agent Improver.
([#240](https://github.com/devantler-tech/agent-plugins/pull/240))

## 5.2.3 — 2026-09-23

**Fixed** — the surveyor copies every branch name, head SHA and lane prefix from the values it read
for a PR, and writes `unknown` when it did not read one. It no longer builds a branch name from the
consumer's naming convention, which had attributed another lane's PR to the orchestrator.
([devantler-tech/monorepo#2739](https://github.com/devantler-tech/monorepo/issues/2739))

## 5.2.2 — 2026-09-23

**Fixed** — onboarding installs `scripts/surveyor-forge-readonly.sh` with every other required runtime
asset and makes only its wiring conditional, so a runtime that passes commands as arguments no longer
omits a file the desired state requires. ([#161](https://github.com/devantler-tech/agent-plugins/issues/161))

## 5.2.1 — 2026-09-22

**Fixed** — the surveyor takes its unresolved-review-thread count from a bundled helper that reports
unknown, never zero, when a read fails or stops short of every page; the read-only guard admits that
helper only when it runs alone. Deployments that load runtime assets individually must also install
`scripts/count-unresolved-review-threads.sh`. ([#235](https://github.com/devantler-tech/agent-plugins/pull/235))

## 5.2.0 — 2026-09-22

**Changed** — the plugin README describes the plugin as it is; released versions and the upgrade
steps for each breaking release moved into this changelog.
([#234](https://github.com/devantler-tech/agent-plugins/pull/234))

**Added** — both write-capable roles route a generic improvement to the upstream that authors the
definition rather than into a consumer's own copy of it, and the README states the same routing for
people, with how to send one.
([#234](https://github.com/devantler-tech/agent-plugins/pull/234))

## 5.1.8 — 2026-09-21

**Fixed** — fail closed when an issue row has no issueType key. ([#230](https://github.com/devantler-tech/agent-plugins/pull/230))

## 5.1.7 — 2026-09-21

**Fixed** — keep issue aggregation inside jq. ([#228](https://github.com/devantler-tech/agent-plugins/pull/228))

## 5.1.6 — 2026-09-20

**Fixed** — keep workflow log bodies out of digests. ([#226](https://github.com/devantler-tech/agent-plugins/pull/226))

## 5.1.5 — 2026-09-19

**Fixed** — define classifier output contract. ([#222](https://github.com/devantler-tech/agent-plugins/pull/222))

## 5.1.4 — 2026-09-17

**Fixed** — report GitHub-managed PR check failures as managed-failing. ([#219](https://github.com/devantler-tech/agent-plugins/pull/219))

## 5.1.3 — 2026-09-16

**Changed** — update agent skills. ([#216](https://github.com/devantler-tech/agent-plugins/pull/216))

## 5.1.2 — 2026-09-15

**Fixed** — let the deployment decide whether external PRs may be merged. ([#215](https://github.com/devantler-tech/agent-plugins/pull/215))

## 5.1.1 — 2026-09-15

**Fixed** — fail closed on stale CI runs.

## 5.1.0 — 2026-09-12

**Added** — evaluate subscription routing policy explicitly. ([#210](https://github.com/devantler-tech/agent-plugins/pull/210))

## 5.0.4 — 2026-09-12

**Changed** — update agent skills. ([#211](https://github.com/devantler-tech/agent-plugins/pull/211))

## 5.0.3 — 2026-09-09

**Changed** — update agent skills. ([#208](https://github.com/devantler-tech/agent-plugins/pull/208))

## 5.0.2 — 2026-09-06

**Changed** — guard surveyor review contracts upstream. ([#206](https://github.com/devantler-tech/agent-plugins/pull/206))

## 5.0.1 — 2026-09-06

**Fixed** — expose the guarded classifier path. ([#205](https://github.com/devantler-tech/agent-plugins/pull/205))

## 5.0.0 — 2026-09-06

**Changed (breaking)** — spend stewardship is explicitly opt-in and default-off. ([#204](https://github.com/devantler-tech/agent-plugins/pull/204))

The desired-state schema requires the boolean `spec.roles["agentic-engineer"].spendStewardshipEnabled`.
The presence of a complete Spend contract does not opt a deployment in. Older documents fail
validation, and the engineer treats missing or malformed enablement as disabled while continuing
ordinary engineering. See
[ADR 0007](../../docs/adr/0007-explicit-spend-enablement.md).

### Upgrading to 5.0.0

1. Refresh the complete desired-state document from the reviewed plugin revision, including its
   entrypoint digest and scheduler pointers. Keep the shipped flag `false` unless the maintainer
   explicitly enables spend stewardship.
2. Declare the path to one full effective desired-state JSON document in the consumer's `AGENTS.md`
   **Spend contract**. That document supplies the flag for every lane. If the consumer keeps a
   byte-identical upstream mirror, retain it and declare a separate full effective document through
   its native configuration; do not edit the mirror or invent a partial-override merge.
3. Reconcile the native scheduler from the updated pointers and verify preflight reports the
   effective document, boolean value, and any unresolved Spend contract prerequisites. Keep a
   disabled deployment disabled during reconciliation.

Without a declared document, preflight uses the shipped `false` default. A declared document that
cannot be read or validated also disables spend and reports the gap. Resolve the document and flag
once per run; never search unrelated settings for an enabling value or switch sources mid-run.

Only the maintainer may set the flag to literal `true`. This permits spend analysis and decisions
only when the Spend contract also resolves; it does not bypass the private decision channel,
protected-outcomes floor, or authority boundaries. Setting it back to `false` disables the cost
dimension on the next preflight. There is no additional spend schedule.

## 4.4.29 — 2026-09-06

**Fixed** — report a three-valued disclosure hint matched anywhere in the body. ([#194](https://github.com/devantler-tech/agent-plugins/pull/194))

## 4.4.26 — 2026-09-06

**Fixed** — classify a flag-shaped word a value flag consumes. ([#198](https://github.com/devantler-tech/agent-plugins/pull/198))

## 4.4.25 — 2026-09-05

**Fixed** — forbid transferring a gh --json field name from a REST or GraphQL surface. ([#199](https://github.com/devantler-tech/agent-plugins/pull/199))

## 4.4.24 — 2026-09-05

**Fixed** — state the CI classifier's flag-form argument shape. ([#197](https://github.com/devantler-tech/agent-plugins/pull/197))

## 4.4.23 — 2026-09-05

**Fixed** — require selection evidence before survey completion. ([#193](https://github.com/devantler-tech/agent-plugins/pull/193))

## 4.4.22 — 2026-09-04

**Fixed** — read blockedBy connections. ([#188](https://github.com/devantler-tech/agent-plugins/pull/188))

## 4.4.21 — 2026-09-04

**Fixed** — admit bundled short flags whose every component is allowlisted. ([#187](https://github.com/devantler-tech/agent-plugins/pull/187))

## 4.4.20 — 2026-09-03

**Changed** — update agent skills. ([#185](https://github.com/devantler-tech/agent-plugins/pull/185))

## 4.4.19 — 2026-09-02

**Fixed** — bump version for synced skills. ([#183](https://github.com/devantler-tech/agent-plugins/pull/183))

## 4.4.18 — 2026-09-01

**Fixed** — teach the surveyor the guard's admitted call shape. ([#182](https://github.com/devantler-tech/agent-plugins/pull/182))

## 4.4.17 — 2026-09-01

**Fixed** — validate Surveyor JSON fields at source. ([#177](https://github.com/devantler-tech/agent-plugins/pull/177))

## 4.4.16 — 2026-08-28

**Fixed** — admit consumer-declared stdin-only classifiers. ([#173](https://github.com/devantler-tech/agent-plugins/pull/173))

## 4.4.15 — 2026-08-27

**Fixed** — admit stderr redirection that creates no file. ([#171](https://github.com/devantler-tech/agent-plugins/pull/171))

## 4.4.14 — 2026-08-27

**Fixed** — stop a credential entering the agent's own transcript. ([#170](https://github.com/devantler-tech/agent-plugins/pull/170))

## 4.4.13 — 2026-08-25

**Fixed** — align git status with the read-only guard. ([#160](https://github.com/devantler-tech/agent-plugins/pull/160))

## 4.4.12 — 2026-08-24

**Changed** — name the environment prerequisite the read-only guard enforces. ([#159](https://github.com/devantler-tech/agent-plugins/pull/159))

## 4.4.11 — 2026-08-24

**Security** — scope the surveyor forge guard by agent. ([#158](https://github.com/devantler-tech/agent-plugins/pull/158))

## 4.4.10 — 2026-08-24

**Changed** — update agent skills. ([#157](https://github.com/devantler-tech/agent-plugins/pull/157))

## 4.4.9 — 2026-08-23

**Fixed** — reject write flags placed before the gh subcommand. ([#156](https://github.com/devantler-tech/agent-plugins/pull/156))

## 4.4.8 — 2026-08-21

**Fixed** — withhold only the affected repository's residual on a cap. ([#154](https://github.com/devantler-tech/agent-plugins/pull/154))

## 4.4.7 — 2026-08-21

**Fixed** — require the untyped residual's two operands to cover one population. ([#153](https://github.com/devantler-tech/agent-plugins/pull/153))

## 4.4.4 — 2026-08-21

**Fixed** — require GH_TELEMETRY=0 before certified gh reads. ([#150](https://github.com/devantler-tech/agent-plugins/pull/150))

## 4.4.3 — 2026-08-21

**Fixed** — require the forge-readonly guard on the surveyor. ([#149](https://github.com/devantler-tech/agent-plugins/pull/149))

## 4.4.2 — 2026-08-20

**Fixed** — allow the two read-only search filters the surveyor uses. ([#148](https://github.com/devantler-tech/agent-plugins/pull/148))

## 4.4.1 — 2026-08-20

**Fixed** — allow gh api field arguments under an explicit GET. ([#145](https://github.com/devantler-tech/agent-plugins/pull/145))

## 4.4.0 — 2026-08-17

**Added** — make simplification a core principle in both roles. ([#143](https://github.com/devantler-tech/agent-plugins/pull/143))

## 4.3.7 — 2026-08-16

**Fixed** — declare runtime executability. ([#142](https://github.com/devantler-tech/agent-plugins/pull/142))

## 4.3.6 — 2026-08-16

**Fixed** — pin runtime asset bytes. ([#140](https://github.com/devantler-tech/agent-plugins/pull/140))

## 4.3.5 — 2026-08-16

**Fixed** — classify current-head CI safely. ([#138](https://github.com/devantler-tech/agent-plugins/pull/138))

## 4.3.4 — 2026-08-16

**Changed** — update agent skills. ([#136](https://github.com/devantler-tech/agent-plugins/pull/136))

## 4.3.3 — 2026-08-15

**Fixed** — pin procedure skill digest. ([#135](https://github.com/devantler-tech/agent-plugins/pull/135))

## 4.3.2 — 2026-08-15

**Changed** — update agent skills. ([#134](https://github.com/devantler-tech/agent-plugins/pull/134))

## 4.3.1 — 2026-08-14

**Fixed** — pin deployed definition digest. ([#133](https://github.com/devantler-tech/agent-plugins/pull/133))

## 4.3.0 — 2026-08-14

**Added** — research on evidence-clean runs. ([#132](https://github.com/devantler-tech/agent-plugins/pull/132))

## 4.2.1 — 2026-08-14

**Changed** — update agent skills.

## 4.2.0 — 2026-08-14

**Added** — measure Improver effectiveness.

## 4.1.7 — 2026-08-13

**Changed** — update agent skills. ([#127](https://github.com/devantler-tech/agent-plugins/pull/127))

## 4.1.6 — 2026-08-12

**Fixed** — retire human promotion gate. ([#87](https://github.com/devantler-tech/agent-plugins/pull/87))

## 4.1.5 — 2026-08-12

**Security** — make the surveyor's read-only boundary executable. ([#120](https://github.com/devantler-tech/agent-plugins/pull/120))

## 4.1.4 — 2026-08-08

**Fixed** — make surveys resumable. ([#114](https://github.com/devantler-tech/agent-plugins/pull/114))

## 4.1.3 — 2026-08-03

**Fixed** — forbid foreground remote polling. ([#112](https://github.com/devantler-tech/agent-plugins/pull/112))

## 4.1.2 — 2026-08-03

**Changed** — update agent skills. ([#110](https://github.com/devantler-tech/agent-plugins/pull/110))

## 4.1.1 — 2026-07-28

**Fixed** — publish connector review hardening. ([#104](https://github.com/devantler-tech/agent-plugins/pull/104))

## 4.1.0 — 2026-07-26

**Fixed** — make plugin content changes reach consumers. ([#100](https://github.com/devantler-tech/agent-plugins/pull/100))

## 4.0.0 — 2026-07-25

**Changed (breaking)** — the primary engineer's agent entrypoint is named `agentic-engineer` rather
than `automated-ai-engineer`, so the role's identifier matches the name it is called by. This is a
rename only: nothing about the role's behaviour, contract sections, or guardrails changes. See
[ADR 0006](../../docs/adr/0006-rename-agentic-engineer-entrypoint.md).
([#89](https://github.com/devantler-tech/agent-plugins/pull/89))

### Upgrading to 4.0.0

There is no marketplace-level migration for agent names the way there is for plugin names, so a
deployment that persists the old entrypoint keeps pointing at an agent that no longer resolves.
Update three places before the next scheduled run:

1. **Scheduler pointers** — every plugin-backed schedule that names
   `plugin:agentic-engineering/automated-ai-engineer` becomes
   `plugin:agentic-engineering/agentic-engineer`, and any bootstrap prompt that names the entrypoint
   in prose changes with it.
2. **Qualified agent references** — persisted selections such as
   `agentic-engineering:automated-ai-engineer` become `agentic-engineering:agentic-engineer`.
3. **The consumer's desired state** — `spec.source.entrypoint`, the `spec.roles` key, and the
   `spec.runtime.scheduler.schedules` key all move to `agentic-engineer`.

Sequence this **after** [*Upgrading to 3.0.0*](#upgrading-to-300): retiring the `finops-engineer`
schedule and renaming the engineer's entrypoint are independent changes, and doing them one at a time
keeps a failed reconcile attributable to one cause.

## 3.0.0 — 2026-07-25

**Changed (breaking)** — spend stewardship is a dimension of the primary engineer's own loop; the
separate FinOps role and its schedule are removed. The plugin name, entrypoint names, and agent set
are unchanged. See
[ADR 0005](../../docs/adr/0005-merge-spend-stewardship-into-the-engineer.md).
([#90](https://github.com/devantler-tech/agent-plugins/pull/90))

### Upgrading to 3.0.0

Two consumer-side changes are required before the next scheduled run:

1. **Retire the `finops-engineer` schedule FIRST — before installing or reconciling this version.**
   Its work now happens inside the engineer's loop, so a surviving schedule would run a role this
   plugin no longer defines. Quiesce or atomically replace it with the runtime's native scheduler
   control **ahead of** the new engineer schedule: installing first opens exactly the
   concurrent-stewardship window this upgrade exists to close, and **a briefly missed cost pass is
   much cheaper than two writers proposing against the same spend.** The cost pass is cadence-gated,
   not continuous, so the gap costs at most one pass.
2. **Rename the consumer contract section to `Spend contract`** and the desired-state key
   `spec.consumer.requiredWhenFinOpsEnabled` to `spec.consumer.requiredWhenSpendStewardshipEnabled`
   (value `["Spend contract"]`). Also delete `spec.roles["finops-engineer"]` and
   `spec.runtime.scheduler.schedules["finops-engineer"]`, and add the never-move-money guardrail. The
   validator rejects the old shape, so a stale copy fails closed rather than silently deploying two
   writers over one concern.

A consumer that keeps its FinOps definition as a separate agent is not broken by this release — but
it is no longer the shape this plugin describes. Spend enablement follows the explicit flag and
resolving `Spend contract` introduced in [*Upgrading to 5.0.0*](#upgrading-to-500).

## 2.0.0 — 2026-07-22

**Changed (breaking)** — the autonomous engineering system moves into this plugin and becomes its
centre; the former `automated-ai-engineer` plugin is consolidated here. From the earlier
`agentic-engineering` bundle only the tool-neutral `agent-instructions` and `find-skills` skills
remain; the provider-specific SDK and instruction-blueprint skills are removed. See
[ADR 0004](../../docs/adr/0004-consolidate-agentic-engineering.md).

### Upgrading to 2.0.0

This version deliberately replaces the old marketplace identity instead of keeping a second alias
bundle. The marketplace's append-only rename history maps `automated-ai-engineer` to
`agentic-engineering`. Claude Code 2.1.193 and later automatically migrates the persisted
installed-plugin key when the marketplace refreshes; restart Claude Code or run `/reload-plugins`,
then continue with step 2.

For older Claude Code versions and runtimes that do not implement marketplace rename migration,
complete the plugin-name change manually before the next scheduled run:

1. Remove the installed `automated-ai-engineer` plugin with the runtime's native plugin control, then
   install `agentic-engineering@devantler-plugins` from `devantler-tech/agent-plugins`.
2. Change persisted qualified agent references from the `automated-ai-engineer` plugin namespace to
   `agentic-engineering`. The entrypoint itself is renamed separately in
   [*Upgrading to 4.0.0*](#upgrading-to-400).
3. Copy the [provider-neutral desired state](resources/provider-neutral.desired-state.json) into the
   consumer workspace and reconcile its native agents and schedules. Preserve the consumer's
   canonical `AGENTS.md`; do not copy its organization-specific facts into this plugin.
4. Before re-enabling unattended writes, verify that the installed plugin reports version `5.0.0` or
   later — so [*Upgrading to 3.0.0*](#upgrading-to-300), [*Upgrading to 4.0.0*](#upgrading-to-400),
   and [*Upgrading to 5.0.0*](#upgrading-to-500) must all be complete too. A stop at `2.0.0` would
   resume writes with the retired FinOps schedule still armed, and a stop at `3.0.0` with a schedule
   pointing at an entrypoint that no longer resolves. Verify also that the plugin exposes
   `agentic-engineer`, `portfolio-surveyor`, and `agent-improver`, and that every plugin-backed
   schedule points to `plugin:agentic-engineering/<entrypoint>`. Run the required read-only preflight
   and record the installed source revision and any unsupported capability.

The upgrade is complete only after the old plugin identity no longer resolves in the runtime and the
read-only preflight loads the new namespace successfully.

## 1.0.0 — 2026-06-28

**Changed** — rename the copilot plugin to agentic-engineering. ([#35](https://github.com/devantler-tech/agent-plugins/pull/35))

