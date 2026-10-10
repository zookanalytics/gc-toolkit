#!/usr/bin/env bash
# Hermetic test for assets/scripts/duplicate-sweep.sh — arm 11 of the merge
# cadence. Covers, for the duplicate_of marker pass: both proofs of "recorded
# no work" (an explicit work_outcome=no-op and the structural no-work-key case)
# and the fact that a no-op duplicate carrying the TWIN's branch still
# disposes; both successor conditions (closed, or open and shipped) and the
# open-unshipped hold; every refusal (empty marker, self-reference, an
# assignee, a review bead, a step bead, a foreign prior pointer, a cross-store
# successor, a non-no-op outcome, a missing outcome with work-product metadata,
# an unresolvable successor); in_progress excluded from the population;
# non-duplicates untouched; idempotence across passes; the args handed to
# bead-rehome; a disposal that does not read back; and the two ways the arm
# does nothing — an unreadable listing (exit 1, loud) and an absent disposal
# writer. For the never-dispatched rework twin pass: the disposal releases the
# anchor's merge hold and the finding's edge, on synthetic fixtures and on a
# replay of a real orphan and its landed twin; every never-dispatched proof
# (dispatch metadata, an assignee, a convoy tracking it, a deferred dispatch
# armed as the live counter-case is) and every landing proof (closed with its
# rejection_reason gone and dispatched, or shipped; not disposed, retired,
# no-op or on another anchor; a promotion to an anchor of its own counts only
# once merged) refuses on its own; the review-open hold; a
# prior pointer finished or refused; the earliest-filed of two landed
# siblings; and idempotence.
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

# --- never-dispatched rework twins -------------------------------------------
# rw <id> <status> <review> <anchor> [extra-metadata-json] — a rework child
# carrying the work order signoff.sh stamps on every child.
rw() {
  local x="${5:-}"; [ -n "$x" ] || x='{}'
  jq -cn --arg id "$1" --arg st "$2" --arg r "$3" --arg a "$4" --argjson x "$x" \
    '{id:$id, status:$st, assignee:"", created_at:"2026-09-18T21:27:33Z",
      title:("Rework branch polecat/" + $a + ": address pre-open signoff findings"), notes:"",
      metadata:({task_kind:"rework", anchor_bead:$a, branch:("polecat/" + $a), target:"main",
                 source_review_bead:$r, merge_strategy:"mr"} + $x)}'
}
# orphan <id> <review> <anchor> [extra-metadata-json] — a child as signoff.sh
# filed it, which nothing touched again.
orphan() {
  local x="${4:-}"; [ -n "$x" ] || x='{}'
  rw "$1" open "$2" "$3" "$(jq -cn --argjson x "$x" \
    '{rejection_reason:"signoff requested changes: address the 1 finding(s) this bead blocks. VERDICT: request-changes"} + $x')"
}
# landed <id> <review> <anchor> [extra-metadata-json] — a dispatched child the
# refinery landed: closed, rejection_reason unset, held by the refinery.
landed() {
  local x="${4:-}"; [ -n "$x" ] || x='{}'
  rw "$1" closed "$2" "$3" "$(jq -cn --argjson x "$x" \
    '{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat", work_dir:"/w/worktree", prepare_mode:"rebase"} + $x')" \
    | jq -c '.assignee = "gc-toolkit/gc-toolkit.refinery" | .created_at = "2026-09-18T21:30:50Z"'
}
review() {
  jq -cn --arg id "$1" --arg st "${2:-closed}" \
    '{id:$id, status:$st, assignee:"", title:("Review " + $id), notes:"",
      metadata:{task_kind:"review", "gc.outcome":"recorded", signoff_verdict:"request-changes"}}'
}
anchor() {
  jq -cn --arg id "$1" \
    '{id:$id, status:"open", assignee:"", title:("anchor " + $id), notes:"",
      metadata:{merge_result:"pre_open_gate", branch:("polecat/" + $id)}}'
}
finding() {
  jq -cn --arg id "$1" --arg a "$2" \
    '{id:$id, status:"open", assignee:"", title:("finding " + $id), notes:"",
      metadata:{task_kind:"finding", anchor_bead:$a, "finding.disposition":"must-fix"}}'
}
convoy() {
  jq -cn --arg id "$1" --arg st "${2:-closed}" \
    '{id:$id, status:$st, assignee:"", issue_type:"convoy", title:("input convoy " + $id), notes:"", metadata:{}}'
}
edge() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$STUB_DEPS"; }
scene() { store "$1"; : > "$STUB_DEPS"; : > "$REHOME_LOG"; }
# The blockers merge.sh and gate-ensure would count: live ones only.
live_blockers() {
  gc bd dep list "$1" --direction=down -t blocks --json \
    | jq -r '[ .[] | select((.status // "open") != "closed") | .id ] | join(",")'
}
# A pair whose landing is proved, around which one gate at a time is varied.
twin_scene() { # <orphan-extra-json> <landed-extra-json>
  scene "[$(anchor A1),$(review R1),$(orphan O1 R1 A1 "${1:-}"),$(landed L1 R1 A1 "${2:-}"),$(convoy CV1)]"
  edge O1 blocks A1; edge L1 blocks A1; edge CV1 tracks L1
}

