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
# — holds the discovered-from provenance, pointing at the finding. The stub keeps
# one edge per pair the way bd does, so provenance on the follow-up/anchor pair
# would take the gate's pair and the deferral would fail closed.
# ---------------------------------------------------------------------------
F3=$("$SUT" upsert --anchor tk-anc --lane correctness --locus "docs/x.md" --message "stale reference to a retired script")
"$SUT" set-disposition --finding "$F3" --anchor tk-anc --disposition deferred --reason "the rewrite it needs lands in the next PR"
eq "$(meta "$F3" 'finding.disposition')" "deferred" "disposition recorded as deferred"
eq "$(bstatus "$F3")" "closed" "a deferred finding closes — no stay-open orphan holding the review"
F3FU=$(meta "$F3" 'finding.follow_up')
if [ -n "$F3FU" ] && [ "$F3FU" != "<absent>" ]; then ok "deferred files a follow-up bead and records its id on the finding"; else bad "deferred did not record finding.follow_up"; fi
has "$(deps)" "$F3FU|discovered-from|$F3" "the follow-up — not the finding — carries the discovered-from provenance, pointing at the finding"
hasnt "$(deps)" "$F3|discovered-from|" "the closed finding holds no provenance edge of its own"
hasnt "$(deps)" "$F3FU|discovered-from|tk-anc" "no provenance edge on the follow-up/anchor pair — that pair is the gate's"
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
# The gate must point anchor->follow-up, never the reverse. The reverse wires
# the follow-up as the anchor's blocker, which holds the anchor merge and fails
# edge_exists so the deferral cannot close. Assert the orientation through the
# same down-blocker probe merge.sh and bd-ready run, not just the raw edge row:
# the follow-up is blocked BY the anchor, and never blocks the anchor merge.
has " $(probe_blockers "$F3FU") " " tk-anc " "the follow-up is blocked BY the anchor (anchor in its down-blockers) — bd holds it unready until the merge closes"
hasnt " $(probe_blockers tk-anc) " " $F3FU " "the follow-up never blocks the anchor merge — the reversed edge would wrongly hold the anchor"
hasnt "$(deps)" "$F3FU|blocks|tk-anc" "no reverse blocks edge: the follow-up is not wired as the anchor's blocker"
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
has "$(deps)" "$F5FU|discovered-from|$F5" "the reclassification files a follow-up carrying the provenance"
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
eq "$(meta "$F8" 'finding.disposition')" "unvalidated" "a fail-closed deferral leaves the finding unvalidated, so the validator's retry set still contains it — not stamped deferred and silently dropped"
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
vid=$(gc bd create "visit: $subj — $msg" -t task --json | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
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
# open-must-fix: the read pr-open.sh holds a publish behind.
# ---------------------------------------------------------------------------
if out=$("$SUT" open-must-fix --anchor tk-anc); then ok "open-must-fix exits 0 when a must-fix finding is open"; else bad "open-must-fix missed the open must-fix finding"; fi
has " $out " " $F1 " "open-must-fix names the must-fix finding"
if "$SUT" open-must-fix --anchor tk-anc --lane arch >/dev/null; then bad "open-must-fix found a must-fix on a lane with none"; else ok "open-must-fix is lane-scoped (none on arch)"; fi

# ---------------------------------------------------------------------------
# close-unvalidated: a green lane clears its own unruled findings, and leaves a
# validated one (must-fix) alone. gate-ensure.sh drives this per reconcile pass
# off the derived green lane state (the close moved out of signoff.sh), so it
# must also be a safe no-op when the lane has nothing left to resolve.
# ---------------------------------------------------------------------------
eq "$(bstatus "$F2")" "open" "the unvalidated finding is open before the lane derives green"
"$SUT" close-unvalidated --anchor tk-anc --lane correctness --reason "lane green"
eq "$(bstatus "$F2")" "closed" "close-unvalidated closes the unvalidated finding"
eq "$(bstatus "$F1")" "open" "close-unvalidated leaves the must-fix finding for the validator/fix unit"
# Re-run on the now-clean lane: it closes nothing and still exits 0. This is the
# per-pass-safe shape gate-ensure relies on — it early-returns before the cache
# invalidation when there is nothing to resolve, exactly as close-answered does.
if "$SUT" close-unvalidated --anchor tk-anc --lane correctness >/dev/null; then ok "close-unvalidated is a no-op when the lane has no unvalidated findings"; else bad "close-unvalidated errored on a lane with nothing to resolve"; fi
eq "$(bstatus "$F1")" "open" "…and still leaves the must-fix finding open"

# --lanes: one call resolves several green lanes in a single finding-set read
# (the batched shape gate-ensure uses after its gate loop), and stays lane-scoped
# — a lane not named is left alone.
LA=$("$SUT" upsert --anchor tk-anc --lane arch --locus "assets/scripts/a.sh:a()" --message "arch unvalidated one")
LP=$("$SUT" upsert --anchor tk-anc --lane pm --locus "docs/p.md" --message "pm unvalidated one")
LD=$("$SUT" upsert --anchor tk-anc --lane docs --locus "docs/d.md" --message "docs unvalidated one")
"$SUT" close-unvalidated --anchor tk-anc --lanes "arch,pm" --reason "lanes green at deadbeef"
eq "$(bstatus "$LA")" "closed" "close-unvalidated --lanes closes the arch finding"
eq "$(bstatus "$LP")" "closed" "…and the pm finding, in the one call"
eq "$(bstatus "$LD")" "open" "…and leaves a lane it was not given (docs) alone"
eq "$(bstatus "$F1")" "open" "…and still never touches the must-fix finding"

# ---------------------------------------------------------------------------
# close-answered: the must-fix finding closes once its fix unit LANDS (every
# blocks-blocker closed), which releases the publish and the merge, unwedging a
# pre_open_gate anchor. FU (wired above) blocks the must-fix F1.
# ---------------------------------------------------------------------------
eq "$(bstatus "$F1")" "open" "the must-fix finding is open with its fix unit still in flight"
"$SUT" close-answered --anchor tk-anc
eq "$(bstatus "$F1")" "open" "close-answered leaves a finding whose fix unit has NOT landed"
# The fix unit lands: its rework bead closes having pushed the fix to the branch.
gc bd update "$FU" --status=closed >/dev/null
"$SUT" close-answered --anchor tk-anc
eq "$(bstatus "$F1")" "closed" "close-answered closes the must-fix finding once its fix unit landed"
has "$(notes "$F1")" "fix unit landed" "the close records why the finding was resolved"
# The anchor is released: open-must-fix, the read pr-open.sh publishes behind,
# now finds nothing on it, so nothing the open finding held is left.
if "$SUT" open-must-fix --anchor tk-anc >/dev/null; then bad "open-must-fix still holds the publish after the finding closed"; else ok "open-must-fix clears once the answered finding closes, so the anchor can publish"; fi

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
# set-disposition must-fix wires the close-ordering edge even when the fix unit
# has ALREADY LANDED. The dispatch of a fix unit and the validator's must-fix
# ruling race: a fix unit can close before its finding is ruled. Wiring only to a
# LIVE fix unit (the old behavior) then left the finding edge-less, and nothing
# ever closed it — it wedged the re-gate at pre_open_gate for days. A landed fix
# unit still blocks the finding, and bd refuses a close only on an OPEN blocker,
# so close-answered closes the finding on the next pass.
# ---------------------------------------------------------------------------
: > "$STUB_DEPS"
export STUB_ENFORCE_BLOCKS=1
store '[{"id":"tk-ancL","status":"open","assignee":"","title":"ancL","notes":"","metadata":{"merge_result":"pre_open_gate","check_set":"codex"}},
        {"id":"fuL","status":"closed","assignee":"","title":"Rework: address codex findings","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancL","source_review_bead":"revL"}}]'
