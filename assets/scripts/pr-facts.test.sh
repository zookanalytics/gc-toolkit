#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-facts.sh — external PR facts, no merge
# authority. Covers: recording an out-of-band merge (never with an empty
# merged_sha); abandoned (+ escalate); retargeted (+ escalate, gate markers
# cleared, human-routed); CONFLICTING -> one rework child per head (dedup on
# branch+head, holds veto, unstamped orphans adopted), classified rebase or
# merge by the head branch and stamped prepare_mode, counted as dispatched only
# once that stamp AND the route read back, with a child stranded by a lost route
# stamp re-routed rather than buried by the dedup; stale-gate -> one
# re-review child per head, carrying mol-review via gc sling --on (dedup,
# pour read-back, fix_target_pool stamped);
# and dismissing our OWN superseded CHANGES_REQUESTED (marker recorded first;
# auto-merge armed skips; a human's review is never dismissed).
# Also covers --posture-only (the pre-merge arm: records posture, dispatches
# nothing, leaves MERGED/CLOSED reconciliation to the full pass, and reports an
# anchor it could not make current in its EXIT CODE, which is what holds
# merge.sh for that pass);
# Also covers the POSTURE record and the comment watermark: the declared
# vocabulary, posture pinned to the live head and written only on change, an
# unanswered comment routing to a fix-pool child or (under a human hold) to a
# visit, the watermark advancing only after both that child's mode and its route
# read back, a comment above the mark re-firing while one below it stays
# answered, and the reads that record nothing rather than clear a standing
# `commented`.
# Also covers the review-round cap reset such a batch performs: once per batch,
# retiring the dispatch tally and the cap's own park with it, while a park no
# `signoff_cap` claims, a live takeaway, a verdict the city posted itself, and a
# rework hand-back each leave the cap standing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# The value@oid half of a dated key. pr_posture carries a third @<since>
# component, stamped by lifecycle.sh under compare-and-preserve: an unmet
# approval requirement is one of the causes that start the owed clock the helm
# board ranks its queue by, so the recorded posture has to date its own turn.
# Assertions about WHAT was recorded and at which head read through this; the
# instant has its own coverage at the end of the posture section.
meta_pinned() { local v; v="$(meta "$1" "$2")"; case "$v" in *@*@*) printf '%s' "${v%@*}" ;; *) printf '%s' "$v" ;; esac; }

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-facts.sh" "$HERE/lifecycle.sh"
# escalate.sh's contract, not just its call log: ONE visit per subject+key,
# stamped so the caller can find it again. pr-facts reads the visit back to
# block the anchor on it, so a stub that only logged would test nothing.
cat > "$SD/escalate.sh" <<'ESC'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_ESC_LOG:?}"
subj=""; key=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) shift; subj="${1:-}" ;;
    --key)     shift; key="${1:-}" ;;
  esac
  shift || true
