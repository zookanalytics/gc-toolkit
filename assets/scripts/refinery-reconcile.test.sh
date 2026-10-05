#!/usr/bin/env bash
# Hermetic test for assets/scripts/refinery-reconcile.sh — the merge-cadence
# driver. Covers: GC_RIG required; refinery discovery + pool derivation;
# the arm ORDER (pr-facts --posture-only, merge, pr-open, pr-facts
# --route-comments-only, pre-open-rebase, gate-ensure, pr-facts,
# convoy-graduate, review-sweep, scaffolding-sweep, duplicate-sweep, pr-stack) —
# merge runs right behind its one same-pass interlock, the posture arm, which
# merge.sh reads off the bead and would otherwise read one written a pass ago,
# and pr-open right behind merge, so no arm whose cost grows with the gating set
# can spend the pass budget before either runs; a gate-ensure that never returns
# leaves both already run; gate-ensure handed a deadline from
# REFINERY_RECONCILE_GATE_BUDGET_SECS and a cursor in the pass state dir, and
# its rc=3 reported without holding or failing anything; the
# posture-gates-merge interlock (a non-zero posture arm HOLDS merge.sh in the
# same pass, because merge.sh validates the posture that arm records),
# exercised by extracting and executing the marked block against stubs;
# BEADS_ACTOR / GC_AGENT projections scoped to their arms; a failing arm not
# skipping the arms after it; the exit-1 failure report; per-arm start and
# elapsed lines in pass.log; the per-rig pass lock (one merge.sh writer across
# two overlapping ticks, a wedged holder reported rather than skipped over, an
# unobtainable lock refusing the pass before any arm); a killed pass leaving its
# partial output in pass.log; and the invariant binding the order timeout to the
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
for a in gate-ensure.sh pre-open-rebase.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh scaffolding-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 0 "a clean pass exits 0"
order=$(cut -d'|' -f1 "$ARM_LOG" | paste -sd, -)
eq "$order" "pr-facts.sh,merge.sh,pr-open.sh,pr-facts.sh,pre-open-rebase.sh,gate-ensure.sh,pr-facts.sh,convoy-graduate.sh,review-sweep.sh,scaffolding-sweep.sh,duplicate-sweep.sh,pr-stack.sh" "the arms ran in the load-bearing order (posture, then merge, then pr-open, ahead of every arm whose cost grows with the gating set)"
dup_line=$(grep '^duplicate-sweep' "$ARM_LOG")
has "$dup_line" "|myrig/gc-toolkit.refinery|" "duplicate-sweep ran as BEADS_ACTOR=<refinery>"
# pr-stack writes PR bodies and no bead, so it carries neither projection: an
# identity it does not need is authority it must not be able to spend.
stack_line=$(grep '^pr-stack' "$ARM_LOG")
eq "$stack_line" "pr-stack.sh|||" "pr-stack ran last, unprojected and with no args"
gate_line=$(grep '^gate-ensure' "$ARM_LOG")
has "$gate_line" "--default correctness,triage --review-pool myrig/gc-toolkit.polecat-codex --fix-pool myrig/gc-toolkit.polecat --validate-pool myrig/gc-toolkit.polecat" "gate-ensure got the default + derived review, fix AND validate pools"
hasnt "$gate_line" "--review-formula" "gate-ensure gets no --review-formula by default (the two-lane quorum pilot is opt-in)"
has "$gate_line" "--cursor $TMP/state/myrig/gate-ensure.cursor" "gate-ensure resumes from a cursor kept in the rig's pass state dir"
# The deadline is the pass clock plus the budget, read from argv; the default
# budget is 300s, so it lands within a few seconds of now+300.
dl=$(printf '%s' "$gate_line" | sed -n 's/.*--deadline \([0-9][0-9]*\).*/\1/p')
now=$(date -u +%s)
if [ -n "$dl" ] && [ "$dl" -ge $((now + 300 - 30)) ] && [ "$dl" -le $((now + 300)) ]; then
  ok "gate-ensure got a deadline the default 300s budget past its start"
else
  bad "gate-ensure deadline '${dl:-<none>}' is not ~300s past now ($now)"
