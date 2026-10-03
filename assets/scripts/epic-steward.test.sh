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
# A child with NO status field — the shape a cross-store dependency comes back as
# (bead-context.sh resolves those from their own store; this pass does not).
child_nostatus() { printf '{"id":"%s","issue_type":"task","metadata":{}}' "$1"; }
run_sut() { : > "$ESC_CALLS"; : > "$STUB_DEPS"; "$SUT" >/dev/null 2>&1; }
esc_count() { wc -l < "$ESC_CALLS" | tr -d ' '; }
esc_has()   { grep -qF "$(printf '%s\t%s\t%s' "$1" "$2" "$3")" "$ESC_CALLS"; }
# esc_subj <mode> <epic>: did any <mode> call (file|retract) land on this epic,
# whatever its key. Used to assert an arm filed NOTHING new across every key.
esc_subj()  { grep -qF "$(printf '%s\t%s\t' "$1" "$2")" "$ESC_CALLS"; }

FULL='{"epic_handle":"h","epic_hypothesis":"for X, Y, signal Z","epic_boundaries":"not the neighbor","epic_closure_condition":"3 checks","epic_indicators":"one"}'

# --- 1. floor: an epic with no recorded hypothesis gets one floor visit -------
store "[$(epic E1 open '{}')]"
run_sut
eq "$(esc_count)" "1" "a hypothesis-less epic gets exactly one visit"
if esc_has file E1 epic-floor; then ok "the visit is the floor visit on the epic"; else bad "expected a file/E1/epic-floor visit"; fi

# --- 1a. the floor is all three fields, not the hypothesis alone: an epic with a
# hypothesis and handle but NO boundaries still owes its floor, so the floor visit
# is filed and not retracted. Regression for the arm that cleared on a hypothesis
# alone and never asked for the handle/boundaries the contract requires. --------
store "[$(epic EPB open '{"epic_handle":"h","epic_hypothesis":"for X, Y, signal Z"}')]"
run_sut
if esc_has file EPB epic-floor; then ok "a hypothesis+handle epic missing boundaries still owes its floor"; else bad "expected a file/EPB/epic-floor visit"; fi
if esc_has retract EPB epic-floor; then bad "a partial floor must not retract the floor visit"; else ok "a partial floor does not retract the floor visit"; fi

# --- 1b. the same when the handle is the missing field: a hypothesis and
# boundaries but NO handle still owes the floor. -------------------------------
store "[$(epic EPH open '{"epic_hypothesis":"for X, Y, signal Z","epic_boundaries":"not the neighbor"}')]"
run_sut
if esc_has file EPH epic-floor; then ok "a hypothesis+boundaries epic missing a handle still owes its floor"; else bad "expected a file/EPH/epic-floor visit"; fi

# --- 2. contract: a complete floor (handle, hypothesis, boundaries) but closure
# and indicators missing. The floor concern has cleared, so that visit is
# retracted in the same pass while the contract visit is filed. ----------------
store "[$(epic E2 open '{"epic_handle":"h","epic_hypothesis":"for X, Y, signal Z","epic_boundaries":"not the neighbor"}')]"
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

# --- 8d. the gate is status-agnostic, so a blocked epic is audited too: the pass
# enumerates every non-closed status, not just open,in_progress. open-only would
# strand a blocked epic whose units later all land with no ruling visit filed. --
store "[$(epic EBL blocked '{}')]"
run_sut
if esc_has file EBL epic-floor; then ok "a blocked epic is audited (its floor is owed)"; else bad "expected the floor visit on a blocked epic"; fi

# --- 8e. and a deferred epic is audited too. ----------------------------------
store "[$(epic EDF deferred '{}')]"
run_sut
if esc_has file EDF epic-floor; then ok "a deferred epic is audited (its floor is owed)"; else bad "expected the floor visit on a deferred epic"; fi

