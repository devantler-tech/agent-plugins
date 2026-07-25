# ADR 0006 — Rename the primary engineer entrypoint to `agentic-engineer`

- **Status:** Accepted
- **Date:** 2026-07-25
- **Deciders:** devantler-tech maintainer
- **Supersedes:** [ADR 0004](0004-consolidate-agentic-engineering.md) where it kept the
  `automated-ai-engineer` agent name unchanged, and
  [ADR 0005](0005-merge-spend-stewardship-into-the-engineer.md) where it left entrypoint names
  unchanged while merging spend stewardship into that same role

## Context

[ADR 0004](0004-consolidate-agentic-engineering.md) consolidated the marketplace on a single
`agentic-engineering` plugin identity, but deliberately left the primary engineer's agent entrypoint
named `automated-ai-engineer` so that consolidation carried exactly one breaking change. That left
the role with two names: consumers install `agentic-engineering`, read about the *Agentic Engineer*
in prose, and then wire a schedule to an entrypoint called `automated-ai-engineer`.

The consuming deployment renamed the role itself to **Agentic Engineer**, so the identifier is now
the only surface still carrying the old name. A role whose identifier disagrees with its own
documentation is a standing source of onboarding confusion, and every new deployment pays that cost.
"Automated AI Engineer" also describes the mechanism (it is automated, it is AI) rather than the
thing that matters to a consumer — that it engineers agentically, on its own initiative, across a
portfolio.

## Decision

1. **The entrypoint is `agentic-engineer`.** The bundled agent file, its frontmatter `name`, the
   desired state's `spec.source.entrypoint`, its `spec.roles` key, and its
   `spec.runtime.scheduler.schedules` key all use `agentic-engineer`.
2. **The prose role name is "Agentic Engineer" everywhere.** This covers the agent definition, the
   surveyor that serves it, the bundled skills, and both READMEs.
3. **This is a major version.** The plugin goes to `4.0.0` — `3.0.0` is the spend-stewardship
   merge in ADR 0005: a persisted
   `plugin:agentic-engineering/automated-ai-engineer` schedule pointer or a qualified
   `agentic-engineering:automated-ai-engineer` agent reference stops resolving, and there is no
   marketplace-level rename migration for agent names the way `renames` provides for plugin names.
4. **No compatibility alias.** Consistent with ADR 0004's rejection of an alias bundle, a second
   agent file under the old name would reintroduce exactly the two-names ambiguity this ADR removes.
   The plugin README carries an explicit migration checklist instead.
5. **Historical records keep their original wording.** ADRs 0002–0005, the append-only marketplace
   `renames` map, and `scripts/marketplace-rename-history.json` are unchanged. Rewriting them would
   falsify the record, and the rename map specifically is a persisted consumer contract that must
   never lose an entry.

## Consequences

- Deployments must update scheduler pointers, qualified agent references, and their copy of the
  desired state before their next scheduled run; the plugin README documents the three places.
- `scripts/validate-manifests.sh` pins the new entrypoint and role key, and its self-test pins that
  guard, so a half-applied rename fails CI rather than reaching consumers.
- The role/configuration boundary from ADR 0002 is untouched: this changes an identifier, not
  behaviour, contract sections, or guardrails.
- The distinction between plugin renames (migrated automatically through the append-only `renames`
  map) and agent renames (manual, and therefore breaking) is now explicit. A future agent rename
  should expect the same major-version treatment.
