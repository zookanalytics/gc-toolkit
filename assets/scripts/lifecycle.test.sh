#!/usr/bin/env bash
# Hermetic test for lifecycle.sh, the plain write of a bead's merge_result.
# Covers: --expect; the ONE atomic `gc bd update` carrying every field; bd
# refusal (exit 1); a write that names no route leaving the route as it is; the
# refusal of a route that is not rig-qualified, `human` included; the clear of
# the executor identity with the assignee; --set-dated's compare-and-preserve
# rule for the @<since> component; the --takeaway writer, capped as gc-helm.sh
# caps it; --keep-route, the write that records on a bead and writes no route;
# a landing's work record and its clear of the live objections; and the
# refusal when no gctk binary resolves.
#
# ONE IMPLEMENTATION, REACHED THROUGH THE SCRIPT. lifecycle.sh execs
# `gctk lifecycle` (services/gctk) and has no other implementation. The suite
# builds it from this checkout and drives every assertion through lifecycle.sh,
# so it is the writer's acceptance bar and also proves the exec wiring.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/lifecycle.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lifecycle-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
harness_init
[ -x "$SUT" ] || chmod +x "$SUT"
# harness_init has recorded why there is no binary. Every assertion below goes
# through it, so running them would only repeat that one failure.
if [ -z "$GCTK_BUILT" ]; then
    echo "passed: $PASS  failed: $FAIL"
    exit 1
fi

# --- transition: happy path is ONE update carrying everything -------------------
echo "# transition happy path"
store '[{"id":"a-1","status":"open","assignee":"rig/refinery","notes":"","metadata":{"merge_result":"blocked","rejection_reason":"old"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition a-1 --to merged --expect blocked --close \
  --set merged_sha=abc123 --unset rejection_reason \
  --append-notes "Merged to main at abc123" --json 2>&1)"; rc=$?
eq "$rc" 0 "legal transition exits 0"
eq "$(meta a-1 merge_result)" "merged" "merge_result written"
eq "$(meta a-1 merged_sha)" "abc123" "--set landed"
eq "$(meta a-1 rejection_reason)" "<absent>" "--unset landed"
eq "$(bstatus a-1)" "closed" "--close landed"
has "$(notes a-1)" "Merged to main at abc123" "--append-notes landed"
updates=$(grep -c '^bd update' "$STUB_GC_LOG" || true)
eq "$updates" "1" "exactly ONE gc bd update carried the whole transition"
has "$(grep '^bd update' "$STUB_GC_LOG")" "--status=closed" "the close rides in the same update"
# …and the close is reached by `update --status=closed`, never by the `close`
# verb. bd's ownership check lives on `bd close`: it compares the actor to the
# assignee and refuses a bead held by another principal, pointing at --force.
# a-1 above is assigned to "rig/refinery", which is the shape of every anchor
# this writer closes — a bead someone handed the refinery. The refusal is
# per-anchor and permanent, so a retry meets it unchanged on every later pass;
# the update form carries no such check, which is what lets one atomic write
# both record and close.
#
# The assertion is on the emitted command because no stub can answer it. The
# shared harness models no acting identity, so its `bd close` would succeed
# exactly as its `bd update` does; teaching it to refuse would prove nothing
# either, since the property being pinned is that the call is never issued.
# The --status=closed assertion above is this one's mirror: together they say
# the close both happened and happened by the verb that carries no such check.
hasnt "$(cat "$STUB_GC_LOG")" "bd close" "the close never uses the \`bd close\` verb, whose ownership check refuses a bead assigned to another principal"
has "$out" '"ok":true' "--json reports the transition"
has "$out" '"from":"blocked"' "--json names the from state"

# --- a closed-state transition sheds every live objection ------------------------
# A merged (closed) bead carries no live objection: a rejection_reason or a
# blocked_reason still on it contradicts the record. The close clears both at
# this one writer, so a caller that lists NEITHER still lands a clean terminal
# record — the divergence the per-caller --unset enumeration used to allow.
echo "# transition closed-state sheds live objections"
store '[{"id":"obj-1","status":"open","assignee":"rig/refinery","notes":"","metadata":{"merge_result":"blocked","rejection_reason":"bounced for X","blocked_reason":"merge_hold: do not merge until Y"}}]'
out="$("$SUT" transition obj-1 --to merged --expect blocked --close \
  --set merged_sha=def456 2>&1)"; rc=$?
eq "$rc" 0 "merged-close exits 0 though neither reason is listed"
eq "$(meta obj-1 merge_result)" "merged" "merge_result written"
eq "$(meta obj-1 rejection_reason)" "<absent>" "rejection_reason cleared by the close, unlisted"
eq "$(meta obj-1 blocked_reason)" "<absent>" "blocked_reason cleared by the close, unlisted"
eq "$(bstatus obj-1)" "closed" "--close landed"

# The clear is scoped to the terminal land: a non-closed transition keeps a
# pre-existing blocked_reason (the mirror of the rejection_reason control in the
# unanchored case below).
store '[{"id":"obj-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","blocked_reason":"merge_hold: still blocked"}}]'
out="$("$SUT" transition obj-2 --to unanchored --route rig/polecat 2>&1)"; rc=$?
eq "$rc" 0 "non-closed transition exits 0"
eq "$(meta obj-2 blocked_reason)" "merge_hold: still blocked" "blocked_reason survives a non-closed transition"

