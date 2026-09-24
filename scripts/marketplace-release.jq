# Stable marketplace release preparation; the publishing boundary is deliberately absent.
def stable_syntax:
  type == "string" and test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$");
def stable_version: stable_syntax and (split(".") | all(.[]; length <= 9));
def nonblank: type == "string" and test("\\S");
def valid_marketplace:
  type == "object" and (.name | nonblank) and (.metadata.version | stable_version)
  and (.plugins | type == "array" and length > 0
    and (map(.name) | length == (unique | length))
    and all(.[]; (.name | type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$"))
      and (.version | stable_version) and .source == ("./plugins/" + .name)));
def commit_level:
  . as $commit | (.message | split("\n")[0]) as $subject
  | ((try ($subject | capture("^(?<type>[a-z][a-z0-9-]*)(\\([^()\\r\\n]+\\))?(?<breaking>!)?: .+"; "i")) catch null) // null) as $header
  | if $header == null then error("unclassified commit requires review: " + .sha)
    elif ($header.type | ascii_downcase) == "revert" then error("revert requires review: " + .sha)
    elif $header.breaking == "!" or (.message | test("(^|\n)BREAKING( CHANGE|-CHANGE): [^\\s]")) then 3
    elif ($header.type | ascii_downcase) == "feat" then 2
    elif ([$header.type | ascii_downcase] | any(.[]; . == "fix" or . == "perf")) then 1
    else 0 end;
def prepare($source; $base; $baseTag; $current; $commits):
  (if $baseTag == "initial" then 0 else ([$commits[] | commit_level] | max // 0) end) as $level
  | ($current | split(".") | map(tonumber)) as $parts
  | (if $baseTag == "initial" then $current
     elif $level == 3 then [$parts[0]+1,0,0] | join(".")
     elif $level == 2 then [$parts[0],$parts[1]+1,0] | join(".")
     elif $level == 1 then [$parts[0],$parts[1],$parts[2]+1] | join(".")
     else null end) as $version
  | if $version != null and ($version | stable_version | not) then error("version component exceeds supported range") else
    {schemaVersion:1, status:(if $version == null then "NO_RELEASE" else "CANDIDATE" end),
     publication:"NOT_AUTHORIZED", sourceCommit:$source,
     baseline:(if $baseTag == "initial" then null else {tag:$baseTag,commit:$base,version:$current} end),
     version:$version, tag:(if $version == null then null else "v"+$version end),
     releaseType:(if $baseTag == "initial" then "initial" else ["none","patch","minor","major"][$level] end),
     commits:($commits | map({sha,subject:(.message | split("\n")[0])})),
     plugins:(.plugins | map({name,version,source}))} end;
def markdown_text:
  gsub("[[:space:]]+"; " ") | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")
  | gsub("(?<mark>[\\\\`*_{}\\[\\]()!|~#+.=-])"; "\\\(.mark)");
def release_notes:
  ["# Marketplace release preparation", "Status: \(.status)",
   "This is a review artifact. It is not a published release and grants no publication authority.",
   "Source commit: `\(.sourceCommit)`",
   "Baseline: \(if .baseline == null then "initial snapshot" else "`"+.baseline.tag+"` at `"+.baseline.commit+"`" end)",
   "Proposed version: \(.version // "none") (\(.releaseType))",
   "## Changes", (.commits[] | "- \(.subject | markdown_text) (`\(.sha)`)") ,
   "## Plugin inventory", (.plugins[] | "- \(.name | markdown_text): \(.version | markdown_text)"),
   "## Before publication",
   "Refresh remote tags, review the proposed manifests, validate the exact release commit, and follow the reviewed publication procedure. Per-plugin cache versions are independent."
  ] | join("\n\n") + "\n";
