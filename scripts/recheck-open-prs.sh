#!/usr/bin/env bash
# Re-trigger the required checks on every open pull request targeting the default branch.
#
# WHY THIS EXISTS
#   A pull-request workflow runs only on that PR's own `pull_request` events. Every PR already
#   open when a new required gate lands on the default branch therefore keeps the green
#   `CI - Required Checks` result it earned BEFORE the gate existed, and the branch rule keyed on
#   that check name is satisfied by the stale run. Such a PR can merge without the new gate ever
#   having run against it — exactly the class of change (a version left unbumped, a synced skill
#   hand-edited) each gate was added to stop.
#
#   The repository's ruleset does not set `strict_required_status_checks_policy`, which is
#   GitHub's own mechanism for this ("require branches to be up to date before merging"), and it
#   is declared org-wide and Observe-only, so it is not this repository's to flip. This script is
#   the repository-scoped equivalent: after the gate lands, ask every open PR to run again.
#
# WHY A FRESH BASE, AND NOT A RE-RUN
#   Re-running a workflow run reuses the ORIGINAL event's `GITHUB_SHA` and `GITHUB_REF`. For a
#   `pull_request` run that ref is `refs/pull/N/merge`, so a re-run replays the merge commit as it
#   stood before the gate landed — with the old workflow file. Only a NEW `pull_request` event
#   resolves the merge ref again and picks the new gate up. Same-repository branches are updated
#   through the head-checked update-branch API, preserving their commits and open state. This
#   moves the head and requires review at that new head. Current non-Dependabot branches and
#   forks use `reopened`, which preserves their head and starts CI for App-created drafts.
#   Current Dependabot branches require an observed PR run without closing; Dependabot forks
#   are refused because closing a Dependabot PR can suppress a wanted update.
#
# WHY AN APP TOKEN IS REQUIRED
#   Events produced with the repository's `GITHUB_TOKEN` do not start new workflow runs, so a
#   branch update or reopen performed with it would be silent. The caller must pass a token from the repository's
#   GitHub App — the same reason `update-agent-skills.yaml` mints one to open its PR.
#
# THE TWO THINGS THIS MUST NEVER LEAVE BEHIND
#   A pull request closed, and an auto-merge that was armed before the run and is not after it.
#   Both are tracked in a state directory from BEFORE the mutation that could cause them, and the
#   exit trap settles both from the pull request's ACTUAL state rather than from an assumption
#   about whether a failed call took effect — a request can be applied and still report failure.
#
# Usage:
#   ./scripts/recheck-open-prs.sh --repo OWNER/NAME [--base BRANCH] [--dry-run]
#
# Reads `gh` from PATH and expects it already authenticated with an App token.
# Exit 0 when every selected PR was re-triggered (or none was selected), 1 when any PR could not
# be, 2 on a usage or environment error.
set -uo pipefail

# Explain the supported invocation and report a usage error.
usage() {
  cat >&2 <<'EOF'
usage: recheck-open-prs.sh --repo OWNER/NAME [--base BRANCH] [--dry-run]
EOF
  exit 2
}

repo=""
base="main"
dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || usage
      repo=$2
      shift 2
      ;;
    --base)
      [ "$#" -ge 2 ] || usage
      base=$2
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    *) usage ;;
  esac
done

[ -n "$repo" ] || usage
# A malformed slug would silently address a different repository, so it is validated rather
# than passed through.
case "$repo" in
  */*/*) usage ;;
  */*) ;;
  *) usage ;;
esac

command -v gh > /dev/null 2>&1 || {
  echo "recheck-open-prs: gh is required" >&2
  exit 2
}
# Used to take every field of a pull request's auto-merge request out of ONE response, so a
# transient failure cannot be mistaken for "no custom metadata".
command -v jq > /dev/null 2>&1 || {
  echo "recheck-open-prs: jq is required" >&2
  exit 2
}
# Probe the needed behavior rather than a version: Apple jq 1.7 preserves decimals
# but does not expose have_decnum. Rounded input cannot safely validate run counts.
if ! jq -ner '1.000000000000000001|tojson=="1.000000000000000001"' > /dev/null 2>&1; then
  echo "recheck-open-prs: jq must preserve decimal-number spelling" >&2
  exit 2
