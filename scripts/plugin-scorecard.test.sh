#!/usr/bin/env bash
# Native usage is distinct from inventory; benchmark scores retain their denominators.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [ ! -f "$root/scripts/plugin-scorecard.sh" ]; then
  printf 'FAIL native plugin scorecard is not available\n'
  exit 1
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
report() { bash "$root/scripts/plugin-scorecard.sh" "$@" > "$work/result" 2> "$work/error"; }
check() { jq -e "$1" "$work/result" >/dev/null || { printf 'FAIL %s\n' "$2"; exit 1; }; }
reject() {
  if report "$@"; then printf 'FAIL accepted invalid observation\n'; exit 1; fi
  [ ! -s "$work/result" ] || { printf 'FAIL partial success output\n'; exit 1; }
}
cat > "$work/usage.json" <<'JSON'
{"resourceLogs":[{"scopeLogs":[{"logRecords":[
{"attributes":[{"key":"event.name","value":{"stringValue":"plugin_loaded"}},{"key":"event.timestamp","value":{"stringValue":"2026-10-31T01:00:00Z"}},{"key":"event.sequence","value":{"intValue":"1"}},{"key":"session.id","value":{"stringValue":"private-session"}},{"key":"plugin.name","value":{"stringValue":"engineering-practices"}},{"key":"marketplace.name","value":{"stringValue":"devantler-plugins"}},{"key":"plugin.version","value":{"stringValue":"1.2.0"}},{"key":"safe_mode","value":{"stringValue":"false"}}]},
{"attributes":[{"key":"event.name","value":{"stringValue":"skill_activated"}},{"key":"event.timestamp","value":{"stringValue":"2026-11-01T01:00:00Z"}},{"key":"event.sequence","value":{"intValue":"2"}},{"key":"session.id","value":{"stringValue":"private-session"}},{"key":"plugin.name","value":{"stringValue":"engineering-practices"}},{"key":"skill.name","value":{"stringValue":"ways-of-working"}},{"key":"skill.source","value":{"stringValue":"plugin"}}]},
{"body":{"stringValue":"PRIVATE_PROMPT_DO_NOT_PRINT"},"attributes":[{"key":"event.name","value":{"stringValue":"user_prompt"}}]}
]}]}]}
JSON
jq -n '{metadata:{skill_name:"ways-of-working",timestamp:"2026-11-01T02:00:00Z"},runs:[
 {eval_id:1,run_number:1,configuration:"with_skill",result:{passed:2,total:2,pass_rate:1,errors:0},expectations:[{text:"correct",passed:true},{text:"usable",passed:true}]},
 {eval_id:1,run_number:1,configuration:"without_skill",result:{passed:1,total:2,pass_rate:0.5,errors:0},expectations:[{text:"correct",passed:true},{text:"usable",passed:false}]}]}' > "$work/benchmark.json"
args=(--since 2026-11-01T00:00:00Z --until 2026-11-02T00:00:00Z)

# Missing evidence is unknown; no export or runtime configuration is read implicitly.
report
check 'all(.plugins[]; .usage.activations == null and .benchmarks == [])' 'missing evidence'
report "${args[@]}" --usage "$work/usage.json" --usage "$work/usage.json" --benchmark engineering-practices 1.2.0 "$work/benchmark.json"
check '.plugins[]|select(.name=="engineering-practices")|.usage.activations==1 and .usage.versions==["1.2.0"] and .benchmarks[0].with_skill.passed==2 and .benchmarks[0].with_skill.total==2 and .benchmarks[0].with_skill.percent==100 and .benchmarks[0].baseline_delta_pp==50' 'native usage and benchmark'
if grep -Eq 'private-session|PRIVATE_PROMPT_DO_NOT_PRINT' "$work/result"; then printf 'FAIL private content emitted\n'; exit 1; fi

