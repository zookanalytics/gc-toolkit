#!/usr/bin/env bash
# Hermetic tests for gc-helm.sh. Two independent scenarios, one file:
#   1. takeaway --release molecule-step quiescing (tk-xypcy, tk-q5r65) — below
#   2. the anchor-gather argv boundary (tk-hgmob) — second half, own header
#
# SCENARIO 1 — takeaway --release molecule-step quiescing
#
# THE BUG (recurring polecat burn): `gc-helm takeaway <anchor> "..." --release`
# parks a work bead — the ANCHOR of a graph.v2 molecule — by clearing
# the ANCHOR's own route. But the molecule's STEP beads keep their own pins
# (gc.routed_to, an assignee, gc.session_affinity=require). Those pins
# independently re-attract the pool / the assigned-work hand-back, so the pool
# re-spawns a polecat onto the already-parked husk, which re-derives "nothing to
# do" and drains — one burned session per scale_check tick.
#
# THE FIX: on --release, after parking the anchor, walk the anchor's molecule
# (reverse: live graph.v2 steps -> gc.root_bead_id -> root's
# gc.input_convoy_id -> convoy's single member) and clear the re-attracting pins
# on exactly the steps whose root resolves to THIS parked anchor.
#
# This test runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a
# stubbed `gc` on PATH — no live city, Dolt, network, or sessions. Covered:
#   (RELEASE)   the anchor still gets the full reopen/unassign/clear-route bundle
#   (AFFINE)    an assigned+affine+routed step -> routed_to + assignee +
#               session_affinity ALL cleared, in ONE update
#   (POOL)      an unassigned+routed step -> routed_to only (nothing else to clear)
#   (ATOMIC)    each quiesced step is written exactly once (no split-update race)
#   (FINAL)     the workflow-finalize step keeps its control-dispatcher route
#   (IDEM)      an already-quiet step is not re-updated
#   (SCOPE)     a DIFFERENT molecule (anchor != parked bead) is left untouched
#   (FAILCLOSE) a root whose anchor cannot be resolved is skipped, not quiesced
#   (CONTRACT)  a graph.v2 step of ANOTHER formula under the parked root is
#               quiesced too — selection is by contract, not formula name
#               (tk-q5r65). This inverts the old (FILTER) case, whose
#               startswith("mol-polecat-work.") row filter dropped every other
#               formula's steps before the anchor match could judge them
#   (NOTV2)     a pinned bead with NO gc.step_ref is never a candidate, even
#               under the parked root — the membership test is the only gate
#               it fails
#   (NOCLOSE)   no step is closed and no step status is rewritten (the DANGER
#               clause), asserted both dynamically and as a static guard
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
# The bead being parked: A-PARKED (anchor of the mol-polecat-work molecule whose
# root is root-PARKED, tracked by convoy convoy-PARKED).
#
# Steps (bd list --json shape). Under root-PARKED:
#   s-load   affine  : assignee + routed + session_affinity -> clear all three
#   s-impl   pool    : routed only (already unassigned)      -> clear routed only
#   s-final  finalize: control-dispatcher route              -> MUST stay routed
#   s-quiet  quiet   : no pins at all                         -> not re-updated
#   s-nonmol contract: a NON-mol-polecat-work graph.v2 step_ref -> quiesced all
#                      the same (tk-q5r65; this used to be ignored)
#   s-noref  not-v2  : pinned, but NO gc.step_ref at all      -> never a candidate
# Under a DIFFERENT molecule (root-OTHER -> convoy-OTHER -> A-OTHER != parked):
#   s-other  scope   : affine+routed                          -> MUST stay untouched
# Under root-ORPHAN (no convoy -> anchor unresolvable):
#   s-orphan failsafe: affine+routed                          -> MUST stay untouched
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
    # A single rig so enumerate_rigs never exit-3s. Path has no .beads dir, so
    # gc-helm resolves db="" and issues un-scoped bd calls (the mock ignores --db).
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
    # A blocker named NOPE stands for every edge that cannot be written: a
    # blocker in another rig's store, a typo, a cycle. bd exits non-zero and
    # gc-helm must survive it.
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
# Neutralize any inherited helm fixture hook so enumerate_rigs uses the stub.
unset GC_HELM_FIXTURE || true

