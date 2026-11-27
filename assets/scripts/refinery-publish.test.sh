#!/usr/bin/env bash
# Hermetic test for refinery-publish.sh, the refinery's mr step on the new
# path. Runs the real script against real git repositories (refinery-test-lib.sh)
# with a fake gc, gh and gctk, and the real gctk for the edit of an open PR's
# title and body (gctk pr compose --edit). Proves:
#   - with no PR open, the head is pushed under the lease and the PR opens as a
#     draft with the composed title and body, then is recorded pending;
#   - a PR open on the branch that the city's account opened and the bead never
#     recorded is adopted: its title is edited, it is returned to draft, the
#     head is pushed, and it is recorded, with no second PR;
#   - the edit of a PR's title and body edits only what moved: a body whose
#     summary names an earlier head is edited alone when the title differs only
#     in spacing, and a PR that shows the composition at the prepared head gets
#     no edit, while its publication goes on;
#   - a PR the bead records is returned to draft before the head is pushed onto
#     it, and a PR that did not return to draft is not pushed onto, while a PR
#     the step opens opens as a draft and needs no return;
#   - a half-written record (the marker and existing_pr, no record) is taken
#     again and recorded on the PR existing_pr names;
#   - a PR another account opened, found on the branch or named by an old-path
#     record, parks the bead behind refinery-pr-not-city-opened, with nothing
#     edited, pushed or opened;
#   - a recorded PR that is closed, or that the repository does not have,
#     parks the bead behind refinery-invalid-existing-pr, whose message names
#     the stand-down under that key, a bead at a head the refinery has not
#     validated among them;
#   - the body names the base the PR opens into: the rig's default branch for a
#     bead that records no target, and a retargeted bead's new target over its
#     older merged_target;
#   - an edit that does not take pushes nothing and returns nothing to draft,
#     so the head never moves under a stale body;
#   - a branch someone pushed to after the prep is refused, never overwritten,
#     and nothing is opened or recorded;
#   - a bead closed or released before its record keeps that state, and the PR
#     is named in a note on it;
#   - a rework child handed back records the PR on its anchor and closes;
#   - a bead that owns its PR records it on itself, though a parked rework
#     child of it waits on its branch with a merge_result of its own;
#   - a listing of the branch's open beads that fails, that prints [] as it
#     fails or that is no JSON array names no owner, so a rework child that
#     carries its anchor's PR keys stops before any PR is read, pushed onto,
#     opened or recorded, and never records that PR as its own; a listing that
#     carries a raw control byte is read once scrubbed, and the child's PR is
#     recorded on its anchor;
#   - a rework whose anchor is not open on its branch records the PR it carries
#     on itself;
#   - a city login that does not read takes no PR;
#   - a bead whose branch the refinery's tree does not hold gets no write.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-publish-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
# The edit is the real gctk's, built from this checkout once, with the compiled
# fake gc it reads the store through, beside the directory each case empties.
RT_GCTK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-publish-bin.XXXXXX")"
trap 'rm -rf "$TMP" "$RT_GCTK_DIR"' EXIT
( cd "$HERE/../../services/gctk" && go build -buildvcs=false -o "$RT_GCTK_DIR/gctk" ./cmd/gctk ) >"$RT_GCTK_DIR/build.log" 2>&1 \
  || { echo "gctk did not build: $(tail -3 "$RT_GCTK_DIR/build.log")" >&2; exit 1; }
export RT_GCTK_REAL="$RT_GCTK_DIR/gctk"
if [ -n "${RUN_TESTS_FAKE_GC:-}" ] && [ -x "$RUN_TESTS_FAKE_GC" ]; then
  export RT_FAKE_GC="$RUN_TESTS_FAKE_GC"
