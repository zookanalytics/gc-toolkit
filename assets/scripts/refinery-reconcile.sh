#!/usr/bin/env bash
# refinery-reconcile — one pass of the merge cadence over this rig's queue.
# Driven by orders/refinery-reconcile.toml (cooldown 60s, scope=rig): the
# controller supplies the loop, cwd = the rig root, and the env (GC_RIG,
# GC_PACK_STATE_DIR, gh token).
# Arms, in load-bearing order: pr-facts --posture-only (the posture merge reads
# must be written in the same pass; a non-zero rc HOLDS merge.sh for the pass),
# merge (BEADS_ACTOR projected to the refinery so its closes and records are
# attributed to it), pr-open, pr-facts --route-comments-only (route operator
# feedback ahead of the slow arms, so a pass killed before the full arm has
# still picked it up; BEADS_ACTOR projected), pre-open-rebase (the conflict
# observer for anchors that have no PR yet), gate-ensure, pr-facts (same
# projection), convoy-graduate (GC_AGENT projected: graduation assigns the
# convoy), review-sweep (cleanup over closed anchors; no projection, no merge
# authority), scaffolding-sweep (retires validation/finding/rework on a disposed
# anchor; no projection, no merge authority), duplicate-sweep (BEADS_ACTOR
# projected: it closes duplicate dispatches through bead-rehome; no merge
# authority), pr-stack (PR bodies only — both managed regions; no projection,
# no merge authority).
# The arms that walk a set growing with the queue share the pass budget (see
# PASS_BUDGET_SECS and PACED_ARMS below): merge, pr-open, pr-feedback,
# pre-open-rebase, gate-ensure, pr-facts and pr-stack.
# Landing is the main way an anchor leaves the gating set, and pr-open is what
# puts an anchor in front of the operator for the approval merge waits on. The
# arms that iterate that set grow in cost with it, so one placed ahead of these
# two can spend the pass budget before they run, and a set that stops draining
# keeps growing, which slows that arm further. So they run first: ahead of
# merge sits only the arm whose output merge must have from this pass, the
# posture, and ahead of pr-open sits only merge. Neither needs anything
# gate-ensure writes in the same pass. Both hold an anchor with no check_set on
# their own read. Of gate-ensure's review-graph writes, a dispatch goes only to
# a lane that is already short of green, and closing a must-fix finding whose
# fix landed can only release a hold, so reading the graph before gate-ensure
# runs can delay an open or a merge by one pass but never allow one early.
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
# The pass budget, in seconds (0 = unpaced). Every arm that walks a set growing
# with the queue is paced: past its deadline it starts no new anchor, and the
# next pass resumes after the last one it finished (a cursor in the state dir).
# Each paced arm's deadline is an equal share of the time the pass budget has
# left when the arm starts, and never less than ARM_FLOOR_SECS, so an arm that
# finishes early leaves its time to the arms behind it, and every arm runs on
# every pass. The budget sits below the order's timeout, so a pass ends and
# writes END instead of being killed. Two walks are never paced: the posture
# record, which merge needs whole, and the PRs merge can land this pass.
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
PASS_T0="$(date -u +%s)"
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

# Per-pass bd_list cache (assets/scripts/bd-lib.sh). The arms re-issue the same
# `gc bd list` many times a pass — the gating anchor, and the
# pull_request/pre_open enumeration nearly every arm re-reads — and each call is
# seconds of server wait. GC_RECONCILE_BD_CACHE points bd_list at a directory it
# serves a repeat from; run_pass clears it before every arm so no arm reads
# another's rows, and it is removed at END. A killed pass leaves it behind, so
# setup is rm-then-create. Caching is enabled only when bd-lib sources here, so
# run_pass can clear the dir between arms through bd_cache_clear; otherwise the
# pass runs uncached (the cache is an optimization, never a correctness input).
CACHE_DIR="$STATE_DIR/cache"
rm -rf "$CACHE_DIR" 2>/dev/null || true
# shellcheck source=bd-lib.sh
if . "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" 2>/dev/null && mkdir -p "$CACHE_DIR" 2>/dev/null; then
  export GC_RECONCILE_BD_CACHE="$CACHE_DIR"
fi

