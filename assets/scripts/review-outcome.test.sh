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

ANCHOR='{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness","pr_number":"42"}}'
green() { "$LANE" green --anchor "$1" --lane "$2" --no-remote; }   # 0 green, 1 not, 2 unreadable

# ---------------------------------------------------------------------------
# back-lane: an unbacked lane is not green; after back-lane it is.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
if green tk-anc correctness; then bad "an unbacked lane derived green before back-lane"; else ok "an unbacked lane is not green"; fi
ID=$("$SUT" back-lane --anchor tk-anc --lane correctness --oid deadbeef)
if [ -n "$ID" ]; then ok "back-lane returns the outcome bead id"; else bad "back-lane returned no id"; fi
eq "$(meta "$ID" task_kind)" "review" "back-lane stamps task_kind=review"
eq "$(meta "$ID" anchor_bead)" "tk-anc" "back-lane stamps anchor_bead"
eq "$(meta "$ID" check_name)" "correctness" "back-lane stamps check_name=lane"
eq "$(meta "$ID" reviewed_oid)" "deadbeef" "back-lane stamps the reviewed_oid pin"
eq "$(meta "$ID" signoff_verdict)" "approve" "back-lane stamps signoff_verdict=approve"
eq "$(meta "$ID" 'gc.outcome')" "recorded" "back-lane stamps gc.outcome=recorded (non-superseded)"
eq "$(bstatus "$ID")" "closed" "the approve outcome bead is closed"
if green tk-anc correctness; then ok "lane-state derives green off the outcome back-lane wrote"; else bad "lane-state did not derive green after back-lane"; fi

# ---------------------------------------------------------------------------
# back-lane is idempotent: a second ruling files no second bead.
# ---------------------------------------------------------------------------
BEFORE=$(jq 'length' "$STUB_STORE")
ID2=$("$SUT" back-lane --anchor tk-anc --lane correctness --oid cafef00d)
eq "$ID2" "$ID" "re-ruling a backed lane returns the existing outcome"
eq "$(jq 'length' "$STUB_STORE")" "$BEFORE" "…and files no second bead (a push does not stale a backing)"

# ---------------------------------------------------------------------------
# back-lane is per-lane: a correctness backing does not green the arch lane.
# ---------------------------------------------------------------------------
if green tk-anc arch; then bad "a correctness backing greened the arch lane"; else ok "green is per-lane: correctness backing leaves arch not green"; fi
"$SUT" back-lane --anchor tk-anc --lane arch --oid deadbeef >/dev/null
if green tk-anc arch; then ok "backing arch greens the arch lane"; else bad "back-lane did not green arch"; fi

# ---------------------------------------------------------------------------
# supersede-lane: the backing stops greening the lane, which returns to unreviewed.
# ---------------------------------------------------------------------------
N=$("$SUT" supersede-lane --anchor tk-anc --lane correctness --reason "operator overturned a diff assumption")
eq "$N" "1" "supersede-lane reports one outcome retired"
eq "$(meta "$ID" 'gc.outcome')" "superseded" "supersede stamps gc.outcome=superseded"
if green tk-anc correctness; then bad "a superseded lane still derived green"; else ok "supersede returns the lane to unreviewed (not green)"; fi
has "$(notes "$ID")" "operator overturned a diff assumption" "the supersede reason is recorded"
# It is scoped: superseding correctness left arch backed.
if green tk-anc arch; then ok "supersede is per-lane: arch stays green"; else bad "superseding correctness disturbed arch"; fi

# ---------------------------------------------------------------------------
# supersede-lane on an unbacked lane is a no-op success (nothing to retire).
# ---------------------------------------------------------------------------
if N0=$("$SUT" supersede-lane --anchor tk-anc --lane nolane); then ok "supersede-lane on an unbacked lane succeeds"; else bad "supersede-lane failed on an unbacked lane"; fi
eq "$N0" "0" "…and reports zero retired"