# --- --set-dated: the @<since> compare-and-preserve rule ------------------------
# The operator's queue is ordered by how long a row has been owed, so the instant
# a turn began has to survive every pass that re-reaches the same verdict at the
# same head. Getting this wrong is not a visible failure: the row keeps rendering,
# it just reports a three-day wait as new and sorts the most neglected row last.
echo "# --set-dated"
OID="1111111111111111111111111111111111111111"
OID2="2222222222222222222222222222222222222222"

store '[{"id":"d-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
out="$("$SUT" transition d-1 --to blocked --set-dated "pr.machine=blocked@$OID" 2>&1)"; rc=$?
eq "$rc" 0 "a first dated write exits 0"
got="$(meta d-1 pr.machine)"
eq "${got%@*}" "blocked@$OID" "the value and oid are written as given"
case "$got" in
  *@*@20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) ok "…and lifecycle.sh appended an RFC 3339 UTC instant" ;;
  *) bad "no instant appended: '$got'" ;;
esac

# Preserve: the reconcile cadence re-reaches the same verdict at the same head
# every few minutes, which is the case a naive clock restarts.
store '[{"id":"d-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","pr.machine":"blocked@'"$OID"'@2026-08-28T04:05:06Z"}}]'
"$SUT" transition d-2 --to blocked --set-dated "pr.machine=blocked@$OID" >/dev/null 2>&1
eq "$(meta d-2 pr.machine)" "blocked@$OID@2026-08-28T04:05:06Z"   "an unchanged value at an unchanged head keeps its instant"

# Restamp on a changed VALUE: a new verdict is a new turn.
store '[{"id":"d-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","pr.machine":"progressing@'"$OID"'@2026-08-28T04:05:06Z"}}]'
"$SUT" transition d-3 --to blocked --set-dated "pr.machine=blocked@$OID" >/dev/null 2>&1
got="$(meta d-3 pr.machine)"
eq "${got%@*}" "blocked@$OID" "a changed value is written"
case "$got" in
  *@2026-08-28T04:05:06Z) bad "a changed value kept the old instant: '$got'" ;;
  *) ok "…and starts a fresh clock" ;;
esac

# Restamp on a moved HEAD: a verdict is pinned to the head it judged, so the old
# instant dates a state that no longer holds.
store '[{"id":"d-4","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","pr.machine":"blocked@'"$OID"'@2026-08-28T04:05:06Z"}}]'
"$SUT" transition d-4 --to blocked --set-dated "pr.machine=blocked@$OID2" >/dev/null 2>&1
got="$(meta d-4 pr.machine)"
eq "${got%@*}" "blocked@$OID2" "a moved head is written"
case "$got" in
  *@2026-08-28T04:05:06Z) bad "a moved head kept the old instant: '$got'" ;;
  *) ok "…and starts a fresh clock" ;;
esac

# A value still in the bare <value>@<oid> shape has no instant to keep.
store '[{"id":"d-5","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","pr.machine":"settled@'"$OID"'"}}]'
"$SUT" transition d-5 --to blocked --set-dated "pr.machine=settled@$OID" >/dev/null 2>&1
got="$(meta d-5 pr.machine)"
case "$got" in
  "settled@$OID@"?*) ok "an undated legacy value gains an instant" ;;
  *) bad "the legacy value was left undated: '$got'" ;;
esac

# One atomic write, exactly as an ordinary --set: the dated key rides the same
# update rather than adding a second one.
store '[{"id":"d-6","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
: > "$STUB_GC_LOG"
"$SUT" transition d-6 --to blocked --set-dated "pr.machine=settled@$OID" --set check_set=correctness >/dev/null 2>&1
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "a dated key rides the ONE atomic update"

# Shape refusals: the writer supplies value and oid, this script supplies the
# instant, and a malformed argument makes the preserve comparison undecidable.
store '[{"id":"d-7","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
out="$("$SUT" transition d-7 --to blocked --set-dated "pr.machine=settled" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated with no oid is refused"
has "$out" "<value>@<oid>" "the refusal names the shape"
out="$("$SUT" transition d-7 --to blocked --set-dated "pr.machine=settled@$OID@2026-01-01T00:00:00Z" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated carrying its own instant is refused"
out="$("$SUT" transition d-7 --to blocked --set-dated "pr.machine" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated with no '=' is refused"
out="$("$SUT" transition d-7 --to blocked --set-dated "merge_result=x@$OID" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated merge_result is refused (owned by --to)"
out="$("$SUT" transition d-7 --to blocked --set-dated "gc.routed_to=x@$OID" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated gc.routed_to is refused (owned by --route)"
eq "$(meta d-7 pr.machine)" "<absent>" "no refusal wrote anything"

# --- a transition that changes nothing performs no write -----------------------
# The observer arms re-reach the same verdict on most anchors of every pass, and
# each re-assertion cost an update, a store subprocess per anchor, on a cadence
# whose budget is store subprocesses. What must not
# change with them gone: the exit code, the report, and the stored value.
echo "# idle transitions"
store '[{"id":"n-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","pr.machine":"settled@'"$OID"'@2026-08-28T04:05:06Z","gc.routed_to":"rig/pool"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition n-1 --to blocked --expect blocked \
  --route rig/pool --set-dated "pr.machine=settled@$OID" 2>&1)"; rc=$?
