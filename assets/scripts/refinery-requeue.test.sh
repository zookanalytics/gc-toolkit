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
#   - a bead a park left blocked, or one the landing order sent back to be
#     validated again, goes back with its merge_result and blocked_reason
#     cleared, since the work gate refuses a bead that carries one, and keeps
#     the PR it may reuse;
#   - a bead that records an open PR keeps it and comes back as its rework
#     child: a task with the work order, joined to the bead and blocking it
#     through edges in its create, settled and slung, while the bead stays with
#     the refinery;
#   - a child that does not settle is not slung, and the next patrol sends it
#     on: find-work takes the bead, and its prep runs the requeue again, which
#     settles the child before its sling. A child left without its blocks edge
#     is sent on the same way, with the edge written first. A create the store
#     refuses files nothing, so find-work takes the bead as it was, and a create
#     whose reply was lost is found among the bead's children and sent on;
#   - an open rework child already on the branch takes the reason in its notes
#     and nothing else is filed, and an unsent one is sent on, its blocks edge
#     and its priority made whole first. When that fails, a gate on the child
#     asks a person, and find-work leaves the bead until the gate clears;
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
# The fixture for the patrol after a requeue: find-work, then the prep, which
# runs the requeue again.
fresh_patrol() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-requeue.sh refinery-find-work.sh refinery-prep.sh detached-job.sh
}
run() { OUT=$("$SUT/refinery-requeue.sh" "$@" 2>&1); RC=$?; }
find_work() { NAMED=$("$SUT/refinery-find-work.sh" 2>"$TMP/fw-err"); FW_RC=$?; FW_ERR=$(cat "$TMP/fw-err"); }
prep() { PREP_OUT=$("$SUT/refinery-prep.sh" "$@" 2>&1); PREP_RC=$?; }
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
has "$(logged gc)" "--deps blocks:p" "…and blocking it, through edges in its create"
hasnt "$(logged gc)" "bd dep " "…so no edge is a write of its own that could fail after the create"
eq "$(cat "$STUB_HOLDS")" "p $CHILD" "the bead waits on its child"
has "$(logged scripts)" "queue-priority settle $CHILD" "it is settled at its priority before the sling"
has "$(logged gc)" "rig-a/gc-toolkit.polecat $CHILD --on mol-polecat-work" "the child is slung"
eq "$(bstatus p) $(bassignee p) $(meta p merge_result)" "open rig-a/gc-toolkit.refinery pull_request_head_changed" "the bead keeps its record and stays with the refinery"

echo "# a child that does not settle is not slung, and the next patrol sends it on"
fresh_patrol
branch_with polecat/p p.txt >/dev/null
work p polecat/p '{"merge_result":"pull_request_head_changed","existing_pr":"https://github.com/zook/rig/pull/7"}'
prepared p polecat/p
STUB_QUEUE_PRIORITY_RC=1 run --bead p --reason "test TestX fails"
eq "$RC" 1 "a child that does not settle stops the requeue (exit 1)"
CHILD=$(kid)
eq "$(bstatus "$CHILD") $(bassignee "$CHILD") $(meta "$CHILD" rejection_reason)" "open  test TestX fails" "the child is filed whole and left open, unassigned"
eq "$(cat "$STUB_HOLDS")" "p $CHILD" "…blocking the bead"
hasnt "$(logged gc)" "sling" "it is not slung, since a pour copies the priority it finds"
hasnt "$(logged scripts)" "deferred-dispatch" "…nor armed"
has "$OUT" "the refinery's next patrol sends it on" "the requeue says what sends it on"
reset_logs
find_work
eq "$FW_RC $NAMED" "0 p" "the next patrol's find-work takes the bead its unsent child holds"
has "$FW_ERR" "p's rework child $CHILD was filed and never sent on" "…and says its prep sends the child on"
prep --bead p
eq "$PREP_RC" 3 "the prep sends the child on instead of preparing the bead (exit 3)"
has "$PREP_OUT" "p's rework child $CHILD was filed and never sent on" "…and says so"
has "$(logged scripts)" "queue-priority settle $CHILD" "the child is settled at its priority"
has "$(logged gc)" "sling --rig rig-a rig-a/gc-toolkit.polecat $CHILD --on mol-polecat-work" "…then slung"
hasnt "$(logged gc)" "bd dep $CHILD --blocks" "…keeping the blocks edge it was filed with"
hasnt "$(logged gc)" "bd create" "no second child is filed"
[ ! -e "$HOME_DIR/worktrees/p" ] && rt_ok "the prep removes its tree" || rt_bad "the prep removes its tree"

echo "# a child left without its blocks edge is sent on by the next patrol, the edge written first"
fresh_patrol
branch_with polecat/e e.txt >/dev/null
work e polecat/e '{"merge_result":"pull_request_head_changed"}'
put '{"id":"e-kid","title":"Rework","status":"open","assignee":"","issue_type":"task","notes":"","created_at":"2026-11-12T01:00:00Z","metadata":{"task_kind":"rework","anchor_bead":"e","branch":"polecat/e","rejection_reason":"lint fails"}}'
find_work
eq "$FW_RC $NAMED" "0 e" "find-work takes the bead whose branch only its unsent child is on"
prep --bead e
eq "$PREP_RC" 3 "the prep sends the child on (exit 3)"
has "$(logged gc)" "bd dep e-kid --blocks e" "the child gets its blocks edge"
has "$(logged scripts)" "queue-priority settle e-kid" "…is settled"
has "$(logged gc)" "rig-a/gc-toolkit.polecat e-kid --on mol-polecat-work" "…and is slung"