echo "# a never-dispatched twin whose sibling landed is disposed, releasing the anchor"
scene "[$(anchor A1),$(review R1),$(orphan O1 R1 A1),$(landed L1 R1 A1),$(convoy CV1),$(finding F1 A1)]"
edge O1 blocks A1; edge L1 blocks A1; edge CV1 tracks L1; edge O1 blocks F1
eq "$(live_blockers A1)" "O1" "before the pass the twin is the anchor's one live blocker"
out=$(run); rc=$?
eq "$rc" 0 "a completed pass exits 0"
eq "$(bstatus O1)" "closed" "the twin is closed"
eq "$(meta O1 gc.superseded_by)" "L1" "…pointed at the sibling that landed"
eq "$(meta O1 gc.superseded_by_store)" "rig:gc-toolkit" "…with the store recorded"
eq "$(live_blockers A1)" "" "the anchor's merge hold is released"
eq "$(live_blockers F1)" "" "…and so is the finding the twin blocked"
eq "$(meta O1 duplicate_of)" "L1" "the closed twin is marked duplicate_of, which pr-stack reads to keep it off the branch's bead list"
a=$(rehome_args)
has "$a" "--origin O1" "the disposal names the twin as the origin"
has "$a" "--successor L1" "…the landed sibling as the successor"
has "$a" "--kind duplicate" "…as a duplicate"
has "$a" "answers the same review R1 on anchor A1" "the reason names the shared review and anchor"
has "$a" "was dispatched (gc.execution_routed_to=gc-toolkit/gc-toolkit.polecat) and is closed" "…how the sibling's landing was proved"
has "$a" "O1 was never dispatched" "…and why the twin carried no work"
has "$a" "review R1 is closed" "…and that signoff is done with the review"
has "$out" "closed O1 as a duplicate of L1" "the pass names what it disposed"
has "$out" "1 duplicate(s) disposed" "…and counts it"
eq "$(bstatus L1)" "closed" "the sibling is untouched"
eq "$(meta L1 gc.superseded_by)" "<absent>" "…and carries no pointer"
eq "$(bstatus A1)" "open" "the anchor is untouched"
eq "$(meta A1 merge_result)" "pre_open_gate" "…including its lifecycle state"