done
[ -n "$subj" ] && [ -n "$key" ] || exit 2
have=$(jq -r --arg s "$subj" --arg k "$key" '
  [ .[] | select((.status // "open") != "closed")
    | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
    | select(((.metadata.escalation_key // "") | tostring) == $k) | .id ] | .[0] // empty' "${STUB_STORE:?}")
[ -n "$have" ] && exit 0
vid=$(gc bd create "visit: $subj — $key" -t task --json | jq -r '.id // empty')
[ -n "$vid" ] || exit 1
gc bd update "$vid" --set-metadata "escalation_key=$key" \
  --set-metadata "gc.continuation_group=$subj" --set-metadata "task_kind=visit" >/dev/null
gc bd dep add "$vid" "$subj" --type=tracks >/dev/null 2>&1 || true
ESC
printf '#!/usr/bin/env bash\necho "METHOD${2:+ note: $2}"\n' > "$SD/review-dispatch-body.sh"
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

ROOT="$(cd "$HERE/../.." && pwd)"

echo "# posture vocabulary drift against lifecycle.toml"
BLOCK="$(awk '/# >>> pr-posture-vocabulary/{f=1;next} /# <<< pr-posture-vocabulary/{f=0} f' "$HERE/pr-facts.sh")"
[ -n "$BLOCK" ] && ok "posture-vocabulary block extracted" || bad "posture-vocabulary markers missing"
eval "$BLOCK"
TOML_POSTURES=$(sed -n 's/^postures = \[\(.*\)\]/\1/p' "$ROOT/lifecycle/lifecycle.toml" | tr -d '",' | sed 's/^ *//;s/ *$//' | tr -s ' ')
eq "$PR_POSTURES" "$TOML_POSTURES" "postures match lifecycle.toml [posture]"

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

echo "# …a route stamp that does not persist leaves the rework UNDISPATCHED"
store "[$(anchor RT 32)]"
printf '%s' "$(prview 32 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_32.json"
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:gc.routed_to" run)
eq "$(meta new-2 'gc.routed_to')" "<absent>" "the route stamp really was dropped"
has "$out" "did not record gc.routed_to=$FIX; left unrouted" "the lost route stamp is caught by a read-back"
hasnt "$out" "filed rebase-mode rework new-2 routed to" "an unreachable rework is never reported as dispatched"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"

echo "# …and the NEXT pass re-routes it, past the branch dedup that would bury it"
out=$(run)
has "$out" "re-routing stranded rework new-2" "the stranded child is adopted, not suppressed as a dup"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and the route lands on the retry"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "…with no twin minted"
has "$out" "filed rebase-mode rework new-2 routed to $FIX" "…and only now is the dispatch reported"

echo "# …once routed, the child dedups normally again"
out=$(run)
has "$out" "already covers branch" "a routed child suppresses a twin as before"

echo "# …a stranded rework a polecat has since claimed is never re-stamped under them"
held='{"id":"held-rw","status":"in_progress","assignee":"rig/gc-toolkit.polecat-2","notes":"",'
held="$held"'"title":"Rebase PR#33 onto main: base rewritten, PR conflicts",'
held="$held"'"metadata":{"branch":"polecat/x33","rejection_reason":"stale base at head sha-33: x"}}'
store "[$(anchor RT2 33), $held]"
printf '%s' "$(prview 33 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_33.json"
out=$(run)
has "$out" "already covers branch" "a claimed child still suppresses the arm"
eq "$(meta held-rw 'gc.routed_to')" "<absent>" "…and nothing is written under the holder"

echo "# …a strand never overrides a LIVE sibling's claim on the force-push"
strand='{"id":"strand-rw","status":"open","assignee":"","notes":"",'
strand="$strand"'"title":"Rebase PR#34 onto main: base rewritten, PR conflicts",'
strand="$strand"'"metadata":{"branch":"polecat/x34","rejection_reason":"stale base at head sha-34: x"}}'
livesib='{"id":"live-rw","status":"in_progress","assignee":"rig/gc-toolkit.polecat-3","notes":"",'
livesib="$livesib"'"title":"Rebase PR#34 onto main: base rewritten, PR conflicts",'
livesib="$livesib"'"metadata":{"branch":"polecat/x34","rejection_reason":"stale base at head sha-old: x"}}'
# The strand is listed FIRST: it is open, so it matches the dedup's live arm and
# would be the one picked as the dup — the veto must not depend on that order.
store "[$strand, $livesib, $(anchor RT3 34)]"
printf '%s' "$(prview 34 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_34.json"
out=$(run)
has "$out" "rework live-rw already covers branch" "the live sibling still vetoes, strand or no strand"
has "$out" "unrouted sibling strand-rw is redundant" "…and the unreachable strand is named, not silently left"
eq "$(meta strand-rw 'gc.routed_to')" "<absent>" "…the strand is NOT routed into a race with it"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no twin is minted"

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

# The stale-gate scan addresses each declared gate by its own name; whitespace
# around a separator must not join two gates into one.
echo "# a multi-gate check_set is scanned per gate, never as one joined name"
store "[$(anchor F9m 19 ',"check_set":"codex, triage","check.triage":"green@sha-OLD"')]"
printf '%s' "$(prview 19 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_19.json"
: > "$STUB_GC_LOG"
out=$(run)
hasnt "$out" "codextriage" "the comma list is not collapsed into one gate name"
has "$out" "check.triage green@sha-OLD is stale" "the stale second gate is found under its own name"
eq "$(meta new-2 check_name)" "triage" "the re-review names the real gate"

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

echo "# posture: an anchor blocked on a human approval says so"
# The sl-bgmuy/PR#552 fixture: gate green at the live head, nothing in flight,
# and by the pack's old accounting indistinguishable from an anchor progressing.
store "[$(anchor S1 50)]"
printf '%s' "$(prview 50 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_50.json"
echo '[]' > "$GH_DIR/reviews_50.json"; echo '[]' > "$GH_DIR/comments_50.json"
out=$(run)
has "$out" "posture review_required@sha-50" "the pass names what it recorded"
eq "$(meta_pinned S1 pr_posture)" "review_required@sha-50" "the anchor carries the posture, pinned to the head"
eq "$(meta S1 pr_merge_state)" "BLOCKED@sha-50" "…and GitHub's mergeStateStatus verbatim beside it"
eq "$(meta S1 merge_result)" "pull_request" "recording a posture is not a state change"

echo "# …an unchanged posture is not re-written"
: > "$STUB_GC_LOG"
out=$(run)
eq "$(grep -c '^bd update S1' "$STUB_GC_LOG" || true)" "0" "no ledger churn when nothing moved"
hasnt "$out" "posture review_required" "…and the pass says nothing about it"

echo "# …a moved head re-pins it"
printf '%s' "$(prview 50 OPEN CLEAN MERGEABLE)" \
  | jq -c '.reviewDecision = "APPROVED" | .headRefOid = "sha-NEW"' > "$GH_DIR/pr_view_50.json"
out=$(run)
eq "$(meta_pinned S1 pr_posture)" "approved@sha-NEW" "the posture follows the head it was read at"
eq "$(meta S1 pr_merge_state)" "CLEAN@sha-NEW" "…so does the merge state"

echo "# COMMENTED is representable, and it routes to work"
# The tk-9heqfh/PR#477 fixture: inline comments that were neither approval nor
# veto, so nothing in the pack could name them.
store "[$(anchor P1 40)]"
printf '%s' "$(prview 40 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_40.json"
echo '[]' > "$GH_DIR/reviews_40.json"
printf '[{"id":5001,"user":{"login":"human1"},"body":"this path never runs","path":"docs/gate-calibration.md"}]' \
  > "$GH_DIR/comments_40.json"
: > "$STUB_SESSION_LOG"
out=$(run)
eq "$(meta_pinned P1 pr_posture)" "commented@sha-40" "COMMENTED is a recorded posture, not an unrepresentable one"
has "$out" "routed to rework:new-2" "the comment routed to something"
eq "$(meta P1 pr_comment_disposition)" "rework:new-2" "…and the choice is recorded on the anchor"
eq "$(meta P1 pr_comment_watermark)" "5001" "the watermark advanced to the routed comment"
eq "$(meta P1 pr_review_watermark)" "0" "…and the review id space stayed put (two spaces, never merged)"
eq "$(meta new-2 anchor_bead)" "P1" "the child names the anchor — this arm's dedup key"
eq "$(meta new-2 pr_number)" "40" "…and the PR, so merge.sh counts it in flight"
eq "$(meta new-2 branch)" "polecat/x40" "the child resumes the PR's own branch"
eq "$(meta new-2 prepare_mode)" "rebase" "a polecat/* head is classified rebase"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "the child is routed to the fix pool"
has "$(meta new-2 rejection_reason)" "Do NOT open a new PR" "the work order reworks THIS PR"
grep -qxF "new-2|blocks|P1" "$STUB_DEPS" && ok "the child blocks the anchor" || bad "blocks edge missing"
has "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "the fix pool is woken"

echo "# …a comment below the watermark is answered; the batch never re-fires"
: > "$STUB_SESSION_LOG"
out=$(run)
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "no twin child"
eq "$(meta_pinned P1 pr_posture)" "review_required@sha-40" "the answered comment falls back to the standing posture"
hasnt "$out" "routed to rework" "…and nothing re-routes"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…nor re-wakes the pool"

echo "# …a comment ABOVE the watermark is new, and gets its own batch"
printf '[{"id":5001,"user":{"login":"human1"},"body":"a"},{"id":5009,"user":{"login":"human1"},"body":"and another"}]' \
  > "$GH_DIR/comments_40.json"
out=$(run)
eq "$(meta_pinned P1 pr_posture)" "commented@sha-40" "a comment above the mark is outstanding by construction"
eq "$(meta P1 pr_comment_watermark)" "5009" "the watermark advanced past it"
eq "$(meta P1 pr_comment_disposition)" "rework:new-3" "the new batch got its own child"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "2" "…and the first child was not reused"

echo "# …a routing that lands but does not read back re-dispatches onto the SAME child"
store "[$(anchor W1 45)]"
printf '%s' "$(prview 45 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_45.json"
echo '[]' > "$GH_DIR/reviews_45.json"
printf '[{"id":9001,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_45.json"
out=$(STUB_DROP_KEYS="W1:pr_comment_watermark" run)
has "$out" "watermark did NOT record" "the lost watermark is caught by the read-back"
eq "$(meta W1 pr_comment_watermark)" "<absent>" "…the mark really did not move"
out=$(run)
has "$out" "already covers this batch; re-checking its route" "the next pass finds its own child"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "STILL one child — an unanswered comment never mints a twin"
eq "$(meta W1 pr_comment_watermark)" "9001" "…and the mark lands on the retry"

echo "# …an unstamped comment-rework orphan is ADOPTED, never twinned"
store "[$(anchor W2 46)]"
printf '%s' "$(prview 46 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_46.json"
echo '[]' > "$GH_DIR/reviews_46.json"
printf '[{"id":9100,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_46.json"
out=$(STUB_DROP_KEYS="new-2:anchor_bead" run)
has "$out" "did not record anchor_bead=W2; left unrouted" "an unstamped child is inert, never routed"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…and cannot be claimed"
out=$(run)
has "$out" "adopting unstamped comment-rework orphan new-2" "the next pass adopts it by its deterministic title"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "STILL exactly one child"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…now routed"

echo "# …but a CLOSED orphan is never adopted: it holds nothing and still moves the mark"
store "[$(anchor W3 47)]"
printf '%s' "$(prview 47 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_47.json"
echo '[]' > "$GH_DIR/reviews_47.json"
printf '[{"id":9200,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_47.json"
out=$(STUB_DROP_KEYS="new-2:anchor_bead" run)
has "$out" "did not record anchor_bead=W3; left unrouted" "the dropped stamp leaves an orphan again"
ctmp=$(mktemp); jq -c 'map(if .id == "new-2" then .status = "closed" else . end)' "$STUB_STORE" > "$ctmp" && mv "$ctmp" "$STUB_STORE"
out=$(run)
hasnt "$out" "adopting unstamped comment-rework orphan" "a closed orphan is passed over"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "2" "a live child is minted in its place"
eq "$(meta new-3 'gc.routed_to')" "$FIX" "…and that one is routed"
eq "$(meta W3 pr_comment_disposition)" "rework:new-3" "the disposition names the live child"
grep -qxF "new-3|blocks|W3" "$STUB_DEPS" && ok "…and it is what holds the merge" || bad "blocks edge missing"

echo "# …a child whose ROUTE stamp drops is never watermarked past"
# The blocks edge holds the merge either way, so the failure is not a silent
# merge — it is an unclaimable child plus a mark retired past the only comments
# that could re-file it.
store "[$(anchor W4 48)]"
printf '%s' "$(prview 48 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_48.json"
echo '[]' > "$GH_DIR/reviews_48.json"
printf '[{"id":9300,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_48.json"
out=$(STUB_DROP_KEYS="new-2:gc.routed_to" run)
has "$out" "is NOT routed to $FIX; NOT watermarking" "a dropped route stamp refuses the watermark"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…the child really is unclaimable"
eq "$(meta W4 pr_comment_watermark)" "<absent>" "…and the comment stays above the mark"
eq "$(meta W4 pr_comment_disposition)" "<absent>" "…with nothing recorded as its disposition"
out=$(run)
has "$out" "already covers this batch; re-checking its route" "the next pass re-checks the route it left behind"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…repairs it in place"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "…without minting a twin"
eq "$(meta W4 pr_comment_watermark)" "9300" "…and only then does the mark move"

echo "# …a child whose prepare_mode stamp drops is never routed, nor watermarked past"
# The classifier called this head SHARED. mol-polecat-work reads an absent mode
# as rebase, so routing the child without it force-pushes the branch the mode
# exists to spare — the one failure a blocks edge does not contain.
store "[$(anchor W6 50 '' 'integration/convoy-77')]"
printf '%s' "$(prview 50 OPEN BLOCKED MERGEABLE '' 'integration/convoy-77')" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_50.json"
echo '[]' > "$GH_DIR/reviews_50.json"
printf '[{"id":9600,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_50.json"
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:prepare_mode" run)
has "$out" "did not record prepare_mode=merge; left unrouted and NOT watermarking" "the lost mode stamp is caught BEFORE the route"
eq "$(meta new-2 prepare_mode)" "<absent>" "the stamp really was dropped"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…so the child is never routable AND rewriting"
eq "$(meta W6 pr_comment_watermark)" "<absent>" "…and the comment stays above the mark"
eq "$(meta W6 pr_comment_disposition)" "<absent>" "…with nothing recorded as its disposition"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"
out=$(run)
has "$out" "already covers this batch; re-checking its route" "the next pass finds its own child"
eq "$(meta new-2 prepare_mode)" "merge" "…re-stamps the mode it classified"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and only then routes it"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "…without minting a twin"
eq "$(meta W6 pr_comment_watermark)" "9600" "…and only then does the mark move"

echo "# …a CLOSED child is dispositioned, so an unrouted one still converges"
store "[$(anchor W5 49)]"
printf '%s' "$(prview 49 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_49.json"
echo '[]' > "$GH_DIR/reviews_49.json"
printf '[{"id":9400,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_49.json"
out=$(STUB_DROP_KEYS="new-2:gc.routed_to" run)
has "$out" "NOT watermarking" "the unrouted child holds the mark"
ctmp=$(mktemp); jq -c 'map(if .id == "new-2" then .status = "closed" else . end)' "$STUB_STORE" > "$ctmp" && mv "$ctmp" "$STUB_STORE"
out=$(run)
eq "$(meta W5 pr_comment_watermark)" "9400" "a closed child answers the batch even unrouted — refusing forever could not converge"

echo "# --posture-only: the record merge.sh reads, written before merge.sh runs"
# merge.sh reads pr_posture off the bead and never asks GitHub. The full arm
# runs AFTER merge, so a comment that arrived since the last pass would be
# invisible to the merge it should have held. This mode closes that window: it
# records, and dispatches nothing.
run_posture() { "$SUT" --posture-only 2>&1; }
store "[$(anchor PO1 60)]"
printf '%s' "$(prview 60 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_60.json"
echo '[]' > "$GH_DIR/reviews_60.json"
printf '[{"id":9500,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_60.json"
: > "$STUB_SESSION_LOG"
out=$(run_posture); rc=$?
eq "$rc" 0 "a posture-only pass exits 0"
eq "$(meta_pinned PO1 pr_posture)" "commented@sha-60" "the posture is recorded"
eq "$(meta PO1 pr_merge_state)" "BLOCKED@sha-60" "…and the merge state beside it"
has "$out" "posture-only" "the summary names the mode"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "NOTHING was dispatched"
eq "$(meta PO1 pr_comment_watermark)" "<absent>" "…and no watermark moved: routing is the full pass's"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake" "…no pool was woken"

echo "# …the full pass that follows still routes the same batch"
out=$(run)
eq "$(meta PO1 pr_comment_disposition)" "rework:new-2" "the comment is routed once the full arm runs"
eq "$(meta PO1 pr_comment_watermark)" "9500" "…and only then is it marked answered"

echo "# …a CONFLICTING anchor is recorded, never reworked, by this mode"
store "[$(anchor PO2 61)]"
printf '%s' "$(prview 61 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_61.json"
echo '[]' > "$GH_DIR/reviews_61.json"
echo '[]' > "$GH_DIR/comments_61.json"
out=$(run_posture)
eq "$(meta_pinned PO2 pr_posture)" "none@sha-61" "the posture is still recorded"
hasnt "$out" "filed rebase-mode rework" "…but no rework child is filed"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…none at all"

echo "# …and MERGED/CLOSED reconciliation is left to the full pass"
store "[$(anchor PO3 62)]"
printf '%s' "$(prview 62 MERGED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_62.json"
out=$(run_posture)
hasnt "$out" "is MERGED" "a merged PR is not reconciled by the posture pass"
eq "$(bstatus PO3)" "open" "…the anchor is left exactly as it was"
eq "$(meta PO3 merge_result)" "pull_request" "…with its state untouched"
out=$(run)
has "$out" "PR#62 is MERGED" "the full pass still records it"
eq "$(bstatus PO3)" "closed" "…and closes the anchor"

echo "# --posture-only: an anchor it could not make current holds the merge arm"
# merge.sh validates the posture recorded here and never asks GitHub. The only
# signal that a posture is NOT current is this arm's exit code, which
# refinery-reconcile reads to hold merge.sh for the pass.
store "[$(anchor PO4 63)]"
printf '%s' "$(prview 63 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_63.json"
echo '[]' > "$GH_DIR/reviews_63.json"
printf '[{"id":9600,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_63.json"
out=$(STUB_UPDATE_FAIL="PO4" run_posture); rc=$?
eq "$rc" 1 "an unpersisted posture exits non-zero"
has "$out" "posture is not current" "…naming the anchor merge must not read"
has "$out" "1 not current" "…and counting it in the summary"
eq "$(meta PO4 pr_posture)" "<absent>" "…with nothing recorded"

echo "# …a posture it could not even determine holds the merge arm too"
# Nothing distinguishes our own comment from a human's without the acting login,
# so this pass cannot tell "no new comment" from "a comment it cannot see".
store "[$(anchor PO4 63)]"
out=$(STUB_SELF_LOGIN="" run_posture); rc=$?
eq "$rc" 1 "an undeterminable posture exits non-zero"
has "$out" "the acting login is unresolved" "…naming the read that failed"

echo "# …but a standing commented@ is already holding, so it is not the gap"
store "[$(anchor PO5 64 ',"pr_posture":"commented@sha-64"')]"
printf '%s' "$(prview 64 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_64.json"
echo '[]' > "$GH_DIR/reviews_64.json"
echo '[]' > "$GH_DIR/comments_64.json"
out=$(STUB_SELF_LOGIN="" run_posture); rc=$?
eq "$rc" 0 "the arm does not hold the whole queue over an anchor already held"
eq "$(meta PO5 pr_posture)" "commented@sha-64" "…and the standing posture is untouched"

echo "# …the FULL pass never gates on the same condition (it runs after merge)"
store "[$(anchor PO6 65)]"
printf '%s' "$(prview 65 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_65.json"
echo '[]' > "$GH_DIR/reviews_65.json"
echo '[]' > "$GH_DIR/comments_65.json"
out=$(STUB_SELF_LOGIN="" run); rc=$?
eq "$rc" 0 "the full pass exits 0"
has "$out" "not current" "…while still reporting the count"

echo "# a human already holding the anchor gets the comments, not the fix pool"
store "[$(anchor H1 44 ',"gc.takeaway":"holding — needs a ruling"')]"
printf '%s' "$(prview 44 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_44.json"
echo '[]' > "$GH_DIR/reviews_44.json"
printf '[{"id":8001,"user":{"login":"human1"},"body":"this is wrong"}]' > "$GH_DIR/comments_44.json"
: > "$STUB_ESC_LOG"; : > "$STUB_SESSION_LOG"
out=$(run)
has "$(cat "$STUB_ESC_LOG")" "--key pr-comments.44.0.8001" "the visit key names the exact batch"
has "$(cat "$STUB_ESC_LOG")" "a sitting recorded a takeaway on it" "…and why no work could be routed"
eq "$(meta H1 pr_comment_disposition)" "visit:new-2" "the choice is recorded, and it is the visit"
eq "$(meta H1 pr_comment_watermark)" "8001" "the comment IS dispositioned — it went to a named party"
eq "$(meta new-2 task_kind)" "visit" "the visit was really filed"
eq "$(meta new-2 pr_number)" "44" "the visit carries the PR, which is what holds the merge"
hasnt "$(grep -F '|blocks|H1' "$STUB_DEPS" || true)" "new-2" "…and NOT a blocks edge: escalate.sh already files the visit depending on its subject"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "no work was routed under the human's decision"

echo "# …and so does rebase_hold: a child told to answer comments may rewrite the branch"
store "[$(anchor H5 54 ',"rebase_hold":"true"')]"
printf '%s' "$(prview 54 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_54.json"
echo '[]' > "$GH_DIR/reviews_54.json"
printf '[{"id":8400,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_54.json"
: > "$STUB_ESC_LOG"; : > "$STUB_SESSION_LOG"
out=$(run)
has "$(cat "$STUB_ESC_LOG")" "rebase_hold freezes the branch" "an operator branch freeze routes to the human, not the pool"
eq "$(meta H5 pr_comment_disposition)" "visit:new-2" "…and the visit is what is recorded"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…no work dispatched against the frozen branch"

echo "# …a visit that did not take the stamp is NOT watermarked past"
store "[$(anchor H4 53 ',"gc.routed_to":"human"')]"
printf '%s' "$(prview 53 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_53.json"
echo '[]' > "$GH_DIR/reviews_53.json"
printf '[{"id":8300,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_53.json"
out=$(STUB_DROP_KEYS="new-2:pr_number" run)
has "$out" "did not record pr_number=53; NOT watermarking" "an unheld visit fails closed"
eq "$(meta H4 pr_comment_watermark)" "<absent>" "…the mark never moved past an unheld comment"
eq "$(meta_pinned H4 pr_posture)" "commented@sha-53" "…and the posture still holds the merge"

echo "# …so does an anchor already routed to a human, and one with no fix pool"
store "[$(anchor H2 47 ',"gc.routed_to":"human"')]"
printf '%s' "$(prview 47 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_47.json"
echo '[]' > "$GH_DIR/reviews_47.json"
printf '[{"id":8100,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_47.json"
: > "$STUB_ESC_LOG"
out=$(run)
has "$(cat "$STUB_ESC_LOG")" "already routed to a human" "a human-routed anchor gets a visit"
eq "$(meta H2 pr_comment_disposition)" "visit:new-2" "…and the visit is what is recorded"
store "[$(anchor H3 48)]"
printf '%s' "$(prview 48 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_48.json"
echo '[]' > "$GH_DIR/reviews_48.json"
printf '[{"id":8200,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_48.json"
: > "$STUB_ESC_LOG"
out=$("$SUT" --review-pool "$REV" 2>&1)
has "$(cat "$STUB_ESC_LOG")" "no fix pool is configured" "with nowhere to route work, the human is asked"
eq "$(meta H3 pr_comment_disposition)" "visit:new-2" "silence is never the answer"

# --- operator feedback resets signoff's round cap --------------------------------
# The cap bounds the city failing to converge against its own reviewer. A review
# the branch has never been answered against is new input, not one of those
# rounds, so it goes back to the loop instead of spending the allowance on the
# operator's own words.
CAP_STATE=',"check.codex":"exception@sha-55","signoff_cap":"codex@sha-55"'
CAP_STATE="$CAP_STATE"',"gc.routed_to":"human","blocked_reason":"signoff did not converge after 3 rework rounds (cap 3)"'
CAP_STATE="$CAP_STATE"',"dispatch_count":"5","dispatch_backstop.codex":"5@sha-55"'

echo "# new operator feedback on a capped anchor resets it, park and all"
store "[$(anchor R1 55 "$CAP_STATE")]"
printf '%s' "$(prview 55 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_55.json"
echo '[]' > "$GH_DIR/reviews_55.json"
printf '[{"id":8500,"user":{"login":"human1"},"body":"this is not what I asked for"}]' > "$GH_DIR/comments_55.json"
: > "$STUB_ESC_LOG"; : > "$STUB_SESSION_LOG"
out=$(run)
eq "$(meta R1 signoff_rounds_reset)" "0.8500" "the batch that reset the cap is recorded by its own id coordinates"
eq "$(meta R1 'check.codex')" "<absent>" "the exception is retired — a cap that resets under its own marker has not reset"
eq "$(meta R1 signoff_cap)" "<absent>" "…and the stamp that proved the park was the cap's"
eq "$(meta R1 blocked_reason)" "<absent>" "…and the reason that named it"
eq "$(meta R1 'gc.routed_to')" "" "…and the human park, so the anchor is back in the cadence"
eq "$(meta R1 dispatch_count)" "<absent>" "the dispatch tally goes too: released rounds nobody may dispatch are no release"
eq "$(meta R1 'dispatch_backstop.codex')" "<absent>" "…with the backstop stamp that dedups its escalation"
has "$(notes R1)" "operator feedback on PR#55 (review 0, comment 8500" "the reset names the feedback that caused it"
eq "$(meta R1 pr_comment_disposition)" "rework:new-2" "the comments route to work, not to the visit the park would have forced"
has "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is woken"

echo "# …and the same feedback on a later pass resets nothing"
BEFORE_NOTES=$(notes R1)
out=$(run)
eq "$(meta R1 signoff_rounds_reset)" "0.8500" "the recorded batch is unchanged"
eq "$(notes R1)" "$BEFORE_NOTES" "…and nothing was appended: one reset per distinct piece of feedback"
hasnt "$out" "resets the signoff round cap" "…and the pass says nothing about a reset"

echo "# …nor does a batch already recorded whose watermark write dropped"
# The watermark and the reset stamp are separate writes. A pass that routed the
# comments but lost the mark sees the same batch again; what stops the second
# reset is the recorded batch, not the mark.
store "[$(anchor R2 56 ',"check.codex":"exception@sha-56","signoff_cap":"codex@sha-56","gc.routed_to":"human","signoff_rounds_reset":"0.8600"')]"
printf '%s' "$(prview 56 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_56.json"
echo '[]' > "$GH_DIR/reviews_56.json"
printf '[{"id":8600,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_56.json"
out=$(run)
hasnt "$out" "resets the signoff round cap" "a batch already recorded resets nothing"
eq "$(meta R2 'check.codex')" "exception@sha-56" "…the cap's exception still stands"
eq "$(meta R2 'gc.routed_to')" "human" "…and its park"
eq "$(meta R2 pr_comment_disposition)" "visit:new-2" "…so the comments go to the person holding it"

echo "# a verdict the city posted itself is not feedback, and resets nothing"
# Identity, not shape: signoff.sh posts its verdicts under the city's own login
# and a rework hand-back posts nothing at all, so neither can reach the reset.
store "[$(anchor R3 57 ',"check.codex":"exception@sha-57","signoff_cap":"codex@sha-57","gc.routed_to":"human"')]"
printf '%s' "$(prview 57 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_57.json"
printf '[{"id":7500,"user":{"login":"gc-city-bot"},"state":"COMMENTED","body":"Signoff verdict: request-changes","commit_id":"sha-57"}]' \
  > "$GH_DIR/reviews_57.json"
printf '[{"id":8700,"user":{"login":"gc-city-bot"},"body":"P2: nit at foo.sh:3"}]' > "$GH_DIR/comments_57.json"
out=$(run)
eq "$(meta R3 pr_posture)" "review_required@sha-57" "the city's own verdict is not an outstanding comment"
eq "$(meta R3 signoff_rounds_reset)" "<absent>" "…so no batch is recorded"
eq "$(meta R3 'check.codex')" "exception@sha-57" "…the cap's exception stands"
eq "$(meta R3 'gc.routed_to')" "human" "…and the anchor stays parked for the person it was given to"

echo "# …and a rework hand-back, which posts nothing at all, is not feedback either"
KID52='{"id":"kid-52","status":"open","assignee":"","title":"Rework PR#52","notes":"","metadata":{"anchor_bead":"R7","source_review_bead":"rv-52"}}'
store "[$(anchor R7 52 ',"check.codex":"exception@sha-52","signoff_cap":"codex@sha-52","gc.routed_to":"human"'),$KID52]"
printf '%s' "$(prview 52 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_52.json"
echo '[]' > "$GH_DIR/reviews_52.json"
echo '[]' > "$GH_DIR/comments_52.json"
out=$(run)
eq "$(meta R7 pr_posture)" "review_required@sha-52" "a hand-back leaves the PR with nothing outstanding on it"
eq "$(meta R7 signoff_rounds_reset)" "<absent>" "…so no batch is recorded"
eq "$(meta R7 'check.codex')" "exception@sha-52" "…and the cap's exception stands"
eq "$(meta R7 'gc.routed_to')" "human" "…with the park it belongs to"

echo "# a park no signoff_cap claims is a person's, and survives the reset"
store "[$(anchor R4 58 ',"check.codex":"exception@sha-58","gc.routed_to":"human"')]"
printf '%s' "$(prview 58 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_58.json"
echo '[]' > "$GH_DIR/reviews_58.json"
printf '[{"id":8800,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_58.json"
out=$(run)
eq "$(meta R4 signoff_rounds_reset)" "0.8800" "the counter still resets — the rounds are the cap's, wherever the park came from"
eq "$(meta R4 'check.codex')" "exception@sha-58" "…but an exception no signoff_cap claims is not the cap's to retire"
eq "$(meta R4 'gc.routed_to')" "human" "…and the park stands"
eq "$(meta R4 pr_comment_disposition)" "visit:new-2" "…so the comments go to the person holding it"

echo "# …and a live takeaway outranks the reset even with the cap's own stamp"
store "[$(anchor R5 59 ',"check.codex":"exception@sha-59","signoff_cap":"codex@sha-59","gc.routed_to":"human","gc.takeaway":"holding — needs a ruling"')]"
printf '%s' "$(prview 59 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_59.json"
echo '[]' > "$GH_DIR/reviews_59.json"
printf '[{"id":8900,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_59.json"
out=$(run)
eq "$(meta R5 'check.codex')" "exception@sha-59" "a sitting's decision is not undone by a comment"
eq "$(meta R5 'gc.routed_to')" "human" "…and the anchor stays parked for it"
eq "$(meta R5 pr_comment_disposition)" "visit:new-2" "…which is who the comments go to"

echo "# a reset the store refuses leaves the cap standing, and says so"
# One transition carries the whole reset, so a refusal retires nothing: the
# batch stays unrecorded and the next pass reads the same comments and retries.
store "[$(anchor R6 51 "$(printf '%s' "$CAP_STATE" | sed 's/sha-55/sha-51/g')")]"
printf '%s' "$(prview 51 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_51.json"
echo '[]' > "$GH_DIR/reviews_51.json"
printf '[{"id":8510,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_51.json"
out=$(STUB_UPDATE_FAIL="R6" run)
has "$out" "cap reset did not record" "the refusal is reported, not swallowed"
eq "$(meta R6 signoff_rounds_reset)" "<absent>" "…no batch is recorded, so the next pass retries"
eq "$(meta R6 'check.codex')" "exception@sha-51" "…the exception is left standing"
eq "$(meta R6 'gc.routed_to')" "human" "…and so is the park"

echo "# a COMMENTED review body with no inline comment is still a human waiting"
store "[$(anchor P3 42)]"
printf '%s' "$(prview 42 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_42.json"
printf '[{"id":7001,"user":{"login":"human1"},"state":"COMMENTED","body":"why this way?","commit_id":"sha-42"}]' \
  > "$GH_DIR/reviews_42.json"
echo '[]' > "$GH_DIR/comments_42.json"
out=$(run)
eq "$(meta_pinned P3 pr_posture)" "commented@sha-42" "a review body with no inline comment still counts"
eq "$(meta P3 pr_review_watermark)" "7001" "the review id space carries it"
eq "$(meta P3 pr_comment_watermark)" "0" "…and the comment id space stays at zero"

echo "# …an EMPTY-bodied COMMENTED review is not a posture no id can answer"
store "[$(anchor P4 43)]"
printf '%s' "$(prview 43 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_43.json"
printf '[{"id":7002,"user":{"login":"human1"},"state":"COMMENTED","body":"","commit_id":"sha-43"}]' > "$GH_DIR/reviews_43.json"
echo '[]' > "$GH_DIR/comments_43.json"
out=$(run)
eq "$(meta_pinned P4 pr_posture)" "none@sha-43" "its inline comments are what the comment read already sees"

echo "# the city's own comment is not a human waiting"
store "[$(anchor P2 41)]"
printf '%s' "$(prview 41 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_41.json"
printf '[{"id":6002,"user":{"login":"gc-city-bot"},"state":"COMMENTED","body":"replayed verdict"}]' > "$GH_DIR/reviews_41.json"
printf '[{"id":6001,"user":{"login":"gc-city-bot"},"body":"replayed verdict"}]' > "$GH_DIR/comments_41.json"
out=$(run)
eq "$(meta_pinned P2 pr_posture)" "approved@sha-41" "our own replayed verdict is not an outstanding comment"
eq "$(meta P2 pr_comment_watermark)" "<absent>" "…and nothing was watermarked"

echo "# an unanswered comment outranks an approval"
store "[$(anchor P5 49)]"
printf '%s' "$(prview 49 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_49.json"
echo '[]' > "$GH_DIR/reviews_49.json"
printf '[{"id":9500,"user":{"login":"human2"},"body":"but what about this?"}]' > "$GH_DIR/comments_49.json"
out=$(run)
eq "$(meta_pinned P5 pr_posture)" "commented@sha-49" "one reviewer's approval does not answer another's question"

echo "# a standing CHANGES_REQUESTED outranks everything and watermarks nothing"
store "[$(anchor P6 51)]"
printf '%s' "$(prview 51 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_51.json"
printf '[{"id":9600,"user":{"login":"human1"},"state":"CHANGES_REQUESTED","commit_id":"sha-51","submitted_at":"2026-08-19T00:00:00Z"}]' \
  > "$GH_DIR/reviews_51.json"
printf '[{"id":9601,"user":{"login":"human1"},"body":"fix this"}]' > "$GH_DIR/comments_51.json"
: > "$STUB_GH_LOG"
out=$(run)
eq "$(meta_pinned P6 pr_posture)" "changes_requested@sha-51" "the veto is the posture"
eq "$(meta P6 pr_comment_watermark)" "<absent>" "its comments belong to signoff's rework loop, not this arm"
hasnt "$(cat "$STUB_GH_LOG")" "pulls/51/comments" "…and the comment read is not even made"

echo "# a read that cannot tell records NOTHING rather than clear a standing hold"
store "[$(anchor P7 52 ',"pr_posture":"commented@sha-52","pr_comment_watermark":"1"')]"
printf '%s' "$(prview 52 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_52.json"
out=$(STUB_SELF_LOGIN="" run)
has "$out" "the acting login is unresolved" "an unresolved login is named"
eq "$(meta P7 pr_posture)" "commented@sha-52" "the standing posture is left holding, never downgraded blind"

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
