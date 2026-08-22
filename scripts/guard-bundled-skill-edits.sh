#!/usr/bin/env bash
# Refuse a hand-edit to a bundled skill's tree, and name the upstream that owns it.
#
# WHY THIS EXISTS
# Bundled skills are executable agent instructions pulled from other people's
# repositories by `gh skill install`. The daily sync re-pulls them, so an edit
# committed here is overwritten on the next run with no conflict, no CI failure
# and no signal — it reads as fixed while changing nothing. That is not a
# hypothetical: a review finding was raised against
# plugins/github/skills/github-issues/references/milestones.md, whose upstream is
# github/awesome-copilot, and the fix could not land where it was found (#116).
#
# WHAT IT CHECKS
# A skill is SYNCED when its SKILL.md carried `metadata.github-repo` AT THE BASE
# REF. Changing any file inside a synced skill's directory fails, and the error
# names the upstream to fix it in. Provenance is read from the base rather than
# the head so the guard cannot be disabled by deleting the provenance line in the
# same commit that edits the skill.
#
# WHAT IT DELIBERATELY ALLOWS
#   - The programmed sync PR (actor + branch must BOTH match) — that is the one
#     writer these trees are supposed to have.
#   - Adding a wholly NEW skill directory. It does not exist at the base ref, so
#     there is no upstream copy to diverge from yet; `gh skill install` followed by
#     a commit stays a one-step operation.
#   - Everything authored here: manifests, plugin.json, agents/, docs, scripts.
#
# WHAT IT CANNOT CHECK
# Whether the bundled bytes still match the upstream. There is no lockfile, and
# `metadata.github-tree-sha` names the UPSTREAM tree, which never equals the
# bundled tree because `gh skill install` rewrites the frontmatter on the way in.
# Verifying that needs a network fetch of a third-party repository. This guard
# closes the silent-revert path only; it is not an integrity check.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SYNC_ACTOR="${SYNC_ACTOR:-botantler-1[bot]}"
SYNC_BRANCH="${SYNC_BRANCH:-deps/agent-skills-update}"

usage() {
  cat >&2 <<'USAGE'
usage: guard-bundled-skill-edits.sh

Reads NEWLINE-separated changed paths on stdin (repo-relative).

Environment:
  BASE_SHA         required when any changed path is inside plugins/*/skills/*/
  PR_ACTOR         the login that opened the change  (required, same condition)
  PR_HEAD_BRANCH   the head branch name              (required, same condition)
  SYNC_ACTOR       override the exempt actor         (default: botantler-1[bot])
  SYNC_BRANCH      override the exempt branch        (default: deps/agent-skills-update)
  GIT_DIR_OVERRIDE run git against this repo instead of the script's own

exit 0  no synced skill tree was touched, or the change is the programmed sync
exit 1  a synced skill tree was hand-edited
exit 2  usage, or the context needed to decide is missing/unreadable
USAGE
}

git_at() { git -C "${GIT_DIR_OVERRIDE:-$REPO_ROOT}" "$@"; }

# skill_dir_of PATH -> "plugins/<plugin>/skills/<skill>" for a path inside a skill,
# empty otherwise. Anchored, and it requires at least one path component BELOW the
# skill directory so `plugins/p/skills/s` itself is not mistaken for a file in it.
skill_dir_of() {
  case "$1" in
    plugins/*/skills/*/*)
      printf '%s/%s/%s/%s\n' \
        "$(printf '%s' "$1" | cut -d/ -f1)" \
        "$(printf '%s' "$1" | cut -d/ -f2)" \
        "$(printf '%s' "$1" | cut -d/ -f3)" \
        "$(printf '%s' "$1" | cut -d/ -f4)"
      ;;
    *) : ;;
  esac
}

# upstream_at_base SKILL_DIR -> the metadata.github-repo recorded at BASE_SHA.
# Prints nothing and returns 1 when the skill did not exist at base (a new skill),
# which is the one shape this guard lets through.
upstream_at_base() {
  local skill_dir="$1" blob
  blob="$(git_at show "${BASE_SHA}:${skill_dir}/SKILL.md" 2>/dev/null)" || return 1
  # The provenance line must sit INSIDE the metadata: block, so a top-level
  # github-repo: cannot satisfy it — same rule validate-manifests.sh applies.
  printf '%s\n' "$blob" | awk '
    /^metadata:[[:space:]]*$/ { in_meta = 1; next }
    /^[^[:space:]]/           { in_meta = 0 }
    in_meta && /^[[:space:]]+github-repo:[[:space:]]*/ {
      v = $0
      sub(/^[[:space:]]+github-repo:[[:space:]]*/, "", v)
      gsub(/^[\"'"'"']|[\"'"'"']$/, "", v)
      if (v != "" && v != "null") { print v; exit }
    }
  '
}

main() {
  case "${1:-}" in -h|--help) usage; exit 2 ;; esac
  [ "$#" -eq 0 ] || { echo "::error::unexpected argument: $1" >&2; usage; exit 2; }

  local -a touched=()
  local line skill_dir
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    skill_dir="$(skill_dir_of "$line")"
    [ -n "$skill_dir" ] || continue
    touched+=("$skill_dir")
  done

  if [ "${#touched[@]}" -eq 0 ]; then
    echo "✓ no bundled skill tree touched"
    exit 0
  fi

  # Context is only required once we know a skill tree was touched, so an ordinary
  # PR that edits nothing bundled never needs it. Missing context here is UNKNOWN,
  # and UNKNOWN fails closed: deciding "not the sync PR" without being able to read
  # the actor would block every legitimate sync instead.
  local missing=()
  [ -n "${BASE_SHA:-}" ]       || missing+=(BASE_SHA)
  [ -n "${PR_ACTOR:-}" ]       || missing+=(PR_ACTOR)
  [ -n "${PR_HEAD_BRANCH:-}" ] || missing+=(PR_HEAD_BRANCH)
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "::error::a bundled skill tree changed but the context to judge it is missing: ${missing[*]}" >&2
    exit 2
  fi

  # BOTH must match. Either alone is forgeable by anyone who can name a branch or
  # who happens to be the App acting on some other branch.
  if [ "$PR_ACTOR" = "$SYNC_ACTOR" ] && [ "$PR_HEAD_BRANCH" = "$SYNC_BRANCH" ]; then
    echo "✓ programmed skill sync (${SYNC_ACTOR} on ${SYNC_BRANCH}) — bundled trees are its to write"
    exit 0
  fi

  # Deduplicate while preserving first-seen order, so one edited skill is reported
  # once however many of its files changed.
  local -a seen=() offenders=()
  local d s
  for d in "${touched[@]}"; do
    for s in ${seen[@]+"${seen[@]}"}; do [ "$s" = "$d" ] && continue 2; done
    seen+=("$d")
    local upstream
    if upstream="$(upstream_at_base "$d")" && [ -n "$upstream" ]; then
      offenders+=("$d	$upstream")
    fi
  done

  if [ "${#offenders[@]}" -eq 0 ]; then
    echo "✓ only new or locally-authored skill directories touched"
    exit 0
  fi

  echo "::error::a bundled skill was edited here, and the daily sync will silently revert it" >&2
  local entry
  for entry in "${offenders[@]}"; do
    printf '  %s\n    fix it upstream in %s, then let the sync pull it through\n' \
      "${entry%%	*}" "${entry##*	}" >&2
  done
  exit 1
}

main "$@"
