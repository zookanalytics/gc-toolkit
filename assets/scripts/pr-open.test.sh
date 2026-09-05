#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-open.sh — pre_open_gate -> pull_request.
# Covers: adopting an existing OPEN or MERGED PR (flip only, one lifecycle
# transition, never a twin); refusing fork/foreign/uncertifiable rows; the
# closed-unmerged headstone (fresh PR + supersede note; same-head close is a
# human decision left alone); holds gating the create path; the all-lanes-green
# gate over every gate the anchor declares, which no head move disturbs; the
# moved-head refusal on the created PR; and the comment-not-approval verdict
# replay.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-open.sh" "$HERE/lifecycle.sh"
SUT="$SD/pr-open.sh"

pre() { # id branch extra-json [check_set]  (4th arg empty = no check_set key)
  local cs="${4-codex}"
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"t %s","description":"d %s","metadata":{"merge_result":"pre_open_gate","branch":"%s","merged_target":"main"%s%s}}' \
    "$1" "$1" "$1" "$2" "${cs:+,\"check_set\":\"$cs\"}" "${3:-}"
}
prrow() { # num state branch head base [mergedAt] [headrepo]
  printf '{"number":%s,"url":"https://github.com/zook/gc-toolkit/pull/%s","state":"%s","mergedAt":%s,"baseRefName":"%s","headRefName":"%s","headRefOid":"%s","headRepository":{"name":"%s"},"headRepositoryOwner":{"login":"%s"},"isCrossRepository":false}' \
    "$1" "$1" "$2" "${6:-null}" "$5" "$3" "$4" "${7:-gc-toolkit}" "${8:-zook}"
}

echo "# adopt an existing OPEN PR"
store "[$(pre A1 polecat/a1)]"
printf '[%s]' "$(prrow 41 OPEN polecat/a1 sha-a1 main)" > "$GH_DIR/pr_list_polecat_a1.json"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "adoption pass exits 0"
has "$out" "already has PR#41 (OPEN); flipped to pull_request" "the open PR was adopted"
eq "$(meta A1 merge_result)" "pull_request" "anchor flipped"
eq "$(meta A1 pr_url)" "https://github.com/zook/gc-toolkit/pull/41" "pr_url recorded"
eq "$(meta A1 pr_number)" "41" "pr_number recorded"
eq "$(meta A1 merged_target)" "main" "merged_target recorded"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no twin PR was opened"
eq "$(grep -c '^bd update A1' "$STUB_GC_LOG" || true)" "1" "ONE atomic update carried the flip"

echo "# a MERGED sibling PR flips too"
store "[$(pre A2 polecat/a2)]"
printf '[%s]' "$(prrow 42 MERGED polecat/a2 sha-a2 main '"2026-08-20T00:00:00Z"')" > "$GH_DIR/pr_list_polecat_a2.json"
out=$("$SUT" 2>&1)
has "$out" "PR#42 (MERGED); flipped" "a merged PR still flips the anchor onto the observer's scan"

echo "# a fork's same-named branch is never adopted"
store "[$(pre A3 polecat/a3)]"
printf '[%s]' "$(prrow 43 OPEN polecat/a3 sha-a3 main null gc-toolkit stranger)" > "$GH_DIR/pr_list_polecat_a3.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "none is ours (name collision)" "the fork row is refused, not adopted"
eq "$(meta A3 merge_result)" "pre_open_gate" "the anchor stays pre_open_gate"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…and no PR is opened into the collision"

echo "# holds gate the create path"
store "[$(pre B1 polecat/b1 ',"merge_hold":"true","check.codex":"green"')]"
echo "sha-b1" > "$GH_DIR/head_polecat_b1"
out=$("$SUT" 2>&1)
has "$out" "held (merge_hold" "merge_hold holds the create"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR published past the hold"

echo "# a declared gate short of green holds"
store "[$(pre B2 polecat/b2 ',"check.codex":"fixing"')]"
echo "sha-b2" > "$GH_DIR/head_polecat_b2"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "check 'codex' is 'fixing', not green" "a lane short of green holds the open"
eq "$(meta B2 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"
# The gate check is row-only (green is a state of the lane, not the head), so
# it is judged before the head fetch: a held anchor pays no network call.
hasnt "$(cat "$STUB_GH_LOG")" "commits/" "an ungreen gate holds before the head is ever fetched"

# The whole of the 211: a green lane is green however far the branch has moved
# since the verdict, so the head the PR opens at is not the gate's business.
echo "# a green lane publishes at a head no verdict ever named"
store "[$(pre B2b polecat/b2b ',"check.codex":"green"')]"
echo "sha-b2b-moved-on" > "$GH_DIR/head_polecat_b2b"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/62"
printf '%s' "$(prrow 62 OPEN polecat/b2b sha-b2b-moved-on main)" > "$GH_DIR/pr_view_62.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta B2b merge_result)" "pull_request" "the anchor publishes"
has "$(cat "$STUB_GH_LOG")" "pr create" "…and the PR is opened"

