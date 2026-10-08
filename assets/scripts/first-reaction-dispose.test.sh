#!/usr/bin/env bash
# Hermetic tests for first-reaction-dispose.sh — the five exits
# mol-first-reaction's terminal step chooses between. Runs the REAL script
# with a stubbed `gc`, a stubbed gc-helm.sh and a stubbed deferred-dispatch.sh
# (both reached through the tool-override env vars), so no live city, Dolt or
# network is touched. What each block guards is named above it.
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

[ -x "$SCRIPT" ] && ok "first-reaction-dispose.sh present and executable" \
                 || bad "first-reaction-dispose.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- stubs --------------------------------------------------------------------
# One ORDER log across every stub: the disposition record must be written
# before the act, so a run that dies part-way is still auditable.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "bd update")
    printf 'UPDATE %s\n' "$*" >> "$FAKE_LOG"
    # Model read-after-write for gc.recommended_formula so the script's read-back
    # guard can be exercised: apply the set/unset to the state file a later
    # `bd show` reflects. FAKE_DROP_RECO models a silent drop — the update still
    # reports success but the key does not move: =once drops only the first
    # recommendation write (so a retry lands), any other value drops them all.
    _prev=""; _reco_set=""; _reco_unset=""
    for _a in "$@"; do
      case "$_prev" in
        --set-metadata)   case "$_a" in gc.recommended_formula=*) _reco_set="${_a#gc.recommended_formula=}" ;; esac ;;
        --unset-metadata) [ "$_a" = "gc.recommended_formula" ] && _reco_unset=1 ;;
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
    # once the record write has landed: the initial subject read (before any
    # UPDATE) sees the fixture, and every read-back after it returns the non-array
    # error object gc bd show emits for a subject it cannot resolve. This is the
    # read the guard must not mistake for a proven-absent key.
    if [ -n "${FAKE_SHOW_UNREADABLE_AFTER_UPDATE:-}" ] && grep -q '^UPDATE ' "$FAKE_LOG" 2>/dev/null; then
      printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'
      exit 0
    fi
    # Overlay the current gc.recommended_formula state (set by bd update above)
    # onto the fixture, so a read-back sees what the last write actually did.
    _base="${FAKE_SHOW_JSON:-$DEFAULT_SHOW}"
    _reco="$(cat "$FAKE_STATE" 2>/dev/null || printf '')"
    if [ -n "$_reco" ]; then
      printf '%s' "$_base" | jq -c --arg v "$_reco" '.[0].metadata = ((.[0].metadata // {}) + {"gc.recommended_formula": $v})' 2>/dev/null || printf '%s\n' "$_base"
    else
      printf '%s' "$_base" | jq -c '.[0].metadata = ((.[0].metadata // {}) | del(.["gc.recommended_formula"]))' 2>/dev/null || printf '%s\n' "$_base"
    fi ;;
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
    [ -n "${FAKE_SLING_FAILS:-}" ] && exit 1 ;;
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
# Model gc-helm.sh takeaway --release retiring the pour stamp as provenance. The
# shared-state file stands in for gc.execution_routed_to; a run that does not opt
# in (FAKE_EXEC_ROUTED_FILE unset) is unchanged. The arm no longer depends on
# this clear — a plain arm lands whether or not the stamp is set — so the clear
# is hygiene the release owes, not a precondition for the dispatch.
case " $* " in
  *" --release "*) [ -n "${FAKE_EXEC_ROUTED_FILE:-}" ] && [ -z "${FAKE_HELM_KEEPS_STAMP:-}" ] && : > "$FAKE_EXEC_ROUTED_FILE" ;;
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
[ -n "${FAKE_DEFERRED_FAILS:-}" ] && exit 1
# deferred-dispatch.sh arm keys on gc.routed_to and status, NOT on
# gc.execution_routed_to — that stamp is a finished pour's provenance, not a live
# queue. A first-reaction subject carries only the stamp and no gc.routed_to, so
# a plain arm lands whether or not the release cleared the stamp. The stub arms
# unconditionally, which is exactly that behavior.
exit 0
DD
chmod +x "$TMP/deferred"

export PATH="$TMP/bin:$PATH"
export FAKE_LOG="$TMP/log"
export FAKE_STATE="$TMP/reco_state"
# The subject fixture when a test sets no FAKE_SHOW_JSON. Held in a variable
# because a literal `{}` inside a ${var:-default} confuses brace matching and
# yields malformed JSON.
export DEFAULT_SHOW='[{"id":"tk-sub","metadata":{}}]'
export GC_HELM_TOOL="$TMP/helm" GC_DEFERRED_DISPATCH_TOOL="$TMP/deferred" \
       GC_PROACTIVE_TOOL="$TMP/proactive"

# Reset per run, then seed the recommendation state from the fixture so the first
# `bd show` matches FAKE_SHOW_JSON and later writes mutate it from there.
run() {
  : > "$FAKE_LOG"; rm -f "$FAKE_STATE.dropped"
  printf '%s' "${FAKE_SHOW_JSON:-$DEFAULT_SHOW}" \
    | jq -r '(.[0].metadata // {})["gc.recommended_formula"] // ""' > "$FAKE_STATE" 2>/dev/null || : > "$FAKE_STATE"
  RC=0; OUT="$("$SCRIPT" "$@" 2>"$TMP/err")" || RC=$?; ERR="$(cat "$TMP/err")"; LOG="$(cat "$FAKE_LOG")";
}

# ── Usage: refuse before writing ─────────────────────────────────────────────
# Every refusal below happens with an empty log: a disposition that cannot be
# performed must not leave a half-written bead behind.
run tk-sub --disposition actionable --takeaway "t"
eq "$RC" "2" "(ARGS) a disposition with no --reason is refused"
eq "$LOG" "" "(ARGS) …and nothing was written"
has "silent classification" "$ERR" "(ARGS) …and the refusal says why the reason is required"

run tk-sub --disposition sideways --reason "r" --takeaway "t"
eq "$RC" "2" "(ARGS) an unknown disposition is refused"

run tk-sub --disposition actionable --reason "r"
eq "$RC" "2" "(ARGS) a disposition with no --takeaway is refused"

run --disposition actionable --reason "r" --takeaway "t"
eq "$RC" "2" "(ARGS) no bead id is refused"

