# Stacked pull requests

Read this before you split a change into dependent pull requests, and on every run that drives,
promotes or merges a layer of an existing stack. It decides when a stack pays off and how its
layers are reviewed and merged. The bundled `gh-stack` skill teaches the tool; where the two
disagree, this guide wins.

A stack is a chain of branches with one pull request each, every one based on the branch below it,
so a reviewer sees only that layer's diff. It trades extra coordination (a review per layer, and a
rebase above every merge) for smaller, faster reviews and the ability to keep building on work that
is still in review. Use it only when that trade pays.

## Stack only when all of these hold

1. **The work layers.** Each layer depends on the one below and is coherent on its own: it builds,
   its tests pass and it makes sense to review alone. Typical layers are a refactor that makes room,
   then the feature on top, then callers moved onto it; or an API or schema, then its
   implementation, then its consumers.
2. **One pull request would be too large to review well.** As a rough guide, that is more than
   about 400 changed lines of hand-written code (not counting generated files, vendored code or
   lock files), or more than one concern a reviewer must hold in mind at once.
3. **Waiting would leave work idle.** You need the next layer now, while the one below is in review.
   If the first part can merge before you need the second, ship it as an ordinary pull request and
   start the next from the updated default branch instead.
4. **Every layer gets the gates.** The repository's required checks and its review provider must
   run on pull requests whose base is not the default branch. Check before you stack: read each
   required workflow's `on.pull_request.branches` (and `pull_request_target`); a filter that lists
   only the default branch skips every layer above the bottom. Review providers often review only
   the default branch unless configured, for example CodeRabbit's
   `reviews.auto_review.base_branches`. If the gates do not run on upper layers, do not stack: a
   layer that never passed its gates cannot be judged ready.
5. **Your draft capacity allows it.** Each layer is one open draft against the consumer's per-run
   and per-lane draft caps. Open no stack that would exceed them; a stack is worth its layers only
   if you can finish all of them.

Keep stacks shallow: two to four layers. Every extra layer adds a rebase and a review wait to
everything above it.

## Do not stack

- **Independent changes.** Open separate pull requests from the default branch. A stack would
  serialize them for no reason and let one blocked layer hold back the rest.
- **A change that fits one reviewable pull request.**
- **Work across repositories.** A stack lives in one repository. Link the pull requests instead
  and merge them in dependency order.
- **Hotfixes, dependency updates and other programmed or generated pull requests.** They go
  straight to the default branch.
- **Another author's pull request.** Never restack or push to someone else's branch unless the
  consumer contract lets you adapt that author's branch.

## Build the stack

- Plan the layers before writing code: foundations at the bottom, consumers at the top.
  `gh-stack`'s `references/stack-design.md` helps choose them.
- Name every layer's branch in your writer namespace, following the consumer's claim and branch
  conventions; `gh stack` uses branch names exactly as given.
- Use only the non-interactive command forms `gh-stack` lists, such as `gh stack view --json` and
  `gh stack submit --auto`. A bare command can block on a prompt. Never pass `--open`: every layer
  starts as a draft. In a checkout with more than one remote, pass `--remote <name>` to `push`,
  `submit`, `sync` and `rebase` unless `remote.pushDefault` is set.
- Give each layer the normal pull request conventions: title, disclosure line and any metadata the
  consumer requires. Its body states its place in the stack, for example "Layer 2 of 3; builds on
  #41, and #43 builds on this." Only the layer that completes the issue says `Fixes #N`; the others
  reference it.
- Fix a review finding in the layer that introduced the code, then `gh stack rebase` to carry the
  fix upward and `gh stack push` to publish every layer. Never patch a lower layer's problem in a
  higher one.

## Merge the stack

This section replaces `gh-stack`'s own merging advice.

- **Merge one layer at a time, bottom first**, with the consumer's normal merge mechanics, and only
  once that layer meets the full readiness bar at its current head: passing checks, a green review
  of that head and resolved threads. For example
  `gh pr merge <bottom> --squash --match-head-commit <sha>`. On a merge-queue repository, enqueue
  the bottom layer alone.
- **Never run `gh stack merge`.** It merges the target and every unmerged layer below it in one
  all-or-nothing call, checks only that each pull request is open and not a draft, reuses the last
  merge method and pins no head commit. It can land a layer whose current head nobody reviewed.
  `gh-stack` says `gh pr merge` "cannot merge a stack"; that is about merging a whole stack at once,
  which this guide forbids anyway. The bottom layer's base is the default branch, so merging it is
  an ordinary merge. If GitHub refuses that merge anyway, park the layer on a named blocker; never
  fall back to `gh stack merge`.
- **After each merge, run `gh stack sync`.** It rebases the remaining layers onto the updated
  default branch and drops the merged commits, including after a squash merge (see `gh-stack`'s
  `references/troubleshooting.md`). A non-interactive sync can exit 0 with `Sync aborted` and change
  nothing, so check its output for that message before treating the stack as synced. Push, then let
  checks and review run again at the new heads. The next layer is now the bottom: merge it only on
  its own fresh readiness.
- **Restructure instead of merging around a problem.** If a lower layer is abandoned or its
  approach changes, rebuild the stack (`gh stack unstack`, then `gh stack init`) rather than merge
  an upper layer that depends on code that will not land.
