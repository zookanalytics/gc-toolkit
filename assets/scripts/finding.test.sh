#!/usr/bin/env bash
# finding.test.sh — hermetic tests for the finding-bead primitive.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-finding-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
unset GC_RIG 2>/dev/null || true
harness_init
SUT="$HERE/finding.sh"

deps() { cat "$STUB_DEPS"; }
# The exact probe merge.sh runs to find an anchor's live blockers.
probe_blockers() { gc bd dep list "$1" --direction=down -t blocks --json | jq -r '.[].id' | tr '\n' ' '; }

# ---------------------------------------------------------------------------
# finding.key: rebase-stable and lane-scoped.
# ---------------------------------------------------------------------------
K1=$("$SUT" key --lane correctness --locus "assets/scripts/foo.sh:bar()" --message "Unquoted expansion in the loop")
K2=$("$SUT" key --lane correctness --locus "assets/scripts/foo.sh:99:bar()" --message "unquoted   expansion in the loop")
eq "$K1" "$K2" "key strips line numbers, case and whitespace so it survives a rebase"
K3=$("$SUT" key --lane arch --locus "assets/scripts/foo.sh:bar()" --message "Unquoted expansion in the loop")
if [ "$K1" != "$K3" ]; then ok "key is lane-scoped"; else bad "key collides across lanes"; fi

# ---------------------------------------------------------------------------
# upsert: files a finding bead with the full metadata contract.
# ---------------------------------------------------------------------------
store '[{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness","pr_number":"42"}}]'
F1=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "assets/scripts/foo.sh:bar()" --message "Unquoted expansion in the loop")
eq "$(meta "$F1" task_kind)" "finding" "upsert stamps task_kind=finding"
eq "$(meta "$F1" anchor_bead)" "tk-anc" "upsert stamps anchor_bead"
eq "$(meta "$F1" 'finding.lane')" "correctness" "upsert stamps finding.lane"
eq "$(meta "$F1" 'finding.disposition')" "unvalidated" "a fresh finding is unvalidated"
eq "$(meta "$F1" 'finding.source')" "machine:correctness" "source defaults to machine:<lane>"
eq "$(meta "$F1" 'finding.key')" "$K1" "upsert stamps the computed key"

# ---------------------------------------------------------------------------
# dedup: re-raising the same objection creates nothing; a distinct one does.
# ---------------------------------------------------------------------------
BEFORE=$(jq 'length' "$STUB_STORE")
F1b=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "assets/scripts/foo.sh:88:bar()" --message "unquoted   Expansion in the loop")
eq "$F1b" "$F1" "re-raising the same objection returns the existing finding"
eq "$(jq 'length' "$STUB_STORE")" "$BEFORE" "…and files no second bead"
F2=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "assets/scripts/baz.sh:qux()" --message "missing error handling on the write")
if [ "$F2" != "$F1" ]; then ok "a distinct objection is a distinct finding"; else bad "distinct objection collided"; fi

# Same key on a DIFFERENT anchor is a different finding (dedup is per-anchor).
store "$(jq -c '. + [{"id":"tk-anc2","status":"open","assignee":"","title":"a2","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness"}}]' "$STUB_STORE")"
F1_other=$("$SUT" upsert --anchor tk-anc2 --lane correctness --locus "assets/scripts/foo.sh:bar()" --message "Unquoted expansion in the loop")
if [ "$F1_other" != "$F1" ]; then ok "the same key on another anchor is its own finding"; else bad "dedup crossed anchors"; fi

# ---------------------------------------------------------------------------
# set-disposition must-fix: the finding blocks the anchor — the hold merge.sh's
# blocker probe already reads.
# ---------------------------------------------------------------------------
"$SUT" set-disposition --finding "$F1" --anchor tk-anc --disposition must-fix
eq "$(meta "$F1" 'finding.disposition')" "must-fix" "disposition recorded as must-fix"
has "$(deps)" "$F1|blocks|tk-anc" "must-fix wires finding --blocks anchor"
has " $(probe_blockers tk-anc) " " $F1 " "merge.sh's down-blocker probe sees the must-fix finding"
# Idempotent: a second must-fix wiring adds no duplicate edge.
"$SUT" set-disposition --finding "$F1" --anchor tk-anc --disposition must-fix
eq "$(grep -c "^$F1|blocks|tk-anc$" "$STUB_DEPS")" "1" "re-running must-fix adds no second edge"

