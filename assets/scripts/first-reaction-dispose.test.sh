#!/usr/bin/env bash
# Hermetic tests for first-reaction-dispose.sh — the exits a first reaction
# ends in, the status read before an exit's first write, and the order of each
# exit's writes that lets a re-offered reaction finish an exit its worker was
# cut off in. Runs the REAL script with a stubbed `gc`, a stubbed gc-helm.sh, a
# stubbed human-gate.sh, a stubbed gc-proactive.sh and a stubbed gctk (all
# reached through the tool-override env vars, gctk's through GCTK_BIN), so no
# live city, Dolt or network is touched. A store of human gates, through the
# real human-gate.sh, runs the gate exits twice, and the real
# tools/gc-proactive.sh check, on its fixture seam, reads the gate an exit
# filed. What each block guards is named above it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/first-reaction-dispose.sh"
PROACTIVE_REAL="$HERE/../../tools/gc-proactive.sh"
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
# writes — the log lines of every write the stubs record.
writes() { grep -E '^(UPDATE|SETSTATE|CREATE|HELM|GATE|SLING|NUDGE|CLOSE|BDGATE|DEP bd dep add|GCTK bead arm) ' "$FAKE_LOG" || true; }

[ -x "$SCRIPT" ] && ok "first-reaction-dispose.sh present and executable" \
                 || bad "first-reaction-dispose.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- stubs --------------------------------------------------------------------
# One ORDER log across every stub, so a case can say which write came first.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 ${2:-}" in
  "bd update")
    printf 'UPDATE %s\n' "$*" >> "$FAKE_LOG"
    # FAKE_NOTES_FAILS models a notes append that does not land, and
    # FAKE_UPDATE_REFUSE refuses an update whose arguments carry that text.
    if [ -n "${FAKE_UPDATE_REFUSE:-}" ]; then
      case " $* " in *"$FAKE_UPDATE_REFUSE"*) echo "Error updating: the store refused it" >&2; exit 1 ;; esac
    fi
    case " $* " in
      *" --append-notes "*) [ -n "${FAKE_NOTES_FAILS:-}" ] && exit 1 ;;
    esac
    # --if-status is bd's compare-and-swap: a guard that does not match the
    # status the bead shows writes nothing and exits 13.
    _prev=""; _guard=""
    for _a in "$@"; do [ "$_prev" = --if-status ] && _guard="$_a"; _prev="$_a"; done
    if [ -n "$_guard" ]; then
      _now="$(cat "$FAKE_STATE.status" 2>/dev/null || printf '%s' "${FAKE_SHOW_JSON:-$DEFAULT_SHOW}" | jq -r '.[0].status // "open"')"
      [ "$_now" = "$_guard" ] || { echo "Error: $3 is $_now, not $_guard; nothing was written" >&2; exit 13; }
    fi
    # Model read-after-write for gc.recommended_formula: apply the set/unset to
    # the state file a later `bd show` reflects.
    _prev=""; _reco_set=""; _reco_unset=""
    for _a in "$@"; do
      case "$_prev" in
        --set-metadata)   case "$_a" in
                            gc.recommended_formula=*) _reco_set="${_a#gc.recommended_formula=}" ;;
                          esac ;;
        --unset-metadata) case "$_a" in
                            gc.recommended_formula) _reco_unset=1 ;;
                          esac ;;
        # An emergency's P0, which a later `bd show` reflects.
        --priority) printf '%s' "$_a" > "$FAKE_STATE.priority" ;;
      esac
      _prev="$_a"
    done
    if [ -n "$_reco_set" ] || [ -n "$_reco_unset" ]; then
      [ -n "$_reco_set" ]   && printf '%s' "$_reco_set" > "$FAKE_STATE"
      [ -n "$_reco_unset" ] && : > "$FAKE_STATE"
    fi ;;
  "bd set-state")
    # Intake's hold, which a later `bd show` reflects. FAKE_SETSTATE_FAILS
    # models a write the store refuses.
    printf 'SETSTATE %s\n' "$*" >> "$FAKE_LOG"
    [ -n "${FAKE_SETSTATE_FAILS:-}" ] && exit 1
    case " $* " in
      *" hold=mayor "*) : > "$FAKE_STATE.hold" ;;
    esac ;;
  "bd create")
    printf 'CREATE %s\n' "$*" >> "$FAKE_LOG"
    [ -n "${FAKE_CREATE_FAILS:-}" ] && { printf '{"error":"nope"}\n'; exit 0; }
    # A create that carries --deps blocks:<bead> writes <bead>'s wait on the new
    # bead with it, as bd does in one transaction, so a later `gctk bead holds`
    # lists that wait as pending. FAKE_CREATE_LOST is a create that lands whole
    # and loses its reply.
    _prev=""; _blocks=""; _title=""
    for _a in "$@"; do
      case "$_prev" in
        --deps)  case "$_a" in blocks:*) _blocks="${_a#blocks:}" ;; esac ;;
        --title) _title="$_a" ;;
      esac
      _prev="$_a"
    done
    _new="${FAKE_NEW_ID:-tk-newblk}"
    if [ -n "$_blocks" ]; then
      jq -nc --arg id "$_new" --arg t "$_title" '{id: $id, type: "blocks", title: $t, status: "open", issue_type: "task"}' >> "$FAKE_STATE.pending"
    fi
    [ -n "${FAKE_CREATE_LOST:-}" ] && { echo "Error: the store did not answer" >&2; exit 1; }
    printf '[{"id":"%s"}]\n' "$_new" ;;
  "rig list")
    # A rig whose path has no .beads dir leaves the pin unresolved, which is
    # what every assertion below the PIN block expects.
    printf '{"rigs":[{"name":"gc-toolkit","path":"%s","prefix":"tk"}]}\n' "${FAKE_RIG_PATH:-/nonexistent-rig}" ;;
  "bd show")
    printf 'SHOW %s\n' "$*" >> "$FAKE_LOG"
    # Overlay the current gc.recommended_formula state (set by bd update above)
    # onto the fixture, so a later read sees what the last write actually did.
    # Intake's hold label, an emergency's priority and a status another writer
    # set overlay the same way.
    _base="${FAKE_SHOW_JSON:-$DEFAULT_SHOW}"
    _reco="$(cat "$FAKE_STATE" 2>/dev/null || printf '')"
    _priority="$(cat "$FAKE_STATE.priority" 2>/dev/null || printf '')"
    if [ -n "$_reco" ]; then
      _shown=$(printf '%s' "$_base" | jq -c --arg v "$_reco" '.[0].metadata = ((.[0].metadata // {}) + {"gc.recommended_formula": $v})' 2>/dev/null || printf '%s\n' "$_base")
    else
      _shown=$(printf '%s' "$_base" | jq -c '.[0].metadata = ((.[0].metadata // {}) | del(.["gc.recommended_formula"]))' 2>/dev/null || printf '%s\n' "$_base")
    fi
    [ -e "$FAKE_STATE.hold" ] && _shown=$(printf '%s' "$_shown" | jq -c '.[0].labels = ((.[0].labels // []) + ["hold:mayor"])' 2>/dev/null || printf '%s' "$_shown")
    [ -n "$_priority" ] && _shown=$(printf '%s' "$_shown" | jq -c --argjson v "$_priority" '.[0].priority = $v' 2>/dev/null || printf '%s' "$_shown")
    [ -e "$FAKE_STATE.status" ] && _shown=$(printf '%s' "$_shown" | jq -c --arg s "$(cat "$FAKE_STATE.status")" '.[0].status = $s' 2>/dev/null || printf '%s' "$_shown")
    printf '%s\n' "$_shown" ;;
  "bd list")
    printf 'LIST %s\n' "$*" >> "$FAKE_LOG"
    printf '%s\n' "${FAKE_LIST_JSON:-[]}" ;;
  "bd ready")
    # bd's ready set, which the hand-off to a named agent reads once the bead is
    # handed over. It holds tk-sub unless FAKE_WAITS says a blocker still holds
    # it. FAKE_READY_FAILS=1 is a read the store refuses, and
    # FAKE_READY_FAILS=object an answer that is no list.
    printf 'READY %s\n' "$*" >> "$FAKE_LOG"
    case "${FAKE_READY_FAILS:-}" in
      object) printf '{"error":"fake"}\n'; exit 0 ;;
      ?*) echo "Error: fake refusal" >&2; exit 1 ;;
    esac
    _ready='[{"id":"tk-other"},{"id":"tk-sub"}]'
    [ -n "${FAKE_WAITS:-}" ] && _ready='[{"id":"tk-other"}]'
    printf '%s\n' "$_ready" ;;
  "session nudge")
    # The nudge a ready hand-off gives the agent. FAKE_NUDGE_FAILS is a nudge
    # that names why it failed on stderr.
    printf 'NUDGE %s\n' "$*" >> "$FAKE_LOG"
    [ -n "${FAKE_NUDGE_FAILS:-}" ] && { echo "gc session nudge: fake refusal" >&2; exit 1; } ;;
  "bd dep")
    printf 'DEP %s\n' "$*" >> "$FAKE_LOG"
    # `dep list --json` answers with what the store holds AFTER the helm call.
    # `dep add` is the close exit's hold edge, and FAKE_DEP_FAILS models a hold
    # that did not land. FAKE_DEP_LIST_FAILS is a list the store refuses, with
    # nothing on stdout.
    case "${3:-}" in
      add)
        [ -z "${FAKE_DEP_FAILS:-}" ] || exit 1 ;;
      list)
        [ -z "${FAKE_DEP_LIST_FAILS:-}" ] || exit 1
        printf '%s\n' "${FAKE_DEPS_JSON:-[]}" ;;
    esac ;;
  "bd close") printf 'CLOSE %s\n' "$*" >> "$FAKE_LOG" ;;
  "bd gate") printf 'BDGATE %s\n' "$*" >> "$FAKE_LOG" ;;
  "sling "*) printf 'SLING %s\n' "$*" >> "$FAKE_LOG"
    # FAKE_SLING_RC is the exit gc sling returns: 3 is its live-workflow
    # conflict, the only code it exits on a bead a workflow of the same formula
    # already drives. FAKE_SLING_FAILS is a sling that names why it failed on
    # stderr.
    [ -n "${FAKE_SLING_FAILS:-}" ] && { echo "gc sling: fake refusal" >&2; exit 1; }
    [ "${FAKE_SLING_RC:-}" = 3 ] && { echo "gc sling: source bead tk-sub already has live workflow(s): tk-closer-root"; exit 3; }
    [ -n "${FAKE_SLING_RC:-}" ] && exit "$FAKE_SLING_RC" ;;
  "formula show")
    printf 'FORMULA %s\n' "$*" >> "$FAKE_LOG"
    # A recommended mol either resolves or it does not; FAKE_FORMULA_MISSING lists
    # names this run must treat as unresolvable, so the recommend exit's probe
    # refuses a typo the way the live `gc formula show` would (exit 1 on a name
    # it cannot load). Any other name falls through to the default success below.
    for _m in ${FAKE_FORMULA_MISSING:-}; do [ "${3:-}" = "$_m" ] && exit 1; done ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

cat > "$TMP/helm" <<'HELM'
#!/usr/bin/env bash
printf 'HELM %s\n' "$*" >> "$FAKE_LOG"
[ -n "${FAKE_HELM_FAILS:-}" ] && exit 4
# Model gc-helm.sh takeaway --release retiring the pour stamp. The shared-state
# file stands in for gc.execution_routed_to; a run that does not opt in
# (FAKE_EXEC_ROUTED_FILE unset) is unchanged. The arm does not depend on this
# clear: a plain arm lands whether or not the stamp is set. FAKE_HELM_KEEPS_STAMP
# leaves the stamp set behind a release that exits 0, as a pour that stamps it
# again after the release landed would. gc-helm.sh clears the stamp in the update
# whose exit it takes, so a release whose update the store refused
# exits 4, which FAKE_HELM_FAILS models.
case " $* " in
  *" --release "*)
    if [ -n "${FAKE_EXEC_ROUTED_FILE:-}" ] && [ -z "${FAKE_HELM_KEEPS_STAMP:-}" ]; then
      : > "$FAKE_EXEC_ROUTED_FILE"
    fi ;;
esac
exit 0
HELM
chmod +x "$TMP/helm"

# human-gate.sh files the human gate a ruling or recommend holds on and prints
# its id on stdout, as the real helper does. FAKE_GATE_FAILS models a gate that
# did not file. A --retract call is logged and changes nothing.
cat > "$TMP/human-gate" <<'HG'
#!/usr/bin/env bash
printf 'GATE %s\n' "$*" >> "$FAKE_LOG"
case " $* " in *" --retract "*) exit 0 ;; esac
[ -n "${FAKE_GATE_FAILS:-}" ] && exit 1
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

cat > "$TMP/gctk" <<'GCTK'
#!/usr/bin/env bash
printf 'GCTK %s\n' "$*" >> "$FAKE_LOG"
case "$1 ${2:-}" in
  "bead holds")
    # What holds each bead named, one line per bead in the order named, as gctk
    # bead holds prints it. The first is the subject: FAKE_HOLDS_JSON is its
    # line; unset, it waits on what the creates above recorded, and is clear
    # when they recorded nothing. Each other bead is a wait the caller names,
    # clear when the store holds it. The store holds a tk- bead unless
    # FAKE_HOLDS_MISSING names it, and no bead of another prefix, so such a bead
    # prints its error line and the command exits 1. FAKE_HOLDS_UNREAD names a
    # bead the store holds whose holds the read could not answer, which prints
    # an error line of another reason. FAKE_HOLDS_FAILS is a store that did not
    # answer, which prints every bead's error line and exits 1.
    shift 2; _ids=""
    while [ $# -gt 0 ]; do case "$1" in --db) shift 2 ;; --db=*) shift ;; *) _ids="$_ids $1"; shift ;; esac; done
    _rc=0; _subject=1
    for _id in $_ids; do
      if [ -n "${FAKE_HOLDS_FAILS:-}" ]; then printf '{"id":"%s","error":"the store did not answer"}\n' "$_id"; _rc=1
      elif [ -n "$_subject" ] && [ -n "${FAKE_HOLDS_JSON:-}" ]; then printf '%s\n' "$FAKE_HOLDS_JSON"
      elif [ -n "$_subject" ] && [ -s "$FAKE_STATE.pending" ]; then
        jq -sc --arg id "$_id" '{id: $id, status: "blocked", waits: ., pending: ., last_landed: "", in_flight: "", arm: null, foreign: []}' "$FAKE_STATE.pending"
      elif [ -z "$_subject" ] && case " ${FAKE_HOLDS_UNREAD:-} " in *" $_id "*) true ;; *) false ;; esac; then
        printf '{"id":"%s","error":"the store'"'"'s read could not answer %s: the store marks it blocked, and its blocked listing leaves it out"}\n' "$_id" "$_id"; _rc=1
      elif [ -z "$_subject" ] && case "$_id" in tk-*) case " ${FAKE_HOLDS_MISSING:-} " in *" $_id "*) true ;; *) false ;; esac ;; *) true ;; esac; then
        printf '{"id":"%s","error":"the store'"'"'s read could not answer %s: the store holds no such bead"}\n' "$_id" "$_id"; _rc=1
      else printf '{"id":"%s","status":"clear","waits":[],"pending":[],"last_landed":"","in_flight":"","arm":null,"foreign":[]}\n' "$_id"; fi
      _subject=""
    done
    exit "$_rc" ;;
  "bead arm")
    # FAKE_ARM_FAILS models an arm gctk bead arm refuses: it names why on
    # stderr and exits 1. gctk bead arm refuses on gc.routed_to and status, NOT
    # on gc.execution_routed_to — that stamp is a finished pour's provenance,
    # not a live queue — so a plain arm lands whether or not the release
    # cleared the stamp, which is what the stub does.
    [ -n "${FAKE_ARM_FAILS:-}" ] && { echo "gctk bead arm: ${FAKE_ARM_WHY:-$3 is dispatched already} (fake refusal)" >&2; exit 1; } ;;
