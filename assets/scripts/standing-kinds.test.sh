#!/usr/bin/env bash
# Hermetic test for the one definition of the standing kinds,
# services/gctk/standing/kinds.json, and for assets/scripts/standing-kinds.sh,
# which reads it into jq defs for the shell readers. Covers:
#   (DEF)     the definition names each kind once, with text saying what its
#             record is, and names both kinds the pack writes as standing
#             records today; standing_kinds is exactly its kinds
#   (PRED)    is_standing_kind is true for every listed kind and false for an
#             empty, absent, near-miss or ordinary task_kind
#   (LOAD)    sourcing fails, and defines nothing, when the definition is
#             missing or does not read as kinds that each say what their record
#             is
#   (READERS) every shell reader sources standing-kinds.sh and applies
#             $STANDING_KINDS_JQ, and every Go reader takes the definition
#             through gctk's standing package
#   (NO-COPY) no file in the pack but the definition carries a list of its own
# A reader with a private list drifts silently: it keeps excluding the kinds it
# copied and misses every kind added later. The behavioral half lives beside
# each reader (tools/gc-proactive.test.sh, liveness-recheck.test.sh,
# liveness-sweep-precheck.test.sh, doctor/check-blocked-work-armed/run.test.sh,
# and the Go tests of services/gctk/standing, services/gctk/listing and
# services/helm/internal/rigboard), each driven by the definition.
# Reads the repo and writes only its own temporary directory; no gc, no city,
# no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/standing-kinds.sh"
DEFINITION="$ROOT/services/gctk/standing/kinds.json"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/standing-kinds-test.XXXXXX")" || { echo "cannot make a temporary directory" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# shellcheck source=standing-kinds.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${STANDING_KINDS_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$STANDING_KINDS_JQ" \
    || bad "(DEF) sourcing the file exposes \$STANDING_KINDS_JQ"

echo "# the definition"
eq "$(jq -r 'type == "object" and length > 0
             and all(keys_unsorted[]; length > 0)
             and all(.[]; type == "string" and test("\\S"))' "$DEFINITION" 2>/dev/null)" \
   "true" "(DEF) kinds.json names its kinds, each saying what its record is"
eq "$(jq -r 'keys_unsorted | length == (unique | length)' "$DEFINITION" 2>/dev/null)" \
   "true" "(DEF) kinds.json names each kind once"
KINDS_JSON="$(jq -nc "$STANDING_KINDS_JQ"'standing_kinds' 2>/dev/null)"
eq "$KINDS_JSON" "$(jq -c 'keys_unsorted' "$DEFINITION" 2>/dev/null)" \
   "(DEF) standing_kinds is exactly the kinds kinds.json names"
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
            '{"metadata":{"task_kind":"review"}}'; do
    eq "$(printf '%s' "$case" | jq -r "$STANDING_KINDS_JQ"'is_standing_kind')" \
       "false" "(PRED) $case is not a standing record"
done

echo "# sourcing refuses what is no definition"
# A pack tree of two files: the library, and the definition at its place
# beside it, holding what each case writes. sources prints what sourcing the
# library there left defined, then its exit status.
mkdir -p "$T/pack/assets/scripts" "$T/pack/services/gctk/standing"
cp "$LIB" "$T/pack/assets/scripts/standing-kinds.sh"
sources() {
    bash -c '. "$1" 2>/dev/null; rc=$?; printf "%s:%s" "${STANDING_KINDS_JQ:+defined}" "$rc"' _ \
        "$T/pack/assets/scripts/standing-kinds.sh"
}
cp "$DEFINITION" "$T/pack/services/gctk/standing/kinds.json"
eq "$(sources)" "defined:0" "(LOAD) the definition copied beside the library sources"
rm -f "$T/pack/services/gctk/standing/kinds.json"
eq "$(sources)" ":1" "(LOAD) a missing definition fails the source and defines nothing"
for case in 'not json:{' 'an array:["triage-subject"]' 'null:null' 'no kind:{}' \
            'an empty kind:{"": "a record"}' 'a blank record:{"a": "  "}' \
            'a record that is not text:{"a": 1}'; do
    printf '%s' "${case#*:}" > "$T/pack/services/gctk/standing/kinds.json"
    eq "$(sources)" ":1" "(LOAD) a definition holding ${case%%:*} fails the source and defines nothing"
done
eq "$(bash -c '. "$1" 2>&1 >/dev/null' _ "$T/pack/assets/scripts/standing-kinds.sh" | grep -c 'services/gctk/standing/kinds.json does not read as the standing kinds')" \
   "1" "(LOAD) the refusal names the definition"

echo "# every reader reads the one definition"
SHELL_READERS="tools/gc-proactive.sh
assets/scripts/liveness-sweep.sh
assets/scripts/liveness-sweep-precheck.sh
assets/scripts/liveness-recheck.sh
doctor/check-blocked-work-armed/run.sh
doctor/check-hq-marooned-work/run.sh"
for r in $SHELL_READERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    grep -qE '^[[:space:]]*\.[[:space:]].*standing-kinds\.sh' "$f" \
        && ok "(READERS) $r sources standing-kinds.sh" \
        || bad "(READERS) $r sources standing-kinds.sh"
    grep -q 'STANDING_KINDS_JQ' "$f" \
        && ok "(READERS) $r applies \$STANDING_KINDS_JQ" \
        || bad "(READERS) $r applies \$STANDING_KINDS_JQ"
done
# The Go readers: the package compiles the definition in, the listing names a
# standing record on each bead it reads by asking the package, and the rig
# board's read leaves a bead the listing names so out of its rows.
GO_READERS="services/gctk/standing/standing.go|^//go:embed kinds\.json$|embeds kinds.json
services/gctk/listing/listing.go|standing\.Is\(|names a standing record through standing.Is
services/helm/internal/rigboard/build.go|!b\.Standing|leaves a standing record out of its rows"
while IFS='|' read -r r pattern says; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    grep -qE "$pattern" "$f" && ok "(READERS) $r $says" || bad "(READERS) $r $says"
done <<< "$GO_READERS"

echo "# no private copies"
# A copy is a jq def of the list, both kinds named side by side in one list
# literal, or a kind as the key of an object, the definition's own shape.
# standing-kinds.sh defines standing_kinds from the definition and names no
# kind itself. Specs and generated renders are history and output, not readers.
COPY_RE='def standing_kinds|"triage-subject"[[:space:]]*,[[:space:]]*"feedback-pattern"|"feedback-pattern"[[:space:]]*,[[:space:]]*"triage-subject"|"(triage-subject|feedback-pattern)"[[:space:]]*:'
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$DEFINITION"|"$LIB"|"$HERE/standing-kinds.test.sh") continue ;; esac
        COPIES="$COPIES ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$COPY_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file but the definition carries its own standing-kinds list"
NAMED=""
for k in $(printf '%s' "$KINDS_JSON" | jq -r '.[]'); do
    grep -qF "$k" "$LIB" && NAMED="$NAMED $k"
done
eq "${NAMED# }" "" "(NO-COPY) standing-kinds.sh names no kind of its own"

echo
echo "standing-kinds: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
