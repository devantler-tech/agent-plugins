# Repository scripts

Use this guide to find the right kind of helper. The [scripts directory](../scripts/) is the
complete inventory; read a script's header for its arguments and safeguards.

| Task | Start here |
|---|---|
| Check a change | Follow the [validation steps](validation.md), including dependency installation |
| Review plugin use and usefulness | [Plugin effectiveness](plugin-effectiveness.md) and `bash scripts/plugin-scorecard.sh`; reads native exports and benchmark artifacts without configuring telemetry |
| Update versions and release notes | Use [bump-plugin-version.sh](../scripts/bump-plugin-version.sh) and add a matching changelog entry; skill syncs use [plugin-changelog.sh write](../scripts/plugin-changelog.sh) |
| Refresh generated resource digests | [refresh-desired-state-digests.sh](../scripts/refresh-desired-state-digests.sh) |
| Synchronize one curated plugin | Dispatch [Update Agent Skills](../.github/workflows/update-agent-skills.yaml) with `agentic-engineering`; [skill-update-scope.sh](../scripts/skill-update-scope.sh) resolves only declared selections before the normal per-skill updater runs. Default and scheduled `all` updates still cover the full catalogue. |
| Prepare or inspect a marketplace release | [Release guide](marketplace-releases.md) and [prepare-marketplace-release.sh](../scripts/prepare-marketplace-release.sh) |
| Propose or publish a marketplace release | [Release guide](marketplace-releases.md), which explains the separate opt-in steps and recovery |

The directory also contains checks for package discovery, skill provenance, licensing and authoring rules,
version changes, changelogs, generated writes, release observations and instruction size.
The [validation guide](validation.md) explains which checks to run and what they establish.

The scope resolver also passes any reviewed skill hold, as `<skill-dir> <commit>`, to
full-catalogue and `agentic-engineering` updates. None is held today: the temporary `git-commit`
hold from [platform#5224](https://github.com/devantler-tech/platform/issues/5224) ended under
[#598](https://github.com/devantler-tech/agent-plugins/issues/598) once upstream repaired the skill.
Deleting a hold's declaration alone leaves native pinned metadata in place, so releasing one also
takes a single manual dispatch of the updater with `unpin` set. That run proposes releasing every
skill pinned in its metadata, including `check-skills` at its release tag: close the proposal for
any pin that should stay.

Files ending in `.test.sh` contain regression cases. Shared `.lib.sh`, `.jq`, `.cjs` and Go
files support the helpers; they are not all standalone commands. Follow the calling script's
header rather than running each file in the directory.

The skill updater publishes digest, version and release-note follow-ups together through
[`publish-skill-metadata.sh`](../scripts/publish-skill-metadata.sh). It uses the existing App's
signed commit API, pins the observed parent, and verifies the complete result tree and signature
before reporting success. Only the selected plugin's generated metadata may change. No-op runs
make no forge calls; uncertain writes require inspection rather than an automatic retry.
Run `bash scripts/publish-skill-metadata.test.sh` for its offline request, scope and readback cases.

[`AGENTS.md`](../AGENTS.md) holds the repository's contribution and maintenance rules.
