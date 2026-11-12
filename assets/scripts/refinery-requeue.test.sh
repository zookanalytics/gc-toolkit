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
#     unassigned, so a run of the landing order that read it writes nothing;
#   - a bead that records an open PR keeps it and comes back as its rework
#     child: a task with the work order, joined to the bead and blocking it,
#     settled and slung, while the bead stays with the refinery;
#   - an open rework child already on the branch takes the reason in its notes
#     and nothing else is filed, and one that was never dispatched is slung;
#   - a rework child handed back goes back itself, and its anchor is untouched;
#   - a write whose guard no longer holds writes nothing (exit 3);
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
run() { OUT=$("$SUT/refinery-requeue.sh" "$@" 2>&1); RC=$?; }

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

echo "# a half-written record goes back the same way, unassigned"
fresh
branch_with polecat/h h.txt >/dev/null
work h polecat/h '{"pr_reconcile_pending":"true","existing_pr":"https://github.com/zook/rig/pull/52"}' in_progress
prepared h polecat/h
run --bead h --reason "lint fails"
eq "$RC" 0 "the requeue exits 0"
eq "$(bassignee h)" "" "the half-written bead is left unassigned"
eq "$(bstatus h)" "open" "…and open"
has "$(logged gc)" "--if-status=in_progress" "the write is guarded on the status read"
eq "$(meta h existing_pr)" "https://github.com/zook/rig/pull/52" "it keeps the PR it may reuse"
hasnt "$(logged gc)" "bd create" "no rework child is filed for it"

echo "# a bead that records an open PR comes back as its rework child"
fresh
branch_with polecat/p p.txt >/dev/null
work p polecat/p '{"merge_result":"pull_request_head_changed","pr_url":"https://github.com/zook/rig/pull/7","existing_pr":"https://github.com/zook/rig/pull/7"}'
prepared p polecat/p
run --bead p --reason "Conflicts with main at abc"
eq "$RC" 0 "the requeue exits 0"
CHILD=$(jq -r '[ .[] | select(.metadata.task_kind == "rework") ][0].id // ""' "$STORE")
[ -n "$CHILD" ] && rt_ok "a rework child is filed" || rt_bad "a rework child is filed"
eq "$(meta "$CHILD" anchor_bead) $(meta "$CHILD" branch) $(meta "$CHILD" target) $(meta "$CHILD" merge_strategy)" "p polecat/p main mr" "the child resumes the bead's branch and lands on its PR"
eq "$(meta "$CHILD" existing_pr)" "https://github.com/zook/rig/pull/7" "…keeping the PR"
eq "$(meta "$CHILD" rejection_reason)" "Conflicts with main at abc" "…with the reason"
has "$(logged gc)" "create Rework polecat/p for p: Conflicts with main at abc -t task --metadata" "it is created as a task"
has "$(logged gc)" "--deps related:p" "…joined to the bead"
has "$(logged gc)" "dep $CHILD --blocks p" "…and blocking it"
has "$(logged scripts)" "queue-priority settle $CHILD" "it is settled at its priority before the sling"
has "$(logged gc)" "rig-a/gc-toolkit.polecat $CHILD --on mol-polecat-work" "the child is slung"
eq "$(bstatus p) $(bassignee p) $(meta p merge_result)" "open rig-a/gc-toolkit.refinery pull_request_head_changed" "the bead keeps its record and stays with the refinery"

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
fresh
branch_with polecat/u u.txt >/dev/null
work u polecat/u '{"merge_result":"pull_request_head_changed"}'
put '{"id":"u-kid","title":"Rework","status":"open","assignee":"","issue_type":"task","notes":"","metadata":{"task_kind":"rework","anchor_bead":"u","branch":"polecat/u"}}'
prepared u polecat/u
run --bead u --reason "lint fails"
eq "$RC" 0 "the requeue exits 0"
has "$(logged gc)" "rig-a/gc-toolkit.polecat u-kid --on mol-polecat-work" "a child filed and never dispatched is slung"
hasnt "$(logged gc)" "bd create" "…and no second child is filed"

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

echo "# a sling that fails arms a retry, and an arm that fails files a gate"
fresh
branch_with polecat/s s.txt >/dev/null
work s polecat/s
prepared s polecat/s
STUB_SLING_RC=1 run --bead s --reason "test fails"
eq "$RC" 0 "an armed retry counts as sent back"
has "$(logged scripts)" "deferred-dispatch arm s --target rig-a/gc-toolkit.polecat --sling-arg --on --sling-arg mol-polecat-work" "a deferred dispatch is armed"
fresh
branch_with polecat/s s.txt >/dev/null
work s polecat/s
prepared s polecat/s
STUB_SLING_RC=1 STUB_DEFERRED_DISPATCH_RC=1 run --bead s --reason "test fails"
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
