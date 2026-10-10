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
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-dead-molecule-dispose-test.XXXXXX")"
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

# A molecule whose root never reached `closed`: parked by a prior molecule-hold
# (blocked head, dead wisp pinned, de-routed) or drained mid-flight. It is
# residue only under three guards — nothing live behind it, every escalation
# answered, and a source work bead that is not mid-PR. The work bead and the
# input convoy are READ for the guards and must never be enumerated or closed.
DEAD_ROSTER='{"sessions":[{"id":"lx-live-other","session_name":"gc-toolkit__polecat-lx-live-other","alias":"","state":"active"}]}'
husk() { # [roster-json] — default roster is active but names nothing in the chain
  store '[
    {"id":"tk-hroot","status":"in_progress","assignee":"","title":"mol-polecat-work",
     "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2",
                 "gc.input_convoy_id":"tk-hconv",
                 "gc.session_name":"gc-toolkit--gc-toolkit__polecat-1-pool"}},
    {"id":"tk-hload","status":"blocked","assignee":"","title":"Load context",
     "metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"tk-hroot",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"lx-dead-wisp"}},
    {"id":"tk-himpl","status":"open","assignee":"","title":"Implement",
     "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-hroot"}},
    {"id":"tk-hfinal","status":"open","assignee":"","title":"Finalize workflow",
     "metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.root_bead_id":"tk-hroot"}},
    {"id":"tk-hwork","status":"open","assignee":"","title":"the work bead","metadata":{}},
    {"id":"tk-hconv","status":"open","assignee":"","title":"input convoy","metadata":{}}
  ]'
  : > "$STUB_GC_LOG"; : > "$STUB_SESSION_LOG"
  printf 'tk-hconv|tracks|tk-hwork\n' > "$STUB_DEPS"   # the convoy tracks its work bead
  printf '%s' "${1:-$DEAD_ROSTER}" > "$TMP/sessions.json"
  export STUB_SESSION_LIST_RC=""
  export STUB_SESSIONS="$TMP/sessions.json"
}

echo "--- non-closed root: a clean dead husk IS disposed ---"
husk
OUT=$("$SCRIPT" tk-hroot --apply 2>&1); rc=$?
eq "$rc" "0" "a dead husk disposes (exit 0)"
has "$OUT" "result=disposed" "a dead husk reports disposed"
for B in tk-hroot tk-hload tk-himpl tk-hfinal; do
  eq "$(bstatus $B)" "closed" "$B is closed"
  eq "$(meta $B gc.routed_to)" "<absent>" "$B is de-routed"
  eq "$(meta $B gc.outcome)" "moot" "$B records outcome moot"
  eq "$(meta $B gc.work_outcome)" "no-op" "$B records no work"
done
eq "$(meta tk-hload gc.session_id)" "<absent>" "the dead wisp pin is cleared"
has "$(notes tk-hload)" "dead husk" "the note names the husk disposal"
eq "$(bstatus tk-hwork)" "open" "the source work bead is never touched"
eq "$(bstatus tk-hconv)" "open" "the input convoy is never touched"
eq "$(meta tk-hwork gc.routed_to)" "<absent>" "the work bead is not even in the enumeration"

echo "--- non-closed root: a LIVE molecule is UNTOUCHED ---"
# A live session behind a MEMBER (the dead wisp is actually still running).
husk '{"sessions":[{"id":"lx-dead-wisp","session_name":"","alias":"","state":"active"}]}'
OUT=$("$SCRIPT" tk-hroot --apply 2>&1); rc=$?
eq "$rc" "0" "a live molecule is refused, chain intact (exit 0)"
has "$OUT" "result=live_root" "a live molecule is refused as live_root"
has "$OUT" "live_session=lx-dead-wisp" "the live session that held it is named"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "a live molecule draws no write"
eq "$(bstatus tk-hload)" "blocked" "the live molecule's step is left alone"
# A live session matching the ROOT's gc.session_name (the affinity pool slot).
husk '{"sessions":[{"id":"x","session_name":"gc-toolkit--gc-toolkit__polecat-1-pool","alias":"","state":"active"}]}'
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "result=live_root" "a live session on the root's own session_name keeps it"
# no-live-step: an in_progress member under a live worker.
husk '{"sessions":[{"id":"lx-worker","session_name":"","alias":"","state":"active"}]}'
jq -c 'map(if .id=="tk-himpl" then (.status="in_progress" | .metadata["gc.session_id"]="lx-worker") else . end)' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "result=live_root" "an in_progress step under a live session keeps the molecule"
has "$OUT" "live_session=lx-worker" "the live worker is named"
# A member pinned only by its agent-address assignee (no gc.session_id/
# gc.session_name), matching an active session that carries that identity in
# name/agent_name while alias is empty — the pool-worker roster shape. LIVE_SET
# must read name and agent_name or this live worker is missed and the molecule
# disposed under it.
husk '{"sessions":[{"id":"lx-pool-7","session_name":"gc-toolkit__polecat-lx-pool-7","alias":"","name":"gc-toolkit/gc-toolkit.polecat-1","agent_name":"gc-toolkit/gc-toolkit.polecat-1","state":"active"}]}'
jq -c 'map(if .id=="tk-himpl" then (.status="in_progress" | .assignee="gc-toolkit/gc-toolkit.polecat-1") else . end)' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "result=live_root" "a member pinned by agent-address assignee keeps the molecule (LIVE_SET reads agent_name)"
has "$OUT" "live_session=gc-toolkit/gc-toolkit.polecat-1" "the agent-address live session is named"
# A non-active session is not live: a stopped roster entry does not protect.
husk '{"sessions":[{"id":"lx-dead-wisp","session_name":"","alias":"","state":"stopped"}]}'
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "result=disposed" "a stopped (non-active) session does not keep the molecule"

