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
  cat <<'USAGE'
usage: guard-bundled-skill-edits.sh [-z|--null]

Reads changed paths on stdin (repo-relative), newline-separated by default.

  -z, --null   read NUL-separated paths, as produced by `git diff -z --name-only`.
               PREFER THIS IN CI. `git diff --name-only` quotes any path it considers
               unusual — non-ASCII, spaces, quotes, backslashes — emitting a leading
               `"` and octal escapes. A quoted path matches none of the anchored
               patterns below, so the file is dropped before any provenance check and
               the guard passes an edit it should have refused. The attacker picks the
               filename, so that bypass needs no pre-existing condition. `-z` emits
               paths raw and unquoted, which removes the failure mode rather than
               working around it, and also handles a newline inside a filename.

Environment:
  BASE_SHA         required when any changed path is inside plugins/*/skills/*/
  HEAD_SHA         required with BASE_SHA; the revision the change proposes. Used only
                   to tell a RETIREMENT from an edit: dropping a skill from a plugin is
                   plugin membership, which AGENTS.md says is authored here, so a skill
                   whose SKILL.md is gone at HEAD is allowed rather than refused with a
                   "fix it upstream" message that cannot be acted on.
  PR_ACTOR         the login that opened the change  (required, same condition)
  PR_HEAD_BRANCH   the head branch name              (required, same condition)
  SYNC_ACTOR       override the exempt actor         (default: botantler-1[bot])
  SYNC_BRANCH      override the exempt branch        (default: deps/agent-skills-update)
  GUARD_REPO_DIR   run git against this repo instead of the script's own

exit 0  no synced skill tree was touched, the change is the programmed sync, or the
        only bundled trees touched were newly added or retired outright
exit 1  a synced skill tree was hand-edited
exit 2  usage, or the context needed to decide is missing/unreadable
USAGE
}

git_at() { git -C "${GUARD_REPO_DIR:-$REPO_ROOT}" "$@"; }

# skill_dir_of PATH -> "plugins/<plugin>/skills/<skill>" for a path inside a skill,
# empty otherwise. Anchored, and it requires at least one path component BELOW the
# skill directory so `plugins/p/skills/s` itself is not mistaken for a file in it.
#
# 🔴 SPLIT ON COMPONENTS, DO NOT GLOB. A shell `*` matches `/` too, so the pattern
# `plugins/*/skills/*/*` also accepts `plugins/p/EXTRA/skills/s/f.md` — and taking the
# first four components of that yields `plugins/p/EXTRA/skills`, a directory holding no
# SKILL.md. That mis-derived directory then reads as "no upstream recorded", i.e. as a
# locally-authored skill, and the edit is allowed. Splitting on `/` and requiring the
# literal components in their exact positions cannot drift that way, and it replaces
# four `cut` subshells per path with none.
skill_dir_of() {
  local a b c d rest IFS=/
  read -r a b c d rest <<<"$1"
  [ "$a" = plugins ] || return 0
  [ "$c" = skills ] || return 0
  [ -n "$b" ] && [ -n "$d" ] && [ -n "$rest" ] || return 0
  printf '%s/%s/%s/%s\n' "$a" "$b" "$c" "$d"
}

# exists_at REV PATH -> true when the blob is present at that revision.
exists_at() { git_at cat-file -e "${1}:${2}" 2>/dev/null; }

