#!/usr/bin/env bash
# Hermetic test for assets/scripts/work-gate.sh, load-context's gate.
#
# Two dispatch surfaces can reach one work bead. Before the workspace is touched
# the gate refuses a bead that is gone, parked, in flight under a live owner or in
# another live run, waiting on a blocker, or finished.
#
# What it holds:
#   1. DISCRIMINATION: a no-op on work that is this session's to build.
#   2. NOBODY DECIDES: a finished bead and a live duplicate end the run with
#      nothing asked.
#   3. A PERSON DECIDES: a parked bead files a gate first, and a bead the store
#      does not have files a finding.
#   4. THE STORE: a store that does not answer asks nothing and cancels nothing.
#   5. FAIL CLOSED: a part that does not land stops what follows it.
#   6. ANOTHER RUN: of the live runs of this formula on the bead the oldest builds
#      it and the others refuse, with nothing written. A run of another formula is
#      no duplicate, a claimant with no run of its own refuses any of them, and the
#      gate asks for nothing Gas City's released core pack does not ship.
#   7. WAITING: a bead with an open blocker waits on it and is armed, and a retry
#      after any failure still knows the pool.
#
# The siblings it calls are stubs that log, except decline.sh and work-lib.sh,
# which are the real ones, and run-lib.stub.sh answers which runs work a bead. No
# live city, Dolt or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-gate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3" "'$2' unexpectedly in '$1'" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true

PACK="$TMP/pack"
mkdir -p "$TMP/bin" "$PACK"
cp "$HERE/work-gate.sh" "$HERE/work-lib.sh" "$HERE/decline.sh" "$HERE/bd-lib.sh" "$HERE/run-lib.sh" "$HERE/run-lib.stub.sh" "$PACK/"

stub() { # <name> <TRACE word> <capture file var> <rc var>
  cat > "$PACK/$1" <<STUB
#!/usr/bin/env bash
printf '$2\n' >> "\$FAKE_LOG"
printf '%s\n' "\$*" >> "\${$3:-/dev/null}"
exit "\${$4:-0}"
STUB
  chmod +x "$PACK/$1"
}
stub run-cancel.sh CANCEL FAKE_CANCEL FAKE_CANCEL_RC
stub human-gate.sh GATE FAKE_GATE FAKE_GATE_RC
stub patrol-finding.sh FINDING FAKE_FINDING FAKE_FINDING_RC
stub await-ruling.sh AWAIT FAKE_AWAIT FAKE_AWAIT_RC

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  # Gas City's released core pack has no helper this gate could ask for.
  "core scripts-dir") printf 'CORE\n' >> "$FAKE_LOG"; exit 1 ;;
  "convoy status")
    [ -z "${FAKE_CONVOY_DOWN:-}" ] || { echo "convoy: store down" >&2; exit 1; }
    ONE='{"children":[{"id":"tk-work"}]}'
    printf '%s\n' "${FAKE_CONVOY:-$ONE}"; exit 0 ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "session list") printf '%s' "${FAKE_SESSIONS:-}"; exit 0 ;;
  "bd show")
    if [ -n "${FAKE_SHOW_OUT+x}" ]; then printf '%s' "$FAKE_SHOW_OUT"; exit "${FAKE_SHOW_RC:-1}"; fi
    cat "$FAKE_ROW_FILE"; exit 0 ;;
  "bd update") shift 2; printf 'UPDATE\n' >> "$FAKE_LOG"; printf '%s\n' "$*" >> "${FAKE_UPDATE:-/dev/null}"; exit "${FAKE_UPDATE_RC:-0}" ;;
  "bd list")
    shift 2; printf '%s\n' "$*" >> "${FAKE_LIST:-/dev/null}"
    [ -z "${FAKE_LIST_DOWN:-}" ] || exit 1
    printf '%s' "${FAKE_ROOTS:-[]}"; exit 0 ;;
esac
echo "gc stub: unsupported '$*'" >&2
exit 2
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

