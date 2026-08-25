#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-facts.sh — external PR facts, no merge
# authority. Covers: recording an out-of-band merge (never with an empty
# merged_sha); abandoned (+ escalate); retargeted (+ escalate, gate markers
# cleared, human-routed); CONFLICTING -> one rework child per head (dedup on
# branch+head, holds veto, unstamped orphans adopted); stale-gate -> one
# re-review child per head, carrying mol-review via gc sling --on (dedup,
# pour read-back, fix_target_pool stamped);
# and dismissing our OWN superseded CHANGES_REQUESTED (marker recorded first;
# auto-merge armed skips; a human's review is never dismissed).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-facts.sh" "$HERE/lifecycle.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${STUB_ESC_LOG:?}"\n' > "$SD/escalate.sh"
printf '#!/usr/bin/env bash\necho "METHOD${2:+ note: $2}"\n' > "$SD/review-dispatch-body.sh"
chmod +x "$SD/escalate.sh" "$SD/review-dispatch-body.sh"
export STUB_ESC_LOG="$TMP/esc.log"; : > "$STUB_ESC_LOG"
SUT="$SD/pr-facts.sh"
FIX="rig/gc-toolkit.polecat"; REV="rig/gc-toolkit.polecat-codex"
run() { "$SUT" --fix-pool "$FIX" --review-pool "$REV" 2>&1; }

anchor() { # id num extra
  printf '{"id":"%s","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"%s","pr_url":"https://github.com/zook/gc-toolkit/pull/%s","branch":"polecat/x%s","merged_target":"main","check_set":"codex","check.codex":"green@sha-%s"%s}}' \
    "$1" "$2" "$2" "$2" "$2" "${3:-}"
}
prview() { # num state mergeState mergeable extra
  printf '{"state":"%s","isDraft":false,"baseRefName":"main","headRefName":"polecat/x%s","headRefOid":"sha-%s","headRepository":{"name":"gc-toolkit"},"headRepositoryOwner":{"login":"zook"},"isCrossRepository":false,"mergeStateStatus":"%s","mergeable":"%s","reviewDecision":"","url":"https://github.com/zook/gc-toolkit/pull/%s","mergeCommit":{"oid":"merged-sha-%s"},"autoMergeRequest":null%s}' \
    "$2" "$1" "$1" "$3" "$4" "$1" "$1" "${5:-}"
}

echo "# out-of-band merge is recorded"
store "[$(anchor F1 10)]"
printf '%s' "$(prview 10 MERGED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_10.json"
out=$(run); rc=$?
eq "$rc" 0 "record pass exits 0"
has "$out" "recorded F1 — PR#10 is MERGED" "the merged fact is recorded"
eq "$(bstatus F1)" "closed" "anchor closed"
eq "$(meta F1 merge_result)" "merged" "merge_result=merged"
eq "$(meta F1 merged_sha)" "merged-sha-10" "merged_sha recorded"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "pr-facts never merges"

echo "# closed-unmerged -> abandoned + escalate"
store "[$(anchor F2 11)]"
printf '%s' "$(prview 11 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_11.json"
: > "$STUB_ESC_LOG"
out=$(run)
has "$out" "closed out-of-band; abandoned" "the abandonment is recorded"
eq "$(meta F2 merge_result)" "abandoned" "merge_result=abandoned"
eq "$(bstatus F2)" "open" "the anchor stays OPEN (work did not land)"
eq "$(meta F2 'gc.routed_to')" "human" "routed to human"
eq "$(bassignee F2)" "" "assignee cleared"
has "$(cat "$STUB_ESC_LOG")" "--subject F2 --key pr-abandoned.11" "escalate.sh got the situation key"

