#!/usr/bin/env bash
# refinery-reconcile — one pass of the merge cadence over this rig's queue.
# Driven by orders/refinery-reconcile.toml (cooldown 60s, scope=rig): the
# controller supplies the loop, cwd = the rig root, and the env (GC_RIG,
# GC_PACK_STATE_DIR, gh token).
# Arms, in order: pr-facts --posture-only (BEADS_ACTOR projected to the
# refinery so its records are attributed to it), pr-facts
# --route-comments-only (route operator feedback ahead of the slow arms, so a
# pass killed before the full arm has still picked it up; BEADS_ACTOR
# projected), gate-ensure, pr-facts (same projection), review-sweep (cleanup
# over closed anchors; no projection), scaffolding-sweep (retires
# validation/finding/rework on a disposed anchor; BEADS_ACTOR projected: it
# closes a finding it carries forward through bead-rehome).
# The arms that walk a set growing with the queue share the pass budget (see
# PASS_BUDGET_SECS and PACED_ARMS below): pr-feedback, gate-ensure and
# pr-facts. A PR lands through the landing order, never through this cadence.
# Single-flight is the per-rig flock below, NOT the controller's open-tracking
# gate: the controller watchdog closes any tracking bead older than 2m, which
# reopens that gate under a pass still running.
# No loop or sleep here — do NOT add one, and never re-create an out-of-band
# driver (docs/refinery-merge-cadence.md).
# NOT set -e / pipefail: arms are independent; a failing arm must not skip the
# rest, and the next cooldown retries everything.
set -u

PROG="refinery-reconcile"

# Rig identity comes from the order runner; guessing would run one rig's arms
# against another rig's store.
RIG="${GC_RIG:-}"
if [ -z "$RIG" ]; then
  echo "$PROG: GC_RIG is unset — this runs as a scope=\"rig\" order and has no rig to reconcile" >&2
  exit 2
fi
# Siblings resolve from $0: the pack lives under the owning rig, so an importer
# rig's own root has no assets/scripts at all.
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# The pass lock, pass_child and the per-pass bd_list cache. Unsourceable,
# nothing serialises the arms, so none runs.
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script — refusing to run any arm without the pass lock" >&2; exit 1; }

# Refinery identity by discovery; FIX/REVIEW pools share its binding prefix so
# a rename cannot split them.
resolve_refinery() {
  local found
  found="$(gc agent list --json 2>/dev/null \
    | jq -r --arg rig "$RIG" '.agents[]? | .qualified_name // empty
        | select(startswith($rig + "/")) | select(endswith("refinery"))' 2>/dev/null | head -1)"
  if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
  if [ -n "${GC_PACK_NAME:-}" ]; then printf '%s/%s.refinery' "$RIG" "$GC_PACK_NAME"; return 0; fi
  return 1
}
AGENT="${REFINERY_RECONCILE_AGENT:-$(resolve_refinery)}"
if [ -z "$AGENT" ]; then
  echo "${PROG}[$RIG]: no refinery agent bound for this rig; nothing to reconcile"
  exit 0
