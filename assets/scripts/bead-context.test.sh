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
# `gc` is stubbed over a file-per-bead ledger under each fake rig; a direct `bd`
# is the regression the stub fails on. gctk's reads are answered from the same
# files through holds-store.stub.sh. No live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/bead-context.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bead-context-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# --- fake city --------------------------------------------------------------
R_TK="$TMP/rigs/gc-toolkit"; R_OR="$TMP/rigs/otherrig"; HQ="$TMP/hq"
mkdir -p "$TMP/bin" "$R_TK/.beads" "$R_OR/.beads" "$HQ/.beads"
cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"gc-toolkit","path":"$R_TK","prefix":"tk","hq":false},
  {"name":"otherrig","path":"$R_OR","prefix":"or","hq":false},
  {"name":"mycity","path":"$HQ","prefix":"hq","hq":true}
]}
JSON
export FAKE_RIGS="$TMP/rigs.json"
export FAKE_GC_LOG="$TMP/gc.log"; : > "$FAKE_GC_LOG"
export FAKE_BD_LOG="$TMP/bd.log"; : > "$FAKE_BD_LOG"
export STUB_ROOT="$TMP"
export STUB_PREFACE=""
# The frontier and the horizon read gctk bead holds and gctk bead stands, built
# from this checkout and run over the fake stores.
export HOLDS_STUB="$HERE/holds-store.stub.sh" GC_NO_API=1
GCTK_BIN="$("$HOLDS_STUB" build "$TMP/gctk")" || { echo "FAIL - gctk did not build, so no frontier can be read"; exit 1; }
export GCTK_BIN

bead() { cat > "$1/.beads/$2.json"; }   # bead <store-repo> <id>  (object on stdin)

# tk-anchor: a subject core (A) with every field the opening reads — anchor
# state, first_reaction, origin, a settled takeaway, task_kind and routing. Its
# edges (D) are the parent tk-epic, two relates deps in each spelling, and a
# reverse `tracks` edge from a conversation (tk-conv, below). Its blocks are all closed — one
# same-store (embedded status), one FOREIGN in the otherrig store (no embedded
# status, the cross-store fold) — so its frontier verdict is ready. It also
# carries a description and notes; the read returns its title but never that body.
bead "$R_TK" tk-anchor <<'J'
{"id":"tk-anchor","title":"rich anchor","status":"open","issue_type":"task","priority":1,
 "assignee":"gc-toolkit/gc-toolkit.refinery","parent":"tk-epic",
 "description":"subject body prose the read must never surface",
 "notes":"## Current state\noperational notes the read must never surface",
 "metadata":{"task_kind":"rework","gc.routed_to":"","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat",
   "merge_result":"pull_request","pr_number":"9","branch":"polecat/tk-anchor","merged_target":"main","target":"main",
   "pr.machine":"progressing@a1b2c3@2026-09-02T22:00:00Z",
   "gc.first_reaction":"ruling","gc.first_reaction_at":"2026-09-02T22:23:04Z",
   "gc.first_reaction_reason":"scope and control flow unresolved","gc.first_reaction_target":"tk-frt",
   "gc.origin":"operator","gc.takeaway":"held pending the opening contract","gc.takeaway_settled":1},
 "dependencies":[
   {"id":"tk-epic","dependency_type":"parent-child","status":"open","title":"the parent epic"},
   {"id":"tk-c1","dependency_type":"blocks","status":"closed","title":"closed same-store blocker"},
   {"id":"or-far","dependency_type":"blocks","title":"foreign closed blocker"},
   {"id":"tk-rel","dependency_type":"relates-to","status":"open","title":"related work"},
   {"id":"tk-rel2","dependency_type":"related","status":"closed","title":"older-spelling related"}]}
J
bead "$R_TK" tk-c1  <<'J'
{"id":"tk-c1","title":"closed blocker","status":"closed","issue_type":"task","metadata":{}}
J
bead "$R_OR" or-far <<'J'
{"id":"or-far","title":"foreign closed blocker","status":"closed","issue_type":"task","metadata":{}}
J
# tk-conv tracks tk-anchor: the reverse edge that makes tk-anchor tracked-by it.
bead "$R_TK" tk-conv <<'J'
{"id":"tk-conv","title":"about tk-anchor","status":"closed","issue_type":"task","assignee":"human","metadata":{},
 "dependencies":[{"id":"tk-anchor","dependency_type":"tracks","status":"open"}]}
J

# tk-design: a closed design and the beads that wait on it, each by its own
# reverse edge. The build it released (open) and its docs (in progress) wait by
# blocks edges; an earlier build (closed) by a blocks edge and a duplicate it
# answered (closed) by an until edge. The closed ones' ids sort before the open
# ones', so only an open-first order lists the build first. A review's inbound
# `related` edge, a conversation's `tracks` edge and a child's `parent-child`
# edge also point at it, and none of those waits on it. The build carries a body
# the read must never surface.
bead "$R_TK" tk-design <<'J'
{"id":"tk-design","title":"the design","status":"closed","issue_type":"task","metadata":{}}
J
bead "$R_TK" tk-aw-next <<'J'
{"id":"tk-aw-next","title":"the build it released","status":"open","issue_type":"task",
 "description":"build body prose the read must never surface","metadata":{},
 "dependencies":[{"id":"tk-design","dependency_type":"blocks","status":"closed","title":"the design"}]}
J
bead "$R_TK" tk-aw-polish <<'J'
{"id":"tk-aw-polish","title":"its docs","status":"in_progress","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-design","dependency_type":"blocks","status":"closed","title":"the design"}]}
J
bead "$R_TK" tk-aw-earlier <<'J'
{"id":"tk-aw-earlier","title":"an earlier build","status":"closed","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-design","dependency_type":"blocks","status":"closed","title":"the design"}]}
J
bead "$R_TK" tk-aw-dup <<'J'
{"id":"tk-aw-dup","title":"a duplicate it answered","status":"closed","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-design","dependency_type":"until","status":"closed","title":"the design"}]}
J
bead "$R_TK" tk-aw-review <<'J'
{"id":"tk-aw-review","title":"review the design","status":"open","issue_type":"task",
 "metadata":{"task_kind":"review"},
 "dependencies":[{"id":"tk-design","dependency_type":"related","status":"closed","title":"the design"}]}
