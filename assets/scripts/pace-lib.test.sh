#!/usr/bin/env bash
# pace-lib.test.sh — hermetic tests for the paced walk the merge-cadence arms
# share: the rotation order after a cursor, the cursor write, the deadline, and
# the per-group bookkeeping (exempt never stops, first skips past the deadline
# and rotates on a cursor of its own, rest stops and resumes at the anchor it
# stopped at, and one anchor of each paced group is always visited), the
# deadline check pace_start makes for every arm, and the seen marks: recorded
# when a visit finishes, replaced mid-visit, never by a visit the deadline
# refused, compacted to one live mark per anchor, and read as no change by a
# walk that has none yet.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pace-lib-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
harness_init
# shellcheck disable=SC2034 # read by pace-lib.sh's warnings
PROG="pace-lib-test"
. "$HERE/pace-lib.sh"

rows() { # <id>... — one compact row per id, in the order given
  local i
  for i in "$@"; do printf '{"id":"%s","metadata":{}}\n' "$i"; done
}
ids() { jq -r '.id' | paste -sd, -; }
CUR="$TMP/walk.cursor"

echo "# pace_order: id order after the cursor, wrapping"
rm -f "$CUR"
eq "$(rows c a b | pace_order "$CUR" | ids)" "a,b,c" "an absent cursor file starts at the lowest id"
printf 'a\n' > "$CUR"
eq "$(rows c a b | pace_order "$CUR" | ids)" "b,c,a" "the walk starts after the cursor's id and wraps"
printf 'c\n' > "$CUR"
eq "$(rows c a b | pace_order "$CUR" | ids)" "a,b,c" "after the highest id it wraps to the lowest"
printf 'bb\n' > "$CUR"
eq "$(rows c a b | pace_order "$CUR" | ids)" "c,a,b" "a cursor naming an id no longer present starts at the next id after it"
eq "$(rows c a b | pace_order "" | ids)" "c,a,b" "with no cursor path the rows pass through in their own order"
eq "$(printf 'not json\n' | pace_order "$CUR")" "not json" "a reorder that fails passes the input through"

echo "# pace_note and pace_spent"
pace_note "$CUR" "z"; rc=$?
eq "$rc,$(cat "$CUR")" "0,z" "pace_note records the id"
pace_note "$TMP/no-such-dir/c" "z"; rc=$?
[ "$rc" -ne 0 ] && ok "an unwritable cursor is reported as a failed write" || bad "an unwritable cursor write returned 0"
pace_note "" "z"; eq "$?" 0 "an empty cursor path records nothing and succeeds"
pace_spent "" && bad "an empty deadline read as spent" || ok "an empty deadline is never spent"
pace_spent 1 && ok "a deadline in the past is spent" || bad "a deadline in the past read as unspent"
pace_spent "$(( $(date +%s) + 600 ))" && bad "a future deadline read as spent" || ok "a future deadline is not spent"

# walk <deadline> <group:id>... — runs the documented loop; prints the visits.
walk() {
  local dl="$1" g id seen=""; shift
  pace_start "$CUR" "$dl"
  for gi in "$@"; do
    g="${gi%%:*}"; id="${gi#*:}"
    pace_visit "$g" "$id"; case $? in 1) continue ;; 2) break ;; esac
    seen="${seen:+$seen,}$id"
  done
  pace_end
  printf '%s\n' "$seen"
}

echo "# the walk: rest anchors stop at the deadline and resume after the last one finished"
rm -f "$CUR"
eq "$(walk 1 rest:a rest:b rest:c)" "a" "past the deadline one rest anchor is visited, then the walk stops"
walk 1 rest:a rest:b rest:c >/dev/null
eq "$PACE_RESUME_AT" "b" "PACE_RESUME_AT names the anchor the deadline stopped at"
eq "$(cat "$CUR")" "a" "the cursor names the rest anchor the walk finished"
eq "$(walk "$(( $(date +%s) + 600 ))" rest:a rest:b rest:c)" "a,b,c" "before the deadline every anchor is visited"
eq "$(cat "$CUR")" "c" "the cursor names the last anchor finished"

