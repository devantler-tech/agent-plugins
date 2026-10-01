# ADR 0015: Historical marketplace content inspection

## Status

Accepted.

## Context

Operators need to examine retained proposal artifacts and completed release commits when a local
version tag is occupied. The normal verifier requires an unoccupied candidate tag because its
result participates in prepublication assessment. Removing or moving the caller's tag to reuse
that verifier destroys relevant recovery evidence and can affect another writer.

## Decision

The verifier offers explicit, default-off `--inspect-existing` mode. It checks complete original
history, then reconstructs the candidate in a disposable local repository sharing immutable Git
objects. Only the private copy of the candidate tag is removed, with an expected-object check.
The ordinary verifier supplies all artifact, baseline, parent, tree and mode checks. No code from
the nominated source, release or artifact is executed. Inherited Git layout overrides are removed
and private repository isolation is checked before its ref mutation.

The original tag inventory is observed before and after inspection. Movement refuses a successful
result. A commit-resolving tag is recorded with its object and commit identities, including whether
it matches the nominated release. A different target is evidence, not a conflict resolution.
Missing local tags remain explicitly absent; non-commit tags are refused. Other local tags retain
their strict history meaning, including the initial-release requirement for no stable tags.

Success reports `INSPECTED` and `local-historical-content`, with assessment-only authority,
proposal and publication unauthorized, readiness unassessed and remote state unknown. It cannot
satisfy a writer's `VERIFIED` contract. Normal verification and all writer entrypoints retain their
prepublication, current-main and independent authority gates.

## Consequences

Operators gain reproducible local content evidence without changing caller refs, checkout files
or index, contacting a remote, or adopting an existing proposal. The result does not establish
remote occupancy, author identity, CI, review, current-main readiness or consumer discovery. A
retained artifact must remain immutable, and a tag snapshot may change after the final observation.
Missing or conflicting historical evidence still requires an operator decision through the normal
reviewed procedure.
