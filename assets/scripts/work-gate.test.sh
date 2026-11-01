#!/usr/bin/env bash
# Hermetic test for assets/scripts/work-gate.sh, load-context's gate.
#
# Two dispatch surfaces can reach one work bead. Before the workspace is touched
# the gate refuses a bead that is gone, parked, in flight under a live owner or in
# a live session's tree, waiting on a blocker, or finished, and takes the work
# when it is free.
#
# What it holds:
#   1. DISCRIMINATION: a no-op on work that is this session's to build.
#   2. NOBODY DECIDES: a finished bead and a live duplicate end the run with
#      nothing asked.
#   3. A PERSON DECIDES: a parked bead and a tree no check clears file a gate
#      first, and a bead the store does not have files a finding.
#   4. THE STORE: a store that does not answer asks nothing and cancels nothing.
#   5. FAIL CLOSED: a part that does not land stops what follows it.
#   6. THE TREE: core's work-holder.sh gets the bead's record and --claim, and its
#      exit decides.
#   7. WAITING: a bead with an open blocker, or whose tree a sibling holds, waits
#      on it and is armed, and a retry after any failure still knows the pool.
#
# The siblings it calls are stubs that log, except decline.sh and work-lib.sh,
# which are the real ones. Core's work-holder.sh is a stub of its documented
# exits. No live city, Dolt or network.
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

PACK="$TMP/pack"; CORE="$TMP/core"
mkdir -p "$TMP/bin" "$PACK" "$CORE"
cp "$HERE/work-gate.sh" "$HERE/work-lib.sh" "$HERE/decline.sh" "$HERE/bd-lib.sh" "$PACK/"

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
cat > "$CORE/work-holder.sh" <<'TREE'
#!/usr/bin/env bash
for a in "$@"; do printf '<%s>' "$a"; done >> "${FAKE_TREE_ARGS:-/dev/null}"
printf '\n' >> "${FAKE_TREE_ARGS:-/dev/null}"
[ -z "${FAKE_TREE_OUT:-}" ] || printf '%s\n' "$FAKE_TREE_OUT"
[ -z "${FAKE_TREE_AFTER_ROW:-}" ] || printf '%s' "$FAKE_TREE_AFTER_ROW" > "$FAKE_ROW_FILE"
exit "${FAKE_TREE_RC:-0}"
TREE
chmod +x "$CORE/work-holder.sh"

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "core scripts-dir") [ -n "${FAKE_CORE:-}" ] || exit 1; printf '%s\n' "$FAKE_CORE"; exit 0 ;;
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
  "bd list") printf '%s' "${FAKE_BEADS:-[]}"; exit 0 ;;
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
  : > "$TMP/log"; : > "$TMP/update"; : > "$TMP/cancel"; : > "$TMP/await"; : > "$TMP/gate"; : > "$TMP/finding"; : > "$TMP/tree-args"
  printf '%s' "$1" > "$TMP/row.json"
  shift
  local rc=0
  [ "$#" -gt 0 ] || set -- --convoy cv-1
  ( cd "$TMP" || exit 97
    GC_SESSION_NAME="$SELF_NAME" GC_SESSION_ID="$SELF_ID" GC_AGENT="$SELF_AGENT" GC_ALIAS="$SELF_ALIAS" \
    WORK_READ_WAIT=0 FAKE_ROW_FILE="$TMP/row.json" FAKE_CORE="${FAKE_CORE-$CORE}" \
    FAKE_LOG="$TMP/log" FAKE_UPDATE="$TMP/update" FAKE_CANCEL="$TMP/cancel" FAKE_AWAIT="$TMP/await" FAKE_GATE="$TMP/gate" FAKE_FINDING="$TMP/finding" \
    FAKE_SESSIONS="${FAKE_SESSIONS-$SESS_EMPTY}" FAKE_TREE_ARGS="$TMP/tree-args" \
      "$PACK/work-gate.sh" "$@" ) > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}
asked() { cat "$TMP/gate" "$TMP/finding"; }
DONE_NOBODY="1|UPDATE;CANCEL;DRAIN;"
DONE_PERSON="1|UPDATE;GATE;CANCEL;DRAIN;"
DONE_WAIT="1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;"

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

eq "$(run '' --bead tk-work --step mol-x.y >/dev/null; cat "$TMP/tree-args" | grep -c .)" "0" "an empty row at a direct claim runs no tree check"

