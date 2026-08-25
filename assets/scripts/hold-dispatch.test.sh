#!/usr/bin/env bash
# Hermetic tests for hold-dispatch.sh (tk-oqseh6).
#
# THE BUG. A polecat that HOLDS a dispatch parks the ANCHOR by hand and leaves
# the molecule's seven step beads routed to the polecat pool. `load-context` is
# the only unblocked step, the drain releases its assignee, and open +
# unassigned + routed + ready is the pool's offer predicate — so the dead chain
# is served to every idle polecat, forever (observed: anchor tk-iljtmq, molecule
# tk-p3p9iv, re-offered ~3h after the hold).
#
# THE FIX. One writer that parks the anchor AND quiesces its molecule, so the
# park cannot be half-performed. This suite runs the REAL script with `gc` and
# `bd` stubbed on PATH — no live city, Dolt, network, or sessions.
#
# SCENARIO 1 — the ordinary hold (forward walk from the anchor's input convoy):
#   (NOTE)      the hold reason is appended BEFORE any delivery key is written
#   (ANCHOR)    the anchor's route is cleared and its deferred twins unset
#   (ANCHORREL) the anchor's own claim is released, reopening in_progress
#   (AFFINE)    a routed+assigned+affine step -> every pin cleared
#   (ORDER)     route first, assignee second, in TWO separate calls
#   (POOL)      an unassigned+routed step -> route only, no assignee call
#   (DEFERRED)  a step pinned ONLY by a deferred twin is still quiesced
#   (FINAL)     workflow-finalize keeps its control-dispatcher route
#   (IDEM)      an already-quiet step is not re-updated
#   (FOREIGN)   a step held by ANOTHER session is not written AT ALL — its
#               delivery keys survive along with its claim — and the run exits
#               non-zero so the partial hold is visible
#   (REPOUR)    a bead tracked by TWO convoys has BOTH molecules quiesced
#   (NOCLOSE)   no step is closed and no step status is rewritten — asserted
#               dynamically and as a static guard over the source
#   (SUMMARY)   what was done is appended to the anchor in the past tense
#
# SCENARIO 2 — the guards, one run each:
#   (FALLBACK)  a broken `tracks` edge falls back to the reverse step scan
#   (SCOPE)     a molecule whose anchor is NOT the held bead is left untouched
#   (ORPHAN)    a root with no resolvable convoy is skipped, not quiesced
#   (GATE)      a REFUSED route clear skips the assignee clear (never leaves a
#               step open+unassigned+routed) and counts as failed
#   (STEPSONLY) --steps-only quiesces the molecule and touches nothing on the
#               anchor but its notes
#   (NOTMINE)   an anchor held by another session is refused before any write
#   (ABSENT)    a bead that resolves to nothing is refused, and says so in its
#               own words — `bd show` returns well-formed JSON for "no such id"
#   (UNREAD)    an unreadable anchor is refused before any write
#   (DRYRUN)    --dry-run writes nothing at all
#   (ARGS)      --bead and --reason are required; a value-less flag is refused
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/hold-dispatch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -x "$SCRIPT" ] && ok "hold-dispatch.sh present and executable" \
  || bad "hold-dispatch.sh missing or not executable at $SCRIPT"

mkdir -p "$TMP/bin"

POOL="gc-toolkit/gc-toolkit.polecat"
ME="gc-toolkit__polecat-lx-me"
MYAGENT="gc-toolkit/gc-toolkit.furiosa"
OTHER="gc-toolkit__polecat-lx-other"

# --- Fixture ------------------------------------------------------------------
# Beads, one JSON document per id, served by the `gc bd show` stub.
mk_bead() { printf '%s\n' "$2" > "$TMP/beads/$1.json"; }
mkdir -p "$TMP/beads"

# The held bead: OUR claim, in_progress, routed to the pool, with an execution
# route as well (the real held instance tk-iljtmq still carried one a full day
# after it was "parked" — the second half-park inside the first).
mk_bead A-HELD "$(jq -n --arg who "$ME" --arg pool "$POOL" '[{
  id:"A-HELD", status:"in_progress", assignee:$who,
  metadata:{"gc.routed_to":$pool, "gc.execution_routed_to":$pool,
            "gc.deferred_assignee":"someone"}}]')"
mk_bead A-OTHER '[{"id":"A-OTHER","status":"open","assignee":"","metadata":{}}]'
mk_bead A-THEIRS "$(jq -n --arg who "$OTHER" '[{
  id:"A-THEIRS", status:"in_progress", assignee:$who, metadata:{}}]')"
