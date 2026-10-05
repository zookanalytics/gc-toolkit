#!/usr/bin/env bash
# Hermetic test for assets/scripts/scaffolding-sweep.sh — arm 10 of the merge
# cadence. Covers: the sweep condition (machine scaffolding on a DISPOSED
# anchor, by either disposition marker) and every way it fails to hold (a live
# anchor, a merged anchor, no disposition, no anchor_bead, an anchor that does
# not resolve); the scope boundary (task_kind=visit and task_kind=review left
# standing); the close ordering (a finding closed before the rework it blocks,
# under the store's blocks-refusal); the disposal shape (gc.outcome=moot, the
# reason APPENDED to the dispatch note, status closed, both read back); a
# claimed bead swept anyway; closed and non-scaffolding beads untouched;
# idempotence across passes; a write that does not read back; and an unreadable
# enumeration, which sweeps nothing and says so.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-scaffolding-sweep-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/scaffolding-sweep.sh"
SUT="$SD/scaffolding-sweep.sh"
run() { "$SUT" 2>&1; }

scaf() { # id anchor kind [status]
  printf '{"id":"%s","status":"%s","assignee":"","notes":"dispatch note","title":"%s on %s","metadata":{"task_kind":"%s","anchor_bead":"%s"}}' \
    "$1" "${4:-open}" "$3" "$2" "$3" "$2"
}
# extra: a JSON metadata fragment, already comma-prefixed when non-empty.
anchor() { # id merge_result [extra_meta]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"anchor %s","metadata":{"merge_result":"%s"%s}}' \
    "$1" "$1" "$2" "${3:-}"
}
SUP='"gc.superseded_by":"SUCC"'          # bead-rehome stamped a successor pointer
DISP='"gc.pr_close_disposition_kind":"not-needed"'  # pr-dispose recorded intent

echo "# the sweep condition: machine scaffolding on a disposed anchor (superseded_by)"
store "[$(scaf F1 ADISP finding),$(scaf V1 ADISP validation),$(scaf RW1 ADISP rework),$(anchor ADISP pull_request ",$SUP")]"
out=$(run); rc=$?
eq "$rc" 0 "a completed pass exits 0"
eq "$(bstatus F1)"  "closed" "the finding is retired"
eq "$(bstatus V1)"  "closed" "the validation pass is retired"
eq "$(bstatus RW1)" "closed" "the rework is retired"
eq "$(meta F1 gc.outcome)" "moot" "…recorded as moot, not as a verdict"
eq "$(bstatus ADISP)" "open" "the anchor itself is NEVER closed by this arm"
eq "$(meta ADISP gc.superseded_by)" "SUCC" "…and the anchor is otherwise untouched"
has "$out" "3 scaffolding bead(s) closed" "the pass counts what it closed"
has "$out" "closed finding F1" "…and names each"
n=$(notes F1)
has "$n" "dispatch note" "the dispatch note survives (notes are APPENDED)"
has "$n" "retired as moot" "the reason is recorded on the bead"
has "$n" "ADISP" "…naming the anchor"
has "$n" "superseded_by=SUCC" "…and the disposition that made it moot"

echo "# the other disposition marker: a pre-recorded PR-close disposition"
store "[$(scaf F2 ADISP2 finding),$(anchor ADISP2 pull_request ",$DISP")]"
run >/dev/null
eq "$(bstatus F2)" "closed" "a pr_close_disposition_kind is a disposed anchor too"
has "$(notes F2)" "pr_close_disposition=not-needed" "…and the note names it"

