#!/usr/bin/env bash
# Runs the REAL check_set resolution blocks extracted verbatim from
# formulas/mol-refinery-patrol.toml's merge-push step and proves that an anchor
# armed with an `approval` lane keeps it through the resolution, so a
# design-convoy checkpoint's gate 1 survives to merge.sh instead of being
# overwritten by the refinery's bare var default.
#
# The step sets CHECK_SET from its {{check_set}} var, then runs
# `check-set-normalize` and `check-set-prefer-approval-arm`. This test simulates
# the post-substitution var value directly and feeds a fixture BEAD_JSON (the
# anchor $WORK's metadata), then asserts the resolved CHECK_SET.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
[ -f "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-approval-arm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }

fence() { awk -v m="$1" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$TOML"; }

# The blocks must survive TOML (no backslashes, which the string would eat) and
# be valid bash.
for b in check-set-normalize check-set-prefer-approval-arm; do
  fence "$b" > "$TMP/$b.sh"
  [ -s "$TMP/$b.sh" ] || bad "$b block found in the formula"
  if grep -q '\\' "$TMP/$b.sh"; then bad "$b block is backslash-free"; else ok "$b block is backslash-free"; fi
  if bash -n "$TMP/$b.sh"; then ok "$b block is valid bash"; else bad "$b block is valid bash"; fi
done

# Resolve CHECK_SET the way the step does: assign the (post-substitution) var,
# set the anchor's metadata as BEAD_JSON, then run both blocks in order.
resolve() { # <var-value> <anchor-check_set-metadata>
  local var="$1" anchor="$2" anchor_json
  anchor_json=$(jq -cn --arg cs "$anchor" 'if $cs=="" then [{metadata:{}}] else [{metadata:{check_set:$cs}}] end')
  {
    printf 'CHECK_SET=%q\n' "$var"
    printf "BEAD_JSON='%s'\n" "$anchor_json"
    fence check-set-normalize
    fence check-set-prefer-approval-arm
    printf 'printf "%%s" "$CHECK_SET"\n'
  } > "$TMP/case.sh"
  bash "$TMP/case.sh"
}

# The reason this change exists: an approval-armed anchor is NOT overwritten.
eq "$(resolve "codex" "codex,approval")" "codex,approval" \
  "codex,approval anchor keeps both lanes over the codex var default"
eq "$(resolve "codex" "codex,approval,style")" "codex,approval,style" \
  "a wider approval-bearing anchor check_set is preserved verbatim"
eq "$(resolve "" "codex,approval")" "codex,approval" \
  "empty var normalizes to codex, then the approval arm wins"
eq "$(resolve "none" "codex,approval")" "codex,approval" \
  "a per-anchor approval arm outranks a gateless var"

# No approval arm on the anchor: the var default stands, unchanged.
eq "$(resolve "codex" "codex")" "codex"   "a codex-only anchor stays codex"
eq "$(resolve "codex" "")"      "codex"   "an anchor with no check_set stays the var default"
eq "$(resolve "" "")"           "codex"   "empty var with no anchor arm normalizes to codex"
eq "$(resolve "none" "")"       "none"    "gateless var is preserved when no approval arm exists"
eq "$(resolve "codex" "codex,style")" "codex" \
  "a non-approval multi-lane anchor does not trigger the arm"

echo
echo "refinery-check-set-approval-arm.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
