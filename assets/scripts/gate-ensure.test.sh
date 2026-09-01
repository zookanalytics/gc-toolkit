#!/usr/bin/env bash
# Hermetic test for assets/scripts/gate-ensure.sh — arm 1 of the merge cadence.
# Covers: default check_set stamping (and the rc=3 hold when the stamp does not
# persist or the enumeration is unreadable); the `none` opt-out; lane-state
# classification (green settles; unreviewed, reviewing, validating, fixing, an
# absent marker and an unknown word each dispatch — and a green lane stays
# settled at a head no verdict ever named); a declared lane still carrying a
# legacy exception@<oid> park is a pre-migration hold (wedged, no dispatch),
# never a fresh dispatch; the live-head read, which now decides only the
# dispatch pin and the machine axis (a deleted ref, a body without .sha, and a
# failed read are all unanswerable); the stray-marker sweep (undeclared and
# outside the lane vocabulary is cleared, the retired green@ grammar included;
# a declared or well-formed one is not, and neither is an undeclared legacy
# exception@ — left for migrate-lane-states.sh; an unpersisted clear is
# reported); a multi-gate check_set split per gate rather than joined into one
# name; in-flight dedup (routed, poured, claimed) + stranded repair (root
# probe: re-sling a review with no LIVE tracking convoy, or one whose live
# convoy carries no workflow root — a pour that minted the convoy but died
# before the root drives nothing and must not hold the anchor in flight
# forever; and when the convoy DOES carry a root, judge it by the poured arm's
# liveness check — a live chain is in flight, a spent one is wedged, an
# unreadable one is held — never counted in flight on sight; and converge
# after a hard sling failure); an in-flight REWORK
# child (a blocks-dep bead carrying source_review_bead) withholds a fresh
# dispatch until it closes; the
# dispatch shape
# (metadata + blocks edge, then gc sling --on mol-review with
# gc.execution_routed_to read-back, never retried in-pass); merge_hold, and the
# cap's park under it reading as the wedge; dispatch_count as a tally the round
# cap never reads; the dispatch backstop (a ceiling on DISPATCHES that refuses
# loudly -- one deduped visit plus a stamp and a note on the anchor -- and
# restates itself when the head moves); and the review-wedge escalation, shared
# by both reach shapes (an exec-stamp-only poured review, and a no-stamp review
# a tracking convoy's root drives) -> a spent workflow is one deduped visit,
# held one pass first.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gate-ensure-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
# A hermetic suite must not read the caller's city: an ambient GC_RIG changes
# the gc sling argv these assertions match on.
unset GC_RIG 2>/dev/null || true
harness_init

# Private scripts dir: the SUT plus a body-emitter stub (interface unchanged).
SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/gate-ensure.sh" "$HERE/lifecycle.sh"
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
# The SUT forwards GC_RIG into every sling and reads GC_MAX_REVIEW_DISPATCHES as
# the ceiling; an ambient value would rewrite the assertions below.
unset GC_RIG GC_MAX_REVIEW_DISPATCHES 2>/dev/null || true
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

# sha1sum is exactly 40 lowercase hex, so a labelled fixture oid satisfies the
# marker grammar. A shorter string is a MALFORMED marker — a different arm.
# live_head_for holds the head it reads to that same grammar, so fixture HEADS
# go through here too; a mnemonic like "sha-b4" now reads as no head at all.
oid() { printf '%s' "$1" | sha1sum | cut -d' ' -f1; }
# The machine axis (lifecycle/lifecycle.toml [machine_axis]) as the anchor
# carries it, and with the instant stripped.
machine() { printf '%s' "$(meta "$1" pr.machine)"; }
pinned()  { local v; v="$(machine "$1")"; case "$v" in *@*@*) printf '%s' "${v%@*}" ;; *) printf '%s' "$v" ;; esac; }
SHORT="8d7f0cf3c"   # the abbreviated-sha shape that wedged gc-na313

# Store-row fixture builders, shared by the stranded-repair and review-wedge
# sections. A review's reach to the gate is routed|poured|claimed: review_row is
# the poured shape (gc.execution_routed_to), stranded_review_row the inert one
# (no stamp, no route, no assignee). A pour is a convoy (tracks the review) whose
# member is a workflow root, and the root's steps carry gc.root_bead_id. A chain
# with every step but the finalizer closed is spent; one non-final step still
# open is live.
review_row() { # <id> <anchor>
  printf '{"id":"%s","status":"open","assignee":"","notes":"","metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"%s","gc.execution_routed_to":"%s","review_pool":"%s"}}' \
    "$1" "$2" "$POOL" "$POOL"
}
stranded_review_row() { # <id> <anchor>
  printf '{"id":"%s","status":"open","assignee":"","notes":"","metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"%s"}}' \
    "$1" "$2"
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

echo "# stamping the default"
store "[$(anchor A1 pre_open_gate "" "" polecat/a1)]"
oid a1 > "$GH_DIR/head_polecat_a1"
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
eq "$(meta "$rid" reviewed_oid)" "$(oid a1)" "dispatch pins reviewed_oid at the live head (signoff binds the verdict to it)"
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

echo "# opt-out and green lanes are settled"
store "[$(anchor B1 pre_open_gate none "" polecat/b1),
        $(anchor B2 pre_open_gate codex green polecat/b2),
        $(anchor B3 pull_request codex green polecat/b3)]"
oid b2 > "$GH_DIR/head_polecat_b2"
oid b3 > "$GH_DIR/head_polecat_b3"
: > "$STUB_GC_LOG"
out=$(run); rc=$?
eq "$rc" 0 "opt-out/settled pass exits 0"
eq "$(meta B1 check_set)" "none" "the none sentinel is left alone"
has "$out" "0 reviews dispatched" "a green lane, and none, dispatch nothing"

