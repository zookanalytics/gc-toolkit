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
store '[{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness","pr_number":"42","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}}]'
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
# set-disposition deferred: a real objection becomes tracked later-work. The
# finding CLOSES (no stay-open orphan that holds the human review hostage), a
# claimable follow-up bead carries the work, and the follow-up — not the finding
# — holds the discovered-from provenance.
# ---------------------------------------------------------------------------
F3=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "docs/x.md" --message "stale reference to a retired script")
"$SUT" set-disposition --finding "$F3" --anchor tk-anc --disposition deferred --reason "the rewrite it needs lands in the next PR"
eq "$(meta "$F3" 'finding.disposition')" "deferred" "disposition recorded as deferred"
eq "$(bstatus "$F3")" "closed" "a deferred finding closes — no stay-open orphan holding the review"
F3FU=$(meta "$F3" 'finding.follow_up')
if [ -n "$F3FU" ] && [ "$F3FU" != "<absent>" ]; then ok "deferred files a follow-up bead and records its id on the finding"; else bad "deferred did not record finding.follow_up"; fi
has "$(deps)" "$F3FU|discovered-from|tk-anc" "the follow-up — not the finding — carries the discovered-from provenance"
hasnt "$(deps)" "$F3|discovered-from|tk-anc" "the closed finding holds no provenance edge of its own"
hasnt "$(deps)" "$F3|blocks|tk-anc" "deferred writes no blocks edge"
hasnt " $(probe_blockers tk-anc) " " $F3 " "merge.sh's probe does NOT see the deferred finding"
has "$(meta "$F3" 'finding.reply')" "$F3FU" "the follow-up id is stamped as the reply the raiser's thread receives"
has "$(notes "$F3")" "the rewrite it needs lands in the next PR" "the deferral reason is recorded on the finding"
# The follow-up is a DISPATCHABLE unit, not a bare open task: gated behind the
# anchor (bd withholds it until the merge closes the anchor) and armed to the fix
# pool, so deferred-dispatch's reconcile slings it once the merge lands. An
# un-routed follow-up was the silent drop this whole change retires.
eq "$(bstatus "$F3FU")" "open" "the follow-up stays open so reconcile can dispatch it"
has "$(deps)" "tk-anc|blocks|$F3FU" "the anchor blocks the follow-up — it waits for the merge"
eq "$(meta "$F3FU" 'gc.dispatch_when_ready')" "gc-toolkit/gc-toolkit.polecat" "the follow-up is armed to the anchor's fix pool (derived from gc.execution_routed_to)"
has "$(meta "$F3FU" 'gc.dispatch_when_ready_args')" "mol-polecat-work" "...to be re-poured through mol-polecat-work"

# ---------------------------------------------------------------------------
# set-disposition must-fix -> deferred: the reclassification retracts the blocks
# edge (else merge.sh keeps reading the finding as a live blocker and a deferred
# finding holds the merge it must not), closes the finding, and files the
# follow-up carrying the provenance.
# ---------------------------------------------------------------------------
F5=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "assets/scripts/qux.sh:main()" --message "double-quote the array expansion")
"$SUT" set-disposition --finding "$F5" --anchor tk-anc --disposition must-fix
has " $(probe_blockers tk-anc) " " $F5 " "must-fix first wires the finding as a live blocker"
"$SUT" set-disposition --finding "$F5" --anchor tk-anc --disposition deferred --reason "safer to land and fix fresh"
eq "$(meta "$F5" 'finding.disposition')" "deferred" "reclassified must-fix -> deferred"
eq "$(bstatus "$F5")" "closed" "the reclassified finding closes"
hasnt "$(deps)" "$F5|blocks|tk-anc" "must-fix -> deferred retracts the blocks edge"
hasnt " $(probe_blockers tk-anc) " " $F5 " "merge.sh's probe no longer sees the reclassified finding"
F5FU=$(meta "$F5" 'finding.follow_up')
has "$(deps)" "$F5FU|discovered-from|tk-anc" "the reclassification files a follow-up carrying the provenance"
has "$(deps)" "tk-anc|blocks|$F5FU" "the reclassified deferral's follow-up is gated behind the anchor"
eq "$(meta "$F5FU" 'gc.dispatch_when_ready')" "gc-toolkit/gc-toolkit.polecat" "the reclassified deferral's follow-up is armed to the fix pool"

# ---------------------------------------------------------------------------
# --fix-pool overrides the pool the anchor would otherwise supply.
# ---------------------------------------------------------------------------
F6=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "assets/scripts/z.sh:z()" --message "defer with an explicit fix pool")
"$SUT" set-disposition --finding "$F6" --anchor tk-anc --disposition deferred --reason "later work" --fix-pool "gc-toolkit/gc-toolkit.polecat-codex"
F6FU=$(meta "$F6" 'finding.follow_up')
eq "$(meta "$F6FU" 'gc.dispatch_when_ready')" "gc-toolkit/gc-toolkit.polecat-codex" "--fix-pool overrides the anchor-derived fix pool"

