#!/usr/bin/env bash
# Hermetic test for refinery-find-work.sh, the refinery patrol's find-work
# step, against a fake gc and gctk over a JSON store (refinery-test-lib.sh).
# Proves:
#   - it names one bead assigned to this refinery, open or in progress, that
#     carries a branch, and prints nothing else on stdout;
#   - a bead a publication left blocked on its pending record is not listed,
#     while a half-written record, open with the marker and existing_pr, is
#     taken like any bead handed to the refinery;
#   - a bead something holds is left, and named;
#   - a bead whose branch another open bead works on is left until that bead
#     is gone, while the anchor a bead names is no writer of its branch;
#   - a bead on the branch that waits on the bead, armed, with no live run and
#     no claim a listed session holds, is no writer of it, so the bead is
#     taken; one a live run works, or whose claim a listed session holds or no
#     session list can be read for, still writes, and so does one that waits on
#     other work; what holds it, or its runs, not reading exits 1;
#   - a rework child handed back is taken before its anchor, then the highest
#     priority, then the oldest;
#   - an ask on the bead's PR is neither a wait on it nor a writer of its
#     branch, so the bead is taken; a rework child or another wait still holds
#     it;
#   - a conversation on the bead's PR, waiting in the operator's queue, held by
#     a sitting or stayed in, is neither a wait on it nor a writer of its
#     branch, so the bead is taken; another wait still holds it, a task that
#     tracks no bead or whose alias names another bead is no conversation and
#     holds it, the beads that hold it not reading exits 1, and a bead nothing
#     holds reads no other bead;
#   - no work exits 3, and a read that does not answer exits 1.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-find-work-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-find-work.sh
  # The runs the store holds, which run-lib.stub.sh answers from.
  export GC_RUN_LIB="$HERE/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$TMP/runs.json"
  echo '[]' > "$RUN_LIB_STUB_RUNS"
}
run() { OUT=$("$SUT/refinery-find-work.sh" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }

echo "# one bead assigned to the refinery with a branch is named, and nothing else is printed"
fresh
work a polecat/a
put '{"id":"other","title":"x","status":"open","assignee":"rig-a/gc-toolkit.polecat-1","issue_type":"task","notes":"","metadata":{"branch":"polecat/o"}}'
put '{"id":"nobranch","title":"x","status":"open","assignee":"rig-a/gc-toolkit.refinery","issue_type":"task","notes":"","metadata":{}}'
run
eq "$RC" 0 "find-work exits 0"
eq "$OUT" "a" "stdout is the one bead to take"

echo "# a blocked pending record is not listed; a half-written record is taken"
fresh
work pend polecat/p '{"merge_result":"pull_request_pending","pr_reconcile_pending":"true"}' blocked
work half polecat/h '{"pr_reconcile_pending":"true","existing_pr":"https://github.com/zook/rig/pull/52"}'
run
eq "$OUT" "half" "the half-written bead is taken, and the blocked one is not"

echo "# a held bead is left and named"
fresh
work held polecat/x
work free polecat/y
echo "held gate-1" > "$STUB_HOLDS"
run
eq "$OUT" "free" "the bead nothing holds is taken"
has "$ERR" "held waits on gate-1" "the held bead is named with what holds it"

echo "# a bead whose branch another open bead works on waits until that bead is gone"
fresh
work an polecat/shared
put '{"id":"writer","title":"x","status":"in_progress","assignee":"rig-a/gc-toolkit.polecat-1","issue_type":"task","notes":"","metadata":{"branch":"polecat/shared","task_kind":"rework","anchor_bead":"an"}}'
run
eq "$RC" 3 "with its only bead's branch worked elsewhere, find-work takes nothing (exit 3)"
has "$ERR" "an (writer works its branch)" "it names the bead and the writer of its branch"
jq 'map(if .id == "writer" then .status = "closed" else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
run
eq "$OUT" "an" "once the writer is gone, the bead is taken"

echo "# a rework that waits on the bead, with no run or claim, writes nothing on its branch"
# Two reworks on one PR's branch: the second yielded behind the first at its
# checkout (work-setup.sh), which made it wait on the first and armed it, and the
# first then handed back to the refinery. The anchor holds the PR's pending
# record and waits on both.
# two_reworks <what sib waits on> [<sib status>] [<sib assignee>]
two_reworks() {
  fresh
  work an polecat/an '{"merge_result":"pull_request_pending","pr_reconcile_pending":"true"}' blocked
  work rw polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
  put "$(jq -nc --arg s "${2:-open}" --arg a "${3:-}" '{id: "sib", title: "Rework", status: $s, assignee: $a, issue_type: "task", notes: "",
    metadata: {task_kind: "rework", anchor_bead: "an", branch: "polecat/an", "gc.dispatch_when_ready": "rig-a/gc-toolkit.polecat"}}')"
  printf 'an rw\nan sib\nsib %s\n' "$1" > "$STUB_HOLDS"
}
two_reworks rw
echo '[{"root":"r-sib","convoy":"c-sib","bead":"sib","formula":"mol-polecat-work","live":false}]' > "$RUN_LIB_STUB_RUNS"
run
eq "$RC $OUT" "0 rw" "the rework handed back is taken while its sibling waits on it, armed, and its run has ended"
hasnt "$ERR" "works its branch" "…since the sibling is no writer of the branch"
echo '[{"root":"r-sib","convoy":"c-sib","bead":"sib","formula":"mol-polecat-work","live":true}]' > "$RUN_LIB_STUB_RUNS"
run
eq "$RC" 3 "a sibling that waits on it while a live run works it still writes the branch (exit 3)"
has "$ERR" "rw (sib works its branch)" "…and is named as its writer"
two_reworks rw in_progress rig-a/gc-toolkit.polecat-2
STUB_SESSIONS_JSON='{"sessions":[{"alias":"rig-a/gc-toolkit.polecat-2"}]}' run
eq "$RC" 3 "a sibling that waits on it under a claim a listed session holds still writes the branch (exit 3)"
has "$ERR" "rw (sib works its branch)" "…and is named as its writer"
run
eq "$RC" 3 "…and so does one whose claim no session list can be read for, which proves nobody gone"
STUB_SESSIONS_JSON='{"sessions":[]}' run
eq "$RC $OUT" "0 rw" "a claim no listed session holds writes nothing, so the rework is taken"
two_reworks gate-1
export RUN_LIB_STUB_LOG="$TMP/runs.log"
run
eq "$RC" 3 "a sibling that waits on other work, not on the bead, still goes first (exit 3)"
has "$ERR" "rw (sib works its branch)" "…and is named as its writer"
eq "$(cat "$RUN_LIB_STUB_LOG" 2>/dev/null)" "" "…with no runs read, since only a bead that waits on the one it holds back is asked whether it is written"
unset RUN_LIB_STUB_LOG
two_reworks rw
work rw2 polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
jq 'map(if .id == "rw2" then .priority = 1 else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
run
eq "$RC $OUT" "0 rw" "a sibling that waits on one rework handed back is no writer of that one alone"
has "$ERR" "rw2 (sib works its branch)" "…so another handed back on the branch still waits for it, even at a higher priority"
two_reworks rw
STUB_HOLDS_FAIL=sib run
eq "$RC" 1 "what holds the other bead on the branch not answering exits 1"
eq "$OUT" "" "…and names no bead"
RUN_LIB_STUB_FAIL=all run
eq "$RC" 1 "the runs of a sibling that waits on it not reading exits 1"
eq "$OUT" "" "…and names no bead"

