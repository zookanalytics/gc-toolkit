#!/usr/bin/env bash
# Hermetic test for assets/scripts/orphan-dispose.sh.
#
# THE BUG the script fixes: witness orphan recovery disposed of every non-visit
# bead with `gc workflow delete-source --apply && gc workflow reopen-source`.
# delete-source matches workflow roots on gc.source_bead_id and a root poured
# from an input convoy never carries it, so the close half is a no-op for
# graph.v2 chains and reopen-source runs alone. Run against a workflow STEP
# that sets it open, unassigned and still routed — a pool's offer predicate
# exactly — and against a ROOT it offers the root itself to a pool as work.
#
# What is exercised here:
#   * CLASSIFICATION on the four shapes that reach the disposal, including the
#     order dependencies: a visit is the source bead of its own molecule and
#     must be read as a visit, and a root carries gc.kind/gc.formula_contract
#     where a step carries gc.step_ref;
#   * the ROOT arm writing NOTHING, and in particular never reaching the
#     open+unassigned+routed shape a pool can claim;
#   * the STEP arm releasing the dead session's pin while the chain survives:
#     gc.routed_to, gc.step_ref, gc.root_bead_id and the dependency list are
#     all still there afterwards, so the molecule resumes at the same step;
#   * that neither graph.v2 arm ever invokes delete-source or reopen-source —
#     asserted on the emitted commands, since the whole defect is those two
#     commands being handed beads they cannot match;
#   * the WRITE ORDER, asserted on the emitted commands rather than the store:
#     bd rejects a whole update when its claim guard refuses the assignee half,
#     so a release batched into one call rolls back every field while looking
#     like it worked. No single update may carry both --status and --assignee,
#     and the order must be metadata, then status, then assignee;
#   * the assignee guard: --if-assignee carries the assignee read a moment
#     earlier and never the --owner, so a bead re-claimed in between is left
#     alone and a step whose owner is not its assignee still releases;
#   * a HALF-LANDED write (the store drops one key while reporting success),
#     which must exit 3 and name the field, not report a clean release;
#   * the source arm still delegating to the two commands it was built for;
#   * preview being the default: no --apply writes nothing at all;
#   * usage errors and an unreadable bead, which must write nothing.
#
# No live city, Dolt, network, or beads — stubs from test-harness.sh only.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/orphan-dispose.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-orphan-dispose-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# A `bd` stub beside the `gc` one: the forced assignee clear falls through to
# bare bd, and a test box need not have the real binary. It logs to the same
# place so ORDER assertions see one stream of writes.
cat > "$TMP/bin/bd" <<'STUB'
#!/usr/bin/env bash
set -u
printf 'bd %s\n' "$*" >> "${STUB_GC_LOG:?}"
exit 1
STUB
chmod +x "$TMP/bin/bd"

# The four shapes, as they appear in a rig store. The step's assignee and its
# metadata.gc.session_id both name the dead session, which is what a step
# claimed by a pool session directly looks like; the other live step shape,
# assigned to the pool ADDRESS while gc.session_id names the dead session, has
# its own fixture under "the owner is not the assignee guard". The root carries
# no assignee and names only gc.session_name.
fixture() {
  store '[
    {"id":"tk-step","status":"in_progress","assignee":"lx-dead","title":"Implement the solution",
     "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"lx-dead",
                 "gc.session_name":"polecat-2-pool","gc.session_affinity":"require",
                 "gc.continuation_group":"cg-1",
                 "gc.native_step_dependencies.v1":"[\"mol-polecat-work.preflight-tests\"]"}},
    {"id":"tk-root","status":"in_progress","assignee":"","title":"mol-polecat-work",
     "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2",
                 "gc.input_convoy_id":"tk-convoy","gc.routed_to":"gc-toolkit/gc-toolkit.polecat",
                 "gc.session_name":"polecat-2-pool"}},
    {"id":"tk-visit","status":"in_progress","assignee":"lx-dead","title":"visit",
     "metadata":{"task_kind":"visit","gc.routed_to":"gc-toolkit/gc-toolkit.converse",
                 "gc.continuation_group":"cg-visit","gc.session_id":"lx-dead"}},
    {"id":"tk-work","status":"in_progress","assignee":"lx-dead","title":"a work bead",
     "metadata":{"branch":"polecat/tk-work","gc.routed_to":"gc-toolkit/gc-toolkit.polecat",
                 "workflow_id":"tk-root","gc.session_id":"lx-dead"}}
  ]'
  : > "$STUB_GC_LOG"
}

