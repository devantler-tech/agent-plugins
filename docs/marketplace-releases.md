# Prepare a marketplace release

A marketplace version describes the entire catalogue at a source revision. Each plugin retains its
own version and runtime cache identity. Release preparation produces a review artifact containing
the proposed marketplace version, release notes, and both updated marketplace manifests.

Preparation is opt-in and offline. It does not publish, create tags, change the checkout, or update
installed plugins. A candidate is not an installable marketplace snapshot: it contains manifest
proposals and identifies the source commit containing the plugins.

## Prepare locally

Use Bash, Git, and jq 1.6 or later from a complete repository clone. Shallow and partial
(`--filter`) clones are refused, because reading their history would need the network. Refresh
tags from the trusted remote before choosing a baseline; the offline command cannot establish
remote freshness.

For the first marketplace release, explicitly select `initial`:

```sh
git fetch origin --tags
bash scripts/prepare-marketplace-release.sh \
  --base-tag initial --output /tmp/marketplace-candidate
```

The output directory must not exist, its parent must exist, and it must be outside every working
tree of the repository, linked worktrees included, so preparation never leaves files in a checkout.
Initial preparation uses the current marketplace manifest version and refuses to run if any stable
marketplace tag is present locally. It records the legacy first-parent history without inferring a
new version from that history.

For a later release, name the latest reachable stable tag:

```sh
bash scripts/prepare-marketplace-release.sh \
  --base-tag v1.0.0 --output /tmp/marketplace-next
```

`v1.0.0` is an example; use the verified baseline for the source being reviewed. The command reads
committed objects at `HEAD`, not uncommitted files. To prepare a specific revision, add
`--head <full-40-character-commit>`. Shallow history, a non-ancestor/side-branch baseline, mismatched
manifest versions, or a locally occupied candidate tag stops preparation without a candidate.

The baseline must be on the source commit's first-parent history. Version calculation follows the
repository's squash-merge convention:

| First-parent commit | Result |
| --- | --- |
| A breaking `!` header or `BREAKING CHANGE:` / `BREAKING-CHANGE:` line | Major |
| `feat:` or a scoped feature | Minor |
| `fix:` or `perf:` | Patch |
| Other conventional types, or no new commits | No release |
| Reverts, blank descriptions, or nonconventional subjects | Stop for human assessment |

The largest change wins. Type names are case-insensitive. Stable versions have three numeric
components, each from 0 to 999999999, with no leading zeroes. Prerelease and build-metadata versions
are not supported. The source manifests must still carry the baseline version: preparation does
not guess how to reconcile an independently edited version.

## Inspect the result

- `release.json` binds the source commit, baseline tag and commit, calculated version and release
  type, first-parent commits, and plugin inventory. `publication: NOT_AUTHORIZED` is always present.
- `RELEASE_NOTES.md` presents that proposal and the contributing commit subjects as escaped text.
- `.github/plugin/marketplace.json` and `.claude-plugin/marketplace.json` contain identical proposed
  marketplace manifests. Every other field, including plugin versions and rename history, is preserved.

For `NO_RELEASE`, only the plan and notes are emitted; there are no proposed manifest updates.
Repeated preparation from the same Git objects produces identical files. Existing output paths are
never reused. Preparation validates manifest shape and parity; full resource/provenance checks
remain the responsibility of `bash scripts/validate-manifests.sh` and the rest of repository CI.

## Prepare in GitHub Actions

Run **Prepare marketplace release** manually, select the source branch/ref, and provide the baseline
tag or `initial`. The workflow checks out the selected revision with full history, validates the
repository manifests, runs the same command, and uploads `marketplace-release-<commit>-<attempt>` for 14 days.
The archive includes the two hidden manifest directories. The job has read-only repository access;
there is no publishing job or automatic release trigger.

## Publication and recovery

Before reserving a tag, verify the candidate against the exact proposed release commit:

```sh
bash scripts/verify-marketplace-release.sh \
  --candidate /tmp/marketplace-next \
  --source <full-reviewed-source-commit> \
  --release <full-proposed-release-commit>
```

Run the verifier from a complete clone using the reviewed repository tooling. Select the source
independently from the reviewed proposal, rather than trusting a value supplied by an arbitrary
download. For a subsequent release, copy the two proposed manifests into an isolated branch based
on that source, review and commit only those files, and pass that commit as `--release`. The release
commit must have exactly one parent, the selected source. Squash merging the version-only PR onto
that same source preserves this relationship. If main moves first, regenerate and review a new
candidate; do not reuse the stale assessment. For an initial release whose manifests already match,
the source itself may be the release commit.

The verifier regenerates and compares the complete four-file candidate, rejects unexpected entries
and symlinks, checks both committed manifest values, and rejects unrelated tree or file-mode changes.
It reads Git objects, so a dirty checkout cannot supply evidence for the release. It makes no
checkout, index or ref changes and does not access the network. Committed manifests must match the
generated bytes, including formatting, so duplicate JSON keys cannot hide an unreviewed value. An
initial release may instead retain its unchanged source manifest bytes. Copy the generated files
without reformatting them. A `NO_RELEASE` plan is not a candidate
for verification. The intended tag must still be absent locally; this is not a post-publication
verification command.

Only exit zero with a single JSON result reporting `status: VERIFIED` is a successful local
assessment. It includes both full commits and `authority: assessment-only`, with
`publication: NOT_AUTHORIZED`. Invalid input or any mismatch exits nonzero without a success result.
The same inputs produce the same assessment. Re-run it against the final merged release commit;
an earlier PR commit's result does not transfer to a new commit.

This check cannot establish remote freshness, genuine readiness, who reviewed the source, or actual
consumer installation. Keep the candidate immutable while reviewing and verifying it; a later edit
invalidates the result. Full repository validation and the independent review gate still apply.

Actual publication is tracked in [#101](https://github.com/devantler-tech/agent-plugins/issues/101).
Before publication, remote tags and the source must be rebound, the proposed manifest update must
be reviewed and validated at its final commit, and tag reservation and GitHub release creation must
be verified. A source change invalidates this candidate. Do not upload it as a released plugin bundle
or claim that consumers have received it. Discarding an unused candidate requires no repository
rollback because preparation made no repository change.

[ADR 0008](adr/0008-marketplace-release-preparation.md) defines this boundary.
