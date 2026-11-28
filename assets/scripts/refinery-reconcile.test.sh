#!/usr/bin/env bash
# Hermetic test for assets/scripts/refinery-reconcile.sh — the merge-cadence
# driver. Covers: GC_RIG required; refinery discovery + pool derivation;
# the arm ORDER (gate-ensure, review-sweep, scaffolding-sweep); gate-ensure, the
# paced arm, handed a cursor in the pass state dir and a deadline that is what
# REFINERY_RECONCILE_PASS_BUDGET_SECS has left, never under
# REFINERY_RECONCILE_ARM_FLOOR_SECS;
# gate-ensure's rc=3 reported without failing anything; BEADS_ACTOR projections
# scoped to their arms, and no arm handed GC_AGENT, since nothing in a pass
# assigns work; a failing arm not skipping the arms after it; the exit-1 failure
# report; per-arm start and elapsed lines in pass.log; the per-rig pass lock
# (one pass's arms across two overlapping ticks, a wedged holder reported
# rather than skipped over, an unobtainable lock refusing the pass before any
# arm, every arm run without its descriptor while it is held, a process an arm
# leaves running holding no lock, a driver killed by itself leaving it held
# while the arm it started runs on, and one lock file per rig for a driver of
# any version, whatever the rig's name); a killed pass leaving its partial
# output in pass.log; and the invariant binding the order timeout to the
# controller's tracking-sweep window.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-reconcile-test.XXXXXX")"
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
# The runner takes its pass lock and runs its arms through bd-lib.sh, which it
# sources beside itself.
cp "$HERE/bd-lib.sh" "$SD/bd-lib.sh"
# With FD9_LOG set, an arm also records whether it was handed fd 9, the pass
# lock's descriptor, and whether the lock at LOCK_PROBE was held while it ran.
mkarm() { # <name> [rc]
  cat > "$SD/$1" <<ARM
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$1" "\$*" "\${BEADS_ACTOR:-}" "\${GC_AGENT:-}" >> "\${ARM_LOG:?}"
if [ -n "\${FD9_LOG:-}" ]; then
  if { : >&9; } 2>/dev/null; then fd9=open; else fd9=closed; fi
  if ( exec 8>>"\${LOCK_PROBE:?}"; flock -n 8 ) 2>/dev/null; then lk=free; else lk=held; fi
  printf '%s fd9=%s lock=%s\n' "$1" "\$fd9" "\$lk" >> "\$FD9_LOG"
fi
exit ${2:-0}
ARM
  chmod +x "$SD/$1"
}
export ARM_LOG="$TMP/arms.log"
export STUB_AGENTS="$TMP/agents.json"
printf '{"agents":[{"qualified_name":"myrig/gc-toolkit.refinery"},{"qualified_name":"myrig/gc-toolkit.polecat"}]}' > "$STUB_AGENTS"
export REFINERY_RECONCILE_STATE_DIR="$TMP/state"
unset BEADS_ACTOR GC_AGENT GC_PACK_NAME 2>/dev/null || true

drive() { GC_RIG=myrig GC_RIG_ROOT="$TMP" "$SD/refinery-reconcile.sh" 2>&1; }

echo "# GC_RIG is required"
out=$(env -u GC_RIG "$SD/refinery-reconcile.sh" 2>&1); rc=$?
eq "$rc" 2 "no GC_RIG exits 2"
has "$out" "GC_RIG is unset" "…and says why"

# A paced arm's deadline, as seconds past the pass start T0 the caller took.
offset() { # <arm-line>
  local dl
  dl=$(printf '%s' "$1" | sed -n 's/.*--deadline \([0-9][0-9]*\).*/\1/p')
  if [ -n "$dl" ]; then echo $(( dl - T0 )); else echo none; fi
}
near() { # <offset> <want-secs> <label> — within 15s, for a loaded host
  case "$1" in none|'') bad "$3 (no deadline)"; return 0 ;; esac
  if [ "$1" -ge $(( $2 - 15 )) ] && [ "$1" -le $(( $2 + 15 )) ]; then ok "$3"; else bad "$3 (got ${1}s, want ~${2}s)"; fi
}

