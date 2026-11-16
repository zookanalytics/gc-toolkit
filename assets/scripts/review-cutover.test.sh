#!/usr/bin/env bash
# Hermetic test for assets/scripts/review-cutover.sh, which closes the old review
# path's scaffolding on a bead a rig's cutover has moved onto the pending
# record. Covers: each kind it closes (a review bead, open or claimed, a
# validation pass, a machine finding unruled or put to a person), with the
# close's shape (status closed, gc.outcome=superseded, gc.work_outcome=no-op,
# the note appended); each kind it leaves (a human finding, an open rework
# child, a bead of another kind, a closed child, another bead's child); a
# machine finding an open rework child of the bead still blocks, left for
# close-answered, and one something else holds, which a person decides; the
# refusal of a bead the old path still reads; the bead's own store, named by
# its prefix; a re-run; and a store that does not answer.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-cutover-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/review-cutover.sh" "$HERE/bead-store.sh" "$HERE/rig-map.sh"
SUT="$SD/review-cutover.sh"

# The rig list bead-store.sh resolves a prefix through: the tk prefix is the rig
# at $TMP/rig, unless STUB_RIG_LIST_FAIL makes the listing fail.
RIG="$TMP/rig"; mkdir -p "$RIG/.beads"
mv "$BIN/gc" "$BIN/gc-fixture"
{ _stub_shebang; cat <<GC
if [ "\${1:-} \${2:-}" = "rig list" ]; then
  [ -z "\${STUB_RIG_LIST_FAIL:-}" ] || { echo "gc: simulated rig list failure" >&2; exit 1; }
  printf '{"rigs":[{"name":"gc-toolkit","prefix":"tk","path":"%s"}]}\n' "$RIG"
  exit 0
fi
exec "$BIN/gc-fixture" "\$@"
GC
} > "$BIN/gc"
chmod +x "$BIN/gc"

run() { "$SUT" "$@" 2>&1; }

# child <id> <anchor> <kind> [status] [extra metadata, comma-prefixed]
child() {
  printf '{"id":"%s","status":"%s","assignee":"","notes":"dispatch note","title":"%s on %s","metadata":{"task_kind":"%s","anchor_bead":"%s"%s}}' \
    "$1" "${4:-open}" "$3" "$2" "$3" "$2" "${5:-}"
}
# bead <id> [merge_result]
bead() {
  printf '{"id":"%s","status":"%s","assignee":"","notes":"","title":"work %s","metadata":{%s}}' \
    "$1" "${3:-open}" "$1" "${2:+\"merge_result\":\"$2\"}"
}
MACHINE=',"finding.source":"machine:correctness","finding.disposition":"unvalidated"'
MACHINE_NY=',"finding.source":"machine:arch","finding.disposition":"needs-you"'
MACHINE_MF=',"finding.source":"machine:correctness","finding.disposition":"must-fix"'
HUMAN=',"finding.source":"human:operator","finding.disposition":"unvalidated"'

echo "# each kind it closes, on a bead the cutover moved to pull_request_head_changed"
store "[$(bead tk-a pull_request_head_changed),$(child tk-r1 tk-a review),$(child tk-r2 tk-a review in_progress),$(child tk-v1 tk-a validation),$(child tk-f1 tk-a finding open "$MACHINE"),$(child tk-f2 tk-a finding open "$MACHINE_NY")]"
out=$(run --bead tk-a); rc=$?
eq "$rc" 0 "a cutover that closes every piece of scaffolding exits 0"
for b in tk-r1 tk-r2 tk-v1 tk-f1 tk-f2; do
  eq "$(bstatus $b)" "closed" "$b is closed"
  eq "$(meta $b gc.outcome)" "superseded" "…as superseded"
  eq "$(meta $b gc.work_outcome)" "no-op" "…with the work record the runtime's close gate reads"