# ---------------------------------------------------------------------------
# set-disposition deferred: discovered-from holds nothing — the probe ignores it.
# ---------------------------------------------------------------------------
F3=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "docs/x.md" --message "stale reference to a retired script")
"$SUT" set-disposition --finding "$F3" --anchor tk-anc --disposition deferred --reason "the rewrite it needs lands in the next PR"
eq "$(meta "$F3" 'finding.disposition')" "deferred" "disposition recorded as deferred"
# A deferred finding holds nothing and outlives the merge: its bead is the only
# place whoever picks it up can read WHY it was not fixed now.
has "$(notes "$F3")" "the rewrite it needs lands in the next PR" "the deferral reason is recorded"
has "$(deps)" "$F3|discovered-from|tk-anc" "deferred wires finding --discovered-from anchor"
hasnt "$(deps)" "$F3|blocks|tk-anc" "deferred writes no blocks edge"
hasnt " $(probe_blockers tk-anc) " " $F3 " "merge.sh's probe does NOT see the deferred finding"

# ---------------------------------------------------------------------------
# set-disposition must-fix -> deferred: the reclassification retracts the blocks
# edge, or merge.sh keeps reading the finding as a live blocker and a deferred
# finding holds the merge it must not (regression).
# ---------------------------------------------------------------------------
F5=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "assets/scripts/qux.sh:main()" --message "double-quote the array expansion")
"$SUT" set-disposition --finding "$F5" --anchor tk-anc --disposition must-fix
has " $(probe_blockers tk-anc) " " $F5 " "must-fix first wires the finding as a live blocker"
"$SUT" set-disposition --finding "$F5" --anchor tk-anc --disposition deferred
eq "$(meta "$F5" 'finding.disposition')" "deferred" "reclassified must-fix -> deferred"
hasnt "$(deps)" "$F5|blocks|tk-anc" "must-fix -> deferred retracts the blocks edge"
hasnt " $(probe_blockers tk-anc) " " $F5 " "merge.sh's probe no longer sees the reclassified finding"
has "$(deps)" "$F5|discovered-from|tk-anc" "must-fix -> deferred keeps the discovered-from provenance edge"

# ---------------------------------------------------------------------------
# set-disposition declined: closed with the reason, holding nothing.
# ---------------------------------------------------------------------------
F4=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "assets/scripts/foo.sh:helper()" --message "nit: rename for clarity")
"$SUT" set-disposition --finding "$F4" --anchor tk-anc --disposition declined --reason "cosmetic, not worth a round"
eq "$(meta "$F4" 'finding.disposition')" "declined" "disposition recorded as declined"
eq "$(bstatus "$F4")" "closed" "declined finding is closed"
has "$(notes "$F4")" "cosmetic, not worth a round" "the decline reason is recorded"
hasnt " $(probe_blockers tk-anc) " " $F4 " "a declined finding holds nothing"
eq "$(meta "$F4" 'finding.reply')" "<absent>" "a machine decline owes no reply, so finding.reply is unset"

# ---------------------------------------------------------------------------
# set-disposition declined --reply: a declined HUMAN objection owes an answer.
# The reply text is stamped on the finding so pr-facts.sh's write-back can post
# it to the raiser's thread; the finding still closes and holds nothing.
# ---------------------------------------------------------------------------
FH=$("$SUT" upsert --anchor tk-anc --lane human --source "human:johnzook" --locus "assets/scripts/foo.sh:helper()" --message "this should assert X")
"$SUT" set-disposition --finding "$FH" --anchor tk-anc --disposition declined \
  --reason "the diff already asserts X at foo.sh" --reply "The diff already asserts X in foo.sh's helper; no change needed."
eq "$(meta "$FH" 'finding.disposition')" "declined" "the human objection is declined on its merits"
eq "$(bstatus "$FH")" "closed" "…and closed like any decline, so a re-raise re-adopts fresh"
has "$(meta "$FH" 'finding.reply')" "no change needed" "…and the owed reply is stamped for the write-back to post"
hasnt " $(probe_blockers tk-anc) " " $FH " "…and it holds nothing once declined"

# ---------------------------------------------------------------------------
# wire-fix-unit: the fix unit's two blocks edges.
# ---------------------------------------------------------------------------
FU=$(gc bd create "Rework: address findings" -t task --json | jq -r '.id')
"$SUT" wire-fix-unit --fix-unit "$FU" --anchor tk-anc --findings "$F1,$F2"
has "$(deps)" "$FU|blocks|tk-anc" "fix unit blocks the anchor"
has "$(deps)" "$FU|blocks|$F1" "fix unit blocks the first finding it answers"
has "$(deps)" "$FU|blocks|$F2" "fix unit blocks the second finding it answers"

