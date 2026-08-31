#!/usr/bin/env bash
# Hermetic test for assets/scripts/merge.sh — the single writer of merged truth.
# Covers: the happy path (pinned read, --squash --match-head-commit, ONE
# lifecycle transition closing with merged_sha); every validate hold in order
# (merge_hold, duplicate anchor + escalate, retarget, non-green gate, unclosed
# child via metadata AND dep edge, tracking_only opt-out, approval arms + veto,
# CLEAN/UNSTABLE handling); the recorded pr_posture hold, read off the anchor;
# identity refusals (fork, url/branch mismatch);
# the terminal full-authorization re-read; and the loud non-zero exit when the
# record half fails after a merge.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/merge.sh" "$HERE/lifecycle.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${STUB_ESC_LOG:?}"\n' > "$SD/escalate.sh"
chmod +x "$SD/escalate.sh"
export STUB_ESC_LOG="$TMP/esc.log"; : > "$STUB_ESC_LOG"
SUT="$SD/merge.sh"

anchor() { # id num extra-json
  printf '{"id":"%s","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"%s","pr_url":"https://github.com/zook/gc-toolkit/pull/%s","branch":"polecat/x%s","merged_target":"main","check_set":"codex","check.codex":"green@sha-%s"%s}}' \
    "$1" "$2" "$2" "$2" "$2" "${3:-}"
}
prview() { # num state mergeState extra-json
  printf '{"state":"%s","isDraft":false,"baseRefName":"main","headRefName":"polecat/x%s","headRefOid":"sha-%s","headRepository":{"name":"gc-toolkit"},"headRepositoryOwner":{"login":"zook"},"isCrossRepository":false,"mergeStateStatus":"%s","mergeable":"MERGEABLE","reviewDecision":"","url":"https://github.com/zook/gc-toolkit/pull/%s","mergeCommit":{"oid":"merged-sha-%s"}%s}' \
    "$2" "$1" "$1" "$3" "$1" "$1" "${4:-}"
}

echo "# happy path"
store "[$(anchor M1 10)]"
printf '%s' "$(prview 10 OPEN CLEAN)" > "$GH_DIR/pr_view_10.json"
echo '[]' > "$GH_DIR/reviews_10.json"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "a clean merge pass exits 0"
has "$out" "merged + recorded M1" "the merge is reported"
ghlog=$(cat "$STUB_GH_LOG")
has "$ghlog" "pr view 10 --repo github.com/zook/gc-toolkit --json state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,reviewDecision,url" "the pinned read asks the exact field set"
has "$ghlog" "pr merge 10 --repo github.com/zook/gc-toolkit --squash --match-head-commit sha-10" "the merge is squash + head-matched"
eq "$(bstatus M1)" "closed" "the anchor closed"
eq "$(meta M1 merge_result)" "merged" "merge_result recorded"
eq "$(meta M1 merged_sha)" "merged-sha-10" "merged_sha recorded from mergeCommit.oid"
has "$(notes M1)" "Merged to main at merged-s" "the close reason names the landing"
eq "$(grep -c '^bd update M1' "$STUB_GC_LOG" || true)" "1" "ONE lifecycle update carried close+record"

echo "# merge_hold"
store "[$(anchor M2 11 ',"merge_hold":"true"')]"
printf '%s' "$(prview 11 OPEN CLEAN)" > "$GH_DIR/pr_view_11.json"
echo '[]' > "$GH_DIR/reviews_11.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "merge_hold set (operator gate); merge held" "merge_hold holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

echo "# one-anchor-per-PR holds + escalates once"
store "[$(anchor M3 12), $(anchor M3b 12)]"
printf '%s' "$(prview 12 OPEN CLEAN)" > "$GH_DIR/pr_view_12.json"
echo '[]' > "$GH_DIR/reviews_12.json"
: > "$STUB_GH_LOG"; : > "$STUB_ESC_LOG"
out=$("$SUT" 2>&1)
has "$out" "claimed by more than one open anchor" "the duplicate holds every anchor"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "no merge under a duplicate claim"
has "$(cat "$STUB_ESC_LOG")" "--subject M3 --key one-anchor-per-pr.12" "escalate.sh got the situation key"

