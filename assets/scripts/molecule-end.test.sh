#!/usr/bin/env bash
# Hermetic test for assets/scripts/molecule-end.sh, run end to end with the
# real molecule-hold.sh and dead-molecule-dispose.sh over the shared stub store.
#
# WHAT IT IS FOR. A molecule parked by molecule-hold.sh used to record how it
# should end as a sentence nothing acted on, so it outlived the work it was
# poured for. molecule-end.sh binds the molecule's lifetime to that work: a
# hold on work already closed ends the molecule there, and a hold on work still
# open arms an end bead, blocked by the work, that the pool is offered once the
# work closes and whose run ends the molecule.
#
# What is exercised:
#   * PARK, CLOSE, END — a molecule held on open work gets one end bead (a
#     member, routed, blocked by the work); nothing offers it while the work is
#     open; once a writer closes the work it is offerable, and the run of the
#     worker that claims it closes the molecule, the end bead included. No
#     sweep runs anywhere in it;
#   * the PARK-AFTER-CLOSE case — a hold whose work has already closed ends the
#     molecule at once, with the holding session's own claim set aside, and
#     writes no hold;
#   * an OPEN source leaves a parked molecule as it is, and an end run on it
#     only re-arms;
#   * the disposer's REFUSALS still hold, each as a wait: an open escalation
#     visit becomes a blocker of the end bead, a live session owns the end, and
#     a refusal the disposer would repeat files a visit the end then waits on;
#   * ANY FORMULA — a mol-validate molecule whose source is a validation pass
#     ends the same way;
#   * ORDER — a new end bead is routed only after its blockers are in place,
#     and a claimed one is re-armed edges first, then reopened, then released;
#   * idempotence, an unbound molecule, failed writes and dry runs.
#
# No live city, Dolt, network, gc or bd — stubs from test-harness.sh only.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-molecule-end-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SUT="$TMP/sut"
mk_sut_dir "$SUT" "$HERE/molecule-end.sh" "$HERE/molecule-hold.sh" "$HERE/dead-molecule-dispose.sh"
END_SH="$SUT/molecule-end.sh"
HOLD_SH="$SUT/molecule-hold.sh"

# escalate.sh is a stub that files a visit into the stub store, tracking the
# subject, the way the real one does, and logs each call.
export ESC_LOG="$TMP/escalate.log"
cat > "$TMP/escalate-stub" <<'ESC'
#!/usr/bin/env bash
subj=""; key=""
while [ $# -gt 0 ]; do
  case "$1" in --subject) shift; subj="${1:-}" ;; --key) shift; key="${1:-}" ;; esac
  shift || true
done
printf '%s %s\n' "$subj" "$key" >> "${ESC_LOG:?}"
[ -n "${FAKE_ESC_RC:-}" ] && exit "$FAKE_ESC_RC"
id="visit-$key"
jq -c --arg id "$id" --arg k "$key" '. + [{"id":$id,"status":"open","assignee":"","title":"visit","issue_type":"task","metadata":{"escalation_key":$k,"task_kind":"visit"}}]' \
  "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
printf '%s|tracks|%s\n' "$id" "$subj" >> "$STUB_DEPS"
echo "escalate: filed visit $id on $subj [$key]"
ESC
chmod +x "$TMP/escalate-stub"
export GC_ESCALATE_TOOL="$TMP/escalate-stub"

POOL="gc-toolkit/gc-toolkit.polecat"
PARKER="lx-park"
CLAIMER="lx-claim"

roster() { # <session-id>... — the active roster
  local s rows=""
  for s in "$@"; do
    rows="${rows:+$rows,}{\"id\":\"$s\",\"session_name\":\"gc-toolkit__polecat-$s\",\"alias\":\"\",\"state\":\"active\"}"
  done
  printf '{"sessions":[%s]}' "$rows" > "$TMP/sessions.json"
  export STUB_SESSIONS="$TMP/sessions.json"
}
as_session() { export GC_SESSION_ID="$1" GC_SESSION_NAME="gc-toolkit__polecat-$1"; }

