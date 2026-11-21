#!/usr/bin/env bash
# Hermetic test for assets/scripts/bead-context.sh.
#
# The tool rebuilds a subject's opening context in one call, so the assertions
# target the contract that opening reads: subject core (A) with the anchor,
# first_reaction, origin and takeaway fields; context edges (D) — parent,
# relates-to (both the `relates-to` and older `related` spellings), the reverse
# `tracks` edges (a conversation about the bead), and the beads that wait on it
# by a reverse `blocks` or `until` edge, open ones first and capped — each with
# a count; the store that answered (E); and, each behind its opt-in flag, the
# frontier verdict over {ready, advancing, stuck} (B) and the direct-children
# epic-health snapshot (C). The frontier and each named bead's advance are the
# answers of `gctk bead holds` and `gctk bead stands`, built from this checkout
# and run over the fake stores, so the cases here hold the keys the script
# composes from them and the readings its callers rely on, and standing's Go
# tests hold each rule. The status scope of the child listing and the three
# `gc bd show --json` quirks each get a case.
#
# `gc` is the compiled fake gc of test-harness.sh, over a store per rig: the
# gc-toolkit and otherrig rigs each keep one in their .beads directory, and the
# city's own store, the one the rig list marks hq, is also the fake's default
# store, as gc answers a call no rig claims from it. Every edge is a dep row,
# so a show and a listing answer each edge as bd does. A direct `bd` is the
# regression a stub of its own fails on. No live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/bead-context.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bead-context-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
harness_init

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
# leaves out (an edge into another store, which holds nothing) — so its frontier
# verdict is ready. It also carries a description and notes; the read returns
# its title but never that body.
bead tk-anchor <<'J'
{"id":"tk-anchor","title":"rich anchor","status":"open","issue_type":"task","priority":1,
 "assignee":"gc-toolkit/gc-toolkit.refinery","parent":"tk-epic",
 "description":"subject body prose the read must never surface",
 "notes":"## Current state\noperational notes the read must never surface",
 "metadata":{"task_kind":"rework","gc.routed_to":"","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat",
   "merge_result":"pull_request_head_changed","pr_number":"9","branch":"polecat/tk-anchor","merged_target":"main","target":"main",
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
{"id":"tk-convheld","title":"held by a conversation","status":"open","issue_type":"task","metadata":{"merge_result":"pull_request_pending"}}
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

# --- where a named bead stands ---------------------------------------------
# The cases the shared answer reads apart from the classifier this script kept
# before it asked gctk, each a wait of a subject or a child of an epic. tk-sent
# is routed work a ruling or a sitting sent, and tk-unsent work nobody routes.
bead tk-sent <<'J'
{"id":"tk-sent","title":"the work a ruling sent","status":"open","issue_type":"task",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead tk-unsent <<'J'
{"id":"tk-unsent","title":"work nobody routes","status":"open","issue_type":"task","metadata":{}}
J
# A decision a ruling left waiting on the work it sent, which tk-ruled-wait
# waits on, and one left waiting on work nobody routes.
bead tk-ruled <<'J'
{"id":"tk-ruled","title":"a ruling's decision","status":"open","issue_type":"decision","metadata":{}}
J
edge tk-ruled blocks tk-sent
bead tk-ruled-wait <<'J'
{"id":"tk-ruled-wait","title":"waits on the decision","status":"open","issue_type":"task","metadata":{}}
J
edge tk-ruled-wait blocks tk-ruled
bead tk-ruled2 <<'J'
{"id":"tk-ruled2","title":"a ruling's decision behind unrouted work","status":"open","issue_type":"decision","metadata":{}}
J
edge tk-ruled2 blocks tk-unsent
# A conversation its sitting stays in, open under its alias and waiting on the
# work it sent, which holds the bead it tracks.
bead tk-stayheld <<'J'
{"id":"tk-stayheld","title":"held by a conversation its sitting stays in","status":"open","issue_type":"task","metadata":{}}
J
edge tk-stayheld blocks tk-stay
bead tk-stay <<'J'
{"id":"tk-stay","title":"what the sitting sent","status":"open","issue_type":"task",
 "assignee":"gc-toolkit/converse-claude-opus.c-tk-stay","metadata":{}}
J
edge tk-stay tracks tk-stayheld
edge tk-stay blocks tk-sent
# Settled pull requests that wait on the operator's review: a posture of none,
# and one of commented. tk-prwait waits on both.
bead tk-pr-none <<'J'
{"id":"tk-pr-none","title":"a settled PR nobody reviewed","status":"open","issue_type":"task",
 "metadata":{"merge_result":"pull_request","pr_number":"11","pr.machine":"settled@h1@2026-10-01T00:00:00Z","pr_posture":"none@h1@2026-10-01T00:00:00Z"}}
J
bead tk-pr-commented <<'J'
{"id":"tk-pr-commented","title":"a settled PR with comments","status":"open","issue_type":"task",
 "metadata":{"merge_result":"pull_request","pr_number":"12","pr.machine":"settled@h1@2026-10-01T00:00:00Z","pr_posture":"commented@h1@2026-10-01T00:00:00Z"}}
J
bead tk-prwait <<'J'
{"id":"tk-prwait","title":"waits on two reviews","status":"open","issue_type":"task","metadata":{}}
J
edge tk-prwait blocks tk-pr-none
edge tk-prwait blocks tk-pr-commented
# Work nobody routes, behind which a human gate waits: the person's move is what
# stops tk-chain.
bead tk-chain <<'J'
{"id":"tk-chain","title":"waits on work behind a person","status":"open","issue_type":"task","metadata":{}}
J
edge tk-chain blocks tk-norte
bead tk-norte <<'J'
{"id":"tk-norte","title":"unrouted, behind a gate","status":"open","issue_type":"task","metadata":{}}
J
edge tk-norte blocks tk-hg2
bead tk-hg2 <<'J'
{"id":"tk-hg2","title":"which way","status":"open","issue_type":"gate","await_type":"human","metadata":{}}
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
# A bead that waits on the root of the live run that works it, as a pull
# request's anchor waits on its review run: the wait is its own work.
put "$R_TK/.beads" "{\"id\":\"tk-r-attached\",\"title\":\"waits on the run that works it\",\"status\":\"open\",\"issue_type\":\"task\",\"metadata\":$POURED}"
edge tk-r-attached blocks tk-r-aroot
pour tk-r-attached tk-r-aroot in_progress

# tk-outer: an epic whose members are an epic with a routed member, a Delivery
# whose only member nobody routes, and routed work the Product Owner holds.
bead tk-outer <<'J'
{"id":"tk-outer","title":"an outer epic","status":"open","issue_type":"epic","metadata":{"epic_hypothesis":"it helps"}}
J
bead tk-inner <<'J'
{"id":"tk-inner","title":"a child epic","status":"open","issue_type":"epic","parent":"tk-outer","metadata":{"epic_hypothesis":"it helps too"}}
J
bead tk-inner-kid <<'J'
{"id":"tk-inner-kid","title":"the child epic's routed member","status":"open","issue_type":"task","parent":"tk-inner",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead tk-delivery <<'J'
{"id":"tk-delivery","title":"a Delivery","status":"open","issue_type":"epic","parent":"tk-outer","metadata":{}}
J
bead tk-delivery-kid <<'J'
{"id":"tk-delivery-kid","title":"the Delivery's unrouted member","status":"open","issue_type":"task","parent":"tk-delivery","metadata":{}}
J
bead tk-mayor <<'J'
{"id":"tk-mayor","title":"routed work held for the Product Owner","status":"open","issue_type":"task","parent":"tk-outer",
 "labels":["hold:mayor"],"metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J

# tk-epic: the horizon fixture. Its direct children (found by the reverse
# parent-child listing, never its own edges) cover the readings a horizon
# shows: an open pool-routed child, an in-progress one and a hooked one advance.
# tk-anchor, a pull request nothing reviewed and nothing works, waits on the
# operator's review. A child in the operator's queue is a person's to move, and
# tk-kid-armed, armed behind the human gate tk-hg, waits on that gate.
# tk-kid-rework, a rework bead whose pour cleared its route, is work nobody
# routes. Three children sit in statuses a default or --status listing can leave
# out: a hooked child, a pinned one, and one in a status its store adds, which no
# pool offers. One done child is counted, never listed. tk-kid-event is the
# closed event `bd set-state` files under a bead whose state changed, and it is
# neither counted nor listed. The epic's own blocks are none, so its frontier
# verdict is ready.
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
eq "$(val "$A" merge_result)"                pull_request_head_changed      "anchor.merge_result present when the bead carries one"
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
eq "$(val "$F" verdict)"                    ready  "all blocks-blockers closed (one in another store) reads ready"
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
eq "$(blkr tk-pgate)" "stuck tk-pgate question" "  ... a gate a person answers, a question"

run tk-waiter --frontier --json
F=$(after "$J" frontier); I=$(first_item frontier)
eq "$(val "$F" verdict)" stuck    "a waits-for edge of its own is a wait the store cannot judge, so not ready"
eq "$(val "$F" holds)"   unjudged "  ... holds=unjudged"
eq "$(json_get "$I" id) $(val "$I" unjudged)" "tk-spawner true" "  ... and the spawner is listed as unjudged"
eq "$(blkr tk-spawner)" "stuck tk-spawner unread" "  ... stuck on the wait it cannot judge, unread"

GCTK_BIN="$TMP/no-gctk" run tk-anchor --frontier --json
F=$(after "$J" frontier)
eq "$(val "$F" verdict) $(val "$F" holds)" "stuck unread" "a read of what holds it that cannot run fails the verdict closed"
has "$(val "$F" unread)" "no gctk binary at $TMP/no-gctk" "  ... and says why"

# A gctk that answers what holds the subject and nothing about where it stands.
{ printf '#!/bin/sh\n'; printf '[ "${2:-}" = stands ] && exit 1\nexec "%s" "$@"\n' "$GCTK_BIN"; } > "$TMP/gctk-holds-only"
chmod +x "$TMP/gctk-holds-only"
GCTK_BIN="$TMP/gctk-holds-only" run tk-adv --frontier --json
F=$(after "$J" frontier)
eq "$(val "$F" verdict) $(val "$F" holds)" "stuck blocked" "a subject gctk bead stands does not answer fails the verdict closed"
has "$(val "$F" unread)" "gctk bead stands" "  ... and says which read did not answer"
eq "$(blkr tk-routed)" "stuck tk-routed unread" "  ... and each wait it names reads stuck on itself, unread"
GCTK_BIN="$TMP/gctk-holds-only" run tk-anchor --frontier --json
F=$(after "$J" frontier)
eq "$(val "$F" verdict) $(val "$F" holds) $(val "$F" unread)" "ready clear <absent>" \
  "  ... while a subject nothing holds is ready by gctk bead holds alone"

# gctk bead stands gives a closed bead no frontier, and nothing holds one.
run tk-design --frontier --json
F=$(after "$J" frontier)
eq "$(val "$F" verdict) $(val "$F" holds) $(val "$F" unread)" "ready clear <absent>" "a closed subject nothing holds reads ready"

run tk-stuck --frontier --json
F=$(after "$J" frontier); I=$(first_item frontier)
eq "$(val "$F" verdict)"           stuck                   "work nobody routes as the blocker leaves the subject stuck"
eq "$(json_get "$I" id)"           tk-op                   "  ... and the open blocker is named"
eq "$(blkr tk-op)"                 "stuck tk-op not-scheduled" "  ... stuck on itself, not scheduled"
eq "$(json_get "$I" title)"        "open unrouted blocker" "  ... with its title"

run tk-adv --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "an open pool-routed blocker is advancing"
eq "$(blkr tk-routed)" "advancing - -" "  ... advance=advancing, and no stuck_on"
hasnt "$(openlist frontier)" '"advance":"advancing","stuck_on"' "an advancing wait carries no stuck_on key"

run tk-humangate --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" stuck "a human gate as the blocker is stuck, not advancing"
eq "$(blkr tk-hg)" "stuck tk-hg question" "  ... the gate is a question a person owes"

run tk-convheld --frontier --json
eq "$(blkr tk-cv)" "stuck tk-cv conversation" "a conversation its sitting holds is a person's, so stuck, not advancing"
eq "$(val "$(after "$J" frontier)" verdict)" stuck "  ... and so is the subject it holds"

run tk-inreview --frontier --json
eq "$(blkr tk-rev)" "advancing - -" "a review of the subject's own pull request is its own work, so advancing"
eq "$(val "$(after "$J" frontier)" verdict)" advancing "  ... so a subject held only by its own review is advancing, not stuck"

run tk-r-attached --frontier --json
eq "$(blkr tk-r-aroot)" "advancing - -" "the root of the live run that works the subject is its own work"
eq "$(val "$(after "$J" frontier)" verdict)" advancing "  ... so a bead waiting on its own run is advancing"

run tk-failclosed --frontier --json
F=$(after "$J" frontier)
eq "$(val "$F" verdict)"                  ready    "an edge onto a bead the store does not hold holds nothing, so the verdict is ready"
eq "$(val "$(after "$F" blockers)" open)" 0        "  ... counted as no open blocker"
eq "$(json_get_strs "$F" foreign)"        zz-ghost "  ... and listed as foreign"

# A decision a ruling left waiting on the work it sent, and a conversation its
# sitting stays in, advance while that work does.
run tk-ruled-wait --frontier --json
eq "$(blkr tk-ruled)" "advancing - -" "a decision a ruling left waiting on the work it sent advances while that work does"
eq "$(val "$(after "$J" frontier)" verdict)" advancing "  ... and so does what waits on it"
run tk-ruled --frontier --json
eq "$(val "$(after "$J" frontier)" verdict)" advancing "  ... read as the subject, its own frontier advances with the work"
run tk-ruled2 --frontier --json
eq "$(blkr tk-unsent)" "stuck tk-unsent not-scheduled" "  ... and one waiting on work nobody routes is stuck on that work"
run tk-stayheld --frontier --json
eq "$(blkr tk-stay)" "advancing - -" "a conversation its sitting stays in advances while the work it sent does"

# A settled pull request whose posture is none or commented waits on the
# operator's review.
run tk-prwait --frontier --json
eq "$(blkr tk-pr-none)" "stuck tk-pr-none pull-request" "a settled PR with no review is stuck on itself, waiting on review"
eq "$(blkr tk-pr-commented)" "stuck tk-pr-commented pull-request" "  ... and so is one with comments and no verdict"
eq "$(val "$(after "$J" frontier)" verdict)" stuck "  ... so the subject waiting on them is stuck"

# A person's move behind work nobody routes is what stops the bead.
run tk-chain --frontier --json
eq "$(blkr tk-norte)" "stuck tk-hg2 own-wait" "work nobody routes, behind a human gate, is stuck on the gate"

run tk-stuck --frontier
has "$OUT" "tk-op  open unrouted blocker (open, stuck: not-scheduled)" "the human block names a blocker that stops itself by just why"
run tk-chain --frontier
has "$OUT" "tk-norte  unrouted, behind a gate (open, stuck on tk-hg2: own-wait)" "  ... and one stopped beneath it by the bead and why"

# --- C. Horizon (opt-in) ----------------------------------------------------
run tk-epic --json;                   hasnt "$J" '"horizon":' "horizon is absent by default (opt-in)"
: > "$STUB_GC_LOG"; run tk-epic --horizon --json
H=$(after "$J" children)
eq "$(val "$H" total)"     10 "every direct child is counted, in any status, and a bd set-state event is not a child"
eq "$(val "$H" open)"      9  "  ... nine are open"
eq "$(val "$H" closed)"    1  "  ... the done child is counted (the listing asks for every status), and the closed event is not"
eq "$(val "$H" advancing)" 3  "  ... the pool-routed, in-progress and hooked children advance"
eq "$(val "$H" stuck)"     6  "  ... the rest are stuck"
KIDS=$(items horizon)
eq "$(sorted "$KIDS")" "tk-anchor,tk-kid-armed,tk-kid-custom,tk-kid-hooked,tk-kid-human,tk-kid-pinned,tk-kid-pool,tk-kid-prog,tk-kid-rework" \
  "open children are listed; the done one is not"
case ",$KIDS," in *,tk-kid-done,*) bad "the done child is never in the open list" ;; *) ok "the done child is never in the open list" ;; esac
eq "$(kid tk-kid-pool)" "advancing - -" "a pool-routed open child advances"
eq "$(kid tk-kid-prog)" "advancing - -" "an in-progress child advances"
eq "$(kid tk-kid-hooked)" "advancing - -" "a hooked child is listed and advances: an agent holds it"
eq "$(kid tk-anchor)" "stuck tk-anchor pull-request" "a pull request nothing reviewed waits on the operator's review"
eq "$(kid tk-kid-human)" "stuck tk-kid-human routed-to-you" "an open child in the operator's queue is a person's to move"
eq "$(kid tk-kid-armed)" "stuck tk-hg own-wait" "an armed child behind a human gate is stuck on the gate"
eq "$(kid tk-kid-rework)" "stuck tk-kid-rework not-scheduled" "a rework child whose route the pour cleared is work nobody routes"
eq "$(kid tk-kid-pinned)" "stuck tk-kid-pinned status" "a pinned child is listed and stuck on its status, though it carries a route"
eq "$(kid tk-kid-custom)" "stuck tk-kid-custom status" "a child in a status its store adds is listed, and stuck on that status"
eq "$(json_get "$(item horizon tk-kid-custom)" status)" in_review "  ... reporting the status as the store holds it"
hasnt "$(openlist horizon)" '"advance":"advancing","stuck_on"' "an advancing child carries no stuck_on key"

run tk-r-epic --horizon --json
H=$(after "$J" children)
eq "$(val "$H" open) $(val "$H" advancing) $(val "$H" stuck)" "2 1 1" \
  "the epic-health snapshot counts the child a live run works as advancing"
eq "$(kid tk-r-work)" "advancing - -" "  ... that child, from the run's start"
eq "$(kid tk-r-ended)" "stuck tk-r-ended not-scheduled" "  ... and its sibling whose run ended is work nobody routes"

run tk-outer --horizon --json
eq "$(kid tk-inner)" "advancing - -" "a child epic advances while every open member does"
eq "$(kid tk-delivery)" "stuck tk-delivery-kid not-scheduled" "a Delivery is stuck on what stops its first open member"
eq "$(kid tk-mayor)" "stuck tk-mayor not-scheduled" "routed work held for the Product Owner is work nobody takes"

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
