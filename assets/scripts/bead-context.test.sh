#!/usr/bin/env bash
# Hermetic test for assets/scripts/bead-context.sh.
#
# The tool rebuilds a subject's opening context in one call, so the assertions
# target the contract that opening reads: subject core (A) with the anchor,
# first_reaction, origin and takeaway fields; context edges (D) — parent,
# relates-to (both the `relates-to` and older `related` spellings), the reverse
# `tracks` edges (a conversation about the bead), and the beads that wait on it
# by a reverse `blocks` or `until` edge, open ones first and capped — each with
# a count; the store that answered (E); and,
# each behind its opt-in flag, the frontier verdict over {ready, advancing,
# stuck} (B) and the direct-children epic-health snapshot (C). The advance enum,
# the bead a live run works, the cross-store fold, the fail-closed unknown, the
# status scope of the child listing, and the three `gc bd show --json` quirks
# each get a case.
#
# `gc` is the compiled fake gc of test-harness.sh, over a store per rig: the
# gc-toolkit and otherrig rigs each keep one in their .beads directory, and the
# city's own store, the one the rig list marks hq, is also the fake's default
# store, as gc answers a call no rig claims from it. Every edge is a dep row,
# so a show and a listing answer each edge as bd does.
# The frontier reads what holds a bead through gctk built from this checkout,
# and the walk reads each store's runs through run-lib.sh itself. A direct `bd`
# is the regression a stub of its own fails on. No live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/bead-context.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bead-context-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
harness_init
# The walk reads the runs of each store it reads through run-lib.sh, which the
# script sources from beside itself once no stub stands in for it.
unset GC_RUN_LIB RUN_LIB_STUB_CMD

# --- fake city --------------------------------------------------------------
R_TK="$TMP/rigs/gc-toolkit"; R_OR="$TMP/rigs/otherrig"; HQ="$TMP/hq"
harness_store "$R_TK/.beads"; harness_store "$R_OR/.beads"; harness_store "$HQ/.beads"
export STUB_RIGS="$TMP/rigs.json"
cat > "$STUB_RIGS" <<JSON
{"rigs":[
  {"name":"gc-toolkit","path":"$R_TK","prefix":"tk","hq":false},
  {"name":"otherrig","path":"$R_OR","prefix":"or","hq":false},
  {"name":"mycity","path":"$HQ","prefix":"hq","hq":true}
]}
JSON
# gc answers a call no rig claims from the city's own store.
export STUB_STORE="$HQ/.beads/beads.json" STUB_DEPS="$HQ/.beads/deps.txt" STUB_KV="$HQ/.beads/kv.txt" STUB_COMMENTS="$HQ/.beads/comments.json"
# The tool reaches every store through `gc bd`. A direct `bd` records the call,
# so one assertion reads the whole run, and refuses it.
export DIRECT_BD_LOG="$TMP/bd.log"; : > "$DIRECT_BD_LOG"
{ _stub_shebang; cat <<'BD'
printf '%s\n' "$*" >> "${DIRECT_BD_LOG:?}"
echo "stub bd: called directly instead of through gc bd" >&2
exit 127
BD
} > "$BIN/bd"
chmod +x "$BIN/bd"

# The rows and the dep rows of each store, written once the fixtures are all
# set (flush). A bead's store is the one its id's prefix names, but for the one
# bead the city's store holds under another rig's prefix (put).
declare -A ROWS=() EDGES=()
store_of() { # <var> <id>
  case "$2" in
    or-*) printf -v "$1" '%s' "$R_OR/.beads" ;;
    hq-*) printf -v "$1" '%s' "$HQ/.beads" ;;
    *)    printf -v "$1" '%s' "$R_TK/.beads" ;;
  esac
}
put() { ROWS[$1]+="${ROWS[$1]:+,}$2"; }                     # put <store> <row-json>
bead() { local s row; store_of s "$1"; IFS= read -r -d '' row; put "$s" "$row"; }   # bead <id> (row on stdin)
# edge <bead> <type> <other> — the bead's edge onto <other>, as the dep row its
# store keeps: "<other>|blocks|<bead>" for a blocks edge, "<bead>|<type>|<other>"
# for any other.
edge() {
  local s; store_of s "$1"
  if [ "$2" = blocks ]; then EDGES[$s]+="$3|blocks|$1"$'\n'; else EDGES[$s]+="$1|$2|$3"$'\n'; fi
}
# closed_at <var> <status> — the closed_at field bd records on every bead it
# closes, with its leading comma, and nothing for a bead that is not closed.
closed_at() { if [ "$2" = closed ]; then printf -v "$1" '%s' ',"closed_at":"2026-10-01T00:00:00Z"'; else printf -v "$1" ''; fi; }
flush() {
  local s
  for s in "$R_TK/.beads" "$R_OR/.beads" "$HQ/.beads"; do
    printf '[%s]\n' "${ROWS[$s]-}" > "$s/beads.json" && printf '%s' "${EDGES[$s]-}" > "$s/deps.txt" \
      || { echo "FAIL - the fixture store $s could not be written"; exit 1; }
  done
}

# tk-anchor: a subject core (A) with every field the opening reads — anchor
# state, first_reaction, origin, a settled takeaway, task_kind and routing. Its
# edges (D) are the parent tk-epic, two relates edges in each spelling, and a
# reverse `tracks` edge from a conversation (tk-conv, below). Its blocks are all
# closed — one same-store, one FOREIGN in the otherrig store, which a show
# leaves out (the cross-store fold) — so its frontier verdict is ready. It also
# carries a description and notes; the read returns its title but never that body.
bead tk-anchor <<'J'
{"id":"tk-anchor","title":"rich anchor","status":"open","issue_type":"task","priority":1,
 "assignee":"gc-toolkit/gc-toolkit.refinery","parent":"tk-epic",
 "description":"subject body prose the read must never surface",
 "notes":"## Current state\noperational notes the read must never surface",
 "metadata":{"task_kind":"rework","gc.routed_to":"","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat",
   "merge_result":"pull_request","pr_number":"9","branch":"polecat/tk-anchor","merged_target":"main","target":"main",
   "pr.machine":"progressing@a1b2c3@2026-09-02T22:00:00Z",
   "gc.first_reaction":"ruling","gc.first_reaction_at":"2026-09-02T22:23:04Z",
   "gc.first_reaction_reason":"scope and control flow unresolved","gc.first_reaction_target":"tk-frt",
   "gc.origin":"operator","gc.takeaway":"held pending the opening contract","gc.takeaway_settled":1}}
J
edge tk-anchor parent-child tk-epic
edge tk-anchor blocks tk-c1
edge tk-anchor blocks or-far
edge tk-anchor relates-to tk-rel
edge tk-anchor related tk-rel2
bead tk-c1 <<'J'
{"id":"tk-c1","title":"closed blocker","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","metadata":{}}
J
bead or-far <<'J'
{"id":"or-far","title":"foreign closed blocker","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","metadata":{}}
J
bead tk-rel <<'J'
{"id":"tk-rel","title":"related work","status":"open","issue_type":"task","metadata":{}}
J
bead tk-rel2 <<'J'
{"id":"tk-rel2","title":"older-spelling related","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","metadata":{}}
J
# tk-conv tracks tk-anchor: the reverse edge that makes tk-anchor tracked-by it.
bead tk-conv <<'J'
{"id":"tk-conv","title":"about tk-anchor","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","assignee":"human","metadata":{}}
J
edge tk-conv tracks tk-anchor

# tk-design: a closed design and the beads that wait on it, each by its own
# reverse edge. The build it released (open) and its docs (in progress) wait by
# blocks edges; an earlier build (closed) by a blocks edge and a duplicate it
# answered (closed) by an until edge. The closed ones' ids sort before the open
# ones', so only an open-first order lists the build first. A review's inbound
# `related` edge, a conversation's `tracks` edge and a child's `parent-child`
# edge also point at it, and none of those waits on it. The build carries a body
# the read must never surface. bd answers the dependents oldest first, and these
# are filed in descending id order, an order the tool must not lean on.
bead tk-design <<'J'
{"id":"tk-design","title":"the design","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","metadata":{}}
J
bead tk-aw-track <<'J'
{"id":"tk-aw-track","title":"the conversation about the design","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","metadata":{}}
J
bead tk-aw-review <<'J'
{"id":"tk-aw-review","title":"review the design","status":"open","issue_type":"task","metadata":{"task_kind":"review"}}
J
bead tk-aw-polish <<'J'
{"id":"tk-aw-polish","title":"its docs","status":"in_progress","issue_type":"task","metadata":{}}
J
bead tk-aw-next <<'J'
{"id":"tk-aw-next","title":"the build it released","status":"open","issue_type":"task",
 "description":"build body prose the read must never surface","metadata":{}}