eq "$rc" 0 "a re-assertion of the state already on the bead exits 0"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "…and issues NO gc bd update"
has "$out" "n-1 blocked -> blocked" "…and still reports the state"
eq "$(meta n-1 pr.machine)" "settled@$OID@2026-08-28T04:05:06Z" "…leaving the instant it would have preserved"
eq "$(meta n-1 gc.routed_to)" "rig/pool" "…and the route it carried back"
out="$("$SUT" transition n-1 --to blocked --route rig/pool \
  --set-dated "pr.machine=settled@$OID" --json 2>&1)"
eq "$(printf '%s' "$out" | jq -r '.ok')" "true" "--json still reports ok"
eq "$(printf '%s' "$out" | jq -r '.from + ">" + .to')" "blocked>blocked" "…with the same from/to"

# Each field the comparison covers, mutated on its own: every one of these must
# still write. A skip that fires on a real change is the failure this optimization
# could introduce, and it is silent — the caller is told the transition landed.
writes_when() { # <label> <bead-json> <args...>
  local label="$1" bead="$2"; shift 2
  store "[$bead]"
  : > "$STUB_GC_LOG"
  "$SUT" transition "$@" >/dev/null 2>&1
  eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "$label"
}
# BASE must be idle on its own: re-asserted unchanged, it writes nothing, so
# each case below writes only for its own field.
BASE='"id":"n-2","status":"open","assignee":"","notes":""'
store "[{$BASE,\"metadata\":{\"merge_result\":\"blocked\"}}]"
: > "$STUB_GC_LOG"
"$SUT" transition n-2 --to blocked >/dev/null 2>&1
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "BASE re-asserted unchanged writes nothing"
writes_when "a moved head writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"blocked\",\"pr.machine\":\"settled@$OID@2026-08-28T04:05:06Z\"}}" \
  n-2 --to blocked --set-dated "pr.machine=settled@$OID2"
writes_when "a changed verdict writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"blocked\",\"pr.machine\":\"settled@$OID@2026-08-28T04:05:06Z\"}}" \
  n-2 --to blocked --set-dated "pr.machine=blocked@$OID"
writes_when "a changed --set writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"blocked\",\"check_set\":\"correctness\"}}" \
  n-2 --to blocked --set check_set=correctness,ci
writes_when "a --set of an absent key writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"blocked\"}}" \
  n-2 --to blocked --set check_set=correctness
writes_when "a --unset of a present key writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"blocked\",\"rejection_reason\":\"old\"}}" \
  n-2 --to blocked --unset rejection_reason
writes_when "a changed --route writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"blocked\",\"gc.routed_to\":\"rig/pool\"}}" \
  n-2 --to blocked --route rig/other
writes_when "a moved state writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"refused_false_completion\"}}" \
  n-2 --to blocked
# Fields the comparison does NOT cover: each writes unconditionally, because a
# skip would drop something no comparison against the current bead can see.
writes_when "--append-notes always writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"blocked\"}}" \
  n-2 --to blocked --append-notes "another line"
writes_when "--takeaway always writes (it stamps a fresh instant)" \
  '{"id":"n-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","gc.takeaway":"same text","gc.takeaway_at":"2026-08-28T04:05:06Z","gc.takeaway_by":"lifecycle"}}' \
  n-2 --to blocked --takeaway "same text"
# The assignee the flag names does not change, and only the flag can force the
# write.
writes_when "--assignee always writes" \
  '{"id":"n-2","status":"open","assignee":"rig/refinery","notes":"","metadata":{"merge_result":"blocked"}}' \
  n-2 --to blocked --assignee rig/refinery
store '[{"id":"n-3","status":"closed","assignee":"","notes":"","metadata":{"merge_result":"merged","merged_sha":"abc123"}}]'
: > "$STUB_GC_LOG"
"$SUT" transition n-3 --to merged --close --set merged_sha=abc123 >/dev/null 2>&1
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "--close always writes"

# The unanchored self-edge: merge_result is already absent, so the --unset the
# skip stands in for genuinely has nothing to do.
store '[{"id":"n-4","status":"open","assignee":"","notes":"","metadata":{}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition n-4 --to unanchored 2>&1)"; rc=$?
eq "$rc" 0 "an unanchored self-edge exits 0"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "…and writes nothing"

# --expect is not what is skipped: an idle-looking call whose --expect does not
# hold is still refused.
store '[{"id":"n-5","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition n-5 --to blocked --expect refused_false_completion 2>&1)"; rc=$?
eq "$rc" 1 "an --expect mismatch is still refused ahead of the skip"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "…and wrote nothing"

# --- --expect mismatch / refusal -------------------------------------------------
echo "# refusals"
store '[{"id":"a-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"refused_false_completion"}}]'
out="$("$SUT" transition a-3 --to blocked --expect blocked 2>&1)"; rc=$?
eq "$rc" 1 "--expect mismatch exits 1"
eq "$(meta a-3 merge_result)" "refused_false_completion" "an --expect mismatch writes nothing"

out="$(STUB_UPDATE_FAIL="a-3" "$SUT" transition a-3 --to blocked 2>&1)"; rc=$?
eq "$rc" 1 "a bd refusal exits 1"
has "$out" "refused by bd" "the refusal is named"

out="$("$SUT" transition a-3 --to blocked --set merge_result=x 2>&1)"; rc=$?
eq "$rc" 1 "--set merge_result is refused (owned by --to)"
out="$("$SUT" transition a-3 --to blocked --set gc.routed_to=x 2>&1)"; rc=$?
eq "$rc" 1 "--set gc.routed_to is refused (owned by --route)"

