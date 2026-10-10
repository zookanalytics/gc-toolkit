#!/usr/bin/env bash
# refinery-gate.test.sh — the run-tests step of formulas/mol-refinery-patrol.toml
# runs the rig's checks as one detached job and waits for it in bounded
# foreground calls. Executes the step's two marked blocks (refinery-gate-start
# and refinery-gate-wait), rendered the way the agent substitutes the formula's
# command vars, against a real git repo with a prep worktree, the real
# detached-job.sh, and a stub gc. Proves:
#   - the gate runs in the prep worktree and reports every failed check by
#     name and exit code, not just the last one;
#   - an empty check is skipped, and run_tests=false skips the test command;
#   - a gate a previous session left running is stopped before the new one
#     starts;
#   - with no detached-job.sh reachable, nothing runs and the cycle drains.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-gate-test.XXXXXX")"
cleanup() {
  [ -f "$TMP/repo/.git/gc-refinery-gate/pid" ] && "$HERE/detached-job.sh" stop "$TMP/repo/.git/gc-refinery-gate" >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT
# Host signing of commits must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

command -v git >/dev/null 2>&1 || { echo "git required" >&2; exit 1; }
[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

fence() { awk -v m="$1" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$TOML"; }
fence refinery-gate-start > "$TMP/start.raw"
fence refinery-gate-wait  > "$TMP/wait.raw"
for b in start wait; do
  [ -s "$TMP/$b.raw" ] && ok "refinery-gate-$b extracted" || bad "refinery-gate-$b extracted"
  case "$(cat "$TMP/$b.raw")" in
    *\\*) bad "refinery-gate-$b is backslash-free (TOML would eat it)" ;;
    *)    ok  "refinery-gate-$b is backslash-free (TOML would eat it)" ;;
  esac
done

# render <raw> <out> <setup> <typecheck> <lint> <build> <test> <run_tests>:
# substitute the formula's vars as the agent does, verbatim.
render() {
  local s
  s=$(cat "$1")
  shopt -u patsub_replacement 2>/dev/null || true
  s=${s//'{{setup_command}}'/$3}
  s=${s//'{{typecheck_command}}'/$4}
  s=${s//'{{lint_command}}'/$5}
  s=${s//'{{build_command}}'/$6}
  s=${s//'{{test_command}}'/$7}
  s=${s//'{{run_tests}}'/$8}
  printf '%s\n' "$s" > "$2"
}
render "$TMP/wait.raw" "$TMP/wait.sh" "" "" "" "" "" true
bash -n "$TMP/wait.sh" && ok "the wait block is valid bash" || bad "the wait block is valid bash"
grep -q '{{' "$TMP/wait.sh" && bad "the wait block needs no var" "it carries a placeholder" || ok "the wait block needs no var"

# The rig: a git repo whose common dir holds the prep worktree.
REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q --detach "$REPO/.git/gc-refinery-prep" HEAD
PREP_WT="$REPO/.git/gc-refinery-prep"
GATE="$REPO/.git/gc-refinery-gate"

# The pack, where the blocks find detached-job.sh: $GC_CITY_PATH/rigs/gc-toolkit.
CITY="$TMP/city"
mkdir -p "$CITY/rigs/gc-toolkit/assets/scripts"
cp "$HERE/detached-job.sh" "$CITY/rigs/gc-toolkit/assets/scripts/"
EMPTY_CITY="$TMP/empty-city"
mkdir -p "$EMPTY_CITY"

# A stub gc: the blocks call it only to drain.
BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_GC_LOG"
exit 0
STUB
chmod +x "$BIN/gc"
export STUB_GC_LOG="$TMP/gc.log"
: > "$STUB_GC_LOG"
export DETACHED_JOB_POLL=1 DETACHED_JOB_STOP_GRACE=2

# run_block <script> <city>: run a rendered block as the agent would, from a
# directory outside any repo, so only GC_CITY_PATH can supply the script.
run_block() {
  ( cd "$TMP" && env PATH="$BIN:$PATH" GC_RIG=testrig GC_RIG_ROOT="$REPO" GC_CITY_PATH="$2" bash "$1" )
}

echo "── a passing gate ──"
render "$TMP/start.raw" "$TMP/s1.sh" 'pwd > "$PWD_OUT"' '' 'true' '' 'true' true
bash -n "$TMP/s1.sh" && ok "the rendered start block is valid bash" || bad "the rendered start block is valid bash"
OUT=$(PWD_OUT="$TMP/gate-pwd" run_block "$TMP/s1.sh" "$CITY"); RC=$?
eq "$RC" 0 "the start block exits 0"
eq "$(field "$OUT" state)" started "it starts the gate"
OUT=$(run_block "$TMP/wait.sh" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" state)/$(field "$OUT" rc)" 0/done/0 "the wait reports done, rc=0"
has "$(cat "$GATE/log")" "GATE PASSED" "the log ends GATE PASSED"
eq "$(cd "$(cat "$TMP/gate-pwd")" && pwd -P)" "$(cd "$PREP_WT" && pwd -P)" "the checks run in the prep worktree"

echo "── a failing gate names every failed check ──"
render "$TMP/start.raw" "$TMP/s2.sh" '' 'exit 3' 'cd /' '' 'echo test-output; pwd; false' true
run_block "$TMP/s2.sh" "$CITY" >/dev/null
OUT=$(run_block "$TMP/wait.sh" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" state)/$(field "$OUT" rc)" 1/done/1 "the wait reports done, rc=1"
LOG=$(cat "$GATE/log")
has "$LOG" "GATE FAILED: typecheck:3 test:1" "the log names each failed check and its exit code"
has "$LOG" "test-output" "the failed check's output is in the log"
has "$LOG" "== test" "each check's output sits under its own header"
case "$LOG" in *"test-output"$'\n'"/"$'\n'*) bad "a cd in one check does not move the next" "the test check ran in /" ;; *) ok "a cd in one check does not move the next" ;; esac
case "$LOG" in *lint:*) bad "a passing check is not named" "lint appears in: $LOG" ;; *) ok "a passing check is not named" ;; esac

echo "── run_tests=false skips the test command ──"
render "$TMP/start.raw" "$TMP/s3.sh" '' '' 'true' '' 'false' false
run_block "$TMP/s3.sh" "$CITY" >/dev/null
OUT=$(run_block "$TMP/wait.sh" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" rc)" 0/0 "the failing test command never ran"

echo "── a gate a previous session left running is stopped first ──"
render "$TMP/start.raw" "$TMP/s4.sh" '' '' 'sleep 45' '' '' true
run_block "$TMP/s4.sh" "$CITY" >/dev/null
OLD=$(cat "$GATE/pid")
kill -0 "$OLD" 2>/dev/null && ok "the old gate is running" || bad "the old gate is running"
OUT=$(PWD_OUT="$TMP/gate-pwd-2" run_block "$TMP/s1.sh" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" state)" 0/started "the new gate starts over a running one"
kill -0 -- "-$OLD" 2>/dev/null && bad "the old gate's process group is gone" "it survived" || ok "the old gate's process group is gone"
OUT=$(run_block "$TMP/wait.sh" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" rc)" 0/0 "the new gate's result is the one reported"

echo "── no detached-job.sh: nothing runs, and the cycle drains ──"
: > "$STUB_GC_LOG"
render "$TMP/start.raw" "$TMP/s5.sh" 'touch "$RAN"' '' 'true' '' '' true
OUT=$(RAN="$TMP/ran" run_block "$TMP/s5.sh" "$EMPTY_CITY" 2>&1); RC=$?
eq "$RC" 1 "the start block exits 1"
has "$OUT" "detached-job.sh not found" "it says why"
has "$(cat "$STUB_GC_LOG")" "runtime drain-ack" "it drains"
sleep 1
[ -e "$TMP/ran" ] && bad "no check ran" "the setup command ran" || ok "no check ran"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
