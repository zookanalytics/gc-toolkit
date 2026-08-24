#!/usr/bin/env bash
# Hermetic test for assets/scripts/gate-ensure.sh — arm 1 of the merge cadence.
# Covers: default check_set stamping (and the rc=3 hold when the stamp does not
# persist or the enumeration is unreadable); the `none` opt-out; marker
# classification (green@live head, stale green, exception, fixable, absent,
# unmappable); in-flight dedup + stranded-route repair; the dispatch shape
# (metadata, blocks edge, stamp-don't-sling route with read-back); merge_hold;
# and the dispatch_count cap.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# Private scripts dir: the SUT plus a body-emitter stub (interface unchanged).
SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/gate-ensure.sh"
printf '#!/usr/bin/env bash\necho "METHOD${2:+ note: $2}"\n' > "$SD/review-dispatch-body.sh"
chmod +x "$SD/review-dispatch-body.sh"
SUT="$SD/gate-ensure.sh"
POOL="rig/gc-toolkit.polecat-codex"
run() { "$SUT" --default codex --review-pool "$POOL" 2>&1; }

anchor() { # id mr checkset marker branch extra-json
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"t %s","metadata":{"merge_result":"%s","branch":"%s","merged_target":"main"%s%s%s}}' \
    "$1" "$1" "$2" "$5" \
    "$( [ -n "$3" ] && printf ',"check_set":"%s"' "$3" )" \
    "$( [ -n "$4" ] && printf ',"check.codex":"%s"' "$4" )" \
    "${6:-}"
}

echo "# stamping the default"
store "[$(anchor A1 pre_open_gate "" "" polecat/a1)]"
echo "sha-a1" > "$GH_DIR/head_polecat_a1"
out=$(run); rc=$?
eq "$rc" 0 "a stamped-and-dispatched pass exits 0"
eq "$(meta A1 check_set)" "codex" "empty check_set is stamped with the default"
has "$out" "dispatched review" "the armed gate got a signoff dispatched"
rid=$(jq -r '.[] | select(.id | startswith("new-")) | .id' "$STUB_STORE")
eq "$(meta "$rid" task_kind)" "review" "review bead carries task_kind=review"
eq "$(meta "$rid" check_name)" "codex" "review bead names the gate"
eq "$(meta "$rid" anchor_bead)" "A1" "review bead links the anchor"
eq "$(meta "$rid" review_branch)" "polecat/a1" "review bead carries review_branch"
eq "$(meta "$rid" review_base)" "main" "review bead carries review_base"
eq "$(meta "$rid" 'gc.routed_to')" "$POOL" "review routed by direct stamp (stamp-don't-sling)"
eq "$(meta "$rid" review_pool)" "$POOL" "durable route copy stamped with it"
grep -qxF "$rid|blocks|A1" "$STUB_DEPS" && ok "review blocks the anchor" || bad "blocks edge missing"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "no gc sling anywhere (default_sling_formula hijack)"
eq "$(meta A1 dispatch_count)" "1" "dispatch_count incremented on the anchor"
d=$(jq -r --arg id "$rid" '.[] | select(.id == $id) | .description' "$STUB_STORE")
has "$d" "METHOD" "the dispatch body came from review-dispatch-body.sh"

echo "# stamp that does not persist holds the merge (rc=3)"
store "[$(anchor A2 pull_request "" "" polecat/a2)]"
out=$(STUB_DROP_KEYS="A2:check_set" run); rc=$?
eq "$rc" 3 "an ungated visible anchor exits rc=3"
has "$out" "UNSAFE" "the unsafe hold is named"

echo "# unreadable enumeration holds the merge (rc=3)"
out=$(STUB_LIST_FAIL=1 run); rc=$?
eq "$rc" 3 "an unreadable gating enumeration exits rc=3"

echo "# opt-out and settled markers"
store "[$(anchor B1 pre_open_gate none "" polecat/b1),
        $(anchor B2 pre_open_gate codex "green@sha-b2" polecat/b2),
        $(anchor B3 pull_request codex "exception@sha-b3" polecat/b3)]"