echo "--- non-closed root: liveness that cannot be read refuses (fail closed) ---"
husk
export STUB_SESSION_LIST_RC=1
OUT=$("$SCRIPT" tk-hroot --apply 2>&1); rc=$?
export STUB_SESSION_LIST_RC=""
eq "$rc" "0" "an unreadable roster refuses, chain intact"
has "$OUT" "result=live_root" "an unreadable roster refuses as live_root"
has "$OUT" "liveness_undetermined" "the refusal names why"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an unreadable roster draws no write"
husk '{"sessions":[]}'
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "liveness_undetermined" "an empty roster is undetermined, not proof of death"

echo "--- non-closed root: a source bead mid-PR is SKIPPED ---"
for MR in pre_open_gate pull_request; do
  husk
  jq -c --arg mr "$MR" 'map(if .id=="tk-hwork" then .metadata.merge_result=$mr else . end)' \
    "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
  OUT=$("$SCRIPT" tk-hroot --apply 2>&1); rc=$?
  eq "$rc" "0" "a source mid-PR ($MR) is refused, chain intact"
  has "$OUT" "result=refused" "a source mid-PR ($MR) is refused"
  has "$OUT" "source_inflight_pr=$MR" "the refusal names the merge_result"
  hasnt "$(cat "$STUB_GC_LOG")" "bd update" "a source mid-PR draws no write"
  eq "$(bstatus tk-hroot)" "in_progress" "the husk root is left alone"
done

echo "--- non-closed root: a source PR reference with no merge_result is SKIPPED (fail closed) ---"
for KEY in pr_number pr_url; do
  husk
  jq -c --arg k "$KEY" 'map(if .id=="tk-hwork" then .metadata[$k]="123" else . end)' \
    "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
  OUT=$("$SCRIPT" tk-hroot --apply 2>&1); rc=$?
  eq "$rc" "0" "a source with $KEY and no merge_result is refused, chain intact"
  has "$OUT" "result=refused" "an unresolved PR reference ($KEY) is refused"
  has "$OUT" "source_pr_unresolved=123" "the refusal names the unresolved PR reference"
  hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an unresolved PR reference draws no write"
  eq "$(bstatus tk-hroot)" "in_progress" "the husk root is left alone"
done
# A resolved PR does not block disposal: a set merge_result records the PR's fate,
# so a lingering pr_number alongside merged is proven not-open and the husk disposes.
husk
jq -c 'map(if .id=="tk-hwork" then (.metadata.pr_number="123" | .metadata.merge_result="merged") else . end)' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "result=disposed" "a resolved PR (merge_result=merged) with a stale pr_number still disposes"

echo "--- non-closed root: an OPEN escalation keeps it, a CLOSED one does not ---"
husk
jq -c '. + [{"id":"tk-hvisit","status":"open","assignee":"","title":"visit: husk blocked",
  "metadata":{"escalation_key":"husk-blocked","task_kind":"visit"}}]' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
printf 'tk-hvisit|tracks|tk-hwork\n' >> "$STUB_DEPS"   # the visit tracks the work bead
OUT=$("$SCRIPT" tk-hroot --apply 2>&1); rc=$?
eq "$rc" "0" "an open escalation refuses, chain intact"
has "$OUT" "result=refused" "an open escalation is refused"
has "$OUT" "open_escalation=tk-hvisit" "the open visit is named"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an open escalation draws no write"
# Same molecule, the visit now closed: the molecule is residue and disposes.
husk
jq -c '. + [{"id":"tk-hvisit","status":"closed","assignee":"","title":"visit: husk blocked",
  "metadata":{"escalation_key":"husk-blocked","task_kind":"visit"}}]' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
