#!/usr/bin/env bash
# preexisting-failure.sh — one tracker per failure that is already red on a base
# branch, so every gate that meets the red confirms that bead instead of filing
# another.
#   preexisting-failure.sh key --test <test function>
#   preexisting-failure.sh key --target <repo-relative path>
#   preexisting-failure.sh key --lint <linter> <repo-relative path>
#   preexisting-failure.sh find <key> [--closed-after <YYYY-MM-DD>]
#   preexisting-failure.sh file <key> --message <text> [--summary <text>]
# Callers: the refinery's merge gate (formulas/mol-refinery-patrol.toml,
# handle-failures) and a polecat's pre-flight (formulas/mol-polecat-work.toml,
# preflight-tests).
#
# The key names the failure, never its wording, and `key` is what derives it,
# so two gates that meet one red reach one key. A failing test function is its
# own key, cut at the first `/` because two gates often trip different Go
# subtests of one function. A failure with no test function, such as a suite
# file, a package or a build target, is its repo-relative path. A lint finding
# is the linter and the repo-relative path of the file it flagged, so one file
# is one tracker whatever lines and codes the linter reports in it.
#
# `file` writes the key as `failure_key` metadata in the create itself and reads
# it back, and `find` matches that stamp exactly, so a fixer who retitles the
# tracker to name the fix does not hide it. A bug filed before the stamp existed
# is found by the key in its title, but only while it carries no stamp, because
# a stamped bead is the tracker of the key it names.
#
# Exit: 0 the store answered: `find` prints the tracker's id, or nothing when
# there is none, and `file` prints the id of the tracker it filed or found · 1
# the store could not be read or written, which is never "none" · 2 usage
set -uo pipefail

PROG="preexisting-failure"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Every status a live tracker can hold, in one comma list, because a repeated
# --status keeps only its last value. A red persists while someone fixes it, so
# its tracker is usually in_progress, or blocked under a hold. Closed is left
# out: a red that outlives a landed fix is new information.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# `bd create` refuses a title over 500 bytes. The key is never cut; a summary
# is cut at a word boundary so the whole title stays within this many
# characters.
TITLE_MAX=200

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }

warn() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
  cat >&2 <<'U'
usage: preexisting-failure.sh key --test <test function>
       preexisting-failure.sh key --target <repo-relative path>
       preexisting-failure.sh key --lint <linter> <repo-relative path>
       preexisting-failure.sh find <key> [--closed-after <YYYY-MM-DD>]
       preexisting-failure.sh file <key> --message <text> [--summary <text>]

  key     prints the failure's key. --test takes a test function, or a pasted
          `--- FAIL: TestFoo/case` line, and drops a Go subtest suffix.
          --target takes the repo-relative path of a failing suite file,
          package or build target. --lint takes the linter or learned rule and
          the repo-relative path of the file it flagged. A trailing
          :<line>[:<col>] on a path is dropped.
  find    prints the id of the key's live tracker, or nothing when there is
          none. --closed-after reads the trackers closed since that date
          instead of the live ones.
  file    files the key's tracker and prints its id: a P1 bug titled
          `Pre-existing failure: <key>`, with --message as its body and the
          key stamped as failure_key. When a live tracker already holds the
          key it files nothing and prints that tracker's id instead.
          --summary appends a few words to the title after the key.
U
}

# The test functions a key names. Go's are Test, Benchmark, Example and Fuzz
# functions; a pytest function opens test_.
TEST_FUNC_RE='^((Test|Benchmark|Example|Fuzz)[A-Za-z0-9_]*|test_[A-Za-z0-9_]*)$'
LINTER_RE='^[a-z0-9][a-z0-9._+-]*$'

