#!/usr/bin/env bash
# detached-job.sh — run a command that can outlive one tool call, detached
# from the caller, and wait for it in bounded foreground calls.
#
# An agent's tool call is cut off at ten minutes, and a long gate (a cold Go
# build and test, a pre-commit hook) runs longer. Left in the background of the
# agent's own shell, such a command dies with that shell or with the session,
# and a background poll for a result that never comes never returns, so the
# agent that ended its turn on that poll is never woken. This script gives a
# long command both things it needs:
#
#   - start runs the command in its own session, with stdin from /dev/null, its
#     output in <dir>/log, and the caller's GC_SESSION_ID shed, so neither the
#     caller's shell, nor a tool call cut off at its ceiling, nor the session
#     reaper that finds a session's processes by that id takes it down. macOS
#     ships no setsid binary, so the new session comes from perl's or python3's
#     setsid(). start returns only once it has seen the command running: a
#     launch that failed is reported with the log tail, never assumed.
#   - wait blocks in the foreground and returns when the command finishes, when
#     its process is gone without a result, or after --max seconds, whichever
#     comes first. Every wait ends, including one waiting on a result that will
#     never be written.
#
# The command runs under a wrapper that leads the job's process group. The
# wrapper records its pid, then the command's exit code LAST, by rename, so a
# reader never sees a result for a command still running. A wrapper ended by a
# signal records which one in <dir>/cause, signals the rest of the job's group,
# and writes no exit code.
#
# Usage:
#   detached-job.sh start <dir> [--] <command> [args...]
#   detached-job.sh wait <dir> [--max SECS] [--limit SECS] [--tail N]
#   detached-job.sh status <dir> [--tail N]
#   detached-job.sh stop <dir>
#
#   <dir>         the job's record; start creates it. One job per dir: start
#                 clears a finished job's record and refuses a running one.
#   --max SECS    wait returns `running` after this long (default 540, inside
#                 the ten-minute ceiling of one tool call)
#   --limit SECS  wait stops a job that has run this long since its start and
#                 reports `exceeded` (default: no limit)
#   --tail N      log lines printed after the report (default 20)
#
# Output is key=value lines, state= first, then the tail of the job's log.
#
#   state     exit  meaning
#   started   0     start: the command was seen running (or already finished)
#   done      0|1   the command finished; rc= is its exit code, and the exit is
#                   0 only when rc is 0. An rc above 128 is a signal that ended
#                   the command itself.
#   died      1     the job's wrapper is gone and recorded no exit code; cause=
#                   names the signal, `stop`, the limit, `never-started` (start
#                   gave up on the launch), or `unknown` (SIGKILL)
#   exceeded  1     wait: the job ran past --limit and has been stopped
#   running   3     status: the job is running. wait: still running after
#                   --max seconds; wait again
#   stopped   0     stop: the job was running and has been killed
#   none      2     no job was started in <dir>
#   busy      2     start: <dir> holds a job that is still running
#   failed    2     start: the job could not be launched or was not seen
#                   running; reason= says why
#
# stop exits 0 when it leaves no job running, including when none was.
#
# env: DETACHED_JOB_START_WAIT  seconds start waits to see the job (default 15)
#      DETACHED_JOB_POLL        seconds between a wait's checks (default 5)
#      DETACHED_JOB_STOP_GRACE  seconds between TERM and KILL (default 10)
#      DETACHED_JOB_DETACHER    perl or python3, to force one (default: the
#                               first of them on PATH)
set -uo pipefail

PROG=detached-job

usage() {
  sed -n '/^# Usage:/,/^# stop exits/{s/^# \{0,1\}//;p;}' "$0" >&2
}

usage_error() {
  echo "$PROG: $*" >&2
  usage
  exit 2
}

num() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

