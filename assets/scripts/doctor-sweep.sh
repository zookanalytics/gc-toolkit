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
#   nothing live, sweep or retry due     start one detached     state=started
#   nothing live, none due yet           nothing                state=idle
#   in flight                            report progress        state=running
#   finished                             collect it             state=complete
#   finished badly, or bad payload       a FAILED scan          state=failed
#   past its bound                       kill it, name the check state=exceeded
#   cannot sweep at all                  say why, start nothing state=blocked
#
# The bound is enforced here rather than by `timeout`, which is what lets it
# exceed the harness ceiling. A sweep that never finishes still ends in a state
# the patrol escalates, carrying its elapsed time and the check it died in.
#
# Starts are capped per interval. An ordinary sweep opens a window; a run that
# ends failed or exceeded earns one retry on the next pass (up to
# GC_DOCTOR_SWEEP_MAX_ATTEMPTS starts), so a sweep that dies early no longer
# burns the whole interval, while a completed run arms no retry.
#
# Output is `key=value` lines with `state=` first. Exit 0 carries a report about
# a sweep; exit 2 means none ran and none can right now — a `blocked` report, or
# a usage error with no report at all. Both are a failed scan to the caller.
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: doctor-sweep.sh [--status]
       (default)   advance the sweep: collect a finished run, or start one
                   once the interval has passed
       --status    report the current state; never starts, kills, or collects
env:   GC_DOCTOR_SWEEP_INTERVAL      seconds between sweeps (default 3600)
       GC_DOCTOR_SWEEP_MAX_ATTEMPTS  sweep starts per interval (default 2, min 1)
       GC_DOCTOR_SWEEP_BOUND         seconds a sweep may run (default 1800)
       GC_DOCTOR_SWEEP_STATE_DIR     where the run record lives
       GC_DOCTOR_SWEEP_NO_SYSTEMD    set to skip the transient user service and
                                     launch with setsid/nohup instead
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
# said out loud. Every pour site passes the interval, and an omitted declared
# var renders its default, so a number is what normally arrives. A malformed
# value must still sweep hourly rather than read as zero and sweep every pass.
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
# At most this many sweep starts per interval; the one over the ordinary hourly
# start is the retry a failed run earns. Clamped to 1 so a zero or low value
# cannot disable sweeping.
MAX_ATTEMPTS=""
resolve_num MAX_ATTEMPTS "${GC_DOCTOR_SWEEP_MAX_ATTEMPTS:-}" 2 GC_DOCTOR_SWEEP_MAX_ATTEMPTS
[ "$MAX_ATTEMPTS" -lt 1 ] && MAX_ATTEMPTS=1

CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
DEFAULT_STATE_DIR="${CITY:+$CITY/.gc/runtime}"
DEFAULT_STATE_DIR="${DEFAULT_STATE_DIR:-${TMPDIR:-/tmp}/gc}/doctor-sweep"
STATE_DIR="${GC_DOCTOR_SWEEP_STATE_DIR:-$DEFAULT_STATE_DIR}"

RUN="$STATE_DIR/current"
STAMP="$STATE_DIR/last-start"
OUTCOME="$STATE_DIR/last-outcome"

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

# A collected run records its outcome so the next window's gate can arm one
# retry after a failure. Advance mode only — --status must not write it. A
# collection records `failed`, and only the complete path upgrades it to
# `complete`, so every abnormal end (bad rc, invalid payload, a vanished
# wrapper, an exceeded bound) is the failure that earns the retry.
collect() { # <complete|failed>
  [ "$MODE" = "status" ] && return 0
  : > "$RUN/collected"
  printf '%s' "$1" > "$OUTCOME"
}