else
  ( cd "$HERE/../../services/gctk" && go build -buildvcs=false -o "$RT_GCTK_DIR/fake-gc" ./internal/gcbd/fakegc ) >"$RT_GCTK_DIR/build.log" 2>&1 \
    || { echo "the fake gc did not build: $(tail -3 "$RT_GCTK_DIR/build.log")" >&2; exit 1; }
  export RT_FAKE_GC="$RT_GCTK_DIR/fake-gc"
fi
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

# fresh — a new fixture, so no case reads another's repositories or store.
fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-publish.sh
}
run() { OUT=$("$SUT/refinery-publish.sh" "$@" 2>&1); RC=$?; }
# page <n> <bead> <head> — PR #<n> shows the title and body the real gctk
# composes for <bead> at <head>, into main.
page() {
  local out f="$GH_DIR/view_$1.json"
  out=$("$BIN/gctk-real" pr compose "$2" --head "$3" --target main --gates '') || { rt_bad "page: $2's PR did not compose"; return 1; }
  jq --argjson c "$out" '.title = $c.title | .body = $c.body' "$f" > "$f.n" && mv "$f.n" "$f"
}
# titled <n> <title> — PR #<n>'s title is <title>.
titled() { jq --arg t "$2" '.title = $t' "$GH_DIR/view_$1.json" > "$GH_DIR/view_$1.json.n" && mv "$GH_DIR/view_$1.json.n" "$GH_DIR/view_$1.json"; }
shows() { jq -r ".$2" "$GH_DIR/view_$1.json"; }

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
eq "$(bstatus a) $(bassignee a)" "blocked " "…and is blocked on it, assigned to nobody, since the refinery's work on it ends"
hasnt "$(logged gctk)" "--edit" "a new PR needs no edit"
hasnt "$(logged gctk)" "pr draft" "a PR that opens as a draft needs no return to draft"

echo "# a PR the city's account opened and the bead never recorded is adopted"
fresh
branch_with polecat/b b.txt >/dev/null
work b polecat/b
prepared b polecat/b
HEAD_B=$(git -C "$HOME_DIR/worktrees/b" rev-parse HEAD)
pr 41 polecat/b gc-city-bot
page 41 b "$HEAD_B"
TITLE_B=$(shows 41 title)
titled 41 "old title 41"
run --bead b
eq "$RC" 0 "the publication exits 0"
has "$OUT" "adopting PR #41" "it says it adopts the open PR"
hasnt "$(logged gh)" "pr create" "no second PR opens"
has "$(logged gctk)" "pr compose b --pr https://github.com/zook/rig/pull/41 --head $HEAD_B --target main --gates  --edit" \
  "gctk edits the PR the bead does not record, which --pr names"
eq "$(logged edits)" "41 title" "the PR's title is edited, and its body, which shows the composition, is not"
eq "$(shows 41 title)" "$TITLE_B" "…to the composed title"
has "$(logged gctk)" "pr draft b --pr https://github.com/zook/rig/pull/41" "the adopted PR is returned to draft"
eq "$(grep -E '^pr (compose|draft) b ' "$LOGS/gctk.log" | cut -d' ' -f2 | tr '\n' ' ')" "compose draft " "…after the edit"
eq "$(tip polecat/b)" "$HEAD_B" "the prepared head is pushed"
eq "$(meta b pr_url)" "https://github.com/zook/rig/pull/41" "the bead records the adopted PR"

echo "# only what moved is edited: a summary that names an earlier head, under a title that differs only in spacing"
fresh
BEFORE=$(branch_with polecat/s s.txt)
work s polecat/s '{"merge_result":"pull_request_head_changed","pr_url":"https://github.com/zook/rig/pull/61","pr_number":"61"}'
main_with s-later.txt >/dev/null
prepared s polecat/s
HEAD_S=$(git -C "$HOME_DIR/worktrees/s" rev-parse HEAD)
pr 61 polecat/s gc-city-bot
page 61 s "$BEFORE"
SPACED=$(shows 61 title | sed 's/ /  /g')
titled 61 "$SPACED"
run --bead s
eq "$RC" 0 "the publication exits 0"
eq "$(logged edits)" "61 body" "the body is edited alone"
has "$(shows 61 body)" "${HEAD_S:0:8}" "…to the summary at the prepared head"
hasnt "$(shows 61 body)" "${BEFORE:0:8}" "…in place of the earlier head's"
eq "$(shows 61 title)" "$SPACED" "the title, the same in its words, stays as it stands"

