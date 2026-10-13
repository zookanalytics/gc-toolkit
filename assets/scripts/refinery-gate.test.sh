#!/usr/bin/env bash
# refinery-gate.test.sh — the run-tests step of formulas/mol-refinery-patrol.toml
# runs the rig's checks as one detached job and waits for it in bounded
# foreground calls. Executes the step's two marked blocks (refinery-gate-start
# and refinery-gate-wait) as written, against a real git repo with a prep
# worktree, the real detached-job.sh, and a stub gc whose `formula show`
# answers with the rig's check commands from a fixture. Proves:
#   - the gate runs in the prep worktree and reports every failed check by
#     name and exit code, not just the last one;
#   - each command runs as configured, so a trailing comment or a heredoc in
#     it works, and the rig's own value wins over the formula default;
#   - a wait that finds the gate still running notes it on the refinery's
#     patrol wisp, and one that finds it finished does not;
#   - an empty check is skipped, and run_tests=false skips the test command;
#   - a gate a previous session left running is stopped before the new one
#     starts, and its checks do not carry into the new one;
#   - a rig with no check commands starts no gate until a quality gate from
#     its CLAUDE.md is added, and an added one runs only for such a rig;
#   - a wait that cannot find its launcher exits 1, leaves the gate running,
#     and does not drain;
#   - with no detached-job.sh reachable, no prep worktree, or an unreadable
#     read of the check commands, nothing runs and the cycle drains.
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

# The blocks run as written: the agent fills in nothing.
for b in start wait; do
  bash -n "$TMP/$b.raw" && ok "the $b block is valid bash" || bad "the $b block is valid bash"
  grep -q '{{' "$TMP/$b.raw" && bad "the $b block needs no var" "it carries a placeholder" || ok "the $b block needs no var"
done

# checks <setup> <typecheck> <lint> <build> <test> <run_tests>: the formula
# defaults `gc formula show` reports, for a rig that sets none of its own.
# rig_lint <value>: the rig's own lint_command, added to the last fixture.
checks() {
  jq -n --arg setup "$1" --arg typecheck "$2" --arg lint "$3" --arg build "$4" --arg test "$5" --arg rt "$6" \
    '{schema_version: "1", ok: true, vars: [
       {name: "run_tests", default: $rt},
       {name: "setup_command", default: $setup},
       {name: "typecheck_command", default: $typecheck},
       {name: "lint_command", default: $lint},
       {name: "build_command", default: $build},
       {name: "test_command", default: $test}]}' > "$STUB_SHOW"
}
rig_lint() {
  jq --arg v "$1" '.vars |= map(if .name == "lint_command" then . + {rig_default: $v} else . end)' "$STUB_SHOW" > "$STUB_SHOW.next" \
    && mv "$STUB_SHOW.next" "$STUB_SHOW"
}

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

# A stub gc: the blocks call it to read the check commands (STUB_SHOW, the
# JSON `formula show` prints), to drain, to list the refinery's patrol wisps
# (STUB_WISPS, a JSON file), and to note a running gate on one.
BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_GC_LOG"
case "$1 $2" in
  "formula show") cat "$STUB_SHOW" ;;
  "bd list") [ -z "${STUB_WISPS:-}" ] || cat "$STUB_WISPS" ;;
esac
exit 0
STUB
chmod +x "$BIN/gc"
export STUB_GC_LOG="$TMP/gc.log" STUB_SHOW="$TMP/show.json"
: > "$STUB_GC_LOG"
export DETACHED_JOB_POLL=1 DETACHED_JOB_STOP_GRACE=2

# run_block <script> <city> [<rig root>]: run a block as the agent would, from
# a directory outside any repo, so only GC_CITY_PATH can supply the script.
run_block() {
  ( cd "$TMP" && env PATH="$BIN:$PATH" GC_RIG=testrig GC_RIG_ROOT="${3:-$REPO}" GC_CITY_PATH="$2" GC_AGENT=testrig/gc-toolkit.refinery bash "$1" )
}