echo "# scope boundary: human visits and review beads are left standing"
store "[$(scaf F3 ADISP3 finding),{\"id\":\"VIS3\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"visit\",\"metadata\":{\"task_kind\":\"visit\",\"anchor_bead\":\"ADISP3\"}},{\"id\":\"REV3\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"review\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"ADISP3\"}},$(anchor ADISP3 pull_request ",$SUP")]"
out=$(run)
eq "$(bstatus F3)"  "closed" "the finding on the disposed anchor is retired"
eq "$(bstatus VIS3)" "open"  "a human visit on the same anchor is left standing"
eq "$(bstatus REV3)" "open"  "a review bead is left to review-sweep, not this arm"
has "$out" "1 scaffolding bead(s) closed" "…so only the one machine bead is swept"

echo "# a live anchor's scaffolding is in flight, not moot"
store "[$(scaf F4 ALIVE finding),$(anchor ALIVE pull_request)]"
out=$(run)
eq "$(bstatus F4)" "open" "an anchor with no disposition marker is left alone"
has "$out" "0 scaffolding bead(s) closed" "…and nothing is swept"

echo "# a merged anchor is a landing, not a disposal (close-answered's, not this arm's)"
store "[$(scaf F5 AMRG finding),$(anchor AMRG merged ",$SUP")]"
run >/dev/null
eq "$(bstatus F5)" "open" "scaffolding on a merged anchor is left alone even with a pointer present"

echo "# findings close before the reworks they block, in one pass"
store "[$(scaf FB ABLK finding),$(scaf RB ABLK rework),$(anchor ABLK pull_request ",$SUP")]"
printf 'FB|blocks|RB\n' >> "$STUB_DEPS"   # the finding blocks the rework
out=$(STUB_ENFORCE_BLOCKS=1 run); rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(bstatus FB)" "closed" "the finding closes (nothing blocks it)"
eq "$(bstatus RB)" "closed" "…and the rework closes the same pass, no longer blocked"
: > "$STUB_DEPS"

echo "# a claimed scaffolding bead is swept too"
store "[$(scaf F6 ADISP6 rework in_progress),$(anchor ADISP6 pull_request ",$SUP")]"
run >/dev/null
eq "$(bstatus F6)" "closed" "a claimed rework on a disposed anchor has nothing left to produce"

echo "# untestable conditions are not satisfied conditions"
store "[{\"id\":\"F7\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"t\",\"metadata\":{\"task_kind\":\"finding\"}}]"
run >/dev/null
eq "$(bstatus F7)" "open" "a finding carrying no anchor_bead is left alone"
store "[$(scaf F8 AGONE finding)]"
out=$(run)
eq "$(bstatus F8)" "open" "a finding whose anchor does not resolve is left alone"
has "$out" "does not resolve" "…and the pass says which anchor it could not read"

echo "# only scaffolding beads, only live ones (idempotence across passes)"
store "[{\"id\":\"W1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"work\",\"metadata\":{\"anchor_bead\":\"A9\"}},$(scaf F9 A9 finding closed),$(anchor A9 pull_request ",$SUP")]"
out=$(run)
eq "$(bstatus W1)" "open" "a bead carrying no scaffolding task_kind is not this arm's business"
has "$out" "no live scaffolding beads" "…and an all-closed population is nothing to do"

echo "# a close that does not read back is reported, never counted"
store "[$(scaf FX ADX finding),$(anchor ADX pull_request ",$SUP")]"
out=$(STUB_DROP_KEYS="FX:status" run); rc=$?
eq "$rc" 0 "a stuck write does not fail the arm (the next pass retries)"
eq "$(bstatus FX)" "open" "the bead really did not close"
has "$out" "did not read back" "…and the pass says so"
has "$out" "0 scaffolding bead(s) closed" "…without counting it swept"
has "$out" "1 write(s) held for retry" "…and reports it held for retry"

echo "# an unreadable enumeration sweeps nothing"
store "[$(scaf FY ADY finding),$(anchor ADY pull_request ",$SUP")]"
out=$(STUB_LIST_FAIL=1 run); rc=$?
eq "$rc" 1 "an unreadable scaffolding listing exits 1"
eq "$(bstatus FY)" "open" "…and closes nothing"
has "$out" "false all-clear" "…rather than reporting one"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