# --- Run: park A-PARKED with --release. ---------------------------------------
OUT="$(sh "$SCRIPT" takeaway A-PARKED "parked" --by proactive --release 2>"$TMP/err" || true)"
ERR="$(cat "$TMP/err")"
UP="$TMP/updates"

# helpers: capture a bead's update line(s); empty string if none.
line_for() { grep -E "^bd update $1( |\$)" "$UP" || true; }

# (RELEASE) the parked anchor still gets the full reopen/unassign/clear-route bundle.
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

# (AFFINE) affine step -> routed_to + assignee + session_affinity, in ONE update.
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
# quiesced exactly like a mol-polecat-work one — steps are selected by the
# graph.v2 contract, not by formula name (tk-q5r65). This assertion is inverted
# from what it used to check: the old `startswith("mol-polecat-work.")` row
# filter dropped such a step here, before the anchor match could have any say,
# so parking a mol-scoped-work anchor quiesced nothing and its husk kept
# re-attracting the pool. The anchor match below is still the fail-closed gate;
# widening the row filter only gives it more candidates to refuse.
SN="$(line_for s-nonmol)"
[ -n "$SN" ] \
  && ok "(CONTRACT) a non-mol-polecat-work graph.v2 step under the parked anchor IS quiesced" \
  || bad "(CONTRACT) graph.v2 step of another formula must be quiesced (got: none)"
grep -q -- '--unset-metadata gc.routed_to' <<< "$SN" \
  && ok "(CONTRACT) its route is cleared" || bad "(CONTRACT) route cleared (got: $SN)"
grep -q -- '--assignee' <<< "$SN" \
  && ok "(CONTRACT) its assignee is cleared" || bad "(CONTRACT) assignee cleared (got: $SN)"

# (NOTV2) a bead with NO gc.step_ref is not a graph.v2 step at all, so it is
# never a candidate — asserted under the SAME parked root, where every other
# gate would pass. The membership test is the only thing holding it back, which
# is what keeps the widening a wider net over graph.v2 steps rather than a
# blanket sweep of every pinned bead under the anchor.
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

# (STATIC NOCLOSE) the quiesce block itself contains no close/status-write cmd.
# The ONLY legitimate `--status` in the block is the `bd list` read filter
# (--status=open,in_progress selects which beads to consider); exclude that line
# so a genuine status-WRITE or `bd close` regression still trips the guard.
BLOCK="$(awk '/# >>> quiesce-release-molecule-steps/{f=1;next} /# <<< quiesce-release-molecule-steps/{f=0} f' "$SCRIPT")"
[ -n "$BLOCK" ] && ok "(MARKERS) quiesce block extracted between markers" || bad "(MARKERS) block extraction EMPTY — markers missing"
DANGER="$(printf '%s\n' "$BLOCK" | grep -v 'bd list --status' | grep -E 'bd close|--status|--close' || true)"
[ -z "$DANGER" ] \
  && ok "(NOCLOSE static) quiesce block writes no status and closes nothing (only the bd list read-filter uses --status)" \
  || bad "(NOCLOSE static) quiesce block contains a close/status-write: $DANGER"

# Surface any script stderr for debugging only (not an assertion).
if [ -n "$ERR" ]; then printf 'note: script stderr:\n%s\n' "$ERR" >&2; fi

# ── takeaway --waiting-on: the wait as a GRAPH EDGE (tk-2plde) ────────────────
#
# THE BUG: a sitting that routed work out of a subject recorded the wait only
# inside the takeaway string. Nothing re-reads prose, so "routed — tk-hgmob
# slung; nothing further needed here" went on saying exactly that after
# tk-hgmob merged, and the subject sat parked at LOW for 29 hours until a whole
# sitting was spent rediscovering it was finished.
#
# THE WRITER HALF: --waiting-on adds `subject depends on <work bead>` as a
# `blocks` edge beside the prose, which is the thing the board can re-ask.
# Covered:
#   (EDGE)      one --waiting-on writes one edge, in the depends-on direction
#   (EDGEMANY)  the flag is repeatable, and --waiting-on=<id> parses too
#   (EDGESTAMP) the takeaway is still stamped in the same run
#   (EDGESELF)  a bead cannot be made to wait on itself
#   (EDGEFAIL)  an edge that will not take does NOT lose the takeaway — the
#               conclusion is what the sitting owes the operator
#   (EDGENONE)  no flag, no edges: every existing caller is unchanged
: > "$TMP/updates"; : > "$TMP/deps"
WOUT="$(sh "$SCRIPT" takeaway A-PARKED "routed — the fix is slung" --by converse \
          --waiting-on tk-blk1 --waiting-on=tk-blk2 2>"$TMP/werr" || true)"
