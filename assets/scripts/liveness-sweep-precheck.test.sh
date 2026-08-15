#!/usr/bin/env bash
# liveness-sweep-precheck.test.sh — the sweep's mechanical half decides without
# an agent session, and can only ever decide "nothing" from good reads
# (bead tk-7h51d).
#
# The script under test is the `check` of a condition-triggered order, so its
# whole contract is its EXIT CODE: 0 runs the agent pass, non-zero does not.
# That inverts the formula's governing bias — "a probe that cannot be read
# excludes nothing" — into a shape where a bad jq, a degraded store or a torn
# read could file nothing and look perfectly healthy. Most of this file exists
# to pin that inversion shut.
#
# What is pinned here:
#
#   1. THE EMPTY PATH SHORT-CIRCUITS. A board whose every ready bead is locally
#      excluded, or whose survivors are all already in the baseline, returns
#      "do not run". That is the whole point: ~16 agent sessions/day across four
#      rigs were being spent to conclude "nothing new".
#
#   2. THE NON-EMPTY PATH RUNS. One new candidate — or a live visit, or a
#      missing subject, or an unreadable probe — returns "run", and the
#      framework then dispatches the same wisp on the same pool as before.
#
#   3. "EMPTY" IS REACHABLE ONLY FROM VERIFIED READS. Every read failure,
#      non-array answer, missing subject and mid-flight abort is exercised, and
#      each must RUN — never skip.
#
#   4. THE COOLDOWN IS ENFORCED, STAMPED BEFORE THE WORK, AND PER RIG. A
#      condition trigger has no interval, so the 6h cadence lives in the script.
#      Stamping after the verdict would let a crash re-offer the pass on the
#      next tick and let a degraded store dispatch a session every tick, so the
#      ordering is itself under test. And the state directory it stamps into is
#      city+pack scoped while the order is rig-scoped, so a window without a rig
#      component would let the first rig through the check silence every other
#      rig for six hours — section 4b runs two rigs against one shared state
#      directory, which is the only way to see that.
#
#   5. THE SUBSET PROPERTY, which is the soundness argument itself. The precheck
#      is only safe because its exclusions are a strict subset of the shipped
#      classifier's, so its survivor set is a SUPERSET of the true candidate set
#      and "zero locally" implies "zero really". Checked by running BOTH — the
#      precheck's own filter and the `classify-candidates` block extracted
#      verbatim from mol-liveness-sweep.toml — over one shared fixture, with a
#      positive control so a passing run cannot mean "both sets were empty".
#
# Hermetic: reads the repo, stubs `gc`; no city, no Dolt, no network, no agent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/assets/scripts/liveness-sweep-precheck.sh"
FORMULA="$ROOT/formulas/mol-liveness-sweep.toml"
ORDER="$ROOT/orders/liveness-sweep.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

[ -s "$SCRIPT" ] || { echo "missing $SCRIPT"; exit 1; }
[ -x "$SCRIPT" ] || { echo "$SCRIPT is not executable"; exit 1; }
[ -s "$FORMULA" ] || { echo "missing $FORMULA"; exit 1; }

echo "── the script is valid shell ──"
bash -n "$SCRIPT" && ok "liveness-sweep-precheck.sh: valid bash" \
    || bad "liveness-sweep-precheck.sh: valid bash" "bash -n failed"

# --- the stub ----------------------------------------------------------------
# One `gc` answering the three bead reads from $FIXDIR and recording which store
# each was pinned to. `gc bd` resolves its ledger from the invoking rig and
# ignores BEADS_DIR, so an unpinned read on the controller answers about the
# wrong store — the pin is worth a test of its own.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 0
sub="$2"; shift 2
status=""; db=""
while [ $# -gt 0 ]; do
    case "$1" in
        --status=*) status="${1#--status=}" ;;
        --db) db="$2"; shift ;;
        --db=*) db="${1#--db=}" ;;
    esac
    shift
done
printf '%s %s\n' "$sub" "$db" >> "$FIXDIR/reads"
case "$sub" in
    ready) name=ready ;;
    list) case "$status" in *blocked*) name=widen ;; *) name=live ;; esac ;;
    *) exit 0 ;;
esac
# FAIL_<name> is a call that fails the way a real outage does: non-zero, no
# output. GARBAGE_<name> is the subtler one — a call that SUCCEEDS and answers
# with something that is not a JSON array. NONZERO_<name> is the subtlest of the
# three and the only one a shape-only check cannot see: the call FAILS and still
# leaves a perfectly well-formed array on stdout — a timeout killed after the
# first flush, a store that errors partway through a listing, a `gc` that
# reports a stale schema on stderr and exits non-zero. Its stdout is
# indistinguishable from a genuinely empty board, so nothing but the exit status
# can tell the two apart.
eval "fail=\${FAIL_${name}:-}"
eval "garbage=\${GARBAGE_${name}:-}"
eval "nonzero=\${NONZERO_${name}:-}"
[ -n "$fail" ] && exit 1
[ -n "$garbage" ] && { printf '%s\n' '{"error":"store is migrating"}'; exit 0; }
[ -n "$nonzero" ] && { printf '%s\n' '[]'; exit 1; }
cat "$FIXDIR/$name.json"
GC
chmod +x "$TMP/bin/gc"

