#!/usr/bin/env bash
# Hermetic test for assets/scripts/until-resolved.sh, the one place that
# decides which beads an `until` edge has resolved. Covers:
#   (SCAN)    until_scan selects an open, unassigned bead with an `until` edge,
#             and one in progress under the pass's own claim, read as the bead
#             it claimed, and nothing else; decides it waiting, unresolved,
#             blocked or owed;
#             names the successor that closed last and the moment the bead
#             became owed (the latest of its targets' closes, its edges'
#             creation and its blockers' closes); carries the live-work marks of
#             its row; writes "-" for an empty column; asks the status read for
#             closed and hidden-class beads; and reads each store once
#   (FAIL)    an unreadable or non-array listing exits 1 and an unreadable or
#             non-array status read exits 2, printing nothing either way; a
#             store with no candidate makes no status read
#   (FRESH)   until_fresh finds the edge to the successor gone, a target or a
#             blocker reopened or added, an edge `bd show` leaves out because
#             its target has no row in the store, live work on the row or the
#             edges, or nothing, and fails closed on a read that fails or does
#             not parse; it reads the pass's own claim as the bead the pass
#             claimed, and with `closed` reads a bead the pass just closed the
#             same way, so only what landed on it meanwhile reads live
#   (READERS) the until consumer and its doctor mirror source this file and
#             call both functions
#   (NO-COPY) no other file in the pack defines these names
# The behavioral half of each reader lives beside it (deferred-dispatch.test.sh,
# doctor/check-until-resolved-owed/run.test.sh).
# Reads the repo only; no gc, no city, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/until-resolved.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-until-resolved-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=until-resolved.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${UNTIL_RESOLVED_JQ:-}" ] && ok "(SCAN) sourcing the file exposes \$UNTIL_RESOLVED_JQ" \
    || bad "(SCAN) sourcing the file exposes \$UNTIL_RESOLVED_JQ"

# The reader the functions are handed, over fixture files: LISTING answers the
# store listing, STATUSES a status read by id, ROW_<id> a read by id of that one
# bead, SHOW_<id> a `bd show`, and UP_<id> a dependents read. A FAIL_* flag
# fails that read; READS gets one line per call.
fake_bd() {
    local want="" prev="" a
    printf '%s\n' "$*" >> "$TMP/reads"
    case "$1" in
        list)
            case " $* " in
                *" --id "*)
                    for a in "$@"; do [ "$prev" = "--id" ] && want="$a"; prev="$a"; done
                    if [ -f "$TMP/row_$want" ]; then
                        [ -z "${FAIL_ROW:-}" ] || return 1; cat "$TMP/row_$want"
                    else
                        [ -z "${FAIL_STATUS:-}" ] || return 1; cat "$TMP/statuses"
                    fi ;;
                *) [ -z "${FAIL_LIST:-}" ] || return 1; cat "$TMP/listing" ;;
            esac ;;
        show) [ -z "${FAIL_SHOW:-}" ] || return 1; cat "$TMP/show_$2" ;;
        dep)  [ -z "${FAIL_UP:-}" ] || return 1; cat "$TMP/up_$3" ;;
        *) return 2 ;;
    esac
}
listing()  { printf '%s' "$1" > "$TMP/listing"; : > "$TMP/reads"; }
statuses() { printf '%s' "$1" > "$TMP/statuses"; }
row_of()   { printf '%s\n' "$1" | awk -F'\t' -v id="$2" '$1 == id'; }
col()      { printf '%s\n' "$1" | cut -f"$2"; }

echo "# until_scan: what is a candidate"
listing '[
 {"id":"c-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"}]},
 {"id":"n-1","issue_type":"task","status":"blocked","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"}]},
 {"id":"n-2","issue_type":"task","status":"open","assignee":"rig/rig.polecat","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"}]},
 {"id":"n-3","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"blocks"}]},
 {"id":"x-1","issue_type":"task","status":"closed","assignee":"","metadata":{},"dependencies":[]}]'
statuses '[{"id":"x-1","status":"closed","closed_at":"2026-01-01T00:00:00Z"}]'
out="$(until_scan fake_bd)"; rc=$?
eq "$rc" "0" "(SCAN) a readable store exits 0"
eq "$(printf '%s\n' "$out" | cut -f1 | paste -sd, -)" "c-1" "(SCAN) only the open, unassigned bead with an until edge is a candidate"
eq "$(grep -c -- '--id' "$TMP/reads")" "1" "(SCAN) every referenced bead is read in one status read"
eq "$(grep -c -- '--id x-1 --all --include-gates --include-infra --include-templates' "$TMP/reads")" "1" "(SCAN) the status read asks for closed beads and every hidden class"