# ── actionable: the bead is work, so hand it to a pool ───────────────────────
#   (ACT)      the record names the choice, the reason and the target
#   (ACTORDER) the record is written BEFORE the release
#   (ACTROUTE) the release carries the route, so the bead lands in a pool queue
#   (ACTRIG)   the target defaults from GC_RIG, and fails closed without one
run tk-sub --disposition actionable --reason "states a done condition and a branch" \
    --takeaway "routed to the polecat pool" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(ACT) an actionable disposition succeeds"
has "gc.first_reaction=actionable" "$LOG" "(ACT) the choice is recorded on the bead"
has "gc.first_reaction_reason=states a done condition and a branch" "$LOG" "(ACT) …with the reason beside it"
has "gc.first_reaction_target=gc-toolkit/gc-toolkit.polecat" "$LOG" "(ACT) …and what it named"
eq "$(grep -n -m1 '^UPDATE' "$FAKE_LOG" | cut -d: -f1)" "$(( $(grep -n -m1 '^HELM' "$FAKE_LOG" | cut -d: -f1) - 1 ))" \
   "(ACTORDER) the record is written before the act, so a run that dies half-way is still auditable"
has "HELM takeaway tk-sub routed to the polecat pool --by proactive --release --route gc-toolkit/gc-toolkit.polecat" \
    "$LOG" "(ACTROUTE) the release hands the bead to the pool in one call"
# The headline's own disposition. Work handed to a pool is moving, not waiting,
# and the sitting says so where it stamps the sentence — nothing downstream can
# tell a settled headline from a park after the fact.
has "--no-wait" "$LOG" "(ACTROUTE) …and says nothing is waiting on it"
LOG_ACT="$LOG"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --waiting-on tk-other
eq "$RC" "2" "(ACT) actionable refuses the other exits' flags"

# (ACTPOOL) a route to a pool nothing runs is worse than a visit: the bead
# would be open, unassigned and offered to nobody.
has "PROACTIVE deliverable gc-toolkit/gc-toolkit.polecat" "$LOG_ACT" \
    "(ACTPOOL) the exit asks whether the pool can claim before handing over"
export FAKE_POOL_DEAD=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.nosuch
eq "$RC" "2" "(ACTPOOL) a pool that cannot claim refuses the exit"
hasnt "HELM" "$LOG" "(ACTPOOL) …and the bead is not released"
has "address it with --assign" "$ERR" "(ACTPOOL) …and the refusal names the named-agent address before the operator"
has "only when the next move is the operator's" "$ERR" "(ACTPOOL) …keeping the operator's exits for the operator's own move"
unset FAKE_POOL_DEAD

: > "$FAKE_LOG"; RC=0
OUT="$(GC_RIG=gc-toolkit "$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(ACTRIG) with GC_RIG set, the pool target needs no flag"
has "--route gc-toolkit/gc-toolkit.polecat" "$LOG" "(ACTRIG) …and defaults to this rig's polecat pool"

: > "$FAKE_LOG"; RC=0
ERR="$(env -u GC_RIG "$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" 2>&1 >/dev/null)" || RC=$?
eq "$RC" "2" "(ACTRIG) with no GC_RIG and no --route it fails closed"
eq "$(cat "$FAKE_LOG")" "" "(ACTRIG) …and writes nothing"
has "routes to nobody" "$ERR" "(ACTRIG) …and names what a bare target would cost"

# ── actionable --assign: work that is a named agent's own ────────────────────
# A town-repo edit is mechanik's direct edit, and mechanik is a named agent: its
# hook matches the bead's assignee and never reads gc.routed_to, so the exit
# releases the bead TO it as its assignee instead of routing it to a pool.
#   (ACTASSIGN)  the release carries --assign, not --route, and still says
#                nothing waits; the record names the agent
#   (ACTASSIGN)  the exit asks whether the agent's hook would offer the bead,
#                and does not ask the pool question
#   (ASSIGNNO)   an agent that cannot be handed the bead refuses the exit
#   (ASSIGNBOTH) --route and --assign together are refused
#   (ASSIGNRIG)  a named agent needs no GC_RIG to qualify it
run tk-sub --disposition actionable --reason "the remedy is a city.toml edit, mechanik's direct edit" \
    --takeaway "city.toml edit routed to mechanik" --assign gc-toolkit.mechanik
eq "$RC" "0" "(ACTASSIGN) an actionable disposition addressed to a named agent succeeds"
has "gc.first_reaction=actionable" "$LOG" "(ACTASSIGN) the choice is recorded as actionable"
has "gc.first_reaction_target=gc-toolkit.mechanik" "$LOG" "(ACTASSIGN) …naming the agent it went to"
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

: > "$FAKE_LOG"; RC=0
OUT="$("$SCRIPT" tk-sub --disposition actionable --reason "r" --takeaway "t" --assign gc-toolkit.mechanik --dry-run 2>"$TMP/err")" || RC=$?
eq "$RC" "0" "(ASSIGNDRY) a dry run of the --assign exit succeeds"
has "would release tk-sub to named agent gc-toolkit.mechanik" "$OUT" "(ASSIGNDRY) …and names the agent it would hand the bead to"
hasnt "UPDATE" "$(cat "$FAKE_LOG")" "(ASSIGNDRY) …writing nothing"

# ── blocked: the wait is an edge, in one store ───────────────────────────────
#   (BLK)      the release carries the wait as --waiting-on
#   (BLKCROSS) a cross-store blocker is refused with the I1 remedy
#   (BLKSELF)  a bead never waits on itself
#   (BLKNEW)   --blocker files the missing bead and waits on it
#   (BLKDEDUP) --blocker-key reuses the bead a prior reaction filed
#   (BLKEDGE)  an edge that did not land fails the exit, so nothing closes over it
#   (BLKARM)   --then-route arms the dispatch that resumes the work
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "waits on the schema migration" \
    --takeaway "held: schema migration first" --waiting-on tk-blk1
eq "$RC" "0" "(BLK) a blocked disposition succeeds"
has "gc.first_reaction=blocked" "$LOG" "(BLK) the choice is recorded"
has "gc.first_reaction_target=tk-blk1" "$LOG" "(BLK) …naming the bead it waits on"
has "--release --waiting-on tk-blk1" "$LOG" "(BLK) the wait rides the release as an edge"
hasnt "--route" "$LOG" "(BLK) …and a held bead is not also routed"
hasnt "--no-wait" "$LOG" "(BLK) …and the named wait is not also called settled"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on sl-foreign
eq "$RC" "2" "(BLKCROSS) a blocker in another store is refused"
eq "$LOG" "" "(BLKCROSS) …and nothing was written"
has "holds nothing" "$ERR" "(BLKCROSS) …because the edge would report success and hold nothing"
has "demand bead" "$ERR" "(BLKCROSS) …and the refusal names the remedy"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-sub
eq "$RC" "2" "(BLKSELF) a bead cannot wait on itself"

