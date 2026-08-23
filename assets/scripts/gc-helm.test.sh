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
# ANCHOR GATHER — the argv boundary (tk-hgmob)
# ══════════════════════════════════════════════════════════════════════════════
#
# THE BUG: gather_anchors() passed the FULL child listing — every child's
# description and notes — across the argv boundary as `jq --argjson ch`. Linux
# caps a SINGLE argv string at MAX_ARG_STRLEN = 131072 B, independent of the far
# larger ARG_MAX (2 MB here), which the "Argument list too long" wording invites
# you to blame. One bead's accumulated notes is enough to cross it: live epic
# sl-zi5z had TWO children carrying 158 KB between them.
#
# Why it was SILENT: jq never execs, so nothing is appended to $ANCHORS. The
# existing guards at the -raw queries check QUERY validity, and the query was
# fine — so the gather was judged clean and the board CACHED AND RENDERED AS
# COMPLETE with the epic simply missing. The stderr line scrolls away.
#
# THE FIX (both halves, one diff):
#   1. project to {id,status,assignee} through a PIPE before the argv hop, so
#      the payload re-bases on child COUNT (~50 B/child) not note volume;
#   2. guard the render with `|| gather_mark`, so a future failure at this step
#      refuses the cache instead of silently shipping a short board.
#
# These run the REAL script with a board-path `gc` stub, same as above.

GTMP="$TMP/gather"
mkdir -p "$GTMP/bin" "$GTMP/rig/.beads"

cat > "$GTMP/bin/gc" <<'GCB'
#!/usr/bin/env bash
# Board-path stub: just enough of the gather surface for gather_anchors().
args="$*"
case "$1 ${2:-}" in
  "rig list")    jq -n --arg p "$FAKE_RIG_PATH" '{rigs:[{name:"gc-toolkit",path:$p,prefix:"tk"}]}' ;;
  "convoy list")  printf '{"convoys":[]}\n' ;;
  "session list") printf '{"sessions":[]}\n' ;;
  "bd show")      printf '[]\n' ;;
  "bd list")
    case "$args" in
      *--parent*)          cat "$FAKE_CHILDREN" ;;
      *"--type epic"*)     cat "$FAKE_EPICS" ;;
      *"--type decision"*) printf '[]\n' ;;
      *)  # the open+in_progress listing, which is also what gather_visits reads
          if [ -n "${FAKE_OPEN:-}" ] && [ -f "${FAKE_OPEN:-}" ]; then cat "$FAKE_OPEN"
          else printf '[]\n'; fi ;;
    esac ;;
esac
exit 0
GCB
chmod +x "$GTMP/bin/gc"

printf '[{"id":"tk-epic1","title":"epic one","priority":1,"updated_at":"2026-08-20T00:00:00Z","metadata":{}}]\n' \
  > "$GTMP/epics.json"

# run_board <children-file> <case-tag> -> sets BRC / BOUT / BERR / BCACHE_N
run_board() {
    local kids="$1" run="$GTMP/run-$2"
    rm -rf "$run"; mkdir -p "$run"
    BRC=0
    BOUT="$(env PATH="$GTMP/bin:$PATH" TMPDIR="$run" \
                FAKE_RIG_PATH="$GTMP/rig" FAKE_EPICS="$GTMP/epics.json" FAKE_CHILDREN="$kids" \
                FAKE_OPEN="${FAKE_OPEN:-}" \
                GC_HELM_FIXTURE= \
                sh "$SCRIPT" board --json --refresh 2>"$run/err")" || BRC=$?
    BERR="$(cat "$run/err" 2>/dev/null || true)"
    # Any cache the run decided to persist lands under TMPDIR/gc-helm-cache.<uid>.
    # Format-AGNOSTIC glob: the cache file name carries its format and changes
    # with it, and every assertion below expects ZERO — so a glob pinned to one
    # format would go on passing while matching nothing.
    BCACHE_N="$(find "$run" -name 'board*.ndjson' 2>/dev/null | wc -l | tr -d ' ')"
}

# --- (ARGVCAP) the live sl-zi5z shape: 158 KB of child NOTES, two children. ----
# Old code: jq is never exec'd, the anchor is dropped, the board renders without
# it and exit 0. Fixed code: the notes never reach argv, so the row survives.
head -c 150000 /dev/zero | tr '\0' 'x' > "$GTMP/big.txt"
jq -n --rawfile big "$GTMP/big.txt" \
  '[{id:"tk-c1",status:"open",assignee:"gc-toolkit__polecat-lx-aaa",description:$big,notes:$big},
    {id:"tk-c2",status:"closed",assignee:null,description:"short",notes:"short"}]' \
  > "$GTMP/children-fat.json"

run_board "$GTMP/children-fat.json" fat
eq "$BRC" "0" "(ARGVCAP) board exits 0 with a 158 KB child payload"
printf '%s' "$BOUT" | jq -e 'any(.[]?; .id=="tk-epic1")' >/dev/null 2>&1 \
  && ok "(ARGVCAP) the epic anchor still renders when a child's notes exceed MAX_ARG_STRLEN" \
  || bad "(ARGVCAP) epic anchor VANISHED from the board (the tk-hgmob bug)"
grep -qi 'argument list too long' <<< "$BERR" \
  && bad "(ARGVCAP) still hitting the argv cap: $BERR" \
  || ok "(ARGVCAP) no 'Argument list too long' on the gather"

# --- (PROJSHAPE) the projection is output-identical to the old inline filter. --
# The render used to build children as [$ch[] | {id,status,assignee}]; it now
# receives that projection ready-made. The board does not emit `children`
# verbatim — it emits the ROLL-UP derived from it, which is the stronger check:
# these four counts can only come out right if all THREE projected fields
# arrived intact. m_total/n_closed/open need id+status; `assigned` needs
# assignee, and only tk-c1 has one.
rollup() { printf '%s' "$BOUT" | jq -r --arg k "$1" 'first(.[]? | select(.id=="tk-epic1")) | .[$k]' 2>/dev/null || true; }
eq "$(rollup m_total)"  "2" "(PROJSHAPE) roll-up counts both children (id survived)"
eq "$(rollup n_closed)" "1" "(PROJSHAPE) the closed child is counted closed (status survived)"
eq "$(rollup open)"     "1" "(PROJSHAPE) the open child is counted open (status survived)"
eq "$(rollup assigned)" "1" "(PROJSHAPE) the assigned child is counted assigned (assignee survived)"

# --- (PROJGUARD) a VALID array whose elements are not objects. ----------------
# The -raw guard passes (it is a real array), so this reaches the projection and
# nothing else can catch it. Old code: the same failure happened inside the
# unguarded render — board rendered short, exit 0, and CACHED. Fixed: marked.
printf '[1,2,3]\n' > "$GTMP/children-bad.json"
run_board "$GTMP/children-bad.json" bad
eq "$BRC" "3" "(PROJGUARD) a projection failure exits 3 (gather refused), not 0"
grep -q 'gather failed' <<< "$BERR" \
  && ok "(PROJGUARD) the run says the gather failed" || bad "(PROJGUARD) no gather-failed line (err: $BERR)"
grep -q 'children-project@tk-epic1' <<< "$BERR" \
  && ok "(PROJGUARD) the mark names the projection step and the epic" \
  || bad "(PROJGUARD) expected children-project@tk-epic1 in: $BERR"
eq "$BCACHE_N" "0" "(PROJGUARD) nothing cached — no false short board served for the TTL"

# --- (RENDERGUARD) force a failure at the render itself. ----------------------
# This is the acceptance case for fix 2: even projected, ~3000 children exceed
# MAX_ARG_STRLEN, so jq cannot exec at the render step. That step used to have no
# `|| gather_mark` at all, which is exactly why the bug was invisible.
jq -n '[range(3000) | {id:("tk-c"+(.|tostring)), status:"open",
                       assignee:"gc-toolkit__polecat-lx-aaaaaaa"}]' > "$GTMP/children-many.json"
run_board "$GTMP/children-many.json" many
eq "$BRC" "3" "(RENDERGUARD) a render that cannot exec exits 3 instead of shipping a short board"
grep -q 'anchor@tk-epic1' <<< "$BERR" \
  && ok "(RENDERGUARD) the render step is gather_mark'ed by name" \
  || bad "(RENDERGUARD) expected anchor@tk-epic1 in: $BERR"
eq "$BCACHE_N" "0" "(RENDERGUARD) nothing cached on a render failure"

# --- (HEADROOM) the fix re-bases growth on child COUNT, not note volume. ------
# 400 children is far past the note-driven failure the bug produced, and well
# inside the new bound — it must render clean.
jq -n '[range(400) | {id:("tk-h"+(.|tostring)), status:"open", assignee:"a",
                      description:"x", notes:"y"}]' > "$GTMP/children-400.json"
run_board "$GTMP/children-400.json" many400
eq "$BRC" "0" "(HEADROOM) 400 children render clean"
eq "$(printf '%s' "$BOUT" | jq -r 'first(.[]? | select(.id=="tk-epic1")) | .m_total' 2>/dev/null || true)" \
   "400" "(HEADROOM) all 400 children survive the roll-up"

