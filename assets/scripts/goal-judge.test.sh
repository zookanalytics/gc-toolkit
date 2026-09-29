#!/usr/bin/env bash
# Tests for goal-judge.sh: the verdict machinery. Runs the real judge against a
# hermetic bead store (stub bd/gc on PATH) with inline oracles, and asserts the
# verdict, exit code, and the writes the judge makes for each of met, not-yet,
# exhausted (iterations and wall-clock), stalled, impossible, invariant
# violation, tamper re-arm, and a fail-closed broken oracle.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/goal-judge.sh"
CANON="$HERE/goal-canonical.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-goal-judge-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; STATE="$TMP/state"
mkdir -p "$BIN" "$STATE"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q -- "$2" "$1" && ok "$3" || bad "$3 (log lacked '$2')"; }
hasnt() { grep -q -- "$2" "$1" && bad "$3 (log unexpectedly had '$2')" || ok "$3"; }

# --- stub bd: serves fixed root/iter/ralph/members and a per-scenario goal, and
# logs every update. bd show returns an array on hit, an error object on miss.
cat > "$BIN/bd" <<'STUB'
#!/usr/bin/env bash
S="$GOAL_TEST_STATE"
cmd="${1:-}"; shift || true
case "$cmd" in
  show)
    case "$1" in
      root1) cat "$S/root.json" ;;
      goal1) cat "$S/goal.json" ;;
      iter1) cat "$S/iter.json" ;;
      *) printf '{"error":"not found"}\n' ;;
    esac ;;
  list)
    case "$*" in *gc.kind=ralph*) cat "$S/ralph.json" ;; *) printf '[]\n' ;; esac ;;
  dep) cat "$S/members.json" ;;
  update)
    id="$1"; shift
    printf 'UPDATE %s %s\n' "$id" "$*" >> "$S/updates.log" ;;
  *) : ;;
esac
STUB
chmod +x "$BIN/bd"

# stub gc: no-op (the judge calls `gc session nudge` on a park).
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$BIN/gc"

# Fixed topology.
printf '[{"id":"root1","metadata":{"gc.var.issue":"goal1","gc.input_convoy_id":"convoy1"}}]\n' > "$STATE/root.json"
printf '[{"id":"iter1","metadata":{"gc.root_bead_id":"root1"}}]\n' > "$STATE/iter.json"
printf '[{"id":"ctrl1","metadata":{"gc.kind":"ralph","gc.max_attempts":"50","gc.root_bead_id":"root1"}}]\n' > "$STATE/ralph.json"
printf '[{"id":"goal1","depth":1,"parent_id":"convoy1"},{"id":"convoy1","depth":0}]\n' > "$STATE/members.json"

export GOAL_TEST_STATE="$STATE"

# Write goal1 with the given metadata object, injecting a matching snapshot so a
# clean scenario does not spuriously re-arm. Pass a second arg to override the
# snapshot (for the tamper test).
scenario() {
  local meta="$1" snap_override="${2:-}"
  printf '[{"id":"goal1","status":"open","title":"dogfood goal","metadata": %s}]\n' "$meta" > "$STATE/goal.json"
  local snap
  if [ -n "$snap_override" ]; then snap="$snap_override"; else snap=$(cat "$STATE/goal.json" | "$CANON"); fi
  jq -c --arg s "$snap" '.[0].metadata["goal.snapshot"]=$s' "$STATE/goal.json" > "$STATE/goal.json.tmp"
  mv "$STATE/goal.json.tmp" "$STATE/goal.json"
  : > "$STATE/updates.log"
}

run_judge() { # $1=attempt ; sets RC and leaves updates.log
  GC_WISP_ID=root1 GC_BEAD_ID=iter1 GC_ITERATION="$1" \
    PATH="$BIN:$PATH" bash "$SUT" >/dev/null 2>&1
}

L="$STATE/updates.log"

