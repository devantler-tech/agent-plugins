# Prepare and publish a marketplace release

A marketplace version describes the entire catalogue at a source revision. Each plugin retains its
own version and runtime cache identity. Release preparation produces a review artifact containing
the proposed marketplace version, release notes, and both updated marketplace manifests.

Preparation is opt-in and offline. It does not publish, create tags, change the checkout, or update
installed plugins. A candidate is not an installable marketplace snapshot: it contains manifest
proposals and identifies the source commit containing the plugins.

Versions are complete canonical stable SemVer strings, without whitespace or line terminators.
Source manifests and native API observations must contain exactly one complete JSON value with
unique decoded object keys, including nested objects and paginated arrays. A GraphQL observation's
error envelope must be absent or an empty array; false, null and other malformed values refuse
proposal and publication observations, including signed-commit and draft readback responses. Contradictory fields
are refused before candidate, readiness, occupancy or writer decisions. An ambiguous response
after a write leaves any created remote objects intact and reports uncertainty for explicit recovery;
it never establishes completed publication or a verified draft.

## Prepare locally

Use Bash, Git, iconv, and jq 1.6 or later from a complete repository clone. Each release helper derives
Git evidence and output exclusions from the caller's checkout. Inherited Git directory, worktree,
index, object-store and command-scoped configuration overrides cannot redirect that evidence. Configuration queries must
complete before an offline result is possible: only Git's no-match status proves an absent
partial-clone setting. Failed reads, including partial output, refuse preparation and validation;
lazy object fetching is disabled defensively.
Shallow and partial
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
never reused. Preparation checks that its entered reservation is empty before writing; writes and
artifact readback stay inside that directory. Movement detected by the directory-identity checks
refuses success and preserves both the replacement and any partial output for explicit recovery;
preparation never recursively removes a mutable public output pathname, including after a late
CI or ref refusal in merged preparation. These observations do not provide an atomic creation
handle or serialize other processes writing inside the directory. Use a separate new destination
for each preparation and inspect retained output before recovery.
Original JSON must preserve its bytes through Unicode validation and contain no unpaired surrogate
escapes. Valid international text and genuine replacement characters remain supported.
Preparation validates manifest shape and parity; full resource/provenance checks
remain the responsibility of `bash scripts/validate-manifests.sh` and the rest of repository CI.

## Prepare in GitHub Actions

Run **Prepare marketplace release** manually, select the source branch/ref, and provide the baseline
tag or `initial`. The workflow checks out the selected revision with full history, validates the
repository manifests, runs the same command, and uploads `marketplace-release-<commit>-<attempt>` for 14 days.
The archive includes the two hidden manifest directories. The job has read-only repository access;
this preparation workflow has no publishing job.

## Publish the merged proposal in Actions

**Publish marketplace release** supports manual main dispatch and an opt-in hourly check at minute
25 UTC. It uses
current-main tooling and regenerates the candidate from the version proposal's sole parent. The
assessment commit and its output bind to the actual current-main checkout, including when main
advances after dispatch. Both
remote main and the named CI run are checked before and after verification. A stale, foreign,
failed, PR or unrelated workflow run is refused. An ordinary commit reports `NO_VERSION_CHANGE`
and cannot publish. No downloaded artifact supplies publication authority.

For manual assessment, select main and pass the successful main CI run ID:

```sh
gh workflow run publish-marketplace-release.yaml --repo devantler-tech/agent-plugins \
  --ref main -f ci-run=<successful-main-CI-run-id> -F publish=false
```

The assessment job has contents and Actions read access and uploads its regenerated candidate for
inspection. Publication is a separate job, disabled by default, with contents write and Actions
read access. To publish that exact current-main proposal, dispatch again with `-F publish=true`.
It reconstructs the candidate again, verifies the same CI run and current main, and invokes the
create-only publisher. Main movement refuses the operation rather than using stale evidence.

