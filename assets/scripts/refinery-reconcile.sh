#!/usr/bin/env bash
# refinery-reconcile — one pass of the merge cadence over this rig's queue.
# Driven by orders/refinery-reconcile.toml (cooldown 60s, scope=rig): the
# controller supplies the loop, cwd = the rig root, and the env (GC_RIG,
# GC_PACK_STATE_DIR, gh token).
# Arms, in load-bearing order: gate-ensure (rc=3 = designed HOLD of merge.sh
# for this pass, not a fault), pr-facts --posture-only (the posture merge reads
# must be written in the same pass), pr-facts --route-comments-only (route
# operator feedback early, before merge, so a pass killed before the full arm has
# still picked it up; BEADS_ACTOR projected), merge (BEADS_ACTOR projected to the
# refinery so its closes and records are attributed to it), pre-open-rebase (the
# conflict observer for anchors that have no PR yet), pr-open, pr-facts (same
# projection), convoy-graduate (GC_AGENT projected: graduation assigns the
# convoy), review-sweep (cleanup over closed anchors; no projection, no merge
# authority), duplicate-sweep (BEADS_ACTOR projected: it closes duplicate
# dispatches through bead-rehome; no merge authority), pr-stack (PR bodies only —
# both managed regions; no projection, no merge authority).
# merge runs AHEAD of pre-open-rebase and pr-open on purpose: those two iterate
# the pre_open_gate backlog with a GitHub round-trip per anchor, and once that
# held backlog grew their cost consumed the whole pass budget before merge was
# reached, so approved CLEAN PRs never landed. merge reads none of their output —
# it lands pull_request anchors, they produce pre_open_gate ones — so its only
# same-pass interlocks are gate-ensure and the posture arm, and it runs the moment
# those two are done.
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
# The head a dropped-tail finding names: the base its anchors would have landed
# on, captured once. A checkout that is not a git tree reads "unknown".
RIG_HEAD="$(git -C "$RIG_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
[ -n "$RIG_HEAD" ] || RIG_HEAD=unknown
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
# mol-validate is a judgment pass — it rules a review's findings, it does not
# re-review — so it defaults to the general claude worker pool where fix units
# land, not REVIEW_POOL (the codex pool the merge cadence routes mol-review to).
# A rig that staffs a dedicated validate pool points this there without an edit.
VALIDATE_POOL="${REFINERY_RECONCILE_VALIDATE_POOL:-$FIX_POOL}"
CHECK_SET_DEFAULT="${REFINERY_RECONCILE_CHECK_SET:-correctness,triage}"
INTEGRATION_AUTO_LAND="${REFINERY_RECONCILE_INTEGRATION_AUTO_LAND:-true}"

# Review dispatch formula (two-lane pilot). Default mol-review — the
# single-agent lifecycle. Opt into the quorum by setting
# REFINERY_RECONCILE_REVIEW_FORMULA=mol-review-quorum-signoff: reviews then run
# as two provider lanes (codex + claude by default) plus a synthesizer that
# makes the single signoff. Reverting is unsetting the env — no code change.
# Lane config is constant across the pass; the per-review base is read from
# each review bead's review_base by the lanes, so base_ref stays defaulted.
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

# Per-pass merge-decision marker: the durable record of whether a pass reached
# and completed its merge decision. A pass the controller kills at its budget
# runs no at-exit code, but the phase it wrote here before the kill survives, and
# the NEXT pass reads it (merge-tail-report.sh below) to see a dropped merge tail
# — a pass that stopped before deciding its approved-clean candidates and left
# them unmerged with no reason on the board. Written atomically so a reader never
# sees a torn line; single-flight means only the live pass writes it.
MERGE_MARK="$STATE_DIR/merge-decision"
mark_merge() { # <phase>
  printf '%s\t%s\t%s\n' "$1" "$TICK" "$RIG_HEAD" > "$MERGE_MARK.tmp" 2>/dev/null \
    && mv -f "$MERGE_MARK.tmp" "$MERGE_MARK" 2>/dev/null || true
}

# Two merge.sh writers against one rig's anchors is the failure this cadence
# must never produce, and the controller's open-tracking gate does not prevent
# it: the watchdog closes tracking beads at 2m, well inside the order's timeout,
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