echo "# arms run in order with derived pools and scoped identities"
for a in gate-ensure.sh review-sweep.sh scaffolding-sweep.sh; do mkarm "$a"; done
: > "$ARM_LOG"
T0=$(date -u +%s)
out=$(drive); rc=$?
eq "$rc" 0 "a clean pass exits 0"
order=$(cut -d'|' -f1 "$ARM_LOG" | paste -sd, -)
ARM_ORDER="gate-ensure.sh,review-sweep.sh,scaffolding-sweep.sh"
eq "$order" "$ARM_ORDER" "the arms ran in order"
scaf_line=$(grep '^scaffolding-sweep' "$ARM_LOG")
has "$scaf_line" "|myrig/gc-toolkit.refinery|" "scaffolding-sweep ran as BEADS_ACTOR=<refinery>"
gate_line=$(grep '^gate-ensure' "$ARM_LOG")
has "$gate_line" "--default correctness,triage --review-pool myrig/gc-toolkit.polecat-codex --fix-pool myrig/gc-toolkit.polecat --validate-pool myrig/gc-toolkit.polecat" "gate-ensure got the default + derived review, fix AND validate pools"
hasnt "$gate_line" "--review-formula" "gate-ensure gets no --review-formula by default (the two-lane quorum pilot is opt-in)"
# The paced arm resumes from its own cursor in the rig's pass state dir, and
# its deadline is what the default 420s pass budget has left when it starts. It
# is the one paced arm, so that is all of it.
has "$gate_line" "--cursor $TMP/state/myrig/gate-ensure.cursor" "gate-ensure resumes from its own cursor in the pass state dir"
near "$(offset "$gate_line")" 420 "gate-ensure's deadline is the whole 420s pass budget"
eq "$(cut -d'|' -f4 "$ARM_LOG" | sort -u | tr -d '\n')" "" "no arm is handed GC_AGENT: nothing in a pass assigns work"
case "$gate_line" in
  *"|myrig/gc-toolkit.refinery|"*) bad "gate-ensure must NOT inherit BEADS_ACTOR (projection is scoped to the closing arms)" ;;
  *) ok "identity projections are scoped, not process-wide" ;;
esac

echo "# each arm is bracketed in pass.log by its start and its elapsed time"
PASSLOG0="$TMP/state/myrig/pass.log"
grep -qE '^-- \(6\) gate-ensure \(started [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\)$' "$PASSLOG0" \
  && ok "an arm's start line carries its start time" \
  || bad "no timed start line for gate-ensure in pass.log"
grep -qE '^-- \(6\) gate-ensure: done in [0-9]+s \(rc=0\)$' "$PASSLOG0" \
  && ok "an arm's done line carries its elapsed seconds and rc" \
  || bad "no elapsed line for gate-ensure in pass.log"
grep -qE '^END [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z \([0-9]+s\)$' "$PASSLOG0" \
  && ok "the END line carries the pass's elapsed seconds" \
  || bad "the END line carries no pass elapsed time"

