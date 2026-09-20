#!/usr/bin/env bash
# review-outcome.test.sh — hermetic tests for the approve-outcome write side.
# The round-trip is the point: what review-outcome.sh writes, lane-state.sh must
# read back as green (and, once superseded, as not green).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-outcome-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
unset GC_RIG 2>/dev/null || true
harness_init
SUT="$HERE/review-outcome.sh"
LANE="$HERE/lane-state.sh"

ANCHOR='{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"42"}}'
green() { "$LANE" green --anchor "$1" --lane "$2" --no-remote; }   # 0 green, 1 not, 2 unreadable

# ---------------------------------------------------------------------------
# back-lane: an unbacked lane is not green; after back-lane it is.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
if green tk-anc codex; then bad "an unbacked lane derived green before back-lane"; else ok "an unbacked lane is not green"; fi
ID=$("$SUT" back-lane --anchor tk-anc --lane codex --oid deadbeef)
if [ -n "$ID" ]; then ok "back-lane returns the outcome bead id"; else bad "back-lane returned no id"; fi
eq "$(meta "$ID" task_kind)" "review" "back-lane stamps task_kind=review"
eq "$(meta "$ID" anchor_bead)" "tk-anc" "back-lane stamps anchor_bead"
eq "$(meta "$ID" check_name)" "codex" "back-lane stamps check_name=lane"
eq "$(meta "$ID" reviewed_oid)" "deadbeef" "back-lane stamps the reviewed_oid pin"
eq "$(meta "$ID" signoff_verdict)" "approve" "back-lane stamps signoff_verdict=approve"
eq "$(meta "$ID" 'gc.outcome')" "recorded" "back-lane stamps gc.outcome=recorded (non-superseded)"
eq "$(bstatus "$ID")" "closed" "the approve outcome bead is closed"
if green tk-anc codex; then ok "lane-state derives green off the outcome back-lane wrote"; else bad "lane-state did not derive green after back-lane"; fi

# ---------------------------------------------------------------------------
# back-lane is idempotent: a second ruling files no second bead.
# ---------------------------------------------------------------------------
BEFORE=$(jq 'length' "$STUB_STORE")
ID2=$("$SUT" back-lane --anchor tk-anc --lane codex --oid cafef00d)
eq "$ID2" "$ID" "re-ruling a backed lane returns the existing outcome"
eq "$(jq 'length' "$STUB_STORE")" "$BEFORE" "…and files no second bead (a push does not stale a backing)"

# ---------------------------------------------------------------------------
# back-lane is per-lane: a codex backing does not green the arch lane.
# ---------------------------------------------------------------------------
if green tk-anc arch; then bad "a codex backing greened the arch lane"; else ok "green is per-lane: codex backing leaves arch not green"; fi
"$SUT" back-lane --anchor tk-anc --lane arch --oid deadbeef >/dev/null
if green tk-anc arch; then ok "backing arch greens the arch lane"; else bad "back-lane did not green arch"; fi

# ---------------------------------------------------------------------------
# supersede-lane: the backing stops greening the lane, which returns to unreviewed.
# ---------------------------------------------------------------------------
N=$("$SUT" supersede-lane --anchor tk-anc --lane codex --reason "operator overturned a diff assumption")
eq "$N" "1" "supersede-lane reports one outcome retired"
eq "$(meta "$ID" 'gc.outcome')" "superseded" "supersede stamps gc.outcome=superseded"
if green tk-anc codex; then bad "a superseded lane still derived green"; else ok "supersede returns the lane to unreviewed (not green)"; fi
has "$(notes "$ID")" "operator overturned a diff assumption" "the supersede reason is recorded"
# It is scoped: superseding codex left arch backed.
if green tk-anc arch; then ok "supersede is per-lane: arch stays green"; else bad "superseding codex disturbed arch"; fi

# ---------------------------------------------------------------------------
# supersede-lane on an unbacked lane is a no-op success (nothing to retire).
# ---------------------------------------------------------------------------
if N0=$("$SUT" supersede-lane --anchor tk-anc --lane nolane); then ok "supersede-lane on an unbacked lane succeeds"; else bad "supersede-lane failed on an unbacked lane"; fi
eq "$N0" "0" "…and reports zero retired"

