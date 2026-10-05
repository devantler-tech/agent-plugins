#!/usr/bin/env bash
# Observe one complete JSON value without erasing repeated decoded keys.
json_source_retain() {
  local data='' converted status=0 i=0 length in_string=0 char hex low backslash=$'\\'
  local LC_ALL=C
  IFS= read -r -d '' data || status=$?
  [ "$status" = 1 ] && [ -n "$data" ] || return 1
  converted=$(set -o pipefail; printf '%s' "$data" |
    iconv -f UTF-8 -t UTF-16BE | iconv -f UTF-16BE -t UTF-8 &&
    printf '.') 2>/dev/null || return 1
  converted=${converted%.}
  [ "$converted" = "$data" ] || return 1
  length=${#data}
  while ((i < length)); do
    char=${data:i:1}
    if ((in_string == 0)); then
      [[ $char == '"' ]] && in_string=1
      i=$((i + 1)); continue
    fi
    if [[ $char == '"' ]]; then in_string=0; i=$((i + 1)); continue; fi
    if [[ $char != "$backslash" ]]; then i=$((i + 1)); continue; fi
    if [[ ${data:i+1:1} != u ]]; then i=$((i + 2)); continue; fi
    hex=${data:i+2:4}
    if [[ ! $hex =~ ^[0-9A-Fa-f]{4}$ ]]; then i=$((i + 2)); continue; fi
    if [[ $hex =~ ^[dD][89AaBb][0-9A-Fa-f]{2}$ ]]; then
      [[ ${data:i+6:2} == "${backslash}u" ]] || return 1
      low=${data:i+8:4}
      [[ $low =~ ^[dD][cCdDeEfF][0-9A-Fa-f]{2}$ ]] || return 1
      i=$((i + 12)); continue
    fi
    [[ ! $hex =~ ^[dD][cCdDeEfF][0-9A-Fa-f]{2}$ ]] || return 1
    i=$((i + 6))
  done
  printf '%s' "$data"
}

json_unique_data() {
  local data=$1
  printf '%s\n' "$data" | jq -es 'length == 1' >/dev/null 2>&1 &&
    printf '%s\n' "$data" | jq --stream -es '
      reduce .[] as $event ({complete:{}, valid:true};
        if ($event|length)==2 then
          .complete as $complete | $event[0] as $path |
          .valid = (.valid and (any(range(0;($path|length)+1);
            $complete[($path[0:.]|tojson)]==true)|not)) |
          .complete[($path|tojson)] = true
        else .complete[($event[0][0:-1]|tojson)] = true end) | .valid
    ' >/dev/null 2>&1
}

json_value_unique() {
  local data
  data=$(set -o pipefail; cat -- "$1" | json_source_retain) || return 1
  json_unique_data "$data"
}

# Object-only boundaries retain their shape requirement; paginated observations
# use json_value_unique before their own complete-array shape checks.
json_object_unique() {
  local data
  data=$(set -o pipefail; cat -- "$1" | json_source_retain) || return 1
  json_unique_data "$data" &&
    printf '%s\n' "$data" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1
}
