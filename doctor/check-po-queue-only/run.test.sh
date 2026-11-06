#!/usr/bin/env bash
# Hermetic test for doctor/check-po-queue-only. Stubs gc and bd, which answer
# the way bd does (a route or an assignee filter, closed beads left out), and
# run-lib.sh's verbs (run-lib.stub.sh); no city, no network. Covers:
#   - a clean city passes, and the reads ask for the right things: the route
#     to the po's qualified name with ephemeral rows included, the seat's
#     sessions by its template, and one assignee query over the po's alias,
#     its session's id and runtime name, and the earlier alias its mailbox
#     names; a decoy agent whose name only ends in "po" is not the po;
#   - each arm fails on its fixture: a bead routed to the po, a bead assigned
#     to its alias, to its session id, to its session's runtime name or to an
#     earlier alias, a run poured to the seat (one finding naming the root and
#     each routed step, and not a step routed elsewhere), unread mail from any
#     sender (a sender of human named as such), a queued bead carrying
#     anchor_bead, one carrying a landing state, one carrying an arm, one
#     carrying an assignee, and one a live run works, and the lift a remedy
#     names removes each spelling of the hold the bead carries;
#   - what is not a finding: a held bead routed or assigned to the po, under
#     either hold label and any spelling Gas City reads, read mail, a closed
#     bead, a queued bead whose only mark is a branch, and a queued bead whose
#     run has ended;
#   - the queue in both shapes `gc beads list` prints;
#   - a city with no po: only the queue is judged, and no store is searched;
#   - a suspended rig's store is never read, and its queued beads are named;
#   - fail-closed: an unreadable agent list, rig list, queue (a failed read and
#     a payload in neither shape), session list (both ways), mailbox, route
#     listing, assignee query or run map warns, and each address the other
#     reads give is still searched; a queued bead no single rig's prefix names
#     warns;
#   - a raw control byte in a mail subject stays on one line, and the scratch
#     tree is removed on exit.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-po-queue-only-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }
# line_of <text> <needle> — the one detail line carrying <needle>.
line_of() { printf '%s\n' "$1" | grep -F -- "$2" | head -n1 || true; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/rt" "$TMP/town" "$TMP/alpha" "$TMP/cold"

cat > "$TMP/rigs.json" <<EOF
{"rigs":[
  {"name":"town","path":"$TMP/town","prefix":"hq","hq":true,"suspended":false},
  {"name":"alpha","path":"$TMP/alpha","prefix":"al","suspended":false},
  {"name":"cold","path":"$TMP/cold","prefix":"co","suspended":true}]}
EOF
cat > "$TMP/agents.json" <<'EOF'
{"city_path":"/nowhere","agents":[
  {"name":"po","qualified_name":"gc-toolkit.po","scope":"city"},
  {"name":"repo","qualified_name":"gc-toolkit.repo","scope":"city"},
  {"name":"mechanik","qualified_name":"gc-toolkit.mechanik","scope":"city"},
  {"name":"polecat","qualified_name":"alpha/gc-toolkit.polecat","scope":"rig"}]}
EOF
cat > "$TMP/agents-nopo.json" <<'EOF'
{"city_path":"/nowhere","agents":[{"name":"mechanik","qualified_name":"gc-toolkit.mechanik","scope":"city"}]}
EOF
INBOX_CLEAN='{"schema_version":"1","ok":true,"recipient":"gc-toolkit.po","recipients":["gc-toolkit.po","hq-sess1","gc-toolkit.prior-po"],"messages":null}'
cat > "$TMP/sessions.json" <<'EOF'
{"schema_version":"1","ok":true,"sessions":[
  {"id":"hq-sess1","name":"gc-toolkit.po","template":"gc-toolkit.po","alias":"gc-toolkit.po","agent_name":"gc-toolkit.po","session_name":"gc-toolkit__po","state":"asleep","closed":false},
  {"id":"hq-sess9","name":"gc-toolkit.mechanik","template":"gc-toolkit.mechanik","alias":"gc-toolkit.mechanik","agent_name":"gc-toolkit.mechanik","session_name":"gc-toolkit__mechanik","state":"active","closed":false}]}
EOF

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "agent list") rc="${AGENTS_RC:-0}"; [ "$rc" -eq 0 ] || { echo "agent list: controller down" >&2; exit "$rc"; }; cat "$AGENTS_JSON" ;;
  "rig list")   rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || { echo "rig list: no city" >&2; exit "$rc"; }; cat "$RIGS_JSON" ;;
  "beads list") rc="${QUEUE_RC:-0}"; [ "$rc" -eq 0 ] || { echo "beads list: a store did not answer" >&2; exit "$rc"; }
                printf '%s\n' "$*" >> "$GC_LOG"; cat "$QUEUE_JSON" ;;
  "mail inbox") rc="${INBOX_RC:-0}"; [ "$rc" -eq 0 ] || { echo "gc mail inbox: mail store unreachable" >&2; exit "$rc"; }
                printf '%s\n' "$*" >> "$GC_LOG"; cat "$INBOX_JSON" ;;
  "session list") rc="${SESSIONS_RC:-0}"; [ "$rc" -eq 0 ] || { echo "gc session list: listing sessions: store down" >&2; exit "$rc"; }
                printf '%s\n' "$*" >> "$GC_LOG"
                # --template keeps the rows whose template it names, as gc does.
                t=""; prev=""; for a in "$@"; do [ "$prev" = --template ] && t="$a"; prev="$a"; done
                jq -c --arg t "$t" 'if (.sessions | type) == "array" and $t != "" then .sessions |= map(select(.template == $t)) else . end' "$SESSIONS_JSON" ;;
  "bd "*) shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