WERR="$(cat "$TMP/werr")"
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

# (EDGESELF) a self-wait is a cycle, and bd would reject it later; refuse here
# where the message can say which flag was wrong.
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "self" --waiting-on A-PARKED >/dev/null 2>"$TMP/werr" || true
eq "$(grep -c '^bd dep add' "$TMP/deps" || true)" "0" "(EDGESELF) a bead is never made to wait on itself"
grep -q 'bead itself' "$TMP/werr" \
  && ok "(EDGESELF) …and the refusal names the reason" \
  || bad "(EDGESELF) silent skip (stderr: $(cat "$TMP/werr"))"

# (EDGEFAIL) THE ORDERING RULE. The takeaway is written FIRST and an edge that
# fails only warns. A sitting that could not wire its graph must still leave the
# conclusion it reached — losing that is the data loss the edge exists to
# prevent, arriving by another door.
: > "$TMP/updates"; : > "$TMP/deps"
WRC=0
sh "$SCRIPT" takeaway A-PARKED "held for review" --waiting-on NOPE >/dev/null 2>"$TMP/werr" || WRC=$?
grep -q -- '--set-metadata gc.takeaway=held for review' "$TMP/updates" \
  && ok "(EDGEFAIL) a rejected edge does not cost the takeaway" \
  || bad "(EDGEFAIL) the stamp was lost when the edge failed: $(cat "$TMP/updates")"
grep -q 'could not wire' "$TMP/werr" \
  && ok "(EDGEFAIL) …and the failure is reported, not swallowed" \
  || bad "(EDGEFAIL) the failed edge was silent (stderr: $(cat "$TMP/werr"))"
# The exit status is what pins the ORDER. Warning and exiting non-zero would
# leave the stamp on the bead but tell the caller the verb failed, and the
# converse step that calls it treats a failure as "this hold left no trace".
eq "$WRC" "0" "(EDGEFAIL) …and the verb still succeeds: the takeaway landed"

# (EDGENONE) the flag is opt-in; every existing caller must be byte-identical.
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "no edges here" >/dev/null 2>&1 || true
eq "$(grep -c '^bd dep' "$TMP/deps" || true)" "0" "(EDGENONE) no --waiting-on, no graph writes"
grep -q -- '--set-metadata gc.takeaway=no edges here' "$TMP/updates" \
  && ok "(EDGENONE) …and the plain stamp path is unchanged" \
  || bad "(EDGENONE) the plain path changed: $(cat "$TMP/updates")"

# ── takeaway length: the ≤140 cap, ENFORCED (tk-9tbbk.1) ─────────────────────
#
# THE BUG: `140` appeared in this script's usage string and nowhere else — not
# in the writer, not in either renderer. Measured live on 2026-08-22, it ran
# 22-for-23 against: 23 stored takeaways averaging 597 characters, longest
# 1876, together 91% of ALL the NEEDS text on the board. NEEDS is the last
# column of a terminal table, so those are not wide cells; each one is a row
# wrapping over the rows beneath it. The remedy tried before this was a
# note-to-self in a bead's notes ("keep gc.takeaway SHORT"); the sitting that
# wrote it then stamped a 200-char takeaway. Documentation cannot hold a cap.
#
# REJECT, never truncate: only the author knows which clause is the headline.
# Covered:
#   (CAP)        over the cap -> usage error, exit 2
#   (CAPNOWRITE) …and NOTHING is written — the bead keeps its old takeaway
#   (CAPMSG)     …and the refusal names the measured length and the cap
#   (CAPOK)      exactly 140 is accepted — the boundary is inclusive
#   (CAPRUNE)    140 multi-byte chars are accepted: the unit is CODEPOINTS,
#                which is what both renderers measure. A byte cap would refuse
#                a headline that fits on the board
#   (CAPWS)      length is measured AFTER the whitespace collapse, so a text
#                padded by a run of spaces is judged on what gets stored
#   (CAPFIRST)   the gate runs before every side effect: --release does not
#                park the bead and --waiting-on writes no edge
#   (CAPNOTRIM)  static: the gate rewrites nothing — a silent trim would drop
#                the half the sitting most wanted read and still report success
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
# 200 spaces between two words is 3 characters by the time it reaches the gate.
: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "a$(printf ' %.0s' {1..200})b" >/dev/null 2>&1 || true
grep -q -- '--set-metadata gc.takeaway=a b' "$TMP/updates" \
  && ok "(CAPWS) the cap measures the collapsed text, not the raw argument" \
  || bad "(CAPWS) whitespace padding was counted against the cap: $(cat "$TMP/updates")"

