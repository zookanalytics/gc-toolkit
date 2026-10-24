#!/usr/bin/env bash
# Hermetic test for assets/scripts/work-sling.sh — the sling of a work bead, which
# gives a convoy that is its own work bead an input convoy that tracks it alone.
# Covers: the usage refusals; a sling that pours no formula, and one onto a bead
# that is not a convoy, a convoy with no branch or a closed convoy, each handed
# to gc sling as it stands; a pour onto a convoy that carries a branch made
# through an input convoy that tracks it alone, marked, at its priority and
# target, with the bead stamped the way gc sling stamps any bead it pours onto,
# and the run mol-polecat-work's own derivation finds working on the bead; a live
# run of the formula on the bead refused, and a closed run or one of another
# formula not; and every way it stops short, each leaving nothing slung and no
# convoy of its own open, except one a workflow root names. The harness gc stub
# stands in for gc and its store.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-sling-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/work-sling.sh"
export GC_RIG="gc-toolkit"
ROUTE="gc-toolkit/gc-toolkit.polecat"

# mol-polecat-work takes the one bead its input convoy tracks as its work bead.
# The derivation is read from the formula, so this suite follows it.
DERIVE=$(grep -m 1 -o "jq -r 'if (.children | length) == 1 then [^']*'" "$HERE/../../formulas/mol-polecat-work.toml" | sed "s/^jq -r '//; s/'\$//")
has "$DERIVE" ".children[0].id" "mol-polecat-work's work-bead derivation was read from the formula"
work_bead_of() { gc convoy status "$1" --json 2>/dev/null | jq -r "$DERIVE" 2>/dev/null; }