# --- met (metric): value under threshold -------------------------------------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 25","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"6"}'
set +e; run_judge 1; RC=$?; set -e
eq "$RC" "0" "met: exit 0"
has "$L" "goal.status=met" "met: sets goal.status=met"
has "$L" "status=closed" "met: closes the goal"

# --- not-yet (metric): value over threshold, budget remains ------------------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 40","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"6"}'
set +e; run_judge 1; RC=$?; set -e
eq "$RC" "1" "not-yet: exit 1"
has "$L" "goal.trail=" "not-yet: records the trail"
has "$L" "goal.not_yet_reason=measured 40, need le 30" "not-yet: threads the current reason to goal.not_yet_reason (the field the iteration step reads)"
hasnt "$L" "goal.status=" "not-yet: does not set a terminal status"

# --- exhausted (iteration budget) --------------------------------------------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 40","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"2"}'
set +e; run_judge 2; RC=$?; set -e
eq "$RC" "0" "exhausted(iterations): exit 0"
has "$L" "goal.status=parked" "exhausted(iterations): parks"
has "$L" "goal.parked_verdict=exhausted" "exhausted(iterations): verdict exhausted"
has "$L" "assignee human" "exhausted(iterations): reassigns to escalation target"

# --- exhausted (wall-clock past deadline) ------------------------------------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 40","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"99","goal.wall_clock_deadline":"2000-01-01T00:00:00Z"}'
set +e; run_judge 1; RC=$?; set -e
eq "$RC" "0" "exhausted(wall-clock): exit 0"
has "$L" "goal.parked_verdict=exhausted" "exhausted(wall-clock): verdict exhausted"

# --- stalled: same signature and no improvement vs the previous attempt ------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 40","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"99","goal.trail":"[{\"attempt\":1,\"verdict\":\"not-yet\",\"reason\":\"measured 40, need le 30\",\"value\":\"40\",\"sig\":\"need le 30\"}]"}'
set +e; run_judge 2; RC=$?; set -e
eq "$RC" "0" "stalled: exit 0"
has "$L" "goal.parked_verdict=stalled" "stalled: verdict stalled"

# --- not-yet when progressing (value improved) even with same signature ------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 35","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"99","goal.trail":"[{\"attempt\":1,\"verdict\":\"not-yet\",\"reason\":\"measured 40, need le 30\",\"value\":\"40\",\"sig\":\"need le 30\"}]"}'
set +e; run_judge 2; RC=$?; set -e
eq "$RC" "1" "progressing: exit 1 (not stalled — value moved toward threshold)"
hasnt "$L" "goal.status=parked" "progressing: does not park"

# --- stalled on a WORSENING metric: the value changes each attempt (so the
# reason text changes) but the value-free signature is stable, so the stall is
# still caught instead of burning the whole budget (finding: stall keyed on
# reason never fired when the measured value moved) --------------------------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 45","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"99","goal.trail":"[{\"attempt\":1,\"verdict\":\"not-yet\",\"reason\":\"measured 40, need le 30\",\"value\":\"40\",\"sig\":\"need le 30\"}]"}'
set +e; run_judge 2; RC=$?; set -e
eq "$RC" "0" "stalled(worsening): exit 0 — value moved away but the signature matched"
has "$L" "goal.parked_verdict=stalled" "stalled(worsening): parks despite the changed value"

# --- impossible (command oracle exits 3) -------------------------------------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"command","goal.oracle.command":"exit 3","goal.budget.max_iterations":"6"}'
set +e; run_judge 1; RC=$?; set -e
eq "$RC" "0" "impossible: exit 0"
has "$L" "goal.parked_verdict=impossible" "impossible: verdict impossible"

# --- command oracle met (exit 0) ---------------------------------------------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"command","goal.oracle.command":"exit 0","goal.budget.max_iterations":"6"}'
set +e; run_judge 1; RC=$?; set -e
eq "$RC" "0" "command met: exit 0"
has "$L" "goal.status=met" "command met: sets goal.status=met"

