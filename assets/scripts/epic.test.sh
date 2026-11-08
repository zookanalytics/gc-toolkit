#!/usr/bin/env bash
# Hermetic test for epic.sh, the create the work skill gives for an epic. It
# execs `gctk epic create`, which files the epic with each contract field in
# its own key, refuses an epic whose parent is not an epic when it has no
# hypothesis, and files a Delivery, an epic under an epic with none, with no
# metadata.
#
# ONE IMPLEMENTATION, REACHED THROUGH THE SCRIPT. The suite builds gctk from
# this checkout and drives every case through epic.sh over the harness's stub
# store, so it holds the rule and the exec wiring together. The parse and the
# rule's wording are held in services/gctk/internal/cli/epic_test.go.
#
# Proves:
#   - a top-level epic with no hypothesis is refused (exit 3), with other
#     fields or with none, nothing is created, and the refusal names
#     --hypothesis, says a rough sentence is enough and names ordinary flow;
#   - a top-level epic with a hypothesis is filed as an epic in one create,
#     carrying each field given in its key and no other, and its id is printed;
#   - a Delivery with no hypothesis is filed under its epic with no metadata;
#   - a Delivery given a contract field is refused, and nothing is created;
#   - an epic under a task, or with a hypothesis of whitespace alone, is
#     refused;
#   - an epic under an epic with a hypothesis of its own is filed carrying it;
#   - a parent that does not read files nothing (exit 1);
#   - a create that fails, or whose reply names no bead, prints no id and says
#     to look for the epic before filing it again, with the gc bd list that
#     finds it (exit 4);
#   - with no gctk binary, the bridge refuses (exit 1) and files nothing;
#   - the work skill gives this create with the contract's floor fields, and
#     says a rough sentence is enough, which the filer writes itself and files
#     at once when the operator has stated none, and records on the epic whose
#     words each field is;
#   - the review records each field the ruling sets in its key, tests the
#     hypothesis's signal at every review, and quotes each change it proposes,
#     and the sitting's record step sends a review of an epic to it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/epic.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-epic-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
harness_init
[ -x "$SUT" ] || chmod +x "$SUT"
# harness_init has recorded why there is no binary. Every case below goes
# through it, so running them would only repeat that one failure.
if [ -z "$GCTK_BUILT" ]; then
    echo "passed: $PASS  failed: $FAIL"
    exit 1
fi

FIXTURE='[
  {"id":"tk-e","status":"open","issue_type":"epic","title":"Epic: an answered question","metadata":{"epic_hypothesis":"For the operator, X changes, and Y shows it"}},
  {"id":"tk-t","status":"open","issue_type":"task","title":"a task","metadata":{}}
]'
# run <args...>: one call through the bridge over a fresh store and log, with
# its stdout in OUT, its stderr in ERR and its exit in RC.
run() {
    store "$FIXTURE"; : > "$STUB_DEPS"; : > "$STUB_GC_LOG"
    OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?
    ERR=$(cat "$TMP/err")
}
creates() { grep '^bd create' "$STUB_GC_LOG" || true; }
ncreates() { creates | grep -c . || true; }
row() { jq -c --arg id "$1" '.[] | select(.id == $id)' "$STUB_STORE"; }

echo "# a top-level epic with no hypothesis is refused"
run create "Epic: no hypothesis" --handle "Unanswerable area" -d "about it"
eq "$RC" 3 "a top-level epic with no hypothesis exits 3"
eq "$(ncreates)" 0 "...and nothing is created"
eq "$OUT" "" "...and no id is printed"
has "$ERR" "it has no parent" "...and the refusal says why"
has "$ERR" "--hypothesis" "...and names the flag that records one"
has "$ERR" "A rough sentence that sets the general direction is enough" "...and says a rough sentence is enough"
has "$ERR" "is not an epic, and its work is ordinary flow" "...and what an area that is only ever improvable is"
run create "Epic: a title alone" -d "about it"
eq "$RC|$(ncreates)" "3|0" "a top-level epic given no field at all is refused, and nothing is created"

