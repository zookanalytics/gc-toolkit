#!/usr/bin/env bash
# Hermetic test for assets/scripts/duplicate-sweep.sh — arm 7 of the merge
# cadence. Covers: both proofs of "recorded no work" (an explicit
# work_outcome=no-op and the structural no-work-key case) and the fact that a
# no-op duplicate carrying the TWIN's branch still disposes; both successor
# conditions (closed, or open and shipped) and the open-unshipped hold; every
# refusal (empty marker, self-reference, an assignee, a review bead, a step
# bead, a foreign prior pointer, a cross-store successor, a non-no-op outcome,
# a missing outcome with work-product metadata, an unresolvable successor);
# in_progress excluded from the population; non-duplicates untouched;
# idempotence across passes; the args handed to bead-rehome; a disposal that
# does not read back; and the two ways the arm does nothing — an unreadable
# listing (exit 1, loud) and an absent disposal writer.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-duplicate-sweep-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/duplicate-sweep.sh"
SUT="$SD/duplicate-sweep.sh"
export GC_RIG="gc-toolkit"

# Stub disposal writer, standing in for bead-rehome.sh: stamps the pointer
# pair and closes, which is the shape the real script guarantees. Its knobs
# are the two partial states the real one can leave behind — REHOME_NO_CLOSE
# (pointer stamped, close refused: its documented exit 5) and REHOME_NO_STAMP
# (a write that reported success and did not land).
REHOME_LOG="$TMP/rehome.log"; : > "$REHOME_LOG"
cat > "$SD/bead-rehome.sh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${REHOME_LOG:?}"
origin=""; succ=""
while [ $# -gt 0 ]; do
  case "$1" in
    --origin) shift; origin="${1:-}" ;;
    --successor) shift; succ="${1:-}" ;;
  esac
  shift || true
done
S="${STUB_STORE:?}"; tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-duplicate-sweep-test.XXXXXX")"
if [ -z "${REHOME_NO_STAMP:-}" ]; then
  jq -c --arg id "$origin" --arg s "$succ" 'map(if .id == $id then
      .metadata["gc.superseded_by"] = $s
      | .metadata["gc.superseded_by_store"] = "rig:gc-toolkit" else . end)' "$S" > "$tmp" && mv "$tmp" "$S"
fi
if [ -z "${REHOME_NO_CLOSE:-}" ] && [ -z "${REHOME_NO_STAMP:-}" ]; then
  tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-duplicate-sweep-test.XXXXXX")"
  jq -c --arg id "$origin" 'map(if .id == $id then .status = "closed" else . end)' "$S" > "$tmp" && mv "$tmp" "$S"
fi
exit 0
STUB
chmod +x "$SD/bead-rehome.sh"
export REHOME_LOG
run() { "$SUT" 2>&1; }

# dup <id> <duplicate_of> [status] [extra-metadata-json]
dup() {
  local x="${4:-}"; [ -n "$x" ] || x='{}'
  jq -cn --arg id "$1" --arg d "$2" --arg st "${3:-open}" --argjson x "$x" \
    '{id:$id, status:$st, assignee:"", title:("dispatch " + $id),
      notes:"dispatch note", metadata:($x + {duplicate_of:$d})}'
}
# twin <id> <status> [extra-metadata-json]
twin() {
  local x="${3:-}"; [ -n "$x" ] || x='{}'
  jq -cn --arg id "$1" --arg st "$2" --argjson x "$x" \
    '{id:$id, status:$st, assignee:"", title:("twin " + $id), notes:"", metadata:$x}'
}
rehome_args() { cat "$REHOME_LOG"; }

echo "# proof A: an explicit no-op outcome, successor closed"
store "[$(dup D1 T1 open '{"work_outcome":"no-op"}'),$(twin T1 closed '{"merge_result":"merged"}')]"
: > "$REHOME_LOG"
out=$(run); rc=$?
eq "$rc" 0 "a completed pass exits 0"
eq "$(bstatus D1)" "closed" "the verified no-op duplicate is closed"
eq "$(meta D1 gc.superseded_by)" "T1" "…pointed at its twin"
eq "$(meta D1 gc.superseded_by_store)" "rig:gc-toolkit" "…with the store recorded"
has "$out" "closed D1 as a duplicate of T1" "…and the pass names what it disposed"
has "$out" "1 duplicate(s) disposed" "…and counts it"
a=$(rehome_args)
has "$a" "--kind duplicate" "the disposal goes through bead-rehome as a duplicate"
has "$a" "--origin D1" "…naming the origin"
has "$a" "--successor T1" "…and the successor"
has "$a" "merge_result=merged" "the reason says how the twin ended"
has "$a" "work_outcome=no-op" "…and which proof of no-work ran"
eq "$(bstatus T1)" "closed" "the twin is untouched"

