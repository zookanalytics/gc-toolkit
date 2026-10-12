#!/usr/bin/env bash
# Hermetic test for assets/scripts/placement.sh, the one definition of a bead
# that waits for placement. Covers:
#   (DEF)     sourcing the file exposes $PLACEMENT_JQ, and the marker value is
#             the one intake writes
#   (PRED)    awaiting_placement is true for a marked bead nothing has placed,
#             blocked or not, and false for a missing or other marker and for
#             each shape that places a bead: a parent in either form bd prints,
#             a route, an arm, an assignee, a live pour
#   (READERS) every reader of the queue sources this file and applies
#             $PLACEMENT_JQ, and asks awaiting_placement where it judges a bead
#   (NO-COPY) no other file in the pack defines the predicate or tests the
#             marker's value itself
# A reader with a private test drifts silently: the queue the operator reads and
# the census the liveness sweep files would disagree about which beads wait on
# the sitting. The behavioral half lives beside each reader
# (gc-helm-unplaced.test.sh, liveness-classify.test.sh,
# doctor/check-blocked-work-armed/run.test.sh).
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/placement.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=dispatch-path.sh
. "$HERE/dispatch-path.sh" || { echo "FAIL - cannot source dispatch-path.sh" >&2; exit 1; }
# shellcheck source=placement.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${PLACEMENT_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$PLACEMENT_JQ" \
    || bad "(DEF) sourcing the file exposes \$PLACEMENT_JQ"
eq "$(jq -nr "$DISPATCH_PATH_JQ$PLACEMENT_JQ"'placement_pending' 2>/dev/null)" "pending" \
   "(DEF) the marker value is the one intake writes (placement=pending)"

echo "# the predicate"
pred() { printf '%s' "$1" | jq -r "$DISPATCH_PATH_JQ$PLACEMENT_JQ"'awaiting_placement' 2>/dev/null; }
eq "$(pred '{"metadata":{"placement":"pending"}}')" "true" "(PRED) a marked bead nothing has placed waits for placement"
eq "$(pred '{"metadata":{"placement":"pending"},"dependencies":[{"depends_on_id":"tk-mig","type":"blocks"}]}')" \
   "true" "(PRED) …and still waits when it also waits on a blocker"
eq "$(pred '{"metadata":{"placement":"pending","gc.routed_to":"  "}}')" \
   "true" "(PRED) …and a blank route places nothing"
for case in '{}' '{"metadata":null}' '{"metadata":{}}' \
            '{"metadata":{"placement":"placed"}}' \
            '{"metadata":{"placement":"pending"},"parent":"tk-epic"}' \
            '{"metadata":{"placement":"pending"},"dependencies":[{"id":"tk-epic","dependency_type":"parent-child"}]}' \
            '{"metadata":{"placement":"pending"},"dependencies":[{"depends_on_id":"tk-epic","type":"parent-child"}]}' \
            '{"metadata":{"placement":"pending","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}' \
            '{"metadata":{"placement":"pending","gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"}}' \
            '{"metadata":{"placement":"pending"},"assignee":"gc-toolkit.mechanik"}' \
            '{"metadata":{"placement":"pending","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}}'; do
    eq "$(pred "$case")" "false" "(PRED) $case does not wait for placement"
done

echo "# every reader sources the one definition"
# Comment lines are left out, so a reader that names the definition in prose
# but no longer calls it still fails. The liveness classifier is applied by the
# sweep and its precheck, which compose its program with these defs, so the
# classifier asks the predicate and its composers source the file.
SOURCERS="assets/scripts/gc-helm.sh
doctor/check-blocked-work-armed/run.sh
assets/scripts/liveness-sweep.sh
assets/scripts/liveness-sweep-precheck.sh"
for r in $SOURCERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    grep -qE '^[[:space:]]*\.[[:space:]].*placement\.sh' <<< "$code" \
        && ok "(READERS) $r sources placement.sh" \
        || bad "(READERS) $r sources placement.sh"
    grep -q 'PLACEMENT_JQ' <<< "$code" \
        && ok "(READERS) $r applies \$PLACEMENT_JQ" \
        || bad "(READERS) $r applies \$PLACEMENT_JQ"
done
for r in assets/scripts/gc-helm.sh doctor/check-blocked-work-armed/run.sh assets/scripts/liveness-classify.sh; do
    code="$(grep -vE '^[[:space:]]*#' "$ROOT/$r" 2>/dev/null)"
    grep -q 'awaiting_placement' <<< "$code" \
        && ok "(READERS) $r asks awaiting_placement" \
        || bad "(READERS) $r asks awaiting_placement"
done

echo "# no private copies"
# A copy is a jq def of the predicate or a test of the marker's value: the key,
# an optional default, then `==` or `!=` against "pending", in either quoting a
# jq program takes in a shell string. Writing the marker is not a test of it.
# Specs and generated renders are history and output, not readers.
DEF_RE='def[[:space:]]+(awaiting_placement|placement_pending)'
VALUE_RE='placement\\?"?\]?\)?[[:space:]]*(//[[:space:]]*\\?"\\?"[[:space:]]*\)?)?[[:space:]]*[!=]=[[:space:]]*\\?"pending'
eq "$(printf '%s\n' '| select((.metadata.placement // "") == "pending")' | grep -cE "$VALUE_RE")" \
   "1" "(NO-COPY) the value test matches a jq select on the marker"
eq "$(printf '%s\n' '(if m(\"placement\") != \"pending\" then 1 else 0 end)' | grep -cE "$VALUE_RE")" \
   "1" "(NO-COPY) the value test matches an escaped test inside a double-quoted program"
eq "$(printf '%s\n' "--set-metadata placement=pending" | grep -cE "$VALUE_RE")" \
   "0" "(NO-COPY) writing the marker is not a test of it"
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/placement.test.sh") continue ;; esac
        COPIES="$COPIES ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$DEF_RE|$VALUE_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside placement.sh carries its own placement test"

echo
echo "placement: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
