#!/usr/bin/env bash
# doctor-sweep — the deacon patrol's `gc doctor` runner.
#
# A full sweep costs ~10 minutes at this city's steady load, and the agent
# harness kills any single call at 600s. So the sweep cannot run in the
# foreground at all: `timeout N gc doctor --json` is killed by the harness
# before `timeout` fires, the payload is empty, and the patrol reports "not
# clean" with nothing read. Raising N cannot fix that — 600s is a ceiling, not
# a budget.
#
# The sweep therefore runs DETACHED and is read on a later pass. One call does
# one thing and returns at once:
#
#   nothing in flight, interval elapsed  start one detached     state=started
#   nothing in flight, interval not up   nothing                state=idle
#   in flight                            report progress        state=running
#   finished                             collect it             state=complete
#   finished badly, or bad payload       a FAILED scan          state=failed
#   past its bound                       kill it, name the check state=exceeded
#
# The bound is enforced here rather than by `timeout`, which is what lets it
# exceed the harness ceiling. A sweep that never finishes still ends in a state
# the patrol escalates, carrying its elapsed time and the check it died in.
#
# Output is `key=value` lines with `state=` first. Exit 0 on any report, 2 when
# no report is possible.
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: doctor-sweep.sh [--status]
       (default)   advance the sweep: collect a finished run, or start one
                   once the interval has passed
       --status    report the current state; never starts, kills, or collects
env:   GC_DOCTOR_SWEEP_INTERVAL   seconds between sweeps (default 3600)
       GC_DOCTOR_SWEEP_BOUND      seconds a sweep may run (default 1800)
       GC_DOCTOR_SWEEP_STATE_DIR  where the run record lives
USAGE
}

MODE="advance"
case "${1:-}" in
  "")        ;;
  --status)  MODE="status" ;;
  -h|--help) usage; exit 0 ;;
  *)         usage; exit 2 ;;
esac

NOTE=""

# A supplied value that is not a plain integer is REPLACED by the default and
# said out loud. The patrol pours `--root-only`, which substitutes no formula
# var, so an unsubstituted `{{doctor_interval}}` reaches this script verbatim;
# it must sweep hourly anyway rather than read as zero and sweep every pass.
# Assigns through the caller's variable rather than stdout: the note is the
# point, and a command substitution would drop it with the subshell.
resolve_num() { # <var-name> <supplied> <default> <setting-name>
  case "$2" in
    ''|*[!0-9]*)
      [ -n "$2" ] && NOTE="${NOTE:+$NOTE; }$4='$2' is not a number, using $3"
      printf -v "$1" '%s' "$3" ;;
    *) printf -v "$1" '%s' "$2" ;;
  esac
}

INTERVAL=""; BOUND=""
# Hourly: at the measured ~600s mean the sweep is then a 16% duty cycle instead
# of the deacon's main activity.
resolve_num INTERVAL "${GC_DOCTOR_SWEEP_INTERVAL:-}" 3600 GC_DOCTOR_SWEEP_INTERVAL
# ~3x the observed mean, so the check count can grow without re-arguing it.
resolve_num BOUND "${GC_DOCTOR_SWEEP_BOUND:-}" 1800 GC_DOCTOR_SWEEP_BOUND

CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
DEFAULT_STATE_DIR="${CITY:+$CITY/.gc/runtime}"
DEFAULT_STATE_DIR="${DEFAULT_STATE_DIR:-${TMPDIR:-/tmp}/gc}/doctor-sweep"
STATE_DIR="${GC_DOCTOR_SWEEP_STATE_DIR:-$DEFAULT_STATE_DIR}"

RUN="$STATE_DIR/current"
STAMP="$STATE_DIR/last-start"

NOW="$(date +%s)"

report() { # <state> [key=value]...
  local st="$1" f; shift
  printf 'state=%s\n' "$st"
  for f in "$@"; do printf '%s\n' "$f"; done
  [ -n "$NOTE" ] && printf 'note=%s\n' "$NOTE"
  return 0
}

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

read_file() { [ -f "$1" ] && tr -d '\n' < "$1" || printf ''; }

# Every process under <root>, as "<pid><TAB><args>". ps output is not ordered
# parent-before-child, so the marking sweeps until the tree stops growing.
descendants() { # <root-pid>
  [ -n "${1:-}" ] || return 0
  ps -eo pid=,ppid=,args= 2>/dev/null | awk -v root="$1" '
    { p=$1; pp=$2; $1=""; $2=""; sub(/^[ \t]+/, ""); n++; PID[n]=p; PPID[n]=pp; ARGS[n]=$0 }
    END {
      mark[root] = 1
      for (pass = 0; pass < 16; pass++)
        for (i = 1; i <= n; i++)
          if (mark[PPID[i]]) mark[PID[i]] = 1
      for (i = 1; i <= n; i++)
        if (mark[PID[i]] && PID[i] != root) printf "%s\t%s\n", PID[i], ARGS[i]
    }'
}