echo "── a passing gate ──"
checks 'pwd > "$PWD_OUT"' '' 'true' '' 'true' true
OUT=$(PWD_OUT="$TMP/gate-pwd" run_block "$TMP/start.raw" "$CITY"); RC=$?
eq "$RC" 0 "the start block exits 0"
eq "$(field "$OUT" state)" started "it starts the gate"
has "$OUT" 'run-tests: setup_command = pwd > "$PWD_OUT"' "it prints each check it hands the gate"
has "$(cat "$STUB_GC_LOG")" "formula show mol-refinery-patrol --rig testrig --json" "it reads the rig's check commands"
OUT=$(run_block "$TMP/wait.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" state)/$(field "$OUT" rc)" 0/done/0 "the wait reports done, rc=0"
has "$(cat "$GATE/log")" "GATE PASSED" "the log ends GATE PASSED"
eq "$(cd "$(cat "$TMP/gate-pwd")" && pwd -P)" "$(cd "$PREP_WT" && pwd -P)" "the checks run in the prep worktree"

echo "── a wait that finds the gate still running notes it on the patrol wisp ──"
: > "$STUB_GC_LOG"
OUT=$(run_block "$TMP/wait.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" state)" 0/done "a wait on a finished gate reports done"
case "$(cat "$STUB_GC_LOG")" in *"bd update"*) bad "a finished gate writes no note" "it wrote one" ;; *) ok "a finished gate writes no note" ;; esac
# A launcher that reports the gate still running, as a wait does after --max.
RUNNING_CITY="$TMP/running-city"
mkdir -p "$RUNNING_CITY/rigs/gc-toolkit/assets/scripts"
cat > "$RUNNING_CITY/rigs/gc-toolkit/assets/scripts/detached-job.sh" <<'STUB'
#!/usr/bin/env bash
printf 'state=running\npid=4242\nelapsed=600\nwaited=540\ndir=%s\n' "$2"
exit 3
STUB
chmod +x "$RUNNING_CITY/rigs/gc-toolkit/assets/scripts/detached-job.sh"
printf '[{"id":"tk-other","title":"mol-polecat-work"},{"id":"tk-wisp","title":"mol-refinery-patrol"}]\n' > "$TMP/wisps.json"
: > "$STUB_GC_LOG"
OUT=$(STUB_WISPS="$TMP/wisps.json" run_block "$TMP/wait.raw" "$RUNNING_CITY"); RC=$?
eq "$RC/$(field "$OUT" state)" 3/running "the wait still reports running, exit 3"
has "$(cat "$STUB_GC_LOG")" "bd list --assignee=testrig/gc-toolkit.refinery --status=open,in_progress --type=molecule --include-infra" \
  "it lists this refinery's patrol wisps as check-refinery-patrol-live does"
has "$(cat "$STUB_GC_LOG")" "bd update tk-wisp --append-notes run-tests: the gate has run 600s and is still running" \
  "it notes the running gate on the patrol wisp"
has "$OUT" "noted the running gate on patrol wisp tk-wisp" "it says so"
: > "$STUB_GC_LOG"
OUT=$(run_block "$TMP/wait.raw" "$RUNNING_CITY"); RC=$?
eq "$RC/$(field "$OUT" state)" 3/running "with no patrol wisp found, the wait still reports running"
has "$OUT" "could not note the running gate" "it says the note did not land"

echo "── a failing gate names every failed check ──"
checks '' 'exit 3' 'cd /' '' 'echo test-output; pwd; false' true
run_block "$TMP/start.raw" "$CITY" >/dev/null
OUT=$(run_block "$TMP/wait.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" state)/$(field "$OUT" rc)" 1/done/1 "the wait reports done, rc=1"
LOG=$(cat "$GATE/log")
has "$LOG" "GATE FAILED: typecheck_command:3 test_command:1" "the log names each failed check and its exit code"
has "$LOG" "test-output" "the failed check's output is in the log"
has "$LOG" "== test_command" "each check's output sits under its own header"
case "$LOG" in *"test-output"$'\n'"/"$'\n'*) bad "a cd in one check does not move the next" "the test check ran in /" ;; *) ok "a cd in one check does not move the next" ;; esac
case "$LOG" in *lint_command:*) bad "a passing check is not named" "lint appears in: $LOG" ;; *) ok "a passing check is not named" ;; esac

