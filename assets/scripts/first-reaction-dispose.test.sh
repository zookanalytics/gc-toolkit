#!/usr/bin/env bash
# Hermetic tests for first-reaction-dispose.sh — the four exits a first reaction
# ends in, in the reaction-bead model. Runs the REAL script with a stubbed `gc`,
# a stubbed gc-helm.sh, a stubbed deferred-dispatch.sh and a stubbed
# bead-rehome.sh (all reached through the tool-override env vars), so no live
# city, Dolt or network is touched. What each block guards is named above it.
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
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "bd update") printf 'UPDATE %s\n' "$*" >> "$FAKE_LOG" ;;
  "bd create")
    printf 'CREATE %s\n' "$*" >> "$FAKE_LOG"
    [ -n "${FAKE_CREATE_FAILS:-}" ] && { printf '{"error":"nope"}\n'; exit 0; }
    printf '[{"id":"%s"}]\n' "${FAKE_NEW_ID:-tk-newblk}" ;;
  "rig list")
    printf '{"rigs":[{"name":"gc-toolkit","path":"%s","prefix":"tk"}]}\n' "${FAKE_RIG_PATH:-/nonexistent-rig}" ;;
  "bd show")
    printf 'SHOW %s\n' "$*" >> "$FAKE_LOG"
    printf '%s\n' "${FAKE_SHOW_JSON:-[{\"id\":\"tk-sub\",\"metadata\":{}}]}" ;;
  "bd list")
    printf 'LIST %s\n' "$*" >> "$FAKE_LOG"
    printf '%s\n' "${FAKE_LIST_JSON:-[]}" ;;
  "bd dep")
    printf 'DEP %s\n' "$*" >> "$FAKE_LOG"
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

# bead-rehome.sh stub — the superseded exit's close-with-successor writer.
# --check answers eligibility (0 eligible / non-zero refused, writing nothing);
# the close answers 0 unless FAKE_REHOME_FAILS. A stub that closed regardless
# would hide the check-first contract.
cat > "$TMP/rehome" <<'RH'
#!/usr/bin/env bash
printf 'REHOME %s\n' "$*" >> "$FAKE_LOG"
case " $* " in
  *" --check "*) [ -n "${FAKE_REHOME_CHECK_FAILS:-}" ] && { echo "rehome --check: origin carries unlanded work" >&2; exit 1; }; exit 0 ;;
esac
[ -n "${FAKE_REHOME_FAILS:-}" ] && { echo "rehome: bd close refused" >&2; exit 5; }
exit 0
RH
chmod +x "$TMP/rehome"

export PATH="$TMP/bin:$PATH"
export FAKE_LOG="$TMP/log"
export GC_HELM_TOOL="$TMP/helm" GC_DEFERRED_DISPATCH_TOOL="$TMP/deferred" \
       GC_PROACTIVE_TOOL="$TMP/proactive" GC_BEAD_REHOME_TOOL="$TMP/rehome"

R="tk-react"   # the reaction bead the worker holds
run() { : > "$FAKE_LOG"; RC=0; OUT="$("$SCRIPT" "$@" 2>"$TMP/err")" || RC=$?; ERR="$(cat "$TMP/err")"; LOG="$(cat "$FAKE_LOG")"; }

# ── Usage: refuse before writing ─────────────────────────────────────────────
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

# ── actionable: the bead is work, so hand it to a pool ───────────────────────
run tk-sub --disposition actionable --reason "states a done condition and a branch" \
    --takeaway "routed to the polecat pool" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(ACT) an actionable disposition succeeds"
has "HELM takeaway tk-sub routed to the polecat pool --by proactive --release --route gc-toolkit/gc-toolkit.polecat" \
    "$LOG" "(ACTROUTE) the release hands the bead to the pool in one call"
has "--no-wait" "$LOG" "(ACTROUTE) …and says nothing is waiting on it"
has "gc.reacted_by=$R" "$LOG" "(ACT) the completion marker names the reaction bead"
# The marker is LAST: written after the release (the act), so its presence proves
# the whole write-back landed.
eq "$(grep -n -m1 'gc.reacted_by' "$FAKE_LOG" | cut -d: -f1 | { read a; b=$(grep -n -m1 '^HELM' "$FAKE_LOG" | cut -d: -f1); [ "${a:-0}" -gt "${b:-0}" ] && echo yes || echo no; })" \
   "yes" "(ACTORDER) the marker is stamped AFTER the act"
has "UPDATE bd update $R" "$LOG" "(ACTCLOSE) the reaction bead is closed"
has "status=closed" "$LOG" "(ACTCLOSE) …with a closed status"
has "gc.outcome=reacted" "$LOG" "(ACTCLOSE) …recording the outcome"
hasnt "gc.first_reaction=" "$LOG" "(ACT) the retired subject-metadata record is not written"
LOG_ACT="$LOG"

