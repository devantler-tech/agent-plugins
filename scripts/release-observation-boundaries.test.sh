#!/usr/bin/env bash
# Real release preparation against malformed original bytes and competing paths.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/json-object.lib.sh
. "$here/json-object.lib.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export REAL_CP REAL_GIT REAL_JQ
REAL_CP=$(command -v cp); REAL_GIT=$(command -v git); REAL_JQ=$(command -v jq)
fresh() {
  repo=$(mktemp -d "$work/repo.XXXXXX")
  "$REAL_GIT" -C "$repo" init -q
  "$REAL_GIT" -C "$repo" config user.name Fixture
  "$REAL_GIT" -C "$repo" config user.email fixture@example.invalid
  "$REAL_GIT" -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/.github/plugin" "$repo/.claude-plugin"
  printf '%s\n' '{"name":"fixture","metadata":{"version":"1.0.0","description":"Kept"},"plugins":[{"name":"example","source":"./plugins/example","version":"1.0.0"}]}' > "$repo/.github/plugin/marketplace.json"
  "$REAL_CP" "$repo/.github/plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  "$REAL_GIT" -C "$repo" add -- .github/plugin/marketplace.json .claude-plugin/marketplace.json
  "$REAL_GIT" -C "$repo" commit -qm 'chore: initial'
  export OUTPUT="$work/out-$RACE_MODE"
}
run() {
  rc=0
  (cd "$repo" && PATH="$work/bin:$PATH" bash "$here/prepare-marketplace-release.sh" --base-tag initial --output "$OUTPUT") > "$work/out" 2> "$work/err" || rc=$?
}
mkdir "$work/bin"
cat > "$work/bin/cp" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == -R ]]; then
  case "$RACE_MODE" in
    redirect|foreign|foreign-fail)
      mv "$OUTPUT" "$OUTPUT.owned"
      if [[ $RACE_MODE == redirect ]]; then ln -s "$SOURCE_REPO" "$OUTPUT"
      else mkdir "$OUTPUT"; printf 'foreign data\n' > "$OUTPUT/other-writer"; fi
      [[ $RACE_MODE != foreign-fail ]] || exit 71 ;;
    copy-fail) "$REAL_CP" "$@"; exit 71 ;;
  esac
  "$REAL_CP" "$@" || exit $?
  case "$RACE_MODE" in
    tampered) printf '{}\n' > ./release.json ;;
    missing) rm ./RELEASE_NOTES.md ;;
  esac
  exit 0
fi
exec "$REAL_CP" "$@"
STUB
cat > "$work/bin/git" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == worktree && $2 == list ]]; then
  case "$RACE_MODE" in
    census-empty) exit 0 ;;
    census-head-only) printf 'HEAD deadbeef\0\0'; exit 0 ;;
    census-incomplete) printf 'worktree %s\0HEAD %s\0' "$SOURCE_REPO" "$("$REAL_GIT" rev-parse HEAD)"; exit 0 ;;
    census-duplicate) "$REAL_GIT" "$@"; "$REAL_GIT" "$@"; exit 0 ;;
  esac
fi
exec "$REAL_GIT" "$@"
STUB
cat > "$work/bin/mkdir" <<'STUB'
#!/usr/bin/env bash
if [[ $RACE_MODE == parent-redirect && $1 == ./candidate ]]; then
  mv "$OUTPUT_PARENT" "$OUTPUT_PARENT.owned"
  ln -s "$SOURCE_REPO/.github" "$OUTPUT_PARENT"
fi
if [[ $RACE_MODE == reservation-foreign && $1 == ./candidate ]]; then
  "$REAL_MKDIR" "$@" || exit $?
  mv ./candidate ./candidate.owned
  "$REAL_MKDIR" ./candidate || exit $?
  printf 'foreign reservation\n' > ./candidate/release.json
  exit 0
fi
exec "$REAL_MKDIR" "$@"
STUB
cat > "$work/bin/jq" <<'STUB'
#!/usr/bin/env bash
if [[ $RACE_MODE == status-fail && $* == *' .status '* ]]; then exit 71; fi
exec "$REAL_JQ" "$@"
STUB
chmod +x "$work/bin/"*
export REAL_MKDIR
REAL_MKDIR=$(command -v mkdir)
for mode in reservation-foreign parent-redirect redirect foreign foreign-fail copy-fail status-fail tampered missing census-empty census-head-only census-incomplete census-duplicate; do
  export RACE_MODE=$mode
  fresh; export SOURCE_REPO=$repo
  if [[ $mode == parent-redirect || $mode == reservation-foreign ]]; then
    export OUTPUT_PARENT="$work/parent-destination-$mode"
    mkdir "$OUTPUT_PARENT"; OUTPUT="$OUTPUT_PARENT/candidate"
  fi
  if [[ $mode == census-* ]]; then OUTPUT="$repo/candidate"; fi
  run
  if [[ $rc == 0 || -s $work/out ]]; then echo "unsafe preparation admitted: $mode" >&2; exit 1; fi
  [[ -z $("$REAL_GIT" -C "$repo" status --porcelain --ignored) ]]
  case "$mode" in
    reservation-foreign) [[ $(cat "$OUTPUT/release.json") == 'foreign reservation' && -d $OUTPUT.owned ]] ;;
    foreign*) [[ $(cat "$OUTPUT/other-writer") == 'foreign data' ]] ;;
    redirect) [[ -L $OUTPUT && -f $OUTPUT.owned/release.json ]] ;;
    parent-redirect) [[ -L $OUTPUT_PARENT && -d $OUTPUT_PARENT.owned/candidate && ! -e $SOURCE_REPO/.github/candidate ]] ;;
    copy-fail) [[ -d $OUTPUT ]] ;; # Explicit recovery retains an entered partial directory.
    census-*) [[ ! -e $OUTPUT ]] ;;
  esac
done
for bytes in 'bad\377text' 'bad\302' '\uDC00' '\uD800' '\uD800x\uDC00'; do
  export RACE_MODE="unicode-$RANDOM"
  fresh
  if [[ $bytes == '\u'* ]]; then value=$bytes; else printf -v value '%b' "$bytes"; fi
  printf '{"name":"fixture","metadata":{"version":"1.0.0","description":"%s"},"plugins":[{"name":"example","source":"./plugins/example","version":"1.0.0"}]}\n' "$value" > "$repo/.github/plugin/marketplace.json"
  "$REAL_CP" "$repo/.github/plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  "$REAL_GIT" -C "$repo" add -- .github/plugin/marketplace.json .claude-plugin/marketplace.json
  "$REAL_GIT" -C "$repo" commit -qm 'fix: invalid original text'
  run
  [[ $rc != 0 && ! -e $OUTPUT && ! -s $work/out ]] || { echo "repaired source admitted: $bytes" >&2; exit 1; }
done
for value in '{"a":"東京 café �"}' '{"a":"\uD83D\uDE80"}' '{"a":"literal \\uDC00"}'; do
  printf '%s' "$value" > "$work/json"
  json_value_unique "$work/json"
done
printf 'release observation boundaries: PASS\n'
