#!/usr/bin/env bash
# Exercise the actual bundled commands from a copied plugin, without external services.
set -euo pipefail
plugin=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$plugin/skills" "$work/installed"
proof="$work/installed/product-engineering"
flow="$work/installed/agent-improvement"
bash "$proof/scripts/check-evidence.sh" --now 2026-09-24T00:00:00Z "$proof/references/evidence-example.json" > "$work/result"
jq -e '.decision=="ADOPT"' "$work/result" >/dev/null
bash "$proof/scripts/accountability-brief.sh" --mode check "$proof/references/accountability-product.json" > "$work/result"
jq -e '.status=="STRUCTURALLY_VALID" and .authority=="none" and .semanticReview=="REQUIRED"' "$work/result" >/dev/null
bash "$proof/scripts/accountability-brief.sh" --mode render "$proof/references/accountability-product.json" > "$work/render"
grep -Fq 'Try faster search suggestions' "$work/render"
bash "$flow/scripts/measure-flow.sh" "$flow/references/flow-example.json" > "$work/result"
jq -e '.version==1 and (.selections|type)=="array"' "$work/result" >/dev/null
printf '{"ignored":"\377"}\n' > "$work/invalid.json"
for mode in proof brief-check brief-render flow; do
  case $mode in
    proof) command=(bash "$proof/scripts/check-evidence.sh" --now 2026-09-24T00:00:00Z) ;;
    brief-check|brief-render) command=(bash "$proof/scripts/accountability-brief.sh" --mode "${mode#brief-}") ;;
    flow) command=(bash "$flow/scripts/measure-flow.sh") ;;
  esac
  status=0
  "${command[@]}" "$work/invalid.json" > "$work/result" 2> "$work/error" || status=$?
  [[ $status == 2 && ! -s $work/result && -s $work/error ]]
done
# A successful snapshot cannot compensate for a failed retained Unicode scan.
mkdir "$work/bin"
REAL_CAT=$(command -v cat)
export REAL_CAT
cat > "$work/bin/cat" <<'STUB'
#!/usr/bin/env bash
if [[ ${!#} == */input ]]; then
  [[ $READ_FAILURE_KIND != partial ]] || printf '%s' '{"prefix":"ordinary"}'
  exit 1
fi
exec "$REAL_CAT" "$@"
STUB
chmod +x "$work/bin/cat"
for mode in proof brief-check brief-render flow; do
  case $mode in
    proof) command=(bash "$proof/scripts/check-evidence.sh" --now 2026-09-24T00:00:00Z); input="$proof/references/evidence-example.json" ;;
    brief-check|brief-render) command=(bash "$proof/scripts/accountability-brief.sh" --mode "${mode#brief-}"); input="$proof/references/accountability-product.json" ;;
    flow) command=(bash "$flow/scripts/measure-flow.sh"); input="$flow/references/flow-example.json" ;;
  esac
  for kind in empty partial; do
    status=0
    PATH="$work/bin:$PATH" READ_FAILURE_KIND="$kind" "${command[@]}" "$input" > "$work/result" 2> "$work/error" || status=$?
    [[ $status == 2 && ! -s $work/result && -s $work/error ]]
  done
done
printf 'installed evidence tools: PASS (proof, check/render, flow, malformed bytes and failed retained reads)\n'
