#!/usr/bin/env bash
# Hermetic test for the check-set-normalize block in
# formulas/mol-refinery-patrol.toml (merge-push step, "Normalize the
# check-set").
#
# The block resolves the check_set that the merge-push transition stamps on
# every anchor this formula gates, so a silent break there mis-gates PRs. It
# holds three behaviors, and the first two must stay distinct:
#   - an empty or whitespace/comma-only value (which the --root-only pour path
#     can mis-substitute) resolves to the declared default correctness,triage,
#     so a never-set check_set is never read as gateless;
#   - the none/off sentinel, in any case or spacing, resolves to the canonical
#     token none, so gateless-by-choice never collapses into never-set;
#   - a declared set passes through unchanged.
#
# It EXECUTES the real snippet extracted verbatim from the formula (between the
# check-set-normalize markers) against each input, so the test cannot drift
# from the shipped instruction. No live city, Dolt, network, or PRs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-set-normalize-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }

[ -s "$TOML" ] || { echo "missing $TOML"; exit 1; }

# --- Extract the real snippet from the formula. -------------------------------
# The $-anchored markers keep the name check-set-normalize from matching a
# longer marker. Missing or renamed markers => empty block => the guard below
# fails loudly.
awk '
  $0 ~ /# >>> check-set-normalize$/ {f=1; next}
  $0 ~ /# <<< check-set-normalize$/ {f=0}
  f' "$TOML" > "$TMP/block.sh"

[ -s "$TMP/block.sh" ] \
  && ok "snippet extracted between check-set-normalize markers" \
  || bad "snippet extraction EMPTY — markers missing from $TOML"

# The block lives inside a TOML `"""` string, so a trailing backslash would be
# eaten before any agent saw it (the header's backslash-free rule). The test
# runs the RAW file text, so a backslash here means what runs differs from what
# this test pins.
grep -q '[\]' "$TMP/block.sh" \
  && bad "block carries a backslash (TOML would eat it)" \
  || ok "block is backslash-free"
bash -n "$TMP/block.sh" && ok "block is valid bash" || bad "block is valid bash" "bash -n failed"

# The block reads $CHECK_SET from scope and rewrites it (the formula sets it
# from {{check_set}} on the line just above the markers). Wrap it so each run
# echoes the resulting value, and feed the input through the environment.
{ cat "$TMP/block.sh"; printf 'printf "%%s" "$CHECK_SET"\n'; } > "$TMP/run.sh"
norm() { CHECK_SET="$1" bash "$TMP/run.sh"; }

echo "── empty / mis-substituted -> the declared default ──"
eq "$(norm '')"       "correctness,triage" "(1) empty resolves to correctness,triage"
eq "$(norm '   ')"    "correctness,triage" "(2) whitespace-only canonicalizes to empty -> default"
eq "$(norm ' , ')"    "correctness,triage" "(3) commas and spaces only -> default"

echo "── none/off sentinel -> the canonical token 'none' ──"
eq "$(norm 'none')"   "none" "(4) none -> none"
eq "$(norm 'off')"    "none" "(5) off -> none"
eq "$(norm 'NONE')"   "none" "(6) NONE (upper case) -> none (canonicalized before the match)"
eq "$(norm '  Off ')" "none" "(7) ' Off ' (mixed case + surrounding space) -> none"

echo "── a declared set passes through unchanged ──"
eq "$(norm 'correctness,triage')"     "correctness,triage"     "(8) a declared set is returned byte-identical"
eq "$(norm 'correctness')"            "correctness"            "(9) a single declared check passes through"
eq "$(norm 'correctness,triage,arch')" "correctness,triage,arch" "(10) a longer declared set passes through"
# Canonicalization serves only the sentinel match; it must not rewrite the
# value that passes through.
eq "$(norm 'Correctness, Triage')" "Correctness, Triage" "(11) passthrough keeps the raw value (case and spacing untouched)"
# The sentinel match is on the whole canonicalized value, not a substring: a
# real check whose name merely begins with 'none' is not the sentinel.
eq "$(norm 'nonexistent')" "nonexistent" "(12) 'nonexistent' is a declared check, not the none sentinel"

echo "── the two defaulting arms stay distinct (the gating invariant) ──"
# never-set (-> correctness,triage) and gateless-by-choice (-> none) must not
# collapse into each other; keeping them apart is the whole point of the block.
[ "$(norm '')" != "none" ] \
  && ok "(13) empty never becomes the 'none' sentinel" \
  || bad "(13) empty collapsed to 'none' — gateless-by-choice no longer distinct from never-set"
{ [ "$(norm 'none')" != "correctness,triage" ] && [ -n "$(norm 'none')" ]; } \
  && ok "(14) 'none' never becomes the default or empty" \
  || bad "(14) 'none' collapsed to the default or empty — gateless-by-choice lost"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
