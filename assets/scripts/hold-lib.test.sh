#!/usr/bin/env bash
# Hermetic test for assets/scripts/hold-lib.sh, the one definition of a hold.
# Covers:
#   (DEF)     sourcing the file exposes $HOLD_JQ, hold_graph and the depth cap
#   (CASES)   every case in hold-lib.fixture.json: the holds the predicate finds,
#             nearest first, the release time, and the reads the walk makes
#   (LABEL)   how a reader prints a hold: the blocker and its title, the
#             ancestor whose edge it sits on, an unreadable blocker or ancestor,
#             and how many more hold the bead; one blocker reached twice is one
#   (FLIGHT)  which keys put a bead in flight, and how a reader names the one
#             that does
#   (SHAPE)   a bead read by `bd show` gives the same edges as one read by a list
#   (FAIL)    a read that fails or does not parse fails the walk, and a chain
#             deeper than the cap holds the bead as unread
#   (READERS) every reader of a hold sources this file, applies $HOLD_JQ and
#             builds its graph with hold_graph
#   (NO-COPY) no other file in the pack defines the predicate's jq defs
# A reader with a private copy of the predicate drifts silently from this one.
# The behavioral half lives beside each reader (deferred-dispatch.test.sh,
# doctor/check-armed-dispatch-owed/run.test.sh).
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/hold-lib.sh"
FX="$HERE/hold-lib.fixture.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-hold-lib-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=hold-lib.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${HOLD_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$HOLD_JQ" || bad "(DEF) sourcing the file exposes \$HOLD_JQ"
[ "$(type -t hold_graph)" = "function" ] && ok "(DEF) sourcing the file defines hold_graph" || bad "(DEF) sourcing the file defines hold_graph"
case "${HOLD_MAX_DEPTH:-}" in ''|*[!0-9]*) bad "(DEF) HOLD_MAX_DEPTH is a whole number (got '${HOLD_MAX_DEPTH:-}')" ;; *) ok "(DEF) HOLD_MAX_DEPTH is a whole number" ;; esac
jq -e '(.beads | type) == "array" and (.cases | type) == "array" and (.cases | length) > 0' "$FX" >/dev/null 2>&1 \
    && ok "(DEF) the fixture carries a store and its cases" || bad "(DEF) the fixture carries a store and its cases"

# The reader the walk calls: the fixture store, by id, the way a real reader
# answers from its own store. Each call is logged so the reads can be counted.
STORE="$FX"
READS="$TMP/reads.log"
fx_read() {
    printf '%s\n' "$1" >> "$READS"
    jq -c --arg ids "$1" '($ids | split(",")) as $w | [ (if type == "array" then . else .beads end)[] | select(.id as $i | $w | index($i)) ]' "$STORE"
}
# walk <bead-id> [<bead-json>]: the walk for one bead, leaving its seed and its
# graph for ask. The seed is the bead's row in the store unless one is given.
walk() {
    : > "$READS"
    if [ -n "${2:-}" ]; then printf '[%s]' "$2" > "$TMP/seed.json"
    else jq -c --arg b "$1" '[ (if type == "array" then . else .beads end)[] | select(.id == $b) ]' "$STORE" > "$TMP/seed.json"; fi
    hold_graph fx_read "$TMP/seed.json" "$TMP/graph.json"
}
ask() { jq -r --slurpfile g "$TMP/graph.json" "$HOLD_JQ"".[0] | $1" "$TMP/seed.json" 2>/dev/null; }
reads() { wc -l < "$READS" | tr -d ' '; }

echo "# the fixture's cases"
while IFS= read -r c; do
    [ -n "$c" ] || continue
    name="$(printf '%s' "$c" | jq -r '.name')"
    bead="$(printf '%s' "$c" | jq -r '.bead')"
    if ! walk "$bead"; then bad "(CASES) $name: the walk for $bead fails"; continue; fi
    eq "$(ask '[ hold_holds($g[0])[] | {by, on, unread} ] | tojson')" "$(printf '%s' "$c" | jq -c '.holds')" "(CASES) $name"
    eq "$(ask 'hold_released_at($g[0]) | tojson')" "$(printf '%s' "$c" | jq -c '.released_at')" "(CASES) $name: released_at"
    eq "$(ask 'hold_held($g[0]) | tostring')" "$(printf '%s' "$c" | jq -r '(.holds | length) > 0 | tostring')" "(CASES) $name: hold_held agrees with the holds"
    want_reads="$(printf '%s' "$c" | jq -r '.reads // empty')"
    [ -z "$want_reads" ] || eq "$(reads)" "$want_reads" "(CASES) $name: $want_reads read(s), one per generation and one for the blockers"
