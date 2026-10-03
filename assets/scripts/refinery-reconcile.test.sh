#!/usr/bin/env bash
# Hermetic test for assets/scripts/refinery-reconcile.sh — the merge-cadence
# driver. Covers: GC_RIG required; refinery discovery + pool derivation;
# the arm ORDER (gate-ensure, pr-facts --posture-only, pr-facts
# --route-comments-only, merge, pre-open-rebase, pr-open, pr-facts,
# convoy-graduate, review-sweep, duplicate-sweep, pr-stack) — merge runs AHEAD of
# pre-open-rebase and pr-open, whose per-anchor GitHub round-trips over the
# pre_open_gate backlog would otherwise starve it of the pass budget; its only
# same-pass interlocks run before it — the posture arm, which merge.sh reads off
# the bead and would otherwise read one written a pass ago, and the feedback arm,
# so a pass killed at the tail has still routed operator feedback;
# the heal-gates-merge interlock (rc=3 from gate-ensure HOLDS merge.sh in the
# merge because the same pass must not fail the order; a non-zero posture arm holds it too,
# because merge.sh validates the posture that arm records), exercised by
# extracting and executing the marked block against stubs; BEADS_ACTOR /
# GC_AGENT projections scoped to their arms; a failing arm not skipping the
# arms after it; the exit-1 failure report; the per-rig pass lock (one merge.sh
# writer across two overlapping ticks, a wedged holder reported rather than
# skipped over, an unobtainable lock refusing the pass before any arm); a
# killed pass leaving its partial output in pass.log; and the invariant binding
# the order timeout to the controller's tracking-sweep window.
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
# The runner sources single-flight.sh (the per-rig pass lock) by sibling path at
# startup, so it must sit beside the SUT for every invocation below.
cp "$HERE/single-flight.sh" "$SD/single-flight.sh"
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
for a in gate-ensure.sh pre-open-rebase.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 0 "a clean pass exits 0"
order=$(cut -d'|' -f1 "$ARM_LOG" | paste -sd, -)
eq "$order" "gate-ensure.sh,pr-facts.sh,pr-facts.sh,merge.sh,pre-open-rebase.sh,pr-open.sh,pr-facts.sh,convoy-graduate.sh,review-sweep.sh,duplicate-sweep.sh,pr-stack.sh" "the arms ran in the load-bearing order (posture + feedback before merge, merge ahead of pre-open-rebase and pr-open, full pr-facts after)"
dup_line=$(grep '^duplicate-sweep' "$ARM_LOG")
has "$dup_line" "|myrig/gc-toolkit.refinery|" "duplicate-sweep ran as BEADS_ACTOR=<refinery>"
# pr-stack writes PR bodies and no bead, so it carries neither projection: an
# identity it does not need is authority it must not be able to spend.
stack_line=$(grep '^pr-stack' "$ARM_LOG")
eq "$stack_line" "pr-stack.sh|||" "pr-stack ran last, unprojected and with no args"
has "$(grep '^gate-ensure' "$ARM_LOG")" "--default correctness,triage --review-pool myrig/gc-toolkit.polecat-codex --fix-pool myrig/gc-toolkit.polecat --validate-pool myrig/gc-toolkit.polecat" "gate-ensure got the default + derived review, fix AND validate pools"
hasnt "$(grep '^gate-ensure' "$ARM_LOG")" "--review-formula" "gate-ensure gets no --review-formula by default (the two-lane quorum pilot is opt-in)"
has "$(grep '^pre-open-rebase' "$ARM_LOG")" "--fix-pool myrig/gc-toolkit.polecat" "pre-open-rebase got the derived fix pool"
case "$(grep '^pre-open-rebase' "$ARM_LOG")" in
  *"|myrig/gc-toolkit.refinery|"*) bad "pre-open-rebase must NOT inherit BEADS_ACTOR (it closes nothing)" ;;
  *) ok "pre-open-rebase ran without the BEADS_ACTOR projection" ;;
