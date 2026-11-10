# Adopt-or-build scorecard

Fill one scorecard per candidate. A candidate that fails the licence, provenance or supply-chain
gate is rejected, whatever it scores elsewhere. So is one that fails the correctness gate, with
one narrow exception: wrong examples that are few, outside the areas you rely on, and that fail
loudly can be accepted as known defects, on the terms under [Reading the result](#reading-the-result).
Write down what you looked at, not only the verdict: the next reader has to
be able to check it.

## Gates (pass or fail)

| Gate | Passes when | How to check |
|---|---|---|
| Licence | The licence allows redistribution, and its notice can be kept with the copy | Read the licence file in the candidate's repository, not a badge or a registry field. It may sit at the repository root, outside the skill's folder |
| Provenance | The owner is who it claims to be, the repository is not archived, and the skill can be pinned to an exact tree | Open the repository; confirm the owner; note the commit and the tree hash you reviewed |
| Supply chain | Nothing in the skill downloads and runs unpinned code, asks for credentials, or widens tool permissions without saying why | Read every script and every command in the text; run the security review if one is available |
| Correctness | Every example you read is right for the tool and version it names | Check the examples against the tool's own documentation or by running them. Read all of them when the skill is under about 300 lines in total, and at least every example in the areas you will rely on when it is larger |

The correctness gate is the one most often skipped. A skill that reads well and is from a
known vendor can still carry an example that is wrong in a way that only shows in production.
Fit is not correctness: read for both. An example you cannot run or check is unverified, and
counts against the gate unless it is inert in your setup.

## Scored (0 to 2 each)

| Dimension | 0 | 1 | 2 |
|---|---|---|---|
| Functionality | Misses the gap in the brief | Covers part of it | Covers the acceptance scenarios |
| Maintenance | Abandoned: reported defects go unanswered | Answered slowly, or one maintainer | Defects are answered and fixes are released |
| Compatibility | Tied to one host or one hosted product you do not use | Works with caveats | Follows the open skill format and names no product you lack |
| Test quality | No examples of expected behaviour | Examples only | Evaluation cases or tests upstream |
| Upkeep | Large, changes often, or needs local patches | Moderate | Small, stable, used unmodified |

A skill that is finished and rarely changes is not abandoned: Maintenance is about whether
defects get fixed, not about how often the text moves.

Record the description length in characters. Every listed skill costs every session some of
its skill-listing budget, so a description over about 400 characters needs a reason.

## Reading the result

The scores are there to make the comparison between candidates visible; they are not added up.
Any 0 needs a sentence in the decision record saying why it is acceptable or why it is not.

- **Adopt**: all gates pass and Functionality is 2.
- **Adopt with known defects**: the licence, provenance and supply-chain gates pass, and the
  only correctness failures are defects in examples that are few,
  outside the areas you rely on, and that fail loudly (an error or an obvious wrong result,
  never a silent one). Name each defect where users read about the skill, and track the
  upstream fix.
- **Reject**: the licence, provenance or supply-chain gate fails, or the wrong examples are
  many, are in the areas you rely on, or fail silently
  (security rules, data loss, access control).
- **Build**: no candidate can be adopted and the gap is still worth closing. Say why each
  candidate was rejected.

A rejection is a result. Record it so the next person does not repeat the evaluation, and say
what would change the answer.