echo "# a top-level epic with a hypothesis is filed with its contract"
run create "Epic: answered" --hypothesis "For the operator, X changes, and Y shows it" \
    --handle "Answered epic" --boundaries "Not Z, which tk-z owns" -d "what the epic is about"
eq "$RC" 0 "a top-level epic with a hypothesis exits 0"
ID="$OUT"
[ -n "$ID" ] && [ -n "$(row "$ID")" ] && ok "...and prints the id of the bead it filed ($ID)" \
    || bad "...and prints the id of the bead it filed (got '$OUT')"
eq "$(ncreates)" 1 "...in one create"
has "$(creates)" "Epic: answered -t epic" "...as an epic"
eq "$(meta "$ID" epic_hypothesis)" "For the operator, X changes, and Y shows it" "...with its hypothesis in epic_hypothesis"
eq "$(meta "$ID" epic_handle)" "Answered epic" "...its handle in epic_handle"
eq "$(meta "$ID" epic_boundaries)" "Not Z, which tk-z owns" "...its boundaries in epic_boundaries"
eq "$(meta "$ID" epic_closure_condition)|$(meta "$ID" epic_indicators)" "<absent>|<absent>" "...and no field it was not given"
eq "$(row "$ID" | jq -r '.description')" "what the epic is about" "...and its description"
eq "$(row "$ID" | jq -r '.parent // "none"')" "none" "...under no parent"
has "$ERR" "filed $ID, an epic carrying epic_handle, epic_hypothesis, epic_boundaries" "...and says what it filed"

echo "# a Delivery with no hypothesis is filed with no metadata"
run create "Delivery: one step" --parent tk-e -d "Aim: a portion of the hypothesis
Done when: the step lands"
eq "$RC" 0 "a Delivery with no hypothesis exits 0"
ID="$OUT"
eq "$(row "$ID" | jq -r '.parent')" "tk-e" "...under its epic"
eq "$(row "$ID" | jq -c '.metadata')" "{}" "...carrying no metadata"
hasnt "$(creates)" "--metadata" "...from a create that carries none"
eq "$(row "$ID" | jq -r '.description')" "Aim: a portion of the hypothesis
Done when: the step lands" "...with its Aim: and Done when: lines"
has "$ERR" "filed $ID, a Delivery under tk-e" "...and says it filed a Delivery"

echo "# a Delivery takes no contract field"
run create "Delivery: with a handle" --parent tk-e --handle "A handle" -d "Aim: a"
eq "$RC" 3 "a Delivery given a contract field exits 3"
eq "$(ncreates)" 0 "...and nothing is created"
has "$ERR" "this is a Delivery" "...and the refusal says it is a Delivery"
has "$ERR" "but it was given --handle" "...and names the field"

echo "# an epic of its own needs a hypothesis wherever it is filed"
run create "Epic: under a task" --parent tk-t
eq "$RC" 3 "an epic under a task with no hypothesis exits 3"
has "$ERR" "its parent tk-t is a task, not an epic" "...and the refusal names the parent's type"
eq "$(ncreates)" 0 "...and nothing is created"
run create "Epic: blank" --hypothesis "   "
eq "$RC" 3 "a hypothesis of whitespace alone is no hypothesis"
eq "$(ncreates)" 0 "...and nothing is created"
run create "Epic: a child of its own" --parent tk-e --hypothesis "For whom, what changes, and its own signal"
eq "$RC" 0 "an epic under an epic with a hypothesis of its own exits 0"
ID="$OUT"
eq "$(meta "$ID" epic_hypothesis)" "For whom, what changes, and its own signal" "...carrying its hypothesis"
eq "$(row "$ID" | jq -r '.parent')" "tk-e" "...under its parent"

echo "# a parent that does not read files nothing"
run create "Delivery: lost parent" --parent tk-gone
eq "$RC" 1 "a parent the store does not hold exits 1"
has "$ERR" "tk-gone did not read" "...and says the parent did not read"
eq "$(ncreates)" 0 "...and nothing is created"
export STUB_SHOW_FAIL_ON=tk-e
run create "Delivery: unreadable parent" --parent tk-e
eq "$RC" 1 "a parent whose read fails exits 1"
eq "$(ncreates)" 0 "...and nothing is created"
unset STUB_SHOW_FAIL_ON