echo "# until_scan: a bead under the pass's own claim"
# A pass claims a bead before it disposes it. A bead it claimed and did not
# finish is in progress under UNTIL_FENCE, and reads as the open, unassigned bead
# it claimed. Any other claim is a live worker's.
listing '[
 {"id":"f-1","issue_type":"task","status":"in_progress","assignee":"deferred-dispatch","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"}]},
 {"id":"n-4","issue_type":"task","status":"in_progress","assignee":"rig/rig.polecat-1","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"}]},
 {"id":"n-5","issue_type":"task","status":"blocked","assignee":"deferred-dispatch","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"}]}]'
statuses '[{"id":"x-1","status":"closed","closed_at":"2026-01-01T00:00:00Z"}]'
out="$(until_scan fake_bd)"
eq "${UNTIL_FENCE:-}" "deferred-dispatch" "(SCAN) the claim's assignee is deferred-dispatch"
eq "$(printf '%s\n' "$out" | cut -f1 | paste -sd, -)" "f-1" "(SCAN) a bead in progress under the claim is a candidate, and one another worker holds, or under the claim at another status, is not"
eq "$(col "$(row_of "$out" f-1)" 2)" "owed" "(SCAN) …decided as the bead the pass claimed"
eq "$(col "$(row_of "$out" f-1)" 8)" "-" "(SCAN) …with no mark for the claim itself"

echo "# until_scan: the four states"
listing '[
 {"id":"w-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"},{"depends_on_id":"o-1","type":"until"}]},
 {"id":"r-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"ghost","type":"until"}]},
 {"id":"r-2","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"},{"depends_on_id":"far","type":"blocks"}]},
 {"id":"r-3","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"","type":"until"}]},
 {"id":"b-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"},{"depends_on_id":"o-1","type":"blocks"}]},
 {"id":"d-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"},{"depends_on_id":"x-2","type":"until"}]}]'
statuses '[
 {"id":"x-1","status":"closed","closed_at":"2026-01-01T00:00:00Z"},
 {"id":"x-2","status":"CLOSED","closed_at":"2026-02-01T00:00:00Z"},
 {"id":"o-1","status":"open","closed_at":null}]'
out="$(until_scan fake_bd)"
eq "$(col "$(row_of "$out" w-1)" 2)" "waiting" "(SCAN) an until target still open is waiting"
eq "$(col "$(row_of "$out" w-1)" 7)" "o-1" "(SCAN) …and names that target"
eq "$(col "$(row_of "$out" r-1)" 2)" "unresolved" "(SCAN) an until target the status read did not return is unresolved, never closed"
eq "$(col "$(row_of "$out" r-1)" 7)" "ghost" "(SCAN) …and names it"
eq "$(col "$(row_of "$out" r-2)" 2)" "unresolved" "(SCAN) so is a blocks blocker the status read did not return"
eq "$(col "$(row_of "$out" r-3)" 2)" "unresolved" "(SCAN) an until edge with a blank target is unresolved"
eq "$(col "$(row_of "$out" b-1)" 2)" "blocked" "(SCAN) every until target closed but a blocks blocker open is blocked"
eq "$(col "$(row_of "$out" b-1)" 7)" "o-1" "(SCAN) …and names the blocker"
eq "$(col "$(row_of "$out" d-1)" 2)" "owed" "(SCAN) every until target closed and no open blocker is owed"
eq "$(col "$(row_of "$out" d-1)" 3)" "x-2" "(SCAN) the successor is the until target that closed last"
eq "$(row_of "$out" d-1)" "$(printf 'd-1\towed\tx-2\t2026-02-01T00:00:00Z\tx-1,x-2\t-\t-\t-')" "(SCAN) an owed row: id, state, successor, owed-since, targets, blockers, detail, marks, with - for empty"

echo "# until_scan: when a bead became owed"
listing '[
 {"id":"e-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until","created_at":"2026-03-01T00:00:00Z"}]},
 {"id":"e-2","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until","created_at":"2025-12-01T00:00:00Z"},{"depends_on_id":"y-1","type":"blocks"}]}]'
statuses '[
 {"id":"x-1","status":"closed","closed_at":"2026-01-01T00:00:00Z"},
 {"id":"y-1","status":"closed","closed_at":"2026-04-01T00:00:00Z"}]'
out="$(until_scan fake_bd)"
eq "$(col "$(row_of "$out" e-1)" 4)" "2026-03-01T00:00:00Z" "(SCAN) an edge added after its target closed is owed from the edge's creation"
eq "$(col "$(row_of "$out" e-2)" 4)" "2026-04-01T00:00:00Z" "(SCAN) a blocker that closed last makes the bead owed from that close"