SELF_NAME="hq-me-pool"; SELF_ID="sess-me"; SELF_AGENT="rig/rig.polecat"; SELF_ALIAS="me-alias"
REFINERY="gc-toolkit/gc-toolkit.refinery"
SESS_EMPTY='{"sessions":[]}'
SESS_REAL='{"sessions":[{"session_name":"hq-busy","id":"sess-busy","alias":"rig/rig.polecat-busy"}]}'
SESS_OTHER='{"sessions":[{"session_name":"hq-other"}]}'

# row '<json fields>' -> one array row with id tk-work
row() { printf '[%s]' "$(jq -c '. + {id: "tk-work"}' <<<"$1")"; }

# run <row-json> [gate args...] -> prints "<rc>|<ordered trace>"
run() {
  : > "$TMP/log"; : > "$TMP/update"; : > "$TMP/cancel"; : > "$TMP/await"; : > "$TMP/gate"; : > "$TMP/finding"; : > "$TMP/run-reads"; : > "$TMP/list"
  printf '%s' "$1" > "$TMP/row.json"
  printf '%s' "${FAKE_RUNS:-[]}" > "$TMP/runs.json"
  shift
  local rc=0
  [ "$#" -gt 0 ] || set -- --convoy cv-1
  ( cd "$TMP" || exit 97
    GC_SESSION_NAME="$SELF_NAME" GC_SESSION_ID="$SELF_ID" GC_AGENT="$SELF_AGENT" GC_ALIAS="$SELF_ALIAS" \
    WORK_READ_WAIT=0 FAKE_ROW_FILE="$TMP/row.json" \
    GC_RUN_LIB="$PACK/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$TMP/runs.json" RUN_LIB_STUB_LOG="$TMP/run-reads" FAKE_LIST="$TMP/list" \
    FAKE_LOG="$TMP/log" FAKE_UPDATE="$TMP/update" FAKE_CANCEL="$TMP/cancel" FAKE_AWAIT="$TMP/await" FAKE_GATE="$TMP/gate" FAKE_FINDING="$TMP/finding" \
    FAKE_SESSIONS="${FAKE_SESSIONS-$SESS_EMPTY}" \
      "$PACK/work-gate.sh" "$@" ) > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}
asked() { cat "$TMP/gate" "$TMP/finding"; }
DONE_NOBODY="1|UPDATE;CANCEL;DRAIN;"
DONE_PERSON="1|UPDATE;GATE;CANCEL;DRAIN;"

# --- 1. Discrimination. ----------------------------------------------------------
eq "$(run "$(row '{"status":"open","assignee":"","metadata":{}}')")" "0|" "fresh work (open, unassigned): passes"
eq "$(run "$(row '{"status":"open","metadata":{}}')")" "0|" "open with no assignee at all: passes"
eq "$(run "$(row '{"status":"open","assignee":"","metadata":{"branch":"polecat/tk-work"}}')")" "0|" "rework child (open, branch set, no merge_result): passes"
for self in "$SELF_NAME" "$SELF_ID" "$SELF_AGENT" "$SELF_ALIAS"; do
  eq "$(run "$(row "{\"status\":\"in_progress\",\"assignee\":\"$self\",\"metadata\":{}}")")" "0|" "in_progress under this session's '$self': passes"
done
eq "$(FAKE_SESSIONS="$SESS_EMPTY" run "$(row '{"status":"in_progress","assignee":"hq-dead","metadata":{}}')")" "0|" \
   "in_progress under an owner no session list names: passes, the work is ours to take over"

# --- 2. Nobody decides. ----------------------------------------------------------
eq "$(run "$(row "{\"status\":\"open\",\"assignee\":\"$REFINERY\",\"metadata\":{}}")")" "$DONE_NOBODY" "completed handoff: cancels with nothing asked"
has "$(cat "$TMP/update")" 'already handed off' "handoff: the note names it"
has "$(cat "$TMP/update")" 'run cancelled with nothing asked' "handoff: the note records the cancel"
has "$(cat "$TMP/cancel")" '--step mol-polecat-work.load-context' "the cancel names this step"
has "$(cat "$TMP/cancel")" 'duplicate dispatch (work finished)' "handoff: the reason reads as a duplicate of finished work"
eq "$(asked)" '' "handoff: nothing asked"