echo "# retarget holds"
store "[$(anchor M4 13)]"
printf '%s' "$(prview 13 OPEN CLEAN)" | jq -c '.baseRefName = "release"' > "$GH_DIR/pr_view_13.json"
echo '[]' > "$GH_DIR/reviews_13.json"
out=$("$SUT" 2>&1)
has "$out" "base 'release' != merged_target 'main'" "a retargeted PR holds"

echo "# gate not green at the live head holds"
store "[$(anchor M5 14 ',"check.codex":"green@stale"' )]"
printf '%s' "$(prview 14 OPEN CLEAN)" > "$GH_DIR/pr_view_14.json"
echo '[]' > "$GH_DIR/reviews_14.json"
out=$("$SUT" 2>&1)
has "$out" "check 'codex' not green at live head" "a stale marker holds"

echo "# fixable and exception hold too"
store "[$(anchor M5b 15 ',"check.codex":"fixable@sha-15"')]"
printf '%s' "$(prview 15 OPEN CLEAN)" > "$GH_DIR/pr_view_15.json"
echo '[]' > "$GH_DIR/reviews_15.json"
out=$("$SUT" 2>&1)
has "$out" "check 'codex' not green" "fixable@ holds the merge"

echo "# unclosed children hold: metadata key, dep edge, tracking_only opt-out"
store "[$(anchor M6 16), {\"id\":\"rw-1\",\"status\":\"blocked\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"pr_number\":\"16\"}}]"
printf '%s' "$(prview 16 OPEN CLEAN)" > "$GH_DIR/pr_view_16.json"
echo '[]' > "$GH_DIR/reviews_16.json"
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead rw-1 (blocked)" "a pr_number child holds (blocked counts)"

store "[$(anchor M7 17), {\"id\":\"rw-2\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"merge_result\":\"pre_open_gate\"}}]"
printf '%s' "$(prview 17 OPEN CLEAN)" > "$GH_DIR/pr_view_17.json"
echo '[]' > "$GH_DIR/reviews_17.json"
printf 'rw-2|blocks|M7\n' > "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead rw-2" "a dep-edge blocker holds even carrying merge_result"

store "[$(anchor M8 18), {\"id\":\"trk-1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"pr_number\":\"18\",\"tracking_only\":\"true\"}}]"
printf '%s' "$(prview 18 OPEN CLEAN)" > "$GH_DIR/pr_view_18.json"
echo '[]' > "$GH_DIR/reviews_18.json"
: > "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded M8" "a tracking_only pr_number reference does not hold"

# The comment arm's visit path holds the merge through this probe and nothing
# else: escalate.sh files the visit DEPENDING on its subject, so a blocks edge
# back would be a cycle, and pr_number is what is left to hold on.
store "[$(anchor M9 19), {\"id\":\"vis-1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"pr_number\":\"19\",\"task_kind\":\"visit\",\"anchor_bead\":\"M9\"}}]"
printf '%s' "$(prview 19 OPEN CLEAN)" > "$GH_DIR/pr_view_19.json"
echo '[]' > "$GH_DIR/reviews_19.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead vis-1" "an open visit stamped with the PR holds the merge"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 19" "…and nothing merged"
store "[$(anchor M9b 20), {\"id\":\"vis-2\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"pr_number\":\"20\",\"task_kind\":\"visit\",\"anchor_bead\":\"M9b\"}}]"
printf '%s' "$(prview 20 OPEN CLEAN)" > "$GH_DIR/pr_view_20.json"
echo '[]' > "$GH_DIR/reviews_20.json"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded M9b" "closing the visit is the release, and it performs"

echo "# approval arms"
store "[$(anchor A1 20 ',"check_set":"codex,approval","check.codex":"green@sha-20"')]"
printf '%s' "$(prview 20 OPEN CLEAN)" > "$GH_DIR/pr_view_20.json"
echo '[]' > "$GH_DIR/reviews_20.json"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review at the live head" "check_set approval with no review holds"

