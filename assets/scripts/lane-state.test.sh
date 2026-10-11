#!/usr/bin/env bash
# lane-state.test.sh — hermetic tests for the green derivation.
#
# TWO ARMS, ONE BODY. The derivation exists twice during the gctk migration —
# `gctk lane-state` (services/gctk/internal/lane) and the shell fallback in
# lane-state.sh — and a caller cannot tell which answered. So every assertion
# below runs against both: arm "shell" forces the fallback with
# GCTK_FALLBACK=lane-state, arm "gctk" reaches the freshly built binary through
# lane-state.sh, which also proves the hand-off wiring.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lane-state-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
unset GC_RIG 2>/dev/null || true
# The gctk arm's binary is built from this checkout, before harness_init puts
# the stub git on PATH.
harness_build_gctk
harness_init
SUT="$HERE/lane-state.sh"

ANCHOR='{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness","pr_number":"42"}}'
# A closed review bead is one whose (task_kind, anchor_bead, check_name, verdict, outcome) we vary per case.
review() { # <status> <verdict> <outcome> [check_name]
  local g="${4:-correctness}"
  printf '{"id":"rv-1","status":"%s","assignee":"","title":"review","notes":"","metadata":{"task_kind":"review","check_name":"%s","anchor_bead":"tk-anc","reviewed_oid":"deadbeef","signoff_verdict":"%s","gc.outcome":"%s"}}' "$1" "$g" "$2" "$3"
}
green() { "$SUT" green "$@"; }   # exit 0 green, 1 not green, 2 unreadable

suite() {

# ---------------------------------------------------------------------------
# No review bead at all: a lane no one reviewed is not green.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
if green --anchor tk-anc --lane correctness --no-remote; then bad "an unreviewed lane derived green"; else ok "an unreviewed lane is not green"; fi

# ---------------------------------------------------------------------------
# A closed approve-verdict review backs the lane.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed approve recorded)]"
if green --anchor tk-anc --lane correctness --no-remote; then ok "a closed approve-verdict review derives green"; else bad "closed approve did not derive green"; fi

# ---------------------------------------------------------------------------
# The non-superseded clause: a superseded approve stops backing the lane.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed approve superseded)]"
if green --anchor tk-anc --lane correctness --no-remote; then bad "a superseded approve still derived green"; else ok "a superseded approve does not derive green"; fi

# ---------------------------------------------------------------------------
# A close with no signoff_verdict names no verdict — recorded is stamped on
# every close, approve and request-changes alike — so it backs no lane locally,
# whatever its gc.outcome.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed '' recorded)]"
if green --anchor tk-anc --lane correctness --no-remote; then bad "a no-verdict recorded review derived green from local backing"; else ok "a no-verdict recorded review is not local backing"; fi

store "[$ANCHOR,$(review closed '' superseded)]"
if green --anchor tk-anc --lane correctness --no-remote; then bad "a no-verdict superseded review derived green"; else ok "a no-verdict superseded review is not local backing"; fi

# The GitHub-approval fallback still greens it: recorded is not a local verdict,
# but an operator's APPROVED review is independent evidence that backs every lane.
printf '[{"state":"APPROVED","id":7}]' > "$GH_DIR/reviews_42.json"
store "[$ANCHOR,$(review closed '' recorded)]"
if green --anchor tk-anc --lane correctness; then ok "a no-verdict-backed lane greens only via the GitHub-approval fallback"; else bad "the GitHub-approval fallback did not green a no-verdict-backed lane"; fi
rm -f "$GH_DIR/reviews_42.json"

# ---------------------------------------------------------------------------
# The reviewed_oid clause guards a local backing bead: an approve naming no
# reviewed commit is a stale row that cannot green the lane on its own. The
# GitHub-approval fallback is still free to supply independent evidence.
# ---------------------------------------------------------------------------
NO_OID_APPROVE='{"id":"rv-1","status":"closed","assignee":"","title":"r","notes":"","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-anc","signoff_verdict":"approve","gc.outcome":"recorded"}}'
store "[$ANCHOR,$NO_OID_APPROVE]"
if green --anchor tk-anc --lane correctness --no-remote; then bad "an approve verdict with no reviewed_oid derived green from local backing"; else ok "an approve verdict with no reviewed_oid is not local backing"; fi

# The same row still greens when the operator's GitHub approval supplies the
# evidence: the reviewed_oid guard scopes the local backing, never the fallback.
printf '[{"state":"APPROVED","id":9}]' > "$GH_DIR/reviews_42.json"
if green --anchor tk-anc --lane correctness; then ok "the GitHub-approval fallback greens a lane whose only local row lacks reviewed_oid"; else bad "a no-reviewed_oid row blocked the GitHub-approval fallback"; fi
rm -f "$GH_DIR/reviews_42.json"

# ---------------------------------------------------------------------------
# request-changes is not an approval.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed request-changes recorded)]"
if green --anchor tk-anc --lane correctness --no-remote; then bad "a request-changes verdict derived green"; else ok "a closed request-changes review is not green"; fi

# ---------------------------------------------------------------------------
# An open review holds the lane out of green even with a prior backing bead.
# ---------------------------------------------------------------------------
store "[$ANCHOR,$(review closed approve recorded),{\"id\":\"rv-2\",\"status\":\"in_progress\",\"assignee\":\"pool/x\",\"title\":\"re-review\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"check_name\":\"correctness\",\"anchor_bead\":\"tk-anc\"}}]"
if green --anchor tk-anc --lane correctness --no-remote; then bad "green while a review is in flight"; else ok "an in-flight review holds the lane out of green (reviewing)"; fi

# ---------------------------------------------------------------------------
# check_name defaults to correctness, and a correctness backing does not green another lane.
# ---------------------------------------------------------------------------
store "[$ANCHOR,{\"id\":\"rv-1\",\"status\":\"closed\",\"assignee\":\"\",\"title\":\"r\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"tk-anc\",\"reviewed_oid\":\"deadbeef\",\"signoff_verdict\":\"approve\",\"gc.outcome\":\"recorded\"}}]"
if green --anchor tk-anc --lane correctness --no-remote; then ok "an absent check_name backs the correctness lane"; else bad "absent check_name did not back correctness"; fi
if green --anchor tk-anc --lane arch --no-remote; then bad "a correctness backing greened the arch lane"; else ok "green is per-lane: correctness backing leaves arch not green"; fi

# ---------------------------------------------------------------------------
# GitHub-approval fallback: no local review bead, but an APPROVED review.
# ---------------------------------------------------------------------------
printf '[{"state":"APPROVED","id":1}]' > "$GH_DIR/reviews_42.json"
store "[$ANCHOR]"
if green --anchor tk-anc --lane correctness; then ok "an APPROVED GitHub review backs the lane (fallback)"; else bad "GitHub approval fallback did not derive green"; fi
if green --anchor tk-anc --lane correctness --no-remote; then bad "--no-remote still consulted GitHub"; else ok "--no-remote is fail-closed: no local backing means not green"; fi
# No APPROVED review and no local bead: not green.
printf '[{"state":"COMMENTED","id":2}]' > "$GH_DIR/reviews_42.json"
if green --anchor tk-anc --lane correctness; then bad "a non-approving GitHub review derived green"; else ok "a GitHub review that is not APPROVED is not green"; fi

# ---------------------------------------------------------------------------
# An unreadable store is not green (exit 2, never green-by-default).
# ---------------------------------------------------------------------------
STUB_LIST_FAIL=1 green --anchor tk-anc --lane correctness --no-remote; rc=$?
eq "$rc" 2 "an unreadable store exits 2 (fail-closed, not green)"

rm -f "$GH_DIR/reviews_42.json"
}

