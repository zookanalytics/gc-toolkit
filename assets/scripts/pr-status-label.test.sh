#!/usr/bin/env bash
# pr-status-label.test.sh — hermetic tests for the workflow-owned PR labels: the
# status: derivation (anchor state -> working/needs-review/needs-attention), its
# mutually-exclusive set, ensure, and reconcile, and the sibling base: group
# (mark-base) that marks an integration checkpoint. No live city, gh, or network.
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
# derive: who must act next, read off the anchor's own state.
# Precedence needs-attention > working > needs-review.
# ---------------------------------------------------------------------------

# needs-review — settled at the head, nothing outstanding (a born gate-green PR).
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-review" "no rework, no hold, no approval => needs-review"

# working — an open rework child means the city is changing the PR.
store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "working" "an open rework child => working"

# needs-review — a CLOSED rework child no longer holds working (commit-scoped, not sticky).
store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-k","status":"closed","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-review" "a closed rework child hands back to needs-review"

# needs-review — a sticky changes_requested posture with no open rework does NOT trap
# the label in working (the whole point of resting the flip on the child).
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"changes_requested@abc123@2026-09-20T00:00:00Z"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-review" "sticky changes_requested + no open child => needs-review, not stuck working"

# working — changes_requested WITH an open rework child is the city reworking.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"changes_requested@abc123@t"}},
        {"id":"tk-k","status":"in_progress","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "working" "changes_requested + an open rework child => working"

# working — the in-flight set is ANY live bead anchored here, not just task_kind=rework.
# A human changes-requested batch travels the validation-pass path (task_kind=validation),
# which leaves no rework child; before the whole set was read it fell through to
# needs-review while the city was mid-change.
store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-v","status":"open","metadata":{"task_kind":"validation","anchor_bead":"tk-a","check_name":"human"}}]'
eq "$("$SUT" derive --anchor tk-a)" "working" "an open validation pass (human changes-requested batch) => working"

# working — an open finding on the anchor is live work too. This is the shape that
# stays open through a converse-held fold round (findings close only as their fix lands).
store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-f","status":"open","metadata":{"task_kind":"finding","anchor_bead":"tk-a","finding.lane":"human"}}]'
eq "$("$SUT" derive --anchor tk-a)" "working" "an open finding on the anchor => working"

# working — an in-flight review child (a re-review that will move the head) is live work.
store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-r","status":"in_progress","metadata":{"task_kind":"review","anchor_bead":"tk-a","check_name":"codex"}}]'
eq "$("$SUT" derive --anchor tk-a)" "working" "an in-flight review child => working"

# needs-review — a CLOSED validation pass no longer holds working (status-scoped, like the child).
store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-v","status":"closed","metadata":{"task_kind":"validation","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-review" "a closed validation pass hands back to needs-review"

# needs-review — the set is anchor-scoped: live work on ANOTHER anchor never flips this
# PR. A bare "any live bead" test without the anchor_bead filter would fail this.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request"}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-other"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-review" "live work anchored to another PR does not flip this one"

# needs-attention — the signoff round cap parked the anchor for a person.
store '[{"id":"tk-a","status":"open","metadata":{"merge_hold":"signoff_cap","signoff_cap":"codex"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "a signoff-cap park => needs-attention"

# needs-attention — an operator freeze is a hold the city stopped behind.
store '[{"id":"tk-a","status":"open","metadata":{"merge_hold":"true"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "an operator freeze (merge_hold=true) => needs-attention"

# needs-attention — a rebase hold is a hold too.
store '[{"id":"tk-a","status":"open","metadata":{"rebase_hold":"true"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "a rebase hold => needs-attention"

# working — approved and merging (merge state not BLOCKED): the city is landing it.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"CLEAN@abc"}}]'
eq "$("$SUT" derive --anchor tk-a)" "working" "approved + merging (CLEAN) => working"

# needs-attention — approved but wedged (BLOCKED) with no rework in flight.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"BLOCKED@abc"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "approved but wedged (BLOCKED), no live work => needs-attention"

# working — approved + BLOCKED but a rework child stands: the child is live work, so working wins.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"BLOCKED@abc"}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "working" "approved + BLOCKED + an open rework child => working (live work)"

# needs-review — a non-blocking review left comments; a human looks again.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"commented@abc@t"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-review" "posture commented, no rework => needs-review"

# precedence — a cap park outranks an open rework child.
store '[{"id":"tk-a","status":"open","metadata":{"merge_hold":"signoff_cap","signoff_cap":"codex"}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "needs-attention outranks working (cap park + open child)"

store '[]'
"$SUT" derive --anchor tk-a >/dev/null 2>&1
eq "$?" "2" "an unresolvable anchor exits 2 — derive never guesses a status"

# ---------------------------------------------------------------------------
# ensure: create the group's labels, idempotently.
# ---------------------------------------------------------------------------
rm -f "$STUB_GH_DIR/labels.json"
"$SUT" ensure --repo "$REPO" >/dev/null 2>&1
for v in working needs-review needs-attention; do
  { repo_has "status: $v" && ok "ensure creates 'status: $v'"; } || bad "ensure missed 'status: $v'"
done
BEFORE=$(jq 'length' "$STUB_GH_DIR/labels.json")
"$SUT" ensure --repo "$REPO" >/dev/null 2>&1
eq "$(jq 'length' "$STUB_GH_DIR/labels.json")" "$BEFORE" "ensure is idempotent (creates no duplicate)"

# ---------------------------------------------------------------------------
# set: adds the target, creating the label first (the labels do not exist yet).
# ---------------------------------------------------------------------------
rm -f "$STUB_GH_DIR/labels.json"
pv 42 '[{"name":"bug"}]'
resetlog
"$SUT" set --pr 42 --value needs-review --repo "$REPO" --current-labels "bug"
eq "$(pv_labels 42)" "bug,status: needs-review" "set adds the target label"
has "$(ghlog)" "label create" "set creates the missing label before adding it (the stub refuses an unknown label)"

# flip: mutual exclusion removes the old status value.
pv 42 '[{"name":"status: working"},{"name":"bug"}]'
resetlog
"$SUT" set --pr 42 --value needs-review --repo "$REPO" --current-labels "status: working,bug"
eq "$(pv_labels 42)" "bug,status: needs-review" "flip adds needs-review and removes working"

# no-op when the target is already the only status label.
pv 42 '[{"name":"status: needs-review"},{"name":"bug"}]'
resetlog
"$SUT" set --pr 42 --value needs-review --repo "$REPO" --current-labels "status: needs-review,bug"
hasnt "$(ghlog)" "pr edit" "set is a no-op when the label is already correct (no churn every pass)"

# mutual exclusion removes EVERY other status value, including a future one.
pv 42 '[{"name":"status: self-checked"},{"name":"status: working"}]'
resetlog
"$SUT" set --pr 42 --value needs-review --repo "$REPO" --current-labels "status: self-checked,status: working"
eq "$(pv_labels 42)" "status: needs-review" "one value at a time: a future status value is removed too, no redesign"

# set rejects a value outside the group.
resetlog
"$SUT" set --pr 42 --value in-rework --repo "$REPO" --current-labels "bug" >/dev/null 2>&1
eq "$?" "1" "set refuses a value outside the group"
hasnt "$(ghlog)" "pr edit" "set writes nothing for a refused value"

# set reads the PR's labels itself when --current-labels is omitted.
printf '[{"name":"status: working"},{"name":"status: needs-review"}]\n' > "$STUB_GH_DIR/labels.json"
pv 43 '[{"name":"status: working"}]'
resetlog
"$SUT" set --pr 43 --value needs-review --repo "$REPO"
eq "$(pv_labels 43)" "status: needs-review" "set reads the PR labels itself when they are not passed in"

# ---------------------------------------------------------------------------
# reconcile: derive then set — the self-healing every-pass projection.
# ---------------------------------------------------------------------------
store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
pv 50 '[{"name":"status: needs-review"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 50 --repo "$REPO" --current-labels "status: needs-review"
eq "$(pv_labels 50)" "status: working" "reconcile self-heals a stale label when a rework child is open"

# reconcile leaves the label untouched when it cannot derive a state.
store '[]'
pv 51 '[{"name":"status: needs-review"}]'
resetlog
"$SUT" reconcile --anchor tk-missing --pr 51 --repo "$REPO" --current-labels "status: needs-review"
eq "$(pv_labels 51)" "status: needs-review" "reconcile leaves the label as-is when the anchor does not resolve"
hasnt "$(ghlog)" "pr edit" "reconcile writes nothing when it cannot derive a status"

# ---------------------------------------------------------------------------
# mark-base: the sibling `base:` group, stamped from the target at pr-open.
# Standing (never derived from anchor state), additive, and orthogonal to status:.
# ---------------------------------------------------------------------------

# an integration/ target earns base: integration, the label created first.
rm -f "$STUB_GH_DIR/labels.json"
pv 60 '[]'
resetlog
"$SUT" mark-base --pr 60 --target "integration/tk-conv" --repo "$REPO"
eq "$(pv_labels 60)" "base: integration" "mark-base stamps base: integration on an integration/ target"
has "$(ghlog)" "label create" "…creating the label first (the stub refuses an unknown label)"
{ repo_has "base: integration" && ok "the base: integration label now exists in the repo"; } || bad "base: integration not created"

# a main target is the default: no label created, no PR edit.
rm -f "$STUB_GH_DIR/labels.json"
pv 61 '[]'
resetlog
"$SUT" mark-base --pr 61 --target "main" --repo "$REPO"
eq "$(pv_labels 61)" "" "mark-base is a no-op on a main target"
hasnt "$(ghlog)" "pr edit" "…writing nothing"
hasnt "$(ghlog)" "label create" "…and creating no label"

# orthogonal: the base marker adds alongside a status value, removing neither.
printf '[{"name":"status: needs-review"},{"name":"base: integration"}]\n' > "$STUB_GH_DIR/labels.json"
pv 62 '[{"name":"status: needs-review"}]'
resetlog
"$SUT" mark-base --pr 62 --target "integration/tk-conv" --repo "$REPO"
eq "$(pv_labels 62)" "base: integration,status: needs-review" "mark-base adds base: alongside status:, removing neither"

# and the status writer, flipping its own value, leaves the sibling base: label alone.
pv 62 '[{"name":"status: working"},{"name":"base: integration"}]'
resetlog
"$SUT" set --pr 62 --value needs-review --repo "$REPO" --current-labels "status: working,base: integration"
eq "$(pv_labels 62)" "base: integration,status: needs-review" "set flips status: and never touches the sibling base: label"

# idempotent: a second mark-base adds no duplicate.
printf '[{"name":"base: integration"}]\n' > "$STUB_GH_DIR/labels.json"
pv 63 '[{"name":"base: integration"}]'
resetlog
"$SUT" mark-base --pr 63 --target "integration/tk-conv" --repo "$REPO"
eq "$(pv_labels 63)" "base: integration" "mark-base is idempotent — a present label is a no-op add"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