# A load is inventory, not an activation; a foreign marketplace cannot own our usage.
jq '(.resourceLogs[0].scopeLogs[0].logRecords) |= [.[0]]' "$work/usage.json" > "$work/load-only.json"
report "${args[@]}" --usage "$work/load-only.json"
check '.plugins[]|select(.name=="engineering-practices")|.usage.activations==0' 'load is not use'
jq '(.resourceLogs[0].scopeLogs[0].logRecords[0].attributes[]|select(.key=="marketplace.name").value.stringValue)="another-marketplace"' "$work/usage.json" > "$work/foreign.json"
report "${args[@]}" --usage "$work/foreign.json"
check '.coverage.unattributed_activations==1 and (.plugins[]|select(.name=="engineering-practices")|.usage.activations==null)' 'foreign source'
jq '(.resourceLogs[0].scopeLogs[0].logRecords[1].attributes[]|select(.key=="plugin.name").value.stringValue)="third-party"' "$work/usage.json" > "$work/redacted.json"
report "${args[@]}" --usage "$work/redacted.json"
check '.coverage.unattributed_activations==1 and (.plugins[]|select(.name=="engineering-practices")|.usage.activations==null)' 'redacted identity'
jq '(.resourceLogs[0].scopeLogs[0].logRecords[0].attributes[]|select(.key=="safe_mode").value.stringValue)="true"' "$work/usage.json" > "$work/safe-mode.json"
report "${args[@]}" --usage "$work/safe-mode.json"
check '.coverage.unattributed_activations==1 and (.plugins[]|select(.name=="engineering-practices")|.usage.activations==null)' 'safe mode is not execution'
jq '.resourceLogs[0].scopeLogs[0].logRecords += [(.resourceLogs[0].scopeLogs[0].logRecords[0] | (.attributes[]|select(.key=="plugin.version").value.stringValue)="9.9.9")]' "$work/usage.json" > "$work/conflict.json"
reject "${args[@]}" --usage "$work/conflict.json"
jq '(.resourceLogs[0].scopeLogs[0].logRecords[1].attributes[]|select(.key=="event.timestamp").value.stringValue)="2026-11-02T00:00:00Z"' "$work/usage.json" > "$work/outside.json"
report "${args[@]}" --usage "$work/outside.json"
check '.plugins[]|select(.name=="engineering-practices")|.usage.activations==0' 'exclusive end'
jq '(.resourceLogs[0].scopeLogs[0].logRecords[0].attributes[]|select(.key=="event.timestamp").value.stringValue)="2026-11-01T01:00:00Z" | (.resourceLogs[0].scopeLogs[0].logRecords[0].attributes[]|select(.key=="event.sequence").value.intValue)="3"' "$work/usage.json" > "$work/later-load.json"
report "${args[@]}" --usage "$work/later-load.json"
check '.coverage.unattributed_activations==1' 'a later load cannot own an earlier activation'
jq '(.resourceLogs[0].scopeLogs[0].logRecords[0].attributes[]|select(.key=="plugin.version").value.stringValue)="PRIVATE_VERSION_DO_NOT_PRINT"' "$work/usage.json" > "$work/invalid-version.json"
report "${args[@]}" --usage "$work/invalid-version.json"
check '.coverage.unattributed_activations==1 and (.plugins[]|select(.name=="engineering-practices")|.usage.activations==null)' 'unusable version is unknown'
if grep -q PRIVATE_VERSION_DO_NOT_PRINT "$work/result"; then printf 'FAIL private version emitted\n'; exit 1; fi
jq '(.resourceLogs[0].scopeLogs[0].logRecords[0].attributes[]|select(.key=="event.timestamp").value.stringValue)="2026-11-01T01:00:00.100Z" | (.resourceLogs[0].scopeLogs[0].logRecords[1].attributes[]|select(.key=="event.timestamp").value.stringValue)="2026-11-01T01:00:00.200Z"' "$work/usage.json" > "$work/fraction.json"
report --since 2026-11-01T01:00:00.150Z --until 2026-11-01T01:00:00.250Z --usage "$work/fraction.json"
check '.plugins[]|select(.name=="engineering-practices")|.usage.activations==1' 'fractional timestamp ordering and window'

# Empty/unsupported evidence never establishes full coverage or a retirement decision.
printf '%s\n' '{"resourceLogs":[]}' > "$work/empty.json"
report "${args[@]}" --usage "$work/empty.json"
check '.coverage.status=="UNKNOWN" and all(.plugins[];.usage.activations==null)' 'empty export'
printf '%s\n' '{"resourceLogs":[],"resourceLogs":[]}' > "$work/duplicate.json"
reject "${args[@]}" --usage "$work/duplicate.json"
printf '%s\n' '{"resourceLogs":[{}]}' > "$work/partial.json"
reject "${args[@]}" --usage "$work/partial.json"
reject --usage "$work/usage.json"
reject --since 2026-11-02T00:00:00Z --until 2026-11-01T00:00:00Z --usage "$work/usage.json"
reject --since 2026-02-30T00:00:00Z --until 2026-11-01T00:00:00Z --usage "$work/usage.json"
reject "${args[@]}" --usage "$work/missing.json"

# Poor and incomplete evidence stays visible; summaries cannot manufacture grades.
jq '.runs[0].result.total=0' "$work/benchmark.json" > "$work/bad-benchmark.json"
reject --benchmark engineering-practices 1.2.0 "$work/bad-benchmark.json"
jq '.metadata.timestamp="PRIVATE_TIMESTAMP_DO_NOT_PRINT"' "$work/benchmark.json" > "$work/bad-benchmark.json"
reject --benchmark engineering-practices 1.2.0 "$work/bad-benchmark.json"
jq '.runs[0].result.pass_rate=0.3' "$work/benchmark.json" > "$work/bad-benchmark.json"
reject --benchmark engineering-practices 1.2.0 "$work/bad-benchmark.json"
jq '.runs[1].expectations[0].text="different criterion"' "$work/benchmark.json" > "$work/unmatched.json"
report --benchmark engineering-practices 1.2.0 "$work/unmatched.json"
check '.plugins[]|select(.name=="engineering-practices")|.benchmarks[0].baseline_delta_pp==null' 'unmatched baseline'
jq '.runs |= [.[0]]' "$work/benchmark.json" > "$work/no-baseline.json"
report --benchmark engineering-practices 1.2.0 "$work/no-baseline.json"
check '.plugins[]|select(.name=="engineering-practices")|.benchmarks[0].with_skill.percent==100 and .benchmarks[0].baseline_delta_pp==null' 'no baseline'
jq 'del(.runs[].expectations)' "$work/benchmark.json" > "$work/no-assertions.json"
report --benchmark engineering-practices 1.2.0 "$work/no-assertions.json"
check '.plugins[]|select(.name=="engineering-practices")|.benchmarks[0].with_skill.percent==100 and .benchmarks[0].baseline_delta_pp==null' 'unproven assertion match'
reject --benchmark engineering-practices 1.2.0 "$work/benchmark.json" --benchmark engineering-practices 1.2.0 "$work/benchmark.json"
reject --benchmark github 1.0.8 "$work/benchmark.json"
printf 'plugin scorecard: native usage, provenance, privacy, window and benchmark cases passed\n'
