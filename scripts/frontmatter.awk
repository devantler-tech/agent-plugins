# Observe the supported scalar/mapping header shape, never claim full YAML validation.
function trim(s) { sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
# Observe literal controls before the scalar decoder can mark them as text.
# Match complete UTF-8 strings: byte ranges inside a regex character class are
# invalid collation characters in GNU awk's UTF-8 locales. Allowed YAML
# whitespace is not a forbidden control.
function forbidden_control(s, t,controls,c1,n,i) {
  t=s; gsub(/[\t\r]/,"",t); gsub("\302\205","",t)
  if (t ~ /[[:cntrl:]]/) return 1
  controls="\302\200 \302\201 \302\202 \302\203 \302\204 " \
    "\302\206 \302\207 \302\210 \302\211 \302\212 \302\213 \302\214 \302\215 \302\216 \302\217 " \
    "\302\220 \302\221 \302\222 \302\223 \302\224 \302\225 \302\226 \302\227 " \
    "\302\230 \302\231 \302\232 \302\233 \302\234 \302\235 \302\236 \302\237"
  n=split(controls,c1," ")
  for (i=1;i<=n;i++) if (index(s,c1[i])) return 1
  return 0
}
# A presence observer, not a general YAML decoder: normalize escaped whitespace,
# decode printable ASCII, and retain valid non-ASCII escapes as nonblank text.
function quoted_text(s,q, i,c,n,hex,j,d,code,out) {
  quoted_ok=0; out=""
  if (q == "\047") { gsub(/\047\047/,"\047",s); quoted_ok=1; return s }
  for (i=1;i<=length(s);i++) {
    c=substr(s,i,1)
    if (c != "\\") { out=out c; continue }
    c=substr(s,++i,1)
    if (c == "\\" || c == "\"" || c == "/") { out=out c; continue }
    if (c ~ /^[0abe]$/) return ""
    if (c ~ /^[tnvfrN_LP ]$/ || c == "\t") { out=out " "; continue }
    if (c != "x" && c != "u" && c != "U") return ""
    n=(c == "x" ? 2 : (c == "u" ? 4 : 8)); hex=substr(s,i+1,n)
    if (length(hex) != n || hex ~ /[^0-9a-fA-F]/) return ""
    code=0
    for (j=1;j<=n;j++) { d=index("0123456789abcdef",tolower(substr(hex,j,1)))-1; code=code*16+d }
    if (code > 1114111 || (code >= 55296 && code <= 57343)) return ""
    if ((code >= 9 && code <= 13) || code == 32 || code == 133 || code == 160 ||
        code == 5760 || (code >= 8192 && code <= 8202) || code == 8232 || code == 8233 ||
        code == 8239 || code == 8287 || code == 12288) out=out " "
    else if (code < 32 || (code >= 127 && code <= 159)) return ""
    else if (code < 127) out=out sprintf("%c",code)
    else out=out "\\" c hex
    i+=n
  }
  quoted_ok=1; return out
}
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
        s=quoted_text(substr(s,2,i-2),q)
        scalar_ok=(quoted_ok && trim(s) != ""); return s
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
  if (forbidden_control($0)) bad=1
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
