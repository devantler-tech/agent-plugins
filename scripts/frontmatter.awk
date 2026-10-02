# Observe the supported scalar/mapping header shape, never claim full YAML validation.
function trim(s) { sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
function scalar(s, q,i,c,escaped,tail) {
  s=trim(s); scalar_ok=0
  q=substr(s,1,1)
  if (q == "\"" || q == "\047") {
    for (i=2;i<=length(s);i++) {
      c=substr(s,i,1)
      if (q == "\"" && !escaped && c == "\\") { escaped=1; continue }
      if (!escaped && c == q) {
        if (q == "\047" && substr(s,i+1,1) == q) { i++; continue }
        tail=trim(substr(s,i+1))
        if (tail != "" && substr(tail,1,1) != "#") return ""
        s=substr(s,2,i-2); scalar_ok=(trim(s) != ""); return s
      }
      escaped=0
    }
    return ""
  }
  sub(/[[:space:]]+#.*$/,"",s); s=trim(s)
  if (s == "" || substr(s,1,1) == "#" || s ~ /^[\[\{&*!|>]/ ||
      s ~ /^(~|null|Null|NULL|true|True|TRUE|false|False|FALSE)$/ ||
      s ~ /^[-+]?([0-9][0-9_]*(\.[0-9_]*)?|\.[0-9_]+)([eE][-+]?[0-9_]+)?$/ ||
      s ~ /^[-+]?0([xX][0-9a-fA-F_]+|[oO][0-7_]+|[bB][01_]+)$/ ||
      s ~ /^[-+]?\.([iI][nN][fF]|[nN][aA][nN])$/ ||
      s ~ /^[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+(\.[0-9_]*)?$/) return ""
  scalar_ok=1; return s
}
{
  sub(/\r$/,"")
  if (NR == 1) { if ($0 !~ /^---[[:space:]]*$/) bad=1; next }
  if ($0 ~ /^---[[:space:]]*$/) { closed=1; exit }
  if (bad) next
  if (mode == "text" && block && $0 ~ /^[[:space:]]/ && $0 ~ /[^[:space:]]/) found=1
  if ($0 ~ /^[[:space:]]*(#.*)?$/) next
  if ($0 ~ /^[A-Za-z_][A-Za-z0-9_-]*:/) {
    key=$0; sub(/:.*/,"",key)
    if (++keys[key] > 1) bad=1
    block=0; in_metadata=(key == "metadata"); depth=0
    raw=substr($0,length(key)+2)
    if (mode == "text" && key == field) {
      v=trim(raw); sub(/[[:space:]]+#.*$/,"",v)
      if (v ~ /^[|>][0-9+-]*$/) block=1
      else { v=scalar(raw); found=scalar_ok }
    }
    if (mode == "repository" && in_metadata) {
      v=trim(raw); sub(/^#.*/,"",v)
      if (v != "") bad=1
    }
    next
  }
  # Unsupported top-level YAML syntax cannot hide a second effective identity.
  if ($0 !~ /^[[:space:]]/) { bad=1; next }
  if (mode != "repository" || !in_metadata || $0 ~ /^[[:space:]]*(#.*)?$/) next
  if ($0 !~ /^[ ]+[A-Za-z_][A-Za-z0-9_-]*:/) { bad=1; next }
  match($0,/[^ ]/); indent=RSTART-1
  if (!depth) depth=indent
  if (indent < depth) { bad=1; next }
  key=trim($0); sub(/:.*/,"",key)
  if (key != "github-repo") next
  if (indent != depth || ++owners > 1) { bad=1; next }
  raw=$0; sub(/^[ ]+github-repo:[[:space:]]*/,"",raw)
  owner=scalar(raw)
  if (!scalar_ok || owner !~ /^https:\/\/github\.com\/[A-Za-z0-9][A-Za-z0-9-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*$/) bad=1
}
END {
  if (!closed || bad) exit (mode == "repository" ? 2 : 1)
  if (mode == "repository") { if (owners) print owner; exit 0 }
  exit (found ? 0 : 1)
}
