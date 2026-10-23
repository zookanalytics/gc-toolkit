#!/usr/bin/env bash
# finalize-gate.test.sh — the composable finalize gate over the hermetic bd stub.
# Seeds human gates as store beads (issue_type gate, await_type human, the
# situation key as await_id) plus a `GATE|blocks|SUBJECT` edge, and asserts the
# gate refuses (exit 1) only for an open human gate that blocks the subject or a
# stewarded epic not ruled closed, allows (exit 0) otherwise, and fails closed
# (exit 1) on an unreadable probe. A gate filed under the --except-key situation
# passes only while no person is assigned it.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/finalize-gate-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"; harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/finalize-gate.sh"
SUT="$SD/finalize-gate.sh"

# A bead in the store: id, status, issue_type, and metadata task_kind.
mkbead() { # <id> <status> <issue_type> <task_kind>
  printf '{"id":"%s","status":"%s","assignee":"","title":"%s","description":"","notes":"","issue_type":"%s","metadata":{"task_kind":"%s"}}' \
    "$1" "$2" "$1" "$3" "$4"
}
work()  { mkbead "$1" "$2" task ""; }       # a plain work bead
visit() { mkbead "$1" "$2" task visit; }    # a visit bead
# A human gate: its situation key is its await id, and its assignee is the one
# person who must clear it, empty while the operator owes it.
hgate() { # <id> <status> <await_id> [<assignee>]
  printf '{"id":"%s","status":"%s","assignee":"%s","title":"clear %s","description":"","notes":"","issue_type":"gate","await_type":"human","await_id":"%s","metadata":{}}' \
    "$1" "$2" "${4:-}" "$1" "$3"
}
# A gate of another await type, or of none (park's gate declares none).
ogate() { # <id> <status> <await_type>
  printf '{"id":"%s","status":"%s","assignee":"","title":"%s","description":"","notes":"","issue_type":"gate","await_type":"%s","metadata":{}}' \
    "$1" "$2" "$1" "$3"
}
# An epic bead carrying arbitrary metadata.
epic_bead() { # <id> <status> <metadata-json>
  printf '{"id":"%s","status":"%s","assignee":"","title":"%s","description":"","notes":"","issue_type":"epic","metadata":%s}' \
    "$1" "$2" "$1" "$3"
}

# 1. No gate at all -> may finalize.
store "[$(work A1 open)]"; : > "$STUB_DEPS"
out=$("$SUT" check A1 2>/dev/null); rc=$?
eq "$rc" 0 "no gate: exit 0"
eq "$out" "" "no gate: no output"

# 2. An open human gate blocking the subject -> refuse, naming the gate, its
# title and the subject.
store "[$(work A2 open), $(hgate G2 open some-question)]"
printf 'G2|blocks|A2\n' > "$STUB_DEPS"
out=$("$SUT" check A2 2>/dev/null); rc=$?
eq "$rc" 1 "open human gate: exit 1"
has "$out" "G2" "open human gate: names the gate"
has "$out" "clear G2" "open human gate: names what the person must clear"
has "$out" "A2" "open human gate: names the subject"

# 3. A gate in any status but closed is open.
store "[$(work A3 open), $(hgate G3 in_progress some-question)]"
printf 'G3|blocks|A3\n' > "$STUB_DEPS"
out=$("$SUT" check A3 2>/dev/null); rc=$?
eq "$rc" 1 "in_progress human gate: exit 1"

# 4. A CLOSED gate does not hold.
store "[$(work A4 open), $(hgate G4 closed some-question)]"
printf 'G4|blocks|A4\n' > "$STUB_DEPS"
out=$("$SUT" check A4 2>/dev/null); rc=$?
eq "$rc" 0 "closed human gate: exit 0"

# 5. Bead-scoped: a gate blocking ANOTHER bead does not hold this one.
store "[$(work A5 open), $(work OTHER open), $(hgate G5 open some-question)]"
printf 'G5|blocks|OTHER\n' > "$STUB_DEPS"
out=$("$SUT" check A5 2>/dev/null); rc=$?
eq "$rc" 0 "gate on another bead: exit 0"

# 5b. A gate that blocks two beads holds each of them.
store "[$(work A5b open), $(work B5b open), $(hgate G5b open shared-question)]"
printf 'G5b|blocks|A5b\nG5b|blocks|B5b\n' > "$STUB_DEPS"
out=$("$SUT" check A5b 2>/dev/null); rc=$?
eq "$rc" 1 "a gate about two beads holds the first"
out=$("$SUT" check B5b 2>/dev/null); rc=$?
eq "$rc" 1 "a gate about two beads holds the second"

