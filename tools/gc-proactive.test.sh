#!/usr/bin/env bash
# Hermetic test for tools/gc-proactive.sh: the refusals the `sling` verb reads
# before it slings a run of mol-first-reaction on a subject, the reaction's own
# check of them (--check --run), what gc sling's own refusal leads to, the
# scan's candidate filter and in-flight drop, the --sling sweep's deadline and
# count, and the deliverable and assignable answers the first reaction's exits
# ask before they hand a bead on.
#
# A first reaction triages a bead nobody has decided on, so the sling refuses a
# subject whose next move is someone's already. Each refusal has its code:
#   (KIND-*)     a standing record or a feedback pattern takes no first
#                reaction (6), and the scan offers neither
#   (ROW-*)      a status other than open, or an assignee (5)
#   (PATH-*)     a route or an arm, the human park route among them (5); blank
#                keys, an execution stamp and a wait on open work are none
#   (HOLD-*)     hold:mayor or hold:external in any case (5); the retired
#                placement marker holds nothing
#   (GATE-*)     an open human gate, on the bead or above it, as `gctk bead
#                holds` lists its waits (5)
#   (CONV-*)     an open conversation that tracks the bead (3); a closed one,
#                and a task that tracks more than the bead, are none
#   (LIVE-*)     a live run of mol-first-reaction (3), or of another formula
#                (4); a pour Gas City left unfinished is no run
#   (CHECK-*)    the reaction's own first act: the same refusals, writing
#                nothing, its own run and its own first-reaction gate passed
#                over
# The scan:
#   (STEP-*)     a molecule step, a first reaction's own included, is no
#                candidate
#   (DISPATCH-*, ARMED-*)  a bead with a dispatch path is no candidate
#   (INFLIGHT-*) a bead a live run works is no candidate, unless that run is an
#                unfinished pour of mol-first-reaction
#   (AGREE-*)    the scan's drop and the sling's refusal agree on one store
#   (SWEEP-*)    a sweep slings every candidate with no cap, counts only what
#                it slung, names each refusal's cause, fails closed with no rig
#                context, skips a rig whose pool cannot take a reaction, and
#                stops before its deadline
#   (READ-*, PAGE-*)  a ready read that fails, or a page the filter cannot
#                build, fails the scan
# gc sling's own refusal (exit 3) passes through when it names a live reaction,
# and files a human gate when every root it names is an unfinished pour
# (CONFLICT-*). The live read paths run against a stub gc and a stub gctk that
# answer each read in its own shape (*-READS).
#
# gc-proactive.sh is a bash script (process substitution), so it is invoked via
# bash, not sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-proactive.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-proactive-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-proactive.sh present" || bad "gc-proactive.sh missing at $SCRIPT"

# A fixture dir short-circuits every gc call: scan reads scan.json, the sling's
# reads answer from beads.json (rows keyed by id) and holds.json (`gctk bead
# holds` lines keyed by id), run-lib.sh's verbs answer from runs.json, and a
# sling that passes the refusals prints the gc sling it would run rather than
# running it.
export GC_PROACTIVE_FIXTURE="$TMP"

# runs_of <rows-file>... — write runs.json, the runs the rows' workflow roots
# and convoys make, by run-lib.sh's own run_rows.
# shellcheck source=../assets/scripts/run-lib.sh
. "$HERE/../assets/scripts/run-lib.sh"
runs_of() { jq -s 'add' "$@" | jq -c "$RUN_JQ"'run_rows' > "$TMP/runs.json"; }

# gc-proactive.sh rig-qualifies its pool target from GC_RIG (resolve_pool_target
# is a pure string join, not a gc call) and fails closed when it is unset. The
# fixture replaces gc, not that rig context, so pin GC_RIG here: left to the
# ambient city it reads green locally and fails a sling on the bare CI runner,
# which has no GC_RIG.
export GC_RIG=gc-toolkit

# sling <bead> [args...] -> OUT (stdout and stderr), RC
sling() { set +e; OUT="$(bash "$SCRIPT" sling "$@" 2>&1)"; RC=$?; set -e; }
# store_of <scan-file> — beads.json holding every row of a scan page, so the
# sling's own row read finds each bead a sweep reaches.
store_of() { jq 'map({key: .id, value: .}) | from_entries' "$1" > "$TMP/beads.json"; }
WOULD="would sling a first reaction on"

echo "# a bead that nothing has decided on is slung"
cat > "$TMP/beads.json" <<'JSON'
{"tk-plain": {"issue_type":"task","status":"open","metadata":{}}}
JSON
sling tk-plain
eq "$RC" 0 "(SLING-GO) sling of an undecided bead exits 0"
has "$OUT" "$WOULD tk-plain -> gc-toolkit/gc-toolkit.proactive" "(SLING-GO) …and slings the reaction (fixture line)"
has "$OUT" "gc sling --rig gc-toolkit gc-toolkit/gc-toolkit.proactive tk-plain --on mol-first-reaction" "(SLING-GO) …as a run of mol-first-reaction at the rig's proactive pool"
sling tk-plain --dry-run --nudge
eq "$RC" 0 "(DRY-RUN) --dry-run exits 0"
has "$OUT" "gc sling --rig gc-toolkit gc-toolkit/gc-toolkit.proactive tk-plain --on mol-first-reaction --nudge" "(DRY-RUN) …printing the sling it would run, --nudge passed to gc sling"
hasnt "$OUT" "$WOULD" "(DRY-RUN) …and slinging nothing"

echo "# a bead the store does not hold is an error, not a refusal"
sling tk-nosuch
eq "$RC" 1 "(SUBJECT-ABSENT) sling of a bead beads.json does not list exits 1"
has "$OUT" "cannot read tk-nosuch's own row" "(SUBJECT-ABSENT) …saying why"
hasnt "$OUT" "$WOULD" "(SUBJECT-ABSENT) …nothing slung"

echo "# usage"
for args in "" "tk-plain --check" "tk-plain --run tk-root" "tk-plain --check --run tk-root --dry-run" "tk-plain --check --run tk-root --nudge" "tk-plain tk-other" "tk-plain --bogus"; do
    # shellcheck disable=SC2086  # each case is its own words
    sling $args
    eq "$RC" 2 "(USAGE) sling $args is a usage error (exit 2)"
done

# --- the subject's kind ------------------------------------------------------
# A standing record (a task_kind assets/scripts/standing-kinds.sh lists) is open,
# unrouted and unassigned by design and never closes, so a first reaction has no
# disposition to make on it. The feedback distiller decides every pattern bd
# ready lists. The kinds are read from the shared definition, so a kind added
# there is covered here with no edit to this file.
# shellcheck source=../assets/scripts/standing-kinds.sh
. "$HERE/../assets/scripts/standing-kinds.sh"
KINDS="$(jq -nr "$STANDING_KINDS_JQ"'standing_kinds[]')"
[ -n "$KINDS" ] && ok "(KIND) the shared definition lists the standing kinds" \
    || bad "(KIND) the shared definition lists the standing kinds (read back empty)"
jq -n --arg kinds "$KINDS" '
  [{"id":"tk-raw", "issue_type":"task", "description":"a raw input bead", "title":"raw input", "metadata":{}},
   {"id":"tk-pattern", "issue_type":"task", "description":"a recurring feedback pattern", "title":"pattern", "metadata":{"task_kind":"feedback-pattern"}}]
  + [ $kinds | split("\n")[] | select(length > 0)
      | {"id": ("tk-standing-" + .), "issue_type": "task", "description": "a standing record",
         "title": ("standing " + .), "metadata": {"task_kind": .}} ]' > "$TMP/scan.json"
store_of "$TMP/scan.json"

echo "# the scan offers neither kind"
IDS="$(bash "$SCRIPT" scan --json 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-raw" "(KIND-KEEP) a raw input beside them is still a candidate"
hasnt "$IDS" "tk-pattern" "(KIND-DROP) a feedback pattern is not a scan candidate"
for k in $KINDS; do
    hasnt "$IDS" "tk-standing-$k" "(KIND-DROP) a task_kind=$k standing record is not a scan candidate"
done
echo "# the sling refuses either kind named to it"
for k in $KINDS; do
    sling "tk-standing-$k"
    eq "$RC" 6 "(KIND-SKIP) sling of a task_kind=$k standing record exits 6"
    has "$OUT" "it is a standing record (task_kind=$k)" "(KIND-SKIP) …naming the kind"
    hasnt "$OUT" "$WOULD" "(KIND-SKIP) …nothing slung"
done
sling tk-pattern
eq "$RC" 6 "(KIND-SKIP) sling of a feedback pattern exits 6"
has "$OUT" "it is a feedback pattern, which the feedback distiller dispatches" "(KIND-SKIP) …naming whose it is"
hasnt "$OUT" "$WOULD" "(KIND-SKIP) …nothing slung"

# --- the subject's own row ---------------------------------------------------
# A route or an arm already decides a bead's dispatch. An armed bead is ready,
# unassigned and unrouted from its own blockers' close until the next
# deferred-dispatch pass, so the arm is all that sets it apart from raw input.
# tk-armed carries the record gctk bead arm writes. tk-capped is an arm the
# start stopped retrying at its failure cap, which waits on the human gate the
# cap filed. One more bead per dispatch-path key carries only that key. The keys
# are read from the shared definition, so a key added there is covered here with
# no edit to this file. tk-blank carries every key with a blank value, which
# names no queue and no sling target, so it is raw input like tk-raw. All pass
# every other clause (task type, a description, no work markers, top-level).
# shellcheck source=../assets/scripts/dispatch-path.sh
. "$HERE/../assets/scripts/dispatch-path.sh"
PATH_KEYS="$(jq -nr "$DISPATCH_PATH_JQ"'dispatch_path_keys[]')"
[ -n "$PATH_KEYS" ] && ok "(DISPATCH) the shared definition lists the dispatch-path keys" \
    || bad "(DISPATCH) the shared definition lists the dispatch-path keys (read back empty)"
jq -n --arg keys "$PATH_KEYS" '
  ($keys | split("\n") | map(select(length > 0))) as $k
  | [ {"id":"tk-raw",    "issue_type":"task", "description":"a raw input bead", "title":"raw input", "metadata":{}},
      {"id":"tk-armed",  "issue_type":"task", "description":"a blocked follow-up armed by hand", "title":"armed follow-up",
       "metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_armed_by":"gc-toolkit/gc-toolkit.mechanik","gc.dispatch_when_ready_armed_at":"2026-10-01T00:00:00Z","gc.dispatch_when_ready_reason":"waits for tk-blocker to land"}},
      {"id":"tk-capped", "issue_type":"task", "description":"an arm past its failure cap", "title":"capped arm",
       "metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_fail_count":3}},
      {"id":"tk-blank",  "issue_type":"task", "description":"dispatch-path keys left blank", "title":"blank keys",
       "metadata": ($k | map({key: ., value: " "}) | from_entries)} ]
    + [ $k[] | {"id": ("tk-path-" + .), "issue_type": "task", "description": "a bead with a dispatch path",
                "title": ("dispatch path " + .), "metadata": {(.): "gc-toolkit/gc-toolkit.polecat"}} ]' > "$TMP/scan.json"

