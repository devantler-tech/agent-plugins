# Research brief and decision record

Both go where the request lives (the issue or the pull request), so the reasoning stays with
the change.

## Research brief

Write this first, before reading candidates closely.

```markdown
## Research brief

**Gap.** <one sentence: what agents get wrong or cannot do today>

**Where it shows up.** <the repositories, files or tasks; link one real example>

**Acceptance scenarios.**
- Should load: "<a request in the user's words>" -> <what a correct result looks like>
- Should load: "<another>" -> <result>
- Near miss: "<a similar request this skill must not take>" -> <what handles it instead>
- Must not load: "<an unrelated request that shares a keyword>"

**Already covered by.** <installed skills that touch this, and why they are not enough>

**Out of scope.** <what stays in a repository's own docs or with another skill's owner>
```

## Decision record

```markdown
## Decision record: <adopt | adopt with known defects | reject | build> `<skill>`

**Candidates.**

| Candidate | Owner and licence | Reviewed at | Gates | Score | Verdict |
|---|---|---|---|---|---|
| <name> | <owner>, <licence> | <commit or tag> | <pass, or the gate that failed> | <n>/10 | <adopt / reject: reason> |

**What was read.** <which files and examples, and how correctness was checked>

**Known defects.** <each one, why it is acceptable, and where the upstream fix is tracked; or "none found">

**Description cost.** <characters added to the skill listing>

**Acceptance scenarios.** <each scenario from the brief and what happened when it was tried>

**What would change this decision.** <for a rejection or a build: the upstream change that would reopen it>
```
