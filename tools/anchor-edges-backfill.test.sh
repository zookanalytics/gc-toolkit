#!/usr/bin/env bash
# anchor-edges-backfill.test.sh — hermetic tests for joining anchors' children
# to them by the membership edge and marking the store joined.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-anchor-edges-backfill-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
# shellcheck source=../assets/scripts/test-harness.sh
. "$HERE/../assets/scripts/test-harness.sh"
harness_init
# bd answers an id it does not hold with an error object at exit 1.
export STUB_SHOW_NOT_FOUND_ERROR=1
SUT="$HERE/anchor-edges-backfill.sh"
edges() { LC_ALL=C sort "$STUB_DEPS" | paste -sd' ' -; }
marked() { grep -c '^anchor_edges\.joined=' "$STUB_KV"; }

# A live anchor whose children predate the edge, closed ones included; a live
# anchor with one child an older writer filed without the edge and a visit its
# tracks edge already joins; a closed anchor one live finding still names; a
# closed anchor with no live child; and a live child naming an anchor that is
# no bead in this store.
store '[
  {"id":"tk-old","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-o1","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"review"}},
  {"id":"tk-o2","status":"open","metadata":{"anchor_bead":"tk-old","task_kind":"finding"}},
  {"id":"tk-mig","status":"in_progress","metadata":{"merge_result":"pre_open_gate"}},
  {"id":"tk-m1","status":"open","metadata":{"anchor_bead":"tk-mig","task_kind":"review"}},
  {"id":"tk-m2","status":"closed","metadata":{"anchor_bead":"tk-mig","task_kind":"rework"}},
  {"id":"tk-mv","status":"open","metadata":{"anchor_bead":"tk-mig","task_kind":"visit"}},
  {"id":"tk-held","status":"closed","metadata":{"merge_result":"merged"}},
  {"id":"tk-h1","status":"open","metadata":{"anchor_bead":"tk-held","task_kind":"finding"}},
  {"id":"tk-h2","status":"closed","metadata":{"anchor_bead":"tk-held","task_kind":"rework"}},
  {"id":"tk-done","status":"closed","metadata":{"merge_result":"merged"}},
  {"id":"tk-d1","status":"closed","metadata":{"anchor_bead":"tk-done","task_kind":"review"}},
  {"id":"tk-stray","status":"open","metadata":{"anchor_bead":"W3","task_kind":"rework"}}
]'
printf '%s\n' 'tk-m1|related|tk-mig' 'tk-mv|tracks|tk-mig' 'tk-o2|blocks|tk-old' > "$STUB_DEPS"
BEFORE=$(edges)

out=$("$SUT" --check 2>&1); rc=$?
eq "$rc" 1 "--check exits 1 when an anchor is missing an edge"
has "$out" "tk-old — 2 child(ren) lack the edge: tk-o1 tk-o2" "…naming a live anchor's children, closed ones included"
has "$out" "tk-mig — 1 child(ren) lack the edge: tk-m2" "…and the child the other live anchor is missing"
has "$out" "tk-held — 2 child(ren) lack the edge: tk-h1 tk-h2" "…and a closed anchor a live child still names"
hasnt "$out" "tk-done" "…but never a closed anchor no live child names"
has "$out" "W3 — named in anchor_bead but no bead in this store; skipped" "…and an anchor that does not resolve is reported, not read as an outage"
has "$out" "the store is not marked joined" "…and it says the store is not marked"
eq "$(edges)" "$BEFORE" "--check writes nothing"

out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "a run that joins every missing child exits 0"
has "$out" "joined 5 child(ren)" "…and reports how many it joined"
eq "$(edges)" "tk-h1|related|tk-held tk-h2|related|tk-held tk-m1|related|tk-mig tk-m2|related|tk-mig tk-mv|tracks|tk-mig tk-o1|related|tk-old tk-o2|blocks|tk-old tk-o2|related|tk-old" \
  "every visited anchor's children are joined, and the visit stays on its tracks edge"
eq "$(grep -c '^bd dep add --file' "$STUB_GC_LOG")" 3 "…in one write per anchor that needed one"
eq "$(marked)" 0 "a plain run marks nothing"

: > "$STUB_GC_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "a second run exits 0"
eq "$(grep -c '^bd dep add' "$STUB_GC_LOG")" 0 "…and joins nothing: the run is idempotent"
"$SUT" --check >/dev/null 2>&1; rc=$?
eq "$rc" 0 "--check exits 0 once every child is joined"

# --mark marks the store only after a run that found nothing to join.
out=$("$SUT" --mark 2>&1); rc=$?
eq "$rc" 0 "--mark over a joined store exits 0"
has "$out" "marked the store joined" "…and says so"
eq "$(marked)" 1 "…with the mark in the store's kv"
out=$("$SUT" --check 2>&1)
has "$out" "the store is marked joined" "--check reports the mark"
: > "$STUB_KV"
printf '%s\n' 'tk-m1|related|tk-mig' 'tk-mv|tracks|tk-mig' > "$STUB_DEPS"
out=$("$SUT" --mark 2>&1); rc=$?
eq "$rc" 3 "--mark that still joins children exits 3"
has "$out" "the store is not marked" "…and says it did not mark"
eq "$(marked)" 0 "…leaving the mark unset"
has "$(edges)" "tk-o1|related|tk-old" "…though it joined what it found"
out=$("$SUT" --mark 2>&1); rc=$?
eq "$rc:$(marked)" "0:1" "the next --mark, finding nothing to join, marks the store"
: > "$STUB_KV"
STUB_KV_FAIL=1 "$SUT" --mark >/dev/null 2>&1; rc=$?
eq "$rc" 1 "a mark that does not read back exits 1"
"$SUT" --mark tk-old >/dev/null 2>&1; rc=$?
eq "$rc" 2 "--mark names no anchor"
"$SUT" --check --mark >/dev/null 2>&1; rc=$?
eq "$rc" 2 "--check and --mark do not combine"

# A named anchor limits the run to it.
printf '%s\n' 'tk-m1|related|tk-mig' > "$STUB_DEPS"
out=$("$SUT" tk-mig 2>&1); rc=$?
eq "$rc" 0 "a named anchor is backfilled"
eq "$(edges)" "tk-m1|related|tk-mig tk-m2|related|tk-mig tk-mv|related|tk-mig" "…and only that anchor"

# A pair bd refuses costs only itself.
: > "$STUB_DEPS"
out=$(STUB_DEP_ADD_FAIL=tk-o2 "$SUT" tk-old 2>&1); rc=$?
eq "$rc" 1 "a run with a pair bd refused exits 1"
has "$out" "could not join tk-o2 to anchor tk-old" "…naming the refused pair"
has "$(edges)" "tk-o1|related|tk-old" "…and the anchor's other child is joined"

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
