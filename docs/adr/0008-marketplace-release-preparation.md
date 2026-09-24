# 0008. Prepare marketplace releases before publication

Status: Proposed

## Context

Marketplace releases identify a complete catalogue revision. Per-plugin versions identify runtime
cache entries and must continue to change independently. Both marketplace manifests contain the
same marketplace version, but a source SHA alone does not explain the next release or its contents.

## Decision

Prepare releases with an explicitly invoked, offline command and a manually dispatched, read-only
workflow. Preparation reads committed Git objects and produces a new directory containing a JSON
plan, readable notes, and proposed copies of both marketplace manifests. It never modifies the
checkout, creates refs, publishes a release, or changes per-plugin versions.

The caller explicitly selects `initial` or the last stable marketplace tag. Initial preparation
uses the existing manifest version and requires no stable marketplace tags locally. Later candidates
require the latest reachable stable tag, its first-parent ancestry, complete history, matching
manifest versions at both endpoints, and no collision with an existing candidate tag. Stable numeric
versions are supported; prerelease/build versions are outside this preparation contract.

For subsequent releases, first-parent Conventional Commits select the largest change: breaking
header/footer → major, `feat` → minor, `fix`/`perf` → patch, other conventional types → no bump.
Unclassified or revert commits require human assessment instead of silently becoming no release.
The initial snapshot may include legacy nonconventional history because its version is explicitly
bootstrapped, not inferred from those commits. Commit subjects are rendered as inert text.

The output binds the source and baseline commits, contributing commits, plugin inventory, and
proposed version. Identical inputs produce identical bytes. It is a review artifact, not a published
marketplace or proof of remote tag freshness. A no-bump history emits an explicit no-release plan.

## Publication boundary

Publication remains separate work under #101. Its implementation must refresh remote refs, review
and merge the version update, validate the exact resulting tree, reserve the tag without overwriting
an existing ref, publish at that commit, and verify the remote tag, release, manifests, and consumer
installation. Source movement invalidates the candidate. Nothing in a preparation artifact grants
authority or bypasses CI, independent review, branch rules, or release verification.

## Consequences

Maintainers can inspect a complete version proposal before any remote release write. Manual
invocation is the opt-in boundary; there is no automatic publishing flag or always-on release job.
The candidate is intentionally conservative about ambiguous histories. The offline tool cannot
prove that local tags are current, and neither a JSON plan nor a successful workflow constitutes a
release. Full manifest/resource validation remains a separate repository CI prerequisite.

References: [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/),
[Semantic Versioning](https://semver.org/), and
[manual workflow inputs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#defining-inputs-for-manually-triggered-workflows).
