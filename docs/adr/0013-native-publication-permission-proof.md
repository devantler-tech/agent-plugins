# ADR 0013: Native publication permission proof

## Status

Accepted.

## Context

The create-only publisher needs effective writer visibility to establish that a draft release is
absent. Its authentication may be a user or a native Actions installation token. GitHub's GraphQL
repository user role is explicitly null for App authentication, so a user role alone cannot prove
the installation's permissions. A null value also cannot establish writer access.

## Decision

Every remote assessment and publication phase independently reads the native REST repository.
The response must have a positive integer repository ID, matching name, active archive state and matching
default branch. Its immutable node ID must match the GraphQL repository ID.

Each phase also invokes GitHub's release-note generation endpoint with the verified candidate tag
and exact release commit. GitHub requires contents-write access for this nonpersistent computation;
it saves neither a release nor notes. A successful response containing one valid name/body object
is positive capability evidence. The generated text is discarded and never controls published
notes, commands or release authority. Repository permission projections alone are insufficient for
installation-token capability.

GraphQL still verifies the repository, complete tag inventory, branch and release state. Its user
role field must exist and contain WRITE, MAINTAIN, ADMIN or explicit null. Null is compatible with
App authentication only because the independent native capability check positively proves writer
visibility; missing, unknown, READ and TRIAGE roles are rejected. Missing, malformed, trailing or
conflicting responses never establish clearance.

The assessment records the immutable repository ID. All later publication phases bind both API
identities to that same repository and repeat the capability check. A permission loss or identity
change stops the operation, including after a remote write.

## Consequences

Users and installation tokens follow the same positive permission rule. The read-only Actions
assessment continues to verify the merged proposal and exact main CI without calling the writer's
remote prepublication check. Only the separate, explicitly armed contents-write job can invoke
publication with native writer evidence.

The check establishes visibility, not release authority or an atomic guarantee that a write will
succeed. Explicit opt-in, independent review and CI, exact current main, create-only writes and
independent readback remain required. A failed write may leave remote objects; operators inspect
them before recovery. No fallback token or extra credential is introduced.

The permission model follows GitHub's documented
[GraphQL repository role](https://docs.github.com/en/graphql/reference/repos),
[native Actions token](https://docs.github.com/en/actions/concepts/security/github_token) and
[REST repository endpoint](https://docs.github.com/en/rest/repos/repos#get-a-repository) and
[nonpersistent release-note generation](https://docs.github.com/en/rest/releases/releases#generate-release-notes-content-for-a-release).