fi
# This repository's automation always addresses github.com, including recovery.
export GH_HOST=github.com

# A hosted caller supplies a collection root to upload unresolved settings after this process.
# Snapshot fields are PR metadata only; credentials and environment values are never journaled.
umask 077
if [ -n "${RECHECK_RECOVERY_ROOT:-}" ]; then
  case "$RECHECK_RECOVERY_ROOT" in /*) ;; *) echo "recheck-open-prs: recovery root must be absolute" >&2; exit 2 ;; esac
  if [ -L "$RECHECK_RECOVERY_ROOT" ] || ! mkdir -p "$RECHECK_RECOVERY_ROOT"; then
    echo "recheck-open-prs: recovery root could not be prepared" >&2
    exit 2
  fi
  state=$(mktemp -d "$RECHECK_RECOVERY_ROOT/recheck.XXXXXX") || exit 2
else
  state=$(mktemp -d) || exit 2
fi
mkdir -p "$state/closed" "$state/rearm" || exit 2
held_recovery=""

# How long to wait for the reopened event's own workflow run before declining to re-arm.
# Overridable so the self-test does not sleep.
CHECK_WAIT_SECONDS=${RECHECK_CHECK_WAIT_SECONDS:-90}
CHECK_POLL_SECONDS=${RECHECK_CHECK_POLL_SECONDS:-3}

# Restore anything this run may have disturbed. Both loops decide from the pull request's real
# state, because a call that reports failure may still have been applied: `gh pr close` can time
# out after GitHub accepted it, and dropping the record on that nonzero exit would leave the PR
# closed with nothing tracking it.
# shellcheck disable=SC2317,SC2329  # invoked indirectly, by the EXIT trap below. Both codes are
# needed: shellcheck >= 0.11 reports the unused-looking function as SC2329 on its declaration,
# while older versions — including the one CI installs — report every line of its body as
# unreachable, SC2317. A directive naming only one version's code passes here and fails there.
settle() {
  local original_status=$? f n st method headline body sha baseline before current recovery_failed=0
  for f in "$state/closed"/*; do
    [ -e "$f" ] || continue
    n=${f##*/}
    if ! before=$(cat "$f") || ! current=$(gh pr view "$n" --repo "$repo" --json state,autoMergeRequest,headRefOid,baseRefOid,baseRefName,number,author,isCrossRepository) \
      || ! printf '%s' "$current" | jq -e --argjson before "$before" '
        type=="object" and .number==$before.number and .headRefOid==$before.headRefOid and
        .baseRefName==$before.baseRefName and .author.login==$before.author.login and
        .isCrossRepository==$before.isCrossRepository and
        (.state=="OPEN" or .state=="CLOSED" or .state=="MERGED")' >/dev/null; then
      echo "::error::#$n recovery identity is unverified; inspect and reopen it by hand" >&2
      recovery_failed=1
      continue
    fi
    st=$(printf '%s' "$current" | jq -r '.state')
    if [ "$st" = "OPEN" ] || [ "$st" = "MERGED" ]; then
      rm -f "$f"
      continue
    fi
    echo "recheck-open-prs: reopening #$n, left closed (state=$st)" >&2
    # An ambiguous acknowledgement may have applied; only readback proves recovery.
    gh pr reopen "$n" --repo "$repo" > /dev/null 2>&1 || true
    if ! verify_reopened "$n" "$before"; then
      echo "::error::#$n recovery reopen is unverified; reopen it by hand" >&2
      recovery_failed=1
    else
      rm -f "$f"
    fi
  done
  for f in "$state/rearm"/*; do
    [ -e "$f" ] || continue
    n=${f##*/}
    # An explicit CI hold stays manual; keep the saved settings without retrying a merge.
    case " $held_recovery " in
      *" $n "*)
        echo "::error::#$n auto-merge remains held; original settings retained for the operator" >&2
        recovery_failed=1
        continue ;;
    esac
    if ! before=$(cat "$state/rearm/$n/before"); then
      echo "::error::#$n recovery record is unreadable; inspect auto-merge by hand" >&2
      recovery_failed=1
      continue
    fi
    # Already armed is insufficient: it must still match the original settings.
    if verify_rearmed "$n" "$before"; then rm -rf "$f"; continue; fi
    if ! verify_reopened "$n" "$before" || ! read_recovery "$n"; then
      echo "::error::#$n auto-merge recovery state is unverified; inspect it by hand" >&2
      recovery_failed=1
      continue
    fi
    # The same wait the main path performs, and for the same reason: arming auto-merge while the
    # pre-gate green is still the newest result can merge the PR before the new run exists.
    if ! await_fresh_check "$sha" "$baseline"; then
      echo "::error::#$n auto-merge was NOT restored: no pull_request run from the reopen appeared, and arming it now could merge the PR on the pre-gate result. Re-arm it by hand once its checks are running." >&2
      recovery_failed=1
      continue
    fi
    echo "recheck-open-prs: restoring auto-merge on #$n" >&2
    if ! verify_reopened "$n" "$before"; then
      echo "::error::#$n auto-merge was NOT restored: reopened state moved or is unreadable." >&2
      recovery_failed=1
      continue
    fi
    rearm "$n" "$method" "$headline" "$body" "$sha" > /dev/null 2>&1 || true
    if ! verify_rearmed "$n" "$before"; then
      echo "::error::#$n auto-merge recovery is unverified; re-arm it by hand" >&2
      recovery_failed=1
    else
      rm -rf "$f"
    fi
  done
  if [ "$recovery_failed" -eq 0 ]; then
    rm -rf "$state"
  else
    echo "::error::Unverified recovery; original settings retained in private records at $state" >&2
  fi
  [ "$original_status" -ne 0 ] || [ "$recovery_failed" -eq 0 ] || exit 1
}

