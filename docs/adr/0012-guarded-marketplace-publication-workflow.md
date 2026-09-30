# ADR 0012: Guarded marketplace publication in Actions

## Status

Accepted.

## Context

Marketplace versions land through reviewed version-only proposals. The existing publisher verifies
their generated manifests and fresh remote state, creates an absent tag and release once, and reads
both back. Operators need the same path in Actions without transferring authority from an arbitrary
artifact or from unrelated green CI.

## Decision

Publication follows the repository CI workflow's completion on main. The automatic path is disabled
unless the repository variable `MARKETPLACE_AUTOPUBLISH` is exactly `true`. Manual dispatch defaults
to assessment and requires an explicit `publish` boolean to authorize writes. The flag's eventual
removal is tracked separately.

The assessment job has only contents and Actions read access. It checks out main with full history
and no persisted credentials. A helper binds that checkout to the selected full commit, the remote
main tip, and the exact completed successful push run of `.github/workflows/ci.yaml` from this
repository. It derives the proposal's sole parent, uses the existing version gate, and regenerates
the candidate from committed objects. Remote main and CI are checked again after local verification.
An ordinary commit returns `NO_VERSION_CHANGE`, never publication readiness.

The separate, armed publication job receives contents write and Actions read access. It checks out
main again, independently reconstructs and verifies the candidate and CI binding, and calls the
existing create-only publisher with `--publish`. It never downloads the assessment artifact. All
Actions are pinned; untrusted pull-request heads, caches and artifacts are not executed. The job
conditions reject PR, foreign-repository, failed and non-main trigger runs before checkout.

Assessment and publication use separate concurrency groups; publication is never cancelled in
progress. A stale run refuses if main advanced. Automatic proposal creation is a separate concern:
this workflow cannot approve or merge a proposal and does not bypass its review or branch protection.

## Consequences

Enabling the rollout variable grants automatic publication only after a reviewed version-only
proposal merges and its exact main CI passes. Without it, operators can inspect a named successful
CI run, then explicitly dispatch publication for that same main commit. There is no new credential,
App installation or direct push to main.

Create-only publication intentionally refuses an occupied release; reruns do not overwrite or
silently adopt it. A failure after a write may leave a tag or release, so operators inspect actual
remote state before recovery. The existing publisher owns that boundary. Native `GITHUB_TOKEN`
writes do not serve as a release-event orchestration contract; independent consumer verification
remains required. Readback is evidence of the remote objects, not of an installed consumer.

The trigger and permission split follow GitHub's documented
[workflow_run boundary](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run)
and [job permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idpermissions).
