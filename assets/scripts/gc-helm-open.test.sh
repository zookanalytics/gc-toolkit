#!/usr/bin/env bash
# Hermetic test for the gc-helm `open` verb: it files a conversation about a
# bead in the operator's queue.
#
# A conversation is an ordinary task that tracks the one bead it is about,
# assigned to `human` while it waits in the operator's queue
# (assets/scripts/conversation.sh). `gc-helm open <bead-id>` resolves the bead
# (`gc bd show`) BEFORE it files anything, and exits 4 ("verb runtime failure",
# the documented bead-not-found code) with nothing filed when the id does not
# resolve: a conversation on an unresolvable id would wait in the queue with
# nothing to be about. The gate fails CLOSED on every unhappy reading, because
# the only alternative is a conversation on an unverified bead.
#
# This test runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a
# stubbed `gc` on PATH — no live city, Dolt, network, or sessions. Covered:
#   (EXISTS)   a resolvable bead gets a conversation: one create, a task that
#              tracks the bead and is assigned to `human`, read back as a
#              conversation, exit 0
#   (QUEUED)   a conversation already waiting in the queue is joined, exit 0,
#              nothing created; a new reason is appended to its notes, and a
#              concern it already carries is not appended again
#   (HELD)     a conversation a sitting holds is not joined: a fresh one is
#              filed in the queue
#   (OPEN-JSON) --json prints {subject, conversation, filed}
#   (ALLOWDUP) --allow-duplicate files a fresh conversation beside a queued one
#   (GATE)     a human gate names the one bead still waiting on it, and the
#              conversation replies to the gate; several waiting beads, or none,
#              file nothing and say why
#   (SHAPE)    a task whose tracks edge did not land is closed, not left behind
#   (MISSING)  bd show's `{"error": …}` OBJECT answer -> exit 4, NOTHING filed
#   (MISMATCH) bd show answering a DIFFERENT bead -> exit 4, nothing filed
#   (NORIG)    an id prefix matching no rig -> exit 4 naming the prefix
#   (DOWN)     an empty answer (wedged data plane) -> exit 4, message says
#              "could not verify", NOT "bead not found" — different operator move
#   (CTRLCHR)  control chars in the payload (invalid --json) never read as
#              "missing" when the bead is really there
#   (ORDER)    static: the existence gate precedes the create in the source
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-open-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- gc stub ------------------------------------------------------------------
# One rig (prefix tk). `bd show` answers from $FAKE_SHOW_MODE so each case can
# pick the exact payload shape the real `bd show` emits for that reading; the
# gate ids tk-gate* read as human gates. Every MUTATING call (create, update,
# close, dep add) is appended to $FAKE_CALLS so "nothing was filed" is asserted
# against the actual argv, not against exit status alone; reads are not.
#   bd dep list <bead> --direction=up --type tracks — the bead's conversations:
#     one row for $FAKE_CONV when set, with assignee $FAKE_CONV_ASSIGNEE
#     (default human) and status $FAKE_CONV_STATUS (default open).
#   bd show $FAKE_CONV — that conversation's own row, its ask
#     $FAKE_CONV_DESC (default "an earlier concern") and its notes
#     $FAKE_CONV_NOTES (default none).
#   bd dep list <gate> --direction=up --type blocks — the beads waiting on the
#     gate: $FAKE_WAITERS, a JSON array.
#   bd list --id <c> — the conversation a create filed, read back: a task that
#     tracks the subject its --deps named and carries the assignee it was filed
#     with, unless $FAKE_SHAPE_BROKEN drops the edge. Its replies-to edges are
#     the ones `dep add` recorded.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 ${2:-}" in
  "rig list")
    # This stub's opens are all bead ids, which pass through the resolver with no
    # PR search; the existence gate and conversation lookups run unscoped (the
    # stub ignores --db), so the path needs no .beads dir and only the prefix
    # mapping matters here.
    jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd show")
    if [ -n "${FAKE_CONV:-}" ] && [ "$3" = "$FAKE_CONV" ]; then
      jq -n --arg i "$3" --arg d "${FAKE_CONV_DESC:-an earlier concern}" --arg n "${FAKE_CONV_NOTES:-}" \
        '[{id:$i, title:"an earlier concern", description:$d, notes:$n, status:"open", issue_type:"task", assignee:"human"}]'
      exit 0
    fi
    case "$3" in
      tk-gate*)
        jq -n --arg i "$3" '[{id:$i, title:"Approve the rollout", description:"Gate on the waiting bead. Approve it or say why not.", status:"open", issue_type:"gate", await_type:"human", await_id:"rollout"}]'
        exit 0 ;;
    esac
    case "$FAKE_SHOW_MODE" in
      found)     jq -n --arg i "$3" '[{id:$i, title:"a real bead", status:"open"}]' ;;
      # The REAL not-found answer: a bare object, not an array, exit 1.
      missing)   printf '{\n  "error": "no issues found matching the provided IDs",\n  "schema_version": 1\n}\n'; exit 1 ;;
      # Resolves, but to some OTHER bead than the one typed.
      mismatch)  jq -n '[{id:"tk-somethingelse", title:"a different bead"}]' ;;
      # Wedged data plane: nothing at all on stdout.
      down)      exit 1 ;;
      # Wedged data plane that DOES answer — same error channel as not-found,
      # different error. Existence is unknown, not disproved.
      dberror)   printf '{"error":"dial tcp 127.0.0.1:3307: connect: connection refused","schema_version":1}\n'; exit 1 ;;
      # A real bead whose notes carry raw control chars (invalid --json).
      ctrlchr)   printf '[{"id":"%s","title":"ctl\002chars","notes":"a\001b"}]\n' "$3" ;;
      # A settled item on the DONE band: it exists, it just closed. No successor,
      # so the resolver passes it through and the closed-subject gate must catch it.
      closed)    jq -n --arg i "$3" '[{id:$i, title:"a settled bead", status:"closed"}]' ;;
    esac ;;
  "bd dep")
    case "${3:-}" in
      list)
        case " $* " in
          *" --type tracks "*)
            if [ -n "${FAKE_CONV:-}" ]; then
              jq -n --arg c "$FAKE_CONV" --arg a "${FAKE_CONV_ASSIGNEE:-human}" --arg st "${FAKE_CONV_STATUS:-open}" \
                '[{id:$c, issue_type:"task", status:$st, assignee:$a, title:"an earlier concern", created_at:"2026-10-01T00:00:00Z", dependency_type:"tracks"}]'
            else printf '[]\n'; fi ;;
          *" --type blocks "*) printf '%s\n' "${FAKE_WAITERS:-[]}" ;;
          *) printf '[]\n' ;;
        esac ;;
      *)
        printf 'bd dep %s\n' "$*" >> "$FAKE_CALLS"
        [ "${3:-}" = add ] && printf '%s %s\n' "$4" "$5" >> "$TMP_REPLIES" ;;
    esac ;;
  "bd list")
    # The read-back of a conversation a create just filed (--id).
    _id=""; _prev=""
    for a in "$@"; do [ "$_prev" = "--id" ] && _id="$a"; _prev="$a"; done
    if [ -n "$_id" ]; then
      _subj="$(cat "$TMP_SUBJ" 2>/dev/null || true)"
      _asg="$(cat "$TMP_ASG" 2>/dev/null || true)"
      _reps="$(awk -v c="$_id" '$1 == c {print $2}' "$TMP_REPLIES" 2>/dev/null | jq -Rsc --arg c "$_id" '[ split("\n")[] | select(. != "") | {issue_id:$c, depends_on_id:., type:"replies-to"} ]')"
      if [ -n "${FAKE_SHAPE_BROKEN:-}" ]; then _subj=""; fi
      jq -n --arg c "$_id" --arg s "$_subj" --arg a "$_asg" --argjson r "${_reps:-[]}" \
        '[{id:$c, issue_type:"task", status:"open", assignee:$a,
           dependencies:((if $s == "" then [] else [{issue_id:$c, depends_on_id:$s, type:"tracks"}] end) + $r)}]'
    else printf '[]\n'; fi ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$FAKE_CALLS"
    # FAKE_CREATE_ERROR models bd REJECTING the create (e.g. a title over the
    # cap): the real bd answers a bare {"error":…} OBJECT on stdout, exit 1.
    if [ -n "${FAKE_CREATE_ERROR:-}" ]; then
      printf '{"error":"%s","schema_version":1}\n' "$FAKE_CREATE_ERROR"; exit 1
    fi
    _prev=""
    for a in "$@"; do
      case "$_prev" in
        --deps) printf '%s' "${a#tracks:}" > "$TMP_SUBJ" ;;
        --assignee) printf '%s' "$a" > "$TMP_ASG" ;;
      esac
      _prev="$a"
    done
    jq -n '{id:"tk-conv1"}' ;;
  "bd update"|"bd close")
    printf '%s\n' "bd ${2} ${*:3}" >> "$FAKE_CALLS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_CALLS="$TMP/calls" TMP_SUBJ="$TMP/subj" TMP_ASG="$TMP/asg" TMP_REPLIES="$TMP/replies"
# Neutralize any inherited helm fixture hook so enumerate_rigs uses the stub.
unset GC_HELM_FIXTURE || true
# Keep the cache out of the operator's real cache dir.
export TMPDIR="$TMP"

# reset_store — forget the conversation an earlier case filed.
reset_store() { : > "$FAKE_CALLS"; rm -f "$TMP_SUBJ" "$TMP_ASG"; : > "$TMP_REPLIES"; }