fi
has "$(grep '^pre-open-rebase' "$ARM_LOG")" "--fix-pool myrig/gc-toolkit.polecat" "pre-open-rebase got the derived fix pool"
case "$(grep '^pre-open-rebase' "$ARM_LOG")" in
  *"|myrig/gc-toolkit.refinery|"*) bad "pre-open-rebase must NOT inherit BEADS_ACTOR (it closes nothing)" ;;
  *) ok "pre-open-rebase ran without the BEADS_ACTOR projection" ;;
esac
merge_line=$(grep '^merge.sh' "$ARM_LOG")
has "$merge_line" "|myrig/gc-toolkit.refinery|" "merge.sh ran as BEADS_ACTOR=<refinery>"
has "$merge_line" "--cursor $TMP/state/myrig/merge.cursor" "merge resumes its paced PRs from a cursor kept in the rig's pass state dir"
dl=$(printf '%s' "$merge_line" | sed -n 's/.*--deadline \([0-9][0-9]*\).*/\1/p')
now=$(date -u +%s)
if [ -n "$dl" ] && [ "$dl" -ge $((now + 120 - 30)) ] && [ "$dl" -le $((now + 120)) ]; then
  ok "merge got a deadline the default 120s budget past its start"
else
  bad "merge deadline '${dl:-<none>}' is not ~120s past now ($now)"
fi
# The full pr-facts arm: --fix-pool and no pre-merge mode flag (the posture arm
# carries neither, the feedback arm carries --route-comments-only).
facts_line=$(grep '^pr-facts' "$ARM_LOG" | grep -- '--fix-pool' | grep -v -- '--route-comments-only')
eq "$(printf '%s\n' "$facts_line" | wc -l | tr -d ' ')" 1 "the full pr-facts arm ran exactly once"
has "$facts_line" "--fix-pool myrig/gc-toolkit.polecat" "pr-facts got the derived fix pool"
hasnt "$facts_line" "--review-pool" "…and no review pool: it dispatches no reviews"
has "$facts_line" "|myrig/gc-toolkit.refinery|" "pr-facts ran as BEADS_ACTOR=<refinery>"

# merge.sh reads pr_posture off the bead and never asks GitHub, so a posture
# written by the pass BEFORE it cannot see a comment that arrived since. The
# posture arm runs first and merge immediately after it, so nothing widens the
# window in which a new comment goes unseen.
posture_line=$(grep '^pr-facts' "$ARM_LOG" | grep -- '--posture-only')
eq "$(printf '%s\n' "$posture_line" | wc -l | tr -d ' ')" 1 "the posture arm ran exactly once"
has "$posture_line" "|myrig/gc-toolkit.refinery|" "the posture arm ran as BEADS_ACTOR=<refinery>"
hasnt "$posture_line" "--fix-pool" "the posture arm dispatches nothing, so it takes no pools"
at() { grep -n "^$1" "$ARM_LOG" | head -1 | cut -d: -f1; }
posture_at=$(at 'pr-facts.*--posture-only')
merge_at=$(at 'merge.sh')
propen_at=$(at 'pr-open')
route_at=$(at 'pr-facts.*--route-comments-only')
preopen_at=$(at 'pre-open-rebase')
gate_at=$(at 'gate-ensure')
eq "$posture_at,$merge_at" "1,2" "the posture is recorded first and merge reads it next, with no arm between them"
# pr-open sits right behind merge: a PR opened this pass is never landable on
# the same tick, so the order costs no landing, and no slower arm can keep a
# green branch from reaching the operator.
eq "$propen_at" 3 "pr-open runs right behind merge"
# gate-ensure visits every gating anchor, so its cost grows with the set merge
# and pr-open drain; behind both, its cost can no longer stop them.
[ -n "$gate_at" ] && [ "$gate_at" -gt "$propen_at" ] && [ "$gate_at" -gt "$merge_at" ] \
  && ok "gate-ensure runs after merge and pr-open" \
  || bad "gate-ensure did not run after merge and pr-open (gate=$gate_at merge=$merge_at propen=$propen_at)"