eq "$(run "$(row '{"status":"open","assignee":"","metadata":{"merge_result":"pull_request"}}')")" "$DONE_NOBODY" "merge_result with no assignee: cancels with nothing asked"
has "$(cat "$TMP/cancel")" 'merge_result=pull_request' "merge_result: the reason names the stamp"
eq "$(asked)" '' "merge_result: nothing asked"

eq "$(run "$(row '{"status":"closed","assignee":"","metadata":{}}')")" "$DONE_NOBODY" "closed and unowned: cancels with nothing asked"
has "$(cat "$TMP/update")" 'Closed before claim; run cancelled with nothing asked' "closed: the note has its own label"
no "$(cat "$TMP/update")" 'Duplicate dispatch' "closed: the note does not call it a duplicate"
has "$(cat "$TMP/cancel")" 'closed before claim: tk-work already closed' "closed: the reason names the close"
no "$(cat "$TMP/cancel")" 'duplicate dispatch' "closed: the reason does not call it a duplicate"
eq "$(asked)" '' "closed: nothing asked"
for self in "$SELF_NAME" "$REFINERY"; do
  eq "$(run "$(row "{\"status\":\"closed\",\"assignee\":\"$self\",\"metadata\":{}}")")" "$DONE_NOBODY" "closed under '$self': cancels with nothing asked"
done
eq "$(FAKE_SESSIONS="$SESS_OTHER" run "$(row '{"status":"closed","assignee":"hq-other","metadata":{}}')")" "$DONE_NOBODY" "closed under a live owner: finished, the liveness read does not apply"

run "$(row '{"status":"closed","assignee":"","close_reason":"duplicate of tk-twin:\n  landed there first","metadata":{"gc.superseded_by":"tk-twin","gc.outcome":"duplicate"}}')" >/dev/null
has "$(cat "$TMP/cancel")" 'superseded by tk-twin' "closed: the reason names what superseded it"
has "$(cat "$TMP/cancel")" 'outcome duplicate' "closed: the reason names gc.outcome"
has "$(cat "$TMP/cancel")" 'close reason: duplicate of tk-twin: landed there first' "closed: the close reason rides on one line"
LONG="$(printf 'r%.0s' $(seq 1 260))"
run "$(row "{\"status\":\"closed\",\"close_reason\":\"$LONG\",\"metadata\":{}}")" >/dev/null
has "$(cat "$TMP/cancel")" "close reason: $(printf 'r%.0s' $(seq 1 200)))" "closed: a long close reason is cut to 200 characters"
no "$(cat "$TMP/cancel")" "$(printf 'r%.0s' $(seq 1 201))" "closed: nothing past the 200th character survives"
run "$(row '{"status":"closed","metadata":{"merge_result":"merged"}}')" >/dev/null
has "$(cat "$TMP/cancel")" 'merge_result=merged' "closed with a merge_result: the stamp is the reason"
no "$(cat "$TMP/cancel")" 'closed before claim' "closed with a merge_result: the stamp wins over the bare close"

eq "$(FAKE_SESSIONS="$SESS_OTHER" run "$(row '{"status":"in_progress","assignee":"hq-other","metadata":{}}')")" "$DONE_NOBODY" "in_progress under a live owner: cancels with nothing asked"
has "$(cat "$TMP/update")" 'Duplicate dispatch refused; run cancelled' "live owner: the note names the duplicate"
has "$(cat "$TMP/cancel")" 'duplicate dispatch: tk-work already in_progress under live hq-other' "live owner: the reason names the owner"
eq "$(asked)" '' "live owner: nothing asked"
eq "$(FAKE_SESSIONS='' run "$(row '{"status":"in_progress","assignee":"hq-other","metadata":{}}')")" "$DONE_NOBODY" "a session list that cannot be read proves nobody gone"
eq "$(FAKE_SESSIONS="$SESS_OTHER" run "$(row '{"status":"in_progress","assignee":"hq-other","metadata":{"merge_result":"pull_request"}}')")" "$DONE_NOBODY" "live owner with a merge_result: still the live duplicate"
has "$(cat "$TMP/cancel")" 'under live hq-other' "live owner with a merge_result: the owner is the reason"

