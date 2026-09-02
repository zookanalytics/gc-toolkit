#!/usr/bin/env bash
# Hermetic tests for gc-helm.sh's takeaway verb (the board half lives in
# services/helm; the open verb is covered by gc-helm-open.test.sh). Runs the
# REAL script with a stubbed `gc` on PATH — no live city, Dolt, network, or
# sessions. Covered:
#   --release molecule quiescing: steps and the workflow root (tk-xypcy, tk-q5r65)
#   the split write, so a refused assignee clear cannot void the route pins
#   --waiting-on edges (tk-2plde)
#   the ≤140-codepoint length gate, shared by takeaway and demand
#   the demand verb's sibling shape and fail-closed edge
#   the retired board verb refuses and names helm-svc board
#   the dismiss verb: both halves of the operator's explicit clear
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- Fixture ------------------------------------------------------------------
# A-PARKED anchors the molecule root-PARKED (via convoy-PARKED). Steps:
#   s-load   affine  : assignee + routed + affinity  -> clear all three
#   s-impl   pool    : routed only                   -> clear routed only
#   s-final  finalize: control-dispatcher route      -> MUST stay routed
#   s-quiet  quiet   : no pins                       -> not re-updated
#   s-nonmol contract: another formula's graph.v2 step -> quiesced too (tk-q5r65)
#   s-noref  not-v2  : pinned but NO gc.step_ref     -> never a candidate
#   s-other  scope   : a different molecule's step   -> untouched
#   s-orphan failsafe: root with no convoy (anchor unresolvable) -> untouched
#   s-NOPIN  refused : the store rejects its pin write -> assignee clear skipped
# and the gc.kind=workflow ROOTS, which carry a pool route of their own:
#   root-PARKED      : this molecule's root          -> de-routed with its steps
#   root-OTHER       : another molecule's root       -> untouched
#   root-ORPHAN      : root with no convoy           -> skipped (fail closed)
cat > "$TMP/steps.json" <<'JSON'
[
  {"id":"s-load","assignee":"gc-toolkit__polecat-lx-dead","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-impl","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-final","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/core.control-dispatcher"}},
  {"id":"s-quiet","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.self-review","gc.root_bead_id":"root-PARKED"}},
  {"id":"s-nonmol","assignee":"someone","metadata":{"gc.step_ref":"mol-other-formula.step","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-noref","assignee":"someone-else","metadata":{"gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-other","assignee":"gc-toolkit__polecat-lx-live","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-OTHER","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-orphan","assignee":"gc-toolkit__polecat-lx-x","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-ORPHAN","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-NOPIN","assignee":"gc-toolkit__polecat-lx-gone","metadata":{"gc.step_ref":"mol-polecat-work.preflight-tests","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"root-PARKED","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-polecat-work","gc.input_convoy_id":"convoy-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"root-OTHER","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-polecat-work","gc.input_convoy_id":"convoy-OTHER","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"root-ORPHAN","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-polecat-work","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
]
JSON

# Roots: root_id|convoy_id   (root-ORPHAN deliberately absent -> no convoy)
cat > "$TMP/roots" <<'R'
root-PARKED|convoy-PARKED
root-OTHER|convoy-OTHER
R

# Convoys: convoy_id|anchor_id
cat > "$TMP/convoys" <<'C'
convoy-PARKED|A-PARKED
convoy-OTHER|A-OTHER
C

: > "$TMP/updates"     # one line per `gc bd update` invocation (the full argv)

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "rig list")
    # Two rigs. gc-toolkit's path has no .beads dir, so gc-helm issues
    # un-scoped bd calls for `tk-` ids; signal-loom's does, so an `sl-` id
    # exercises the rig pin.
    jq -n --arg sl "$FAKE_SL_PATH" \
       '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"},
               {name:"signal-loom", path:$sl, prefix:"sl"}]}' ;;
  "bd list")
    # Record the store this list actually read, so a lookup that searched the
    # caller's rig instead of the subject's is visible rather than silent.
    printf '%s\n' "${BEADS_DIR:-<unpinned>}" >> "$FAKE_LISTS"
    # A store that will not answer. Distinct from one that answers "none":
    # callers that read the two the same way act on an absence they never saw.
    # FAKE_LIST_RC is the non-answer that carries an exit code; FAKE_LIST_OUT
    # is the one that does not, and it is set to the payload to emit at rc 0.
    [ -n "${FAKE_LIST_RC:-}" ] && exit "$FAKE_LIST_RC"
    [ -n "${FAKE_LIST_OUT+x}" ] && { printf '%s' "$FAKE_LIST_OUT"; exit 0; }
    cat "$FAKE_STEPS_JSON" ;;
  "bd show")
    id="$3"
    # UNKNOWN- ids resolve to nothing, the way `bd show` answers for a bead
    # that is not there: a bare error OBJECT, never an array.
    case "$id" in UNKNOWN-*) printf '{"error":"no issues found"}\n'; exit 0 ;; esac
    # CLOSED- ids answer status=closed; everything else is open. dismiss says
    # different things about the two, and the DONE row only exists for one.
    st=open; case "$id" in CLOSED-*) st=closed ;; esac
    convoy=$(awk -F'|' -v r="$id" '$1==r{print $2; exit}' "$FAKE_ROOTS")
    # What gc.routed_to reads back as. FAKE_ROUTED holds it, so a test can
    # model the route LANDING and the route landing EMPTY (the silent drop a
    # multi-pair --set-metadata update can produce) with the same stub.
    routed="$(cat "${FAKE_ROUTED:-/dev/null}" 2>/dev/null || true)"
    if [ -n "$convoy" ]; then jq -n --arg i "$id" --arg s "$st" --arg c "$convoy" --arg rt "$routed" '[{id:$i,status:$s,metadata:{"gc.input_convoy_id":$c,"gc.routed_to":$rt}}]'
    else jq -n --arg i "$id" --arg s "$st" --arg rt "$routed" '[{id:$i,status:$s,metadata:{"gc.routed_to":$rt}}]'; fi ;;
  "bd close")
    printf '%s\n' "$*" >> "$FAKE_CLOSES"
    # Model bd's close-authority guard: a visit HELD by another session is
    # refused unless --force. A stub that closed it either way would leave the
    # escalation path untested behind a green suite.
    case "$3" in
      *HELD*) case "$*" in *--force*) ;; *) exit 1 ;; esac ;;
      *STUCK*) exit 1 ;;
    esac ;;
  "convoy status")
    anchor=$(awk -F'|' -v c="$3" '$1==c{print $2; exit}' "$FAKE_CONVOYS")
    if [ -n "$anchor" ]; then jq -n --arg a "$anchor" '{children:[{id:$a}]}'
    else printf '{"children":[]}\n'; fi ;;
  "bd update")
    printf '%s\n' "$*" >> "$FAKE_UPDATES"
    # A store that rejects the write. NOPIN stands for every reason the route
    # pins fail to land; the quiesce must not go on to unassign a bead it has
    # just failed to de-route.
    case "$3" in *NOPIN*) exit 1 ;; esac ;;
  "bd dep")
    printf '%s\n' "$*" >> "$FAKE_DEPS"
    # A blocker named NOPE stands for every edge that cannot be written.
    case "$*" in *NOPE*) exit 1 ;; esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_STEPS_JSON="$TMP/steps.json" FAKE_ROOTS="$TMP/roots" \
       FAKE_CONVOYS="$TMP/convoys" FAKE_UPDATES="$TMP/updates" \
       FAKE_DEPS="$TMP/deps" FAKE_CLOSES="$TMP/closes" FAKE_LISTS="$TMP/lists" \
       FAKE_ROUTED="$TMP/routed"
mkdir -p "$TMP/signal-loom/.beads"
export FAKE_SL_PATH="$TMP/signal-loom"
: > "$TMP/deps"; : > "$TMP/closes"; : > "$TMP/lists"; : > "$TMP/routed"
unset GC_HELM_FIXTURE || true
unset GC_SESSION_NAME GC_SESSION_ID GC_ALIAS || true

# --- Run: park A-PARKED with --release. ---------------------------------------
OUT="$(sh "$SCRIPT" takeaway A-PARKED "parked" --by proactive --release 2>"$TMP/err" || true)"
ERR="$(cat "$TMP/err")"
UP="$TMP/updates"

line_for() { grep -E "^bd update $1( |\$)" "$UP" || true; }

# (RELEASE) the parked anchor gets the full reopen/unassign/clear-route bundle.
A="$(line_for A-PARKED)"
[ -n "$A" ] && ok "(RELEASE) anchor A-PARKED was updated" || bad "(RELEASE) anchor never updated"
grep -q -- '--status=open' <<< "$A" \
  && ok "(RELEASE) anchor reopened (--status=open)" || bad "(RELEASE) anchor --status=open (got: $A)"