# Reached only through gc bd. Answers a route listing and an assignee query from
# the store's file the way bd does: the filter applied, closed beads left out.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; shift
db=""; field=""; expr=""; prev=""
for a in "$@"; do
    case "$prev" in
        --db) db="$a" ;;
        --metadata-field) field="$a" ;;
        --limit) ;;
        *) case "$a" in -*) ;; *) [ "$sub" = query ] && expr="$a" ;; esac ;;
    esac
    prev="$a"
done
name=$(basename "$(dirname "$db")")
printf '%s %s %s\n' "$name" "$sub" "$*" >> "$BD_LOG"
[ "$name" = cold ] && { echo "stub bd: read the suspended rig's store" >&2; exit 99; }
if [ "$name" = "${BD_FAIL_STORE:-}" ] && { [ -z "${BD_FAIL_SUB:-}" ] || [ "$sub" = "$BD_FAIL_SUB" ]; }; then
    echo "bd: the $name store is down" >&2; exit 3
fi
f="$STORES/$name.json"; [ -f "$f" ] || { printf '[]'; exit 0; }
case "$sub" in
  list)  jq -c --arg k "${field%%=*}" --arg v "${field#*=}" \
            '[ .[] | select((.status // "open") != "closed" and ((.metadata // {})[$k] // "") == $v) ]' "$f" ;;
  query) vals=$(printf '%s' "$expr" | grep -oE 'assignee="[^"]*"' | sed -e 's/^assignee="//' -e 's/"$//' | jq -R . | jq -sc .)
         jq -c --argjson vals "$vals" \
            '[ .[] | select((.status // "open") != "closed" and ((.assignee // "") as $a | $a != "" and ($vals | index($a)) != null)) ]' "$f" ;;
  *) printf '[]' ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"