# The whole of the 211. Green is a state of the lane, so the head the branch
# now carries is not the gate's business: no dispatch, at any head, ever.
echo "# a green lane at a head no verdict ever named is still settled"
store "[$(anchor B2b pre_open_gate codex green polecat/b2b)]"
oid moved-on-b2b > "$GH_DIR/head_polecat_b2b"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "0 reviews dispatched" "a branch that grew commits buys no review"
hasnt "$out" "advanced to" "…and no arm calls the move a reason to re-gate"
eq "$(meta B2b dispatch_count)" "<absent>" "…and no dispatch is counted"

# check_set is a comma list and each gate is addressed by its own name, so the
# split has to survive whitespace around the separators.
echo "# a multi-gate check_set is raised per gate, never as one joined name"
store "[$(anchor M1 pull_request "codex, triage" green polecat/m1)]"
oid m1 > "$GH_DIR/head_polecat_m1"
: > "$STUB_GC_LOG"
out=$(run)
hasnt "$out" "codextriage" "the comma list is not collapsed into one gate name"
has "$out" "gate 'triage'" "the second declared gate is raised under its own name"
mrid=$(jq -r '.[] | select(.id | startswith("new-")) | .id' "$STUB_STORE")
eq "$(meta "$mrid" check_name)" "triage" "the dispatched review names the real gate"
eq "$(meta M1 dispatch_count)" "1" "the green lane bought no dispatch"

echo "# the cap's park suppresses the dispatch and reads as the wedge"
# The shared predicate (also merge.sh's): merge_hold is the literal string
# "signoff_cap" AND signoff_cap is non-empty. An operator's own hold writes
# merge_hold=true, never this value.
store "[$(anchor B4 pull_request codex unreviewed polecat/b4 ',"merge_hold":"signoff_cap","signoff_cap":"codex","gc.routed_to":"human"')]"
oid b4 > "$GH_DIR/head_polecat_b4"
: > "$STUB_GC_LOG"
out=$(run); rc=$?
eq "$rc" 0 "the park pass exits 0"
has "$out" "0 reviews dispatched" "a parked anchor buys no review"
has "$out" "1 operator-held" "…and is counted as held"
eq "$(pinned B4)" "wedged-exception@$(oid b4)" "…and the machine axis is the cap's wedge"

echo "# an operator hold beside a STALE orphan signoff_cap is not the cap's wedge"
# merge_hold=true (not the literal "signoff_cap") is an operator's own hold,
# even with a signoff_cap value left over from an earlier park.
store "[$(anchor B4b pull_request codex unreviewed polecat/b4b ',"merge_hold":"true","signoff_cap":"codex"')]"
oid b4b > "$GH_DIR/head_polecat_b4b"
out=$(run); rc=$?
eq "$rc" 0 "the held pass exits 0"
has "$out" "0 reviews dispatched" "an operator hold still suppresses the dispatch"
eq "$(pinned B4b)" "progressing@$(oid b4b)" "…but the machine axis reads progressing, not the cap's wedge"

echo "# a fully green capped anchor still records the wedge — the park sits on the anchor, not the lane"
store "[$(anchor B4c pull_request codex green polecat/b4c ',"merge_hold":"signoff_cap","signoff_cap":"codex","gc.routed_to":"human"')]"
oid b4c > "$GH_DIR/head_polecat_b4c"
out=$(run); rc=$?
eq "$rc" 0 "the settled-but-parked pass exits 0"
has "$out" "0 reviews dispatched" "a green lane dispatches nothing, capped or not"
eq "$(pinned B4c)" "wedged-exception@$(oid b4c)" "…but the machine axis still reads the cap's wedge, not settled"

echo "# every lane short of green dispatches"
store "[$(anchor C1 pre_open_gate codex unreviewed polecat/c1),
        $(anchor C2 pull_request codex fixing polecat/c2),
        $(anchor C3 pull_request codex "" polecat/c3),
        $(anchor C3b pull_request codex reviewing polecat/c3b),
        $(anchor C3c pull_request codex validating polecat/c3c),
        $(anchor C4 pull_request codex "red" polecat/c4)]"
for b in c1 c2 c3 c3b c3c c4; do oid "$b" > "$GH_DIR/head_polecat_$b"; done
out=$(run); rc=$?
eq "$rc" 0 "dispatch pass exits 0"
has "$out" "6 reviews dispatched" "unreviewed, fixing, absent, reviewing, validating and an unknown word each dispatched one"
has "$out" "the lane is unreviewed" "the absent marker names the lane it means"
has "$out" "names no lane state the contract knows" "an unknown word is named as one"

echo "# an unreadable live head neither settles a lane nor stops a dispatch"
# gh answers a deleted ref with a 422: error body on STDOUT, non-zero exit. The
# classification never consulted it, so the only thing the head decides now is
# the dispatch pin and the machine axis.
store "[$(anchor C5 pre_open_gate codex green polecat/c5),
        $(anchor C5b pull_request codex unreviewed polecat/c5b)]"
: > "$STUB_GC_LOG"
out=$(run); rc=$?
eq "$rc" 0 "no-head pass exits 0"
has "$out" "1 reviews dispatched" "the green lane is settled and the unreviewed one still dispatches"
hasnt "$out" "No commit found" "the gh error body never becomes a dispatch reason"
eq "$(pinned C5b)" "<absent>" "an unreadable head records no machine axis"
c5brid=$(jq -r '.[] | select(.id | startswith("new-")) | .id' "$STUB_STORE")
eq "$(meta "$c5brid" reviewed_oid)" "<absent>" "…and the dispatch carries no pin it could not read"