grep -q 'gc.proactive_reaction=1' <<< "$A" \
  && ok "(RELEASE) anchor marks the proactive reaction" || bad "(RELEASE) anchor proactive_reaction"
grep -q 'gc.routed_to=' <<< "$A" \
  && ok "(RELEASE) anchor route cleared" || bad "(RELEASE) anchor route cleared"
grep -q 'gc.takeaway_by=proactive' <<< "$A" \
  && ok "(RELEASE) anchor takeaway headline stamped" || bad "(RELEASE) anchor takeaway stamped"

# (AFFINE) affine step -> all three pins cleared.
SL="$(line_for s-load)"
if grep -q -- '--unset-metadata gc.routed_to' <<< "$SL" \
   && grep -q -- '--assignee' <<< "$SL" \
   && grep -q -- '--unset-metadata gc.session_affinity' <<< "$SL"; then
  ok "(AFFINE) affine step -> routed_to + assignee + session_affinity all cleared"
else
  bad "(AFFINE) affine step must clear all three pins (got: $SL)"
fi

# (ORDER) …across TWO writes, route first. beads refuses `--assignee ""` on an
# in_progress bead a live session holds, and refuses the whole update with it,
# so a single write loses the route pins on exactly the bead being re-offered.
# Route first and not last: the reverse leaves a routed+unassigned window,
# which is the pool-offer shape a fresh polecat races into.
eq "$(grep -cE '^bd update s-load( |$)' "$UP" || true)" "2" \
  "(ORDER) s-load's pins are written in two updates, not one"
ROUTE_N="$(grep -nE '^bd update s-load .*--unset-metadata gc.routed_to' "$UP" | head -n1 | cut -d: -f1)"
WHO_N="$(grep -nE '^bd update s-load .*--assignee' "$UP" | head -n1 | cut -d: -f1)"
if [ -n "$ROUTE_N" ] && [ -n "$WHO_N" ] && [ "$ROUTE_N" -lt "$WHO_N" ]; then
  ok "(ORDER) …the route clear goes first, so no window leaves it routed+unassigned"
else
  bad "(ORDER) the route clear must precede the assignee clear (route@${ROUTE_N:-none} assignee@${WHO_N:-none})"
fi
WHO_LINE="$(grep -E '^bd update s-load .*--assignee' "$UP" | head -n1)"
grep -q -- '--unset-metadata' <<< "$WHO_LINE" \
  && bad "(ORDER) the assignee clear still rides with the route pins ($WHO_LINE)" \
  || ok "(ORDER) …and rides alone, so a refusal of it cannot void them"

# (POOL) unassigned+routed step -> routed_to only.
SI="$(line_for s-impl)"
grep -q -- '--unset-metadata gc.routed_to' <<< "$SI" \
  && ok "(POOL) unassigned+routed step -> routed_to cleared" || bad "(POOL) routed_to cleared (got: $SI)"
grep -q -- '--assignee' <<< "$SI" \
  && bad "(POOL) must not clear an assignee that was already empty" || ok "(POOL) no spurious assignee clear"
grep -q 'gc.session_affinity' <<< "$SI" \
  && bad "(POOL) must not clear a session_affinity that was absent" || ok "(POOL) no spurious affinity clear"

# (FINAL) workflow-finalize keeps its control-dispatcher route.
[ -z "$(line_for s-final)" ] \
  && ok "(FINAL) workflow-finalize step left untouched (keeps its escape route)" \
  || bad "(FINAL) must NOT de-route workflow-finalize"

# (IDEM) already-quiet step is not re-updated.
[ -z "$(line_for s-quiet)" ] \
  && ok "(IDEM) already-quiet step skipped" || bad "(IDEM) quiet step must not be updated"

# (CONTRACT) a graph.v2 step from ANOTHER formula, under the parked root, is
# quiesced too — selection is by contract, not formula name (tk-q5r65).
SN="$(line_for s-nonmol)"
[ -n "$SN" ] \
  && ok "(CONTRACT) a non-mol-polecat-work graph.v2 step under the parked anchor IS quiesced" \
  || bad "(CONTRACT) graph.v2 step of another formula must be quiesced (got: none)"
grep -q -- '--unset-metadata gc.routed_to' <<< "$SN" \
  && ok "(CONTRACT) its route is cleared" || bad "(CONTRACT) route cleared (got: $SN)"
grep -q -- '--assignee' <<< "$SN" \
  && ok "(CONTRACT) its assignee is cleared" || bad "(CONTRACT) assignee cleared (got: $SN)"

# (NOTV2) no gc.step_ref -> never a candidate, even under the parked root.
[ -z "$(line_for s-noref)" ] \
  && ok "(NOTV2) bead with no gc.step_ref never quiesced (not a graph.v2 step)" \
  || bad "(NOTV2) a bead without gc.step_ref must never be touched"

# (SCOPE) a different molecule (anchor != parked bead) is left untouched.
[ -z "$(line_for s-other)" ] \
  && ok "(SCOPE) molecule whose anchor != parked bead untouched" || bad "(SCOPE) wrong molecule quiesced"

# (FAILCLOSE) a root whose anchor cannot be resolved is skipped.
[ -z "$(line_for s-orphan)" ] \
  && ok "(FAILCLOSE) unresolved-anchor root skipped (fail closed)" || bad "(FAILCLOSE) unresolved anchor quiesced"

# (ROOT) the gc.kind=workflow root is a second pool-routed door into the same
# molecule. A release that quiets every worker step and leaves the root routed
# keeps attracting polecat spawns onto the husk.
RP="$(line_for root-PARKED)"
grep -q -- '--unset-metadata gc.routed_to' <<< "$RP" \
  && ok "(ROOT) the workflow root is de-routed alongside its steps" \
  || bad "(ROOT) the workflow root kept its pool route (got: ${RP:-<none>})"
grep -q 'quiesced husk root root-PARKED' <<< "$OUT" \
  && ok "(ROOT) …and the run names it as a root, not a step" \
  || bad "(ROOT) the root is unreported (out: $OUT)"

# (ROOTSCOPE) the root walk inherits the step walk's scope and fail-closed guard.
[ -z "$(line_for root-OTHER)" ] \
  && ok "(ROOTSCOPE) a root whose anchor != the parked bead is untouched" \
  || bad "(ROOTSCOPE) another molecule's root was de-routed"
[ -z "$(line_for root-ORPHAN)" ] \
  && ok "(ROOTSCOPE) a root with no resolvable convoy is skipped (fail closed)" \
  || bad "(ROOTSCOPE) an unresolvable root was de-routed"

# (PINFAIL) the pin write is what makes the assignee clear safe. If it does not
# land, unassigning would leave the bead routed AND unassigned — the pool-offer
# shape the whole order exists to avoid — so the second write is skipped.
eq "$(grep -cE '^bd update s-NOPIN( |$)' "$UP" || true)" "1" \
  "(PINFAIL) a rejected pin write is not followed by an assignee clear"
grep -q -- '--assignee' <<< "$(line_for s-NOPIN)" \
  && bad "(PINFAIL) the bead was unassigned while still routed" \
  || ok "(PINFAIL) …so the bead is never left routed+unassigned"
grep -q 'could not quiesce step s-NOPIN' <<< "$ERR" \
  && ok "(PINFAIL) …and the failure is reported for the patrol to retry" \
  || bad "(PINFAIL) the failed quiesce is silent (stderr: $ERR)"

# (NOCLOSE dynamic) no STEP update ever closes a bead or rewrites its status.
STEP_UPDATES="$(grep -E '^bd update s-' "$UP" || true)"
if grep -qE -- '--status|--close|bd close' <<< "$STEP_UPDATES"; then
  bad "(NOCLOSE) a step update rewrote status or closed a bead (DANGER clause)"
else
  ok "(NOCLOSE) no step status rewrite / close (DANGER clause honored)"
fi

# (REPORT) the run announces the steps it quiesced.
grep -q 'quiesced husk step s-load' <<< "$OUT" \
  && ok "(REPORT) run reports the affine step it quiesced" || bad "(REPORT) run reports s-load (out: $OUT)"

# (NOCLOSE static) the quiesce block itself contains no close/status-write; the
# only legitimate `--status` is the bd list READ filter.
BLOCK="$(awk '/# >>> quiesce-release-molecule-steps/{f=1;next} /# <<< quiesce-release-molecule-steps/{f=0} f' "$SCRIPT")"
[ -n "$BLOCK" ] && ok "(MARKERS) quiesce block extracted between markers" || bad "(MARKERS) block extraction EMPTY — markers missing"
DANGER="$(printf '%s\n' "$BLOCK" | grep -v 'bd list --status' | grep -E 'bd close|--status|--close' || true)"
[ -z "$DANGER" ] \
  && ok "(NOCLOSE static) quiesce block writes no status and closes nothing (only the bd list read-filter uses --status)" \
  || bad "(NOCLOSE static) quiesce block contains a close/status-write: $DANGER"