run tk-sub --disposition blocked --reason "r" --takeaway "t"
eq "$RC" "2" "(BLK) blocked with no wait at all is refused"
has "prose about it holds nothing" "$ERR" "(BLK) …and the refusal says why"

export FAKE_NEW_ID=tk-filed FAKE_DEPS_JSON='[{"id":"tk-filed"}]' FAKE_LIST_JSON='[]'
run tk-sub --disposition blocked --reason "nothing tracks the migration yet" \
    --takeaway "held: the migration is now filed" --blocker "Migrate the seed schema" --blocker-key migration
eq "$RC" "0" "(BLKNEW) a wait that is not a bead yet is filed"
has "CREATE bd create -t task --title Migrate the seed schema" "$LOG" "(BLKNEW) …as a bead"
has "gc.blocker_key" "$LOG" "(BLKNEW) …carrying the dedup key"
case "$(grep -c '^CREATE' "$FAKE_LOG")" in
  1) ok "(BLKNEW) …filed in one write, so the key cannot land without the bead" ;;
  *) bad "(BLKNEW) the blocker took more than one create: $LOG" ;;
esac
has "--waiting-on tk-filed" "$LOG" "(BLKNEW) …and the subject waits on it"
run tk-sub --disposition blocked --reason "r" --takeaway "t" \
    --blocker "$(printf 'x%.0s' $(seq 1 501))"
eq "$RC" "2" "(BLKNEW) a blocker title past bd's 500-byte cap is refused here"
has "cap is 500" "$ERR" "(BLKNEW) …by its actual cause, not 'no id returned'"

export FAKE_LIST_JSON='[{"id":"tk-already"}]' FAKE_DEPS_JSON='[{"id":"tk-already"}]'
run tk-sub --disposition blocked --reason "same cause as last time" \
    --takeaway "held: same migration" --blocker "Migrate the seed schema" --blocker-key migration
eq "$RC" "0" "(BLKDEDUP) a repeat of one cause succeeds"
hasnt "CREATE" "$LOG" "(BLKDEDUP) …and files no second bead"
has "--waiting-on tk-already" "$LOG" "(BLKDEDUP) …it waits on the one already filed"
unset FAKE_LIST_JSON FAKE_NEW_ID

export FAKE_DEPS_JSON='[]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1
eq "$RC" "4" "(BLKEDGE) a dropped edge fails the verb — the bead is recorded as waiting and nothing holds it"
has "not held by tk-blk1" "$ERR" "(BLKEDGE) …the missing edge is named"
has "gc bd dep add tk-sub tk-blk1 -t blocks" "$ERR" "(BLKEDGE) …with the repair spelled out"
has "parked on prose alone" "$ERR" "(BLKEDGE) …and the failure says what it costs"
hasnt "disposed as blocked" "$OUT" "(BLKEDGE) …and the run does not report a disposition"

# A partial landing is still a failure: one edge holds, the other does not, and
# the record names both.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --waiting-on tk-blk2
eq "$RC" "4" "(BLKEDGE) one of two edges landing is still a failed exit"
has "not held by tk-blk2" "$ERR" "(BLKEDGE) …naming only the one that missed"
hasnt "not held by tk-blk1" "$ERR" "(BLKEDGE) …and not the one that landed"

# The arm is downstream of the hold: no edge, no deferred dispatch.
export FAKE_DEPS_JSON='[]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat
eq "$RC" "4" "(BLKEDGE) a dropped edge fails before the deferred dispatch is armed"
hasnt "DEFERRED arm" "$LOG" "(BLKEDGE) …so nothing is armed on a wait that does not exist"

# A real first-reaction subject carries the pour stamp gc.execution_routed_to,
# set by the sling that put it in the pool. The blocked exit releases it
# (gc-helm.sh --release retires that stamp as provenance) and arms a PLAIN
# deferred dispatch. deferred-dispatch's arm keys on gc.routed_to, not the
# execution stamp, and the subject carries no gc.routed_to, so the arm lands
# whether or not the release cleared the stamp. The stubs model that, so the arm
# is exercised against the real guard rather than a fixture no sling ever poured.
export FAKE_EXEC_ROUTED_FILE="$TMP/exec_routed"
printf 'gc-toolkit/gc-toolkit.proactive' > "$FAKE_EXEC_ROUTED_FILE"
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.proactive"}}]'
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" \
    "(BLKARM) --then-route arms the dispatch for when the wait lifts"
hasnt "--sling-arg" "$LOG" \
    "(BLKARM) …a plain arm, no --on — reconcile slings it even with the pour stamp set"
has "armed the dispatch to gc-toolkit/gc-toolkit.polecat" "$ERR" \
    "(BLKARM) …and the arm lands"

# Control: a release that leaves the pour stamp set still lets the plain arm land.
# The coupled surface is gc-helm.sh takeaway --release: it WARNS on a surviving
# gc.execution_routed_to and returns 0 rather than failing, because no arm or
# reconcile guard reads that stamp. The stub returns 0 with the stamp still set to
# model exactly that path, so this control exercises the real release, not a state
# the real flow cannot reach — and dispose runs on to arm the plain dispatch.
printf 'gc-toolkit/gc-toolkit.proactive' > "$FAKE_EXEC_ROUTED_FILE"
export FAKE_HELM_KEEPS_STAMP=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(BLKARM) a surviving pour stamp does not fail the disposition"
has "armed the dispatch to gc-toolkit/gc-toolkit.polecat" "$ERR" \
    "(BLKARM) a stamp left set does NOT refuse the plain arm — provenance, not a live queue"
unset FAKE_HELM_KEEPS_STAMP

# Contract: the arm is downstream of a release that SUCCEEDED. A genuine release
# failure — not a cosmetic surviving stamp, but gc-helm exiting non-zero because a
# write it owed did not land — dies before the arm, so a bead whose disposition
# only half-wrote is never armed to auto-resume from that state. This is the
# release-then-arm coupling; the surviving-stamp control above proves a cosmetic
# stamp is NOT such a failure.
export FAKE_HELM_FAILS=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat
eq "$RC" "4" "(BLKARM) a genuine gc-helm release failure fails the disposition"
hasnt "DEFERRED arm" "$LOG" "(BLKARM) …and nothing is armed after a release that did not land"
unset FAKE_HELM_FAILS FAKE_EXEC_ROUTED_FILE FAKE_SHOW_JSON

