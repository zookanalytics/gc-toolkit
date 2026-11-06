#!/usr/bin/env bash
# pr-status-label.test.sh — hermetic tests for the workflow-owned status: PR
# label: its derivation (anchor state -> working, merging, needs-review or
# needs-attention), its mutually-exclusive set, ensure, reconcile, and the clear
# that takes it off a PR that merged or closed. No live city, gh, or network.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-prlabel-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
unset GC_RIG 2>/dev/null || true
harness_init
SUT="$HERE/pr-status-label.sh"
REPO="github.com/zook/gc-toolkit"

# The derivation is `gctk pr-status` (services/gctk); this script
# reaches it and computes nothing itself, so the derive and reconcile cases
# below exercise the binary. Build it and point GCTK_BIN at it, overriding the
# harness's GCTK_BIN=none. gctk shells out to the same stubbed `gc`, so the
# store fixtures serve it unchanged. There is no shell fallback to fall back on,
# so no Go toolchain means the only code path was NOT exercised: fail loud.
ROOT="$(cd "$HERE/../.." && pwd)"
GCTK_BUILD_LOG="$TMP/gctk-build.log"
if command -v go >/dev/null 2>&1 && ( cd "$ROOT/services/gctk" && go build -buildvcs=false -o "$TMP/gctk" ./cmd/gctk ) >"$GCTK_BUILD_LOG" 2>&1; then
  export GCTK_BIN="$TMP/gctk"
else
  bad "gctk did not build; pr-status derive is gctk-only and was NOT exercised — $(tail -3 "$GCTK_BUILD_LOG" 2>/dev/null | tr '\n' ' ')"
fi

pv() { # <num> <labels-json-array> — a pr_view fixture carrying those labels
  printf '{"number":%s,"state":"OPEN","isDraft":false,"labels":%s}\n' "$1" "$2" \
    > "$STUB_GH_DIR/pr_view_$1.json"
}
pv_labels() { jq -r '[.labels[].name] | sort | join(",")' "$STUB_GH_DIR/pr_view_$1.json"; }
repo_has() { jq -e --arg n "$1" 'any(.[]?; .name == $n)' "$STUB_GH_DIR/labels.json" >/dev/null 2>&1; }
ghlog() { cat "$STUB_GH_LOG"; }
resetlog() { : > "$STUB_GH_LOG"; }

# ---------------------------------------------------------------------------
# derive: whose move it is, read off the anchor's own state.
# Precedence needs-attention > merging > working > needs-review.
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

# needs-attention — an operator freeze is a hold the city stopped behind.
store '[{"id":"tk-a","status":"open","metadata":{"merge_hold":"true"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "an operator freeze (merge_hold=true) => needs-attention"

# needs-attention — a rebase hold is a hold too.
store '[{"id":"tk-a","status":"open","metadata":{"rebase_hold":"true"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "a rebase hold => needs-attention"

# merging — approved, and the merge pass is landing it: the city has it.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr.machine":"settled@abc@t"}}]'
eq "$("$SUT" derive --anchor tk-a)" "merging" "approved, the merge pass settled => merging"

# merging — GitHub's BLOCKED covers a required check still running, so it is not
# read: the merge pass's verdict is. Here it is still waiting on the check.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"BLOCKED@abc","pr.machine":"progressing@abc@t"}}]'
eq "$("$SUT" derive --anchor tk-a)" "merging" "approved + BLOCKED while a required check runs (progressing) => merging, not needs-attention"

# needs-attention — the merge pass recorded blocked at the head the posture was read at.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"check-failed"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "approved, blocked by the merge pass, no live work => needs-attention"

# merging — a blocked verdict at a head the PR has left was about another commit.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@def@t","pr.machine":"blocked@abc@t","pr.machine_cause":"check-failed"}}]'
eq "$("$SUT" derive --anchor tk-a)" "merging" "a blocked verdict at an earlier head => merging"

# merging — a blocked verdict with city work in flight on its cause: the fix is moving.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"check-failed"}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "merging" "approved + blocked + an open rework child on the cause => merging (live work)"