# run_open <show-mode> <bead-id> [args...] -> sets RC/OUT/ERR/CALLS
run_open() {
    reset_store
    export FAKE_SHOW_MODE="$1"; _ro_bead="$2"; shift 2
    set +e
    OUT="$(sh "$SCRIPT" open "$_ro_bead" "$@" 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"
    CALLS="$(cat "$FAKE_CALLS")"
}

# --- (EXISTS) the happy path ---------------------------------------------------
# A positive control first: a gate that rejects everything would pass every
# fail-closed assertion below while breaking the verb outright.
unset FAKE_CONV FAKE_WAITERS FAKE_SHAPE_BROKEN || true
run_open found tk-real1
eq "$RC" "0" "(EXISTS) a resolvable bead exits 0"
CREATE=$(grep '^bd create' <<< "$CALLS" || true)
[ "$(grep -c '^bd create' <<< "$CALLS" || true)" = 1 ] \
  && ok "(EXISTS) one create files the conversation" || bad "(EXISTS) one create (calls: $CALLS)"
# The stub records `$*`, so quoting is flattened — match the argv words.
grep -q -- '-t task' <<< "$CREATE" \
  && ok "(EXISTS) the conversation is an ordinary task" || bad "(EXISTS) task type (calls: $CALLS)"
grep -q -- '--deps tracks:tk-real1' <<< "$CREATE" \
  && ok "(EXISTS) it tracks the bead, on the create" || bad "(EXISTS) tracks edge on the create (calls: $CALLS)"
grep -q -- '--assignee human' <<< "$CREATE" \
  && ok "(EXISTS) it waits in the operator's queue (assigned to human), on the create" \
  || bad "(EXISTS) assignee human on the create (calls: $CALLS)"
grep -qE 'task_kind|gc\.routed_to|gc\.continuation_group' <<< "$CALLS" \
  && bad "(EXISTS) a conversation carries no pack metadata (calls: $CALLS)" \
  || ok "(EXISTS) no pack metadata is stamped"
grep -q '^bd close' <<< "$CALLS" \
  && bad "(EXISTS) the conversation read back and must not be closed (calls: $CALLS)" \
  || ok "(EXISTS) the conversation reads back as one and stays open"
grep -q 'conversation tk-conv1 filed on tk-real1' <<< "$OUT" \
  && ok "(EXISTS) success names the conversation and its bead" || bad "(EXISTS) success sentence (out: $OUT)"
grep -q "operator's queue" <<< "$OUT" \
  && ok "(EXISTS) …and says it waits in the operator's queue" || bad "(EXISTS) queue named (out: $OUT)"
grep -q 'engage tk-real1' <<< "$OUT" \
  && ok "(EXISTS) …and the engage action needed next" || bad "(EXISTS) success points at engage (out: $OUT)"
grep -qi 'visit' <<< "$OUT$ERR" \
  && bad "(EXISTS) open's words name no visit (out: $OUT err: $ERR)" || ok "(EXISTS) no retired word in open's output"

# --- (QUEUED) a conversation waiting in the queue is joined -------------------
export FAKE_CONV=tk-conv0
run_open found tk-real1
eq "$RC" "0" "(QUEUED) a bead whose conversation waits in the queue exits 0"
grep -q 'conversation tk-conv0 is already open' <<< "$OUT" \
  && ok "(QUEUED) prints the queued conversation's id" || bad "(QUEUED) existing conversation reported (out: $OUT)"
grep -q 'engage tk-real1' <<< "$OUT" \
  && ok "(QUEUED) points the operator at engage" || bad "(QUEUED) points at engage (out: $OUT)"
[ -z "$CALLS" ] \
  && ok "(QUEUED) with no new concern, nothing is written" || bad "(QUEUED) wrote something (calls: $CALLS)"
run_open found tk-real1 --reason "the cost question" --body "Compare the two options."
grep -q '^bd create' <<< "$CALLS" \
  && bad "(QUEUED) a second concern must join, not file (calls: $CALLS)" \
  || ok "(QUEUED) a second concern files no second conversation"
grep -q 'bd update tk-conv0 --append-notes Another concern joined this conversation: the cost question' <<< "$CALLS" \
  && ok "(QUEUED) the concern is appended to the queued conversation's notes" \
  || bad "(QUEUED) the concern joins the conversation's notes (calls: $CALLS)"
grep -q 'Compare the two options' <<< "$CALLS" \
  && ok "(QUEUED) …with its body" || bad "(QUEUED) body appended (calls: $CALLS)"
# The same concern again joins nothing. A caller that asks on every pass while
# its condition stands, as deferred dispatch's capped arm does, re-sends the
# words the conversation already carries, in a note an earlier join appended or
# as the ask it was filed with.
export FAKE_CONV_NOTES="Another concern joined this conversation: the cost question

Compare the two options."
run_open found tk-real1 --reason "the cost question" --body "Compare the two options."
eq "$RC" "0" "(QUEUED) the same concern again exits 0"
[ -z "$CALLS" ] \
  && ok "(QUEUED) a concern an earlier join appended is not appended again" \
  || bad "(QUEUED) the same concern was appended again (calls: $CALLS)"
unset FAKE_CONV_NOTES
export FAKE_CONV_DESC="Compare the two options."
run_open found tk-real1 --reason "the cost question" --body "Compare the two options."
[ -z "$CALLS" ] \
  && ok "(QUEUED) a concern that is the conversation's own ask is not appended" \
  || bad "(QUEUED) the conversation's own ask was appended (calls: $CALLS)"
unset FAKE_CONV_DESC

# --- (HELD) a conversation a sitting holds is not joined ----------------------
# A conversation held by a sitting is in that sitting, not in the queue, so a
# concern opened from the board waits in the queue as its own conversation.
export FAKE_CONV=tk-conv0 FAKE_CONV_ASSIGNEE=gc-toolkit/gc-toolkit.tk-conv0 FAKE_CONV_STATUS=in_progress
run_open found tk-real1
eq "$RC" "0" "(HELD) a bead whose conversation a sitting holds exits 0"
grep -q 'conversation tk-conv1 filed on tk-real1' <<< "$OUT" \
  && ok "(HELD) a fresh conversation is filed in the queue" || bad "(HELD) fresh conversation (out: $OUT calls: $CALLS)"
unset FAKE_CONV FAKE_CONV_ASSIGNEE FAKE_CONV_STATUS

# --- (OPEN-JSON) --json prints one object -------------------------------------
run_open found tk-real1 --json
eq "$RC" "0" "(OPEN-JSON) a fresh file exits 0 under --json"
printf '%s' "$OUT" | jq -e '.conversation == "tk-conv1" and .subject == "tk-real1" and .filed == true' >/dev/null 2>&1 \
  && ok "(OPEN-JSON) --json names the conversation filed, filed:true" \
  || bad "(OPEN-JSON) --json object wrong for a fresh file (got: ${OUT:-<nothing>})"
export FAKE_CONV=tk-conv0
run_open found tk-real1 --json
printf '%s' "$OUT" | jq -e '.conversation == "tk-conv0" and .filed == false' >/dev/null 2>&1 \
  && ok "(OPEN-JSON) a join names the queued conversation, filed:false" \
  || bad "(OPEN-JSON) --json object wrong for a join (got: ${OUT:-<nothing>})"
unset FAKE_CONV

# --- (ALLOWDUP) --allow-duplicate files beside a queued conversation ------------
# engage passes it for a concern of its own, which is a distinct dialogue even
# when the bead has a conversation waiting.
export FAKE_CONV=tk-conv0
run_open found tk-real1 --reason "a distinct concern" --allow-duplicate
eq "$RC" "0" "(ALLOWDUP) open --allow-duplicate beside a queued conversation exits 0"
grep -q 'bd create .*--title a distinct concern' <<< "$CALLS" \
  && ok "(ALLOWDUP) a second conversation is filed, titled with the reason" \
  || bad "(ALLOWDUP) second conversation filed (calls: $CALLS)"
grep -q 'is already open' <<< "$OUT$ERR" \
  && bad "(ALLOWDUP) still joined the queued conversation" \
  || ok "(ALLOWDUP) the join is bypassed"
unset FAKE_CONV

# --- (GATE) a gate names the one bead still waiting on it ---------------------
export FAKE_WAITERS='[{"id":"tk-anchor","status":"open","dependency_type":"blocks"},{"id":"tk-done","status":"closed","dependency_type":"blocks"}]'
run_open found tk-gate1
eq "$RC" "0" "(GATE) a gate with one open bead waiting on it exits 0"
grep -q -- '--deps tracks:tk-anchor' <<< "$CALLS" \
  && ok "(GATE) the conversation tracks the waiting bead, never the gate" \
  || bad "(GATE) tracks the waiting bead (calls: $CALLS)"
grep -q -- '--deps tracks:tk-gate1' <<< "$CALLS" \
  && bad "(GATE) a conversation never tracks a gate (calls: $CALLS)" || ok "(GATE) no tracks edge onto the gate"
grep -q 'bd dep add tk-conv1 tk-gate1 --type replies-to' <<< "$CALLS" \
  && ok "(GATE) the conversation replies to the gate" || bad "(GATE) replies-to edge (calls: $CALLS)"
grep -q -- '--title Approve the rollout' <<< "$CALLS" \
  && ok "(GATE) its title is what the gate asks" || bad "(GATE) gate's title (calls: $CALLS)"
grep -q 'Answer the human gate tk-gate1' <<< "$CALLS" \
  && ok "(GATE) its ask names the gate" || bad "(GATE) ask names the gate (calls: $CALLS)"
