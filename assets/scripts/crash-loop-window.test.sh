#!/usr/bin/env bash
# Hermetic test for the witness-patrol CRASH-LOOP WINDOW.
#
# mol-witness-patrol's recover-orphaned-beads decides a crash loop from a RATE.
# It reads recovered_at and recovered_count before its own stamp overwrites
# them, and escalates only when the previous recovery falls inside
# CRASH_LOOP_WINDOW: two recoveries close together are a loop, two far apart are
# two incidents. A bead carrying only the legacy `recovered=true` flag, with no
# timestamp or count, holds no recurrence evidence, so it stamps a first
# timestamp and escalates nothing. An unusable recovered_at is unknown, and
# unknown never escalates.
#
# This test EXECUTES the real block extracted verbatim from the formula
# (between the `crash-loop-window` markers), so it cannot drift from the
# shipped instruction. No live city, Dolt, network, or sessions.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-crash-loop-window-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# --- Extract the REAL block from the formula. --------------------------------
# If the markers or the block are removed or renamed, extraction yields nothing
# and the check below fails loudly — the contract cannot silently disappear.
BLOCK="$(awk '
  /# >>> crash-loop-window/ {f=1; next}
  /# <<< crash-loop-window/ {f=0}
  f' "$TOML")"

[ -n "$BLOCK" ] \
  && ok "block extracted between crash-loop-window markers" \
  || bad "block extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$BLOCK" > "$TMP/block.sh"
bash -n "$TMP/block.sh" \
  && ok "extracted block is syntactically valid bash" \
  || bad "extracted block failed bash -n"

case "$BLOCK" in
  *'\'*) bad "the block carries a backslash — TOML triple-quote eats continuations" ;;
  *)     ok "the block is backslash-free, as the formula header requires" ;;
esac

# decide <prev_at> <prev_count> <prev_flag> [window] -> "COUNT CRASH_LOOP"
# Sourced exactly as the witness runs it, under `set -u`: the recovery loop has
# no obligation to pre-set a key the bead does not carry, so every input must
# absorb its own absence rather than abort the cycle.
decide() {
  PREV_AT="$1" PREV_COUNT="$2" PREV_FLAG="$3" CRASH_LOOP_WINDOW="${4:-}" \
  bash -u -c '
    [ -n "$CRASH_LOOP_WINDOW" ] || unset CRASH_LOOP_WINDOW
    source "$0"
    printf "%s %s" "$COUNT" "$CRASH_LOOP"
  ' "$TMP/block.sh" 2>"$TMP/err"
}
# ago <seconds> -> the stamp that many seconds back, in the form NOW_AT writes.
# GNU date reads epoch seconds with -d @N and BSD date with -r N.
ago() {
  local s=$(( $(date -u +%s) - $1 ))
  date -u -d "@$s" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$s" +%Y-%m-%dT%H:%M:%SZ
}

echo "# a bead with no recovery history is never a loop"
eq "$(decide '' '' '')" "1 0" "a first recovery counts 1 and escalates nothing"
eq "$(cat "$TMP/err")" "" "and runs clean under set -u"

echo "# the legacy population drains instead of escalating itself"
# A bead carrying a bare recovered=true with no timestamp holds no recurrence
# evidence, so it seeds a first count and escalates nothing rather than reading
# the mark as a repeat.
eq "$(decide '' '' 'true')" "2 0" "a bare legacy flag escalates nothing and seeds the count at 2"
eq "$(decide '' 'notanumber' 'true')" "2 0" "an unparseable count falls back to the flag"
eq "$(decide '' 'notanumber' '')" "1 0" "with no flag either, it starts over at 1"

echo "# inside the window is a loop; outside it is two incidents"
eq "$(decide "$(ago 600)" '1' 'true')" "2 1" "a recovery 10 minutes after the last one is a loop"
eq "$(decide "$(ago 3600)" '1' 'true')" "2 1" "an hour after is still a loop"
eq "$(decide "$(ago 86400)" '1' 'true')" "2 0" "a day after is not"
eq "$(decide "$(ago 259200)" '4' 'true')" "5 0" "three days after is not, however many came before"

echo "# the boundary is closed against the loop"
# A minute either side, not a second: `ago` and the block read the clock
# separately, so a one-second margin makes the case race the tick rather than
# test the comparison.
eq "$(decide "$(ago 21540)" '1' 'true')" "2 1" "just inside the default window is a loop"
eq "$(decide "$(ago 21660)" '1' 'true')" "2 0" "just outside it is not"

echo "# an unusable timestamp is UNKNOWN, and unknown never escalates"
# The read failing is a different fact from the recoveries being close
# together, and only the second one is grounds for a visit.
eq "$(decide 'not-a-date' '1' 'true')" "2 0" "an unparseable recovered_at does not escalate"
eq "$(decide '' '3' 'true')" "4 0" "a count with no timestamp does not escalate"
eq "$(cat "$TMP/err")" "" "and neither path leaks an error"

echo "# the count is the history, and it keeps counting"
eq "$(decide "$(ago 600)" '7' 'true')" "8 1" "an existing count increments"
eq "$(decide "$(ago 90000)" '7' 'true')" "8 0" "and increments outside the window too"

echo "# the block survives set -e, which the sibling guards in this step run under"
# The last command of a sourced file sets its exit status, and `source` hands
# that status to the caller. So the window has to end in a construct that
# succeeds on BOTH verdicts: an `if` does, while `[ ... ] && CRASH_LOOP=1`
# returns 1 whenever the test is false — the ordinary not-a-loop path, taken on
# almost every recovery. These cases source the block as the whole unit, because
# any command after the window supplies its own status and hides the difference.
sete() {
  PREV_AT="$1" PREV_COUNT="$2" PREV_FLAG="$3" \
  bash -eu -c 'source "$0"; printf "%s %s" "$COUNT" "$CRASH_LOOP"' "$TMP/block.sh" 2>/dev/null
}
eq "$(sete "$(ago 90000)" '1' 'true')" "2 0" "the not-a-loop path completes under set -e"
eq "$(sete "$(ago 600)" '1' 'true')" "2 1" "the loop path completes under set -e"
eq "$(sete '' '' '')" "1 0" "and so does the no-history path"

echo "# the stamp is read as UTC whatever zone the witness runs in"
# POSIX TZ strings need no zoneinfo files: LINT-14 is fourteen hours ahead of
# UTC and HST10 ten hours behind. A parse that read the stamp as local time
# would move each recovery by that offset and flip both verdicts.
eq "$(TZ=LINT-14 decide "$(ago 600)" '1' 'true')" "2 1" "fourteen hours ahead of UTC, a recovery 10 minutes ago is still a loop"
eq "$(TZ=HST10 decide "$(ago 43200)" '1' 'true')" "2 0" "ten hours behind, one 12 hours ago is still not"

echo "# the window is tunable"
eq "$(decide "$(ago 3600)" '1' 'true' 600)" "2 0" "a narrower window reads the same pair as two incidents"
eq "$(decide "$(ago 90000)" '1' 'true' 172800)" "2 1" "a wider one reads them as a loop"

echo
echo "crash-loop-window.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