echo "# REFINERY_RECONCILE_PASS_BUDGET_SECS sets the deadline; 0 unpaces; a spent budget leaves the arm the floor"
: > "$ARM_LOG"; T0=$(date -u +%s)
REFINERY_RECONCILE_PASS_BUDGET_SECS=700 drive > /dev/null
near "$(offset "$(grep '^gate-ensure' "$ARM_LOG")")" 700 "a 700s budget gives gate-ensure 700s"
: > "$ARM_LOG"
REFINERY_RECONCILE_PASS_BUDGET_SECS=0 drive > /dev/null
hasnt "$(cat "$ARM_LOG")" "--deadline" "a 0 budget hands no arm a deadline"
eq "$(grep -c -- '--cursor ' "$ARM_LOG")" 1 "…and the paced arm still resumes from its cursor"
: > "$ARM_LOG"; T0=$(date -u +%s)
REFINERY_RECONCILE_PASS_BUDGET_SECS=1 drive > /dev/null
near "$(offset "$(grep '^gate-ensure' "$ARM_LOG")")" 20 "a spent budget still gives the paced arm the 20s floor"
: > "$ARM_LOG"; T0=$(date -u +%s)
REFINERY_RECONCILE_PASS_BUDGET_SECS=1 REFINERY_RECONCILE_ARM_FLOOR_SECS=200 drive > /dev/null
near "$(offset "$(grep '^gate-ensure' "$ARM_LOG")")" 200 "REFINERY_RECONCILE_ARM_FLOOR_SECS sets the floor"
: > "$ARM_LOG"; T0=$(date -u +%s)
REFINERY_RECONCILE_PASS_BUDGET_SECS=soon drive > /dev/null
near "$(offset "$(grep '^gate-ensure' "$ARM_LOG")")" 420 "an unparseable budget falls back to the 420s default"
# The shares split among the arms still on PACED_ARMS, so the arms the runner
# paces or skips must be exactly that list, in its order: an arm paced but not
# listed would take a share no split counted, and one listed but never reached
# would shrink every share ahead of it.
listed=$(sed -n 's/^PACED_ARMS=(\(.*\))$/\1/p' "$RUNNER" | tr ' ' ',')
called=$(grep -oE '^[[:space:]]*pace_(args|skip) [a-z-]+$' "$RUNNER" | awk '{ print $2 }' | awk '!seen[$0]++' | paste -sd, -)
[ -n "$listed" ] && ok "PACED_ARMS is readable from the runner" || bad "PACED_ARMS is not readable from the runner"
eq "$called" "$listed" "the runner paces exactly the arms PACED_ARMS lists, in its order"

echo "# gate-ensure rc=3 is reported, and fails nothing"
mkarm gate-ensure.sh 3
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 0 "an unsafe gate-ensure does not fail the order"
has "$out" "gate-ensure UNSAFE (rc=3)" "the unsafe rc is reported"
grep -q '^review-sweep' "$ARM_LOG" && ok "review-sweep still ran (arms are independent)" || bad "review-sweep was skipped"
mkarm gate-ensure.sh

echo "# a failing arm fails the order but does not skip later arms"
mkarm gate-ensure.sh 1
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 1 "a failing arm exits 1"
has "$out" "gate-ensure rc=1" "…naming the failed arm"
grep -q '^review-sweep' "$ARM_LOG" && ok "review-sweep still ran after the gate-ensure failure" || bad "review-sweep was skipped"
grep -q '^scaffolding-sweep' "$ARM_LOG" && ok "scaffolding-sweep still ran" || bad "scaffolding-sweep was skipped"
mkarm gate-ensure.sh

echo "# no refinery bound = nothing to reconcile"
printf '{"agents":[]}' > "$STUB_AGENTS"
out=$(drive); rc=$?
eq "$rc" 0 "no bound refinery exits 0"
has "$out" "no refinery agent bound" "…and says so"
printf '{"agents":[{"qualified_name":"myrig/gc-toolkit.refinery"}]}' > "$STUB_AGENTS"