mk_bead root-HELD  '[{"id":"root-HELD","status":"in_progress","metadata":{"gc.input_convoy_id":"convoy-HELD"}}]'
mk_bead root-TWO   '[{"id":"root-TWO","status":"in_progress","metadata":{"gc.input_convoy_id":"convoy-TWO"}}]'
mk_bead root-OTHER '[{"id":"root-OTHER","status":"in_progress","metadata":{"gc.input_convoy_id":"convoy-OTHER"}}]'
mk_bead root-ORPHAN '[{"id":"root-ORPHAN","status":"in_progress","metadata":{}}]'

# Convoys: convoy_id|anchor_id. convoy-ORPHAN is deliberately absent.
cat > "$TMP/convoys" <<C
convoy-HELD|A-HELD
convoy-TWO|A-HELD
convoy-OTHER|A-OTHER
C

# `bd dep list <bead> --direction=up -t tracks`: bead_id|convoy,convoy,...
cat > "$TMP/tracks" <<'T'
A-HELD|convoy-HELD,convoy-TWO
A-THEIRS|
T

# Steps, the `bd list` shape. Under root-HELD:
#   s-load   affine  : routed + OUR assignee + affinity -> all cleared, 2 calls
#   s-impl   pool    : routed only (already unassigned)  -> route only
#   s-defer  deferred: ONLY a deferred twin              -> still quiesced
#   s-final  finalize: control-dispatcher route          -> MUST stay routed
#   s-quiet  quiet   : no pins, no assignee              -> not re-updated
#   s-them   foreign : 4 delivery keys + ANOTHER session's claim -> NO write
# Under root-TWO (the same anchor, a second pour): s-two
# Under root-OTHER (anchor A-OTHER):               s-other   -> untouched
# Under root-ORPHAN (no convoy):                   s-orphan  -> untouched
cat > "$TMP/steps.json" <<JSON
[
  {"id":"s-load","assignee":"$ME","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-HELD","gc.routed_to":"$POOL","gc.session_affinity":"require"}},
  {"id":"s-impl","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-HELD","gc.routed_to":"$POOL"}},
  {"id":"s-defer","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.self-review","gc.root_bead_id":"root-HELD","gc.deferred_routed_to":"$POOL"}},
  {"id":"s-final","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.root_bead_id":"root-HELD","gc.routed_to":"gc-toolkit/core.control-dispatcher","gc.execution_routed_to":"$POOL"}},
  {"id":"s-quiet","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.preflight-tests","gc.root_bead_id":"root-HELD"}},
  {"id":"s-them","assignee":"$OTHER","metadata":{"gc.step_ref":"mol-polecat-work.submit-and-exit","gc.root_bead_id":"root-HELD","gc.routed_to":"$POOL","gc.execution_routed_to":"$POOL","gc.deferred_routed_to":"$POOL","gc.session_affinity":"require"}},
  {"id":"s-two","assignee":"$MYAGENT","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-TWO","gc.routed_to":"$POOL","gc.session_affinity":"require"}},
  {"id":"s-other","assignee":"$OTHER","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-OTHER","gc.routed_to":"$POOL","gc.session_affinity":"require"}},
  {"id":"s-orphan","assignee":"$OTHER","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-ORPHAN","gc.routed_to":"$POOL","gc.session_affinity":"require"}}
]
JSON

