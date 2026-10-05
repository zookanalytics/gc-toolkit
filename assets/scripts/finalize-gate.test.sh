#!/usr/bin/env bash
# finalize-gate.test.sh — the composable finalize gate over the hermetic bd stub.
# Seeds visits as store beads plus a `VISIT|tracks|SUBJECT` edge and asserts the
# gate refuses (exit 1) only for an OPEN visit tracking the subject, allows
# (exit 0) otherwise, and fails closed (exit 1) on an unreadable probe.
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
# A human demand gate: the bead it holds (gc.demand_for) and the visit recorded on
# it (gc.gate_visit, the sweep's idempotence key). An empty assignee is a ruling; a
# non-empty one is a task a named person performs, which the orphan clause leaves
# alone. An empty gate_visit stands for the unset key (the sweep will offer one).
gate() { # <id> <status> <demand_for> <gate_visit> [<assignee>]
  printf '{"id":"%s","status":"%s","assignee":"%s","title":"decide %s","description":"","notes":"","issue_type":"gate","await_type":"human","metadata":{"gc.demand_for":"%s","gc.gate_visit":"%s"}}' \
    "$1" "$2" "${5:-}" "$3" "$3" "$4"
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

# ── clause no-orphan-gate: a gate whose conversation died without a decision ──
# The gate stays open and still blocks its bead, but its gc.gate_visit names a
# closed visit the sweep never re-offers. no-open-visit cannot see it (the visit
# is closed); this clause does and refuses finalize, fail-closed.

# 13. ORPHAN: open gate on A13, gc.gate_visit names a CLOSED visit -> refuse.
store "[$(work A13 open), $(gate G13 open A13 V13C), $(visit V13C closed)]"; : > "$STUB_DEPS"
out=$("$SUT" check A13 2>/dev/null); rc=$?
eq "$rc" 1 "orphan gate (gate_visit -> closed visit): exit 1"
has "$out" "G13" "orphan gate: names the gate"
has "$out" "A13" "orphan gate: names the gated bead"

# 14. LIVE gate_visit: the recorded visit is still OPEN -> no orphan (that live
# visit is no-open-visit's domain; here it does not cover A14, so the set passes).
store "[$(work A14 open), $(gate G14 open A14 V14O), $(visit V14O open)]"; : > "$STUB_DEPS"
out=$("$SUT" check A14 2>/dev/null); rc=$?
eq "$rc" 0 "gate with an open recorded visit: exit 0"

# 15. UNSET gate_visit: the sweep will offer a visit; not a dead-visit orphan.
store "[$(work A15 open), $(gate G15 open A15 "")]"; : > "$STUB_DEPS"
out=$("$SUT" check A15 2>/dev/null); rc=$?
eq "$rc" 0 "gate with no recorded visit (sweep will offer): exit 0"

# 16. SKIP sentinel: a deliberate operator suppression, not an orphan.
store "[$(work A16 open), $(gate G16 open A16 skip)]"; : > "$STUB_DEPS"
out=$("$SUT" check A16 2>/dev/null); rc=$?
eq "$rc" 0 "gate suppressed with gc.gate_visit=skip: exit 0"

# 17. ASSIGNED gate: a task a named person performs, not a ruling -> left alone.
store "[$(work A17 open), $(gate G17 open A17 V17C human/op), $(visit V17C closed)]"; : > "$STUB_DEPS"
out=$("$SUT" check A17 2>/dev/null); rc=$?
eq "$rc" 0 "assigned gate (a person's task): exit 0"

# 18. DANGLING visit: gc.gate_visit names a visit not in the store -> fail-closed
# orphan (a visit we cannot read is treated as gone).
store "[$(work A18 open), $(gate G18 open A18 V18GONE)]"; : > "$STUB_DEPS"
out=$("$SUT" check A18 2>/dev/null); rc=$?
eq "$rc" 1 "orphan gate (gate_visit -> missing visit): exit 1"
has "$out" "G18" "dangling-visit orphan: names the gate"

# 19. A gate demanding for ANOTHER bead does not hold this one.
store "[$(work A19 open), $(work OTHER19 open), $(gate G19 open OTHER19 V19C), $(visit V19C closed)]"; : > "$STUB_DEPS"
out=$("$SUT" check A19 2>/dev/null); rc=$?
eq "$rc" 0 "orphan gate on another subject: exit 0"

# 20. Fail closed: an unreadable gate listing refuses, naming this clause. Called
# directly (sourced), since a failing `gc bd list` would otherwise refuse at
# no-open-visit's own probe first.
out=$(STUB_LIST_FAIL=1 bash -c '. "$1"; clause_no_orphan_gate A20' _ "$SUT" 2>&1); rc=$?
eq "$rc" 1 "orphan-gate probe unreadable: exit 1 (fail-closed)"
has "$out" "fail-closed" "orphan-gate probe unreadable: names fail-closed"

# 12. Usage.
"$SUT" check >/dev/null 2>&1; eq "$?" 2 "check without a bead id: exit 2"
"$SUT" >/dev/null 2>&1; eq "$?" 2 "no subcommand: exit 2"
"$SUT" bogus >/dev/null 2>&1; eq "$?" 2 "unknown subcommand: exit 2"

echo "----- finalize-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
