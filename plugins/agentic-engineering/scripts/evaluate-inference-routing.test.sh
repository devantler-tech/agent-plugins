#!/usr/bin/env bash
# Real evaluator behavior; all observations are synthetic, no model is launched.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/request.json" <<'JSON'
{
  "policy": {
    "version": 1, "revision": "test-1", "enabled": true,
    "billingMode": "subscription-only", "paidFallback": false,
    "deniedModelTerms": ["forbidden-family"],
    "routes": {
      "support": {"model": "small-v1", "runtime": "local", "effort": "low"},
      "workhorse": {"model": "standard-v1", "runtime": "local", "effort": "medium"},
      "diagnosis": {"model": "reasoner-v1", "runtime": "local", "effort": "high"},
      "deepRefactor": {"model": "native-v1", "runtime": "native", "effort": "high"}
    },
    "runtimes": {
      "local": {"enabled": true, "role": "owner", "expiresAt": 2000003600},
      "native": {"enabled": true, "role": "builder", "expiresAt": 2000003600}
    },
    "limits": {"maxDepth": 1, "maxChildren": 1, "repairHypotheses": 2,
      "activeMinutes": 20, "snapshotMaxAgeSeconds": 300,
      "reservePercent": {"short": 20, "weekly": 15}}
  },
  "task": {"class": "workhorse", "depth": 0, "children": 0,
    "distinctFailedHypotheses": 0, "activeMinutes": 0, "failureKind": "none",
    "contractClear": true, "checksDefined": true, "reversible": true,
    "sensitiveInvariants": false, "writeRequired": true},
  "snapshot": {"observedAt": 2000000000, "runtime": "local", "runtimeVersion": "test",
    "model": "standard-v1", "billing": "included", "controls": "verified",
    "evidenceRef": "test-fixture-only",
    "buckets": {
      "short": {"remainingPercent": 70, "estimatedChainPercent": 5, "reservedPercent": 10, "unsettledPercent": 5},
      "weekly": {"remainingPercent": 80, "estimatedChainPercent": 2, "reservedPercent": 3, "unsettledPercent": 1}
    }}
}
JSON
# Apply a fixture change, run the real evaluator, and assert its exit code and JSON result.
# Arguments: case name, jq fixture transformation, expected exit status, jq assertion.
run_case() {
  local name="$1" change="$2" expected_exit="$3" assertion="$4" status=0
  jq "$change" "$TMP/request.json" > "$TMP/input.json"
  bash "$HERE/evaluate-inference-routing.sh" --now 2000000000 < "$TMP/input.json" > "$TMP/output.json" || status=$?
  if [[ "$status" != "$expected_exit" ]] || ! jq -e "$assertion" "$TMP/output.json" > /dev/null; then
    printf 'FAIL %s: exit=%s expected=%s\n' "$name" "$status" "$expected_exit" >&2
    cat "$TMP/output.json" >&2
    exit 1
  fi
  printf 'PASS %s\n' "$name"
}
run_case nominal '.' 0 '.decision == "RECOMMEND" and .route.model == "standard-v1" and .executionAdmitted == false'
run_case escalation '.task.distinctFailedHypotheses=2 | .snapshot.model="reasoner-v1"' 0 '.taskClass == "diagnosis"'
run_case active-time '.task.activeMinutes=20 | .snapshot.model="reasoner-v1"' 0 '.taskClass == "diagnosis"'
run_case hard-task '.task.sensitiveInvariants=true | .snapshot.model="reasoner-v1"' 0 '.taskClass == "diagnosis"'
run_case unclear-write '.task.contractClear=false | .snapshot.model="reasoner-v1"' 1 '.reasons | index("CONTRACT_UNCLEAR") != null'
run_case unclear-investigation '.task.contractClear=false | .task.writeRequired=false | .snapshot.model="reasoner-v1"' 0 '.taskClass == "diagnosis"'
run_case missing-checks '.task.checksDefined=false | .snapshot.model="reasoner-v1"' 1 '.reasons | index("CHECKS_UNDEFINED") != null'
run_case irreversible-write '.task.reversible=false | .snapshot.model="reasoner-v1"' 1 '.reasons | index("IRREVERSIBLE_WRITE") != null'
run_case environment '.task.failureKind="environment"' 1 '.reasons | index("NON_REASONING_FAILURE") != null'
run_case policy-off '.policy.enabled=false' 1 '.reasons | index("POLICY_DISABLED") != null'
run_case no-model-override '.snapshot.model="other-v2"' 1 '.reasons | index("MODEL_MISMATCH") != null'
run_case unresolved-provider-alias '.policy.routes.workhorse.model="reasoner-stable" | .snapshot.model="reasoner-2026-09"' 1 '.reasons | index("MODEL_MISMATCH") != null'
run_case no-paid-fallback '.policy.paidFallback=true' 2 '.decision == "INVALID"'
run_case denied-case '.policy.routes.workhorse.model="FORBIDDEN-FAMILY-v2"' 2 '.decision == "INVALID"'
run_case denied-unused-route '.policy.routes.support.model="forbidden-family-v1"' 2 '.decision == "INVALID"'
run_case opaque-default '.policy.routes.workhorse.model="default" | .snapshot.model="default"' 2 '.decision == "INVALID"'
run_case opaque-best '.policy.routes.workhorse.model="best" | .snapshot.model="best"' 2 '.decision == "INVALID"'
run_case duplicated-denial '.policy.deniedModelTerms=["prohibited","PROHIBITED"]' 2 '.decision == "INVALID"'
run_case missing-policy '.policy=null' 2 '.decision == "INVALID"'
run_case malformed-class '.task.class="latest"' 2 '.decision == "INVALID"'
run_case unknown-field '.snapshot.admitted=true' 2 '.decision == "INVALID"'
run_case unknown-quota '.snapshot.buckets.short=null' 1 '.reasons | index("QUOTA_UNKNOWN") != null'
run_case unsettled-debit '.snapshot.buckets.short.unsettledPercent=40' 1 '.reasons | index("QUOTA_RESERVE") != null'
run_case weekly-floor '.snapshot.buckets.weekly.remainingPercent=20' 1 '.reasons | index("QUOTA_RESERVE") != null'
run_case exact-floor '.snapshot.buckets.weekly.remainingPercent=21' 0 '.decision == "RECOMMEND"'
run_case unknown-estimate '.snapshot.buckets.short.estimatedChainPercent=null' 1 '.reasons | index("QUOTA_UNKNOWN") != null'
run_case stale '.snapshot.observedAt=1999999600' 1 '.reasons | index("SNAPSHOT_STALE") != null'
run_case future '.snapshot.observedAt=2000000001' 1 '.reasons | index("SNAPSHOT_STALE") != null'
run_case expired-runtime '.policy.runtimes.local.expiresAt=2000000000' 1 '.reasons | index("RUNTIME_EXPIRED") != null'
run_case disabled-runtime '.policy.runtimes.local.enabled=false' 1 '.reasons | index("RUNTIME_DISABLED") != null'
run_case observer-write '.policy.runtimes.local.role="observer"' 1 '.reasons | index("OBSERVER_WRITE") != null'
run_case child-limit '.task.children=2' 1 '.reasons | index("DELEGATION_LIMIT") != null'
run_case depth-limit '.task.depth=2' 1 '.reasons | index("DELEGATION_LIMIT") != null'
run_case unverified-controls '.snapshot.controls="unverified"' 1 '.reasons | index("CONTROLS_UNVERIFIED") != null'
run_case no-evidence '.snapshot.evidenceRef=null' 1 '.reasons | index("CONTROLS_UNVERIFIED") != null'
run_case paygo '.snapshot.billing="paygo"' 1 '.reasons | index("BILLING_UNPROVEN") != null'
run_case negative-quota '.snapshot.buckets.weekly.remainingPercent=-1' 2 '.decision == "INVALID"'
run_case no-cross-runtime-reuse '.task.class="deepRefactor" | .snapshot.model="native-v1"' 1 '.reasons | index("RUNTIME_MISMATCH") != null'
printf '{broken' > "$TMP/broken.json"
status=0
bash "$HERE/evaluate-inference-routing.sh" --now 2000000000 < "$TMP/broken.json" > "$TMP/output.json" 2>/dev/null || status=$?
if [[ "$status" != 2 ]] || ! jq -e '.decision == "INVALID" and .executionAdmitted == false' "$TMP/output.json" > /dev/null; then
  printf 'FAIL malformed JSON\n' >&2
  exit 1
fi
printf 'PASS malformed JSON\n'
