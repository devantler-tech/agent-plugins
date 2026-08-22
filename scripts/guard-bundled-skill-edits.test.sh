#!/usr/bin/env bash
# Self-test for guard-bundled-skill-edits.sh.
#
# Builds a throwaway git repository whose history contains a SYNCED skill (its
# SKILL.md carries metadata.github-repo) and runs the REAL guard against it,
# asserting exit code AND the specific message. Self-contained, no network.
#
# The cases that matter are the ones where a weakened guard still looks green:
# an exemption that accepts the actor OR the branch instead of both, a provenance
# read taken from the head so deleting the line disables the guard, and a path
# match loose enough to catch authored files.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/guard-bundled-skill-edits.sh"

pass=0
fail=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# expect WANTED_RC PATTERN LABEL -- asserts on the rc/output of the last run().
expect() {
  local want_rc="$1" pattern="$2" label="$3"
  if [ "$rc" != "$want_rc" ]; then
    echo "FAIL: $label (wanted rc=$want_rc, got rc=$rc)"
    sed 's/^/       /' "$WORK/out"
    fail=$((fail + 1))
    return
  fi
  if [ -n "$pattern" ] && ! grep -q -- "$pattern" "$WORK/out"; then
    echo "FAIL: $label (rc ok, but output lacks '$pattern')"
    sed 's/^/       /' "$WORK/out"
    fail=$((fail + 1))
    return
  fi
  echo "ok: $label"
  pass=$((pass + 1))
}

FIXTURE="$WORK/repo"
mkdir -p "$FIXTURE"
git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" config user.email t@example.invalid
git -C "$FIXTURE" config user.name test

mkdir -p "$FIXTURE/plugins/github/skills/github-issues/references"
mkdir -p "$FIXTURE/plugins/agentic-engineering/agents"
cat > "$FIXTURE/plugins/github/skills/github-issues/SKILL.md" <<'SKILL'
---
name: github-issues
description: manage issues
metadata:
  github-repo: https://github.com/github/awesome-copilot
  github-path: skills/github-issues
---
body
SKILL
echo 'docs' > "$FIXTURE/plugins/github/skills/github-issues/references/milestones.md"
echo '{}'   > "$FIXTURE/plugins/github/plugin.json"
echo 'x'    > "$FIXTURE/plugins/agentic-engineering/agents/agentic-engineer.agent.md"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit -qm base
BASE="$(git -C "$FIXTURE" rev-parse HEAD)"

REF='plugins/github/skills/github-issues/references/milestones.md'

# run PATHS -- executes the guard against the fixture; sets $rc, writes $WORK/out.
# ACTOR/BRANCH/SHA may be overridden per call in the environment. HEAD_SHA defaults to
# the fixture's current tip, which is where the guard looks to tell an EDIT (SKILL.md
# still there) from a RETIREMENT (gone).
run() {
  printf '%s' "$1" | GUARD_REPO_DIR="$FIXTURE" BASE_SHA="${SHA-$BASE}" \
    HEAD_SHA="${HEAD_AT-$(git -C "$FIXTURE" rev-parse HEAD)}" \
    PR_ACTOR="${ACTOR-someone}" PR_HEAD_BRANCH="${BRANCH-claude/x}" \
    "$GUARD" >"$WORK/out" 2>&1
  rc=$?
}

# run_z PATHS -- same, but NUL-separated on stdin via --null.
run_z() {
  printf '%s\0' "$@" | GUARD_REPO_DIR="$FIXTURE" BASE_SHA="${SHA-$BASE}" \
    HEAD_SHA="${HEAD_AT-$(git -C "$FIXTURE" rev-parse HEAD)}" \
    PR_ACTOR="${ACTOR-someone}" PR_HEAD_BRANCH="${BRANCH-claude/x}" \
    "$GUARD" --null >"$WORK/out" 2>&1
  rc=$?
}

run 'docs/adr/0001.md
README.md'
expect 0 'no bundled skill tree touched' 'a change touching no skill tree passes'

run 'plugins/github/plugin.json
plugins/agentic-engineering/agents/agentic-engineer.agent.md'
expect 0 'no bundled skill tree touched' 'authored plugin files are not mistaken for skill content'

run 'plugins/github/skills/github-issues'
expect 0 'no bundled skill tree touched' 'the bare skill directory path is not a file inside it'

# THE CASE THIS EXISTS FOR.
run "$REF"
expect 1 'silently revert' 'a hand-edited reference file fails'
run "$REF"
expect 1 'github/awesome-copilot' 'the failure names the upstream that owns it'

