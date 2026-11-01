#!/usr/bin/env bash
# Hermetic test for assets/scripts/hold-lib.sh, the one definition of a hold.
# Covers:
#   (DEF)     sourcing the file exposes $HOLD_JQ, hold_graph and the depth cap
#   (CASES)   every case in hold-lib.fixture.json: the holds the predicate finds,
#             nearest first, the release time, and the reads the walk makes
#   (LABEL)   how a reader prints a hold: the blocker and its title, the
#             ancestor whose edge it sits on, an unreadable blocker or ancestor,
#             an absent ancestor named nowhere, and how many more hold the bead;
#             one blocker reached twice is one
#   (FLIGHT)  which keys put a bead in flight, and how a reader names the one
#             that does
#   (SHAPE)   a bead read by `bd show` gives the same edges as one read by a list
#   (FAIL)    a read that fails or does not parse fails the walk, and a chain
#             deeper than the cap holds the bead as unread
#   (ANNOTATE) hold_annotate gives every bead of one listing the state, label
#             and release time the predicate finds for it alone, fails whole on
#             a read that fails or input that is not an array, and leaves no
#             scratch behind
#   (READERS) every reader of a hold sources this file, and either applies
#             $HOLD_JQ and builds its graph with hold_graph, or reads its
#             listing's holds with hold_annotate
#   (NO-COPY) no other file in the pack defines the predicate's jq defs
# A reader with a private copy of the predicate drifts silently from this one.
# The behavioral half lives beside each reader (deferred-dispatch.test.sh,
# doctor/check-armed-dispatch-owed/run.test.sh, find-work-gating-guard.test.sh,
# refinery-stuck-handoff.test.sh, doctor/check-refinery-patrol-live/run.test.sh).
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

# The predicate reads a human gate by bd-lib.sh's rule, so a reader sources
# bd-lib.sh first, and the source fails without it.
# shellcheck source=hold-lib.sh
if ( unset HUMAN_GATE_JQ; . "$LIB" ) 2>/dev/null; then bad "(DEF) sourcing the file without bd-lib.sh's human gate rule fails"
else ok "(DEF) sourcing the file without bd-lib.sh's human gate rule fails"; fi
# shellcheck source=bd-lib.sh
. "$HERE/bd-lib.sh" || { echo "FAIL - cannot source $HERE/bd-lib.sh" >&2; exit 1; }
# shellcheck source=hold-lib.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${HOLD_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$HOLD_JQ" || bad "(DEF) sourcing the file exposes \$HOLD_JQ"
[ "$(type -t hold_graph)" = "function" ] && ok "(DEF) sourcing the file defines hold_graph" || bad "(DEF) sourcing the file defines hold_graph"
[ "$(type -t hold_annotate)" = "function" ] && ok "(DEF) sourcing the file defines hold_annotate" || bad "(DEF) sourcing the file defines hold_annotate"
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
eq "$(ask 'hold_summary($g[0])')" "" "(LABEL) an ancestor the store does not return names no hold"
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

echo "# what holds a bead bd reports ready"
# bd counts a pinned blocker as none, so bd can report a bead ready while a
# pinned human gate holds it. A reader that takes the readiness bd reports asks
# hold_holds_ready, which keeps the holds of human gates alone: for every other
# blocker the answer bd gives stands, an edge it cannot resolve included.
ready_by() { ask '[ hold_holds_ready($g[0])[] | {by, on} ] | tojson'; }
walk s-1
eq "$(ready_by)" '[{"by":"gate-s","on":"s-1"}]' "(READY) a pinned human gate on the bead holds it though bd reports it ready"
walk t-1
eq "$(ready_by)" '[{"by":"gate-t","on":"epic-t"}]' "(READY) so does a pinned human gate on its ancestor"
walk d-1
eq "$(ready_by)" '[{"by":"gate-d","on":"d-1"}]' "(READY) an open human gate holds it as well"
walk m-1
eq "$(ready_by)" '[{"by":"gate-m","on":"epic-m"}]' "(READY) of a park and a human gate on one epic, the gate is the hold bd did not count"
walk a-1
eq "$(ready_by)" '[]' "(READY) a park is no hold beside a ready answer, since bd counted it"
walk i-1
eq "$(ready_by)" '[]' "(READY) nor is a blocker the store does not return, which bd resolves to none"
walk u-1
eq "$(ready_by)" '[]' "(READY) nor a pinned gate of another type"
walk d-1
eq "$(ask '[ hold_holds($g[0])[] | .human ] | tojson')" '[true]' "(READY) a hold by a human gate is marked human"
walk e-1
eq "$(ask '[ hold_holds($g[0])[] | .human ] | tojson')" '[false]' "(READY) a hold by any other blocker is not"
walk i-1
eq "$(ask '[ hold_holds($g[0])[] | .human ] | tojson')" '[false]' "(READY) nor is a blocker with no row, which nothing shows to be a gate"

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
eq "$(ask 'hold_summary($g[0])')" "ancestor deep-$deep (unreadable)" "(LABEL) an ancestor the walk never read says so"
[ "$(reads)" -le $((HOLD_MAX_DEPTH + 1)) ] && ok "(FAIL) the walk stops reading at the cap ($(reads) reads)" \
    || bad "(FAIL) the walk stops reading at the cap ($(reads) reads)"

