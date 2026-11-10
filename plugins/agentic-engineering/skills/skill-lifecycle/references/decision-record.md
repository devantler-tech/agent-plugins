# Research brief and decision record

Both go where the request lives (the issue or the pull request), so the reasoning stays with
the change. A request that arrived in conversation has no such place yet: open an issue in the
repository that would carry the skill, and record them there.

## Research brief

Draft this first, before reading candidates closely. Fill in "Already covered by" once you
have looked at what is installed.

```markdown
## Research brief

**Gap.** <one sentence: what agents get wrong or cannot do today>

**Evidence.** <at least two real cases, linked: the pull request, review or incident where it went wrong>

**Where it shows up.** <the repositories, files or tasks>

**Acceptance scenarios.**
- Should load: "<a request in the user's words>" -> <what a correct result looks like>
- Should load: "<another>" -> <result>
- Near miss: "<a similar request this skill must not take>" -> <what handles it instead>
- Must not load: "<an unrelated request that shares a keyword>"

**Already covered by.** <installed skills that touch this, and why they are not enough>

**Would something else fix it better?** <a check in CI, a linter, or a line in the repository's own docs; and why a skill is still the answer, or is not>

**Out of scope.** <what stays in a repository's own docs or with another skill's owner>
```

## Decision record

```markdown
## Decision record: <adopt | adopt with known defects | reject | build | no skill> `<skill>`

**Candidates.**

| Candidate | Owner and licence | Reviewed at | Gates | Scores | Verdict |
|---|---|---|---|---|---|
| <name> | <owner>, <licence> | <commit and tree hash> | <pass, or the gate that failed> | <F n, M n, C n, T n, U n> | <adopt / reject: reason> |

**What was read.** <which files and examples, and how correctness was checked; name anything left unverified>

**Known defects.** <each one, why it is acceptable, and where the upstream fix is tracked; or "none found">

**Description cost.** <characters added to the skill listing>

**Acceptance scenarios.** <each scenario from the brief and what happened when it was tried>

**What would change this decision.** <for a rejection, a build or no skill: what would reopen it>
```