# --- fixtures ----------------------------------------------------------------
# Shapes chosen to cover every local exclusion AND the tri-states that a strict
# ==/!= against a missing key gets wrong. `f-plain` carries no metadata object
# at all, which is what most rows on a real store look like.
FIX="$TMP/fix"; mkdir -p "$FIX"

cat > "$FIX/ready.json" <<'JSON'
[
  {"id":"f-plain","title":"an ordinary idle bug","issue_type":"bug"},
  {"id":"f-routed","title":"already dispatched","issue_type":"task","metadata":{"gc.routed_to":"rig/rig.polecat"}},
  {"id":"f-visit","title":"visit: something","issue_type":"task","metadata":{"task_kind":"visit"}},
  {"id":"f-subject","title":"triage: unnamed waits (this rig)","issue_type":"task","metadata":{"task_kind":"triage-subject","triage.scope":"unnamed-waits","sweep.reported":"f-carried"}},
  {"id":"f-ingroup","title":"subject of a live visit","issue_type":"task","metadata":{}},
  {"id":"f-takeaway","title":"parked by a human","issue_type":"epic","metadata":{"gc.takeaway":"needs operator ratify"}},
  {"id":"f-takeaway-empty","title":"takeaway was cleared — NOT a hold","issue_type":"task","metadata":{"gc.takeaway":""}},
  {"id":"f-hold","title":"operator decided this waits","issue_type":"task","metadata":{"triage.hold":"deferred; may take another direction"}},
  {"id":"f-hold-empty","title":"hold was cleared — NOT a hold","issue_type":"task","metadata":{"triage.hold":""}},
  {"id":"f-carried","title":"already reported by an earlier pass","issue_type":"bug","metadata":{}},
  {"id":"f-epic-open","title":"an epic with a child still alive","issue_type":"epic","metadata":{}},
  {"id":"f-epic-done","title":"an epic whose children have all closed","issue_type":"epic","metadata":{}},
  {"id":"f-convoy","title":"a convoy waiting on what it carries","issue_type":"convoy","metadata":{},"dependencies":[{"issue_id":"f-convoy","depends_on_id":"f-member","type":"tracks"}]},
  {"id":"f-spec","title":"a spec bead hanging off a root still alive","issue_type":"task","metadata":{},"dependencies":[{"issue_id":"f-spec","depends_on_id":"f-root-live","type":"tracks"}]},
  {"id":"f-tracks-dead","title":"tracks something already CLOSED — a wait no more","issue_type":"task","metadata":{},"dependencies":[{"issue_id":"f-tracks-dead","depends_on_id":"f-root-closed","type":"tracks"}]},
  {"id":"f-child","title":"a child whose parent is open — workable, not a wait","issue_type":"bug","metadata":{},"dependencies":[{"issue_id":"f-child","depends_on_id":"f-epic-open","type":"parent-child"}]},
  {"id":"f-pr-open","title":"done, parked on an open PR awaiting approval","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"521","pr_url":"https://github.com/zookanalytics/signal-loom/pull/521"}},
  {"id":"f-preopen-green","title":"pre-open, codex green — waits on pre-open-resolve","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex","check.codex":"green@756d5d7"}},
  {"id":"f-worked","title":"a work bead a live molecule is driving","issue_type":"bug","metadata":{}}
]
JSON

# LIVE is open+in_progress: the subject, a live visit naming f-ingroup, the
# alive edge targets, and the molecule/convoy pair behind f-worked.
cat > "$FIX/live.json" <<'JSON'
[
  {"id":"f-subject","title":"triage: unnamed waits (this rig)","metadata":{"task_kind":"triage-subject","triage.scope":"unnamed-waits","sweep.reported":"f-carried"}},
  {"id":"v-1","title":"visit: f-ingroup — a live sitting","metadata":{"task_kind":"visit","gc.continuation_group":"f-ingroup"}},
  {"id":"f-member","title":"the bead the convoy carries","metadata":{}},
  {"id":"f-root-live","title":"a routed root the spec bead hangs off","metadata":{}},
  {"id":"f-child","title":"a child whose parent is open","metadata":{},"dependencies":[{"issue_id":"f-child","depends_on_id":"f-epic-open","type":"parent-child"}]},
  {"id":"m-live","title":"a live molecule driving a work bead","metadata":{"gc.input_convoy_id":"conv-live"}},
  {"id":"f-worked","title":"a work bead a live molecule is driving","metadata":{}}
]
JSON

