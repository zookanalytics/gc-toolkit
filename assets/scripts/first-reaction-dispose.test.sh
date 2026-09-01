#!/usr/bin/env bash
# Hermetic tests for first-reaction-dispose.sh — the three exits
# mol-first-reaction's terminal step chooses between. Runs the REAL script
# with a stubbed `gc`, a stubbed gc-helm.sh and a stubbed deferred-dispatch.sh
# (both reached through the tool-override env vars), so no live city, Dolt or
# network is touched. What each block guards is named above it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/first-reaction-dispose.sh"
TMP="$(mktemp -d)"
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
    # `dep list --json` answers with what the store holds AFTER the helm call.
    case "${3:-}" in list) printf '%s\n' "${FAKE_DEPS_JSON:-[]}" ;; esac ;;
  "bd close") printf 'CLOSE %s\n' "$*" >> "$FAKE_LOG" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

cat > "$TMP/helm" <<'HELM'
#!/usr/bin/env bash
printf 'HELM %s\n' "$*" >> "$FAKE_LOG"
[ -n "${FAKE_HELM_FAILS:-}" ] && exit 4
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
#   (BLKEDGE)  an edge that did not land is reported, not assumed
#   (BLKARM)   --then-route arms the dispatch that resumes the work
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "waits on the schema migration" \
    --takeaway "held: schema migration first" --waiting-on tk-blk1
eq "$RC" "0" "(BLK) a blocked disposition succeeds"
has "gc.first_reaction=blocked" "$LOG" "(BLK) the choice is recorded"
has "gc.first_reaction_target=tk-blk1" "$LOG" "(BLK) …naming the bead it waits on"
has "--release --waiting-on tk-blk1" "$LOG" "(BLK) the wait rides the release as an edge"
hasnt "--route" "$LOG" "(BLK) …and a held bead is not also routed"

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
eq "$RC" "0" "(BLKEDGE) a dropped edge does not fail the verb"
has "not held by tk-blk1" "$ERR" "(BLKEDGE) …but it is reported"
has "gc bd dep add tk-sub tk-blk1 -t blocks" "$ERR" "(BLKEDGE) …with the repair spelled out"

export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" \
    "(BLKARM) --then-route arms the dispatch for when the wait lifts"

# ── ruling: the visit stays the exit for a question only a human answers ─────
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --visit tk-visit1
eq "$RC" "0" "(RUL) a ruling disposition succeeds"
has "gc.first_reaction_target=tk-visit1" "$LOG" "(RUL) the visit it filed is recorded"
has "HELM takeaway tk-sub needs a ruling: which default --by proactive --release" "$LOG" \
   "(RUL) the bead is released back to the human"
hasnt "--route" "$LOG" "(RUL) …not routed to a pool"
hasnt "--waiting-on" "$LOG" "(RUL) …and not held by an edge"

run tk-sub --disposition ruling --reason "r" --takeaway "t"
eq "$RC" "2" "(RUL) a ruling with no visit is refused"

# ── An operator's commissioned topic is always the conversation ──────────────
# gc-visit-open stamps gc.origin=operator on a topic a human typed and is
# waiting to talk about. Routing or holding that answers a question nobody
# asked. Positive finding only: an unreadable bead proceeds.
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.origin":"operator"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "2" "(ORIGIN) an operator-commissioned subject refuses the actionable exit"
hasnt "UPDATE" "$LOG" "(ORIGIN) …and nothing was written"
has "the visit IS the answer" "$ERR" "(ORIGIN) …and the refusal names the contract it protects"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1
eq "$RC" "2" "(ORIGIN) …and the blocked exit too"

run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1
eq "$RC" "0" "(ORIGIN) …while the ruling exit is exactly what it wants"

export FAKE_SHOW_JSON='not json'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(ORIGIN) an unreadable bead is not evidence of a commission"
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

# ── A failed act leaves the record and says the bead is unreleased ───────────
export FAKE_HELM_FAILS=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "4" "(HELMFAIL) a failed release is a runtime failure"
has "unreleased" "$ERR" "(HELMFAIL) …and says the bead is still held"
unset FAKE_HELM_FAILS

echo ""
echo "first-reaction-dispose (three exits, one record): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
