#!/usr/bin/env bash
# Optional offline assessment; disabled mode reads no contract and invokes no compiler.
set -euo pipefail
if [ "$#" -eq 0 ]; then
  printf '%s\n' '{"status":"DISABLED","authority":"assessment-only","executionAdmitted":false,"mutationPerformed":false,"reportedEvidenceAuthenticated":false}'
  exit 0
fi
if [ "$#" -eq 1 ] && [ "$1" = --help ]; then
  printf '%s\n' 'Usage: bash assess-autonomy.sh --assess --contract FILE --now YYYY-MM-DDTHH:MM:SSZ' \
    'Default: DISABLED. Opt-in assesses one bounded offline document; no authority or execution is granted.'
  exit 0
fi
if [ "$1" != --assess ]; then
  printf '%s\n' 'Explicit --assess opt-in must be the first argument.' >&2
  exit 2
fi
shift
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
command -v go >/dev/null || { printf '%s\n' 'Assessment needs the locally installed Go 1.22+ toolchain.' >&2; exit 2; }
# Compile only the shipped assessor. No surveyed source or dependency is imported.
export GOENV=off GOWORK=off GO111MODULE=off GOTOOLCHAIN=local GOFLAGS='' CGO_ENABLED=0
export GOOS='' GOARCH='' GOCACHEPROG=''
exec go run "$here/autonomy-contract-go/main.go" "$@"