# (BLKROUTE) --then-route is held to the SAME roster test as --route: a target no
# pool runs is refused before anything is written, not silently armed to fail
# every reconcile pass. Its parse check only tests for a "/", which a copied
# `<rig>/<rig>.polecat` placeholder passes, so the roster probe is what catches it.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{}}]'
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
export FAKE_POOL_DEAD=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.nosuchpool
eq "$RC" "2" "(BLKROUTE) --then-route to a pool nothing runs is refused"
has "PROACTIVE deliverable gc-toolkit/gc-toolkit.nosuchpool" "$LOG" \
    "(BLKROUTE) …the exit asks whether that pool can claim before arming"
hasnt "DEFERRED arm" "$LOG" "(BLKROUTE) …and nothing is armed to a target that would fail every reconcile pass"
unset FAKE_POOL_DEAD FAKE_SHOW_JSON FAKE_DEPS_JSON

# (BLKASSIGN) a town-repo edit that must wait on a rig change is held on that
# change AND assigned to mechanik in the same release. An assigned bead reaches
# its agent's hook only once bd reports it ready, so the edge is the gate and
# nothing is armed: a deferred dispatch slings a pool, and a named agent is not
# one.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "the comment can change only once the order lands" \
    --takeaway "held: city.toml comment waits on the order" --waiting-on tk-blk1 --then-assign gc-toolkit.mechanik
eq "$RC" "0" "(BLKASSIGN) a blocked disposition assigned to a named agent succeeds"
has "gc.first_reaction_target=tk-blk1" "$LOG" "(BLKASSIGN) the record still names the wait"
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

export FAKE_AGENT_GONE=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --then-assign gc-toolkit/gc-toolkit.witness
eq "$RC" "2" "(BLKASSIGN) a --then-assign agent that cannot be handed the bead is refused"
hasnt "HELM" "$LOG" "(BLKASSIGN) …and the bead is not released"
unset FAKE_AGENT_GONE FAKE_DEPS_JSON

# ── ruling: the human gate is the wait, filed by the exit itself ─────────────
#   (RUL)      the exit files the gate through gc-helm.sh demand, the takeaway
#              as its question, and holds the subject on it
#   (RULTOPIC) the gate is filed under the topic first-reaction
#   (RULORDER) record, then gate, then release: the gate is the act
#   (RULGATE)  a gate that did not file, or that demand did not name, fails
#              the exit before the release, and the record stands for a re-run
#   (RULEDGE)  a hold that did not land fails the exit
#   (RULVISIT) --visit holds the subject on a visit the caller filed, no gate
# The gate is the escalation's state; gate-visit-sweep files the visit that
# resolves it, so the exit files no visit. The FAKE dep list answers with the
# gate so the hold verification passes.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default"
eq "$RC" "0" "(RUL) a ruling disposition succeeds"
has "HELM demand tk-sub needs a ruling: which default --by proactive --topic first-reaction --body" "$LOG" \
   "(RUL) it files the human gate, the takeaway as the gate's question"
# gc-helm.sh demand keeps one open gate per gated bead and topic. With no topic
# it matches on the subject alone: it refreshes a converse sitting's lone demand
# on the subject in place, overwriting the question that sitting holds, and stops
# on a subject that carries two. The reaction's own topic files beside them.
has "--topic first-reaction" "$(grep '^HELM demand' "$FAKE_LOG")" \
   "(RULTOPIC) the gate is filed under the first reaction's own topic"
# The body spans lines, so read the demand call up to the release that follows
# it; the record UPDATE that also carries the reason sits before this range.
has "the trade-off is the operator's" "$(sed -n '/^HELM demand/,/^HELM takeaway/p' "$FAKE_LOG")" \
   "(RUL) …with the reason in the gate's body"
has "gc.first_reaction_target=tk-gate1" "$LOG" "(RUL) the gate it filed is recorded"
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
REC_L=$(grep -n -m1 'gc.first_reaction=ruling' "$FAKE_LOG" | cut -d: -f1)
DEM_L=$(grep -n -m1 '^HELM demand' "$FAKE_LOG" | cut -d: -f1)
TAK_L=$(grep -n -m1 '^HELM takeaway' "$FAKE_LOG" | cut -d: -f1)
{ [ -n "$REC_L" ] && [ -n "$DEM_L" ] && [ -n "$TAK_L" ] && [ "$REC_L" -lt "$DEM_L" ] && [ "$DEM_L" -lt "$TAK_L" ]; } \
   && ok "(RULORDER) the record, then the gate, then the release" \
   || bad "(RULORDER) the record, then the gate, then the release (record=$REC_L demand=$DEM_L takeaway=$TAK_L)"

export FAKE_DEMAND_FAILS=1
run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "4" "(RULGATE) a gate that did not file fails the exit"
has "gc.first_reaction=ruling" "$LOG" "(RULGATE) …the record was written first and stands"
hasnt "HELM takeaway" "$LOG" "(RULGATE) …and the subject is not released onto a gate that does not exist"
has "re-run this command" "$ERR" "(RULGATE) …and the failure names the retry"
unset FAKE_DEMAND_FAILS

export FAKE_DEMAND_NOID=1
run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "4" "(RULGATE) a demand that names no gate fails the exit"
hasnt "HELM takeaway" "$LOG" "(RULGATE) …before the release"
unset FAKE_DEMAND_NOID

export FAKE_DEPS_JSON='[]'
run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "4" "(RULEDGE) a gate edge that is not on the subject fails the exit"
has "not held by tk-gate1" "$ERR" "(RULEDGE) …naming the gate it is not held by"

export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --visit tk-visit1
eq "$RC" "0" "(RULVISIT) a ruling held on a caller's visit succeeds"
hasnt "HELM demand" "$LOG" "(RULVISIT) …and files no gate"
has "gc.first_reaction_target=tk-visit1" "$LOG" "(RULVISIT) …the visit is recorded"
has "--waiting-on tk-visit1" "$LOG" "(RULVISIT) …and holds the subject"

run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit sl-foreign
eq "$RC" "2" "(RULVISIT) a visit in another store is refused"
eq "$LOG" "" "(RULVISIT) …and nothing was written"