esac
exit 0
GCTK
chmod +x "$TMP/gctk"

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
# yields malformed JSON. The default subject is an open member of an epic, which
# intake admits to a pool; UNPLACED is the same subject with no parent, which
# intake holds for placement. MEMBER splices the membership into a fixture of a
# test's own.
MEMBER='"parent":"tk-epic","dependencies":[{"id":"tk-epic","dependency_type":"parent-child","status":"open"}]'
UNPLACED='[{"id":"tk-sub","status":"open","metadata":{}}]'
export DEFAULT_SHOW='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{}}]'
export GC_HELM_TOOL="$TMP/helm" GCTK_BIN="$TMP/gctk" \
       GC_PROACTIVE_TOOL="$TMP/proactive" GC_HUMAN_GATE_TOOL="$TMP/human-gate"

ROOT="tk-root"   # the root of the reaction's run, which --run names

# run_now <args...> — run the script and read what it wrote, with the log and
# the state as they stand. run resets both first, then seeds the recommendation
# state from the fixture, so the first `bd show` matches FAKE_SHOW_JSON and
# later writes mutate it from there.
run_now() {
  RC=0; OUT="$("$SCRIPT" "$@" 2>"$TMP/err")" || RC=$?; ERR="$(cat "$TMP/err")"; LOG="$(cat "$FAKE_LOG")"
}
run() {
  : > "$FAKE_LOG"; rm -f "$FAKE_STATE.hold" "$FAKE_STATE.priority" "$FAKE_STATE.status" "$FAKE_STATE.pending"
  printf '%s' "${FAKE_SHOW_JSON:-$DEFAULT_SHOW}" \
    | jq -r '(.[0].metadata // {})["gc.recommended_formula"] // ""' > "$FAKE_STATE" 2>/dev/null || : > "$FAKE_STATE"
  run_now "$@"
}

# ── Usage: refuse before writing ─────────────────────────────────────────────
# Every refusal below happens with an empty log: a disposition that cannot be
# performed must not leave a half-written bead behind.
run tk-sub --disposition actionable --takeaway "t" --run "$ROOT"
eq "$RC" "2" "(ARGS) a disposition with no --reason is refused"
eq "$LOG" "" "(ARGS) …and nothing was written"
has "silent classification" "$ERR" "(ARGS) …and the refusal says why the reason is required"

run tk-sub --disposition sideways --reason "r" --takeaway "t" --run "$ROOT"
eq "$RC" "2" "(ARGS) an unknown disposition is refused"

run tk-sub --disposition actionable --reason "r" --run "$ROOT"
eq "$RC" "2" "(ARGS) a disposition with no --takeaway is refused"

run --disposition actionable --reason "r" --takeaway "t" --run "$ROOT"
eq "$RC" "2" "(ARGS) no bead id is refused"

# A first reaction never closes a bead, and a confident no-op is the close
# exit's validating closer.
run tk-sub --disposition superseded --reason "r" --takeaway "t" --run "$ROOT"
eq "$RC" "2" "(ARGS) superseded is not an exit — a reaction never closes its subject"

# (RUNARG) --run names the reaction's run, one bead id, which the gate's
# message carries for the check to find.
run tk-sub --disposition actionable --reason "r" --takeaway "t" --run tk-sub
eq "$RC" "2" "(RUNARG) --run naming the subject itself is refused"
eq "$LOG" "" "(RUNARG) …and nothing was written"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --run "tk-root; rm"
eq "$RC" "2" "(RUNARG) --run that is not one bead id is refused"
has "one bead id" "$ERR" "(RUNARG) …saying what it takes"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --run=
eq "$RC" "2" "(RUNARG) an empty --run is refused"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --run
eq "$RC" "2" "(RUNARG) --run with no value is refused"

# ── The status read: an exit writes only to an open subject ─────────────────
# The subject's status is read before the first write. A subject that is not
# open takes no write, whichever exit was asked for, and the exit says so with
# its own status, 3, which ends the reaction with nothing written.
#   (STATUS)       a closed or in-progress subject: exit 3, nothing written
#   (STATUSREAD)   a subject that does not read, or reads as another id: exit
#                  4, nothing written
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
for exit_args in "actionable --route gc-toolkit/gc-toolkit.polecat" "actionable --assign gc-toolkit.mechanik" \
                 "blocked --waiting-on tk-blk1 --then-route gc-toolkit/gc-toolkit.polecat" \
                 "close --route gc-toolkit/gc-toolkit.polecat" "ruling" "recommend --recommended-formula mol-x"; do
  for st in closed in_progress; do
    export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"'"$st"'",'"$MEMBER"',"metadata":{}}]'
    # shellcheck disable=SC2086  # one flag per word
    run tk-sub --run "$ROOT" --reason "r" --takeaway "t" --disposition $exit_args
    eq "$RC" "3" "(STATUS) --disposition ${exit_args%% *} on a $st subject exits 3"
    eq "$(writes)" "" "(STATUS) …and writes nothing"
    has "tk-sub is $st, and an exit writes only to an open subject" "$ERR" "(STATUS) …saying what the subject is"
  done
done
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"CLOSED",'"$MEMBER"',"metadata":{}}]'
run tk-sub --run "$ROOT" --reason "r" --takeaway "t" --disposition ruling --dry-run
eq "$RC" "3" "(STATUS) a dry run on a closed subject says the same"
export FAKE_SHOW_JSON='[{"id":"tk-sub",'"$MEMBER"',"metadata":{}}]'
run tk-sub --run "$ROOT" --reason "r" --takeaway "t" --disposition ruling
eq "$RC" "0" "(STATUS) a row with no status reads as open, as the check reads it"
export FAKE_SHOW_JSON='not json'
run tk-sub --run "$ROOT" --reason "r" --takeaway "t" --disposition actionable --assign gc-toolkit.mechanik
eq "$RC" "4" "(STATUSREAD) a subject that does not read stops the exit"
has "could not read tk-sub" "$ERR" "(STATUSREAD) …saying so"
eq "$(writes)" "" "(STATUSREAD) …before anything is written"
export FAKE_SHOW_JSON='[{"id":"tk-sub2","status":"open","metadata":{}}]'
run tk-sub --run "$ROOT" --reason "r" --takeaway "t" --disposition ruling
eq "$RC" "4" "(STATUSREAD) a read that answers with another bead's row stops the exit"
eq "$(writes)" "" "(STATUSREAD) …and nothing is written to the bead it named"
unset FAKE_SHOW_JSON FAKE_DEPS_JSON

# ── A reaction to a subject that closes ──────────────────────────────────────
# A reaction runs the check, writes its card guarded on the subject's status,
# then takes one exit. A subject closed before the check is refused by the
# check itself, and one closed between the card and the exit is refused by the
# exit's own read, so neither takes a write.
#   (CLOSEDCHECK)  the real check refuses a subject closed before it runs, and
#                  every exit refuses it too
#   (CLOSEDCARD)   the card lands on an open subject; once the subject closes,
#                  the exit writes nothing and a second card is refused
FX="$TMP/fx"; mkdir -p "$FX"
# check <run> — the real check, on its fixture seam: beads.json and holds.json
# under $FX answer its reads.
check() {
  RC=0; OUT="$(GC_PROACTIVE_FIXTURE="$FX" GC_RIG=gc-toolkit bash "$PROACTIVE_REAL" sling tk-sub --check --run "$1" 2>&1)" || RC=$?
}
printf '{"tk-sub": {"issue_type":"task","status":"closed",%s,"metadata":{}}}\n' "$MEMBER" > "$FX/beads.json"
: > "$FAKE_LOG"
check "$ROOT"
eq "$RC" "5" "(CLOSEDCHECK) the check refuses a subject closed before it runs (exit 5)"
has "its status is closed" "$OUT" "(CLOSEDCHECK) …naming the status, which the reaction declines with"
eq "$(writes)" "" "(CLOSEDCHECK) …and writes nothing"
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"closed",'"$MEMBER"',"metadata":{}}]'
run tk-sub --run "$ROOT" --reason "r" --takeaway "t" --disposition close --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "3" "(CLOSEDCHECK) an exit run on that subject anyway is refused as well"
eq "$(writes)" "" "(CLOSEDCHECK) …with nothing written"
unset FAKE_SHOW_JSON

: > "$FAKE_LOG"; rm -f "$FAKE_STATE.status" "$FAKE_STATE.hold" "$FAKE_STATE.priority" "$FAKE_STATE.pending"; : > "$FAKE_STATE"
CARD="# First reaction · run $ROOT · a subject that closes while it is read
## Disposition
ruling — r"
CARD_RC=0; gc bd update tk-sub --if-status open --append-notes "$CARD" 2>/dev/null || CARD_RC=$?
eq "$CARD_RC" "0" "(CLOSEDCARD) the card's guarded write lands on an open subject"
printf 'closed' > "$FAKE_STATE.status"
for exit_args in "actionable --route gc-toolkit/gc-toolkit.polecat" "blocked --waiting-on tk-blk1" \
                 "close --route gc-toolkit/gc-toolkit.polecat" "ruling" "recommend --recommended-formula mol-x"; do
  : > "$FAKE_LOG"
  # shellcheck disable=SC2086  # one flag per word
  run_now tk-sub --run "$ROOT" --reason "r" --takeaway "t" --disposition $exit_args
  eq "$RC" "3" "(CLOSEDCARD) --disposition ${exit_args%% *} after the subject closed exits 3"
  eq "$(writes)" "" "(CLOSEDCARD) …and writes nothing to the closed subject"
done
: > "$FAKE_LOG"
CARD_RC=0; gc bd update tk-sub --if-status open --append-notes "$CARD" 2>/dev/null || CARD_RC=$?
eq "$CARD_RC" "13" "(CLOSEDCARD) a card written after the close is refused by its guard (exit 13)"
rm -f "$FAKE_STATE.status"

# ── actionable: the bead is work, so hand it to a pool ───────────────────────
#   (ACT)      the release hands the bead on, and the run reports the pool
#   (ACTROUTE) the release carries the route, so the bead lands in a pool queue
#   (ACTRIG)   the target defaults from GC_RIG, and fails closed without one
run tk-sub --disposition actionable --reason "states a done condition and a branch" \
    --takeaway "routed to the polecat pool" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(ACT) an actionable disposition succeeds"
has "HELM takeaway tk-sub routed to the polecat pool --by proactive --release --route gc-toolkit/gc-toolkit.polecat" \
    "$LOG" "(ACTROUTE) the release hands the bead to the pool in one call"
# The headline's own disposition. Work handed to a pool is moving, not waiting,
# and the sitting says so where it stamps the sentence — nothing downstream can
# tell a settled headline from a park after the fact.
has "--no-wait" "$LOG" "(ACTROUTE) …and says nothing is waiting on it"
eq "$(grep -c '^HELM ' "$FAKE_LOG")" "1" "(ACT) …in the one write the exit makes"
hasnt "SETSTATE" "$LOG" "(ACT) …and a member is not held"
has "disposed as actionable (gc-toolkit/gc-toolkit.polecat)" "$OUT" "(ACT) …and the run reports the pool it routed to"
LOG_ACT="$LOG"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --waiting-on tk-other --run "$ROOT"
eq "$RC" "2" "(ACT) actionable refuses the other exits' flags"

# (ACTPOOL) a route to a pool nothing runs is worse than a human gate: the bead
# would be open, unassigned and offered to nobody.
has "PROACTIVE deliverable gc-toolkit/gc-toolkit.polecat tk-sub" "$LOG_ACT" \
    "(ACTPOOL) the exit asks whether the pool can claim this bead before handing over"
export FAKE_POOL_DEAD=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.nosuch --run "$ROOT"
eq "$RC" "2" "(ACTPOOL) a pool that cannot claim refuses the exit"
hasnt "HELM" "$LOG" "(ACTPOOL) …and the bead is not released"
has "address it with --assign" "$ERR" "(ACTPOOL) …and the refusal names the named-agent address before the operator"
has "only when the next move is the operator's" "$ERR" "(ACTPOOL) …keeping the operator's exits for the operator's own move"
unset FAKE_POOL_DEAD

# real_helm_run <args...> — run with the real gc-helm.sh in place of the stub.
# This fake's `bd update` keeps none of the keys a takeaway writes, and refuses
# an update that carries FAKE_UPDATE_REFUSE. A run cancel it reaches is logged
# as RUNCANCEL, and its board cache sits under $TMP.
printf '#!/usr/bin/env bash\nprintf "RUNCANCEL %%s\\n" "$*" >> "$FAKE_LOG"\n' > "$TMP/run-cancel"
chmod +x "$TMP/run-cancel"
real_helm_run() {
  local _tmpdir="${TMPDIR:-}"
  export GC_HELM_TOOL="$HERE/gc-helm.sh" GC_RUN_CANCEL_TOOL="$TMP/run-cancel" TMPDIR="$TMP"
  run "$@"
  export GC_HELM_TOOL="$TMP/helm"; unset GC_RUN_CANCEL_TOOL
  if [ -n "$_tmpdir" ]; then export TMPDIR="$_tmpdir"; else unset TMPDIR; fi
}

# (ACTREFUSED) the store refuses the real gc-helm.sh's release, over a subject
# carrying an earlier sitting's headline, an old route and assignee, and the
# session pins of the executor that held it. takeaway exits non-zero, so the
# exit stops there, and a re-run resumes.
export FAKE_SHOW_JSON='[{"id":"tk-sub",'"$MEMBER"',"status":"open","assignee":"gc-toolkit__proactive-hq-dead","metadata":{"gc.takeaway":"the sitting before this one parked it","gc.takeaway_at":"2026-11-01T09:00:00Z","gc.takeaway_by":"converse","gc.routed_to":"gc-toolkit/gc-toolkit.proactive","gc.session_name":"gc-toolkit__proactive-hq-dead","gc.session_id":"gc-dead-session"}}]'
export FAKE_UPDATE_REFUSE='gc.takeaway='
real_helm_run tk-sub --disposition actionable --reason "states a done condition and a branch" \
    --takeaway "routed to the polecat pool" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
unset FAKE_SHOW_JSON FAKE_UPDATE_REFUSE
eq "$RC" "4" "(ACTREFUSED) a release the store refuses fails the actionable exit"
has "could not update 'tk-sub'" "$ERR" "(ACTREFUSED) …after the real gc-helm.sh says its update was refused"
hasnt "RUNCANCEL" "$LOG" "(ACTREFUSED) …so no run is ended"
hasnt "disposed as actionable" "$OUT" "(ACTREFUSED) …and nothing reports a disposition"

: > "$FAKE_LOG"; RC=0
OUT="$(GC_RIG=gc-toolkit "$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" --run "$ROOT" 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(ACTRIG) with GC_RIG set, the pool target needs no flag"
has "--route gc-toolkit/gc-toolkit.polecat" "$LOG" "(ACTRIG) …and defaults to this rig's polecat pool"

: > "$FAKE_LOG"; RC=0
ERR="$(env -u GC_RIG "$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" --run "$ROOT" 2>&1 >/dev/null)" || RC=$?
eq "$RC" "2" "(ACTRIG) with no GC_RIG and no --route it fails closed"
eq "$(cat "$FAKE_LOG")" "" "(ACTRIG) …and writes nothing"
has "routes to nobody" "$ERR" "(ACTRIG) …and names what a bare target would cost"