echo "# the scan drops a bead with a dispatch path, keeps raw input"
IDS="$(bash "$SCRIPT" scan --json 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-raw" "(DISPATCH-KEEP) a raw input beside the routed and armed beads is still a candidate"
has "$IDS" "tk-blank" "(DISPATCH-KEEP) …and so is a bead whose dispatch-path keys are blank"
for k in $PATH_KEYS; do
    hasnt "$IDS" "tk-path-$k" "(DISPATCH-DROP) a bead carrying $k is not a scan candidate"
done
hasnt "$IDS" "tk-armed" "(ARMED-DROP) an armed bead is not a scan candidate"
hasnt "$IDS" "tk-capped" "(ARMED-DROP) …nor an arm the start stopped retrying"

store_of "$TMP/scan.json"
echo "# a scan --sling sweep reacts to raw input and never to a bead with a dispatch path"
set +e
OUT="$(bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ARMED-SWEEP) the sweep exits 0"
has "$OUT" "$WOULD tk-raw" "(ARMED-SWEEP) the sweep slings a first reaction at the raw input"
hasnt "$OUT" "$WOULD tk-armed" "(ARMED-SWEEP) …and none at the armed bead"
hasnt "$OUT" "$WOULD tk-capped" "(ARMED-SWEEP) …nor at the capped arm"
for k in $PATH_KEYS; do
    hasnt "$OUT" "$WOULD tk-path-$k" "(ARMED-SWEEP) …nor at the bead carrying $k"
done

# The scan never offers a routed or armed bead, but gc-helm react, a patrol
# finding and operator-intake name a bead to the sling directly. beads.json is
# the store: every scan row above, plus these shapes:
#   tk-human            parked on the human route, which is a route too
#   tk-exec-only        only the gc.execution_routed_to a pour leaves, which no
#                       queue reads
#   tk-work-blocked     open work blocks it, which is no refusal
#   tk-closed / tk-wip  a status other than open
#   tk-assigned         an assignee
jq '(map({key: .id, value: .}) | from_entries)
    + {"tk-human":        {"metadata": {"gc.routed_to": "human"}},
       "tk-exec-only":    {"metadata": {"gc.execution_routed_to": "gc-toolkit/gc-toolkit.polecat"}},
       "tk-work-blocked": {"metadata": {}},
       "tk-closed":       {"status": "closed", "metadata": {}},
       "tk-wip":          {"status": "in_progress", "metadata": {}},
       "tk-assigned":     {"assignee": "gc-toolkit/gc-toolkit.polecat-3", "metadata": {}}}' \
    "$TMP/scan.json" > "$TMP/beads.json"
cat > "$TMP/holds.json" <<'JSON'
{"tk-work-blocked": {"id":"tk-work-blocked","status":"blocked","waits":[{"id":"tk-work","type":"blocks","title":"open work","status":"open","issue_type":"task"}],"pending":["tk-work"]}}
JSON

echo "# sling refuses a routed or armed bead, naming the path"
for k in $PATH_KEYS; do
    sling "tk-path-$k"
    eq "$RC" 5 "(PATH-SKIP) sling of a bead carrying $k exits 5"
    has "$OUT" "already has a dispatch path ($k=gc-toolkit/gc-toolkit.polecat)" "(PATH-SKIP) …naming the key and its value"
    hasnt "$OUT" "$WOULD" "(PATH-SKIP) …nothing slung"
done
for b in tk-armed tk-capped tk-human; do
    sling "$b"
    eq "$RC" 5 "(PATH-SKIP) sling of $b exits 5"
    hasnt "$OUT" "$WOULD" "(PATH-SKIP) …nothing slung for $b"
done
sling tk-human
has "$OUT" "gc.routed_to=human" "(PATH-SKIP) the human park route is named as the path"

echo "# a status other than open, or an assignee, decides the bead"
for b in tk-closed:closed tk-wip:in_progress; do
    sling "${b%%:*}"
    eq "$RC" 5 "(ROW-STATUS) sling of a ${b#*:} bead exits 5"
    has "$OUT" "its status is ${b#*:}" "(ROW-STATUS) …naming the status"
    hasnt "$OUT" "$WOULD" "(ROW-STATUS) …nothing slung"
done
sling tk-assigned
eq "$RC" 5 "(ROW-ASSIGNEE) sling of an assigned bead exits 5"
has "$OUT" "it is assigned to gc-toolkit/gc-toolkit.polecat-3" "(ROW-ASSIGNEE) …naming the assignee"
hasnt "$OUT" "$WOULD" "(ROW-ASSIGNEE) …nothing slung"

echo "# blank keys, an execution stamp and a wait on open work are no refusal"
for b in tk-blank tk-exec-only tk-work-blocked; do
    sling "$b"
    eq "$RC" 0 "(PATH-GO) sling of $b exits 0"
    has "$OUT" "$WOULD $b" "(PATH-GO) …and slings a reaction"
done
rm -f "$TMP/holds.json"

# --- a person's answer -------------------------------------------------------
# An open human gate holds the bead until a person answers it, and that answer
# decides what happens to the bead. `gctk bead holds` lists the waits behind a
# bead's status, a gate on an ancestor of work not yet started among them, and
# the sling refuses a bead any open human gate among them holds. A gate a person
# answered, or a gate of another await type, is no refusal.
cat > "$TMP/beads.json" <<'JSON'
{"tk-gated": {"metadata":{}}, "tk-under": {"metadata":{}}, "tk-answered": {"metadata":{}}, "tk-timer": {"metadata":{}}}
JSON
cat > "$TMP/holds.json" <<'JSON'
{"tk-gated":    {"id":"tk-gated","status":"blocked","waits":[{"id":"tk-gate-open","type":"blocks","title":"Rule on it","status":"open","issue_type":"gate","await_type":"human"}]},
 "tk-under":    {"id":"tk-under","status":"held","waits":[{"id":"tk-gate-up","type":"blocks","title":"Rule on the epic","status":"open","issue_type":"gate","await_type":"human","ancestor":"tk-epic"}]},
 "tk-answered": {"id":"tk-answered","status":"clear","waits":[{"id":"tk-gate-shut","type":"blocks","title":"Answered","status":"closed","issue_type":"gate","await_type":"human"}]},
 "tk-timer":    {"id":"tk-timer","status":"blocked","waits":[{"id":"tk-gate-timer","type":"blocks","title":"Wait an hour","status":"open","issue_type":"gate","await_type":"timer"}]}}
JSON
echo "# sling refuses a bead an open human gate holds"
sling tk-gated
eq "$RC" 5 "(GATE-SKIP) sling of a bead an open human gate blocks exits 5"
has "$OUT" "it waits on a person's answer (open human gate tk-gate-open)" "(GATE-SKIP) …naming the gate"
hasnt "$OUT" "$WOULD" "(GATE-SKIP) …nothing slung"
sling tk-under
eq "$RC" 5 "(GATE-SKIP) sling of a bead held by a gate on its epic exits 5"
has "$OUT" "open human gate tk-gate-up on tk-epic" "(GATE-SKIP) …naming the gate and the ancestor it is on"
for b in tk-answered tk-timer; do
    sling "$b"
    eq "$RC" 0 "(GATE-GO) sling of $b exits 0"
    has "$OUT" "$WOULD $b" "(GATE-GO) …and slings a reaction"
done
rm -f "$TMP/holds.json"

# --- an open conversation ----------------------------------------------------
# An open conversation about the bead already puts it to the operator, as gc-helm
# engage --new-subject files one for the subject it creates. The conversation
# shape is conversation.sh's: an open task assigned to human, or to the alias
# that names its own id, that tracks exactly the one bead.
cat > "$TMP/beads.json" <<'JSON'
{
 "tk-talked":   {"issue_type":"task","metadata":{}},
 "tk-held":     {"issue_type":"task","metadata":{}},
 "tk-ended":    {"issue_type":"task","metadata":{}},
 "tk-shared":   {"issue_type":"task","metadata":{}},
 "tk-owed":     {"issue_type":"task","metadata":{}},
 "tk-c1":   {"issue_type":"task","status":"open","assignee":"human","dependencies":[{"type":"tracks","depends_on_id":"tk-talked"}],"metadata":{}},
 "tk-c2":   {"issue_type":"task","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.tk-c2","dependencies":[{"type":"tracks","depends_on_id":"tk-held"}],"metadata":{}},
 "tk-c3":   {"issue_type":"task","status":"closed","assignee":"human","dependencies":[{"type":"tracks","depends_on_id":"tk-ended"}],"metadata":{}},
 "tk-c4":   {"issue_type":"task","status":"open","assignee":"human","dependencies":[{"type":"tracks","depends_on_id":"tk-shared"},{"type":"tracks","depends_on_id":"tk-other"}],"metadata":{}},
 "tk-c5":   {"issue_type":"task","status":"open","assignee":"someone","dependencies":[{"type":"tracks","depends_on_id":"tk-owed"}],"metadata":{}}
}
JSON
echo "# sling refuses a bead an open conversation tracks"
for b in tk-talked:tk-c1 tk-held:tk-c2; do
    sling "${b%%:*}"
    eq "$RC" 3 "(CONV-SKIP) sling of ${b%%:*}, which ${b#*:} tracks, exits 3"
    has "$OUT" "an open conversation tracks it (${b#*:})" "(CONV-SKIP) …naming the conversation"
    hasnt "$OUT" "$WOULD" "(CONV-SKIP) …nothing slung"
done
echo "# a closed conversation, or a task that is no conversation, is no refusal"
for b in tk-ended tk-shared tk-owed; do
    sling "$b"
    eq "$RC" 0 "(CONV-GO) sling of $b exits 0"
    has "$OUT" "$WOULD $b" "(CONV-GO) …and slings a reaction"
done