# The gate is the anchor's whole declared set: a set naming a second reviewer
# publishes only once that reviewer has answered, and a set naming no
# marker-bearing gate publishes rather than waiting on a marker no arm writes.
echo "# a second declared gate with no marker holds the publish"
store "[$(pre B3 polecat/b3 ',"check.codex":"green"' 'codex,triage')]"
echo "sha-b3" > "$GH_DIR/head_polecat_b3"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "check 'triage' is 'unreviewed', not green" "the unmarked second gate holds"
eq "$(meta B3 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR is published past an unanswered gate"
hasnt "$(cat "$STUB_GH_LOG")" "commits/" "…and the head was never fetched to decide it"

echo "# an empty check_set is never the gateless opt-out"
store "[$(pre B4 polecat/b4 '' '')]"
echo "sha-b4" > "$GH_DIR/head_polecat_b4"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "no normalized check_set" "an unnormalized anchor is held, not published"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…and nothing is opened under it"
hasnt "$(cat "$STUB_GH_LOG")" "commits/" "an unnormalized check_set holds before the head is ever fetched"

echo "# check_set=none publishes: gateless BY CHOICE is not a missing marker"
store "[$(pre B5 polecat/b5 '' 'none')]"
echo "sha-b5" > "$GH_DIR/head_polecat_b5"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/61"
printf '%s' "$(prrow 61 OPEN polecat/b5 sha-b5 main)" > "$GH_DIR/pr_view_61.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#61" "the none sentinel opens instead of stranding at pre_open_gate"
eq "$(meta B5 merge_result)" "pull_request" "anchor flipped"

echo "# check_set=approval publishes: approval carries no marker and needs the PR"
store "[$(pre B6 polecat/b6 '' 'approval')]"
echo "sha-b6" > "$GH_DIR/head_polecat_b6"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/62"
printf '%s' "$(prrow 62 OPEN polecat/b6 sha-b6 main)" > "$GH_DIR/pr_view_62.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#62" "an approval-only set opens; merge.sh holds for the human review"
eq "$(meta B6 merge_result)" "pull_request" "anchor flipped"