echo "sha-b2" > "$GH_DIR/head_polecat_b2"
echo "sha-b3x" > "$GH_DIR/head_polecat_b3"
: > "$STUB_GC_LOG"
out=$(run); rc=$?
eq "$rc" 0 "opt-out/settled pass exits 0"
eq "$(meta B1 check_set)" "none" "the none sentinel is left alone"
has "$out" "0 reviews dispatched" "green@live-head, exception@ and none dispatch nothing"

echo "# stale green / fixable / absent / unmappable all dispatch"
store "[$(anchor C1 pre_open_gate codex "green@old-oid" polecat/c1),
        $(anchor C2 pull_request codex "fixable@old-oid" polecat/c2),
        $(anchor C3 pull_request codex "" polecat/c3),
        $(anchor C4 pull_request codex "red" polecat/c4)]"
echo "sha-c1" > "$GH_DIR/head_polecat_c1"
echo "sha-c2" > "$GH_DIR/head_polecat_c2"
echo "sha-c3" > "$GH_DIR/head_polecat_c3"
echo "sha-c4" > "$GH_DIR/head_polecat_c4"
out=$(run); rc=$?
eq "$rc" 0 "dispatch pass exits 0"
has "$out" "4 reviews dispatched" "stale green, fixable, absent and unmappable each dispatched one review"

echo "# unreadable live head fails soft: a present green marker stays satisfiable"
store "[$(anchor C5 pre_open_gate codex "green@somewhere" polecat/c5)]"
out=$(run); rc=$?
eq "$rc" 0 "no-head pass exits 0"
has "$out" "0 reviews dispatched" "green with an unreadable head is not re-gated"

echo "# in-flight dedup"
store "[$(anchor D1 pull_request codex "" polecat/d1),
        {\"id\":\"rev-1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D1\",\"gc.routed_to\":\"$POOL\"}}]"
echo "sha-d1" > "$GH_DIR/head_polecat_d1"
out=$(run)
has "$out" "0 reviews dispatched" "a live routed review suppresses the dispatch"

store "[$(anchor D2 pull_request codex "" polecat/d2),
        {\"id\":\"rev-2\",\"status\":\"in_progress\",\"assignee\":\"rig/codex-1\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D2\"}}]"
echo "sha-d2" > "$GH_DIR/head_polecat_d2"
out=$(run)
has "$out" "0 reviews dispatched" "a claimed review (route consumed) suppresses the dispatch"

echo "# stranded review is repaired, not counted in flight forever"
store "[$(anchor D3 pull_request codex "" polecat/d3),
        {\"id\":\"rev-3\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D3\"}}]"
echo "sha-d3" > "$GH_DIR/head_polecat_d3"
out=$(run)
has "$out" "STRANDED review rev-3" "the stranded shape is named"
eq "$(meta rev-3 'gc.routed_to')" "$POOL" "the stranded review was re-routed"
eq "$(meta rev-3 review_pool)" "$POOL" "…with its durable copy restored"
hasnt "$out" "dispatched review new-" "no twin was minted for it"

echo "# merge_hold gates the re-dispatch"
store "[$(anchor E1 pull_request codex "" polecat/e1 ',"merge_hold":"true"')]"
echo "sha-e1" > "$GH_DIR/head_polecat_e1"
out=$(run)
has "$out" "merge_hold is set (operator gate); no dispatch" "an operator hold suppresses the dispatch"
has "$out" "0 reviews dispatched" "…and nothing was dispatched"

echo "# dispatch_count cap"
store "[$(anchor F1 pull_request codex "" polecat/f1 ',"dispatch_count":"3"')]"
echo "sha-f1" > "$GH_DIR/head_polecat_f1"
out=$(run)
has "$out" "cap of 3" "the round cap declines further dispatches"
has "$out" "0 reviews dispatched" "…and nothing was dispatched"

echo "# route write that does not persist is not counted"
store "[$(anchor G1 pull_request codex "" polecat/g1)]"
echo "sha-g1" > "$GH_DIR/head_polecat_g1"
out=$(STUB_DROP_KEYS="new-2:gc.routed_to,review_pool" run); rc=$?
eq "$rc" 0 "a failed route leaves rc=0 (gate armed, merge held)"
has "$out" "did not verify; dispatch NOT counted" "the unverified route is reported"
eq "$(meta G1 dispatch_count)" "<absent>" "an uncounted dispatch does not consume a round"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