Automatic publication after successful main CI is enabled only when the repository variable
`MARKETPLACE_AUTOPUBLISH` is exactly `true`. Missing, false or any other value leaves publication
disabled. Enable it only as a separate validated rollout step; remove or change it to disable the
automatic path. The rollout decision and eventual removal are tracked in
[#277](https://github.com/devantler-tech/agent-plugins/issues/277).

The workflow does not create, approve or merge version proposals. Their review and CI gates remain
required. It accepts only a version-only proposal at current main, refuses occupied tags/releases,
and never overwrites or retries a write. Inspect remote objects after any failed publication;
a failure is not proof that no write happened. `GITHUB_TOKEN` publication is not a promise that
other release-triggered workflows ran. Independently verify the published tag, release, notes and
a real pinned consumer installation. The scheduled job runs only while the rollout variable is
enabled; GitHub can delay scheduled runs. The `ci-run` input defaults to `latest`, which selects the
newest exact-main push CI run and refuses it if pending or failed, rather than finding an older
green. A changed latest run identity also refuses verification.
[ADR 0012](adr/0012-guarded-marketplace-publication-workflow.md)
records the workflow's trust and permission boundaries.

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

Pull-request CI enforces this contract whenever a branch changes the marketplace version. To run
that gate locally, supply the exact current base and proposed head:

```sh
bash scripts/check-marketplace-version.sh <full-current-base> <full-proposed-head>
```

The gate detects version changes against the branch's unique merge base, so ordinary branches are
not blamed for releases that landed after they branched. A version proposal must be one commit on
the current base containing only the generated manifests. If main advances, regenerate the proposal
and repeat review and CI. The baseline is the stable tag matching the base manifests' version;
missing history, malformed or ambiguous versions, and stale proposals fail closed. An unchanged
marketplace version returns `NO_VERSION_CHANGE`; that result does not approve a release.

The gate uses the pull request's actual head, not its synthetic merge commit. It is intentionally
pre-merge: main CI reruns must continue to work after the release tag exists. After merging, still
run the verifier and publisher against the actual merged commit as described below.
[ADR 0011](adr/0011-marketplace-version-proposal-gate.md) records this boundary.

Only exit zero with a single JSON result reporting `status: VERIFIED` is a successful local
assessment. It includes both full commits and `authority: assessment-only`, with
`publication: NOT_AUTHORIZED`. Invalid input or any mismatch exits nonzero without a success result.
The same inputs produce the same assessment. Re-run it against the final merged release commit;
an earlier PR commit's result does not transfer to a new commit.

This check cannot establish remote freshness, genuine readiness, who reviewed the source, or actual
consumer installation. Keep the candidate immutable while reviewing and verifying it; a later edit
invalidates the result. Full repository validation and the independent review gate still apply.

### Inspect a retained proposal after its tag is occupied

For an operator investigating a retained candidate or completed release, explicitly select the
verifier's read-only historical mode:

```sh
bash scripts/verify-marketplace-release.sh \
  --candidate /tmp/retained-marketplace-candidate \
  --source <full-independently-selected-source-commit> \
  --release <full-retained-proposal-or-release-commit> \
  --inspect-existing
```

Use reviewed tooling from a complete local clone and keep the candidate immutable. The inspector
reuses the complete candidate reproduction, source parent, two-manifest tree and file-mode checks
in a disposable local repository. Only that private repository's copy of the candidate tag is
removed for reconstruction. The caller's tags, branches, index and working files are preserved;
neither GitHub nor another remote is contacted. Inherited Git layout overrides are neutralized.
Physical checkout pathnames retain all their bytes, including trailing newlines. Verification keeps
configured filesystem observation hooks inert and preserves the caller's index and configuration.

Success emits `status: INSPECTED`, `scope: local-historical-content`, and a `localTag` snapshot.
`PRESENT` records the tag object, resolved commit and whether it targets the nominated release;
`ABSENT` records null identities and match status. A different target is reported without adopting
or changing it. A non-commit tag or any tag-inventory movement during inspection is refused.

This is content evidence for an operator decision. `proposal: NOT_AUTHORIZED`,
`publication: NOT_AUTHORIZED`, `readiness: NOT_ASSESSED` and `remoteState: UNKNOWN` remain explicit.
`INSPECTED` never satisfies a writer's `VERIFIED` contract, reserves a version, authenticates a
proposal author, or establishes current main, CI, review or consumer discovery. The ordinary
verifier still refuses an occupied tag. Inspect remote identities and permissions separately;
regenerate and review a new current-main candidate before any subsequent write.

All other local tags remain available to the strict history checks. Initial-release reconstruction
still requires no other stable tags, and a changed baseline identity is refused. Inspection does
not manufacture missing historical evidence or permit an arbitrary baseline. A snapshot can change
after the final observation; the result is not an atomic reservation.
[ADR 0015](adr/0015-historical-marketplace-content-inspection.md) records this boundary.

## Check against GitHub

After the proposed release commit lands on the default branch, use the opt-in remote assessment:

```sh
bash scripts/check-marketplace-release-remote.sh \
  --repo devantler-tech/agent-plugins \
  --candidate /tmp/marketplace-next \
  --source <full-reviewed-source-commit> \
  --release <full-merged-release-commit>
```

This needs an authenticated `gh` with effective repository write permissions, so draft releases
are visible; the operation itself creates no remote objects. Both user and GitHub App authentication
are supported. Each observation reads the native REST repository and binds its immutable node ID,
name, default branch and archive state to GraphQL. It also calls GitHub's nonpersistent release-note
generation endpoint with the candidate tag and exact commit. This endpoint requires contents-write
access and saves nothing remotely; its successful, well-formed response proves writer capability.
The generated text is discarded and never supplies publication notes or authority. A user role must
be WRITE, MAINTAIN or ADMIN; an explicitly null App role still requires the same positive native
capability proof. Missing fields, unknown roles, failed capability checks and incomplete responses
are refused. Repository permission projections alone do not establish an installation token's access. Choose
the repository independently of the candidate. The command uses that explicit identity and host,
not the checkout's Git transport configuration or `GH_HOST`.

It runs the local verifier and compares the complete local tag inventory with GitHub, including
annotated tag object identities. The selected release must be the remote default-branch tip, and
both its intended tag and GitHub release must be absent. GraphQL errors, missing fields, incomplete
pagination and conflicting observations fail closed. A draft release also occupies the version.
An account with only read or triage access cannot establish draft absence and is refused.
See [GitHub's release visibility rules](https://docs.github.com/en/rest/releases/releases#list-releases).
The command repeats the remote observation around another local verification and rejects movement
of the default branch, tags or release, or a change in local tags during the check.

Exit zero emits one JSON assessment with `scope: remote-prepublication-snapshot`, the repository,
immutable repository ID, default branch, full commits and observed tag inventory. `authority: assessment-only` and
`publication: NOT_AUTHORIZED` remain unchanged. It never fetches into your clone, edits files or
refs, reserves tags, or creates releases. The command is manual; no publishing trigger is enabled.

When tags disagree, refresh them in an isolated complete clone and regenerate the candidate there.
Do not overwrite a conflicting tag or reuse a stale assessment. When the default branch has moved,
prepare and review a new candidate from its current source. This check records two agreeing
observations, not an atomic reservation: state can change between reads or immediately afterward.
It cannot prove review readiness, release permissions, or consumer discovery. The publisher below
reserves the tag with a create-only operation and verifies the published result independently.

[ADR 0009](adr/0009-marketplace-remote-assessment.md) records this observation boundary.

## Create a version proposal through Actions

The proposal workflow prepares the next marketplace version from current main and the latest stable
published baseline. Manual dispatch defaults to read-only assessment:

```sh
gh workflow run propose-marketplace-release.yaml --repo devantler-tech/agent-plugins \
  --ref main -f ci-run=latest -F propose=false
```

It matches complete local and remote tag objects, the published baseline commit, immutable repository
identity and exact successful main push CI. It refuses an occupied proposal branch, candidate release
or an open PR touching either marketplace manifest. A complete unrelated PR is not a blocker. The
latest selector refuses a pending or failed latest CI run rather than finding an older green one.
For renamed PR files, complete REST filename/status records must match GraphQL before the original
paths are considered. Moving a manifest away is a conflict; complete unrelated renames are allowed.
The CI workflow identity accepts its plain path or the exact main-qualified forms
`.github/workflows/ci.yaml@main` and `.github/workflows/ci.yaml@refs/heads/main`.
Two agreeing observations and byte-exact private reconstruction are required. `NO_CHANGE` performs
no writes, including when proposal creation was requested. Evidence artifacts supply no write authority.
Read-only candidate-release visibility is the reader's projection; it does not establish visibility of
every draft release. The writer repeats occupancy checks with positively proven native write capability
before creating objects. `PREPARED` is an assessment, not a reservation or mutation clearance.

To deliberately create the reviewed-tooling proposal, use the same dispatch with **`-F propose=true`**.
The native Actions bot reconstructs its own candidate. It creates a new deterministic branch and a
GitHub-signed commit containing only the generated marketplace manifests, preserving individual
plugin versions. The expected parent prevents appending to another writer's branch. Independent
signature readback, a fresh fetch and exact release-tree verification precede draft creation.
Final readback binds the bot author, branch, source, commit, draft, title and plain-language body.
Only `CREATED` with `proposal: DRAFT_READBACK_VERIFIED` reports success.

The final job dispatches the existing `recheck-open-prs.yaml` on main so the normal App-backed reopen
starts fresh required PR checks. That dispatch reports a request, not successful CI. The draft still
requires current-head checks, substantive review, zero unresolved findings and normal promotion and
merge. It is never automatically promoted or merged, and proposal creation never reserves a release
tag or publishes a release.

Read-only local assessment uses the same command without write opt-in:

```sh
bash scripts/propose-marketplace-release.sh --repo devantler-tech/agent-plugins \
  --source <full-current-main-commit> --ci-run latest --output /tmp/marketplace-proposal
```

The CLI's `--propose` writer requires native Actions authentication. It refuses another actor before
creating a branch. Contents-write capability is positively checked without saving provider-generated
notes at each write phase. Preparation needs contents, actions and pull-request read permissions;
creation adds contents and pull-request write, while the separate CI dispatcher has only actions write.
Checkouts retain no credentials and read-only artifacts are never downloaded into the writer.
Final draft readback joins independent REST and GraphQL PR observations by their exact PR and
author node identities. The author must be REST `Bot` `github-actions[bot]` and GraphQL `Bot`
`github-actions`; missing identities, human actors or mismatched projections are refused.

Scheduled proposal creation runs hourly at minute 35 UTC only when `MARKETPLACE_AUTOPROPOSE` is
exactly `true`. Missing, false or any other value disables scheduled work. This variable is independent
of publication's flag. Both remain default-off; rollout and eventual removal are tracked in #277.
All armed manual and scheduled runs share one writer queue. Read-only assessments use a separate
queue and cannot displace a queued writer; an active writer is never cancelled by a newer dispatch.

### Recover a partial proposal

Branch creation, signed commit creation and draft creation are separate create-only operations. A
failed response can follow a successful write. The tool never retries, updates, deletes or adopts
existing remote objects. On failure it names the repository, branch and source to inspect; it emits
no delivered result. Retain the candidate, inspect the actual branch and any draft, and independently
verify their parent, two-manifest tree and author before choosing an operator recovery. Preserve a
competing writer's objects. A later invocation refuses an occupied or partially created branch;
rerunning it is not a resume operation. Main advancement requires a fresh candidate and readiness.
If the candidate tag is already occupied, use the explicit historical inspection above for local
content evidence; its result does not authorize resuming the partial writer.

[ADR 0014](adr/0014-create-only-marketplace-proposals.md) records this boundary.

## Publish the reviewed commit

First establish genuine readiness at the final merged commit: successful repository validation and
required CI, completed current-head review with no unresolved findings, and the deployment's authority
to release it. Neither a candidate nor a successful assessment establishes those independent gates.
Use reviewed tooling from a complete clone and independently select the repository and full commits.

Run the publisher without its write option for another read-only assessment:

```sh
bash scripts/publish-marketplace-release.sh \
  --repo devantler-tech/agent-plugins \
  --candidate /tmp/marketplace-next \
  --source <full-reviewed-source-commit> \
  --release <full-merged-release-commit>
```

To deliberately publish, add **`--publish`** to that same command. It regenerates a private candidate
from the verified Git objects, assesses fresh remote state, reserves the tag at the selected commit,
and creates a public, non-draft release. Publication notes render the verified plan's escaped commit
subjects and plugin inventory with source/release identities; the proposal-only warning is not used
as a published release description. GitHub's version-based latest-release selection is used.

Both remote writes are create-only, attempted once. Existing tags or releases are never updated,
deleted or reused, even if they appear to match. A fresh read between writes checks the default branch,
reserved tag and absent release. Each phase also re-reads effective native permissions and binds
both API identities to the immutable repository ID established during assessment and repeats the
nonpersistent capability check. Losing permission
or changing repository identity stops publication. A final independent read verifies the published release ID, notes,
tag commit and URL. Only exit zero with `status: PUBLISHED` and `scope: remote-publication-readback`
reports successful publication. The default mode retains `publication: NOT_AUTHORIZED` and makes no
remote writes. No scheduled publishing workflow is enabled.

After success, verify an actual consumer against the release tag and resolve its installed provenance
back to the reported release commit. Native plugin discovery and updates depend on the chosen runtime;
publication does not modify installed caches. For a skills-only smoke test in a disposable directory:

```sh
gh skill install devantler-tech/agent-plugins \
  plugins/agentic-engineering/skills/agent-instructions \
  --pin v1.0.0 --dir /tmp/marketplace-release-smoke
```

Replace the example tag with the verified published tag. Check the installed file and provenance;
the install command exiting successfully alone is not sufficient.

### Recover a partial attempt

A failed write response may still mean the write succeeded. On any failure after a write was attempted,
the command prints the repository, tag and exact commit to investigate. It emits no success result and
never retries or rolls back automatically. Inspect that tag and both draft/published release state with
write-capable visibility before deciding what to do. Preserve a conflicting writer's objects. An
existing reservation requires an operator decision; rerunning the command does not resume it.

Remote reads and the two writes are not atomic. A competing writer or default-branch movement can
make a later check fail after the tag or release exists. A nonzero exit is not proof of absence. Record
the observed state, restore correctness through the normal reviewed procedure, and independently
verify any manual recovery. Discarding an unused local candidate needs no repository rollback.

[ADR 0008](adr/0008-marketplace-release-preparation.md) defines this boundary.
[ADR 0010](adr/0010-create-only-marketplace-publication.md) records the publication and recovery rules.
[ADR 0013](adr/0013-native-publication-permission-proof.md) records the native permission and identity proof.