# --- a write that names no route leaves the route as it is ----------------------
# A write that parks a bead for a person writes no route. The human gate its
# caller files beside it is what holds the bead, whatever route it carries.
echo "# a write names no route unless asked"
store '[{"id":"a-6","status":"open","assignee":"rig/refinery","notes":"","metadata":{"merge_result":"blocked"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition a-6 --to refused_false_completion --assignee "" \
  --set blocked_reason="PR#7 closed out-of-band" \
  --takeaway "PR#7 was closed without merging — rework it or close this bead" 2>&1)"; rc=$?
eq "$rc" 0 "transition to refused_false_completion exits 0"
eq "$(meta a-6 'gc.routed_to')" "<absent>" "refused_false_completion writes no route"
hasnt "$(grep '^bd update' "$STUB_GC_LOG")" "gc.routed_to" "…since the update names no route"
eq "$(bassignee a-6)" "" "--assignee '' cleared the assignee"
eq "$(meta a-6 'gc.takeaway')" "PR#7 was closed without merging — rework it or close this bead" \
  "the park names what it wants"
eq "$(meta a-6 'gc.takeaway_by')" "lifecycle" "the takeaway names its writer"
case "$(meta a-6 'gc.takeaway_at')" in
  ????-??-??T??:??:??Z) ok "the takeaway is dated" ;;
  *) bad "the takeaway carries no gc.takeaway_at" ;;
esac
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "state + clear + reason + takeaway ride in ONE update"
eq "$(meta a-6 'gc.takeaway_settled')" "" "the park's headline carries its own disposition, not a settled one"

# The entry keeps whatever route the bead carries: a transition routes no work,
# and the gate holds the bead whatever its route.
store '[{"id":"a-6b","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","gc.routed_to":"rig/pool"}}]'
out="$("$SUT" transition a-6b --to blocked --expect blocked --takeaway "PR#7 sits on another base" 2>&1)"; rc=$?
eq "$rc" 0 "transition to blocked exits 0"
eq "$(meta a-6b 'gc.routed_to')" "rig/pool" "…and the bead keeps the route it carries"

store '[{"id":"a-8","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","gc.takeaway_settled":"1"}}]'
out="$("$SUT" transition a-8 --to refused_false_completion --takeaway "needs a ruling on the base branch" 2>&1)"; rc=$?
eq "$rc" 0 "a takeaway over an inherited settled-key exits 0"
eq "$(meta a-8 'gc.takeaway_settled')" "" "…and clears it, leaving the park's own disposition on the bead"

# --- unassigning takes the executor identity with it ----------------------------
# gc.session_id and gc.session_name name the session that claimed the bead, so
# they are the third field of the same let-go as the route and the assignee. A
# transition can hand a bead back to the pool with --assignee "", and a stamp
# that survives it is
# doctor/executor-identity-residue's report the moment the bead next carries a
# route, and the runtime's stale orphan-recovery pin. So the clear rides the same
# atomic update as the unassign.
echo "# unassigning clears the executor identity"
store '[{"id":"x-1","status":"open","assignee":"rig/gc-toolkit.polecat-1","notes":"","metadata":{"merge_result":"blocked","gc.session_id":"hq-dead","gc.session_name":"rig--rig__polecat-1-pool","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition x-1 --to unanchored --assignee "" --route "" --unset gc.execution_routed_to --set rejection_reason="base moved; resume by merge" 2>&1)"; rc=$?
eq "$rc" 0 "the rejection repool's shape exits 0"
eq "$(meta x-1 'gc.execution_routed_to')" "<absent>" "the repool's release clears the last pour's stamp"
eq "$(bassignee x-1)" "" "the repool cleared the assignee"
eq "$(meta x-1 'gc.session_id')" "<absent>" "gc.session_id went with the assignee"
eq "$(meta x-1 'gc.session_name')" "<absent>" "gc.session_name went with the assignee"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "the identity clear rides the ONE atomic update"
has "$(grep '^bd update' "$STUB_GC_LOG")" "--unset-metadata gc.session_id" "gc.session_id is unset in that call"
has "$(grep '^bd update' "$STUB_GC_LOG")" "--unset-metadata gc.session_name" "gc.session_name is unset in that call"

# The pins are the assignee's: a live claim keeps them. On an in_progress bead
# the assignee clear is refused (bd's anti-steal guard), so no --assignee reaches
# bd, the arm never fires, and the identity stays with the session that holds it.
store '[{"id":"x-3","status":"in_progress","assignee":"rig/gc-toolkit.polecat-1","notes":"","metadata":{"merge_result":"blocked","gc.session_id":"hq-live","gc.session_name":"rig--rig__polecat-1-pool"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition x-3 --to blocked --expect blocked --route "" --set pr_number=9 2>&1)"; rc=$?
eq "$rc" 0 "a transition on an in_progress anchor still lands"
eq "$(meta x-3 'gc.session_id')" "hq-live" "a live claim keeps gc.session_id"
eq "$(meta x-3 'gc.session_name')" "rig--rig__polecat-1-pool" "a live claim keeps gc.session_name"
hasnt "$(grep '^bd update' "$STUB_GC_LOG")" "--unset-metadata gc.session_id" "no identity clear when the assignee is not cleared"