# ---------------------------------------------------------------------------
# supersede-lane retires a standing request-changes verdict, not just an approve
# backing. A bare request-changes lane has no backing, so retiring only backings
# left the closed verdict at gc.outcome=recorded — exactly what gate-ensure.sh's
# per-head bar reads to block a re-review at the unmoved head, wedging the
# validator-ordered re-review. The superseded stamp is the signal the bar excludes.
# ---------------------------------------------------------------------------
RC_ANCHOR='{"id":"tk-rcanc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"91"}}'
RC_REVIEW='{"id":"tk-rcrev","status":"closed","assignee":"","notes":"","metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"tk-rcanc","reviewed_oid":"305c7b69","signoff_verdict":"request-changes","gc.outcome":"recorded"}}'
store "[$RC_ANCHOR, $RC_REVIEW]"
if green tk-rcanc codex; then bad "a request-changes-only lane derived green"; else ok "a request-changes-only lane is not green (setup)"; fi
NRC=$("$SUT" supersede-lane --anchor tk-rcanc --lane codex --reason "validator ordered a fresh whole-diff look at the unmoved head")
eq "$NRC" "1" "supersede-lane retires the standing request-changes verdict (was a silent no-op)"
eq "$(meta tk-rcrev 'gc.outcome')" "superseded" "the request-changes review is stamped superseded — the signal the per-head bar excludes"
has "$(notes tk-rcrev)" "validator ordered a fresh whole-diff look" "the supersede reason is recorded on the request-changes review"

# ---------------------------------------------------------------------------
# back-lane after supersede: a superseded backing does not block a fresh one.
# ---------------------------------------------------------------------------
ID3=$("$SUT" back-lane --anchor tk-anc --lane correctness --oid abcd1234)
if [ "$ID3" != "$ID" ]; then ok "re-converging after a supersede files a fresh backing"; else bad "back-lane returned the superseded bead"; fi
if green tk-anc correctness; then ok "the fresh backing greens the lane again"; else bad "the fresh backing did not green the lane"; fi

# ---------------------------------------------------------------------------
# back-lane leaves no bead its own dedup cannot see. The dedup selects on
# anchor_bead and task_kind=review, so an outcome created bare and stamped in a
# second write is invisible to it once that write fails: the bead stays open
# and unstamped, no review reader ever closes it, and the retry files a stamped
# twin under the same title. Born closed with every stamp in the one create,
# the outcome is whole or absent whatever happens to the write, and one left
# stamped but open is finished rather than twinned.
# ---------------------------------------------------------------------------
AT_ANCHOR='{"id":"tk-at","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness","pr_number":"43"}}'
AT_TITLE="lane correctness converged: validator ruled no further review — anchor tk-at"
outcomes()  { jq --arg t "$AT_TITLE" '[ .[] | select(.title == $t) ] | length' "$STUB_STORE"; }
unstamped() { jq --arg t "$AT_TITLE" '[ .[] | select(.title == $t) | select(((.metadata // {}).task_kind // "") == "") ] | length' "$STUB_STORE"; }

# Every write after the create refused: the stamp-and-close a create-then-stamp
# writer depends on can no longer fail, because the create carries it.
store "[$AT_ANCHOR]"
STUB_UPDATE_FAIL="new-2" "$SUT" back-lane --anchor tk-at --lane correctness --oid deadbeef --reason "one localized must-fix" >/dev/null 2>&1; rc=$?
eq "$rc" 0 "with every write after the create refused, back-lane still backs the lane"
eq "$(unstamped)" "0" "…and leaves no unstamped outcome"
eq "$(bstatus new-2)" "closed" "the outcome is born closed"
eq "$(meta new-2 signoff_verdict)" "approve" "…with its stamps in the same write"
has "$(notes new-2)" "converged at deadbeef — one localized must-fix" "…and its note"
if green tk-at correctness; then ok "…so the lane derives green from the create alone"; else bad "the lane did not derive green from a born-closed outcome"; fi

# A refused create leaves nothing behind, and the retry files exactly one.
store "[$AT_ANCHOR]"
STUB_CREATE_FAIL=1 "$SUT" back-lane --anchor tk-at --lane correctness --oid deadbeef >/dev/null 2>&1; rc=$?
eq "$rc" 2 "a refused create fails closed (exit 2)"
eq "$(jq 'length' "$STUB_STORE")" "1" "…and leaves no bead behind"
"$SUT" back-lane --anchor tk-at --lane correctness --oid deadbeef >/dev/null 2>&1
eq "$(outcomes)" "1" "the retry after a refused create files exactly one outcome"

