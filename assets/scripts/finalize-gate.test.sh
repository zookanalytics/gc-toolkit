#!/usr/bin/env bash
# finalize-gate.test.sh — the composable finalize gate over the hermetic bd stub.
# Seeds visits as store beads plus a `VISIT|tracks|SUBJECT` edge and asserts the
# gate refuses (exit 1) only for an OPEN visit tracking the subject, allows
# (exit 0) otherwise, and fails closed (exit 1) on an unreadable probe. A visit
# filed under the --except-key situation for this bead passes only while nobody is
# engaged in it; claimed, or bound by assignee or session, it holds.
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
# A visit escalate.sh filed: its situation key and subject stamp, plus who is
# engaged in it (an assignee and a bound session, each empty for nobody).
evisit() { # <id> <status> <subject> <escalation_key> [<assignee>] [<gc.session_name>]
  printf '{"id":"%s","status":"%s","assignee":"%s","title":"%s","description":"","notes":"","issue_type":"task","metadata":{"task_kind":"visit","gc.continuation_group":"%s","escalation_key":"%s"%s}}' \
    "$1" "$2" "${5:-}" "$1" "$3" "$4" "${6:+,\"gc.session_name\":\"$6\"}"
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

# 12. Usage.
"$SUT" check >/dev/null 2>&1; eq "$?" 2 "check without a bead id: exit 2"
"$SUT" >/dev/null 2>&1; eq "$?" 2 "no subcommand: exit 2"
"$SUT" bogus >/dev/null 2>&1; eq "$?" 2 "unknown subcommand: exit 2"

# 13. --except-key: the caller's own report of a refused finalization, filed
# under that key for this bead, does not hold the retry it asks for while nobody
# is engaged in it.
store "[$(work A13 open), $(evisit V13 open A13 dispose-failed.13)]"
printf 'V13|tracks|A13\n' > "$STUB_DEPS"
out=$("$SUT" check A13 --except-key dispose-failed.13 2>/dev/null); rc=$?
eq "$rc" 0 "excepted unengaged visit: exit 0"
eq "$out" "" "excepted unengaged visit: no output"
out=$("$SUT" check A13 2>/dev/null); rc=$?
eq "$rc" 1 "the same visit with no exception named: exit 1"

# 14. Engaged, the excepted visit holds like any other: a person is in it. The
# board counts a visit engaged once it is claimed, and also while it is still
# open but bound by assignee or session (engage binds before the claim).
store "[$(work A14 open), $(evisit V14 in_progress A14 dispose-failed.14 lx-sitting)]"
printf 'V14|tracks|A14\n' > "$STUB_DEPS"
out=$("$SUT" check A14 --except-key dispose-failed.14 2>/dev/null); rc=$?
eq "$rc" 1 "excepted visit claimed (in_progress): exit 1"
has "$out" "V14" "excepted visit claimed: names the visit"
store "[$(work A14a open), $(evisit V14a open A14a dispose-failed.14 lx-sitting)]"
printf 'V14a|tracks|A14a\n' > "$STUB_DEPS"
out=$("$SUT" check A14a --except-key dispose-failed.14 2>/dev/null); rc=$?
eq "$rc" 1 "excepted visit open but bound by assignee: exit 1"
has "$out" "V14a" "excepted visit bound by assignee: names the visit"
store "[$(work A14s open), $(evisit V14s open A14s dispose-failed.14 "" s-lx-sitting)]"
printf 'V14s|tracks|A14s\n' > "$STUB_DEPS"
out=$("$SUT" check A14s --except-key dispose-failed.14 2>/dev/null); rc=$?
eq "$rc" 1 "excepted visit open but bound by session: exit 1"
has "$out" "V14s" "excepted visit bound by session: names the visit"

# 15. The key names one situation: a visit under another key, or a visit with
# no key at all, still holds. Twins under the key are excepted alike.
store "[$(work A15 open), $(evisit V15 open A15 dispose-failed.15), $(evisit W15 open A15 another-question)]"
printf 'V15|tracks|A15\nW15|tracks|A15\n' > "$STUB_DEPS"
out=$("$SUT" check A15 --except-key dispose-failed.15 2>/dev/null); rc=$?
eq "$rc" 1 "a visit under another key beside the excepted one: exit 1"
has "$out" "W15" "a visit under another key beside the excepted one: names it"
store "[$(work A15n open), $(visit V15n open)]"
printf 'V15n|tracks|A15n\n' > "$STUB_DEPS"
out=$("$SUT" check A15n --except-key dispose-failed.15 2>/dev/null); rc=$?
eq "$rc" 1 "a visit carrying no escalation key: exit 1"
store "[$(work A15t open), $(evisit V15t open A15t dispose-failed.15), $(evisit T15t open A15t dispose-failed.15)]"
printf 'V15t|tracks|A15t\nT15t|tracks|A15t\n' > "$STUB_DEPS"
out=$("$SUT" check A15t --except-key dispose-failed.15 2>/dev/null); rc=$?
eq "$rc" 0 "twin visits under the excepted key: exit 0"

# 15b. The visit must be stamped for THIS bead. One that tracks this bead but
# carries another subject's stamp is not this bead's report, so it holds.
store "[$(work A15b open), $(work OTHER15b open), $(evisit V15b open OTHER15b dispose-failed.15)]"
printf 'V15b|tracks|A15b\n' > "$STUB_DEPS"
out=$("$SUT" check A15b --except-key dispose-failed.15 2>/dev/null); rc=$?
eq "$rc" 1 "an excepted-key visit stamped for another bead: exit 1"
has "$out" "V15b" "an excepted-key visit stamped for another bead: names it"

# 16. The exception reaches the gc.continuation_group fallback too, by the same
# rule.
store "[$(work A16 open), $(evisit V16 open A16 dispose-failed.16)]"; : > "$STUB_DEPS"
out=$("$SUT" check A16 --except-key dispose-failed.16 2>/dev/null); rc=$?
eq "$rc" 0 "excepted stamp-only visit: exit 0"
store "[$(work A16b open), $(evisit V16b open A16b dispose-failed.16), $(evisit W16b open A16b another-question)]"; : > "$STUB_DEPS"
out=$("$SUT" check A16b --except-key dispose-failed.16 2>/dev/null); rc=$?
eq "$rc" 1 "a stamp-only visit under another key beside the excepted one: exit 1"
has "$out" "W16b" "a stamp-only visit under another key beside the excepted one: names it"
store "[$(work A16e open), $(evisit V16e open A16e dispose-failed.16 lx-sitting)]"; : > "$STUB_DEPS"
out=$("$SUT" check A16e --except-key dispose-failed.16 2>/dev/null); rc=$?
eq "$rc" 1 "an engaged stamp-only visit under the excepted key: exit 1"

# 17. Usage of the option.
"$SUT" check A1 --except-key >/dev/null 2>&1; eq "$?" 2 "--except-key without a key: exit 2"
"$SUT" check A1 --except-key 'bad key' >/dev/null 2>&1; eq "$?" 2 "--except-key outside escalate.sh's key charset: exit 2"
"$SUT" check A1 --except-visit V1 >/dev/null 2>&1; eq "$?" 2 "an unknown option: exit 2"
"$SUT" check --except-key k1 >/dev/null 2>&1; eq "$?" 2 "an option in place of the bead id: exit 2"

# ── clause no-orphan-gate: a gate whose conversation died without a decision ──
# The gate stays open and still blocks its bead, but its gc.gate_visit names a
# closed visit the sweep never re-offers. no-open-visit cannot see it (the visit
# is closed); this clause does and refuses finalize, fail-closed.

# 18. ORPHAN: open gate on A18, gc.gate_visit names a CLOSED visit -> refuse.
store "[$(work A18 open), $(gate G18 open A18 V18C), $(visit V18C closed)]"; : > "$STUB_DEPS"
out=$("$SUT" check A18 2>/dev/null); rc=$?
eq "$rc" 1 "orphan gate (gate_visit -> closed visit): exit 1"
has "$out" "G18" "orphan gate: names the gate"
has "$out" "A18" "orphan gate: names the gated bead"

# 19. LIVE gate_visit: the recorded visit is still OPEN -> no orphan (that live
# visit is no-open-visit's domain; here it does not cover A19, so the set passes).
store "[$(work A19 open), $(gate G19 open A19 V19O), $(visit V19O open)]"; : > "$STUB_DEPS"
out=$("$SUT" check A19 2>/dev/null); rc=$?
eq "$rc" 0 "gate with an open recorded visit: exit 0"

# 20. UNSET gate_visit: the sweep will offer a visit; not a dead-visit orphan.
store "[$(work A20 open), $(gate G20 open A20 "")]"; : > "$STUB_DEPS"
out=$("$SUT" check A20 2>/dev/null); rc=$?
eq "$rc" 0 "gate with no recorded visit (sweep will offer): exit 0"

# 21. SKIP sentinel: a deliberate operator suppression, not an orphan.
store "[$(work A21 open), $(gate G21 open A21 skip)]"; : > "$STUB_DEPS"
out=$("$SUT" check A21 2>/dev/null); rc=$?
eq "$rc" 0 "gate suppressed with gc.gate_visit=skip: exit 0"

# 22. ASSIGNED gate: a task a named person performs, not a ruling -> left alone.
store "[$(work A22 open), $(gate G22 open A22 V22C human/op), $(visit V22C closed)]"; : > "$STUB_DEPS"
out=$("$SUT" check A22 2>/dev/null); rc=$?
eq "$rc" 0 "assigned gate (a person's task): exit 0"

# 23. DANGLING visit: gc.gate_visit names a visit not in the store -> fail-closed
# orphan (a visit we cannot read is treated as gone).
store "[$(work A23 open), $(gate G23 open A23 V23GONE)]"; : > "$STUB_DEPS"
out=$("$SUT" check A23 2>/dev/null); rc=$?
eq "$rc" 1 "orphan gate (gate_visit -> missing visit): exit 1"
has "$out" "G23" "dangling-visit orphan: names the gate"

# 24. A gate demanding for ANOTHER bead does not hold this one.
store "[$(work A24 open), $(work OTHER24 open), $(gate G24 open OTHER24 V24C), $(visit V24C closed)]"; : > "$STUB_DEPS"
out=$("$SUT" check A24 2>/dev/null); rc=$?
eq "$rc" 0 "orphan gate on another subject: exit 0"

# 25. Fail closed: an unreadable gate listing refuses, naming this clause. Called
# directly (sourced), since a failing `gc bd list` would otherwise refuse at
# no-open-visit's own probe first.
out=$(STUB_LIST_FAIL=1 bash -c '. "$1"; clause_no_orphan_gate A25' _ "$SUT" 2>&1); rc=$?
eq "$rc" 1 "orphan-gate probe unreadable: exit 1 (fail-closed)"
has "$out" "fail-closed" "orphan-gate probe unreadable: names fail-closed"

echo "----- finalize-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
