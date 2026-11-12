#!/usr/bin/env bash
# ui-copy.sh — run a copy of a rig's UI from a tree, on a loopback port of its
# own, and publish it on request at an address of its own, so that a person can
# open a change's UI as a live page while a session makes the change with them.
#
# A rig offers a live copy by declaring the command that serves its UI. The
# command is the formula var ui_serve_command, which a city sets among the
# rig's [rigs.formula_vars] in city.toml. The city's publisher is two more vars
# set there. ui_publish_command publishes a loopback port at an origin of its
# own for exactly as long as the command runs, and ui_address_pattern is the
# address the port gets. mol-rig-demo declares all three. start reads them in
# one call, `gc formula show mol-rig-demo --rig <rig> --json`, as each var's
# rig_default. Each takes the copy's port as $PORT: the two commands run with
# PORT in their environment, and every $PORT or ${PORT} in the address pattern
# is replaced by the port. A city with a foreground `tailscale serve` as its
# publisher sets, for each rig that offers a live copy:
#   [rigs.formula_vars]
#   ui_serve_command = "<the rig's own command, run from the tree's root>"
#   ui_publish_command = "tailscale serve --yes --https=$PORT http://127.0.0.1:$PORT"
#   ui_address_pattern = "https://<the host's tailnet name>:$PORT/"
#
# A copy runs the serve command from the tree, on a free loopback port that
# demo_engine_free_port picks, so any number of copies run at once and none
# shares another's port. The serve command serves the UI on fixture data and
# listens on loopback only, which the rig's command guarantees.
#
# Each copy is a process group of its own, led by a bash process that this
# script leaves running in a new session. The leader runs the serve command,
# runs the publish command whenever this script asks it to, and ends the whole
# group when the serve command ends or a signal ends the leader, so no address
# outlives its copy. A publish command that ends alone leaves the copy running
# with no address until start publishes it again. A publish command that ends
# within the settle window has refused the port, and its output decides what
# follows. Tailscale's "please try again", printed while another client is
# changing its serve config, is tried again on the same port. Tailscale's
# "listener already exists for port", printed when another mapping holds the
# port, moves the copy to another free port. Any other refusal leaves the copy
# running with no address, and the report says why. This script never runs
# `tailscale serve reset`, which would drop every mapping.
#
# A copy ends when its caller stops it. It also ends once the session that
# started it has ended, through Gas City's orphan sweep, which this script
# composes and does not rebuild. The sweep ends a process that left its
# session's process group, carries the session's GC_SESSION_ID and GC_CITY_PATH,
# and has been reparented to PID 1, once its session is closed, or stopped with
# no live pane. For a stopped session it also needs the process's
# GC_RUNTIME_EPOCH and a start before the stop. It signals the whole process
# group (Gas City's `sweepProcessTableOrphans` and `processRootIncarnationOver`
# in cmd/gc/session_beads.go). So the leader keeps all three values from the
# caller's environment, where detached-job.sh sheds GC_SESSION_ID, and leads the
# copy's group. The sweep reads a process's environment the way ps does, and
# macOS withholds an Apple platform binary's environment from ps, so the leader
# is never /bin/bash. On macOS it is the bash running this script, or the bash
# on PATH, from outside the system's directories. A copy started with no
# GC_SESSION_ID belongs to no session and ends only when its caller stops it.
#
# Each copy's record is a directory under the state root, named for the tree:
# <city>/.gc/runtime/packs/gc-toolkit/ui-copies, for the city that GC_CITY_PATH,
# GC_CITY or GC_CITY_ROOT names, else ${TMPDIR:-/tmp}/gc/ui-copies. A tree has
# at most one copy, so a start for a tree whose copy runs reports that copy and
# starts no other, and a start after a session wakes is safe to repeat.
#
# Usage:
#   ui-copy.sh start --tree <dir> [--rig <rig>] [--publish]
#   ui-copy.sh status --tree <dir>
#   ui-copy.sh stop --tree <dir>
#
#   --tree      the tree the copy runs from, and the copy's name in status and
#               stop. start needs it to exist.
#   --rig       the rig whose formula vars start reads (default: $GC_RIG)
#   --publish   also give the copy an address. Without it the copy has none,
#               as for a copy a session runs for its own checks. A start with
#               --publish for a copy that runs with no address publishes it.
#
# Output is key=value lines, state= first. port= and address= are printed for a
# copy that runs, and address= is empty when the copy has no address, with
# detail= saying why. log= names the file the serve command writes to.
#
#   state     exit  meaning
#   running   0     start, status: the copy runs and answers on its port
#   stopped   0     stop: the copy was running and its process group has ended
#   none      0|1   stop (0), status (1): no copy of the tree runs
#   died      1     status: the copy's leader is gone; rc= is the serve
#                   command's exit code when it recorded one
#   failed    1     start: no copy runs; reason= and detail= say why
#   running   1     stop: the copy's process group survived TERM and KILL
#
# Exit 2 is a usage error.
#
# env: UI_COPY_STATE_DIR   the state root, in place of the one above
#      UI_COPY_START_WAIT  seconds start waits for the copy to answer on its
#                          port (default 180, for a serve command that compiles)
#      UI_COPY_SETTLE      seconds a publish command must run before the copy
#                          counts as published (default 3)
set -uo pipefail