export FAKE_WAITERS='[{"id":"tk-anchor","status":"open"},{"id":"tk-child","status":"in_progress"}]'
run_open found tk-gate1
eq "$RC" "4" "(GATE-TWO) a gate two open beads wait on exits 4"
[ -z "$CALLS" ] && ok "(GATE-TWO) nothing filed" || bad "(GATE-TWO) filed something (calls: $CALLS)"
grep -q 'tk-anchor tk-child' <<< "$ERR" \
  && ok "(GATE-TWO) names both beads, so the operator names the one they mean" \
  || bad "(GATE-TWO) names both beads (err: $ERR)"
export FAKE_WAITERS='[{"id":"tk-done","status":"closed"}]'
run_open found tk-gate1
eq "$RC" "4" "(GATE-NONE) a gate nothing waits on exits 4"
[ -z "$CALLS" ] && ok "(GATE-NONE) nothing filed" || bad "(GATE-NONE) filed something (calls: $CALLS)"
grep -q 'nothing waits on gate tk-gate1' <<< "$ERR" && grep -q 'tk-done' <<< "$ERR" \
  && ok "(GATE-NONE) says nothing waits and names the bead it was about" \
  || bad "(GATE-NONE) message (err: $ERR)"
grep -q 'gc bd gate resolve tk-gate1' <<< "$ERR" \
  && ok "(GATE-NONE) …and how to clear the gate" || bad "(GATE-NONE) names the resolve (err: $ERR)"
unset FAKE_WAITERS

# --- (SHAPE) a task that did not land as a conversation is closed ---------------
export FAKE_SHAPE_BROKEN=1
run_open found tk-real1
eq "$RC" "4" "(SHAPE) a task whose tracks edge did not land exits 4"
grep -q 'bd close tk-conv1' <<< "$CALLS" \
  && ok "(SHAPE) the misshapen task is closed, not left behind" || bad "(SHAPE) closed (calls: $CALLS)"
unset FAKE_SHAPE_BROKEN

# --- (MISSING) a typo must file NOTHING ----------------------------------------
run_open missing tk-nope1
eq "$RC" "4" "(MISSING) an unresolvable id exits 4 (verb runtime failure)"
[ -z "$CALLS" ] \
  && ok "(MISSING) NO conversation created or wired — nothing filed" \
  || bad "(MISSING) filed something for a nonexistent bead (calls: $CALLS)"
grep -q 'bead not found' <<< "$ERR" \
  && ok "(MISSING) says 'bead not found'" || bad "(MISSING) message (err: $ERR)"
grep -q "tk-nope1" <<< "$ERR" \
  && ok "(MISSING) names the offending id" || bad "(MISSING) message names the id (err: $ERR)"
# The not-found payload is an OBJECT, so a `.[]?|.id` probe would make jq error
# out rather than answer cleanly. Assert the gate never mistakes that for a
# resolved subject — i.e. it fails closed on the shape it meets in production.
grep -q 'filed on' <<< "$OUT" \
  && bad "(MISSING) the {\"error\":…} object read as a resolved subject" \
  || ok "(MISSING) the {\"error\":…} object never reads as resolved"
# --- (MISMATCH) resolving to a DIFFERENT bead is not a resolution --------------
run_open mismatch tk-typo9
eq "$RC" "4" "(MISMATCH) an answer for another bead exits 4"
[ -z "$CALLS" ] \
  && ok "(MISMATCH) nothing filed for a near-miss id" || bad "(MISMATCH) filed on a near-miss (calls: $CALLS)"

# --- (NORIG) an unknown id prefix ---------------------------------------------
run_open missing zz-1234
eq "$RC" "4" "(NORIG) an id whose prefix matches no rig exits 4"
[ -z "$CALLS" ] && ok "(NORIG) nothing filed" || bad "(NORIG) filed something (calls: $CALLS)"
grep -q "prefix 'zz' matches no rig" <<< "$ERR" \
  && ok "(NORIG) names the unmatched prefix (the actionable diagnostic)" \
  || bad "(NORIG) message names the prefix (err: $ERR)"

# --- (DOWN) a wedged data plane is not a typo ---------------------------------
run_open down tk-real1
eq "$RC" "4" "(DOWN) an empty answer exits 4 (fail closed — no conversation on an unverified subject)"
[ -z "$CALLS" ] && ok "(DOWN) nothing filed" || bad "(DOWN) filed on an unverified subject (calls: $CALLS)"
grep -q 'could not verify' <<< "$ERR" \
  && ok "(DOWN) says 'could not verify', not 'bead not found'" \
  || bad "(DOWN) a data-plane outage must not be reported as a typo (err: $ERR)"

# --- (DBERROR) an error payload is not a missing bead -------------------------
# The failure mode this separates: a refused Dolt connection answers on the same
# error channel as not-found. Calling that "bead not found" sends the operator
# hunting a typo while the data plane is down.
run_open dberror tk-real1
eq "$RC" "4" "(DBERROR) an error payload exits 4 (fail closed)"
[ -z "$CALLS" ] && ok "(DBERROR) nothing filed" || bad "(DBERROR) filed on an unverified subject (calls: $CALLS)"
grep -q 'could not verify' <<< "$ERR" \
  && ok "(DBERROR) reported as unverifiable, not as a typo" \
  || bad "(DBERROR) a non-not-found error must not read as 'bead not found' (err: $ERR)"
grep -q 'connection refused' <<< "$ERR" \
  && ok "(DBERROR) surfaces the underlying error to the operator" \
  || bad "(DBERROR) message carries the underlying error (err: $ERR)"

# --- (CTRLCHR) invalid --json must not read as missing ------------------------
# Control chars in a bead's notes break `jq` outright; a real bead reported as
# "not found" would send the operator hunting a typo that does not exist.
run_open ctrlchr tk-real1
eq "$RC" "0" "(CTRLCHR) a real bead with control chars in its payload still resolves"
grep -q 'bd create' <<< "$CALLS" \
  && ok "(CTRLCHR) the conversation is filed normally" || bad "(CTRLCHR) conversation filed (err: $ERR)"

# --- (CLOSED) a settled DONE-band item is not open work -----------------------
# The subject EXISTS but has closed, so the existence gate passes and the pick
# would otherwise file a fresh "operator pick" conversation on it — the loop by
# which a settled question gets re-engaged as a new ask. A
# closed subject here is genuinely settled (a superseded predecessor was already
# redirected to its live successor), so the pick fails closed and files nothing.
run_open closed tk-clsd1
eq "$RC" "4" "(CLOSED) a closed subject exits 4 (no fresh conversation on a settled DONE row)"
grep -q 'is closed' <<< "$ERR" \
  && ok "(CLOSED) the message names the subject as closed" || bad "(CLOSED) message (err: $ERR)"
if grep -q 'bd create' <<< "$CALLS"; then
  bad "(CLOSED) nothing is filed on a closed subject" "found a bd create (calls: $CALLS)"
else
  ok "(CLOSED) nothing is filed on a closed subject"
fi

# --- (ORDER static) the existence gate precedes the create ---------------------
# Placement is the invariant, not just presence: a check that ran after the
# create would leave behind the conversation it exists to refuse.
# `|| true`: with `pipefail`, a grep that finds NOTHING — exactly the regression
# this case exists to catch — would otherwise kill the run under `set -e` before
# it could report, turning a legible failure into a silent early exit.
GATE_LINE="$(grep -n '# >>> open-subject-exists' "$SCRIPT" | head -n1 | cut -d: -f1 || true)"
CREATE_LINE="$(awk '/^cmd_open\(\)/{f=1} f && /gc bd create -t task/{print NR; exit}' "$SCRIPT")"
if [ -n "$GATE_LINE" ] && [ -n "$CREATE_LINE" ] && [ "$GATE_LINE" -lt "$CREATE_LINE" ]; then
  ok "(ORDER) the existence gate precedes the create (line $GATE_LINE < $CREATE_LINE)"
else
  bad "(ORDER) gate must precede the create (gate=${GATE_LINE:-absent} create=${CREATE_LINE:-absent})"
fi

# --- (BLURB) --reason / --body say what the sitting is actually for -----------
# The default wording ("operator pick from the board") is true of the board
# picker and false of every other caller, and the body is not decoration: it is
# the conversation's ask, written at filing time and read at CLAIM time as the
# converse session's brief. Two knobs because the default is two — a short
# title and a longer ask — so one flag driving both would bloat titles or
# starve asks.
reset_store
export FAKE_SHOW_MODE=found
set +e
sh "$SCRIPT" open tk-real1 --reason "operator-origin topic intake" \
   --body "Rebuild what context exists, prep, and hold." >/dev/null 2>&1
set -e
CALLS="$(cat "$FAKE_CALLS")"
grep -q 'bd create .*--title operator-origin topic intake' <<< "$CALLS" \
  && ok "(BLURB) --reason is the title" || bad "(BLURB) title (calls: $CALLS)"
grep -q -- '-d Rebuild what context exists' <<< "$CALLS" \
  && ok "(BLURB) --body becomes the ask" || bad "(BLURB) body (calls: $CALLS)"
grep -q 'operator pick from the board' <<< "$CALLS" \
  && bad "(BLURB) the stock wording must not survive an override" || ok "(BLURB) no stock wording left over"
# --reason alone must not leave a stock body contradicting a custom title.
reset_store
set +e
sh "$SCRIPT" open tk-real1 --reason "operator-origin topic intake" >/dev/null 2>&1
set -e
CALLS="$(cat "$FAKE_CALLS")"
grep -q 'operator pick from the board' <<< "$CALLS" \
  && bad "(BLURB) --reason alone left the stock body (calls: $CALLS)" \
  || ok "(BLURB) --reason alone carries into the body too"
