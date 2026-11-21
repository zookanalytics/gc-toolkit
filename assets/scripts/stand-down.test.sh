#!/usr/bin/env bash
# Hermetic test for assets/scripts/stand-down.sh, a person's ruling that work a
# human gate holds will not go on.
#
# The constraint: bd refuses to close a bead an open gate blocks, and answering
# the gate first makes the bead ready, which is what an arm waits for. So the
# suite gives the fake store what makes those two true, a `blocks` edge that holds
# a close and keeps a bead out of the ready listing, and runs the real
# stand-down.sh, bead-rehome.sh and finalize-gate.sh over it, with the arm's
# verbs and the takeaway those scripts call run by gctk built from this
# checkout.
#
# What is exercised here:
#   * the orders a person would try by hand, as controls: a close first is refused,
#     and an answer first, or an edge removed with the arm standing, lets the next
#     pass sling the work;
#   * the stand-down: the arm goes, then the gate is answered with the ruling, then
#     the bead closes pointed at that gate, and the next pass slings nothing;
#   * no moment to sling: a pass run after every write the stand-down makes, and a
#     pass already running when the stand-down lands between its reads, sling
#     nothing;
#   * the run beneath the bead ends before any gate is answered, and a run that
#     does not end stops the stand-down;
#   * a stop at each write leaves the bead unsent and names it, and a re-run
#     converges on the same close and the first answer;
#   * a gate under the key that a person is assigned is taken back from them before
#     the check, in a write held to the assignee read, and the stand-down goes on;
#     the take-back stands when something else then holds the close, a take-back
#     the store refuses writes nothing, and a dry run names the gate and stops;
#   * each refusal writes nothing: an open PR, no gate under the key, another open
#     gate, a gate a person is assigned that this bead leaves or that is in
#     progress, another live blocker, an open child, a gate that also holds another
#     open bead with nothing else as the evidence, a claim, an unreadable bead, a
#     disposition already naming other evidence, a review bead;
#   * a bead at each of the pending record's exceptions stands down only once
#     its record names its PR and GitHub reads each PR the record names closed or
#     merged, and the script's copy of those values is held to
#     services/gctk/pr/record;
#   * a gate that also holds another open bead, with the evidence named: the arm and
#     the route go before the edge, passes after every write and mid-pass sling
#     nothing, a stop at the edge converges on a re-run, and the gate stays open and
#     asking about the other bead;
#   * an epic that carries a hypothesis, whatever its ruling reads: the close's
#     disposition is its terminal reason, so the check ahead of the first write lets
#     it through, what the check refuses is what the close holds on, and every other
#     refusal stands;
#   * --successor names other evidence, the ruling is one line headed `ruled:`, a
#     dry run writes nothing, and a closed bead is nothing to do;
#   * the clause a decline message carries is a command that runs.
#
# No live city, Dolt, network, gc, gh or bd: a tmpdir, the shared harness's
# compiled fake gc over its store, stand-ins for gh, a run's cancel and a
# branch's end, and the scripts themselves. specs/tk-utv2kaq/real-store-proof.sh
# runs the same shapes on the real bd by hand, because the test floor refuses it
# here.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/stand-down.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-stand-down-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The shared harness: the compiled fake gc over one store, which logs every call
# to $STUB_GC_LOG, and gctk built from this checkout, which runs the
# stand-down's disarm and the deferred-dispatch order's pass, gctk bead
# start-armed, over that store.
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
harness_init

[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }

# The fake refuses to close a bead a live blocker holds, as bd does. A pass reads
# the pool's default formula from the config, for an arm that names none, and the
# session list names no session.
export STUB_ENFORCE_BLOCKS=1 STUB_CONFIG="$TMP/config.json" STUB_SESSIONS="$TMP/sessions.json" STUB_RIGS="$TMP/rigs.json"
printf '%s\n' '{"ok":true,"config":{"Agents":[{"Name":"pool","Dir":"rig","DefaultSlingFormula":"mol-polecat-work"}]}}' > "$STUB_CONFIG"
printf '%s\n' '{"sessions":[]}' > "$STUB_SESSIONS"
mkdir -p "$TMP/rig/.beads"
printf '{"rigs":[{"name":"tkrig","path":"%s","prefix":"tk"}]}\n' "$TMP/rig" > "$STUB_RIGS"
export BEADS_ACTOR=a-person GC_BRANCH_END_TOOL="$BIN/branch-end"
# The takeaway's release runs run-cancel.sh from GCTK_SCRIPTS_DIR, which here
# holds the stand-in alone.
export GCTK_SCRIPTS_DIR="$TMP/scripts"
export STUB_GH_STATES="$TMP/gh-states" LANDED="$TMP/landed" LAND_LOG="$TMP/land.log" PASS_LOG="$TMP/pass.log" AT_EDGE="$TMP/at-edge"

# --- stand-ins for what is not gc -------------------------------------------------
# run-cancel and branch-end log each call among the fake's, and
# STUB_RUN_CANCEL_FAILS makes a run's cancel fail. The gh stand-in answers a PR's
# state from $STUB_GH_STATES, one "<url> <state>" line per PR, fails as gh does
# for a PR it does not list, and refuses any other call.
{ _stub_shebang; cat; } > "$BIN/run-cancel" <<'STUB'
printf 'run-cancel %s\n' "$*" >> "${STUB_GC_LOG:?}"
[ -z "${STUB_RUN_CANCEL_FAILS:-}" ] || { echo "run-cancel: simulated failure" >&2; exit 1; }
exit 0
STUB
{ _stub_shebang; cat; } > "$BIN/branch-end" <<'STUB'
printf 'branch-end %s\n' "$*" >> "${STUB_GC_LOG:?}"
exit 0
STUB
{ _stub_shebang; cat; } > "$BIN/gh" <<'STUB'
printf 'gh %s\n' "$*" >> "${STUB_GC_LOG:?}"
[ "$*" = "pr view ${3:-} --json state -q .state" ] || { echo "gh stub: unsupported '$*'" >&2; exit 2; }
st=$(awk -v u="$3" '$1 == u { print $2; exit }' "${STUB_GH_STATES:?}")
[ -n "$st" ] || { echo "GraphQL: Could not resolve to a PullRequest with the number of ${3##*/}. (repository.pullRequest)" >&2; exit 1; }
printf '%s\n' "$st"
STUB