: > "$FAKE_LOG"; RC=0
OUT="$("$SCRIPT" tk-sub --disposition ruling --reason "r" --takeaway "t" --dry-run 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(RULDRY) a dry run succeeds"
has "would file a human gate on tk-sub" "$OUT" "(RULDRY) …saying it would file the gate"
hasnt "HELM" "$LOG" "(RULDRY) …and files nothing"
hasnt "UPDATE" "$LOG" "(RULDRY) …and records nothing"

# ── recommend: the gate's visit offers Accept ────────────────────────────────
# recommend names a determinable action (converse/operator authority) and stamps
# gc.recommended_formula on the subject. That stamp is the whole difference
# between a plain Discuss-only ruling visit and a recommendation visit the
# operator can Accept, and it rides the record write — before the act — so a
# half-written recommendation is still visible. recommend files and holds on the
# same human gate ruling does, and the stamp lands before the gate is filed, so
# the visit gate-visit-sweep files for the gate offers Accept from the start.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition recommend --reason "retire the PR, supersede its anchor — operator authority" \
    --takeaway "recommend: retire PR + supersede anchor; execute via mol-x — Accept or Discuss" \
    --recommended-formula mol-x
eq "$RC" "0" "(RECO) a recommend disposition succeeds"
has "gc.recommended_formula=mol-x" "$LOG" "(RECO) the recommended formula is stamped on the subject"
has "gc.first_reaction=recommend" "$LOG" "(RECO) …alongside the disposition record"
has "HELM demand tk-sub recommend: retire PR + supersede anchor; execute via mol-x — Accept or Discuss" "$LOG" \
   "(RECO) …it files the human gate, as ruling does"
has "--topic first-reaction" "$(grep '^HELM demand' "$FAKE_LOG")" \
   "(RECO) …under the first reaction's own topic"
has "--waiting-on tk-gate1" "$LOG" "(RECO) …and the gate holds the subject, the ruling shape"
RECO_UL=$(grep -n -m1 '^UPDATE' "$FAKE_LOG" | cut -d: -f1)
RECO_DL=$(grep -n -m1 '^HELM demand' "$FAKE_LOG" | cut -d: -f1)
RECO_HL=$(grep -n -m1 '^HELM takeaway' "$FAKE_LOG" | cut -d: -f1)
{ [ -n "$RECO_UL" ] && [ -n "$RECO_DL" ] && [ -n "$RECO_HL" ] && [ "$RECO_UL" -lt "$RECO_DL" ] && [ "$RECO_DL" -lt "$RECO_HL" ]; } \
   && ok "(RECO) …in the record write, before the gate and the release" \
   || bad "(RECO) …in the record write, before the gate and the release (UPDATE=$RECO_UL demand=$RECO_DL takeaway=$RECO_HL)"

# recommend REQUIRES the flag it exists to carry: no --recommended-formula is a
# usage error naming ruling as the flagless alternative.
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via <mol> — Accept or Discuss" --visit tk-visit1
eq "$RC" "2" "(RECO) recommend with no --recommended-formula is refused"
eq "$LOG" "" "(RECO) …and writes nothing"
has "is --disposition ruling" "$ERR" "(RECO) …naming ruling as the flagless alternative"

# --visit holds a recommend on a visit the caller filed, the way it does a ruling.
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" --visit tk-visit1 --recommended-formula mol-x
eq "$RC" "0" "(RECO) a recommend held on a caller's visit succeeds"
hasnt "HELM demand" "$LOG" "(RECO) …and files no gate"
has "--waiting-on tk-visit1" "$LOG" "(RECO) …the visit holds the subject"

# A recommended formula that does not resolve is a usage error, refused before the
# record: Accept slings this exact name, so a typo would stamp a live
# gc.recommended_formula and render an 'accept ▸' that fails at gc sling on every
# click. Validated the way --route/--then-route are against the roster.
export FAKE_FORMULA_MISSING="mol-typo"
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-typo — Accept or Discuss" \
    --visit tk-visit1 --recommended-formula mol-typo
eq "$RC" "2" "(RECO) a --recommended-formula that does not resolve is refused (usage error)"
hasnt "UPDATE" "$LOG" "(RECO) …nothing is recorded on an unresolved formula"
hasnt "HELM" "$LOG" "(RECO) …and the act does not run"
has "does not resolve to a formula" "$ERR" "(RECO) …the message names the unresolved formula"
unset FAKE_FORMULA_MISSING

# ── ruling rejects a recommendation: it is Discuss-only ───────────────────────
# A ruling is the operator's judgment with no worker-runnable action, so it takes
# no --recommended-formula; the refusal names recommend as the disposition that
# carries one.
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --visit tk-visit1 --recommended-formula mol-x
eq "$RC" "2" "(RECO) ruling refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
has "use --disposition recommend" "$ERR" "(RECO) …pointing at the disposition that carries a recommendation"

# A plain ruling stamps nothing, so the visit stays Discuss-only (no Accept).
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --visit tk-visit1
eq "$RC" "0" "(RECO) a Discuss-only ruling succeeds"
hasnt "gc.recommended_formula" "$LOG" "(RECO) …and stamps no recommendation, so the visit offers no Accept"

# A partial record can already carry a recommendation a prior recommend stamped:
# the record was written, the act did not land (no gc.proactive_reaction=1), and
# this retry resumes it. A ruling retry names no recommendation and clears that
# stale stamp in the record write, so the visit never offers Accept for an action
# the current disposition did not recommend.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.first_reaction":"recommend","gc.recommended_formula":"mol-old"}}]'
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --visit tk-visit1
eq "$RC" "0" "(RECO) a ruling retry over a partial recommendation succeeds"
has "--unset-metadata gc.recommended_formula" "$LOG" "(RECO) …and clears the stale recommendation the prior recommend left"
hasnt "gc.recommended_formula=" "$LOG" "(RECO) …stamping no new one, so the record states the current disposition"

# The same partial record retried as a recommend with a different formula replaces
# the stale one rather than clearing it — the record always states the current
# recommendation, whichever direction it moves.
run tk-sub --disposition recommend --reason "the newer mol is the right execution" \
    --takeaway "recommend: execute via mol-new — Accept or Discuss" \
    --visit tk-visit1 --recommended-formula mol-new
eq "$RC" "0" "(RECO) a retry that re-recommends succeeds"
has "gc.recommended_formula=mol-new" "$LOG" "(RECO) …and the record carries the new recommendation"
hasnt "--unset-metadata gc.recommended_formula" "$LOG" "(RECO) …with no stale-clear, because the recommend names one"
unset FAKE_SHOW_JSON