echo "── each command runs as configured: a trailing comment, a heredoc ──"
checks $'cat > "$HD_OUT" <<\'EOF\'\nfrom a heredoc\nEOF' '' 'true  # a trailing comment' '' 'test -s "$HD_OUT"' true
HD_OUT="$TMP/heredoc-out" run_block "$TMP/start.raw" "$CITY" >/dev/null
OUT=$(run_block "$TMP/wait.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" state)/$(field "$OUT" rc)" 0/done/0 "a command with a trailing comment and one that is a heredoc both pass"
eq "$(cat "$TMP/heredoc-out" 2>/dev/null)" "from a heredoc" "the heredoc command wrote its body"
has "$(cat "$GATE/log")" "GATE PASSED" "the log ends GATE PASSED"

echo "── the rig's own check command wins over the formula default ──"
checks '' '' 'echo default-lint >> "$RAN"' '' '' true
rig_lint 'echo rig-lint >> "$RAN"'
: > "$TMP/ran"
RAN="$TMP/ran" run_block "$TMP/start.raw" "$CITY" >/dev/null
OUT=$(run_block "$TMP/wait.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" rc)" 0/0 "the gate passes"
eq "$(cat "$TMP/ran")" "rig-lint" "the gate runs the rig's lint_command, not the default"

echo "── run_tests=false skips the test command ──"
checks '' '' 'true' '' 'false' false
run_block "$TMP/start.raw" "$CITY" >/dev/null
OUT=$(run_block "$TMP/wait.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" rc)" 0/0 "the failing test command never ran"

echo "── a gate a previous session left running is stopped first ──"
checks '' '' '' 'sleep 45' '' true
run_block "$TMP/start.raw" "$CITY" >/dev/null
OLD=$(cat "$GATE/pid")
kill -0 "$OLD" 2>/dev/null && ok "the old gate is running" || bad "the old gate is running"
checks 'pwd > "$PWD_OUT"' '' 'true' '' 'true' true
OUT=$(PWD_OUT="$TMP/gate-pwd-2" run_block "$TMP/start.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" state)" 0/started "the new gate starts over a running one"
kill -0 -- "-$OLD" 2>/dev/null && bad "the old gate's process group is gone" "it survived" || ok "the old gate's process group is gone"
eq "$(ls "$GATE/checks" | tr '\n' ' ')" "01-setup_command 02-lint_command 03-test_command " "the new gate's checks replace the old gate's"
OUT=$(run_block "$TMP/wait.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" rc)" 0/0 "the new gate's result is the one reported"
case "$(cat "$GATE/log")" in *"== build_command"*) bad "the old gate's check does not run again" "build_command ran" ;; *) ok "the old gate's check does not run again" ;; esac

echo "── a wait that cannot find its launcher leaves the gate running ──"
checks '' '' 'sleep 45' '' '' true
run_block "$TMP/start.raw" "$CITY" >/dev/null
: > "$STUB_GC_LOG"
OUT=$(run_block "$TMP/wait.raw" "$EMPTY_CITY" 2>&1); RC=$?
eq "$RC" 1 "with no detached-job.sh reachable, the wait exits 1"
has "$OUT" "detached-job.sh not found" "it says what it could not find"
has "$OUT" "keeps running" "it says the gate keeps running"
kill -0 "$(cat "$GATE/pid")" 2>/dev/null && ok "the gate is still running" || bad "the gate is still running" "it is gone"
case "$(cat "$STUB_GC_LOG")" in
  *"runtime drain-ack"*) bad "the wait does not drain the session while the gate runs" "drain-ack was called" ;;
  *) ok "the wait does not drain the session while the gate runs" ;;
esac
"$HERE/detached-job.sh" stop "$GATE" >/dev/null

echo "── a rig with no check commands runs the quality gates its CLAUDE.md documents ──"
checks '' '' '' '' '' true
: > "$STUB_GC_LOG"
PID_BEFORE=$(cat "$GATE/pid" 2>/dev/null)
OUT=$(run_block "$TMP/start.raw" "$CITY" 2>&1); RC=$?
eq "$RC" 1 "with no check to run, the start block exits 1"
has "$OUT" "run-tests: rig testrig sets no check commands" "it says the rig sets none"
has "$OUT" "no gate started" "it says it started no gate"
eq "$(cat "$GATE/pid" 2>/dev/null)" "$PID_BEFORE" "no gate started"
case "$(cat "$STUB_GC_LOG")" in
  *"runtime drain-ack"*) bad "it does not drain: adding the CLAUDE.md gates comes next" "drain-ack was called" ;;
  *) ok "it does not drain: adding the CLAUDE.md gates comes next" ;;
