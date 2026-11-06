#!/usr/bin/env bash
# liveness-recheck.test.sh — the liveness-sweep gate's message is a SNAPSHOT,
# and whoever acts on it is entitled to a corrected census.
#
# THE DEFECT. classify writes its census into the message at pass time; a person
# reads it whenever they reach it, which is routinely a day or more later, and
# nothing re-checked it in between. Measured
# once: the sitting read the census ~41.5h after the pass cut it, and FIVE of
# the ten new candidates had merged AND deployed in the interval — 60% of that
# body was wrong on arrival. A sitting that trusts such a body routes
# already-merged work and burns a polecat on a no-op, as this scope's record
# already shows.
#
# WHAT THIS PINS, in the two halves the fix has:
#
#   1. THE RE-CHECK ITSELF (`liveness-recheck.sh`), executed against a stubbed
#      `gc`. Every verdict class, the precedence between them, and — the half
#      that matters most — that every uncertainty leaves a bead VISIBLE:
#        * the batched bead read fails   -> NO census at all, non-zero exit.
#        * the ready read fails          -> the not-ready rule is SKIPPED, so a
#                                           transient cannot classify the whole
#                                           agenda as gated and hide it.
#        * an id the read did not return -> its own bucket, counted INTO the
#                                           live agenda.
#        * a merge_result marker         -> FLAGGED, never dropped: PR liveness
#                                           is not re-checked here.
#      The inverse defect is the one worth guarding: a re-check that HIDES a
#      bead on a signal it did not verify is worse than the staleness it fixes,
#      because a hidden bead has no next pass that surfaces it.
#
#   2. THE WIRING that makes it fire. liveness-sweep.sh writes the census into
#      its gate's message as this script's command line (covered by
#      liveness-sweep.test.sh); here the flags that command names are pinned
#      against what this script parses, so the writer and the reader cannot
#      drift apart. The converse prep skill, which runs the re-check a sitting
#      finds in a gate's message, is asserted to run the pack's own copy with
#      the values the message names, never the message's line as written. Every
#      kind in the shared standing-kinds list re-checks as standing.
# Hermetic: reads the repo, stubs `gc`; no city, no Dolt, no network, no gh.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/assets/scripts/liveness-recheck.sh"
SWEEP="$ROOT/assets/scripts/liveness-sweep.sh"
PROMPT="$ROOT/agents/_converse/prompt.template.md"
# The claim-time re-check lives in the converse prep skill (steps 3–4).
PREP="$ROOT/skills/converse-prep/SKILL.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-liveness-recheck-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { grep -qF -- "$2" "$3" && ok "$1" || bad "$1" "missing: $2"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -s "$SCRIPT" ]  || { echo "missing $SCRIPT" >&2; exit 1; }
[ -s "$SWEEP" ]  || { echo "missing $SWEEP" >&2; exit 1; }
[ -s "$PROMPT" ]  || { echo "missing $PROMPT" >&2; exit 1; }
[ -s "$PREP" ]  || { echo "missing $PREP" >&2; exit 1; }

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SCRIPT" ] && ok "liveness-recheck.sh is executable" \
    || bad "liveness-recheck.sh is executable" "chmod +x it, or the converse hook's -x guard skips it forever"
bash -n "$SCRIPT" && ok "liveness-recheck.sh: valid bash" \
    || bad "liveness-recheck.sh: valid bash" "bash -n failed"

# --- the gc stub -------------------------------------------------------------
# Answers each read the script performs from a file of its own, so a case can
# inject a failure:
#   gc bd list --id ... --all --json             <- $STUB_BEADS   ("FAIL" => exit 1)
#   gc bd gate list --json --limit 0             <- $STUB_GATES   ("FAIL" => exit 1)
#   gc bd ready --unassigned ...                 <- $STUB_READY   ("FAIL" => exit 1)
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
[ "$1" = "bd" ] || exit 0
case "$2" in
    list)  f="${STUB_BEADS:-}" ;;
    gate)  [ "${3:-}" = list ] || exit 0; f="${STUB_GATES:-}" ;;
    ready) f="${STUB_READY:-}" ;;
    *)     exit 0 ;;
