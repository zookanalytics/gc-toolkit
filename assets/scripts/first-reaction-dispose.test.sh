#!/usr/bin/env bash
# Hermetic tests for first-reaction-dispose.sh — the exits a first reaction
# ends in, in the reaction-bead model, the stand-down it asks before it reacts,
# and the frozen no-reaction-bead call an in-flight mol-first-reaction molecule
# still makes. Runs the REAL script with a
# stubbed `gc`, a stubbed gc-helm.sh, a stubbed human-gate.sh, a stubbed
# gc-proactive.sh and a stubbed deferred-dispatch.sh (all reached through the
# tool-override env vars), so no
# live city, Dolt or network is touched. What each block guards is named above it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/first-reaction-dispose.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-first-reaction-dispose-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$2" in *"$1"*) ok "$3" ;; *) bad "$3 (missing '$1' in: $2)" ;; esac; }
hasnt() { case "$2" in *"$1"*) bad "$3 (unexpected '$1' in: $2)" ;; *) ok "$3" ;; esac; }
# before <a> <b> — the first log line matching <a> precedes the first matching <b>.
before() {
  local a b
  a=$(grep -n -m1 -- "$1" "$FAKE_LOG" | cut -d: -f1 || true)
  b=$(grep -n -m1 -- "$2" "$FAKE_LOG" | cut -d: -f1 || true)
  { [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; } \
    && ok "$3" || bad "$3 ('$1' at ${a:-none}, '$2' at ${b:-none})"
}

[ -x "$SCRIPT" ] && ok "first-reaction-dispose.sh present and executable" \
                 || bad "first-reaction-dispose.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- stubs --------------------------------------------------------------------
# One ORDER log across every stub: the landed proof must be written after the
# act, so its presence proves the write-back landed.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 ${2:-}" in
  "bd update")
    printf 'UPDATE %s\n' "$*" >> "$FAKE_LOG"
    # FAKE_PROACTIVE_STAMP_FAILS models the frozen path's landed-proof write
    # failing: the update carrying gc.proactive_reaction=1 exits non-zero.
    # FAKE_NOTES_FAILS models a notes append that does not land, and
    # FAKE_CLOSE_FAILS a close of the reaction bead the store refuses.
    case " $* " in
      *" gc.proactive_reaction=1 "*) [ -n "${FAKE_PROACTIVE_STAMP_FAILS:-}" ] && exit 1 ;;
      *" --append-notes "*) [ -n "${FAKE_NOTES_FAILS:-}" ] && exit 1 ;;
      *" --status=closed "*) [ -n "${FAKE_CLOSE_FAILS:-}" ] && exit 1 ;;
    esac
    # Model read-after-write for gc.recommended_formula so the script's read-back
    # guard can be exercised: apply the set/unset to the state file a later
    # `bd show` reflects. FAKE_DROP_RECO models a silent drop — the update still
    # reports success but the key does not move: =once drops only the first
    # recommendation write (so a retry lands), any other value drops them all.
    _prev=""; _reco_set=""; _reco_unset=""
    for _a in "$@"; do
      case "$_prev" in
        --set-metadata)   case "$_a" in
                            gc.recommended_formula=*) _reco_set="${_a#gc.recommended_formula=}" ;;
                            # Intake's marker, read back by the script before it
                            # releases the bead. FAKE_DROP_PLACEMENT models a
                            # silent drop: =once drops the first write only.
                            placement=*)
                              case "${FAKE_DROP_PLACEMENT:-}" in
                                once) if [ -e "$FAKE_STATE.placement-dropped" ]; then printf '%s' "${_a#placement=}" > "$FAKE_STATE.placement"
                                      else : > "$FAKE_STATE.placement-dropped"; fi ;;
                                ?*)   : ;;
                                *)    printf '%s' "${_a#placement=}" > "$FAKE_STATE.placement" ;;
                              esac ;;
                            # The notice the real deferred-dispatch.sh records,
                            # which its own notice listing reads back below.
                            gc.notify_when_ready=*) printf '%s' "${_a#gc.notify_when_ready=}" > "$FAKE_STATE.notice" ;;
                          esac ;;
        --unset-metadata) case "$_a" in
                            gc.recommended_formula) _reco_unset=1 ;;
                            gc.notify_when_ready) rm -f "$FAKE_STATE.notice" ;;
                          esac ;;
        # An emergency's P0, read back before its route. FAKE_DROP_PRIORITY
        # models a priority write that reports success and does not move.
        --priority) [ -n "${FAKE_DROP_PRIORITY:-}" ] || printf '%s' "$_a" > "$FAKE_STATE.priority" ;;
      esac
      _prev="$_a"
    done
    if [ -n "$_reco_set" ] || [ -n "$_reco_unset" ]; then
      _drop=""
      case "${FAKE_DROP_RECO:-}" in
        once) [ -e "$FAKE_STATE.dropped" ] || { _drop=1; : > "$FAKE_STATE.dropped"; } ;;
        ?*)   _drop=1 ;;
      esac
      if [ -z "$_drop" ]; then
        [ -n "$_reco_set" ]   && printf '%s' "$_reco_set" > "$FAKE_STATE"
        [ -n "$_reco_unset" ] && : > "$FAKE_STATE"
      fi
    fi ;;
  "bd create")
    printf 'CREATE %s\n' "$*" >> "$FAKE_LOG"
    [ -n "${FAKE_CREATE_FAILS:-}" ] && { printf '{"error":"nope"}\n'; exit 0; }
    printf '[{"id":"%s"}]\n' "${FAKE_NEW_ID:-tk-newblk}" ;;
  "rig list")
    # A rig whose path has no .beads dir leaves the pin unresolved, which is
    # what every assertion below the PIN block expects.
    printf '{"rigs":[{"name":"gc-toolkit","path":"%s","prefix":"tk"}]}\n' "${FAKE_RIG_PATH:-/nonexistent-rig}" ;;
  "bd show")
    printf 'SHOW %s\n' "$*" >> "$FAKE_LOG"
    # FAKE_SHOW_UNREADABLE_AFTER_UPDATE models a subject that becomes unreadable
    # once a write has landed: the initial subject read (before any UPDATE) sees
    # the fixture, and every read-back after it returns the non-array error
    # object gc bd show emits for a subject it cannot resolve. This is the read
    # the guard must not mistake for a proven-absent key.
    if [ -n "${FAKE_SHOW_UNREADABLE_AFTER_UPDATE:-}" ] && grep -q '^UPDATE ' "$FAKE_LOG" 2>/dev/null; then
      printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'
      exit 0
    fi
    # Overlay the current gc.recommended_formula state (set by bd update above)
    # onto the fixture, so a read-back sees what the last write actually did.
    # Intake's placement marker and an emergency's priority overlay the same way.
    _base="${FAKE_SHOW_JSON:-$DEFAULT_SHOW}"
    _reco="$(cat "$FAKE_STATE" 2>/dev/null || printf '')"
    _placement="$(cat "$FAKE_STATE.placement" 2>/dev/null || printf '')"
    _priority="$(cat "$FAKE_STATE.priority" 2>/dev/null || printf '')"
    if [ -n "$_reco" ]; then
      _shown=$(printf '%s' "$_base" | jq -c --arg v "$_reco" '.[0].metadata = ((.[0].metadata // {}) + {"gc.recommended_formula": $v})' 2>/dev/null || printf '%s\n' "$_base")
    else
      _shown=$(printf '%s' "$_base" | jq -c '.[0].metadata = ((.[0].metadata // {}) | del(.["gc.recommended_formula"]))' 2>/dev/null || printf '%s\n' "$_base")
    fi
    [ -n "$_placement" ] && _shown=$(printf '%s' "$_shown" | jq -c --arg v "$_placement" '.[0].metadata.placement = $v' 2>/dev/null || printf '%s' "$_shown")
    [ -n "$_priority" ] && _shown=$(printf '%s' "$_shown" | jq -c --argjson v "$_priority" '.[0].priority = $v' 2>/dev/null || printf '%s' "$_shown")
    # The notice the real deferred-dispatch.sh records, as the store returns
    # it: its retire re-reads the bead and clears only a record that still
    # names the agent it notified.
    _notice_rec="$(cat "$FAKE_STATE.notice" 2>/dev/null || printf '')"
    if [ -n "$_notice_rec" ]; then
      _shown=$(printf '%s' "$_shown" | jq -c --arg v "$_notice_rec" '.[0].metadata = ((.[0].metadata // {}) + {"gc.notify_when_ready": $v})' 2>/dev/null || printf '%s' "$_shown")
    fi
    # The release's --assign, which the helm stub records: the bead is open and
    # held by that agent from then on.
    _assignee="$(cat "$FAKE_STATE.assignee" 2>/dev/null || printf '')"
    [ -n "$_assignee" ] && _shown=$(printf '%s' "$_shown" | jq -c --arg v "$_assignee" '.[0].assignee = $v | .[0].status = "open"' 2>/dev/null || printf '%s' "$_shown")
    printf '%s\n' "$_shown" ;;
  "bd list")
    printf 'LIST %s\n' "$*" >> "$FAKE_LOG"
    case " $* " in
      *" --has-metadata-key gc.notify_when_ready "*)
        # The notice recorded above, as the real deferred-dispatch.sh lists it.
        # Every listing carries it, and a --ready one only while
        # FAKE_SUBJECT_READY says bd reports the bead ready.
        _notice="$(cat "$FAKE_STATE.notice" 2>/dev/null || printf '')"
        case " $* " in *" --ready "*) [ -n "${FAKE_SUBJECT_READY:-}" ] || _notice="" ;; esac
        if [ -n "$_notice" ]; then
          jq -cn --arg a "$_notice" --arg who "$(cat "$FAKE_STATE.assignee" 2>/dev/null)" \
            '[{id: "tk-sub", status: "open", assignee: $who, metadata: {"gc.notify_when_ready": $a}}]'
        else
          printf '[]\n'
        fi ;;
      *) printf '%s\n' "${FAKE_LIST_JSON:-[]}" ;;
    esac ;;
  "mail send")
    # The --json answer gascity's doMailSendJSON gives. A send whose dedup key
    # matches a message still in the mailbox saves nothing, requests no turn
    # and reports already_done. Any other send saves the message and then
    # requests the turn, reporting `notified` only when that succeeds.
    # FAKE_MAIL_NUDGE_FAILS fails the request, which the real command reports
    # on stderr while it still exits 0.
    printf 'MAIL %s\n' "$*" >> "$FAKE_LOG"
    [ -n "${FAKE_MAIL_FAILS:-}" ] && exit 1
    _prev=""; _key=""
    for _a in "$@"; do [ "$_prev" = "--dedup" ] && _key="$_a"; _prev="$_a"; done
    if [ -n "$_key" ] && grep -qxF -- "$_key" "$FAKE_STATE.mailbox" 2>/dev/null; then
      printf '%s\n' '{"ok":true,"action":"send","count":0,"already_done":true}'; exit 0
    fi
    printf '%s\n' "$_key" >> "$FAKE_STATE.mailbox"
    if [ -n "${FAKE_MAIL_NUDGE_FAILS:-}" ]; then
      echo "gc mail send: nudge failed: fake nudge-store failure" >&2
      printf '%s\n' '{"ok":true,"action":"send","count":1}'; exit 0
    fi
    printf '%s\n' '{"ok":true,"action":"send","count":1,"notified":true}' ;;
  "session nudge")
    printf 'NUDGE %s\n' "$*" >> "$FAKE_LOG"
    if [ -n "${FAKE_NUDGE_FAILS:-}" ]; then echo "gc session nudge: fake nudge failure" >&2; exit 1; fi ;;
  "bd dep")
    printf 'DEP %s\n' "$*" >> "$FAKE_LOG"
    # `dep list --json` answers with what the store holds AFTER the helm call.
    # `dep add` writes one positional edge, or every line `--file -` reads,
    # which bd commits as one transaction, so the first edge it refuses lands
    # none of them. Each landed edge is logged as EDGE <from> <to> <type>.
    # FAKE_DEP_FAILS refuses every add, the close exit's hold that did not land,
    # and FAKE_DEP_REFUSES refuses an edge onto that bead. FAKE_DEP_PASS is a
    # command the stub runs after each add, the deferred-dispatch pass running
    # right after the write.
    case "${3:-}" in
      add)
        case " $* " in
          *" --file - "*)
            _in=$(cat)
            printf '%s\n' "$_in" | sed 's/^/DEPFILE /' >> "$FAKE_LOG"
            _edges=$(printf '%s\n' "$_in" | jq -r '"\(.from) \(.to) \(.type // "blocks")"') ;;
          *)
            _type=blocks; _prev=""
            for _a in "$@"; do
              case "$_a" in --type=*) _type=${_a#--type=} ;; esac
              case "$_prev" in -t|--type) _type=$_a ;; esac
              _prev=$_a
            done
            _edges="$4 $5 $_type" ;;
        esac
        _rc=0
        [ -n "${FAKE_DEP_FAILS:-}" ] && _rc=1
        if [ -n "${FAKE_DEP_REFUSES:-}" ] && printf '%s\n' "$_edges" | awk -v r="$FAKE_DEP_REFUSES" '$2 == r { found = 1 } END { exit !found }'; then
          _rc=1
        fi
        [ "$_rc" -eq 0 ] && printf '%s\n' "$_edges" | sed 's/^/EDGE /' >> "$FAKE_LOG"
        [ -z "${FAKE_DEP_PASS:-}" ] || "$FAKE_DEP_PASS"
        exit "$_rc" ;;
      list) printf '%s\n' "${FAKE_DEPS_JSON:-[]}" ;;
    esac ;;
  "bd close") printf 'CLOSE %s\n' "$*" >> "$FAKE_LOG" ;;
  "sling "*) printf 'SLING %s\n' "$*" >> "$FAKE_LOG"
    # FAKE_SLING_RC is the exit gc sling returns: 3 is its live-workflow
    # conflict, the only code it exits on a bead a workflow already drives.
    [ -n "${FAKE_SLING_FAILS:-}" ] && exit 1
    [ -n "${FAKE_SLING_RC:-}" ] && exit "$FAKE_SLING_RC" ;;
  "formula show")
    printf 'FORMULA %s\n' "$*" >> "$FAKE_LOG"
    # A recommended mol either resolves or it does not; FAKE_FORMULA_MISSING lists
    # names this run must treat as unresolvable, so the ruling exit's probe refuses
    # a typo the way the live `gc formula show` would (exit 1 on a name it cannot
    # load). Any other name falls through to the default success below.
    for _m in ${FAKE_FORMULA_MISSING:-}; do [ "${3:-}" = "$_m" ] && exit 1; done ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

cat > "$TMP/helm" <<'HELM'
#!/usr/bin/env bash
printf 'HELM %s\n' "$*" >> "$FAKE_LOG"
[ -n "${FAKE_HELM_FAILS:-}" ] && exit 4
# gc-helm.sh takeaway --release reads the bead's status, then writes status open
# and no assignee with no condition on that write. FAKE_UNTIL_PASS is a command
# the stub runs between the two, the deferred-dispatch pass running while the
# release is in flight, and each step is logged.
case " $* " in
  *" --release "*)
    if [ -n "${FAKE_UNTIL_PASS:-}" ]; then
      printf 'HELM release reads %s\n' "$2" >> "$FAKE_LOG"
      "$FAKE_UNTIL_PASS"
      printf 'HELM release writes %s --status=open --assignee=\n' "$2" >> "$FAKE_LOG"
    fi ;;
esac
# A release with --assign makes that agent the bead's assignee, which a later
# `bd show` reflects.
case " $* " in
  *" --release "*)
    _prev=""
    for _a in "$@"; do
      [ "$_prev" = "--assign" ] && printf '%s' "$_a" > "$FAKE_STATE.assignee"
      _prev="$_a"
    done ;;
esac
# Model gc-helm.sh takeaway --release retiring the pour stamp. The shared-state
# file stands in for gc.execution_routed_to; a run that does not opt in
# (FAKE_EXEC_ROUTED_FILE unset) is unchanged. The arm does not depend on this
# clear: a plain arm lands whether or not the stamp is set. FAKE_HELM_KEEPS_STAMP
# models a clear that does not land. gc-helm.sh then fails the release (exit 4)
# when the stamp is all that places the bead. That is a bead intake marked
# placement=pending, released with no route or assignee. Everywhere else it warns
# and exits 0.
case " $* " in
  *" --release "*)
    if [ -n "${FAKE_EXEC_ROUTED_FILE:-}" ]; then
      if [ -z "${FAKE_HELM_KEEPS_STAMP:-}" ]; then
        : > "$FAKE_EXEC_ROUTED_FILE"
      elif [ "$(cat "$FAKE_STATE.placement" 2>/dev/null)" = pending ]; then
        case " $* " in *" --route "*|*" --assign "*) ;; *) exit 4 ;; esac
      fi
    fi ;;
esac
exit 0
HELM
chmod +x "$TMP/helm"

# human-gate.sh files the human gate a ruling or recommend holds on and prints
# its id on stdout, as the real helper does. FAKE_GATE_FAILS models a gate that
# did not file; FAKE_GATE_NOID a helper that exits 0 and names no gate. A
# --retract call is logged and changes nothing.
cat > "$TMP/human-gate" <<'HG'
#!/usr/bin/env bash
printf 'GATE %s\n' "$*" >> "$FAKE_LOG"
case " $* " in *" --retract "*) exit 0 ;; esac
[ -n "${FAKE_GATE_FAILS:-}" ] && exit 1
[ -n "${FAKE_GATE_NOID:-}" ] && exit 0
printf '%s\n' "${FAKE_GATE_ID:-tk-gate1}"
HG
chmod +x "$TMP/human-gate"