if [ -n "$ERR" ]; then printf 'note: script stderr:\n%s\n' "$ERR" >&2; fi

# ── takeaway --waiting-on: the wait as a GRAPH EDGE (tk-2plde) ────────────────
# --waiting-on writes `subject depends on <work bead>` as a `blocks` edge
# beside the prose, which is what the board re-asks. Covered:
#   (EDGE)      one flag, one edge, depends-on direction
#   (EDGEMANY)  repeatable; --waiting-on=<id> parses too
#   (EDGESTAMP) the takeaway is still stamped in the same run
#   (EDGESELF)  a bead cannot wait on itself
#   (EDGEFAIL)  a rejected edge never loses the takeaway, and the verb exits 0
#   (EDGENONE)  no flag, no edges
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "routed — the fix is slung" --by converse \
   --waiting-on tk-blk1 --waiting-on=tk-blk2 >/dev/null 2>"$TMP/werr" || true
DEPS="$(cat "$TMP/deps")"

grep -qE '^bd dep add A-PARKED tk-blk1 -t blocks' <<< "$DEPS" \
  && ok "(EDGE) the wait is written as an edge: A-PARKED depends on tk-blk1" \
  || bad "(EDGE) no depends-on edge for tk-blk1 (got: ${DEPS:-<none>})"
grep -qE '^bd dep add A-PARKED tk-blk2 -t blocks' <<< "$DEPS" \
  && ok "(EDGEMANY) --waiting-on repeats, and the =VALUE form parses" \
  || bad "(EDGEMANY) tk-blk2 missing (got: ${DEPS:-<none>})"
eq "$(grep -c '^bd dep add' <<< "$DEPS")" "2" "(EDGEMANY) exactly one edge per flag, no duplicates"
grep -q -- '--set-metadata gc.takeaway=routed — the fix is slung' "$TMP/updates" \
  && ok "(EDGESTAMP) the takeaway itself is still stamped in the same run" \
  || bad "(EDGESTAMP) the stamp was lost: $(cat "$TMP/updates")"

# (EDGESELF) refuse a self-wait here, where the message can name the flag.
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "self" --waiting-on A-PARKED >/dev/null 2>"$TMP/werr" || true
eq "$(grep -c '^bd dep add' "$TMP/deps" || true)" "0" "(EDGESELF) a bead is never made to wait on itself"
grep -q 'bead itself' "$TMP/werr" \
  && ok "(EDGESELF) …and the refusal names the reason" \
  || bad "(EDGESELF) silent skip (stderr: $(cat "$TMP/werr"))"

# (EDGEFAIL) the takeaway is written FIRST; a failed edge warns, exit stays 0.
: > "$TMP/updates"; : > "$TMP/deps"
WRC=0
sh "$SCRIPT" takeaway A-PARKED "held for review" --waiting-on NOPE >/dev/null 2>"$TMP/werr" || WRC=$?
grep -q -- '--set-metadata gc.takeaway=held for review' "$TMP/updates" \
  && ok "(EDGEFAIL) a rejected edge does not cost the takeaway" \
  || bad "(EDGEFAIL) the stamp was lost when the edge failed: $(cat "$TMP/updates")"
grep -q 'could not wire' "$TMP/werr" \
  && ok "(EDGEFAIL) …and the failure is reported, not swallowed" \
  || bad "(EDGEFAIL) the failed edge was silent (stderr: $(cat "$TMP/werr"))"
eq "$WRC" "0" "(EDGEFAIL) …and the verb still succeeds: the takeaway landed"

# (EDGENONE) the flag is opt-in; existing callers are unchanged.
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "no edges here" >/dev/null 2>&1 || true
eq "$(grep -c '^bd dep' "$TMP/deps" || true)" "0" "(EDGENONE) no --waiting-on, no graph writes"
grep -q -- '--set-metadata gc.takeaway=no edges here' "$TMP/updates" \
  && ok "(EDGENONE) …and the plain stamp path is unchanged" \
  || bad "(EDGENONE) the plain path changed: $(cat "$TMP/updates")"

# ── takeaway --release --route: release the bead TO a pool ────────────────────
# A first reaction that concludes "this is work" hands the bead on instead of
# back. The route rides the release write, so the disposition lands whole or
# not at all. Covered:
#   (ROUTE)     the route replaces the empty clear, in the SAME single update
#   (ROUTECLR)  no --route still clears the route (the release is unchanged)
#   (ROUTEQUAL) a bare agent name is refused before anything is written
#   (ROUTEREL)  --route without --release is refused (the unreadable half-state)
#   (ROUTEOK)   a route that reads back correct is not re-written
#   (ROUTEFIX)  a route that reads back EMPTY is repaired and reported
#   (ROUTEDEAD) a repair that also misses is a verb failure, with its writes kept
POOL="gc-toolkit/gc-toolkit.polecat"
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
sh "$SCRIPT" takeaway A-PARKED "actionable — routed to the polecat pool" \
   --by proactive --release --route "$POOL" >/dev/null 2>"$TMP/rerr" || true
RLINE="$(grep -E "^bd update A-PARKED( |$)" "$TMP/updates" | head -n1)"
case "$RLINE" in
  *"--set-metadata gc.routed_to=$POOL"*) ok "(ROUTE) the release routes the bead to the pool" ;;
  *) bad "(ROUTE) no route stamp in the release write (got: ${RLINE:-<none>})" ;;
esac
case "$RLINE" in
  *"--status=open"*"--assignee="*) ok "(ROUTE) …in the same write that reopens and unassigns" ;;
  *) bad "(ROUTE) the release halves split off the route write: ${RLINE:-<none>}" ;;
esac
case "$RLINE" in
  *"--set-metadata gc.takeaway=actionable — routed to the polecat pool"*) ok "(ROUTE) …and the headline still rides it" ;;
  *) bad "(ROUTE) the headline was lost: ${RLINE:-<none>}" ;;
esac

# (ROUTECLR) the plain release is untouched: it still hands the bead back.
: > "$TMP/updates"; : > "$TMP/routed"
sh "$SCRIPT" takeaway A-PARKED "back to the human" --by proactive --release >/dev/null 2>&1 || true
grep -q -- '--set-metadata gc.routed_to= ' "$TMP/updates" \
  && ok "(ROUTECLR) no --route still clears the route" \
  || bad "(ROUTECLR) the plain release changed shape: $(cat "$TMP/updates")"

# (ROUTEQUAL) a bare name is matched against nothing and would sit forever.
: > "$TMP/updates"
QRC=0
sh "$SCRIPT" takeaway A-PARKED "bare" --release --route "gc-toolkit.polecat" >/dev/null 2>"$TMP/rerr" || QRC=$?
eq "$QRC" "2" "(ROUTEQUAL) a bare agent name is a usage error"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(ROUTEQUAL) …and nothing was written"
grep -q 'rig-qualified' "$TMP/rerr" \
  && ok "(ROUTEQUAL) …and the refusal names the cause" \
  || bad "(ROUTEQUAL) the refusal does not explain itself (stderr: $(cat "$TMP/rerr"))"

# (ROUTEREL) routed but still assigned to the reacting session reads as neither.
: > "$TMP/updates"
RRC=0
sh "$SCRIPT" takeaway A-PARKED "no release" --route "$POOL" >/dev/null 2>"$TMP/rerr" || RRC=$?
eq "$RRC" "2" "(ROUTEREL) --route without --release is a usage error"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(ROUTEREL) …and nothing was written"

# (ROUTEOK) a landed route is verified once and left alone.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
sh "$SCRIPT" takeaway A-PARKED "landed" --release --route "$POOL" >/dev/null 2>"$TMP/rerr" || true
eq "$(grep -cE "^bd update A-PARKED( |\$)" "$TMP/updates" || true)" "1" \
   "(ROUTEOK) a route that reads back correct is written once (the anchor, not its quiesced steps)"

# (ROUTEFIX) the silent drop: the stamp lands empty, so the bead is visible to
# no pool. The verb must notice and repair rather than report success.
: > "$TMP/updates"; : > "$TMP/routed"
FRC=0
sh "$SCRIPT" takeaway A-PARKED "dropped" --release --route "$POOL" >"$TMP/rout" 2>"$TMP/rerr" || FRC=$?
eq "$(grep -c -- "--set-metadata gc.routed_to=$POOL" "$TMP/updates" || true)" "2" \
   "(ROUTEFIX) an empty read-back is re-stamped"
