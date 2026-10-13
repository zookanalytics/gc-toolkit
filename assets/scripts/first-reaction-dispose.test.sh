#!/usr/bin/env bash
# Hermetic tests for first-reaction-dispose.sh — the five exits a first reaction
# ends in, in the reaction-bead model, and the frozen no-reaction-bead call an
# in-flight mol-first-reaction molecule still makes. Runs the REAL script with a
# stubbed `gc`, a stubbed gc-helm.sh, a stubbed gc-proactive.sh and a stubbed
# deferred-dispatch.sh (all reached through the tool-override env vars), so no
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
    # FAKE_NOTES_FAILS models a notes append that does not land.
    case " $* " in
      *" gc.proactive_reaction=1 "*) [ -n "${FAKE_PROACTIVE_STAMP_FAILS:-}" ] && exit 1 ;;
      *" --append-notes "*) [ -n "${FAKE_NOTES_FAILS:-}" ] && exit 1 ;;
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
                          esac ;;
        --unset-metadata) [ "$_a" = "gc.recommended_formula" ] && _reco_unset=1 ;;
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
    printf '%s\n' "$_shown" ;;
  "bd list")
    printf 'LIST %s\n' "$*" >> "$FAKE_LOG"
    printf '%s\n' "${FAKE_LIST_JSON:-[]}" ;;
  "bd dep")
    printf 'DEP %s\n' "$*" >> "$FAKE_LOG"
    # `dep list --json` answers with what the store holds AFTER the helm call;
    # `dep add` is the close exit's gate edge, and FAKE_DEP_FAILS models a hold
    # that did not land.
    case "${3:-}" in
      add)  [ -n "${FAKE_DEP_FAILS:-}" ] && exit 1 ;;
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
# demand files the human gate a ruling or recommend holds on, and names it the
# way gc-helm.sh does: a `demand <id> blocks <gated> …` line on stdout.
# FAKE_DEMAND_FAILS models a gate that did not file (gc-helm.sh exits 4);
# FAKE_DEMAND_NOID a demand that exits 0 but names no gate.
if [ "${1:-}" = demand ]; then
  [ -n "${FAKE_DEMAND_FAILS:-}" ] && exit 4
  [ -n "${FAKE_DEMAND_NOID:-}" ] && exit 0
  printf 'blocks edge: %s depends on %s\n' "$2" "${FAKE_GATE_ID:-tk-gate1}"
  printf 'demand %s blocks %s (by proactive): %s\n' "${FAKE_GATE_ID:-tk-gate1}" "$2" "$3"
  exit 0
fi
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
# still-running runs, none red), down (gh answers nothing).
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<'GIT'
case "$*" in
  *"remote get-url origin"*) [ -n "${FAKE_ORIGIN_URL:-}" ] || exit 2; printf '%s\n' "$FAKE_ORIGIN_URL" ;;
  *) exit 1 ;;
esac
GIT
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gh" <<'GH'
printf 'GH %s\n' "$*" >> "$FAKE_LOG"
[ "${FAKE_GH:-}" = down ] && exit 1
case "${2:-}" in
  repos/*/check-runs*)
    case "${FAKE_GH:-}" in
      red) printf '%s\n' '{"total_count":2,"check_runs":[{"name":"lint","status":"completed","conclusion":"success","head_sha":"abcdef1234567890"},{"name":"test-macos","status":"completed","conclusion":"failure","head_sha":"abcdef1234567890"}]}' ;;
      *)   printf '%s\n' '{"total_count":3,"check_runs":[{"name":"lint","status":"completed","conclusion":"success","head_sha":"abcdef1234567890"},{"name":"test-linux","status":"completed","conclusion":"cancelled","head_sha":"abcdef1234567890"},{"name":"test-macos","status":"in_progress","conclusion":null,"head_sha":"abcdef1234567890"}]}' ;;
    esac ;;
  repos/*/status)
    case "${FAKE_GH:-}" in
      status-red) printf '%s\n' '{"state":"failure","sha":"abcdef1234567890","statuses":[{"context":"ci/legacy","state":"failure"}]}' ;;
      *)          printf '%s\n' '{"state":"success","sha":"abcdef1234567890","statuses":[]}' ;;
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
       GC_PROACTIVE_TOOL="$TMP/proactive"

R="tk-react"   # the reaction bead the worker holds