# (CAPFIRST) THE ORDERING RULE, the mirror of (EDGEFAIL). A refusal must cost
# nothing: --release would park the bead and --waiting-on would write an edge,
# and both would outlive a takeaway that never landed.
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "$T141" --release --waiting-on tk-blk1 >/dev/null 2>&1 || true
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(CAPFIRST) a refused takeaway does not park the bead"
eq "$(grep -c '^bd dep' "$TMP/deps" || true)"       "0" "(CAPFIRST) …and writes no waiting-on edge"

# (CAPNOTRIM) static: the gate must REFUSE, not silently shorten. A trim would
# be invisible — the update succeeds, the board looks tidy, and the clause the
# sitting cared about is gone with no record that it existed.
GATE="$(awk '/# >>> takeaway-length-gate/{f=1;next} /# <<< takeaway-length-gate/{f=0} f' "$SCRIPT")"
[ -n "$GATE" ] && ok "(CAPNOTRIM) length-gate block extracted between markers" \
               || bad "(CAPNOTRIM) block extraction EMPTY — markers missing"
TRIM="$(printf '%s\n' "$GATE" | grep -vE '^\s*#' | grep -E 'text=|text:0:|cut -c' || true)"
[ -z "$TRIM" ] \
  && ok "(CAPNOTRIM) the gate never rewrites the text — it refuses it" \
  || bad "(CAPNOTRIM) the gate silently shortens the takeaway: $TRIM"

# ══════════════════════════════════════════════════════════════════════════════
# THE THIN RENDERER — what this script does AROUND helm-svc (tk-clvkf6)
# ══════════════════════════════════════════════════════════════════════════════
#
# WHAT LEFT, AND WHY NOTHING IS UNGUARDED BY ITS LEAVING. Everything between
# here and the summary used to drive the board's own gather, rank and render
# through the GC_HELM_FIXTURE hook: the argv boundary (tk-hgmob), the in-flight
# join, the metadata-keyed kinds, the render-side liveness re-check, the row
# cap, the NEEDS clip. That code is gone from this file — the board is
# services/helm now — and its assertions went WITH the code rather than being
# deleted: internal/board/derive_test.go covers the model, and
# cmd/helm-svc/board_cli_test.go covers the render, the cap and the flags,
# against the implementation that actually runs.
#
# One of those cases earned a Go home by name. (VISITEDGE) proved a visit whose
# gc.continuation_group stamp landed EMPTY is still gathered through its
# `tracks` edge — the behaviour the Go gather did NOT have, which is how the
# same anchor could read held here and unheld there. It is now
# TestSubjectOfPrefersTracksEdge in internal/source.
#
# WHAT IS TESTED HERE is the part that is genuinely this script's: which flags
# it forwards, what it caches and under what key, and how it behaves when
# helm-svc fails or is not built at all. The stub below stands in for the
# binary via GC_HELM_SVC_BIN, so none of this needs a built helm-svc, a live
# city or Dolt.

TH="$TMP/thin"
mkdir -p "$TH"

# The stub records every invocation and prints something identifiable. Its
# output is deliberately a function of its ARGV, so a cache slot serving the
# wrong caller's answer is visible in the assertion rather than inferred.
cat > "$TH/helm-svc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_CALLS"
[ -n "${STUB_STDERR:-}" ] && printf '%s\n' "$STUB_STDERR" >&2
[ -n "${STUB_RC:-}" ] && [ "${STUB_RC}" != "0" ] && { printf 'STUB-OUT %s\n' "$*"; exit "$STUB_RC"; }
printf 'STUB-OUT %s\n' "$*"
exit 0
STUB
chmod +x "$TH/helm-svc"