# An explicit new assignee wins over the clear, and its identity is not stripped:
# the field is the assignee's, and this names one.
store '[{"id":"x-4","status":"open","assignee":"rig/gc-toolkit.refinery","notes":"","metadata":{"merge_result":"refused_false_completion","gc.session_id":"hq-keep","gc.session_name":"rig--rig__polecat-3-pool"}}]'
: > "$STUB_GC_LOG"
"$SUT" transition x-4 --to blocked --assignee "rig/mechanik" >/dev/null 2>&1
eq "$(bassignee x-4)" "rig/mechanik" "an explicit --assignee is written as given"
eq "$(meta x-4 'gc.session_id')" "hq-keep" "a named assignee keeps gc.session_id"
hasnt "$(grep '^bd update' "$STUB_GC_LOG")" "--unset-metadata gc.session_id" "no identity clear when an assignee is named"

store '[{"id":"a-7","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
"$SUT" transition a-7 --to blocked --route rig/mechanik >/dev/null 2>&1
eq "$(meta a-7 'gc.routed_to')" "rig/mechanik" "an explicit --route is written as given"

# --- an empty --route clears the route ---------------------------------------------
echo "# an empty route clears the route"
store '[{"id":"a-7b","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","gc.routed_to":"rig/pool"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition a-7b --to refused_false_completion --route "" 2>&1)"; rc=$?
eq "$rc" 0 "an EMPTY --route exits 0"
eq "$(meta a-7b merge_result)" "refused_false_completion" "…and enters the state"
eq "$(meta a-7b 'gc.routed_to')" "" "…with the route cleared"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "…in the transition's one update"

# --- a route names a pool by its qualified address --------------------------------
# gc.routed_to is matched as an exact string by every pool claim, so a bare
# token like "pool" reaches no pool: the bead stays ready and is offered to
# nobody. This one writer, shared by every --route caller, refuses it before the
# write rather than stranding the bead ready-but-unclaimable.
echo "# a route is rig-qualified"
store '[{"id":"r-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition r-1 --to unanchored --route pool 2>&1)"; rc=$?
eq "$rc" 1 "a bare --route that names no pool exits 1"
has "$out" "not rig-qualified" "the refusal says the route is unqualified"
has "$out" "exact string" "…and why a bare name reaches nobody"
eq "$(meta r-1 merge_result)" "blocked" "the refused transition wrote nothing"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "and never reached bd"

# A rig-qualified target is exactly what a pool claims, so it passes and is
# stamped verbatim.
store '[{"id":"r-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
out="$("$SUT" transition r-2 --to unanchored --route gc-toolkit/gc-toolkit.polecat 2>&1)"; rc=$?
eq "$rc" 0 "a <rig>/<agent> route is accepted"
eq "$(meta r-2 'gc.routed_to')" "gc-toolkit/gc-toolkit.polecat" "…and stamped verbatim"

# `human` is a bare name like any other. A person's wait is the human gate filed
# on the bead, so no transition parks a bead on a route, whatever the state.
store '[{"id":"r-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition r-3 --to refused_false_completion --route human --takeaway "PR#7 was closed without merging" 2>&1)"; rc=$?
eq "$rc" 1 "--route human exits 1"
has "$out" "not rig-qualified" "…refused as a bare name"
has "$out" "human gate" "…and the refusal names the gate that parks a bead for a person"
out="$("$SUT" transition r-3 --to blocked --expect blocked --route human --takeaway "parked" 2>&1)"; rc=$?
eq "$rc" 1 "--route human on a re-record exits 1 too"
eq "$(meta r-3 merge_result)" "blocked" "the refused transitions wrote nothing"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "and never reached bd"

# --- --takeaway writes the board's headline --------------------------------------
# The helm board spends gc.takeaway as a row's NEEDS sentence. A write that
# parks a bead needs none, since the gate its caller files says what is asked.
# A caller that passes --takeaway gets the headline in the transition's one
# update, capped, and refused when it says nothing.
echo "# --takeaway"
store '[{"id":"p-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition p-1 --to refused_false_completion --set blocked_reason="PR#7 closed out-of-band" 2>&1)"; rc=$?
eq "$rc" 0 "a write with no takeaway exits 0"
eq "$(meta p-1 merge_result)" "refused_false_completion" "…and enters the state"
eq "$(meta p-1 'gc.takeaway')" "<absent>" "…writing no headline"
eq "$(meta p-1 'gc.routed_to')" "<absent>" "…and no route"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "…in one update"

# The takeaway triple is this flag's to write.
store '[{"id":"p-6","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
out="$("$SUT" transition p-6 --to refused_false_completion --set gc.takeaway="via --set" 2>&1)"; rc=$?
eq "$rc" 1 "--set gc.takeaway is refused (owned by --takeaway)"
has "$out" "--takeaway" "the refusal names the owning flag"

# Over the cap the verb REJECTS rather than truncating: only the author knows
# which clause is the headline, and a truncated one loses it silently. The cap
# is the one gc-helm.sh, the other writer of the cell, carries as TAKEAWAY_MAX.
eq "$(sed -n 's/^TAKEAWAY_MAX=\([0-9]*\).*/\1/p' "$HERE/gc-helm.sh" | head -1)" "140" "gc-helm.sh caps a takeaway at the same 140 codepoints"
store '[{"id":"p-7","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
LONG=$(printf 'x%.0s' $(seq 141))
: > "$STUB_GC_LOG"
out="$("$SUT" transition p-7 --to refused_false_completion --takeaway "$LONG" 2>&1)"; rc=$?
eq "$rc" 1 "a takeaway over the cap exits 1"
has "$out" "141 chars" "the refusal reports the measured length"
has "$out" "the cap is 140" "…and the cap"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "and nothing was written"

