#!/usr/bin/env bash
# finalize-gate.test.sh — the composable finalize gate over the hermetic bd stub.
# Seeds visits as store beads plus a `VISIT|tracks|SUBJECT` edge and asserts the
# gate refuses (exit 1) only for an OPEN visit tracking the subject, allows
# (exit 0) otherwise, and fails closed (exit 1) on an unreadable probe. The one
# visit --except-visit names passes only while it is open; claimed, it holds.
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
convoy() { mkbead "$1" "$2" convoy ""; }    # a tracking convoy
# A visit that names its subject by the gc.continuation_group stamp (the shared
# identity fallback) — its tracks edge, if any, is seeded separately in STUB_DEPS.
visit_cg() { # <id> <status> <continuation_group-subject>
  printf '{"id":"%s","status":"%s","assignee":"","title":"%s","description":"","notes":"","issue_type":"task","metadata":{"task_kind":"visit","gc.continuation_group":"%s"}}' \
    "$1" "$2" "$1" "$3"
}

# 1. No tracker at all -> may finalize.
store "[$(work A1 open)]"; : > "$STUB_DEPS"
out=$("$SUT" check A1 2>/dev/null); rc=$?
eq "$rc" 0 "no visit: exit 0"
eq "$out" "" "no visit: no output"

# 2. An OPEN visit tracking the subject -> refuse, naming the visit.
store "[$(work A2 open), $(visit V2 open)]"
printf 'V2|tracks|A2\n' > "$STUB_DEPS"
out=$("$SUT" check A2 2>/dev/null); rc=$?
eq "$rc" 1 "open visit: exit 1"
has "$out" "V2" "open visit: names the visit"
has "$out" "A2" "open visit: names the subject"

# 3. An in_progress visit also holds.
store "[$(work A3 open), $(visit V3 in_progress)]"
printf 'V3|tracks|A3\n' > "$STUB_DEPS"
out=$("$SUT" check A3 2>/dev/null); rc=$?
eq "$rc" 1 "in_progress visit: exit 1"

# 4. A CLOSED visit does not hold.
store "[$(work A4 open), $(visit V4 closed)]"
printf 'V4|tracks|A4\n' > "$STUB_DEPS"
out=$("$SUT" check A4 2>/dev/null); rc=$?
eq "$rc" 0 "closed visit: exit 0"

# 5. Subject-scoped: a visit tracking ANOTHER bead does not hold this one.
store "[$(work A5 open), $(work OTHER open), $(visit V5 open)]"
printf 'V5|tracks|OTHER\n' > "$STUB_DEPS"
out=$("$SUT" check A5 2>/dev/null); rc=$?
eq "$rc" 0 "visit on another subject: exit 0"

# 6. Only visits hold: an open tracking convoy on the subject does not.
store "[$(work A6 open), $(convoy CV6 open)]"
printf 'CV6|tracks|A6\n' > "$STUB_DEPS"
out=$("$SUT" check A6 2>/dev/null); rc=$?
eq "$rc" 0 "non-visit tracker: exit 0"

# 7. A blocks edge is not a tracks edge: it does not reach this gate.
store "[$(work A7 open), $(visit V7 open)]"
printf 'V7|blocks|A7\n' > "$STUB_DEPS"
out=$("$SUT" check A7 2>/dev/null); rc=$?
eq "$rc" 0 "blocks edge (not tracks): exit 0"

# 8. Fail closed: an unreadable tracker probe refuses.
store "[$(work A8 open)]"; : > "$STUB_DEPS"
out=$(STUB_DEP_GARBAGE=1 "$SUT" check A8 2>/dev/null); rc=$?
eq "$rc" 1 "unreadable probe: exit 1 (fail-closed)"
has "$out" "fail-closed" "unreadable probe: names fail-closed"

# 9. gc.continuation_group fallback: a visit stamped with the subject but whose
# tracks edge has not landed still holds — the reachable escalate.sh partial write.
store "[$(work A9 open), $(visit_cg V9 open A9)]"; : > "$STUB_DEPS"
out=$("$SUT" check A9 2>/dev/null); rc=$?
eq "$rc" 1 "stamp-only visit (no tracks edge): exit 1"
has "$out" "V9" "stamp-only visit: names the visit"
has "$out" "A9" "stamp-only visit: names the subject"