# The early feedback arm routes operator feedback ahead of gate-ensure and the
# full pr-facts arm, so a pass killed in either has still picked it up. It
# carries a fix pool (it dispatches rework children) but the
# --route-comments-only flag.
route_line=$(grep '^pr-facts' "$ARM_LOG" | grep -- '--route-comments-only')
eq "$(printf '%s\n' "$route_line" | wc -l | tr -d ' ')" 1 "the feedback arm ran exactly once"
has "$route_line" "--fix-pool myrig/gc-toolkit.polecat" "the feedback arm got the derived fix pool"
has "$route_line" "|myrig/gc-toolkit.refinery|" "the feedback arm ran as BEADS_ACTOR=<refinery>"
[ -n "$route_at" ] && [ -n "$gate_at" ] && [ "$route_at" -lt "$gate_at" ] \
  && ok "the feedback arm routes BEFORE gate-ensure (a pass killed there has still picked feedback up)" \
  || bad "feedback arm did not run before gate-ensure (route=$route_at gate=$gate_at)"
# pre-open-rebase observes the pre_open_gate anchors pr-open left where they
# were; an anchor pr-open flipped is the CONFLICTING arm's.
[ -n "$preopen_at" ] && [ "$preopen_at" -gt "$propen_at" ] \
  && ok "pre-open-rebase runs after pr-open" \
  || bad "pre-open-rebase did not run after pr-open (preopen=$preopen_at propen=$propen_at)"
grad_line=$(grep '^convoy-graduate' "$ARM_LOG")
has "$grad_line" "--target main" "convoy-graduate got the origin/HEAD target"
has "$grad_line" "|myrig/gc-toolkit.refinery" "convoy-graduate ran with GC_AGENT=<refinery>"
case "$gate_line" in
  *"|myrig/gc-toolkit.refinery|"*) bad "gate-ensure must NOT inherit BEADS_ACTOR (projection is scoped to the closing arms)" ;;
  *) ok "identity projections are scoped, not process-wide" ;;
esac

echo "# each arm is bracketed in pass.log by its start and its elapsed time"
PASSLOG0="$TMP/state/myrig/pass.log"
grep -qE '^-- \(1\) pr-posture \(started [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\)$' "$PASSLOG0" \
  && ok "an arm's start line carries its start time" \
  || bad "no timed start line for the posture arm in pass.log"
grep -qE '^-- \(6\) gate-ensure: done in [0-9]+s \(rc=0\)$' "$PASSLOG0" \
  && ok "an arm's done line carries its elapsed seconds and rc" \
  || bad "no elapsed line for gate-ensure in pass.log"
grep -qE '^END [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z \([0-9]+s\)$' "$PASSLOG0" \
  && ok "the END line carries the pass's elapsed seconds" \
  || bad "the END line carries no pass elapsed time"

echo "# REFINERY_RECONCILE_MERGE_BUDGET_SECS sets merge's deadline; 0 runs it unbounded"
: > "$ARM_LOG"
REFINERY_RECONCILE_MERGE_BUDGET_SECS=40 drive > /dev/null
dl=$(grep '^merge.sh' "$ARM_LOG" | sed -n 's/.*--deadline \([0-9][0-9]*\).*/\1/p')
now=$(date -u +%s)
[ -n "$dl" ] && [ "$dl" -ge $((now + 40 - 30)) ] && [ "$dl" -le $((now + 40)) ] \
  && ok "a 40s budget puts merge's deadline 40s past its start" \
  || bad "a 40s budget gave merge deadline '${dl:-<none>}' (now $now)"
: > "$ARM_LOG"
REFINERY_RECONCILE_MERGE_BUDGET_SECS=0 drive > /dev/null
ml=$(grep '^merge.sh' "$ARM_LOG")
hasnt "$ml" "--deadline" "a 0 budget hands merge no deadline"
has "$ml" "--cursor " "…and it still resumes from its cursor"

echo "# REFINERY_RECONCILE_GATE_BUDGET_SECS sets gate-ensure's deadline; 0 runs it unbounded"
: > "$ARM_LOG"
REFINERY_RECONCILE_GATE_BUDGET_SECS=45 drive > /dev/null
dl=$(grep '^gate-ensure' "$ARM_LOG" | sed -n 's/.*--deadline \([0-9][0-9]*\).*/\1/p')
now=$(date -u +%s)
[ -n "$dl" ] && [ "$dl" -ge $((now + 45 - 30)) ] && [ "$dl" -le $((now + 45)) ] \
  && ok "a 45s budget puts the deadline 45s past gate-ensure's start" \
  || bad "a 45s budget gave deadline '${dl:-<none>}' (now $now)"
