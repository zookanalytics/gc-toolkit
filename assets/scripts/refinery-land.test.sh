#!/usr/bin/env bash
# Hermetic test for refinery-land.sh, the refinery patrol's merge-push step.
# Runs the real script with the real direct-merge-push.sh, refinery-publish.sh
# and branch-push.sh against real git repositories, with a fake gc, gh and gctk
# and a stub lifecycle.sh that logs each transition (refinery-test-lib.sh).
# Proves:
#   - a direct bead onto an integration branch lands by a fast-forward push and
#     is recorded through direct-merge-push.sh; one a person handed back from a
#     park, blocked or refused_false_completion, first leaves it for
#     unanchored, and one that does not leave it lands nothing, while a value
#     the pending record writes goes through no transition there;
#   - once a direct landing is recorded, the PR open from its target that a
#     bead holds at pull_request is composed at the target's new tip and edited
#     to name the bead that landed, an edit that does not take, or a PR that
#     does not read, leaving the landing's exit 0, and an owner the pending
#     record holds is left to the landing order;
#   - a direct bead bound for the default branch takes mr;
#   - on a rig whose pending_through_merge is "true", mr publishes the PR and
#     records it pending;
#   - on any other rig, mr pushes the head under the lease and parks the bead
#     for the merge cadence: at pre_open_gate, or at pull_request when it
#     records an open PR, whose title and body it brings current first, with
#     merged_target and the check set, an empty check set recovering the
#     declared default; a bead a person handed back from a park first leaves
#     it; a PR whose body is current and whose title differs only in its
#     spacing is not edited;
#   - a rework child handed back on the old path brings its anchor's PR title
#     and body current, pushes, notes the anchor and closes;
#   - the body brought current names the gates of the check set the PR waits
#     on, resolved at the prepared head: the one the landing stamps on a bead
#     that owns its PR, else the anchor's;
#   - on the old path, a title and body that do not reach the PR, its own or
#     its anchor's, gates that do not resolve, or a view of a recorded PR that
#     does not answer, stop the landing with nothing pushed, while a recorded
#     PR GitHub reads as closed, or says the repository does not have, is no
#     PR to bring current, so the landing goes on;
#   - a bead that owns its PR lands as itself on the old path, though a parked
#     rework child of it waits on its branch with a merge_result of its own;
#   - a convoy's rebuild child lands on its convoy while the convoy is open on
#     its branch in a queue, the refinery's or the merge cadence's, and the
#     convoy stays where it was; when the convoy is closed or open on another
#     branch, the store holds no bead by its id, or the convoy is open on its
#     branch with no merge_result and assigned to nobody, the child is parked
#     behind refinery-rebuild-convoy-not-open, with nothing pushed, edited or
#     transitioned, and a second pass over the parked child parks it again; a
#     named bead that does not read, or a gate that does not file, writes
#     nothing; and a rework naming a closed bead that is no convoy lands as
#     itself;
#   - a branch with no change parks the bead behind refinery-false-completion,
#     unless the target carries the bead's stamped direct landing, which is
#     recorded, and a gate that is not filed parks nothing;
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
  rt_init refinery-land.sh refinery-publish.sh direct-merge-push.sh rig-root.sh review-checks.sh
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
hasnt "$(logged gctk)" "pr compose" "with no PR open from the target, nothing is composed"