printf '[{"user":{"login":"human1"},"state":"APPROVED","commit_id":"sha-20","submitted_at":"2026-08-20T01:00:00Z","id":1}]' > "$GH_DIR/reviews_20.json"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded A1" "an external APPROVED at the live head satisfies it"

printf '[{"user":{"login":"human1"},"state":"APPROVED","commit_id":"sha-OLD","submitted_at":"2026-08-20T01:00:00Z","id":1}]' > "$GH_DIR/reviews_20.json"
store "[$(anchor A1 20 ',"check_set":"codex,approval","check.codex":"green@sha-20"')]"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review at the live head" "an approval of an OLD head does not count"

printf '[{"user":{"login":"gc-city-bot"},"state":"APPROVED","commit_id":"sha-20","submitted_at":"2026-08-20T01:00:00Z","id":1}]' > "$GH_DIR/reviews_20.json"
store "[$(anchor A1 20 ',"check_set":"codex,approval","check.codex":"green@sha-20"')]"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review" "a self-approval never counts"

echo "# signoff_dismissed and an own DISMISSED review arm the requirement"
store "[$(anchor A2 21 ',"signoff_dismissed":"r9@sha-21"')]"
printf '%s' "$(prview 21 OPEN CLEAN)" > "$GH_DIR/pr_view_21.json"
echo '[]' > "$GH_DIR/reviews_21.json"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review" "signoff_dismissed arms the approval requirement"

store "[$(anchor A3 22)]"
printf '%s' "$(prview 22 OPEN CLEAN)" > "$GH_DIR/pr_view_22.json"
printf '[{"user":{"login":"gc-city-bot"},"state":"DISMISSED","commit_id":"sha-old","submitted_at":"2026-08-19T00:00:00Z","id":1}]' > "$GH_DIR/reviews_22.json"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review" "our own DISMISSED review arms it from the GitHub side"

echo "# a standing CHANGES_REQUESTED vetoes every candidate"
store "[$(anchor A4 23)]"
printf '%s' "$(prview 23 OPEN CLEAN)" > "$GH_DIR/pr_view_23.json"
printf '[{"user":{"login":"human2"},"state":"CHANGES_REQUESTED","commit_id":"sha-old","submitted_at":"2026-08-19T00:00:00Z","id":1}]' > "$GH_DIR/reviews_23.json"
out=$("$SUT" 2>&1)
has "$out" "standing CHANGES_REQUESTED" "the veto holds a codex-only anchor too"

echo "# mergeStateStatus"
store "[$(anchor U1 30)]"
printf '%s' "$(prview 30 OPEN BLOCKED)" > "$GH_DIR/pr_view_30.json"
echo '[]' > "$GH_DIR/reviews_30.json"
out=$("$SUT" 2>&1)
has "$out" "not mergeable yet (mergeStateStatus='BLOCKED')" "BLOCKED holds"

store "[$(anchor U2 31)]"
printf '%s' "$(prview 31 OPEN UNSTABLE ',"statusCheckRollup":[]')" > "$GH_DIR/pr_view_31.json"
echo '[]' > "$GH_DIR/reviews_31.json"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded U2" "UNSTABLE with zero required contexts proceeds"

store "[$(anchor U3 32)]"
printf '%s' "$(prview 32 OPEN UNSTABLE ',"statusCheckRollup":[{"name":"ci","conclusion":"FAILURE"}]')" > "$GH_DIR/pr_view_32.json"
echo '[]' > "$GH_DIR/reviews_32.json"
printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"ci"}]}}]' > "$GH_DIR/rules_main.json"
out=$("$SUT" 2>&1)
has "$out" "a REQUIRED check is not green" "UNSTABLE with a red required check holds"
rm -f "$GH_DIR/rules_main.json"