# ---------------------------------------------------------------------------
# open-must-fix: the quiescence read helper.
# ---------------------------------------------------------------------------
if out=$("$SUT" open-must-fix --anchor tk-anc); then ok "open-must-fix exits 0 when a must-fix finding is open"; else bad "open-must-fix missed the open must-fix finding"; fi
has " $out " " $F1 " "open-must-fix names the must-fix finding"
if "$SUT" open-must-fix --anchor tk-anc --lane arch >/dev/null; then bad "open-must-fix found a must-fix on a lane with none"; else ok "open-must-fix is lane-scoped (none on arch)"; fi

# ---------------------------------------------------------------------------
# close-unvalidated: an approving lane clears its own unruled findings, and
# leaves a validated one (must-fix) alone.
# ---------------------------------------------------------------------------
eq "$(bstatus "$F2")" "open" "the unvalidated finding is open before the approve"
"$SUT" close-unvalidated --anchor tk-anc --lane correctness --reason "lane approved"
eq "$(bstatus "$F2")" "closed" "close-unvalidated closes the unvalidated finding"
eq "$(bstatus "$F1")" "open" "close-unvalidated leaves the must-fix finding for the validator/fix unit"

# ---------------------------------------------------------------------------
# close-answered: the must-fix finding closes once its fix unit LANDS (every
# blocks-blocker closed), which is what releases the re-gate quiescence and
# unwedges a pre_open_gate anchor. FU (wired above) blocks the must-fix F1.
# ---------------------------------------------------------------------------
eq "$(bstatus "$F1")" "open" "the must-fix finding is open with its fix unit still in flight"
"$SUT" close-answered --anchor tk-anc
eq "$(bstatus "$F1")" "open" "close-answered leaves a finding whose fix unit has NOT landed"
# The fix unit lands: its rework bead closes having pushed the fix to the branch.
gc bd update "$FU" --status=closed >/dev/null
"$SUT" close-answered --anchor tk-anc
eq "$(bstatus "$F1")" "closed" "close-answered closes the must-fix finding once its fix unit landed"
has "$(notes "$F1")" "fix unit landed" "the close records why the finding was resolved"
# Quiescence clears: gate-ensure's open-must-fix now finds nothing on the
# anchor, so the re-gate the open finding held is free to dispatch.
if "$SUT" open-must-fix --anchor tk-anc >/dev/null; then bad "open-must-fix still holds the re-gate after the finding closed"; else ok "quiescence clears once the answered finding closes, so the anchor re-gates"; fi

# A must-fix finding NO fix unit blocks is an objection nothing has answered
# yet: close-answered must leave it open, or it drops the objection.
F6=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "assets/scripts/new.sh:go()" --message "guard the nil deref")
"$SUT" set-disposition --finding "$F6" --anchor tk-anc --disposition must-fix
"$SUT" close-answered --anchor tk-anc
eq "$(bstatus "$F6")" "open" "close-answered leaves a must-fix finding no fix unit blocks (unanswered objection)"

# ---------------------------------------------------------------------------
# set-disposition must-fix hangs the fix unit's close-ordering edge FROM the
# ruling, so the fix unit blocks ONLY the findings the validator ruled must-fix
# — never one still unvalidated, which a later declined ruling could not close
# past that block.
# ---------------------------------------------------------------------------
: > "$STUB_DEPS"
store '[{"id":"tk-anc3","status":"open","assignee":"","title":"anchor3","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex"}},
        {"id":"fu3","status":"open","assignee":"","title":"Rework: address findings","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-anc3","source_review_bead":"rev3"}}]'
# The fix unit stands on the anchor (holds the merge) before any finding is ruled.
gc bd dep fu3 --blocks tk-anc3 >/dev/null
FA=$("$SUT" upsert --anchor tk-anc3 --lane codex --locus "assets/scripts/a.sh:f()" --message "guard the write")
FB=$("$SUT" upsert --anchor tk-anc3 --lane codex --locus "assets/scripts/b.sh:g()" --message "double-quote the expansion")
hasnt "$(deps)" "fu3|blocks|$FA" "an unvalidated finding carries no inbound fix-unit block"
"$SUT" set-disposition --finding "$FA" --anchor tk-anc3 --disposition must-fix
has "$(deps)" "$FA|blocks|tk-anc3" "must-fix wires the finding --blocks anchor"
has "$(deps)" "fu3|blocks|$FA" "…and hangs the fix unit's close-ordering edge onto the must-fix finding"
hasnt "$(deps)" "fu3|blocks|$FB" "the fix unit blocks ONLY the ruled must-fix finding, not the unvalidated one"