PROG=ui-copy
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMULA=mol-rig-demo
# Port moves and retried publishes, each at most this many times.
TRIES=3
STOP_GRACE=10

# shellcheck source=demo-engine-lib.sh
. "$HERE/demo-engine-lib.sh" || { echo "$PROG: cannot source demo-engine-lib.sh beside this script" >&2; exit 1; }

usage() {
  sed -n '/^# Usage:/,/^# Exit 2/{s/^# \{0,1\}//;p;}' "$0" >&2
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

START_WAIT=$(setting "${UI_COPY_START_WAIT:-}" 180)
SETTLE=$(setting "${UI_COPY_SETTLE:-}" 3)

now() { date +%s; }

# The first line of a record file, or nothing when the file is absent.
read_line() {
  local v=""
  [ -f "$1" ] && IFS= read -r v < "$1" 2>/dev/null
  printf '%s' "$v"
}
read_num() {
  local v
  v=$(read_line "$1")
  v=${v//[[:space:]]/}
  num "$v" || return 1
  printf '%s' "$v"
}

report() { # <state> [key=value ...]
  printf 'state=%s\n' "$1"
  shift
  local kv
  for kv in "$@"; do printf '%s\n' "$kv"; done
}

show_tail() { # <file> <lines>
  [ -s "$1" ] || return 0
  printf -- '--- last %s line(s) of %s\n' "$2" "$1"
  tail -n "$2" "$1"
}

# A process's start, in a form that stays the same for as long as it runs, as
# detached-job.sh reads it: the starttime field of /proc/<pid>/stat where that
# exists, else ps's start time in the C locale and UTC. A pid the kernel reused
# belongs to a process that started later, so this tells the leader from it.
start_id() {
  if [ -r "/proc/$1/stat" ]; then
    sed -n 's/^.*) //p' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f20
  else
    LC_ALL=C TZ=UTC ps -o lstart= -p "$1" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//'
  fi
}

# --- the leader --------------------------------------------------------------
# start writes these functions into the record as lead.sh, and the leader runs
# them, so a copy keeps running the code it started with. The leader sets its
# traps before it records its pid, so a signal this script sends once it reads
# the pid reaches a trap.

lead() { # <record dir>
  UC_DIR=$1
  UC_GEN=0
  trap '_lead_end 129' HUP
  trap '_lead_end 130' INT
  trap '_lead_end 143' TERM
  trap '_lead_publish' USR1
  UC_PORT=$(cat "$UC_DIR/port") || _lead_end 1
  start_id $$ > "$UC_DIR/start_id"
  printf '%s\n' "$$" > "$UC_DIR/pid.tmp" && mv -f "$UC_DIR/pid.tmp" "$UC_DIR/pid"
  cd "$(cat "$UC_DIR/tree")" || _lead_end 1
  PORT=$UC_PORT "$BASH" -c "$(cat "$UC_DIR/serve_command")" </dev/null &
  UC_SERVE=$!
  # wait returns early each time USR1's trap runs, so it is repeated until the
  # serve command itself has ended.
  while :; do
    wait "$UC_SERVE"
    UC_RC=$?
    kill -0 "$UC_SERVE" 2>/dev/null || break
  done
  printf '%s\n' "$UC_RC" > "$UC_DIR/rc"
  _lead_end "$UC_RC"
}

# Runs the publish command for the copy's port, and records which run it is
# and its pid, by rename, so a reader never sees a half-written record.
_lead_publish() {
  UC_GEN=$((UC_GEN + 1))
  PORT=$UC_PORT "$BASH" -c "$(cat "$UC_DIR/publish_command")" </dev/null >"$UC_DIR/publish.log" 2>&1 &
  printf '%s %s\n' "$UC_GEN" "$!" > "$UC_DIR/publisher.tmp" && mv -f "$UC_DIR/publisher.tmp" "$UC_DIR/publisher"
}

# Ends the copy's whole process group, which holds the serve command and the
# publish command, and then the leader.
_lead_end() {
  trap '' HUP INT TERM USR1
  kill -TERM 0 2>/dev/null
  exit "$1"
}

# --- the record --------------------------------------------------------------

state_root() {
  local c
  if [ -n "${UI_COPY_STATE_DIR:-}" ]; then
    printf '%s\n' "${UI_COPY_STATE_DIR%/}"
    return
  fi
  for c in "${GC_CITY_PATH:-}" "${GC_CITY:-}" "${GC_CITY_ROOT:-}"; do
    case "$c" in
      /*) if [ -d "$c/.gc" ]; then printf '%s/.gc/runtime/packs/gc-toolkit/ui-copies\n' "${c%/}"; return; fi ;;
    esac
  done
  printf '%s/gc/ui-copies\n' "${TMPDIR:-/tmp}" | sed 's|//*|/|g'
}

# A record's directory name: the hash of the tree's canonical path.
tree_key() {
  printf '%s' "$1" | git hash-object --stdin 2>/dev/null
}

# Sets REC to the record of the tree named as given: the record for its
# canonical path while it exists, else the record whose tree, canonical or as
# given at start, is that path. REC is empty when no record names the tree.
find_record() {
  local given="${1%/}" canon key d
  REC=""
  [ -n "$given" ] || given=/
  if [ -d "$1" ] && canon=$(cd "$1" 2>/dev/null && pwd -P) && key=$(tree_key "$canon") && [ -n "$key" ]; then
    [ -d "$ROOT/$key" ] && REC="$ROOT/$key"
    return 0
  fi
  for d in "$ROOT"/*/; do
    [ -d "$d" ] || continue
    if [ "$(read_line "${d}tree")" = "$given" ] || [ "$(read_line "${d}given")" = "$given" ]; then
      REC="${d%/}"
      return 0
    fi
  done
  return 0
}

remove_record() { # <record dir>
  case "$1" in
    "$ROOT"/?*) rm -rf -- "$1" ;;
  esac
}

# The copy's leader is running, and is the process its record names.
alive() { # <record dir>
  local pid stat want got
  pid=$(read_num "$1/pid") || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  stat=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]')
  case "$stat" in '' | Z*) return 1 ;; esac
  want=$(read_line "$1/start_id")
  [ -n "$want" ] || return 0
  got=$(start_id "$pid")
  [ -z "$got" ] || [ "$got" = "$want" ]
}