# A mol-polecat-work molecule claimed by the parker at load-context, poured for
# tk-work through input convoy tk-conv, its steps chained by blocks edges.
molecule() {
  store '[
    {"id":"tk-root","status":"in_progress","assignee":"","title":"mol-polecat-work",
     "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"tk-conv",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_name":"gc-toolkit__polecat-lx-park"}},
    {"id":"tk-load","status":"in_progress","assignee":"lx-park","title":"Load context",
     "metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"tk-root",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require","gc.session_id":"lx-park"}},
    {"id":"tk-impl","status":"open","assignee":"lx-park","title":"Implement",
     "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
    {"id":"tk-submit","status":"open","assignee":"","title":"Submit",
     "metadata":{"gc.step_ref":"mol-polecat-work.submit-and-exit","gc.root_bead_id":"tk-root","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
    {"id":"tk-final","status":"open","assignee":"","title":"Finalize workflow",
     "metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.root_bead_id":"tk-root","gc.routed_to":"core.control-dispatcher"}},
    {"id":"tk-work","status":"open","assignee":"","title":"the work","metadata":{}},
    {"id":"tk-conv","status":"open","assignee":"","title":"input convoy for tk-work","metadata":{}},
    {"id":"tk-other","status":"open","assignee":"","title":"unrelated","metadata":{}}
  ]'
  printf 'tk-conv|tracks|tk-work\ntk-load|blocks|tk-impl\ntk-impl|blocks|tk-submit\ntk-submit|blocks|tk-final\n' > "$STUB_DEPS"
  : > "$STUB_GC_LOG"; : > "$ESC_LOG"
  roster "$PARKER"; as_session "$PARKER"
}

end_bead() { jq -r '[ .[] | select((.metadata["gc.step_ref"] // "") == "molecule-end") | .id ] | join(",")' "$STUB_STORE"; }
blockers() { awk -F'|' -v id="$1" '$2 == "blocks" && $3 == id { print $1 }' "$STUB_DEPS" | sort | paste -sd, -; }
# The pool's offer: open, unassigned, routed, and every blocks blocker closed.
offered() {
  local b
  [ "$(bstatus "$1")" = "open" ] && [ -z "$(bassignee "$1")" ] && [ "$(meta "$1" gc.routed_to)" != "<absent>" ] || { echo no; return; }
  for b in $(awk -F'|' -v id="$1" '$2 == "blocks" && $3 == id { print $1 }' "$STUB_DEPS"); do
    [ "$(bstatus "$b")" = "closed" ] || { echo no; return; }
  done
  echo yes
}
claim() { gc bd update "$1" --status=in_progress --assignee "$2" --set-metadata "gc.session_id=$2" >/dev/null; }
close_bead() { gc bd update "$1" --status=closed >/dev/null; }
MEMBERS="tk-root tk-load tk-impl tk-submit tk-final"

park() { "$HOLD_SH" --step mol-polecat-work.load-context --bead tk-load --reason "premise falsified: $1" 2>&1; }

echo "--- park on open work: the end is armed, nothing ends ---"
molecule
OUT=$(park "the work is moot"); rc=$?
eq "$rc" "0" "the hold exits 0, so the parker drains"
has "$OUT" "result=armed" "molecule-end.sh armed the end before the hold"
END=$(end_bead)
[ -n "$END" ] && [ "${END#*,}" = "$END" ] && ok "exactly one end bead was created ($END)" || bad "one end bead expected, got '$END'"
eq "$(meta "$END" gc.root_bead_id)" "tk-root" "the end bead is a member of the molecule"
eq "$(meta "$END" gc.step_ref)" "molecule-end" "the end bead carries the molecule-end step ref"
eq "$(meta "$END" gc.routed_to)" "$POOL" "the end bead is routed to the pool the held step ran on"
eq "$(blockers "$END")" "tk-work" "the end bead is blocked by the work, and only by it"
eq "$(bstatus "$END")" "open" "the end bead is open"
eq "$(offered "$END")" "no" "no pool is offered the end while the work is open"
eq "$(bstatus tk-load)" "blocked" "the held step is held"
eq "$(meta tk-impl gc.routed_to)" "<absent>" "the rest of the molecule is quiesced"
for B in $MEMBERS; do [ "$(bstatus "$B")" != "closed" ] || bad "$B was closed by a park on open work"; done
ok "nothing in the molecule closed"
has "$(jq -r --arg id "$END" '.[] | select(.id == $id) | .description' "$STUB_STORE")" "molecule-end.sh" "the end bead states its method"

# Route-before-blockers would make the end bead offerable for an instant.
CREATE_L=$(grep -n "bd create" "$STUB_GC_LOG" | head -1 | cut -d: -f1)
EDGE_L=$(grep -n "bd dep add $END tk-work" "$STUB_GC_LOG" | head -1 | cut -d: -f1)
ROUTE_L=$(grep -n "bd update $END --set-metadata gc.routed_to" "$STUB_GC_LOG" | head -1 | cut -d: -f1)
if [ -n "$CREATE_L" ] && [ -n "$EDGE_L" ] && [ -n "$ROUTE_L" ] && [ "$CREATE_L" -lt "$EDGE_L" ] && [ "$EDGE_L" -lt "$ROUTE_L" ]; then
  ok "the end bead is created, then blocked, then routed"
else
  bad "create/edge/route out of order (create=$CREATE_L edge=$EDGE_L route=$ROUTE_L)"
fi
hasnt "$(head -n "$CREATE_L" "$STUB_GC_LOG" | tail -1)" "gc.routed_to" "the end bead is created unrouted"

echo "--- an open source leaves the parked molecule as it is ---"
OUT=$("$END_SH" "$END" 2>&1); rc=$?
eq "$rc" "0" "an end run while the work is open exits 0"
has "$OUT" "result=armed" "it only re-arms"
eq "$(bstatus tk-root)" "in_progress" "the root stays"
eq "$(bstatus tk-load)" "blocked" "the held step stays held"
eq "$(end_bead)" "$END" "no second end bead"

echo "--- the work closes, whichever writer closes it: the end is offered, and its run ends the molecule ---"
close_bead tk-work
eq "$(offered "$END")" "yes" "the pool is offered the end once the work closes"
roster "$CLAIMER"; as_session "$CLAIMER"; claim "$END" "$CLAIMER"
: > "$STUB_GC_LOG"
OUT=$("$END_SH" "$END" 2>&1); rc=$?
eq "$rc" "0" "the end run exits 0"
has "$OUT" "result=ended" "the molecule ended"
for B in $MEMBERS "$END"; do eq "$(bstatus "$B")" "closed" "$B is closed"; done
for B in tk-load tk-impl tk-submit "$END"; do eq "$(meta "$B" gc.routed_to)" "<absent>" "$B is de-routed"; done
eq "$(bstatus tk-conv)" "open" "the input convoy is never written"
hasnt "$(grep -- 'bd update tk-work' "$STUB_GC_LOG")" "update" "the work bead is never written"
eq "$(bstatus tk-other)" "open" "a bead outside the molecule is untouched"

echo "--- park after close: a hold on work already closed ends the molecule there ---"
molecule
close_bead tk-work
: > "$STUB_GC_LOG"
OUT=$(park "already closed"); rc=$?
eq "$rc" "0" "the hold exits 0"
has "$OUT" "result=ended" "molecule-end.sh ended it"
has "$OUT" "nothing left to hold" "and the hold says it had nothing to do"
for B in $MEMBERS; do eq "$(bstatus "$B")" "closed" "$B is closed"; done
eq "$(end_bead)" "" "no end bead is armed"
hasnt "$(cat "$STUB_GC_LOG")" "--status=blocked" "no hold is written over the ended molecule"
has "$(notes tk-load)" "besides the caller" "the parker's own claim was set aside, and the note says so"

echo "--- the disposer's refusals still hold, each as a wait ---"
# A live session: another session holds a member when the end runs.
molecule; park "x" >/dev/null 2>&1; END=$(end_bead)
close_bead tk-work
gc bd update tk-impl --status=in_progress --assignee lx-other --set-metadata gc.session_id=lx-other >/dev/null
roster "$CLAIMER" lx-other; as_session "$CLAIMER"; claim "$END" "$CLAIMER"
OUT=$("$END_SH" "$END" 2>&1); rc=$?
eq "$rc" "0" "a live session refusal exits 0"
has "$OUT" "result=live" "a live session owns the end"
eq "$(bstatus tk-root)" "in_progress" "the molecule stays while a live session holds it"
eq "$(bstatus tk-impl)" "in_progress" "the live session's step is untouched"
eq "$(bstatus "$END")" "closed" "the claimed end bead is retired, so it is not offered again and again"
eq "$(meta "$END" gc.work_outcome)" "no-op" "the retire records no work"
# An open escalation: a visit filed after the arm.
molecule; park "x" >/dev/null 2>&1; END=$(end_bead)
jq -c '. + [{"id":"tk-visit","status":"open","assignee":"","title":"visit","metadata":{"escalation_key":"polecat-premise","task_kind":"visit"}}]' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
printf 'tk-visit|tracks|tk-work\n' >> "$STUB_DEPS"
close_bead tk-work
roster "$CLAIMER"; as_session "$CLAIMER"; claim "$END" "$CLAIMER"
: > "$STUB_GC_LOG"
OUT=$("$END_SH" "$END" 2>&1); rc=$?
eq "$rc" "0" "an open escalation refusal exits 0"
has "$OUT" "result=armed" "the end is re-armed"
has "$OUT" "waits_on=tk-visit" "on the open visit"
eq "$(blockers "$END")" "tk-visit,tk-work" "the visit joined the end bead's blockers"
eq "$(bstatus "$END")" "open" "the end bead is reopened"
eq "$(bassignee "$END")" "" "and released"
eq "$(meta "$END" gc.routed_to)" "$POOL" "with its route kept"
eq "$(offered "$END")" "no" "no pool is offered it while the visit is open"
eq "$(bstatus tk-root)" "in_progress" "the molecule stays while a person owns the decision"
E_L=$(grep -n "bd dep add $END tk-visit" "$STUB_GC_LOG" | head -1 | cut -d: -f1)
O_L=$(grep -n "bd update $END --status=open" "$STUB_GC_LOG" | head -1 | cut -d: -f1)
A_L=$(grep -n "bd update $END --assignee" "$STUB_GC_LOG" | head -1 | cut -d: -f1)
if [ -n "$E_L" ] && [ -n "$O_L" ] && [ -n "$A_L" ] && [ "$E_L" -lt "$O_L" ] && [ "$O_L" -lt "$A_L" ]; then
  ok "re-armed edge first, then reopened, then released"
else
  bad "re-arm out of order (edge=$E_L open=$O_L assignee=$A_L)"
fi
close_bead tk-visit
eq "$(offered "$END")" "yes" "the end is offered once the visit closes"
claim "$END" "$CLAIMER"
OUT=$("$END_SH" "$END" 2>&1)
has "$OUT" "result=ended" "and its run ends the molecule"
eq "$(bstatus tk-root)" "closed" "the root closes"
# Work still open and mid-PR: the end waits on it and never asks the disposer.
molecule
gc bd update tk-work --set-metadata merge_result=pull_request --set-metadata pr_number=77 >/dev/null
: > "$STUB_GC_LOG"
OUT=$(park "duplicate of a live PR"); rc=$?
eq "$rc" "0" "a hold on work mid-PR exits 0"
has "$OUT" "waits_on=tk-work" "the end waits on the work mid-PR"
hasnt "$(cat "$STUB_GC_LOG")" "--status=closed" "nothing closes while the work is mid-PR"
# A refusal the disposer would repeat files a visit, and the end waits on it.
molecule; park "x" >/dev/null 2>&1; END=$(end_bead)
gc bd update tk-submit --set-metadata branch=polecat/tk-odd >/dev/null
close_bead tk-work
roster "$CLAIMER"; as_session "$CLAIMER"; claim "$END" "$CLAIMER"
OUT=$("$END_SH" "$END" 2>&1); rc=$?
eq "$rc" "0" "a structural refusal exits 0"
has "$(cat "$ESC_LOG")" "tk-root molecule-end-tk-root" "a visit keyed to the molecule is filed on its root"
has "$OUT" "waits_on=visit-molecule-end-tk-root" "the end waits on that visit"
eq "$(bstatus tk-root)" "in_progress" "the molecule stays for the person"
molecule; park "x" >/dev/null 2>&1; END=$(end_bead)
gc bd update tk-submit --set-metadata branch=polecat/tk-odd >/dev/null
close_bead tk-work
roster "$CLAIMER"; as_session "$CLAIMER"; claim "$END" "$CLAIMER"
OUT=$(FAKE_ESC_RC=1 "$END_SH" "$END" 2>&1); rc=$?
eq "$rc" "1" "a structural refusal with no visit filed exits 1"
eq "$(bstatus "$END")" "in_progress" "and the end bead is left with its claimant"

echo "--- work reopened between the read and the end keeps the end waiting on it ---"
molecule; park "x" >/dev/null 2>&1; END=$(end_bead)
close_bead tk-work
roster "$CLAIMER"; as_session "$CLAIMER"; claim "$END" "$CLAIMER"
# The second show of tk-work, the disposer's, finds it reopened.
export SHOW_COUNT="$TMP/show-count"; : > "$SHOW_COUNT"
cat > "$TMP/reopen-hook" <<'HOOK'
#!/usr/bin/env bash
[ "${1:-}" = "tk-work" ] || exit 0
echo x >> "${SHOW_COUNT:?}"
[ "$(wc -l < "$SHOW_COUNT")" -ge 2 ] || exit 0
jq -c 'map(if .id == "tk-work" then .status = "open" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
HOOK
chmod +x "$TMP/reopen-hook"
OUT=$(STUB_SHOW_HOOK="$TMP/reopen-hook" "$END_SH" "$END" 2>&1); rc=$?
eq "$rc" "0" "a source reopened mid-run exits 0"
has "$OUT" "result=armed" "the end is re-armed rather than run"
has "$OUT" "waits_on=tk-work" "on the reopened work"
eq "$(bstatus tk-root)" "in_progress" "the molecule stays"
eq "$(bstatus "$END")" "open" "the end bead goes back to waiting"
eq "$(bassignee "$END")" "" "released by its claimant"

echo "--- a visit already open at the arm is a blocker from the start ---"
molecule
jq -c '. + [{"id":"tk-visit","status":"open","assignee":"","title":"visit","metadata":{"escalation_key":"polecat-premise","task_kind":"visit"}}]' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
printf 'tk-visit|tracks|tk-work\n' >> "$STUB_DEPS"
park "x" >/dev/null 2>&1; END=$(end_bead)
eq "$(blockers "$END")" "tk-visit,tk-work" "the end waits on the work and on the open visit"
# Escalate-then-hold on work already closed: the visit holds the end, and the
# molecule is held behind it.
molecule
jq -c '. + [{"id":"tk-visit","status":"open","assignee":"","title":"visit","metadata":{"escalation_key":"polecat-premise","task_kind":"visit"}}]' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
printf 'tk-visit|tracks|tk-work\n' >> "$STUB_DEPS"
close_bead tk-work
OUT=$(park "x"); rc=$?
eq "$rc" "0" "a hold on closed work with an open visit exits 0"
END=$(end_bead)
eq "$(blockers "$END")" "tk-visit" "the end waits on the visit"
eq "$(bstatus tk-load)" "blocked" "the molecule is held behind it"
eq "$(bstatus tk-root)" "in_progress" "and not ended while a person owns it"

