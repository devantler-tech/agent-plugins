#!/usr/bin/env bash
# Self-test for check-skill-authoring.sh: run the real check against fixture repositories and
# assert its exit status and the message that names the broken rule.
# Markdown and YAML fragments below are matched and written literally.
# shellcheck disable=SC2016
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
ours=plugins/alpha/skills/ours
record=scripts/skill-authoring-exceptions.json

# Write the exception record of a fixture: limit, description exceptions, reference exceptions.
exceptions() { # root limit description-exceptions-json reference-exceptions-json
  printf '{"description":{"limit":%s,"exceptions":%s},"references":{"exceptions":%s}}\n' \
    "$2" "$3" "$4" > "$1/$record"
}

# Write the first-party skill's entry file with a given description line and body.
entry() { # root description-yaml body
  printf -- '---\nname: ours\n%s\n---\n# ours\n\n%s\n' "$2" "$3" > "$1/$ours/SKILL.md"
}

# A consistent repository. The first-party skill links its one reference, which links its
# worked example. The external skill breaks every rule, and must not be judged.
fixture() {
  local root=$work/$1
  mkdir -p "$root/scripts" "$root/$ours/references" "$root/plugins/alpha/skills/theirs/references/deep"
  exceptions "$root" 60 '[]' '[]'
  entry "$root" 'description: Fixture skill for the authoring check.' 'Read [the guide](references/guide.md).'
  printf '# Guide\n\nSee [the example](example.json).\n' > "$root/$ours/references/guide.md"
  printf '{}\n' > "$root/$ours/references/example.json"
  {
    printf -- '---\nname: theirs\ndescription: %s\n' "$(printf 'x%.0s' $(seq 1 200))"
    printf 'metadata:\n  github-repo: https://github.com/example/skills\n---\n# theirs\n'
  } > "$root/plugins/alpha/skills/theirs/SKILL.md"
  printf 'Unlinked and nested.\n' > "$root/plugins/alpha/skills/theirs/references/deep/note.md"
  printf '%s\n' "$root"
}

# Run the real check in a fixture and compare its exit status and messages.
expect() { # label expected-exit root [message...]
  local label=$1 want=$2 root=$3 rc=0 message
  shift 3
  (cd "$root" && bash "$here/check-skill-authoring.sh") > "$work/out" 2>&1 || rc=$?
  if [ "$rc" -ne "$want" ]; then
    echo "FAIL $label: expected exit $want, got $rc"
    sed 's/^/    /' "$work/out"
    failures=$((failures + 1))
    return 0
  fi
  for message in "$@"; do
    if ! grep -Fq -- "$message" "$work/out"; then
      echo "FAIL $label: the output lacks: $message"
      sed 's/^/    /' "$work/out"
      failures=$((failures + 1))
      return 0
    fi
  done
  echo "PASS $label"
}

repeat() { # text count
  local out='' i
  for ((i = 0; i < $2; i++)); do out+=$1; done
  printf '%s' "$out"
}

# --- the consistent fixture, and what is out of scope ---
root=$(fixture consistent)
expect 'a consistent repository passes and reports the measured length' 0 "$root" \
  "  38 characters  $ours" '1 first-party skills follow the authoring rules'
if grep -Fq 'theirs' "$work/out"; then
  echo 'FAIL an external skill was judged'
  failures=$((failures + 1))
else
  echo 'PASS an external skill is not judged'
fi

# --- references sit one level deep ---
root=$(fixture nested)
mkdir -p "$root/$ours/references/deep"
printf 'Nested.\n' > "$root/$ours/references/deep/note.md"
entry "$root" 'description: Fixture skill.' 'Read [the guide](references/guide.md) and [a note](references/deep/note.md).'
expect 'a nested reference fails even when linked' 1 "$root" \
  "file=$ours/references/deep/note.md::references sit one level deep"

