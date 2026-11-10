---
name: skill-lifecycle
description: Decide whether to adopt, build or reject an agent skill, and carry the choice through - research brief, adopt-or-build scorecard, pinned install with licence and provenance, first-party authoring rules, and review of skill updates. Use when adding, writing, replacing or updating a skill, or when asked whether a skill for something should exist.
license: Apache-2.0
---

# Skill lifecycle

A skill is an instruction an agent will follow without re-checking it. A wrong example in a
skill becomes wrong work in every repository that loads it. So a skill earns its place the way
a dependency does: by evidence, with a recorded decision and a pinned source.

Prefer a good upstream skill over a new one. Build only when the research shows nothing fits.
Never do both: one capability has one skill and one owner.

## The order of work

1. **Write the research brief** before reading any candidate closely
   ([template](references/decision-record.md#research-brief)). State the gap in one sentence,
   the repositories and tasks it shows up in, and three to five acceptance scenarios: tasks that
   should load the skill, a near miss that should not, and what a correct result looks like.
2. **Look for what already exists.** Check the skills already installed, then search upstream
   (use `find-skills` if it is available). Stop here if an installed skill already covers the
   gap: improve its owner instead of adding a second one.
3. **Score every serious candidate** with the [scorecard](references/scorecard.md). Four gates
   are pass or fail; the rest are scored. Read the candidate's examples for correctness, not
   only for fit. This is the step that gets skipped, and it is the one that matters.
4. **Record the decision** where the request lives
   ([template](references/decision-record.md#decision-record)): adopt, adopt with known
   defects, reject, or build. Name every candidate you rejected and why.
5. **Carry it out**: [adopt and pin](#adopting-an-upstream-skill), or
   [author a first-party skill](#authoring-a-first-party-skill).
6. **Prove it loads and helps.** Install it the way a user would, run the acceptance scenarios
   from the brief, and say what you saw.

## Adopting an upstream skill

- **Install it with its provenance, never by copying files.** Use the installer the repository
  uses (for example `gh skill install <owner>/<repo> <path>`), so the copy records its source
  repository, path, ref and tree hash. That record is the pin: it names exactly which upstream
  content was reviewed.
- **Never edit an adopted skill.** A fix goes to its upstream and arrives through an update.
  If you find a defect you cannot fix upstream today, either reject the skill or adopt it with
  the defect written down where users will read it, and track the upstream fix.
- **Keep its licence with it.** Record the licence and copyright notice the way the repository
  records third-party content. No licence, or one that forbids redistribution, is a rejection.
- **Take only what was reviewed.** Adopt single skills, not a whole collection.
- **Run the security review** before installing anything with scripts, downloads, tool
  permissions or network calls (use `check-skills` if it is available).

## Reviewing a skill update

An update to an adopted skill is new instruction text from someone else. Read it as a change,
not as a version bump. [The update checklist](references/updates.md) has the steps: the exact
diff against the pinned tree, what upstream says changed, anything that breaks a documented
behaviour, a licence change, the validation result, and how to roll back.

## Authoring a first-party skill

Only after the decision record says build. The full rules are in
[authoring.md](references/authoring.md); the ones that fail most often:

- The description says what the skill does and when to use it, in the words a user would
  type. It is the only part loaded before the skill is chosen.
- The body is the procedure, in the order the work happens. Detail that only some tasks need
  moves to `references/`, one level deep.
- Every example is one you ran or checked against the tool's own documentation, with the date
  you checked it when the fact can go stale.
- The acceptance scenarios from the brief become the skill's test cases.
- Draft and evaluate with the host's own skill-authoring tool when it has one. That tool
  covers drafting and evaluation; this skill covers the decision and the rules.

## Ownership

- An adopted skill is owned by its upstream. The repository that bundles it owns the decision
  to carry it, its pin and its licence record, and nothing inside it.
- A first-party skill is owned by the repository that holds its source. Change it there.
- Do not carry two skills for one capability. When a better one arrives, the same change
  removes or retires the old one and says so.

## What to hand back

The decision record, the scorecard for each candidate, what was installed or written and from
which pinned source, the acceptance scenarios with what you observed, and anything left open
with its owner.
