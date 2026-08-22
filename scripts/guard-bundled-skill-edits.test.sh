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
# ACTOR/BRANCH/SHA may be overridden per call in the environment.
run() {
  printf '%s' "$1" | GIT_DIR_OVERRIDE="$FIXTURE" BASE_SHA="${SHA-$BASE}" \
    PR_ACTOR="${ACTOR-someone}" PR_HEAD_BRANCH="${BRANCH-claude/x}" \
    "$GUARD" >"$WORK/out" 2>&1
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
printf '%s' "$REF" | GIT_DIR_OVERRIDE="$FIXTURE" BASE_SHA="$BASE" \
  PR_HEAD_BRANCH=claude/x "$GUARD" >"$WORK/out" 2>&1
rc=$?
expect 2 'PR_ACTOR' 'missing actor fails closed as UNKNOWN rather than passing'

# ...but an unrelated change must not demand CI context at all.
printf '%s' 'README.md' | GIT_DIR_OVERRIDE="$FIXTURE" "$GUARD" >"$WORK/out" 2>&1
rc=$?
expect 0 'no bundled skill tree touched' 'an unrelated change needs no CI context'

echo
if [ "$fail" -gt 0 ]; then
  echo "FAIL: bundled-skill edit guard ($pass passed, $fail failed)"
  exit 1
fi
echo "PASS: bundled-skill edit guard ($pass cases)"
