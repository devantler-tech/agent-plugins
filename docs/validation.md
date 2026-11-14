# Validation

Every command that validates a change, what each check observes, and how a new CI gate reaches
pull requests that are already open. [`AGENTS.md`](../AGENTS.md) links here.

Run before opening any PR. Steps 1–2 mirror the CI gates; step 3 is a best-effort local lint that CI
does not currently enforce but that keeps workflow changes clean:

The generated version, digest and changelog writers also need Go 1.22 or later.
Their shared writer pins each operation to a real checkout directory, so a concurrent
ancestor replacement cannot redirect publication or recovery through a symlink.
Moved directories retain their staging and original files for operator recovery.

The JSON-field guard needs Go 1.22 or later for every scanned surface. It builds only
its installed observer, joins adjacent literal shell quotes without evaluation, requires unique
decoded JSON keys, reads Go comments and decoded literal strings/argument blocks, and never
executes the inspected package. Native skill YAML metadata is observed as block mappings with
single-line plain/quoted scalar values, comments and literal text blocks. Double-quoted escapes
use the JSON-compatible subset. Repeated decoded keys, sequences, flow collections, aliases,
tags, folded blocks and multiline plain/quoted scalars remain UNKNOWN.
Unresolved groupings beside a known JSON flag, malformed source,
incomplete decoding, or exhausted source/decoded-work budgets stay UNKNOWN. This is not analysis of
arbitrary Go runtime behavior.

CI installs the pinned spec validator through `scripts/install-skills-ref.sh`, with at most three
attempts and 5/10-second backoff. A persistent installation failure blocks the job; skill validation
runs once after installation and remains required. `scripts/install-skills-ref.test.sh` exercises
recovery and failure offline in `lint-scripts`.

The validator judges each skill through `scripts/skill-spec-view.sh`, which copies the skill and
drops exactly two top-level frontmatter fields the spec does not define, `argument-hint` and
`user-invocable`. Claude Code and VS Code both read them, and Anthropic's own skills use them. The
maintainer chose to accept those two on 2026-11-04 so such skills can be bundled unmodified. Every
other field, and every other spec rule, is still checked. The view refuses to strip a field it
cannot remove whole: a block, empty, flow, anchored or tagged value, a quote that does not close
on its line, a continuation line, even after a blank or comment line, or a repeat. CI then reads
both the skill and its view with `skills-ref read-properties` and fails unless they match, so the
view can never hand the validator frontmatter the skill does not have.
`scripts/skill-spec-view.test.sh` covers the view, and
`scripts/ci-skill-validation-workflow.test.sh` keeps the CI job on both checks.

```bash
# Install the pinned parser for changelog checks and the offline regression suite (Node.js 22+).
npm ci --ignore-scripts --no-audit --no-fund

# Offline native usage attribution and benchmark score reporting.
bash scripts/plugin-scorecard.test.sh

# 1. Marketplace parity, portable ↔ strict-Claude plugin.json parity, catalogue table,
#    desired-state resources, and skill provenance — the exact checks CI's
#    "Validate manifests" job runs.
./scripts/validate-manifests.sh
# Every bundled skill keeps its own license (CI's "Check bundled skill licenses" step). A third-party
# skill needs a row and a `## <owner>/<repo>` section with its copyright notice and license text in
# plugins/<plugin>/resources/THIRD-PARTY-NOTICES.md; every skill needs a row in docs/plugins.md.
bash scripts/check-skill-licenses.sh
bash scripts/check-skill-licenses.test.sh
# A first-party skill's references sit one level deep and are linked from its entry file, and its
# description stays inside the limit (CI's "Check first-party skill authoring rules" step). Needs
# jq and the Go yq. Exceptions, each with its reason: scripts/skill-authoring-exceptions.json.
bash scripts/check-skill-authoring.sh
bash scripts/check-skill-authoring.test.sh
# Remote MCP URL syntax uses the repository-local Go helper (Go ≥1.22, standard library only).
GOENV=off GOWORK=off GO111MODULE=off GOTOOLCHAIN=local GOFLAGS='' CGO_ENABLED=0 \
  go test scripts/mcp-url-go/main.go scripts/mcp-url-go/main_test.go

bash plugins/agentic-engineering/scripts/assess-autonomy.test.sh # optional copied consumer; always assessment-only
GOENV=off GOWORK=off GO111MODULE=off GOTOOLCHAIN=local go test ./plugins/agentic-engineering/scripts/autonomy-contract-go

# 1b. Every plugin whose shipped content changed must also move its version, or the change
#     never reaches consumers that cache by version (CI's "Check version bump" job).
#     Fix a failure with: ./scripts/bump-plugin-version.sh <plugin> [patch|minor|major]
./scripts/check-plugin-version-bump.sh origin/main HEAD
bash scripts/plugin-changelog.sh check origin/main HEAD
bash scripts/plugin-changelog.test.sh
bash scripts/plugin-changelog-release-boundaries.test.sh # caller identity, committed provenance and safe release writes

# 1c. Every content digest a desired-state resource pins must match the file it pins.
#     Those digests have a writer: refresh them rather than hand-editing, or the next
#     skill synchronization replaces manual edits. --check reports without writing.
#     The writer completes every inventory and digest before its first resource write;
#     independently verifies the direct resource inventory, refuses linked roots and
#     repeated declaration paths, checks declaration shapes and unique asset paths,
#     and binds each runtime asset's executable permission to its declaration.
#     failed observations or missing targets leave all resources unchanged.
./scripts/refresh-desired-state-digests.sh --check
bash scripts/generated-write-safety.test.sh # resource refusal and failed batch-write recovery