# Before this pass overwrites the marker, judge the PRIOR pass by it. We hold the
# pass lock, so the pass that wrote the marker is already dead: a marker that never
# reached `decided`/`held` while gating anchors are still open is a dropped merge
# tail, and this files the board-visible finding naming it. BEADS_ACTOR projected
# so the finding and the reaction it dispatches are attributed to the refinery,
# like every other bead-writing arm. The report never fails the pass — it only
# records — so its rc is discarded.
if [ -x "$SCRIPTS_DIR/merge-tail-report.sh" ]; then
  ( export BEADS_ACTOR="$AGENT"
    "$SCRIPTS_DIR/merge-tail-report.sh" --marker "$MERGE_MARK" --rig "$RIG" ) \
    >> "${LOG_SINK:-/dev/null}" 2>&1 || true
fi
mark_merge started

# >>> heal-gates-merge
# Extracted and EXECUTED by refinery-reconcile.test.sh against stub arms: an
# unsafe gate-ensure must HOLD merge.sh in the same pass. Keep it executable
# with only a prologue supplying SCRIPTS_DIR, LOG_SINK, NOTED, FAILED, AGENT,
# CHECK_SET_DEFAULT, REVIEW_POOL, FIX_POOL, VALIDATE_POOL and the mark_merge
# helper (the merge-decision marker writer).
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
  --fix-pool "$FIX_POOL" --validate-pool "$VALIDATE_POOL" ${GATE_REVIEW_FORMULA_ARGS[@]+"${GATE_REVIEW_FORMULA_ARGS[@]}"} || gate_rc=$?
if [ "$gate_rc" = "$GATE_UNSAFE_RC" ]; then
  MERGE_HELD=1
  MERGE_HELD_WHY="${MERGE_HELD_WHY:+$MERGE_HELD_WHY, }gate-ensure unsafe"
  note "gate-ensure UNSAFE (rc=$gate_rc) — merge.sh HELD this pass"
elif [ "$gate_rc" != 0 ]; then
  FAILED="${FAILED}gate-ensure rc=$gate_rc; "
fi

# (2) posture: merge.sh answers "is a human waiting on this?" off the bead and
# never asks GitHub, so the posture it reads has to be written in THIS pass. The
# full pr-facts arm runs after merge, which leaves a comment that arrived since
# the last pass invisible to the merge it should have held. Its rc is the same
# guarantee read the other way: an arm that could not record a posture leaves
# merge.sh validating one from an earlier tick, so it holds merge for the pass.
posture_rc=0
( export BEADS_ACTOR="$AGENT"
  run_pass "(2) pr-posture" pr-facts.sh --posture-only ) || posture_rc=$?
if [ "$posture_rc" != 0 ]; then
  MERGE_HELD=1
  MERGE_HELD_WHY="${MERGE_HELD_WHY:+$MERGE_HELD_WHY, }posture not current"
  FAILED="${FAILED}pr-posture rc=$posture_rc; "
  note "pr-posture rc=$posture_rc — merge.sh HELD this pass"
fi

# (3) pr-feedback: route operator PR feedback on the same early tick the posture
# is stamped, before merge. The full pr-facts arm (arm 7) runs near the pass tail,
# so a pass the timeout killed after the posture arm but before arm 7 left the
# feedback stamped-as-seen yet unrouted for hours. This arm closes that window: it
# does only the routing (skipping the write-back sweep and every non-feedback
# arm), so it is cheap and finishes early. The full arm re-runs the same routing
# idempotently and still owns the write-back and the external-fact reconciliation.
# BEADS_ACTOR is projected so the children it dispatches are attributed to the
# refinery, like the full arm; its rc is reported but never holds merge — routing
# is not the posture interlock.
( export BEADS_ACTOR="$AGENT"
  run_pass "(3) pr-feedback" pr-facts.sh --route-comments-only --fix-pool "$FIX_POOL" ) \
  || FAILED="${FAILED}pr-feedback rc=$?; "

