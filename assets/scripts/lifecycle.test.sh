#!/usr/bin/env bash
# Hermetic test for the anchor lifecycle — THE writer of lifecycle transitions.
# Covers: the state verb; legal/illegal edges; --expect; the ONE atomic
# `gc bd update` carrying every field; bd refusal (exit 1); post-write
# verification mismatch (exit 2); human states routing to human and detached
# states clearing the route, both in the same call; the empty-route refusal that
# keeps a human state from waiting on nobody; the `held` sitting-hold state; the
# close/terminal pairing guards (--close only into a closed state, closed states
# must --close); --set-dated's compare-and-preserve rule for the @<since>
# component; the reopen repair verb; the park-route takeaway guard and its
# --takeaway writer, capped and mirrored from gc-helm.sh; and the drift
# assertion against lifecycle/lifecycle.toml.
#
# TWO ARMS, ONE BODY. The lifecycle writer exists twice during the gctk
# migration — `gctk lifecycle` (services/gctk) and the shell fallback in
# lifecycle.sh — and a caller cannot tell which answered. So every assertion
# below runs against both: arm "shell" forces the fallback with GCTK_BIN=none,
# arm "gctk" points GCTK_BIN at a freshly built binary and reaches it through
# lifecycle.sh, which also proves the preference wiring. Each arm holds its own
# mirror of the state table against lifecycle.toml — the embedded shell block
# for one, `gctk lifecycle --dump-machine` for the other.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/lifecycle.sh"
TOML="$ROOT/lifecycle/lifecycle.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build the port BEFORE the harness puts stub binaries on PATH: the stub git
# answers nothing, and a toolchain that consults it for a VCS stamp would be
# reading a fixture. -buildvcs=false keeps the build off that path entirely; no
# assertion here reads a version.
GCTK_BUILT=""
GCTK_BUILD_LOG="$TMP/gctk-build.log"
GO_PRESENT=0
if command -v go >/dev/null 2>&1; then
    GO_PRESENT=1
    if ( cd "$ROOT/services/gctk" && go build -buildvcs=false -o "$TMP/gctk" ./cmd/gctk ) >"$GCTK_BUILD_LOG" 2>&1; then
        GCTK_BUILT="$TMP/gctk"
    fi
fi

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init
[ -x "$SUT" ] || chmod +x "$SUT"

