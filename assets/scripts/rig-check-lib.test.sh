#!/usr/bin/env bash
# rig-check-lib.test.sh — the one definition of whether a recorded fail of a rig
# check is judged pre-existing, and the readers that apply it.
#
#   (DEF)     pre_existing answers "tracked by <ids>" only for a mark that holds
#             the record in hand at the commit and names a tracker. It answers
#             "another run" for a mark at the commit that names a tracker for
#             another record, or when the record in hand does not parse, and
#             nothing for a mark at another commit, a mark with no tracker, an
#             absent or unparsable mark, another check's key, or an input that
#             is not a bead row.
#   (READERS) the scripts that read a rig_check_pre_existing mark, its writer
#             aside, source this file and apply $PRE_EXISTING_JQ, and no script
#             or formula reads one any other way.
#   (NO-COPY) no other file defines pre_existing.
# A reader with a private copy of the judgment drifts silently from this one.
# The behavioral half lives beside its reader (self-review-check.test.sh).
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/rig-check-lib.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=rig-check-lib.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${PRE_EXISTING_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$PRE_EXISTING_JQ" || bad "(DEF) sourcing the file exposes \$PRE_EXISTING_JQ"

C1=1111111111111111111111111111111111111111
C2=2222222222222222222222222222222222222222
REC='{"check":"test","result":"fail","scope":"affected","commit":"'$C1'","exit_code":1,"command":"run"}'
OTHER='{"check":"test","result":"fail","scope":"full","commit":"'$C1'","exit_code":1,"command":"run all"}'
# bead <key> <mark JSON, or empty for none> [string|object] : a bead row whose
# metadata carries the mark under <key>, stored as a string the way bd stores
# metadata, or as an object.
bead() {
  if [ -z "$2" ]; then printf '[{"id":"tk-w","metadata":{}}]'; return; fi
  if [ "${3:-string}" = string ]; then
    jq -nc --arg k "$1" --arg m "$2" '[{id: "tk-w", metadata: {($k): $m}}]'
  else
    jq -nc --arg k "$1" --argjson m "$2" '[{id: "tk-w", metadata: {($k): $m}}]'
  fi
}
mark() { jq -nc --arg c "$1" --argjson r "$2" --argjson t "$3" '{commit: $c, record: $r, trackers: $t}'; }
# judge <bead row> <check> <commit> <record> : the judgment, as a reader applies it.
judge() {
  printf '%s' "$1" | jq -r --arg k "rig_check_pre_existing.$2" --arg c "$3" --arg rec "$4" \
    "$PRE_EXISTING_JQ"' pre_existing($k; $c; $rec)' 2>/dev/null
}
K=rig_check_pre_existing.test

echo "# the judgment"
eq "$(judge "$(bead $K "$(mark $C1 "$REC" '["tk-a","tk-b"]')")" test $C1 "$REC")" "tracked by tk-a, tk-b" \
  "(DEF) a mark holding the record at the commit is pre-existing, naming its trackers"
eq "$(judge "$(bead $K "$(mark $C1 "$REC" '["tk-a"]')" object)" test $C1 "$REC")" "tracked by tk-a" \
  "(DEF) …stored as an object as well as a string"
eq "$(judge "$(bead $K "$(mark $C1 "$REC" '["tk-a"]')")" test $C1 "$(printf '%s' "$REC" | jq -c '{command, exit_code, commit, scope, result, check}')")" "tracked by tk-a" \
  "(DEF) the record compares as JSON, whatever its key order"
eq "$(judge "$(bead $K "$(mark $C1 "$OTHER" '["tk-a"]')")" test $C1 "$REC")" "another run" \
  "(DEF) a mark at the commit for another record is another run's"
eq "$(judge "$(bead $K "$(mark $C1 "$REC" '["tk-a"]')")" test $C1 "not json")" "another run" \
  "(DEF) a record in hand that does not parse is not the one judged"
eq "$(judge "$(bead $K "$(mark $C2 "$REC" '["tk-a"]')")" test $C1 "$REC")" "" \
  "(DEF) a mark at another commit answers nothing"
eq "$(judge "$(bead $K "$(mark $C1 "$REC" '[]')")" test $C1 "$REC")" "" \
  "(DEF) a mark naming no tracker answers nothing"
eq "$(judge "$(bead $K "$(jq -nc --arg c $C1 --argjson r "$REC" '{commit: $c, record: $r}')")" test $C1 "$REC")" "" \
  "(DEF) a mark with no trackers key answers nothing"
eq "$(judge "$(bead $K "")" test $C1 "$REC")" "" "(DEF) no mark answers nothing"
eq "$(judge "$(bead $K "{not json")" test $C1 "$REC")" "" "(DEF) a mark that does not parse answers nothing"
eq "$(judge "$(bead rig_check_pre_existing.lint "$(mark $C1 "$REC" '["tk-a"]')")" test $C1 "$REC")" "" \
  "(DEF) another check's mark answers nothing for this one"
eq "$(judge '{"error":"no such bead"}' test $C1 "$REC")" "" "(DEF) an input that is not a bead row answers nothing"

echo "# every reader applies the one definition"
# Comment lines are left out, so a reader that names the library in prose but
# no longer calls it still fails.
code() { grep -vE '^[[:space:]]*#' "$1"; }
READERS="assets/scripts/self-review-check.sh"
for r in $READERS; do
  f="$ROOT/$r"
  if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
  grep -qE '^[[:space:]]*\.[[:space:]].*rig-check-lib\.sh' < <(code "$f") \
    && ok "(READERS) $r sources rig-check-lib.sh" || bad "(READERS) $r sources rig-check-lib.sh"
  grep -qF '"$PRE_EXISTING_JQ"'"' pre_existing(" < <(code "$f") \
    && ok "(READERS) $r applies pre_existing from \$PRE_EXISTING_JQ" || bad "(READERS) $r applies pre_existing from \$PRE_EXISTING_JQ"
done
# The writer reads the key back to merge trackers into its own judgment, which
# is not this question; every other script or formula that names the key is a
# reader.
WRITER="assets/scripts/rig-check-pre-existing.sh"
NAMED=$(git -C "$ROOT" grep -l -F 'rig_check_pre_existing' -- 'assets/scripts/*.sh' 'formulas/*.toml' 'packs' 'doctor' 'orders' 'tools' ':!*.test.sh' 2>/dev/null)
[ -n "$NAMED" ] && ok "(READERS) the scan finds the scripts that name the key" || bad "(READERS) the scan finds the scripts that name the key"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$f" = "$WRITER" ] && continue
  grep -qF 'rig_check_pre_existing' < <(code "$ROOT/$f") || continue
  grep -qxF -- "$f" <<< "$READERS" && ok "(READERS) $f reads a mark and is a listed reader" \
    || bad "(READERS) $f reads a mark and is a listed reader" "add it to READERS and have it source rig-check-lib.sh"
done <<< "$NAMED"

echo "# no private copies"
COPIES=$(git -C "$ROOT" grep -l -E 'def[[:space:]]+pre_existing[^[:alnum:]_]' -- . ':!assets/scripts/rig-check-lib.sh' ':!specs' 2>/dev/null | grep -v '\.test\.sh$')
eq "$COPIES" "" "(NO-COPY) no other file defines pre_existing"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