# ---------------------------------------------------------------------------
# Regression: a finding a fix unit blocks is DECLINED and still closes. With the
# block enforced the way bd enforces it, the earlier one-sided strip left the
# inbound fix-unit edge and the close failed rc=2, stalling the whole triage.
# ---------------------------------------------------------------------------
export STUB_ENFORCE_BLOCKS=1
FC=$("$SUT" upsert --anchor tk-anc3 --lane codex --locus "assets/scripts/c.sh:h()" --message "nit: rename for clarity")
"$SUT" wire-fix-unit --fix-unit fu3 --anchor tk-anc3 --findings "$FC"
has "$(deps)" "fu3|blocks|$FC" "the fix unit blocks the finding (the pre-decline state the incident hit)"
if "$SUT" set-disposition --finding "$FC" --anchor tk-anc3 --disposition declined --reason "not a real objection"; then
  ok "declining a fix-unit-blocked finding exits 0 (its inbound block was stripped before the close)"
else
  bad "declining a fix-unit-blocked finding failed (rc=2) — the inbound fix-unit block was not stripped"
fi
eq "$(bstatus "$FC")" "closed" "the declined finding closes despite the fix unit that blocked it"
hasnt "$(deps)" "fu3|blocks|$FC" "…and the stale fix-unit edge onto the declined finding is gone"
unset STUB_ENFORCE_BLOCKS

# ---------------------------------------------------------------------------
# Human-lane fix unit: pr-facts files one rework child per human batch, carrying
# the batch's review ids in source_review and NO source_review_bead. A human
# must-fix finding must hang THAT child's close-ordering edge — not a machine
# child that happens to stand on the same anchor — so the finding closes when the
# human batch lands, and never before. Both children stand on the anchor here, so
# the assertions prove the lane match discriminates rather than picking either.
# ---------------------------------------------------------------------------
: > "$STUB_DEPS"
store '[{"id":"tk-anch","status":"open","assignee":"","title":"anchorH","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex"}},
        {"id":"cfuh","status":"open","assignee":"","title":"Address review comments on PR#7","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-anch","source_review":"111,222"}},
        {"id":"mfuh","status":"open","assignee":"","title":"Rework: address codex findings","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-anch","source_review_bead":"revH"}}]'
gc bd dep cfuh --blocks tk-anch >/dev/null
gc bd dep mfuh --blocks tk-anch >/dev/null
FHM=$("$SUT" upsert --anchor tk-anch --lane human --source "human:johnzook" --locus "assets/scripts/z.sh:go()" --message "handle the empty batch")
"$SUT" set-disposition --finding "$FHM" --anchor tk-anch --disposition must-fix
has "$(deps)" "$FHM|blocks|tk-anch" "a human must-fix finding blocks the anchor"
has "$(deps)" "cfuh|blocks|$FHM" "must-fix hangs the human batch child's close-ordering edge onto the human finding"
hasnt "$(deps)" "mfuh|blocks|$FHM" "…and never the machine child, whose source_review_bead marks a different lane"
"$SUT" close-answered --anchor tk-anch
eq "$(bstatus "$FHM")" "open" "close-answered leaves the human finding open while its batch child is in flight"
gc bd update cfuh --status=closed >/dev/null
"$SUT" close-answered --anchor tk-anch
eq "$(bstatus "$FHM")" "closed" "close-answered closes the human finding once its batch child lands"
has "$(notes "$FHM")" "fix unit landed" "the close records why the human finding was resolved"

# ---------------------------------------------------------------------------
# close-resolved: a human's re-approval (recorded pr_posture=approved) closes the
# anchor's HUMAN objection beads whatever route the fix took — the signal
# close-answered cannot see. Scoped to human-source beads, so a machine finding
# and its machine fix unit are untouched; and it strips a finding's inbound blocks
# so the close never waits on an unrelated blocker (the PR#887 mis-wiring).
# ---------------------------------------------------------------------------
: > "$STUB_DEPS"
export STUB_ENFORCE_BLOCKS=1   # prove the fix-unit-first order and the strip are real
store '[{"id":"tk-ancR","status":"open","assignee":"","title":"anchorR","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex","pr_posture":"changes_requested@2026-09-30T00:00:00Z"}},
        {"id":"hfu","status":"open","assignee":"","title":"Address review comments on PR#9","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancR","source_review":"501"}},
        {"id":"mfu","status":"open","assignee":"","title":"Rework: address codex findings","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancR","source_review_bead":"revR"}},
        {"id":"unrel","status":"open","assignee":"","title":"Unrelated check-fix","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-other","source_review_bead":"revX"}}]'