echo "# a head that is not a SHA is not a head"
# gh exits 0 and prints 'null' when the body carries no .sha: the exit code
# alone does not separate a head from a miss.
store "[$(anchor C7 pre_open_gate codex unreviewed polecat/c7)]"
echo "null" > "$GH_DIR/head_polecat_c7"
: > "$STUB_GC_LOG"
out=$(run); rc=$?
eq "$rc" 0 "malformed-head pass exits 0"
eq "$(pinned C7)" "<absent>" "a non-SHA answer at rc=0 is unanswerable, and records nothing"

echo "# stray markers: a check.<g> outside check_set that no arm could rewrite"
store "[$(anchor N1 pull_request codex green polecat/n1 ',"check.refinery":"green@'"$SHORT"'"')]"
oid n1 > "$GH_DIR/head_polecat_n1"
out=$(run); rc=$?
eq "$rc" 0 "the sweep pass exits 0"
eq "$(meta N1 check.refinery)" "<absent>" "the undeclared legacy marker is cleared"
eq "$(meta N1 check.codex)" "green" "…and the declared lane state is untouched"
has "$out" "cleared undeclared malformed gate marker check.refinery" "the clear is reported"
has "$out" "1 stray markers cleared" "…and counted"
has "$out" "0 reviews dispatched" "…and a marker that governs nothing dispatches nothing"
has "$(jq -r '.[] | select(.id == "N1") | .notes' "$STUB_STORE")" "does not declare that gate" "the anchor records why it was cleared"

echo "# …a WELL-FORMED undeclared lane state is history, not damage"
store "[$(anchor N2 pull_request codex green polecat/n2 ',"check.refinery":"fixing"')]"
oid n2 > "$GH_DIR/head_polecat_n2"
out=$(run)
eq "$(meta N2 check.refinery)" "fixing" "a narrowed check_set keeps its well-formed history"
has "$out" "0 stray markers cleared" "…and nothing was swept"

echo "# …an undeclared legacy exception@ is EXEMPT from the sweep — migrate-lane-states.sh's to retire"
# Between this PR merging and the migration running, an anchor can still carry
# check.<g>=exception@<oid> with merge_hold unset. Sweeping it here the moment
# check_set narrows would leave the migration nothing to find, so it survives
# like an operator's park, not like the rest of the retired grammar.
store "[$(anchor N3 pull_request codex green polecat/n3 ',"check.refinery":"exception@'"$SHORT"'"')]"
oid n3 > "$GH_DIR/head_polecat_n3"
out=$(run)
eq "$(meta N3 check.refinery)" "exception@$SHORT" "the legacy park survives the sweep"
has "$out" "0 stray markers cleared" "…and nothing is counted as swept"

echo "# …a DECLARED lane still carrying that legacy exception@ park is a pre-migration hold"
store "[$(anchor N3b pull_request codex "exception@$SHORT" polecat/n3b ',"gc.routed_to":"human","blocked_reason":"round cap"')]"
oid n3b > "$GH_DIR/head_polecat_n3b"
: > "$STUB_GC_LOG"
out=$(run); rc=$?
eq "$rc" 0 "the pre-migration park pass exits 0"
has "$out" "0 reviews dispatched" "a legacy exception@ park on a declared gate buys no review"
has "$out" "awaits migrate-lane-states.sh" "…and says why"
has "$out" "1 operator-held" "…and is counted as held"
eq "$(pinned N3b)" "wedged-exception@$(oid n3b)" "…and the machine axis reads the cap's wedge"

echo "# …the none opt-out does not exempt an anchor from the sweep"
store "[$(anchor N4 pull_request none "" polecat/n4 ',"check.refinery":"green@'"$SHORT"'"')]"
out=$(run)
eq "$(meta N4 check.refinery)" "<absent>" "check_set=none still gets its stray marker cleared"
has "$out" "0 reviews dispatched" "…and none still dispatches nothing"

echo "# …a clear that does not persist is reported, not counted"
store "[$(anchor N5 pull_request codex green polecat/n5 ',"check.refinery":"green@'"$SHORT"'"')]"
oid n5 > "$GH_DIR/head_polecat_n5"
out=$(STUB_DROP_KEYS="N5:check.refinery" run 2>&1); rc=$?
eq "$rc" 0 "an unpersisted clear does not hold the merge (the marker gates nothing)"
eq "$(meta N5 check.refinery)" "green@$SHORT" "the marker is still there"
has "$out" "still reads" "the failed clear is reported"
has "$out" "0 stray markers cleared" "…and not counted"

