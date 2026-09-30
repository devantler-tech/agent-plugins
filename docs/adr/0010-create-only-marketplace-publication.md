# 0010: Create-only marketplace publication

Date: 2026-09-30

Status: Accepted

## Context

Release preparation, exact-commit verification and fresh remote assessment establish a candidate.
Consumers need a stable tag and a published release describing that same catalogue. An assessment
does not reserve either object, and a failed network response does not prove that a write failed.

## Decision

Provide a manual publisher whose default mode remains read-only. `--publish` explicitly enables two
create-only operations: reserve a lightweight tag at the independently selected release commit, then
create a non-draft GitHub release. No workflow publishes automatically. The operator must first
establish current-head CI, review and genuine readiness; the command verifies artifact/remote
consistency and does not claim to establish those independent gates.

Regenerate a private candidate from the verified Git objects before remote assessment. Derive
publication notes from that frozen plan, reusing its escaped commit subjects and plugin inventory;
do not publish the preparation document's proposal-only wording. Require matching repository,
default branch, tag identity and release state immediately before and after the writes. Verify the
created release ID, published state, notes, URL and tag commit in an independent readback.

Use GitHub's [create-reference](https://docs.github.com/en/rest/git/refs#create-a-reference) and
[create-release](https://docs.github.com/en/rest/releases/releases#create-a-release) endpoints.
Never update, delete, force or retry a remote write. Existing objects, conflicts, malformed responses
and ambiguous failures stop with no success result. A partial attempt leaves its objects intact for
operator investigation; blindly rolling back could erase another writer's work.

## Consequences

The safe default can be exercised without publication credentials. Explicit publication requires
GitHub write permission and the deployment's authority to release the selected commit. The flag is
a permanent operation selector, not a temporary rollout toggle.

The two writes are not a transaction. Another writer can change remote state between observations;
create-only reservation prevents overwriting its tag, and readback detects divergence rather than
claiming atomicity. A lost response can leave a reserved tag or a published release despite a nonzero
exit. Recovery requires inspecting those exact objects and deciding how to proceed; rerunning this
command never resumes an occupied version. Installed runtime caches are outside its scope.
