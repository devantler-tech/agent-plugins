#!/usr/bin/env bash
# Contract test: a parked PR is owned work, never a terminal state.
#
# Dependency-update PRs stranded for weeks once a deployment parked them on a blocker: each run read
# the park as finished, nobody worked the blocker or re-checked the upstream it waited on, and nine
# parked PRs filled one ecosystem's open-PR limit so no new update could open. The role already said
# bot PRs are first-priority work; nothing said a park stays owned. These clauses say it in the three
# places a run reads it — the agent definition, the PR-driving procedure the skill links, and the
# surveyor that reports parked PRs — and each is removed from a copy to prove its assertion fires.
set -Eeuo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent="$plugin_root/agents/agentic-engineer.agent.md"
surveyor="$plugin_root/agents/portfolio-surveyor.agent.md"
skill_dir="$plugin_root/skills/portfolio-maintenance"
tmp="$(mktemp -d)"
# Bash 3.2 can report an errexit abort as success once an EXIT trap has run, so the trap refuses to
# exit 0 unless the script reached its final line.
completed=0
trap 'rm -rf "$tmp"; [ "$completed" = 1 ] || exit 1' EXIT

agent_clauses=(
	"parking is not finishing: a pr parked through the deployment's blocked-work mechanism stays owned work."
	"an in-portfolio blocker is finishing work, ahead of new pulls"
	"an upstream one is re-checked on a cadence, with an engineering route considered each time"
	"unblock a dependency pr parked past its bound by engineering routes you take yourself, recording what you tried and the next route."
	"ownership stays with you: a park never hands work to the maintainer, and no timer makes contacting the maintainer the outcome."
	"treat an update ecosystem at or near its open-pr limit with any pr parked as a stall"
	"unpark and drive a mis-park."
)
skill_clauses=(
	# The run loop's own summary, so a run that never opens the reference still meets the rule.
	"a parked pr is not finished: its blocker is owned work"
	"ownership never moves to the maintainer."
	"work the in-portfolio blocker behind every parked pr"
	# The complete rule, in the PR-driving procedure the skill links.
	"a parked pr is not a resting place."
	"the blocker a park names is owned work, and these rules apply to every parked pr on every run that drives prs."
	"a pr the consumer's contract designates automation-owned stays outside them, exactly as the survey leaves it."
	"never from the latest relabel, so a re-park keeps the earlier date and errs toward more work, never less."
	"an in-portfolio blocker is finishing work."
	"an unclaimed in-portfolio blocker behind a parked pr is a finding, never a wait."
	"make that decision yourself, and never resume fixing its findings one by one."
	"an upstream blocker is re-checked, not waited on."
	"at least every 7 days unless the cadence names another interval"
	"each check also weighs an engineering route instead of only waiting:"
	"or split or ignore only the blocked part of a grouped update, so the rest merges now."
	"once it has been parked for 14 days, unless the cadence names another bound, waiting is no longer a route."
	"take an engineering route yourself, and keep taking them until the pr merges:"
	"record on the pr what you tried and what it showed, the next route you will take,"
	"a missing or lapsed record makes taking the next route finishing work this run. it never lifts the park or the merge hold"
	"an ignore is a lasting configuration change: record it on the blocker, and remove it when the blocker clears."
	# The maintainer owns direction, not the work (maintainer, 2026-11-13): no bound hands it over.
	"ownership stays with you."
	"no timer or bound makes contacting the maintainer the outcome."
	"only for a genuine question of direction you cannot settle on your own, and never to ask about what you can do yourself."
	"such an ask is never a handoff and never a substitute for the work: state the default you will act on if no answer comes, and keep working the routes meanwhile."
	"an update ecosystem at or near its open-pr limit is stalled."
	"raising the limit alone hides the stall instead of clearing it."
	"a blocker you cannot read, or a record that names none, never justifies unparking"
	"a mis-park is unparked and driven. at every check, confirm the pr really depends on its named blocker:"
	"when its park facts (when it was parked, its blocker, its latest route record) cannot be read, the pr is unknown, never settled."
)
surveyor_clauses=(
	"a pr the consumer parked through its blocked-work mechanism is still a candidate, never settled."
	"reports that field as \`unknown\`, never a guessed date or \`none\`."
	"never omit a parked pr from the digest, or classify it as finished, because it is parked."
	"parked=<date|unknown>"
	"never from a census or search row, which can drop a label."
	"a later relabel never restarts the clock."
	"\`blocker=<owner/repo#n|upstream|decision|none>\`"
	"decision=<date|none|unknown>"
)
# A sentence that would make any of the three read a park as settled, or hand it to the maintainer.
forbidden_clauses=(
	"a parked pr is a terminal state"
	"parked prs are finished"
	"raise it once through the deployment's maintainer channels"
	"past a longer bound"
	# Dependabot security updates have their own open-PR limit, so a version-update stall never blocks them.
	"security fixes included"
)