echo "# base moved -> retargeted + markers cleared"
store "[$(anchor F3 12)]"
printf '%s' "$(prview 12 OPEN CLEAN MERGEABLE)" | jq -c '.baseRefName = "release"' > "$GH_DIR/pr_view_12.json"
: > "$STUB_ESC_LOG"
out=$(run)
has "$out" "retargeted (base 'release'" "the retarget is recorded"
eq "$(meta F3 merge_result)" "retargeted" "merge_result=retargeted"
eq "$(meta F3 'gc.routed_to')" "human" "routed to human"
eq "$(meta F3 'check.codex')" "<absent>" "the pre-retarget gate marker is cleared"
has "$(cat "$STUB_ESC_LOG")" "--key pr-retargeted.12" "escalated once per situation key"

echo "# CONFLICTING -> one rework child per head"
store "[$(anchor F4 13)]"
printf '%s' "$(prview 13 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_13.json"
out=$(run)
has "$out" "filed rebase new-2 routed to $FIX" "a rework child was filed and routed"
eq "$(meta new-2 branch)" "polecat/x13" "child carries the branch"
eq "$(meta new-2 target)" "main" "child carries the target"
eq "$(meta new-2 merge_strategy)" "mr" "child is mr-mode"
eq "$(meta new-2 existing_pr)" "https://github.com/zook/gc-toolkit/pull/13" "child reworks THIS PR"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "child routed to the fix pool"
has "$(meta new-2 rejection_reason)" "head sha-13" "the rejection reason names the head (the dedup key)"
grep -qxF "new-2|blocks|F4" "$STUB_DEPS" && ok "child blocks the anchor" || bad "blocks edge missing"
eq "$(meta F4 merge_result)" "pull_request" "the anchor keeps gating (no state flip)"

echo "# …dedup: second pass files nothing"
out=$(run)
has "$out" "already covers branch" "an existing child suppresses a twin"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "still exactly one child"

echo "# …a closed child at the SAME head still dedups; holds veto the dispatch"
store "[$(anchor F5 14 ',"rebase_hold":"true"')]"
printf '%s' "$(prview 14 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_14.json"
out=$(run)
has "$out" "a hold is set (operator gate); no rebase dispatched" "rebase_hold vetoes the dispatch"

store "[$(anchor F6 15), {\"id\":\"old-rw\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"branch\":\"polecat/x15\",\"rejection_reason\":\"stale base at head sha-15: ...\"}}]"
printf '%s' "$(prview 15 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_15.json"
out=$(run)
has "$out" "already covers branch" "a closed child at the same head suppresses a re-file"

echo "# …a created-but-unstamped rework orphan is ADOPTED, never twinned"
store "[$(anchor F4b 19)]"
printf '%s' "$(prview 19 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_19.json"
out=$(STUB_DROP_KEYS="new-2:branch,target,rejection_reason,merge_strategy,existing_pr,pr_url,pr_number,gc.routed_to" run)
eq "$(meta new-2 branch)" "<absent>" "first pass left an unstamped orphan (stamp dropped)"
out=$(run)
has "$out" "adopting unstamped rebase orphan new-2" "the next pass adopts the orphan by its deterministic title"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "STILL exactly one rework child — no twin minted"
eq "$(meta new-2 branch)" "polecat/x19" "the adopted orphan is now fully stamped"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and routed to the fix pool"

echo "# an empty mergeCommit read never records an empty merged_sha"
store "[$(anchor F1b 24)]"
printf '%s' "$(prview 24 MERGED CLEAN MERGEABLE)" | jq -c 'del(.mergeCommit)' > "$GH_DIR/pr_view_24.json"
out=$(run)
has "$out" "recording merged_sha=unverified:PR#24" "the degraded record is loud"
eq "$(meta F1b merged_sha)" "unverified:PR#24" "merged_sha is never empty"
eq "$(bstatus F1b)" "closed" "the anchor still closed"