echo "# proof A holds even when the duplicate carries the TWIN's branch"
store "[$(dup D2 T2 open '{"work_outcome":"no-op","branch":"polecat/T2","target":"main","merge_result":"merged","pr_number":"7"}'),$(twin T2 closed)]"
out=$(run); rc=$?
eq "$(bstatus D2)" "closed" "a rebase duplicate naming the twin's branch still disposes"
has "$out" "1 duplicate(s) disposed" "…branch-absence is not the no-work test"

echo "# proof B: no outcome recorded, and no work-product key either"
store "[$(dup D3 T3 blocked '{"hold_reason":"subsumed by T3; release: close as duplicate"}'),$(twin T3 closed)]"
: > "$REHOME_LOG"
out=$(run); rc=$?
eq "$(bstatus D3)" "closed" "a blocked bead carrying only a prose hold disposes on structure"
has "$(rehome_args)" "no branch, worktree, PR or merge_result" "…and the reason says structure proved it"
hasnt "$(rehome_args)" "work_outcome=no-op" "…not the explicit arm"
has "$(rehome_args)" "parked under a hold_reason" "…and the close reason says a hold was standing"
eq "$(meta D3 hold_reason)" "subsumed by T3; release: close as duplicate" "the hold text stays on the bead"

echo "# a duplicate with no hold is not described as having had one"
store "[$(dup D3b T3b open '{"work_outcome":"no-op"}'),$(twin T3b closed)]"
: > "$REHOME_LOG"
run >/dev/null
hasnt "$(rehome_args)" "parked under a hold_reason" "an unparked duplicate's reason claims no hold"

echo "# proof B refuses when work-product metadata exists"
store "[$(dup D4 T4 open '{"hold_reason":"h","branch":"polecat/D4","work_dir":"/w/D4"}'),$(twin T4 closed)]"
out=$(run); rc=$?
eq "$(bstatus D4)" "open" "an unrecorded outcome plus a worktree is left alone"
has "$out" "records no work_outcome and carries work-product metadata" "…saying why"
has "$out" "1 left alone" "…and counting it as held, not disposed"

echo "# a non-no-op outcome is a hard refusal under both proofs"
for o in shipped blocked abandoned; do
  store "[$(dup D5 T5 open "{\"gc.work_outcome\":\"$o\"}"),$(twin T5 closed)]"
  out=$(run)
  eq "$(bstatus D5)" "open" "work_outcome=$o is not disposable"
  has "$out" "records work_outcome=$o, which is not a no-op" "…and says so ($o)"
done

echo "# the gc.-prefixed and bare outcome spellings are both read"
store "[$(dup D6 T6 open '{"gc.work_outcome":"no-op"}'),$(twin T6 closed)]"
run >/dev/null
eq "$(bstatus D6)" "closed" "gc.work_outcome=no-op disposes"

echo "# successor conditions"
store "[$(dup D7 T7 open '{"work_outcome":"no-op"}'),$(twin T7 open)]"
out=$(run)
eq "$(bstatus D7)" "open" "an open, unshipped twin holds the duplicate"
has "$out" "successor T7 is open and has not shipped" "…and says which fact was missing"

store "[$(dup D8 T8 open '{"work_outcome":"no-op"}'),$(twin T8 open '{"gc.work_outcome":"shipped"}')]"
out=$(run)
eq "$(bstatus D8)" "closed" "an open twin that has SHIPPED is enough"
has "$out" "records work_outcome=shipped" "…and the reason says which condition held"

store "[$(dup D9 GONE open '{"work_outcome":"no-op"}')]"
out=$(run)
eq "$(bstatus D9)" "open" "a successor that does not resolve disposes nothing"
has "$out" "does not resolve in this store" "…and says the pointer is unresolvable"

echo "# nobody else's bead"
store "[$(dup DA TA open '{"work_outcome":"no-op"}'),$(twin TA closed)]"
store "$(jq -c '(.[] | select(.id == "DA") | .assignee) |= "rig/some.polecat"' "$STUB_STORE")"
out=$(run)
eq "$(bstatus DA)" "open" "an assigned duplicate is left to its holder"
has "$out" "assigned to rig/some.polecat" "…naming the holder"

store "[$(dup DB TB in_progress '{"work_outcome":"no-op"}'),$(twin TB closed)]"
out=$(run)
eq "$(bstatus DB)" "in_progress" "an in_progress duplicate is outside the population"
has "$out" "no live duplicate-marked beads" "…so the pass sees nothing at all"

store "[$(dup DC TC open '{"work_outcome":"no-op","task_kind":"review","anchor_bead":"TC"}'),$(twin TC closed)]"
out=$(run)
eq "$(bstatus DC)" "open" "a review bead is never closed here"
has "$out" "signoff.sh and review-sweep close those" "…deferring to the writers that own it"

store "[$(dup DD TD open '{"work_outcome":"no-op","gc.step_ref":"mol-x.implement"}'),$(twin TD closed)]"
out=$(run)
eq "$(bstatus DD)" "open" "a step bead is never closed here"
has "$out" "step bead or workflow root" "…saying what it is"

