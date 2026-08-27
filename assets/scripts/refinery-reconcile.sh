#!/usr/bin/env bash
# refinery-reconcile — one pass of the merge cadence over this rig's queue.
# Driven by orders/refinery-reconcile.toml (cooldown 60s, scope=rig): the
# controller supplies the loop, cwd = the rig root, and the env (GC_RIG,
# GC_PACK_STATE_DIR, gh token).
# Arms, in load-bearing order: gate-ensure (rc=3 = designed HOLD of merge.sh
# for this pass, not a fault), pr-open, pr-facts --posture-only (the posture
# merge reads must be written in the same pass), merge (BEADS_ACTOR projected to
# the refinery: it closes anchors assigned to it), pr-facts (same projection),
# convoy-graduate (GC_AGENT projected: graduation assigns the convoy),
# review-sweep (cleanup over closed anchors; no projection, no merge authority).
# Single-flight is the per-rig flock below, NOT the controller's open-tracking
# gate: the controller watchdog closes any tracking bead older than 2m, which
# reopens that gate under a pass still running.
# No loop or sleep here — do NOT add one, and never re-create an out-of-band
# driver (docs/refinery-merge-cadence.md).
# NOT set -e / pipefail: arms are independent; a failing arm must not skip the
# rest, and the next cooldown retries everything.
set -u

PROG="refinery-reconcile"

# Rig identity comes from the order runner; guessing would run one rig's merge
# writer against another rig's store.
RIG="${GC_RIG:-}"
if [ -z "$RIG" ]; then
  echo "$PROG: GC_RIG is unset — this runs as a scope=\"rig\" order and has no rig to reconcile" >&2
  exit 2
fi
RIG_ROOT="${GC_RIG_ROOT:-$PWD}"
# Siblings resolve from $0: the pack lives under the owning rig, so an importer
# rig's own root has no assets/scripts at all.
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

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
CHECK_SET_DEFAULT="${REFINERY_RECONCILE_CHECK_SET:-codex}"
INTEGRATION_AUTO_LAND="${REFINERY_RECONCILE_INTEGRATION_AUTO_LAND:-true}"

# Graduation target = this rig's own origin/HEAD (one [order.env] serves every
# rig, so a constant here would be per-rig drift).
TARGET="${REFINERY_RECONCILE_TARGET:-}"
if [ -z "$TARGET" ]; then
  TARGET="$(git -C "$RIG_ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  TARGET="${TARGET#origin/}"
fi
[ -n "$TARGET" ] || TARGET=main

# Per-rig state (GC_PACK_STATE_DIR is city+pack scoped; this order runs per rig).
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
FAILED=""
NOTED=""

# Two merge.sh writers against one rig's anchors is the failure this cadence
# must never produce, and the controller's open-tracking gate does not prevent
# it: the watchdog closes tracking beads at 2m, well inside the 300s timeout,
# and an un-gated tracking bead is a second dispatch. This flock depends on no
# bead surviving. The arms inherit fd 9, so the lock is held for exactly as
# long as a writer is live and the kernel releases it on any exit, SIGKILL
# included.
LOCK="$STATE_DIR/pass.lock"
HOLDER="$STATE_DIR/pass.holder"
# A holder older than this is not a slow pass: the driver is gone and an arm
# still owns the fd. Merges have stopped, so it is reported, not skipped over.
LOCK_STALL_SECS="${REFINERY_RECONCILE_LOCK_STALL_SECS:-900}"
lock_unguarded=""
lock_held=0
if ! command -v flock >/dev/null 2>&1; then
  lock_unguarded="flock not found on PATH"
elif ! ( : >> "$LOCK" ) 2>/dev/null; then
  lock_unguarded="cannot create $LOCK"
else
  exec 9>>"$LOCK" || lock_unguarded="cannot open $LOCK"
  if [ -z "$lock_unguarded" ] && flock -n 9; then
    lock_held=1
    printf '%s %s\n' "$$" "$(date -u +%s)" > "$HOLDER" 2>/dev/null || true
  fi