: > "$ARM_LOG"
REFINERY_RECONCILE_GATE_BUDGET_SECS=0 drive > /dev/null
gl=$(grep '^gate-ensure' "$ARM_LOG")
hasnt "$gl" "--deadline" "a 0 budget hands gate-ensure no deadline"
has "$gl" "--cursor " "…and it still resumes from its cursor"
: > "$ARM_LOG"
REFINERY_RECONCILE_GATE_BUDGET_SECS=soon drive > /dev/null
dl=$(grep '^gate-ensure' "$ARM_LOG" | sed -n 's/.*--deadline \([0-9][0-9]*\).*/\1/p')
now=$(date -u +%s)
[ -n "$dl" ] && [ "$dl" -ge $((now + 300 - 30)) ] && [ "$dl" -le $((now + 300)) ] \
  && ok "an unparseable budget falls back to the 300s default" \
  || bad "an unparseable budget gave deadline '${dl:-<none>}' (now $now)"

echo "# gate-ensure rc=3 is reported, and holds and fails nothing"
# merge has already run when gate-ensure does, and merge.sh and pr-open.sh each
# hold an anchor with no check_set on their own read, so the rc is a report.
mkarm gate-ensure.sh 3
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 0 "an unsafe gate-ensure does not fail the order"
has "$out" "gate-ensure UNSAFE (rc=3)" "the unsafe rc is reported"
hasnt "$out" "merge.sh HELD" "…and holds no merge"
grep -q '^merge.sh' "$ARM_LOG" && ok "merge.sh ran" || bad "merge.sh did not run"
grep -q '^pr-facts.sh|--fix-pool' "$ARM_LOG" && ok "pr-facts still ran (arms are independent)" || bad "pr-facts was skipped"
mkarm gate-ensure.sh

echo "# a non-zero posture arm HOLDS merge.sh — merge validates what it records"
# merge.sh reads pr_posture off the bead and never asks GitHub, so an anchor the
# posture arm could not make current is one merge.sh would clear against a fact
# from an earlier tick.
mkarm gate-ensure.sh
cat > "$SD/pr-facts.sh" <<'ARM'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' pr-facts.sh "$*" "${BEADS_ACTOR:-}" "${GC_AGENT:-}" >> "${ARM_LOG:?}"
case "$*" in *--posture-only*) exit 1 ;; esac
exit 0
ARM
chmod +x "$SD/pr-facts.sh"
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 1 "an unrecordable posture fails the order"
has "$out" "pr-posture rc=1" "…naming the arm"
has "$out" "merge.sh HELD this pass" "…and reporting the hold"
if grep -q '^merge.sh' "$ARM_LOG"; then bad "merge.sh RAN on a posture the arm could not record"; else ok "merge.sh did not run"; fi
grep -q '^pr-facts.sh|--fix-pool' "$ARM_LOG" && ok "the full pr-facts arm still ran" || bad "the full pr-facts arm was skipped"
grep -q '^convoy-graduate' "$ARM_LOG" && ok "convoy-graduate still ran (the hold is merge's alone)" || bad "convoy-graduate was skipped"
mkarm pr-facts.sh

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
MARK="$TMP/state/myrig/merge-decision"
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
# A pr-facts whose posture arm blocks until released (its other modes record and
# return), so a pass can be caught before it has decided its merge tail.
mkblocking_posture() {
  cat > "$SD/pr-facts.sh" <<'ARM'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "pr-facts.sh" "$*" "${BEADS_ACTOR:-}" "${GC_AGENT:-}" >> "${ARM_LOG:?}"
case "$*" in *--posture-only*) : ;; *) exit 0 ;; esac
: > "${POSTURE_STARTED:?}"
i=0
while [ ! -f "${POSTURE_RELEASE:?}" ] && [ "$i" -lt 6000 ]; do sleep 0.05; i=$((i + 1)); done
ARM
  chmod +x "$SD/pr-facts.sh"
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
export POSTURE_STARTED="$TMP/posture-started" POSTURE_RELEASE="$TMP/posture-release"

