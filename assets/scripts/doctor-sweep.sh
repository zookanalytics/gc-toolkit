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
#   due, one already started this hour   hold the cadence       state=throttled
#   due, but the data plane is degraded  stand down for now     state=deferred
#   in flight                            report progress        state=running
#   finished                             collect it             state=complete
#   finished more than an interval ago   discard its payload    state=stale
#   finished badly, or bad payload       a FAILED scan          state=failed
#   past its bound                       kill it, name the check state=exceeded
#   cannot sweep at all                  say why, start nothing state=blocked
#
# The bound is enforced here rather than by `timeout`, which is what lets it
# exceed the harness ceiling. A sweep that never finishes still ends in a state
# the patrol escalates, carrying its elapsed time and the check it died in.
#
# A payload describes the city at the second its sweep finished, and only a pass
# collects it, so a patrol that stops for hours leaves a finished run waiting.
# A run that finished more than one interval before the pass that reaches it is
# reported stale, never complete or failed: its payload and its exit code are
# not handed on, and because its window has elapsed, the next pass is due to
# start a fresh sweep in its place.
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
env:   GC_DOCTOR_SWEEP_INTERVAL      seconds between sweeps, and the age past
                                     which a finished sweep is stale
                                     (default 3600)
       GC_DOCTOR_SWEEP_MAX_ATTEMPTS  sweep starts per interval (default 2, min 1)
       GC_DOCTOR_SWEEP_BOUND         seconds a sweep may run (default 1800)
       GC_DOCTOR_SWEEP_STATE_DIR     where the run record lives
       GC_DOCTOR_SWEEP_NO_SYSTEMD    set to skip the transient user service and
                                     launch with setsid/nohup instead
       GC_DOCTOR_SWEEP_DOLT_PROBE_TIMEOUT  seconds the pre-spawn Dolt health
                                     probe may run; a probe still running then
                                     is unproven and defers nothing (default 90)
       GC_DOCTOR_SWEEP_CADENCE_DIR   where the cross-session cadence lock and
                                     last-start timestamp live (default under
                                     $XDG_RUNTIME_DIR, else a per-uid /tmp path)
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
# The pre-spawn Dolt health probe's bound is a hang guard, not a health signal
# (see dolt_degraded). It is long enough for the probe to report a server it
# cannot reach. That report skips the per-database counts, so it takes the ping,
# `gc rig list` and `gc dolt-cleanup` calls at their caps plus the report's own
# process scans, about a minute. It is short enough that a cut probe still
# leaves this call inside the two minutes the deacon's harness gives a tool call
# that asks for no more.
DOLT_PROBE_TIMEOUT=""
resolve_num DOLT_PROBE_TIMEOUT "${GC_DOCTOR_SWEEP_DOLT_PROBE_TIMEOUT:-}" 90 GC_DOCTOR_SWEEP_DOLT_PROBE_TIMEOUT

CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
DEFAULT_STATE_DIR="${CITY:+$CITY/.gc/runtime}"
DEFAULT_STATE_DIR="${DEFAULT_STATE_DIR:-${TMPDIR:-/tmp}/gc}/doctor-sweep"
STATE_DIR="${GC_DOCTOR_SWEEP_STATE_DIR:-$DEFAULT_STATE_DIR}"

RUN="$STATE_DIR/current"
STAMP="$STATE_DIR/last-start"
OUTCOME="$STATE_DIR/last-outcome"

# The cadence floor's lock and last-start live OUTSIDE STATE_DIR, at a path every
# one of the user's sessions shares and that survives a session recycle, so a
# sweep one session starts is visible to the next even when STATE_DIR is the
# per-session fallback above. XDG_RUNTIME_DIR is the user's systemd runtime dir;
# with none, a fixed per-uid /tmp path stands in. The same place for every
# session is what lets the floor serialize them, independent of STATE_DIR.
CADENCE_DIR="${GC_DOCTOR_SWEEP_CADENCE_DIR:-}"
if [ -z "$CADENCE_DIR" ]; then
  if [ -n "${XDG_RUNTIME_DIR:-}" ]; then CADENCE_DIR="$XDG_RUNTIME_DIR/gc-doctor-sweep"
  else CADENCE_DIR="/tmp/gc-doctor-sweep.$(id -u 2>/dev/null || echo 0)"; fi
fi
CADENCE_STAMP="$CADENCE_DIR/last-start"
CADENCE_LOCK="$CADENCE_DIR/lock"

