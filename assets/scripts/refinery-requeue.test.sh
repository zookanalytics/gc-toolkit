#!/usr/bin/env bash
# Hermetic test for refinery-requeue.sh, which sends work the refinery will
# not land back to the polecat pool. Runs the real script against real git
# repositories and a fake gc (refinery-test-lib.sh). Proves:
#   - a bead with no record goes back itself in one write guarded on the
#     assignee and status it read: open, unassigned, with the reason, its claim
#     route, pour stamp and session pins cleared, and its branch, target and
#     existing_pr kept; a live workflow on it is closed, and it is slung on
#     mol-polecat-work;
#   - a half-written record, the marker and existing_pr, goes back the same way,
#     unassigned with its marker cleared in the same write, so a run of the
#     landing order that read it writes nothing and no later run reads it;
#   - a bead a park left blocked, or one the landing order sent back to be
#     validated again, goes back with its merge_result and blocked_reason
#     cleared, since the work gate refuses a bead that carries one, and keeps
#     the PR it may reuse;
#   - a bead that owns an open PR on the record keeps it, and its branch goes
#     to the review run: an ask with the reason, opening on a line that names
#     the head the prep read, is filed on the bead, and only then is the PR
#     recorded pending at that head, with no rework child. An ask that does
#     not land records nothing. A record that does not land after the ask
#     leaves the bead as it was, held by the ask and so never pending without
#     it, and asks a person to write the record; the next patrol's find-work
#     takes the bead, and its requeue of the same head finds the open ask and
#     files no second, whatever its reason;
#   - an open rework child already on the branch takes the reason in its notes,
#     and nothing else is filed or slung;
#   - a rework child handed back goes back itself, and its anchor is untouched;
#   - a write whose guard no longer holds writes nothing (exit 3), and a write
#     the store fails is no move of the bead: it stops (exit 1);
#   - a sling that fails arms a deferred dispatch, and an arm that fails too
#     files a gate;
#   - a bead whose branch the refinery's tree does not hold gets no write.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-requeue-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-requeue.sh
}
# The fixture for the patrol after a requeue, whose find-work takes the bead
# again.
fresh_patrol() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-requeue.sh refinery-find-work.sh
}
run() { OUT=$("$SUT/refinery-requeue.sh" "$@" 2>&1); RC=$?; }
find_work() { NAMED=$("$SUT/refinery-find-work.sh" 2>/dev/null); FW_RC=$?; }
kid() { jq -r '[ .[] | select(.metadata.task_kind == "rework") ][0].id // ""' "$STORE"; }

echo "# a bead with no record goes back itself, unassigned, in one guarded write"
fresh
branch_with polecat/a a.txt >/dev/null
work a polecat/a '{"existing_pr":"https://github.com/zook/rig/pull/9","gc.routed_to":"x","gc.execution_routed_to":"rig-a/gc-toolkit.polecat","gc.session_id":"s-1","gc.session_name":"polecat-1"}'
prepared a polecat/a
run --bead a --reason "test TestX fails on the branch"
eq "$RC" 0 "the requeue exits 0"
eq "$(bstatus a) $(bassignee a)" "open " "the bead is open and unassigned"
eq "$(meta a rejection_reason)" "test TestX fails on the branch" "it carries the reason"
eq "$(meta a gc.execution_routed_to)$(meta a gc.routed_to)$(meta a gc.session_id)$(meta a gc.session_name)" "<absent><absent><absent><absent>" "its route, pour stamp and session pins are cleared"
eq "$(meta a branch) $(meta a existing_pr)" "polecat/a https://github.com/zook/rig/pull/9" "its branch and existing_pr stay"
has "$(logged gc)" "--if-assignee=rig-a/gc-toolkit.refinery --if-status=open --status=open --assignee=" "the write is guarded on the assignee and status read"
has "$(logged gc)" "workflow delete-source a --apply" "a live workflow on it is closed"
has "$(logged gc)" "sling --rig rig-a rig-a/gc-toolkit.polecat a --on mol-polecat-work" "it is slung on mol-polecat-work"