fi

if [ -z "$lock_unguarded" ] && [ "$lock_held" = 0 ]; then
  held_pid=""; held_since=""; elapsed=""
  [ -r "$HOLDER" ] && read -r held_pid held_since < "$HOLDER"
  case "$held_since" in
    ''|*[!0-9]*) ;;
    *) elapsed=$(( $(date -u +%s) - held_since )) ;;
  esac
  who="pid ${held_pid:-unknown}"
  [ -n "$elapsed" ] && who="$who, ${elapsed}s elapsed"
  if [ -n "$elapsed" ] && [ "$elapsed" -gt "$LOCK_STALL_SECS" ]; then
    [ -n "$LOG_SINK" ] && printf -- '--- %s rig=%s STALLED: pass lock held %ss (%s)\n' \
      "$TICK" "$RIG" "$elapsed" "$who" >> "$LOG_SINK"
    echo "${PROG}[$RIG]: pass lock held ${elapsed}s (> ${LOCK_STALL_SECS}s) by $who — the cadence is wedged and nothing is landing"
    echo "${PROG}[$RIG]: pass log: $LOG"
    exit 1
  fi
  [ -n "$LOG_SINK" ] && printf -- '--- %s rig=%s SKIPPED: pass already in flight (%s)\n' \
    "$TICK" "$RIG" "$who" >> "$LOG_SINK"
  echo "${PROG}[$RIG]: a pass is already in flight ($who) — skipping this tick"
  exit 0
fi
# The lock is the whole of single-flight, so an unavailable one leaves nothing
# serialising the arms. Running them anyway is the second merge.sh writer this
# driver exists to prevent.
if [ -n "$lock_unguarded" ]; then
  [ -n "$LOG_SINK" ] && printf -- '--- %s rig=%s UNGUARDED: %s; no arm ran\n' \
    "$TICK" "$RIG" "$lock_unguarded" >> "$LOG_SINK"
  echo "${PROG}[$RIG]: single-flight UNGUARDED ($lock_unguarded) — refusing to run any arm without the pass lock"
  echo "${PROG}[$RIG]: pass log: $LOG"
  exit 1
fi

# The controller keeps combined output only on a non-zero exit, so the log is
# where a healthy pass is readable and the exit code is the alarm. The header
# goes down before the first arm runs; the END line below closes it, so a
# header with no END under it is a pass that was killed.
[ -n "$LOG_SINK" ] && printf '=== %s rig=%s refinery=%s\n' "$TICK" "$RIG" "$AGENT" >> "$LOG_SINK"

# >>> heal-gates-merge
# Extracted and EXECUTED by refinery-reconcile.test.sh against stub arms: an
# unsafe gate-ensure must HOLD merge.sh in the same pass. Keep it executable
# with only a prologue supplying SCRIPTS_DIR, LOG_SINK, NOTED, FAILED, AGENT,
# CHECK_SET_DEFAULT, REVIEW_POOL and FIX_POOL.
note() { NOTED="${NOTED}$*"$'\n'; }
log()  { [ -n "$LOG_SINK" ] && printf '%s\n' "$*" >> "$LOG_SINK"; return 0; }
run_pass() { # <label> <script> [args...]
  local label="$1" script="$2"; shift 2
  if [ ! -x "$SCRIPTS_DIR/$script" ]; then
    log "-- $label: SKIPPED (no $SCRIPTS_DIR/$script)"
    return 0
  fi
  log "-- $label"
  local rc=0
  if [ -n "$LOG_SINK" ]; then
    "$SCRIPTS_DIR/$script" "$@" >> "$LOG_SINK" 2>&1 || rc=$?
  else
    "$SCRIPTS_DIR/$script" "$@" >/dev/null 2>&1 || rc=$?
  fi
  return "$rc"
}