esac
merge_line=$(grep '^merge.sh' "$ARM_LOG")
has "$merge_line" "|myrig/gc-toolkit.refinery|" "merge.sh ran as BEADS_ACTOR=<refinery>"
# The full pr-facts arm: --fix-pool and no pre-merge mode flag (the posture arm
# carries neither, the feedback arm carries --route-comments-only).
facts_line=$(grep '^pr-facts' "$ARM_LOG" | grep -- '--fix-pool' | grep -v -- '--route-comments-only')
eq "$(printf '%s\n' "$facts_line" | wc -l | tr -d ' ')" 1 "the full pr-facts arm ran exactly once"
has "$facts_line" "--fix-pool myrig/gc-toolkit.polecat" "pr-facts got the derived fix pool"
hasnt "$facts_line" "--review-pool" "…and no review pool: it dispatches no reviews"
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

# The early feedback arm routes operator feedback before merge, so a pass killed
# at the tail (before the full pr-facts arm) has still picked it up. It carries a
# fix pool (it dispatches rework children) but the --route-comments-only flag.
route_line=$(grep '^pr-facts' "$ARM_LOG" | grep -- '--route-comments-only')
eq "$(printf '%s\n' "$route_line" | wc -l | tr -d ' ')" 1 "the feedback arm ran exactly once"
has "$route_line" "--fix-pool myrig/gc-toolkit.polecat" "the feedback arm got the derived fix pool"
has "$route_line" "|myrig/gc-toolkit.refinery|" "the feedback arm ran as BEADS_ACTOR=<refinery>"
route_at=$(grep -n '^pr-facts.*--route-comments-only' "$ARM_LOG" | head -1 | cut -d: -f1)
[ -n "$posture_at" ] && [ -n "$route_at" ] && [ "$posture_at" -lt "$route_at" ] \
  && ok "the feedback arm runs after the posture arm" \
  || bad "feedback arm did not run after posture (posture=$posture_at route=$route_at)"
[ -n "$route_at" ] && [ -n "$merge_at" ] && [ "$route_at" -lt "$merge_at" ] \
  && ok "the feedback arm routes BEFORE merge (a tail-killed pass has still picked feedback up)" \
  || bad "feedback arm did not run before merge (route=$route_at merge=$merge_at)"
# merge runs AHEAD of pre-open-rebase and pr-open — those two iterate the
# pre_open_gate backlog with a GitHub round-trip per anchor, and a grown held
# backlog let their cost consume the whole 600s budget before merge was reached,
# so approved CLEAN PRs never landed. This ordering is the fix: gate-ensure and
# posture are merge's only same-pass interlocks, so nothing merge does not need
# may sit between them and it.
preopen_at=$(grep -n '^pre-open-rebase' "$ARM_LOG" | head -1 | cut -d: -f1)
propen_at=$(grep -n '^pr-open' "$ARM_LOG" | head -1 | cut -d: -f1)
[ -n "$merge_at" ] && [ -n "$preopen_at" ] && [ "$merge_at" -lt "$preopen_at" ] \
  && ok "merge runs BEFORE pre-open-rebase (not starved by the pre_open_gate backlog)" \
  || bad "merge did not run before pre-open-rebase (merge=$merge_at preopen=$preopen_at)"