echo "# replay: the real orphan and its landed twin, metadata as the store holds it"
store "$(jq -cn '[
  {id:"tk-5n01ns", status:"open", assignee:"", title:"anchor", notes:"",
   metadata:{merge_result:"pre_open_gate", branch:"polecat/tk-5n01ns"}},
  {id:"tk-6rb445", status:"closed", assignee:"", title:"Review branch polecat/tk-5n01ns -> main", notes:"",
   metadata:{task_kind:"review", anchor_bead:"tk-5n01ns", "gc.outcome":"recorded", signoff_verdict:"request-changes"}},
  {id:"tk-shutdw", status:"open", assignee:null, created_at:"2026-09-18T21:27:33Z",
   title:"Rework branch polecat/tk-5n01ns: address pre-open signoff findings", notes:"",
   metadata:{anchor_bead:"tk-5n01ns", branch:"polecat/tk-5n01ns", merge_strategy:"mr",
     rejection_reason:"signoff requested changes (round 2): address the 1 finding(s) this bead blocks. VERDICT: request-changes",
     source_review_bead:"tk-6rb445", target:"main", task_kind:"rework"}},
  {id:"tk-ko029i", status:"closed", assignee:"gc-toolkit/gc-toolkit.refinery", created_at:"2026-09-18T21:30:50Z",
   title:"Rework branch polecat/tk-5n01ns: address pre-open signoff findings",
   notes:"Rework landed on polecat/tk-5n01ns at 918986ce; gating continues on anchor tk-5n01ns",
   metadata:{anchor_bead:"tk-5n01ns", branch:"polecat/tk-5n01ns", "gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat",
     "gc.routed_to":"", merge_strategy:"mr", prepare_mode:"rebase", source_review_bead:"tk-6rb445", target:"main",
     task_kind:"rework", work_dir:"/w/tk-ko029i"}},
  {id:"tk-3p3c3k", status:"closed", assignee:"", issue_type:"convoy", title:"input convoy for tk-ko029i", notes:"", metadata:{}}
]')"
: > "$STUB_DEPS"; : > "$REHOME_LOG"
edge tk-shutdw blocks tk-5n01ns; edge tk-ko029i blocks tk-5n01ns; edge tk-3p3c3k tracks tk-ko029i
out=$(run)
eq "$(bstatus tk-shutdw)" "closed" "the replayed orphan is disposed"
eq "$(meta tk-shutdw gc.superseded_by)" "tk-ko029i" "…as a duplicate of the twin that landed"
eq "$(live_blockers tk-5n01ns)" "" "…and its anchor is no longer held"

echo "# an empty-valued route is no route"
twin_scene '{"gc.execution_routed_to":"","gc.routed_to":"","gc.deferred_assignee":""}'
run >/dev/null
eq "$(bstatus O1)" "closed" "keys present with empty values record no dispatch"

echo "# a twin that was dispatched is left alone"
for k in gc.execution_routed_to gc.routed_to gc.dispatch_when_ready gc.claimed_at work_dir self_review_passed_sha gc.work_outcome; do
  twin_scene "{\"$k\":\"x\"}"
  out=$(run)
  eq "$(bstatus O1)" "open" "a twin recording $k is not disposed"
  hasnt "$out" "O1" "…and is outside the population, not reported every pass"
  eq "$(rehome_args)" "" "…with no disposal attempted ($k)"
done

echo "# only an OPEN twin is in the population"
for st in in_progress blocked deferred; do
  twin_scene
  store "$(jq -c --arg st "$st" '(.[] | select(.id == "O1") | .status) |= $st' "$STUB_STORE")"
  run >/dev/null
  eq "$(bstatus O1)" "$st" "a twin whose status is $st is left as it is"
  eq "$(rehome_args)" "" "…with no disposal attempted ($st)"
done

echo "# an assigned twin is left to its holder"
twin_scene
store "$(jq -c '(.[] | select(.id == "O1") | .assignee) |= "rig/some.polecat"' "$STUB_STORE")"
run >/dev/null
eq "$(bstatus O1)" "open" "an assigned twin is not disposed"
eq "$(rehome_args)" "" "…and no disposal is attempted"