cat > "$TMP/proactive" <<'PA'
#!/usr/bin/env bash
printf 'PROACTIVE %s\n' "$*" >> "$FAKE_LOG"
# `assignable` answers for a named agent addressed by assignee; FAKE_AGENT_GONE
# models an agent the roster does not carry. Every other verb is `deliverable`.
if [ "$1" = "assignable" ]; then
  [ -n "${FAKE_AGENT_GONE:-}" ] && { printf 'no: no agent is registered as %s in this city\n' "$2"; exit 1; }
  printf 'yes: %s is a registered, unsuspended named session\n' "$2"
  exit 0
fi
[ -n "${FAKE_POOL_DEAD:-}" ] && { printf 'no: no agent is registered at %s in this city\n' "$2"; exit 1; }
printf 'yes: %s is registered and unsuspended\n' "$2"
exit 0
PA
chmod +x "$TMP/proactive"

cat > "$TMP/deferred" <<'DD'
#!/usr/bin/env bash
printf 'DEFERRED %s\n' "$*" >> "$FAKE_LOG"
# FAKE_DEFERRED_FAILS models an arm the real script refuses: it names why on
# stderr and exits 1.
[ -n "${FAKE_DEFERRED_FAILS:-}" ] && { echo "deferred-dispatch: arm: $2 is already dispatched (fake refusal)" >&2; exit 1; }
# deferred-dispatch.sh arm keys on gc.routed_to and status, NOT on
# gc.execution_routed_to — that stamp is a finished pour's provenance, not a live
# queue. A first-reaction subject carries only the stamp and no gc.routed_to, so
# a plain arm lands whether or not the release cleared the stamp. The stub arms
# unconditionally, which is exactly that behavior.
exit 0
DD
chmod +x "$TMP/deferred"

# An emergency's check reads the subject's repository from its rig checkout and
# main's checks from GitHub. FAKE_ORIGIN_URL is the origin the checkout names
# (unset: no origin). FAKE_GH picks GitHub's answer: red (a failing check run),
# status-red (only a legacy commit status fails), green (passing, cancelled and
# still-running runs, none red), down (gh answers nothing), hang (gh stalls on
# the check runs until something kills it). red-page2 and status-red-page2 put
# the failure on a second page, which gh prints only under --paginate, as one
# more JSON object after the first page's.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<'GIT'
case "$*" in
  *"remote get-url origin"*) [ -n "${FAKE_ORIGIN_URL:-}" ] || exit 2; printf '%s\n' "$FAKE_ORIGIN_URL" ;;
  *) exit 1 ;;