# 10. A stamped visit that DID land its tracks edge is held by the edge (probe 1),
# not double-counted by the fallback.
store "[$(work A10 open), $(visit_cg V10 open A10)]"
printf 'V10|tracks|A10\n' > "$STUB_DEPS"
out=$("$SUT" check A10 2>/dev/null); rc=$?
eq "$rc" 1 "stamped visit with tracks edge: exit 1"
has "$out" "V10" "stamped visit with tracks edge: names the visit"

# 11. The stamp is the fallback ONLY for an empty edge: a visit stamped with this
# subject but whose tracks edge points at ANOTHER bead covers that other bead, so
# it does not hold this one (matches visit-identity.sh, no over-hold).
store "[$(work A11 open), $(work OTHER11 open), $(visit_cg V11 open A11)]"
printf 'V11|tracks|OTHER11\n' > "$STUB_DEPS"
out=$("$SUT" check A11 2>/dev/null); rc=$?
eq "$rc" 0 "stamp here but tracks edge elsewhere: exit 0"

# 12. Usage.
"$SUT" check >/dev/null 2>&1; eq "$?" 2 "check without a bead id: exit 2"
"$SUT" >/dev/null 2>&1; eq "$?" 2 "no subcommand: exit 2"
"$SUT" bogus >/dev/null 2>&1; eq "$?" 2 "unknown subcommand: exit 2"

# 13. --except-visit: the visit a caller filed to report its own refused
# finalization does not hold the retry it asks for, while it is open.
store "[$(work A13 open), $(visit V13 open)]"
printf 'V13|tracks|A13\n' > "$STUB_DEPS"
out=$("$SUT" check A13 --except-visit V13 2>/dev/null); rc=$?
eq "$rc" 0 "excepted open visit: exit 0"
eq "$out" "" "excepted open visit: no output"

# 14. Claimed, the excepted visit holds like any other: a person is in it.
store "[$(work A14 open), $(visit V14 in_progress)]"
printf 'V14|tracks|A14\n' > "$STUB_DEPS"
out=$("$SUT" check A14 --except-visit V14 2>/dev/null); rc=$?
eq "$rc" 1 "excepted visit claimed (in_progress): exit 1"
has "$out" "V14" "excepted visit claimed: names the visit"

# 15. The exception names one visit: another open visit still holds.
store "[$(work A15 open), $(visit V15 open), $(visit W15 open)]"
printf 'V15|tracks|A15\nW15|tracks|A15\n' > "$STUB_DEPS"
out=$("$SUT" check A15 --except-visit V15 2>/dev/null); rc=$?
eq "$rc" 1 "another open visit beside the excepted one: exit 1"
has "$out" "W15" "another open visit beside the excepted one: names it"

# 16. The exception reaches the gc.continuation_group fallback too, and there
# also excepts only the visit it names.
store "[$(work A16 open), $(visit_cg V16 open A16)]"; : > "$STUB_DEPS"
out=$("$SUT" check A16 --except-visit V16 2>/dev/null); rc=$?
eq "$rc" 0 "excepted stamp-only visit: exit 0"
store "[$(work A16b open), $(visit_cg V16b open A16b), $(visit_cg W16b open A16b)]"; : > "$STUB_DEPS"
out=$("$SUT" check A16b --except-visit V16b 2>/dev/null); rc=$?
eq "$rc" 1 "another stamp-only visit beside the excepted one: exit 1"
has "$out" "W16b" "another stamp-only visit beside the excepted one: names it"

# 17. Usage of the option.
"$SUT" check A1 --except-visit >/dev/null 2>&1; eq "$?" 2 "--except-visit without a visit id: exit 2"
"$SUT" check A1 --bogus >/dev/null 2>&1; eq "$?" 2 "unknown option: exit 2"
"$SUT" check --except-visit V1 >/dev/null 2>&1; eq "$?" 2 "an option in place of the bead id: exit 2"

echo "----- finalize-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