# --- a molecule step is not a scan candidate --------------------------------
# Most graph.v2 steps are issue_type task, and no graph.v2 step has a
# parent-child edge, so the type allowlist and the top-level clause both pass
# one. tk-step-validate and tk-step-react are ordinary steps of two formulas,
# the second a first reaction's own, each tied to its root by a tracks edge.
# tk-step-finalize is a control step whose gc.kind is not a topology kind, tied
# to its root by gc.root_bead_id alone. Each is unrouted and passes every other
# clause, so gc.step_ref is all that sets it apart from tk-raw. tk-step-blank
# carries the key with an empty value, which names no step.
cat > "$TMP/scan.json" <<'JSON'
[
  {"id":"tk-raw", "issue_type":"task", "description":"a raw input bead", "title":"raw input", "metadata":{}},
  {"id":"tk-step-validate", "issue_type":"task", "description":"converge the rules", "title":"rule convergence",
   "metadata":{"gc.step_ref":"mol-validate.rule-convergence","gc.step_id":"rule-convergence","gc.root_bead_id":"tk-root-validate"},
   "dependencies":[{"issue_id":"tk-step-validate","depends_on_id":"tk-root-validate","type":"tracks"}]},
  {"id":"tk-step-react", "issue_type":"task", "description":"react to the subject", "title":"react",
   "metadata":{"gc.step_ref":"mol-first-reaction.react","gc.step_id":"react","gc.root_bead_id":"tk-root-reaction"},
   "dependencies":[{"issue_id":"tk-step-react","depends_on_id":"tk-root-reaction","type":"tracks"}]},
  {"id":"tk-step-finalize", "issue_type":"task", "description":"finalize the workflow", "title":"workflow finalize",
   "metadata":{"gc.kind":"workflow-finalize","gc.step_ref":"mol-polecat-work.workflow-finalize","gc.step_id":"workflow-finalize","gc.root_bead_id":"tk-root-work"}},
  {"id":"tk-step-blank", "issue_type":"task", "description":"a step key left empty", "title":"blank step key", "metadata":{"gc.step_ref":""}}
]
JSON

echo "# scan_precision_filter drops a molecule step, keeps raw input"
IDS="$(bash "$SCRIPT" scan --json 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-raw" "(STEP-KEEP) a raw input beside the step beads is still a candidate"
has "$IDS" "tk-step-blank" "(STEP-KEEP) …and so is a bead whose gc.step_ref is empty"
hasnt "$IDS" "tk-step-validate" "(STEP-DROP) a mol-validate step is not a scan candidate"
hasnt "$IDS" "tk-step-react" "(STEP-DROP) …nor a first reaction's own react step"
hasnt "$IDS" "tk-step-finalize" "(STEP-DROP) …nor a workflow-finalize control step"

store_of "$TMP/scan.json"
echo "# a scan --sling sweep reacts to raw input and never to a molecule step"
set +e
OUT="$(bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(STEP-SWEEP) the sweep exits 0"
has "$OUT" "$WOULD tk-raw" "(STEP-SWEEP) the sweep slings a first reaction at the raw input"
hasnt "$OUT" "$WOULD tk-step-validate" "(STEP-SWEEP) …and none at the mol-validate step"
hasnt "$OUT" "$WOULD tk-step-react" "(STEP-SWEEP) …nor at the react step"
hasnt "$OUT" "$WOULD tk-step-finalize" "(STEP-SWEEP) …nor at the control step"

# --- a held bead is not a scan candidate ------------------------------------
# tk-held-bug is the bug the witness's bug-file block files, and tk-held-proposal
# a prompt-update the feedback distiller files: each carries hold:mayor from its
# create, is unrouted, and carries no takeaway. tk-held-external carries Gas
# City's other hold, in another case. tk-old-marker carries only the retired
# placement marker, which holds nothing. Each passes every other clause, so
# has_dispatch_hold is all that sets the first three apart from tk-raw.
cat > "$TMP/scan.json" <<'JSON'
[
  {"id":"tk-raw", "issue_type":"task", "description":"a raw input bead", "title":"raw input", "metadata":{}},
  {"id":"tk-held-bug", "issue_type":"bug", "description":"a pack defect the witness filed", "title":"pack defect",
   "labels":["hold:mayor"], "metadata":{}},
  {"id":"tk-held-proposal", "issue_type":"task", "description":"a rule the distiller proposes", "title":"prompt update",
   "labels":["learning","prompt-update","hold:mayor"],
   "metadata":{"task_kind":"prompt-update","target":"main","merge_strategy":"mr"}},
  {"id":"tk-held-external", "issue_type":"task", "description":"work waiting outside this store", "title":"held outside",
   "labels":["Hold:External"], "metadata":{}},
  {"id":"tk-old-marker", "issue_type":"task", "description":"a bead marked before the native hold", "title":"old marker",
   "metadata":{"placement":"pending"}}
]
JSON

echo "# scan_precision_filter drops a held bead, keeps raw input"
IDS="$(bash "$SCRIPT" scan --json 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-raw" "(HOLD-KEEP) a raw input beside the held beads is still a candidate"
has "$IDS" "tk-old-marker" "(HOLD-KEEP) …and so is a bead carrying only the retired placement marker"
hasnt "$IDS" "tk-held-bug" "(HOLD-DROP) a bug the witness holds for placement is not a scan candidate"
hasnt "$IDS" "tk-held-proposal" "(HOLD-DROP) …nor a proposal the distiller holds for placement"
hasnt "$IDS" "tk-held-external" "(HOLD-DROP) …nor a bead held outside this store, its label in any case"

store_of "$TMP/scan.json"
echo "# a scan --sling sweep reacts to raw input and never to a held bead"
set +e
OUT="$(bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(HOLD-SWEEP) the sweep exits 0"
has "$OUT" "$WOULD tk-raw" "(HOLD-SWEEP) the sweep slings a first reaction at the raw input"
hasnt "$OUT" "$WOULD tk-held-bug" "(HOLD-SWEEP) …and none at the witness's held bug"
hasnt "$OUT" "$WOULD tk-held-proposal" "(HOLD-SWEEP) …nor at the distiller's held proposal"

echo "# sling refuses a held bead named to it, naming the hold as the bead spells it"
for b in tk-held-bug:hold:mayor tk-held-proposal:hold:mayor tk-held-external:Hold:External; do
    id="${b%%:*}" label="${b#*:}"
    sling "$id"
    eq "$RC" 5 "(HOLD-SKIP) sling of $id exits 5"
    has "$OUT" "it is held ($label)" "(HOLD-SKIP) …naming the label as $id spells it"
    hasnt "$OUT" "$WOULD" "(HOLD-SKIP) …nothing slung for $id"
done
sling tk-old-marker
eq "$RC" 0 "(HOLD-SKIP) sling of a bead carrying only the retired placement marker exits 0"
has "$OUT" "$WOULD tk-old-marker" "(HOLD-SKIP) …and slings a reaction"

# --- the sweep: no cap, each refusal under its cause ------------------------
# Seven candidates, more than any per-sweep cap ever allowed. Two of them were
# decided after the scan's read, which the scan rows do not show: tk-late-routed
# was routed and tk-late-held held, so the sling's own row read refuses each.
# Every other one is slung, and only those count.
jq -n '[ range(1; 6) | {id: "tk-many-\(.)", issue_type: "task", description: "raw input \(.)", title: "many \(.)", metadata: {}} ]
       + [ {id: "tk-late-routed", issue_type: "task", description: "routed after the scan read", title: "late routed", metadata: {}},
           {id: "tk-late-held",   issue_type: "task", description: "held after the scan read",   title: "late held",   metadata: {}} ]' > "$TMP/scan.json"
store_of "$TMP/scan.json"
jq '."tk-late-routed".metadata = {"gc.routed_to": "gc-toolkit/gc-toolkit.polecat"} | ."tk-late-held".labels = ["hold:mayor"]' \
    "$TMP/beads.json" > "$TMP/beads.next" && mv "$TMP/beads.next" "$TMP/beads.json"
echo "# a sweep slings every candidate nobody decided on, and counts only those"
set +e
OUT="$(bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(SWEEP-NOCAP) the sweep exits 0"
eq "$(printf '%s\n' "$OUT" | grep -c "$WOULD tk-many-")" 5 "(SWEEP-NOCAP) …slinging every one of the five, with no cap"
hasnt "$OUT" "$WOULD tk-late-" "(SWEEP-NOCAP) …and none at a bead decided since the read"
has "$OUT" "slung 5 first reaction(s) (2 already routed, armed, held, assigned or waiting on a person)" "(SWEEP-COUNT) …counting the slings alone, the refusals under their cause"
hasnt "$OUT" "left for the next sweep" "(SWEEP-NOCAP) …and leaving none for the next sweep"

echo "# a sweep whose deadline will not parse fails before it reads anything"
set +e
OUT="$(GC_PROACTIVE_SWEEP_TIMEOUT=soon bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(SWEEP-DEADLINE) an unreadable GC_PROACTIVE_SWEEP_TIMEOUT fails the sweep"
has "$OUT" "GC_PROACTIVE_SWEEP_TIMEOUT must be a duration" "(SWEEP-DEADLINE) …naming the variable"
hasnt "$OUT" "$WOULD" "(SWEEP-DEADLINE) …and slinging nothing"
set +e
OUT="$(GC_PROACTIVE_SWEEP_TIMEOUT=5m bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(SWEEP-DEADLINE) a deadline in minutes, as an order's timeout is written, is read"
has "$OUT" "slung 5 first reaction(s)" "(SWEEP-DEADLINE) …and the sweep runs"