store()   { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.json"; }
queue()   { local IFS=,; printf '[%s]' "$*" > "$TMP/queue.json"; }
runs()    { local IFS=,; printf '[%s]' "$*" > "$TMP/runs.json"; }
inbox()   { printf '%s' "$1" > "$TMP/inbox.json"; }
reset()   { rm -f "$TMP/stores/"*.json "$TMP/bd.log" "$TMP/gc.log"; queue; runs; inbox "$INBOX_CLEAN"; }

# Every run makes its scratch tree under $TMP/rt, so the last case can tell
# whether any run left one behind.
run_check() {
    : > "$TMP/bd.log"; : > "$TMP/gc.log"
    AGENTS_JSON="${AGENTS_JSON:-$TMP/agents.json}" RIGS_JSON="$TMP/rigs.json" \
    QUEUE_JSON="${QUEUE_JSON:-$TMP/queue.json}" INBOX_JSON="$TMP/inbox.json" \
    SESSIONS_JSON="${SESSIONS_JSON:-$TMP/sessions.json}" \
    STORES="$TMP/stores" BD_LOG="$TMP/bd.log" GC_LOG="$TMP/gc.log" \
    GC_RUN_LIB="$HERE/../../assets/scripts/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$TMP/runs.json" \
    PATH="$TMP/bin:$PATH" TMPDIR="$TMP/rt" GC_CITY_PATH="" GC_CITY="" \
    bash "$CHECK" 2>&1
}

NEW1='{"id":"al-new1","status":"open","issue_type":"task","title":"new work","labels":["hold:mayor"],"metadata":{}}'
NEW2='{"id":"hq-new2","status":"open","issue_type":"bug","title":"new work in the town store","labels":["hold:mayor"],"metadata":{"gc.routed_to":"mayor"}}'
POOL='{"id":"al-pool","status":"open","issue_type":"task","metadata":{"gc.routed_to":"alpha/gc-toolkit.polecat"}}'
OTHER='{"id":"al-other","status":"in_progress","issue_type":"task","assignee":"alpha/gc-toolkit.polecat","metadata":{}}'

# --- 1. a clean city passes, and the reads ask for the right things ---------
reset
store alpha "$POOL" "$OTHER" "$NEW1"
store town "$NEW2"
queue "$NEW1" "$NEW2"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a city where nothing reaches the po but its queue passes"
has "$OUT" "OK: the po receives nothing but its queue" "the pass message is the OK line"
has "$OUT" "2 queued bead(s)" "…and it counts the queue it read"
LOG=$(cat "$TMP/bd.log")
has "$LOG" "alpha list --db $TMP/alpha/.beads --metadata-field gc.routed_to=gc-toolkit.po --include-ephemeral" "the route listing asks for the po's qualified name, ephemeral rows included"
has "$LOG" 'alpha query --db '"$TMP/alpha/.beads"' assignee="gc-toolkit.po" OR assignee="gc-toolkit.prior-po" OR assignee="gc-toolkit__po" OR assignee="hq-sess1" --json' "one assignee query names the po's alias, its earlier alias, its session's runtime name and its session id"
hasnt "$LOG" "gc-toolkit__mechanik" "…and no other seat's session"
has "$LOG" "town list" "the town store is searched too"
hasnt "$LOG" "gc.routed_to=gc-toolkit.repo" "an agent whose name only ends in po is not the po"
has "$(cat "$TMP/gc.log")" "mail inbox gc-toolkit.po --json" "the mailbox is read at the po's address"
has "$(cat "$TMP/gc.log")" "session list --template gc-toolkit.po --json" "the seat's sessions are read by its template"
has "$(cat "$TMP/gc.log")" "beads list --label hold:mayor --format=json" "the queue is read the way the po reads it"

# --- 2. a bead routed to the po ---------------------------------------------
reset
store alpha '{"id":"al-r1","status":"open","issue_type":"task","metadata":{"gc.routed_to":"gc-toolkit.po"}}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "an unheld bead routed to the po is an ERROR"
has "$OUT" "alpha bead al-r1 (open task): routed to gc-toolkit.po, outside the po's queue" "the finding names the store, the bead and the route"
has "$OUT" "gc bd set-state al-r1 hold=mayor --reason" "…and names holding it for the po as a remedy"

# --- 3. a bead assigned to the po's alias ------------------------------------
reset
store town '{"id":"hq-a1","status":"open","issue_type":"bug","assignee":"gc-toolkit.po","metadata":{}}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "an unheld bead assigned to the po's alias is an ERROR"
has "$OUT" "town bead hq-a1 (open bug): assigned to gc-toolkit.po" "the finding names the assignment"

# --- 4. a bead assigned to the po's session bead -----------------------------
reset
store alpha '{"id":"al-a2","status":"in_progress","issue_type":"task","assignee":"hq-sess1","metadata":{}}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bead assigned to the session id the po's mailbox names is an ERROR"
has "$OUT" "alpha bead al-a2 (in_progress task): assigned to hq-sess1" "the finding names the session id"

# --- 4a. a bead assigned to the po's session's runtime name ------------------
reset
store alpha '{"id":"al-a4","status":"open","issue_type":"task","assignee":"gc-toolkit__po","metadata":{}}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bead assigned to the runtime name of the po's session is an ERROR"
has "$OUT" "alpha bead al-a4 (open task): assigned to gc-toolkit__po" "the finding names the session name"

# --- 4b. a bead assigned to an alias the seat had before ----------------------
reset
store town '{"id":"hq-a5","status":"open","issue_type":"task","assignee":"gc-toolkit.prior-po","metadata":{}}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bead assigned to an earlier alias the po's mailbox names is an ERROR"
has "$OUT" "town bead hq-a5 (open task): assigned to gc-toolkit.prior-po" "the finding names the earlier alias"

# --- 5. a run poured to the seat ---------------------------------------------
reset
store alpha \
  '{"id":"al-root","status":"open","issue_type":"task","metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.routed_to":"gc-toolkit.po"}}' \
  '{"id":"al-s1","status":"open","issue_type":"task","metadata":{"gc.step_ref":"mol-x.load-context","gc.root_bead_id":"al-root","gc.routed_to":"gc-toolkit.po"}}' \
  '{"id":"al-s2","status":"open","issue_type":"task","metadata":{"gc.step_ref":"mol-x.implement","gc.root_bead_id":"al-root","gc.routed_to":"gc-toolkit.po"}}' \
  '{"id":"al-ctl","status":"open","issue_type":"task","metadata":{"gc.step_ref":"mol-x.finalize","gc.root_bead_id":"al-root","gc.routed_to":"core.control-dispatcher"}}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a run poured to the po is an ERROR"
has "$OUT" "1 finding(s)" "the run is one finding"
has "$OUT" "alpha: run al-root sends the po work:" "the finding names the run's root"
has "$OUT" "al-root (the root, routed to gc-toolkit.po)" "…the root itself"
has "$OUT" "al-s1 (mol-x.load-context, routed to gc-toolkit.po)" "…each step routed to the po, by its step ref"
has "$OUT" "al-s2 (mol-x.implement, routed to gc-toolkit.po)" "…every one of them"
hasnt "$OUT" "al-ctl" "a step routed elsewhere is not named"
has "$OUT" "assets/scripts/run-cancel.sh --root al-root" "the remedy cancels the run"

# --- 6. a held bead reaches no seat ------------------------------------------
reset
HR='{"id":"al-h1","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"gc.routed_to":"gc-toolkit.po"}}'
HS='{"id":"al-h2","status":"open","issue_type":"task","labels":[" Hold:Mayor "],"metadata":{"gc.routed_to":"gc-toolkit.po"}}'
HX='{"id":"al-h3","status":"open","issue_type":"task","assignee":"gc-toolkit.po","labels":["hold:external"],"metadata":{}}'
store alpha "$HR" "$HS" "$HX"
queue "$HR"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a held bead routed or assigned to the po is not a finding"
hasnt "$OUT" "al-h2" "…under any spelling Gas City reads as the hold"
hasnt "$OUT" "al-h3" "…or under hold:external"

# --- 7. read mail, a closed bead -------------------------------------------
reset
store town \
  '{"id":"hq-wisp-m0","status":"open","issue_type":"message","assignee":"gc-toolkit.po","metadata":{}}' \
  '{"id":"hq-c1","status":"closed","issue_type":"task","assignee":"gc-toolkit.po","metadata":{"gc.routed_to":"gc-toolkit.po"}}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a message bead and a closed bead are not findings"
hasnt "$OUT" "hq-wisp-m0" "read mail is the mailbox's, not an assignment"

# --- 8. unread mail, from any sender -----------------------------------------
reset
inbox '{"schema_version":"1","ok":true,"recipient":"gc-toolkit.po","recipients":["gc-toolkit.po","hq-sess1"],"messages":[
  {"id":"hq-wisp-m1","from":"gc-toolkit/gc-toolkit.witness","to":"gc-toolkit.po","subject":"HELP: stuck","body":"x","read":false},
  {"id":"hq-wisp-m2","from":"human","to":"gc-toolkit.po","subject":"nightly report","body":"y","read":false}]}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "unread mail to the po is an ERROR"