esac
[ -n "$f" ] && [ -f "$f" ] || exit 1
[ "$(cat "$f")" = "FAIL" ] && exit 1
cat "$f"
GC
chmod +x "$TMP/bin/gc"
PATH="$TMP/bin:$PATH"; export PATH

bead() { # bead <id> <status> <metadata-json> [title]
    jq -nc --arg id "$1" --arg st "$2" --argjson m "$3" --arg t "${4:-a title}" \
        '{id: $id, title: $t, status: $st, priority: 1, issue_type: "bug",
          closed_at: (if $st == "closed" then "2026-08-12T02:44:44Z" else null end),
          metadata: $m}'
}
verdict_of() { printf '%s' "$1" | jq -r --arg id "$2" '[(.new[], .carried[]) | select(.id == $id)] | .[0].verdict // "ABSENT"'; }

STUB_BEADS="$TMP/beads.json";     export STUB_BEADS
STUB_READY="$TMP/ready.json";     export STUB_READY
STUB_GATES="$TMP/gates.json";     export STUB_GATES
# A human gate a person owes, as `gate list` prints it.
hgate() { jq -nc --arg id "$1" '{id: $id, issue_type: "gate", await_type: "human", await_id: "some-question", status: "open"}'; }
# Most cases have nobody owing anything; the ones that do overwrite this. With
# no gate open, bd prints null.
printf 'null\n' > "$STUB_GATES"

# --- 1. the verdict classes and their precedence -----------------------------
echo "── every listed id is re-derived into exactly one verdict ──"
jq -nc --argjson b "[
  $(bead b-idle    open   '{}')
 ,$(bead b-closed  closed '{"merge_result":"merged","pr_number":"316"}')
 ,$(bead b-routed  open   '{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}')
 ,$(bead b-held    open   '{"triage.hold":"waiting on the operator"}')
 ,$(bead b-take    open   '{"gc.takeaway":"routed — nothing further needed here"}')
 ,$(bead b-demand  open   '{"gc.takeaway":"holding — needs a decision"}' | jq -c '.dependencies = [{issue_id: "b-demand", depends_on_id: "g-1", type: "blocks"}]')
 ,$(bead b-stand   open   '{"task_kind":"feedback-pattern"}')
 ,$(bead b-parked  open   '{}')
 ,$(bead b-marker  open   '{"merge_result":"pull_request","pr_number":"349"}')
]" '$b' > "$STUB_BEADS"
# b-parked is absent from ready: a park/blocker edge appeared since the pass.
# b-stand IS ready — a standing record is open, unblocked and unassigned by
# design, which is exactly why every other test here reads it as idle.
jq -nc '[{id:"b-idle"},{id:"b-closed"},{id:"b-routed"},{id:"b-held"},{id:"b-take"},{id:"b-demand"},{id:"b-stand"},{id:"b-marker"}]' > "$STUB_READY"
printf '[%s,%s]\n' "$(hgate g-1)" "$(jq -nc '{id: "g-timer", issue_type: "gate", await_type: "timer", status: "open"}')" > "$STUB_GATES"
IDS="b-idle,b-closed,b-routed,b-held,b-take,b-demand,b-stand,b-parked,b-marker,b-gone"
C="$("$SCRIPT" --ids "$IDS" --json 2>/dev/null)"