store '[{"id":"p-8","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
out="$("$SUT" transition p-8 --to refused_false_completion --takeaway "$(printf 'x%.0s' $(seq 140))" 2>&1)"; rc=$?
eq "$rc" 0 "a takeaway AT the cap is accepted"

# An EMPTY takeaway is not one. Normalization can leave nothing behind, and
# writing that would overwrite the headline a bead carries with nothing, under
# a fresh date and author.
store '[{"id":"p-9","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition p-9 --to refused_false_completion --takeaway "" 2>&1)"; rc=$?
eq "$rc" 1 "an empty --takeaway exits 1"
has "$out" "tells the operator nothing" "the refusal says what an empty headline would show"
eq "$(meta p-9 'gc.takeaway')" "<absent>" "no empty takeaway is written"
eq "$(meta p-9 merge_result)" "blocked" "the refused transition wrote nothing"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "and never reached bd"

store '[{"id":"p-10","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition p-10 --to refused_false_completion --takeaway "   " 2>&1)"; rc=$?
eq "$rc" 1 "a whitespace-only --takeaway exits 1"
has "$out" "tells the operator nothing" "…with the same refusal"
eq "$(meta p-10 'gc.takeaway')" "<absent>" "…and nothing is written"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "…and nothing reaches bd"

# The refusal belongs to the flag, whatever the route.
store '[{"id":"p-11","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
out="$("$SUT" transition p-11 --to blocked --route rig/mechanik --takeaway " " 2>&1)"; rc=$?
eq "$rc" 1 "an empty --takeaway is refused on a pool route too"

# --- a record on an anchor staying in its state moves no route -------------------
# pr-facts.sh records the rank an anchor's PR-finishing work settled at with a
# self-transition, and that write must move no route. So --keep-route writes no
# route at all.
echo "# --keep-route records without routing"
store '[{"id":"k-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"refused_false_completion","gc.routed_to":""}},
        {"id":"k-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"refused_false_completion","gc.routed_to":"","gc.takeaway":"PR#7 was closed without merging"}},
        {"id":"k-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","gc.routed_to":"rig/gc-toolkit.mechanik"}},
        {"id":"k-4","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","gc.routed_to":"rig/gc-toolkit.polecat"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition k-1 --to refused_false_completion --expect refused_false_completion --keep-route --set pr_finishing_settled=unapproved 2>&1)"; rc=$?
eq "$rc" 0 "a self-transition with no route and no takeaway records under --keep-route"
eq "$(meta k-1 pr_finishing_settled)|$(meta k-1 'gc.routed_to')" "unapproved|" "…and the route stays empty"
hasnt "$(grep '^bd update k-1' "$STUB_GC_LOG")" "gc.routed_to" "…since the write names no route"
"$SUT" transition k-2 --to refused_false_completion --expect refused_false_completion --keep-route --set pr_finishing_settled=unapproved >/dev/null 2>&1
eq "$(meta k-2 pr_finishing_settled)|$(meta k-2 'gc.routed_to')" "unapproved|" "…and one that carries a takeaway keeps its empty route"
"$SUT" transition k-3 --to blocked --expect blocked --keep-route --set pr_finishing_settled=unapproved >/dev/null 2>&1
eq "$(meta k-3 'gc.routed_to')" "rig/gc-toolkit.mechanik" "…a route a person gave the bead is kept"
"$SUT" transition k-4 --to blocked --expect blocked --keep-route --set pr_finishing_settled=approved >/dev/null 2>&1
eq "$(meta k-4 pr_finishing_settled)|$(meta k-4 'gc.routed_to')" "approved|rig/gc-toolkit.polecat" "…and so is a pool's"
store '[{"id":"k-6","status":"open","assignee":"","notes":"","metadata":{"merge_result":"refused_false_completion","gc.routed_to":""}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition k-6 --to refused_false_completion --expect refused_false_completion --keep-route --route rig/gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 1 "--keep-route with --route exits 1"
has "$out" "opposite things" "…saying the two contradict"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "…and the refusal does not reach bd"

# --- rejection to unanchored ------------------------------------------------------
echo "# unanchored"
store '[{"id":"a-8","status":"open","assignee":"","notes":"","metadata":{"merge_result":"refused_false_completion","branch":"polecat/x"}}]'
out="$("$SUT" transition a-8 --to unanchored --set rejection_reason="scope wrong" --route rig/polecat 2>&1)"; rc=$?
eq "$rc" 0 "rejection to unanchored exits 0"
eq "$(meta a-8 merge_result)" "<absent>" "unanchored unsets merge_result"
eq "$(meta a-8 rejection_reason)" "scope wrong" "the rejection reason rides along"

# --- self-edge is an idempotent re-record ----------------------------------------
store '[{"id":"a-9","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked"}}]'
out="$("$SUT" transition a-9 --to blocked --set pr_number=12 2>&1)"; rc=$?
eq "$rc" 0 "a re-record of the value a bead carries lands"
eq "$(meta a-9 pr_number)" "12" "and carries its fields"