NOW="$(date +%s)"

report() { # <state> [key=value]...
  local st="$1" f; shift
  printf 'state=%s\n' "$st"
  for f in "$@"; do printf '%s\n' "$f"; done
  [ -n "$NOTE" ] && printf 'note=%s\n' "$NOTE"
  return 0
}

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

read_file() { [ -f "$1" ] && tr -d '\n' < "$1" || printf ''; }

# A collected run records its outcome so the next window's gate can arm one
# retry after a failure. Advance mode only — --status must not write it. A
# collection records `failed`, and only the complete path upgrades it to
# `complete`, so every abnormal end (bad rc, invalid payload, a vanished
# wrapper, an exceeded bound) is the failure that earns the retry. A stale run
# records `stale`, which arms no retry and needs none: its window has elapsed,
# so the next start is the ordinary one.
collect() { # <complete|failed|stale>
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

# Whether Dolt is degraded enough that a sweep must not pile onto it. Prints a
# one-line reason and returns 0 when degraded, 1 when healthy, and 2 when the
# probe proved neither. The verdict reads server.reachable and
# server.latency_ms, the same fields and 5000ms ceiling the deacon patrol's
# dolt-health step uses. The report's wall time is not a Dolt signal. `gc dolt
# health` caps each Dolt call it makes, so a server that cannot answer the ping
# inside its cap reads as unreachable, while the time the whole report takes
# follows host load and the gc calls it makes. A probe still running at its
# bound is therefore unproven, like a missing gc, a failed run, or an unreadable
# answer. Unproven never defers, so a broken or stalled probe cannot disable
# sweeping. The kill-after holds the bound for a probe that ignores TERM.
dolt_degraded() {
  local gcbin out rc reachable latency
  gcbin="$(command -v gc 2>/dev/null)"
  if [ -z "$gcbin" ]; then
    printf 'gc not on PATH'
    return 2
  fi
  out="$(timeout -k 5 "$DOLT_PROBE_TIMEOUT" "$gcbin" dolt health --json 2>/dev/null)"; rc=$?
  case "$rc" in
    0) ;;
    124|137)
      printf 'health probe gave no answer within %ss' "$DOLT_PROBE_TIMEOUT"
      return 2 ;;
    *)
      printf 'health probe exited %s' "$rc"
      return 2 ;;
  esac
  # Not `// empty`: jq's `//` treats boolean false like null, so it would swallow
  # the very `reachable:false` this is looking for. Read the field raw.
  reachable="$(printf '%s' "$out" | jq -r '.server.reachable' 2>/dev/null)"
  if [ "$reachable" = "false" ]; then
    printf 'Dolt server unreachable'
    return 0
  fi
  latency="$(printf '%s' "$out" | jq -r '.server.latency_ms // empty' 2>/dev/null)"
  case "$latency" in
    ''|*[!0-9]*)
      printf 'health probe answer carried no readable server.latency_ms'
      return 2 ;;
    *) if [ "$latency" -gt 5000 ]; then
         printf 'Dolt server latency %sms over 5000ms' "$latency"
         return 0
       fi ;;
  esac
  return 1
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
    # Read into arithmetic below, so an unreadable stamp is dropped like the
    # others rather than aborting the collect.
    case "$FINISHED" in ''|*[!0-9]*) FINISHED="" ;; esac
    [ -n "$FINISHED" ] && ELAPSED=$(( FINISHED - STARTED_AT ))
    # Aged from when the run finished. An unreadable finished_at falls back to
    # started_at, which is never later, so the fallback can only overstate the
    # age: it may discard a current payload, never report a stale one.
    AGE=$(( NOW - ${FINISHED:-$STARTED_AT} ))

    if [ "$AGE" -gt "$INTERVAL" ]; then
      collect stale
      report stale "finished_at=${FINISHED:-unknown}" "age=$AGE" \
        "interval=$INTERVAL"
      exit 0
    fi

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
    report complete "rc=$RC" "elapsed=$ELAPSED" \
      "finished_at=${FINISHED:-unknown}" "age=$AGE" "payload=$PAYLOAD" \
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
    # The wrapper names the signal that ended it when it could catch one; an
    # untrappable kill (SIGKILL, OOM) leaves no file, so say so rather than
    # nothing. launch/unit point a reader at the run's own journal.
    CAUSE="$(read_file "$RUN/cause")"
    LAUNCH="$(read_file "$RUN/launch")"
    UNIT="$(read_file "$RUN/unit")"
    VANISHED=("reason=sweep-vanished" "cause=${CAUSE:-unknown}" \
      "elapsed=$ELAPSED" "pid=$PID")
    [ -n "$LAUNCH" ] && VANISHED+=("launch=$LAUNCH")
    [ -n "$UNIT" ] && VANISHED+=("unit=$UNIT")
    VANISHED+=("stderr=$RUN/stderr.log")
    report failed "${VANISHED[@]}"
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
RETRY=0           # a retry the window authorized: exempt from the cadence floor
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
  DO_START=1; NEW_ATTEMPTS=$(( ATTEMPTS + 1 )); RETRY=1
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