FL=$("$SUT" upsert --anchor tk-ancL --lane codex --locus "assets/scripts/l.sh:f()" --message "guard the write")
"$SUT" set-disposition --finding "$FL" --anchor tk-ancL --disposition must-fix
has "$(deps)" "fuL|blocks|$FL" "must-fix hangs the close-ordering edge onto a fix unit that ALREADY LANDED (the dispatch-vs-ruling race)"
"$SUT" close-answered --anchor tk-ancL
eq "$(bstatus "$FL")" "closed" "close-answered then closes the finding — a landed (closed) blocker does not refuse the close"
unset STUB_ENFORCE_BLOCKS

# ---------------------------------------------------------------------------
# close-answered is the backstop for an edge-less must-fix finding: if the
# close-ordering edge was missed for any reason, a finding with NO blocker whose
# lane's fix unit has LANDED is not an unanswered objection — its fix is on the
# branch — so close-answered closes it from the lane census rather than letting it
# wedge the re-gate. (The finding here carries no inbound edge at all, simulating
# the missed wire.)
# ---------------------------------------------------------------------------
: > "$STUB_DEPS"
store '[{"id":"tk-ancE","status":"open","assignee":"","title":"ancE","notes":"","metadata":{"merge_result":"pre_open_gate","check_set":"codex"}},
        {"id":"fuE","status":"closed","assignee":"","title":"Rework: address codex findings","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancE","source_review_bead":"revE"}}]'