echo "# identity refusals"
store "[$(anchor I1 40)]"
printf '%s' "$(prview 40 OPEN CLEAN)" | jq -c '.headRepositoryOwner.login = "stranger" | .isCrossRepository = true' > "$GH_DIR/pr_view_40.json"
echo '[]' > "$GH_DIR/reviews_40.json"
out=$("$SUT" 2>&1)
has "$out" "not this repository's own branch; merge held" "a fork head is refused"

store "[$(anchor I2 41)]"
printf '%s' "$(prview 41 OPEN CLEAN)" | jq -c '.headRefName = "other/branch"' > "$GH_DIR/pr_view_41.json"
echo '[]' > "$GH_DIR/reviews_41.json"
out=$("$SUT" 2>&1)
has "$out" "records branch 'polecat/x41' but PR#41 is opened from 'other/branch'" "a head-branch mismatch is refused"

echo "# terminal re-read holds on a mid-pass write"
store "[$(anchor T1 50)]"
printf '%s' "$(prview 50 OPEN CLEAN)" > "$GH_DIR/pr_view_50.json"
echo '[]' > "$GH_DIR/reviews_50.json"
# The gh stub runs AFTER the fresh re-read: model the mid-pass write by having
# the reviews file swap the marker via a hook — instead, simplest: drop the
# check marker between reads is not injectable, so assert the hold via
# merge_hold appearing only in the terminal read using STUB_DROP_KEYS inverse:
# store the hold from the start but drop it from the FIRST update path is not a
# read; so exercise the re-read by pre-setting a hold the early gate misses is
# impossible — covered instead by asserting the re-read HAPPENS:
: > "$STUB_GC_LOG"
out=$("$SUT" 2>&1)
shows=$(grep -c '^bd show T1' "$STUB_GC_LOG" || true)
[ "$shows" -ge 2 ] && ok "the anchor is re-read at least twice (validation + terminal)" \
                   || bad "expected >=2 anchor reads, got $shows"
has "$out" "merged + recorded T1" "…and a clean pass still merges"

echo "# record failure after a merge exits non-zero loudly"
store "[$(anchor R1 60)]"
printf '%s' "$(prview 60 OPEN CLEAN)" > "$GH_DIR/pr_view_60.json"
echo '[]' > "$GH_DIR/reviews_60.json"
out=$(STUB_UPDATE_FAIL="R1" "$SUT" 2>&1); rc=$?
eq "$rc" 1 "a failed record exits non-zero"
has "$out" "MERGED but the lifecycle record FAILED" "…and says the PR did land"
has "$(cat "$STUB_GH_LOG")" "pr merge 60" "the merge itself was performed"

echo "# non-OPEN and draft PRs are pr-facts' business"
store "[$(anchor S1 70)]"
printf '%s' "$(prview 70 MERGED CLEAN)" > "$GH_DIR/pr_view_70.json"
out=$("$SUT" 2>&1)
has "$out" "1 skipped" "a merged PR is skipped (the skill only merges)"

echo "# empty/absent check_set holds (empty is never the 'none' opt-out)"
store '[{"id":"E1","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"80","pr_url":"https://github.com/zook/gc-toolkit/pull/80","branch":"polecat/x80","merged_target":"main"}}]'
printf '%s' "$(prview 80 OPEN CLEAN)" > "$GH_DIR/pr_view_80.json"
echo '[]' > "$GH_DIR/reviews_80.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "no normalized check_set" "an anchor with no check_set holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged ungated"
store '[{"id":"E2","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"81","pr_url":"https://github.com/zook/gc-toolkit/pull/81","branch":"polecat/x81","merged_target":"main","check_set":" , "}}]'
printf '%s' "$(prview 81 OPEN CLEAN)" > "$GH_DIR/pr_view_81.json"
echo '[]' > "$GH_DIR/reviews_81.json"
out=$("$SUT" 2>&1)
has "$out" "no normalized check_set" "a whitespace-only check_set holds too"
store '[{"id":"E3","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"82","pr_url":"https://github.com/zook/gc-toolkit/pull/82","branch":"polecat/x82","merged_target":"main","check_set":"none"}}]'
printf '%s' "$(prview 82 OPEN CLEAN)" > "$GH_DIR/pr_view_82.json"
echo '[]' > "$GH_DIR/reviews_82.json"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded E3" "the explicit 'none' sentinel still opts out"