eq "$(verdict_of "$C" b-idle)"   "idle"       "an unchanged bead stays on the agenda"
eq "$(verdict_of "$C" b-closed)" "resolved"   "a bead closed since the pass is resolved — do NOT route"
eq "$(verdict_of "$C" b-routed)" "worked"     "a route that appeared since the pass reads as worked"
eq "$(verdict_of "$C" b-held)"   "held"       "a triage.hold that appeared since the pass reads as held"
# A takeaway is stamped at a hold and REPLACED by its outcome at sign-off, and
# nothing clears it, so on its own it dates a sitting rather than naming a live
# wait. Flagged so the sitting reads what was concluded, and left on the agenda
# so nothing has to notice a board row to bring it back.
eq "$(verdict_of "$C" b-take)"   "recorded"   "a takeaway with no open gate records a sitting that ended"
eq "$(verdict_of "$C" b-demand)" "held"       "an OPEN human gate blocking the bead is the hold — a person owes that answer"
eq "$(verdict_of "$C" b-stand)"  "standing"   "a standing record is held-by-design, never an idle bead (tk-rw2ra)"
eq "$(verdict_of "$C" b-parked)" "not-ready"  "a bead that left the ready set was parked or blocked"
eq "$(verdict_of "$C" b-marker)" "marker"     "a merge_result marker is FLAGGED, not dropped"
eq "$(verdict_of "$C" b-gone)"   "unreadable" "an id the read did not return stays visible"

printf '%s' "$C" | jq -e '[(.new[], .carried[]) | select(.id == "b-demand")] | .[0].detail | test("human gate g-1 is open")' >/dev/null 2>&1 \
    && ok "the held detail names the gate a person has to clear" \
    || bad "the held detail names the gate" "$(printf '%s' "$C" | jq -r '[(.new[]) | select(.id == "b-demand")] | .[0].detail')"
printf '%s' "$C" | jq -e '[(.new[], .carried[]) | select(.id == "b-take")] | .[0].detail | test("gc.takeaway=routed")' >/dev/null 2>&1 \
    && ok "the recorded detail carries the takeaway text itself" \
    || bad "the recorded detail carries the takeaway" "$(printf '%s' "$C" | jq -r '[(.new[]) | select(.id == "b-take")] | .[0].detail')"

# The detail is what tells a sitting why it cannot disposition the bead: a
# standing record has no owner to chase and no close to wait for.
printf '%s' "$C" | jq -e '[(.new[], .carried[]) | select(.id == "b-stand")] | .[0].detail | test("task_kind=feedback-pattern")' >/dev/null 2>&1 \
    && ok "the standing-record detail names the kind" \
    || bad "the standing-record detail names the kind" "detail did not name task_kind"

eq "$(printf '%s' "$C" | jq -r '.summary.new_listed')" "10" "every listed id is accounted for"
eq "$(printf '%s' "$C" | jq -r '.summary.new_live')"   "4" "live agenda = idle + marker + recorded + unreadable (never the resolved/worked/held/standing/parked)"

# Mutate the guard: clear the gate (it leaves the not-closed gate listing) and
# the bead it held comes back onto the agenda under its own takeaway, its
# blocks edge left behind as bd leaves it. Re-runs the script into $CX; $C above
# stays the pre-mutation census. A gate of another type holds nothing either.
printf 'null\n' > "$STUB_GATES"
CX="$("$SCRIPT" --ids "$IDS" --json 2>/dev/null)"
eq "$(verdict_of "$CX" b-demand)" "recorded" "the gate clears → the bead it held is on the agenda again"
jq -nc '[{id: "g-1", issue_type: "gate", await_type: "timer", status: "open"}]' > "$STUB_GATES"
CX="$("$SCRIPT" --ids "$IDS" --json 2>/dev/null)"
eq "$(verdict_of "$CX" b-demand)" "recorded" "a gate that is not a human gate holds nothing"
printf '[%s]\n' "$(hgate g-1)" > "$STUB_GATES"

