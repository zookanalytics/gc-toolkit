#!/usr/bin/env bash
# Hermetic test for assets/scripts/decline.sh: a run ends only with its record in
# place, so each part runs in order and a part that does not land stops the rest.
#
# No live city, Dolt or network: stubs of the three scripts it calls, and of gc.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-decline-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
PACK="$TMP/pack"; mkdir -p "$PACK" "$TMP/bin"
cp "$HERE/decline.sh" "$PACK/"
for pair in human-gate.sh:GATE:GATE_RC await-ruling.sh:AWAIT:AWAIT_RC run-cancel.sh:CANCEL:CANCEL_RC; do
  IFS=: read -r name word rc <<<"$pair"
  cat > "$PACK/$name" <<STUB
#!/usr/bin/env bash
printf '$word\n' >> "\$LOG"
printf '%s\n' "\$*" >> "\$ARGS.$word"
exit "\${$rc:-0}"
STUB
  chmod +x "$PACK/$name"
done
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1 $2" = "runtime drain-ack" ] && printf 'DRAIN\n' >> "$LOG"
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" LOG="$TMP/log" ARGS="$TMP/args"

run() {
  : > "$LOG"; rm -f "$ARGS".*
  OUT=$("$PACK/decline.sh" "$@" 2>&1); RC=$?
  TRACE=$(tr '\n' ' ' < "$LOG")
}
args() { cat "$ARGS.$1" 2>/dev/null; }
GATED=(--step mol.x --reason why --subject tk-w --key k1 --message "the message.")

run --step mol.x --reason why
eq "$RC" 0 "no gate: exits 0"
eq "$TRACE" "CANCEL DRAIN " "no gate: nobody is asked, the run ends and the session drains"
eq "$(args CANCEL)" "--step mol.x --reason why" "the cancel names the step and the reason"

run "${GATED[@]}"
eq "$TRACE" "GATE CANCEL DRAIN " "a gate with no formula: asks, then ends the run, with no wait"
eq "$(args GATE)" "--subject tk-w --key k1 --message the message." "the gate gets the message as given, and declares no quiet window"

run "${GATED[@]}" --formula mol-f
eq "$TRACE" "GATE AWAIT CANCEL DRAIN " "a gate with a formula: asks, waits, ends the run, drains"
eq "$(args AWAIT)" "tk-w --key k1 --formula mol-f" "the wait names the subject, the key and the formula"
has "$(args GATE)" "the message. Then clear this gate: tk-w waits on it, and clearing it re-slings tk-w." "the gate tells the person what clearing it does"
has "$(args GATE)" "To stand down instead, close tk-w first." "and how to stand down"

GATE_RC=1 run "${GATED[@]}" --formula mol-f
eq "$RC" 1 "a gate that does not land exits 1"
eq "$TRACE" "GATE " "and nothing follows it"
has "$OUT" "recorded no gate" "and it says so"
AWAIT_RC=1 run "${GATED[@]}" --formula mol-f
eq "$RC" 1 "a wait that does not land exits 1"
eq "$TRACE" "GATE AWAIT " "and the run is not cancelled"
CANCEL_RC=1 run "${GATED[@]}" --formula mol-f
eq "$RC" 1 "a cancel that does not land exits 1"
eq "$TRACE" "GATE AWAIT CANCEL " "and the session does not drain"
has "$OUT" "NOT draining" "and it says so"
GATE_RC=1 run "${GATED[@]}"
no "$OUT" "run-cancel" "a stop at the gate never names the cancel as tried"

for bad_args in "" "--step mol.x" "--reason why" "--step mol.x --reason why --subject tk-w" \
  "--step mol.x --reason why --key k" "--step mol.x --reason why --formula f" "--nope" "--step"; do
  # shellcheck disable=SC2086  # each case's words are the arguments
  run $bad_args
  eq "$RC" 2 "usage error for: ${bad_args:-no arguments}"
  eq "$TRACE" "" "and nothing runs for: ${bad_args:-no arguments}"
done

echo
echo "decline: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