# --- lifecycle.toml, read the same way for both arms ---------------------------
toml_states() { awk '/^states = \[/{f=1;next} f&&/^\]/{exit} f{gsub(/[ ",]/,"");print}' "$TOML" | tr '\n' ' ' | sed 's/ $//'; }
toml_human()  { sed -n 's/^human_states = \[\(.*\)\]/\1/p' "$TOML" | tr -d '",' | sed 's/^ *//;s/ *$//' | tr -s ' '; }
toml_detached() { sed -n 's/^detached_states = \[\(.*\)\]/\1/p' "$TOML" | tr -d '",' | sed 's/^ *//;s/ *$//' | tr -s ' '; }
toml_park()   { sed -n 's/^park_route = "\(.*\)"/\1/p' "$TOML"; }
toml_closed() { sed -n 's/^closed_states = \[\(.*\)\]/\1/p' "$TOML" | tr -d '", '; }
toml_edges()  {
  awk '
    /^\[\[transition\]\]/ { from=""; to="" }
    /^from = /  { gsub(/from = |"/,""); from=$0 }
    /^to = /    { gsub(/to = |"/,""); to=$0; print from ">" to }' "$TOML" | sort
}

# The shell fallback carries the table as constants in a marked block.
drift_shell() {
  echo "# drift against lifecycle.toml (embedded shell table)"
  BLOCK="$(awk '/# >>> lifecycle-state-table/{f=1;next} /# <<< lifecycle-state-table/{f=0} f' "$SUT")"
  [ -n "$BLOCK" ] && ok "state-table block extracted" || bad "state-table markers missing"
  eval "$BLOCK"
  eq "$LIFECYCLE_STATES" "$(toml_states)" "states match lifecycle.toml"
  eq "$(printf '%s' "$LIFECYCLE_HUMAN_STATES" | tr -s ' ')" "$(toml_human)" "human states match lifecycle.toml"
  eq "$(printf '%s' "$LIFECYCLE_DETACHED_STATES" | tr -s ' ')" "$(toml_detached)" "detached states match lifecycle.toml"
  eq "$LIFECYCLE_PARK_ROUTE" "$(toml_park)" "park route matches lifecycle.toml"
  eq "$LIFECYCLE_CLOSED_STATES" "$(toml_closed)" "closed states match lifecycle.toml"
  eq "$(printf '%s\n' "$LIFECYCLE_TRANSITIONS" | sed '/^$/d' | sort)" "$(toml_edges)" "transition edges match lifecycle.toml"
}

# The port carries it in a typed package and prints it on demand.
drift_gctk() {
  echo "# drift against lifecycle.toml (gctk lifecycle --dump-machine)"
  DUMP="$("$GCTK_BUILT" lifecycle --dump-machine 2>&1)"
  [ -n "$DUMP" ] && ok "machine dumped" || bad "gctk lifecycle --dump-machine produced nothing"
  eq "$(printf '%s\n' "$DUMP" | sed -n 's/^states //p')" "$(toml_states)" "states match lifecycle.toml"
  eq "$(printf '%s\n' "$DUMP" | sed -n 's/^human_states //p')" "$(toml_human)" "human states match lifecycle.toml"
  eq "$(printf '%s\n' "$DUMP" | sed -n 's/^detached_states //p')" "$(toml_detached)" "detached states match lifecycle.toml"
  eq "$(printf '%s\n' "$DUMP" | sed -n 's/^park_route //p')" "$(toml_park)" "park route matches lifecycle.toml"
  eq "$(printf '%s\n' "$DUMP" | sed -n 's/^closed_states //p')" "$(toml_closed)" "closed states match lifecycle.toml"
  eq "$(printf '%s\n' "$DUMP" | sed -n 's/^transition //p' | sort)" "$(toml_edges)" "transition edges match lifecycle.toml"
  # The cap is not in lifecycle.toml: it is a rendering bound the two takeaway
  # writers share, and the shell arm holds lifecycle.sh's copy against
  # gc-helm.sh. Chaining the port to lifecycle.sh completes that line.
  eq "$(printf '%s\n' "$DUMP" | sed -n 's/^takeaway_max //p')" \
     "$(sed -n 's/^LIFECYCLE_TAKEAWAY_MAX=\([0-9]*\).*/\1/p' "$SUT" | head -1)" \
     "takeaway cap matches lifecycle.sh"
}

suite() {

# The machine axis is declared here and spent by the helm board, which mirrors
# it as Go constants. One meaning, two lists: a value added on one side only
# renders as `unknown` on every row carrying it, which is the answer that tells
# the operator to stop looking.
TOML_MACHINES=$(sed -n 's/^machines = \[\(.*\)\]/\1/p' "$TOML" | tr -d '",' | tr -s ' ' | sed 's/^ *//;s/ *$//')
[ -n "$TOML_MACHINES" ] && ok "machine axis declared in lifecycle.toml" || bad "machines = [...] missing from lifecycle.toml"
GO_MACHINES=$(sed -n 's/^[[:space:]]*Machine[A-Za-z]*[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$ROOT/services/helm/internal/board/derive.go" | tr '\n' ' ' | sed 's/ *$//')
eq "$GO_MACHINES" "$TOML_MACHINES" "machine axis values match lifecycle.toml"

# --- state verb ----------------------------------------------------------------
echo "# state"
store '[{"id":"b-1","status":"open","assignee":"","notes":"","metadata":{}},
        {"id":"b-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}},
        {"id":"b-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"weird_value"}}]'
out="$("$SUT" state b-1)"; rc=$?
eq "$rc" 0 "state exits 0 on a readable bead"
eq "$out" "unanchored" "absent merge_result reads as unanchored"
eq "$("$SUT" state b-2)" "pull_request" "declared value is printed"
out="$("$SUT" state b-3 2>&1)"; rc=$?
eq "$rc" 1 "undeclared merge_result exits 1"
has "$out" "weird_value" "the undeclared value is named"
out="$("$SUT" state b-nope 2>&1)"; rc=$?
eq "$rc" 2 "an unreadable bead exits 2"

# --- transition: happy path is ONE update carrying everything -------------------
echo "# transition happy path"
store '[{"id":"a-1","status":"open","assignee":"rig/refinery","notes":"","metadata":{"merge_result":"pull_request","rejection_reason":"old"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition a-1 --to merged --expect pull_request --close \
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
has "$out" '"ok":true' "--json reports the transition"
has "$out" '"from":"pull_request"' "--json names the from state"

# --- --set-dated: the @<since> compare-and-preserve rule ------------------------
# The operator's queue is ordered by how long a row has been owed, so the instant
# a turn began has to survive every pass that re-reaches the same verdict at the
# same head. Getting this wrong is not a visible failure: the row keeps rendering,
# it just reports a three-day wait as new and sorts the most neglected row last.
echo "# --set-dated"
OID="1111111111111111111111111111111111111111"
OID2="2222222222222222222222222222222222222222"

store '[{"id":"d-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$("$SUT" transition d-1 --to pull_request --set-dated "pr.machine=wedged-exception@$OID" 2>&1)"; rc=$?
eq "$rc" 0 "a first dated write exits 0"
got="$(meta d-1 pr.machine)"
eq "${got%@*}" "wedged-exception@$OID" "the value and oid are written as given"
case "$got" in
  *@*@20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) ok "…and lifecycle.sh appended an RFC 3339 UTC instant" ;;
  *) bad "no instant appended: '$got'" ;;
esac

# Preserve: the reconcile cadence re-reaches the same verdict at the same head
# every few minutes, which is the case a naive clock restarts.
store '[{"id":"d-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","pr.machine":"wedged-exception@'"$OID"'@2026-08-28T04:05:06Z"}}]'
"$SUT" transition d-2 --to pull_request --set-dated "pr.machine=wedged-exception@$OID" >/dev/null 2>&1
eq "$(meta d-2 pr.machine)" "wedged-exception@$OID@2026-08-28T04:05:06Z"   "an unchanged value at an unchanged head keeps its instant"

# Restamp on a changed VALUE: a new verdict is a new turn.
store '[{"id":"d-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","pr.machine":"progressing@'"$OID"'@2026-08-28T04:05:06Z"}}]'
"$SUT" transition d-3 --to pull_request --set-dated "pr.machine=wedged-exception@$OID" >/dev/null 2>&1
got="$(meta d-3 pr.machine)"
eq "${got%@*}" "wedged-exception@$OID" "a changed value is written"
case "$got" in
  *@2026-08-28T04:05:06Z) bad "a changed value kept the old instant: '$got'" ;;
  *) ok "…and starts a fresh clock" ;;
esac

# Restamp on a moved HEAD: a wedge is released by a head move, so the old
# instant dates a state that no longer holds.
store '[{"id":"d-4","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","pr.machine":"wedged-exception@'"$OID"'@2026-08-28T04:05:06Z"}}]'
"$SUT" transition d-4 --to pull_request --set-dated "pr.machine=wedged-exception@$OID2" >/dev/null 2>&1
got="$(meta d-4 pr.machine)"
eq "${got%@*}" "wedged-exception@$OID2" "a moved head is written"
case "$got" in
  *@2026-08-28T04:05:06Z) bad "a moved head kept the old instant: '$got'" ;;
  *) ok "…and starts a fresh clock" ;;
esac

# A value still in the bare <value>@<oid> shape has no instant to keep.
store '[{"id":"d-5","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","pr.machine":"settled@'"$OID"'"}}]'
"$SUT" transition d-5 --to pull_request --set-dated "pr.machine=settled@$OID" >/dev/null 2>&1
got="$(meta d-5 pr.machine)"
case "$got" in
  "settled@$OID@"?*) ok "an undated legacy value gains an instant" ;;
  *) bad "the legacy value was left undated: '$got'" ;;