# The text report prints one bucket per verdict and NOTHING else, so a verdict
# with no bucket line is dropped from it silently while still counted in the
# JSON — a hidden bead, the one failure this whole script is built to avoid.
# Assert the rendered report, not just the census.
T="$("$SCRIPT" --ids "$IDS" --all 2>/dev/null)"
printf '%s' "$T" | grep -q "b-stand" \
    && ok "a standing record is PRINTED, not silently dropped from the report" \
    || bad "a standing record is PRINTED, not silently dropped from the report" "b-stand absent from the text report"
printf '%s' "$T" | grep -q "standing record" \
    && ok "its bucket says what it is, rather than filing it under a human hold" \
    || bad "its bucket says what it is, rather than filing it under a human hold" "no standing-record bucket in the report"
printf '%s' "$T" | grep -q "b-take" \
    && ok "a recorded takeaway is PRINTED, not silently dropped from the report" \
    || bad "a recorded takeaway is PRINTED, not silently dropped from the report" "b-take absent from the text report"
printf '%s' "$T" | grep -q "a sitting ended here" \
    && ok "its bucket says the takeaway is a record, not a wait" \
    || bad "its bucket says the takeaway is a record, not a wait" "no recorded bucket in the report"

echo "── every kind in the shared standing-kinds list re-checks as standing ──"
# The re-check and liveness-sweep.sh both read their standing kinds from
# assets/scripts/standing-kinds.sh, so they cannot disagree about which records
# are held by design. standing-kinds.test.sh asserts that both source it; here
# each listed kind runs through the re-check itself. The kinds are read from the
# shared definition, so a kind added there is covered with no edit to this file.
# shellcheck source=standing-kinds.sh
. "$ROOT/assets/scripts/standing-kinds.sh"
KINDS="$(jq -nr "$STANDING_KINDS_JQ"'standing_kinds[]')"
[ -n "$KINDS" ] && ok "the shared definition lists the standing kinds" \
    || bad "the shared definition lists the standing kinds" "standing_kinds read back empty"
SB='[]'; SR='[]'; SIDS=""
for k in $KINDS; do
    SB="$(printf '%s' "$SB" | jq -c --argjson b "$(bead "s-$k" open "$(jq -nc --arg k "$k" '{task_kind: $k}')")" '. + [$b]')"
    SR="$(printf '%s' "$SR" | jq -c --arg id "s-$k" '. + [{id: $id}]')"
    SIDS="${SIDS:+$SIDS,}s-$k"
done
printf '%s' "$SB" > "$STUB_BEADS"; printf '%s' "$SR" > "$STUB_READY"
C="$("$SCRIPT" --ids "$SIDS" --json 2>/dev/null)"
for k in $KINDS; do
    eq "$(verdict_of "$C" "s-$k")" "standing" "a task_kind=$k record re-checks as standing"
done

echo "── an assignee alone marks a bead worked, and closed beats every other signal ──"
jq -nc --argjson b "[
  $(bead b-assigned open   '{}')
 ,$(bead b-cr       closed '{"gc.routed_to":"gc-toolkit/gc-toolkit.refinery","merge_result":"merged"}')
]" '$b | (.[0] | .assignee) = "gc-toolkit/gc-toolkit.furiosa"' > "$STUB_BEADS"
jq -nc '[{id:"b-assigned"},{id:"b-cr"}]' > "$STUB_READY"
C="$("$SCRIPT" --ids "b-assigned,b-cr" --json 2>/dev/null)"
eq "$(verdict_of "$C" b-assigned)" "worked"   "an assignee alone is enough to read as worked"
eq "$(verdict_of "$C" b-cr)"       "resolved" "closed outranks a leftover route — the disposition differs"