done
has "$(notes tk-r1)" "dispatch note" "the dispatch note survives (notes are appended)"
has "$(notes tk-r1)" "Superseded at the rig's cutover" "…and the note says why it closed"
has "$(notes tk-r1)" "tk-a moved onto the pending-through-merge record" "…naming the bead that moved"
has "$out" "closed tk-r1 (review bead, superseded)" "the output names a review bead it closed"
has "$out" "closed tk-r2 (review bead, superseded)" "…a claimed review bead too, whose verdict signoff.sh then refuses"
has "$out" "closed tk-v1 (validation pass, superseded)" "…a validation pass"
has "$out" "closed tk-f1 (machine finding, superseded)" "…an unruled machine finding"
has "$out" "closed tk-f2 (machine finding, superseded)" "…and one put to a person, whose gate stays open on the bead"
has "$out" "tk-a: closed 5, left 0" "…and counts what it closed"
eq "$(bstatus tk-a)" "open" "the bead itself is untouched"
has "$(cat "$STUB_GC_LOG")" "bd --db $RIG/.beads update tk-r1" "every write goes to the store the bead's prefix names"
has "$(cat "$STUB_GC_LOG")" "bd --db $RIG/.beads list" "…and so does the read of its children"

echo "# each kind it leaves"
store "[$(bead tk-b pull_request_pending),$(child tk-h1 tk-b finding open "$HUMAN"),$(child tk-w1 tk-b rework in_progress),$(child tk-x1 tk-b visit),$(child tk-r3 tk-b review closed),$(child tk-r4 tk-other review),$(child tk-r5 tk-b review)]"
out=$(run --bead tk-b); rc=$?
eq "$rc" 0 "leaving what the run rules and what finishes as today is no failure"
eq "$(bstatus tk-h1)" "open" "a human finding is left for the review run to rule"
has "$out" "left tk-h1 (human finding; the review run rules it)" "…and the output says so"
eq "$(bstatus tk-w1)" "in_progress" "an open rework child is left to finish on the branch"
has "$out" "left tk-w1 (open rework child" "…and the output says so"
eq "$(bstatus tk-x1)" "open" "a bead of another kind is no review scaffolding, and is left"
has "$out" "left tk-x1 (a visit bead, which is no review scaffolding)" "…and the output names its kind"
eq "$(meta tk-r3 gc.outcome)" "<absent>" "a closed review bead is not written again"
eq "$(bstatus tk-r4)" "open" "a review bead on another bead is not this bead's"
eq "$(bstatus tk-r5)" "closed" "the bead's own open review bead beside them is closed"
has "$out" "tk-b: closed 1, left 3" "…and the count names both"

echo "# a machine finding an open rework child of the bead still blocks"
store "[$(bead tk-c pull_request_head_changed),$(child tk-f3 tk-c finding open "$MACHINE_MF"),$(child tk-w2 tk-c rework),$(child tk-r6 tk-c review)]"
printf 'tk-w2|blocks|tk-f3\ntk-w2|blocks|tk-c\ntk-f3|blocks|tk-c\n' > "$STUB_DEPS"
out=$(STUB_ENFORCE_BLOCKS=1 run --bead tk-c); rc=$?
eq "$rc" 0 "a finding its fix unit still holds is left with no failure"
eq "$(bstatus tk-f3)" "open" "bd refuses that close, so the finding stays open"
eq "$(meta tk-f3 gc.outcome)" "<absent>" "…with nothing of the refused write landed"
has "$out" "left tk-f3 (machine finding held by open rework child tk-w2; finding.sh close-answered closes it once that child lands)" "…and the output says what closes it"
eq "$(bstatus tk-r6)" "closed" "the review bead beside it still closes"
has "$out" "tk-c: closed 1, left 2" "…and the count holds the finding among what it left"
: > "$STUB_DEPS"

echo "# a close something other than an open rework child holds"
store "[$(bead tk-d pull_request_head_changed),$(child tk-f4 tk-d finding open "$MACHINE_MF"),$(bead tk-elsewhere),$(child tk-r7 tk-d review)]"
printf 'tk-elsewhere|blocks|tk-f4\n' > "$STUB_DEPS"
out=$(STUB_ENFORCE_BLOCKS=1 run --bead tk-d); rc=$?
eq "$rc" 1 "a hold the cutover cannot name the end of exits 1"
eq "$(bstatus tk-f4)" "open" "…and the finding stays open"
has "$out" "tk-f4 (machine finding) is held by tk-elsewhere; bd refuses its close, so a person decides what releases it" "…naming what holds it"
eq "$(bstatus tk-r7)" "closed" "…while the rest still closes"
: > "$STUB_DEPS"

