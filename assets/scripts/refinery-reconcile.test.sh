#!/usr/bin/env bash
# Hermetic test for assets/scripts/refinery-reconcile.sh — the merge-cadence
# driver. Covers: GC_RIG required; refinery discovery + pool derivation;
# the arm ORDER (gate-ensure, pr-open, pr-facts --posture-only, merge, pr-facts,
# convoy-graduate, review-sweep) — the posture arm runs BEFORE merge because
# merge.sh reads posture off the bead and would otherwise read one written a
# pass ago;
# the heal-gates-merge interlock (rc=3 from gate-ensure HOLDS merge.sh in the
# same pass, without failing the order), exercised by extracting and executing
# the marked block against stubs; BEADS_ACTOR / GC_AGENT projections scoped to
# their arms; a failing arm not skipping the arms after it; the exit-1
# failure report; the per-rig pass lock (one merge.sh writer across two
# overlapping ticks, a wedged holder reported rather than skipped over, an
# unobtainable lock refusing the pass before any arm); a killed pass leaving
# its partial output in pass.log; and the invariant binding the order timeout
# to the controller's tracking-sweep window.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init
RUNNER="$HERE/refinery-reconcile.sh"

# Stub arms record invocation order, args and the projected identities.
SD="$TMP/scripts"
mkdir -p "$SD"
cp "$RUNNER" "$SD/refinery-reconcile.sh"
chmod +x "$SD/refinery-reconcile.sh"
mkarm() { # <name> [rc]
  cat > "$SD/$1" <<ARM
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$1" "\$*" "\${BEADS_ACTOR:-}" "\${GC_AGENT:-}" >> "\${ARM_LOG:?}"
exit ${2:-0}
ARM
  chmod +x "$SD/$1"
}
export ARM_LOG="$TMP/arms.log"
export STUB_AGENTS="$TMP/agents.json"
printf '{"agents":[{"qualified_name":"myrig/gc-toolkit.refinery"},{"qualified_name":"myrig/gc-toolkit.polecat"}]}' > "$STUB_AGENTS"
export REFINERY_RECONCILE_STATE_DIR="$TMP/state"
export STUB_ORIGIN_HEAD="main"
unset BEADS_ACTOR GC_AGENT GC_PACK_NAME 2>/dev/null || true

drive() { GC_RIG=myrig GC_RIG_ROOT="$TMP" "$SD/refinery-reconcile.sh" 2>&1; }

echo "# GC_RIG is required"
out=$(env -u GC_RIG "$SD/refinery-reconcile.sh" 2>&1); rc=$?
eq "$rc" 2 "no GC_RIG exits 2"
has "$out" "GC_RIG is unset" "…and says why"

echo "# arms run in order with derived pools and scoped identities"
for a in gate-ensure.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh; do mkarm "$a"; done
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 0 "a clean pass exits 0"
order=$(cut -d'|' -f1 "$ARM_LOG" | paste -sd, -)
eq "$order" "gate-ensure.sh,pr-open.sh,pr-facts.sh,merge.sh,pr-facts.sh,convoy-graduate.sh,review-sweep.sh" "the arms ran in the load-bearing order"
has "$(grep '^gate-ensure' "$ARM_LOG")" "--default codex --review-pool myrig/gc-toolkit.polecat-codex --fix-pool myrig/gc-toolkit.polecat" "gate-ensure got the default + derived review AND fix pools"
merge_line=$(grep '^merge.sh' "$ARM_LOG")
has "$merge_line" "|myrig/gc-toolkit.refinery|" "merge.sh ran as BEADS_ACTOR=<refinery>"
facts_line=$(grep '^pr-facts' "$ARM_LOG" | grep -- '--fix-pool')
has "$facts_line" "--fix-pool myrig/gc-toolkit.polecat --review-pool myrig/gc-toolkit.polecat-codex" "pr-facts got both derived pools"
has "$facts_line" "|myrig/gc-toolkit.refinery|" "pr-facts ran as BEADS_ACTOR=<refinery>"