run tk-sub --disposition actionable --reason "r" --takeaway "t" --waiting-on tk-other --reaction-bead "$R"
eq "$RC" "2" "(ACT) actionable refuses the other exits' flags"

has "PROACTIVE deliverable gc-toolkit/gc-toolkit.polecat" "$LOG_ACT" \
    "(ACTPOOL) the exit asks whether the pool can claim before handing over"
export FAKE_POOL_DEAD=1
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.nosuch --reaction-bead "$R"
eq "$RC" "2" "(ACTPOOL) a pool that cannot claim refuses the exit"
hasnt "HELM" "$LOG" "(ACTPOOL) …and the bead is not released"
has "File the visit instead" "$ERR" "(ACTPOOL) …and the refusal names the exit that does work"
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

# ── blocked: the wait is an edge, in one store ───────────────────────────────
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "waits on the schema migration" \
    --takeaway "held: schema migration first" --waiting-on tk-blk1 --reaction-bead "$R"
eq "$RC" "0" "(BLK) a blocked disposition succeeds"
has "--release --waiting-on tk-blk1" "$LOG" "(BLK) the wait rides the release as an edge"
hasnt "--route" "$LOG" "(BLK) …and a held bead is not also routed"
hasnt "--no-wait" "$LOG" "(BLK) …and the named wait is not also called settled"
has "gc.reacted_by=$R" "$LOG" "(BLK) the completion marker is stamped"
# Marker after the EDGE: the dep-list verification reads the edge, then the marker
# lands. Assert the marker follows the dep list read.
eq "$(a=$(grep -n -m1 'gc.reacted_by' "$FAKE_LOG" | cut -d: -f1); b=$(grep -n -m1 '^DEP bd dep list' "$FAKE_LOG" | cut -d: -f1); [ "${a:-0}" -gt "${b:-0}" ] && echo yes || echo no)" \
   "yes" "(BLKORDER) the marker is stamped after the edge is verified"
has "UPDATE bd update $R" "$LOG" "(BLK) …and the reaction bead is closed"

run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on sl-foreign --reaction-bead "$R"
eq "$RC" "2" "(BLKCROSS) a blocker in another store is refused"
eq "$LOG" "" "(BLKCROSS) …and nothing was written"
has "holds nothing" "$ERR" "(BLKCROSS) …because the edge would report success and hold nothing"

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
has "--waiting-on tk-filed" "$LOG" "(BLKNEW) …and the subject waits on it"

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
hasnt "gc.reacted_by" "$LOG" "(BLKEDGE) …and the completion marker is NOT stamped over an unheld bead"
hasnt "UPDATE bd update $R" "$LOG" "(BLKEDGE) …and the reaction bead is NOT closed"

# The arm is downstream of the hold: no edge, no deferred dispatch.
export FAKE_DEPS_JSON='[]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "4" "(BLKEDGE) a dropped edge fails before the deferred dispatch is armed"
hasnt "DEFERRED arm" "$LOG" "(BLKEDGE) …so nothing is armed on a wait that does not exist"

export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]'
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
has "DEFERRED arm tk-sub --target gc-toolkit/gc-toolkit.polecat" "$LOG" \
    "(BLKARM) --then-route arms the dispatch for when the wait lifts"
has "armed the dispatch to gc-toolkit/gc-toolkit.polecat" "$ERR" "(BLKARM) …and the arm lands"

# --then-route held to the roster test.
export FAKE_POOL_DEAD=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 \
    --then-route gc-toolkit/gc-toolkit.nosuchpool --reaction-bead "$R"
eq "$RC" "2" "(BLKROUTE) --then-route to a pool nothing runs is refused"
hasnt "DEFERRED arm" "$LOG" "(BLKROUTE) …and nothing is armed to a target that would fail every reconcile pass"
unset FAKE_POOL_DEAD FAKE_DEPS_JSON

# A genuine gc-helm release failure dies before the marker and the close.
export FAKE_DEPS_JSON='[{"id":"tk-blk1"}]' FAKE_HELM_FAILS=1
run tk-sub --disposition blocked --reason "r" --takeaway "t" --waiting-on tk-blk1 --reaction-bead "$R"
eq "$RC" "4" "(HELMFAIL) a failed release is a runtime failure"
hasnt "gc.reacted_by" "$LOG" "(HELMFAIL) …and the completion marker is not stamped"
hasnt "UPDATE bd update $R" "$LOG" "(HELMFAIL) …and the reaction bead is not closed"
unset FAKE_HELM_FAILS FAKE_DEPS_JSON

