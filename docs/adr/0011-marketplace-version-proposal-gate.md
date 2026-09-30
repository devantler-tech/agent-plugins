# 0011: Verify marketplace version proposals in pull-request CI

## Decision

When a branch changes the marketplace metadata version, CI regenerates its release
candidate from the current pull-request base and verifies the exact head with the
existing release verifier. The matching stable baseline tag must exist. The head
must have only the evaluated base as its parent and contain only the generated
manifest changes. The gate does not calculate SemVer independently.

Version-change detection compares the branch head with its unique merge base.
Comparing directly with the latest base would incorrectly attribute a marketplace
release to every ordinary branch created before that release. Both manifest pairs
are read from Git objects; invalid, missing or ambiguous version evidence fails.

## Consequences

A proposal becomes stale when its base moves. Regenerate it from the new base and
repeat CI and review. Do not rebase generated files and assume the earlier
assessment transfers. The existing main-push open-PR recheck refreshes merge refs.

This is pre-merge validation, with read-only permissions and no opt-out. The gate
runs inside the existing required version-check job on pull-request events. It
uses the event's explicit base and head commits, not GitHub's synthetic merge
commit. Tests exercise real branch histories and release generation.

The successful result establishes a local proposal, not remote tag freshness,
review readiness, or permission to publish. Re-run release verification against
the actual merged commit before publication. The gate does not run on main pushes
or manual CI reruns: a published candidate's tag is occupied, and publication must
not invalidate an already delivered commit's historical CI record.

Automatic version-proposal creation and publishing remain separate delivery work.
This decision implements the pre-merge portion of the existing release contract
in [ADR 0008](0008-marketplace-release-preparation.md) and
[ADR 0010](0010-create-only-marketplace-publication.md).