# merge.sh reads pr_posture off the bead and never asks GitHub, so a posture
# written by the pass BEFORE it cannot see a comment that arrived since.
posture_line=$(grep '^pr-facts' "$ARM_LOG" | grep -- '--posture-only')
eq "$(printf '%s\n' "$posture_line" | wc -l | tr -d ' ')" 1 "the posture arm ran exactly once"
has "$posture_line" "|myrig/gc-toolkit.refinery|" "the posture arm ran as BEADS_ACTOR=<refinery>"
hasnt "$posture_line" "--fix-pool" "the posture arm dispatches nothing, so it takes no pools"
posture_at=$(grep -n '^pr-facts.*--posture-only' "$ARM_LOG" | head -1 | cut -d: -f1)
merge_at=$(grep -n '^merge.sh' "$ARM_LOG" | head -1 | cut -d: -f1)
[ -n "$posture_at" ] && [ -n "$merge_at" ] && [ "$posture_at" -lt "$merge_at" ] \
  && ok "posture is recorded BEFORE merge reads it" \
  || bad "posture arm did not run before merge (posture=$posture_at merge=$merge_at)"
grad_line=$(grep '^convoy-graduate' "$ARM_LOG")
has "$grad_line" "--target main" "convoy-graduate got the origin/HEAD target"
has "$grad_line" "|myrig/gc-toolkit.refinery" "convoy-graduate ran with GC_AGENT=<refinery>"
gate_line=$(grep '^gate-ensure' "$ARM_LOG")
case "$gate_line" in
  *"|myrig/gc-toolkit.refinery|"*) bad "gate-ensure must NOT inherit BEADS_ACTOR (projection is scoped to the closing arms)" ;;
  *) ok "identity projections are scoped, not process-wide" ;;
esac

echo "# gate-ensure rc=3 HOLDS merge.sh without failing the order"
mkarm gate-ensure.sh 3
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 0 "the designed hold does not fail the order"
has "$out" "merge.sh HELD this pass" "the hold is reported"
if grep -q '^merge.sh' "$ARM_LOG"; then bad "merge.sh RAN despite an unsafe gate-ensure"; else ok "merge.sh did not run"; fi
grep -q '^pr-facts' "$ARM_LOG" && ok "pr-facts still ran (arms are independent)" || bad "pr-facts was skipped by the hold"

echo "# a failing arm fails the order but does not skip later arms"
mkarm gate-ensure.sh
mkarm pr-open.sh 1
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 1 "a failing arm exits 1"
has "$out" "pr-open rc=1" "…naming the failed arm"
grep -q '^merge.sh' "$ARM_LOG" && ok "merge.sh still ran after the pr-open failure" || bad "merge.sh was skipped"
grep -q '^convoy-graduate' "$ARM_LOG" && ok "convoy-graduate still ran" || bad "convoy-graduate was skipped"

echo "# integration_auto_land=false disables graduation only"
mkarm pr-open.sh
: > "$ARM_LOG"
out=$(REFINERY_RECONCILE_INTEGRATION_AUTO_LAND=false drive); rc=$?
eq "$rc" 0 "the disabled pass exits 0"
if grep -q '^convoy-graduate' "$ARM_LOG"; then bad "convoy-graduate ran despite the kill-switch"; else ok "convoy-graduate disabled"; fi
grep -q '^merge.sh' "$ARM_LOG" && ok "the merge arm is untouched by the switch" || bad "merge arm missing"
grep -q '^review-sweep' "$ARM_LOG" && ok "review-sweep is untouched by the switch" || bad "review-sweep was skipped"

echo "# no refinery bound = nothing to reconcile"
printf '{"agents":[]}' > "$STUB_AGENTS"
out=$(drive); rc=$?
eq "$rc" 0 "no bound refinery exits 0"
has "$out" "no refinery agent bound" "…and says so"
printf '{"agents":[{"qualified_name":"myrig/gc-toolkit.refinery"}]}' > "$STUB_AGENTS"

