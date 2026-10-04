# Assess an autonomy method offline

The optional assessor compares caller-reported proof for one method replacement with a
consumer-owned contract. It helps a human reviewer decide whether to retain a default, consider a
candidate, consider scoped recovery, or hold for missing facts. It does not grant execution,
authenticate an owner or report, read referenced artifacts, update a runtime, or perform recovery.

The command is disabled unless explicitly invoked with `--assess`. No arguments returns
`DISABLED` without opening a contract or invoking Go. Installation leaves every existing role,
permission, hook and schedule unchanged. The active command needs Bash and a local Go 1.22 or
later toolchain; it has no third-party Go dependencies.

## Try the synthetic example

From an installed agentic-engineering plugin directory:

```sh
bash scripts/assess-autonomy.sh
bash scripts/assess-autonomy.sh --assess \
  --contract resources/autonomy-contract.example.json \
  --now 2026-10-04T00:00:00Z
```

The second command deliberately assesses the example at its fixed fixture time. Its result is
`RECOMMEND_CANDIDATE` with `synthetic: true`. This is a teaching fixture, not a live evaluation,
review, human decision or runtime attestation. Supply independently reviewed deployment facts and
the actual assessment time for a real consumer assessment.

## Declare a consumer contract

The example is the complete version 1 input shape. Exactly spelled field names, one UTF-8 JSON
object and unique decoded keys are required, including nested objects. Case aliases, unknown
fields, trailing documents, input above 1 MiB and nesting above 64 levels are refused. Selectors
are `--contract` and `--now`, each exactly once; single-dash aliases are refused. Timestamps are
exact UTC seconds in `YYYY-MM-DDTHH:MM:SSZ` form. Names and opaque artifact records use visible
ASCII letters, digits and `:/@._-`, without spaces. Nothing opens those records.

- `contract.enabled` is an explicit boolean. The declared owner has an id, `kind: human` and an
  ownership record. Those values are reports; this command cannot establish who wrote them.
- `protected` must include security, spend, production, destructive operations, lifecycle,
  disclosure, external commitments and enforcement. Only an explicitly recorded
  `replaceable-default` classification is assessable. A `protected` candidate retains the default;
  unknown or incomplete classifications are invalid. Deployments retain their actual authority
  decisions and enforcement outside this input.
- `scope` binds one capability, repository, environment and exact set of operations. Contract,
  request and proof must agree. Runtime and recovery observations also name that scope.
- `bindings` names the contract, role, runtime controls, incumbent and candidate revisions as
  full lowercase 40-character Git identities or 64-character content digests. All five must
  match across contract, request and proof; incumbent and candidate must differ. A changed role
  or control needs new proof. The command checks equality and shape, not authenticity or
  correspondence with external bytes.
- `requiredEvidence` includes measurement, static, behavior, deployment, live, review, holdout and
  rollback. `requiredOutcomes` names every dimension the consumer requires; `protectedOutcomes`
  is a nonempty subset naming its floors. A passing benefit never cancels a failed floor.
  Evidence requirements cannot omit one of these stages.
- `requiredPaths` declares every applicable main, child, resume, retry or fallback path. This
  deployment-specific declaration must be independently complete. Both the positive and
  intercepted-negative runtime reports carry their own complete `coveredPaths`; a union of
  different tests is insufficient. The runtime observation names the exact control revision.
- `fallbackRevision` equals the incumbent revision, and `recoveryOwner` names who resolves a
  recovery hold. Recovery reports bind the same scope and control revision, a tested fallback,
  an existing authorization record and current observation/expiry times. Initial replacement
  also requires this reported recovery readiness.

## Supply bounded replacement proof

The proof names an immutable preregistration plan, evidence bundle and assessment, each with an
opaque record and SHA-256 digest. `registeredAt` precedes `startedAt`, and the experiment must
already have started. The assessment explicitly joins both `planSha256` and `bundleSha256`
and carries its result and observation/expiry times.

Every required evidence stage needs a report with a distinct id, kind, record, result and times.
Every required outcome needs exactly one reported result. Replacement and runtime positive reports must be current,
observed after the experiment started and no later than the assessment time. Runtime support
requires a positive report and an intercepted-negative report of the same controls and complete
paths, with different ids and records. These are reported assertions; a passing JSON assessment
does not prove a provider evaluation, genuine independent review or intercepted execution.

Use the product-engineering evidence-bundle calculator to measure actual objective changes and
protected floors. Preserve its immutable input and output as the nominated bundle and assessment,
and independently verify their hashes, scope and verdict before using this adapter. This command
does not parse the referenced calculator output or compute its measurements. Incomplete, unknown,
future, foreign or unbound assertions yield a hold rather than replacement support.

A bound runtime failure remains negative even if its counterpart is missing or future-dated, and
a bound failure remains negative after expiry. Both runtime reports must be complete for replacement
support. Protected requests retain only the matching incumbent; foreign scope or an unsupported
current revision produces no recommendation. Unknown observations never establish support or its loss. Loss of current evidence or runtime support can
recommend contraction when the candidate is current and scoped recovery is reported tested and
already authorized. Pre-experiment and future observations cannot establish that loss. Missing
recovery readiness yields a hold with the recovery owner; no fallback command is run.

## Interpret the result

| Status | Meaning |
| --- | --- |
| `DISABLED` | The optional command was not activated. No contract or compiler was used. |
| `RETAIN_DEFAULT` | Disabled/protected contract, or failed/expired support while still on the incumbent. |
| `RECOMMEND_CANDIDATE` | Complete matching caller reports support human review of this method only. |
| `RECOMMEND_CONTRACTION` | Current candidate lost support and reported scoped recovery is ready. |
| `HOLD` | Missing, unknown, foreign, future or unsupported facts need resolution. |

Every result retains `authority: assessment-only`, `executionAdmitted: false`,
`mutationPerformed: false` and `reportedEvidenceAuthenticated: false`. Recommendation and hold
results exit zero because assessment completed; consumers must read the status rather than treating
exit zero as admission. Invalid input exits nonzero without assessment output.

The consumer must separately authenticate classifications and evidence, enforce all runtime paths,
resolve any actual permission changes through its governing process, and verify recovery through
the real provider/user path. The portable runtime integration remains outside this offline tool.
[ADR 0016](../../docs/adr/0016-offline-autonomy-contract-assessment.md) records that boundary.
