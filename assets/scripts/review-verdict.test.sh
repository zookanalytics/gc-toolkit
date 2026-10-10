#!/usr/bin/env bash
# Hermetic test for assets/scripts/review-verdict.sh, the one definition of the
# approval rule. Covers:
#   (DEF)     sourcing the file exposes $REVIEW_VERDICT_DEF
#   (PRED)    review_verdict: each account other than the city takes its latest
#             APPROVED or CHANGES_REQUESTED review; a dismissed review drops out
#             before the latest is taken; a COMMENTED review is neither; a tie on
#             the timestamp falls to the review id. standing_approvals names
#             every outside approval not yet dismissed, and dismissing that set
#             leaves no approver behind.
#   (READERS) every reader of the rule sources this file and applies
#             $REVIEW_VERDICT_DEF
#   (NO-COPY) no other file in the pack carries a jq definition of the rule
# A reader with a private copy drifts silently: the merge gate and the arm that
# brings a branch current would then disagree about which PRs are approved. The
# behavioral half lives beside each reader (merge.test.sh, pr-facts.test.sh).
# Reads the repo only; no gc, no city, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/review-verdict.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=review-verdict.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${REVIEW_VERDICT_DEF:-}" ] && ok "(DEF) sourcing the file exposes \$REVIEW_VERDICT_DEF" \
    || bad "(DEF) sourcing the file exposes \$REVIEW_VERDICT_DEF"

