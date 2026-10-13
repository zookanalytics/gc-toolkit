#!/usr/bin/env bash
# run-cancel — end a graph.v2 molecule's run through gascity.
#
#   run-cancel.sh --step <formula.step-id> --reason "<text>" [--bead <id>] [--dry-run]
#   run-cancel.sh --root <root-id> --reason "<text>" [--ended] [--db <path>] [--dry-run]
#
# A molecule's lifecycle is gascity's: pour, claim, finalize, autoclose and run
# cancel. A run that should not continue is cancelled through gascity's run
# cancel, `POST /v0/city/<city>/runs/<root>/cancel` on the supervisor API. The
# cancel closes the root and every member that is not closed, a `blocked` one
# included, with gc.outcome=canceled, blockers first, and runs none of them. A
# session mid-step finishes that step and idles. This script writes no member of
# the molecule. In --step mode it appends the reason to the step this session
# holds, which is the one bead a worker writes.
#
# --step names the run by the step this shell is executing: this session's bead
# for that gc.step_ref, found by assignee (in_progress first, then open, then
# blocked), and that bead's gc.root_bead_id. --bead is a hint, used only when it
# verifies as this session's bead for the step. --root names the run directly,
# for a caller that holds no step of it.
#
# A run whose root is already closed is not cancelled, because gascity's cancel
# leaves a terminal run's members as they are and answers 409. A member still
# open under a closed root, which a root closed by hand leaves behind, is closed
# by gascity's `gc convoy delete <root> --force`. That close is refused when
# such a member carries `branch` or `merge_result`, because that member is a
# work bead and only the refinery closes one. --ended is for a caller that read
# the root as closed and means to end only what such a run left open: it refuses
# a root that reads live instead of cancelling it.
#
# The cancel is retried on a 5xx answer or a failed connection. When it still
# does not land the script exits 1, and the caller does not drain: its step
# stays claimed, so whichever worker the step goes to next retries the cancel.
#
# Callers: the decline arms of mol-polecat-work, mol-validate and mol-rig-demo;
# orphan-dispose.sh (--ended); gc-helm.sh takeaway --release.
# exit: 0 the run is ended · 1 the run is not ended · 2 refused, nothing written
set -uo pipefail

PROG="run-cancel"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: run-cancel.sh --step <formula.step-id> --reason "<text>" [--bead <id>] [--dry-run]
       run-cancel.sh --root <root-id> --reason "<text>" [--ended] [--db <path>] [--dry-run]

  --step     the gc.step_ref of the step this shell is executing, e.g.
             mol-polecat-work.load-context. The run is that step's molecule.
  --root     the run's root bead, for a caller that holds no step of it.
  --reason   why the run ends; appended to the held step in --step mode and
             printed on the result line (required)
  --bead     candidate id, e.g. `.bead_id` from `gc hook --claim --json`. A
             HINT: used only if it verifies as this session's bead for --step.
  --ended    the caller read the root as closed: close only what the run left
             open, and refuse a root that reads live rather than cancel it.
  --db       the store the run's beads live in, for a caller outside it.
  --dry-run  resolve and report; write nothing and send nothing.

env: GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS name the session in --step mode.
     GC_CITY_PATH (or GC_CITY, GC_CITY_ROOT) names the city; GC_HOME holds
     supervisor.toml and cities.toml.

exit: 0 the run is ended · 1 the run is not ended · 2 refused, nothing written
USAGE
}

# `OPT="$2"; shift 2` hangs the parse loop when the option ends argv.
require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
  case "$2" in
    --step|--root|--reason|--bead|--ended|--db|--dry-run|-h|--help)
      echo "$PROG: $1 requires a value, but the next argument is the option '$2'" >&2
      usage
      exit 2 ;;
  esac
}

