#!/usr/bin/env bash
# Cache versions use the same bounded, canonical stable syntax as marketplace releases.
plugin_version_library_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_version_valid() {
  jq -en -L "$plugin_version_library_dir" --arg v "$1" 'include "marketplace-release"; $v | stable_version' >/dev/null
}
plugin_version_increases() {
  jq -en -L "$plugin_version_library_dir" --arg old "$1" --arg new "$2" '
    include "marketplace-release";
    ($old | stable_version) and ($new | stable_version)
    and (($new | split(".") | map(tonumber)) > ($old | split(".") | map(tonumber)))' >/dev/null
}
plugin_version_next() {
  jq -ern -L "$plugin_version_library_dir" --arg v "$1" --arg level "$2" '
    include "marketplace-release";
    if ($v | stable_version | not) then error("invalid cache version") else
      ($v | split(".") | map(tonumber)) as $p
      | (if $level == "major" then [$p[0]+1,0,0]
         elif $level == "minor" then [$p[0],$p[1]+1,0]
         elif $level == "patch" then [$p[0],$p[1],$p[2]+1]
         else error("unknown bump level") end | join(".")) as $next
      | if ($next | stable_version) then $next else error("cache version exceeds supported range") end
    end'
}