gc bd dep hfu --blocks tk-ancR >/dev/null
gc bd dep mfu --blocks tk-ancR >/dev/null
HF=$("$SUT" upsert --anchor tk-ancR --lane human --source "human:johnzook" --locus "assets/scripts/demo.sh:clip()" --message "attach the demo clip")
"$SUT" set-disposition --finding "$HF" --anchor tk-ancR --disposition must-fix
MF=$("$SUT" upsert --anchor tk-ancR --lane codex --locus "assets/scripts/x.sh:f()" --message "guard the write")
"$SUT" set-disposition --finding "$MF" --anchor tk-ancR --disposition must-fix
# The human finding is also wired to block behind an unrelated fix unit — the
# tk-kljbvk shape — so its close must not depend on that bead.
gc bd dep unrel --blocks "$HF" >/dev/null

# Not approved yet: the objection stands and nothing closes.
"$SUT" close-resolved --anchor tk-ancR
eq "$(bstatus "$HF")" "open" "close-resolved leaves the human finding open while the posture is changes_requested"
eq "$(bstatus hfu)" "open" "…and leaves the human fix unit open"

# The human re-approves: pr-facts records pr_posture=approved on the anchor.
store "$(jq -c 'map(if .id=="tk-ancR" then .metadata.pr_posture="approved@2026-09-30T13:00:00Z" else . end)' "$STUB_STORE")"
"$SUT" close-resolved --anchor tk-ancR
eq "$(bstatus "$HF")" "closed" "close-resolved closes the human must-fix finding on re-approval"
eq "$(bstatus hfu)" "closed" "…and closes the human-batch fix unit that answered it"
has "$(notes "$HF")" "re-approved" "the close records the re-approval as the resolution"
# The strip: the close did not wait on the unrelated blocker, and only its EDGE
# is dropped — the unrelated bead itself is another lane's and is left alone.
hasnt "$(deps)" "unrel|blocks|$HF" "close-resolved strips the finding's inbound blocks so an unrelated blocker cannot wedge it"
eq "$(bstatus unrel)" "open" "…and closes only the objection, never the unrelated bead"
# Scope: the machine objection is the machine lane's, and a human approval is not
# a machine validation, so the machine finding and its fix unit still hold.
eq "$(bstatus "$MF")" "open" "close-resolved leaves the machine must-fix finding — a human approval is not a machine validation"
eq "$(bstatus mfu)" "open" "…and leaves the machine fix unit open, still holding the merge"
has " $(probe_blockers tk-ancR) " " mfu " "the machine fix unit still blocks the anchor"
unset STUB_ENFORCE_BLOCKS

# A deferred human finding is a tracked post-merge follow-up that holds nothing;
# re-approval does not close it, and an already-declined one is closed already.
FD=$("$SUT" upsert --anchor tk-ancR --lane human --source "human:johnzook" --locus "docs/readme.md" --message "expand this section later")
"$SUT" set-disposition --finding "$FD" --anchor tk-ancR --disposition deferred --reason "own PR"
"$SUT" close-resolved --anchor tk-ancR
eq "$(bstatus "$FD")" "open" "close-resolved leaves a deferred human finding open (a post-merge tracker, not a merge hold)"

# An anchor with no recorded posture — a pre-open gate with no PR — has no
# re-approval to read, so close-resolved is a no-op.
store '[{"id":"tk-preR","status":"open","assignee":"","title":"pre-open","notes":"","metadata":{"merge_result":"pre_open_gate","check_set":"codex"}}]'
FP=$("$SUT" upsert --anchor tk-preR --lane human --source "human:johnzook" --locus "a.sh:f()" --message "fix it")
"$SUT" set-disposition --finding "$FP" --anchor tk-preR --disposition must-fix
"$SUT" close-resolved --anchor tk-preR
eq "$(bstatus "$FP")" "open" "close-resolved no-ops on an anchor with no recorded posture (no PR to re-approve)"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