# WIDEN is every OTHER non-closed status. f-blocked-child is the live case
# tk-dhue in miniature: a blocked child still names its parent's wait, and it is
# absent from LIVE, so an edge check resolved against LIVE alone would misfile
# the parent as unnamed.
cat > "$FIX/widen.json" <<'JSON'
[
  {"id":"f-blocked-child","title":"a BLOCKED child of f-epic-open","status":"blocked","metadata":{},"dependencies":[{"issue_id":"f-blocked-child","depends_on_id":"f-epic-open","type":"parent-child"}]}
]
JSON

export FIXDIR="$FIX"
export PATH="$TMP/bin:$PATH"
export GC_RIG=testrig
export GC_RIG_ROOT="$TMP/rigroot"
export LIVENESS_SWEEP_STATE_DIR="$TMP/state"
# LIVENESS_SWEEP_STATE_DIR is the BASE; the script keys a rig component onto it
# so two rigs sharing one state directory cannot share a cooldown window. With
# GC_RIG=testrig that component is `testrig` — an ordinary rig name survives
# sanitizing untouched, which section 4 pins directly.
STATE="$LIVENESS_SWEEP_STATE_DIR/testrig"

# Every case below wants a fresh classification, so the cooldown stamp is
# cleared first; the cooldown itself is exercised in its own section.
# Sets $OUT and $RC in the CALLER, never through a command substitution: a
# `$(...)` runs in a subshell, so the exit code — which is this script's entire
# contract — would not survive the capture.
OUT=""; RC=0
run_precheck() { # run_precheck [args...] -> sets OUT and RC
    rm -rf "$LIVENESS_SWEEP_STATE_DIR"
    : > "$FIXDIR/reads"
    OUT="$("$SCRIPT" "$@" 2>&1)"; RC=$?
}
survivors_of() { printf '%s\n' "$1" | sed -n 's/^  new: //p' | tr -d ' '; }

# --- 1. the non-empty path: the pass runs ------------------------------------
echo "── a board with new candidates runs the agent pass ──"
run_precheck
eq "$RC" "0" "exit 0 — the condition is due, the framework dispatches the wisp"
has "$OUT" "RUN:" "the verdict is RUN"
# The store pin travels with every read, or the controller reads the wrong rig.
eq "$(sort -u "$FIX/reads" | tr '\n' '|')" "list $TMP/rigroot/.beads|ready $TMP/rigroot/.beads|" \
   "every bead read is pinned to the rig store"

echo "── the local classification: which beads survive to the delta ──"
run_precheck --dry-run
SURV="$(survivors_of "$OUT")"
has ",$SURV," ",f-plain," "an ordinary idle bead survives — the defect the sweep exists for"
has ",$SURV," ",f-takeaway-empty," "an EMPTY gc.takeaway is a cleared hold, not a hold"
has ",$SURV," ",f-hold-empty," "an EMPTY triage.hold is a cleared hold, not a hold"
has ",$SURV," ",f-epic-done," "an epic whose children ALL closed survives (the what-comes-next candidate)"
has ",$SURV," ",f-tracks-dead," "tracking a CLOSED bead names no wait — it survives"
has ",$SURV," ",f-child," "a child with an open parent is workable, not a wait"
hasnt ",$SURV," ",f-routed," "gc.routed_to non-empty is excluded (class 1)"
hasnt ",$SURV," ",f-visit," "task_kind=visit is excluded (class 3)"
hasnt ",$SURV," ",f-subject," "task_kind=triage-subject is excluded (class 4a)"
hasnt ",$SURV," ",f-ingroup," "a subject with a live visit is excluded (class 3)"
hasnt ",$SURV," ",f-takeaway," "gc.takeaway non-empty is excluded (class 4c)"
hasnt ",$SURV," ",f-hold," "triage.hold non-empty is excluded (class 4d)"
hasnt ",$SURV," ",f-carried," "a bead already in the baseline is CARRIED, not new"
hasnt ",$SURV," ",f-epic-open," "a parent with a non-closed child is excluded (class 2i-a)"
hasnt ",$SURV," ",f-convoy," "a convoy tracking a live member is excluded (class 2i-b)"
hasnt ",$SURV," ",f-spec," "a bead tracking a live root is excluded (class 2i-c)"
# The exclusions the precheck deliberately does NOT make. Each of these IS
# dropped by the full classifier; the precheck reports them and runs the pass,
# because the reads that decide them are non-local or non-monotone.
has ",$SURV," ",f-pr-open," "a PR-parked bead is NOT excluded locally — the PR read is non-monotone"
has ",$SURV," ",f-preopen-green," "a pre-open-gated bead is NOT excluded locally"
has ",$SURV," ",f-worked," "a convoy-worked bead is NOT excluded locally — that read is not local"