echo "# until_scan: live-work marks come from the row"
listing '[{"id":"l-1","issue_type":"task","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/rig.polecat"},"dependencies":[{"depends_on_id":"x-1","type":"until"}]}]'
statuses '[{"id":"x-1","status":"closed","closed_at":"2026-01-01T00:00:00Z"}]'
out="$(until_scan fake_bd)"
eq "$(col "$out" 2)" "owed" "(SCAN) live work does not change the state"
eq "$(col "$out" 8)" "gc.routed_to=rig/rig.polecat" "(SCAN) …and the marks column names it"

echo "# until_scan: an unread store is never an empty one"
listing '[{"id":"c-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"}]}]'
statuses '[{"id":"x-1","status":"closed","closed_at":"2026-01-01T00:00:00Z"}]'
out="$(FAIL_LIST=1 until_scan fake_bd)"; rc=$?
eq "$rc" "1" "(FAIL) a listing that fails exits 1"
eq "$out" "" "(FAIL) …printing nothing"
printf '%s' '{"error":"store unavailable"}' > "$TMP/listing"
out="$(until_scan fake_bd)"; rc=$?
eq "$rc" "1" "(FAIL) a listing that is not an array exits 1"
eq "$out" "" "(FAIL) …printing nothing"
listing '[{"id":"c-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"}]}]'
out="$(FAIL_STATUS=1 until_scan fake_bd)"; rc=$?
eq "$rc" "2" "(FAIL) a status read that fails exits 2"
eq "$out" "" "(FAIL) …printing nothing"
statuses '{"error":"store unavailable"}'
out="$(until_scan fake_bd)"; rc=$?
eq "$rc" "2" "(FAIL) a status read that is not an array exits 2"
eq "$out" "" "(FAIL) …printing nothing"
listing '[{"id":"n-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[]}]'
out="$(until_scan fake_bd)"; rc=$?
eq "$rc" "0" "(FAIL) a store with no candidate exits 0"
eq "$out" "" "(FAIL) …printing nothing"
eq "$(grep -c -- '--id' "$TMP/reads")" "0" "(FAIL) …and makes no status read"

echo "# until_fresh: the bead as the store holds it now"
# The bead's own row from `bd list` carries every edge the show row renders, in
# the list-edge shape, plus each edge given after <want>: an edge whose target
# has no row in the store, which real `bd show` leaves out.
fresh_case() { # name show-row up-array want [listed-only edge, as {depends_on_id, type}]...
    local name="$1" show="$2" up="$3" want="$4" extra; shift 4
    extra="$(printf '%s\n' "$@" | jq -sc .)"
    printf '%s' "[$show]" > "$TMP/show_g-1"
    printf '%s' "$up" > "$TMP/up_g-1"
    printf '%s' "[$show]" | jq -c --argjson extra "$extra" \
        '[ .[] | .dependencies = ([ (.dependencies // [])[] | {depends_on_id: .id, type: .dependency_type} ] + $extra) ]' > "$TMP/row_g-1"
    eq "$(until_fresh fake_bd g-1 x-1)" "$want" "(FRESH) $name"
}
CLEAN_UNTIL='{"id":"x-1","dependency_type":"until","issue_type":"task","status":"closed"}'
fresh_case "still owed and nothing live reads clear" \
    '{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'clear\t-')"
fresh_case "an until edge to the successor that is gone reads gone" \
    '{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[]}' '[]' "$(printf 'gone\t-')"
fresh_case "an edge to another closed target does not stand in for the successor's" \
    '{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"id":"x-9","dependency_type":"until","issue_type":"task","status":"closed"}]}' '[]' "$(printf 'gone\t-')"
fresh_case "an until target reopened or added reads waiting" \
    '{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":['"$CLEAN_UNTIL"',{"id":"x-2","dependency_type":"until","issue_type":"task","status":"open"}]}' '[]' "$(printf 'waiting\tx-2')"
fresh_case "a blocks blocker open now reads blocked" \
    '{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":['"$CLEAN_UNTIL"',{"id":"y-1","dependency_type":"blocks","issue_type":"task","status":"in_progress"}]}' '[]' "$(printf 'blocked\ty-1')"
fresh_case "a route stamped since the listing reads live" \
    '{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/rig.polecat"},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'live\tgc.routed_to=rig/rig.polecat')"
fresh_case "a convoy tracking the bead reads live" \
    '{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":['"$CLEAN_UNTIL"']}' '[{"id":"c-1","dependency_type":"tracks","issue_type":"convoy","status":"closed"}]' "$(printf 'live\ttracked by convoy c-1 (closed)')"