[ -n "$merge_at" ] && [ -n "$propen_at" ] && [ "$merge_at" -lt "$propen_at" ] \
  && ok "merge runs BEFORE pr-open (not starved by the pre_open_gate backlog)" \
  || bad "merge did not run before pr-open (merge=$merge_at propen=$propen_at)"
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
# A pre-open-rebase that blocks until released — a post-merge backlog arm that
# does not return within the pass, used to prove merge already ran ahead of it.
mkblocking_preopen() {
  cat > "$SD/pre-open-rebase.sh" <<'ARM'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "pre-open-rebase.sh" "$*" "${BEADS_ACTOR:-}" "${GC_AGENT:-}" >> "${ARM_LOG:?}"
: > "${PREOPEN_STARTED:?}"
i=0
while [ ! -f "${PREOPEN_RELEASE:?}" ] && [ "$i" -lt 6000 ]; do sleep 0.05; i=$((i + 1)); done
ARM
  chmod +x "$SD/pre-open-rebase.sh"
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
export PREOPEN_STARTED="$TMP/preopen-started" PREOPEN_RELEASE="$TMP/preopen-release"

echo "# merge reaches its arm before a slow pre_open_gate-backlog arm spends the budget"
# The landing stall this ordering fixes: pre-open-rebase and pr-open iterate the
# pre_open_gate backlog with a GitHub round-trip per anchor, and a grown backlog
# spent the whole 600s pass budget before merge ran, so approved CLEAN PRs never
# landed. With merge ahead of them, a pass whose budget is exhausted inside those
# arms has already merged. Model the worst case — a backlog arm that does not
# return within the pass — by blocking pre-open-rebase and proving merge already
# ran while pr-open (the other backlog arm) has not.
for a in gate-ensure.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
mkblocking_preopen
rm -f "$PREOPEN_STARTED" "$PREOPEN_RELEASE"
: > "$ARM_LOG"
drive > /dev/null 2>&1 &
dP=$!
if await "$PREOPEN_STARTED"; then
  grep -q '^merge.sh' "$ARM_LOG" \
    && ok "merge ran before the blocked backlog arm — a budget spent there cannot starve it" \
    || bad "merge had NOT run when pre-open-rebase blocked — merge is still behind the backlog arm"
  if grep -q '^pr-open' "$ARM_LOG"; then bad "pr-open ran before the blocked pre-open-rebase (order wrong)"; else ok "pr-open has not run — the backlog arms sit after merge"; fi
  : > "$PREOPEN_RELEASE"
  wait "$dP"
else
  bad "the pass never reached its pre-open-rebase arm (fixture wedged)"
  : > "$PREOPEN_RELEASE"; wait "$dP" 2>/dev/null
fi
mkarm pre-open-rebase.sh   # restore the non-blocking stub for the tests below

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
rm -f "$PASSLOG" "$MARK" "$GATE_STARTED" "$GATE_RELEASE"
: > "$ARM_LOG"
# Launch the driver directly, not through the drive() function. Backgrounding a
# function forks a wrapper subshell, so $! names the wrapper and `kill` below
# would leave the real driver orphaned — and the GATE_RELEASE written right after
# the kill would then let that orphan run on to `decided`, defeating this very
# check. A backgrounded simple command makes $! the driver, so the kill lands.
GC_RIG=myrig GC_RIG_ROOT="$TMP" "$SD/refinery-reconcile.sh" > /dev/null 2>&1 &
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
  # A pass killed before it decides its merge tail rests at a pre-decision phase:
  # `started` if killed before the merge arm, `reached` if killed inside it.
  # merge-tail-report.sh reads both as a dropped tail; only `decided`/`held` (or
  # an empty marker) would mean the pass was not caught before deciding.
  read -r kph _ < "$MARK" 2>/dev/null || kph=""
  case "$kph" in
    started|reached) ok "the killed pass left its merge-decision marker at a pre-decision phase ('$kph')" ;;
    *) bad "the killed pass left its marker at '${kph:-<empty>}', not a pre-decision phase — it was not caught before deciding its tail" ;;
  esac
else
  bad "the pass to be killed never reached its gate-ensure arm (fixture wedged)"
  : > "$GATE_RELEASE"; wait "$d2" 2>/dev/null
fi

