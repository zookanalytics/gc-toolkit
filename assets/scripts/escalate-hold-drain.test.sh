#!/usr/bin/env bash
# Hermetic test for escalate-hold-drain.sh: a declined step records its release
# path, then holds, then drains, and each stage runs only after the one before
# it landed.
#
# What it holds:
#   1. ORDER — with a visit, escalate precedes the hold and the hold precedes
#      the drain; each tool receives the arguments it was given.
#   2. NO VISIT — without --key the hold and drain run and nothing escalates.
#   3. FAIL CLOSED — a failed escalation holds and drains nothing (exit 3); a
#      hold that did not fully land drains nothing (exit 4).
#   4. USAGE — a missing --step or --reason, or a partial visit, refuses with
#      exit 2 and runs nothing.
#
# Fakes escalate.sh, molecule-hold.sh and gc; no city, Dolt, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/escalate-hold-drain.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-escalate-hold-drain-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }

[ -x "$SUT" ] || { echo "not executable: $SUT" >&2; exit 1; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1 $2" = "runtime drain-ack" ] && { printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0; }
exit 0
GC
cat > "$TMP/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf 'ESCALATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "$FAKE_ESC"
exit "${FAKE_ESC_RC:-0}"
ESC
cat > "$TMP/molecule-hold.sh" <<'HOLD'
#!/usr/bin/env bash
printf 'HOLD\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "$FAKE_HOLD"
exit "${FAKE_HOLD_RC:-0}"
HOLD
chmod +x "$TMP/bin/gc" "$TMP/escalate.sh" "$TMP/molecule-hold.sh"
export PATH="$TMP/bin:$PATH"
export GC_ESCALATE_TOOL="$TMP/escalate.sh" GC_MOLECULE_HOLD_TOOL="$TMP/molecule-hold.sh"
export FAKE_LOG="$TMP/log" FAKE_ESC="$TMP/esc" FAKE_HOLD="$TMP/hold"

# run <args...> -> prints "<rc>|<ordered verb trace>"
run() {
  : > "$FAKE_LOG"; : > "$FAKE_ESC"; : > "$FAKE_HOLD"
  local rc=0
  "$SUT" "$@" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$FAKE_LOG")"
}

VISIT=(--subject tk-work --key polecat-x --message "a human decides X")
HELD=(--step mol-polecat-work.load-context --bead tk-step --reason "held for X")

# --- 1. Order. ----------------------------------------------------------------
eq "$(run "${HELD[@]}" "${VISIT[@]}")" "0|ESCALATE;HOLD;DRAIN;" \
   "with a visit: escalates, then holds, then drains"
eq "$(cat "$FAKE_ESC")" "--subject tk-work --key polecat-x --message a human decides X" \
   "escalate.sh receives the subject, key and message"
eq "$(cat "$FAKE_HOLD")" "--step mol-polecat-work.load-context --bead tk-step --reason held for X" \
   "molecule-hold.sh receives the step, the bead hint and the reason"

run --step mol-polecat-work.load-context --reason "no hint" >/dev/null
eq "$(cat "$FAKE_HOLD")" "--step mol-polecat-work.load-context --bead  --reason no hint" \
   "an absent --bead reaches molecule-hold.sh as an empty hint"

# --- 2. No visit. -------------------------------------------------------------
eq "$(run "${HELD[@]}")" "0|HOLD;DRAIN;" \
   "without --key: holds and drains, files no visit"

# --- 3. Fail closed. ----------------------------------------------------------
eq "$(FAKE_ESC_RC=1 run "${HELD[@]}" "${VISIT[@]}")" "3|ESCALATE;" \
   "a failed escalation neither holds nor drains"
has "$(cat "$TMP/out")" "NOT holding or draining" \
   "a failed escalation says why the step stays claimable"
eq "$(FAKE_HOLD_RC=1 run "${HELD[@]}" "${VISIT[@]}")" "4|ESCALATE;HOLD;" \
   "a hold that did not land does not drain"
has "$(cat "$TMP/out")" "NOT draining" \
   "a failed hold says why the session does not drain"
eq "$(FAKE_HOLD_RC=1 run "${HELD[@]}")" "4|HOLD;" \
   "without a visit, a hold that did not land does not drain either"

# --- 4. Usage. ----------------------------------------------------------------
eq "$(run --reason "x")" "2|" "a missing --step refuses and runs nothing"
eq "$(run --step mol-polecat-work.load-context)" "2|" "a missing --reason refuses and runs nothing"
eq "$(run "${HELD[@]}" --subject tk-work --key polecat-x)" "2|" \
   "a visit without its message refuses and runs nothing"
eq "$(run "${HELD[@]}" --key)" "2|" "an option without its value refuses"
eq "$(run "${HELD[@]}" --bogus x)" "2|" "an unknown option refuses"

echo
echo "escalate-hold-drain: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