echo "# empty mergeCommit read never records an empty merged_sha"
store "[$(anchor V1 61)]"
printf '%s' "$(prview 61 OPEN CLEAN)" | jq -c 'del(.mergeCommit)' > "$GH_DIR/pr_view_61.json"
echo '[]' > "$GH_DIR/reviews_61.json"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "the pass still exits 0 (the merge itself landed)"
has "$out" "recording merged_sha=unverified:PR#61" "the degraded record is loud"
eq "$(meta V1 merged_sha)" "unverified:PR#61" "merged_sha is never empty"
eq "$(bstatus V1)" "closed" "the anchor still closed"

echo '# a recorded commented posture holds the merge'
store "[$(anchor C1 70 ',"pr_posture":"commented@sha-70"')]"
printf '%s' "$(prview 70 OPEN CLEAN)" > "$GH_DIR/pr_view_70.json"
echo '[]' > "$GH_DIR/reviews_70.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "carries review comments nothing has answered (commented@sha-70); merge held" "the posture read off the anchor holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 70" "…and nothing merged"
hasnt "$(cat "$STUB_GH_LOG")" "pulls/70/comments" "…without merge.sh asking GitHub anything about it"
eq "$(bstatus C1)" "open" "the anchor was not closed"

echo "# …a posture pinned to an OLD head still holds — a comment survives a head move"
store "[$(anchor C2 71 ',"pr_posture":"commented@sha-STALE"')]"
printf '%s' "$(prview 71 OPEN CLEAN)" > "$GH_DIR/pr_view_71.json"
echo '[]' > "$GH_DIR/reviews_71.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "commented@sha-STALE); merge held" "the hold is not head-matched"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 71" "…and nothing merged"

echo "# …every other posture, and an ABSENT one, merge as before"
store "[$(anchor C3 72 ',"pr_posture":"approved@sha-72"')]"
printf '%s' "$(prview 72 OPEN CLEAN)" > "$GH_DIR/pr_view_72.json"
echo '[]' > "$GH_DIR/reviews_72.json"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded C3" "an approved posture does not hold"
store "[$(anchor C4 73)]"
printf '%s' "$(prview 73 OPEN CLEAN)" > "$GH_DIR/pr_view_73.json"
echo '[]' > "$GH_DIR/reviews_73.json"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded C4" "an absent posture is a fact not yet recorded, never a hold"

echo "# …a comment landing mid-pass is caught by the terminal re-read"
store "[$(anchor C5 74)]"
printf '%s' "$(prview 74 OPEN CLEAN)" > "$GH_DIR/pr_view_74.json"
echo '[]' > "$GH_DIR/reviews_74.json"
PHOOK_COUNT="$TMP/phookcount"; : > "$PHOOK_COUNT"
cat > "$TMP/phook.sh" <<HOOK
#!/usr/bin/env bash
# Records the posture on C5 immediately before its SECOND read (the terminal
# re-read): the validation read saw none, so only the re-read can catch it.
[ "\${1:-}" = "C5" ] || exit 0
n=\$(cat "$PHOOK_COUNT" 2>/dev/null || echo 0); n=\$((n + 1)); printf '%s' "\$n" > "$PHOOK_COUNT"
if [ "\$n" = 2 ]; then
  tmp=\$(mktemp)
  jq -c 'map(if .id == "C5" then .metadata.pr_posture = "commented@sha-74" else . end)' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
fi
HOOK
chmod +x "$TMP/phook.sh"
: > "$STUB_GH_LOG"
out=$(STUB_SHOW_HOOK="$TMP/phook.sh" "$SUT" 2>&1)
has "$out" "review comments went unanswered after validation; merge held" "the terminal re-read caught the mid-pass comment"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 74" "…and the merge was withheld"
eq "$(bstatus C5)" "open" "the anchor was not closed"