setting() { # <value> <default>: a value that is not a whole number takes the default
  if num "$1"; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

START_WAIT=$(setting "${DETACHED_JOB_START_WAIT:-}" 15)
POLL=$(setting "${DETACHED_JOB_POLL:-}" 5)
STOP_GRACE=$(setting "${DETACHED_JOB_STOP_GRACE:-}" 10)
[ "$POLL" -ge 1 ] || POLL=1

now() { date +%s; }

# The first line of a record file with every blank removed; nothing when the
# file is absent. read_num additionally fails unless that is a whole number.
read_word() {
  local v=""
  [ -f "$1" ] && IFS= read -r v < "$1" 2>/dev/null
  printf '%s' "${v//[[:space:]]/}"
}
read_num() {
  local v
  v=$(read_word "$1")
  num "$v" || return 1
  printf '%s' "$v"
}

# A process's start time, blanks collapsed. A pid the kernel reused belongs to
# a process that started later, so this is what tells our wrapper from it.
lstart_of() {
  ps -o lstart= -p "$1" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//'
}

# The wrapper is alive: its pid answers, is not a zombie, and started when the
# wrapper recorded that it started.
alive() {
  local pid stat want got
  pid=$(read_num "$DIR/pid") || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  stat=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]')
  case "$stat" in Z*) return 1 ;; esac
  want=""
  [ -f "$DIR/lstart" ] && want=$(tr -s '[:space:]' ' ' < "$DIR/lstart" | sed 's/^ //;s/ $//')
  if [ -n "$want" ]; then
    got=$(lstart_of "$pid")
    [ -z "$got" ] || [ "$got" = "$want" ] || return 1
  fi
  return 0
}

# Classify the job in DIR: sets STATE (none|running|done|died), RC and CAUSE.
classify() {
  STATE=""; RC=""; CAUSE=""
  if RC=$(read_num "$DIR/rc"); then STATE="done"; return; fi
  RC=""
  if [ -f "$DIR/pid" ]; then
    if alive; then STATE=running; return; fi
    # Gone: a result written between the two reads still counts.
    if RC=$(read_num "$DIR/rc"); then STATE="done"; return; fi
    RC=""
    STATE=died
    CAUSE=$(read_word "$DIR/stopped_by")
    [ -n "$CAUSE" ] || CAUSE=$(read_word "$DIR/cause")
    [ -n "$CAUSE" ] || CAUSE=unknown
    return
  fi
  local started
  if ! started=$(read_num "$DIR/started_at"); then STATE=none; return; fi
  # Started, but the wrapper has not recorded its pid.
  if [ -f "$DIR/cancelled" ] || [ $(( $(now) - started )) -gt $(( START_WAIT * 4 )) ]; then
    STATE=died; CAUSE=never-started; return
  fi
  STATE=running
}

elapsed() {
  local started end
  started=$(read_num "$DIR/started_at") || { printf 0; return; }
  end=$(read_num "$DIR/finished_at") || end=$(now)
  printf '%s' $(( end - started ))
}

report() { # <state> [key=value ...]
  printf 'state=%s\n' "$1"
  shift
  local kv
  for kv in "$@"; do printf '%s\n' "$kv"; done
}

show_tail() { # <lines>
  [ "$1" -gt 0 ] 2>/dev/null && [ -s "$DIR/log" ] || return 0
  printf -- '--- last %s line(s) of %s\n' "$1" "$DIR/log"
  tail -n "$1" "$DIR/log"
}

# Report the classified state of a job that is not running, and exit with its
# code.
finish() { # <tail lines>
  case "$STATE" in
    none)
      report none "dir=$DIR"
      exit 2 ;;
    done)
      report "done" "rc=$RC" "elapsed=$(elapsed)" "dir=$DIR" "log=$DIR/log"
      show_tail "$1"
      [ "$RC" = 0 ] && exit 0
      exit 1 ;;
    died)
      report died "cause=$CAUSE" "elapsed=$(elapsed)" "dir=$DIR" "log=$DIR/log"
      show_tail "$1"
      exit 1 ;;
  esac
}

# Kill a running job's process group, which its wrapper leads. Only a wrapper
# proved alive names a group that is still this job's: a dead wrapper's pid can
# be reused, so its group is left alone. Records why before the first signal.
kill_job() { # <why>
  local pid i
  pid=$(read_num "$DIR/pid") || return 0
  alive || return 0
  printf '%s\n' "$1" > "$DIR/stopped_by"
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
  i=0
  while kill -0 -- "-$pid" 2>/dev/null && [ "$i" -lt $(( STOP_GRACE * 5 )) ]; do
    sleep 0.2
    i=$((i + 1))
  done
  if kill -0 -- "-$pid" 2>/dev/null; then
    kill -KILL -- "-$pid" 2>/dev/null
    sleep 0.2
  fi
  ! kill -0 -- "-$pid" 2>/dev/null
}

