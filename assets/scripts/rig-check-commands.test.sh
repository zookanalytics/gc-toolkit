#!/usr/bin/env bash
# Hermetic test for the rig-check-commands block in
# formulas/mol-refinery-patrol.toml (run-tests step), and for the gate script
# that runs the checks it writes.
#
# The refinery patrol is a --root-only wisp, so no step text is rendered, and
# `gc formula show` offers each check command two values: the formula default
# and the rig's [rigs.formula_vars] entry. The block is the one read of those
# values, so every refinery session runs the same checks. It writes each check
# into the gate's check list, and the step's detached gate runs that list. It
# holds:
#   (R) RIG WINS. A var the rig sets runs instead of the formula default, and an
#       empty rig value turns that check off.
#   (D) DEFAULT. A var the rig does not set runs the formula default.
#   (O) ORDER AND PLACE. setup, typecheck, lint and build run in that order,
#       then test when run_tests is "true", each in the prep worktree (cwd). The
#       gate names a failing check with its exit code and the checks after it
#       still run; a check that exits or changes directory touches nothing
#       outside itself.
#   (F) FAIL-CLOSED. An unreadable `gc formula show` answer, or no GC_RIG, runs
#       no check and drains. An empty read would look like a rig with no checks.
#       A check the block cannot write drains too, so the gate never runs a
#       list that is missing one.
#   (Z) ZSH. Agents paste the block into zsh, so the core cases run under zsh
#       too when it is installed.
#   (P) PACK DEFAULTS. The formula serves every rig, so each check command's
#       default is empty: a default command would run in rigs whose repo does
#       not carry it. Every var the block reads is declared, and no text in the
#       formula carries a placeholder for one, which a session would fill in by
#       hand.
#
# It runs the real snippet extracted verbatim from the formula against a stub
# `gc` that answers `formula show` from a fixture shaped like gc's --json
# output, then runs the gate script, also extracted verbatim, over the checks
# the snippet wrote, the way the detached job runs it. No live city, Dolt, or
# network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rig-check-commands-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # ok/bad/eq/has/hasnt and tomllib_python
PASS=0; FAIL=0

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

# --- Extract the real snippet. -------------------------------------------------
awk '
  $0 ~ /# >>> rig-check-commands$/ {f=1; next}
  $0 ~ /# <<< rig-check-commands$/ {f=0}
  f' "$TOML" > "$TMP/block.sh"
# The gate script is the quoted heredoc that refinery-gate-start writes.
awk '
  $0 ~ /# >>> refinery-gate-start$/ {s=1; next}
  $0 ~ /# <<< refinery-gate-start$/ {s=0}
  s && f && $0 == "GATE" {f=0; next}
  s && f {print; next}
  s && $0 ~ /<<.GATE.$/ {f=1}' "$TOML" > "$TMP/gate.sh"

echo "── shape ──"
[ -s "$TMP/block.sh" ] \
  && ok "snippet extracted between rig-check-commands markers" \
  || bad "snippet extraction EMPTY — markers missing from $TOML"
# The block lives inside a TOML """ string, which would eat a line-ending
# backslash before any agent saw it. The test runs the raw file text, so a
# backslash here means what runs differs from what this test pins.
case "$(cat "$TMP/block.sh")" in
  *\\*) bad "block is backslash-free (TOML would eat it)" ;;
  *)    ok  "block is backslash-free (TOML would eat it)" ;;
esac
printf 'x\\y\n' > "$TMP/backslash-control"
case "$(cat "$TMP/backslash-control")" in
  *\\*) ok  "backslash guard detects a backslash (not vacuous)" ;;
  *)    bad "backslash guard is vacuous — a literal backslash went undetected" ;;
esac
bash -n "$TMP/block.sh" && ok "block is valid bash" || bad "block is valid bash"
[ -s "$TMP/gate.sh" ] \
  && ok "gate script extracted from refinery-gate-start" \
  || bad "gate script extraction EMPTY — its heredoc is missing from $TOML"
bash -n "$TMP/gate.sh" && ok "gate script is valid bash" || bad "gate script is valid bash"

# --- Stub gc. --------------------------------------------------------------------
# `formula show` prints $STUB_SHOW and exits $STUB_SHOW_RC; every call is logged.
mkdir -p "$TMP/bin" "$TMP/prep" "$TMP/gate"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "formula show")      [ -f "$STUB_SHOW" ] && cat "$STUB_SHOW"; exit "${STUB_SHOW_RC:-0}" ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$STUB_LOG" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
PREP="$(cd "$TMP/prep" && pwd -P)"
GATE_DIR="$TMP/gate"
export STUB_LOG="$TMP/gc.log" STUB_SHOW="$TMP/show.json" RAN="$TMP/ran"