echo "# terminal re-read HOLDS on a real mid-pass write (hook mutates the store)"
store "[$(anchor T2 51)]"
printf '%s' "$(prview 51 OPEN CLEAN)" > "$GH_DIR/pr_view_51.json"
echo '[]' > "$GH_DIR/reviews_51.json"
HOOK_COUNT="$TMP/hookcount"; : > "$HOOK_COUNT"
cat > "$TMP/hook.sh" <<HOOK
#!/usr/bin/env bash
# Sets merge_hold on T2 immediately before its SECOND read (the terminal
# re-read) — the validation read saw no hold, so only the re-read can catch it.
[ "\${1:-}" = "T2" ] || exit 0
n=\$(cat "$HOOK_COUNT" 2>/dev/null || echo 0); n=\$((n + 1)); printf '%s' "\$n" > "$HOOK_COUNT"
if [ "\$n" = 2 ]; then
  tmp=\$(mktemp)
  jq -c 'map(if .id == "T2" then .metadata.merge_hold = "true" else . end)' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
fi
HOOK
chmod +x "$TMP/hook.sh"
: > "$STUB_GH_LOG"
out=$(STUB_SHOW_HOOK="$TMP/hook.sh" "$SUT" 2>&1)
has "$out" "merge_hold was set after validation; merge held" "the terminal re-read caught the mid-pass hold"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 51" "…and the merge was withheld"
eq "$(bstatus T2)" "open" "the anchor was not closed"

echo "# generated-artifact freshness at the merge result"
# The arm exists because generated/seed-audit is rendered from the whole source
# tree and committed per branch: a PR carrying a render made at an older base
# overwrites inputs it never saw, and every other gate here is head-keyed, so
# nothing else notices the base moving underneath.
RENDER_LOG="$TMP/render.log"; : > "$RENDER_LOG"
cat > "$SD/render-seed-audit.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$RENDER_LOG"
printf '%s\n' "\${STUB_RENDER_OUT:-seed audit is current}"
exit "\${STUB_RENDER_RC:-0}"
STUB
chmod +x "$SD/render-seed-audit.sh"
export STUB_RENDER_RC=0 STUB_RENDER_OUT=""
mkdir -p "$TMP/repo/generated/seed-audit"; printf 'name = "t"\n' > "$TMP/repo/pack.toml"
export STUB_TOPLEVEL="$TMP/repo" STUB_FETCHED_HEAD="sha-80"

store "[$(anchor S0 80)]"
printf '%s' "$(prview 80 OPEN CLEAN)" > "$GH_DIR/pr_view_80.json"
echo '[]' > "$GH_DIR/reviews_80.json"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded S0" "a repository carrying no rendered audit merges"
eq "$(wc -c < "$RENDER_LOG" | tr -d ' ')" "0" "…and the freshness probe never ran"

: > "$TMP/repo/generated/seed-audit/INDEX.md"
store "[$(anchor S1 81)]"
printf '%s' "$(prview 81 OPEN CLEAN)" > "$GH_DIR/pr_view_81.json"
echo '[]' > "$GH_DIR/reviews_81.json"
export STUB_FETCHED_HEAD="sha-81"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded S1" "a current merge result merges"
has "$(cat "$RENDER_LOG")" "--check-merge refs/gc-toolkit/merge-gate/base refs/gc-toolkit/merge-gate/head" \
  "…and the question was asked of the merge, in the probe's own ref namespace"

store "[$(anchor S2 82)]"
printf '%s' "$(prview 82 OPEN CLEAN)" > "$GH_DIR/pr_view_82.json"
echo '[]' > "$GH_DIR/reviews_82.json"
export STUB_FETCHED_HEAD="sha-82" STUB_RENDER_RC=1 STUB_RENDER_OUT="seed audit would be STALE at the merge"
: > "$STUB_GH_LOG"; : > "$STUB_ESC_LOG"
out=$("$SUT" 2>&1)
has "$out" "would land a stale generated/seed-audit; merge held" "a stale merge result holds"
has "$out" "seed audit would be STALE at the merge" "…quoting what the renderer found"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"
has "$(cat "$STUB_ESC_LOG")" "--key seed-audit-merge-gate.82" "…and one visit carries the situation to a human"
has "$(cat "$STUB_ESC_LOG")" "PR#82 would land a stale generated/seed-audit; the merge is held." \
  "…whose first line is a headline, since escalate.sh titles the visit from it"