printf 'tk-hvisit|tracks|tk-hwork\n' >> "$STUB_DEPS"
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "result=disposed" "a closed escalation does not block disposal"
eq "$(bstatus tk-hroot)" "closed" "the husk root closes once its visit is answered"
eq "$(bstatus tk-hvisit)" "closed" "the visit itself is never touched"

echo "--- non-closed root: an unreadable convoy fails closed ---"
husk
export STUB_DEP_GARBAGE=1
OUT=$("$SCRIPT" tk-hroot --apply 2>&1); rc=$?
export STUB_DEP_GARBAGE=""
eq "$rc" "0" "an unreadable convoy refuses, chain intact"
has "$OUT" "result=refused" "an unreadable convoy is refused"
has "$OUT" "convoy_unreadable=tk-hconv" "the refusal names the convoy"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an unreadable convoy draws no write"

echo "--- non-closed root: the work-bead-in-chain refusal still fires first ---"
# The anchor guard runs BEFORE the husk guards: a chain member carrying branch /
# merge_result is the refinery's regardless of the root's status.
husk
jq -c 'map(if .id=="tk-himpl" then .metadata.branch="polecat/tk-x" else . end)' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "result=refused" "a non-closed chain holding a work bead is refused"
has "$OUT" "work_bead_in_chain=tk-himpl" "the refusal names the work bead"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "a chain holding a work bead draws no write"

echo "--- non-closed root: preview reaches the same verdict, writing nothing ---"
husk
OUT=$("$SCRIPT" tk-hroot 2>&1); rc=$?
eq "$rc" "0" "preview of a dead husk exits 0"
has "$OUT" "result=preview" "a dead husk previews as would-dispose"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "preview of a dead husk writes nothing"
eq "$(bstatus tk-hroot)" "in_progress" "preview leaves the husk root alone"
husk '{"sessions":[{"id":"lx-dead-wisp","session_name":"","alias":"","state":"active"}]}'
OUT=$("$SCRIPT" tk-hroot 2>&1)
has "$OUT" "result=live_root" "preview of a live molecule reports live_root, not would-dispose"

echo "--- non-closed root: a CLOSED work bead is past the PR guard ---"
# merge.sh lands open anchors only, so a PR a closed bead names is merged,
# retired with its anchor, or the anchor's own to land. A rework child closed
# moot keeps its anchor's pr_number with an empty merge_result.
close_work() { jq -c 'map(if .id=="tk-hwork" then .status="closed" else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"; }
for MR in pre_open_gate pull_request; do
  husk
  jq -c --arg mr "$MR" 'map(if .id=="tk-hwork" then .metadata.merge_result=$mr else . end)' \
    "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
  close_work
  OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
  has "$OUT" "result=disposed" "a closed work bead carrying merge_result=$MR does not hold the molecule"
done
husk
jq -c 'map(if .id=="tk-hwork" then (.metadata.pr_number="824" | .metadata.task_kind="rework" | .metadata.anchor_bead="tk-anchor") else . end)' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
close_work
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "result=disposed" "a closed rework child's inherited pr_number does not hold its molecule"
has "$(notes tk-hload)" "ends with its work bead tk-hwork, which is closed" "the note says the molecule ended with its closed work"
# The same child still open keeps the fail-closed refusal.
husk
jq -c 'map(if .id=="tk-hwork" then (.metadata.pr_number="824" | .metadata.task_kind="rework" | .metadata.anchor_bead="tk-anchor") else . end)' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$("$SCRIPT" tk-hroot --apply 2>&1)
has "$OUT" "source_pr_unresolved=824" "an OPEN rework child's pr_number still refuses"

echo "--- --if-source-closed: only a molecule whose work closed ends ---"
husk
OUT=$("$SCRIPT" tk-hroot --apply --if-source-closed 2>&1); rc=$?
eq "$rc" "0" "an open work bead refuses with the chain intact"
has "$OUT" "result=refused" "an open work bead is refused under --if-source-closed"
has "$OUT" "source_open=tk-hwork" "the refusal names the open work bead"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an open work bead draws no write"
husk
close_work
OUT=$("$SCRIPT" tk-hroot --apply --if-source-closed 2>&1)
has "$OUT" "result=disposed" "a closed work bead lets the molecule end"
eq "$(bstatus tk-hroot)" "closed" "the root closes with its work"
eq "$(bstatus tk-hwork)" "closed" "the work bead is read, never written"
# No input convoy, or a convoy that does not track exactly one bead, is no
# source to end with.
husk
jq -c 'map(if .id=="tk-hroot" then (.metadata |= del(.["gc.input_convoy_id"])) else . end)' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$("$SCRIPT" tk-hroot --apply --if-source-closed 2>&1)
has "$OUT" "detail=no_source" "a root with no input convoy has no source to end with"
husk
close_work
jq -c '. + [{"id":"tk-hwork2","status":"closed","assignee":"","title":"second member","metadata":{}}]' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
printf 'tk-hconv|tracks|tk-hwork2\n' >> "$STUB_DEPS"
OUT=$("$SCRIPT" tk-hroot --apply --if-source-closed 2>&1)
has "$OUT" "detail=no_source" "a convoy tracking two beads names no single source"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "no source draws no write"
# The other refusals still hold when the work has closed.
husk '{"sessions":[{"id":"lx-dead-wisp","session_name":"","alias":"","state":"active"}]}'
close_work
OUT=$("$SCRIPT" tk-hroot --apply --if-source-closed 2>&1)
has "$OUT" "result=live_root" "a live session still keeps a molecule whose work closed"
husk
close_work
jq -c '. + [{"id":"tk-hvisit","status":"open","assignee":"","title":"visit","metadata":{"escalation_key":"k","task_kind":"visit"}}]' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
printf 'tk-hvisit|tracks|tk-hwork\n' >> "$STUB_DEPS"
OUT=$("$SCRIPT" tk-hroot --apply --if-source-closed 2>&1)
has "$OUT" "open_escalation=tk-hvisit" "an open escalation still keeps a molecule whose work closed"

echo "--- --owner: the caller's own claim is not a live worker ---"
OWN_ROSTER='{"sessions":[{"id":"lx-me","session_name":"gc-toolkit__polecat-lx-me","alias":"","name":"gc-toolkit__polecat-lx-me","agent_name":"gc-toolkit/gc-toolkit.polecat-3","state":"active"},
  {"id":"lx-live-other","session_name":"gc-toolkit__polecat-lx-live-other","alias":"","state":"active"}]}'