# Reset per run, then seed the recommendation state from the fixture so the first
# `bd show` matches FAKE_SHOW_JSON and later writes mutate it from there.
run() {
  : > "$FAKE_LOG"; rm -f "$FAKE_STATE.dropped" "$FAKE_STATE.placement" "$FAKE_STATE.placement-dropped" "$FAKE_STATE.priority"
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
# A town-repo edit is mechanik's direct edit, and mechanik is a named agent: its
# hook matches the bead's assignee and never reads gc.routed_to, so the exit
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
run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1 --assign gc-toolkit.mechanik
eq "$RC" "2" "(ASSIGNEXIT) ruling refuses --assign: it waits on the operator"
eq "$LOG" "" "(ASSIGNEXIT) …and nothing was written"
run tk-sub --disposition ruling --reason "r" --takeaway "t" --then-assign gc-toolkit.mechanik
eq "$RC" "2" "(ASSIGNEXIT) ruling refuses --then-assign: its wait is the operator's gate"
eq "$LOG" "" "(ASSIGNEXIT) …and no gate was filed"

: > "$FAKE_LOG"; RC=0
OUT="$("$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --dry-run 2>"$TMP/err")" || RC=$?
eq "$RC" "0" "(ASSIGNDRY) a dry run of the --assign exit succeeds"
has "would release tk-sub to named agent gc-toolkit.mechanik" "$OUT" "(ASSIGNDRY) …and names the agent it would hand the bead to"
hasnt "UPDATE" "$(cat "$FAKE_LOG")" "(ASSIGNDRY) …writing nothing"

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

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on sl-foreign --reaction-bead "$R"
eq "$RC" "2" "(BLKCROSS) a blocker in another store is refused"
eq "$LOG" "" "(BLKCROSS) …and nothing was written"
has "holds nothing" "$ERR" "(BLKCROSS) …because the edge would report success and hold nothing"
has "demand bead" "$ERR" "(BLKCROSS) …and the refusal names the remedy"

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
# its agent's hook only once bd reports it ready, so the edge is the gate and
# nothing is armed: a deferred dispatch slings a pool, and a named agent is not
# one.
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
hasnt "DEFERRED arm" "$LOG" "(BLKASSIGN) …and no deferred dispatch is armed for a named agent"
has "PROACTIVE assignable gc-toolkit.mechanik tk-sub" "$LOG" "(BLKASSIGN) the exit asks whether the agent's hook would offer the bead"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --then-assign gc-toolkit.mechanik
eq "$RC" "2" "(BLKASSIGN) --then-route beside --then-assign is refused"
eq "$LOG" "" "(BLKASSIGN) …and nothing was written"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --assign gc-toolkit.mechanik
eq "$RC" "2" "(BLKASSIGN) blocked refuses --assign, the actionable exit's flag"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik --dry-run
eq "$RC" "0" "(BLKASSIGN) a dry run of the --then-assign exit succeeds"
has "would wait tk-sub on: tk-blk1, assigned to gc-toolkit.mechanik" "$OUT" "(BLKASSIGN) …and names the agent the held bead goes to"
hasnt "UPDATE" "$LOG" "(BLKASSIGN) …writing nothing"

export FAKE_AGENT_GONE=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit/gc-toolkit.witness
eq "$RC" "2" "(BLKASSIGN) a --then-assign agent that cannot be handed the bead is refused"
hasnt "HELM" "$LOG" "(BLKASSIGN) …and the bead is not released"
unset FAKE_AGENT_GONE FAKE_DEPS_JSON

# ── ruling: the human gate is the wait, filed by the exit itself ─────────────
#   (RUL)      the exit files the gate through gc-helm.sh demand, the takeaway
#              as its question, and holds the subject on it
#   (RULTOPIC) the gate is filed under the topic first-reaction
#   (RULORDER) gate, then release, then the landed proof
#   (RULGATE)  a gate that did not file, or that demand did not name, fails
#              the exit before the release, with nothing recorded done
#   (RULEDGE)  a hold that did not land fails the exit
#   (RULVISIT) --visit holds the subject on a visit the caller filed, no gate
# The gate is the escalation's state; gate-visit-sweep files the visit that
# resolves it, so the exit files no visit. The FAKE dep list answers with the
# gate so the hold verification passes.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --reaction-bead "$R"
eq "$RC" "0" "(RUL) a ruling disposition succeeds"
has "HELM demand tk-sub needs a ruling: which default --by proactive --topic first-reaction --body" "$LOG" \
   "(RUL) it files the human gate, the takeaway as the gate's question"