grep -q 'read back as' "$TMP/rerr" \
  && ok "(ROUTEFIX) …and the miss is reported" \
  || bad "(ROUTEFIX) the dropped route was silent (stderr: $(cat "$TMP/rerr"))"
grep -q 'visible to no pool' "$TMP/rerr" \
  && ok "(ROUTEFIX) …and a repair that also misses says what it costs" \
  || bad "(ROUTEFIX) the persistent miss does not name its consequence (stderr: $(cat "$TMP/rerr"))"

# (ROUTEDEAD) --route promises the pool can see the bead. A caller that reads a
# zero exit as "released to that pool" would drain over a bead nothing can
# claim, so the persistent miss is a verb failure — with every write that DID
# land kept, and named, so a hand repair finishes it.
eq "$FRC" "4" "(ROUTEDEAD) a route that will not stamp is a verb runtime failure"
grep -q 'takeaway set on' "$TMP/rout" \
  && bad "(ROUTEDEAD) the verb reported success on an unrouted bead" \
  || ok "(ROUTEDEAD) …and it does not report the takeaway as set"
grep -q -- '--set-metadata gc.routed_to=' "$TMP/rerr" \
  && ok "(ROUTEDEAD) …the message carries the by-hand repair" \
  || bad "(ROUTEDEAD) no repair spelled out (stderr: $(cat "$TMP/rerr"))"
RD="$(grep -E "^bd update A-PARKED( |\$)" "$TMP/updates" | head -n1)"
case "$RD" in
  *"--status=open"*"--assignee="*) ok "(ROUTEDEAD) …the release it already wrote is kept, not rolled back" ;;
  *) bad "(ROUTEDEAD) the release write was lost: ${RD:-<none>}" ;;
esac
grep -qE "^bd update s-impl( |\$)" "$TMP/updates" \
  && ok "(ROUTEDEAD) …and the molecule steps the release quiesced stay quiesced" \
  || bad "(ROUTEDEAD) the failure exited before quiescing the released molecule"

# A route that lands is unaffected by any of that.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
GRC=0
sh "$SCRIPT" takeaway A-PARKED "landed clean" --release --route "$POOL" >"$TMP/rout" 2>/dev/null || GRC=$?
eq "$GRC" "0" "(ROUTEDEAD) a route that stamps still exits zero"
grep -q "released to $POOL" "$TMP/rout" \
  && ok "(ROUTEDEAD) …and says where the bead went" \
  || bad "(ROUTEDEAD) the success line lost the route (stdout: $(cat "$TMP/rout"))"

# ── takeaway length: the ≤140 cap, ENFORCED (tk-9tbbk.1) ─────────────────────
# REJECT over the cap, never truncate; measured in codepoints, after the
# whitespace collapse, before every side effect.
T140="$(printf 'x%.0s' {1..140})"
T141="$(printf 'x%.0s' {1..141})"
T140M="$(printf '—%.0s' {1..140})"   # 140 codepoints, 420 bytes

: > "$TMP/updates"; : > "$TMP/deps"
CRC=0
sh "$SCRIPT" takeaway A-PARKED "$T141" >/dev/null 2>"$TMP/cerr" || CRC=$?
CERR="$(cat "$TMP/cerr")"
eq "$CRC" "2" "(CAP) a 141-char takeaway is a usage error"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" \
   "(CAPNOWRITE) nothing is written — the bead keeps whatever it had"
grep -q '141 chars' <<< "$CERR" && grep -q 'cap is 140' <<< "$CERR" \
  && ok "(CAPMSG) the refusal names the measured length and the cap" \
  || bad "(CAPMSG) the refusal does not say what was wrong (stderr: ${CERR:-<none>})"

: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "$T140" >/dev/null 2>&1 || true
grep -q -- "--set-metadata gc.takeaway=$T140" "$TMP/updates" \
  && ok "(CAPOK) exactly 140 chars is accepted — the boundary is inclusive" \
  || bad "(CAPOK) a conforming 140-char headline was refused: $(cat "$TMP/updates")"

: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "$T140M" >/dev/null 2>"$TMP/cerr" || true
grep -q -- "--set-metadata gc.takeaway=$T140M" "$TMP/updates" \
  && ok "(CAPRUNE) 140 multi-byte chars (420 bytes) are accepted: the unit is codepoints" \
  || bad "(CAPRUNE) a 140-CHARACTER headline was refused for its byte count (stderr: $(cat "$TMP/cerr"))"

# (CAPWS) the collapse runs first, so what is measured is what gets stored.
: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "a$(printf ' %.0s' {1..200})b" >/dev/null 2>&1 || true
grep -q -- '--set-metadata gc.takeaway=a b' "$TMP/updates" \
  && ok "(CAPWS) the cap measures the collapsed text, not the raw argument" \
  || bad "(CAPWS) whitespace padding was counted against the cap: $(cat "$TMP/updates")"

# (CAPFIRST) a refusal must cost nothing: no park, no edge.
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "$T141" --release --waiting-on tk-blk1 >/dev/null 2>&1 || true
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(CAPFIRST) a refused takeaway does not park the bead"
eq "$(grep -c '^bd dep' "$TMP/deps" || true)"       "0" "(CAPFIRST) …and writes no waiting-on edge"

# (CAPNOTRIM static) the gate must REFUSE, not silently shorten.
GATE="$(awk '/# >>> takeaway-length-gate/{f=1;next} /# <<< takeaway-length-gate/{f=0} f' "$SCRIPT")"
[ -n "$GATE" ] && ok "(CAPNOTRIM) length-gate block extracted between markers" \
               || bad "(CAPNOTRIM) block extraction EMPTY — markers missing"
TRIM="$(printf '%s\n' "$GATE" | grep -vE '^\s*#' | grep -E 'text=|text:0:|cut -c' || true)"
[ -z "$TRIM" ] \
  && ok "(CAPNOTRIM) the gate never rewrites the text — it refuses it" \
  || bad "(CAPNOTRIM) the gate silently shortens the takeaway: $TRIM"

# ── the board verb is retired (moved to helm-svc board) ──────────────────────
BRC=0
BERRTXT="$(sh "$SCRIPT" board --json 2>&1 >/dev/null)" || BRC=$?
eq "$BRC" "2" "(NOBOARD) 'board' is a usage error now"
grep -q 'helm-svc board' <<< "$BERRTXT" \
  && ok "(NOBOARD) …and the refusal points at helm-svc board" \
  || bad "(NOBOARD) refusal must name the successor (got: $BERRTXT)"

# ── dismiss: the operator's one explicit "take this out of my view" ─────────
# Two surfaces hold a subject in view and neither lets go on its own: converse
# runs with no idle_timeout so a held visit keeps its pane, and a closed anchor
# keeps a DONE row on the board. dismiss is the single act that releases both,
# so each half is asserted separately — a verb that did one and silently
# skipped the other would look like it worked.

cat > "$TMP/visits.json" <<'JSON'
[
  {"id":"v-HELD","assignee":"gc-toolkit__converse-lx-1",
   "metadata":{"task_kind":"visit","gc.continuation_group":"A-PARKED"}},
  {"id":"v-EDGE","assignee":"","metadata":{"task_kind":"visit","gc.continuation_group":""},
   "dependencies":[{"type":"tracks","depends_on_id":"A-EDGE"}]},
  {"id":"v-OTHER","assignee":"","metadata":{"task_kind":"visit","gc.continuation_group":"A-OTHER"}},
  {"id":"n-NOTAVISIT","assignee":"","metadata":{"gc.continuation_group":"A-PARKED"}},
  {"id":"v-STUCK","assignee":"gc-toolkit__converse-lx-2",
   "metadata":{"task_kind":"visit","gc.continuation_group":"A-STUCK"}}
]
JSON
export FAKE_STEPS_JSON="$TMP/visits.json"

: > "$TMP/updates"; : > "$TMP/closes"
DOUT="$(sh "$SCRIPT" dismiss A-PARKED --reason "settled offline" 2>"$TMP/derr")"
DERR="$(cat "$TMP/derr")"

# (DISMISS-SITTING) the held visit is closed, and over its holder's claim: bd
# refuses a close by anyone but the assignee, and the assignee is the session
# the operator is dismissing. Assert on what the VERB reported, not on the
# stub's log — the log records the attempt, and a refused close is logged too.
CL="$(grep -E '^bd close v-HELD' "$TMP/closes" || true)"
if grep -q 'closed visit v-HELD' <<< "$DOUT"; then
    ok "(DISMISS-SITTING) the subject's open visit is closed"
else
    bad "(DISMISS-SITTING) no visit was closed (said: ${DOUT:-<nothing>} / ${DERR:-<nothing>})"