# --- every Markdown reference is linked from the entry file ---
root=$(fixture orphan)
printf 'Nobody links this.\n' > "$root/$ours/references/orphan.md"
expect 'an unlinked Markdown reference fails' 1 "$root" \
  "file=$ours/references/orphan.md::this reference is not linked from SKILL.md"

root=$(fixture chained)
printf '# Guide\n\nSee [the example](example.json) and [more](more.md).\n' > "$root/$ours/references/guide.md"
printf 'Reached only through the guide.\n' > "$root/$ours/references/more.md"
expect 'a Markdown reference reached only through another reference fails' 1 "$root" \
  "file=$ours/references/more.md::this reference is not linked from SKILL.md"
exceptions "$root" 60 '[]' "[{\"file\":\"$ours/references/more.md\",\"reason\":\"Fixture reason.\"}]"
expect 'a recorded exception admits a chained Markdown reference' 0 "$root"

root=$(fixture fenced)
entry "$root" 'description: Fixture skill.' '```
Read [the guide](references/guide.md).
```'
expect 'a link inside a fenced code block is not a link' 1 "$root" \
  "file=$ours/references/guide.md::this reference is not linked from SKILL.md"

root=$(fixture fragment)
entry "$root" 'description: Fixture skill.' 'Read [the guide](./references/guide.md#part "Title").'
expect 'a ./ prefix, a fragment and a title still link the reference' 0 "$root"

root=$(fixture definition)
entry "$root" 'description: Fixture skill.' 'Read [the guide][guide].

[guide]: references/guide.md'
expect 'a link definition links the reference' 0 "$root"

root=$(fixture mention)
entry "$root" 'description: Fixture skill.' 'Read `references/guide.md`.'
expect 'a mention without a link fails' 1 "$root" \
  "file=$ours/references/guide.md::this reference is not linked from SKILL.md"

# --- a worked example belongs to the entry file or to a Markdown reference ---
root=$(fixture stray)
printf '{}\n' > "$root/$ours/references/stray.json"
expect 'a data file linked from nowhere fails' 1 "$root" \
  "file=$ours/references/stray.json::this file is not linked from SKILL.md or from a Markdown file"
exceptions "$root" 60 '[]' "[{\"file\":\"$ours/references/stray.json\",\"reason\":\"Fixture reason.\"}]"
expect 'an exception cannot admit a data file linked from nowhere' 1 "$root" \
  "file=$ours/references/stray.json::this file is not linked"

root=$(fixture entry-example)
printf '# Guide\n\nNo example here.\n' > "$root/$ours/references/guide.md"
entry "$root" 'description: Fixture skill.' 'Read [the guide](references/guide.md) and [the example](references/example.json).'
expect 'a data file linked from the entry file passes' 0 "$root"

# --- only regular files ---
root=$(fixture link)
ln -s guide.md "$root/$ours/references/alias.md"
expect 'a symbolic link among the references fails' 1 "$root" \
  "file=$ours/references/alias.md::a reference must be a regular file, not a link"

root=$(fixture linked-folder)
mv "$root/$ours/references" "$root/$ours/elsewhere"
ln -s elsewhere "$root/$ours/references"
expect 'a references folder that is a link fails' 1 "$root" \
  "file=$ours/references::references must be a real directory"

# --- stale reference exceptions ---
root=$(fixture stale-linked)
exceptions "$root" 60 '[]' "[{\"file\":\"$ours/references/guide.md\",\"reason\":\"Fixture reason.\"}]"
expect 'an exception for a reference that is linked fails as stale' 1 "$root" \
  "$ours/references/guide.md is now linked from SKILL.md; remove its exception"

root=$(fixture stale-missing)
exceptions "$root" 60 '[]' "[{\"file\":\"$ours/references/gone.md\",\"reason\":\"Fixture reason.\"}]"
expect 'an exception for a missing reference fails as stale' 1 "$root" \
  "$ours/references/gone.md: the reference exception names no reference of a first-party skill"

# --- description length, in characters ---
root=$(fixture at-limit)
entry "$root" "description: $(repeat a 60)" 'Read [the guide](references/guide.md).'
expect 'a description at the limit passes' 0 "$root" "  60 characters  $ours"

root=$(fixture over-limit)
entry "$root" "description: $(repeat a 61)" 'Read [the guide](references/guide.md).'
expect 'a description over the limit fails' 1 "$root" \
  "file=$ours/SKILL.md::the description is 61 characters; the limit for a first-party skill is 60"

root=$(fixture multibyte)
entry "$root" "description: $(repeat é 60)" 'Read [the guide](references/guide.md).'
expect 'characters are counted, not bytes' 0 "$root" "  60 characters  $ours"
entry "$root" "description: $(repeat é 61)" 'Read [the guide](references/guide.md).'
expect 'a multi-byte description over the limit fails' 1 "$root" 'the description is 61 characters'

root=$(fixture folded)
entry "$root" 'description: >-
  line one
  line two' 'Read [the guide](references/guide.md).'
expect 'a folded description is measured as the text a host reads' 0 "$root" "  17 characters  $ours"

root=$(fixture no-description)
printf -- '---\nname: ours\n---\n# ours\n\nRead [the guide](references/guide.md).\n' > "$root/$ours/SKILL.md"
expect 'a description that cannot be read fails' 1 "$root" \
  "file=$ours/SKILL.md::the description could not be read as text"

# --- description exceptions are a ratchet ---
root=$(fixture ceiling)
entry "$root" "description: $(repeat a 70)" 'Read [the guide](references/guide.md).'
exceptions "$root" 60 "[{\"skill\":\"$ours\",\"ceiling\":70,\"reason\":\"Fixture reason.\"}]" '[]'
expect 'a recorded ceiling equal to the measured length passes' 0 "$root"
exceptions "$root" 60 "[{\"skill\":\"$ours\",\"ceiling\":80,\"reason\":\"Fixture reason.\"}]" '[]'
expect 'a ceiling above the measured length fails as stale' 1 "$root" \
  "$ours: the description is now 70 characters; lower its recorded ceiling from 80 to 70"
exceptions "$root" 60 "[{\"skill\":\"$ours\",\"ceiling\":65,\"reason\":\"Fixture reason.\"}]" '[]'
expect 'a description above its ceiling fails' 1 "$root" \
  "file=$ours/SKILL.md::the description is 70 characters; its recorded exception allows 65"
entry "$root" "description: $(repeat a 50)" 'Read [the guide](references/guide.md).'
expect 'an exception for a description inside the limit fails as stale' 1 "$root" \
  "$ours: the description is now 50 characters, within the limit of 60; remove its exception"

root=$(fixture ceiling-missing)
exceptions "$root" 60 '[{"skill":"plugins/alpha/skills/gone","ceiling":70,"reason":"Fixture reason."}]' '[]'
expect 'an exception for a missing skill fails as stale' 1 "$root" \
  'plugins/alpha/skills/gone: the description exception names no first-party skill'

root=$(fixture ceiling-external)
exceptions "$root" 60 '[{"skill":"plugins/alpha/skills/theirs","ceiling":200,"reason":"Fixture reason."}]' '[]'
expect 'an exception cannot name an external skill' 1 "$root" \
  'plugins/alpha/skills/theirs: the description exception names no first-party skill'

# --- a skill that cannot be classified is never skipped ---
root=$(fixture unclassified)
printf -- '---\nname: ours\ndescription: Partial install.\nmetadata:\n  github-path: skills/ours\n---\nBody.\n' \
  > "$root/$ours/SKILL.md"
expect 'a skill with partial install provenance fails' 1 "$root" \
  "file=$ours/SKILL.md::the skill cannot be classified as first-party or external"

# --- an unusable setup is never a pass ---
root=$(fixture bad-record)
printf '{}\n' > "$root/$record"
expect 'an empty exception record is refused' 2 "$root" 'does not have the expected shape'
printf '{"description":{"limit":0,"exceptions":[]},"references":{"exceptions":[]}}\n' > "$root/$record"
expect 'a limit of zero is refused' 2 "$root" 'does not have the expected shape'
exceptions "$root" 60 "[{\"skill\":\"$ours\",\"ceiling\":60,\"reason\":\"Fixture reason.\"}]" '[]'
expect 'a ceiling that is not above the limit is refused' 2 "$root" 'does not have the expected shape'
exceptions "$root" 60 "[{\"skill\":\"$ours\",\"ceiling\":70,\"reason\":\" \"}]" '[]'
expect 'an exception without a reason is refused' 2 "$root" 'does not have the expected shape'
exceptions "$root" 60 "[{\"skill\":\"$ours\",\"ceiling\":70,\"reason\":\"One.\"},{\"skill\":\"$ours\",\"ceiling\":80,\"reason\":\"Two.\"}]" '[]'
expect 'a skill recorded twice is refused' 2 "$root" 'does not have the expected shape'
printf '{"description":{"limit":60,"exceptions":[]},"references":{"exceptions":[]},"extra":true}\n' > "$root/$record"
expect 'an unknown key is refused' 2 "$root" 'does not have the expected shape'
rm "$root/$record"
expect 'a missing exception record is refused' 2 "$root" "$record is missing"

root=$(fixture no-plugins)
rm -rf "$root/plugins"
expect 'a directory without plugins is refused' 2 "$root" 'no plugins directory here'

root=$(fixture other-yq)
mkdir "$work/stub"
printf '#!/bin/sh\necho "yq 3.4.3"\n' > "$work/stub/yq"
chmod +x "$work/stub/yq"
rc=0
(cd "$root" && PATH="$work/stub:$PATH" bash "$here/check-skill-authoring.sh") > "$work/out" 2>&1 || rc=$?
if [ "$rc" -eq 2 ] && grep -Fq 'the Go yq' "$work/out"; then
  echo 'PASS another yq is refused'
else
  echo "FAIL another yq was not refused (exit $rc)"
  failures=$((failures + 1))
fi

rc=0
(cd "$root" && bash "$here/check-skill-authoring.sh" --anything) > "$work/out" 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  echo 'PASS an argument is refused'
else
  echo "FAIL an argument was not refused (exit $rc)"
  failures=$((failures + 1))
fi

# --- this repository ---
expect 'this repository passes with its recorded exceptions' 0 "$here/.." 'first-party skills follow the authoring rules'

# Without its exceptions the same tree must fail on exactly the recorded places, which proves
# the check reads the real skills and that no exception is recorded without need.
copy=$work/repository
mkdir -p "$copy/scripts"
cp -R "$here/../plugins" "$copy/plugins"
limit=$(jq -r '.description.limit' "$here/../$record")
exceptions "$copy" "$limit" '[]' '[]'
rc=0
(cd "$copy" && bash "$here/check-skill-authoring.sh") > "$work/out" 2>&1 || rc=$?
recorded=$(jq -r '[.description.exceptions[], .references.exceptions[]] | length' "$here/../$record")
reported=$(grep -c '^::error' "$work/out" || true)
if [ "$rc" -eq 1 ] && [ "$reported" -eq "$recorded" ]; then
  echo "PASS without its exceptions this repository fails in exactly the $recorded recorded places"
elif [ "$recorded" -eq 0 ] && [ "$rc" -eq 0 ]; then
  echo 'PASS this repository needs no exceptions'
else
  echo "FAIL without its exceptions this repository reported $reported errors for $recorded recorded exceptions (exit $rc)"
  sed 's/^/    /' "$work/out"
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "FAIL: $failures case(s) failed"
  exit 1
fi
echo 'PASS: the first-party skill authoring check holds every rule and refuses every unusable setup'
