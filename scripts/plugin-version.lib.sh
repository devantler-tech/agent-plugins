#!/usr/bin/env bash
# Cache versions use the same bounded, canonical stable syntax as marketplace releases.
plugin_version_library_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_version_git_context() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE
  export GIT_NO_REPLACE_OBJECTS=1 GIT_NO_LAZY_FETCH=1
}
plugin_version_history() {
  local shallow grafts
  shallow=$(git rev-parse --is-shallow-repository) || return 1
  [ "$shallow" = false ] || { echo '::error::Complete Git history is required.' >&2; return 1; }
  grafts=$(git rev-parse --git-path info/grafts) || return 1
  if [ -z "$grafts" ] || [ -s "$grafts" ]; then
    echo '::error::Grafted history is unsupported.' >&2; return 1
  fi
  # shellcheck source=scripts/complete-clone.lib.sh
  . "$plugin_version_library_dir/complete-clone.lib.sh"
  assert_complete_clone_config
}
plugin_version_read() {
  local file=$1 name=$2
  if ! jq -es -L "$plugin_version_library_dir" --arg n "$name" '
    include "marketplace-release";
    length == 1 and (.[0] | type == "object" and .name == $n and (.version | stable_version))
  ' "$file" >/dev/null ||
     ! jq --stream -se '[.[] | select(length == 2 and (.[0] == ["version"] or .[0] == ["name"]))]
    | (map(select(.[0] == ["version"])) | length == 1)
      and (map(select(.[0] == ["name"])) | length == 1)' "$file" >/dev/null; then
    echo '::error::Cache version must increase from an unambiguous canonical manifest.' >&2
    return 1
  fi
  jq -er '.version' "$file"
}
plugin_version_local_parents() {
  local name=$1 directory
  for directory in plugins "plugins/$name" "plugins/$name/.claude-plugin"; do
    if [ ! -d "$directory" ] || [ -L "$directory" ]; then
      echo '::error::Manifest parent must be a real checkout directory.' >&2; return 1
    fi
  done
}
plugin_version_at() {
  local commit=$1 name=$2 path="plugins/$2/.claude-plugin/plugin.json" entry file status=0
  entry=$(git ls-tree "$commit" -- "$path") || return 1
  [[ "$entry" == '100644 blob '* || "$entry" == '100755 blob '* ]] || {
    echo '::error::Version manifest is not a regular committed file.' >&2; return 1;
  }
  file=$(mktemp) || return 1
  if git cat-file blob "$commit:$path" > "$file"; then
    plugin_version_read "$file" "$name" || status=$?
  else
    echo '::error::Version manifest could not be read.' >&2; status=1
  fi
  rm -f "$file"
  return "$status"
}
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