# upstream_at_base SKILL_DIR -> the metadata.github-repo recorded at BASE_SHA.
# Returns 1 when the skill did not exist at base (a new skill), which is the one shape
# this guard lets through, and 2 when the answer cannot be read at all.
#
# 🔴 "ABSENT" AND "UNREADABLE" ARE DIFFERENT ANSWERS. Collapsing every `git show`
# failure into "new skill" hands the guard's single most reassuring output — "only new
# or locally-authored skill directories touched" — to an unreadable base, a corrupt or
# partial object store, or a mis-derived path. That is an affirmative all-clear the
# guard has not earned, and it contradicts this script's own promise to exit 2 when the
# context is unreadable. Probe existence first, and only call it new when the base
# itself is readable and the file is genuinely not in it.
upstream_at_base() {
  local skill_dir="$1" blob
  if ! exists_at "$BASE_SHA" "${skill_dir}/SKILL.md"; then
    git_at cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null || return 2
    return 1
  fi
  blob="$(git_at show "${BASE_SHA}:${skill_dir}/SKILL.md" 2>/dev/null)" || return 2
  # The provenance line must sit INSIDE the metadata: block, so a top-level
  # github-repo: cannot satisfy it.
  #
  # ⚠️ This is deliberately NOT byte-identical to validate-manifests.sh's
  # `validate_skill_provenance`, and the difference matters in one direction: that one
  # accepts a literal `null` as valid provenance, while this treats it as "no upstream
  # recorded" and therefore lets the edit through. A skill carrying `github-repo: null`
  # is consequently green there and unguarded here. Reconciling the two into one shared
  # parser is worth doing; until then, do not describe them as the same rule.
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
  local nul=0
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -z|--null) nul=1; shift ;;
  esac
  [ "$#" -eq 0 ] || { echo "::error::unexpected argument: $1"; usage >&2; exit 2; }

  local -a touched=()
  local line skill_dir
  while { [ "$nul" -eq 1 ] && IFS= read -r -d '' line; } ||
        { [ "$nul" -eq 0 ] && IFS= read -r line; } || [ -n "${line:-}" ]; do
    [ -n "$line" ] || continue
    # 🔴 A QUOTED PATH IS UNKNOWN, NEVER "no match". In newline mode the producer may be
    # `git diff --name-only`, which quotes any path it considers unusual. Such a path
    # matches nothing below, so it would be dropped silently and the guard would pass an
    # edit it never inspected — the exact fail-open `-z` exists to remove. Callers that
    # cannot use `-z` must at least be told the input was unreadable.
    case "$line" in
      '"'*) echo "::error::changed path arrived quoted, so it cannot be matched reliably: $line"
            echo "  re-run the producer with -z (or core.quotePath=false) and pass --null"
            exit 2 ;;
    esac
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
  [ -n "${HEAD_SHA:-}" ]       || missing+=(HEAD_SHA)
  [ -n "${PR_ACTOR:-}" ]       || missing+=(PR_ACTOR)
  [ -n "${PR_HEAD_BRANCH:-}" ] || missing+=(PR_HEAD_BRANCH)
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "::error::a bundled skill tree changed but the context to judge it is missing: ${missing[*]}"
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
  local -a seen=() offenders=() retired=()
  local d s upstream rc
  for d in "${touched[@]}"; do
    for s in ${seen[@]+"${seen[@]}"}; do [ "$s" = "$d" ] && continue 2; done
    seen+=("$d")
    upstream="$(upstream_at_base "$d")" && rc=0 || rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "::error::cannot read ${d}/SKILL.md at ${BASE_SHA}, so this change cannot be judged"
      exit 2
    fi
    [ "$rc" -eq 0 ] && [ -n "$upstream" ] || continue
    # Retiring a bundled skill is plugin membership, which IS authored here — and it is
    # unblockable by the message this guard would otherwise print, since there is nothing
    # to "fix upstream" about a directory you are removing.
    if ! exists_at "$HEAD_SHA" "${d}/SKILL.md"; then
      retired+=("$d")
      continue
    fi
    offenders+=("$d	$upstream")
  done

  if [ "${#offenders[@]}" -eq 0 ]; then
    if [ "${#retired[@]}" -gt 0 ]; then
      echo "✓ bundled skill(s) retired outright, which is plugin membership and authored here:"
      for d in "${retired[@]}"; do printf '  %s\n' "$d"; done
    else
      echo "✓ only new or locally-authored skill directories touched"
    fi
    exit 0
  fi

  echo "::error::a bundled skill was edited here, and the daily sync will silently revert it"
  local entry
  for entry in "${offenders[@]}"; do
    printf '  %s\n    fix it upstream in %s, then let the sync pull it through\n' \
      "${entry%%	*}" "${entry##*	}"
  done
  exit 1
}

main "$@"
