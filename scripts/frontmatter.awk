# Observe the supported scalar/mapping header shape, never claim full YAML validation.
function trim(s) { sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
# YAML separation uses ASCII spaces and tabs; Unicode spaces are scalar content.
function yaml_trim(s) { sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
# Normalize the same Unicode whitespace observed in escaped scalars for presence
# only. Preserve the original scalar for provenance; use complete UTF-8 strings
# so the C and UTF-8 locales agree without partial-byte regex ranges.
function nonblank_text(s,spaces,blanks,n,i) {
  spaces="\302\205 \302\240 \341\232\200 " \
    "\342\200\200 \342\200\201 \342\200\202 \342\200\203 \342\200\204 \342\200\205 " \
    "\342\200\206 \342\200\207 \342\200\210 \342\200\211 \342\200\212 \342\200\213 " \
    "\342\200\250 \342\200\251 \342\200\257 \342\201\237 \343\200\200"
  n=split(spaces,blanks,"[ ]")
  for (i=1;i<=n;i++) gsub(blanks[i]," ",s)
  return trim(s) != ""
}
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
        code == 8203 || code == 8239 || code == 8287 || code == 12288) out=out " "
    else if (code < 32 || (code >= 127 && code <= 159)) return ""
    else if (code < 127) out=out sprintf("%c",code)
    else out=out "\\" c hex
    i+=n
  }
  quoted_ok=1; return out
}
function scalar(s, q,i,c,escaped,tail) {
  s=yaml_trim(s); scalar_ok=0
  q=substr(s,1,1)
  if (q == "\"" || q == "\047") {
    for (i=2;i<=length(s);i++) {
      c=substr(s,i,1)
      if (q == "\"" && !escaped && c == "\\") { escaped=1; continue }
      if (!escaped && c == q) {
        if (q == "\047" && substr(s,i+1,1) == q) { i++; continue }
        tail=yaml_trim(substr(s,i+1))
        if (tail != "" && substr(tail,1,1) != "#") return ""
        s=quoted_text(substr(s,2,i-2),q)
        scalar_ok=(quoted_ok && nonblank_text(s)); return s
      }
      escaped=0
    }
    return ""
  }
  sub(/[ \t]+#.*$/,"",s); s=yaml_trim(s)
  # A plain scalar cannot start with a reserved indicator, contain a mapping
  # separator, or turn its first token into a sequence/mapping declaration.
  # The same punctuation remains valid inside supported quoted scalars.
  if (s == "" || s ~ /^[\[\]\{\},#&*!|>%@`]/ ||
      s ~ /^[-?:]([ \t]|$)/ || s ~ /:([ \t]|$)/ ||
      s ~ /^(~|null|Null|NULL|true|True|TRUE|false|False|FALSE)$/ ||
      s ~ /^[-+]?([0-9][0-9_]*(\.[0-9_]*)?|\.[0-9_]+)([eE][-+]?[0-9_]+)?$/ ||
      s ~ /^[-+]?0([xX][0-9a-fA-F_]+|[oO][0-7_]+|[bB][01_]+)$/ ||
      s ~ /^[-+]?\.([iI][nN][fF]|[nN][aA][nN])$/ ||
      s ~ /^[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+(\.[0-9_]*)?$/) return ""
  scalar_ok=nonblank_text(s); return s
}
{
  sub(/\r$/,"")
  if (forbidden_control($0)) bad=1
  if (NR == 1) { if ($0 !~ /^---[[:space:]]*$/) bad=1; next }
  if ($0 ~ /^---[[:space:]]*$/) { closed=1; exit }
  if (bad) next
  if (mode == "text" && block) {
    indent=length($0)
    if (match($0,/[^ ]/)) indent=RSTART-1
    rest=substr($0,indent+1)
    blank_line=($0 ~ /^[ \t]*$/)
    # A dedented comment ends the scalar. Later indented text cannot resume it
    # before a new top-level key supplies another mapping or scalar context.
    if ((!blank_line && indent == 0) ||
        (rest ~ /^#/ && indent < (block_indent ? block_indent : 1))) {
      block=0; after_block=1
    } else if (blank_line && rest == "") {
      if (!block_indent && indent > block_blank_indent) block_blank_indent=indent
    } else {
      # Tabs may be scalar content only after an explicit or inferred indentation
      # is established; they cannot establish the first line's indentation.
      if (!block_indent && rest ~ /^\t/) bad=1
      if (!block_indent) {
        block_indent=indent
        if (block_blank_indent > indent) bad=1
      }
      if (indent < 1 || indent < block_indent) bad=1
      else if (nonblank_text($0)) found=1
    }
  }
  if (after_block && $0 !~ /^[ \t]*(#.*)?$/ && $0 !~ /^[A-Za-z_][A-Za-z0-9_-]*:/) bad=1
  if ($0 ~ /^[[:space:]]*(#.*)?$/) next
  if ($0 ~ /^[A-Za-z_][A-Za-z0-9_-]*:/) {
    key=$0; sub(/:.*/,"",key)
    if (++keys[key] > 1) bad=1
    block=0; block_indent=0; block_blank_indent=0; after_block=0
    in_metadata=(key == "metadata"); depth=0
    raw=substr($0,length(key)+2)
    if (mode == "text" && key == field) {
      v=yaml_trim(raw); sub(/[ \t]+#.*$/,"",v)
      # YAML permits one nonzero indentation digit and one chomping indicator
      # in either order. An omitted digit is inferred from the first text line.
      if (v ~ /^[|>]([1-9][+-]?|[+-][1-9]?)?$/) {
        block=1
        if (match(v,/[1-9]/)) block_indent=substr(v,RSTART,1)+0
      }
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