PASSLOG="$TMP/state/myrig/pass.log"
# A gate-ensure that blocks until released, so a pass can be caught in flight.
# The wait is bounded only as an anti-hang backstop — run-tests.sh's per-file
# timeout is the real one — so it is set far above the test's own detect-and-
# kill latency. A tighter bound could expire first under parallel load, letting
# the driver run on past the phase the kill means to freeze; that is how a kill
# misses the pass. `await` caps at 400 polls, so 6000 leaves ample headroom.
mkblocking_gate() {
  cat > "$SD/gate-ensure.sh" <<'ARM'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "gate-ensure.sh" "$*" "${BEADS_ACTOR:-}" "${GC_AGENT:-}" >> "${ARM_LOG:?}"
: > "${GATE_STARTED:?}"
i=0
while [ ! -f "${GATE_RELEASE:?}" ] && [ "$i" -lt 6000 ]; do sleep 0.05; i=$((i + 1)); done
ARM
  chmod +x "$SD/gate-ensure.sh"
}
await() { # <file> — bounded wait for a sentinel to appear
  local i=0
  while [ ! -f "$1" ] && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
  [ -f "$1" ]
}
# Each arm runs from a subshell that holds the pass lock until the arm exits, so
# killing a driver does not free the lock until the arm it was running exits too.
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
  n=$(grep -c '^gate-ensure.sh' "$ARM_LOG")
  eq "$n" 1 "exactly one pass ran its arms across the two overlapping ticks"
  [ "$n" = 1 ] && LOCK_PROVEN=1
  grep -q 'SKIPPED: pass already in flight' "$PASSLOG" \
    && ok "the skipped tick is recorded in pass.log" \
    || bad "the skipped tick left no trace in pass.log"
else
  bad "the first pass never reached its gate-ensure arm (fixture wedged)"
  : > "$GATE_RELEASE"; wait "$d1" 2>/dev/null
fi

echo "# a driver killed in its first arm leaves its partial output behind, and the lock held while the arm runs on"
await_lock_free || bad "the lock test's pass never released the lock"
mkblocking_gate
rm -f "$PASSLOG" "$GATE_STARTED" "$GATE_RELEASE"
: > "$ARM_LOG"
# Launch the driver directly, not through the drive() function. Backgrounding a
# function forks a wrapper subshell, so $! names the wrapper and `kill` below
# would leave the real driver orphaned — and the GATE_RELEASE written right
# after the kill would then let that orphan run on to its END line, defeating
# this very check. A backgrounded simple command makes $! the driver, so the kill
# lands.
GC_RIG=myrig GC_RIG_ROOT="$TMP" "$SD/refinery-reconcile.sh" > /dev/null 2>&1 &
d2=$!
if await "$GATE_STARTED"; then
  kill -9 "$d2" 2>/dev/null
  wait "$d2" 2>/dev/null
  # gate-ensure runs straight from the driver, with no projection subshell, so
  # only pass_child's subshell can still hold the lock once the driver is gone.
  ( exec 9>>"$TMP/state/myrig/pass.lock"; flock -n 9 ) 2>/dev/null \
    && bad "killing the driver by itself freed the lock while the gate-ensure arm it started ran on" \
    || ok "the lock stays held while the arm a killed driver started is still running"
  grep -q '^=== .*rig=myrig' "$PASSLOG" \
    && ok "the killed pass left its header in pass.log" \
    || bad "the killed pass left no header — an overrun is invisible again"
  grep -q '^-- (6) gate-ensure (started ' "$PASSLOG" \
    && ok "…and the start of the arm it died in" \
    || bad "…but not the arm it died in"
  grep -q '^-- (6) gate-ensure: done' "$PASSLOG" \
    && bad "the arm the pass died in logged a done line" \
    || ok "…with no done line, so the arm it died in is legible"
  grep -q '^END ' "$PASSLOG" \
    && bad "the killed pass wrote an END line — a kill is indistinguishable from a clean exit" \
    || ok "no END line, so the kill is legible as an unfinished pass"
  : > "$GATE_RELEASE"
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
  has "$out" "cadence is wedged" "…saying the arms have stopped"
  [ -s "$ARM_LOG" ] && bad "an arm ran while another writer held the lock" \
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