J
bead "$R_TK" tk-aw-track <<'J'
{"id":"tk-aw-track","title":"the conversation about the design","status":"closed","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-design","dependency_type":"tracks","status":"closed"}]}
J
bead "$R_TK" tk-aw-kid <<'J'
{"id":"tk-aw-kid","title":"a child of the design","status":"open","issue_type":"task","parent":"tk-design","metadata":{},
 "dependencies":[{"id":"tk-design","dependency_type":"parent-child","status":"closed","title":"the design"}]}
J

# tk-hub: a gate twelve beads wait on, more than the list names. tk-hw-00 is
# closed and sorts first by id; tk-hw-01 to tk-hw-11 are open.
bead "$R_TK" tk-hub <<'J'
{"id":"tk-hub","title":"a gate","status":"open","issue_type":"gate","metadata":{}}
J
for i in 00 01 02 03 04 05 06 07 08 09 10 11; do
  st=open; [ "$i" = 00 ] && st=closed
  printf '{"id":"tk-hw-%s","title":"parked %s","status":"%s","issue_type":"task","metadata":{},"dependencies":[{"id":"tk-hub","dependency_type":"blocks","status":"open","title":"a gate"}]}\n' \
    "$i" "$i" "$st" > "$R_TK/.beads/tk-hw-$i.json"
done

# Frontier verdict fixtures: one open unrouted blocker (stuck), one open
# pool-routed blocker (advancing), one open human gate (stuck).
bead "$R_TK" tk-stuck <<'J'
{"id":"tk-stuck","title":"held by an unrouted blocker","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-op","dependency_type":"blocks","status":"open","title":"open unrouted blocker"}]}
J
bead "$R_TK" tk-op <<'J'
{"id":"tk-op","title":"open unrouted blocker","status":"open","issue_type":"task","metadata":{}}
J
bead "$R_TK" tk-adv <<'J'
{"id":"tk-adv","title":"held by a routed blocker","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-routed","dependency_type":"blocks","status":"open","title":"routed blocker"}]}
J
bead "$R_TK" tk-routed <<'J'
{"id":"tk-routed","title":"routed blocker","status":"open","issue_type":"task",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead "$R_TK" tk-humangate <<'J'
{"id":"tk-humangate","title":"held by a human gate","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-hg","dependency_type":"blocks","status":"open","title":"a human gate"}]}
J
bead "$R_TK" tk-hg <<'J'
{"id":"tk-hg","title":"a human gate","status":"open","issue_type":"gate",
 "await_type":"human","await_id":"which-base","metadata":{}}
J
# tk-convheld: held by a conversation its sitting holds, in progress under the
# alias that names its own id, as one on an open PR holds the PR's merge. It is a
# person's, so it reads stuck, not advancing.
bead "$R_TK" tk-convheld <<'J'
{"id":"tk-convheld","title":"held by a conversation","status":"open","issue_type":"task","metadata":{"merge_result":"pull_request"},
 "dependencies":[{"id":"tk-cv","dependency_type":"blocks","status":"in_progress","title":"should this land as built?"}]}
J
bead "$R_TK" tk-cv <<'J'
{"id":"tk-cv","title":"should this land as built?","status":"in_progress","issue_type":"task",
 "assignee":"gc-toolkit/converse-claude-opus.c-tk-cv","metadata":{},
 "dependencies":[{"id":"tk-convheld","dependency_type":"tracks","status":"open","title":"held by a conversation"}]}
J
# tk-inreview: held by a review bead the review cadence dispatched. The review
# bead's live route is CLEARED by the pour (gc.routed_to="") and its status is not
# in_progress, so it looks like an unrouted stuck blocker — but it is machine work
# the pool owns, so its advance is advancing, not stuck.
bead "$R_TK" tk-inreview <<'J'
{"id":"tk-inreview","title":"held by a review in flight","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-rev","dependency_type":"blocks","status":"open","title":"review branch -> main"}]}
J
bead "$R_TK" tk-rev <<'J'
{"id":"tk-rev","title":"review branch -> main","status":"open","issue_type":"task",
 "metadata":{"task_kind":"review","anchor_bead":"tk-inreview","gc.routed_to":"","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat-codex"}}
J
# tk-under: a member of a parked parent, held through it. tk-waiter: a bead
# with a waits-for edge of its own, which the store cannot judge yet.
bead "$R_TK" tk-parked <<'J'
{"id":"tk-parked","title":"a parked parent","status":"open","issue_type":"epic","metadata":{},
 "dependencies":[{"id":"tk-pgate","dependency_type":"blocks","status":"open","title":"Parked until the operator says"}]}
J
bead "$R_TK" tk-pgate <<'J'
{"id":"tk-pgate","title":"Parked until the operator says","status":"open","issue_type":"gate","await_type":"human","metadata":{}}
J
bead "$R_TK" tk-under <<'J'
{"id":"tk-under","title":"a member of the parked parent","status":"open","issue_type":"task","parent":"tk-parked","metadata":{}}
J
bead "$R_TK" tk-spawner <<'J'
{"id":"tk-spawner","title":"the spawner","status":"closed","issue_type":"task","metadata":{}}
J
bead "$R_TK" tk-waiter <<'J'
{"id":"tk-waiter","title":"waits for its spawner","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-spawner","dependency_type":"waits-for","status":"closed","title":"the spawner"}]}
J
# tk-failclosed: a blocks dep whose store no rig carries and which bd could not
# embed a status for — an edge into another store, which holds nothing.
bead "$R_TK" tk-failclosed <<'J'
{"id":"tk-failclosed","title":"fail-closed","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"zz-ghost","dependency_type":"blocks","title":"unplaceable blocker"}]}
J

# --- where a named bead stands ---------------------------------------------
# The cases the shared answer reads apart from the classifier this script kept
# before it asked gctk, each a wait of a subject or a child of an epic. tk-sent
# is routed work a ruling or a sitting sent, and tk-unsent work nobody routes.
bead "$R_TK" tk-sent <<'J'
{"id":"tk-sent","title":"the work a ruling sent","status":"open","issue_type":"task",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead "$R_TK" tk-unsent <<'J'
{"id":"tk-unsent","title":"work nobody routes","status":"open","issue_type":"task","metadata":{}}
J
# A decision a ruling left waiting on the work it sent, which tk-ruled-wait
# waits on, and one left waiting on work nobody routes.
bead "$R_TK" tk-ruled <<'J'
{"id":"tk-ruled","title":"a ruling's decision","status":"open","issue_type":"decision","metadata":{},
 "dependencies":[{"id":"tk-sent","dependency_type":"blocks","status":"open","title":"the work a ruling sent"}]}
J
bead "$R_TK" tk-ruled-wait <<'J'
{"id":"tk-ruled-wait","title":"waits on the decision","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-ruled","dependency_type":"blocks","status":"open","title":"a ruling's decision"}]}
J
bead "$R_TK" tk-ruled2 <<'J'
{"id":"tk-ruled2","title":"a ruling's decision behind unrouted work","status":"open","issue_type":"decision","metadata":{},
 "dependencies":[{"id":"tk-unsent","dependency_type":"blocks","status":"open","title":"work nobody routes"}]}