esac

# One atomic write, exactly as an ordinary --set: the dated key rides the same
# update rather than adding a second one.
store '[{"id":"d-6","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
"$SUT" transition d-6 --to pull_request --set-dated "pr.machine=settled@$OID" --set check_set=codex >/dev/null 2>&1
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "a dated key rides the ONE atomic update"

# Shape refusals: the writer supplies value and oid, this script supplies the
# instant, and a malformed argument makes the preserve comparison undecidable.
store '[{"id":"d-7","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$("$SUT" transition d-7 --to pull_request --set-dated "pr.machine=settled" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated with no oid is refused"
has "$out" "<value>@<oid>" "the refusal names the shape"
out="$("$SUT" transition d-7 --to pull_request --set-dated "pr.machine=settled@$OID@2026-01-01T00:00:00Z" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated carrying its own instant is refused"
out="$("$SUT" transition d-7 --to pull_request --set-dated "pr.machine" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated with no '=' is refused"
out="$("$SUT" transition d-7 --to pull_request --set-dated "merge_result=x@$OID" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated merge_result is refused (owned by --to)"
out="$("$SUT" transition d-7 --to pull_request --set-dated "gc.routed_to=x@$OID" 2>&1)"; rc=$?
eq "$rc" 1 "--set-dated gc.routed_to is refused (owned by --route)"
eq "$(meta d-7 pr.machine)" "<absent>" "no refusal wrote anything"

# --- a transition that changes nothing performs no write -----------------------
# The observer arms re-reach the same verdict on most anchors of every pass, and
# each re-assertion cost an update plus its read-back — two store subprocesses
# per anchor, on a cadence whose budget is store subprocesses. What must not
# change with them gone: the exit code, the report, and the stored value.
echo "# idle transitions"
store '[{"id":"n-1","status":"open","assignee":"rig/refinery","notes":"","metadata":{"merge_result":"pull_request","pr.machine":"settled@'"$OID"'@2026-08-28T04:05:06Z","gc.routed_to":"rig/pool"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition n-1 --to pull_request --expect pull_request \
  --route rig/pool --set-dated "pr.machine=settled@$OID" 2>&1)"; rc=$?
eq "$rc" 0 "a re-assertion of the state already on the bead exits 0"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "…and issues NO gc bd update"
has "$out" "n-1 pull_request -> pull_request" "…and still reports the state"
eq "$(meta n-1 pr.machine)" "settled@$OID@2026-08-28T04:05:06Z" "…leaving the instant it would have preserved"
eq "$(meta n-1 gc.routed_to)" "rig/pool" "…and the route it carried back"
out="$("$SUT" transition n-1 --to pull_request --route rig/pool \
  --set-dated "pr.machine=settled@$OID" --json 2>&1)"
eq "$(printf '%s' "$out" | jq -r '.ok')" "true" "--json still reports ok"
eq "$(printf '%s' "$out" | jq -r '.from + ">" + .to')" "pull_request>pull_request" "…with the same from/to"

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
BASE='"id":"n-2","status":"open","assignee":"rig/refinery","notes":""'
writes_when "a moved head writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"pull_request\",\"pr.machine\":\"settled@$OID@2026-08-28T04:05:06Z\"}}" \
  n-2 --to pull_request --set-dated "pr.machine=settled@$OID2"
writes_when "a changed verdict writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"pull_request\",\"pr.machine\":\"settled@$OID@2026-08-28T04:05:06Z\"}}" \
  n-2 --to pull_request --set-dated "pr.machine=wedged-exception@$OID"
writes_when "a changed --set writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"pull_request\",\"check_set\":\"codex\"}}" \
  n-2 --to pull_request --set check_set=codex,ci
writes_when "a --set of an absent key writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"pull_request\"}}" \
  n-2 --to pull_request --set check_set=codex
writes_when "a --unset of a present key writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"pull_request\",\"rejection_reason\":\"old\"}}" \
  n-2 --to pull_request --unset rejection_reason
writes_when "a changed --route writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"pull_request\",\"gc.routed_to\":\"rig/pool\"}}" \
  n-2 --to pull_request --route rig/other
writes_when "a moved state writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"pre_open_gate\"}}" \
  n-2 --to pull_request
# Fields the comparison does NOT cover: each writes unconditionally, because a
# skip would drop something no comparison against the current bead can see.
writes_when "--append-notes always writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"pull_request\"}}" \
  n-2 --to pull_request --append-notes "another line"
writes_when "--takeaway always writes (it stamps a fresh instant)" \
  '{"id":"n-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","gc.routed_to":"human","gc.takeaway":"same text","gc.takeaway_at":"2026-08-28T04:05:06Z","gc.takeaway_by":"lifecycle"}}' \
  n-2 --to pull_request --route human --takeaway "same text"
writes_when "--assignee always writes" \
  "{$BASE,\"metadata\":{\"merge_result\":\"pull_request\"}}" \
  n-2 --to pull_request --assignee rig/refinery
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

# Validation is not what is skipped: an idle-looking call whose --expect does not
# hold is still refused, and so is one whose edge is illegal.
store '[{"id":"n-5","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition n-5 --to pull_request --expect pre_open_gate 2>&1)"; rc=$?
eq "$rc" 1 "an --expect mismatch is still refused ahead of the skip"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "…and wrote nothing"
store '[{"id":"n-6","status":"open","assignee":"","notes":"","metadata":{"merge_result":"merged"}}]'
out="$("$SUT" transition n-6 --to pull_request 2>&1)"; rc=$?
eq "$rc" 1 "an illegal edge is still refused"

