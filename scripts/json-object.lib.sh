#!/usr/bin/env bash
# Observe one complete JSON value without erasing repeated decoded keys.
json_value_unique() {
  local file=$1
  jq -es 'length == 1' "$file" >/dev/null 2>&1 &&
    jq --stream -es '
      reduce .[] as $event ({complete:{}, valid:true};
        if ($event|length)==2 then
          .complete as $complete | $event[0] as $path |
          .valid = (.valid and (any(range(0;($path|length)+1);
            $complete[($path[0:.]|tojson)]==true)|not)) |
          .complete[($path|tojson)] = true
        else .complete[($event[0][0:-1]|tojson)] = true end) | .valid
    ' "$file" >/dev/null 2>&1
}

# Object-only boundaries retain their shape requirement; paginated observations
# use json_value_unique before their own complete-array shape checks.
json_object_unique() {
  local file=$1
  jq -es 'length == 1 and (.[0] | type == "object")' "$file" >/dev/null 2>&1 &&
    json_value_unique "$file"
}
