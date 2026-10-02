#!/usr/bin/env bash
# Recompute every content digest a *.desired-state.json resource declares, from the
# bundled files those digests pin.
#
# Why this exists: validate-manifests.sh treats those digests as a required content
# gate, but nothing ever wrote them. A branch that legitimately changes a bundled
# agent, skill, or runtime asset — the daily agent-skills sync being the standing
# case — therefore produces a manifest its own repository rejects, and no amount of
# re-running the sync fixes it. Only a hand edit did, and a hand edit on a generated
# branch is force-pushed away on the next sync with no signal that it happened.
#
# The digest helpers are sourced from scripts/sha256.lib.sh, the same file
# validate-manifests.sh sources, so the value written here and the value demanded
# there cannot drift apart.
#
# Operates on the current working directory (run from the repo root, exactly as CI
# does). Idempotent: a second run over an already-current tree writes nothing.
#
# Usage:
#   ./scripts/refresh-desired-state-digests.sh            # rewrite stale digests in place
#   ./scripts/refresh-desired-state-digests.sh --check    # report drift, write nothing
#
# Exit codes:
#   0  every digest is current (--check), or every stale digest was rewritten
#   1  --check found drift, or a declared digest's target file is missing
#   2  usage error, or a required tool is unavailable
set -euo pipefail

# shellcheck source=scripts/sha256.lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sha256.lib.sh"

mode="write"
case "${1-}" in
  "") ;;
  --check) mode="check" ;;
  *)
    echo "usage: refresh-desired-state-digests.sh [--check]" >&2
    exit 2
    ;;
esac
if [ "$#" -gt 1 ]; then
  echo "usage: refresh-desired-state-digests.sh [--check]" >&2
  exit 2
fi

for tool in jq perl awk; do
  command -v "$tool" > /dev/null 2>&1 || {
    echo "::error::refresh-desired-state-digests: required tool not found: $tool" >&2
    exit 2
  }
done

# A missing hasher is an environment failure, not a finding about the tree. Without this check
# sha256_file simply fails, digest_for reports it as an absent target, and the run exits 1 blaming
# a file that is present — the misdiagnosis costing more than the failure.
if ! command -v sha256sum > /dev/null 2>&1 && ! command -v shasum > /dev/null 2>&1; then
  echo "::error::refresh-desired-state-digests: no SHA-256 program found (need sha256sum or shasum)" >&2
  exit 2
fi

umask 077
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
if ! find plugins -type f -path '*/resources/*.desired-state.json' -print0 > "$work/resources"; then
  echo '::error::desired-state resource inventory failed; refusing all writes.' >&2
  exit 2
fi
: > "$work/changes"
drift=0
missing=0
seen=0

# Resolve one declared digest against the file it pins. Emits nothing and returns 1
# when the target is absent, so a missing file fails closed here instead of being
# papered over with a digest of nothing.
digest_for() {
  local target="$1" resource="$2" field="$3"
  if [ ! -f "$target" ]; then
    echo "::error::$resource: $field pins a file that does not exist: $target" >&2
    return 1
  fi
  local digest
  digest=$(sha256_file "$target") || return 1
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { echo "::error::$resource: invalid $field digest" >&2; return 1; }
  printf '%s\n' "$digest"
}