echo "# a convoy tracking the twin proves a pour even when the metadata does not"
twin_scene
store "$(jq -c --argjson c "$(convoy CV9 open)" '. + [$c]' "$STUB_STORE")"; edge CV9 tracks O1
out=$(run)
eq "$(bstatus O1)" "open" "a twin a molecule was poured over is not disposed"
has "$out" "convoy CV9 tracks it, so a molecule was poured over it" "…and the pass names the convoy"

echo "# a tracks edge from a bead that is not a convoy is no pour"
twin_scene
store "$(jq -c '. + [{id:"BUG1", status:"open", assignee:"", issue_type:"bug", title:"instance bug", notes:"", metadata:{}}]' "$STUB_STORE")"
edge BUG1 tracks O1
run >/dev/null
eq "$(bstatus O1)" "closed" "an instance bug tracking the twin does not hold it"

echo "# the deferred-dispatch counter-case: armed, cleared stamps, convoys from earlier pours"
scene "[$(anchor A1),$(review R1),$(orphan O1 R1 A1 '{"gc.deferred_assignee":"","gc.deferred_execution_routed_to":"","gc.deferred_routed_to":"","gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]","gc.dispatch_when_ready_reason":"serialized behind base-refresh","gc.execution_routed_to":"","gc.routed_to":""}'),$(landed L1 R1 A1),$(convoy CV1),$(convoy CV2 open),$(convoy CV3)]"
edge O1 blocks A1; edge CV1 tracks L1; edge CV2 tracks O1; edge CV3 tracks O1
run >/dev/null
eq "$(bstatus O1)" "open" "an armed deferred dispatch is not disposed, even beside a landed sibling"
eq "$(live_blockers A1)" "O1" "…and still holds its anchor, as it should"
store "$(jq -c '(.[] | select(.id == "O1") | .metadata) |= del(.["gc.dispatch_when_ready"])' "$STUB_STORE")"
out=$(run)
eq "$(bstatus O1)" "open" "with the arm gone, the convoys from its earlier pours still hold it"
has "$out" "convoy CV2 tracks it" "…the second proof standing on its own"

echo "# the review must be closed: signoff may still adopt the child"
twin_scene
store "$(jq -c '(.[] | select(.id == "R1") | .status) |= "open"' "$STUB_STORE")"
out=$(run)
eq "$(bstatus O1)" "open" "a twin whose review is still open is not disposed"
has "$out" "its review R1 is open, so signoff.sh may still adopt and dispatch it" "…saying why"
store "$(jq -c 'map(select(.id != "R1"))' "$STUB_STORE")"
out=$(run)
eq "$(bstatus O1)" "open" "a review that does not resolve holds too"
has "$out" "its review R1 does not resolve" "…saying so"

echo "# a sibling that has not landed holds the twin"
scene "[$(anchor A1),$(review R1),$(orphan O1 R1 A1),$(rw L1 open R1 A1 '{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}'),$(convoy CV1 open)]"
edge O1 blocks A1; edge L1 blocks A1; edge CV1 tracks L1
out=$(run)
eq "$(bstatus O1)" "open" "a sibling still in flight is not a landing"
has "$out" "no other child of review R1 on anchor A1 has landed" "…and the pass says what it looked for"
scene "[$(anchor A1),$(review R1),$(orphan O1 R1 A1)]"
out=$(run)
eq "$(bstatus O1)" "open" "a child with no sibling at all is never disposed"
has "$out" "no other child of review R1" "…for the same reason"

echo "# each non-landing close is refused on its own"
for spec in \
  'rejection_reason|{"rejection_reason":"signoff requested changes"}' \
  'gc.outcome=moot|{"gc.outcome":"moot"}' \
  'work_outcome=no-op|{"gc.work_outcome":"no-op"}' \
  'a successor pointer|{"gc.superseded_by":"OTHER"}' \
  'a duplicate_of marker|{"duplicate_of":"OTHER"}' \
  'another anchor|{"anchor_bead":"A2"}'; do
  label="${spec%%|*}"; x="${spec#*|}"
  twin_scene '' "$x"
  out=$(run)
  eq "$(bstatus O1)" "open" "a closed sibling carrying $label is not a landing"
