#!/usr/bin/env bash
# Hermetic test for assets/scripts/review-sweep.sh — arm 6 of the merge cadence.
# Covers: the sweep condition (anchor closed AND review_branch absent from
# origin) and every way it fails to hold (anchor still open, branch still on
# origin, no review_branch, no anchor_bead, an anchor that does not resolve);
# the disposal shape (gc.outcome=moot, the reason APPENDED to the dispatch
# note, status closed, both read back); a claimed review swept anyway; closed
# reviews and non-review beads untouched; idempotence across passes; a write
# that does not read back; and the two unreadable enumerations — origin's
# branch list and the review listing — each of which sweeps nothing and says so.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/review-sweep.sh"
SUT="$SD/review-sweep.sh"
run() { "$SUT" 2>&1; }

# origin's branch list: what git ls-remote --heads serves this pass.
REFS="$TMP/refs"
export STUB_LS_REMOTE="$REFS"
printf 'main\npolecat/live\n' > "$REFS"

review() { # id anchor branch [status] [assignee]
  printf '{"id":"%s","status":"%s","assignee":"%s","notes":"dispatch note","title":"Review branch %s -> main: t","metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"%s","review_branch":"%s"}}' \
    "$1" "${4:-open}" "${5:-}" "$3" "$2" "$3"
}
anchor() { # id status [merge_result]
  printf '{"id":"%s","status":"%s","assignee":"","notes":"","title":"anchor %s","metadata":{"merge_result":"%s","branch":"polecat/%s"}}' \
    "$1" "$2" "$1" "${3:-merged}" "$1"
}

echo "# the sweep condition: anchor closed AND branch gone from origin"
store "[$(review R1 A1 polecat/gone),$(anchor A1 closed merged)]"
out=$(run); rc=$?
eq "$rc" 0 "a completed pass exits 0"
eq "$(bstatus R1)" "closed" "the phantom review is closed"
eq "$(meta R1 gc.outcome)" "moot" "…recorded as moot, not as a verdict"
has "$out" "closed review R1" "…and the pass names what it closed"
has "$out" "1 review(s) closed" "…and counts it"
n=$(notes R1)
has "$n" "dispatch note" "the dispatch note survives (notes are APPENDED)"
has "$n" "closed with no verdict" "the reason is recorded on the bead"
has "$n" "A1" "…naming the anchor"
has "$n" "polecat/gone" "…and the branch that is gone"
has "$n" "merge_result=merged" "…and how the anchor ended"
eq "$(meta A1 check.codex)" "<absent>" "no gate marker was written on the anchor"
eq "$(bstatus A1)" "closed" "the anchor is untouched"

echo "# a second pass re-sweeps nothing, with the loop still running"
store "$(jq -c ". + [$(review R1L A1 polecat/live)]" "$STUB_STORE")"
out=$(run); rc=$?
eq "$rc" 0 "the repeat pass exits 0"
has "$out" "0 review(s) closed" "the already-closed review is out of the live population"
has "$out" "1 left alone" "…and the pass still walked the one live review beside it"
eq "$(bstatus R1L)" "open" "…which it left open"

echo "# anchor still open: the review is still owed"
store "[$(review R2 A2 polecat/gone),$(anchor A2 open pull_request)]"
out=$(run)
eq "$(bstatus R2)" "open" "a review whose anchor still gates is left alone"
has "$out" "0 review(s) closed" "…and nothing is swept"

echo "# branch still on origin: a live surface, whatever the anchor says"
store "[$(review R3 A3 polecat/live),$(anchor A3 closed merged)]"
run >/dev/null
eq "$(bstatus R3)" "open" "a branch still on origin is never swept"

echo "# neither condition: untouched"
store "[$(review R4 A4 polecat/live),$(anchor A4 open pull_request)]"
run >/dev/null
eq "$(bstatus R4)" "open" "an ordinary in-flight review is untouched"

echo "# untestable conditions are not satisfied conditions"
store "[{\"id\":\"R5\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"t\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"A5\"}},$(anchor A5 closed merged)]"
run >/dev/null
eq "$(bstatus R5)" "open" "a review carrying no review_branch is left alone"
store "[{\"id\":\"R6\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"t\",\"metadata\":{\"task_kind\":\"review\",\"review_branch\":\"polecat/gone\"}}]"
run >/dev/null
eq "$(bstatus R6)" "open" "a review carrying no anchor_bead is left alone"
store "[$(review R7 A7 polecat/gone)]"
out=$(run)
eq "$(bstatus R7)" "open" "a review whose anchor does not resolve is left alone"
has "$out" "does not resolve" "…and the pass says which anchor it could not read"

echo "# a claimed review with nothing to review is swept too"
store "[$(review R8 A8 polecat/gone in_progress rig/codex-1),$(anchor A8 closed merged)]"
run >/dev/null
eq "$(bstatus R8)" "closed" "a claimed phantom is closed, not left burning its holder"

echo "# only review beads, only live ones"
store "[{\"id\":\"W1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"work\",\"metadata\":{\"anchor_bead\":\"A9\",\"review_branch\":\"polecat/gone\"}},$(review R9 A9 polecat/gone closed),$(anchor A9 closed merged)]"
out=$(run)
eq "$(bstatus W1)" "open" "a bead without task_kind=review is not this arm's business"
has "$out" "no live review beads" "…and an all-closed review population is nothing to do"

echo "# a close that does not read back is reported, never counted"
store "[$(review RX AX polecat/gone),$(anchor AX closed merged)]"
out=$(STUB_DROP_KEYS="RX:status" run); rc=$?
eq "$rc" 0 "a stuck write does not fail the arm (the next pass retries)"
eq "$(bstatus RX)" "open" "the bead really did not close"
has "$out" "did not read back" "…and the pass says so"
has "$out" "0 review(s) closed" "…without counting it swept"
has "$out" "1 write(s) held for retry" "…and reports it held for retry"

echo "# an unreadable origin sweeps nothing"
store "[$(review RY AY polecat/gone),$(anchor AY closed merged)]"
out=$(STUB_LS_REMOTE_RC=128 run); rc=$?
eq "$rc" 1 "an unreachable origin exits 1"
eq "$(bstatus RY)" "open" "…and closes nothing (every branch would read as deleted)"
has "$out" "branch list is unreadable" "…saying why"

echo "# a rig with nothing to sweep never reaches origin"
store "[$(anchor AZ closed merged)]"
out=$(STUB_LS_REMOTE_RC=128 run); rc=$?
eq "$rc" 0 "no live reviews exits 0 even with origin unreachable"
has "$out" "no live review beads" "…having stopped before the branch read"
store "[$(review RY AY polecat/gone),$(anchor AY closed merged)]"

echo "# an empty branch listing is unreadable, not an empty repository"
: > "$REFS"
out=$(run); rc=$?
eq "$rc" 1 "an empty ls-remote exits 1"
eq "$(bstatus RY)" "open" "…and closes nothing"
printf 'main\npolecat/live\n' > "$REFS"

echo "# an unreadable review listing sweeps nothing"
out=$(STUB_LIST_FAIL=1 run); rc=$?
eq "$rc" 1 "an unreadable review listing exits 1"
eq "$(bstatus RY)" "open" "…and closes nothing"
has "$out" "false all-clear" "…rather than reporting one"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