echo "# stale gate -> one re-review child per head, carrying mol-review"
store "[$(anchor F9 18 ',"check.codex":"green@sha-OLD"')]"
printf '%s' "$(prview 18 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_18.json"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "filed re-review new-2 routed to $REV" "a re-review child was filed"
eq "$(meta new-2 task_kind)" "review" "re-review carries task_kind=review"
eq "$(meta new-2 check_name)" "codex" "re-review names the gate"
eq "$(meta new-2 anchor_bead)" "F9" "re-review links the anchor"
eq "$(meta new-2 review_branch)" "polecat/x18" "re-review carries review_branch"
eq "$(meta new-2 reviewed_oid)" "sha-18" "re-review pins the live head (the dedup key, and signoff's verdict binding)"
eq "$(meta new-2 fix_target_pool)" "$FIX" "re-review carries the derived fix pool for the rework path"
eq "$(meta new-2 review_pool)" "$REV" "re-review carries the durable review_pool copy"
has "$(cat "$STUB_GC_LOG")" "sling $REV new-2 --on mol-review" "the review formula is attached by an explicit gc sling --on"
eq "$(meta new-2 'gc.execution_routed_to')" "$REV" "the pour stamped gc.execution_routed_to (the dispatch read-back)"
grep -qxF "new-2|blocks|F9" "$STUB_DEPS" && ok "re-review blocks the anchor" || bad "re-review blocks edge missing"

echo "# …dedup on second pass"
out=$(run)
hasnt "$out" "filed re-review" "a live review naming the anchor suppresses a twin"

echo "# dismissal of our OWN superseded CHANGES_REQUESTED"
store "[$(anchor D1 20)]"
printf '%s' "$(prview 20 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_20.json"
printf '[{"id":901,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_20.json"
: > "$STUB_GH_LOG"
out=$(run)
has "$out" "dismissed our own superseded CHANGES_REQUESTED (review 901)" "the stale own block is dismissed"
eq "$(meta D1 signoff_dismissed)" "901@sha-20" "signoff_dismissed recorded (and read back) first"
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/20/reviews/901/dismissals" "the dismissal hit the pinned endpoint"

echo "# …a human's CHANGES_REQUESTED is never dismissed"
store "[$(anchor D2 21)]"
printf '%s' "$(prview 21 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_21.json"
printf '[{"id":902,"user":{"login":"human1"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_21.json"
: > "$STUB_GH_LOG"
out=$(run)
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "a human's block is left standing"
eq "$(meta D2 signoff_dismissed)" "<absent>" "…and no marker is recorded"

echo "# …native auto-merge armed skips the dismissal"
store "[$(anchor D3 22)]"
printf '%s' "$(prview 22 OPEN BLOCKED MERGEABLE)" \
  | jq -c '.reviewDecision = "CHANGES_REQUESTED" | .autoMergeRequest = {"enabledAt":"x"}' > "$GH_DIR/pr_view_22.json"
printf '[{"id":903,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_22.json"
: > "$STUB_GH_LOG"
out=$(run)
has "$out" "auto-merge is armed" "the armed auto-merge is named"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and nothing is dismissed"

echo "# …marker that does not persist blocks the dismissal"
store "[$(anchor D4 23)]"
printf '%s' "$(prview 23 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_23.json"
printf '[{"id":904,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_23.json"
: > "$STUB_GH_LOG"
out=$(STUB_DROP_KEYS="D4:signoff_dismissed" run)
has "$out" "marker did not persist; NOT dismissing" "an unrecorded marker fails closed"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and the dismissal is withheld"

echo "# identity mismatch records nothing"
store "[$(anchor I1 30)]"
printf '%s' "$(prview 30 MERGED CLEAN MERGEABLE)" | jq -c '.headRepositoryOwner.login = "stranger" | .isCrossRepository = true' > "$GH_DIR/pr_view_30.json"
out=$(run)
has "$out" "identity did not certify" "the foreign head is refused"
eq "$(meta I1 merge_result)" "pull_request" "…and NOTHING was recorded"

echo "# unreadable enumeration fails loudly"
out=$(STUB_LIST_FAIL=1 run); rc=$?
eq "$rc" 1 "an unreadable enumeration exits non-zero"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