echo "── a work bead marked only by gc.execution_routed_to reads as worked ──"
# A slung work bead's claim moves its pool route to gc.execution_routed_to and
# leaves assignee and gc.routed_to empty. It is unassigned and unblocked, so it
# stays in the ready set — which is why the miss surfaced as "idle", not
# "not-ready", and a sitting re-slung work already in flight.
jq -nc --argjson b "[$(bead b-exec open '{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}')]" '$b' > "$STUB_BEADS"
jq -nc '[{id:"b-exec"}]' > "$STUB_READY"
C="$("$SCRIPT" --ids "b-exec" --json 2>/dev/null)"
eq "$(verdict_of "$C" b-exec)" "worked" "an execution route alone reads as worked, not idle"
printf '%s' "$C" | jq -e '[(.new[], .carried[]) | select(.id == "b-exec")] | .[0].detail | test("execution_routed_to=gc-toolkit/gc-toolkit.polecat")' >/dev/null 2>&1 \
    && ok "the worked detail names the execution route" \
    || bad "the worked detail names the execution route" "$(printf '%s' "$C" | jq -r '[.new[] | select(.id == "b-exec")] | .[0].detail')"

echo "── a bead held for placement reads as that wait, whatever else it carries ──"
# Intake marks new work placement=pending and leaves it unrouted, and
# gc-helm.sh unplaced lists it for the placement sitting. A visit the sweep
# filed before intake held the bead still lists it, and reading it as idle or
# recorded would put the same decision on this sitting's agenda too. The queue
# lists such a bead whether or not a blocker holds it or the first reaction left
# its takeaway, so neither sends it to not-ready, recorded or idle. A parent or
# a route places the bead whatever its marker says, and an open human gate is a
# person's answer owed, which outranks the wait as it does in the sweep.
jq -nc --argjson b "[
  $(bead p-plain    open '{"placement":"pending"}')
 ,$(bead p-take     open '{"placement":"pending","gc.takeaway":"actionable — held for placement"}')
 ,$(bead p-blocked  open '{"placement":"pending"}')
 ,$(bead p-blk-take open '{"placement":"pending","gc.takeaway":"blocked — held for placement"}')
 ,$(bead p-parent   open '{"placement":"pending"}')
 ,$(bead p-routed   open '{"placement":"pending","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}')
 ,$(bead p-demand   open '{"placement":"pending"}')
]" '$b
  | map(if (.id == "p-blocked" or .id == "p-blk-take") then .dependencies = [{depends_on_id: "tk-blocker", type: "blocks"}] else . end)
  | map(if .id == "p-parent" then (.parent = "tk-epic" | .dependencies = [{depends_on_id: "tk-epic", type: "parent-child"}]) else . end)
  | map(if .id == "p-demand" then .dependencies = [{depends_on_id: "g-2", type: "blocks"}] else . end)' > "$STUB_BEADS"
# The two blocked beads and the one a gate holds left the ready set.
jq -nc '[{id:"p-plain"},{id:"p-take"},{id:"p-parent"},{id:"p-routed"}]' > "$STUB_READY"
printf '[%s]\n' "$(hgate g-2)" > "$STUB_GATES"
PIDS="p-plain,p-take,p-blocked,p-blk-take,p-parent,p-routed,p-demand"
C="$("$SCRIPT" --ids "$PIDS" --json 2>/dev/null)"
eq "$(verdict_of "$C" p-plain)"    "awaiting-placement" "a bead held for placement reads as that wait, not idle"
eq "$(verdict_of "$C" p-take)"     "awaiting-placement" "…with the first reaction's takeaway on it, not recorded"
eq "$(verdict_of "$C" p-blocked)"  "awaiting-placement" "…with a blocker holding it, not not-ready"
eq "$(verdict_of "$C" p-blk-take)" "awaiting-placement" "…with a takeaway and a blocker both"
eq "$(verdict_of "$C" p-parent)"   "idle"               "a parent places the bead whatever its marker says"
eq "$(verdict_of "$C" p-routed)"   "worked"             "a route places the bead whatever its marker says"
eq "$(verdict_of "$C" p-demand)"   "held"               "an open human gate outranks the placement wait"
eq "$(printf '%s' "$C" | jq -r '.summary.new_live')" "1" \
   "the placement wait is not on this sitting's live agenda (only the placed, idle bead is)"