# gc-helm.sh demand keeps one open gate per gated bead and topic. With no topic
# it matches on the subject alone: it refreshes a converse sitting's lone demand
# on the subject in place, overwriting the question that sitting holds, and stops
# on a subject that carries two. The reaction's own topic files beside them.
has "--topic first-reaction" "$(grep '^HELM demand' "$FAKE_LOG")" \
   "(RULTOPIC) the gate is filed under the first reaction's own topic"
# The body spans lines, so read the demand call up to the release that follows it.
has "the trade-off is the operator's" "$(sed -n '/^HELM demand/,/^HELM takeaway/p' "$FAKE_LOG")" \
   "(RUL) …with the reason in the gate's body"
has "HELM takeaway tk-sub needs a ruling: which default --by proactive --release" "$LOG" \
   "(RUL) the bead is released back to the human"
hasnt "--route" "$LOG" "(RUL) …not routed to a pool"
has "--waiting-on tk-gate1" "$LOG" "(RUL) …and held by the gate's edge"
# A ruling names the gate as its wait: the subject waits on a person, the gate
# is what a person owes, and --waiting-on records that wait as a blocks edge so
# doctor/check-wait-is-an-edge reads a graph state rather than reporting prose.
hasnt "--no-wait" "$LOG" "(RUL) …and never claims nothing is waiting"
hasnt "CREATE" "$LOG" "(RUL) …and files no visit: gate-visit-sweep files it"
has "disposed as ruling (tk-gate1)" "$OUT" "(RUL) …and reports the gate it disposed onto"
has "gc.reacted_by=$R" "$LOG" "(RUL) the landed proof is stamped"
has "UPDATE bd update $R" "$LOG" "(RUL) …and the reaction bead is closed"
before '^HELM demand' '^HELM takeaway' "(RULORDER) the gate is filed before the release"
before '^HELM takeaway' 'gc.reacted_by' "(RULORDER) …and the landed proof follows the release"

export FAKE_DEMAND_FAILS=1
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "4" "(RULGATE) a gate that did not file fails the exit"
hasnt "HELM takeaway" "$LOG" "(RULGATE) …and the subject is not released onto a gate that does not exist"
has "re-run this command" "$ERR" "(RULGATE) …and the failure names the retry"
hasnt "gc.reacted_by" "$LOG" "(RULGATE) …with no landed proof stamped"
hasnt "UPDATE bd update $R" "$LOG" "(RULGATE) …and the reaction bead left open for the re-offer"
unset FAKE_DEMAND_FAILS

export FAKE_DEMAND_NOID=1
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "4" "(RULGATE) a demand that names no gate fails the exit"
hasnt "HELM takeaway" "$LOG" "(RULGATE) …before the release"
unset FAKE_DEMAND_NOID

export FAKE_DEPS_JSON='[]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "4" "(RULEDGE) a gate edge that is not on the subject fails the exit"
has "not held by tk-gate1" "$ERR" "(RULEDGE) …naming the gate it is not held by"
hasnt "gc.reacted_by" "$LOG" "(RULEDGE) …with no landed proof stamped"

export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --visit tk-visit1 --reaction-bead "$R"
eq "$RC" "0" "(RULVISIT) a ruling held on a caller's visit succeeds"
hasnt "HELM demand" "$LOG" "(RULVISIT) …and files no gate"
has "--waiting-on tk-visit1" "$LOG" "(RULVISIT) …and holds the subject"
has "disposed as ruling (tk-visit1)" "$OUT" "(RULVISIT) …and reports the visit it disposed onto"

run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit sl-foreign --reaction-bead "$R"
eq "$RC" "2" "(RULVISIT) a visit in another store is refused"
eq "$LOG" "" "(RULVISIT) …and nothing was written"

: > "$FAKE_LOG"; RC=0
OUT="$("$SCRIPT" tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R" --dry-run 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(RULDRY) a dry run succeeds"
has "would file a human gate on tk-sub" "$OUT" "(RULDRY) …saying it would file the gate"
has "would close reaction bead $R" "$OUT" "(RULDRY) …and close the reaction bead"
hasnt "HELM" "$LOG" "(RULDRY) …and files nothing"
hasnt "UPDATE" "$LOG" "(RULDRY) …and writes nothing"

