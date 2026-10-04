#!/usr/bin/env bash
# Exercise the user command from a copied installation, including default-off behavior.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/installed/scripts/autonomy-contract-go" "$work/bin"
cp "$root/plugins/agentic-engineering/scripts/assess-autonomy.sh" "$work/installed/scripts/"
cp "$root/plugins/agentic-engineering/scripts/autonomy-contract-go/main.go" "$work/installed/scripts/autonomy-contract-go/"
helper="$work/installed/scripts/assess-autonomy.sh"
printf '#!/usr/bin/env bash\nprintf touched > "%s"\nexit 99\n' "$work/compiler-called" > "$work/bin/go"
chmod +x "$work/bin/go"
PATH="$work/bin:$PATH" bash "$helper" > "$work/disabled"
jq -e '.status=="DISABLED" and .executionAdmitted==false and .authority=="assessment-only"' "$work/disabled" >/dev/null
PATH="$work/bin:$PATH" bash "$helper" --help > "$work/help"
if PATH="$work/bin:$PATH" bash "$helper" --contract "$work/missing" --now 2026-10-04T00:00:00Z > "$work/result" 2> "$work/error"; then exit 1; fi
[ ! -e "$work/compiler-called" ] && [ ! -s "$work/result" ]
example="$root/plugins/agentic-engineering/resources/autonomy-contract.example.json"
bash "$helper" --assess --contract "$example" --now 2026-10-04T00:00:00Z > "$work/result"
jq -e '.status=="RECOMMEND_CANDIDATE" and .synthetic==true and .executionAdmitted==false and .mutationPerformed==false and .reportedEvidenceAuthenticated==false' "$work/result" >/dev/null
jq '.contract.enabled=false' "$example" > "$work/off.json"
bash "$helper" --assess --contract "$work/off.json" --now 2026-10-04T00:00:00Z > "$work/result"
jq -e '.status=="RETAIN_DEFAULT"' "$work/result" >/dev/null
jq '.request.currentRevision=.contract.bindings.candidateRevision | .observation.proof.outcomes[1].result="fail"' "$example" > "$work/failure.json"
bash "$helper" --assess --contract "$work/failure.json" --now 2026-10-04T00:00:00Z > "$work/result"
jq -e '.status=="RECOMMEND_CONTRACTION" and .recommendedRevision=="4444444444444444444444444444444444444444444444444444444444444444" and .executionAdmitted==false' "$work/result" >/dev/null
for args in duplicate single-dash extra; do
  options=(--contract "$example" --now 2026-10-04T00:00:00Z)
  if [ "$args" = duplicate ]; then options+=(--contract "$example"); elif [ "$args" = single-dash ]; then options+=(-contract "$example" -now 2026-10-05T00:00:00Z); else options+=(unexpected); fi
  if bash "$helper" --assess "${options[@]}" > "$work/result" 2> "$work/error"; then exit 1; fi
  [ ! -s "$work/result" ]
done
printf 'installed autonomy consumer: PASS\n'