# 6. Only human gates count. An open gate of another await type, or of none, and
# an open work blocker hold nothing here: bd's own close refuses on them, and
# this clause states only what a person owes.
store "[$(work A6 open), $(ogate P6 open ""), $(ogate T6 open timer), $(work W6 open)]"
printf 'P6|blocks|A6\nT6|blocks|A6\nW6|blocks|A6\n' > "$STUB_DEPS"
out=$("$SUT" check A6 2>/dev/null); rc=$?
eq "$rc" 0 "non-human blockers: exit 0"

# 7. A tracks edge holds nothing: a conversation, or a visit, that tracks the
# bead blocks nothing, and neither does a tracks edge from a human gate.
store "[$(work A7 open), $(visit V7 open), $(hgate G7 open some-question)]"
printf 'V7|tracks|A7\nG7|tracks|A7\n' > "$STUB_DEPS"
out=$("$SUT" check A7 2>/dev/null); rc=$?
eq "$rc" 0 "tracks edges only: exit 0"

# 8. Fail closed: an unreadable gate probe refuses, whether it answers bytes that
# are not JSON or fails after printing an empty array.
store "[$(work A8 open)]"; : > "$STUB_DEPS"
out=$(STUB_DEP_GARBAGE=1 "$SUT" check A8 2>/dev/null); rc=$?
eq "$rc" 1 "unreadable probe: exit 1 (fail-closed)"
has "$out" "fail-closed" "unreadable probe: names fail-closed"
out=$(STUB_DEP_PARTIAL=1 "$SUT" check A8 2>/dev/null); rc=$?
eq "$rc" 1 "a probe that fails after printing []: exit 1 (fail-closed)"
out=$("$SUT" check NOSUCH 2>/dev/null); rc=$?
eq "$rc" 1 "a bead the store cannot find: exit 1 (fail-closed)"

# 12. Usage.
"$SUT" check >/dev/null 2>&1; eq "$?" 2 "check without a bead id: exit 2"
"$SUT" >/dev/null 2>&1; eq "$?" 2 "no subcommand: exit 2"
"$SUT" bogus >/dev/null 2>&1; eq "$?" 2 "unknown subcommand: exit 2"

# 13. --except-key: the caller's own report of a refused finalization, filed
# under that key, does not hold the retry it asks for while no person is
# assigned it.
store "[$(work A13 open), $(hgate G13 open dispose-failed.13)]"
printf 'G13|blocks|A13\n' > "$STUB_DEPS"
out=$("$SUT" check A13 --except-key dispose-failed.13 2>/dev/null); rc=$?
eq "$rc" 0 "excepted unassigned gate: exit 0"
eq "$out" "" "excepted unassigned gate: no output"
out=$("$SUT" check A13 2>/dev/null); rc=$?
eq "$rc" 1 "the same gate with no exception named: exit 1"

# 14. Assigned to a person, the excepted gate holds like any other: that person
# must clear it.
store "[$(work A14 open), $(hgate G14 open dispose-failed.14 operator)]"
printf 'G14|blocks|A14\n' > "$STUB_DEPS"
out=$("$SUT" check A14 --except-key dispose-failed.14 2>/dev/null); rc=$?
eq "$rc" 1 "excepted gate assigned to a person: exit 1"
has "$out" "G14" "excepted gate assigned to a person: names the gate"

# 15. The key names one situation: a gate under another key still holds. Twins
# under the key are excepted alike.
store "[$(work A15 open), $(hgate G15 open dispose-failed.15), $(hgate W15 open another-question)]"
printf 'G15|blocks|A15\nW15|blocks|A15\n' > "$STUB_DEPS"
out=$("$SUT" check A15 --except-key dispose-failed.15 2>/dev/null); rc=$?
eq "$rc" 1 "a gate under another key beside the excepted one: exit 1"
has "$out" "W15" "a gate under another key beside the excepted one: names it"
store "[$(work A15t open), $(hgate G15t open dispose-failed.15), $(hgate T15t open dispose-failed.15)]"
printf 'G15t|blocks|A15t\nT15t|blocks|A15t\n' > "$STUB_DEPS"
out=$("$SUT" check A15t --except-key dispose-failed.15 2>/dev/null); rc=$?
eq "$rc" 0 "twin gates under the excepted key: exit 0"