# --- (VISITEDGE) a live visit whose group stamp landed EMPTY (bead tk-d6ddn) --
# gather_visits feeds $held, and $held is the ONLY thing keeping an anchor that
# is already in conversation out of the stranded band. A visit records its
# subject twice — the gc.continuation_group stamp and the tracks edge filed with
# it — and su-ab9je (shutupandlisten, 2026-08-20) proved the stamp can land
# EMPTY while the edge is intact. Read on the stamp alone that anchor bands HIGH
# and the board tells the operator to open a visit that already exists.
#
# These run through the REAL gather (GC_HELM_FIXTURE is cleared by run_board),
# so gather_open's listing IS the visits listing — the stub serves both from
# $FAKE_OPEN.
printf '[{"id":"tk-c1","status":"open","assignee":null},{"id":"tk-c2","status":"closed","assignee":null}]\n' \
  > "$GTMP/children-stranded.json"

# Positive control FIRST: with the stamp populated the anchor is held. Without
# this a broken stub would make the real case below "pass" by gathering nothing.
cat > "$GTMP/open-stamped.json" <<'JSON'
[{"id":"tk-v1","title":"visit: tk-epic1","metadata":{"task_kind":"visit","gc.continuation_group":"tk-epic1"}}]
JSON
FAKE_OPEN="$GTMP/open-stamped.json" run_board "$GTMP/children-stranded.json" visit-stamped
held_of() { printf '%s' "$BOUT" | jq -r --arg k "$1" 'first(.[]? | select(.id=="tk-epic1")) | .[$k]' 2>/dev/null || true; }
eq "$BRC" "0" "(VISITEDGE) control: the board renders with a stamped visit in the gather"
eq "$(held_of held)" "true" "(VISITEDGE) control: a visit naming the anchor by its STAMP is gathered"
eq "$(held_of stranded)" "false" "(VISITEDGE) control: an anchor in conversation is not stranded"

# A visit with NO visit at all: the anchor really is stranded. This is what
# makes the assertion below mean something — it pins that `held` tracks the
# gather rather than being true for every anchor.
printf '[]\n' > "$GTMP/open-novisit.json"
FAKE_OPEN="$GTMP/open-novisit.json" run_board "$GTMP/children-stranded.json" visit-none
eq "$(held_of held)" "false" "(VISITEDGE) control: no visit at all → not held"
eq "$(held_of stranded)" "true" "(VISITEDGE) control: and the anchor bands as stranded"

# The regression: stamp EMPTY, tracks edge intact — the su-ab9je shape. Rendered
# in the `gc bd list` key pair (.type + .depends_on_id), which is what this
# listing emits; `gc bd show` names the same edge .dependency_type + .id.
cat > "$GTMP/open-edge.json" <<'JSON'
[{"id":"tk-v2","title":"visit: tk-epic1","metadata":{"task_kind":"visit","gc.continuation_group":""},"dependencies":[{"issue_id":"tk-v2","depends_on_id":"tk-epic1","type":"tracks"}]}]
JSON
FAKE_OPEN="$GTMP/open-edge.json" run_board "$GTMP/children-stranded.json" visit-edge
eq "$(held_of held)" "true" \
   "(VISITEDGE) a visit whose stamp is EMPTY is still gathered, via its tracks edge"
eq "$(held_of stranded)" "false" \
   "(VISITEDGE) so the anchor already in conversation is not banded stranded"

# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 3 — the board reads work-bead status, so live work reads as stranded
#              (tk-fkeft), and metadata-owned beads never reach the board at all
#
# THE BUG (a). `gc sling` pours a graph.v2 molecule and routes its STEP beads.
# The work bead itself keeps status=open / assignee=null from dispatch until the
# refinery closes it — the in-flight state lives on the WORKFLOW. The board
# counted only children with status=in_progress, so a polecat five minutes into
# an implementation was byte-for-byte identical, in bead state, to a bead nobody
# had ever touched, and its parent epic rendered
#   "N open · 0 in-progress (stranded) / decomposed, idle — assign or visit"
# i.e. an instruction to intervene in work that is already moving. Ten of the
# eleven HIGH rows on the live board read that way when this was filed.
#
# THE FIX: join the work bead to any LIVE workflow over it, by the canonical
# walk (root -> gc.input_convoy_id -> the convoy's single tracked member), and
# count a covered child as moving.
#
# WHY LIVENESS IS THE WHOLE GAME, and why (HUSK) below is the load-bearing case:
# nothing finalizes a graph.v2 chain after its session drains, so every completed
# workflow leaves an open husk root behind and they pile up (18 open roots in
# one rig when this was written; 17 of them dead). Joining on root EXISTENCE
# would flip all 17 husks to "in flight" — trading a false stall for a false
# all-clear, which is the worse lie on a board whose job is to say what needs a
# human. So a root counts only while a session it is stamped with is live.
#
# THE BUG (b). The gather admitted three anchor kinds, all selected by issue
# TYPE — epic, decision, convoy. An ordinary task/bug the operator owns could
# not appear no matter its state, and invisible also means unresumable. Two
# metadata-keyed kinds are added, mirroring the Go helm service (tk-2v08m):
# `human` (gc.routed_to=human, ELEVATED) and `parked` (gc.takeaway present, LOW).
#
# Covered:
#   (INFLIGHT)  a live workflow over an unclaimed child -> parent NOT stranded
#   (HUSK)      a DEAD-session workflow -> parent still stranded (no false green)
#   (CLAIMED)   the pre-existing claimed+live-owner path still counts as moving
#   (IDLEHEAD)  a workflow-covered child drops out of open_heads
#   (ONEMEMBER) a convoy resolving to != 1 member is refused, not guessed
#   (HUMAN)     gc.routed_to=human gathers as kind `human`, band ELEVATED
#   (PARKED)    gc.takeaway gathers as kind `parked`, band LOW
#   (EXCLUDE)   an EPIC carrying a takeaway stays kind `epic` — gathered once
#   (FLOOR)     a parked row never outranks a stranded epic
#
# THE BUG (c) — tk-2plde. A sitting that ROUTES work out of a subject recorded
# the wait as prose inside gc.takeaway, and nothing ever re-read it. So
# "holding — awaiting X" and "nothing further needed here" were mechanically the
# same row, both LOW, forever: tk-yps55 sat parked for 29 hours after its work
# merged and cost a whole sitting to discover it was finished. The wait is now a
# `blocks` EDGE, and the board re-derives — per render, storing nothing —
# whether it has been discharged.
#
#   (DISPO)     every blocker closed -> ELEVATED, "blocker landed", and the
#               STALE takeaway is replaced as the NEEDS answer
#   (LIVEHOLD)  a blocker still open -> LOW, and the frontier counts it
#   (BAREPARK)  a parked row with NO edges renders exactly as it did before
#   (FAILCLOSE) a blocker the store cannot resolve counts as OPEN, never as
#               landed — a false "go dispose of this" is the costly direction
#
# THE BUG (d) — tk-b3rga. A `decision` and a `human` row are banded by what they
# ARE, and what they are never changes while the bead is open. So the row asked
# for the operator on the day it was filed and went on asking after they
# answered it: seven of the 24 ELEVATED rows on the 2026-08-23 board carried a
# takeaway recording their own ruling, one of them (tk-z130v) for thirty days,
# and converse never closes a subject by contract so nothing else could retire
# them. Same derivation shape as (c) — per render, storing nothing — pointed the
# other way: DOWN out of the band rather than up out of the floor.
#
#   (RULED)     takeaway + every wait landed -> LOW, "ruled — takeaway
#               recorded" / "ruled — close or extend", on both kinds
#   (RULEHOLD)  takeaway + a wait still OPEN -> band unchanged. Without the
#               waiting edges now gathered for these kinds this clause would be
#               vacuous, so it is what proves them wired
#   (RULEKIDS)  a ruled row that DECOMPOSED is banded by its roll-up — a ruling
#               must not become a new way to hide stranded children (tk-a9k0l)
#   (RULETWIN)  the `parked` twin of a ruled human bead must not hand the band
#               straight back through the dedup
# ══════════════════════════════════════════════════════════════════════════════

ITMP="$TMP/inflight"
mkdir -p "$ITMP/bin" "$ITMP/rig/.beads"

# Two epics. e-LIVE's child is carried by a live workflow; e-HUSK's child is
# carried by a workflow whose session is gone. Both children are open with NO
# assignee — the shape the old board could not tell apart.
cat > "$ITMP/epics.json" <<'J'
[
 {"id":"tk-eLIVE","title":"live epic","priority":1,"updated_at":"2026-08-21T00:00:00Z","metadata":{}},
 {"id":"tk-eHUSK","title":"husk epic","priority":1,"updated_at":"2026-08-21T00:00:00Z","metadata":{}},
 {"id":"tk-eCLAIM","title":"claimed epic","priority":1,"updated_at":"2026-08-21T00:00:00Z","metadata":{}},
 {"id":"tk-eMANY","title":"many-member epic","priority":1,"updated_at":"2026-08-21T00:00:00Z","metadata":{}},
 {"id":"tk-eTAKE","title":"epic that carries a takeaway","priority":1,"updated_at":"2026-08-21T00:00:00Z",
  "metadata":{"gc.takeaway":"an epic may carry one of these too"}}
]
J