ACTOR='botantler-1[bot]' BRANCH='deps/agent-skills-update' run "$REF"
expect 0 'programmed skill sync' 'the programmed sync PR is exempt'

ACTOR='botantler-1[bot]' BRANCH='claude/something' run "$REF"
expect 1 'silently revert' 'the sync actor on another branch is NOT exempt'

ACTOR='someone' BRANCH='deps/agent-skills-update' run "$REF"
expect 1 'silently revert' 'the sync branch under another actor is NOT exempt'

run 'plugins/github/skills/brand-new/SKILL.md
plugins/github/skills/brand-new/references/a.md'
expect 0 'new or locally-authored' 'adding a wholly new skill directory is allowed'

# Provenance is read at BASE, so stripping the line at head cannot disable the guard.
cat > "$FIXTURE/plugins/github/skills/github-issues/SKILL.md" <<'SKILL'
---
name: github-issues
description: provenance stripped at head
---
body
SKILL
git -C "$FIXTURE" add -A >/dev/null
git -C "$FIXTURE" commit -qm 'strip provenance'
run "$REF"
expect 1 'github/awesome-copilot' 'stripping provenance at head does not disable the guard'

# A top-level github-repo, outside the metadata: block, is not provenance.
mkdir -p "$FIXTURE/plugins/github/skills/toplevel/references"
cat > "$FIXTURE/plugins/github/skills/toplevel/SKILL.md" <<'SKILL'
---
name: toplevel
github-repo: https://github.com/example/not-metadata
---
body
SKILL
echo 'r' > "$FIXTURE/plugins/github/skills/toplevel/references/r.md"
git -C "$FIXTURE" add -A >/dev/null
git -C "$FIXTURE" commit -qm 'add toplevel skill'
SHA="$(git -C "$FIXTURE" rev-parse HEAD)" \
  run 'plugins/github/skills/toplevel/references/r.md'
expect 0 'new or locally-authored' 'a top-level github-repo does not count as provenance'

# Missing context with a touched skill is UNKNOWN, never a pass.
printf '%s' "$REF" | GUARD_REPO_DIR="$FIXTURE" BASE_SHA="$BASE" \
  HEAD_SHA="$(git -C "$FIXTURE" rev-parse HEAD)" PR_HEAD_BRANCH=claude/x "$GUARD" >"$WORK/out" 2>&1
rc=$?
expect 2 'PR_ACTOR' 'missing actor fails closed as UNKNOWN rather than passing'

# ...but an unrelated change must not demand CI context at all.
printf '%s' 'README.md' | GUARD_REPO_DIR="$FIXTURE" "$GUARD" >"$WORK/out" 2>&1
rc=$?
expect 0 'no bundled skill tree touched' 'an unrelated change needs no CI context'

# A push-to-main event has NO PR context at all — both the actor and the branch are
# empty, while a base sha is still populated. The guard must call that UNKNOWN; the CI
# job additionally never runs on push, so the two together are what keep main green.
printf '%s' "$REF" | GUARD_REPO_DIR="$FIXTURE" BASE_SHA="$BASE" \
  HEAD_SHA="$(git -C "$FIXTURE" rev-parse HEAD)" PR_ACTOR='' PR_HEAD_BRANCH='' \
  "$GUARD" >"$WORK/out" 2>&1
rc=$?
expect 2 'PR_ACTOR PR_HEAD_BRANCH' 'a push-event context (no actor, no branch) is UNKNOWN, not a pass'

# ---------------------------------------------------------------------------
# A NON-ASCII PATH MUST STILL BE MATCHED. `git diff --name-only` QUOTES such a path,
# and a quoted path matches none of the guard's anchored patterns — so the file is
# dropped before any provenance check and the edit passes unseen. The attacker names
# their own file, so this needs no pre-existing condition. `-z` is the fix; the case
# below proves the guard reads it and still refuses.
# ---------------------------------------------------------------------------
#
# THE ORDER AND THE NON-SKILL FIRST PATH ARE BOTH LOAD-BEARING — two ablations were
# needed to get this case to discriminate at all. Bash drops NUL bytes when a
# newline-reading `read` swallows the whole stream, so with a single path the case still
# passed with NUL-reading removed, asserting nothing about the mode. Two skill paths did
# not fix it either: glued together they still begin `plugins/github/skills/…`, so the
# guard matched anyway. A non-skill path FIRST is what makes the glued line start with
# `README.mdplugins/…`, which resolves to no skill at all — so the case now fails
# whenever --null stops reading NUL-separated input.
run_z 'README.md' 'plugins/github/skills/github-issues/references/évil.md'
expect 1 'github/awesome-copilot' 'a non-ASCII path inside a synced skill is still refused (--null)'

