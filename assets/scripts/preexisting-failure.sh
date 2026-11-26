#!/usr/bin/env bash
# preexisting-failure.sh — one tracker per failure that is already red on a base
# branch, sent to be fixed when it is filed, so every gate that meets the red
# confirms that bead instead of filing another.
#   preexisting-failure.sh key --test <test function>
#   preexisting-failure.sh key --target <repo-relative path>
#   preexisting-failure.sh key --lint <linter> <repo-relative path>
#   preexisting-failure.sh find <key> [--closed-after <YYYY-MM-DD>]
#   preexisting-failure.sh file <key> --message <text> [--summary <text>]
# Callers: the refinery's merge gate (formulas/mol-refinery-patrol.toml,
# handle-failures, through refinery-pre-existing.sh), a polecat's pre-flight
# and self-review (formulas/mol-polecat-work.toml), the actions-track order's
# pass over a rig's default branch (services/gctk/actions), and an agent that
# finds a failure on a default branch some other way (skills/work/SKILL.md).
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
# it back, and `find` matches that stamp exactly and nothing else, so a fixer
# who retitles the tracker to name the fix does not hide it. A title is never
# read. A key is a substring of titles that name other failures, as TestFoo is
# of a TestFooBar tracker's title, and of titles that merely mention it, so a
# title match can take an unrelated bug for the tracker. A bug that carries no
# stamp is no key's tracker.
#
# A tracker can close while its failure is still red. bead-rehome.sh closes a
# folded, re-homed or duplicate tracker with a supersedes or duplicates edge
# naming the bead that carries its work now, such as a batch that clears a set of lint
# trackers, and that bead carries no stamp of its own. So when no live tracker
# holds the key, the most recently closed one decides, because its close is
# the latest word on the failure. Its edge is followed through every bead
# that closed onward the same way, and a live bead at the end of the chain is
# the key's filing. The chain ends with no filing at a bead that closed naming
# no successor, because the failure was fixed there. It also ends at a not-needed
# close, whose edge names the evidence for that ruling rather than a bead
# that carries the failure. A red seen after either is new, and it is filed.
#
# A failure red on a base branch is work to fix, so no person places its
# tracker first (docs/steering.md, the intake rule). `file` slings the tracker
# it files with no target, and Gas City sends a bead slung so to the
# default_sling_target of the rig its prefix names, on that agent's default
# formula. A bead `file` finds instead is not slung again: it was sent when it
# was filed, or someone holds it, works it or has it wait, and a second sling
# would step past them.
#
# Two filers can meet one red at once, such as two gates, or a gate and the
# actions-track order. So `file` holds the store's filing lock from its lookup
# until its create has answered: a flock on preexisting-failure.lock in the
# store's own .beads directory, the one path `gc bd where` names for every
# caller of that store. The filer that comes second waits for the lock, then
# finds the tracker the first one filed and sends nothing. The send runs after
# the lock is let go, so a slow sling holds no other filer.
#
# Exit: 0 the store answered: `find` prints the id of the bead that tracks the
# key, or nothing when none does, and `file` prints the id of the tracker it
# filed or the bead it found, with a warning when the new tracker could not be
# read back to confirm its stamp, or could not be sent · 1 the store could not
# be read or written, its filing lock could not be taken, or the new tracker
# read back with its stamp missing or wrong, which is never "none" · 2 usage
set -uo pipefail

PROG="preexisting-failure"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Every status a live tracker can hold, in one comma list, because a repeated
# --status keeps only its last value. A red persists while someone fixes it, so
# its tracker is usually in_progress, or blocked under a hold. A closed tracker
# counts only through the live bead its failure moved to (tracked_by): a red
# that outlives a landed fix is new information.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# The most edges a chain of dispositions is followed through. A real chain
# is a fold or two long, so a longer one is a fault in the edges, and it is
# read as naming no bead that carries the failure rather than walked further.
CHAIN_MAX=20

# `bd create` refuses a title over 500 bytes. The key is never cut; a summary
# is cut at a word boundary so the whole title stays within this many
# characters.
TITLE_MAX=200

# How long `file` waits for the store's filing lock. A filer holds it for one
# lookup and one create, which take seconds.
LOCK_WAIT_SECS=60

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

# Every gc call runs with fd 9 closed. `file` holds the filing lock on fd 9, and
# a process a gc call starts, such as a Dolt server, can outlive this script and
# would hold the lock against every later filer.
gc() { command gc "$@" 9>&-; }

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
  find    prints the id of the bead that tracks the key, or nothing when none
          does. That bead is the live tracker stamped with the key. When there
          is none, it is the live bead that the most recently closed tracker's
          chain of disposition edges reaches. --closed-after reads the trackers
          closed since that date instead, and follows no chain.
  file    files the key's tracker, sends it to be fixed and prints its id: a
          P1 bug titled `Pre-existing failure: <key>`, with --message as its
          body and the key stamped as failure_key, slung to its rig's default
          sling target. When a bead already tracks the key, as find reads it,
          it files and sends nothing and prints that bead's id instead.
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