# ── The recommendation must land before the act (read-back guard) ─────────────
# gc.recommended_formula is presence-sensitive downstream, so a silently dropped
# write is a wrong operator affordance, not a cosmetic miss. The bulk record
# write reports success without proving this one key moved, so the exit reads it
# back, retries the lone set/unset once, and refuses before the act if it is
# still wrong — the record stands, so the command re-runs.
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'

# A set that silently drops and never recovers: the act is withheld, so nothing
# files a recommendation visit the operator could only Discuss.
export FAKE_DROP_RECO=1
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" \
    --visit tk-visit1 --recommended-formula mol-x
eq "$RC" "4" "(RECOGUARD) a silently dropped recommendation set refuses the exit"
hasnt "HELM" "$LOG" "(RECOGUARD) …the act is withheld, so no Discuss-only visit is filed"
has "did not land" "$ERR" "(RECOGUARD) …and the refusal names the key that did not land"
# The gate brings the visit, so the guard must refuse before the gate is filed:
# a gate filed over a dropped recommendation gets a visit that offers only
# Discuss.
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" --recommended-formula mol-x
eq "$RC" "4" "(RECOGUARD) the same drop on the gate form refuses the exit"
hasnt "HELM demand" "$LOG" "(RECOGUARD) …before the gate is filed, so no visit can offer only Discuss"
unset FAKE_DROP_RECO

# The same drop, but the lone retry lands it: the act proceeds.
export FAKE_DROP_RECO=once
run tk-sub --disposition recommend --reason "operator authority" \
    --takeaway "recommend: execute via mol-x — Accept or Discuss" \
    --visit tk-visit1 --recommended-formula mol-x
eq "$RC" "0" "(RECOGUARD) a set that lands on the retry lets the act proceed"
has "HELM takeaway tk-sub" "$LOG" "(RECOGUARD) …the act runs once the recommendation is confirmed"
unset FAKE_DROP_RECO

# A stale-clear that silently drops and never recovers: the act is withheld, so a
# Discuss-only retry never leaves a superseded Accept executable.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.first_reaction":"recommend","gc.recommended_formula":"mol-old"}}]'
export FAKE_DROP_RECO=1
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --visit tk-visit1
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
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.first_reaction":"recommend","gc.recommended_formula":"mol-old"}}]'
export FAKE_SHOW_UNREADABLE_AFTER_UPDATE=1
run tk-sub --disposition ruling --reason "on reflection this is a plain discussion" \
    --takeaway "needs a ruling: which default" --visit tk-visit1
eq "$RC" "4" "(RECOGUARD) an unreadable stale-clear read-back refuses the exit"
hasnt "HELM" "$LOG" "(RECOGUARD) …the act is withheld, so a stale Accept cannot slip through an unreadable read"
has "did not clear" "$ERR" "(RECOGUARD) …and the refusal names the key it could not prove cleared"
unset FAKE_SHOW_UNREADABLE_AFTER_UPDATE FAKE_SHOW_JSON  # leave FAKE_DEPS_JSON for later ruling tests

# --recommended-formula belongs to the recommend exit only: actionable, blocked,
# and close route, hold, or close the bead, and none gates a visit the operator
# Accepts — so each refuses the flag (ruling's refusal is tested above).
run tk-sub --disposition actionable --reason "r" --takeaway "t" \
    --route gc-toolkit/gc-toolkit.polecat --recommended-formula mol-x
eq "$RC" "2" "(RECO) actionable refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --recommended-formula mol-x
eq "$RC" "2" "(RECO) blocked refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"
run tk-sub --disposition close --reason "r" --takeaway "t" \
    --route gc-toolkit/gc-toolkit.polecat --recommended-formula mol-x
eq "$RC" "2" "(RECO) close refuses --recommended-formula"
eq "$LOG" "" "(RECO) …and writes nothing"

# ── Origin does not decide the exit ──────────────────────────────────────────
# gc-visit-open stamps gc.origin=operator on a topic a human typed, but the
# script no longer forces such a bead to the ruling exit: an operator capture is
# triaged on its merits, so every exit is open to it. The guardrail that a fork
# or an irreversible action still goes to a human lives in the reacting agent's
# rubric, not here.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.origin":"operator"}}]'
export FAKE_DEPS_JSON='[{"id":"tk-blk1"},{"id":"tk-visit1"}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(ORIGIN) an operator-origin subject may take the actionable exit"
has "HELM takeaway tk-sub" "$LOG" "(ORIGIN) …and is routed like any other bead"
hasnt "the visit IS the answer" "$ERR" "(ORIGIN) …with no operator-origin refusal"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1
eq "$RC" "0" "(ORIGIN) …the blocked exit too"

run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1
eq "$RC" "0" "(ORIGIN) …and the ruling exit, when the agent chooses it"
# Leave FAKE_DEPS_JSON holding tk-visit1 for the ruling-exit checks downstream.
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
unset FAKE_SHOW_JSON

# ── close: hand the bead to a validating closer, never close here ────────────
# The reaction concluded there is nothing to do. It does not close the bead — a
# cheap model must not have the last word — it hands the bead to a capable pool
# carrying mol-validate-close, which re-checks the call and closes or escalates.
# Called by hand on a bead with no live workflow (no --after-workflow), the
# closer is slung now; run from inside a live reaction (--after-workflow), it is
# deferred (held on the reaction root, dispatch armed) so it is the bead's sole
# workflow — that path is covered further below.
# GC_RIG is set on every run: the proactive pool is rig-scoped, and it is what
# both defaults the pool target and pins the sling with --rig.
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "already fixed, nothing to merge" --takeaway "close: fixed in #123"
eq "$RC" "0" "(CLOSE) the close exit succeeds"
has "UPDATE bd update tk-sub --set-metadata gc.first_reaction=close" "$LOG" "(CLOSE) it records the disposition first"
has "SLING sling --rig gc-toolkit gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close" "$LOG" \
   "(CLOSE) …then slings the closer formula to \$GC_RIG/gc-toolkit.polecat, rig-pinned"
has "gc.proactive_reaction=1" "$LOG" "(CLOSE) …and stamps the landed marker so a re-offer does not sling a second closer"
hasnt "CLOSE bd close" "$LOG" "(CLOSE) …and never closes the bead itself"
hasnt "--release" "$LOG" "(CLOSE) …and does not release it to a pool as a raw bead"