echo "# a half-written record goes back the same way, unassigned, with its marker cleared"
fresh
branch_with polecat/h h.txt >/dev/null
work h polecat/h '{"pr_reconcile_pending":"true","existing_pr":"https://github.com/zook/rig/pull/52"}' in_progress
prepared h polecat/h
run --bead h --reason "lint fails"
eq "$RC" 0 "the requeue exits 0"
eq "$(bassignee h)" "" "the half-written bead is left unassigned"
eq "$(bstatus h)" "open" "…and open"
eq "$(meta h pr_reconcile_pending)" "<absent>" "…with its marker cleared, so the landing order reads no PR that waits on it"
has "$(logged gc)" "--if-status=in_progress" "the write is guarded on the status read"
has "$(logged gc)" "--unset-metadata pr_reconcile_pending" "…in the write that reopens it"
eq "$(meta h existing_pr)" "https://github.com/zook/rig/pull/52" "it keeps the PR it may reuse"
hasnt "$(logged gc)" "bd create" "no rework child is filed for it"

echo "# a parked bead, or one sent back to be validated again, goes back with no merge_result"
fresh
branch_with polecat/p p.txt >/dev/null
work p polecat/p '{"merge_result":"blocked","blocked_reason":"refinery-false-completion: no change"}'
prepared p polecat/p
run --bead p --reason "Conflicts with main at 1234567"
eq "$RC" 0 "the requeue of a parked bead exits 0"
eq "$(meta p merge_result) $(meta p blocked_reason)" "<absent> <absent>" "its merge_result and blocked_reason are cleared, so the work gate takes it"
eq "$(bstatus p) $(bassignee p)" "open " "it is open and unassigned"
has "$(logged gc)" "sling --rig rig-a rig-a/gc-toolkit.polecat p --on mol-polecat-work" "it is slung"
branch_with polecat/v v.txt >/dev/null
work v polecat/v '{"merge_result":"pull_request_record_incomplete","pr_state":"revalidation_required","existing_pr":"https://github.com/zook/rig/pull/53"}'
prepared v polecat/v
run --bead v --reason "test TestY fails on the branch"
eq "$RC" 0 "the requeue of a record sent back to be validated again exits 0"
eq "$(meta v merge_result)" "<absent>" "its merge_result is cleared"
eq "$(meta v existing_pr)" "https://github.com/zook/rig/pull/53" "it keeps the PR it may reuse"
hasnt "$(logged gc)" "bd create" "no rework child is filed for either"

echo "# a bead that owns an open PR on the record sends its branch to the review run as an ask"
fresh
branch_with polecat/p p.txt >/dev/null
work p polecat/p '{"merge_result":"pull_request_head_changed","pr_url":"https://github.com/zook/rig/pull/7","existing_pr":"https://github.com/zook/rig/pull/7"}'
prepared p polecat/p
READ=$(git -C "$HOME_DIR/worktrees/p" rev-parse refs/worktree/refinery/polecat/p)
run --bead p --reason "Conflicts with main at abc"
eq "$RC" 0 "the requeue exits 0"
eq "$(kid)" "" "no rework child is filed"
has "$(logged gctk)" "pr record p --pr https://github.com/zook/rig/pull/7 --head $READ --target main --refinery rig-a/gc-toolkit.refinery" "the PR is recorded pending at the head the prep read"
eq "$(bstatus p) $(meta p merge_result) $(meta p pr_head_sha)" "blocked pull_request_pending $READ" "…so the landing order reads the record at that head"
ASK=$(jq -r '[ .[] | select((.title // "") | startswith("Review ask: ")) ][0].id // ""' "$STORE")
[ -n "$ASK" ] && rt_ok "an ask is filed" || rt_bad "an ask is filed"
eq "$(meta "$ASK" branch)" "polecat/p" "…naming the PR's branch"
eq "$(jq -r --arg id "$ASK" '.[] | select(.id == $id) | .description' "$STORE")" "The refinery sent $READ back:
Conflicts with main at abc" "…whose reason opens on a line naming the head, then the refinery's"
ASK_AT=$(grep -n "^review ask p " "$LOGS/gctk.log" | head -n 1 | cut -d: -f1)
RECORD_AT=$(grep -n "^pr record p " "$LOGS/gctk.log" | head -n 1 | cut -d: -f1)
[ -n "$ASK_AT" ] && [ -n "$RECORD_AT" ] && [ "$ASK_AT" -lt "$RECORD_AT" ] \
  && rt_ok "the ask is filed before the PR is recorded pending" || rt_bad "the ask is filed before the PR is recorded pending" "ask at line ${ASK_AT:-none}, record at ${RECORD_AT:-none}"
has "$(cat "$STUB_HOLDS")" "p $ASK" "the bead waits on its ask"
hasnt "$(logged gc)" "sling" "nothing is slung, since the review run is the branch's one writer"
has "$OUT" "takes its ask $ASK" "the requeue names the ask"