resource=''
while IFS= read -r -d '' resource; do
  seen=$((seen + 1))
  [ -n "$resource" ] || continue
  if ! jq -e . "$resource" > /dev/null 2>&1; then
    echo "::error::$resource: not valid JSON — refusing to rewrite" >&2
    missing=1
    continue
  fi

  # plugins/<name>/resources/<file>.desired-state.json -> plugins/<name>
  resource_dir=${resource%/*}
  plugin_dir=${resource_dir%/*}

  args=()
  program='.'

  entrypoint=$(jq -r '.spec.source.entrypoint // ""' "$resource")
  if ! has_entrypoint_digest=$(jq -r 'has("spec") and (.spec | has("source")) and (.spec.source | has("entrypointSha256"))' "$resource"); then
    echo "::error::$resource: entrypoint declaration could not be observed; refusing all writes." >&2
    exit 1
  fi
  if [ "$has_entrypoint_digest" = true ]; then
    if [ -z "$entrypoint" ]; then
      # Declared but unresolvable. Skipping it would exit 0 over a digest nothing examined — the
      # exact shape of failure this generator exists to remove, one level up.
      echo "::error::$resource: entrypointSha256 is declared but entrypoint is empty, so nothing resolves it" >&2
      missing=1
    elif value=$(digest_for "$plugin_dir/agents/$entrypoint.agent.md" "$resource" entrypointSha256); then
      args+=(--arg entrypointSha256 "$value")
      program="$program | .spec.source.entrypointSha256 = \$entrypointSha256"
    else
      missing=1
    fi
  fi

  # Every role that pins its own definition or skill file. Driven off the keys the
  # resource actually declares, so a new role's definitionSha256 inherits the generator
  # without an edit. skillSha256 is deliberately not generalized: validate-manifests.sh
  # resolves it to one hard-coded bundled skill, and a generator that guessed a
  # different path would write a digest that gate never reads.
  if ! jq -r '
      (.spec.roles // {})
      | to_entries[]
      | . as $entry
      | (
          (if ($entry.value | has("definitionSha256"))
             then [$entry.key, "definitionSha256", "agents/\($entry.key).agent.md"]
             else empty end),
          (if ($entry.value | has("skillSha256"))
             then (if $entry.key == "agent-improver"
                     then [$entry.key, "skillSha256", "skills/agent-improvement/SKILL.md"]
                     else [$entry.key, "skillSha256", "!UNMAPPED"] end)
             else empty end)
        )
      | @tsv
    ' "$resource" > "$work/roles"; then
    echo "::error::$resource: role inventory failed; refusing all writes." >&2
    exit 1
  fi
  role_number=0
  while IFS=$'\t' read -r role field relative; do
    [ -n "$role" ] || continue
    if [ "$relative" = "!UNMAPPED" ]; then
      # The validator resolves each digest field to one specific bundled path. A field
      # this generator cannot map to that same path would be written with a value the
      # gate never checks, so refuse rather than write a plausible wrong digest.
      echo "::error::$resource: $role.$field has no known source path in this generator — teach it the mapping validate-manifests.sh uses" >&2
      missing=1
      continue
    fi
    if value=$(digest_for "$plugin_dir/$relative" "$resource" "$role.$field"); then
      role_number=$((role_number + 1))
      key="digest_$role_number"
      role_key="role_$role_number"
      args+=(--arg "$key" "$value" --arg "$role_key" "$role")
      program="$program | .spec.roles[\$$role_key].$field = \$$key"
    else
      missing=1
    fi
  done < "$work/roles"

  # Runtime assets are hashed as exact bytes: they are executed from the checkout, so a
  # checkout-only CRLF change must invalidate the digest rather than be normalized away.
  if ! jq -j '.spec.source.requiredRuntimeAssets[]? | (.path // "") + "\u0000"' "$resource" > "$work/assets"; then
    echo "::error::$resource: runtime asset inventory failed; refusing all writes." >&2
    exit 1
  fi
  asset_map='{}'
  asset_path=''
  while IFS= read -r -d '' asset_path; do
    if [ -z "$asset_path" ]; then
      # An entry with a declared digest and no path is unverifiable, so filtering it out would
      # again exit 0 over something never examined.
      echo "::error::$resource: a requiredRuntimeAssets entry declares no path, so nothing resolves its digest" >&2
      missing=1
      continue
    fi
    if [ ! -f "$plugin_dir/$asset_path" ]; then
      echo "::error::$resource: requiredRuntimeAssets pins a file that does not exist: $asset_path" >&2
      missing=1
      continue
    fi
    if ! value=$(sha256_bytes "$plugin_dir/$asset_path") || [[ ! "$value" =~ ^[0-9a-f]{64}$ ]]; then
      echo "::error::$resource: runtime asset digest could not be observed; refusing all writes." >&2
      exit 1
    fi
    asset_map=$(
      jq -c --arg p "$asset_path" --arg s "$value" \
        '.[$p] = $s' <<< "$asset_map"
    )
  done < "$work/assets"
  if [ -n "$asset_path" ]; then
    echo '::error::unterminated runtime-asset inventory; refusing all writes.' >&2
    exit 2
  fi

  if [ "$asset_map" != '{}' ]; then
    args+=(--argjson assetDigests "$asset_map")
    program="$program | .spec.source.requiredRuntimeAssets |= map(.sha256 = (\$assetDigests[.path] // .sha256))"
  fi

  if [ "${#args[@]}" -eq 0 ]; then
    continue
  fi

  updated=$(jq "${args[@]}" "$program" "$resource")

  if [ "$updated" = "$(cat "$resource")" ]; then
    continue
  fi

  drift=1
  if [ "$mode" = "check" ]; then
    echo "::error::$resource: declared digests are stale — run ./scripts/refresh-desired-state-digests.sh" >&2
    continue
  fi

  printf '%s\n' "$updated" > "$work/update-$seen"
  printf '%s\0%s\0' "$resource" "$work/update-$seen" >> "$work/changes"
done < "$work/resources"
if [ -n "$resource" ]; then
  echo '::error::unterminated desired-state resource inventory; refusing all writes.' >&2
  exit 2
fi

# Zero resources is never a legitimate clean run: this repository always declares at least one.
# Without this, an enumeration that matched nothing is indistinguishable from one that matched
# everything and found it current — the same success-over-nothing shape guarded against above.
if [ "$seen" -eq 0 ]; then
  echo "::error::refresh-desired-state-digests: no *.desired-state.json resource found under plugins/" >&2
  exit 2
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

if [ "$mode" = "check" ] && [ "$drift" -ne 0 ]; then
  exit 1
fi

# All producers and targets are proven before the first generated resource changes.
if [ "$mode" = "write" ]; then
  while IFS= read -r -d '' resource; do
    IFS= read -r -d '' staged <&0 || exit 1
    cat "$staged" > "$resource"
    echo "✓ refreshed $resource"
  done < "$work/changes"
fi

if [ "$mode" = "write" ] && [ "$drift" -eq 0 ]; then
  echo "✓ every declared desired-state digest is already current"
fi
