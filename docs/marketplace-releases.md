# Marketplace releases

A marketplace version describes the whole catalogue at one commit of `main`. It is the
`.metadata.version` in both marketplace manifests, and each release is tagged `vX.Y.Z`. Each plugin
keeps its own version, which is its runtime cache key; the marketplace version does not replace it.

## How a release happens

[release-please](https://github.com/googleapis/release-please) cuts releases from the Conventional
Commit titles that squash merges leave on `main`. The
[Release Please workflow](../.github/workflows/release-please.yaml) runs on every push to `main`:

1. It opens or updates one **release PR**. The PR moves `.metadata.version` in
   [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) and
   [`.github/plugin/marketplace.json`](../.github/plugin/marketplace.json) together, and its body holds
   the release notes. The repository's GitHub App opens it, so normal CI runs on it.
2. The release PR is an ordinary pull request. Review it like any other, and merge it when the
   release should go out. Until then it keeps collecting the changes that land on `main`.
3. Merging it tags the merge commit `vX.Y.Z` and publishes a GitHub release with the same notes.
   GitHub Actions creates the tag, which is the only identity allowed to create `v*` tags here.

The version follows the commits merged since the last release:

| Commit title | Result |
| --- | --- |
| A breaking `!` header or a `BREAKING CHANGE:` footer | Major |
| `feat:` | Minor |
| `fix:`, `perf:` or `revert:` | Patch |
| Other types, such as `chore:`, `docs:` or `ci:` | No release on their own |

The configuration is in [`release-please-config.json`](../release-please-config.json): a single root
package with the `simple` release type, tags without a component, and no root changelog. The last
released version is recorded in [`.release-please-manifest.json`](../.release-please-manifest.json);
release-please updates it in each release PR. Never edit either manifest's `.metadata.version` by
hand.

## What stays with each pull request

Release-please does not move plugin versions. A PR that changes a plugin's shipped content still
bumps that plugin with [`scripts/bump-plugin-version.sh`](../scripts/bump-plugin-version.sh) and adds
a matching entry to `plugins/<plugin>/CHANGELOG.md`. CI's **Check version bump** job enforces both;
see [validation](validation.md).

## Install a released version

Consumers can pin a release tag. For a skills-only smoke test in a disposable directory:

```sh
gh skill install devantler-tech/agent-plugins \
  plugins/agentic-engineering/skills/agent-instructions \
  --pin v2.2.0 --dir /tmp/marketplace-release-smoke
```

Replace the example tag with the release you are checking, then check the installed file and its
provenance; the command exiting successfully is not enough on its own.

Earlier releases were cut by a custom preparation, proposal and publication toolchain. The ADRs under
[`docs/adr/`](adr/) from 0008 to 0015 record that history.