printf '%s' "$C" | jq -e '[.new[] | select(.id == "p-take")] | .[0].detail | test("gc.takeaway=actionable")' >/dev/null 2>&1 \
    && ok "the placement detail carries the first reaction's takeaway" \
    || bad "the placement detail carries the first reaction's takeaway" "$(printf '%s' "$C" | jq -r '[.new[] | select(.id == "p-take")] | .[0].detail')"
T="$("$SCRIPT" --ids "$PIDS" 2>/dev/null)"
printf '%s' "$T" | grep -q "p-blk-take" \
    && ok "a bead held for placement is PRINTED, not silently dropped from the report" \
    || bad "a bead held for placement is PRINTED, not silently dropped from the report" "p-blk-take absent from the text report"
printf '%s' "$T" | grep -q "gc-helm.sh unplaced lists it" \
    && ok "its bucket names the queue that lists it" \
    || bad "its bucket names the queue that lists it" "no placement bucket in the report"
# The rule reads the bead's own row, not the ready set, so a failed ready read
# leaves the wait named.
printf 'FAIL\n' > "$STUB_READY"
C="$("$SCRIPT" --ids "p-plain,p-blocked" --json 2>/dev/null)"
eq "$(verdict_of "$C" p-plain)$(verdict_of "$C" p-blocked)" "awaiting-placementawaiting-placement" \
   "with the ready set unverified, a bead held for placement still reads as that wait"
printf 'null\n' > "$STUB_GATES"

# --- 2. report-don't-hide on every failure path ------------------------------
echo "── the bead read failing prints NO census (a partial one looks complete) ──"
printf 'FAIL\n' > "$STUB_BEADS"
jq -nc '[]' > "$STUB_READY"
OUT="$("$SCRIPT" --ids "b-idle" 2>/dev/null)"; RC=$?
[ "$RC" -ne 0 ] && ok "a failed bead read exits non-zero" \
    || bad "a failed bead read exits non-zero" "got rc=$RC"
[ -z "$OUT" ] && ok "a failed bead read prints nothing on stdout" \
    || bad "a failed bead read prints nothing on stdout" "printed: $OUT"

echo "── the ready read failing SKIPS the not-ready rule (never hides the agenda) ──"
# The inverse defect this guards: trusting a failed ready read would make every
# listed bead 'not-ready', i.e. gated, i.e. gone from the sitting's agenda.
jq -nc --argjson b "[$(bead b-idle open '{}'),$(bead b-idle2 open '{}')]" '$b' > "$STUB_BEADS"
printf 'FAIL\n' > "$STUB_READY"
C="$("$SCRIPT" --ids "b-idle,b-idle2" --json 2>/dev/null)"
eq "$(printf '%s' "$C" | jq -r '.ready_state')" "unverified" "a failed ready read is reported as unverified, not as an empty set"
eq "$(verdict_of "$C" b-idle)"  "idle" "with the ready set unverified, a candidate stays on the agenda"
eq "$(verdict_of "$C" b-idle2)" "idle" "…for every candidate, not just the first"
eq "$(printf '%s' "$C" | jq -r '[.new[] | select(.verdict == "not-ready")] | length')" "0" \
   "no bead is classified not-ready off an unverified ready read"
"$SCRIPT" --ids "b-idle" 2>/dev/null | grep -q "WARNING: the ready read failed" \
    && ok "the report says the ready read failed" \
    || bad "the report says the ready read failed" "no WARNING line in the human report"

