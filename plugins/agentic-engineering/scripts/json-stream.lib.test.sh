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
printf 'PASS: unique raw documents and paginated JSON boundaries\n'
