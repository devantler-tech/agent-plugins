#!/usr/bin/env bash
# Retain producer bytes before Bash command substitution can erase literal NULs
# or jq can repair invalid UTF-8. No temporary response files or compiler.
json_stream_retain_raw() {
 local raw='' converted read_status=0
 local LC_ALL=C
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
 # jq repairs lone surrogate escapes. Refuse those original bytes before an
 # identity can collapse onto a distinct literal replacement character.
 # Byte-by-byte Bash substring expansion stalls on large retained responses. Scan
 # in bounded awk byte arrays instead, retaining quote/escape state across lines.
 # macOS awk substr also walks from the start of its string for each offset;
 # splitting small windows avoids that repeated traversal and bounds array memory.
 # The scan only checks surrogate escapes; jq still owns JSON syntax/uniqueness.
 command -v awk >/dev/null 2>&1 || return 2
 printf '%s' "$raw" | LC_ALL=C awk '
  {
   n=length($0)
   for (start=1; start<=n;) {
    # Eleven lookahead bytes keep a surrogate pair atomic at a window edge.
    split(substr($0,start,32779),bytes,"")
    limit=n-start+1; if (limit>32768) limit=32768
    for (i=1; i<=limit;) {
     char=bytes[i]
     if (!in_string) { if (char=="\"") in_string=1; i++; continue }
     if (char=="\"") { in_string=0; i++; continue }
     if (char!="\\") { i++; continue }
     if (bytes[i+1]!="u") { i+=2; continue }
     hex=bytes[i+2] bytes[i+3] bytes[i+4] bytes[i+5]
     if (hex !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) { i+=2; continue }
     if (hex ~ /^[dD][89AaBb][0-9A-Fa-f][0-9A-Fa-f]$/) {
      low=bytes[i+8] bytes[i+9] bytes[i+10] bytes[i+11]
      if ((bytes[i+6] bytes[i+7])!="\\u" ||
          low !~ /^[dD][cCdDeEfF][0-9A-Fa-f][0-9A-Fa-f]$/) exit 2
      i+=12; continue
     }
     if (hex ~ /^[dD][cCdDeEfF][0-9A-Fa-f][0-9A-Fa-f]$/) exit 2
     i+=6
    }
    start+=i-1
   }
  }
 ' || return 2
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
