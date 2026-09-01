#!/usr/bin/env bash
# Self-test for refresh-desired-state-digests.sh.
#
# Proves the generator writes exactly the values validate-manifests.sh demands — the
# whole point of the pair, since a generator that disagrees with the gate leaves the
# branch just as unmergeable as having no generator at all. So the coupling is asserted
# against the REAL repository tree and the REAL validator, not against a restatement of
# the hashing rule: a skill change is simulated, the validator is shown to reject it,
# the generator is run, and the validator is shown to accept it. The ablation is the
# same scenario without the refresh, which must still fail.
#
# Also proves the two hashing rules stay distinct (definition files normalize CRLF,
# runtime assets do not), that the pass is idempotent and format-preserving, and that
# every unknown or unresolvable digest fails closed rather than being written wrong.
#
# Self-contained: throwaway copies, the REAL scripts, no network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REFRESH="$SCRIPT_DIR/refresh-desired-state-digests.sh"

pass=0
fail=0
ok() { echo "  ✓ $1"; pass=$((pass + 1)); }
ko() { echo "  ✗ $1"; fail=$((fail + 1)); }

tmproot=$(mktemp -d)
trap 'rm -rf "$tmproot"' EXIT
fresh() { mktemp -d "$tmproot/case.XXXXXX"; }

sha_norm() {
  LC_ALL=C PERL5OPT='' PERL_UNICODE='' PERLIO='' perl -C0 -pe \
    'BEGIN { binmode STDIN, ":raw"; binmode STDOUT, ":raw" } s/\r\n/\n/g' \
    < "$1" | shasum -a 256 | awk '{ print $1 }'
}
sha_raw() { shasum -a 256 "$1" | awk '{ print $1 }'; }

ZERO=0000000000000000000000000000000000000000000000000000000000000000

# A minimal tree carrying only what the generator reads: an entrypoint agent, one role
# definition, one bundled skill, and one runtime asset.
make_fixture() {
  local root="$1"
  mkdir -p "$root/plugins/alpha/agents" \
    "$root/plugins/alpha/skills/agent-improvement" \
    "$root/plugins/alpha/scripts" \
    "$root/plugins/alpha/resources"
  printf -- '---\nname: alpha-entry\n---\nentry body\n' > "$root/plugins/alpha/agents/alpha-entry.agent.md"
  printf -- '---\nname: agent-improver\n---\nimprover body\n' > "$root/plugins/alpha/agents/agent-improver.agent.md"
  printf -- '---\nname: agent-improvement\n---\nskill body\n' > "$root/plugins/alpha/skills/agent-improvement/SKILL.md"
  printf '#!/usr/bin/env bash\necho asset\n' > "$root/plugins/alpha/scripts/asset.sh"
  chmod +x "$root/plugins/alpha/scripts/asset.sh"
  cat > "$root/plugins/alpha/resources/provider-neutral.desired-state.json" <<JSON
{
  "spec": {
    "source": {
      "entrypoint": "alpha-entry",
      "requiredRuntimeAssets": [
        {
          "path": "scripts/asset.sh",
          "sha256": "$ZERO",
          "executable": true
        }
      ],
      "entrypointSha256": "$ZERO"
    },
    "roles": {
      "agent-improver": {
        "definitionSha256": "$ZERO",
        "skillSha256": "$ZERO"
      }
    }
  }
}
JSON
}

field() { jq -r "$2" "$1/plugins/alpha/resources/provider-neutral.desired-state.json"; }

echo "refresh-desired-state-digests.sh self-test"