# ── recommend: the gate's visit offers Accept ────────────────────────────────
# recommend names a determinable action (converse/operator authority) and stamps
# gc.recommended_formula on the subject. That stamp is the whole difference
# between a plain Discuss-only ruling visit and a recommendation visit the
# operator can Accept, and it lands before the act. recommend files and holds on
# the same human gate ruling does, and the stamp lands before the gate is filed,
# so the visit gate-visit-sweep files for the gate offers Accept from the start.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition recommend --reason "retire the PR, supersede its anchor — operator authority" \
    --takeaway "recommend: retire PR + supersede anchor; execute via mol-x — Accept or Discuss" \
    --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "0" "(RECO) a recommend disposition succeeds"
has "gc.recommended_formula=mol-x" "$LOG" "(RECO) the recommended formula is stamped on the subject"
has "HELM demand tk-sub recommend: retire PR + supersede anchor; execute via mol-x — Accept or Discuss" "$LOG" \
   "(RECO) …it files the human gate, as ruling does"
has "--topic first-reaction" "$(grep '^HELM demand' "$FAKE_LOG")" \
   "(RECO) …under the first reaction's own topic"
has "--waiting-on tk-gate1" "$LOG" "(RECO) …and the gate holds the subject, the ruling shape"
before 'gc.recommended_formula=mol-x' '^HELM demand' "(RECO) …the recommendation lands before the gate"
before '^HELM demand' '^HELM takeaway' "(RECO) …and the gate before the release"
has "gc.reacted_by=$R" "$LOG" "(RECO) the landed proof is stamped"
has "UPDATE bd update $R" "$LOG" "(RECO) …and the reaction bead is closed"

# recommend REQUIRES the flag it exists to carry: no --recommended-formula is a
# usage error naming ruling as the flagless alternative.
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via <mol> — Accept or Discuss" --visit tk-visit1 --reaction-bead "$R"
eq "$RC" "2" "(RECO) recommend with no --recommended-formula is refused"
eq "$LOG" "" "(RECO) …and writes nothing"
has "is --disposition ruling" "$ERR" "(RECO) …naming ruling as the flagless alternative"

# --visit holds a recommend on a visit the caller filed, the way it does a ruling.
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" --visit tk-visit1 --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "0" "(RECO) a recommend held on a caller's visit succeeds"
hasnt "HELM demand" "$LOG" "(RECO) …and files no gate"
has "--waiting-on tk-visit1" "$LOG" "(RECO) …the visit holds the subject"

# A recommended formula that does not resolve is a usage error, refused before
# anything is written: Accept slings this exact name, so a typo would stamp a live
# gc.recommended_formula and render an 'accept ▸' that fails at gc sling on every
# click. Validated the way --route/--then-route are against the roster.
export FAKE_FORMULA_MISSING="mol-typo"
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-typo — Accept or Discuss" \
    --visit tk-visit1 --recommended-formula mol-typo --reaction-bead "$R"
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
    --takeaway "needs a ruling: which default" --visit tk-visit1 --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "2" "(RECO) ruling refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
has "use --disposition recommend" "$ERR" "(RECO) …pointing at the disposition that carries a recommendation"

# A plain ruling stamps nothing, so the visit stays Discuss-only (no Accept).
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --visit tk-visit1 --reaction-bead "$R"
eq "$RC" "0" "(RECO) a Discuss-only ruling succeeds"
hasnt "gc.recommended_formula" "$LOG" "(RECO) …and stamps no recommendation, so the visit offers no Accept"

# A subject can already carry a recommendation a prior recommend stamped: the
# stamp landed, the act did not (no landed proof), and this retry resumes it. A
# ruling retry names no recommendation and clears that stale stamp before the
# act, so the visit never offers Accept for an action the current disposition did
# not recommend.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.recommended_formula":"mol-old"}}]'
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --visit tk-visit1 --reaction-bead "$R"
eq "$RC" "0" "(RECO) a ruling retry over a stale recommendation succeeds"
has "--unset-metadata gc.recommended_formula" "$LOG" "(RECO) …and clears the stale recommendation the prior recommend left"
hasnt "gc.recommended_formula=" "$LOG" "(RECO) …stamping no new one, so the subject states the current disposition"