# --- Fixture: the vars array of `gc formula show --json`. ------------------------
# var NAME DEFAULT          a var the rig does not set
# rigvar NAME DEFAULT RIG   a var whose rig_default is RIG (possibly empty)
vars_reset() { printf '[]' > "$TMP/vars.json"; }
var() {
  jq --arg n "$1" --arg d "$2" '. + [{name: $n, description: "d", default: $d}]' \
    "$TMP/vars.json" > "$TMP/vars.next" && mv "$TMP/vars.next" "$TMP/vars.json"
}
rigvar() {
  jq --arg n "$1" --arg d "$2" --arg r "$3" '. + [{name: $n, description: "d", default: $d, rig_default: $r}]' \
    "$TMP/vars.json" > "$TMP/vars.next" && mv "$TMP/vars.next" "$TMP/vars.json"
}
show_ok() {
  jq '{schema_version: "1", ok: true, city_path: "/city", name: "mol-refinery-patrol", search_paths: [], vars: .}' \
    "$TMP/vars.json" > "$STUB_SHOW"
}

# run_block [SHELL ARGV...] — the block under bash unless a shell is named,
# over an empty check list as the step leaves it, then the gate script over the
# checks the block wrote, under bash as the detached job runs it. For one call,
# RIG overrides GC_RIG, STUB_SHOW_RC sets the stub's exit code, and CHECKS_RO=1
# makes the check list read-only. Sets OUT (the block's stdout+stderr), RC,
# GATE_OUT and GATE_RC (empty when the gate did not run), the check list
# CHECKLIST, the check-run log RANLOG and the gc call log GCLOG.
run_block() {
  [ "$#" -gt 0 ] || set -- bash
  : > "$STUB_LOG"; : > "$RAN"
  chmod 755 "$GATE_DIR/checks" 2>/dev/null || true
  rm -rf "${GATE_DIR:?}/checks"; mkdir -p "$GATE_DIR/checks"
  [ -z "${CHECKS_RO:-}" ] || chmod 555 "$GATE_DIR/checks"
  set +e
  OUT=$(cd "$TMP" && PATH="$TMP/bin:$PATH" GC_RIG="${RIG-fixture-rig}" STUB_SHOW_RC="${STUB_SHOW_RC:-0}" GATE="$GATE_DIR" "$@" "$TMP/block.sh" 2>&1)
  RC=$?
  CHECKLIST=$(ls "$GATE_DIR/checks" | tr '\n' ' ' | sed 's/ $//')
  GATE_OUT=""; GATE_RC=""
  if [ "$RC" -eq 0 ] && [ -n "$CHECKLIST" ]; then
    GATE_OUT=$(cd "$TMP" && bash "$TMP/gate.sh" "$PREP" "$GATE_DIR/checks" </dev/null 2>&1)
    GATE_RC=$?
  fi
  set -e
  RANLOG=$(cat "$RAN"); GCLOG=$(cat "$STUB_LOG")
}

# The five checks, each recording its name in run order.
all_checks_default() {
  var run_tests "true"
  var setup_command     'echo setup >> "$RAN"'
  var typecheck_command 'echo typecheck >> "$RAN"'
  var lint_command      'echo lint >> "$RAN"'
  var build_command     'echo build >> "$RAN"'
  var test_command      'echo test >> "$RAN"'
}
lines() { printf '%s' "$1" | tr '\n' ' ' | sed 's/ $//'; }

echo "── (R) the rig's value wins ──"
vars_reset
var run_tests "true"
rigvar lint_command 'echo DEFAULT-LINT >> "$RAN"' 'echo RIG-LINT >> "$RAN"'
show_ok; run_block
eq "$RC" 0 "(R1) block exits 0 when it wrote its checks"
eq "$(lines "$RANLOG")" "RIG-LINT" "(R1) the rig's lint_command runs, the formula default does not"
has "$OUT" 'run-tests: lint_command = echo RIG-LINT' "(R1) the block prints the command it hands the gate"
has "$GCLOG" 'formula show mol-refinery-patrol --rig fixture-rig --json' "(R2) the read is scoped to GC_RIG and names this formula"

vars_reset
var run_tests "true"
rigvar lint_command 'echo DEFAULT-LINT >> "$RAN"' ''
var build_command 'echo build >> "$RAN"'
show_ok; run_block
eq "$(lines "$RANLOG")" "build" "(R3) an empty rig value turns the check off over a non-empty default"
has "$OUT" 'run-tests: lint_command not set' "(R3) the turned-off check is reported as not set"

