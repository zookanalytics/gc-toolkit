#!/usr/bin/env bash
# Hermetic test for epic-steward.sh. Uses the shared test-harness stub store and
# a fake escalate.sh that logs the (mode, subject, key) of every visit it files
# or retracts, so the test asserts which arm fired on which epic.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/epic-steward-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
harness_init
export GC_RIG=alpha                       # the driver is scope=rig; it needs one
export EPIC_STEWARD_STATE_DIR="$TMP/state" # isolate the per-rig flock from other runs

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/epic-steward.sh"   # copies the SUT + bd-lib.sh
SUT="$SD/epic-steward.sh"

# Fake escalate.sh: record mode (file|retract), subject, key. escalate.sh's own
# dedup is out of scope here — the test asserts which arm the driver fires.
cat > "$BIN/escalate.sh" <<'ESC'
#!/usr/bin/env bash
mode=file; s=""; k=""
while [ $# -gt 0 ]; do
  case "$1" in
    --retract) mode=retract ;;
    --subject) shift; s="${1:-}" ;;
    --key)     shift; k="${1:-}" ;;
    --message) shift ;;
  esac
  shift || true
done
printf '%s\t%s\t%s\n' "$mode" "$s" "$k" >> "${ESC_CALLS:?}"
ESC
chmod +x "$BIN/escalate.sh"
export GC_ESCALATE_TOOL="$BIN/escalate.sh" ESC_CALLS="$TMP/esc.log"

epic()  { printf '{"id":"%s","issue_type":"epic","status":"%s","title":"an epic","metadata":%s}' "$1" "$2" "$3"; }
child() { printf '{"id":"%s","issue_type":"task","status":"%s","metadata":{}}' "$1" "$2"; }
run_sut() { : > "$ESC_CALLS"; : > "$STUB_DEPS"; "$SUT" >/dev/null 2>&1; }
esc_count() { wc -l < "$ESC_CALLS" | tr -d ' '; }
esc_has()   { grep -qF "$(printf '%s\t%s\t%s' "$1" "$2" "$3")" "$ESC_CALLS"; }

FULL='{"epic_handle":"h","epic_hypothesis":"for X, Y, signal Z","epic_closure_condition":"3 checks","epic_indicators":"one"}'

# --- 1. floor: an epic with no recorded hypothesis gets one floor visit -------
store "[$(epic E1 open '{}')]"
run_sut
eq "$(esc_count)" "1" "a hypothesis-less epic gets exactly one visit"
if esc_has file E1 epic-floor; then ok "the visit is the floor visit on the epic"; else bad "expected a file/E1/epic-floor visit"; fi

# --- 2. contract: hypothesis present but closure/indicators missing -----------
store "[$(epic E2 open '{"epic_hypothesis":"for X, Y, signal Z"}')]"
run_sut
eq "$(esc_count)" "1" "an epic with a floor but no rest-of-contract gets one visit"
if esc_has file E2 epic-contract; then ok "the visit is the contract visit"; else bad "expected a file/E2/epic-contract visit"; fi

# --- 3. a fully-elaborated epic with no landed units is left alone ------------
store "[$(epic E3 open "$FULL")]"
run_sut
eq "$(esc_count)" "0" "a complete-contract epic with work still in flight owes nothing"

# --- 4. ruling: every unit landed, no ruling -> the ruling visit fires --------
store "[$(epic E4 open "$FULL"), $(child C1 closed), $(child C2 closed)]"
: > "$ESC_CALLS"
printf 'C1|parent-child|E4\nC2|parent-child|E4\n' > "$STUB_DEPS"
"$SUT" >/dev/null 2>&1
eq "$(esc_count)" "1" "an epic whose units have all landed gets one visit"
if esc_has file E4 epic-ruling; then ok "the visit is the ruling visit"; else bad "expected a file/E4/epic-ruling visit"; fi

# --- 5. a unit still in flight: the ruling is not yet owed --------------------
store "[$(epic E5 open "$FULL"), $(child C3 closed), $(child C4 open)]"
: > "$ESC_CALLS"
printf 'C3|parent-child|E5\nC4|parent-child|E5\n' > "$STUB_DEPS"
"$SUT" >/dev/null 2>&1
eq "$(esc_count)" "0" "an epic with a unit still open is not asked for a ruling"

# --- 6. a ruled (still-open) epic: the ruling visit is retracted, releasing the
# finalize hold so the epic can close -----------------------------------------
store "[$(epic E6 open "$(printf '%s' "$FULL" | jq -c '. + {"epic_ruling":"persevere"}')")]"
run_sut
eq "$(esc_count)" "1" "a ruled epic makes exactly one escalate call"
if esc_has retract E6 epic-ruling; then ok "the ruling visit is retracted once the ruling is recorded"; else bad "expected a retract/E6/epic-ruling call"; fi

# --- 7. a thin epic with landed units: floor is owed, ruling is NOT -----------
# A ruling answers a hypothesis; without one, the floor arm owns the epic first.
store "[$(epic E7 open '{}'), $(child C5 closed)]"
: > "$ESC_CALLS"
printf 'C5|parent-child|E7\n' > "$STUB_DEPS"
"$SUT" >/dev/null 2>&1
eq "$(esc_count)" "1" "a hypothesis-less epic with landed units owes only the floor"
if esc_has file E7 epic-floor; then ok "the floor arm fires"; else bad "expected the floor visit"; fi
if esc_has file E7 epic-ruling; then bad "ruling must not fire without a hypothesis"; else ok "the ruling arm stays silent without a hypothesis"; fi

# --- 8. one visit per epic across many -----------------------------------------
store "[$(epic E8 open '{}'), $(epic E9 open '{}')]"
run_sut
eq "$(esc_count)" "2" "each hypothesis-less epic gets its own floor visit"

# --- 9. GC_RIG unset: a scope=rig order with no rig refuses -------------------
RC=0; ( unset GC_RIG; "$SUT" >/dev/null 2>&1 ) || RC=$?
eq "$RC" "2" "the driver exits 2 when GC_RIG is unset"

# --- 10. single-flight: a pass already holding the lock skips this tick -------
mkdir -p "$TMP/state/alpha"
store "[$(epic EA open '{}')]"
: > "$ESC_CALLS"
exec 8>"$TMP/state/alpha/pass.lock"
flock -n 8
"$SUT" >/dev/null 2>&1; RC=$?
flock -u 8; exec 8>&-
eq "$RC" "0" "a tick that finds a pass in flight exits 0 (skip, not error)"
eq "$(esc_count)" "0" "the skipped tick files nothing"

echo
echo "epic-steward: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