store "[$(dup DE TE open '{"work_outcome":"no-op","gc.kind":"workflow"}'),$(twin TE closed)]"
run >/dev/null
eq "$(bstatus DE)" "open" "a workflow root is never closed here"

echo "# a disposition somebody else already recorded is not overwritten"
store "[$(dup DF TF open '{"work_outcome":"no-op","gc.superseded_by":"OTHER"}'),$(twin TF closed)]"
out=$(run)
eq "$(bstatus DF)" "open" "a pointer to a different successor holds"
eq "$(meta DF gc.superseded_by)" "OTHER" "…and is left exactly as found"
has "$out" "somebody else's disposition" "…saying whose call it is"

echo "# a pointer that already names THIS successor is not an obstacle"
store "[$(dup DG TG open '{"work_outcome":"no-op","gc.superseded_by":"TG"}'),$(twin TG closed)]"
run >/dev/null
eq "$(bstatus DG)" "closed" "a half-finished disposition to the same twin completes"

echo "# a successor in another store is unreadable from here, not absent"
store "[$(dup DH TH open '{"work_outcome":"no-op","duplicate_of_store":"rig:gascity"}'),$(twin TH closed)]"
out=$(run)
eq "$(bstatus DH)" "open" "a cross-store successor is left alone"
has "$out" "lives in rig:gascity, which this pass cannot read" "…rather than judged against the local store"

store "[$(dup DI TI open '{"work_outcome":"no-op","duplicate_of_store":"rig:gc-toolkit"}'),$(twin TI closed)]"
run >/dev/null
eq "$(bstatus DI)" "closed" "a store ref naming THIS rig is not an obstacle"

echo "# malformed markers"
store "[$(dup DJ '' open '{"work_outcome":"no-op"}')]"
out=$(run)
eq "$(bstatus DJ)" "open" "an empty duplicate_of disposes nothing"
has "$out" "names no successor" "…and says the marker is empty"

store "[$(dup DK DK open '{"work_outcome":"no-op"}')]"
out=$(run)
eq "$(bstatus DK)" "open" "a self-referential marker disposes nothing"
has "$out" "names the bead itself" "…and says so"

echo "# beads with no marker at all are outside the population"
store "[$(twin N1 open),$(twin N2 closed)]"
out=$(run); rc=$?
eq "$rc" 0 "a store with no duplicate markers exits 0"
eq "$(bstatus N1)" "open" "…touching nothing"
has "$out" "no live duplicate-marked beads" "…and saying the population is empty"

echo "# idempotence: a disposed duplicate leaves the live population"
store "[$(dup DL TL open '{"work_outcome":"no-op"}'),$(twin TL closed)]"
out=$(run)
has "$out" "1 duplicate(s) disposed" "the first pass disposes"
: > "$REHOME_LOG"
out=$(run)
has "$out" "no live duplicate-marked beads" "the second pass finds nothing to do"
eq "$(rehome_args)" "" "…and calls the disposal writer zero times"

echo "# a disposal that does not read back is reported, not retried"
store "[$(dup DM TM open '{"work_outcome":"no-op"}'),$(twin TM closed)]"
out=$(REHOME_NO_CLOSE=1 run); rc=$?
eq "$rc" 0 "a refused close still completes the pass"
eq "$(bstatus DM)" "open" "the bead stays open"
eq "$(meta DM gc.superseded_by)" "TM" "…and pointed, which is the designed partial state"
has "$out" "was NOT disposed" "the arm reports the refusal"
has "$out" "1 write(s) held for retry" "…and counts it apart from the disposals"
hasnt "$out" "1 duplicate(s) disposed" "…never claiming it disposed of one"

store "[$(dup DN TN open '{"work_outcome":"no-op"}'),$(twin TN closed)]"
out=$(REHOME_NO_STAMP=1 run)
eq "$(bstatus DN)" "open" "a pointer that never landed leaves the bead open"
has "$out" "gc.superseded_by=''" "…and the arm names the empty pointer it read back"

echo "# the two ways this arm does nothing"
store "[$(dup DO TO open '{"work_outcome":"no-op"}'),$(twin TO closed)]"
out=$(STUB_LIST_FAIL=1 run); rc=$?
eq "$rc" 1 "an unreadable listing exits 1"
eq "$(bstatus DO)" "open" "…and disposes of nothing"
has "$out" "false all-clear" "…rather than reporting one"

chmod -x "$SD/bead-rehome.sh"
: > "$REHOME_LOG"
out=$(run); rc=$?
eq "$rc" 0 "an absent disposal writer is not a pass failure"
eq "$(bstatus DO)" "open" "…and nothing is closed without it"
has "$out" "the disposal writer is the whole arm" "…saying why the arm stood down"
hasnt "$out" "duplicate(s) disposed" "…before enumerating, so no pass is reported"
hasnt "$out" "held for retry" "…and no bead is left looking like a failed write"
eq "$(rehome_args)" "" "…having attempted nothing"
chmod +x "$SD/bead-rehome.sh"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
