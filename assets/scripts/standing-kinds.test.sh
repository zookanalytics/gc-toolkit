#!/usr/bin/env bash
# Hermetic test for assets/scripts/standing-kinds.sh, the one definition of the
# standing kinds. Covers:
#   (DEF)     the list is non-empty, unique, and names both kinds the pack writes
#             as standing records today
#   (PRED)    is_standing_kind is true for every listed kind and false for an
#             empty, absent, near-miss or ordinary task_kind
#   (READERS) every reader of the standing kinds sources this file and applies
#             $STANDING_KINDS_JQ
#   (NO-COPY) no other file in the pack carries a standing-kinds list of its own
# A reader with a private list drifts silently: it keeps excluding the kinds it
# copied and misses every kind added later. The behavioral half lives beside
# each reader (tools/gc-proactive.test.sh, liveness-recheck.test.sh,
# doctor/check-blocked-work-armed/run.test.sh), each driven by this list.
# Reads the repo only; no gc, no city, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/standing-kinds.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=standing-kinds.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${STANDING_KINDS_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$STANDING_KINDS_JQ" \
    || bad "(DEF) sourcing the file exposes \$STANDING_KINDS_JQ"

echo "# the list"
KINDS_JSON="$(jq -nc "$STANDING_KINDS_JQ"'standing_kinds' 2>/dev/null)"
eq "$(printf '%s' "$KINDS_JSON" | jq -r 'type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' 2>/dev/null)" \
   "true" "(DEF) standing_kinds is a non-empty list of non-empty strings"
eq "$(printf '%s' "$KINDS_JSON" | jq -r 'length == (unique | length)' 2>/dev/null)" \
   "true" "(DEF) standing_kinds names each kind once"
for k in triage-subject feedback-pattern; do
    eq "$(printf '%s' "$KINDS_JSON" | jq -r --arg k "$k" 'index($k) != null' 2>/dev/null)" \
       "true" "(DEF) standing_kinds names $k"
done

echo "# the predicate"
for k in $(printf '%s' "$KINDS_JSON" | jq -r '.[]'); do
    eq "$(jq -nc --arg k "$k" '{metadata: {task_kind: $k}}' | jq -r "$STANDING_KINDS_JQ"'is_standing_kind')" \
       "true" "(PRED) a task_kind=$k bead is a standing record"
done
for case in '{"metadata":{"task_kind":""}}' '{"metadata":{}}' '{}' \
            '{"metadata":{"task_kind":"triage-subjects"}}' \
            '{"metadata":{"task_kind":"visit"}}' '{"metadata":{"task_kind":"review"}}'; do
    eq "$(printf '%s' "$case" | jq -r "$STANDING_KINDS_JQ"'is_standing_kind')" \
       "false" "(PRED) $case is not a standing record"
done

echo "# every reader sources the one definition"
READERS="tools/gc-proactive.sh
assets/scripts/liveness-sweep.sh
assets/scripts/liveness-recheck.sh
doctor/check-blocked-work-armed/run.sh
doctor/check-hq-marooned-work/run.sh"
for r in $READERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    grep -qE '^[[:space:]]*\.[[:space:]].*standing-kinds\.sh' "$f" \
        && ok "(READERS) $r sources standing-kinds.sh" \
        || bad "(READERS) $r sources standing-kinds.sh"
    grep -q 'STANDING_KINDS_JQ' "$f" \
        && ok "(READERS) $r applies \$STANDING_KINDS_JQ" \
        || bad "(READERS) $r applies \$STANDING_KINDS_JQ"
done

echo "# no private copies"
# A copy is a jq def of the list, or both kinds named side by side in one list
# literal. Specs and generated renders are history and output, not readers.
COPY_RE='def standing_kinds|"triage-subject"[[:space:]]*,[[:space:]]*"feedback-pattern"|"feedback-pattern"[[:space:]]*,[[:space:]]*"triage-subject"'
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/standing-kinds.test.sh") continue ;; esac
        COPIES="$COPIES ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$COPY_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside standing-kinds.sh carries its own standing-kinds list"

echo
echo "standing-kinds: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
