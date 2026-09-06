#!/usr/bin/env bash
# Hermetic test for the witness-patrol RECOVERY-STAMP GATE.
#
# mol-witness-patrol's recover-orphaned-beads records a recovery — stamps
# recovered=/recovered_at/recovered_count and reads the crash-loop RATE off them —
# ONLY for a bead orphan-dispose actually returned to the pool. A disposal that
# SKIPPED touched nothing: a workflow root, or a source bead whose work already
# reached a downstream court (an in-flight PR, or a human gate). Stamping a
# recovery on a skip would feed the crash-loop signal a RATE for work that was
# never re-dispatched, which is the moot-visit escalation the downstream-court
# filter exists to stop. The gate keys on orphan-dispose's own result verdict:
# only `disposed` is a recovery; `skipped`, `partial`, `failed`, and an unread
# empty are not.
#
# This test EXECUTES the real block extracted verbatim from the formula (between
# the `recovery-stamp-gate` markers), so it cannot drift from the shipped
# instruction. No live city, Dolt, network, or sessions.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

# --- Extract the REAL block from the formula. --------------------------------
# If the markers or the block are removed or renamed, extraction yields nothing
# and the check below fails loudly — the contract cannot silently disappear.
BLOCK="$(awk '
  /# >>> recovery-stamp-gate/ {f=1; next}
  /# <<< recovery-stamp-gate/ {f=0}
  f' "$TOML")"

[ -n "$BLOCK" ] \
  && ok "block extracted between recovery-stamp-gate markers" \
  || bad "block extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$BLOCK" > "$TMP/block.sh"
bash -n "$TMP/block.sh" \
  && ok "extracted block is syntactically valid bash" \
  || bad "extracted block failed bash -n"

case "$BLOCK" in
  *'\'*) bad "the block carries a backslash — TOML triple-quote eats continuations" ;;
  *)     ok "the block is backslash-free, as the formula header requires" ;;
esac

# gate <dispose_result> -> STAMP_RECOVERY. Sourced exactly as the witness runs
# it, under `set -u`: the step pre-sets DISPOSE_RESULT to "" before the disposal,
# but the block must absorb an unset value rather than abort the cycle.
gate() {
  DISPOSE_RESULT="$1" \
  bash -u -c '
    [ -n "$DISPOSE_RESULT" ] || unset DISPOSE_RESULT
    source "$0"
    printf "%s" "$STAMP_RECOVERY"
  ' "$TMP/block.sh" 2>"$TMP/err"
}

echo "# only a disposed bead is a recovery"
eq "$(gate disposed)" "1" "result=disposed stamps a recovery"
eq "$(cat "$TMP/err")" "" "and runs clean under set -u"

echo "# a skip is not a recovery — the P1 the gate fixes"
eq "$(gate skipped)" "0" "result=skipped (a root, or a downstream-court source) stamps nothing"

echo "# a failed or partial disposal returned nothing to the pool"
eq "$(gate partial)" "0" "result=partial is not a recovery"
eq "$(gate failed)"  "0" "result=failed is not a recovery"

echo "# an unread or absent verdict fails safe — do not stamp"
eq "$(gate '')" "0" "an empty result stamps nothing"
eq "$(gate preview)" "0" "a preview (no --apply reached the disposal) stamps nothing"
eq "$(gate whatever)" "0" "an unrecognised verdict stamps nothing"
eq "$(cat "$TMP/err")" "" "and no path leaks an error under set -u"

echo "# the block survives set -e, which the sibling guards in this step run under"
sete() {
  DISPOSE_RESULT="$1" \
  bash -eu -c 'source "$0"; printf "%s" "$STAMP_RECOVERY"' "$TMP/block.sh" 2>/dev/null
}
eq "$(sete disposed)" "1" "the recovery path completes under set -e"
eq "$(sete skipped)"  "0" "the skip path completes under set -e"

echo
echo "recovery-stamp-gate.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