echo "# a gate-ensure that never returns leaves merge and pr-open already run"
# gate-ensure visits every gating anchor, so its cost grows with the set that
# only merge drains and only pr-open advances. Model the worst case, a
# gate-ensure that does not return within the pass, and prove both already ran
# while the full pr-facts arm behind it has not.
for a in pre-open-rebase.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh scaffolding-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
mkblocking_gate
rm -f "$GATE_STARTED" "$GATE_RELEASE"
: > "$ARM_LOG"
drive > /dev/null 2>&1 &
dG=$!
if await "$GATE_STARTED"; then
  grep -q '^merge.sh' "$ARM_LOG" \
    && ok "merge ran before the blocked gate-ensure — a budget spent there cannot starve it" \
    || bad "merge had NOT run when gate-ensure blocked — merge is still behind it"
  grep -q '^pr-open' "$ARM_LOG" \
    && ok "pr-open ran before the blocked gate-ensure — a green branch still reaches the operator" \
    || bad "pr-open had NOT run when gate-ensure blocked"
  if grep -q '^pr-facts.sh|--fix-pool' "$ARM_LOG"; then bad "the full pr-facts arm ran ahead of gate-ensure (order wrong)"; else ok "the full pr-facts arm sits behind gate-ensure"; fi
  : > "$GATE_RELEASE"
  wait "$dG"
else
  bad "the pass never reached its gate-ensure arm (fixture wedged)"
  : > "$GATE_RELEASE"; wait "$dG" 2>/dev/null
fi

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

echo "# a pass killed before its merge decision leaves its partial output behind"
await_lock_free || bad "the lock test's pass never released the lock"
mkarm gate-ensure.sh
mkblocking_posture
rm -f "$PASSLOG" "$MARK" "$POSTURE_STARTED" "$POSTURE_RELEASE"
: > "$ARM_LOG"
# Launch the driver directly, not through the drive() function. Backgrounding a
# function forks a wrapper subshell, so $! names the wrapper and `kill` below
# would leave the real driver orphaned — and the POSTURE_RELEASE written right
# after the kill would then let that orphan run on to `decided`, defeating this
# very check. A backgrounded simple command makes $! the driver, so the kill
# lands.
GC_RIG=myrig GC_RIG_ROOT="$TMP" "$SD/refinery-reconcile.sh" > /dev/null 2>&1 &
d2=$!
if await "$POSTURE_STARTED"; then
  kill -9 "$d2" 2>/dev/null
  wait "$d2" 2>/dev/null
  # Read the log before releasing the arm: the posture arm runs in a subshell
  # that outlives the killed driver, and once released it would log its own
  # done line, which is the very line this case asserts is absent.
  grep -q '^=== .*rig=myrig' "$PASSLOG" \
    && ok "the killed pass left its header in pass.log" \
    || bad "the killed pass left no header — an overrun is invisible again"
  grep -q '^-- (1) pr-posture (started ' "$PASSLOG" \
    && ok "…and the start of the arm it died in" \
    || bad "…but not the arm it died in"
  grep -q '^-- (1) pr-posture: done' "$PASSLOG" \
    && bad "the arm the pass died in logged a done line" \
    || ok "…with no done line, so the arm it died in is legible"
  grep -q '^END ' "$PASSLOG" \
    && bad "the killed pass wrote an END line — a kill is indistinguishable from a clean exit" \
    || ok "no END line, so the kill is legible as an unfinished pass"
  # A pass killed before it decides its merge tail rests at a pre-decision phase:
  # `started` if killed before the merge arm, `reached` if killed inside it.
  # merge-tail-report.sh reads both as a dropped tail; only `decided`/`held` (or
  # an empty marker) would mean the pass was not caught before deciding.
  read -r kph _ < "$MARK" 2>/dev/null || kph=""
  case "$kph" in
    started|reached) ok "the killed pass left its merge-decision marker at a pre-decision phase ('$kph')" ;;
    *) bad "the killed pass left its marker at '${kph:-<empty>}', not a pre-decision phase — it was not caught before deciding its tail" ;;
  esac
  : > "$POSTURE_RELEASE"