FE=$("$SUT" upsert --anchor tk-ancE --lane codex --locus "assets/scripts/e.sh:f()" --message "guard the write")
gc bd update "$FE" --set-metadata finding.disposition=must-fix >/dev/null
hasnt "$(deps)" "fuE|blocks|$FE" "the finding is edge-less (the close-ordering edge was missed)"
"$SUT" close-answered --anchor tk-ancE
eq "$(bstatus "$FE")" "closed" "close-answered closes an edge-less must-fix finding once its lane's fix unit has LANDED (the backstop)"
has "$(notes "$FE")" "no close-ordering edge" "…and records that it was matched by lane, not by edge"

# An edge-less must-fix finding whose lane's fix unit is still IN FLIGHT must stay
# open: the fix has not landed, so the finding still holds. (With no live fix unit
# AND no landed one — a genuinely unanswered objection — it also stays open, as
# the earlier F6 case proves.)
: > "$STUB_DEPS"
store '[{"id":"tk-ancF","status":"open","assignee":"","title":"ancF","notes":"","metadata":{"merge_result":"pre_open_gate","check_set":"codex"}},
        {"id":"fuF","status":"open","assignee":"","title":"Rework: address codex findings","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancF","source_review_bead":"revF"}}]'
FF=$("$SUT" upsert --anchor tk-ancF --lane codex --locus "assets/scripts/f.sh:f()" --message "guard the write")
gc bd update "$FF" --set-metadata finding.disposition=must-fix >/dev/null
"$SUT" close-answered --anchor tk-ancF
eq "$(bstatus "$FF")" "open" "close-answered leaves an edge-less must-fix finding open while its lane's fix unit is in flight"

# ---------------------------------------------------------------------------
# fix-in-flight: the actor gate-ensure's quiescence holds on. It names the fix
# unit answering an open must-fix finding — the finding's live blocks-blocker, or
# for an edge-less finding the live fix unit on its lane — and reports the open
# must-fix findings no fix unit answers, so a hold never names a bead that is not
# acting on the anchor.
# ---------------------------------------------------------------------------
: > "$STUB_DEPS"
store '[{"id":"tk-ancG","status":"open","assignee":"","title":"ancG","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex"}},
        {"id":"fuG","status":"in_progress","assignee":"","title":"Rework: address codex findings","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancG","source_review_bead":"revG"}}]'
GA=$("$SUT" upsert --anchor tk-ancG --lane codex --locus "assets/scripts/g.sh:a()" --message "guard the read")
GB=$("$SUT" upsert --anchor tk-ancG --lane codex --locus "assets/scripts/g.sh:b()" --message "quote the expansion")
out=$("$SUT" fix-in-flight --anchor tk-ancG); rc=$?
eq "$rc" "1" "fix-in-flight exits 1 when no must-fix finding is open"
eq "$out" "" "…and reports no unanswered finding"
# The ruling hangs fuG's close-ordering edge onto GA, so fuG is GA's fix in flight.
"$SUT" set-disposition --finding "$GA" --anchor tk-ancG --disposition must-fix
out=$("$SUT" fix-in-flight --anchor tk-ancG); rc=$?
eq "$rc" "0" "fix-in-flight exits 0 while a live fix unit answers an open must-fix finding"
eq "$out" "fuG in_progress $GA" "…naming the fix unit, its status, and the finding it answers"
# The fix unit lands. GA's only blocker is closed, so no fix is in flight for it:
# its release is close-answered's, and fix-in-flight reports it unanswered.
gc bd update fuG --status=closed >/dev/null
out=$("$SUT" fix-in-flight --anchor tk-ancG); rc=$?
eq "$rc" "1" "a must-fix finding whose fix unit has landed has no fix in flight"
eq "$out" "$GA" "…and is reported unanswered"
hasnt " $out " " $GB " "an unvalidated finding is not a demand, so it is never reported"

# An edge-less must-fix finding is matched by lane: a human finding takes the
# human batch's fix unit (no source_review_bead), never a machine lane's.
: > "$STUB_DEPS"
store '[{"id":"tk-ancH","status":"open","assignee":"","title":"ancH","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex"}},
        {"id":"fuHm","status":"open","assignee":"","title":"Rework: address codex findings","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancH","source_review_bead":"revH"}}]'