# norm_path <path> — the repo-relative spelling of a path, or non-zero when it
# has none. A trailing :<line>[:<col>] is dropped, because a linter prints one
# and the line moves as the file changes. An absolute path inside the current
# checkout is made relative to it; any other absolute path names one agent's
# worktree, so it is refused.
norm_path() {
  local p="$1" top
  p="${p%%:[0-9]*}"
  case "$p" in
    ''|-*|*'<'*|*'>'*|*=*|*[[:space:]]*) return 1 ;;
  esac
  if [ "${p#/}" != "$p" ]; then
    top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    case "$p" in
      "$top"/*) p="${p#"$top"/}" ;;
      *) return 1 ;;
    esac
  fi
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  p=$(printf '%s' "$p" | tr -s '/')
  p="${p%/}"
  case "/$p/" in
    //|*/./*|*/../*) return 1 ;;
  esac
  printf '%s' "$p"
}

# test_key <name> — the test function a failing test reports, or non-zero.
test_key() {
  local n="$1"
  n="${n#*--- FAIL: }"
  n="${n#"${n%%[![:space:]]*}"}"
  n="${n%%[[:space:]]*}"
  n="${n%%/*}"
  [[ "$n" =~ $TEST_FUNC_RE ]] || return 1
  printf '%s' "$n"
}

# lint_name <linter> — the linter's name as a key spells it: lower case, and
# words joined by hyphens, so "ShellCheck" and "go vet" each have one spelling.
lint_name() {
  local l
  l=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' '-')
  l="${l#-}"; l="${l%-}"
  [[ "$l" =~ $LINTER_RE ]] || return 1
  printf '%s' "$l"
}

# valid_key <key> — 0 when the key is one `key` could have printed: a test
# function or a path, or a linter and a path. A hand-typed token such as a
# prose summary or a shellcheck code list is refused, because the stamp match
# is exact and a token derived any other way never meets the tracker.
valid_key() {
  local k="$1" first rest n
  [ -n "$k" ] || return 1
  [[ "$k" == *[[:cntrl:]]* ]] && return 1
  case "$k" in
    *' '*)
      first="${k%% *}"; rest="${k#* }"
      n=$(lint_name "$first") && [ "$n" = "$first" ] || return 1
      n=$(norm_path "$rest") && [ "$n" = "$rest" ] ;;
    *)
      [[ "$k" =~ $TEST_FUNC_RE ]] && return 0
      n=$(norm_path "$k") && [ "$n" = "$k" ] ;;
  esac
}

key_cmd() {
  local k
  case "${1:-}" in
    --test)
      [ $# -eq 2 ] || { usage; exit 2; }
      k=$(test_key "$2") || {
        warn "--test takes a test function, such as TestFoo or a pasted '--- FAIL: TestFoo/case' line (got '$2'). A failing suite file, package or build target is --target <path>"
        exit 2
      } ;;
    --target)
      [ $# -eq 2 ] || { usage; exit 2; }
      k=$(norm_path "$2") || {
        warn "--target takes a repo-relative path (got '$2')"
        exit 2
      } ;;
    --lint)
      [ $# -eq 3 ] || { usage; exit 2; }
      local l p
      l=$(lint_name "$2") || { warn "--lint takes the linter or learned rule that reported the finding, such as shellcheck (got '$2')"; exit 2; }
      p=$(norm_path "$3") || { warn "--lint takes the repo-relative path of the flagged file (got '$3')"; exit 2; }
      k="$l $p" ;;
    *) usage; exit 2 ;;
  esac
  printf '%s\n' "$k"
}

# find_tracker <key> <statuses> [<closed-after>] — the id of the key's tracker,
# or nothing. Non-zero when a listing could not be read, which the caller must
# treat as "unknown", never as "none". The stamp is matched first; the title
# match is for a bug filed before the stamp existed. Each row is re-checked
# against the filters it was listed by, so a listing that ignored one cannot
# pass another bead off as the tracker.
find_tracker() {
  local key="$1" st="$2" after="${3:-}" rows id
  local since=()
  [ -n "$after" ] && since=(--closed-after "$after")
  rows=$(bd_list --status="$st" --metadata-field "failure_key=$key" ${since[@]+"${since[@]}"}) || return 1
  id=$(printf '%s' "$rows" | jq -r --arg k "$key" --arg st "$st" '
      ($st | split(",")) as $want
      | [ .[] | select((((.metadata // {}).failure_key // "") | tostring) == $k
                       and ((.status // "") as $s | $want | any(. == $s))) ]
      | .[0].id // empty' 2>/dev/null) || return 1
  if [ -z "$id" ]; then
    rows=$(bd_list --type=bug --status="$st" --title-contains "$key" ${since[@]+"${since[@]}"}) || return 1
    id=$(printf '%s' "$rows" | jq -r --arg k "$key" --arg st "$st" '
        ($st | split(",")) as $want
        | [ .[] | select((((.metadata // {}).failure_key // "") | tostring) == ""
                         and (.issue_type // "") == "bug"
                         and ((.title // "") | ascii_downcase | contains($k | ascii_downcase))
                         and ((.status // "") as $s | $want | any(. == $s))) ]
        | .[0].id // empty' 2>/dev/null) || return 1
  fi
  printf '%s' "$id"
}

find_cmd() {
  local key="${1:-}" after="" id st
  [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --closed-after) after="${2:-}"; shift 2 || { usage; exit 2; } ;;
      *) warn "unknown argument '$1'"; usage; exit 2 ;;
    esac
  done
  valid_key "$key" || { warn "'$key' is not a key this script derives; derive it with \`$PROG.sh key\`"; exit 2; }
  st="$LIVE_STATUSES"
  if [ -n "$after" ]; then
    [[ "$after" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || { warn "--closed-after takes a date, YYYY-MM-DD (got '$after')"; exit 2; }
    st="closed"
  fi
  id=$(find_tracker "$key" "$st" "$after") || {
    warn "the lookup for '$key' could not read the store; that is not proof the tracker is missing"
    exit 1
  }
  [ -z "$id" ] || printf '%s\n' "$id"
  exit 0
}

file_cmd() {
  local key="${1:-}" message="" summary="" id title room body meta out got
  [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --message) message="${2:-}"; shift 2 || { usage; exit 2; } ;;
      --summary) summary="${2:-}"; shift 2 || { usage; exit 2; } ;;
      *) warn "unknown argument '$1'"; usage; exit 2 ;;
    esac
  done
  valid_key "$key" || { warn "'$key' is not a key this script derives; derive it with \`$PROG.sh key\`"; exit 2; }
  # The evidence is what makes the bead workable: a title-only P1 cannot be
  # dispositioned, since nothing in it separates a host-load flake from a real
  # regression.
  [ -n "$(printf '%s' "$message" | tr -d '[:space:]')" ] || { warn "--message is required: the failure's evidence is the tracker's body"; exit 2; }
  summary=$(printf '%s' "$summary" | tr '\n\r\t' '   ' | tr -s ' ')
  summary="${summary# }"; summary="${summary% }"
  case "$summary" in
    *'<'*'>'*) warn "--summary still carries a <placeholder> (got '$summary')"; exit 2 ;;
  esac

  # The caller's lookup and this create are not one transaction, so a gate that
  # filed the key in between is found here rather than filed beside.
  id=$(find_tracker "$key" "$LIVE_STATUSES") || {
    warn "the lookup for '$key' could not read the store; filing nothing, since an unread store is not proof the tracker is missing"
    exit 1
  }
  if [ -n "$id" ]; then
    warn "'$key' is already tracked as $id; filed nothing"
    printf '%s\n' "$id"
    exit 0
  fi

  title="Pre-existing failure: $key"
  if [ -n "$summary" ]; then
    room=$(( TITLE_MAX - ${#title} - 4 ))
    if [ "${#summary}" -gt "$room" ] && [ "$room" -gt 0 ]; then
      summary="${summary:0:$room}"
      case "$summary" in *" "*) summary="${summary% *}" ;; esac
      # Braced: under a UTF-8 locale, macOS /bin/bash 3.2 and Homebrew bash
      # 5.3.15 read the ellipsis's first byte into an unbraced name.
      summary="${summary}…"
    fi
    [ "$room" -gt 0 ] && title="$title — $summary"
  fi
  # shellcheck disable=SC2016  # the backticks are markdown in the bead body
  body=$(printf '%s\n\n## Tracking\n\nEvery gate that meets this failure finds this bead by its `failure_key` metadata, `%s`, and confirms on it instead of filing another. A retitle leaves that key in place, so the title can be changed to name the fix.' "$message" "$key")

  # The stamp rides the create. A bead whose key landed in a second write that
  # failed is a bead the next gate's lookup cannot find, and that gate files
  # again.
  meta=$(jq -nc --arg k "$key" '{failure_key: $k}') || { warn "could not build the metadata payload (jq); nothing filed"; exit 1; }
  out=$(gc bd create --type=bug --priority=1 --title "$title" -d "$body" --metadata "$meta" --json 2>/dev/null | scrub)
  id=$(printf '%s' "$out" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    # bd can file a bead and answer with no id, and a blind retry would file
    # the duplicate. The stamp rode the create, so the bead is found instead.
    id=$(find_tracker "$key" "$LIVE_STATUSES") || id=""
    [ -z "$id" ] || warn "bd create returned no id, but the tracker exists as $id"
  fi
  [ -n "$id" ] || { warn "bd create filed nothing for '$key'"; exit 1; }

  got=$(bd_json show "$id" | jq -r 'if type == "array" then (.[0].metadata.failure_key // "") else "" end' 2>/dev/null)
  if [ "$got" != "$key" ]; then
    warn "failure_key on $id read back as '$got', expected '$key', so the next gate's lookup cannot find it by its stamp. Repair: gc bd update $id --set-metadata \"failure_key=$key\""
    exit 1
  fi
  printf '%s\n' "$id"
}

CMD="${1:-}"
[ $# -gt 0 ] && shift
case "$CMD" in
  key)  key_cmd "$@" ;;
  find) find_cmd "$@" ;;
  file) file_cmd "$@" ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac
