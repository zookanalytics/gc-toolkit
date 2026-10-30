#!/usr/bin/env bash
# Hermetic test for assets/scripts/orphan-dispose.sh.
#
# THE BUG the script fixes: witness orphan recovery disposed of every bead it
# did not release by `gc workflow delete-source --apply && gc workflow reopen-source`.
# delete-source matches workflow roots on gc.source_bead_id and a root poured
# from an input convoy never carries it, so the close half is a no-op for
# graph.v2 chains and reopen-source runs alone. Run against a workflow STEP
# that sets it open, unassigned and still routed — a pool's offer predicate
# exactly — and against a ROOT it offers the root itself to a pool as work.
#
# What is exercised here:
#   * CLASSIFICATION of the shapes that reach the disposal, including the
#     order dependencies: a review is the source bead of its own molecule and
#     must be recognised by task_kind before the source arm,
#     and a root carries gc.kind/gc.formula_contract where a step carries
#     gc.step_ref;
#   * the ROOT arm writing NOTHING, and in particular never reaching the
#     open+unassigned+routed shape a pool can claim;
#   * the STEP arm releasing the dead session's pin while the chain survives:
#     gc.routed_to, gc.step_ref, gc.root_bead_id and the dependency list are
#     all still there afterwards, so the molecule resumes at the same step;
#   * that neither graph.v2 arm ever invokes delete-source or reopen-source —
#     asserted on the emitted commands, since the whole defect is those two
#     commands being handed beads they cannot match;
#   * ONE WRITE per step release, asserted on the emitted commands:
#     the pins, the open status and the cleared assignee ride one update under
#     --if-assignee and --if-status, so a guard another writer trips lands none
#     of the release, and no pin is gone from a bead that writer now owns;
#   * the assignee guard: --if-assignee carries the assignee read a moment
#     earlier and never the claim's owner, so a step whose owner is not its
#     assignee still releases;
#   * the CLAIM recovery judged: a bead whose owner, status or assignee differs
#     from the --claim it was handed is skipped with nothing written, while a
#     claim the listing read through its control-character strip still matches
#     the read that kept those characters. A gc in front of the harness's
#     enforces --if-assignee and --if-status the way bd does, so a re-claim or
#     a close that lands just ahead of the release stops it whole;
#   * a HALF-LANDED write (the store drops one key while reporting success),
#     which must exit 3 and name the field, not report a clean release;
#   * the source arm delegating to the two commands it was built for, then
#     clearing the session pins reopen-source leaves (gc.session_id and
#     gc.session_name) so orphan recovery stops re-detecting the pooled bead,
#     with verify reporting partial when a pin reports cleared and rolls back;
#   * the source arm's two `gc workflow` calls running under a hard bound: a
#     call that stalls deaf to SIGTERM is killed, a timed-out delete-source
#     fails without reopening, and a timed-out reopen-source is judged by
#     whether the bead reads released;
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

# A gc in front of the harness's, for the cases where another writer moves the
# bead. It enforces bd's --if-assignee and --if-status guards on `gc bd
# update`: the update lands only while the bead still has that status and that
# assignee, and a stale guard lands nothing, logs the refused update and exits
# 13. Before the first update whose arguments contain STUB_RACE_AT, it lands
# STUB_RACE_JQ on the store: the write another writer makes just ahead of it.
GUARD_BIN="$TMP/guard-bin"
mkdir -p "$GUARD_BIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'NEXT=%q\n' "$TMP/bin/gc"; cat; } > "$GUARD_BIN/gc" <<'STUB'
set -u
S="${STUB_STORE:?}"
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "update" ]; then
  id="${3:-}"
  if [ -n "${STUB_RACE_AT:-}" ] && [ ! -e "${STUB_RACE_DONE:?}" ]; then
    case " $* " in
      *"$STUB_RACE_AT"*)
        jq -c "${STUB_RACE_JQ:?}" "$S" > "$S.race" && mv "$S.race" "$S"
        : > "$STUB_RACE_DONE" ;;
    esac
  fi
  if_st="-"; if_who="-"
  for a in "$@"; do
    case "$a" in
      --if-status=*) if_st="${a#--if-status=}" ;;
      --if-assignee=*) if_who="${a#--if-assignee=}" ;;
    esac
  done
  if [ "$if_st" != "-" ] || [ "$if_who" != "-" ]; then
    cur="$(jq -r --arg id "$id" '(.[] | select(.id == $id) | [(.status // ""), (.assignee // "")] | @tsv) // empty' "$S")"
    if { [ "$if_st" != "-" ] && [ "${cur%%$'\t'*}" != "$if_st" ]; } \
       || { [ "$if_who" != "-" ] && [ "${cur#*$'\t'}" != "$if_who" ]; }; then
      printf 'refused %s\n' "$*" >> "${STUB_GC_LOG:?}"
      echo "Error: precondition failed for $id: status/assignee changed" >&2
      exit 13
    fi
  fi
fi
exec "$NEXT" "$@"
STUB
chmod +x "$GUARD_BIN/gc"
export STUB_RACE_DONE="$TMP/race.done"

# land <jq>: another writer's change to the store, landed before the script runs.
land() { jq -c "$1" "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"; }

# dispose_guarded <bead> <claim> [<at> <jq>]: dispose of <bead> under the
# guarding gc, handing it the claim recovery listed. With <at> and <jq>, another
# writer lands <jq> just ahead of the first update that carries <at>. Sets OUT
# and rc.
dispose_guarded() {
  rm -f "$STUB_RACE_DONE"
  OUT=$(PATH="$GUARD_BIN:$PATH" STUB_RACE_AT="${3:-}" STUB_RACE_JQ="${4:-}" \
    "$SCRIPT" "$1" --claim "$2" --apply 2>&1); rc=$?
}

# writes <bead>: the updates of <bead> that reached the store, one per line.
# refused <bead>: the updates of <bead> a stale guard refused.
writes()  { grep -E "^bd update $1 " "$STUB_GC_LOG" || true; }
refused() { grep -E "^refused bd update $1 " "$STUB_GC_LOG" || true; }

