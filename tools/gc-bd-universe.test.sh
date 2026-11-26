#!/usr/bin/env bash
# gc-bd-universe.test.sh — hermetic tests for the universe slice's read of a
# bead's children: a read that fails is no answer, never a bead with none.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-bd-universe-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
# shellcheck source=../assets/scripts/test-harness.sh
. "$HERE/../assets/scripts/test-harness.sh"
harness_init
SUT="$HERE/gc-bd-universe.sh"

store '[
  {"id":"tk-p","title":"parent","status":"open"},
  {"id":"tk-c1","title":"open child","status":"open","parent":"tk-p"},
  {"id":"tk-c2","title":"closed child","status":"closed","parent":"tk-p"},
  {"id":"tk-lone","title":"no children","status":"open"}
]'

out=$("$SUT" slice tk-p 2>&1); rc=$?
eq "$rc" 0 "a slice whose children read answers exits 0"
has "$out" "children=2" "…and counts each child, a closed one included"
has "$out" "child  → tk-c2 · closed child · closed" "…and lists the closed one"

out=$("$SUT" slice tk-lone 2>&1); rc=$?
eq "$rc" 0 "a slice of a bead with no children exits 0"
has "$out" "children=0" "…and counts none"

# The fake answers children as the listing `list --parent <id> --status all`,
# which the list faults read.
for fault in "STUB_FAIL_ON=bd children" "STUB_LIST_PARTIAL=--parent tk-p" "STUB_LIST_OBJECT=1"; do
  out=$(env "$fault" "$SUT" slice tk-p 2>&1); rc=$?
  eq "$rc" 3 "$fault: slice exits 3, as for a bead it cannot read"
  has "$out" "children of bead tk-p" "$fault: …naming the children read"
  hasnt "$out" "children=0" "$fault: …and counts no children"
  out=$(env "$fault" "$SUT" slice tk-p --json 2>/dev/null); rc=$?
  eq "$rc" 3 "$fault: slice --json exits 3"
  eq "$out" "" "$fault: …and prints no slice"
  out=$(env "$fault" "$SUT" footprint tk-p 2>&1); rc=$?
  eq "$rc" 3 "$fault: footprint exits 3"
  hasnt "$out" "PASS" "$fault: …and passes nothing"
done

out=$("$SUT" footprint tk-gone 2>&1); rc=$?
eq "$rc" 3 "footprint of a bead the store does not hold exits 3"
hasnt "$out" "PASS" "…and passes nothing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