esac
# The agent adds a quality gate from the rig's CLAUDE.md where the block marks.
cat > "$TMP/claude-md.line" <<'LINE'
  add_check claude-md-check 'echo from-claude-md >> "$RAN"'
LINE
awk -v f="$TMP/claude-md.line" '{print} /^  #   add_check <name> / {while ((getline l < f) > 0) print l}' "$TMP/start.raw" > "$TMP/start-claude.sh"
eq "$(grep -c 'add_check claude-md-check' "$TMP/start-claude.sh")" 1 "the CLAUDE.md gate goes where the block marks"
: > "$TMP/ran"
OUT=$(RAN="$TMP/ran" run_block "$TMP/start-claude.sh" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" state)" 0/started "with a CLAUDE.md gate added, the gate starts"
OUT=$(run_block "$TMP/wait.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" rc)" 0/0 "the added check passes"
eq "$(cat "$TMP/ran")" "from-claude-md" "the added check ran"
has "$(cat "$GATE/log")" "== claude-md-check" "it runs under the name it was given"
# A rig that sets a check command runs that, not the CLAUDE.md gate.
checks '' '' 'echo configured-lint >> "$RAN"' '' '' true
: > "$TMP/ran"
RAN="$TMP/ran" run_block "$TMP/start-claude.sh" "$CITY" >/dev/null
OUT=$(run_block "$TMP/wait.raw" "$CITY"); RC=$?
eq "$RC/$(field "$OUT" rc)" 0/0 "the configured gate passes"
eq "$(cat "$TMP/ran")" "configured-lint" "a CLAUDE.md gate runs only for a rig that sets no check commands"

echo "── an unreadable read of the check commands: nothing runs, and the cycle drains ──"
printf 'not json' > "$STUB_SHOW"
: > "$STUB_GC_LOG"
PID_BEFORE=$(cat "$GATE/pid" 2>/dev/null)
OUT=$(run_block "$TMP/start.raw" "$CITY" 2>&1); RC=$?
eq "$RC" 1 "the start block exits 1"
has "$OUT" "cannot read the check commands of rig 'testrig'" "it says why"
has "$(cat "$STUB_GC_LOG")" "runtime drain-ack" "it drains"
eq "$(cat "$GATE/pid" 2>/dev/null)" "$PID_BEFORE" "no gate started"

echo "── no prep worktree: nothing runs, and the cycle drains ──"
BARE="$TMP/bare-rig"
git init -q "$BARE"
git -C "$BARE" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
checks 'touch "$RAN"' '' 'true' '' '' true
: > "$STUB_GC_LOG"
OUT=$(RAN="$TMP/ran-bare" run_block "$TMP/start.raw" "$CITY" "$BARE" 2>&1); RC=$?
eq "$RC" 1 "the start block exits 1"
has "$OUT" "cannot find the prep worktree" "it says why"
has "$(cat "$STUB_GC_LOG")" "runtime drain-ack" "it drains"
[ -e "$BARE/.git/gc-refinery-gate/pid" ] && bad "no gate started" "a job record exists" || ok "no gate started"

echo "── no detached-job.sh: nothing runs, and the cycle drains ──"
: > "$STUB_GC_LOG"
checks 'touch "$RAN"' '' 'true' '' '' true
OUT=$(RAN="$TMP/ran-nojob" run_block "$TMP/start.raw" "$EMPTY_CITY" 2>&1); RC=$?
eq "$RC" 1 "the start block exits 1"
has "$OUT" "detached-job.sh not found" "it says why"
has "$(cat "$STUB_GC_LOG")" "runtime drain-ack" "it drains"
sleep 1
[ -e "$TMP/ran-nojob" ] && bad "no check ran" "the setup command ran" || ok "no check ran"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