# needs-attention — the blocker cause holds the PR whatever is in flight beside it.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"blocker"}},
        {"id":"tk-f","status":"open","metadata":{"task_kind":"finding","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "the blocker cause beside live work => needs-attention"

# needs-attention — a recorded value the derivation has no word for.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"dismissed@abc@t"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "a posture outside the vocabulary => needs-attention"

# needs-review — a non-blocking review left comments; a human looks again.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"commented@abc@t"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-review" "posture commented, no rework => needs-review"

# working — a draft the city opened (opened_as_draft, no draft_readied) still owes
# the checks that flip it ready, so it is not up for review with nothing in flight.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","opened_as_draft":"abc123"}}]'
eq "$("$SUT" derive --anchor tk-a)" "working" "a draft the city opened, not yet readied => working"

# needs-review — once pr-open.sh records draft_readied, the draft is up for review.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","opened_as_draft":"abc123","draft_readied":"abc123"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-review" "a readied draft with nothing in flight => needs-review"

# needs-attention — a hold outranks the draft stage, as it does live work.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","opened_as_draft":"abc123","merge_hold":"true"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "a held draft => needs-attention"

# precedence — a hold outranks an open rework child.
store '[{"id":"tk-a","status":"open","metadata":{"merge_hold":"true"}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "needs-attention outranks working (hold + open child)"

# needs-attention — an open human gate that blocks the anchor is a hold: the
# merge pass refuses the merge while it stands, so an approved PR that would
# otherwise read merging (here conflicting, DIRTY) waits on a person.
GATE='{"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","await_id":"pr-comments.7.x","title":"answer the review","metadata":{}}'
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"DIRTY@abc"}},
        '"$GATE"']'
printf 'tk-g|blocks|tk-a\n' > "$STUB_DEPS"
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "an open human gate on an approved PR => needs-attention, not working"

# needs-attention — a gate in any status but closed holds the PR.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"CLEAN@abc"}},
        {"id":"tk-g","status":"in_progress","issue_type":"gate","await_type":"human","metadata":{}}]'
printf 'tk-g|blocks|tk-a\n' > "$STUB_DEPS"
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "an in_progress human gate => needs-attention"

# precedence — an open human gate outranks an open rework child.
store '[{"id":"tk-a","status":"open","metadata":{}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}},
        '"$GATE"']'
printf 'tk-g|blocks|tk-a\n' > "$STUB_DEPS"
eq "$("$SUT" derive --anchor tk-a)" "needs-attention" "needs-attention outranks working (open human gate + open child)"

# merging — a CLEARED gate no longer holds the PR.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"DIRTY@abc"}},
        {"id":"tk-g","status":"closed","issue_type":"gate","await_type":"human","metadata":{}}]'
printf 'tk-g|blocks|tk-a\n' > "$STUB_DEPS"
eq "$("$SUT" derive --anchor tk-a)" "merging" "a cleared gate releases the PR back to merging"

# merging — the gate is anchor-scoped: a gate that blocks another bead never
# holds this PR.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"CLEAN@abc"}},
        '"$GATE"']'
printf 'tk-g|blocks|tk-other\n' > "$STUB_DEPS"
eq "$("$SUT" derive --anchor tk-a)" "merging" "a gate on another bead does not hold this PR"

# merging — only a human gate holds: a gate with no await type, and a task that
# blocks the anchor, are not one.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"CLEAN@abc"}},
        {"id":"tk-p","status":"open","issue_type":"gate","metadata":{}},
        {"id":"tk-t","status":"open","issue_type":"task","metadata":{}}]'
printf 'tk-p|blocks|tk-a\ntk-t|blocks|tk-a\n' > "$STUB_DEPS"
eq "$("$SUT" derive --anchor tk-a)" "merging" "a gate with no await type and a blocking task do not hold the PR"

# merging — a bead that tracks the anchor blocks nothing: a visit, a
# conversation or a first reaction holds no PR.
store '[{"id":"tk-a","status":"open","metadata":{"pr_posture":"approved@abc@t","pr_merge_state":"CLEAN@abc"}},
        {"id":"tk-v","status":"open","metadata":{"task_kind":"visit","gc.continuation_group":"tk-a","gc.routed_to":"human"}},
        {"id":"tk-r","status":"open","metadata":{"task_kind":"reaction"}}]'
printf 'tk-v|tracks|tk-a\ntk-r|tracks|tk-a\n' > "$STUB_DEPS"
eq "$("$SUT" derive --anchor tk-a)" "merging" "a bead that tracks the anchor does not hold the PR"
: > "$STUB_DEPS"

