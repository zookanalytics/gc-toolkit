#!/usr/bin/env bash
# liveness-recheck.test.sh — the liveness-sweep visit body is a SNAPSHOT, and
# the sitting that reads it is entitled to a corrected census (bead tk-gvas6).
#
# THE DEFECT. classify writes its census into the visit body at pass time; the
# converse sitting reads that body whenever the visit is claimed, which is
# routinely a day or more later, and nothing re-checked it in between. Measured
# on visit 8 of tk-hok6w (visit tk-3qeq0): the pass cut 2026-08-12T00:10Z, the
# sitting read it ~41.5h later, and FIVE of the ten new candidates had merged
# AND deployed in the interval (tk-1u8mi #316, tk-7g37t #322, tk-xesf6 #325,
# tk-5ttye #328, tk-pe1hd #332 — the headline P0). 60% of that body was wrong on
# arrival. A sitting that trusts such a body routes already-merged work and
# burns a polecat on a no-op — already on this scope's record (visit 4 routed
# tk-yjtf, closed as a no-op 30 minutes later).
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
#   2. THE WIRING that makes it fire. liveness-sweep.sh stamps the id lists
#      and the visit.recheck PATH (covered by liveness-sweep.test.sh); here the
#      converse loop's claim-time hook is asserted to read `visit.recheck` as a
#      PATH and run it, never to eval a command string, and the stamp key /
#      standing-kinds list are pinned against liveness-sweep.sh so the writer
#      and the reader cannot drift apart.
# Hermetic: reads the repo, stubs `gc`; no city, no Dolt, no network, no gh.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/assets/scripts/liveness-recheck.sh"
SWEEP="$ROOT/assets/scripts/liveness-sweep.sh"
PROMPT="$ROOT/agents/converse/prompt.template.md"
TMP="$(mktemp -d)"
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

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SCRIPT" ] && ok "liveness-recheck.sh is executable" \
    || bad "liveness-recheck.sh is executable" "chmod +x it, or the converse hook's -x guard skips it forever"
bash -n "$SCRIPT" && ok "liveness-recheck.sh: valid bash" \
    || bad "liveness-recheck.sh: valid bash" "bash -n failed"

# --- the gc stub -------------------------------------------------------------
# Answers the four reads the script performs, each from a file so a case can
# inject a failure. Both bead reads are `bd list`; the demand one is the one
# carrying --has-metadata-key, which is how the stub tells them apart:
#   gc bd show <visit> --json                    <- $STUB_VISIT   ("FAIL" => exit 1)
#   gc bd list --id ... --all --json             <- $STUB_BEADS   ("FAIL" => exit 1)
#   gc bd list --has-metadata-key gc.demand_for  <- $STUB_DEMANDS ("FAIL" => exit 1)
#   gc bd ready --unassigned ...                 <- $STUB_READY   ("FAIL" => exit 1)
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || exit 0
demandq=""
for a in "$@"; do case "$a" in --has-metadata-key) demandq=1 ;; esac; done
case "$2" in
    show)  f="${STUB_VISIT:-}" ;;
    list)  if [ -n "$demandq" ]; then f="${STUB_DEMANDS:-}"; else f="${STUB_BEADS:-}"; fi ;;
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
verdict_of() { printf '%s' "$1" | jq -r --arg id "$2" '[(.new[], .promoted[]?, .carried[]) | select(.id == $id)] | .[0].verdict // "ABSENT"'; }

STUB_VISIT="$TMP/visit.json";     export STUB_VISIT
STUB_BEADS="$TMP/beads.json";     export STUB_BEADS
STUB_READY="$TMP/ready.json";     export STUB_READY
STUB_DEMANDS="$TMP/demands.json"; export STUB_DEMANDS
# Most cases have nobody owing anything; the ones that do overwrite this.
printf '[]\n' > "$STUB_DEMANDS"