# --- 3. A person decides. --------------------------------------------------------
for st in blocked deferred hooked pinned; do
  eq "$(FAKE_SESSIONS="$SESS_REAL" run "$(row "{\"status\":\"$st\",\"assignee\":\"\",\"metadata\":{}}")")" "$DONE_PERSON" "parked ($st): files a gate, cancels"
done
eq "$(run "$(row "{\"status\":\"blocked\",\"assignee\":\"$SELF_AGENT\",\"metadata\":{}}")")" "$DONE_PERSON" "parked under this session: not built"
eq "$(run "$(row "{\"status\":\"deferred\",\"assignee\":\"$REFINERY\",\"metadata\":{}}")")" "$DONE_PERSON" "parked under another assignee: files a gate"
eq "$(run "$(row '{"status":"blocked","metadata":{"merge_result":"pull_request"}}')")" "$DONE_NOBODY" "parked with a merge_result: finished, nothing asked"
run "$(row '{"status":"deferred","assignee":"","metadata":{}}')" >/dev/null
has "$(cat "$TMP/gate")" '--subject tk-work --key polecat-parked-work' "parked: the gate blocks the work under its own key"
has "$(cat "$TMP/gate")" 'tk-work is deferred' "parked: the gate names the status"
has "$(cat "$TMP/gate")" 'Nothing re-slings it when it is released' "parked: the gate says the release needs a re-sling"
has "$(cat "$TMP/gate")" 'gc sling <pool> tk-work --on mol-polecat-work' "parked: and names it"
no "$(cat "$TMP/gate")" '--quiet-window' "parked: the gate declares no quiet window"
has "$(cat "$TMP/update")" 'Parked work bead; run cancelled for a person' "parked: the note names the park"
has "$(cat "$TMP/cancel")" 'parked work bead: tk-work parked (status deferred)' "parked: the reason names the status"

NOTFOUND='{"error":"no issues found matching the provided IDs","schema_version":1}'
eq "$(FAKE_SHOW_OUT="$NOTFOUND" run '')" "1|UPDATE;FINDING;CANCEL;DRAIN;" "a bead the store does not have: files a finding, cancels"
has "$(cat "$TMP/finding")" '--scope polecat-findings --key polecat-unreadable-work.tk-work' "no such bead: the finding has its own key, per bead"
has "$(cat "$TMP/finding")" 'Could not read work bead tk-work' "no such bead: the finding says so"
no "$(cat "$TMP/finding")" 'Duplicate dispatch' "no such bead: the finding claims no duplicate"
eq "$(cat "$TMP/gate")" '' "no such bead: no gate, since a bead nobody can read cannot be blocked"
has "$(cat "$TMP/cancel")" 'unreadable work bead: tk-work unreadable' "no such bead: the reason names it"

eq "$(run '' --bead tk-work --step mol-x.y >/dev/null; grep -c . "$TMP/run-reads")" "0" "an empty row at a direct claim reads no runs"

MANY='{"children":[{"id":"a"},{"id":"b"}]}'
eq "$(FAKE_CONVOY="$MANY" run '')" "1|GATE;CANCEL;DRAIN;" "a convoy that tracks more than one bead: files a gate on the convoy, cancels"
has "$(cat "$TMP/gate")" '--subject cv-1 --key polecat-malformed-convoy' "malformed convoy: the gate blocks the convoy"
has "$(cat "$TMP/cancel")" 'does not have exactly one tracked member' "malformed convoy: the reason says so"

