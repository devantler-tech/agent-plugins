# ADR 0014: Create-only marketplace proposal drafts

## Status

Accepted.

## Context

A marketplace release starts with two generated manifest versions on current main. Preparation and
publication are separate operations; a candidate does not establish review readiness or authority
to merge. Automated proposals need a bounded writer and observable normal CI.

## Decision

Proposal preparation reads complete Git history and matches all local tag objects to complete remote
tag observations. The latest stable baseline must be a published release at its tagged commit.
Current main, immutable repository identity, exact successful main CI and conflicting manifest PRs
are checked twice around candidate reconstruction. Incomplete reads are refusals.

Creation is explicitly armed. Native Actions creates a new deterministic branch and a signed commit
through GitHub's GraphQL commit mutation, bound to its expected parent. The commit may change only
the two reproduced manifests. The writer verifies the provider's signature and fetches the exact
commit to reproduce the release-tree check before creating a draft. It then reads the branch and PR
back. Existing branches or conflicting proposals are never updated or adopted.

The workflow uses separate read-only preparation, creation and CI-trigger jobs. Creation reconstructs
its own candidate with current main tooling. Only exact successful draft readback permits dispatch
of the existing main recheck workflow, which supplies fresh normal PR CI. Downloaded artifacts,
branch names, PR bodies and commit subjects cannot choose executable code or the target repository.
Manual dispatch defaults to assessment; scheduled creation requires `MARKETPLACE_AUTOPROPOSE` to be
exactly `true`. The rollout variable remains absent until separately evaluated. Rollout and removal
are tracked in issue #277.

## Consequences

Drafts still require current-head CI, substantive review, zero unresolved findings and normal merge
mechanics. No proposal operation promotes, merges, creates a release tag or publishes a release.
Marketplace and individual plugin versions remain independent.

Remote operations are not a transaction. The `main` branch can advance after observation. A write response can
fail after creating its object; failure emits no delivered result and never retries or rolls back.
Inspect the named branch and any draft using the retained source and candidate before choosing an
operator recovery. A later invocation refuses occupied state, including a partially created branch.
An unrelated PR is not a blocker; a PR touching either marketplace manifest is a shared-artifact
conflict. Large or incomplete PR file inventories cannot establish absence.

Reference: [GitHub GraphQL commits](https://docs.github.com/en/graphql/reference/commits).