echo "── the human-gate read failing holds NOTHING (never hides the agenda) ──"
# The inverse defect: an unread gate listing that held every bead would empty
# the agenda outright. pr-facts.sh and signoff.sh answer "held" on the same
# unreadable probe, because there releasing an anchor hands a person's decision
# back to a pool. Here the cost runs the other way — a bead nothing reports is a
# bead nobody comes back to — so an unread probe holds nothing, and says so.
jq -nc --argjson b "[$(bead b-take open '{"gc.takeaway":"routed — nothing further needed here"}' | jq -c '.dependencies = [{issue_id: "b-take", depends_on_id: "g-1", type: "blocks"}]')]" '$b' > "$STUB_BEADS"
jq -nc '[{id:"b-take"}]' > "$STUB_READY"
printf 'FAIL\n' > "$STUB_GATES"
C="$("$SCRIPT" --ids "b-take" --json 2>/dev/null)"
eq "$(printf '%s' "$C" | jq -r '.gate_state')" "unverified" "a failed gate read is reported as unverified, not as an empty set"
eq "$(verdict_of "$C" b-take)" "recorded" "with gates unverified, the bead stays on the agenda"
eq "$(printf '%s' "$C" | jq -r '[.new[] | select(.verdict == "held")] | length')" "0" \
   "no bead is classified held off an unverified gate read"
"$SCRIPT" --ids "b-take" 2>/dev/null | grep -q "WARNING: the human-gate read failed" \
    && ok "the report says the gate read failed" \
    || bad "the report says the gate read failed" "no WARNING line in the human report"
printf 'null\n' > "$STUB_GATES"

echo "── PR liveness is never re-checked, and the report says so ──"
jq -nc --argjson b "[$(bead b-marker open '{"merge_result":"pull_request","pr_number":"349"}')]" '$b' > "$STUB_BEADS"
jq -nc '[{id:"b-marker"}]' > "$STUB_READY"
REPORT="$("$SCRIPT" --ids "b-marker" 2>/dev/null)"
printf '%s' "$REPORT" | grep -q "PR liveness NOT re-checked" \
    && ok "the header states PR liveness is not re-checked" \
    || bad "the header states PR liveness is not re-checked" "no such line"
printf '%s' "$REPORT" | grep -q "b-marker" \
    && ok "a PR-marked bead is still listed" \
    || bad "a PR-marked bead is still listed" "the marker dropped it — the inverse defect"
eq "$("$SCRIPT" --ids "b-marker" --json 2>/dev/null | jq -r '.pr_liveness')" "not-rechecked" \
   "the JSON census declares pr_liveness=not-rechecked"

# --- 3. the census flags are the input ----------------------------------------
echo "── --ids, --carried and --pass-at drive the census ──"
jq -nc --argjson b "[
  $(bead b-idle   open   '{}')
 ,$(bead b-closed closed '{"merge_result":"merged"}')
 ,$(bead b-held   open   '{"triage.hold":"parked by the operator"}')
]" '$b' > "$STUB_BEADS"
jq -nc '[{id:"b-idle"},{id:"b-closed"},{id:"b-held"}]' > "$STUB_READY"
C="$("$SCRIPT" --ids b-idle,b-closed --carried b-held --pass-at 2026-08-12T00:10:00Z --json 2>/dev/null)"
eq "$(printf '%s' "$C" | jq -r '[.new[].id] | join(",")')"     "b-idle,b-closed" "--ids becomes the new section"
eq "$(printf '%s' "$C" | jq -r '[.carried[].id] | join(",")')" "b-held"          "--carried becomes the carried section"
eq "$(printf '%s' "$C" | jq -r '.pass_at')" "2026-08-12T00:10:00Z" "the census cut travels with --pass-at"
"$SCRIPT" --ids b-idle,b-closed --carried b-held --pass-at 2026-08-12T00:10:00Z 2>/dev/null | grep -q "2026-08-12T00:10:00Z" \
    && ok "the report leads with the census cut" \
    || bad "the report leads with the census cut" "no pass timestamp in the header"
