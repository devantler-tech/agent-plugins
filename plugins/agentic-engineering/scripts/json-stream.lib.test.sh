#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=plugins/agentic-engineering/scripts/json-stream.lib.sh
. "$here/json-stream.lib.sh"
for value in '{}' '[]' '{"a":{"b":1},"c":[{},{"b":2}]}' $'{"a":1}\n{"a":2}' '{"a":"données/検証"}'; do
 printf '%s\n' "$value" | json_stream_unique
done
for value in '' '{' '{"a":1,"a":2}' '{"a":1,"\u0061":2}' '{"a":{},"a":{}}' '[{"a":1,"a":2}]' $'{"a":1}\n{"b":[],"b":[]}'; do
 if printf '%s\n' "$value" | json_stream_unique; then printf 'FAIL: ambiguous raw JSON accepted\n' >&2; exit 1; fi
done
for value in '{"a":"\\udc00"}' '{"a":"\\ud800"}' '{"a":"quote\" text \\ud800"}' '{"a":"\ud83d\ude00"}' $'{"a":"quote\\\""}\n{"b":"\\\\udc00"}\n\n'; do
 retained=$(printf '%s' "$value" | json_stream_retain_raw && printf '.')
 [[ ${retained%.} == "$value" ]]
 printf '%s' "$value" | json_stream_unique
done
for value in '{"a":"\udc00"}' '{"a":"\uD800"}' '{"a":"\uD800\\udc00"}' '{"a":"\uD800\uD800"}' '{"a":"quote\"\udc00"}' $'{"a":1}\n{"b":"\\udc00"}'; do
 if printf '%s' "$value" | json_stream_retain_raw; then printf 'FAIL: lone surrogate accepted\n' >&2; exit 1; fi
done
# Escapes straddling each byte of a scan-window edge keep the same state.
for offset in 32754 32755 32756 32757 32758 32759 32760 32761 32762 32763 32764 32765 32766 32767 32768; do
 printf -v padding '%*s' "$offset" ''
 for escape in '\ud83d\ude00' '\\udc00' '\"\ud83d\ude00'; do
  value='{"a":"'"${padding}${escape}"'"}'
  retained=$(printf '%s' "$value" | json_stream_retain_raw && printf '.')
  [[ ${retained%.} == "$value" ]]
  printf '%s' "$value" | json_stream_unique
 done
 for escape in '\udc00' '\ud800\\udc00' '\"\udc00'; do
  value='{"a":"'"${padding}${escape}"'"}'
  if printf '%s' "$value" | json_stream_retain_raw; then printf 'FAIL: edge surrogate accepted\n' >&2; exit 1; fi
 done
done
printf 'PASS: unique raw documents and paginated JSON boundaries\n'
