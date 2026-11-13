#!/usr/bin/env bash
# Hermetic test for refinery-publish.sh, the refinery's mr step on the new
# path. Runs the real script against real git repositories (refinery-test-lib.sh)
# with a fake gc, gh and gctk. Proves:
#   - with no PR open, the head is pushed under the lease and the PR opens as a
#     draft with the composed title and body, then is recorded pending;
#   - a PR open on the branch that the city's account opened and the bead never
#     recorded is adopted: its title and body are edited, the head is pushed,
#     and it is recorded, with no second PR;
#   - a half-written record (the marker and existing_pr, no record) is taken
#     again and recorded on the PR existing_pr names;
#   - a PR another account opened, found on the branch or named by an old-path
#     record, parks the bead behind refinery-pr-not-city-opened, with nothing
#     edited, pushed or opened;
#   - a recorded PR that is closed parks the bead behind
#     refinery-invalid-existing-pr;
#   - an edit that does not take pushes nothing, so the head never moves under
#     a stale body;
#   - a branch someone pushed to after the prep is refused, never overwritten,
#     and nothing is opened or recorded;
#   - a bead closed or released before its record keeps that state, and the PR
#     is named in a note on it;
#   - a rework child handed back records the PR on its anchor and closes;
#   - a bead that owns its PR records it on itself, though a parked rework
#     child of it waits on its branch with a merge_result of its own;
#   - a convoy's rebuild child records the PR on its convoy while the convoy is
#     open on its branch and the refinery's; a convoy the merge cadence holds
#     at pull_request refuses the record, as `gctk pr record` refuses any owner
#     that is not the refinery's, so its notes name the PR and the child
#     closes; when the convoy is closed or open on another branch, the store
#     holds no bead by its id, or the convoy is open on its branch with no
#     merge_result and assigned to nobody, the child is parked behind
#     refinery-rebuild-convoy-not-open before any PR is read, pushed onto,
#     opened or recorded, and a second pass over the parked child parks it
#     again; a named bead that does not read, or a gate that does not file,
#     writes nothing; and a rework naming a closed bead that is no convoy
#     records the PR it carries on itself;
#   - a city login that does not read takes no PR;
#   - a bead whose branch the refinery's tree does not hold gets no write.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-publish-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

# fresh — a new fixture, so no case reads another's repositories or store.
fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-publish.sh
}
run() { OUT=$("$SUT/refinery-publish.sh" "$@" 2>&1); RC=$?; }

echo "# with no PR open, the head is pushed and a draft PR opens and is recorded"
fresh
branch_with polecat/a a.txt >/dev/null
work a polecat/a
prepared a polecat/a
HEAD_A=$(git -C "$HOME_DIR/worktrees/a" rev-parse HEAD)
run --bead a
eq "$RC" 0 "the publication exits 0"
eq "$(tip polecat/a)" "$HEAD_A" "the prepared head is on origin's branch"
has "$(logged gh)" "pr create --repo zook/rig --base main --head polecat/a --draft --title feat: a (a)" "the PR opens as a draft with the composed title"
eq "$(meta a merge_result)" "pull_request_pending" "the bead records its PR as pending"
eq "$(meta a pr_head_sha)" "$HEAD_A" "…at the head the refinery validated"
eq "$(bstatus a)" "blocked" "…and is blocked on it"
hasnt "$(logged gh)" "pr edit" "a new PR needs no edit"

echo "# a PR the city's account opened and the bead never recorded is adopted"
fresh
branch_with polecat/b b.txt >/dev/null
work b polecat/b
prepared b polecat/b
HEAD_B=$(git -C "$HOME_DIR/worktrees/b" rev-parse HEAD)
pr 41 polecat/b gc-city-bot
run --bead b
eq "$RC" 0 "the publication exits 0"
has "$OUT" "adopting PR #41" "it says it adopts the open PR"
hasnt "$(logged gh)" "pr create" "no second PR opens"
has "$(logged gh)" "pr edit 41 --repo zook/rig --title feat: b (b) --body-file" "the PR's title and body are edited"
eq "$(tip polecat/b)" "$HEAD_B" "the prepared head is pushed"
eq "$(meta b pr_url)" "https://github.com/zook/rig/pull/41" "the bead records the adopted PR"

