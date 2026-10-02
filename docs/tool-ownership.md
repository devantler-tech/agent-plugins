# Marketplace tool ownership and callers

This assessment freezes the marketplace at
[`00519de5b7836402c087e99c3e498e8e3ab97ed2`](https://github.com/devantler-tech/agent-plugins/tree/00519de5b7836402c087e99c3e498e8e3ab97ed2)
and the skill source at
[`5d61a1157328fd1f84218d2509b085cff64ecd52`](https://github.com/devantler-tech/agent-skills/tree/5d61a1157328fd1f84218d2509b085cff64ecd52).
It records the 2026-10-02 decisions for
[tool maturation](https://github.com/devantler-tech/agent-plugins/issues/102) and the bounded
[shared-code assessment](https://github.com/devantler-tech/agent-plugins/issues/103).
These are the observed repository contracts, not a claim of complete portfolio usage or adoption.

## Coverage and method

The installed census selected every tracked regular non-test `*.sh` file at the frozen revisions:
24 marketplace paths and six source paths. Its complete Git leaf listing agreed with an independent
raw diff. Complete tree listings separately identified three non-test Go entrypoint files across
the two repositories: the source entrypoint classifier, its bundled copy and the marketplace's
guidance decoder. All three were read as source. No surveyed Go program ran during the assessment.
Tests, build tasks, workflows, documentation and direct script calls were traced separately.

The 30 shell paths plus three Go files are file candidates, not 33 independent commands. The bundled
inventory wrapper and parser belong to their skill source. Tests are validation callers, not a second
product. Non-shell companion programs are included below so the extension-based census does not
hide their ownership. Inline workflow commands, test programs and JSON fixtures are calling or
validation surfaces, not separately promoted products.

Only these two repositories were examined. Undeclared dynamic callers, runtime registration and
external operational usage remain UNKNOWN. In particular, a shipped agent instruction or desired-state
registration requirement does not prove that a consumer has installed or exercised it. The
portfolio-wide inventory and real migration requirements on the umbrella issues remain open.

## Repository policy tools

Every path in this table is relative to `scripts/`. The destination is **stay repository-local**.
They compose existing Git, GitHub CLI, jq or a supported parser with marketplace-specific policy.
Their documented interfaces are supported here; none establishes an independent CLI product lifetime.

| Candidate | Observed caller and task | Ownership rationale |
|---|---|---|
| [`validate-manifests.sh`](../scripts/validate-manifests.sh) | CI, release preparation/publication workflows and maintainer instructions validate manifests, provenance and resource parity | Marketplace schema and consumer promises belong here. A generic schema checker does not replace the parity and provenance policy. |
| [`bump-plugin-version.sh`](../scripts/bump-plugin-version.sh) | Skill-update workflow and maintainer invocation move four related manifests together | Keep version selection with the four manifests. The assessment found failed Git observations could be accepted; [#319](https://github.com/devantler-tech/agent-plugins/issues/319) tracks the repair. |
| [`check-plugin-version-bump.sh`](../scripts/check-plugin-version-bump.sh) | CI compares a change with its merge base and requires changed plugin content to move version | The cache/version promise is marketplace policy. The same discovery failure is covered by #319; a language migration would not itself correct it. |
| [`guard-bundled-skill-edits.sh`](../scripts/guard-bundled-skill-edits.sh) | PR CI checks changed paths against base provenance and the authorized sync writer | Retain the source-ownership and writer rules here. Skill installation transport cannot decide this repository's editing exemption. |
| [`guard-gh-json-fields.sh`](../scripts/guard-gh-json-fields.sh) | CI checks agent-readable guidance for unsupported GitHub CLI fields | Keep the guidance policy and content-bound exemptions here; delegate Go syntax decoding to the adjacent parser. |
| [`gh-json-go/main.go`](../scripts/gh-json-go/main.go) | The guidance guard builds this installed decoder and passes retained Go source; CI also runs its tests | Retain Go for syntax/literal interpretation, using the standard library. It decodes source as data; it never builds the inspected package. |
| [`recheck-open-prs.sh`](../scripts/recheck-open-prs.sh) | The recheck workflow renews checks or refreshes a base under its exact-head and author rules | Keep forge orchestration with the owning workflow and GitHub CLI. Its branch-writing policy does not fit a cluster-management command; complexity alone does not establish a new CLI audience. |
| [`plugin-changelog.sh`](../scripts/plugin-changelog.sh) | Skill update writes notes; CI checks notes for changed plugin versions | Keep version/changelog policy here, reuse the locked CommonMark decoder for heading syntax rather than duplicating that grammar. |
| [`refresh-desired-state-digests.sh`](../scripts/refresh-desired-state-digests.sh) | Skill update recomputes declared resource digests; maintainers can check without writing | The writer must share hashing rules with the manifest validator; keep both under one repository owner. |
| [`sha256.lib.sh`](../scripts/sha256.lib.sh) | The validator and digest writer source the same hashing functions | Keep local sharing. Two callers within the marketplace are one product need, not evidence for a separate hashing library. |
| [`install-skills-ref.sh`](../scripts/install-skills-ref.sh) | Each spec-validation job installs the pinned skill validator with bounded recovery | Keep the CI dependency wrapper and its existing installer. Installing a validator is not independent product demand. |

## Marketplace release tools

These eight `scripts/` entrypoints also stay repository-local. GitHub CLI owns forge transport;
the marketplace owns version occupancy, content reconstruction and create-only publication policy.
Shared use of the release API does not make source-skill and marketplace publication interchangeable.

| Candidate | Observed caller and responsibility |
|---|---|
| [`prepare-marketplace-release.sh`](../scripts/prepare-marketplace-release.sh) | Preparation workflow, proposal helper, publication helper and merged-proposal verifier reproduce a candidate from exact Git history. The assessment found an unchecked second worktree census and newline-trimming output boundary; [#322](https://github.com/devantler-tech/agent-plugins/issues/322) tracks the repair. |
| [`verify-marketplace-release.sh`](../scripts/verify-marketplace-release.sh) | Proposal, publication and merged-proposal helpers verify candidate contents and commit relationships. Its explicit historical-inspection option delegates to the inspector. |
| [`inspect-marketplace-release.sh`](../scripts/inspect-marketplace-release.sh) | The verifier's opt-in historical path checks occupied releases without granting fresh publication readiness. |
| [`check-marketplace-version.sh`](../scripts/check-marketplace-version.sh) | PR CI and merged-proposal preparation check the proposed marketplace version against reproduced content. |
| [`check-marketplace-release-remote.sh`](../scripts/check-marketplace-release-remote.sh) | Publication helper and documented maintainer assessment inspect remote tag/release occupancy before a write. |
| [`prepare-merged-marketplace-release.sh`](../scripts/prepare-merged-marketplace-release.sh) | Publication workflow reconstructs the selected merged release with exact successful main CI. |
| [`propose-marketplace-release.sh`](../scripts/propose-marketplace-release.sh) | Proposal workflow assesses current main and separately opts into a signed, create-only draft proposal. |
| [`publish-marketplace-release.sh`](../scripts/publish-marketplace-release.sh) | Publication workflow separately opts into create-only publication after reproducing local and remote evidence. |

The distinct contracts separate read-only assessment from a separately authorized write.
Collapsing those boundaries into one apparently generic publisher is not a behavior-preserving extraction.

## Installed agent and skill helpers

These paths are relative to `plugins/agentic-engineering/`. Their destination is **stay with the
owning plugin or upstream skill**, released and installed as that resource rather than as a new CLI.

| Candidate | Declared caller and contract | Rationale |
|---|---|---|
| [`scripts/classify-default-branch-ci-runs.sh`](../plugins/agentic-engineering/scripts/classify-default-branch-ci-runs.sh) | Portfolio-surveyor asks for repository/default-branch/exact-head CI classification through the read-only guard | Keep portable classification with the agent contract; GitHub CLI supplies data, not the agent's verdict. Actual runtime wiring is a consumer responsibility. |
| [`scripts/count-unresolved-review-threads.sh`](../plugins/agentic-engineering/scripts/count-unresolved-review-threads.sh) | Portfolio-surveyor obtains a complete unresolved-thread count through the same guard | Keep pagination and unknown-evidence behavior with the survey contract. A zero from incomplete data cannot satisfy readiness. |
| [`scripts/forge-readonly-guard.sh`](../plugins/agentic-engineering/scripts/forge-readonly-guard.sh) | Agent instructions require a consumer-side pre-execution guard; the portable argument interface evaluates a candidate command | Keep the execution boundary with the installed agent assets. Moving it to another product would require proving registration and compatibility in each consumer. |
| [`scripts/surveyor-forge-readonly.sh`](../plugins/agentic-engineering/scripts/surveyor-forge-readonly.sh) | Desired state and the surveyor describe an optional structured-input adapter to the portable guard | Keep the adapter; it translates runtime input and delegates policy. It does not establish another guard implementation or authorize dispatching a surveyor. |
| [`scripts/evaluate-inference-routing.sh`](../plugins/agentic-engineering/scripts/evaluate-inference-routing.sh) | [Routing reference](../plugins/agentic-engineering/resources/inference-routing.md) evaluates reported policy/task/snapshot JSON offline | Keep the evaluator with the routing contract. A recommendation is not authenticated billing evidence and authorizes no inference launch. |
| [`skills/product-engineering/scripts/inspect-shell-helpers.sh`](../plugins/agentic-engineering/skills/product-engineering/scripts/inspect-shell-helpers.sh) | Installed tool-maturation procedure explicitly requests a revision-bound read-only census | Keep source ownership in Agent Skills; use normal sync for distribution. This copied wrapper is not an independent second consumer. |
| [`skills/product-engineering/scripts/go-entrypoint.go`](../plugins/agentic-engineering/skills/product-engineering/scripts/go-entrypoint.go) | The copied inventory wrapper's explicit Go mode builds only this installed parser | Keep with the same upstream skill. One source parser copied into a bundle is one policy owner. |

## Companion mechanisms and alternatives

The five local jq modules (`marketplace-release`, `marketplace-remote-state`, `marketplace-publication`,
`marketplace-proposal`, `marketplace-permissions`) are invoked by their release wrappers. They retain
marketplace policy: candidate calculation, remote occupancy, native identity/capability joins and
proposal/publication decisions. Keep them local. The CommonMark companion
[`changelog-headings.cjs`](../scripts/changelog-headings.cjs) is invoked by the changelog wrapper and
uses the locked existing parser; rewriting its grammar merely to change language is not a demonstrated
benefit. This assessment grants no new embedded-language exception.

The copied `measure-flow.jq`, `check-evidence.jq` and `accountability-brief.jq` retain their Agent Skills
owners and documented installed interfaces. Those distribution copies do not count as additional
independent product needs. The [source assessment](https://github.com/devantler-tech/agent-skills/issues/153)
records those contracts and the source repository's remaining helper decisions.

The two authored Go tools already share the standard library's `go/parser`, `go/ast` and `go/token`.
Keep the different entrypoint-classification and guidance-decoding policies local. No incompatible
common syntax need, module coupling or independent maintenance lifecycle was observed that requires
a new shared module. No shared authoritative state or hosted failure contract justifies a service.

GitHub CLI and Git already fit the observed transport and object-read tasks. KSail's cluster-management
purpose does not fit marketplace release, PR rewriting or agent execution-boundary policy. A new CLI
would require independent users, interface/support needs and distribution evidence not established
here. Existing-library reuse and local policy ownership are the chosen destinations; reconsider
only on a concrete new caller contract or measured coupling, rather than hypothetical demand.

## Delivery and remaining evidence

The version-tool failure was repaired in [#320](https://github.com/devantler-tech/agent-plugins/pull/320),
with before/after regressions and normal workflow callers. Release preparation's separate output
boundary finding is tracked by #322 with real linked-checkout fixtures. The syntax decoder is already adopted by the marketplace's actual guidance gate;
that is repository-local Go adoption, not publication of a standalone command. Retain the existing
wrappers and version pins as recovery paths when proposing any further migration.

The census invocation was exercised from the installed skill against both frozen repositories.
Optional Go execution was not repeated under the host's low-disk rule. Native CI validates syntax
decoders separately; neither it nor this assessment establishes consumer runtime registration,
the deferred comprehension pilot, a full portfolio survey or an independently installed new CLI.
The umbrella issues stay open for those named requirements. No repository, permission, runtime
registration, release-automation flag or service is created by this assessment.