# The record precedes the act: the record UPDATE lands on an earlier log line
# than the SLING, so a run that dies mid-way is still auditable.
REC_LINE=$(printf '%s\n' "$LOG" | grep -n 'gc.first_reaction=close' | head -1 | cut -d: -f1)
SLING_LINE=$(printf '%s\n' "$LOG" | grep -n 'SLING' | head -1 | cut -d: -f1)
{ [ -n "$REC_LINE" ] && [ -n "$SLING_LINE" ] && [ "$REC_LINE" -lt "$SLING_LINE" ]; } \
  && ok "(CLOSE) the record is written before the sling" \
  || bad "(CLOSE) the record is written before the sling (rec=$REC_LINE sling=$SLING_LINE)"

# With no GC_RIG, an explicit --route still slings — and pins nothing.
: > "$FAKE_LOG"; RC=0
OUT="$(env -u GC_RIG "$SCRIPT" tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat 2>"$TMP/err")" || RC=$?
LOG="$(cat "$FAKE_LOG")"
eq "$RC" "0" "(CLOSE) with no GC_RIG, an explicit --route still slings"
has "SLING sling gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close" "$LOG" "(CLOSE) …with no --rig pin"

# An operator-origin subject may take the close exit like any other.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.origin":"operator"}}]'
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(CLOSE) an operator-origin subject may be routed to the closer"
unset FAKE_SHOW_JSON

# The closer must be able to claim, or the bead is routed to nobody — same
# roster gate the actionable exit uses, same fallback.
FAKE_POOL_DEAD=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "2" "(CLOSE) a closer pool that cannot claim is refused"
has "Put it to the operator instead" "$ERR" "(CLOSE) …and the refusal names the exit that reaches a human"
hasnt "SLING" "$LOG" "(CLOSE) …and nothing is slung"
unset FAKE_POOL_DEAD

# A failed sling leaves the record and refers to the cause; the landed marker is
# NOT stamped, so the documented re-run resumes rather than double-slinging.
FAKE_SLING_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "4" "(CLOSE) a failed sling is a runtime failure"
has "gc.first_reaction=close" "$LOG" "(CLOSE) …the record was written first and stands"
hasnt "gc.proactive_reaction=1" "$LOG" "(CLOSE) …and the landed marker is not stamped"
unset FAKE_SLING_FAILS

# ── close --after-workflow: DEFER behind the reaction, never a second workflow ─
# Run from inside a live reaction, the closer must be the bead's SOLE dispatch
# surface (formula-spec-v2 §3), so the close exit does NOT sling now: it holds
# the bead on the reaction's own workflow root and arms a deferred dispatch, and
# the deferred-dispatch reconcile pass slings mol-validate-close once that root
# closes. The arm carries the exact sling reconcile replays, so the closer
# FORMULA is asserted here rather than a bare "something was slung" — the gap the
# review flagged in the stubbed immediate-sling path.
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "already fixed" --takeaway "close: fixed in #123" --after-workflow tk-root
eq "$RC" "0" "(CLOSEDEFER) the deferred close exit succeeds"
has "UPDATE bd update tk-sub --set-metadata gc.first_reaction=close" "$LOG" "(CLOSEDEFER) it records the disposition first"
has "DEP bd dep add tk-sub tk-root -t blocks" "$LOG" "(CLOSEDEFER) …holds the bead on the reaction root so reconcile waits for it to close"
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat --sling-arg --on --sling-arg mol-validate-close" "$LOG" \
   "(CLOSEDEFER) …and arms a deferred dispatch carrying the exact --on mol-validate-close sling reconcile replays"
hasnt "SLING" "$LOG" "(CLOSEDEFER) …and slings nothing now — the reconcile pass does it once the reaction closes"
has "gc.proactive_reaction=1" "$LOG" "(CLOSEDEFER) …and stamps the landed marker so a re-offer does not queue a second closer"
hasnt "CLOSE bd close" "$LOG" "(CLOSEDEFER) …and never closes the bead itself"

# The record precedes the act here too: the record lands before the arm.
REC_LINE=$(printf '%s\n' "$LOG" | grep -n 'gc.first_reaction=close' | head -1 | cut -d: -f1)
ARM_LINE=$(printf '%s\n' "$LOG" | grep -n 'DEFERRED arm' | head -1 | cut -d: -f1)
{ [ -n "$REC_LINE" ] && [ -n "$ARM_LINE" ] && [ "$REC_LINE" -lt "$ARM_LINE" ]; } \
  && ok "(CLOSEDEFER) the record is written before the arm" \
  || bad "(CLOSEDEFER) the record is written before the arm (rec=$REC_LINE arm=$ARM_LINE)"

# The gate is a REQUIRED write: reconcile dispatches from `bd list --ready`, so a
# hold that does not land leaves the bead reading ready and mol-validate-close
# would sling beside the still-live reaction — the two-live-surfaces shape this
# exit prevents. So a failed hold fails closed: the exit refuses to arm, the
# disposition record stands, and the landed marker is left unstamped so the
# documented re-run resumes.
FAKE_DEP_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --after-workflow tk-root
eq "$RC" "4" "(CLOSEDEFER) a hold that did not land fails the exit closed"
has "gc.first_reaction=close" "$LOG" "(CLOSEDEFER) …the disposition record was written first and stands"
hasnt "DEFERRED arm" "$LOG" "(CLOSEDEFER) …and the ungated dispatch is NOT armed"
hasnt "gc.proactive_reaction=1" "$LOG" "(CLOSEDEFER) …and the landed marker is not stamped"
unset FAKE_DEP_FAILS

# An arm that fails to record IS a runtime failure: no closer would be
# dispatched, so the documented re-run resumes (the landed marker is unstamped).
FAKE_DEFERRED_FAILS=1 GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --after-workflow tk-root
eq "$RC" "4" "(CLOSEDEFER) a failed arm is a runtime failure"
has "gc.first_reaction=close" "$LOG" "(CLOSEDEFER) …the record was written first and stands"
hasnt "gc.proactive_reaction=1" "$LOG" "(CLOSEDEFER) …and the landed marker is not stamped"
unset FAKE_DEFERRED_FAILS

# --after-workflow belongs to close only, and must be same-store as the subject.
run tk-sub --disposition actionable --reason "r" --takeaway "t" --after-workflow tk-root
eq "$RC" "2" "(CLOSEDEFER) --after-workflow is refused on a non-close exit"
GC_RIG=gc-toolkit run tk-sub --disposition close --reason "r" --takeaway "t" --after-workflow zz-root
eq "$RC" "2" "(CLOSEDEFER) a cross-store --after-workflow is refused (the hold would hold nothing)"