# --- 1. the verdict classes and their precedence -----------------------------
echo "── every listed id is re-derived into exactly one verdict ──"
jq -nc --argjson b "[
  $(bead b-idle    open   '{}')
 ,$(bead b-closed  closed '{"merge_result":"merged","pr_number":"316"}')
 ,$(bead b-routed  open   '{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}')
 ,$(bead b-held    open   '{"triage.hold":"waiting on the operator"}')
 ,$(bead b-take    open   '{"gc.takeaway":"routed — nothing further needed here"}')
 ,$(bead b-demand  open   '{"gc.takeaway":"holding — needs a decision"}')
 ,$(bead b-stand   open   '{"task_kind":"feedback-pattern"}')
 ,$(bead b-parked  open   '{}')
 ,$(bead b-marker  open   '{"merge_result":"pull_request","pr_number":"349"}')
]" '$b' > "$STUB_BEADS"
# b-parked is absent from ready: a park/blocker edge appeared since the pass.
# b-stand IS ready — a standing record is open, unblocked and unassigned by
# design, which is exactly why every other test here reads it as idle.
jq -nc '[{id:"b-idle"},{id:"b-closed"},{id:"b-routed"},{id:"b-held"},{id:"b-take"},{id:"b-demand"},{id:"b-stand"},{id:"b-marker"}]' > "$STUB_READY"
jq -nc '[{id:"d-1",metadata:{"gc.demand_for":"b-demand"}}]' > "$STUB_DEMANDS"
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
eq "$(verdict_of "$C" b-take)"   "recorded"   "a takeaway with no open demand records a sitting that ended"
eq "$(verdict_of "$C" b-demand)" "held"       "an OPEN demand on the bead is the hold — a person owes that answer"
eq "$(verdict_of "$C" b-stand)"  "standing"   "a standing record is held-by-design, never an idle bead (tk-rw2ra)"
eq "$(verdict_of "$C" b-parked)" "not-ready"  "a bead that left the ready set was parked or blocked"
eq "$(verdict_of "$C" b-marker)" "marker"     "a merge_result marker is FLAGGED, not dropped"
eq "$(verdict_of "$C" b-gone)"   "unreadable" "an id the read did not return stays visible"

printf '%s' "$C" | jq -e '[(.new[], .carried[]) | select(.id == "b-demand")] | .[0].detail | test("demand d-1 is open")' >/dev/null 2>&1 \
    && ok "the held detail names the demand bead a person has to answer" \
    || bad "the held detail names the demand bead" "$(printf '%s' "$C" | jq -r '[(.new[]) | select(.id == "b-demand")] | .[0].detail')"
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

# Mutate the guard: close the demand (it leaves every not-closed listing) and
# the bead it held comes back onto the agenda under its own takeaway. Re-runs
# the script into $CX; $C above stays the pre-mutation census.
jq -nc '[]' > "$STUB_DEMANDS"
CX="$("$SCRIPT" --ids "$IDS" --json 2>/dev/null)"
eq "$(verdict_of "$CX" b-demand)" "recorded" "the demand closes → the bead it held is on the agenda again"
jq -nc '[{id:"d-1",metadata:{"gc.demand_for":"b-demand"}}]' > "$STUB_DEMANDS"

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

echo "── an assignee alone marks a bead worked, and closed beats every other signal ──"
jq -nc --argjson b "[
  $(bead b-assigned open   '{}')
 ,$(bead b-cr       closed '{"gc.routed_to":"gc-toolkit/gc-toolkit.refinery","merge_result":"merged"}')
]" '$b | (.[0] | .assignee) = "gc-toolkit/gc-toolkit.furiosa"' > "$STUB_BEADS"
jq -nc '[{id:"b-assigned"},{id:"b-cr"}]' > "$STUB_READY"
C="$("$SCRIPT" --ids "b-assigned,b-cr" --json 2>/dev/null)"
eq "$(verdict_of "$C" b-assigned)" "worked"   "an assignee alone is enough to read as worked"
eq "$(verdict_of "$C" b-cr)"       "resolved" "closed outranks a leftover route — the disposition differs"

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

echo "── the demand read failing holds NOTHING (never hides the agenda) ──"
# The inverse defect: an unread demand listing that held every bead would empty
# the agenda outright. pr-facts.sh and signoff.sh answer "held" on the same
# unreadable probe, because there releasing an anchor hands a person's decision
# back to a pool. Here the cost runs the other way — a bead nothing reports is a
# bead nobody comes back to — so an unread probe holds nothing, and says so.
jq -nc --argjson b "[$(bead b-take open '{"gc.takeaway":"routed — nothing further needed here"}')]" '$b' > "$STUB_BEADS"
jq -nc '[{id:"b-take"}]' > "$STUB_READY"
printf 'FAIL\n' > "$STUB_DEMANDS"
C="$("$SCRIPT" --ids "b-take" --json 2>/dev/null)"
eq "$(printf '%s' "$C" | jq -r '.demand_state')" "unverified" "a failed demand read is reported as unverified, not as an empty set"
eq "$(verdict_of "$C" b-take)" "recorded" "with demands unverified, the bead stays on the agenda"
eq "$(printf '%s' "$C" | jq -r '[.new[] | select(.verdict == "held")] | length')" "0" \
   "no bead is classified held off an unverified demand read"