# --- illegal edge / --expect mismatch / refusal ---------------------------------
echo "# refusals"
store '[{"id":"a-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"merged"}}]'
out="$("$SUT" transition a-2 --to pull_request 2>&1)"; rc=$?
eq "$rc" 1 "illegal edge exits 1"
has "$out" "illegal edge merged -> pull_request" "the illegal edge is named"
eq "$(meta a-2 merge_result)" "merged" "an illegal edge writes nothing"

store '[{"id":"a-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate"}}]'
out="$("$SUT" transition a-3 --to pull_request --expect pull_request 2>&1)"; rc=$?
eq "$rc" 1 "--expect mismatch exits 1"
eq "$(meta a-3 merge_result)" "pre_open_gate" "an --expect mismatch writes nothing"

out="$(STUB_UPDATE_FAIL="a-3" "$SUT" transition a-3 --to pull_request 2>&1)"; rc=$?
eq "$rc" 1 "a bd refusal exits 1"
has "$out" "refused by bd" "the refusal is named"

out="$("$SUT" transition a-3 --to nowhere 2>&1)"; rc=$?
eq "$rc" 1 "an undeclared --to state exits 1"
out="$("$SUT" transition a-3 --to pull_request --set merge_result=x 2>&1)"; rc=$?
eq "$rc" 1 "--set merge_result is refused (owned by --to)"
out="$("$SUT" transition a-3 --to pull_request --set gc.routed_to=x 2>&1)"; rc=$?
eq "$rc" 1 "--set gc.routed_to is refused (owned by --route)"

# --- post-write verification ----------------------------------------------------
echo "# verification"
store '[{"id":"a-4","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate"}}]'
out="$(STUB_DROP_KEYS="a-4:pr_url" "$SUT" transition a-4 --to pull_request \
  --set pr_url=https://github.com/z/r/pull/9 --set pr_number=9 2>&1)"; rc=$?
eq "$rc" 2 "a half-landed write exits 2 (verification mismatch)"
has "$out" "pr_url" "the unverified field is named"

store '[{"id":"a-5","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$(STUB_DROP_KEYS="a-5:status" "$SUT" transition a-5 --to merged --close --set merged_sha=x 2>&1)"; rc=$?
eq "$rc" 2 "a close that did not land exits 2"

# --- human states route to human in the same atomic call ------------------------
echo "# human states"
store '[{"id":"a-6","status":"open","assignee":"rig/refinery","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition a-6 --to abandoned --assignee "" \
  --set blocked_reason="PR#7 closed out-of-band" \
  --takeaway "PR#7 was closed without merging — rework it or close this bead" 2>&1)"; rc=$?
eq "$rc" 0 "transition to abandoned exits 0"
eq "$(meta a-6 'gc.routed_to')" "human" "abandoned routes to human automatically"
eq "$(bassignee a-6)" "" "--assignee '' cleared the assignee"
eq "$(meta a-6 'gc.takeaway')" "PR#7 was closed without merging — rework it or close this bead" \
  "the park names what it wants"
eq "$(meta a-6 'gc.takeaway_by')" "lifecycle" "the takeaway names its writer"
case "$(meta a-6 'gc.takeaway_at')" in
  ????-??-??T??:??:??Z) ok "the takeaway is dated" ;;
  *) bad "the takeaway carries no gc.takeaway_at" ;;
esac
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "route + clear + reason + takeaway ride in ONE update"
eq "$(meta a-6 'gc.takeaway_settled')" "" "the park's headline carries its own disposition, not a settled one"

# A transition's takeaway parks a bead or ends it, so its disposition is never
# "settled" — and a bead can carry that value from the sitting before this one.
# The clear is the one field of the stamp whose stale value is a wrong answer
# rather than a missing one: doctor/check-wait-is-an-edge reads it and skips the
# park it was written to report. A clear that did not land is a failed
# transition, on the same terms as a dropped timestamp.
store '[{"id":"a-7","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","gc.takeaway_settled":"1"}}]'
out="$(STUB_DROP_KEYS="a-7:gc.takeaway_settled" "$SUT" transition a-7 --to abandoned \
  --takeaway "PR#7 was closed without merging — rework it or close this bead" 2>&1)"; rc=$?
eq "$rc" 2 "a takeaway that did not clear an inherited settled-key exits 2"
has "$out" "gc.takeaway_settled" "…and the unverified field is named"
eq "$(meta a-7 'gc.takeaway_settled')" "1" "…and the stale value is what read back"

store '[{"id":"a-8","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","gc.takeaway_settled":"1"}}]'
out="$("$SUT" transition a-8 --to abandoned --takeaway "needs a ruling on the base branch" 2>&1)"; rc=$?
eq "$rc" 0 "…while a clear that lands over an inherited value exits 0"
eq "$(meta a-8 'gc.takeaway_settled')" "" "…leaving the park's own disposition on the bead"

# --- detached states clear the route in the same atomic call --------------------
# A detached anchor rests unrouted so that no pool offers it. Any route but the
# park sentinel turns the resting state back into pool demand.
echo "# detached states"
store '[{"id":"d-1","status":"open","assignee":"rig/refinery","notes":"","metadata":{"gc.routed_to":"rig/pool"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition d-1 --to pre_open_gate --assignee "" --set check_set=codex 2>&1)"; rc=$?
eq "$rc" 0 "transition to pre_open_gate exits 0"
eq "$(meta d-1 'gc.routed_to')" "" "pre_open_gate clears the route automatically"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "the clear rides in the SAME update"

store '[{"id":"d-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate","gc.routed_to":"rig/pool"}}]'
out="$("$SUT" transition d-2 --to pull_request --expect pre_open_gate \
  --set pr_url=https://github.com/z/r/pull/9 --set pr_number=9 2>&1)"; rc=$?