echo "# a rework child handed back is taken before its anchor"
fresh
work an polecat/s '{"merge_result":"pull_request_head_changed"}'
work ch polecat/s '{"task_kind":"rework","anchor_bead":"an"}'
jq 'map(if .id == "an" then .priority = 0 else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
run
eq "$OUT" "ch" "the child goes first, even below its anchor's priority"

echo "# then the highest priority, then the oldest"
fresh
work late polecat/1
work early polecat/2
work urgent polecat/3
jq 'map(if .id == "late" then .created_at = "2026-11-12T05:00:00Z" elif .id == "early" then .created_at = "2026-11-12T01:00:00Z" elif .id == "urgent" then .priority = 1 | .created_at = "2026-11-12T09:00:00Z" else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
run
eq "$OUT" "urgent" "the highest priority goes first"
jq 'map(select(.id != "urgent"))' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
run
eq "$OUT" "early" "within a priority, the oldest goes first"

echo "# an ask on the bead's PR is no wait and no writer"
ask() { put "$(jq -nc --arg id "$1" --argjson m "${2:-{\}}" '{id: $id, title: "Review ask: x", status: "open", assignee: "", issue_type: "task", notes: "",
  metadata: ({branch: "polecat/p"} + $m)}')"; }
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed","existing_pr":"https://github.com/zook/rig/pull/52"}'
ask k
echo "p k" > "$STUB_HOLDS"
run
eq "$RC $OUT" "0 p" "the bead an ask holds, on the ask's branch, is taken"
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
ask k
printf 'p k\np gate-3\n' > "$STUB_HOLDS"
run
eq "$RC" 3 "a bead another wait holds is left beside its ask"
has "$ERR" "p waits on gate-3" "…and names that wait"
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
ask k '{"gc.routed_to":"rig-a/gc-toolkit.polecat"}'
echo "p k" > "$STUB_HOLDS"
run
eq "$RC" 3 "a routed bead on the branch is no ask, and still holds the bead"
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
ask k '{"gc.execution_routed_to":"rig-a/gc-toolkit.polecat"}'
echo "p k" > "$STUB_HOLDS"
run
eq "$RC" 3 "a bead on the branch whose workflow Gas City's sling started is no ask, and still holds the bead"

