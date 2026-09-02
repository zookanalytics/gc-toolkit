#!/usr/bin/env bash
# Hermetic test for assets/scripts/doctor-sweep.sh — the detached sweep runner.
# The states it can report are the whole contract, so each one is driven here:
# a stubbed `gc doctor` on PATH supplies the payload, the rc, how long the
# sweep takes and whether it forks a pack check; no live city, no real doctor.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/doctor-sweep.sh"
TMP="$(mktemp -d)"
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
# The ambient city must never be an input; every case names its own state dir.
unset GC_CITY_PATH GC_CITY GC_CITY_ROOT GC_RIG 2>/dev/null || true

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

# STATE is per-case so no case inherits another's stamp.
new_state() { STATE="$TMP/state.$1"; mkdir -p "$STATE"; export GC_DOCTOR_SWEEP_STATE_DIR="$STATE"; }
run() { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }
field() { sed -n "s/^$2=//p" <<< "$1"; }
# The sweep is DETACHED, so the script returns state=started before its child
# has run anything. Every assertion about a launch waits for the child's own
# evidence rather than for the parent's return, which proves only that a launch
# was attempted. The predicate is a function so each poll re-reads the state.
await_until() { # <predicate> [arg]
  local end=$(( $(date +%s) + 20 ))
  until "$@" >/dev/null 2>&1 || [ "$(date +%s)" -ge "$end" ]; do sleep 1; done
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

printf '%s' "$(( $(date +%s) - 3601 ))" > "$STATE/last-start"
run
has "$OUT" "state=started" "once the interval has passed it sweeps again"
await_sweeps 2
eq "$(grep -c . "$STUB_LOG")" "2" "  ... a second run, not a re-read of the first"

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
sleep 1
if kill -0 "$PID" 2>/dev/null; then bad "  ... and the sweep is killed, not left running"
else ok "  ... and the sweep is killed, not left running"; fi
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

# --- --status is a read ------------------------------------------------------
new_state status
: > "$STUB_LOG"
run --status
has "$OUT" "state=idle" "--status reports without acting"
eq "$(grep -c . "$STUB_LOG")" "0" "  ... it starts nothing"
if [ -d "$STATE/current" ]; then bad "  ... and creates no run dir"; else ok "  ... and creates no run dir"; fi

run --nonsense
eq "$RC" "2" "an unknown flag is a usage error"
has "$ERR" "usage: doctor-sweep.sh" "  ... and says so on stderr"
hasnt "$OUT" "usage: doctor-sweep.sh" "  ... never on stdout, which the caller parses"

echo
echo "doctor-sweep: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