STEP=""; ROOT=""; REASON=""; HINT=""; ENDED=0; DB=""; DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --step)    require_value "$@"; STEP="$2";   shift 2 ;;
    --root)    require_value "$@"; ROOT="$2";   shift 2 ;;
    --reason)  require_value "$@"; REASON="$2"; shift 2 ;;
    --bead)    require_value "$@"; HINT="$2";   shift 2 ;;
    --ended)   ENDED=1; shift ;;
    --db)      require_value "$@"; DB="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 2 ;;
    *)         echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ -n "$STEP" ] && [ -n "$ROOT" ]; then
  echo "$PROG: --step and --root name the run two ways; pass one" >&2
  exit 2
fi
if [ "$ENDED" = 1 ] && [ -n "$STEP" ]; then
  echo "$PROG: --ended names a run by its closed root; pass --root" >&2
  exit 2
fi
if [ -z "$STEP" ] && [ -z "$ROOT" ]; then
  echo "$PROG: name the run with --step (the step this shell is executing) or --root" >&2
  usage
  exit 2
fi
case "$STEP" in
  '{{'*'}}')
    echo "$PROG: --step was passed unsubstituted ('$STEP'); the pour did not render it" >&2
    exit 2 ;;
  *[!A-Za-z0-9._-]*)
    echo "$PROG: --step must contain only [A-Za-z0-9._-] (got '$STEP')" >&2
    exit 2 ;;
esac
case "$ROOT" in
  *[!A-Za-z0-9._-]*)
    echo "$PROG: --root must contain only [A-Za-z0-9._-] (got '$ROOT')" >&2
    exit 2 ;;
esac
# --bead is only a hint, so one that names no bead, such as a placeholder left
# unsubstituted, is reported and the store resolves the step instead.
case "$HINT" in
  *[!A-Za-z0-9._-]*)
    echo "$PROG: NOTE: --bead '$HINT' is not a bead id; resolving from the store" >&2
    HINT="" ;;
esac
if [ -z "$REASON" ]; then
  echo "$PROG: --reason is required; a run ended for no stated reason cannot be audited" >&2
  usage
  exit 2
fi

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }

# bd_json swallows gc's exit status through its pipe, so a failed read and an
# empty one arrive as the same empty string. bd_json_array fails on a non-zero
# command or a payload that is not a JSON array (bd answers an object when
# nothing resolves), so "nothing is open" is never read off an unread store.
bd_json_array() { # <bd args...> -> the array on stdout; non-zero on a failed read or a non-array payload
  local out
  out=$(bd_json "$@") || return 1
  printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$out"
}