# --- 4. The store. ---------------------------------------------------------------
eq "$(FAKE_SHOW_OUT='' run '')" "1|DRAIN;" "a store that never answers: asks nothing, cancels nothing, drains"
has "$(cat "$TMP/out")" 'The store did not answer' "no answer: says so"
eq "$(FAKE_SHOW_OUT='bd: invalid connection' run '')" "1|DRAIN;" "error text on stdout is no answer"
eq "$(FAKE_SHOW_OUT='' FAKE_SHOW_RC=0 run '')" "1|DRAIN;" "exit 0 with nothing printed is no answer"
eq "$(FAKE_SHOW_OUT="$(row '{"status":"open","metadata":{}}')" FAKE_SHOW_RC=1 run '')" "1|DRAIN;" "a row beside a failed exit is no answer"
eq "$(FAKE_SHOW_OUT='[{"id":"tk-other","status":"open","metadata":{}}]' FAKE_SHOW_RC=0 run '')" "1|DRAIN;" "a row for another bead is no answer"
eq "$(FAKE_CONVOY_DOWN=1 run '')" "1|DRAIN;" "a convoy read the store does not answer: drains and asks nothing"

# A read that fails once and answers on the retry is an answer.
RETRY_ROW="$(row '{"status":"open","assignee":"","metadata":{}}')"
FLAKY_BIN="$TMP/flaky-bin"; mkdir -p "$FLAKY_BIN"
cat > "$FLAKY_BIN/gc" <<GC
#!${BASH:-/usr/bin/env bash}
if [ "\$1 \$2" = "bd show" ]; then
  if [ ! -e "$TMP/flaky.seen" ]; then : > "$TMP/flaky.seen"; exit 1; fi
fi
exec "$TMP/bin/gc" "\$@"
GC
chmod +x "$FLAKY_BIN/gc"
eq "$(PATH="$FLAKY_BIN:$PATH" run "$RETRY_ROW")" "0|" "a read that fails once and answers on the retry: passes"

# --- 5. Fail closed. -------------------------------------------------------------
eq "$(FAKE_FINDING_RC=1 FAKE_SHOW_OUT="$NOTFOUND" run '')" "1|UPDATE;FINDING;" "no such bead, the finding fails: no cancel, no drain"
eq "$(FAKE_GATE_RC=1 run "$(row '{"status":"deferred","metadata":{}}')")" "1|UPDATE;GATE;" "parked, the gate fails: no cancel, no drain"
eq "$(FAKE_CANCEL_RC=1 FAKE_SHOW_OUT="$NOTFOUND" run '')" "1|UPDATE;FINDING;CANCEL;" "no such bead, the cancel fails: no drain"
eq "$(FAKE_CANCEL_RC=1 run "$(row "{\"status\":\"open\",\"assignee\":\"$REFINERY\",\"metadata\":{}}")")" "1|UPDATE;CANCEL;" "finished, the cancel fails: no drain, asks nothing"
eq "$(FAKE_CANCEL_RC=1 FAKE_SESSIONS="$SESS_OTHER" run "$(row '{"status":"in_progress","assignee":"hq-other","metadata":{}}')")" "1|UPDATE;CANCEL;" "live duplicate, the cancel fails: no drain"

OUT="$(FAKE_UPDATE_RC=1 run "$(row '{"status":"closed","assignee":"","metadata":{}}')")"
eq "$OUT" "$DONE_NOBODY" "the refusal note refused: the cancel and drain still run"
has "$(cat "$TMP/out")" 'The refusal note did not land on tk-work' "the refused note is reported"
has "$(cat "$TMP/cancel")" 'already closed' "the cancel reason still records it"
run "$(row '{"status":"closed","assignee":"","metadata":{}}')" >/dev/null
no "$(cat "$TMP/out")" 'did not land' "a note that landed reports nothing"