# thin <case-tag> [args…] -> sets TRC / TOUT / TERR / TCALLS
# Each case gets its own TMPDIR, so one case's cache cannot answer another's.
# GC_CITY_PATH is pinned because it keys the cache file name.
thin() {
    local tag="$1"; shift
    local run="$TH/run-$tag"
    mkdir -p "$run"
    TRC=0
    TOUT="$(env TMPDIR="$run" GC_CITY_PATH=/fake/city \
                GC_HELM_SVC_BIN="${THIN_BIN-$TH/helm-svc}" \
                STUB_CALLS="$run/calls" STUB_RC="${STUB_RC:-0}" STUB_STDERR="${STUB_STDERR:-}" \
                GC_HELM_FIXTURE= \
                sh "$SCRIPT" "$@" 2>"$run/err")" || TRC=$?
    TERR="$(cat "$run/err" 2>/dev/null || true)"
    TCALLS="$(cat "$run/calls" 2>/dev/null || true)"
    TSLOTS="$(find "$run" -name 'render1-*' 2>/dev/null | wc -l | tr -d ' ')"
}

# --- (DELEGATE) the verbs reach helm-svc's matching subcommand ---------------
thin delegate-board --limit=7
eq "$TRC" "0" "(DELEGATE) board exits 0 (err: ${TERR:-none})"
eq "$TCALLS" "board --limit=7" "(DELEGATE) board forwards its flags to \`helm-svc board\`"
eq "$TOUT" "STUB-OUT board --limit=7" "(DELEGATE) …and hands back helm-svc's bytes unaltered"

thin delegate-closed closed --since 7d --json
eq "$TCALLS" "closed --since 7d --json" "(DELEGATE) closed forwards to \`helm-svc closed\`, flag order intact"

# The no-verb form is the back-compat path the tmux picker uses.
thin delegate-bare --json
eq "$TCALLS" "board --json" "(DELEGATE) a bare flag still means board"

# --- (PASSTHRU) helm-svc owns validation, and its exit code is ours ----------
# The script must not grow a second flag parser: an unknown flag is helm-svc's
# to refuse, and its refusal has to arrive unchanged. A wrapper that validated
# separately would be a second surface to keep equal — the exact duplication
# this change removes.
STUB_RC=2 thin passthru-usage --nonsense
eq "$TRC" "2" "(PASSTHRU) a usage failure keeps helm-svc's exit code"
eq "$TCALLS" "board --nonsense" "(PASSTHRU) …and the flag reached helm-svc rather than being pre-judged"

STUB_RC=3 STUB_STDERR="gather failed: dolt wedged" thin passthru-gather
eq "$TRC" "3" "(PASSTHRU) a failed gather exits 3"
eq "$TOUT" "" "(PASSTHRU) …renders NOTHING (a short board is worse than none)"
case "$TERR" in *"dolt wedged"*) ok "(PASSTHRU) …and helm-svc's reason reaches the operator" ;;
                *) bad "(PASSTHRU) helm-svc's stderr was swallowed: $TERR" ;; esac
eq "$TSLOTS" "0" "(PASSTHRU) …and a failed run is never cached"

# --- (CACHEHIT) a repeat glance costs nothing --------------------------------
# The reason the cache exists at all: helm-svc's CLI path is daemonless and
# pays a full gather (~6s on the live city) every run, and the tmux picker
# re-opens the board on every glance.
CRUN="$TH/run-cachehit"
mkdir -p "$CRUN"
cachehit() {
    env TMPDIR="$CRUN" GC_CITY_PATH=/fake/city GC_HELM_SVC_BIN="$TH/helm-svc" \
        STUB_CALLS="$CRUN/calls" GC_HELM_FIXTURE= sh "$SCRIPT" "$@" 2>/dev/null
}
: > "$CRUN/calls"
A1="$(cachehit --json --limit=36)"
A2="$(cachehit --json --limit=36)"
eq "$(wc -l < "$CRUN/calls" | tr -d ' ')" "1" "(CACHEHIT) an identical second glance does not re-run helm-svc"
eq "$A2" "$A1" "(CACHEHIT) …and replays the same bytes"