normalize() {
	LC_ALL=C awk '{
		line=tolower($0)
		gsub(/\*/, "", line)
		gsub(/[[:space:]]+/, " ", line)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
		if (line != "") printf "%s ", line
	}
	# One terminated line, so an awk pass that removes nothing reproduces it byte for byte and the
	# "found nothing to remove" guard below can actually fire.
	END { printf "\n" }' "$1"
}

# check <file> <clause>... — exit 0 when every clause is present and no forbidden one is.
check() {
	local file="$1" text clause
	shift
	text="$(normalize "$file")"
	[ -n "$text" ] || return 1
	for clause in "$@"; do
		[[ $text == *"$clause"* ]] || return 1
	done
	for clause in "${forbidden_clauses[@]}"; do
		[[ $text != *"$clause"* ]] || return 1
	done
}

# The skill keeps a summary and links the complete rung in references/driving-prs.md. Check the text
# an agent reads by following that link: the skill with the reference inserted after the first line
# that links it. A dropped link or an emptied reference removes the clauses, so the check fails closed.
linked_skill() { # skill-dir output reference
	LC_ALL=C awk -v dir="$1" -v ref="$3" '
		{
			print
			if (!done && index($0, "](" ref ")")) {
				while ((getline line < (dir "/" ref)) > 0) print line
				close(dir "/" ref)
				done = 1
			}
		}
	' "$1/SKILL.md" >"$2"
}

fail=0
for f in "$agent" "$surveyor" "$skill_dir/SKILL.md" "$skill_dir/references/driving-prs.md"; do
	[ -r "$f" ] || { echo "cannot read $f" >&2; exit 1; }
done
linked_skill "$skill_dir" "$tmp/linked-skill.md" references/driving-prs.md
grep -qF "A parked PR is not a resting place." "$tmp/linked-skill.md" || {
	echo "  ✗ SKILL.md no longer links references/driving-prs.md, so the linked text lacks the rule" >&2
	exit 1
}

# surface <label> <file> <clause>...
surface() {
	local label="$1" file="$2" clause
	shift 2
	local -a clauses=("$@")
	if check "$file" "${clauses[@]}"; then
		echo "  ✓ $label says a parked PR stays owned work"
	else
		echo "  ✗ $label must say a parked PR stays owned work (missing clause, or a forbidden one present)" >&2
		fail=1
	fi
	# Mutation cases: the text with one clause removed must fail. Prose wraps, so each clause is removed
	# from the normalised text, not the file.
	normalize "$file" >"$tmp/normalized.md"
	for clause in "${clauses[@]}"; do
		awk -v clause="$clause" '{
			position = index($0, clause)
			if (position > 0) $0 = substr($0, 1, position - 1) substr($0, position + length(clause))
			print
		}' "$tmp/normalized.md" >"$tmp/mutant.md"
		if cmp -s "$tmp/normalized.md" "$tmp/mutant.md"; then
			echo "  ✗ $label: mutation found nothing to remove for: $clause" >&2
			fail=1
		elif check "$tmp/mutant.md" "${clauses[@]}"; then
			echo "  ✗ $label: check passed with a clause removed: $clause" >&2
			fail=1
		else
			echo "  ✓ $label: removing a clause fails: ${clause:0:60}…"
		fi
	done
	# A forbidden sentence added to the real text must fail, for the right reason: every required
	# clause is still present.
	for clause in "${forbidden_clauses[@]}"; do
		{ cat "$tmp/normalized.md"; printf '%s\n' "$clause"; } >"$tmp/forbidden.md"
		if check "$tmp/forbidden.md" "${clauses[@]}"; then
			echo "  ✗ $label: check passed with a forbidden clause added: $clause" >&2
			fail=1
		else
			echo "  ✓ $label: adding a forbidden clause fails: $clause"
		fi
	done
}

surface "agentic-engineer" "$agent" "${agent_clauses[@]}"
surface "portfolio-maintenance (with driving-prs.md)" "$tmp/linked-skill.md" "${skill_clauses[@]}"
surface "portfolio-surveyor" "$surveyor" "${surveyor_clauses[@]}"

completed=1
exit "$fail"