# (1) gate-ensure: its unsafe rc is a designed hold of merge.sh for this
# pass — an approval-gated queue must not raise order.failed every 60s over it.
GATE_UNSAFE_RC=3
MERGE_HELD=0
MERGE_HELD_WHY=""
gate_rc=0
run_pass "(1) gate-ensure" gate-ensure.sh \
  --default "$CHECK_SET_DEFAULT" --review-pool "$REVIEW_POOL" \
  --fix-pool "$FIX_POOL" || gate_rc=$?
if [ "$gate_rc" = "$GATE_UNSAFE_RC" ]; then
  MERGE_HELD=1
  MERGE_HELD_WHY="${MERGE_HELD_WHY:+$MERGE_HELD_WHY, }gate-ensure unsafe"
  note "gate-ensure UNSAFE (rc=$gate_rc) — merge.sh HELD this pass"
elif [ "$gate_rc" != 0 ]; then
  FAILED="${FAILED}gate-ensure rc=$gate_rc; "
fi

# (2) pr-open: pre_open_gate -> pull_request.
run_pass "(2) pr-open" pr-open.sh || FAILED="${FAILED}pr-open rc=$?; "

# (2b) posture: merge.sh answers "is a human waiting on this?" off the bead and
# never asks GitHub, so the posture it reads has to be written in THIS pass. The
# full pr-facts arm runs after merge, which leaves a comment that arrived since
# the last pass invisible to the merge it should have held. Its rc is the same
# guarantee read the other way: an arm that could not record a posture leaves
# merge.sh validating one from an earlier tick, so it holds merge for the pass.
posture_rc=0
( export BEADS_ACTOR="$AGENT"
  run_pass "(2b) pr-posture" pr-facts.sh --posture-only ) || posture_rc=$?
if [ "$posture_rc" != 0 ]; then
  MERGE_HELD=1
  MERGE_HELD_WHY="${MERGE_HELD_WHY:+$MERGE_HELD_WHY, }posture not current"
  FAILED="${FAILED}pr-posture rc=$posture_rc; "
  note "pr-posture rc=$posture_rc — merge.sh HELD this pass"
fi

# (3) merge: BEADS_ACTOR projected in a subshell — the anchors it closes are
# assigned to the refinery, and bd refuses a close by a different principal.
if [ "$MERGE_HELD" = 1 ]; then
  log "-- (3) merge: HELD this pass ($MERGE_HELD_WHY)"
else
  ( export BEADS_ACTOR="$AGENT"
    run_pass "(3) merge" merge.sh ) || FAILED="${FAILED}merge rc=$?; "
fi
# <<< heal-gates-merge

# (4) pr-facts: same actor projection (it records closes too).
( export BEADS_ACTOR="$AGENT"
  run_pass "(4) pr-facts" pr-facts.sh \
    --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL" ) \
  || FAILED="${FAILED}pr-facts rc=$?; "

# (5) convoy-graduate: GC_AGENT projected in a subshell (graduation assigns the
# convoy to the refinery; the order env does not supply GC_AGENT).
if [ "$INTEGRATION_AUTO_LAND" = "false" ]; then
  log "-- (5) convoy-graduate: DISABLED (integration_auto_land=false)"
else
  ( export GC_AGENT="$AGENT"
    run_pass "(5) convoy-graduate" convoy-graduate.sh --target "$TARGET" ) \
    || FAILED="${FAILED}convoy-graduate rc=$?; "
fi

# (6) review-sweep: close reviews whose anchor and branch are both gone. Last,
# because it reads only closed anchors — nothing earlier in the pass can see
# them, and the residue this pass's merges create drains on the same tick.
run_pass "(6) review-sweep" review-sweep.sh || FAILED="${FAILED}review-sweep rc=$?; "

if [ -n "$LOG_SINK" ]; then
  {
    [ -n "$NOTED" ] && printf '%s' "$NOTED"
    [ -n "$FAILED" ] && printf 'FAILED: %s\n' "$FAILED"
    printf 'END %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
