#!/usr/bin/env bash
# Hermetic tests for gc-helm.sh's takeaway verb (the board half lives in
# services/helm; the open verb is covered by gc-helm-open.test.sh). Runs the
# REAL script with a stubbed `gc` on PATH — no live city, Dolt, network, or
# sessions. Covered:
#   --release molecule-step quiescing (tk-xypcy, tk-q5r65)
#   --waiting-on edges (tk-2plde)
#   the ≤140-codepoint length gate (tk-9tbbk.1)
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
cat > "$TMP/steps.json" <<'JSON'
[
  {"id":"s-load","assignee":"gc-toolkit__polecat-lx-dead","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-impl","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-final","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/core.control-dispatcher"}},
  {"id":"s-quiet","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.self-review","gc.root_bead_id":"root-PARKED"}},
  {"id":"s-nonmol","assignee":"someone","metadata":{"gc.step_ref":"mol-other-formula.step","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-noref","assignee":"someone-else","metadata":{"gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-other","assignee":"gc-toolkit__polecat-lx-live","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-OTHER","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-orphan","assignee":"gc-toolkit__polecat-lx-x","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-ORPHAN","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}}
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
    printf '%s\n' "$*" >> "$FAKE_UPDATES" ;;
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

# (AFFINE/ATOMIC) affine step -> all three pins cleared, in ONE update.
eq "$(grep -c '^bd update s-load' "$UP" || true)" "1" \
  "(ATOMIC) s-load quiesced in exactly one update (no split-update race)"
SL="$(line_for s-load)"
if grep -q -- '--unset-metadata gc.routed_to' <<< "$SL" \
   && grep -q -- '--assignee' <<< "$SL" \
   && grep -q -- '--unset-metadata gc.session_affinity' <<< "$SL"; then
  ok "(AFFINE) affine step -> routed_to + assignee + session_affinity all cleared"
else
  bad "(AFFINE) affine step must clear all three pins (got: $SL)"
fi

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
sh "$SCRIPT" takeaway A-PARKED "dropped" --release --route "$POOL" >/dev/null 2>"$TMP/rerr" || true
eq "$(grep -c -- "--set-metadata gc.routed_to=$POOL" "$TMP/updates" || true)" "2" \
   "(ROUTEFIX) an empty read-back is re-stamped"
grep -q 'read back as' "$TMP/rerr" \
  && ok "(ROUTEFIX) …and the miss is reported" \
  || bad "(ROUTEFIX) the dropped route was silent (stderr: $(cat "$TMP/rerr"))"
grep -q 'visible to no pool' "$TMP/rerr" \
  && ok "(ROUTEFIX) …and a repair that also misses says what it costs" \
  || bad "(ROUTEFIX) the persistent miss does not name its consequence (stderr: $(cat "$TMP/rerr"))"

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

echo ""
echo "gc-helm takeaway (release quiesce, waiting-on edges, length gate) + dismiss: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