echo "# in-flight dedup"
store "[$(anchor D1 pull_request codex "" polecat/d1),
        {\"id\":\"rev-1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D1\",\"gc.routed_to\":\"$POOL\"}}]"
oid d1 > "$GH_DIR/head_polecat_d1"
out=$(run)
has "$out" "0 reviews dispatched" "a live routed review (legacy stamp shape) suppresses the dispatch"

store "[$(anchor D1b pull_request codex "" polecat/d1b),
        {\"id\":\"rev-1b\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D1b\",\"gc.execution_routed_to\":\"$POOL\"}}]"
oid d1b > "$GH_DIR/head_polecat_d1b"
out=$(run)
has "$out" "0 reviews dispatched" "a poured review (gc.execution_routed_to) suppresses the dispatch"

store "[$(anchor D2 pull_request codex "" polecat/d2),
        {\"id\":\"rev-2\",\"status\":\"in_progress\",\"assignee\":\"rig/codex-1\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"D2\"}}]"
oid d2 > "$GH_DIR/head_polecat_d2"
out=$(run)
has "$out" "0 reviews dispatched" "a claimed review (route consumed) suppresses the dispatch"

echo "# stranded review (never poured) is re-slung, not counted in flight forever"
store "[$(anchor D3 pull_request codex "" polecat/d3),
        $(stranded_review_row rev-3 D3)]"
oid d3 > "$GH_DIR/head_polecat_d3"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "STRANDED review rev-3" "the stranded shape is named"
has "$(cat "$STUB_GC_LOG")" "sling $POOL rev-3 --on mol-review" "the never-poured stranded review is re-slung with the formula"
eq "$(meta rev-3 'gc.execution_routed_to')" "$POOL" "…and the pour read back"
hasnt "$out" "dispatched review new-" "no twin was minted for it"

echo "# stranded review whose tracked root has a LIVE step chain is a live pour — never re-slung"
store "[$(anchor D4 pull_request codex "" polecat/d4),
        $(stranded_review_row rev-4 D4),
        $(convoy_row conv-1),
        $(root_row root-1 conv-1),
        $(live_steps root-1 s4)]"
printf 'conv-1|tracks|rev-4\n' >> "$STUB_DEPS"
oid d4 > "$GH_DIR/head_polecat_d4"
: > "$STUB_GC_LOG"; : > "$STUB_ESCALATE_LOG"
out=$(run)
has "$out" "live poured workflow" "a tracked root whose non-final steps are still open is a live pour"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "…and never re-poured (a re-pour mints a second workflow root)"
eq "$(meta rev-4 'gc.routed_to')" "<absent>" "…and gc.routed_to is not restored beside the live workflow"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "…and a live chain is never escalated as wedged"
hasnt "$out" "dispatched review new-" "…and no twin was minted"

echo "# stranded review (no exec stamp) whose tracked root is SPENT is wedged, not counted in flight forever"
store "[$(anchor D4s pull_request codex "" polecat/d4s),
        $(stranded_review_row rev-4s D4s),
        $(convoy_row conv-1s),
        $(root_row root-1s conv-1s),
        $(spent_steps root-1s s4s)]"
printf 'conv-1s|tracks|rev-4s\n' >> "$STUB_DEPS"
oid d4s > "$GH_DIR/head_polecat_d4s"
: > "$STUB_GC_LOG"; : > "$STUB_ESCALATE_LOG"
out=$(run)
has "$out" "looks WEDGED" "a stranded review whose tracked root is spent is seen as wedged, not in flight"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "…and not re-slung (a root exists; a re-pour would mint a second)"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "…nothing escalates on the first sighting"
out=$(run)
has "$out" "is WEDGED" "the second sighting confirms it"
esc=$(cat "$STUB_ESCALATE_LOG")
has "$esc" "--subject rev-4s" "the visit is filed on the wedged stranded review"
has "$esc" "--key review-wedge" "…under the same wedge key the poured arm uses"
has "$esc" "root-1s" "…naming the spent workflow"

echo "# stranded review whose tracked root does not enumerate its steps is held, not claimed a live pour"
store "[$(anchor D4u pull_request codex "" polecat/d4u),
        $(stranded_review_row rev-4u D4u),
        $(convoy_row conv-1u),
        $(root_row root-1u conv-1u)]"
printf 'conv-1u|tracks|rev-4u\n' >> "$STUB_DEPS"
oid d4u > "$GH_DIR/head_polecat_d4u"
: > "$STUB_GC_LOG"; : > "$STUB_ESCALATE_LOG"
out=$(run); out="$out$(run)"
has "$out" "pour-liveness probe unreadable" "a root that does not enumerate its steps proves nothing about the pour"
hasnt "$out" "live poured workflow" "…so it is never claimed to be a live pour"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "…and never re-poured behind an unreadable root"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "…and nothing is escalated on an unanswerable probe"

echo "# stranded review tracked by an EMPTY live convoy (pour minted the convoy but died before the root) is re-slung, not held in flight forever"
store "[$(anchor D4e pull_request codex "" polecat/d4e),
        $(stranded_review_row rev-4e D4e),
        $(convoy_row conv-1e)]"
printf 'conv-1e|tracks|rev-4e\n' >> "$STUB_DEPS"
oid d4e > "$GH_DIR/head_polecat_d4e"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "STRANDED review rev-4e" "an empty tracking convoy carries no root, so it is not a live pour"
has "$(cat "$STUB_GC_LOG")" "sling $POOL rev-4e --on mol-review" "…so the stranded review is re-slung, minting the first root"
eq "$(meta rev-4e 'gc.execution_routed_to')" "$POOL" "…and the pour read back"
hasnt "$out" "convoy-tracked" "…and it is never counted in flight behind an empty convoy"