# --- 8e'. a hooked and a pinned epic are audited too: the gate holds every
# non-closed status, so the pass must enumerate the full live set (the set
# gc-helm.sh uses), not stop at blocked/deferred. A hooked or pinned epic left
# out would strand exactly as a blocked one does. -----------------------------
store "[$(epic EHK hooked '{}')]"
run_sut
if esc_has file EHK epic-floor; then ok "a hooked epic is audited (its floor is owed)"; else bad "expected the floor visit on a hooked epic"; fi
store "[$(epic EPN pinned '{}')]"
run_sut
if esc_has file EPN epic-floor; then ok "a pinned epic is audited (its floor is owed)"; else bad "expected the floor visit on a pinned epic"; fi

# --- 8f. a multi-line contract value must not split one epic across read rows.
# epic_closure_condition is a multi-line list (3-6 checks); jq -r decodes its JSON
# \n to a real newline. The pass emits presence flags, not the raw text, so this
# complete epic is read as ONE row: its cleared floor/contract visits are retracted
# and NOTHING is filed — no contract visit on a truncated first row, no bogus floor
# visit on a continuation line read as an epic id. --------------------------------
store "[$(epic EML open '{"epic_handle":"h","epic_hypothesis":"hyp","epic_boundaries":"b","epic_closure_condition":"check 1\ncheck 2\ncheck 3","epic_indicators":"i"}')]"
run_sut
if grep -q "$(printf '^file\t')" "$ESC_CALLS"; then bad "a multi-line contract value split the row and filed a visit"; else ok "a multi-line contract value files no visit (row not split)"; fi
if esc_has retract EML epic-contract; then ok "the complete multi-line epic is read as one row (contract retracted)"; else bad "expected retract/EML/epic-contract"; fi

# --- 8g. a cross-store unit (no embedded status) cannot be judged landed: it is
# counted a failure and named, not silently read as in-flight forever. Before this
# guard (.status // "") read the status-less child as unlanded, so a complete epic
# with one cross-store unit could never reach "all landed" and never be ruled. ----
store "[$(epic EXS open "$FULL"), $(child_nostatus CXS)]"
: > "$ESC_CALLS"
printf 'CXS|parent-child|EXS\n' > "$STUB_DEPS"
ERRLOG2="$TMP/err2.log"
"$SUT" >/dev/null 2>"$ERRLOG2"; RC=$?
eq "$RC" "1" "a cross-store unit with no status makes the pass exit non-zero"
if grep -qF "no embedded status" "$ERRLOG2" && grep -qF "EXS" "$ERRLOG2"; then ok "the status-less unit is named on stderr"; else bad "expected a 'no embedded status' stderr line naming EXS"; fi
if esc_has file EXS epic-ruling; then bad "a status-less unit must not yield a ruling visit"; else ok "no ruling visit is filed when a unit's status is unknown"; fi

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

# --- 10b. a lock held past the stall bound is reported (exit 1), not skipped
# silently every tick: the stall detection the shared single-flight helper brings.
# A holder timestamp of 1 (1970) is older than any bound, so a wedged pass surfaces.
mkdir -p "$TMP/state/alpha"
store "[$(epic EA2 open '{}')]"
: > "$ESC_CALLS"
exec 8>"$TMP/state/alpha/pass.lock"
flock -n 8
printf '999999 1\n' > "$TMP/state/alpha/pass.holder"
STALLERR="$TMP/stall-err.log"
EPIC_STEWARD_LOCK_STALL_SECS=60 "$SUT" >/dev/null 2>"$STALLERR"; RC=$?
flock -u 8; exec 8>&-
rm -f "$TMP/state/alpha/pass.holder"
eq "$RC" "1" "a holder older than the stall bound fails the pass (reported, not skipped)"
if grep -qF "wedged" "$STALLERR"; then ok "the wedged pass is named on stderr"; else bad "expected a 'wedged' stderr line"; fi
eq "$(esc_count)" "0" "the wedged tick files nothing"

echo
echo "epic-steward: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