TARGET=""
if [ -n "$STEP" ]; then
  IDENTITIES=$(printf '%s\n%s\n%s\n' \
    "${GC_SESSION_NAME:-}" "${GC_SESSION_ID:-}" "${GC_ALIAS:-}" | awk 'NF && !seen[$0]++')
  if [ -z "$IDENTITIES" ]; then
    echo "$PROG: no session identity in the environment (GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS all unset), so no step can be proven this session's; nothing was cancelled" >&2
    exit 2
  fi

  # `index` is exact element equality; `inside` and `contains` match
  # substrings, which would let session lx-zzk own lx-zzk9's bead.
  verify() { # <id> -> its status when it is this session's bead for $STEP
    local json
    [ -n "$1" ] || return 1
    # shellcheck disable=SC2086  # ${DB:+--db "$DB"} expands to 0 or 2 space-free fields
    json=$(bd_json show "$1" ${DB:+--db "$DB"})
    [ -n "$json" ] || return 1
    printf '%s' "$json" | jq -r --arg step "$STEP" --arg ids "$IDENTITIES" '
      ($ids | split("\n") | map(select(. != ""))) as $me
      | .[0] as $b
      | if $b == null then empty
        elif (($b.metadata["gc.step_ref"] // "") != $step) then empty
        elif (($me | index($b.assignee // "")) == null) then empty
        else ($b.status // "") end
    ' 2>/dev/null
  }

  discover() { # <status> -> this session's ids for $STEP at that status
    local ident json
    while IFS= read -r ident; do
      [ -n "$ident" ] || continue
      # shellcheck disable=SC2086  # ${DB:+--db "$DB"} expands to 0 or 2 space-free fields
      json=$(bd_json list --status="$1" --assignee="$ident" --limit=0 ${DB:+--db "$DB"})
      [ -n "$json" ] || continue
      printf '%s' "$json" | jq -r --arg step "$STEP" '
        if type == "array" then
          .[] | select((.metadata["gc.step_ref"] // "") == $step) | .id
        else empty end
      ' 2>/dev/null
    done <<< "$IDENTITIES"
  }

  if [ -n "$HINT" ]; then
    case "$(verify "$HINT")" in
      in_progress|open|blocked|closed) TARGET="$HINT" ;;
      *) echo "$PROG: NOTE: --bead $HINT is not this session's bead for $STEP; resolving from the store" >&2 ;;
    esac
  fi
  if [ -z "$TARGET" ]; then
    for tier in in_progress open blocked; do
      FOUND=$(discover "$tier" | sort -u)
      N=$(printf '%s\n' "$FOUND" | awk 'NF' | wc -l | tr -d ' ')
      if [ "$N" -eq 1 ]; then
        TARGET="$FOUND"
        break
      elif [ "$N" -gt 1 ]; then
        echo "$PROG: $N $tier beads match step '$STEP' for this session: $(printf '%s' "$FOUND" | tr '\n' ' ')" >&2
        echo "$PROG: refusing to guess which run this shell is executing; pass the claimed step as --bead. Nothing was cancelled." >&2
        exit 2
      fi
    done
  fi
  if [ -z "$TARGET" ]; then
    echo "$PROG: cannot identify this session's bead for step '$STEP' (identities tried: $(printf '%s' "$IDENTITIES" | tr '\n' ' ')); nothing was cancelled" >&2
    exit 2
  fi
  # shellcheck disable=SC2086  # ${DB:+--db "$DB"} expands to 0 or 2 space-free fields
  if ! TARGET_JSON=$(bd_json_array show "$TARGET" ${DB:+--db "$DB"}); then
    echo "$PROG: could not read $TARGET to find its run; nothing was cancelled" >&2
    exit 1
  fi
  ROOT=$(printf '%s' "$TARGET_JSON" | jq -r '.[0].metadata["gc.root_bead_id"] // empty' 2>/dev/null)
  if [ -z "$ROOT" ]; then
    echo "$PROG: $TARGET ($STEP) carries no gc.root_bead_id, so it names no run; nothing was cancelled" >&2
    exit 2
  fi
fi

# gascity's own test for a workflow root: gc.kind=workflow or
# gc.formula_contract=graph.v2.
# shellcheck disable=SC2086  # ${DB:+--db "$DB"} expands to 0 or 2 space-free fields
if ! ROOT_JSON=$(bd_json_array show "$ROOT" ${DB:+--db "$DB"}); then
  echo "$PROG: could not read root $ROOT; nothing was cancelled" >&2
  exit 1
fi
IS_ROOT=$(printf '%s' "$ROOT_JSON" | jq -r '
  .[0] as $r
  | if $r == null then "missing"
    elif ((($r.metadata["gc.kind"] // "") | tostring | ascii_downcase) == "workflow")
      or ((($r.metadata["gc.formula_contract"] // "") | tostring | ascii_downcase) == "graph.v2")
    then "root" else "other" end' 2>/dev/null)
case "$IS_ROOT" in
  root) ;;
  missing)
    echo "$PROG: no bead $ROOT in this store; nothing was cancelled" >&2
    exit 2 ;;
  *)
    echo "$PROG: $ROOT is not a workflow root (neither gc.kind=workflow nor gc.formula_contract=graph.v2); nothing was cancelled" >&2
    exit 2 ;;
esac

ROOT_CLOSED=0
[ "$(printf '%s' "$ROOT_JSON" | jq -r '.[0].status // ""' 2>/dev/null)" = "closed" ] && ROOT_CLOSED=1
if [ "$ENDED" = 1 ] && [ "$ROOT_CLOSED" = 0 ]; then
  echo "$PROG: root $ROOT does not read closed, and --ended ends only a run that is over; nothing was cancelled" >&2
  exit 2
fi

if [ "$DRY_RUN" = "1" ]; then
  if [ "$ROOT_CLOSED" = 1 ]; then
    echo "$PROG: DRY RUN: run $ROOT has ended; would close any member it left open: $REASON"
  else
    echo "$PROG: DRY RUN: would cancel run $ROOT${TARGET:+, whose step $TARGET ($STEP) this session holds}: $REASON"
  fi
  exit 0
fi

WHO="${GC_SESSION_NAME:-${GC_SESSION_ID:-${GC_ALIAS:-unknown session}}}"
if [ -n "$TARGET" ]; then
  # shellcheck disable=SC2086  # ${DB:+--db "$DB"} expands to 0 or 2 space-free fields
  gc bd update "$TARGET" ${DB:+--db "$DB"} --append-notes "Declined at $STEP by $WHO: $REASON. Cancelling run $ROOT through gascity." >/dev/null 2>&1 \
    || echo "$PROG: NOTE: the reason did not land on $TARGET; the result line below still records it" >&2
fi

# The address the supervisor serves, derived as gctk's internal/daemon derives
# it: [supervisor] bind and port in $GC_HOME/supervisor.toml, defaulting to
# 127.0.0.1:8372, a wildcard bind read as loopback.
supervisor_value() { # <key> -> the scalar under [supervisor], quotes stripped
  awk -v want="$1" '
    /^[[:space:]]*\[/ { in_sup = ($0 ~ /^[[:space:]]*\[supervisor\][[:space:]]*$/); next }
    in_sup && $0 ~ "^[[:space:]]*" want "[[:space:]]*=" {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]*$/, "", v)
      gsub(/^"|"$/, "", v); print v; exit
    }' "${GC_HOME:-$HOME/.gc}/supervisor.toml" 2>/dev/null
}
api_base() {
  local bind port
  bind=$(supervisor_value bind); port=$(supervisor_value port)
  case "$port" in ''|*[!0-9]*) port=8372 ;; esac
  case "$bind" in
    ''|0.0.0.0) bind=127.0.0.1 ;;
    '::'|'[::]') bind='[::1]' ;;
    '['*) ;;
    *:*) bind="[$bind]" ;;
  esac
  printf 'http://%s:%s' "$bind" "$port"
}
# The city the supervisor registered at this path in $GC_HOME/cities.toml, else
# the path's basename, the name the supervisor gives an unnamed city.
city_name() {
  local path name
  path="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
  path="${path%/}"
  [ -n "$path" ] || return 1
  name=$(awk -v want="$path" '
    /^\[\[cities\]\]/ { if (p == want && n != "") { print n; exit } p = ""; n = ""; blk = 1; next }
    /^\[/             { if (p == want && n != "") { print n; exit } blk = 0; next }
    blk && /^[[:space:]]*path[[:space:]]*=/ { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); p = v }
    blk && /^[[:space:]]*name[[:space:]]*=/ { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); n = v }
    END { if (p == want && n != "") print n }' "${GC_HOME:-$HOME/.gc}/cities.toml" 2>/dev/null | head -n 1)
  [ -n "$name" ] || name=$(basename "$path")
  printf '%s' "$name"
}

TERMINAL=$ROOT_CLOSED
if [ "$TERMINAL" = 0 ]; then
  if ! CITY=$(city_name); then
    echo "$PROG: no city path in the environment (GC_CITY_PATH, GC_CITY, GC_CITY_ROOT all unset), so there is no city to send the cancel to; run $ROOT is not cancelled" >&2
    exit 1
  fi
  URL="$(api_base)/v0/city/$CITY/runs/$ROOT/cancel"

  ATTEMPTS="${GC_RUN_CANCEL_ATTEMPTS:-3}"
  case "$ATTEMPTS" in ''|*[!0-9]*|0) ATTEMPTS=3 ;; esac
  WAIT="${GC_RUN_CANCEL_BACKOFF:-5}"
  case "$WAIT" in ''|*[!0-9]*) WAIT=5 ;; esac
  BODY=$(mktemp "${TMPDIR:-/tmp}/gctk-run-cancel.XXXXXX") || { echo "$PROG: could not create a temp file for the answer; run $ROOT is not cancelled" >&2; exit 1; }
  trap 'rm -f "$BODY"' EXIT

  attempt=1
  while :; do
    : > "$BODY"
    CODE=$(curl -s -o "$BODY" -w '%{http_code}' -X POST -H 'X-GC-Request: true' \
      --max-time "${GC_RUN_CANCEL_TIMEOUT:-60}" "$URL" 2>/dev/null) || CODE="${CODE:-000}"
    DETAIL=$(scrub < "$BODY" | jq -r '.detail // empty' 2>/dev/null)
    case "$CODE" in
      200|202)
        CLOSED=$(scrub < "$BODY" | jq -r '.closed // empty' 2>/dev/null)
        echo "$PROG: cancelled run $ROOT${CLOSED:+ ($CLOSED beads closed)}: $REASON"
        exit 0 ;;
      409)
        TERMINAL=1
        break ;;
      404)
        echo "$PROG: gascity knows no run $ROOT (${DETAIL:-404 from $URL}); it is not cancelled" >&2
        exit 1 ;;
      5*|000)
        if [ "$attempt" -ge "$ATTEMPTS" ]; then
          echo "$PROG: run $ROOT is not cancelled: the supervisor answered ${CODE/#000/no connection} ${DETAIL:+($DETAIL) }on each of $ATTEMPTS attempts at $URL" >&2
          exit 1
        fi
        sleep $((WAIT * attempt))
        attempt=$((attempt + 1)) ;;
      *)
        echo "$PROG: run $ROOT is not cancelled: the supervisor answered $CODE ${DETAIL:+($DETAIL) }at $URL" >&2
        exit 1 ;;
    esac
  done
