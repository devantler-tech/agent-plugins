#!/usr/bin/env bash
# Self-test for skill-spec-view.sh: the spec view drops exactly the Claude Code and VS Code
# `argument-hint` and `user-invocable` frontmatter fields and keeps every other byte, so the
# Agent Skills spec still judges everything else about the skill.
# Frontmatter fragments below are matched literally.
# shellcheck disable=SC2016
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
view=$here/skill-spec-view.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

skill() { # name, then SKILL.md lines
  local dir=$work/src/$1; shift
  rm -rf "$dir"; mkdir -p "$dir/references"
  printf '%s\n' "$@" > "$dir/SKILL.md"
  printf 'reference\n' > "$dir/references/extra.md"
  printf '%s\n' "$dir"
}

expect_view() { # description, source dir, expected SKILL.md lines...
  local description=$1 src=$2 out status=0; shift 2
  rm -rf "$work/out"
  out=$(bash "$view" "$src" "$work/out" 2>"$work/err") || status=$?
  if [ "$status" -ne 0 ]; then fail "$description (exit $status: $(cat "$work/err"))"; return; fi
  if [ "$out" != "$work/out/$(basename "$src")" ]; then fail "$description (printed $out)"; return; fi
  printf '%s\n' "$@" > "$work/expected"
  if ! cmp -s "$work/expected" "$out/SKILL.md"; then
    fail "$description (SKILL.md differs)"; diff "$work/expected" "$out/SKILL.md" >&2 || true; return
  fi
  if ! cmp -s "$src/references/extra.md" "$out/references/extra.md"; then
    fail "$description (supporting file not copied)"; return
  fi
  pass "$description"
}

expect_refused() { # description, expected status, source dir
  local status=0
  rm -rf "$work/out"
  bash "$view" "$3" "$work/out" > "$work/stdout" 2>"$work/err" || status=$?
  if [ "$status" -ne "$2" ]; then fail "$1 (exit $status, want $2)"; return; fi
  if [ -s "$work/stdout" ]; then fail "$1 (printed a path on refusal)"; return; fi
  pass "$1"
}

src=$(skill both '---' 'name: both' 'description: Fixture.' 'argument-hint: "<file>"' 'user-invocable: false' 'metadata:' '    github-repo: https://github.com/example/skills' '---' '# both' 'argument-hint: stays in the body')
expect_view 'both Claude Code fields are dropped and nothing else changes' "$src" \
  '---' 'name: both' 'description: Fixture.' 'metadata:' '    github-repo: https://github.com/example/skills' '---' '# both' 'argument-hint: stays in the body'
if [ "$(grep -c 'argument-hint' "$src/SKILL.md")" -eq 2 ]; then pass 'the source skill is left untouched'; else fail 'the source skill was modified'; fi

src=$(skill plain '---' 'name: plain' 'description: Fixture.' '---' '# plain')
expect_view 'a skill without the fields is copied unchanged' "$src" '---' 'name: plain' 'description: Fixture.' '---' '# plain'

src=$(skill nested '---' 'name: nested' 'description: Fixture.' 'metadata:' '    argument-hint: nested' '---' '# nested')
expect_view 'an indented key of the same name is not touched' "$src" \
  '---' 'name: nested' 'description: Fixture.' 'metadata:' '    argument-hint: nested' '---' '# nested'

src=$(skill other '---' 'name: other' 'description: Fixture.' 'disable-model-invocation: true' '---' '# other')
expect_view 'any other non-spec field is kept for the spec to judge' "$src" \
  '---' 'name: other' 'description: Fixture.' 'disable-model-invocation: true' '---' '# other'

src=$(skill block '---' 'name: block' 'description: Fixture.' 'argument-hint: |' '  multi' '---' '# block')
expect_refused 'a block value is refused instead of half-stripped' 1 "$src"

src=$(skill continued '---' 'name: continued' 'description: Fixture.' 'argument-hint: one' '  two' '---' '# continued')
expect_refused 'an indented continuation line is refused' 1 "$src"

src=$(skill empty '---' 'name: empty' 'description: Fixture.' 'argument-hint:' '  - a' '---' '# empty')
expect_refused 'an empty value introducing a nested node is refused' 1 "$src"

src=$(skill twice '---' 'name: twice' 'description: Fixture.' 'user-invocable: true' 'user-invocable: false' '---' '# twice')
expect_refused 'a repeated field is refused' 1 "$src"

# A dropped value must not leave part of itself behind for the validator to read as something else.
src=$(skill blankcont '---' 'name: blankcont' 'description:' 'argument-hint: one' '' '  Text.' '---' '# blankcont')
expect_refused 'a continuation after a blank line is refused' 1 "$src"

src=$(skill commentcont '---' 'name: commentcont' 'description: Fixture.' 'argument-hint: one' '# note' '  more' '---' '# commentcont')
expect_refused 'a continuation after a comment line is refused' 1 "$src"

src=$(skill openquote '---' 'name: openquote' 'argument-hint: "a' 'description: only in view' '---' '# openquote')
expect_refused 'a quoted value that runs onto the next line is refused' 1 "$src"

src=$(skill unclosed1 '---' 'name: unclosed1' 'description: Fixture.' 'argument-hint: "<file>' '---' '# unclosed1')
expect_refused 'an unclosed double-quoted value is refused' 1 "$src"

src=$(skill flow '---' 'name: flow' 'description: Fixture.' 'argument-hint: [a, b]' '---' '# flow')
expect_refused 'a flow value is refused' 1 "$src"

src=$(skill anchor '---' 'name: anchor' 'description: Fixture.' 'argument-hint: &x y' '---' '# anchor')
expect_refused 'an anchored value is refused' 1 "$src"

src=$(skill commentonly '---' 'name: commentonly' 'description: Fixture.' 'argument-hint: # c' '---' '# commentonly')
expect_refused 'a value that is only a comment is refused' 1 "$src"

src=$(skill quoted '---' 'name: quoted' 'description: Fixture.' "argument-hint: 'it''s <file>' # hint" 'user-invocable: "false"' '---' '# quoted')
expect_view 'closed single- and double-quoted values are dropped' "$src" '---' 'name: quoted' 'description: Fixture.' '---' '# quoted'

src=$(skill nospace '---' 'name: nospace' 'description: Fixture.' 'user-invocable:false' '---' '# nospace')
expect_view 'a key without a space after its colon is not a field to drop' "$src" \
  '---' 'name: nospace' 'description: Fixture.' 'user-invocable:false' '---' '# nospace'

src=$(skill unclosed '---' 'name: unclosed' 'description: Fixture.' 'argument-hint: x')
expect_refused 'unterminated frontmatter is refused' 1 "$src"

src=$(skill nofront 'name: nofront' 'argument-hint: x')
expect_refused 'a file without frontmatter is refused' 1 "$src"

mkdir -p "$work/src/missing"
expect_refused 'a directory without SKILL.md is refused' 2 "$work/src/missing"
expect_refused 'a missing argument is refused' 2 ""

src=$(skill exists '---' 'name: exists' 'description: Fixture.' '---' '# exists')
mkdir -p "$work/out/exists"
status=0; bash "$view" "$src" "$work/out" > /dev/null 2>&1 || status=$?
if [ "$status" -eq 2 ]; then pass 'an existing destination is never overwritten'; else fail "an existing destination was reused (exit $status)"; fi

if [ "$failures" -ne 0 ]; then
  echo "skill-spec-view self-test: $failures failure(s)" >&2
  exit 1
fi
echo 'skill-spec-view self-test passed'
