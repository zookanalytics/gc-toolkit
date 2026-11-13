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
#   - a head no gate cleared, by the gate's record, is neither pushed nor
#     recorded: no gate finished, one ran at another head, one was cut short,
#     or one failed a check with no failure tracked at the head; a failed check
#     whose failure is tracked there lets the head be recorded;
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

echo "# a head no gate cleared is neither pushed nor recorded"
fresh
BEFORE=$(branch_with polecat/g g.txt)
work g polecat/g
prepared g polecat/g
HEAD_G=$(git -C "$HOME_DIR/worktrees/g" rev-parse HEAD)
rm -f "$(gate_dir)/rc"
run --bead g
eq "$RC" 1 "a head whose gate never finished stops (exit 1)"
has "$OUT" "no gate cleared $HEAD_G" "it names the head"
has "$OUT" "no gate has finished" "…and says no gate finished"
gate_record g 0 "GATE PASSED" 0123456789abcdef0123456789abcdef01234567
run --bead g
eq "$RC" 1 "a gate that passed at another head stops"
has "$OUT" "the last gate ran at 0123456789abcdef0123456789abcdef01234567, not at $HEAD_G" "it names both heads"
gate_record g 4 "GATE CUT SHORT: test:124"
run --bead g
eq "$RC" 1 "a gate cut short stops"
gate_record g 1 "GATE FAILED: lint:1 test:1"
printf 'lint %s\n' "$HEAD_G" >> "$(gate_dir)/tracked"
printf 'test 0123456789abcdef0123456789abcdef01234567\n' >> "$(gate_dir)/tracked"
run --bead g
eq "$RC" 1 "a failed check with no failure tracked at the head stops"
has "$OUT" "failed test, and no failure of it is tracked as pre-existing there" "it names the check"
eq "$(tip polecat/g)" "$BEFORE" "none of them pushes anything"
hasnt "$(logged gctk)" "pr record" "…or records anything"
hasnt "$(logged gh)" "pr create" "…or opens a PR"
printf 'test %s\n' "$HEAD_G" >> "$(gate_dir)/tracked"
run --bead g
eq "$RC" 0 "a gate whose every failed check has a failure tracked at the head lets it be recorded"
eq "$(tip polecat/g)" "$HEAD_G" "the head is pushed"
has "$(logged gctk)" "pr record g --pr" "…and recorded as pending"

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
