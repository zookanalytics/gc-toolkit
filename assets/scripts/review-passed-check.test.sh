#!/usr/bin/env bash
# Tests for review-passed-check.sh, the review loop's check, with gctk stubbed.
#
# Covers the one call it makes, `gctk review passed <iteration bead>
# --iteration <n> --record`, with the pack's scripts directory named for the
# gate and the findings' close it runs; gctk's exit handed to Gas City as it
# is, 0, 1 or 75; and 75, a re-run that spends no attempt, when no iteration is
# named or there is no gctk to ask.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only
PASS=0; FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-passed-check-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
unset "${!GC_@}" "${!BEADS_@}" GCTK_BIN GCTK_SCRIPTS_DIR 2>/dev/null || true

SD="$TMP/scripts"; mkdir -p "$SD"
cp "$HERE/review-passed-check.sh" "$HERE/gctk-resolve.sh" "$SD/"
LOG="$TMP/calls.log"; export LOG
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/gctk" <<'STUB'
printf '%s|%s\n' "$*" "${GCTK_SCRIPTS_DIR:-}" >> "$LOG"
exit "${STUB_RC:-0}"
STUB
chmod +x "$TMP/gctk"
export GCTK_BIN="$TMP/gctk"

run() { : > "$LOG"; OUT=$(bash "$SD/review-passed-check.sh" 2>&1); RC=$?; }

GC_BEAD_ID=tk-iter GC_ITERATION=2 run
eq "$RC" 0 "an iteration that passed and recorded exits 0"
eq "$(cat "$LOG")" "review passed tk-iter --iteration 2 --record|$SD" \
    "through one call that records, naming the pack's scripts directory"
for rc in 1 75; do
    GC_BEAD_ID=tk-iter GC_ITERATION=2 STUB_RC=$rc run
    eq "$RC" "$rc" "gctk's exit $rc reaches Gas City as it is"
done

GC_ITERATION=2 run
eq "$RC/$(wc -l < "$LOG" | tr -d ' ')" "75/0" "no iteration bead named is a re-run, and gctk is not asked"
has "$OUT" "GC_BEAD_ID and GC_ITERATION name no iteration" "saying why"
GC_BEAD_ID=tk-iter GC_ITERATION=2 GCTK_BIN=none run
eq "$RC" 75 "no gctk to ask is a re-run"

echo
echo "review-passed-check.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
