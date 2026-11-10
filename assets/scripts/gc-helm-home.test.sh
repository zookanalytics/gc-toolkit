#!/usr/bin/env bash
# Hermetic test for gc-helm's home page and its two seats: a bare `gc-helm`,
# `gc-helm po` and `gc-helm mechanik`.
#
# Runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a stubbed `gc` on
# PATH that records every call. No live city, controller, tmux or session.
# Covered:
#   (HOME)        a bare gc-helm on a terminal hands it to the conversation form
#                 on its home page
#   (HOME-NOTTY)  without a terminal it names the verbs and the home page,
#                 prints the usage and exits 2, opening no form
#   (HOME-MISSING) with no form built it exits 3, naming each entry's command
#   (PO, MK)      a seat's verb is one `gc session attach` on the seat's name,
#                 which starts a seat that is not running, and nothing else: no
#                 listing, no nudge and no wake of its own; once the attach
#                 comes back it names how to return
#   (PO-ATTACH-FAIL, MK-ATTACH-FAIL) an attach that fails exits 4, naming the
#                 re-run and no return
#   (PO-ARGS, MK-ARGS) an argument or a flag exits 2 and calls nothing
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
SCRIPT_REAL="$(readlink -f "$SCRIPT" 2>/dev/null || printf '%s' "$SCRIPT")"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-home-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()    { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# The session's own city must not reach a hermetic run.
unset GC_CITY_PATH GC_CITY GC_CITY_ROOT GC_RIG BEADS_DIR GC_HELM_FIXTURE GC_HELM_ASSUME_TTY GC_HELM_FORM_BIN || true
export CALLS="$TMP/calls"
mkdir -p "$TMP/bin" "$TMP/agents/converse-claude-opus"
export GC_HELM_AGENTS_DIR="$TMP/agents" TMPDIR="$TMP"

# The stub records each call on a line of its own. `gc session attach` exits
# $ATTACH_RC, saying why on stderr when that is not 0, as gc does; every other
# call is one the verbs must not make, so the stub fails it.
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" | tr '\n' ' ' >> "$CALLS"; printf '\n' >> "$CALLS"
case "$1 ${2:-}" in
  "session attach")
    [ "${ATTACH_RC:-0}" -eq 0 ] || echo "gc session attach: session ${3:-} did not start within 2m0s; not attaching" >&2
    exit "${ATTACH_RC:-0}" ;;
  *) echo "stub gc: unhandled: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gc"

# The conversation form's stand-in records the argv it was handed.
cat > "$TMP/bin/form-stub" <<'FORM'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done > "$FORM_ARGV_FILE"
echo "form-stub ran"
FORM
chmod +x "$TMP/bin/form-stub"
export FORM_ARGV_FILE="$TMP/form.argv"
export PATH="$TMP/bin:$PATH"

# reset — no calls recorded and no form run.
reset() { : > "$CALLS"; rm -f "$FORM_ARGV_FILE"; }

# run <verb> [args...] -> RC/OUT/CALLED. stdin is /dev/null, so no terminal.
run() {
  set +e
  OUT="$(sh "$SCRIPT" "$@" </dev/null 2>"$TMP/err")"; RC=$?
  set -e
  OUT="$OUT$(cat "$TMP/err")"
  CALLED="$(cat "$CALLS")"
}

echo "# a bare gc-helm opens the home page on a terminal, and without one prints its usage"
reset
set +e
OUT="$(GC_HELM_ASSUME_TTY=1 GC_HELM_FORM_BIN="$TMP/bin/form-stub" sh "$SCRIPT" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(HOME) a bare gc-helm on a terminal runs the form"
eq "$(paste -s -d'|' - < "$FORM_ARGV_FILE" 2>/dev/null || true)" "form|--helm|$SCRIPT_REAL|--models|claude-opus|--home" "(HOME) …on its home page, handed this script's path"
reset
set +e
OUT="$(GC_HELM_FORM_BIN="$TMP/bin/form-stub" sh "$SCRIPT" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 2 "(HOME-NOTTY) a bare gc-helm without a terminal exits 2"
has "$OUT" "name a verb" "(HOME-NOTTY) …asking for a verb"
has "$OUT" "a bare gc-helm opens the home page" "(HOME-NOTTY) …saying what it does on a terminal"
has "$OUT" "gc-helm po  attach to the po" "(HOME-NOTTY) …and printing the usage, the seats included"
eq "$(cat "$FORM_ARGV_FILE" 2>/dev/null || true)" "" "(HOME-NOTTY) …opening no form"
reset
set +e
OUT="$(GC_HELM_ASSUME_TTY=1 GC_HELM_FORM_BIN="$TMP/no-such-form" sh "$SCRIPT" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 3 "(HOME-MISSING) with no form built a bare gc-helm exits 3"
has "$OUT" "no helm-svc binary is built" "(HOME-MISSING) …saying the form is not built"
has "$OUT" "gc-helm po to open the po, gc-helm mechanik to attach to mechanik" "(HOME-MISSING) …naming the seats' commands"
has "$OUT" "gc-helm attach <conversation> to return" "(HOME-MISSING) …and the conversations' commands"

echo "# a seat's verb is Gas City's attach on the seat, and nothing else"
reset; run po
eq "$RC" 0 "(PO) po exits 0 once the attach comes back"
eq "$CALLED" "session attach gc-toolkit.po " "(PO) …having made one call, the attach on the po's seat"
has "$OUT" "Return to the po with: gc-helm po" "(PO) …and naming how to return"
reset; run mechanik
eq "$RC" 0 "(MK) mechanik exits 0 once the attach comes back"
eq "$CALLED" "session attach gc-toolkit.mechanik " "(MK) …having made one call, the attach on mechanik's seat"
has "$OUT" "Return to mechanik with: gc-helm mechanik" "(MK) …and naming how to return"

echo "# an attach that fails exits 4"
reset; ATTACH_RC=1 run po
eq "$RC" 4 "(PO-ATTACH-FAIL) an attach that fails exits 4"
has "$OUT" "did not start within 2m0s" "(PO-ATTACH-FAIL) …leaving gc's reason in view"
has "$OUT" "gc session attach gc-toolkit.po exited 1, so the po was not attached. Re-run: gc-helm po" "(PO-ATTACH-FAIL) …and naming the re-run"
hasnt "$OUT" "Return to" "(PO-ATTACH-FAIL) …and no return"
reset; ATTACH_RC=1 run mechanik
eq "$RC" 4 "(MK-ATTACH-FAIL) mechanik's attach that fails exits 4"
has "$OUT" "so mechanik was not attached. Re-run: gc-helm mechanik" "(MK-ATTACH-FAIL) …naming the re-run"

echo "# a seat's verb takes no argument"
reset; run po now
eq "$RC" 2 "(PO-ARGS) an argument exits 2"
has "$OUT" "po takes no argument" "(PO-ARGS) …saying so"
reset; run po --bogus
eq "$RC" 2 "(PO-ARGS) an unknown flag exits 2"
has "$OUT" "po: unknown flag '--bogus'" "(PO-ARGS) …naming the flag"
eq "$(cat "$CALLS")" "" "(PO-ARGS) …each calling nothing"
reset; run mechanik now
eq "$RC" 2 "(MK-ARGS) an argument exits 2"
reset; run mechanik --bogus
eq "$RC" 2 "(MK-ARGS) an unknown flag exits 2"
eq "$(cat "$CALLS")" "" "(MK-ARGS) …each calling nothing"

echo
echo "gc-helm-home: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