echo "# a conversation on the bead's PR is no wait and no writer"
# conv <id> <status> <assignee>: a task that tracks p, as a conversation about
# p's PR does, which p's blocks edge onto it holds the merge of.
conv() { put "$(jq -nc --arg id "$1" --arg s "$2" --arg a "$3" '{id: $id, title: "Converse about the PR", status: $s, assignee: $a,
  issue_type: "task", notes: "", metadata: {}, dependencies: [{issue_id: $id, depends_on_id: "p", type: "tracks"}]}')"; }
for c in "open human" "in_progress rig-a/gc-toolkit.tk-c" "open rig-a/gc-toolkit.c-tk-c"; do
  fresh
  work p polecat/p '{"merge_result":"pull_request_head_changed","existing_pr":"https://github.com/zook/rig/pull/52"}'
  # shellcheck disable=SC2086  # the conversation's status and assignee
  conv tk-c $c
  echo "p tk-c" > "$STUB_HOLDS"
  run
  eq "$RC $OUT" "0 p" "the bead a conversation holds ($c) is taken"
done
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
conv tk-c open human
put '{"id":"gate-4","title":"a gate","status":"open","assignee":"","issue_type":"gate","notes":"","metadata":{}}'
printf 'p tk-c\np gate-4\n' > "$STUB_HOLDS"
run
eq "$RC" 3 "a bead another wait holds is left beside its conversation"
has "$ERR" "p waits on gate-4" "…and names that wait"
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
put '{"id":"owed","title":"Do a thing","status":"open","assignee":"human","issue_type":"task","notes":"","metadata":{}}'
echo "p owed" > "$STUB_HOLDS"
run
eq "$RC" 3 "work a person owes, which tracks no bead, is no conversation and still holds the bead"
has "$ERR" "p waits on owed" "…and names it"
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
conv tk-x open rig-a/gc-toolkit.tk-c
echo "p tk-x" > "$STUB_HOLDS"
run
eq "$RC" 3 "a task assigned to an alias that names another bead is no conversation and still holds the bead"
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
conv tk-c open human
echo "p tk-c" > "$STUB_HOLDS"
STUB_GC_ID_FAIL=1 run
eq "$RC" 1 "what holds the bead not reading by id exits 1"
eq "$OUT" "" "…and names no bead"
fresh
work a polecat/a
run
hasnt "$(logged gc)" "--id" "with nothing holding the bead, no bead is read by id"

echo "# no work, and reads that do not answer"
fresh
run
eq "$RC" 3 "an empty queue exits 3"
eq "$OUT" "" "…and prints nothing"
work a polecat/a
STUB_GC_LIST_FAIL=1 run
eq "$RC" 1 "a listing that does not answer exits 1"
eq "$OUT" "" "…and names no bead"
GCTK_BIN=none run
eq "$RC" 1 "no gctk binary to read the holds with exits 1"
GC_AGENT="" run
eq "$RC" 1 "an empty identity exits 1"

echo
echo "refinery-find-work: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