fi

# The run is already terminal: its root read closed, or the cancel answered 409.
# The cancel closes no member of a closed root, so any member still standing is
# closed here.
[ "$TERMINAL" = 1 ] || exit 1
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
# shellcheck disable=SC2086  # ${DB:+--db "$DB"} expands to 0 or 2 space-free fields
if ! LEFT=$(bd_json_array list --metadata-field "gc.root_bead_id=$ROOT" --status="$LIVE_STATUSES" --limit=0 ${DB:+--db "$DB"}); then
  echo "$PROG: run $ROOT is already terminal, but its members could not be listed, so none can be proven closed" >&2
  exit 1
fi
NLEFT=$(printf '%s' "$LEFT" | jq 'length' 2>/dev/null)
if [ "${NLEFT:-0}" = "0" ]; then
  echo "$PROG: run $ROOT had already ended: $REASON"
  exit 0
fi
WORK=$(printf '%s' "$LEFT" | jq -r '[ .[] | select(((.metadata.branch // "") != "") or ((.metadata.merge_result // "") != "")) | .id ] | join(" ")' 2>/dev/null)
if [ -n "$WORK" ]; then
  echo "$PROG: run $ROOT is closed but leaves $NLEFT member(s) open, and $WORK carries a branch or a merge_result. That is a work bead, which only the refinery closes, so nothing was closed." >&2
  exit 2
fi
if ! gc convoy delete "$ROOT" --force >/dev/null 2>&1; then
  echo "$PROG: run $ROOT is closed but leaves $NLEFT member(s) open, and gc convoy delete $ROOT --force failed" >&2
  exit 1
fi
if ! LEFT=$(bd_json_array list --metadata-field "gc.root_bead_id=$ROOT" --status="$LIVE_STATUSES" --limit=0 ${DB:+--db "$DB"}) \
   || [ "$(printf '%s' "$LEFT" | jq 'length' 2>/dev/null)" != "0" ]; then
  echo "$PROG: gc convoy delete $ROOT --force ran, but members of run $ROOT still read open" >&2
  exit 1
fi
echo "$PROG: run $ROOT had already ended; gascity closed the $NLEFT member(s) it left open: $REASON"
exit 0