# 1786493400 is that cut, 2026-08-12T00:10:00Z. The script reads the clock
# between the two samples taken here, so its age matches what one of them
# gives. HST10 is ten hours behind UTC, so a parse that read the cut as local
# time would be ten hours out.
age_at() { awk -v a=1786493400 -v b="$1" 'BEGIN { printf "%.1fh", (b - a) / 3600 }'; }
T0=$(date -u +%s)
AGE=$(TZ=HST10 "$SCRIPT" --ids b-idle --pass-at 2026-08-12T00:10:00Z --json 2>/dev/null | jq -r '.age')
T1=$(date -u +%s)
case "$AGE" in
    "$(age_at "$T0")"|"$(age_at "$T1")") ok "the census reports how long ago the cut was ($AGE)" ;;
    *) bad "the census reports how long ago the cut was" "got '$AGE' want '$(age_at "$T0")'" ;;
esac

echo "── an id in both lists is counted once, as NEW (the agenda outranks the background) ──"
C="$("$SCRIPT" --ids b-idle --carried b-idle,b-held --json 2>/dev/null)"
eq "$(printf '%s' "$C" | jq -r '[.new[].id] | join(",")')"     "b-idle" "the duplicate stays in the new section"
eq "$(printf '%s' "$C" | jq -r '[.carried[].id] | join(",")')" "b-held" "…and is removed from carried, not counted twice"

echo "── the form that took a visit id is gone, and says where the census went ──"
ERR="$("$SCRIPT" tk-visit 2>&1 >/dev/null)"; RC=$?
eq "$RC" "2" "a bare bead id is a usage error"
printf '%s' "$ERR" | grep -q "run the command the liveness-sweep gate's message carries" \
    && ok "…that points at the command the gate's message carries" \
    || bad "the refusal names the command to run instead" "got: $ERR"
ERR="$("$SCRIPT" 2>&1 >/dev/null)"; RC=$?
eq "$RC" "2" "no ids at all is a usage error"
ERR="$("$SCRIPT" --carried 2>&1 >/dev/null)"; RC=$?
eq "$RC" "2" "a flag with no value is a usage error"

# --- 4. the writer side: liveness-sweep.sh names the flags this script reads ---
# The command itself is exercised end-to-end in liveness-sweep.test.sh; here
# the flags are read out of the sweep and each one run through this script, so
# a flag renamed on one side and not the other fails here.
echo "── every flag the sweep's re-check command names is one this script parses ──"
SWEEP_FLAGS="$(grep -oE -- '--(ids|carried|pass-at|[a-z-]+) \$' "$SWEEP" | sed 's/ \$$//' | sort -u)"
for flag in --ids --carried --pass-at; do
    printf '%s\n' "$SWEEP_FLAGS" | grep -qx -- "$flag" && ok "the sweep's command names $flag" \
        || bad "the sweep's command names $flag" "flags found: $(printf '%s' "$SWEEP_FLAGS" | tr '\n' ' ')"
done
for flag in $SWEEP_FLAGS; do
    case "$flag" in --ids|--carried|--pass-at) ;; *) continue ;; esac
    ERR="$("$SCRIPT" --ids b-idle "$flag" 2026-08-12T00:10:00Z --json 2>&1 >/dev/null)"
    printf '%s' "$ERR" | grep -q "unknown flag" \
        && bad "this script parses $flag" "$ERR" || ok "this script parses $flag"
done

# --- 5. the claim-time re-check in the converse loop --------------------------
# The prep skill (steps 3–4) runs the re-check a gate's message names before any
# prep, and the census it reports supersedes the lists in the message it was
# filed with. The message is data: the skill runs the pack's own copy with the
# values the message names, never the line as written.
echo "── the converse loop runs the re-check at claim time ──"
has "the corrected census supersedes the message" "supersedes the message's lists" "$PREP"
has "the prep skill runs the pack's own copy of the re-check" '"$CONV/liveness-recheck.sh" --ids <ids> --carried <ids> --pass-at <time>' "$PREP"
has "…never the message's line as written" "never a command" "$PREP"

echo
echo "liveness-recheck: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