echo "# a rig whose pool cannot take a reaction is skipped before the store is read"
cat > "$TMP/agents.json" <<'JSON'
{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]}
JSON
set +e
OUT="$(bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(SWEEP-DELIVERABLE) a sweep where the proactive pool is not registered exits 0"
has "$OUT" "no sweep this rig — no: no agent is registered at gc-toolkit/gc-toolkit.proactive" "(SWEEP-DELIVERABLE) …saying why"
hasnt "$OUT" "$WOULD" "(SWEEP-DELIVERABLE) …and slinging nothing"
cat > "$TMP/agents.json" <<'JSON'
{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.proactive","pool":{"max":2}}]}
JSON
set +e
OUT="$(bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
has "$OUT" "slung 5 first reaction(s)" "(SWEEP-DELIVERABLE) …while a registered pool is swept"
rm -f "$TMP/agents.json"

# --- fail closed with no rig context --------------------------------------
# resolve_pool_target dies when GC_RIG is unset, so a sling has no pool to sling
# into. The --sling sweep must abort ONCE, not surface that failure per
# candidate. Two candidates make "once, not per-bead" observable; env -u GC_RIG
# drops, for just this invocation, the rig context the harness pinned above.
cat > "$TMP/scan.json" <<'JSON'
[
  {"id":"tk-a", "issue_type":"task", "description":"raw input a", "title":"a", "metadata":{}},
  {"id":"tk-b", "issue_type":"task", "description":"raw input b", "title":"b", "metadata":{}}
]
JSON
store_of "$TMP/scan.json"

echo "# scan --sling with no rig context aborts the whole sweep once"
set +e
OUT="$(env -u GC_RIG bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] && ok "(SWEEP-FAILCLOSED) scan --sling exits non-zero when GC_RIG is unset" || bad "(SWEEP-FAILCLOSED) scan --sling exited 0 with no rig context (got $RC)"
hasnt "$OUT" "$WOULD" "(SWEEP-FAILCLOSED) …nothing slung"
NSET="$(printf '%s\n' "$OUT" | grep -c 'set GC_RIG' || true)"
eq "$NSET" 1 "(SWEEP-FAILCLOSED) …the set-GC_RIG guidance surfaces once, not per candidate"

echo "# a direct sling with no rig context also fails closed"
set +e
OUT="$(env -u GC_RIG bash "$SCRIPT" sling tk-a 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(SLING-FAILCLOSED) sling exits 1 when GC_RIG is unset"
hasnt "$OUT" "$WOULD" "(SLING-FAILCLOSED) …nothing slung"

# --- the live runs -------------------------------------------------------------
# A run is live until its root closes, whatever gc.execution_routed_to the pour
# left on the bead. The runs come from runs.json, the runs the fixture store's
# roots and convoys make, and a root's pour marks from beads.json:
#   tk-building     a convoy a live mol-polecat-work root names tracks it
#   tk-reacting     a convoy a live mol-first-reaction root names tracks it
#   tk-both         a live first reaction and a live build both work it
#   tk-built        its root closed
#   tk-retired      tracked only by a convoy no root names
#   tk-fresh        no convoy tracks it
#   tk-failed       a live mol-first-reaction root that carries molecule_failed
#   tk-fenced       a live mol-first-reaction root a step under it is still
#                   fenced by gc.instantiating
#   tk-garbled      the runs that work it cannot be read
cat > "$TMP/store.json" <<'JSON'
[
  {"id":"tk-root-building", "status":"in_progress", "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work",   "gc.input_convoy_id":"tk-cv-building"}},
  {"id":"tk-root-reacting", "status":"in_progress", "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction", "gc.input_convoy_id":"tk-cv-reacting"}},
  {"id":"tk-root-both-r",   "status":"in_progress", "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction", "gc.input_convoy_id":"tk-cv-both-r"}},
  {"id":"tk-root-both-b",   "status":"in_progress", "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work",   "gc.input_convoy_id":"tk-cv-both-b"}},
  {"id":"tk-root-built",    "status":"closed",      "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work",   "gc.input_convoy_id":"tk-cv-built"}},
  {"id":"tk-root-failed",   "status":"open",        "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction", "gc.input_convoy_id":"tk-cv-failed"}},
  {"id":"tk-root-fenced",   "status":"in_progress", "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction", "gc.input_convoy_id":"tk-cv-fenced"}},
  {"id":"tk-cv-building", "issue_type":"convoy", "status":"open",   "dependencies":[{"type":"tracks","depends_on_id":"tk-building"}]},
  {"id":"tk-cv-reacting", "issue_type":"convoy", "status":"open",   "dependencies":[{"type":"tracks","depends_on_id":"tk-reacting"}]},
  {"id":"tk-cv-both-r",   "issue_type":"convoy", "status":"open",   "dependencies":[{"type":"tracks","depends_on_id":"tk-both"}]},
  {"id":"tk-cv-both-b",   "issue_type":"convoy", "status":"open",   "dependencies":[{"type":"tracks","depends_on_id":"tk-both"}]},
  {"id":"tk-cv-built",    "issue_type":"convoy", "status":"open",   "dependencies":[{"type":"tracks","depends_on_id":"tk-built"}]},
  {"id":"tk-cv-retired",  "issue_type":"convoy", "status":"closed", "dependencies":[{"type":"tracks","depends_on_id":"tk-retired"}]},
  {"id":"tk-cv-failed",   "issue_type":"convoy", "status":"open",   "dependencies":[{"type":"tracks","depends_on_id":"tk-failed"}]},
  {"id":"tk-cv-fenced",   "issue_type":"convoy", "status":"open",   "dependencies":[{"type":"tracks","depends_on_id":"tk-fenced"}]}
]
JSON
runs_of "$TMP/store.json"
cat > "$TMP/beads.json" <<'JSON'
{
  "tk-building": {"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  "tk-reacting": {"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.proactive"}},
  "tk-both":     {"metadata":{}},
  "tk-built":    {"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  "tk-retired":  {"metadata":{}},
  "tk-fresh":    {"metadata":{}},
  "tk-failed":   {"metadata":{}},
  "tk-fenced":   {"metadata":{}},
  "tk-garbled":  {"metadata":{}},
  "tk-root-failed":      {"status":"open","issue_type":"gate","metadata":{"molecule_failed":"true","gc.kind":"workflow"}},
  "tk-step-fenced":      {"status":"open","issue_type":"gate","metadata":{"gc.instantiating":"true","gc.root_bead_id":"tk-root-fenced"}}
}
JSON

echo "# sling refuses a bead a live run works, naming it"
sling tk-building
eq "$RC" 4 "(LIVE-SKIP) sling of a bead a live build works exits 4"
has "$OUT" "tk-root-building (mol-polecat-work)" "(LIVE-SKIP) …naming the root and its formula"
hasnt "$OUT" "$WOULD" "(LIVE-SKIP) …nothing slung"
sling tk-reacting
eq "$RC" 3 "(LIVE-REACTING) sling of a bead a live first reaction runs on exits 3"
has "$OUT" "a first reaction already runs on it (tk-root-reacting)" "(LIVE-REACTING) …naming the run"
hasnt "$OUT" "$WOULD" "(LIVE-REACTING) …nothing slung"
sling tk-both
eq "$RC" 3 "(LIVE-ORDER) a bead a first reaction and a build both work reports the reaction (3), not 4"

echo "# a closed root, a convoy no root names, or no convoy at all, frees the bead"
for b in tk-built tk-retired tk-fresh; do
    sling "$b"
    eq "$RC" 0 "(LIVE-NONE) sling of $b exits 0"
    has "$OUT" "$WOULD $b" "(LIVE-NONE) …and slings a reaction"
done

echo "# an unfinished pour of mol-first-reaction is no run"
for b in tk-failed tk-fenced; do
    sling "$b"
    eq "$RC" 0 "(UNFINISHED-NORUN) sling of $b, whose only run is an unfinished pour, exits 0"
    has "$OUT" "$WOULD $b" "(UNFINISHED-NORUN) …and goes on to the sling, whose refusal names the root"
done

echo "# a read that fails is not proof that no run works the bead"
set +e
OUT="$(RUN_LIB_STUB_FAIL="runs:tk-garbled" bash "$SCRIPT" sling tk-garbled 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(LIVE-FAILCLOSED) unreadable runs fail the sling closed (exit 1)"
has "$OUT" "cannot read the runs that work tk-garbled" "(LIVE-FAILCLOSED) …saying why"
hasnt "$OUT" "$WOULD" "(LIVE-FAILCLOSED) …nothing slung"

echo "# the scan drops a bead a live run works, keeps one whose only run is an unfinished reaction"
jq -n '[ "tk-building", "tk-reacting", "tk-built", "tk-retired", "tk-fresh", "tk-failed", "tk-fenced" ]
  | map({id: ., issue_type: "task", description: "a raw input bead", title: ., metadata: {}})' > "$TMP/scan.json"
OUT="$(bash "$SCRIPT" scan --json 2>"$TMP/scan.err")"
IDS="$(printf '%s' "$OUT" | jq -r '.[].id' | sort | tr '\n' ' ')"
hasnt "$IDS" "tk-building" "(INFLIGHT-DROP) a bead a live build works is not a candidate"
hasnt "$IDS" "tk-reacting" "(INFLIGHT-DROP) …nor one a live first reaction runs on"
has "$IDS" "tk-built" "(INFLIGHT-KEEP) a bead whose root closed still is"
has "$IDS" "tk-retired" "(INFLIGHT-KEEP) …so is a bead whose convoy no root names"
has "$IDS" "tk-fresh" "(INFLIGHT-KEEP) …and a bead no convoy tracks"
has "$IDS" "tk-failed" "(INFLIGHT-UNFINISHED) …and one whose only run is a pour marked failed"
has "$IDS" "tk-fenced" "(INFLIGHT-UNFINISHED) …or a pour whose step is still fenced"
has "$(cat "$TMP/scan.err")" "2 candidate(s) already have a live workflow" "(INFLIGHT-DROP) …and the sweep says how many it left out"

echo "# an unreadable read of the runs drops nothing, and the sweep says so"
IDS="$(RUN_LIB_STUB_FAIL=map bash "$SCRIPT" scan --json 2>"$TMP/scan.err" | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-building" "(INFLIGHT-FAILOPEN) with the runs unreadable, the bead stays a candidate (the sling still refuses it)"
has "$(cat "$TMP/scan.err")" "could not read the live runs" "(INFLIGHT-FAILOPEN) …and the sweep logs that it went unfiltered"

# --- the scan's drop and the sling's refusal read one definition ------------
# One store state, seen through each caller's read of run-lib.sh: the scan's
# map of the live runs, and the sling's runs of each bead. Each bead above the
# scan drops, the sling refuses for a live run (3 or 4), and no other.
echo "# the scan drops exactly what the sling refuses for a live run"
DROPPED="$(bash "$SCRIPT" scan --json 2>/dev/null \
    | jq -r --slurpfile all "$TMP/scan.json" '[ $all[0][].id ] - [ .[].id ] | sort | join(" ")')"
REFUSED=""
for b in $(jq -r '.[].id' "$TMP/scan.json" | sort); do
    set +e
    bash "$SCRIPT" sling "$b" >/dev/null 2>&1; RC=$?
    set -e
    case "$RC" in 3|4) REFUSED="${REFUSED:+$REFUSED }$b" ;; esac
done
eq "$DROPPED" "tk-building tk-reacting" "(AGREE-SCAN) the scan drops the beads a live run works"
eq "$REFUSED" "tk-building tk-reacting" "(AGREE-SLING) the sling refuses the same beads"

# --- the reaction's own check --------------------------------------------------
# The reaction asks the same refusals as its first act: `sling <S> --check --run
# <root>`. It writes nothing, its own run is no second reaction, and a gate filed
# under the first-reaction key whose message names its run is its own, so a
# reaction re-offered after its recommend or ruling exit filed that gate goes on.
cat > "$TMP/beads.json" <<'JSON'
{
  "tk-reacting": {"metadata":{}},
  "tk-both":     {"metadata":{}},
  "tk-closed":   {"status":"closed","metadata":{}},
  "tk-own-gate": {"metadata":{}},
  "tk-other-gate": {"metadata":{}},
  "tk-other-key": {"metadata":{}},
  "tk-g-own":   {"issue_type":"gate","await_type":"human","await_id":"first-reaction","status":"open","description":"Recommend mol-polecat-work.\n\nFiled by the first reaction run tk-root-reacting.","metadata":{}},
  "tk-g-other": {"issue_type":"gate","await_type":"human","await_id":"first-reaction","status":"open","description":"Recommend it. Filed by the first reaction run tk-root-reacting2.","metadata":{}},
  "tk-g-key":   {"issue_type":"gate","await_type":"human","await_id":"polecat-blocked","status":"open","description":"Blocked while run tk-root-reacting ran.","metadata":{}}
}
JSON
cat > "$TMP/holds.json" <<'JSON'
{"tk-own-gate":   {"id":"tk-own-gate","status":"blocked","waits":[{"id":"tk-g-own","type":"blocks","title":"Recommend","status":"open","issue_type":"gate","await_type":"human"}]},
 "tk-other-gate": {"id":"tk-other-gate","status":"blocked","waits":[{"id":"tk-g-other","type":"blocks","title":"Recommend","status":"open","issue_type":"gate","await_type":"human"}]},
 "tk-other-key":  {"id":"tk-other-key","status":"blocked","waits":[{"id":"tk-g-key","type":"blocks","title":"Blocked","status":"open","issue_type":"gate","await_type":"human"}]}}
JSON
echo "# the check passes over its own run, and refuses another reaction's"
sling tk-reacting --check --run tk-root-reacting
eq "$RC" 0 "(CHECK-OWN) the reaction's own run is no second reaction (exit 0)"
has "$OUT" "tk-reacting takes this first reaction (run tk-root-reacting)" "(CHECK-OWN) …saying the subject takes it"
hasnt "$OUT" "$WOULD" "(CHECK-WRITES-NOTHING) …and slinging nothing"
hasnt "$OUT" "gc sling" "(CHECK-WRITES-NOTHING) …nor printing a sling"
sling tk-reacting --check --run tk-root-elsewhere
eq "$RC" 3 "(CHECK-OTHER) another reaction's live run on the subject refuses it (exit 3)"
has "$OUT" "a first reaction already runs on it (tk-root-reacting)" "(CHECK-OTHER) …naming that run"
hasnt "$OUT" "No first reaction is slung" "(CHECK-OTHER) …as the refusal alone, which the reaction declines with"
sling tk-both --check --run tk-root-both-r
eq "$RC" 4 "(CHECK-OTHER) a live build beside the reaction refuses it (exit 4)"
sling tk-closed --check --run tk-root-reacting
eq "$RC" 5 "(CHECK-CLOSED) a subject closed before the check refuses the reaction (exit 5)"
has "$OUT" "its status is closed" "(CHECK-CLOSED) …naming the status"
echo "# the check passes over its own run's first-reaction gate, and no other gate"
sling tk-own-gate --check --run tk-root-reacting
eq "$RC" 0 "(CHECK-OWN-GATE) a first-reaction gate whose message names the run is passed over (exit 0)"
sling tk-other-gate --check --run tk-root-reacting
eq "$RC" 5 "(CHECK-OTHER-GATE) a first-reaction gate naming another run holds the subject (exit 5)"
has "$OUT" "open human gate tk-g-other" "(CHECK-OTHER-GATE) …naming the gate"
sling tk-other-key --check --run tk-root-reacting
eq "$RC" 5 "(CHECK-OTHER-GATE) a gate under another key holds it, even when its message names the run (exit 5)"
sling tk-own-gate
eq "$RC" 5 "(CHECK-OWN-GATE) a sling, which no run asks, refuses the subject that gate holds (exit 5)"
rm -f "$TMP/holds.json" "$TMP/store.json" "$TMP/runs.json"

# --- deliverable: the store-ownership arm -----------------------------------
# A rig-scope pool only claims beads in its own store, so `deliverable <target>
# <bead>` answers no when the target's rig does not own the bead's id prefix (the
# cross-store route gc sling refuses as CrossStoreRouteError), and falls through
# to the roster check when they agree. The fixture seam feeds rigs.json/agents.json
# instead of `gc rig list` / `gc agent list`.
cat > "$TMP/rigs.json" <<'JSON'
{"rigs":[
  {"name":"gc-toolkit","prefix":"tk","path":"/x/gc-toolkit"},
  {"name":"gascity","prefix":"gc","path":"/x/gascity"},
  {"name":"mycity","prefix":"hq","path":"/x/mycity"}]}
JSON
cat > "$TMP/agents.json" <<'JSON'
{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]}
JSON