# 2i-a resolves against the NOT-CLOSED set, not the open one. Re-run with the
# only live child BLOCKED (it lives in WIDEN, absent from LIVE): the parent must
# still be excluded, or the live case tk-dhue returns.
echo "── 'still alive' means NOT CLOSED, never 'present in the open listing' ──"
cp "$FIX/live.json" "$TMP/live.bak"
cp "$FIX/ready.json" "$TMP/ready.bak"
jq 'map(select(.id != "f-child"))' "$TMP/live.bak" > "$FIX/live.json"
run_precheck --dry-run
SURV2="$(survivors_of "$OUT")"
hasnt ",$SURV2," ",f-epic-open," "a parent whose only live child is BLOCKED is still gated (tk-dhue)"
cp "$TMP/live.bak" "$FIX/live.json"

# --- 2. the empty path: no agent session at all ------------------------------
echo "── an empty board ends the pass with no agent session ──"
# Keep only the beads a local rule excludes. Nothing survives, so nothing is new.
jq 'map(select([.id] | inside(["f-routed","f-visit","f-subject","f-ingroup","f-takeaway","f-hold","f-epic-open","f-convoy","f-spec"])))' \
   "$TMP/ready.bak" > "$FIX/ready.json"
run_precheck
eq "$RC" "1" "exit 1 — no agent session is dispatched at all"
has "$OUT" "SKIP:" "the verdict is SKIP"
has "$OUT" "no agent session this pass" "it says so in as many words"

echo "── a stable population is not news: survivors already in the baseline ──"
# Every survivor is in sweep.reported, so the delta is empty even though the
# census is not. This is the common case on a busy rig.
jq 'map(select(.id == "f-carried" or .id == "f-plain"))' "$TMP/ready.bak" > "$FIX/ready.json"
jq '(.[] | select(.id == "f-subject") | .metadata["sweep.reported"]) |= "f-carried,f-plain"' \
   "$TMP/live.bak" > "$FIX/live.json"
run_precheck
eq "$RC" "1" "carried-only survivors are not new — no agent session"
has "$OUT" "local survivors 2 -> new 0" "the funnel shows the census, not just the delta"

echo "── a live visit on the SWEEP subject runs the pass even with nothing new ──"
jq '. + [{"id":"v-2","title":"visit: the sweep subject","metadata":{"task_kind":"visit","gc.continuation_group":"f-subject"}}]' \
   "$FIX/live.json" > "$TMP/live.visit" && cp "$TMP/live.visit" "$FIX/live.json"
run_precheck
eq "$RC" "0" "a live visit on the subject runs the pass"
has "$OUT" "a visit is already live" "and says which condition fired"
# A live visit on some OTHER subject must not block the skip — the condition is
# about this sweep's subject, not about visits in general.
jq '(.[] | select(.id == "f-subject") | .metadata["sweep.reported"]) |= "f-carried,f-plain"' \
   "$TMP/live.bak" > "$FIX/live.json"
run_precheck
eq "$RC" "1" "a visit live on a DIFFERENT subject does not block the skip"

# --- 3. "empty" only from verified reads -------------------------------------
# The inverted failure mode. Each of these must RUN: a probe that cannot be read
# excludes nothing, and a short-circuit that reads it as "nothing to do" would
# file nothing and look perfectly healthy.
echo "── an unreadable probe NEVER produces a silent empty pass ──"
# The board is emptied first, so the ONLY thing that could make these run is the
# failed read itself. Without this the test would pass on leftover candidates
# and prove nothing.
jq 'map(select([.id] | inside(["f-routed","f-visit","f-subject","f-ingroup","f-takeaway","f-hold","f-epic-open","f-convoy","f-spec"])))' \
   "$TMP/ready.bak" > "$FIX/ready.json"
cp "$TMP/live.bak" "$FIX/live.json"
run_precheck
eq "$RC" "1" "control: this board really does skip when every read is good"

# `--force --dry-run`: classify regardless of the window the control run above
# just stamped, and do not move it. Without --force these all hit the cooldown
# and exit silently, which looks exactly like the skip they are meant to rule
# out — the empty $OUT is the tell.
for probe in ready live widen; do
    OUT="$(bash -c "export FAIL_${probe}=1; exec \"\$0\" --force --dry-run" "$SCRIPT" 2>&1)"; RC=$?
    eq "$RC" "0" "a FAILED $probe read RUNS the pass — it is not an empty board"
    hasnt "$OUT" "SKIP:" "a FAILED $probe read does not skip"
    has "$OUT" "UNREADABLE" "a failed $probe read says the probe was unreadable"
    has "$OUT" "$probe" "the diagnostic names the $probe read"

    OUT="$(bash -c "export GARBAGE_${probe}=1; exec \"\$0\" --force --dry-run" "$SCRIPT" 2>&1)"; RC=$?
    eq "$RC" "0" "a NON-ARRAY $probe answer RUNS the pass"
    has "$OUT" "UNREADABLE" "a non-array $probe answer is unreadable, not empty"