# A create whose reply will not parse has still filed the whole backing; the
# read-back finds it, and the retry's dedup does too.
store "[$AT_ANCHOR]"
ID=$(STUB_CREATE_GARBAGE=1 "$SUT" back-lane --anchor tk-at --lane correctness --oid deadbeef 2>/dev/null); rc=$?
eq "$rc" 0 "a create whose reply will not parse still backs the lane"
eq "$ID" "new-2" "…and reports the backing the read-back found"
eq "$(unstamped)" "0" "…leaving no unstamped outcome"
ID2=$("$SUT" back-lane --anchor tk-at --lane correctness --oid deadbeef 2>/dev/null)
eq "$ID2" "new-2" "the retry finds that backing"
eq "$(outcomes)" "1" "…and files no second approve outcome"

# A create that lands stamped but without its closed status fails the read-back.
# What it leaves is stamped, so the retry finishes it instead of filing a twin
# beside it.
store "[$AT_ANCHOR]"
STUB_DROP_KEYS="new-2:status" "$SUT" back-lane --anchor tk-at --lane correctness --oid deadbeef >/dev/null 2>&1; rc=$?
eq "$rc" 2 "a create that lands open fails closed (exit 2)"
eq "$(unstamped)" "0" "…and what it leaves is stamped, not an orphan the dedup cannot see"
if green tk-at correctness; then bad "an open outcome derived green"; else ok "the open outcome holds the lane in flight until it closes"; fi
ID=$("$SUT" back-lane --anchor tk-at --lane correctness --oid cafef00d 2>/dev/null); rc=$?
eq "$rc" 0 "the retry succeeds"
eq "$ID" "new-2" "…by finishing the open outcome"
eq "$(bstatus new-2)" "closed" "…which it closes"
eq "$(outcomes)" "1" "…and files no second approve outcome"
if green tk-at correctness; then ok "…and the lane derives green"; else bad "the finished outcome did not green the lane"; fi

# An open outcome beside a live backing still holds the lane in flight, so it is
# finished before the dedup returns the backing, and nothing new is filed.
AT_BACKING='{"id":"tk-atb","status":"closed","assignee":"","title":"'"$AT_TITLE"'","notes":"","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-at","reviewed_oid":"deadbeef","signoff_verdict":"approve","gc.outcome":"recorded"}}'
AT_OPEN='{"id":"tk-ato","status":"open","assignee":"","title":"'"$AT_TITLE"'","notes":"","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-at","reviewed_oid":"deadbeef","signoff_verdict":"approve","gc.outcome":"recorded"}}'
store "[$AT_ANCHOR, $AT_BACKING, $AT_OPEN]"
if green tk-at correctness; then bad "setup: a lane with an open outcome derived green"; else ok "an open outcome beside a backing holds the lane (setup)"; fi
"$SUT" back-lane --anchor tk-at --lane correctness --oid deadbeef >/dev/null 2>&1
eq "$(bstatus tk-ato)" "closed" "back-lane finishes the open outcome beside the backing"
eq "$(outcomes)" "2" "…and files nothing new"
if green tk-at correctness; then ok "…so the lane derives green"; else bad "the lane stayed held after the open outcome was finished"; fi

# A close that reports success but leaves the outcome open still holds the lane,
# and the dedup cannot see an open outcome, so back-lane reads the close back
# and fails closed instead of filing a twin beside it.
store "[$AT_ANCHOR, $AT_OPEN]"
STUB_DROP_KEYS="tk-ato:status" "$SUT" back-lane --anchor tk-at --lane correctness --oid deadbeef >/dev/null 2>&1; rc=$?
eq "$rc" 2 "a close of the open outcome that does not land fails closed (exit 2)"
eq "$(outcomes)" "1" "…and files no twin beside the outcome still holding the lane"

# Finishing is bound to back-lane's own outcome. An open approve review under
# any other title belongs to another writer, and back-lane leaves it open.
OTHER='{"id":"tk-other","status":"open","assignee":"","title":"Review PR#43 correctness","notes":"","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-at","reviewed_oid":"deadbeef","signoff_verdict":"approve","gc.outcome":"recorded"}}'
store "[$AT_ANCHOR, $OTHER]"
"$SUT" back-lane --anchor tk-at --lane correctness --oid deadbeef >/dev/null 2>&1
eq "$(bstatus tk-other)" "open" "back-lane never closes an open review it did not file"

