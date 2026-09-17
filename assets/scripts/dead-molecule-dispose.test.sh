#!/usr/bin/env bash
# Hermetic test for assets/scripts/dead-molecule-dispose.sh.
#
# WHAT THE SCRIPT IS FOR. A graph.v2 root closes and its steps keep the status,
# the route and the dependency edges they were poured with. The chain then
# re-offers a finished molecule as fresh work, or — when its head step sits at
# `blocked` — falls out of every readiness query, where no pool and no sweep
# can see it. The root's own status is the whole predicate: a closed root
# cannot produce work, so everything under it is residue.
#
# What is exercised:
#   * ROOT RESOLUTION from either end — a step's gc.root_bead_id, and a root
#     handed in directly (gc.kind=workflow / gc.formula_contract=graph.v2);
#   * the REFUSALS, each writing nothing: a root that is not closed, a root
#     that will not read, a bead that is no part of a molecule, and a chain
#     holding a work bead (branch / merge_result), which only the refinery may
#     close;
#   * the PHASE ORDER, asserted on the emitted commands: every de-route is
#     issued before the first close. This is the whole safety property —
#     closing a step readies its successor, and a successor readied while
#     still routed is claimable, which is the partial teardown that mints a
#     duplicate PR for already-merged code;
#   * a failed de-route stopping the pass BEFORE any close, rather than
#     tearing down half a chain whose remainder is still offerable;
#   * the PASS LOOP unwinding a blocking chain from its open end, since bd
#     refuses to close a blocked issue;
#   * the FALSE-EMPTY guard — an unreadable listing exits non-zero instead of
#     reporting a clean chain, the same class of fail-open the dispatcher's
#     own enumerate guard exists to prevent;
#   * a close that reports success and rolls back, which must exit 3 and name
#     the member, not report a clean teardown;
#   * preview as the default: no --apply writes nothing at all.
#
# No live city, Dolt, network, gc or bd — stubs from test-harness.sh only.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/dead-molecule-dispose.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# The store reads must not be pinned to a live rig: an ambient GC_RIG_ROOT
# would send --db at a real .beads directory instead of the stub store.
unset GC_RIG_ROOT

[ -x "$SCRIPT" ] || chmod +x "$SCRIPT" 2>/dev/null