# 1d. Offline marketplace candidate preparation: real Git histories, no publication.
# Source manifests and every native release/proposal observation require unique decoded
# object keys before semantic checks, including objects inside paginated arrays. Stable
# versions contain no whitespace or line terminators. Partial-write ambiguity remains
# uncertain and preserves remote objects for explicit recovery.
bash scripts/marketplace-caller-context.test.sh # inherited Git selectors cannot redirect caller evidence
bash scripts/prepare-marketplace-release.test.sh
bash scripts/release-observation-boundaries.test.sh # original Unicode, census completeness and reserved output identity
bash scripts/verify-marketplace-release.test.sh # artifact reproduction and exact release-tree binding
bash scripts/inspect-marketplace-release.test.sh # historical content, occupied tags and caller-state preservation
bash scripts/check-marketplace-release-remote.test.sh # remote state, pagination and movement; offline forge
bash scripts/publish-marketplace-release.test.sh # opt-in publication, competing writers and readback; offline forge
bash scripts/prepare-merged-marketplace-release.test.sh # exact main CI and fresh proposal reconstruction
bash scripts/marketplace-publication-workflow.test.sh # actual workflow authorization and permission branches
bash scripts/propose-marketplace-release.test.sh # signed draft creation and complete readback; offline forge
bash scripts/marketplace-proposal-workflow.test.sh # default-off proposal and CI dispatch boundaries
bash scripts/publish-skill-metadata.test.sh # scoped App-signed requests and complete readback; offline forge

# 1e. AGENTS.md is loaded by every session and must stay under the 32 KiB Codex reads;
#     every guide its "Agent guides" table links must exist.
./scripts/check-instruction-size.sh
bash scripts/check-instruction-size.test.sh

# 2. Validate each bundled skill against the agentskills.io spec (the consolidated CI check). Pin to the
#    SAME agentskills commit CI uses (AGENTSKILLS_REF in .github/workflows/ci.yaml) so local matches CI.
AGENTSKILLS_REF=8d8fcbc69e0c42e05922c2ffc287a3bbdef7b0a3 bash scripts/install-skills-ref.sh
views=$(mktemp -d)
find plugins -mindepth 4 -maxdepth 4 -name SKILL.md -exec sh -c '
  views=$1; shift
  for skill_file do
    skill=${skill_file%/SKILL.md}
    view=$(bash scripts/skill-spec-view.sh "$skill" "$views/$(printf %s "$skill" | tr / _)") || exit
    skills-ref read-properties "$skill" > "$views/original.json" || exit
    skills-ref read-properties "$view" > "$views/view.json" || exit
    cmp -s "$views/original.json" "$views/view.json" || { echo "view differs: $skill"; exit 1; }
    skills-ref validate "$view" || exit
  done
' sh "$views" {} +

# 3. (local only) Lint changed workflows.
actionlint
```

Step 1 deliberately calls the script rather than restating its checks: it is the single source of
truth CI runs, and a hand-copied version of it drifts. It did — the snippet that used to live here
asserted `.skills == "skills/"` in every `plugin.json`, long after the convention moved to omitting
that field (skills are auto-discovered), so following this document reported all 8 plugins broken
while CI was green (#65).

The validator retains marketplace entries, catalogue rows, desired-state resources, runtime assets,
schedule sources and skill provenance only after their inventory commands succeed. Failed empty or
partial observations refuse validation; complete empty selections remain valid where resources are
optional. Filesystem inventories preserve complete filenames with NUL-delimited records.

Agent identity and installed-source checks share a minimum frontmatter observer. It requires a
closed header, unique top-level keys, text-valued agent identity, and a usable GitHub repository at
the direct `metadata.github-repo` key. Plain identity values reject reserved YAML indicators and
mapping separators. Literal and folded identity blocks require a valid single indentation/chomping
declaration and content meeting the declared or inferred indentation. Unsupported header syntax is
refused; this observer does not replace the skill specification validator. The bundled-edit guard uses
the same source observation
at the base commit and preserves whole path components, including embedded and trailing newlines. Body examples
never supply provenance, and malformed base provenance remains UNKNOWN.

The required gate is the aggregated **`CI - Required Checks`** job. It requires retired-repository
link checks, manifest validation, script lint/tests, marketplace tests, package tests, version/changelog
checks, the bundled-skill edit guard, and skill-spec validation. The exact dependency list lives in
[`ci.yaml`](../.github/workflows/ci.yaml); `actionlint` above is a local-only convenience, not a CI gate. Never
weaken a check to pass — fix the root cause.

**A new gate applies to open PRs through the merge queue.** `main` requires a merge queue (declared in
devantler-tech/.github `deploy/repository-rulesets/require-merge-queue-on-agent-plugins.yaml`). The queue
runs `CI - Required Checks` on the exact commit each queued PR would land as, so a PR opened before a
gate reached `main` still has to pass that gate before it merges. CI runs on `merge_group` for this;
PR-only steps such as the bundled-skill edit guard have already passed on the PR before it can join the
queue. Merge with `gh pr merge <n> --match-head-commit <sha>` (no `--squash`: the queue squashes).
