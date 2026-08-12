#!/usr/bin/env bash
#
# forge-readonly-guard.sh
#
# Decides whether a candidate shell command is provably a read against the
# source forge, so a runtime can enforce the portfolio-surveyor's read-only
# boundary by construction instead of trusting the model to honour it.
#
# The surveyor's definition already states the boundary in prose — "your shell
# access exists solely to run the source-forge CLI's read verbs" — and asks
# deployments to enforce it in the permission/guard layer. This is the decision
# procedure that layer calls. It is tool-neutral: a Claude Code PreToolUse hook,
# a Codex approval guard, and a plain wrapper all ask the same question.
#
#   forge-readonly-guard.sh --command '<command>'
#   <command> | forge-readonly-guard.sh --stdin
#
#   exit 0  allowed — every pipeline segment is a recognised read
#   exit 1  denied  — prints `deny: <reason>`
#   exit 2  usage error
#
# Deny by default. A subcommand that is not positively recognised as a read is
# denied, so a new or renamed verb fails closed rather than passing unnoticed.
#
# The command is parsed quote-aware, because the surveyor's real queries carry
# `|` and `>` inside `--jq` expressions where they are data, not shell syntax.
# Outside quotes those characters are structural and refused: a denied command
# must not be able to ride along behind an allowed one.
#
# Two limits are deliberate and stated rather than hidden:
#
#   * It classifies the command text as written. Command substitution is denied,
#     but parameter expansion is not — the surveyor's own prescriptions use it.
#     A deployment that also lets the agent set arbitrary environment variables
#     must constrain that separately; this guard cannot see through `$VAR`.
#   * The allowlist is the surveyor's measured vocabulary, not every read a forge
#     CLI offers. Widening it is a reviewed edit here, which is the point.
#
# Written for bash 3.2 so it runs on a stock macOS agent host as well as CI.
#
set -euo pipefail

deny() {
  printf 'deny: %s\n' "$1"
  exit 1
}

die() {
  printf 'forge-readonly-guard: %s\n' "$1" >&2
  exit 2
}

# Filters with no in-language write primitive: without shell redirection, which
# the scanner already refuses, none of these can create or modify a file. awk is
# absent on purpose — its `print > "file"` needs no shell redirection at all.
SAFE_FILTERS=" jq grep sort head tail uniq wc cut tr cat "

# gh api flags that consume the following word. Needed so the endpoint is found
# by position rather than mistaken for a --jq expression.
GH_API_VALUE_FLAGS=" --jq -q --method -X --header -H --field -f --raw-field -F --input --template -t --hostname --cache --preview -p "

# git global flags that consume the following word, so `git -C <path> log`
# resolves to the `log` subcommand rather than to `-C`.
GIT_VALUE_FLAGS=" -C -c --git-dir --work-tree --exec-path --namespace "

SEGMENTS=()
WORDS=()
SUB_WORD=''
SUB_INDEX=-1