has "$(cat "$STUB_ESC_LOG")" "seed audit would be STALE at the merge" "…carrying the renderer's own diagnosis"
eq "$(bstatus S2)" "open" "the anchor stays open"

store "[$(anchor S3 83)]"
printf '%s' "$(prview 83 OPEN CLEAN)" > "$GH_DIR/pr_view_83.json"
echo '[]' > "$GH_DIR/reviews_83.json"
export STUB_FETCHED_HEAD="sha-83" STUB_RENDER_RC=2 STUB_RENDER_OUT="cannot tell"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "freshness could not be determined; merge held" "an unanswerable probe holds rather than passing"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

store "[$(anchor S4 84)]"
printf '%s' "$(prview 84 OPEN CLEAN)" > "$GH_DIR/pr_view_84.json"
echo '[]' > "$GH_DIR/reviews_84.json"
export STUB_RENDER_RC=0 STUB_FETCH_RC=1
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "could not fetch 'main' and 'polecat/x84'" "an unreachable remote holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

store "[$(anchor S5 85)]"
printf '%s' "$(prview 85 OPEN CLEAN)" > "$GH_DIR/pr_view_85.json"
echo '[]' > "$GH_DIR/reviews_85.json"
export STUB_FETCH_RC="" STUB_FETCHED_HEAD="sha-moved"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "head moved during the freshness probe (fetched 'sha-moved', validated 'sha-85')" \
  "a head that moved under the probe holds rather than answering about the wrong tree"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"
export STUB_TOPLEVEL="" STUB_FETCHED_HEAD=""

# --- the machine axis (lifecycle/lifecycle.toml [machine_axis]) ------------------
# Every hold above already decides what the cadence can do next and spends the
# answer on a log line. These assert that the answer is kept, so a reader learns
# whether an anchor is moving without re-implementing these predicates.
machine() { printf '%s' "$(meta "$1" pr.machine)"; }
pinned()  { local v; v="$(machine "$1")"; case "$v" in *@*@*) printf '%s' "${v%@*}" ;; *) printf '%s' "$v" ;; esac; }

