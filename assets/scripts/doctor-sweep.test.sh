#!/usr/bin/env bash
# Hermetic test for assets/scripts/doctor-sweep.sh — the detached sweep runner.
# The states it can report are the whole contract, so each one is driven here:
# a stubbed `gc doctor` on PATH supplies the payload, the rc, how long the
# sweep takes and whether it forks a pack check; no live city, no real doctor.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/doctor-sweep.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-doctor-sweep-test.XXXXXX")"
cleanup() {
  [ -n "${STUB_LOG:-}" ] && pkill -f "$TMP/rig/doctor" >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { if grep -qF -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (missing '$2' in: $1)"; fi; }
hasnt() { if grep -qF -- "$2" <<< "$1"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
# The pre-spawn Dolt health probe. Answer from the fixture the case set (default
# healthy), and do NOT log it: the sweep-count assertions below count doctor
# runs by log line, and the probe is not a sweep.
if [ "${1:-}" = "dolt" ] && [ "${2:-}" = "health" ]; then
  [ -n "${STUB_DOLT_SLEEP:-}" ] && sleep "$STUB_DOLT_SLEEP"
  if [ -n "${STUB_DOLT_HEALTH:-}" ]; then printf '%s' "$STUB_DOLT_HEALTH"
  else printf '%s' '{"server":{"reachable":true,"latency_ms":120}}'; fi
  exit "${STUB_DOLT_RC:-0}"
fi
printf '%s\n' "$*" >> "${STUB_LOG:?}"
[ "${1:-}" = "doctor" ] || exit 0
[ -n "${STUB_CHECK:-}" ] && "$STUB_CHECK" &
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
[ -n "${STUB_PAYLOAD:-}" ] && cat "$STUB_PAYLOAD"
exit "${STUB_RC:-0}"
STUB
chmod +x "$BIN/gc"

export PATH="$BIN:$PATH"

# A pack check the sweep can be caught inside. Its PATH is what names it.
mkdir -p "$TMP/rig/doctor/check-fixture-slow"
cat > "$TMP/rig/doctor/check-fixture-slow/run.sh" <<'CHK'
#!/usr/bin/env bash
sleep 45
CHK
chmod +x "$TMP/rig/doctor/check-fixture-slow/run.sh"

export STUB_LOG="$TMP/gc.log"; : > "$STUB_LOG"
export STUB_SLEEP="" STUB_RC=0 STUB_PAYLOAD="" STUB_CHECK=""
# Pre-spawn gate control: the Dolt health probe answer (empty = healthy default).
export STUB_DOLT_HEALTH="" STUB_DOLT_RC=0 STUB_DOLT_SLEEP=""
# The ambient city must never be an input; every case names its own state dir.
unset GC_CITY_PATH GC_CITY GC_CITY_ROOT GC_RIG 2>/dev/null || true
# The cadence floor defaults to a per-user runtime path; pin it into TMP so no
# case reads or writes the real one, and give each case its own dir below so none
# inherits another's last-start stamp. XDG_RUNTIME_DIR is left as the host set it,
# so the systemd-launch cases still run where a user manager is reachable.
export GC_DOCTOR_SWEEP_CADENCE_DIR="$TMP/cadence.default"; mkdir -p "$GC_DOCTOR_SWEEP_CADENCE_DIR"

payload_ok() { # <file>
  cat > "$1" <<'JSON'
{"passed":1,"warned":1,"failed":1,
 "results":[
  {"name":"city-structure","status":"ok","severity":"advisory","message":"OK"},
  {"name":"fork-rate","status":"warning","severity":"advisory","message":"high fork rate"},
  {"name":"gc-toolkit:check-fixture-slow","status":"error","severity":"advisory",
   "message":"timed out after 1m0s and was abandoned (outcome unknown)","timed_out":true}]}
JSON
}

# STATE and CADENCE are per-case so no case inherits another's stamp. The
# cadence floor lives outside STATE_DIR, so it gets its own per-case dir too.
new_state() { STATE="$TMP/state.$1"; mkdir -p "$STATE"; export GC_DOCTOR_SWEEP_STATE_DIR="$STATE";
              CADENCE="$TMP/cadence.$1"; mkdir -p "$CADENCE"; export GC_DOCTOR_SWEEP_CADENCE_DIR="$CADENCE"; }
run() { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }
field() { sed -n "s/^$2=//p" <<< "$1"; }
# The sweep is DETACHED, so the script returns state=started before its child
# has run anything. Every assertion about a launch waits for the child's own
# evidence rather than for the parent's return, which proves only that a launch
# was attempted. The predicate is a function so each poll re-reads the state.
await_until() { # <predicate> [arg]
  local end=$(( $(date +%s) + 20 ))
  # Poll finely: these awaits wait on a DETACHED child's evidence, which lands
  # in tens of milliseconds, so a 1s tick spent up to a second per await — and
  # there are ~20 of them. The 20s ceiling is the real bound; the interval only
  # sets how promptly a satisfied predicate is noticed.
  until "$@" >/dev/null 2>&1 || [ "$(date +%s)" -ge "$end" ]; do sleep 0.05; done
}
# The rc file is written last, by rename, so it is the completion signal.
have_rc()     { [ -f "$STATE/current/rc" ]; }
have_pid()    { [ -s "$STATE/current/pid" ]; }
swept()       { [ "$(grep -c . "$STUB_LOG")" -ge "$1" ]; }
check_alive() { pgrep -f "$TMP/rig/doctor/check-fixture-slow/run.sh"; }
# The bound case runs at GC_DOCTOR_SWEEP_BOUND=0, and elapsed is whole seconds,
# so the sweep is only past its bound once its start second is behind us.
past_bound()  { [ "$(date +%s)" -gt "$(cat "$STATE/current/started_at")" ]; }
await_run()    { await_until have_rc; }
await_sweeps() { await_until swept "$1"; }

# --- an unusable state dir is loud, never a clean-looking idle ---------------
mkdir -p "$TMP/nowrite"; chmod 500 "$TMP/nowrite"
OUT=$(GC_DOCTOR_SWEEP_STATE_DIR="$TMP/nowrite/sub" "$SUT" 2>/dev/null); RC=$?
eq "$RC" "2" "an unwritable state dir exits 2"
has "$OUT" "state=blocked" "  ... and reports blocked rather than idle"
chmod 700 "$TMP/nowrite"

# --- the full happy path: start, run, collect, then hold -------------------
new_state happy
payload_ok "$TMP/payload.json"
export STUB_PAYLOAD="$TMP/payload.json" STUB_RC=1 STUB_SLEEP=3
run
eq "$RC" "0" "the first pass exits 0"
has "$OUT" "state=started" "  ... starts a sweep when nothing has ever run"
has "$OUT" "bound=1800" "  ... and reports the bound it will enforce"
eq "$(cat "$STATE/last-start")" "$(field "$OUT" run | xargs -I{} cat {}/started_at)" \
  "the interval stamp and the run agree on when it started"

run
has "$OUT" "state=running" "a second pass while it works reports running"
await_sweeps 1
eq "$(grep -c . "$STUB_LOG")" "1" "  ... and does NOT start a second sweep"
hasnt "$OUT" "state=started" "  ... the run dir is the start guard"

await_run
run
has "$OUT" "state=complete" "the pass after it finishes collects the payload"
eq "$(field "$OUT" finished_at)" "$(cat "$STATE/current/finished_at")" \
  "  ... carrying the second the sweep finished"
AGE=$(field "$OUT" age)
if [ "$AGE" -ge 0 ] && [ "$AGE" -le 60 ]; then ok "  ... and the payload's age, counted from that second"
else bad "  ... and the payload's age, counted from that second (got '$AGE')"; fi
eq "$(field "$OUT" rc)" "1" "  ... rc 1 is doctor's normal findings-exist exit, not a failure"
eq "$(field "$OUT" checks)" "3" "  ... counts the checks"
eq "$(field "$OUT" findings)" "2" "  ... counts what is not ok"
eq "$(field "$OUT" abandoned)" "1" "  ... counts the checks abandoned at their own timeout"
eq "$(field "$OUT" abandoned_checks)" "gc-toolkit:check-fixture-slow" "  ... and names them"
eq "$(jq -r '.results | length' "$(field "$OUT" payload)")" "3" "  ... the payload path it prints is readable"

run
has "$OUT" "state=idle" "the next pass holds — one sweep per interval"
NEXT=$(field "$OUT" next_in)
if [ "$NEXT" -gt 3400 ] && [ "$NEXT" -le 3600 ]; then ok "  ... and the wait is the hour, not the patrol cycle"
else bad "  ... and the wait is the hour, not the patrol cycle (got '$NEXT')"; fi
eq "$(grep -c . "$STUB_LOG")" "1" "  ... still exactly one sweep run"

# An elapsed interval is an aged window-start now; last-start ages with it, and
# so does the cadence floor's own stamp — otherwise the floor would hold this
# second start back seconds after the first, which is exactly its job.
printf '%s' "$(( $(date +%s) - 3601 ))" > "$STATE/window-start"
printf '%s' "$(( $(date +%s) - 3601 ))" > "$STATE/last-start"
printf '%s' "$(( $(date +%s) - 3601 ))" > "$CADENCE/last-start"
run
has "$OUT" "state=started" "once the interval has passed it sweeps again"
await_sweeps 2
eq "$(grep -c . "$STUB_LOG")" "2" "  ... a second run, not a re-read of the first"

# --- the recorded pid is a real pid, in whichever mode launched it ----------
# The body is a file, not an inline `sh -c` string, so systemd's argv expansion
# cannot turn the wrapper's `$$` into a literal `$`. A pid that is not a number
# is that regression, and it strands every later collect on a `kill -0` of
# garbage. The fallback row runs everywhere; the systemd row runs only where a
# user manager is reachable, which is the only place the regression can occur.
new_state pidfallback
: > "$STUB_LOG"; export STUB_SLEEP=2 STUB_RC=1 STUB_PAYLOAD="$TMP/payload.json"
GC_DOCTOR_SWEEP_NO_SYSTEMD=1 "$SUT" >/dev/null
await_until have_pid
PID=$(cat "$STATE/current/pid" 2>/dev/null)
if [[ "$PID" =~ ^[0-9]+$ ]]; then ok "the setsid/nohup fallback records a numeric pid"
else bad "the setsid/nohup fallback records a numeric pid (got '$PID')"; fi
await_run
if command -v systemd-run >/dev/null 2>&1 && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  new_state pidsystemd
  : > "$STUB_LOG"; export STUB_SLEEP=2 STUB_RC=1 STUB_PAYLOAD="$TMP/payload.json"
  "$SUT" >/dev/null
  await_until have_pid
  PID=$(cat "$STATE/current/pid" 2>/dev/null)
  if [[ "$PID" =~ ^[0-9]+$ ]]; then ok "the transient user service records a numeric pid, never a systemd-expanded \$"
  else bad "the transient user service records a numeric pid (got '$PID')"; fi
  await_run
fi
export STUB_SLEEP=0 STUB_RC=0 STUB_PAYLOAD=""

# --- a finished sweep is collected only while its payload is current --------
# A payload describes the city at the second its sweep finished, and a patrol
# that stopped for hours reaches it late. Each run here is written by hand the
# way the wrapper leaves a finished one: an rc, a finished_at second, and a
# whole payload with findings in it, so a collect that ignored the age would
# report them as complete.
seed_finished() { # <started_at> <finished_at> <rc>
  mkdir -p "$STATE/current"
  printf '%s' "$1" > "$STATE/current/started_at"
  printf '%s' "$2" > "$STATE/current/finished_at"
  payload_ok "$STATE/current/payload.json"
  printf '%s' "$3" > "$STATE/current/rc"
}
export STUB_PAYLOAD="$TMP/payload.json" STUB_RC=1 STUB_SLEEP=0

new_state stale
: > "$STUB_LOG"
FIN=$(( $(date +%s) - 3601 ))
# The window and cadence stamps the run's own start left behind.
printf '%s' "$(( FIN - 600 ))" > "$STATE/window-start"
printf '%s' "$(( FIN - 600 ))" > "$STATE/last-start"
printf '1'                     > "$STATE/attempts"
printf '%s' "$(( FIN - 600 ))" > "$CADENCE/last-start"
seed_finished "$(( FIN - 600 ))" "$FIN" 1
run
has "$OUT" "state=stale" "a sweep that finished more than an interval ago is stale, never complete"
hasnt "$OUT" "payload=" "  ... it names no payload, so no filter reads its findings"
hasnt "$OUT" "findings=" "  ... and counts none"
eq "$(field "$OUT" finished_at)" "$FIN" "  ... it says when the sweep finished"
AGE=$(field "$OUT" age)
if [ "$AGE" -gt 3600 ]; then ok "  ... and how long ago, past the interval"
else bad "  ... and how long ago, past the interval (got '$AGE')"; fi
eq "$(field "$OUT" interval)" "3600" "  ... and the interval it was held to"
eq "$(cat "$STATE/last-outcome")" "stale" "  ... recording last-outcome=stale"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... and starting nothing in the same pass"
printf '%s\n' "$OUT" > "$TMP/report-stale"
run
has "$OUT" "state=started" "the next pass starts a fresh sweep in its place"
await_run
run
has "$OUT" "state=complete" "  ... which is collected as current"
eq "$(grep -c . "$STUB_LOG")" "1" "  ... from one real sweep, not the stale run read again"
AGE=$(field "$OUT" age)
if [ "$AGE" -le 60 ]; then ok "  ... its age counted from its own finish"
else bad "  ... its age counted from its own finish (got '$AGE')"; fi

# A failed run that old is stale too: its failure is not a current one.
new_state stale_failed
FIN=$(( $(date +%s) - 3601 ))
seed_finished "$(( FIN - 600 ))" "$FIN" 2
run
has "$OUT" "state=stale" "a failed run that finished more than an interval ago is stale, not a current failure"
hasnt "$OUT" "rc=" "  ... and carries no exit code to file"

# Just inside the interval the same run is current.
new_state fresh_finish
FIN=$(( $(date +%s) - 3500 ))
seed_finished "$(( FIN - 600 ))" "$FIN" 1
run
has "$OUT" "state=complete" "a sweep that finished inside the interval is collected complete"
eq "$(field "$OUT" finished_at)" "$FIN" "  ... carrying when it finished"
eq "$(field "$OUT" findings)" "2" "  ... and its findings"

# The bound is the configured interval, not a fixed hour: 2000s is current at
# the default and stale at 1800.
new_state stale_knob
FIN=$(( $(date +%s) - 2000 ))
seed_finished "$(( FIN - 600 ))" "$FIN" 1
OUT=$(GC_DOCTOR_SWEEP_INTERVAL=1800 "$SUT")
has "$OUT" "state=stale" "at a 1800s interval a sweep that finished 2000s ago is stale"
eq "$(field "$OUT" interval)" "1800" "  ... held to the configured interval"

# An unreadable finished_at is aged from started_at, which is never later, so
# the fallback can only overstate the age.
new_state stale_nofinish
seed_finished "$(( $(date +%s) - 4000 ))" "not-a-time" 1
run
has "$OUT" "state=stale" "an unreadable finished_at is aged from an old started_at, so the run is stale"
eq "$(field "$OUT" finished_at)" "unknown" "  ... and the report says the finish is unknown"
new_state fresh_nofinish
seed_finished "$(( $(date +%s) - 100 ))" "not-a-time" 1
run
has "$OUT" "state=complete" "  ... while a recent start with an unreadable finish still collects"

# --status reports a stale run and leaves it for the pass that advances.
new_state stale_status
FIN=$(( $(date +%s) - 3601 ))
seed_finished "$(( FIN - 600 ))" "$FIN" 1
run --status
has "$OUT" "state=stale" "--status reports a stale run as stale"
if [ -e "$STATE/current/collected" ]; then bad "  ... without collecting it"; else ok "  ... without collecting it"; fi
if [ -e "$STATE/last-outcome" ]; then bad "  ... or recording an outcome"; else ok "  ... or recording an outcome"; fi
export STUB_SLEEP=0 STUB_RC=0 STUB_PAYLOAD=""

# --- a malformed interval still sweeps hourly -------------------------------
# Nothing routine delivers one: every pour site passes the interval, and an
# omitted declared var renders its default. A bad value must not read as zero.
new_state var
: > "$STUB_LOG"
printf '%s' "$(( $(date +%s) - 100 ))" > "$STATE/last-start"
OUT=$(GC_DOCTOR_SWEEP_INTERVAL='every hour' "$SUT")
has "$OUT" "state=idle" "a malformed interval holds instead of sweeping every pass"
eq "$(field "$OUT" interval)" "3600" "  ... falling back to the hourly default"
has "$OUT" "note=" "  ... and says so"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... no sweep was started"

# --- a sweep past its bound is killed and named -----------------------------
new_state bound
: > "$STUB_LOG"
export STUB_SLEEP=45 STUB_CHECK="$TMP/rig/doctor/check-fixture-slow/run.sh"
GC_DOCTOR_SWEEP_BOUND=0 "$SUT" >/dev/null
await_until have_pid
await_until check_alive
await_until past_bound
PID=$(cat "$STATE/current/pid")
OUT=$(GC_DOCTOR_SWEEP_BOUND=0 "$SUT")
has "$OUT" "state=exceeded" "a sweep past its bound reports exceeded"
has "$OUT" "elapsed=" "  ... carrying the elapsed time the escalation needs"
eq "$(field "$OUT" last_check)" "check-fixture-slow" "  ... and the check it was inside"
# The SUT issued the kill above; give SIGTERM a moment to land, then confirm.
sleep 0.3
if kill -0 "$PID" 2>/dev/null; then bad "  ... and the sweep is killed, not left running"
else ok "  ... and the sweep is killed, not left running"; fi
eq "$(cat "$STATE/last-outcome")" "failed" "  ... and records the exceeded run failed, so it can retry"
export STUB_SLEEP=0 STUB_CHECK=""

# --- a bad exit and a bad payload are both FAILED scans ---------------------
new_state rc2
: > "$STUB_LOG"; export STUB_RC=2
run; await_run; run
has "$OUT" "state=failed" "an rc other than 0/1 is a failed scan"
eq "$(field "$OUT" reason)" "doctor-rc" "  ... named as the exit code"
has "$OUT" "stderr=" "  ... pointing at the sweep's stderr"

new_state drift
: > "$STUB_LOG"; export STUB_RC=0
printf '%s' '{"checks":[{"name":"x","status":"ok"}]}' > "$TMP/drifted.json"
export STUB_PAYLOAD="$TMP/drifted.json"
run; await_run; run
has "$OUT" "state=failed" "a payload without .results is a failed scan, never clean"
eq "$(field "$OUT" reason)" "payload-invalid" "  ... named as the payload"

new_state null
: > "$STUB_LOG"; export STUB_RC=0
printf '%s' '{"results":null}' > "$TMP/null-results.json"
export STUB_PAYLOAD="$TMP/null-results.json"
run; await_run; run
has "$OUT" "state=failed" "a results key holding null is a failed scan, not a clean sweep of nothing"
eq "$(field "$OUT" reason)" "payload-invalid" "  ... named as the payload"

new_state notchecks
: > "$STUB_LOG"
printf '%s' '{"results":["city-structure","fork-rate"]}' > "$TMP/not-checks.json"
export STUB_PAYLOAD="$TMP/not-checks.json"
run; await_run; run
has "$OUT" "state=failed" "a results array the count filters cannot read is a failed scan too"
eq "$(field "$OUT" reason)" "payload-invalid" "  ... named as the payload"

new_state ctrl
: > "$STUB_LOG"
payload_ok "$TMP/ctrl.json"
python3 -c 'import sys;p=sys.argv[1];d=open(p).read().replace("high fork rate","high\x01fork rate");open(p,"w").write(d)' "$TMP/ctrl.json"
export STUB_PAYLOAD="$TMP/ctrl.json"
run; await_run; run
has "$OUT" "state=complete" "a control byte in one message is scrubbed, not read as schema drift"
eq "$(field "$OUT" checks)" "3" "  ... and the scrubbed payload still counts"
export STUB_PAYLOAD="$TMP/payload.json" STUB_RC=1

# --- a sweep that dies without an rc is not left in flight forever ----------
new_state gone
sh -c 'exit 0' & DEAD=$!; wait "$DEAD" 2>/dev/null
mkdir -p "$STATE/current"
printf '%s' "$(( $(date +%s) - 100 ))" > "$STATE/current/started_at"
printf '%s' "$DEAD" > "$STATE/current/pid"
run
has "$OUT" "state=failed" "a sweep whose process is gone with no rc is a failed scan"
eq "$(field "$OUT" reason)" "sweep-vanished" "  ... named as the vanished process"
eq "$(field "$OUT" cause)" "unknown" "  ... cause=unknown when it left no death note (an untrappable kill)"

# --- a vanished sweep names the signal that killed it, when it could catch one
# systemd counts SIGTERM/SIGHUP/SIGINT/SIGPIPE as a clean stop and logs no
# failure line, so a reap that uses one is invisible everywhere but here: the
# wrapper's trap records which signal ended it before it dies.
new_state vanished_signal
: > "$STUB_LOG"; export STUB_SLEEP=15 STUB_RC=1 STUB_PAYLOAD="$TMP/payload.json"
GC_DOCTOR_SWEEP_NO_SYSTEMD=1 "$SUT" >/dev/null
await_sweeps 1                       # the wrapper has set its traps and the sweep is running
WPID=$(cat "$STATE/current/pid")
# Signal the whole group: the wrapper's trap fires and the detached child dies
# with it, so nothing is orphaned. Fall back to the wrapper alone off setsid.
kill -TERM -- -"$WPID" 2>/dev/null || kill -TERM "$WPID" 2>/dev/null
await_until test -s "$STATE/current/cause"
run
has "$OUT" "state=failed" "a sweep killed by a catchable signal is a failed scan"
eq "$(field "$OUT" reason)" "sweep-vanished" "  ... still named as the vanished process"
eq "$(field "$OUT" cause)" "signal:TERM" "  ... now carrying the signal that ended it"
LV=$(field "$OUT" launch)
if [ "$LV" = setsid ] || [ "$LV" = nohup ]; then
  ok "  ... and the launcher ($LV), to find the run's own journal"
else bad "  ... and the launcher (got '$LV')"; fi
export STUB_SLEEP=0 STUB_RC=0 STUB_PAYLOAD=""

# --- the detached sweep sheds the caller's session identity -----------------
# The city-wide session-orphan reaper matches a detached process by the
# GC_SESSION_ID in its environ and kills its group, through the systemd-user
# isolation. So the sweep must not carry the launching session's id, or that
# session's next teardown reaps it mid-run. The check reads the child's own
# environ, in whichever mode launched it.
environ_has_session() { local e; e=$(tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null); grep -q '^GC_SESSION_ID=' <<< "$e"; }
new_state no_session_id
: > "$STUB_LOG"; export STUB_SLEEP=15 STUB_RC=1 STUB_PAYLOAD="$TMP/payload.json"
GC_SESSION_ID=reaper-sentinel GC_DOCTOR_SWEEP_NO_SYSTEMD=1 "$SUT" >/dev/null
await_sweeps 1
WPID=$(cat "$STATE/current/pid")
if environ_has_session "$WPID"; then bad "the setsid/nohup sweep sheds GC_SESSION_ID (the reaper's match key)"
else ok "the setsid/nohup sweep sheds GC_SESSION_ID (the reaper's match key)"; fi
kill -TERM -- -"$WPID" 2>/dev/null || kill -TERM "$WPID" 2>/dev/null

if command -v systemd-run >/dev/null 2>&1 && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  new_state no_session_id_systemd
  : > "$STUB_LOG"; export STUB_SLEEP=15 STUB_RC=1 STUB_PAYLOAD="$TMP/payload.json"
  GC_SESSION_ID=reaper-sentinel "$SUT" >/dev/null
  await_sweeps 1
  WPID=$(cat "$STATE/current/pid")
  if environ_has_session "$WPID"; then bad "the transient user service sheds GC_SESSION_ID too"
  else ok "the transient user service sheds GC_SESSION_ID too"; fi
  UNIT=$(cat "$STATE/current/unit" 2>/dev/null); [ -n "$UNIT" ] && systemctl --user stop "$UNIT" >/dev/null 2>&1
  kill -TERM -- -"$WPID" 2>/dev/null || kill -TERM "$WPID" 2>/dev/null
fi
export STUB_SLEEP=0 STUB_RC=0 STUB_PAYLOAD=""

new_state never
mkdir -p "$STATE/current"
printf '%s' "$(( $(date +%s) - 100 ))" > "$STATE/current/started_at"
run
has "$OUT" "state=failed" "a run dir that never recorded a pid is a failed scan"
eq "$(field "$OUT" reason)" "never-started" "  ... named as the launch"

# --- a half-written run record costs one sweep, not every future one --------
# The window is a start that dies between making the run dir and stamping it.
new_state halfborn
: > "$STUB_LOG"
mkdir -p "$STATE/current"
run
has "$OUT" "state=started" "a run dir with no start stamp is cleared, not treated as in flight"
await_sweeps 1
eq "$(grep -c . "$STUB_LOG")" "1" "  ... and the next sweep actually runs"

new_state corrupt
: > "$STUB_LOG"
mkdir -p "$STATE/current"
printf 'not-a-time' > "$STATE/current/started_at"
printf 'not-a-time' > "$STATE/last-start"
run
has "$OUT" "state=started" "an unreadable stamp costs one sweep, not every future one"
# Drain this detached sweep before the next case resets STUB_LOG: its gc call
# logs asynchronously, and a late write would land in the --status count below.
await_sweeps 1

# --- --status is a read ------------------------------------------------------
new_state status
: > "$STUB_LOG"
# Seed a window where a retry is due, so a write would be visible: a start
# would bump attempts, a collection would set last-outcome.
SEED_W=$(( $(date +%s) - 100 ))
printf '%s' "$SEED_W" > "$STATE/window-start"
printf '1'      > "$STATE/attempts"
printf 'failed' > "$STATE/last-outcome"
run --status
has "$OUT" "state=idle" "--status reports without acting"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... it starts nothing"
if [ -d "$STATE/current" ]; then bad "  ... and creates no run dir"; else ok "  ... and creates no run dir"; fi
eq "$(cat "$STATE/window-start")" "$SEED_W" "  ... and leaves window-start untouched"
eq "$(cat "$STATE/attempts")" "1" "  ... and leaves attempts untouched"
eq "$(cat "$STATE/last-outcome")" "failed" "  ... and leaves last-outcome untouched"

run --nonsense
eq "$RC" "2" "an unknown flag is a usage error"
has "$ERR" "usage: doctor-sweep.sh" "  ... and says so on stderr"
hasnt "$OUT" "usage: doctor-sweep.sh" "  ... never on stdout, which the caller parses"

# --- the per-interval start cap: retry a failed sweep, never a completed one,
#     and fall back to hourly when the window state is lost -------------------
# window-start + attempts cap starts to MAX_ATTEMPTS per interval and let one
# follow a failure; last-start is the fallback the pair degrades to. A sweep
# started here is DETACHED, so each case awaits the child's rc before the next
# pass reads it, exactly as the happy path does.
export STUB_PAYLOAD="$TMP/payload.json" STUB_SLEEP=0

new_state cap_complete
: > "$STUB_LOG"; export STUB_RC=1
run
has "$OUT" "state=started" "cap: the window's first sweep starts"
await_run
run
has "$OUT" "state=complete" "cap: it completes"
eq "$(cat "$STATE/last-outcome")" "complete" "  ... recording last-outcome=complete"
run
has "$OUT" "state=idle" "cap: a completed run arms no retry inside the window"
eq "$(grep -c . "$STUB_LOG")" "1" "  ... so no second sweep runs"

new_state cap_failed
: > "$STUB_LOG"; export STUB_RC=2
run
has "$OUT" "state=started" "cap: the window's first sweep starts"
WIN=$(cat "$STATE/window-start")
eq "$(cat "$STATE/attempts")" "1" "  ... as attempt 1 of the window"
await_run
run
has "$OUT" "state=failed" "cap: it fails"
eq "$(cat "$STATE/last-outcome")" "failed" "  ... recording last-outcome=failed"
run
has "$OUT" "state=started" "cap: a failed run earns one retry on the next pass"
eq "$(cat "$STATE/attempts")" "2" "  ... counted as attempt 2 of the same window"
eq "$(cat "$STATE/window-start")" "$WIN" "  ... whose window-start is left in place"
await_run
run
has "$OUT" "state=failed" "cap: the retry fails too"
run
has "$OUT" "state=idle" "cap: a second failure starts no third inside the window"
eq "$(grep -c . "$STUB_LOG")" "2" "  ... only the two starts the cap allows"
NEXT=$(field "$OUT" next_in)
if [ "$NEXT" -gt 0 ] && [ "$NEXT" -le 3600 ]; then ok "  ... and next_in counts down the window"
else bad "  ... and next_in counts down the window (got '$NEXT')"; fi

new_state cap_expiry
: > "$STUB_LOG"; export STUB_RC=1
OLD=$(( $(date +%s) - 3601 ))
printf '%s' "$OLD" > "$STATE/window-start"
printf '%s' "$OLD" > "$STATE/last-start"
printf '2'         > "$STATE/attempts"
printf 'failed'    > "$STATE/last-outcome"
run
has "$OUT" "state=started" "cap: a window older than the interval sweeps again"
eq "$(cat "$STATE/attempts")" "1" "  ... resetting attempts to 1 for the new window"
if [ "$(cat "$STATE/window-start")" -gt "$OLD" ]; then ok "  ... and moving window-start forward"
else bad "  ... and moving window-start forward (still $OLD)"; fi
await_run

new_state cap_corrupt_attempts
: > "$STUB_LOG"; export STUB_RC=1
RECENT=$(( $(date +%s) - 100 ))
printf '%s' "$RECENT" > "$STATE/window-start"
printf 'NaN'          > "$STATE/attempts"
printf 'failed'       > "$STATE/last-outcome"
printf '%s' "$RECENT" > "$STATE/last-start"
run
has "$OUT" "state=idle" "cap: corrupt attempts holds on a recent last-start"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... no hot loop, though last-outcome=failed"
printf '%s' "$(( $(date +%s) - 3601 ))" > "$STATE/last-start"
run
has "$OUT" "state=started" "  ... and sweeps once the interval since last-start passes"
eq "$(cat "$STATE/attempts")" "1" "  ... self-healing attempts to 1"
await_run

new_state cap_corrupt_window
: > "$STUB_LOG"; export STUB_RC=1
printf 'not-a-time' > "$STATE/window-start"
printf '1'          > "$STATE/attempts"
printf 'failed'     > "$STATE/last-outcome"
printf '%s' "$(( $(date +%s) - 100 ))" > "$STATE/last-start"
run
has "$OUT" "state=idle" "cap: corrupt window-start holds on a recent last-start too"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... a lost window costs the retry, not the hourly ceiling"

# --- the MAX_ATTEMPTS knob, and its floor of 1 -------------------------------
# The default window earns one retry after a failed run (proven above); the knob
# tunes that, and a value below 1 is clamped so it can never disable sweeping.
# At GC_DOCTOR_SWEEP_MAX_ATTEMPTS=1 that retry is refused: seed the state a failed
# run leaves, where the default-2 window would start a retry, and prove the knob
# holds it at idle instead.
new_state cap_knob_one
export GC_DOCTOR_SWEEP_MAX_ATTEMPTS=1
: > "$STUB_LOG"
RECENT=$(( $(date +%s) - 100 ))
printf '%s' "$RECENT" > "$STATE/window-start"
printf '1'            > "$STATE/attempts"
printf 'failed'       > "$STATE/last-outcome"
printf '%s' "$RECENT" > "$STATE/last-start"
run
has "$OUT" "state=idle" "knob: MAX_ATTEMPTS=1 arms no retry the default-2 window would"
eq "$(cat "$STATE/attempts")" "1" "  ... leaving attempts at 1"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... and starting no sweep"
unset GC_DOCTOR_SWEEP_MAX_ATTEMPTS

# Zero is too low: it clamps to 1, which still sweeps a due window (never
# disabling the patrol) but arms no retry, exactly as MAX_ATTEMPTS=1 does.
new_state cap_knob_zero
export GC_DOCTOR_SWEEP_MAX_ATTEMPTS=0
: > "$STUB_LOG"; export STUB_RC=2
OLD=$(( $(date +%s) - 3601 ))
printf '%s' "$OLD" > "$STATE/window-start"
printf '%s' "$OLD" > "$STATE/last-start"
printf '2'         > "$STATE/attempts"
printf 'failed'    > "$STATE/last-outcome"
run
has "$OUT" "state=started" "knob: MAX_ATTEMPTS=0 is clamped to 1, so a due window still sweeps"
eq "$(cat "$STATE/attempts")" "1" "  ... as attempt 1 of the fresh window"
await_run
run
has "$OUT" "state=failed" "  ... the clamped run fails"
eq "$(cat "$STATE/last-outcome")" "failed" "  ... recording last-outcome=failed"
run
has "$OUT" "state=idle" "  ... and the floor of 1 arms no retry, never a hot loop"
eq "$(grep -c . "$STUB_LOG")" "1" "  ... only the single start the clamped minimum allows"
unset GC_DOCTOR_SWEEP_MAX_ATTEMPTS

# --- the pre-spawn Dolt health gate: a degraded data plane defers the start --
# A sweep queries every store's Dolt, so starting one while the data plane is
# unreachable or overloaded is the amplifier that turned a slowdown into a
# collapse. The gate stands the sweep down instead — and because it sits past
# the start decision, it brakes both the ordinary hourly start and the retry a
# failed run arms, without spending either's state.
export STUB_PAYLOAD="$TMP/payload.json" STUB_RC=1 STUB_SLEEP=0

new_state dolt_unreachable
: > "$STUB_LOG"
export STUB_DOLT_HEALTH='{"server":{"reachable":false}}'
run
has "$OUT" "state=deferred" "an unreachable Dolt defers the start instead of sweeping"
has "$OUT" "reason=dolt-degraded" "  ... naming why"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... and starts no sweep"
if [ -d "$STATE/current" ]; then bad "  ... and creates no run dir"; else ok "  ... and creates no run dir"; fi

new_state dolt_overloaded
: > "$STUB_LOG"
export STUB_DOLT_HEALTH='{"server":{"reachable":true,"latency_ms":9999}}'
run
has "$OUT" "state=deferred" "a Dolt server past the latency ceiling defers too"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... starting nothing"

# The deferred start is held, not spent: window-start and attempts are left
# untouched, so the SAME due start fires once Dolt recovers.
new_state dolt_recover
: > "$STUB_LOG"
export STUB_DOLT_HEALTH='{"server":{"reachable":false}}'
run
has "$OUT" "state=deferred" "degraded: the due start defers"
if [ -e "$STATE/window-start" ]; then bad "  ... and stamps no window-start while deferred"; else ok "  ... and stamps no window-start while deferred"; fi
export STUB_DOLT_HEALTH='{"server":{"reachable":true,"latency_ms":80}}'
run
has "$OUT" "state=started" "once Dolt recovers the held start fires"
await_run

# A Dolt-caused failure arms no retry while Dolt stays degraded: seed the state
# a failed run leaves (window open, a retry due), hold it degraded, and prove no
# sweep starts and no attempt is burned — then recovery lets the retry run.
new_state dolt_retry_held
: > "$STUB_LOG"
RECENT=$(( $(date +%s) - 100 ))
printf '%s' "$RECENT" > "$STATE/window-start"
printf '1'            > "$STATE/attempts"
printf 'failed'       > "$STATE/last-outcome"
printf '%s' "$RECENT" > "$STATE/last-start"
export STUB_DOLT_HEALTH='{"server":{"reachable":false}}'
run
has "$OUT" "state=deferred" "a failed run's retry defers while Dolt is degraded"
eq "$(cat "$STATE/attempts")" "1" "  ... burning no attempt on a sweep that never ran"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... and starting no retry"
export STUB_DOLT_HEALTH='{"server":{"reachable":true,"latency_ms":80}}'
run
has "$OUT" "state=started" "  ... and the retry fires once Dolt recovers"
eq "$(cat "$STATE/attempts")" "2" "  ... counted as attempt 2 of the same window"
await_run

# An unprovable probe must NOT disable sweeping: a health check that returns an
# unreadable answer, or fails outright, is treated as healthy-enough to proceed,
# so a broken probe can never silence the patrol. The report says the gate was
# skipped, so a skip never reads as a pass.
new_state dolt_unprovable
: > "$STUB_LOG"
export STUB_DOLT_RC=0 STUB_DOLT_HEALTH='not json'
run
has "$OUT" "state=started" "an unreadable health probe proceeds, never blocks the sweep"
has "$OUT" "note=Dolt health gate skipped: health probe answer carried no readable server.latency_ms" "  ... and the report says the gate was skipped"
await_run

new_state dolt_probe_failed
: > "$STUB_LOG"
export STUB_DOLT_RC=3 STUB_DOLT_HEALTH='{"server":{"reachable":false}}'
run
has "$OUT" "state=started" "a health probe that exits non-zero proceeds, its output unread"
has "$OUT" "note=Dolt health gate skipped: health probe exited 3" "  ... naming the exit code"
await_run
export STUB_DOLT_RC=0 STUB_DOLT_HEALTH=""

# How long the report takes is not a Dolt signal. `gc dolt health` caps each of
# its own Dolt calls, so a slow report measures the host and the gc calls it
# makes. A report that runs long and finishes is judged on what it says.
new_state dolt_probe_slow_healthy
: > "$STUB_LOG"
export STUB_DOLT_SLEEP=2 GC_DOCTOR_SWEEP_DOLT_PROBE_TIMEOUT=6
run
has "$OUT" "state=started" "a slow health report that says reachable and fast starts the sweep"
hasnt "$OUT" "Dolt health gate skipped" "  ... on its verdict, not on a skipped gate"
await_run

new_state dolt_probe_slow_unreachable
: > "$STUB_LOG"
export STUB_DOLT_HEALTH='{"server":{"reachable":false}}'
run
has "$OUT" "state=deferred" "a slow health report that says unreachable still defers"
has "$OUT" "detail=Dolt server unreachable" "  ... on what it said"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... starting nothing"

# The bound is a hang guard. A probe still running at it proved nothing, so the
# start proceeds and the report says the gate was skipped. The answer this probe
# would have given is unreachable, so the case also shows a cut answer is never
# guessed at.
new_state dolt_probe_timeout
: > "$STUB_LOG"
export STUB_DOLT_SLEEP=3 GC_DOCTOR_SWEEP_DOLT_PROBE_TIMEOUT=1 STUB_DOLT_HEALTH='{"server":{"reachable":false}}'
run
has "$OUT" "state=started" "a health probe cut at its bound proceeds instead of deferring"
has "$OUT" "note=Dolt health gate skipped: health probe gave no answer within 1s" "  ... and the report says the gate was skipped"
await_run
eq "$(grep -c . "$STUB_LOG")" "1" "  ... and the sweep ran"
unset GC_DOCTOR_SWEEP_DOLT_PROBE_TIMEOUT
export STUB_DOLT_SLEEP="" STUB_DOLT_HEALTH=""

# The default bound is the one the usage text names. A malformed value falls
# back to it out loud, from an idle pass that runs no probe.
new_state dolt_probe_default
: > "$STUB_LOG"
printf '%s' "$(( $(date +%s) - 100 ))" > "$STATE/last-start"
OUT=$(GC_DOCTOR_SWEEP_DOLT_PROBE_TIMEOUT='soon' "$SUT" 2>/dev/null)
has "$OUT" "GC_DOCTOR_SWEEP_DOLT_PROBE_TIMEOUT='soon' is not a number, using 90" "a malformed probe bound falls back to the 90s default"
has "$("$SUT" --help 2>&1)" "is unproven and defers nothing (default 90)" "  ... the default the usage text names"

# --- the pre-spawn cadence floor: the one cross-session gate -----------------
# STATE_DIR can go blind — a per-session fallback a recycled session does not
# inherit — and that is what let one incident start a burst of sweeps at once.
# The cadence floor is the STATE_DIR-independent gate: a last-start stamp every
# session shares, taken under flock, that holds the interval even when two
# sessions cannot see each other's STATE_DIR. It rests on a file lock, not on a
# query a loaded host cannot answer.
export STUB_PAYLOAD="$TMP/payload.json" STUB_RC=1 STUB_SLEEP=0

# Two sessions, two blind STATE_DIRs, one shared cadence dir: only the first
# sweeps; the second is throttled though its own STATE_DIR shows nothing. This
# is the incident, reproduced — the burst the floor collapses to a single sweep.
SHARED_CADENCE="$TMP/cadence.shared"; mkdir -p "$SHARED_CADENCE"
: > "$STUB_LOG"
OUT=$(GC_DOCTOR_SWEEP_STATE_DIR="$TMP/state.burst-a" GC_DOCTOR_SWEEP_CADENCE_DIR="$SHARED_CADENCE" "$SUT" 2>/dev/null)
has "$OUT" "state=started" "cadence: the first session's sweep starts"
await_sweeps 1
OUT=$(GC_DOCTOR_SWEEP_STATE_DIR="$TMP/state.burst-b" GC_DOCTOR_SWEEP_CADENCE_DIR="$SHARED_CADENCE" "$SUT" 2>/dev/null)
has "$OUT" "state=throttled" "cadence: a second session with a blind STATE_DIR is throttled, not a second start"
has "$OUT" "reason=cadence-floor" "  ... named as the floor, not STATE_DIR, that caught it"
eq "$(grep -c . "$STUB_LOG")" "1" "  ... so exactly one sweep ran across both sessions"
if [ -d "$TMP/state.burst-b/current" ]; then bad "  ... and the throttled session creates no run dir"; else ok "  ... and the throttled session creates no run dir"; fi

# A start due by STATE_DIR is throttled while the floor's own stamp is recent.
new_state cadence_recent
: > "$STUB_LOG"
printf '%s' "$(( $(date +%s) - 100 ))" > "$CADENCE/last-start"
run
has "$OUT" "state=throttled" "cadence: a due start is throttled while the floor's stamp is inside the interval"
has "$OUT" "floor=3600" "  ... reporting the floor it enforced"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... and starts nothing"

# Once the floor has elapsed the same start proceeds, and refreshes the stamp.
new_state cadence_old
: > "$STUB_LOG"
printf '%s' "$(( $(date +%s) - 3601 ))" > "$CADENCE/last-start"
run
has "$OUT" "state=started" "cadence: once the floor has elapsed the start proceeds"
NEWSTAMP=$(cat "$CADENCE/last-start")
if [ "$NEWSTAMP" -gt "$(( $(date +%s) - 60 ))" ]; then ok "  ... and refreshes the floor's stamp, at the cadence dir not STATE_DIR"
else bad "  ... and refreshes the floor's stamp (got '$NEWSTAMP')"; fi
await_run

# The retry a failed run armed is exempt from the floor: it was authorized by a
# STATE_DIR this session could read, where the burst cannot arise. A recent
# floor stamp that would throttle a FRESH start does not hold the retry back.
new_state cadence_retry_exempt
: > "$STUB_LOG"; export STUB_RC=2
RECENT=$(( $(date +%s) - 100 ))
printf '%s' "$RECENT" > "$STATE/window-start"
printf '1'            > "$STATE/attempts"
printf 'failed'       > "$STATE/last-outcome"
printf '%s' "$RECENT" > "$STATE/last-start"
printf '%s' "$RECENT" > "$CADENCE/last-start"
run
has "$OUT" "state=started" "cadence: the retry a failed run armed is exempt from the floor"
eq "$(cat "$STATE/attempts")" "2" "  ... counted as attempt 2 of the window"
await_run
export STUB_RC=1

# --status takes no floor: it reports without starting, so it writes no stamp.
new_state cadence_status
: > "$STUB_LOG"
run --status
has "$OUT" "state=idle" "cadence: --status reports without taking the floor"
if [ -e "$CADENCE/last-start" ]; then bad "  ... and writes no cadence stamp"; else ok "  ... and writes no cadence stamp"; fi
eq "$(grep -c . "$STUB_LOG")" "0" "  ... and starts nothing"

# A cadence dir it cannot write fails OPEN — the patrol is never silenced by a
# broken guard — and the report says the cross-session guard was skipped.
new_state cadence_failopen
: > "$STUB_LOG"
mkdir -p "$TMP/cad-nowrite"; chmod 500 "$TMP/cad-nowrite"
OUT=$(GC_DOCTOR_SWEEP_CADENCE_DIR="$TMP/cad-nowrite/sub" "$SUT" 2>/dev/null)
has "$OUT" "state=started" "cadence: an unwritable cadence dir fails open, never silences the sweep"
has "$OUT" "cadence floor unavailable" "  ... and the note says the guard was skipped"
chmod 700 "$TMP/cad-nowrite"
await_run
export STUB_DOLT_HEALTH="" STUB_PAYLOAD="" STUB_RC=0

# --- the shipped patrol step must handle every state this script reports -----
# The step is prose plus one snippet, read by an agent, and both halves can go
# wrong on their own: the snippet has to survive a runner that exits non-zero,
# and the decision table has to name every state the runner can emit. A state
# the table omits is a sweep that stops without a visit, which is the failure
# the whole runner exists to end.
TOML="$HERE/../../formulas/mol-deacon-patrol.toml"
# The description is a TOML basic multi-line string, so a literal backslash
# ships escaped; un-escape to recover the shell text the deacon runs.
sed -n '/# >>> doctor-sweep-run/,/# <<< doctor-sweep-run/p' "$TOML" \
    | sed 's/\\\\/\\/g' > "$TMP/step-snippet.sh"
if [ -s "$TMP/step-snippet.sh" ]; then
  ok "extracted the doctor-sweep-run snippet from the shipped formula"
else
  bad "could not extract the doctor-sweep-run snippet from $TOML (markers gone?)"
fi
if bash -n "$TMP/step-snippet.sh" 2>"$TMP/err"; then
  ok "  ... and it parses as bash"
else
  bad "  ... and it parses as bash ($(cat "$TMP/err"))"
fi

# A rig root holding a scripted runner, so the snippet resolves one the way it
# does in the city and no real sweep is involved.
FORMULA_RIG="$TMP/formula-rig"; mkdir -p "$FORMULA_RIG/assets/scripts"
cat > "$FORMULA_RIG/assets/scripts/doctor-sweep.sh" <<'RUNNER'
#!/usr/bin/env bash
cat "${STUB_REPORT:?}"
exit "${STUB_REPORT_RC:-0}"
RUNNER
chmod +x "$FORMULA_RIG/assets/scripts/doctor-sweep.sh"

# Under `set -e` an uncaptured non-zero assignment ends the block before the
# report is echoed, so the snippet is driven in the strictest shell it can meet.
snippet_run() { # <report-file> <rc>
  SNIP_OUT=$(STUB_REPORT="$1" STUB_REPORT_RC="$2" GC_RIG_ROOT="$FORMULA_RIG" \
    bash -euo pipefail -c '. "$0"; printf "read-state=%s\nread-rc=%s\nread-payload=%s\n" \
      "${STATE:-}" "${RC:-}" "${PAYLOAD:-}"' "$TMP/step-snippet.sh" 2>"$TMP/snip.err")
  SNIP_RC=$?
}

printf 'state=blocked\nreason=state-dir-unwritable\nstate_dir=/dev/null/doctor\n' \
  > "$TMP/report-blocked"
snippet_run "$TMP/report-blocked" 2
eq "$SNIP_RC" "0" "a blocked runner does not abort the step's snippet"
has "$SNIP_OUT" "state=blocked" "  ... the report still reaches the transcript"
has "$SNIP_OUT" "reason=state-dir-unwritable" "  ... carrying why it could not sweep"
has "$SNIP_OUT" "read-state=blocked" "  ... and the state is readable for the table"
has "$SNIP_OUT" "read-rc=2" "  ... with the runner's exit code kept"

printf 'state=complete\nrc=1\nelapsed=503\npayload=%s\n' "$TMP/payload.json" \
  > "$TMP/report-complete"
snippet_run "$TMP/report-complete" 0
eq "$SNIP_RC" "0" "a completed sweep still reads through the same snippet"
has "$SNIP_OUT" "read-state=complete" "  ... state=complete is readable"
has "$SNIP_OUT" "read-payload=$TMP/payload.json" "  ... and the payload path survives"
has "$SNIP_OUT" "read-rc=0" "  ... with rc 0"

# The runner's own stale report, read through the shipped snippet: it names no
# payload, so the filter after the table has nothing to read.
snippet_run "$TMP/report-stale" 0
has "$SNIP_OUT" "read-state=stale" "the runner's stale report reads through the snippet as state=stale"
eq "$(sed -n 's/^read-payload=//p' <<< "$SNIP_OUT")" "" "  ... with no payload path for the filter"

# The decision table is asserted against the states the RUNNER can emit, not a
# list copied here: a state added to the script fails this until the step says
# what the deacon owes for it.
STEP="$(awk '/^id = "system-health"$/ {f=1} f && /^\[\[steps\]\]$/ {exit} f {print}' "$TOML")"
if [ -n "$STEP" ]; then
  ok "extracted the shipped system-health step"
else
  bad "could not extract the system-health step from $TOML"
fi
# A call, not the word: the states are the arguments of `report` where it
# opens a statement, never its mention in the usage text.
SCRIPT_STATES=$(grep -vE '^[[:space:]]*#' "$SUT" \
  | grep -oE '^[[:space:]]*report [a-z]+' | awk '{print $NF}' | sort -u)
for st in $SCRIPT_STATES; do
  if grep -qF -- "\`$st\`" <<< "$STEP"; then
    ok "the step's decision table names state=$st"
  else
    bad "the step's decision table never names state=$st (the runner emits it)"
  fi
done
# `blocked` is a failed scan, not a quiet nothing: it means no sweep ran at all.
if grep -qE '^- .*`blocked`.*FAILED scan' <<< "$STEP"; then
  ok "  ... and routes blocked to the failed-scan arm"
else
  bad "  ... but blocked is not routed to the failed-scan arm"
fi
# `stale` is a finished sweep whose payload is too old to file, so it belongs
# with the states that carry nothing to filter.
if grep -qE '^- `stale`: there is no payload' <<< "$STEP"; then
  ok "  ... and routes stale to a no-payload arm, so an old sweep files nothing"
else
  bad "  ... but stale is not routed to a no-payload arm"
fi
if grep -qE '^- Any other state.*FAILED scan' <<< "$STEP"; then
  ok "  ... with a catch-all for a state it does not name"
else
  bad "  ... and has no catch-all, so an unnamed state goes dark"
fi

echo
echo "doctor-sweep: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