cat > "$ITMP/kids-eLIVE.json"  <<'J'
[{"id":"tk-wLIVE","status":"open","assignee":null},{"id":"tk-done1","status":"closed","assignee":null}]
J
cat > "$ITMP/kids-eHUSK.json"  <<'J'
[{"id":"tk-wHUSK","status":"open","assignee":null},{"id":"tk-done2","status":"closed","assignee":null}]
J
# Claimed by a live session the old way — must keep counting as moving.
cat > "$ITMP/kids-eCLAIM.json" <<'J'
[{"id":"tk-wCLAIM","status":"in_progress","assignee":"gc-toolkit__polecat-lx-live"},{"id":"tk-done3","status":"closed","assignee":null}]
J
cat > "$ITMP/kids-eMANY.json"  <<'J'
[{"id":"tk-wMANY","status":"open","assignee":null},{"id":"tk-done4","status":"closed","assignee":null}]
J
cat > "$ITMP/kids-eTAKE.json"  <<'J'
[{"id":"tk-done5","status":"closed","assignee":null}]
J

# The shared per-rig open-bead snapshot: workflow roots, their steps, and the
# two metadata-owned beads. root-MANY's convoy resolves to TWO members, which
# the fail-closed one-member gate must refuse rather than guess at.
cat > "$ITMP/open.json" <<'J'
[
 {"id":"tk-rLIVE","status":"in_progress","assignee":null,"issue_type":"task","title":"wf live","priority":3,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"cv-LIVE","gc.session_name":"gc-toolkit__polecat-lx-live"}},
 {"id":"tk-rHUSK","status":"open","assignee":null,"issue_type":"task","title":"wf husk","priority":3,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"cv-HUSK","gc.session_name":"gc-toolkit__polecat-lx-gone"}},
 {"id":"tk-rMANY","status":"open","assignee":null,"issue_type":"task","title":"wf many","priority":3,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"cv-MANY","gc.session_name":"gc-toolkit__polecat-lx-live"}},
 {"id":"tk-sSTEP","status":"open","assignee":null,"issue_type":"task","title":"a step","priority":3,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.root_bead_id":"tk-rLIVE","gc.step_ref":"mol-polecat-work.implement","gc.session_name":"gc-toolkit__polecat-lx-live"}},
 {"id":"tk-human","status":"open","assignee":null,"issue_type":"bug","title":"the operator owns this","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human"}},
 {"id":"tk-parked","status":"open","assignee":null,"issue_type":"task","title":"a parked conversation","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.takeaway":"nothing further needed here"}},
 {"id":"tk-eTAKE","status":"open","assignee":null,"issue_type":"epic","title":"epic that carries a takeaway","priority":1,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.takeaway":"an epic may carry one of these too"}},
 {"id":"tk-dHUMAN","status":"open","assignee":null,"issue_type":"decision","title":"decision routed to human","priority":1,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human"}},
 {"id":"tk-both","status":"open","assignee":null,"issue_type":"task","title":"routed to the operator AND parked","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human","gc.takeaway":"parked, and still owed to the operator"}},
 {"id":"tk-pdone","status":"open","assignee":null,"issue_type":"task","title":"routed, and the work has landed","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.takeaway":"routed — tk-blkC slung. Nothing further needed here."},
  "dependencies":[{"issue_id":"tk-pdone","depends_on_id":"tk-blkC","type":"blocks"}]},
 {"id":"tk-phold","status":"open","assignee":null,"issue_type":"task","title":"routed, and the work is still in flight","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.takeaway":"holding — awaiting tk-blkO"},
  "dependencies":[{"issue_id":"tk-phold","depends_on_id":"tk-blkO","type":"blocks"},
                  {"issue_id":"tk-phold","depends_on_id":"cv-LIVE","type":"tracks"}]},
 {"id":"tk-punk","status":"open","assignee":null,"issue_type":"task","title":"waiting on a bead this store cannot resolve","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.takeaway":"holding — awaiting sl-9999 over in another rig"},
  "dependencies":[{"issue_id":"tk-punk","depends_on_id":"sl-9999","type":"blocks"}]},
 {"id":"tk-pkids","status":"open","assignee":null,"issue_type":"task","title":"parked, and the work it routed is its own child","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.takeaway":"routed — next sitting when the findings land"}},
 {"id":"tk-pmove","status":"open","assignee":null,"issue_type":"task","title":"parked, and a child is being worked right now","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.takeaway":"routed — implementation in flight"}},
 {"id":"tk-pdone2","status":"open","assignee":null,"issue_type":"task","title":"parked, and every child has closed","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.takeaway":"routed — next sitting when the findings land"}},
 {"id":"tk-hkids","status":"open","assignee":null,"issue_type":"bug","title":"routed to the operator, and decomposed","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human"}},
 {"id":"tk-hASK","status":"open","assignee":null,"issue_type":"bug","title":"routed to the operator, with the ask stated","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human","blocked_reason":"PR#88 closed\n  out-of-band without merging"}},
 {"id":"tk-hBLANK","status":"open","assignee":null,"issue_type":"bug","title":"routed to the operator, ask field present but empty","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human","blocked_reason":"   "}},
 {"id":"tk-hRULED","status":"open","assignee":null,"issue_type":"bug","title":"routed to the operator, and answered","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human","gc.takeaway":"ruled — design settled; tk-blkC slung"},
  "dependencies":[{"issue_id":"tk-hRULED","depends_on_id":"tk-blkC","type":"blocks"}]},
 {"id":"tk-hRKIDS","status":"open","assignee":null,"issue_type":"bug","title":"answered, but its own child is stranded","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human","gc.takeaway":"ruled — the follow-up is filed under this bead"},
  "dependencies":[{"issue_id":"tk-hRKIDS","depends_on_id":"tk-blkC","type":"blocks"}]},
 {"id":"tk-hRDONE","status":"open","assignee":null,"issue_type":"bug","title":"answered, decomposed, and every child closed","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human","gc.takeaway":"ruled — all of it landed"},
  "dependencies":[{"issue_id":"tk-hRDONE","depends_on_id":"tk-blkC","type":"blocks"}]},
 {"id":"tk-hHOLD","status":"open","assignee":null,"issue_type":"bug","title":"answered, but the routed work is still open","priority":2,
  "updated_at":"2026-08-21T00:00:00Z","description":"",
  "metadata":{"gc.routed_to":"human","blocked_reason":"land it, or split the rest into follow-ups",
              "gc.takeaway":"ruled — tk-blkO slung, landing next"},
  "dependencies":[{"issue_id":"tk-hHOLD","depends_on_id":"tk-blkO","type":"blocks"}]}
]
J

# What `bd show <anchor ids> --include-dependents` answers with: the children
# of the metadata-keyed anchors, at ALL statuses, so n_closed is a real count.
# tk-pkids also carries a `tracks` dependent — the edge a convoy files, which
# points at the same bead and is NOT a child. Filtering to `parent-child` is
# the only thing that keeps it out of the roll-up.
cat > "$ITMP/dependents.json" <<'J'
[
 {"id":"tk-pkids","dependents":[
   {"id":"tk-kOPEN","status":"open","assignee":null,"dependency_type":"parent-child"},
   {"id":"tk-kDONE","status":"closed","assignee":null,"dependency_type":"parent-child"},
   {"id":"cv-TRACK","status":"in_progress","assignee":null,"dependency_type":"tracks"}]},
 {"id":"tk-pmove","dependents":[
   {"id":"tk-kMOVE","status":"in_progress","assignee":"gc-toolkit__polecat-lx-live","dependency_type":"parent-child"}]},
 {"id":"tk-pdone2","dependents":[
   {"id":"tk-kDONE1","status":"closed","assignee":null,"dependency_type":"parent-child"},
   {"id":"tk-kDONE2","status":"closed","assignee":null,"dependency_type":"parent-child"}]},
 {"id":"tk-hkids","dependents":[
   {"id":"tk-kHUM","status":"open","assignee":null,"dependency_type":"parent-child"}]},
 {"id":"tk-hRKIDS","dependents":[
   {"id":"tk-kRULE","status":"open","assignee":null,"dependency_type":"parent-child"}]},
 {"id":"tk-hRDONE","dependents":[
   {"id":"tk-kRD1","status":"closed","assignee":null,"dependency_type":"parent-child"},
   {"id":"tk-kRD2","status":"closed","assignee":null,"dependency_type":"parent-child"}]}
]
J

# What `bd show <blocker-ids>` answers with. tk-blkC has closed; tk-blkO has
# not; sl-9999 is deliberately ABSENT — the shape a cross-store or `external:`
# reference produces, which must read as still-waiting rather than as landed.
cat > "$ITMP/blockers.json" <<'J'
[
 {"id":"tk-blkC","status":"closed","title":"the routed fix","metadata":{}},
 {"id":"tk-blkO","status":"open","title":"the routed fix, still in flight","metadata":{}}
]
J

cat > "$ITMP/decisions.json" <<'J'
[{"id":"tk-dHUMAN","title":"decision routed to human","priority":1,"updated_at":"2026-08-21T00:00:00Z",
  "metadata":{"gc.routed_to":"human"}},
 {"id":"tk-dRULED","title":"a decision that has been answered","priority":1,"updated_at":"2026-07-01T00:00:00Z",
  "metadata":{"gc.takeaway":"ROUTED: excise the fork; tk-blkC slung"},
  "dependencies":[{"issue_id":"tk-dRULED","depends_on_id":"tk-blkC","type":"blocks"}]},
 {"id":"tk-dHOLD","title":"answered, but the routed work is still open","priority":1,"updated_at":"2026-08-21T00:00:00Z",
  "metadata":{"gc.takeaway":"answered NO — real bug is elsewhere, routed tk-blkO"},
  "dependencies":[{"issue_id":"tk-dHOLD","depends_on_id":"tk-blkO","type":"blocks"}]}]
