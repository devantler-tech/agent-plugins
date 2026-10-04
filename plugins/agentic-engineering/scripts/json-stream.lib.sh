#!/usr/bin/env bash
# Observe raw paginated JSON before semantic parsing can erase repeated decoded keys.
json_stream_unique() {
 jq --stream -es '
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