fi
BINDING_PREFIX="${AGENT#"$RIG"/}"
BINDING_PREFIX="${BINDING_PREFIX%refinery}"
FIX_POOL="$RIG/${BINDING_PREFIX}polecat"
REVIEW_POOL="$RIG/${BINDING_PREFIX}polecat-codex"
# mol-validate is a judgment pass — it rules a review's findings, it does not
# re-review — so it defaults to the general claude worker pool where fix units
# land, not REVIEW_POOL (the codex pool the merge cadence routes mol-review to).
# A rig that staffs a dedicated validate pool points this there without an edit.
VALIDATE_POOL="${REFINERY_RECONCILE_VALIDATE_POOL:-$FIX_POOL}"
CHECK_SET_DEFAULT="${REFINERY_RECONCILE_CHECK_SET:-correctness,triage}"
# The pass budget, in seconds (0 = unpaced). Every arm that walks a set growing
# with the queue is paced: past its deadline it starts no new anchor, and the
# next pass resumes after the last one it finished (a cursor in the state dir).
# Each paced arm's deadline is an equal share of the time the pass budget has
# left when the arm starts, and never less than ARM_FLOOR_SECS, so an arm that
# finishes early leaves its time to the arms behind it, and every arm runs on
# every pass. The budget sits below the order's timeout, so a pass ends and
# writes END instead of being killed. The posture record is never paced: it
# reads every open PR in one batched call.
PASS_BUDGET_SECS="${REFINERY_RECONCILE_PASS_BUDGET_SECS:-420}"
case "$PASS_BUDGET_SECS" in ''|*[!0-9]*) PASS_BUDGET_SECS=420 ;; esac
PASS_BUDGET_SECS=$((10#$PASS_BUDGET_SECS))
ARM_FLOOR_SECS="${REFINERY_RECONCILE_ARM_FLOOR_SECS:-20}"
case "$ARM_FLOOR_SECS" in ''|*[!0-9]*) ARM_FLOOR_SECS=20 ;; esac
ARM_FLOOR_SECS=$((10#$ARM_FLOOR_SECS))

# Review dispatch formula (two-lane pilot). Default mol-review — the
# single-agent lifecycle. Opt into the quorum by setting
# REFINERY_RECONCILE_REVIEW_FORMULA=mol-review-quorum-signoff: reviews then run
# as two provider lanes (codex + claude by default) plus a synthesizer that
# makes the single signoff. Reverting is unsetting the env — no code change.
# Lane config is constant across the pass; gate-ensure passes each review's own
# values, its base among them, as vars on that review's sling.
REVIEW_FORMULA="${REFINERY_RECONCILE_REVIEW_FORMULA:-mol-review}"
GATE_REVIEW_FORMULA_ARGS=()
if [ "$REVIEW_FORMULA" != "mol-review" ]; then
  GATE_REVIEW_FORMULA_ARGS=(
    --review-formula "$REVIEW_FORMULA"
    --sling-var "lane_one_id=${REFINERY_RECONCILE_LANE_ONE_ID:-codex}"
    --sling-var "lane_one_provider=${REFINERY_RECONCILE_LANE_ONE_PROVIDER:-codex}"
    --sling-var "lane_one_target=${REFINERY_RECONCILE_LANE_ONE_TARGET:-$REVIEW_POOL}"
    --sling-var "lane_two_id=${REFINERY_RECONCILE_LANE_TWO_ID:-claude}"
    --sling-var "lane_two_provider=${REFINERY_RECONCILE_LANE_TWO_PROVIDER:-claude}"
    --sling-var "lane_two_target=${REFINERY_RECONCILE_LANE_TWO_TARGET:-$FIX_POOL}"
    --sling-var "synthesis_target=${REFINERY_RECONCILE_SYNTHESIS_TARGET:-$FIX_POOL}"
  )
fi

# Per-rig state (GC_PACK_STATE_DIR is city+pack scoped; this order runs per rig).
# The key also names the pass lock below, so every version of this driver must
# derive it the same way. A deploy can start a new driver while the one it
# replaces is still running a pass, and the two passes stay apart only on one
# lock file. bd-lib.sh's rig_state_key is not this key: it cuts a rig name past
# 64 bytes and adds a checksum to any name it rewrites.
RIG_KEY="$(printf '%s' "$RIG" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
case "$RIG_KEY" in ''|.|..) RIG_KEY=rig ;; esac
STATE_DIR="${REFINERY_RECONCILE_STATE_DIR:-${GC_PACK_STATE_DIR:-${TMPDIR:-/tmp}/gc}/refinery-reconcile}/$RIG_KEY"
LOG="$STATE_DIR/pass.log"
LOG_KEEP="${REFINERY_RECONCILE_LOG_KEEP:-2000}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
# Arms append to the log as they run, so a pass the controller kills at its
# timeout still leaves its output behind. An unwritable state dir empties
# LOG_SINK, never LOG, so a failure report can still name the path it wanted.
LOG_SINK="$LOG"
( : >> "$LOG" ) 2>/dev/null || LOG_SINK=""
TICK="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PASS_T0="$(date -u +%s)"
FAILED=""
NOTED=""

# Two passes writing one rig's anchors at once is the failure this cadence must
# never produce, and the controller's open-tracking gate does not prevent it:
# the watchdog closes tracking beads at 2m, well inside the order's timeout,
# and an un-gated tracking bead is a second dispatch. bd-lib.sh's pass lock
# depends on no bead surviving. The driver holds it, and each arm runs through
# pass_child, from a subshell that holds it until the arm exits, so the lock is
# held for exactly as long as a writer is live. The arm itself runs without the
# lock's descriptor: an arm's store read can bring up a Dolt server that outlives
# the pass, and a server that kept the descriptor would hold the lock against
# every later pass.
# A holder older than this is not a slow pass, because the order's timeout stops
# the pass's whole process group well before it: a driver run by hand, or an
# arm still running after its driver was killed by itself, holds the lock.
# The arms have stopped, so it is reported, not skipped over.
LOCK_STALL_SECS="${REFINERY_RECONCILE_LOCK_STALL_SECS:-900}"
case "$LOCK_STALL_SECS" in ''|*[!0-9]*) LOCK_STALL_SECS=900 ;; esac
LOCK_STALL_SECS=$((10#$LOCK_STALL_SECS))
lock_rc=0
take_pass_lock "$STATE_DIR" "$LOCK_STALL_SECS" || lock_rc=$?
case "$lock_rc" in
  0) ;;
  1)
    [ -n "$LOG_SINK" ] && printf -- '--- %s rig=%s SKIPPED: pass already in flight (%s)\n' \
      "$TICK" "$RIG" "$LOCK_NOTE" >> "$LOG_SINK"
    echo "${PROG}[$RIG]: a pass is already in flight ($LOCK_NOTE) — skipping this tick"
    exit 0 ;;
  2)
    [ -n "$LOG_SINK" ] && printf -- '--- %s rig=%s STALLED: pass lock held past %ss (%s)\n' \
      "$TICK" "$RIG" "$LOCK_STALL_SECS" "$LOCK_NOTE" >> "$LOG_SINK"
    echo "${PROG}[$RIG]: pass lock held past ${LOCK_STALL_SECS}s ($LOCK_NOTE) — the cadence is wedged and no arm is running"
    echo "${PROG}[$RIG]: pass log: $LOG"
    exit 1 ;;
  *)
    # The lock is the whole of single-flight, so an unavailable one leaves nothing
    # serialising the arms. Running them anyway is the second writer this driver
    # exists to prevent.
    [ -n "$LOG_SINK" ] && printf -- '--- %s rig=%s UNGUARDED: %s; no arm ran\n' \
      "$TICK" "$RIG" "$LOCK_NOTE" >> "$LOG_SINK"
    echo "${PROG}[$RIG]: single-flight UNGUARDED ($LOCK_NOTE) — refusing to run any arm without the pass lock"
    echo "${PROG}[$RIG]: pass log: $LOG"
    exit 1 ;;