# The same path arriving QUOTED in newline mode is UNKNOWN, never a silent drop — a
# caller that cannot use --null must be told its input was unreadable.
printf '%s' '"plugins/github/skills/github-issues/references/\303\251vil.md"' |
  GUARD_REPO_DIR="$FIXTURE" BASE_SHA="$BASE" \
  HEAD_SHA="$(git -C "$FIXTURE" rev-parse HEAD)" PR_ACTOR=someone PR_HEAD_BRANCH=claude/x \
  "$GUARD" >"$WORK/out" 2>&1
rc=$?
expect 2 'arrived quoted' 'a quoted path fails closed instead of being silently dropped'

# ---------------------------------------------------------------------------
# AN UNREADABLE BASE IS UNKNOWN, NOT "a new skill". Collapsing every failed read into
# "the skill did not exist at base" hands the guard's most reassuring line — "only new
# or locally-authored skill directories touched" — to a base it could not read at all.
# ---------------------------------------------------------------------------
SHA='0000000000000000000000000000000000000000' run "$REF"
expect 2 'cannot read' 'an unreadable base is UNKNOWN rather than a false all-clear'

# ---------------------------------------------------------------------------
# RETIRING a bundled skill is plugin membership, which IS authored here — and there is
# nothing to "fix upstream" about a directory being removed, so refusing it leaves no
# usable escape hatch.
# ---------------------------------------------------------------------------
git -C "$FIXTURE" rm -rq plugins/github/skills/github-issues
git -C "$FIXTURE" commit -qm 'retire the github-issues skill'
SHA="$BASE" run "plugins/github/skills/github-issues/SKILL.md
$REF"
expect 0 'retired outright' 'retiring a bundled skill outright is allowed'
git -C "$FIXTURE" revert --no-edit HEAD >/dev/null

# ---------------------------------------------------------------------------
# A DEEPER SHAPE IS NOT A SKILL PATH. Shell globs match `/` too, so `plugins/*/skills/*/*`
# also accepts `plugins/p/EXTRA/skills/s/f.md`; taking its first four components yields
# `plugins/p/EXTRA/skills`, which holds no SKILL.md and therefore reads as "locally
# authored" — an edit allowed on the strength of a mis-derived directory.
# ---------------------------------------------------------------------------
run 'plugins/github/EXTRA/skills/github-issues/references/a.md'
expect 0 'no bundled skill tree touched' 'a deeper path shape is not mistaken for a skill file'

# The SKILL.md itself is the primary file a hand-edit lands in, yet every case above
# reaches the guard through a reference file or a NEW skill's SKILL.md. Edit the existing
# synced one directly.
run 'plugins/github/skills/github-issues/SKILL.md'
expect 1 'github/awesome-copilot' 'editing the synced SKILL.md itself is refused'

# TWO distinct synced skills in one change. This is the only case that reaches the
# dedup loop's `continue 2` with more than one offender, and it proves the report names
# both rather than stopping at the first.
mkdir -p "$FIXTURE/plugins/github/skills/second-skill"
cat > "$FIXTURE/plugins/github/skills/second-skill/SKILL.md" <<'SKILL'
---
name: second-skill
description: another synced skill
metadata:
  github-repo: https://github.com/fluxcd/agent-skills
---
body
SKILL
# An earlier case stripped github-issues' provenance at head, so it must be restored here
# or this base carries only ONE synced skill and the case silently stops testing the
# two-offender path — which is what the first run of it did.
cat > "$FIXTURE/plugins/github/skills/github-issues/SKILL.md" <<'SKILL'
---
name: github-issues
description: manage issues
metadata:
  github-repo: https://github.com/github/awesome-copilot
---
body
SKILL
git -C "$FIXTURE" add -A >/dev/null
git -C "$FIXTURE" commit -qm 'add a second synced skill'
TWO="$(git -C "$FIXTURE" rev-parse HEAD)"
SHA="$TWO" run "$REF
plugins/github/skills/second-skill/SKILL.md"
expect 1 'fluxcd/agent-skills' 'two edited skills are both named, not just the first'
SHA="$TWO" run "$REF
plugins/github/skills/second-skill/SKILL.md"
expect 1 'github/awesome-copilot' 'the first of two edited skills is named too'

echo
if [ "$fail" -gt 0 ]; then
  echo "FAIL: bundled-skill edit guard ($pass passed, $fail failed)"
  exit 1
fi
echo "PASS: bundled-skill edit guard ($pass cases)"