HH=$("$SUT" upsert --anchor tk-ancH --lane human --locus "PR review" --message "rename the flag")
gc bd update "$HH" --set-metadata finding.disposition=must-fix >/dev/null
out=$("$SUT" fix-in-flight --anchor tk-ancH); rc=$?
eq "$rc" "1" "a machine lane's fix unit does not answer an edge-less human finding"
eq "$out" "$HH" "…so the human finding is reported unanswered"
# pr-facts.sh files the human batch's fix unit: task_kind=rework, no source_review_bead.
store "$(jq -c '. + [{"id":"fuHh","status":"open","assignee":"","title":"Address review comments","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancH","source_review":"5000"}}]' "$STUB_STORE")"
out=$("$SUT" fix-in-flight --anchor tk-ancH); rc=$?
eq "$rc" "0" "the human batch's fix unit answers the edge-less human finding"
eq "$out" "fuHh open $HH" "…matched by lane"
# A read that fails is never "no fix unit".
STUB_DEP_GARBAGE=1 "$SUT" fix-in-flight --anchor tk-ancH >/dev/null 2>&1; rc=$?
eq "$rc" "2" "an unreadable blocker read exits 2"
STUB_LIST_FAIL=1 "$SUT" fix-in-flight --anchor tk-ancH >/dev/null 2>&1; rc=$?
eq "$rc" "2" "an unreadable finding read exits 2"

# ---------------------------------------------------------------------------
# shed-orphaned: an unvalidated finding whose anchor has left the open set is
# moot (no validator runs on closed work) and is shed, keyed on the anchor being
# closed and never on an approve. A finding on a still-open anchor is left alone,
# for gate-ensure's per-anchor pass.
# ---------------------------------------------------------------------------
: > "$STUB_DEPS"
store '[{"id":"tk-open","status":"open","assignee":"","title":"open anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness"}},
        {"id":"tk-gone","status":"closed","assignee":"","title":"merged anchor","notes":"","metadata":{"merge_result":"merged"}}]'
ORPH=$("$SUT" upsert --anchor tk-gone --lane correctness --locus "assets/scripts/g.sh:g()" --message "orphan on a merged anchor")
LIVEF=$("$SUT" upsert --anchor tk-open --lane correctness --locus "assets/scripts/h.sh:h()" --message "live on an open anchor")
"$SUT" shed-orphaned --reason "test"
eq "$(bstatus "$ORPH")" "closed" "shed-orphaned closes an unvalidated finding on a closed anchor"
eq "$(bstatus "$LIVEF")" "open" "…and leaves one on a still-open anchor for gate-ensure's per-anchor pass"