# The same stale stamp retried as a recommend with a different formula replaces
# the stale one rather than clearing it — the subject always states the current
# recommendation, whichever direction it moves.
run tk-sub --disposition recommend --reason "the newer mol is the right execution" \
    --takeaway "recommend: execute via mol-new — Accept or Discuss" \
    --visit tk-visit1 --recommended-formula mol-new --reaction-bead "$R"
eq "$RC" "0" "(RECO) a retry that re-recommends succeeds"
has "gc.recommended_formula=mol-new" "$LOG" "(RECO) …and the subject carries the new recommendation"
hasnt "--unset-metadata gc.recommended_formula" "$LOG" "(RECO) …with no stale-clear, because the recommend names one"
unset FAKE_SHOW_JSON

# ── The recommendation must land before the act (read-back guard) ─────────────
# gc.recommended_formula is presence-sensitive downstream, so a silently dropped
# write is a wrong operator affordance, not a cosmetic miss. An update reports
# success without proving this one key moved, so the exit reads it back, retries
# the lone set/unset once, and refuses before the act if it is still wrong —
# nothing else has been written, so the command re-runs.
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'

# A set that silently drops and never recovers: the act is withheld, so nothing
# files a recommendation visit the operator could only Discuss.
export FAKE_DROP_RECO=1
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" \
    --visit tk-visit1 --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "4" "(RECOGUARD) a silently dropped recommendation set refuses the exit"
hasnt "HELM" "$LOG" "(RECOGUARD) …the act is withheld, so no Discuss-only visit is filed"
has "did not land" "$ERR" "(RECOGUARD) …and the refusal names the key that did not land"
hasnt "UPDATE bd update $R" "$LOG" "(RECOGUARD) …and the reaction bead is left open for the re-offer"
# The gate brings the visit, so the guard must refuse before the gate is filed:
# a gate filed over a dropped recommendation gets a visit that offers only
# Discuss.
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "4" "(RECOGUARD) the same drop on the gate form refuses the exit"
hasnt "HELM demand" "$LOG" "(RECOGUARD) …before the gate is filed, so no visit can offer only Discuss"
unset FAKE_DROP_RECO

# The same drop, but the lone retry lands it: the act proceeds.
export FAKE_DROP_RECO=once
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" \
    --visit tk-visit1 --recommended-formula mol-x --reaction-bead "$R"
eq "$RC" "0" "(RECOGUARD) a set that lands on the retry lets the act proceed"
has "HELM takeaway tk-sub" "$LOG" "(RECOGUARD) …the act runs once the recommendation is confirmed"
unset FAKE_DROP_RECO

# A stale-clear that silently drops and never recovers: the act is withheld, so a
# Discuss-only retry never leaves a superseded Accept executable.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.recommended_formula":"mol-old"}}]'
export FAKE_DROP_RECO=1
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --visit tk-visit1 --reaction-bead "$R"
eq "$RC" "4" "(RECOGUARD) a silently dropped stale-clear refuses the exit"
hasnt "HELM" "$LOG" "(RECOGUARD) …the act is withheld, so the superseded Accept is never left executable"
has "did not clear" "$ERR" "(RECOGUARD) …and the refusal names the stale key that did not clear"
unset FAKE_DROP_RECO FAKE_SHOW_JSON  # leave FAKE_DEPS_JSON: later ruling tests reuse the visit edge

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
    --takeaway "needs a ruling: which default" --visit tk-visit1 --reaction-bead "$R"
eq "$RC" "4" "(RECOGUARD) an unreadable stale-clear read-back refuses the exit"
hasnt "HELM" "$LOG" "(RECOGUARD) …the act is withheld, so a stale Accept cannot slip through an unreadable read"
has "did not clear" "$ERR" "(RECOGUARD) …and the refusal names the key it could not prove cleared"
unset FAKE_SHOW_UNREADABLE_AFTER_UPDATE FAKE_SHOW_JSON  # leave FAKE_DEPS_JSON for later ruling tests

