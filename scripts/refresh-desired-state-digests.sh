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
# shellcheck source=scripts/atomic-write.lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/atomic-write.lib.sh"

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

for tool in jq perl awk sort cmp; do
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
if ! find plugins \( -type f -o -type l \) -path '*/resources/*.desired-state.json' -print0 > "$work/resources"; then
  echo '::error::desired-state resource inventory failed; refusing all writes.' >&2
  exit 2
fi
# Shell expansion supplies an independent, direct-layout inventory. A successful
# prefix from find is not proof that every desired-state resource was observed.
: > "$work/expected"
shopt -s nullglob
if [ ! -d plugins ] || [ -L plugins ]; then
  echo '::error::linked or missing plugin root.' >&2
  exit 2
fi
for plugin_root in plugins/*; do
  [ -d "$plugin_root" ] || [ -L "$plugin_root" ] || continue
  if [ -L "$plugin_root" ] || [[ ! ${plugin_root#plugins/} =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo '::error::linked or invalid plugin root; refusing all writes.' >&2
    exit 2
  fi
  [ ! -L "$plugin_root/resources" ] || { echo '::error::linked resource directory; refusing all writes.' >&2; exit 2; }
  for expected_resource in "$plugin_root"/resources/*.desired-state.json; do
    [[ $expected_resource != *[[:cntrl:]]* ]] || { echo '::error::invalid resource inventory path.' >&2; exit 2; }
    printf '%s\n' "$expected_resource" >> "$work/expected"
  done
done
shopt -u nullglob
: > "$work/observed"
resource=''
while IFS= read -r -d '' resource; do
  [[ $resource != *[[:cntrl:]]* ]] || { echo '::error::invalid resource inventory path.' >&2; exit 2; }
  printf '%s\n' "$resource" >> "$work/observed"
done < "$work/resources"
[ -z "$resource" ] || { echo '::error::unterminated desired-state resource inventory.' >&2; exit 2; }
LC_ALL=C sort "$work/expected" > "$work/expected-sorted" || exit 2
LC_ALL=C sort "$work/observed" > "$work/observed-sorted" || exit 2
cmp -s "$work/expected-sorted" "$work/observed-sorted" || {
  echo '::error::desired-state resource inventory is incomplete or inconsistent; refusing all writes.' >&2; exit 2;
}
: > "$work/changes"
drift=0
missing=0
seen=0

# Resolve only regular files under this plugin, without following any linked
# component. Identity and relative-path checks precede every digest read.
contained_file() {
  local relative=$2 component current=$1
  [[ "$relative" != /* && "$relative" != */ && "$relative" != *//* && "$relative" != *[[:cntrl:]]* ]] || return 1
  local parts=()
  IFS=/ read -r -a parts <<<"$relative"
  for component in "${parts[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. && "$component" != *[[:cntrl:]]* ]] || return 1
    current="$current/$component"
    [ ! -L "$current" ] || return 1
  done
  [ -f "$current" ]
}