echo "# a review tracked ONLY by a closed convoy is dead-tracked — re-slung"
store "[$(anchor D5 pull_request codex "" polecat/d5),
        $(stranded_review_row rev-5 D5),
        {\"id\":\"conv-2\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"issue_type\":\"convoy\",\"metadata\":{}}]"
printf 'conv-2|tracks|rev-5\n' >> "$STUB_DEPS"
oid d5 > "$GH_DIR/head_polecat_d5"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "STRANDED review rev-5" "a closed convoy no longer counts as a live pour"
has "$(cat "$STUB_GC_LOG")" "sling $POOL rev-5 --on mol-review" "…so the stranded review is re-slung, not suppressed forever"
eq "$(meta rev-5 'gc.execution_routed_to')" "$POOL" "…and the pour read back"

echo "# merge_hold gates the re-dispatch"
store "[$(anchor E1 pull_request codex "" polecat/e1 ',"merge_hold":"true"')]"
oid e1 > "$GH_DIR/head_polecat_e1"
out=$(run)
has "$out" "merge_hold is set (operator gate); no dispatch" "an operator hold suppresses the dispatch"
has "$out" "0 reviews dispatched" "…and nothing was dispatched"

# --- rework rounds: the ledger the cap is counted from --------------------------
# A review of a commit no rework has touched returns the findings that filed
# the child already waiting, and spends a dispatch round doing it.
judged_review() { # <id> <anchor> <oid>
  printf '{"id":"%s","status":"closed","assignee":"","notes":"","metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"%s","reviewed_oid":"%s"}}' \
    "$1" "$2" "$3"
}
rework_kid() { # <id> <source-review> <status>
  printf '{"id":"%s","status":"%s","assignee":"","notes":"","metadata":{"source_review_bead":"%s"}}' "$1" "$3" "$2"
}

echo "# dispatch_count is a tally, not a cap: cap-many spent rounds still dispatch"
store "[$(anchor F1 pull_request codex "" polecat/f1 ',"dispatch_count":"3"'),
        $(judged_review rev-f1 F1 old-f1),
        $(rework_kid fix-f1a rev-f1 closed),
        $(rework_kid fix-f1b rev-f1 closed),
        $(rework_kid fix-f1c rev-f1 closed)]"
printf 'fix-f1a|blocks|F1\nfix-f1b|blocks|F1\nfix-f1c|blocks|F1\n' >> "$STUB_DEPS"
oid f1 > "$GH_DIR/head_polecat_f1"
out=$(run)
has "$out" "1 reviews dispatched" "the third rework's result still gets the review that settles the gate"
hasnt "$out" "cap of" "…no dispatch-side cap preempts signoff.sh's terminal verdict"
eq "$(meta F1 dispatch_count)" "4" "…and the tally advances past the cap it is not"

# A commit no longer bars a dispatch — but an OPEN rework child does: that is
# what the lane is owed, and inflight_review only ever sees live REVIEW beads,
# never a rework child, so without this probe a fresh review pours at the same
# head every pass while the rework child sits open.
echo "# an OPEN rework child blocks the fresh dispatch — the lane is owed rework, not a new review"
store "[$(anchor R1 pull_request codex "" polecat/r1),
        $(judged_review rev-r1 R1 "$(oid r1)"),
        $(rework_kid fix-r1 rev-r1 open)]"
printf 'fix-r1|blocks|R1\n' >> "$STUB_DEPS"
oid r1 > "$GH_DIR/head_polecat_r1"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "0 reviews dispatched" "the open rework child withholds the fresh dispatch"
has "$out" "waiting on rework child fix-r1" "…and the anchor says why"
hasnt "$out" "already judged" "…and no arm claims a commit was judged"
hasnt "$(cat "$STUB_GC_LOG")" "bd create" "…and no review bead is created"

echo "# …but a CLOSED rework child no longer blocks it"
store "[$(anchor R1c pull_request codex "" polecat/r1c),
        $(judged_review rev-r1c R1c "$(oid r1c)"),
        $(rework_kid fix-r1c rev-r1c closed)]"
printf 'fix-r1c|blocks|R1c\n' >> "$STUB_DEPS"
oid r1c > "$GH_DIR/head_polecat_r1c"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "1 reviews dispatched" "a closed rework child no longer withholds the review"

echo "# …and an unreadable rework ledger holds the dispatch, like an unreadable in-flight lookup"
store "[$(anchor R1u pull_request codex "" polecat/r1u)]"
oid r1u > "$GH_DIR/head_polecat_r1u"
out=$(STUB_DEP_GARBAGE=1 run)
has "$out" "rework-child ledger unreadable" "the unreadable ledger is named"
has "$out" "0 reviews dispatched" "…and nothing is dispatched"

echo "# the stranded-review repair is refused nothing either"
store "[$(anchor R8 pull_request codex "" polecat/r8),
        {\"id\":\"rev-stray8\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"R8\"}},
        $(judged_review rev-r8old R8 "$(oid r8)"),
        $(rework_kid fix-r8 rev-r8old open)]"
printf 'fix-r8|blocks|R8\n' >> "$STUB_DEPS"
oid r8 > "$GH_DIR/head_polecat_r8"
: > "$STUB_GC_LOG"
out=$(run)
has "$(cat "$STUB_GC_LOG")" "sling $POOL rev-stray8 --on mol-review" "an inert review is re-slung"

# --- dispatch backstop -------------------------------------------------------
# The ceiling bounds DISPATCHES. already_answered above sees only the rework a
# verdict actually filed, so a review that ends writing no marker and leaving
# no visible child returns the anchor to the state that triggered the dispatch
# and the next pass repeats it. These fixtures pin where the refusal starts,
# that it is never silent, and that it defers to the precise refusal.
echo "# under the ceiling nothing is refused"
store "[$(anchor S1 pull_request codex "" polecat/s1 ',"dispatch_count":"4"')]"
oid s1 > "$GH_DIR/head_polecat_s1"
: > "$STUB_ESCALATE_LOG"
out=$(run)
has "$out" "1 reviews dispatched" "the last dispatch under the ceiling is made"
eq "$(meta S1 dispatch_count)" "5" "...and counted"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "...and nothing is escalated below the ceiling"
eq "$(meta S1 'dispatch_backstop.codex')" "<absent>" "...and the anchor carries no hold"