echo "--- idempotence: a second hold re-uses the end bead ---"
molecule
park "x" >/dev/null 2>&1; FIRST=$(end_bead)
OUT=$(park "again"); rc=$?
eq "$rc" "0" "the re-hold exits 0"
eq "$(end_bead)" "$FIRST" "the molecule still has exactly one end bead"
eq "$(meta "$FIRST" gc.routed_to)" "$POOL" "the re-hold's quiesce leaves the end bead routed"

echo "--- any formula: a mol-validate molecule poured for a validation pass ---"
store '[
  {"id":"tk-vroot","status":"in_progress","assignee":"","title":"mol-validate",
   "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"tk-vconv","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-vload","status":"in_progress","assignee":"lx-park","title":"Load dispatch",
   "metadata":{"gc.step_ref":"mol-validate.load-dispatch","gc.root_bead_id":"tk-vroot","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-vtriage","status":"open","assignee":"lx-park","title":"Triage",
   "metadata":{"gc.step_ref":"mol-validate.triage-findings","gc.root_bead_id":"tk-vroot","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-pass","status":"open","assignee":"","title":"validation pass","metadata":{"task_kind":"validation","anchor_bead":"tk-anchor"}},
  {"id":"tk-vconv","status":"open","assignee":"","title":"input convoy for tk-pass","metadata":{}}
]'
printf 'tk-vconv|tracks|tk-pass\ntk-vload|blocks|tk-vtriage\n' > "$STUB_DEPS"
roster "$PARKER"; as_session "$PARKER"
OUT=$("$HOLD_SH" --step mol-validate.load-dispatch --bead tk-vload --reason "pass is moot" 2>&1); rc=$?
eq "$rc" "0" "a mol-validate hold exits 0"
END=$(end_bead)
eq "$(blockers "$END")" "tk-pass" "its end waits on the validation pass"
close_bead tk-pass
roster "$CLAIMER"; as_session "$CLAIMER"; claim "$END" "$CLAIMER"
OUT=$("$END_SH" "$END" 2>&1)
has "$OUT" "result=ended" "the pass closing ends the mol-validate molecule"
eq "$(bstatus tk-vroot)" "closed" "the mol-validate root closes"
eq "$(bstatus tk-vtriage)" "closed" "its steps close"

echo "--- unbound: a molecule with no single source is held as before ---"
molecule
jq -c 'map(if .id=="tk-root" then (.metadata |= del(.["gc.input_convoy_id"])) else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$(park "x"); rc=$?
eq "$rc" "0" "an unbound molecule is held, exit 0"
has "$OUT" "result=unbound" "and reported unbound"
eq "$(end_bead)" "" "no end bead is armed"
eq "$(bstatus tk-load)" "blocked" "the step is held"

echo "--- the pool falls back from the step to the root to the caller's template ---"
molecule
jq -c 'map(if .id=="tk-load" then (.metadata |= del(.["gc.routed_to"])) else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
"$END_SH" tk-load >/dev/null 2>&1
eq "$(meta "$(end_bead)" gc.routed_to)" "$POOL" "an unrouted step takes the root's route"
molecule
jq -c 'map(if .id=="tk-load" or .id=="tk-root" then (.metadata |= del(.["gc.routed_to"])) else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
GC_TEMPLATE="gc-toolkit/gc-toolkit.polecat-codex" "$END_SH" tk-load >/dev/null 2>&1
eq "$(meta "$(end_bead)" gc.routed_to)" "gc-toolkit/gc-toolkit.polecat-codex" "with neither routed, the caller's pool template"
molecule
jq -c 'map(if .id=="tk-load" or .id=="tk-root" then (.metadata |= del(.["gc.routed_to"])) else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
OUT=$("$END_SH" tk-load 2>&1); rc=$?
eq "$rc" "1" "no pool at all exits 1"
has "$OUT" "detail=no_route" "and names why"
eq "$(end_bead)" "" "and creates nothing"

echo "--- failed writes leave nothing offerable ---"
molecule
export STUB_CREATE_FAIL=1
OUT=$("$END_SH" tk-load 2>&1); rc=$?
export STUB_CREATE_FAIL=""
eq "$rc" "1" "a refused create exits 1"
has "$OUT" "create_failed" "and names it"
molecule
OUT=$(STUB_CREATE_FAIL=1 park "x"); rc=$?
eq "$rc" "1" "a hold whose end could not be armed exits 1, so the parker does not drain"
eq "$(bstatus tk-load)" "blocked" "the hold itself still landed"
molecule
# A gc ahead of the stub on PATH that refuses every `bd dep add`.
mkdir -p "$TMP/refbin"
cat > "$TMP/refbin/gc" <<'REF'
#!/usr/bin/env bash
case "$*" in "bd dep add "*) echo "gc bd dep: simulated refusal" >&2; exit 1 ;; esac
exec "$REAL_GC" "$@"
REF
chmod +x "$TMP/refbin/gc"
OUT=$(REAL_GC="$TMP/bin/gc" PATH="$TMP/refbin:$PATH" "$END_SH" tk-load 2>&1); rc=$?
eq "$rc" "1" "a refused blocks edge exits 1"
has "$OUT" "edge_failed=tk-work" "and names the blocker"
eq "$(meta "$(end_bead)" gc.routed_to)" "<absent>" "the end bead was never routed, so no pool is offered it"
molecule; close_bead tk-work
export STUB_CLOSE_FAIL="tk-impl"
OUT=$("$END_SH" tk-load 2>&1); rc=$?
export STUB_CLOSE_FAIL=""
eq "$rc" "1" "a teardown that closed only part of the molecule exits 1"
has "$OUT" "detail=partial" "and says the teardown was partial"
eq "$(meta tk-impl gc.routed_to)" "<absent>" "the member that did not close is de-routed, so no pool is offered it"

