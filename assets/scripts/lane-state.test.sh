#!/usr/bin/env bash
# lane-state.test.sh — hermetic tests for the green derivation.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lane-state-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
unset GC_RIG 2>/dev/null || true
harness_init
SUT="$HERE/lane-state.sh"

ANCHOR='{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness","pr_number":"42"}}'
# A closed review bead is one whose (task_kind, anchor_bead, check_name, verdict, outcome) we vary per case.
review() { # <status> <verdict> <outcome> [check_name]
  local g="${4:-correctness}"
  printf '{"id":"rv-1","status":"%s","assignee":"","title":"review","notes":"","metadata":{"task_kind":"review","check_name":"%s","anchor_bead":"tk-anc","reviewed_oid":"deadbeef","signoff_verdict":"%s","gc.outcome":"%s"}}' "$1" "$g" "$2" "$3"
}
green() { "$SUT" green "$@"; }   # exit 0 green, 1 not green, 2 unreadable
# Each case seeds the store and the edges together: a review bead is created
# joined to its anchor (bd_create_child), so the fixture carries the edge.
case_store() { store "$1"; : > "$STUB_DEPS"; shift; local c; for c in "$@"; do printf '%s|related|tk-anc\n' "$c" >> "$STUB_DEPS"; done; }

# ---------------------------------------------------------------------------
# No review bead at all: a lane no one reviewed is not green.
# ---------------------------------------------------------------------------
case_store "[$ANCHOR]"
if green --anchor tk-anc --lane correctness --no-remote; then bad "an unreviewed lane derived green"; else ok "an unreviewed lane is not green"; fi

# ---------------------------------------------------------------------------
# A closed approve-verdict review backs the lane.
# ---------------------------------------------------------------------------
case_store "[$ANCHOR,$(review closed approve recorded)]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then ok "a closed approve-verdict review derives green"; else bad "closed approve did not derive green"; fi

# ---------------------------------------------------------------------------
# The non-superseded clause: a superseded approve stops backing the lane.
# ---------------------------------------------------------------------------
case_store "[$ANCHOR,$(review closed approve superseded)]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then bad "a superseded approve still derived green"; else ok "a superseded approve does not derive green"; fi

# ---------------------------------------------------------------------------
# A close with no signoff_verdict names no verdict — recorded is stamped on
# every close, approve and request-changes alike — so it backs no lane locally,
# whatever its gc.outcome.
# ---------------------------------------------------------------------------
case_store "[$ANCHOR,$(review closed '' recorded)]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then bad "a no-verdict recorded review derived green from local backing"; else ok "a no-verdict recorded review is not local backing"; fi

case_store "[$ANCHOR,$(review closed '' superseded)]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then bad "a no-verdict superseded review derived green"; else ok "a no-verdict superseded review is not local backing"; fi

# The GitHub-approval fallback still greens it: recorded is not a local verdict,
# but an operator's APPROVED review is independent evidence that backs every lane.
printf '[{"state":"APPROVED","id":7}]' > "$GH_DIR/reviews_42.json"
case_store "[$ANCHOR,$(review closed '' recorded)]" rv-1
if green --anchor tk-anc --lane correctness; then ok "a no-verdict-backed lane greens only via the GitHub-approval fallback"; else bad "the GitHub-approval fallback did not green a no-verdict-backed lane"; fi
rm -f "$GH_DIR/reviews_42.json"

# ---------------------------------------------------------------------------
# The reviewed_oid clause guards a local backing bead: an approve naming no
# reviewed commit is a stale row that cannot green the lane on its own. The
# GitHub-approval fallback is still free to supply independent evidence.
# ---------------------------------------------------------------------------
NO_OID_APPROVE='{"id":"rv-1","status":"closed","assignee":"","title":"r","notes":"","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-anc","signoff_verdict":"approve","gc.outcome":"recorded"}}'
case_store "[$ANCHOR,$NO_OID_APPROVE]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then bad "an approve verdict with no reviewed_oid derived green from local backing"; else ok "an approve verdict with no reviewed_oid is not local backing"; fi

# The same row still greens when the operator's GitHub approval supplies the
# evidence: the reviewed_oid guard scopes the local backing, never the fallback.
printf '[{"state":"APPROVED","id":9}]' > "$GH_DIR/reviews_42.json"
if green --anchor tk-anc --lane correctness; then ok "the GitHub-approval fallback greens a lane whose only local row lacks reviewed_oid"; else bad "a no-reviewed_oid row blocked the GitHub-approval fallback"; fi
rm -f "$GH_DIR/reviews_42.json"