# The highest WORKFLOW RUN id for a `pull_request` event at a commit, or 0 when it has none.
#
# Workflow runs, not check runs, and this distinction is the whole point. Re-running an existing
# workflow keeps its run id and adds an attempt, but it creates fresh CHECK runs with new ids and
# the same name — so a manual rerun of the pre-gate run would satisfy a check-run comparison while
# no run for the reopen existed at all. A new `pull_request` run id can only come from a new
# `pull_request` event, which is exactly what is being waited for. Another such event (a push, say)
# would satisfy it too, and legitimately: it also resolves a fresh merge ref.
#
# Ids increase, so a larger one later means a newer run — no clock, and no assumption about either
# side's timekeeping. Exits non-zero when the read fails, so a caller can tell "none yet" (0) from
# "unknown". The parameters are GET fields rather than query text for the same reason as the
# listing: a value spliced into the path could change which runs are counted.
newest_pr_run() {
  local sha=$1 observation
  observation=$(gh api --paginate --slurp --method GET "repos/${repo}/actions/workflows/ci.yaml/runs" \
    -f event=pull_request -f head_sha="$sha" -F per_page=100) || return 1
  printf '%s' "$observation" | jq -er --arg sha "$sha" --arg repo "$repo" '
    # Keep the original numeric spelling: floor/equality can round a fraction.
    def integer: type=="number" and (tojson|test("^(0|[1-9][0-9]*)$")) and .<=9007199254740991;
    if type=="array" and length>0 and all(.[];
      type=="object" and (.total_count|integer) and (.workflow_runs|type=="array")) then
      . as $pages | [.[].workflow_runs[]] as $runs |
      if all($pages[]; .total_count==$pages[0].total_count) and
        ($runs|length)==$pages[0].total_count and
        all($runs[]; type=="object" and (.id|integer and .>0) and
          .event=="pull_request" and .head_sha==$sha and
          (.path|type=="string" and test("^\\.github/workflows/ci\\.yaml(@.+)?$")) and
          .repository.full_name==$repo) and
        ($runs|map(.id)|unique|length)==($runs|length)
      then ($runs|map(.id)|max // 0) else error("incomplete or mismatched CI runs") end
    else error("invalid CI run observation") end'
}

# Every journal write is checked before close can clear the original merge request.
save_recovery() {
  local n=$1 before=$2 baseline=$3
  mkdir -p "$state/rearm/$n" || return 1
  printf '%s' "$before" > "$state/rearm/$n/before" || return 1
  printf '%s' "$before" | jq -jr '.autoMergeRequest.mergeMethod // ""' > "$state/rearm/$n/method" || return 1
  printf '%s' "$before" | jq -jr '.autoMergeRequest.commitHeadline // ""' > "$state/rearm/$n/headline" || return 1
  printf '%s' "$before" | jq -jr '.autoMergeRequest.commitBody // ""' > "$state/rearm/$n/body" || return 1
  printf '%s' "$before" | jq -jr '.headRefOid' > "$state/rearm/$n/sha" || return 1
  printf '%s' "$baseline" > "$state/rearm/$n/baseline" || return 1
}

# Sentinel reads retain trailing newlines; cat's failure still propagates.
# Dynamic caller locals are intentional: both main and recovery use these values.
read_recovery() {
  local n=$1
  method=$(cat "$state/rearm/$n/method") || return 1
  headline=$(cat "$state/rearm/$n/headline" && printf x) || return 1
  headline=${headline%x}
  body=$(cat "$state/rearm/$n/body" && printf x) || return 1
  body=${body%x}
  sha=$(cat "$state/rearm/$n/sha") || return 1
  baseline=$(cat "$state/rearm/$n/baseline") || return 1
}

# Block until a `pull_request` workflow run newer than $2 exists at commit $1. Auto-merge means "merge once the
# requirements are met", and immediately after a reopen the newest result at that commit is still
# the PRE-GATE green: arming there can merge the pull request in the window before Actions has
# created the run for the reopen, past the very gate this script exists to apply. Returns
# non-zero if no new run appears, and the caller then declines to arm — an auto-merge a human
# must restore is recoverable, a merge that skipped a gate is not.
await_fresh_check() {
  local sha=$1 baseline=$2 waited=0 now
  # An absent sha or baseline is unknown, not zero: comparing against an invented lower bound
  # would let any historical run satisfy the wait immediately.
  [ -n "$sha" ] || return 1
  case "$baseline" in '' | *[!0-9]*) return 1 ;; esac
  while [ "$waited" -lt "$CHECK_WAIT_SECONDS" ]; do
    # A failed poll is "not yet", never "satisfied" — the loop simply keeps waiting.
    if now=$(newest_pr_run "$sha") && case "$now" in '' | *[!0-9]*) false ;; *) true ;; esac; then
      [ "$now" -gt "$baseline" ] && return 0
    fi
    sleep "$CHECK_POLL_SECONDS"
    waited=$((waited + CHECK_POLL_SECONDS))
  done
  return 1
}

