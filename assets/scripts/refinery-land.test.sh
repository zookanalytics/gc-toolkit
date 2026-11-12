#!/usr/bin/env bash
# Hermetic test for refinery-land.sh, the refinery patrol's merge-push step.
# Runs the real script with the real direct-merge-push.sh, refinery-publish.sh
# and branch-push.sh against real git repositories, with a fake gc, gh and gctk
# and a stub lifecycle.sh that logs each transition (refinery-test-lib.sh).
# Proves:
#   - a direct bead onto an integration branch lands by a fast-forward push and
#     is recorded through direct-merge-push.sh;
#   - a direct bead bound for the default branch takes mr;
#   - on a rig whose pending_through_merge is "true", mr publishes the PR and
#     records it pending;
#   - on any other rig, mr pushes the head under the lease and parks the bead
#     for the merge cadence: at pre_open_gate, or at pull_request when it
#     records an open PR, with merged_target and the check set, an empty check
#     set recovering the declared default; a bead a person handed back from a
#     park first leaves it;
#   - a rework child handed back on the old path brings its anchor's PR title
#     and body current, pushes, notes the anchor and closes;
#   - a branch with no change parks the bead behind refinery-false-completion,
#     unless the target carries the bead's stamped direct landing, which is
#     recorded;
#   - an unsupported strategy parks the bead behind
#     refinery-unsupported-strategy;
#   - a target that moved after the prep lands nothing (exit 6);
#   - a bead whose branch the refinery's tree does not hold gets no write.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-land-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-land.sh refinery-publish.sh direct-merge-push.sh rig-root.sh
  export GC_RIG_ROOT="$RIG" DIRECT_MERGE_PUSH_BACKOFF=0
}
run() { OUT=$("$SUT/refinery-land.sh" "$@" 2>&1); RC=$?; }
integration() { branch_with integration/e e-base.txt >/dev/null; }

echo "# a direct bead onto an integration branch lands by a fast-forward push"
fresh
integration
branch_with polecat/d d.txt integration/e >/dev/null
work d polecat/d '{"target":"integration/e","merge_strategy":"direct"}'
prepared d polecat/d
git -C "$HOME_DIR" fetch -q origin "+refs/heads/integration/e:refs/remotes/origin/integration/e"
git -C "$HOME_DIR/worktrees/d" merge -q --no-edit refs/remotes/origin/integration/e >/dev/null 2>&1
HEAD_D=$(git -C "$HOME_DIR/worktrees/d" rev-parse HEAD)
run --bead d
eq "$RC" 0 "the landing exits 0"
eq "$(tip integration/e)" "$HEAD_D" "the target holds the prepared head"
has "$(logged scripts)" "lifecycle transition d --to merged --close --set merged_sha=$HEAD_D --set merged_target=integration/e" "the landing is recorded and the bead closed"
[ ! -e "$HOME_DIR/worktrees/d" ] && rt_ok "the tree is removed" || rt_bad "the tree is removed"
eq "$(tip polecat/d)" "<absent>" "delete_merged_branches deletes the branch once the landing is recorded"

echo "# a direct bead bound for the default branch takes mr"
fresh
branch_with polecat/m m.txt >/dev/null
work m polecat/m '{"merge_strategy":"direct"}'
prepared m polecat/m
HEAD_M=$(git -C "$HOME_DIR/worktrees/m" rev-parse HEAD)
run --bead m
eq "$RC" 0 "the landing exits 0"
[ "$(tip main)" != "$HEAD_M" ] && rt_ok "nothing is pushed onto the default branch" || rt_bad "nothing is pushed onto the default branch"
has "$(logged scripts)" "lifecycle transition m --to pre_open_gate" "the bead is parked for the cadence's PR"

echo "# on the new path, mr publishes the PR and records it pending"
fresh
rt_vars pending_through_merge=true
branch_with polecat/n n.txt >/dev/null
work n polecat/n
prepared n polecat/n
HEAD_N=$(git -C "$HOME_DIR/worktrees/n" rev-parse HEAD)
run --bead n
eq "$RC" 0 "the landing exits 0"
eq "$(meta n merge_result)" "pull_request_pending" "the bead records its PR as pending"
eq "$(tip polecat/n)" "$HEAD_N" "the prepared head is on its branch"
has "$(logged gh)" "pr create" "the PR opens"
hasnt "$(logged scripts)" "lifecycle" "the old path's transitions are not written"
[ ! -e "$HOME_DIR/worktrees/n" ] && rt_ok "the tree is removed" || rt_bad "the tree is removed"

echo "# on the old path, mr pushes the head and parks the bead for the cadence"
fresh
branch_with polecat/o o.txt >/dev/null
work o polecat/o
prepared o polecat/o
HEAD_O=$(git -C "$HOME_DIR/worktrees/o" rev-parse HEAD)
run --bead o
eq "$RC" 0 "the landing exits 0"
eq "$(tip polecat/o)" "$HEAD_O" "the head is pushed"
has "$(logged scripts)" "lifecycle transition o --to pre_open_gate --assignee  --route  --set merged_target=main --set check_set=lane-a,lane-b --unset rejection_reason" "the bead waits at pre_open_gate with its target and check set"
hasnt "$(logged gh)" "pr create" "the cadence, not the refinery, opens its PR"
fresh
branch_with polecat/r r.txt >/dev/null
work r polecat/r '{"existing_pr":"https://github.com/zook/rig/pull/61"}'
prepared r polecat/r
pr 61 polecat/r someone
rt_vars check_set=""
run --bead r
eq "$RC" 0 "the landing exits 0"
has "$(logged scripts)" "lifecycle transition r --to pull_request --assignee  --route  --set pr_url=https://github.com/zook/rig/pull/61 --set pr_number=61 --set merged_target=main --set check_set=lane-a,lane-b" "a bead that records an open PR waits at pull_request on it, an empty check set recovering the default"
fresh
branch_with polecat/b b.txt >/dev/null
work b polecat/b '{"merge_result":"blocked"}'
prepared b polecat/b
rt_vars check_set=none
run --bead b
eq "$RC" 0 "the landing exits 0"
has "$(logged scripts)" "lifecycle transition b --to unanchored --expect blocked" "a bead handed back from a park leaves it first"
has "$(logged scripts)" "--set check_set=none" "a none check set is stamped as none"