J

# lx-live is active; lx-gone is ABSENT from the list entirely (the dead shape).
cat > "$ITMP/sessions.json" <<'J'
{"sessions":[{"session_name":"gc-toolkit__polecat-lx-live","alias":"gc-toolkit/gc-toolkit.furiosa","state":"active"}]}
J

cat > "$ITMP/bin/gc" <<'GCI'
#!/usr/bin/env bash
args="$*"
case "$1 ${2:-}" in
  "rig list")     jq -n --arg p "$FAKE_RIG_PATH" '{rigs:[{name:"gc-toolkit",path:$p,prefix:"tk"}]}' ;;
  "convoy list")  printf '{"convoys":[]}\n' ;;
  "session list") cat "$FAKE_SESSIONS" ;;
  "bd show")
    # Two batched `bd show` calls ride the board path, told apart by their
    # flags: gather_meta_anchors asks for --include-dependents (the children
    # roll-up of the metadata-keyed kinds), resolve_waiting_status asks for the
    # DISTINCT blocker ids of a rig with no such flag. Everything else is
    # unrelated and keeps answering empty.
    case "$args" in
      *--include-dependents*) cat "$FAKE_DEPENDENTS" ;;
      *tk-blk*|*sl-9999*)     cat "$FAKE_BLOCKERS" ;;
      *)                      printf '[]\n' ;;
    esac ;;
  "convoy status")
    case "$3" in
      cv-LIVE) jq -n '{children:[{id:"tk-wLIVE"}]}' ;;
      cv-HUSK) jq -n '{children:[{id:"tk-wHUSK"}]}' ;;
      # Two members: a shape the join does not understand. It must make NO
      # claim about movement rather than pick one.
      cv-MANY) jq -n '{children:[{id:"tk-wMANY"},{id:"tk-extra"}]}' ;;
      *)       printf '{"children":[]}\n' ;;
    esac ;;
  "bd list")
    case "$args" in
      *"--parent tk-eLIVE"*)  cat "$FAKE_DIR/kids-eLIVE.json" ;;
      *"--parent tk-eHUSK"*)  cat "$FAKE_DIR/kids-eHUSK.json" ;;
      *"--parent tk-eCLAIM"*) cat "$FAKE_DIR/kids-eCLAIM.json" ;;
      *"--parent tk-eMANY"*)  cat "$FAKE_DIR/kids-eMANY.json" ;;
      *"--parent tk-eTAKE"*)  cat "$FAKE_DIR/kids-eTAKE.json" ;;
      *"--type epic"*)        cat "$FAKE_EPICS" ;;
      *"--type decision"*)    cat "$FAKE_DIR/decisions.json" ;;
      *)                      cat "$FAKE_OPEN" ;;   # the shared snapshot
    esac ;;
esac
exit 0
GCI
chmod +x "$ITMP/bin/gc"

IRUN="$ITMP/run"; mkdir -p "$IRUN"
IRC=0
IOUT="$(env PATH="$ITMP/bin:$PATH" TMPDIR="$IRUN" \
            FAKE_RIG_PATH="$ITMP/rig" FAKE_EPICS="$ITMP/epics.json" \
            FAKE_OPEN="$ITMP/open.json" FAKE_SESSIONS="$ITMP/sessions.json" \
            FAKE_DIR="$ITMP" FAKE_BLOCKERS="$ITMP/blockers.json" \
            FAKE_DEPENDENTS="$ITMP/dependents.json" GC_HELM_FIXTURE= \
            sh "$SCRIPT" board --json --refresh --limit=0 2>"$IRUN/err")" || IRC=$?
IERR="$(cat "$IRUN/err" 2>/dev/null || true)"
eq "$IRC" "0" "(SCENARIO3) board renders (err: ${IERR:-none})"

# row <id> <field>
row() { printf '%s' "$IOUT" | jq -r --arg i "$1" --arg k "$2" \
        'first(.[]? | select(.id==$i)) | .[$k] | if .==null then "null" else tostring end' 2>/dev/null || true; }

# --- (INFLIGHT) the defect itself -------------------------------------------
eq "$(row tk-eLIVE stranded)"        "false"  "(INFLIGHT) a live workflow over an unclaimed child clears stranded"
eq "$(row tk-eLIVE in_progress_live)" "1"     "(INFLIGHT) the covered child counts as moving"
eq "$(row tk-eLIVE in_flight)"       "1"      "(INFLIGHT) it is attributed to the workflow, not to a claim"
eq "$(row tk-eLIVE in_progress)"     "0"      "(INFLIGHT) and the raw status count is still honestly zero"
eq "$(row tk-eLIVE severity)"        "NORMAL" "(INFLIGHT) the row leaves the HIGH attention band"
printf '%s' "$IOUT" | jq -e 'first(.[]?|select(.id=="tk-eLIVE")).frontier | test("1 in flight")' >/dev/null 2>&1 \
  && ok "(INFLIGHT) the frontier says in flight, not '0 in-progress (stranded)'" \
  || bad "(INFLIGHT) frontier still reads: $(row tk-eLIVE frontier)"

# --- (HUSK) the load-bearing guard ------------------------------------------
# 17 of 18 open roots in the live rig were husks when this was written. If root
# existence alone counted, every one of them would render a false all-clear.
eq "$(row tk-eHUSK stranded)"         "true" "(HUSK) a dead-session workflow does NOT clear stranded"
eq "$(row tk-eHUSK in_flight)"        "0"    "(HUSK) the husk contributes no in-flight movement"
eq "$(row tk-eHUSK severity)"         "HIGH" "(HUSK) the row stays in the attention band"
eq "$(row tk-eHUSK in_progress_dead)" "0"    "(HUSK) an unclaimed child is not a dead OWNER either"

# --- (CLAIMED) the pre-existing path is untouched ---------------------------
eq "$(row tk-eCLAIM stranded)"         "false" "(CLAIMED) claimed + live owner still counts as moving"
eq "$(row tk-eCLAIM in_progress_live)" "1"     "(CLAIMED) counted once"
eq "$(row tk-eCLAIM in_flight)"        "0"     "(CLAIMED) and attributed to the claim, not a workflow"

# --- (IDLEHEAD) covered work is not an idle head ----------------------------
printf '%s' "$IOUT" | jq -e 'first(.[]?|select(.id=="tk-eLIVE")).open_heads | index("tk-wLIVE") == null' >/dev/null 2>&1 \
  && ok "(IDLEHEAD) a workflow-covered child drops out of open_heads" \
  || bad "(IDLEHEAD) tk-wLIVE still listed as an idle head"
printf '%s' "$IOUT" | jq -e 'first(.[]?|select(.id=="tk-eHUSK")).open_heads | index("tk-wHUSK") != null' >/dev/null 2>&1 \
  && ok "(IDLEHEAD) a husk-covered child REMAINS an idle head" \
  || bad "(IDLEHEAD) tk-wHUSK wrongly dropped from open_heads"

# --- (ONEMEMBER) fail closed on a shape the walk does not understand --------
eq "$(row tk-eMANY stranded)" "true" "(ONEMEMBER) a convoy with 2 tracked members makes no movement claim"
eq "$(row tk-eMANY in_flight)" "0"   "(ONEMEMBER) nothing is guessed from the ambiguous convoy"

# --- (HUMAN) / (PARKED) the metadata-keyed kinds ----------------------------
eq "$(row tk-human kind)"     "human"    "(HUMAN) gc.routed_to=human reaches the board at all"
eq "$(row tk-human severity)" "ELEVATED" "(HUMAN) banded with the other human-gated rows"
eq "$(row tk-parked kind)"     "parked"  "(PARKED) a takeaway-bearing bead is findable"
eq "$(row tk-parked severity)" "LOW"     "(PARKED) floored — it wants nothing, it just has to be findable"

# --- (DISPO) the defect tk-2plde is about ------------------------------------
# The subject routed work out of a sitting and the work has since closed. The
# takeaway is FROZEN at dispatch time — it still says "nothing further needed
# here" — so the row has to be promoted by the EDGE, not by re-reading prose.
eq "$(row tk-pdone severity)" "ELEVATED" "(DISPO) a parked row whose blocker landed leaves the LOW floor"
eq "$(row tk-pdone disposition_due)" "true" "(DISPO) …and says so structurally, not just in a phrase"
eq "$(row tk-pdone frontier)" "parked · blocker landed" "(DISPO) the frontier names what changed"
eq "$(row tk-pdone needs)" "blocker landed — dispose or resume" \
   "(DISPO) the STALE takeaway is not the answer for this row"
eq "$(row tk-pdone waiting_on)" '["tk-blkC"]' "(DISPO) the wait is on the wire as an id, not as prose"
eq "$(row tk-pdone waiting_on_open)" '[]' "(DISPO) nothing outstanding"
# The takeaway itself is still carried — the row is promoted, not censored.
printf '%s' "$IOUT" | jq -e 'first(.[]?|select(.id=="tk-pdone")).takeaway | test("Nothing further needed")' >/dev/null 2>&1 \
  && ok "(DISPO) the takeaway stays on the wire for anyone reading the row" \
  || bad "(DISPO) the takeaway was dropped: $(row tk-pdone takeaway)"