# A graduation's anchor: a convoy carrying the branch and target
# convoy-graduate.sh stamps, tracking the three members it landed. $1 adds to
# the store, $2 to its metadata.
anchor() { # [extra-rows] [extra-metadata-fields]
  store "[{\"id\":\"tk-g\",\"status\":\"open\",\"assignee\":\"\",\"title\":\"g\",\"issue_type\":\"convoy\",\"priority\":1,\"metadata\":{\"branch\":\"integration/tk-g\",\"target\":\"main\",\"graduation\":true${2:-}}},
          {\"id\":\"tk-m1\",\"status\":\"closed\",\"title\":\"m1\",\"metadata\":{}},
          {\"id\":\"tk-m2\",\"status\":\"closed\",\"title\":\"m2\",\"metadata\":{}},
          {\"id\":\"tk-m3\",\"status\":\"closed\",\"title\":\"m3\",\"metadata\":{}}${1:-}]"
  : > "$STUB_DEPS"
  local m
  for m in tk-m1 tk-m2 tk-m3; do printf 'tk-g|tracks|%s\n' "$m" >> "$STUB_DEPS"; done
}
reset() {
  : > "$STUB_GC_LOG"
  export STUB_SLING_FAIL="" STUB_UPDATE_FAIL="" STUB_SHOW_FAIL="" STUB_DROP_KEYS="" STUB_DEP_PARTIAL=""
  export STUB_CONVOY_CREATE_FAIL="" STUB_CONVOY_ADD_FAIL=""
}
# $out is stderr and stdout together.
run() { "$SD/work-sling.sh" "$@" > "$TMP/stdout" 2> "$TMP/stderr"; rc=$?; out=$(cat "$TMP/stderr" "$TMP/stdout"); }
slung() { grep '^sling ' "$STUB_GC_LOG" || true; }
slings() { grep -c '^sling ' "$STUB_GC_LOG" || true; }
convoys() { jq -r '[.[] | select((.issue_type // "") == "convoy" and .id != "tk-g") | .id] | join(" ")' "$STUB_STORE"; }
open_convoys() { jq -r '[.[] | select((.issue_type // "") == "convoy" and .id != "tk-g" and .status != "closed") | .id] | join(" ")' "$STUB_STORE"; }

echo "# usage refusals do nothing"
reset; anchor
run --target "$ROUTE";                eq "$rc" 1 "no bead -> exit 1"
run tk-g;                             eq "$rc" 1 "no --target -> exit 1"
run tk-g --target "$ROUTE" --bogus;   eq "$rc" 1 "an unknown flag -> exit 1"
run tk-g tk-x --target "$ROUTE";      eq "$rc" 1 "two beads -> exit 1"
eq "$(wc -l < "$STUB_GC_LOG" | tr -d ' ')" "0" "a usage refusal runs no gc"

echo "# a sling that pours no formula is gc sling's own"
reset; anchor
run tk-g --target "$ROUTE" -- --merge mr
eq "$rc" 0 "it exits as gc sling does"
eq "$(cat "$STUB_GC_LOG")" "sling --rig gc-toolkit $ROUTE tk-g --merge mr" "one gc call: the sling, its args in order, and no read of the bead"
eq "$(convoys)" "" "no input convoy is made"
reset; anchor
STUB_SLING_FAIL=1 run tk-g --target "$ROUTE"
eq "$rc" 1 "a failed plain sling exits with gc sling's code"

echo "# a pour onto a bead that is not a convoy is gc sling's own"
reset
store '[{"id":"tk-w","status":"open","assignee":"","title":"w","issue_type":"task","metadata":{"branch":"polecat/tk-w"}}]'; : > "$STUB_DEPS"
run tk-w --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "it exits 0"
eq "$(slung)" "sling --rig gc-toolkit $ROUTE tk-w --on mol-polecat-work" "slung onto the bead itself, which gc sling gives its own input convoy"
eq "$(convoys)" "" "no input convoy is made here"

echo "# a pour onto a convoy that carries no branch is onto its members"
reset
store '[{"id":"tk-c","status":"open","assignee":"","title":"c","issue_type":"convoy","metadata":{"target":"integration/tk-c"}}]'; : > "$STUB_DEPS"
run tk-c --target "$ROUTE" -- --on mol-polecat-work
eq "$(slung)" "sling --rig gc-toolkit $ROUTE tk-c --on mol-polecat-work" "an integration convoy not yet graduated is slung as it stands"
eq "$(convoys)" "tk-c" "no input convoy is made for it"

echo "# a pour onto a closed convoy goes to gc sling, which refuses it"
reset; anchor
jq -c 'map(if .id == "tk-g" then .status = "closed" else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$(slung)" "sling --rig gc-toolkit $ROUTE tk-g --on mol-polecat-work" "a closed anchor is slung as it stands"
eq "$(convoys)" "" "no input convoy is made for a closed anchor"

echo "# a pour onto a convoy that is its own work goes through an input convoy that tracks it alone"
reset; anchor
eq "$(work_bead_of tk-g)" "" "poured as it stands, the run would find no one work bead"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "it exits 0"
icv="$(convoys)"
eq "$icv" "new-5" "one input convoy is made"
eq "$(slung)" "sling --rig gc-toolkit $ROUTE $icv --on mol-polecat-work" "the pour is onto the input convoy, to the target, with its args"
has "$(cat "$STUB_GC_LOG")" "convoy create input convoy for tk-g --rig gc-toolkit --target main --json" "the convoy is made in GC_RIG's store, with the anchor's target"
has "$(cat "$STUB_GC_LOG")" "convoy add $icv tk-g --rig gc-toolkit" "and then tracks the anchor"
eq "$(work_bead_of "$icv")" "tk-g" "the run it pours works on the anchor"
eq "$(jq -r --arg id "$icv" '.[] | select(.id == $id) | [.title, .priority, .metadata["gc.synthetic"], .metadata.target] | map(tostring) | join(" | ")' "$STUB_STORE")" \
  "input convoy for tk-g | 1 | true | main" "titled and marked as gc sling makes one, at the anchor's priority and target"
eq "$(meta tk-g gc.execution_routed_to)" "$ROUTE" "the anchor carries the gc.execution_routed_to the pour left on its convoy"
eq "$(meta "$icv" gc.execution_routed_to)" "$ROUTE" "the convoy keeps its own"
has "$out" "slung tk-g to $ROUTE through input convoy $icv" "the run says what it slung"
reset; anchor
run tk-g --target "$ROUTE" -- --on=mol-polecat-work
eq "$(work_bead_of "$(convoys)")" "tk-g" "the --on=<formula> form is a pour too"

echo "# an anchor that names no target gives its input convoy none"
reset; anchor
jq -c 'map(if .id == "tk-g" then (.metadata |= del(.target)) else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "it exits 0"
eq "$(meta "$(convoys)" target)" "<absent>" "the input convoy carries no target"

echo "# a live run of the formula on the anchor is not poured again"
# The input convoy an earlier pour made, and its root.
earlier='{"id":"tk-icv0","status":"open","title":"input convoy for tk-g","issue_type":"convoy","metadata":{"gc.synthetic":"true"}}'
reset; anchor ",$earlier,{\"id\":\"tk-r0\",\"status\":\"in_progress\",\"title\":\"mol-polecat-work\",\"metadata\":{\"gc.kind\":\"workflow\",\"gc.formula_name\":\"mol-polecat-work\",\"gc.input_convoy_id\":\"tk-icv0\"}}"
printf 'tk-icv0|tracks|tk-g\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 3 "a live run -> exit 3, as gc sling refuses one"
eq "$(slings)" "0" "nothing is slung"
eq "$(convoys)" "tk-icv0" "no second input convoy is made"
has "$out" "mol-polecat-work already runs on tk-g (root tk-r0, over input convoy tk-icv0)" "the refusal names the live run"
reset; anchor ",$earlier,{\"id\":\"tk-r0\",\"status\":\"closed\",\"title\":\"mol-polecat-work\",\"metadata\":{\"gc.kind\":\"workflow\",\"gc.formula_name\":\"mol-polecat-work\",\"gc.input_convoy_id\":\"tk-icv0\"}}"
printf 'tk-icv0|tracks|tk-g\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "a closed run is no conflict"
eq "$(slings)" "1" "it is poured again"
reset; anchor ",$earlier,{\"id\":\"tk-r0\",\"status\":\"open\",\"title\":\"mol-review\",\"metadata\":{\"gc.kind\":\"workflow\",\"gc.formula_name\":\"mol-review\",\"gc.input_convoy_id\":\"tk-icv0\"}}"
printf 'tk-icv0|tracks|tk-g\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "a live run of another formula is no conflict"
eq "$(slings)" "1" "it is poured"
reset; anchor ',{"id":"tk-own","status":"open","title":"own","issue_type":"convoy","metadata":{}},{"id":"tk-r1","status":"open","title":"mol-polecat-work","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"tk-own"}}'
printf 'tk-own|tracks|tk-g\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "a run over a convoy that is not an input convoy (no gc.synthetic) is no conflict, as gc sling counts only its own"
eq "$(slings)" "1" "it is poured"

echo "# it stops short, slinging nothing, when what it relies on does not hold"
reset; anchor
export STUB_SHOW_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "an unreadable bead -> exit 2"
eq "$(slings)" "0" "nothing slung"
has "$out" "could not read tk-g" "the run names the unreadable bead"
reset; anchor
export STUB_DEP_PARTIAL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "an unreadable set of trackers -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(convoys)" "" "no input convoy is made"
reset; anchor
export STUB_CONVOY_CREATE_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "a refused convoy create -> exit 2"
eq "$(slings)" "0" "nothing slung"
reset; anchor
export STUB_CONVOY_ADD_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "a refused track of the anchor -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(open_convoys)" "" "the convoy it made is closed again"
has "$out" "could not track tk-g" "the run names the refused track"
# The convoy about to be made already tracks another bead, so it reads back
# tracking more than the anchor: the store holds four beads, so it is new-5.
reset; anchor
printf 'new-5|tracks|tk-m1\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "an input convoy that does not read back tracking the anchor alone -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(open_convoys)" "" "the convoy it made is closed again"
has "$out" "not tk-g alone" "the run says what the convoy tracks"
reset; anchor
export STUB_UPDATE_FAIL="new-5"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "a mark that does not land -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(open_convoys)" "" "the convoy it made is closed again"

echo "# a failed sling leaves no input convoy open, unless a root names it"
reset; anchor
export STUB_SLING_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 1 "it exits with gc sling's code"
eq "$(open_convoys)" "" "the convoy no root names is closed"
eq "$(meta tk-g gc.execution_routed_to)" "<absent>" "the anchor is not stamped"
# A root that names the convoy about to be made: the store holds five beads, so
# the convoy is new-6.
reset; anchor ',{"id":"tk-r2","status":"open","title":"mol-polecat-work","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"new-6"}}'
export STUB_SLING_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 1 "it exits with gc sling's code"
eq "$(open_convoys)" "new-6" "a convoy a root names is left open"

echo "# a pour whose stamp did not land leaves the anchor unstamped"
reset; anchor
export STUB_DROP_KEYS="new-5:gc.execution_routed_to"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "the sling exited 0, so it exits 0"
eq "$(meta tk-g gc.execution_routed_to)" "<absent>" "the anchor carries no stamp the pour did not leave"
has "$out" "left no gc.execution_routed_to" "the run says so"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