# The array is the shape the counts consume, and demanding it is what keeps a
# drifted payload from reading as a clean sweep: a `results` key holding null
# satisfies a mere existence check and then counts zero checks, zero findings.
results_array() { jq -e '.results | type == "array"' "$1" >/dev/null 2>&1; }

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
    collect failed

    if [ "$RC" != "0" ] && [ "$RC" != "1" ]; then
      # rc 1 is doctor's normal "findings exist"; anything else is a failure.
      report failed "reason=doctor-rc" "rc=$RC" "elapsed=$ELAPSED" \
        "stderr=$RUN/stderr.log"
      exit 0
    fi

    if ! results_array "$PAYLOAD"; then
      # One retry through the scrub before calling it a failure: a stray
      # control byte in one message must not read as a drifted schema.
      if [ -f "$PAYLOAD" ] && CLEAN="$(mktemp "$RUN/.payload.XXXXXX" 2>/dev/null)"; then
        scrub < "$PAYLOAD" > "$CLEAN" 2>/dev/null
        if results_array "$CLEAN"; then
          mv "$CLEAN" "$PAYLOAD"
          NOTE="${NOTE:+$NOTE; }payload carried control characters and was scrubbed"
        else
          rm -f "$CLEAN"
        fi
      fi
    fi
    if ! results_array "$PAYLOAD"; then
      report failed "reason=payload-invalid" "rc=$RC" "elapsed=$ELAPSED" \
        "payload=$PAYLOAD" "stderr=$RUN/stderr.log"
      exit 0
    fi

    # Indexes `.results` as the array the guard proved it is, so an array
    # holding something other than check results fails the filters rather than
    # counting nothing. An empty TSV is that failure: a real sweep, even one
    # with no checks at all, renders four fields.
    COUNTS="$(jq -r '
      .results as $r
      | [ ($r | length),
          ([ $r[] | select(.status != "ok") ] | length),
          ([ $r[] | select(.timed_out == true) ] | length),
          ([ $r[] | select(.timed_out == true) | .name ] | join(","))
        ] | @tsv' "$PAYLOAD" 2>/dev/null)"
    if [ -z "$COUNTS" ]; then
      report failed "reason=payload-invalid" "rc=$RC" "elapsed=$ELAPSED" \
        "payload=$PAYLOAD" "stderr=$RUN/stderr.log"
      exit 0
    fi
    CHECKS="$(printf '%s' "$COUNTS" | cut -f1)"
    FINDINGS="$(printf '%s' "$COUNTS" | cut -f2)"
    ABANDONED="$(printf '%s' "$COUNTS" | cut -f3)"
    ABANDONED_NAMES="$(printf '%s' "$COUNTS" | cut -f4)"
    collect complete
    report complete "rc=$RC" "elapsed=$ELAPSED" "payload=$PAYLOAD" \
      "checks=$CHECKS" "findings=$FINDINGS" \
      "abandoned=$ABANDONED" "abandoned_checks=$ABANDONED_NAMES"
    exit 0
  fi

  # No rc yet. Either it is still working, or the wrapper died without one.
  if [ -z "$PID" ]; then
    if [ "$ELAPSED" -lt 30 ]; then
      report running "elapsed=$ELAPSED" "bound=$BOUND" "current_check=starting"
      exit 0
    fi
    collect failed
    report failed "reason=never-started" "elapsed=$ELAPSED"
    exit 0
  fi

  if ! kill -0 "$PID" 2>/dev/null; then
    collect failed
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
    collect failed
    report exceeded "elapsed=$ELAPSED" "bound=$BOUND" "pid=$PID" \
      "last_check=${CHECK:-unknown}" "stderr=$RUN/stderr.log"
    exit 0
  fi

  report running "elapsed=$ELAPSED" "bound=$BOUND" "pid=$PID" \
    "current_check=${CHECK:-builtin}"
  exit 0
fi

# ------------------------------------------------------------ nothing live --

WINDOW="$STATE_DIR/window-start"
ATTEMPTS_FILE="$STATE_DIR/attempts"
WINDOW_START="$(read_file "$WINDOW")"
ATTEMPTS="$(read_file "$ATTEMPTS_FILE")"
LAST_OUTCOME="$(read_file "$OUTCOME")"
# Both feed the arithmetic below; a non-numeric value falls back to the
# last-start gate rather than reading as zero and starting every pass.
case "$WINDOW_START" in ''|*[!0-9]*) WINDOW_START="" ;; esac
case "$ATTEMPTS" in ''|*[!0-9]*) ATTEMPTS="" ;; esac

SINCE=""
[ -n "$LAST_START" ] && SINCE=$(( NOW - LAST_START ))

# window-start + attempts cap starts to MAX_ATTEMPTS per INTERVAL and let one
# of them follow a failed run, so a sweep that dies early no longer burns the
# whole interval. last-start is the fallback when that pair is missing or
# corrupt: it holds the hourly ceiling by itself, so a lost pair costs the
# retry, never a hot loop.
DO_START=0
NEW_WINDOW=""     # window-start to stamp on a start; empty leaves it in place
NEW_ATTEMPTS=""   # attempts to stamp on a start
NEXT_IN=""        # seconds until the window reopens, for the idle report
if [ -z "$WINDOW_START" ] || [ -z "$ATTEMPTS" ]; then
  # Missing or corrupt pair: degrade to one start per interval on last-start.
  if [ -n "$SINCE" ] && [ "$SINCE" -lt "$INTERVAL" ]; then
    NEXT_IN=$(( INTERVAL - SINCE ))
  else
    DO_START=1; NEW_WINDOW="$NOW"; NEW_ATTEMPTS=1
  fi