# The four shapes, as they appear in a rig store. The step's assignee and its
# metadata.gc.session_id both name the dead session, which is what a step
# claimed by a pool session directly looks like; the other live step shape,
# assigned to the pool ADDRESS while gc.session_id names the dead session, has
# its own fixture under "the owner is not the assignee guard". The root carries
# no assignee and names only gc.session_name. The source work bead carries both
# gc.session_id and gc.session_name from its pool claim — the shape whose pins
# the source arm must scrub, or orphan recovery re-derives the dead owner.
fixture() {
  store '[
    {"id":"tk-step","status":"in_progress","assignee":"hq-dead","title":"Implement the solution",
     "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"hq-dead",
                 "gc.session_name":"polecat-2-pool","gc.session_affinity":"require",
                 "gc.continuation_group":"cg-1",
                 "gc.native_step_dependencies.v1":"[\"mol-polecat-work.preflight-tests\"]"}},
    {"id":"tk-root","status":"in_progress","assignee":"","title":"mol-polecat-work",
     "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2",
                 "gc.input_convoy_id":"tk-convoy","gc.routed_to":"gc-toolkit/gc-toolkit.polecat",
                 "gc.session_name":"polecat-2-pool"}},
    {"id":"tk-work","status":"in_progress","assignee":"hq-dead","title":"a work bead",
     "metadata":{"branch":"polecat/tk-work","gc.routed_to":"gc-toolkit/gc-toolkit.polecat",
                 "workflow_id":"tk-root","gc.session_id":"hq-dead","gc.session_name":"polecat-3-pool"}}
  ]'
  : > "$STUB_GC_LOG"
}

echo "--- classification ---"
fixture
OUT=$("$SCRIPT" tk-step 2>&1);  has "$OUT" "class=workflow-step"  "step classified as workflow-step"
OUT=$("$SCRIPT" tk-root 2>&1);  has "$OUT" "class=workflow-root"  "root classified as workflow-root"
OUT=$("$SCRIPT" tk-work 2>&1);  has "$OUT" "class=source"         "plain work bead classified as source"

# A review bead is the source bead of its own mol-review molecule, so it is
# classified by task_kind before the source arm — and before the step/root
# checks, so a review that also carried a step_ref still reads review.
store '[{"id":"tk-rv","status":"in_progress","assignee":"hq-dead","title":"Review branch polecat/tk-anc -> main: a finding",
         "metadata":{"task_kind":"review","gc.step_ref":"mol-review.review","check_name":"codex",
                     "anchor_bead":"tk-anc","review_branch":"polecat/tk-anc",
                     "gc.routed_to":"gc-toolkit/gc-toolkit.polecat-codex","gc.session_id":"hq-dead"}}]'
OUT=$("$SCRIPT" tk-rv 2>&1); has "$OUT" "class=review" "task_kind=review outranks a step_ref"

