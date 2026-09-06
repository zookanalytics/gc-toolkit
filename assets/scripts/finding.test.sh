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
K1=$("$SUT" key --lane codex --locus "assets/scripts/foo.sh:bar()" --message "Unquoted expansion in the loop")
K2=$("$SUT" key --lane codex --locus "assets/scripts/foo.sh:99:bar()" --message "unquoted   expansion in the loop")
eq "$K1" "$K2" "key strips line numbers, case and whitespace so it survives a rebase"
K3=$("$SUT" key --lane arch --locus "assets/scripts/foo.sh:bar()" --message "Unquoted expansion in the loop")
if [ "$K1" != "$K3" ]; then ok "key is lane-scoped"; else bad "key collides across lanes"; fi

# ---------------------------------------------------------------------------
# upsert: files a finding bead with the full metadata contract.
# ---------------------------------------------------------------------------
store '[{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"42"}}]'
F1=$("$SUT" upsert --anchor tk-anc --lane codex --locus "assets/scripts/foo.sh:bar()" --message "Unquoted expansion in the loop")
eq "$(meta "$F1" task_kind)" "finding" "upsert stamps task_kind=finding"
eq "$(meta "$F1" anchor_bead)" "tk-anc" "upsert stamps anchor_bead"
eq "$(meta "$F1" 'finding.lane')" "codex" "upsert stamps finding.lane"
eq "$(meta "$F1" 'finding.disposition')" "unvalidated" "a fresh finding is unvalidated"
eq "$(meta "$F1" 'finding.source')" "machine:codex" "source defaults to machine:<lane>"
eq "$(meta "$F1" 'finding.key')" "$K1" "upsert stamps the computed key"

# ---------------------------------------------------------------------------
# dedup: re-raising the same objection creates nothing; a distinct one does.
# ---------------------------------------------------------------------------
BEFORE=$(jq 'length' "$STUB_STORE")
F1b=$("$SUT" upsert --anchor tk-anc --lane codex --locus "assets/scripts/foo.sh:88:bar()" --message "unquoted   Expansion in the loop")
eq "$F1b" "$F1" "re-raising the same objection returns the existing finding"
eq "$(jq 'length' "$STUB_STORE")" "$BEFORE" "…and files no second bead"
F2=$("$SUT" upsert --anchor tk-anc --lane codex --locus "assets/scripts/baz.sh:qux()" --message "missing error handling on the write")
if [ "$F2" != "$F1" ]; then ok "a distinct objection is a distinct finding"; else bad "distinct objection collided"; fi

# Same key on a DIFFERENT anchor is a different finding (dedup is per-anchor).
store "$(jq -c '. + [{"id":"tk-anc2","status":"open","assignee":"","title":"a2","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex"}}]' "$STUB_STORE")"
F1_other=$("$SUT" upsert --anchor tk-anc2 --lane codex --locus "assets/scripts/foo.sh:bar()" --message "Unquoted expansion in the loop")
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
F3=$("$SUT" upsert --anchor tk-anc --lane codex --locus "docs/x.md" --message "stale reference to a retired script")
"$SUT" set-disposition --finding "$F3" --anchor tk-anc --disposition deferred
eq "$(meta "$F3" 'finding.disposition')" "deferred" "disposition recorded as deferred"
has "$(deps)" "$F3|discovered-from|tk-anc" "deferred wires finding --discovered-from anchor"
hasnt "$(deps)" "$F3|blocks|tk-anc" "deferred writes no blocks edge"
hasnt " $(probe_blockers tk-anc) " " $F3 " "merge.sh's probe does NOT see the deferred finding"

# ---------------------------------------------------------------------------
# set-disposition must-fix -> deferred: the reclassification retracts the blocks
# edge, or merge.sh keeps reading the finding as a live blocker and a deferred
# finding holds the merge it must not (regression).
# ---------------------------------------------------------------------------
F5=$("$SUT" upsert --anchor tk-anc --lane codex --locus "assets/scripts/qux.sh:main()" --message "double-quote the array expansion")
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
F4=$("$SUT" upsert --anchor tk-anc --lane codex --locus "assets/scripts/foo.sh:helper()" --message "nit: rename for clarity")
"$SUT" set-disposition --finding "$F4" --anchor tk-anc --disposition declined --reason "cosmetic, not worth a round"
eq "$(meta "$F4" 'finding.disposition')" "declined" "disposition recorded as declined"
eq "$(bstatus "$F4")" "closed" "declined finding is closed"
has "$(notes "$F4")" "cosmetic, not worth a round" "the decline reason is recorded"
hasnt " $(probe_blockers tk-anc) " " $F4 " "a declined finding holds nothing"

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
"$SUT" close-unvalidated --anchor tk-anc --lane codex --reason "lane approved"
eq "$(bstatus "$F2")" "closed" "close-unvalidated closes the unvalidated finding"
eq "$(bstatus "$F1")" "open" "close-unvalidated leaves the must-fix finding for the validator/fix unit"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