eq "$rc" 0 "pre_open_gate -> pull_request exits 0"
eq "$(meta d-2 'gc.routed_to')" "" "a route carried into pull_request is cleared, not inherited"

store '[{"id":"d-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate"}}]'
out="$("$SUT" transition d-3 --to pull_request --route rig/human-recovery 2>&1)"; rc=$?
eq "$rc" 0 "an explicit --route into a detached state exits 0"
eq "$(meta d-3 'gc.routed_to')" "rig/human-recovery" "an explicit --route wins over the declared clear"

store '[{"id":"d-4","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate","gc.routed_to":"human"}}]'
out="$("$SUT" transition d-4 --to pull_request --set pr_number=9 2>&1)"; rc=$?
eq "$rc" 0 "a park-routed anchor transitions"
eq "$(meta d-4 'gc.routed_to')" "human" "the park route survives the transition"

store '[{"id":"d-5","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate","gc.routed_to":"rig/pool"}}]'
out="$(STUB_DROP_KEYS="d-5:gc.routed_to" "$SUT" transition d-5 --to pull_request 2>&1)"; rc=$?
eq "$rc" 2 "a clear that did not land exits 2 (verification mismatch)"
has "$out" "gc.routed_to" "the unverified route is named"

# --- detached states clear the assignee in the same atomic call ----------------
# The unheld half of the same property. The refinery's find-work queue is
# assignee-keyed and flags a merge_result-bearing bead it finds there instead of
# taking it, so an assignee that survives the gating transition sits in that
# queue for the life of the anchor.
echo "# detached states clear the assignee"
store '[{"id":"h-1","status":"open","assignee":"rig/gc-toolkit.refinery","notes":"","metadata":{}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition h-1 --to pre_open_gate --set check_set=codex 2>&1)"; rc=$?
eq "$rc" 0 "entry to pre_open_gate exits 0"
eq "$(bassignee h-1)" "" "the handoff assignee is cleared without the caller asking"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "the clear rides in the SAME update as the state"

store '[{"id":"h-2","status":"open","assignee":"rig/gc-toolkit.refinery","notes":"","metadata":{"merge_result":"pull_request"}}]'
"$SUT" transition h-2 --to pull_request --expect pull_request --route "" >/dev/null 2>&1
eq "$(bassignee h-2)" "" "a self-edge observation converges a survivor already parked in the state"

store '[{"id":"h-3","status":"open","assignee":"rig/gc-toolkit.refinery","notes":"","metadata":{"merge_result":"pre_open_gate"}}]'
"$SUT" transition h-3 --to pull_request --assignee "rig/mechanik" >/dev/null 2>&1
eq "$(bassignee h-3)" "rig/mechanik" "an explicit --assignee wins over the declared clear"

# bd refuses an assignee edit on a bead another actor holds in_progress and
# drops the whole atomic update with it, so the arm must not reach for the
# field there. The proof is the emitted call: no --assignee flag, no guard.
store '[{"id":"h-4","status":"in_progress","assignee":"rig/gc-toolkit.polecat-1","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition h-4 --to pull_request --expect pull_request --route "" --set pr_number=9 2>&1)"; rc=$?
eq "$rc" 0 "a transition on an in_progress anchor still lands"
eq "$(bassignee h-4)" "rig/gc-toolkit.polecat-1" "a live claim is left for escalation, not overwritten"
hasnt "$(grep '^bd update' "$STUB_GC_LOG")" "--assignee" "no assignee flag reaches bd, so the anti-steal guard is never armed"
eq "$(meta h-4 pr_number)" "9" "the rest of the transition landed"

# An already-unheld anchor is the healthy case, and it must issue the bd call it
# always did: an --assignee flag there buys nothing and arms the guard for free.
store '[{"id":"h-5","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate"}}]'
: > "$STUB_GC_LOG"
"$SUT" transition h-5 --to pull_request --set pr_number=9 >/dev/null 2>&1
hasnt "$(grep '^bd update' "$STUB_GC_LOG")" "--assignee" "an empty assignee emits no flag"

# A human state is not detached: it names a person by route, and the assignee is
# the caller's to decide.
store '[{"id":"h-6","status":"open","assignee":"rig/gc-toolkit.refinery","notes":"","metadata":{"merge_result":"pull_request"}}]'
"$SUT" transition h-6 --to retargeted --route rig/mechanik >/dev/null 2>&1
eq "$(bassignee h-6)" "rig/gc-toolkit.refinery" "a human state leaves the assignee alone"

store '[{"id":"h-7","status":"open","assignee":"rig/gc-toolkit.refinery","notes":"","metadata":{"merge_result":"pre_open_gate"}}]'
out="$(STUB_DROP_KEYS="h-7:assignee" "$SUT" transition h-7 --to pull_request 2>&1)"; rc=$?
eq "$rc" 2 "a clear that did not land exits 2 (verification mismatch)"
has "$out" "assignee" "the unverified assignee is named"

store '[{"id":"a-7","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
"$SUT" transition a-7 --to retargeted --route rig/mechanik >/dev/null 2>&1
eq "$(meta a-7 'gc.routed_to')" "rig/mechanik" "an explicit --route overrides the human default"

# --- a human state must NAME the person it waits on -----------------------------
echo "# human states name a route"
store '[{"id":"a-7b","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition a-7b --to abandoned --route "" 2>&1)"; rc=$?
eq "$rc" 1 "an EMPTY --route into a human state exits 1"
has "$out" "waiting on nobody" "the refusal says what an empty route leaves behind"
has "$out" "human_states:" "the refusal names the human-state set"
eq "$(meta a-7b merge_result)" "pull_request" "the refused transition wrote nothing"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "and never reached bd"