elif [ "$(( NOW - WINDOW_START ))" -ge "$INTERVAL" ]; then
  # The window has elapsed: the ordinary start opens a fresh one.
  DO_START=1; NEW_WINDOW="$NOW"; NEW_ATTEMPTS=1
elif [ "$ATTEMPTS" -lt "$MAX_ATTEMPTS" ] && [ "$LAST_OUTCOME" = "failed" ]; then
  # One retry inside the open window after a failed run. Leaving window-start
  # in place is what makes the per-interval ceiling hold however runs fail.
  DO_START=1; NEW_ATTEMPTS=$(( ATTEMPTS + 1 ))
else
  # Window still open and either the cap is spent or the last run completed.
  NEXT_IN=$(( INTERVAL - ( NOW - WINDOW_START ) ))
fi

if [ "$DO_START" -eq 0 ]; then
  report idle "next_in=$NEXT_IN" "interval=$INTERVAL" "since_last=${SINCE:-never}"
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

# The sweep has to outlive the session that starts it. The deacon runs this on
# a patrol cycle whose session is torn down and replaced each cycle, and that
# teardown SIGKILLs the pane's whole process tree, walking descendants and
# process-group members to catch children that called setsid(). setsid alone
# does not help: the detached child reparents to the session harness, a
# child-subreaper, and so stays inside that tree.
#
# On a systemd host the sweep runs as a transient user service instead, so the
# user manager owns it, outside the session's process tree, process group, and
# cgroup. The teardown cannot reach it there. A service starts with a clean
# environment, so the caller's is forwarded: gc doctor needs the city context
# the caller holds. With no reachable user manager, or with
# GC_DOCTOR_SWEEP_NO_SYSTEMD set, it falls back to setsid then nohup, which is
# enough to outlive the harness ceiling on a host with no per-session teardown.
#
# The body is a file, not an inline `sh -c` string, because systemd expands $$
# and $VAR in a unit's argv and would corrupt the recorded pid; read from a
# file, sh sees the body unexpanded. The wrapper records its own pid before the
# sweep and writes `rc` LAST, by rename, so a reader never sees a half-written
# payload behind a finished marker.
SWEEP_BODY="$RUN/sweep.sh"
cat > "$SWEEP_BODY" <<'BODY'
printf %s "$$" > "$5"
"$1" doctor --json > "$2" 2> "$3"
rc=$?
date +%s > "$6"
printf %s "$rc" > "$4.tmp" && mv "$4.tmp" "$4"
BODY
SWEEP_ARGV=(sh "$SWEEP_BODY" "$GC_BIN" "$RUN/payload.json" "$RUN/stderr.log" \
  "$RUN/rc" "$RUN/pid" "$RUN/finished_at")

launched=0
if [ -z "${GC_DOCTOR_SWEEP_NO_SYSTEMD:-}" ] \
   && command -v systemd-run >/dev/null 2>&1 \
   && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  # Forward the caller's environment faithfully: env -0 keeps values that hold
  # spaces or newlines whole, and only POSIX-named vars pass so a shell-function
  # export cannot make systemd reject the whole launch.
  SETENV=()
  while IFS= read -r -d '' kv; do
    case ${kv%%=*} in ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*) continue ;; esac
    SETENV+=(--setenv="$kv")
  done < <(env -0 2>/dev/null)
  if [ "${#SETENV[@]}" -gt 0 ] \
     && systemd-run --user --collect --quiet \
          --description="gc doctor sweep (survives session teardown)" \
          "${SETENV[@]}" "${SWEEP_ARGV[@]}" >/dev/null 2>&1; then
    launched=1
  fi
fi
if [ "$launched" -eq 0 ]; then
  LAUNCH=(setsid)
  command -v setsid >/dev/null 2>&1 || LAUNCH=(nohup)
  "${LAUNCH[@]}" "${SWEEP_ARGV[@]}" </dev/null >/dev/null 2>&1 &
fi

printf '%s' "$NOW" > "$STAMP"
[ -n "$NEW_WINDOW" ] && printf '%s' "$NEW_WINDOW" > "$WINDOW"
printf '%s' "$NEW_ATTEMPTS" > "$ATTEMPTS_FILE"
report started "bound=$BOUND" "interval=$INTERVAL" "run=$RUN"
exit 0