PASSLOG="$TMP/state/myrig/pass.log"
# A gate-ensure that blocks until released, so a pass can be caught in flight.
# The wait is BOUNDED: a driver that let a second pass in would otherwise sit
# on its own release sentinel and hang the suite instead of failing it.
mkblocking_gate() {
  cat > "$SD/gate-ensure.sh" <<'ARM'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "gate-ensure.sh" "$*" "${BEADS_ACTOR:-}" "${GC_AGENT:-}" >> "${ARM_LOG:?}"
: > "${GATE_STARTED:?}"
i=0
while [ ! -f "${GATE_RELEASE:?}" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done
ARM
  chmod +x "$SD/gate-ensure.sh"
}
await() { # <file> — bounded wait for a sentinel to appear
  local i=0
  while [ ! -f "$1" ] && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
  [ -f "$1" ]
}
# An arm inherits fd 9, so killing a driver does not free the lock until the
# arm it was inside exits too — which is the wedge the stall bound exists for.
await_lock_free() {
  local i=0
  while [ "$i" -lt 400 ]; do
    ( exec 9>>"$TMP/state/myrig/pass.lock"; flock -n 9 ) 2>/dev/null && return 0
    sleep 0.05; i=$((i + 1))
  done
  return 1
}
export GATE_STARTED="$TMP/gate-started" GATE_RELEASE="$TMP/gate-release"

echo "# the per-rig pass lock, not the tracking bead, is the single-flight"
LOCK_PROVEN=0
for a in pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh; do mkarm "$a"; done
mkblocking_gate
rm -f "$GATE_STARTED" "$GATE_RELEASE"
: > "$ARM_LOG"
drive > /dev/null 2>&1 &
d1=$!
if await "$GATE_STARTED"; then
  out=$(drive); rc=$?
  eq "$rc" 0 "a tick that overlaps a running pass exits 0 — the cadence is firing, not failing"
  has "$out" "already in flight" "…and says a pass is in flight"
  : > "$GATE_RELEASE"
  wait "$d1"
  n=$(grep -c '^merge.sh' "$ARM_LOG")
  eq "$n" 1 "exactly one merge.sh writer ran across the two overlapping ticks"
  [ "$n" = 1 ] && LOCK_PROVEN=1
  grep -q 'SKIPPED: pass already in flight' "$PASSLOG" \
    && ok "the skipped tick is recorded in pass.log" \
    || bad "the skipped tick left no trace in pass.log"
else
  bad "the first pass never reached its gate-ensure arm (fixture wedged)"
  : > "$GATE_RELEASE"; wait "$d1" 2>/dev/null
fi

echo "# a pass killed mid-run leaves its partial output behind"
rm -f "$PASSLOG" "$GATE_STARTED" "$GATE_RELEASE"
: > "$ARM_LOG"
drive > /dev/null 2>&1 &
d2=$!
if await "$GATE_STARTED"; then
  kill -9 "$d2" 2>/dev/null
  : > "$GATE_RELEASE"
  wait "$d2" 2>/dev/null
  grep -q '^=== .*rig=myrig' "$PASSLOG" \
    && ok "the killed pass left its header in pass.log" \
    || bad "the killed pass left no header — an overrun is invisible again"
  grep -q '^-- (1) gate-ensure' "$PASSLOG" \
    && ok "…and the arm it died in" \
    || bad "…but not the arm it died in"
  grep -q '^END ' "$PASSLOG" \
    && bad "the killed pass wrote an END line — a kill is indistinguishable from a clean exit" \
    || ok "no END line, so the kill is legible as an unfinished pass"
else
  bad "the pass to be killed never reached its gate-ensure arm (fixture wedged)"
  : > "$GATE_RELEASE"; wait "$d2" 2>/dev/null
fi

echo "# a lock held past the stall bound is reported, not skipped over"
await_lock_free || bad "the killed pass's arm never released the lock"
rm -f "$PASSLOG"
( exec 9>>"$TMP/state/myrig/pass.lock"
  flock -n 9 || exit 1
  printf '999999 1\n' > "$TMP/state/myrig/pass.holder"
  : > "$TMP/stall-held"
  i=0
  while [ ! -f "$TMP/stall-release" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done ) &
d3=$!
if await "$TMP/stall-held"; then
  : > "$ARM_LOG"
  out=$(REFINERY_RECONCILE_LOCK_STALL_SECS=60 drive); rc=$?
  eq "$rc" 1 "a holder older than the stall bound fails the order"
  has "$out" "cadence is wedged" "…saying merges have stopped"
  grep -q '^merge.sh' "$ARM_LOG" && bad "merge.sh ran while another writer held the lock" \
    || ok "no second writer ran"
else
  bad "the stall fixture never took the lock"
fi
: > "$TMP/stall-release"; wait "$d3" 2>/dev/null
rm -f "$TMP/stall-held" "$TMP/stall-release" "$TMP/state/myrig/pass.holder"

echo "# a completed pass is bracketed in pass.log"
rm -f "$PASSLOG"
mkarm gate-ensure.sh
drive > /dev/null
grep -q '^=== .*rig=myrig refinery=myrig/gc-toolkit.refinery' "$PASSLOG" \
  && ok "the pass opens with its === header" || bad "no === header"
grep -q '^END ' "$PASSLOG" && ok "…and closes with END" || bad "no END line on a clean pass"

echo "# a lock that cannot be established stops the pass before any arm"
# Both ways the lock goes missing are covered: a lock file the driver cannot
# open, and no flock on PATH at all.
NOLOCK="$TMP/state-nolock"
mkdir -p "$NOLOCK/myrig/pass.lock"
: > "$ARM_LOG"
out=$(REFINERY_RECONCILE_STATE_DIR="$NOLOCK" drive); rc=$?
eq "$rc" 1 "an unobtainable pass lock fails the order"
has "$out" "single-flight UNGUARDED" "…naming the guarantee it could not take"
if [ -s "$ARM_LOG" ]; then
  bad "arms ran unguarded: $(cut -d'|' -f1 "$ARM_LOG" | paste -sd, -)"
else
  ok "no arm ran without the lock"
fi
grep -q 'UNGUARDED: .*no arm ran' "$NOLOCK/myrig/pass.log" \
  && ok "the refusal is recorded in pass.log" \
  || bad "the refusal left no trace in pass.log"
grep -q '^=== ' "$NOLOCK/myrig/pass.log" \
  && bad "the refused tick opened a pass header — it got past the lock check" \
  || ok "…with no pass header under it, so nothing started"

# Permissions cannot hide flock from `command -v`, because bash skips a
# non-executable hit and keeps searching PATH. So this arm needs a PATH carrying
# every tool the driver reaches for except flock.
NOFLOCK="$TMP/noflock"
mkdir -p "$NOFLOCK"
for c in bash env jq git gc date mkdir mktemp tr head tail mv dirname cat; do
  p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$NOFLOCK/$c"
done
: > "$ARM_LOG"
out=$(PATH="$NOFLOCK" REFINERY_RECONCILE_STATE_DIR="$TMP/state-noflock" \
  GC_RIG=myrig GC_RIG_ROOT="$TMP" "$SD/refinery-reconcile.sh" 2>&1); rc=$?
eq "$rc" 1 "a driver with no flock on PATH fails the order"
has "$out" "flock not found" "…naming the missing tool"
if [ -s "$ARM_LOG" ]; then
  bad "arms ran with no flock available: $(cut -d'|' -f1 "$ARM_LOG" | paste -sd, -)"
else
  ok "no arm ran without flock"
fi

echo "# the marked interlock block executes standalone against stubs"
GATE="$(awk '/# >>> heal-gates-merge/{f=1;next} /# <<< heal-gates-merge/{f=0} f' "$RUNNER")"
[ -n "$GATE" ] && ok "heal-gates-merge block extracted" || bad "heal-gates-merge markers missing"
hasnt "$GATE" '{{' "the block is template-free (executable verbatim)"
GSD="$TMP/gsd"; mkdir -p "$GSD"
printf '#!/usr/bin/env bash\nexit 3\n' > "$GSD/gate-ensure.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GSD/pr-open.sh"
printf '#!/usr/bin/env bash\necho "posture $*" >> "${BLOCK_SENTINEL:?}"\n' > "$GSD/pr-facts.sh"
printf '#!/usr/bin/env bash\necho ran >> "${MERGE_SENTINEL:?}"\necho merge >> "${BLOCK_SENTINEL:?}"\n' > "$GSD/merge.sh"
chmod +x "$GSD"/*.sh
export MERGE_SENTINEL="$TMP/merge-ran"; : > "$MERGE_SENTINEL"
export BLOCK_SENTINEL="$TMP/block-order"; : > "$BLOCK_SENTINEL"
{
  printf 'set -u\nSCRIPTS_DIR=%q\nLOG_SINK=""\nNOTED=""\nFAILED=""\n' "$GSD"
  printf 'AGENT=%q\nCHECK_SET_DEFAULT=%q\nREVIEW_POOL=%q\nFIX_POOL=%q\n' \
    'myrig/gc-toolkit.refinery' codex 'myrig/p-codex' 'myrig/p'
  printf '%s\n' "$GATE"
  printf 'echo "MERGE_HELD=$MERGE_HELD"\n'
} > "$TMP/gaterun.sh"
gout=$(bash "$TMP/gaterun.sh" 2>/dev/null)
[ -s "$MERGE_SENTINEL" ] && bad "(block) merge.sh RAN despite rc=3" || ok "(block) rc=3 held merge.sh"
has "$gout" "MERGE_HELD=1" "(block) the hold flag is set"
# Recording a fact is not a dispatch: a held merge still gets a fresh posture,
# so the pass that finally merges is not reading a stale one.
has "$(cat "$BLOCK_SENTINEL")" "posture --posture-only" "(block) the posture arm runs even when merge is HELD"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GSD/gate-ensure.sh"
: > "$MERGE_SENTINEL"; : > "$BLOCK_SENTINEL"
gout=$(bash "$TMP/gaterun.sh" 2>/dev/null)
[ -s "$MERGE_SENTINEL" ] && ok "(block) a clean gate-ensure lets merge.sh run" || bad "(block) merge.sh did not run after a clean gate-ensure"
has "$gout" "MERGE_HELD=0" "(block) the hold flag is clear"
eq "$(paste -sd, - < "$BLOCK_SENTINEL")" "posture --posture-only,merge" "(block) posture is recorded before merge reads it"

echo "# the shipped order stays wired to this runner"
ORDER="$(cd "$HERE/../.." && pwd)/orders/refinery-reconcile.toml"
o=$(cat "$ORDER" 2>/dev/null)
has "$o" 'trigger = "cooldown"' "order is cooldown-triggered"
has "$o" 'interval = "60s"' "order keeps the 60s cadence"
# The controller watchdog sweeps EVERY order's tracking bead once it is older
# than 2m (gascity cmd/gc/order_dispatch.go, orderTrackingSweepWatchdogStaleAfter),
# and an un-gated tracking bead is a second dispatch. So a timeout above that
# window is only safe when the driver carries its own exclusive lock.
SWEEP_WINDOW=120
to=$(awk -F'"' '/^[[:space:]]*timeout[[:space:]]*=/{print $2}' "$ORDER")
to_secs=""
case "$to" in
  [0-9]*s) to_secs="${to%s}" ;;
  [0-9]*m) to_secs=$(( ${to%m} * 60 )) ;;
esac
if [ -z "$to_secs" ]; then
  bad "order timeout \"$to\" is unparseable — the single-flight invariant cannot be checked"
elif [ "$to_secs" -le "$SWEEP_WINDOW" ]; then
  ok "timeout $to is inside the ${SWEEP_WINDOW}s tracking-sweep window"
elif [ "$LOCK_PROVEN" = 1 ]; then
  ok "timeout $to outruns the ${SWEEP_WINDOW}s tracking-sweep window, and the driver's own lock (proven above) carries single-flight"
else
  bad "timeout $to outruns the ${SWEEP_WINDOW}s tracking-sweep window and the driver has no working lock — a swept tracking bead is a second merge writer"
fi
has "$o" 'scope = "rig"' "order is rig-scoped (single-flight per rig)"
has "$o" 'refinery-reconcile.sh' "order execs this runner"
if grep -qE '^[[:space:]]*no_work_gate' "$ORDER"; then
  bad "no_work_gate must never be set (it opts out of the single-flight gate)"
else
  ok "no_work_gate is not set"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
