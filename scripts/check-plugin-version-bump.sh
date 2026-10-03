#!/usr/bin/env bash
# Fail when a plugin's shipped content changes without moving that plugin's version.
#
# Runtimes cache marketplace plugins keyed by <marketplace>/<plugin>/<version>. A content
# change that leaves the version untouched is therefore unreachable for every consumer that
# already installed that version: the runtime's update command reports "already at the
# latest version" and keeps serving the stale copy — no error, no drift signal. That
# silently defeats the `updatePolicy: latest-reviewed-default-branch` and
# `refreshTiming: before-starting-each-run` properties the shipped desired state declares.
#
# Compares the merge base of <base-ref> and <head-ref> against <head-ref>, exactly as a
# pull request is reviewed, and reports every offending plugin in one pass so a fix needs
# one round rather than one per plugin.
#
# Usage:  ./scripts/check-plugin-version-bump.sh [base-ref] [head-ref]
#         BASE_REF=origin/main HEAD_REF=HEAD ./scripts/check-plugin-version-bump.sh
#
# Fail-closed: an unresolvable ref is an error, never a pass — a shallow checkout must not
# silently downgrade this gate to a no-op.
set -euo pipefail
# shellcheck source=scripts/plugin-version.lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugin-version.lib.sh"
plugin_version_git_context
plugin_version_history || exit 1

BASE_REF="${1:-${BASE_REF:-origin/main}}"
HEAD_REF="${2:-${HEAD_REF:-HEAD}}"

# The strict Claude manifest is the version source of truth. validate-manifests.sh already
# enforces that the portable plugin.json and both marketplace manifests carry the same
# version, so checking one here cannot disagree with the others.
MANIFEST_REL=".claude-plugin/plugin.json"

head_sha=$(git rev-parse --verify "$HEAD_REF^{commit}") || exit 1
if ! base_sha=$(git merge-base --all "$BASE_REF" "$head_sha" 2>/dev/null) ||
   ! [[ "$base_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::Cannot resolve a merge base for '$BASE_REF'...'$HEAD_REF'."
  echo "::error::Fetch the base branch with full history (actions/checkout with fetch-depth: 0) before running this guard."
  exit 1
fi

violations=0
checked=0

# Retain the producer status before consuming any paths. A process substitution
# hides a failed ls-tree, including one that has already emitted a valid prefix.
inventory=$(mktemp) || exit 1
trap 'rm -f "$inventory"' EXIT
if ! git ls-tree -d --name-only -z "$head_sha" plugins/ > "$inventory"; then
  echo "::error::Cannot enumerate plugins at '$HEAD_REF'; refusing an incomplete version check."
  exit 1
fi

# Plugin directories as they exist at HEAD. A plugin deleted in this change has no version
# to bump, so iterating HEAD (not the base) is what keeps a removal from failing the gate.
plugin_dir=''
while IFS= read -r -d '' plugin_dir; do
  name="${plugin_dir#plugins/}"
  [[ "$plugin_dir" == "plugins/$name" && "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || {
    echo '::error::Unsupported plugin directory identity.' >&2; exit 1;
  }

  changed=$(git diff --no-ext-diff --no-textconv --no-relative --name-only "$base_sha" "$head_sha" -- "$plugin_dir/") || exit 1
  [ -n "$changed" ] || continue
  checked=$((checked + 1))

  head_version=$(plugin_version_at "$head_sha" "$name") || exit 1

  # Absent at the base means this change introduces the plugin — nothing to bump from. But
  # ABSENT and UNREADABLE are different answers, and `git show` fails the same way for both:
  # in a partial clone a promisor-object fetch failure looks exactly like a missing path, and
  # reading that as "new plugin" lets the gate pass on a plugin that already ships. So ask the
  # base TREE whether the manifest exists (trees are present even when blobs are not), and only
  # then read it — a read that fails on a listed manifest is an error, never a pass.
  if ! base_entry=$(git ls-tree "$base_sha" -- "$plugin_dir/$MANIFEST_REL" 2>&1); then
    echo "::error::$plugin_dir/$MANIFEST_REL: could not list the base tree at ${base_sha:0:12}: $base_entry"
    echo "::error::The base revision must be readable for this gate to decide anything; fetch it fully and re-run."
    exit 1
  fi
  if [ -z "$base_entry" ]; then
    echo "✓ $name is new in this change (version $head_version)"
    continue
  fi
  if ! base_version=$(plugin_version_at "$base_sha" "$name" 2>&1); then
    echo "::error::$plugin_dir/$MANIFEST_REL: exists at ${base_sha:0:12} but could not be read: $base_version"
    echo "::error::Refusing to treat an unreadable base manifest as a new plugin — the version gate would pass on a plugin that already ships."
    echo "::error::Make the base revision's objects available (a full or --refetch'd clone, not a partial one) and re-run."
    exit 1
  fi

  if [ "$base_version" = "$head_version" ]; then
    echo "::error::$name: shipped content changed but the version is still $head_version."
    echo "::error::Consumers cache by version, so this change would never reach them."
    echo "::error::Bump the version in all four manifests, then re-run ./scripts/validate-manifests.sh:"
    echo "::error::  $plugin_dir/plugin.json"
    echo "::error::  $plugin_dir/$MANIFEST_REL"
    echo "::error::  .claude-plugin/marketplace.json      (the '$name' entry)"
    echo "::error::  .github/plugin/marketplace.json      (the '$name' entry)"
    echo "::error::Changed files in $name:"
    printf '%s\n' "$changed" | sed 's/^/::error::  /'
    violations=$((violations + 1))
    continue
  fi

  if ! plugin_version_increases "$base_version" "$head_version"; then
    echo "::error::$name: cache version must increase from a canonical stable version ($base_version → $head_version)."
    violations=$((violations + 1))
    continue
  fi
  echo "✓ $name content changed and version moved $base_version → $head_version"
done < "$inventory"
[ -z "$plugin_dir" ] || { echo '::error::Unterminated plugin inventory.' >&2; exit 1; }

if [ "$violations" -gt 0 ]; then
  echo "::error::$violations plugin(s) changed content without a version bump."
  exit 1
fi

if [ "$checked" -eq 0 ]; then
  echo "✓ No plugin content changed in $BASE_REF...$HEAD_REF"
else
  echo "✓ All $checked changed plugin(s) moved their version"
fi