# --- (CACHEKEY) the slot is keyed by the WHOLE argv --------------------------
# The live case this guards: tmux-pick-helm.sh runs `--json --limit=36`, so a
# `--limit=2` typed at a prompt inside the TTL must not hand the picker two
# rows. A verb-only key would do exactly that — and silently, because the
# answer is well-formed JSON either way.
B1="$(cachehit --json --limit=2)"
eq "$(wc -l < "$CRUN/calls" | tr -d ' ')" "2" "(CACHEKEY) a different --limit is a different question, so helm-svc runs again"
eq "$B1" "STUB-OUT board --json --limit=2" "(CACHEKEY) …and the answer matches the flags THIS caller passed"
eq "$(cachehit --json --limit=36)" "$A1" "(CACHEKEY) …while the first question still replays its own answer"
eq "$(wc -l < "$CRUN/calls" | tr -d ' ')" "2" "(CACHEKEY) …from cache, without a third run"

# The table and the JSON are different representations of the same question and
# must not share a slot either.
T1="$(cachehit --limit=36)"
eq "$T1" "STUB-OUT board --limit=36" "(CACHEKEY) the table does not read the --json slot"

# --- (REFRESH) the cache-control flags are ours, not helm-svc's --------------
: > "$CRUN/calls"
R1="$(cachehit --json --limit=36 --refresh)"
eq "$(wc -l < "$CRUN/calls" | tr -d ' ')" "1" "(REFRESH) --refresh re-runs helm-svc despite a fresh cache"
eq "$R1" "STUB-OUT board --json --limit=36" "(REFRESH) …and is NOT forwarded (helm-svc has no cache to bust)"
: > "$CRUN/calls"
N1="$(cachehit --json --limit=36 --no-cache)"
eq "$(wc -l < "$CRUN/calls" | tr -d ' ')" "1" "(REFRESH) --no-cache is a synonym"
eq "$N1" "STUB-OUT board --json --limit=36" "(REFRESH) …and is not forwarded either"

# --- (BUSTED) a write invalidates what the next glance would replay ----------
# Every write verb changes what the board says — `open` files a visit (the held
# glyph), `takeaway` sets the NEEDS sentence — so a cache that outlived the
# write would show the operator their own action having no effect.
BRUN="$TH/run-bust"
mkdir -p "$BRUN/bin"
cp "$TMP/bin/gc" "$BRUN/bin/gc" 2>/dev/null || true
: > "$BRUN/calls"
env TMPDIR="$BRUN" GC_CITY_PATH=/fake/city GC_HELM_SVC_BIN="$TH/helm-svc" \
    STUB_CALLS="$BRUN/calls" GC_HELM_FIXTURE= sh "$SCRIPT" --json >/dev/null 2>&1
BEFORE="$(find "$BRUN" -name 'render1-*' | wc -l | tr -d ' ')"
env PATH="$BRUN/bin:$PATH" TMPDIR="$BRUN" GC_CITY_PATH=/fake/city \
    GC_HELM_FIXTURE= sh "$SCRIPT" takeaway A-PARKED "busting the cache" >/dev/null 2>&1 || true
AFTER="$(find "$BRUN" -name 'render1-*' | wc -l | tr -d ' ')"
eq "$BEFORE" "1" "(BUSTED) control: the glance left a cached slot"
eq "$AFTER"  "0" "(BUSTED) a takeaway write drops it, so the next glance re-renders"

# --- (DEGRADE) no binary is a build that has not run, not a dead city --------
DRUN="$TH/run-degrade"
mkdir -p "$DRUN"
env TMPDIR="$DRUN" GC_CITY_PATH=/fake/city GC_HELM_SVC_BIN="$TH/helm-svc" \
    STUB_CALLS="$DRUN/calls" GC_HELM_FIXTURE= sh "$SCRIPT" --json >/dev/null 2>&1
# Age the stamp past the TTL, so a replay cannot be mistaken for a cache HIT.
DSLOT="$(find "$DRUN" -name 'render1-*' | head -1)"
if [ -n "$DSLOT" ]; then
    DTS="$(head -n1 "$DSLOT")"
    { printf '%s\n' "$((DTS - 600))"; tail -n +2 "$DSLOT"; } > "$DSLOT.aged" && mv "$DSLOT.aged" "$DSLOT"