# ── actionable --assign: work that is a named agent's own ────────────────────
# A town-repo edit is mechanik's direct edit, and mechanik is a named agent that
# claims through its hook, so the exit hands the bead TO it through Gas City's
# hand-off (docs/deferred-dispatch.md) instead of routing it to a pool.
#   (ACTASSIGN)  the release leaves the bead at rest, unassigned and unrouted,
#                and still says nothing waits; the run names the agent
#   (ACTASSIGN)  the exit asks whether the agent's hook would offer the bead,
#                and does not ask the pool question
#   (ACTHANDOFF) gc sling then routes the bead to the agent's own name, raw: no
#                formula and no convoy, after the release, with no arm and no
#                assignee; bd's ready set, read once the bead is routed, holds
#                it, so gc session nudge gives the agent a turn for it
#   (ACTWAITS)   an actionable bead bd does not report ready is handed over
#                with no nudge, which its blocker's close sends
#   (ASSIGNNO)   an agent that cannot be handed the bead refuses the exit
#   (ASSIGNBOTH) --route and --assign together are refused
#   (ASSIGNRIG)  a named agent needs no GC_RIG to qualify it
run tk-sub --disposition actionable --reason "the remedy is a city.toml edit, mechanik's direct edit" \
    --takeaway "city.toml edit routed to mechanik" --assign gc-toolkit.mechanik --run "$ROOT"
eq "$RC" "0" "(ACTASSIGN) an actionable disposition addressed to a named agent succeeds"
has "disposed as actionable (gc-toolkit.mechanik)" "$OUT" "(ACTASSIGN) …and the run names the agent it went to"
has "HELM takeaway tk-sub city.toml edit routed to mechanik --by proactive --release --no-wait" \
    "$LOG" "(ACTASSIGN) the release leaves the bead at rest and says nothing waits, in one call"
hasnt "--assign" "$(grep '^HELM' "$FAKE_LOG")" "(ACTASSIGN) …writing no assignee"
hasnt "--route" "$(grep '^HELM' "$FAKE_LOG")" "(ACTASSIGN) …and no pool route"
has "PROACTIVE assignable gc-toolkit.mechanik tk-sub" "$LOG" "(ACTASSIGN) the exit asks whether the agent's hook would offer this bead"
hasnt "PROACTIVE deliverable" "$LOG" "(ACTASSIGN) …and does not ask the pool question of a named agent"
has "gc-toolkit.mechanik tk-sub --no-formula --no-convoy" "$(grep '^SLING ' "$FAKE_LOG")" \
    "(ACTHANDOFF) gc sling hands the bead to the agent's own name, pouring no formula and filing no convoy"
eq "$(grep -c '^SLING ' "$FAKE_LOG")" "1" "(ACTHANDOFF) …once"
before '^HELM takeaway' '^SLING ' "(ACTHANDOFF) …after the release leaves the bead at rest"
hasnt "GCTK" "$LOG" "(ACTHANDOFF) …arming nothing for a named agent"
has "NUDGE session nudge gc-toolkit.mechanik tk-sub is routed to you and ready" "$LOG" \
    "(ACTHANDOFF) the agent is nudged with the bead's id, since a route alone gives it no turn"
has "READY bd ready --brief --json --limit 0" "$LOG" "(ACTHANDOFF) …once bd's ready set, read whole, holds the bead"
before '^SLING ' '^READY ' "(ACTHANDOFF) …read once the bead is routed to the agent"
before '^READY ' '^NUDGE ' "(ACTHANDOFF) …and before the nudge"

export FAKE_WAITS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --run "$ROOT"
eq "$RC" "0" "(ACTWAITS) an actionable bead bd does not report ready is still handed over"
has "gc-toolkit.mechanik tk-sub --no-formula --no-convoy" "$(grep '^SLING ' "$FAKE_LOG")" "(ACTWAITS) …routed to the agent"
hasnt "NUDGE" "$LOG" "(ACTWAITS) …with no nudge while a blocker holds it"
unset FAKE_WAITS

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
has "SLING sling gc-toolkit.mechanik tk-sub --no-formula --no-convoy" "$LOG" "(ASSIGNRIG) …because a named agent is addressed by its own name"

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
has "would hand tk-sub to named agent gc-toolkit.mechanik (gc sling gc-toolkit.mechanik tk-sub --no-formula --no-convoy) and nudge it" "$OUT" \
    "(ASSIGNDRY) …and names the agent it would hand the bead to, and how"
hasnt "UPDATE" "$(cat "$FAKE_LOG")" "(ASSIGNDRY) …writing nothing"
hasnt "SLING" "$(cat "$FAKE_LOG")" "(ASSIGNDRY) …and handing nothing over"

# (HANDOFFFAIL) a hand-off gc sling refused leaves the agent's hook without the
# bead, so the exit fails, and a re-run resumes it.
export FAKE_SLING_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --run "$ROOT"
eq "$RC" "4" "(HANDOFFFAIL) an --assign whose hand-off did not land fails the exit"
has "gc sling did not hand it to gc-toolkit.mechanik (exit 1: gc sling: fake refusal" "$ERR" "(HANDOFFFAIL) …with gc sling's own reason"
has "HELM takeaway tk-sub" "$LOG" "(HANDOFFFAIL) …after the release, which stands"
has "a re-run resumes" "$ERR" "(HANDOFFFAIL) …and the failure says a re-run resumes"
hasnt "NUDGE" "$LOG" "(HANDOFFFAIL) …and no agent nudged about a bead it was not handed"
unset FAKE_SLING_FAILS
export FAKE_NUDGE_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --run "$ROOT"
eq "$RC" "4" "(HANDOFFFAIL) an --assign whose nudge did not reach the agent fails the exit"
has "gc session nudge did not reach the agent (exit 1: gc session nudge: fake refusal" "$ERR" "(HANDOFFFAIL) …with the nudge's own reason"
has "SLING " "$LOG" "(HANDOFFFAIL) …after the route, which stands"
unset FAKE_NUDGE_FAILS

# (HANDOFFREAD) a readiness read that does not answer leaves whether the agent
# is owed a nudge unknown, so the exit fails, rather than read the bead as
# waiting, and the re-run reads it again.
for read_case in "1|exited 1" "object|answered no list"; do
    export FAKE_READY_FAILS="${read_case%%|*}"
    run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --run "$ROOT"
    eq "$RC" "4" "(HANDOFFREAD) a readiness read that ${read_case#*|} fails the exit"
    has "whether bd reports it ready could not be read (gc bd ready ${read_case#*|})" "$ERR" \
        "(HANDOFFREAD) …saying the read did not answer"
    has "SLING " "$LOG" "(HANDOFFREAD) …after the route, which stands"
    hasnt "NUDGE" "$LOG" "(HANDOFFREAD) …with no nudge"
done
unset FAKE_READY_FAILS

# (HANDOFFTOOL) the hand-off is gc sling's, so --assign lands with no gctk
# binary to arm with.
GCTK_BIN="$TMP/no-such-gctk" \
    run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --run "$ROOT"
eq "$RC" "0" "(HANDOFFTOOL) --assign lands with no gctk binary"
has "SLING " "$LOG" "(HANDOFFTOOL) …handing the bead over"

# ── A named agent takes the bead in the form it finds its work in ────────────
# docs/authority-map.md's Route work row: the mechanik claims through its hook
# and takes a route (above). The refinery and the keeper list the beads
# assigned to them, which a route never reaches, so each takes the assignee.
# The deacon and the witness patrol their own wisps and take no bead.
#   (ACTREFINERY) --assign to the refinery or the keeper writes the agent as the
#                 assignee in the release, routes nothing, and nudges it, since
#                 the bead is ready now
#   (REFFIND)     the refinery's own find-work, the script its patrol's
#                 find-work step runs, takes the bead as that release leaves
#                 it, and takes nothing for a bead the release left unassigned
#   (BLKREFINERY) --then-assign to the refinery writes the assignee beside the
#                 wait, and sends no nudge while the bead waits
#   (BLKREADY)    a --then-assign whose blocker has closed already, so that no
#                 blocker close is left to nudge the agent, finds the bead in
#                 bd's ready set once it is handed over, and nudges the agent
#   (PATROL)      the deacon and the witness are refused before anything is read
#                 or written, and the refusal names the mail that reaches them
#   (UNNAMED)     an agent the row does not name is refused the same way

# The refinery's find-work as its patrol runs it: refinery-find-work.sh, which
# the formula's find-work step calls, over a store that holds tk-sub, an open
# task with a branch, as the last release in the log left it: assigned to the
# agent its --assign named, or to nobody. Nothing holds it, and no other bead
# works its branch.
FIND_STEP="$(awk '/^id = "find-work"$/{f=1} f && /^\[\[steps\]\]$/{exit} f' "$HERE/../../formulas/mol-refinery-patrol.toml")"
case "$FIND_STEP" in
    *refinery-find-work.sh*) ok "(REFFIND) the refinery's patrol runs refinery-find-work.sh in its find-work step" ;;
    *) bad "(REFFIND) mol-refinery-patrol.toml's find-work step does not run refinery-find-work.sh" ;;
esac
mkdir -p "$TMP/store-bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/store-bin/gc" <<'STORE'
[ "$1 ${2:-}" = "bd list" ] || exit 2
want=""
for a in "$@"; do case "$a" in --assignee=*) want="${a#--assignee=}" ;; esac; done
had="$(grep '^HELM takeaway tk-sub ' "$FAKE_LOG" | tail -n 1 | sed -n 's/.* --release.* --assign \([^ ]*\).*/\1/p')"
if [ -n "$want" ] && [ "$want" = "$had" ]; then
  printf '[{"id":"tk-sub","status":"open","issue_type":"task","assignee":"%s","metadata":{"branch":"polecat/tk-sub"}}]\n' "$had"
else
  printf '[]\n'
fi
STORE
chmod +x "$TMP/store-bin/gc"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/store-bin/gctk" <<'HOLDS'
[ "$1 ${2:-}" = "bead holds" ] || exit 2
shift 2
for id in "$@"; do printf '{"id":"%s","status":"clear","waits":[]}\n' "$id"; done
HOLDS
chmod +x "$TMP/store-bin/gctk"
find_work() { # <agent> — the bead the agent's find-work takes, or nothing
  ( export PATH="$TMP/store-bin:$PATH" GC_RIG=gc-toolkit GC_AGENT="$1" GCTK_BIN="$TMP/store-bin/gctk"
    "$HERE/refinery-find-work.sh" 2>/dev/null )
}

export FAKE_SHOW_JSON='[{"id":"tk-sub",'"$MEMBER"',"status":"open","metadata":{"branch":"polecat/tk-sub"}}]'
run tk-sub --disposition actionable --reason "the branch is ready for the merge queue" \
    --takeaway "branch handed to the refinery" --assign gc-toolkit/gc-toolkit.refinery --run "$ROOT"
eq "$RC" "0" "(ACTREFINERY) an actionable disposition addressed to the refinery succeeds"
has "HELM takeaway tk-sub branch handed to the refinery --by proactive --release --assign gc-toolkit/gc-toolkit.refinery --no-wait" "$LOG" \
    "(ACTREFINERY) the release writes the refinery as the assignee and says nothing waits, in one call"
hasnt "SLING" "$LOG" "(ACTREFINERY) …and routes nothing"
has "PROACTIVE assignable gc-toolkit/gc-toolkit.refinery tk-sub" "$LOG" "(ACTREFINERY) the exit asks whether the agent can be handed the bead"
has "NUDGE session nudge gc-toolkit/gc-toolkit.refinery tk-sub is assigned to you and ready" "$LOG" \
    "(ACTREFINERY) the refinery is nudged with the bead's id, since an assignee alone gives it no turn"
before '^HELM takeaway' '^NUDGE ' "(ACTREFINERY) …once the release has assigned it"
eq "$(find_work gc-toolkit/gc-toolkit.refinery)" "tk-sub" "(REFFIND) the refinery's own find-work takes the bead the exit handed it"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --run "$ROOT"
eq "$(find_work gc-toolkit/gc-toolkit.refinery)" "" "(REFFIND) …and takes nothing for a bead the release left unassigned, as a route leaves it"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gascity/gascity-keeper.keeper --run "$ROOT"
eq "$RC" "0" "(ACTREFINERY) the keeper takes the bead the same way"
has "--release --assign gascity/gascity-keeper.keeper --no-wait" "$LOG" "(ACTREFINERY) …as its assignee, written in the release"
hasnt "SLING" "$LOG" "(ACTREFINERY) …with no route"
has "NUDGE session nudge gascity/gascity-keeper.keeper tk-sub is assigned to you and ready" "$LOG" "(ACTREFINERY) …and a nudge"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit/gc-toolkit.refinery --dry-run
eq "$RC" "0" "(ACTREFINERY) a dry run of the refinery's hand-off succeeds"
has "would release tk-sub to named agent gc-toolkit/gc-toolkit.refinery as its assignee and nudge it" "$OUT" \
    "(ACTREFINERY) …and names the form it would take"
hasnt "HELM" "$LOG" "(ACTREFINERY) …releasing nothing"

export FAKE_NUDGE_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit/gc-toolkit.refinery --run "$ROOT"
eq "$RC" "4" "(HANDOFFFAIL) an assignee whose nudge did not reach the agent fails the exit"
has "It is assigned to gc-toolkit/gc-toolkit.refinery, but gc session nudge did not reach the agent" "$ERR" \
    "(HANDOFFFAIL) …saying the assignment stands"
unset FAKE_NUDGE_FAILS

export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]' FAKE_WAITS=1
run tk-sub --disposition blocked --reason "the hand-off waits on the unit it brings in" \
    --takeaway "held: bring-current waits on the unit" --waiting-on tk-blk1 --then-assign gc-toolkit/gc-toolkit.refinery \
    --run "$ROOT"
eq "$RC" "0" "(BLKREFINERY) a blocked disposition handed to the refinery succeeds"
has "--release --waiting-on tk-blk1 --assign gc-toolkit/gc-toolkit.refinery" "$LOG" \
    "(BLKREFINERY) the release writes the wait and the assignee in one call"
hasnt "SLING" "$LOG" "(BLKREFINERY) …routing nothing"
before '^HELM takeaway' '^READY ' "(BLKREFINERY) …then reads whether bd reports the bead ready"
hasnt "NUDGE" "$LOG" "(BLKREFINERY) …and sends no nudge while the bead still waits"
unset FAKE_WAITS
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit/gc-toolkit.refinery --dry-run
has "would release tk-sub to named agent gc-toolkit/gc-toolkit.refinery as its assignee and nudge it if bd reports the bead ready; while the wait holds, Gas City nudges it when the blocker closes" "$OUT" \
    "(BLKREFINERY) a dry run names the form it would take"

run tk-sub --disposition blocked --reason "the hand-off waited on a unit that has landed" \
    --takeaway "held: bring-current waits on the unit" --waiting-on tk-blk1 --then-assign gc-toolkit/gc-toolkit.refinery \
    --run "$ROOT"
eq "$RC" "0" "(BLKREADY) a blocked disposition whose blocker has closed already succeeds"
has "--release --waiting-on tk-blk1 --assign gc-toolkit/gc-toolkit.refinery" "$LOG" \
    "(BLKREADY) …writing the wait and the assignee as before"
has "NUDGE session nudge gc-toolkit/gc-toolkit.refinery tk-sub is assigned to you and ready" "$LOG" \
    "(BLKREADY) the refinery is nudged, since bd reports the bead ready and no blocker close is left to nudge it"
before '^HELM takeaway' '^READY ' "(BLKREADY) …once the release has assigned it"
before '^READY ' '^NUDGE ' "(BLKREADY) …and bd's ready set holds it"
unset FAKE_DEPS_JSON FAKE_SHOW_JSON

for who in gc-toolkit.deacon deacon gc-toolkit/gc-toolkit.witness; do
    run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign "$who" --run "$ROOT"
    eq "$RC" "2" "(PATROL) --assign $who is refused"
    has "--assign $who names an agent that patrols its own wisps and takes no bead" "$ERR" "(PATROL) …saying why"
    has "gc mail send $who" "$ERR" "(PATROL) …and naming the mail that reaches it"
    eq "$LOG" "" "(PATROL) …before anything is read or written"
done
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit/gc-toolkit.witness --run "$ROOT"
eq "$RC" "2" "(PATROL) --then-assign naming the witness is refused"
has "--then-assign gc-toolkit/gc-toolkit.witness names an agent that patrols its own wisps" "$ERR" "(PATROL) …naming the flag"
eq "$LOG" "" "(PATROL) …and nothing was read or written"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit/gc-toolkit.dog --run "$ROOT"
eq "$RC" "2" "(UNNAMED) an agent the Route work row does not name is refused"
has "--assign gc-toolkit/gc-toolkit.dog names no agent this exit can hand a bead to" "$ERR" "(UNNAMED) …saying which agents it can"
eq "$LOG" "" "(UNNAMED) …before anything is read or written"

