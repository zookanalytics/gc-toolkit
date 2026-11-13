#!/usr/bin/env bash
# Hermetic test for refinery-gate.sh, the refinery patrol's run-tests step.
# Runs the real script and the real detached-job.sh against real git
# repositories, with a fake gctk whose `rig` runs each check's command and a
# fake gc whose `formula show` answers with the rig's check commands
# (refinery-test-lib.sh). Proves:
#   - the checks run in the refinery's tree for the bead, through gctk rig, in
#     the order setup, typecheck, lint, build, test, and the gate names every
#     failed check, not just the last, and a check cut short ahead of any
#     failure; the log's first line names the head the checks ran at, and a
#     start clears the failures tracked against the gate before it;
#   - the rig's value wins over the formula's default, an empty one turns its
#     check off, and run_tests=false skips the test command;
#   - a rig with no check commands starts no gate until checks are given with
#     --add, which run only for such a rig;
#   - a gate a previous session left running is stopped before the next starts;
#   - an unreadable read of the check commands, no GC_RIG, no gctk binary, or a
#     bead whose branch the tree does not hold starts nothing;
#   - wait reports the job's state with detached-job.sh's exit.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-gate-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'cleanup' EXIT
cleanup() {
  [ -n "${SUT:-}" ] && [ -n "${GATE:-}" ] && "$SUT/detached-job.sh" stop "$GATE" >/dev/null 2>&1
  rm -rf "$TMP"
}
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

fresh() {
  [ -n "${SUT:-}" ] && [ -n "${GATE:-}" ] && "$SUT/detached-job.sh" stop "$GATE" >/dev/null 2>&1
  rm -rf "${TMP:?}"/*
  rt_init refinery-gate.sh detached-job.sh
  GATE="$(git -C "$HOME_DIR" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-gate"
  branch_with polecat/a a.txt >/dev/null
  work a polecat/a
  prepared a polecat/a
}
start() { OUT=$("$SUT/refinery-gate.sh" start "$@" 2>&1); RC=$?; }
finish() {
  local n=0
  while :; do
    WAIT=$("$SUT/refinery-gate.sh" wait 2>&1); WRC=$?
    [ "$WRC" = 3 ] && [ "$n" -lt 20 ] || break
    n=$((n + 1))
  done
  LOG=$(cat "$GATE/log" 2>/dev/null)
}

echo "# the checks run in the refinery's tree, in order, and every failure is named"
fresh
printf 'lint 0123456789abcdef0123456789abcdef01234567\n' > "$GATE/tracked"
rt_vars setup_command='echo setup-ran > setup.out' lint_command='exit 1' build_command='pwd > build.out' test_command='exit 1'
start --bead a
eq "$RC" 0 "the gate starts"
finish
eq "$WRC" 1 "the wait exits 1 for a gate that finished with failures"
has "$WAIT" "state=done" "…and reports it done"
has "$WAIT" "rc=1" "…with the gate's exit"
has "$LOG" "GATE FAILED: lint:1 test:1" "every failed check is named"
eq "$(printf '%s\n' "$LOG" | head -n 1)" "GATE AT $(git -C "$HOME_DIR/worktrees/a" rev-parse HEAD)" "the log's first line names the head the checks ran at"
eq "$(cat "$GATE/tracked" 2>/dev/null)" "" "the start cleared the failures tracked against the gate before it"
eq "$(cat "$HOME_DIR/worktrees/a/build.out" 2>/dev/null)" "$HOME_DIR/worktrees/a" "the checks run in the tree for the bead"
eq "$(printf '%s\n' "$LOG" | grep '^== ' | tr '\n' ' ')" "== setup == lint == build == test " "they run in order, and an empty check is skipped"
has "$(logged gctk)" "rig test --scope full --command exit 1" "the test command runs as the full suite"

echo "# a check cut short is named ahead of any failure"
fresh
rt_vars lint_command='exit 1' test_command='exit 7'
start --bead a
finish
has "$LOG" "GATE CUT SHORT: test:7 (failed: lint:1)" "the cut-short check leads, with the failure beside it"

echo "# the rig's value wins, an empty one turns its check off, and run_tests=false skips test"
fresh
rt_vars lint_command='' run_tests=false test_command='exit 1' build_command='true'
jq '.vars |= map(if .name == "lint_command" then .default = "exit 1" else . end)' "$STUB_VARS" > "$STUB_VARS.n" && mv "$STUB_VARS.n" "$STUB_VARS"
start --bead a
has "$OUT" "test_command skipped (run_tests=false)" "run_tests=false skips the test command"
finish
eq "$WRC" 0 "the wait exits 0 for a gate that passed"
has "$LOG" "GATE PASSED" "the rig's empty lint wins over the default's"
hasnt "$LOG" "== lint" "…so no lint runs"

echo "# a rig with no check commands starts no gate until checks are given"
fresh
start --bead a
eq "$RC" 5 "no gate starts (exit 5)"
has "$OUT" "--add" "it asks for the CLAUDE.md gates with --add"
start --bead a --add lint 'echo linted' --add test 'true'
eq "$RC" 0 "the gate starts with the added checks"
finish
has "$LOG" "== lint" "an added check runs"
has "$LOG" "GATE PASSED" "…and passes"
fresh
rt_vars lint_command='true'
start --bead a --add test 'exit 1'
has "$OUT" "sets its own check commands, so the --add checks do not run" "a rig with checks of its own runs none it is given"
finish
has "$LOG" "GATE PASSED" "…so the added failing check never runs"

echo "# a gate a previous session left running is stopped before the next starts"
fresh
rt_vars test_command='sleep 60'
start --bead a
eq "$RC" 0 "the long gate starts"
OLD_PID=$(cat "$GATE/pid" 2>/dev/null)
rt_vars lint_command='true'
start --bead a
eq "$RC" 0 "the next gate starts"
kill -0 "$OLD_PID" 2>/dev/null && rt_bad "the earlier gate is stopped" || rt_ok "the earlier gate is stopped"
finish
has "$LOG" "== lint" "the new gate runs its own checks"
hasnt "$LOG" "== test" "…and none of the earlier gate's"

echo "# starts that cannot run start nothing"
fresh
rt_vars lint_command='true'
echo '{"ok":false}' > "$STUB_VARS"
start --bead a
eq "$RC" 1 "an unreadable read of the check commands starts nothing"
rt_vars lint_command='true'
GC_RIG="" start --bead a
eq "$RC" 1 "no GC_RIG starts nothing"
GCTK_BIN=none start --bead a
eq "$RC" 1 "no gctk binary starts nothing"
branch_with polecat/b b.txt >/dev/null
work b polecat/b
start --bead b
eq "$RC" 1 "a bead this iteration did not prepare starts nothing"
[ -e "$GATE/pid" ] && rt_bad "no job was started" || rt_ok "no job was started"
"$SUT/refinery-gate.sh" bogus >/dev/null 2>&1; eq "$?" 2 "an unknown verb is usage"

echo
echo "refinery-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