echo "# the walk: exempt anchors are never stopped, and never move the cursor"
printf 'q\n' > "$CUR"
eq "$(walk 1 exempt:x exempt:y rest:a rest:b)" "x,y,a" "exempt anchors all visit past the deadline, then one rest anchor"
eq "$(cat "$CUR")" "a" "only the rest anchor moved the cursor"

echo "# the walk: first anchors come first, are skipped past the deadline, and the rest still run"
printf 'q\n' > "$CUR"; rm -f "$CUR.first"
out=$(walk 1 first:f1 first:f2 first:f3 rest:a rest:b)
eq "$out" "f1,a" "past the deadline one first anchor and one rest anchor are visited"
walk 1 first:f1 first:f2 first:f3 rest:a rest:b >/dev/null
eq "$PACE_FIRST_SKIPPED,$PACE_VISITED,$PACE_RESUME_AT" "2,2,b" "the skipped first anchors are counted, and the rest walk names where it stopped"
eq "$(cat "$CUR")" "a" "first anchors never move the rest cursor"
eq "$PACE_FIRST_CURSOR" "$CUR.first" "first anchors rotate on a cursor of their own, beside the rest cursor"
eq "$(cat "$CUR.first" 2>/dev/null)" "f1" "…which names the first anchor the walk finished"
eq "$(rows f3 f1 f2 | pace_order "$PACE_FIRST_CURSOR" | ids)" "f2,f3,f1" "…so the next pass starts the first group after it, not at the anchor that led this one"

echo "# the walk: a first anchor is recorded once the walk moves on to the rest"
rm -f "$CUR" "$CUR.first"
pace_start "$CUR" ""
pace_visit first f1; pace_visit first f2; pace_visit rest a
eq "$(cat "$CUR.first" 2>/dev/null)" "f2" "the last first anchor is recorded when the first rest visit begins, so a kill there does not redo it"
pace_end
eq "$(cat "$CUR" 2>/dev/null)" "a" "pace_end records the rest anchor in hand"

echo "# pace_start: a deadline that is not epoch seconds leaves the walk unpaced"
rm -f "$CUR"
eq "$(walk soon rest:a rest:b rest:c 2>/dev/null)" "a,b,c" "a deadline that is not epoch seconds visits every anchor"
err=$( { walk soon rest:a >/dev/null; walk 12.5 rest:b >/dev/null; } 2>&1 )
has "$err" "--deadline 'soon' is not epoch seconds" "…and says so"
eq "$(printf '%s\n' "$err" | grep -c 'is not epoch seconds')" 1 "…once per process, however many walks start with one"
err=$( { walk "" rest:a >/dev/null; } 2>&1 )
eq "$err" "" "an empty deadline is no deadline, and warns nothing"

echo "# a cursor write that fails warns once and the walk goes on"
CUR="$TMP/no-such-dir/walk.cursor"
err=$( { walk "$(( $(date +%s) + 600 ))" rest:a rest:b rest:c >/dev/null; } 2>&1 )
has "$err" "cannot record progress" "the failed write is reported"
eq "$(printf '%s\n' "$err" | grep -c 'cannot record progress')" 1 "…once per walk"
eq "$(walk "$(( $(date +%s) + 600 ))" rest:a rest:b rest:c 2>/dev/null)" "a,b,c" "…and every anchor is still visited"

echo "# seen marks: a walk with none reads nothing as changed, and one with marks compares"
CUR="$TMP/seen.cursor"; SEEN="$TMP/walk.seen"; rm -f "$CUR" "$SEEN"
pace_seen_start "$SEEN"
eq "$PACE_SEEN_FRESH" 1 "a walk whose seen file does not exist has no marks"
pace_seen_changed a m1 && bad "a walk with no marks read an anchor as changed" || ok "with no marks nothing reads as changed, so the caller seeds instead"
pace_seen_put a m1
pace_seen_put b m1
eq "$(pace_seen_get a)" "m1" "a recorded mark reads back in the same walk"
pace_seen_start "$SEEN"
eq "$PACE_SEEN_FRESH" 0 "the next walk loads the marks"
pace_seen_changed a m1 && bad "the same mark read as a change" || ok "the same mark is no change"
pace_seen_changed a m2 && ok "a different mark is a change" || bad "a different mark read as no change"
pace_seen_changed c m1 && ok "an anchor the walk never saw is a change once it has marks" || bad "an unseen anchor read as no change"