# --------------------------------------------------------------- pre-spawn --
# A start is due. Two last gates stand before spawning a ~10-minute sweep that
# queries every store's Dolt. The Dolt-health gate keeps the sweep off a data
# plane that is already unreachable or overloaded. The cadence floor keeps a
# would-be burst — concurrent sessions, or a rapidly recycled one whose STATE_DIR
# cannot see the last start — collapsed to one sweep per interval. Together they
# stop this health check from driving the data plane it watches into a collapse.

# Dolt degraded. Piling a ~10-minute sweep onto a data plane that is unreachable
# or overloaded is one way this health check amplifies a slowdown; the probe is
# far cheaper than the sweep it gates. This runs before the cadence stamp below,
# so a start deferred here spends no cadence window; window-start and attempts
# are left untouched too, so the same due start — the ordinary hourly one or the
# retry a failed run armed — fires on the next pass once Dolt recovers, with no
# attempt burned on a sweep that never ran. A probe that proved nothing holds
# nothing, and the report says the gate was skipped and why.
DOLT_DETAIL="$(dolt_degraded)"; DOLT_RC=$?
if [ "$DOLT_RC" -eq 0 ]; then
  report deferred "reason=dolt-degraded" "detail=$DOLT_DETAIL"
  exit 0
fi
[ "$DOLT_RC" -eq 2 ] && NOTE="${NOTE:+$NOTE; }Dolt health gate skipped: $DOLT_DETAIL"

# The cadence floor — the one cross-session gate. The in-flight and interval
# guards above read only STATE_DIR, which falls back to a per-session path when
# the city is unset and need not survive a rapidly recycled session; a blind
# STATE_DIR lets concurrent or back-to-back starts each read as the first. The
# floor reads and stamps a shared last-start timestamp under flock, so the check
# and the claim are one atomic step no second starter can slip between. A fresh
# start is refused while the last one sits inside the interval; the retry a
# failed run armed is exempt from the refusal — it was authorized by a STATE_DIR
# this session could read, where the burst cannot arise — but still stamps the
# floor. The gate rests on a file lock, not on any process or query staying
# responsive. If it cannot be taken — no flock, or a runtime dir it cannot write
# — the sweep proceeds rather than go silent, and the report says so.
CADENCE_NOTE=""
if ! command -v flock >/dev/null 2>&1; then
  CADENCE_NOTE="flock not found"
elif ! mkdir -p "$CADENCE_DIR" 2>/dev/null || ! ( : >> "$CADENCE_LOCK" ) 2>/dev/null; then
  CADENCE_NOTE="cannot write $CADENCE_DIR"
else
  CADENCE_THROTTLE=""
  {
    if flock -w 10 9 2>/dev/null; then
      CADENCE_LAST="$(read_file "$CADENCE_STAMP")"
      case "$CADENCE_LAST" in ''|*[!0-9]*) CADENCE_LAST="" ;; esac
      if [ "$RETRY" -eq 0 ] && [ -n "$CADENCE_LAST" ] \
         && [ "$(( NOW - CADENCE_LAST ))" -lt "$INTERVAL" ]; then
        CADENCE_THROTTLE=$(( NOW - CADENCE_LAST ))
      else
        printf '%s' "$NOW" > "$CADENCE_STAMP.tmp" 2>/dev/null \
          && mv "$CADENCE_STAMP.tmp" "$CADENCE_STAMP" 2>/dev/null
      fi
    else
      CADENCE_NOTE="cadence lock contended past 10s"
    fi
  } 9>>"$CADENCE_LOCK"
  if [ -n "$CADENCE_THROTTLE" ]; then
    report throttled "reason=cadence-floor" "since_last=$CADENCE_THROTTLE" "floor=$INTERVAL"
    exit 0
  fi