# The gate read is scoped to the anchor, the way the finalize gate reads it: the
# beads its blocks edges reach. It never lists visits, or every gate, in the store.
: > "$STUB_GC_LOG"
"$SUT" derive --anchor tk-a >/dev/null 2>&1
grep -qF 'bd dep list tk-a --type blocks' "$STUB_GC_LOG"; eq "$?" "0" "the derive reads the anchor's blocks blockers"
grep -qF 'task_kind=visit' "$STUB_GC_LOG"; eq "$?" "1" "the derive makes no store-wide read of the open visits"
grep -qF 'gc.continuation_group' "$STUB_GC_LOG"; eq "$?" "1" "the derive reads no continuation-group stamp"

store '[]'
"$SUT" derive --anchor tk-a >/dev/null 2>&1
eq "$?" "2" "an unresolvable anchor exits 2 — derive never guesses a status"

# ---------------------------------------------------------------------------
# ensure: create the group's labels, idempotently.
# ---------------------------------------------------------------------------
rm -f "$STUB_GH_DIR/labels.json"
"$SUT" ensure --repo "$REPO" >/dev/null 2>&1
for v in working merging needs-review needs-attention; do
  { repo_has "status: $v" && ok "ensure creates 'status: $v'"; } || bad "ensure missed 'status: $v'"
done
BEFORE=$(jq 'length' "$STUB_GH_DIR/labels.json")
resetlog
"$SUT" ensure --repo "$REPO" >/dev/null 2>&1
eq "$(jq 'length' "$STUB_GH_DIR/labels.json")" "$BEFORE" "ensure is idempotent (creates no duplicate)"
hasnt "$(ghlog)" "label edit" "…and edits no label whose description is already right"

# ensure corrects a description that no longer says what its value means: the
# working label once also covered an approved PR being merged.
jq '(.[] | select(.name == "status: working") | .description) = "Workflow: the city holds the ball — rework or merge in flight; no human input needed."' \
  "$STUB_GH_DIR/labels.json" > "$STUB_GH_DIR/labels.tmp" && mv "$STUB_GH_DIR/labels.tmp" "$STUB_GH_DIR/labels.json"
resetlog
"$SUT" ensure --repo "$REPO" >/dev/null 2>&1
has "$(ghlog)" "label edit status: working" "ensure corrects a stale description"
hasnt "$(ghlog)" "label edit status: needs-review" "…and leaves a right one alone"
eq "$(jq -r '.[] | select(.name == "status: working") | .description' "$STUB_GH_DIR/labels.json")" \
  "Workflow: the city is changing the PR or readying its draft; no human input needed." "…to the description the value has now"

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

# set takes merging, the value an approved PR the city is landing carries.
pv 44 '[{"name":"status: working"}]'
resetlog
"$SUT" set --pr 44 --value merging --repo "$REPO" --current-labels "status: working"
eq "$(pv_labels 44)" "status: merging" "set flips working to merging"

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
# held: what holds an open PR that the city will not clear on its own, one
# label per value beside the one status: value. reconcile writes both families
# from one derivation, and any held value reads status: needs-attention.
# ---------------------------------------------------------------------------
rm -f "$STUB_GH_DIR/labels.json"
"$SUT" ensure --repo "$REPO" >/dev/null 2>&1
for v in gate review blocked; do
  { repo_has "held: $v" && ok "ensure creates 'held: $v'"; } || bad "ensure missed 'held: $v'"
done
rm -f "$STUB_GH_DIR/labels.json"
resetlog
"$SUT" ensure --repo "$REPO" >/dev/null 2>&1
has "$(ghlog)" "label create held: gate --repo $REPO --color D93F0B" "the held: labels take a colour of their own"
has "$(ghlog)" "label create status: working --repo $REPO --color 1D76DB" "…apart from the status: group's"

# a PR nothing holds carries no held: label.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"settled@abc@t"}}]'
: > "$STUB_DEPS"
pv 70 '[{"name":"bug"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 70 --repo "$REPO" --current-labels "bug"
eq "$(pv_labels 70)" "bug,status: merging" "a PR nothing holds gets its status: label and no held: label"

# held: gate — an open human gate on the anchor holds it, though its rework is
# live work the city would otherwise be doing.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request"}},
        {"id":"tk-k","status":"in_progress","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}},
        {"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","metadata":{}}]'