# ---------------------------------------------------------------------------
# set-disposition deferred FAILS CLOSED when no fix pool resolves: the follow-up
# cannot be made dispatchable, so the finding does not close and no orphan is
# filed. An unrouted follow-up silently dropped is exactly the failure this
# retires — leaving the finding holding the review beats promising work that
# nothing will ever pick up.
# ---------------------------------------------------------------------------
store "$(jq -c '. + [{"id":"tk-nopool","status":"open","assignee":"","title":"a","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness"}}]' "$STUB_STORE")"
F8=$("$SUT" upsert --anchor tk-nopool --lane correctness --locus "x.sh:x()" --message "no pool anywhere")
BEFORE_N=$(jq 'length' "$STUB_STORE")
"$SUT" set-disposition --finding "$F8" --anchor tk-nopool --disposition deferred --reason "later"; rc=$?
if [ "$rc" -ne 0 ]; then ok "deferred fails closed (exit $rc) when no fix pool resolves"; else bad "deferred closed with an unroutable follow-up (exit 0)"; fi
eq "$(bstatus "$F8")" "open" "the finding stays open on a fail-closed deferral — it still holds the review"
eq "$(meta "$F8" 'finding.follow_up')" "<absent>" "no follow-up id is recorded on a fail-closed deferral"
eq "$(jq 'length' "$STUB_STORE")" "$BEFORE_N" "no orphan follow-up bead is filed when the pool cannot be resolved"

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
# set-disposition needs-you: a comment only the operator can judge. The finding
# stays OPEN (holding its review changes-requested), a visit is filed for the
# operator, and the visit id is stamped as the reply the raiser's thread receives.
# ---------------------------------------------------------------------------
# A stub escalate.sh files a visit-shaped bead the needs-you arm looks up by key.
cat > "$TMP/escalate-stub.sh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
subj=""; key=""; msg=""
while [ $# -gt 0 ]; do case "$1" in
  --subject) subj="${2:-}"; shift 2 ;;
  --key) key="${2:-}"; shift 2 ;;
  --message) msg="${2:-}"; shift 2 ;;
  --pool) shift 2 ;;
  *) shift ;;
esac; done
existing=$(gc bd list --metadata-field escalation_key="$key" --status=open,in_progress,blocked --json 2>/dev/null \
  | jq -r --arg s "$subj" '[.[]? | select((.metadata["gc.continuation_group"] // "") == $s)][0].id // empty')
[ -n "$existing" ] && exit 0
vid=$(gc bd create "visit: $subj — $msg" -t task --json | jq -r '.id // .[0].id')
gc bd update "$vid" --set-metadata task_kind=visit --set-metadata escalation_key="$key" \
  --set-metadata gc.continuation_group="$subj" --set-metadata gc.routed_to=human >/dev/null
gc bd dep add "$vid" "$subj" --type=tracks >/dev/null 2>&1 || true
STUB
chmod +x "$TMP/escalate-stub.sh"
export GC_ESCALATE_SH="$TMP/escalate-stub.sh"

FNU=$("$SUT" upsert --anchor tk-anc --lane human --source "human:johnzook" --locus "specs/x.md" --message "does this match the product intent?")
gc bd update "$FNU" --set-metadata finding.comment_id=778899 >/dev/null
"$SUT" set-disposition --finding "$FNU" --anchor tk-anc --disposition needs-you --reason "turns on product intent only the operator knows"
eq "$(meta "$FNU" 'finding.disposition')" "needs-you" "disposition recorded as needs-you"
eq "$(bstatus "$FNU")" "open" "a needs-you finding stays OPEN — it holds the review until the operator rules"
FNUV=$(meta "$FNU" 'finding.visit')
if [ -n "$FNUV" ] && [ "$FNUV" != "<absent>" ]; then ok "needs-you files a visit and records its id on the finding"; else bad "needs-you did not record finding.visit"; fi
eq "$(meta "$FNUV" task_kind)" "visit" "the filed bead is a visit"
has "$(meta "$FNU" 'finding.reply')" "$FNUV" "the visit id is stamped as the reply the raiser's thread receives"
hasnt " $(probe_blockers tk-anc) " " $FNU " "needs-you holds nothing via blocks — the open finding and the review are the hold"
# Idempotent: re-ruling needs-you reuses the one open visit (escalate dedups on key).
BEFORE_V=$(jq 'length' "$STUB_STORE")
"$SUT" set-disposition --finding "$FNU" --anchor tk-anc --disposition needs-you --reason "still the operator's call"
eq "$(meta "$FNU" 'finding.visit')" "$FNUV" "re-ruling needs-you reuses the same visit"
eq "$(jq 'length' "$STUB_STORE")" "$BEFORE_V" "…and files no second visit"

# must-fix -> needs-you retracts the block: the review, not a blocks edge, holds it.
FNU2=$("$SUT" upsert --anchor tk-anc --lane human --source "human:johnzook" --locus "a.md" --message "unsure about the scope here")
gc bd update "$FNU2" --set-metadata finding.comment_id=112233 >/dev/null
"$SUT" set-disposition --finding "$FNU2" --anchor tk-anc --disposition must-fix
has " $(probe_blockers tk-anc) " " $FNU2 " "must-fix first wires the block"
"$SUT" set-disposition --finding "$FNU2" --anchor tk-anc --disposition needs-you --reason "escalating to the operator"
hasnt " $(probe_blockers tk-anc) " " $FNU2 " "must-fix -> needs-you retracts the block"
eq "$(bstatus "$FNU2")" "open" "the reclassified needs-you finding stays open"

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

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