# The tk-9heqfh shape: a sitting ended holding and left its subject waiting on
# nobody — no state, empty route, the hold recorded only as takeaway prose.
# Through this writer that attempt is refused rather than recorded.
store '[{"id":"tk-9heqfh","status":"open","assignee":"","notes":"","metadata":{"gc.takeaway":"holding — PR#477 is codex-green and one approval from landing; needs a ruling"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition tk-9heqfh --to held --route "" 2>&1)"; rc=$?
eq "$rc" 1 "the found tk-9heqfh state is unreachable through the writer"
has "$out" "requires a route" "the refusal names the missing route"
eq "$(meta tk-9heqfh merge_result)" "<absent>" "no state was recorded"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "and no write was attempted"

# --- a park must NAME what it waits for ------------------------------------------
# The helm board spends gc.takeaway as a row's NEEDS sentence and, on a row
# routed to a person with none, reports that nobody recorded a question. So
# writing the park route without a takeaway is refused here.
echo "# a park names what it waits for"
store '[{"id":"p-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition p-1 --to abandoned --set blocked_reason="PR#7 closed out-of-band" 2>&1)"; rc=$?
eq "$rc" 1 "a park with no takeaway exits 1"
has "$out" "no question recorded" "the refusal quotes what the board would render"
has "$out" "--takeaway" "the refusal names the flag that fixes it"
eq "$(meta p-1 merge_result)" "pull_request" "the refused park wrote nothing"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "and never reached bd"

# The same refusal on an EXPLICIT --route human, whatever the state.
store '[{"id":"p-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate"}}]'
out="$("$SUT" transition p-2 --to pull_request --route human 2>&1)"; rc=$?
eq "$rc" 1 "an explicit --route human with no takeaway exits 1"
has "$out" "no question recorded" "the refusal is the same one"

# A bead that already carries a takeaway satisfies the guard: that is the
# converse sitting which stamped its hold before transitioning.
store '[{"id":"p-3","status":"open","assignee":"","notes":"","metadata":{"gc.takeaway":"holding — needs a ruling on the base branch"}}]'
out="$("$SUT" transition p-3 --to blocked 2>&1)"; rc=$?
eq "$rc" 0 "a bead already carrying a takeaway parks"
eq "$(meta p-3 'gc.takeaway')" "holding — needs a ruling on the base branch" "and keeps the sentence it had"

# Routing anywhere but the park sentinel is not a park.
store '[{"id":"p-4","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$("$SUT" transition p-4 --to retargeted --route rig/mechanik 2>&1)"; rc=$?
eq "$rc" 0 "a route to a POOL needs no takeaway"

# Preserving a park route this call did not set is not a park either: the
# question stays with whoever asked it.
store '[{"id":"p-5","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate","gc.routed_to":"human"}}]'
out="$("$SUT" transition p-5 --to pull_request --set pr_number=9 2>&1)"; rc=$?
eq "$rc" 0 "a preserved park route needs no takeaway"
eq "$(meta p-5 'gc.routed_to')" "human" "and the route survives"

# Nor is naming the route the bead already rests on. gate-ensure.sh and merge.sh
# carry gc.routed_to back on every pr.machine write so that recording a verdict
# cannot clear a route they never looked at, and the anchors they most need to
# record are the wedged ones a cap already parked.
store '[{"id":"p-5b","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","gc.routed_to":"human"}}]'
out="$("$SUT" transition p-5b --to pull_request --route human --set-dated "pr.machine=wedged-exception@sha1" 2>&1)"; rc=$?
eq "$rc" 0 "carrying an existing park route back needs no takeaway"
eq "$(meta p-5b 'gc.routed_to')" "human" "and the route is unchanged"
case "$(meta p-5b 'pr.machine')" in
  wedged-exception@sha1@*) ok "…so the observer's verdict is recorded" ;;
  *) bad "…so the observer's verdict is recorded (got '$(meta p-5b 'pr.machine')')" ;;
esac

# The narrowing is only for a route already there: the same call on a bead this
# write would park is the refusal above.
store '[{"id":"p-5c","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","gc.routed_to":"rig/mechanik"}}]'
out="$("$SUT" transition p-5c --to pull_request --route human --set-dated "pr.machine=wedged-exception@sha1" 2>&1)"; rc=$?
eq "$rc" 1 "moving a bead ONTO the park route still needs a takeaway"
has "$out" "no question recorded" "…with the same refusal"
eq "$(meta p-5c 'gc.routed_to')" "rig/mechanik" "…and the route it had is untouched"

# The takeaway triple is this flag's to write.
store '[{"id":"p-6","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$("$SUT" transition p-6 --to abandoned --set gc.takeaway="via --set" 2>&1)"; rc=$?
eq "$rc" 1 "--set gc.takeaway is refused (owned by --takeaway)"
has "$out" "--takeaway" "the refusal names the owning flag"

# Over the cap the verb REJECTS rather than truncating: only the author knows
# which clause is the headline, and a truncated one loses it silently.
store '[{"id":"p-7","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
LONG=$(printf 'x%.0s' $(seq 141))
: > "$STUB_GC_LOG"
out="$("$SUT" transition p-7 --to abandoned --takeaway "$LONG" 2>&1)"; rc=$?
eq "$rc" 1 "a takeaway over the cap exits 1"
has "$out" "141 chars" "the refusal reports the measured length"
has "$out" "the cap is 140" "…and the cap"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "and nothing was written"

store '[{"id":"p-8","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$("$SUT" transition p-8 --to abandoned --takeaway "$(printf 'x%.0s' $(seq 140))" 2>&1)"; rc=$?
eq "$rc" 0 "a takeaway AT the cap is accepted"

# An EMPTY takeaway is not one. The flag's presence alone must not satisfy the
# park guard: normalization can leave nothing behind, and the park then writes
# the empty gc.takeaway that renders as the very row the guard exists to stop.
store '[{"id":"p-9","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition p-9 --to abandoned --takeaway "" 2>&1)"; rc=$?
eq "$rc" 1 "an empty --takeaway exits 1"
has "$out" "no question recorded" "the refusal quotes what the board would render"
eq "$(meta p-9 'gc.takeaway')" "<absent>" "no empty takeaway is written"
eq "$(meta p-9 merge_result)" "pull_request" "the refused park wrote nothing"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "and never reached bd"