# ---------------------------------------------------------------------------
# request-changes is not an approval.
# ---------------------------------------------------------------------------
case_store "[$ANCHOR,$(review closed request-changes recorded)]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then bad "a request-changes verdict derived green"; else ok "a closed request-changes review is not green"; fi

# ---------------------------------------------------------------------------
# An open review holds the lane out of green even with a prior backing bead.
# ---------------------------------------------------------------------------
case_store "[$ANCHOR,$(review closed approve recorded),{\"id\":\"rv-2\",\"status\":\"in_progress\",\"assignee\":\"pool/x\",\"title\":\"re-review\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"correctness\",\"anchor_bead\":\"tk-anc\"}}]" rv-1 rv-2
if green --anchor tk-anc --lane correctness --no-remote; then bad "green while a review is in flight"; else ok "an in-flight review holds the lane out of green (reviewing)"; fi

# ---------------------------------------------------------------------------
# check_name defaults to correctness, and a correctness backing does not green another lane.
# ---------------------------------------------------------------------------
case_store "[$ANCHOR,{\"id\":\"rv-1\",\"status\":\"closed\",\"assignee\":\"\",\"title\":\"r\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"tk-anc\",\"reviewed_oid\":\"deadbeef\",\"signoff_verdict\":\"approve\",\"gc.outcome\":\"recorded\"}}]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then ok "an absent check_name backs the correctness lane"; else bad "absent check_name did not back correctness"; fi
if green --anchor tk-anc --lane arch --no-remote; then bad "a correctness backing greened the arch lane"; else ok "green is per-lane: correctness backing leaves arch not green"; fi

# ---------------------------------------------------------------------------
# GitHub-approval fallback: no local review bead, but an APPROVED review.
# ---------------------------------------------------------------------------
printf '[{"state":"APPROVED","id":1}]' > "$GH_DIR/reviews_42.json"
case_store "[$ANCHOR]"
if green --anchor tk-anc --lane correctness; then ok "an APPROVED GitHub review backs the lane (fallback)"; else bad "GitHub approval fallback did not derive green"; fi
if green --anchor tk-anc --lane correctness --no-remote; then bad "--no-remote still consulted GitHub"; else ok "--no-remote is fail-closed: no local backing means not green"; fi
# No APPROVED review and no local bead: not green.
printf '[{"state":"COMMENTED","id":2}]' > "$GH_DIR/reviews_42.json"
if green --anchor tk-anc --lane correctness; then bad "a non-approving GitHub review derived green"; else ok "a GitHub review that is not APPROVED is not green"; fi

rm -f "$GH_DIR/reviews_42.json"

# ---------------------------------------------------------------------------
# The cases above run in a store not marked joined, where every review is read
# by anchor_bead. A store marked joined reads the open reviews by anchor_bead
# and the closed ones through the anchor's edges, and derives the same green.
# ---------------------------------------------------------------------------
mark_store() { printf 'anchor_edges.joined=2026-10-11T00:00:00Z\n' > "$STUB_KV"; }
OPEN_RV='{"id":"rv-2","status":"open","assignee":"","title":"re-review","notes":"","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-anc"}}'
mark_store
case_store "[$ANCHOR,$(review closed approve recorded)]" rv-1
: > "$STUB_GC_LOG"
if green --anchor tk-anc --lane correctness --no-remote; then ok "marked: a closed approve the edge reaches derives green"; else bad "marked: the edge-read approve did not derive green"; fi
has "$(grep '^bd list' "$STUB_GC_LOG")" "--status=open,in_progress,blocked,deferred,hooked,pinned " "marked: …the anchor_bead read covering the live statuses"
eq "$(grep -c '^bd list.*closed' "$STUB_GC_LOG")" 0 "marked: …and none covering closed"
case_store "[$ANCHOR,$(review closed approve superseded)]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then bad "marked: a superseded approve derived green"; else ok "marked: a superseded approve does not derive green"; fi
case_store "[$ANCHOR,$(review closed request-changes recorded)]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then bad "marked: a request-changes verdict derived green"; else ok "marked: a closed request-changes review is not green"; fi
case_store "[$ANCHOR,$(review closed approve recorded),$OPEN_RV]" rv-1 rv-2
if green --anchor tk-anc --lane correctness --no-remote; then bad "marked: green while a review is in flight"; else ok "marked: an in-flight review holds the lane out of green"; fi
# A review filed without the edge (by a writer outside the pack, or one an
# older script filed) is still read while it is open, so it holds the lane.
case_store "[$ANCHOR,$(review closed approve recorded),$OPEN_RV]" rv-1
if green --anchor tk-anc --lane correctness --no-remote; then bad "marked: an open review filed without the edge let the lane derive green"; else ok "marked: an open review filed without the edge holds the lane out of green"; fi
# A review the edge reaches whose anchor_bead names another anchor is not this
# anchor's.
MOVED='{"id":"rv-9","status":"closed","assignee":"","title":"r","notes":"","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-other","reviewed_oid":"deadbeef","signoff_verdict":"approve","gc.outcome":"recorded"}}'
case_store "[$ANCHOR,$MOVED]" rv-9
if green --anchor tk-anc --lane correctness --no-remote; then bad "marked: a review moved to another anchor backed this one"; else ok "marked: a review whose anchor_bead names another anchor backs nothing here"; fi