echo "# deliverable refuses a cross-store route, by rig prefix"
set +e
OUT="$(bash "$SCRIPT" deliverable gascity/gc-toolkit.polecat tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(XSTORE-NO) a tk- bead routed at a gascity pool is refused"
has "$OUT" "cross-store" "(XSTORE-NO) …naming the dimension"
has "$OUT" "CrossStoreRouteError" "(XSTORE-NO) …tying it to the sling guard it mirrors"

set +e
OUT="$(bash "$SCRIPT" deliverable gc-toolkit/gc-toolkit.converse hq-300fe 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(XSTORE-CITY) a city-store (hq-) bead routed at a rig pool is refused"

echo "# deliverable falls through to the roster when target and bead share a store"
set +e
OUT="$(bash "$SCRIPT" deliverable gc-toolkit/gc-toolkit.polecat tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(XSTORE-SAME) a tk- bead routed at a gc-toolkit pool passes the store arm"
has "$OUT" "yes" "(XSTORE-SAME) …and the roster arm answers yes for a present pool"

echo "# the store arm is skipped without a bead argument (backward compatible)"
set +e
OUT="$(bash "$SCRIPT" deliverable gc-toolkit/gc-toolkit.polecat 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(XSTORE-NOBEAD) with no bead named, only the roster arm runs"

echo "# an unreadable rig list is not evidence of a cross-store route (positive finding only)"
rm -f "$TMP/rigs.json"
set +e
OUT="$(bash "$SCRIPT" deliverable gascity/gc-toolkit.polecat tk-82he4j 2>&1)"; RC=$?
set -e
hasnt "$OUT" "cross-store" "(XSTORE-UNREADABLE) with no rig list, the store arm does not fire"

# --- assignable: a named agent addressed by assignee ------------------------
# A named session's hook matches the bead's assignee, so `assignable <agent>
# [<bead>]` answers no when the roster has no agent by that exact name, when it
# is suspended, when it is a pool (absent from the merged config's
# NamedSessions), or when a rig-scoped agent's hook reads neither the bead's
# store nor the city's. A city-scoped agent's hook reads every rig store. The
# fixture seam feeds agents.json, config.json and rigs.json.
cat > "$TMP/rigs.json" <<'JSON'
{"rigs":[
  {"name":"mycity","prefix":"hq","path":"/x/mycity","hq":true},
  {"name":"gc-toolkit","prefix":"tk","path":"/x/gc-toolkit","hq":false},
  {"name":"gascity","prefix":"gc","path":"/x/gascity","hq":false}]}
JSON
cat > "$TMP/agents.json" <<'JSON'
{"agents":[
  {"name":"mechanik","qualified_name":"gc-toolkit.mechanik","scope":"city","suspended":false},
  {"name":"deacon","qualified_name":"gc-toolkit.deacon","scope":"city","suspended":true},
  {"name":"witness","qualified_name":"gc-toolkit/gc-toolkit.witness","dir":"gc-toolkit","scope":"rig","suspended":false},
  {"name":"polecat","qualified_name":"gc-toolkit/gc-toolkit.polecat","dir":"gc-toolkit","scope":"rig","suspended":false}]}
JSON
cat > "$TMP/config.json" <<'JSON'
{"config":{"NamedSessions":[
  {"Template":"mechanik","Scope":"city","Dir":""},
  {"Template":"deacon","Scope":"city","Dir":""},
  {"Template":"witness","Scope":"rig","Dir":"gc-toolkit"}]}}
JSON

echo "# assignable answers yes for a city-scoped named agent, in any rig store"
set +e
OUT="$(bash "$SCRIPT" assignable gc-toolkit.mechanik tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ASSIGNABLE-YES) mechanik can be handed a tk- bead"
has "$OUT" "named session" "(ASSIGNABLE-YES) …as a registered named session"
set +e
OUT="$(bash "$SCRIPT" assignable gc-toolkit.mechanik gc-300fe 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ASSIGNABLE-YES) …and a bead in another rig's store, which its hook also reads"

echo "# assignable refuses what no hook would offer"
set +e
OUT="$(bash "$SCRIPT" assignable mechanik tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(ASSIGNABLE-ABSENT) a bare name no agent is registered under is refused"
has "$OUT" "exact qualified name" "(ASSIGNABLE-ABSENT) …naming the address form"

set +e
OUT="$(bash "$SCRIPT" assignable gc-toolkit.deacon tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(ASSIGNABLE-SUSPENDED) a suspended agent is refused"
has "$OUT" "suspended" "(ASSIGNABLE-SUSPENDED) …naming why"

set +e
OUT="$(bash "$SCRIPT" assignable gc-toolkit/gc-toolkit.polecat tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(ASSIGNABLE-POOL) a pool is refused: its instances never match the pool name"
has "$OUT" "--route" "(ASSIGNABLE-POOL) …pointing at the route a pool takes"

echo "# assignable holds a rig-scoped agent to the stores its hook reads"
set +e
OUT="$(bash "$SCRIPT" assignable gc-toolkit/gc-toolkit.witness gc-300fe 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(ASSIGNABLE-XSTORE) a rig-scoped agent is refused a bead in another rig's store"
has "$OUT" "gc- store" "(ASSIGNABLE-XSTORE) …naming the store the bead lives in"
set +e
OUT="$(bash "$SCRIPT" assignable gc-toolkit/gc-toolkit.witness tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ASSIGNABLE-OWNSTORE) …and answers yes for its own rig's store"
set +e
OUT="$(bash "$SCRIPT" assignable gc-toolkit/gc-toolkit.witness hq-300fe 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ASSIGNABLE-CITYSTORE) …and for the city store, which its hook also reads"

echo "# assignable says no only on a positive finding"
rm -f "$TMP/config.json"
set +e
OUT="$(bash "$SCRIPT" assignable gc-toolkit/gc-toolkit.polecat tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ASSIGNABLE-NOCONFIG) with no config to read, a pool is not proven a pool"
printf '{"config":{}}' > "$TMP/config.json"
set +e
OUT="$(bash "$SCRIPT" assignable gc-toolkit/gc-toolkit.polecat tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ASSIGNABLE-NOCONFIG) …nor with a config that carries no NamedSessions list"
rm -f "$TMP/agents.json"
set +e
OUT="$(bash "$SCRIPT" assignable mechanik tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ASSIGNABLE-UNREADABLE) with no roster to read, the agent is assumed assignable"
printf '{"error":"no city"}' > "$TMP/agents.json"
set +e
OUT="$(bash "$SCRIPT" assignable mechanik tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ASSIGNABLE-UNREADABLE) …and a roster with no agent list is unreadable, not empty"


# The roster and config the cases above leave would answer for the sweep's
# deliverable gate, so the cases below start without them.
rm -f "$TMP/agents.json" "$TMP/config.json" "$TMP/rigs.json"