# ── blocked: the wait is an edge, in one store ───────────────────────────────
#   (BLK)        the release carries the wait as --waiting-on
#   (BLKHOLDS)   what holds the subject is read before the first write, in the
#                subject's store, and a read that does not answer, for the
#                subject or for a bead it would wait on, writes nothing
#   (BLKFOREIGN) a subject with a wait edge into another store takes no write,
#                and the refusal names the edge and its removal
#   (BLKCROSS)   a --waiting-on the subject's store does not hold, such as one
#                in another store, is refused before anything is written, so a
#                --blocker or an emergency riding along writes nothing either
#   (BLKSELF)    a bead never waits on itself
#   (BLKNEW)     --blocker files the missing bead and waits on it, the wait
#                riding the bead's create
#   (BLKRETRY)   an exit that stops after it filed the blocker, at a release
#                the store refuses, waits on that blocker when it is run again
#   (BLKLOST)    a create that landed and lost its reply stops the exit, and a
#                re-run waits on the blocker that landed
#   (BLKREUSE)   a pending wait of the subject's with the blocker's title is
#                reused, so a re-run files no second bead
#   (BLKEDGE)    an edge takeaway could not write fails the exit before any arm
#   (BLKARM)     --then-route arms the dispatch that resumes the work
#   (BLKARMFAIL) an arm that did not land fails the exit the same way, and a
#                re-run arms
#   (BLKARMTOOL) a blocked exit with no gctk binary to read its holds or arm is
#                refused before anything is written
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "waits on the schema migration" \
    --takeaway "held: schema migration first" --waiting-on tk-blk1 --run "$ROOT"
eq "$RC" "0" "(BLK) a blocked disposition succeeds"
has "--release --waiting-on tk-blk1" "$LOG" "(BLK) the wait rides the release as an edge"
hasnt "--route" "$LOG" "(BLK) …and a held bead is not also routed"
hasnt "--no-wait" "$LOG" "(BLK) …and the named wait is not also called settled"
has "disposed as blocked (tk-blk1)" "$OUT" "(BLK) …and the run reports the bead it waits on"
has "GCTK bead holds tk-sub" "$LOG" "(BLKHOLDS) the exit reads what holds the subject"
before '^GCTK bead holds' '^HELM takeaway' "(BLKHOLDS) …before its first write"

FAKE_HOLDS_FAILS=1 run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(BLKHOLDS) a holds read that does not answer stops the exit"
has "could not read what holds tk-sub" "$ERR" "(BLKHOLDS) …saying so"
eq "$(writes)" "" "(BLKHOLDS) …and nothing is written"

# An error line for a reason other than the store holding no such bead is a
# read that did not answer for a bead the store may hold, so it says nothing
# about whether an edge onto that bead would hold the subject.
FAKE_HOLDS_UNREAD=tk-blk1 run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --run "$ROOT"
eq "$RC" "4" "(BLKHOLDS) a wait the read could not answer for stops the exit"
has "could not read whether tk-sub's store holds tk-blk1" "$ERR" "(BLKHOLDS) …saying so"
has "its blocked listing leaves it out" "$ERR" "(BLKHOLDS) …with the read's reason"
hasnt "is not a bead tk-sub's store holds" "$ERR" "(BLKHOLDS) …and not that the store does not hold it"
eq "$(writes)" "" "(BLKHOLDS) …and nothing is written"

export FAKE_HOLDS_JSON='{"id":"tk-sub","status":"clear","waits":[],"pending":[],"foreign":[{"id":"ra-elsewhere","type":"blocks"}]}'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(BLKFOREIGN) a subject with a wait edge into another store is refused"
has "carries a wait edge into another store (ra-elsewhere (blocks)), which holds nothing" "$ERR" "(BLKFOREIGN) …naming the edge"
has "gc bd dep remove tk-sub ra-elsewhere" "$ERR" "(BLKFOREIGN) …and its removal"
eq "$(writes)" "" "(BLKFOREIGN) …before anything is written"
unset FAKE_HOLDS_JSON

# The read of what holds the subject names each --waiting-on, and the store
# answers a bead it does not hold with an error line, so the exit refuses the
# wait before its first write. The --blocker it would file and an emergency's
# P0, both written before the release that writes the wait, land no more than
# the wait does.
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on ra-foreign --run "$ROOT"
eq "$RC" "2" "(BLKCROSS) a blocker in another store is refused"
has "GCTK bead holds tk-sub ra-foreign" "$LOG" "(BLKCROSS) …which the read of what holds the subject names"
eq "$(writes)" "" "(BLKCROSS) …before anything is written"
has "the store holds no such bead" "$ERR" "(BLKCROSS) …saying the store does not hold it"
has "store that names it instead" "$ERR" "(BLKCROSS) …and naming the remedy"
FAKE_HOLDS_MISSING=tk-gone run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-gone --run "$ROOT"
eq "$RC" "2" "(BLKCROSS) a blocker this store does not hold is refused the same way"
eq "$(writes)" "" "(BLKCROSS) …writing nothing"
run tk-sub --disposition blocked --reason "r" --takeaway "t" --blocker "Migrate the seed schema" \
    --waiting-on ra-foreign --run "$ROOT"
eq "$RC" "2" "(BLKCROSS) a --blocker beside a wait in another store is refused too"
eq "$(writes)" "" "(BLKCROSS) …filing no blocker"
mkdir -p "$TMP/rig/.beads"
FAKE_RIG_PATH="$TMP/rig" FAKE_ORIGIN_URL="git@github.com:zook/repo.git" FAKE_GH=red FAKE_SHOW_JSON="$UNPLACED" \
    run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on ra-foreign \
    --then-route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
eq "$RC" "2" "(BLKCROSS) an emergency waiting on a bead in another store is refused"
has "GH api repos/zook/repo/commits/main/check-runs" "$LOG" "(BLKCROSS) …once its claim is checked"
eq "$(writes)" "" "(BLKCROSS) …writing no P0"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-sub --run "$ROOT"
eq "$RC" "2" "(BLKSELF) a bead cannot wait on itself"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --run "$ROOT"
eq "$RC" "2" "(BLK) blocked with no wait at all is refused"
has "prose about it holds nothing" "$ERR" "(BLK) …and the refusal says why"

export FAKE_NEW_ID=tk-filed FAKE_DEPS_JSON='[{"id":"tk-filed"}]'
run tk-sub --disposition blocked --reason "nothing tracks the migration yet" \
    --takeaway "held: the migration is now filed" --blocker "Migrate the seed schema" --run "$ROOT"
eq "$RC" "0" "(BLKNEW) a wait that is not a bead yet is filed"
has "CREATE bd create -t task --title Migrate the seed schema" "$LOG" "(BLKNEW) …as a bead"
has "--deps blocks:tk-sub" "$(grep '^CREATE' "$FAKE_LOG")" "(BLKNEW) …whose create writes the subject's wait on it"
eq "$(grep -c '^CREATE' "$FAKE_LOG")" "1" "(BLKNEW) …once"
has "--waiting-on tk-filed" "$LOG" "(BLKNEW) …and the subject waits on it"
before '^CREATE' '^HELM takeaway' "(BLKNEW) …filed before the release writes the wait"
run tk-sub --disposition blocked --reason "r" --takeaway "t" \
    --blocker "$(printf 'x%.0s' $(seq 1 501))" --run "$ROOT"
eq "$RC" "2" "(BLKNEW) a blocker title past bd's 500-byte cap is refused here"
has "cap is 500" "$ERR" "(BLKNEW) …by its actual cause, not 'no id returned'"

# The release the store refuses stops the exit after the blocker is filed. The
# re-run keeps the log and the state the first run left, as a re-offered
# reaction meets them.
export FAKE_NEW_ID=tk-blocker-first FAKE_HELM_FAILS=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --blocker "Migrate the seed schema" --run "$ROOT"
eq "$RC" "4" "(BLKRETRY) an exit whose release fails after the blocker is filed stops"
unset FAKE_HELM_FAILS; export FAKE_NEW_ID=tk-blocker-second
run_now tk-sub --disposition blocked --reason "r" --takeaway "t" --blocker "Migrate the seed schema" --run "$ROOT"
eq "$RC" "0" "(BLKRETRY) …and the same exit run again succeeds"
eq "$(grep -c '^CREATE' "$FAKE_LOG")" "1" "(BLKRETRY) …filing the blocker once across both runs"
has "--waiting-on tk-blocker-first" "$(grep '^HELM takeaway' "$FAKE_LOG" | tail -n 1)" "(BLKRETRY) …the re-run waiting on the blocker the first run filed"
has "already tk-sub's pending wait tk-blocker-first" "$ERR" "(BLKRETRY) …and saying so"
hasnt "tk-blocker-second" "$LOG" "(BLKRETRY) …with no second blocker anywhere"

export FAKE_NEW_ID=tk-blocker-lost FAKE_CREATE_LOST=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --blocker "Migrate the seed schema" --run "$ROOT"
eq "$RC" "4" "(BLKLOST) a create that named no bead stops the exit"
has "either both landed or neither did" "$ERR" "(BLKLOST) …saying the bead and the wait land together"
hasnt "HELM takeaway" "$LOG" "(BLKLOST) …before the release"
unset FAKE_CREATE_LOST
run_now tk-sub --disposition blocked --reason "r" --takeaway "t" --blocker "Migrate the seed schema" --run "$ROOT"
eq "$RC" "0" "(BLKLOST) …and the same exit run again succeeds"
eq "$(grep -c '^CREATE' "$FAKE_LOG")" "1" "(BLKLOST) …waiting on the blocker that landed rather than filing another"
has "--waiting-on tk-blocker-lost" "$(grep '^HELM takeaway' "$FAKE_LOG" | tail -n 1)" "(BLKLOST) …which the release names"
unset FAKE_NEW_ID

export FAKE_HOLDS_JSON='{"id":"tk-sub","status":"blocked","waits":[{"id":"tk-already","type":"blocks","title":"Migrate the seed schema","status":"open","issue_type":"task"}],"pending":[{"id":"tk-already","type":"blocks","title":"Migrate the seed schema","status":"open","issue_type":"task"}],"foreign":[]}'
export FAKE_DEPS_JSON='[{"id":"tk-already"}]'
run tk-sub --disposition blocked --reason "same cause as the run before" \
    --takeaway "held: same migration" --blocker "Migrate the seed schema" --run "$ROOT"
eq "$RC" "0" "(BLKREUSE) a blocker the subject already waits on succeeds"
hasnt "CREATE" "$LOG" "(BLKREUSE) …and files no second bead"
has "--waiting-on tk-already" "$LOG" "(BLKREUSE) …it waits on the one already filed"
has "already tk-sub's pending wait tk-already" "$ERR" "(BLKREUSE) …and says so"
run tk-sub --disposition blocked --reason "r" --takeaway "t" --blocker "Migrate the seed data" --run "$ROOT"
has "CREATE bd create -t task --title Migrate the seed data" "$LOG" "(BLKREUSE) a pending wait under another title is not this blocker"
export FAKE_HOLDS_JSON='{"id":"tk-sub","status":"unjudged","waits":[],"pending":[{"id":"tk-g9","type":"waits-for","title":"Migrate the seed schema","status":"open","issue_type":"gate"}],"foreign":[]}'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --blocker "Migrate the seed schema" --run "$ROOT"
has "CREATE bd create -t task --title Migrate the seed schema" "$LOG" "(BLKREUSE) …and neither is a wait of another edge type"
unset FAKE_HOLDS_JSON FAKE_NEW_ID

# takeaway exits non-zero when the store refuses a wait edge, which FAKE_HELM_FAILS
# models, and the exit stops there: the bead is recorded as waiting and nothing
# holds it, so nothing is armed or handed over on it.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]' FAKE_HELM_FAILS=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(BLKEDGE) a wait edge takeaway could not write fails the exit"
hasnt "GCTK bead arm" "$LOG" "(BLKEDGE) …nothing is armed on a wait that does not exist"
hasnt "disposed as blocked" "$OUT" "(BLKEDGE) …and the run does not report a disposition"
unset FAKE_HELM_FAILS

# A first-reaction subject can carry the pour stamp gc.execution_routed_to. The
# blocked exit releases it (gc-helm.sh --release retires that stamp as
# provenance) and arms a PLAIN deferred dispatch. gctk bead arm keys on
# gc.routed_to, not the execution stamp, and the subject carries no gc.routed_to,
# so the arm lands whether or not the release cleared the stamp.
export FAKE_EXEC_ROUTED_FILE="$TMP/exec_routed"
printf 'gc-toolkit/gc-toolkit.proactive' > "$FAKE_EXEC_ROUTED_FILE"
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.proactive"}}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
has "GCTK bead arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" \
    "(BLKARM) --then-route arms the dispatch for when the wait lifts"
hasnt "--sling-arg" "$LOG" \
    "(BLKARM) …a plain arm, no --on — the order's start slings it even with the pour stamp set"
has "armed the dispatch to gc-toolkit/gc-toolkit.polecat" "$ERR" \
    "(BLKARM) …and the arm lands"
before '^HELM takeaway' '^GCTK bead arm' "(BLKARM) …after the release writes the wait, as the exit's last write"

# Control: a pour stamp still set after a release that exits 0 still lets the
# plain arm land. gc-helm.sh takeaway --release clears the stamp in the update
# whose exit it takes, so a stamp set after a zero exit was written after the
# release landed. No arm or start guard reads that stamp, so dispose runs on to
# arm the plain dispatch.
printf 'gc-toolkit/gc-toolkit.proactive' > "$FAKE_EXEC_ROUTED_FILE"
export FAKE_HELM_KEEPS_STAMP=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(BLKARM) a surviving pour stamp does not fail the disposition"
has "armed the dispatch to gc-toolkit/gc-toolkit.polecat" "$ERR" \
    "(BLKARM) a stamp left set does NOT refuse the plain arm — provenance, not a live queue"
unset FAKE_HELM_KEEPS_STAMP

# Contract: the arm is downstream of a release that SUCCEEDED. A release failure,
# gc-helm exiting non-zero because the store refused its update, dies before the
# arm, so a bead whose disposition did not land is never armed to auto-resume
# from that state.
export FAKE_HELM_FAILS=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(BLKARM) a genuine gc-helm release failure fails the disposition"
hasnt "GCTK bead arm" "$LOG" "(BLKARM) …and nothing is armed after a release that did not land"
unset FAKE_HELM_FAILS FAKE_EXEC_ROUTED_FILE FAKE_SHOW_JSON

# (BLKARMFAIL) A bead held with no arm waits on its edge with nothing to route
# it once the wait lifts. So an arm that does not land fails the exit, as a
# missing edge does.
FAKE_ARM_FAILS=1 run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(BLKARMFAIL) an arm that did not land fails the exit"
has "GCTK bead arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" "(BLKARMFAIL) …after the arm was tried"
has "nothing would route tk-sub once the wait lifts" "$ERR" "(BLKARMFAIL) …and the failure says what it costs"
has "dispatched already (fake refusal)" "$ERR" "(BLKARMFAIL) …carrying the cause the arm named"
has "a re-run resumes" "$ERR" "(BLKARMFAIL) …and that a re-run resumes"
hasnt "disposed as blocked" "$OUT" "(BLKARMFAIL) …and the run does not report a disposition"

# The re-offered step re-runs the same call once the cause is cleared. The
# failed run left the headline and the wait on the subject, which is no
# refusal, so the re-run releases again, harmlessly, and arms.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{"gc.takeaway":"t","gc.takeaway_by":"proactive"}}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(BLKARMFAIL) the re-run after a failed arm succeeds"
has "armed the dispatch to gc-toolkit/gc-toolkit.polecat" "$ERR" "(BLKARMFAIL) …the arm lands"
unset FAKE_SHOW_JSON