# Still fails closed on a flag with no value, and on a second bead-id.
set +e; sh "$SCRIPT" open tk-real1 --reason >/dev/null 2>&1; RC=$?; set -e
eq "$RC" "2" "(BLURB) --reason with no value is a usage error"
set +e; sh "$SCRIPT" open tk-real1 tk-real2 >/dev/null 2>&1; RC=$?; set -e
eq "$RC" "2" "(BLURB) two bead-ids is a usage error"

# --- (LONGREASON) a reason past the headline cap yields a bounded title --------
# open caps the title at a board headline and keeps the FULL reason in the
# body, so a reason longer than bd's title cap still files. The marker sits past
# the cap: it must be ABSENT from the bounded title and PRESENT in the preserved
# body.
LONG_HEAD="$(printf 'A%.0s' $(seq 1 300))"
LONG_REASON="${LONG_HEAD}ZZTAILZZ"
reset_store
export FAKE_SHOW_MODE=found
set +e
sh "$SCRIPT" open tk-real1 --reason "$LONG_REASON" >/dev/null 2>"$TMP/err"; RC=$?
set -e
CALLS="$(cat "$FAKE_CALLS")"
eq "$RC" "0" "(LONGREASON) a reason past the cap still files the conversation"
# The stub flattens argv; the title is what sits between `--title ` and ` -d `.
TITLE="${CALLS#*--title }"; TITLE="${TITLE%% -d *}"
case "$TITLE" in
  *ZZTAILZZ*) bad "(LONGREASON) the title still carries the full reason, unbounded (title: $TITLE)" ;;
  *…*)        ok "(LONGREASON) the title is truncated to a bounded headline (ends with …)" ;;
  *)          bad "(LONGREASON) the title was neither bounded nor ellipsized (title: $TITLE)" ;;
esac
case "$CALLS" in
  *ZZTAILZZ*) ok "(LONGREASON) the full reason is preserved in the ask" ;;
  *)          bad "(LONGREASON) the full reason was lost from the body (calls: $CALLS)" ;;
esac

# --- (WIDEREASON) a reason in 4-byte characters still fits bd's byte cap ------
# bd caps a title at 500 BYTES, so a tail at the codepoint cap overruns it when
# every character is 4 bytes wide; the headline is cut to a byte budget too.
reset_store
set +e
sh "$SCRIPT" open tk-real1 --reason "$(printf '\360\237\230\200%.0s' $(seq 1 200))" >/dev/null 2>"$TMP/err"; RC=$?
set -e
CALLS="$(cat "$FAKE_CALLS")"
eq "$RC" "0" "(WIDEREASON) a reason in 4-byte characters still files the conversation"
TITLE="${CALLS#*--title }"; TITLE="${TITLE%% -d *}"
TITLE_BYTES=$(printf '%s' "$TITLE" | wc -c)
if [ "$TITLE_BYTES" -le 500 ]; then
  ok "(WIDEREASON) the title fits bd's 500-byte cap ($TITLE_BYTES bytes)"
else
  bad "(WIDEREASON) the title overruns bd's 500-byte cap ($TITLE_BYTES bytes)"
fi

# --- (CREATEFAIL) a real create failure surfaces bd's error, not a jq crash ----
# bd reports a failed create as an {"error":…} object, and the subject bead has
# already resolved by this point. open surfaces bd's own message for such a
# failure, rather than a jq indexing error or a misleading "does it exist?" that
# blames a missing subject.
reset_store
export FAKE_SHOW_MODE=found
set +e
FAKE_CREATE_ERROR='validation failed: title must be 500 characters or less (got 512)' \
  sh "$SCRIPT" open tk-real1 --reason "a short reason" 2>"$TMP/err" >/dev/null; RC=$?
set -e
ERR="$(cat "$TMP/err")"
eq "$RC" "4" "(CREATEFAIL) a create failure exits 4"
grep -q 'title must be 500 characters or less' <<< "$ERR" \
  && ok "(CREATEFAIL) bd's own error is surfaced to the operator" \
  || bad "(CREATEFAIL) bd's error not surfaced (err: $ERR)"
grep -q 'does it exist' <<< "$ERR" \
  && bad "(CREATEFAIL) still prints the misleading '(does it exist?)' (err: $ERR)" \
  || ok "(CREATEFAIL) no misleading '(does it exist?)'"
grep -qi 'cannot index object' <<< "$ERR" \
  && bad "(CREATEFAIL) a raw jq error leaked to the operator (err: $ERR)" \
  || ok "(CREATEFAIL) no raw jq error leaked"

# --- (RIGTIMEOUT) the rig-enumeration bound is generous, and tunable ----------
# `gc rig list` can take several seconds to answer in a loaded city, and a bound
# it overruns makes open exit 3 having filed nothing. That is harmless for the
# board picker, but operator-intake.sh's topic path creates the subject bead
# before open runs, so a timeout there leaves that bead with no conversation.
# enumerate_rigs bounds the call by GC_HELM_RIG_TIMEOUT, default 30s.
mkdir -p "$TMP/slowbin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/slowbin/gc" <<'SLOW'
case "$1 ${2:-}" in
  "rig list")  sleep 2; jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd show")   jq -n --arg i "$3" '[{id:$i, title:"a real bead"}]' ;;
  "bd list")
    case " $* " in
      *" --id "*)
        _p=""; _c=""; for a in "$@"; do [ "$_p" = --id ] && _c="$a"; _p="$a"; done
        jq -n --arg c "$_c" --arg s "$(cat "$TMP_SUBJ" 2>/dev/null)" \
          '[{id:$c, issue_type:"task", status:"open", assignee:"human", dependencies:[{issue_id:$c, depends_on_id:$s, type:"tracks"}]}]'
        exit 0 ;;
    esac
    printf '[]\n' ;;
  "bd dep")
    case "$3" in list) printf '[]\n' ;; *) printf 'bd dep %s\n' "$*" >> "$FAKE_CALLS" ;; esac ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$FAKE_CALLS"
    _p=""; for a in "$@"; do [ "$_p" = --deps ] && printf '%s' "${a#tracks:}" > "$TMP_SUBJ"; _p="$a"; done
    jq -n '{id:"tk-conv1"}' ;;
  "bd update") printf 'bd update %s\n' "$*" >> "$FAKE_CALLS" ;;
esac
exit 0
SLOW
chmod +x "$TMP/slowbin/gc"
: > "$FAKE_CALLS"
set +e
PATH="$TMP/slowbin:$PATH" GC_HELM_RIG_TIMEOUT=1 sh "$SCRIPT" open tk-slow1 >/dev/null 2>&1; RC=$?
set -e
eq "$RC" "3" "(RIGTIMEOUT) a bound shorter than the answer still fails closed"
eq "$(cat "$FAKE_CALLS")" "" "(RIGTIMEOUT) and files nothing when it does"
: > "$FAKE_CALLS"
set +e
PATH="$TMP/slowbin:$PATH" GC_HELM_RIG_TIMEOUT=10 sh "$SCRIPT" open tk-slow1 >/dev/null 2>&1; RC=$?
set -e
eq "$RC" "0" "(RIGTIMEOUT) a generous bound rides out a slow gc rig list"
grep -q 'bd create' <<< "$(cat "$FAKE_CALLS")" \
  && ok "(RIGTIMEOUT) and the conversation is filed" || bad "(RIGTIMEOUT) conversation filed"
# The shipped default must be generous, not the board's render budget.
grep -q 'GC_HELM_RIG_TIMEOUT:-30' "$SCRIPT" \
  && ok "(RIGTIMEOUT) the shipped default is 30s, not the board's 10" \
  || bad "(RIGTIMEOUT) shipped default changed — a one-shot verb must not inherit the board budget"

# --- (RIGWHY) enumerate_rigs names WHICH failure it hit ----------------------
# Every unhappy reading of `gc rig list` exits 3 having filed nothing, with a
# message that names its own cause: a timeout kill, a non-zero exit, an empty
# answer, output that is not JSON, JSON with no '.rigs' array, or a city that
# genuinely has no rigs. Each calls for a different operator move, and behind
# the web board's open button the exit code plus that message is the ENTIRE
# signal the browser gets.
#
# Each case below drives ONE cause through the real script and asserts the
# message names that cause. (DISTINCT) requires the messages to be pairwise
# different, so no two causes share one.
mkdir -p "$TMP/rigbin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/rigbin/gc" <<'RIGSTUB'
if [ "$1 ${2:-}" = "rig list" ]; then
  case "${RIGMODE:-}" in
    slow)     sleep 3; jq -n '{rigs:[{name:"gc-toolkit",path:"/nonexistent-rig",prefix:"tk"}]}' ;;
    exitfail) echo "dial tcp 127.0.0.1:3307: connect: connection refused" >&2; exit 7 ;;
    empty)    : ;;                                  # exit 0, prints NOTHING
    notjson)  echo "warning: rebuilding stale rig cache" ;;
    shape)    jq -n '{other:[]}' ;;                 # valid JSON, no .rigs
    rigless)  jq -n '{rigs:[]}' ;;                  # valid, correct, and empty
    ok)       jq -n '{rigs:[{name:"gc-toolkit",path:"/nonexistent-rig",prefix:"tk"}]}' ;;
  esac
  exit 0
fi
case "$1 ${2:-} ${3:-}" in
  "bd dep list") printf '[]\n'; exit 0 ;;
esac
case "$1 ${2:-}" in
  "bd show") jq -n --arg i "$3" '[{id:$i, title:"a real bead", status:"open"}]'; exit 0 ;;
  "bd list")
    case " $* " in
      *" --id "*)
        _p=""; _c=""; for a in "$@"; do [ "$_p" = --id ] && _c="$a"; _p="$a"; done
        jq -n --arg c "$_c" --arg s "$(cat "$TMP_SUBJ" 2>/dev/null)" \
          '[{id:$c, issue_type:"task", status:"open", assignee:"human", dependencies:[{issue_id:$c, depends_on_id:$s, type:"tracks"}]}]'
        exit 0 ;;
    esac
    printf '[]\n'; exit 0 ;;