# --- (LIVEHOLD) the case that must stay quiet --------------------------------
# A genuine hold: the work it is waiting on is still open. Promoting this would
# reintroduce the noise the LOW floor exists to prevent.
eq "$(row tk-phold severity)" "LOW" "(LIVEHOLD) a hold whose work is still in flight stays floored"
eq "$(row tk-phold disposition_due)" "false" "(LIVEHOLD) …and owes no disposition"
eq "$(row tk-phold frontier)" "parked · waiting on 1" "(LIVEHOLD) the frontier counts what is outstanding"
eq "$(row tk-phold needs)" "holding — awaiting tk-blkO" "(LIVEHOLD) its takeaway still answers for it"
eq "$(row tk-phold waiting_on)" '["tk-blkO"]' "(LIVEHOLD) only blocks edges count — a tracks edge is not a wait"

# --- (BAREPARK) every parked row in the city today ---------------------------
# No edges have been written yet, so this is the shape the change must leave
# byte-identical or it is a regression dressed as a feature.
eq "$(row tk-parked disposition_due)" "false" "(BAREPARK) no edges is not a discharged wait"
eq "$(row tk-parked frontier)" "conversation parked — takeaway recorded" \
   "(BAREPARK) an edgeless parked row renders exactly as before"
eq "$(row tk-parked waiting_on)" '[]' "(BAREPARK) the field is an empty ARRAY, never null (jq/Go parity)"
eq "$(row tk-parked m_total)" "0" "(BAREPARK) a childless parked row still rolls up nothing"
eq "$(row tk-parked severity)" "LOW" "(BAREPARK) …and keeps the floor"

# --- (PKIDS) the defect tk-a9k0l is about ------------------------------------
# The canonical converse shape: the sitting filed the work it routed as a CHILD
# of the subject. That work can never be a `waiting_on` edge — `bd` refuses a
# parent→descendant `blocks` edge (tk-2cyxo) — so `children` is the ONLY
# relation that can see it. The gather used to hardcode `children:[]`, which
# reported zero children AND, because a plain bead reaches the board only
# through its parent's roll-up, deleted the open child from every surface.
eq "$(row tk-pkids kind)"     "parked" "(PKIDS) it is still a parked conversation"
eq "$(row tk-pkids m_total)"  "2"      "(PKIDS) its children are counted, not hardcoded away"
eq "$(row tk-pkids n_closed)" "1"      "(PKIDS) …at all statuses, so n_closed is real"
eq "$(row tk-pkids open)"     "1"      "(PKIDS) …and the open frontier is visible"
eq "$(row tk-pkids open_heads)" '["tk-kOPEN"]' "(PKIDS) the open child is nameable from the row"
eq "$(row tk-pkids severity)" "HIGH"   "(PKIDS) the LOW floor does not survive open work under it"
eq "$(row tk-pkids stranded)" "true"   "(PKIDS) …because the frontier is genuinely stranded"
eq "$(row tk-pkids frontier)" "1 open · 0 in flight (stranded)" \
   "(PKIDS) and the frontier explains the band it was given"
# A convoy files a `tracks` edge that points at the same bead. It is a
# membership edge, not a child, and counting it would inflate every roll-up.
# cv-TRACK is in_progress on purpose: drop the `parent-child` filter and this
# row reads m_total=3 with one in-progress child, so the assertion can only
# pass while the filter is there.
eq "$(row tk-pkids in_progress)" "0" "(TRACKSEDGE) a tracks dependent is not a child"

# --- (PMOVE) the same row, with the work actually moving ---------------------
eq "$(row tk-pmove severity)" "NORMAL" "(PMOVE) a parked subject whose child is being worked is active, not floored"
eq "$(row tk-pmove frontier)" "1 open · 1 in flight" "(PMOVE) …and says what is moving"

# --- (PALLDONE) the state tk-2cyxo has to be able to see ---------------------
# Every child closed. The band is LOW either way, so this is not about ranking:
# it is about the row being able to SAY that the work it routed has landed.
# Before the fix "never decomposed" and "decomposed, all landed" were the same
# m_total=0 row, and no sweep could tell them apart.
eq "$(row tk-pdone2 m_total)"  "2"    "(PALLDONE) a finished roll-up is still reported"
eq "$(row tk-pdone2 n_closed)" "2"    "(PALLDONE) …and reads as complete"
eq "$(row tk-pdone2 complete)" "true" "(PALLDONE) …structurally, not just in a phrase"
eq "$(row tk-pdone2 severity)" "LOW"  "(PALLDONE) promoting this row is tk-2cyxo's call, not this one's"
eq "$(row tk-pdone2 frontier)" "all 2 closed · 0 open" "(PALLDONE) the frontier stops claiming it wants nothing"

# --- (HKIDS) the same hole on the other metadata-keyed kind ------------------
eq "$(row tk-hkids m_total)"  "1"        "(HKIDS) a human-routed bead rolls up its children too"
eq "$(row tk-hkids severity)" "ELEVATED" "(HKIDS) …and its band still comes from the marker, not the counts"

# --- (ASK) a human row spends the ask its router recorded (tk-wfufb9) --------
# The census that filed it: nine ELEVATED rows whose entire NEEDS cell was the
# constant "operator action", roughly half of them ordinary agent work parked in
# the operator band because nobody had claimed it. A constant cannot tell those
# apart, so the cell answers from the bead instead — the ask `blocked_reason`
# carries, or the fact that no ask was recorded, which is itself the bug.
eq "$(row tk-hASK needs)" "PR#88 closed out-of-band without merging"    "(ASK) the NEEDS cell is the recorded ask, not a constant"
eq "$(row tk-hASK frontier)" "routed to the operator — no agent will take it"    "(ASK) …and a justified route keeps the claim it earned"
eq "$(row tk-hASK severity)" "ELEVATED"    "(ASK) …at the band it already had — being justified is not being answered"
# Collapsed like a takeaway: blocked_reason is free prose a writer may have
# wrapped, and one stray newline breaks the table for every row below it.
printf '%s' "$IOUT" | jq -e '[.[]?|select(.id=="tk-hASK")|.needs|test("\n")]|any|not' >/dev/null 2>&1   && ok "(ASK) …and a wrapped ask reaches the table collapsed"   || bad "(ASK) a newline survived into the NEEDS cell"

# The marker alone. Three of the nine census rows looked exactly like this.
eq "$(row tk-hkids needs)" "unexplained human route — state the ask or return it to the pool"    "(ASK) a bare marker NAMES the omission — and outranks the roll-up it has"
eq "$(row tk-hkids frontier)" "routed to the operator — no ask recorded"    "(ASK) …and the frontier stops asserting a claim nobody made"
# Present-but-empty is not an ask: blocked_reason is often built by
# interpolation, and an empty interpolation leaves a field that says nothing.
eq "$(row tk-hBLANK needs)" "unexplained human route — state the ask or return it to the pool"    "(ASK) a whitespace-only ask is no ask"
eq "$(row tk-hBLANK severity)" "ELEVATED"    "(ASK) …and an unexplained row is NOT quietly demoted off the board"

# --- (PRANK) the floor was the thing hiding it ------------------------------
PK_SCORE="$(row tk-pkids rank_score)"; BARE_SCORE="$(row tk-parked rank_score)"
case "${PK_SCORE}${BARE_SCORE}" in
  ''|*[!0-9]*) bad "(PRANK) a rank_score is missing or non-numeric (pkids='$PK_SCORE' bare='$BARE_SCORE')" ;;
  *) [ "$PK_SCORE" -gt "$BARE_SCORE" ] \
       && ok "(PRANK) a decomposed parked row outranks a floored one ($PK_SCORE > $BARE_SCORE)" \
       || bad "(PRANK) the decomposed row is still floored ($PK_SCORE <= $BARE_SCORE)" ;;
esac

# --- (FAILCLOSE) the direction to be wrong in --------------------------------
# sl-9999 is absent from the blocker read — a cross-store id, an `external:`
# ref, or a query that died. Reading absence as "closed" would tell the operator
# to dispose of a subject whose work is still in flight.
eq "$(row tk-punk disposition_due)" "false" "(FAILCLOSE) an unresolvable blocker never reads as landed"
eq "$(row tk-punk severity)" "LOW" "(FAILCLOSE) …so the row keeps its pre-fix band"
eq "$(row tk-punk waiting_on_open)" '["sl-9999"]' "(FAILCLOSE) …and it is still counted outstanding"

# --- (RULED) the defect tk-b3rga is about ------------------------------------
# The row was ANSWERED and went on demanding the operator anyway, because the
# band came from the kind and the kind never changes. tk-dRULED is the shape of
# tk-z130v: ruled on 2026-07-01 against a fixture clock in August, so it is also
# the proof that a stood-down row is not re-elevated by the staleness bump.
eq "$(row tk-dRULED severity)" "LOW" "(RULED) an answered decision leaves the attention band"
eq "$(row tk-dRULED frontier)" "ruled — takeaway recorded" "(RULED) the frontier says the row was answered"
eq "$(row tk-dRULED needs)" "ruled — close or extend" "(RULED) …and NEEDS names the disposition it now wants"
eq "$(row tk-dRULED waiting_on)" '["tk-blkC"]' "(RULED) the decision gather carries its blocks edges at all"
eq "$(row tk-dRULED waiting_on_open)" '[]' "(RULED) …and nothing is outstanding"
# The ruling itself is not censored — it is still on the wire for the reader.
printf '%s' "$IOUT" | jq -e 'first(.[]?|select(.id=="tk-dRULED")).takeaway | test("excise the fork")' >/dev/null 2>&1 \
  && ok "(RULED) the takeaway survives the stand-down" \
  || bad "(RULED) the takeaway was dropped: $(row tk-dRULED takeaway)"