done

echo "# a sibling promoted to an anchor of its own landed only if it merged"
# The promotion unsets rejection_reason, so the closed branch cannot stand on
# that field alone.
for mr in pre_open_gate pull_request abandoned retargeted blocked refused_false_completion held; do
  twin_scene '' "{\"merge_result\":\"$mr\"}"
  out=$(run)
  eq "$(bstatus O1)" "open" "a closed sibling at merge_result=$mr is not a landing"
  has "$out" "no other child of review R1 on anchor A1 has landed" "…so the twin is held ($mr)"
done
twin_scene '' '{"merged_target":"main"}'
out=$(run)
eq "$(bstatus O1)" "open" "a promotion moved back to unanchored keeps its merged_target, and is not a landing"
has "$out" "no other child of review R1 on anchor A1 has landed" "…so the twin is held"
twin_scene '' '{"merge_result":"merged","merged_target":"main","merged_sha":"abc1234"}'
out=$(run)
eq "$(bstatus O1)" "closed" "a promoted sibling whose own PR merged has landed"
eq "$(meta O1 gc.superseded_by)" "L1" "…and the twin is pointed at it"

echo "# a promoted sibling whose PR was abandoned, then closed by hand, keeps the real twin"
twin_scene '' '{"merge_result":"abandoned","merged_target":"main","check_set":"codex","pr_url":"https://github.com/o/r/pull/9","pr_number":"9"}'
out=$(run)
eq "$(bstatus O1)" "open" "the abandoned promotion is not a landing"
eq "$(live_blockers A1)" "O1" "…and the twin still holds its anchor"
eq "$(rehome_args)" "" "…with no disposal attempted"

echo "# a closed sibling never dispatched is another twin, not a landing"
twin_scene '' '{"gc.execution_routed_to":"","work_dir":"","prepare_mode":""}'
: > "$STUB_DEPS"; edge O1 blocks A1
out=$(run)
eq "$(bstatus O1)" "open" "no dispatch metadata and no convoy: not a landing"
has "$out" "no other child of review R1 on anchor A1 has landed" "…so the twin is held"

echo "# a landing whose dispatch metadata was scrubbed is proved by its convoy"
twin_scene '' '{"gc.execution_routed_to":"","work_dir":""}'
out=$(run)
eq "$(bstatus O1)" "closed" "the convoy tracking the sibling proves its dispatch"
has "$(rehome_args)" "was dispatched (convoy CV1 tracks it) and is closed" "…and the reason says so"

echo "# a sibling that records work_outcome=shipped has landed, open or closed"
scene "[$(anchor A1),$(review R1),$(orphan O1 R1 A1),$(rw L1 open R1 A1 '{"gc.work_outcome":"shipped","work_dir":"/w/L1"}' | jq -c '.assignee = "gc-toolkit/gc-toolkit.refinery"')]"
edge O1 blocks A1
out=$(run)
eq "$(bstatus O1)" "closed" "an open sibling handed back shipped is enough"
has "$(rehome_args)" "records work_outcome=shipped" "…and the reason says which condition held"

echo "# a twin someone parked is left alone"
twin_scene '{"hold_reason":"keep until the operator rules"}'
out=$(run)
eq "$(bstatus O1)" "open" "a twin under a hold_reason is not disposed"
has "$out" "parked under a hold_reason" "…saying why"

echo "# a twin carrying duplicate_of belongs to the marker pass"
twin_scene '{"duplicate_of":"L1"}'
out=$(run)
hasnt "$out" "never dispatched" "the twin pass does not judge a marked child"