esac
printf '%s %s\n' "$1" "${2:-}" >> "$FAKE_CALLS"
case "$1 ${2:-}" in
  "bd create")
    _p=""; for a in "$@"; do [ "$_p" = --deps ] && printf '%s' "${a#tracks:}" > "$TMP_SUBJ"; _p="$a"; done
    jq -n '{id:"tk-conv9"}' ;;
esac
exit 0
RIGSTUB
chmod +x "$TMP/rigbin/gc"

# Drive one cause; capture stderr and status. Bound is 1s so (TIMEOUT) is quick.
rigwhy() {
  : > "$FAKE_CALLS"
  set +e
  RIGWHY_ERR=$(PATH="$TMP/rigbin:$PATH" RIGMODE="$1" GC_HELM_RIG_TIMEOUT="${2:-30}" \
    sh "$SCRIPT" open tk-any1 2>&1 >/dev/null)
  RIGWHY_RC=$?
  set -e
}
# says <mode> <bound> <substring> <label> — the message names this cause, the
# script still fails closed on 3, and nothing was filed on the way out.
says() {
  rigwhy "$1" "$2"
  case "$RIGWHY_ERR" in
    *"$3"*) ok "(RIGWHY) $4" ;;
    *)      bad "(RIGWHY) $4 — got: $RIGWHY_ERR" ;;
  esac
  eq "$RIGWHY_RC" "3" "(RIGWHY) …and still exits 3 ($4)"
  eq "$(cat "$FAKE_CALLS")" "" "(RIGWHY) …having filed nothing ($4)"
}

says slow     1  "did not answer within 1s and was killed" "a timeout kill says it timed out, and names the bound"
says exitfail 30 "exited 7"                                "a non-zero gc exit reports the status"
says exitfail 30 "connection refused"                      "…and carries gc's own stderr, instead of discarding it"
says empty    30 "exited 0 but printed nothing"            "a silent empty answer is not read as an empty city"
says notjson  30 "is not JSON"                             "unparseable output says so, rather than 'returned nothing'"
says shape    30 "no '.rigs' array"                        "valid JSON of the wrong shape is a gc contract change"
says rigless  30 "no rigs in this city"                    "a genuinely rigless city is reported as a CITY state"

# (DISTINCT) no two causes share a message: collect every cause's message and
# require as many unique messages as there are causes.
: > "$TMP/rigmsgs"
for m in slow exitfail empty notjson shape rigless; do
  if [ "$m" = slow ]; then rigwhy "$m" 1; else rigwhy "$m" 30; fi
  printf '%s\n' "$RIGWHY_ERR" >> "$TMP/rigmsgs"
done
NUNIQ=$(sort -u "$TMP/rigmsgs" | wc -l | tr -d ' ')
eq "$NUNIQ" "6" "(RIGWHY-DISTINCT) six causes produce six different sentences"

# The rigless message must NOT accuse the data plane — that is the wrong move
# for a city that answered correctly.
rigwhy rigless 30
case "$RIGWHY_ERR" in
  *"gc doctor"*|*Dolt*) bad "(RIGWHY-DISTINCT) an empty city is blamed on the data plane: $RIGWHY_ERR" ;;
  *)                    ok  "(RIGWHY-DISTINCT) an empty city is not blamed on the data plane" ;;
esac
# …and the happy path still works through the same stub, so none of the cause
# checks fire on a good answer.
rigwhy ok 30
eq "$RIGWHY_RC" "0" "(RIGWHY) a well-formed rig list still enumerates and files"

# MUTATION CHECK (static): the causes are told apart by gc's exit status and
# stderr, so enumerate_rigs must capture both. No stubbed run above takes its
# mktemp-failure fallback, so only the source shows that the fallback keeps the
# exit status too.
grep -q 'gc rig list --json 2>"\$_er_errf"' "$SCRIPT" \
  && ok "(RIGWHY-EVIDENCE) gc's stderr is captured, not sent to /dev/null" \
  || bad "(RIGWHY-EVIDENCE) stderr capture removed — messages will lose their 'why'"
# Match the ASSIGNMENT lines only, bounded to the function body. The first line
# in enumerate_rigs naming "gc rig list" is a COMMENT, so a check anchored there
# passes whatever the code does. Anchor guards to code, never to prose.
grep -q '|| true' < <(awk '/^enumerate_rigs\(\)/{f=1} f&&/^\}/{f=0} f&&/rigs_raw=\$\(/' "$SCRIPT") \
  && bad "(RIGWHY-EVIDENCE) '|| true' is back — the exit status is discarded again" \
  || ok "(RIGWHY-EVIDENCE) the exit status is kept, not swallowed by '|| true'"

# --- (RESOLVE) the subject resolver: PR ref / superseded id -> live bead ------
# A PR reference or a settled (closed and superseded) bead id resolves to the
# LIVE bead that owns the work, by metadata and the graph and never by a title,
# before a conversation is filed on it. These cases drive the REAL cmd_open over
# a stub whose `bd show` is id-aware, so a supersede chain and a live bead read
# differently, and whose `bd list` answers the PR search. They assert the
# conversation is filed on the RESOLVED bead (its tracks edge), and that an
# unresolvable or ambiguous reference files nothing.
mkdir -p "$TMP/resbin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/resbin/gc" <<'RESGC'
# One rig, prefix tk, with a real .beads store (created below as $RESRIG) so the
# resolver can pin --db for its cross-store PR search; the stub ignores the --db
# value and answers by argv pattern. `bd show` branches on the id so a supersede
# chain and a live bead read differently; `bd list` answers the PR search (which
# carries `blocked` in --status) and the read-back of the conversation a create
# filed (--id).
case "$1 ${2:-}" in
  "rig list")
    jq -n '{rigs:[{name:"gc-toolkit", path:env.RESRIG, prefix:"tk"}]}' ;;
  "bd show")
    case "$3" in
      tk-pred)    jq -n '[{id:"tk-pred",   status:"closed", metadata:{"gc.superseded_by":"tk-succ","gc.superseded_by_store":"rig:gc-toolkit"}}]' ;;
      tk-pred2)   jq -n '[{id:"tk-pred2",  status:"closed", metadata:{"gc.superseded_by":"tk-gone"}}]' ;;
      tk-head)    jq -n '[{id:"tk-head",   status:"closed", metadata:{"gc.superseded_by":"tk-mid"}}]' ;;
      tk-mid)     jq -n '[{id:"tk-mid",    status:"closed", metadata:{"gc.superseded_by":"tk-succ"}}]' ;;
      tk-succ)    jq -n '[{id:"tk-succ",   status:"open",   title:"the live successor"}]' ;;
      tk-cyc1)    jq -n '[{id:"tk-cyc1",   status:"closed", metadata:{"gc.superseded_by":"tk-cyc2"}}]' ;;
      tk-cyc2)    jq -n '[{id:"tk-cyc2",   status:"closed", metadata:{"gc.superseded_by":"tk-cyc1"}}]' ;;
      tk-live1)   jq -n '[{id:"tk-live1",  status:"open",   title:"a live bead"}]' ;;
      tk-prbead)  jq -n '[{id:"tk-prbead", status:"open",   title:"the PR anchor"}]' ;;
      tk-prbead2) jq -n '[{id:"tk-prbead2",status:"open",   title:"another PR anchor"}]' ;;
      tk-defbead) jq -n '[{id:"tk-defbead",status:"deferred",title:"a deferred PR anchor"}]' ;;
      *)          printf '{"error":"no issues found"}\n'; exit 1 ;;
    esac ;;
  "bd list")
    case " $* " in
      *" --id "*)
        _p=""; _c=""; for a in "$@"; do [ "$_p" = --id ] && _c="$a"; _p="$a"; done
        jq -n --arg c "$_c" --arg s "$(cat "$TMP_SUBJ" 2>/dev/null)" \
          '[{id:$c, issue_type:"task", status:"open", assignee:"human", dependencies:[{issue_id:$c, depends_on_id:$s, type:"tracks"}]}]'
        exit 0 ;;
    esac
    case "$*" in
      # The resolver's PR search carries the full live-status set
      # (open,in_progress,blocked,deferred,hooked,pinned). FAKE_DEFERRED_ROWS
      # models an anchor only a query carrying `deferred` can see, and falls
      # back to the ordinary PR rows when unset. A query carrying `blocked`
      # without `deferred` sees only the ordinary rows, so a resolver on that
      # narrower set fails RESOLVE-PR-DEFERRED while every other PR case passes.
      *deferred*) printf '%s' "${FAKE_DEFERRED_ROWS:-${FAKE_PR_ROWS:-[]}}" ;;
      *blocked*)  printf '%s' "${FAKE_PR_ROWS:-[]}" ;;
      *)          printf '[]' ;;
    esac ;;
  "bd dep")
    case "$3" in list) printf '[]\n' ;; *) printf 'bd dep %s\n' "$*" >> "$FAKE_CALLS" ;; esac ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$FAKE_CALLS"
    _p=""; for a in "$@"; do [ "$_p" = --deps ] && printf '%s' "${a#tracks:}" > "$TMP_SUBJ"; _p="$a"; done
    jq -n '{id:"tk-convR"}' ;;
  "bd update") printf 'bd update %s\n' "$*" >> "$FAKE_CALLS" ;;