J
bead tk-aw-kid <<'J'
{"id":"tk-aw-kid","title":"a child of the design","status":"open","issue_type":"task","parent":"tk-design","metadata":{}}
J
bead tk-aw-earlier <<'J'
{"id":"tk-aw-earlier","title":"an earlier build","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","metadata":{}}
J
bead tk-aw-dup <<'J'
{"id":"tk-aw-dup","title":"a duplicate it answered","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","metadata":{}}
J
edge tk-aw-track tracks tk-design
edge tk-aw-review related tk-design
edge tk-aw-polish blocks tk-design
edge tk-aw-next blocks tk-design
edge tk-aw-kid parent-child tk-design
edge tk-aw-earlier blocks tk-design
edge tk-aw-dup until tk-design

# tk-hub: a gate twelve beads wait on, more than the list names. tk-hw-00 is
# closed and sorts first by id; tk-hw-01 to tk-hw-11 are open. They are filed
# newest id first.
bead tk-hub <<'J'
{"id":"tk-hub","title":"a gate","status":"open","issue_type":"gate","metadata":{}}
J
for i in 11 10 09 08 07 06 05 04 03 02 01 00; do
  st=open; [ "$i" = 00 ] && st=closed
  closed_at ca "$st"
  put "$R_TK/.beads" "{\"id\":\"tk-hw-$i\",\"title\":\"parked $i\",\"status\":\"$st\"$ca,\"issue_type\":\"task\",\"metadata\":{}}"
  edge "tk-hw-$i" blocks tk-hub
done