# --- a page the filter cannot build fails the scan --------------------------
# The fixture seam feeds scan.json through the same filter and drop. A page
# they cannot build is not an empty page: an unreadable candidate set, or an
# empty one, fails the scan and the sweep before the live-workflow drop counts
# it.
echo "# a candidate set the filter cannot build a page from fails the scan"
printf '{\n  "error": "database is locked",\n  "schema_version": 1\n}\n' > "$TMP/scan.json"
set +e
OUT="$(bash "$SCRIPT" scan --json 2>"$TMP/scan.err")"; RC=$?
set -e
[ "$RC" -ne 0 ] && ok "(PAGE-FAILCLOSED) an unreadable candidate set fails the scan (exit $RC)" \
    || bad "(PAGE-FAILCLOSED) an unreadable candidate set fails the scan (exited 0)"
eq "$OUT" "" "(PAGE-FAILCLOSED) …printing no candidate page"
has "$(cat "$TMP/scan.err")" "could not be filtered" "(PAGE-FAILCLOSED) …and saying so"
set +e
OUT="$(bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] && ok "(PAGE-FAILCLOSED) a sweep over it exits non-zero (exit $RC)" \
    || bad "(PAGE-FAILCLOSED) a sweep over it exits non-zero (exited 0)"
hasnt "$OUT" "$WOULD" "(PAGE-FAILCLOSED) …slinging nothing"
hasnt "$OUT" "first reaction(s)" "(PAGE-FAILCLOSED) …and reporting no sweep total"
: > "$TMP/scan.json"
set +e
OUT="$(bash "$SCRIPT" scan --json 2>"$TMP/scan.err")"; RC=$?
set -e
[ "$RC" -ne 0 ] && ok "(PAGE-FAILCLOSED) an empty candidate set fails the scan (exit $RC)" \
    || bad "(PAGE-FAILCLOSED) an empty candidate set fails the scan (exited 0)"
hasnt "$(cat "$TMP/scan.err")" "syntax error" "(PAGE-FAILCLOSED) …refused before the live-workflow drop counts it"
rm -f "$TMP/scan.json" "$TMP/beads.json"

# --- the live reads ------------------------------------------------------------
# The fixture seam replaces every read, so it cannot catch a wrong flag on one.
# These cases run the tool's real reads, run-lib.sh's included, against a stub
# gc over a JSON store, a stub gctk and a stub human-gate.sh. The stub gc
# answers each read the way bd does: `list` hides a gate-typed row unless
# --include-gates is passed and a closed row unless --all is, and its
# --has-metadata-key matches a key whatever its value, an empty one included;
# `show` answers the rows it finds and an error when it finds none, and `dep
# list --direction up` answers the beads that track the one named. A read whose
# arguments match a pattern in LIVE_FAIL answers bd's error object instead, and
# a list read whose arguments match one in LIVE_TWICE prints its answer twice.
# gc sling answers per bead from sling/<bead>.out and .rc. The rig map names a
# path with no .beads directory, so no read is pinned to a store.
LIVE="$TMP/live"
mkdir -p "$LIVE/bin" "$LIVE/show" "$LIVE/holds" "$LIVE/sling"
cat > "$LIVE/bin/gc" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LIVE/calls.log"
fail() { printf '{"error":"%s","schema_version":1}' "$1"; exit 1; }
while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    # shellcheck disable=SC2053  # a pattern on purpose
    [[ "$*" == $pat ]] && fail "database is locked"
done <<< "${LIVE_FAIL:-}"
twice=""
while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    # shellcheck disable=SC2053  # a pattern on purpose
    [[ "$*" == $pat ]] && twice=1
done <<< "${LIVE_TWICE:-}"
case "$1" in
  rig) [ "$*" = "rig list --json" ] && { printf '{"rigs":[{"name":"gc-toolkit","prefix":"tk","path":"/nonexistent/gc-toolkit"}]}'; exit 0; } ;;
  agent) printf '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.proactive","pool":{"max":2}}]}'; exit 0 ;;
  sling)
    shift
    pos=()
    while [ $# -gt 0 ]; do case "$1" in --rig|--on|--title) shift 2 ;; --*) shift ;; *) pos+=("$1"); shift ;; esac; done
    sleep "${LIVE_SLING_SLEEP:-0}"
    [ -f "$LIVE/sling/${pos[1]}.out" ] && cat "$LIVE/sling/${pos[1]}.out"
    rc="$(cat "$LIVE/sling/${pos[1]}.rc" 2>/dev/null || echo 0)"
    [ "$rc" != 0 ] || echo "Slung ${pos[1]} to ${pos[0]}"
    exit "$rc" ;;
  bd) shift ;;
  *) fail "unexpected call: $*" ;;