# direct_onto <bead> <metadata> — a direct bead whose branch, cut from
# integration/e, carries a change, prepared and current with integration/e;
# HEAD_D is its prepared head.
direct_onto() {
  integration
  branch_with "polecat/$1" "$1.txt" integration/e >/dev/null
  work "$1" "polecat/$1" "$(jq -nc --argjson m "$2" '{target: "integration/e", merge_strategy: "direct"} + $m')"
  prepared "$1" "polecat/$1"
  git -C "$HOME_DIR" fetch -q origin "+refs/heads/integration/e:refs/remotes/origin/integration/e"
  git -C "$HOME_DIR/worktrees/$1" merge -q --no-edit refs/remotes/origin/integration/e >/dev/null 2>&1
  HEAD_D=$(git -C "$HOME_DIR/worktrees/$1" rev-parse HEAD)
}
# before <log> <first> <second>: <first> is logged ahead of <second>, and both are.
before() {
  local a b
  a=$(grep -n -F -- "$2" "$LOGS/$1.log" | head -n 1 | cut -d: -f1)
  b=$(grep -n -F -- "$3" "$LOGS/$1.log" | head -n 1 | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

echo "# a direct bead handed back from a park leaves it before its landing is recorded"
for park in blocked refused_false_completion; do
  fresh
  direct_onto d "{\"merge_result\":\"$park\",\"rejection_reason\":\"parked\"}"
  run --bead d
  eq "$RC" 0 "$park: the landing exits 0"
  eq "$(tip integration/e)" "$HEAD_D" "$park: the target holds the prepared head"
  if before scripts "lifecycle transition d --to unanchored --expect $park --unset rejection_reason" \
       "lifecycle transition d --to merged --close --set merged_sha=$HEAD_D --set merged_target=integration/e"; then
    rt_ok "$park: the bead leaves it for unanchored, then closes merged at its merged_sha"
  else
    rt_bad "$park: the bead leaves it for unanchored, then closes merged at its merged_sha" "$(logged scripts)"
  fi
done
fresh
integration
STAMP=$(branch_with polecat/s s.txt integration/e)
git -C "$SEED" checkout -q integration/e && git -C "$SEED" merge -q --ff-only "$STAMP" && git -C "$SEED" push -q origin integration/e
work s polecat/s "{\"target\":\"integration/e\",\"merge_strategy\":\"direct\",\"direct_landing_sha\":\"$STAMP\",\"merge_result\":\"blocked\"}"
prepared s polecat/s
run --bead s
eq "$RC" 0 "a landing pushed under a park but never recorded is recorded"
if before scripts "lifecycle transition s --to unanchored --expect blocked" "lifecycle transition s --to merged --close --set merged_sha=$STAMP"; then
  rt_ok "…at its stamp, once the bead has left blocked"
else
  rt_bad "…at its stamp, once the bead has left blocked" "$(logged scripts)"
fi
fresh
direct_onto d '{"merge_result":"blocked"}'
BEFORE=$(git -C "$SEED" rev-parse origin/integration/e)
STUB_LIFECYCLE_RC=1 run --bead d
eq "$RC" 1 "a park the bead does not leave stops (exit 1)"
eq "$(tip integration/e)" "$BEFORE" "…with nothing pushed onto the target"
hasnt "$(logged scripts)" "--to merged" "…and nothing recorded"
fresh
direct_onto d '{"merge_result":"pull_request_pending"}'
run --bead d
hasnt "$(logged scripts)" "--to unanchored" "a value the pending record writes is not sent through lifecycle.sh"

echo "# a direct landing onto a branch whose PR a bead holds at pull_request brings that PR current"
# owner_of_e <merge_result> — an, holding PR #66 from integration/e into main at
# <merge_result>, with a published body that names nothing riding it.
owner_of_e() {
  put "$(jq -nc --arg r "$1" '{id: "an", title: "Anchor", status: "open", assignee: "", issue_type: "task",
    created_at: "2026-11-11T00:00:00Z", notes: "", metadata: {branch: "integration/e", target: "main", merge_result: $r,
    pr_url: "https://github.com/zook/rig/pull/66", pr_number: "66", merged_target: "main", check_set: "lane-c"}}')"
  pr 66 integration/e gc-city-bot OPEN main "<!-- gc:pr-summary -->stale<!-- /gc:pr-summary -->"
}
fresh
direct_onto d '{}'
owner_of_e pull_request
run --bead d
eq "$RC" 0 "the landing exits 0"
has "$(logged scripts)" "lifecycle transition d --to merged --close --set merged_sha=$HEAD_D --set merged_target=integration/e" "the landing is recorded"
has "$(logged gctk)" "pr compose an --head $HEAD_D --target main --gates lane-c	pre-open --body-file" "the owner's PR is composed at the target's new tip, naming its base and the gates of its check set"
has "$(cat "$GH_DIR/edit_66.md" 2>/dev/null)" "riding: d" "…and the body its edit gives the PR names the bead that landed"
fresh
direct_onto d '{}'
owner_of_e pull_request
STUB_EDIT_RC=1 run --bead d
eq "$RC" 0 "an edit that does not take leaves the landing's exit 0"
has "$(logged scripts)" "lifecycle transition d --to merged --close" "…with the bead recorded merged and closed"
has "$OUT" "PR #66, open from integration/e, does not name d, which landed on it; the landing stands" "…and a line saying the PR does not name it"
fresh
direct_onto d '{}'
owner_of_e pull_request
STUB_VIEW_FAIL=1 run --bead d
eq "$RC" 0 "a PR the owner records that does not read leaves the landing's exit 0"
has "$(logged scripts)" "lifecycle transition d --to merged --close" "…with the bead recorded merged and closed"
has "$OUT" "PR https://github.com/zook/rig/pull/66, which an records, did not read, so it was not brought current with d, which landed on integration/e; the landing stands" "…and a line saying the PR did not read"
fresh
direct_onto d '{}'
owner_of_e pull_request_pending
run --bead d
eq "$RC" 0 "a landing onto a branch whose PR the pending record holds exits 0"
hasnt "$(logged gctk)" "pr compose" "…and composes nothing: the landing order hands that owner back to the refinery"

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
hasnt "$(logged gh)" "pr edit" "with no PR open, nothing is edited"
fresh
branch_with polecat/r r.txt >/dev/null
work r polecat/r '{"existing_pr":"https://github.com/zook/rig/pull/61"}'
prepared r polecat/r
HEAD_R=$(git -C "$HOME_DIR/worktrees/r" rev-parse HEAD)
pr 61 polecat/r someone
rt_vars check_set=""
run --bead r
eq "$RC" 0 "the landing exits 0"
has "$(logged gh)" "pr edit 61 --repo zook/rig --title feat: r (r) --body-file" "its PR's title and body are brought current"
has "$(logged gctk)" "pr compose r --head $HEAD_R --target main --gates lane-a	pre-open
lane-b	pre-open --body-file" "…its body naming the gates of the check set it is stamped with, resolved at the head"
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
fresh
branch_with polecat/q q.txt >/dev/null
work q polecat/q '{"existing_pr":"https://github.com/zook/rig/pull/67"}'
prepared q polecat/q
HEAD_Q=$(git -C "$HOME_DIR/worktrees/q" rev-parse HEAD)
pr 67 polecat/q someone OPEN main "<!-- gc:pr-summary -->composed for q at $HEAD_Q<!-- /gc:pr-summary -->"
jq '.title = "feat:  q (q)"' "$GH_DIR/view_67.json" > "$GH_DIR/view_67.json.t" && mv "$GH_DIR/view_67.json.t" "$GH_DIR/view_67.json"
run --bead q
eq "$RC" 0 "the landing exits 0"
hasnt "$(logged gh)" "pr edit 67" "a PR whose body is current and whose title differs only in spacing is not edited"

echo "# a rework child handed back on the old path lands on its anchor's branch"
fresh
branch_with polecat/an an.txt >/dev/null
put '{"id":"an","title":"Anchor","status":"open","assignee":"","issue_type":"task","created_at":"2026-11-11T00:00:00Z","notes":"","metadata":{"branch":"polecat/an","target":"main","merge_result":"pull_request","pr_url":"https://github.com/zook/rig/pull/62","pr_number":"62","check_set":"lane-c"}}'
work ch polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
prepared ch polecat/an
HEAD_C=$(git -C "$HOME_DIR/worktrees/ch" rev-parse HEAD)
pr 62 polecat/an gc-city-bot OPEN main "<!-- gc:pr-summary -->stale<!-- /gc:pr-summary -->"
run --bead ch
eq "$RC" 0 "the hand-back exits 0"
eq "$(tip polecat/an)" "$HEAD_C" "the head is on the anchor's branch"
has "$(logged gh)" "pr edit 62 --repo zook/rig --title feat: an (an) --body-file" "the anchor's PR title and body are brought current"
has "$(logged gctk)" "pr compose an --head $HEAD_C --target main --gates lane-c	pre-open --body-file" "…its body naming the base and the gates of the anchor's check set"
has "$(bnotes an)" "Rework ch landed on polecat/an at $HEAD_C" "the anchor notes the landing"
eq "$(bstatus ch) $(meta ch gc.work_outcome)" "closed shipped" "the child closes with its work record"
eq "$(meta an merge_result)" "pull_request" "the anchor keeps its record"
fresh
branch_with polecat/an an.txt >/dev/null
put '{"id":"an","title":"Anchor","status":"open","assignee":"","issue_type":"task","created_at":"2026-11-11T00:00:00Z","notes":"","metadata":{"branch":"polecat/an","target":"main","merge_result":"pull_request","pr_url":"https://github.com/zook/rig/pull/62","pr_number":"62"}}'
work ch polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
prepared ch polecat/an
HEAD_C=$(git -C "$HOME_DIR/worktrees/ch" rev-parse HEAD)
pr 62 polecat/an gc-city-bot CLOSED
run --bead ch
eq "$RC" 0 "a hand-back whose anchor's recorded PR GitHub reads as closed exits 0"
eq "$(tip polecat/an)" "$HEAD_C" "…the head on the anchor's branch"
hasnt "$(logged gh)" "pr edit" "…with no open PR to bring current"
eq "$(bstatus ch)" "closed" "…and the child closed"

echo "# on the old path, a title and body that do not reach the PR, or gates that do not resolve, stop the landing with nothing pushed"
fresh
BEFORE=$(branch_with polecat/st st.txt)
main_with st-later.txt >/dev/null
work st polecat/st '{"existing_pr":"https://github.com/zook/rig/pull/64"}'
prepared st polecat/st
pr 64 polecat/st gc-city-bot
STUB_EDIT_RC=1 run --bead st
eq "$RC" 1 "an edit of the bead's own PR that does not take stops (exit 1)"
eq "$(tip polecat/st)" "$BEFORE" "…with nothing pushed"
hasnt "$(logged scripts)" "lifecycle" "…and no transition written"
fresh
BEFORE=$(branch_with polecat/an an.txt)
main_with an-later.txt >/dev/null
put '{"id":"an","title":"Anchor","status":"open","assignee":"","issue_type":"task","created_at":"2026-11-11T00:00:00Z","notes":"","metadata":{"branch":"polecat/an","target":"main","merge_result":"pull_request","pr_url":"https://github.com/zook/rig/pull/62","pr_number":"62"}}'
work ch polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
prepared ch polecat/an
pr 62 polecat/an gc-city-bot
STUB_EDIT_RC=1 run --bead ch
eq "$RC" 1 "an edit of the anchor's PR that does not take stops (exit 1)"
eq "$(tip polecat/an)" "$BEFORE" "…with nothing pushed onto the anchor's branch"
eq "$(bstatus ch)" "open" "…and the child stays open for the next pass"
fresh
BEFORE=$(branch_with polecat/gr gr.txt)
main_with gr-later.txt >/dev/null
work gr polecat/gr '{"existing_pr":"https://github.com/zook/rig/pull/65"}'
prepared gr polecat/gr
pr 65 polecat/gr gc-city-bot
printf '[checks.lane-a]\npurpose = "a"\nphase = "someday"\n' > "$TMP/bad-index.toml"
GC_REVIEW_CHECKS_INDEX="$TMP/bad-index.toml" run --bead gr
eq "$RC" 1 "gates that do not resolve at the head stop (exit 1)"
has "$OUT" "the gates of check set 'lane-a,lane-b' did not resolve at" "…saying which check set did not resolve"
eq "$(tip polecat/gr)" "$BEFORE" "…with nothing pushed"
hasnt "$(logged gctk)" "pr compose" "…nothing composed"
hasnt "$(logged gh)" "pr edit" "…the PR not edited"
hasnt "$(logged scripts)" "lifecycle" "…and no transition written"
fresh
BEFORE=$(branch_with polecat/vf vf.txt)
main_with vf-later.txt >/dev/null
work vf polecat/vf '{"existing_pr":"https://github.com/zook/rig/pull/69"}'
prepared vf polecat/vf
pr 69 polecat/vf gc-city-bot
STUB_VIEW_FAIL=1 run --bead vf
eq "$RC" 1 "a PR the bead records that does not read stops (exit 1)"
has "$OUT" "PR https://github.com/zook/rig/pull/69, which vf records, did not read" "…saying which PR did not read"
eq "$(tip polecat/vf)" "$BEFORE" "…with nothing pushed"
hasnt "$(logged gctk)" "pr compose" "…nothing composed"
hasnt "$(logged scripts)" "lifecycle" "…and no transition written"
fresh
BEFORE=$(branch_with polecat/an an.txt)
main_with an-later.txt >/dev/null
put '{"id":"an","title":"Anchor","status":"open","assignee":"","issue_type":"task","created_at":"2026-11-11T00:00:00Z","notes":"","metadata":{"branch":"polecat/an","target":"main","merge_result":"pull_request","pr_url":"https://github.com/zook/rig/pull/62","pr_number":"62"}}'
work ch polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
prepared ch polecat/an
pr 62 polecat/an gc-city-bot
STUB_VIEW_FAIL=1 run --bead ch
eq "$RC" 1 "a PR the anchor records that does not read stops the hand-back (exit 1)"
has "$OUT" "PR https://github.com/zook/rig/pull/62, which an records, did not read" "…saying which PR did not read"
eq "$(tip polecat/an)" "$BEFORE" "…with nothing pushed onto the anchor's branch"
hasnt "$(logged gctk)" "pr compose" "…nothing composed"
eq "$(bstatus ch)" "open" "…and the child stays open for the next pass"
fresh
branch_with polecat/vg vg.txt >/dev/null
work vg polecat/vg '{"existing_pr":"https://github.com/zook/rig/pull/71"}'
prepared vg polecat/vg
HEAD_V=$(git -C "$HOME_DIR/worktrees/vg" rev-parse HEAD)
run --bead vg
eq "$RC" 0 "a PR the bead records that GitHub says it does not have is no PR open on the branch, so the landing exits 0"
eq "$(tip polecat/vg)" "$HEAD_V" "…the head is pushed"
has "$(logged scripts)" "lifecycle transition vg --to pre_open_gate" "…and the bead waits at pre_open_gate"
fresh
branch_with polecat/an an.txt >/dev/null
put '{"id":"an","title":"Anchor","status":"open","assignee":"","issue_type":"task","created_at":"2026-11-11T00:00:00Z","notes":"","metadata":{"branch":"polecat/an","target":"main","merge_result":"pull_request","pr_url":"https://github.com/zook/rig/pull/72","pr_number":"72"}}'
work ch polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
prepared ch polecat/an
HEAD_C=$(git -C "$HOME_DIR/worktrees/ch" rev-parse HEAD)
run --bead ch
eq "$RC" 0 "a hand-back whose anchor records a PR GitHub says it does not have lands (exit 0)"
eq "$(tip polecat/an)" "$HEAD_C" "…the head on the anchor's branch"
eq "$(bstatus ch)" "closed" "…and the child closed"

echo "# a bead that owns its PR lands as itself on the old path, though a parked rework child waits on its branch"
fresh
branch_with polecat/bp bp.txt >/dev/null
work bp polecat/bp '{"merge_result":"blocked","existing_pr":"https://github.com/zook/rig/pull/63"}'
work kid polecat/bp '{"task_kind":"rework","anchor_bead":"bp","merge_result":"blocked","blocked_reason":"parked behind a gate"}'
prepared bp polecat/bp
pr 63 polecat/bp gc-city-bot
run --bead bp
eq "$RC" 0 "the landing exits 0"
has "$(logged scripts)" "lifecycle transition bp --to pull_request --assignee  --route  --set pr_url=https://github.com/zook/rig/pull/63" "the bead waits at pull_request on its own PR"
eq "$(bstatus bp)" "open" "it is not closed as a landed rework"
eq "$(bstatus kid) $(meta kid merge_result)" "open blocked" "the parked rework child is left as it was"

# rebuild <status> <branch> [<type>] [<child metadata>] [<convoy assignee>]
# [<convoy metadata>] — a convoy (or a bead of <type>) with status <status> on
# <branch>, assigned to <convoy assignee>, by default the refinery, as the
# requeue leaves a convoy it rebuilds, whose open PR #70 is from integration/cv,
# and its rebuild child rb on integration/cv, handed back and prepared over a
# main that moved, so its prepared head is new. The convoy carries no
# merge_result unless <convoy metadata> gives it one, so an empty
# <convoy assignee> alone leaves it in neither queue. An empty <status> leaves
# the named bead out of the store. BEFORE is the branch's tip before the
# landing.
rebuild() {
  fresh
  branch_with integration/cv cv.txt >/dev/null
  main_with later.txt >/dev/null
  [ -z "$1" ] || put "$(jq -nc --arg s "$1" --arg b "$2" --arg t "${3:-convoy}" --arg a "${5-$GC_AGENT}" --argjson m "${6:-{\}}" '{id: "cv", title: "Convoy", status: $s, assignee: $a, issue_type: $t,
    created_at: "2026-11-11T00:00:00Z", notes: "", metadata: ({branch: $b, target: "main", pr_url: "https://github.com/zook/rig/pull/70", pr_number: "70"} + $m)}')"
  work rb integration/cv "$(jq -nc --argjson m "${4:-{\}}" '{task_kind: "rework", anchor_bead: "cv", merge_strategy: "mr", existing_pr: "https://github.com/zook/rig/pull/70"} + $m')"
  prepared rb integration/cv
  pr 70 integration/cv gc-city-bot
  BEFORE=$(tip integration/cv)
}
# parked_rebuild <case> — rb is parked behind refinery-rebuild-convoy-not-open,
# with nothing pushed, transitioned or closed.
parked_rebuild() {
  eq "$RC" 4 "$1: the landing parks (exit 4)"
  has "$(logged scripts)" "human-gate --subject rb --key refinery-rebuild-convoy-not-open" "$1: the gate is keyed refinery-rebuild-convoy-not-open"
  eq "$(bstatus rb) $(meta rb merge_result) $(bassignee rb)" "open blocked $GC_AGENT" "$1: the child records blocked and stays with the refinery"
  eq "$(tip integration/cv)" "$BEFORE" "$1: nothing is pushed"
  hasnt "$(logged scripts)" "lifecycle" "$1: no transition is written"
  hasnt "$(logged gh)" "pr edit" "$1: the PR is not edited"
}