# ---------------------------------------------------------------------------
# Guards: --oid required; unreadable store fails closed (exit 2).
# ---------------------------------------------------------------------------
if "$SUT" back-lane --anchor tk-anc --lane correctness >/dev/null 2>&1; then bad "back-lane ran without --oid"; else ok "back-lane requires --oid"; fi
STUB_LIST_FAIL=1 "$SUT" back-lane --anchor tk-anc --lane correctness --oid deadbeef >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an unreadable store fails closed on back-lane (exit 2)"
STUB_LIST_FAIL=1 "$SUT" supersede-lane --anchor tk-anc --lane correctness >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an unreadable store fails closed on supersede-lane (exit 2)"

# ---------------------------------------------------------------------------
# supersede-anchor: a human feedback batch is anchor-wide. Its non-convergence
# must return every declared check_set lane to unreviewed — not the
# check_name=human pseudo-lane the validation pass carries, which no check reader
# derives green from. Regression for the P0 where the validator superseded lane
# `human`, left the correctness check green, and the anchor could merge without the
# fresh whole-diff review the ruling required.
# ---------------------------------------------------------------------------
CODEX_ANCHOR='{"id":"tk-hanc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness","pr_number":"7"}}'
store "[$CODEX_ANCHOR]"
"$SUT" back-lane --anchor tk-hanc --lane correctness --oid deadbeef >/dev/null
if green tk-hanc correctness; then ok "correctness lane green before the human batch is ruled"; else bad "setup: correctness did not green"; fi
# The validator rules the human batch NOT converged -> supersede-anchor.
NA=$("$SUT" supersede-anchor --anchor tk-hanc --reason "operator overturned a diff assumption"); rc=$?
eq "$rc" 0 "supersede-anchor succeeds on a check_set=correctness anchor"
eq "$NA" "1" "…and reports the one correctness backing retired"
if green tk-hanc correctness; then bad "the correctness check stayed green after a human non-convergence (the P0)"; else ok "supersede-anchor returns the real correctness lane to unreviewed"; fi

# It fans out over EVERY declared lane, not just the first.
TWO_ANCHOR='{"id":"tk-2anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness,arch","pr_number":"8"}}'
store "[$TWO_ANCHOR]"
"$SUT" back-lane --anchor tk-2anc --lane correctness --oid deadbeef >/dev/null
"$SUT" back-lane --anchor tk-2anc --lane arch  --oid deadbeef >/dev/null
if green tk-2anc correctness && green tk-2anc arch; then ok "both lanes green before the human batch"; else bad "setup: two lanes did not green"; fi
N2=$("$SUT" supersede-anchor --anchor tk-2anc)
eq "$N2" "2" "supersede-anchor retires a backing on every declared lane"
if green tk-2anc correctness; then bad "correctness stayed green after anchor-wide supersede"; else ok "correctness returned to unreviewed"; fi
if green tk-2anc arch;  then bad "arch stayed green after anchor-wide supersede";  else ok "arch returned to unreviewed"; fi

# A checkless anchor (check_set=none) has no lane to move: no-op success, not error.
NONE_ANCHOR='{"id":"tk-nanc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"none"}}'
store "[$NONE_ANCHOR]"
if NN=$("$SUT" supersede-anchor --anchor tk-nanc); then ok "supersede-anchor succeeds on a checkless (none) anchor"; else bad "supersede-anchor failed on a none anchor"; fi
eq "$NN" "0" "…and reports zero lanes retired"

# Fail closed: an unreadable anchor is never a silent no-op that leaves a check green.
store "[$CODEX_ANCHOR]"
STUB_SHOW_FAIL=1 "$SUT" supersede-anchor --anchor tk-hanc >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an unreadable anchor fails closed on supersede-anchor (exit 2)"
# An anchor that declares no check_set at all is anomalous, not checkless.
NOCS_ANCHOR='{"id":"tk-xanc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request"}}'
store "[$NOCS_ANCHOR]"
"$SUT" supersede-anchor --anchor tk-xanc >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an anchor with no check_set fails closed (exit 2)"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