MANY='{"children":[{"id":"a"},{"id":"b"}]}'
eq "$(FAKE_CONVOY="$MANY" run '')" "1|GATE;CANCEL;DRAIN;" "a convoy that tracks more than one bead: files a gate on the convoy, cancels"
has "$(cat "$TMP/gate")" '--subject cv-1 --key polecat-malformed-convoy' "malformed convoy: the gate blocks the convoy"
has "$(cat "$TMP/cancel")" 'does not have exactly one tracked member' "malformed convoy: the reason says so"

# --- 4. The store. ---------------------------------------------------------------
eq "$(FAKE_SHOW_OUT='' run '')" "1|DRAIN;" "a store that never answers: asks nothing, cancels nothing, drains"
has "$(cat "$TMP/out")" 'The store did not answer' "no answer: says so"
eq "$(FAKE_SHOW_OUT='bd: invalid connection' run '')" "1|DRAIN;" "error text on stdout is no answer"
eq "$(FAKE_SHOW_OUT='' FAKE_SHOW_RC=0 run '')" "1|DRAIN;" "exit 0 with nothing printed is no answer"
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

# --- 6. The tree. ----------------------------------------------------------------
eq "$(run "$(row '{"status":"open","assignee":"","metadata":{}}')")" "0|" "fresh work the holder check clears: passes"
eq "$(cat "$TMP/tree-args")" "<--claim><--bead><tk-work><--work-dir><><--holder><><--branch><>" "fresh work: the check gets --claim and an empty record"
run "$(row '{"status":"open","assignee":"","metadata":{"branch":"polecat/tk-anchor","work_dir":"/w/p/worktrees/tk-work","work_holder":"sess-gone"}}')" >/dev/null
eq "$(cat "$TMP/tree-args")" "<--claim><--bead><tk-work><--work-dir></w/p/worktrees/tk-work><--holder><sess-gone><--branch><polecat/tk-anchor>" "rework child: the check gets the recorded tree, holder and branch"

run "$(row "{\"status\":\"open\",\"assignee\":\"$REFINERY\",\"metadata\":{}}")" >/dev/null
eq "$(cat "$TMP/tree-args")" "" "completed handoff: no tree check"
run "$(row '{"status":"closed","metadata":{}}')" >/dev/null
eq "$(cat "$TMP/tree-args")" "" "closed: no tree check"
run "$(row '{"status":"open","metadata":{"merge_result":"pull_request"}}')" >/dev/null
eq "$(cat "$TMP/tree-args")" "" "merge_result: no tree check"
run "$(row '{"status":"deferred","metadata":{}}')" >/dev/null
eq "$(cat "$TMP/tree-args")" "" "parked: no tree check"
FAKE_SESSIONS="$SESS_OTHER" run "$(row '{"status":"in_progress","assignee":"hq-other","metadata":{}}')" >/dev/null
eq "$(cat "$TMP/tree-args")" "" "live owner: no tree check"

eq "$(FAKE_TREE_OUT="$TMP/x is yours to adopt" run "$(row '{"status":"open","metadata":{"work_dir":"/w/x"}}')")" "0|" "an adoptable tree: passes"
has "$(cat "$TMP/out")" "is yours to adopt" "an adoptable tree: the finding is printed"

# Another run of this bead: its own record names the live holder.
HELD="tk-work records live hq-peer as the holder of worktree /w/p (uncommitted paths: 2)"
eq "$(FAKE_TREE_RC=1 FAKE_TREE_OUT="$HELD" run "$(row '{"status":"open","assignee":"","metadata":{"work_dir":"/w/p","work_holder":"hq-peer"}}')")" "$DONE_NOBODY" "a live holder on this bead: cancels with nothing asked"
has "$(cat "$TMP/update")" "in flight in another session's tree: $HELD" "live holder: the note carries the finding"
has "$(cat "$TMP/cancel")" "duplicate dispatch: tk-work in flight in another session's tree: $HELD" "live holder: the reason carries the finding"
eq "$(asked)" '' "live holder: nothing asked"
eq "$(cat "$TMP/await")" '' "live holder: this run's work needs no wait"

# A compare-and-set that conflicts finds a holder the first read did not hold, so
# the bead is read again.
AFTER="$(row '{"status":"open","assignee":"","metadata":{"work_holder":"hq-peer"}}')"
eq "$(FAKE_TREE_RC=1 FAKE_TREE_OUT="$HELD" FAKE_TREE_AFTER_ROW="$AFTER" run "$(row '{"status":"open","assignee":"","metadata":{}}')")" "$DONE_NOBODY" \
   "a conflict on this bead's holder: the second dispatch cancels with nothing asked"