# --- what a case runs inside the store's calls ------------------------------------
# land is the hook a case names in STUB_HOOK to land another writer's change once,
# before the first call that carries STUB_HOOK_AT (the fake's doc.go): it runs
# $LAND under bash, logging to $LAND_LOG, and leaves $LANDED, so a later call that
# carries the text lands nothing more. A change it writes goes through the fake's
# fixture writers, which log nothing. after-write runs the deferred-dispatch
# order's pass, gctk bead start-armed, logging to $PASS_LOG, and a case names it
# in STUB_AFTER_WRITE to run that pass after each write the stand-down makes.
# at-edge writes what tk-w carries when it runs, its arm and its route, to
# $AT_EDGE.
{ _stub_shebang; cat; } > "$TMP/land" <<'STUB'
[ -e "${LANDED:?}" ] && exit 0
: > "$LANDED"
bash -c "${LAND:?}" >> "${LAND_LOG:?}" 2>&1
exit 0
STUB
{ _stub_shebang; cat; } > "$TMP/after-write" <<'STUB'
"${GCTK_BIN:?}" bead start-armed >> "${PASS_LOG:?}" 2>&1
exit 0
STUB
{ _stub_shebang; cat; } > "$TMP/at-edge" <<'STUB'
a=$(gc --harness-read meta tk-w gc.dispatch_when_ready); [ "$a" != "<absent>" ] || a=""
r=$(gc --harness-read meta tk-w gc.routed_to); [ "$r" != "<absent>" ] || r=""
printf '%s|%s\n' "$a" "$r" > "${AT_EDGE:?}"
STUB
chmod +x "$BIN/run-cancel" "$BIN/branch-end" "$BIN/gh" "$TMP/land" "$TMP/after-write" "$TMP/at-edge"
mkdir -p "$GCTK_SCRIPTS_DIR" && ln -s "$BIN/run-cancel" "$GCTK_SCRIPTS_DIR/run-cancel.sh"

# --- fixtures ----------------------------------------------------------------------
# An edge is a dep row: `edge <id> <type> <on>` is <id>'s edge onto <on>.
edge() {
  if [ "$2" = blocks ]; then printf '%s|blocks|%s\n' "$3" "$1" >> "$STUB_DEPS"
  else printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$STUB_DEPS"; fi
}
# A work bead as a declined run leaves it: open, unassigned, unrouted, armed to
# re-sling, with a `blocks` edge onto an open human gate under polecat-x.
FRESH='[{"id":"tk-w","status":"open","assignee":"","issue_type":"task","notes":"","title":"the work",
  "metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]",
              "gc.dispatch_when_ready_armed_at":"2026-11-01T00:00:00Z",
              "gc.dispatch_when_ready_reason":"waits on the ruling","resling_target":"rig/pool"}},
 {"id":"tk-g","status":"open","assignee":"","issue_type":"gate","await_type":"human","await_id":"polecat-x",
  "title":"does this go on?","notes":"","metadata":{},"created_at":"2026-11-01T00:00:00Z"},
 {"id":"tk-conv","status":"open","assignee":"human","issue_type":"task","title":"a conversation","notes":"","metadata":{}}]'
fresh() {
  store "$FRESH"
  : > "$STUB_DEPS"; echo '[]' > "$STUB_COMMENTS"
  edge tk-w blocks tk-g
  rm -f "$LANDED"; : > "$LAND_LOG"; : > "$PASS_LOG"
  : > "$STUB_GC_LOG"; : > "$STUB_GH_STATES"
}
# bead <id> <title> [<setting>...]: an open, unassigned task.
bead() { local id="$1" title="$2"; shift 2; brow "$id" status=open assignee= issue_type=task "title=$title" 'metadata:={}' "$@"; }
# gate <id> <key> <title>: an open human gate under the key, filed after tk-g.
gate() { brow "$1" status=open assignee= issue_type=gate await_type=human "await_id=$2" "title=$3" 'metadata:={}' created_at=2026-11-01T00:00:01Z; }
# The same work bead, on a gate that also holds another open bead.
shared() { fresh; bead tk-o "another bead"; edge tk-o blocks tk-g; }
field() { local v; v=$(bfield "$1" "$2"); [ "$v" = "<absent>" ] || printf '%s' "$v"; }
# The bead a disposed bead names through its supersedes or duplicates edge.
succ() { local s; s=$(bedges "$1" supersedes); [ -n "$s" ] || s=$(bedges "$1" duplicates); printf '%s' "${s:-<absent>}"; }
# Whether a bead waits on a gate through a blocks edge: 1 or 0.
on_gate() { case " $(bedges "$1" blocks) " in *" $2 "*) echo 1 ;; *) echo 0 ;; esac; }
# A sling is a line of the fake's log, which a pass's start makes.
slings() { grep -c '^sling ' "$STUB_GC_LOG" || true; }
sling_lines() { grep '^sling ' "$STUB_GC_LOG" || true; }
run()    { OUT=$("$SCRIPT" "$@" 2>&1); RC=$?; }
pass()   { PASS_OUT=$("$GCTK_BIN" bead start-armed 2>&1); PASS_RC=$?; }
line_of() { grep -n -F -- "$1" "$STUB_GC_LOG" | head -1 | cut -d: -f1; }
# close_of <bead> — the line of the bead's close, a guarded update that moves it
# to closed, which the release's guarded update before it does not.
close_of() { grep -n -F -- "update $1 --if-status" "$STUB_GC_LOG" | grep -F -- "--status=closed" | head -1 | cut -d: -f1; }
# The store's writes among the fake's log lines, gctk's own included, which name
# their store ahead of the verb.
WRITES='^bd (--(db|actor) [^ ]+ )*(update|close|gate resolve|dep remove|dep add)'
writes() { grep -c -E "$WRITES" "$STUB_GC_LOG" || true; }
# snap and same: the store's rows and edges as a case found them, and whether
# they still read that way.
snap() { cp "$STUB_STORE" "$TMP/before.json" && cp "$STUB_DEPS" "$TMP/before.deps"; }
same() { cmp -s "$TMP/before.json" "$STUB_STORE" && cmp -s "$TMP/before.deps" "$STUB_DEPS"; }
refused() { # <label> <args...>: exit 1, the store as it was, nothing sent
  local label="$1"; shift
  snap
  run "$@"
  eq "$RC" 1 "$label: exit 1"
  if same; then ok "$label: nothing was written"; else bad "$label: the store changed"; fi
  has "$OUT" "Nothing was written." "$label: it says so"
  eq "$(writes)" 0 "$label: no write was tried"
}