# Which check the sweep is inside, read off the live process tree. Pack checks
# are `<rig>/doctor/check-<name>/run.sh`; doctor's built-in checks fork nothing,
# so an empty answer means "in a built-in check", not "idle".
running_check() { # <root-pid>
  descendants "$1" \
    | sed -n 's|.*/doctor/\(check-[A-Za-z0-9._+-]*\)/run\.sh.*|\1|p' \
    | head -1
}

kill_tree() { # <root-pid>
  local root="$1" pids p
  pids="$(descendants "$root" | cut -f1)"
  # Children first: a parent that outlives them cannot fork a replacement.
  for p in $pids; do kill -TERM "$p" 2>/dev/null; done
  kill -TERM "$root" 2>/dev/null
  sleep 2
  for p in $pids; do kill -KILL "$p" 2>/dev/null; done
  kill -KILL "$root" 2>/dev/null
}

STATE_DIR_OK=1
mkdir -p "$STATE_DIR" 2>/dev/null || STATE_DIR_OK=0
# `-w` too: mkdir -p succeeds on an existing unwritable directory.
{ [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ]; } || STATE_DIR_OK=0
if [ "$STATE_DIR_OK" -eq 0 ]; then
  report blocked "reason=state-dir-unwritable" "state_dir=$STATE_DIR"
  exit 2
fi

STARTED_AT="$(read_file "$RUN/started_at")"
LAST_START="$(read_file "$STAMP")"
# Both are read straight into arithmetic below, and an unreadable stamp must
# cost one skipped sweep rather than every future one.
case "$STARTED_AT" in ''|*[!0-9]*) STARTED_AT="" ;; esac
case "$LAST_START" in ''|*[!0-9]*) LAST_START="" ;; esac
COLLECTED=0
[ -f "$RUN/collected" ] && COLLECTED=1
IN_FLIGHT=0
{ [ -d "$RUN" ] && [ "$COLLECTED" -eq 0 ] && [ -n "$STARTED_AT" ]; } && IN_FLIGHT=1

# ---------------------------------------------------------------- in flight --

