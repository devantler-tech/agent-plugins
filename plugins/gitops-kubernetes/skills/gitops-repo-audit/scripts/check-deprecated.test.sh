#!/usr/bin/env bash
# Self-test for check-deprecated.sh.
#
# Proves the script's argument validation, prerequisite checks, and
# deprecation-detection exit-code contract behave as documented — so a refactor
# that breaks an error path or silently swallows a deprecated-API finding is
# caught here, not by a stale audit reaching a user. Self-contained: stubs the
# `flux` CLI on PATH (no real flux, no cluster, no network) and asserts exit
# code + the specific message for every branch.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-deprecated.sh"

pass=0
fail=0

# A minimal PATH that has coreutils (basename/grep/head) but NOT flux, used to
# exercise the "flux CLI is required" branch deterministically regardless of
# whether flux happens to be installed on the host.
NOFLUX_PATH="/usr/bin:/bin"

# Write a stub `flux` into a throwaway bin dir and echo that dir.
#   $1 = output that `flux migrate` should print (its presence of ✚/-> drives
#        the script's exit code).
make_flux_stub() {
  local out="$1" bindir
  bindir="$(mktemp -d)"
  cat > "$bindir/flux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  version) echo "flux version 2.0.0-stub" ;;
  migrate) cat <<'MIGRATE'
$out
MIGRATE
    ;;
esac
EOF
  chmod +x "$bindir/flux"
  echo "$bindir"
}

# check_exit <description> <expected-rc> <expected-substring> -- <command...>
# Runs the command, capturing combined output + exit code without tripping the
# test's own errexit-free flow, then asserts both.
check_exit() {
  local desc="$1" want_rc="$2" pat="$3"
  shift 3
  [ "$1" = "--" ] && shift
  local out rc
  out=$("$@" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq "$want_rc" ] && { [ -z "$pat" ] || printf '%s' "$out" | grep -qF "$pat"; }; then
    echo "  ✓ $desc"
    pass=$((pass + 1))
  else
    echo "  ✗ $desc — expected exit $want_rc + message containing '$pat'; got exit $rc"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
}

# --- argument / prerequisite validation (flux never reached) ---

check_exit "no directory flag fails with usage" 1 "directory is required" \
  -- bash "$SCRIPT"

check_exit "-h prints usage and exits non-zero" 1 "Usage:" \
  -- bash "$SCRIPT" -h

check_exit "non-existent directory fails" 1 "is not a directory" \
  -- bash "$SCRIPT" -d "/no/such/dir/$$"

valid_dir="$(mktemp -d)"
check_exit "missing flux CLI is reported" 1 "flux CLI is required" \
  -- env PATH="$NOFLUX_PATH" bash "$SCRIPT" -d "$valid_dir"

# --- deprecation detection (flux stubbed) ---

clean_bin="$(make_flux_stub "All Flux resources are up to date.")"
check_exit "clean repo exits 0" 0 "" \
  -- env PATH="$clean_bin:$PATH" bash "$SCRIPT" -d "$valid_dir"

# `->` marks an API migration in `flux migrate` dry-run output.
arrow_bin="$(make_flux_stub "HelmRelease/app helm.toolkit.fluxcd.io/v2beta1 -> helm.toolkit.fluxcd.io/v2")"
check_exit "deprecated API (-> marker) exits 1" 1 "" \
  -- env PATH="$arrow_bin:$PATH" bash "$SCRIPT" -d "$valid_dir"

# `✚` is the other marker the script greps for.
plus_bin="$(make_flux_stub "✚ Kustomization/app migrated to kustomize.toolkit.fluxcd.io/v1")"
check_exit "deprecated API (✚ marker) exits 1" 1 "" \
  -- env PATH="$plus_bin:$PATH" bash "$SCRIPT" -d "$valid_dir"

echo "-----------------------------------------"
echo "check-deprecated.sh self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
