#!/usr/bin/env bash
# Pure, offline policy evaluation. Reads one {policy,task,snapshot} JSON object.
# Exit 0 RECOMMEND, 1 HOLD, 2 INVALID. NO exit status authorizes a launch.
# Observations are caller reports, not authenticated runtime or billing evidence.
# This command never launches inference, takes a lock, or reserves allowance.
set -euo pipefail
# Emit a fixed, non-sensitive invalid-input result and terminate with exit status 2.
invalid() {
  printf '%s\n' '{"decision":"INVALID","executionAdmitted":false,"reasons":["INVALID_INPUT"]}'
  exit 2
}
if [[ $# == 0 ]]; then
  now="$(date +%s)"
elif [[ $# == 2 && "$1" == --now && "$2" =~ ^[0-9]{1,12}$ ]]; then
  now="$2"
else
  invalid
fi
command -v jq > /dev/null || invalid
result=$(jq -sce --argjson now "$now" '
  def exact($allowed): type == "object" and (keys | sort) == ($allowed | sort);
  def text: type == "string" and length > 0 and length <= 256;
  def identifier: text and test("^[A-Za-z0-9][A-Za-z0-9._/-]*$");
  def int: type == "number" and floor == . and . >= 0 and . <= 1000000000000;
  def pct: type == "number" and . >= 0 and . <= 100;
  def nullable_pct: . == null or pct;
  def boolean: type == "boolean";
  def bucket:
    . == null or
    (exact(["remainingPercent","estimatedChainPercent","reservedPercent","unsettledPercent"])
      and all(.[]; nullable_pct));
  def valid:
    exact(["policy","task","snapshot"])
    and (.policy |
      exact(["version","revision","enabled","billingMode","paidFallback","deniedModelTerms","routes","runtimes","limits"])
      and .version == 1 and (.revision | identifier) and (.enabled | boolean)
      and .billingMode == "subscription-only" and .paidFallback == false
      and (.deniedModelTerms | type == "array" and length > 0
        and all(.[]; identifier) and (map(ascii_downcase) | unique | length) == length)
      and (.routes | exact(["support","workhorse","diagnosis","deepRefactor"])
        and all(.[]; exact(["model","runtime","effort"])
          and (.model | identifier and (ascii_downcase | IN("default","inherit","latest","auto","best") | not))
          and (.runtime | identifier)
          and (.effort | IN("low","medium","high","xhigh"))))
      and (.runtimes | type == "object" and length > 0
        and all(keys[]; identifier)
        and all(.[]; exact(["enabled","role","expiresAt"])
          and (.enabled | boolean) and (.role | IN("owner","builder","observer"))
          and (.expiresAt | int)))
      and (.limits | exact(["maxDepth","maxChildren","repairHypotheses","activeMinutes","snapshotMaxAgeSeconds","reservePercent"])
        and (.maxDepth | int and . <= 1) and (.maxChildren | int and . <= 1)
        and (.repairHypotheses | int and . >= 1) and (.activeMinutes | int and . >= 1)
        and (.snapshotMaxAgeSeconds | int and . >= 1 and . <= 300)
        and (.reservePercent | exact(["short","weekly"]) and all(.[]; pct and . > 0)))
      and (. as $p | all(.routes[]; . as $route |
        ($p.runtimes | has($route.runtime))
        and all($p.deniedModelTerms[]; . as $term |
          $route.model | ascii_downcase | contains($term | ascii_downcase) | not))))
    and (.task |
      exact(["class","depth","children","distinctFailedHypotheses","activeMinutes","failureKind","contractClear","checksDefined","reversible","sensitiveInvariants","writeRequired"])
      and (.class | IN("support","workhorse","diagnosis","deepRefactor"))
      and all(.depth,.children,.distinctFailedHypotheses,.activeMinutes; int)
      and (.failureKind | IN("none","reasoning","environment","quota","authority"))
      and all(.contractClear,.checksDefined,.reversible,.sensitiveInvariants,.writeRequired; boolean))
    and (.snapshot |
      exact(["observedAt","runtime","runtimeVersion","model","billing","controls","evidenceRef","buckets"])
      and (.observedAt | int) and (.runtime | identifier) and (.runtimeVersion | text)
      and (.model | . == null or identifier)
      and (.billing | IN("included","unknown","paygo"))
      and (.controls | IN("verified","unverified"))
      and (.evidenceRef | . == null or text)
      and (.buckets | exact(["short","weekly"]) and all(.[]; bucket)));
  if length != 1 or (.[0] | valid | not) then error("invalid request") else .[0] end
  | .policy as $p | .task as $t | .snapshot as $s
  | (if ($t.class | IN("workhorse","support")) and
        (($t.contractClear and $t.checksDefined and $t.reversible and ($t.sensitiveInvariants | not) | not)
         or $t.distinctFailedHypotheses >= $p.limits.repairHypotheses
         or $t.activeMinutes >= $p.limits.activeMinutes)
      then "diagnosis" else $t.class end) as $class
  | $p.routes[$class] as $route
  | $p.runtimes[$route.runtime] as $runtime
  | [
      if $p.enabled then empty else "POLICY_DISABLED" end,
      if $t.failureKind | IN("environment","quota","authority") then "NON_REASONING_FAILURE" else empty end,
      if $t.writeRequired and ($t.contractClear | not) then "CONTRACT_UNCLEAR" else empty end,
      if $t.writeRequired and ($t.checksDefined | not) then "CHECKS_UNDEFINED" else empty end,
      if $t.writeRequired and ($t.reversible | not) then "IRREVERSIBLE_WRITE" else empty end,
      if $runtime.enabled then empty else "RUNTIME_DISABLED" end,
      if $runtime.expiresAt <= $now then "RUNTIME_EXPIRED" else empty end,
      if $runtime.role == "observer" and $t.writeRequired then "OBSERVER_WRITE" else empty end,
      if $t.depth > $p.limits.maxDepth or $t.children > $p.limits.maxChildren then "DELEGATION_LIMIT" else empty end,
      if $s.runtime != $route.runtime then "RUNTIME_MISMATCH" else empty end,
      if $s.model != $route.model then "MODEL_MISMATCH" else empty end,
      if $s.observedAt > $now or ($now - $s.observedAt) > $p.limits.snapshotMaxAgeSeconds then "SNAPSHOT_STALE" else empty end,
      if $s.billing != "included" then "BILLING_UNPROVEN" else empty end,
      if $s.controls != "verified" or $s.evidenceRef == null then "CONTROLS_UNVERIFIED" else empty end,
      (["short","weekly"][] as $name | $s.buckets[$name] as $b |
        if $b == null or any($b[]; . == null) then "QUOTA_UNKNOWN"
        elif ($b.estimatedChainPercent + $b.reservedPercent + $b.unsettledPercent + $p.limits.reservePercent[$name]) > $b.remainingPercent
        then "QUOTA_RESERVE" else empty end)
    ] | unique as $reasons
  | {decision: (if $reasons | length == 0 then "RECOMMEND" else "HOLD" end),
      policyRevision: $p.revision, taskClass: $class, route: $route,
      reportedControls: $s.controls, executionAdmitted: false, reasons: $reasons,
      boundary: "Caller reports are unauthenticated. No inference launch, billing enforcement, or quota reservation occurred."}
' 2>/dev/null) || invalid
printf '%s\n' "$result"
[[ "$(jq -r '.decision' <<< "$result")" == RECOMMEND ]] || exit 1