fi
eq "$(grep -c -- '--force' "$TMP/closes" || true)" "1" \
   "(DISMISS-FORCE) the holder's claim is overridden exactly once, after the plain close is refused"
if grep -q 'settled offline' <<< "$CL"; then
    ok "(DISMISS-WHY) the close reason carries the operator's words"
else
    bad "(DISMISS-WHY) reason not recorded (got: $CL)"
fi

# (DISMISS-ROW) …and the board row is cleared in the same act.
DU="$(grep -E '^bd update A-PARKED' "$TMP/updates" || true)"
if grep -q 'gc.dismissed_at=' <<< "$DU"; then
    ok "(DISMISS-ROW) the subject is stamped dismissed, so its DONE row leaves the board"
else
    bad "(DISMISS-ROW) gc.dismissed_at not stamped (got: $DU)"
fi
if grep -q -- '--append-notes' <<< "$DU"; then
    ok "(DISMISS-NOTES) the reason is appended, never replacing the dispatch note"
else
    bad "(DISMISS-NOTES) reason not appended (got: $DU)"
fi
if grep -q -- '--notes ' <<< "$DU"; then
    bad "(DISMISS-NOTES) a replacing --notes write erases the dispatch note"
else
    ok "(DISMISS-NOTES) no replacing --notes write"
fi

# (DISMISS-SCOPE) another subject's visit is not collateral.
if [ -z "$(grep -E '^bd close v-OTHER' "$TMP/closes" || true)" ]; then
    ok "(DISMISS-SCOPE) a visit on a different subject is untouched"
else
    bad "(DISMISS-SCOPE) dismissed a foreign subject's visit"
fi
if [ -z "$(grep -E '^bd close n-NOTAVISIT' "$TMP/closes" || true)" ]; then
    ok "(DISMISS-KIND) a non-visit bead in the group is never closed"
else
    bad "(DISMISS-KIND) closed a bead that is not a visit"
fi

# (DISMISS-EDGE) the subject is recorded twice — the group stamp and the tracks
# edge — and only the edge has proved reliable. Matching the stamp alone leaves
# the sitting the dismiss was asked to end still holding the pane.
: > "$TMP/updates"; : > "$TMP/closes"
sh "$SCRIPT" dismiss A-EDGE >/dev/null 2>&1 || true
if grep -qE '^bd close v-EDGE' "$TMP/closes"; then
    ok "(DISMISS-EDGE) a visit found only by its tracks edge is closed too"
else
    bad "(DISMISS-EDGE) an empty group stamp hid the visit (closes: $(cat "$TMP/closes"))"
fi

# (DISMISS-IDEM) a subject with no open visit is already dismissed and says so;
# the row half still runs, so a second dismiss is not a no-op that half-worked.
: > "$TMP/updates"; : > "$TMP/closes"
IOUT="$(sh "$SCRIPT" dismiss A-QUIET 2>&1 || true)"
eq "$(grep -c '^bd close' "$TMP/closes" || true)" "0" "(DISMISS-IDEM) nothing to close, nothing closed"
if grep -q 'no open visit' <<< "$IOUT"; then
    ok "(DISMISS-IDEM) …and the run says so rather than reporting a sitting it did not end"
else
    bad "(DISMISS-IDEM) silent about the absent sitting (got: $IOUT)"
fi
if grep -q 'gc.dismissed_at=' <<< "$(grep -E '^bd update A-QUIET' "$TMP/updates" || true)"; then
    ok "(DISMISS-IDEM) …and the row is still cleared"
else
    bad "(DISMISS-IDEM) the board half was skipped when there was no visit"
fi

# (DISMISS-STUCK) a visit that will not close must not take the row with it.
# The quiet direction is a pane that stays up; the loud one is a row that
# disappears while the sitting behind it is still live. The row is the
# operator's only evidence that the sitting exists, so the row half runs only
# when the visit half accounted for every sitting.
: > "$TMP/updates"; : > "$TMP/closes"
SRC=0
SOUT="$(sh "$SCRIPT" dismiss A-STUCK 2>&1)" || SRC=$?
if grep -q 'could not close visit v-STUCK' <<< "$SOUT"; then
    ok "(DISMISS-STUCK) an unclosable visit is reported, not swallowed"
else
    bad "(DISMISS-STUCK) the failure was silent (got: $SOUT)"
fi
if grep -q 'gc bd close v-STUCK --force' <<< "$SOUT"; then
    ok "(DISMISS-STUCK) …and the message names the command that finishes the job"
else
    bad "(DISMISS-STUCK) no recovery command offered"
fi
eq "$(grep -c '^bd update A-STUCK' "$TMP/updates" || true)" "0" \
   "(DISMISS-STUCK) …and the row is NOT retired over a sitting that is still up"
eq "$SRC" "4" "(DISMISS-STUCK) …and the run fails, so a caller cannot read it as a dismiss"
if grep -q 'was NOT dismissed' <<< "$SOUT"; then
    ok "(DISMISS-STUCK) …and it says the subject was not dismissed"
else
    bad "(DISMISS-STUCK) the refusal is not stated as one (got: $SOUT)"
fi

# (DISMISS-BLIND) a visit lookup that did not ANSWER is not a subject with no
# visit. Reading the two the same way stamps the marker over a sitting the verb
# never saw — the same lost row as DISMISS-STUCK, reached without a close.
: > "$TMP/updates"; : > "$TMP/closes"
BRC=0
BOUT="$(FAKE_LIST_RC=1 sh "$SCRIPT" dismiss A-PARKED 2>&1)" || BRC=$?
eq "$BRC" "4" "(DISMISS-BLIND) an unanswered visit lookup is a failed dismiss"
eq "$(grep -c '^bd update A-PARKED' "$TMP/updates" || true)" "0" \
   "(DISMISS-BLIND) …and nothing was stamped on a subject whose sittings were never read"
if grep -q 'could not read the visits' <<< "$BOUT"; then
    ok "(DISMISS-BLIND) …and the refusal names the read that failed"
else
    bad "(DISMISS-BLIND) unclear refusal (got: $BOUT)"
fi

# (DISMISS-BLIND) …and the non-answer that carries NO exit code is the same
# non-answer. Empty stdout and a bare `null` leave a `.[]?` derive exiting 0
# with no visits, which is indistinguishable from a subject that has none, so
# the shape is what gets checked rather than the status. An error object errors
# inside the derive and was already refused; it is pinned here beside the two
# that were not.
for blind_payload in '' '{"error":"no issues found"}' 'null'; do
    blind_label="${blind_payload:-<empty stdout>}"
    : > "$TMP/updates"; : > "$TMP/closes"
    ZRC=0
    ZOUT="$(FAKE_LIST_OUT="$blind_payload" sh "$SCRIPT" dismiss A-PARKED 2>&1)" || ZRC=$?
    eq "$ZRC" "4" "(DISMISS-BLIND) rc=0 with $blind_label is a failed dismiss"
    eq "$(grep -c '^bd update A-PARKED' "$TMP/updates" || true)" "0" \
       "(DISMISS-BLIND) …and $blind_label stamped nothing"
    if grep -q 'could not read the visits' <<< "$ZOUT"; then
        ok "(DISMISS-BLIND) …and the refusal for $blind_label names the read"
    else
        bad "(DISMISS-BLIND) silent on $blind_label (got: $ZOUT)"
    fi
done

# …and the gate must not swallow the honest answer: an EMPTY ARRAY is a subject
# with no visit, which dismisses. Without it the shape gate above trades a lost
# row for a verb that can never clear one.
: > "$TMP/updates"; : > "$TMP/closes"
ERC=0
EOUT="$(FAKE_LIST_OUT='[]' sh "$SCRIPT" dismiss A-PARKED 2>&1)" || ERC=$?
eq "$ERC" "0" "(DISMISS-BLIND) an empty visit array is an answer, not a blind read"
if grep -q 'gc.dismissed_at=' <<< "$(grep -E '^bd update A-PARKED' "$TMP/updates" || true)"; then
    ok "(DISMISS-BLIND) …and the row half still runs on it"
else
    bad "(DISMISS-BLIND) the shape gate refused a legitimate empty result (got: $EOUT)"
fi

# (DISMISS-VERIFY) an id nothing answers for writes NOTHING. A marker stamped on
# an unverified id is a row nobody can ever bring back.
: > "$TMP/updates"; : > "$TMP/closes"
VRC=0
VERR="$(sh "$SCRIPT" dismiss UNKNOWN-9 2>&1 >/dev/null)" || VRC=$?
eq "$VRC" "4" "(DISMISS-VERIFY) an unresolvable subject is a runtime failure"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(DISMISS-VERIFY) …and nothing was written"
if grep -q 'could not verify' <<< "$VERR"; then
    ok "(DISMISS-VERIFY) …and the refusal says why"