store '[{"id":"p-10","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition p-10 --to abandoned --takeaway "   " 2>&1)"; rc=$?
eq "$rc" 1 "a whitespace-only --takeaway exits 1"
has "$out" "no question recorded" "…with the same refusal"
eq "$(meta p-10 'gc.takeaway')" "<absent>" "…and nothing is written"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "…and nothing reaches bd"

# The refusal belongs to the flag, not to the park: whatever the route, the
# write itself is what the board reads.
store '[{"id":"p-11","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$("$SUT" transition p-11 --to retargeted --route rig/mechanik --takeaway " " 2>&1)"; rc=$?
eq "$rc" 1 "an empty --takeaway is refused on a pool route too"

# --- a takeaway that lands in part is not a transition ---------------------------
# The verifier owes every written field, and a takeaway is three of them: the
# text the board renders, the timestamp it dates and attributes the wait by, and
# the writer that readers discriminate on. Checking only the text passes a park
# the board can neither place nor attribute back as recorded.
echo "# takeaway triple read-back"
store '[{"id":"p-12","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$(STUB_DROP_KEYS="p-12:gc.takeaway_by" "$SUT" transition p-12 --to abandoned \
  --takeaway "PR#7 was closed without merging" 2>&1)"; rc=$?
eq "$rc" 2 "a dropped gc.takeaway_by exits 2"
has "$out" "did NOT verify" "the half-landed triple is reported unverified"
has "$out" "gc.takeaway_by" "…and the refusal names the missing provenance"

store '[{"id":"p-13","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$(STUB_DROP_KEYS="p-13:gc.takeaway_at" "$SUT" transition p-13 --to abandoned \
  --takeaway "PR#8 was closed without merging" 2>&1)"; rc=$?
eq "$rc" 2 "a dropped gc.takeaway_at exits 2"
has "$out" "gc.takeaway_at" "the refusal names the missing timestamp"

store '[{"id":"p-14","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$(STUB_DROP_KEYS="p-14:gc.takeaway" "$SUT" transition p-14 --to abandoned \
  --takeaway "PR#9 was closed without merging" 2>&1)"; rc=$?
eq "$rc" 2 "a dropped gc.takeaway exits 2"
has "$out" "gc.takeaway=" "the refusal names the missing text"

# --- the cap mirrors gc-helm.sh, the other takeaway writer ------------------------
echo "# takeaway cap drift"
HELM_MAX=$(sed -n 's/^TAKEAWAY_MAX=\([0-9]*\).*/\1/p' "$HERE/gc-helm.sh" | head -1)
SUT_MAX=$(sed -n 's/^LIFECYCLE_TAKEAWAY_MAX=\([0-9]*\).*/\1/p' "$SUT" | head -1)
eq "$SUT_MAX" "$HELM_MAX" "the takeaway cap matches gc-helm.sh's TAKEAWAY_MAX"

# --- held: a sitting's hold is a state, entered only from unanchored ------------
echo "# held"
store '[{"id":"h-1","status":"open","assignee":"","notes":"","metadata":{"gc.takeaway":"holding — needs a ruling"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition h-1 --to held 2>&1)"; rc=$?
eq "$rc" 0 "unanchored -> held exits 0"
eq "$(meta h-1 merge_result)" "held" "the hold is recorded as a declared state"
eq "$(meta h-1 'gc.routed_to')" "human" "held routes to human by default"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "state + route ride in ONE update"

# A gating anchor keeps its gating state: merge.sh, gate-ensure.sh and pr-facts.sh
# each enumerate anchors by it, and a hold must not drop one from all three.
store '[{"id":"h-2","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$("$SUT" transition h-2 --to held 2>&1)"; rc=$?
eq "$rc" 1 "pull_request -> held is an illegal edge"
has "$out" "illegal edge pull_request -> held" "the refusal names the edge"

store '[{"id":"h-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"held","gc.routed_to":"human","gc.takeaway":"holding — needs a ruling"}}]'
out="$("$SUT" transition h-3 --to held 2>&1)"; rc=$?
eq "$rc" 0 "re-holding is an idempotent self-edge"

out="$("$SUT" transition h-3 --to unanchored --route rig/polecat 2>&1)"; rc=$?
eq "$rc" 0 "held -> unanchored releases the hold"
eq "$(meta h-3 merge_result)" "<absent>" "the released bead carries no state"
eq "$(meta h-3 'gc.routed_to')" "rig/polecat" "the ruling routes it onward"

# --- rejection to unanchored ------------------------------------------------------
echo "# unanchored"
store '[{"id":"a-8","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate","branch":"polecat/x"}}]'
out="$("$SUT" transition a-8 --to unanchored --set rejection_reason="scope wrong" --route rig/polecat 2>&1)"; rc=$?
eq "$rc" 0 "rejection to unanchored exits 0"
eq "$(meta a-8 merge_result)" "<absent>" "unanchored unsets merge_result"
eq "$(meta a-8 rejection_reason)" "scope wrong" "the rejection reason rides along"
eq "$("$SUT" state a-8)" "unanchored" "state reads back unanchored"

# --- self-edge is an idempotent re-record ----------------------------------------
store '[{"id":"a-9","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$("$SUT" transition a-9 --to pull_request --set pr_number=12 2>&1)"; rc=$?
eq "$rc" 0 "a self-edge (re-record) is legal"
eq "$(meta a-9 pr_number)" "12" "and carries its fields"

