#!/usr/bin/env bash
# visit-identity.test.sh — the shared visit-coverage predicate (visit-identity.sh).
#
# Coverage is the visit's outgoing `tracks` edge; the gc.continuation_group
# stamp is a recovery fallback consulted ONLY when the edge set is empty. The
# regression this pins: a visit that tracks one subject by edge while carrying a
# stamp naming a DIFFERENT subject covers the edge target alone. A stale stamp
# beside a live edge must not add a second covered subject, or the open/dismiss/
# fold/sweep callers treat one visit as standing for two beads.
#
# The tracks edge renders two ways by read verb — `gc bd show` gives
# {dependency_type,id}, `gc bd list` gives {type,depends_on_id} — so both
# spellings are exercised.
#
# Hermetic: sources the predicate and runs jq against literal fixtures. No
# gc/bd, no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/visit-identity.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
# is <label> <got> <want>
is() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }

[ -r "$LIB" ] || { echo "visit-identity.test: cannot read $LIB" >&2; exit 1; }
# shellcheck source=visit-identity.sh
. "$LIB" || { echo "visit-identity.test: cannot source $LIB" >&2; exit 1; }
[ -n "${VISIT_IDENTITY_JQ:-}" ] || { echo "visit-identity.test: sourcing set no VISIT_IDENTITY_JQ" >&2; exit 1; }

# One def, run against a fixture.
match()    { printf '%s' "$1" | jq -r --arg s "$2" "$VISIT_IDENTITY_JQ"'visit_identity_match($s)'; }
covers()   { printf '%s' "$1" | jq -r --arg s "$2" "$VISIT_IDENTITY_JQ"'visit_covers($s)'; }
subject()  { printf '%s' "$1" | jq -r "$VISIT_IDENTITY_JQ"'visit_subject'; }
subjects() { printf '%s' "$1" | jq -c "$VISIT_IDENTITY_JQ"'visit_identity_subjects'; }

# Fixture builders. A visit bead object carrying a continuation_group stamp and
# a dependency array; edges come in the two shapes the read verbs emit.
show_edge() { jq -nc --arg s "$1" '{dependency_type:"tracks", id:$s}'; }
list_edge() { jq -nc --arg s "$1" '{type:"tracks", depends_on_id:$s}'; }
# visit <stamp> <deps-json-array>
visit() { jq -nc --arg g "$1" --argjson deps "$2" \
  '{metadata:{"task_kind":"visit","gc.continuation_group":$g}, dependencies:$deps}'; }

# --- Conflicting edge (show shape) vs stamp: the edge wins, alone ---------------
V="$(visit tk-stampB "[$(show_edge tk-edgeA)]")"
is "conflict: match(edge target) is tracks"           "$(match "$V" tk-edgeA)"  "tracks"
is "conflict: stamp subject is NOT covered"           "$(match "$V" tk-stampB)" ""
is "conflict: covers(edge target) true"               "$(covers "$V" tk-edgeA)" "true"
is "conflict: covers(stamp subject) false"            "$(covers "$V" tk-stampB)" "false"
is "conflict: subject is the edge target"             "$(subject "$V")"          "tk-edgeA"
is "conflict: subjects is [edge] only, stamp dropped" "$(subjects "$V")"         '["tk-edgeA"]'

# --- Same conflict, list shape: both edge spellings read identically ------------
V="$(visit tk-stampB "[$(list_edge tk-edgeA)]")"
is "conflict (list shape): match(edge) tracks"        "$(match "$V" tk-edgeA)"  "tracks"
is "conflict (list shape): stamp not covered"         "$(match "$V" tk-stampB)" ""
is "conflict (list shape): subjects [edge] only"      "$(subjects "$V")"        '["tk-edgeA"]'

# --- Fallback: no edge, stamp is the identity -----------------------------------
V="$(visit tk-stampB '[]')"
is "fallback: match(stamp) is continuation_group"     "$(match "$V" tk-stampB)" "continuation_group"
is "fallback: covers(stamp) true"                     "$(covers "$V" tk-stampB)" "true"
is "fallback: subject is the stamp"                   "$(subject "$V")"          "tk-stampB"
is "fallback: subjects is [stamp]"                    "$(subjects "$V")"         '["tk-stampB"]'

# --- Edge only, empty stamp -----------------------------------------------------
V="$(visit '' "[$(show_edge tk-edgeA)]")"
is "edge-only: match(edge) tracks"                    "$(match "$V" tk-edgeA)"  "tracks"
is "edge-only: subject is edge"                       "$(subject "$V")"          "tk-edgeA"
is "edge-only: subjects [edge]"                       "$(subjects "$V")"         '["tk-edgeA"]'

# --- Multiple edges + stamp: every edge covered, stamp still excluded -----------
V="$(visit tk-stampB "[$(show_edge tk-edgeA),$(show_edge tk-edgeC)]")"
is "multi-edge: subjects are the edges, stamp dropped" "$(subjects "$V")"        '["tk-edgeA","tk-edgeC"]'
is "multi-edge: second edge covered as tracks"         "$(match "$V" tk-edgeC)"  "tracks"
is "multi-edge: stamp subject not covered"             "$(match "$V" tk-stampB)" ""

# --- Empty visit: nothing is covered, no crash ----------------------------------
V="$(visit '' '[]')"
is "empty: match(empty subject) is ''"                "$(match "$V" '')"        ""
is "empty: match(some subject) is ''"                 "$(match "$V" tk-x)"      ""
is "empty: subject is ''"                             "$(subject "$V")"         ""
is "empty: subjects is []"                            "$(subjects "$V")"        '[]'

# --- Invariant: the single subject a visit resolves to is one it covers ---------
# visit_subject and the match/subject-set helpers must agree, so a stale stamp
# cannot desync them. Checked on the conflict fixture, where the old union broke it.
V="$(visit tk-stampB "[$(show_edge tk-edgeA)]")"
S="$(subject "$V")"
is "invariant: match(visit_subject) is non-empty"     "$(match "$V" "$S")"      "tracks"
is "invariant: visit_subject is in visit_identity_subjects" \
  "$(printf '%s' "$V" | jq -r --arg s "$S" "$VISIT_IDENTITY_JQ"'(visit_identity_subjects | index($s)) != null')" \
  "true"

echo
echo "visit-identity: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
