#!/usr/bin/env bash
# Tests for goal-arm.sh: contract validation, the effective-contract overlay
# (bead metadata + flags), the tamper-evident snapshot, and that --dry-run
# neither writes nor slings while a real arm does both.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/goal-arm.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-goal-arm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; STATE="$TMP/state"
mkdir -p "$BIN" "$STATE"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q -- "$2" "$1" && ok "$3" || bad "$3 (log lacked '$2')"; }
hasnt() { grep -q -- "$2" "$1" && bad "$3 (log unexpectedly had '$2')" || ok "$3"; }

# stub gc: gc bd show/update against a fixture goal, and gc sling — all logged.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
S="$GOAL_TEST_STATE"
case "${1:-}" in
  bd)
    shift
    case "${1:-}" in
      show) case "${2:-}" in goal1) cat "$S/goal.json" ;; *) printf '{"error":"nf"}\n' ;; esac ;;
      update) shift; printf 'UPDATE %s\n' "$*" >> "$S/gc.log" ;;
    esac ;;
  sling) shift; printf 'SLING %s\n' "$*" >> "$S/gc.log" ;;
  *) : ;;
esac
STUB
chmod +x "$BIN/gc"
export GOAL_TEST_STATE="$STATE"

goal_meta() { printf '[{"id":"goal1","status":"open","metadata": %s}]\n' "$1" > "$STATE/goal.json"; : > "$STATE/gc.log"; }
run() { PATH="$BIN:$PATH" bash "$SUT" "$@"; }

FULL=(--statement "cut it" --oracle-kind metric --oracle-command "echo 25" --compare le --threshold 30 --max-iterations 6)

# missing positional -> usage error
set +e; goal_meta '{}'; run --dry-run >/dev/null 2>&1; rc=$?; set -e
eq "$rc" "2" "no goal id -> exit 2"

# nonexistent goal bead -> exit 2
set +e; goal_meta '{}'; run nope --dry-run "${FULL[@]}" >/dev/null 2>&1; rc=$?; set -e
eq "$rc" "2" "nonexistent goal bead -> exit 2"

# incomplete: no --max-iterations
set +e; goal_meta '{}'; run goal1 --dry-run --statement s --oracle-kind command --oracle-command "true" >/dev/null 2>&1; rc=$?; set -e
eq "$rc" "2" "missing max-iterations -> exit 2"

# metric missing threshold
set +e; goal_meta '{}'; run goal1 --dry-run --statement s --oracle-kind metric --oracle-command "echo 1" --compare le --max-iterations 3 >/dev/null 2>&1; rc=$?; set -e
eq "$rc" "2" "metric without threshold -> exit 2"

# metric with a punctuation-only / malformed threshold -> exit 2. A character
# class alone accepts '-', '+', '.', '1-2', '1.2.3', which the judge's awk
# would then coerce to a number.
for bad_t in - + . 1-2 1.2.3; do
  set +e; goal_meta '{}'; run goal1 --dry-run --statement s --oracle-kind metric --oracle-command "echo 1" --compare le --threshold "$bad_t" --max-iterations 3 >/dev/null 2>&1; rc=$?; set -e
  eq "$rc" "2" "malformed threshold '$bad_t' -> exit 2"
done

# a decimal threshold is accepted: the strict parser must not over-tighten
set +e; goal_meta '{}'; run goal1 --dry-run --statement s --oracle-kind metric --oracle-command "echo 1" --compare le --threshold 29.5 --max-iterations 3 >/dev/null 2>&1; rc=$?; set -e
eq "$rc" "0" "decimal threshold 29.5 -> exit 0 (accepted)"

# complete metric via flags, dry-run: valid, prints snapshot, does NOT sling/write
goal_meta '{}'
set +e; out=$(run goal1 --dry-run "${FULL[@]}" 2>&1); rc=$?; set -e
eq "$rc" "0" "complete contract dry-run -> exit 0"
grep -q 'effective snapshot' <<< "$out" && ok "dry-run prints the snapshot" || bad "dry-run prints the snapshot"
grep -q 'would sling' <<< "$out" && ok "dry-run prints the sling command" || bad "dry-run prints the sling command"
hasnt "$STATE/gc.log" "SLING" "dry-run does not sling"
hasnt "$STATE/gc.log" "UPDATE" "dry-run does not write"

# effective-contract overlay: bead has some fields, flags supply the rest
goal_meta '{"goal.statement":"preset","goal.budget.max_iterations":"4"}'
set +e; out=$(run goal1 --dry-run --oracle-kind metric --oracle-command "echo 1" --compare lt --threshold 5 2>&1); rc=$?; set -e
eq "$rc" "0" "overlay (bead + flags) validates in dry-run"

# real arm: writes the contract + snapshot and slings
goal_meta '{}'
set +e; run goal1 "${FULL[@]}" >/dev/null 2>&1; rc=$?; set -e
eq "$rc" "0" "real arm -> exit 0"
has "$STATE/gc.log" "goal.snapshot=" "real arm writes the snapshot"
has "$STATE/gc.log" "goal.status=armed" "real arm marks armed"
has "$STATE/gc.log" "goal.not_yet_reason=" "real arm seeds the baseline reason"
has "$STATE/gc.log" "SLING" "real arm slings the keeper loop"
has "$STATE/gc.log" "mol-goal-keeper" "real arm slings mol-goal-keeper"

# wall-clock stamps an absolute deadline
goal_meta '{}'
set +e; run goal1 "${FULL[@]}" --wall-clock 72h >/dev/null 2>&1; rc=$?; set -e
eq "$rc" "0" "arm with wall-clock -> exit 0"
has "$STATE/gc.log" "goal.wall_clock_deadline=" "wall-clock stamps a deadline"

echo "---"
echo "goal-arm: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
