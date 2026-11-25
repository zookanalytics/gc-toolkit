#!/usr/bin/env bash
# Hermetic test for assets/scripts/dispatch-path.sh, the one definition of a
# dispatch path and of a dispatch hold. Covers:
#   (DEF)     the key list is non-empty and unique, names the route and the arm,
#             and leaves out gc.execution_routed_to, which is provenance; the
#             placement hold's values are po and mayor, lower case
#   (PRED)    has_dispatch_path is true for a bead carrying any listed key, and
#             false for a blank value, no metadata, provenance alone, an arm's
#             sibling keys alone, or a near-miss key
#   (HOLD)    has_dispatch_hold is true for any hold:<value> label, trimmed
#             and in any case, and false for hold:cleared, a hold: with no
#             value, no labels, another label, a label that only contains the
#             word, a label that is not in a list, or the retired marker
#   (SPELLING) placement_hold_spellings names each label that reads as hold:po
#             or hold:mayor, verbatim, and no other hold
#   (READERS) every reader of the dispatch path sources this file, applies
#             $DISPATCH_PATH_JQ and asks has_dispatch_path, and every reader of
#             the hold sources it and asks has_dispatch_hold
#   (NO-COPY) no other file in the pack defines the keys, the values or a
#             predicate, tests both keys for a value itself, tests a label
#             against both placement labels itself, or tests a label for the
#             hold: prefix in jq itself
# A reader with a private test drifts silently: it keeps the keys or labels it
# copied and misses every one added later. The behavioral half lives beside
# each reader (doctor/check-blocked-work-armed/run.test.sh,
# doctor/check-step-terminal/run.test.sh,
# doctor/check-armed-dispatch-owed/run.test.sh,
# doctor/check-po-queue-only/run.test.sh, liveness-classify.test.sh,
# liveness-recheck.test.sh).
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

echo "# the placement hold's values"
eq "$(jq -nc "$DISPATCH_PATH_JQ"'placement_hold_values' 2>/dev/null)" '["po","mayor"]' \
   "(DEF) placement_hold_values names hold:po and its earlier spelling, lower case"

echo "# the hold predicate"
held() { printf '%s' "$1" | jq -r "$DISPATCH_PATH_JQ"'has_dispatch_hold' 2>/dev/null; }
for l in hold:po hold:mayor hold:external hold:release-train HOLD:MAYOR Hold:PO ' hold:po' \
         $'hold:external\t' 'hold: po' 'hold:mayorx'; do
    eq "$(held "$(jq -nc --arg l "$l" '{labels: ["learning", $l]}')")" \
       "true" "(HOLD) a bead labelled '$l' is held"
done
eq "$(held '{"labels":["hold:cleared","hold:po"]}')" "true" "(HOLD) hold:cleared beside a hold releases nothing"
for case in '{}' '{"labels":null}' '{"labels":[]}' '{"labels":["learning","human"]}' \
            '{"labels":["hold:cleared"]}' '{"labels":["Hold: Cleared "]}' '{"labels":["hold:"]}' \
            '{"labels":["hold: "]}' '{"labels":["hold"]}' '{"labels":["on-hold","mpr-human-hold"]}' \
            '{"labels":"hold:po"}' '{"metadata":{"placement":"pending"}}' \
            '{"metadata":{"hold":"po"}}'; do
    eq "$(held "$case")" "false" "(HOLD) $case is not held"
done

spellings() { printf '%s' "$1" | jq -c "$DISPATCH_PATH_JQ"'placement_hold_spellings' 2>/dev/null; }
eq "$(spellings '{"labels":["learning","hold:po"]}')" '["hold:po"]' \
   "(SPELLING) a lift removes hold:po as the bead spells it"
eq "$(spellings '{"labels":["Hold:Mayor"," hold:po","hold:external","hold:mayor","hold:release-train"]}')" '["Hold:Mayor"," hold:po","hold:mayor"]' \
   "(SPELLING) every spelling of hold:po or hold:mayor is named, verbatim, and no other hold"
for case in '{}' '{"labels":null}' '{"labels":["hold:external","hold:cleared"]}' \
            '{"labels":["hold:pos","hold:mayorx","hold"]}' '{"labels":"hold:po"}'; do
    eq "$(spellings "$case")" '[]' "(SPELLING) $case spells no placement hold"
done