# --- 6. Another run. -------------------------------------------------------------
run_of() { # <root> <convoy> [<formula>] [<live>]
  jq -nc --arg r "$1" --arg c "$2" --arg f "${3:-mol-polecat-work}" --argjson l "${4:-true}" '{root: $r, convoy: $c, bead: "tk-work", formula: $f, live: $l}'
}
FREE="$(row '{"status":"open","assignee":"","metadata":{}}')"
MINE="$(run_of r-mine cv-1)"; PEER="$(run_of r-peer cv-0)"
OLDER_PEER='[{"id":"r-peer","created_at":"2026-11-01T09:00:00Z"},{"id":"r-mine","created_at":"2026-11-01T10:00:00Z"}]'
YOUNGER_PEER='[{"id":"r-mine","created_at":"2026-11-01T09:00:00Z"},{"id":"r-peer","created_at":"2026-11-01T10:00:00Z"}]'

eq "$(FAKE_RUNS="[$MINE]" run "$FREE")" "0|" "this run alone on the bead: passes, nothing written, and no core helper asked for"
eq "$(cat "$TMP/run-reads")" "runs store_read tk-work" "this run alone: the runs that work the bead are read"
eq "$(cat "$TMP/list")" "" "this run alone: no ages are read"

eq "$(FAKE_RUNS="[$MINE,$PEER]" FAKE_ROOTS="$OLDER_PEER" run "$FREE")" "$DONE_NOBODY" "an older live run: cancels with nothing asked"
has "$(cat "$TMP/update")" "Duplicate dispatch refused; run cancelled" "an older live run: the note names the duplicate"
has "$(cat "$TMP/update")" "in flight in live run r-peer" "an older live run: the note names it"
has "$(cat "$TMP/cancel")" "duplicate dispatch: tk-work in flight in live run r-peer" "an older live run: the reason names it"
eq "$(asked)" "" "an older live run: nothing asked"
eq "$(cat "$TMP/await")" "" "an older live run: this run's work needs no wait"
has "$(cat "$TMP/list")" "--all --include-ephemeral" "the ages are read whatever tier a root is in"
has "$(cat "$TMP/list")" "--id r-mine,r-peer " "the ages are read for those roots"

eq "$(FAKE_RUNS="[$MINE,$PEER]" FAKE_ROOTS="$YOUNGER_PEER" run "$FREE")" "0|" "a younger live run: this run builds it"
SAME='[{"id":"r-mine","created_at":"2026-11-01T09:00:00Z"},{"id":"r-peer","created_at":"2026-11-01T09:00:00Z"}]'
eq "$(FAKE_RUNS="[$MINE,$PEER]" FAKE_ROOTS="$SAME" run "$FREE")" "0|" "the same second: the lower id builds it"
eq "$(FAKE_RUNS="[$(run_of r-zed cv-1),$(run_of r-mine cv-0)]" FAKE_ROOTS='[{"id":"r-zed","created_at":"2026-11-01T09:00:00Z"},{"id":"r-mine","created_at":"2026-11-01T09:00:00Z"}]' run "$FREE")" "$DONE_NOBODY" "the same second: the higher id refuses"
THREE="[$MINE,$PEER,$(run_of r-third cv-2)]"
eq "$(FAKE_RUNS="$THREE" FAKE_ROOTS="$OLDER_PEER" run "$FREE")" "$DONE_NOBODY" "three live runs: this one is not the oldest"
has "$(cat "$TMP/cancel")" "in flight in live run r-peer, r-third" "three live runs: the reason names each"

eq "$(FAKE_RUNS="[$MINE,$(run_of r-peer cv-0 mol-polecat-work false)]" run "$FREE")" "0|" "a run that has ended: passes"
eq "$(cat "$TMP/list")" "" "a run that has ended: no ages are read"
eq "$(FAKE_RUNS="[$MINE,$(run_of r-peer cv-0 mol-review)]" run "$FREE")" "0|" "a live run of another formula: no duplicate, as to gc sling"
eq "$(FAKE_RUNS="[$(run_of r-peer cv-0 mol-other)]" FAKE_ROOTS="$OLDER_PEER" run "$FREE" --convoy cv-1 --formula mol-other)" "$DONE_NOBODY" "the formula the gate is told of is the one it compares"