# A successful write acknowledgement is not readback proof, including on unarmed PRs.
verify_reopened() {
  local n=$1 before=$2 current
  current=$(gh pr view "$n" --repo "$repo" --json state,autoMergeRequest,headRefOid,baseRefOid,baseRefName,number,author,isCrossRepository) || return 1
  printf '%s' "$current" | jq -e --argjson before "$before" '
    type=="object" and has("autoMergeRequest") and .autoMergeRequest==null and
    .state=="OPEN" and .number==$before.number and .headRefOid==$before.headRefOid and
    .baseRefOid==$before.baseRefOid and .baseRefName==$before.baseRefName and
    .author.login==$before.author.login and .isCrossRepository==$before.isCrossRepository' >/dev/null
}

# Verify the original merge strategy and metadata from a fresh identity-bound read.
verify_rearmed() {
  local n=$1 before=$2 current
  current=$(gh pr view "$n" --repo "$repo" --json state,autoMergeRequest,headRefOid,baseRefOid,baseRefName,number,author,isCrossRepository) || return 1
  printf '%s' "$current" | jq -e --argjson before "$before" '
    type=="object" and .number==$before.number and .headRefOid==$before.headRefOid and
    .baseRefName==$before.baseRefName and .author.login==$before.author.login and
    .isCrossRepository==$before.isCrossRepository and
    (.state=="MERGED" or (.state=="OPEN" and .baseRefOid==$before.baseRefOid and
      .autoMergeRequest.mergeMethod==$before.autoMergeRequest.mergeMethod and
      (.autoMergeRequest.commitHeadline // "")==($before.autoMergeRequest.commitHeadline // "") and
      (.autoMergeRequest.commitBody // "")==($before.autoMergeRequest.commitBody // "")))' >/dev/null
}

# Re-arm auto-merge exactly as it was: the same strategy, and the same commit metadata.
# Recreating it as a default squash would silently change both the merge behaviour and the
# message someone chose deliberately.
rearm() {
  local n=$1 method=$2 headline=$3 body=$4 sha=$5 flag
  case "$method" in
    MERGE) flag=--merge ;;
    REBASE) flag=--rebase ;;
    SQUASH) flag=--squash ;;
    *) echo "::error::Unknown auto-merge method; refusing to guess." >&2; return 1 ;;
  esac
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  set -- "$n" --repo "$repo" --auto "$flag" --match-head-commit "$sha"
  # A rebase carries no commit message of its own, so those flags apply to the other two only.
  if [ "$flag" != "--rebase" ]; then
    set -- "$@" --subject "$headline" --body "$body"
  fi
  gh pr merge "$@"
}