# Frontier verdict fixtures: one open unrouted blocker (stuck), one open
# pool-routed blocker (advancing), one open human gate (stuck).
bead tk-stuck <<'J'
{"id":"tk-stuck","title":"held by an unrouted blocker","status":"open","issue_type":"task","metadata":{}}
J
edge tk-stuck blocks tk-op
bead tk-op <<'J'
{"id":"tk-op","title":"open unrouted blocker","status":"open","issue_type":"task","metadata":{}}
J
bead tk-adv <<'J'
{"id":"tk-adv","title":"held by a routed blocker","status":"open","issue_type":"task","metadata":{}}
J
edge tk-adv blocks tk-routed
bead tk-routed <<'J'
{"id":"tk-routed","title":"routed blocker","status":"open","issue_type":"task",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead tk-humangate <<'J'
{"id":"tk-humangate","title":"held by a human gate","status":"open","issue_type":"task","metadata":{}}
J
edge tk-humangate blocks tk-hg
bead tk-hg <<'J'
{"id":"tk-hg","title":"a human gate","status":"open","issue_type":"gate",
 "await_type":"human","await_id":"which-base","metadata":{}}
J
# tk-convheld: held by a conversation its sitting holds, in progress under the
# alias that names its own id, as one on an open PR holds the PR's merge. It is a
# person's, so it reads stuck, not advancing.
bead tk-convheld <<'J'
{"id":"tk-convheld","title":"held by a conversation","status":"open","issue_type":"task","metadata":{"merge_result":"pull_request"}}
J
edge tk-convheld blocks tk-cv
bead tk-cv <<'J'
{"id":"tk-cv","title":"should this land as built?","status":"in_progress","issue_type":"task",
 "assignee":"gc-toolkit/converse-claude-opus.c-tk-cv","metadata":{}}
J
edge tk-cv tracks tk-convheld
# tk-inreview: held by a review bead the review cadence dispatched. The review
# bead's live route is CLEARED by the pour (gc.routed_to="") and its status is not
# in_progress, so it looks like an unrouted stuck blocker — but it is machine work
# the pool owns, so its advance is advancing, not stuck.
bead tk-inreview <<'J'
{"id":"tk-inreview","title":"held by a review in flight","status":"open","issue_type":"task","metadata":{}}
J
edge tk-inreview blocks tk-rev
bead tk-rev <<'J'
{"id":"tk-rev","title":"review branch -> main","status":"open","issue_type":"task",
 "metadata":{"task_kind":"review","anchor_bead":"tk-inreview","gc.routed_to":"","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat-codex"}}
J
# tk-under: a member of a parked parent, held through it. tk-waiter: a bead
# with a waits-for edge of its own, which the store cannot judge yet.
bead tk-parked <<'J'
{"id":"tk-parked","title":"a parked parent","status":"open","issue_type":"epic","metadata":{}}
J
edge tk-parked blocks tk-pgate
bead tk-pgate <<'J'
{"id":"tk-pgate","title":"Parked until the operator says","status":"open","issue_type":"gate","await_type":"human","metadata":{}}
J
bead tk-under <<'J'
{"id":"tk-under","title":"a member of the parked parent","status":"open","issue_type":"task","parent":"tk-parked","metadata":{}}
J
edge tk-under parent-child tk-parked
bead tk-spawner <<'J'
{"id":"tk-spawner","title":"the spawner","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","metadata":{}}
J
bead tk-waiter <<'J'
{"id":"tk-waiter","title":"waits for its spawner","status":"open","issue_type":"task","metadata":{}}
J
edge tk-waiter waits-for tk-spawner
# tk-failclosed: a blocks edge onto a bead no store holds — an edge into another
# store, which holds nothing.
bead tk-failclosed <<'J'
{"id":"tk-failclosed","title":"fail-closed","status":"open","issue_type":"task","metadata":{}}
J
edge tk-failclosed blocks zz-ghost

# --- the transitive walk ----------------------------------------------------
# blk <id> <status> <metadata-json> [blocker...]: a bead whose only edges are
# blocks edges onto the blockers named, in its own store whatever store each
# blocker lives in.
blk() {
  local id="$1" st="$2" md="$3" s b ca; shift 3
  store_of s "$id"; closed_at ca "$st"
  put "$s" "{\"id\":\"$id\",\"title\":\"$id\",\"status\":\"$st\"$ca,\"issue_type\":\"task\",\"metadata\":$md}"
  for b in "$@"; do edge "$id" blocks "$b"; done
}
POOL='{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}'
ARMED='{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"}'

# A routed blocker held by an orphan: one level reads it advancing, but nothing
# will ever pick up what it waits on, so it is stuck and names the orphan.
blk tk-w-sub1 open '{}' tk-w-routed
blk tk-w-routed open "$POOL" tk-w-orphan
blk tk-w-orphan open '{}'
# An armed bead takes its blockers' verdict: moving blockers advance it ...
blk tk-w-sub2 open '{}' tk-w-armed
blk tk-w-armed open "$ARMED" tk-w-mover
blk tk-w-mover open "$POOL"
# ... and a human gate beneath it makes it stuck, naming the gate.
blk tk-w-sub3 open '{}' tk-w-armed2
blk tk-w-armed2 open "$ARMED" tk-w-gate
bead tk-w-gate <<'J'
{"id":"tk-w-gate","title":"tk-w-gate","status":"open","issue_type":"gate",
 "await_type":"human","await_id":"ship-it","metadata":{}}
J
# A cycle never drains: each routed bead waits on the other.
blk tk-w-sub4 open '{}' tk-w-cyc-a
blk tk-w-cyc-a open "$POOL" tk-w-cyc-b
blk tk-w-cyc-b open "$POOL" tk-w-cyc-a
# A cross-store hop: the middle bead lives in otherrig, its orphan back in tk.
blk tk-w-sub6 open '{}' or-w-mid
blk or-w-mid open "$POOL" tk-w-far
blk tk-w-far open '{}'
# A routed bead whose only blocker lives in another store: `gc bd show` leaves
# that edge out, so only its list row shows the orphan it waits on.
blk tk-w-xs open '{}' tk-w-xmid
blk tk-w-xmid open "$POOL" or-w-leaf
blk or-w-leaf open '{}'
# A routed chain three deep, for the bead budget.
blk tk-w-sub7 open '{}' tk-w-ch1
blk tk-w-ch1 open "$POOL" tk-w-ch2
blk tk-w-ch2 open "$POOL" tk-w-ch3
blk tk-w-ch3 open "$POOL"
# A routed chain with a closed bead beside it: a closed row costs no budget.
blk tk-w-cl open '{}' tk-w-cl1
blk tk-w-cl1 open "$POOL" tk-w-clx tk-w-cl2
blk tk-w-clx closed '{}'
blk tk-w-cl2 open "$POOL" tk-w-cl3
blk tk-w-cl3 open "$POOL"
# A routed blocker over four routed leaves: one level wider than a budget of
# three, so the read has to stop inside the level.
blk tk-w-wide open '{}' tk-w-fan
blk tk-w-fan open "$POOL" tk-w-f1 tk-w-f2 tk-w-f3 tk-w-f4
for i in 1 2 3 4; do blk "tk-w-f$i" open "$POOL"; done
# The same fan with a closed leaf first, as a listing orders a bead's edges by
# the far bead's id: its row hands its share of the budget back, so the leaf
# the cut read left out is read next.
blk tk-w-refund open '{}' tk-w-rfan
blk tk-w-rfan open "$POOL" tk-w-r0 tk-w-r1 tk-w-r2 tk-w-r3
blk tk-w-r0 closed '{}'
for i in 1 2 3; do blk "tk-w-r$i" open "$POOL"; done
# Routed chains six and seven deep, for the depth bound: six levels are read.
blk tk-w-six open '{}' tk-w-s1
for i in 1 2 3 4 5; do blk "tk-w-s$i" open "$POOL" "tk-w-s$((i + 1))"; done
blk tk-w-s6 open "$POOL"
blk tk-w-seven open '{}' tk-w-v1
for i in 1 2 3 4 5 6; do blk "tk-w-v$i" open "$POOL" "tk-w-v$((i + 1))"; done
blk tk-w-v7 open "$POOL"
# A diamond: two routed blockers share one routed blocker, read once.
blk tk-w-sub8 open '{}' tk-w-d1 tk-w-d2
blk tk-w-d1 open "$POOL" tk-w-dshared
blk tk-w-d2 open "$POOL" tk-w-dshared
blk tk-w-dshared open "$POOL"
# A stuck bead stops the walk on its branch: what it waits on is never read.
blk tk-w-sub9 open '{}' tk-w-stopper
blk tk-w-stopper open '{}' tk-w-hidden
blk tk-w-hidden open "$POOL"

# Merge anchors read their recorded merge axis, not their empty route.
blk tk-w-anchors open '{}' tk-a-approval tk-a-progress tk-a-preopen tk-a-approved \
  tk-a-hold tk-a-blocked tk-a-stale tk-a-noaxis tk-a-humanstate \
  tk-a-rpend tk-a-rreview tk-a-rnopost tk-a-rhead tk-a-rhold
AX='@h1@2026-10-01T00:00:00Z'
blk tk-a-approval open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"settled$AX\",\"pr_posture\":\"review_required$AX\"}"
blk tk-a-progress open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"progressing$AX\",\"pr_posture\":\"changes_requested$AX\"}"
blk tk-a-preopen open "{\"merge_result\":\"pre_open_gate\",\"pr.machine\":\"settled$AX\"}"
blk tk-a-approved open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"settled$AX\",\"pr_posture\":\"approved$AX\"}"
blk tk-a-hold open "{\"merge_result\":\"pre_open_gate\",\"merge_hold\":\"true\",\"pr.machine\":\"settled$AX\"}"
blk tk-a-blocked open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"blocked$AX\"}"
blk tk-a-stale open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"settled$AX\",\"pr_posture\":\"review_required@h0@2026-09-30T00:00:00Z\"}"
blk tk-a-noaxis open '{"merge_result":"pre_open_gate"}'
blk tk-a-humanstate open '{"merge_result":"abandoned","gc.takeaway":"PR#9 was closed without merging"}'
# The pending record: no merge axis is ever written there, and a pending bead is
# blocked by the record itself while it waits on the merge.
blk tk-a-rpend blocked "{\"merge_result\":\"pull_request_pending\",\"pr_posture\":\"approved$AX\"}"
blk tk-a-rreview blocked "{\"merge_result\":\"pull_request_pending\",\"pr_posture\":\"review_required$AX\"}"
blk tk-a-rnopost blocked '{"merge_result":"pull_request_pending"}'
blk tk-a-rhead open '{"merge_result":"pull_request_head_changed"}'
blk tk-a-rhold blocked "{\"merge_result\":\"pull_request_pending\",\"merge_hold\":\"true\",\"pr_posture\":\"approved$AX\"}"

# A bead's own state, one rule per blocker.
blk tk-w-kinds open '{}' tk-k-blocked tk-k-validation tk-k-finding tk-k-needsyou \
  tk-k-refinery tk-k-capped tk-k-hooked tk-k-deferred tk-k-gate tk-k-humanroute
blk tk-k-blocked blocked "$POOL"
blk tk-k-validation open '{"task_kind":"validation","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}'
blk tk-k-finding open '{"task_kind":"finding","finding.disposition":"must-fix"}'
blk tk-k-needsyou open '{"task_kind":"finding","finding.disposition":"needs-you"}'
blk tk-k-capped open '{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat","gc.dispatch_when_ready_fail_count":"3"}'
blk tk-k-hooked hooked '{}'
blk tk-k-deferred deferred "$POOL"
blk tk-k-humanroute open '{"gc.routed_to":"human"}'
bead tk-k-gate <<'J'
{"id":"tk-k-gate","title":"held by ruling","status":"open","issue_type":"gate",
 "await_type":"human","await_id":"which-way","metadata":{}}
J
bead tk-k-refinery <<'J'
{"id":"tk-k-refinery","title":"handed to the refinery","status":"open","issue_type":"task",
 "assignee":"gc-toolkit/gc-toolkit.refinery","metadata":{"gc.routed_to":""}}
J
bead tk-w-decides <<'J'
{"id":"tk-w-decides","title":"held by a decision","status":"open","issue_type":"task","metadata":{}}
J
edge tk-w-decides blocks tk-k-decision
bead tk-k-decision <<'J'
{"id":"tk-k-decision","title":"a ruling","status":"open","issue_type":"decision","metadata":{}}
J

# The bead a run works. pour <bead> <root> <root-status> writes a graph.v2 run
# over the bead, in its store: its root, and the input convoy the root names,
# which tracks the bead and stays open for as long as the bead is open, whether
# or not the root has closed. The pour leaves the bead open, unassigned and
# unrouted, with the route it ran on as provenance only.
pour() {
  local s ca; store_of s "$1"; closed_at ca "$3"
  put "$s" "{\"id\":\"$2-cv\",\"title\":\"input convoy for $1\",\"status\":\"open\",\"issue_type\":\"convoy\",\"metadata\":{\"gc.synthetic\":\"true\"}}"
  edge "$2-cv" tracks "$1"
  put "$s" "{\"id\":\"$2\",\"title\":\"mol-polecat-work\",\"status\":\"$3\"$ca,\"issue_type\":\"task\",\"metadata\":{\"gc.kind\":\"workflow\",\"gc.formula_contract\":\"graph.v2\",\"gc.formula_name\":\"mol-polecat-work\",\"gc.input_convoy_id\":\"$2-cv\"}}"
}
POURED='{"gc.routed_to":"","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}'
# tk-r-epic, an epic in active work: a live run works tk-r-work, and the run
# over tk-r-ended has closed its root, leaving its convoy open.
bead tk-r-epic <<'J'
{"id":"tk-r-epic","title":"an epic in active work","status":"open","issue_type":"epic","metadata":{}}
J
for b in work ended; do
  put "$R_TK/.beads" "{\"id\":\"tk-r-$b\",\"title\":\"tk-r-$b\",\"status\":\"open\",\"issue_type\":\"task\",\"parent\":\"tk-r-epic\",\"metadata\":$POURED}"
done
pour tk-r-work tk-r-root in_progress
pour tk-r-ended tk-r-eroot closed
# A merge anchor a live review run works is still judged as an anchor. tk-r-sub
# waits on it, on tk-r-work and on tk-r-ended.
blk tk-r-anchor open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"settled$AX\",\"pr_posture\":\"review_required$AX\"}"
pour tk-r-anchor tk-r-aroot in_progress
blk tk-r-sub open '{}' tk-r-work tk-r-ended tk-r-anchor
# Live runs two deep over an orphan no run works: the walk reads on below the
# bead a live run works.
blk tk-r-deep open '{}' tk-r-w2
blk tk-r-w2 open "$POURED" tk-r-w3
blk tk-r-w3 open "$POURED" tk-r-orphan
blk tk-r-orphan open '{}'
pour tk-r-w2 tk-r-root2 in_progress
pour tk-r-w3 tk-r-root3 in_progress
# A routed chain whose sixth level, the last the walk reads, a live run works.
blk tk-r-six open '{}' tk-r-s1
for i in 1 2 3 4 5; do blk "tk-r-s$i" open "$POOL" "tk-r-s$((i + 1))"; done
blk tk-r-s6 open "$POURED"
pour tk-r-s6 tk-r-root6 in_progress
# A routed bead over orphans in two stores, so the runs of both are read.
blk tk-r-two open '{}' tk-r-mid
blk tk-r-mid open "$POOL" tk-r-orphan or-r-orphan
blk or-r-orphan open '{}'
# A design a live run works, and its build, armed behind it.
put "$R_TK/.beads" "{\"id\":\"tk-r-design\",\"title\":\"a design in its run\",\"status\":\"open\",\"issue_type\":\"task\",\"metadata\":$POURED}"
pour tk-r-design tk-r-droot in_progress
bead tk-r-impl <<'J'
{"id":"tk-r-impl","title":"its build","status":"open","issue_type":"task","parent":"tk-r-design",
 "metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"}}