# --- gc stub ------------------------------------------------------------------
# Records every `bd update` argv, one line per call (newlines in --append-notes
# squashed so line-order assertions stay readable). FAKE_FAIL matches an argv
# substring: a call whose argv contains it is REFUSED, which is how the gate
# case drives a failed route clear.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
rec() { { printf '%s' "$*" | tr '\n' ' '; printf '\n'; } >> "$FAKE_UPDATES"; }
case "$1 ${2:-} ${3:-}" in
  "bd show "*)
    f="$FAKE_BEADS/$3.json"
    # bd answers an ARRAY when an id resolves and a bare OBJECT when none do.
    if [ -f "$f" ]; then cat "$f"
    elif [ "$3" = "A-UNREADABLE" ]; then printf ''
    else printf '{"error":"no issues found matching the provided IDs"}\n'; fi ;;
  "bd dep list")
    row=$(awk -F'|' -v b="$4" '$1==b{print $2; exit}' "$FAKE_TRACKS")
    printf '%s' "$row" | tr ',' '\n' | jq -R 'select(length>0) | {id:., issue_type:"convoy"}' | jq -s '.' ;;
  "bd list "*|"bd list")
    case "$*" in
      *gc.input_convoy_id=*)
        c=$(printf '%s\n' "$@" | sed -n 's/^gc\.input_convoy_id=//p' | head -n1)
        # roots whose gc.input_convoy_id is $c
        for r in "$FAKE_BEADS"/root-*.json; do
          id=$(jq -r '.[0].id' "$r"); ic=$(jq -r '.[0].metadata["gc.input_convoy_id"] // ""' "$r")
          [ "$ic" = "$c" ] && printf '%s\n' "$id"
        done | jq -R '{id:.}' | jq -s '.' ;;
      *gc.root_bead_id=*)
        r=$(printf '%s\n' "$@" | sed -n 's/^gc\.root_bead_id=//p' | head -n1)
        jq --arg r "$r" '[.[] | select(.metadata["gc.root_bead_id"] == $r)]' "$FAKE_STEPS" ;;
      *) cat "$FAKE_STEPS" ;;
    esac ;;
  "bd update "*)
    rec "$@"
    case "$*" in *"${FAKE_FAIL:-__never__}"*) exit 1 ;; esac ;;
  "convoy status "*)
    a=$(awk -F'|' -v c="$3" '$1==c{print $2; exit}' "$FAKE_CONVOYS")
    if [ -n "$a" ]; then jq -n --arg a "$a" '{children:[{id:$a}]}'
    else printf '{"children":[]}\n'; fi ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# Bare `bd` — reached only for the --force fallback on the assignee half.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
{ printf 'FORCE %s' "$*" | tr '\n' ' '; printf '\n'; } >> "$FAKE_UPDATES"
exit 0
BD
chmod +x "$TMP/bin/bd"

export PATH="$TMP/bin:$PATH"
export FAKE_BEADS="$TMP/beads" FAKE_CONVOYS="$TMP/convoys" \
       FAKE_TRACKS="$TMP/tracks" FAKE_STEPS="$TMP/steps.json"
export GC_SESSION_NAME="$ME" GC_ALIAS="$MYAGENT" GC_AGENT="$MYAGENT" GC_SESSION_ID="lx-me"

run_hold() {
  UP="$TMP/updates.$1"; shift
  : > "$UP"
  # `&& RC=0 || RC=$?` rather than `; RC=$?`: this suite runs under `set -e`,
  # and every guard case here exits non-zero ON PURPOSE.
  FAKE_UPDATES="$UP" "$SCRIPT" "$@" >"$UP.out" 2>"$UP.err" && RC=0 || RC=$?
  return 0
}
line_for()  { grep -E "^bd update $2( |$)" "$1" || true; }
force_for() { grep -E "^FORCE update $2( |$)" "$1" || true; }

# ============================ SCENARIO 1 ======================================
run_hold s1 --bead A-HELD --reason "live sitting owns the decision"
S1="$TMP/updates.s1"

# (NOTE) the reason is recorded BEFORE anything is de-routed: a run that dies
# mid-walk must leave an explained bead, never a silently de-routed one.
NOTE_LINE=$(grep -n -- '--append-notes' "$S1" | head -n1 | cut -d: -f1)
ROUTE_LINE=$(grep -n -- '--set-metadata gc.routed_to=' "$S1" | head -n1 | cut -d: -f1)
if [ -n "$NOTE_LINE" ] && [ -n "$ROUTE_LINE" ] && [ "$NOTE_LINE" -lt "$ROUTE_LINE" ]; then
  ok "(NOTE) the hold reason is appended before the first delivery write"
else
  bad "(NOTE) reason must be recorded first (note=$NOTE_LINE route=$ROUTE_LINE)"
fi
grep -q 'live sitting owns the decision' "$S1" \
  && ok "(NOTE) the caller's reason reaches the bead verbatim" \
  || bad "(NOTE) reason text missing from the appended note"

# (ANCHOR) the anchor's own delivery keys.
A=$(line_for "$S1" A-HELD)
grep -q -- '--set-metadata gc.routed_to=' <<< "$A" \
  && ok "(ANCHOR) anchor route cleared" || bad "(ANCHOR) anchor route (got: $A)"
grep -q -- '--unset-metadata gc.execution_routed_to' <<< "$A" \
  && ok "(ANCHOR) anchor execution route cleared" || bad "(ANCHOR) execution route (got: $A)"