# 17. Usage of the option.
"$SUT" check A1 --except-key >/dev/null 2>&1; eq "$?" 2 "--except-key without a key: exit 2"
"$SUT" check A1 --except-key 'bad key' >/dev/null 2>&1; eq "$?" 2 "--except-key outside human-gate.sh's key charset: exit 2"
"$SUT" check A1 --except-visit V1 >/dev/null 2>&1; eq "$?" 2 "an unknown option: exit 2"
"$SUT" check --except-key k1 >/dev/null 2>&1; eq "$?" 2 "an option in place of the bead id: exit 2"

# 18. clause_epic_ruling_recorded: a STEWARDED epic (has a hypothesis) with no
# recorded ruling is held.
store "[$(epic_bead E1 open '{"epic_hypothesis":"h"}')]"; : > "$STUB_DEPS"
out=$("$SUT" check E1 2>/dev/null); rc=$?
eq "$rc" 1 "stewarded epic without a ruling: exit 1"
has "$out" "epic_ruling" "unruled epic: names the missing ruling"
has "$out" "E1" "unruled epic: names the epic"

# 19. An epic ruled close, its outcome recorded, may finalize.
store "[$(epic_bead E2 open '{"epic_hypothesis":"h","epic_ruling":"close","epic_ruling_reason":"held: the signal moved"}')]"; : > "$STUB_DEPS"
out=$("$SUT" check E2 2>/dev/null); rc=$?
eq "$rc" 0 "epic ruled close with its outcome: exit 0"

# 19a. A close ruling carries its outcome: one recorded without epic_ruling_reason,
# or with a reason of whitespace alone, holds and names the missing field.
store "[$(epic_bead E2nr open '{"epic_hypothesis":"h","epic_ruling":"close"}')]"; : > "$STUB_DEPS"
out=$("$SUT" check E2nr 2>/dev/null); rc=$?
eq "$rc" 1 "epic ruled close without its outcome: exit 1"
has "$out" "epic_ruling_reason" "the close-without-outcome hold names the missing field"
store "[$(epic_bead E2ws open '{"epic_hypothesis":"h","epic_ruling":"close","epic_ruling_reason":"  "}')]"; : > "$STUB_DEPS"
out=$("$SUT" check E2ws 2>/dev/null); rc=$?
eq "$rc" 1 "a whitespace-only epic_ruling_reason is no outcome: exit 1"

# 19b. continue and shift are rulings, but not terminal ones: each keeps the epic
# open, so the gate holds it as it holds an unruled one, naming the ruling.
for r in continue shift; do
  store "[$(epic_bead "E2$r" open "{\"epic_hypothesis\":\"h\",\"epic_ruling\":\"$r\"}")]"; : > "$STUB_DEPS"
  out=$("$SUT" check "E2$r" 2>/dev/null); rc=$?
  eq "$rc" 1 "epic ruled $r (non-terminal): exit 1"
  has "$out" "non-terminal ruling '$r'" "the $r hold names the non-terminal ruling"
  has "$out" "close ruling" "the $r hold names the ruling that releases it"
done

# 20. An empty epic_ruling is not a ruling.
store "[$(epic_bead E3 open '{"epic_hypothesis":"h","epic_ruling":""}')]"; : > "$STUB_DEPS"
out=$("$SUT" check E3 2>/dev/null); rc=$?
eq "$rc" 1 "epic with an empty ruling: exit 1"

# 20b. A present-but-off-enum ruling ("pending", a typo) is not a ruling either —
# the enum is continue|shift|close (docs/epics.md), so the gate still holds and
# an epic cannot close "ruled" on a value that is not a ruling.
store "[$(epic_bead E3off open '{"epic_hypothesis":"h","epic_ruling":"pending"}')]"; : > "$STUB_DEPS"
out=$("$SUT" check E3off 2>/dev/null); rc=$?
eq "$rc" 1 "epic with an off-enum ruling ('pending'): exit 1"
has "$out" "continue/shift/close" "the refusal names the allowed ruling set"

# 21. A pre-stewardship epic (no hypothesis) is exempt — it predates the model.
store "[$(epic_bead E3b open '{}')]"; : > "$STUB_DEPS"
out=$("$SUT" check E3b 2>/dev/null); rc=$?
eq "$rc" 0 "an epic with no hypothesis is not held by the ruling clause: exit 0"