cmd_start() {
  [ "${1:-}" = "--" ] && shift
  [ $# -ge 1 ] || usage_error "start needs a command to run"
  if ! mkdir -p "$DIR" 2>/dev/null || [ ! -w "$DIR" ]; then
    report failed "reason=dir-unwritable" "dir=$DIR"
    exit 2
  fi
  DIR=$(cd "$DIR" && pwd)
  classify
  if [ "$STATE" = running ]; then
    report busy "dir=$DIR" "pid=$(read_num "$DIR/pid")"
    exit 2
  fi

  local detacher="${DETACHED_JOB_DETACHER:-}"
  if [ -z "$detacher" ]; then
    if command -v perl >/dev/null 2>&1; then
      detacher=perl
    elif command -v python3 >/dev/null 2>&1; then
      detacher=python3
    fi
  fi
  # Each detacher forks, and its child starts a new session, closes every
  # descriptor above stderr (an inherited pipe would hold the caller's tool
  # call open until the job ends), and execs the wrapper.
  local -a detach
  case "$detacher" in
    perl)
      detach=(perl -e 'use POSIX (); my $p = fork(); die "detached-job: fork: $!\n" unless defined $p; exit 0 if $p; defined(POSIX::setsid()) or die "detached-job: setsid: $!\n"; POSIX::close($_) for 3 .. 255; exec { $ARGV[0] } @ARGV; die "detached-job: exec $ARGV[0]: $!\n";') ;;
    python3)
      detach=(python3 -c 'import os, sys
if os.fork():
    os._exit(0)
os.setsid()
os.closerange(3, 256)
os.execvp(sys.argv[1], sys.argv[1:])') ;;
    *)
      report failed "reason=no-detacher" "detail=neither perl nor python3 is on PATH, and nothing else here can start a new session" "dir=$DIR"
      exit 2 ;;
  esac

  # Clear the previous job's record: only the files this script writes.
  rm -rf "$DIR/claim"
  rm -f "$DIR/pid" "$DIR/pid.tmp" "$DIR/lstart" "$DIR/rc" "$DIR/rc.tmp" \
    "$DIR/cause" "$DIR/cause.tmp" "$DIR/stopped_by" "$DIR/finished_at" \
    "$DIR/started_at" "$DIR/cancelled" "$DIR/command" "$DIR/run.sh" "$DIR/log"

  # The wrapper and start race for one atomic mkdir of <dir>/claim. The wrapper
  # that wins runs the command; a start that wins cancels a launch it gave up
  # on, so a wrapper that wakes late can never run a job start reported failed.
  cat > "$DIR/run.sh" <<'WRAPPER'
dir=$1
shift
mkdir "$dir/claim" 2>/dev/null || exit 0
ps -o lstart= -p $$ > "$dir/lstart" 2>/dev/null
printf '%s\n' "$$" > "$dir/pid.tmp" && mv -f "$dir/pid.tmp" "$dir/pid"
_died() {
  trap '' HUP INT TERM
  printf 'signal:%s\n' "$1" > "$dir/cause.tmp" && mv -f "$dir/cause.tmp" "$dir/cause"
  kill -TERM 0 2>/dev/null
  exit "$2"
}
trap '_died HUP 129' HUP
trap '_died INT 130' INT
trap '_died TERM 143' TERM
"$@" &
child=$!
wait "$child"
rc=$?
date +%s > "$dir/finished_at"
printf '%s\n' "$rc" > "$dir/rc.tmp" && mv -f "$dir/rc.tmp" "$dir/rc"
WRAPPER
  printf '%q ' "$@" > "$DIR/command"
  printf '\n' >> "$DIR/command"
  now > "$DIR/started_at"

  # The detacher's parent exits as soon as it has forked, so this returns at
  # once; its child leaves our session and becomes the wrapper. A non-zero exit
  # is a detacher that never forked, so there is no wrapper to wait for.
  env -u GC_SESSION_ID "${detach[@]}" sh "$DIR/run.sh" "$DIR" "$@" </dev/null >>"$DIR/log" 2>&1
  local launch_rc=$?

  local deadline=$(( $(now) + START_WAIT ))
  [ "$launch_rc" -eq 0 ] || deadline=0
  while [ ! -f "$DIR/pid" ] && [ ! -f "$DIR/rc" ] && [ "$(now)" -lt "$deadline" ]; do
    sleep 0.2
  done
  if [ ! -f "$DIR/pid" ] && [ ! -f "$DIR/rc" ]; then
    if mkdir "$DIR/claim" 2>/dev/null; then
      : > "$DIR/cancelled"
      report failed "reason=not-started" "detacher=$detacher" "launch_rc=$launch_rc" "waited=$START_WAIT" "dir=$DIR" "log=$DIR/log"
      show_tail 20
      exit 2
    fi
    # The wrapper claimed the job as the window closed; give it the time to
    # record its pid.
    deadline=$(( $(now) + START_WAIT ))
    while [ ! -f "$DIR/pid" ] && [ ! -f "$DIR/rc" ] && [ "$(now)" -lt "$deadline" ]; do
      sleep 0.2
    done
  fi
  classify
  case "$STATE" in
    running | done)
      report started "pid=$(read_num "$DIR/pid")" "detacher=$detacher" "dir=$DIR" "log=$DIR/log"
      exit 0 ;;
  esac
  report failed "reason=died-at-start" "cause=${CAUSE:-unknown}" "detacher=$detacher" "launch_rc=$launch_rc" "dir=$DIR" "log=$DIR/log"
  show_tail 20
  exit 2
}

