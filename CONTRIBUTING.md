# Contributing to Agent Plugins

Documentation corrections, useful bundle suggestions, and focused tests are welcome. Start with an
[issue](https://github.com/devantler-tech/agent-plugins/issues) before a substantial change so its
purpose and ownership are clear. For sensitive vulnerabilities, use
[private reporting](https://github.com/devantler-tech/agent-plugins/security/advisories/new), not a
public issue or pull request.

## Try a small documentation change

You need Git, Bash, jq, Node.js 22 or later with npm, and Go 1.22 or later. The package checks fetch
public upstream Git objects to verify licensing, so internet access is required. No production
credentials, cluster, publishing access, or submodule setup is needed for this path.

Fork this repository on GitHub. Replace `YOUR-LOGIN` below with your login, then run:

```sh
git clone https://github.com/YOUR-LOGIN/agent-plugins.git
cd agent-plugins
git switch -c docs/first-contribution
npm ci --ignore-scripts --no-audit --no-fund
```

Make a small wording correction in `README.md` or the installation guide. From the repository root:

```sh
bash scripts/validate-manifests.sh
bash scripts/check-instruction-size.sh
git diff --check
```

The checks should exit successfully: the marketplace, catalogue and packaged resources must agree,
and the canonical instruction file must fit its supported size. These are a useful first checkpoint,
not the complete pre-PR validation matrix. Follow [Validation](docs/validation.md) before submitting;
CI also runs the required specification checks and regression tests. A documentation check does not
prove that a plugin was loaded successfully in your assistant.

## Change the right source

Every bundled skill records its original repository in `metadata.github-repo`. Fix that skill there,
not in `plugins/*/skills/*`: the updater replaces those copies. New skills must be installed with
`gh skill install` (GitHub CLI 2.90 or later), not copied by hand.

Bundle membership and marketplace documentation are authored here. If you change shipped plugin
content, update both marketplace manifests, the portable and strict plugin manifests, and the
catalogue together. Use `bash scripts/bump-plugin-version.sh <plugin> minor` for an additive skill.
Commit the new skill trees first: the release-note writer reads committed provenance, not unstaged
files. Then run `bash scripts/plugin-changelog.sh write origin/main`, inspect its output, and include
the generated changelog in a follow-up commit before opening the PR.
The [repository contract](AGENTS.md) and [script guide](docs/scripts.md) describe the full rules;
plugin content without a version increase will stay stale in consumers' caches.

## Submit your change

Use explicit paths when staging, configure commit signing, and write a Conventional Commit subject:

```sh
git add README.md
git commit -S -m "docs: clarify the first installation step"
git push -u origin docs/first-contribution
```

Adjust the staged path and subject to match your change. Open a **draft** pull request from your
fork's branch to `devantler-tech/agent-plugins:main`, use the supplied PR template, and link the issue
for substantial work. Explain the reader problem, the outcome, and the checks you actually ran.
Follow the [organization code of conduct](https://github.com/devantler-tech/.github/blob/main/.github/CODE_OF_CONDUCT.md),
retain [license and attribution obligations](LICENSE), and disclose AI assistance when applicable.
Respond to findings; CI and an exact-current-head review must pass before merge. Release preparation
and publication are separate [maintainer operations](docs/marketplace-releases.md), not contribution
setup steps.
