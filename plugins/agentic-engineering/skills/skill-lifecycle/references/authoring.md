# Authoring a first-party skill

Write one only after the decision record says build.

## Shape

- **Folder and name.** The folder name is the skill name: lowercase letters, digits and single
  hyphens, at most 64 characters. `SKILL.md` sits at its root.
- **Frontmatter.** `name` and `description` are required; add `license`. Add other fields only
  when a host needs them, and say which host.
- **Description.** One or two sentences, at most 1024 characters and much shorter when you can.
  Say what the skill does, then when to use it, in the words a user would type. It is loaded in
  every session, before the skill is chosen, so it pays for itself or it costs everyone.
- **Body.** The procedure in the order the work happens, under 500 lines. Start with what the
  reader must not get wrong.
- **References.** Detail that only some tasks need goes in `references/`, linked from the body,
  one level deep. Scripts go in `scripts/` and say what they need to run.

## Content

- **Every example is checked.** Run it, or check it against the tool's own documentation, and
  name the version it is true for when that matters.
- **Facts that go stale carry a date.** "Checked 2026-11-04" beside a list of products or
  limits tells the next reader when to look again.
- **Say what the skill does not cover** and what does. A near miss that loads the wrong skill
  is worse than no skill.
- **No secrets, private hostnames or account details**, and nothing that only works in one
  person's environment.
- **Do not restate another skill.** Point to it.

## Proof

- The acceptance scenarios from the research brief are the test cases. Keep them with the
  skill's decision record, and add them to the repository's evaluation suite when it has one.
- Validate the folder against the open skill format (`skills-ref validate <folder>`), and run
  whatever else the repository runs for its skills.
- Install the skill the way a user would and try each scenario. A skill that validates but
  never loads for its own scenarios is not finished: fix the description first.

## Change

- A first-party skill changes in the repository that holds its source, with the same review
  as code.
- A change to the description is a change to when the skill loads. Re-run the scenarios.
- Retire a skill in the same change that replaces it.