# ── ruling: the visit is the wait, named as a blocks edge on the subject ─────
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
run tk-sub --disposition ruling --reason "the trade-off is the operator's" \
    --takeaway "needs a ruling: which default" --visit tk-visit1 --reaction-bead "$R"
eq "$RC" "0" "(RUL) a ruling disposition succeeds"
has "HELM takeaway tk-sub needs a ruling: which default --by proactive --release" "$LOG" \
   "(RUL) the bead is released back to the human"
hasnt "--route" "$LOG" "(RUL) …not routed to a pool"
has "--waiting-on tk-visit1" "$LOG" "(RUL) …and held by the visit edge"
hasnt "--no-wait" "$LOG" "(RUL) …and never claims nothing is waiting"
has "gc.reacted_by=$R" "$LOG" "(RUL) the completion marker is stamped"
has "UPDATE bd update $R" "$LOG" "(RUL) …and the reaction bead is closed"

run tk-sub --disposition ruling --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "2" "(RUL) a ruling with no visit is refused"

# ── superseded: close the subject with a successor, through bead-rehome ───────
#   (SUP)      --check gates the close; a pass runs check < close < close-R
#   (SUPCHECK) a --check refusal writes nothing and names the ruling fallback
#   (SUPKIND)  only fixed-upstream|duplicate; a judgment kind is refused
#   (SUPARGS)  --successor required, not self; foreign flags refused
export FAKE_DEPS_JSON='[]'
run tk-sub --disposition superseded --reason "duplicate of the survivor" \
    --takeaway "closed: duplicate of tk-surv" --successor tk-surv --kind duplicate --reaction-bead "$R"
eq "$RC" "0" "(SUP) a superseded disposition succeeds"
has "REHOME --check --origin tk-sub --successor tk-surv --kind duplicate" "$LOG" "(SUP) --check runs first"
has "REHOME --origin tk-sub --successor tk-surv --kind duplicate --note" "$LOG" "(SUP) …then the close"
eq "$(a=$(grep -n -m1 'REHOME --origin' "$FAKE_LOG" | cut -d: -f1); b=$(grep -n -m1 'REHOME --check' "$FAKE_LOG" | cut -d: -f1); [ "${a:-0}" -gt "${b:-0}" ] && echo yes || echo no)" \
   "yes" "(SUP) the close runs after the check"
has "UPDATE bd update $R" "$LOG" "(SUP) …and the reaction bead is closed"
hasnt "gc.reacted_by" "$LOG" "(SUP) …no reacted_by marker: the subject closing IS the completion signal"
hasnt "HELM" "$LOG" "(SUP) …and superseded does not go through the takeaway release"

export FAKE_REHOME_CHECK_FAILS=1
run tk-sub --disposition superseded --reason "r" --takeaway "t" --successor tk-surv --reaction-bead "$R"
eq "$RC" "4" "(SUPCHECK) a --check refusal fails the exit"
hasnt "REHOME --origin" "$LOG" "(SUPCHECK) …the close never runs"
hasnt "UPDATE bd update $R" "$LOG" "(SUPCHECK) …and the reaction bead is not closed"
has "take --disposition ruling" "$ERR" "(SUPCHECK) …and the refusal names the ruling fallback"
unset FAKE_REHOME_CHECK_FAILS

run tk-sub --disposition superseded --reason "r" --takeaway "t" --successor tk-surv --kind re-homed --reaction-bead "$R"
eq "$RC" "2" "(SUPKIND) a judgment kind (re-homed) is refused"
has "operator's call" "$ERR" "(SUPKIND) …naming it the operator's call"

run tk-sub --disposition superseded --reason "r" --takeaway "t" --reaction-bead "$R"
eq "$RC" "2" "(SUPARGS) superseded with no --successor is refused"
run tk-sub --disposition superseded --reason "r" --takeaway "t" --successor tk-sub --reaction-bead "$R"
eq "$RC" "2" "(SUPARGS) …and the successor cannot be the subject"
run tk-sub --disposition superseded --reason "r" --takeaway "t" --successor tk-surv --route x/y --reaction-bead "$R"
eq "$RC" "2" "(SUPARGS) …and a foreign exit's flag is refused"
# default kind is fixed-upstream
run tk-sub --disposition superseded --reason "r" --takeaway "t" --successor tk-surv --reaction-bead "$R"
has "REHOME --check --origin tk-sub --successor tk-surv --kind fixed-upstream" "$LOG" "(SUPKIND) --kind defaults to fixed-upstream"