esac
case "$1" in
  ready)
    case "${FAIL_READY:-}" in
      object) printf '{\n  "error": "database is locked",\n  "schema_version": 1\n}\n'; exit 1 ;;
      nothing) printf 'Error: failed to open database\n' >&2; exit 1 ;;
      array-exit-1) printf '[]'; exit 1 ;;
      nothing-exit-0) exit 0 ;;
    esac
    [ "$*" = "ready --unassigned --exclude-type=epic --json --sort priority --limit 0" ] || fail "unexpected ready: $*"
    cat "$LIVE/ready.json" ;;
  show)
    shift; ids=()
    while [ $# -gt 0 ]; do case "$1" in --json) shift ;; --db) shift 2 ;; *) ids+=("$1"); shift ;; esac; done
    if [ "${#ids[@]}" -eq 1 ] && [ -f "$LIVE/show/${ids[0]}" ]; then
        cat "$LIVE/show/${ids[0]}"; exit "$(cat "$LIVE/show/${ids[0]}.rc" 2>/dev/null || echo 0)"
    fi
    jq -c --args '[ .[] | select(.id as $i | $ARGS.positional | index($i) != null) ] | if length == 0 then error("none") else . end' \
        "${ids[@]}" < "$LIVE/store.json" 2>/dev/null || fail "no issues found matching the provided IDs" ;;
  dep)
    [ "$2" = list ] || fail "unexpected dep: $*"
    jq -c --arg id "$3" 'if any(.[]; .id == $id) then
          [ .[] | select(any((.dependencies // [])[]; (.type // "") == "tracks" and .depends_on_id == $id)) | . + {dependency_type: "tracks"} ]
        else error("none") end' < "$LIVE/store.json" 2>/dev/null || fail "resolving $3: no issue found matching \"$3\"" ;;
  list)
    shift; ids=""; hk=""; all=""; gates=""; mf=()
    while [ $# -gt 0 ]; do case "$1" in
        --id) ids="$2"; shift 2 ;;
        --metadata-field) mf+=("$2"); shift 2 ;;
        --has-metadata-key) hk="$2"; shift 2 ;;
        --all) all=1; shift ;;
        --include-gates) gates=1; shift ;;
        --include-ephemeral|--json) shift ;;
        --limit|--db) shift 2 ;;
        *) fail "unexpected list flag: $1" ;;
    esac; done
    jq -c --arg ids "$ids" --arg hk "$hk" --arg all "$all" --arg gates "$gates" --arg twice "$twice" --args '
        ($ARGS.positional | map(split("=") | {k: .[0], v: (.[1:] | join("="))})) as $mf
        | [ .[] | select($ids == "" or (.id as $i | ($ids | split(",") | index($i)) != null))
                | select($all != "" or ((.status // "open") != "closed"))
                | select($gates != "" or ((.issue_type // "") != "gate"))
                | select($hk == "" or ((.metadata // {}) | has($hk)))
                | select(. as $r | all($mf[]; ((($r.metadata // {})[.k]) // "" | tostring) == .v)) ]
        | if $twice == "" then . else (., .) end' \
        "${mf[@]}" < "$LIVE/store.json" ;;
  *) fail "unexpected bd call: $*" ;;
esac
SH
cat > "$LIVE/bin/gctk" <<'SH'
#!/usr/bin/env bash
printf 'gctk %s\n' "$*" >> "$LIVE/calls.log"
[ "$1 $2" = "bead holds" ] || exit 2
id="${!#}"
if [ -f "$LIVE/holds/$id" ]; then
    cat "$LIVE/holds/$id"; exit "$(cat "$LIVE/holds/$id.rc" 2>/dev/null || echo 0)"
fi
printf '{"id":"%s","status":"clear","waits":[],"pending":[],"last_landed":"","in_flight":"","arm":null,"foreign":[]}\n' "$id"
SH
cat > "$LIVE/bin/human-gate" <<'SH'
#!/usr/bin/env bash
printf 'human-gate %s\n' "$*" >> "$LIVE/calls.log"
for a in "$@"; do printf '%s\n' "$a"; done > "$LIVE/gate.args"
[ "${LIVE_GATE_RC:-0}" = 0 ] || { echo "human-gate: the store refused the gate" >&2; exit "$LIVE_GATE_RC"; }
echo "tk-gate-new"
SH
chmod +x "$LIVE/bin/gc" "$LIVE/bin/gctk" "$LIVE/bin/human-gate"

# The store, in `bd list` shape:
#   tk-free       nothing works it or holds it
#   tk-driven     a live mol-polecat-work run works it
#   tk-reacting   a live first reaction runs on it, its pour finished
#   tk-gr         a first reaction's pour still fenced, root and all, so its
#                 root is gate-typed and run-lib.sh reads no run; gc sling
#                 names the root
#   tk-fr         a first reaction's pour marked failed, its root gate-typed
#   tk-sf         a first reaction whose root was let out of the fence and
#                 whose step was not, so the root reads as a live run
#   tk-race       gc sling meets a live first reaction poured since the
#                 sling's own read
#   tk-talked     an open conversation, tk-conv, tracks it
#   tk-ctrl       routed, its title carrying a raw control byte
LIVE_STORE='[
 {"id":"tk-free","status":"open","issue_type":"task","metadata":{}},
 {"id":"tk-driven","status":"open","issue_type":"task","metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}},
 {"id":"tk-cv-driven","status":"open","issue_type":"convoy","dependencies":[{"type":"tracks","depends_on_id":"tk-driven"}]},
 {"id":"tk-root-driven","status":"in_progress","issue_type":"task","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"tk-cv-driven"}},
 {"id":"tk-reacting","status":"open","issue_type":"task","metadata":{}},
 {"id":"tk-cv-reacting","status":"open","issue_type":"convoy","dependencies":[{"type":"tracks","depends_on_id":"tk-reacting"}]},
 {"id":"tk-root-reacting","status":"in_progress","issue_type":"task","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction","gc.input_convoy_id":"tk-cv-reacting"}},
 {"id":"tk-gr","status":"open","issue_type":"task","metadata":{}},
 {"id":"tk-cv-gr","status":"open","issue_type":"convoy","dependencies":[{"type":"tracks","depends_on_id":"tk-gr"}]},
 {"id":"tk-root-gr","status":"open","issue_type":"gate","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction","gc.input_convoy_id":"tk-cv-gr","gc.instantiating":"true"}},
 {"id":"tk-fr","status":"open","issue_type":"task","metadata":{}},
 {"id":"tk-cv-fr","status":"open","issue_type":"convoy","dependencies":[{"type":"tracks","depends_on_id":"tk-fr"}]},
 {"id":"tk-root-fr","status":"open","issue_type":"gate","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction","gc.input_convoy_id":"tk-cv-fr","molecule_failed":"true"}},
 {"id":"tk-sf","status":"open","issue_type":"task","metadata":{}},
 {"id":"tk-cv-sf","status":"open","issue_type":"convoy","dependencies":[{"type":"tracks","depends_on_id":"tk-sf"}]},
 {"id":"tk-root-sf","status":"in_progress","issue_type":"task","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction","gc.input_convoy_id":"tk-cv-sf"}},
 {"id":"tk-step-sf","status":"open","issue_type":"gate","metadata":{"gc.step_ref":"mol-first-reaction.react","gc.root_bead_id":"tk-root-sf","gc.instantiating":"true"}},
 {"id":"tk-race","status":"open","issue_type":"task","metadata":{}},
 {"id":"tk-root-race","status":"in_progress","issue_type":"task","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction"}},
 {"id":"tk-talked","status":"open","issue_type":"task","metadata":{}},
 {"id":"tk-conv","status":"open","issue_type":"task","assignee":"human","dependencies":[{"type":"tracks","depends_on_id":"tk-talked"}],"metadata":{}},
 {"id":"tk-ctrl","status":"open","issue_type":"task","title":"routed\u0001","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
 {"id":"tk-gated","status":"open","issue_type":"task","metadata":{}},
 {"id":"tk-g-own","status":"open","issue_type":"gate","await_type":"human","await_id":"first-reaction","description":"Recommend mol-polecat-work. Filed by the first reaction run tk-root-gated.","metadata":{}}
]'
printf '%s' "$LIVE_STORE" | jq -c . > "$LIVE/store.json"
printf 'gc sling: source bead tk-gr already has live workflow(s): tk-root-gr\n' > "$LIVE/sling/tk-gr.out"; echo 3 > "$LIVE/sling/tk-gr.rc"
printf 'gc sling: source bead tk-fr already has live workflow(s): tk-root-fr\n' > "$LIVE/sling/tk-fr.out"; echo 3 > "$LIVE/sling/tk-fr.rc"
printf 'gc sling: source bead tk-sf already has live workflow(s): tk-root-sf\n' > "$LIVE/sling/tk-sf.out"; echo 3 > "$LIVE/sling/tk-sf.rc"
printf 'gc sling: source bead tk-race already has live workflow(s): tk-root-race\n' > "$LIVE/sling/tk-race.out"; echo 3 > "$LIVE/sling/tk-race.rc"

# live <args...> -> OUT, RC, CALLS for one run of the tool over the stubs.
live() {
    : > "$LIVE/calls.log"; rm -f "$LIVE/gate.args"
    set +e
    OUT="$(env -u GC_PROACTIVE_FIXTURE -u GC_RUN_LIB -u RUN_LIB_STUB_RUNS PATH="$LIVE/bin:$PATH" LIVE="$LIVE" \
        GCTK_BIN="$LIVE/bin/gctk" GC_HUMAN_GATE_TOOL="$LIVE/bin/human-gate" bash "$SCRIPT" "$@" </dev/null 2>&1)"; RC=$?
    set -e
    CALLS="$(cat "$LIVE/calls.log")"
}

echo "# the live reads: a free bead is slung as a run of mol-first-reaction"
live sling tk-free
eq "$RC" 0 "(LIVE-READS) a bead nothing works or holds is slung (exit 0)"
has "$CALLS" "sling --rig gc-toolkit gc-toolkit/gc-toolkit.proactive tk-free --on mol-first-reaction" "(LIVE-READS) …through gc sling at the rig's proactive pool, naming the formula"
has "$OUT" "slung a first reaction on tk-free" "(LIVE-READS) …and says so"
has "$CALLS" "gctk bead holds tk-free" "(LIVE-READS) …after asking gctk what holds it"
has "$CALLS" "bd dep list tk-free --direction=up --type tracks --json" "(LIVE-READS) …and reading what tracks it"
live sling tk-free --dry-run
eq "$RC" 0 "(LIVE-READS) a dry run exits 0"
hasnt "$CALLS" "sling --rig" "(LIVE-READS) …and runs no gc sling"

echo "# the live reads: a live run refuses the bead"
live sling tk-driven
eq "$RC" 4 "(LIVE-READS) a bead a live build works is refused (exit 4)"
has "$OUT" "tk-root-driven (mol-polecat-work)" "(LIVE-READS) …naming the root, read through run-lib.sh's own reads"
hasnt "$CALLS" "sling --rig" "(LIVE-READS) …and slinging nothing"
live sling tk-reacting
eq "$RC" 3 "(LIVE-READS) a bead a live first reaction runs on is refused (exit 3)"
LIVE_FAIL='bd dep list tk-driven --direction=up -t tracks*' live sling tk-driven
eq "$RC" 1 "(LIVE-READS) a runs read that fails fails the sling closed (exit 1)"
has "$OUT" "cannot read the runs that work tk-driven" "(LIVE-READS) …saying why"
hasnt "$CALLS" "sling --rig" "(LIVE-READS) …and slinging nothing"

echo "# the subject's own row: only its one row, read whole, answers"
printf '{"error":"no issues found matching the provided IDs","schema_version":1}' > "$LIVE/show/tk-missing"; echo 1 > "$LIVE/show/tk-missing.rc"
printf '[{"id":"tk-partial-twin","status":"open","metadata":{}}]' > "$LIVE/show/tk-partial"
: > "$LIVE/show/tk-empty"
printf '[{"id":"tk-twice","metadata":{}}]\n[{"id":"tk-twice","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}]' > "$LIVE/show/tk-twice"
for b in tk-missing tk-partial tk-empty tk-twice; do
    live sling "$b"
    eq "$RC" 1 "(SUBJECT-READS) a row read answering $b fails the sling closed (exit 1)"
    has "$OUT" "cannot read $b's own row" "(SUBJECT-READS) …saying why"
    hasnt "$CALLS" "sling --rig" "(SUBJECT-READS) …and slinging nothing for $b"
done
printf '[{"id":"tk-ctrl","status":"open","issue_type":"task","title":"routed\001","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}]' > "$LIVE/show/tk-ctrl"
live sling tk-ctrl
eq "$RC" 5 "(SUBJECT-READS) a routed bead whose row carries a raw control byte is refused (exit 5)"
has "$OUT" "already has a dispatch path (gc.routed_to=gc-toolkit/gc-toolkit.polecat)" "(SUBJECT-READS) …its row read through the scrub"

echo "# the conversation read"
live sling tk-talked
eq "$RC" 3 "(CONV-READS) a bead an open conversation tracks is refused (exit 3)"
has "$OUT" "an open conversation tracks it (tk-conv)" "(CONV-READS) …naming it, its shape read from its own row"
has "$CALLS" "bd list --id tk-conv --all --limit 0 --json" "(CONV-READS) …which is read with its edges"
LIVE_FAIL='bd list --id tk-conv*' live sling tk-talked
eq "$RC" 1 "(CONV-READS) a candidate whose own row does not read fails the sling closed (exit 1)"
has "$OUT" "cannot read whether an open conversation tracks tk-talked" "(CONV-READS) …saying why"
LIVE_FAIL='bd dep list tk-free --direction=up --type tracks*' live sling tk-free
eq "$RC" 1 "(CONV-READS) a tracks read that fails fails the sling closed (exit 1)"
hasnt "$CALLS" "sling --rig" "(CONV-READS) …and slinging nothing"

echo "# what holds the bead, as gctk bead holds answers it"
printf '{"id":"tk-gated","status":"blocked","waits":[{"id":"tk-g-own","type":"blocks","title":"Recommend","status":"open","issue_type":"gate","await_type":"human"}]}\n' > "$LIVE/holds/tk-gated"
live sling tk-gated
eq "$RC" 5 "(HOLDS-READS) a bead an open human gate holds is refused (exit 5)"
has "$OUT" "open human gate tk-g-own" "(HOLDS-READS) …naming the gate gctk listed"
live sling tk-gated --check --run tk-root-gated
eq "$RC" 0 "(HOLDS-READS) the reaction whose run that first-reaction gate names passes over it (exit 0)"
has "$CALLS" "bd show tk-g-own --json" "(HOLDS-READS) …reading the gate's own row for its key and message"
LIVE_FAIL='bd show tk-g-own*' live sling tk-gated --check --run tk-root-gated
eq "$RC" 1 "(HOLDS-READS) a gate row that does not read decides nothing (exit 1)"
has "$OUT" "The check decides nothing" "(HOLDS-READS) …and says the reaction should ask again"
printf '{"id":"tk-free","error":"database is locked"}\n' > "$LIVE/holds/tk-free"; echo 1 > "$LIVE/holds/tk-free.rc"
live sling tk-free
eq "$RC" 1 "(HOLDS-READS) a holds read that fails fails the sling closed (exit 1)"
has "$OUT" "cannot read what holds tk-free" "(HOLDS-READS) …saying why"
hasnt "$CALLS" "sling --rig" "(HOLDS-READS) …and slinging nothing"
echo 0 > "$LIVE/holds/tk-free.rc"
live sling tk-free
eq "$RC" 1 "(HOLDS-READS) a holds line that carries an error fails it closed, whatever the exit (exit 1)"
rm -f "$LIVE/holds/tk-free" "$LIVE/holds/tk-free.rc"
set +e
OUT="$(env -u GC_PROACTIVE_FIXTURE -u GC_RUN_LIB -u RUN_LIB_STUB_RUNS PATH="$LIVE/bin:$PATH" LIVE="$LIVE" \
    GCTK_BIN="$LIVE/bin/no-such-gctk" bash "$SCRIPT" sling tk-free </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(HOLDS-READS) with no gctk binary to ask, the sling fails closed (exit 1)"

echo "# gc sling's own refusal: an unfinished pour is asked about, a live reaction passed through"
for b in tk-gr:tk-root-gr:"it is still fenced by gc.instantiating" tk-fr:tk-root-fr:"it carries molecule_failed=true" tk-sf:tk-root-sf:"gc.instantiating still fences tk-step-sf under it"; do
    id="${b%%:*}"; rest="${b#*:}"; root="${rest%%:*}"; why="${rest#*:}"
    live sling "$id"
    eq "$RC" 5 "(CONFLICT-UNFINISHED) gc sling's exit 3 on $id's unfinished pour exits 5"
    has "$CALLS" "sling --rig gc-toolkit gc-toolkit/gc-toolkit.proactive $id --on mol-first-reaction" "(CONFLICT-UNFINISHED) …after the sling, since no live run was read for $id"
    eq "$(sed -n '2p;4p' "$LIVE/gate.args" 2>/dev/null | tr '\n' ' ')" "$id first-reaction-unfinished-pour " "(CONFLICT-UNFINISHED) …filing a human gate on $id under its own key"
    MSG="$(sed -n '6,$p' "$LIVE/gate.args" 2>/dev/null || true)"
    has "$MSG" "$root ($why)" "(CONFLICT-UNFINISHED) …naming the root and why its pour is unfinished"
    has "$MSG" "gc convoy delete $root --force" "(CONFLICT-UNFINISHED) …and the command that closes it"
    has "$OUT" "human gate tk-gate-new asks a person to close it" "(CONFLICT-UNFINISHED) …and saying so"
done
live sling tk-race
eq "$RC" 3 "(CONFLICT-LIVE) gc sling's exit 3 naming a live reaction whose pour finished passes through (exit 3)"
has "$OUT" "gc sling found a first reaction already running on it (tk-root-race)" "(CONFLICT-LIVE) …naming it"
hasnt "$CALLS" "human-gate" "(CONFLICT-LIVE) …and filing no gate"
printf 'gc sling: refused\n' > "$LIVE/sling/tk-free.out"; echo 3 > "$LIVE/sling/tk-free.rc"
live sling tk-free
eq "$RC" 3 "(CONFLICT-LIVE) an exit 3 that names no root passes through (exit 3)"
hasnt "$CALLS" "human-gate" "(CONFLICT-LIVE) …filing no gate"
echo 1 > "$LIVE/sling/tk-free.rc"
live sling tk-free
eq "$RC" 1 "(SLING-FAIL) any other gc sling failure is an error (exit 1)"
has "$OUT" "gc sling refused or failed on tk-free (exit 1)" "(SLING-FAIL) …naming its exit"
rm -f "$LIVE/sling/tk-free.out" "$LIVE/sling/tk-free.rc"
LIVE_GATE_RC=1 live sling tk-gr
eq "$RC" 1 "(CONFLICT-UNFINISHED) a gate that cannot be filed is an error (exit 1)"
has "$OUT" "the gate that asks a person to close it could not be filed" "(CONFLICT-UNFINISHED) …saying so"
LIVE_FAIL='bd list --metadata-field molecule_failed=true*' live sling tk-gr
eq "$RC" 1 "(CONFLICT-UNFINISHED) marks that cannot be read after the refusal decide nothing (exit 1)"
hasnt "$CALLS" "human-gate" "(CONFLICT-UNFINISHED) …filing no gate"

echo "# the scan's live reads"
jq -c '[ .[] | select(.id == "tk-free" or .id == "tk-driven" or .id == "tk-reacting" or .id == "tk-sf" or .id == "tk-gr")
         | . + {description: "a raw input bead", title: .id} ]' "$LIVE/store.json" > "$LIVE/ready.json"
live scan --json
IDS="$(printf '%s' "$OUT" | grep '^\[' | jq -r '.[].id' | sort | tr '\n' ' ' || true)"
eq "$RC" 0 "(INFLIGHT-READS) the scan exits 0"
has "$IDS" "tk-free" "(INFLIGHT-READS) …offering a bead no run works"
hasnt "$IDS" "tk-driven" "(INFLIGHT-READS) …dropping one a live build works"
hasnt "$IDS" "tk-reacting" "(INFLIGHT-READS) …and one a live first reaction runs on"
has "$IDS" "tk-sf" "(INFLIGHT-READS) …keeping one whose only run is a pour its fence still holds"
has "$IDS" "tk-gr" "(INFLIGHT-READS) …and one whose gate-typed root the run reads do not see"
LIVE_FAIL='bd list --has-metadata-key gc.instantiating*' live scan --json
IDS="$(printf '%s' "$OUT" | grep '^\[' | jq -r '.[].id' | sort | tr '\n' ' ' || true)"
has "$OUT" "could not read whether the live first reactions' pours finished" "(INFLIGHT-READS) marks that do not read are named"
hasnt "$IDS" "tk-sf" "(INFLIGHT-READS) …and every live first reaction's bead stays out of the sweep"

echo "# the marks of an unfinished pour: reads larger than ARG_MAX, each one list"
# The fenced read matches the key whatever its value, so it answers every bead
# whose fence Gas City cleared to an empty value, each row whole. These cleared
# fences, one on a step under the live reaction tk-root-reacting, come to more
# than ARG_MAX, the cap on a command's arguments.
ARG_MAX_BYTES="$(getconf ARG_MAX)"
cp "$LIVE/store.json" "$LIVE/store.small.json"
jq -c --argjson max "$ARG_MAX_BYTES" '. + [ range(24) as $i
    | {id: "tk-cleared-\($i)", status: "closed", issue_type: "task", description: ("x" * ($max / 16 | floor)),
       metadata: {"gc.instantiating": "", "gc.root_bead_id": (if $i == 0 then "tk-root-reacting" else "tk-root-old-\($i)" end)}} ]' \
    "$LIVE/store.small.json" > "$LIVE/store.json"
FENCED_BYTES="$(env PATH="$LIVE/bin:$PATH" LIVE="$LIVE" gc bd list --has-metadata-key gc.instantiating --all --include-gates --include-ephemeral --limit 0 --json | wc -c | tr -d '[:space:]' || true)"
[ "$FENCED_BYTES" -gt "$ARG_MAX_BYTES" ] 2>/dev/null && ok "(MARKS-READS) the fenced read answers more than ARG_MAX ($FENCED_BYTES > $ARG_MAX_BYTES bytes)" \
    || bad "(MARKS-READS) the fenced read answers more than ARG_MAX (got '$FENCED_BYTES' bytes, ARG_MAX $ARG_MAX_BYTES)"
live sling tk-reacting --check --run tk-root-reacting
eq "$RC" 0 "(MARKS-READS) the reaction's own check passes over its run (exit 0)"
has "$OUT" "tk-reacting takes this first reaction (run tk-root-reacting)" "(MARKS-READS) …having read its runs"
live sling tk-reacting
eq "$RC" 3 "(MARKS-READS) a sling onto the live reaction is refused (exit 3)"
has "$OUT" "a first reaction already runs on it (tk-root-reacting)" "(MARKS-READS) …the fence cleared under its root marking no unfinished pour"
live scan --json
IDS="$(printf '%s' "$OUT" | grep '^\[' | jq -r '.[].id' | sort | tr '\n' ' ' || true)"
hasnt "$OUT" "could not read whether the live first reactions' pours finished" "(MARKS-READS) the scan reads the marks"
has "$IDS" "tk-sf" "(MARKS-READS) …keeping the bead whose only run is a pour its fence still holds"
hasnt "$IDS" "tk-reacting" "(MARKS-READS) …and dropping the one a live first reaction runs on"
mv "$LIVE/store.small.json" "$LIVE/store.json"
LIVE_TWICE='bd list --metadata-field molecule_failed=true*' live sling tk-reacting --check --run tk-root-reacting
eq "$RC" 1 "(MARKS-READS) a marks read that answers twice decides nothing (exit 1)"
has "$OUT" "cannot read the runs that work tk-reacting" "(MARKS-READS) …saying why"

echo "# the ready read: one read, and a failure in any shape fails the scan"
live scan --json
has "$CALLS" "bd ready --unassigned --exclude-type=epic --json --sort priority --limit 0" "(READ-CONTROL) the scan reads the whole ready set, highest priority first"
eq "$(printf '%s\n' "$CALLS" | grep -c '^bd ready')" 1 "(READ-CONTROL) …in one read, with no opt-in read beside it"
for shape in object nothing array-exit-1 nothing-exit-0; do
    FAIL_READY="$shape" live scan --json
    [ "$RC" -ne 0 ] && ok "(READ-FAILCLOSED) the ready read answering $shape fails the scan (exit $RC)" \
        || bad "(READ-FAILCLOSED) the ready read answering $shape fails the scan (exited 0)"
    has "$OUT" "the ready read failed" "(READ-FAILCLOSED) …naming the read"
    hasnt "$OUT" "tk-free" "(READ-FAILCLOSED) …and offering no candidate"
done
FAIL_READY=object live scan --json
has "$OUT" "gc bd ready exit 1: database is locked" "(READ-FAILCLOSED) …with gc bd's own error text"
FAIL_READY=nothing live scan --sling
[ "$RC" -ne 0 ] && ok "(READ-SWEEP) a sweep whose ready read fails exits non-zero (exit $RC)" \
    || bad "(READ-SWEEP) a sweep whose ready read fails exits non-zero (exited 0)"
hasnt "$CALLS" "sling --rig" "(READ-SWEEP) …slinging nothing"
hasnt "$OUT" "first reaction(s)" "(READ-SWEEP) …and reporting no sweep total"

echo "# a sweep's live slings, each refusal under its cause"
live scan --sling
eq "$RC" 0 "(SWEEP-LIVE) the sweep exits 0"
has "$CALLS" "sling --rig gc-toolkit gc-toolkit/gc-toolkit.proactive tk-free --on mol-first-reaction" "(SWEEP-LIVE) …slinging the free bead"
has "$OUT" "slung 1 first reaction(s) (2 already routed, armed, held, assigned or waiting on a person)" "(SWEEP-LIVE) …counting the sling alone, and the two pours it asked a person about as decided"

echo "# the sweep stops before its deadline"
# Each sling takes five seconds, and the sweep has eight. The first starts with
# time to spare; once it has taken five, less than that is left, so the sweep
# starts no other and leaves them for the next one.
jq -c '[ .[] | select(.id == "tk-free" or .id == "tk-race" or .id == "tk-talked") | . + {description: "a raw input bead", title: .id} ]' \
    "$LIVE/store.json" > "$LIVE/ready.json"
rm -f "$LIVE/sling/tk-race.out" "$LIVE/sling/tk-race.rc"
LIVE_SLING_SLEEP=5 GC_PROACTIVE_SWEEP_TIMEOUT=8s live scan --sling
eq "$RC" 0 "(SWEEP-DEADLINE) the sweep exits 0"
eq "$(printf '%s\n' "$CALLS" | grep -c '^sling ')" 1 "(SWEEP-DEADLINE) …starting one sling"
has "$OUT" "slung 1 first reaction(s); 2 candidate(s) left for the next sweep" "(SWEEP-DEADLINE) …and leaving the rest for the next sweep"
has "$OUT" "GC_PROACTIVE_SWEEP_TIMEOUT" "(SWEEP-DEADLINE) …naming the deadline it kept"

echo
echo "gc-proactive: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
