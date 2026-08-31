#!/usr/bin/env bash
# Hermetic test for assets/scripts/lifecycle.sh — the one writer of lifecycle
# transitions. Covers: the state verb; legal/illegal edges; --expect; the ONE
# atomic `gc bd update` carrying every field; bd refusal (exit 1); post-write
# verification mismatch (exit 2); human states routing to human and detached
# states clearing the route, both in the same call; the empty-route refusal that
# keeps a human state from waiting on nobody; the `held` sitting-hold state; the
# close/terminal pairing guards (--close only into a closed state, closed states
# must --close); the reopen repair verb; and the drift assertion between
# lifecycle/lifecycle.toml and the embedded lifecycle-state-table block.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/lifecycle.sh"
TOML="$ROOT/lifecycle/lifecycle.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init
[ -x "$SUT" ] || chmod +x "$SUT"

# --- drift: the embedded table IS lifecycle.toml -------------------------------
echo "# drift against lifecycle.toml"
BLOCK="$(awk '/# >>> lifecycle-state-table/{f=1;next} /# <<< lifecycle-state-table/{f=0} f' "$SUT")"
[ -n "$BLOCK" ] && ok "state-table block extracted" || bad "state-table markers missing"
eval "$BLOCK"

TOML_STATES=$(awk '/^states = \[/{f=1;next} f&&/^\]/{exit} f{gsub(/[ ",]/,"");print}' "$TOML" | tr '\n' ' ' | sed 's/ $//')
eq "$LIFECYCLE_STATES" "$TOML_STATES" "states match lifecycle.toml"
TOML_HUMAN=$(sed -n 's/^human_states = \[\(.*\)\]/\1/p' "$TOML" | tr -d '",' )
eq "$(printf '%s' "$LIFECYCLE_HUMAN_STATES" | tr -s ' ')" "$(printf '%s' "$TOML_HUMAN" | sed 's/^ *//;s/ *$//' | tr -s ' ')" "human states match lifecycle.toml"
TOML_DETACHED=$(sed -n 's/^detached_states = \[\(.*\)\]/\1/p' "$TOML" | tr -d '",' )
eq "$(printf '%s' "$LIFECYCLE_DETACHED_STATES" | tr -s ' ')" "$(printf '%s' "$TOML_DETACHED" | sed 's/^ *//;s/ *$//' | tr -s ' ')" "detached states match lifecycle.toml"
TOML_PARK=$(sed -n 's/^park_route = "\(.*\)"/\1/p' "$TOML")
eq "$LIFECYCLE_PARK_ROUTE" "$TOML_PARK" "park route matches lifecycle.toml"
TOML_CLOSED=$(sed -n 's/^closed_states = \[\(.*\)\]/\1/p' "$TOML" | tr -d '", ')
eq "$LIFECYCLE_CLOSED_STATES" "$TOML_CLOSED" "closed states match lifecycle.toml"
TOML_EDGES=$(awk '
  /^\[\[transition\]\]/ { from=""; to="" }
  /^from = /  { gsub(/from = |"/,""); from=$0 }
  /^to = /    { gsub(/to = |"/,""); to=$0; print from ">" to }' "$TOML" | sort)
SH_EDGES=$(printf '%s\n' "$LIFECYCLE_TRANSITIONS" | sed '/^$/d' | sort)
eq "$SH_EDGES" "$TOML_EDGES" "transition edges match lifecycle.toml"

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
  --set blocked_reason="PR#7 closed out-of-band" 2>&1)"; rc=$?
eq "$rc" 0 "transition to abandoned exits 0"
eq "$(meta a-6 'gc.routed_to')" "human" "abandoned routes to human automatically"
eq "$(bassignee a-6)" "" "--assignee '' cleared the assignee"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "1" "route + clear + reason ride in ONE update"

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

store '[{"id":"h-3","status":"open","assignee":"","notes":"","metadata":{"merge_result":"held","gc.routed_to":"human"}}]'
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

store '[{"id":"r-4","status":"closed","assignee":"","notes":"","metadata":{}}]'
out="$("$SUT" reopen r-4 2>&1)"; rc=$?
eq "$rc" 1 "reopen refuses a closed unanchored bead (a legal closed shape)"

store '[{"id":"r-5","status":"closed","assignee":"","notes":"","metadata":{"merge_result":"pre_open_gate"}}]'
out="$(STUB_DROP_KEYS="r-5:status" "$SUT" reopen r-5 2>&1)"; rc=$?
eq "$rc" 2 "a reopen that did not land exits 2 (read-back verification)"
has "$out" "status" "the unverified field is named"

out="$("$SUT" reopen r-nope 2>&1)"; rc=$?
eq "$rc" 2 "reopen on an unreadable bead exits 2"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