# --- the generator writes what each digest kind actually pins -------------------------
d=$(fresh); make_fixture "$d"
( cd "$d" && "$REFRESH" > /dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then ok "rewrites a fully stale resource and exits 0"; else ko "rewrites a fully stale resource and exits 0 (got $rc)"; fi

want=$(sha_norm "$d/plugins/alpha/agents/alpha-entry.agent.md")
if [ "$(field "$d" '.spec.source.entrypointSha256')" = "$want" ]; then
  ok "entrypointSha256 is the entrypoint agent's normalized digest"
else ko "entrypointSha256 is the entrypoint agent's normalized digest"; fi

want=$(sha_norm "$d/plugins/alpha/agents/agent-improver.agent.md")
if [ "$(field "$d" '.spec.roles["agent-improver"].definitionSha256')" = "$want" ]; then
  ok "definitionSha256 resolves to agents/<role>.agent.md"
else ko "definitionSha256 resolves to agents/<role>.agent.md"; fi

want=$(sha_norm "$d/plugins/alpha/skills/agent-improvement/SKILL.md")
if [ "$(field "$d" '.spec.roles["agent-improver"].skillSha256')" = "$want" ]; then
  ok "skillSha256 resolves to the bundled agent-improvement skill"
else ko "skillSha256 resolves to the bundled agent-improvement skill"; fi

want=$(sha_raw "$d/plugins/alpha/scripts/asset.sh")
if [ "$(field "$d" '.spec.source.requiredRuntimeAssets[0].sha256')" = "$want" ]; then
  ok "runtime asset digest is the exact bytes"
else ko "runtime asset digest is the exact bytes"; fi

# --- the two hashing rules must stay different ----------------------------------------
# A definition file differing only by CRLF keeps its digest; a runtime asset does not.
# Collapsing the two would silently accept a checkout-only change to an executed script.
d=$(fresh); make_fixture "$d"
( cd "$d" && "$REFRESH" > /dev/null 2>&1 )
before_def=$(field "$d" '.spec.roles["agent-improver"].definitionSha256')
before_asset=$(field "$d" '.spec.source.requiredRuntimeAssets[0].sha256')
perl -pe 's/\n/\r\n/' < "$d/plugins/alpha/agents/agent-improver.agent.md" > "$d/crlf.tmp"
mv "$d/crlf.tmp" "$d/plugins/alpha/agents/agent-improver.agent.md"
perl -pe 's/\n/\r\n/' < "$d/plugins/alpha/scripts/asset.sh" > "$d/crlf2.tmp"
cat "$d/crlf2.tmp" > "$d/plugins/alpha/scripts/asset.sh"
( cd "$d" && "$REFRESH" > /dev/null 2>&1 )
if [ "$(field "$d" '.spec.roles["agent-improver"].definitionSha256')" = "$before_def" ]; then
  ok "a CRLF-only change leaves a definition digest unchanged"
else ko "a CRLF-only change leaves a definition digest unchanged"; fi
if [ "$(field "$d" '.spec.source.requiredRuntimeAssets[0].sha256')" != "$before_asset" ]; then
  ok "a CRLF-only change DOES change a runtime asset digest"
else ko "a CRLF-only change DOES change a runtime asset digest"; fi

# --- idempotence and format preservation ---------------------------------------------
d=$(fresh); make_fixture "$d"
( cd "$d" && "$REFRESH" > /dev/null 2>&1 )
cp "$d/plugins/alpha/resources/provider-neutral.desired-state.json" "$d/first.json"
( cd "$d" && "$REFRESH" > /dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$d/first.json" "$d/plugins/alpha/resources/provider-neutral.desired-state.json"; then
  ok "a second run over a current tree writes nothing"
else ko "a second run over a current tree writes nothing (rc=$rc)"; fi

# Only the digest values may move: a generator that reformatted the document would make
# every sync PR an unreviewable whole-file diff.
d=$(fresh); make_fixture "$d"
cp "$d/plugins/alpha/resources/provider-neutral.desired-state.json" "$d/before.json"
( cd "$d" && "$REFRESH" > /dev/null 2>&1 )
changed=$(diff "$d/before.json" "$d/plugins/alpha/resources/provider-neutral.desired-state.json" \
  | grep -c '^[<>]')
if [ "$changed" -eq 8 ]; then
  ok "only the four digest lines change (4 removed + 4 added)"
else ko "only the four digest lines change (got $changed changed lines)"; fi

# --- --check reports without writing ---------------------------------------------------
d=$(fresh); make_fixture "$d"
cp "$d/plugins/alpha/resources/provider-neutral.desired-state.json" "$d/before.json"
( cd "$d" && "$REFRESH" --check > /dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 1 ] && cmp -s "$d/before.json" "$d/plugins/alpha/resources/provider-neutral.desired-state.json"; then
  ok "--check reports drift (exit 1) and writes nothing"
else ko "--check reports drift (exit 1) and writes nothing (rc=$rc)"; fi

( cd "$d" && "$REFRESH" > /dev/null 2>&1 )
( cd "$d" && "$REFRESH" --check > /dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then ok "--check exits 0 on a current tree"; else ko "--check exits 0 on a current tree (got $rc)"; fi

# --- fail closed -----------------------------------------------------------------------
d=$(fresh); make_fixture "$d"
rm "$d/plugins/alpha/skills/agent-improvement/SKILL.md"
( cd "$d" && "$REFRESH" > "$d/out" 2>&1 ); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'pins a file that does not exist' "$d/out"; then
  ok "a digest whose target file is missing fails closed"
else ko "a digest whose target file is missing fails closed (rc=$rc)"; fi

d=$(fresh); make_fixture "$d"
J="$d/plugins/alpha/resources/provider-neutral.desired-state.json"
jq '.spec.roles["some-other-role"] = {"skillSha256": "'"$ZERO"'"}' "$J" > "$J.tmp" && mv "$J.tmp" "$J"
( cd "$d" && "$REFRESH" > "$d/out" 2>&1 ); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'no known source path in this generator' "$d/out"; then
  ok "a skillSha256 on an unmapped role fails closed instead of guessing"
else ko "a skillSha256 on an unmapped role fails closed instead of guessing (rc=$rc)"; fi
if [ "$(jq -r '.spec.roles["some-other-role"].skillSha256' "$J")" = "$ZERO" ]; then
  ok "the unmapped role's digest is left untouched"
else ko "the unmapped role's digest is left untouched"; fi

# A declared digest that nothing resolves must not be silently skipped: exiting 0 there would
# report "every digest is current" over one the generator never examined, which is the same
# shape of failure this generator exists to remove one level up.
d=$(fresh); make_fixture "$d"
J="$d/plugins/alpha/resources/provider-neutral.desired-state.json"
jq '.spec.source.entrypoint = ""' "$J" > "$J.tmp" && mv "$J.tmp" "$J"
( cd "$d" && "$REFRESH" > "$d/out" 2>&1 ); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'entrypointSha256 is declared but entrypoint is empty' "$d/out"; then
  ok "entrypointSha256 with no entrypoint fails closed instead of exiting 0"
else ko "entrypointSha256 with no entrypoint fails closed instead of exiting 0 (rc=$rc)"; fi

d=$(fresh); make_fixture "$d"
J="$d/plugins/alpha/resources/provider-neutral.desired-state.json"
jq 'del(.spec.source.requiredRuntimeAssets[0].path)' "$J" > "$J.tmp" && mv "$J.tmp" "$J"
( cd "$d" && "$REFRESH" > "$d/out" 2>&1 ); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'declares no path' "$d/out"; then
  ok "a runtime asset with a digest but no path fails closed"
else ko "a runtime asset with a digest but no path fails closed (rc=$rc)"; fi

# A missing hasher is an environment failure (exit 2), not a claim that a present file is absent.
d=$(fresh); make_fixture "$d"
mkdir -p "$d/onlybin"
for t in bash env jq perl awk find sort dirname; do
  real=$(command -v "$t" 2> /dev/null) && ln -sf "$real" "$d/onlybin/$t"
done
( cd "$d" && PATH="$d/onlybin" "$REFRESH" > "$d/out" 2>&1 ); rc=$?
if [ "$rc" -eq 2 ] && grep -q 'no SHA-256 program found' "$d/out"; then
  ok "no sha256sum and no shasum exits 2, not a bogus missing-file exit 1"
else ko "no sha256sum and no shasum exits 2, not a bogus missing-file exit 1 (rc=$rc): $(head -1 "$d/out")"; fi

d=$(fresh); make_fixture "$d"
( cd "$d" && "$REFRESH" --bogus > /dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then ok "an unknown flag exits 2"; else ko "an unknown flag exits 2 (got $rc)"; fi
( cd "$d" && "$REFRESH" --check extra > /dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then ok "a surplus argument exits 2"; else ko "a surplus argument exits 2 (got $rc)"; fi

# --- the coupling this pair exists for, against the REAL validator ---------------------
# Reproduces the deadlock: a synced skill change the sync workflow cannot follow up on.
d=$(fresh)
tar -cf - -C "$REPO_ROOT" --exclude='./.git' . 2> /dev/null | tar -xf - -C "$d"
SKILL="$d/plugins/agentic-engineering/skills/agent-improvement/SKILL.md"
if [ ! -f "$SKILL" ]; then
  ko "fixture copy carries the bundled agent-improvement skill"
else
  ( cd "$d" && ./scripts/validate-manifests.sh > /dev/null 2>&1 ); rc=$?
  if [ "$rc" -eq 0 ]; then ok "the untouched copy validates clean (control)"; else ko "the untouched copy validates clean (control, rc=$rc)"; fi

  printf '\n<!-- simulated upstream skill sync -->\n' >> "$SKILL"
  ( cd "$d" && ./scripts/validate-manifests.sh > "$d/v1" 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ] && grep -q 'agent-improvement skill digest must match the bundled skill' "$d/v1"; then
    ok "ABLATION: a synced skill change without a refresh still fails the gate"
  else ko "ABLATION: a synced skill change without a refresh still fails the gate (rc=$rc)"; fi

  ( cd "$d" && ./scripts/refresh-desired-state-digests.sh > /dev/null 2>&1 ); rc=$?
  if [ "$rc" -eq 0 ]; then ok "the generator refreshes the real resource"; else ko "the generator refreshes the real resource (rc=$rc)"; fi

  ( cd "$d" && ./scripts/validate-manifests.sh > "$d/v2" 2>&1 ); rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "refresh then validate is clean — the deadlock is resolved without a hand edit"
  else ko "refresh then validate is clean (rc=$rc): $(tail -1 "$d/v2")"; fi
fi

# ---------------------------------------------------------------------------
# Reporting success over a tree it never examined is the exact failure this script
# exists to remove, so it must not commit that failure itself. The enumeration is
# cwd-relative BY DESIGN (the cases above exercise the script against synthetic
# trees), but its `find` runs inside a process substitution whose failure neither
# `set -e` nor the loop's exit status observes. Run where nothing matches, it
# printed "every declared desired-state digest is already current" and exited 0.
# Zero resources is never a clean run.
# ---------------------------------------------------------------------------
d=$(fresh)
out=$( cd "$d" && "$REFRESH" 2>&1 ); rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'no \*.desired-state.json resource found'; then
  ok "an enumeration matching nothing fails closed instead of reporting success"
else
  ko "an enumeration matching nothing fails closed (rc=$rc): $out"
fi

d=$(fresh)
mkdir -p "$d/plugins"
out=$( cd "$d" && "$REFRESH" --check 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then
  ok "--check also fails closed on an empty enumeration"
else
  ko "--check also fails closed on an empty enumeration (rc=$rc): $out"
fi

echo "refresh-desired-state-digests.sh self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