# >>> posture-gates-merge
# Extracted and EXECUTED by refinery-reconcile.test.sh against stub arms: a
# posture arm that could not make every posture current must HOLD merge.sh in
# the same pass. Keep it executable with only a prologue supplying SCRIPTS_DIR,
# LOG_SINK, NOTED, FAILED, AGENT, STATE_DIR, PASS_T0, PASS_BUDGET_SECS,
# ARM_FLOOR_SECS and the mark_merge helper (the merge-decision marker writer).
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
  # cached; a repeat within the arm still hits. Guarded by command -v because
  # this block is extracted and run standalone by refinery-reconcile.test.sh,
  # where bd-lib is not sourced and bd_cache_clear is undefined.
  command -v bd_cache_clear >/dev/null 2>&1 && bd_cache_clear
  local rc=0
  if [ -n "$LOG_SINK" ]; then
    "$SCRIPTS_DIR/$script" "$@" >> "$LOG_SINK" 2>&1 || rc=$?
  else
    "$SCRIPTS_DIR/$script" "$@" >/dev/null 2>&1 || rc=$?
  fi
  log "-- $label: done in $(( $(date -u +%s) - t0 ))s (rc=$rc)"
  return "$rc"
}
# The paced arms, in pass order, each named for its cursor. pace_args hands the
# next one its cursor and an equal share of what the pass budget has left, split
# among it and the arms still on this list, in PACE_ARGS, and takes it off the
# list. pace_skip takes off an arm this pass will not run, so the arms behind it
# split its share.
PACED_ARMS=(merge pr-open pr-feedback pre-open-rebase gate-ensure pr-facts pr-stack)
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

# (1) posture: merge.sh answers "is a human waiting on this?" off the bead and
# never asks GitHub, so the posture it reads has to be written in THIS pass. It
# runs immediately before merge, so the window in which a newly arrived comment
# goes unseen is only as long as these two arms make it. Its rc is the same
# guarantee read the other way: an arm that could not record a posture leaves
# merge.sh validating one from an earlier tick, so it holds merge for the pass.
# It reads every open PR in one batched call and keeps, in pr-posture.seen,
# what each posture was derived from, so a PR nothing has touched since costs
# no per-PR read and the arm's cost follows the PRs that moved.
MERGE_HELD=0
posture_rc=0
( export BEADS_ACTOR="$AGENT"
  run_pass "(1) pr-posture" pr-facts.sh --posture-only --seen "$STATE_DIR/pr-posture.seen" ) || posture_rc=$?
if [ "$posture_rc" != 0 ]; then
  MERGE_HELD=1
  FAILED="${FAILED}pr-posture rc=$posture_rc; "
  note "pr-posture rc=$posture_rc — merge.sh HELD this pass"
fi

# (2) merge: runs the moment its one same-pass interlock, the posture record, is
# done. It visits every PR that can land this pass first, and its share of the
# pass budget paces only the rest, so `decided` below means every landable PR
# was decided.
# BEADS_ACTOR projected in a subshell so its closes and records are attributed
# to the refinery in the events log. The anchors it closes are detached in a
# gating state and carry no assignee (mol-refinery-patrol clears it), and the
# close is a bd update --status=closed, not the ownership-checked bd close, so
# the projection is attribution, not permission.
if [ "$MERGE_HELD" = 1 ]; then
  log "-- (2) merge: HELD this pass (posture not current)"
  # A hold is a recorded decision, not a dropped tail.
  mark_merge held
  # The held arm spends none of the pass budget, so the paced arms behind it
  # divide its share among themselves.
  pace_skip merge
else
  # `reached` before merge, `decided` after: a pass killed between them leaves
  # `reached`, which the next pass reads as a merge arm that never finished.
  mark_merge reached
  pace_args merge
  ( export BEADS_ACTOR="$AGENT"
    run_pass "(2) merge" merge.sh "${PACE_ARGS[@]}" ) || FAILED="${FAILED}merge rc=$?; "
  mark_merge decided
fi
# <<< posture-gates-merge

# (3) pr-open: pre_open_gate -> pull_request, right after merge. The city
# approves nothing at open, so a PR opened this pass is never landable on the
# same tick, and merge reads none of this arm's output, so running after merge
# costs no landing. Running ahead of every other arm means no slow one can keep
# a green branch from reaching the operator.
pace_args pr-open
run_pass "(3) pr-open" pr-open.sh "${PACE_ARGS[@]}" || FAILED="${FAILED}pr-open rc=$?; "

# (4) pr-feedback: route operator PR feedback ahead of the slow arms. The full
# pr-facts arm (arm 7) re-runs the same routing idempotently, but it sits
# behind gate-ensure, so this arm is what routes feedback on a pass killed
# before arm 7. It does only the routing (skipping the write-back sweep and
# every non-feedback arm); arm 7 still owns the write-back and the
# external-fact reconciliation.
# BEADS_ACTOR is projected so the children it dispatches are attributed to the
# refinery, like the full arm. Its rc is reported and holds nothing: merge has
# already run, and routing is not the posture interlock.
pace_args pr-feedback
( export BEADS_ACTOR="$AGENT"
  run_pass "(4) pr-feedback" pr-facts.sh --route-comments-only --fix-pool "$FIX_POOL" "${PACE_ARGS[@]}" ) \
  || FAILED="${FAILED}pr-feedback rc=$?; "