else
    bad "(DISMISS-VERIFY) unclear refusal (got: $VERR)"
fi

# (DISMISS-LIVE) dismissing a bead that is still OPEN ends its sitting but must
# not claim to have taken its row off the board: the row is live work, and a
# verb that said otherwise would teach the operator that dismiss hides things
# that still need them.
: > "$TMP/updates"; : > "$TMP/closes"
LOUT="$(sh "$SCRIPT" dismiss A-PARKED 2>&1 || true)"
if grep -q 'still open, so it keeps its live row' <<< "$LOUT"; then
    ok "(DISMISS-LIVE) an open subject is told it keeps its live row"
else
    bad "(DISMISS-LIVE) an open subject was told its row left the board (got: $LOUT)"
fi
: > "$TMP/updates"; : > "$TMP/closes"
COUT="$(sh "$SCRIPT" dismiss CLOSED-7 2>&1 || true)"
if grep -q "leaves the board's DONE band" <<< "$COUT"; then
    ok "(DISMISS-LIVE) …and a closed subject is told its DONE row leaves"
else
    bad "(DISMISS-LIVE) a closed subject got the live-row wording (got: $COUT)"
fi

# (DISMISS-RIG) a subject in ANOTHER rig: the visit lookup must read that rig's
# ledger. Unpinned it reads the caller's, finds nothing, and reports a sitting
# ended while its pane is still up.
: > "$TMP/updates"; : > "$TMP/closes"; : > "$TMP/lists"
sh "$SCRIPT" dismiss sl-9001 >/dev/null 2>&1 || true
if grep -qF "$TMP/signal-loom/.beads" "$TMP/lists"; then
    ok "(DISMISS-RIG) the visit lookup is pinned at the subject's rig"
else
    bad "(DISMISS-RIG) the visit lookup ran against the wrong store" \
        "read: $(cat "$TMP/lists")"
fi

# (DISMISS-ARGS) the fail-closed arg checks, matching the other verbs.
ARC=0; sh "$SCRIPT" dismiss >/dev/null 2>&1 || ARC=$?
eq "$ARC" "2" "(DISMISS-ARGS) a missing bead-id is a usage error"
ARC=0; sh "$SCRIPT" dismiss A-PARKED --nope >/dev/null 2>&1 || ARC=$?
eq "$ARC" "2" "(DISMISS-ARGS) an unknown flag is a usage error"

export FAKE_STEPS_JSON="$TMP/steps.json"

# ── The releasing session's own step survives the release ────────────────────
# mol-first-reaction's terminal step disposes by calling `takeaway --release` on
# the bead its own molecule is anchored to, and then has to close its own step
# bead. step-close.sh resolves that bead by (assignee, gc.step_ref), so a
# quiesce that clears the live step's assignee lands the disposition and strands
# the molecule: the step stays open and is re-offered forever. This section runs
# the real release and then the real step-close.sh against ONE mutating store —
# a logging-only stub cannot show the second command failing on what the first
# wrote.
LIVE="$TMP/live"; mkdir -p "$LIVE/bin"
export LIVE_STORE="$LIVE/store.json" LIVE_CONVOYS="$LIVE/convoys" LIVE_LOG="$LIVE/log"
SESSION="gc-toolkit--gc-toolkit__proactive-1-pool"
POOL="gc-toolkit/gc-toolkit.polecat"

# A-LIVE is the anchor; root-LIVE its molecule root, pool-routed in its own
# right. L-live is the terminal step this session is executing the release
# FROM; L-peer is a sibling step left pinned to a session that is gone, which
# is what the quiesce exists for; L-held is the hard case — in_progress under
# a DIFFERENT live session, so beads refuses to clear its assignee.
cat > "$LIVE_STORE" <<JSON
[
 {"id":"A-LIVE","status":"in_progress","assignee":"$SESSION","metadata":{}},
 {"id":"root-LIVE","status":"in_progress","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-first-reaction","gc.input_convoy_id":"convoy-LIVE","gc.routed_to":"gc-toolkit/gc-toolkit.proactive"}},
 {"id":"L-live","status":"in_progress","assignee":"$SESSION","metadata":{"gc.step_ref":"mol-first-reaction.advance-and-drain","gc.root_bead_id":"root-LIVE","gc.routed_to":"gc-toolkit/gc-toolkit.proactive","gc.session_affinity":"require"}},
 {"id":"L-peer","status":"open","assignee":"gc-toolkit__polecat-lx-gone","metadata":{"gc.step_ref":"mol-first-reaction.load-bead","gc.root_bead_id":"root-LIVE","gc.routed_to":"gc-toolkit/gc-toolkit.proactive","gc.session_affinity":"require"}},
 {"id":"L-held","status":"in_progress","assignee":"gc-toolkit__polecat-lx-other","metadata":{"gc.step_ref":"mol-first-reaction.decide","gc.root_bead_id":"root-LIVE","gc.routed_to":"gc-toolkit/gc-toolkit.proactive","gc.session_affinity":"require"}}
]
JSON
printf 'convoy-LIVE|A-LIVE\n' > "$LIVE_CONVOYS"
: > "$LIVE_LOG"

cat > "$LIVE/bin/gc" <<'GCL'
#!/usr/bin/env bash
# A MUTATING store: `bd update` rewrites LIVE_STORE, so a later list/show
# answers the state the earlier write left behind.
sw() { jq "$@" "$LIVE_STORE" > "$LIVE_STORE.n" && mv "$LIVE_STORE.n" "$LIVE_STORE"; }
case "$1 ${2:-}" in
  "rig list") printf '{"rigs":[{"name":"gc-toolkit","path":"/nonexistent-rig","prefix":"tk"}]}\n' ;;
  "bd list")
    st=""; who=""; seen_who=0
    for a in "$@"; do
      case "$a" in
        --status=*)   st="${a#--status=}" ;;
        --assignee=*) who="${a#--assignee=}"; seen_who=1 ;;
      esac
    done
    jq --arg st "$st" --arg who "$who" --argjson sw "$seen_who" '
      [ .[] | . as $b
        | select($st == "" or (($st | split(",")) | index($b.status // "")) != null)
        | select($sw == 0 or (($b.assignee // "") == $who)) ]' "$LIVE_STORE" ;;
  "bd show")
    row=$(jq -c --arg i "$3" '[ .[] | select(.id == $i) ]' "$LIVE_STORE")
    [ "$row" != "[]" ] && printf '%s\n' "$row" || printf '[{"id":"%s","status":"open","metadata":{}}]\n' "$3" ;;
  "convoy status")
    a=$(awk -F'|' -v c="$3" '$1==c{print $2; exit}' "$LIVE_CONVOYS")
    [ -n "$a" ] && jq -n --arg a "$a" '{children:[{id:$a}]}' || printf '{"children":[]}\n' ;;
  "bd update")
    printf 'update %s\n' "$*" >> "$LIVE_LOG"
    id="$3"; shift 3
    # beads refuses to clear the assignee of an in_progress bead ANOTHER
    # session holds, and refuses the whole update along with it. Checked
    # before anything is applied, so the refusal is atomic here too: a stub
    # that let the other keys through would hide the loss this split prevents.
    for a in "$@"; do
      case "$a" in
        --assignee|--assignee=*)
          st=$(jq -r --arg i "$id" '.[] | select(.id==$i) | .status // ""' "$LIVE_STORE")
          who=$(jq -r --arg i "$id" '.[] | select(.id==$i) | .assignee // ""' "$LIVE_STORE")
          if [ "$st" = "in_progress" ] && [ -n "$who" ] && [ "$who" != "${GC_SESSION_NAME:-}" ]; then
            printf 'refused %s (held by %s)\n' "$id" "$who" >> "$LIVE_LOG"
            exit 1
          fi ;;
      esac
    done
    while [ $# -gt 0 ]; do
      case "$1" in
        --db)             shift 2 ;;
        --assignee=*)     sw --arg i "$id" --arg v "${1#--assignee=}" 'map(if .id==$i then .assignee=$v else . end)'; shift ;;
        --assignee)       sw --arg i "$id" --arg v "${2:-}" 'map(if .id==$i then .assignee=$v else . end)'; shift 2 ;;
        --status=*)       sw --arg i "$id" --arg v "${1#--status=}" 'map(if .id==$i then .status=$v else . end)'; shift ;;
        --set-metadata)   sw --arg i "$id" --arg k "${2%%=*}" --arg v "${2#*=}" 'map(if .id==$i then .metadata[$k]=$v else . end)'; shift 2 ;;
        --unset-metadata) sw --arg i "$id" --arg k "$2" 'map(if .id==$i then (.metadata |= del(.[$k])) else . end)'; shift 2 ;;
        *)                shift ;;
      esac
    done ;;
  "bd dep") printf 'dep %s\n' "$*" >> "$LIVE_LOG" ;;