# (BLKARMTOOL) The blocked exit reads what holds its subject through gctk, and
# arms through it, so with no gctk binary it is refused before the first write,
# whether or not it would arm.
for then_args in "--then-route gc-toolkit/gc-toolkit.polecat" ""; do
  # shellcheck disable=SC2086  # 0 or 2 flag words
  GCTK_BIN="$TMP/no-such-gctk" \
      run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 $then_args --run "$ROOT"
  eq "$RC" "4" "(BLKARMTOOL) a blocked exit${then_args:+ with --then-route} and no gctk binary is refused"
  has "no-such-gctk" "$ERR" "(BLKARMTOOL) …naming the binary it looked for"
  eq "$LOG" "" "(BLKARMTOOL) …before anything is read or written"
done
unset FAKE_DEPS_JSON

# (BLKROUTE) --then-route is held to the SAME roster test as --route: a target no
# pool runs is refused before anything is written, not silently armed to fail
# every pass of the order. Its parse check only tests for a "/", which a copied
# `<rig>/<rig>.polecat` placeholder passes, so the roster probe is what catches it.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
export FAKE_POOL_DEAD=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.nosuchpool --run "$ROOT"
eq "$RC" "2" "(BLKROUTE) --then-route to a pool nothing runs is refused"
has "PROACTIVE deliverable gc-toolkit/gc-toolkit.nosuchpool tk-sub" "$LOG" \
    "(BLKROUTE) …the exit asks whether that pool can claim before arming"
eq "$(writes)" "" "(BLKROUTE) …and nothing is written or armed"
unset FAKE_POOL_DEAD FAKE_DEPS_JSON

# (BLKASSIGN) a town-repo edit that must wait on a rig change is held on that
# change, and handed to mechanik after the release. A routed bead reaches its
# agent's hook only once bd reports it ready, so the edge is the gate and no
# sling is armed: a deferred dispatch slings a pool, and a named agent is not
# one. The hand-off goes now, while the bead waits (BLKHANDOFF): Gas City nudges
# the agent's route when the blocker closes. A blocker that closed already
# (BLKREADY) leaves no close to nudge the agent, so the exit nudges it.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]' FAKE_WAITS=1
run tk-sub --disposition blocked --reason "the comment can change only once the order lands" \
    --takeaway "held: city.toml comment waits on the order" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik \
    --run "$ROOT"
eq "$RC" "0" "(BLKASSIGN) a blocked disposition handed to a named agent succeeds"
has "disposed as blocked (tk-blk1)" "$OUT" "(BLKASSIGN) the run still names the wait"
has "--release --waiting-on tk-blk1" "$LOG" "(BLKASSIGN) the wait rides the release"
hasnt "--assign" "$(grep '^HELM' "$FAKE_LOG")" "(BLKASSIGN) …which writes no assignee"
hasnt "--no-wait" "$LOG" "(BLKASSIGN) …and the named wait is not called settled"
hasnt "GCTK bead arm" "$LOG" "(BLKASSIGN) …and nothing is armed for a named agent"
has "PROACTIVE assignable gc-toolkit.mechanik tk-sub" "$LOG" "(BLKASSIGN) the exit asks whether the agent's hook would offer the bead"
has "gc-toolkit.mechanik tk-sub --no-formula --no-convoy" "$(grep '^SLING ' "$FAKE_LOG")" \
    "(BLKHANDOFF) gc sling hands the waiting bead to the agent's own name"
before '^HELM takeaway' '^SLING ' "(BLKHANDOFF) …after the release writes the wait"
before '^SLING ' '^READY ' "(BLKHANDOFF) …then reads whether bd reports the bead ready"
hasnt "NUDGE" "$LOG" "(BLKHANDOFF) …and sends no nudge while the bead still waits"
unset FAKE_WAITS

run tk-sub --disposition blocked --reason "the comment waited on an order that has landed" \
    --takeaway "held: city.toml comment waits on the order" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik \
    --run "$ROOT"
eq "$RC" "0" "(BLKREADY) a blocked disposition to the mechanik whose blocker has closed already succeeds"
has "--release --waiting-on tk-blk1" "$LOG" "(BLKREADY) …writing the wait as before"
has "gc-toolkit.mechanik tk-sub --no-formula --no-convoy" "$(grep '^SLING ' "$FAKE_LOG")" "(BLKREADY) …and routing the bead to the agent"
has "NUDGE session nudge gc-toolkit.mechanik tk-sub is routed to you and ready" "$LOG" \
    "(BLKREADY) the mechanik is nudged, since bd reports the bead ready and no blocker close is left to nudge it"
before '^SLING ' '^READY ' "(BLKREADY) …once the bead is routed to it"
before '^READY ' '^NUDGE ' "(BLKREADY) …and bd's ready set holds it"

export FAKE_NUDGE_FAILS=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik --run "$ROOT"
eq "$RC" "4" "(HANDOFFFAIL) a --then-assign whose nudge did not reach the agent fails the exit"
has "the blocked disposition on tk-sub did not land. It is routed to gc-toolkit.mechanik, but gc session nudge did not reach the agent" "$ERR" \
    "(HANDOFFFAIL) …naming the exit and saying the route stands"
unset FAKE_NUDGE_FAILS

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --then-assign gc-toolkit.mechanik
eq "$RC" "2" "(BLKASSIGN) --then-route beside --then-assign is refused"
eq "$LOG" "" "(BLKASSIGN) …and nothing was written"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --assign gc-toolkit.mechanik
eq "$RC" "2" "(BLKASSIGN) blocked refuses --assign, the actionable exit's flag"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik --dry-run
eq "$RC" "0" "(BLKASSIGN) a dry run of the --then-assign exit succeeds"
has "would wait tk-sub on: tk-blk1" "$OUT" "(BLKASSIGN) …and names the wait"
has "would hand tk-sub to named agent gc-toolkit.mechanik (gc sling gc-toolkit.mechanik tk-sub --no-formula --no-convoy) and nudge it if bd reports the bead ready; while the wait holds, Gas City nudges it when the blocker closes" "$OUT" \
    "(BLKASSIGN) …and the agent the held bead goes to"
eq "$(writes)" "" "(BLKASSIGN) …writing and handing over nothing"

export FAKE_SLING_FAILS=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik --run "$ROOT"
eq "$RC" "4" "(HANDOFFFAIL) a --then-assign whose hand-off did not land fails the exit"
has "gc sling did not hand it to gc-toolkit.mechanik" "$ERR" "(HANDOFFFAIL) …saying the agent's hook does not offer it"
unset FAKE_SLING_FAILS

export FAKE_AGENT_GONE=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit/gc-toolkit.refinery
eq "$RC" "2" "(BLKASSIGN) a --then-assign agent that cannot be handed the bead is refused"
has "PROACTIVE assignable gc-toolkit/gc-toolkit.refinery tk-sub" "$LOG" "(BLKASSIGN) …on the agent's own answer"
hasnt "HELM" "$LOG" "(BLKASSIGN) …and the bead is not released"
unset FAKE_AGENT_GONE FAKE_DEPS_JSON

# ── ruling: the human gate is the wait, filed by the exit itself ─────────────
#   (RUL)      the exit files the gate through human-gate.sh, the takeaway as
#              its title, and holds the subject on it
#   (RULKEY)   the gate is filed under the key first-reaction, with no quiet
#              window
#   (RULRUN)   the gate's message names the run that filed it, and a call by
#              hand names none
#   (RULORDER) the gate, then the release
#   (RULGATE)  a gate that did not file fails the exit before the release
#   (RULRULE)  which open gates still ask is bd-lib.sh's one rule
#   (RULREAD)  a gate read that does not answer stops the exit
#   (RULKIDS)  a subject with open children is gated like any other bead
#   (RULCAP)   a takeaway over the 140-character cap is refused first
# The exit files no visit. The FAKE dep list answers with the gate so the hold
# verification passes.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --run "$ROOT"
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
GATE_MSG="$(sed -n '/^GATE --subject/,/^HELM takeaway/p' "$FAKE_LOG")"
has "the trade-off is the operator's" "$GATE_MSG" "(RUL) …with the reason in the gate's message"
has "Filed by a first reaction on tk-sub (ruling, run $ROOT), which waits on it." "$GATE_MSG" \
   "(RULRUN) …and the run that filed it"
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
before '^GATE --subject' '^HELM takeaway' "(RULORDER) the gate is filed before the release"

run tk-sub --disposition ruling --reason "the trade-off is the operator's" --takeaway "needs a ruling: which default"
GATE_MSG="$(sed -n '/^GATE --subject/,/^HELM takeaway/p' "$FAKE_LOG")"
has "Filed by a first reaction on tk-sub (ruling), which waits on it." "$GATE_MSG" \
   "(RULRUN) a ruling by hand names no run"

export FAKE_GATE_FAILS=1
run tk-sub --disposition ruling --reason "r" --takeaway "t" --run "$ROOT"
eq "$RC" "4" "(RULGATE) a gate that did not file fails the exit"
hasnt "HELM takeaway" "$LOG" "(RULGATE) …and the subject is not released onto a gate that does not exist"
has "re-run this command" "$ERR" "(RULGATE) …and the failure names the retry"
unset FAKE_GATE_FAILS

# Which gates still ask is bd-lib.sh's one rule: a human gate under this key, in
# any status but closed, whatever its case. Each gate below carries another
# reaction's question, so only a gate the rule reads as open is withdrawn.
# fr_gate <status> [await-id] [issue-type] -> a store whose gate is a superseded reaction's.
fr_gate() {
  jq -cn --arg s "$1" --arg k "${2:-first-reaction}" --arg i "${3:-gate}" \
    '[{id: "tk-gate0", issue_type: $i, await_type: "human", await_id: $k, status: $s, title: "an older reaction asked this", description: "an older reaction asked this"}, {id: "tk-gate1"}]'
}
for GST in open pinned in_progress; do
  FAKE_DEPS_JSON="$(fr_gate "$GST")"; export FAKE_DEPS_JSON
  run tk-sub --disposition ruling --reason "r" --takeaway "needs a ruling: which default" --run "$ROOT"
  has "GATE --retract --subject tk-sub --key first-reaction" "$LOG" "(RULRULE) a superseded gate at status $GST still asks, so it is withdrawn"
  before '^GATE --retract' '^GATE --subject tk-sub --key first-reaction --message' "(RULRULE) …before the exit files its own"
done
for GST in closed CLOSED Closed; do
  FAKE_DEPS_JSON="$(fr_gate "$GST")"; export FAKE_DEPS_JSON
  run tk-sub --disposition ruling --reason "r" --takeaway "needs a ruling: which default" --run "$ROOT"
  eq "$RC" "0" "(RULRULE) a ruling beside a gate at status $GST succeeds"
  hasnt "--retract" "$LOG" "(RULRULE) …and withdraws nothing: that gate asks nothing"
done
FAKE_DEPS_JSON="$(fr_gate open another-key)"; export FAKE_DEPS_JSON
run tk-sub --disposition ruling --reason "r" --takeaway "needs a ruling: which default" --run "$ROOT"
hasnt "--retract" "$LOG" "(RULRULE) an open gate under another key is not this reaction's to withdraw"
FAKE_DEPS_JSON="$(fr_gate open first-reaction task)"; export FAKE_DEPS_JSON
run tk-sub --disposition ruling --reason "r" --takeaway "needs a ruling: which default" --run "$ROOT"
hasnt "--retract" "$LOG" "(RULRULE) a bead that is not a gate is not a question to withdraw"
# A read that fails cannot say whether a gate already asks, and neither can a
# store's answer that is not an array.
export FAKE_DEP_LIST_FAILS=1
run tk-sub --disposition ruling --reason "r" --takeaway "needs a ruling: which default" --run "$ROOT"
eq "$RC" "4" "(RULREAD) a gate read the store refuses stops the exit"
has "could not read the human gates of tk-sub" "$ERR" "(RULREAD) …saying so"
hasnt "GATE " "$LOG" "(RULREAD) …and neither withdraws nor files a gate"
unset FAKE_DEP_LIST_FAILS
export FAKE_DEPS_JSON='{"error":"no issue found"}'
run tk-sub --disposition ruling --reason "r" --takeaway "needs a ruling: which default" --run "$ROOT"
eq "$RC" "4" "(RULREAD) a gate read that answers with something other than an array stops the exit"
hasnt "GATE " "$LOG" "(RULREAD) …and neither withdraws nor files a gate"
GC_BD_LIB="$TMP/no-such-bd-lib.sh" run tk-sub --disposition ruling --reason "r" --takeaway "t" --run "$ROOT"
eq "$RC" "4" "(RULREAD) a script that cannot source bd-lib.sh stops as a runtime failure"
has "cannot source bd-lib.sh" "$ERR" "(RULREAD) …naming the file"
hasnt "GATE " "$LOG" "(RULREAD) …before it files anything"
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{}},{"id":"tk-sub.1","parent":"tk-sub","status":"open"}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --run "$ROOT"
eq "$RC" "0" "(RULKIDS) a subject with open children takes the ruling exit"
has "GATE --subject tk-sub --key first-reaction" "$LOG" "(RULKIDS) …and its gate blocks the parent itself"
hasnt "--parent" "$LOG" "(RULKIDS) …with no read of its children: what a gate on a parent pauses is the call site's policy"
unset FAKE_SHOW_JSON
LONG_TAKEAWAY="$(printf 'needs a ruling%.0s ' $(seq 1 12))"
run tk-sub --disposition ruling --reason "r" --takeaway "$LONG_TAKEAWAY" --run "$ROOT"
eq "$RC" "2" "(RULCAP) a takeaway over 140 characters is refused"
eq "$LOG" "" "(RULCAP) …before anything is written, since it is the gate's title"

: > "$FAKE_LOG"; RC=0
OUT="$("$SCRIPT" tk-sub --disposition ruling --reason "r" --takeaway "t" --run "$ROOT" --dry-run 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(RULDRY) a dry run succeeds"
has "would file a human gate on tk-sub" "$OUT" "(RULDRY) …saying it would file the gate"
eq "$(writes)" "" "(RULDRY) …and files and writes nothing"

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
    --recommended-formula mol-x --run "$ROOT"
eq "$RC" "0" "(RECO) a recommend disposition succeeds"
has "gc.recommended_formula=mol-x" "$LOG" "(RECO) the recommended formula is stamped on the subject"
has "GATE --subject tk-sub --key first-reaction --message recommend: retire PR + supersede anchor; execute via mol-x — Accept or Discuss" "$LOG" \
   "(RECO) …it files the human gate, as ruling does"
GATE_MSG="$(sed -n '/^GATE --subject/,/^UPDATE/p' "$FAKE_LOG")"
has "It recommends mol-x, the formula Accept runs on tk-sub." "$GATE_MSG" "(RECO) …whose message names the recommended formula"
has "(recommend, run $ROOT)" "$GATE_MSG" "(RECO) …and the run that filed it"
has "--waiting-on tk-gate1" "$LOG" "(RECO) …and the gate holds the subject, the ruling shape"
before '^GATE --subject' 'gc.recommended_formula=mol-x' "(RECO) …the recommendation lands only once the gate is filed"
before '^GATE --subject' '^HELM takeaway' "(RECO) …and the gate before the release"

# recommend REQUIRES the flag it exists to carry: no --recommended-formula is a
# usage error naming ruling as the flagless alternative.
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via <mol> — Accept or Discuss" --run "$ROOT"
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
    --recommended-formula mol-typo --run "$ROOT"
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
    --takeaway "needs a ruling: which default" --recommended-formula mol-x --run "$ROOT"
eq "$RC" "2" "(RECO) ruling refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
has "use --disposition recommend" "$ERR" "(RECO) …pointing at the disposition that carries a recommendation"

# A plain ruling stamps nothing, so the gate stays Discuss-only (no Accept).
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --run "$ROOT"
eq "$RC" "0" "(RECO) a Discuss-only ruling succeeds"
hasnt "gc.recommended_formula" "$LOG" "(RECO) …and stamps no recommendation, so the gate offers no Accept"