grep -q -- '--unset-metadata gc.deferred_assignee' <<< "$A" \
  && ok "(ANCHOR) anchor deferred assignee cleared" || bad "(ANCHOR) deferred assignee (got: $A)"

# (ANCHORREL) our own claim is released, and in_progress is carried back to open
# — an in_progress bead with no assignee is a state nothing writes on purpose.
REL=$(grep -E "^bd update A-HELD .*--assignee" "$S1" || true)
grep -q -- '--assignee' <<< "$REL" \
  && ok "(ANCHORREL) anchor claim released" || bad "(ANCHORREL) anchor claim not released"
grep -q -- '--status=open' <<< "$REL" \
  && ok "(ANCHORREL) in_progress anchor reopened" || bad "(ANCHORREL) --status=open missing (got: $REL)"

# (AFFINE) every pin on the affine step.
SL=$(line_for "$S1" s-load)
grep -q -- '--unset-metadata gc.routed_to' <<< "$SL" \
  && ok "(AFFINE) affine step route cleared" || bad "(AFFINE) route (got: $SL)"
grep -q -- '--unset-metadata gc.session_affinity' <<< "$SL" \
  && ok "(AFFINE) affine step session_affinity cleared" || bad "(AFFINE) affinity (got: $SL)"

# (ORDER) TWO calls, route FIRST. A batched update is rolled back whole when the
# claim guard refuses the assignee, taking the route clear with it; and clearing
# the assignee first would leave the step open+unassigned+routed — the exact
# pool-offer shape this park exists to remove.
eq "$(grep -cE '^(bd|FORCE) update s-load( |$)' "$S1" || true)" "2" \
  "(ORDER) s-load written in exactly two calls"
R_AT=$(grep -n -E '^bd update s-load .*--unset-metadata gc.routed_to' "$S1" | head -n1 | cut -d: -f1)
A_AT=$(grep -n -E '^bd update s-load .*--assignee' "$S1" | head -n1 | cut -d: -f1)
if [ -n "$R_AT" ] && [ -n "$A_AT" ] && [ "$R_AT" -lt "$A_AT" ]; then
  ok "(ORDER) route cleared before the assignee"
else
  bad "(ORDER) route must precede assignee (route=$R_AT assignee=$A_AT)"
fi

# (POOL) an already-unassigned step gets no assignee call at all.
SI=$(line_for "$S1" s-impl)
grep -q -- '--unset-metadata gc.routed_to' <<< "$SI" \
  && ok "(POOL) unassigned+routed step de-routed" || bad "(POOL) route (got: $SI)"
grep -qE '^(bd|FORCE) update s-impl .*--assignee' "$S1" \
  && bad "(POOL) must not clear an assignee that was already empty" \
  || ok "(POOL) no spurious assignee clear"
grep -q 'gc.session_affinity' <<< "$SI" \
  && bad "(POOL) must not clear an affinity that was absent" \
  || ok "(POOL) no spurious affinity clear"

# (DEFERRED) a deferred twin is WITHHELD delivery that activation promotes into
# the live key. A step pinned only by one still has to be quiesced.
SD=$(line_for "$S1" s-defer)
grep -q -- '--unset-metadata gc.deferred_routed_to' <<< "$SD" \
  && ok "(DEFERRED) deferred-only step quiesced" || bad "(DEFERRED) deferred twin (got: $SD)"

# (FINAL) the control-dispatcher route is the molecule's only escape path.
eq "$(line_for "$S1" s-final)" "" \
  "(FINAL) workflow-finalize left untouched, execution route and all"

# (IDEM) nothing to clear -> not written.
eq "$(line_for "$S1" s-quiet)" "" "(IDEM) an already-quiet step is not re-updated"

# (FOREIGN) a step held by another session belongs to a LIVE molecule, and the
# hold must not write to it AT ALL — not the assignee, and not the delivery keys
# either. De-routing somebody else's step is the half that actually strands
# them: gc.routed_to and its siblings are how that step is re-delivered when
# their session drains, so stripping the route while politely leaving the
# assignee alone is the hazard, not a mitigation of it. s-them carries four
# delivery keys precisely so an ownership check that ran one call too late would
# show up here as unsets.
eq "$(line_for "$S1" s-them)" "" \
  "(FOREIGN) a foreign-held step is not written at all — delivery keys and all"
grep -qE '^(bd|FORCE) update s-them( |$)' "$S1" \
  && bad "(FOREIGN) must never write to another session's step" \
  || ok "(FOREIGN) another session's claim left alone"
