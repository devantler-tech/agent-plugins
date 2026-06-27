#!/usr/bin/env bash
# Self-test for discover.sh.
#
# Proves the inventory script's argument validation, awk prerequisite check, and
# resource-classification contract behave as documented — so a refactor that
# breaks an error path, misfiles a resource (Flux vs Kubernetes vs kustomize),
# or stops honouring an exclusion is caught here, not by a wrong audit reaching a
# user. Self-contained: builds throwaway fixture dirs and uses only awk/git/
# coreutils — no network, no cluster.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/discover.sh"

# discover.sh needs bash 4+ (associative arrays); invoke it via an absolute bash
# path captured here so the restricted PATHs below control only what the *script*
# sees (awk presence), never which interpreter runs it.
BASH_BIN="$(command -v bash)"

pass=0
fail=0

# check_exit <description> <expected-rc> <expected-substring> -- <command...>
# Runs the command, capturing combined output + exit code without tripping the
# test's own flow, then asserts both. An empty substring asserts only the code.
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

# refute_substr <description> <absent-substring> -- <command...>
# Asserts the command exits 0 and the substring is ABSENT from its output — used
# to prove an excluded / auto-skipped resource is NOT counted in the inventory.
refute_substr() {
  local desc="$1" pat="$2"
  shift 2
  [ "$1" = "--" ] && shift
  local out rc
  out=$("$@" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF -- "$pat"; then
    echo "  ✓ $desc"
    pass=$((pass + 1))
  else
    echo "  ✗ $desc — expected exit 0 with '$pat' absent; got exit $rc"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
}

# check_output_eq <description> <expected-output> -- <command...>
# Asserts exit 0 and that combined output equals exactly the expected string
# (trailing newline ignored). Used for the empty-inventory `{}` contract, where a
# substring match would be ambiguous (the empty `byKind: {}` appears regardless).
check_output_eq() {
  local desc="$1" want="$2"
  shift 2
  [ "$1" = "--" ] && shift
  local out rc
  out=$("$@" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then
    echo "  ✓ $desc"
    pass=$((pass + 1))
  else
    echo "  ✗ $desc — expected exit 0 and output '$want'; got exit $rc"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
}

# section_block <section-name> : reads the full discover JSON on stdin and prints
# only the lines of that top-level section (header through the line before the
# next 2-space-indented "key" — i.e. the next section, or EOF for the last one).
section_block() {
  awk -v s="\"$1\"" '
    $0 ~ "^  " s ":" { inblock = 1; print; next }
    inblock && /^  "[a-zA-Z]/ { inblock = 0 }
    inblock { print }
  '
}

# check_in_section <description> <section> <count-key> -- <command...>
# Asserts exit 0 AND that `"<count-key>": 1` appears *within* the named section —
# so a resource filed under the wrong top-level bucket (Flux vs Kubernetes vs
# kustomize) is caught, which a whole-output substring match would miss.
check_in_section() {
  local desc="$1" section="$2" key="$3"
  shift 3
  [ "$1" = "--" ] && shift
  local out rc block
  out=$("$@" 2>&1) && rc=0 || rc=$?
  block=$(printf '%s\n' "$out" | section_block "$section")
  if [ "$rc" -eq 0 ] && printf '%s' "$block" | grep -qF -- "\"$key\": 1"; then
    echo "  ✓ $desc"
    pass=$((pass + 1))
  else
    echo "  ✗ $desc — expected exit 0 and '\"$key\": 1' inside section '$section'; got exit $rc"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
}

# A throwaway git work tree — exercises discover.sh's primary git-pathspec branch
# (untracked files are surfaced via `git ls-files --others`, no commit needed).
new_git_dir() {
  local d
  d="$(mktemp -d)"
  git -C "$d" init -q
  echo "$d"
}

# --- argument validation (prerequisites / discovery never reached) ---

check_exit "-h prints usage and exits 0" 0 "Usage:" \
  -- "$BASH_BIN" "$SCRIPT" -h

check_exit "unknown argument fails with usage" 1 "Unknown argument" \
  -- "$BASH_BIN" "$SCRIPT" --bogus

check_exit "-d without a value fails" 1 "--dir requires" \
  -- "$BASH_BIN" "$SCRIPT" -d

check_exit "-e without a value fails" 1 "--exclude requires" \
  -- "$BASH_BIN" "$SCRIPT" -e

# --- prerequisite check (awk required) ---

# An empty PATH dir hides awk regardless of where it lives on the host, so the
# "awk is not installed" branch is exercised deterministically on any machine.
NOAWK_PATH="$(mktemp -d)"
empty_dir="$(mktemp -d)"
check_exit "missing awk is reported" 1 "awk is not installed" \
  -- env PATH="$NOAWK_PATH" "$BASH_BIN" "$SCRIPT" -d "$empty_dir"

# --- empty inventory (non-git dir → find fallback branch) ---

check_output_eq "empty directory yields an empty JSON object" "{}" \
  -- "$BASH_BIN" "$SCRIPT" -d "$empty_dir"

# --- resource classification ---

flux_dir="$(new_git_dir)"
cat > "$flux_dir/hr.yaml" <<'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: app
EOF
check_in_section "Flux resource is filed under fluxResources" fluxResources HelmRelease \
  -- "$BASH_BIN" "$SCRIPT" -d "$flux_dir"

k8s_dir="$(new_git_dir)"
cat > "$k8s_dir/deploy.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
EOF
check_in_section "vanilla Kubernetes resource is filed under kubernetesResources" kubernetesResources Deployment \
  -- "$BASH_BIN" "$SCRIPT" -d "$k8s_dir"

kust_dir="$(new_git_dir)"
mkdir -p "$kust_dir/overlays"
cat > "$kust_dir/overlays/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deploy.yaml
EOF
check_in_section "kustomize overlay is filed under kustomizeOverlays.byDirectory" kustomizeOverlays overlays \
  -- "$BASH_BIN" "$SCRIPT" -d "$kust_dir"

# --- exclusion semantics ---

# -e takes a path resolved the same way as the scanned dirs (under -d), so an
# absolute child path excludes it. The only manifest lives under it → empty set.
ex_dir="$(new_git_dir)"
mkdir -p "$ex_dir/skipme"
cat > "$ex_dir/skipme/deploy.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: x
EOF
refute_substr "resource under an -e excluded directory is not counted" "Deployment" \
  -- "$BASH_BIN" "$SCRIPT" -d "$ex_dir" -e "$ex_dir/skipme"

# A dir holding a Chart.yaml is auto-detected as a Helm chart and skipped, so a
# manifest nested beneath it must not appear in the inventory.
chart_dir="$(new_git_dir)"
mkdir -p "$chart_dir/mychart/templates"
cat > "$chart_dir/mychart/Chart.yaml" <<'EOF'
apiVersion: v2
name: mychart
version: 0.1.0
EOF
cat > "$chart_dir/mychart/templates/deploy.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: x
EOF
refute_substr "resource under an auto-skipped Helm chart directory is not counted" "Deployment" \
  -- "$BASH_BIN" "$SCRIPT" -d "$chart_dir"

echo "-----------------------------------------"
echo "discover.sh self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