# A subject can already carry a recommendation a prior recommend stamped: the
# stamp landed and the exit was cut off before its release, and this retry
# resumes it. A ruling retry names no recommendation and clears that stale stamp
# before the act, so the gate never offers Accept for an action the current
# disposition did not recommend.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{"gc.recommended_formula":"mol-old"}}]'
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --run "$ROOT"
eq "$RC" "0" "(RECO) a ruling retry over a stale recommendation succeeds"
has "--unset-metadata gc.recommended_formula" "$LOG" "(RECO) …and clears the stale recommendation the prior recommend left"
hasnt "gc.recommended_formula=" "$LOG" "(RECO) …stamping no new one, so the subject states the current disposition"

# The same stale stamp retried as a recommend with a different formula clears the
# stale one before the gate is filed and stamps the new one after it, so no
# recommendation is older than the newest first-reaction gate, and an exit that
# stops part way never leaves its gate beside the older recommendation.
run tk-sub --disposition recommend --reason "the newer mol is the right execution" \
    --takeaway "recommend: execute via mol-new — Accept or Discuss" \
    --recommended-formula mol-new --run "$ROOT"
eq "$RC" "0" "(RECO) a retry that re-recommends succeeds"
has "gc.recommended_formula=mol-new" "$LOG" "(RECO) …and the subject carries the new recommendation"
has "--unset-metadata gc.recommended_formula" "$LOG" "(RECOORDER) …clearing the older recommendation first"
before '--unset-metadata gc.recommended_formula' '^GATE --subject' "(RECOORDER) …before the gate is filed"
before '^GATE --subject' 'gc.recommended_formula=mol-new' "(RECOORDER) …and stamping the new one after it"
unset FAKE_SHOW_JSON

# ── The recommendation must land before the act ───────────────────────────────
# gc.recommended_formula is presence-sensitive downstream, so a write the store
# refuses is a wrong operator affordance, not a cosmetic miss. The act after it
# cannot be undone, so the exit refuses before the act, and the command re-runs.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'

# A set the store refuses: the release is withheld over a gate that offers only
# Discuss. The gate is filed before the set, and a re-run finds it and sets the
# recommendation again.
export FAKE_UPDATE_REFUSE='gc.recommended_formula'
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" \
    --recommended-formula mol-x --run "$ROOT"
eq "$RC" "4" "(RECOGUARD) a recommendation set the store refuses refuses the exit"
hasnt "HELM takeaway" "$LOG" "(RECOGUARD) …the release is withheld"
has "the store refused gc.recommended_formula=mol-x" "$ERR" "(RECOGUARD) …and the refusal names the key"
has "The gate tk-gate1 is filed" "$ERR" "(RECOGUARD) …saying the gate is already filed"
unset FAKE_UPDATE_REFUSE

# A stale-clear the store refuses: the act is withheld, so a Discuss-only retry
# never leaves a superseded Accept executable.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{"gc.recommended_formula":"mol-old"}}]'
export FAKE_UPDATE_REFUSE='gc.recommended_formula'
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --run "$ROOT"
eq "$RC" "4" "(RECOGUARD) a stale-clear the store refuses refuses the exit"
hasnt "HELM" "$LOG" "(RECOGUARD) …the act is withheld, so the superseded Accept is never left executable"
hasnt "GATE " "$LOG" "(RECOGUARD) …and no gate is filed beside the older recommendation"
has "the store refused the clear of the earlier recommendation" "$ERR" "(RECOGUARD) …and the refusal names the stale key"
unset FAKE_UPDATE_REFUSE FAKE_SHOW_JSON

# --recommended-formula belongs to the recommend exit only: actionable, blocked,
# and close route, hold, or hand the bead to a closer, and none files a gate the
# operator Accepts — so each refuses the flag (ruling's refusal is tested above).
run tk-sub --disposition actionable --reason "r" --takeaway "t" \
    --route gc-toolkit/gc-toolkit.polecat --recommended-formula mol-x --run "$ROOT"
eq "$RC" "2" "(RECO) actionable refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --recommended-formula mol-x --run "$ROOT"
eq "$RC" "2" "(RECO) blocked refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
run tk-sub --disposition close --reason "r" --takeaway "t" \
    --route gc-toolkit/gc-toolkit.polecat --recommended-formula mol-x --run "$ROOT"
eq "$RC" "2" "(RECO) close refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
unset FAKE_DEPS_JSON