echo "--- classification ---"
fixture
OUT=$("$SCRIPT" tk-step 2>&1);  has "$OUT" "class=workflow-step"  "step classified as workflow-step"
OUT=$("$SCRIPT" tk-root 2>&1);  has "$OUT" "class=workflow-root"  "root classified as workflow-root"
OUT=$("$SCRIPT" tk-visit 2>&1); has "$OUT" "class=visit"          "visit classified as visit"
OUT=$("$SCRIPT" tk-work 2>&1);  has "$OUT" "class=source"         "plain work bead classified as source"

# A visit that also carried step metadata must still read as a visit: it is the
# source bead of its own mol-visit molecule, and the visit arm is the narrower
# contract (release the assignee and touch no metadata).
store '[{"id":"tk-v2","status":"in_progress","assignee":"lx-dead","title":"visit",
         "metadata":{"task_kind":"visit","gc.step_ref":"mol-visit.converse",
                     "gc.routed_to":"r","gc.session_id":"lx-dead"}}]'
OUT=$("$SCRIPT" tk-v2 2>&1); has "$OUT" "class=visit" "task_kind=visit outranks a step_ref"

echo "--- preview is the default ---"
fixture
OUT=$("$SCRIPT" tk-step 2>&1); rc=$?
eq "$rc" "0" "preview exits 0"
has "$OUT" "result=preview" "preview says so"
eq "$(bstatus tk-step)" "in_progress" "preview left the status alone"
eq "$(meta tk-step gc.session_id)" "lx-dead" "preview left the session pin alone"
eq "$(wc -l < "$STUB_GC_LOG")" "1" "preview issued exactly one read and no write"

echo "--- root arm: never returns a root to a pool ---"
fixture
OUT=$("$SCRIPT" tk-root --apply 2>&1); rc=$?
eq "$rc" "0" "root disposal exits 0"
has "$OUT" "result=skipped" "root is skipped"
has "$OUT" "detail=root_not_schedulable" "root skip states why"
eq "$(bstatus tk-root)" "in_progress" "root status untouched"
eq "$(meta tk-root gc.session_name)" "polecat-2-pool" "root session name untouched"
eq "$(meta tk-root gc.routed_to)" "gc-toolkit/gc-toolkit.polecat" "root route untouched"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "root arm issued no write at all"
hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "root arm never reopens the root"
hasnt "$(cat "$STUB_GC_LOG")" "delete-source" "root arm never calls delete-source"

echo "--- step arm: pin released, chain preserved ---"
fixture
OUT=$("$SCRIPT" tk-step --owner lx-dead --apply 2>&1); rc=$?
eq "$rc" "0" "step release exits 0"
has "$OUT" "result=disposed" "step release reports disposed"
eq "$(bstatus tk-step)" "open" "step is open"
eq "$(bassignee tk-step)" "" "step is unassigned"
eq "$(meta tk-step gc.session_id)" "<absent>" "dead session id cleared"
eq "$(meta tk-step gc.session_affinity)" "<absent>" "session affinity cleared"
eq "$(meta tk-step gc.continuation_group)" "<absent>" "continuation group cleared"
eq "$(meta tk-step gc.routed_to)" "gc-toolkit/gc-toolkit.polecat" "route PRESERVED"
eq "$(meta tk-step gc.step_ref)" "mol-polecat-work.implement" "step_ref PRESERVED"
eq "$(meta tk-step gc.root_bead_id)" "tk-root" "root link PRESERVED"
has "$(meta tk-step gc.native_step_dependencies.v1)" "preflight-tests" "dependency edges PRESERVED"
hasnt "$(cat "$STUB_GC_LOG")" "delete-source" "step arm never calls delete-source"
hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "step arm never calls reopen-source"

echo "--- write order: the claim guard cannot roll a release back ---"
# Asserted on the emitted commands. bd rejects the WHOLE update when its claim
# guard refuses the assignee half, so a batched release reports success and
# writes nothing; splitting is the fix and the log is where it is provable.
LOG_UPDATES=$(grep -c -- "update tk-step" "$STUB_GC_LOG" || true)
[ "$LOG_UPDATES" -ge 3 ] \
  && ok "release used separate calls per field ($LOG_UPDATES)" \
  || bad "release batched fields into $LOG_UPDATES call(s)"
BATCHED=$(grep -- "update tk-step" "$STUB_GC_LOG" | grep -c -- "--status.*--assignee\|--assignee.*--status" || true)
eq "$BATCHED" "0" "no single update carries both --status and --assignee"
ORDER=$(grep -- "update tk-step" "$STUB_GC_LOG" \
  | sed -e 's/.*--unset-metadata.*/meta/' -e 's/.*--status.*/status/' -e 's/.*--assignee.*/assignee/' \
  | tr '\n' ',')