grep -q 'not this session' "$S1.err" \
  && ok "(FOREIGN) the skip is reported" || bad "(FOREIGN) skip not reported"
grep -q 'BUG:' "$S1.err" \
  && bad "(FOREIGN) the loop reached clear_assignee with a foreign claim" \
  || ok "(FOREIGN) the skip happened before any write, not inside clear_assignee"
grep -q '1 step(s) left to another session' "$S1" \
  && ok "(FOREIGN) the summary counts it once, as foreign" \
  || bad "(FOREIGN) summary does not report one foreign step"
# Left alone on purpose, but the chain still has a live claim in it: that is a
# PARTIAL hold, and the caller is entitled to know.
eq "$RC" "1" "(FOREIGN) a partially-parked molecule exits non-zero"

# (REPOUR) a re-poured bead is tracked by one convoy per pour, each naming a
# different root. A walk that keeps only the first leaves the others routed and
# reports nothing.
grep -qE '^bd update s-two .*--unset-metadata gc.routed_to' "$S1" \
  && ok "(REPOUR) the second pour's molecule is quiesced too" \
  || bad "(REPOUR) second root never reached"

# (NOCLOSE) the footgun: closing load-context unblocks workspace-setup and walks
# the next polecat onto a branch that may already be under review — and a
# molecule with a closed step is PERMANENTLY unsweepable by the witness pass
# (specs/tk-8m8d4 guard 2).
grep -qE -- '--status=closed|--status closed' "$S1" \
  && bad "(NOCLOSE) no update may close a bead" || ok "(NOCLOSE) nothing was closed"
# Process substitution, not a pipe: `grep -q` exits at its first match and
# SIGPIPEs the writer, and pipefail promotes that 141 to the pipeline's status —
# so a match that SUCCEEDED takes the failure branch (doctor/check-pipefail-grep-q).
grep -qE -- '--status=closed|--status closed|bd close' < <(grep -vE '^[[:space:]]*#' "$SCRIPT") \
  && bad "(NOCLOSE) the source must contain no close path outside comments" \
  || ok "(NOCLOSE) static guard: no close path in the source"

# (SUMMARY) the past-tense record — what a hand-written park could never write,
# because it never knew what it had missed.
grep -q 'Molecule park (hold-dispatch.sh)' "$S1" \
  && ok "(SUMMARY) the park result is appended to the anchor" \
  || bad "(SUMMARY) no park summary appended"

# ============================ SCENARIO 2 ======================================

# (FALLBACK)/(SCOPE)/(ORPHAN) — a broken `tracks` edge must not silently miss the
# molecule. The reverse scan finds every live graph.v2 root; the anchor-match
# gate is what keeps that safe.
printf 'A-HELD|\n' > "$TMP/tracks"
run_hold s2 --bead A-HELD --reason "broken tracks edge"
S2="$TMP/updates.s2"
grep -q 'falling back to the reverse step scan' "$S2.err" \
  && ok "(FALLBACK) a missing input convoy falls back to the reverse scan" \
  || bad "(FALLBACK) no reverse-scan fallback"
grep -qE '^bd update s-load ' "$S2" \
  && ok "(FALLBACK) the molecule is still quiesced through the fallback" \
  || bad "(FALLBACK) fallback quiesced nothing"
eq "$(line_for "$S2" s-other)" "" \
  "(SCOPE) a molecule anchored on a DIFFERENT bead is left untouched"
eq "$(line_for "$S2" s-orphan)" "" \
  "(ORPHAN) a root with no resolvable convoy is skipped, not quiesced"
cat > "$TMP/tracks" <<'T'
A-HELD|convoy-HELD,convoy-TWO
A-THEIRS|
T

# (GATE) a refused route clear must SKIP the assignee clear. Clearing it anyway
# turns a momentary window into the step's resting state: open + unassigned +
# still routed, which is strictly worse than the husk we found.
export FAKE_FAIL='--unset-metadata gc.routed_to'
run_hold s3 --bead A-HELD --reason "gate"
unset FAKE_FAIL
S3="$TMP/updates.s3"
grep -qE '^(bd|FORCE) update s-load .*--assignee' "$S3" \
  && bad "(GATE) assignee cleared despite a refused route clear" \
  || ok "(GATE) a refused route clear skips the assignee clear"
