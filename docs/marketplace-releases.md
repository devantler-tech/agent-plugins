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

The output directory must not exist, its parent must exist, and it must be outside the
repository's working tree, so preparation never leaves files in the checkout. Initial preparation
uses the current marketplace manifest version and refuses to run if any stable marketplace tag is
present locally. It records the legacy first-parent history without inferring a new version from
that history.

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
| Reverts or nonconventional subjects | Stop for human assessment |

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

Actual publication is tracked in [#101](https://github.com/devantler-tech/agent-plugins/issues/101).
Before publication, remote tags and the source must be rebound, the proposed manifest update must
be reviewed and validated at its final commit, and tag reservation and GitHub release creation must
be verified. A source change invalidates this candidate. Do not upload it as a released plugin bundle
or claim that consumers have received it. Discarding an unused candidate requires no repository
rollback because preparation made no repository change.

[ADR 0008](adr/0008-marketplace-release-preparation.md) defines this boundary.