echo "# a bead the old path still reads is refused"
for mr in pull_request pre_open_gate; do
  store "[$(bead tk-e "$mr"),$(child tk-r8 tk-e review),$(child tk-f5 tk-e finding open "$MACHINE")]"
  out=$(run --bead tk-e); rc=$?
  eq "$rc" 1 "merge_result=$mr is refused"
  has "$out" "tk-e is at merge_result=$mr" "…and the refusal names the record"
  has "$out" "Move it onto the record first; nothing closed" "…and says to move it first"
  eq "$(bstatus tk-r8)" "open" "…and its review bead stays open, so gate-ensure.sh files nothing again"
  eq "$(bstatus tk-f5)" "open" "…and so does its finding"
done

echo "# a bead with no record, moved to the refinery from pre_open_gate"
store "[$(bead tk-g),$(child tk-r9 tk-g review)]"
out=$(run --bead tk-g); rc=$?
eq "$rc" 0 "a bead with no record is taken"
eq "$(bstatus tk-r9)" "closed" "…and its review bead closes"

echo "# a re-run closes nothing more"
out=$(run --bead tk-g); rc=$?
eq "$rc" 0 "a re-run exits 0"
has "$out" "tk-g: closed 0, left 0" "…and closes nothing"

echo "# a bead the store does not hold, or no rig carries"
store "[$(bead tk-h)]"
out=$(run --bead tk-missing); rc=$?
eq "$rc" 1 "a bead its store does not hold is refused"
has "$out" "holds no bead tk-missing" "…and the refusal says so"
out=$(run --bead zz-nope); rc=$?
eq "$rc" 1 "a prefix no rig carries is refused"
has "$out" "no rig's store carries zz-nope" "…and the refusal says so"

echo "# a store that does not answer"
store "[$(bead tk-i pull_request_head_changed),$(child tk-r10 tk-i review)]"
out=$(STUB_RIG_LIST_FAIL=1 run --bead tk-i); rc=$?
eq "$rc" 3 "a rig list that does not read exits 3"
has "$out" "the store for tk-i did not resolve" "…and says so"
out=$(STUB_SHOW_FAIL=1 run --bead tk-i); rc=$?
eq "$rc" 3 "a bead that does not read exits 3"
has "$out" "tk-i did not read from" "…and says so"
out=$(STUB_LIST_FAIL=1 run --bead tk-i); rc=$?
eq "$rc" 3 "children that do not read exit 3"
has "$out" "the beads anchored on tk-i did not read; nothing closed" "…and say so"
eq "$(bstatus tk-r10)" "open" "…and nothing is closed on a partial read"
out=$(STUB_UPDATE_FAIL=tk-r10 run --bead tk-i); rc=$?
eq "$rc" 3 "a close the store refuses with nothing holding it exits 3"
has "$out" "tk-r10 (review bead) did not close, with nothing holding it; run it again" "…and asks for a re-run"
for knob in STUB_DEP_PARTIAL STUB_DEP_GARBAGE; do
  out=$(env "$knob=--direction=down" STUB_UPDATE_FAIL=tk-r10 "$SUT" --bead tk-i 2>&1); rc=$?
  eq "$rc" 3 "a refused close whose blockers do not read exits 3 ($knob)"
  has "$out" "tk-r10 (review bead) did not close, and its blockers did not read; run it again" "…and does not read the failure as nothing holding it"
done
out=$(run --bead tk-i); rc=$?
eq "$rc" 0 "the re-run closes it"
eq "$(bstatus tk-r10)" "closed" "…and the review bead is closed"

echo "# usage"
out=$(run); rc=$?
eq "$rc" 2 "no --bead is a usage error"
out=$(run --bead); rc=$?
eq "$rc" 2 "--bead with no value is a usage error"
out=$(run --bead tk-a --extra); rc=$?
eq "$rc" 2 "an unknown argument is a usage error"
has "$out" "unknown argument '--extra'" "…named as such"
out=$(run --help); rc=$?
eq "$rc" 0 "--help exits 0"
has "$out" "usage: review-cutover --bead <bead>" "…and prints the usage"

echo
echo "review-cutover.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