has "$OUT" "2 finding(s)" "each message is a finding"
M1=$(line_of "$OUT" "hq-wisp-m1")
has "$M1" "unread mail hq-wisp-m1 to the po (gc-toolkit.po) from gc-toolkit/gc-toolkit.witness: \"HELP: stuck\"" "the finding names the sender and the subject"
has "$M1" "gc mail archive hq-wisp-m1" "…and archiving it once the sender is answered"
hasnt "$M1" "A sender of human" "an agent sender gets no note about human"
has "$(line_of "$OUT" "hq-wisp-m2")" "A sender of human is any caller with no session identity" "mail from human is a finding too, and says who human can be"

# --- 9. a queued bead that is not new work -----------------------------------
reset
queue '{"id":"al-q1","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"anchor_bead":"al-anchor"}}' \
      '{"id":"al-q2","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"merge_result":"pending"}}' \
      '{"id":"al-q3","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"branch":"polecat/al-q3"}}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a queued bead that is not new work is an ERROR"
has "$OUT" "queued bead al-q1 carries anchor_bead=al-anchor" "PR-finishing work in the queue is named"
has "$OUT" "gc bd update al-q1 --remove-label hold:mayor --db $TMP/alpha/.beads" "…with the lift that takes it out, in its own store"
has "$OUT" "queued bead al-q2 carries a landing state, merge_result=pending" "a landing state in the queue is named"
hasnt "$OUT" "al-q3" "a branch alone is not counted"