# Update only a same-repository branch, retaining its complete prior history and merge settings.
# GitHub's expected_head_sha rejects an intervening push. Accepted asynchronous writes are not
# success evidence: read back the new head, verify both ancestors, then observe its PR event.
# Return 3 only for a current non-Dependabot branch that needs the existing reopen route.
refresh_same_repository() {
  local n=$1 before=$2 old_head old_base relation current new_head new_base base_path final_base waited=0
  old_head=$(printf '%s' "$before" | jq -r '.headRefOid')
  # A PR's associated base OID is not proof of the current named branch tip.
  base_path=$(printf '%s' "$base" | jq -sRr @uri)
  if ! old_base=$(gh api "repos/$repo/branches/$base_path" --jq '.commit.sha'); then
    echo "::error::#$n current base could not be read; left untouched"
    return 1
  fi
  if [[ ! "$old_head" =~ ^[0-9a-f]{40}$ || ! "$old_base" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::#$n commit identity is incomplete; left untouched"
    return 1
  fi
  if ! relation=$(gh api "repos/$repo/compare/$old_base...$old_head" --jq '.status'); then
    echo "::error::#$n base ancestry could not be read; left untouched"
    return 1
  fi
  case "$relation" in
    ahead|identical)
      case "$(printf '%s' "$before" | jq -r '.author.login')" in
        'app/dependabot'|'dependabot[bot]')
          # This is verification of an already-current head, not a newly triggered event.
          # A pre-gate head cannot enter this route: it fails the named-base ancestry above.
          if ! await_fresh_check "$old_head" 0; then
            echo "::error::#$n contains the current base but no PR workflow run was observed; left open"
            return 1
          fi
          if ! current=$(gh pr view "$n" --repo "$repo" --json state,autoMergeRequest,headRefOid,baseRefOid,baseRefName,number,author,isCrossRepository) \
            || ! printf '%s' "$current" | jq -e --argjson before "$before" \
              'has("autoMergeRequest") and .state=="OPEN" and .number==$before.number and .baseRefName==$before.baseRefName and
               .headRefOid==$before.headRefOid and .isCrossRepository==false and
               .author.login==$before.author.login and .autoMergeRequest==$before.autoMergeRequest' > /dev/null \
            || ! final_base=$(gh api "repos/$repo/branches/$base_path" --jq '.commit.sha') \
            || [ "$final_base" != "$old_base" ]; then
            echo "::error::#$n moved during the check wait; current refresh is unverified"
            return 1
          fi
          echo "  checked #$n — its head contains the current base and has an observed PR run"
          return 0 ;;
        *) return 3 ;;
      esac ;;
    behind|diverged) ;;
    *) echo "::error::#$n base ancestry is unknown; left untouched"; return 1 ;;
  esac
  if ! gh api --method PUT "repos/$repo/pulls/$n/update-branch" -f expected_head_sha="$old_head" > /dev/null; then
    echo "::error::#$n head-checked base update failed; no close or recreation attempted"
    return 1
  fi
  while [ "$waited" -lt "$CHECK_WAIT_SECONDS" ]; do
    if ! current=$(gh pr view "$n" --repo "$repo" --json state,autoMergeRequest,headRefOid,baseRefOid,baseRefName,number,author,isCrossRepository) \
      || ! printf '%s' "$current" | jq -e --argjson before "$before" --arg base "$base" \
        'has("autoMergeRequest") and .state=="OPEN" and .number==$before.number and .baseRefName==$base and
         .isCrossRepository==false and .author.login==$before.author.login and
         .autoMergeRequest==$before.autoMergeRequest and (.headRefOid|test("^[0-9a-f]{40}$")) and
         (.baseRefOid|test("^[0-9a-f]{40}$"))' > /dev/null; then
      echo "::error::#$n updated state is unreadable or changed; no recovery mutation attempted"
      return 1
    fi
    new_head=$(printf '%s' "$current" | jq -r '.headRefOid')
    if ! new_base=$(gh api "repos/$repo/branches/$base_path" --jq '.commit.sha') \
      || [[ ! "$new_base" =~ ^[0-9a-f]{40}$ ]]; then
      echo "::error::#$n current base became unreadable; refresh is unverified"
      return 1
    fi
    if [ "$new_head" != "$old_head" ]; then
      if ! relation=$(gh api "repos/$repo/compare/$old_head...$new_head" --jq '.status') || [ "$relation" != ahead ]; then
        echo "::error::#$n updated head does not prove preservation of the previous commits"
        return 1
      fi
      if ! relation=$(gh api "repos/$repo/compare/$new_base...$new_head" --jq '.status') \
        || { [ "$relation" != ahead ] && [ "$relation" != identical ]; }; then
        echo "::error::#$n updated head does not prove inclusion of the current base"
        return 1
      fi
      if ! await_fresh_check "$new_head" 0; then
        echo "::error::#$n base was updated, but no fresh pull_request workflow run was observed"
        return 1
      fi
      # A check observed at one head cannot certify a successor pushed during the wait.
      if ! current=$(gh pr view "$n" --repo "$repo" --json state,autoMergeRequest,headRefOid,baseRefOid,baseRefName,number,author,isCrossRepository) \
        || ! printf '%s' "$current" | jq -e --argjson before "$before" --arg head "$new_head" --arg base "$base" \
          'has("autoMergeRequest") and .state=="OPEN" and .number==$before.number and .baseRefName==$base and
           .headRefOid==$head and .isCrossRepository==false and .author.login==$before.author.login and
           .autoMergeRequest==$before.autoMergeRequest' > /dev/null \
        || ! final_base=$(gh api "repos/$repo/branches/$base_path" --jq '.commit.sha') \
        || [ "$final_base" != "$new_base" ]; then
        echo "::error::#$n moved during the check wait; current refresh is unverified"
        return 1
      fi
      echo "  refreshed #$n at $new_head — prior commits and auto-merge settings preserved; current-head review required"
      return 0
    fi
    sleep "$CHECK_POLL_SECONDS"
    waited=$((waited + CHECK_POLL_SECONDS))
  done
  echo "::error::#$n accepted update did not produce an observed new head"
  return 1
}