grep -q 'assignee clear skipped' "$S3.err" \
  && ok "(GATE) the skip is reported" || bad "(GATE) skip not reported"
eq "$RC" "1" "(GATE) a failed clear exits non-zero"
# A REFUSED write and a step deliberately left to its owner are different
# outcomes and are counted in different columns — s-load/s-impl/s-two are refused
# here, s-them is foreign. Collapsing them would make the summary say a hold was
# botched when it was correctly partial, or the reverse.
grep -q '1 step(s) left to another session, 3 failed' "$S3" \
  && ok "(GATE) the summary counts refused writes apart from foreign steps" \
  || bad "(GATE) counts (got: $(grep -o 'quiesced across.*failed' "$S3" | head -n1))"

# (STEPSONLY) the duplicate-dispatch arm: the anchor belongs to a live owner, so
# only THIS molecule is dead.
run_hold s4 --bead A-HELD --reason "duplicate of a live owner" --steps-only
S4="$TMP/updates.s4"
grep -qE '^bd update A-HELD .*gc\.routed_to' "$S4" \
  && bad "(STEPSONLY) must not touch the anchor's delivery keys" \
  || ok "(STEPSONLY) the anchor's delivery keys are left to its owner"
grep -qE '^bd update A-HELD .*--assignee' "$S4" \
  && bad "(STEPSONLY) must not release the anchor's claim" \
  || ok "(STEPSONLY) the anchor's claim is left to its owner"
grep -qE '^bd update s-load .*--unset-metadata gc.routed_to' "$S4" \
  && ok "(STEPSONLY) the molecule is still quiesced" \
  || bad "(STEPSONLY) molecule not quiesced"
grep -q -- '--append-notes' "$S4" \
  && ok "(STEPSONLY) the hold is still recorded on the anchor" \
  || bad "(STEPSONLY) hold not recorded"

# (NOTMINE) parking a bead somebody else holds is not a hold; it is taking their
# claim. Refuse before writing anything.
run_hold s5 --bead A-THEIRS --reason "not mine"
eq "$RC" "2" "(NOTMINE) an anchor held by another session is refused"
eq "$(wc -l < "$TMP/updates.s5" | tr -d ' ')" "0" \
  "(NOTMINE) nothing was written"
grep -q -- '--steps-only' "$TMP/updates.s5.err" \
  && ok "(NOTMINE) the refusal names the flag that covers this case" \
  || bad "(NOTMINE) refusal should point at --steps-only"

# (UNREAD) an unreadable bead is not proof of anything.
run_hold s6 --bead A-UNREADABLE --reason "unreadable"
eq "$RC" "2" "(UNREAD) an unreadable anchor is refused"
eq "$(wc -l < "$TMP/updates.s6" | tr -d ' ')" "0" "(UNREAD) nothing was written"

# (ABSENT) `bd show` answers a bare OBJECT when no id resolves and an ARRAY when
# one does, exit 0 either way — so "no such bead" arrives as well-formed JSON,
# not as an error. It must be refused, and with its own sentence: an absent bead
# and an unreadable store need different fixes.
run_hold s11 --bead A-NOSUCHBEAD --reason "absent"
eq "$RC" "2" "(ABSENT) a bead that resolves to nothing is refused"
eq "$(wc -l < "$TMP/updates.s11" | tr -d ' ')" "0" "(ABSENT) nothing was written"
grep -q 'resolved to no issue' "$TMP/updates.s11.err" \
  && ok "(ABSENT) the refusal distinguishes absent from unreadable" \
  || bad "(ABSENT) refusal should name the absent case, not the unreadable one"

# (DRYRUN) resolve and report; write nothing.
run_hold s7 --bead A-HELD --reason "dry" --dry-run
eq "$(wc -l < "$TMP/updates.s7" | tr -d ' ')" "0" "(DRYRUN) --dry-run writes nothing"
grep -q 'DRY RUN' "$TMP/updates.s7.out" \
  && ok "(DRYRUN) the run says it wrote nothing" || bad "(DRYRUN) no dry-run notice"

# (ARGS) a parked bead with no recorded reason cannot be told from an abandoned
# one, so --reason is required; and a value-less flag must not eat the next one.
run_hold s8 --bead A-HELD
eq "$RC" "2" "(ARGS) --reason is required"
run_hold s9 --reason "no bead"
eq "$RC" "2" "(ARGS) --bead is required"
run_hold s10 --bead --reason "x"
eq "$RC" "2" "(ARGS) a value-less --bead does not swallow the next option"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