echo "--- dry run writes nothing ---"
molecule
OUT=$("$END_SH" tk-load --dry-run 2>&1); rc=$?
eq "$rc" "0" "a dry run exits 0"
has "$OUT" "result=would_arm" "an open source would arm"
eq "$(end_bead)" "" "and nothing is created"
close_bead tk-work
: > "$STUB_GC_LOG"
OUT=$("$END_SH" tk-load --dry-run 2>&1)
has "$OUT" "result=would_end" "a closed source would end"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "and nothing is written"

echo "--- usage and unreadable input ---"
"$END_SH" >/dev/null 2>&1; eq "$?" "2" "no bead id exits 2"
"$END_SH" tk-load --nope >/dev/null 2>&1; eq "$?" "2" "an unknown flag exits 2"
"$END_SH" tk-load tk-impl >/dev/null 2>&1; eq "$?" "2" "a second bead id exits 2"
molecule
OUT=$("$END_SH" tk-other 2>&1); rc=$?
eq "$rc" "1" "a bead that names no molecule exits 1"
has "$OUT" "not_a_molecule" "and says so"
molecule
export STUB_DEP_GARBAGE=1
OUT=$("$END_SH" tk-load 2>&1); rc=$?
export STUB_DEP_GARBAGE=""
eq "$rc" "1" "an unreadable convoy exits 1"
has "$OUT" "convoy_unreadable=tk-conv" "and names the convoy"
eq "$(end_bead)" "" "and arms nothing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