# --- invariant violation fails the iteration even when the oracle passes ------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 25","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"6","goal.invariants":"[\"exit 1\"]"}'
set +e; run_judge 1; RC=$?; set -e
eq "$RC" "1" "invariant violation: not-yet (exit 1) despite the oracle passing"
hasnt "$L" "goal.status=met" "invariant violation: does not mark met"

# --- fail-closed: a broken metric oracle is never met ------------------------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo notanumber","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"6"}'
set +e; run_judge 1; RC=$?; set -e
eq "$RC" "1" "broken oracle: not-yet (exit 1), never met"
hasnt "$L" "goal.status=met" "broken oracle: does not mark met"

# --- fail-closed: a punctuation-only or malformed metric value is not a number.
# A character class alone accepts '-', '+', '.', '1-2', '1.2.3'; awk then
# coerces them (e.g. '-' to 0) and would false-report the goal met.
for badv in - + . 1-2 1.2.3; do
  scenario "{\"goal.statement\":\"cut it\",\"goal.oracle.kind\":\"metric\",\"goal.oracle.command\":\"echo $badv\",\"goal.oracle.compare\":\"le\",\"goal.oracle.threshold\":\"30\",\"goal.budget.max_iterations\":\"6\"}"
  set +e; run_judge 1; RC=$?; set -e
  eq "$RC" "1" "malformed metric value '$badv': not-yet (exit 1), never met"
  hasnt "$L" "goal.status=met" "malformed metric value '$badv': does not mark met"
done

# --- a malformed THRESHOLD is rejected, not coerced (defense in depth:
# goal-arm.sh validates it first, but the judge must not let a hand-edited
# contract through — coercing '-' to 0 here would mark an unmet goal met under
# a ge comparison).
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 25","goal.oracle.compare":"ge","goal.oracle.threshold":"-","goal.budget.max_iterations":"6"}'
set +e; run_judge 1; RC=$?; set -e
eq "$RC" "1" "malformed threshold '-': not-yet (exit 1), never met"
hasnt "$L" "goal.status=met" "malformed threshold '-': does not mark met"

# --- a decimal value under a decimal threshold is still met: the strict parser
# must not over-tighten and reject legitimate fractions.
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 29.5","goal.oracle.compare":"le","goal.oracle.threshold":"30.0","goal.budget.max_iterations":"6"}'
set +e; run_judge 1; RC=$?; set -e
eq "$RC" "0" "decimal 29.5 le 30.0: met (exit 0)"
has "$L" "goal.status=met" "decimal 29.5 le 30.0: marks met"

# --- a broken metric oracle flows through the shared bounds and parks at the
# iteration budget, rather than exiting past every bound (finding: metric oracle
# errors took the early not_yet path, skipping wall-clock/budget/stall/ceiling)
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo notanumber","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"2"}'
set +e; run_judge 2; RC=$?; set -e
eq "$RC" "0" "broken oracle at budget: exit 0 (parks, not an early not-yet exit)"
has "$L" "goal.parked_verdict=exhausted" "broken oracle at budget: parks exhausted through the bounds"

# --- same for a nonzero-exit oracle ------------------------------------------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"exit 2","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"2"}'
set +e; run_judge 2; RC=$?; set -e
eq "$RC" "0" "oracle nonzero-exit at budget: exit 0 (parks)"
has "$L" "goal.parked_verdict=exhausted" "oracle nonzero-exit at budget: parks exhausted through the bounds"

# --- tamper re-arm: a snapshot that disagrees re-arms and still judges --------
scenario '{"goal.statement":"cut it","goal.oracle.kind":"metric","goal.oracle.command":"echo 25","goal.oracle.compare":"le","goal.oracle.threshold":"30","goal.budget.max_iterations":"6"}' '{"stale":"snapshot"}'
set +e; run_judge 1; RC=$?; set -e
has "$L" "goal.snapshot=" "tamper: re-arms the snapshot"
has "$L" "goal.status=met" "tamper: still reaches the verdict after re-arming"

echo "---"
echo "goal-judge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
