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

state=$(mktemp -d) || exit 2
mkdir -p "$state/closed" "$state/rearm" || exit 2

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
  local f n st method headline body sha baseline
  for f in "$state/closed"/*; do
    [ -e "$f" ] || continue
    n=${f##*/}
    st=$(gh pr view "$n" --repo "$repo" --json state --jq '.state' 2> /dev/null) || st=UNKNOWN
    # UNKNOWN reopens too: an unreadable state is not evidence the PR is open, and reopening an
    # already-open pull request costs nothing.
    if [ "$st" = "OPEN" ] || [ "$st" = "MERGED" ]; then
      continue
    fi
    echo "recheck-open-prs: reopening #$n, left closed (state=$st)" >&2
    gh pr reopen "$n" --repo "$repo" > /dev/null 2>&1 \
      || echo "::error::#$n could not be reopened; reopen it by hand" >&2
  done
  for f in "$state/rearm"/*; do
    [ -e "$f" ] || continue
    n=${f##*/}
    st=$(gh pr view "$n" --repo "$repo" --json autoMergeRequest \
      --jq 'if .autoMergeRequest == null then "none" else "armed" end' 2> /dev/null) || st=none
    [ "$st" = "armed" ] && continue
    method=$(cat "$state/rearm/$n/method" 2> /dev/null) || method=""
    headline=$(cat "$state/rearm/$n/headline" 2> /dev/null) || headline=""
    body=$(cat "$state/rearm/$n/body" 2> /dev/null) || body=""
    sha=$(cat "$state/rearm/$n/sha" 2> /dev/null) || sha=""
    baseline=$(cat "$state/rearm/$n/baseline" 2> /dev/null) || baseline=0
    # The same wait the main path performs, and for the same reason: arming auto-merge while the
    # pre-gate green is still the newest result can merge the PR before the new run exists.
    if ! await_fresh_check "$sha" "$baseline"; then
      echo "::error::#$n auto-merge was NOT restored: no pull_request run from the reopen appeared, and arming it now could merge the PR on the pre-gate result. Re-arm it by hand once its checks are running." >&2
      continue
    fi
    echo "recheck-open-prs: restoring auto-merge on #$n" >&2
    if ! verify_reopened "$n" "$(cat "$state/rearm/$n/before")"; then
      echo "::error::#$n auto-merge was NOT restored: reopened state moved or is unreadable." >&2
      continue
    fi
    rearm "$n" "$method" "$headline" "$body" "$sha" > /dev/null 2>&1 \
      || echo "::error::#$n auto-merge could not be restored; re-arm it by hand" >&2
  done
  rm -rf "$state"
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
  gh api --method GET "repos/${repo}/actions/runs" \
    -f event=pull_request -f head_sha="$1" -F per_page=100 \
    --jq '[.workflow_runs[].id] | max // 0' 2> /dev/null
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
    [ -z "$headline" ] || set -- "$@" --subject "$headline"
    [ -z "$body" ] || set -- "$@" --body "$body"
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
if ! prs=$(gh api --paginate --method GET "repos/${repo}/pulls" \
  -f state=open -f base="$base" -F per_page=100 \
  --jq '.[]|[(.number|tostring), (.title // "")]|@tsv'); then
  echo "recheck-open-prs: could not list open pull requests" >&2
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
      (.commitHeadline | .==null or type=="string") and (.commitBody | .==null or type=="string")))' >/dev/null; then
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
    mkdir -p "$state/rearm/$number"
    printf '%s' "$snapshot" > "$state/rearm/$number/before"
    printf '%s' "$snapshot" | jq -r '.autoMergeRequest.mergeMethod // ""' > "$state/rearm/$number/method"
    printf '%s' "$snapshot" | jq -r '.autoMergeRequest.commitHeadline // ""' > "$state/rearm/$number/headline"
    printf '%s' "$snapshot" | jq -r '.autoMergeRequest.commitBody // ""' > "$state/rearm/$number/body"
    head_sha=$(printf '%s' "$snapshot" | jq -r '.headRefOid // ""')
    printf '%s' "$head_sha" > "$state/rearm/$number/sha"
    printf '%s' "$check_baseline" > "$state/rearm/$number/baseline"
  fi

  # Close and reopen produce the `reopened` event that resolves a fresh merge ref. The head is
  # untouched, so a green review at the current head stays current. The record is written first
  # and is NOT removed when the close reports failure: a close can be applied and still report
  # one, and only the trap's read of the real state can tell those apart.
  : > "$state/closed/$number"
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
    rm -rf "$state/rearm/$number"
    failed=$((failed + 1))
    continue
  fi
  rm -f "$state/closed/$number"

  if [ "$automerge" = "armed" ]; then
    method=$(cat "$state/rearm/$number/method" 2> /dev/null) || method=""
    headline=$(cat "$state/rearm/$number/headline" 2> /dev/null) || headline=""
    body=$(cat "$state/rearm/$number/body" 2> /dev/null) || body=""
    if ! rearm "$number" "$method" "$headline" "$body" "$head_sha" > /dev/null; then
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