# Undecided.
UNDECIDED="polecat/tk-work is checked out in worktree /w/elsewhere (uncommitted paths: 0), which no unclosed bead records"
eq "$(FAKE_TREE_RC=2 FAKE_TREE_OUT="$UNDECIDED" run "$(row '{"status":"open","metadata":{"branch":"polecat/tk-work"}}')")" "$DONE_WAIT" "a tree the check cannot clear: files a gate, waits, cancels"
has "$(cat "$TMP/gate")" "--subject tk-work --key polecat-duplicate-dispatch" "undecided: the gate blocks the work under its key"
has "$(cat "$TMP/gate")" "Possible duplicate dispatch on tk-work: it is possibly in flight in another session's tree: $UNDECIDED" "undecided: the gate names the tree"
has "$(cat "$TMP/gate")" "Check the tree" "undecided: the gate says how to release it"
has "$(cat "$TMP/gate")" "clearing it re-slings tk-work" "undecided: the gate says clearing it re-slings"
no "$(cat "$TMP/gate")" "--quiet-window" "undecided: the gate a wait follows declares no quiet window"
eq "$(cat "$TMP/await")" "tk-work --key polecat-duplicate-dispatch --formula mol-polecat-work" "undecided: the work waits under the key, with no owner named"
has "$(cat "$TMP/cancel")" "duplicate dispatch: tk-work possibly in flight in another session's tree: $UNDECIDED" "undecided: the reason carries the finding"

eq "$(FAKE_TREE_RC=127 run "$(row '{"status":"open","metadata":{}}')")" "$DONE_WAIT" "a check that dies with no finding: fails closed"
has "$(cat "$TMP/cancel")" "work-holder.sh exited 127 with no finding" "a dead check: the reason says what failed"
eq "$(FAKE_CORE='' run "$(row '{"status":"open","metadata":{}}')")" "$DONE_WAIT" "no core pack to ask: fails closed"
has "$(cat "$TMP/gate")" "gc core scripts-dir did not name a directory holding it" "no core pack: the gate says why"
eq "$(FAKE_CORE="$TMP/nowhere" run "$(row '{"status":"open","metadata":{}}')")" "$DONE_WAIT" "a core pack without the script: fails closed"

eq "$(FAKE_GATE_RC=1 FAKE_TREE_RC=2 FAKE_TREE_OUT="$UNDECIDED" run "$(row '{"status":"open","metadata":{}}')")" "1|UPDATE;GATE;" "undecided, the gate fails: no wait, no cancel, no drain"
eq "$(FAKE_AWAIT_RC=1 FAKE_TREE_RC=2 FAKE_TREE_OUT="$UNDECIDED" run "$(row '{"status":"open","metadata":{}}')")" "1|UPDATE;GATE;AWAIT;" "undecided, the wait fails: no cancel, no drain"
eq "$(FAKE_CANCEL_RC=1 FAKE_TREE_RC=2 FAKE_TREE_OUT="$UNDECIDED" run "$(row '{"status":"open","metadata":{}}')")" "1|UPDATE;GATE;AWAIT;CANCEL;" "undecided, the cancel fails: no drain"