# --- 10. a queued bead that something already sends --------------------------
reset
queue '{"id":"al-q4","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"gc.dispatch_when_ready":"alpha/gc-toolkit.polecat"}}' \
      '{"id":"hq-q5","status":"in_progress","issue_type":"task","assignee":"someone","labels":["hold:mayor"],"metadata":{}}' \
      '{"id":"al-q6","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{}}' \
      '{"id":"al-q7","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{}}'
runs '{"root":"al-run1","convoy":"al-cv1","bead":"al-q6","formula":"mol-polecat-work","live":true}' \
     '{"root":"al-run2","convoy":"al-cv2","bead":"al-q7","formula":"mol-polecat-work","live":false}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a queued bead something already sends is an ERROR"
has "$OUT" "queued bead al-q4 is armed for dispatch to alpha/gc-toolkit.polecat" "an arm on a queued bead is named"
has "$OUT" "deferred-dispatch.sh disarm al-q4" "…with the disarm"
has "$OUT" "queued bead hq-q5 is assigned to someone" "an assignee on a queued bead is named"
has "$OUT" "queued bead al-q6 is worked by live run al-run1 (mol-polecat-work)" "a live run working a queued bead is named"
has "$OUT" "gc-helm.sh place al-q6 --under <parent> or --standalone" "…with the placement that finishes it"
hasnt "$OUT" "al-q7" "a run that has ended is not a live run"

# An arm for the validating closer is a wait whose hold was not lifted, so its
# remedy is the lift, never the disarm or a placement that would replace it.
reset
queue '{"id":"al-q8","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"gc.dispatch_when_ready":"alpha/gc-toolkit.polecat","gc.dispatch_when_ready_args":"[\"--on\",\"mol-validate-close\"]"}}' \
      '{"id":"al-q9","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"gc.dispatch_when_ready":"alpha/gc-toolkit.polecat","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]"}}' \
      '{"id":"al-q10","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"gc.dispatch_when_ready":"alpha/gc-toolkit.polecat","gc.dispatch_when_ready_args":"[\"--on=mol-validate-close\"]"}}' \
      '{"id":"al-q11","status":"open","issue_type":"task","labels":["learning","hold:mayor","Hold:Mayor"],"metadata":{"gc.dispatch_when_ready":"alpha/gc-toolkit.polecat","gc.dispatch_when_ready_args":"[\"--on\",\"mol-validate-close\"]"}}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a queued bead armed for its validating closer is an ERROR"