# The run of the publish command the record names, as "<run> <pid>".
publisher() { read_line "$1/publisher"; }

# That run of the publish command is still running, as the leader's child.
publisher_alive() { # <record dir>
  local rec pid leader ppid stat
  rec=$(publisher "$1")
  pid=${rec#* }
  num "$pid" || return 1
  leader=$(read_num "$1/pid") || return 1
  read -r ppid stat <<<"$(ps -o ppid=,stat= -p "$pid" 2>/dev/null)"
  [ "${ppid:-}" = "$leader" ] || return 1
  case "${stat:-}" in '' | Z*) return 1 ;; esac
  return 0
}

# The address the copy has while its publish command runs.
address_of() { # <record dir>
  publisher_alive "$1" && read_line "$1/address"
}

# Why a running copy has no address.
no_address_why() { # <record dir>
  local last
  if [ ! -f "$1/asked" ]; then
    printf 'it was started without --publish, so it has no address'
  elif [ ! -s "$1/publish_command" ]; then
    printf 'rig %s sets no ui_publish_command or no ui_address_pattern among its formula vars, so no address can be given' "$(read_line "$1/rig")"
  else
    last=$(tail -n 1 "$1/publish.log" 2>/dev/null | tr -d '\r')
    printf 'its publish command ended%s, so it has no address until start --publish publishes it again' "${last:+ (\"$last\")}"
  fi
}