echo "# a PR that shows the composition at the prepared head gets no edit, and its publication goes on"
fresh
branch_with polecat/n n.txt >/dev/null
work n polecat/n '{"merge_result":"pull_request_head_changed","pr_url":"https://github.com/zook/rig/pull/62","pr_number":"62"}'
prepared n polecat/n
HEAD_N=$(git -C "$HOME_DIR/worktrees/n" rev-parse HEAD)
pr 62 polecat/n gc-city-bot
page 62 n "$HEAD_N"
run --bead n
eq "$RC" 0 "the publication exits 0"
has "$(logged gctk)" "pr compose n --pr https://github.com/zook/rig/pull/62 --head $HEAD_N --target main --gates  --edit" "gctk is asked for the edit"
eq "$(logged edits)" "" "…and edits nothing"
has "$OUT" "shows its composition already" "…saying the PR shows its composition"
eq "$(tip polecat/n)" "$HEAD_N" "the head is pushed"
eq "$(meta n merge_result)" "pull_request_pending" "…and the PR recorded pending"

echo "# a recorded PR returns to draft before the push, and one that does not is not pushed onto"
fresh
BEFORE=$(branch_with polecat/d d.txt)
work d polecat/d '{"merge_result":"pull_request_head_changed","pr_url":"https://github.com/zook/rig/pull/45","pr_number":"45"}'
main_with d-later.txt >/dev/null
prepared d polecat/d
HEAD_D=$(git -C "$HOME_DIR/worktrees/d" rev-parse HEAD)
eq "$([ "$HEAD_D" != "$BEFORE" ] && echo new)" "new" "the prep merged main that moved, so its prepared head is new"
pr 45 polecat/d gc-city-bot
STUB_DRAFT_RC=2 run --bead d
eq "$RC" 1 "a PR that did not return to draft stops the step"
has "$OUT" "did not return to draft, so the head is not pushed" "…and says why"
eq "$(tip polecat/d)" "$BEFORE" "nothing is pushed onto the PR while it may be ready"
hasnt "$(logged gctk)" "pr record" "…and nothing is recorded"
reset_logs
run --bead d
eq "$RC" 0 "the next pass publishes"
has "$(logged gctk)" "pr draft d --pr https://github.com/zook/rig/pull/45" "…returning the recorded PR to draft"
eq "$(tip polecat/d)" "$HEAD_D" "…then pushing the head"
eq "$(meta d merge_result)" "pull_request_pending" "…and recording it"

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
eq "$(logged edits)" "" "nothing on the PR is edited"
eq "$(tip polecat/c)" "$BEFORE" "nothing is pushed onto its branch"
hasnt "$(logged gctk)" "pr record" "no record is written"
fresh
BEFORE=$(branch_with polecat/c c.txt)
work c polecat/c
prepared c polecat/c
pr 43 polecat/c someone-else
STUB_HUMAN_GATE_RC=1 run --bead c
eq "$RC" 1 "a park whose gate does not file stops (exit 1)"
eq "$(meta c merge_result)" "<absent>" "…and parks nothing"
eq "$(logged edits)" "" "…edits nothing on the PR"
eq "$(tip polecat/c)" "$BEFORE" "…pushes nothing"
hasnt "$(logged gctk)" "pr record" "…and records nothing"

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
has "$(logged scripts)" "stand-down.sh x --key refinery-invalid-existing-pr --ruling" "…and names the stand-down under its key"
fresh
branch_with polecat/hc hc.txt >/dev/null
work hc polecat/hc '{"merge_result":"pull_request_head_changed","existing_pr":"https://github.com/zook/rig/pull/47","pr_url":"https://github.com/zook/rig/pull/47","pr_number":"47"}'
prepared hc polecat/hc
pr 47 polecat/hc gc-city-bot CLOSED
run --bead hc
eq "$RC" 4 "a bead at a head the refinery has not validated, whose PR closed, parks at its publication (exit 4)"
has "$(logged scripts)" "human-gate --subject hc --key refinery-invalid-existing-pr" "…behind the gate stand-down.sh's refusal names for it"
has "$(logged scripts)" "stand-down.sh hc --key refinery-invalid-existing-pr --ruling" "…whose message names the stand-down under its key"
hasnt "$(logged gctk)" "pr record" "…and nothing is recorded"
fresh
branch_with polecat/nf nf.txt >/dev/null
work nf polecat/nf '{"existing_pr":"https://github.com/zook/rig/pull/48"}'
prepared nf polecat/nf
run --bead nf
eq "$RC" 4 "a recorded PR the repository does not have parks the bead (exit 4)"
has "$(logged scripts)" "human-gate --subject nf --key refinery-invalid-existing-pr" "…behind refinery-invalid-existing-pr"
has "$(logged scripts)" "stand-down.sh nf --key refinery-invalid-existing-pr --ruling" "…whose message names the stand-down under its key"

