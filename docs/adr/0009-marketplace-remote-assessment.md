# 0009. Observe remote release state without publication authority

Status: Proposed

## Context

The offline candidate verifier establishes artifact and commit agreement. It cannot establish that
local tags are current or that a release commit is still the repository's default-branch tip.
Publication needs both local content evidence and fresh remote observations.

## Decision

Provide an explicitly invoked read-only command that accepts the intended repository and full
source/release commits. Run the existing verifier before contacting GitHub. Read GitHub through
host-bound GraphQL queries, with the repository and tag passed as variables. Require the returned
repository identity, default-branch commit, complete tag inventory and absent release to agree.
Require a WRITE, MAINTAIN or ADMIN repository role: readers cannot establish the absence of draft
releases. This is a visibility precondition, not a grant to write.

Compare all tag names and direct object IDs, including annotated tag objects. Require pagination
to terminate, its total count to match the unique observed tags, and repository metadata to agree
across pages. API errors and missing fields never mean an empty inventory or an absent release.
The same inventory must match local refs used by the offline verifier.

Observe the remote again after repeating local verification. Reject differences between the two
normalized snapshots and changes in local tags. Emit an assessment-only record, without modifying
local or remote state. There is no automatic invocation or publication workflow in this slice.

## Consequences

Operators can detect a stale baseline, occupied version, incomplete API read or moved default
branch before publication. The CLI needs authenticated GitHub read access, Bash, Git and jq.

These are observations, not a transaction: a ref can move and return between reads, and state can
change after success. The assessment grants no authority and does not establish independent review,
CI readiness or a consumer installation. Publication under #101 still requires create-only tag
reservation, exact-commit release creation and post-publication verification. Neither a retry nor
recovery may overwrite an occupied tag to make a candidate pass.