echo "── (D) a var the rig does not set runs the formula default ──"
vars_reset
var run_tests "true"
var typecheck_command 'echo DEFAULT-TYPECHECK >> "$RAN"'
rigvar lint_command '' 'echo RIG-LINT >> "$RAN"'
show_ok; run_block
eq "$(lines "$RANLOG")" "DEFAULT-TYPECHECK RIG-LINT" "(D1) default typecheck and rig lint both run, in order"

echo "── (O) order, place, failures ──"
vars_reset; all_checks_default; show_ok; run_block
eq "$(lines "$RANLOG")" "setup typecheck lint build test" "(O1) checks run setup, typecheck, lint, build, then test"
eq "$CHECKLIST" "01-setup_command 02-typecheck_command 03-lint_command 04-build_command 05-test_command" "(O1) the check list holds one file per check, named for its place and its var"
eq "$GATE_RC" 0 "(O1) the gate exits 0 when every check passed"
has "$GATE_OUT" 'GATE PASSED' "(O1) the gate reports that every check passed"

vars_reset
var run_tests "true"
var setup_command 'cd / && echo setup >> "$RAN"'
var lint_command 'pwd -P > "$RAN.where"'
show_ok; run_block
eq "$(cat "$RAN.where" 2>/dev/null)" "$PREP" "(O2) a check runs in the prep worktree, even after an earlier check's cd"

vars_reset
var run_tests "true"
var typecheck_command 'exit 3'
var lint_command 'echo lint >> "$RAN"'
var build_command 'echo build >> "$RAN"; false'
var test_command 'echo test >> "$RAN"'
show_ok; run_block
eq "$GATE_RC" 1 "(O3) a gate with a failing check exits 1"
eq "$(lines "$RANLOG")" "lint build test" "(O3) the checks after a failing one still run"
has "$GATE_OUT" 'GATE FAILED: typecheck_command:3 build_command:1' "(O3) the gate names every failed check with its exit code, a check whose last command fails included"
hasnt "$GATE_OUT" 'GATE PASSED' "(O3) a run with a failure never reports all passed"

# A rig value is a shell command line, not one program: the eval must keep its
# lists, $? and tests, so a value that runs two linters and fails when either
# does is judged as written.
vars_reset
var run_tests "true"
var lint_command 'false; FIRST_RC=$?; echo second >> "$RAN" && [ "$FIRST_RC" -eq 0 ]'
show_ok; run_block
eq "$(lines "$RANLOG")" "second" "(O4) the second command of a list runs after the first fails"
has "$GATE_OUT" 'GATE FAILED: lint_command:1' "(O4) the list fails when its first command failed"
vars_reset
var run_tests "true"
var lint_command 'true; FIRST_RC=$?; false && [ "$FIRST_RC" -eq 0 ]'
show_ok; run_block
has "$GATE_OUT" 'GATE FAILED: lint_command:1' "(O4) the list fails when its second command failed"
vars_reset
var run_tests "true"
var lint_command 'true; FIRST_RC=$?; true && [ "$FIRST_RC" -eq 0 ]'
show_ok; run_block
has "$GATE_OUT" 'GATE PASSED' "(O4) the list passes when both commands pass"

vars_reset
var run_tests "false"
var lint_command 'echo lint >> "$RAN"'
var test_command 'echo test >> "$RAN"'
show_ok; run_block
eq "$(lines "$RANLOG")" "lint" "(O5) run_tests=false skips test_command"
has "$OUT" 'run-tests: test_command skipped (run_tests=false)' "(O5) the skip is reported"
vars_reset
rigvar run_tests "true" "false"
var test_command 'echo test >> "$RAN"'
show_ok; run_block
eq "$RANLOG" "" "(O6) a rig's run_tests=false wins over the default true"

vars_reset
var run_tests "true"
var setup_command 'exit 0'
var lint_command 'echo lint >> "$RAN"'
show_ok; run_block
eq "$(lines "$RANLOG")" "lint" "(O7) a check that runs exit 0 ends only itself"

vars_reset
var run_tests "true"
var setup_command 'failed=" setup_command:9"; CHECKS=99'
show_ok; run_block
eq "$GATE_RC" 0 "(O8) a check cannot rewrite the gate's own tally"
has "$GATE_OUT" 'GATE PASSED' "(O8) the gate still reports its own verdict"

