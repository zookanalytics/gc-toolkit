#!/usr/bin/env bash
# detached-job.test.sh — the detached runner a long gate goes through. Proves
# the two properties the refinery's run-tests step rests on: start puts the
# command in a session of its own and reports a launch that did not happen,
# and every wait ends — on the command's exit code, on a wrapper that died
# without one, on --max, or on --limit — so no caller is ever left waiting on
# a result that cannot arrive. Real processes, no stubs except the detacher
# fakes the launch-failure cases need.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB="$HERE/detached-job.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-detached-job-test.XXXXXX")"
# Any job a failed assertion left running is stopped before the record goes.
cleanup() {
  local d
  for d in "$TMP"/*/; do
    [ -f "${d}pid" ] && "$JOB" stop "${d%/}" >/dev/null 2>&1
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
# A job's process group, which its wrapper leads, has no member left.
group_gone() { ! kill -0 -- "-$1" 2>/dev/null; }

export DETACHED_JOB_POLL=1 DETACHED_JOB_STOP_GRACE=2

[ -x "$JOB" ] || { echo "missing or not executable: $JOB"; exit 1; }
bash -n "$JOB" && ok "detached-job.sh is valid bash" || bad "detached-job.sh is valid bash" "bash -n failed"

echo "── start runs the command detached, in a session of its own ──"
OUT=$(GC_SESSION_ID=caller-session "$JOB" start "$TMP/a" -- \
  bash -c 'echo "sid=[${GC_SESSION_ID:-}]"; read -r line; echo "stdin-rc=$?"; echo to-stderr >&2; sleep 4; exit 7'); RC=$?
eq "$RC" 0 "start exits 0"
eq "$(field "$OUT" state)" started "start reports state=started"
PID=$(field "$OUT" pid)
[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && ok "the wrapper it names is running" || bad "the wrapper it names is running" "pid='$PID'"
eq "$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d '[:space:]')" "$PID" "the wrapper leads its own process group"
case "$(ps -o stat= -p "$PID" 2>/dev/null)" in
  *s*) ok "the wrapper leads its own session" ;;
  *) bad "the wrapper leads its own session" "stat='$(ps -o stat= -p "$PID")'" ;;
esac
[ "$(ps -o pgid= -p $$ | tr -d '[:space:]')" != "$PID" ] && ok "the job is outside the caller's process group" \
  || bad "the job is outside the caller's process group" "same pgid as the test"
OUT=$("$JOB" status "$TMP/a"); RC=$?
eq "$RC" 3 "status of a running job exits 3"
eq "$(field "$OUT" state)" running "status reports state=running"

echo "── start refuses a directory whose job is still running ──"
OUT=$("$JOB" start "$TMP/a" -- true); RC=$?
eq "$RC" 2 "a second start exits 2"
eq "$(field "$OUT" state)" busy "it reports state=busy"
kill -0 "$PID" 2>/dev/null && ok "the running job is untouched" || bad "the running job is untouched" "wrapper $PID is gone"

echo "── wait returns the command's exit code once it finishes ──"
OUT=$("$JOB" wait "$TMP/a" --max 60); RC=$?
eq "$RC" 1 "wait on a job that exited 7 exits 1"
eq "$(field "$OUT" state)" "done" "it reports state=done"
eq "$(field "$OUT" rc)" 7 "it reports the command's rc"
LOG=$(cat "$TMP/a/log")
has "$LOG" "sid=[]" "the caller's GC_SESSION_ID is shed"
has "$LOG" "stdin-rc=1" "stdin is /dev/null"
has "$LOG" "to-stderr" "stderr lands in the log"
has "$OUT" "to-stderr" "the report carries the log tail"
OUT=$("$JOB" start "$TMP/a" -- bash -c 'echo second'); RC=$?
eq "$RC" 0 "start reuses a directory whose job finished"
OUT=$("$JOB" wait "$TMP/a" --max 30); RC=$?
eq "$RC" 0 "wait on a job that exited 0 exits 0"
eq "$(field "$OUT" rc)" 0 "the new job's rc replaces the old"
case "$(cat "$TMP/a/log")" in *to-stderr*) bad "the old job's log is cleared" "old output survived" ;; *) ok "the old job's log is cleared" ;; esac

echo "── wait gives up after --max and says the job is still running ──"
"$JOB" start "$TMP/b" -- sleep 30 >/dev/null
T0=$(date +%s)
OUT=$("$JOB" wait "$TMP/b" --max 2); RC=$?
T1=$(date +%s)
eq "$RC" 3 "wait past --max exits 3"
eq "$(field "$OUT" state)" running "it reports state=running"
[ $((T1 - T0)) -lt 8 ] && ok "it returned near --max ($((T1 - T0))s)" || bad "it returned near --max" "took $((T1 - T0))s"

echo "── wait ends when the wrapper dies without writing an exit code ──"
PID=$(cat "$TMP/b/pid")
( sleep 2; kill -KILL "$PID" ) >/dev/null 2>&1 &
T0=$(date +%s)
OUT=$("$JOB" wait "$TMP/b" --max 60); RC=$?
T1=$(date +%s)
eq "$RC" 1 "wait on a killed job exits 1"
eq "$(field "$OUT" state)" died "it reports state=died"
eq "$(field "$OUT" cause)" unknown "a SIGKILL leaves the cause unknown"
[ $((T1 - T0)) -lt 15 ] && ok "it returned once the wrapper was gone ($((T1 - T0))s)" || bad "it returned once the wrapper was gone" "took $((T1 - T0))s"
# The SIGKILLed wrapper could not take its command down; its group is still
# this job's while the orphan holds it.
kill -KILL -- "-$PID" 2>/dev/null

echo "── a signalled wrapper records the signal and takes its job group down ──"
"$JOB" start "$TMP/c" -- bash -c 'sleep 41; true' >/dev/null
PID=$(cat "$TMP/c/pid")
kill -TERM "$PID"
OUT=$("$JOB" wait "$TMP/c" --max 30); RC=$?
eq "$(field "$OUT" state)" died "a TERMed wrapper reads as died"
eq "$(field "$OUT" cause)" signal:TERM "the cause names the signal"
sleep 1
group_gone "$PID" && ok "the command dies with its wrapper" || bad "the command dies with its wrapper" "group $PID survived"

echo "── stop kills a running job and leaves nothing to stop twice ──"
"$JOB" start "$TMP/d" -- bash -c 'sleep 42; true' >/dev/null
PID=$(cat "$TMP/d/pid")
OUT=$("$JOB" stop "$TMP/d"); RC=$?
eq "$RC" 0 "stop exits 0"
eq "$(field "$OUT" state)" stopped "it reports state=stopped"
group_gone "$PID" && ok "the job's whole group is gone" || bad "the job's whole group is gone" "group $PID survived"
OUT=$("$JOB" status "$TMP/d"); RC=$?
eq "$(field "$OUT" state)/$(field "$OUT" cause)" died/stop "status afterwards reports died, cause=stop"
OUT=$("$JOB" stop "$TMP/d"); RC=$?
eq "$RC" 0 "stop on a finished job exits 0"
OUT=$("$JOB" stop "$TMP/never"); RC=$?
eq "$RC/$(field "$OUT" state)" 0/none "stop where no job ran exits 0 with state=none"
OUT=$("$JOB" wait "$TMP/never" --max 1); RC=$?
eq "$RC/$(field "$OUT" state)" 2/none "wait where no job ran exits 2 with state=none"

echo "── wait stops a job that runs past --limit ──"
"$JOB" start "$TMP/e" -- bash -c 'sleep 43; true' >/dev/null
PID=$(cat "$TMP/e/pid")
OUT=$("$JOB" wait "$TMP/e" --limit 2 --max 30); RC=$?
eq "$RC" 1 "wait past --limit exits 1"
eq "$(field "$OUT" state)" exceeded "it reports state=exceeded"
group_gone "$PID" && ok "the job past its limit is killed" || bad "the job past its limit is killed" "group $PID survived"
OUT=$("$JOB" status "$TMP/e")
eq "$(field "$OUT" cause)" limit:2s "status afterwards names the limit"

echo "── extra descriptors are not inherited, so a caller's pipe is not held open ──"
T0=$(date +%s)
OUT=$("$JOB" start "$TMP/f" -- sleep 44 5>&1 6>&2)
T1=$(date +%s)
eq "$(field "$OUT" state)" started "start with extra descriptors open"
[ $((T1 - T0)) -lt 10 ] && ok "the caller's pipe closed when start returned ($((T1 - T0))s)" \
  || bad "the caller's pipe closed when start returned" "took $((T1 - T0))s"
"$JOB" stop "$TMP/f" >/dev/null

echo "── the python3 detacher ──"
if command -v python3 >/dev/null 2>&1; then
  OUT=$(DETACHED_JOB_DETACHER=python3 "$JOB" start "$TMP/g" -- bash -c 'echo via-python; exit 3'); RC=$?
  eq "$RC/$(field "$OUT" detacher)" 0/python3 "start through python3"
  OUT=$("$JOB" wait "$TMP/g" --max 30)
  eq "$(field "$OUT" rc)" 3 "the python3-launched job's rc is recorded"
else
  ok "python3 not on PATH; its detacher is not exercised here"
fi

# A PATH with what the script needs and neither perl nor python3. Each name
# comes from wherever this host keeps it.
NODET="$TMP/nodet-bin"
mkdir -p "$NODET"
for t in bash env sh date sed tr ps kill sleep mkdir rm cat head tail mv dirname; do
  p=$(command -v "$t" 2>/dev/null) || continue
  case "$p" in /*) ln -sf "$p" "$NODET/$t" ;; esac
done

echo "── no detacher on PATH: start says so and starts nothing ──"
OUT=$(PATH="$NODET" DETACHED_JOB_DETACHER='' "$JOB" start "$TMP/h" -- touch "$TMP/h-ran"); RC=$?
eq "$RC" 2 "start exits 2"
eq "$(field "$OUT" state)/$(field "$OUT" reason)" failed/no-detacher "it reports failed, reason=no-detacher"
[ -e "$TMP/h-ran" ] && bad "nothing ran" "the command ran" || ok "nothing ran"

echo "── a detacher that never forks is reported at once ──"
T0=$(date +%s)
OUT=$(PATH="$NODET" DETACHED_JOB_DETACHER=perl "$JOB" start "$TMP/i" -- touch "$TMP/i-ran"); RC=$?
T1=$(date +%s)
eq "$RC" 2 "start exits 2"
eq "$(field "$OUT" state)/$(field "$OUT" reason)" failed/not-started "it reports failed, reason=not-started"
[ $((T1 - T0)) -lt 10 ] && ok "without waiting out the start window ($((T1 - T0))s)" || bad "without waiting out the start window" "took $((T1 - T0))s"
has "$OUT" "perl" "the log tail names what failed"
OUT=$("$JOB" status "$TMP/i")
eq "$(field "$OUT" state)/$(field "$OUT" cause)" died/never-started "status afterwards reports died, cause=never-started"

echo "── a wrapper that wakes after start gave up never runs the command ──"
# A fake perl that forks a wrapper which waits for a release file before it
# runs, so the launch outlives start's window deterministically.
SLOW="$TMP/slow-bin"
mkdir -p "$SLOW"
cat > "$SLOW/perl" <<'FAKE'
#!/usr/bin/env bash
shift 2
( while [ ! -e "$RELEASE" ]; do sleep 0.2; done; exec "$@" ) </dev/null >/dev/null 2>&1 &
exit 0
FAKE
chmod +x "$SLOW/perl"
OUT=$(PATH="$SLOW:$PATH" RELEASE="$TMP/release" DETACHED_JOB_DETACHER=perl DETACHED_JOB_START_WAIT=1 \
  "$JOB" start "$TMP/j" -- touch "$TMP/j-ran"); RC=$?
eq "$RC/$(field "$OUT" reason)" 2/not-started "start gives up on a launch it cannot see"
: > "$TMP/release"
sleep 2
[ -e "$TMP/j-ran" ] && bad "the late wrapper exits without running the command" "the command ran" \
  || ok "the late wrapper exits without running the command"

echo "── usage errors exit 2 ──"
"$JOB" >/dev/null 2>&1; eq "$?" 2 "no subcommand"
"$JOB" start >/dev/null 2>&1; eq "$?" 2 "start without a directory"
"$JOB" start "$TMP/k" >/dev/null 2>&1; eq "$?" 2 "start without a command"
"$JOB" wait "$TMP/k" --max soon >/dev/null 2>&1; eq "$?" 2 "a non-numeric --max"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
