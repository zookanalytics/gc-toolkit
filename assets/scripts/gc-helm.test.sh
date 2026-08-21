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
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_STEPS_JSON="$TMP/steps.json" FAKE_ROOTS="$TMP/roots" \
       FAKE_CONVOYS="$TMP/convoys" FAKE_UPDATES="$TMP/updates"
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
      *)                   printf '[]\n' ;;   # the visits query
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
                GC_HELM_FIXTURE= \
                sh "$SCRIPT" board --json --refresh 2>"$run/err")" || BRC=$?
    BERR="$(cat "$run/err" 2>/dev/null || true)"
    # Any cache the run decided to persist lands under TMPDIR/gc-helm-cache.<uid>.
    BCACHE_N="$(find "$run" -name 'board-*.ndjson' 2>/dev/null | wc -l | tr -d ' ')"
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

echo ""
echo "gc-helm takeaway --release quiesce + anchor-gather argv boundary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