if [ "$IN_FLIGHT" -eq 1 ]; then
  ELAPSED=$(( NOW - STARTED_AT ))
  PID="$(read_file "$RUN/pid")"
  RC="$(read_file "$RUN/rc")"
  PAYLOAD="$RUN/payload.json"

  # `rc` is written last and moved into place, so its presence proves the
  # payload is whole.
  if [ -n "$RC" ]; then
    FINISHED="$(read_file "$RUN/finished_at")"
    [ -n "$FINISHED" ] && ELAPSED=$(( FINISHED - STARTED_AT ))
    [ "$MODE" = "status" ] || : > "$RUN/collected"

    if [ "$RC" != "0" ] && [ "$RC" != "1" ]; then
      # rc 1 is doctor's normal "findings exist"; anything else is a failure.
      report failed "reason=doctor-rc" "rc=$RC" "elapsed=$ELAPSED" \
        "stderr=$RUN/stderr.log"
      exit 0
    fi

    if ! jq -e 'has("results")' "$PAYLOAD" >/dev/null 2>&1; then
      # One retry through the scrub before calling it a failure: a stray
      # control byte in one message must not read as a drifted schema.
      if [ -f "$PAYLOAD" ] && CLEAN="$(mktemp "$RUN/.payload.XXXXXX" 2>/dev/null)"; then
        scrub < "$PAYLOAD" > "$CLEAN" 2>/dev/null
        if jq -e 'has("results")' "$CLEAN" >/dev/null 2>&1; then
          mv "$CLEAN" "$PAYLOAD"
          NOTE="${NOTE:+$NOTE; }payload carried control characters and was scrubbed"
        else
          rm -f "$CLEAN"
        fi
      fi
    fi
    if ! jq -e 'has("results")' "$PAYLOAD" >/dev/null 2>&1; then
      report failed "reason=payload-invalid" "rc=$RC" "elapsed=$ELAPSED" \
        "payload=$PAYLOAD" "stderr=$RUN/stderr.log"
      exit 0
    fi

    COUNTS="$(jq -r '
      [ .results[]? ] as $r
      | [ $r | length,
          ([ $r[] | select(.status != "ok") ] | length),
          ([ $r[] | select(.timed_out == true) ] | length),
          ([ $r[] | select(.timed_out == true) | .name ] | join(","))
        ] | @tsv' "$PAYLOAD" 2>/dev/null)"
    CHECKS="$(printf '%s' "$COUNTS" | cut -f1)"
    FINDINGS="$(printf '%s' "$COUNTS" | cut -f2)"
    ABANDONED="$(printf '%s' "$COUNTS" | cut -f3)"
    ABANDONED_NAMES="$(printf '%s' "$COUNTS" | cut -f4)"
    report complete "rc=$RC" "elapsed=$ELAPSED" "payload=$PAYLOAD" \
      "checks=${CHECKS:-0}" "findings=${FINDINGS:-0}" \
      "abandoned=${ABANDONED:-0}" "abandoned_checks=${ABANDONED_NAMES:-}"
    exit 0
  fi

  # No rc yet. Either it is still working, or the wrapper died without one.
  if [ -z "$PID" ]; then
    if [ "$ELAPSED" -lt 30 ]; then
      report running "elapsed=$ELAPSED" "bound=$BOUND" "current_check=starting"
      exit 0
    fi
    [ "$MODE" = "status" ] || : > "$RUN/collected"
    report failed "reason=never-started" "elapsed=$ELAPSED"
    exit 0
  fi

  if ! kill -0 "$PID" 2>/dev/null; then
    [ "$MODE" = "status" ] || : > "$RUN/collected"
    report failed "reason=sweep-vanished" "elapsed=$ELAPSED" "pid=$PID" \
      "stderr=$RUN/stderr.log"
    exit 0
  fi

  CHECK="$(running_check "$PID")"
  if [ "$ELAPSED" -gt "$BOUND" ]; then
    if [ "$MODE" = "status" ]; then
      report exceeded "elapsed=$ELAPSED" "bound=$BOUND" "pid=$PID" \
        "last_check=${CHECK:-unknown}"
      exit 0
    fi
    kill_tree "$PID"
    : > "$RUN/collected"
    report exceeded "elapsed=$ELAPSED" "bound=$BOUND" "pid=$PID" \
      "last_check=${CHECK:-unknown}" "stderr=$RUN/stderr.log"
    exit 0
  fi

  report running "elapsed=$ELAPSED" "bound=$BOUND" "pid=$PID" \
    "current_check=${CHECK:-builtin}"
  exit 0
fi

# ------------------------------------------------------------ nothing live --

SINCE=""
[ -n "$LAST_START" ] && SINCE=$(( NOW - LAST_START ))

if [ -n "$SINCE" ] && [ "$SINCE" -lt "$INTERVAL" ]; then
  report idle "next_in=$(( INTERVAL - SINCE ))" "interval=$INTERVAL" \
    "since_last=$SINCE"
  exit 0
fi

if [ "$MODE" = "status" ]; then
  report idle "next_in=0" "interval=$INTERVAL" "since_last=${SINCE:-never}"
  exit 0
fi

# Nothing is in flight, so whatever is here is spent: a collected run, or a
# dir left by a start that died before recording anything. Clearing it is what
# lets the next `mkdir` be the start guard. Only a collector reaches here, so
# the clear is not contended.
[ -d "$RUN" ] && rm -rf "$RUN"
if ! mkdir "$RUN" 2>/dev/null; then
  report blocked "reason=run-dir-contended" "run=$RUN"
  exit 2
fi

GC_BIN="$(command -v gc 2>/dev/null)"
if [ -z "$GC_BIN" ]; then
  rm -rf "$RUN"
  report blocked "reason=gc-not-on-path"
  exit 2
fi

printf '%s' "$NOW" > "$RUN/started_at"

# Detached so the harness ceiling cannot reach it: a new session where setsid
# exists, otherwise nohup, which is enough to survive the caller. The wrapper
# records its own pid before the sweep and writes `rc` LAST, by rename, so a
# reader never sees a half-written payload behind a finished marker.
LAUNCH=(setsid)
command -v setsid >/dev/null 2>&1 || LAUNCH=(nohup)
"${LAUNCH[@]}" sh -c '
  printf %s "$$" > "$4"
  "$0" doctor --json > "$1" 2> "$2"
  rc=$?
  date +%s > "$5"
  printf %s "$rc" > "$3.tmp" && mv "$3.tmp" "$3"
' "$GC_BIN" "$RUN/payload.json" "$RUN/stderr.log" "$RUN/rc" "$RUN/pid" \
  "$RUN/finished_at" </dev/null >/dev/null 2>&1 &

printf '%s' "$NOW" > "$STAMP"
report started "bound=$BOUND" "interval=$INTERVAL" "run=$RUN"
exit 0