echo "# every arm runs without the lock's descriptor, under the lock"
# An arm's store read can bring up a Dolt server that outlives the pass, and one
# that kept fd 9 would hold the lock against every later pass.
for a in gate-ensure.sh review-sweep.sh scaffolding-sweep.sh; do mkarm "$a"; done
export FD9_LOG="$TMP/fd9.log" LOCK_PROBE="$TMP/state/myrig/pass.lock"; : > "$FD9_LOG"
out=$(drive); rc=$?
eq "$rc" 0 "the pass completes"
RUNS=$(printf '%s\n' "$ARM_ORDER" | tr ',' '\n' | grep -c .)
eq "$(grep -c ' fd9=' "$FD9_LOG")" "$RUNS" "each arm run in the pass order recorded what it was handed"
eq "$(grep -c 'fd9=open' "$FD9_LOG")" 0 "none of them was handed fd 9"
eq "$(grep -c 'lock=held' "$FD9_LOG")" "$RUNS" "and the pass lock was held while each of them ran"
unset FD9_LOG LOCK_PROBE

echo "# a process an arm leaves running does not hold the lock against the next pass"
DAEMON="$TMP/arm-daemon.pid"; rm -f "$DAEMON"
cat > "$SD/review-sweep.sh" <<'ARM'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "review-sweep.sh" "$*" "${BEADS_ACTOR:-}" "${GC_AGENT:-}" >> "${ARM_LOG:?}"
# A process that keeps every descriptor the arm was handed and runs on after it,
# as a Dolt server a store read brings up does.
( exec sleep 300 ) </dev/null >/dev/null 2>&1 &
printf '%s\n' "$!" > "${ARM_DAEMON:?}"
ARM
chmod +x "$SD/review-sweep.sh"
: > "$ARM_LOG"
ARM_DAEMON="$DAEMON" drive > /dev/null; rc=$?
eq "$rc" 0 "a pass whose arm leaves a process running completes"
mkarm review-sweep.sh
dpid="$(cat "$DAEMON" 2>/dev/null)"
if [ -n "$dpid" ] && kill -0 "$dpid" 2>/dev/null; then
  ok "the process the arm started outlives the pass"
  ( exec 9>>"$TMP/state/myrig/pass.lock"; flock -n 9 ) 2>/dev/null \
    && ok "…and does not hold the pass lock" \
    || bad "a process an arm left running holds the pass lock"
  : > "$ARM_LOG"
  out=$(drive); rc=$?
  hasnt "$out" "already in flight" "the next pass is not held off by it"
  grep -q '^gate-ensure.sh' "$ARM_LOG" && ok "…and runs its arms" || bad "the next pass ran no arms"
else
  bad "the process the fixture's arm starts never ran"
fi
[ -n "$dpid" ] && kill "$dpid" 2>/dev/null