# --- the orders by hand ---------------------------------------------------------
fresh
OUT=$(gc bd close tk-w --reason "standing down" 2>&1); RC=$?
eq "$RC" 1 "control: closing the bead first is refused"
has "$OUT" "cannot close blocked issue" "control: …because the open gate blocks it"
eq "$(field tk-w status)" open "control: …and it stays open"
fresh
gc bd gate resolve tk-g --reason "ruled: do not go on" >/dev/null 2>&1
pass
eq "$(slings)" 1 "control: answering the gate first lets the next pass sling the work"
shared
gc bd dep remove tk-w tk-g >/dev/null 2>&1
pass
eq "$(slings)" 1 "control: taking the bead off a shared gate with its arm standing lets the next pass sling the work"

# --- the stand-down -------------------------------------------------------------
fresh
bset tk-w metadata.gc.execution_routed_to=rig/pool metadata.gc.routed_to=rig/pool metadata.gc.session_id=s-1 metadata.gc.session_name=n-1
run tk-w --key polecat-x --ruling "the branch is wrong and nobody needs this"
eq "$RC" 0 "a stand-down exits 0"
eq "$(field tk-w status)" closed "the work closes"
has "$(field tk-w notes)" "not needed, per tk-g in rig:tkrig" "…as not needed, per the gate"
has "$(field tk-w notes)" "the branch is wrong and nobody needs this" "…with the ruling in its note"
eq "$(succ tk-w)" tk-g "…its supersedes edge naming the gate"
eq "$(meta tk-w gc.work_outcome)" no-op "…recording that nothing shipped"
eq "$(field tk-g status)" closed "the gate closes"
eq "$(field tk-g close_reason)" "ruled: the branch is wrong and nobody needs this" "…with the ruling as its answer"
for k in gc.dispatch_when_ready gc.dispatch_when_ready_args gc.dispatch_when_ready_reason; do
  eq "$(meta tk-w "$k")" "<absent>" "the arm is gone: $k"
done
for k in gc.routed_to gc.session_id gc.session_name gc.execution_routed_to; do
  case "$(meta tk-w "$k")" in ""|"<absent>") ok "the dispatch path is gone: $k" ;; *) bad "the dispatch path is gone: $k (reads $(meta tk-w "$k"))" ;; esac
done
DISARM=$(line_of "--unset-metadata gc.dispatch_when_ready ")
ANSWER=$(line_of "gate resolve tk-g")
CLOSE=$(close_of tk-w)
if [ -n "$DISARM" ] && [ -n "$ANSWER" ] && [ -n "$CLOSE" ] && [ "$DISARM" -lt "$ANSWER" ] && [ "$ANSWER" -lt "$CLOSE" ]; then
  ok "the arm goes first, then the answer, then the close"
else
  bad "the arm goes first, then the answer, then the close (lines ${DISARM:-none}, ${ANSWER:-none}, ${CLOSE:-none})"
fi
pass
eq "$PASS_RC" 0 "the next pass is clean"
eq "$(slings)" 0 "…and slings nothing"
WRITES_BEFORE=$(writes)
run tk-w --key polecat-x --ruling "again"
eq "$RC" 0 "a second run exits 0"
has "$OUT" "already closed" "…and says there is nothing to do"
eq "$(writes)" "$WRITES_BEFORE" "…and writes nothing"
eq "$(field tk-g close_reason)" "ruled: the branch is wrong and nobody needs this" "…and the first answer stands"

fresh
STUB_AFTER_WRITE="$TMP/after-write" run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "with a pass after every write, the stand-down still lands"
eq "$(slings)" 0 "…and none of those passes slings the work"
[ -s "$PASS_LOG" ] && ok "…and the passes did run" || bad "…and the passes did run"

fresh
STUB_HOOK_AT="list --id tk-w" STUB_HOOK="$TMP/land" LAND="$SCRIPT tk-w --key polecat-x --ruling 'stop while the pass runs'" pass
eq "$(field tk-w status)" closed "a stand-down that lands between a pass's listing and its hold read closes the work"
eq "$(slings)" 0 "…and that pass does not sling it"
has "$PASS_OUT" '"action":"withdrawn"' "…and says why"

# --- the run beneath the bead ----------------------------------------------------
# live_run: a graph.v2 run over tk-w, its root r-1 in progress over the input
# convoy c-1, which tracks tk-w, as the harness's runs reader reads one.
live_run() {
  brow r-1 status=in_progress issue_type=task title=mol-polecat-work \
    'metadata:={"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"c-1"}'
  brow c-1 status=open issue_type=convoy "title=input convoy for tk-w" 'metadata:={"gc.synthetic":"true"}'
  edge c-1 tracks tk-w
}
fresh; live_run
run tk-w --key polecat-x --ruling "stop the run"
eq "$RC" 0 "a bead with a live run stands down"
CANCEL=$(line_of "run-cancel --root r-1")
ANSWER=$(line_of "gate resolve tk-g")
if [ -n "$CANCEL" ] && [ -n "$ANSWER" ] && [ "$CANCEL" -lt "$ANSWER" ]; then
  ok "…and its run ends before the gate is answered"
else
  bad "…and its run ends before the gate is answered (lines ${CANCEL:-none}, ${ANSWER:-none})"
fi
fresh; live_run
STUB_RUN_CANCEL_FAILS=1 run tk-w --key polecat-x --ruling "stop the run"
eq "$RC" 1 "a run that does not end stops the stand-down"
eq "$(field tk-g status)" open "…with the gate unanswered"
eq "$(field tk-w status)" open "…and the work open"

# --- a stop at each write, then a re-run ------------------------------------------
stop_case() { # <label> <text the fake refuses> <gate status after> <arm after> <text the stop names>
  fresh
  STUB_FAIL_ON="$2" run tk-w --key polecat-x --ruling "stop"
  eq "$RC" 1 "stop at $1: exit 1"
  has "$OUT" "Re-run this command" "stop at $1: it names the way on"
  has "$OUT" "$5" "stop at $1: it says what stands"
  eq "$(field tk-g status)" "$3" "stop at $1: the gate reads $3"
  case "$4" in
    armed) eq "$(meta tk-w gc.dispatch_when_ready)" rig/pool "stop at $1: the arm stands" ;;
    gone)  eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "stop at $1: the arm is gone" ;;
  esac
  [ "$4" = armed ] || { pass; eq "$(slings)" 0 "stop at $1: a pass sends nothing"; }
  run tk-w --key polecat-x --ruling "stop"
  eq "$RC" 0 "stop at $1: a re-run exits 0"
  eq "$(field tk-w status)" closed "stop at $1: a re-run closes the work"
  eq "$(field tk-g close_reason)" "ruled: stop" "stop at $1: the gate carries the ruling"
  eq "$(succ tk-w)" tk-g "stop at $1: its edge names the gate"
  eq "$(slings)" 0 "stop at $1: nothing was sent"
}
stop_case "the disarm" "--unset-metadata gc.dispatch_when_ready " open armed "was not removed"
stop_case "the release" "gc.takeaway=" open gone "did not end or its route did not clear"
stop_case "the answer" "gate resolve" open gone "did not resolve"
stop_case "the close" "--status=closed" closed gone "bead-rehome.sh said why"
# The writer's non-zero exit can come after its close. The bead is closed then, and
# a re-run of the stand-down would find it closed and record nothing.
fresh
STUB_LIST_FAIL_AFTER="--status=closed" run tk-w --key polecat-x --ruling "stop"
eq "$RC" 1 "a close that stands behind the writer's exit 4 is reported"
eq "$(field tk-w status)" closed "…the work is closed"
has "$OUT" "closed as not needed, but its edge onto tk-g may not be recorded" "…and it says the close stands"
has "$OUT" "bead-rehome.sh --origin tk-w --successor tk-g --kind not-needed" "…and names the call that records the edge"
hasnt "$OUT" "it did not close" "…and does not say it did not close"
run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "…a re-run finds it closed"
has "$OUT" "already closed" "…and says so"