echo "# the body names the base the PR opens into: the rig's default branch, or a retargeted bead's new one"
fresh
branch_with trunk trunk.txt >/dev/null
git -C "$RIG" fetch -q origin "+refs/heads/trunk:refs/remotes/origin/trunk"
git -C "$RIG" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
branch_with polecat/dt dt.txt trunk >/dev/null
work dt polecat/dt '{"target":""}'
prepared dt polecat/dt
HEAD_DT=$(git -C "$HOME_DIR/worktrees/dt" rev-parse HEAD)
run --bead dt
eq "$RC" 0 "a bead that records no target publishes (exit 0)"
has "$(logged gctk)" "pr compose dt --head $HEAD_DT --target trunk " "…its body naming the rig's default branch"
has "$(logged gh)" "pr create --repo zook/rig --base trunk --head polecat/dt" "…the base the PR opens into"
fresh
branch_with integration/y y-base.txt >/dev/null
branch_with polecat/rt rt.txt integration/y >/dev/null
work rt polecat/rt '{"target":"integration/y","merged_target":"integration/x"}'
prepared rt polecat/rt
HEAD_RT=$(git -C "$HOME_DIR/worktrees/rt" rev-parse HEAD)
run --bead rt
eq "$RC" 0 "a retargeted bead whose merged_target names its old base publishes (exit 0)"
has "$(logged gctk)" "pr compose rt --head $HEAD_RT --target integration/y " "…its body naming the new base"
has "$(logged gh)" "pr create --repo zook/rig --base integration/y --head polecat/rt" "…the base the PR opens into"

echo "# an edit that does not take pushes nothing"
fresh
BEFORE=$(branch_with polecat/e e.txt)
work e polecat/e
main_with e-later.txt >/dev/null
prepared e polecat/e
pr 46 polecat/e gc-city-bot
STUB_EDIT_RC=1 run --bead e
eq "$RC" 1 "the publication stops (exit 1)"
has "$OUT" "the title and body of PR #46 did not take" "…and says why"
eq "$(tip polecat/e)" "$BEFORE" "the head is not pushed under a stale body"
hasnt "$(logged gctk)" "pr draft" "the PR is not returned to draft"
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

