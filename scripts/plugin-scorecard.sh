#!/usr/bin/env bash
# Read native OTLP/HTTP JSON exports and skill-creator benchmark.json artifacts.
# Explicit input only; no discovery, inference, network, configuration or retirement writes.
# Usage: plugin-scorecard.sh [--since UTC --until UTC --usage export.json]...
#        [--benchmark plugin version benchmark.json]...
# Output: one aggregate JSON scorecard. Missing evidence is null, not zero.
set -euo pipefail
umask 077
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname "$here")
# shellcheck source=scripts/json-object.lib.sh
. "$here/json-object.lib.sh"
fail() { printf 'plugin scorecard: UNKNOWN - %s\n' "$1" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
touch "$work/usage" "$work/benchmarks"
since='' until='' count=0 bytes=0
# Snapshot before validating, so a later source edit cannot replace the judged bytes.
snapshot() {
  local size
  [ -f "$1" ] || fail 'an input file is unavailable'
  count=$((count+1))
  [ "$count" -le 100 ] || fail 'input count exceeds 100'
  head -c "$((33554433-bytes))" -- "$1" > "$work/input" 2> "$work/error" || fail 'an input read failed'
  size=$(wc -c < "$work/input")
  bytes=$((bytes+size))
  [ "$bytes" -le 33554432 ] || fail 'input budget exceeds 32 MiB'
  json_object_unique "$work/input" || fail 'input is not one unambiguous JSON object'
}
snapshot "$root/.github/plugin/marketplace.json"
cp "$work/input" "$work/catalogue"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since|--until)
      [ "$#" -ge 2 ] || fail 'a window argument is missing'
      if [ "$1" = --since ]; then
        [ -z "$since" ] || fail 'window start was repeated'; since=$2
      else
        [ -z "$until" ] || fail 'window end was repeated'; until=$2
      fi
      shift 2 ;;
    --usage)
      [ "$#" -ge 2 ] || fail 'usage input is missing'
      snapshot "$2"
      jq -c . "$work/input" >> "$work/usage"
      shift 2 ;;
    --benchmark)
      [ "$#" -ge 4 ] || fail 'benchmark needs plugin, version and file'
      [[ $2 =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && $3 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'invalid benchmark identity'
      plugin=$2 version=$3
      snapshot "$4"
      skill=$(jq -er '.metadata.skill_name|select(type=="string" and test("^[a-z0-9]+(-[a-z0-9]+)*$"))' "$work/input") || fail 'benchmark skill is missing'
      [ -f "$root/plugins/$plugin/skills/$skill/SKILL.md" ] || fail 'benchmark skill is outside the selected plugin'
      jq -c --arg plugin "$plugin" --arg version "$version" '{plugin:$plugin,version:$version,data:.}' "$work/input" >> "$work/benchmarks"
      shift 4 ;;
    --help)
      sed -n '2,6p' "$0"; exit 0 ;;
    *) fail 'unsupported argument' ;;
  esac
done
if ! jq -n --arg since "$since" --arg until "$until" \
  --slurpfile catalogue "$work/catalogue" --slurpfile usage "$work/usage" \
  --slurpfile benchmarks "$work/benchmarks" -f "$here/plugin-scorecard.jq" > "$work/report" 2> "$work/error"; then
  fail 'invalid export, window, attribution or benchmark; no scorecard produced'
fi
cat "$work/report"