# Both dispatches read the same rows, whichever reaches the gate first.
dispatch() { # <convoy> <dir>
  mkdir -p "$2"
  printf '%s' "$FREE" > "$2/row.json"
  printf '%s' "[$MINE,$PEER]" > "$2/runs.json"
  ( cd "$TMP" || exit 97
    env GC_SESSION_NAME="$SELF_NAME" GC_SESSION_ID="$SELF_ID" GC_AGENT="$SELF_AGENT" GC_ALIAS="$SELF_ALIAS" \
      WORK_READ_WAIT=0 FAKE_ROW_FILE="$2/row.json" GC_RUN_LIB="$PACK/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$2/runs.json" \
      FAKE_LOG="$2/log" FAKE_CANCEL="$2/cancel" FAKE_SESSIONS="$SESS_EMPTY" FAKE_ROOTS="$YOUNGER_PEER" \
      "$PACK/work-gate.sh" --convoy "$1" >"$2/out" 2>&1
    echo "$?" > "$2/rc" ) &
}
for round in 1 2 3; do
  rm -rf "$TMP/race-a" "$TMP/race-b"
  dispatch cv-1 "$TMP/race-a"; dispatch cv-0 "$TMP/race-b"; wait
  eq "$(cat "$TMP/race-a/rc")$(cat "$TMP/race-b/rc")" "01" "two concurrent dispatches, round $round: exactly the older one builds"
  eq "$(tr '\n' ';' < "$TMP/race-b/log")" "UPDATE;CANCEL;DRAIN;" "two concurrent dispatches, round $round: the other declines as a live duplicate does"
  eq "$(cat "$TMP/race-a/log" 2>/dev/null)" "" "two concurrent dispatches, round $round: the one that builds writes nothing"
done

eq "$(FAKE_RUNS="[$PEER]" run "$FREE" --bead tk-work)" "$DONE_NOBODY" "a direct claim beside a live run: it has no run of its own, so it refuses"
has "$(cat "$TMP/cancel")" "in flight in live run r-peer" "a direct claim beside a live run: the reason names it"
eq "$(cat "$TMP/list")" "" "a direct claim beside a live run: no ages are read"
eq "$(FAKE_RUNS="[$(run_of r-old "")]" run "$FREE" --bead tk-work)" "$DONE_NOBODY" "a direct claim beside a classic molecule, which names no convoy: refuses"
eq "$(FAKE_RUNS='[]' run "$FREE" --bead tk-work)" "0|" "a direct claim with no run on the bead: passes"
eq "$(FAKE_RUNS="[$(run_of r-peer cv-0 mol-review)]" run "$FREE" --bead tk-work)" "0|" "a direct claim beside another formula's run: passes"

eq "$(RUN_LIB_STUB_FAIL=all run "$FREE")" "1|DRAIN;" "the runs cannot be read: asks nothing, cancels nothing, drains"
has "$(cat "$TMP/out")" "could not read the runs that work tk-work" "the runs cannot be read: says so"
eq "$(FAKE_LIST_DOWN=1 FAKE_RUNS="[$MINE,$PEER]" run "$FREE")" "1|DRAIN;" "the ages cannot be read: asks nothing, cancels nothing, drains"
has "$(cat "$TMP/out")" "could not read the age of the runs that work tk-work" "the ages cannot be read: says so"
eq "$(FAKE_ROOTS='[{"id":"r-peer","created_at":"2026-11-01T09:00:00Z"}]' FAKE_RUNS="[$MINE,$PEER]" run "$FREE")" "$DONE_NOBODY" "this run's root is not returned: it cannot be the oldest"
eq "$(FAKE_RUNS="[$MINE,$PEER]" FAKE_ROOTS="$OLDER_PEER" FAKE_CANCEL_RC=1 run "$FREE")" "1|UPDATE;CANCEL;" "an older live run, the cancel fails: no drain"