echo "# a driver of any version names the same lock for a rig, whatever the rig's name"
# A deploy can start this driver while the one it replaces is still running a
# pass over the same queue, and only a lock file both name keeps the two apart.
# A stand-in for that pass holds <state-dir>/<key>/pass.lock as a driver does,
# under the key written beside each rig name below: a name past 64 bytes, one
# with bytes the key rewrites, and one the key replaces whole.
for a in gate-ensure.sh review-sweep.sh scaffolding-sweep.sh; do mkarm "$a"; done
NAMES="$TMP/state-names"
LONG="$(printf '%070d' 0 | tr 0 r)"
names_drive() { # <rig>
  REFINERY_RECONCILE_STATE_DIR="$NAMES" REFINERY_RECONCILE_AGENT="$1/gc-toolkit.refinery" \
    GC_RIG="$1" GC_RIG_ROOT="$TMP" "$SD/refinery-reconcile.sh" 2>&1
}
for pair in "$LONG|$LONG" "team a/rig:one|team_a_rig_one" ".|rig"; do
  name="${pair%%|*}" key="${pair#*|}"
  rm -f "$TMP/names-held" "$TMP/names-release"
  ( mkdir -p "$NAMES/$key"
    exec 9>>"$NAMES/$key/pass.lock"
    flock -n 9 || exit 1
    printf '4242 %s\n' "$(date -u +%s)" > "$NAMES/$key/pass.holder"
    : > "$TMP/names-held"
    i=0
    while [ ! -f "$TMP/names-release" ] && [ "$i" -lt 6000 ]; do sleep 0.05; i=$((i + 1)); done ) >/dev/null 2>&1 &
  dn=$!
  if await "$TMP/names-held"; then
    : > "$ARM_LOG"
    out=$(names_drive "$name"); rc=$?
    eq "$rc" 0 "rig '$name': a tick beside the other driver's pass exits 0"
    has "$out" "already in flight (pid 4242" "…because it finds that pass holding the lock under '$key'"
    if [ -s "$ARM_LOG" ]; then
      bad "rig '$name': arms ran beside the other driver's pass: $(cut -d'|' -f1 "$ARM_LOG" | paste -sd, -)"
    else
      ok "…and runs no arm beside it"
    fi
  else
    bad "rig '$name': the stand-in never took the lock"
  fi
  : > "$TMP/names-release"; wait "$dn" 2>/dev/null
  : > "$ARM_LOG"
  export FD9_LOG="$TMP/names-fd9.log" LOCK_PROBE="$NAMES/$key/pass.lock"; : > "$FD9_LOG"
  out=$(names_drive "$name"); rc=$?
  unset FD9_LOG LOCK_PROBE
  eq "$rc" 0 "rig '$name': with the lock free, the pass completes"
  n_all=$(grep -c ' lock=' "$TMP/names-fd9.log"); n_held=$(grep -c ' lock=held' "$TMP/names-fd9.log")
  if [ "$n_all" -gt 0 ] && [ "$n_held" = "$n_all" ]; then
    ok "…and each of its $n_all arm runs holds the lock under '$key', which the other driver would find held"
  else
    bad "rig '$name': $n_held of $n_all arm runs held the lock under '$key'"
  fi
done
eq "$(ls -1 "$NAMES" | LC_ALL=C sort | paste -sd, -)" "rig,$LONG,team_a_rig_one" "no pass kept its state under any other key"

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
  bad "timeout $to outruns the ${SWEEP_WINDOW}s tracking-sweep window and the driver has no working lock — a swept tracking bead is a second writer"
fi
# The other end of the same budget. The runner calls a lock held past
# LOCK_STALL_SECS a wedge and says no arm is running — true of an abandoned fd,
# false of a pass the controller is still running. A timeout at or above that
# bound makes the two indistinguishable, and the report the operator gets for a
# merely slow pass is that the cadence has stopped.
STALL=$(sed -n 's/^LOCK_STALL_SECS=.*:-\([0-9][0-9]*\)}.*/\1/p' "$RUNNER")
case "$STALL" in
  ''|*[!0-9]*) bad "LOCK_STALL_SECS default is unreadable — the timeout cannot be bounded against it" ;;
  *) if [ -n "$to_secs" ] && [ "$to_secs" -lt "$STALL" ]; then
       ok "timeout $to is inside the runner's ${STALL}s lock-stall bound"
     else
       bad "timeout $to is not below the runner's ${STALL}s lock-stall bound — a pass still running reads as a wedged one"
     fi ;;
esac
# The pass budget is what the paced arms divide, so a pass that keeps to it ends
# and writes END. At or above the timeout the controller kills it first, and the
# arms the budget was meant to leave room for are cut off instead.
PB=$(sed -n 's/^PASS_BUDGET_SECS="\${REFINERY_RECONCILE_PASS_BUDGET_SECS:-\([0-9][0-9]*\)}"$/\1/p' "$RUNNER")
case "$PB" in
  ''|*[!0-9]*) bad "PASS_BUDGET_SECS default is unreadable — it cannot be bounded against the timeout" ;;
  *) if [ -n "$to_secs" ] && [ "$PB" -lt "$to_secs" ]; then
       ok "the ${PB}s pass budget sits below the ${to} timeout"
     else
       bad "the ${PB}s pass budget is not below the ${to} timeout — the pass is killed before its paced arms end"
     fi ;;