# ---------------------------------------------------------------------------
# A lane a conflicted bring-current round reopened is backed only by an approval
# submitted after the round; a lane the round did not reopen keeps the fallback.
# ---------------------------------------------------------------------------
REOPENED='{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness,triage","pr_number":"42","bring_current_reopened":"triage,correctness","bring_current_round_at":"2026-10-01T00:00:00Z"}}'
store "[$REOPENED]"
printf '[{"state":"APPROVED","id":11,"submitted_at":"2026-09-30T00:00:00Z"}]' > "$GH_DIR/reviews_42.json"
if green --anchor tk-anc --lane triage; then bad "an approval older than the round backed a lane the round reopened"; else ok "an approval older than the round does not back a reopened lane"; fi
if green --anchor tk-anc --lane arch; then ok "…while a lane the round did not reopen keeps the fallback"; else bad "the round withdrew the fallback from a lane it did not reopen"; fi
printf '[{"state":"APPROVED","id":11,"submitted_at":"2026-09-30T00:00:00Z"},{"state":"APPROVED","id":12,"submitted_at":"2026-10-02T00:00:00Z"}]' > "$GH_DIR/reviews_42.json"
if green --anchor tk-anc --lane triage; then ok "an approval given after the round backs the reopened lane"; else bad "an approval after the round did not back the reopened lane"; fi
store "[$(printf '%s' "$REOPENED" | jq -c 'del(.metadata.bring_current_round_at)')]"
if green --anchor tk-anc --lane triage; then bad "a reopened lane with no round time was backed by an approval"; else ok "a reopened lane whose round has no time is backed by no approval"; fi
store "[$REOPENED,$(review closed approve recorded triage)]"
if green --anchor tk-anc --lane triage; then ok "a fresh local approve backs the reopened lane, approval or not"; else bad "a local approve backing did not green the reopened lane"; fi
rm -f "$GH_DIR/reviews_42.json"

# ---------------------------------------------------------------------------
# An unreadable store is not green (exit 2, never green-by-default).
# ---------------------------------------------------------------------------
case_store "[$ANCHOR,$(review closed approve recorded)]" rv-1
STUB_DEP_PARTIAL=1 green --anchor tk-anc --lane correctness --no-remote; rc=$?
eq "$rc" 2 "marked: an unreadable edge read exits 2 (fail-closed, not green)"
STUB_LIST_FAIL=1 green --anchor tk-anc --lane correctness --no-remote; rc=$?
eq "$rc" 2 "marked: an unreadable live read exits 2"
: > "$STUB_KV"
STUB_LIST_FAIL=1 green --anchor tk-anc --lane correctness --no-remote; rc=$?
eq "$rc" 2 "unmarked: an unreadable store exits 2"

# A store not marked joined reads its closed reviews by anchor_bead, so a review
# filed before the edge still backs the lane, and the read writes no edge.
case_store "[$ANCHOR,$(review closed approve recorded)]"
if green --anchor tk-anc --lane correctness --no-remote; then ok "unmarked: a closed approve with no edge still derives green"; else bad "unmarked: an edgeless approve lost its backing"; fi
eq "$(grep -c '' "$STUB_DEPS")" 0 "unmarked: …and the read wrote no edge"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