echo "# seen marks: recorded when the visit finishes, which is when the cursor records it"
rm -f "$CUR" "$SEEN"
pace_start "$CUR" ""; pace_seen_start "$SEEN"
pace_visit rest a ma
eq "$(cut -f1,2 "$SEEN" 2>/dev/null | paste -sd, -)" "" "a visit in hand has recorded nothing yet"
pace_visit rest b mb
eq "$(cut -f1,2 "$SEEN" | paste -sd, -)" "a	ma" "the mark is recorded once the next visit begins"
pace_seen_mark "mb2"
pace_visit rest c
pace_end
eq "$(cut -f1,2 "$SEEN" | paste -sd, -)" "a	ma,b	mb2" "pace_seen_mark replaces the mark mid-visit, and a visit with no mark records none"
pace_seen_start "$SEEN"
eq "$(pace_seen_get b),$(pace_seen_get c)" "mb2," "…as the next walk reads them"

echo "# seen marks: a visit the deadline refused records nothing"
rm -f "$CUR" "$CUR.first" "$SEEN"
pace_start "$CUR" 1; pace_seen_start "$SEEN"
pace_visit first f1 mf1; pace_visit first f2 mf2; pace_visit rest r1 mr1; pace_visit rest r2 mr2
pace_end
eq "$(cut -f1,2 "$SEEN" | sort | paste -sd, -)" "f1	mf1,r1	mr1" "only the visits the deadline let through record a mark"

echo "# seen marks: compaction keeps the last mark per anchor and drops the stale and the malformed"
now=$(date +%s)
printf 'a\told\t%s\na\tnew\t%s\nb\tgone\t%s\nnot a mark line\nc\t\t%s\n' "$now" "$now" "$((now - 1209600 - 100))" "$now" > "$SEEN"
pace_seen_start "$SEEN"
eq "$(pace_seen_get a)" "new" "the last line for an anchor wins"
eq "$(pace_seen_get b)" "" "a mark older than the TTL is dropped"
eq "$(cut -f1,2 "$SEEN" | paste -sd, -)" "a	new" "the file is rewritten with one live mark per anchor"
PACE_SEEN_TTL_SECS=10
printf 'a\tm\t%s\n' "$((now - 60))" > "$SEEN"
pace_seen_start "$SEEN"
eq "$PACE_SEEN_FRESH" 1 "a file holding only expired marks reads as no marks"
unset PACE_SEEN_TTL_SECS

echo "# seen marks: a tab or newline in a mark is flattened, so it stays one line"
rm -f "$SEEN"; pace_seen_start "$SEEN"
pace_seen_put a "x	y
z"
eq "$(wc -l < "$SEEN" | tr -d ' ')" 1 "the record is one line"
pace_seen_start "$SEEN"
eq "$(pace_seen_get a)" "x y z" "…and reads back flattened"

echo "# seen marks: an empty path records nothing; an unwritable file warns once and the walk goes on"
pace_seen_start ""
pace_seen_put a m; eq "$?" 0 "a put with no seen file succeeds"
eq "$PACE_SEEN_FRESH" 1 "…and the walk has no marks"
CUR="$TMP/no-such-dir/walk.cursor"
err=$( { pace_start "$CUR" ""; pace_seen_start "$TMP/no-such-dir/walk.seen"
         pace_visit rest a ma; pace_visit rest b mb; pace_visit rest c mc; pace_end; } 2>&1 )
has "$err" "cannot record seen marks" "the failed record is reported"
eq "$(printf '%s\n' "$err" | grep -c 'cannot record seen marks')" 1 "…once per walk"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