echo "--- preview is the default ---"
fixture
OUT=$("$SCRIPT" tk-step 2>&1); rc=$?
eq "$rc" "0" "preview exits 0"
has "$OUT" "result=preview" "preview says so"
eq "$(bstatus tk-step)" "in_progress" "preview left the status alone"
eq "$(meta tk-step gc.session_id)" "hq-dead" "preview left the session pin alone"
eq "$(wc -l < "$STUB_GC_LOG" | tr -d ' ')" "2" "preview reads the step and its root, nothing more"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "preview issued no write at all"

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
OUT=$("$SCRIPT" tk-step --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "0" "step release exits 0"
has "$OUT" "result=disposed" "step release reports disposed"
eq "$(bstatus tk-step)" "open" "step is open"
eq "$(bassignee tk-step)" "" "step is unassigned"
eq "$(meta tk-step gc.session_id)" "<absent>" "dead session id cleared"
eq "$(meta tk-step gc.session_name)" "<absent>" "dead session name cleared"
eq "$(meta tk-step gc.session_affinity)" "<absent>" "session affinity cleared"
eq "$(meta tk-step gc.continuation_group)" "<absent>" "continuation group cleared"
eq "$(meta tk-step gc.routed_to)" "gc-toolkit/gc-toolkit.polecat" "route PRESERVED"
eq "$(meta tk-step gc.step_ref)" "mol-polecat-work.implement" "step_ref PRESERVED"
eq "$(meta tk-step gc.root_bead_id)" "tk-root" "root link PRESERVED"
has "$(meta tk-step gc.native_step_dependencies.v1)" "preflight-tests" "dependency edges PRESERVED"
hasnt "$(cat "$STUB_GC_LOG")" "delete-source" "step arm never calls delete-source"
hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "step arm never calls reopen-source"

echo "--- one write: a release lands whole or not at all ---"
# Asserted on the emitted commands. bd applies an update as one operation and
# checks its guards inside it, so a release that rides one update can only land
# whole, and one a guard refuses lands nothing. A release split across writes
# could be refused after its pins were already gone.
eq "$(writes tk-step | wc -l | tr -d ' ')" "1" "the step release is one write"
REL=$(writes tk-step)
for k in gc.session_id gc.session_name gc.session_affinity gc.continuation_group; do
  has "$REL" "--unset-metadata $k" "the release removes $k"
done
has "$REL" "--status=open --assignee  --if-assignee=hq-dead --if-status=in_progress" \
  "it opens and unassigns the step, guarded on the assignee and status just read"
# The guard value is attached (=form), never space-separated, so the gc wrapper
# never reads a session-id guard as the bead id that picks the store.
hasnt "$(cat "$STUB_GC_LOG")" "--if-assignee hq-dead" "guard uses the attached =form, not the mis-scoping spaced form"
hasnt "$REL" "--force" "the release carries no --force, which bd refuses beside --if-assignee"

echo "--- the owner is not the assignee guard ---"
# The dead owner orphan recovery hands over is the step's gc.session_id, while a
# session that claimed under an alias left that alias as the assignee. The two
# are different strings, so guarding the release on the claim's owner would
# mismatch and refuse every release of this shape.
store '[{"id":"tk-slot","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.polecat","title":"step",
         "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root",
                     "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"hq-dead"}},
        {"id":"tk-root","status":"in_progress","assignee":"","title":"mol-polecat-work",
         "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-slot --claim hq-dead:in_progress:gc-toolkit/gc-toolkit.polecat --apply 2>&1); rc=$?
eq "$rc" "0" "a step whose owner differs from its assignee still releases"
eq "$(bassignee tk-slot)" "" "the alias assignee is cleared"
eq "$(meta tk-slot gc.session_id)" "<absent>" "the dead session id is cleared"
has "$(cat "$STUB_GC_LOG")" "--if-assignee=gc-toolkit/gc-toolkit.polecat" \
  "the guard is the ASSIGNEE, not the claim's owner"
hasnt "$(cat "$STUB_GC_LOG")" "--if-assignee=hq-dead" "the owner is never used as the guard"

# Orphan recovery lists a bead, proves its owner's session gone, and hands the
# disposal that owner and the status and assignee it listed, as one claim. A
# pool can claim a step whose dead holder Gas City released at any moment after
# the listing, and the step's chain can close it. Each case below lands the
# other writer's change on the store.

echo "--- the claim recovery judged: changed before the disposal reads the bead ---"
fixture
land 'map(if .id == "tk-step" then .status = "closed" else . end)'
OUT=$("$SCRIPT" tk-step --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "0" "a step closed after the listing exits 0"
has "$OUT" "result=skipped" "a step closed after the listing is skipped"
has "$OUT" "status=closed" "the skip names the status the read found"
eq "$(writes tk-step)" "" "a closed step takes no write"
eq "$(bassignee tk-step)" "hq-dead" "it keeps the assignee it closed with"
eq "$(meta tk-step gc.session_id)" "hq-dead" "and its pins"

# A step another holder took before the read is skipped.
fixture
land 'map(if .id == "tk-step" then .assignee = "hq-live" | .metadata["gc.session_id"] = "hq-live" else . end)'
OUT=$("$SCRIPT" tk-step --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
has "$OUT" "result=skipped" "a step a live session claimed after the listing is skipped"
eq "$(writes tk-step)" "" "it takes no write"
eq "$(meta tk-step gc.session_id)" "hq-live" "the live claim keeps its pin"

# A session that claims under the pool's alias leaves the same assignee and
# status behind it, so a live session's claim of the step reads as listed in
# both. Only its owner, the gc.session_id the claim stamps, tells it apart.
store '[{"id":"tk-slot","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.polecat","title":"step",
         "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root",
                     "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"hq-live"}},
        {"id":"tk-root","status":"in_progress","assignee":"","title":"mol-polecat-work",
         "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-slot --claim hq-dead:in_progress:gc-toolkit/gc-toolkit.polecat --apply 2>&1); rc=$?
has "$OUT" "result=skipped" "a step re-claimed under its listed alias is skipped on its owner"
has "$OUT" "owner=hq-live" "the skip names the owner the read found"
eq "$(writes tk-slot)" "" "it takes no write"
eq "$(meta tk-slot gc.session_id)" "hq-live" "the live claim keeps its pin"

echo "--- the claim recovery judged: read through the listing's strip ---"
# The candidate listing strips control characters with its own tr ahead of its
# first jq, and that class takes DEL, which this script's read keeps. A claim
# whose values carry one reaches the disposal without it, so the claim check
# compares through the same strip, and the release's guard still names the
# assignee as the store holds it.
LISTING_TR="$(awk '/# >>> candidate-pipeline$/ {f = 1; next} /# <<< candidate-pipeline$/ {f = 0} f' "$HERE/../../formulas/mol-witness-patrol.toml" \
  | sed -n 's/^gc bd list .* | \(tr -d [^|]*\) | {$/\1/p')"
FENCED_TR="$(awk '/^# >>> listing-strip$/ {f = 1; next} /^# <<< listing-strip$/ {f = 0} f' "$SCRIPT" \
  | sed -n 's/^listing_strip() { \(tr -d [^;]*\); }$/\1/p')"
[ -n "$LISTING_TR" ] && [ "$LISTING_TR" = "$FENCED_TR" ] \
  && ok "the claim check compares through the strip the formula's candidate listing runs ($FENCED_TR)" \
  || bad "the listing strips with '${LISTING_TR:-<none>}' and the claim check with '${FENCED_TR:-<none>}'"
# bd writes JSON with Go's encoder, which emits DEL raw where jq escapes it, so
# the fixture carries the raw byte the way bd's output does. The two strips are
# the script's own fenced copies, the listing's checked against the formula's
# just above.
eval "$(awk '/^# >>> control-char-scrub$/ {f = 1; next} /^# <<< control-char-scrub$/ {f = 0} f' "$SCRIPT")"
eval "$(awk '/^# >>> listing-strip$/ {f = 1; next} /^# <<< listing-strip$/ {f = 0} f' "$SCRIPT")"
DEL="$(printf '\177')"
del_fixture() {
  store "[{\"id\":\"tk-del\",\"status\":\"in_progress\",\"assignee\":\"hq-de${DEL}l\",\"title\":\"step\",
           \"metadata\":{\"gc.step_ref\":\"mol-polecat-work.implement\",\"gc.root_bead_id\":\"tk-root\",
                        \"gc.routed_to\":\"gc-toolkit/gc-toolkit.polecat\"}},
          {\"id\":\"tk-root\",\"status\":\"in_progress\",\"assignee\":\"\",\"title\":\"mol-polecat-work\",
           \"metadata\":{\"gc.kind\":\"workflow\",\"gc.formula_contract\":\"graph.v2\"}}]"
  : > "$STUB_GC_LOG"
}
del_fixture
eq "$(listing_strip < "$STUB_STORE" | jq -r '.[0].assignee')" "hq-del" \
  "(premise) the listing reads the assignee without its DEL"
eq "$(scrub < "$STUB_STORE" | jq -r '.[0].assignee')" "hq-de${DEL}l" \
  "(premise) the disposal's own read keeps it"
dispose_guarded tk-del "hq-del:in_progress:hq-del"
eq "$rc" "0" "an assignee whose DEL the listing dropped exits 0"
has "$OUT" "result=disposed" "it is released, not skipped as a changed claim"
eq "$(refused tk-del)" "" "its guard, the assignee as stored, is not refused"
eq "$(bassignee tk-del)" "" "the assignee is cleared"
del_fixture
dispose_guarded tk-del "hq-dex:in_progress:hq-dex"
has "$OUT" "result=skipped" "a claim that differs in a printable character still reads changed"
eq "$(writes tk-del)" "" "and takes no write"

echo "--- the guards ride the one release write ---"
# The guarding gc enforces --if-assignee and --if-status the way bd does. An
# unraced release lands its one write under them.
fixture
dispose_guarded tk-step hq-dead:in_progress:hq-dead
eq "$rc" "0" "an unraced release under enforced guards exits 0"
has "$OUT" "result=disposed" "an unraced step release under enforced guards lands"
eq "$(refused tk-step)" "" "the step's write is not refused"
eq "$(writes tk-step | wc -l | tr -d ' ')" "1" "the release is one write"
has "$(writes tk-step)" "--if-assignee=hq-dead --if-status=in_progress" \
  "it is guarded on the listed claim"

echo "--- the claim recovery judged: changed just ahead of the release ---"
# Another writer lands its change just ahead of the release write. The guard
# refuses the write, so none of the release lands, and the bead is left exactly
# as that writer left it, its pins included.
fixture
dispose_guarded tk-step hq-dead:in_progress:hq-dead \
  "--status=open" 'map(if .id == "tk-step" then .status = "closed" else . end)'
eq "$rc" "0" "a step closed ahead of the release exits 0"
has "$OUT" "result=skipped" "a step closed ahead of the release is skipped"
has "$OUT" "detail=claim_changed(write=release)" "the refused release is named"
hasnt "$OUT" "landed=" "nothing of the release landed"
eq "$(bstatus tk-step)" "closed" "the step stays as it was closed"
eq "$(bassignee tk-step)" "hq-dead" "it keeps its assignee"
eq "$(meta tk-step gc.session_id)$(meta tk-step gc.session_name)" "hq-deadpolecat-2-pool" \
  "and both its pins: none is gone from a bead the closing writer owns"

fixture
dispose_guarded tk-step hq-dead:in_progress:hq-dead \
  "--status=open" 'map(if .id == "tk-step" then .assignee = "hq-live" | .metadata["gc.session_id"] = "hq-live" else . end)'
has "$OUT" "result=skipped" "a step a live session claims just ahead of the release is skipped"
has "$OUT" "detail=claim_changed(write=release)" "the refused release is named"
hasnt "$OUT" "landed=" "nothing of the release landed"
eq "$(bstatus tk-step)" "in_progress" "the live claim stays in progress"
eq "$(bassignee tk-step)" "hq-live" "the live session stays its assignee"
eq "$(meta tk-step gc.session_id)" "hq-live" "the live claim keeps its pin"
eq "$(meta tk-step gc.continuation_group)" "cg-1" "the chain keeps its continuation group"
eq "$(meta tk-step gc.session_affinity)" "require" "and its session affinity"

echo "--- step arm: a step with no route says so ---"
store '[{"id":"tk-unrouted","status":"in_progress","assignee":"hq-dead","title":"step",
         "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root",
                     "gc.session_id":"hq-dead"}},
        {"id":"tk-root","status":"in_progress","assignee":"","title":"mol-polecat-work",
         "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-unrouted --claim hq-dead:in_progress:hq-dead --apply 2>&1)
has "$OUT" "detail=routed=absent" "an unrouted step is released and flagged"
eq "$(bstatus tk-unrouted)" "open" "unrouted step still released"

echo "--- step arm: a root that CLOSED means there is no molecule to resume ---"
# Releasing here would set the step open+unassigned+routed — a pool's offer
# predicate exactly — for a molecule that is over. The chain, not this bead, is
# the disposal unit, so the arm delegates to run-cancel.sh --ended, which ends
# what the run left open through gascity. A stub stands in for it: what this
# suite owns is the DELEGATION and how its exit is read.
cat > "$TMP/bin/run-cancel-stub" <<'STUB'
#!/usr/bin/env bash
printf 'run-cancel %s\n' "$*" >> "${STUB_GC_LOG:?}"
[ -n "${STUB_END_ERR:-}" ] && printf '%s\n' "$STUB_END_ERR" >&2
exit "${STUB_END_RC:-0}"
STUB
chmod +x "$TMP/bin/run-cancel-stub"
export GC_RUN_CANCEL_TOOL="$TMP/bin/run-cancel-stub"

dead_fixture() {
  store '[{"id":"tk-step","status":"in_progress","assignee":"hq-dead","title":"step",
           "metadata":{"gc.step_ref":"mol-review.load-dispatch","gc.root_bead_id":"tk-root",
                       "gc.routed_to":"gc-toolkit/gc-toolkit.polecat-codex","gc.session_id":"hq-dead"}},
          {"id":"tk-root","status":"closed","assignee":"","title":"mol-review",
           "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.outcome":"moot"}}]'
  : > "$STUB_GC_LOG"
}

dead_fixture
OUT=$("$SCRIPT" tk-step --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "0" "a step under a closed root exits 0"
has "$OUT" "class=workflow-step-dead" "it is classified dead, not releasable"
has "$OUT" "root_status=closed" "the report carries the root status it judged on"
has "$OUT" "action=dispose-dead-chain" "the arm ends the chain rather than releases"
has "$OUT" "result=disposed" "an ended chain is reported disposed"
has "$(cat "$STUB_GC_LOG")" "run-cancel --root tk-root --ended" "the run is ended through run-cancel.sh --ended, naming the step's root"
hasnt "$(cat "$STUB_GC_LOG")" "--status=open" "the dead step is never reopened"
hasnt "$(cat "$STUB_GC_LOG")" "--assignee" "the dead step is never returned to a pool"
hasnt "$(cat "$STUB_GC_LOG")" "--status=closed" "the arm closes no member itself"
hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "the dead arm never calls reopen-source"

echo "--- step arm: a refusal (exit 2) is a skip, not a landed disposal ---"
# run-cancel.sh --ended refuses with exit 2 and writes nothing when the root
# reads live on its own read, or when a member left open carries a branch or a
# merge_result (a work bead, which only the refinery closes). That is a skip
# that leaves the step owned for the next cycle.
dead_fixture
export STUB_END_RC=2 STUB_END_ERR="run-cancel: run tk-root is closed but leaves 2 member(s) open, and tk-anchor carries a branch or a merge_result."
OUT=$("$SCRIPT" tk-step --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
export STUB_END_RC=0 STUB_END_ERR=""
eq "$rc" "0" "a refused chain still exits 0"
has "$OUT" "result=skipped" "a refusal is not reported as a disposal"
hasnt "$OUT" "result=disposed" "the wrapper does not claim a landing it did not make"
hasnt "$OUT" "landed=dead-chain" "nothing is marked landed when the chain is intact"
has "$OUT" "not-ended=refused" "the refusal is named"
has "$OUT" "tk-anchor carries a branch or a merge_result" "the reason it was refused survives on stderr"

dead_fixture
OUT=$("$SCRIPT" tk-step 2>&1)
has "$OUT" "result=preview" "preview of a dead step says preview"
hasnt "$(cat "$STUB_GC_LOG")" "run-cancel" "preview does not end the run"

dead_fixture
export STUB_END_RC=1
OUT=$("$SCRIPT" tk-step --apply 2>&1); rc=$?
export STUB_END_RC=0
eq "$rc" "1" "a run that could not be ended exits non-zero"
has "$OUT" "failed=dead-chain" "the failure is named, not swallowed"

dead_fixture
OUT=$(GC_RUN_CANCEL_TOOL="$TMP/bin/no-such-tool" "$SCRIPT" tk-step --apply 2>&1); rc=$?
eq "$rc" "1" "a missing run-cancel.sh exits non-zero"
has "$OUT" "failed=run-cancel-missing" "the missing tool is named"

echo "--- step arm: an unreadable root withholds the release ---"
# An unreadable root is not a live one. Releasing on a failed probe is how a
# finished molecule gets handed back to a pool; the step stays owned and
# returns next cycle instead.
store '[{"id":"tk-step","status":"in_progress","assignee":"hq-dead","title":"step",
         "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-gone",
                     "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"hq-dead"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-step --apply 2>&1); rc=$?
eq "$rc" "0" "an unresolved root exits 0"
has "$OUT" "class=workflow-step-unresolved" "it is classified unresolved"
has "$OUT" "detail=root_unreadable" "the skip states why"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "nothing is written"
hasnt "$(cat "$STUB_GC_LOG")" "run-cancel" "and nothing is ended on a failed probe"
eq "$(bstatus tk-step)" "in_progress" "the step stays owned for the next cycle"
unset GC_RUN_CANCEL_TOOL

echo "--- half-landed write is not a clean release ---"
fixture
export STUB_DROP_KEYS="tk-step:assignee"
OUT=$("$SCRIPT" tk-step --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "3" "a partial release exits 3"
has "$OUT" "result=partial" "a partial release says partial"
has "$OUT" "assignee(still=hq-dead)" "the field that did not land is named"
export STUB_DROP_KEYS=""

echo "--- a refused write is reported, not swallowed ---"
fixture
export STUB_UPDATE_FAIL="tk-step"
OUT=$("$SCRIPT" tk-step --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a refused release exits non-zero" || bad "a refused release exited 0"
has "$OUT" "failed=" "the refusal is named in the result"
eq "$(bstatus tk-step)" "in_progress" "a refused release changed nothing"
export STUB_UPDATE_FAIL=""

echo "--- source arm still delegates ---"
fixture
OUT=$("$SCRIPT" tk-work --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "0" "source disposal exits 0"
has "$OUT" "action=delegate-source-workflow" "source arm delegates"
has "$(cat "$STUB_GC_LOG")" "workflow delete-source tk-work --apply" "delete-source invoked with --apply"
has "$(cat "$STUB_GC_LOG")" "workflow reopen-source tk-work" "reopen-source invoked"
eq "$(bstatus tk-work)" "open" "source bead returned to the pool"
eq "$(meta tk-work gc.routed_to)" "gc-toolkit/gc-toolkit.polecat" "source route preserved by reopen-source"
has "$OUT" "result=disposed" "source disposal reports disposed"
has "$OUT" "pins" "source arm reports the pin clear in landed"
eq "$(meta tk-work gc.session_id)" "<absent>" "source arm clears the dead session id (reopen leaves it)"
eq "$(meta tk-work gc.session_name)" "<absent>" "source arm clears the dead session name (reopen leaves it)"

echo "--- review arm: a review orphan is reopened to its pool by the source contract ---"
# A review bead is the source of its own mol-review molecule: no worktree, so the
# witness scope gate skips its salvage/verify, but its disposal IS the source
# contract — delete-source (a no-op on the input-convoy root) + reopen-source,
# then the dead session's pins cleared and the route restored from the durable
# execution stamp so another reviewer is offered it. It reports class=review only
# so the scope gate and this classifier agree that it takes no salvage path.
store '[{"id":"tk-rev","status":"in_progress","assignee":"hq-dead","title":"Review branch polecat/tk-anc -> main: a finding",
         "metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"tk-anc",
                     "review_branch":"polecat/tk-anc","review_base":"main","gc.routed_to":"",
                     "gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat-codex",
                     "gc.session_id":"hq-dead","gc.session_name":"polecat-5-pool"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-rev --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "0" "review disposal exits 0"
has "$OUT" "class=review" "a review orphan is classed review, not source"
has "$OUT" "action=delegate-source-workflow" "the review arm delegates to the source contract"
has "$(cat "$STUB_GC_LOG")" "workflow reopen-source tk-rev" "reopen-source invoked for the review"
eq "$(bstatus tk-rev)" "open" "the review bead is returned to the pool"
eq "$(meta tk-rev gc.routed_to)" "gc-toolkit/gc-toolkit.polecat-codex" "review route restored from the execution stamp"
eq "$(meta tk-rev gc.session_id)" "<absent>" "the dead session id is cleared"
eq "$(meta tk-rev gc.session_name)" "<absent>" "the dead session name is cleared"
has "$OUT" "result=disposed" "review disposal reports disposed"

echo "--- source arm: a claimed-then-orphaned source bead has its route restored ---"
# The bug this arm exists to close: a source bead (a rework, say) is dispatched
# to a pool, its own claim empties gc.routed_to and stamps the assignee, then the
# claiming session dies. reopen-source reopens it but preserves the emptied route,
# so it lands open, unassigned and unrouted — bd-ready yet never offered to a pool
# again. The durable gc.execution_routed_to stamp survived the claim, so the route
# is restored from it and the bead becomes offerable once more.
store '[{"id":"tk-strand","status":"in_progress","assignee":"hq-dead","title":"Rework branch polecat/tk-anchor: address pre-open signoff findings",
         "metadata":{"branch":"polecat/tk-anchor","gc.routed_to":"",
                     "gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat",
                     "gc.session_id":"hq-dead","gc.session_name":"gc-toolkit--gc-toolkit__polecat-4-pool"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-strand --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "0" "a restored source disposal exits 0"
has "$OUT" "class=source" "the stranded rework is a source bead"
has "$(cat "$STUB_GC_LOG")" "workflow reopen-source tk-strand" "reopen-source invoked"
eq "$(bstatus tk-strand)" "open" "the bead is returned to the pool"
eq "$(meta tk-strand gc.routed_to)" "gc-toolkit/gc-toolkit.polecat" "gc.routed_to restored from the execution stamp"
has "$OUT" "result=disposed" "a restored disposal reports disposed"
has "$OUT" "route" "the route restore is reported in landed"
eq "$(meta tk-strand gc.session_id)" "<absent>" "the dead session id is still cleared"

echo "--- source arm: a route already present is never clobbered ---"
# reopen-source (or a source-id workflow) may leave a route in place. A bead that
# still carries gc.routed_to keeps it, rather than having it overwritten from the
# execution stamp, so a restore never fights a live route.
store '[{"id":"tk-liveroute","status":"in_progress","assignee":"hq-dead","title":"a work bead",
         "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat-codex",
                     "gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat",
                     "gc.session_id":"hq-dead","gc.session_name":"polecat-9-pool"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-liveroute --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "0" "a preserved-route disposal exits 0"
eq "$(meta tk-liveroute gc.routed_to)" "gc-toolkit/gc-toolkit.polecat-codex" "an existing route is left untouched"
hasnt "$OUT" "route-unrecoverable" "a live route is not flagged unrecoverable"

echo "--- source arm: a reopened bead with no recoverable route is surfaced, not stranded ---"
# When the claim emptied gc.routed_to and no gc.execution_routed_to was ever
# stamped, the reopened bead cannot be offered and there is nothing to restore it
# from. Leaving it silent recreates the strand, so the release is reported partial
# (exit 3) for the patrol to surface, rather than passed off as a clean disposal.
store '[{"id":"tk-noroute","status":"in_progress","assignee":"hq-dead","title":"Rework branch polecat/tk-old: address findings",
         "metadata":{"branch":"polecat/tk-old","gc.routed_to":"",
                     "gc.session_id":"hq-dead","gc.session_name":"polecat-3-pool"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-noroute --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "3" "an unrecoverable-route release exits 3"
has "$OUT" "result=partial" "it reports partial, not disposed"
has "$OUT" "route-unrecoverable" "the missing route is named"
eq "$(bstatus tk-noroute)" "open" "the bead was still reopened and unassigned"
eq "$(meta tk-noroute gc.routed_to)" "" "gc.routed_to stays empty when nothing can restore it"

echo "--- source arm: an in-flight-PR source bead is NOT returned to the pool ---"
# A work bead handed off with its branch pushed and its PR in flight (merge_result
# pull_request/pre_open_gate) still names its dead session, so orphan recovery
# classes it source and would delete-source + reopen-source it back to the pool,
# re-dispatching finished work the refinery owns landing and stamping a recovery
# the crash-loop signal reads as a RATE. The source arm skips it: no delete-source,
# no reopen, bead left as-is.
for MR in pull_request pre_open_gate; do
  store "[{\"id\":\"tk-inflight\",\"status\":\"open\",\"assignee\":\"\",\"title\":\"in-flight work bead\",
           \"metadata\":{\"branch\":\"polecat/tk-inflight\",\"merge_result\":\"$MR\",
                       \"gc.routed_to\":\"gc-toolkit/gc-toolkit.polecat\",\"gc.session_name\":\"polecat-9-pool\"}}]"
  : > "$STUB_GC_LOG"
  OUT=$("$SCRIPT" tk-inflight --claim polecat-9-pool:open: --apply 2>&1); rc=$?
  eq "$rc" "0" "in-flight source disposal ($MR) exits 0"
  has "$OUT" "class=source"        "in-flight bead is still classed source ($MR)"
  has "$OUT" "action=skip"         "in-flight source is skipped, not delegated ($MR)"
  has "$OUT" "result=skipped"      "in-flight source reports skipped ($MR)"
  has "$OUT" "detail=inflight_pr"  "in-flight skip states why ($MR)"
  hasnt "$(cat "$STUB_GC_LOG")" "delete-source" "in-flight source never calls delete-source ($MR)"
  hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "in-flight source never reopens ($MR)"
  eq "$(bstatus tk-inflight)" "open" "in-flight bead left as-is ($MR)"
done

echo "--- source arm: a stale progressing pr.machine (no anchor) is recovered ---"
# pr.machine=progressing is written only alongside an anchor merge_result, and
# transition --to unanchored clears merge_result while leaving pr.machine behind,
# so a `progressing` stamp with NO merge_result is a stale leftover on a bead
# unanchored back to the pool — genuinely lost work. It must NOT block the reopen:
# the source arm delegates and recovers it, whatever the stamp says.
store '[{"id":"tk-prog","status":"in_progress","assignee":"hq-dead","title":"stale-progressing work bead",
         "metadata":{"branch":"polecat/tk-prog","pr.machine":"progressing@abc@2026-09-05T00:00:00Z",
                     "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"hq-dead","gc.session_name":"polecat-9-pool"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-prog --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "0" "stale-progressing source disposal exits 0"
has "$OUT" "action=delegate-source-workflow" "a stale progressing stamp (no anchor) delegates, not skips"
has "$(cat "$STUB_GC_LOG")" "delete-source" "stale-progressing source calls delete-source"
has "$OUT" "result=disposed" "stale-progressing source is recovered"

echo "--- source arm: a human-routed source bead is NOT returned to the pool ---"
# A work bead a person owns clearing — routed to a human (gc.routed_to=human: a
# merge gate, an operator approval) — is not lost work, even with no
# merge_result and no progressing machine. It still names its dead session, so orphan
# recovery classes it source and would delete-source + reopen-source it back to the
# pool. mol-witness-patrol's downstream-court-skip filter drops it upstream, but a bead
# that moves onto a human route after that filter, or reaches this script by recovery or
# manual replay, must still be skipped here. The tk-work and tk-settled cases above
# (routed to a pool address, no in-flight state) still delegate, so the guard is scoped
# to the human route, not to any route.
store '[{"id":"tk-human","status":"open","assignee":"","title":"human-gate work bead",
         "metadata":{"branch":"polecat/tk-human","gc.routed_to":"human","gc.session_name":"polecat-9-pool"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-human --claim polecat-9-pool:open: --apply 2>&1); rc=$?
eq "$rc" "0" "human-gate source disposal exits 0"
hasnt "$OUT" "claim_changed" "an empty listed assignee matches an unassigned bead"
has "$OUT" "class=source"      "human-gate bead is still classed source"
has "$OUT" "action=skip"       "human-gate source is skipped, not delegated"
has "$OUT" "result=skipped"    "human-gate source reports skipped"
has "$OUT" "detail=human_route" "human-route skip states why"
hasnt "$(cat "$STUB_GC_LOG")" "delete-source" "human-gate source never calls delete-source"
hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "human-gate source never reopens"
eq "$(bstatus tk-human)" "open" "human-gate bead left as-is"

echo "--- source arm: a conversation is NOT returned to the pool ---"
# A conversation is a task assigned to `human` in the operator's queue, or to
# the alias of its sitting, which names the task's own id (conversation.sh). No
# session carries either owner: Gas City reserves `human`, and a sitting whose
# session closed keeps its alias as the assignee until a session under that
# alias takes the conversation back. Orphan recovery resolves both as dead and
# would reopen the conversation to a pool. A task whose alias names another id
# is not a conversation, so the guard is scoped to the shape.
for conv in "tk-conv:in_progress:gc-toolkit/gc-toolkit.tk-conv" "tk-convq:open:human" "tk-convc:in_progress:gc-toolkit/gc-toolkit.c-tk-convc"; do
    cid="${conv%%:*}"; rest="${conv#*:}"; cst="${rest%%:*}"; cas="${rest#*:}"
    store "[{\"id\":\"$cid\",\"status\":\"$cst\",\"issue_type\":\"task\",\"assignee\":\"$cas\",\"title\":\"about tk-subj\",
             \"dependencies\":[{\"id\":\"tk-subj\",\"dependency_type\":\"tracks\",\"status\":\"open\"}],\"metadata\":{}}]"
    : > "$STUB_GC_LOG"
    OUT=$("$SCRIPT" "$cid" --claim "$cas:$cst:$cas" --apply 2>&1); rc=$?
    eq "$rc" "0" "a conversation's disposal exits 0 ($cas)"
    has "$OUT" "action=skip" "a conversation is skipped, not delegated ($cas)"
    has "$OUT" "detail=conversation(assignee=$cas)" "…and the skip names it ($cas)"
    hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "…and it is never reopened ($cas)"
    eq "$(bstatus "$cid")" "$cst" "…and it is left as it was ($cas)"
done
store '[{"id":"tk-notconv","status":"in_progress","issue_type":"task","assignee":"gc-toolkit/gc-toolkit.tk-other","title":"a task under an alias naming another bead",
         "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"hq-dead"}}]'
OUT=$("$SCRIPT" tk-notconv 2>&1)
has "$OUT" "action=delegate-source-workflow" "a task whose alias names another id is no conversation, and delegates"

echo "--- source arm: a progressing pr.machine WITH an anchor still skips (on merge_result) ---"
# The in-flight skip is the merge_result arm's alone now. A bead genuinely in the
# machine carries an anchor merge_result, so it still skips — proving the fix
# narrowed the skip to merge_result/human without letting in-flight work through.
store '[{"id":"tk-anchor-prog","status":"open","assignee":"","title":"anchored progressing work bead",
         "metadata":{"branch":"polecat/tk-anchor-prog","merge_result":"pull_request","pr.machine":"progressing@abc@2026-09-05T00:00:00Z",
                     "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_name":"polecat-9-pool"}}]'
: > "$STUB_GC_LOG"
OUT=$("$SCRIPT" tk-anchor-prog --claim polecat-9-pool:open: --apply 2>&1); rc=$?
eq "$rc" "0" "anchored-progressing source disposal exits 0"
has "$OUT" "result=skipped" "an in-flight bead (merge_result=pull_request) still skips"
has "$OUT" "detail=inflight_pr" "the skip is on the merge_result arm"
hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "anchored-progressing source never reopens"

echo "--- source arm: a pin that will not clear is not a clean release ---"
# clear_pins bypasses the claim guard, but a store that reports success and drops
# the key is the rollback verify exists to catch. With the dead session id
# surviving, orphan recovery would re-detect this bead — so it must read partial,
# not disposed, and name the pin.
fixture
export STUB_DROP_KEYS="tk-work:gc.session_id"
OUT=$("$SCRIPT" tk-work --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
eq "$rc" "3" "a source disposal whose pin survives exits 3"
has "$OUT" "result=partial" "it reports partial, not disposed"
has "$OUT" "gc.session_id(still=hq-dead)" "the surviving pin is named"
export STUB_DROP_KEYS=""

echo "--- source arm: reopen does not run when the close failed ---"
fixture
export STUB_DELETE_SOURCE_RC=1
OUT=$("$SCRIPT" tk-work --apply 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a failed delete-source exits non-zero" || bad "a failed delete-source exited 0"
hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "reopen-source is not run after a failed close"
eq "$(bstatus tk-work)" "in_progress" "the bead was not returned to the pool"
export STUB_DELETE_SOURCE_RC=""

echo "--- source arm: the gc workflow calls are hard-bounded ---"
# Once either command holds its per-bead lock it ignores SIGTERM and runs the
# work inside the lock to completion, so a TERM-only timeout bounds nothing.
# The stub's stall ignores TERM the same way. A call that returns well inside
# the stall was ended by the bound's SIGKILL; an unbounded one would run the
# whole stall and blow through the ceiling.
export GC_ORPHAN_WORKFLOW_TIMEOUT=3 GC_ORPHAN_WORKFLOW_KILL_AFTER=1
STALL=60
CEILING=20
run_bounded_case() { # <bead>: sets OUT, rc and ELAPSED
  local start; start=$(date +%s)
  OUT=$("$SCRIPT" "$1" --claim hq-dead:in_progress:hq-dead --apply 2>&1); rc=$?
  ELAPSED=$(( $(date +%s) - start ))
}
within_ceiling() { # <label>
  if [ "$ELAPSED" -lt "$CEILING" ]; then
    ok "$1 (${ELAPSED}s)"
  else
    bad "$1: ran ${ELAPSED}s, so the bound never killed the call"
  fi
}

# A delete-source that prints its result and never exits counts as failed:
# reopen-source never runs, and the bead stays owned for the next cycle.
fixture
export STUB_DELETE_SOURCE_HANG=$STALL
run_bounded_case tk-work
export STUB_DELETE_SOURCE_HANG=""
within_ceiling "a delete-source deaf to SIGTERM is killed at the bound"
eq "$rc" "1" "a timed-out delete-source exits 1"
has "$OUT" "failed=delete-source-timeout" "the timeout is named, not reported as a plain failure"
hasnt "$(cat "$STUB_GC_LOG")" "reopen-source" "reopen-source does not run after a timed-out delete-source"
eq "$(bstatus tk-work)" "in_progress" "the bead stays owned for the next cycle"
eq "$(meta tk-work gc.session_id)" "hq-dead" "its session pin is untouched"

# A reopen-source that releases the bead, prints, and never exits has landed
# its release. The bead reads open and unassigned, so the arm finishes the job
# exactly as after a clean exit: pins cleared, route restored from the durable
# execution stamp, verify green.
store '[{"id":"tk-strand","status":"in_progress","assignee":"hq-dead","title":"a source bead",
         "metadata":{"branch":"polecat/tk-anchor","gc.routed_to":"",
                     "gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat",
                     "gc.session_id":"hq-dead","gc.session_name":"polecat-4-pool"}}]'
: > "$STUB_GC_LOG"
export STUB_REOPEN_SOURCE_HANG=$STALL
run_bounded_case tk-strand
export STUB_REOPEN_SOURCE_HANG=""
within_ceiling "a reopen-source deaf to SIGTERM after its release is killed at the bound"
eq "$rc" "0" "a release that landed before the bound exits 0"
has "$OUT" "result=disposed" "a landed release is a disposal, not a failure"
has "$OUT" "landed=delete-source,reopen-source,pins,route" "pins and route are finished after the cut-off call"
has "$OUT" "detail=reopen-source-past-bound" "the report says the call ran past its bound"
eq "$(bstatus tk-strand)" "open" "the bead is released"
eq "$(bassignee tk-strand)" "" "the bead is unassigned"
eq "$(meta tk-strand gc.session_id)" "<absent>" "the dead session id is cleared"
eq "$(meta tk-strand gc.session_name)" "<absent>" "the dead session name is cleared"
eq "$(meta tk-strand gc.routed_to)" "gc-toolkit/gc-toolkit.polecat" "the route is restored from the execution stamp"

# A reopen-source killed before it writes released nothing. The arm writes
# nothing either, so the bead keeps its assignee and its pins and orphan
# recovery finds it again next cycle.
fixture
export STUB_REOPEN_SOURCE_STALL=$STALL
run_bounded_case tk-work
export STUB_REOPEN_SOURCE_STALL=""
within_ceiling "a reopen-source stalled before its writes is killed at the bound"
eq "$rc" "3" "a timed-out reopen-source after a landed delete-source exits 3"
has "$OUT" "landed=delete-source failed=reopen-source-timeout" "only the close is reported landed, and the timeout is named"
eq "$(bstatus tk-work)" "in_progress" "an unreleased bead is not reported released"
eq "$(bassignee tk-work)" "hq-dead" "it keeps its assignee"
eq "$(meta tk-work gc.session_id)" "hq-dead" "and its session pin, so orphan recovery finds it again"
unset GC_ORPHAN_WORKFLOW_TIMEOUT GC_ORPHAN_WORKFLOW_KILL_AFTER

echo "--- unreadable bead and usage ---"
fixture
OUT=$("$SCRIPT" tk-nope --apply 2>&1); rc=$?
eq "$rc" "1" "an unknown bead exits 1"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an unknown bead is never written to"
OUT=$("$SCRIPT" 2>&1); eq "$?" "2" "no bead id exits 2"
OUT=$("$SCRIPT" tk-step --bogus 2>&1); eq "$?" "2" "an unknown flag exits 2"
OUT=$("$SCRIPT" tk-step --claim 2>&1); eq "$?" "2" "--claim at end of argv exits 2"
OUT=$("$SCRIPT" tk-step --claim hq-dead --apply 2>&1); eq "$?" "2" "a --claim value with no colon exits 2"
OUT=$("$SCRIPT" tk-step --claim hq-dead:in_progress --apply 2>&1); eq "$?" "2" "a --claim value with one colon exits 2"
OUT=$("$SCRIPT" tk-step --claim :in_progress:hq-dead --apply 2>&1); eq "$?" "2" "a --claim value with no owner exits 2"
OUT=$("$SCRIPT" tk-step --claim hq-dead::hq-dead --apply 2>&1); eq "$?" "2" "a --claim value with no status exits 2"
OUT=$("$SCRIPT" tk-step --owner hq-dead --apply 2>&1); eq "$?" "2" "the retired --owner flag is refused"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "a malformed --claim writes nothing"

echo "--- json output ---"
fixture
OUT=$("$SCRIPT" tk-step --claim hq-dead:in_progress:hq-dead --json 2>&1)
printf '%s' "$OUT" | jq -e '.class == "workflow-step" and .result == "preview" and .root == "tk-root" and .owner == "hq-dead"' >/dev/null 2>&1 \
  && ok "--json emits one object carrying class, result, root and the owner the claim names" \
  || bad "--json object wrong: $OUT"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