echo "# an ask that does not land records nothing, and the bead stays with the refinery"
fresh
branch_with polecat/p p.txt >/dev/null
work p polecat/p '{"merge_result":"pull_request_head_changed","existing_pr":"https://github.com/zook/rig/pull/7"}'
prepared p polecat/p
STUB_ASK_RC=2 run --bead p --reason "test TestX fails"
eq "$RC" 1 "an ask that does not land stops the requeue (exit 1)"
hasnt "$(logged gctk)" "pr record" "the PR is not recorded pending"
hasnt "$(logged scripts)" "human-gate" "no person is asked"
eq "$(bstatus p) $(bassignee p) $(meta p merge_result)" "open rig-a/gc-toolkit.refinery pull_request_head_changed" "the bead stays with the refinery as it was"

echo "# a record that does not land after the ask leaves the ask holding the bead, and asks a person to write it"
fresh_patrol
branch_with polecat/p p.txt >/dev/null
work p polecat/p '{"merge_result":"pull_request_head_changed","existing_pr":"https://github.com/zook/rig/pull/7"}'
prepared p polecat/p
READ=$(git -C "$HOME_DIR/worktrees/p" rev-parse refs/worktree/refinery/polecat/p)
STUB_RECORD_RC=2 run --bead p --reason "test TestX fails"
eq "$RC" 1 "a record that does not land stops the requeue (exit 1)"
ASK=$(jq -r '[ .[] | select((.title // "") | startswith("Review ask: ")) ][0].id // ""' "$STORE")
[ -n "$ASK" ] && rt_ok "the ask filed first stands" || rt_bad "the ask filed first stands"
has "$(cat "$STUB_HOLDS")" "p $ASK" "…and holds the bead, so no merge waits only on the record"
eq "$(bstatus p) $(bassignee p) $(meta p merge_result) $(meta p pr_head_sha)" "open rig-a/gc-toolkit.refinery pull_request_head_changed <absent>" "the bead is not recorded pending, so the landing order merges nothing at that head"
has "$(logged scripts)" "human-gate --subject p --key refinery-requeue-failed" "a gate on the bead asks a person"
has "$(logged scripts)" "pr record p --pr https://github.com/zook/rig/pull/7 --head $READ --target main --refinery rig-a/gc-toolkit.refinery" "…naming the record to write by hand"
find_work
eq "$FW_RC $NAMED" "0 p" "the next patrol takes the bead the ask holds"
run --bead p --reason "TestX fails at the second check"
eq "$RC" 0 "the requeue of the same head exits 0"
eq "$(jq '[ .[] | select((.title // "") | startswith("Review ask: ")) ] | length' "$STORE")" "1" "it files no second ask, though its reason differs"
has "$OUT" "ask $ASK, which an earlier requeue of $READ filed, is open" "…and names the ask it found"
eq "$(bstatus p) $(meta p merge_result) $(meta p pr_head_sha)" "blocked pull_request_pending $READ" "the PR is recorded pending at that head"
has "$OUT" "takes its ask $ASK" "…and the run takes the first ask"

echo "# a record the bead's guard refuses leaves the bead as it stands, with the ask holding its merge"
fresh
branch_with polecat/p p.txt >/dev/null
work p polecat/p '{"merge_result":"pull_request_head_changed","existing_pr":"https://github.com/zook/rig/pull/7"}'
prepared p polecat/p
STUB_RECORD_RC=3 run --bead p --reason "test TestX fails"
eq "$RC" 3 "a record the bead's guard refuses exits 3"
has "$OUT" "changed after it was read" "it says the bead moved"
ASK=$(jq -r '[ .[] | select((.title // "") | startswith("Review ask: ")) ][0].id // ""' "$STORE")
[ -n "$ASK" ] && rt_ok "the ask filed first stands" || rt_bad "the ask filed first stands"
has "$(cat "$STUB_HOLDS")" "p $ASK" "…and holds the bead"
eq "$(bstatus p) $(bassignee p) $(meta p merge_result)" "open rig-a/gc-toolkit.refinery pull_request_head_changed" "the bead is left as it stands"
hasnt "$(logged scripts)" "human-gate" "no person is asked"