Q8=$(line_of "$OUT" "al-q8")
has "$Q8" "queued bead al-q8 is armed for its validating closer (mol-validate-close) on alpha/gc-toolkit.polecat" "an arm for the validating closer is named as one"
has "$Q8" "gc bd update al-q8 --remove-label hold:mayor --db $TMP/alpha/.beads, and keep the arm" "…with the lift that lets the closer run, in its own store"
hasnt "$Q8" "disarm" "…and no disarm, which would drop the check"
hasnt "$Q8" "gc-helm.sh place" "…and no placement"
Q9=$(line_of "$OUT" "al-q9")
has "$Q9" "queued bead al-q9 is armed for dispatch to alpha/gc-toolkit.polecat" "an arm on another formula keeps the placement remedy"
has "$Q9" "deferred-dispatch.sh disarm al-q9" "…and its disarm"
has "$(line_of "$OUT" "al-q10")" "armed for its validating closer (mol-validate-close)" "the --on=<formula> spelling names the closer too"
# bd removes a label by its exact text, so the lift names each spelling of the
# hold the bead carries, and only those.
has "$(line_of "$OUT" "al-q11")" "gc bd update al-q11 --remove-label hold:mayor --remove-label Hold:Mayor --db $TMP/alpha/.beads, and keep the arm" "the lift removes each spelling of the hold the bead carries"

# --- 11. the queue in the API's shape ----------------------------------------
reset
printf '{"beads":[%s],"_cache_age_s":4}' '{"id":"al-q1","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"anchor_bead":"al-anchor"}}' > "$TMP/queue-api.json"
OUT=$(QUEUE_JSON="$TMP/queue-api.json" run_check); RC=$?
eq "$RC" "2" "the queue read through the API is judged the same way"
has "$OUT" "queued bead al-q1 carries anchor_bead=al-anchor" "…its beads are read out of the envelope"

# --- 12. a city with no po ---------------------------------------------------
reset
store alpha '{"id":"al-r1","status":"open","issue_type":"task","metadata":{"gc.routed_to":"gc-toolkit.po"}}'
OUT=$(AGENTS_JSON="$TMP/agents-nopo.json" run_check); RC=$?
eq "$RC" "0" "with no po configured nothing can reach one"
has "$OUT" "no agent named po is configured in this city" "…and the check says it judged only the queue"
eq "$(grep -cE ' (list|query) ' "$TMP/bd.log")" "0" "no store is searched for a route or an assignment"
hasnt "$(cat "$TMP/gc.log")" "mail inbox" "no mailbox is read"
hasnt "$(cat "$TMP/gc.log")" "session list" "no session list is read"
queue '{"id":"al-q1","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{"anchor_bead":"al-anchor"}}'
OUT=$(AGENTS_JSON="$TMP/agents-nopo.json" run_check); RC=$?
eq "$RC" "2" "the queue is still judged with no po configured"

# --- 13. a suspended rig's store is never read --------------------------------
reset
store cold '{"id":"co-r1","status":"open","issue_type":"task","metadata":{"gc.routed_to":"gc-toolkit.po"}}'
queue '{"id":"co-q1","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{}}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped, not failed"
hasnt "$(cat "$TMP/bd.log")" "cold " "its store is never read"
has "$OUT" "cold: skipped (suspended" "…and the skip is noted"
has "$OUT" "the runs of its queued bead(s) co-q1 were not read" "…naming its queued beads"

# --- 14. fail-closed probes --------------------------------------------------
reset
OUT=$(AGENTS_RC=3 run_check); RC=$?
eq "$RC" "1" "an unreadable agent list warns"
has "$OUT" "could not read \`gc agent list --json\` (rc=3)" "…naming the read"
has "$OUT" "controller down" "…and gc's reason"