# LOW is not stale-bumped; NORMAL would be, and tk-z130v would be back tomorrow.
STALE_D="$(row tk-dRULED stale_days)"
case "$STALE_D" in
  ''|*[!0-9]*) bad "(RULED) stale_days is missing or non-numeric ('$STALE_D')" ;;
  *) [ "$STALE_D" -gt 14 ] \
       && ok "(RULED) …and it is genuinely stale ($STALE_D days), so the band is holding it down" \
       || bad "(RULED) the fixture is not stale enough to prove the bump does not fire ($STALE_D days)" ;;
esac
# The same state on the other human-gated kind.
eq "$(row tk-hRULED severity)" "LOW" "(RULED) a human-routed bead stands down the same way"
eq "$(row tk-hRULED needs)" "ruled — close or extend" "(RULED) …with the same disposition phrase"

# --- (RULEHOLD) the guard that keeps the rule honest -------------------------
# "Answered" is not "answered and the work landed". A decision whose
# `--waiting-on` work is still open has not finished being a decision. This is
# also the only assertion that can fail if the waiting edges stop being
# gathered for these kinds — without them the clause is vacuously true and
# every answered row stands down whether or not its work landed.
eq "$(row tk-dHOLD severity)" "ELEVATED" "(RULEHOLD) a live wait keeps the row in the band"
eq "$(row tk-dHOLD frontier)" "human-gated decision" "(RULEHOLD) …and its frontier is unchanged"
eq "$(row tk-dHOLD waiting_on_open)" '["tk-blkO"]' "(RULEHOLD) the outstanding blocker is named"
eq "$(row tk-dHOLD needs)" "answered NO — real bug is elsewhere, routed tk-blkO" \
   "(RULEHOLD) its takeaway still answers for it"
# The same guard on the human kind — and the ONLY assertion in this suite that
# can see whether the META gather still reads waiting edges for `human`. Nothing
# else can: every other human fixture here has its waits already discharged, so
# dropping the edges leaves waiting_on_open empty either way and the rows stand
# down for the wrong reason. Here the edge is what holds the row up.
eq "$(row tk-hHOLD severity)" "ELEVATED" "(RULEHOLD) a human row whose routed work is open keeps its band"
eq "$(row tk-hHOLD waiting_on)" '["tk-blkO"]' "(RULEHOLD) …because the meta gather carries its blocks edges"
eq "$(row tk-hHOLD waiting_on_open)" '["tk-blkO"]' "(RULEHOLD) …and the blocker is still outstanding"
eq "$(row tk-hHOLD frontier)" "routed to the operator — no agent will take it" \
   "(RULEHOLD) …so its frontier is unchanged too"
# And the unanswered rows are untouched: no takeaway, no stand-down.
eq "$(row tk-human severity)" "ELEVATED" "(RULEHOLD) an unanswered human row keeps its band"
eq "$(row tk-dHUMAN severity)" "ELEVATED" "(RULEHOLD) …and so does an unanswered decision"

# --- (RULEKIDS) a ruling is not a new way to hide open work ------------------
# The tk-a9k0l lesson, one kind over: "answered" is a claim about the BEAD, and
# open work hanging under it falsifies the claim. A ruled row that DECOMPOSED is
# banded by its roll-up like any other anchor.
eq "$(row tk-hRKIDS severity)" "HIGH" "(RULEKIDS) a stranded child outranks the ruling"
eq "$(row tk-hRKIDS stranded)" "true" "(RULEKIDS) …structurally, not just in a phrase"
eq "$(row tk-hRKIDS frontier)" "1 open · 0 in flight (stranded)" \
   "(RULEKIDS) the frontier reports the roll-up, not the ruling"
eq "$(row tk-hRKIDS needs)" "ruled — the follow-up is filed under this bead" \
   "(RULEKIDS) NEEDS falls back to the takeaway, never to a bare close-or-extend"

# --- (RULETWIN) the dedup would hand the band straight back ------------------
# A bead carrying BOTH gc.routed_to=human and gc.takeaway is gathered once per
# marker, and the dedup keeps the HIGHER band. So the `parked` twin of a
# stood-down row must stand down with it: with a discharged wait the twin would
# otherwise be promoted by the disposition rule and win, on every row this fix
# was written for. tk-hRDONE decomposed with all children closed — the shape of
# sl-kg9z6.1.2 — because the childless twin is already caught one branch above.
eq "$(printf '%s' "$IOUT" | jq -r '[.[]?|select(.id=="tk-hRDONE")]|length')" "1" \
   "(RULETWIN) the doubly-marked bead still renders exactly once"
eq "$(row tk-hRDONE severity)" "LOW" "(RULETWIN) …and the twin does not re-elevate it"
eq "$(row tk-hRDONE disposition_due)" "false" \
   "(RULETWIN) a human-gated subject owes its disposition through the ruled row"
eq "$(row tk-hRDONE m_total)" "2" "(RULETWIN) the roll-up is still reported"
# tk-2plde intact: a parked row that is NOT human-gated keeps its promotion.
eq "$(row tk-pdone severity)" "ELEVATED" "(RULETWIN) a plain parked row still leaves the floor"
eq "$(row tk-pdone disposition_due)" "true" "(RULETWIN) …and still says so"

# --- (EXCLUDE) the typed kinds are not re-gathered by metadata --------------
eq "$(printf '%s' "$IOUT" | jq -r '[.[]?|select(.id=="tk-eTAKE")]|length')" "1" \
   "(EXCLUDE) an epic carrying a takeaway appears exactly once"
eq "$(row tk-eTAKE kind)" "epic" "(EXCLUDE) …and stays kind epic, not parked"
eq "$(printf '%s' "$IOUT" | jq -r '[.[]?|select(.id=="tk-dHUMAN")]|length')" "1" \
   "(EXCLUDE) a decision routed to human appears exactly once"
eq "$(row tk-dHUMAN kind)" "decision" "(EXCLUDE) …and stays kind decision, not human"

eq "$(printf '%s' "$IOUT" | jq -r '[.[]?|select(.id=="tk-both")]|length')" "1" \
   "(BOTH) …and renders exactly once after dedup"
eq "$(row tk-both kind)"     "human"    "(BOTH) the human reading wins the row"
# SUPERSEDED by tk-b3rga, deliberately. This row used to assert ELEVATED — "an
# owed-to-the-operator bead is not floored by its takeaway" — which is exactly
# the behaviour the operator ruled against on 2026-08-23: a takeaway on a
# human-gated bead RECORDS the answer, and a row that keeps demanding an
# operator who already answered it is the single largest false contributor to
# the board. tk-both carries a takeaway and no outstanding wait, which is the
# same shape as tk-z130v — the thirty-day regression case the rule is named for.
eq "$(row tk-both severity)" "LOW"       "(BOTH) an answered bead stands down, whichever marker gathered it"

# --- (FLOOR) a parked row never competes with real attention ----------------
# Guard the comparison on both scores being REAL numbers first. Defaulting a
# missing score to 0 would let this pass when the parked row does not exist at
# all — which is precisely the state before the fix, so the assertion would
# have certified the bug as compliant.
PARKED_SCORE="$(row tk-parked rank_score)"; HUSK_SCORE="$(row tk-eHUSK rank_score)"
case "${PARKED_SCORE}${HUSK_SCORE}" in
  ''|*[!0-9]*) bad "(FLOOR) a rank_score is missing or non-numeric (parked='$PARKED_SCORE' husk='$HUSK_SCORE')" ;;
  *) [ "$PARKED_SCORE" -lt "$HUSK_SCORE" ] \
       && ok "(FLOOR) parked ranks below a stranded epic ($PARKED_SCORE < $HUSK_SCORE)" \
       || bad "(FLOOR) parked outranked a stranded epic ($PARKED_SCORE >= $HUSK_SCORE)" ;;
esac