esac
exit 0
RESGC
chmod +x "$TMP/resbin/gc"
# The rig's ledger must exist as a real .beads dir: the resolver fails closed on
# any listed rig it cannot pin with --db, so a no-.beads path would refuse every
# PR resolution below rather than exercise it.
mkdir -p "$TMP/resrig/.beads"
export RESRIG="$TMP/resrig"
# FAKE_DEFERRED_ROWS is left UNSET by default, so the PR search falls back to
# FAKE_PR_ROWS for every case but the deferred one, which exports it to model an
# anchor only a query carrying `deferred` sees.
export FAKE_PR_ROWS='[]'

# run_resolve <arg> -> RC/OUT/ERR/CALLS via the id-aware resbin stub.
run_resolve() {
    reset_store
    set +e
    OUT="$(PATH="$TMP/resbin:$PATH" sh "$SCRIPT" open "$1" 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"; CALLS="$(cat "$FAKE_CALLS")"
}

# (RESOLVE-SUPERSEDE) a closed+superseded id files on the SUCCESSOR, said aloud.
FAKE_PR_ROWS='[]'; run_resolve tk-pred
eq "$RC" "0" "(RESOLVE-SUPERSEDE) a closed+superseded id resolves and files"
grep -q -- '--deps tracks:tk-succ' <<< "$CALLS" \
  && ok "(RESOLVE-SUPERSEDE) the conversation is filed on the live successor" \
  || bad "(RESOLVE-SUPERSEDE) the conversation tracks the successor (calls: $CALLS)"
grep -q -- '--deps tracks:tk-pred' <<< "$CALLS" \
  && bad "(RESOLVE-SUPERSEDE) filed on the dead predecessor" \
  || ok "(RESOLVE-SUPERSEDE) never files on the predecessor"
grep -q 'tk-pred is closed and superseded' <<< "$ERR" \
  && ok "(RESOLVE-SUPERSEDE) announces the redirect — never silent" \
  || bad "(RESOLVE-SUPERSEDE) redirect not announced (err: $ERR)"

# (RESOLVE-CHAIN) a multi-hop chain (head -> mid -> succ) resolves to the end.
FAKE_PR_ROWS='[]'; run_resolve tk-head
eq "$RC" "0" "(RESOLVE-CHAIN) a supersede chain resolves and files"
grep -q -- '--deps tracks:tk-succ' <<< "$CALLS" \
  && ok "(RESOLVE-CHAIN) followed head->mid->succ to the live end" \
  || bad "(RESOLVE-CHAIN) chain not followed to the end (calls: $CALLS)"

# (RESOLVE-LIVE) a live bead id passes through unchanged and unremarked.
FAKE_PR_ROWS='[]'; run_resolve tk-live1
eq "$RC" "0" "(RESOLVE-LIVE) a live bead id still files"
grep -q -- '--deps tracks:tk-live1' <<< "$CALLS" \
  && ok "(RESOLVE-LIVE) filed on the id as given" || bad "(RESOLVE-LIVE) filed elsewhere (calls: $CALLS)"
grep -qiE 'superseded|PR #' <<< "$ERR" \
  && bad "(RESOLVE-LIVE) a live id must not trigger a redirect note (err: $ERR)" \
  || ok "(RESOLVE-LIVE) no redirect note for a live id"

# (RESOLVE-CYCLE) a superseded-by cycle is refused, not guessed; nothing filed.
FAKE_PR_ROWS='[]'; run_resolve tk-cyc1
eq "$RC" "4" "(RESOLVE-CYCLE) a supersede cycle exits 4"
[ -z "$CALLS" ] && ok "(RESOLVE-CYCLE) nothing filed on a cycle" || bad "(RESOLVE-CYCLE) filed despite a cycle (calls: $CALLS)"
grep -q 'cycle' <<< "$ERR" && ok "(RESOLVE-CYCLE) names the cycle" || bad "(RESOLVE-CYCLE) message (err: $ERR)"

# (RESOLVE-BROKEN-POINTER) a superseded id whose successor does not resolve is
# refused — never a silent fall-back to opening the settled predecessor.
FAKE_PR_ROWS='[]'; run_resolve tk-pred2
eq "$RC" "4" "(RESOLVE-BROKEN-POINTER) an unresolvable successor exits 4"
[ -z "$CALLS" ] \
  && ok "(RESOLVE-BROKEN-POINTER) nothing filed on the settled predecessor" \
  || bad "(RESOLVE-BROKEN-POINTER) filed something (calls: $CALLS)"
grep -q 'tk-gone' <<< "$ERR" \
  && ok "(RESOLVE-BROKEN-POINTER) names the successor it could not resolve" \
  || bad "(RESOLVE-BROKEN-POINTER) names the successor (err: $ERR)"

# (RESOLVE-PR-NUMBER) a bare PR number resolves to the anchor recording it.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]'
run_resolve 615
eq "$RC" "0" "(RESOLVE-PR-NUMBER) a PR number resolves and files"
grep -q -- '--deps tracks:tk-prbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-NUMBER) filed on the bead whose pr_number matches" \
  || bad "(RESOLVE-PR-NUMBER) filed elsewhere (calls: $CALLS)"
grep -q 'PR #615 -> tk-prbead' <<< "$ERR" \
  && ok "(RESOLVE-PR-NUMBER) says which bead it matched" || bad "(RESOLVE-PR-NUMBER) match not announced (err: $ERR)"

# (RESOLVE-PR-URL) a PR URL resolves the same way, pinning the repo.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]'
run_resolve 'https://github.com/o/r/pull/615'
eq "$RC" "0" "(RESOLVE-PR-URL) a PR URL resolves and files"
grep -q -- '--deps tracks:tk-prbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-URL) filed on the anchor whose pr_url matches" || bad "(RESOLVE-PR-URL) filed elsewhere (calls: $CALLS)"

# (RESOLVE-PR-URL-DISAMBIG) two beads share a number; the URL pins the repo.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r1/pull/615"}},{"id":"tk-prbead2","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r2/pull/615"}}]'
run_resolve 'https://github.com/o/r1/pull/615'
eq "$RC" "0" "(RESOLVE-PR-URL-DISAMBIG) the URL disambiguates a shared number"
grep -q -- '--deps tracks:tk-prbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-URL-DISAMBIG) the repo in the URL selects one bead" \
  || bad "(RESOLVE-PR-URL-DISAMBIG) filed elsewhere (calls: $CALLS)"

# (RESOLVE-PR-URL-SUBPAGE) a browser URL from a PR subpage (…/pull/615/files)
# resolves the same anchor: the stored pr_url is the canonical …/pull/<number>,
# so the paste is canonicalized before the comparison.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]'
run_resolve 'https://github.com/o/r/pull/615/files'
eq "$RC" "0" "(RESOLVE-PR-URL-SUBPAGE) a PR subpage URL resolves and files"
grep -q -- '--deps tracks:tk-prbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-URL-SUBPAGE) filed on the anchor whose canonical pr_url matches" \
  || bad "(RESOLVE-PR-URL-SUBPAGE) filed elsewhere (calls: $CALLS)"

# (RESOLVE-PR-URL-QUERY) a URL carrying a query string (…/pull/615?diff=split)
# resolves the same anchor for the same reason.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]'
run_resolve 'https://github.com/o/r/pull/615?diff=split'
eq "$RC" "0" "(RESOLVE-PR-URL-QUERY) a PR URL with a query string resolves and files"
grep -q -- '--deps tracks:tk-prbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-URL-QUERY) filed on the anchor whose canonical pr_url matches" \
  || bad "(RESOLVE-PR-URL-QUERY) filed elsewhere (calls: $CALLS)"

# (RESOLVE-PR-URL-SUBPAGE-DISAMBIG) canonicalizing the paste keeps the repo, so
# a subpage URL still pins one bead among a shared number.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r1/pull/615"}},{"id":"tk-prbead2","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r2/pull/615"}}]'
run_resolve 'https://github.com/o/r1/pull/615/files'
eq "$RC" "0" "(RESOLVE-PR-URL-SUBPAGE-DISAMBIG) a subpage URL disambiguates a shared number"
grep -q -- '--deps tracks:tk-prbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-URL-SUBPAGE-DISAMBIG) the repo in the subpage URL selects one bead" \
  || bad "(RESOLVE-PR-URL-SUBPAGE-DISAMBIG) filed elsewhere (calls: $CALLS)"

# (RESOLVE-PR-MISSING) a PR no bead records fails closed, nothing filed.
FAKE_PR_ROWS='[]'; run_resolve 999
eq "$RC" "4" "(RESOLVE-PR-MISSING) an unrecorded PR exits 4"
[ -z "$CALLS" ] && ok "(RESOLVE-PR-MISSING) nothing filed" || bad "(RESOLVE-PR-MISSING) filed something (calls: $CALLS)"
grep -q 'no open bead records PR #999' <<< "$ERR" \
  && ok "(RESOLVE-PR-MISSING) names the PR it could not resolve" || bad "(RESOLVE-PR-MISSING) message (err: $ERR)"

# (RESOLVE-PR-AMBIGUOUS) a bare number several beads record is refused by name.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615"}},{"id":"tk-prbead2","status":"open","metadata":{"pr_number":"615"}}]'
run_resolve 615
eq "$RC" "4" "(RESOLVE-PR-AMBIGUOUS) an ambiguous PR number exits 4"
[ -z "$CALLS" ] && ok "(RESOLVE-PR-AMBIGUOUS) nothing filed" || bad "(RESOLVE-PR-AMBIGUOUS) filed something (calls: $CALLS)"
grep -q 'ambiguous' <<< "$ERR" && ok "(RESOLVE-PR-AMBIGUOUS) says ambiguous" || bad "(RESOLVE-PR-AMBIGUOUS) message (err: $ERR)"
grep -q 'tk-prbead2' <<< "$ERR" && ok "(RESOLVE-PR-AMBIGUOUS) names every candidate" || bad "(RESOLVE-PR-AMBIGUOUS) names candidates (err: $ERR)"