# A finished mol-review chain: the root closed, one step left at `blocked`
# behind the dep edge it was poured with, the rest open and still routed.
fixture() {
  store '[
    {"id":"tk-root","status":"closed","assignee":"","title":"mol-review",
     "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2",
                 "gc.outcome":"moot","gc.input_convoy_id":"tk-conv"}},
    {"id":"tk-load","status":"blocked","assignee":"","title":"Read the dispatch",
     "metadata":{"gc.step_ref":"mol-review.load-dispatch","gc.root_bead_id":"tk-root",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat-codex","gc.session_id":"lx-dead"}},
    {"id":"tk-review","status":"open","assignee":"","title":"Review",
     "metadata":{"gc.step_ref":"mol-review.review","gc.root_bead_id":"tk-root",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat-codex"}},
    {"id":"tk-verdict","status":"open","assignee":"","title":"Verdict and drain",
     "metadata":{"gc.step_ref":"mol-review.verdict-and-drain","gc.root_bead_id":"tk-root",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat-codex"}},
    {"id":"tk-final","status":"open","assignee":"","title":"Finalize workflow",
     "metadata":{"gc.step_ref":"mol-review.workflow-finalize","gc.root_bead_id":"tk-root",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat-codex"}},
    {"id":"tk-other","status":"open","assignee":"","title":"unrelated work",
     "metadata":{}}
  ]'
  : > "$STUB_DEPS"
  : > "$STUB_GC_LOG"
}

echo "--- preview is the default ---"
fixture
OUT=$("$SCRIPT" tk-load 2>&1); rc=$?
eq "$rc" "0" "preview exits 0"
has "$OUT" "result=preview" "preview says so"
has "$OUT" "root=tk-root" "preview names the root it resolved"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "preview issued no write at all"
eq "$(bstatus tk-load)" "blocked" "preview left the step alone"
eq "$(meta tk-review gc.routed_to)" "gc-toolkit/gc-toolkit.polecat-codex" "preview left the route alone"

echo "--- root resolution from either end ---"
fixture
OUT=$("$SCRIPT" tk-root 2>&1)
has "$OUT" "root=tk-root" "a root handed in directly resolves to itself"
has "$OUT" "members=" "the chain is enumerated from the root"
fixture
OUT=$("$SCRIPT" tk-final 2>&1)
has "$OUT" "root=tk-root" "a step resolves its root through gc.root_bead_id"

echo "--- refusal: a live root is machinery, not residue ---"
for LIVE in open in_progress blocked; do
  fixture
  jq -c --arg s "$LIVE" 'map(if .id == "tk-root" then .status = $s else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
  OUT=$("$SCRIPT" tk-load --apply 2>&1); rc=$?
  eq "$rc" "0" "a root at $LIVE exits 0 (refused, chain intact)"
  has "$OUT" "result=live_root" "a root at $LIVE is refused"
  hasnt "$(cat "$STUB_GC_LOG")" "bd update" "a root at $LIVE draws no write"
  eq "$(bstatus tk-load)" "blocked" "a root at $LIVE leaves the step alone"
done

echo "--- refusal: an unreadable root is not a closed one ---"
fixture
# The step names a root the store does not carry.
jq -c 'map(select(.id != "tk-root"))' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$("$SCRIPT" tk-load --apply 2>&1); rc=$?
eq "$rc" "1" "an unreadable root exits 1"
has "$OUT" "result=unreadable" "an unreadable root says so"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an unreadable root draws no write"

echo "--- refusal: a bead that is no part of a molecule ---"
fixture
OUT=$("$SCRIPT" tk-other --apply 2>&1); rc=$?
eq "$rc" "0" "a non-member exits 0"
has "$OUT" "result=refused" "a non-member is refused"
has "$OUT" "detail=not_a_molecule" "the refusal names why"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "a non-member draws no write"

echo "--- refusal: a work bead in the chain is the refinery's ---"
# An anchor carries branch / merge_result. Closing one here would take a bead
# out of the anchor class without a verified merge.
for KEY in branch merge_result; do
  fixture
  jq -c --arg k "$KEY" 'map(if .id == "tk-review" then .metadata[$k] = "polecat/tk-x" else . end)' \
    "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
  OUT=$("$SCRIPT" tk-load --apply 2>&1); rc=$?
  eq "$rc" "0" "a chain holding $KEY exits 0 (refused)"
  has "$OUT" "result=refused" "a chain holding $KEY is refused"
  has "$OUT" "tk-review" "the refusal names the work bead"
  hasnt "$(cat "$STUB_GC_LOG")" "bd update" "a chain holding $KEY draws no write"
done

echo "--- the false-empty guard: an unreadable listing is not a clean chain ---"
fixture
export STUB_LIST_FAIL="1"
OUT=$("$SCRIPT" tk-load --apply 2>&1); rc=$?
export STUB_LIST_FAIL=""
eq "$rc" "1" "an unreadable listing exits 1"
has "$OUT" "result=unreadable" "an unreadable listing says so"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an unreadable listing draws no write"

echo "--- apply: de-routes come first, then the closes ---"
fixture
OUT=$("$SCRIPT" tk-load --apply 2>&1); rc=$?
eq "$rc" "0" "the teardown exits 0"
has "$OUT" "result=disposed" "the teardown reports disposed"
# The ordering property, on the emitted commands: no close may precede a
# de-route, or a readied successor is claimable while still routed.
LAST_DEROUTE=$(grep -n -- "--unset-metadata gc.routed_to" "$STUB_GC_LOG" | tail -1 | cut -d: -f1)
FIRST_CLOSE=$(grep -n -- "--status=closed" "$STUB_GC_LOG" | head -1 | cut -d: -f1)
if [ -n "$LAST_DEROUTE" ] && [ -n "$FIRST_CLOSE" ] && [ "$LAST_DEROUTE" -lt "$FIRST_CLOSE" ]; then
  ok "every de-route is issued before the first close"
else
  bad "de-route/close interleaved (last de-route line '$LAST_DEROUTE', first close line '$FIRST_CLOSE')"
fi

echo "--- apply: nothing of the chain is left standing or offerable ---"
for B in tk-load tk-review tk-verdict tk-final; do
  eq "$(bstatus $B)" "closed" "$B is closed"
  eq "$(meta $B gc.routed_to)" "<absent>" "$B is de-routed"
  eq "$(meta $B gc.outcome)" "moot" "$B records an outcome"
  eq "$(meta $B gc.work_outcome)" "no-op" "$B records no work"
done
eq "$(meta tk-load gc.session_id)" "<absent>" "the dead session pin is cleared"
has "$(notes tk-load)" "root tk-root is closed" "the step says why it was closed"
eq "$(bstatus tk-other)" "open" "a bead outside the chain is untouched"
eq "$(bstatus tk-root)" "closed" "the already-closed root is not rewritten"

echo "--- the pass loop unwinds a blocking chain from its open end ---"
# bd refuses to close a blocked issue, so a chain whose head is held by an
# open blocker only closes as the blocker ahead of it closes.
fixture
# tk-load blocks tk-review blocks tk-verdict: "A|blocks|B" = A blocks B.
printf 'tk-load|blocks|tk-review\ntk-review|blocks|tk-verdict\n' > "$STUB_DEPS"
OUT=$("$SCRIPT" tk-load --apply 2>&1); rc=$?
eq "$rc" "0" "a dep-chained teardown exits 0"
has "$OUT" "result=disposed" "a dep-chained teardown completes"
eq "$(bstatus tk-verdict)" "closed" "the deepest blocked step still closes"
CLOSE_ORDER=$(grep -o -- "update tk-[a-z]* --status=closed" "$STUB_GC_LOG" | sed 's/update \(tk-[a-z]*\).*/\1/' | tr '\n' ',')
case "$CLOSE_ORDER" in
  tk-load,*tk-review,*tk-verdict,*) ok "closes ran forward: $CLOSE_ORDER" ;;
  *) bad "closes ran out of order ($CLOSE_ORDER)" ;;
esac

echo "--- a failed de-route stops before any close ---"
fixture
export STUB_UPDATE_FAIL="tk-verdict"
OUT=$("$SCRIPT" tk-load --apply 2>&1); rc=$?
export STUB_UPDATE_FAIL=""
eq "$rc" "3" "a failed de-route exits 3"
has "$OUT" "result=partial" "a failed de-route says partial"
has "$OUT" "deroute(tk-verdict)" "the failed member is named"
hasnt "$(cat "$STUB_GC_LOG")" "--status=closed" "no close was issued at all"
eq "$(bstatus tk-load)" "blocked" "the chain still stands"

echo "--- a close that rolls back is not a clean teardown ---"
fixture
export STUB_DROP_KEYS="tk-verdict:status"
OUT=$("$SCRIPT" tk-load --apply 2>&1); rc=$?
export STUB_DROP_KEYS=""
eq "$rc" "3" "a rolled-back close exits 3"
has "$OUT" "result=partial" "a rolled-back close says partial"
has "$OUT" "tk-verdict" "the member that did not close is named"
eq "$(meta tk-verdict gc.routed_to)" "<absent>" "it is de-routed even so, so no pool can claim it"

echo "--- usage ---"
fixture
"$SCRIPT" >/dev/null 2>&1; eq "$?" "2" "no bead id exits 2"
"$SCRIPT" tk-load --nope >/dev/null 2>&1; eq "$?" "2" "an unknown flag exits 2"
"$SCRIPT" tk-load --db >/dev/null 2>&1; eq "$?" "2" "a value-taking flag at end of argv exits 2"
"$SCRIPT" tk-load extra >/dev/null 2>&1; eq "$?" "2" "a second bead id exits 2"

echo "--- json output ---"
fixture
OUT=$("$SCRIPT" tk-load --json 2>/dev/null)
printf '%s' "$OUT" | jq -e '.result == "preview" and .root == "tk-root" and (.members | test("tk-load"))' >/dev/null 2>&1 \
  && ok "--json emits one object carrying result, root and members" \
  || bad "--json payload wrong: $OUT"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