else
  bad "the pass to be killed never reached its posture arm (fixture wedged)"
  : > "$POSTURE_RELEASE"; wait "$d2" 2>/dev/null
fi
mkarm pr-facts.sh

echo "# a pass killed in gate-ensure has already decided its merge tail"
await_lock_free || bad "the posture-killed pass's arm never released the lock"
mkblocking_gate
rm -f "$PASSLOG" "$MARK" "$GATE_STARTED" "$GATE_RELEASE"
: > "$ARM_LOG"
GC_RIG=myrig GC_RIG_ROOT="$TMP" "$SD/refinery-reconcile.sh" > /dev/null 2>&1 &
d4=$!
if await "$GATE_STARTED"; then
  kill -9 "$d4" 2>/dev/null
  wait "$d4" 2>/dev/null
  read -r gph _ < "$MARK" 2>/dev/null || gph=""
  eq "$gph" "decided" "a pass killed in gate-ensure left its marker at 'decided' — no dropped merge tail to report"
  grep -q '^-- (2) merge: done in [0-9]*s (rc=0)$' "$PASSLOG" \
    && ok "…and the merge arm's done line is in pass.log" \
    || bad "the merge arm left no done line before the kill"
  grep -q '^-- (6) gate-ensure (started ' "$PASSLOG" \
    && ok "…and gate-ensure's start line names the arm the pass died in" \
    || bad "gate-ensure left no start line"
  : > "$GATE_RELEASE"
else
  bad "the pass to be killed never reached its gate-ensure arm (fixture wedged)"
  : > "$GATE_RELEASE"; wait "$d4" 2>/dev/null
fi

echo "# the merge-decision marker tracks a clean pass to 'decided', and the report runs at pass start"
# The killed pass above orphaned its gate-ensure arm, which holds the pass lock
# until it exits. Wait for the lock to free first, or this pass reads it as
# already in flight and skips — running no arms, no marker, and no report.
await_lock_free || bad "the killed pass's arm never released the lock before the clean pass"
for a in gate-ensure.sh pre-open-rebase.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh scaffolding-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
# A report stub records how the driver invoked it. It is created only for this
# case and removed after, so the surrounding cases run with the report absent
# (the driver's [ -x ] guard skips it) exactly as they did before.
cat > "$SD/merge-tail-report.sh" <<'RPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${REPORT_LOG:?}"
exit 0
RPT
chmod +x "$SD/merge-tail-report.sh"
export REPORT_LOG="$TMP/report.log"; : > "$REPORT_LOG"
rm -f "$MARK"
out=$(drive); rc=$?
eq "$rc" 0 "a clean pass exits 0 with the marker wired in"
read -r cph _ < "$MARK" 2>/dev/null || cph=""
eq "$cph" "decided" "a clean pass leaves the merge-decision marker at 'decided'"
has "$(cat "$REPORT_LOG")" "--marker $MARK --rig myrig" "the drop-tail report is invoked at pass start with the marker path and rig"
# The report runs BEFORE this pass overwrites the marker: it must see the prior
# value, so it is called before the header's own arms advance the phase.
rm -f "$SD/merge-tail-report.sh"
unset REPORT_LOG

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
GATE="$(awk '/# >>> posture-gates-merge/{f=1;next} /# <<< posture-gates-merge/{f=0} f' "$RUNNER")"
[ -n "$GATE" ] && ok "posture-gates-merge block extracted" || bad "posture-gates-merge markers missing"
hasnt "$GATE" '{{' "the block is template-free (executable verbatim)"
hasnt "$GATE" 'gate-ensure.sh' "gate-ensure is outside the block: merge needs nothing it writes in the same pass"
GSD="$TMP/gsd"; mkdir -p "$GSD"
# The block runs the posture arm and merge, and nothing else; the stub records a
# token per pr-facts mode so an arm that crept into the block would show.
cat > "$GSD/pr-facts.sh" <<'PF'
#!/usr/bin/env bash
case "$*" in
  *--posture-only*)        echo posture  >> "${BLOCK_SENTINEL:?}" ;;
  *--route-comments-only*) echo feedback >> "${BLOCK_SENTINEL:?}" ;;
  *)                       echo facts    >> "${BLOCK_SENTINEL:?}" ;;