echo "# an open rework child already on the branch takes the reason, and nothing else is filed"
fresh
branch_with polecat/q q.txt >/dev/null
work q polecat/q '{"merge_result":"pull_request_head_changed"}'
put '{"id":"q-kid","title":"Rework","status":"in_progress","assignee":"rig-a/gc-toolkit.polecat-2","issue_type":"task","notes":"","metadata":{"task_kind":"rework","anchor_bead":"q","branch":"polecat/q","gc.execution_routed_to":"rig-a/gc-toolkit.polecat"}}'
prepared q polecat/q
run --bead q --reason "Conflicts with main at def"
eq "$RC" 0 "the requeue exits 0"
has "$(bnotes q-kid)" "Conflicts with main at def" "the child already on the branch takes the reason"
hasnt "$(logged gc)" "bd create" "no second child is filed"
hasnt "$(logged gc)" "sling" "a child already dispatched is not slung again"
for k in '"source_review_bead":"rv-1"' '"gc.dispatch_when_ready":"rig-a/gc-toolkit.polecat"'; do
  fresh
  branch_with polecat/u u.txt >/dev/null
  work u polecat/u '{"merge_result":"pull_request_head_changed"}'
  put "{\"id\":\"u-kid\",\"title\":\"Rework\",\"status\":\"open\",\"assignee\":\"\",\"issue_type\":\"task\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"rework\",\"anchor_bead\":\"u\",\"branch\":\"polecat/u\",$k}}"
  prepared u polecat/u
  run --bead u --reason "lint fails"
  eq "$RC" 0 "the requeue exits 0 ($k)"
  hasnt "$(logged gc)" "sling" "a child a review filed, or one armed, is its filer's or its arm's to send ($k)"
done

echo "# a rework child handed back goes back itself, and its anchor is untouched"
fresh
branch_with polecat/an an.txt >/dev/null
put '{"id":"an","title":"Anchor","status":"open","assignee":"","issue_type":"task","notes":"","metadata":{"branch":"polecat/an","merge_result":"pull_request"}}'
work ch polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
prepared ch polecat/an
run --bead ch --reason "test fails"
eq "$RC" 0 "the requeue exits 0"
eq "$(bassignee ch) $(meta ch rejection_reason)" " test fails" "the child goes back unassigned with the reason"
eq "$(meta an merge_result) $(bnotes an)" "pull_request " "the anchor is untouched"
hasnt "$(logged gc)" "bd create" "no new child is filed"

echo "# a write whose guard no longer holds writes nothing"
fresh
branch_with polecat/g g.txt >/dev/null
work g polecat/g
prepared g polecat/g
STUB_GUARD_FAIL=1 run --bead g --reason "test fails"
eq "$RC" 3 "a bead that moved after its read exits 3"
has "$OUT" "changed after it was read" "it says the bead moved"
eq "$(meta g rejection_reason)" "<absent>" "nothing is written"
hasnt "$(logged gc)" "sling" "nothing is slung"
fresh
branch_with polecat/g g.txt >/dev/null
work g polecat/g
prepared g polecat/g
STUB_UPDATE_FAIL=1 run --bead g --reason "test fails"
eq "$RC" 1 "a write the store fails stops (exit 1)"
has "$OUT" "a failure of the store rather than a change to g" "it names the store, not a move of the bead"
hasnt "$OUT" "changed after it was read" "…and never says the bead moved"
eq "$(bassignee g) $(meta g rejection_reason)" "rig-a/gc-toolkit.refinery <absent>" "the bead stays with the refinery, unwritten"
hasnt "$(logged gc)" "sling" "nothing is slung"

echo "# a sling that fails arms a retry, and an arm that fails files a gate"
fresh
branch_with polecat/s s.txt >/dev/null
work s polecat/s
prepared s polecat/s
STUB_SLING_RC=1 run --bead s --reason "test fails"
eq "$RC" 0 "an armed retry counts as sent back"
has "$(logged gctk)" "bead arm s --target rig-a/gc-toolkit.polecat --on mol-polecat-work" "a deferred dispatch is armed"
fresh
branch_with polecat/s s.txt >/dev/null
work s polecat/s
prepared s polecat/s
STUB_SLING_RC=1 STUB_ARM_RC=1 run --bead s --reason "test fails"
eq "$RC" 1 "a sling and an arm that both fail stop (exit 1)"
has "$(logged scripts)" "human-gate --subject s --key refinery-requeue-failed" "a refinery-requeue-failed gate asks a person to pour it"

echo "# a bead whose branch the refinery's tree does not hold gets no write"
fresh
branch_with polecat/w w.txt >/dev/null
branch_with polecat/v v.txt >/dev/null
work w polecat/w
work v polecat/v
prepared v polecat/v
run --bead w --reason "test fails"
eq "$RC" 1 "a bead this iteration did not prepare is refused"
eq "$(meta w rejection_reason) $(bassignee w)" "<absent> rig-a/gc-toolkit.refinery" "nothing is written on it"
run --bead w
eq "$RC" 2 "no reason is usage"

echo
echo "refinery-requeue: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