"$SCRIPT" --ids "b-take" 2>/dev/null | grep -q "WARNING: the open-demand read failed" \
    && ok "the report says the demand read failed" \
    || bad "the report says the demand read failed" "no WARNING line in the human report"
printf '[]\n' > "$STUB_DEMANDS"

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

# --- 3. the visit stamps are the input, and their absence is legible ---------
echo "── a visit's stamped id lists drive the census ──"
jq -nc '[{metadata: {"sweep.new_ids": "b-idle,b-closed", "sweep.carried_ids": "b-held",
                     "sweep.pass_at": "2026-08-12T00:10:00Z",
                     "gc.continuation_group": "tk-subject"}}]' > "$STUB_VISIT"
jq -nc --argjson b "[
  $(bead b-idle   open   '{}')
 ,$(bead b-closed closed '{"merge_result":"merged"}')
 ,$(bead b-held   open   '{"triage.hold":"parked by the operator"}')
]" '$b' > "$STUB_BEADS"
jq -nc '[{id:"b-idle"},{id:"b-closed"},{id:"b-held"}]' > "$STUB_READY"
C="$("$SCRIPT" tk-visit --json 2>/dev/null)"
eq "$(printf '%s' "$C" | jq -r '[.new[].id] | join(",")')"     "b-idle,b-closed" "sweep.new_ids becomes the new section"
eq "$(printf '%s' "$C" | jq -r '[.carried[].id] | join(",")')" "b-held"          "sweep.carried_ids becomes the carried section"
eq "$(printf '%s' "$C" | jq -r '.pass_at')" "2026-08-12T00:10:00Z" "the census cut travels with the visit"
eq "$(printf '%s' "$C" | jq -r '.subject')" "tk-subject"           "the subject is read from the continuation group"
"$SCRIPT" tk-visit 2>/dev/null | grep -q "2026-08-12T00:10:00Z" \
    && ok "the report leads with the census cut" \
    || bad "the report leads with the census cut" "no pass timestamp in the header"

echo "── an id in both lists is counted once, as NEW (the agenda outranks the background) ──"
jq -nc '[{metadata: {"sweep.new_ids": "b-idle", "sweep.carried_ids": "b-idle,b-held"}}]' > "$STUB_VISIT"
C="$("$SCRIPT" tk-visit --json 2>/dev/null)"
eq "$(printf '%s' "$C" | jq -r '[.new[].id] | join(",")')"     "b-idle" "the duplicate stays in the new section"
eq "$(printf '%s' "$C" | jq -r '[.carried[].id] | join(",")')" "b-held" "…and is removed from carried, not counted twice"

echo "── the rotated carried slice stays TITLED in the claim-time census (no --all) ──"
# The sweep promotes a bounded slice of the carried backlog into the agenda each
# pass, but a sitting works from THIS census, not the visit body, and the converse
# hook runs the re-check without --all. If the promoted slice collapsed back into
# the bare carried-id list here the rotation would be cosmetic and those beads
# skipped again. sweep.carried_promoted_ids names the slice; it must print as its
# own titled section while the REST of the carried backlog stays bare unless --all
# (the bounded-cost design is preserved).
jq -nc '[{metadata: {"sweep.new_ids": "b-idle",
                     "sweep.carried_ids": "k-promo,k-rest",
                     "sweep.carried_promoted_ids": "k-promo",
                     "sweep.pass_at": "2026-08-12T00:10:00Z"}}]' > "$STUB_VISIT"
jq -nc --argjson b "[
  $(bead b-idle  open '{}' 'the new one')
 ,$(bead k-promo open '{}' 'PROMOTED-TITLE re-examine me')
 ,$(bead k-rest  open '{}' 'RESTCARRIED-TITLE still bare')
]" '$b' > "$STUB_BEADS"
jq -nc '[{id:"b-idle"},{id:"k-promo"},{id:"k-rest"}]' > "$STUB_READY"
C="$("$SCRIPT" tk-visit --json 2>/dev/null)"
eq "$(printf '%s' "$C" | jq -r '[.promoted[].id] | join(",")')" "k-promo" "the promoted slice becomes its own re-examined section"
eq "$(printf '%s' "$C" | jq -r '[.carried[].id] | join(",")')" "k-rest"  "…and is removed from the bare carried list, not shown twice"
eq "$(verdict_of "$C" k-promo)" "idle" "a still-open promoted bead is on the live agenda"
eq "$(printf '%s' "$C" | jq -r '.summary.promoted_live')" "1" "the summary counts the re-examined live"
R="$("$SCRIPT" tk-visit 2>/dev/null)"
printf '%s' "$R" | grep -q "PROMOTED-TITLE" \
    && ok "the promoted bead's TITLE renders without --all (the sitting re-examines it by name)" \
    || bad "promoted title without --all" "$R"