echo "# create the PR at the reviewed head"
store "[$(pre C1 polecat/c1 ',"check.codex":"green"'),
        {\"id\":\"rev-c1\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"VERDICT: COMMENT ok\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"C1\"}}]"
echo "sha-c1" > "$GH_DIR/head_polecat_c1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/77"
printf '%s' "$(prrow 77 OPEN polecat/c1 sha-c1 main)" > "$GH_DIR/pr_view_77.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "create pass exits 0"
has "$out" "opened PR#77" "the PR was opened and reported"
eq "$(meta C1 merge_result)" "pull_request" "anchor flipped to pull_request"
eq "$(meta C1 pr_number)" "77" "pr_number recorded"
ghlog=$(cat "$STUB_GH_LOG")
has "$ghlog" "pr create --repo github.com/zook/gc-toolkit --base main --head polecat/c1" "create pinned to origin, base and head"
hasnt "$ghlog" "--draft" "the PR is non-draft"
has "$ghlog" "pr view 77 --repo github.com/zook/gc-toolkit" "read back BY NUMBER, pinned"
has "$ghlog" "pr comment 77" "the verdict was replayed as a comment"
hasnt "$ghlog" "pr review" "never an approval"

echo "# the body summarizes the diff, and demotes the dispatch text"
# A reviewer who was not in the originating conversation opens this body. The
# anchor's description is dispatch text — what the work was asked to do — so
# the polecat's pr_summary is the ## Summary and the description survives one
# level down.
store "[$(pre E1 polecat/e1 ',"check.codex":"green","pr_summary":"Compares heads instead of branch names, so a moved head is refused."')]"
echo "sha-e1" > "$GH_DIR/head_polecat_e1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/81"
printf '%s' "$(prrow 81 OPEN polecat/e1 sha-e1 main)" > "$GH_DIR/pr_view_81.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#81" "the PR was opened"
body=$(cat "$GH_DIR/pr_create_body.txt")
has "$body" "## Summary"$'\n'$'\n'"Compares heads instead of branch names, so a moved head is refused." \
    "pr_summary is the summary a reviewer reads first"
has "$body" "<summary>Dispatch — what this work was asked to do</summary>" "the dispatch text is demoted, not dropped"
has "$body" "d E1" "…and it is still in the body"
has "$body" "## Refinery handoff" "the handoff block is unchanged"

echo "# no carried summary keeps today's body"
# The current text is a poor summary, not an empty one: an anchor whose handoff
# carried nothing must still open with a body.
store "[$(pre E2 polecat/e2 ',"check.codex":"green"')]"
echo "sha-e2" > "$GH_DIR/head_polecat_e2"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/82"
printf '%s' "$(prrow 82 OPEN polecat/e2 sha-e2 main)" > "$GH_DIR/pr_view_82.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#82" "the PR was opened"
body=$(cat "$GH_DIR/pr_create_body.txt")
has "$body" "## Summary"$'\n'$'\n'"d E2" "the description is the summary when nothing was carried"
hasnt "$body" "<details>" "no empty demotion section when there is nothing to demote"

echo "# a whitespace-only summary is the absent case"
store "[$(pre E3 polecat/e3 ',"check.codex":"green","pr_summary":"   \n  "')]"
echo "sha-e3" > "$GH_DIR/head_polecat_e3"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/83"
printf '%s' "$(prrow 83 OPEN polecat/e3 sha-e3 main)" > "$GH_DIR/pr_view_83.json"
out=$("$SUT" 2>&1)
body=$(cat "$GH_DIR/pr_create_body.txt")
has "$body" "## Summary"$'\n'$'\n'"d E3" "blank prose falls back rather than publishing an empty summary"
hasnt "$body" "<details>" "…and demotes nothing"

echo "# a head that moved between gate and create refuses the stamp"
store "[$(pre C2 polecat/c2 ',"check.codex":"green"')]"
echo "sha-c2" > "$GH_DIR/head_polecat_c2"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/78"
printf '%s' "$(prrow 78 OPEN polecat/c2 sha-c2-moved main)" > "$GH_DIR/pr_view_78.json"
out=$("$SUT" 2>&1)
has "$out" "not the reviewed 'sha-c2'" "the moved head is refused"
eq "$(meta C2 merge_result)" "pre_open_gate" "nothing stamped; the anchor re-adopts next pass"

echo "# closed-unmerged headstone: supersede at a NEW head"
store "[$(pre D1 polecat/d1 ',"check.codex":"green"')]"
printf '[%s]' "$(prrow 50 CLOSED polecat/d1 sha-d1-old main)" > "$GH_DIR/pr_list_polecat_d1.json"
echo "sha-d1-new" > "$GH_DIR/head_polecat_d1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/51"
printf '%s' "$(prrow 51 OPEN polecat/d1 sha-d1-new main)" > "$GH_DIR/pr_view_51.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "superseding closed PR#50" "the fresh PR names the headstone"
eq "$(meta D1 pr_number)" "51" "the fresh PR is the recorded identity"
has "$(cat "$STUB_GH_LOG")" "pr comment 50" "the superseded PR got the pointer comment"

echo "# closed-unmerged at the SAME head is a human decision"
store "[$(pre D2 polecat/d2 ',"check.codex":"green"')]"
printf '[%s]' "$(prrow 52 CLOSED polecat/d2 sha-d2 main)" > "$GH_DIR/pr_list_polecat_d2.json"
echo "sha-d2" > "$GH_DIR/head_polecat_d2"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "not reopening a human's decision" "same-head close is respected"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no replacement PR is opened"

echo "# unreadable enumeration fails loudly"
out=$(STUB_LIST_FAIL=1 "$SUT" 2>&1); rc=$?
eq "$rc" 1 "an unreadable enumeration exits non-zero"
has "$out" "false all-clear" "…and says why"

echo "# the opened title carries a conventional-commit type from the bead kind"
# A conventional-commit PR-title check requires a leading type token. The type
# is derived from the bead's issue_type, unless the title already opens with a
# recognized one — then it is kept, never double-prefixed. The bead id suffix
# survives in every case.
tanchor() { # id issue_type title  — a green pre_open_gate anchor + its head
  echo "sha-$1" > "$GH_DIR/head_polecat_$1"
  printf '{"id":"%s","status":"open","issue_type":"%s","title":"%s","description":"d %s","metadata":{"merge_result":"pre_open_gate","branch":"polecat/%s","merged_target":"main","check_set":"codex","check.codex":"green"}}' \
    "$1" "$2" "$3" "$1" "$1"
}
store "[$(tanchor ttbug  bug     'Reject a moved head'),
        $(tanchor tttask task    'Reshape the reconcile loop'),
        $(tanchor ttdoc  docs    'Document the merge cadence'),
        $(tanchor ttfeat feature 'Support integration branches'),
        $(tanchor ttpfx  task    'fix(pr-open): keep the bead id in the title'),
        $(tanchor ttbare ''      'Tidy the enumerate step')]"
# STUB_PR_CREATE_URL empty: create logs its args (the --title among them) and
# returns nothing, so the pass stops before the readback. The title is read
# from the logged create, where gh's arg log space-joins argv — so a title is
# the run between --title and the --body-file that always follows it.
export STUB_PR_CREATE_URL=""
: > "$STUB_GH_LOG"
"$SUT" >/dev/null 2>&1
tlog=$(cat "$STUB_GH_LOG")
has "$tlog" "--title fix: Reject a moved head (ttbug) --body-file"            "bug maps to fix"
has "$tlog" "--title chore: Reshape the reconcile loop (tttask) --body-file"  "task maps to chore"
has "$tlog" "--title docs: Document the merge cadence (ttdoc) --body-file"    "docs maps to docs"
has "$tlog" "--title feat: Support integration branches (ttfeat) --body-file" "feature maps to feat"
has "$tlog" "--title fix(pr-open): keep the bead id in the title (ttpfx) --body-file" \
    "an existing conventional prefix is kept, not double-prefixed"
hasnt "$tlog" "chore: fix(pr-open):" "…and no derived type is prepended to it"
has "$tlog" "--title chore: Tidy the enumerate step (ttbare) --body-file" \
    "a bead with no issue_type falls back to chore"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
