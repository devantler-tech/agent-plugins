#!/usr/bin/env bash
# Retain producer bytes before Bash command substitution can erase literal NULs
# or jq can repair invalid UTF-8. No temporary response files or compiler.
json_stream_retain_raw() {
 local raw='' converted read_status=0
 IFS= read -r -d '' raw || read_status=$?
 # read succeeds only when its NUL delimiter was encountered. EOF is status 1.
 [ "$read_status" = 1 ] && [ -n "$raw" ] || return 2
 command -v iconv >/dev/null 2>&1 || return 2
 # Some iconv versions repair malformed characters yet return success. A bounded
 # UTF-16 round trip must preserve every original byte, including trailing LFs.
 converted=$(set -o pipefail; printf '%s' "$raw" |
   iconv -f UTF-8 -t UTF-16BE | iconv -f UTF-16BE -t UTF-8 &&
   printf '.') 2>/dev/null || return 2
 converted=${converted%.}
 [ "$converted" = "$raw" ] || return 2
 printf '%s' "$raw"
}

# Observe raw paginated JSON before semantic parsing can erase repeated decoded keys.
# An internal final separator makes jq produce one verdict even at scalar EOF.
json_stream_unique() {
 local raw
 raw=$(json_stream_retain_raw) || return 2
 printf '%s\n' "$raw" | jq --stream -es '
  if length==0 then false else
  reduce .[] as $event ({complete:{}, valid:true};
   (if .complete["[]"]==true then .complete={} else . end) |
   if ($event|length)==2 then
    .complete as $complete | $event[0] as $path |
    .valid = (.valid and (any(range(0;($path|length)+1);
      $complete[($path[0:.]|tojson)]==true)|not)) |
    .complete[($path|tojson)] = true
   else .complete[($event[0][0:-1]|tojson)] = true end
  ) | .valid end
 ' >/dev/null 2>&1
}