# --- refusals --------------------------------------------------------------------
for mr in pull_request_pending pull_request_head_changed; do
  fresh; bset tk-w "metadata.merge_result=$mr"
  refused "an open PR at $mr" tk-w --key polecat-x --ruling "x"
  has "$OUT" "pr-dispose.sh" "an open PR at $mr: it names the writer that retires one"
  has "$OUT" "--retire" "…and the sitting's sign-off that runs it"
done
fresh
refused "no gate under the key" tk-w --key another-key --ruling "x"
has "$OUT" "no human gate under another-key" "no gate under the key: it says so"
fresh; gate tk-g2 another-question "another question"; edge tk-w blocks tk-g2
refused "another open gate" tk-w --key polecat-x --ruling "x"
has "$OUT" "tk-g2" "another open gate: it names the gate"
shared; bset tk-g assignee=a-person-owes-it
refused "a gate a person is assigned that this bead leaves" tk-w --key polecat-x --ruling "x" --successor tk-conv
fresh; bset tk-g assignee=a-person-owes-it status=in_progress
refused "a gate a person is assigned that is in progress" tk-w --key polecat-x --ruling "x"
fresh; bead tk-p prerequisite; edge tk-w blocks tk-p
refused "another live blocker" tk-w --key polecat-x --ruling "x"
has "$OUT" "tk-p" "another live blocker: it names it"
fresh; bead tk-c child parent=tk-w
refused "an open child" tk-w --key polecat-x --ruling "x"
has "$OUT" "tk-c" "an open child: it names it"
shared
refused "a gate that also holds another open bead, with nothing else as the evidence" tk-w --key polecat-x --ruling "x"
has "$OUT" "also holds tk-o" "a shared gate's refusal: it names the other bead"
has "$OUT" "--successor" "a shared gate's refusal: it names the way on"
hasnt "$OUT" "dep remove" "a shared gate's refusal: it sends nobody to take the bead off the gate by hand"
shared
refused "a shared gate named as the evidence" tk-w --key polecat-x --ruling "x" --successor tk-g
has "$OUT" "cannot carry this ruling" "a shared gate named as the evidence: it says why"
fresh; bset tk-w assignee=someone status=in_progress
refused "a claim" tk-w --key polecat-x --ruling "x"
has "$OUT" "someone" "a claim: it names the holder"
fresh; edge tk-w supersedes tk-conv
refused "a disposition already naming other evidence" tk-w --key polecat-x --ruling "x" --successor tk-g
fresh; bset tk-w metadata.task_kind=review
refused "a review bead" tk-w --key polecat-x --ruling "x"
fresh
refused "an unreadable bead" tk-absent --key polecat-x --ruling "x"
has "$OUT" "could not read tk-absent" "an unreadable bead: it says so"
fresh
snap
STUB_FAIL_ON="dep list tk-w" run tk-w --key polecat-x --ruling "x" --successor tk-conv
eq "$RC" 1 "gates that do not read: exit 1"
has "$OUT" "could not read the human gates of tk-w" "gates that do not read: it says so"
same && ok "gates that do not read: nothing was written" || bad "gates that do not read: the store changed"
fresh
snap
STUB_FAIL_ON="--direction=up" run tk-w --key polecat-x --ruling "x"
eq "$RC" 1 "what the gate holds does not read: exit 1"
same && ok "what the gate holds does not read: nothing was written" || bad "what the gate holds does not read: the store changed"
fresh; bead tk-o landed status=closed; edge tk-o blocks tk-g
run tk-w --key polecat-x --ruling "x"
eq "$RC" 0 "a gate that holds only a closed bead besides this one is no refusal"
eq "$(field tk-g close_reason)" "ruled: x" "…and that gate carries the ruling"

# --- a gate a person is assigned ----------------------------------------------------
# bead-rehome.sh --check holds a gate a person is assigned, and the ruling answers
# it, so the stand-down takes it back from them before that check.
assigned() { fresh; bset tk-g assignee=a-person-owes-it; }
first_write() { grep -n -E "$WRITES" "$STUB_GC_LOG" | head -1 | cut -d: -f1; }
assigned
run tk-w --key polecat-x --ruling "the push is not wanted"
eq "$RC" 0 "a gate a person is assigned: the stand-down exits 0"
has "$OUT" "took gate tk-g back from a-person-owes-it" "…saying it took the gate back from them"
TAKE=$(line_of "update tk-g --if-status=open --if-assignee=a-person-owes-it --assignee=")
[ -n "$TAKE" ] && [ "$TAKE" = "$(first_write)" ] && ok "…in the first write, held to the open gate and the assignee read" \
  || bad "…in the first write, held to the open gate and the assignee read (take-back line ${TAKE:-none}, first write line $(first_write))"
eq "$(field tk-g assignee)" "" "…so it no longer names them"
eq "$(field tk-g close_reason)" "ruled: the push is not wanted" "…and the gate carries the ruling"
eq "$(field tk-w status)" closed "…and the work closes"
eq "$(succ tk-w)" tk-g "…its edge naming the gate"
pass
eq "$(slings)" 0 "…and the next pass slings nothing"

assigned; bead tk-p prerequisite; edge tk-w blocks tk-p
run tk-w --key polecat-x --ruling "x"
eq "$RC" 1 "a gate a person is assigned, with another live blocker: exit 1"
has "$OUT" "tk-p" "…naming the blocker"
has "$OUT" "Nothing was written but the take-back printed above" "…and the take-back as the one write"
eq "$(writes)" 1 "…which is the one write tried"
eq "$(field tk-g assignee)" "" "…and it stands"
eq "$(field tk-g status)" open "…with the gate open"
eq "$(meta tk-w gc.dispatch_when_ready)" rig/pool "…and the arm in place"
bset tk-p status=closed
run tk-w --key polecat-x --ruling "x"
eq "$RC" 0 "…and once the blocker closes, a re-run stands the work down"
eq "$(field tk-w status)" closed "…closing it"

