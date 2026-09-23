# `agentic-engineering`

The primary autonomous-engineering plugin for a repository portfolio. It carries the engineer that
operates and advances the portfolio, the read-only surveyor that gathers current state, and the
meta-engineer that improves the system from measured evidence. The generic role lives here; each
consumer supplies its organization-specific configuration through its canonical `AGENTS.md`.

Released versions and the upgrade steps each breaking release needs are in the
[changelog](CHANGELOG.md). A plugin's version is its cache key, so an install that never moves off an
old version keeps serving that version's definitions — check what a deployment actually loaded before
assuming it has a change the changelog lists.

## What it includes

Three agents:

- **`agentic-engineer`** — the actor that runs the survey → select → act → report loop, operates
  the portfolio, advances the oldest actionable issue, and — after explicit maintainer opt-in and a
  resolving **Spend contract** — stewards the portfolio's running cost in the same loop.
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
native capabilities, reconcile two thin scheduled dispatches from `AGENTS.md`, and report any
capability it cannot safely implement.

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

## Consumer contract

The consuming repository's canonical `AGENTS.md` must define five named sections. The agents and core
skills fail closed when any are absent:

- **Portfolio map** — repositories in scope and each product's `## Maintenance` card, including
  validate commands, labels, protected/generated files, roadmap home, and the standard
  **feature-flag mechanism** required for non-trivial feature work.
- **Trust gate** — trusted identities, reviewer-only identities, and repository merge mechanics.
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
   A bundled skill is not: each `SKILL.md` names its upstream in `metadata.github-repo` and is
   re-synced automatically, so an edit made here is reverted with no conflict and no signal. Send a
   skill change to the repository that field names.
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
- `scripts/count-unresolved-review-threads.sh` supplies the surveyor's unresolved-thread count. The
  guard accepts only `--repo` and a positive `--pr`, and only when the helper runs alone: its
  verdict is its exit status (0 none, 1 some, 2 unknown), so a pipeline around it is denied.

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

Tools that implement this marketplace's plugin layout auto-discover the `agents/` and `skills/`
directories. On surfaces without full plugin support, load the same canonical agent and skill files
from this repository; do not fork or paste copies into the consumer repository.