esac

# The controller keeps combined output only on a non-zero exit, so the log is
# where a healthy pass is readable and the exit code is the alarm. The header
# goes down before the first arm runs; the END line below closes it, so a
# header with no END under it is a pass that was killed.
[ -n "$LOG_SINK" ] && printf '=== %s rig=%s refinery=%s\n' "$TICK" "$RIG" "$AGENT" >> "$LOG_SINK"

# Per-pass bd_list cache (assets/scripts/bd-lib.sh). The arms re-issue the same
# `gc bd list` many times a pass, and each call is seconds of server wait.
# GC_RECONCILE_BD_CACHE points bd_list at a directory it serves a repeat from;
# run_pass clears it before every arm so no arm reads another's rows, and it is
# removed at END. A killed pass leaves it behind, so setup is rm-then-create. A
# cache dir that cannot be made leaves the pass uncached (the cache is an
# optimization, never a correctness input).
CACHE_DIR="$STATE_DIR/cache"
rm -rf "$CACHE_DIR" 2>/dev/null || true
if mkdir -p "$CACHE_DIR" 2>/dev/null; then
  export GC_RECONCILE_BD_CACHE="$CACHE_DIR"
fi

note() { NOTED="${NOTED}$*"$'\n'; }
log()  { [ -n "$LOG_SINK" ] && printf '%s\n' "$*" >> "$LOG_SINK"; return 0; }
run_pass() { # <label> <script> [args...]
  local label="$1" script="$2"; shift 2
  if [ ! -x "$SCRIPTS_DIR/$script" ]; then
    log "-- $label: SKIPPED (no $SCRIPTS_DIR/$script)"
    return 0
  fi
  # Each arm is bracketed by its start time and, once it returns, its elapsed
  # seconds and rc, so the log shows which arm a slow pass spent its budget in.
  # An arm the controller killed has a start line and no done line.
  local t0
  t0=$(date -u +%s)
  log "-- $label (started $(date -u +%Y-%m-%dT%H:%M:%SZ))"
  # Clear the per-pass bd_list cache so this arm cannot read rows an earlier arm
  # cached; a repeat within the arm still hits.
  bd_cache_clear
  # The arm runs without the pass lock's descriptor, and the subshell pass_child
  # runs it from holds the lock until it exits (bd-lib.sh).
  local rc=0
  if [ -n "$LOG_SINK" ]; then
    pass_child "$SCRIPTS_DIR/$script" "$@" >> "$LOG_SINK" 2>&1 || rc=$?
  else
    pass_child "$SCRIPTS_DIR/$script" "$@" >/dev/null 2>&1 || rc=$?
  fi
  log "-- $label: done in $(( $(date -u +%s) - t0 ))s (rc=$rc)"
  return "$rc"
}
# The paced arms, in pass order, each named for its cursor. pace_args hands the
# next one its cursor and an equal share of what the pass budget has left, split
# among it and the arms still on this list, in PACE_ARGS, and takes it off the
# list. pace_skip takes off an arm this pass will not run, so the arms behind it
# split its share.
PACED_ARMS=(pr-feedback gate-ensure pr-facts)
pace_skip() { # <arm>
  local a left=()
  for a in ${PACED_ARMS[@]+"${PACED_ARMS[@]}"}; do
    [ "$a" = "$1" ] || left+=("$a")
  done
  PACED_ARMS=(${left[@]+"${left[@]}"})
}
pace_args() { # <arm>
  local now share n=${#PACED_ARMS[@]}
  now=$(date -u +%s)
  PACE_ARGS=(--cursor "$STATE_DIR/$1.cursor")
  [ "$n" -gt 0 ] || n=1
  if [ "$PASS_BUDGET_SECS" -gt 0 ]; then
    share=$(( (PASS_T0 + PASS_BUDGET_SECS - now) / n ))
    [ "$share" -lt "$ARM_FLOOR_SECS" ] && share="$ARM_FLOOR_SECS"
    PACE_ARGS+=(--deadline "$(( now + share ))")
  fi
  pace_skip "$1"
  return 0
}

# (1) posture: record each open PR's posture, which the PR-finishing rank and
# the board read. It reads every open PR in one batched call and keeps, in
# pr-posture.seen, what each posture was derived from, so a PR nothing has
# touched since costs no per-PR read and the arm's cost follows the PRs that
# moved.
( export BEADS_ACTOR="$AGENT"
  run_pass "(1) pr-posture" pr-facts.sh --posture-only --seen "$STATE_DIR/pr-posture.seen" ) \
  || FAILED="${FAILED}pr-posture rc=$?; "

# (4) pr-feedback: route operator PR feedback ahead of the slow arms. The full
# pr-facts arm (arm 7) re-runs the same routing idempotently, but it sits
# behind gate-ensure, so this arm is what routes feedback on a pass killed
# before arm 7. It does only the routing (skipping the write-back sweep and
# every non-feedback arm); arm 7 still owns the write-back and the
# external-fact reconciliation.
# BEADS_ACTOR is projected so the children it dispatches are attributed to the
# refinery, like the full arm. Its rc is reported and holds nothing.
pace_args pr-feedback
( export BEADS_ACTOR="$AGENT"
  run_pass "(4) pr-feedback" pr-facts.sh --route-comments-only --fix-pool "$FIX_POOL" "${PACE_ARGS[@]}" ) \
  || FAILED="${FAILED}pr-feedback rc=$?; "

# (6) gate-ensure: review dispatch. It visits every gating anchor, so it runs
# under its share of the pass budget: past the deadline it starts no new anchor,
# and its cursor names the last anchor it finished, so the next pass resumes
# after it. A slow gate-ensure therefore delays review dispatch for the anchors
# it has not reached, and nothing else. Its rc=3 (an anchor whose check_set stamp did
# not persist, or an enumeration it could not read) is reported and fails
# nothing.
GATE_UNSAFE_RC=3
pace_args gate-ensure
gate_rc=0
run_pass "(6) gate-ensure" gate-ensure.sh \
  --default "$CHECK_SET_DEFAULT" --review-pool "$REVIEW_POOL" \
  --fix-pool "$FIX_POOL" --validate-pool "$VALIDATE_POOL" "${PACE_ARGS[@]}" \
  ${GATE_REVIEW_FORMULA_ARGS[@]+"${GATE_REVIEW_FORMULA_ARGS[@]}"} || gate_rc=$?
if [ "$gate_rc" = "$GATE_UNSAFE_RC" ]; then
  note "gate-ensure UNSAFE (rc=$gate_rc) — an anchor has no check_set, or the gating enumeration did not read"
elif [ "$gate_rc" != 0 ]; then
  FAILED="${FAILED}gate-ensure rc=$gate_rc; "
fi

# (7) pr-facts: same actor projection (it records closes too). Paced like the
# arms ahead of it, so the arms behind it still get their turn.
pace_args pr-facts
( export BEADS_ACTOR="$AGENT"
  run_pass "(7) pr-facts" pr-facts.sh --fix-pool "$FIX_POOL" "${PACE_ARGS[@]}" ) \
  || FAILED="${FAILED}pr-facts rc=$?; "

# (8) review-sweep: close reviews whose anchor and branch are both gone. Late,
# because it reads only closed anchors, so a close an earlier arm made this pass
# drains on the same tick.
run_pass "(8) review-sweep" review-sweep.sh || FAILED="${FAILED}review-sweep rc=$?; "

# (9) scaffolding-sweep: retire the machine review scaffolding
# (validation/finding/rework) hung on an anchor once that anchor is DISPOSED, so
# the disposed anchor can finalize instead of standing stuck behind scaffolding
# that will never resolve. Late, beside review-sweep, because it keys on a
# terminal disposition no earlier arm produces, and a disposal this pass is
# cleaned on the same tick. No merge authority: it writes scaffolding beads, and
# a bug bead for a finding it carries forward, never the anchor — bead-rehome
# (via pr-facts' close arm) closes that, held by finalize-gate while a human
# gate on it is still open. BEADS_ACTOR projected — the close of a
# carried-forward finding is delegated to bead-rehome and attributed in the
# events table.
( export BEADS_ACTOR="$AGENT"
  run_pass "(9) scaffolding-sweep" scaffolding-sweep.sh ) \
  || FAILED="${FAILED}scaffolding-sweep rc=$?; "

# The per-pass bd_list cache is this pass's; drop it so no later pass can read
# these rows. A killed pass never reaches here and the next pass's rm-then-create
# setup clears the leftover.
[ -n "${CACHE_DIR:-}" ] && rm -rf "$CACHE_DIR" 2>/dev/null || true

if [ -n "$LOG_SINK" ]; then
  {
    [ -n "$NOTED" ] && printf '%s' "$NOTED"
    [ -n "$FAILED" ] && printf 'FAILED: %s\n' "$FAILED"
    printf 'END %s (%ss)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(( $(date -u +%s) - PASS_T0 ))"
  } >> "$LOG_SINK" 2>/dev/null || true
  if [ -w "$LOG" ]; then
    tail -n "$LOG_KEEP" "$LOG" > "$LOG.trim" 2>/dev/null && mv "$LOG.trim" "$LOG" 2>/dev/null
  fi
fi
[ -n "$NOTED" ] && printf '%s' "$NOTED"
if [ -n "$FAILED" ]; then
  echo "${PROG}[$RIG]: $FAILED"
  echo "${PROG}[$RIG]: pass log: $LOG"
  exit 1
fi
exit 0