trap settle EXIT

# `gh pr list --limit N` fetches at most N, so any cap silently skips the pull requests past it
# and leaves them on the pre-gate result — the exact failure this script exists to prevent, just
# further down the list. `gh api --paginate` walks every page instead.
#
# The query parameters are passed as GET fields rather than interpolated into the path: a branch
# name may legally contain `&` or `#`, which spliced into a query string would silently select a
# different set of pull requests. `--method GET` is what keeps gh from turning the fields into a
# POST body.
#
# Auto-merge is deliberately NOT read here. A snapshot taken now could be minutes old by the time
# a given PR is processed, and re-arming from it would restore an auto-merge someone disabled in
# between — a merge nobody asked for. It is read per PR, immediately before closing.
if ! gh api --paginate --slurp --method GET "repos/${repo}/pulls" \
  -f state=open -f base="$base" -F per_page=100 > "$state/inventory"; then
  echo "recheck-open-prs: could not list open pull requests" >&2
  exit 2
fi
if ! jq -es --arg repo "$repo" --arg base "$base" '
  length==1 and (.[0] | type=="array" and length>0 and all(.[]; type=="array") and
  ([.[][]] | all(.[]; type=="object" and
    (.number|type=="number" and (tojson|test("^[1-9][0-9]*$")) and .<=9007199254740991) and
    (.title|type=="string") and .state=="open" and
    .base.ref==$base and .base.repo.full_name==$repo) and
    (map(.number)|unique|length)==length))' "$state/inventory" >/dev/null \
  || ! prs=$(jq -r '.[][]|[(.number|tostring),.title]|@tsv' "$state/inventory"); then
  echo "recheck-open-prs: open pull request inventory is malformed or contradictory; no PR was changed" >&2
  exit 2