echo "# a convoy's rebuild child lands on its convoy while the convoy is open on its branch in a queue"
rebuild open integration/cv
HEAD_RB=$(git -C "$HOME_DIR/worktrees/rb" rev-parse HEAD)
run --bead rb
eq "$RC" 0 "the hand-back exits 0"
eq "$(tip integration/cv)" "$HEAD_RB" "the head is on the convoy's branch"
has "$(bnotes cv)" "Rework rb landed on integration/cv at $HEAD_RB" "the convoy notes the landing"
eq "$(bstatus rb)" "closed" "the child closes"
hasnt "$(logged scripts)" "human-gate" "no gate is filed"
eq "$(bstatus cv) $(bassignee cv)" "open $GC_AGENT" "the convoy stays open and the refinery's, which takes it again once the child closes"
rebuild open integration/cv convoy '{}' "" '{"merge_result":"pull_request"}'
HEAD_RB=$(git -C "$HOME_DIR/worktrees/rb" rev-parse HEAD)
run --bead rb
eq "$RC" 0 "a convoy the merge cadence holds at pull_request: the hand-back exits 0"
eq "$(tip integration/cv)" "$HEAD_RB" "…with the head on the convoy's branch"
eq "$(bstatus rb)" "closed" "…and the child closed"
eq "$(meta cv merge_result) $(bassignee cv)" "pull_request " "…and the convoy left at pull_request for the cadence"