esac
GIT
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gh" <<'GH'
printf 'GH %s\n' "$*" >> "$FAKE_LOG"
[ "${FAKE_GH:-}" = down ] && exit 1
PAGINATE=""; case " $* " in *" --paginate "*) PAGINATE=1 ;; esac
GREEN_RUNS='{"total_count":3,"check_runs":[{"name":"lint","status":"completed","conclusion":"success","head_sha":"abcdef1234567890"},{"name":"test-linux","status":"completed","conclusion":"cancelled","head_sha":"abcdef1234567890"},{"name":"test-macos","status":"in_progress","conclusion":null,"head_sha":"abcdef1234567890"}]}'
GREEN_STATUS='{"state":"success","sha":"abcdef1234567890","statuses":[]}'
case "${2:-}" in
  repos/*/check-runs*)
    case "${FAKE_GH:-}" in
      hang) exec sleep 30 ;;
      red) printf '%s\n' '{"total_count":2,"check_runs":[{"name":"lint","status":"completed","conclusion":"success","head_sha":"abcdef1234567890"},{"name":"test-macos","status":"completed","conclusion":"failure","head_sha":"abcdef1234567890"}]}' ;;
      red-page2) printf '%s\n' "$GREEN_RUNS"
                 [ -z "$PAGINATE" ] || printf '%s\n' '{"total_count":4,"check_runs":[{"name":"test-e2e","status":"completed","conclusion":"timed_out","head_sha":"abcdef1234567890"}]}' ;;
      *)   printf '%s\n' "$GREEN_RUNS" ;;
    esac ;;
  repos/*/status*)
    case "${FAKE_GH:-}" in
      status-red) printf '%s\n' '{"state":"failure","sha":"abcdef1234567890","statuses":[{"context":"ci/legacy","state":"failure"}]}' ;;
      status-red-page2) printf '%s\n' '{"state":"failure","sha":"abcdef1234567890","statuses":[{"context":"ci/docs","state":"success"}]}'
                        [ -z "$PAGINATE" ] || printf '%s\n' '{"state":"failure","sha":"abcdef1234567890","statuses":[{"context":"ci/legacy","state":"error"}]}' ;;
      *)          printf '%s\n' "$GREEN_STATUS" ;;
    esac ;;
  repos/*) printf '%s\n' '{"default_branch":"main"}' ;;
  *) exit 1 ;;
esac
GH
chmod +x "$TMP/bin/git" "$TMP/bin/gh"

export PATH="$TMP/bin:$PATH"
export FAKE_LOG="$TMP/log"
export FAKE_STATE="$TMP/reco_state"
# The subject fixture when a test sets no FAKE_SHOW_JSON. Held in a variable
# because a literal `{}` inside a ${var:-default} confuses brace matching and
# yields malformed JSON. The default subject is a member of an epic, which intake
# admits to a pool; UNPLACED is the same subject with no parent, which intake
# holds for placement. MEMBER splices the membership into a fixture of a test's
# own.
MEMBER='"parent":"tk-epic","dependencies":[{"id":"tk-epic","dependency_type":"parent-child","status":"open"}]'
UNPLACED='[{"id":"tk-sub","metadata":{}}]'
export DEFAULT_SHOW='[{"id":"tk-sub",'"$MEMBER"',"metadata":{}}]'
export GC_HELM_TOOL="$TMP/helm" GC_DEFERRED_DISPATCH_TOOL="$TMP/deferred" \
       GC_PROACTIVE_TOOL="$TMP/proactive" GC_HUMAN_GATE_TOOL="$TMP/human-gate"

R="tk-react"   # the reaction bead the worker holds

# Reset per run, then seed the recommendation state from the fixture so the first
# `bd show` matches FAKE_SHOW_JSON and later writes mutate it from there.
run() {
  : > "$FAKE_LOG"; rm -f "$FAKE_STATE.dropped" "$FAKE_STATE.placement" "$FAKE_STATE.placement-dropped" "$FAKE_STATE.priority" \
    "$FAKE_STATE.assignee" "$FAKE_STATE.notice" "$FAKE_STATE.mailbox"
  printf '%s' "${FAKE_SHOW_JSON:-$DEFAULT_SHOW}" \
    | jq -r '(.[0].metadata // {})["gc.recommended_formula"] // ""' > "$FAKE_STATE" 2>/dev/null || : > "$FAKE_STATE"
  RC=0; OUT="$("$SCRIPT" "$@" 2>"$TMP/err")" || RC=$?; ERR="$(cat "$TMP/err")"; LOG="$(cat "$FAKE_LOG")";
}

# ── Usage: refuse before writing ─────────────────────────────────────────────
# Every refusal below happens with an empty log: a disposition that cannot be
# performed must not leave a half-written bead behind.
run tk-sub --disposition actionable --takeaway "t" --reaction-bead "$R"
eq "$RC" "2" "(ARGS) a disposition with no --reason is refused"
eq "$LOG" "" "(ARGS) …and nothing was written"
has "silent classification" "$ERR" "(ARGS) …and the refusal says why the reason is required"

run tk-sub --disposition sideways --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "2" "(ARGS) an unknown disposition is refused"

run tk-sub --disposition actionable --reason "r" --reaction-bead "$R"
eq "$RC" "2" "(ARGS) a disposition with no --takeaway is refused"

run --disposition actionable --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "2" "(ARGS) no bead id is refused"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --reaction-bead tk-sub
eq "$RC" "2" "(ARGS) the reaction bead cannot be the subject itself"
eq "$LOG" "" "(ARGS) …and nothing was written"

# The reaction-bead model has no superseded exit: a first reaction never closes
# a bead, and a confident no-op is the close exit's validating closer.
run tk-sub --disposition superseded --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "2" "(ARGS) superseded is not an exit — a reaction never closes its subject"

# ── actionable: the bead is work, so hand it to a pool ───────────────────────
#   (ACT)      the release hands the bead on, and the landed proof names R
#   (ACTORDER) the landed proof is stamped AFTER the act
#   (ACTCLOSE) R is closed once the write-back lands
#   (ACTROUTE) the release carries the route, so the bead lands in a pool queue
#   (ACTRIG)   the target defaults from GC_RIG, and fails closed without one
run tk-sub --disposition actionable --reason "states a done condition and a branch" \
    --takeaway "routed to the polecat pool" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(ACT) an actionable disposition succeeds"
has "HELM takeaway tk-sub routed to the polecat pool --by proactive --release --route gc-toolkit/gc-toolkit.polecat" \
    "$LOG" "(ACTROUTE) the release hands the bead to the pool in one call"
# The headline's own disposition. Work handed to a pool is moving, not waiting,
# and the sitting says so where it stamps the sentence — nothing downstream can
# tell a settled headline from a park after the fact.
has "--no-wait" "$LOG" "(ACTROUTE) …and says nothing is waiting on it"
has "gc.reacted_by=$R" "$LOG" "(ACT) the landed proof names the reaction bead"
before '^HELM takeaway' 'gc.reacted_by' "(ACTORDER) the landed proof is stamped after the act"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" "$LOG" \
    "(ACTCLOSE) the reaction bead is closed, recording its outcome and the no-op work record a triage bead owes"
before 'gc.reacted_by' "UPDATE bd update $R" "(ACTCLOSE) …after the landed proof"
hasnt "gc.first_reaction" "$LOG" "(ACT) no attempt record is written on the subject"
hasnt "gc.proactive_reaction" "$LOG" "(ACT) …and no legacy landed proof: R's identity is the key"
has "disposed as actionable (gc-toolkit/gc-toolkit.polecat)" "$OUT" "(ACT) …and the run reports the pool it routed to"
LOG_ACT="$LOG"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --waiting-on tk-other --reaction-bead "$R"
eq "$RC" "2" "(ACT) actionable refuses the other exits' flags"

# (ACTPOOL) a route to a pool nothing runs is worse than a visit: the bead
# would be open, unassigned and offered to nobody.
has "PROACTIVE deliverable gc-toolkit/gc-toolkit.polecat tk-sub" "$LOG_ACT" \
    "(ACTPOOL) the exit asks whether the pool can claim this bead before handing over"
export FAKE_POOL_DEAD=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.nosuch --reaction-bead "$R"
eq "$RC" "2" "(ACTPOOL) a pool that cannot claim refuses the exit"
hasnt "HELM" "$LOG" "(ACTPOOL) …and the bead is not released"
hasnt "UPDATE bd update $R" "$LOG" "(ACTPOOL) …and the reaction bead stays open"
has "address it with --assign" "$ERR" "(ACTPOOL) …and the refusal names the named-agent address before the operator"
has "only when the next move is the operator's" "$ERR" "(ACTPOOL) …keeping the operator's exits for the operator's own move"
unset FAKE_POOL_DEAD

: > "$FAKE_LOG"; RC=0
OUT="$(GC_RIG=gc-toolkit "$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" --reaction-bead "$R" 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(ACTRIG) with GC_RIG set, the pool target needs no flag"
has "--route gc-toolkit/gc-toolkit.polecat" "$LOG" "(ACTRIG) …and defaults to this rig's polecat pool"

: > "$FAKE_LOG"; RC=0
ERR="$(env -u GC_RIG "$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" --reaction-bead "$R" 2>&1 >/dev/null)" || RC=$?
eq "$RC" "2" "(ACTRIG) with no GC_RIG and no --route it fails closed"
eq "$(cat "$FAKE_LOG")" "" "(ACTRIG) …and writes nothing"
has "routes to nobody" "$ERR" "(ACTRIG) …and names what a bare target would cost"

# ── actionable --assign: work that is a named agent's own ────────────────────
# A town-repo edit is mechanik's direct edit, and mechanik is a named agent,
# which the pack addresses by assignee (docs/deferred-dispatch.md), so the exit
# releases the bead TO it as its assignee instead of routing it to a pool.
#   (ACTASSIGN)  the release carries --assign, not --route, and still says
#                nothing waits; the run names the agent, and the reaction
#                bead closes once the landed proof is stamped
#   (ACTASSIGN)  the exit asks whether the agent's hook would offer the bead,
#                and does not ask the pool question
#   (ASSIGNNO)   an agent that cannot be handed the bead refuses the exit
#   (ASSIGNBOTH) --route and --assign together are refused
#   (ASSIGNRIG)  a named agent needs no GC_RIG to qualify it
run tk-sub --disposition actionable --reason "the remedy is a city.toml edit, mechanik's direct edit" \
    --takeaway "city.toml edit routed to mechanik" --assign gc-toolkit.mechanik --reaction-bead "$R"
eq "$RC" "0" "(ACTASSIGN) an actionable disposition addressed to a named agent succeeds"
has "gc.reacted_by=$R" "$LOG" "(ACTASSIGN) the landed proof names the reaction bead"
has "disposed as actionable (gc-toolkit.mechanik)" "$OUT" "(ACTASSIGN) …and the run names the agent it went to"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" "$LOG" \
    "(ACTASSIGN) …and the reaction bead closes"
has "HELM takeaway tk-sub city.toml edit routed to mechanik --by proactive --release --assign gc-toolkit.mechanik --no-wait" \
    "$LOG" "(ACTASSIGN) the release hands the bead to the agent as its assignee, moving, in one call"
hasnt "--route" "$LOG" "(ACTASSIGN) …and stamps no pool route beside the assignee"
has "PROACTIVE assignable gc-toolkit.mechanik tk-sub" "$LOG" "(ACTASSIGN) the exit asks whether the agent's hook would offer this bead"
hasnt "PROACTIVE deliverable" "$LOG" "(ACTASSIGN) …and does not ask the pool question of a named agent"
# (ACTNOTIFY) nothing wakes an idle named session for a new assignee, so the
# exit asks deferred-dispatch.sh to tell the agent it assigned: once the release
# has made it the assignee, and before the landed proof.
has "DEFERRED notify tk-sub --agent gc-toolkit.mechanik --reason first reaction: the remedy is a city.toml edit, mechanik's direct edit" \
    "$LOG" "(ACTNOTIFY) the exit asks deferred-dispatch.sh to tell the agent about the bead"
before '^HELM takeaway' '^DEFERRED notify' "(ACTNOTIFY) …after the release makes the agent its assignee"
before '^DEFERRED notify' 'gc.reacted_by' "(ACTNOTIFY) …and before the landed proof"
hasnt "DEFERRED arm" "$LOG" "(ACTNOTIFY) …arming no sling for a named agent"

export FAKE_AGENT_GONE=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign mechanik
eq "$RC" "2" "(ASSIGNNO) an agent its hook could never reach refuses the exit"
has "PROACTIVE assignable mechanik tk-sub" "$LOG" "(ASSIGNNO) …on the agent's own answer"
hasnt "UPDATE" "$LOG" "(ASSIGNNO) …before anything is written to the bead"
hasnt "HELM" "$LOG" "(ASSIGNNO) …and the bead is not released"
has "exact qualified name" "$ERR" "(ASSIGNNO) …and the refusal names the address form"
unset FAKE_AGENT_GONE

run tk-sub --disposition actionable --reason "r" --takeaway "t" \
    --route gc-toolkit/gc-toolkit.polecat --assign gc-toolkit.mechanik
eq "$RC" "2" "(ASSIGNBOTH) --route beside --assign is refused"
eq "$LOG" "" "(ASSIGNBOTH) …and nothing was written"
has "not both" "$ERR" "(ASSIGNBOTH) …and the refusal says a bead takes one address"

: > "$FAKE_LOG"; RC=0
OUT="$(env -u GC_RIG "$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(ASSIGNRIG) with no GC_RIG, an --assign still lands"
has "--assign gc-toolkit.mechanik --no-wait" "$LOG" "(ASSIGNRIG) …because a named agent is addressed by its own name"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --then-assign gc-toolkit.mechanik
eq "$RC" "2" "(ASSIGNEXIT) actionable refuses --then-assign, the blocked exit's flag"
run tk-sub --disposition close --reason "r" --takeaway "t" --assign gc-toolkit.mechanik
eq "$RC" "2" "(ASSIGNEXIT) close refuses --assign: its closer is a pool"
run tk-sub --disposition ruling --reason "r" --takeaway "t" --assign gc-toolkit.mechanik
eq "$RC" "2" "(ASSIGNEXIT) ruling refuses --assign: it waits on the operator"
eq "$LOG" "" "(ASSIGNEXIT) …and nothing was written"
run tk-sub --disposition ruling --reason "r" --takeaway "t" --then-assign gc-toolkit.mechanik
eq "$RC" "2" "(ASSIGNEXIT) ruling refuses --then-assign: its wait is the operator's gate"
eq "$LOG" "" "(ASSIGNEXIT) …and no gate was filed"

: > "$FAKE_LOG"; RC=0
OUT="$("$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --dry-run 2>"$TMP/err")" || RC=$?
eq "$RC" "0" "(ASSIGNDRY) a dry run of the --assign exit succeeds"
has "would release tk-sub to named agent gc-toolkit.mechanik" "$OUT" "(ASSIGNDRY) …and names the agent it would hand the bead to"
has "would tell gc-toolkit.mechanik about tk-sub once bd reports it ready" "$OUT" "(ASSIGNDRY) …and that it would tell the agent"
hasnt "UPDATE" "$(cat "$FAKE_LOG")" "(ASSIGNDRY) …writing nothing"
hasnt "DEFERRED" "$(cat "$FAKE_LOG")" "(ASSIGNDRY) …and telling no one"

# (NOTIFYFAIL) a notice deferred-dispatch.sh neither sent nor recorded leaves the
# agent unwoken for its bead, so the exit fails before the landed proof and the
# reaction bead stays open for the re-run.
export FAKE_DEFERRED_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --reaction-bead "$R"
eq "$RC" "4" "(NOTIFYFAIL) an --assign whose notice did not land fails the exit"
has "gc-toolkit.mechanik was not told about it" "$ERR" "(NOTIFYFAIL) …saying the agent was not told"
has "fake refusal" "$ERR" "(NOTIFYFAIL) …with the tool's own reason"
has "HELM takeaway tk-sub" "$LOG" "(NOTIFYFAIL) …after the release, which stands"
hasnt "gc.reacted_by" "$LOG" "(NOTIFYFAIL) …with no landed proof"
hasnt "UPDATE bd update $R" "$LOG" "(NOTIFYFAIL) …and the reaction bead left open"
unset FAKE_DEFERRED_FAILS

# (NOTIFYTOOL) with no deferred-dispatch.sh to tell the agent, the exit cannot
# land, so it is refused before the first write.
GC_DEFERRED_DISPATCH_TOOL="$TMP/no-such-deferred-dispatch" \
    run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --reaction-bead "$R"
eq "$RC" "4" "(NOTIFYTOOL) --assign with no deferred-dispatch.sh is refused"
has "no-such-deferred-dispatch" "$ERR" "(NOTIFYTOOL) …naming the tool it looked for"
eq "$LOG" "" "(NOTIFYTOOL) …before anything is written"

# ── blocked: the wait is an edge, in one store ───────────────────────────────
#   (BLK)      the release carries the wait as --waiting-on
#   (BLKORDER) the landed proof follows the edge's verification
#   (BLKCROSS) a cross-store blocker is refused with the I1 remedy
#   (BLKSELF)  a bead never waits on itself
#   (BLKNEW)   --blocker files the missing bead and waits on it
#   (BLKDEDUP) --blocker-key reuses the bead a prior reaction filed
#   (BLKEDGE)  an edge that did not land fails the exit, so nothing records done
#   (BLKARM)   --then-route arms the dispatch that resumes the work
#   (BLKARMFAIL)  an arm that did not land fails the exit the same way, and a
#                 re-run arms, then stamps the landed proof, then closes R
#   (BLKARMTOOL)  --then-route with no deferred-dispatch.sh to arm it is
#                 refused before anything is written
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "waits on the schema migration" \
    --takeaway "held: schema migration first" --waiting-on tk-blk1 --reaction-bead "$R"
eq "$RC" "0" "(BLK) a blocked disposition succeeds"
has "--release --waiting-on tk-blk1" "$LOG" "(BLK) the wait rides the release as an edge"
hasnt "--route" "$LOG" "(BLK) …and a held bead is not also routed"
hasnt "--no-wait" "$LOG" "(BLK) …and the named wait is not also called settled"
has "gc.reacted_by=$R" "$LOG" "(BLK) the landed proof is stamped"
before '^DEP bd dep list' 'gc.reacted_by' "(BLKORDER) …after the edge is verified"
has "UPDATE bd update $R" "$LOG" "(BLK) …and the reaction bead is closed"
has "disposed as blocked (tk-blk1)" "$OUT" "(BLK) …and the run reports the bead it waits on"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on ra-foreign --reaction-bead "$R"
eq "$RC" "2" "(BLKCROSS) a blocker in another store is refused"
eq "$LOG" "" "(BLKCROSS) …and nothing was written"
has "holds nothing" "$ERR" "(BLKCROSS) …because the edge would report success and hold nothing"
has "store that names ra-foreign" "$ERR" "(BLKCROSS) …and the refusal names the remedy"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-sub --reaction-bead "$R"
eq "$RC" "2" "(BLKSELF) a bead cannot wait on itself"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "2" "(BLK) blocked with no wait at all is refused"
has "prose about it holds nothing" "$ERR" "(BLK) …and the refusal says why"

export FAKE_NEW_ID=tk-filed FAKE_DEPS_JSON='[{"id":"tk-filed"}]' FAKE_LIST_JSON='[]'
run tk-sub --disposition blocked --reason "nothing tracks the migration yet" \
    --takeaway "held: the migration is now filed" --blocker "Migrate the seed schema" --blocker-key migration --reaction-bead "$R"
eq "$RC" "0" "(BLKNEW) a wait that is not a bead yet is filed"
has "CREATE bd create -t task --title Migrate the seed schema" "$LOG" "(BLKNEW) …as a bead"
has "gc.blocker_key" "$LOG" "(BLKNEW) …carrying the dedup key"
case "$(grep -c '^CREATE' "$FAKE_LOG")" in
  1) ok "(BLKNEW) …filed in one write, so the key cannot land without the bead" ;;
  *) bad "(BLKNEW) the blocker took more than one create: $LOG" ;;
esac
has "--waiting-on tk-filed" "$LOG" "(BLKNEW) …and the subject waits on it"
run tk-sub --disposition blocked --reason "r" --takeaway "t" \
    --blocker "$(printf 'x%.0s' $(seq 1 501))" --reaction-bead "$R"
eq "$RC" "2" "(BLKNEW) a blocker title past bd's 500-byte cap is refused here"
has "cap is 500" "$ERR" "(BLKNEW) …by its actual cause, not 'no id returned'"

export FAKE_LIST_JSON='[{"id":"tk-already"}]' FAKE_DEPS_JSON='[{"id":"tk-already"}]'
run tk-sub --disposition blocked --reason "same cause as last time" \
    --takeaway "held: same migration" --blocker "Migrate the seed schema" --blocker-key migration --reaction-bead "$R"
eq "$RC" "0" "(BLKDEDUP) a repeat of one cause succeeds"
hasnt "CREATE" "$LOG" "(BLKDEDUP) …and files no second bead"
has "--waiting-on tk-already" "$LOG" "(BLKDEDUP) …it waits on the one already filed"
unset FAKE_LIST_JSON FAKE_NEW_ID

export FAKE_DEPS_JSON='[]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --reaction-bead "$R"
eq "$RC" "4" "(BLKEDGE) a dropped edge fails the verb — the bead is recorded as waiting and nothing holds it"
has "not held by tk-blk1" "$ERR" "(BLKEDGE) …the missing edge is named"
has "gc bd dep add tk-sub tk-blk1 -t blocks" "$ERR" "(BLKEDGE) …with the repair spelled out"
has "parked on prose alone" "$ERR" "(BLKEDGE) …and the failure says what it costs"
has "a re-run resumes" "$ERR" "(BLKEDGE) …and that a re-run resumes, since no landed proof was stamped"
hasnt "gc.reacted_by" "$LOG" "(BLKEDGE) …the landed proof is NOT stamped over an unheld bead"
hasnt "UPDATE bd update $R" "$LOG" "(BLKEDGE) …and the reaction bead is NOT closed"
hasnt "disposed as blocked" "$OUT" "(BLKEDGE) …and the run does not report a disposition"

# A partial landing is still a failure: one edge holds, the other does not, and
# the failure names only the missing one.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --waiting-on tk-blk2 --reaction-bead "$R"
eq "$RC" "4" "(BLKEDGE) one of two edges landing is still a failed exit"
has "not held by tk-blk2" "$ERR" "(BLKEDGE) …naming only the one that missed"
hasnt "not held by tk-blk1" "$ERR" "(BLKEDGE) …and not the one that landed"

# The arm is downstream of the hold: no edge, no deferred dispatch.
export FAKE_DEPS_JSON='[]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(BLKEDGE) a dropped edge fails before the deferred dispatch is armed"
hasnt "DEFERRED arm" "$LOG" "(BLKEDGE) …so nothing is armed on a wait that does not exist"

# A first-reaction subject can carry the pour stamp gc.execution_routed_to. The
# blocked exit releases it (gc-helm.sh --release retires that stamp as
# provenance) and arms a PLAIN deferred dispatch. deferred-dispatch's arm keys on
# gc.routed_to, not the execution stamp, and the subject carries no gc.routed_to,
# so the arm lands whether or not the release cleared the stamp. The stubs model
# that, so the arm is exercised against the real guard rather than a fixture no
# sling ever poured.
export FAKE_EXEC_ROUTED_FILE="$TMP/exec_routed"
printf 'gc-toolkit/gc-toolkit.proactive' > "$FAKE_EXEC_ROUTED_FILE"
export FAKE_SHOW_JSON='[{"id":"tk-sub",'"$MEMBER"',"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.proactive"}}]'
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" \
    "(BLKARM) --then-route arms the dispatch for when the wait lifts"
hasnt "--sling-arg" "$LOG" \
    "(BLKARM) …a plain arm, no --on — reconcile slings it even with the pour stamp set"
has "armed the dispatch to gc-toolkit/gc-toolkit.polecat" "$ERR" \
    "(BLKARM) …and the arm lands"
before '^DEFERRED arm' 'gc.reacted_by' "(BLKARM) …before the landed proof, which is the last write"

# Control: a release that leaves the pour stamp set still lets the plain arm land.
# The coupled surface is gc-helm.sh takeaway --release: on a bead nothing holds
# for placement, here a member its parent places, it WARNS on a surviving
# gc.execution_routed_to and returns 0 rather than failing, because no arm or
# reconcile guard reads that stamp. The stub returns 0 with the stamp still set to
# model exactly that path, so this control exercises the real release, not a state
# the real flow cannot reach — and dispose runs on to arm the plain dispatch.
printf 'gc-toolkit/gc-toolkit.proactive' > "$FAKE_EXEC_ROUTED_FILE"
export FAKE_HELM_KEEPS_STAMP=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(BLKARM) a surviving pour stamp does not fail the disposition"
has "armed the dispatch to gc-toolkit/gc-toolkit.polecat" "$ERR" \
    "(BLKARM) a stamp left set does NOT refuse the plain arm — provenance, not a live queue"
unset FAKE_HELM_KEEPS_STAMP

# Contract: the arm is downstream of a release that SUCCEEDED. A genuine release
# failure — not a surviving stamp gc-helm only warns on, but gc-helm exiting
# non-zero because a write it owed did not land — dies before the arm, so a bead
# whose disposition only half-wrote is never armed to auto-resume from that
# state, and no landed proof or closed R says otherwise.
export FAKE_HELM_FAILS=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(BLKARM) a genuine gc-helm release failure fails the disposition"
hasnt "DEFERRED arm" "$LOG" "(BLKARM) …and nothing is armed after a release that did not land"
hasnt "gc.reacted_by" "$LOG" "(BLKARM) …and the landed proof is not stamped"
hasnt "UPDATE bd update $R" "$LOG" "(BLKARM) …and the reaction bead is not closed"
unset FAKE_HELM_FAILS FAKE_EXEC_ROUTED_FILE FAKE_SHOW_JSON

# (BLKARMFAIL) The arm is part of the write-back the landed proof stands for. A
# bead held with no arm waits on its edge with nothing to route it once the wait
# lifts, and a closed R brings no re-offer to arm it later. So an arm that does
# not land fails the exit, as a missing edge does: no landed proof, R left open.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
FAKE_DEFERRED_FAILS=1 run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(BLKARMFAIL) an arm that did not land fails the exit"
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" "(BLKARMFAIL) …after the arm was tried"
has "nothing would route tk-sub once the wait lifts" "$ERR" "(BLKARMFAIL) …and the failure says what it costs"
has "already dispatched (fake refusal)" "$ERR" "(BLKARMFAIL) …carrying the cause the arm named"
has "a re-run resumes" "$ERR" "(BLKARMFAIL) …and that a re-run resumes, since no landed proof was stamped"
hasnt "gc.reacted_by" "$LOG" "(BLKARMFAIL) …the landed proof is NOT stamped"
hasnt "UPDATE bd update $R" "$LOG" "(BLKARMFAIL) …and the reaction bead stays open"
hasnt "disposed as blocked" "$OUT" "(BLKARMFAIL) …and the run does not report a disposition"

# The re-offered R re-runs the same call once the cause is cleared. The failed
# run left the headline and the hold on the subject and no landed proof, so
# nothing refuses the re-run: the arm lands, then the landed proof, then R closes.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{"gc.takeaway":"t","gc.takeaway_by":"proactive"}}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(BLKARMFAIL) the re-run after a failed arm succeeds"
has "armed the dispatch to gc-toolkit/gc-toolkit.polecat" "$ERR" "(BLKARMFAIL) …the arm lands"
before '^DEFERRED arm' 'gc.reacted_by' "(BLKARMFAIL) …then the landed proof"
before 'gc.reacted_by' "UPDATE bd update $R" "(BLKARMFAIL) …then the reaction bead closes"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" "$LOG" \
    "(BLKARMFAIL) …recording its outcome"
unset FAKE_SHOW_JSON

# (BLKARMTOOL) With no deferred-dispatch.sh to arm it, the exit cannot land, so
# it is refused before the first write.
GC_DEFERRED_DISPATCH_TOOL="$TMP/no-such-deferred-dispatch" \
    run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(BLKARMTOOL) --then-route with no deferred-dispatch.sh is refused"
has "no-such-deferred-dispatch" "$ERR" "(BLKARMTOOL) …naming the tool it looked for"
eq "$LOG" "" "(BLKARMTOOL) …before anything is written"
GC_DEFERRED_DISPATCH_TOOL="$TMP/no-such-deferred-dispatch" \
    run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --reaction-bead "$R"
eq "$RC" "0" "(BLKARMTOOL) a blocked exit that asks for no arm does not need the tool"
unset FAKE_DEPS_JSON

# (BLKROUTE) --then-route is held to the SAME roster test as --route: a target no
# pool runs is refused before anything is written, not silently armed to fail
# every reconcile pass. Its parse check only tests for a "/", which a copied
# `<rig>/<rig>.polecat` placeholder passes, so the roster probe is what catches it.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
export FAKE_POOL_DEAD=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.nosuchpool --reaction-bead "$R"
eq "$RC" "2" "(BLKROUTE) --then-route to a pool nothing runs is refused"
has "PROACTIVE deliverable gc-toolkit/gc-toolkit.nosuchpool tk-sub" "$LOG" \
    "(BLKROUTE) …the exit asks whether that pool can claim before arming"
hasnt "DEFERRED arm" "$LOG" "(BLKROUTE) …and nothing is armed to a target that would fail every reconcile pass"
unset FAKE_POOL_DEAD FAKE_DEPS_JSON

# (BLKASSIGN) a town-repo edit that must wait on a rig change is held on that
# change AND assigned to mechanik in the same release. An assigned bead reaches
# its agent's hook only once bd reports it ready, so the edge is the gate and no
# sling is armed: a deferred dispatch slings a pool, and a named agent is not
# one. What is armed is the notice that tells the agent when the wait lifts
# (BLKNOTIFY), since nothing else wakes an idle named session then.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "the comment can change only once the order lands" \
    --takeaway "held: city.toml comment waits on the order" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik \
    --reaction-bead "$R"
eq "$RC" "0" "(BLKASSIGN) a blocked disposition assigned to a named agent succeeds"
has "disposed as blocked (tk-blk1)" "$OUT" "(BLKASSIGN) the run still names the wait"
has "gc.reacted_by=$R" "$LOG" "(BLKASSIGN) …and the landed proof names the reaction bead"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" "$LOG" \
    "(BLKASSIGN) …which then closes"
has "--release --waiting-on tk-blk1 --assign gc-toolkit.mechanik" "$LOG" \
    "(BLKASSIGN) the wait and the assignee ride one release"
hasnt "--no-wait" "$LOG" "(BLKASSIGN) …and the named wait is not called settled"
hasnt "DEFERRED arm" "$LOG" "(BLKASSIGN) …and no sling is armed for a named agent"
has "PROACTIVE assignable gc-toolkit.mechanik tk-sub" "$LOG" "(BLKASSIGN) the exit asks whether the agent's hook would offer the bead"
has "DEFERRED notify tk-sub --agent gc-toolkit.mechanik --reason first reaction: the comment can change only once the order lands" \
    "$LOG" "(BLKNOTIFY) the exit asks deferred-dispatch.sh for the notice that tells the agent when the wait lifts"
before '^DEP bd dep list' '^DEFERRED notify' "(BLKNOTIFY) …once the hold is proven"
before '^DEFERRED notify' 'gc.reacted_by' "(BLKNOTIFY) …and before the landed proof"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --then-assign gc-toolkit.mechanik
eq "$RC" "2" "(BLKASSIGN) --then-route beside --then-assign is refused"
eq "$LOG" "" "(BLKASSIGN) …and nothing was written"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --assign gc-toolkit.mechanik
eq "$RC" "2" "(BLKASSIGN) blocked refuses --assign, the actionable exit's flag"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik --dry-run
eq "$RC" "0" "(BLKASSIGN) a dry run of the --then-assign exit succeeds"
has "would wait tk-sub on: tk-blk1, assigned to gc-toolkit.mechanik" "$OUT" "(BLKASSIGN) …and names the agent the held bead goes to"
has "would tell gc-toolkit.mechanik about tk-sub once bd reports it ready" "$OUT" "(BLKASSIGN) …and when the agent would be told"
hasnt "UPDATE" "$LOG" "(BLKASSIGN) …writing nothing"
hasnt "DEFERRED" "$LOG" "(BLKASSIGN) …and arming no notice"

export FAKE_DEFERRED_FAILS=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik --reaction-bead "$R"
eq "$RC" "4" "(NOTIFYFAIL) a --then-assign whose notice did not land fails the exit"
has "no notice was armed" "$ERR" "(NOTIFYFAIL) …saying nothing would tell the agent"
hasnt "gc.reacted_by" "$LOG" "(NOTIFYFAIL) …with no landed proof"
hasnt "UPDATE bd update $R" "$LOG" "(NOTIFYFAIL) …and the reaction bead left open"
unset FAKE_DEFERRED_FAILS
GC_DEFERRED_DISPATCH_TOOL="$TMP/no-such-deferred-dispatch" \
    run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik --reaction-bead "$R"
eq "$RC" "4" "(NOTIFYTOOL) --then-assign with no deferred-dispatch.sh is refused"
eq "$LOG" "" "(NOTIFYTOOL) …before anything is written"

export FAKE_AGENT_GONE=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit/gc-toolkit.witness
eq "$RC" "2" "(BLKASSIGN) a --then-assign agent that cannot be handed the bead is refused"
hasnt "HELM" "$LOG" "(BLKASSIGN) …and the bead is not released"
unset FAKE_AGENT_GONE FAKE_DEPS_JSON

# ── until: the bead's job ends when another bead lands ───────────────────────
# A problem in code another bead retires closes with the bead that retires the
# code. The deferred-dispatch pass closes a bead once its until targets have
# closed, and only a pure wait, so the exit writes the until edge and nothing
# that routes, arms, places or blocks the subject. The subject here is a plain
# bug with no parent, the one intake holds for placement on a pool exit.
#   (UNT)       the until edge is written, read back by its type, and the
#               release says nothing holds the subject; the reaction completes
#   (UNTORDER)  the release lands before the edge is written, the landed proof
#               after the edge reads back, and nothing after the edge releases
#               the subject or writes its status or assignee
#   (UNTPURE)   the pass's own read of the subject the exit left: waiting while
#               the target is open, owed with no live-work mark once it closes;
#               the blocked exit's subject is never selected at all
#   (UNTRACE)   the pass, run between the release's status read and its write
#               with the target already closed, finds nothing to close there,
#               and once the exit completes it reads the subject owed with no
#               live-work mark
#   (UNTMULTI)  two targets, one closed and one open, land in one write, so the
#               pass run right after it reads the subject waiting, never owed
#               on the closed target's edge alone
#   (UNTRETRY)  a write bd refuses lands no edge of the set, so the pass has
#               nothing to close, and the re-run writes the whole set
#   (UNTEDGE)   an edge that does not read back as until fails the exit after
#               the release, before the landed proof; a re-run over a landed
#               edge succeeds
#   (UNTCROSS)  a target in another store is refused, naming a person's close
#   (UNTARGS)   until takes --until only and needs one; no other exit takes it
#   (UNTDRY)    a dry run names the wait and writes nothing
#
# until_row prints the subject as the fake store holds it, as `bd list --json`
# lists it: the fixture with each metadata value written to it, and each edge
# that landed, an until edge or a --waiting-on blocks edge. until_reader
# answers until-resolved.sh's two reads with that row and UNTIL_STATUSES, so
# scan_subject is the pass's own selection and decision over it. The suite
# sources them, and so does the pass the helm stub runs inside a release, which
# closes the subject the way the pass's disposal does when its scan reads it
# owed.
cat > "$TMP/until-lib.sh" <<'LIB'
until_row() {
  local meta edges
  meta=$(grep '^UPDATE bd update tk-sub ' "$FAKE_LOG" | grep -o -- '--set-metadata [^ ]*' | sed 's/^--set-metadata //' \
    | jq -Rn '[inputs | capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}] | add // {}')
  edges=$({ awk '$1 == "EDGE" && $2 == "tk-sub" && $4 == "until" { print $3 "\tuntil" }' "$FAKE_LOG"
            grep '^HELM takeaway tk-sub ' "$FAKE_LOG" | grep -o -- '--waiting-on [^ ]*' | awk '{print $2 "\tblocks"}'; } \
    | jq -Rn '[inputs | split("\t") | {depends_on_id: .[0], type: .[1]}]')
  printf '%s' "$FAKE_SHOW_JSON" | jq -c --argjson m "$meta" --argjson e "$edges" \
    '.[0] | .metadata = ((.metadata // {}) + $m) | .dependencies = $e'
}
until_reader() {
  case " $* " in
    *" --id "*) printf '%s\n' "$UNTIL_STATUSES" ;;
    *) printf '[%s]\n' "$(until_row)" ;;
  esac
}
scan_subject() { ( export GC_RUN_LIB="$UNTIL_SCRIPTS/run-lib.stub.sh"; . "$UNTIL_SCRIPTS/until-resolved.sh"; until_scan until_reader ) || echo "until_scan exited $?"; }
LIB
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/until-pass" <<'PASS'
. "$UNTIL_LIB"
case "$(scan_subject | cut -f2)" in
  owed) printf 'UPDATE bd update tk-sub --status=closed --set-metadata gc.superseded_by=tk-retire\n' >> "$FAKE_LOG"
        printf 'UNTILPASS closes tk-sub\n' >> "$FAKE_LOG" ;;
  *)    printf 'UNTILPASS leaves tk-sub\n' >> "$FAKE_LOG" ;;
esac
PASS
chmod +x "$TMP/until-pass"
export UNTIL_LIB="$TMP/until-lib.sh" UNTIL_SCRIPTS="$HERE"
# shellcheck source=/dev/null  # written above
. "$UNTIL_LIB"

UNTIL_SUBJECT='[{"id":"tk-sub","status":"open","issue_type":"bug","assignee":"","metadata":{}}]'
export FAKE_SHOW_JSON="$UNTIL_SUBJECT" FAKE_DEPS_JSON='[{"id":"tk-retire","dependency_type":"until"}]'
run tk-sub --disposition until --reason "the file it reports on is retired whole by tk-retire" \
    --takeaway "closes once tk-retire retires its code" --until tk-retire --reaction-bead "$R"
eq "$RC" "0" "(UNT) an until disposition succeeds"
has 'DEPFILE {"from":"tk-sub","to":"tk-retire","type":"until"}' "$LOG" "(UNT) the until edge is written onto the bead whose landing ends the job"
has "DEP bd dep list tk-sub --direction=down -t until --json" "$LOG" "(UNT) …and read back by its type"
has "HELM takeaway tk-sub closes once tk-retire retires its code --by proactive --release --no-wait" "$LOG" \
    "(UNT) the release says nothing holds the subject"
has "gc.reacted_by=$R" "$LOG" "(UNT) the landed proof is stamped"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" "$LOG" \
    "(UNT) …and the reaction bead is closed"
has "disposed as until (tk-retire)" "$OUT" "(UNT) …and the run reports the bead it waits for"
before '^HELM takeaway' '^DEP bd dep add --file -' "(UNTORDER) the release lands before the edge is written"
before '^DEP bd dep list' 'gc.reacted_by' "(UNTORDER) …and the landed proof follows the edge's read-back"
AFTER_EDGE=$(sed -n '/^DEP bd dep add --file -/,$p' "$FAKE_LOG")
hasnt "HELM" "$AFTER_EDGE" "(UNTORDER) nothing after the edge releases the subject"
eq "$(printf '%s\n' "$AFTER_EDGE" | awk '/^UPDATE bd update tk-sub / && /--status|--assignee/')" "" \
    "(UNTORDER) …or writes its status or assignee"
hasnt "--waiting-on" "$LOG" "(UNTPURE) no blocks edge rides the release"
hasnt "-t blocks" "$LOG" "(UNTPURE) …and none is added directly"
hasnt "--route" "$LOG" "(UNTPURE) no route"
hasnt "--assign" "$LOG" "(UNTPURE) no assignee"
hasnt "DEFERRED" "$LOG" "(UNTPURE) no arm and no notice"
hasnt "placement" "$LOG" "(UNTPURE) no placement, though the subject has no parent"
hasnt "HELM demand" "$LOG" "(UNTPURE) no human gate"

UNTIL_STATUSES='[{"id":"tk-retire","status":"open","closed_at":null}]'
eq "$(scan_subject | cut -f2)" "waiting" "(UNTPURE) while tk-retire is open, the pass reads the subject as waiting on it"
UNTIL_STATUSES='[{"id":"tk-retire","status":"closed","closed_at":"2026-10-27T00:00:00Z"}]'
UNTIL_SCAN=$(scan_subject)
eq "$(printf '%s' "$UNTIL_SCAN" | cut -f2)" "owed" "(UNTPURE) once tk-retire closes, the pass reads the subject as owed its close"
eq "$(printf '%s' "$UNTIL_SCAN" | cut -f3)" "tk-retire" "(UNTPURE) …pointing it at tk-retire"
eq "$(printf '%s' "$UNTIL_SCAN" | cut -f8)" "-" "(UNTPURE) …and it carries no live-work mark that keeps the pass from closing it (live-work.sh)"

# The pass can run while the release is still in flight. Here it runs between
# the release's status read and its write, over the subject as the store holds
# it then, with tk-retire already closed. A close it made there would be undone
# by the release's write, and the successor pointer that close left would read
# as live work to every later pass, so none would close the subject again.
export FAKE_UNTIL_PASS="$TMP/until-pass" UNTIL_STATUSES='[{"id":"tk-retire","status":"closed","closed_at":"2026-10-27T00:00:00Z"}]'
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-retire --reaction-bead "$R"
eq "$RC" "0" "(UNTRACE) the until exit succeeds with the pass running inside its release"
before '^HELM release reads tk-sub' '^UNTILPASS' "(UNTRACE) the pass runs after the release reads the subject"
before '^UNTILPASS' '^HELM release writes tk-sub' "(UNTRACE) …and before the release writes it"
has "UNTILPASS leaves tk-sub" "$LOG" "(UNTRACE) …and finds nothing to close there"
hasnt "UNTILPASS closes tk-sub" "$LOG" "(UNTRACE) …so the release's write undoes no close"
before '^HELM release writes tk-sub' '^DEP bd dep add --file -' \
    "(UNTRACE) …because the edge that selects the subject is written after the release's write"
UNTIL_SCAN=$(scan_subject)
eq "$(printf '%s' "$UNTIL_SCAN" | cut -f2)" "owed" "(UNTRACE) once the exit completes, the pass reads the subject owed its close"
eq "$(printf '%s' "$UNTIL_SCAN" | cut -f8)" "-" "(UNTRACE) …with no live-work mark, so the pass closes it"
unset FAKE_UNTIL_PASS

# Two targets, tk-a closed and tk-b open, and the pass runs right after each
# edge write over the subject as the store holds it then. Both edges land in
# the one write, so the pass never reads the subject with the edge onto tk-a
# alone, which it would read as owed its close while tk-b is still open.
export FAKE_DEP_PASS="$TMP/until-pass" \
    FAKE_DEPS_JSON='[{"id":"tk-a","dependency_type":"until"},{"id":"tk-b","dependency_type":"until"}]' \
    UNTIL_STATUSES='[{"id":"tk-a","status":"closed","closed_at":"2026-10-27T00:00:00Z"},{"id":"tk-b","status":"open","closed_at":null}]'
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-a --until tk-b --reaction-bead "$R"
eq "$RC" "0" "(UNTMULTI) an until disposition onto two beads succeeds"
eq "$(grep -c '^DEP bd dep add' "$FAKE_LOG")" "1" "(UNTMULTI) …writing its edges in one add"
has 'DEPFILE {"from":"tk-sub","to":"tk-a","type":"until"}' "$LOG" "(UNTMULTI) …which carries the edge onto tk-a"
has 'DEPFILE {"from":"tk-sub","to":"tk-b","type":"until"}' "$LOG" "(UNTMULTI) …and the edge onto tk-b"
has "UNTILPASS leaves tk-sub" "$LOG" "(UNTMULTI) the pass run right after the write leaves the subject"
hasnt "UNTILPASS closes tk-sub" "$LOG" "(UNTMULTI) …and does not close it while tk-b is open"
eq "$(scan_subject | cut -f2,7)" "$(printf 'waiting\ttk-b')" "(UNTMULTI) once the exit completes, the pass reads the subject waiting on tk-b"
# Control: with the edge onto tk-a written alone, the pass reads the subject
# owed its close, the close an edge-at-a-time write would let it make.
UNTIL_FULL_LOG="$FAKE_LOG"; FAKE_LOG="$TMP/until-one-edge.log"
{ grep -v '^EDGE ' "$UNTIL_FULL_LOG"; printf 'EDGE tk-sub tk-a until\n'; } > "$FAKE_LOG"
eq "$(scan_subject | cut -f2)" "owed" "(UNTMULTI) control: with only the edge onto tk-a written, the pass reads the subject owed"
FAKE_LOG="$UNTIL_FULL_LOG"

# A retry after a write bd refused. The subject's blocks edge onto tk-b refuses
# its until edge, and the one write then lands neither edge, so the pass run
# right after it has no until edge to select the subject by. Once that blocks
# edge is gone, the re-run writes both.
export FAKE_DEP_REFUSES=tk-b FAKE_DEPS_JSON='[{"id":"tk-b","dependency_type":"blocks"}]'
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-a --until tk-b --reaction-bead "$R"
eq "$RC" "4" "(UNTRETRY) a write bd refuses fails the exit"
has "no until edge onto tk-a tk-b reads back" "$ERR" "(UNTRETRY) …and no edge of the set reads back"
hasnt "EDGE tk-sub" "$LOG" "(UNTRETRY) …since the refused write landed neither edge"
has "UNTILPASS leaves tk-sub" "$LOG" "(UNTRETRY) …so the pass run right after it leaves the subject"
eq "$(scan_subject)" "" "(UNTRETRY) …and selects nothing, the subject having no until edge"
hasnt "gc.reacted_by" "$LOG" "(UNTRETRY) …with no landed proof"
unset FAKE_DEP_REFUSES
export FAKE_DEPS_JSON='[{"id":"tk-a","dependency_type":"until"},{"id":"tk-b","dependency_type":"until"}]'
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-a --until tk-b --reaction-bead "$R"
eq "$RC" "0" "(UNTRETRY) the re-run succeeds"
hasnt "UNTILPASS closes tk-sub" "$LOG" "(UNTRETRY) …the pass run right after its write leaving the subject open"
eq "$(scan_subject | cut -f2,7)" "$(printf 'waiting\ttk-b')" "(UNTRETRY) …and waiting on tk-b, with both edges written"
has "gc.reacted_by=$R" "$LOG" "(UNTRETRY) …and the landed proof stamped"
unset FAKE_DEP_PASS

# Control: the blocked exit onto the same bead leaves a blocks edge, and holds
# the parentless subject for placement. The pass selects only a bead with an
# until edge, so that subject stays open after the retirement lands.
export FAKE_DEPS_JSON='[{"id":"tk-retire"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-retire \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(UNTPURE) control: the blocked exit on the same subject succeeds"
has "placement=pending" "$LOG" "(UNTPURE) control: …holds it for placement"
eq "$(scan_subject)" "" "(UNTPURE) control: …and with tk-retire closed, the pass selects nothing to close"

# The read-back is by type: a blocks edge onto the target, which refuses the
# until one, is not taken for it.
export FAKE_DEPS_JSON='[{"id":"tk-retire","dependency_type":"blocks"}]'
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-retire --reaction-bead "$R"
eq "$RC" "4" "(UNTEDGE) a target that reads back only as a blocks edge fails the exit"
has "no until edge onto tk-retire reads back" "$ERR" "(UNTEDGE) …naming the edge that is missing"
has "gc bd dep remove tk-sub" "$ERR" "(UNTEDGE) …and the blocks edge to remove first"
before '^HELM takeaway' '^DEP bd dep add --file -' "(UNTEDGE) …after the release"
has "The headline and the release stand" "$ERR" "(UNTEDGE) …which the failure says stands"
hasnt "gc.reacted_by" "$LOG" "(UNTEDGE) …with no landed proof"
hasnt "UPDATE bd update $R" "$LOG" "(UNTEDGE) …and the reaction bead left open"
export FAKE_DEPS_JSON='[]' FAKE_DEP_FAILS=1
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-retire --reaction-bead "$R"
eq "$RC" "4" "(UNTEDGE) a refused add with nothing to read back fails the exit"
has "bd answered" "$ERR" "(UNTEDGE) …carrying what bd answered"
export FAKE_DEPS_JSON='[{"id":"tk-retire","dependency_type":"until"}]'
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-retire --reaction-bead "$R"
eq "$RC" "0" "(UNTEDGE) a re-run whose add is refused over an edge that landed succeeds"
unset FAKE_DEP_FAILS
export FAKE_DEPS_JSON='[{"id":"tk-a","dependency_type":"until"}]'
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-a --until tk-b --reaction-bead "$R"
eq "$RC" "4" "(UNTEDGE) one of two edges reading back is still a failed exit"
has "no until edge onto tk-b reads back" "$ERR" "(UNTEDGE) …naming only the one that missed"

run tk-sub --disposition until --reason "r" --takeaway "t" --until ra-foreign --reaction-bead "$R"
eq "$RC" "2" "(UNTCROSS) a target in another store is refused"
eq "$LOG" "" "(UNTCROSS) …and nothing was written"
has "never sees ra-foreign close" "$ERR" "(UNTCROSS) …because the pass cannot see it close"
has "--disposition ruling" "$ERR" "(UNTCROSS) …and the refusal names a person's close as the remedy"

run tk-sub --disposition until --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "2" "(UNTARGS) until with no --until is refused"
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-sub --reaction-bead "$R"
eq "$RC" "2" "(UNTARGS) a bead cannot wait until itself lands"
for extra in "--then-route gc-toolkit/gc-toolkit.polecat" "--waiting-on tk-other" "--route gc-toolkit/gc-toolkit.polecat" "--assign gc-toolkit.mechanik"; do
  # shellcheck disable=SC2086  # $extra is a flag and its value
  run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-retire $extra --reaction-bead "$R"
  eq "$RC" "2" "(UNTARGS) until refuses ${extra%% *}"
  eq "$LOG" "" "(UNTARGS) …and writes nothing"
done
for d in actionable "blocked --waiting-on tk-blk1" close ruling "recommend --recommended-formula mol-polecat-work"; do
  # shellcheck disable=SC2086  # $d is a disposition and the flags it needs
  run tk-sub --disposition $d --reason "r" --takeaway "t" --until tk-retire --reaction-bead "$R"
  eq "$RC" "2" "(UNTARGS) ${d%% *} refuses --until"
  has "--until" "$ERR" "(UNTARGS) …naming it"
done

export FAKE_DEPS_JSON='[{"id":"tk-retire","dependency_type":"until"}]'
run tk-sub --disposition until --reason "r" --takeaway "t" --until tk-retire --dry-run
eq "$RC" "0" "(UNTDRY) a dry run of the until exit succeeds"
has "would close tk-sub once each of these lands" "$OUT" "(UNTDRY) …and names the wait"
hasnt "DEP" "$LOG" "(UNTDRY) …writing no edge"
hasnt "HELM" "$LOG" "(UNTDRY) …and releasing nothing"
unset FAKE_SHOW_JSON FAKE_DEPS_JSON

# ── ruling: the human gate is the wait, filed by the exit itself ─────────────
#   (RUL)      the exit files the gate through human-gate.sh, the takeaway as
#              its title, and holds the subject on it
#   (RULKEY)   the gate is filed under the key first-reaction, with no quiet
#              window
#   (RULORDER) gate, then release, then the landed proof
#   (RULGATE)  a gate that did not file, or that the helper did not name, fails
#              the exit before the release, with nothing recorded done
#   (RULEDGE)  a hold that did not land fails the exit
#   (RULSUPER) an open first-reaction gate a superseded reaction filed is
#              withdrawn before the new one, and this reaction's own is kept
#   (RULTITLE) the gate's title line is the takeaway on one line, as the
#              board shows it, so a re-run of a takeaway that spans lines
#              keeps its gate
#   (RULKIDS)  a subject with open children is gated like any other bead
#   (RULCAP)   a takeaway over the 140-character cap is refused first
# The exit files no visit. The FAKE dep list answers with the gate so the hold
# verification passes.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --reaction-bead "$R"
eq "$RC" "0" "(RUL) a ruling disposition succeeds"
has "GATE --subject tk-sub --key first-reaction --message needs a ruling: which default" "$LOG" \
   "(RUL) it files the human gate, the takeaway as the gate's title"
# human-gate.sh keeps one open gate per bead and key, so the reaction's own key
# files beside any other gate on the subject and a re-run finds its own.
has "--key first-reaction" "$(grep '^GATE ' "$FAKE_LOG")" \
   "(RULKEY) the gate is filed under the first reaction's own key"
hasnt "--quiet-window" "$(grep '^GATE ' "$FAKE_LOG")" \
   "(RULKEY) …declaring no quiet window: a reaction is an event of its own"
# The message spans lines, so read the gate call up to the release that follows it.
has "the trade-off is the operator's" "$(sed -n '/^GATE --subject/,/^HELM takeaway/p' "$FAKE_LOG")" \
   "(RUL) …with the reason in the gate's message"
has "HELM takeaway tk-sub needs a ruling: which default --by proactive --release" "$LOG" \
   "(RUL) the bead is released back to the human"
hasnt "--route" "$LOG" "(RUL) …not routed to a pool"
has "--waiting-on tk-gate1" "$LOG" "(RUL) …and held by the gate's edge"
# A ruling names the gate as its wait: the subject waits on a person, the gate
# is what a person owes, and --waiting-on records that wait as a blocks edge so
# doctor/check-wait-is-an-edge reads a graph state rather than reporting prose.
hasnt "--no-wait" "$LOG" "(RUL) …and never claims nothing is waiting"
hasnt "CREATE" "$LOG" "(RUL) …and files no visit"
has "disposed as ruling (tk-gate1)" "$OUT" "(RUL) …and reports the gate it disposed onto"
has "gc.reacted_by=$R" "$LOG" "(RUL) the landed proof is stamped"
has "UPDATE bd update $R" "$LOG" "(RUL) …and the reaction bead is closed"
before '^GATE --subject' '^HELM takeaway' "(RULORDER) the gate is filed before the release"
before '^HELM takeaway' 'gc.reacted_by' "(RULORDER) …and the landed proof follows the release"

export FAKE_GATE_FAILS=1
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "4" "(RULGATE) a gate that did not file fails the exit"
hasnt "HELM takeaway" "$LOG" "(RULGATE) …and the subject is not released onto a gate that does not exist"
has "re-run this command" "$ERR" "(RULGATE) …and the failure names the retry"
hasnt "gc.reacted_by" "$LOG" "(RULGATE) …with no landed proof stamped"
hasnt "UPDATE bd update $R" "$LOG" "(RULGATE) …and the reaction bead left open for the re-offer"
unset FAKE_GATE_FAILS

export FAKE_GATE_NOID=1
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "4" "(RULGATE) a helper that names no gate fails the exit"
hasnt "HELM takeaway" "$LOG" "(RULGATE) …before the release"
unset FAKE_GATE_NOID

export FAKE_DEPS_JSON='[]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "4" "(RULEDGE) a gate edge that is not on the subject fails the exit"
has "not held by tk-gate1" "$ERR" "(RULEDGE) …naming the gate it is not held by"
hasnt "gc.reacted_by" "$LOG" "(RULEDGE) …with no landed proof stamped"

export FAKE_DEPS_JSON='[{"id":"tk-gate0","issue_type":"gate","await_type":"human","await_id":"first-reaction","status":"open","title":"an older reaction asked this"},{"id":"tk-gate1"}]'
run tk-sub --disposition ruling --reason "r" --takeaway "needs a ruling: which default" --reaction-bead "$R"
eq "$RC" "0" "(RULSUPER) a ruling over a superseded reaction's gate succeeds"
has "GATE --retract --subject tk-sub --key first-reaction" "$LOG" "(RULSUPER) …withdrawing the superseded gate"
before '^GATE --retract' '^GATE --subject tk-sub --key first-reaction --message' "(RULSUPER) …before it files its own"
export FAKE_DEPS_JSON='[{"id":"tk-gate1","issue_type":"gate","await_type":"human","await_id":"first-reaction","status":"open","title":"needs a ruling: which default"}]'
run tk-sub --disposition ruling --reason "r" --takeaway "needs a ruling: which default" --reaction-bead "$R"
eq "$RC" "0" "(RULSUPER) a re-run of the same reaction succeeds"
hasnt "--retract" "$LOG" "(RULSUPER) …and withdraws nothing: the open gate asks this reaction's question"
# The helper titles a gate with its message's first line. A takeaway that spans
# lines is stored on the board as one line, and the gate's title has to be that
# same line, or each re-run reads its own gate as a superseded reaction's.
run tk-sub --disposition ruling --reason "r" --takeaway "needs a ruling:
which default" --reaction-bead "$R"
eq "$RC" "0" "(RULTITLE) a takeaway that spans lines takes the ruling exit"
has "GATE --subject tk-sub --key first-reaction --message needs a ruling: which default" "$LOG" \
   "(RULTITLE) …and the gate's title line is the takeaway on one line, as the board shows it"
hasnt "--retract" "$LOG" "(RULTITLE) …so a re-run finds the gate it filed and withdraws nothing"
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
export FAKE_SHOW_JSON='[{"id":"tk-sub",'"$MEMBER"',"metadata":{}},{"id":"tk-sub.1","parent":"tk-sub","status":"open"}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "0" "(RULKIDS) a subject with open children takes the ruling exit"
has "GATE --subject tk-sub --key first-reaction" "$LOG" "(RULKIDS) …and its gate blocks the parent itself"
hasnt "--parent" "$LOG" "(RULKIDS) …with no read of its children: what a gate on a parent pauses is the call site's policy"
unset FAKE_SHOW_JSON
LONG_TAKEAWAY="$(printf 'needs a ruling%.0s ' $(seq 1 12))"
run tk-sub --disposition ruling --reason "r" --takeaway "$LONG_TAKEAWAY" --reaction-bead "$R"
eq "$RC" "2" "(RULCAP) a takeaway over 140 characters is refused"
eq "$LOG" "" "(RULCAP) …before anything is written, since it is the gate's title"

: > "$FAKE_LOG"; RC=0
OUT="$("$SCRIPT" tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R" --dry-run 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(RULDRY) a dry run succeeds"
has "would file a human gate on tk-sub" "$OUT" "(RULDRY) …saying it would file the gate"
has "would close reaction bead $R" "$OUT" "(RULDRY) …and close the reaction bead"
hasnt "HELM" "$LOG" "(RULDRY) …and files nothing"
hasnt "UPDATE" "$LOG" "(RULDRY) …and writes nothing"

# ── recommend: the gate offers Accept ────────────────────────────────────────
# recommend names a determinable action (converse/operator authority) and stamps
# gc.recommended_formula on the subject. That stamp is the whole difference
# between a plain Discuss-only ruling gate and a recommendation the operator can
# Accept. recommend files and holds on the same human gate ruling does, and the
# stamp lands only once the gate is filed, so no recommendation is ever older
# than the newest first-reaction gate.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition recommend --reason "retire the PR, supersede its anchor — operator authority" \
    --takeaway "recommend: retire PR + supersede anchor; execute via mol-x — Accept or Discuss" \
    --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "0" "(RECO) a recommend disposition succeeds"
has "gc.recommended_formula=mol-x" "$LOG" "(RECO) the recommended formula is stamped on the subject"
has "GATE --subject tk-sub --key first-reaction --message recommend: retire PR + supersede anchor; execute via mol-x — Accept or Discuss" "$LOG" \
   "(RECO) …it files the human gate, as ruling does"
has "--waiting-on tk-gate1" "$LOG" "(RECO) …and the gate holds the subject, the ruling shape"
before '^GATE --subject' 'gc.recommended_formula=mol-x' "(RECO) …the recommendation lands only once the gate is filed"
before '^GATE --subject' '^HELM takeaway' "(RECO) …and the gate before the release"
has "gc.reacted_by=$R" "$LOG" "(RECO) the landed proof is stamped"
has "UPDATE bd update $R" "$LOG" "(RECO) …and the reaction bead is closed"

# recommend REQUIRES the flag it exists to carry: no --recommended-formula is a
# usage error naming ruling as the flagless alternative.
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via <mol> — Accept or Discuss" --reaction-bead "$R"
eq "$RC" "2" "(RECO) recommend with no --recommended-formula is refused"
eq "$LOG" "" "(RECO) …and writes nothing"
has "is --disposition ruling" "$ERR" "(RECO) …naming ruling as the flagless alternative"

# A recommended formula that does not resolve is a usage error, refused before
# anything is written: Accept slings this exact name, so a typo would stamp a live
# gc.recommended_formula and render an 'accept ▸' that fails at gc sling on every
# click. Validated the way --route/--then-route are against the roster.
export FAKE_FORMULA_MISSING="mol-typo"
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-typo — Accept or Discuss" \
    --recommended-formula mol-typo --reaction-bead "$R"
eq "$RC" "2" "(RECO) a --recommended-formula that does not resolve is refused (usage error)"
hasnt "UPDATE" "$LOG" "(RECO) …nothing is written for an unresolved formula"
hasnt "HELM" "$LOG" "(RECO) …and the act does not run"
has "does not resolve to a formula" "$ERR" "(RECO) …the message names the unresolved formula"
unset FAKE_FORMULA_MISSING

# ── ruling rejects a recommendation: it is Discuss-only ───────────────────────
# A ruling is the operator's judgment with no worker-runnable action, so it takes
# no --recommended-formula; the refusal names recommend as the disposition that
# carries one.
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "2" "(RECO) ruling refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
has "use --disposition recommend" "$ERR" "(RECO) …pointing at the disposition that carries a recommendation"

# A plain ruling stamps nothing, so the gate stays Discuss-only (no Accept).
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --reaction-bead "$R"
eq "$RC" "0" "(RECO) a Discuss-only ruling succeeds"
hasnt "gc.recommended_formula" "$LOG" "(RECO) …and stamps no recommendation, so the gate offers no Accept"

# A subject can already carry a recommendation a prior recommend stamped: the
# stamp landed, the act did not (no landed proof), and this retry resumes it. A
# ruling retry names no recommendation and clears that stale stamp before the
# act, so the gate never offers Accept for an action the current disposition did
# not recommend.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.recommended_formula":"mol-old"}}]'
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --reaction-bead "$R"
eq "$RC" "0" "(RECO) a ruling retry over a stale recommendation succeeds"
has "--unset-metadata gc.recommended_formula" "$LOG" "(RECO) …and clears the stale recommendation the prior recommend left"
hasnt "gc.recommended_formula=" "$LOG" "(RECO) …stamping no new one, so the subject states the current disposition"

# The same stale stamp retried as a recommend with a different formula clears the
# stale one before the gate is filed and stamps the new one after it, so no
# recommendation is older than the newest first-reaction gate, and an exit that
# stops part way never leaves its gate beside the older recommendation.
run tk-sub --disposition recommend --reason "the newer mol is the right execution" \
    --takeaway "recommend: execute via mol-new — Accept or Discuss" \
    --recommended-formula mol-new --reaction-bead "$R"
eq "$RC" "0" "(RECO) a retry that re-recommends succeeds"
has "gc.recommended_formula=mol-new" "$LOG" "(RECO) …and the subject carries the new recommendation"
has "--unset-metadata gc.recommended_formula" "$LOG" "(RECOORDER) …clearing the older recommendation first"
before '--unset-metadata gc.recommended_formula' '^GATE --subject' "(RECOORDER) …before the gate is filed"
before '^GATE --subject' 'gc.recommended_formula=mol-new' "(RECOORDER) …and stamping the new one after it"
unset FAKE_SHOW_JSON

# ── The recommendation must land before the act (read-back guard) ─────────────
# gc.recommended_formula is presence-sensitive downstream, so a silently dropped
# write is a wrong operator affordance, not a cosmetic miss. An update reports
# success without proving this one key moved, so the exit reads it back, retries
# the lone set/unset once, and refuses before the act if it is still wrong —
# nothing else has been written, so the command re-runs.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'

# A set that silently drops and never recovers: the release is withheld, so the
# reaction is not recorded done over a gate that offers only Discuss. The gate is
# filed before the set, and a re-run finds it and sets the recommendation again.
export FAKE_DROP_RECO=1
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" \
    --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "4" "(RECOGUARD) a silently dropped recommendation set refuses the exit"
hasnt "HELM takeaway" "$LOG" "(RECOGUARD) …the release is withheld"
has "did not land" "$ERR" "(RECOGUARD) …and the refusal names the key that did not land"
has "The gate tk-gate1 is filed" "$ERR" "(RECOGUARD) …saying the gate is already filed"
hasnt "UPDATE bd update $R" "$LOG" "(RECOGUARD) …and the reaction bead is left open for the re-offer"
unset FAKE_DROP_RECO

# The same drop, but the lone retry lands it: the act proceeds.
export FAKE_DROP_RECO=once
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" \
    --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "0" "(RECOGUARD) a set that lands on the retry lets the act proceed"
has "HELM takeaway tk-sub" "$LOG" "(RECOGUARD) …the act runs once the recommendation is confirmed"
unset FAKE_DROP_RECO

# A stale-clear that silently drops and never recovers: the act is withheld, so a
# Discuss-only retry never leaves a superseded Accept executable.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.recommended_formula":"mol-old"}}]'
export FAKE_DROP_RECO=1
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --reaction-bead "$R"
eq "$RC" "4" "(RECOGUARD) a silently dropped stale-clear refuses the exit"
hasnt "HELM" "$LOG" "(RECOGUARD) …the act is withheld, so the superseded Accept is never left executable"
hasnt "GATE " "$LOG" "(RECOGUARD) …and no gate is filed beside the older recommendation"
has "did not clear" "$ERR" "(RECOGUARD) …and the refusal names the stale key that did not clear"
unset FAKE_DROP_RECO FAKE_SHOW_JSON  # leave FAKE_DEPS_JSON: later ruling tests reuse the gate edge

# A stale-clear whose read-back is UNREADABLE — every post-write `bd show`
# answers the non-array error object gc bd show emits for an unresolvable
# subject — must fail closed, not read the empty value as a proven clear. The
# subject last read carried gc.recommended_formula=mol-old, so accepting the
# unreadable read (want empty) would leave a superseded Accept executable. This
# is distinct from the dropped-write case above: the write is not modelled as
# dropped, the subject simply cannot be read back to prove it moved.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.recommended_formula":"mol-old"}}]'
export FAKE_SHOW_UNREADABLE_AFTER_UPDATE=1
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --reaction-bead "$R"
eq "$RC" "4" "(RECOGUARD) an unreadable stale-clear read-back refuses the exit"
hasnt "HELM" "$LOG" "(RECOGUARD) …the act is withheld, so a stale Accept cannot slip through an unreadable read"
has "did not clear" "$ERR" "(RECOGUARD) …and the refusal names the key it could not prove cleared"
unset FAKE_SHOW_UNREADABLE_AFTER_UPDATE FAKE_SHOW_JSON  # leave FAKE_DEPS_JSON for later ruling tests

# --recommended-formula belongs to the recommend exit only: actionable, blocked,
# and close route, hold, or hand the bead to a closer, and none files a gate the
# operator Accepts — so each refuses the flag (ruling's refusal is tested above).
run tk-sub --disposition actionable --reason "r" --takeaway "t" \
    --route gc-toolkit/gc-toolkit.polecat --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "2" "(RECO) actionable refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "2" "(RECO) blocked refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
run tk-sub --disposition close --reason "r" --takeaway "t" \
    --route gc-toolkit/gc-toolkit.polecat --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "2" "(RECO) close refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"

# ── Origin does not decide the exit ──────────────────────────────────────────
# operator-intake stamps gc.origin=operator on a topic a human typed, but the
# script does not force such a bead to the ruling exit: an operator capture is
# triaged on its merits, so every exit is open to it. The guardrail that a fork
# or an irreversible action still goes to a human lives in the reacting agent's
# rubric, not here.
export FAKE_SHOW_JSON='[{"id":"tk-sub",'"$MEMBER"',"metadata":{"gc.origin":"operator"}}]'
export FAKE_DEPS_JSON='[{"id":"tk-blk1"},{"id":"tk-gate1"}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(ORIGIN) an operator-origin subject may take the actionable exit"
has "HELM takeaway tk-sub" "$LOG" "(ORIGIN) …and is routed like any other bead"
hasnt "the visit IS the answer" "$ERR" "(ORIGIN) …with no operator-origin refusal"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --reaction-bead "$R"
eq "$RC" "0" "(ORIGIN) …the blocked exit too"

run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "0" "(ORIGIN) …and the ruling exit, when the agent chooses it"
# Leave FAKE_DEPS_JSON holding tk-gate1 for the ruling-exit checks downstream.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
unset FAKE_SHOW_JSON

# ── close: hand the bead to a validating closer, never close here ────────────
# The reaction concluded there is nothing to do. It does not close the bead — a
# cheap model must not have the last word — it hands the bead to a capable pool
# carrying mol-validate-close, which re-checks the call and closes or escalates.
# A reaction bead is no workflow on the subject, so its closer is slung now; a
# frozen molecule's close runs inside a live reaction workflow (--after-workflow)
# and is deferred instead — that path is covered further below.
# GC_RIG is set on every run: the proactive pool is rig-scoped, and it is what
# both defaults the pool target and pins the sling with --rig.
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "already fixed, nothing to merge" --takeaway "close: fixed in #123" --reaction-bead "$R"
eq "$RC" "0" "(CLOSE) the close exit succeeds"
has "SLING sling --rig gc-toolkit gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close" "$LOG" \
   "(CLOSE) it slings the closer formula to \$GC_RIG/gc-toolkit.polecat, rig-pinned"
has "HELM takeaway tk-sub close: fixed in #123 --by proactive" "$LOG" "(CLOSE) …sets the board headline"
has "UPDATE bd update tk-sub --append-notes ## Close brief (first reaction" "$LOG" "(CLOSEBRIEF) the close brief is appended to the subject's notes"
has "already fixed, nothing to merge" "$(sed -n '/--append-notes ## Close brief/,/^SLING/p' "$FAKE_LOG")" "(CLOSEBRIEF) …carrying the reaction's reason, which the closer validates"
before 'Close brief' '^SLING' "(CLOSEBRIEF) …before the closer is slung, so it is there when the closer reads it"
hasnt "--release" "$LOG" "(CLOSE) …and does not release it to a pool as a raw bead"
has "gc.reacted_by=$R" "$LOG" "(CLOSE) …stamps the landed proof so a re-offer does not sling a second closer"
before '^SLING' 'gc.reacted_by' "(CLOSE) …after the sling"
hasnt "gc.proactive_reaction" "$LOG" "(CLOSE) …no legacy landed proof on the reaction-bead path"
has "UPDATE bd update $R" "$LOG" "(CLOSE) …and closes the reaction bead"
hasnt "CLOSE bd close" "$LOG" "(CLOSE) …and never closes the subject itself"
hasnt "DEFERRED" "$LOG" "(CLOSE) …with no deferred arm: nothing on the subject has to close first"

# With no GC_RIG, an explicit --route still slings — and pins nothing.
: > "$FAKE_LOG"; RC=0
OUT="$(env -u GC_RIG "$SCRIPT" tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R" 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(CLOSE) with no GC_RIG, an explicit --route still slings"
has "SLING sling gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close" "$LOG" "(CLOSE) …with no --rig pin"

# An operator-origin subject may take the close exit like any other.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.origin":"operator"}}]'
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(CLOSE) an operator-origin subject may be routed to the closer"
unset FAKE_SHOW_JSON

# The closer must be able to claim, or the bead is routed to nobody — same
# roster gate the actionable exit uses, same fallback.
FAKE_POOL_DEAD=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "2" "(CLOSE) a closer pool that cannot claim is refused"
has "Put it to the operator instead" "$ERR" "(CLOSE) …and the refusal names the exits that reach a human"
hasnt "SLING" "$LOG" "(CLOSE) …and nothing is slung"
unset FAKE_POOL_DEAD

# The closer reads the brief from the notes, so a brief that does not land
# dispatches no closer.
FAKE_NOTES_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(CLOSEBRIEF) a close brief that does not land fails the exit"
hasnt "SLING" "$LOG" "(CLOSEBRIEF) …and no closer is slung without its brief"
hasnt "gc.reacted_by" "$LOG" "(CLOSEBRIEF) …and the landed proof is not stamped"

# A failed sling refers to the cause; the landed proof is NOT stamped and R stays
# open, so the re-offered reaction resumes rather than recording done.
FAKE_SLING_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(CLOSE) a failed sling is a runtime failure"
hasnt "gc.reacted_by" "$LOG" "(CLOSE) …and the landed proof is not stamped"
hasnt "UPDATE bd update $R" "$LOG" "(CLOSE) …and the reaction bead stays open"

# The act-on-S -> close-R window on this exit: the first run slung the closer and
# died before the landed proof. The re-offered R runs the close again, and gc
# sling refuses a second live workflow with its exit 3. That refusal is the proof
# the closer is already slung, so the run records done instead of failing the
# re-offer forever.
FAKE_SLING_RC=3 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(CLOSEREOFFER) a re-offered close whose closer is already live succeeds"
has "not slinging a second" "$ERR" "(CLOSEREOFFER) …naming the live closer"
has "gc.reacted_by=$R" "$LOG" "(CLOSEREOFFER) …stamps the landed proof"
has "UPDATE bd update $R" "$LOG" "(CLOSEREOFFER) …and closes the reaction bead"
# Without a reaction bead the 3 has no earlier run behind it: someone else's
# workflow drives the bead, and a hand-run close must not paper over that.
FAKE_SLING_RC=3 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "4" "(CLOSEREOFFER) a hand-run close onto a bead a live workflow drives is a failure"
hasnt "gc.proactive_reaction=1" "$LOG" "(CLOSEREOFFER) …with no landed proof stamped"

# A reaction bead is not a workflow on the subject, so --after-workflow (the
# frozen molecule's deferral) does not combine with it.
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --after-workflow tk-root --reaction-bead "$R"
eq "$RC" "2" "(CLOSE) --after-workflow is refused beside --reaction-bead"
eq "$LOG" "" "(CLOSE) …and nothing is written"

# ── close --after-workflow: the frozen molecule's DEFERRED closer ─────────────
# A frozen mol-first-reaction molecule runs its close from inside the live
# reaction workflow, and the closer must be the bead's SOLE dispatch surface
# (formula-spec-v2 §3). So the close exit does NOT sling now: it holds the bead on
# the reaction's own workflow root and arms a deferred dispatch, and the
# deferred-dispatch reconcile pass slings mol-validate-close once that root
# closes. The arm carries the exact sling reconcile replays, so the closer
# FORMULA is asserted here rather than a bare "something was slung".
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "already fixed" --takeaway "close: fixed in #123" --after-workflow tk-root
eq "$RC" "0" "(CLOSEDEFER) the deferred close exit succeeds"
has "DEP bd dep add tk-sub tk-root -t blocks" "$LOG" "(CLOSEDEFER) it holds the bead on the reaction root so reconcile waits for it to close"
before 'Close brief' '^DEFERRED arm' "(CLOSEDEFER) …with the close brief on the subject before the closer is armed"
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat --sling-arg --on --sling-arg mol-validate-close" "$LOG" \
   "(CLOSEDEFER) …and arms a deferred dispatch carrying the exact --on mol-validate-close sling reconcile replays"
hasnt "SLING" "$LOG" "(CLOSEDEFER) …and slings nothing now — the reconcile pass does it once the reaction closes"
has "gc.proactive_reaction=1" "$LOG" "(CLOSEDEFER) …and stamps the legacy landed proof so a re-offer does not queue a second closer"
before '^DEFERRED arm' 'gc.proactive_reaction=1' "(CLOSEDEFER) …after the arm"
hasnt "gc.reacted_by" "$LOG" "(CLOSEDEFER) …with no reaction-bead marker on the frozen path"
hasnt "CLOSE bd close" "$LOG" "(CLOSEDEFER) …and never closes the bead itself"

# The gate is a REQUIRED write: reconcile dispatches from `bd list --ready`, so a
# hold that does not land leaves the bead reading ready and mol-validate-close
# would sling beside the still-live reaction — the two-live-surfaces shape this
# exit prevents. So a failed hold fails closed: the exit refuses to arm, and the
# landed proof is left unstamped so the documented re-run resumes.
FAKE_DEP_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --after-workflow tk-root
eq "$RC" "4" "(CLOSEDEFER) a hold that did not land fails the exit closed"
hasnt "DEFERRED arm" "$LOG" "(CLOSEDEFER) …and the ungated dispatch is NOT armed"
hasnt "gc.proactive_reaction=1" "$LOG" "(CLOSEDEFER) …and the landed proof is not stamped"
unset FAKE_DEP_FAILS

# An arm that fails to record IS a runtime failure: no closer would be
# dispatched, so the documented re-run resumes (the landed proof is unstamped).
FAKE_DEFERRED_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --after-workflow tk-root
eq "$RC" "4" "(CLOSEDEFER) a failed arm is a runtime failure"
hasnt "gc.proactive_reaction=1" "$LOG" "(CLOSEDEFER) …and the landed proof is not stamped"
unset FAKE_DEFERRED_FAILS

# --after-workflow belongs to close only, and must be same-store as the subject.
run tk-sub --disposition actionable --reason "r" --takeaway "t" --after-workflow tk-root
eq "$RC" "2" "(CLOSEDEFER) --after-workflow is refused on a non-close exit"
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --after-workflow zz-root
eq "$RC" "2" "(CLOSEDEFER) a cross-store --after-workflow is refused (the hold would hold nothing)"

# Called by hand with no live workflow and no reaction bead, the closer is slung
# now and the legacy landed proof stands in for gc.reacted_by.
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(CLOSE) a hand-run close with no reaction bead succeeds"
has "SLING sling --rig gc-toolkit gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close" "$LOG" "(CLOSE) …slinging the closer now"
has "gc.proactive_reaction=1" "$LOG" "(CLOSE) …and stamping the legacy landed proof"

# ── Re-offer recovery: a reaction happens once ───────────────────────────────
# R re-offered after a crash in the act-on-S -> close-R window: S already carries
# gc.reacted_by=R, so the run closes R and touches S no further.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"gc.reacted_by":"tk-react"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(REOFFER) a subject already reacted-by this R closes R without re-disposing"
hasnt "HELM" "$LOG" "(REOFFER) …the subject is not re-released"
has "UPDATE bd update $R" "$LOG" "(REOFFER) …and the reaction bead is closed"
has "already carries this reaction's write-back" "$ERR" "(REOFFER) …and it says so"
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "0" "(REOFFER) …the close exit too"
hasnt "SLING" "$LOG" "(REOFFER) …which slings no second closer"
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
hasnt "GATE " "$LOG" "(REOFFER) …and the gate form files no second gate"
# A marker naming a DIFFERENT reaction does not suppress this one (re-reaction).
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{"gc.reacted_by":"tk-oldreact"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(REOFFER) a marker from a DIFFERENT reaction does not block this one"
has "HELM takeaway tk-sub" "$LOG" "(REOFFER) …the reaction proceeds"
unset FAKE_SHOW_JSON

# ── Stand-down: a subject that takes no reaction from R ──────────────────────
# The reaction asks this before it reads the subject. Either marker closes R
# through the close every exit ends in and writes nothing to the subject; with
# neither, nothing is written and exit 3 sends the reaction ahead.
#   (SDLANDED)    this R's write-back already landed: R closes with its outcome
#                 and the no-op work record, and the subject is not touched
#   (SDOWNED)     a live owner holds the reaction: R closes, the marker stays
#   (SDNUM)       the number form bd stores reads as the owner's marker too
#   (SDOTHER)     a gc.reacted_by naming a different R does not stand this one down
#   (SDNONE)      neither marker: nothing is written, and the exit says react
#   (SDREAD)      an unreadable subject carries neither marker
#   (SDDRY)       --dry-run names the close it would make and writes nothing
#   (SDARGS)      no R, an exit's flag, or R as the subject is refused; the
#                 common flags pass
#   (SDPIN)       the read and the close carry the subject's store pin
#   (SDCLOSEFAIL) a refused close still stands down, naming the full hand repair
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"gc.reacted_by":"tk-react"}}]'
run tk-sub --stand-down --reaction-bead "$R"
eq "$RC" "0" "(SDLANDED) a subject already reacted-by this R stands the reaction down"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" "$LOG" \
    "(SDLANDED) …closing R with its outcome and the no-op work record, the close every exit makes"
hasnt "UPDATE bd update tk-sub" "$LOG" "(SDLANDED) …and writing nothing to the subject"
hasnt "HELM" "$LOG" "(SDLANDED) …which is not released again"
has "already carries this reaction's write-back" "$ERR" "(SDLANDED) …and it says why it stood down"

export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"gc.reaction_owned":"1","gc.origin":"operator"}}]'
run tk-sub --stand-down --reaction-bead "$R"
eq "$RC" "0" "(SDOWNED) a subject a live owner holds stands the reaction down"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" "$LOG" \
    "(SDOWNED) …closing R through the same close"
hasnt "UPDATE bd update tk-sub" "$LOG" "(SDOWNED) …and leaving the subject and its marker untouched"
has "gc.reaction_owned=1" "$ERR" "(SDOWNED) …naming the marker"

export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.reaction_owned":1}}]'
run tk-sub --stand-down --reaction-bead "$R"
eq "$RC" "0" "(SDNUM) the number form bd stores reads as the owner's marker too"
has "UPDATE bd update $R" "$LOG" "(SDNUM) …and R is closed"

export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"gc.reacted_by":"tk-oldreact"}}]'
run tk-sub --stand-down --reaction-bead "$R"
eq "$RC" "3" "(SDOTHER) a marker from a DIFFERENT reaction does not stand this one down"
hasnt "UPDATE" "$LOG" "(SDOTHER) …and nothing is written"

export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{}}]'
run tk-sub --stand-down --reaction-bead "$R"
eq "$RC" "3" "(SDNONE) a subject with neither marker sends the reaction ahead"
hasnt "UPDATE" "$LOG" "(SDNONE) …R stays open for the disposition to close"
hasnt "HELM" "$LOG" "(SDNONE) …and nothing is disposed"
has "the reaction goes ahead" "$ERR" "(SDNONE) …and it says so"

export FAKE_SHOW_JSON='not json'
run tk-sub --stand-down --reaction-bead "$R"
eq "$RC" "3" "(SDREAD) an unreadable subject is not evidence of either marker"
hasnt "UPDATE" "$LOG" "(SDREAD) …so nothing is written"

export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.reacted_by":"tk-react"}}]'
run tk-sub --stand-down --reaction-bead "$R" --dry-run
eq "$RC" "0" "(SDDRY) a dry-run stand-down succeeds"
has "would close reaction bead $R" "$OUT" "(SDDRY) …naming the close it would make"
hasnt "UPDATE" "$LOG" "(SDDRY) …and writing nothing"

run tk-sub --stand-down
eq "$RC" "2" "(SDARGS) a stand-down with no reaction bead is refused"
eq "$LOG" "" "(SDARGS) …before anything is read or written"
has "needs --reaction-bead" "$ERR" "(SDARGS) …naming the bead it would close"
# A whole actionable call, --route included: without GC_RIG the actionable arm
# refuses an unqualified route, so a call missing it would be refused there.
run tk-sub --stand-down --reaction-bead "$R" --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "2" "(SDARGS) a stand-down carrying an exit's flags is refused"
eq "$LOG" "" "(SDARGS) …and nothing was read or written"
has "--stand-down takes --reaction-bead only" "$ERR" "(SDARGS) …naming the one flag it takes"
# The subject carries this R's marker, so a flag the check let through would
# stand down and close R instead of being refused.
run tk-sub --stand-down --reaction-bead "$R" --emergency "test-macos"
eq "$RC" "2" "(SDARGS) a stand-down carrying --emergency is refused, as every exit flag is"
eq "$LOG" "" "(SDARGS) …and nothing was read or written"
has "was given --emergency" "$ERR" "(SDARGS) …naming the flag it does not take"
run tk-sub --stand-down --reaction-bead "$R" --by proactive --db "$TMP/sd.beads"
eq "$RC" "0" "(SDARGS) the common flags pass the stand-down's check"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed --db $TMP/sd.beads" "$LOG" \
    "(SDARGS) …and the stand-down closes R in the store --db names"
run tk-sub --stand-down --reaction-bead tk-sub
eq "$RC" "2" "(SDARGS) the reaction bead cannot be the subject itself"

mkdir -p "$TMP/rig/.beads"
export FAKE_RIG_PATH="$TMP/rig"
run tk-sub --stand-down --reaction-bead "$R"
has "SHOW bd show tk-sub --json --db $TMP/rig/.beads" "$LOG" "(SDPIN) the markers are read from the subject's own store"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed --db $TMP/rig/.beads" \
    "$LOG" "(SDPIN) …and R's close is written there"
unset FAKE_RIG_PATH

export FAKE_CLOSE_FAILS=1
run tk-sub --stand-down --reaction-bead "$R"
eq "$RC" "0" "(SDCLOSEFAIL) a close the store refuses still stands the reaction down"
has "its re-offer reaches this close again" "$ERR" "(SDCLOSEFAIL) …since R's re-offer reaches the close again"
has "Close it by hand: gc bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" \
    "$ERR" "(SDCLOSEFAIL) …and the hand repair writes every field the close does"
unset FAKE_SHOW_JSON
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(SDCLOSEFAIL) an exit whose close of R is refused still reports its landed disposition"
has "Close it by hand: gc bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" \
    "$ERR" "(SDCLOSEFAIL) …and names the same full hand repair"
unset FAKE_CLOSE_FAILS

# ── The frozen mol-first-reaction call (no --reaction-bead) ───────────────────
# An in-flight molecule calls this without --reaction-bead, so it has no R to key
# exactly-once on. The write-back runs and, in place of gc.reacted_by, stamps the
# legacy landed proof gc.proactive_reaction=1 — the marker that molecule's own
# REACTED checks read and this script's re-offer guard keys on.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "0" "(LEGACY) the frozen call with no --reaction-bead still disposes"
has "GATE --subject tk-sub --key first-reaction" "$LOG" "(LEGACY) …the act runs"
hasnt "gc.reacted_by" "$LOG" "(LEGACY) …no gc.reacted_by marker without an R to name"
has "gc.proactive_reaction=1" "$LOG" "(LEGACY) …but the legacy landed proof is stamped so a re-offer does not re-dispose"
before '^HELM takeaway' 'gc.proactive_reaction=1' "(LEGACY) …after the release, which no longer stamps it itself"
hasnt "UPDATE bd update tk-react" "$LOG" "(LEGACY) …and no reaction bead is closed"
hasnt "gc.first_reaction" "$LOG" "(LEGACY) …and no attempt record is written"

# The frozen path's proof is the only exactly-once key that molecule has, so a
# stamp that did not land fails the exit with the by-hand repair named.
export FAKE_PROACTIVE_STAMP_FAILS=1
run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "4" "(LEGACY) a landed proof that did not stamp fails the frozen exit"
has "Stamp it by hand" "$ERR" "(LEGACY) …naming the repair"
unset FAKE_PROACTIVE_STAMP_FAILS

# The frozen path takes the blocked exit's failed arm the same way: the exit
# fails before gc.proactive_reaction=1, so a re-offered frozen step reads no
# landed proof and runs the write-back again.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
FAKE_DEFERRED_FAILS=1 run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat
eq "$RC" "4" "(LEGACY) a --then-route arm that did not land fails the frozen exit"
has "DEFERRED arm tk-sub" "$LOG" "(LEGACY) …after the arm was tried"
hasnt "gc.proactive_reaction=1" "$LOG" "(LEGACY) …before the legacy landed proof is stamped"
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'

# A re-offered frozen step: S already carries the landed proof, so the second run
# is a no-op success — the act does NOT run, so a bead a downstream worker may
# have claimed is not reopened and re-routed out from under it, and a ruling
# files no second gate. The frozen step then closes itself and drains.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"gc.proactive_reaction":"1"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(LEGACY-REOFFER) a subject already carrying the landed proof disposes as a no-op"
hasnt "HELM" "$LOG" "(LEGACY-REOFFER) …the subject is not re-released"
hasnt "UPDATE" "$LOG" "(LEGACY-REOFFER) …and nothing is written"
has "already carries a landed first reaction" "$ERR" "(LEGACY-REOFFER) …and it says so"
run tk-sub --disposition ruling --reason "r" --takeaway "t"
hasnt "GATE " "$LOG" "(LEGACY-REOFFER) …the gate form files no second gate"
# bd stores `--set-metadata gc.proactive_reaction=1` as the JSON number 1, so the
# guard must read the number the same as the string.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.proactive_reaction":1}}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "0" "(LEGACY-REOFFER) the number form bd stores is read as the landed proof too"
hasnt "HELM" "$LOG" "(LEGACY-REOFFER) …with no re-release"

# Positive finding only: an unreadable bead is not evidence of a prior reaction.
# The exit here hands the bead to a named agent, which intake does not read: an
# unreadable subject proves no membership, so a pool route on it is held (see
# INTAKEUNREAD below).
export FAKE_SHOW_JSON='not json'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik
eq "$RC" "0" "(LEGACY-REOFFER) an unreadable bead is not evidence of a prior reaction"
has "HELM takeaway tk-sub" "$LOG" "(LEGACY-REOFFER) …so the act runs"

# A retired attempt record left by an older reaction is not a landed proof: it
# neither refuses the run nor is written again.
export FAKE_SHOW_JSON='[{"id":"tk-sub",'"$MEMBER"',"metadata":{"gc.first_reaction":"actionable","gc.first_reaction_at":"2026-09-03T04:45:05Z"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(RESUME) a retired gc.first_reaction record does not refuse the run"
has "HELM takeaway tk-sub" "$LOG" "(RESUME) …the act runs"
hasnt "gc.first_reaction=" "$LOG" "(RESUME) …and the record is not rewritten"
# A ruling whose gate already filed resumes through the helper again, under the
# same key, which finds the gate the first run filed instead of filing a second.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{}}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "0" "(RESUME) the gate form resumes"
has "GATE --subject tk-sub --key first-reaction" "$LOG" "(RESUME) …asking the helper for the subject's gate again, under the key the first run filed it under"
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
unset FAKE_SHOW_JSON

# ── The store is pinned to the subject's own rig ─────────────────────────────
# A blocker filed into another store makes the hold a cross-store edge, which
# reports success and holds nothing — and this runs from a worktree where an
# unpinned up-walk finds the wrong ledger.
mkdir -p "$TMP/rig/.beads"
export FAKE_RIG_PATH="$TMP/rig" FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
has "--db $TMP/rig/.beads" "$LOG" "(PIN) the subject's own store is passed to every bead write"
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat --reason first reaction: r --db $TMP/rig/.beads" \
    "$LOG" "(PIN) …and to the deferred dispatch it arms"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed --db $TMP/rig/.beads" \
    "$LOG" "(PIN) …and to the close of the reaction bead"
unset FAKE_RIG_PATH

# ── The invariant that outranks every exit ───────────────────────────────────
# A first reaction advances the subject; it never finishes it. The script's only
# closed-status write is the reaction bead's own close.
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
hasnt "CLOSE" "$LOG" "(NEVERCLOSE) no exit closes the subject"
grep -qE 'bd (update "?\$?BEAD"?|close).*status=closed|close "\$BEAD"' "$SCRIPT" \
  && bad "(NEVERCLOSE) the script can close the subject" \
  || ok "(NEVERCLOSE) …and the script has no path that closes the subject"
eq "$(grep 'status=closed' "$SCRIPT" | grep -v -E '^[[:space:]]*(note|die|#)' | grep -c 'gc_bd update "\$REACTION_BEAD"')" "1" \
   "(NEVERCLOSE) …its one closed-status write is the reaction bead's"
eq "$(grep 'status=closed' "$SCRIPT" | grep -v -E '^[[:space:]]*(note|die|#)' | grep -c .)" "1" \
   "(NEVERCLOSE) …and it has no other"

# ── R has one close: the prompt that runs this script writes none ────────────
# The proactive prompt is this script's caller. A close of R written into the
# prompt is a second copy of close_reaction's write, free to drift from the work
# record that close carries, so the prompt stands a reaction down through
# --stand-down and closes nothing itself. This suite is the merge gate a prompt
# change runs, since tools/run-tests.sh maps the prompt's path below to it;
# tools/proactive-first-reaction-fixture.sh asserts the same, by hand only.
PROMPT_MD="$HERE/../../agents/proactive/prompt.template.md"
if [ -f "$PROMPT_MD" ]; then
  PM="$(cat "$PROMPT_MD")"
  has '"$DISPOSE" "$SUBJECT" --stand-down --reaction-bead <R>' "$PM" \
      "(ONECLOSE) the prompt stands a reaction down through this script"
  hasnt "--status=closed" "$PM" "(ONECLOSE) …and writes no close of its own"
else
  bad "(ONECLOSE) the proactive prompt is missing at $PROMPT_MD"
fi

# ── The prompt reacts only when the stand-down says to ───────────────────────
# --stand-down answers 0 when it closed R, and the worker drains, or 3 when the
# reaction goes ahead. Any other status means it did not answer, and a reaction
# run on one skips the marker check. The prompt's stand-down block runs here the
# way a worker runs it: R filled in, a stand-in for this script that exits each
# status, a gc that only logs, and a line after the block standing for the
# reaction.
#   (SDGATE) 0 drains and 3 goes on to react; every other status stops the block
#            with a failure, before the reaction and with no drain
SD_BLOCK="$(awk '/^### Before you react/{f=1} f && /^```bash$/{b=1; next} b && /^```$/{exit} b' "$PROMPT_MD" 2>/dev/null || true)"
SD_BLOCK="${SD_BLOCK//<R>/$R}"
mkdir -p "$TMP/sdbin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/sdbin/gc" <<'SDGC'
printf 'GC %s\n' "$*" >> "$FAKE_LOG"
SDGC
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/sd-dispose" <<'SDD'
printf 'DISPOSE %s\n' "$*" >> "$FAKE_LOG"
exit "$FAKE_SD_RC"
SDD
chmod +x "$TMP/sdbin/gc" "$TMP/sd-dispose"
sd_block() {
  : > "$FAKE_LOG"
  RC=0
  OUT="$(FAKE_SD_RC="$1" DISPOSE="$TMP/sd-dispose" SUBJECT=tk-sub PATH="$TMP/sdbin:$PATH" \
    bash -c "$SD_BLOCK"$'\n''echo REACTING' 2>"$TMP/err")" || RC=$?
  ERR="$(cat "$TMP/err")"; LOG="$(cat "$FAKE_LOG")"
}
if [ -n "$SD_BLOCK" ]; then
  sd_block 0
  has "DISPOSE tk-sub --stand-down --reaction-bead $R" "$LOG" "(SDGATE) the prompt's block asks the stand-down about S and R"
  has "GC runtime drain-ack" "$LOG" "(SDGATE) exit 0, R closed, drains"
  hasnt "REACTING" "$OUT" "(SDGATE) …and does not go on to react"
  eq "$RC" "0" "(SDGATE) …and the block succeeds"

  sd_block 3
  has "REACTING" "$OUT" "(SDGATE) exit 3, neither marker, goes on to react"
  hasnt "drain-ack" "$LOG" "(SDGATE) …without draining"
  eq "$RC" "0" "(SDGATE) …and the block succeeds"

  for SD_RC in 1 2 4 127; do
    sd_block "$SD_RC"
    hasnt "REACTING" "$OUT" "(SDGATE) exit $SD_RC is no answer, so the block does not go on to react"
    hasnt "drain-ack" "$LOG" "(SDGATE) …and does not drain, since R is still open"
    [ "$RC" -ne 0 ] && ok "(SDGATE) …and the block fails" || bad "(SDGATE) …and the block fails (got $RC)"
    has "exited $SD_RC" "$ERR" "(SDGATE) …naming the status it stopped on"
  done
else
  bad "(SDGATE) no stand-down block under 'Before you react' in $PROMPT_MD"
fi

# ── A failed act refers to the cause ─────────────────────────────────────────
# gc-helm.sh exits non-zero for a release that did not write AND for a release
# whose route would not stamp, and only it knows which — so this refers to its
# message rather than asserting a state it cannot see.
export FAKE_HELM_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(HELMFAIL) a failed release is a runtime failure"
has "what landed and what did not" "$ERR" "(HELMFAIL) …and the failure refers to the cause gc-helm.sh named"
hasnt "disposed as actionable" "$OUT" "(HELMFAIL) …and nothing reports a disposition"
hasnt "gc.reacted_by" "$LOG" "(HELMFAIL) …and the landed proof is not stamped"
hasnt "UPDATE bd update $R" "$LOG" "(HELMFAIL) …and the reaction bead is not closed"
unset FAKE_HELM_FAILS

# ── Intake: only placed work, PR-finishing work or an emergency enters a pool ──
# Every case above routes a member of an epic. A bead with no parent waits for
# the operator's placement sitting instead: the actionable exit marks it
# placement=pending and releases it with no route, and the blocked exit's
# --then-route arms nothing.
#   (INTAKE)       an unplaced subject is marked and released unrouted, settled
#   (INTAKEORDER)  the marker lands before the release, the landed proof after
#   (INTAKENOTE)   the marker's write carries a note naming why it was held
#   (INTAKEPOOL)   the route it never writes is not probed
#   (INTAKEMEMBER) a parent-child dependency is membership even with no .parent,
#                  and a blocks edge is not
#   (INTAKEANCHOR) PR-finishing work (anchor_bead) is routed
#   (INTAKEMARK)   a marker that does not land stops the exit before the release
#   (INTAKESTAMP)  a pour stamp the release cannot clear from a held subject
#                  stops the exit before its landed proof
#   (INTAKEBLK)    an unplaced blocked subject's edge lands and nothing is armed
#   (INTAKEDRY)    a dry run names the hold and writes nothing
#   (INTAKEUNREAD) an unreadable subject proves no membership, so it is held
export FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "states a done condition and a branch" \
    --takeaway "ready to build once placed" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(INTAKE) an unplaced subject's actionable exit succeeds"
has "UPDATE bd update tk-sub --set-metadata placement=pending --append-notes ## Intake (first reaction" "$LOG" \
    "(INTAKE) …marking it placement=pending"
has "HELM takeaway tk-sub ready to build once placed --by proactive --release --no-wait" "$LOG" \
    "(INTAKE) …and releasing it with no route, nothing waiting on a bead"
hasnt "--route" "$LOG" "(INTAKE) …so no pool is offered it"
before 'placement=pending' '^HELM takeaway' "(INTAKEORDER) the marker lands before the release"
before '^HELM takeaway' 'gc.reacted_by' "(INTAKEORDER) …and the landed proof after it"
has "UPDATE bd update $R --set-metadata gc.outcome=reacted --set-metadata gc.work_outcome=no-op --status=closed" "$LOG" \
    "(INTAKE) …and the reaction bead closes"
has "disposed as actionable (held for placement)" "$OUT" "(INTAKE) …and the run says the bead is held for placement"
has "tk-sub has no parent epic and is not PR-finishing work" "$LOG" "(INTAKENOTE) the note names why it was held"
has "gc-helm.sh unplaced lists it" "$LOG" "(INTAKENOTE) …and where the sitting finds it"
hasnt "PROACTIVE deliverable" "$LOG" "(INTAKEPOOL) the route it never writes is not probed"
hasnt "GH " "$LOG" "(INTAKE) …and with no emergency claimed, GitHub is not read"

export FAKE_SHOW_JSON='[{"id":"tk-sub","dependencies":[{"id":"tk-feat","dependency_type":"parent-child","status":"open"}],"metadata":{}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
has "--release --route gc-toolkit/gc-toolkit.polecat --no-wait" "$LOG" "(INTAKEMEMBER) a parent-child dependency alone is membership"
hasnt "placement=pending" "$LOG" "(INTAKEMEMBER) …and a member is not marked"
export FAKE_SHOW_JSON='[{"id":"tk-sub","dependencies":[{"id":"tk-rl","dependency_type":"blocks","status":"open"}],"metadata":{}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
has "placement=pending" "$LOG" "(INTAKEMEMBER) a blocks edge onto an epic is not membership"
hasnt "--route" "$LOG" "(INTAKEMEMBER) …so the bead is not routed"

export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"anchor_bead":"tk-anchor"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(INTAKEANCHOR) PR-finishing work's actionable exit succeeds"
has "--release --route gc-toolkit/gc-toolkit.polecat --no-wait" "$LOG" "(INTAKEANCHOR) …and it is routed"
hasnt "placement=pending" "$LOG" "(INTAKEANCHOR) …unmarked"

export FAKE_SHOW_JSON="$UNPLACED" FAKE_DROP_PLACEMENT=always
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(INTAKEMARK) a marker that does not land stops the exit"
has "placement=pending did not land" "$ERR" "(INTAKEMARK) …naming the write that missed"
hasnt "HELM takeaway" "$LOG" "(INTAKEMARK) …before the release, so the bead is not left unrouted without its marker"
hasnt "gc.reacted_by" "$LOG" "(INTAKEMARK) …with no landed proof"
hasnt "UPDATE bd update $R" "$LOG" "(INTAKEMARK) …and the reaction bead open for a re-run"
export FAKE_DROP_PLACEMENT=once
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(INTAKEMARK) a marker that lands on the retry lets the exit through"
has "HELM takeaway tk-sub t --by proactive --release --no-wait" "$LOG" "(INTAKEMARK) …and the bead is released"
unset FAKE_DROP_PLACEMENT

# (INTAKESTAMP) a held subject still carries a dead pour's stamp, and the release
# cannot clear it. gc-helm.sh fails the release, because placement.sh reads the
# stamp as a live pour and the queue would not list the bead. The exit stops
# there, before its landed proof, so the reaction is not recorded done over a hold
# the sitting cannot see, and R stays open for a re-run.
export FAKE_EXEC_ROUTED_FILE="$TMP/exec_routed" FAKE_HELM_KEEPS_STAMP=1
printf 'gc-toolkit/gc-toolkit.polecat' > "$FAKE_EXEC_ROUTED_FILE"
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(INTAKESTAMP) a held subject whose pour stamp survives the release fails the exit"
has "HELM takeaway tk-sub t --by proactive --release --no-wait" "$LOG" "(INTAKESTAMP) …at the release"
has "gc-helm.sh takeaway failed on tk-sub" "$ERR" "(INTAKESTAMP) …naming the release that failed"
hasnt "gc.reacted_by" "$LOG" "(INTAKESTAMP) …with no landed proof"
hasnt "UPDATE bd update $R" "$LOG" "(INTAKESTAMP) …and the reaction bead open for a re-run"
# Control: the same stamp on a member is no hold, so the release warns and exits
# 0, and the reaction lands.
printf 'gc-toolkit/gc-toolkit.polecat' > "$FAKE_EXEC_ROUTED_FILE"
export FAKE_SHOW_JSON='[{"id":"tk-sub",'"$MEMBER"',"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(INTAKESTAMP) the same stamp on a member does not fail the exit"
has "gc.reacted_by" "$LOG" "(INTAKESTAMP) …and the landed proof is stamped"
unset FAKE_EXEC_ROUTED_FILE FAKE_HELM_KEEPS_STAMP

export FAKE_SHOW_JSON="$UNPLACED" FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "waits on the migration" --takeaway "held: migration first" \
    --waiting-on tk-blk1 --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(INTAKEBLK) an unplaced blocked subject's exit succeeds"
has "placement=pending" "$LOG" "(INTAKEBLK) …marked for placement"
has "--release --waiting-on tk-blk1" "$LOG" "(INTAKEBLK) …its wait still an edge"
hasnt "DEFERRED arm" "$LOG" "(INTAKEBLK) …and no dispatch armed: placing it is the sitting's"
hasnt "PROACTIVE deliverable" "$LOG" "(INTAKEBLK) …so the then-route is not probed"
has "disposed as blocked (tk-blk1; held for placement)" "$OUT" "(INTAKEBLK) …and the run names both waits"
unset FAKE_DEPS_JSON

export FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --dry-run
eq "$RC" "0" "(INTAKEDRY) a dry run of a held exit succeeds"
has "would hold tk-sub for placement (placement=pending, unrouted)" "$OUT" "(INTAKEDRY) …naming the hold"
hasnt "UPDATE" "$LOG" "(INTAKEDRY) …and writing nothing"

export FAKE_SHOW_JSON='not json'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(INTAKEUNREAD) an unreadable subject is held, and a marker it cannot read back stops the exit"
hasnt "HELM takeaway" "$LOG" "(INTAKEUNREAD) …so it is never routed on an unread membership"
unset FAKE_SHOW_JSON

# ── Intake's emergency: checked, not asserted ────────────────────────────────
# --emergency <check> claims a red main or a broken gate, naming the check whose
# failure it is about. The claim admits a bead at P0 only when that check is
# failing on the head of main, read from GitHub through the subject's own rig
# checkout.
#   (EMERG)       a confirmed emergency is written P0, read back, then routed
#   (EMERGSTATUS) a failing commit status confirms it as a failing check run does
#   (EMERGMEMBER) an emergency outranks membership: a member is routed at P0
#   (EMERGNO)     a green main confirms nothing, so the bead is held, and the
#                 note says what the check found
#   (EMERGOTHER)  another check failing on main confirms nothing, and neither
#                 does a check main does not carry; the note names what fails
#   (EMERGDOWN)   a check that cannot run confirms nothing
#   (EMERGPAGE)   a failure past the first page of check runs or commit
#                 statuses confirms it, because both are read across every page
#   (EMERGSLOW)   a GitHub that stalls is cut off at the bound and confirms
#                 nothing, so the exit lands rather than hold its pool slot
#   (EMERGPRIO)   a P0 that does not land stops the exit before the route
#   (EMERGBLK)    an emergency's then-route arms at P0
#   (EMERGARGS)   --emergency rides only a pool route, and names a check
mkdir -p "$TMP/rig/.beads"
export FAKE_RIG_PATH="$TMP/rig" FAKE_ORIGIN_URL="git@github.com:zook/repo.git"
export FAKE_SHOW_JSON="$UNPLACED" FAKE_GH=red
run tk-sub --disposition actionable --reason "test-macos fails on main" --takeaway "fix red main" \
    --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --reaction-bead "$R"
eq "$RC" "0" "(EMERG) a confirmed emergency's actionable exit succeeds"
has "GH api repos/zook/repo/commits/main/check-runs" "$LOG" "(EMERG) the claim is checked against main's own checks"
has "UPDATE bd update tk-sub --priority 0 --append-notes ## Intake (first reaction" "$LOG" "(EMERG) …P0 is written"
before '--priority 0' '^HELM takeaway' "(EMERG) …before the route"
has "--release --route gc-toolkit/gc-toolkit.polecat --no-wait" "$LOG" "(EMERG) …and the bead is routed"
hasnt "placement=pending" "$LOG" "(EMERG) …unmarked"
has "main of zook/repo at abcdef123456 is red: test-macos (failure)" "$LOG" "(EMERG) the note names the head and the failing check"
has "disposed as actionable (gc-toolkit/gc-toolkit.polecat at P0)" "$OUT" "(EMERG) …and the run says P0"

export FAKE_GH=status-red
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency ci/legacy --reaction-bead "$R"
has "--priority 0" "$LOG" "(EMERGSTATUS) a failing commit status confirms an emergency"
has "ci/legacy (failure)" "$LOG" "(EMERGSTATUS) …named in the note"

export FAKE_GH=red FAKE_SHOW_JSON="$DEFAULT_SHOW"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --reaction-bead "$R"
has "--priority 0" "$LOG" "(EMERGMEMBER) a member claimed as a confirmed emergency is written P0"
has "--release --route gc-toolkit/gc-toolkit.polecat" "$LOG" "(EMERGMEMBER) …and routed"

export FAKE_GH=green FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --reaction-bead "$R"
eq "$RC" "0" "(EMERGNO) an unconfirmed emergency's exit still lands"
has "placement=pending" "$LOG" "(EMERGNO) …held for placement"
hasnt "--priority" "$LOG" "(EMERGNO) …at the priority it was filed at"
hasnt "--route" "$LOG" "(EMERGNO) …and unrouted"
has "--emergency was not confirmed: test-macos is not failing on main of zook/repo at abcdef123456" "$LOG" \
    "(EMERGNO) the note says what the check found"
hasnt "other checks failing" "$LOG" "(EMERGNO) …and names no other failing check, because none fails"
export FAKE_GH=green FAKE_SHOW_JSON="$DEFAULT_SHOW"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --reaction-bead "$R"
has "--release --route gc-toolkit/gc-toolkit.polecat" "$LOG" "(EMERGNO) an unconfirmed emergency on a member still routes as a member"
hasnt "--priority" "$LOG" "(EMERGNO) …at its own priority"

# Main is red on test-macos. A claim naming a check that passes there, or one
# main does not carry, says nothing about this bead, so it is held.
export FAKE_GH=red FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency lint --reaction-bead "$R"
eq "$RC" "0" "(EMERGOTHER) a claim on a passing check, while another check fails, still lands"
has "placement=pending" "$LOG" "(EMERGOTHER) …held for placement"
hasnt "--priority" "$LOG" "(EMERGOTHER) …at the priority it was filed at"
hasnt "--route" "$LOG" "(EMERGOTHER) …and unrouted"
has "--emergency was not confirmed: lint is not failing on main of zook/repo at abcdef123456; other checks failing there: test-macos (failure)" "$LOG" \
    "(EMERGOTHER) the note names the claimed check and the check that does fail"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-windows --reaction-bead "$R"
has "placement=pending" "$LOG" "(EMERGOTHER) a claim on a check main does not carry is held"
has "main of zook/repo at abcdef123456 has no check named test-windows; other checks failing there: test-macos (failure)" "$LOG" \
    "(EMERGOTHER) …and the note says no check by that name runs there"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency=test-macos --reaction-bead "$R"
has "--priority 0" "$LOG" "(EMERGOTHER) --emergency=<check> names the check the same way"

export FAKE_GH=down FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --reaction-bead "$R"
eq "$RC" "0" "(EMERGDOWN) a GitHub that does not answer leaves the exit landing"
has "placement=pending" "$LOG" "(EMERGDOWN) …held, because an unread check confirms nothing"
has "GitHub did not answer for the default branch of zook/repo (gh exit 1)" "$LOG" "(EMERGDOWN) …and the note says so"
export FAKE_GH=red
unset FAKE_ORIGIN_URL
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --reaction-bead "$R"
has "placement=pending" "$LOG" "(EMERGDOWN) a checkout with no origin confirms nothing"
has "is not a GitHub repository" "$LOG" "(EMERGDOWN) …and the note names why"
hasnt "GH " "$LOG" "(EMERGDOWN) …and GitHub is not asked about a repository nobody named"
export FAKE_ORIGIN_URL="https://github.com/zook/repo"

export FAKE_GH=red-page2
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-e2e --reaction-bead "$R"
has "GH api repos/zook/repo/commits/main/check-runs?per_page=100 --paginate" "$LOG" "(EMERGPAGE) the check runs are read across every page"
has "--priority 0" "$LOG" "(EMERGPAGE) …so a failing run on the second page confirms the emergency"
has "test-e2e (timed_out)" "$LOG" "(EMERGPAGE) …named in the note"
export FAKE_GH=status-red-page2
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency ci/legacy --reaction-bead "$R"
has "GH api repos/zook/repo/commits/main/status?per_page=100 --paginate" "$LOG" "(EMERGPAGE) the commit statuses are read across every page"
has "--priority 0" "$LOG" "(EMERGPAGE) …so a failing status on the second page confirms the emergency"
has "ci/legacy (error)" "$LOG" "(EMERGPAGE) …named in the note"

export FAKE_GH=hang GC_FIRST_REACTION_GH_TIMEOUT=1
SLOW_T0=$SECONDS
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --reaction-bead "$R"
SLOW_DT=$((SECONDS - SLOW_T0))
eq "$RC" "0" "(EMERGSLOW) a GitHub that stalls leaves the exit landing"
[ "$SLOW_DT" -lt 15 ] && ok "(EMERGSLOW) …cut off at the bound rather than held for the stall (${SLOW_DT}s)" \
    || bad "(EMERGSLOW) …cut off at the bound rather than held for the stall (took ${SLOW_DT}s)"
has "placement=pending" "$LOG" "(EMERGSLOW) …held, because a read that ran out of time confirms nothing"
has "GitHub did not answer for the check runs on main of zook/repo within 1s" "$LOG" "(EMERGSLOW) …and the note says the read timed out"
unset GC_FIRST_REACTION_GH_TIMEOUT
export FAKE_GH=red

export FAKE_DROP_PRIORITY=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --reaction-bead "$R"
eq "$RC" "4" "(EMERGPRIO) a P0 that does not land stops the exit"
has "priority P0 did not land" "$ERR" "(EMERGPRIO) …naming the write that missed"
hasnt "HELM takeaway" "$LOG" "(EMERGPRIO) …before the route, so it is never claimable at the wrong priority"
unset FAKE_DROP_PRIORITY

export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --emergency test-macos --reaction-bead "$R"
eq "$RC" "0" "(EMERGBLK) a blocked emergency's exit succeeds"
before '--priority 0' '^DEFERRED arm' "(EMERGBLK) …P0 written before the arm"
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" "(EMERGBLK) …and the dispatch armed"
has "disposed as blocked (tk-blk1; armed at P0)" "$OUT" "(EMERGBLK) …and the run says the arm is at P0"
unset FAKE_DEPS_JSON

run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --emergency test-macos
eq "$RC" "2" "(EMERGARGS) --emergency beside --assign is refused"
eq "$LOG" "" "(EMERGARGS) …and nothing was written"
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --emergency test-macos
eq "$RC" "2" "(EMERGARGS) --emergency on a blocked exit that arms nothing is refused"
run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos
eq "$RC" "2" "(EMERGARGS) close refuses --emergency"
run tk-sub --disposition ruling --reason "r" --takeaway "t" --emergency test-macos
eq "$RC" "2" "(EMERGARGS) ruling refuses --emergency"
eq "$LOG" "" "(EMERGARGS) …and nothing was written"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R" --emergency
eq "$RC" "2" "(EMERGARGS) --emergency that names no check is refused"
has "needs the name of the check that fails on main" "$ERR" "(EMERGARGS) …saying what it needs"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
eq "$RC" "2" "(EMERGARGS) …and so is one followed by another flag instead of a check"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency= --reaction-bead "$R"
eq "$RC" "2" "(EMERGARGS) …and so is an empty --emergency="
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency "  " --reaction-bead "$R"
eq "$RC" "2" "(EMERGARGS) …and so is a blank check name"
eq "$LOG" "" "(EMERGARGS) …and nothing was written"
unset FAKE_SHOW_JSON FAKE_GH FAKE_ORIGIN_URL FAKE_RIG_PATH

# ── The notice, end to end through the real deferred-dispatch.sh ─────────────
# The stubbed tool above proves each exit asks for the notice. These runs hand
# the exits the real deferred-dispatch.sh over the same stubbed gc, so what the
# agent receives is pinned. The store stays unpinned, and the deferred-dispatch
# pass keeps its lock in this run's tmpdir.
#   (E2EASSIGN) --assign on a bead bd reports ready: the agent is mailed at
#               once, asking for its turn and naming the bead, and no notice
#               is left recorded
#   (E2EHELD)   --then-assign while the wait holds: no mail, the notice is
#               recorded for the agent, and a pass while bd still holds the
#               bead sends nothing
#   (E2ELIFT)   the wait lifts: the next pass mails the agent, naming the
#               bead, and retires the notice
#   (E2ENOTURN) --assign whose mail is saved but gets the agent no turn, from
#               the mail or from the nudge after it: the exit lands with the
#               notice still recorded, and the next pass, with the first mail
#               still unread in the mailbox, requests the turn with
#               gc session nudge and retires the notice
unset GC_RIG_ROOT GC_PACK_STATE_DIR GC_ORDER_OUTCOME_FILE
export DEFERRED_DISPATCH_STATE_DIR="$TMP/deferred-state" DEFERRED_DISPATCH_PASS_BUDGET_SECS=0
REAL_DD="$HERE/deferred-dispatch.sh"
GC_DEFERRED_DISPATCH_TOOL="$REAL_DD" FAKE_SUBJECT_READY=1 \
    run tk-sub --disposition actionable --reason "the remedy is a city.toml edit" \
    --takeaway "city.toml edit routed to mechanik" --assign gc-toolkit.mechanik --reaction-bead "$R"
eq "$RC" "0" "(E2EASSIGN) the --assign exit lands with the real deferred-dispatch.sh"
eq "$(grep -c '^MAIL ' "$FAKE_LOG")" "1" "(E2EASSIGN) the agent is mailed once"
has "MAIL mail send gc-toolkit.mechanik --notify" "$LOG" "(E2EASSIGN) …the agent the bead went to, asking for its turn"
has "Ready for you: tk-sub" "$LOG" "(E2EASSIGN) …naming the bead"
before '^HELM takeaway' '^MAIL ' "(E2EASSIGN) …once the release has made it the assignee"
before '^MAIL ' 'gc.reacted_by' "(E2EASSIGN) …and before the landed proof"
hasnt "NUDGE " "$LOG" "(E2EASSIGN) …with no nudge, since the mail requested the turn"
[ ! -e "$FAKE_STATE.notice" ] && ok "(E2EASSIGN) …leaving no notice recorded" \
    || bad "(E2EASSIGN) a notice sent at once is still recorded"

export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
GC_DEFERRED_DISPATCH_TOOL="$REAL_DD" \
    run tk-sub --disposition blocked --reason "the comment can change only once the order lands" \
    --takeaway "held: city.toml comment waits on the order" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik \
    --reaction-bead "$R"
eq "$RC" "0" "(E2EHELD) the --then-assign exit lands with the real deferred-dispatch.sh"
hasnt "MAIL " "$LOG" "(E2EHELD) no mail goes while the wait holds the bead"
has "--set-metadata gc.notify_when_ready=gc-toolkit.mechanik" "$LOG" "(E2EHELD) …the notice is recorded for the agent instead"
before '^UPDATE bd update tk-sub --set-metadata gc.notify_when_ready' 'gc.reacted_by' "(E2EHELD) …before the landed proof"
: > "$FAKE_LOG"
DD_RC=0; "$REAL_DD" reconcile >/dev/null 2>&1 || DD_RC=$?
eq "$DD_RC" "0" "(E2EHELD) a deferred-dispatch pass while the wait holds is clean"
hasnt "MAIL " "$(cat "$FAKE_LOG")" "(E2EHELD) …and sends nothing"
eq "$(cat "$FAKE_STATE.notice" 2>/dev/null)" "gc-toolkit.mechanik" "(E2EHELD) …keeping the notice for the agent"
DD_RC=0; FAKE_SUBJECT_READY=1 "$REAL_DD" reconcile >/dev/null 2>&1 || DD_RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$DD_RC" "0" "(E2ELIFT) the pass once the wait lifts is clean"
eq "$(grep -c '^MAIL ' "$FAKE_LOG")" "1" "(E2ELIFT) the agent is mailed once the wait lifts"
has "MAIL mail send gc-toolkit.mechanik --notify" "$LOG" "(E2ELIFT) …asking for its turn"
has "Ready for you: tk-sub" "$LOG" "(E2ELIFT) …naming the bead"
[ ! -e "$FAKE_STATE.notice" ] && ok "(E2ELIFT) …and the notice retires" \
    || bad "(E2ELIFT) the notice is still recorded after it was sent"

unset FAKE_DEPS_JSON
GC_DEFERRED_DISPATCH_TOOL="$REAL_DD" FAKE_SUBJECT_READY=1 FAKE_MAIL_NUDGE_FAILS=1 FAKE_NUDGE_FAILS=1 \
    run tk-sub --disposition actionable --reason "the remedy is a city.toml edit" \
    --takeaway "city.toml edit routed to mechanik" --assign gc-toolkit.mechanik --reaction-bead "$R"
eq "$RC" "0" "(E2ENOTURN) the --assign exit lands though no turn was requested, since the notice is recorded"
eq "$(grep -c '^MAIL ' "$FAKE_LOG")" "1" "(E2ENOTURN) the agent is mailed once"
eq "$(grep -c '^NUDGE ' "$FAKE_LOG")" "1" "(E2ENOTURN) …and, the mail having requested no turn, nudged once"
before '^NUDGE ' 'gc.reacted_by' "(E2ENOTURN) …before the landed proof"
eq "$(cat "$FAKE_STATE.notice" 2>/dev/null)" "gc-toolkit.mechanik" "(E2ENOTURN) …and the notice stays recorded for the agent"
has "nudge failed: fake nudge-store failure" "$ERR" "(E2ENOTURN) …and the mail's diagnostic reaches the exit's output"
: > "$FAKE_LOG"
DD_RC=0; FAKE_SUBJECT_READY=1 "$REAL_DD" reconcile >/dev/null 2>&1 || DD_RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$DD_RC" "0" "(E2ENOTURN) the next pass is clean"
eq "$(grep -c '^MAIL ' "$FAKE_LOG")" "1" "(E2ENOTURN) …it sends the mail again"
eq "$(wc -l < "$FAKE_STATE.mailbox" | tr -d ' ')" "1" "(E2ENOTURN) …which the dedup key keeps to the one copy in the mailbox"
has "NUDGE session nudge gc-toolkit.mechanik Ready for you: tk-sub" "$LOG" "(E2ENOTURN) …so it requests the turn with gc session nudge, naming the bead"
[ ! -e "$FAKE_STATE.notice" ] && ok "(E2ENOTURN) …and the notice retires" \
    || bad "(E2ENOTURN) the notice is still recorded after the turn was requested"
unset DEFERRED_DISPATCH_STATE_DIR DEFERRED_DISPATCH_PASS_BUDGET_SECS

echo ""
echo "first-reaction-dispose (exits, reaction-bead): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