assigned
snap
STUB_FAIL_ON="--if-assignee=a-person-owes-it" run tk-w --key polecat-x --ruling "x"
eq "$RC" 1 "a take-back the store refuses: exit 1"
has "$OUT" "gate tk-g was not taken back from a-person-owes-it" "…saying so"
has "$OUT" "Nothing was written." "…and that nothing was written"
same && ok "…and nothing was" || bad "…and nothing was"

assigned
STUB_HOOK_AT="update tk-g" STUB_HOOK="$TMP/land" LAND="gc --harness-write set tk-g assignee=someone-else" \
  run tk-w --key polecat-x --ruling "x"
eq "$RC" 1 "a gate assigned to someone else after the read: exit 1"
eq "$(field tk-g assignee)" someone-else "…and the gate stays theirs"
eq "$(field tk-w status)" open "…and the work open"

assigned
snap
run tk-w --key polecat-x --ruling "x" --dry-run
eq "$RC" 0 "a dry run with a gate to take back exits 0"
has "$OUT" "DRY RUN: the ruling answers each gate under polecat-x, so a real run first takes back gate tk-g from a-person-owes-it" "…naming the take-back"
has "$OUT" "cannot say whether tk-w would close" "…and that it reads no further"
eq "$(writes)" 0 "…and tries no write"
same && ok "…and writes nothing" || bad "…and writes nothing"

# --- a bead at an exception of the pending record ---------------------------------
RECORD_GO="$ROOT/services/gctk/pr/record/record.go"
EXCEPTIONS=$(for name in $(awk '/^func Exception\(/ { f = 1 } f && /case / { sub(/^[[:space:]]*case /, ""); sub(/:.*/, ""); gsub(/,/, " "); print; exit }' "$RECORD_GO"); do
    awk -v n="$name" '$1 == n && $2 == "=" { gsub(/"/, "", $3); print $3 }' "$RECORD_GO"
  done | sort | paste -sd ' ' -)
COPY=$(sed -n 's/^RECORD_EXCEPTIONS="\(.*\)"$/\1/p' "$SCRIPT" | tr ' ' '\n' | sort | paste -sd ' ' -)
if [ -n "$EXCEPTIONS" ]; then
  eq "$COPY" "$EXCEPTIONS" "(NO-DRIFT) the script's exceptions are the values record.Exception names"
else
  bad "(NO-DRIFT) no exception read from $RECORD_GO"
fi
PR7=https://github.com/o/r/pull/7
PR8=https://github.com/o/r/pull/8
# exception <merge_result> [<setting>...]: the work bead at an exception whose
# gate has filed, blocked at that value behind a gate keyed by it, with its record
# naming PR7, and the settings after that.
exception() {
  local mr="$1"; shift
  fresh
  bset tk-w status=blocked "metadata.merge_result=$mr" "metadata.pr_url=$PR7" "$@"
  bset tk-g "await_id=$mr"
}
gh_says()  { printf '%s %s\n' "$1" "$2" >> "$STUB_GH_STATES"; } # <url> <state>
gh_reads() { grep -c '^gh pr view ' "$STUB_GC_LOG" || true; }
gh_other() { grep '^gh ' "$STUB_GC_LOG" | grep -vc '^gh pr view ' || true; }
for v in $EXCEPTIONS; do
  exception "$v"; gh_says "$PR7" OPEN
  refused "$v, its PR open" tk-w --key "$v" --ruling "x"
  has "$OUT" "gh pr close $PR7" "$v, its PR open: it names the close"
  eq "$(gh_other)" 0 "$v, its PR open: GitHub is only read"
done
exception pull_request_reconcile_invalid "metadata.existing_pr=$PR7"; gh_says "$PR7" CLOSED
run tk-w --key pull_request_reconcile_invalid --ruling "the record is wrong and nobody needs the work"
eq "$RC" 0 "a bead at an exception whose PR reads closed stands down"
eq "$(field tk-w status)" closed "…and closes"
eq "$(field tk-g close_reason)" "ruled: the record is wrong and nobody needs the work" "…with its gate answered"
eq "$(gh_reads)" 1 "…and a PR both keys name is read once"
exception pull_request_merged_unvalidated_head; gh_says "$PR7" MERGED
run tk-w --key pull_request_merged_unvalidated_head --ruling "x"
eq "$RC" 0 "a bead at an exception whose PR reads merged stands down"
eq "$(field tk-w status)" closed "…and closes"
exception pull_request_reconcile_invalid
refused "an exception whose PR does not read" tk-w --key pull_request_reconcile_invalid --ruling "x"
has "$OUT" "GitHub did not say whether its PR $PR7 is still open" "an exception whose PR does not read: it says so"
exception pull_request_legacy_closed_unverified
bunset tk-w metadata.pr_url; bset tk-w "metadata.existing_pr=$PR8"
gh_says "$PR8" OPEN
refused "an exception whose record names its PR only as existing_pr" tk-w --key pull_request_legacy_closed_unverified --ruling "x"
has "$OUT" "gh pr close $PR8" "an exception whose record names its PR only as existing_pr: it names that PR's close"
exception pull_request_closed_unmerged "metadata.existing_pr=$PR8"; gh_says "$PR7" CLOSED; gh_says "$PR8" OPEN
refused "an exception whose record names a second PR, open" tk-w --key pull_request_closed_unmerged --ruling "x"
has "$OUT" "gh pr close $PR8" "an exception whose record names a second PR, open: it names that one"
exception pull_request_reconcile_invalid metadata.pr_url=7
refused "an exception whose pr_url is no PR's URL" tk-w --key pull_request_reconcile_invalid --ruling "x"
has "$OUT" "pr_url reads '7'" "an exception whose pr_url is no PR's URL: it names the key and its value"
eq "$(gh_reads)" 0 "an exception whose pr_url is no PR's URL: GitHub is not asked"
exception pull_request_reconcile_invalid
bunset tk-w metadata.pr_url
refused "an exception whose record names no PR" tk-w --key pull_request_reconcile_invalid --ruling "x"
has "$OUT" "neither pr_url nor existing_pr names its PR" "an exception whose record names no PR: it says so"
eq "$(gh_reads)" 0 "an exception whose record names no PR: GitHub is not asked"
exception pull_request_legacy_closed_unverified "metadata.pr_url= " metadata.existing_pr=
refused "an exception whose PR keys are empty" tk-w --key pull_request_legacy_closed_unverified --ruling "x"
has "$OUT" "neither pr_url nor existing_pr names its PR" "an exception whose PR keys are empty: it says so"
exception pull_request_reconcile_invalid
bunset tk-w metadata.pr_url
refused "a dry run at an exception whose record names no PR" tk-w --key pull_request_reconcile_invalid --ruling "x" --dry-run
hasnt "$OUT" "DRY RUN" "a dry run at an exception whose record names no PR: it reports no plan"
exception pull_request_reconcile_invalid; gh_says "$PR7" OPEN
refused "a dry run at an exception whose PR is open" tk-w --key pull_request_reconcile_invalid --ruling "x" --dry-run
hasnt "$OUT" "DRY RUN" "a dry run at an exception whose PR is open: it reports no plan"
fresh; bset tk-w metadata.merge_result=blocked "metadata.existing_pr=$PR7"
gh_says "$PR7" OPEN
run tk-w --key polecat-x --ruling "x"
eq "$RC" 0 "a refinery park stands down whatever the PR it records reads"
eq "$(gh_reads)" 0 "…and GitHub is not asked"