printf '%s' "$R" | grep -q "RE-EXAMINED" \
    && ok "the census names the RE-EXAMINED section" \
    || bad "re-examined section header" "$R"
printf '%s' "$R" | grep -q "RESTCARRIED-TITLE" \
    && bad "the rest of the carried backlog stays bare without --all" "k-rest title leaked — bounded cost broken" \
    || ok "the rest of the carried backlog stays bare without --all (bounded cost preserved)"
printf '%s' "$R" | grep -q "k-rest" \
    && ok "…but the bare carried id is still listed, nothing hidden" \
    || bad "k-rest listed as a bare id" "$R"
R2="$("$SCRIPT" tk-visit --all 2>/dev/null)"
printf '%s' "$R2" | grep -q "RESTCARRIED-TITLE" \
    && ok "--all still titles the rest of the carried backlog" \
    || bad "--all titles the rest of carried" "$R2"

echo "── an id both new and promoted is listed once as NEW; a plain carried copy drops ──"
jq -nc '[{metadata: {"sweep.new_ids": "x1",
                     "sweep.carried_ids": "x1,x2,x3",
                     "sweep.carried_promoted_ids": "x1,x2"}}]' > "$STUB_VISIT"
jq -nc --argjson b "[$(bead x1 open '{}'),$(bead x2 open '{}'),$(bead x3 open '{}')]" '$b' > "$STUB_BEADS"
jq -nc '[{id:"x1"},{id:"x2"},{id:"x3"}]' > "$STUB_READY"
C="$("$SCRIPT" tk-visit --json 2>/dev/null)"
eq "$(printf '%s' "$C" | jq -r '[.new[].id] | join(",")')"      "x1" "an id both new and promoted stays in NEW"
eq "$(printf '%s' "$C" | jq -r '[.promoted[].id] | join(",")')" "x2" "the promoted slice keeps only what NEW did not claim"
eq "$(printf '%s' "$C" | jq -r '[.carried[].id] | join(",")')"  "x3" "the bare carried list keeps only what neither claimed"

echo "── a visit filed before the stamps shipped says so instead of guessing ──"
jq -nc '[{metadata: {"task_kind": "visit"}}]' > "$STUB_VISIT"
ERR="$("$SCRIPT" tk-visit 2>&1 >/dev/null)"; RC=$?
[ "$RC" -ne 0 ] && ok "an unstamped visit exits non-zero" || bad "an unstamped visit exits non-zero" "got rc=$RC"
printf '%s' "$ERR" | grep -q "sweep.new_ids" \
    && ok "the error names the missing stamps and the by-hand fallback" \
    || bad "the error names the missing stamps and the by-hand fallback" "got: $ERR"

echo "── an unreadable visit re-checks nothing rather than re-checking an empty set ──"
printf 'FAIL\n' > "$STUB_VISIT"
"$SCRIPT" tk-visit >/dev/null 2>&1 \
    && bad "an unreadable visit exits non-zero" "exited 0" \
    || ok "an unreadable visit exits non-zero"

# --- 4. the writer side: liveness-sweep.sh stamps what the re-check reads ----
# The stamping behaviour itself is exercised end-to-end in
# liveness-sweep.test.sh; here the key strings are pinned so writer and
# reader cannot drift apart.
echo "── liveness-sweep.sh stamps the keys this script reads ──"
for key in sweep.new_ids sweep.carried_ids sweep.carried_promoted_ids sweep.pass_at visit.recheck; do
    grep -qF "$key=" "$SWEEP" && ok "the sweep stamps $key" \
        || bad "the sweep stamps $key" "no $key= write in $SWEEP"
done

# --- 5. the claim-time hook in the converse loop -----------------------------
# The stamp only matters if something runs it. The sitting is where the body is
# read, so the hook lives in the prep step — before any prep, not after.
echo "── the converse loop runs the re-check at claim time ──"
has "the prep step reads visit.recheck"      'visit.recheck'            "$PROMPT"
has "an -x guard, so a missing copy is loud" '[ -x "$RECHECK" ]'        "$PROMPT"
grep -qE 'eval +"?\$RECHECK' "$PROMPT" \
    && bad "the hook never evals a metadata string" "found an eval of \$RECHECK — the stamp is a path, so read-then-run is available" \
    || ok "the hook never evals a metadata string"
