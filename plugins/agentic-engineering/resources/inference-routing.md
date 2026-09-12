# Inference routing contract

This optional contract separates task policy from runtime enforcement. The consumer's **Inference
routing** section names one reviewed policy file, its revision, runtime verification records, and
the private telemetry store. Without that section, existing model selection continues. If a
declared policy cannot resolve, hold dependent routing changes and report the gap; continue
independent authorized work. Infrastructure spend opt-in remains a separate contract.

## Evaluation boundary

`scripts/evaluate-inference-routing.sh` reads exactly one JSON object from stdin and writes a JSON
decision. It uses Bash and jq, makes no network request, reads no credentials, launches no model,
takes no lock, and writes no file. Run it from the reviewed plugin revision whose desired state
pins its digest. `--now <Unix-seconds>` supplies deterministic evaluation time for tests; production
uses the host clock.

| Exit | Decision | Meaning |
|---|---|---|
| 0 | `RECOMMEND` | Policy and supplied observations permit the recommended route |
| 1 | `HOLD` | The request is valid but one or more policy/evidence conditions are unmet |
| 2 | `INVALID` | Malformed, unsupported, or prohibited configuration/input |

**Every result has `executionAdmitted: false`. No exit code is a launch authorization.** The
`reportedControls` field describes caller-supplied data, not verified enforcement. Do not wire an
exit-zero shell condition directly to an inference launcher. An assistant calling this helper has
already incurred its own initial inference and instruction load.

The JSON root requires `policy`, `task`, and `snapshot` only. Unknown fields, missing fields, extra
JSON documents, and invalid types fail validation. JSON producers must emit unique object keys;
jq parses repeated keys using its normal last-value semantics. The helper is a policy aid, not a
hostile-input authentication boundary.

## Policy version 1

| Field | Contract |
|---|---|
| `version`, `revision`, `enabled` | `1`, immutable review identifier, and explicit boolean opt-in |
| `billingMode`, `paidFallback` | Exactly `subscription-only` and `false` |
| `deniedModelTerms` | Nonempty distinct case-insensitive literal substrings; every route is checked, including unused routes |
| `routes` | Exactly `support`, `workhorse`, `diagnosis`, `deepRefactor`; each has an exact `model`, registered `runtime`, and `effort` (`low`, `medium`, `high`, `xhigh`) |
| `runtimes` | Map of runtime registration IDs to `enabled`, `role` (`owner`, `builder`, `observer`), and `expiresAt` in Unix seconds |
| `limits` | `maxDepth` and `maxChildren` (0 or 1 initially), positive integer `repairHypotheses`, `activeMinutes`, `snapshotMaxAgeSeconds` (1–300), and `reservePercent` with positive `short` and `weekly` percentages |

Deployment model names and runtime IDs never enter portable agent frontmatter. An exact string
in a policy is an intended model, not proof that the runtime supports it. Denial terms cover visible
IDs only; opaque aliases/defaults/substitutions need native verification before execution.

## Task and observation input

The task supplies `class`, nonnegative integer `depth`, `children`, `distinctFailedHypotheses`, and
`activeMinutes`; `failureKind` (`none`, `reasoning`, `environment`, `quota`, `authority`); and boolean
`contractClear`, `checksDefined`, `reversible`, `sensitiveInvariants`, `writeRequired`.
`depth` is the proposed target depth (the owner is zero); `children` is the total active child count
after the proposed dispatch. They are prospective counts, not the counts before adding a child.

Support and workhorse tasks move to diagnosis when the stated contract/check/reversibility criteria
fail, sensitive invariants remain, or either repair/active-time threshold is reached. Active time
excludes waits. Count distinct tested hypotheses, not repeated commands. Environment, quota, and
authority failures hold the request; they never justify buying more reasoning. An unclear contract
also holds writes, as do missing checks and irreversible scope; diagnosis may investigate these
read-only but cannot manufacture missing authority.
`deepRefactor` is
an explicit task classification supported by a demonstrated runtime advantage, not the next
automatic rung after diagnosis. The owner must also check task scope and previous handoffs.

The snapshot requires:

- `observedAt` (Unix seconds), `runtime`, `runtimeVersion`, runtime-reported resolved exact `model`
  or `null` (never populate it by copying the policy's intended model);
- `billing` (`included`, `unknown`, `paygo`), `controls` (`verified`, `unverified`), `evidenceRef`
  (a private verification record reference or `null`);
- `buckets.short` and `buckets.weekly`, each `null` or an object with `remainingPercent`,
  `estimatedChainPercent`, `reservedPercent`, and `unsettledPercent`. Each value is a percentage
  in 0–100 or `null`. Unknown is never zero.

Snapshots must refer to the selected runtime and exact model. Future timestamps, expired runtime
registrations, stale observations, observer writes, and excess delegation produce `HOLD`. Quota
headroom must cover the estimated whole attempt chain, existing reservations, unsettled debits,
and the reserve in **each** bucket. This is arithmetic over reported values, not a reservation.
Provider/model-specific extra buckets require a verified adapter extension before that route can
run; never discard a bucket to fit this two-window version. Percentage units are local to each
provider bucket and cannot be added across accounts or compared as inference prices.

See the adjacent hermetic test for complete synthetic requests and independently expected results.

## Runtime controls before unattended activation

Maintain an expiring verification record for each concrete deployed surface and version. Verify
the included billing path, disabled paid fallback/overages, exact model resolution, inherited tool
permissions, workspace isolation, and account admission. The trusted launcher/native control must
apply before inference; a prompt, model preference, or caller-supplied `verified` flag is insufficient.
Exercise launch, resume, child overrides, advisors, defaults, and fallback. Intercept forbidden
requests before inference in negative tests; never invoke a prohibited model as a test. If the
runtime cannot provide the needed control, leave its affected unattended route disabled.

Use the native subscription harness; never add an inference broker, API credential, purchased
credits, or pay-as-you-go fallback. Native schemas differ: do not copy generic tool names into a
provider manifest and assume enforcement. A deployment's explicit inline survey override takes
precedence over generic delegation advice.

Start with serialized scheduled admission per account and one bounded child at depth one. The
reservation covers parent, children, integration, retries, and handoff. Serialize the check and
reservation in a trusted external admission mechanism before enabling fan-out. A worktree lock
does not reserve model quota. Expiring a writer lease does not stop an old session; retain its
unsettled debit until consumption is reconciled or termination is verified. Resume with the same
reservation identity. Include interactive and other-device usage in coverage; missing coverage
prevents an exact per-task attribution claim.

## Ownership and measurement

The engineering skill owns bounded task packets and one delivery owner. A helper performing lint,
tests, or a commit is a procedure/tool call, not an automatic new agent. The improvement skill owns
complete attempt-chain accounting, context hydration, matched task cohorts, quality floors,
canary promotion, and rollback. Consumer governance supplies experimental thresholds and its single
policy publisher; overlapping runs of that publisher still require fencing. Runtime validation and
longitudinal outcomes are separate acceptance gates from passing these offline tests.