echo "# machine axis: a standing veto is a wedge only once the round cap is spent"
# The live shape of the seventh wedged anchor: gates green at the live head, a
# non-city CHANGES_REQUESTED standing, and the signoff round cap spent, so
# nothing will file further rework and nothing reads the review to decide
# whether it was answered.
store "[$(anchor V1 80),
        {\"id\":\"rw-v1a\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"source_review_bead\":\"rev-a\"}},
        {\"id\":\"rw-v1b\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"source_review_bead\":\"rev-b\"}},
        {\"id\":\"rw-v1c\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"source_review_bead\":\"rev-c\"}}]"
printf 'rw-v1a|blocks|V1\nrw-v1b|blocks|V1\nrw-v1c|blocks|V1\n' > "$STUB_DEPS"
printf '%s' "$(prview 80 OPEN CLEAN)" > "$GH_DIR/pr_view_80.json"
printf '[{"user":{"login":"human2"},"state":"CHANGES_REQUESTED","commit_id":"sha-old","submitted_at":"2026-08-19T00:00:00Z","id":1}]' > "$GH_DIR/reviews_80.json"
out=$("$SUT" 2>&1)
has "$out" "standing CHANGES_REQUESTED" "the veto still holds"
has "$out" "rework rounds 3/3" "…and the pass names the round count it decided on"
eq "$(pinned V1)" "wedged-veto@sha-80" "a veto past the cap records the veto wedge"
case "$(machine V1)" in
  *@*@20[0-9][0-9]-*Z) ok "…dated at the turn it began" ;;
  *) bad "no @<since> component: '$(machine V1)'" ;;
esac

echo "# …and under the cap it is a hold something will still answer"
store "[$(anchor V2 81),
        {\"id\":\"rw-v2a\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"source_review_bead\":\"rev-a\"}}]"
printf 'rw-v2a|blocks|V2\n' > "$STUB_DEPS"
printf '%s' "$(prview 81 OPEN CLEAN)" > "$GH_DIR/pr_view_81.json"
printf '[{"user":{"login":"human2"},"state":"CHANGES_REQUESTED","commit_id":"sha-old","submitted_at":"2026-08-19T00:00:00Z","id":1}]' > "$GH_DIR/reviews_81.json"
out=$("$SUT" 2>&1)
eq "$(pinned V2)" "progressing@sha-81" "a veto under the cap is progressing — signoff can still file rework"

echo "# a gate the head moved past is progressing; the cap's exception is the wedge"
store "[$(anchor V3 82 ',"check.codex":"green@sha-STALE"'),
        $(anchor V4 83 ',"check.codex":"exception@sha-83","gc.routed_to":"human"')]"
: > "$STUB_DEPS"
printf '%s' "$(prview 82 OPEN CLEAN)" > "$GH_DIR/pr_view_82.json"
printf '%s' "$(prview 83 OPEN CLEAN)" > "$GH_DIR/pr_view_83.json"
echo '[]' > "$GH_DIR/reviews_82.json"
echo '[]' > "$GH_DIR/reviews_83.json"
out=$("$SUT" 2>&1)
eq "$(pinned V3)" "progressing@sha-82" "a marker the head moved past is a gate a review is due to raise"
eq "$(pinned V4)" "wedged-exception@sha-83" "exception@<live head> is the convergence cap's wedge"

echo "# gates green and waiting on a person: settled, not wedged"
store "[$(anchor V5 84 ',"check_set":"codex,approval","check.codex":"green@sha-84"')]"
printf '%s' "$(prview 84 OPEN CLEAN)" > "$GH_DIR/pr_view_84.json"
echo '[]' > "$GH_DIR/reviews_84.json"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review" "the approval hold fires"
eq "$(pinned V5)" "settled@sha-84" "the cadence is done; the pull request waits on an approval"

echo "# recording a verdict moves no route"
store "[$(anchor V8 87 ',"check.codex":"exception@sha-87","gc.routed_to":"human"')]"
: > "$STUB_DEPS"
printf '%s' "$(prview 87 OPEN CLEAN)" > "$GH_DIR/pr_view_87.json"
echo '[]' > "$GH_DIR/reviews_87.json"
out=$("$SUT" 2>&1)
eq "$(pinned V8)" "wedged-exception@sha-87" "the verdict is recorded"
eq "$(meta V8 'gc.routed_to')" "human" "…and the anchor keeps the park route the cap gave it"

echo "# an open blocker is progressing only when a POOL is behind it"
store "[$(anchor V6 85),
        {\"id\":\"rw-v6\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"gc.routed_to\":\"rig/gc-toolkit.polecat\"}},
        $(anchor V7 86),
        {\"id\":\"dm-v7\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"gc.routed_to\":\"human\"}}]"
printf 'rw-v6|blocks|V6\ndm-v7|blocks|V7\n' > "$STUB_DEPS"
printf '%s' "$(prview 85 OPEN CLEAN)" > "$GH_DIR/pr_view_85.json"
printf '%s' "$(prview 86 OPEN CLEAN)" > "$GH_DIR/pr_view_86.json"
echo '[]' > "$GH_DIR/reviews_85.json"
echo '[]' > "$GH_DIR/reviews_86.json"
out=$("$SUT" 2>&1)
eq "$(pinned V6)" "progressing@sha-85" "a pool-routed rework child is an actor that will act"
# The demand bead that makes an anchor `asking` blocks it the same way and has
# no automated actor behind it, so it must not read as the machine working.
eq "$(machine V7)" "<absent>" "a demand bead blocking the anchor is not the machine progressing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