echo "# a half-written record is taken again and recorded on the PR existing_pr names"
fresh
branch_with polecat/h h.txt >/dev/null
work h polecat/h '{"pr_reconcile_pending":"true","existing_pr":"https://github.com/zook/rig/pull/52"}'
prepared h polecat/h
pr 52 polecat/h gc-city-bot
run --bead h
eq "$RC" 0 "the publication exits 0"
hasnt "$(logged gh)" "pr create" "no second PR opens"
hasnt "$(logged gh)" "pr list" "the PR existing_pr names is read, not searched for"
eq "$(meta h merge_result)" "pull_request_pending" "the half-written bead is recorded"
eq "$(meta h pr_url)" "https://github.com/zook/rig/pull/52" "…on the PR existing_pr names"

echo "# a PR another account opened on the branch parks the bead and opens no second PR"
fresh
BEFORE=$(branch_with polecat/c c.txt)
work c polecat/c
prepared c polecat/c
pr 43 polecat/c someone-else
run --bead c
eq "$RC" 4 "the publication parks (exit 4)"
has "$(logged scripts)" "human-gate --subject c --key refinery-pr-not-city-opened" "a refinery-pr-not-city-opened gate is filed on the bead"
has "$(logged scripts)" "opened by someone-else" "…naming the account that opened it"
eq "$(meta c merge_result)" "blocked" "the bead records blocked"
eq "$(bassignee c)" "$GC_AGENT" "…and stays with the refinery, held by its gate"
hasnt "$(logged gh)" "pr create" "no second PR opens"
hasnt "$(logged gh)" "pr edit" "nothing on the PR is edited"
eq "$(tip polecat/c)" "$BEFORE" "nothing is pushed onto its branch"
hasnt "$(logged gctk)" "pr record" "no record is written"

echo "# an old-path record of a PR another account opened parks the bead the same way"
fresh
BEFORE=$(branch_with polecat/o o.txt)
work o polecat/o '{"merge_result":"pull_request_head_changed","pr_url":"https://github.com/zook/rig/pull/44","pr_number":"44"}'
prepared o polecat/o
pr 44 polecat/o someone-else
run --bead o
eq "$RC" 4 "the publication parks (exit 4)"
has "$(logged scripts)" "human-gate --subject o --key refinery-pr-not-city-opened" "the gate names the PR another account opened"
eq "$(tip polecat/o)" "$BEFORE" "nothing is pushed"
hasnt "$(logged gh)" "pr create" "no second PR opens"

echo "# a recorded PR that is closed parks the bead behind refinery-invalid-existing-pr"
fresh
branch_with polecat/x x.txt >/dev/null
work x polecat/x '{"existing_pr":"https://github.com/zook/rig/pull/45"}'
prepared x polecat/x
pr 45 polecat/x gc-city-bot CLOSED
run --bead x
eq "$RC" 4 "the publication parks (exit 4)"
has "$(logged scripts)" "human-gate --subject x --key refinery-invalid-existing-pr" "the gate is keyed refinery-invalid-existing-pr"
has "$(logged scripts)" "is CLOSED, not open" "…and says why the PR is not reused"

echo "# an edit that does not take pushes nothing"
fresh
BEFORE=$(branch_with polecat/e e.txt)
work e polecat/e
prepared e polecat/e
pr 46 polecat/e gc-city-bot
STUB_EDIT_RC=1 run --bead e
eq "$RC" 1 "the publication stops (exit 1)"
eq "$(tip polecat/e)" "$BEFORE" "the head is not pushed under a stale body"
hasnt "$(logged gctk)" "pr record" "nothing is recorded"

echo "# a branch someone pushed to after the prep is refused, never overwritten"
fresh
branch_with polecat/m m.txt >/dev/null
work m polecat/m
prepared m polecat/m
THEIRS=$(branch_with polecat/m theirs.txt polecat/m)
run --bead m
eq "$RC" 6 "the publication says the branch moved (exit 6)"
eq "$(tip polecat/m)" "$THEIRS" "the push someone else made stays"
hasnt "$(logged gh)" "pr create" "no PR opens"
hasnt "$(logged gctk)" "pr record" "nothing is recorded"

echo "# a bead closed or released before its record keeps that state, and its notes name the PR"
fresh
branch_with polecat/r r.txt >/dev/null
work r polecat/r
prepared r polecat/r
STUB_RECORD_RC=3 run --bead r
eq "$RC" 0 "the publication exits 0 once the PR is named"
eq "$(meta r merge_result)" "<absent>" "the bead carries no record"
eq "$(bstatus r)" "open" "…and keeps the state it had"
has "$(bnotes r)" "https://github.com/zook/rig/pull/500" "its notes name the PR"
STUB_RECORD_RC=2 run --bead r
eq "$RC" 1 "a record that did not answer stops (exit 1), for the next pass"