fi
[ -n "$CADENCE_NOTE" ] && NOTE="${NOTE:+$NOTE; }cadence floor unavailable ($CADENCE_NOTE); started without the cross-session guard"

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
#
# It also names its own cause of death. systemd counts SIGHUP/SIGINT/SIGTERM/
# SIGPIPE as a clean stop and logs no failure line for them, so a sweep a reap
# ends with one of those leaves no trace in the journal either; the trap records
# which signal it was. The sweep runs in the background and the wrapper `wait`s,
# so a trapped signal fires the handler at once instead of after doctor returns.
# SIGKILL and OOM cannot be trapped and leave no cause file, which the reader
# reports as `unknown`.
SWEEP_BODY="$RUN/sweep.sh"
cat > "$SWEEP_BODY" <<'BODY'
gc=$1; payload=$2; errlog=$3; rcfile=$4; pidfile=$5; finfile=$6; causefile=$7
printf %s "$$" > "$pidfile"
_died() { printf 'signal:%s' "$1" > "$causefile.tmp" && mv "$causefile.tmp" "$causefile"; exit "$2"; }
trap '_died HUP 129'  HUP
trap '_died INT 130'  INT
trap '_died QUIT 131' QUIT
trap '_died PIPE 141' PIPE
trap '_died TERM 143' TERM
"$gc" doctor --json > "$payload" 2> "$errlog" &
sweep_pid=$!
wait "$sweep_pid"
rc=$?
date +%s > "$finfile"
printf %s "$rc" > "$rcfile.tmp" && mv "$rcfile.tmp" "$rcfile"
BODY
SWEEP_ARGV=(sh "$SWEEP_BODY" "$GC_BIN" "$RUN/payload.json" "$RUN/stderr.log" \
  "$RUN/rc" "$RUN/pid" "$RUN/finished_at" "$RUN/cause")

launched=0
if [ -z "${GC_DOCTOR_SWEEP_NO_SYSTEMD:-}" ] \
   && command -v systemd-run >/dev/null 2>&1 \
   && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  # Forward the caller's environment faithfully: env -0 keeps values that hold
  # spaces or newlines whole, and only POSIX-named vars pass so a shell-function
  # export cannot make systemd reject the whole launch. GC_SESSION_ID is the one
  # exception, dropped on purpose: the city-wide session-orphan reaper finds a
  # detached process by the GC_SESSION_ID in its /proc/<pid>/environ and kills
  # its whole process group, which this unit's cgroup does not shield it from.
  # Carry the caller's id and the sweep looks like the deacon session it was
  # launched from, so that session's next teardown reaps it mid-run. gc doctor
  # needs the city context this forwards, never the session id.
  SETENV=()
  while IFS= read -r -d '' kv; do
    case ${kv%%=*} in
      ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*|GC_SESSION_ID) continue ;;
    esac
    SETENV+=(--setenv="$kv")
  done < <(env -0 2>/dev/null)
  # A named unit is what lets a later reader pull this run's own journal after
  # the transient unit is collected; the start second keeps the name unique.
  UNIT="gc-doctor-sweep-$NOW.service"
  if [ "${#SETENV[@]}" -gt 0 ] \
     && systemd-run --user --collect --quiet --unit="$UNIT" \
          --description="gc doctor sweep (survives session teardown)" \
          "${SETENV[@]}" "${SWEEP_ARGV[@]}" >/dev/null 2>&1; then
    launched=1
    printf 'systemd' > "$RUN/launch"
    printf '%s' "$UNIT" > "$RUN/unit"
  fi
fi
if [ "$launched" -eq 0 ]; then
  LAUNCH=(setsid)
  command -v setsid >/dev/null 2>&1 || LAUNCH=(nohup)
  printf '%s' "${LAUNCH[0]}" > "$RUN/launch"
  # `env -u GC_SESSION_ID` for the same reason as the systemd branch: shed the
  # caller's session identity so the reaper cannot claim the detached sweep by
  # it. Here the child inherits the caller's env directly, so drop it at exec.
  "${LAUNCH[@]}" env -u GC_SESSION_ID "${SWEEP_ARGV[@]}" </dev/null >/dev/null 2>&1 &
fi

printf '%s' "$NOW" > "$STAMP"
[ -n "$NEW_WINDOW" ] && printf '%s' "$NEW_WINDOW" > "$WINDOW"
printf '%s' "$NEW_ATTEMPTS" > "$ATTEMPTS_FILE"
report started "bound=$BOUND" "interval=$INTERVAL" "run=$RUN"
exit 0