# (RESOLVE-PR-DEFERRED) a PR whose anchor sits in a NON-OPEN live state (deferred)
# resolves too. The resolver's status set must be the pack's live-PR set
# (open,in_progress,blocked,deferred,hooked,pinned), which pr-facts.sh defines
# as LIVE_STATUSES and gctk merge as mergeLiveStatuses. FAKE_DEFERRED_ROWS is
# visible only to a query carrying `deferred`, so a resolver searching
# open,in_progress,blocked alone finds nothing here and exits 4.
FAKE_PR_ROWS='[]'
export FAKE_DEFERRED_ROWS='[{"id":"tk-defbead","status":"deferred","metadata":{"pr_number":"616","pr_url":"https://github.com/o/r/pull/616"}}]'
run_resolve 616
eq "$RC" "0" "(RESOLVE-PR-DEFERRED) a PR anchor in a non-open live state resolves and files"
grep -q -- '--deps tracks:tk-defbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-DEFERRED) filed on the deferred anchor recording the PR" \
  || bad "(RESOLVE-PR-DEFERRED) not filed on the deferred anchor (calls: $CALLS)"
grep -q 'PR #616 -> tk-defbead' <<< "$ERR" \
  && ok "(RESOLVE-PR-DEFERRED) says which bead it matched" || bad "(RESOLVE-PR-DEFERRED) match not announced (err: $ERR)"
unset FAKE_PR_ROWS FAKE_DEFERRED_ROWS

# --- (RESOLVE-PR-UNREADABLE) a store that will not read fails the number CLOSED -
# A bare PR number is unique only across EVERY live store, so the search must be
# able to read them all: a per-rig `gc bd list` that errors, or answers with a
# non-array payload, leaves the candidate set incomplete and the resolution is
# refused rather than resolved from the stores that answered — otherwise a number
# an unreadable store also records would open a conversation on the wrong anchor. Two
# rig stores: rigA does not read, rigB records PR #615. Driven over `open` so
# "nothing filed" is observable, with a readable-but-EMPTY control proving the
# refusal keys on unreadability, not merely on a second rig existing.
mkdir -p "$TMP/unread/rigA/.beads" "$TMP/unread/rigB/.beads" "$TMP/unread/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/unread/bin/gc" <<UNREADGC
# rigA (prefix aa) is scanned first; its ledger read is controlled by \$RIGA_MODE:
# fail = non-zero exit, badshape = rc 0 with a non-array answer, ok = an empty
# array (readable, no PR rows). rigB (prefix tk) records PR #615. The PR search
# carries the --db of the rig it scans, so the arms tell the ledgers apart by path.
case "\$1 \${2:-}" in
  "rig list")
    jq -n '{rigs:[{name:"riga",path:"$TMP/unread/rigA",prefix:"aa"},{name:"rigb",path:"$TMP/unread/rigB",prefix:"tk"}]}' ;;
  "bd list")
    case "\$*" in
      *"$TMP/unread/rigA/.beads"*)
        case "\${RIGA_MODE:-fail}" in
          badshape) printf '{"error":"dolt is wedged"}\n' ;;
          ok)       printf '[]\n' ;;
          *)        echo "dolt: connection refused" >&2; exit 7 ;;
        esac ;;
      *"$TMP/unread/rigB/.beads"*) printf '%s' "\${FAKE_PR_ROWS:-[]}" ;;
      *) printf '[]' ;;
    esac ;;
  "bd show")
    # Reached only if the resolver does NOT refuse an unreadable store: it would
    # then resolve #615 from rigB and file a conversation, so this arm lets that path
    # complete (RC 0, a non-empty CALLS) and the assertions below catch it.
    case "\$3" in
      tk-prbead) jq -n '[{id:"tk-prbead",status:"open",title:"the PR anchor"}]' ;;
      *)         printf '{"error":"no issues found"}\n'; exit 1 ;;
    esac ;;
  "bd create") printf 'bd create %s\n' "\$*" >> "\$FAKE_CALLS"; jq -n '{id:"tk-convU"}' ;;
  "bd update") printf 'bd update %s\n' "\$*" >> "\$FAKE_CALLS" ;;
esac
exit 0
UNREADGC
chmod +x "$TMP/unread/bin/gc"
export FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]'

run_unread() { # <riga-mode> <verb> -> RC/OUT/ERR/CALLS
    : > "$FAKE_CALLS"
    set +e
    OUT="$(RIGA_MODE="$1" PATH="$TMP/unread/bin:$PATH" sh "$SCRIPT" "$2" 615 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"; CALLS="$(cat "$FAKE_CALLS")"
}

# rigA's read fails (non-zero): refuse, name the ledger, file nothing.
run_unread fail open
eq "$RC" "4" "(RESOLVE-PR-UNREADABLE) a non-zero per-rig read fails the resolution closed"
[ -z "$CALLS" ] && ok "(RESOLVE-PR-UNREADABLE) nothing filed when a store errored" \
  || bad "(RESOLVE-PR-UNREADABLE) filed despite an unreadable store (calls: $CALLS)"
grep -q 'riga' <<< "$ERR" && ok "(RESOLVE-PR-UNREADABLE) names the ledger that made the proof incomplete" \
  || bad "(RESOLVE-PR-UNREADABLE) does not name the unreadable ledger (err: $ERR)"

# rigA answers rc 0 but with a non-array payload: same refusal.
run_unread badshape open
eq "$RC" "4" "(RESOLVE-PR-BADSHAPE) a non-array per-rig answer fails the resolution closed"
[ -z "$CALLS" ] && ok "(RESOLVE-PR-BADSHAPE) nothing filed on a non-array answer" \
  || bad "(RESOLVE-PR-BADSHAPE) filed despite a non-array answer (calls: $CALLS)"
grep -q 'riga' <<< "$ERR" && ok "(RESOLVE-PR-BADSHAPE) names the unreadable ledger" \
  || bad "(RESOLVE-PR-BADSHAPE) does not name the ledger (err: $ERR)"

# CONTROL: rigA is readable but empty, so the scan finds #615 in rigB and
# resolves — proving the refusal keys on unreadability, not on a second store.
run_unread ok resolve
eq "$OUT" "tk-prbead" "(RESOLVE-PR-UNREADABLE-CONTROL) a readable empty store does not block resolution"
grep -q 'PR #615 -> tk-prbead' <<< "$ERR" \
  && ok "(RESOLVE-PR-UNREADABLE-CONTROL) announces the match found in the readable store" \
  || bad "(RESOLVE-PR-UNREADABLE-CONTROL) match not announced (err: $ERR)"
unset FAKE_PR_ROWS

# --- (RESOLVE-PR-NO-LEDGER) a listed rig with no .beads store fails CLOSED ------
# Distinct from the non-zero-exit and non-array reads above: here the ledger is
# simply absent, so it cannot be pinned with --db and the per-rig read would fall
# back to the session default store — one store read twice, this rig never read.
# That leaves the cross-store uniqueness proof silently incomplete, and a number
# the unread rig also records could open a conversation on the wrong anchor. rigA has no
# .beads dir and is scanned first; rigB records #615 but is never reached.
mkdir -p "$TMP/noledger/rigA" "$TMP/noledger/rigB/.beads" "$TMP/noledger/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/noledger/bin/gc" <<NOLEDGERGC
case "\$1 \${2:-}" in
  "rig list")
    jq -n '{rigs:[{name:"riga",path:"$TMP/noledger/rigA",prefix:"aa"},{name:"rigb",path:"$TMP/noledger/rigB",prefix:"tk"}]}' ;;
  "bd list")
    case "\$*" in
      *"$TMP/noledger/rigB/.beads"*) printf '%s' "\${FAKE_PR_ROWS:-[]}" ;;
      *) printf '[]' ;;
    esac ;;
  "bd show")
    case "\$3" in
      tk-prbead) jq -n '[{id:"tk-prbead",status:"open",title:"the PR anchor"}]' ;;
      *)         printf '{"error":"no issues found"}\n'; exit 1 ;;
    esac ;;
  "bd create") printf 'bd create %s\n' "\$*" >> "\$FAKE_CALLS"; jq -n '{id:"tk-convN"}' ;;
  "bd update") printf 'bd update %s\n' "\$*" >> "\$FAKE_CALLS" ;;
esac
exit 0
NOLEDGERGC
chmod +x "$TMP/noledger/bin/gc"
export FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]'
: > "$FAKE_CALLS"
set +e
OUT="$(PATH="$TMP/noledger/bin:$PATH" sh "$SCRIPT" open 615 2>"$TMP/err")"; RC=$?
set -e
ERR="$(cat "$TMP/err")"; CALLS="$(cat "$FAKE_CALLS")"
eq "$RC" "4" "(RESOLVE-PR-NO-LEDGER) a rig with no .beads store fails the resolution closed"
[ -z "$CALLS" ] && ok "(RESOLVE-PR-NO-LEDGER) nothing filed when a rig ledger is missing" \
  || bad "(RESOLVE-PR-NO-LEDGER) filed despite a missing ledger (calls: $CALLS)"
grep -q 'riga' <<< "$ERR" && ok "(RESOLVE-PR-NO-LEDGER) names the rig whose ledger is missing" \
  || bad "(RESOLVE-PR-NO-LEDGER) does not name the missing ledger (err: $ERR)"
unset FAKE_PR_ROWS