echo "# at the ceiling the dispatch is refused, and said out loud"
store "[$(anchor S2 pull_request codex "" polecat/s2 ',"dispatch_count":"5"')]"
oid s2 > "$GH_DIR/head_polecat_s2"
: > "$STUB_ESCALATE_LOG"; : > "$STUB_GC_LOG"
out=$(run); rc=$?
eq "$rc" 0 "the refusal exits 0 (gate stays armed, merge held)"
has "$out" "0 reviews dispatched" "nothing is dispatched at the ceiling"
has "$out" "1 at the dispatch backstop" "...and the pass reports the hold"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "...no review is poured"
esc=$(cat "$STUB_ESCALATE_LOG")
has "$esc" "--subject S2" "the visit is filed on the anchor"
has "$esc" "--key dispatch-runaway" "...under its own situation key, so repeats dedup"
has "$esc" "GC_MAX_REVIEW_DISPATCHES" "...and names the ceiling's own env var"
has "$esc" "NOT the convergence cap" "...and says which number it is not"
eq "$(meta S2 'dispatch_backstop.codex')" "5@$(oid s2)" "the hold is stamped, keyed to the head it holds"
has "$(notes S2)" "merge stays HELD" "...and the anchor's notes carry the reason, readable from the anchor alone"
eq "$(meta S2 dispatch_count)" "5" "a refused dispatch consumes no count"

echo "# ...once per situation: a repeat pass re-reports without re-filing"
: > "$STUB_ESCALATE_LOG"
out=$(run)
has "$out" "already escalated [dispatch-runaway]" "a second pass names the standing hold"
has "$out" "1 at the dispatch backstop" "...and keeps counting it, so the hold stays visible every pass"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "...and files nothing new"
eq "$(notes S2 | awk '/merge stays HELD/{n++} END{print n+0}')" "1" "...and appends the anchor note exactly once"

echo "# ...and a moved head restates the situation, which says it again"
oid s2b > "$GH_DIR/head_polecat_s2"
: > "$STUB_ESCALATE_LOG"
out=$(run)
has "$out" "5@$(oid s2b)" "the hold names the head it now holds"
has "$(cat "$STUB_ESCALATE_LOG")" "--subject S2" "...and the visit is re-filed against it"
eq "$(meta S2 'dispatch_backstop.codex')" "5@$(oid s2b)" "...and the stamp follows the head"
eq "$(meta S2 dispatch_count)" "5" "...but a moved head buys no dispatch past the ceiling"

echo "# an escalation that does not file leaves the anchor unstamped, and retries"
store "[$(anchor S3 pull_request codex "" polecat/s3 ',"dispatch_count":"6"')]"
oid s3 > "$GH_DIR/head_polecat_s3"
out=$(STUB_ESCALATE_FAIL=1 run)
has "$out" "escalation did not file" "a failed visit is reported"
has "$out" "0 reviews dispatched" "...and the dispatch is still refused"
eq "$(meta S3 'dispatch_backstop.codex')" "<absent>" "...and the anchor is not stamped"
: > "$STUB_ESCALATE_LOG"
out=$(run)
has "$(cat "$STUB_ESCALATE_LOG")" "--subject S3" "the next pass files it"
eq "$(meta S3 'dispatch_backstop.codex')" "6@$(oid s3)" "...and stamps the anchor"

echo "# a hold stamp that does not persist is reported, and appends no note"
store "[$(anchor S10 pull_request codex "" polecat/s10 ',"dispatch_count":"5"')]"
oid s10 > "$GH_DIR/head_polecat_s10"
: > "$STUB_ESCALATE_LOG"
out=$(STUB_DROP_KEYS="S10:dispatch_backstop.codex" run)
has "$(cat "$STUB_ESCALATE_LOG")" "--subject S10" "the visit is filed even when the anchor cannot be stamped"
has "$out" "hold stamp did not persist" "...and the unstamped anchor is reported"
eq "$(notes S10)" "" "...and no note is appended, so repeat passes cannot flood the anchor"

echo "# with no escalator the hold is still stamped on the anchor"
store "[$(anchor S9 pull_request codex "" polecat/s9 ',"dispatch_count":"5"')]"
oid s9 > "$GH_DIR/head_polecat_s9"
chmod -x "$SD/escalate.sh"
out=$(run)
chmod +x "$SD/escalate.sh"
has "$out" "is missing" "a missing escalator is reported"
has "$out" "0 reviews dispatched" "...and the dispatch is still refused"
eq "$(meta S9 'dispatch_backstop.codex')" "5@$(oid s9)" "...and the anchor still carries the hold"
has "$(notes S9)" "NOT escalated" "...whose note says plainly that no visit was filed"

echo "# the round cap does not reach the dispatch path"
store "[$(anchor S4 pull_request codex "" polecat/s4 ',"dispatch_count":"3"')]"
oid s4 > "$GH_DIR/head_polecat_s4"
: > "$STUB_ESCALATE_LOG"
out=$(GC_MAX_REVIEW_ROUNDS=1 run)
has "$out" "1 reviews dispatched" "GC_MAX_REVIEW_ROUNDS bounds signoff.sh's rework rounds, never this dispatch"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "...and escalates nothing"

echo "# the ceiling is configurable, and a garbage value falls back to the default"
store "[$(anchor S5 pull_request codex "" polecat/s5 ',"dispatch_count":"2"')]"
oid s5 > "$GH_DIR/head_polecat_s5"
: > "$STUB_ESCALATE_LOG"
out=$(GC_MAX_REVIEW_DISPATCHES=2 run)
has "$out" "at the dispatch backstop" "GC_MAX_REVIEW_DISPATCHES moves the ceiling"
has "$(cat "$STUB_ESCALATE_LOG")" "--key dispatch-runaway" "...and a lowered ceiling escalates like the default"
store "[$(anchor S6 pull_request codex "" polecat/s6 ',"dispatch_count":"2"')]"
oid s6 > "$GH_DIR/head_polecat_s6"
out=$(GC_MAX_REVIEW_DISPATCHES=abc run)
has "$out" "1 reviews dispatched" "a non-numeric ceiling still dispatches"
hasnt "$out" "integer expression" "...because it fell back to the default, not because the comparison errored"