echo "# every reader sources the one definition"
# Comment lines are left out, so a reader that names the definition in prose
# but no longer calls it still fails. The liveness classifier is applied by the
# sweep and its precheck, which compose its program with these defs, so the
# classifier asks the hold predicate and its composers source the file.
sources() { # <reader> — it exists, sources this file and applies $DISPATCH_PATH_JQ
    local f="$ROOT/$1" code
    if [ ! -f "$f" ]; then bad "(READERS) $1 exists"; return; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    grep -qE '^[[:space:]]*\.[[:space:]].*dispatch-path\.sh' <<< "$code" \
        && ok "(READERS) $1 sources dispatch-path.sh" \
        || bad "(READERS) $1 sources dispatch-path.sh"
    grep -q 'DISPATCH_PATH_JQ' <<< "$code" \
        && ok "(READERS) $1 applies \$DISPATCH_PATH_JQ" \
        || bad "(READERS) $1 applies \$DISPATCH_PATH_JQ"
}
asks() { # <reader> <predicate>
    local code
    code="$(grep -vE '^[[:space:]]*#' "$ROOT/$1" 2>/dev/null)"
    grep -q "$2" <<< "$code" \
        && ok "(READERS) $1 asks $2" \
        || bad "(READERS) $1 asks $2"
}
for r in doctor/check-blocked-work-armed/run.sh doctor/check-step-terminal/run.sh; do
    sources "$r"; asks "$r" has_dispatch_path
done
for r in assets/scripts/liveness-sweep.sh assets/scripts/liveness-sweep-precheck.sh \
         assets/scripts/liveness-recheck.sh doctor/check-po-queue-only/run.sh; do
    sources "$r"
done
for r in doctor/check-blocked-work-armed/run.sh assets/scripts/liveness-classify.sh \
         assets/scripts/liveness-recheck.sh doctor/check-po-queue-only/run.sh; do
    asks "$r" has_dispatch_hold
done
asks doctor/check-po-queue-only/run.sh placement_hold_spellings
asks assets/scripts/converse-signoff.sh placement_hold_spellings

echo "# no private copies"
# A copy is a jq def of the keys or the predicate, or one file that tests both
# keys for a value: the key, an optional `// ""` default, then `== ""` or
# `!= ""`, in either quoting a jq program takes in a shell string. A file that
# tests only the route (a pool's own queue) or only the arm (the arm's owner)
# asks a different question. Specs and generated renders are history and output,
# not readers.
value_test_re() { printf '%s' "$1"'\\?"\]?\)?[[:space:]]*(//[[:space:]]*\\?"\\?"[[:space:]]*\)?)?[[:space:]]*[!=]=[[:space:]]*\\?"\\?"'; }
DEF_RE='def[[:space:]]+(dispatch_path_keys|has_dispatch_path|dispatch_hold_value|has_dispatch_hold|placement_hold_values|placement_hold_spellings)'
ROUTE_RE="$(value_test_re 'gc\.routed_to')"
ARM_RE="$(value_test_re 'gc\.dispatch_when_ready')"
eq "$(printf '%s\n' '| select(($m["gc.dispatch_when_ready"] // "") == "")' | grep -cE "$ARM_RE")" \
   "1" "(NO-COPY) the value test matches a jq select on the arm"
eq "$(printf '%s\n' '(if m(\"gc.routed_to\") != \"\" then \"1\" else \"0\" end)' | grep -cE "$ROUTE_RE")" \
   "1" "(NO-COPY) the value test matches an escaped test inside a double-quoted program"
# A label test compares a value with a hold label: `==` or `!=`, or index,
# contains or inside, then the label, in either quoting. A file that tests only
# one placement label asks a different question, such as whether its own write
# of the label landed, so a copy of the placement test is a file that tests
# both, and a copy of the hold test is a jq startswith of the hold: prefix.
label_test_re() { printf '%s' '([!=]=|index\(|contains\(|inside\()[[:space:]]*\[?[[:space:]]*\\?"'"$1"'\\?"'; }
MAYOR_RE="$(label_test_re 'hold:mayor')"
PO_RE="$(label_test_re 'hold:po')"
PREFIX_RE='startswith\([[:space:]]*\\?"hold:\\?"'
eq "$(printf '%s\n' '| select(any(.labels[]?; ascii_downcase == "hold:mayor"))' | grep -cE "$MAYOR_RE")" \
   "1" "(NO-COPY) the label test matches a jq comparison with a hold label"
eq "$(printf '%s\n' '(.labels | index(\"hold:po\"))' | grep -cE "$PO_RE")" \
   "1" "(NO-COPY) the label test matches an escaped index inside a double-quoted program"
eq "$(printf '%s\n' 'gc bd create "$TITLE" -t bug --labels hold:po --json' | grep -cE "$PO_RE")" \
   "0" "(NO-COPY) writing the label is not a test of it"
eq "$(printf '%s\n' '| select(.labels[]? | ascii_downcase | startswith("hold:"))' | grep -cE "$PREFIX_RE")" \
   "1" "(NO-COPY) the prefix test matches a jq startswith of hold:"
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/dispatch-path.test.sh") continue ;; esac
        if grep -qE "$DEF_RE|$PREFIX_RE" "$f" || { grep -qE "$ROUTE_RE" "$f" && grep -qE "$ARM_RE" "$f"; } \
            || { grep -qE "$MAYOR_RE" "$f" && grep -qE "$PO_RE" "$f"; }; then
            COPIES="$COPIES ${f#"$ROOT"/}"
        fi
    done <<< "$(grep -rlE "$DEF_RE|$ARM_RE|$PO_RE|$PREFIX_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside dispatch-path.sh carries its own dispatch-path or hold test"

echo
echo "dispatch-path: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