# --- close/terminal pairing: status and merge_result move together ---------------
echo "# close pairing"
store '[{"id":"c-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" transition c-1 --to abandoned --close 2>&1)"; rc=$?
eq "$rc" 1 "--close on a non-closed --to state exits 1"
has "$out" "abandoned" "the refused state is named"
has "$out" "not a closed state" "the rule is named"
eq "$(meta c-1 merge_result)" "pull_request" "a refused close writes nothing"
eq "$(bstatus c-1)" "open" "and closes nothing"
out="$("$SUT" transition c-1 --to merged 2>&1)"; rc=$?
eq "$rc" 1 "--to merged without --close exits 1 (a terminal transition must close)"
has "$out" "requires --close" "the missing flag is named"
eq "$(meta c-1 merge_result)" "pull_request" "a refused terminal transition writes nothing"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "neither refusal attempted a bd update"

# --- reopen: the sanctioned repair for a wrongly-closed bead ---------------------
echo "# reopen"
store '[{"id":"r-1","status":"closed","assignee":"","notes":"","metadata":{"merge_result":"pull_request","pr_url":"https://x/pr/4"}}]'
: > "$STUB_GC_LOG"
out="$("$SUT" reopen r-1 2>&1)"; rc=$?
eq "$rc" 0 "reopen on closed+pull_request (the violation shape) exits 0"
eq "$(bstatus r-1)" "open" "the bead is open again"
eq "$(meta r-1 merge_result)" "pull_request" "merge_result is untouched"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "reopen is ONE gc bd update"
has "$(grep '^bd update' "$STUB_GC_LOG")" "--status=open" "and it flips status open"
hasnt "$(grep '^bd update' "$STUB_GC_LOG")" "merge_result" "it never writes merge_result"

store '[{"id":"r-2","status":"closed","assignee":"","notes":"","metadata":{"merge_result":"merged","merged_sha":"abc"}}]'
out="$("$SUT" reopen r-2 2>&1)"; rc=$?
eq "$rc" 1 "reopen refuses a legitimately closed (merged) bead"
has "$out" "legitimate" "the refusal says that close was legitimate"
eq "$(bstatus r-2)" "closed" "and writes nothing"

store '[{"id":"r-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
out="$("$SUT" reopen r-3 2>&1)"; rc=$?
eq "$rc" 1 "reopen refuses an open bead"
has "$out" "nothing to repair" "and says there is nothing to repair"

# A value-taking flag as the LAST token is a truncated command: refuse it. The
# empty value it would otherwise take drops --expect's compare-and-swap guard,
# and a parser that shifts past the end never terminates at all.
store '[{"id":"v-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
: > "$STUB_GC_LOG"
for FLAG in --to --expect --set --set-dated --unset --assignee --route --takeaway --append-notes; do
  out="$(timeout 10 "$SUT" transition v-1 --to pull_request "$FLAG" 2>&1)"; rc=$?
  eq "$rc" 1 "$FLAG with no value is refused (exit 1, not a hang)"
  has "$out" "flag $FLAG needs a value" "and names the flag"
done
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "a refused truncated command writes nothing"

store '[{"id":"r-4","status":"closed","assignee":"","notes":"","metadata":{}}]'
out="$("$SUT" reopen r-4 2>&1)"; rc=$?
eq "$rc" 1 "reopen refuses a closed unanchored bead (a legal closed shape)"

store '[{"id":"r-5","status":"closed","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate"}}]'
out="$(STUB_DROP_KEYS="r-5:status" "$SUT" reopen r-5 2>&1)"; rc=$?
eq "$rc" 2 "a reopen that did not land exits 2 (read-back verification)"
has "$out" "status" "the unverified field is named"

out="$("$SUT" reopen r-nope 2>&1)"; rc=$?
eq "$rc" 2 "reopen on an unreadable bead exits 2"

}

echo "## arm: shell fallback (GCTK_BIN=none)"
export GCTK_BIN=none
drift_shell
suite

echo
echo "## arm: gctk lifecycle (reached through lifecycle.sh)"
if [ -n "$GCTK_BUILT" ]; then
    export GCTK_BIN="$GCTK_BUILT"
    drift_gctk
    suite
    # The arm proves nothing unless lifecycle.sh actually handed off. gctk's
    # usage text names itself; the fallback's does not.
    has "$("$SUT" 2>&1)" "gctk lifecycle" "lifecycle.sh execs the binary when GCTK_BIN resolves"
elif [ "$GO_PRESENT" -eq 0 ]; then
    bad "no Go toolchain: the gctk lifecycle port was NOT exercised, and this suite is its acceptance bar"
else
    bad "gctk did not build; the port was NOT exercised — $(tail -3 "$GCTK_BUILD_LOG" | tr '\n' ' ')"
fi

echo
echo "## arm: the city chain, with no GCTK_BIN to shortcut it"
# GC_CITY_PATH is the city root a supervisor puts in an agent session; GC_CITY
# and GC_CITY_ROOT are absent there. A resolver blind to it leaves every agent
# on the fallback, so the port ships and never runs in the shape most callers
# have. Reached with GCTK_BIN unset, which is how a real caller reaches it.
if [ -n "$GCTK_BUILT" ]; then
    CITY="$TMP/city"
    mkdir -p "$CITY/.gc/services/gctk/bin"
    cp "$GCTK_BUILT" "$CITY/.gc/services/gctk/bin/gctk"
    # gctk's usage names itself; the fallback's does not. Same discriminator the
    # gctk arm uses for the handoff.
    for VAR in GC_CITY_PATH GC_CITY GC_CITY_ROOT; do
        out=$(env -u GCTK_BIN -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT "$VAR=$CITY" "$SUT" 2>&1)
        has "$out" "gctk lifecycle" "$VAR alone resolves the deployed binary"
    done
    # The control: the same binary on disk, named by nothing.
    out=$(env -u GCTK_BIN -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT "$SUT" 2>&1)
    hasnt "$out" "gctk lifecycle" "no city named: the shell fallback answers"
else
    bad "gctk did not build; the city resolution chain was NOT exercised"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