esac
PF
printf '#!/usr/bin/env bash\necho ran >> "${MERGE_SENTINEL:?}"\necho merge >> "${BLOCK_SENTINEL:?}"\n' > "$GSD/merge.sh"
chmod +x "$GSD"/*.sh
export MERGE_SENTINEL="$TMP/merge-ran"; : > "$MERGE_SENTINEL"
export BLOCK_SENTINEL="$TMP/block-order"; : > "$BLOCK_SENTINEL"
# The block writes the merge-decision marker through mark_merge; the prologue
# supplies it (a real one appending each phase, so the marks are assertable).
export MARK_LOG="$TMP/mark-log"; : > "$MARK_LOG"
{
  printf 'set -u\nSCRIPTS_DIR=%q\nLOG_SINK=""\nNOTED=""\nFAILED=""\n' "$GSD"
  printf 'AGENT=%q\nSTATE_DIR=%q\nMERGE_BUDGET_SECS=120\n' 'myrig/gc-toolkit.refinery' "$TMP/gsd-state"
  printf 'MARK_LOG=%q\nmark_merge() { printf "%%s\\n" "$1" >> "$MARK_LOG"; }\n' "$MARK_LOG"
  printf '%s\n' "$GATE"
  printf 'echo "MERGE_HELD=$MERGE_HELD"\n'
} > "$TMP/gaterun.sh"
: > "$MARK_LOG"
gout=$(bash "$TMP/gaterun.sh" 2>/dev/null)
[ -s "$MERGE_SENTINEL" ] && ok "(block) a recorded posture lets merge.sh run" || bad "(block) merge.sh did not run after a recorded posture"
has "$gout" "MERGE_HELD=0" "(block) the hold flag is clear"
eq "$(paste -sd, - < "$BLOCK_SENTINEL")" "posture,merge" "(block) the posture is recorded, then merge reads it, with nothing between them"
eq "$(paste -sd, - < "$MARK_LOG")" "reached,decided" "(block) a run marks 'reached' before merge and 'decided' after"

# The posture arm's rc is the interlock: merge.sh validates the posture this arm
# records, so an arm that could not record one must not be followed by a merge
# in the same pass.
cat > "$GSD/pr-facts.sh" <<'PF'
#!/usr/bin/env bash
case "$*" in
  *--posture-only*) echo posture >> "${BLOCK_SENTINEL:?}"; exit 1 ;;
  *)                echo other   >> "${BLOCK_SENTINEL:?}"; exit 0 ;;
esac
PF
: > "$MERGE_SENTINEL"; : > "$BLOCK_SENTINEL"; : > "$MARK_LOG"
gout=$(bash "$TMP/gaterun.sh" 2>/dev/null)
[ -s "$MERGE_SENTINEL" ] && bad "(block) merge.sh RAN despite an unrecordable posture" || ok "(block) a non-zero posture arm held merge.sh"
has "$gout" "MERGE_HELD=1" "(block) the hold flag is set by the posture arm"
eq "$(paste -sd, - < "$MARK_LOG")" "held" "(block) a posture-held merge marks 'held', not a drop"

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
# The other end of the same budget. The runner calls a lock held past
# LOCK_STALL_SECS a wedge and says nothing is landing — true of an abandoned fd,
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
has "$o" 'scope = "rig"' "order is rig-scoped (single-flight per rig)"
has "$o" 'refinery-reconcile.sh' "order execs this runner"
if grep -qE '^[[:space:]]*no_work_gate' "$ORDER"; then
  bad "no_work_gate must never be set (it opts out of the single-flight gate)"
else
  ok "no_work_gate is not set"
fi

echo "# REFINERY_RECONCILE_REVIEW_FORMULA opts reviews into the two-lane quorum pilot"
for a in gate-ensure.sh pre-open-rebase.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh scaffolding-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
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
# The driver only enables the cache when it can source bd-lib (so run_pass can
# clear it between arms); the SD above has no copy, which is why every drive()
# before this ran uncached. Put one beside the runner so the wiring activates.
cp "$HERE/bd-lib.sh" "$SD/bd-lib.sh"
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
for a in pre-open-rebase.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh scaffolding-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
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