J
edge tk-r-impl blocks tk-r-design
# Two stores holding a bead of one id. A live run works gc-toolkit's tk-r-twin,
# which tk-r-tsub waits on. The city store's tk-r-twin is an idle child of
# hq-pin, beside a routed child waiting on an orphan in gc-toolkit's store, so
# the runs of both stores are read.
blk tk-r-twin open "$POURED"
pour tk-r-twin tk-r-troot in_progress
blk tk-r-tsub open '{}' tk-r-twin
blk tk-r-lone open '{}'
bead hq-pin <<'J'
{"id":"hq-pin","title":"an epic in the city store","status":"open","issue_type":"epic","metadata":{}}
J
put "$HQ/.beads" '{"id":"tk-r-twin","title":"an idle bead of that id","status":"open","issue_type":"task","parent":"hq-pin","metadata":{}}'
bead hq-pmid <<'J'
{"id":"hq-pmid","title":"a routed bead over the orphan","status":"open","issue_type":"task","parent":"hq-pin",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
edge hq-pmid blocks tk-r-lone

# tk-epic: the horizon fixture. Its direct children (found by the reverse
# parent-child listing, never its own edges) cover every advance state: an open
# pool-routed and an in-progress child advance, as do tk-anchor — a merge anchor
# whose recorded machine axis is progressing — and tk-kid-rework, a rework bead
# whose pour cleared its route, machine work rather than a human gate. A child
# in the operator's queue is stuck, and so is tk-kid-armed: armed, so it takes
# its blocker's verdict, and its blocker is the human gate tk-hg. Three children sit
# in statuses a default or --status listing can leave out: a hooked child
# advances, a pinned one is a hold whatever its route, and one in a status its
# store adds is unknown to the classifier, so it fails closed. One done child is
# counted, never listed. tk-kid-event is the closed event `bd set-state` files
# under a bead whose state changed, and it is neither counted nor listed. The
# epic's own blocks are none, so its frontier verdict is ready. The plain
# unrouted-stuck case is covered by tk-stuck in the frontier section above, off
# the same shared classifier.
bead tk-epic <<'J'
{"id":"tk-epic","title":"the epic","status":"open","issue_type":"epic","priority":2,"metadata":{}}
J
edge tk-epic related tk-relE
bead tk-relE <<'J'
{"id":"tk-relE","title":"related epic","status":"open","issue_type":"epic","metadata":{}}
J
bead tk-kid-pool <<'J'
{"id":"tk-kid-pool","title":"routed child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead tk-kid-prog <<'J'
{"id":"tk-kid-prog","title":"in-progress child","status":"in_progress","issue_type":"task","parent":"tk-epic","metadata":{}}
J
bead tk-kid-human <<'J'
{"id":"tk-kid-human","title":"a child in the operator's queue","status":"open","issue_type":"task","parent":"tk-epic",
 "assignee":"human","metadata":{}}
J
bead tk-kid-done <<'J'
{"id":"tk-kid-done","title":"done child","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"task","parent":"tk-epic","metadata":{}}
J
bead tk-kid-event <<'J'
{"id":"tk-kid-event","title":"State change: situation → cleared","status":"closed","closed_at":"2026-10-01T00:00:00Z","issue_type":"event","priority":4,"parent":"tk-epic","metadata":{}}
J
bead tk-kid-rework <<'J'
{"id":"tk-kid-rework","title":"rework child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"task_kind":"rework","gc.routed_to":""}}
J
bead tk-kid-armed <<'J'
{"id":"tk-kid-armed","title":"armed child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"}}
J
edge tk-kid-armed blocks tk-hg
bead tk-kid-hooked <<'J'
{"id":"tk-kid-hooked","title":"hooked child","status":"hooked","issue_type":"task","parent":"tk-epic","metadata":{}}
J
bead tk-kid-pinned <<'J'
{"id":"tk-kid-pinned","title":"pinned child","status":"pinned","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead tk-kid-custom <<'J'
{"id":"tk-kid-custom","title":"custom-status child","status":"in_review","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J

# hq-city lives in the city's store, which no --rig value names — only --db reaches.
bead hq-city <<'J'
{"id":"hq-city","title":"city bead","status":"open","issue_type":"task","metadata":{}}
J

# tk-ctrl carries a C0 byte (SOH \001) in its title and tk-nul a NUL (\000) in
# its notes. Under STUB_SHOW_RAW_CONTROL a show answers each as the raw byte,
# the payload that aborts a naive jq, which scrub must remove; the NUL also trips
# grep's binary heuristic, so the notice-strip must run in text mode (grep -a)
# or grep drops the whole payload.
bead tk-ctrl <<'J'
{"id":"tk-ctrl","title":"ctl\u0001note","status":"open","issue_type":"task","metadata":{}}
J
bead tk-nul <<'J'
{"id":"tk-nul","title":"nul","status":"open","issue_type":"task","notes":"a\u0000b","metadata":{}}
J
flush

# One run per subject; each assertion reads that run's output. A --json answer
# is also read into J, as jq -c prints it: jq's indent and the break before
# each line dropped, and the blank after each key's colon. No string in an
# answer here carries a line break or a quoted key's colon.
run()  { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(<"$TMP/err"); compact; }
# Bounded variant for a call that could spin before a fix: a wedged SUT surfaces
# as timeout's rc 124 (a test failure) instead of hanging the whole suite.
runb() { OUT=$(timeout 10 "$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(<"$TMP/err"); compact; }
compact() {
  local l
  J=""
  case "$OUT" in '{'*) ;; *) return 0 ;; esac
  while IFS= read -r l; do J+="${l#"${l%%[! ]*}"}"; done <<< "$OUT"
  J=${J//'": '/'":'}
}
# after <json> <key> — the text after the first "<key>": in it, empty when it
# has none.
after() { local r=${1#*\""$2"\":}; [ "$r" = "$1" ] || printf '%s' "$r"; }
# val <json> <key> — the value at the first "<key>": in the text, as jq -r
# prints a scalar: a string's text, any other value up to the comma or bracket
# that ends it, and <absent> when the text has no such key.
val() {
  local r=${1#*\""$2"\":}
  if [ "$r" = "$1" ]; then printf '<absent>'; return 0; fi
  case "$r" in
    \"*) r=${r#\"}; printf '%s' "${r%%\"*}" ;;
    *) printf '%s' "${r%%[],\}]*}" ;;
  esac
}
# A section's open list: the frontier's waits or the horizon's open children.
# Each item is a flat object but for the stuck_on object it can end with, so
# the list ends at its first `]`, and an item is the object whose id is followed
# by its title, which stuck_on never carries.
openlist() { # <frontier|horizon>
  local s; s=$(after "$J" "$1"); [ "$1" = frontier ] && s=${s%%\"horizon\":*}
  s=${s#*\"open\":\[}; printf '%s' "${s%%]*}"
}
# item <section> <id> — the item's text up to its first `}`, empty when the list
# names no such bead.
item() {
  local s e; s=$(openlist "$1")
  e=${s#*\{\"id\":\""$2"\",\"title\":}
  [ "$e" = "$s" ] || printf '"title":%s' "${e%%\}*}"
}
# first_item <section> — the list's first item, as item reads it.
first_item() { local s; s=$(openlist "$1"); s=${s#\{}; printf '%s' "${s%%\}*}"; }
# items <section> — the ids of the list's items, comma-joined, in its order.
items() {
  local s out="" id; s=$(openlist "$1")
  while [[ $s == *'{"id":"'* ]]; do
    s=${s#*\{\"id\":\"}; id=${s%%\"*}; s=${s#*\"}
    [[ $s == ',"title":'* ]] && out+=",$id"
  done
  printf '%s' "${out#,}"
}
# named <section> <id> — "<advance> <stuck_on id> <stuck_on why>" of the bead
# the list names, "-" for each stuck_on field it lacks, "null - -" when the
# list names no such bead.
named() {
  local e so; e=$(item "$1" "$2")
  [ -n "$e" ] || { printf 'null - -'; return 0; }
  so=${e#*\"stuck_on\":\{}
  if [ "$so" = "$e" ]; then printf '%s - -' "$(json_get "$e" advance)"
  else printf '%s %s %s' "$(json_get "$e" advance)" "$(json_get "$so" id)" "$(json_get "$so" why)"; fi
}
blkr() { named frontier "$1"; }
kid() { named horizon "$1"; }
# awaited <field>... — each awaited-by item, its fields joined by ':', the
# items by blanks; the field "keys" names the item's keys, sorted and
# comma-joined.
awaited() {
  local s o f out="" one
  s=$(after "$J" awaited_by); s=${s#\[}; s=${s%%]*}
  while [[ $s == '{'* ]]; do
    o=${s%%\}*}; s=${s#*\}}; s=${s#,}
    one=""
    for f in "$@"; do
      if [ "$f" = keys ]; then one+="${one:+:}$(objkeys "$o")"
      else one+="${one:+:}$(json_get "$o" "$f")"; fi
    done
    out+="${out:+ }$one"
  done
  printf '%s' "$out"
}
# objkeys <object> — the keys of a flat object, sorted and comma-joined: each
# quoted string a colon follows.
objkeys() {
  local o=$1 k=()
  while [[ $o =~ \"([^\"]*)\":(.*) ]]; do k+=("${BASH_REMATCH[1]}"); o=${BASH_REMATCH[2]}; done
  sorted "$(IFS=,; printf '%s' "${k[*]}")"
}
# bodykeys — the keys anywhere in the answer that name a description, notes or a
# comment, a line each.
bodykeys() {
  local s=${J,,} k
  while [[ $s =~ \"([^\"]*(description|notes|comment)[^\"]*)\":(.*) ]]; do
    k=${BASH_REMATCH[1]}; s=${BASH_REMATCH[3]}; printf '%s\n' "$k"
  done
}
# The fake logs every call, gctk's reads among them; logcount <regex> counts
# the calls the regex matches.
logcount() {
  local n=0 l
  while IFS= read -r l; do [[ $l =~ $1 ]] && n=$((n + 1)); done < "$STUB_GC_LOG"
  printf '%s' "$n"
}
# sorted <list> — a comma-joined list in sort order. count <list> — how many
# items it names.
sorted() { local IFS=,; printf '%s\n' $1 | sort | paste -sd, -; }
count() { local IFS=, a; read -r -a a <<< "$1"; printf '%s' "${#a[@]}"; }

# --- A. Subject core --------------------------------------------------------
run tk-anchor
eq "$RC" 0 "a resolvable bead reports (rc)"
has "$OUT" "Title       rich anchor"             "  ... the subject's own title"
has "$OUT" "Status      open"                    "  ... status"
has "$OUT" "Type        task"                    "  ... type from issue_type"
has "$OUT" "Task kind   rework"                  "  ... task_kind"
has "$OUT" "Store       gc-toolkit"              "  ... store resolved from the id prefix"
has "$OUT" "Origin      operator"                "  ... gc.origin"
has "$OUT" "First react ruling → tk-frt"         "  ... first_reaction with its target"
has "$OUT" "[settled]"                           "  ... a settled takeaway is marked"
has "$(<"$STUB_GC_LOG")" "show tk-anchor --brief-deps" \
  "  ... via a --brief-deps read, so a hub bead's dependency bodies are never fetched"

run tk-anchor --json
eq "$(val "$J" title)"                       "rich anchor"     "subject.title — section A returns the subject's own title"
eq "$(val "$J" status)"                      open              "subject.status"
eq "$(val "$J" priority)"                    1                 "subject.priority (top-level)"
eq "$(val "$J" task_kind)"                   rework            "subject.task_kind"
eq "$(val "$J" routed_to)"                   ""                "subject.routed_to preserves the empty (cleared) route"
eq "$(val "$J" execution_routed_to)"         gc-toolkit/gc-toolkit.polecat "subject.execution_routed_to"
A=$(after "$J" anchor)
eq "$(val "$A" merge_result)"                pull_request      "anchor.merge_result present when the bead carries one"
eq "$(val "$A" pr_number)"                   9                 "anchor.pr_number"
eq "$(val "$A" branch)"                      polecat/tk-anchor "anchor.branch"
eq "$(val "$A" merged_target)"               main              "anchor.merged_target"
FR=$(after "$J" first_reaction)
eq "$(val "$FR" reaction)"                   ruling            "first_reaction.reaction"
eq "$(val "$FR" target)"                     tk-frt            "first_reaction.target"
eq "$(val "$J" origin)"                      operator          "subject.origin"
eq "$(val "$J" takeaway_settled)"            1                 "subject.takeaway_settled returned as the field it is"
# A bead with no merge_result carries a null anchor, not a fabricated one.
run tk-epic --json;   eq "$(val "$J" anchor)" null        "anchor is null when the bead is not an anchor"

# --- D. Context edges -------------------------------------------------------
run tk-anchor --json
E=$(after "$J" edges); C=$(after "$E" counts)
P=$(after "$E" parent)
eq "$(val "$P" id)"                          tk-epic           "edges.parent resolved from .parent"
eq "$(val "$P" title)"                       "the epic"        "  ... with the parent's title from the edge"
eq "$(val "$C" parent)"                      1                 "edges.counts.parent"
REL=$(json_get_ids "$E" relates_to); TB=$(json_get_ids "$E" tracked_by)
eq "$(count "$REL")"                         2                 "both relates spellings — relates-to AND related — are the relates class"
eq "$(sorted "$REL")"                        tk-rel,tk-rel2    "  ... and both are named"
eq "$(count "$TB")"                          1                 "tracked-by is read from the reverse tracks edge"
eq "$TB"                                     tk-conv           "  ... naming the conversation that tracks it"
has "$(<"$STUB_GC_LOG")" "dep list tk-anchor --direction=up --type tracks" \
  "  ... via a reverse dep-list, since the subject carries no tracked-by edge itself"

# The beads that wait on a bead: a closed design names the build it released.
: > "$STUB_GC_LOG"
run tk-design --json
eq "$(awaited id status edge)" \
  "tk-aw-next:open:blocks tk-aw-polish:in_progress:blocks tk-aw-dup:closed:until tk-aw-earlier:closed:blocks" \
  "awaited-by names the beads with a blocks or until edge to the subject, open ones first, each with its status and edge"
eq "$(val "$(after "$J" awaited_by)" title)" "the build it released" "  ... and its title"
C=$(after "$J" counts)
eq "$(val "$C" awaited_by) $(val "$C" awaited_by_open)" "4 2" "  ... counted in all and open"
eq "$(json_get_ids "$(after "$J" edges)" tracked_by)" tk-aw-track \
  "  ... while a conversation's tracks edge stays tracked-by, and a related review and a child are in neither"
eq "$(awaited keys)" "edge,id,status,title edge,id,status,title edge,id,status,title edge,id,status,title" \
  "  ... each cut to its id, title, status and edge"
eq "$(bodykeys | wc -l | tr -d ' ')" 0 "  ... and no waiter's body rides along"
eq "$(logcount 'show tk-design --brief-deps --include-dependents')" 1 \
  "  ... taken from the dependents the subject's own read carries"
eq "$(logcount 'dep list tk-design') $(logcount 'dep list tk-design .*--type tracks')" "1 1" \
  "  ... with no reverse read of its own beside tracked-by's"
run tk-design
has "$OUT" "awaited-by  4 (2 open): tk-aw-next (open, blocks), tk-aw-polish (in_progress, blocks), tk-aw-dup (closed, until), tk-aw-earlier (closed, blocks)" \
  "  ... and the text view names them on one line after the counts"

run tk-hub --json
eq "$(json_get_ids "$(after "$J" edges)" awaited_by)" \
  "tk-hw-01,tk-hw-02,tk-hw-03,tk-hw-04,tk-hw-05,tk-hw-06,tk-hw-07,tk-hw-08,tk-hw-09,tk-hw-10" \
  "a bead with more waiters than the cap names ten, open ones first, so a closed one that sorts first is cut"
C=$(after "$J" counts)
eq "$(val "$C" awaited_by) $(val "$C" awaited_by_open)" "12 11" "  ... and counts all twelve, eleven open"
run tk-hub
has "$OUT" "awaited-by  12 (11 open): tk-hw-01 (open, blocks), " "  ... the text view leads with the counts"
has "$OUT" "tk-hw-10 (open, blocks), and 2 more" "  ... and says how many it left out"
# The Edges section's line for a bead with no edge of any class.
NO_EDGES=$'\n    (none)'
hasnt "$OUT" "$NO_EDGES" "  ... and a bead whose only edges are its waiters does not read as having none"

run tk-anchor --json
C=$(after "$J" counts)
eq "$(val "$C" awaited_by) $(val "$C" awaited_by_open)" "0 0" "a bead nothing waits on counts no waiters"
eq "$(json_get_ids "$(after "$J" edges)" awaited_by)" "" "  ... and names none"
run tk-anchor
hasnt "$OUT" "awaited-by" "  ... and prints no awaited-by line"
run hq-city --db "$HQ/.beads"
has "$OUT" "$NO_EDGES" "a bead with no edge of any class reads (none)"

# --- B. Frontier (opt-in) ---------------------------------------------------
# Default output carries no frontier; it is added only on --frontier. A frontier
# run starts the gctk under test, which reads the store several times, so each
# subject runs once and its assertions query that run's output.
run tk-anchor --json;                 hasnt "$J" '"frontier":' "frontier is absent by default (opt-in)"
run tk-anchor --frontier --json
F=$(after "$J" frontier); B=$(after "$F" blockers)
eq "$(val "$F" verdict)"                    ready  "all blocks-blockers closed (one cross-store) reads ready"
eq "$(val "$B" closed)"                     1      "the same-store closed blocker is counted"
eq "$(json_get_strs "$F" foreign)"          or-far "  ... and the edge into another store holds nothing, listed as foreign"
eq "$(val "$B" open)"                       0      "no open blocker"
eq "$(items frontier)"                      ""     "closed blockers are counted, never listed"
eq "$(val "$F" holds)"                      clear  "  ... and gctk bead holds answers clear"

run tk-under --frontier --json
F=$(after "$J" frontier); I=$(first_item frontier)
eq "$(val "$F" verdict)" stuck "a member of a parked parent is held through it, so not ready"
eq "$(val "$F" holds)"   held  "  ... holds=held"
eq "$(json_get "$I" id) $(json_get "$I" ancestor)" "tk-pgate tk-parked" "  ... naming the parent's gate and the parent it sits on"

run tk-waiter --frontier --json
F=$(after "$J" frontier); I=$(first_item frontier)
eq "$(val "$F" verdict)" stuck    "a waits-for edge of its own is a wait the store cannot judge, so not ready"
eq "$(val "$F" holds)"   unjudged "  ... holds=unjudged"
eq "$(json_get "$I" id) $(val "$I" unjudged)" "tk-spawner true" "  ... and the spawner is listed as unjudged"

GCTK_BIN="$TMP/no-gctk" run tk-anchor --frontier --json
F=$(after "$J" frontier)
eq "$(val "$F" verdict) $(val "$F" holds)" "stuck unread" "a read of what holds it that cannot run fails the verdict closed"
has "$(val "$F" unread)" "no gctk binary at $TMP/no-gctk" "  ... and says why"

run tk-stuck --frontier --json
F=$(after "$J" frontier); I=$(first_item frontier)
eq "$(val "$F" verdict)"           stuck                   "an open unrouted blocker is stuck, so the verdict is stuck"
eq "$(json_get "$I" id)"           tk-op                   "  ... and the open blocker is named"
eq "$(json_get "$I" advance)"      stuck                   "  ... advance=stuck"
eq "$(json_get "$I" title)"        "open unrouted blocker" "  ... with its title"

run tk-adv --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "an open pool-routed blocker is advancing"
eq "$(json_get "$(first_item frontier)" advance)" advancing "  ... advance=advancing"

run tk-humangate --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" stuck "a human gate as the blocker is stuck, not advancing"
eq "$(json_get "$(first_item frontier)" advance)" stuck "  ... advance=stuck for the human gate"

run tk-convheld --frontier --json
I=$(first_item frontier)
eq "$(json_get "$I" id) $(json_get "$I" advance)" "tk-cv stuck" "a conversation its sitting holds is a person's, so stuck, not advancing"
eq "$(val "$(after "$J" frontier)" verdict)" stuck "  ... and so is the subject it holds"

run tk-inreview --frontier --json
eq "$(json_get "$(first_item frontier)" advance)" advancing "a review bead with a pour-cleared route is machine work, so advancing not stuck"
eq "$(val "$(after "$J" frontier)" verdict)" advancing "  ... so a subject held only by a review in flight is advancing, not stuck"

run tk-failclosed --frontier --json
F=$(after "$J" frontier)
eq "$(val "$F" verdict)"                  ready    "an edge onto a bead the store does not hold holds nothing, so the verdict is ready"
eq "$(val "$(after "$F" blockers)" open)" 0        "  ... counted as no open blocker"
eq "$(json_get_strs "$F" foreign)"        zz-ghost "  ... and listed as foreign"

# --- B2. The transitive walk --------------------------------------------------
# The walk reads a row by id with --brief, which gctk's reads do not carry.
WALKREAD='list --id [^ ]+ --all --brief'

run tk-w-sub1 --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" stuck "a routed blocker held by an orphan is stuck: the walk looks past one level"
eq "$(blkr tk-w-routed)" "stuck tk-w-orphan unrouted" "  ... and stuck_on names the orphan beneath it, unrouted"

run tk-w-sub2 --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "an armed blocker whose own blocker moves is advancing"
eq "$(blkr tk-w-armed)" "advancing - -" "  ... it takes its blocker's verdict, and carries no stuck_on"

run tk-w-sub3 --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" stuck "an armed blocker behind a human gate is stuck"
eq "$(blkr tk-w-armed2)" "stuck tk-w-gate human" "  ... naming the gate, so it reads apart from an orphan"

run tk-w-sub4 --frontier --json
I=$(first_item frontier); SO=$(after "$I" stuck_on)
eq "$(val "$(after "$J" frontier)" verdict)" stuck "a cycle of routed beads never drains, so it is stuck"
eq "$(json_get "$SO" why)" cycle "  ... why=cycle"
case "$(json_get "$SO" id)" in
  tk-w-cyc-a|tk-w-cyc-b) ok "  ... naming a bead on the cycle" ;;
  *) bad "  ... naming a bead on the cycle (got '$(json_get "$SO" id)')" ;;
esac

: > "$STUB_GC_LOG"
run tk-w-sub6 --frontier --json
F=$(after "$J" frontier)
eq "$(val "$(after "$F" blockers)" open)" 0 "a subject's only blocker, in another store, holds nothing"
eq "$(json_get_strs "$F" foreign)" or-w-mid "  ... and is listed as foreign, not walked"

run tk-w-xs --frontier --json
eq "$(blkr tk-w-xmid)" "stuck or-w-leaf unrouted" "a walked bead's blocker in another store is read off its list row"

run tk-w-sub7 --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "a routed chain three deep advances under the default budget"
run tk-w-sub7 --frontier --walk-budget 1 --json
eq "$(blkr tk-w-ch1)" "stuck tk-w-ch3 budget" "a walk out of budget reads stuck, naming the bead it could not read"
eq "$(val "$(after "$(after "$J" frontier)" blockers)" open)" 1 "  ... the subject's own blocker is read whatever the budget"

run tk-w-cl --frontier --walk-budget 2 --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "the budget counts open beads met: a closed row beside the chain costs nothing"

run tk-w-wide --frontier --walk-budget 4 --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "a level exactly as wide as the budget is read in full"
: > "$STUB_GC_LOG"
run tk-w-wide --frontier --walk-budget 3 --json
eq "$(blkr tk-w-fan)" "stuck tk-w-f4 budget" "a level wider than the budget has left reads stuck, naming the blocker past the budget"
eq "$(logcount 'list --id tk-w-f1,tk-w-f2,tk-w-f3 --all --brief')" 1 "  ... the batch asks for only the three beads the budget covers"
eq "$(logcount 'list --id [^ ]*tk-w-f4')" 0 "  ... and the fourth is never read"
: > "$STUB_GC_LOG"
run tk-w-refund --frontier --walk-budget 3 --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "a closed row in a read the budget cut short hands its share of the budget back"
eq "$(logcount 'list --id tk-w-r3 --all --brief')" 1 "  ... so the leaf the cut read left out is read next"

run tk-w-six --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "a routed chain six deep is read to its end"
run tk-w-seven --frontier --json
eq "$(blkr tk-w-v1)" "stuck tk-w-v7 budget" "  ... a seventh level is past the depth bound, so it reads stuck"

: > "$STUB_GC_LOG"
run tk-w-sub8 --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "a diamond of routed beads advances"
eq "$(logcount 'list --id [^ ]*tk-w-dshared[^ ]* --all --brief')" 1 "  ... and the shared blocker is read once"
eq "$(logcount 'list --id tk-w-d1,tk-w-d2 --all --brief')" 1 \
  "  ... the subject's waits in one batched read of their store"

: > "$STUB_GC_LOG"
run tk-w-sub9 --frontier --json
eq "$(blkr tk-w-stopper)" "stuck tk-w-stopper unrouted" "a stuck blocker names itself"
eq "$(logcount 'list --id [^ ]*tk-w-hidden')" 0 "  ... and the walk never reads what a stuck bead waits on"

# Merge anchors: the recorded merge axis, not the route the merge cadence clears.
: > "$STUB_GC_LOG"
run tk-w-anchors --frontier --json
eq "$(blkr tk-a-approval)" "stuck tk-a-approval approval" "a settled PR waiting on review is stuck on the operator's approval"
eq "$(blkr tk-a-progress)" "advancing - -" "a progressing anchor advances, a requested change being worked"
eq "$(blkr tk-a-preopen)" "advancing - -" "a settled anchor before its PR opens advances: the PR-open pass publishes it"
eq "$(blkr tk-a-approved)" "advancing - -" "a settled, approved PR advances to the merge pass"
eq "$(blkr tk-a-hold)" "stuck tk-a-hold merge-hold" "an operator merge hold is stuck"
eq "$(blkr tk-a-blocked)" "stuck tk-a-blocked merge-blocked" "an anchor its machine axis records blocked is stuck"
eq "$(blkr tk-a-stale)" "stuck tk-a-stale unread" "a posture read at another head than the axis is unread, so stuck"
eq "$(blkr tk-a-noaxis)" "stuck tk-a-noaxis unread" "an anchor with no recorded axis is unread, so stuck"
eq "$(blkr tk-a-humanstate)" "stuck tk-a-humanstate human" "an anchor parked in a human state is stuck on a person"
eq "$(blkr tk-a-rpend)" "advancing - -" "an approved PR on the pending record advances to the landing order, though its bead is blocked"
eq "$(blkr tk-a-rreview)" "stuck tk-a-rreview approval" "a PR on the pending record waiting on review is stuck on the operator's approval"
eq "$(blkr tk-a-rnopost)" "stuck tk-a-rnopost unread" "a PR on the pending record with no recorded posture is unread, so stuck"
eq "$(blkr tk-a-rhead)" "advancing - -" "a PR whose head moved advances: the refinery validates the new head"
eq "$(blkr tk-a-rhold)" "stuck tk-a-rhold merge-hold" "an operator merge hold on the pending record is stuck"
eq "$(logcount "$WALKREAD")" 1 "  ... the same-store blockers cost one read"

# A bead's own state, one rule per blocker.
run tk-w-kinds --frontier --json
eq "$(blkr tk-k-blocked)" "stuck tk-k-blocked held" "a routed bead whose status is blocked is held, not advancing"
eq "$(blkr tk-k-deferred)" "stuck tk-k-deferred held" "a deferred bead is held"
eq "$(blkr tk-k-validation)" "advancing - -" "a validation pass with a pour-cleared route is machine work"
eq "$(blkr tk-k-finding)" "advancing - -" "a must-fix finding is machine work the review cycle owns"
eq "$(blkr tk-k-needsyou)" "stuck tk-k-needsyou human" "a finding that needs the operator is stuck on a person"
eq "$(blkr tk-k-refinery)" "advancing - -" "an open bead assigned to the refinery is in its queue"
eq "$(blkr tk-k-capped)" "stuck tk-k-capped capped" "an armed dispatch at its sling-failure cap is stuck"
eq "$(blkr tk-k-hooked)" "advancing - -" "a hooked bead is held by an agent, so advancing"
eq "$(blkr tk-k-gate)" "stuck tk-k-gate human" "a human gate, which a bare listing hides and which carries no route, is read and stuck on a person"
eq "$(blkr tk-k-humanroute)" "advancing - -" "a human route marks no person's hold: it reads as the route it is"

run tk-w-decides --frontier --json
eq "$(blkr tk-k-decision)" "stuck tk-k-decision human" "a decision is a person's to make"

run tk-w-sub3 --frontier
has "$OUT" "tk-w-armed2  tk-w-armed2 (open, stuck on tk-w-gate: human)" "the human block names the stuck leaf and why"
run tk-w-sub9 --frontier
has "$OUT" "(open, stuck: unrouted)" "  ... and a blocker that stops itself as just why"

# --- B3. The bead a live run works -------------------------------------------
# run-lib.sh's map reads a store's runs from its roots, pinned to the store the
# walk read its rows from. MAPREAD is that read, which gctk's own read of the
# runs, asking for gates, infrastructure and templates too, does not match.
MAPREAD='list --has-metadata-key gc.input_convoy_id --include-ephemeral --json'
maps() { logcount "$MAPREAD"; }
eq "$(bstatus tk-r-eroot)" closed "the fixture's ended run is a run whose root closed"

: > "$STUB_GC_LOG"
run tk-r-sub --frontier --json
eq "$(blkr tk-r-work)" "advancing - -" "an open, unassigned, unrouted bead a live run works advances"
eq "$(blkr tk-r-ended)" "stuck tk-r-ended unrouted" "  ... one whose run's root closed is unrouted"
eq "$(blkr tk-r-anchor)" "stuck tk-r-anchor approval" "  ... and a merge anchor a live run works is judged as the anchor it is"
eq "$(val "$(after "$J" frontier)" verdict)" stuck "  ... so the subject waiting on them is stuck"
eq "$(maps)" 1 "  ... and the store holding them is asked for its runs once"
eq "$(blkr tk-r-work) | $(blkr tk-r-ended)" "advancing - - | stuck tk-r-ended unrouted" \
  "run-lib.sh's own map tells the bead a live run works from one whose run ended"
eq "$(logcount "--db $R_TK/.beads $MAPREAD") $(maps)" "1 1" \
  "  ... reading it once, from the store the rows were read from"
run tk-r-ended --json
eq "$(json_get_ids "$(after "$J" edges)" tracked_by) $(val "$(after "$J" tracked_by)" status)" "tk-r-eroot-cv open" \
  "  ... though the ended run's input convoy is still open"

: > "$STUB_GC_LOG"
run tk-r-deep --frontier --json
eq "$(blkr tk-r-w2)" "stuck tk-r-orphan unrouted" "the walk reads on below a bead a live run works, to the orphan beneath"
eq "$(maps)" 1 "  ... asking the store for its runs once across the levels"
run tk-r-six --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "a bead a live run works on the last level the walk reads advances"

: > "$STUB_GC_LOG"
run tk-r-two --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" stuck "orphans in two stores leave the routed bead over them stuck"
eq "$(maps)" 2 "  ... and each store is asked for its runs"
eq "$(logcount "--db $R_TK/.beads $MAPREAD") $(logcount "--db $R_OR/.beads $MAPREAD")" "1 1" \
  "  ... and, with orphans in two stores, each store's runs from that store"

STUB_FAIL_ON="$MAPREAD" run tk-r-sub --frontier --json
eq "$(blkr tk-r-work)" "stuck tk-r-work unknown" "a store whose runs do not read leaves a bead with no route unknown"
eq "$(blkr tk-r-ended)" "stuck tk-r-ended unknown" "  ... whatever its run"

: > "$STUB_GC_LOG"
run tk-adv --frontier --json
run tk-r-work --frontier --json
run hq-city --db "$HQ/.beads" --frontier --json
eq "$(maps)" 0 "no runs are read when no walked bead reads unrouted, nor for a subject nothing waits on"

: > "$STUB_GC_LOG"
run tk-r-design --frontier --horizon --json
eq "$(kid tk-r-impl)" "advancing - -" "a child armed behind its subject advances while a live run works the subject"
eq "$(maps)" 1 "  ... the subject's runs read because a walked bead waits on it"

run tk-r-epic --horizon --json
H=$(after "$J" children)
eq "$(val "$H" open) $(val "$H" advancing) $(val "$H" stuck)" "2 1 1" \
  "the epic-health snapshot counts the child a live run works as advancing"
eq "$(kid tk-r-work)" "advancing - -" "  ... that child"
eq "$(kid tk-r-ended)" "stuck tk-r-ended unrouted" "  ... and its sibling whose run ended as unrouted"

run tk-r-tsub --frontier --json
eq "$(blkr tk-r-twin)" "advancing - -" "a live run in gc-toolkit's store works its tk-r-twin"
: > "$STUB_GC_LOG"
run hq-pin --db "$HQ/.beads" --horizon --json
eq "$(kid tk-r-twin) | $(kid hq-pmid)" "stuck tk-r-twin unrouted | stuck tk-r-lone unrouted" \
  "  ... and leaves the city store's idle tk-r-twin unrouted, though gc-toolkit's runs were read in the same walk"
eq "$(logcount "--db $HQ/.beads $MAPREAD") $(logcount "--db $R_TK/.beads $MAPREAD")" "1 1" \
  "  ... once each, each from its own store"

# A roster that does not read places no store. A read by id still finds its
# rows, since gc routes an id to the store that owns it, but a read of runs
# names no bead, so gc would answer it from the caller's own store.
: > "$STUB_GC_LOG"
STUB_FAIL_ON="rig list" run hq-pin --horizon --json
eq "$(kid tk-r-twin) | $(kid hq-pmid)" "stuck tk-r-twin unknown | stuck tk-r-lone unknown" \
  "with no roster, the city store's idle tk-r-twin and the orphan read unknown, never judged by another store's runs"
eq "$(maps)" 0 "  ... and no store's runs are read"
: > "$STUB_GC_LOG"
STUB_FAIL_ON="rig list" run hq-pin --db "$HQ/.beads" --horizon --json
eq "$(kid tk-r-twin) | $(kid hq-pmid)" "stuck tk-r-twin unrouted | stuck tk-r-lone unknown" \
  "  ... while --db places the subject's store, whose runs read, and leaves unknown only the orphan whose store it cannot place"
eq "$(logcount "--db $HQ/.beads $MAPREAD") $(maps)" "1 1" \
  "  ... reading the runs of the store --db names alone"

# --- C. Horizon (opt-in) ----------------------------------------------------
run tk-epic --json;                   hasnt "$J" '"horizon":' "horizon is absent by default (opt-in)"
: > "$STUB_GC_LOG"; run tk-epic --horizon --json
H=$(after "$J" children)
eq "$(val "$H" total)"     10 "every direct child is counted, in any status, and a bd set-state event is not a child"
eq "$(val "$H" open)"      9  "  ... nine are open"
eq "$(val "$H" closed)"    1  "  ... the done child is counted (the listing asks for every status), and the closed event is not"
eq "$(val "$H" advancing)" 5  "  ... pool-routed, in-progress, hooked, a progressing anchor and a pour-cleared rework child advance"
eq "$(val "$H" stuck)"     4  "  ... the operator-queued, armed-behind-the-gate, pinned and custom-status children are stuck"
KIDS=$(items horizon)
eq "$(sorted "$KIDS")" "tk-anchor,tk-kid-armed,tk-kid-custom,tk-kid-hooked,tk-kid-human,tk-kid-pinned,tk-kid-pool,tk-kid-prog,tk-kid-rework" \
  "open children are listed; the done one is not"
case ",$KIDS," in *,tk-kid-done,*) bad "the done child is never in the open list" ;; *) ok "the done child is never in the open list" ;; esac
eq "$(kid tk-kid-pool)" "advancing - -" "a pool-routed open child advances"
eq "$(json_get "$(item horizon tk-kid-human)" advance)" stuck "an open child in the operator's queue is stuck"
eq "$(kid tk-kid-human)" "stuck tk-kid-human human" "  ... and names itself, a person's to move"
eq "$(kid tk-kid-rework)" "advancing - -" "a pour-cleared rework child advances, with no stuck_on"
eq "$(kid tk-kid-armed)" "stuck tk-hg human" "an armed child takes its blocker's verdict: behind a human gate it is stuck, naming the gate"
eq "$(kid tk-kid-hooked)" "advancing - -" "a hooked child is listed and advances: an agent holds it"
eq "$(kid tk-kid-pinned)" "stuck tk-kid-pinned held" "a pinned child is listed and stuck on its hold, though it carries a route"
eq "$(kid tk-kid-custom)" "stuck tk-kid-custom held" "a child in a status its store adds is listed, and fails closed as held"
eq "$(json_get "$(item horizon tk-kid-custom)" status)" in_review "  ... reporting the status as the store holds it"
eq "$(logcount 'list --id [^ ]*tk-hg[^ ]* --all --brief')" 1 "  ... read through the listing's list-shaped edge"
eq "$(logcount 'list --id [^ ]*tk-kid-')" 0 "  ... while the children themselves cost no read: the listing carries their rows"
hasnt "$(openlist horizon)" '"advance":"advancing","stuck_on"' "an advancing child carries no stuck_on key"

# --- one call is enough: the opening's subject slice, verdict and snapshot --
# The done-condition: with both dimensions opted in, ONE invocation yields the
# subject slice, the readiness verdict and the epic-health snapshot — no forced
# follow-up read by the caller.
run tk-epic --frontier --horizon --json
eq "$(val "$J" id)|$(val "$(after "$J" frontier)" verdict)|$(val "$(after "$J" children)" total)" "tk-epic|ready|10" \
  "one call returns subject slice, readiness verdict and epic-health snapshot together"

# --- E. Store pinning, and the object-vs-array shape ------------------------
run tk-missing
eq "$RC" 4 "a not-found id (\`{\"error\":…}\` object) is reported, not parsed as a bead"
has "$ERR" "did not resolve to a bead" "  ... with a diagnostic"

run hq-city --db "$HQ/.beads"
eq "$RC" 0 "--db reaches the HQ store, which no --rig value names"
has "$OUT" "Store       mycity" "  ... and the rig is recovered from the db path"

run or-far --store rig:otherrig --json
eq "$(val "$J" status)" closed "--store rig:<name> pins the read to that rig's store"

# --- the stdout notice line, and control bytes, do not break the read -------
STUB_SHOW_NOTICE=gc-toolkit run tk-anchor
eq "$RC" 0 "a leading \`gc bd:\` notice line does not break the read (rc)"
has "$OUT" "Status      open" "  ... and the bead still renders"
STUB_SHOW_NOTICE=gc-toolkit STUB_FAIL_ON="rig list" run tk-anchor
eq "$RC" 0 "  ... nor that of a read no roster pins (rc)"
has "$OUT" "Status      open" "  ... which still renders"

STUB_SHOW_RAW_CONTROL=1 run tk-ctrl
eq "$RC" 0 "a raw C0 byte in notes is scrubbed before jq, not fatal"
has "$OUT" "Status      open" "  ... and the bead renders"
STUB_SHOW_RAW_CONTROL=1 run tk-nul
eq "$RC" 0 "a raw NUL in notes does not switch the notice-strip to binary and drop the payload"
has "$OUT" "Status      open" "  ... and the bead still renders"

# --- usage ------------------------------------------------------------------
run;                       eq "$RC" 2 "no id is a usage error"
run tk-anchor extra-id;    eq "$RC" 2 "a second id is a usage error"
run tk-anchor --store nope;eq "$RC" 2 "a --store that is not rig:<name> is a usage error"
run --nope tk-anchor;      eq "$RC" 2 "an unknown flag is a usage error"
runb tk-anchor --store;    eq "$RC" 2 "a --store with no value is a usage error, not a hang"
has "$ERR" "needs a value" "  ... with a diagnostic"
runb tk-anchor --db;       eq "$RC" 2 "a --db with no value is a usage error, not a hang"
runb tk-anchor --walk-budget;   eq "$RC" 2 "a --walk-budget with no value is a usage error, not a hang"
run tk-anchor --walk-budget 0;  eq "$RC" 2 "a zero --walk-budget is a usage error"
run tk-anchor --walk-budget x;  eq "$RC" 2 "a non-numeric --walk-budget is a usage error"

# --- the raw-bd regression guard: no probe ever bypassed gc bd --------------
eq "$(wc -l < "$DIRECT_BD_LOG" | tr -d ' ')" "0" \
  "no store was reached through a direct \`bd\` at any point in the run"

# --- the omit clause: no body of any bead is ever returned ------------------
run tk-anchor --frontier --horizon --json
eq "$(bodykeys | wc -l | tr -d ' ')" "0" \
  "no description, notes or comment field appears anywhere in the JSON"

echo
echo "bead-context: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