done <<< "$(jq -c '.cases[]' "$FX")"

echo "# how a hold reads"
walk a-1
eq "$(ask 'hold_summary($g[0])')" 'park-1 "Parked: the operator unparks the epic" on ancestor epic-a' \
   "(LABEL) a hold on an ancestor names the blocker, its title and the ancestor"
walk e-1
eq "$(ask 'hold_summary($g[0])')" "e-0 \"e-1's open prerequisite\"" "(LABEL) a hold of the bead's own names the blocker and its title"
walk i-1
eq "$(ask 'hold_summary($g[0])')" "ghost-i (unreadable)" "(LABEL) an unreadable blocker says so"
walk j-1
eq "$(ask 'hold_summary($g[0])')" "ancestor ghost-epic (unreadable)" "(LABEL) an unreadable ancestor says so"
walk f-1
eq "$(ask 'hold_summary($g[0])')" "" "(LABEL) a bead nothing holds has an empty summary"
two='{"id":"two-1","title":"Two holds","status":"open","dependencies":[{"issue_id":"two-1","depends_on_id":"e-0","type":"blocks"},{"issue_id":"two-1","depends_on_id":"epic-a","type":"parent-child"}]}'
walk two-1 "$two"
eq "$(ask 'hold_summary($g[0])')" "e-0 \"e-1's open prerequisite\" (+1 more)" "(LABEL) the nearest hold is named, and the rest are counted"
twice='{"id":"twice-1","title":"Parked twice","status":"open","dependencies":[{"issue_id":"twice-1","depends_on_id":"park-1","type":"blocks"},{"issue_id":"twice-1","depends_on_id":"epic-a","type":"parent-child"}]}'
walk twice-1 "$twice"
eq "$(ask '[ hold_holds($g[0])[] | {by, on} ] | tojson')" '[{"by":"park-1","on":"twice-1"}]' \
   "(LABEL) one blocker on the bead and on its ancestor is one hold, the nearest"
nl='{"id":"nl-1","title":"x","status":"open","dependencies":[{"issue_id":"nl-1","depends_on_id":"nl-0","type":"blocks"}]}'
printf '%s' '[{"id":"nl-0","title":"line one\u0009tabbed\nline two","status":"open"}]' > "$TMP/nl-store.json"
STORE="$TMP/nl-store.json" walk nl-1 "$nl"
eq "$(ask 'hold_summary($g[0])')" 'nl-0 "line one tabbed line two"' "(LABEL) a control character in a title prints as a space"

echo "# what puts a bead in flight"
walk fl-1
eq "$(ask 'hold_flight_why')" "rejection_reason set" "(FLIGHT) a rejection_reason is named ahead of the branch it comes with"
walk fl-2
eq "$(ask 'hold_flight_why')" "branch polecat/fl-2" "(FLIGHT) a branch alone is named with its value"
walk fl-3
eq "$(ask 'hold_flight_why')" "merge_result=pull_request" "(FLIGHT) a merge_result is named with its value"
walk fl-blank
eq "$(ask 'hold_in_flight | tostring')" "false" "(FLIGHT) blank keys do not put a bead in flight"
walk a-1
eq "$(ask 'hold_in_flight | tostring')" "false" "(FLIGHT) a bead with none of the keys is not in flight"
eq "$(printf '%s' '{"id":"x","metadata":"not an object"}' | jq -r "$HOLD_JQ"'hold_in_flight | tostring')" "false" \
   "(FLIGHT) metadata that is not an object puts nothing in flight"

echo "# both shapes bd prints edges in"
shown='{"id":"a-1","status":"open","dependencies":[{"id":"epic-a","dependency_type":"parent-child","status":"open"}]}'
walk a-1 "$shown"
eq "$(ask '[ hold_holds($g[0])[] | {by, on} ] | tojson')" '[{"by":"park-1","on":"epic-a"}]' \
   "(SHAPE) a bead read by bd show is held by the same blocker as one read by a list"
