#!/usr/bin/env bash
# Hermetic test for the gctk-bin block: the one line by which a formula step,
# the correctness method, self-review-check.sh and rig-check-pre-existing.sh find
# the gctk binary they call directly, as $GCTK. Formula text has no include
# mechanism, so each caller carries the line in a `# >>> gctk-bin` block, and
# this holds every copy to the one definition and runs it.
#
# run-tests-scope: tree
#
# Proves:
#   - every tracked copy of the block is the same line;
#   - the line takes $GCTK_BIN as given, else the city's build under
#     $GC_CITY_PATH, and names no binary a caller could run when neither is
#     set, under bash and zsh;
#   - every file that calls "$GCTK" sets it through the block.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bin-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

LINE='GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"'

echo "# every copy is the one line"
git -C "$ROOT" grep -l -F -e '# >>> gctk-bin' -- formulas skills assets/scripts ':!*.test.sh' > "$TMP/files"
eq "$(tr '\n' ' ' < "$TMP/files")" "assets/scripts/rig-check-pre-existing.sh assets/scripts/self-review-check.sh formulas/mol-polecat-work.toml formulas/mol-refinery-patrol.toml skills/review-correctness/SKILL.md " \
  "the block sits in the files that call gctk directly"
while IFS= read -r f; do
  awk '/# >>> gctk-bin$/ {f = 1; n++; next} /# <<< gctk-bin$/ {f = 0; next} f {print n "\t" $0}' "$ROOT/$f" > "$TMP/copies"
  copies=$(cut -f1 "$TMP/copies" | sort -u | grep -c . || true)
  [ "$copies" -gt 0 ] && ok "$f: the block extracts ($copies)" || bad "$f: no block extracted"
  while IFS="$(printf '\t')" read -r n body; do
    eq "$body" "$LINE" "$f: copy $n is the one line"
  done < "$TMP/copies"
done < "$TMP/files"
eq "$(grep -c -F -x -e '# >>> gctk-bin' "$ROOT/formulas/mol-polecat-work.toml")" 3 \
  "mol-polecat-work carries it in workspace-setup, preflight-tests and self-review"

echo "# the line resolves as stated"
printf '%s\nprintf "%%s" "$GCTK"\n' "$LINE" > "$TMP/line.sh"
SHELLS="bash"; command -v zsh >/dev/null 2>&1 && SHELLS="bash zsh"
for sh in $SHELLS; do
  eq "$(env -i PATH="$PATH" GCTK_BIN=/x/gctk GC_CITY_PATH=/city "$sh" "$TMP/line.sh")" "/x/gctk" "$sh: GCTK_BIN wins"
  eq "$(env -i PATH="$PATH" GC_CITY_PATH=/city "$sh" "$TMP/line.sh")" "/city/.gc/services/gctk/bin/gctk" "$sh: else the city's build"
  eq "$(env -i PATH="$PATH" "$sh" "$TMP/line.sh")" "/.gc/services/gctk/bin/gctk" "$sh: with neither, a path no city holds"
done

echo "# every caller sets GCTK through the block"
git -C "$ROOT" grep -l -F -e '"$GCTK" rig' -- formulas skills assets/scripts ':!*.test.sh' > "$TMP/callers"
while IFS= read -r f; do
  grep -q -F -x -e '# >>> gctk-bin' "$ROOT/$f" && ok "$f: sets GCTK through the block" || bad "$f: calls \"\$GCTK\" with no gctk-bin block"
done < "$TMP/callers"

echo "---"
echo "gctk-bin.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
