# Repository scripts

Use this guide to find the right kind of helper. The [scripts directory](../scripts/) is the
complete inventory; read a script's header for its arguments and safeguards.

| Task | Start here |
|---|---|
| Check a change | Follow the [validation steps](validation.md), including dependency installation |
| Update versions and release notes | Use [bump-plugin-version.sh](../scripts/bump-plugin-version.sh) and add a matching changelog entry; skill syncs use [plugin-changelog.sh write](../scripts/plugin-changelog.sh) |
| Refresh generated resource digests | [refresh-desired-state-digests.sh](../scripts/refresh-desired-state-digests.sh) |
| Synchronize one curated plugin | Dispatch [Update Agent Skills](../.github/workflows/update-agent-skills.yaml) with `agentic-engineering` or `engineering-practices`; [skill-update-scope.sh](../scripts/skill-update-scope.sh) resolves only declared selections before the normal per-skill updater runs. Default and scheduled `all` updates still cover the full catalogue. |
| Prepare or inspect a marketplace release | [Release guide](marketplace-releases.md) and [prepare-marketplace-release.sh](../scripts/prepare-marketplace-release.sh) |
| Propose or publish a marketplace release | [Release guide](marketplace-releases.md), which explains the separate opt-in steps and recovery |
| Recheck open pull requests after changing CI | [recheck-open-prs.sh](../scripts/recheck-open-prs.sh) |

The directory also contains checks for package discovery, skill provenance and licensing,
version changes, changelogs, generated writes, release observations and instruction size.
The [validation guide](validation.md) explains which checks to run and what they establish.

Files ending in `.test.sh` contain regression cases. Shared `.lib.sh`, `.jq`, `.cjs` and Go
files support the helpers; they are not all standalone commands. Follow the calling script's
header rather than running each file in the directory.

[`AGENTS.md`](../AGENTS.md) holds the repository's contribution and maintenance rules.
