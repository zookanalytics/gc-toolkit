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
# esc_subj <mode> <epic>: did any <mode> call (file|retract) land on this epic,
# whatever its key. Used to assert an arm filed NOTHING new across every key.
esc_subj()  { grep -qF "$(printf '%s\t%s\t' "$1" "$2")" "$ESC_CALLS"; }

FULL='{"epic_handle":"h","epic_hypothesis":"for X, Y, signal Z","epic_closure_condition":"3 checks","epic_indicators":"one"}'

# --- 1. floor: an epic with no recorded hypothesis gets one floor visit -------
store "[$(epic E1 open '{}')]"
run_sut
eq "$(esc_count)" "1" "a hypothesis-less epic gets exactly one visit"
if esc_has file E1 epic-floor; then ok "the visit is the floor visit on the epic"; else bad "expected a file/E1/epic-floor visit"; fi

# --- 2. contract: hypothesis present but closure/indicators missing. The floor
# concern has cleared, so that visit is retracted in the same pass. -------------
store "[$(epic E2 open '{"epic_hypothesis":"for X, Y, signal Z"}')]"
run_sut
if esc_has file E2 epic-contract; then ok "the contract visit is filed"; else bad "expected a file/E2/epic-contract visit"; fi
if esc_has retract E2 epic-floor; then ok "the cleared floor visit is retracted"; else bad "expected a retract/E2/epic-floor call"; fi

# --- 3. a fully-elaborated epic with no landed units owes no NEW visit; its now-
# cleared floor and contract visits are retracted, and no ruling is filed. ------
store "[$(epic E3 open "$FULL")]"
run_sut
if esc_has retract E3 epic-floor; then ok "the cleared floor visit is retracted"; else bad "expected retract/E3/epic-floor"; fi
if esc_has retract E3 epic-contract; then ok "the cleared contract visit is retracted"; else bad "expected retract/E3/epic-contract"; fi
if esc_subj file E3; then bad "a complete-contract epic with work in flight owes no new visit"; else ok "no new visit is filed on a complete epic with work in flight"; fi

# --- 4. ruling: every unit landed, no ruling -> the ruling visit fires --------
store "[$(epic E4 open "$FULL"), $(child C1 closed), $(child C2 closed)]"
: > "$ESC_CALLS"
printf 'C1|parent-child|E4\nC2|parent-child|E4\n' > "$STUB_DEPS"
"$SUT" >/dev/null 2>&1
if esc_has file E4 epic-ruling; then ok "the ruling visit fires when every unit has landed"; else bad "expected a file/E4/epic-ruling visit"; fi

# --- 5. a unit still in flight: the ruling is not yet owed --------------------
store "[$(epic E5 open "$FULL"), $(child C3 closed), $(child C4 open)]"
: > "$ESC_CALLS"
printf 'C3|parent-child|E5\nC4|parent-child|E5\n' > "$STUB_DEPS"
"$SUT" >/dev/null 2>&1
if esc_subj file E5; then bad "an epic with a unit still open must not be asked for a ruling"; else ok "an epic with a unit still open is not asked for a ruling"; fi

# --- 6. a ruled (still-open) epic: every visit it cleared is retracted, releasing
# the finalize hold so the epic can close, and nothing new is filed. -----------
store "[$(epic E6 open "$(printf '%s' "$FULL" | jq -c '. + {"epic_ruling":"persevere"}')")]"
run_sut
if esc_has retract E6 epic-ruling; then ok "the ruling visit is retracted once a valid ruling is recorded"; else bad "expected a retract/E6/epic-ruling call"; fi
if esc_subj file E6; then bad "a fully ruled epic owes no new visit"; else ok "a fully ruled epic files nothing new"; fi

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

# --- 8a. the gate holds every non-closed epic, so an in_progress epic is audited
# too — open-only would strand an in_progress epic whose units later all land. ---
store "[$(epic EI in_progress '{}')]"
run_sut
if esc_has file EI epic-floor; then ok "an in_progress epic is audited (its floor is owed)"; else bad "expected the floor visit on an in_progress epic"; fi

# --- 8b. a present-but-off-enum ruling ("pending", a typo) is not a ruling: the
# arm does not retract, and files for a real one (persevere|pivot|close), matching
# the finalize gate and the doctor backstop. ----------------------------------
store "[$(epic EO open "$(printf '%s' "$FULL" | jq -c '. + {"epic_ruling":"pending"}')"), $(child C7 closed)]"
: > "$ESC_CALLS"
printf 'C7|parent-child|EO\n' > "$STUB_DEPS"
"$SUT" >/dev/null 2>&1
if esc_has file EO epic-ruling; then ok "an off-enum ruling still owes a ruling visit"; else bad "expected file/EO/epic-ruling for an off-enum ruling"; fi
if esc_has retract EO epic-ruling; then bad "an off-enum ruling must not retract the ruling visit"; else ok "an off-enum ruling does not retract the ruling visit"; fi

# --- 8c. an unreadable children probe is a counted failure, not a silent "no
# ruling owed": the pass names it on stderr and exits non-zero. ----------------
store "[$(epic EP open "$FULL")]"
: > "$ESC_CALLS"
ERRLOG="$TMP/err.log"
STUB_DEP_GARBAGE=1 "$SUT" >/dev/null 2>"$ERRLOG"; RC=$?
eq "$RC" "1" "a pass with an unreadable children probe exits non-zero"
if grep -qF "children probe unreadable for EP" "$ERRLOG"; then ok "the unreadable children probe is named on stderr"; else bad "expected a 'children probe unreadable for EP' stderr line"; fi

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