has "the corrected census supersedes the body" "supersedes the body's lists" "$PROMPT"

# The seam between the two files is where this fix can rot without either side
# looking wrong, so the hook is EXECUTED rather than grepped: the stamp key the
# sweep writes and the key the prompt reads have to be the same string, and a
# text assertion on each file separately would not notice them drifting apart.
extract() { awk -v m="$1" '$0 ~ ("# >>> " m) {inb=1; next} $0 ~ ("# <<< " m) {inb=0} inb' "$2"; }
extract visit-recheck-hook "$PROMPT" | sed 's/^   //' > "$TMP/hook.sh"
[ -s "$TMP/hook.sh" ] && ok "visit-recheck-hook block present in the converse prompt" \
    || bad "visit-recheck-hook block present in the converse prompt" "no marked block in $PROMPT"
bash -n "$TMP/hook.sh" && ok "visit-recheck-hook: valid bash" \
    || bad "visit-recheck-hook: valid bash" "bash -n failed"

# The one string that has to agree across the two files, read out of each side
# rather than asserted against a literal here: if this test spelled the key
# itself, a rename in the formula plus a matching rename in the test would pass
# while the converse hook silently read a key nobody writes any more.
STAMP_KEY=$(sed -n 's/.*"\(visit\.[a-z_]*\)=.*/\1/p' "$SWEEP" | head -1)
HOOK_KEY=$(sed -n 's/.*metadata\["\(visit\.[a-z_]*\)"\].*/\1/p' "$TMP/hook.sh" | head -1)
[ -n "$STAMP_KEY" ] && ok "the sweep writes a visit.* key" \
    || bad "the sweep writes a visit.* key" "found none in liveness-sweep.sh"
eq "$HOOK_KEY" "$STAMP_KEY" "the key the sweep stamps is the key the sitting reads"

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] && [ "$2" = "show" ] || exit 0
cat "${STUB_VISIT:-/dev/null}"
GC
chmod +x "$TMP/bin/gc"
# A stand-in for liveness-recheck.sh that records how it was invoked.
cat > "$TMP/fake-recheck" <<'RC'
#!/usr/bin/env bash
printf 'invoked with: %s\n' "$*"
RC
chmod +x "$TMP/fake-recheck"
jq -nc --arg p "$TMP/fake-recheck" '[{metadata: {"visit.recheck": $p}}]' > "$STUB_VISIT"
OUT="$(VISIT=tk-visit bash "$TMP/hook.sh" 2>&1)"
eq "$OUT" "invoked with: tk-visit" "the hook runs the stamped path with the visit id as its only argument"

echo "── the hook is loud, not silent, when the stamped path is not executable ──"
jq -nc --arg p "$TMP/not-there" '[{metadata: {"visit.recheck": $p}}]' > "$STUB_VISIT"
OUT="$(VISIT=tk-visit bash "$TMP/hook.sh" 2>&1)"
printf '%s' "$OUT" | grep -q "UNVERIFIED" \
    && ok "an unrunnable stamp says the body is UNVERIFIED" \
    || bad "an unrunnable stamp says the body is UNVERIFIED" "got: $OUT"

echo "── a visit with no stamp runs nothing and says nothing ──"
jq -nc '[{metadata: {"task_kind": "visit"}}]' > "$STUB_VISIT"
OUT="$(VISIT=tk-visit bash "$TMP/hook.sh" 2>&1)"
eq "$OUT" "" "an unstamped visit produces no hook output (the ordinary case, not an error)"

echo "── the standing-record list agrees across the sweep and the re-check ──"
# The other string that has to agree across two files, read out of each side for
# the same reason as the stamp key above (bead tk-rw2ra). These two cannot share
# code — one is a jq program inside a TOML formula description, the other this
# standalone script — and a drifted pair fails INVISIBLY in both directions: the
# sweep stops filing an idiom the re-check still calls idle, or the re-check
# holds one the sweep is still filing, and either way the disagreement shows up
# only as a bead a sitting cannot disposition.
kinds_of() { sed -n 's/.*def standing_kinds: *\(\[[^]]*\]\);.*/\1/p' "$1" | head -1 | tr -d ' '; }
F_KINDS="$(kinds_of "$SWEEP")"
[ -n "$F_KINDS" ] && ok "the sweep names a standing_kinds list" \
    || bad "the sweep names a standing_kinds list" "no def standing_kinds in $SWEEP"
eq "$(kinds_of "$SCRIPT")" "$F_KINDS" \
   "the standing records the sweep excludes are the ones the re-check holds"

echo
echo "liveness-recheck: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