# --- a gate that also holds another open bead --------------------------------------
shared
bset tk-w metadata.gc.routed_to=rig/pool
STUB_HOOK_AT="dep remove tk-w" STUB_HOOK="$TMP/land" LAND="$TMP/at-edge" \
  run tk-w --key polecat-x --ruling "only this bead stops" --successor tk-conv
eq "$RC" 0 "with the evidence named, a shared gate stands this bead down"
eq "$(field tk-w status)" closed "…and closes it"
eq "$(succ tk-w)" tk-conv "…its edge naming the evidence"
eq "$(cat "$AT_EDGE")" "|" "…with no arm and no route left when the edge goes"
eq "$(field tk-g status)" open "…and the gate stays open"
eq "$(field tk-g close_reason)" "" "…unanswered"
eq "$(line_of "gate resolve")" "" "…with no answer tried"
eq "$(on_gate tk-w tk-g)" 0 "…and this bead off it"
eq "$(on_gate tk-o tk-g)" 1 "…and the other bead still on it"
eq "$(field tk-o status)" open "…and the other bead open"
has "$OUT" "left gate tk-g, which stays open: gate tk-g also holds tk-o" "…and it says what the gate still holds"
DISARM=$(line_of "--unset-metadata gc.dispatch_when_ready ")
RELEASE=$(line_of "gc.takeaway=")
LEAVE=$(line_of "dep remove tk-w tk-g")
CLOSE=$(close_of tk-w)
if [ -n "$DISARM" ] && [ -n "$RELEASE" ] && [ -n "$LEAVE" ] && [ -n "$CLOSE" ] && [ "$DISARM" -lt "$RELEASE" ] && [ "$RELEASE" -lt "$LEAVE" ] && [ "$LEAVE" -lt "$CLOSE" ]; then
  ok "the arm goes first, then the route, then the edge, then the close"
else
  bad "the arm goes first, then the route, then the edge, then the close (lines ${DISARM:-none}, ${RELEASE:-none}, ${LEAVE:-none}, ${CLOSE:-none})"
fi
pass
eq "$(slings)" 0 "the next pass slings nothing"
bset tk-o metadata.gc.dispatch_when_ready=rig/pool 'metadata.gc.dispatch_when_ready_args=[]' metadata.gc.dispatch_when_ready_armed_at=2026-11-01T00:00:00Z
pass
eq "$(slings)" 0 "the gate still holds the other bead's arm"
gc bd gate resolve tk-g --reason "ruled: the other bead goes on" >/dev/null 2>&1
pass
eq "$(slings)" 1 "an answer once this bead has closed sends the other bead"
has "$(sling_lines)" "tk-o" "…and that sling is the other bead's"
hasnt "$(sling_lines)" "tk-w" "…and not this one's"

shared
STUB_AFTER_WRITE="$TMP/after-write" run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 0 "with a pass after every write, the shared gate's stand-down still lands"
eq "$(slings)" 0 "…and none of those passes, the one right after the edge goes included, slings the work"
[ -s "$PASS_LOG" ] && ok "…and the passes did run" || bad "…and the passes did run"

shared
STUB_HOOK_AT="where --json" STUB_HOOK="$TMP/land" LAND="$SCRIPT tk-w --key polecat-x --ruling 'stop while the pass runs' --successor tk-conv" pass
eq "$(field tk-w status)" closed "a shared gate's stand-down that lands while a pass runs closes the work"
eq "$(slings)" 0 "…and that pass does not sling it"

shared
STUB_HOOK_AT="where --json" STUB_HOOK="$TMP/land" LAND="STUB_FAIL_ON='--status=closed' $SCRIPT tk-w --key polecat-x --ruling 'stop while the pass runs' --successor tk-conv" pass
eq "$(field tk-w status)" open "a shared gate's stand-down that has taken the bead off the gate but not closed it while a pass runs leaves it open"
eq "$(slings)" 0 "…and that pass does not sling it"
pass
eq "$(slings)" 0 "…nor does the next, which finds it ready with no arm"

shared
STUB_FAIL_ON="dep remove tk-w" run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 1 "an edge that does not go stops the stand-down"
has "$OUT" "did not leave gate tk-g" "…and it says so"
has "$OUT" "Re-run this command" "…and names the way on"
eq "$(field tk-w status)" open "…with the work open"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "…and its arm gone"
pass
eq "$(slings)" 0 "…so a pass sends nothing"
run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 0 "a re-run stands it down"
eq "$(field tk-w status)" closed "…and closes it"
eq "$(field tk-g status)" open "…and the gate stays open"
eq "$(slings)" 0 "…and nothing was sent"

shared
bset tk-w metadata.gc.routed_to=rig/pool
STUB_FAIL_ON='gc.takeaway=' run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 1 "a release the store refuses stops the stand-down before the bead leaves a shared gate"
has "$OUT" "did not end or its route did not clear" "…and says why"
eq "$(line_of "dep remove tk-w")" "" "…with no removal tried"
eq "$(on_gate tk-w tk-g)" 1 "…and the bead still on the gate"

shared
STUB_FAIL_ON="--status=closed" run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 1 "a close refused after the edge went stops"
has "$OUT" "no gate under polecat-x holds it" "…and it says what stands"
hasnt "$OUT" "answered" "…and calls no gate answered, since the bead left this one"
run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 0 "the same command, re-run, closes"
eq "$(succ tk-w)" tk-conv "…naming the evidence it names"
eq "$(field tk-g status)" open "…and the gate stays open"