# --recommended-formula belongs to the recommend exit only: actionable, blocked,
# and close route, hold, or hand the bead to a closer, and none gates a visit the
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
# gc-visit-open stamps gc.origin=operator on a topic a human typed, but the
# script does not force such a bead to the ruling exit: an operator capture is
# triaged on its merits, so every exit is open to it. The guardrail that a fork
# or an irreversible action still goes to a human lives in the reacting agent's
# rubric, not here.
export FAKE_SHOW_JSON='[{"id":"tk-sub",'"$MEMBER"',"metadata":{"gc.origin":"operator"}}]'
export FAKE_DEPS_JSON='[{"id":"tk-blk1"},{"id":"tk-visit1"}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(ORIGIN) an operator-origin subject may take the actionable exit"
has "HELM takeaway tk-sub" "$LOG" "(ORIGIN) …and is routed like any other bead"
hasnt "the visit IS the answer" "$ERR" "(ORIGIN) …with no operator-origin refusal"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --reaction-bead "$R"
eq "$RC" "0" "(ORIGIN) …the blocked exit too"

run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1 --reaction-bead "$R"
eq "$RC" "0" "(ORIGIN) …and the ruling exit, when the agent chooses it"
# Leave FAKE_DEPS_JSON holding tk-visit1 for the ruling-exit checks downstream.
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
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
hasnt "HELM demand" "$LOG" "(REOFFER) …and the gate form files no second gate"
# A marker naming a DIFFERENT reaction does not suppress this one (re-reaction).
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open",'"$MEMBER"',"metadata":{"gc.reacted_by":"tk-oldreact"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(REOFFER) a marker from a DIFFERENT reaction does not block this one"
has "HELM takeaway tk-sub" "$LOG" "(REOFFER) …the reaction proceeds"
unset FAKE_SHOW_JSON

# ── The frozen mol-first-reaction call (no --reaction-bead) ───────────────────
# An in-flight molecule calls this without --reaction-bead, so it has no R to key
# exactly-once on. The write-back runs and, in place of gc.reacted_by, stamps the
# legacy landed proof gc.proactive_reaction=1 — the marker that molecule's own
# REACTED checks read and this script's re-offer guard keys on.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "0" "(LEGACY) the frozen call with no --reaction-bead still disposes"
has "HELM demand tk-sub" "$LOG" "(LEGACY) …the act runs"
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
hasnt "HELM demand" "$LOG" "(LEGACY-REOFFER) …the gate form files no second gate"
# bd stores `--set-metadata gc.proactive_reaction=1` as the JSON number 1, so the
# guard must read the number the same as the string.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.proactive_reaction":1}}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1
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
# A ruling whose gate already filed resumes through demand again, under the same
# topic, which refreshes the gate the first run filed instead of filing a second.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{}}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "0" "(RESUME) the gate form resumes"
has "HELM demand tk-sub" "$LOG" "(RESUME) …asking demand for the subject's gate again"
has "--topic first-reaction" "$(grep '^HELM demand' "$FAKE_LOG")" \
   "(RESUME) …under the topic the first run filed it under"
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
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
# --emergency claims a red main or a broken gate. The claim admits a bead at P0
# only when the head of main carries a failing check, read from GitHub through
# the subject's own rig checkout.
#   (EMERG)       a confirmed emergency is written P0, read back, then routed
#   (EMERGSTATUS) a failing commit status confirms it as a failing check run does
#   (EMERGMEMBER) an emergency outranks membership: a member is routed at P0
#   (EMERGNO)     a green main confirms nothing, so the bead is held, and the
#                 note says what the check found
#   (EMERGDOWN)   a check that cannot run confirms nothing
#   (EMERGPRIO)   a P0 that does not land stops the exit before the route
#   (EMERGBLK)    an emergency's then-route arms at P0
#   (EMERGARGS)   --emergency rides only a pool route
mkdir -p "$TMP/rig/.beads"
export FAKE_RIG_PATH="$TMP/rig" FAKE_ORIGIN_URL="git@github.com:zook/repo.git"
export FAKE_SHOW_JSON="$UNPLACED" FAKE_GH=red
run tk-sub --disposition actionable --reason "test-macos fails on main" --takeaway "fix red main" \
    --route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
eq "$RC" "0" "(EMERG) a confirmed emergency's actionable exit succeeds"
has "GH api repos/zook/repo/commits/main/check-runs" "$LOG" "(EMERG) the claim is checked against main's own checks"
has "UPDATE bd update tk-sub --priority 0 --append-notes ## Intake (first reaction" "$LOG" "(EMERG) …P0 is written"
before '--priority 0' '^HELM takeaway' "(EMERG) …before the route"
has "--release --route gc-toolkit/gc-toolkit.polecat --no-wait" "$LOG" "(EMERG) …and the bead is routed"
hasnt "placement=pending" "$LOG" "(EMERG) …unmarked"
has "main of zook/repo at abcdef123456 is red: test-macos (failure)" "$LOG" "(EMERG) the note names the head and the failing check"
has "disposed as actionable (gc-toolkit/gc-toolkit.polecat at P0)" "$OUT" "(EMERG) …and the run says P0"