echo "# a create that fails or names no bead prints no id"
export STUB_CREATE_FAIL=1
run create "Epic: bd fails" --hypothesis "For the operator, X changes, and Y shows it"
eq "$RC|$OUT" "4|" "a create that exits non-zero exits 4 and prints no id"
has "$ERR" "bd's create exited 1" "...and says how the create ended"
has "$ERR" "look for it by its title before filing it again" "...and to look for the epic before filing it again"
has "$ERR" "with gc bd list -t epic --title 'Epic: bd fails'" "...with the list that finds it"
unset STUB_CREATE_FAIL
export STUB_CREATE_GARBAGE=1
run create "Epic: reply lost" --hypothesis "For the operator, X changes, and Y shows it"
eq "$RC|$OUT" "4|" "a create whose reply names no bead exits 4 and prints no id"
has "$ERR" "its reply named no bead" "...and says the reply named none"
eq "$(jq -r '[.[] | select(.title == "Epic: reply lost")] | length' "$STUB_STORE")" 1 \
    "...where the create landed, which is why it says to look before filing again"
unset STUB_CREATE_GARBAGE

echo "# usage"
run create
eq "$RC" 2 "no title exits 2"
run create "Epic: x" --hypothesis "y" --type task
eq "$RC" 2 "an argument the create does not take exits 2"
eq "$(ncreates)" 0 "...and nothing is created"
run create --help
eq "$RC" 0 "create --help exits 0"
has "$OUT" "gctk epic create <title>" "...and prints the usage"

echo "# with no binary, the bridge files nothing"
store "$FIXTURE"; : > "$STUB_GC_LOG"
GCTK_BIN=none "$SUT" create "Epic: x" --hypothesis "y" >/dev/null 2>"$TMP/err"; RC=$?
eq "$RC" 1 "GCTK_BIN=none exits 1"
has "$(cat "$TMP/err")" "no binary" "...and says there is no binary"
eq "$(ncreates)" 0 "...and nothing is created"

echo "# the skills give this create and name the keys"
# pin <file> <text> <name>: <text> sits in <file>, its line breaks read as
# spaces so a sentence that wraps still matches.
pin() {
    if grep -qF -- "$2" < <(tr '\n' ' ' < "$ROOT/$1" | tr -s ' '); then ok "$3"; else bad "$3 (no '$2' in $1)"; fi
}
pin skills/work/SKILL.md '"$(gc <binding> scripts-dir)/epic.sh" create' "the work skill files an epic through epic.sh"
for f in --hypothesis --handle --boundaries; do
    pin skills/work/SKILL.md "$f \"" "...giving $f"
done
pin skills/work/SKILL.md 'A rough sentence that sets the general direction is enough.' "...and says a rough sentence that sets the general direction is enough"
pin skills/work/SKILL.md 'When the operator has stated none, write one yourself and file at once, without asking first' "...which the filer writes itself when the operator has stated none, and files at once"
pin skills/work/SKILL.md 'quote each field you wrote and call it your proposal' "...and quotes each field it wrote as its proposal where it reports the filing"
pin skills/work/SKILL.md 'Proposed by <you>: <each field you wrote>. Stated by the operator:' "...and says on the epic whose words each field is"
pin skills/work/SKILL.md '"Epics are mortal"' "...and says an area that is only ever improvable is not an epic"
for k in epic_hypothesis epic_handle epic_boundaries epic_closure_condition epic_indicators; do
    pin skills/converse-epic-review/SKILL.md "--set-metadata $k=" "the review records $k in its key"
done
pin skills/converse-epic-review/SKILL.md 'assess the contract as it reads, whoever wrote it and whatever a past ruling said' "...judges the contract as it reads at every review"
pin skills/converse-epic-review/SKILL.md 'Could it still come out wrong once the work lands?' "...and tests its signal"
pin skills/converse-epic-review/SKILL.md 'Quote each change you propose, as your proposal' "...and its framing quotes each change it proposes"
pin skills/converse-settle/SKILL.md '`converse-epic-review` skill'"'"'s writes record it' "the settle step sends a review of an epic to the review's writes"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