esac
exit 0
GCL
chmod +x "$LIVE/bin/gc"

field() { jq -r --arg i "$1" --arg k "$2" '.[] | select(.id==$i) | (if $k=="status" then .status elif $k=="assignee" then (.assignee // "") else (.metadata[$k] // "") end)' "$LIVE_STORE"; }

SAVED_PATH="$PATH"; PATH="$LIVE/bin:$PATH"
RELOUT="$(GC_SESSION_NAME="$SESSION" GC_SESSION_ID="lx-live1" \
  sh "$SCRIPT" takeaway A-LIVE "released to the impl pool" --by proactive --release --route "$POOL" 2>&1 || true)"

eq "$(field L-live assignee)" "$SESSION" \
   "(LIVESTEP) the step the release runs FROM keeps its assignee"
eq "$(field L-live gc.routed_to)" "gc-toolkit/gc-toolkit.proactive" \
   "(LIVESTEP) …and its route"
eq "$(field L-live gc.session_affinity)" "require" \
   "(LIVESTEP) …and its session affinity"
grep -q 'kept live step L-live' <<< "$RELOUT" \
  && ok "(LIVESTEP) …and the run says which step it kept" \
  || bad "(LIVESTEP) the kept step is unreported (out: $RELOUT)"

# The guard is narrow: a sibling pinned to a session that is GONE is exactly the
# husk the quiesce exists for, and it must still be cleared.
eq "$(field L-peer assignee)" "" \
   "(LIVESTEP) a peer session's step under the same anchor is still quiesced"
eq "$(field L-peer gc.routed_to)" "" \
   "(LIVESTEP) …and de-routed"

# The bug the split exists for. The refused `--assignee ""` used to take the
# route pins down with it, on precisely the bead being re-offered — and the
# patrol retry cannot succeed either while the holder is alive.
eq "$(field L-held gc.routed_to)" "" \
   "(HELDSTEP) a step a live session holds is de-routed even though its assignee clear is refused"
eq "$(field L-held gc.session_affinity)" "" \
   "(HELDSTEP) …and loses its session affinity in the same write"
eq "$(field L-held assignee)" "gc-toolkit__polecat-lx-other" \
   "(HELDSTEP) …while the assignee stays with the session that holds it"
grep -q 'de-pinned husk step L-held' <<< "$RELOUT" \
  && ok "(HELDSTEP) …and the run says the assignee was left behind" \
  || bad "(HELDSTEP) the partial quiesce is unreported (out: $RELOUT)"

# The root is the other door: a molecule whose worker steps are all quiet still
# draws spawns while its gc.kind=workflow root keeps a pool route.
eq "$(field root-LIVE gc.routed_to)" "" \
   "(LIVEROOT) the workflow root is de-routed too, so no door is left open"

# The disposition itself still lands whole.
eq "$(field A-LIVE status)" "open"  "(LIVESTEP) the anchor is released"
eq "$(field A-LIVE assignee)" ""    "(LIVESTEP) …and unassigned"
eq "$(field A-LIVE gc.routed_to)" "$POOL" "(LIVESTEP) …and routed to the pool"

# The proof the guard exists for: the terminal step is still CLOSABLE after the
# release, by the same resolution the formula's terminal block uses.
SCRC=0
SCOUT="$(GC_SESSION_NAME="$SESSION" GC_SESSION_ID="lx-live1" \
  bash "$HERE/step-close.sh" --step mol-first-reaction.advance-and-drain --outcome pass 2>&1)" || SCRC=$?
eq "$SCRC" "0" "(LIVESTEP) step-close.sh still resolves this session's step after the release"
eq "$(field L-live status)" "closed" \
   "(LIVESTEP) …and closes it, so the molecule advances instead of re-offering"
[ "$SCRC" -eq 0 ] || printf 'note: step-close output:\n%s\n' "$SCOUT" >&2
PATH="$SAVED_PATH"

# ── demand: what a person owes, as a bead the work is blocked by ──────────────
# The verb replaces parking a subject on prose. Its whole value is the EDGE, so
# every assertion here is about the shape that makes the edge possible (a
# SIBLING demand, never a child) and about failing closed when the edge does
# not land — a demand with no edge leaves the work reading ready while a person
# owes an answer, which is the state the verb exists to remove.
#
# Its own stub: the release-quiesce fixture above answers `bd list` with step
# beads, and demand reads `bd list` for an existing open demand.
mkdir -p "$TMP/bin2"
cat > "$TMP/bin2/gc" <<'GC2'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$D_LOG"
case "$1 ${2:-}" in
  "rig list")
    jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd show")
    id="$3"
    if grep -qx "$id" "$D_MISSING" 2>/dev/null; then printf '{"error":"no issues found"}\n'; exit 0; fi
    p="$(awk -F'|' -v b="$id" '$1==b{print $2; exit}' "$D_PARENTS")"
    blk="$(awk -v b="$id" '$1=="bd" && $2=="dep" && $3=="add" && $4==b {print $5}' "$D_LOG" | jq -R . | jq -sc .)"
    jq -n --arg id "$id" --arg p "$p" --argjson blk "$blk" \
      '[{id: $id,
         dependencies: ((if $p != "" then [{id: $p, dependency_type: "parent-child"}] else [] end)
                        + ($blk | map({id: ., dependency_type: "blocks"})))}]' ;;
  "bd list")  cat "$D_LIST" ;;
  "bd create") printf '{"id":"%s"}\n' "$(cat "$D_NEXTID")" ;;
  "bd update") : ;;
  "bd dep")
    # NOEDGE in any id of the call stands for an edge that cannot be written:
    # the call fails AND nothing is recorded, so the read-back sees no edge.
    # On a demand id that is every edge; on a TARGET id it is that one edge,
    # while the rest of the call's edges land.
    case "$*" in *NOEDGE*) sed -i '$d' "$D_LOG"; exit 1 ;; esac ;;
esac
exit 0
GC2
chmod +x "$TMP/bin2/gc"

export D_LOG="$TMP/dlog" D_PARENTS="$TMP/dparents" D_LIST="$TMP/dlist" \
       D_NEXTID="$TMP/dnextid" D_MISSING="$TMP/dmissing"
printf 'tk-kid|tk-mum\n' > "$D_PARENTS"   # tk-kid has a parent; tk-solo has none
printf 'tk-gone\n'        > "$D_MISSING"
printf '[]\n'             > "$D_LIST"
printf 'tk-dem1\n'        > "$D_NEXTID"

# demand_run <gated> [args...] — fresh log, returns the verb's exit status in DRC
DRC=0
demand_run() {
    : > "$D_LOG"; : > "$TMP/derr"
    DRC=0
    DOUT="$(PATH="$TMP/bin2:$PATH" sh "$SCRIPT" demand "$@" 2>"$TMP/derr")" || DRC=$?
    DERR="$(cat "$TMP/derr")"
}
# d_create — the argv of the `bd create` call, or empty
d_create() { grep -E '^bd create ' "$D_LOG" || true; }
d_update() { grep -E '^bd update ' "$D_LOG" || true; }
d_deps()   { grep -E '^bd dep add ' "$D_LOG" || true; }

# (SIBLING) the demand inherits the GATED bead's parent — never becomes its
# child, which beads would refuse to let it block.
demand_run tk-kid "operator: pick the storage backend" --by converse
eq "$DRC" "0" "(SIBLING) a demand on a parented bead succeeds"
grep -q -- '--parent tk-mum' <<< "$(d_create)" \
  && ok "(SIBLING) the demand is filed under the gated bead's own parent" \
  || bad "(SIBLING) no --parent tk-mum in: $(d_create)"
grep -q -- '--parent tk-kid' <<< "$(d_create)" \
  && bad "(SIBLING) the demand was filed as a CHILD of the bead it gates" \
  || ok "(SIBLING) …and not as a child of the bead it gates"
grep -q -- '-t decision' <<< "$(d_create)" \
  && ok "(SIBLING) a ruling is issue_type=decision (a typed board anchor)" \
  || bad "(SIBLING) not -t decision: $(d_create)"
grep -q -- '--title operator: pick the storage backend' <<< "$(d_create)" \
  && ok "(SIBLING) the authored headline is the demand's TITLE" \
  || bad "(SIBLING) headline is not the title: $(d_create)"

