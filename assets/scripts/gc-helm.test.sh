#!/usr/bin/env bash
# Hermetic tests for gc-helm.sh's takeaway verb (the board half lives in
# services/helm; the open verb is covered by gc-helm-open.test.sh). Runs the
# REAL script with a stubbed `gc` on PATH — no live city, Dolt, network, or
# sessions. Covered:
#   --release molecule-step quiescing (tk-xypcy, tk-q5r65)
#   --waiting-on edges (tk-2plde)
#   the ≤140-codepoint length gate (tk-9tbbk.1)
#   the retired board verb refuses and names helm-svc board
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
    # One rig; its path has no .beads dir, so gc-helm issues un-scoped bd calls.
    jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd list")
    cat "$FAKE_STEPS_JSON" ;;
  "bd show")
    id="$3"
    convoy=$(awk -F'|' -v r="$id" '$1==r{print $2; exit}' "$FAKE_ROOTS")
    if [ -n "$convoy" ]; then jq -n --arg c "$convoy" '[{metadata:{"gc.input_convoy_id":$c}}]'
    else printf '[{"metadata":{}}]\n'; fi ;;
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
       FAKE_DEPS="$TMP/deps"
: > "$TMP/deps"
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

echo ""
echo "gc-helm takeaway (release quiesce, waiting-on edges, length gate): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