J
# A conversation its sitting stays in, open under its alias and waiting on the
# work it sent, which holds the bead it tracks.
bead "$R_TK" tk-stayheld <<'J'
{"id":"tk-stayheld","title":"held by a conversation its sitting stays in","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-stay","dependency_type":"blocks","status":"open","title":"what the sitting sent"}]}
J
bead "$R_TK" tk-stay <<'J'
{"id":"tk-stay","title":"what the sitting sent","status":"open","issue_type":"task",
 "assignee":"gc-toolkit/converse-claude-opus.c-tk-stay","metadata":{},
 "dependencies":[{"id":"tk-stayheld","dependency_type":"tracks","status":"open"},
   {"id":"tk-sent","dependency_type":"blocks","status":"open","title":"the work a ruling sent"}]}
J
# Settled pull requests that wait on the operator's review: a posture of none,
# and one of commented. tk-prwait waits on both.
bead "$R_TK" tk-pr-none <<'J'
{"id":"tk-pr-none","title":"a settled PR nobody reviewed","status":"open","issue_type":"task",
 "metadata":{"merge_result":"pull_request","pr_number":"11","pr.machine":"settled@h1@2026-10-01T00:00:00Z","pr_posture":"none@h1@2026-10-01T00:00:00Z"}}
J
bead "$R_TK" tk-pr-commented <<'J'
{"id":"tk-pr-commented","title":"a settled PR with comments","status":"open","issue_type":"task",
 "metadata":{"merge_result":"pull_request","pr_number":"12","pr.machine":"settled@h1@2026-10-01T00:00:00Z","pr_posture":"commented@h1@2026-10-01T00:00:00Z"}}
J
bead "$R_TK" tk-prwait <<'J'
{"id":"tk-prwait","title":"waits on two reviews","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-pr-none","dependency_type":"blocks","status":"open","title":"a settled PR nobody reviewed"},
   {"id":"tk-pr-commented","dependency_type":"blocks","status":"open","title":"a settled PR with comments"}]}
J
# Work nobody routes, behind which a human gate waits: the person's move is what
# stops tk-chain.
bead "$R_TK" tk-chain <<'J'
{"id":"tk-chain","title":"waits on work behind a person","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-norte","dependency_type":"blocks","status":"open","title":"unrouted, behind a gate"}]}
J
bead "$R_TK" tk-norte <<'J'
{"id":"tk-norte","title":"unrouted, behind a gate","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-hg2","dependency_type":"blocks","status":"open","title":"which way"}]}
J
bead "$R_TK" tk-hg2 <<'J'
{"id":"tk-hg2","title":"which way","status":"open","issue_type":"gate","await_type":"human","metadata":{}}
J

# The bead a run works. pour <store-repo> <bead> <root> <root-status> writes a
# graph.v2 run over the bead: its root, and the input convoy the root names,
# which tracks the bead and stays open for as long as the bead is open, whether
# or not the root has closed. The pour leaves the bead open, unassigned and
# unrouted, with the route it ran on as provenance only.
pour() {
  printf '{"id":"%s-cv","title":"input convoy for %s","status":"open","issue_type":"convoy","metadata":{"gc.synthetic":"true"},"dependencies":[{"id":"%s","dependency_type":"tracks","status":"open"}]}\n' \
    "$3" "$2" "$2" > "$1/.beads/$3-cv.json"
  printf '{"id":"%s","title":"mol-polecat-work","status":"%s","issue_type":"task","metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"%s-cv"}}\n' \
    "$3" "$4" "$3" > "$1/.beads/$3.json"
}
POURED='{"gc.routed_to":"","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}'
# tk-r-epic, an epic in active work: a live run works tk-r-work, and the run
# over tk-r-ended has closed its root, leaving its convoy open.
bead "$R_TK" tk-r-epic <<'J'
{"id":"tk-r-epic","title":"an epic in active work","status":"open","issue_type":"epic","metadata":{}}
J
for b in work ended; do
  printf '{"id":"tk-r-%s","title":"tk-r-%s","status":"open","issue_type":"task","parent":"tk-r-epic","metadata":%s}\n' \
    "$b" "$b" "$POURED" > "$R_TK/.beads/tk-r-$b.json"
done
pour "$R_TK" tk-r-work tk-r-root in_progress
pour "$R_TK" tk-r-ended tk-r-eroot closed
# A bead that waits on the root of the live run that works it, as a pull
# request's anchor waits on its review run: the wait is its own work.
printf '{"id":"tk-r-attached","title":"waits on the run that works it","status":"open","issue_type":"task","metadata":%s,"dependencies":[{"id":"tk-r-aroot","dependency_type":"blocks","status":"in_progress","title":"mol-polecat-work"}]}\n' \
  "$POURED" > "$R_TK/.beads/tk-r-attached.json"
pour "$R_TK" tk-r-attached tk-r-aroot in_progress