# ── The gate exits against a store of human gates ────────────────────────────
# A store that keeps the gates the real human-gate.sh files and resolves, and the
# subject's recommendation, runs a gate exit twice, as a re-offered reaction or
# a newer one does.
#   (RECO2)     two recommends with one headline and two formulas leave one
#               open gate, which names the second formula, and the subject's
#               gc.recommended_formula names it too
#   (RECOAGAIN) the same recommend run again keeps its gate: it files and
#               withdraws nothing
#   (RULTITLE)  a gate whose title the real helper cut to fit bd is kept by a
#               re-run, and a takeaway that spans lines is the gate's one-line
#               title, kept the same way
#   (RECOCHECK) the real check passes over the gate the exit filed for its own
#               run, and refuses it for another run
GS="$TMP/gs"; mkdir -p "$TMP/gs-bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/gs-bin/gc" <<'GSTORE'
printf 'GS %s\n' "$*" >> "$FAKE_LOG"
gates() { cat "$GS/gates.json" 2>/dev/null || printf '[]'; }
put()   { cat > "$GS/gates.tmp" && mv "$GS/gates.tmp" "$GS/gates.json"; }
case "$1 ${2:-}" in
  "rig list") printf '{"rigs":[]}\n' ;;
  "bd show")
    if [ "$3" = tk-sub ]; then
      jq -cn --arg r "$(cat "$GS/reco" 2>/dev/null)" \
        '[{id: "tk-sub", status: "open", parent: "tk-epic", metadata: (if $r == "" then {} else {"gc.recommended_formula": $r} end)}]'
    else
      gates | jq -c --arg id "$3" '[ .[] | select(.id == $id) ]'
    fi ;;
  "bd update")
    id="$3"; shift 3
    while [ $# -gt 0 ]; do
      case "$id $1" in
        "tk-sub --set-metadata") case "$2" in gc.recommended_formula=*) printf '%s' "${2#gc.recommended_formula=}" > "$GS/reco" ;; esac; shift 2 ;;
        "tk-sub --unset-metadata") [ "$2" = gc.recommended_formula ] && : > "$GS/reco"; shift 2 ;;
        *" --description") gates | jq -c --arg id "$id" --arg d "$2" 'map(if .id == $id then .description = $d else . end)' | put; shift 2 ;;
        *) shift ;;
      esac
    done ;;
  "bd dep")
    [ "${3:-}" = list ] && gates | jq -c --arg s "$4" '[ .[] | select(.blocks == $s) ]' ;;
  "bd gate")
    case "${3:-}" in
      create)
        shift 3; b=""; k=""; t=""; r=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --blocks) b="$2"; shift 2 ;; --await-id) k="$2"; shift 2 ;;
            --title) t="$2"; shift 2 ;; --reason) r="$2"; shift 2 ;; *) shift ;;
          esac
        done
        n=$(( $(cat "$GS/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$GS/n"
        gates | jq -c --arg id "tk-g$n" --arg b "$b" --arg k "$k" --arg t "$t" --arg r "$r" \
          '. + [{id: $id, issue_type: "gate", await_type: "human", await_id: $k, status: "open", title: $t, description: ("Gate head\n\n" + $r), blocks: $b}]' | put
        printf '[{"id":"tk-g%s"}]\n' "$n" ;;
      resolve)
        g="$4"; shift 4; r=""
        while [ $# -gt 0 ]; do case "$1" in --reason) r="$2"; shift 2 ;; *) shift ;; esac; done
        gates | jq -c --arg id "$g" --arg r "$r" 'map(if .id == $id then .status = "closed" | .close_reason = $r else . end)' | put ;;
    esac ;;
esac
exit 0
GSTORE
chmod +x "$TMP/gs-bin/gc"
gs_reset() { rm -rf "$GS"; mkdir -p "$GS"; }
gs_run() {
  : > "$FAKE_LOG"
  RC=0; OUT="$(env -u GC_AGENT GS="$GS" PATH="$TMP/gs-bin:$PATH" GC_HUMAN_GATE_TOOL="$HERE/human-gate.sh" \
    "$SCRIPT" "$@" 2>"$TMP/err")" || RC=$?
  ERR="$(cat "$TMP/err")"; LOG="$(cat "$FAKE_LOG")"
}
open_fr_gates() { jq -c '[ .[] | select(.await_id == "first-reaction" and .status != "closed") ]' "$GS/gates.json"; }

RECO_HEAD="recommend: fix the flaky suite; execute via a fix formula — discuss if the cause is upstream"
gs_reset
gs_run tk-sub --run tk-root-a --disposition recommend --reason "the suite's own fixture is the cause" \
    --takeaway "$RECO_HEAD" --recommended-formula mol-fix-a
eq "$RC" "0" "(RECO2) the first recommend succeeds"
gs_run tk-sub --run tk-root-b --disposition recommend --reason "the cause is the order of the suite's cases" \
    --takeaway "$RECO_HEAD" --recommended-formula mol-fix-b
eq "$RC" "0" "(RECO2) a second recommend with the same headline and another formula succeeds"
eq "$(open_fr_gates | jq 'length')" "1" "(RECO2) one first-reaction gate stays open"
has "mol-fix-b" "$(open_fr_gates | jq -r '.[0].description')" "(RECO2) …and its brief names the second formula"
hasnt "mol-fix-a" "$(open_fr_gates | jq -r '.[0].description')" "(RECO2) …and not the first"
has "the cause is the order of the suite's cases" "$(open_fr_gates | jq -r '.[0].description')" "(RECO2) …with the second reason"
eq "$(cat "$GS/reco")" "mol-fix-b" "(RECO2) gc.recommended_formula names the second formula too"
has "moot: superseded by a newer first reaction on tk-sub" "$(jq -r '.[] | select(.id == "tk-g1") | .close_reason' "$GS/gates.json")" \
    "(RECO2) the first gate was withdrawn as superseded"
before 'GS bd gate resolve tk-g1' 'GS bd gate create' "(RECO2) …before the second was filed"
GATE_B="$(open_fr_gates | jq -r '.[0].id')"

gs_run tk-sub --run tk-root-b --disposition recommend --reason "the cause is the order of the suite's cases" \
    --takeaway "$RECO_HEAD" --recommended-formula mol-fix-b
eq "$RC" "0" "(RECOAGAIN) the same recommend run again succeeds"
hasnt "GS bd gate create" "$LOG" "(RECOAGAIN) …filing no second gate"
hasnt "GS bd gate resolve" "$LOG" "(RECOAGAIN) …and withdrawing none"
has "disposed as recommend ($GATE_B)" "$OUT" "(RECOAGAIN) …onto the gate it filed before"
eq "$(cat "$GS/reco")" "mol-fix-b" "(RECOAGAIN) …and the recommendation stands"

# The real check, over the store as the exit left it: the subject, its open
# gate, and what holds it.
gs_fixture() {
  jq -c --arg g "$1" '(map({key: .id, value: (del(.blocks))}) | from_entries) + {"tk-sub": {issue_type: "task", status: "open", metadata: {}}}' \
    "$GS/gates.json" > "$FX/beads.json"
  jq -cn --arg g "$1" --arg t "$(jq -r --arg g "$1" '.[] | select(.id == $g) | .title' "$GS/gates.json")" \
    '{"tk-sub": {id: "tk-sub", status: "blocked", waits: [{id: $g, type: "blocks", title: $t, status: "open", issue_type: "gate", await_type: "human"}], pending: [], foreign: []}}' \
    > "$FX/holds.json"
}
gs_fixture "$GATE_B"
check tk-root-b
eq "$RC" "0" "(RECOCHECK) the check passes over the gate the exit filed for its own run"
check tk-root-a
eq "$RC" "5" "(RECOCHECK) …and refuses it for another run"
has "open human gate $GATE_B" "$OUT" "(RECOCHECK) …naming the gate"
gs_reset
gs_run tk-sub --disposition ruling --reason "a fork only the operator decides" --takeaway "needs a ruling: which default"
gs_fixture "$(open_fr_gates | jq -r '.[0].id')"
check tk-root-b
eq "$RC" "5" "(RECOCHECK) a gate filed by hand names no run, so no reaction's check passes over it"
rm -f "$FX/holds.json"

# 134 CJK characters are 402 bytes. The real helper files them under a title
# cut below 400 bytes, and the description it writes holds the message whole,
# so a re-run of the same exit through the real helper keeps that gate.
CJK=$(printf '問%.0s' $(seq 1 134))
gs_reset
gs_run tk-sub --run "$ROOT" --disposition ruling --reason "r" --takeaway "$CJK"
eq "$RC" "0" "(RULTITLE) a ruling with a takeaway past 400 bytes succeeds through the real helper"
CJK_TITLE="$(open_fr_gates | jq -r '.[0].title')"
[ -n "$CJK_TITLE" ] && [ "$CJK_TITLE" != "$CJK" ] \
  && ok "(RULTITLE) the real helper titles a 402-byte takeaway with a shorter line" \
  || bad "(RULTITLE) the real helper's title for a 402-byte takeaway is '$CJK_TITLE', so the next case tests no cut"
gs_run tk-sub --run "$ROOT" --disposition ruling --reason "r" --takeaway "$CJK"
eq "$RC" "0" "(RULTITLE) a re-run with that takeaway succeeds"
hasnt "GS bd gate resolve" "$LOG" "(RULTITLE) …withdrawing nothing, since the gate's whole brief is this exit's"
hasnt "GS bd gate create" "$LOG" "(RULTITLE) …and filing nothing"
# The helper titles a gate with its message's first line. A takeaway that spans
# lines is stored on the board as one line, and the gate's title has to be that
# same line, or each re-run reads its own gate as a superseded reaction's.
gs_reset
gs_run tk-sub --run "$ROOT" --disposition ruling --reason "r" --takeaway "needs a ruling:
which default"
eq "$(open_fr_gates | jq -r '.[0].title')" "needs a ruling: which default" \
   "(RULTITLE) a takeaway that spans lines is the gate's title on one line, as the board shows it"
gs_run tk-sub --run "$ROOT" --disposition ruling --reason "r" --takeaway "needs a ruling:
which default"
hasnt "GS bd gate resolve" "$LOG" "(RULTITLE) …so a re-run finds the gate it filed and withdraws nothing"

# ── Origin does not decide the exit ──────────────────────────────────────────
# operator-intake stamps gc.origin=operator on a topic a human typed, but the
# script does not force such a bead to the ruling exit: an operator capture is
# triaged on its merits, so every exit is open to it. The guardrail that a fork
# or an irreversible action still goes to a human lives in the reacting agent's
# rubric, not here.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{"gc.origin":"operator"}}]'
export FAKE_DEPS_JSON='[{"id":"tk-blk1"},{"id":"tk-gate1"}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(ORIGIN) an operator-origin subject may take the actionable exit"
has "HELM takeaway tk-sub" "$LOG" "(ORIGIN) …and is routed like any other bead"
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --run "$ROOT"
eq "$RC" "0" "(ORIGIN) …the blocked exit too"
run tk-sub --disposition ruling --reason "r" --takeaway "t" --run "$ROOT"
eq "$RC" "0" "(ORIGIN) …and the ruling exit, when the agent chooses it"
unset FAKE_SHOW_JSON FAKE_DEPS_JSON

# ── close: hand the bead to a validating closer, never close here ────────────
# The reaction concluded there is nothing to do. It does not close the bead — a
# cheap model must not have the last word — it hands the bead to a capable pool
# carrying mol-validate-close, which re-checks the call and closes or escalates.
# GC_RIG is set on every run: the proactive pool is rig-scoped, and it is what
# both defaults the pool target and pins the sling with --rig.
#   (CLOSE)        the closer is slung, after the close brief and the headline
#   (CLOSEBRIEF)   the brief is the reason, on the subject before any dispatch
#   (CLOSEHEAD)    the headline is written before the closer is dispatched, and
#                  a headline that does not land dispatches nothing
#   (CLOSEREOFFER) a live closer already on the subject is its closer, so the
#                  exit lands with no second
#   (CLOSEWAIT)    a close that waits holds the subject on each bead and arms
#                  the closer for when they close. A wait the subject's store
#                  does not hold, or a subject with a wait edge into another
#                  store, is refused before anything is written, and a read
#                  that does not answer for a wait writes nothing
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "already fixed, nothing to merge" --takeaway "close: fixed in #123" --run "$ROOT"
eq "$RC" "0" "(CLOSE) the close exit succeeds"
has "SLING sling --rig gc-toolkit gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close" "$LOG" \
   "(CLOSE) it slings the closer formula to \$GC_RIG/gc-toolkit.polecat, rig-pinned"
has "HELM takeaway tk-sub close: fixed in #123 --by proactive" "$LOG" "(CLOSE) …sets the board headline"
has "UPDATE bd update tk-sub --append-notes ## Close brief (first reaction" "$LOG" "(CLOSEBRIEF) the close brief is appended to the subject's notes"
has "already fixed, nothing to merge" "$(sed -n '/--append-notes ## Close brief/,/^HELM/p' "$FAKE_LOG")" "(CLOSEBRIEF) …carrying the reaction's reason, which the closer validates"
before 'Close brief' '^HELM takeaway' "(CLOSEBRIEF) …before the headline"
before '^HELM takeaway' '^SLING' "(CLOSEHEAD) the headline is written before the closer is slung"
hasnt "--release" "$LOG" "(CLOSE) …and does not release it to a pool as a raw bead"
hasnt "held on" "$LOG" "(CLOSEBRIEF) …and a close that waits on nothing names no hold"
hasnt "CLOSE bd close" "$LOG" "(CLOSE) …and never closes the subject itself"
hasnt "GCTK" "$LOG" "(CLOSE) …with no deferred arm: nothing on the subject has to close first"
has "disposed as close (gc-toolkit/gc-toolkit.polecat)" "$OUT" "(CLOSE) …and the run reports the closer"

# With no GC_RIG, an explicit --route still slings — and pins nothing.
: > "$FAKE_LOG"; RC=0
OUT="$(env -u GC_RIG "$SCRIPT" tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT" 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(CLOSE) with no GC_RIG, an explicit --route still slings"
has "SLING sling gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close" "$LOG" "(CLOSE) …with no --rig pin"

# The closer must be able to claim, or the bead is routed to nobody — same
# roster gate the actionable exit uses, same fallback.
FAKE_POOL_DEAD=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "2" "(CLOSE) a closer pool that cannot claim is refused"
has "Put it to the operator instead" "$ERR" "(CLOSE) …and the refusal names the exits that reach a human"
eq "$(writes)" "" "(CLOSE) …and nothing is written or slung"

# The closer reads the brief from the notes, so a brief that does not land
# dispatches no closer.
FAKE_NOTES_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(CLOSEBRIEF) a close brief that does not land fails the exit"
hasnt "SLING" "$LOG" "(CLOSEBRIEF) …and no closer is slung without its brief"
hasnt "HELM" "$LOG" "(CLOSEBRIEF) …and no headline is written"

FAKE_HELM_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(CLOSEHEAD) a headline that does not land fails the exit"
has "its board headline did not land" "$ERR" "(CLOSEHEAD) …saying so"
hasnt "SLING" "$LOG" "(CLOSEHEAD) …and no closer is dispatched under no headline"

# A failed sling refers to the cause, and the re-offered reaction resumes.
FAKE_SLING_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(CLOSE) a failed sling is a runtime failure"
has "gc sling --on mol-validate-close exited 1: gc sling: fake refusal" "$ERR" "(CLOSE) …naming gc sling's own reason"

# The first run slung the closer, and its worker was cut off before its step
# closed. The re-offered reaction runs the close again, and gc sling refuses a
# second live run of the closer with its exit 3: that closer is the bead's, so
# the exit lands, whoever slung it.
FAKE_SLING_RC=3 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(CLOSEREOFFER) a close whose closer is already live succeeds"
has "a validating closer already drives tk-sub, so no second is slung" "$ERR" "(CLOSEREOFFER) …naming it"
has "tk-closer-root" "$ERR" "(CLOSEREOFFER) …with the run gc sling named"

# ── close --waiting-on: the bead's job ends when another bead lands ──────────
# A problem in code another bead retires is done once the retirement lands, and
# the validating closer checks that it is. So the close exit holds the subject
# on each bead through a blocks edge and arms the closer for when they close.
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "the file it reports on is retired whole by tk-retire" \
    --takeaway "checked once tk-retire retires its code" --waiting-on tk-retire --run "$ROOT"
eq "$RC" "0" "(CLOSEWAIT) a close that waits on the bead retiring its code succeeds"
has "DEP bd dep add tk-sub tk-retire -t blocks" "$LOG" "(CLOSEWAIT) it holds the subject on that bead"
has "--append-notes ## Close brief (first reaction, held on tk-retire, " "$LOG" "(CLOSEWAIT) …with a brief naming the bead it is held on"
before 'Close brief' '^HELM takeaway' "(CLOSEWAIT) …and the brief, then the headline"
before '^HELM takeaway' '^DEP bd dep add' "(CLOSEWAIT) …before the hold"
has "GCTK bead arm tk-sub --target gc-toolkit/gc-toolkit.polecat --on mol-validate-close" "$LOG" \
   "(CLOSEWAIT) …and arms the validating closer for when it closes"
before '^DEP bd dep add' '^GCTK bead arm' "(CLOSEWAIT) …after the hold, so the arm never fires ungated"
hasnt "SLING" "$LOG" "(CLOSEWAIT) …and slings nothing now"
hasnt "CLOSE bd close" "$LOG" "(CLOSEWAIT) …and never closes the subject itself"
has "disposed as close (gc-toolkit/gc-toolkit.polecat once tk-retire closes)" "$OUT" "(CLOSEWAIT) …and the run reports what it waits for"

GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-a --waiting-on tk-b --run "$ROOT"
eq "$RC" "0" "(CLOSEWAIT) a close that waits on two beads succeeds"
has "DEP bd dep add tk-sub tk-a -t blocks" "$LOG" "(CLOSEWAIT) …holding the subject on the first"
has "DEP bd dep add tk-sub tk-b -t blocks" "$LOG" "(CLOSEWAIT) …and on the second"
eq "$(grep -c '^GCTK bead arm' "$FAKE_LOG")" "1" "(CLOSEWAIT) …and arming the closer once"
has "--append-notes ## Close brief (first reaction, held on tk-a,tk-b, " "$LOG" "(CLOSEWAIT) …with a brief that names both"

FAKE_DEP_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-retire --run "$ROOT"
eq "$RC" "4" "(CLOSEWAIT) a hold that did not land fails the exit closed"
has "gc bd dep remove tk-sub tk-retire" "$ERR" "(CLOSEWAIT) …naming the edge of another type that would refuse it"
hasnt "GCTK bead arm" "$LOG" "(CLOSEWAIT) …and the ungated closer is NOT armed"

FAKE_ARM_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-retire --run "$ROOT"
eq "$RC" "4" "(CLOSEWAIT) a failed arm is a runtime failure"
has "the validating closer was not armed" "$ERR" "(CLOSEWAIT) …saying so"

# The read of what holds the subject names each bead the close waits on, and
# the store answers a bead it does not hold with an error line. An edge onto
# that bead would hold nothing, so the close is refused before its first write,
# the close brief, and the remedy is a person's close. Every wait is read
# before that write, so a wait in this store named first is not written either.
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on ra-foreign --run "$ROOT"
eq "$RC" "2" "(CLOSEWAIT) a close that waits on a bead in another store is refused"
has "GCTK bead holds tk-sub ra-foreign" "$LOG" "(CLOSEWAIT) …which the read of what holds the subject names"
eq "$(writes)" "" "(CLOSEWAIT) …before anything is written"
has "the store holds no such bead" "$ERR" "(CLOSEWAIT) …saying the store does not hold it"
has "--disposition ruling" "$ERR" "(CLOSEWAIT) …and a person's close as the remedy"
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-a --waiting-on ra-foreign --run "$ROOT"
eq "$RC" "2" "(CLOSEWAIT) a wait in another store named after one in this store is refused"
eq "$(writes)" "" "(CLOSEWAIT) …holding the subject on neither"
FAKE_HOLDS_MISSING=tk-gone GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-gone --run "$ROOT"
eq "$RC" "2" "(CLOSEWAIT) a wait on a bead this store does not hold is refused the same way"
eq "$(writes)" "" "(CLOSEWAIT) …writing nothing"
FAKE_HOLDS_UNREAD=tk-retire GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-retire --run "$ROOT"
eq "$RC" "4" "(CLOSEWAIT) a wait the read could not answer for stops the close"
has "could not read whether tk-sub's store holds tk-retire" "$ERR" "(CLOSEWAIT) …saying so"
hasnt "is not a bead tk-sub's store holds" "$ERR" "(CLOSEWAIT) …and not that the store does not hold it"
eq "$(writes)" "" "(CLOSEWAIT) …writing nothing"

# A subject that already carries a wait edge into another store holds nothing
# on it, and gctk bead arm refuses to arm it, so the same read refuses it
# before the first write and names the edge.
FAKE_HOLDS_JSON='{"id":"tk-sub","status":"clear","waits":[],"pending":[],"foreign":[{"id":"ra-elsewhere","type":"blocks"}]}' \
    GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-retire --run "$ROOT"
eq "$RC" "4" "(CLOSEWAIT) a subject with a wait edge into another store is refused"
has "carries a wait edge into another store (ra-elsewhere (blocks)), which holds nothing" "$ERR" "(CLOSEWAIT) …naming the edge"
has "gc bd dep remove tk-sub ra-elsewhere" "$ERR" "(CLOSEWAIT) …and its removal"
eq "$(writes)" "" "(CLOSEWAIT) …before anything is written"

# An edge into another store added between the read and the arm is one the arm
# refuses after the exit's writes, so the exit carries the arm's reason and
# names the edge's removal and a person's close.
FAKE_ARM_FAILS=1 FAKE_ARM_WHY="tk-sub has a wait edge onto ra-elsewhere, a bead its store does not hold" \
    GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-retire --run "$ROOT"
eq "$RC" "4" "(CLOSEWAIT) an arm refused for a foreign edge added after the read fails the exit"
has "a bead its store does not hold" "$ERR" "(CLOSEWAIT) …carrying the arm's reason"
has "gc bd dep remove tk-sub <that bead>" "$ERR" "(CLOSEWAIT) …naming the edge's removal"
has "--disposition ruling" "$ERR" "(CLOSEWAIT) …and a person's close as the remedy"

GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-retire --dry-run
eq "$RC" "0" "(CLOSEWAIT) a dry run of a close that waits succeeds"
has "would wait tk-sub on: tk-retire, then arm a deferred dispatch to validating closer gc-toolkit/gc-toolkit.polecat (mol-validate-close)" "$OUT" \
   "(CLOSEWAIT) …and names the wait and the closer"
eq "$(writes)" "" "(CLOSEWAIT) …writing no edge and arming nothing"

GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-sub --run "$ROOT"
eq "$RC" "2" "(CLOSEWAIT) a bead cannot wait on itself"
GCTK_BIN="$TMP/no-such-gctk" GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --waiting-on tk-retire --run "$ROOT"
eq "$RC" "4" "(CLOSEWAIT) with no gctk binary, a close that waits is refused"
eq "$LOG" "" "(CLOSEWAIT) …before anything is written"

# ── The store is pinned to the subject's own rig ─────────────────────────────
# A blocker filed into another store makes the hold a cross-store edge, which
# reports success and holds nothing — and this runs from a worktree where an
# unpinned up-walk finds the wrong ledger.
mkdir -p "$TMP/rig/.beads"
export FAKE_RIG_PATH="$TMP/rig" FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
has "SHOW bd show tk-sub --json --db $TMP/rig/.beads" "$LOG" "(PIN) the subject is read from its own store"
has "GCTK bead holds --db $TMP/rig/.beads tk-sub" "$LOG" "(PIN) …and so is what holds it"
has "GCTK bead arm tk-sub --target gc-toolkit/gc-toolkit.polecat --reason first reaction: r --db $TMP/rig/.beads" \
    "$LOG" "(PIN) …and the deferred dispatch is armed there"
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --run "$ROOT"
has "DEP bd dep list tk-sub --type blocks --json --db $TMP/rig/.beads" "$LOG" \
    "(PIN) …and the subject's human gates are read there"
unset FAKE_RIG_PATH FAKE_DEPS_JSON

# ── The invariant that outranks every exit ───────────────────────────────────
# A first reaction advances the subject; it never finishes it, and the script
# writes no closed status at all.
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
hasnt "CLOSE" "$LOG" "(NEVERCLOSE) no exit closes the subject"
eq "$(grep -E 'status=closed|bd close' "$SCRIPT" | grep -v -E '^[[:space:]]*(note|die|#)' | grep -c . || true)" "0" \
   "(NEVERCLOSE) …and the script has no write that closes a bead"

# ── A failed act refers to the cause ─────────────────────────────────────────
# gc-helm.sh exits non-zero for a release that did not write AND for a release
# whose route would not stamp, and only it knows which — so this refers to its
# message rather than asserting a state it cannot see.
export FAKE_HELM_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(HELMFAIL) a failed release is a runtime failure"
has "what landed and what did not" "$ERR" "(HELMFAIL) …and the failure refers to the cause gc-helm.sh named"
hasnt "disposed as actionable" "$OUT" "(HELMFAIL) …and nothing reports a disposition"
unset FAKE_HELM_FAILS

# ── Intake: only placed work, PR-finishing work or an emergency enters a pool ──
# Every case above routes a member of an epic. A bead with no parent waits for
# the operator's placement sitting instead: the actionable exit holds it with
# hold:mayor and releases it with no route, and the blocked exit's --then-route
# arms nothing.
#   (INTAKE)       an unplaced subject is held and released unrouted, settled
#   (INTAKEORDER)  the release, then the note, then the hold, the exit's last
#                  write, which the check a re-offered reaction runs refuses
#   (INTAKENOTE)   the note names why it was held and the queue's read
#   (INTAKEPOOL)   the route it never writes is not probed
#   (INTAKEMEMBER) a parent-child dependency is membership even with no .parent,
#                  and a blocks edge is not
#   (INTAKEANCHOR) PR-finishing work (anchor_bead) is routed
#   (INTAKEMARK)   a hold or its note the store refuses fails the exit after the
#                  release, and a re-run lands them
#   (INTAKESTAMP)  a held subject's release the store refuses, its pour stamp
#                  still set, stops the exit before its hold
#   (INTAKEBLK)    an unplaced blocked subject's edge lands and nothing is armed
#   (INTAKEDRY)    a dry run names the hold and writes nothing
export FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "states a done condition and a branch" \
    --takeaway "ready to build once placed" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(INTAKE) an unplaced subject's actionable exit succeeds"
has "SETSTATE bd set-state tk-sub hold=mayor --reason Held for placement instead of reaching gc-toolkit/gc-toolkit.polecat" "$LOG" \
    "(INTAKE) …holding it with Gas City's hold:mayor, through set-state with intake's reason"
has "UPDATE bd update tk-sub --append-notes ## Intake (first reaction" "$LOG" "(INTAKE) …and noting it"
hasnt "placement=pending" "$LOG" "(INTAKE) …with no placement marker"
has "HELM takeaway tk-sub ready to build once placed --by proactive --release --no-wait" "$LOG" \
    "(INTAKE) …and releasing it with no route, nothing waiting on a bead"
hasnt "--route" "$LOG" "(INTAKE) …so no pool is offered it"
before '^HELM takeaway' '## Intake (first reaction' "(INTAKEORDER) the release comes first"
before '## Intake (first reaction' 'hold=mayor' "(INTAKEORDER) …then the note"
eq "$(tail -n 1 "$FAKE_LOG" | cut -c1-12)" "SETSTATE bd " "(INTAKEORDER) …and the hold is the exit's last write"
has "disposed as actionable (held for placement)" "$OUT" "(INTAKE) …and the run says the bead is held for placement"
has "tk-sub has no parent epic and is not PR-finishing work" "$LOG" "(INTAKENOTE) the note names why it was held"
has "gc beads list --label hold:mayor lists it" "$LOG" "(INTAKENOTE) …and the read that lists the queue"
hasnt "PROACTIVE deliverable" "$LOG" "(INTAKEPOOL) the route it never writes is not probed"
hasnt "GH " "$LOG" "(INTAKE) …and with no emergency claimed, GitHub is not read"

export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","dependencies":[{"id":"tk-feat","dependency_type":"parent-child","status":"open"}],"metadata":{}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
has "--release --route gc-toolkit/gc-toolkit.polecat --no-wait" "$LOG" "(INTAKEMEMBER) a parent-child dependency alone is membership"
hasnt "hold=mayor" "$LOG" "(INTAKEMEMBER) …and a member is not held"
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","dependencies":[{"id":"tk-rl","dependency_type":"blocks","status":"open"}],"metadata":{}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
has "hold=mayor" "$LOG" "(INTAKEMEMBER) a blocks edge onto an epic is not membership"
hasnt "--route" "$LOG" "(INTAKEMEMBER) …so the bead is not routed"

export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"anchor_bead":"tk-anchor"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(INTAKEANCHOR) PR-finishing work's actionable exit succeeds"
has "--release --route gc-toolkit/gc-toolkit.polecat --no-wait" "$LOG" "(INTAKEANCHOR) …and it is routed"
hasnt "hold=mayor" "$LOG" "(INTAKEANCHOR) …unheld"

# A hold the store refuses fails the exit after its release, which stands. The
# subject then carries no hold, so the check a re-offered reaction runs passes,
# and the re-run releases again, harmlessly, and lands the hold.
export FAKE_SHOW_JSON="$UNPLACED" FAKE_SETSTATE_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(INTAKEMARK) a hold the store refuses fails the exit"
has "the hold:mayor label did not" "$ERR" "(INTAKEMARK) …naming the write that was refused"
has "HELM takeaway tk-sub" "$LOG" "(INTAKEMARK) …after the release, which stands"
hasnt "disposed as actionable" "$OUT" "(INTAKEMARK) …and the run reports no disposition"
unset FAKE_SETSTATE_FAILS
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(INTAKEMARK) the re-run lands"
before '^HELM takeaway' 'hold=mayor' "(INTAKEMARK) …releasing again, then holding"
export FAKE_NOTES_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "4" "(INTAKEMARK) a note the store refuses fails the exit"
has "intake's note saying why it holds tk-sub did not" "$ERR" "(INTAKEMARK) …naming the note"
hasnt "SETSTATE" "$LOG" "(INTAKEMARK) …before the hold, which a re-run still writes"
unset FAKE_NOTES_FAILS

# (INTAKESTAMP) a held subject still carries a dead pour's stamp, and the release
# that clears it is refused. The store refuses the real gc-helm.sh's update, so
# it fails the release. The exit stops there, before its hold, so the check a
# re-offered reaction runs still passes.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}}]'
export FAKE_UPDATE_REFUSE='gc.takeaway='
real_helm_run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
unset FAKE_UPDATE_REFUSE
eq "$RC" "4" "(INTAKESTAMP) a held subject whose release the store refuses, its pour stamp still set, fails the exit"
has "could not update 'tk-sub'" "$ERR" "(INTAKESTAMP) …at the release"
has "gc-helm.sh takeaway failed on tk-sub" "$ERR" "(INTAKESTAMP) …naming the release that failed"
hasnt "SETSTATE" "$LOG" "(INTAKESTAMP) …before the hold"
# Control: a stamp still set after a release that exits 0 is no hold, so the
# reaction lands. gc-helm.sh clears the stamp in its update, so a stamp set after
# a zero exit was written after the release landed, and the queue reads the hold
# label, not the stamp.
export FAKE_EXEC_ROUTED_FILE="$TMP/exec_routed" FAKE_HELM_KEEPS_STAMP=1
printf 'gc-toolkit/gc-toolkit.polecat' > "$FAKE_EXEC_ROUTED_FILE"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(INTAKESTAMP) a held subject whose stamp is set after its release still lands"
has "hold=mayor" "$LOG" "(INTAKESTAMP) …held"
unset FAKE_EXEC_ROUTED_FILE FAKE_HELM_KEEPS_STAMP

export FAKE_SHOW_JSON="$UNPLACED" FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "waits on the migration" --takeaway "held: migration first" \
    --waiting-on tk-blk1 --then-route gc-toolkit/gc-toolkit.polecat --run "$ROOT"
eq "$RC" "0" "(INTAKEBLK) an unplaced blocked subject's exit succeeds"
has "hold=mayor" "$LOG" "(INTAKEBLK) …held for placement"
has "--release --waiting-on tk-blk1" "$LOG" "(INTAKEBLK) …its wait still an edge"
before '^HELM takeaway' 'hold=mayor' "(INTAKEBLK) …the hold written after the wait"
hasnt "GCTK bead arm" "$LOG" "(INTAKEBLK) …and no dispatch armed: placing it is the sitting's"
hasnt "PROACTIVE deliverable" "$LOG" "(INTAKEBLK) …so the then-route is not probed"
has "disposed as blocked (tk-blk1; held for placement)" "$OUT" "(INTAKEBLK) …and the run names both waits"
unset FAKE_DEPS_JSON

export FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --dry-run
eq "$RC" "0" "(INTAKEDRY) a dry run of a held exit succeeds"
has "would hold tk-sub for placement (hold:mayor, unrouted)" "$OUT" "(INTAKEDRY) …naming the hold"
eq "$(writes)" "" "(INTAKEDRY) …and writing nothing, no hold included"
unset FAKE_SHOW_JSON

# ── The po takes no work by assignment ────────────────────────────────────────
# Its queue is the new work intake holds, so neither assignment flag may name it,
# bare or qualified, and the refusal comes before any read or write.
#   (PO)  --assign and --then-assign naming the po are usage errors that write nothing
for who in gc-toolkit.po po gc-toolkit/gc-toolkit.po; do
    run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign "$who" --run "$ROOT"
    eq "$RC" "2" "(PO) --assign $who is refused"
    has "--assign $who names the po, which takes no work by assignment" "$ERR" "(PO) …saying why"
    eq "$(writes)" "" "(PO) …and writing nothing"
done
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit.po --run "$ROOT"
eq "$RC" "2" "(PO) --then-assign naming the po is refused"
has "--then-assign gc-toolkit.po names the po" "$ERR" "(PO) …naming the flag"
has "Pass --then-route" "$ERR" "(PO) …and the pool flag that does the job"
eq "$(writes)" "" "(PO) …writing nothing"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.polecat-po --run "$ROOT"
hasnt "names the po" "$ERR" "(PO) an agent whose name only ends in po is not the po"

# ── Intake's emergency: checked, not asserted ────────────────────────────────
# --emergency <check> claims a red main or a broken gate, naming the check whose
# failure it is about. The claim admits a bead at P0 only when that check is
# failing on the head of main, read from GitHub through the subject's own rig
# checkout.
#   (EMERG)       a confirmed emergency is written P0, then routed
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
#   (EMERGPRIO)   a P0 the store refuses stops the exit before the route
#   (EMERGBLK)    an emergency's then-route arms at P0
#   (EMERGARGS)   --emergency rides only a pool route, and names a check
mkdir -p "$TMP/rig/.beads"
export FAKE_RIG_PATH="$TMP/rig" FAKE_ORIGIN_URL="git@github.com:zook/repo.git"
export FAKE_SHOW_JSON="$UNPLACED" FAKE_GH=red
run tk-sub --disposition actionable --reason "test-macos fails on main" --takeaway "fix red main" \
    --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
eq "$RC" "0" "(EMERG) a confirmed emergency's actionable exit succeeds"
has "GH api repos/zook/repo/commits/main/check-runs" "$LOG" "(EMERG) the claim is checked against main's own checks"
has "UPDATE bd update tk-sub --priority 0 --append-notes ## Intake (first reaction" "$LOG" "(EMERG) …P0 is written"
before '--priority 0' '^HELM takeaway' "(EMERG) …before the route"
has "--release --route gc-toolkit/gc-toolkit.polecat --no-wait" "$LOG" "(EMERG) …and the bead is routed"
hasnt "hold=mayor" "$LOG" "(EMERG) …unheld"
has "main of zook/repo at abcdef123456 is red: test-macos (failure)" "$LOG" "(EMERG) the note names the head and the failing check"
has "disposed as actionable (gc-toolkit/gc-toolkit.polecat at P0)" "$OUT" "(EMERG) …and the run says P0"

export FAKE_GH=status-red
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency ci/legacy --run "$ROOT"
has "--priority 0" "$LOG" "(EMERGSTATUS) a failing commit status confirms an emergency"
has "ci/legacy (failure)" "$LOG" "(EMERGSTATUS) …named in the note"

export FAKE_GH=red FAKE_SHOW_JSON="$DEFAULT_SHOW"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
has "--priority 0" "$LOG" "(EMERGMEMBER) a member claimed as a confirmed emergency is written P0"
has "--release --route gc-toolkit/gc-toolkit.polecat" "$LOG" "(EMERGMEMBER) …and routed"

export FAKE_GH=green FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
eq "$RC" "0" "(EMERGNO) an unconfirmed emergency's exit still lands"
has "hold=mayor" "$LOG" "(EMERGNO) …held for placement"
hasnt "--priority" "$LOG" "(EMERGNO) …at the priority it was filed at"
hasnt "--route" "$LOG" "(EMERGNO) …and unrouted"
has "--emergency was not confirmed: test-macos is not failing on main of zook/repo at abcdef123456" "$LOG" \
    "(EMERGNO) the note says what the check found"
hasnt "other checks failing" "$LOG" "(EMERGNO) …and names no other failing check, because none fails"
export FAKE_GH=green FAKE_SHOW_JSON="$DEFAULT_SHOW"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
has "--release --route gc-toolkit/gc-toolkit.polecat" "$LOG" "(EMERGNO) an unconfirmed emergency on a member still routes as a member"
hasnt "--priority" "$LOG" "(EMERGNO) …at its own priority"

# Main is red on test-macos. A claim naming a check that passes there, or one
# main does not carry, says nothing about this bead, so it is held.
export FAKE_GH=red FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency lint --run "$ROOT"
eq "$RC" "0" "(EMERGOTHER) a claim on a passing check, while another check fails, still lands"
has "hold=mayor" "$LOG" "(EMERGOTHER) …held for placement"
hasnt "--priority" "$LOG" "(EMERGOTHER) …at the priority it was filed at"
hasnt "--route" "$LOG" "(EMERGOTHER) …and unrouted"
has "--emergency was not confirmed: lint is not failing on main of zook/repo at abcdef123456; other checks failing there: test-macos (failure)" "$LOG" \
    "(EMERGOTHER) the note names the claimed check and the check that does fail"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-windows --run "$ROOT"
has "hold=mayor" "$LOG" "(EMERGOTHER) a claim on a check main does not carry is held"
has "main of zook/repo at abcdef123456 has no check named test-windows; other checks failing there: test-macos (failure)" "$LOG" \
    "(EMERGOTHER) …and the note says no check by that name runs there"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency=test-macos --run "$ROOT"
has "--priority 0" "$LOG" "(EMERGOTHER) --emergency=<check> names the check the same way"

export FAKE_GH=down FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
eq "$RC" "0" "(EMERGDOWN) a GitHub that does not answer leaves the exit landing"
has "hold=mayor" "$LOG" "(EMERGDOWN) …held, because an unread check confirms nothing"
has "GitHub did not answer for the default branch of zook/repo (gh exit 1)" "$LOG" "(EMERGDOWN) …and the note says so"
export FAKE_GH=red
unset FAKE_ORIGIN_URL
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
has "hold=mayor" "$LOG" "(EMERGDOWN) a checkout with no origin confirms nothing"
has "is not a GitHub repository" "$LOG" "(EMERGDOWN) …and the note names why"
hasnt "GH " "$LOG" "(EMERGDOWN) …and GitHub is not asked about a repository nobody named"
export FAKE_ORIGIN_URL="https://github.com/zook/repo"

export FAKE_GH=red-page2
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-e2e --run "$ROOT"
has "GH api repos/zook/repo/commits/main/check-runs?per_page=100 --paginate" "$LOG" "(EMERGPAGE) the check runs are read across every page"
has "--priority 0" "$LOG" "(EMERGPAGE) …so a failing run on the second page confirms the emergency"
has "test-e2e (timed_out)" "$LOG" "(EMERGPAGE) …named in the note"
export FAKE_GH=status-red-page2
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency ci/legacy --run "$ROOT"
has "GH api repos/zook/repo/commits/main/status?per_page=100 --paginate" "$LOG" "(EMERGPAGE) the commit statuses are read across every page"
has "--priority 0" "$LOG" "(EMERGPAGE) …so a failing status on the second page confirms the emergency"
has "ci/legacy (error)" "$LOG" "(EMERGPAGE) …named in the note"

export FAKE_GH=hang GC_FIRST_REACTION_GH_TIMEOUT=1
SLOW_T0=$SECONDS
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
SLOW_DT=$((SECONDS - SLOW_T0))
eq "$RC" "0" "(EMERGSLOW) a GitHub that stalls leaves the exit landing"
[ "$SLOW_DT" -lt 15 ] && ok "(EMERGSLOW) …cut off at the bound rather than held for the stall (${SLOW_DT}s)" \
    || bad "(EMERGSLOW) …cut off at the bound rather than held for the stall (took ${SLOW_DT}s)"
has "hold=mayor" "$LOG" "(EMERGSLOW) …held, because a read that ran out of time confirms nothing"
has "GitHub did not answer for the check runs on main of zook/repo within 1s" "$LOG" "(EMERGSLOW) …and the note says the read timed out"
unset GC_FIRST_REACTION_GH_TIMEOUT
export FAKE_GH=red

export FAKE_UPDATE_REFUSE='--priority 0'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
eq "$RC" "4" "(EMERGPRIO) a P0 the store refuses stops the exit"
has "could not write priority P0 on tk-sub" "$ERR" "(EMERGPRIO) …naming the write that was refused"
hasnt "HELM takeaway" "$LOG" "(EMERGPRIO) …before the route, so it is never claimable at the wrong priority"
unset FAKE_UPDATE_REFUSE

export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --emergency test-macos --run "$ROOT"
eq "$RC" "0" "(EMERGBLK) a blocked emergency's exit succeeds"
before '--priority 0' '^GCTK bead arm' "(EMERGBLK) …P0 written before the arm"
has "GCTK bead arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" "(EMERGBLK) …and the dispatch armed"
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
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --run "$ROOT" --emergency
eq "$RC" "2" "(EMERGARGS) --emergency that names no check is refused"
has "needs the name of the check that fails on main" "$ERR" "(EMERGARGS) …saying what it needs"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency --run "$ROOT"
eq "$RC" "2" "(EMERGARGS) …and so is one followed by another flag instead of a check"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency= --run "$ROOT"
eq "$RC" "2" "(EMERGARGS) …and so is an empty --emergency="
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency "  " --run "$ROOT"
eq "$RC" "2" "(EMERGARGS) …and so is a blank check name"
eq "$LOG" "" "(EMERGARGS) …and nothing was written"
unset FAKE_SHOW_JSON FAKE_GH FAKE_ORIGIN_URL FAKE_RIG_PATH

echo ""
echo "first-reaction-dispose (exits): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
