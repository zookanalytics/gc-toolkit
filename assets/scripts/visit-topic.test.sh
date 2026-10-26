#!/usr/bin/env bash
# Hermetic test for assets/scripts/visit-topic.sh, the one definition of a
# visit's topic.
# Covers:
#   (DEF)     sourcing the file exposes $VISIT_TOPIC_JQ, and the fixture carries
#             its visit, its subject and its cases
#   (CASES)   every case in visit-topic.fixture.json: the kind the decision
#             gives, and the fold and demand encodings of it
#   (READERS) converse-fold.sh, converse-hold.sh and converse-signoff.sh source
#             this file and apply its encodings: the fold its fold topic, the
#             hold and the sign-off its demand topic
#   (NO-COPY) no other file in the pack defines the topic defs or reads the
#             visit_topic stamp itself
# A consumer with a private copy of the rule drifts silently from the others,
# and then a sitting's fold identity and the demands it owns disagree. The
# behavioral half lives beside each consumer (converse-fold-scope.test.sh,
# converse-hold.test.sh, converse-signoff.test.sh), each running its consumer
# over the same fixture.
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/visit-topic.sh"
FX="$HERE/visit-topic.fixture.json"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=visit-topic.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${VISIT_TOPIC_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$VISIT_TOPIC_JQ" || bad "(DEF) sourcing the file exposes \$VISIT_TOPIC_JQ"
jq -e '(.visit | type) == "string" and (.subject | type) == "string" and (.cases | type) == "array" and (.cases | length) > 0' "$FX" >/dev/null 2>&1 \
    && ok "(DEF) the fixture carries a visit, a subject and its cases" || bad "(DEF) the fixture carries a visit, a subject and its cases"

VISIT="$(jq -r '.visit' "$FX")"
SUBJECT="$(jq -r '.subject' "$FX")"
# ask <metadata-json> <program> — the program run over the case's visit row.
ask() { jq -nr --arg v "$VISIT" --arg s "$SUBJECT" --argjson m "$1" "$VISIT_TOPIC_JQ"'{id: $v, metadata: $m} | '"$2" 2>/dev/null; }

echo "# the fixture's cases"
while IFS= read -r c; do
    [ -n "$c" ] || continue
    name="$(printf '%s' "$c" | jq -r '.name')"
    meta="$(printf '%s' "$c" | jq -c '.metadata')"
    eq "$(ask "$meta" 'visit_topic_kind')" "$(printf '%s' "$c" | jq -r '.kind')" "(CASES) $name: its kind"
    eq "$(ask "$meta" 'visit_fold_topic($s)')" "$(printf '%s' "$c" | jq -r '.fold_topic')" "(CASES) $name: its fold topic"
    eq "$(ask "$meta" 'visit_demand_topic')" "$(printf '%s' "$c" | jq -r '.demand_topic')" "(CASES) $name: its demand topic"
done <<< "$(jq -c '.cases[]' "$FX")"

echo "# a row with no metadata"
eq "$(printf '%s' '{"id":"v-y"}' | jq -r --arg s "$SUBJECT" "$VISIT_TOPIC_JQ"'[visit_topic_kind, visit_fold_topic($s), visit_demand_topic] | join("|")')" \
   "subject|$SUBJECT|" "(CASES) a row with no metadata is an ordinary visit"

echo "# every consumer applies the one definition"
# Comment lines are left out, so a consumer that names the library in prose but
# no longer calls it still fails.
reader() { # <path> <def it applies>
    local f="$ROOT/$1" code
    if [ ! -f "$f" ]; then bad "(READERS) $1 exists"; return; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    grep -qE '^[[:space:]]*\.[[:space:]].*visit-topic\.sh' <<< "$code" \
        && ok "(READERS) $1 sources visit-topic.sh" || bad "(READERS) $1 sources visit-topic.sh"
    grep -q 'VISIT_TOPIC_JQ' <<< "$code" && ok "(READERS) $1 applies \$VISIT_TOPIC_JQ" || bad "(READERS) $1 applies \$VISIT_TOPIC_JQ"
    grep -qE "(^|[^[:alnum:]_])$2([^[:alnum:]_]|\$)" <<< "$code" \
        && ok "(READERS) $1 takes its topic from $2" || bad "(READERS) $1 takes its topic from $2"
}
reader assets/scripts/converse-fold.sh visit_fold_topic
reader assets/scripts/converse-hold.sh visit_demand_topic
reader assets/scripts/converse-signoff.sh visit_demand_topic

echo "# no private copies"
# A copy is a jq def of one of the topic's names, or a read of the visit_topic
# stamp outside this definition. Specs and generated renders are history and
# output, not consumers.
DEF_RE='def[[:space:]]+(visit_topic_kind|visit_fold_topic|visit_demand_topic)[^[:alnum:]_]'
READ_RE='\.visit_topic([^[:alnum:]_]|$)|\["visit_topic"\]'
DEFS=""; READS=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/visit-topic.test.sh") continue ;; esac
        DEFS="$DEFS ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$DEF_RE" "$ROOT/$d" 2>/dev/null)"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/visit-topic.test.sh") continue ;; esac
        READS="$READS ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$READ_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${DEFS# }" "" "(NO-COPY) no file outside visit-topic.sh defines the topic's defs"
eq "${READS# }" "" "(NO-COPY) no file outside visit-topic.sh reads the visit_topic stamp"

echo
echo "visit-topic: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