# Walk the command one character at a time, tracking quote state, splitting on
# unquoted `|` and refusing every other unquoted construct that could smuggle a
# second command in.
scan_segments() {
  local s=$1
  local n=${#s}
  local state=none
  local cur=''
  local i=0 ch nxt

  while [ "$i" -lt "$n" ]; do
    ch=${s:$i:1}
    nxt=${s:$((i + 1)):1}

    if [ "$state" = single ]; then
      if [ "$ch" = "'" ]; then state=none; fi
      cur=$cur$ch
      i=$((i + 1))
      continue
    fi

    if [ "$state" = double ]; then
      case "$ch" in
        \\)
          cur=$cur$ch$nxt
          i=$((i + 2))
          continue
          ;;
        '`') deny 'backtick command substitution is not a read' ;;
        '$')
          if [ "$nxt" = '(' ]; then deny 'dollar-paren command substitution is not a read'; fi
          ;;
        '"') state=none ;;
      esac
      cur=$cur$ch
      i=$((i + 1))
      continue
    fi

    case "$ch" in
      "'")
        state=single
        cur=$cur$ch
        ;;
      '"')
        state=double
        cur=$cur$ch
        ;;
      \\)
        cur=$cur$ch$nxt
        i=$((i + 1))
        ;;
      '`') deny 'backtick command substitution is not a read' ;;
      '$')
        if [ "$nxt" = '(' ]; then deny 'dollar-paren command substitution is not a read'; fi
        cur=$cur$ch
        ;;
      '<')
        if [ "$nxt" = '(' ]; then deny 'process substitution <( ) is not a read'; fi
        deny 'input redirection is not a read'
        ;;
      '>')
        if [ "$nxt" = '(' ]; then deny 'process substitution >( ) is not a read'; fi
        deny 'output redirection writes a file'
        ;;
      ';') deny 'chaining with ; can carry a write' ;;
      '&') deny '& backgrounding or && chaining can carry a write' ;;
      '|')
        SEGMENTS[${#SEGMENTS[@]}]=$cur
        cur=''
        ;;
      $'\n' | $'\r') deny 'a newline can carry a second command' ;;
      *) cur=$cur$ch ;;
    esac
    i=$((i + 1))
  done

  if [ "$state" != none ]; then
    deny 'unbalanced quoting — the command cannot be classified'
  fi
  SEGMENTS[${#SEGMENTS[@]}]=$cur
}

unquote() {
  local s=$1
  s=${s%\"}
  s=${s#\"}
  s=${s%\'}
  s=${s#\'}
  printf '%s' "$s"
}

# The first non-flag word in WORDS at or after $1, skipping flags and the values
# they consume ($2 is a space-delimited set of value-taking flags).
#
# Reports through the globals SUB_WORD and SUB_INDEX rather than stdout, because
# a caller needs both the word and where it sat — and reading the word through
# `$(...)` would run this in a subshell, where the index assignment dies with it.
find_subcommand() {
  local i=$1
  local value_flags=$2
  local w

  SUB_WORD=''
  SUB_INDEX=-1
  while [ "$i" -lt "${#WORDS[@]}" ]; do
    w=$(unquote "${WORDS[$i]}")
    case "$w" in
      --)
        i=$((i + 1))
        continue
        ;;
      -*)
        case "$value_flags" in
          *" $w "*) i=$((i + 2)) ;;
          *) i=$((i + 1)) ;;
        esac
        continue
        ;;
      *)
        SUB_WORD=$w
        SUB_INDEX=$i
        return 0
        ;;
    esac
  done
  return 0
}

classify_gh_api() {
  local seg=$1
  local endpoint method=''

  find_subcommand 2 "$GH_API_VALUE_FLAGS"
  endpoint=$SUB_WORD

  if [[ "$seg" =~ (^|[[:space:]])(--method|-X)[[:space:]]+([A-Za-z]+) ]]; then
    method=$(printf '%s' "${BASH_REMATCH[3]}" | tr '[:lower:]' '[:upper:]')
  fi

  if [ "$endpoint" = graphql ]; then
    # GraphQL is served over POST, so the method cannot separate a read from a
    # write here — the operation keyword does. The GraphQL spec has exactly
    # three operation types, and an anonymous `{ ... }` document is a query, so
    # refusing the other two is exhaustive rather than a blacklist with gaps.
    if [[ "$seg" =~ (^|[^A-Za-z])[Mm][Uu][Tt][Aa][Tt][Ii][Oo][Nn]([^A-Za-z]|$) ]]; then
      deny 'GraphQL mutation is a write'
    fi
    if [[ "$seg" =~ (^|[^A-Za-z])[Ss][Uu][Bb][Ss][Cc][Rr][Ii][Pp][Tt][Ii][Oo][Nn]([^A-Za-z]|$) ]]; then
      deny 'GraphQL subscription is not a bounded read'
    fi
    if [ -n "$method" ] && [ "$method" != POST ] && [ "$method" != GET ]; then
      deny "gh api graphql --method $method is not a read"
    fi
    return 0
  fi

  if [ -n "$method" ] && [ "$method" != GET ]; then
    deny "gh api --method $method is not a read"
  fi

  # Without an explicit --method, gh switches to POST as soon as a field is set,
  # so a field argument on a REST endpoint is a write in everything but spelling.
  if [ -z "$method" ] &&
    [[ "$seg" =~ (^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]]|=) ]]; then
    deny 'gh api field arguments make the request a POST'
  fi

  if [ -z "$endpoint" ]; then
    deny 'gh api needs an endpoint to be classified'
  fi
  return 0
}

