#!/usr/bin/env bash
# Self-test for validate.sh.
#
# Proves the manifest-validation script's argument validation, prerequisite
# checks (each of yq / kustomize / kubeconform), and exit-code contract behave as
# documented — so a refactor that swallows a validation failure or breaks an
# error path is caught here, not by a green audit hiding an invalid manifest.
# Self-contained: stubs the three external CLIs on PATH (configurable exit codes)
# and runs against throwaway fixtures — no network, no cluster, no real tools.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/validate.sh"

# validate.sh needs bash 4+ (associative arrays); invoke it via an absolute bash
# path captured here so the restricted PATHs below control only which external
# tools the *script* sees, never which interpreter runs it.
BASH_BIN="$(command -v bash)"

pass=0
fail=0

# check_exit <description> <expected-rc> <expected-substring> -- <command...>
check_exit() {
  local desc="$1" want_rc="$2" pat="$3"
  shift 3
  [ "$1" = "--" ] && shift
  local out rc
  out=$("$@" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq "$want_rc" ] && { [ -z "$pat" ] || printf '%s' "$out" | grep -qF -- "$pat"; }; then
    echo "  ✓ $desc"
    pass=$((pass + 1))
  else
    echo "  ✗ $desc — expected exit $want_rc + message containing '$pat'; got exit $rc"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
}

# make_tools <yq_rc> <kustomize_rc> <kubeconform_rc> -> bindir
# Writes the three CLIs as stubs exiting with the given codes (kustomize also
# prints a trivial manifest so the `kustomize build | kubeconform` pipe has
# data). Pass "x" for a tool's rc to leave it ABSENT — driving the matching
# "<tool> is not installed" prerequisite branch.
make_tools() {
  local yqrc="$1" kzrc="$2" kcrc="$3" bindir
  bindir="$(mktemp -d)"
  if [ "$yqrc" != x ]; then
    printf '#!/usr/bin/env bash\nexit %s\n' "$yqrc" > "$bindir/yq"
    chmod +x "$bindir/yq"
  fi
  if [ "$kzrc" != x ]; then
    printf '#!/usr/bin/env bash\necho "apiVersion: v1"\necho "kind: ConfigMap"\nexit %s\n' "$kzrc" > "$bindir/kustomize"
    chmod +x "$bindir/kustomize"
  fi
  if [ "$kcrc" != x ]; then
    printf '#!/usr/bin/env bash\nexit %s\n' "$kcrc" > "$bindir/kubeconform"
    chmod +x "$bindir/kubeconform"
  fi
  echo "$bindir"
}

# A fixture with a plain manifest (exercises validate_yaml_syntax +
# validate_kubernetes_manifests) and a kustomize overlay in its own dir
# (auto-detected → skipped by the first two passes, handled by
# validate_kustomize_overlays). Non-git → find fallback for file discovery.
make_fixture() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/app" "$d/overlay"
  printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: web\n' > "$d/app/deploy.yaml"
  printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n  - ../app/deploy.yaml\n' > "$d/overlay/kustomization.yaml"
  echo "$d"
}

# A minimal PATH carrying coreutils (find/dirname/env) but none of the three
# validated tools, so the stub bindir is the sole source of yq/kustomize/
# kubeconform. git is intentionally absent → find_files takes its find fallback.
BASE_PATH="/usr/bin:/bin"

# --- argument validation (prerequisites never reached) ---

check_exit "-h prints usage and exits 0" 0 "Usage:" \
  -- "$BASH_BIN" "$SCRIPT" -h

check_exit "unknown argument fails with usage" 1 "Unknown argument" \
  -- "$BASH_BIN" "$SCRIPT" --bogus

check_exit "-d without a value fails" 1 "--dir requires" \
  -- "$BASH_BIN" "$SCRIPT" -d

check_exit "-e without a value fails" 1 "--exclude requires" \
  -- "$BASH_BIN" "$SCRIPT" -e

# --- prerequisite checks (each tool reported independently) ---

empty_fix="$(mktemp -d)"

no_yq="$(make_tools x 0 0)"
check_exit "missing yq is reported" 1 "yq is not installed" \
  -- env PATH="$no_yq:$BASE_PATH" "$BASH_BIN" "$SCRIPT" -d "$empty_fix"

no_kustomize="$(make_tools 0 x 0)"
check_exit "missing kustomize is reported" 1 "kustomize is not installed" \
  -- env PATH="$no_kustomize:$BASE_PATH" "$BASH_BIN" "$SCRIPT" -d "$empty_fix"

no_kubeconform="$(make_tools 0 0 x)"
check_exit "missing kubeconform is reported" 1 "kubeconform is not installed" \
  -- env PATH="$no_kubeconform:$BASE_PATH" "$BASH_BIN" "$SCRIPT" -d "$empty_fix"

# --- exit-code contract (tools stubbed; real schemas dir present in the repo) ---

good_fix="$(make_fixture)"
all_pass="$(make_tools 0 0 0)"
check_exit "all validations passing → exit 0" 0 "All validations passed" \
  -- env PATH="$all_pass:$BASE_PATH" "$BASH_BIN" "$SCRIPT" -d "$good_fix"

yaml_fix="$(make_fixture)"
bad_yq="$(make_tools 1 0 0)"
check_exit "invalid YAML syntax (yq fails) → exit 1" 1 "Invalid YAML syntax" \
  -- env PATH="$bad_yq:$BASE_PATH" "$BASH_BIN" "$SCRIPT" -d "$yaml_fix"

manifest_fix="$(make_fixture)"
bad_kc="$(make_tools 0 0 1)"
check_exit "manifest validation failure (kubeconform fails) → exit 1" 1 "Validation failed with" \
  -- env PATH="$bad_kc:$BASE_PATH" "$BASH_BIN" "$SCRIPT" -d "$manifest_fix"

echo "-----------------------------------------"
echo "validate.sh self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
