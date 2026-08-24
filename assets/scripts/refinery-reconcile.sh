#!/usr/bin/env bash
# refinery-reconcile — one pass of the merge cadence over this rig's queue.
# Driven by orders/refinery-reconcile.toml (cooldown 60s, scope=rig): the
# controller supplies the loop, the single-flight gate (ScopedName tracking),
# cwd = the rig root, and the env (GC_RIG, GC_PACK_STATE_DIR, gh token).
# Arms, in load-bearing order: gate-ensure (rc=3 = designed HOLD of merge.sh
# for this pass, not a fault), pr-open, merge (BEADS_ACTOR projected to the
# refinery: it closes anchors assigned to it), pr-facts (same projection),
# convoy-graduate (GC_AGENT projected: graduation assigns the convoy).
# No lock, loop or sleep here — do NOT add one, and never re-create an
# out-of-band driver (docs/refinery-merge-cadence.md).
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
PASS_OUT="$(mktemp "${TMPDIR:-/tmp}/$PROG.XXXXXX")" || PASS_OUT=""
# shellcheck disable=SC2329  # reached through the EXIT trap
cleanup() { [ -n "$PASS_OUT" ] && rm -f "$PASS_OUT"; return 0; }
trap cleanup EXIT
TICK="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FAILED=""
NOTED=""

# >>> heal-gates-merge
# Extracted and EXECUTED by refinery-reconcile.test.sh against stub arms: an
# unsafe gate-ensure must HOLD merge.sh in the same pass. Keep it executable
# with only a prologue supplying SCRIPTS_DIR, PASS_OUT, NOTED, FAILED, AGENT,
# CHECK_SET_DEFAULT, REVIEW_POOL and FIX_POOL.
note() { NOTED="${NOTED}$*"$'\n'; }
log()  { [ -n "$PASS_OUT" ] && printf '%s\n' "$*" >> "$PASS_OUT"; return 0; }
run_pass() { # <label> <script> [args...]
  local label="$1" script="$2"; shift 2
  if [ ! -x "$SCRIPTS_DIR/$script" ]; then
    log "-- $label: SKIPPED (no $SCRIPTS_DIR/$script)"
    return 0
  fi
  log "-- $label"
  local rc=0
  if [ -n "$PASS_OUT" ]; then
    "$SCRIPTS_DIR/$script" "$@" >> "$PASS_OUT" 2>&1 || rc=$?
  else
    "$SCRIPTS_DIR/$script" "$@" >/dev/null 2>&1 || rc=$?
  fi
  return "$rc"
}

# (1) gate-ensure: its unsafe rc is a designed hold of merge.sh for this
# pass — an approval-gated queue must not raise order.failed every 60s over it.
GATE_UNSAFE_RC=3
MERGE_HELD=0
gate_rc=0
run_pass "(1) gate-ensure" gate-ensure.sh \
  --default "$CHECK_SET_DEFAULT" --review-pool "$REVIEW_POOL" || gate_rc=$?
if [ "$gate_rc" = "$GATE_UNSAFE_RC" ]; then
  MERGE_HELD=1
  note "gate-ensure UNSAFE (rc=$gate_rc) — merge.sh HELD this pass"
elif [ "$gate_rc" != 0 ]; then
  FAILED="${FAILED}gate-ensure rc=$gate_rc; "
fi

# (2) pr-open: pre_open_gate -> pull_request.
run_pass "(2) pr-open" pr-open.sh || FAILED="${FAILED}pr-open rc=$?; "

# (3) merge: BEADS_ACTOR projected in a subshell — the anchors it closes are
# assigned to the refinery, and bd refuses a close by a different principal.
if [ "$MERGE_HELD" = 1 ]; then
  log "-- (3) merge: HELD this pass (gate-ensure unsafe)"
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

# The controller keeps combined output only on a non-zero exit, so the log is
# where a healthy pass is readable and the exit code is the alarm.
{
  printf '=== %s rig=%s refinery=%s\n' "$TICK" "$RIG" "$AGENT"
  [ -n "$PASS_OUT" ] && cat "$PASS_OUT"
  [ -n "$NOTED" ] && printf '%s' "$NOTED"
  [ -n "$FAILED" ] && printf 'FAILED: %s\n' "$FAILED"
} >> "$LOG" 2>/dev/null || true
if [ -w "$LOG" ]; then
  tail -n "$LOG_KEEP" "$LOG" > "$LOG.trim" 2>/dev/null && mv "$LOG.trim" "$LOG" 2>/dev/null
fi
[ -n "$NOTED" ] && printf '%s' "$NOTED"
if [ -n "$FAILED" ]; then
  echo "${PROG}[$RIG]: $FAILED"
  echo "${PROG}[$RIG]: pass log: $LOG"
  exit 1
fi
exit 0