# --- merged writes the work record from the landing it records -------------------
# The runtime's work-record gate reads gc.work_outcome, gc.work_commit and
# gc.work_branch on the close. A merged transition already holds all three
# facts, so it writes them in the same atomic update: shipped, the merge commit,
# and the branch that commit landed on.
echo "# merged writes the work record"
SHA_A=0123456789abcdef0123456789abcdef01234567
store '[{"id":"w-1","status":"open","assignee":"rig/refinery","notes":"","metadata":{"merge_result":"blocked","merged_target":"main","gc.work_branch":"polecat/w-1"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition w-1 --to merged --expect blocked --close --set merged_sha=$SHA_A 2>&1)"; rc=$?
eq "$rc" 0 "a merged close exits 0"
eq "$(meta w-1 gc.work_outcome)" "shipped" "gc.work_outcome is shipped"
eq "$(meta w-1 gc.work_commit)" "$SHA_A" "gc.work_commit is the merge commit"
eq "$(meta w-1 gc.work_branch)" "main" "gc.work_branch is merged_target, the branch the merge commit is on, not the polecat branch it was cut from"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "the work record rides the ONE update that closes"
has "$(grep '^bd update' "$STUB_GC_LOG")" "--set-metadata gc.work_commit=$SHA_A" "the commit is in the closing update, which is where the gate reads it"

# The direct strategy names its target in the same call, and that value is the
# branch recorded.
store '[{"id":"w-2","status":"open","assignee":"","notes":"","metadata":{"merged_target":"main"}}]'
out="$("$SUT" transition w-2 --to merged --close --set merged_sha=$SHA_A --set merged_target=release 2>&1)"; rc=$?
eq "$rc" 0 "an unanchored -> merged close (direct strategy) exits 0"
eq "$(meta w-2 gc.work_branch)" "release" "gc.work_branch follows the merged_target the call sets"

# A landing that names only one of the commit and the branch writes none of the
# record. The bead can already hold part of one, such as the branch
# workspace-setup stamps, and half a new record beside half of that one pairs a
# commit with a branch it is not on. The unverified:PR#<n> sentinel names no
# commit, so the bead keeps the record it had.
SHA_P=89abcdef0123456789abcdef0123456789abcdef
store '[{"id":"w-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","merged_target":"main","gc.work_commit":"'"$SHA_P"'","gc.work_branch":"polecat/w-3"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition w-3 --to merged --close --set 'merged_sha=unverified:PR#7' 2>&1)"; rc=$?
eq "$rc" 0 "an unverified landing still records"
eq "$(bstatus w-3)" "closed" "an unverified landing still closes"
eq "$(meta w-3 gc.work_outcome)" "<absent>" "an unverified landing writes no gc.work_outcome"
eq "$(meta w-3 gc.work_commit)" "$SHA_P" "the bead keeps its gc.work_commit, so the target branch is not paired with it"
eq "$(meta w-3 gc.work_branch)" "polecat/w-3" "the bead keeps its gc.work_branch"
hasnt "$(grep '^bd update' "$STUB_GC_LOG")" "gc.work_" "the closing update carries no work-record key"

# A landing with no merged_target names no branch, so the merge commit is not
# paired with the polecat branch the bead still records.
store '[{"id":"w-6","status":"open","assignee":"","notes":"","metadata":{"gc.work_commit":"'"$SHA_P"'","gc.work_branch":"polecat/w-6"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition w-6 --to merged --close --set merged_sha=$SHA_A 2>&1)"; rc=$?
eq "$rc" 0 "an unanchored -> merged close with no merged_target exits 0"
eq "$(meta w-6 gc.work_outcome)" "<absent>" "a landing that names no branch writes no gc.work_outcome"
eq "$(meta w-6 gc.work_commit)" "$SHA_P" "the merge commit is not paired with the polecat branch"
eq "$(meta w-6 gc.work_branch)" "polecat/w-6" "the bead keeps its gc.work_branch"
hasnt "$(grep '^bd update' "$STUB_GC_LOG")" "gc.work_" "the closing update carries no work-record key"

# A key the caller sets itself is written even when the landing derives none.
store '[{"id":"w-7","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","merged_target":"main"}}]'
out="$("$SUT" transition w-7 --to merged --close --set 'merged_sha=unverified:PR#8' --set gc.work_commit=$SHA_A 2>&1)"; rc=$?
eq "$rc" 0 "a partial landing whose caller sets gc.work_commit exits 0"
eq "$(meta w-7 gc.work_commit)" "$SHA_A" "the caller's gc.work_commit is written"
eq "$(meta w-7 gc.work_outcome)" "<absent>" "no gc.work_outcome is derived beside it"
eq "$(meta w-7 gc.work_branch)" "<absent>" "no gc.work_branch is derived beside it"

# A key the caller writes itself is the one written.
store '[{"id":"w-4","status":"open","assignee":"","notes":"","metadata":{"merge_result":"blocked","merged_target":"main"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition w-4 --to merged --close --set merged_sha=$SHA_A --set gc.work_branch=polecat/w-4 2>&1)"; rc=$?
eq "$rc" 0 "a merged close that sets gc.work_branch itself exits 0"
eq "$(meta w-4 gc.work_branch)" "polecat/w-4" "the caller's gc.work_branch is the one written"
hasnt "$(grep '^bd update' "$STUB_GC_LOG")" "gc.work_branch=main" "no derived gc.work_branch is written beside it"

# Only a landing writes a work record.
store '[{"id":"w-5","status":"open","assignee":"","notes":"","metadata":{"merge_result":"refused_false_completion","merged_target":"main"}}]'
out="$("$SUT" transition w-5 --to blocked --set pr_url=https://x/pr/5 --set pr_number=5 2>&1)"; rc=$?
eq "$rc" 0 "a non-landing transition exits 0"
eq "$(meta w-5 gc.work_outcome)" "<absent>" "a non-landing transition writes no gc.work_outcome"