# --- (MAPGATHER) the gather-side filter, asserted on its own output ----------
# The two liveness checks (gather-side, render-side) each mask the other under
# a single end-to-end assertion: mutate either one alone and the board still
# reads correctly, because the other still refuses the husk. So each is pinned
# by a test that can only see THAT layer. Here: the map the gather produced,
# read straight off the cache it wrote. A dead root must never have had its
# convoy resolved at all.
ICACHE="$(find "$IRUN" -name 'board2-*.ndjson' 2>/dev/null | head -1)"
if [ -n "$ICACHE" ] && [ -s "$ICACHE" ]; then
    IMAP="$(sed -n '3p' "$ICACHE")"
    printf '%s' "$IMAP" | jq -e 'has("tk-wLIVE")' >/dev/null 2>&1 \
      && ok "(MAPGATHER) the live workflow's member is in the in-flight map" \
      || bad "(MAPGATHER) tk-wLIVE missing from the map: $IMAP"
    printf '%s' "$IMAP" | jq -e 'has("tk-wHUSK") | not' >/dev/null 2>&1 \
      && ok "(MAPGATHER) the dead workflow's convoy was never resolved" \
      || bad "(MAPGATHER) a husk reached the in-flight map: $IMAP"
    printf '%s' "$IMAP" | jq -e 'has("tk-wMANY") | not' >/dev/null 2>&1 \
      && ok "(MAPGATHER) the ambiguous convoy was never resolved" \
      || bad "(MAPGATHER) a 2-member convoy reached the map: $IMAP"

    # (EXCLGATHER) the type exclusion, asserted where it happens. Counting rows
    # in the RENDERED board cannot see it: the render dedups by id, so a
    # doubly-gathered epic collapses back to one row and the assertion passes
    # whether or not the exclusion ran. The gathered anchor set is lines 4.. of
    # the same cache, before any dedup.
    GATHERED="$(tail -n +4 "$ICACHE" 2>/dev/null | jq -s -c '.' 2>/dev/null || printf '[]')"
    eq "$(printf '%s' "$GATHERED" | jq -r '[.[]|select(.id=="tk-eTAKE")]|length')" "1" \
       "(EXCLGATHER) an epic carrying a takeaway is gathered ONCE, not also as parked"
    eq "$(printf '%s' "$GATHERED" | jq -r '[.[]|select(.id=="tk-dHUMAN")]|length')" "1" \
       "(EXCLGATHER) a decision routed to human is gathered ONCE, not also as human"
    eq "$(printf '%s' "$GATHERED" | jq -r '[.[]|select(.id=="tk-parked")]|length')" "1" \
       "(EXCLGATHER) …while a non-typed bead still gathers exactly once"
    # (BOTH) a bead carrying BOTH markers is emitted twice ON PURPOSE — the two
    # kinds are independent claims — and the render's id-dedup collapses it to
    # the higher band. Asserted on both sides of that dedup, because each half
    # is invisible from the other: the gather count cannot see which band won,
    # and the rendered row cannot see that two were produced.
    eq "$(printf '%s' "$GATHERED" | jq -r '[.[]|select(.id=="tk-both")]|length')" "2" \
       "(BOTH) a bead with both markers is gathered under both kinds"
else
    bad "(MAPGATHER) no cache written — cannot inspect the gathered map"
fi

# --- (NMCOL) the human table, where the operator actually reads it -----------
# The N/M cell printed "—" for every human/parked row by KIND. That is right
# for a row with no roll-up and a lie over a real child set — and the table is
# the surface the operator glances at, so the JSON being correct is not enough.
ITAB="$(env PATH="$ITMP/bin:$PATH" TMPDIR="$IRUN" \
            FAKE_RIG_PATH="$ITMP/rig" FAKE_EPICS="$ITMP/epics.json" \
            FAKE_OPEN="$ITMP/open.json" FAKE_SESSIONS="$ITMP/sessions.json" \
            FAKE_DIR="$ITMP" FAKE_BLOCKERS="$ITMP/blockers.json" \
            FAKE_DEPENDENTS="$ITMP/dependents.json" GC_HELM_FIXTURE= \
            sh "$SCRIPT" board --refresh --limit=0 2>/dev/null)" || true
# The held glyph is a bare space on an unheld row, so the column index shifts
# by one under awk's whitespace splitting. Find the ID cell instead (it is
# field 1 or 2, and rpad never truncates it) and step three fields to N/M:
# ID, RIG, KIND, N/M.
tabcell() { printf '%s' "$ITAB" | awk -v id="$1" '{for(i=1;i<=2;i++) if($i==id){print $(i+3); exit}}'; }
[ -n "$ITAB" ] && ok "(NMCOL) the human table rendered" || bad "(NMCOL) the human table did not render"
eq "$(tabcell tk-pkids)"  "1/2" "(NMCOL) a decomposed parked row prints its real count"
eq "$(tabcell tk-parked)" "—"   "(NMCOL) …while a childless one still prints —"
eq "$(tabcell tk-hkids)"  "0/1" "(NMCOL) the same on a human-routed row"
eq "$(tabcell tk-dHUMAN)" "—"   "(NMCOL) a decision never has a roll-up to print"

# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 4 — the RENDER-side liveness re-check, isolated (tk-fkeft)
#
# The map is CACHED (45s) but session state is not: it is re-read every glance
# precisely so a polecat that drained mid-TTL stops counting as movement at
# once. That re-check is the correctness guarantee — the gather-side filter is
# an optimisation that bounds convoy reads — and scenario 3 cannot see it,
# because there the gather has already dropped the dead root before the render
# ever runs.
#
# So drive the render directly through GC_HELM_FIXTURE with a map that CONTAINS
# both a live-session entry and dead-session ones. Only liveness separates them.
# ══════════════════════════════════════════════════════════════════════════════

FTMP="$TMP/fixture"; mkdir -p "$FTMP/fx" "$FTMP/bin" "$FTMP/run"
cat > "$FTMP/fx/anchors.ndjson" <<'J'
{"id":"tk-fLIVE","title":"live","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":1,"updated_at":"2026-08-21T00:00:00Z","description":"","progress":null,"takeaway":"","takeaway_at":"","takeaway_by":"","children":[{"id":"tk-fw1","status":"open","assignee":null}]}
{"id":"tk-fGONE","title":"absent owner","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":1,"updated_at":"2026-08-21T00:00:00Z","description":"","progress":null,"takeaway":"","takeaway_at":"","takeaway_by":"","children":[{"id":"tk-fw2","status":"open","assignee":null}]}
{"id":"tk-fARCH","title":"archived owner","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":1,"updated_at":"2026-08-21T00:00:00Z","description":"","progress":null,"takeaway":"","takeaway_at":"","takeaway_by":"","children":[{"id":"tk-fw3","status":"open","assignee":null}]}
J
printf '[]\n' > "$FTMP/fx/visits.json"
# All three children ARE in the map. tk-fw1's session is active; tk-fw2's is
# absent from the session list entirely; tk-fw3's is archived.
cat > "$FTMP/fx/inflight.json" <<'J'
{"tk-fw1":["sess-alive"],"tk-fw2":["sess-absent"],"tk-fw3":["sess-archived"]}
J
cat > "$FTMP/fx/sessions.json" <<'J'
{"sessions":[{"session_name":"sess-alive","alias":"a","state":"active"},
             {"session_name":"sess-archived","alias":"b","state":"archived"}]}
J
cat > "$FTMP/bin/gc" <<'GCF'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "rig list") jq -n '{rigs:[{name:"gc-toolkit",path:"/nonexistent",prefix:"tk"}]}' ;;
  *)          printf '[]\n' ;;
esac
exit 0
GCF
chmod +x "$FTMP/bin/gc"

FRC=0
FOUT="$(env PATH="$FTMP/bin:$PATH" TMPDIR="$FTMP/run" GC_HELM_FIXTURE="$FTMP/fx" \
            sh "$SCRIPT" board --json --limit=0 2>"$FTMP/err")" || FRC=$?
eq "$FRC" "0" "(SCENARIO4) fixture board renders (err: $(cat "$FTMP/err" 2>/dev/null || true))"
frow() { printf '%s' "$FOUT" | jq -r --arg i "$1" --arg k "$2" \
         'first(.[]? | select(.id==$i)) | .[$k] | if .==null then "null" else tostring end' 2>/dev/null || true; }

eq "$(frow tk-fLIVE stranded)"  "false" "(RENDERLIVE) a mapped child with an ACTIVE session counts as moving"
eq "$(frow tk-fLIVE in_flight)" "1"     "(RENDERLIVE) …and is attributed to the workflow"
eq "$(frow tk-fGONE stranded)"  "true"  "(RENDERLIVE) a mapped child whose session is ABSENT does not count"
eq "$(frow tk-fGONE in_flight)" "0"     "(RENDERLIVE) …and contributes no in-flight movement"
eq "$(frow tk-fARCH stranded)"  "true"  "(RENDERLIVE) a mapped child whose session is ARCHIVED does not count"
eq "$(frow tk-fARCH in_flight)" "0"     "(RENDERLIVE) …and contributes no in-flight movement either"

# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 5 — the row cap must not re-hide what the parked kind surfaces
#
# Parked is band-floored to LOW, so it sorts LAST. Under one shared cap it is
# therefore the first thing trimmed — and the operator's own surface asks for
# 36 rows (tmux-pick-helm.sh:64) against a board whose attention bands alone
# fill most of that. Measured on the live city while this was written: at
# --limit=36 under a shared cap, 0 of 17 parked rows survived. A bead added to
# the gather so it could be FOUND would have been absent from the only board
# the operator reads — defect (b) fixed in the gather and undone in the cap.
#
# So parked draws on its own budget. Attention rows keep the whole of --limit.
# ══════════════════════════════════════════════════════════════════════════════