# A twin gate under the key that holds the other bead alone besides this one.
fresh; bead tk-o "another bead"; gate tk-g2 polecat-x "a twin"
edge tk-w blocks tk-g2; edge tk-o blocks tk-g2
run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "a twin gate that holds only this bead carries the ruling for the one it leaves"
eq "$(field tk-g close_reason)" "ruled: stop" "…with the ruling as its answer"
eq "$(succ tk-w)" tk-g "…and its edge naming it"
eq "$(field tk-g2 status)" open "…and the shared twin stays open"
eq "$(field tk-w status)" closed "…and the work closes"

shared; gate tk-g2 polecat-x "a twin"; bead tk-o2 "a second bead"
edge tk-o2 blocks tk-g2; edge tk-w blocks tk-g2
run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 0 "two gates under the key that each hold another bead: the bead leaves both"
eq "$(field tk-g status)" open "…with the first open"
eq "$(field tk-g2 status)" open "…and the second open"
eq "$(bedges tk-w blocks)" "" "…and on neither"
eq "$(field tk-w status)" closed "…and the work closes"

shared
snap
run tk-w --key polecat-x --ruling "x" --successor tk-conv --dry-run
eq "$RC" 0 "a shared gate's dry run exits 0"
has "$OUT" "also holds tk-o" "…and names what the gate still holds"
same && ok "…and writes nothing" || bad "…and writes nothing"

# --- evidence, wording, dry run ---------------------------------------------------
fresh
run tk-w --key polecat-x --ruling "the operator ruled this out" --successor tk-conv
eq "$RC" 0 "--successor names other evidence"
eq "$(succ tk-w)" tk-conv "…and its edge names it"
eq "$(field tk-g close_reason)" "ruled: the operator ruled this out" "…and the gate still carries the ruling"
fresh
refused "a successor that does not exist" tk-w --key polecat-x --ruling "x" --successor tk-nobody

fresh
STUB_FAIL_ON="--status=closed" run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 1 "a close refused under --successor stops"
eq "$(succ tk-w)" "<absent>" "…recording no successor, since the close did not land"
run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 0 "the same command, re-run, closes"
eq "$(succ tk-w)" tk-conv "…naming the evidence it names"

fresh; gate tk-g2 polecat-x "a twin"; edge tk-w blocks tk-g2
run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "twin gates under the key do not stop a stand-down"
eq "$(field tk-g close_reason)|$(field tk-g2 close_reason)" "ruled: stop|ruled: stop" "…and each carries the ruling"
eq "$(succ tk-w)" tk-g "…and its edge names the first"

fresh; bset tk-g status=closed "close_reason=ruled: an earlier answer"; bunset tk-w metadata.gc.dispatch_when_ready
run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "a gate already answered still names the evidence"
eq "$(succ tk-w)" tk-g "…in its edge"
eq "$(field tk-g close_reason)" "ruled: an earlier answer" "…and its answer stands"

fresh
STUB_HOOK_AT="gate resolve" STUB_HOOK="$TMP/land" LAND="gc --harness-write set tk-g status=closed 'close_reason=ruled: go on'" run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "another answer that reaches the gate first does not stop the close"
has "$OUT" "another answer reached gate tk-g first" "…and it is reported"
eq "$(field tk-g close_reason)" "ruled: go on" "…and stands"

fresh
run tk-w --key polecat-x --ruling "ruled: already headed"
eq "$(field tk-g close_reason)" "ruled: already headed" "a ruling already headed ruled: is not headed twice"
fresh
run tk-w --key polecat-x --ruling "over
two lines"
eq "$(field tk-g close_reason)" "ruled: over two lines" "a ruling is one line"

fresh; bset tk-w 'metadata:={}'
run tk-w --key polecat-x --ruling "no arm here"
eq "$RC" 0 "a bead with no arm stands down"
eq "$(line_of "--unset-metadata gc.dispatch_when_ready ")" "" "…and its disarm writes nothing"
# The disarm reads no arm first, so an arm written after the stand-down read the
# bead is removed before the gate's answer could send it. The arm lands ahead of
# gctk's own read of the bead, the first read that lists templates.
fresh; bset tk-w 'metadata:={}'
STUB_HOOK_AT="--include-templates" STUB_HOOK="$TMP/land" \
  LAND="gc --harness-write set tk-w metadata.gc.dispatch_when_ready=rig/pool 'metadata.gc.dispatch_when_ready_args=[]' metadata.gc.dispatch_when_ready_armed_at=2026-11-13T00:00:00Z 'metadata.gc.dispatch_when_ready_reason=armed meanwhile'" \
  run tk-w --key polecat-x --ruling "armed after the read"
eq "$RC" 0 "a bead armed after the stand-down read it stands down"
[ -e "$LANDED" ] && ok "…the arm landed in the stand-down's run" || bad "the arm never landed, so the case proves nothing"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "…and the arm written meanwhile is gone"
DISARM=$(line_of "--unset-metadata gc.dispatch_when_ready ")
ANSWER=$(line_of "gate resolve tk-g")
if [ -n "$DISARM" ] && [ -n "$ANSWER" ] && [ "$DISARM" -lt "$ANSWER" ]; then
  ok "…removed before the gate's answer"
else
  bad "the arm written meanwhile is removed before the gate's answer (lines ${DISARM:-none}, ${ANSWER:-none})"
fi
fresh; bset tk-w metadata.gc.routed_to=human
run tk-w --key polecat-x --ruling "parked for a person"
eq "$RC" 0 "a subject parked on the person route stands down"
eq "$(field tk-w status)" closed "…and closes"
eq "$(meta tk-w gc.routed_to)" "" "…with its person route cleared"
fresh; bset tk-w metadata.branch=polecat/tk-w
run tk-w --key polecat-x --ruling "drop the branch"
has "$(cat "$STUB_GC_LOG")" "branch-end --rig tkrig --branch polecat/tk-w" "the bead's branch ends with the close"

fresh
snap
run tk-w --key polecat-x --ruling "x" --dry-run
eq "$RC" 0 "a dry run exits 0"
has "$OUT" "DRY RUN" "…and says so"
has "$OUT" "tk-g" "…and names the evidence"
same && ok "…and writes nothing" || bad "…and writes nothing"