# (EDGE) the wait is an edge on the GATED bead: "tk-kid is blocked by tk-dem1".
eq "$(d_deps)" "bd dep add tk-kid tk-dem1 -t blocks" \
   "(EDGE) the gated bead is blocked by the demand, in that direction"

# (STAMP) the demand carries what the board and the next sitting read.
U="$(d_update)"
grep -q 'gc.demand_for=tk-kid' <<< "$U" \
  && ok "(STAMP) the demand records what it gates" || bad "(STAMP) gc.demand_for missing: $U"
grep -q 'gc.routed_to=human' <<< "$U" \
  && ok "(STAMP) …and that a person owes it" || bad "(STAMP) gc.routed_to=human missing: $U"
grep -q 'gc.takeaway=operator: pick the storage backend' <<< "$U" \
  && ok "(STAMP) …and carries the headline as its own takeaway" || bad "(STAMP) gc.takeaway missing: $U"
grep -q 'gc.takeaway_by=converse' <<< "$U" \
  && ok "(STAMP) …attributed to the caller" || bad "(STAMP) gc.takeaway_by missing: $U"

# (OUT) the id is readable off stdout — the caller closes this bead later.
eq "$(awk '/^demand /{print $2; exit}' <<< "$DOUT")" "tk-dem1" \
   "(OUT) the demand id is the second field of the 'demand …' line"

# (SIBLINGNONE) a parentless gated bead gets a parentless demand: still a
# sibling, and still able to carry the edge.
demand_run tk-solo "operator: ratify the cutover" --by converse
eq "$DRC" "0" "(SIBLINGNONE) a demand on a parentless bead succeeds"
grep -q -- '--parent' <<< "$(d_create)" \
  && bad "(SIBLINGNONE) invented a parent: $(d_create)" \
  || ok "(SIBLINGNONE) no parent is invented for a parentless subject"

# (KIND) work only a person can do is a task assigned to that person.
demand_run tk-solo "sign the vendor contract" --kind task --assignee zook
eq "$DRC" "0" "(KIND) --kind task is accepted"
grep -q -- '-t task' <<< "$(d_create)" \
  && ok "(KIND) …filed as a task" || bad "(KIND) not -t task: $(d_create)"
grep -q -- '--assignee zook' <<< "$(d_update)" \
  && ok "(KIND) …assigned to the person who owes it" || bad "(KIND) no assignee: $(d_update)"

# (KINDBAD) any other kind is a usage error, and files nothing.
demand_run tk-solo "whatever" --kind epic
eq "$DRC" "2" "(KINDBAD) an unsupported --kind is a usage error"
eq "$(d_create)" "" "(KINDBAD) …and nothing is filed"

# (CAP) the ≤140 gate is SHARED with takeaway: the title is the same headline.
demand_run tk-solo "$T141"
eq "$DRC" "2" "(CAP) a 141-char demand headline is a usage error"
eq "$(d_create)" "" "(CAP) …and nothing is filed"
grep -q 'cap is 140' <<< "$DERR" \
  && ok "(CAP) …and the refusal names the cap" || bad "(CAP) refusal is silent: $DERR"
demand_run tk-solo "$T140"
eq "$DRC" "0" "(CAP) exactly 140 chars is accepted — one boundary, both verbs"

# (RESOLVE) an unresolvable gated bead files nothing: a demand nothing gates
# still reads on the board as a question someone owes an answer to.
demand_run tk-gone "operator: decide"
eq "$DRC" "4" "(RESOLVE) an unresolvable gated bead is a runtime failure"
eq "$(d_create)" "" "(RESOLVE) …and no demand is filed"
grep -q 'does not resolve' <<< "$DERR" \
  && ok "(RESOLVE) …and the refusal says why" || bad "(RESOLVE) refusal is silent: $DERR"

# (IDEM) one open demand per gated bead. A resumed sitting re-states the same
# question; a second bead would give one wait two blockers.
printf '[{"id":"tk-old1","metadata":{"gc.demand_for":"tk-kid"}}]\n' > "$D_LIST"
demand_run tk-kid "operator: pick the storage backend (still)" --by converse
eq "$DRC" "0" "(IDEM) a re-stated demand succeeds"
eq "$(d_create)" "" "(IDEM) …without filing a second bead"
grep -q '^bd update tk-old1 ' <<< "$(d_update)" \
  && ok "(IDEM) …refreshing the open one instead" || bad "(IDEM) the open demand was not refreshed: $(d_update)"
grep -q -- '--title operator: pick the storage backend (still)' <<< "$(d_update)" \
  && ok "(IDEM) …with the re-stated headline as its title" || bad "(IDEM) title not refreshed: $(d_update)"
grep -q 'gc.takeaway_at=' <<< "$(d_update)" \
  && ok "(IDEM) …and a fresh takeaway_at, which is what earns the next visit" \
  || bad "(IDEM) takeaway_at not refreshed: $(d_update)"
eq "$(awk '/^demand /{print $2; exit}' <<< "$DOUT")" "tk-old1" "(IDEM) …and it names the bead that already existed"
printf '[]\n' > "$D_LIST"

# (FAILCLOSED) the edge IS the record here. Unlike takeaway --waiting-on, a
# demand whose edge did not land must not report success — the work would read
# ready while a person still owes an answer.
printf 'tk-NOEDGE9\n' > "$D_NEXTID"
demand_run tk-kid "operator: decide the cutover order"
eq "$DRC" "4" "(FAILCLOSED) an edge that did not land is a runtime failure"
grep -q 'is NOT blocked by' <<< "$DERR" \
  && ok "(FAILCLOSED) …and the message says the work still reads ready" \
  || bad "(FAILCLOSED) the failure did not name the state: $DERR"
grep -q 'gc bd dep add tk-kid tk-NOEDGE9 -t blocks' <<< "$DERR" \
  && ok "(FAILCLOSED) …and hands over the exact repair" \
  || bad "(FAILCLOSED) no repair command offered: $DERR"

# (PREFIX) a create routed to another rig's ledger returns an id, not an error,
# and that id can never carry an edge to the gated bead.
printf 'sl-wrong1\n' > "$D_NEXTID"
demand_run tk-kid "operator: decide"
eq "$DRC" "4" "(PREFIX) a demand filed in the wrong ledger is a runtime failure"
grep -q "not 'tk'" <<< "$DERR" \
  && ok "(PREFIX) …and the message names the prefix that was expected" \
  || bad "(PREFIX) prefix mismatch not reported: $DERR"
printf 'tk-dem1\n' > "$D_NEXTID"

# (ALSO) --also-blocks gates further work on the same demand.
demand_run tk-kid "operator: pick the backend" --also-blocks tk-sib1 --also-blocks=tk-sib2
eq "$DRC" "0" "(ALSO) --also-blocks is accepted in both forms"
eq "$(grep -c '^bd dep add ' "$D_LOG")" "3" "(ALSO) one edge for the gated bead and one per --also-blocks"
grep -q '^bd dep add tk-sib2 tk-dem1 -t blocks$' "$D_LOG" \
  && ok "(ALSO) …each in the depends-on direction" || bad "(ALSO) tk-sib2 edge missing: $(d_deps)"

# (ALSOCLOSED) every requested blocker fails closed, not just the primary one.
# The gated bead's edge lands here and one --also-blocks target's does not:
# reporting success would leave that target reading ready against a demand it
# was named to wait on, which is the same state (FAILCLOSED) refuses.
demand_run tk-kid "operator: pick the backend" --also-blocks tk-NOEDGE1 --also-blocks tk-sib2
eq "$DRC" "4" "(ALSOCLOSED) an --also-blocks edge that did not land is a runtime failure"
grep -q 'tk-NOEDGE1 is NOT blocked by tk-dem1' <<< "$DERR" \
  && ok "(ALSOCLOSED) …and the failure names the target left unwired" \
  || bad "(ALSOCLOSED) the unwired target was not named: $DERR"
grep -q 'gc bd dep add tk-NOEDGE1 tk-dem1 -t blocks' <<< "$DERR" \
  && ok "(ALSOCLOSED) …with the repair for that target, not for the gated bead" \
  || bad "(ALSOCLOSED) no repair command for the unwired target: $DERR"
grep -q 'tk-kid is NOT blocked by' <<< "$DERR" \
  && bad "(ALSOCLOSED) the primary edge landed but was reported unwired: $DERR" \
  || ok "(ALSOCLOSED) …and the primary edge, which did land, is not accused"
grep -q '^demand tk-dem1 blocks tk-kid' <<< "$DOUT" \
  && bad "(ALSOCLOSED) success was printed while a requested edge was missing: $DOUT" \
  || ok "(ALSOCLOSED) …and no success line is printed"

echo ""
echo "gc-helm takeaway + demand + dismiss (release quiesce, waiting-on edges, length gate, demand shape): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