echo "# a rework child handed back records the PR on its anchor and closes"
fresh
branch_with polecat/an an.txt >/dev/null
put "$(jq -nc --arg a "$GC_AGENT" '{id: "an", title: "Anchor", status: "open", assignee: $a, issue_type: "task", created_at: "2026-11-11T00:00:00Z", notes: "",
  metadata: {branch: "polecat/an", target: "main", merge_result: "pull_request_head_changed", pr_url: "https://github.com/zook/rig/pull/47", pr_number: "47"}}')"
work ch polecat/an '{"task_kind":"rework","anchor_bead":"an"}'
prepared ch polecat/an
HEAD_C=$(git -C "$HOME_DIR/worktrees/ch" rev-parse HEAD)
pr 47 polecat/an gc-city-bot
run --bead ch
eq "$RC" 0 "the hand-back exits 0"
has "$(logged gctk)" "pr record an --pr https://github.com/zook/rig/pull/47" "the anchor's record is written"
eq "$(meta an merge_result)" "pull_request_pending" "the anchor records its PR as pending"
eq "$(bstatus ch)" "closed" "the child closes"
eq "$(meta ch gc.work_commit)" "$HEAD_C" "…with its work record"
eq "$(tip polecat/an)" "$HEAD_C" "the head is on the anchor's branch"

echo "# a bead that owns its PR records it on itself, though a parked rework child waits on its branch"
fresh
branch_with polecat/bp bp.txt >/dev/null
work bp polecat/bp '{"merge_result":"pull_request_head_changed","existing_pr":"https://github.com/zook/rig/pull/49","pr_number":"49"}'
work kid polecat/bp '{"task_kind":"rework","anchor_bead":"bp","merge_result":"blocked","blocked_reason":"parked behind a gate"}'
prepared bp polecat/bp
pr 49 polecat/bp gc-city-bot
run --bead bp
eq "$RC" 0 "the publication exits 0"
has "$(logged gctk)" "pr record bp --pr https://github.com/zook/rig/pull/49" "the record is written on the bead that owns the PR"
hasnt "$(logged gctk)" "pr record kid" "…and never on the parked rework child"
eq "$(bstatus bp) $(meta bp merge_result)" "blocked pull_request_pending" "the bead waits on its PR's merge"
eq "$(bstatus kid) $(meta kid merge_result)" "open blocked" "the parked rework child is left as it was"
hasnt "$(bnotes bp)" "Rework landed" "the bead that owns the PR is not closed as a landed rework"

# rebuild <status> <branch> [<type>] [<child metadata>] [<convoy assignee>]
# [<convoy metadata>] — a convoy (or a bead of <type>) with status <status> on
# <branch>, assigned to <convoy assignee>, by default the refinery, as the
# requeue leaves a convoy it rebuilds, whose open PR #70 is from integration/cv,
# and its rebuild child rb on integration/cv, handed back and prepared over a
# main that moved, so its prepared head is new. The convoy carries no
# merge_result unless <convoy metadata> gives it one, so an empty
# <convoy assignee> alone leaves it in neither queue. An empty <status> leaves
# the named bead out of the store. BEFORE is the branch's tip before the
# publication.
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
# with no PR read, edited or opened, nothing pushed and no record written.
parked_rebuild() {
  eq "$RC" 4 "$1: the publication parks (exit 4)"
  has "$(logged scripts)" "human-gate --subject rb --key refinery-rebuild-convoy-not-open" "$1: the gate is keyed refinery-rebuild-convoy-not-open"
  eq "$(bstatus rb) $(meta rb merge_result) $(bassignee rb)" "open blocked $GC_AGENT" "$1: the child records blocked and stays with the refinery"
  eq "$(tip integration/cv)" "$BEFORE" "$1: nothing is pushed"
  eq "$(logged gh)" "" "$1: no PR is read, edited or opened"
  hasnt "$(logged gctk)" "pr record" "$1: no record is written"
}