reset
OUT=$(RIGS_RC=3 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list warns"
has "$OUT" "\`gc rig list --json\` failed" "…naming the read"

reset
OUT=$(QUEUE_RC=2 run_check); RC=$?
eq "$RC" "1" "an unreadable queue warns"
has "$OUT" "could not read the po's queue" "…naming the queue"
has "$OUT" "a store did not answer" "…and gc's reason"

reset
printf '{"error":"not a queue"}' > "$TMP/queue-bad.json"
OUT=$(QUEUE_JSON="$TMP/queue-bad.json" run_check); RC=$?
eq "$RC" "1" "a queue payload in neither shape warns, never passes"

reset
store alpha '{"id":"al-a3","status":"open","issue_type":"task","assignee":"gc-toolkit.po","metadata":{}}'
OUT=$(INBOX_RC=1 run_check); RC=$?
eq "$RC" "2" "an unreadable mailbox still leaves the alias searched"
has "$OUT" "alpha bead al-a3 (open task): assigned to gc-toolkit.po" "…so an assignment to the alias is found"
has "$OUT" "could not read the po's mailbox" "…and the unread mailbox is named"
has "$OUT" "mail store unreachable" "…with gc's reason"
has "$(cat "$TMP/bd.log")" 'assignee="gc-toolkit.po"' "the query still carries the alias"
has "$(cat "$TMP/bd.log")" 'assignee="gc-toolkit__po" OR assignee="hq-sess1"' "…and the session's runtime name and id, which its session list gives"
hasnt "$(cat "$TMP/bd.log")" 'gc-toolkit.prior-po' "…and no earlier alias it could not read"

reset
store alpha '{"id":"al-a6","status":"open","issue_type":"task","assignee":"hq-sess1","metadata":{}}' \
            '{"id":"al-a7","status":"open","issue_type":"task","assignee":"gc-toolkit__po","metadata":{}}'
OUT=$(SESSIONS_RC=1 run_check); RC=$?
eq "$RC" "2" "an unreadable session list still leaves the mailbox's addresses searched"
has "$OUT" "alpha bead al-a6 (open task): assigned to hq-sess1" "…so an assignment to the session id the mailbox names is found"
has "$OUT" "could not read the po's sessions, \`gc session list --template gc-toolkit.po --json\` (rc=1)" "…and the unread session list is named"
has "$OUT" "store down" "…with gc's reason"
hasnt "$(cat "$TMP/bd.log")" 'gc-toolkit__po' "…and no runtime name it could not read"

reset
printf '{"error":"not a session list"}' > "$TMP/sessions-bad.json"
OUT=$(SESSIONS_JSON="$TMP/sessions-bad.json" run_check); RC=$?
eq "$RC" "1" "a session list payload with no sessions array warns, never passes"
has "$OUT" "could not read the po's sessions" "…naming the read"

reset
OUT=$(BD_FAIL_STORE=alpha BD_FAIL_SUB=list run_check); RC=$?
eq "$RC" "1" "an unreadable route listing warns"
has "$OUT" "alpha: could not list the beads routed to gc-toolkit.po" "…naming the store"
has "$OUT" "the alpha store is down" "…and bd's reason"

reset
OUT=$(BD_FAIL_STORE=town BD_FAIL_SUB=query run_check); RC=$?
eq "$RC" "1" "an unreadable assignee query warns"
has "$OUT" "town: could not query the beads assigned to the po" "…naming the store"

reset
queue "$NEW1"
OUT=$(RUN_LIB_STUB_FAIL=map run_check); RC=$?
eq "$RC" "1" "an unreadable run map warns"
has "$OUT" "alpha: could not read the live runs" "…naming the store whose runs were not read"
has "$OUT" "queued bead(s) al-new1" "…and the queued beads left unchecked"

reset
queue '{"id":"zz-q1","status":"open","issue_type":"task","labels":["hold:mayor"],"metadata":{}}'
OUT=$(run_check); RC=$?
eq "$RC" "1" "a queued bead no rig's prefix names warns"
has "$OUT" "queued bead(s) zz-q1 carry an id prefix no single rig" "…naming it"

# --- 15. a raw control byte, and the scratch tree -----------------------------
reset
inbox "$(printf '{"recipients":["gc-toolkit.po"],"messages":[{"id":"hq-wisp-m3","from":"human","subject":"line one\\nline two%s","read":false}]}' "$(printf '\001')")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a message carrying control bytes is still a finding"
eq "$(printf '%s\n' "$OUT" | grep -c 'hq-wisp-m3')" "1" "…on one line"
eq "$(find "$TMP/rt" -maxdepth 1 -name 'gctk-check-po-queue-only.*' | wc -l | tr -d ' ')" "0" "no run leaves its scratch tree behind"

echo
echo "check-po-queue-only: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