# (5) pre-open-rebase: the conflict observer for the pre_open_gate anchors
# pr-open left where they were. An anchor pr-open flipped this pass carries a
# PR, where `mergeable` answers the same question and pr-facts' CONFLICTING arm
# owns the dispatch; both arms probe the same children on the branch, so
# whichever sees a conflict first files and the other stands down. Its failure
# is not a merge hold — an anchor it could not observe is left exactly as this
# cadence found it.
pace_args pre-open-rebase
run_pass "(5) pre-open-rebase" pre-open-rebase.sh \
  --fix-pool "$FIX_POOL" "${PACE_ARGS[@]}" || FAILED="${FAILED}pre-open-rebase rc=$?; "

# (6) gate-ensure: review dispatch. It visits every gating anchor, so it runs
# under its share of the pass budget: past the deadline it starts no new anchor,
# and its cursor names the last anchor it finished, so the next pass resumes
# after it. A slow gate-ensure therefore delays review dispatch for the anchors
# it has not reached, and nothing else. Its rc=3 (an anchor whose check_set stamp did
# not persist, or an enumeration it could not read) is reported and fails
# nothing: merge.sh and pr-open.sh each hold an anchor with no check_set on
# their own read.
GATE_UNSAFE_RC=3
pace_args gate-ensure
gate_rc=0
run_pass "(6) gate-ensure" gate-ensure.sh \
  --default "$CHECK_SET_DEFAULT" --review-pool "$REVIEW_POOL" \
  --fix-pool "$FIX_POOL" --validate-pool "$VALIDATE_POOL" "${PACE_ARGS[@]}" \
  ${GATE_REVIEW_FORMULA_ARGS[@]+"${GATE_REVIEW_FORMULA_ARGS[@]}"} || gate_rc=$?
if [ "$gate_rc" = "$GATE_UNSAFE_RC" ]; then
  note "gate-ensure UNSAFE (rc=$gate_rc) — an anchor has no check_set; merge.sh and pr-open.sh hold it on their own read"
elif [ "$gate_rc" != 0 ]; then
  FAILED="${FAILED}gate-ensure rc=$gate_rc; "
fi

# (7) pr-facts: same actor projection (it records closes too). Paced like the
# arms ahead of it, so the arms behind it still get their turn.
pace_args pr-facts
( export BEADS_ACTOR="$AGENT"
  run_pass "(7) pr-facts" pr-facts.sh --fix-pool "$FIX_POOL" "${PACE_ARGS[@]}" ) \
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

# (10) scaffolding-sweep: retire the machine review scaffolding
# (validation/finding/rework) hung on an anchor once that anchor is DISPOSED, so
# the disposed anchor can finalize instead of standing stuck behind scaffolding
# that will never resolve. Late, beside review-sweep, because it keys on a
# terminal disposition no earlier arm produces, and a disposal this pass is
# cleaned on the same tick. No projection and no merge authority: it writes only
# scaffolding beads, never the anchor — bead-rehome (via pr-facts' close arm)
# closes that, held by finalize-gate while a human visit is still owed.
run_pass "(10) scaffolding-sweep" scaffolding-sweep.sh || FAILED="${FAILED}scaffolding-sweep rc=$?; "

# (11) duplicate-sweep: dispose of verified no-op duplicate dispatches and of
# never-dispatched rework twins whose same-review sibling landed. Late, and
# after review-sweep, because the gate it re-verifies is a CLOSED successor: a
# twin that arm 2 merged or arm 7 recorded this pass is disposable on this tick
# rather than a minute later. BEADS_ACTOR projected — the close it delegates to
# bead-rehome is attributed in the events table.
( export BEADS_ACTOR="$AGENT"
  run_pass "(11) duplicate-sweep" duplicate-sweep.sh ) \
  || FAILED="${FAILED}duplicate-sweep rc=$?; "

# (12) pr-stack: bring each open PR's body current with its anchor in both managed
# regions — re-render the beads-on-this-branch section, and refresh the pr-summary
# region when a rework moved the anchor summary past the published one (pr-open
# composes that region only at pre_open_gate, which an open anchor never re-enters).
# Last, and after merge: a bead this pass landed onto another anchor's branch is in
# the ledger it reads, so the body names it on the same tick rather than a minute
# later. It writes only PR bodies — no bead, no merge authority — so it runs
# unprojected and its failure gates nothing.
pace_args pr-stack
run_pass "(12) pr-stack" pr-stack.sh "${PACE_ARGS[@]}" || FAILED="${FAILED}pr-stack rc=$?; "

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