# Prints the report of a copy that runs, from its record.
report_running() { # <record dir>
  local addr
  addr=$(address_of "$1")
  if [ -n "$addr" ]; then
    report running "port=$(read_line "$1/port")" "address=$addr" "tree=$(read_line "$1/tree")" "log=$1/serve.log"
  else
    report running "port=$(read_line "$1/port")" "address=" "tree=$(read_line "$1/tree")" "log=$1/serve.log" \
      "detail=$(no_address_why "$1")"
  fi
}

# Ends the copy's process group, which its leader leads. Only a leader proved
# alive names a group that is still this copy's, since a dead leader's pid can
# be reused. Returns 1 when the group survived TERM and KILL.
stop_group() { # <record dir>
  local pid i
  pid=$(read_num "$1/pid") || return 0
  alive "$1" || return 0
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
  i=0
  while kill -0 -- "-$pid" 2>/dev/null && [ "$i" -lt $((STOP_GRACE * 5)) ]; do
    sleep 0.2
    i=$((i + 1))
  done
  if kill -0 -- "-$pid" 2>/dev/null; then
    kill -KILL -- "-$pid" 2>/dev/null
    sleep 0.2
  fi
  ! kill -0 -- "-$pid" 2>/dev/null
}

# The bash that leads a copy: one whose environment ps can read, so the orphan
# sweep sees the session the copy belongs to. On macOS that rules out the
# system's own binaries, whose environment macOS withholds from ps.
lead_bash() {
  local b dir
  for b in "${BASH:-}" "$(command -v bash 2>/dev/null)"; do
    [ -n "$b" ] && [ -x "$b" ] || continue
    if [ "$(uname -s)" = Darwin ]; then
      dir=$(cd "$(dirname "$b")" 2>/dev/null && pwd -P) || continue
      case "$dir/" in /bin/* | /sbin/* | /usr/bin/* | /usr/sbin/* | /usr/libexec/* | /System/*) continue ;; esac
    fi
    printf '%s\n' "$b"
    return 0
  done
  return 1
}

# The copy answers on its loopback port.
answers() { # <port>
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# --- start -------------------------------------------------------------------

fail() { # <reason> <detail>
  report failed "reason=$1" "tree=$TREE" "detail=$2"
  exit 1
}

# A var's value from gc formula show's answer: the rig's value, else the
# formula's default, else nothing when the formula declares no such var.
formula_var() { # <json> <name>
  printf '%s' "$1" | jq -r --arg n "$2" '[.vars[] | select(.name == $n)][0]
    | if . == null then "" elif .rig_default != null then (.rig_default | tostring) else ((.default // "") | tostring) end'
}

# Reads the three vars into SERVE, PUBLISH and PATTERN. Fails the start when
# they do not read, or when the rig declares no serve command.
read_vars() {
  local json why
  json=$(gc formula show "$FORMULA" --rig "$RIG" --json 2>/dev/null)
  if ! printf '%s' "$json" | jq -e '.ok == true and (.vars | type == "array")' >/dev/null 2>&1; then
    why=$(printf '%s' "$json" | jq -r '.error.message // empty' 2>/dev/null)
    fail vars-unread "gc formula show $FORMULA --rig $RIG --json did not read: ${why:-gc answered nothing jq could read}"
  fi
  SERVE=$(formula_var "$json" ui_serve_command)
  PUBLISH=$(formula_var "$json" ui_publish_command)
  PATTERN=$(formula_var "$json" ui_address_pattern)
  if [ -z "$SERVE" ]; then
    if printf '%s' "$json" | jq -e 'any(.vars[]; .name == "ui_serve_command")' >/dev/null 2>&1; then
      fail no-serve-command "rig $RIG declares no ui_serve_command among its formula vars, so it offers no live copy"
    fi
    fail no-serve-command "$FORMULA, as gc loads it, declares no ui_serve_command, so no rig offers a live copy yet"
  fi
}

# Waits until the leader of the record's copy has recorded its pid. Returns 1
# when it does not within the bound.
await_leader() { # <record dir> <seconds>
  local deadline=$(( $(now) + $2 ))
  while [ ! -f "$1/pid" ] && [ "$(now)" -lt "$deadline" ]; do
    sleep 0.2
  done
  [ -f "$1/pid" ]
}

# Has the copy's leader run the publish command again, and waits for that run
# to settle. Sets PUB to published, to taken when the publisher refused the
# port as taken, or to refused for any other end.
publish() { # <record dir>
  local rec="$1" try gen pid deadline
  PUB=refused
  for ((try = 1; try <= TRIES; try++)); do
    gen=$(publisher "$rec")
    gen=${gen%% *}
    num "$gen" || gen=0
    kill -USR1 "$(read_num "$rec/pid")" 2>/dev/null || return
    deadline=$(( $(now) + 10 ))
    while :; do
      pid=$(publisher "$rec")
      [ "${pid%% *}" = "$((gen + 1))" ] && break
      [ "$(now)" -lt "$deadline" ] || return
      sleep 0.1
    done
    deadline=$(( $(now) + SETTLE ))
    while publisher_alive "$rec" && [ "$(now)" -lt "$deadline" ]; do
      sleep 0.2
    done
    if publisher_alive "$rec"; then
      PUB=published
      return
    fi
    case "$(cat "$rec/publish.log" 2>/dev/null)" in
      *"already exists for port"*) PUB=taken; return ;;
      *"try again"*) sleep 1 ;;
      *) return ;;
    esac
  done
}

# Runs a copy in the claimed record REC, on a free port, publishing it when
# WANT asks for an address the city can give. Prints its report and exits.
launch() {
  local try port detacher leader pattern
  leader=$(lead_bash) || fail no-leader "no bash outside the system's directories is on PATH, and macOS hides a system binary's environment from ps, so Gas City's orphan sweep could not end the copy once its session ends"
  detacher=""
  if command -v perl >/dev/null 2>&1; then detacher=perl
  elif command -v python3 >/dev/null 2>&1; then detacher=python3
  fi
  # The detacher forks, and its child starts a new session, closes every
  # descriptor above stderr and execs the leader. The caller's environment
  # passes through whole, GC_SESSION_ID, GC_CITY_PATH and GC_RUNTIME_EPOCH
  # included, because the orphan sweep reads them from the leader.
  local -a detach
  case "$detacher" in
    perl)
      detach=(perl -e 'use POSIX (); my $p = fork(); die "ui-copy: fork: $!\n" unless defined $p; exit 0 if $p; defined(POSIX::setsid()) or die "ui-copy: setsid: $!\n"; POSIX::close($_) for 3 .. 255; exec { $ARGV[0] } @ARGV; die "ui-copy: exec $ARGV[0]: $!\n";') ;;
    python3)
      detach=(python3 -c 'import os, sys
if os.fork():
    os._exit(0)
os.setsid()
os.closerange(3, 256)
os.execvp(sys.argv[1], sys.argv[1:])') ;;
    *)
      remove_record "$REC"
      fail no-detacher "neither perl nor python3 is on PATH, and nothing else here can start a new session" ;;
  esac
  for ((try = 1; try <= TRIES; try++)); do
    port=$(demo_engine_free_port) || { remove_record "$REC"; fail no-free-port "no free loopback port could be picked, which needs node"; }
    rm -f "$REC/pid" "$REC/pid.tmp" "$REC/start_id" "$REC/publisher" "$REC/publisher.tmp" "$REC/rc" \
      "$REC/serve.log" "$REC/publish.log" "$REC/address"
    printf '%s\n' "$port" > "$REC/port"
    if [ -s "$REC/publish_command" ]; then
      pattern=$(read_line "$REC/address_pattern")
      pattern=${pattern//\$\{PORT\}/$port}
      printf '%s\n' "${pattern//\$PORT/$port}" > "$REC/address"
    fi
    { declare -f lead _lead_publish _lead_end start_id; printf 'lead "$@"\n'; } > "$REC/lead.sh"
    "${detach[@]}" "$leader" "$REC/lead.sh" "$REC" </dev/null >>"$REC/serve.log" 2>&1
    if ! await_leader "$REC" 15; then
      remove_record "$REC"
      fail not-started "the copy's leader did not start within 15 seconds"
    fi
    if [ "$WANT" = 1 ] && [ -s "$REC/publish_command" ]; then
      publish "$REC"
      if [ "$PUB" = taken ] && [ "$try" -lt "$TRIES" ]; then
        stop_group "$REC"
        continue
      fi
    fi
    break
  done
  local deadline=$(( $(now) + START_WAIT ))
  until answers "$port"; do
    if ! alive "$REC"; then
      local rc
      rc=$(read_num "$REC/rc") || rc=""
      report failed "reason=serve-exited" "tree=$TREE" "rc=$rc" \
        "detail=the serve command ended before the copy answered on port $port"
      show_tail "$REC/serve.log" 20
      remove_record "$REC"
      exit 1
    fi
    if [ "$(now)" -ge "$deadline" ]; then
      stop_group "$REC"
      report failed "reason=not-answering" "tree=$TREE" \
        "detail=the copy did not answer on port $port within $START_WAIT seconds, so it was stopped"
      show_tail "$REC/serve.log" 20
      remove_record "$REC"
      exit 1
    fi
    sleep 0.5
  done
  report_running "$REC"
  exit 0
}

cmd_start() {
  local tree="" rig="${GC_RIG:-}" want=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tree) [ $# -ge 2 ] || usage_error "--tree needs a directory"; tree=$2; shift 2 ;;
      --rig) [ $# -ge 2 ] || usage_error "--rig needs a rig"; rig=$2; shift 2 ;;
      --publish) want=1; shift ;;
      *) usage_error "unknown start option: $1" ;;
    esac
  done
  [ -n "$tree" ] || usage_error "start needs --tree"
  [ -n "$rig" ] || usage_error "start needs --rig, or GC_RIG set"
  TREE=$tree
  [ -d "$tree" ] || fail no-tree "$tree is not a directory"
  TREE=$(cd "$tree" && pwd -P) || fail no-tree "$tree could not be entered"
  RIG=$rig
  WANT=$want
  read_vars
  ROOT=$(state_root)
  mkdir -p "$ROOT" 2>/dev/null || fail no-state "the state root $ROOT could not be made"
  local key
  key=$(tree_key "$TREE")
  [ -n "$key" ] || fail no-state "git could not name a record for the tree"
  REC="$ROOT/$key"

  local claims=0
  until mkdir "$REC" 2>/dev/null; do
    claims=$((claims + 1))
    [ "$claims" -le "$TRIES" ] || fail no-state "the record $REC could neither be claimed nor read"
    # A record that holds no leader yet is a start in progress, or one that
    # died before its leader ran.
    if ! await_leader "$REC" 30 || ! alive "$REC"; then
      remove_record "$REC"
      continue
    fi
    # The tree's copy runs: report it, publishing it first when asked.
    [ "$want" = 1 ] && : > "$REC/asked"
    if [ "$want" = 1 ] && [ -s "$REC/publish_command" ] && ! publisher_alive "$REC"; then
      publish "$REC"
      if [ "$PUB" = taken ]; then
        stop_group "$REC"
        launch
      fi
    fi
    local deadline=$(( $(now) + START_WAIT ))
    until answers "$(read_line "$REC/port")" || [ "$(now)" -ge "$deadline" ] || ! alive "$REC"; do
      sleep 0.5
    done
    if alive "$REC"; then
      report_running "$REC"
      exit 0
    fi
    remove_record "$REC"
  done

  printf '%s\n' "$TREE" > "$REC/tree"
  printf '%s\n' "${tree%/}" > "$REC/given"
  printf '%s\n' "$RIG" > "$REC/rig"
  printf '%s\n' "$SERVE" > "$REC/serve_command"
  [ "$want" = 1 ] && : > "$REC/asked"
  if [ -n "$PUBLISH" ] && [ -n "$PATTERN" ]; then
    printf '%s\n' "$PUBLISH" > "$REC/publish_command"
    printf '%s\n' "$PATTERN" > "$REC/address_pattern"
  fi
  launch
}

# --- status and stop ---------------------------------------------------------

tree_arg() { # <verb> <args...>: prints the --tree value
  local verb=$1 tree=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --tree) [ $# -ge 2 ] || usage_error "--tree needs a directory"; tree=$2; shift 2 ;;
      *) usage_error "unknown $verb option: $1" ;;
    esac
  done
  [ -n "$tree" ] || usage_error "$verb needs --tree"
  printf '%s' "$tree"
}

cmd_status() {
  local tree rc
  tree=$(tree_arg status "$@") || exit 2
  ROOT=$(state_root)
  find_record "$tree"
  if [ -z "$REC" ]; then
    report none "tree=$tree"
    exit 1
  fi
  if alive "$REC"; then
    report_running "$REC"
    exit 0
  fi
  rc=$(read_num "$REC/rc") || rc=""
  report died "tree=$(read_line "$REC/tree")" "rc=$rc" "log=$REC/serve.log"
  show_tail "$REC/serve.log" 20
  exit 1
}

cmd_stop() {
  local tree
  tree=$(tree_arg stop "$@") || exit 2
  ROOT=$(state_root)
  find_record "$tree"
  if [ -z "$REC" ]; then
    report none "tree=$tree"
    exit 0
  fi
  if ! alive "$REC"; then
    remove_record "$REC"
    report none "tree=$tree"
    exit 0
  fi
  if stop_group "$REC"; then
    remove_record "$REC"
    report stopped "tree=$tree"
    exit 0
  fi
  report running "tree=$tree" "detail=the copy's process group survived TERM and KILL"
  exit 1
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  start | status | stop) ;;
  "") usage_error "missing subcommand" ;;
  *) usage_error "unknown subcommand: $1" ;;
esac
SUB=$1
shift
case "$SUB" in
  start) cmd_start "$@" ;;
  status) cmd_status "$@" ;;
  stop) cmd_stop "$@" ;;
esac