echo "# a twin with no anchor_bead cannot be matched"
scene "[$(review R1),$(orphan O1 R1 A1),$(landed L1 R1 A1)]"
store "$(jq -c '(.[] | select(.id == "O1") | .metadata) |= del(.anchor_bead)' "$STUB_STORE")"
out=$(run)
eq "$(bstatus O1)" "open" "a twin naming no anchor is not disposed"
has "$out" "names no anchor_bead" "…saying why"

echo "# a prior pointer: finished when it names the landed sibling, refused otherwise"
twin_scene '{"gc.superseded_by":"L1","gc.superseded_by_store":"rig:gc-toolkit"}'
run >/dev/null
eq "$(bstatus O1)" "closed" "a half-finished disposition to the landed sibling completes"
twin_scene '{"gc.superseded_by":"ELSEWHERE"}'
out=$(run)
eq "$(bstatus O1)" "open" "a pointer to something else is somebody else's disposition"
eq "$(meta O1 gc.superseded_by)" "ELSEWHERE" "…and is left exactly as found"
has "$out" "already records a successor pointer to ELSEWHERE" "…saying whose call it is"

echo "# two landed siblings: the earliest filed is the successor"
scene "[$(anchor A1),$(review R1),$(orphan O1 R1 A1),$(landed L2 R1 A1 | jq -c '.created_at = "2026-09-18T22:00:00Z"'),$(landed L1 R1 A1)]"
run >/dev/null
eq "$(meta O1 gc.superseded_by)" "L1" "the choice does not depend on store order"

echo "# an unreadable tracks probe is not an all-clear"
twin_scene
out=$(STUB_DEP_GARBAGE=1 run)
eq "$(bstatus O1)" "open" "a twin whose edges cannot be read is not disposed"
has "$out" "a pour over it cannot be ruled out" "…saying so"

echo "# idempotence: a disposed twin leaves the population"
twin_scene
run >/dev/null
: > "$REHOME_LOG"
out=$(run)
has "$out" "no open rework child is undispatched" "the second pass finds no twin"
eq "$(rehome_args)" "" "…and calls the disposal writer zero times"

echo "# a twin disposal that does not read back is reported, not counted"
twin_scene
out=$(REHOME_NO_CLOSE=1 run)
eq "$(bstatus O1)" "open" "the twin stays open"
has "$out" "O1 was NOT disposed" "the refusal is reported"
has "$out" "1 write(s) held for retry" "…and counted apart from the disposals"
eq "$(meta O1 duplicate_of)" "<absent>" "…and it is not marked, so it stays in the twin pass"
run >/dev/null
eq "$(bstatus O1)" "closed" "the next pass finishes the disposal its pointer names"
eq "$(meta O1 duplicate_of)" "L1" "…and marks it then"

echo "# a marker that does not stick after the close is reported"
twin_scene
out=$(STUB_UPDATE_FAIL="O1" run)
eq "$(bstatus O1)" "closed" "the disposal itself stands"
has "$out" "1 duplicate(s) disposed" "…and is counted"
has "$out" "duplicate_of=L1 did not stick" "…while the missing marker is reported"

echo "# both passes run in one invocation"
scene "[$(dup D1 T1 open '{"work_outcome":"no-op"}'),$(twin T1 closed),$(anchor A1),$(review R1),$(orphan O1 R1 A1),$(landed L1 R1 A1)]"
out=$(run); rc=$?
eq "$rc" 0 "a pass with work in both exits 0"
eq "$(bstatus D1)" "closed" "the marked duplicate is disposed"
eq "$(bstatus O1)" "closed" "…and so is the rework twin"
has "$out" "2 duplicate(s) disposed" "…and the summary counts both"
out=$(STUB_LIST_FAIL=1 run); rc=$?
eq "$rc" 1 "an unreadable listing still exits 1"
has "$out" "could not enumerate open rework children" "…and the twin pass reports its own enumeration"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