# guarded — the anchor ga, whose PR #71 is open from polecat/ga, and its rework
# child gk on that branch in the shape a rework child is filed in: a source key
# and the anchor's PR keys. gk is handed back and prepared over a main that moved,
# so its prepared head is new. BEFORE is the branch's tip before the
# publication.
guarded() {
  fresh
  branch_with polecat/ga ga.txt >/dev/null
  main_with later.txt >/dev/null
  work ga polecat/ga '{"merge_result":"pull_request_head_changed","pr_url":"https://github.com/zook/rig/pull/71","pr_number":"71"}'
  work gk polecat/ga '{"task_kind":"rework","anchor_bead":"ga","source_review":"rv","prepare_mode":"merge","merge_strategy":"mr","existing_pr":"https://github.com/zook/rig/pull/71","pr_url":"https://github.com/zook/rig/pull/71","pr_number":"71"}'
  prepared gk polecat/ga
  pr 71 polecat/ga gc-city-bot
  BEFORE=$(tip polecat/ga)
}
# unread <case> — the publication stopped before reading a PR, and gk records
# nothing as its own.
unread() {
  eq "$RC" 1 "$1: the publication stops (exit 1)"
  has "$OUT" "the bead whose PR polecat/ga lands on cannot be told" "$1: …because no owner can be told"
  eq "$(logged gh)" "" "$1: no PR is read, edited or opened"
  hasnt "$(logged gctk)" "pr record" "$1: no record is written"
  eq "$(tip polecat/ga)" "$BEFORE" "$1: nothing is pushed"
  eq "$(bstatus gk) $(meta gk merge_result)" "open <absent>" "$1: the child stays open and records nothing"
  eq "$(meta ga merge_result)" "pull_request_head_changed" "$1: the anchor keeps its record"
}

echo "# a branch listing that does not read names no owner, so a rework child never records its anchor's PR as its own"
guarded
STUB_GC_LIST_FAIL=1 run --bead gk
unread "a listing that fails"
guarded
STUB_GC_LIST_OUT='[]' STUB_GC_LIST_RC=1 run --bead gk
unread "a listing that prints [] as it fails"
guarded
STUB_GC_LIST_OUT='{"error":"database is locked"}' run --bead gk
unread "a listing that is no JSON array"

echo "# a branch listing that carries a raw control byte is read once scrubbed"
guarded
HEAD_GK=$(git -C "$HOME_DIR/worktrees/gk" rev-parse HEAD)
LISTING=$(jq -c '[ .[] | select(.metadata.branch == "polecat/ga") ]' "$STORE")
CTRL=$(printf '\001')
STUB_GC_LIST_OUT="${LISTING/Work ga/Work${CTRL}ga}" run --bead gk
case "${LISTING/Work ga/Work${CTRL}ga}" in *"$CTRL"*) rt_ok "the listing the store gives carries the byte" ;; *) rt_bad "the listing the store gives carries the byte" ;; esac
eq "$RC" 0 "the hand-back exits 0"
has "$(logged gctk)" "pr record ga --pr https://github.com/zook/rig/pull/71" "the PR is recorded on the anchor"
hasnt "$(logged gctk)" "pr record gk" "…and never on the child"
eq "$(tip polecat/ga)" "$HEAD_GK" "the head is on the anchor's branch"
eq "$(bstatus gk)" "closed" "the child closes"

echo "# a rework whose anchor is not open on its branch records the PR it carries on itself"
fresh
branch_with polecat/cl cl.txt >/dev/null
put "$(jq -nc '{id: "gone", title: "Gone", status: "closed", assignee: "", issue_type: "task", created_at: "2026-11-11T00:00:00Z", notes: "",
  metadata: {branch: "polecat/cl", target: "main", pr_url: "https://github.com/zook/rig/pull/72", pr_number: "72"}}')"
work rw polecat/cl '{"task_kind":"rework","anchor_bead":"gone","merge_strategy":"mr","existing_pr":"https://github.com/zook/rig/pull/72"}'
prepared rw polecat/cl
pr 72 polecat/cl gc-city-bot
run --bead rw
eq "$RC" 0 "the publication exits 0"
has "$(logged gctk)" "pr record rw --pr https://github.com/zook/rig/pull/72" "the child records the PR it carries on itself"
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