SELF="gc-city-bot"
verdict() { printf '%s' "$1" | jq -c --arg self "$SELF" "$REVIEW_VERDICT_DEF"'review_verdict($self)'; }
approvals() { printf '%s' "$1" | jq -c --arg self "$SELF" "$REVIEW_VERDICT_DEF"'[ standing_approvals($self)[] | .id ]'; }
# The verdict after a withdrawal dismisses the standing approvals, and then after
# every CHANGES_REQUESTED is dismissed too, the way pr-facts.sh clears a request
# once its findings close.
withdrawn() { printf '%s' "$1" | jq -c --arg self "$SELF" "$REVIEW_VERDICT_DEF"'
  [ standing_approvals($self)[] | .id ] as $ids
  | map(if (.id as $i | any($ids[]; . == $i)) then .state = "DISMISSED" else . end)
  | [ review_verdict($self), (map(if .state == "CHANGES_REQUESTED" then .state = "DISMISSED" else . end) | review_verdict($self)) ]'; }
rv() { # id login state submitted_at
  printf '{"id":%s,"user":{"login":"%s"},"state":"%s","submitted_at":"%s"}' "$1" "$2" "$3" "$4"
}

echo "# the rule"
eq "$(verdict '[]')" '{"veto":"","approver":""}' "(PRED) no reviews: no approver, no veto"
eq "$(verdict "[$(rv 1 human1 APPROVED 2026-08-20T00:00:00Z)]")" '{"veto":"","approver":"human1"}' \
   "(PRED) an outside approval is the approver"
eq "$(verdict "[$(rv 1 $SELF APPROVED 2026-08-20T00:00:00Z)]")" '{"veto":"","approver":""}' \
   "(PRED) the city's own approval is not one"
eq "$(verdict "[$(rv 1 human1 DISMISSED 2026-08-20T00:00:00Z)]")" '{"veto":"","approver":""}' \
   "(PRED) a dismissed approval is not one"
eq "$(verdict "[$(rv 1 human1 APPROVED 2026-08-20T00:00:00Z),$(rv 2 human1 CHANGES_REQUESTED 2026-08-21T00:00:00Z)]")" \
   '{"veto":"human1","approver":""}' "(PRED) a later CHANGES_REQUESTED replaces the same account's approval"
eq "$(verdict "[$(rv 1 human1 CHANGES_REQUESTED 2026-08-20T00:00:00Z),$(rv 2 human1 APPROVED 2026-08-21T00:00:00Z)]")" \
   '{"veto":"","approver":"human1"}' "(PRED) a later approval replaces the same account's CHANGES_REQUESTED"
eq "$(verdict "[$(rv 1 human1 APPROVED 2026-08-20T00:00:00Z),$(rv 2 human2 CHANGES_REQUESTED 2026-08-21T00:00:00Z)]")" \
   '{"veto":"human2","approver":"human1"}' "(PRED) another account's CHANGES_REQUESTED stands beside an approval as a veto"
eq "$(verdict "[$(rv 1 human1 APPROVED 2026-08-20T00:00:00Z),$(rv 2 human1 DISMISSED 2026-08-21T00:00:00Z)]")" \
   '{"veto":"","approver":"human1"}' "(PRED) a later dismissed review does not hide the same account's approval"
eq "$(verdict "[$(rv 1 human1 APPROVED 2026-08-20T00:00:00Z),$(rv 2 human1 COMMENTED 2026-08-21T00:00:00Z)]")" \
   '{"veto":"","approver":"human1"}' "(PRED) a later COMMENTED review does not hide it either"
eq "$(verdict "[$(rv 2 human1 APPROVED 2026-08-20T00:00:00Z),$(rv 1 human1 CHANGES_REQUESTED 2026-08-20T00:00:00Z)]")" \
   '{"veto":"","approver":"human1"}' "(PRED) a tie on the timestamp falls to the higher review id"

echo "# the standing approvals"
STANDING="[$(rv 1 human1 APPROVED 2026-08-20T00:00:00Z),$(rv 3 human1 APPROVED 2026-08-22T00:00:00Z),$(rv 2 human2 APPROVED 2026-08-21T00:00:00Z),$(rv 4 $SELF APPROVED 2026-08-21T00:00:00Z),$(rv 5 human3 APPROVED 2026-08-20T00:00:00Z),$(rv 6 human3 CHANGES_REQUESTED 2026-08-23T00:00:00Z),$(rv 7 human2 DISMISSED 2026-08-24T00:00:00Z)]"
eq "$(approvals "$STANDING")" '[1,3,2,5]' \
   "(PRED) every outside approval not yet dismissed: an account's older approval and one behind its later CHANGES_REQUESTED included, never the city's and never a dismissed review"
eq "$(withdrawn "$STANDING")" '[{"veto":"human3","approver":""},{"veto":"","approver":""}]' \
   "(PRED) dismissing the standing approvals leaves no approver, and none comes back once the later CHANGES_REQUESTED is dismissed"

echo "# every reader sources the one definition"
READERS="assets/scripts/merge.sh
assets/scripts/pr-facts.sh
assets/scripts/bring-current-guard.sh"
for r in $READERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    grep -qE '^[[:space:]]*\.[[:space:]].*review-verdict\.sh' "$f" \
        && ok "(READERS) $r sources review-verdict.sh" \
        || bad "(READERS) $r sources review-verdict.sh"
    grep -q 'REVIEW_VERDICT_DEF' "$f" \
        && ok "(READERS) $r applies \$REVIEW_VERDICT_DEF" \
        || bad "(READERS) $r applies \$REVIEW_VERDICT_DEF"
done

echo "# no private copies"
# A copy is a jq def of the rule under any of its names. Specs and generated
# renders are history and output, not readers.
COPY_RE='def (review_verdict|latest_opinions|standing_approvals)[[:space:]]*\('
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    hits=$(grep -rlE "$COPY_RE" "$ROOT/$d" 2>/dev/null | grep -vxF "$LIB" | grep -v '\.test\.sh$' || true)
    [ -n "$hits" ] && COPIES="$COPIES $hits"
done
eq "$(printf '%s' "$COPIES" | sed 's#'"$ROOT"'/##g' | tr -s ' ' | sed 's/^ //')" "" \
   "(NO-COPY) no file but review-verdict.sh defines the rule"

echo
echo "review-verdict: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
