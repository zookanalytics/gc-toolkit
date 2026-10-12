#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-finishing-priority.sh, the one definition
# of the priority PR-finishing work is filed at. Covers:
#   (DEF)      sourcing the file defines pr_finishing_priority
#   (RANK)     an approved posture, bare or as recorded, ranks P0; every other
#              posture, and none, ranks P1
#   (VOCAB)    approved is a posture lifecycle.toml declares, so a renamed
#              vocabulary cannot leave the rank reading a word nothing records
#   (CREATORS) every creator sources this file, calls pr_finishing_priority and
#              writes the priority it gets
# The behavioral half lives beside each creator (pr-facts.test.sh,
# pre-open-rebase.test.sh, rework-child.test.sh, gate-ensure.test.sh), which
# assert the priority each child is filed and poured at. signoff.test.sh asserts
# it for a review's rework, which signoff.sh files through rework-child.sh.
# Reads the repo only; no gc, no city, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/pr-finishing-priority.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

# shellcheck source=pr-finishing-priority.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
declare -F pr_finishing_priority >/dev/null \
    && ok "(DEF) sourcing the file defines pr_finishing_priority" \
    || bad "(DEF) sourcing the file defines pr_finishing_priority"

echo "# the rank"
HEAD_OID=$(printf 'a%.0s' $(seq 1 40))
eq "$(pr_finishing_priority approved)" "0" "(RANK) an approved posture ranks P0"
eq "$(pr_finishing_priority "approved@$HEAD_OID@2026-10-11T00:00:00Z")" "0" \
   "(RANK) …given as recorded, pinned to a head and dated"
for p in changes_requested commented review_required none; do
    eq "$(pr_finishing_priority "$p@$HEAD_OID@2026-10-11T00:00:00Z")" "1" "(RANK) a $p posture ranks P1"
done
eq "$(pr_finishing_priority "")" "1" "(RANK) no posture recorded ranks P1"
eq "$(pr_finishing_priority "approved_once@$HEAD_OID@2026-10-11T00:00:00Z")" "1" \
   "(RANK) only the posture word approved itself ranks P0"

echo "# the vocabulary"
POSTURES=$(sed -n 's/^postures = \[\(.*\)\]$/\1/p' "$ROOT/lifecycle/lifecycle.toml")
case "$POSTURES" in
    *'"approved"'*) ok "(VOCAB) lifecycle/lifecycle.toml declares the approved posture" ;;
    *) bad "(VOCAB) lifecycle/lifecycle.toml declares the approved posture (postures: '${POSTURES:-unread}')" ;;
esac

echo "# every creator sources the one definition"
CREATORS="assets/scripts/pr-facts.sh
assets/scripts/pre-open-rebase.sh
assets/scripts/rework-child.sh
assets/scripts/gate-ensure.sh"
for c in $CREATORS; do
    f="$ROOT/$c"
    if [ ! -f "$f" ]; then bad "(CREATORS) $c exists"; continue; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    grep -qE '^[[:space:]]*\.[[:space:]].*pr-finishing-priority\.sh' <<< "$code" \
        && ok "(CREATORS) $c sources pr-finishing-priority.sh" \
        || bad "(CREATORS) $c sources pr-finishing-priority.sh"
    grep -qE 'pr_finishing_priority[[:space:]]' <<< "$code" \
        && ok "(CREATORS) $c calls pr_finishing_priority" \
        || bad "(CREATORS) $c calls pr_finishing_priority"
    grep -qF -- '--priority' <<< "$code" \
        && ok "(CREATORS) $c writes the priority it gets" \
        || bad "(CREATORS) $c writes the priority it gets"
done

echo
echo "pr-finishing-priority: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
