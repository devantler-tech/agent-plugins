# Skill lifecycle in this marketplace

How a skill gets into a plugin here, stays current, and leaves. The decision procedure itself
(research brief, adopt-or-build scorecard, decision record, authoring rules, update checklist)
is the [`skill-lifecycle`](../plugins/agentic-engineering/skills/skill-lifecycle/SKILL.md) skill,
so agents load it wherever they work. This page adds only what is specific to this repository:
the commands, the files a change touches, and worked examples. [`AGENTS.md`](../AGENTS.md) links
here.

## Ownership and non-duplication

- **One capability, one skill, one owner.** Before adding a skill, check the
  [catalogue](plugins.md) and the [coverage page](skill-coverage.md). If a bundled skill already
  covers the gap, improve its owner; do not add a second.
- **External skills are owned by their upstream.** They keep their `metadata.github-*`
  provenance and are never edited here; the base-tree edit guard enforces it. A defect is fixed
  upstream and arrives through the updater. This repository owns only the decision to carry the
  skill, its pin and its licence record.
- **First-party skills are owned here**, at `plugins/<plugin>/skills/<skill>/`, and carry no
  install provenance. [ADR 0006](adr/0006-maintained-skill-ownership.md) records that boundary.
- **Replacing a skill removes the old one in the same change**, with the reason in the
  changelog. The 7.0.0 entry for `astro` is the model.
- **Guidance that is true for one repository stays in that repository.** A skill here holds
  what is true wherever the tool is used.

## Adopting an external skill

1. Post the research brief and the decision record on the issue (templates in the skill's
   [`decision-record.md`](../plugins/agentic-engineering/skills/skill-lifecycle/references/decision-record.md)).
2. Install with provenance, from a clean tree:
   `gh skill install <owner>/<repo> <path-in-repo> --dir plugins/<plugin>/skills`.
   The copy records the repository, path, ref and tree hash. That tree hash is the pin.
3. Record the licence: a row in [`plugins.md`](plugins.md), and for third-party content a row
   and a `## <owner>/<repo>` section with the copyright notice and licence text in
   `plugins/<plugin>/resources/THIRD-PARTY-NOTICES.md`.
4. Add the skill to the catalogue cell in [`plugins.md`](plugins.md) and to the plugin's README.
5. Bump the plugin version with `./scripts/bump-plugin-version.sh <plugin> minor` and add a
   changelog entry that names the source, what was deliberately not taken, and any known defect.
6. Update the [coverage page](skill-coverage.md): the matrix row, the candidate row and the
   priority list.
7. Run the checks in [`validation.md`](validation.md): `./scripts/validate-manifests.sh`,
   `bash scripts/check-skill-licenses.sh` and the spec validation.
8. Try it as a user: install the skill from the pull request's head into an empty directory
   (`gh skill install devantler-tech/agent-plugins <path> --pin <head> --dir <tmp>`), compare it
   with a fresh upstream install, and run the acceptance scenarios from the brief.

**Worked examples.**

| Outcome | Where | What it shows |
|---|---|---|
| Adopted | #654, merged in #675 | Two skills taken from a larger collection and two rejected, with the scorecard reasons; the pin and licence record; an install-and-compare trial |
| Adopted with known defects | #675, follow-up #676 | Review found two wrong examples. They fail loudly and sit outside what the portfolio relies on, so the changelog and the coverage page name them and the upstream fix is tracked |
| Rejected after review | #653, merged in #673, follow-up #674 | A vendor-maintained skill whose examples were wrong where it mattered (access rules). The first decision was made on fit alone and had to be reversed: read for correctness before deciding |
| Not bundled | the 7.0.0 changelog entry | A skill removed from the bundle, with the one command that installs it from upstream where it is needed |

## Reviewing an updater pull request

`update-agent-skills.yaml` opens one pull request per skill whose upstream moved (#671 is a
recent one). Its body does not yet say what changed upstream; #583 tracks that, under #581
(reviewable updates and redistribution terms). Until it lands, the reviewer does the reading by hand, with the
skill's [update checklist](../plugins/agentic-engineering/skills/skill-lifecycle/references/updates.md):

- the difference between the old and new `github-tree-sha`, for every file in the skill;
- the upstream commits in that range;
- a changed licence or notice (the licence check fails on a missing record, or one that
  disagrees with the licence the skill declares, but it does not compare licence texts except
  where a dedicated check exists);
- the same validation as an adoption.

Rolling back is reverting the updater pull request, which restores the previous tree hash.
A skill pinned to a tag or commit stays there until the pin is moved on purpose; #598 is the
record of one temporary pin and its release.

## Authoring a first-party skill

Only after a decision record says build. Draft with the host's skill-authoring tool where it
has one (Anthropic's `skill-creator` in Claude); the rules it must meet are the skill's
[`authoring.md`](../plugins/agentic-engineering/skills/skill-lifecycle/references/authoring.md).
Then, in this repository:

1. Create `plugins/<plugin>/skills/<skill>/SKILL.md` with `name`, `description` and
   `license: Apache-2.0`, and no `metadata.github-*` fields.
2. Add its row and catalogue entry in [`plugins.md`](plugins.md) with this repository as the
   source, and list it in the plugin's README.
3. Bump the version and write the changelog entry, as for an adoption.
4. Run the same checks. CI validates every skill folder against the open skill format.
5. Record the acceptance scenarios on the issue and list them for the activation suite (#651).

`skill-lifecycle` itself was written this way: its brief, the candidates it was weighed against
and its scenarios are on #641.

## What CI checks, and what it does not

Checked on every pull request: the two marketplace manifests agree, every skill folder is
catalogued, external skills keep their provenance and are not edited, every bundled skill has a
licence record, each `SKILL.md` validates against the open skill format, and a changed plugin
has a changed version. [`validation.md`](validation.md) has the commands.

Checked for first-party skills only, because external skills are not edited here:

- **Entry file size.** `SKILL.md` is at most 500 lines and 20,000 bytes.
- **References.** Every file under `references/` sits directly in that folder. Each Markdown
  reference is linked from `SKILL.md`. A worked example or data file is linked from `SKILL.md`
  or from the Markdown reference that explains it.
- **Description length.** At most 600 characters. The limit was set on 2026-11-10 from the 18
  first-party skills: 16 were at or under it, and the format itself allows 1,024. CI prints
  every first-party description's length on each run.

A skill that cannot meet a reference or description rule yet is recorded in
[`skill-authoring-exceptions.json`](../scripts/skill-authoring-exceptions.json) with its
reason. The record can only shrink: CI fails when an exception is no longer needed, when a
recorded description grows, and when its recorded ceiling is higher than the measured length.
The five first exceptions are tracked in #680.

Not checked by CI: whether a skill's examples are correct, whether it loads for the tasks it
is meant for, and whether its acceptance scenarios exist. The first is the correctness gate in
the scorecard. The other two belong to the activation suite in #651, which decides where
scenarios live; until then they are the trial in each pull request and the scenarios recorded
on the skill's issue.

## Keeping sources current

- **On every updater pull request**: the update checklist above.
- **When a product changes its stack**: update the [coverage page](skill-coverage.md) in the
  same piece of work, so the matrix does not describe a stack that is gone.
- **Dated facts**: a skill that lists products, limits or legal requirements says when they
  were checked. Re-check them when the skill is next changed, and at least when the coverage
  page is re-audited.
- **The coverage audit** is repeated when a gap it lists is closed or a new product joins the
  portfolio. It is the place a stale or duplicated skill gets noticed.