own_claim() { jq -c 'map(if .id=="tk-hload" then (.status="in_progress" | .assignee="gc-toolkit/gc-toolkit.polecat-3" | .metadata["gc.session_id"]="lx-me") else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"; }
husk "$OWN_ROSTER"; close_work; own_claim
OUT=$(GC_SESSION_ID=lx-me "$SCRIPT" tk-hroot --apply --if-source-closed 2>&1)
has "$OUT" "live_session=" "without --owner the caller's own claim reads as live"
husk "$OWN_ROSTER"; close_work; own_claim
OUT=$(GC_SESSION_ID=lx-me "$SCRIPT" tk-hload --apply --owner --if-source-closed 2>&1); rc=$?
eq "$rc" "0" "the owner ends its own molecule (exit 0)"
has "$OUT" "result=disposed" "the caller's id and agent address do not hold the molecule under --owner"
eq "$(bstatus tk-hload)" "closed" "the caller's own claimed step closes with the molecule"
has "$(notes tk-hload)" "besides the caller" "the note records that the caller's own session was set aside"
husk "$OWN_ROSTER"; close_work; own_claim
OUT=$(GC_SESSION_NAME=gc-toolkit__polecat-lx-me "$SCRIPT" tk-hload --apply --owner --if-source-closed 2>&1)
has "$OUT" "result=disposed" "the caller is found by GC_SESSION_NAME as well"
# Any other live session still keeps it.
husk "$OWN_ROSTER"; close_work; own_claim
jq -c 'map(if .id=="tk-himpl" then .metadata["gc.session_id"]="lx-live-other" else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$(GC_SESSION_ID=lx-me "$SCRIPT" tk-hload --apply --owner --if-source-closed 2>&1)
has "$OUT" "live_session=lx-live-other" "another live session still keeps the molecule under --owner"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "a molecule another session holds draws no write"
# A name the caller shares with another active session still counts for that one.
husk '{"sessions":[{"id":"lx-me","session_name":"s-me","alias":"","agent_name":"gc-toolkit/gc-toolkit.polecat-3","state":"active"},
  {"id":"lx-twin","session_name":"s-twin","alias":"","agent_name":"gc-toolkit/gc-toolkit.polecat-3","state":"active"}]}'
close_work; own_claim
OUT=$(GC_SESSION_ID=lx-me "$SCRIPT" tk-hload --apply --owner --if-source-closed 2>&1)
has "$OUT" "live_session=gc-toolkit/gc-toolkit.polecat-3" "a name shared with another active session is still live under --owner"
# --owner names a session or it is a usage error.
husk "$OWN_ROSTER"
"$SCRIPT" tk-hload --apply --owner >/dev/null 2>&1; eq "$?" "2" "--owner with no session identity in the environment exits 2"
# A closed root is residue whatever its source says.
fixture
OUT=$("$SCRIPT" tk-load --apply --if-source-closed 2>&1)
has "$OUT" "result=disposed" "a closed root disposes under --if-source-closed whatever its source"
# Do not let the guarded path's env leak into the closed-root tests below.
export STUB_SESSIONS="" STUB_SESSION_LIST_RC=""

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