export FAKE_GH=status-red
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
has "--priority 0" "$LOG" "(EMERGSTATUS) a failing commit status confirms an emergency"
has "ci/legacy (failure)" "$LOG" "(EMERGSTATUS) …named in the note"

export FAKE_GH=red FAKE_SHOW_JSON="$DEFAULT_SHOW"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
has "--priority 0" "$LOG" "(EMERGMEMBER) a member claimed as a confirmed emergency is written P0"
has "--release --route gc-toolkit/gc-toolkit.polecat" "$LOG" "(EMERGMEMBER) …and routed"

export FAKE_GH=green FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
eq "$RC" "0" "(EMERGNO) an unconfirmed emergency's exit still lands"
has "placement=pending" "$LOG" "(EMERGNO) …held for placement"
hasnt "--priority" "$LOG" "(EMERGNO) …at the priority it was filed at"
hasnt "--route" "$LOG" "(EMERGNO) …and unrouted"
has "--emergency was not confirmed: main of zook/repo at abcdef123456 has no failing check" "$LOG" \
    "(EMERGNO) the note says what the check found"
export FAKE_GH=green FAKE_SHOW_JSON="$DEFAULT_SHOW"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
has "--release --route gc-toolkit/gc-toolkit.polecat" "$LOG" "(EMERGNO) an unconfirmed emergency on a member still routes as a member"
hasnt "--priority" "$LOG" "(EMERGNO) …at its own priority"

export FAKE_GH=down FAKE_SHOW_JSON="$UNPLACED"
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
eq "$RC" "0" "(EMERGDOWN) a GitHub that does not answer leaves the exit landing"
has "placement=pending" "$LOG" "(EMERGDOWN) …held, because an unread check confirms nothing"
has "GitHub did not name the default branch of zook/repo" "$LOG" "(EMERGDOWN) …and the note says so"
export FAKE_GH=red
unset FAKE_ORIGIN_URL
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
has "placement=pending" "$LOG" "(EMERGDOWN) a checkout with no origin confirms nothing"
has "is not a GitHub repository" "$LOG" "(EMERGDOWN) …and the note names why"
hasnt "GH " "$LOG" "(EMERGDOWN) …and GitHub is not asked about a repository nobody named"
export FAKE_ORIGIN_URL="https://github.com/zook/repo"

export FAKE_DROP_PRIORITY=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
eq "$RC" "4" "(EMERGPRIO) a P0 that does not land stops the exit"
has "priority P0 did not land" "$ERR" "(EMERGPRIO) …naming the write that missed"
hasnt "HELM takeaway" "$LOG" "(EMERGPRIO) …before the route, so it is never claimable at the wrong priority"
unset FAKE_DROP_PRIORITY

export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --emergency --reaction-bead "$R"
eq "$RC" "0" "(EMERGBLK) a blocked emergency's exit succeeds"
before '--priority 0' '^DEFERRED arm' "(EMERGBLK) …P0 written before the arm"
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" "(EMERGBLK) …and the dispatch armed"
has "disposed as blocked (tk-blk1; armed at P0)" "$OUT" "(EMERGBLK) …and the run says the arm is at P0"
unset FAKE_DEPS_JSON

run tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --emergency
eq "$RC" "2" "(EMERGARGS) --emergency beside --assign is refused"
eq "$LOG" "" "(EMERGARGS) …and nothing was written"
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --emergency
eq "$RC" "2" "(EMERGARGS) --emergency on a blocked exit that arms nothing is refused"
run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --emergency
eq "$RC" "2" "(EMERGARGS) close refuses --emergency"
run tk-sub --disposition ruling --reason "r" --takeaway "t" --emergency
eq "$RC" "2" "(EMERGARGS) ruling refuses --emergency"
eq "$LOG" "" "(EMERGARGS) …and nothing was written"
unset FAKE_SHOW_JSON FAKE_GH FAKE_ORIGIN_URL FAKE_RIG_PATH

echo ""
echo "first-reaction-dispose (five exits, reaction-bead): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
