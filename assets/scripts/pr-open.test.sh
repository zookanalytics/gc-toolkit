#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-open.sh — pre_open_gate -> pull_request.
# Covers: adopting an existing OPEN or MERGED PR (flip only, one lifecycle
# transition, never a twin); refusing fork/foreign/uncertifiable rows; the
# closed-unmerged headstone (fresh PR + supersede note; same-head close is a
# human decision left alone); holds gating the create path; the codex
# green@live-head gate; the moved-head refusal on the created PR; and the
# comment-not-approval verdict replay (the CLOSED codex verdict at the opened
# head, never a sibling gate's or an unfinished round's).
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

pre() { # id branch extra-json
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"t %s","description":"d %s","metadata":{"merge_result":"pre_open_gate","branch":"%s","merged_target":"main"%s}}' \
    "$1" "$1" "$1" "$2" "${3:-}"
}
review() { # id status check_name reviewed_oid anchor updated_at notes
  printf '{"id":"%s","status":"%s","assignee":"","updated_at":"%s","notes":"%s","metadata":{"task_kind":"review","check_name":"%s","anchor_bead":"%s","reviewed_oid":"%s"}}' \
    "$1" "$2" "$6" "$7" "$3" "$5" "$4"
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
store "[$(pre B1 polecat/b1 ',"merge_hold":"true","check.codex":"green@sha-b1"')]"
echo "sha-b1" > "$GH_DIR/head_polecat_b1"
out=$("$SUT" 2>&1)
has "$out" "held (merge_hold" "merge_hold holds the create"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR published past the hold"

echo "# codex not green at the live head holds"
store "[$(pre B2 polecat/b2 ',"check.codex":"green@stale-oid"')]"
echo "sha-b2" > "$GH_DIR/head_polecat_b2"
out=$("$SUT" 2>&1)
has "$out" "codex not green at live head" "a stale marker holds the open"
eq "$(meta B2 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"

echo "# create the PR at the reviewed head"
# Three reviews on one anchor: the codex verdict this PR is opened on, a newer
# triage verdict, and a newer codex round still in progress. Only the first is
# the comment's subject; the other two are what a most-recently-updated pick
# would replay under the codex label.
store "[$(pre C1 polecat/c1 ',"check.codex":"green@sha-c1"'),
        $(review rev-c1 closed codex sha-c1 C1 2026-08-20T01:00:00Z 'VERDICT: approve CODEX-AT-HEAD'),
        $(review rev-c1-tri closed triage sha-c1 C1 2026-08-20T02:00:00Z 'VERDICT: approve TRIAGE-WIDENED-NOTHING'),
        $(review rev-c1-run in_progress codex sha-c1 C1 2026-08-20T03:00:00Z 'VERDICT: ROUND-STILL-RUNNING')]"
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
has "$ghlog" "CODEX-AT-HEAD" "the replayed verdict is the codex one at the opened head"
hasnt "$ghlog" "TRIAGE-WIDENED-NOTHING" "a newer sibling gate's verdict is never replayed under the codex label"
hasnt "$ghlog" "ROUND-STILL-RUNNING" "…nor is a codex round that has not closed"

echo "# no codex verdict at the opened head falls back to the bare signoff line"
store "[$(pre C1b polecat/c1b ',"check.codex":"green@sha-c1b"'),
        $(review rev-c1b closed codex sha-older C1b 2026-08-20T01:00:00Z 'VERDICT: approve STALE-ROUND')]"
echo "sha-c1b" > "$GH_DIR/head_polecat_c1b"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/79"
printf '%s' "$(prrow 79 OPEN polecat/c1b sha-c1b main)" > "$GH_DIR/pr_view_79.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "opened PR#79" "the PR opens on the live green marker"
ghlog=$(cat "$STUB_GH_LOG")
hasnt "$ghlog" "STALE-ROUND" "a codex verdict recorded against another head is not replayed as this one"
has "$ghlog" "Codex signed off pre-open at" "the fallback line stands in for the missing verdict body"

echo "# a head that moved between gate and create refuses the stamp"
store "[$(pre C2 polecat/c2 ',"check.codex":"green@sha-c2"')]"
echo "sha-c2" > "$GH_DIR/head_polecat_c2"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/78"
printf '%s' "$(prrow 78 OPEN polecat/c2 sha-c2-moved main)" > "$GH_DIR/pr_view_78.json"
out=$("$SUT" 2>&1)
has "$out" "not the reviewed 'sha-c2'" "the moved head is refused"
eq "$(meta C2 merge_result)" "pre_open_gate" "nothing stamped; the anchor re-adopts next pass"

echo "# closed-unmerged headstone: supersede at a NEW head"
store "[$(pre D1 polecat/d1 ',"check.codex":"green@sha-d1-new"')]"
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
store "[$(pre D2 polecat/d2 ',"check.codex":"green@sha-d2"')]"
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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
