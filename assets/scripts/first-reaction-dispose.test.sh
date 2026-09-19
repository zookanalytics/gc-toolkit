#!/usr/bin/env bash
# Hermetic tests for first-reaction-dispose.sh — the four exits
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
  "bd update") printf 'UPDATE %s\n' "$*" >> "$FAKE_LOG" ;;
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
    printf '%s\n' "${FAKE_SHOW_JSON:-[{\"id\":\"tk-sub\",\"metadata\":{}}]}" ;;
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
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

cat > "$TMP/helm" <<'HELM'
#!/usr/bin/env bash
printf 'HELM %s\n' "$*" >> "$FAKE_LOG"
[ -n "${FAKE_HELM_FAILS:-}" ] && exit 4
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
export GC_HELM_TOOL="$TMP/helm" GC_DEFERRED_DISPATCH_TOOL="$TMP/deferred" \
       GC_PROACTIVE_TOOL="$TMP/proactive"

run() { : > "$FAKE_LOG"; RC=0; OUT="$("$SCRIPT" "$@" 2>"$TMP/err")" || RC=$?; ERR="$(cat "$TMP/err")"; LOG="$(cat "$FAKE_LOG")"; }

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
has "File the visit instead" "$ERR" "(ACTPOOL) …and the refusal names the exit that does work"
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

# ── ruling: the visit is the wait, named as a blocks edge on the subject ─────
# The visit re-asks the question, so the subject waits on it: the ruling exit
# passes --waiting-on <visit>, and the edge is verified to have landed the way
# the blocked exit's is. The FAKE dep list answers with the visit so the
# verification passes (a dropped edge is the (BLKEDGE) case, on the blocked exit).
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --visit tk-visit1
eq "$RC" "0" "(RUL) a ruling disposition succeeds"
has "gc.first_reaction_target=tk-visit1" "$LOG" "(RUL) the visit it filed is recorded"
has "HELM takeaway tk-sub needs a ruling: which default --by proactive --release" "$LOG" \
   "(RUL) the bead is released back to the human"
hasnt "--route" "$LOG" "(RUL) …not routed to a pool"
has "--waiting-on tk-visit1" "$LOG" "(RUL) …and held by the visit edge"
# A ruling names the visit as its wait: the subject waits on a person, the visit
# bead is what re-asks, and --waiting-on records that wait as a blocks edge so
# doctor/check-wait-is-an-edge reads a graph state rather than reporting prose.
hasnt "--no-wait" "$LOG" "(RUL) …and never claims nothing is waiting"

run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "2" "(RUL) a ruling with no visit is refused"

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
has "File the visit instead" "$ERR" "(CLOSE) …and the refusal names the exit that reaches a human"
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
# re-released just the same and the guard covers it too.
run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1
eq "$RC" "2" "(REACTED) …the ruling exit too"
hasnt "HELM" "$LOG" "(REACTED) …with no re-release"

# gc.proactive_reaction=1 alone (the record stamps absent) still proves the
# release landed, so a second dispose is refused.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.proactive_reaction":"1"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "2" "(REACTED) gc.proactive_reaction=1 alone also refuses a second dispose"

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
echo "first-reaction-dispose (four exits, one record): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
