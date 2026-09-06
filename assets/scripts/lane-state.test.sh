#!/usr/bin/env bash
# lane-state.test.sh — hermetic tests for the green derivation.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lane-state-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
unset GC_RIG 2>/dev/null || true
harness_init
SUT="$HERE/lane-state.sh"

ANCHOR='{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"42"}}'
# A closed review bead is one whose (task_kind, anchor_bead, check_name, verdict, outcome) we vary per case.
review() { # <status> <verdict> <outcome> [check_name]
  local g="${4:-codex}"
  printf '{"id":"rv-1","status":"%s","assignee":"","title":"review","notes":"","metadata":{"task_kind":"review","check_name":"%s","anchor_bead":"tk-anc","reviewed_oid":"deadbeef","signoff_verdict":"%s","gc.outcome":"%s"}}' "$1" "$g" "$2" "$3"
}
green() { "$SUT" green "$@"; }   # exit 0 green, 1 not green, 2 unreadable

# ---------------------------------------------------------------------------
# No review bead at all: a lane no one reviewed is not green.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
if green --anchor tk-anc --lane codex --no-remote; then bad "an unreviewed lane derived green"; else ok "an unreviewed lane is not green"; fi

# ---------------------------------------------------------------------------
# A closed approve-verdict review backs the lane.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed approve recorded)]"
if green --anchor tk-anc --lane codex --no-remote; then ok "a closed approve-verdict review derives green"; else bad "closed approve did not derive green"; fi

# ---------------------------------------------------------------------------
# The non-superseded clause: a superseded approve stops backing the lane.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed approve superseded)]"
if green --anchor tk-anc --lane codex --no-remote; then bad "a superseded approve still derived green"; else ok "a superseded approve does not derive green"; fi

# ---------------------------------------------------------------------------
# Legacy bead: no verdict stamp, gc.outcome=recorded still backs the lane.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed '' recorded)]"
if green --anchor tk-anc --lane codex --no-remote; then ok "a legacy no-verdict recorded review derives green"; else bad "legacy recorded review did not derive green"; fi

# A superseded legacy bead loses gc.outcome=recorded, so it does not back.
store "[$ANCHOR,$(review closed '' superseded)]"
if green --anchor tk-anc --lane codex --no-remote; then bad "a superseded legacy bead still derived green"; else ok "a superseded legacy bead does not derive green"; fi

# ---------------------------------------------------------------------------
# A closed review carrying no reviewed_oid is not local backing. This derivation
# reads the same evidence doctor/check-gate-marker-provenance resolves a marker
# against — the review bead's reviewed_oid — so a recorded verdict naming no
# reviewed commit is a stale or legacy row that cannot green the lane on its own,
# whether it carries an approve verdict or the legacy recorded stamp. The
# GitHub-approval fallback is still free to supply independent evidence.
# ---------------------------------------------------------------------------
NO_OID_LEGACY='{"id":"rv-1","status":"closed","assignee":"","title":"r","notes":"","metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"tk-anc","gc.outcome":"recorded"}}'
store "[$ANCHOR,$NO_OID_LEGACY]"
if green --anchor tk-anc --lane codex --no-remote; then bad "a legacy recorded review with no reviewed_oid derived green from local backing"; else ok "a legacy recorded review with no reviewed_oid is not local backing"; fi

NO_OID_APPROVE='{"id":"rv-1","status":"closed","assignee":"","title":"r","notes":"","metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"tk-anc","signoff_verdict":"approve","gc.outcome":"recorded"}}'
store "[$ANCHOR,$NO_OID_APPROVE]"
if green --anchor tk-anc --lane codex --no-remote; then bad "an approve verdict with no reviewed_oid derived green from local backing"; else ok "an approve verdict with no reviewed_oid is not local backing"; fi

# The same row still greens when the operator's GitHub approval supplies the
# evidence: the reviewed_oid guard scopes the local backing, never the fallback.
printf '[{"state":"APPROVED","id":9}]' > "$GH_DIR/reviews_42.json"
if green --anchor tk-anc --lane codex; then ok "the GitHub-approval fallback greens a lane whose only local row lacks reviewed_oid"; else bad "a no-reviewed_oid row blocked the GitHub-approval fallback"; fi
rm -f "$GH_DIR/reviews_42.json"

# ---------------------------------------------------------------------------
# request-changes is not an approval.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed request-changes recorded)]"
if green --anchor tk-anc --lane codex --no-remote; then bad "a request-changes verdict derived green"; else ok "a closed request-changes review is not green"; fi

# ---------------------------------------------------------------------------
# An open review holds the lane out of green even with a prior backing bead.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed approve recorded),{\"id\":\"rv-2\",\"status\":\"in_progress\",\"assignee\":\"pool/x\",\"title\":\"re-review\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"codex\",\"anchor_bead\":\"tk-anc\"}}]"
if green --anchor tk-anc --lane codex --no-remote; then bad "green while a review is in flight"; else ok "an in-flight review holds the lane out of green (reviewing)"; fi

# ---------------------------------------------------------------------------
# check_name defaults to codex, and a codex backing does not green another lane.
# ---------------------------------------------------------------------------
store "[$ANCHOR,{\"id\":\"rv-1\",\"status\":\"closed\",\"assignee\":\"\",\"title\":\"r\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"tk-anc\",\"reviewed_oid\":\"deadbeef\",\"signoff_verdict\":\"approve\",\"gc.outcome\":\"recorded\"}}]"
if green --anchor tk-anc --lane codex --no-remote; then ok "an absent check_name backs the codex lane"; else bad "absent check_name did not back codex"; fi
if green --anchor tk-anc --lane arch --no-remote; then bad "a codex backing greened the arch lane"; else ok "green is per-lane: codex backing leaves arch not green"; fi

# ---------------------------------------------------------------------------
# GitHub-approval fallback: no local review bead, but an APPROVED review.
# ---------------------------------------------------------------------------
printf '[{"state":"APPROVED","id":1}]' > "$GH_DIR/reviews_42.json"
store "[$ANCHOR]"
if green --anchor tk-anc --lane codex; then ok "an APPROVED GitHub review backs the lane (fallback)"; else bad "GitHub approval fallback did not derive green"; fi
if green --anchor tk-anc --lane codex --no-remote; then bad "--no-remote still consulted GitHub"; else ok "--no-remote is fail-closed: no local backing means not green"; fi
# No APPROVED review and no local bead: not green.
printf '[{"state":"COMMENTED","id":2}]' > "$GH_DIR/reviews_42.json"
if green --anchor tk-anc --lane codex; then bad "a non-approving GitHub review derived green"; else ok "a GitHub review that is not APPROVED is not green"; fi

# ---------------------------------------------------------------------------
# An unreadable store is not green (exit 2, never green-by-default).
# ---------------------------------------------------------------------------
STUB_LIST_FAIL=1 green --anchor tk-anc --lane codex --no-remote; rc=$?
eq "$rc" 2 "an unreadable store exits 2 (fail-closed, not green)"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