# An arm proves nothing about which implementation answered unless the hand-off
# is checked directly. lane-state writes nothing on either path, so a sentinel
# on the resolved path is the discriminator: it names itself and the subcommand
# it was handed.
SENTINEL="$TMP/sentinel-gctk"
printf '#!/usr/bin/env bash\nprintf "SENTINEL-GCTK %%s\\n" "$*"\n' > "$SENTINEL"
chmod +x "$SENTINEL"
store "[$ANCHOR]"

echo "## arm: shell fallback (GCTK_FALLBACK=lane-state)"
export GCTK_FALLBACK=lane-state
suite
out=$(GCTK_BIN="$SENTINEL" "$SUT" green --anchor tk-anc --lane correctness --no-remote 2>&1)
hasnt "$out" "SENTINEL-GCTK" "GCTK_FALLBACK=lane-state keeps lane-state.sh on its shell with a binary named"
unset GCTK_FALLBACK

echo
echo "## arm: gctk lane-state (reached through lane-state.sh)"
if [ -n "$GCTK_BUILT" ]; then
  # The suite body must have run THROUGH the binary, not fallen back to the
  # shell with the same answers. The arm's GCTK_BIN is a wrapper that logs the
  # argv it was handed and then execs the real build, so after the body the log
  # is the proof: one `lane-state green --anchor ...` line per SUT call.
  LOGGED="$TMP/gctk-logged"; CALLS="$TMP/gctk-calls.log"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexec %q "$@"\n' "$CALLS" "$GCTK_BUILT" > "$LOGGED"
  chmod +x "$LOGGED"
  : > "$CALLS"
  export GCTK_BIN="$LOGGED"
  suite
  # 16 is the number of `green` calls suite() makes; a new case there must bump it.
  eq "$(grep -c '^lane-state green --anchor ' "$CALLS")" 16 "every suite call reached the gctk binary as \`lane-state green --anchor ...\` (16 calls, one line each)"
  eq "$(grep -vc -- '--anchor' "$CALLS")" 0 "no call handed to the binary lacks its --anchor"
  out=$(GCTK_BIN="$SENTINEL" "$SUT" green --anchor tk-anc --lane correctness --no-remote 2>&1)
  eq "$out" "SENTINEL-GCTK lane-state green --anchor tk-anc --lane correctness --no-remote" "lane-state.sh execs \$GCTK_BIN with the lane-state subcommand and its arguments verbatim"
else
  bad "gctk was not built, so the gctk lane-state port was NOT exercised, and this suite is its acceptance bar"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
