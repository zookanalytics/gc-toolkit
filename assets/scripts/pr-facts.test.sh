#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-facts.sh — external PR facts, no merge
# authority. Covers: recording an out-of-band merge (never with an empty
# merged_sha); abandoned (+ escalate); retargeted (+ escalate, gate markers
# cleared, human-routed); CONFLICTING -> one rework child per head (dedup on
# branch+head, holds veto, unstamped orphans adopted), classified rebase or
# merge by the head branch and stamped prepare_mode, routed only once that stamp
# reads back; stale-gate -> one
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
cat > "$SD/review-dispatch-body.sh" <<'EMIT'
#!/usr/bin/env bash
cn=""; note=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check-name) cn="${2:-}"; shift 2 ;;
    --note) note="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
echo "METHOD gate=$cn${note:+ note: $note}"
EMIT
chmod +x "$SD/escalate.sh" "$SD/review-dispatch-body.sh"
export STUB_ESC_LOG="$TMP/esc.log"; : > "$STUB_ESC_LOG"
SUT="$SD/pr-facts.sh"
FIX="rig/gc-toolkit.polecat"; REV="rig/gc-toolkit.polecat-codex"
run() { "$SUT" --fix-pool "$FIX" --review-pool "$REV" 2>&1; }

anchor() { # id num extra [branch]
  printf '{"id":"%s","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"%s","pr_url":"https://github.com/zook/gc-toolkit/pull/%s","branch":"%s","merged_target":"main","check_set":"codex","check.codex":"green@sha-%s"%s}}' \
    "$1" "$2" "$2" "${4:-polecat/x$2}" "$2" "${3:-}"
}
prview() { # num state mergeState mergeable extra [headRefName]
  printf '{"state":"%s","isDraft":false,"baseRefName":"main","headRefName":"%s","headRefOid":"sha-%s","headRepository":{"name":"gc-toolkit"},"headRepositoryOwner":{"login":"zook"},"isCrossRepository":false,"mergeStateStatus":"%s","mergeable":"%s","reviewDecision":"","url":"https://github.com/zook/gc-toolkit/pull/%s","mergeCommit":{"oid":"merged-sha-%s"},"autoMergeRequest":null%s}' \
    "$2" "${6:-polecat/x$1}" "$1" "$3" "$4" "$1" "$1" "${5:-}"
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

echo "# …and EVERY declared gate's marker is cleared, not one fused token"
store "[$(anchor F3b 25 ',"check_set":"codex,triage,arch","check.triage":"green@sha-25","check.arch":"green@sha-25"')]"
printf '%s' "$(prview 25 OPEN CLEAN MERGEABLE ',"x":1')" | jq -c '.baseRefName = "release"' > "$GH_DIR/pr_view_25.json"
out=$(run)
eq "$(meta F3b 'check.codex')" "<absent>" "codex's marker is cleared"
eq "$(meta F3b 'check.triage')" "<absent>" "triage's marker is cleared"
eq "$(meta F3b 'check.arch')" "<absent>" "arch's marker is cleared"
has "$(cat "$STUB_ESC_LOG")" "--key pr-retargeted.12" "escalated once per situation key"

echo "# CONFLICTING -> one rework child per head"
store "[$(anchor F4 13)]"
printf '%s' "$(prview 13 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_13.json"
out=$(run)
has "$out" "filed rebase-mode rework new-2 routed to $FIX" "a rework child was filed, classified, and routed"
eq "$(meta new-2 branch)" "polecat/x13" "child carries the branch"
eq "$(meta new-2 target)" "main" "child carries the target"
eq "$(meta new-2 merge_strategy)" "mr" "child is mr-mode"
eq "$(meta new-2 existing_pr)" "https://github.com/zook/gc-toolkit/pull/13" "child reworks THIS PR"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "child routed to the fix pool"
has "$(meta new-2 rejection_reason)" "head sha-13" "the rejection reason names the head (the dedup key)"
eq "$(meta new-2 prepare_mode)" "rebase" "a polecat/* head is classified rebase"
has "$(meta new-2 rejection_reason)" "force-push with --force-with-lease" "…and the work order names the rewrite"
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
has "$out" "a hold is set (operator gate); no rework dispatched" "rebase_hold vetoes the dispatch"

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
has "$out" "adopting unstamped rework orphan new-2" "the next pass adopts the orphan by its deterministic title"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "STILL exactly one rework child — no twin minted"
eq "$(meta new-2 branch)" "polecat/x19" "the adopted orphan is now fully stamped"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and routed to the fix pool"

echo "# …a SHARED head branch is classified merge, never rebase"
store "[$(anchor SB 28 '' 'integration/refinery-fixes')]"
printf '%s' "$(prview 28 OPEN DIRTY CONFLICTING '' 'integration/refinery-fixes')" > "$GH_DIR/pr_view_28.json"
out=$(run)
has "$out" "filed merge-mode rework new-2" "the dispatch names the mode it classified"
eq "$(meta new-2 prepare_mode)" "merge" "an integration/* head is classified merge"
eq "$(bstatus new-2)" "open" "the child was filed"
has "$(jq -r '.[] | select(.id == "new-2") | .title' "$STUB_STORE")" "Merge main into PR#28 (shared branch integration/refinery-fixes)" "the TITLE names the mode an operator would act on by hand"
hasnt "$(meta new-2 rejection_reason)" "force-push with --force-with-lease" "the merge-mode work order must NOT instruct a force-push"
hasnt "$(meta new-2 rejection_reason)" "rebase 'integration" "…nor a rebase"
has "$(meta new-2 rejection_reason)" "MERGING origin/main IN" "…it names the non-destructive remedy instead"
has "$(meta new-2 rejection_reason)" "Do NOT rebase it and do NOT force-push it" "…and forbids the rewrite in words too"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "the merge-mode child is still dispatched, not stalled on a human"

echo "# …a graduation on a polecat-shaped branch is classified merge anyway"
store "[$(anchor GD 29 ',"graduation":"true"')]"
printf '%s' "$(prview 29 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_29.json"
out=$(run)
eq "$(meta new-2 prepare_mode)" "merge" "the graduation marker overrides the branch name"
hasnt "$(meta new-2 rejection_reason)" "force-push with --force-with-lease" "…and the work order follows the mode, not the prefix"

echo "# …a prepare_mode stamp that does not persist leaves the child UNROUTED"
store "[$(anchor DM 31)]"
printf '%s' "$(prview 31 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_31.json"
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:prepare_mode" run)
has "$out" "did not record prepare_mode=rebase; left unrouted" "the lost stamp is caught by the read-back"
eq "$(meta new-2 prepare_mode)" "<absent>" "the stamp really was dropped"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "an unstamped child is inert, never routable AND rewriting"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"

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
d=$(jq -r '.[] | select(.id == "new-2") | .description' "$STUB_STORE")
has "$d" "gate=codex" "the dispatch body names the STALE gate's method, not a fixed one"

echo "# …dedup on second pass"
out=$(run)
hasnt "$out" "filed re-review" "a live review naming the anchor suppresses a twin"

echo "# an exception at a stale head rides the same re-review path as a stale green"
store "[$(anchor F9b 21 ',"check.codex":"exception@sha-OLD"')]"
printf '%s' "$(prview 21 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_21.json"
out=$(run)
has "$out" "check.codex exception@sha-OLD is stale (live head sha-21)" \
  "a head that moved past an exception is re-reviewed, not left terminal"
eq "$(meta new-2 anchor_bead)" "F9b" "the re-review links the anchor"
eq "$(meta new-2 reviewed_oid)" "sha-21" "…and pins the live head"
d=$(jq -r '.[] | select(.id == "new-2") | .description' "$STUB_STORE")
has "$d" "check.codex was exception@sha-OLD" "the dispatch note names the verb that staled, not a hardcoded green@"

echo "# …and an exception AT the live head is still terminal"
store "[$(anchor F9c 22 ',"check.codex":"exception@sha-22"')]"
printf '%s' "$(prview 22 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_22.json"
out=$(run)
hasnt "$out" "filed re-review" "a verdict bound to the live head dispatches nothing"

echo "# a non-codex gate going stale carries ITS method into the re-review"
store "[$(anchor F9d 27 ',"check_set":"codex,triage,arch","check.codex":"green@sha-27","check.triage":"green@sha-27","check.arch":"green@sha-OLD"')]"
printf '%s' "$(prview 27 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_27.json"
out=$(run)
arid=$(jq -r '[.[] | select(.metadata.anchor_bead == "F9d") | .id] | .[0] // ""' "$STUB_STORE")
eq "$(meta "$arid" check_name)" "arch" "the re-review is filed for the gate that went stale"
d=$(jq -r --arg id "$arid" '.[] | select(.id == $id) | .description' "$STUB_STORE")
has "$d" "gate=arch" "…and its body names that gate's method"

echo "# dismissal of our OWN superseded CHANGES_REQUESTED"
store "[$(anchor D1 20)]"
printf '%s' "$(prview 20 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_20.json"
printf '[{"id":901,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_20.json"
: > "$STUB_GH_LOG"
out=$(run)
has "$out" "dismissed our own superseded CHANGES_REQUESTED (review 901)" "the stale own block is dismissed"
eq "$(meta D1 signoff_dismissed)" "901@sha-20" "signoff_dismissed recorded (and read back) first"
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/20/reviews/901/dismissals" "the dismissal hit the pinned endpoint"

echo "# …and a multi-gate check_set still reads all-green"
store "[$(anchor D1b 26 ',"check_set":"codex,triage","check.triage":"green@sha-26"')]"
printf '%s' "$(prview 26 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_26.json"
printf '[{"id":904,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_26.json"
: > "$STUB_GH_LOG"
out=$(run)
has "$(cat "$STUB_GH_LOG")" "reviews/904/dismissals" "two green gates read as all-green (the split is per gate)"

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