printf 'tk-g|blocks|tk-a\n' > "$STUB_DEPS"
pv 71 '[{"name":"status: working"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 71 --repo "$REPO" --current-labels "status: working"
eq "$(pv_labels 71)" "held: gate,status: needs-attention" "a human gate on the anchor beside its rework => held: gate, and status: needs-attention"
eq "$(grep -c 'pr edit 71' "$STUB_GH_LOG")" "1" "…written in one edit"

# the same PR re-reconciled over an unchanged store writes nothing.
resetlog
"$SUT" reconcile --anchor tk-a --pr 71 --repo "$REPO" --current-labels "held: gate,status: needs-attention"
hasnt "$(ghlog)" "pr edit" "a reconcile over labels already right writes nothing"

# the gate is cleared: held: gate comes off and the status follows the rework.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request"}},
        {"id":"tk-k","status":"in_progress","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}},
        {"id":"tk-g","status":"closed","issue_type":"gate","await_type":"human","metadata":{}}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 71 --repo "$REPO" --current-labels "held: gate,status: needs-attention"
eq "$(pv_labels 71)" "status: working" "the gate cleared => held: gate comes off, and the PR reads working again"
: > "$STUB_DEPS"

# held: blocked — a live blocker routed to a person, which no automated actor clears.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"settled@abc@t"}},
        {"id":"tk-d","status":"open","metadata":{"gc.routed_to":"human"}}]'
printf 'tk-d|blocks|tk-a\n' > "$STUB_DEPS"
pv 72 '[{"name":"status: merging"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 72 --repo "$REPO" --current-labels "status: merging"
eq "$(pv_labels 72)" "held: blocked,status: needs-attention" "a blocker a person owes => held: blocked, and needs-attention over merging"

# a blocker the city is landing is no hold, and the PR keeps its status.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"settled@abc@t"}},
        {"id":"tk-d","status":"open","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 72 --repo "$REPO" --current-labels "held: blocked,status: needs-attention"
eq "$(pv_labels 72)" "status: merging" "a blocker a pool is landing => held: blocked comes off, and the PR reads merging"
: > "$STUB_DEPS"

# held: blocked off the merge pass's stuck-blocker verdict, and held: review off
# its unresolved-thread verdict, both at the posture's head.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"blocker"}}]'
pv 73 '[]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 73 --repo "$REPO" --current-labels ""
eq "$(pv_labels 73)" "held: blocked,status: needs-attention" "the merge pass's stuck-blocker verdict => held: blocked"
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"review-threads"}}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 73 --repo "$REPO"
eq "$(pv_labels 73)" "held: review,status: needs-attention" "the merge pass's unresolved-thread verdict => held: review, held: blocked off"

# a failed check reads needs-attention and names no hold.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"check-failed"}}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 73 --repo "$REPO"
eq "$(pv_labels 73)" "status: needs-attention" "a failed required check => needs-attention with no held: label"

# held: review off review feedback the city has not answered, which holds an
# unapproved PR on a base that requires no thread resolution: the merge pass
# counted a thread no post of the city's answers, and nothing is in flight.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"review_required@abc@t","pr.machine":"settled@abc@t","pr.unanswered_threads":"1@abc"}}]'
pv 79 '[{"name":"status: needs-review"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 79 --repo "$REPO" --current-labels "status: needs-review"
eq "$(pv_labels 79)" "held: review,status: needs-attention" "feedback the city has not answered => held: review, and needs-attention over needs-review"

# a rework in flight is the city answering it, so the count holds nothing while it runs.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"review_required@abc@t","pr.machine":"progressing@abc@t","pr.unanswered_threads":"1@abc"}},
        {"id":"tk-k","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 79 --repo "$REPO" --current-labels "held: review,status: needs-attention"
eq "$(pv_labels 79)" "status: working" "a rework in flight to answer it => held: review comes off, and the PR reads working"

# the thread answered or resolved: the merge pass counts none, and the PR is
# the operator's to review again.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"review_required@abc@t","pr.machine":"settled@abc@t","pr.unanswered_threads":"0@abc"}}]'
pv 80 '[{"name":"held: review"},{"name":"status: needs-attention"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 80 --repo "$REPO" --current-labels "held: review,status: needs-attention"
eq "$(pv_labels 80)" "status: needs-review" "the feedback answered or resolved => held: review comes off, and the PR reads needs-review"

# more than one value stands at once, each its own label.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"review-threads"}},
        {"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","metadata":{}},
        {"id":"tk-d","status":"open","issue_type":"decision","metadata":{}}]'
