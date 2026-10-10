#!/usr/bin/env bash
# anchor-edges-backfill.test.sh — hermetic tests for joining live anchors'
# children to them by the membership edge.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-anchor-edges-backfill-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
# shellcheck source=../assets/scripts/test-harness.sh
. "$HERE/../assets/scripts/test-harness.sh"
harness_init
SUT="$HERE/anchor-edges-backfill.sh"
edges() { LC_ALL=C sort "$STUB_DEPS" | paste -sd' ' -; }

# A live anchor whose children predate the edge, closed ones included; a
# migrated live anchor with one child an older writer filed without the edge
# and a visit its tracks edge already joins; and a closed anchor.
store '[
  {"id":"tk-old","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-o1","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"review"}},
  {"id":"tk-o2","status":"open","metadata":{"anchor_bead":"tk-old","task_kind":"finding"}},
  {"id":"tk-mig","status":"in_progress","metadata":{"merge_result":"pre_open_gate"}},
  {"id":"tk-m1","status":"open","metadata":{"anchor_bead":"tk-mig","task_kind":"review"}},
  {"id":"tk-m2","status":"closed","metadata":{"anchor_bead":"tk-mig","task_kind":"rework"}},
  {"id":"tk-mv","status":"open","metadata":{"anchor_bead":"tk-mig","task_kind":"visit"}},
  {"id":"tk-done","status":"closed","metadata":{"merge_result":"merged"}},
  {"id":"tk-d1","status":"closed","metadata":{"anchor_bead":"tk-done","task_kind":"review"}}
]'
printf '%s\n' 'tk-m1|related|tk-mig' 'tk-mv|tracks|tk-mig' 'tk-o2|blocks|tk-old' > "$STUB_DEPS"
BEFORE=$(edges)

out=$("$SUT" --check 2>&1); rc=$?
eq "$rc" 1 "--check exits 1 when a live anchor is missing an edge"
has "$out" "tk-old — 2 child(ren) lack the edge: tk-o1 tk-o2" "…naming the unmigrated anchor's children, closed ones included"
has "$out" "tk-mig — 1 child(ren) lack the edge: tk-m2" "…and the child a migrated anchor is missing"
hasnt "$out" "tk-done" "…and never a closed anchor"
eq "$(edges)" "$BEFORE" "--check writes nothing"

out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "a run that joins every missing child exits 0"
has "$out" "joined 3 child(ren)" "…and reports how many it joined"
eq "$(edges)" "tk-m1|related|tk-mig tk-m2|related|tk-mig tk-mv|tracks|tk-mig tk-o1|related|tk-old tk-o2|blocks|tk-old tk-o2|related|tk-old" \
  "every live anchor's children are joined, the visit stays on its tracks edge, and the closed anchor is left alone"
eq "$(grep -c '^bd dep add --file' "$STUB_GC_LOG")" 2 "…in one write per anchor that needed one"

: > "$STUB_GC_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "a second run exits 0"
eq "$(grep -c '^bd dep add' "$STUB_GC_LOG")" 0 "…and joins nothing: the run is idempotent"
"$SUT" --check >/dev/null 2>&1; rc=$?
eq "$rc" 0 "--check exits 0 once every child is joined"

# A named anchor limits the run to it.
printf '%s\n' 'tk-m1|related|tk-mig' > "$STUB_DEPS"
out=$("$SUT" tk-mig 2>&1); rc=$?
eq "$rc" 0 "a named anchor is backfilled"
eq "$(edges)" "tk-m1|related|tk-mig tk-m2|related|tk-mig tk-mv|related|tk-mig" "…and only that anchor"

# A store that does not answer joins nothing and says so.
STUB_LIST_FAIL=1 "$SUT" >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an unreadable anchor enumeration exits 2"
: > "$STUB_DEPS"
out=$(STUB_DEP_PARTIAL=1 "$SUT" tk-old 2>&1); rc=$?
eq "$rc" 2 "an unreadable edge read exits 2"
has "$out" "tk-old — its children did not read" "…naming the anchor"
eq "$(edges)" "" "…and joins nothing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