echo "# a listing annotated in one walk"
# Every case's bead in one listing, walked together. Each must come back with
# the state, label and release time the predicate finds for it walked alone.
ANN="$TMP/annotate"; mkdir -p "$ANN"
jq -c '[ .cases[].bead ] as $b | [ .beads[] | select(.id as $i | $b | index($i)) ]' "$FX" > "$TMP/listing.json"
if ANNOTATED="$(TMPDIR="$ANN" hold_annotate fx_read < "$TMP/listing.json")"; then
    ok "(ANNOTATE) a listing of every case's bead is annotated"
else
    bad "(ANNOTATE) a listing of every case's bead is annotated"; ANNOTATED='[]'
fi
eq "$(printf '%s' "$ANNOTATED" | jq 'length')" "$(jq '.cases | length' "$FX")" "(ANNOTATE) every bead of the listing comes back"
while IFS= read -r c; do
    [ -n "$c" ] || continue
    name="$(printf '%s' "$c" | jq -r '.name')"
    bead="$(printf '%s' "$c" | jq -r '.bead')"
    want="$(printf '%s' "$c" | jq -c '{state: (if any(.holds[]; .unread | not) then "held" elif (.holds | length) > 0 then "unread" else "free" end), released_at}')"
    walk "$bead" || { bad "(ANNOTATE) $name: the walk for $bead fails"; continue; }
    want_why="$(ask 'hold_summary($g[0])')"
    eq "$(printf '%s' "$ANNOTATED" | jq -c --arg b "$bead" '.[] | select(.id == $b) | .hold | {state, released_at}')" "$want" "(ANNOTATE) $name: state and released_at"
    eq "$(printf '%s' "$ANNOTATED" | jq -r --arg b "$bead" '.[] | select(.id == $b) | .hold.why')" "$want_why" "(ANNOTATE) $name: why is the bead's own summary"
done <<< "$(jq -c '.cases[]' "$FX")"
eq "$(printf '%s' "$ANNOTATED" | jq -c '[.[] | select(.id == "e-1")] | .[0] | del(.hold) | keys')" "$(jq -c '[.beads[] | select(.id == "e-1")] | .[0] | keys' "$FX")" \
   "(ANNOTATE) each bead keeps every field it came with"
out_fail="$(TMPDIR="$ANN" hold_annotate fail_read < "$TMP/listing.json")"; rc=$?
[ "$rc" -ne 0 ] && ok "(ANNOTATE) a read that fails fails the whole listing" || bad "(ANNOTATE) a read that fails fails the whole listing"
eq "$out_fail" "" "(ANNOTATE) and prints nothing a caller could take for a verdict"
out_junk="$(printf 'not json' | TMPDIR="$ANN" hold_annotate fx_read)"; rc=$?
[ "$rc" -ne 0 ] && ok "(ANNOTATE) input that is not a JSON array fails" || bad "(ANNOTATE) input that is not a JSON array fails"
eq "$out_junk" "" "(ANNOTATE) and prints nothing"
eq "$(printf '[]' | TMPDIR="$ANN" hold_annotate fx_read)" "[]" "(ANNOTATE) an empty listing is an empty array"
eq "$(find "$ANN" -mindepth 1 | wc -l | tr -d ' ')" "0" "(ANNOTATE) no scratch is left behind, on success or failure"

echo "# every reader sources the one definition"
# Comment lines are left out, so a reader that names the library in prose but
# no longer calls it still fails.
READERS="assets/scripts/deferred-dispatch.sh
doctor/check-armed-dispatch-owed/run.sh
doctor/check-refinery-patrol-live/run.sh
formulas/mol-refinery-patrol.toml
formulas/mol-witness-patrol.toml"
for r in $READERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    grep -qE '(^|[;&|[:space:]])\.[[:space:]].*hold-lib\.sh' <<< "$code" \
        && ok "(READERS) $r sources hold-lib.sh" || bad "(READERS) $r sources hold-lib.sh"
    if grep -qE '(^|[^[:alnum:]_])hold_annotate[[:space:]]' <<< "$code"; then
        ok "(READERS) $r reads its listing's holds with hold_annotate"
        continue
    fi
    grep -q 'HOLD_JQ' <<< "$code" && ok "(READERS) $r applies \$HOLD_JQ" || bad "(READERS) $r applies \$HOLD_JQ"
    grep -qE '(^|[^[:alnum:]_])hold_graph[[:space:]]' <<< "$code" \
        && ok "(READERS) $r builds its graph with hold_graph" || bad "(READERS) $r builds its graph with hold_graph"
done

echo "# no private copies"
# A copy is a jq def of one of the predicate's names. Specs and generated
# renders are history and output, not readers.
DEF_RE='def[[:space:]]+(hold_edges|hold_parent_ids|hold_blocker_ids|hold_done|hold_blocker_open|hold_flight_why|hold_in_flight|hold_absent|hold_chain|hold_holds|hold_held|hold_holds_ready|hold_released_at)[^[:alnum:]_]'
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