echo "# the merge-decision marker tracks a clean pass to 'decided', and the report runs at pass start"
# The killed pass above orphaned its gate-ensure arm, which holds the pass lock
# until it exits. Wait for the lock to free first, or this pass reads it as
# already in flight and skips — running no arms, no marker, and no report.
await_lock_free || bad "the killed pass's arm never released the lock before the clean pass"
for a in gate-ensure.sh pre-open-rebase.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
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
GATE="$(awk '/# >>> heal-gates-merge/{f=1;next} /# <<< heal-gates-merge/{f=0} f' "$RUNNER")"
[ -n "$GATE" ] && ok "heal-gates-merge block extracted" || bad "heal-gates-merge markers missing"
hasnt "$GATE" '{{' "the block is template-free (executable verbatim)"
GSD="$TMP/gsd"; mkdir -p "$GSD"
printf '#!/usr/bin/env bash\nexit 3\n' > "$GSD/gate-ensure.sh"
# The block runs gate-ensure, the two pre-merge pr-facts modes and merge; pr-open
# and pre-open-rebase are outside it now (they run after merge), so it stubs
# neither. pr-facts is invoked twice in the block — --posture-only, then
# --route-comments-only — so the stub records a token per mode.
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
  printf 'AGENT=%q\nCHECK_SET_DEFAULT=%q\nREVIEW_POOL=%q\nFIX_POOL=%q\nVALIDATE_POOL=%q\n' \
    'myrig/gc-toolkit.refinery' correctness 'myrig/p-correctness' 'myrig/p' 'myrig/p'
  printf 'MARK_LOG=%q\nmark_merge() { printf "%%s\\n" "$1" >> "$MARK_LOG"; }\n' "$MARK_LOG"
  printf '%s\n' "$GATE"
  printf 'echo "MERGE_HELD=$MERGE_HELD"\n'
} > "$TMP/gaterun.sh"
: > "$MARK_LOG"
gout=$(bash "$TMP/gaterun.sh" 2>/dev/null)
[ -s "$MERGE_SENTINEL" ] && bad "(block) merge.sh RAN despite rc=3" || ok "(block) rc=3 held merge.sh"
has "$gout" "MERGE_HELD=1" "(block) the hold flag is set"
eq "$(paste -sd, - < "$MARK_LOG")" "held" "(block) a held merge marks the decision 'held', not a drop"
# Recording a fact is not a dispatch: a held merge still gets a fresh posture,
# so the pass that finally merges is not reading a stale one. The feedback arm
# runs under the hold too — routing operator feedback does not wait on merge.
has "$(cat "$BLOCK_SENTINEL")" "posture" "(block) the posture arm runs even when merge is HELD"
has "$(cat "$BLOCK_SENTINEL")" "feedback" "(block) the feedback arm runs even when merge is HELD"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GSD/gate-ensure.sh"
: > "$MERGE_SENTINEL"; : > "$BLOCK_SENTINEL"; : > "$MARK_LOG"
gout=$(bash "$TMP/gaterun.sh" 2>/dev/null)
[ -s "$MERGE_SENTINEL" ] && ok "(block) a clean gate-ensure lets merge.sh run" || bad "(block) merge.sh did not run after a clean gate-ensure"
has "$gout" "MERGE_HELD=0" "(block) the hold flag is clear"
eq "$(paste -sd, - < "$BLOCK_SENTINEL")" "posture,feedback,merge" "(block) posture and feedback both run, in that order, before merge reads posture"
eq "$(paste -sd, - < "$MARK_LOG")" "reached,decided" "(block) a run marks 'reached' before merge and 'decided' after"

# The posture arm's rc is the second half of the same interlock: merge.sh
# validates the posture this arm records, so an arm that could not record one
# must not be followed by a merge in the same pass.
# Only the posture arm fails here; the feedback arm exits 0, so the hold under
# test is unambiguously the posture arm's.
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
for a in gate-ensure.sh pre-open-rebase.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
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
for a in pre-open-rebase.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh review-sweep.sh duplicate-sweep.sh pr-stack.sh; do mkarm "$a"; done
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
