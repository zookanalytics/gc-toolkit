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
#   - a rework child handed back is taken before its anchor, then the highest
#     priority, then the oldest;
#   - a rework child the requeue filed and never sent on, which nothing holds,
#     neither holds its bead nor works its branch, so the bead is taken and the
#     child named; one in flight, assigned, armed, labeled with a hold, held,
#     or filed for a review still does, and so does any other wait on the bead;
#   - a bead the old path's cadence drives is left, and named;
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

echo "# a rework child filed and never sent on is no wait and no writer"
unsent_kid() { put "$(jq -nc --argjson m "${1:-{\}}" --arg a "${2:-}" --argjson l "${3:-[]}" '{id: "c", title: "Rework", status: "open", assignee: $a, issue_type: "task", notes: "", labels: $l,
  metadata: ({task_kind: "rework", anchor_bead: "p", branch: "polecat/p"} + $m)}')"; }
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
unsent_kid
echo "p c" > "$STUB_HOLDS"
run
eq "$RC $OUT" "0 p" "the bead its unsent child holds, on the child's branch, is taken"
has "$ERR" "p's rework child c was filed and never sent on" "…naming the child its prep sends on"
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
unsent_kid
run
eq "$RC $OUT" "0 p" "…and so is one whose unsent child has no blocks edge"
for v in '{"gc.execution_routed_to":"rig-a/gc-toolkit.polecat"}|' '{}|rig-a/gc-toolkit.polecat-1' '{"gc.dispatch_when_ready":"rig-a/gc-toolkit.polecat"}|' \
         '{"source_review_bead":"rv-1"}|' '{}||["hold:mayor"]'; do
  IFS='|' read -r m a l <<< "$v"
  fresh
  work p polecat/p '{"merge_result":"pull_request_head_changed"}'
  unsent_kid "$m" "$a" "${l:-[]}"
  echo "p c" > "$STUB_HOLDS"
  run
  eq "$RC" 3 "a child that is not unsent still holds its bead ($v)"
  has "$ERR" "p waits on c" "…and is named ($v)"
done
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
unsent_kid
printf 'p c\nc gate-1\n' > "$STUB_HOLDS"
run
eq "$RC" 3 "an unsent child something holds still holds its bead"
fresh
work p polecat/p '{"merge_result":"pull_request_head_changed"}'
unsent_kid
printf 'p c\np gate-2\n' > "$STUB_HOLDS"
run
eq "$RC" 3 "a bead another wait holds is left beside its unsent child"
has "$ERR" "p waits on gate-2" "…and names that wait"

echo "# a bead the old path's cadence drives is left and named"
fresh
work cad polecat/c '{"merge_result":"pull_request"}'
work gate polecat/g '{"merge_result":"pre_open_gate"}'
run
eq "$RC" 3 "neither is taken (exit 3)"
has "$ERR" "cad(pull_request)" "the pull_request bead is named"
has "$ERR" "gate(pre_open_gate)" "the pre_open_gate bead is named"

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