echo "# the operator hold outranks the ceiling: a held anchor is never paged"
store "[$(anchor S7 pull_request codex "" polecat/s7 ',"dispatch_count":"9","merge_hold":"true"')]"
oid s7 > "$GH_DIR/head_polecat_s7"
: > "$STUB_ESCALATE_LOG"
out=$(run)
has "$out" "merge_hold is set (operator gate); no dispatch" "the hold is the reason, and it is reached first"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "...and nothing is paged as a runaway, however high the tally"
eq "$(meta S7 'dispatch_backstop.codex')" "<absent>" "...and the anchor carries no backstop hold"

echo "# a pour that does not read back burns no count, so the ceiling stays where it is"
store "[$(anchor S8 pull_request codex "" polecat/s8 ',"dispatch_count":"4"')]"
oid s8 > "$GH_DIR/head_polecat_s8"
: > "$STUB_ESCALATE_LOG"
out=$(STUB_DROP_KEYS="new-2:gc.execution_routed_to" run)
has "$out" "dispatch NOT counted" "the unread-back pour is not counted"
eq "$(meta S8 dispatch_count)" "4" "...so the tally does not advance"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "...and a failed pour never pushes an anchor to the ceiling"

echo "# a created-but-unstamped orphan is ADOPTED, never twinned"
store "[$(anchor H1 pull_request codex "" polecat/h1)]"
oid h1 > "$GH_DIR/head_polecat_h1"
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
oid g1 > "$GH_DIR/head_polecat_g1"
out=$(STUB_DROP_KEYS="new-2:gc.execution_routed_to" run); rc=$?
eq "$rc" 0 "a failed pour read-back leaves rc=0 (gate armed, merge held)"
has "$out" "pour did not read back" "the unverified pour is reported"
has "$out" "dispatch NOT counted" "…and the dispatch is not counted"
eq "$(meta G1 dispatch_count)" "<absent>" "an uncounted dispatch does not consume a round"

echo "# …convergence: the next pass sees the tracking convoy's root and does not twin"
printf '%s\n' \
  "$(convoy_row conv-g1)" \
  "$(root_row root-g1 conv-g1)" \
  "$(step_row sg1-a root-g1 load-dispatch closed)" \
  "$(step_row sg1-b root-g1 review in_progress)" \
  "$(step_row sg1-c root-g1 verdict-and-drain open)" \
  "$(step_row sg1-d root-g1 workflow-finalize open)" > "$TMP/conv.json"
store "$(jq -c --slurpfile c "$TMP/conv.json" '. + $c' "$STUB_STORE")"
printf 'conv-g1|tracks|new-2\n' >> "$STUB_DEPS"
: > "$STUB_GC_LOG"
out=$(run)
has "$out" "live poured workflow" "the half-landed pour, its exec stamp dropped but its steps still live, is recognized as in flight"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "…never re-poured"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "STILL exactly one review bead — no twin minted"

echo "# a hard sling failure (rc!=0, nothing written) is not counted…"
store "[$(anchor K1 pull_request codex "" polecat/k1)]"
oid k1 > "$GH_DIR/head_polecat_k1"
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
# workflow is spent no verdict can still be coming; the fixture builders at the
# top of the file distinguish that from a review still legitimately running.
echo "# a spent pour is held one pass, then escalated once"
store "[$(anchor W1 pull_request codex "" polecat/w1),
        $(review_row rev-w1 W1),
        $(convoy_row conv-w1),
        $(root_row root-w1 conv-w1),
        $(spent_steps root-w1 sw1)]"
printf 'conv-w1|tracks|rev-w1\n' >> "$STUB_DEPS"
oid w1 > "$GH_DIR/head_polecat_w1"
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
oid w2 > "$GH_DIR/head_polecat_w2"
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
oid w3 > "$GH_DIR/head_polecat_w3"
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
oid w4 > "$GH_DIR/head_polecat_w4"
: > "$STUB_ESCALATE_LOG"
out=$(run); out="$out$(run)"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "a second live workflow keeps the review in flight"
eq "$(meta rev-w4 wedge_seen_root)" "<absent>" "…and no sighting is recorded"

echo "# an unreadable pour linkage escalates nothing"
store "[$(anchor W5 pull_request codex "" polecat/w5),
        $(review_row rev-w5 W5)]"
oid w5 > "$GH_DIR/head_polecat_w5"
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
oid w6 > "$GH_DIR/head_polecat_w6"
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
oid w7 > "$GH_DIR/head_polecat_w7"
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
oid w8 > "$GH_DIR/head_polecat_w8"
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
oid w9 > "$GH_DIR/head_polecat_w9"
: > "$STUB_ESCALATE_LOG"
out=$(run); out="$out$(run)"
eq "$(cat "$STUB_ESCALATE_LOG")" "" "an agent still holding the bead is finishing the round, not wedged"
eq "$(meta rev-w9 wedge_seen_root)" "<absent>" "…and no sighting is recorded"
hasnt "$out" "WEDGED" "…and it is never called wedged"

# --- the machine axis (lifecycle/lifecycle.toml [machine_axis]) ------------------
# This loop classifies every marker into settled or needs-raising once per pass.
# Recording that answer is what lets the helm board say whether an anchor is
# moving without re-implementing these predicates, and the value is head-pinned
# so a stale verdict can never read as current.
echo "# machine axis: the wedge, the settled gate, and the one being raised"
store "[$(anchor X1 pull_request codex unreviewed polecat/x1 ',"dispatch_count":"3","merge_hold":"signoff_cap","signoff_cap":"codex","gc.routed_to":"human"'),
        $(anchor X2 pull_request codex green polecat/x2),
        $(anchor X3 pull_request codex fixing polecat/x3),
        $(anchor X4 pre_open_gate codex unreviewed polecat/x4 ',"merge_hold":"signoff_cap","signoff_cap":"codex","gc.routed_to":"human"')]"