# --- (RESOLVE-REACT / RESOLVE-ENGAGE) the resolved subject drives the write ----
# react and engage resolve the same reference open does, then act on the LIVE
# bead: react slings it through gc-proactive.sh, engage holds a conversation
# about it in a new sitting. These cases drive the REAL verbs over a stub that
# answers the resolve reads and, for engage, the conversation lookup, the spawn
# and the bind, and assert the id each verb writes is the RESOLVED one (a
# supersede chain's successor, or the bead a PR number records), never the
# reference typed.
mkdir -p "$TMP/rebin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/rebin/gc" <<'REBIN'
# `bd show` branches on the id so a supersede chain and a live bead read
# differently. The conversation tk-convE tracks $FAKE_CONV_SUBJ, waiting in the
# queue until a bind writes the assignee kept in $CONV_STATE. `bd list` tells
# the PR search (carries `blocked` in --status) apart from a by-id read. The
# session list holds no sitting; `session new` returns a fixed identity, its
# alias qualified as gascity stores it. Mutations append to $FAKE_CALLS.
case "$1 ${2:-}" in
  "rig list")
    jq -n '{rigs:[{name:"gc-toolkit", path:env.REBINRIG, prefix:"tk"}]}' ;;
  "bd show")
    case "$3" in
      tk-pred)   jq -n '[{id:"tk-pred",   status:"closed", metadata:{"gc.superseded_by":"tk-succ"}}]' ;;
      tk-succ)   jq -n '[{id:"tk-succ",   status:"open",   title:"the live successor"}]' ;;
      tk-prbead) jq -n '[{id:"tk-prbead", status:"open",   title:"the PR anchor"}]' ;;
      tk-convE)
        _a="$(cat "$CONV_STATE" 2>/dev/null || true)"
        jq -n --arg a "${_a:-human}" --arg s "${FAKE_CONV_SUBJ:-}" '[{id:"tk-convE", issue_type:"task", status:"open", assignee:$a, title:"an earlier concern", dependencies:[{id:$s, dependency_type:"tracks"}]}]' ;;
      *) printf '{"error":"no issues found"}\n'; exit 1 ;;
    esac ;;
  "bd list")
    case "$*" in
      *blocked*) printf '%s' "${FAKE_PR_ROWS:-[]}" ;;
      *)         printf '[]' ;;
    esac ;;
  "bd dep")
    case "$3" in
      list)
        if [ "$4" = "${FAKE_CONV_SUBJ:-}" ] && [ -n "$4" ] && case " $* " in *" --type tracks "*) true ;; *) false ;; esac; then
          _a="$(cat "$CONV_STATE" 2>/dev/null || true)"
          jq -n --arg a "${_a:-human}" '[{id:"tk-convE", issue_type:"task", status:"open", assignee:$a, title:"an earlier concern", created_at:"2026-10-01T00:00:00Z", dependency_type:"tracks"}]'
        else printf '[]\n'; fi ;;
      *) printf 'bd dep %s\n' "$*" >> "$FAKE_CALLS" ;;
    esac ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$FAKE_CALLS"
    _sn="$(printf '%s' "$*" | sed -n 's/.* --assignee \([^ ]*\).*$/\1/p')"
    [ -n "$_sn" ] && printf '%s' "$_sn" > "$CONV_STATE" ;;
  "session list")
    jq -n '{sessions:[]}' ;;
  "session new")
    jq -n '{session_id:"lx-fake", session_name:"s-lx-fake", alias:"gc-toolkit/gc-toolkit.tk-convE"}' ;;
esac
exit 0
REBIN
chmod +x "$TMP/rebin/gc"
cat > "$TMP/rebin/gc-proactive.sh" <<'PROACTIVE'
#!/usr/bin/env bash
printf 'proactive %s\n' "$*" >> "$FAKE_SLING"
exit 0
PROACTIVE
chmod +x "$TMP/rebin/gc-proactive.sh"
printf '#!/bin/sh\nexit 0\n' > "$TMP/rebin/no-reminder"; chmod +x "$TMP/rebin/no-reminder"
# A real .beads store for the rig, so the resolver can pin --db for the PR search
# react/engage run; without it the resolver fails closed before resolving. engage
# also refuses up front a rig whose checkout carries no converse template
# (agents/converse-*), so the fixture carries one; without it engage exits 4
# before it resolves and binds.
mkdir -p "$TMP/rebinrig/.beads" "$TMP/rebinrig/agents/converse-opus"
export REBINRIG="$TMP/rebinrig"
export FAKE_SLING="$TMP/slung" CONV_STATE="$TMP/conv_state"

# run_react <arg> — drive the REAL cmd_react; the fake gc-proactive.sh records
# the `sling` argv so the resolved subject is checked against the slung id.
run_react() {
    : > "$FAKE_SLING"
    set +e
    OUT="$(PATH="$TMP/rebin:$PATH" GC_PROACTIVE_TOOL="$TMP/rebin/gc-proactive.sh" \
        sh "$SCRIPT" react "$1" --dry-run 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"; SLUNG="$(cat "$FAKE_SLING")"
}
# run_engage <arg> — drive the REAL cmd_engage through the spawn/bind path,
# --no-attach so no session is attached; CONV_STATE reset so the pre-bind read
# sees the conversation waiting in the queue.
run_engage() {
    : > "$FAKE_CALLS"; : > "$CONV_STATE"
    set +e
    OUT="$(PATH="$TMP/rebin:$PATH" GC_SITTING_COMMENT_TOOL="$TMP/rebin/no-reminder" \
        sh "$SCRIPT" engage "$1" --no-input --no-attach 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"; CALLS="$(cat "$FAKE_CALLS")"
}

# (RESOLVE-REACT-SUPERSEDE) react slings the successor of a settled id.
export FAKE_PR_ROWS='[]'
run_react tk-pred
eq "$RC" "0" "(RESOLVE-REACT-SUPERSEDE) react resolves a settled id and slings"
grep -q 'sling tk-succ' <<< "$SLUNG" \
  && ok "(RESOLVE-REACT-SUPERSEDE) gc-proactive.sh is slung the live successor" \
  || bad "(RESOLVE-REACT-SUPERSEDE) slung the successor (slung: $SLUNG)"
grep -q 'sling tk-pred' <<< "$SLUNG" \
  && bad "(RESOLVE-REACT-SUPERSEDE) slung the settled predecessor" \
  || ok "(RESOLVE-REACT-SUPERSEDE) never slings the predecessor"

# (RESOLVE-REACT-PR) react slings the bead a PR number records, not the number.
export FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]'
run_react 615
eq "$RC" "0" "(RESOLVE-REACT-PR) react resolves a PR number and slings"
grep -q 'sling tk-prbead' <<< "$SLUNG" \
  && ok "(RESOLVE-REACT-PR) gc-proactive.sh is slung the bead recording the PR" \
  || bad "(RESOLVE-REACT-PR) slung the PR anchor (slung: $SLUNG)"
grep -qE 'sling 615( |$)' <<< "$SLUNG" \
  && bad "(RESOLVE-REACT-PR) slung the raw PR number" \
  || ok "(RESOLVE-REACT-PR) never slings the raw PR number"

# (RESOLVE-ENGAGE-SUPERSEDE) engage holds the successor's conversation.
export FAKE_PR_ROWS='[]' FAKE_CONV_SUBJ=tk-succ
run_engage tk-pred
eq "$RC" "0" "(RESOLVE-ENGAGE-SUPERSEDE) engage resolves a settled id and binds a sitting"
grep -q 'conversation tk-convE for tk-succ' <<< "$OUT" \
  && ok "(RESOLVE-ENGAGE-SUPERSEDE) the sitting holds the live successor's conversation" \
  || bad "(RESOLVE-ENGAGE-SUPERSEDE) sitting is on the successor (out: $OUT err: $ERR)"
grep -q 'tk-pred is closed and superseded' <<< "$ERR" \
  && ok "(RESOLVE-ENGAGE-SUPERSEDE) announces the redirect before spawning" \
  || bad "(RESOLVE-ENGAGE-SUPERSEDE) redirect announced (err: $ERR)"
grep -q 'bd update tk-convE --if-assignee human --assignee gc-toolkit/gc-toolkit.tk-convE' <<< "$CALLS" \
  && ok "(RESOLVE-ENGAGE-SUPERSEDE) binds the conversation to the sitting's alias, guarded on the queue" \
  || bad "(RESOLVE-ENGAGE-SUPERSEDE) bound the resolved bead's conversation (calls: $CALLS)"

# (RESOLVE-ENGAGE-PR) engage holds the conversation about the PR's bead.
export FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]' FAKE_CONV_SUBJ=tk-prbead
run_engage 615
eq "$RC" "0" "(RESOLVE-ENGAGE-PR) engage resolves a PR number and binds a sitting"
grep -q 'conversation tk-convE for tk-prbead' <<< "$OUT" \
  && ok "(RESOLVE-ENGAGE-PR) the sitting holds the conversation on the bead recording the PR" \
  || bad "(RESOLVE-ENGAGE-PR) sitting is on the PR anchor (out: $OUT err: $ERR)"
grep -q 'PR #615 -> tk-prbead' <<< "$ERR" \
  && ok "(RESOLVE-ENGAGE-PR) announces the PR match before spawning" \
  || bad "(RESOLVE-ENGAGE-PR) PR match announced (err: $ERR)"
unset FAKE_PR_ROWS FAKE_SLING CONV_STATE FAKE_CONV_SUBJ

# --- (SYNTAX) the shipped script still parses ---------------------------------
sh -n "$SCRIPT" 2>/dev/null && ok "(SYNTAX) gc-helm.sh parses as POSIX sh" || bad "(SYNTAX) sh -n failed"

echo ""
echo "gc-helm open: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