# 22. A disposed epic (gc.superseded_by) is exempt — a recorded terminal reason.
store "[$(epic_bead E3c open '{"epic_hypothesis":"h","gc.superseded_by":"s-1"}')]"; : > "$STUB_DEPS"
out=$("$SUT" check E3c 2>/dev/null); rc=$?
eq "$rc" 0 "a disposed epic is not held by the ruling clause: exit 0"

# 23. The clause is epic-only: a plain work bead with no ruling may finalize.
store "[$(work W1 open)]"; : > "$STUB_DEPS"
out=$("$SUT" check W1 2>/dev/null); rc=$?
eq "$rc" 0 "non-epic bead is untouched by the epic-ruling clause: exit 0"

# 24. The clauses are independent: an open human gate still holds a ruled epic.
store "[$(epic_bead E4 open '{"epic_hypothesis":"h","epic_ruling":"close","epic_ruling_reason":"held"}'), $(hgate GE4 open some-question)]"
printf 'GE4|blocks|E4\n' > "$STUB_DEPS"
out=$("$SUT" check E4 2>/dev/null); rc=$?
eq "$rc" 1 "a ruled epic under an open human gate is still held by the gate clause"
has "$out" "GE4" "the gate clause names the gate, first refusal stops the set"

# 25. A `gc bd:` notice line leading the probe's stdout must not break it: the
# gate strips it like bead-context.sh. This probe runs for EVERY finalize, so
# without the strip one notice line would error jq and fail every merge/close in
# the rig closed — epics and plain work beads alike.
store "[$(epic_bead EN open '{"epic_hypothesis":"h","epic_ruling":"close","epic_ruling_reason":"held"}')]"; : > "$STUB_DEPS"
out=$(STUB_SHOW_NOTICE=alpha "$SUT" check EN 2>/dev/null); rc=$?
eq "$rc" 0 "epic ruled close behind a gc bd: notice on stdout: exit 0 (notice stripped, not failed-closed)"
store "[$(epic_bead EM open '{"epic_hypothesis":"h"}')]"; : > "$STUB_DEPS"
out=$(STUB_SHOW_NOTICE=alpha "$SUT" check EM 2>/dev/null); rc=$?
eq "$rc" 1 "unruled epic behind a gc bd: notice: still held"
has "$out" "no valid epic_ruling" "the hold is the real refusal, not a probe-unreadable error"

# 26. Every check reads the store as it stands, even inside a refinery pass that
# memoizes bd_list (GC_RECONCILE_BD_CACHE). merge.sh re-asserts the gate in the
# terminal window to catch a gate filed after its first check; here the gate
# lands between the two checks.
mkdir -p "$TMP/bd-cache"
store "[$(work A26 open)]"; : > "$STUB_DEPS"
out=$(GC_RECONCILE_BD_CACHE="$TMP/bd-cache" "$SUT" check A26 2>/dev/null); rc=$?
eq "$rc" 0 "first check under a pass cache, no gate yet: exit 0"
store "[$(work A26 open), $(hgate G26 open late-question)]"
printf 'G26|blocks|A26\n' > "$STUB_DEPS"
out=$(GC_RECONCILE_BD_CACHE="$TMP/bd-cache" "$SUT" check A26 2>/dev/null); rc=$?
eq "$rc" 1 "re-assert under the same pass cache sees the gate filed since: exit 1"
has "$out" "G26" "the re-assert names the gate the cache would have hidden"

# 27. --except-key excepts a gate, so it reaches the human-gate clause only. A
# stewarded epic whose one gate is excepted is still held until it is ruled
# close with its outcome, and passes once it is.
store "[$(epic_bead E27 open '{"epic_hypothesis":"h"}'), $(hgate G27 open dispose-failed.27)]"
printf 'G27|blocks|E27\n' > "$STUB_DEPS"
out=$("$SUT" check E27 --except-key dispose-failed.27 2>/dev/null); rc=$?
eq "$rc" 1 "an unruled epic whose only gate is excepted: exit 1"
has "$out" "no valid epic_ruling" "the hold is the ruling clause's, not the excepted gate's"
store "[$(epic_bead E27r open '{"epic_hypothesis":"h","epic_ruling":"close","epic_ruling_reason":"held"}'), $(hgate G27r open dispose-failed.27)]"
printf 'G27r|blocks|E27r\n' > "$STUB_DEPS"
out=$("$SUT" check E27r --except-key dispose-failed.27 2>/dev/null); rc=$?
eq "$rc" 0 "an epic ruled close with its outcome whose only gate is excepted: exit 0"

echo "----- finalize-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
