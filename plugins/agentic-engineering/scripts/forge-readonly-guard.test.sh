#!/usr/bin/env bash
#
# Self-test for forge-readonly-guard.sh.
#
# Proves both paths, because either alone is worthless: a guard that denies
# everything passes a prohibited-path test, and a guard that allows everything
# passes an intended-path test.
#
#   intended    the surveyor's measured read vocabulary is still accepted,
#               including the `--jq` expressions whose `|` and `>` are data
#   prohibited  create/edit/comment/review/merge/push/checkout/build and
#               arbitrary shell are denied — including when a denied command
#               rides behind an allowed one through chaining or substitution
#
# Self-contained: no network, no forge, no cluster. It only ever asks the guard
# to classify a string; nothing here executes the commands under test.
#
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GUARD="$HERE/forge-readonly-guard.sh"

pass=0
fail=0

expect_allow() {
  local label=$1 cmd=$2 out status=0
  out=$("$GUARD" --command "$cmd" 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      expected allow, got exit %s: %s\n      command: %s\n' \
      "$label" "$status" "$out" "$cmd"
  fi
}

expect_deny() {
  local label=$1 cmd=$2 out status=0
  out=$("$GUARD" --command "$cmd" 2>&1) || status=$?
  if [ "$status" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      expected deny (exit 1), got exit %s: %s\n      command: %s\n' \
      "$label" "$status" "$out" "$cmd"
  fi
}

expect_usage() {
  local label=$1 status=0
  shift
  "$GUARD" "$@" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      expected usage error (exit 2), got exit %s\n' "$label" "$status"
  fi
}

# ---------------------------------------------------------------------------
# Intended path — the surveyor's measured vocabulary
# ---------------------------------------------------------------------------

expect_allow 'pr view with a json field list' \
  "gh pr view 2786 --repo devantler-tech/monorepo --json number,state,headRefOid"
expect_allow 'pr list' "gh pr list --repo devantler-tech/platform --state open --limit 100"
expect_allow 'issue view' "gh issue view 108 --repo devantler-tech/agent-plugins --json body"
expect_allow 'issue list' "gh issue list --repo devantler-tech/ksail --state open --limit 200"
expect_allow 'search issues' "gh search issues --owner devantler-tech --state open --limit 300"
expect_allow 'search prs' "gh search prs --owner devantler-tech --state open"
expect_allow 'repo list' "gh repo list devantler-tech --limit 100"
expect_allow 'run list' "gh run list --repo devantler-tech/platform --branch main --limit 40"
expect_allow 'run view' "gh run view 31544900207 --repo devantler-tech/platform --json jobs"
expect_allow 'pr checks' "gh pr checks 2786 --repo devantler-tech/monorepo"
expect_allow 'pr diff' "gh pr diff 2786 --repo devantler-tech/monorepo"
expect_allow 'label list' "gh label list --repo devantler-tech/monorepo"
expect_allow 'release view' "gh release view --repo devantler-tech/ksail"

expect_allow 'api rest get' "gh api repos/devantler-tech/monorepo/issues/2786/comments --paginate"
expect_allow 'api with an explicit GET method' \
  "gh api --method GET repos/devantler-tech/platform/rulesets"
expect_allow 'api rate_limit with a jq object expression' \
  "gh api rate_limit --jq '{graphql:.resources.graphql,core:.resources.core}'"

# The point of the quote-aware scanner: these `|` and `>` are jq syntax, not
# shell syntax, and a naive split on `|` breaks every real survey query.
expect_allow 'jq expression containing a pipe' \
  "gh api repos/devantler-tech/monorepo/branches --paginate --jq '.[].name'"
expect_allow 'jq select with an inner pipe' \
  "gh pr list --repo devantler-tech/platform --json number,title --jq '.[]|select(.number>3000)|.title'"
expect_allow 'jq expression containing a greater-than' \
  "gh issue list --repo devantler-tech/ksail --json number --jq '.[]|select(.number > 100)'"

expect_allow 'piped through jq' \
  "gh api repos/devantler-tech/monorepo/pulls --paginate | jq -c 'add|map(.number)'"
expect_allow 'piped through grep' \
  "gh api repos/devantler-tech/monorepo/branches --jq '.[].name' | grep -E '^(claude|cursor|codex)/'"
expect_allow 'piped through sort and head' "gh repo list devantler-tech | sort | head -20"
expect_allow 'a plain sed substitution' "gh pr list --json number --jq '.[]|@tsv' | sed 's/^/pr\t/'"
expect_allow 'sed with -n and a print command' "gh pr list --json number | sed -n '1p'"
expect_allow 'a longer read pipeline' \
  "gh api repos/devantler-tech/platform/pulls --paginate --jq '.[].head.ref' | sort | uniq | wc -l"

expect_allow 'git log' "git -C libraries/agent-plugins log --oneline -5"
expect_allow 'git status' "git status --porcelain"
expect_allow 'git ls-remote' "git ls-remote --heads origin"

# GraphQL is the one read the surveyor cannot do over GET: reviewThreads is a
# GraphQL-only field, so a guard that refused every POST would break it.
expect_allow 'graphql query for review threads' \
  "gh api graphql -f query='query(\$o:String!){repository(owner:\$o){name}}'"
expect_allow 'anonymous graphql document is a query by spec' \
  "gh api graphql -f query='{ viewer { login } }'"
expect_allow 'graphql reviewThreads pagination' \
  "gh api graphql -F n=2786 -f query='query{repository{pullRequest{reviewThreads(first:100){nodes{isResolved}}}}}'"

# ---------------------------------------------------------------------------
# Prohibited path — every mutation the surveyor must never make
# ---------------------------------------------------------------------------

expect_deny 'pr merge' "gh pr merge 2786 --repo devantler-tech/monorepo --squash"
expect_deny 'pr create' "gh pr create --draft --title x --body y"
expect_deny 'pr comment' "gh pr comment 2786 --body 'looks good'"
expect_deny 'pr edit' "gh pr edit 2786 --add-label security"
expect_deny 'pr review' "gh pr review 2786 --approve"
expect_deny 'pr ready' "gh pr ready 2786"
expect_deny 'pr close' "gh pr close 2786"
expect_deny 'issue create' "gh issue create --title x --body y"
expect_deny 'issue edit' "gh issue edit 108 --add-assignee devantler"
expect_deny 'issue comment' "gh issue comment 108 --body x"
expect_deny 'issue close' "gh issue close 108"
expect_deny 'repo clone' "gh repo clone devantler-tech/platform"
expect_deny 'repo delete' "gh repo delete devantler-tech/platform"
expect_deny 'run rerun' "gh run rerun 31544900207"
expect_deny 'run cancel' "gh run cancel 31544900207"
expect_deny 'workflow run' "gh workflow run cd.yaml"
expect_deny 'release create' "gh release create v1.0.0"
expect_deny 'secret set' "gh secret set KUBE_CONFIG"
expect_deny 'auth token' "gh auth token"
expect_deny 'label create' "gh label create x"
expect_deny 'gh with no subcommand' "gh"

expect_deny 'api explicit POST' \
  "gh api --method POST repos/devantler-tech/monorepo/issues/2786/comments"
expect_deny 'api short-flag POST' "gh api -X POST repos/devantler-tech/monorepo/issues"
expect_deny 'api DELETE' "gh api --method DELETE repos/devantler-tech/monorepo/issues/1/labels"
expect_deny 'api PATCH' "gh api --method PATCH repos/devantler-tech/monorepo/issues/1"
expect_deny 'api PUT' "gh api --method PUT repos/devantler-tech/monorepo/pulls/1/merge"
expect_deny 'api lowercase post' "gh api --method post repos/devantler-tech/monorepo/issues"
# gh makes the request a POST as soon as a field is set, with no --method in sight.
expect_deny 'api field argument implies POST' \
  "gh api repos/devantler-tech/monorepo/issues/2786/comments -f body=hi"
expect_deny 'api raw-field implies POST' \
  "gh api repos/devantler-tech/monorepo/issues/2786/comments -F body=@x"
expect_deny 'api --input implies POST' \
  "gh api repos/devantler-tech/monorepo/issues --input payload.json"
expect_deny 'api with no endpoint' "gh api --paginate"

expect_deny 'graphql mutation' \
  "gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:\"x\"}){thread{id}}}'"
expect_deny 'graphql mutation in mixed case' "gh api graphql -f query='Mutation { addComment }'"
expect_deny 'graphql subscription' "gh api graphql -f query='subscription{events{id}}'"

expect_deny 'git push' "git push origin main"
expect_deny 'git commit' "git commit -m x"
expect_deny 'git checkout of a branch' "git checkout claude/some-branch"
expect_deny 'git reset' "git reset --hard origin/main"
expect_deny 'git fetch' "git fetch origin"
expect_deny 'git -C then push' "git -C libraries/agent-plugins push origin HEAD"
expect_deny 'git with no subcommand' "git"

# The whole reason the scanner exists: a denied command riding behind an allowed
# one. Each of these begins with a perfectly legitimate read.
expect_deny 'semicolon chaining' "gh pr list --json number; gh pr merge 2786 --squash"
expect_deny 'and-and chaining' "gh pr list --json number && gh pr merge 2786 --squash"
expect_deny 'or-or chaining' "gh pr list --json number || gh pr merge 2786 --squash"
expect_deny 'backgrounding' "gh pr merge 2786 --squash &"
expect_deny 'command substitution' "gh pr view \$(gh pr merge 2786 --squash)"
expect_deny 'backtick substitution' "gh pr view \`gh pr merge 2786 --squash\`"
expect_deny 'substitution inside double quotes' "gh pr view --json \"\$(gh pr merge 2786)\""
expect_deny 'process substitution' "gh pr list --json number < <(gh pr merge 2786)"
expect_deny 'output redirection' "gh pr list --json number > /tmp/out.json"
expect_deny 'append redirection' "gh pr list --json number >> /tmp/out.json"
expect_deny 'input redirection' "gh api repos/x/y/issues < payload.json"
expect_deny 'a newline carrying a second command' "gh pr list --json number
gh pr merge 2786 --squash"
expect_deny 'a mutation later in the pipeline' "gh pr list --json number | gh pr merge 2786"
expect_deny 'a non-allowlisted program in the pipeline' "gh pr list --json number | tee /tmp/x"

expect_deny 'arbitrary shell' "bash -c 'gh pr merge 2786 --squash'"
expect_deny 'sh' "sh -c 'echo hi'"
expect_deny 'curl' "curl https://example.com"
expect_deny 'rm' "rm -rf /tmp/x"
expect_deny 'a build command' "go build ./..."
expect_deny 'npm install' "npm ci"
expect_deny 'an env-prefixed command' "GH_TOKEN=x gh pr list --json number"

# awk and in-place sed can write without any shell redirection at all.
expect_deny 'awk is not allowlisted' "gh pr list --json number | awk '{print > \"/tmp/x\"}'"
expect_deny 'sed in place' "sed -i 's/a/b/' AGENTS.md"
expect_deny 'sed in place with a suffix' "sed -i.bak 's/a/b/' AGENTS.md"
expect_deny 'sed write flag' "gh pr list --json number | sed 's/a/b/w /tmp/out'"
expect_deny 'sed execute flag' "gh pr list --json number | sed 's/a/b/e'"
expect_deny 'sed script from a file' "gh pr list --json number | sed -f script.sed"
expect_deny 'sed -e with a write flag' "gh pr list --json number | sed -e 's/a/b/w /tmp/out'"

expect_deny 'unbalanced quoting' "gh pr list --json 'number"
expect_deny 'a stray leading pipe' "| gh pr list --json number"

# --- Regressions: every one of these was ALLOWED before review ---------------
#
# A method flag whose value a raw-text regex cannot see reads as "no method
# given", which is indistinguishable from a GET.
expect_deny 'quoted method value' "gh api --method 'POST' repos/devantler-tech/monorepo/issues"
expect_deny 'attached long method' "gh api --method=POST repos/devantler-tech/monorepo/issues"
expect_deny 'attached short method' "gh api -XPOST repos/devantler-tech/monorepo/issues"
expect_deny 'attached short DELETE' "gh api -XDELETE repos/devantler-tech/monorepo/issues/1"
expect_deny 'method flag with no value' "gh api --method repos/devantler-tech/monorepo/issues"
expect_allow 'quoted GET is still a read' "gh api --method 'GET' repos/devantler-tech/monorepo/pulls"
expect_allow 'attached GET is still a read' "gh api -XGET repos/devantler-tech/monorepo/pulls"

# git options that turn a read into local execution.
expect_deny 'git ext transport' "git -c protocol.ext.allow=always ls-remote 'ext::sh -c whoami'"
expect_deny 'git upload-pack override' "git ls-remote --upload-pack=/tmp/evil origin"
expect_deny 'git receive-pack override' "git ls-remote --receive-pack=/tmp/evil origin"
expect_deny 'git -c config injection' "git -c core.pager=/tmp/evil log"
expect_deny 'git --config-env' "git --config-env=core.pager=EVIL log"
expect_deny 'git --exec-path' "git --exec-path=/tmp/evil log"
expect_allow 'git -C is still fine' "git -C libraries/agent-plugins log --oneline -5"

# A filter is not a reader: it may not open the pipeline, and it may not take a
# path. `cat ~/.config/gh/hosts.yml` is a credential read wearing a filter name.
expect_deny 'cat a credential file' "cat /Users/someone/.config/gh/hosts.yml"
expect_deny 'cat a file mid-pipeline' "gh pr list --json number | cat /etc/passwd"
expect_deny 'grep recursively over a directory' "grep -r token /Users/someone/.claude"
expect_deny 'grep a file mid-pipeline' "gh pr list --json number | grep token /etc/passwd"
expect_deny 'jq reading a file mid-pipeline' "gh pr list --json number | jq '.[]' /etc/passwd"
expect_deny 'jq --from-file' "gh pr list --json number | jq -f /tmp/prog.jq"
expect_deny 'sed reading a file mid-pipeline' "gh pr list --json number | sed 's/a/b/' /etc/passwd"
expect_deny 'head of a file mid-pipeline' "gh pr list --json number | head -5 /etc/passwd"
expect_deny 'a filter opening the pipeline' "jq '.' "
expect_deny 'sort opening the pipeline' "sort /etc/passwd"
expect_allow 'grep with a pattern only' "gh api repos/x/y/branches --jq '.[].name' | grep -E '^claude/'"
expect_allow 'grep with -e is still fine' "gh pr list --json number | grep -e claude"
expect_allow 'tr takes its two sets' "gh pr list --json number | tr 'a-z' 'A-Z'"
expect_allow 'cut with a delimiter' "gh pr list --json number | cut -d, -f1"
expect_allow 'head with a count' "gh repo list devantler-tech | head -n 20"

# --- Regressions: shell spellings a text scanner cannot see through ---------
#
# Every one of these was ALLOWED by the scanner that classified the command as
# TEXT. They are not eight unrelated bugs: each is another spelling of a word
# the shell rewrites before the program ever sees it, which is why the guard now
# resolves one literal argument vector first and classifies only that.

# A shell expansion the guard cannot perform is refused rather than guessed at,
# because its result — a flag, a second operand, a path — is exactly what the
# classification depends on.
expect_deny 'brace expansion can manufacture a method flag' \
  "gh api {--method,POST} repos/devantler-tech/monorepo/issues"
expect_deny 'brace expansion can manufacture an operand' \
  "gh pr list --json number | grep -E claude{,/x}"
expect_deny 'ANSI-C quoting hides the operation keyword' \
  "gh api graphql -f query=\$'\\x6dutation{x}'"
expect_deny 'a glob can expand into flags the guard never saw' "git diff *"
expect_allow 'parameter expansion stays allowed, as documented' \
  "git -C \$REPO log --oneline -5"
expect_allow 'a braced parameter expansion is not brace expansion' \
  "gh api repos/\${OWNER}/monorepo/pulls --paginate"

# gh switches to POST as soon as a field is set, in EVERY spelling of the flag.
expect_deny 'attached short field flag' "gh api repos/devantler-tech/monorepo/issues -fbody=hi"
expect_deny 'attached short raw-field flag' "gh api repos/devantler-tech/monorepo/issues -Fbody=hi"
expect_deny 'attached long field flag' "gh api repos/devantler-tech/monorepo/issues --field=body=hi"
expect_deny 'attached long input flag' "gh api repos/devantler-tech/monorepo/issues --input=payload.json"

# gh honours the LAST method flag, so a harmless first one is a free bypass.
expect_deny 'a repeated method flag whose last value is a write' \
  "gh api --method GET --method POST repos/devantler-tech/monorepo/issues"
expect_deny 'a repeated method flag in attached form' \
  "gh api -X GET -XPOST repos/devantler-tech/monorepo/issues"

# `-F value` beginning with @ makes gh read that file and send its contents.
expect_deny 'a file-backed graphql field reads a local file' \
  "gh api graphql -F token=@/Users/someone/.config/gh/hosts.yml -f query='{viewer{login}}'"
expect_deny 'a file-backed field on any endpoint' \
  "gh api graphql -f token=@/etc/passwd -f query='{viewer{login}}'"

# An unknown flag is a flag whose effect the guard has not established.
expect_deny 'an unrecognised gh api flag' "gh api repos/devantler-tech/monorepo/pulls --nope"

# git writes these files itself — no shell redirection for the scanner to catch.
expect_deny 'git diff --output writes a file' "git diff --output=/tmp/guard-bypass"
expect_deny 'git diff --output in separated form' "git diff --output /tmp/guard-bypass"
expect_deny 'an unrecognised git option' "git log --nope"

# grep's operands are PATTERNS [FILE]: once -e supplies the pattern, every
# positional word is a file — in the attached spelling too.
expect_deny 'attached grep -e leaves the operand a file' \
  "gh pr list --json number | grep -e'.*' /Users/someone/.config/gh/hosts.yml"
expect_deny 'grep --regexp= leaves the operand a file' \
  "gh pr list --json number | grep --regexp='.*' /etc/passwd"

# GNU sed reads `w/tmp/g` as a write flag, so the last delimiter is not the end
# of the substitution.
expect_deny 'a sed write flag hidden behind delimiters' \
  "gh pr list --json number | sed 's/a/b/w/tmp/g'"
expect_deny 'a sed execute flag hidden behind delimiters' \
  "gh pr list --json number | sed 's/a/b/e/tmp/g'"
expect_allow 'an ordinary substitution with flags still passes' \
  "gh pr list --json number | sed 's/a/b/g'"

# Quote boundaries carry meaning: a quoted pattern is ONE operand, and a scanner
# that splits on whitespace turns a legitimate read into a denied file read.
expect_allow 'a quoted pattern containing a space is one operand' \
  "gh pr list --json title --jq '.[].title' | grep -E 'release candidate'"
expect_allow 'a quoted sed program containing a space' \
  "gh pr list --json number | sed 's/a b/c d/'"
expect_allow 'a quoted jq expression containing spaces' \
  "gh api rate_limit --jq '.resources | to_entries | map(.key)'"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

expect_usage 'no arguments'
expect_usage 'unknown argument' --nope
expect_usage 'command flag with no value' --command
expect_usage 'an all-whitespace command' --command '   '

# stdin form
stdin_status=0
printf '%s' "gh pr list --json number" | "$GUARD" --stdin >/dev/null 2>&1 || stdin_status=$?
if [ "$stdin_status" -eq 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL  stdin form\n      expected allow, got exit %s\n' "$stdin_status"
fi

stdin_status=0
printf '%s' "gh pr merge 2786 --squash" | "$GUARD" --stdin >/dev/null 2>&1 || stdin_status=$?
if [ "$stdin_status" -eq 1 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL  stdin form denies a mutation\n      expected deny, got exit %s\n' "$stdin_status"
fi

printf '\nforge-readonly-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