echo "# a rebuild child whose convoy cannot carry its PR is parked, not landed as its own"
rebuild closed integration/cv
run --bead rb
parked_rebuild "a closed convoy"
has "$(logged scripts)" "but cv is closed, so no bead on integration/cv can carry that PR" "a closed convoy: the gate says the convoy is closed"
has "$(logged scripts)" "make cv open with branch integration/cv, then clear this gate" "the gate asks for the convoy open on its branch to go on"
has "$(logged scripts)" "stand-down.sh rb --key refinery-rebuild-convoy-not-open" "…and names the stand-down that abandons the graduation"
rebuild open integration/other
run --bead rb
parked_rebuild "a convoy open on another branch"
has "$(logged scripts)" "but cv is open on integration/other" "a convoy open on another branch: the gate names that branch"
hasnt "$(bnotes cv)" "Rework rb landed" "…and the convoy is not noted as landed"
rebuild ""
run --bead rb
parked_rebuild "a named bead the store does not hold"
has "$(logged scripts)" "but the store holds no bead cv" "a named bead the store does not hold: the gate says so"
rebuild open integration/cv convoy '{}' ""
run --bead rb
parked_rebuild "a convoy open on its branch in neither queue"
has "$(logged scripts)" "but cv is open on integration/cv with no merge_result and assigned to nobody" "a convoy in neither queue: the gate says so"
has "$(logged scripts)" "put cv back in a merge queue by assigning it to the refinery (gc bd update cv --assignee=$GC_AGENT), then clear this gate" "…and names the assignment that goes on"
has "$(logged scripts)" "stand-down.sh rb --key refinery-rebuild-convoy-not-open" "…or the stand-down that abandons the graduation"
eq "$(bassignee cv)|$(meta cv merge_result)|$(bnotes cv)" "|<absent>|" "…and the convoy is left as it was"
rebuild closed integration/cv convoy '{"merge_result":"blocked","blocked_reason":"the rebuild of cv has no bead on integration/cv to carry its PR"}'
run --bead rb
parked_rebuild "a second pass over a parked child whose convoy is still closed"