fi

count=$(printf '%s' "$prs" | awk 'NF { n++ } END { print n + 0 }')

if [ "$count" -eq 0 ]; then
  echo "recheck-open-prs: no open pull requests targeting $base — nothing to re-trigger"
  exit 0
fi

echo "recheck-open-prs: re-triggering required checks on $count open PR(s) targeting $base"

failed=0
done_count=0

while IFS=$'\t' read -r number title; do
  [ -n "$number" ] || continue
  # A line that is not a PR number means the listing was not what it claimed to be. Failing here
  # keeps a malformed response from being read as a shorter list of real pull requests.
  case "$number" in
    '' | *[!0-9]*)
      echo "recheck-open-prs: open pull request listing is malformed near '$number'" >&2
      exit 2
      ;;
  esac

  if [ "$dry_run" -eq 1 ]; then
    echo "  would re-trigger #$number — $title"
    done_count=$((done_count + 1))
    continue
  fi

  # Read auto-merge fresh, immediately before closing, so the decision to restore it is based on
  # the state that is true now rather than when the sweep started. A read that fails leaves the
  # PR untouched: closing it without knowing would risk silently dropping an armed auto-merge.
  # ONE read, capturing everything this PR's handling depends on. Splitting it across calls made
  # a transient failure on a later call indistinguishable from "no custom metadata", which would
  # then be restored as GitHub's default message — a silent change to someone's chosen commit.
  # A failed read leaves the PR untouched: closing it without knowing its state would risk both
  # reversing a deliberate closure and dropping an armed auto-merge.
  if ! snapshot=$(gh pr view "$number" --repo "$repo" --json state,autoMergeRequest,headRefOid,baseRefOid,baseRefName,number,author,isCrossRepository) \
    || ! printf '%s' "$snapshot" | jq -e --argjson number "$number" --arg base "$base" \
      'type=="object" and has("autoMergeRequest") and (.author.login|type=="string" and test("\\S")) and
       .number==$number and .baseRefName==$base and (.isCrossRepository|type=="boolean") and
       (.state=="OPEN" or .state=="CLOSED" or .state=="MERGED")' > /dev/null; then
    echo "::error::#$number state could not be read; left untouched"
    failed=$((failed + 1))
    continue
  fi

  pr_state=$(printf '%s' "$snapshot" | jq -r '.state // ""')
  # The listing is a snapshot; a maintainer may have closed or merged this PR since. Reopening it
  # would reverse that deliberate act, and the `autoMergeRequest` read alone would not have
  # noticed — it succeeds for a closed pull request too.
  if [ "$pr_state" != "OPEN" ]; then
    echo "  skipped #$number — no longer open (state=${pr_state:-unknown})"
    continue
  fi

  if ! printf '%s' "$snapshot" | jq -e '
    (.headRefOid | type=="string" and test("^[0-9a-f]{40}$")) and
    (.baseRefOid | type=="string" and test("^[0-9a-f]{40}$")) and
    (.autoMergeRequest==null or (.autoMergeRequest | type=="object" and
      (.mergeMethod=="MERGE" or .mergeMethod=="REBASE" or .mergeMethod=="SQUASH") and
      (.commitHeadline | .==null or (type=="string" and (contains("\u0000")|not))) and
      (.commitBody | .==null or (type=="string" and (contains("\u0000")|not)))))' >/dev/null; then
    echo "::error::#$number identity or auto-merge strategy is unknown; left untouched"
    failed=$((failed + 1))
    continue
  fi

  if [ "$(printf '%s' "$snapshot" | jq -r '.isCrossRepository')" = false ]; then
    refresh_same_repository "$number" "$snapshot"
    refresh_status=$?
    if [ "$refresh_status" -eq 0 ]; then
      done_count=$((done_count + 1))
      continue
    elif [ "$refresh_status" -ne 3 ]; then
      failed=$((failed + 1))
      continue
    fi
  fi
  case "$(printf '%s' "$snapshot" | jq -r '.author.login')" in
    'app/dependabot'|'dependabot[bot]')
      echo "::error::#$number is a Dependabot fork; closing would suppress its update, so it was left untouched"
      failed=$((failed + 1))
      continue ;;
  esac

  head_sha=$(printf '%s' "$snapshot" | jq -r '.headRefOid')
  if ! check_baseline=$(newest_pr_run "$head_sha") ||
     case "$check_baseline" in '' | *[!0-9]*) true ;; *) false ;; esac; then
    echo "::error::#$number run baseline could not be read; left untouched"
    failed=$((failed + 1))
    continue
  fi

  automerge=$(printf '%s' "$snapshot" | jq -r 'if .autoMergeRequest == null then "none" else "armed" end')
  if [ "$automerge" = "armed" ]; then
    # Capture the strategy and commit metadata before the close clears the request, so the
    # restore puts back what was there rather than a default squash.
    if ! save_recovery "$number" "$snapshot" "$check_baseline"; then
      echo "::error::#$number recovery record could not be saved; left untouched"
      rm -rf "$state/rearm/$number"
      failed=$((failed + 1))
      continue
    fi
  fi

  # Close and reopen produce the `reopened` event that resolves a fresh merge ref. The head is
  # untouched, so a green review at the current head stays current. The record is written first
  # and is NOT removed when the close reports failure: a close can be applied and still report
  # one, and only the trap's read of the real state can tell those apart.
  if ! printf '%s' "$snapshot" > "$state/closed/$number"; then
    echo "::error::#$number close recovery record could not be saved; left untouched"
    rm -f "$state/closed/$number"
    rm -rf "$state/rearm/$number"
    failed=$((failed + 1))
    continue
  fi
  if ! gh pr close "$number" --repo "$repo" > /dev/null; then
    echo "::error::#$number could not be closed; skipped without re-triggering"
    failed=$((failed + 1))
    continue
  fi

  if ! gh pr reopen "$number" --repo "$repo" > /dev/null; then
    echo "::error::#$number was closed but could not be reopened"
    failed=$((failed + 1))
    continue
  fi
  if ! await_fresh_check "$head_sha" "$check_baseline" || ! verify_reopened "$number" "$snapshot"; then
    echo "::error::#$number reopen is unverified: no fresh PR event or matching OPEN readback; auto-merge was NOT restored, because it could merge the PR on the pre-gate result."
    held_recovery="$held_recovery $number"
    failed=$((failed + 1))
    continue
  fi
  rm -f "$state/closed/$number"

  if [ "$automerge" = "armed" ]; then
    if ! read_recovery "$number" || ! rearm "$number" "$method" "$headline" "$body" "$head_sha" > /dev/null ||
       ! verify_rearmed "$number" "$snapshot"; then
      # Left in the rearm set on purpose: once the close has cleared the request, a later run
      # cannot tell that this PR ever had auto-merge armed, so the obligation has to survive
      # here or it is lost for good. The trap retries it.
      echo "::error::#$number was re-triggered but its auto-merge could not be re-armed"
      failed=$((failed + 1))
      continue
    fi
    rm -rf "$state/rearm/$number"
    echo "  re-triggered #$number and re-armed auto-merge — $title"
  else
    echo "  re-triggered #$number — $title"
  fi
  done_count=$((done_count + 1))
  # `printf '%s\n'`, never `printf '%s'`: command substitution strips the trailing newline, so
  # feeding the value back without one makes `read` return false on the final line and drops the
  # last pull request from the sweep — silently, and reported as a smaller total.
done < <(printf '%s\n' "$prs")

echo "recheck-open-prs: $done_count of $count current-base refreshes completed"
if [ "$failed" -gt 0 ]; then
  echo "::error::$failed pull request(s) could not be re-triggered; their required checks are still the pre-gate result"
  exit 1
fi
exit 0