classify_gh() {
  local seg=$1
  local sub sub2 sub_at

  find_subcommand 1 ' '
  sub=$SUB_WORD
  sub_at=$SUB_INDEX
  if [ -z "$sub" ]; then deny 'gh needs a subcommand to be classified'; fi

  if [ "$sub" = api ]; then
    classify_gh_api "$seg"
    return 0
  fi

  find_subcommand $((sub_at + 1)) ' '
  sub2=$SUB_WORD

  case "$sub" in
    pr)
      case "$sub2" in
        list | view | diff | checks | status) return 0 ;;
        *) deny "gh pr ${sub2:-<none>} is not a read verb" ;;
      esac
      ;;
    issue)
      case "$sub2" in
        list | view) return 0 ;;
        *) deny "gh issue ${sub2:-<none>} is not a read verb" ;;
      esac
      ;;
    search)
      case "$sub2" in
        issues | prs | repos | code | commits) return 0 ;;
        *) deny "gh search ${sub2:-<none>} is not on the read allowlist" ;;
      esac
      ;;
    repo)
      case "$sub2" in
        list | view) return 0 ;;
        *) deny "gh repo ${sub2:-<none>} is not a read verb" ;;
      esac
      ;;
    run)
      case "$sub2" in
        list | view) return 0 ;;
        *) deny "gh run ${sub2:-<none>} is not a read verb" ;;
      esac
      ;;
    release)
      case "$sub2" in
        list | view) return 0 ;;
        *) deny "gh release ${sub2:-<none>} is not a read verb" ;;
      esac
      ;;
    label)
      case "$sub2" in
        list) return 0 ;;
        *) deny "gh label ${sub2:-<none>} is not a read verb" ;;
      esac
      ;;
    *) deny "gh $sub is not on the read-only allowlist" ;;
  esac
}

classify_git() {
  local sub
  find_subcommand 1 "$GIT_VALUE_FLAGS"
  sub=$SUB_WORD
  if [ -z "$sub" ]; then deny 'git needs a subcommand to be classified'; fi

  case "$sub" in
    log | status | show | diff | rev-parse | rev-list | ls-remote | ls-files | cat-file | describe)
      return 0
      ;;
    *) deny "git $sub is not a read verb" ;;
  esac
}

# sed is allowed by shape, not by exclusion: a plain substitution or a line
# print/delete, and nothing else. `w` writes a file and `e` executes a command,
# and both hide in a flag position that a blacklist keeps missing.
check_sed_script() {
  local s delim tail
  s=$(unquote "$1")

  if [[ "$s" =~ ^[0-9,\$]*[pd]$ ]]; then return 0; fi

  case "$s" in
    s?*) ;;
    *) deny "sed script '$s' is not a plain substitution" ;;
  esac

  delim=${s:1:1}
  tail=${s##*"$delim"}
  if [[ ! "$tail" =~ ^[gpIiMm0-9]*$ ]]; then
    deny "sed flags '$tail' may write a file or execute a command"
  fi
  return 0
}

classify_sed() {
  local i=1 a

  while [ "$i" -lt "${#WORDS[@]}" ]; do
    a=$(unquote "${WORDS[$i]}")
    case "$a" in
      -n | -E | -r | --regexp-extended | --quiet | --silent | --) ;;
      -e | --expression)
        i=$((i + 1))
        check_sed_script "${WORDS[$i]:-}"
        ;;
      -i | --in-place | -i* | --in-place=*) deny 'sed -i rewrites a file in place' ;;
      -f | --file) deny 'sed -f takes its script from a file' ;;
      -*) deny "sed flag '$a' is not on the read-only allowlist" ;;
      *) check_sed_script "$a" ;;
    esac
    i=$((i + 1))
  done
}

classify_segment() {
  local seg=$1
  local prog=''

  WORDS=()
  read -ra WORDS <<<"$seg"

  if [ "${#WORDS[@]}" -gt 0 ]; then prog=$(unquote "${WORDS[0]}"); fi
  if [ -z "$prog" ]; then deny 'empty pipeline segment — || chaining or a stray |'; fi

  case "$prog" in
    gh) classify_gh "$seg" ;;
    git) classify_git ;;
    sed) classify_sed ;;
    *)
      case "$SAFE_FILTERS" in
        *" $prog "*) ;;
        *) deny "'$prog' is not on the read-only allowlist" ;;
      esac
      ;;
  esac
}

main() {
  local command='' have=0 seg

  while [ $# -gt 0 ]; do
    case "$1" in
      --command)
        if [ $# -lt 2 ]; then die '--command needs a value'; fi
        command=$2
        have=1
        shift 2
        ;;
      --stdin)
        command=$(cat)
        have=1
        shift
        ;;
      -h | --help)
        sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  if [ "$have" -ne 1 ]; then die 'need --command <command> or --stdin'; fi
  if [[ ! "$command" =~ [^[:space:]] ]]; then die 'the command is empty'; fi

  scan_segments "$command"
  for seg in "${SEGMENTS[@]}"; do
    classify_segment "$seg"
  done

  printf 'allow\n'
}

main "$@"