done

# The gap a shape-only check leaves wide open, and the reason the read's own
# exit status is required and not merely observed: a failed call whose stdout IS
# a JSON array. `[]` from a call that exited non-zero is byte-identical to `[]`
# from a healthy empty board, so a check that consults only the shape reads a
# store outage as "nothing to report" and skips — silently, on every pass, for
# as long as the outage lasts. That is precisely the inversion this whole file
# exists to pin shut, arriving through the one door left open.
#
# The board is still the emptied one the control above proved really does SKIP,
# so a RUN here can be the non-zero status and nothing else.
for probe in ready live widen; do
    OUT="$(bash -c "export NONZERO_${probe}=1; exec \"\$0\" --force --dry-run" "$SCRIPT" 2>&1)"; RC=$?
    eq "$RC" "0" "a $probe read that exits NON-ZERO with a valid array RUNS the pass"
    hasnt "$OUT" "SKIP:" "an array-shaped answer from a FAILED $probe call does not skip"
    has "$OUT" "UNREADABLE" "a failed $probe call is unreadable however good its stdout looks"
    has "$OUT" "$probe" "the diagnostic names the $probe read"
done

echo "── the standing subject must resolve, or there is no baseline to trust ──"
jq 'map(select(.id != "f-subject"))' "$TMP/live.bak" > "$FIX/live.json"
run_precheck
eq "$RC" "0" "no triage subject → run the pass (the agent creates it)"
has "$OUT" "no standing unnamed-waits triage subject" "and says why"
jq '. + [{"id":"f-subject-2","title":"a second subject","metadata":{"task_kind":"triage-subject","triage.scope":"unnamed-waits","sweep.reported":""}}]' \
   "$TMP/live.bak" > "$FIX/live.json"
run_precheck
eq "$RC" "0" "two subjects → run the pass rather than guess a baseline"
has "$OUT" "cannot tell which baseline" "and says why"
cp "$TMP/live.bak" "$FIX/live.json"
cp "$TMP/ready.bak" "$FIX/ready.json"

echo "── an abort BEFORE the decision runs the pass ──"
# The case no fixture can reach from outside: a mid-flight abort — an errexit
# crash, a signal, a bad edit. Injected into a COPY so the production script
# keeps no test-only backdoor, and placed after the trap is armed, which is the
# code actually under test.
sed 's|^trap on_exit EXIT$|trap on_exit EXIT\nexit 3|' "$SCRIPT" > "$TMP/aborting.sh"
chmod +x "$TMP/aborting.sh"
grep -qx 'exit 3' "$TMP/aborting.sh" && ok "abort injection landed" \
    || bad "abort injection landed" "the trap line moved — this test is checking nothing"
rm -rf "$LIVENESS_SWEEP_STATE_DIR"
OUT="$("$TMP/aborting.sh" 2>&1)"; RC=$?
eq "$RC" "0" "an abort before deciding RUNS the pass"
has "$OUT" "ABORTED before deciding" "it says it aborted"
has "$OUT" "NOT an empty board" "and refuses to be read as an empty board"

# --- 4. the cooldown ---------------------------------------------------------
# A condition trigger has no interval and its check runs on every dispatch tick,
# so the 6h cadence is this script's own.
echo "── the cadence is enforced here, and stamped BEFORE the work ──"
rm -rf "$LIVENESS_SWEEP_STATE_DIR"
"$SCRIPT" >/dev/null 2>&1; RC=$?
eq "$RC" "0" "first run in a fresh window classifies and runs"
[ -f "$STATE/last-pass" ] && ok "it stamped the window" \
    || bad "it stamped the window" "no $STATE/last-pass"
OUT="$("$SCRIPT" 2>&1)"; RC=$?
eq "$RC" "1" "a second tick inside the window does NOT run the pass"
eq "$OUT" "" "and says nothing — this is the answer on almost every tick"
OUT="$("$SCRIPT" --force 2>&1)"; RC=$?
eq "$RC" "0" "--force classifies anyway"
# Backdate the stamp past the window: the next tick classifies again.
printf '%s\n' "$(( $(date -u +%s) - 21601 ))" > "$STATE/last-pass"
"$SCRIPT" >/dev/null 2>&1; RC=$?
eq "$RC" "0" "once the window has elapsed the pass runs again"
# A shorter window is honoured, so the interval is really read from one place.
printf '%s\n' "$(( $(date -u +%s) - 100 ))" > "$STATE/last-pass"
LIVENESS_SWEEP_INTERVAL=60 "$SCRIPT" >/dev/null 2>&1; RC=$?
eq "$RC" "0" "LIVENESS_SWEEP_INTERVAL is the single source of the cadence"
# STAMP-BEFORE-WORK: a run whose reads all fail must still have stamped, or a
# degraded store dispatches an agent session on every dispatch tick.
rm -rf "$LIVENESS_SWEEP_STATE_DIR"
FAIL_ready=1 "$SCRIPT" >/dev/null 2>&1; RC=$?
eq "$RC" "0" "a degraded store runs the pass"
[ -f "$STATE/last-pass" ] && ok "and STILL stamped — a degraded store cannot storm" \
    || bad "and STILL stamped — a degraded store cannot storm" "no stamp; every tick would dispatch"
