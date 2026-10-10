#!/usr/bin/env bash
# Hermetic test for assets/scripts/dispatch-path.sh, the one definition of a
# dispatch path. Covers:
#   (DEF)     the key list is non-empty and unique, names the route and the arm,
#             and leaves out gc.execution_routed_to, which is provenance
#   (PRED)    has_dispatch_path is true for a bead carrying any listed key, and
#             false for a blank value, no metadata, provenance alone, an arm's
#             sibling keys alone, or a near-miss key
#   (READERS) every reader of the dispatch path sources this file, applies
#             $DISPATCH_PATH_JQ and asks has_dispatch_path
#   (NO-COPY) no other file in the pack defines the keys or the predicate, or
#             tests both keys for a value itself
# A reader with a private test drifts silently: it keeps the keys it copied and
# misses every key added later. The behavioral half lives beside each reader
# (tools/gc-proactive.test.sh, doctor/check-blocked-work-armed/run.test.sh,
# doctor/check-step-terminal/run.test.sh).
# Reads the repo only; no gc, no city, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/dispatch-path.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=dispatch-path.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${DISPATCH_PATH_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$DISPATCH_PATH_JQ" \
    || bad "(DEF) sourcing the file exposes \$DISPATCH_PATH_JQ"

echo "# the keys"
KEYS_JSON="$(jq -nc "$DISPATCH_PATH_JQ"'dispatch_path_keys' 2>/dev/null)"
eq "$(printf '%s' "$KEYS_JSON" | jq -r 'type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' 2>/dev/null)" \
   "true" "(DEF) dispatch_path_keys is a non-empty list of non-empty strings"
eq "$(printf '%s' "$KEYS_JSON" | jq -r 'length == (unique | length)' 2>/dev/null)" \
   "true" "(DEF) dispatch_path_keys names each key once"
for k in gc.routed_to gc.dispatch_when_ready; do
    eq "$(printf '%s' "$KEYS_JSON" | jq -r --arg k "$k" 'index($k) != null' 2>/dev/null)" \
       "true" "(DEF) dispatch_path_keys names $k"
done
eq "$(printf '%s' "$KEYS_JSON" | jq -r 'index("gc.execution_routed_to") == null' 2>/dev/null)" \
   "true" "(DEF) dispatch_path_keys leaves out gc.execution_routed_to (provenance, not a queue)"

echo "# the predicate"
pred() { printf '%s' "$1" | jq -r "$DISPATCH_PATH_JQ"'has_dispatch_path' 2>/dev/null; }
for k in $(printf '%s' "$KEYS_JSON" | jq -r '.[]'); do
    eq "$(pred "$(jq -nc --arg k "$k" '{metadata: {($k): "gc-toolkit/gc-toolkit.polecat"}}')")" \
       "true" "(PRED) a bead carrying $k has a dispatch path"
    for blank in empty space tab; do
        case "$blank" in empty) v='' ;; space) v=' ' ;; tab) v=$'\t' ;; esac
        eq "$(pred "$(jq -nc --arg k "$k" --arg v "$v" '{metadata: {($k): $v}}')")" \
           "false" "(PRED) a bead whose $k is blank ($blank) has no dispatch path"
    done
done
eq "$(pred '{"metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat","gc.dispatch_when_ready_fail_count":3}}')" \
   "true" "(PRED) an arm capped at its failure cap is still a dispatch path"
for case in '{}' '{"metadata":null}' '{"metadata":{}}' \
            '{"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}}' \
            '{"metadata":{"gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_slung":"slung@2026-01-01T00:00:00Z"}}' \
            '{"metadata":{"gc.routed_to_hint":"gc-toolkit/gc-toolkit.polecat"}}'; do
    eq "$(pred "$case")" "false" "(PRED) $case has no dispatch path"
done

echo "# every reader sources the one definition"
# Comment lines are left out, so a reader that names the definition in prose
# but no longer calls it still fails.
READERS="tools/gc-proactive.sh
doctor/check-blocked-work-armed/run.sh
doctor/check-step-terminal/run.sh"
for r in $READERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    grep -qE '^[[:space:]]*\.[[:space:]].*dispatch-path\.sh' <<< "$code" \
        && ok "(READERS) $r sources dispatch-path.sh" \
        || bad "(READERS) $r sources dispatch-path.sh"
    grep -q 'DISPATCH_PATH_JQ' <<< "$code" \
        && ok "(READERS) $r applies \$DISPATCH_PATH_JQ" \
        || bad "(READERS) $r applies \$DISPATCH_PATH_JQ"
    grep -q 'has_dispatch_path' <<< "$code" \
        && ok "(READERS) $r asks has_dispatch_path" \
        || bad "(READERS) $r asks has_dispatch_path"
done

echo "# no private copies"
# A copy is a jq def of the keys or the predicate, or one file that tests both
# keys for a value: the key, an optional `// ""` default, then `== ""` or
# `!= ""`, in either quoting a jq program takes in a shell string. A file that
# tests only the route (a pool's own queue) or only the arm (the arm's owner)
# asks a different question. Specs and generated renders are history and output,
# not readers.
value_test_re() { printf '%s' "$1"'\\?"\]?\)?[[:space:]]*(//[[:space:]]*\\?"\\?"[[:space:]]*\)?)?[[:space:]]*[!=]=[[:space:]]*\\?"\\?"'; }
DEF_RE='def[[:space:]]+(dispatch_path_keys|has_dispatch_path)'
ROUTE_RE="$(value_test_re 'gc\.routed_to')"
ARM_RE="$(value_test_re 'gc\.dispatch_when_ready')"
eq "$(printf '%s\n' '| select(($m["gc.dispatch_when_ready"] // "") == "")' | grep -cE "$ARM_RE")" \
   "1" "(NO-COPY) the value test matches a jq select on the arm"
eq "$(printf '%s\n' '(if m(\"gc.routed_to\") != \"\" then \"1\" else \"0\" end)' | grep -cE "$ROUTE_RE")" \
   "1" "(NO-COPY) the value test matches an escaped test inside a double-quoted program"
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/dispatch-path.test.sh") continue ;; esac
        if grep -qE "$DEF_RE" "$f" || { grep -qE "$ROUTE_RE" "$f" && grep -qE "$ARM_RE" "$f"; }; then
            COPIES="$COPIES ${f#"$ROOT"/}"
        fi
    done <<< "$(grep -rlE "$DEF_RE|$ARM_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside dispatch-path.sh carries its own dispatch-path test"

echo
echo "dispatch-path: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
