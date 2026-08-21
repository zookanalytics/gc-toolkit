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
  "metadata":{"gc.routed_to":"human","gc.takeaway":"parked, and still owed to the operator"}}
]
J

cat > "$ITMP/decisions.json" <<'J'
[{"id":"tk-dHUMAN","title":"decision routed to human","priority":1,"updated_at":"2026-08-21T00:00:00Z",
  "metadata":{"gc.routed_to":"human"}}]
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
  "bd show")      printf '[]\n' ;;
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
            FAKE_DIR="$ITMP" GC_HELM_FIXTURE= \
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

# --- (EXCLUDE) the typed kinds are not re-gathered by metadata --------------
eq "$(printf '%s' "$IOUT" | jq -r '[.[]?|select(.id=="tk-eTAKE")]|length')" "1" \
   "(EXCLUDE) an epic carrying a takeaway appears exactly once"
eq "$(row tk-eTAKE kind)" "epic" "(EXCLUDE) …and stays kind epic, not parked"
eq "$(printf '%s' "$IOUT" | jq -r '[.[]?|select(.id=="tk-dHUMAN")]|length')" "1" \
   "(EXCLUDE) a decision routed to human appears exactly once"
eq "$(row tk-dHUMAN kind)" "decision" "(EXCLUDE) …and stays kind decision, not human"

eq "$(printf '%s' "$IOUT" | jq -r '[.[]?|select(.id=="tk-both")]|length')" "1" \
   "(BOTH) …and renders exactly once after dedup"
eq "$(row tk-both kind)"     "human"    "(BOTH) the higher band wins the row"
eq "$(row tk-both severity)" "ELEVATED" "(BOTH) an owed-to-the-operator bead is not floored by its takeaway"

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

echo ""
echo "gc-helm takeaway --release quiesce + anchor-gather argv boundary + in-flight/metadata kinds: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