eq "$(printf '%s' "$shown" | jq -c "$HOLD_JQ"'[hold_parent_ids, hold_blocker_ids]')" '[["epic-a"],[]]' \
   "(SHAPE) hold_edges reads a show's {id, dependency_type}"

echo "# a walk that cannot read"
jq -c '[ .beads[] | select(.id == "a-1") ]' "$FX" > "$TMP/seed.json"
fail_read() { return 3; }
hold_graph fail_read "$TMP/seed.json" "$TMP/graph.json"; rc=$?
[ "$rc" -ne 0 ] && ok "(FAIL) a read that fails fails the walk" || bad "(FAIL) a read that fails fails the walk"
junk_read() { printf '%s' '{"error":"no issues found"}'; }
hold_graph junk_read "$TMP/seed.json" "$TMP/graph.json"; rc=$?
[ "$rc" -ne 0 ] && ok "(FAIL) a read that is not a JSON array fails the walk" || bad "(FAIL) a read that is not a JSON array fails the walk"
printf 'not json' > "$TMP/bad-seed.json"
hold_graph fx_read "$TMP/bad-seed.json" "$TMP/graph.json"; rc=$?
[ "$rc" -ne 0 ] && ok "(FAIL) a seed that is not JSON fails the walk" || bad "(FAIL) a seed that is not JSON fails the walk"

# A chain one generation deeper than the cap, with a park at the top. The walk
# stops at the cap, so the ancestor past it is never read and holds the bead.
deep=$((HOLD_MAX_DEPTH + 1))
jq -nc --argjson n "$deep" '
    [ range(0; $n) as $i
      | {id: "deep-\($i)", title: "level \($i)", status: "open",
         dependencies: [ {issue_id: "deep-\($i)", depends_on_id: "deep-\($i + 1)", type: "parent-child"} ]} ]
    + [ {id: "deep-\($n)", title: "the top", status: "open",
         dependencies: [ {issue_id: "deep-\($n)", depends_on_id: "park-1", type: "blocks"} ]},
        {id: "park-1", title: "Parked", status: "open", issue_type: "gate"} ]' > "$TMP/deep.json"
STORE="$TMP/deep.json" walk deep-0
eq "$(ask '[ hold_holds($g[0])[] | {by, unread} ] | tojson')" "[{\"by\":\"deep-$deep\",\"unread\":true}]" \
   "(FAIL) an ancestor past the cap is never read, so it holds the bead"
[ "$(reads)" -le $((HOLD_MAX_DEPTH + 1)) ] && ok "(FAIL) the walk stops reading at the cap ($(reads) reads)" \
    || bad "(FAIL) the walk stops reading at the cap ($(reads) reads)"

echo "# every reader sources the one definition"
# Comment lines are left out, so a reader that names the library in prose but
# no longer calls it still fails.
READERS="assets/scripts/deferred-dispatch.sh
doctor/check-armed-dispatch-owed/run.sh"
for r in $READERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    grep -qE '^[[:space:]]*\.[[:space:]].*hold-lib\.sh' <<< "$code" \
        && ok "(READERS) $r sources hold-lib.sh" || bad "(READERS) $r sources hold-lib.sh"
    grep -q 'HOLD_JQ' <<< "$code" && ok "(READERS) $r applies \$HOLD_JQ" || bad "(READERS) $r applies \$HOLD_JQ"
    grep -qE '(^|[^[:alnum:]_])hold_graph[[:space:]]' <<< "$code" \
        && ok "(READERS) $r builds its graph with hold_graph" || bad "(READERS) $r builds its graph with hold_graph"
done

echo "# no private copies"
# A copy is a jq def of one of the predicate's names. Specs and generated
# renders are history and output, not readers.
DEF_RE='def[[:space:]]+(hold_edges|hold_parent_ids|hold_blocker_ids|hold_done|hold_is_demand_gate|hold_flight_why|hold_in_flight|hold_chain|hold_holds|hold_held|hold_released_at)[^[:alnum:]_]'
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/hold-lib.test.sh") continue ;; esac
        COPIES="$COPIES ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$DEF_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside hold-lib.sh defines the hold predicate"

echo
echo "hold-lib: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