eq "$ORDER" "meta,status,assignee," "metadata first, status next, assignee last"
has "$(cat "$STUB_GC_LOG")" "--if-assignee lx-dead" "assignee clear is guarded on the assignee snapshot"

echo "--- the owner is not the assignee guard ---"
# The shape orphan recovery most often hands over: the dead owner is the step's
# gc.session_id, while the assignee still names the pool SLOT, which is live and
# inherited by the next occupant. The two are different strings, so guarding the
# clear on --owner would mismatch and refuse every release of this shape.
store '[{"id":"tk-slot","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.polecat","title":"step",
         "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root",
                     "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"lx-dead"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-slot --owner lx-dead --apply 2>&1); rc=$?
eq "$rc" "0" "a step whose owner differs from its assignee still releases"
eq "$(bassignee tk-slot)" "" "the slot assignee is cleared"
eq "$(meta tk-slot gc.session_id)" "<absent>" "the dead session id is cleared"
has "$(cat "$STUB_GC_LOG")" "--if-assignee gc-toolkit/gc-toolkit.polecat" \
  "the guard is the ASSIGNEE, not the --owner"
hasnt "$(cat "$STUB_GC_LOG")" "--if-assignee lx-dead" "the owner is never used as the guard"

echo "--- step arm: a step with no route says so ---"
store '[{"id":"tk-unrouted","status":"in_progress","assignee":"lx-dead","title":"step",
         "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root",
                     "gc.session_id":"lx-dead"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-unrouted --owner lx-dead --apply 2>&1)
has "$OUT" "detail=routed=absent" "an unrouted step is released and flagged"
eq "$(bstatus tk-unrouted)" "open" "unrouted step still released"

echo "--- half-landed write is not a clean release ---"
fixture
export STUB_DROP_KEYS="tk-step:assignee"
OUT=$("$SCRIPT" tk-step --owner lx-dead --apply 2>&1); rc=$?
eq "$rc" "3" "a partial release exits 3"
has "$OUT" "result=partial" "a partial release says partial"
has "$OUT" "assignee(still=lx-dead)" "the field that did not land is named"
export STUB_DROP_KEYS=""

echo "--- a refused write is reported, not swallowed ---"
fixture
export STUB_UPDATE_FAIL="tk-step"
OUT=$("$SCRIPT" tk-step --owner lx-dead --apply 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a refused release exits non-zero" || bad "a refused release exited 0"
has "$OUT" "failed=" "the refusal is named in the result"
eq "$(bstatus tk-step)" "in_progress" "a refused release changed nothing"
export STUB_UPDATE_FAIL=""

echo "--- source arm still delegates ---"
fixture
OUT=$("$SCRIPT" tk-work --owner lx-dead --apply 2>&1); rc=$?
eq "$rc" "0" "source disposal exits 0"
has "$OUT" "action=delegate-source-workflow" "source arm delegates"
has "$(cat "$STUB_GC_LOG")" "workflow delete-source tk-work --apply" "delete-source invoked with --apply"
has "$(cat "$STUB_GC_LOG")" "workflow reopen-source tk-work" "reopen-source invoked"
eq "$(bstatus tk-work)" "open" "source bead returned to the pool"
eq "$(meta tk-work gc.routed_to)" "gc-toolkit/gc-toolkit.polecat" "source route preserved by reopen-source"

echo "--- source arm: reopen does not run when the close failed ---"
fixture
export STUB_DELETE_SOURCE_RC=1
OUT=$("$SCRIPT" tk-work --apply 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a failed delete-source exits non-zero" || bad "a failed delete-source exited 0"
hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "reopen-source is not run after a failed close"
eq "$(bstatus tk-work)" "in_progress" "the bead was not returned to the pool"
export STUB_DELETE_SOURCE_RC=""

echo "--- unreadable bead and usage ---"
fixture
OUT=$("$SCRIPT" tk-nope --apply 2>&1); rc=$?
eq "$rc" "1" "an unknown bead exits 1"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an unknown bead is never written to"
OUT=$("$SCRIPT" 2>&1); eq "$?" "2" "no bead id exits 2"
OUT=$("$SCRIPT" tk-step --bogus 2>&1); eq "$?" "2" "an unknown flag exits 2"
OUT=$("$SCRIPT" tk-step --owner 2>&1); eq "$?" "2" "a value-taking flag at end of argv exits 2"

echo "--- json output ---"
fixture
OUT=$("$SCRIPT" tk-step --owner lx-dead --json 2>&1)
printf '%s' "$OUT" | jq -e '.class == "workflow-step" and .result == "preview" and .root == "tk-root"' >/dev/null 2>&1 \
  && ok "--json emits one object carrying class, result and root" \
  || bad "--json object wrong: $OUT"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
