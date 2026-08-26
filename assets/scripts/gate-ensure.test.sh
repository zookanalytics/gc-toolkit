#!/usr/bin/env bash
# Hermetic test for assets/scripts/gate-ensure.sh — arm 1 of the merge cadence.
# Covers: default check_set stamping (and the rc=3 hold when the stamp does not
# persist or the enumeration is unreadable); the `none` opt-out; marker
# classification (green@live head, stale green, exception, fixable, absent,
# unmappable); in-flight dedup (routed, poured, claimed) + stranded repair
# (convoy probe: re-sling only a review with no LIVE tracking convoy, and
# converge after a hard sling failure); the dispatch shape
# (metadata + blocks edge, then gc sling --on mol-review with
# gc.execution_routed_to read-back, never retried in-pass); merge_hold; the
# dispatch_count cap; and the review-wedge escalation (exec-stamp-only reach
# whose poured workflow is spent -> one deduped visit, held one pass first).
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
# escalate.sh stub: records subject/key/message so the wedge arm's one-visit
# contract can be asserted without a live converse pool.
export STUB_ESCALATE_LOG="$TMP/escalate.log"
cat > "$SD/escalate.sh" <<'ESC'
#!/usr/bin/env bash
set -u
{ printf 'CALL'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "${STUB_ESCALATE_LOG:?}"
[ -n "${STUB_ESCALATE_FAIL:-}" ] && exit 1
exit 0
ESC
chmod +x "$SD/escalate.sh"
SUT="$SD/gate-ensure.sh"
POOL="rig/gc-toolkit.polecat-codex"
FIXP="rig/gc-toolkit.polecat"
run() { "$SUT" --default codex --review-pool "$POOL" --fix-pool "$FIXP" 2>&1; }

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
eq "$(meta "$rid" reviewed_oid)" "sha-a1" "dispatch pins reviewed_oid at the live head (signoff binds the verdict to it)"
eq "$(meta "$rid" fix_target_pool)" "$FIXP" "dispatch stamps the derived fix pool for the rework path"
eq "$(meta "$rid" 'gc.execution_routed_to')" "$POOL" "the pour stamped gc.execution_routed_to (the dispatch read-back)"
eq "$(meta "$rid" 'gc.routed_to')" "<absent>" "the pour retired gc.routed_to (never restored beside a live workflow)"
eq "$(meta "$rid" review_pool)" "$POOL" "durable route copy stamped in the metadata stamp"
grep -qxF "$rid|blocks|A1" "$STUB_DEPS" && ok "review blocks the anchor" || bad "blocks edge missing"
has "$(cat "$STUB_GC_LOG")" "sling $POOL $rid --on mol-review" "the review formula is attached by an explicit gc sling --on (no default hijack)"
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
has "$out" "0 reviews dispatched" "a live routed review (legacy stamp shape) suppresses the dispatch"

store "[$(anchor D1b pull_request codex "" polecat/d1b),
        {\"id\":\"rev-1b\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D1b\",\"gc.execution_routed_to\":\"$POOL\"}}]"
echo "sha-d1b" > "$GH_DIR/head_polecat_d1b"
out=$(run)
has "$out" "0 reviews dispatched" "a poured review (gc.execution_routed_to) suppresses the dispatch"

store "[$(anchor D2 pull_request codex "" polecat/d2),
        {\"id\":\"rev-2\",\"status\":\"in_progress\",\"assignee\":\"rig/codex-1\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D2\"}}]"
echo "sha-d2" > "$GH_DIR/head_polecat_d2"
out=$(run)
has "$out" "0 reviews dispatched" "a claimed review (route consumed) suppresses the dispatch"

echo "# stranded review (never poured) is re-slung, not counted in flight forever"
store "[$(anchor D3 pull_request codex "" polecat/d3),
        {\"id\":\"rev-3\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D3\"}}]"
echo "sha-d3" > "$GH_DIR/head_polecat_d3"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "STRANDED review rev-3" "the stranded shape is named"
has "$(cat "$STUB_GC_LOG")" "sling $POOL rev-3 --on mol-review" "the never-poured stranded review is re-slung with the formula"
eq "$(meta rev-3 'gc.execution_routed_to')" "$POOL" "…and the pour read back"
hasnt "$out" "dispatched review new-" "no twin was minted for it"

echo "# stranded review with a tracking convoy is a live pour — never re-slung"
store "[$(anchor D4 pull_request codex "" polecat/d4),
        {\"id\":\"rev-4\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D4\"}},
        {\"id\":\"conv-1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"issue_type\":\"convoy\",\"metadata\":{}}]"
printf 'conv-1|tracks|rev-4\n' >> "$STUB_DEPS"
echo "sha-d4" > "$GH_DIR/head_polecat_d4"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "convoy-tracked" "the convoy-tracked review is recognized as a live pour"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "…and never re-poured (a re-pour mints a second workflow root)"
eq "$(meta rev-4 'gc.routed_to')" "<absent>" "…and gc.routed_to is not restored beside the live workflow"
hasnt "$out" "dispatched review new-" "…and no twin was minted"

echo "# a review tracked ONLY by a closed convoy is dead-tracked — re-slung"
store "[$(anchor D5 pull_request codex "" polecat/d5),
        {\"id\":\"rev-5\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D5\"}},
        {\"id\":\"conv-2\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"issue_type\":\"convoy\",\"metadata\":{}}]"
printf 'conv-2|tracks|rev-5\n' >> "$STUB_DEPS"
echo "sha-d5" > "$GH_DIR/head_polecat_d5"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "STRANDED review rev-5" "a closed convoy no longer counts as a live pour"
has "$(cat "$STUB_GC_LOG")" "sling $POOL rev-5 --on mol-review" "…so the stranded review is re-slung, not suppressed forever"
eq "$(meta rev-5 'gc.execution_routed_to')" "$POOL" "…and the pour read back"

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

echo "# a created-but-unstamped orphan is ADOPTED, never twinned"
store "[$(anchor H1 pull_request codex "" polecat/h1)]"
echo "sha-h1" > "$GH_DIR/head_polecat_h1"
out=$(STUB_DROP_KEYS="new-2:anchor_bead" run)
has "$out" "did not record anchor_bead=H1" "the failed stamp is reported (orphan left behind)"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "the orphan exists"
out=$(run)
has "$out" "adopting unstamped review orphan new-2" "the next pass adopts the orphan by its deterministic title"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "STILL exactly one review bead — no twin minted"
eq "$(meta new-2 anchor_bead)" "H1" "the adopted orphan is now fully stamped"
eq "$(meta new-2 'gc.execution_routed_to')" "$POOL" "…and poured"

echo "# a pour whose exec stamp does not read back is not counted"
store "[$(anchor G1 pull_request codex "" polecat/g1)]"
echo "sha-g1" > "$GH_DIR/head_polecat_g1"
out=$(STUB_DROP_KEYS="new-2:gc.execution_routed_to" run); rc=$?
eq "$rc" 0 "a failed pour read-back leaves rc=0 (gate armed, merge held)"
has "$out" "pour did not read back" "the unverified pour is reported"
has "$out" "dispatch NOT counted" "…and the dispatch is not counted"
eq "$(meta G1 dispatch_count)" "<absent>" "an uncounted dispatch does not consume a round"

echo "# …convergence: the next pass sees the tracking convoy and does not twin"
printf '{"id":"conv-g1","status":"open","assignee":"","notes":"","issue_type":"convoy","metadata":{}}' > "$TMP/conv.json"
store "$(jq -c --slurpfile c "$TMP/conv.json" '. + $c' "$STUB_STORE")"
printf 'conv-g1|tracks|new-2\n' >> "$STUB_DEPS"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "convoy-tracked" "the half-landed pour is recognized by its convoy"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "…never re-poured"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "STILL exactly one review bead — no twin minted"

echo "# a hard sling failure (rc!=0, nothing written) is not counted…"
store "[$(anchor K1 pull_request codex "" polecat/k1)]"
echo "sha-k1" > "$GH_DIR/head_polecat_k1"
out=$(STUB_SLING_FAIL=1 run); rc=$?
eq "$rc" 0 "a hard sling failure leaves rc=0 (gate armed, merge held)"
has "$out" "pour did not read back" "the hard-failed pour is reported"
has "$out" "dispatch NOT counted" "…and the dispatch is not counted"
eq "$(meta K1 dispatch_count)" "<absent>" "…and no review round was consumed"
krid=$(jq -r '.[] | select(.id | startswith("new-")) | .id' "$STUB_STORE")
eq "$(meta "$krid" 'gc.execution_routed_to')" "<absent>" "the failed sling wrote no exec stamp"

echo "# …and converges: the next pass re-slings it as stranded (no convoy)"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "STRANDED review $krid" "the never-poured bead is seen as stranded"
has "$(cat "$STUB_GC_LOG")" "sling $POOL $krid --on mol-review" "…and re-slung successfully"
eq "$(meta "$krid" 'gc.execution_routed_to')" "$POOL" "…with the pour read back (hard-fail convergence)"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "STILL exactly one review bead — no twin minted"

# --- review-wedge escalation -------------------------------------------------
# A poured review reaches the gate through its workflow alone. Once that
# workflow is spent no verdict can still be coming, and only these fixtures
# distinguish that from a review still legitimately running.
review_row() { # <id> <anchor>
  printf '{"id":"%s","status":"open","assignee":"","notes":"","metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"%s","gc.execution_routed_to":"%s","review_pool":"%s"}}' \
    "$1" "$2" "$POOL" "$POOL"
}
convoy_row() { # <id>
  printf '{"id":"%s","status":"open","assignee":"","notes":"","issue_type":"convoy","metadata":{}}' "$1"
}
root_row() { # <id> <convoy>
  printf '{"id":"%s","status":"in_progress","assignee":"","notes":"","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"%s"}}' "$1" "$2"
}
step_row() { # <id> <root> <step> <status>
  printf '{"id":"%s","status":"%s","assignee":"","notes":"","metadata":{"gc.root_bead_id":"%s","gc.step_ref":"mol-review.%s"}}' \
    "$1" "$4" "$2" "$3"
}
# Every step closed but the finalizer: the shape a reviewer leaves behind when
# it closes its chain and dies before signoff.sh or the route restore.
spent_steps() { # <root> <id-prefix>
  printf '%s,%s,%s,%s' \
    "$(step_row "$2-a" "$1" load-dispatch closed)" \
    "$(step_row "$2-b" "$1" review closed)" \
    "$(step_row "$2-c" "$1" verdict-and-drain closed)" \
    "$(step_row "$2-d" "$1" workflow-finalize open)"
}
live_steps() { # <root> <id-prefix>
  printf '%s,%s,%s,%s' \
    "$(step_row "$2-a" "$1" load-dispatch closed)" \
    "$(step_row "$2-b" "$1" review in_progress)" \
    "$(step_row "$2-c" "$1" verdict-and-drain open)" \
    "$(step_row "$2-d" "$1" workflow-finalize open)"
}

echo "# a spent pour is held one pass, then escalated once"
store "[$(anchor W1 pull_request codex "" polecat/w1),
        $(review_row rev-w1 W1),
        $(convoy_row conv-w1),
        $(root_row root-w1 conv-w1),
        $(spent_steps root-w1 sw1)]"
printf 'conv-w1|tracks|rev-w1\n' >> "$STUB_DEPS"
echo "sha-w1" > "$GH_DIR/head_polecat_w1"
: > "$STUB_ESCALATE_LOG"
out=$(run)
has "$out" "looks WEDGED" "the first sighting names the wedge"
has "$out" "holding one pass" "…and holds, because the route restore lands AFTER the chain close"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "nothing is escalated on a single sighting"
eq "$(meta rev-w1 wedge_seen_root)" "root-w1" "the sighting is stamped against the root it saw"
has "$out" "0 reviews dispatched" "a wedged review is never twinned by a fresh dispatch"

out=$(run)
has "$out" "is WEDGED" "the second sighting confirms it"
has "$out" "escalated [review-wedge]" "…and escalates"
esc=$(cat "$STUB_ESCALATE_LOG")
has "$esc" "--subject rev-w1" "the visit is filed on the wedged review bead"
has "$esc" "--key review-wedge" "…under one situation key, so repeats dedup"
has "$esc" "gate 'codex' on W1 is held" "…naming the anchor and gate that are stuck"
has "$esc" "gc bd update rev-w1 --set-metadata gc.routed_to=$POOL" "…and the route-restore repair"
has "$esc" "root-w1" "…and the spent workflow"
has "$esc" "check.codex is absent" "…and the marker state, not the dispatch arm's rationale"
has "$out" "0 reviews dispatched" "escalating still dispatches nothing"

echo "# a pour still running its chain is never escalated"
store "[$(anchor W2 pull_request codex "" polecat/w2),
        $(review_row rev-w2 W2),
        $(convoy_row conv-w2),
        $(root_row root-w2 conv-w2),
        $(live_steps root-w2 sw2)]"
printf 'conv-w2|tracks|rev-w2\n' >> "$STUB_DEPS"
echo "sha-w2" > "$GH_DIR/head_polecat_w2"
: > "$STUB_ESCALATE_LOG"
out=$(run); out="$out$(run)"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "a live step chain escalates nothing, however many passes run"
eq "$(meta rev-w2 wedge_seen_root)" "<absent>" "…and is never even stamped as a sighting"
hasnt "$out" "WEDGED" "…and is never called wedged"

echo "# only the finalizer open still counts as spent (it is the dispatcher's)"
store "[$(anchor W3 pull_request codex "" polecat/w3),
        $(review_row rev-w3 W3),
        $(convoy_row conv-w3),
        $(root_row root-w3 conv-w3),
        $(step_row sw3-a root-w3 load-dispatch closed),
        $(step_row sw3-b root-w3 review closed),
        $(step_row sw3-c root-w3 verdict-and-drain closed),
        $(step_row sw3-d root-w3 workflow-finalize in_progress)]"
printf 'conv-w3|tracks|rev-w3\n' >> "$STUB_DEPS"
echo "sha-w3" > "$GH_DIR/head_polecat_w3"
: > "$STUB_ESCALATE_LOG"
out=$(run); out=$(run)
has "$(cat "$STUB_ESCALATE_LOG")" "--subject rev-w3" "a chain whose only live step is workflow-finalize is spent"

echo "# a re-pour: one spent root beside a live one is NOT spent"
store "[$(anchor W4 pull_request codex "" polecat/w4),
        $(review_row rev-w4 W4),
        $(convoy_row conv-w4),
        $(convoy_row conv-w4b),
        $(root_row root-w4 conv-w4),
        $(root_row root-w4b conv-w4b),
        $(spent_steps root-w4 sw4),
        $(live_steps root-w4b sw4b)]"
printf 'conv-w4|tracks|rev-w4\nconv-w4b|tracks|rev-w4\n' >> "$STUB_DEPS"
echo "sha-w4" > "$GH_DIR/head_polecat_w4"
: > "$STUB_ESCALATE_LOG"
out=$(run); out="$out$(run)"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "a second live workflow keeps the review in flight"
eq "$(meta rev-w4 wedge_seen_root)" "<absent>" "…and no sighting is recorded"

echo "# an unreadable pour linkage escalates nothing"
store "[$(anchor W5 pull_request codex "" polecat/w5),
        $(review_row rev-w5 W5)]"
echo "sha-w5" > "$GH_DIR/head_polecat_w5"
: > "$STUB_ESCALATE_LOG"
out=$(run); out="$out$(run)"
has "$out" "pour-liveness probe unreadable" "a review with no traceable workflow is reported, not judged"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "…and nothing is escalated on an unanswerable probe"
has "$out" "0 reviews dispatched" "…and no twin is dispatched either"

echo "# a root whose steps do not enumerate is unanswerable, not spent"
store "[$(anchor W6 pull_request codex "" polecat/w6),
        $(review_row rev-w6 W6),
        $(convoy_row conv-w6),
        $(root_row root-w6 conv-w6)]"
printf 'conv-w6|tracks|rev-w6\n' >> "$STUB_DEPS"
echo "sha-w6" > "$GH_DIR/head_polecat_w6"
: > "$STUB_ESCALATE_LOG"
out=$(run); out="$out$(run)"
has "$out" "pour-liveness probe unreadable" "an empty step enumeration proves nothing about the pour"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "…and escalates nothing"

echo "# a failed escalation is reported, and retried next pass"
store "[$(anchor W7 pull_request codex "" polecat/w7),
        $(review_row rev-w7 W7),
        $(convoy_row conv-w7),
        $(root_row root-w7 conv-w7),
        $(spent_steps root-w7 sw7)]"
printf 'conv-w7|tracks|rev-w7\n' >> "$STUB_DEPS"
echo "sha-w7" > "$GH_DIR/head_polecat_w7"
: > "$STUB_ESCALATE_LOG"
out=$(run)
out=$(STUB_ESCALATE_FAIL=1 run); rc=$?
eq "$rc" 0 "a failed escalation does not fail the pass"
has "$out" "the escalation did not file" "…it is reported"
out=$(run)
has "$out" "escalated [review-wedge]" "…and the next pass files it (the sighting stamp persists)"

# Both of the next two carry a SPENT chain on purpose: without it the
# unreadable-linkage guard would decline the escalation on its own and the
# exec-only qualification would never be the reason the arm stayed quiet.
echo "# a review the pool can still re-claim is not the wedge arm's business"
store "[$(anchor W8 pull_request codex "" polecat/w8),
        {\"id\":\"rev-w8\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"W8\",\"gc.routed_to\":\"$POOL\",\"gc.execution_routed_to\":\"$POOL\"}},
        $(convoy_row conv-w8),
        $(root_row root-w8 conv-w8),
        $(spent_steps root-w8 sw8)]"
printf 'conv-w8|tracks|rev-w8\n' >> "$STUB_DEPS"
echo "sha-w8" > "$GH_DIR/head_polecat_w8"
: > "$STUB_ESCALATE_LOG"
out=$(run); out="$out$(run)"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "a restored route means the pool can re-claim it — spent chain or not"
eq "$(meta rev-w8 wedge_seen_root)" "<absent>" "…and no sighting is recorded"
hasnt "$out" "WEDGED" "…and it is never called wedged"

echo "# a claimed review is not the wedge arm's business either"
store "[$(anchor W9 pull_request codex "" polecat/w9),
        {\"id\":\"rev-w9\",\"status\":\"in_progress\",\"assignee\":\"rig/codex-1\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"W9\",\"gc.execution_routed_to\":\"$POOL\"}},
        $(convoy_row conv-w9),
        $(root_row root-w9 conv-w9),
        $(spent_steps root-w9 sw9)]"
printf 'conv-w9|tracks|rev-w9\n' >> "$STUB_DEPS"
echo "sha-w9" > "$GH_DIR/head_polecat_w9"
: > "$STUB_ESCALATE_LOG"
out=$(run); out="$out$(run)"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "an agent still holding the bead is finishing the round, not wedged"
eq "$(meta rev-w9 wedge_seen_root)" "<absent>" "…and no sighting is recorded"
hasnt "$out" "WEDGED" "…and it is never called wedged"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
