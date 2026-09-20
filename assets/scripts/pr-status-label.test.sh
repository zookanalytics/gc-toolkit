#!/usr/bin/env bash
# pr-status-label.test.sh — hermetic tests for the workflow-owned `status:` PR
# label: the derivation (rework state -> in-rework/ready-for-review), the
# mutually-exclusive set, ensure, and reconcile. No live city, gh, or network.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-prlabel-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
unset GC_RIG 2>/dev/null || true
harness_init
SUT="$HERE/pr-status-label.sh"
REPO="github.com/zook/gc-toolkit"

pv() { # <num> <labels-json-array> — a pr_view fixture carrying those labels
  printf '{"number":%s,"state":"OPEN","isDraft":false,"labels":%s}\n' "$1" "$2" \
    > "$STUB_GH_DIR/pr_view_$1.json"
}
pv_labels() { jq -r '[.labels[].name] | sort | join(",")' "$STUB_GH_DIR/pr_view_$1.json"; }
repo_has() { jq -e --arg n "$1" 'any(.[]?; .name == $n)' "$STUB_GH_DIR/labels.json" >/dev/null 2>&1; }
ghlog() { cat "$STUB_GH_LOG"; }
resetlog() { : > "$STUB_GH_LOG"; }

# ---------------------------------------------------------------------------
# derive: the human-attention signal is the city's own rework state.
# ---------------------------------------------------------------------------
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request"}}]'
eq "$("$SUT" derive --anchor tk-a)" "ready-for-review" "no rework child, no cap => ready-for-review"

store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "in-rework" "an open rework child => in-rework"

store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-k","status":"closed","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "ready-for-review" "a CLOSED rework child no longer holds in-rework (non-sticky)"

store '[{"id":"tk-a","status":"open","metadata":{"merge_hold":"signoff_cap"}}]'
eq "$("$SUT" derive --anchor tk-a)" "in-rework" "a signoff-cap park => in-rework"

store '[{"id":"tk-a","status":"open","metadata":{"merge_hold":"true"}}]'
eq "$("$SUT" derive --anchor tk-a)" "ready-for-review" "an operator freeze (merge_hold=true) is not in-rework"

store '[]'
"$SUT" derive --anchor tk-a >/dev/null 2>&1
eq "$?" "2" "an unresolvable anchor exits 2 — derive never guesses a status"

# ---------------------------------------------------------------------------
# ensure: create the group's labels, idempotently.
# ---------------------------------------------------------------------------
rm -f "$STUB_GH_DIR/labels.json"
"$SUT" ensure --repo "$REPO" >/dev/null 2>&1
{ repo_has "status: in-rework" && ok "ensure creates 'status: in-rework'"; } || bad "ensure missed 'status: in-rework'"
{ repo_has "status: ready-for-review" && ok "ensure creates 'status: ready-for-review'"; } || bad "ensure missed 'status: ready-for-review'"
BEFORE=$(jq 'length' "$STUB_GH_DIR/labels.json")
"$SUT" ensure --repo "$REPO" >/dev/null 2>&1
eq "$(jq 'length' "$STUB_GH_DIR/labels.json")" "$BEFORE" "ensure is idempotent (creates no duplicate)"

# ---------------------------------------------------------------------------
# set: adds the target, creating the label first (the labels do not exist yet).
# ---------------------------------------------------------------------------
rm -f "$STUB_GH_DIR/labels.json"
pv 42 '[{"name":"bug"}]'
resetlog
"$SUT" set --pr 42 --value ready-for-review --repo "$REPO" --current-labels "bug"
eq "$(pv_labels 42)" "bug,status: ready-for-review" "set adds the target label"
has "$(ghlog)" "label create" "set creates the missing label before adding it (the stub refuses an unknown label)"

# flip: mutual exclusion removes the old status value.
pv 42 '[{"name":"status: in-rework"},{"name":"bug"}]'
resetlog
"$SUT" set --pr 42 --value ready-for-review --repo "$REPO" --current-labels "status: in-rework,bug"
eq "$(pv_labels 42)" "bug,status: ready-for-review" "flip adds ready-for-review and removes in-rework"

# no-op when the target is already the only status label.
pv 42 '[{"name":"status: ready-for-review"},{"name":"bug"}]'
resetlog
"$SUT" set --pr 42 --value ready-for-review --repo "$REPO" --current-labels "status: ready-for-review,bug"
hasnt "$(ghlog)" "pr edit" "set is a no-op when the label is already correct (no churn every pass)"

# mutual exclusion removes EVERY other status value, including a future one.
pv 42 '[{"name":"status: in-review"},{"name":"status: in-rework"}]'
resetlog
"$SUT" set --pr 42 --value ready-for-review --repo "$REPO" --current-labels "status: in-review,status: in-rework"
eq "$(pv_labels 42)" "status: ready-for-review" "one value at a time: a future status value is removed too, no redesign"

# set reads the PR's labels itself when --current-labels is omitted.
printf '[{"name":"status: in-rework"},{"name":"status: ready-for-review"}]\n' > "$STUB_GH_DIR/labels.json"
pv 43 '[{"name":"status: in-rework"}]'
resetlog
"$SUT" set --pr 43 --value ready-for-review --repo "$REPO"
eq "$(pv_labels 43)" "status: ready-for-review" "set reads the PR labels itself when they are not passed in"

# ---------------------------------------------------------------------------
# reconcile: derive then set — the self-healing every-pass projection.
# ---------------------------------------------------------------------------
store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
pv 50 '[{"name":"status: ready-for-review"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 50 --repo "$REPO" --current-labels "status: ready-for-review"
eq "$(pv_labels 50)" "status: in-rework" "reconcile self-heals a stale ready label when a rework child is open"

# reconcile leaves the label untouched when it cannot derive a state.
store '[]'
pv 51 '[{"name":"status: ready-for-review"}]'
resetlog
"$SUT" reconcile --anchor tk-missing --pr 51 --repo "$REPO" --current-labels "status: ready-for-review"
eq "$(pv_labels 51)" "status: ready-for-review" "reconcile leaves the label as-is when the anchor does not resolve"
hasnt "$(ghlog)" "pr edit" "reconcile writes nothing when it cannot derive a status"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