echo "# a rework child handed back on the old path lands on its anchor's branch"
fresh
branch_with polecat/an an.txt >/dev/null
put '{"id":"an","title":"Anchor","status":"open","assignee":"","issue_type":"task","created_at":"2026-11-11T00:00:00Z","notes":"","metadata":{"branch":"polecat/an","target":"main","merge_result":"pull_request","pr_url":"https://github.com/zook/rig/pull/62","pr_number":"62"}}'
work ch polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
prepared ch polecat/an
HEAD_C=$(git -C "$HOME_DIR/worktrees/ch" rev-parse HEAD)
pr 62 polecat/an gc-city-bot OPEN main "<!-- gc:pr-summary -->stale<!-- /gc:pr-summary -->"
run --bead ch
eq "$RC" 0 "the hand-back exits 0"
eq "$(tip polecat/an)" "$HEAD_C" "the head is on the anchor's branch"
has "$(logged gh)" "pr edit 62 --repo zook/rig --title feat: an (an) --body-file" "the anchor's PR title and body are brought current"
has "$(bnotes an)" "Rework ch landed on polecat/an at $HEAD_C" "the anchor notes the landing"
eq "$(bstatus ch) $(meta ch gc.work_outcome)" "closed shipped" "the child closes with its work record"
eq "$(meta an merge_result)" "pull_request" "the anchor keeps its record"

echo "# a branch with no change parks the bead, unless the target carries its stamped landing"
fresh
git -C "$SEED" fetch -q origin && git -C "$SEED" branch -f polecat/z origin/main && git -C "$SEED" push -q origin polecat/z
work z polecat/z
prepared z polecat/z
run --bead z
eq "$RC" 4 "the landing parks (exit 4)"
has "$(logged scripts)" "human-gate --subject z --key refinery-false-completion" "the gate is keyed refinery-false-completion"
eq "$(meta z merge_result)" "refused_false_completion" "the bead records refused_false_completion"
eq "$(bassignee z)" "$GC_AGENT" "…and stays with the refinery, held by its gate"
fresh
integration
STAMP=$(branch_with polecat/s s.txt integration/e)
git -C "$SEED" checkout -q integration/e && git -C "$SEED" merge -q --ff-only "$STAMP" && git -C "$SEED" push -q origin integration/e
work s polecat/s "{\"target\":\"integration/e\",\"merge_strategy\":\"direct\",\"direct_landing_sha\":\"$STAMP\"}"
prepared s polecat/s
run --bead s
eq "$RC" 0 "a stamped landing the target carries is recorded"
has "$(logged scripts)" "lifecycle transition s --to merged --close --set merged_sha=$STAMP" "…at the stamped commit"

echo "# an unsupported strategy parks the bead"
fresh
integration
branch_with polecat/l l.txt integration/e >/dev/null
work l polecat/l '{"target":"integration/e","merge_strategy":"local"}'
prepared l polecat/l
run --bead l
eq "$RC" 4 "the landing parks (exit 4)"
has "$(logged scripts)" "human-gate --subject l --key refinery-unsupported-strategy" "the gate is keyed refinery-unsupported-strategy"

echo "# a target that moved after the prep lands nothing"
fresh
integration
branch_with polecat/t t.txt integration/e >/dev/null
work t polecat/t '{"target":"integration/e","merge_strategy":"direct"}'
prepared t polecat/t
git -C "$HOME_DIR" fetch -q origin "+refs/heads/integration/e:refs/remotes/origin/integration/e"
git -C "$HOME_DIR/worktrees/t" merge -q --no-edit refs/remotes/origin/integration/e >/dev/null 2>&1
MOVED=$(branch_with integration/e later.txt integration/e)
run --bead t
eq "$RC" 6 "the landing says the target moved (exit 6)"
has "$OUT" "the next pass prepares it again" "it says the next pass prepares it again"
eq "$(tip integration/e)" "$MOVED" "the target keeps what moved it"
hasnt "$(logged scripts)" "--to merged" "nothing is recorded"

echo "# a bead whose branch the refinery's tree does not hold gets no write"
fresh
branch_with polecat/p p.txt >/dev/null
branch_with polecat/q q.txt >/dev/null
work p polecat/p
work q polecat/q
prepared q polecat/q
run --bead p
eq "$RC" 1 "a bead this iteration did not prepare is refused"
eq "$(logged scripts)" "" "no gate, transition or landing is written"
eq "$(tip polecat/p)" "$(git -C "$SEED" rev-parse polecat/p)" "nothing is pushed"

echo
echo "refinery-land: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
