#!/usr/bin/env bash
# Observe actual Git trees and license bytes; stub only the public fetch transport.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
export FIXTURE_REAL_GIT=$real_git FIXTURE_UPSTREAM=$work/upstream
mkdir -p "$work/bin" "$work/plugin/skills/codebase-design" "$work/plugin/resources"
"$real_git" init -q "$FIXTURE_UPSTREAM"
"$real_git" -C "$FIXTURE_UPSTREAM" config user.name Fixture
"$real_git" -C "$FIXTURE_UPSTREAM" config user.email fixture@example.invalid
mkdir -p "$FIXTURE_UPSTREAM/skills/engineering/codebase-design"
printf 'Approved skill body\n' > "$FIXTURE_UPSTREAM/skills/engineering/codebase-design/SKILL.md"
printf 'Copyright fixture. MIT permission notice.\n' > "$FIXTURE_UPSTREAM/LICENSE"
"$real_git" -C "$FIXTURE_UPSTREAM" add -- LICENSE skills/engineering/codebase-design/SKILL.md
"$real_git" -C "$FIXTURE_UPSTREAM" -c commit.gpgsign=false commit -qm 'test: approved snapshot'
revision=$("$real_git" -C "$FIXTURE_UPSTREAM" rev-parse HEAD)
tree=$("$real_git" -C "$FIXTURE_UPSTREAM" rev-parse HEAD:skills/engineering/codebase-design)
cat > "$work/bin/git" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
args=()
for argument in "$@"; do
  if [[ $argument == https://github.com/mattpocock/skills.git ]]; then
    if [[ ${FIXTURE_FETCH_FAIL:-0} == 1 ]]; then
      printf 'partial successful-looking observation\n'
      exit 8
    fi
    argument=$FIXTURE_UPSTREAM
  fi
  args+=("$argument")
done
exec "$FIXTURE_REAL_GIT" -c protocol.file.allow=always "${args[@]}"
STUB
chmod +x "$work/bin/git"
export PATH="$work/bin:$PATH"
skill=$work/plugin/skills/codebase-design/SKILL.md
notice=$work/plugin/resources/matt-pocock-LICENSE.txt
header() {
  cat > "$skill" <<HEADER
---
name: codebase-design
description: Fixture.
metadata:
    github-repo: https://github.com/mattpocock/skills
    github-path: skills/engineering/codebase-design
    github-ref: $revision
    github-tree-sha: $tree
---
Body.
HEADER
  cp "$FIXTURE_UPSTREAM/LICENSE" "$notice"
}
expect() {
  local want=$1 result=0
  bash "$here/check-matt-skill-license.sh" "$skill" > "$work/out" 2> "$work/err" || result=$?
  [[ $result == "$want" ]] || { cat "$work/out" "$work/err"; exit 1; }
}
header
expect 0
printf 'Copyright from a different revision.\n' > "$notice"
expect 1
header
rm "$notice"
expect 1
header
FIXTURE_FETCH_FAIL=1 expect 2
header
# A changed repository notice with the SAME skill tree cannot reuse old license evidence.
printf 'Different upstream grant.\n' > "$FIXTURE_UPSTREAM/LICENSE"
"$real_git" -C "$FIXTURE_UPSTREAM" add -- LICENSE
"$real_git" -C "$FIXTURE_UPSTREAM" -c commit.gpgsign=false commit -qm 'test: changed license'
new_revision=$("$real_git" -C "$FIXTURE_UPSTREAM" rev-parse HEAD)
sed "s/$revision/$new_revision/" "$skill" > "$work/header"
mv "$work/header" "$skill"
expect 1
header
# An unavailable or moved ref cannot certify the previously downloaded tree.
sed "s/$tree/0000000000000000000000000000000000000000/" "$skill" > "$work/header"
mv "$work/header" "$skill"
expect 2
header
sed '/github-ref:/a\
    github-ref: refs/heads/main
' "$skill" > "$work/header"
mv "$work/header" "$skill"
expect 2
header
sed 's|skills/engineering/codebase-design|../outside|' "$skill" > "$work/header"
mv "$work/header" "$skill"
expect 2
printf 'Matt license gate: PASS (8 cases)\n'