# ---------------------------------------------------------------------------
# upsert files a finding in ONE write, so a failure leaves a fully stamped
# finding or none. A bead stamped in a second write was left open with no
# metadata when that write failed: no finding reader selects it, and the retry's
# dedup, which reads finding.key, filed a stamped twin beside it.
# ---------------------------------------------------------------------------
: > "$STUB_DEPS"
store '[{"id":"tk-ancA","status":"open","assignee":"","title":"ancA","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness"}}]'
# The id the stub's next create mints.
next_id() { printf 'new-%s' "$(( $(jq 'length' "$STUB_STORE") + 1 ))"; }
# Open beads titled as findings that carry no task_kind, so no finding reader sees them.
live_unstamped() {
  jq -r '[ .[] | select((.status // "open") != "closed") | select((.title // "") | startswith("finding["))
               | select(((.metadata // {}).task_kind // "") == "") ] | length' "$STUB_STORE"
}
live_titled() { jq -r --arg t "$1" '[ .[] | select((.status // "open") != "closed") | select(.title == $t) ] | length' "$STUB_STORE"; }
upsert_a() { "$SUT" upsert --anchor tk-ancA --lane correctness --locus "assets/scripts/atomic.sh:$1()" --message "$2"; }
key_a() { "$SUT" key --lane correctness --locus "assets/scripts/atomic.sh:$1()" --message "$2"; }

: > "$STUB_GC_LOG"
FA1=$(upsert_a one "stamp the birth write")
eq "$(meta "$FA1" 'finding.key')" "$(key_a one "stamp the birth write")" "the create lands the finding's key"
has "$(cat "$STUB_GC_LOG")" "--metadata {\"task_kind\":\"finding\",\"anchor_bead\":\"tk-ancA\"" "the identity rides the create"
hasnt "$(cat "$STUB_GC_LOG")" "--set-metadata task_kind=finding" "…and no second write stamps it"

# The incident: the store refuses every write to the bead after its create.
NX=$(next_id)
export STUB_UPDATE_FAIL="$NX"
FA2=$(upsert_a two "survive a refused second write"); rc=$?
export STUB_UPDATE_FAIL=""
eq "$rc" "0" "a store that refuses every write after the create still files the finding"
eq "$FA2" "$NX" "…and upsert returns it"
eq "$(meta "$NX" 'finding.key')" "$(key_a two "survive a refused second write")" "…carrying its key"
eq "$(live_unstamped)" "0" "…so no open finding bead is left unstamped"
eq "$(upsert_a two "survive a refused second write")" "$NX" "the retry re-raises that finding"
eq "$(live_titled "finding[correctness]: survive a refused second write")" "1" "…and files no twin"

BEFORE=$(jq 'length' "$STUB_STORE")
export STUB_CREATE_FAIL=1
FA3=$(upsert_a three "retry a refused create"); rc=$?
export STUB_CREATE_FAIL=""
eq "$rc" "2" "a refused create exits 2"
eq "$FA3" "" "…prints no finding"
eq "$(jq 'length' "$STUB_STORE")" "$BEFORE" "…and leaves no bead"
FA3b=$(upsert_a three "retry a refused create")
eq "$(meta "$FA3b" 'finding.key')" "$(key_a three "retry a refused create")" "the retry files the finding with its key"
eq "$(live_titled "finding[correctness]: retry a refused create")" "1" "…once"

# The create lands and its reply is lost: the key it was born with finds it.
NX=$(next_id)
export STUB_CREATE_GARBAGE=1
FA4=$(upsert_a four "recover a lost create reply"); rc=$?
export STUB_CREATE_GARBAGE=""
eq "$rc" "0" "a create whose reply does not parse is recovered in the same call"
eq "$FA4" "$NX" "…by the key it was born with"
eq "$(live_unstamped)" "0" "…and no open finding bead is left unstamped"
eq "$(upsert_a four "recover a lost create reply")" "$NX" "the retry re-raises the landed finding"
eq "$(live_titled "finding[correctness]: recover a lost create reply")" "1" "…and files no twin"
# Inside a reconcile pass bd_list is memoized, and upsert's dedup read has cached
# the anchor's findings from before the create.
GC_RECONCILE_BD_CACHE=$(mktemp -d "$TMP/bdcache.XXXXXX"); export GC_RECONCILE_BD_CACHE
NX=$(next_id)
export STUB_CREATE_GARBAGE=1
FA6=$(upsert_a six "recover a lost reply past the pass cache"); rc=$?
export STUB_CREATE_GARBAGE=""
unset GC_RECONCILE_BD_CACHE
eq "$rc/$FA6" "0/$NX" "inside a reconcile pass the recovery reads past the cached pre-create findings"

# The create lands without its payload: the keyless bead is closed, not left open.
NX=$(next_id)
export STUB_DROP_KEYS="$NX:task_kind,anchor_bead,finding.lane,finding.key,finding.disposition,finding.source"
FA5=$(upsert_a five "close a keyless birth"); rc=$?
export STUB_DROP_KEYS=""
eq "$rc" "2" "a create whose payload did not land exits 2"
eq "$FA5" "" "…prints no finding"
eq "$(bstatus "$NX")" "closed" "…and closes the keyless bead it left"
eq "$(live_unstamped)" "0" "…so no open finding bead is left unstamped"
FA5b=$(upsert_a five "close a keyless birth")
eq "$(meta "$FA5b" 'finding.key')" "$(key_a five "close a keyless birth")" "the retry files the finding with its key"
eq "$(live_titled "finding[correctness]: close a keyless birth")" "1" "…and it is the only open bead with that title"

# ---------------------------------------------------------------------------
# A human finding whose question an open visit already carries. pr-facts mints a
# rework per human feedback batch, and that rework can put the question to the
# operator before the validator rules: a visit that tracks the rework, or one on
# the anchor that holds the rework through a blocks edge. Declining or deferring
# the finding then overrules a decision the operator holds, and its close lets
# pr-facts dismiss their review; a fresh needs-you visit asks them twice. So those
# rulings refuse (exit 3) and needs-you --visit defers to the open visit.
# List rows carry their dependencies the way `gc bd list --json` renders them,
# which is what the shared visit identity reads.
# ---------------------------------------------------------------------------
: > "$STUB_DEPS"
store '[{"id":"tk-ancV","status":"open","assignee":"","title":"PR#7 anchor","notes":"","metadata":{"merge_result":"pull_request","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat","pr_review_batch":"rework:rwV|0|5000","pr_issue_comment_batch":"rework:rwV|0|50"}},
        {"id":"rwV","status":"blocked","assignee":"","title":"Address review comments on PR#7 (through review 5000, comment 0)","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancV","source_review":"5000"},"dependencies":[{"issue_id":"rwV","depends_on_id":"visV","type":"blocks"}]},
        {"id":"visV","status":"open","assignee":"","title":"visit: tk-ancV — PR#7 approach is rejected; drop it or keep it?","notes":"","metadata":{"task_kind":"visit","escalation_key":"approach-rejected","gc.continuation_group":"tk-ancV","gc.routed_to":"human"},"dependencies":[{"issue_id":"visV","depends_on_id":"tk-ancV","type":"tracks"}]},
        {"id":"visOld","status":"closed","assignee":"","title":"visit: tk-ancV — an old question, already ruled","notes":"","metadata":{"task_kind":"visit","escalation_key":"old-question","gc.continuation_group":"tk-ancV"},"dependencies":[{"issue_id":"visOld","depends_on_id":"tk-ancV","type":"tracks"}]}]'
human_finding() { # <anchor> <locus> <message> <comment-id> [<review-id>]
  local f
  f=$("$SUT" upsert --anchor "$1" --lane human --source "human:johnzook" --locus "$2" --message "$3")
  gc bd update "$f" --set-metadata "finding.comment_id=$4" >/dev/null
  [ -z "${5:-}" ] || gc bd update "$f" --set-metadata "finding.review_id=$5" >/dev/null
  printf '%s' "$f"
}
FV1=$(human_finding tk-ancV "PR review" "This sweeps state that should not exist instead of fixing its cause" 5000 5000)

out=$("$SUT" open-visits --anchor tk-ancV); rc=$?
eq "$rc" "0" "open-visits exits 0 while a visit is open on the anchor's feedback"
has "$out" "visV	tracks anchor tk-ancV, holds rework rwV	" "…and names the visit holding the batch's rework, and the anchor it tracks"
has "$out" "approach-rejected	visit: tk-ancV — PR#7 approach is rejected" "…with its key and title, so the validator can read what it asks"
hasnt "$out" "visOld" "a closed visit carries no question the operator still holds"

BEFORE=$(jq 'length' "$STUB_STORE")
err=$("$SUT" set-disposition --finding "$FV1" --anchor tk-ancV --disposition declined --reason "a reaper is the principled design" --reply "We disagree." 2>&1 >/dev/null); rc=$?
eq "$rc" "3" "declining a human finding whose batch rework an open visit holds is refused (exit 3)"
has "$err" "visV" "…naming the visit that already carries the question"
has "$err" "needs-you --visit" "…and the ruling that defers to it"
eq "$(meta "$FV1" 'finding.disposition')" "unvalidated" "…and nothing is ruled, so the validator's retry set still holds the finding"
eq "$(bstatus "$FV1")" "open" "…and the finding stays open, so pr-facts keeps the operator's review changes-requested"
eq "$(meta "$FV1" 'finding.reply')" "<absent>" "…and no overrule is stamped for the write-back to post"
"$SUT" set-disposition --finding "$FV1" --anchor tk-ancV --disposition deferred --reason "later" >/dev/null 2>&1; rc=$?
eq "$rc" "3" "deferring it is refused the same way"
eq "$(meta "$FV1" 'finding.follow_up')" "<absent>" "…and no follow-up is filed"
"$SUT" set-disposition --finding "$FV1" --anchor tk-ancV --disposition needs-you --reason "the operator's call" >/dev/null 2>&1; rc=$?
eq "$rc" "3" "a needs-you that would file a second visit for the same question is refused"
eq "$(jq 'length' "$STUB_STORE")" "$BEFORE" "…and none of the refused rulings wrote a bead"

"$SUT" set-disposition --finding "$FV1" --anchor tk-ancV --disposition needs-you --visit visV --reason "visV already asks whether to drop the approach"; rc=$?
eq "$rc" "0" "needs-you --visit defers to the open visit"
eq "$(meta "$FV1" 'finding.disposition')" "needs-you" "…recording needs-you"
eq "$(meta "$FV1" 'finding.visit')" "visV" "…naming the visit that carries the decision"
has "$(meta "$FV1" 'finding.reply')" "visit visV already asks you for it" "…as the reply the raiser's thread receives"
eq "$(bstatus "$FV1")" "open" "…and the finding stays open, holding the review"
eq "$(jq 'length' "$STUB_STORE")" "$BEFORE" "…and no second visit is filed"
has "$(notes "$FV1")" "deferred to open visit visV" "…and the finding's notes record the deferral"

FV2=$(human_finding tk-ancV "assets/scripts/x.sh" "quote the expansion" 4999 5000)
"$SUT" set-disposition --finding "$FV2" --anchor tk-ancV --disposition must-fix >/dev/null 2>&1; rc=$?
eq "$rc" "3" "must-fix is refused too: it would settle the operator's question as keep-and-fix"
hasnt "$(deps)" "$FV2|blocks|tk-ancV" "…and wires no hold"

# A Conversation comment names no review, so the anchor's batch ledger is what
# names its batch's rework.
FV3=$(human_finding tk-ancV "PR conversation" "why an hourly order at all?" 40)
"$SUT" set-disposition --finding "$FV3" --anchor tk-ancV --disposition declined --reason "answered in the PR summary" >/dev/null 2>&1; rc=$?
eq "$rc" "3" "a Conversation comment routed to the held rework by the batch ledger is refused too"

# A machine finding carries no comment of a human's, so no visit holds its question.
FM=$("$SUT" upsert --anchor tk-ancV --lane correctness --locus "assets/scripts/m.sh:m()" --message "nit: rename")
"$SUT" set-disposition --finding "$FM" --anchor tk-ancV --disposition declined --reason "cosmetic"; rc=$?
eq "$rc" "0" "a machine finding is declined past the open visit"

# --visit must name an open visit on this anchor's feedback.
FV4=$(human_finding tk-ancV "docs/y.md" "is this the product intent?" 4998 5000)
"$SUT" set-disposition --finding "$FV4" --anchor tk-ancV --disposition needs-you --visit visOld >/dev/null 2>&1; rc=$?
eq "$rc" "1" "needs-you --visit refuses a closed visit"
"$SUT" set-disposition --finding "$FV4" --anchor tk-ancV --disposition needs-you --visit tk-nosuch >/dev/null 2>&1; rc=$?
eq "$rc" "1" "…and a visit that is not on the anchor's feedback"
eq "$(meta "$FV4" 'finding.disposition')" "unvalidated" "…leaving the finding unruled"
"$SUT" set-disposition --finding "$FV4" --anchor tk-ancV --disposition declined --visit visV >/dev/null 2>&1; rc=$?
eq "$rc" "1" "--visit applies to needs-you only"
STUB_LIST_FAIL=1 "$SUT" set-disposition --finding "$FV4" --anchor tk-ancV --disposition declined --reason "x" >/dev/null 2>&1; rc=$?
eq "$rc" "2" "a store that will not list the visits refuses the ruling (exit 2), never reads as none open"
eq "$(bstatus "$FV4")" "open" "…and leaves the finding open"

# The PR#992 shape: the rework's own visit tracks the rework, holding no edge, and
# the anchor carries no ledger, so source_review (stored as a number) names the
# batch. A visit on the anchor itself is left to the validator's judgment.
: > "$STUB_DEPS"
store "$(jq -c '. + [
  {"id":"tk-ancW","status":"open","assignee":"","title":"PR#9 anchor","notes":"","metadata":{"merge_result":"pull_request","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"rwW","status":"in_progress","assignee":"","title":"Address review comments on PR#9 (through review 777, comment 0)","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancW","source_review":777}},
  {"id":"rwW2","status":"open","assignee":"","title":"Address review comments on PR#9 (through review 999, comment 0)","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-ancW","source_review":"999"}},
  {"id":"visW","status":"open","assignee":"","title":"visit: rwW — PR#9 sweep or fix the cause?","notes":"","metadata":{"task_kind":"visit","escalation_key":"pr9-sweep-approach","gc.continuation_group":"rwW"},"dependencies":[{"issue_id":"visW","depends_on_id":"rwW","type":"tracks"}]},
  {"id":"visA","status":"open","assignee":"","title":"visit: tk-ancW — seed-audit merge gate","notes":"","metadata":{"task_kind":"visit","escalation_key":"seed-audit-merge-gate.9","gc.continuation_group":"tk-ancW"}}]' "$STUB_STORE")"
FW1=$(human_finding tk-ancW "PR review" "This feels heavy handed; fix why the state occurs" 777 777)
FW2=$(human_finding tk-ancW "assets/scripts/w.sh" "nit: a typo" 1001 999)
out=$("$SUT" open-visits --anchor tk-ancW)
has "$out" "visW	tracks rework rwW" "open-visits names the visit tracking the batch's rework"
has "$out" "visA	tracks anchor tk-ancW" "…and the anchor's own visit, which the validator judges"
"$SUT" set-disposition --finding "$FW1" --anchor tk-ancW --disposition declined --reason "x" >/dev/null 2>&1; rc=$?
eq "$rc" "3" "a visit tracking the rework minted for the finding's review refuses the decline"
"$SUT" set-disposition --finding "$FW2" --anchor tk-ancW --disposition declined --reason "cosmetic"; rc=$?
eq "$rc" "0" "a finding from another batch is declined past both visits: one sits on another rework, one on the anchor"
eq "$(bstatus "$FW2")" "closed" "…and closes"
"$SUT" set-disposition --finding "$FW1" --anchor tk-ancW --disposition declined --reason "not an objection" --unrelated-visit visW; rc=$?
eq "$rc" "0" "--unrelated-visit names a visit that asks something else, and the ruling proceeds"
eq "$(meta "$FW1" 'finding.disposition')" "declined" "…as the ruling the validator meant"
has "$(notes "$FW1")" "past open visit(s) visW" "…and the finding's notes record the visit it was ruled past"

# ---------------------------------------------------------------------------
# The release: a needs-you finding closes once its visit has closed and no fix
# unit on its lane is in flight, and while one is, fix-in-flight names it so
# quiescence holds reviews off a diff the ruling may still change.
# ---------------------------------------------------------------------------
out=$("$SUT" fix-in-flight --anchor tk-ancV); rc=$?
eq "$rc" "0" "fix-in-flight holds while the held rework answers the needs-you finding's lane"
has "$out" "rwV blocked" "…naming that rework"
"$SUT" close-answered --anchor tk-ancV
eq "$(bstatus "$FV1")" "open" "close-answered leaves a needs-you finding open while its visit is open"
jq -c 'map(if .id == "visV" then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
"$SUT" close-answered --anchor tk-ancV
eq "$(bstatus "$FV1")" "open" "…and once the visit closes, while the rework its ruling released is still in flight"
gc bd update rwV --status=closed >/dev/null
"$SUT" close-answered --anchor tk-ancV
eq "$(bstatus "$FV1")" "closed" "…and closes it once the rework has landed too"
has "$(notes "$FV1")" "its visit visV closed" "…recording why"
# A needs-you finding with nothing answering it waits on a person and holds no
# merge, so it never reads as an unanswered demand.
: > "$STUB_DEPS"
store '[{"id":"tk-ancN","status":"open","assignee":"","title":"ancN","notes":"","metadata":{"merge_result":"pull_request"}},
        {"id":"visN","status":"open","assignee":"","title":"visit: tk-ancN","notes":"","metadata":{"task_kind":"visit","gc.continuation_group":"tk-ancN"}}]'