oid x1 > "$GH_DIR/head_polecat_x1"
oid x2 > "$GH_DIR/head_polecat_x2"
oid x3 > "$GH_DIR/head_polecat_x3"
oid x4 > "$GH_DIR/head_polecat_x4"
out=$(run); rc=$?
eq "$rc" 0 "the recording pass exits 0"
# The commonest wedge: the convergence cap parked the anchor under merge_hold
# and routed it to a person. No automated actor lifts that, and no commit does.
eq "$(pinned X1)" "wedged-exception@$(oid x1)" "the cap's park records the wedge, with its shape named"
eq "$(pinned X2)" "settled@$(oid x2)" "every gate green records settled"
eq "$(pinned X3)" "progressing@$(oid x3)" "a lane short of green records progressing"
# Most wedged anchors have no PR at all, so a key written only for open PRs
# would miss the majority of the condition.
eq "$(pinned X4)" "wedged-exception@$(oid x4)" "a pre_open_gate anchor is recorded the same way"
case "$(machine X1)" in
  *@*@20[0-9][0-9]-*Z) ok "the recorded verdict dates its own turn" ;;
  *) bad "no @<since> component: '$(machine X1)'" ;;
esac

echo "# …and the clock holds across a second pass at an unchanged head"
was="$(machine X1)"
: > "$STUB_GC_LOG"
run >/dev/null
eq "$(machine X1)" "$was" "a re-derived verdict at the same head keeps its instant (the reconcile cadence runs every few minutes)"
# The instant surviving is not enough: this pass must not have paid for it. Every
# anchor already carrying its verdict costs a `gc bd show` if the writer is asked
# at all, and that read is the most expensive call the arm makes.
hasnt "$(cat "$STUB_GC_LOG")" "bd update X1" "…re-recording an unchanged verdict issues no update"
hasnt "$(cat "$STUB_GC_LOG")" "bd show X1" "…and does not even re-read the anchor to discover that"

echo "# recording a verdict moves no route"
# The stamp rides a lifecycle self-transition, and a detached state's default is
# to clear the route. An observation must not retract a routing decision it
# never looked at, so the anchor's own route rides back with it.
eq "$(meta X1 'gc.routed_to')" "human" "a parked anchor keeps the route the cap gave it"
store "[$(anchor X6 pull_request codex green polecat/x6 ',"gc.routed_to":"rig/gc-toolkit.polecat"')]"
oid x6 > "$GH_DIR/head_polecat_x6"
run >/dev/null
eq "$(pinned X6)" "settled@$(oid x6)" "the verdict is recorded"
eq "$(meta X6 'gc.routed_to')" "rig/gc-toolkit.polecat" "…and the route is left exactly as it was found"

echo "# an unreadable head is not evidence, so nothing is recorded"
store "[$(anchor X5 pull_request codex green polecat/x5)]"
out=$(run); rc=$?
eq "$rc" 0 "the no-head pass exits 0"
eq "$(machine X5)" "<absent>" "a verdict pinned to no head is never written"

echo "# the skip is the exact verdict at the exact head, and nothing wider"
# A verdict the head has moved past is a different verdict, and a value not yet
# in the dated shape still owes the instant lifecycle.sh appends.
store "[$(anchor X7 pull_request codex green polecat/x7 ',"pr.machine":"settled@'"$(oid stale7)"'@2026-08-28T04:05:06Z"')]"
oid x7 > "$GH_DIR/head_polecat_x7"
: > "$STUB_GC_LOG"
run >/dev/null
has "$(cat "$STUB_GC_LOG")" "bd update X7" "a verdict pinned to a head that has moved is rewritten"
eq "$(pinned X7)" "settled@$(oid x7)" "…at the head the branch now carries"
store "[$(anchor X8 pull_request codex green polecat/x8 ',"pr.machine":"settled@'"$(oid x8)"'"')]"
oid x8 > "$GH_DIR/head_polecat_x8"
: > "$STUB_GC_LOG"
run >/dev/null
has "$(cat "$STUB_GC_LOG")" "bd update X8" "an undated legacy verdict is rewritten, not skipped"
case "$(machine X8)" in
  "settled@$(oid x8)@"?*) ok "…and gains its instant" ;;
  *) bad "the legacy value was left undated: '$(machine X8)'" ;;
esac
# Anything short of the full dated shape is one lifecycle.sh restamps, so the
# skip must not read it as recorded. Left alone it never gets repaired: the board
# cannot date the row, and every later pass agrees the verdict is already there.
# An unpinned value is the one shape that carries no head at all, which is what
# makes it the shape a prefix comparison alone would accept.
for bad_shape in "settled" "settled@OID@" "settled@OID@2026-08-28T04:05:06Z@x"; do
  store "[$(anchor X9 pull_request codex green polecat/x9 ",\"pr.machine\":\"${bad_shape//OID/$(oid x9)}\"")]"
  oid x9 > "$GH_DIR/head_polecat_x9"
  : > "$STUB_GC_LOG"
  run >/dev/null
  has "$(cat "$STUB_GC_LOG")" "bd update X9" "a verdict whose instant is malformed ('$bad_shape') is rewritten"
  case "$(machine X9)" in
    "settled@$(oid x9)@"20[0-9][0-9]-*Z) ok "…and comes back dateable" ;;
    *) bad "left malformed: '$(machine X9)'" ;;
  esac
done

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