# tk-outer: an epic whose members are an epic with a routed member, a Delivery
# whose only member nobody routes, and routed work the Product Owner holds.
bead "$R_TK" tk-outer <<'J'
{"id":"tk-outer","title":"an outer epic","status":"open","issue_type":"epic","metadata":{"epic_hypothesis":"it helps"}}
J
bead "$R_TK" tk-inner <<'J'
{"id":"tk-inner","title":"a child epic","status":"open","issue_type":"epic","parent":"tk-outer","metadata":{"epic_hypothesis":"it helps too"}}
J
bead "$R_TK" tk-inner-kid <<'J'
{"id":"tk-inner-kid","title":"the child epic's routed member","status":"open","issue_type":"task","parent":"tk-inner",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead "$R_TK" tk-delivery <<'J'
{"id":"tk-delivery","title":"a Delivery","status":"open","issue_type":"epic","parent":"tk-outer","metadata":{}}
J
bead "$R_TK" tk-delivery-kid <<'J'
{"id":"tk-delivery-kid","title":"the Delivery's unrouted member","status":"open","issue_type":"task","parent":"tk-delivery","metadata":{}}
J
bead "$R_TK" tk-mayor <<'J'
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
bead "$R_TK" tk-epic <<'J'
{"id":"tk-epic","title":"the epic","status":"open","issue_type":"epic","priority":2,
 "metadata":{},
 "dependencies":[{"id":"tk-relE","dependency_type":"related","status":"open","title":"related epic"}]}
J
bead "$R_TK" tk-kid-pool <<'J'
{"id":"tk-kid-pool","title":"routed child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead "$R_TK" tk-kid-prog <<'J'
{"id":"tk-kid-prog","title":"in-progress child","status":"in_progress","issue_type":"task","parent":"tk-epic","metadata":{}}
J
bead "$R_TK" tk-kid-human <<'J'
{"id":"tk-kid-human","title":"a child in the operator's queue","status":"open","issue_type":"task","parent":"tk-epic",
 "assignee":"human","metadata":{}}
J
bead "$R_TK" tk-kid-done <<'J'
{"id":"tk-kid-done","title":"done child","status":"closed","issue_type":"task","parent":"tk-epic","metadata":{}}
J
bead "$R_TK" tk-kid-event <<'J'
{"id":"tk-kid-event","title":"State change: situation → cleared","status":"closed","issue_type":"event","priority":4,"parent":"tk-epic","metadata":{}}
J
bead "$R_TK" tk-kid-rework <<'J'
{"id":"tk-kid-rework","title":"rework child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"task_kind":"rework","gc.routed_to":""}}
J
bead "$R_TK" tk-kid-armed <<'J'
{"id":"tk-kid-armed","title":"armed child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"},
 "dependencies":[{"id":"tk-hg","dependency_type":"blocks","status":"open","title":"a human gate"}]}
J
bead "$R_TK" tk-kid-hooked <<'J'
{"id":"tk-kid-hooked","title":"hooked child","status":"hooked","issue_type":"task","parent":"tk-epic","metadata":{}}
J
bead "$R_TK" tk-kid-pinned <<'J'
{"id":"tk-kid-pinned","title":"pinned child","status":"pinned","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead "$R_TK" tk-kid-custom <<'J'
{"id":"tk-kid-custom","title":"custom-status child","status":"in_review","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J

# hq-city lives in the HQ store, which no --rig value names — only --db reaches.
bead "$HQ" hq-city <<'J'
{"id":"hq-city","title":"city bead","status":"open","issue_type":"task","metadata":{}}
J

# tk-ctrl carries a raw C0 byte (SOH \001) in its notes, the payload real bd
# emits that aborts a naive jq; scrub must remove it. tk-nul carries a raw NUL
# (\000), the C0 byte that also trips grep's binary heuristic: the notice-strip
# must run in text mode (grep -a) or grep drops the whole payload.
printf '{"id":"tk-ctrl","title":"ctl\001note","status":"open","issue_type":"task","metadata":{}}\n' \
  > "$R_TK/.beads/tk-ctrl.json"
printf '{"id":"tk-nul","title":"nul","status":"open","issue_type":"task","notes":"a\000b","metadata":{}}\n' \
  > "$R_TK/.beads/tk-nul.json"

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
# Only the surface bead-context.sh touches: rig list; bd show, with the bead's
# dependents on --include-dependents; bd list --parent (children); bd dep list
# --direction=up --type tracks (reverse trackers). Every call is logged so the
# test can prove which store was asked, not just what came back.
set -u
# A read the gctk under test makes answers from the store its --db names,
# through the seam holds-store.stub.sh keeps. gctk reads the store several times
# for each frontier, so one jq builds the store whatever its size: the shell's
# read builtin takes in each bead file whole, and jq parses each file on its
# own, so a file it cannot parse, such as a fixture that carries a raw control
# byte, is left out without ending the read. An edge onto a bead another store
# holds is one into another store.
if [ -n "${HOLDS_STUB_READ:-}" ] && [ "${1:-}" = bd ]; then
  shift
  hdb="$STUB_ROOT/rigs/gc-toolkit/.beads"; [ "${1:-}" = --db ] && hdb="${2:-}"
  hs="${hdb%/*}"; hs="$STUB_ROOT/holds-${hs##*/}.json"
  rows=()
  for f in "$hdb"/*.json; do
    [ -e "$f" ] || continue
    IFS= read -r -d '' row < "$f"
    rows+=("$row")
  done
  jq -n -c '[$ARGS.positional[] | fromjson? | objects]' --args "${rows[@]}" > "$hs"
  HOLDS_STORE="$hs" HOLDS_WHERE="$hdb" exec "${HOLDS_STUB:?}" answer "$@"
fi
printf '%s\n' "$*" >> "$FAKE_GC_LOG"
preface() { [ -n "${STUB_PREFACE:-}" ] && echo 'gc bd: answering from the rig "fake" store'; }
miss() { printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; echo "Issue $1 not found" >&2; exit 1; }
# Real `gc bd show` leaves out an edge whose far end lives in another store; a
# fixture writes such an edge with no status, so show drops every status-less
# edge. A fixture jq cannot parse — one carrying a raw C0 byte — streams through
# `cat`, not `"$(cat)"`: command substitution drops a raw NUL (bash: "ignored null
# byte in input"), and the NUL is exactly the byte real `gc bd show` can emit that
# the tool must survive. Brackets keep the array shape the tool discriminates on.
serve() {
  preface; printf '['
  local first=1 f out deps
  for f in "$@"; do
    [ "$first" = 1 ] || printf ','; first=0
    if out=$(jq -c '.dependencies = [(.dependencies // [])[] | select(.status != null)]' "$f" 2>/dev/null); then
      if [ -n "$WITH_DEPENDENTS" ]; then
        deps=$(dependents_of "$(printf '%s' "$out" | jq -r '.id')")
        [ "$deps" = "[]" ] || out=$(printf '%s' "$out" | jq -c --argjson d "$deps" '.dependents = $d')
      fi
      printf '%s' "$out"
    else
      cat "$f"
    fi
  done
  printf ']\n'; exit 0
}
# Real `bd show --include-dependents` adds every bead in the store with an edge to
# the shown one, of any type, cut to its identity fields and the edge's type, and
# leaves the key out when there are none. It streams them oldest first, so here
# they come in descending id order, an order the tool must not lean on.
dependents_of() {
  local d f row first=1
  printf '['
  for d in $(stores); do
    for f in $(grep -laF "\"$1\"" "$d"/*.json 2>/dev/null | sort -r); do
      row=$(jq -c --arg s "$1" '. as $b | (.dependencies // [])[] | select(.id == $s)
        | {id: $b.id, title: $b.title, status: $b.status, issue_type: $b.issue_type, dependency_type}' "$f" 2>/dev/null) || continue
      [ -n "$row" ] || continue
      [ "$first" = 1 ] || printf ','; first=0
      printf '%s' "$row"
    done
  done
  printf ']'
}
# A list row renders every edge, another store's included, in the shape real
# `gc bd list` emits: {issue_id, depends_on_id, type}, no embedded status.
listrow() { jq -c '.id as $i | .dependencies = [(.dependencies // [])[] | {issue_id: $i, depends_on_id: .id, type: .dependency_type}]'; }
# The stores a query scans: the one --db pins, else every rig plus HQ. Files are
# read one at a time: real bd returns clean list/dep rows, and reading each alone
# means a contaminated show-only fixture (tk-nul, tk-ctrl) — never a child or
# tracker — is skipped by its own jq guard rather than aborting a whole-directory
# slurp. Command substitution drops the raw NUL on the way in.
stores() { if [ -n "$DB" ]; then printf '%s\n' "$DB"; else printf '%s\n' "$STUB_ROOT"/rigs/*/.beads "$STUB_ROOT"/hq/.beads; fi; }
case "${1:-} ${2:-}" in
  "rig list") preface; cat "$FAKE_RIGS"; exit 0 ;;
esac
[ "${1:-}" = bd ] || { echo "gc: unsupported ($*)" >&2; exit 1; }
shift
DB=""; SUB=""; SUB2=""; ID=""; IDS=(); PARENT=""; DIRECTION="down"; TYPE=""; STATUS=""; ALL=""; WITH_DEPENDENTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --db)          DB="$2"; shift 2 ;;
    --parent)      PARENT="$2"; shift 2 ;;
    --all)         ALL=1; shift ;;
    --include-dependents) WITH_DEPENDENTS=1; shift ;;
    --direction|--direction=*) case "$1" in *=*) DIRECTION="${1#*=}"; shift ;; *) DIRECTION="$2"; shift 2 ;; esac ;;
    -t|--type)     TYPE="$2"; shift 2 ;;
    -s|--status)   STATUS="$2"; shift 2 ;;
    --json|--brief-deps|--limit) [ "$1" = --limit ] && shift 2 || shift ;;
    show)          SUB=show; shift ;;
    list)          [ -z "$SUB" ] && SUB=list || SUB2=list; shift ;;
    dep)           SUB=dep; shift ;;
    -*)            shift ;;
    *)             if [ "$SUB" = show ]; then IDS+=("$1"); elif [ -z "$ID" ]; then ID="$1"; fi; shift ;;
  esac