printf 'tk-d|blocks|tk-a\ntk-g|blocks|tk-a\n' > "$STUB_DEPS"
pv 74 '[{"name":"status: merging"},{"name":"bug"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 74 --repo "$REPO" --current-labels "status: merging,bug"
eq "$(pv_labels 74)" "bug,held: blocked,held: gate,held: review,status: needs-attention" "a human gate, a thread verdict and a decision blocker => three held: labels"
: > "$STUB_DEPS"

# the merge freeze reads needs-attention with no held value, and a stale held:
# label comes off.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","merge_hold":"true"}}]'
pv 75 '[{"name":"held: visit"},{"name":"status: needs-attention"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 75 --repo "$REPO" --current-labels "held: visit,status: needs-attention"
eq "$(pv_labels 75)" "status: needs-attention" "the merge freeze => needs-attention, and a stale held: visit from before the cutover comes off"

# a held: label of a value the writer does not derive comes off, as a status:
# one does; a label that only looks like one is a human's and stays.
store '[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request"}}]'
pv 76 '[{"name":"held: legal"},{"name":"held:visit"},{"name":"release held: legal"},{"name":"on hold"}]'
resetlog
"$SUT" reconcile --anchor tk-a --pr 76 --repo "$REPO" --current-labels "held: legal,held:visit,release held: legal,on hold"
eq "$(pv_labels 76)" "held:visit,on hold,release held: legal,status: needs-review" "every label under the held: prefix is the writer's; one carrying it mid-name, or no space, is left alone"

# a derivation that cannot answer leaves both families as they are.
store '[]'
pv 77 '[{"name":"held: visit"},{"name":"status: needs-attention"}]'
resetlog
"$SUT" reconcile --anchor tk-missing --pr 77 --repo "$REPO" --current-labels "held: visit,status: needs-attention"
eq "$(pv_labels 77)" "held: visit,status: needs-attention" "reconcile leaves both families as they are when the anchor does not resolve"
hasnt "$(ghlog)" "pr edit" "…and writes nothing"

# set writes the status: value alone and leaves the held: labels to reconcile.
pv 78 '[{"name":"held: blocked"},{"name":"status: working"}]'
resetlog
"$SUT" set --pr 78 --value needs-attention --repo "$REPO" --current-labels "held: blocked,status: working"
eq "$(pv_labels 78)" "held: blocked,status: needs-attention" "set flips the status: value and leaves held: alone"

# ---------------------------------------------------------------------------
# clear: a PR that merged or closed carries no status: label; GitHub's own
# Merged or Closed state takes over.
# ---------------------------------------------------------------------------
pv 60 '[{"name":"status: merging"},{"name":"bug"}]'
resetlog
"$SUT" clear --pr 60 --repo "$REPO" --current-labels "status: merging,bug"
eq "$?" "0" "clear exits 0"
eq "$(pv_labels 60)" "bug" "clear takes the status: label off and leaves the rest"

pv 61 '[{"name":"status: working"},{"name":"status: needs-review"},{"name":"bug"}]'
resetlog
"$SUT" clear --pr 61 --repo "$REPO"
eq "$(pv_labels 61)" "bug" "clear reads the PR's labels itself and takes every status: label off"

pv 62 '[{"name":"bug"}]'
resetlog
"$SUT" clear --pr 62 --repo "$REPO" --current-labels "bug"
hasnt "$(ghlog)" "pr edit" "clear writes nothing on a PR with no status: label"

pv 64 '[{"name":"status: needs-attention"},{"name":"held: visit"},{"name":"held: blocked"},{"name":"bug"}]'
resetlog
"$SUT" clear --pr 64 --repo "$REPO"
eq "$(pv_labels 64)" "bug" "clear takes every held: label off with the status: label"

pv 65 '[{"name":"held: review"}]'
resetlog
"$SUT" clear --pr 65 --repo "$REPO" --current-labels "held: review"
eq "$(pv_labels 65)" "" "clear takes a held: label off a PR that carries no status: label"

resetlog
"$SUT" clear --pr 63 --repo "$REPO" >/dev/null 2>&1
eq "$?" "2" "clear exits 2 when the PR's labels cannot be read"
hasnt "$(ghlog)" "pr edit" "…and writes nothing"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
