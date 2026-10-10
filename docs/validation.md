# Validation

Every command that validates a change, in the order CI runs them, what each check observes,
and how a new CI gate reaches pull requests that are already open. [`AGENTS.md`](../AGENTS.md) links here.

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

```bash
# Install the pinned parser for changelog checks and the offline regression suite (Node.js 22+).
npm ci --ignore-scripts --no-audit --no-fund

# 1. Marketplace parity, portable ↔ strict-Claude plugin.json parity, catalogue table,
#    desired-state resources, and skill provenance — the exact checks CI's
#    "Validate manifests" job runs.
./scripts/validate-manifests.sh
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
#     agent-skills sync force-pushes the hand edit away. --check reports without writing.
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

# 1e. AGENTS.md is loaded by every session and must stay under the 32 KiB Codex reads;
#     every guide its "Agent guides" table links must exist.
./scripts/check-instruction-size.sh
bash scripts/check-instruction-size.test.sh

# 2. Validate each bundled skill against the agentskills.io spec (the consolidated CI check). Pin to the
#    SAME agentskills commit CI uses (AGENTSKILLS_REF in .github/workflows/ci.yaml) so local matches CI.
AGENTSKILLS_REF=8d8fcbc69e0c42e05922c2ffc287a3bbdef7b0a3 bash scripts/install-skills-ref.sh
find plugins -mindepth 4 -maxdepth 4 -name SKILL.md -printf '%h\n' | while read -r d; do skills-ref validate "$d"; done

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

The required gate is the aggregated **`CI - Required Checks`** job (validate-manifests +
validate-spec); `actionlint` above is a local-only convenience, not a CI gate. Never
weaken a check to pass — fix the root cause.

**Adding a gate does not retroactively apply it to open PRs — the recheck workflow is what does.**
A pull-request workflow runs only on that PR's own `pull_request` events, so every PR already open
when a new job joins `CI - Required Checks` keeps the green it earned *before* that job existed, and
the branch rule keyed on the check's name is satisfied by the stale run. Such a PR can merge without
the new gate ever running against it — which is how a stale plugin version or a hand-edited synced
skill would reach consumers past the very checks added to stop them.
[`recheck-open-prs.yaml`](../.github/workflows/recheck-open-prs.yaml) closes that window: **every push
to `main`** re-triggers every open PR's checks, and it can also be dispatched by hand with a
`dry-run` input to see what a sweep would touch. So **when you add or alter a required job, the
recheck is the mechanism that makes it apply to work already in flight** — there is nothing extra to
remember, but there is something to notice if it ever stops running.

It sweeps unconditionally because deciding *whether* a gate changed cannot be made correct here, and
three narrower designs were tried and rejected: a `paths:` filter is capped at 300 files, so a large
sync can change `ci.yaml` without the filter seeing it; diffing the pushed range loses a push the
concurrency group coalesced away; and testing `ci.yaml` alone misses a gate strengthened in its
*implementation*, since that file runs `validate-manifests.sh` and friends and a new rejection there
changes what the required check accepts while `ci.yaml` is untouched. Each blind spot is silent,
which is worse than no trigger. **If you narrow this trigger, you are re-opening one of those three.**

[`recheck-open-prs.sh`](../scripts/recheck-open-prs.sh) refreshes **same-repository branches** through
GitHub's update-branch API with the observed head as its concurrency guard. It verifies that the
result contains both the old head and current base, preserves auto-merge settings, and observes a
fresh PR workflow event. An updated head requires a new current-head review before merge;
existing commits are retained. Current non-Dependabot branches use the reopen route to ensure
App-created drafts receive their required PR CI event.

**Forks** use close and immediate reopen, which preserves their head and current-head review.
Every reopen requires a newer PR event and a matching OPEN readback of head, base, author and
merge state, including when auto-merge was unarmed. Unknown merge strategies refuse mutation;
restoring a known strategy also pins the observed head. The restored request is read back before
completion is counted.
**Dependabot PRs are never closed or recreated:** closing can suppress a wanted update, so a
Dependabot fork is reported as a failure and left untouched. Unknown author or repository-boundary
data, failed updates and incomplete readback likewise cannot report a successful refresh.
For a current Dependabot branch, the helper observes a PR workflow run at that head and verifies
the head includes the current named base. Missing event evidence is a failure, not a reason to close it.

Re-running an old workflow replays its original merge revision; it does not apply a new gate.
These refresh routes use an App token because `GITHUB_TOKEN` events start no new workflow runs.
For the fork route, a previously armed auto-merge is restored with its original strategy and message
only after a fresh PR event is observable. An unarmed request is never armed, and missing event
evidence prevents restoration. The hermetic tests cover both routes, real commit ancestry,
Dependabot protection, recovery and incomplete observations.

GitHub's own mechanism for this is `strict_required_status_checks_policy` — "require branches to be up
to date before merging" — which would block a stale PR outright rather than re-running it. It is
declared **org-wide and `Observe`-only** in `devantler-tech/.github`, so turning it on is a maintainer
decision affecting every repository, not this one's to make; the workflow above is the
repository-scoped equivalent.