# --dry-run must never move the window.
rm -rf "$LIVENESS_SWEEP_STATE_DIR"
"$SCRIPT" --dry-run >/dev/null 2>&1
[ -f "$STATE/last-pass" ] \
    && bad "--dry-run does not stamp" "it wrote the window stamp" \
    || ok "--dry-run does not stamp"
# An unwritable state dir is the one condition that refuses to run: with no
# cadence the check would dispatch a session every tick.
rm -rf "$LIVENESS_SWEEP_STATE_DIR"
mkdir -p "$TMP/nowrite"; : > "$TMP/nowrite/blocker"; chmod 500 "$TMP/nowrite"
OUT="$(LIVENESS_SWEEP_STATE_DIR="$TMP/nowrite/state" "$SCRIPT" 2>&1)"; RC=$?
chmod 700 "$TMP/nowrite"
eq "$RC" "1" "an unwritable state dir refuses to run rather than storm"
has "$OUT" "CANNOT WRITE the cooldown stamp" "and says exactly what is broken"
has "$OUT" "the sweep is OFF" "and that the sweep is off until it is fixed"

echo "── the report survives the controller discarding stdout ──"
rm -rf "$LIVENESS_SWEEP_STATE_DIR"
"$SCRIPT" >/dev/null 2>&1
[ -s "$STATE/pass.log" ] && ok "the verdict is appended to pass.log" \
    || bad "the verdict is appended to pass.log" "no log — a condition check's stdout is discarded"
grep -q "RUN:" "$STATE/pass.log" && ok "the log carries the verdict" \
    || bad "the log carries the verdict" "no verdict line in pass.log"
LIVENESS_SWEEP_LOG_KEEP=3 "$SCRIPT" --force >/dev/null 2>&1
LIVENESS_SWEEP_LOG_KEEP=3 "$SCRIPT" --force >/dev/null 2>&1
eq "$(awk 'END { print NR }' "$STATE/pass.log")" "3" \
   "the log is bounded — a quiet rig cannot grow it without limit"

# --- 4b. the window is PER RIG -----------------------------------------------
# The production path, not the LIVENESS_SWEEP_STATE_DIR one: the order runner
# gives every rig-scoped check the SAME GC_PACK_STATE_DIR (city+pack —
# `<city>/.gc/runtime/packs/<pack>`, citylayout.PackStateDir) and a per-rig
# GC_RIG/GC_RIG_ROOT. A stamp without a rig component is therefore shared by
# every importing rig, and the first one through the check silences all the
# others for the whole 6h window — an empty-looking sweep on a rig that was
# never read. This section runs two rigs against one shared state directory.
echo "── two rigs sharing one GC_PACK_STATE_DIR keep separate windows ──"
SHARED="$TMP/packstate"
rm -rf "$SHARED"
# Rig A: a normal first pass. Classifies, runs, and stamps its own window.
: > "$FIXDIR/reads"
OUT_A="$(unset LIVENESS_SWEEP_STATE_DIR; GC_PACK_STATE_DIR="$SHARED" GC_RIG=rigA "$SCRIPT" 2>&1)"; RC_A=$?
eq "$RC_A" "0" "rig A runs its pass"
has "$OUT_A" "RUN:" "and reached a real verdict"
[ -f "$SHARED/liveness-sweep/rigA/last-pass" ] && ok "rig A stamped its OWN window" \
    || bad "rig A stamped its OWN window" "no $SHARED/liveness-sweep/rigA/last-pass"
# Rig A again, inside the window: still silent, so the cadence was not simply
# disabled to separate the rigs.
OUT_A2="$(unset LIVENESS_SWEEP_STATE_DIR; GC_PACK_STATE_DIR="$SHARED" GC_RIG=rigA "$SCRIPT" 2>&1)"; RC_A2=$?
eq "$RC_A2" "1" "rig A's own second tick is still held by the cooldown"
eq "$OUT_A2" "" "and still says nothing"
# Rig B, same state directory, immediately after: this is the regression. It
# must classify its own store rather than inherit rig A's window.
: > "$FIXDIR/reads"
OUT_B="$(unset LIVENESS_SWEEP_STATE_DIR; GC_PACK_STATE_DIR="$SHARED" GC_RIG=rigB "$SCRIPT" 2>&1)"; RC_B=$?
eq "$RC_B" "0" "rig B still runs after rig A stamped — the window is not shared"
has "$OUT_B" "RUN:" "and rig B reached a real verdict"
[ -s "$FIXDIR/reads" ] && ok "rig B actually read its store" \
    || bad "rig B actually read its store" "no reads — it exited from the cooldown branch"