cmd_wait() {
  local max=540 limit="" tail_n=20
  while [ $# -gt 0 ]; do
    case "$1" in
      --max) num "${2:-}" || usage_error "--max needs a whole number of seconds"; max=$2; shift 2 ;;
      --limit) num "${2:-}" || usage_error "--limit needs a whole number of seconds"; limit=$2; shift 2 ;;
      --tail) num "${2:-}" || usage_error "--tail needs a whole number of lines"; tail_n=$2; shift 2 ;;
      *) usage_error "unknown wait option: $1" ;;
    esac
  done
  local t0 waited nap
  t0=$(now)
  while :; do
    classify
    [ "$STATE" = running ] || finish "$tail_n"
    if [ -n "$limit" ] && [ "$(elapsed)" -ge "$limit" ]; then
      kill_job "limit:${limit}s"
      report exceeded "limit=$limit" "elapsed=$(elapsed)" "dir=$DIR" "log=$DIR/log"
      show_tail "$tail_n"
      exit 1
    fi
    waited=$(( $(now) - t0 ))
    if [ "$waited" -ge "$max" ]; then
      report running "pid=$(read_num "$DIR/pid")" "elapsed=$(elapsed)" "waited=$waited" "dir=$DIR" "log=$DIR/log"
      show_tail 5
      exit 3
    fi
    nap=$POLL
    [ $(( max - waited )) -lt "$nap" ] && nap=$(( max - waited ))
    sleep "$nap"
  done
}

cmd_status() {
  local tail_n=20
  while [ $# -gt 0 ]; do
    case "$1" in
      --tail) num "${2:-}" || usage_error "--tail needs a whole number of lines"; tail_n=$2; shift 2 ;;
      *) usage_error "unknown status option: $1" ;;
    esac
  done
  classify
  if [ "$STATE" = running ]; then
    report running "pid=$(read_num "$DIR/pid")" "elapsed=$(elapsed)" "dir=$DIR" "log=$DIR/log"
    show_tail "$tail_n"
    exit 3
  fi
  finish "$tail_n"
}

cmd_stop() {
  [ $# -eq 0 ] || usage_error "stop takes no options"
  classify
  if [ "$STATE" != running ]; then
    report "$STATE" "dir=$DIR"
    exit 0
  fi
  if kill_job stop; then
    report stopped "elapsed=$(elapsed)" "dir=$DIR"
    exit 0
  fi
  report running "detail=the job's process group survived TERM and KILL" "dir=$DIR"
  exit 1
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  start | wait | status | stop) ;;
  "") usage_error "missing subcommand" ;;
  *) usage_error "unknown subcommand: $1" ;;
esac
SUB=$1
shift
[ $# -ge 1 ] && [ -n "$1" ] || usage_error "$SUB needs a job directory"
DIR=$1
shift
case "$SUB" in
  start) cmd_start "$@" ;;
  wait) cmd_wait "$@" ;;
  status) cmd_status "$@" ;;
  stop) cmd_stop "$@" ;;
esac