done

if [ "$SUB" = show ]; then
  [ "${#IDS[@]}" -gt 0 ] || { echo "gc bd: no id" >&2; exit 1; }
  FOUND=()
  for id in "${IDS[@]}"; do
    hit=""
    for d in $(stores); do [ -f "$d/$id.json" ] && { hit="$d/$id.json"; break; }; done
    if [ -n "$hit" ]; then FOUND+=("$hit"); else echo "Issue $id not found" >&2; fi
  done
  [ "${#FOUND[@]}" -gt 0 ] || miss "${IDS[0]}"
  serve "${FOUND[@]}"
fi

if [ "$SUB" = list ] && [ -n "$PARENT" ]; then
  # Children of $PARENT, scoped as real bd scopes them: --all returns every
  # status, a store's own included; --status returns only the statuses it names;
  # with neither, bd's default returns every built-in status but closed and
  # pinned. So a caller that wants every child counted must pass --all.
  if [ -z "$ALL" ] && [ -z "$STATUS" ]; then STATUS="open,in_progress,blocked,deferred,hooked"; fi
  preface; printf '['; first=1
  for d in $(stores); do
    # One grep per store narrows the files to those naming the parent; jq decides.
    for f in $(grep -laF "\"$PARENT\"" "$d"/*.json 2>/dev/null); do
      row=$(cat "$f")
      printf '%s' "$row" | jq -e --arg p "$PARENT" '.parent == $p' >/dev/null 2>&1 || continue
      st=$(printf '%s' "$row" | jq -r '.status // ""')
      if [ -z "$ALL" ]; then case ",$STATUS," in *",$st,"*) ;; *) continue ;; esac; fi
      [ "$first" = 1 ] || printf ','; first=0
      printf '%s' "$row" | listrow
    done
  done
  printf ']\n'; exit 0
fi

if [ "$SUB" = dep ] && [ "$SUB2" = list ] && [ "$DIRECTION" = up ]; then
  # Reverse edges into $ID: beads whose dependencies name $ID, filtered by --type.
  preface; printf '['; first=1
  for d in $(stores); do
    # One grep per store narrows the files to those naming the id; jq decides.
    for f in $(grep -laF "\"$ID\"" "$d"/*.json 2>/dev/null); do
      row=$(cat "$f")
      printf '%s' "$row" | jq -e --arg s "$ID" --arg t "$TYPE" \
        'any(.dependencies[]?; .id == $s and ($t == "" or .dependency_type == $t))' >/dev/null 2>&1 || continue
      [ "$first" = 1 ] || printf ','; first=0
      printf '%s' "$row"
    done
  done
  printf ']\n'; exit 0
fi

echo "gc bd: unsupported ($SUB $SUB2)" >&2; exit 1
GC

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
# The tool reaches every store through `gc bd`; a direct `bd` is the regression
# this stub exists to fail on. It records the call so one assertion reads the
# whole run.
printf '%s\n' "$*" >> "$FAKE_BD_LOG"
echo "stub bd: called directly instead of through gc bd" >&2
exit 127
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH"

run()  { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }
runj() { run "$@" --json; JQ=$(printf '%s' "$OUT" | jq -r "$JQF" 2>/dev/null); }
# Bounded variant for a call that could spin before a fix: a wedged SUT surfaces
# as timeout's rc 124 (a test failure) instead of hanging the whole suite.
runb() { OUT=$(timeout 10 "$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }
# One run per subject; each assertion queries that run's output.
jr()  { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }

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
has "$(cat "$FAKE_GC_LOG")" "show tk-anchor --brief-deps" \
  "  ... via a --brief-deps read, so a hub bead's dependency bodies are never fetched"

run tk-anchor --json
eq "$(jr .subject.title)"                    "rich anchor"     "subject.title — section A returns the subject's own title"
eq "$(jr .subject.status)"                   open              "subject.status"
eq "$(jr .subject.priority)"                 1                 "subject.priority (top-level)"
eq "$(jr .subject.task_kind)"                rework            "subject.task_kind"
eq "$(jr .subject.routed_to)"                ""                "subject.routed_to preserves the empty (cleared) route"
eq "$(jr .subject.execution_routed_to)"      gc-toolkit/gc-toolkit.polecat "subject.execution_routed_to"
eq "$(jr .subject.anchor.merge_result)"      pull_request      "anchor.merge_result present when the bead carries one"
eq "$(jr .subject.anchor.pr_number)"         9                 "anchor.pr_number"
eq "$(jr .subject.anchor.branch)"            polecat/tk-anchor "anchor.branch"
eq "$(jr .subject.anchor.merged_target)"     main              "anchor.merged_target"
eq "$(jr .subject.first_reaction.reaction)"  ruling            "first_reaction.reaction"
eq "$(jr .subject.first_reaction.target)"    tk-frt            "first_reaction.target"
eq "$(jr .subject.origin)"                   operator          "subject.origin"
eq "$(jr .subject.takeaway_settled)"         1                 "subject.takeaway_settled returned as the field it is"
# A bead with no merge_result carries a null anchor, not a fabricated one.
JQF='.subject.anchor'                 runj tk-epic;   eq "$JQ" null        "anchor is null when the bead is not an anchor"

# --- D. Context edges -------------------------------------------------------
run tk-anchor --json
eq "$(jr .edges.parent.id)"                  tk-epic           "edges.parent resolved from .parent"
eq "$(jr .edges.parent.title)"               "the parent epic" "  ... with the parent's title from the edge"
eq "$(jr .edges.counts.parent)"              1                 "edges.counts.parent"
eq "$(jr '.edges.relates_to | length')"      2                 "both relates spellings — relates-to AND related — are the relates class"
eq "$(jr '[.edges.relates_to[].id]|sort|join(",")')" tk-rel,tk-rel2 "  ... and both are named"
eq "$(jr '.edges.tracked_by | length')"      1                 "tracked-by is read from the reverse tracks edge"
eq "$(jr '.edges.tracked_by[0].id')"         tk-conv           "  ... naming the conversation that tracks it"
has "$(cat "$FAKE_GC_LOG")" "dep list tk-anchor --direction=up --type tracks" \
  "  ... via a reverse dep-list, since the subject carries no tracked-by edge itself"

# The beads that wait on a bead: a closed design names the build it released.
: > "$FAKE_GC_LOG"
run tk-design --json
eq "$(jr '[.edges.awaited_by[] | "\(.id):\(.status):\(.edge)"] | join(" ")')" \
  "tk-aw-next:open:blocks tk-aw-polish:in_progress:blocks tk-aw-dup:closed:until tk-aw-earlier:closed:blocks" \
  "awaited-by names the beads with a blocks or until edge to the subject, open ones first, each with its status and edge"
eq "$(jr '.edges.awaited_by[0].title')" "the build it released" "  ... and its title"
eq "$(jr '.edges.counts | "\(.awaited_by) \(.awaited_by_open)"')" "4 2" "  ... counted in all and open"
eq "$(jr '[.edges.tracked_by[].id] | join(",")')" tk-aw-track \
  "  ... while a conversation's tracks edge stays tracked-by, and a related review and a child are in neither"
eq "$(jr '[.edges.awaited_by[] | keys | join(",")] | unique | join(" ")')" "edge,id,status,title" \
  "  ... each cut to its id, title, status and edge"
eq "$(jr '[paths | join(".")] | map(select(test("description|notes|comment"; "i"))) | length')" 0 \
  "  ... and no waiter's body rides along"
eq "$(grep -c -- 'show tk-design --brief-deps --include-dependents' "$FAKE_GC_LOG")" 1 \
  "  ... taken from the dependents the subject's own read carries"
eq "$(grep -- 'dep list tk-design' "$FAKE_GC_LOG" | grep -vc -- '--type tracks')" 0 \
  "  ... with no reverse read of its own beside tracked-by's"
run tk-design
has "$OUT" "awaited-by  4 (2 open): tk-aw-next (open, blocks), tk-aw-polish (in_progress, blocks), tk-aw-dup (closed, until), tk-aw-earlier (closed, blocks)" \
  "  ... and the text view names them on one line after the counts"

run tk-hub --json
eq "$(jr '[.edges.awaited_by[].id] | join(",")')" \
  "tk-hw-01,tk-hw-02,tk-hw-03,tk-hw-04,tk-hw-05,tk-hw-06,tk-hw-07,tk-hw-08,tk-hw-09,tk-hw-10" \
  "a bead with more waiters than the cap names ten, open ones first, so a closed one that sorts first is cut"
eq "$(jr '.edges.counts | "\(.awaited_by) \(.awaited_by_open)"')" "12 11" "  ... and counts all twelve, eleven open"
run tk-hub
has "$OUT" "awaited-by  12 (11 open): tk-hw-01 (open, blocks), " "  ... the text view leads with the counts"
has "$OUT" "tk-hw-10 (open, blocks), and 2 more" "  ... and says how many it left out"
# The Edges section's line for a bead with no edge of any class.
NO_EDGES=$'\n    (none)'
hasnt "$OUT" "$NO_EDGES" "  ... and a bead whose only edges are its waiters does not read as having none"

run tk-anchor --json
eq "$(jr '.edges.counts | "\(.awaited_by) \(.awaited_by_open)"')" "0 0" "a bead nothing waits on counts no waiters"
eq "$(jr '.edges.awaited_by | length')" 0 "  ... and names none"
run tk-anchor
hasnt "$OUT" "awaited-by" "  ... and prints no awaited-by line"
run hq-city --db "$HQ/.beads"
has "$OUT" "$NO_EDGES" "a bead with no edge of any class reads (none)"

# --- B. Frontier (opt-in) ---------------------------------------------------
# Default output carries no frontier; it is added only on --frontier. A frontier
# run starts the gctk under test, which reads the store several times, so each
# subject runs once and its assertions query that run's output.
blkr() { jr "[.frontier.open[] | select(.id == \"$1\")][0] | \"\(.advance) \(.stuck_on.id // \"-\") \(.stuck_on.why // \"-\")\""; }
kid() { jr "[.horizon.open[] | select(.id == \"$1\")][0] | \"\(.advance) \(.stuck_on.id // \"-\") \(.stuck_on.why // \"-\")\""; }

JQF='has("frontier")'  runj tk-anchor;             eq "$JQ" false "frontier is absent by default (opt-in)"
run tk-anchor --frontier --json
eq "$(jr .frontier.verdict)"                ready  "all blocks-blockers closed (one cross-store) reads ready"
eq "$(jr .frontier.blockers.closed)"        1      "the same-store closed blocker is counted"
eq "$(jr '.frontier.foreign | join(",")')"  or-far "  ... and the edge into another store holds nothing, listed as foreign"
eq "$(jr .frontier.blockers.open)"          0      "no open blocker"
eq "$(jr '.frontier.open | length')"        0      "closed blockers are counted, never listed"
eq "$(jr .frontier.holds)"                  clear  "  ... and gctk bead holds answers clear"

run tk-under --frontier --json
eq "$(jr .frontier.verdict)" stuck "a member of a parked parent is held through it, so not ready"
eq "$(jr .frontier.holds)"   held  "  ... holds=held"
eq "$(jr '.frontier.open[0] | "\(.id) \(.ancestor)"')" "tk-pgate tk-parked" "  ... naming the parent's gate and the parent it sits on"
eq "$(blkr tk-pgate)" "stuck tk-pgate question" "  ... a gate a person answers, a question"

run tk-waiter --frontier --json
eq "$(jr .frontier.verdict)" stuck    "a waits-for edge of its own is a wait the store cannot judge, so not ready"
eq "$(jr .frontier.holds)"   unjudged "  ... holds=unjudged"
eq "$(jr '.frontier.open[0] | "\(.id) \(.unjudged)"')" "tk-spawner true" "  ... and the spawner is listed as unjudged"
eq "$(blkr tk-spawner)" "stuck tk-spawner unread" "  ... stuck on the wait it cannot judge, unread"

GCTK_BIN="$TMP/no-gctk" run tk-anchor --frontier --json
eq "$(jr '.frontier | "\(.verdict) \(.holds)"')" "stuck unread" "a read of what holds it that cannot run fails the verdict closed"
has "$(jr .frontier.unread)" "no gctk binary at $TMP/no-gctk" "  ... and says why"

# A gctk that answers what holds the subject and nothing about where it stands.
{ printf '#!/bin/sh\n'; printf '[ "${2:-}" = stands ] && exit 1\nexec "%s" "$@"\n' "$GCTK_BIN"; } > "$TMP/gctk-holds-only"
chmod +x "$TMP/gctk-holds-only"
GCTK_BIN="$TMP/gctk-holds-only" run tk-adv --frontier --json
eq "$(jr '.frontier | "\(.verdict) \(.holds)"')" "stuck blocked" "a subject gctk bead stands does not answer fails the verdict closed"
has "$(jr .frontier.unread)" "gctk bead stands" "  ... and says which read did not answer"
eq "$(blkr tk-routed)" "stuck tk-routed unread" "  ... and each wait it names reads stuck on itself, unread"

run tk-stuck --frontier --json
eq "$(jr .frontier.verdict)"           stuck                   "work nobody routes as the blocker leaves the subject stuck"
eq "$(jr '.frontier.open[0].id')"      tk-op                   "  ... and the open blocker is named"
eq "$(blkr tk-op)"                     "stuck tk-op not-scheduled" "  ... stuck on itself, not scheduled"
eq "$(jr '.frontier.open[0].title')"   "open unrouted blocker" "  ... with its title"

run tk-adv --frontier --json
eq "$(jr .frontier.verdict)" advancing "an open pool-routed blocker is advancing"
eq "$(blkr tk-routed)" "advancing - -" "  ... advance=advancing, and no stuck_on"
eq "$(jr '[.frontier.open[] | select(.advance == "advancing") | has("stuck_on")] | any')" false \
  "an advancing wait carries no stuck_on key"

run tk-humangate --frontier --json
eq "$(jr .frontier.verdict)" stuck "a human gate as the blocker is stuck, not advancing"
eq "$(blkr tk-hg)" "stuck tk-hg question" "  ... the gate is a question a person owes"

run tk-convheld --frontier --json
eq "$(blkr tk-cv)" "stuck tk-cv conversation" "a conversation its sitting holds is a person's, so stuck, not advancing"
eq "$(jr .frontier.verdict)" stuck "  ... and so is the subject it holds"

run tk-inreview --frontier --json
eq "$(blkr tk-rev)" "advancing - -" "a review of the subject's own pull request is its own work, so advancing"
eq "$(jr .frontier.verdict)" advancing "  ... so a subject held only by its own review is advancing, not stuck"

run tk-r-attached --frontier --json
eq "$(blkr tk-r-aroot)" "advancing - -" "the root of the live run that works the subject is its own work"
eq "$(jr .frontier.verdict)" advancing "  ... so a bead waiting on its own run is advancing"

run tk-failclosed --frontier --json
eq "$(jr .frontier.verdict)"               ready    "an edge onto a bead the store does not hold holds nothing, so the verdict is ready"
eq "$(jr .frontier.blockers.open)"         0        "  ... counted as no open blocker"
eq "$(jr '.frontier.foreign | join(",")')" zz-ghost "  ... and listed as foreign"

# A decision a ruling left waiting on the work it sent, and a conversation its
# sitting stays in, advance while that work does.
run tk-ruled-wait --frontier --json
eq "$(blkr tk-ruled)" "advancing - -" "a decision a ruling left waiting on the work it sent advances while that work does"
eq "$(jr .frontier.verdict)" advancing "  ... and so does what waits on it"
run tk-ruled --frontier --json
eq "$(jr .frontier.verdict)" advancing "  ... read as the subject, its own frontier advances with the work"
run tk-ruled2 --frontier --json
eq "$(blkr tk-unsent)" "stuck tk-unsent not-scheduled" "  ... and one waiting on work nobody routes is stuck on that work"
run tk-stayheld --frontier --json
eq "$(blkr tk-stay)" "advancing - -" "a conversation its sitting stays in advances while the work it sent does"

# A settled pull request whose posture is none or commented waits on the
# operator's review.
run tk-prwait --frontier --json
eq "$(blkr tk-pr-none)" "stuck tk-pr-none pull-request" "a settled PR with no review is stuck on itself, waiting on review"
eq "$(blkr tk-pr-commented)" "stuck tk-pr-commented pull-request" "  ... and so is one with comments and no verdict"
eq "$(jr .frontier.verdict)" stuck "  ... so the subject waiting on them is stuck"

# A person's move behind work nobody routes is what stops the bead.
run tk-chain --frontier --json
eq "$(blkr tk-norte)" "stuck tk-hg2 own-wait" "work nobody routes, behind a human gate, is stuck on the gate"

run tk-stuck --frontier
has "$OUT" "tk-op  open unrouted blocker (open, stuck: not-scheduled)" "the human block names a blocker that stops itself by just why"
run tk-chain --frontier
has "$OUT" "tk-norte  unrouted, behind a gate (open, stuck on tk-hg2: own-wait)" "  ... and one stopped beneath it by the bead and why"

# --- C. Horizon (opt-in) ----------------------------------------------------
JQF='has("horizon")'                 runj tk-epic;            eq "$JQ" false "horizon is absent by default (opt-in)"
: > "$FAKE_GC_LOG"; run tk-epic --horizon --json
eq "$(jr .horizon.children.total)"     10 "every direct child is counted, in any status, and a bd set-state event is not a child"
eq "$(jr .horizon.children.open)"      9  "  ... nine are open"
eq "$(jr .horizon.children.closed)"    1  "  ... the done child is counted (the listing asks for every status), and the closed event is not"
eq "$(jr .horizon.children.advancing)" 3  "  ... the pool-routed, in-progress and hooked children advance"
eq "$(jr .horizon.children.stuck)"     6  "  ... the rest are stuck"
eq "$(jr '.horizon.open | length')"    9  "open children are listed; the done one is not"
eq "$(jr '[.horizon.open[].id] | index("tk-kid-done")')" null "the done child is never in the open list"
eq "$(kid tk-kid-pool)" "advancing - -" "a pool-routed open child advances"
eq "$(kid tk-kid-prog)" "advancing - -" "an in-progress child advances"
eq "$(kid tk-kid-hooked)" "advancing - -" "a hooked child is listed and advances: an agent holds it"
eq "$(kid tk-anchor)" "stuck tk-anchor pull-request" "a pull request nothing reviewed waits on the operator's review"
eq "$(kid tk-kid-human)" "stuck tk-kid-human routed-to-you" "an open child in the operator's queue is a person's to move"
eq "$(kid tk-kid-armed)" "stuck tk-hg own-wait" "an armed child behind a human gate is stuck on the gate"
eq "$(kid tk-kid-rework)" "stuck tk-kid-rework not-scheduled" "a rework child whose route the pour cleared is work nobody routes"
eq "$(kid tk-kid-pinned)" "stuck tk-kid-pinned status" "a pinned child is listed and stuck on its status, though it carries a route"
eq "$(kid tk-kid-custom)" "stuck tk-kid-custom status" "a child in a status its store adds is listed, and stuck on that status"
eq "$(jr '[.horizon.open[] | select(.id == "tk-kid-custom")][0].status')" in_review "  ... reporting the status as the store holds it"
eq "$(jr '[.horizon.open[] | select(.advance == "advancing") | has("stuck_on")] | any')" false \
  "an advancing child carries no stuck_on key"

run tk-r-epic --horizon --json
eq "$(jr '.horizon.children | "\(.open) \(.advancing) \(.stuck)"')" "2 1 1" \
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
JQF='[.subject.id, .frontier.verdict, (.horizon.children.total|tostring)] | join("|")' \
  runj tk-epic --frontier --horizon
eq "$JQ" "tk-epic|ready|10" "one call returns subject slice, readiness verdict and epic-health snapshot together"

# --- E. Store pinning, and the object-vs-array shape ------------------------
run tk-missing
eq "$RC" 4 "a not-found id (\`{\"error\":…}\` object) is reported, not parsed as a bead"
has "$ERR" "did not resolve to a bead" "  ... with a diagnostic"

run hq-city --db "$HQ/.beads"
eq "$RC" 0 "--db reaches the HQ store, which no --rig value names"
has "$OUT" "Store       mycity" "  ... and the rig is recovered from the db path"

JQF='.subject.status'  runj or-far --store rig:otherrig
eq "$JQ" closed "--store rig:<name> pins the read to that rig's store"

# --- the stdout notice line, and control bytes, do not break the read -------
STUB_PREFACE=1 run tk-anchor
eq "$RC" 0 "a leading \`gc bd:\` notice line does not break the read (rc)"
has "$OUT" "Status      open" "  ... and the bead still renders"
STUB_PREFACE=""

run tk-ctrl
eq "$RC" 0 "a raw C0 byte in notes is scrubbed before jq, not fatal"
has "$OUT" "Status      open" "  ... and the bead renders"
run tk-nul
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
eq "$(wc -l < "$FAKE_BD_LOG" | tr -d ' ')" "0" \
  "no store was reached through a direct \`bd\` at any point in the run"

# --- the omit clause: no body of any bead is ever returned ------------------
run tk-anchor --frontier --horizon --json
eq "$(printf '%s' "$OUT" | jq -r '[paths|join(".")]|map(select(test("description|notes|comment";"i")))|length')" "0" \
  "no description, notes or comment field appears anywhere in the JSON"

echo
echo "bead-context: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