echo "# a rebuild child whose named bead does not read, or whose gate does not file, writes nothing"
rebuild closed integration/cv
STUB_GC_ID_FAIL=1 run --bead rb
eq "$RC" 1 "an unreadable named bead stops (exit 1)"
eq "$(logged scripts)" "" "…with no gate, transition or landing written"
eq "$(meta rb merge_result)" "<absent>" "…and nothing recorded"
eq "$(tip integration/cv)" "$BEFORE" "…or pushed"
rebuild closed integration/cv
STUB_HUMAN_GATE_RC=1 run --bead rb
eq "$RC" 1 "a gate that does not file stops (exit 1)"
eq "$(meta rb merge_result)" "<absent>" "…and parks nothing"
eq "$(tip integration/cv)" "$BEFORE" "…and pushes nothing"
hasnt "$(logged scripts)" "lifecycle" "…and transitions nothing"

echo "# a rework naming a closed bead that is no convoy keeps today's path"
rebuild closed integration/cv task
HEAD_RB=$(git -C "$HOME_DIR/worktrees/rb" rev-parse HEAD)
run --bead rb
eq "$RC" 0 "the landing exits 0"
eq "$(tip integration/cv)" "$HEAD_RB" "the head is pushed"
has "$(logged scripts)" "lifecycle transition rb --to pull_request" "the child waits at pull_request on the PR it records"
hasnt "$(logged scripts)" "human-gate" "no gate is filed"

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
git -C "$SEED" fetch -q origin && git -C "$SEED" branch -f polecat/y origin/main && git -C "$SEED" push -q origin polecat/y
work y polecat/y
prepared y polecat/y
STUB_HUMAN_GATE_RC=1 run --bead y
eq "$RC" 1 "a refusal whose gate is not filed stops (exit 1)"
eq "$(meta y merge_result)" "<absent>" "…and parks nothing, so the bead stays with the refinery for the next patrol"
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