echo "# a convoy's rebuild child records the PR on its convoy while the convoy is open on its branch and the refinery's"
rebuild open integration/cv
HEAD_RB=$(git -C "$HOME_DIR/worktrees/rb" rev-parse HEAD)
run --bead rb
eq "$RC" 0 "the hand-back exits 0"
has "$(logged gctk)" "pr record cv --pr https://github.com/zook/rig/pull/70" "the convoy's record is written"
eq "$(bstatus cv) $(meta cv merge_result) $(bassignee cv)" "blocked pull_request_pending $GC_AGENT" "…and the convoy waits on its PR's merge, the refinery's"
eq "$(tip integration/cv)" "$HEAD_RB" "the head is on the convoy's branch"
eq "$(bstatus rb)" "closed" "the child closes"
hasnt "$(logged scripts)" "human-gate" "no gate is filed"
rebuild open integration/cv convoy '{}' "" '{"merge_result":"pull_request"}'
HEAD_RB=$(git -C "$HOME_DIR/worktrees/rb" rev-parse HEAD)
run --bead rb
eq "$RC" 0 "a convoy the merge cadence holds at pull_request: the hand-back exits 0"
eq "$(meta cv merge_result) $(bassignee cv)" "pull_request " "…and the record, which takes only an owner that is the refinery's, leaves the convoy as it was"
has "$(bnotes cv)" "Refinery: published https://github.com/zook/rig/pull/70 from integration/cv at $HEAD_RB" "…its notes name the PR"
eq "$(bstatus rb)" "closed" "…and the child closes"

echo "# a rebuild child whose convoy cannot carry its PR is parked, not published as its own"
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
eq "$(meta cv merge_result)" "<absent>" "…and the convoy records nothing"
rebuild ""
run --bead rb
parked_rebuild "a named bead the store does not hold"
has "$(logged scripts)" "but the store holds no bead cv" "a named bead the store does not hold: the gate says so"
rebuild open integration/cv convoy '{}' ""
run --bead rb
parked_rebuild "a convoy open on its branch in neither queue"
has "$(logged scripts)" "but cv is open on integration/cv with no merge_result and assigned to nobody" "a convoy in neither queue: the gate says so"
has "$(logged scripts)" "put cv back in a merge queue by assigning it to the refinery (gc bd update cv --assignee=$GC_AGENT), then clear this gate" "…and names the assignment that goes on"
eq "$(bassignee cv)|$(meta cv merge_result)|$(bnotes cv)" "|<absent>|" "…and the convoy is left as it was"
rebuild closed integration/cv convoy '{"merge_result":"blocked","blocked_reason":"parked behind a gate"}'
run --bead rb
parked_rebuild "a second pass over a parked child whose convoy is still closed"

echo "# a rebuild child whose named bead does not read, or whose gate does not file, writes nothing"
rebuild closed integration/cv
STUB_GC_ID_FAIL=1 run --bead rb
eq "$RC" 1 "an unreadable named bead stops (exit 1)"
eq "$(logged scripts)" "" "…with no gate filed"
eq "$(logged gh)" "" "…no PR read, edited or opened"
eq "$(meta rb merge_result)" "<absent>" "…and nothing recorded"
eq "$(tip integration/cv)" "$BEFORE" "…or pushed"
rebuild closed integration/cv
STUB_HUMAN_GATE_RC=1 run --bead rb
eq "$RC" 1 "a gate that does not file stops (exit 1)"
eq "$(meta rb merge_result)" "<absent>" "…and parks nothing"
eq "$(tip integration/cv)" "$BEFORE" "…and pushes nothing"
eq "$(logged gh)" "" "…and reads, edits or opens no PR"
hasnt "$(logged gctk)" "pr record" "…and records nothing"

echo "# a rework naming a closed bead that is no convoy keeps today's path"
rebuild closed integration/cv task
run --bead rb
eq "$RC" 0 "the publication exits 0"
has "$(logged gctk)" "pr record rb --pr https://github.com/zook/rig/pull/70" "the child records the PR it carries on itself"
hasnt "$(logged scripts)" "human-gate" "no gate is filed"

echo "# a city login that does not read takes no PR"
fresh
BEFORE=$(branch_with polecat/l l.txt)
work l polecat/l
prepared l polecat/l
pr 48 polecat/l gc-city-bot
STUB_LOGIN="" run --bead l
eq "$RC" 1 "the publication stops (exit 1)"
eq "$(tip polecat/l)" "$BEFORE" "nothing is pushed"
hasnt "$(logged gctk)" "pr record" "nothing is recorded"

echo "# a bead whose branch the refinery's tree does not hold gets no write"
fresh
branch_with polecat/p p.txt >/dev/null
branch_with polecat/q q.txt >/dev/null
work p polecat/p
work q polecat/q
prepared q polecat/q
run --bead p
eq "$RC" 1 "a bead with no tree of its own is refused"
hasnt "$(logged gh)" "pr " "nothing is read from or written to GitHub"
eq "$(meta p merge_result)" "<absent>" "nothing is recorded"

echo
echo "refinery-publish: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