# Each refusal that comes first reads no runs.
for fields in \
  "{\"status\":\"open\",\"assignee\":\"$REFINERY\",\"metadata\":{}}" \
  '{"status":"closed","metadata":{}}' \
  '{"status":"open","metadata":{"merge_result":"pull_request"}}' \
  '{"status":"deferred","metadata":{}}' \
  '{"status":"open","metadata":{},"dependencies":[{"id":"tk-x","dependency_type":"blocks","status":"open"}]}'; do
  run "$(row "$fields")" >/dev/null
  eq "$(cat "$TMP/run-reads")" "" "no runs read for a bead refused first: $fields"
done
FAKE_SESSIONS="$SESS_OTHER" run "$(row '{"status":"in_progress","assignee":"hq-other","metadata":{}}')" >/dev/null
eq "$(cat "$TMP/run-reads")" "" "no runs read for a live owner"

# --- 7. Waiting. -----------------------------------------------------------------
BLOCKED="$(row '{"status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/pool"},"dependencies":[{"id":"tk-blocker","dependency_type":"blocks","status":"open"},{"id":"tk-b2","dependency_type":"blocks","status":"in_progress"},{"id":"tk-done","dependency_type":"blocks","status":"closed"},{"id":"tk-rel","dependency_type":"related","status":"open"}]}')"
eq "$(run "$BLOCKED")" "1|AWAIT;UPDATE;CANCEL;DRAIN;" "an open blocker: waits on it, notes the arm, cancels, drains"
eq "$(cat "$TMP/await")" "tk-work --blocked-by tk-blocker --formula mol-polecat-work" "an open blocker: the wait names the first blocker and the formula"
has "$(cat "$TMP/update")" "open blocks-blocker(s): tk-blocker tk-b2" "an open blocker: the note names only the open blocks edges"
has "$(cat "$TMP/cancel")" "open blocks-blocker(s) tk-blocker tk-b2" "an open blocker: the reason names them"
eq "$(cat "$TMP/gate")" "" "an open blocker: nothing asked when the arm lands"
eq "$(run "$(row '{"status":"open","metadata":{},"dependencies":[{"id":"tk-x","dependency_type":"blocks","status":"closed"}]}')")" "0|" "a blocker that is closed: passes"
eq "$(run "$(row '{"status":"open","metadata":{},"dependencies":[{"id":"tk-x","dependency_type":"related","status":"open"}]}')")" "0|" "an open dep that is not blocks: passes"
eq "$(FAKE_AWAIT_RC=1 run "$BLOCKED")" "1|AWAIT;GATE;CANCEL;DRAIN;" "the wait does not land: no note claims an arm, a gate asks for the re-sling, then cancels"
has "$(cat "$TMP/gate")" "--subject tk-work --key polecat-blocked-work" "the fallback gate has its own key"
has "$(cat "$TMP/gate")" "re-sling this work once the blocker(s) close" "the fallback gate says what to do"
eq "$(FAKE_AWAIT_RC=1 FAKE_GATE_RC=1 run "$BLOCKED")" "1|AWAIT;GATE;" "neither the wait nor the gate lands: no cancel, no drain"
eq "$(FAKE_CANCEL_RC=1 run "$BLOCKED")" "1|AWAIT;UPDATE;CANCEL;" "the wait landed and the cancel did not: no drain"

# Each name a claim writes as an assignee finds the session that goes by it.
for owner in hq-busy sess-busy rig/rig.polecat-busy rig.polecat-busy; do
  eq "$(FAKE_SESSIONS="$SESS_REAL" run "$(row "{\"status\":\"in_progress\",\"assignee\":\"$owner\",\"metadata\":{}}")")" "$DONE_NOBODY" "in_progress under '$owner', a listed session's name: refused"
done

# --- usage ------------------------------------------------------------------------
OUT="$("$PACK/work-gate.sh" 2>&1)"; eq "$?" "2" "no work named: usage error"
OUT="$("$PACK/work-gate.sh" --convoy a --bead b 2>&1)"; eq "$?" "2" "both named: usage error"
OUT="$("$PACK/work-gate.sh" --nope 2>&1)"; eq "$?" "2" "an unknown flag: usage error"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