# --- the exec ------------------------------------------------------------------
# gctk's usage text names itself, so it is the proof that lifecycle.sh handed
# the call to the binary rather than answering it some other way.
echo "# lifecycle.sh execs gctk"
has "$("$SUT" 2>&1)" "gctk lifecycle" "lifecycle.sh execs the binary GCTK_BIN names"

# --- the city chain, with no GCTK_BIN to shortcut it -----------------------------
# GC_CITY_PATH is the city root a supervisor puts in an agent session; GC_CITY
# and GC_CITY_ROOT are absent there. A resolver blind to it refuses every
# transition an agent makes. Reached with GCTK_BIN unset, which is how a real
# caller reaches it.
echo "# the city chain"
CITY="$TMP/city"
mkdir -p "$CITY/.gc/services/gctk/bin"
cp "$GCTK_BUILT" "$CITY/.gc/services/gctk/bin/gctk"
for VAR in GC_CITY_PATH GC_CITY GC_CITY_ROOT; do
    out=$(env -u GCTK_BIN -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT "$VAR=$CITY" "$SUT" 2>&1)
    has "$out" "gctk lifecycle" "$VAR alone resolves the deployed binary"
done

# The order runner that execs the merge cadence carries no city variable at all,
# so the city `gc service list --json` reports is the only route its transitions
# have.
SVC="$TMP/svc-bin"
mkdir -p "$SVC"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$SVC/gc" <<EOF
[ "\${1:-} \${2:-}" = "service list" ] && { printf '{"city_path":"%s"}\n' "$CITY"; exit 0; }
exec "$BIN/gc" "\$@"
EOF
chmod +x "$SVC/gc"
out=$(env -u GCTK_BIN -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT PATH="$SVC:$PATH" "$SUT" 2>&1)
has "$out" "gctk lifecycle" "with no city variable, the city \`gc service list --json\` names resolves the deployed binary"

# A build that fails after a good one leaves that binary in place, and its record
# says so. lifecycle.sh does not consult the record: the last good binary answers.
printf '{"component":"gctk","last_build_rc":1,"binary_rev":"aaaa","source_rev":"bbbb"}\n' \
  > "$CITY/.gc/services/gctk/build-status.json"
out=$(env -u GCTK_BIN -u GC_CITY -u GC_CITY_ROOT GC_CITY_PATH="$CITY" "$SUT" 2>&1)
has "$out" "gctk lifecycle" "a city whose latest build failed still runs its last good binary"

# --- no binary: refused, named, and nothing read or written ----------------------
# lifecycle.sh has no other implementation, so a call it cannot hand to a binary
# is refused with exit 1 — the code every caller reads as a refused transition —
# and a message that names what is missing. The bead is left exactly as it was.
echo "# no binary to exec"
store '[{"id":"z-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"refused_false_completion"}}]'

: > "$STUB_GC_LOG"
out=$(GCTK_BIN=none "$SUT" transition z-1 --to blocked --set pr_number=9 2>&1); rc=$?
eq "$rc" 1 "GCTK_BIN=none refuses the transition (exit 1)"
has "$out" "GCTK_BIN=none names no binary" "…and says why"
eq "$(meta z-1 merge_result)" "refused_false_completion" "…writing nothing"
eq "$(grep -c '' "$STUB_GC_LOG" || true)" "0" "…and making no gc call at all"

out=$(GCTK_BIN="$TMP/no-such-gctk" "$SUT" transition z-1 --to blocked 2>&1); rc=$?
eq "$rc" 1 "a GCTK_BIN that is not an executable refuses the transition"
has "$out" "$TMP/no-such-gctk is not an executable gctk binary" "…naming the path it was given"

# A fresh city: the gctk-build order has not published a binary yet. The same
# refusal covers a city whose builds have never succeeded.
FRESH="$TMP/fresh-city"
mkdir -p "$FRESH"
: > "$STUB_GC_LOG"
out=$(env -u GCTK_BIN -u GC_CITY -u GC_CITY_ROOT GC_CITY_PATH="$FRESH" \
  "$SUT" transition z-1 --to blocked --set pr_number=9 2>&1); rc=$?
eq "$rc" 1 "a city with no binary yet refuses the transition (exit 1)"
has "$out" "no gctk binary at $FRESH/.gc/services/gctk/bin/gctk" "…naming where the binary belongs"
has "$out" "gctk-build order" "…and the order that publishes it"
has "$out" "$FRESH/.gc/services/gctk/build-status.json" "…and the record of that order's last build"
eq "$(meta z-1 merge_result)" "refused_false_completion" "…writing nothing"
eq "$(grep -c '' "$STUB_GC_LOG" || true)" "0" "…and making no gc call at all"

# The control for the city chain: the binary is on disk at $CITY, and nothing
# names that city.
: > "$STUB_GC_LOG"
out=$(env -u GCTK_BIN -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT "$SUT" transition z-1 --to blocked 2>&1); rc=$?
eq "$rc" 1 "no city named anywhere refuses the transition"
has "$out" "no city to find the gctk binary in" "…naming what is missing"
eq "$(grep -c '^bd ' "$STUB_GC_LOG" || true)" "0" "…and reading or writing no bead"
eq "$(meta z-1 merge_result)" "refused_false_completion" "…so the bead is untouched"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