# ── Re-offer recovery: a reaction happens once ───────────────────────────────
# R re-offered after a crash in the act-on-S -> close-R window: S already carries
# gc.reacted_by=R, so the run closes R and touches S no further.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"gc.reacted_by":"tk-react"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(REOFFER) a subject already reacted-by this R closes R without re-disposing"
hasnt "HELM" "$LOG" "(REOFFER) …the subject is not re-released"
has "UPDATE bd update $R" "$LOG" "(REOFFER) …and the reaction bead is closed"
has "already carries this reaction's write-back" "$ERR" "(REOFFER) …and it says so"
# A marker naming a DIFFERENT reaction does not suppress this one (re-reaction).
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"gc.reacted_by":"tk-oldreact"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "0" "(REOFFER) a marker from a DIFFERENT reaction does not block this one"
has "HELM takeaway tk-sub" "$LOG" "(REOFFER) …the reaction proceeds"
# superseded recovery: S already closed with a successor -> close R, no re-close.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"closed","metadata":{"gc.superseded_by":"tk-surv"}}]'
run tk-sub --disposition superseded --reason "r" --takeaway "t" --successor tk-surv --reaction-bead "$R"
eq "$RC" "0" "(REOFFER) a subject already closed-with-successor closes R without re-closing"
hasnt "REHOME --origin" "$LOG" "(REOFFER) …bead-rehome does not run again"
has "UPDATE bd update $R" "$LOG" "(REOFFER) …and the reaction bead is closed"
unset FAKE_SHOW_JSON

# ── An operator's commissioned topic is always the conversation ──────────────
export FAKE_SHOW_JSON='[{"id":"tk-sub","metadata":{"gc.origin":"operator"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat --reaction-bead "$R"
eq "$RC" "2" "(ORIGIN) an operator-commissioned subject refuses the actionable exit"
has "the visit IS the answer" "$ERR" "(ORIGIN) …and the refusal names the contract it protects"
export FAKE_DEPS_JSON='[]'
run tk-sub --disposition superseded --reason "r" --takeaway "t" --successor tk-surv --reaction-bead "$R"
eq "$RC" "2" "(ORIGIN) …and the superseded exit too"
export FAKE_DEPS_JSON='[{"id":"tk-visit1"}]'
run tk-sub --disposition ruling --reason "r" --takeaway "t" --visit tk-visit1 --reaction-bead "$R"
eq "$RC" "0" "(ORIGIN) …while the ruling exit is exactly what it wants"
unset FAKE_SHOW_JSON FAKE_DEPS_JSON

# ── Backward compat: the frozen mol-first-reaction call (no --reaction-bead) ──
# An in-flight molecule calls this without --reaction-bead, so it has no R to key
# exactly-once on. The write-back runs and, in place of gc.reacted_by, stamps the
# legacy landed proof gc.proactive_reaction=1 — the marker that molecule's own
# load-bead REACTED check reads and this script's re-offer guard keys on.
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(LEGACY) the frozen call with no --reaction-bead still disposes"
has "HELM takeaway tk-sub" "$LOG" "(LEGACY) …the act runs"
hasnt "gc.reacted_by" "$LOG" "(LEGACY) …no gc.reacted_by marker without an R to name"
has "gc.proactive_reaction=1" "$LOG" "(LEGACY) …but the legacy landed proof is stamped so a re-offer does not re-dispose"
hasnt "UPDATE bd update tk-react" "$LOG" "(LEGACY) …and no reaction bead is closed"
hasnt "gc.first_reaction=" "$LOG" "(LEGACY) …and the retired attempt record stays gone"

# A re-offered frozen step: S already carries the landed proof, so the second run
# is a no-op success — the act does NOT run, so a bead a downstream worker may
# have claimed is not reopened and re-routed out from under it.
export FAKE_SHOW_JSON='[{"id":"tk-sub","status":"open","metadata":{"gc.proactive_reaction":"1"}}]'
run tk-sub --disposition actionable --reason "r" --takeaway "t" --route gc-toolkit/gc-toolkit.polecat
eq "$RC" "0" "(LEGACY-REOFFER) a subject already carrying the landed proof disposes as a no-op"
hasnt "HELM" "$LOG" "(LEGACY-REOFFER) …the subject is not re-released"
has "already carries a landed first reaction" "$ERR" "(LEGACY-REOFFER) …and it says so"
unset FAKE_SHOW_JSON

# ── The subject is never closed by a bare gc bd close ────────────────────────
# Three exits leave the subject open; superseded closes it ONLY through
# bead-rehome. The script's only status=closed write is the reaction bead's.
grep -qE 'bd (update "?\$?BEAD"?|close).*status=closed|close "\$BEAD"' "$SCRIPT" \
  && bad "(NEVERCLOSE) the script closes the subject directly" \
  || ok "(NEVERCLOSE) the subject is closed only through bead-rehome, never a bare close"

echo ""
echo "first-reaction-dispose (four exits, reaction-bead): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