esac
has "$o" 'scope = "rig"' "order is rig-scoped (single-flight per rig)"
has "$o" 'refinery-reconcile.sh' "order execs this runner"
if grep -qE '^[[:space:]]*no_work_gate' "$ORDER"; then
  bad "no_work_gate must never be set (it opts out of the single-flight gate)"
else
  ok "no_work_gate is not set"
fi

echo "# REFINERY_RECONCILE_REVIEW_FORMULA opts reviews into the two-lane quorum pilot"
for a in gate-ensure.sh review-sweep.sh scaffolding-sweep.sh; do mkarm "$a"; done
: > "$ARM_LOG"
GC_RIG=myrig GC_RIG_ROOT="$TMP" REFINERY_RECONCILE_REVIEW_FORMULA=mol-review-quorum-signoff "$SD/refinery-reconcile.sh" >/dev/null 2>&1
gate_pilot=$(grep '^gate-ensure' "$ARM_LOG")
has "$gate_pilot" "--default correctness,triage --review-pool myrig/gc-toolkit.polecat-codex --fix-pool myrig/gc-toolkit.polecat" "the base gate-ensure args are unchanged under the pilot"
has "$gate_pilot" "--review-formula mol-review-quorum-signoff" "gate-ensure gets the pilot formula from the env"
has "$gate_pilot" "--sling-var lane_one_provider=codex" "lane one runs on the codex provider"
has "$gate_pilot" "--sling-var lane_one_target=myrig/gc-toolkit.polecat-codex" "lane one targets the codex pool"
has "$gate_pilot" "--sling-var lane_two_provider=claude" "lane two runs on the claude provider"
has "$gate_pilot" "--sling-var lane_two_target=myrig/gc-toolkit.polecat" "lane two targets the claude pool"
has "$gate_pilot" "--sling-var synthesis_target=myrig/gc-toolkit.polecat" "the synthesis runs on the claude pool"

echo "# the per-pass bd_list cache is set up, reaches the arms, and is torn down"
CACHE_DIR="$TMP/state/myrig/cache"
CACHE_PROBE="$TMP/cache-probe"
# A gate-ensure stub that records, from inside the pass: the cache var it was
# handed, whether the dir existed, and whether a leftover file survived setup.
cat > "$SD/gate-ensure.sh" <<ARM
#!/usr/bin/env bash
d="\${GC_RECONCILE_BD_CACHE:-<unset>}"
printf '%s|%s|%s\n' "\$d" "\$([ -d "\$d" ] && echo dir-present || echo dir-absent)" "\$([ -e "\$d/stale.json" ] && echo stale-present || echo stale-absent)" >> "$CACHE_PROBE"
exit 0
ARM
chmod +x "$SD/gate-ensure.sh"
for a in review-sweep.sh scaffolding-sweep.sh; do mkarm "$a"; done
# Seed a leftover entry from a notional killed pass; the rm-then-create setup must clear it.
mkdir -p "$CACHE_DIR"; echo '[{"id":"stale"}]' > "$CACHE_DIR/stale.json"
: > "$CACHE_PROBE"
out=$(drive); rc=$?
eq "$rc" 0 "a pass with the bd_list cache wiring exits 0"
probe=$(head -1 "$CACHE_PROBE")
has "$probe" "$CACHE_DIR" "GC_RECONCILE_BD_CACHE is exported to the arms, pointing into the pass state dir"
has "$probe" "dir-present" "the cache dir exists while an arm runs"
has "$probe" "stale-absent" "a leftover dir from a killed pass is recreated clean (its stale entry is gone)"
if [ ! -d "$CACHE_DIR" ]; then ok "the cache dir is removed after END"; else bad "the cache dir survived past END"; fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