# ── A LANDED first reaction refuses a second dispose ─────────────────────────
# gc-helm.sh takeaway --release stamps gc.proactive_reaction=1 in the write that
# parks the subject (reopen, unassign, route), so that stamp proves the release
# LANDED. A re-offered advance-and-drain that runs this again on a landed
# reaction would re-release a bead a worker has since claimed, so the guard
# refuses on that stamp and names the prior reaction. It sits ahead of the
# disposition switch, so it guards every exit.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.first_reaction":"actionable","gc.proactive_reaction":"1","gc.first_reaction_at":"2026-09-03T04:45:05Z","gc.first_reaction_target":"gc-toolkit/gc-toolkit.polecat"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "2" "(REACTED) a subject already carrying a first reaction refuses a second dispose"
hasnt "UPDATE" "$LOG" "(REACTED) …and re-writes no record"
hasnt "HELM" "$LOG" "(REACTED) …and does not re-release the bead"
has "already carries a first reaction" "$ERR" "(REACTED) …and the refusal says so"
has "gc.first_reaction=actionable" "$ERR" "(REACTED) …naming the prior disposition"
has "at 2026-09-03T04:45:05Z" "$ERR" "(REACTED) …its timestamp"
has "-> gc-toolkit/gc-toolkit.polecat" "$ERR" "(REACTED) …and its target"

# takeaway --release reopens the bead on every exit, so the ruling exit is
# re-released just the same and the guard covers it too — ahead of the gate, so
# a re-offered run files nothing.
run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1
eq "$RC" "2" "(REACTED) …the ruling exit too"
hasnt "HELM" "$LOG" "(REACTED) …with no re-release"
run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "2" "(REACTED) …and the gate form of the ruling exit"
hasnt "HELM demand" "$LOG" "(REACTED) …which files no second gate"

# gc.proactive_reaction=1 alone (the record stamps absent) still proves the
# release landed, so a second dispose is refused.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.proactive_reaction":"1"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "2" "(REACTED) gc.proactive_reaction=1 alone also refuses a second dispose"

# bd stores the release's `--set-metadata gc.proactive_reaction=1` as the JSON
# number 1, so the refusal must read the number the same as the string.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.first_reaction":"ruling","gc.proactive_reaction":1}}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1
eq "$RC" "2" "(REACTED) the number form bd stores refuses a second dispose too"
hasnt "HELM" "$LOG" "(REACTED) …with no re-release"
has "gc.first_reaction=ruling" "$ERR" "(REACTED) …naming the prior disposition"

# Positive finding only: an unreadable bead is not evidence of a prior reaction.
export FAKE_SHOW_JSON='not json'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(REACTED) an unreadable bead is not evidence of a prior reaction"
unset FAKE_SHOW_JSON

# ── A PARTIAL record resumes — it does not block the retry ────────────────────
# The record is written BEFORE the act, so a bead can carry gc.first_reaction
# while the release never landed (gc-helm.sh failed, or a guard fired after the
# record). Only gc.proactive_reaction=1 — which takeaway --release stamps as it
# parks — proves the act landed, so the guard keys on it, not on the pre-act
# record: a partial resumes and re-attempts the act, which is the retry the die
# messages promise.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.first_reaction":"actionable","gc.first_reaction_at":"2026-09-03T04:45:05Z","gc.first_reaction_target":"gc-toolkit/gc-toolkit.polecat"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(RESUME) a partial record with no gc.proactive_reaction resumes rather than refusing"
has "HELM takeaway tk-sub" "$LOG" "(RESUME) …and re-attempts the act"
has "the prior act did not land" "$ERR" "(RESUME) …announcing the resume"
# The same partial on the ruling exit resumes too — the guard is ahead of the switch.
run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1
eq "$RC" "0" "(RESUME) …and every exit resumes, not just actionable"
has "HELM takeaway tk-sub" "$LOG" "(RESUME) …the ruling act is re-attempted"
# A partial whose gate already filed resumes through demand again, under the
# same topic, which refreshes the gate the first run filed instead of filing a
# second.
export FAKE_DEPS_JSON='[{"id":"tk-gate1"}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "0" "(RESUME) the gate form resumes"
has "HELM demand tk-sub" "$LOG" "(RESUME) …asking demand for the subject's gate again"
has "--topic first-reaction" "$(grep '^HELM demand' "$FAKE_LOG")" \
   "(RESUME) …under the topic the first run filed it under"
has "HELM takeaway tk-sub" "$LOG" "(RESUME) …and re-attempting the release"
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
unset FAKE_SHOW_JSON

# ── The store is pinned to the subject's own rig ─────────────────────────────
# A blocker filed into another store makes the hold a cross-store edge, which
# reports success and holds nothing — and this runs from a worktree where an
# unpinned up-walk finds the wrong ledger.
mkdir -p "$TMP/rig/.beads"
export FAKE_RIG_PATH="$TMP/rig" FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat
has "--db $TMP/rig/.beads" "$LOG" "(PIN) the subject's own store is passed to every bead write"
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat --reason first reaction: r --db $TMP/rig/.beads" \
    "$LOG" "(PIN) …and to the deferred dispatch it arms"
unset FAKE_RIG_PATH

# ── The invariant that outranks all three ────────────────────────────────────
# A first reaction advances the bead; it never finishes it.
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
hasnt "CLOSE" "$LOG" "(NEVERCLOSE) no exit closes the work bead"
grep -q 'status=closed' "$SCRIPT" && bad "(NEVERCLOSE) the script can set a closed status" \
                                 || ok "(NEVERCLOSE) …and the script has no close path at all"

# ── A failed act leaves the record and refers to the cause ───────────────────
# gc-helm.sh exits non-zero for a release that did not write AND for a release
# whose route would not stamp, and only it knows which — so this refers to its
# message rather than asserting a state it cannot see.
export FAKE_HELM_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "4" "(HELMFAIL) a failed release is a runtime failure"
has "gc.first_reaction=actionable" "$LOG" "(HELMFAIL) …the record was written first and stands"
has "what landed and what did not" "$ERR" "(HELMFAIL) …and the failure refers to the cause gc-helm.sh named"
hasnt "disposed as actionable" "$OUT" "(HELMFAIL) …and nothing reports a disposition"
unset FAKE_HELM_FAILS

echo ""
echo "first-reaction-dispose (five exits, one record): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