fresh_case "a claim since the listing reads live" \
    '{"id":"g-1","issue_type":"task","status":"in_progress","assignee":"rig__polecat-1","metadata":{},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'live\tstatus=in_progress; assignee=rig__polecat-1')"
fresh_case "the pass's own claim reads as the bead it claimed" \
    '{"id":"g-1","issue_type":"task","status":"in_progress","assignee":"deferred-dispatch","metadata":{},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'clear\t-')"
fresh_case "a route on a bead the pass holds reads live, naming the route alone" \
    '{"id":"g-1","issue_type":"task","status":"in_progress","assignee":"deferred-dispatch","metadata":{"gc.routed_to":"rig/rig.polecat"},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'live\tgc.routed_to=rig/rig.polecat')"
fresh_case "a bead closed under the claim, read before a close, reads live" \
    '{"id":"g-1","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'live\tstatus=closed; assignee=deferred-dispatch')"

echo "# until_fresh closed: the bead just after the pass closed it"
# The read after a close: a bead closed under the claim, or closed and unassigned
# once a pass has released the claim from it, reads as the bead the pass
# claimed. Anything that landed on it meanwhile reads as it would before.
closed_case() { # name show-row up-array want
    printf '%s' "[$2]" > "$TMP/show_g-1"
    printf '%s' "$3" > "$TMP/up_g-1"
    printf '%s' "[$2]" | jq -c '[ .[] | .dependencies = [ (.dependencies // [])[] | {depends_on_id: .id, type: .dependency_type} ] ]' > "$TMP/row_g-1"
    eq "$(until_fresh fake_bd g-1 x-1 closed)" "$4" "(FRESH) $1"
}
closed_case "a bead closed under the claim, with nothing new on it, reads clear" \
    '{"id":"g-1","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{"gc.superseded_by":"x-1"},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'clear\t-')"
closed_case "so does one closed and unassigned" \
    '{"id":"g-1","issue_type":"task","status":"closed","assignee":"","metadata":{"gc.superseded_by":"x-1"},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'clear\t-')"
closed_case "a route that landed on it reads live" \
    '{"id":"g-1","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{"gc.superseded_by":"x-1","gc.routed_to":"rig/rig.polecat"},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'live\tgc.routed_to=rig/rig.polecat')"
closed_case "a convoy that began tracking it reads live" \
    '{"id":"g-1","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{"gc.superseded_by":"x-1"},"dependencies":['"$CLEAN_UNTIL"']}' '[{"id":"c-1","dependency_type":"tracks","issue_type":"convoy","status":"open"}]' "$(printf 'live\ttracked by convoy c-1 (open)')"
closed_case "a bead closed under another assignee reads live" \
    '{"id":"g-1","issue_type":"task","status":"closed","assignee":"rig__polecat-1","metadata":{"gc.superseded_by":"x-1"},"dependencies":['"$CLEAN_UNTIL"']}' '[]' "$(printf 'live\tstatus=closed; assignee=rig__polecat-1')"
closed_case "a removed until edge reads gone" \
    '{"id":"g-1","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{"gc.superseded_by":"x-1"},"dependencies":[]}' '[]' "$(printf 'gone\t-')"

CLEAN_ROW='{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":['"$CLEAN_UNTIL"']}'
fresh_case "an until edge bd show leaves out, to a target with no row in this store, reads unresolved" \
    "$CLEAN_ROW" '[]' "$(printf 'unresolved\tfar-1')" '{"depends_on_id":"far-1","type":"until"}'
fresh_case "so does a blocks edge bd show leaves out" \
    "$CLEAN_ROW" '[]' "$(printf 'unresolved\tfar-2')" '{"depends_on_id":"far-2","type":"blocks"}'
fresh_case "so does a parent bd show leaves out, which could be a convoy" \
    "$CLEAN_ROW" '[]' "$(printf 'unresolved\tfar-3')" '{"depends_on_id":"far-3","type":"parent-child"}'
fresh_case "an edge of another type bd show leaves out decides nothing" \
    "$CLEAN_ROW" '[]' "$(printf 'clear\t-')" '{"depends_on_id":"far-4","type":"related"}'
fresh_case "every edge bd show leaves out is named" \
    "$CLEAN_ROW" '[]' "$(printf 'unresolved\tfar-1,far-2')" '{"depends_on_id":"far-2","type":"blocks"}' '{"depends_on_id":"far-1","type":"until"}'
