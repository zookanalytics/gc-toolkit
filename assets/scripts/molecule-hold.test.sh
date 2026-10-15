#!/usr/bin/env bash
# Hermetic test for assets/scripts/molecule-hold.sh.
#
# The constraint: a molecule keeps the step text it was poured with, so step
# text that names molecule-hold.sh still requires it and calls it to decline.
# The script holds nothing. It hands the call to run-cancel.sh's --step mode
# unchanged and refuses anything else, so such a run ends through gascity's run
# cancel like any other decline.
#
# What is exercised here:
#   * the hand-off: the arguments reach run-cancel.sh exactly as given and in
#     order, an empty --bead and a reason that starts with a dash included, and
#     run-cancel.sh's exit code is the script's;
#   * the old call shape gets through the real run-cancel.sh's parser to its
#     session check;
#   * refusals: --root, --ended, --db, an unknown flag, a flag with no value,
#     --help; none of them reaches run-cancel.sh;
#   * a run-cancel.sh that is not there exits 1, so the caller does not drain.
#
# No live city, Dolt, or network: a stub run-cancel.sh, and the real one under
# an empty environment with a `gc` that fails if it is called.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/molecule-hold.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-molecule-hold-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true

# The stub writes one bracketed argument per line, so an empty argument reads
# as [] and an argument's own spaces stay inside its brackets.
STUB="$TMP/run-cancel.sh"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$STUB" <<'STUB'
printf '[%s]\n' "$@" > "${STUB_ARGV:?}"
exit "${STUB_RC:-0}"
STUB
chmod +x "$STUB"

RC=0; OUT=""
run() { # <stub exit code> <args...>; sets RC and OUT (stderr)
  local stub_rc="$1"; shift
  rm -f "$TMP/argv"
  OUT=$(GC_RUN_CANCEL_TOOL="$STUB" STUB_ARGV="$TMP/argv" STUB_RC="$stub_rc" "$SCRIPT" "$@" 2>&1 >/dev/null)
  RC=$?
}
argv() { # what the stub received, on one line
  if [ -f "$TMP/argv" ]; then tr '\n' ' ' < "$TMP/argv" | sed 's/ $//'; else printf '<not called>'; fi
}

# --- 1. The hand-off. ----------------------------------------------------------
run 0 --step mol-polecat-work.load-context --bead "" --reason "duplicate dispatch: tk-w in flight"
eq "$RC" 0 "the old load-context call exits as run-cancel.sh does"
eq "$(argv)" "[--step] [mol-polecat-work.load-context] [--bead] [] [--reason] [duplicate dispatch: tk-w in flight]" \
  "the old load-context call reaches run-cancel.sh unchanged, its empty --bead included"

run 0 --step mol-rig-demo.capture --bead tk-step1 --reason "-x is a reason, not a flag" --dry-run
eq "$(argv)" "[--step] [mol-rig-demo.capture] [--bead] [tk-step1] [--reason] [-x is a reason, not a flag] [--dry-run]" \
  "a reason that starts with a dash stays a value, and --dry-run is handed on"

run 1 --step mol-polecat-work.submit-and-exit --reason "r"
eq "$RC" 1 "a run run-cancel.sh did not end exits 1, so the caller does not drain"
run 2 --step mol-validate.load-dispatch --reason "r"
eq "$RC" 2 "a call run-cancel.sh refused exits 2"

# --- 2. Only the --step mode is handed on. -------------------------------------
for args in "--root tk-root --reason r" "--step s --ended --reason r" "--step s --db /x --reason r" \
            "--step s --reason r --bogus" "--step s --reason" "--help"; do
  # shellcheck disable=SC2086  # each case is a word list on purpose
  run 0 $args
  eq "$RC" 2 "refused with exit 2: $args"
  eq "$(argv)" "<not called>" "refused before run-cancel.sh runs: $args"
done

# --- 3. No run-cancel.sh. -------------------------------------------------------
OUT=$(GC_RUN_CANCEL_TOOL="$TMP/absent.sh" "$SCRIPT" --step mol-polecat-work.load-context --reason r 2>&1 >/dev/null); RC=$?
eq "$RC" 1 "no run-cancel.sh: exit 1, so the caller does not drain"
has "$OUT" "not ended" "no run-cancel.sh: says the run is not ended"

# --- 4. The real run-cancel.sh beside the script. ------------------------------
# An empty environment names no session, so run-cancel.sh stops at its session
# check, which it reaches only after it has accepted every argument.
mkdir -p "$TMP/nogc"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/nogc/gc" <<'GC'
printf '%s\n' "$*" >> "${0%/*}/called"
exit 97
GC
chmod +x "$TMP/nogc/gc"
OUT=$(env -i PATH="$TMP/nogc:$PATH" HOME="$TMP" "$SCRIPT" --step mol-polecat-work.load-context --bead "" \
  --reason "possible duplicate" --dry-run 2>&1 >/dev/null); RC=$?
eq "$RC" 2 "the real run-cancel.sh refuses for want of a session, exit 2"
has "$OUT" "no session identity" "the old call shape gets through the real run-cancel.sh's parser to its session check"
hasnt "$OUT" "unknown argument" "no argument of the old call shape is unknown to the real run-cancel.sh"
eq "$([ -f "$TMP/nogc/called" ] && echo called || echo none)" "none" "the real run-cancel.sh called no gc"

echo
echo "molecule-hold.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