CTMP="$TMP/cap"; mkdir -p "$CTMP/fx" "$CTMP/bin" "$CTMP/run"
# 5 stranded epics (attention, HIGH) + 8 parked beads.
{
  for i in 1 2 3 4 5; do
    printf '{"id":"tk-cap-e%s","title":"epic %s","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":1,"updated_at":"2026-08-21T00:00:00Z","description":"","progress":null,"takeaway":"","takeaway_at":"","takeaway_by":"","children":[{"id":"tk-cap-k%s","status":"open","assignee":null}]}\n' "$i" "$i" "$i"
  done
  for i in 1 2 3 4 5 6 7 8; do
    printf '{"id":"tk-cap-p%s","title":"parked %s","kind":"parked","source":"parked","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-08-21T00:00:00Z","description":"","progress":null,"takeaway":"a takeaway","takeaway_at":"","takeaway_by":"converse","children":[]}\n' "$i" "$i"
  done
} > "$CTMP/fx/anchors.ndjson"
printf '[]\n' > "$CTMP/fx/visits.json"
printf '{}\n'  > "$CTMP/fx/inflight.json"
printf '{"sessions":[]}\n' > "$CTMP/fx/sessions.json"
cp "$FTMP/bin/gc" "$CTMP/bin/gc"

# cap_run <limit> <max_parked> -> COUT
cap_run() {
    COUT="$(env PATH="$CTMP/bin:$PATH" TMPDIR="$CTMP/run" GC_HELM_FIXTURE="$CTMP/fx" \
                GC_HELM_MAX_PARKED="$2" \
                sh "$SCRIPT" board --json --limit="$1" 2>/dev/null || printf '[]')"
}
ckind() { printf '%s' "$COUT" | jq -r --arg k "$1" '[.[]?|select(.kind==$k)]|length' 2>/dev/null || echo 0; }

# --limit=3 with a parked budget of 2: attention keeps its FULL 3.
cap_run 3 2
eq "$(ckind epic)"   "3" "(CAPSPLIT) attention rows get the whole of --limit, undiminished by parked"
eq "$(ckind parked)" "2" "(CAPSPLIT) parked rows draw on their own budget"
eq "$(printf '%s' "$COUT" | jq -r 'length')" "5" "(CAPSPLIT) the board is attention + parked, not one shared cap"

# The regression this guards: a parked budget of 0 is the old shared-cap shape.
cap_run 3 0
eq "$(ckind epic)"   "3" "(CAPSPLIT) …attention unaffected when parked is budgeted to zero"
eq "$(ckind parked)" "0" "(CAPSPLIT) …and parked can still be switched off explicitly"

# Ranking is preserved across the merge: every attention row outranks every
# parked row, so the re-merged array is still globally rank-ordered.
cap_run 5 8
printf '%s' "$COUT" | jq -e '[.[].rank_score] as $r | $r == ($r | sort | reverse)' >/dev/null 2>&1 \
  && ok "(CAPSPLIT) the merged board is still sorted by rank_score" \
  || bad "(CAPSPLIT) merge broke the global rank order"
eq "$(printf '%s' "$COUT" | jq -r '[.[]?|select(.kind=="epic")]|length')" "5" "(CAPSPLIT) all 5 attention rows at limit=5"
eq "$(printf '%s' "$COUT" | jq -r '[.[]?|select(.kind=="parked")]|length')" "8" "(CAPSPLIT) all 8 parked rows at a budget of 8"

# --limit=0 means ALL, both kinds, regardless of the parked budget.
cap_run 0 2
eq "$(printf '%s' "$COUT" | jq -r 'length')" "13" "(CAPSPLIT) --limit=0 is uncapped for both kinds"

# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 6 — the NEEDS cell is bounded in the TABLE and whole on the WIRE
#
# The write gate (scenario 1) is the cure; this is the backstop. 22 oversized
# takeaways are already stored, nothing re-renders a stamp, and a paragraph in
# NEEDS is not a wide cell — NEEDS is the last column, so the row simply wraps
# over every row below it and the table stops being one.
#
# The two halves must be pinned separately because each hides the other under a
# single assertion: clip the derived model instead of the cell and the table
# still looks right while `--json` quietly loses text; leave the table alone and
# the wire still looks right. So: same board, rendered both ways.
#
#   (CLIP)      an oversized takeaway renders as exactly 140 chars ending in …
#   (CLIPROW)   …so the whole rendered row is bounded — the defect itself,
#               since a 490-column row is what wraps over the rows below it
#   (CLIPFITS)  a conforming 140-char takeaway renders in FULL, no ellipsis
#   (CLIPPHRASE) a deterministic state phrase is untouched
#   (CLIPWIRE)  --json still carries the whole string, in `needs` AND `takeaway`
# ══════════════════════════════════════════════════════════════════════════════

NTMP="$TMP/needs"; mkdir -p "$NTMP/fx" "$NTMP/bin" "$NTMP/run"
# Filler is Z: it appears in no id, rig, severity, kind or frontier on this
# board, so "everything from the first Z" is exactly the NEEDS cell.
Z400="$(printf 'Z%.0s' {1..400})"
Z140="$(printf 'Z%.0s' {1..140})"
{
  printf '{"id":"tk-clip-long","title":"paragraph takeaway","kind":"parked","source":"parked","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-08-21T00:00:00Z","description":"","progress":null,"takeaway":"%s","takeaway_at":"","takeaway_by":"converse","children":[]}\n' "$Z400"
  printf '{"id":"tk-clip-fits","title":"conforming takeaway","kind":"parked","source":"parked","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-08-21T00:00:00Z","description":"","progress":null,"takeaway":"%s","takeaway_at":"","takeaway_by":"converse","children":[]}\n' "$Z140"
  printf '{"id":"tk-clip-plain","title":"no takeaway","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":1,"updated_at":"2026-08-21T00:00:00Z","description":"","progress":null,"takeaway":"","takeaway_at":"","takeaway_by":"","children":[]}\n'
} > "$NTMP/fx/anchors.ndjson"
printf '[]\n' > "$NTMP/fx/visits.json"
printf '{}\n'  > "$NTMP/fx/inflight.json"
printf '{"sessions":[]}\n' > "$NTMP/fx/sessions.json"
cp "$FTMP/bin/gc" "$NTMP/bin/gc"

nboard() {
    env PATH="$NTMP/bin:$PATH" TMPDIR="$NTMP/run" GC_HELM_FIXTURE="$NTMP/fx" \
        sh "$SCRIPT" board --limit=0 "$@" 2>"$NTMP/err"
}
NTAB="$(nboard || true)"
NJSON="$(nboard --json || printf '[]')"
# The NEEDS cell of a row: nothing to its left on this board contains a Z.
ncell() { grep -- "$1" <<< "$NTAB" | head -1 | sed 's/^[^Z]*//' || true; }
nlen()  { printf '%s' "$1" | jq -Rsr 'length' 2>/dev/null || printf 'ERR'; }

LONGCELL="$(ncell tk-clip-long)"
eq "$(nlen "$LONGCELL")" "140" "(CLIP) an oversized takeaway is bounded to 140 chars in the table"
case "$LONGCELL" in
  *…) ok "(CLIP) …and the cut is marked, so a clipped cell says it was clipped" ;;
  *)  bad "(CLIP) the cell was cut with no ellipsis: '${LONGCELL: -20}'" ;;
esac
# The defect is measured on the WHOLE row, not the cell: this row printed 490
# columns before the bound, which is three wrapped lines on a wide terminal and
# five on a normal one. The fixed columns ahead of NEEDS come to 90 here, so a
# bounded row lands at 230; 240 leaves room for the id/rig columns to size
# themselves without turning this into a layout assertion.
NROWLEN="$(nlen "$(grep -- 'tk-clip-long' <<< "$NTAB" | head -1 || true)")"
case "$NROWLEN" in
  ''|*[!0-9]*) bad "(CLIPROW) could not measure the rendered row (got '$NROWLEN')" ;;
  *) [ "$NROWLEN" -le 240 ] \
       && ok "(CLIPROW) the whole rendered row is bounded ($NROWLEN columns)" \
       || bad "(CLIPROW) the row is $NROWLEN columns — it wraps over the rows below it" ;;
esac
eq "$(grep -c -- 'tk-clip-long' <<< "$NTAB" || true)" "1" \
   "(CLIPROW) …and the bound does not split it into two lines"

eq "$(nlen "$(ncell tk-clip-fits)")" "140" \
   "(CLIPFITS) a conforming 140-char takeaway renders in full"
case "$(ncell tk-clip-fits)" in
  *…) bad "(CLIPFITS) a conforming headline was clipped anyway" ;;
  *)  ok "(CLIPFITS) …and is not marked as clipped, because it was not" ;;
esac

grep -q 'no children — decompose or assign' < <(grep -- 'tk-clip-plain' <<< "$NTAB") \
  && ok "(CLIPPHRASE) a deterministic state phrase is untouched" \
  || bad "(CLIPPHRASE) the state phrase changed: $(grep -- 'tk-clip-plain' <<< "$NTAB" || true)"

# (CLIPWIRE) the bound is a DISPLAY guard. Applying it to the model would make
# the table pass and silently truncate every consumer of the contract.
nfield() { printf '%s' "$NJSON" | jq -r --arg i "$1" --arg k "$2" \
           'first(.[]?|select(.id==$i)) | .[$k] // "" | length' 2>/dev/null || printf 'ERR'; }
eq "$(nfield tk-clip-long needs)"    "400" "(CLIPWIRE) --json keeps the whole NEEDS string"
eq "$(nfield tk-clip-long takeaway)" "400" "(CLIPWIRE) …and the whole takeaway beside it"

echo ""
echo "gc-helm takeaway --release quiesce + anchor-gather argv boundary + in-flight/metadata kinds: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