vars_reset; var run_tests "true"
var setup_command ''; var typecheck_command ''; var lint_command ''; var build_command ''; var test_command ''
show_ok; run_block
eq "$RANLOG" "" "(O9) nothing runs when the rig sets no check"
eq "$CHECKLIST" "" "(O9) the check list is empty"
has "$OUT" 'run-tests: rig fixture-rig sets no check commands' "(O9) no checks is reported, so the CLAUDE.md fallback applies"

echo "── (F) an unreadable read runs nothing ──"
fail_closed() {   # fail_closed LABEL — assert the last run drained and ran nothing
  eq "$RC" 1 "$1: block exits 1"
  has "$GCLOG" 'DRAIN' "$1: drains"
  eq "$RANLOG" "" "$1: no check ran"
  eq "$CHECKLIST" "" "$1: no check was written"
  hasnt "$OUT" 'sets no check commands' "$1: never reads as a rig with no checks"
}
vars_reset; all_checks_default; show_ok
printf '%s' '{"schema_version":"1","ok":false,"error":{"code":"command_failed","message":"rig is not registered","exit_code":1}}' > "$STUB_SHOW"
STUB_SHOW_RC=1 run_block; fail_closed "(F1) gc formula show refuses (ok:false, exit 1)"
printf 'not json' > "$STUB_SHOW"
run_block; fail_closed "(F2) a non-JSON answer at exit 0"
: > "$STUB_SHOW"
run_block; fail_closed "(F3) an empty answer at exit 0"
printf '%s' '{"schema_version":"1","ok":true}' > "$STUB_SHOW"
run_block; fail_closed "(F4) ok:true with no vars array"
vars_reset; all_checks_default; show_ok
RIG="" run_block; fail_closed "(F5) GC_RIG empty"
hasnt "$GCLOG" 'formula show' "(F5) no rig to scope the read to, so nothing is read"
# A check the block cannot write would leave the gate a list without it.
vars_reset; all_checks_default; show_ok
CHECKS_RO=1 run_block; fail_closed "(F6) a check list it cannot write"
has "$OUT" 'cannot write the setup_command check' "(F6) it names the check it could not write"

echo "── (Z) zsh runs the block the same way ──"
if command -v zsh >/dev/null 2>&1; then
  # -f skips the startup files, so the host's zsh setup cannot change the run.
  vars_reset
  var run_tests "true"
  rigvar lint_command 'echo DEFAULT-LINT >> "$RAN"' 'echo RIG-LINT >> "$RAN"'
  var typecheck_command 'exit 3'
  var build_command 'false; FIRST_RC=$?; echo second >> "$RAN" && [ "$FIRST_RC" -eq 0 ]'
  var test_command 'echo test >> "$RAN"'
  show_ok; run_block zsh -f
  eq "$RC" 0 "(Z1) under zsh: block exits 0 when it wrote its checks"
  eq "$(lines "$RANLOG")" "RIG-LINT second test" "(Z1) under zsh: rig value wins, checks run in order past failures"
  has "$GATE_OUT" 'GATE FAILED: typecheck_command:3 build_command:1' "(Z1) under zsh: the gate names every failed check with its exit code"
  printf 'not json' > "$STUB_SHOW"
  run_block zsh -f; fail_closed "(Z2) under zsh: an unreadable read"
else
  echo "skip - zsh not installed; (Z) cases not run"
fi

echo "── (P) the formula's own defaults ──"
if TOML_PY="$(tomllib_python)"; then
  DEFAULTS=$("$TOML_PY" -c '
import sys, tomllib
v = tomllib.load(open(sys.argv[1], "rb"))["vars"]
for name in ("run_tests", "setup_command", "typecheck_command", "lint_command", "build_command", "test_command"):
    print("%s=%s" % (name, v[name]["default"]) if name in v else "%s MISSING" % name)
' "$TOML")
  hasnt "$DEFAULTS" 'MISSING' "(P1) every var the block reads is declared"
  for name in setup_command typecheck_command lint_command build_command test_command; do
    has "$DEFAULTS" "$name=" "(P2) $name is declared"
    printf '%s\n' "$DEFAULTS" | awk -v n="$name=" 'index($0, n) == 1 && length($0) > length(n) {found=1} END {exit found}' \
      && ok "(P2) $name default is empty — the town wires each rig's command" \
      || bad "(P2) $name default is empty — the town wires each rig's command (got: $(printf '%s\n' "$DEFAULTS" | grep "^$name="))"
  done
else
  bad "(P) tomllib unavailable: $TOML_PY"
fi
# No text in the formula invites a hand-filled check value beside the block.
for name in run_tests setup_command typecheck_command lint_command build_command test_command; do
  eq "$(grep -c -F "{{$name}}" "$TOML" || true)" 0 "(P3) the formula carries no {{$name}} placeholder"
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