FN=$(human_finding tk-ancN "docs/n.md" "which audience is this for?" 60)
"$SUT" set-disposition --finding "$FN" --anchor tk-ancN --disposition needs-you --visit visN >/dev/null; rc=$?
eq "$rc" "0" "needs-you --visit adopts a visit on the anchor itself"
out=$("$SUT" fix-in-flight --anchor tk-ancN); rc=$?
eq "$rc/$out" "1/" "fix-in-flight reports a needs-you finding with no fix unit as neither in flight nor unanswered"
jq -c 'map(if .id == "visN" then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
"$SUT" close-answered --anchor tk-ancN
eq "$(bstatus "$FN")" "closed" "close-answered closes it once its visit closes, with no fix unit to wait on"

# shed-orphaned: a needs-you finding on an anchor that has closed is moot; its
# visit is the operator's and stays.
: > "$STUB_DEPS"
store '[{"id":"tk-ancS","status":"closed","assignee":"","title":"merged","notes":"","metadata":{"merge_result":"merged"}},
        {"id":"tk-ancT","status":"open","assignee":"","title":"open","notes":"","metadata":{"merge_result":"pull_request"}},
        {"id":"visS","status":"open","assignee":"","title":"visit: tk-ancS","notes":"","metadata":{"task_kind":"visit","gc.continuation_group":"tk-ancS"}},
        {"id":"visT","status":"open","assignee":"","title":"visit: tk-ancT","notes":"","metadata":{"task_kind":"visit","gc.continuation_group":"tk-ancT"}}]'
FS=$(human_finding tk-ancS "a.md" "orphaned question" 70)
gc bd update "$FS" --set-metadata finding.disposition=needs-you --set-metadata finding.visit=visS >/dev/null
FT=$(human_finding tk-ancT "b.md" "live question" 71)
gc bd update "$FT" --set-metadata finding.disposition=needs-you --set-metadata finding.visit=visT >/dev/null
"$SUT" shed-orphaned --reason "test"
eq "$(bstatus "$FS")" "closed" "shed-orphaned closes a needs-you finding whose anchor has closed"
eq "$(bstatus "visS")" "open" "…and leaves its visit to the operator"
eq "$(bstatus "$FT")" "open" "…and leaves one on an open anchor waiting on its visit"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