# (4) merge: runs immediately after its only same-pass interlocks — gate-ensure's
# rc=3 hold and the posture arm above — and AHEAD of pre-open-rebase and pr-open,
# whose pre_open_gate-backlog iteration would otherwise consume the pass budget
# before merge was reached. merge reads none of their output (it lands
# pull_request anchors; they produce pre_open_gate ones), so pulling it ahead
# starves it of nothing. BEADS_ACTOR projected in a subshell so its closes and
# records are attributed to the refinery in the events log. The anchors it closes
# are detached in a gating state and carry no assignee (mol-refinery-patrol clears
# it), and the close is a bd update --status=closed, not the ownership-checked
# bd close, so the projection is attribution, not permission.
if [ "$MERGE_HELD" = 1 ]; then
  log "-- (4) merge: HELD this pass ($MERGE_HELD_WHY)"
  # A hold is a recorded decision (MERGE_HELD_WHY names it), not a dropped tail.
  mark_merge held
else
  # `reached` before merge, `decided` after: a pass killed between them leaves
  # `reached`, which the next pass reads as a merge arm that never finished.
  mark_merge reached
  ( export BEADS_ACTOR="$AGENT"
    run_pass "(4) merge" merge.sh ) || FAILED="${FAILED}merge rc=$?; "
  mark_merge decided
fi
# <<< heal-gates-merge

# (5) pre-open-rebase: the conflict observer for pre_open_gate anchors. It runs
# after merge (merge reads none of its output) and before pr-open, because
# pr-open is what ends its domain: once an anchor carries a PR, `mergeable`
# answers the same question and pr-facts' CONFLICTING arm owns the dispatch. Its
# failure is not a merge hold — an anchor it could not observe is left exactly as
# this cadence found it.
run_pass "(5) pre-open-rebase" pre-open-rebase.sh \
  --fix-pool "$FIX_POOL" || FAILED="${FAILED}pre-open-rebase rc=$?; "

# (6) pr-open: pre_open_gate -> pull_request. After merge because it produces the
# pull_request anchors a LATER pass lands — the city approves nothing at open, so
# a freshly opened PR is never landable on the same tick, and running this after
# merge defers a landing by one pass only in the ungated lane-only case, never
# starves merge.
run_pass "(6) pr-open" pr-open.sh || FAILED="${FAILED}pr-open rc=$?; "

# (7) pr-facts: same actor projection (it records closes too).
( export BEADS_ACTOR="$AGENT"
  run_pass "(7) pr-facts" pr-facts.sh --fix-pool "$FIX_POOL" ) \
  || FAILED="${FAILED}pr-facts rc=$?; "

# (8) convoy-graduate: GC_AGENT projected in a subshell (graduation assigns the
# convoy to the refinery; the order env does not supply GC_AGENT).
if [ "$INTEGRATION_AUTO_LAND" = "false" ]; then
  log "-- (8) convoy-graduate: DISABLED (integration_auto_land=false)"
else
  ( export GC_AGENT="$AGENT"
    run_pass "(8) convoy-graduate" convoy-graduate.sh --target "$TARGET" ) \
    || FAILED="${FAILED}convoy-graduate rc=$?; "
fi

# (9) review-sweep: close reviews whose anchor and branch are both gone. Late,
# because it reads only closed anchors — nothing earlier in the pass can see
# them, and the residue this pass's merges create drains on the same tick.
run_pass "(9) review-sweep" review-sweep.sh || FAILED="${FAILED}review-sweep rc=$?; "

# (10) duplicate-sweep: dispose of verified no-op duplicate dispatches. Late,
# and after review-sweep, because the gate it re-verifies is a CLOSED
# successor: a twin that arm 4 merged or arm 7 recorded this pass is
# disposable on this tick rather than a minute later. BEADS_ACTOR projected —
# the close it delegates to bead-rehome is attributed in the events table.
( export BEADS_ACTOR="$AGENT"
  run_pass "(10) duplicate-sweep" duplicate-sweep.sh ) \
  || FAILED="${FAILED}duplicate-sweep rc=$?; "

# (11) pr-stack: bring each open PR's body current with its anchor in both managed
# regions — re-render the beads-on-this-branch section, and refresh the pr-summary
# region when a rework moved the anchor summary past the published one (pr-open
# composes that region only at pre_open_gate, which an open anchor never re-enters).
# Last, and after merge: a bead this pass landed onto another anchor's branch is in
# the ledger it reads, so the body names it on the same tick rather than a minute
# later. It writes only PR bodies — no bead, no merge authority — so it runs
# unprojected and its failure gates nothing.
run_pass "(11) pr-stack" pr-stack.sh || FAILED="${FAILED}pr-stack rc=$?; "

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