echo "# a create the store refuses files nothing, and the bead is taken as it was"
fresh_patrol
branch_with polecat/f f.txt >/dev/null
work f polecat/f '{"merge_result":"pull_request_head_changed"}'
prepared f polecat/f
STUB_BD_CREATE_FAIL=1 run --bead f --reason "lint fails"
eq "$RC" 1 "a refused create stops the requeue (exit 1)"
has "$OUT" "so none was filed" "it says no child was filed"
eq "$(kid)$(cat "$STUB_HOLDS")" "" "no child and no edge stand"
find_work
eq "$FW_RC $NAMED" "0 f" "the next patrol takes the bead again"

echo "# a create whose reply was lost is found among the bead's children and sent on"
fresh
branch_with polecat/l l.txt >/dev/null
work l polecat/l '{"merge_result":"pull_request_head_changed"}'
prepared l polecat/l
STUB_CREATE_REPLY_LOST=1 run --bead l --reason "lint fails"
eq "$RC" 0 "the requeue exits 0"
CHILD=$(kid)
has "$OUT" "$CHILD is the unsent rework child it filed" "it finds the child the create filed"
has "$(logged scripts)" "queue-priority settle $CHILD" "…settles it"
has "$(logged gc)" "rig-a/gc-toolkit.polecat $CHILD --on mol-polecat-work" "…and slings it"

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
has "$(logged gc)" "bd dep u-kid --blocks u" "an unsent child that lacks its blocks edge gets it"
has "$(logged scripts)" "queue-priority settle u-kid" "…is settled at its priority"
has "$(logged gc)" "rig-a/gc-toolkit.polecat u-kid --on mol-polecat-work" "…and is slung"
hasnt "$(logged gc)" "bd create" "…and no second child is filed"
fresh
branch_with polecat/u u.txt >/dev/null
work u polecat/u '{"merge_result":"pull_request_head_changed"}'
put '{"id":"u-kid","title":"Rework","status":"open","assignee":"","issue_type":"task","notes":"","metadata":{"task_kind":"rework","anchor_bead":"u","branch":"polecat/u"}}'
echo "u u-kid" > "$STUB_HOLDS"
prepared u polecat/u
run --bead u --reason "lint fails"
hasnt "$(logged gc)" "bd dep u-kid --blocks" "an unsent child that carries its blocks edge gets no second one"
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

echo "# an unsent child that cannot be sent on asks a person, and the bead waits for the gate"
fresh_patrol
branch_with polecat/u u.txt >/dev/null
work u polecat/u '{"merge_result":"pull_request_head_changed"}'
put '{"id":"u-kid","title":"Rework","status":"open","assignee":"","issue_type":"task","notes":"","metadata":{"task_kind":"rework","anchor_bead":"u","branch":"polecat/u"}}'
echo "u u-kid" > "$STUB_HOLDS"
prepared u polecat/u
printf '#!/usr/bin/env bash\necho "queue-priority $*" >> "$LOGS/scripts.log"\necho "queue-priority: the priority lock is held by pid 4242" >&2\nexit 1\n' > "$TMP/qp-refuses"
chmod +x "$TMP/qp-refuses"
GC_QUEUE_PRIORITY_TOOL="$TMP/qp-refuses" run --bead u --reason "lint fails"
eq "$RC" 1 "an unsent child that does not settle stops the requeue (exit 1)"
has "$(logged scripts)" "human-gate --subject u-kid --key refinery-requeue-failed" "a gate on the child asks a person"
has "$(logged scripts)" "did not settle at its priority (queue-priority: the priority lock is held by pid 4242)" "…saying what refused the settle"
has "$(logged scripts)" "queue-priority.sh settle u-kid, then gc sling rig-a/gc-toolkit.polecat u-kid --on mol-polecat-work" "…naming how to send it on by hand"
hasnt "$(logged gc)" "sling" "the child is not slung"
echo "u-kid gate-u" >> "$STUB_HOLDS"
find_work
eq "$FW_RC" 3 "while the gate holds the child, find-work leaves the bead"
has "$FW_ERR" "u waits on u-kid" "…and names the child it waits on"
grep -v '^u-kid gate-u$' "$STUB_HOLDS" > "$STUB_HOLDS.n" && mv "$STUB_HOLDS.n" "$STUB_HOLDS"
find_work
eq "$FW_RC $NAMED" "0 u" "once the gate clears, find-work takes the bead again"
fresh
branch_with polecat/u u.txt >/dev/null
work u polecat/u '{"merge_result":"pull_request_head_changed"}'
put '{"id":"u-kid","title":"Rework","status":"open","assignee":"","issue_type":"task","notes":"","metadata":{"task_kind":"rework","anchor_bead":"u","branch":"polecat/u"}}'
prepared u polecat/u
STUB_DEP_RC=1 run --bead u --reason "lint fails"
eq "$RC" 1 "an unsent child whose blocks edge does not land stops the requeue (exit 1)"
has "$(logged scripts)" "human-gate --subject u-kid --key refinery-requeue-failed" "…and a gate on the child asks a person"
hasnt "$(logged scripts)" "queue-priority settle" "…before any settle"
hasnt "$(logged gc)" "sling" "…and it is not slung"

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