fresh_case "an until target still open reads waiting ahead of an edge bd show leaves out" \
    '{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":['"$CLEAN_UNTIL"',{"id":"x-2","dependency_type":"until","issue_type":"task","status":"open"}]}' '[]' "$(printf 'waiting\tx-2')" '{"depends_on_id":"far-1","type":"until"}'
fresh_case "an edge to the successor that only the listed row carries reads unresolved, not gone" \
    '{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[]}' '[]' "$(printf 'unresolved\tx-1')" '{"depends_on_id":"x-1","type":"until"}'

printf '%s' '[{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":['"$CLEAN_UNTIL"']}]' > "$TMP/show_g-1"
printf '%s' '[]' > "$TMP/up_g-1"
out="$(FAIL_SHOW=1 until_fresh fake_bd g-1 x-1)"; rc=$?
eq "$rc:$out" "1:" "(FRESH) a show that fails exits 1 with nothing printed"
out="$(FAIL_UP=1 until_fresh fake_bd g-1 x-1)"; rc=$?
eq "$rc:$out" "1:" "(FRESH) a dependents read that fails exits 1 with nothing printed"
printf '%s' '{"error":"no issues found matching the provided IDs"}' > "$TMP/show_g-1"
out="$(until_fresh fake_bd g-1 x-1)"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && ok "(FRESH) a show that answers an error object fails closed" \
    || bad "(FRESH) a show that answers an error object fails closed (rc=$rc out='$out')"
printf '%s' '[{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":['"$CLEAN_UNTIL"']}]' > "$TMP/show_g-1"
printf '%s' '{"error":"simulated dependents failure"}' > "$TMP/up_g-1"
out="$(until_fresh fake_bd g-1 x-1)"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && ok "(FRESH) a dependents read that is not an array fails closed" \
    || bad "(FRESH) a dependents read that is not an array fails closed (rc=$rc out='$out')"
printf '%s' '[]' > "$TMP/up_g-1"
printf '%s' '[{"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"dependencies":[{"depends_on_id":"x-1","type":"until"}]}]' > "$TMP/row_g-1"
: > "$TMP/reads"
eq "$(until_fresh fake_bd g-1 x-1)" "$(printf 'clear\t-')" "(FRESH) the control: with every read answering, the bead reads clear"
eq "$(grep -c -- '^list --id g-1 --all --include-gates --include-infra --include-templates ' "$TMP/reads")" "1" "(FRESH) the bead's own row is read once by id, with the flags of the status read"
out="$(FAIL_ROW=1 until_fresh fake_bd g-1 x-1)"; rc=$?
eq "$rc:$out" "1:" "(FRESH) a read of the bead's own row that fails exits 1 with nothing printed"
printf '%s' '[]' > "$TMP/row_g-1"
out="$(until_fresh fake_bd g-1 x-1)"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && ok "(FRESH) a row read that returns no row for the bead fails closed" \
    || bad "(FRESH) a row read that returns no row for the bead fails closed (rc=$rc out='$out')"
printf '%s' '{"error":"simulated listing failure"}' > "$TMP/row_g-1"
out="$(until_fresh fake_bd g-1 x-1)"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && ok "(FRESH) a row read that is not an array fails closed" \
    || bad "(FRESH) a row read that is not an array fails closed (rc=$rc out='$out')"

echo "# every reader sources the one definition"
# Comment lines are left out, so a reader that names the file in prose but no
# longer calls it still fails.
READERS="assets/scripts/deferred-dispatch.sh
doctor/check-until-resolved-owed/run.sh"
for r in $READERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    grep -qE '^[[:space:]]*\.[[:space:]].*until-resolved\.sh' <<< "$code" \
        && ok "(READERS) $r sources until-resolved.sh" \
        || bad "(READERS) $r sources until-resolved.sh"
    grep -qE '(^|[^_[:alnum:]])until_scan[[:space:]]' <<< "$code" \
        && ok "(READERS) $r calls until_scan" \
        || bad "(READERS) $r calls until_scan"
    grep -qE '(^|[^_[:alnum:]])until_fresh[[:space:]]' <<< "$code" \
        && ok "(READERS) $r calls until_fresh" \
        || bad "(READERS) $r calls until_fresh"
done

echo "# no private copies"
# Specs and generated renders are history and output, not readers.
DEF_RE='def[[:space:]]+(until_unfenced|until_candidate|until_status_map|until_judge|until_row|until_fresh_verdict)|(^|[[:space:]])(until_scan|until_fresh)[[:space:]]*\(\)'
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/until-resolved.test.sh") continue ;; esac
        COPIES="$COPIES ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$DEF_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside until-resolved.sh defines its own until defs or functions"

echo
echo "until-resolved: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