# Resolve one declared digest against the file it pins. Emits nothing and returns 1
# when the target is absent, so a missing file fails closed here instead of being
# papered over with a digest of nothing.
digest_for() {
  local target="$1" resource="$2" field="$3"
  if ! contained_file "$plugin_dir" "${target#"$plugin_dir"/}"; then
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
  [ ! -L "$resource" ] || { echo '::error::Linked resource refused.' >&2; exit 1; }
  observed_resource="$work/original-$seen"
  cat "$resource" > "$observed_resource" || { echo '::error::Original resource could not be read.' >&2; exit 1; }
  if ! jq -es 'length==1 and (.[0]|type=="object")' "$observed_resource" > /dev/null 2>&1; then
    echo "::error::$resource: not valid JSON — refusing to rewrite" >&2
    missing=1
    continue
  fi
  # Completed streaming paths catch repeated values and containers before
  # normal object decoding can collapse their declarations.
  if ! jq --stream -es '
      reduce .[] as $event ({complete:{}, valid:true};
        if ($event|length)==2 then
          .complete as $complete | $event[0] as $path |
          .valid = (.valid and (any(range(0;($path|length)+1);
            $complete[($path[0:.]|tojson)]==true)|not)) |
          .complete[($path|tojson)] = true
        else .complete[($event[0][0:-1]|tojson)] = true end) | .valid
    ' "$observed_resource" >/dev/null ||
     ! jq -e '
       def digest_fields: all(to_entries[]; if (.key|endswith("Sha256")) then (.value|type)=="string" else true end);
       (.spec|type)=="object" and
       (if .spec|has("source") then
          (.spec.source|type)=="object" and (.spec.source|digest_fields) and
          (if .spec.source|has("entrypoint") then (.spec.source.entrypoint|type)=="string" else true end) and
          (if .spec.source|has("requiredRuntimeAssets") then
             (.spec.source.requiredRuntimeAssets|type)=="array" and
             all(.spec.source.requiredRuntimeAssets[]; type=="object" and
               ((.path // "")|type)=="string" and (.sha256|type)=="string" and (.executable|type)=="boolean")
           else true end)
        else true end) and
       (if .spec|has("roles") then (.spec.roles|type)=="object" and
          all(.spec.roles[]; type=="object" and digest_fields) else true end)
     ' "$observed_resource" >/dev/null; then
    echo "::error::$resource: invalid or duplicate digest declaration; refusing all writes." >&2
    exit 1
  fi
  if ! jq -e '(.spec.source.requiredRuntimeAssets // []) | map(.path) | length == (unique|length)' "$observed_resource" >/dev/null; then
    echo "::error::$resource: duplicate runtime asset declaration; refusing all writes." >&2
    exit 1
  fi

  # plugins/<name>/resources/<file>.desired-state.json -> plugins/<name>
  resource_dir=${resource%/*}
  plugin_dir=${resource_dir%/*}

  args=()
  program='.'

  entrypoint=$(jq -r '.spec.source.entrypoint // ""' "$observed_resource")
  if ! has_entrypoint_digest=$(jq -r 'has("spec") and (.spec | has("source")) and (.spec.source | has("entrypointSha256"))' "$observed_resource"); then
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
    ' "$observed_resource" > "$work/roles"; then
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
  if ! jq -j '.spec.source.requiredRuntimeAssets[]? | (.path // "") + "\u0000"' "$observed_resource" > "$work/assets"; then
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
    if ! contained_file "$plugin_dir" "$asset_path"; then
      echo "::error::$resource: requiredRuntimeAssets pins a file that does not exist: $asset_path" >&2
      missing=1
      continue
    fi
    executable=$(jq -r --arg path "$asset_path" '.spec.source.requiredRuntimeAssets[] | select(.path==$path) | .executable' "$observed_resource") || exit 1
    if { [ "$executable" = true ] && [ ! -x "$plugin_dir/$asset_path" ]; } ||
       { [ "$executable" = false ] && [ -x "$plugin_dir/$asset_path" ]; }; then
      echo "::error::$resource: runtime asset executable permissions differ from its declaration; refusing all writes." >&2
      exit 1
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

  updated=$(jq "${args[@]}" "$program" "$observed_resource")

  if ! original=$(cat "$observed_resource"); then
    echo "::error::$resource: original bytes could not be read; refusing all writes." >&2
    exit 1
  fi
  if [ "$updated" = "$original" ]; then
    continue
  fi

  drift=1
  if [ "$mode" = "check" ]; then
    echo "::error::$resource: declared digests are stale — run ./scripts/refresh-desired-state-digests.sh" >&2
    continue
  fi

  printf '%s\n' "$updated" > "$work/update-$seen"
  printf '%s\0%s\0%s\0' "$resource" "$work/update-$seen" "$observed_resource" >> "$work/changes"
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
  atomic_write_batch "$work/changes" || exit 1
  while IFS= read -r -d '' resource; do
    IFS= read -r -d '' _staged <&0 || exit 1
    IFS= read -r -d '' _original <&0 || exit 1
    echo "✓ refreshed $resource"
  done < "$work/changes"
fi

if [ "$mode" = "write" ] && [ "$drift" -eq 0 ]; then
  echo "✓ every declared desired-state digest is already current"
fi