# ---------------------------------------------------------------------------
# back-lane after supersede: a superseded backing does not block a fresh one.
# ---------------------------------------------------------------------------
ID3=$("$SUT" back-lane --anchor tk-anc --lane codex --oid abcd1234)
if [ "$ID3" != "$ID" ]; then ok "re-converging after a supersede files a fresh backing"; else bad "back-lane returned the superseded bead"; fi
if green tk-anc codex; then ok "the fresh backing greens the lane again"; else bad "the fresh backing did not green the lane"; fi

# ---------------------------------------------------------------------------
# Guards: --oid required; unreadable store fails closed (exit 2).
# ---------------------------------------------------------------------------
if "$SUT" back-lane --anchor tk-anc --lane codex >/dev/null 2>&1; then bad "back-lane ran without --oid"; else ok "back-lane requires --oid"; fi
STUB_LIST_FAIL=1 "$SUT" back-lane --anchor tk-anc --lane codex --oid deadbeef >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an unreadable store fails closed on back-lane (exit 2)"
STUB_LIST_FAIL=1 "$SUT" supersede-lane --anchor tk-anc --lane codex >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an unreadable store fails closed on supersede-lane (exit 2)"

# ---------------------------------------------------------------------------
# supersede-anchor: a human feedback batch is anchor-wide. Its non-convergence
# must return every declared check_set lane to unreviewed — not the
# check_name=human pseudo-lane the validation pass carries, which no gate reader
# derives green from. Regression for the P0 where the validator superseded lane
# `human`, left the codex gate green, and the anchor could merge without the
# fresh whole-diff review the ruling required.
# ---------------------------------------------------------------------------
CODEX_ANCHOR='{"id":"tk-hanc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"7"}}'
store "[$CODEX_ANCHOR]"
"$SUT" back-lane --anchor tk-hanc --lane codex --oid deadbeef >/dev/null
if green tk-hanc codex; then ok "codex lane green before the human batch is ruled"; else bad "setup: codex did not green"; fi
# The validator rules the human batch NOT converged -> supersede-anchor.
NA=$("$SUT" supersede-anchor --anchor tk-hanc --reason "operator overturned a diff assumption"); rc=$?
eq "$rc" 0 "supersede-anchor succeeds on a check_set=codex anchor"
eq "$NA" "1" "…and reports the one codex backing retired"
if green tk-hanc codex; then bad "the codex gate stayed green after a human non-convergence (the P0)"; else ok "supersede-anchor returns the real codex lane to unreviewed"; fi

# It fans out over EVERY declared lane, not just the first.
TWO_ANCHOR='{"id":"tk-2anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex,arch","pr_number":"8"}}'
store "[$TWO_ANCHOR]"
"$SUT" back-lane --anchor tk-2anc --lane codex --oid deadbeef >/dev/null
"$SUT" back-lane --anchor tk-2anc --lane arch  --oid deadbeef >/dev/null
if green tk-2anc codex && green tk-2anc arch; then ok "both lanes green before the human batch"; else bad "setup: two lanes did not green"; fi
N2=$("$SUT" supersede-anchor --anchor tk-2anc)
eq "$N2" "2" "supersede-anchor retires a backing on every declared lane"
if green tk-2anc codex; then bad "codex stayed green after anchor-wide supersede"; else ok "codex returned to unreviewed"; fi
if green tk-2anc arch;  then bad "arch stayed green after anchor-wide supersede";  else ok "arch returned to unreviewed"; fi

# A gateless anchor (check_set=none) has no lane to move: no-op success, not error.
NONE_ANCHOR='{"id":"tk-nanc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"none"}}'
store "[$NONE_ANCHOR]"
if NN=$("$SUT" supersede-anchor --anchor tk-nanc); then ok "supersede-anchor succeeds on a gateless (none) anchor"; else bad "supersede-anchor failed on a none anchor"; fi
eq "$NN" "0" "…and reports zero lanes retired"

# Fail closed: an unreadable anchor is never a silent no-op that leaves a gate green.
store "[$CODEX_ANCHOR]"
STUB_SHOW_FAIL=1 "$SUT" supersede-anchor --anchor tk-hanc >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an unreadable anchor fails closed on supersede-anchor (exit 2)"
# An anchor that declares no check_set at all is anomalous, not gateless.
NOCS_ANCHOR='{"id":"tk-xanc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request"}}'
store "[$NOCS_ANCHOR]"
"$SUT" supersede-anchor --anchor tk-xanc >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an anchor with no check_set fails closed (exit 2)"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