fi
DRC=0
DOUT="$(env TMPDIR="$DRUN" GC_CITY_PATH=/fake/city GC_HELM_SVC_BIN=/nonexistent \
            GC_HELM_SERVICE_NAME=no-such-service GC_CITY= GC_CITY_ROOT= \
            GC_HELM_FIXTURE= sh "$SCRIPT" --json 2>"$DRUN/err")" || DRC=$?
DERR="$(cat "$DRUN/err")"
eq "$DRC" "0" "(DEGRADE) a stale cache is served rather than nothing"
eq "$DOUT" "STUB-OUT board --json" "(DEGRADE) …with the bytes intact"
case "$DERR" in *"not built"*replaying*) ok "(DEGRADE) …and the replay says so on stderr" ;;
                *) bad "(DEGRADE) a stale replay was silent: $DERR" ;; esac
# The age is asserted as a NUMBER, not as the exact 600 the stamp was moved
# back by: a second ticking over between writing the cache and reading it makes
# that 601, and a test that fails on the clock teaches everyone to re-run it.
# What has to hold is that an age is stated at all — the reader, not this
# script, decides whether a ten-minute-old board is good enough.
if printf '%s' "$DERR" | grep -qE 'cached [0-9]+s ago'; then
    ok "(DEGRADE) …naming the age, so the reader judges it"
else
    bad "(DEGRADE) the banner did not state the age: $DERR"
fi
# The banner must not corrupt the contract it is warning about.
printf '%s' "$DOUT" | grep -q 'not built' \
  && bad "(DEGRADE) the banner leaked into stdout, corrupting --json" \
  || ok "(DEGRADE) the banner is on stderr, so --json stays parseable"

# --- (NOBIN) nothing to render and nothing to replay -------------------------
NRUN="$TH/run-nobin"
mkdir -p "$NRUN"
NRC=0
NOUT="$(env TMPDIR="$NRUN" GC_CITY_PATH=/fake/city GC_HELM_SVC_BIN=/nonexistent \
             GC_HELM_SERVICE_NAME=no-such-service GC_CITY= GC_CITY_ROOT= \
             GC_HELM_FIXTURE= sh "$SCRIPT" --json 2>"$NRUN/err")" || NRC=$?
NERR="$(cat "$NRUN/err")"
eq "$NRC" "3" "(NOBIN) no binary and no cache exits 3"
eq "$NOUT" "" "(NOBIN) …and renders nothing"
case "$NERR" in *gc-helm-build.sh*) ok "(NOBIN) …and names the build that fixes it" ;;
                *) bad "(NOBIN) the message does not say how to recover: $NERR" ;; esac

# --- (HELPHERE) -h is answered by this script, which knows every verb --------
# helm-svc's own usage covers one subcommand; a caller typing `gc-helm --help`
# is asking about open/react/takeaway too.
HRUN="$TH/run-help"
mkdir -p "$HRUN"
: > "$HRUN/calls"
HERR="$(env TMPDIR="$HRUN" GC_CITY_PATH=/fake/city GC_HELM_SVC_BIN="$TH/helm-svc" \
             STUB_CALLS="$HRUN/calls" GC_HELM_FIXTURE= sh "$SCRIPT" --help 2>&1 >/dev/null || true)"
eq "$(cat "$HRUN/calls" 2>/dev/null | wc -l | tr -d ' ')" "0" "(HELPHERE) --help does not shell out to helm-svc"
case "$HERR" in *takeaway*) ok "(HELPHERE) …and documents the write verbs helm-svc knows nothing about" ;;
                *) bad "(HELPHERE) usage lost the write verbs: $HERR" ;; esac
case "$HERR" in *closed*) ok "(HELPHERE) …and the closed verb" ;;
                *) bad "(HELPHERE) usage does not mention closed" ;; esac

# --- (NOGATHER) the duplicate really is gone ---------------------------------
# A static guard, because the failure it catches is someone re-adding a "just
# this one field" gather here rather than in the model — which is how the two
# boards diverged the first time.
for fn in gather_anchors gather_open_beads gather_visits gather_meta_anchors gather_inflight resolve_waiting_status; do
    if grep -qE "^$fn\(\)" "$SCRIPT"; then
        bad "(NOGATHER) $fn() is back in gc-helm.sh — the board belongs to services/helm"
    else
        ok "(NOGATHER) $fn() is gone"
    fi
done

echo ""
echo "gc-helm takeaway --release quiesce + the thin renderer over helm-svc: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