[ -f "$SHARED/liveness-sweep/rigB/last-pass" ] && ok "rig B stamped a window of its own" \
    || bad "rig B stamped a window of its own" "no $SHARED/liveness-sweep/rigB/last-pass"
# Two rigs, two logs: a quiet rig's history stays its own.
[ -s "$SHARED/liveness-sweep/rigA/pass.log" ] && [ -s "$SHARED/liveness-sweep/rigB/pass.log" ] \
    && ok "each rig keeps its own pass.log" \
    || bad "each rig keeps its own pass.log" "the logs are shared or missing"

# The key is derived, so it must not be escapable or collidable. Two rig names
# that differ only in a character the sanitizer rewrites must NOT land on one
# directory — that would rebuild the shared window through the back door.
echo "── the rig key is sanitized, and sanitizing cannot collide ──"
KEYS="$TMP/keys"
rm -rf "$KEYS"
(unset LIVENESS_SWEEP_STATE_DIR; GC_PACK_STATE_DIR="$KEYS" GC_RIG='a/b' "$SCRIPT" >/dev/null 2>&1)
(unset LIVENESS_SWEEP_STATE_DIR; GC_PACK_STATE_DIR="$KEYS" GC_RIG='a_b' "$SCRIPT" >/dev/null 2>&1)
eq "$(find "$KEYS/liveness-sweep" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" "2" \
   "'a/b' and 'a_b' get two windows, not one"
[ -e "$KEYS/liveness-sweep/a/b" ] \
    && bad "a rig name cannot escape into a subdirectory" "'a/b' wrote a nested path" \
    || ok "a rig name cannot escape into a subdirectory"
# No rig identity at all is a hand run, and it gets its own bucket rather than
# stamping over whichever rig happened to be first.
rm -rf "$KEYS"
(unset LIVENESS_SWEEP_STATE_DIR; GC_PACK_STATE_DIR="$KEYS" GC_RIG='' GC_RIG_ROOT='' "$SCRIPT" >/dev/null 2>&1)
[ -f "$KEYS/liveness-sweep/_unscoped/last-pass" ] && ok "an unscoped hand run stamps its own bucket" \
    || bad "an unscoped hand run stamps its own bucket" "no _unscoped window"
# A rig root with no rig name still keys per root, and two roots sharing a last
# component stay distinct — the basename reads well, the full path is the identity.
rm -rf "$KEYS"
(unset LIVENESS_SWEEP_STATE_DIR; GC_PACK_STATE_DIR="$KEYS" GC_RIG='' GC_RIG_ROOT="$TMP/one/dup" "$SCRIPT" >/dev/null 2>&1)
(unset LIVENESS_SWEEP_STATE_DIR; GC_PACK_STATE_DIR="$KEYS" GC_RIG='' GC_RIG_ROOT="$TMP/two/dup" "$SCRIPT" >/dev/null 2>&1)
eq "$(find "$KEYS/liveness-sweep" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" "2" \
   "two rig roots ending in the same name keep separate windows"

# --- 5. the order wiring -----------------------------------------------------
echo "── the order is wired to this script, with one source for the cadence ──"
if [ -s "$ORDER" ]; then
    ORDER_TXT="$(cat "$ORDER")"
    has "$ORDER_TXT" 'trigger = "condition"' "the order is condition-triggered"
    has "$ORDER_TXT" "liveness-sweep-precheck.sh" "its check is this script"
    has "$ORDER_TXT" 'formula = "mol-liveness-sweep"' "the formula is unchanged"
    hasnt "$ORDER_TXT" "interval =" "no inert interval key — a condition trigger ignores it"
    # check_timeout must exceed this script's own worst case, or a wedged store
    # is killed mid-read and reads as not-due: a silent skip, the one outcome
    # this whole design exists to prevent.
    CT="$(printf '%s\n' "$ORDER_TXT" | sed -n 's/^check_timeout *= *"\([0-9]*\)s".*/\1/p')"
    [ -n "$CT" ] && [ "$CT" -gt $((45 * 3)) ] \
        && ok "check_timeout ${CT}s exceeds the script's worst case (3 reads x 45s)" \
        || bad "check_timeout exceeds the script's worst case" "got '${CT:-unset}'s, need > 135s"
else
    bad "orders/liveness-sweep.toml exists" "missing"
fi

