# Repository scripts

What the main files under `scripts/` are for. A `*.test.sh` beside a script is its self-test, and
CI runs it. This list is kept by hand and can lag: the directory itself is the complete list.
[`AGENTS.md`](../AGENTS.md) links here; [validation](validation.md) lists the commands.

```text
scripts/
├── validate-manifests.sh       # Manifest + parity + plugin.json + catalogue-table + skill-provenance guard (single source of truth; run locally before pushing)
├── validate-manifests.test.sh  # Self-test: PASS a consistent fixture, FAIL each drift scenario the guard catches
├── check-plugin-version-bump.sh      # Gate: a plugin whose shipped content changed must move its version
├── check-plugin-version-bump.test.sh # Self-test for the gate above
├── plugin-version-boundaries.test.sh # Original Git identity, complete inventories and contained writes
├── plugin-version.lib.sh       # Shared canonical manifest versions and original-history observations
├── plugin-changelog.sh             # Write skill-sync release notes and check changed-version entries
├── plugin-changelog.test.sh        # Offline Git fixtures for release-note generation and checks
├── plugin-changelog-boundaries.test.sh # Exact objects, complete observations and failed-write recovery
├── changelog-headings.cjs          # CommonMark release-heading inventory used by writer and gate
├── guard-bundled-skill-edits.sh      # Gate: refuse a hand-edit to a synced skill tree, naming its upstream
├── guard-bundled-skill-edits.test.sh # Self-test for the gate above
├── guard-gh-json-fields.sh     # Gate: refuse a bundled definition that requests the nonexistent gh `merged` field
├── guard-gh-json-fields.test.sh # Self-test for the gate above
├── gh-json-go/                # Syntax-only Go guidance decoder and its tests; never executes scanned source
├── recheck-open-prs.sh         # Re-trigger every open PR's checks after a CI gate changes on main
├── recheck-open-prs.test.sh    # Self-test for the recheck above (stubs `gh`; no network)
├── bump-plugin-version.sh      # Move a plugin's version across all four manifests (the fix the gate points at)
├── bump-plugin-version.test.sh # Self-test for the bump helper
├── prepare-marketplace-release.sh # Offline version proposal, manifests and release notes from Git objects
├── marketplace-release.jq      # Candidate validation, version calculation and notes rendering
├── graphql-observation.jq      # Shared successful-envelope shape for proposal/publication observations
├── prepare-marketplace-release.test.sh # Real-history release and refusal cases
├── inspect-marketplace-release.sh # Read-only historical inspection behind --inspect-existing
├── inspect-marketplace-release.test.sh # Occupied tags, immutable caller state and refusal cases
├── check-marketplace-version.sh # PR gate: reproduce and verify any marketplace version proposal
├── check-marketplace-version.test.sh # Real branch histories, stale proposals and malformed input
├── prepare-merged-marketplace-release.sh # Reconstruct a merged proposal with exact successful main CI
├── prepare-merged-marketplace-release.test.sh # Real proposals and offline CI/ref movement cases
├── marketplace-publication-workflow.test.sh # Actual workflow guards, default-off and opt-in event matrix
├── propose-marketplace-release.sh # Current-main reconstruction and create-only signed draft proposals
├── propose-marketplace-release.test.sh # Real histories and offline proposal/ref/readback refusals
├── marketplace-proposal.jq # Complete repository-bound proposal observations and draft readback
├── marketplace-proposal-workflow.test.sh # Proposal event, permission and normal-CI dispatch guards
├── marketplace-permissions.jq # Native writer capability and immutable repository identity checks
├── refresh-desired-state-digests.sh      # Writer: recompute every digest a *.desired-state.json pins (the fix "digest must match" points at)
├── refresh-desired-state-digests.test.sh # Self-test for the generator, incl. its coupling to the validator
├── check-instruction-size.sh      # Gate: AGENTS.md stays under the 32 KiB Codex reads, and every guide it indexes exists
├── check-instruction-size.test.sh # Self-test for the gate above
└── sha256.lib.sh               # The two hashing rules, sourced by BOTH the validator and the generator so they cannot drift
```