# find_tracker <key> <statuses> [<closed-after>] — the id of the bead stamped
# with the key, or nothing. Non-zero when the listing could not be read, which
# the caller must treat as "unknown", never as "none". Only the failure_key
# stamp is matched, never a title. Each row is re-checked against the filters
# it was listed by, so a listing that ignored one cannot pass another bead off
# as the tracker.
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
  printf '%s' "$id"
}

# read_stamp <id> — the failure_key bead <id> carries, which is empty when it
# carries none. Non-zero when the bead could not be read. `gc bd show` can
# answer an error object or nothing at all, so a read counts only when it
# returns that bead's own row.
read_stamp() {
  bd_json show "$1" | jq -er --arg id "$1" '
      if type == "array" and length > 0 and ((.[0].id // "") | tostring) == $id
      then (.[0].metadata // {}).failure_key // "" | tostring
      else error("unread") end' 2>/dev/null
}

# tracked_by <key> — the bead that tracks the key, set in the caller's shell so
# that both answers reach it: FILING is that bead's id, or empty when none
# tracks the key, and FILING_VIA is the closed tracker whose chain of
# disposition edges reached FILING, or empty when FILING is the key's own live tracker.
# Non-zero when the store could not be read, which the caller must treat as
# "unknown", never as "untracked".
#
# The chain is read as bead-rehome.sh writes it: each closed bead's duplicates
# or supersedes edge names the next. A not-needed close carries the note
# `Disposition <time>: not needed, per <successor> in <store>`, or, when the edge
# was added after an earlier close, `Disposition recorded <time>: ...`; a close
# made before the edges carries the same words as its close reason. An edge onto
# a bead the store does not hold ends the chain the way a fixed tracker does,
# because no bead carries the failure.
tracked_by() {
  local key="$1" rows tracker id prev="" out step hops=0 seen=" "
  FILING=""; FILING_VIA=""
  FILING=$(find_tracker "$key" "$LIVE_STATUSES") || return 1
  [ -z "$FILING" ] || return 0
  rows=$(bd_list --status=closed --metadata-field "failure_key=$key") || return 1
  tracker=$(printf '%s' "$rows" | jq -r --arg k "$key" '
      [ .[] | select((((.metadata // {}).failure_key // "") | tostring) == $k
                     and ((.status // "") | tostring) == "closed") ]
      | sort_by([((.closed_at // "") | tostring), ((.id // "") | tostring)])
      | (last // {}) | .id // empty' 2>/dev/null) || return 1
  id="$tracker"
  while [ -n "$id" ]; do
    case "$seen" in
      *" $id "*)
        warn "the chain of disposition edges from $tracker loops back to $id, so it names no bead that carries '$key'"
        return 0 ;;
    esac
    if [ "$hops" -gt "$CHAIN_MAX" ]; then
      warn "the chain of disposition edges from $tracker runs past $CHAIN_MAX edges without reaching a live bead, so it is read as naming none that carries '$key'"
      return 0
    fi
    seen="$seen$id "
    # The bead's list row, the one that carries an edge onto a bead in another
    # rig's store. No row is a store that holds no such bead, and a read that
    # fails is unknown.
    out=$(bd_exact_row "$id") || return 1
    step=$(printf '%s' "$out" | jq -r --arg live "$LIVE_STATUSES" "$DISPOSITION_JQ"'
        if length > 0 then
          .[0] as $b
          | ($b | disposed_to) as $p
          | if ($live | split(",") | any(. == (($b.status // "") | tostring))) then "live"
            elif $p == "" then "fixed"
            elif ((($b.close_reason // "") | tostring) | startswith("not needed, per " + $p + " "))
              or ((($b.notes // "") | tostring) | contains(": not needed, per " + $p + " in "))
            then "ruled"
            else "next " + $p end
        else "missing" end' 2>/dev/null) || return 1
    case "$step" in
      live)
        FILING="$id"
        [ "$id" = "$tracker" ] || FILING_VIA="$tracker"
        return 0 ;;
      fixed|ruled) return 0 ;;
      missing)
        [ -z "$prev" ] || warn "$prev names $id as its successor, but the store holds no such bead, so the chain from $tracker names no bead that carries '$key'"
        return 0 ;;
      "next "*) prev="$id"; id="${step#next }"; hops=$((hops + 1)) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

find_cmd() {
  local key="${1:-}" after="" id
  [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --closed-after) after="${2:-}"; shift 2 || { usage; exit 2; } ;;
      *) warn "unknown argument '$1'"; usage; exit 2 ;;
    esac
  done
  valid_key "$key" || { warn "'$key' is not a key this script derives; derive it with \`$PROG.sh key\`"; exit 2; }
  if [ -n "$after" ]; then
    [[ "$after" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || { warn "--closed-after takes a date, YYYY-MM-DD (got '$after')"; exit 2; }
    id=$(find_tracker "$key" closed "$after") || {
      warn "the lookup for '$key' could not read the store; that is not proof the tracker is missing"
      exit 1
    }
  else
    tracked_by "$key" || {
      warn "the lookup for '$key' could not read the store; that is not proof the tracker is missing"
      exit 1
    }
    id="$FILING"
    [ -z "$FILING_VIA" ] || warn "no live tracker holds '$key'; its closed tracker $FILING_VIA moved the failure to $id, which is live, so $id is its filing"
  fi
  [ -z "$id" ] || printf '%s\n' "$id"
  exit 0
}

# send <id> — slings the tracker this call filed, with no target. The sling's
# own lines go to stderr, because stdout is the tracker's id. A sling that fails
# leaves the tracker filed, where the next gate's lookup finds it and sends
# nothing, so the warning names the sling that sends it.
send() {
  if gc sling "$1" </dev/null >&2; then
    warn "sent $1 to be fixed"
  else
    warn "filed $1, but its sling failed, as gc says above, so nothing is fixing it yet. Send it: gc sling $1"
  fi
}

# take_filing_lock — take the filing lock of the store gc bd files into, on fd
# 9, waiting up to LOCK_WAIT_SECS for a filer that holds it. Non-zero when it is
# not taken, with the cause in LOCK_NOTE. The lock is let go when fd 9 closes,
# and at the latest when this script exits, however it exits.
take_filing_lock() {
  local dir lock
  LOCK_NOTE=""
  command -v flock >/dev/null 2>&1 || { LOCK_NOTE="flock is not on PATH"; return 1; }
  dir=$(bd_json where | jq -r 'if type == "object" then .path // empty else empty end' 2>/dev/null)
  [ -n "$dir" ] && [ -d "$dir" ] || { LOCK_NOTE="gc bd where named no store directory"; return 1; }
  lock="$dir/preexisting-failure.lock"
  ( : >> "$lock" ) 2>/dev/null || { LOCK_NOTE="cannot create $lock"; return 1; }
  exec 9>>"$lock" || { LOCK_NOTE="cannot open $lock"; return 1; }
  flock -w "$LOCK_WAIT_SECS" 9 2>/dev/null && return 0
  exec 9>&-
  LOCK_NOTE="another filer held $lock for ${LOCK_WAIT_SECS}s"
  return 1
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
  # filed the key in between is found here rather than filed beside. The lookup
  # is the one find makes, so the live bead a fold moved the tracker to is found
  # here too. It and the create run under the filing lock, so a filer that met
  # the same red at the same moment is found here as well.
  take_filing_lock || {
    warn "could not take the store's filing lock ($LOCK_NOTE); filing nothing, so the next filer to meet the red files it"
    exit 1
  }
  tracked_by "$key" || {
    warn "the lookup for '$key' could not read the store; filing nothing, since an unread store is not proof the tracker is missing"
    exit 1
  }
  id="$FILING"
  if [ -n "$id" ]; then
    if [ -n "$FILING_VIA" ]; then
      warn "'$key' is tracked by $id, the live bead its closed tracker $FILING_VIA moved the failure to; filed and sent nothing"
    else
      warn "'$key' is already tracked as $id; filed and sent nothing"
    fi
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
  # The create carried the stamp, so the next filer's lookup finds this tracker,
  # and the lock is let go before the read-back and the send.
  exec 9>&-

  # A read that fails says nothing about the stamp, and the tracker exists, so
  # it is retried once and then reported as filed, and sent. Only a read that
  # returns the bead without the key fails the filing: the next gate's lookup
  # cannot find that bead, and it would file another and send that one, so
  # this one is not sent.
  if ! got=$(read_stamp "$id") && ! got=$(read_stamp "$id"); then
    warn "filed $id with failure_key '$key' in its create, but could not read $id back to confirm the stamp. If gc bd show $id lacks it, repair: gc bd update $id --set-metadata \"failure_key=$key\""
    send "$id"
    printf '%s\n' "$id"
    exit 0
  fi
  if [ "$got" != "$key" ]; then
    warn "failure_key on $id read back as '$got', expected '$key', so the next gate's lookup cannot find it by its stamp, and it was not sent. Repair: gc bd update $id --set-metadata \"failure_key=$key\" && gc sling $id"
    exit 1
  fi
  send "$id"
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