# --- 7. Waiting. -----------------------------------------------------------------
BLOCKED="$(row '{"status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/pool"},"dependencies":[{"id":"tk-blocker","dependency_type":"blocks","status":"open"},{"id":"tk-b2","dependency_type":"blocks","status":"in_progress"},{"id":"tk-done","dependency_type":"blocks","status":"closed"},{"id":"tk-rel","dependency_type":"related","status":"open"}]}')"
eq "$(run "$BLOCKED")" "1|UPDATE;AWAIT;CANCEL;DRAIN;" "an open blocker: notes, waits on it, cancels, drains"
eq "$(cat "$TMP/await")" "tk-work --blocked-by tk-blocker --formula mol-polecat-work" "an open blocker: the wait names the first blocker and the formula"
has "$(cat "$TMP/update")" "open blocks-blocker(s): tk-blocker tk-b2" "an open blocker: the note names only the open blocks edges"
has "$(cat "$TMP/cancel")" "open blocks-blocker(s) tk-blocker tk-b2" "an open blocker: the reason names them"
eq "$(cat "$TMP/gate")" "" "an open blocker: nothing asked when the arm lands"
eq "$(cat "$TMP/tree-args")" "" "an open blocker: the tree check does not run, so a blocked rework never meets its sibling's tree"
eq "$(run "$(row '{"status":"open","metadata":{},"dependencies":[{"id":"tk-x","dependency_type":"blocks","status":"closed"}]}')")" "0|" "a blocker that is closed: passes"
eq "$(run "$(row '{"status":"open","metadata":{},"dependencies":[{"id":"tk-x","dependency_type":"related","status":"open"}]}')")" "0|" "an open dep that is not blocks: passes"
eq "$(FAKE_AWAIT_RC=1 run "$BLOCKED")" "1|UPDATE;AWAIT;GATE;CANCEL;DRAIN;" "the wait does not land: a gate asks for the re-sling, then cancels"
has "$(cat "$TMP/gate")" "--subject tk-work --key polecat-blocked-work" "the fallback gate has its own key"
has "$(cat "$TMP/gate")" "re-sling this work once the blocker(s) close" "the fallback gate says what to do"
eq "$(FAKE_AWAIT_RC=1 FAKE_GATE_RC=1 run "$BLOCKED")" "1|UPDATE;AWAIT;GATE;" "neither the wait nor the gate lands: no cancel, no drain"
eq "$(FAKE_CANCEL_RC=1 run "$BLOCKED")" "1|UPDATE;AWAIT;CANCEL;" "the wait landed and the cancel did not: no drain"

# A sibling holds the tree: different work, so this bead waits on it.
SIBLING_ROWS='[{"id":"tk-work","metadata":{"branch":"polecat/tk-anchor"}},{"id":"tk-anchor","metadata":{"branch":"polecat/tk-anchor","work_holder":"hq-gone"}},{"id":"tk-mine","metadata":{"branch":"polecat/tk-anchor","work_holder":"sess-me"}},{"id":"tk-sib","metadata":{"branch":"polecat/tk-anchor","work_holder":"hq-peer","work_dir":"/w/p/worktrees/tk-sib"}}]'
SESS_PEER='{"sessions":[{"session_name":"hq-peer"}]}'
REWORK="$(row '{"status":"open","assignee":"","metadata":{"branch":"polecat/tk-anchor"}}')"
HELD_SIB="tk-sib records live hq-peer as the holder of worktree /w/p/worktrees/tk-sib (uncommitted paths: 0)"
eq "$(FAKE_SESSIONS="$SESS_PEER" FAKE_TREE_RC=1 FAKE_TREE_OUT="$HELD_SIB" FAKE_BEADS="$SIBLING_ROWS" run "$REWORK")" "1|AWAIT;UPDATE;CANCEL;DRAIN;" "a sibling holds the tree: waits on it, notes it, cancels, drains"
eq "$(cat "$TMP/await")" "tk-work --blocked-by tk-sib --formula mol-polecat-work" "a sibling holds the tree: the wait names the live one, past a gone holder and this session"
has "$(cat "$TMP/update")" "Yielded behind sibling tk-sib on polecat/tk-anchor" "a sibling holds the tree: the note says so"
has "$(cat "$TMP/cancel")" "waits on sibling tk-sib" "a sibling holds the tree: the reason says so"
eq "$(cat "$TMP/gate")" "" "a sibling holds the tree: nothing asked"
eq "$(FAKE_SESSIONS="$SESS_PEER" FAKE_AWAIT_RC=1 FAKE_TREE_RC=1 FAKE_TREE_OUT="$HELD_SIB" FAKE_BEADS="$SIBLING_ROWS" run "$REWORK")" "1|AWAIT;UPDATE;GATE;AWAIT;" \
   "the wait on the sibling does not land: a person looks at the tree, and no wait means no cancel"
eq "$(FAKE_TREE_RC=1 FAKE_TREE_OUT="$HELD_SIB" FAKE_BEADS='[]' run "$REWORK")" "$DONE_WAIT" "a live holder nobody's record names: a person looks at the tree"

# --- usage ------------------------------------------------------------------------
OUT="$("$PACK/work-gate.sh" 2>&1)"; eq "$?" "2" "no work named: usage error"
OUT="$("$PACK/work-gate.sh" --convoy a --bead b 2>&1)"; eq "$?" "2" "both named: usage error"
OUT="$("$PACK/work-gate.sh" --nope 2>&1)"; eq "$?" "2" "an unknown flag: usage error"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