# --- 6. the subset property: the soundness argument, mechanically ------------
# The precheck is safe ONLY because its exclusions are a strict subset of the
# shipped classifier's. Run both over one fixture and assert containment. The
# classifier half is EXTRACTED VERBATIM from the formula, so this cannot drift
# from the instruction an agent actually runs.
echo "── the precheck's survivors are a SUPERSET of the classifier's candidates ──"
extract() { awk -v m="$1" '$0 ~ ("# >>> " m) {inb=1; next} $0 ~ ("# <<< " m) {inb=0} inb' "$2"; }
extract classify-candidates "$FORMULA" > "$TMP/classify.sh"
[ -s "$TMP/classify.sh" ] && ok "the formula still has a marked classify-candidates block" \
    || bad "the formula still has a marked classify-candidates block" "extract found nothing"

# The comparison runs on a fixture with NO dependency edges ANYWHERE — not just
# none on the candidates. That matters, and getting it wrong is what this
# comment exists to prevent: class 2(i)(a) is a REVERSE index, so an edge held
# by some other bead in the not-closed set still drops a candidate that has no
# edges of its own. Stripping only the candidates' own `dependencies` left
# f-epic-open dropped by the precheck and kept by the classifier, which reads
# like a containment violation and is not one — `classify-candidates` is the
# PRE-edge-check set, and the edge check belongs to both paths.
#
# With every edge gone the precheck's class-2(i) check is provably a no-op, so
# the two filters are compared on exactly the ground the subset claim is about:
# the metadata exclusions. Edge behaviour is pinned separately, above, and the
# baseline is emptied so the precheck reports its whole census rather than a
# delta.
CFIX="$TMP/cfix"; mkdir -p "$CFIX"; : > "$CFIX/reads"
jq 'map(del(.dependencies))' "$TMP/ready.bak" > "$CFIX/ready.json"
jq 'map(del(.dependencies))
    | map(if .id == "f-subject" then .metadata["sweep.reported"] = "" else . end)' \
   "$TMP/live.bak" > "$CFIX/live.json"
jq 'map(del(.dependencies))' "$FIX/widen.json" > "$CFIX/widen.json"
EDGES_LEFT="$(jq -s '[.[][] | .dependencies // [] | length] | add // 0' \
    "$CFIX/ready.json" "$CFIX/live.json" "$CFIX/widen.json")"
eq "$EDGES_LEFT" "0" "precondition: the containment fixture has no edges, so the edge check is a no-op"

FIXDIR="$CFIX"; export FIXDIR
LIVE="$CFIX/live.json" READY="$CFIX/ready.json"
export LIVE READY
# The classifier's two batched inputs. OPEN_PRS answers for the one PR-parked
# bead in the fixture; WORKED for the one convoy-driven bead. Supplying them is
# what makes this a real subset test: they are precisely the exclusions the
# precheck does NOT make, so they are the ones that must shrink the classifier's
# set below the precheck's.
# These are JSON payloads the extracted block reads through `--argjson`, never
# command strings to be word-split — hence the disables.
# shellcheck disable=SC2089
OPEN_PRS='["https://github.com/zookanalytics/signal-loom/pull/521"]'
# shellcheck disable=SC2089
WORKED='["f-worked"]'
# shellcheck disable=SC2090
export OPEN_PRS WORKED
# shellcheck disable=SC1090
. "$TMP/classify.sh"
CLASSIFY_IDS="$(printf '%s' "$CANDIDATES" | jq -r '[.[].id] | sort | join(",")')"
run_precheck --dry-run
PRE_IDS="$(survivors_of "$OUT")"

# Positive control FIRST: a containment assertion over two empty sets passes
# while proving nothing at all.
CLASSIFY_N="$(printf '%s' "$CANDIDATES" | jq 'length')"
PRE_N="$(printf '%s' "$PRE_IDS" | tr ',' '\n' | awk 'NF { n++ } END { print n + 0 }')"
[ "$CLASSIFY_N" -gt 0 ] && ok "positive control: the classifier's candidate set is non-empty ($CLASSIFY_N)" \
    || bad "positive control: the classifier's candidate set is non-empty" "it returned nothing — the containment below is vacuous"
[ "$PRE_N" -gt 0 ] && ok "positive control: the precheck's survivor set is non-empty ($PRE_N)" \
    || bad "positive control: the precheck's survivor set is non-empty" "it returned nothing — the containment below is vacuous"

MISSING=""
for id in $(printf '%s' "$CLASSIFY_IDS" | tr ',' ' '); do
    case ",$PRE_IDS," in *",$id,"*) ;; *) MISSING="$MISSING $id" ;; esac
done
eq "$MISSING" "" "every classifier candidate also survives the precheck (containment holds)"

# And the containment must be PROPER here, or the precheck is not actually the
# smaller filter it claims to be and the whole design is misdescribed.
[ "$PRE_N" -gt "$CLASSIFY_N" ] \
    && ok "the precheck is the LOOSER filter ($PRE_N survivors vs $CLASSIFY_N candidates)" \
    || bad "the precheck is the LOOSER filter" "precheck $PRE_N, classifier $CLASSIFY_N — the non-local exclusions are not showing up"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