# --- an epic that carries a hypothesis ---------------------------------------------
# The close stamps its disposition before it runs the finalize gate, and the gate
# takes that as a stewarded epic's terminal reason. The check ahead of the first
# write has to read the epic the same way, or it refuses what the close would do.
epic() { # [<key>=<value>...]: the work bead as a stewarded epic, with those metadata keys
  local s m=()
  for s in "$@"; do m+=("metadata.$s"); done
  fresh
  bset tk-w issue_type=epic "metadata.epic_hypothesis=the hypothesis" ${m[@]+"${m[@]}"}
}
epic
run tk-w --key polecat-x --ruling "the operator ruled this epic out" --successor tk-conv
eq "$RC" 0 "an epic with no ruling stands down, with a conversation as the evidence"
eq "$(field tk-w status)" closed "…and closes"
has "$(field tk-w notes)" "not needed, per tk-conv" "…as not needed, per the conversation"
eq "$(succ tk-w)" tk-conv "…recording the disposition that is its terminal reason"
eq "$(field tk-g close_reason)" "ruled: the operator ruled this epic out" "…with its gate answered"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "…and its arm gone"
eq "$(meta tk-w epic_ruling)" "<absent>" "…and no epic_ruling written, which is the operator's alone"
pass
eq "$(slings)" 0 "…and the next pass slings nothing"
epic
run tk-w --key polecat-x --ruling "the operator ruled this epic out"
eq "$RC" 0 "an epic with no ruling stands down with its gate as the evidence"
eq "$(succ tk-w)" tk-g "…its edge naming the gate"
eq "$(field tk-w status)" closed "…and closes"
for m in epic_ruling=continue epic_ruling=shift epic_ruling=pending epic_ruling=close 'epic_ruling=close epic_ruling_reason=held'; do
  # shellcheck disable=SC2086  # each row is the keys it spells
  epic $m
  run tk-w --key polecat-x --ruling "ruled out" --successor tk-conv
  eq "$RC" 0 "an epic carrying $m stands down"
  eq "$(field tk-w status)" closed "…and closes"
done
epic
snap
run tk-w --key polecat-x --ruling "x" --successor tk-conv --dry-run
eq "$RC" 0 "a dry run on an epic with no ruling exits 0, as the stand-down would"
same && ok "…and writes nothing" || bad "…and writes nothing"
epic
STUB_FAIL_ON="--status=closed" run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 1 "a close refused on an epic stops"
pass
eq "$(slings)" 0 "…a pass between the runs slings nothing"
run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 0 "…and a re-run closes it"
eq "$(field tk-w status)" closed "…and it reads closed"
epic; bset tk-g assignee=a-person-it-asks
run tk-w --key polecat-x --ruling "x" --successor tk-conv
eq "$RC" 0 "an epic whose gate a person is assigned stands down"
eq "$(field tk-g assignee)" "" "…taking the gate back"
eq "$(field tk-w status)" closed "…and closing the epic"

# What else holds a close holds an epic's: each of these refuses, writing nothing.
epic; gate tk-g2 another-question "another question"; edge tk-w blocks tk-g2
refused "an epic under another open gate" tk-w --key polecat-x --ruling "x" --successor tk-conv
has "$OUT" "tk-g2" "…naming that gate"
refused "an epic with another open gate named as the evidence" tk-w --key polecat-x --ruling "x" --successor tk-g2
has "$OUT" "tk-g2" "…naming that gate"
epic; bead tk-pre "a prerequisite"; edge tk-w blocks tk-pre
refused "an epic with another live blocker" tk-w --key polecat-x --ruling "x" --successor tk-conv
has "$OUT" "tk-pre" "…naming it"
epic; bead tk-kid "a unit" parent=tk-w
refused "an epic with an open child" tk-w --key polecat-x --ruling "x" --successor tk-conv
has "$OUT" "tk-kid" "…naming it"
epic; bset tk-w status=in_progress assignee=a-live-session
refused "an epic someone has claimed" tk-w --key polecat-x --ruling "x" --successor tk-conv
has "$OUT" "a-live-session" "…naming them"

# The check agrees with the close it stands in front of: what it lets through
# closes, and what it refuses stays open.
agree() { # <label>: the store as set up
  local want=closed
  "$HERE/bead-rehome.sh" --origin tk-w --successor tk-conv --kind not-needed --except-key polecat-x --check >/dev/null 2>&1 || want=open
  "$HERE/bead-rehome.sh" --origin tk-w --successor tk-conv --kind not-needed --except-key polecat-x >/dev/null 2>&1
  eq "$(field tk-w status)" "$want" "$1: the close does what the check said"
}
for m in '' epic_ruling=continue epic_ruling=close 'epic_ruling=close epic_ruling_reason=held'; do
  # shellcheck disable=SC2086  # each row is the keys it spells
  epic $m
  agree "an epic carrying ${m:-no ruling}"
done
epic; edge tk-w supersedes tk-conv
agree "an epic already naming the evidence"
epic; bead tk-kid "a unit" parent=tk-w
agree "an epic with an open child"
epic; bead tk-pre "a prerequisite"; edge tk-w blocks tk-pre
agree "an epic with another live blocker"
epic; gate tk-g2 another-question "another question"; edge tk-w blocks tk-g2
agree "an epic under another open gate"

# --- usage -------------------------------------------------------------------------
fresh
for args in "tk-w --ruling x" "tk-w --key k" "--key k --ruling x" "tk-w --key k --ruling x --what" "tk-w --key --ruling x" "tk-w --key k --ruling x extra"; do
  # shellcheck disable=SC2086  # each row is the argv it spells
  run $args
  eq "$RC" 2 "usage: '$args'"
done
run 'tk w' --key k --ruling x
eq "$RC" 2 "usage: an id with a space is refused"
eq "$(writes)" 0 "usage errors write nothing"
if grep -q -e '--set-metadata' "$SCRIPT"; then bad "the script writes a metadata key of its own"; else ok "the script writes no metadata key of its own"; fi

# --- the clause a decline message carries ------------------------------------------
# Each message names the command with its own key, and that text runs as written.
# decline.sh writes it into the message of each gate the work scripts file with a
# re-sling.
CLAUSE=$(grep -o -e 'run \$SCRIPT_DIR/stand-down\.sh \$SUBJECT --key \$KEY --ruling '"'"'<why>'"'" "$ROOT/assets/scripts/decline.sh" | head -1)
[ -n "$CLAUSE" ] && ok "decline.sh carries the clause" || bad "decline.sh carries the clause"
fresh; bset tk-g await_id=polecat-branch-divergence
OUT=$(SCRIPT_DIR="$HERE" SUBJECT=tk-w KEY=polecat-branch-divergence bash -c "${CLAUSE#run }" 2>&1); RC=$?
eq "$RC" 0 "the clause runs as written"
eq "$(field tk-w status)" closed "…and closes the work"
eq "$(field tk-g close_reason)" "ruled: <why>" "…and answers the gate"

echo
echo "stand-down: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
