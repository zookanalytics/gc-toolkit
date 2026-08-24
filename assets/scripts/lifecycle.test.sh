#!/usr/bin/env bash
# Hermetic test for assets/scripts/lifecycle.sh — the one writer of lifecycle
# transitions. Covers: the state verb; legal/illegal edges; --expect; the ONE
# atomic `gc bd update` carrying every field; bd refusal (exit 1); post-write
# verification mismatch (exit 2); human states routing to human in the same
# call; and the drift assertion between lifecycle/lifecycle.toml and the
# embedded lifecycle-state-table block.
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

store '[{"id":"a-7","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}]'
"$SUT" transition a-7 --to retargeted --route rig/mechanik >/dev/null 2>&1
eq "$(meta a-7 'gc.routed_to')" "rig/mechanik" "an explicit --route overrides the human default"

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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
