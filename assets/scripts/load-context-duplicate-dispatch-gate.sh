#!/usr/bin/env bash
# load-context-duplicate-dispatch-gate — refuse to build a work bead that is not
# this session's to build, before mol-polecat-work's load-context touches the
# workspace.
#
#   load-context-duplicate-dispatch-gate.sh --bead <work-bead> --convoy <input-convoy>
#                                           [--step-bead <claimed step bead>]
#
# Two dispatch surfaces can reach one work bead: the mol-polecat-work molecule,
# and a direct pool route left on the bead itself. When both fire, two workers
# set up the same branch and one silently destroys the other's commits. So the
# gate proves the bead is readable, not parked, not in flight under another live
# owner, and not already finished.
#
# The bead's status decides first. Only an open or in_progress bead can be built,
# so only those reach the owner check. Every refusal holds the molecule at
# load-context, and the refusals split by whether a human has a decision to make.
#
# A FINISHED bead (closed, a completed hand-off, or carrying a merge_result) is
# not a live conflict. Its work has landed, is landing with the refinery, or was
# ruled unnecessary by whoever closed it. The gate quiesces the molecule and
# drains with no visit, because a visit answers nothing there and a hold behind
# one has no way back: molecule-hold.sh is one-way and dead-molecule-dispose.sh
# refuses a live root. molecule-hold.sh never touches the work bead, so a closed
# bead stays closed and a handed-off bead stays with the refinery while its PR
# proceeds. A closed bead's note and hold reason read `closed before claim` and
# carry what the bead records about its close, so a duplicate close reads
# differently from a merge.
#
# Three other refusals need a human, and each files its own visit:
#   - a LIVE conflict, in flight under a foreign owner still present in
#     `gc session list --state all`, is two dispatches building at once;
#   - an UNREADABLE bead proves nothing, so no liveness answer can clear it;
#   - a PARKED bead (blocked, deferred, hooked, pinned) waits on whoever parked
#     it, and releasing it does not resume a held molecule.
#
# Owner liveness gates the in-flight case only. An idle pool worker between
# claims looks identical to an abandoned one, so an in_progress bead is a
# conflict only while its owner is present in the session list. A crashed owner
# leaves the work this session's to take.
#
# The step is held, never closed: closing advances the workflow into
# workspace-setup, which recreates the branch and destroys a live worker's
# uncommitted work. escalate-hold-drain.sh files the visit, holds and drains,
# each only after the one before it landed.
#
# env: GC_SESSION_NAME, GC_SESSION_ID, GC_AGENT and GC_ALIAS name this session;
#      GC_ESCALATE_HOLD_DRAIN_TOOL replaces the sibling escalate-hold-drain.sh.
# exit: 0 the bead is this session's to build · 1 refused (held and drained when
#       the hold landed) · 2 usage
set -uo pipefail

PROG="load-context-duplicate-dispatch-gate"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
EHD="${GC_ESCALATE_HOLD_DRAIN_TOOL:-$SCRIPTS_DIR/escalate-hold-drain.sh}"

usage() {
  echo "usage: $PROG --bead <work-bead> --convoy <input-convoy> [--step-bead <claimed step bead>]" >&2
}

WORK_BEAD_ID=""; CONVOY_ID=""; CLAIMED_STEP_BEAD_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead|--convoy|--step-bead)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; usage; exit 2; }
      case "$1" in
        --bead)      WORK_BEAD_ID="$2" ;;
        --convoy)    CONVOY_ID="$2" ;;
        --step-bead) CLAIMED_STEP_BEAD_ID="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if [ -z "$WORK_BEAD_ID" ] || [ -z "$CONVOY_ID" ]; then
  echo "$PROG: --bead and --convoy are required" >&2
  usage
  exit 2
fi

WORK_BEAD_JSON=$(gc bd show "$WORK_BEAD_ID" --json 2>/dev/null)
WORK_STATUS=$(printf '%s' "$WORK_BEAD_JSON" | jq -r '.[0].status // empty' 2>/dev/null)
WORK_OWNER=$(printf '%s' "$WORK_BEAD_JSON" | jq -r '.[0].assignee // empty' 2>/dev/null)
WORK_MERGE_RESULT=$(printf '%s' "$WORK_BEAD_JSON" | jq -r '.[0].metadata.merge_result // empty' 2>/dev/null)
# A refusal sets WHY. A finished bead keeps the default labels and sets no
# ESCALATE_KEY, so it quiesces without a visit; every other refusal names the
# visit a human must answer.
WHY=""
NOTE_LABEL="Duplicate dispatch refused (work finished; quiesced without escalation)"
HOLD_LABEL="duplicate dispatch (work finished)"
ESCALATE_KEY=""
ESCALATE_MESSAGE=""
# A merge_result stamp means a PR or merge already exists for THIS bead (fresh
# work is its own anchor), and it outlives a cleared assignee.
MERGED=""
[ -n "$WORK_MERGE_RESULT" ] && MERGED="already carrying merge_result=$WORK_MERGE_RESULT; a PR or merge exists for this bead"
case "$WORK_STATUS" in
  "")
    WHY="unreadable (gc bd show returned no status)"
    NOTE_LABEL="Unreadable work bead; held for a human"
    HOLD_LABEL="unreadable work bead"
    ESCALATE_KEY=polecat-unreadable-work
    ESCALATE_MESSAGE="Could not read work bead $WORK_BEAD_ID at load-context (gc bd show returned no status), so nothing proves it is safe to build. Held at load-context; no workspace was touched and nothing was closed. Check that the bead exists and its store answers, then re-offer this molecule." ;;
  closed)
    # Closed is finished whoever holds it. A close that lands after the pour,
    # such as a duplicate or a no-work close, leaves the assignee empty and
    # stamps no merge_result, so the reason carries what the bead records about
    # its close.
    if [ -n "$MERGED" ]; then
      WHY="$MERGED"
    else
      CLOSED_HOW=$(printf '%s' "$WORK_BEAD_JSON" | jq -r '.[0] | [(.metadata["gc.superseded_by"] // "" | tostring | select(length > 0) | "superseded by " + .), (.metadata["gc.outcome"] // "" | tostring | select(length > 0) | "outcome " + .), (.close_reason // "" | tostring | gsub("[[:space:]]+"; " ") | select(length > 0) | "close reason: " + .[0:200])] | join("; ")' 2>/dev/null)
      WHY="already closed${CLOSED_HOW:+ ($CLOSED_HOW)}; its work is done or was ruled unnecessary"
      NOTE_LABEL="Closed before claim; quiesced without escalation"
      HOLD_LABEL="closed before claim"
    fi ;;
  open|in_progress)
    case "$WORK_OWNER" in
      ""|"${GC_SESSION_NAME:-}"|"${GC_SESSION_ID:-}"|"${GC_AGENT:-}"|"${GC_ALIAS:-}") ;;   # unowned, or owned by this session
      *)
        if [ "$WORK_STATUS" = "in_progress" ]; then
          # In flight: a live worker may still hold it, so the hold is gated on
          # that owner being alive. An assignee is any of the three forms a
          # claim writes — the session name (what `gc bd update --claim` sets),
          # the session id, or the agent address — and a session record exposes
          # them as .session_name, .id and .alias respectively, with no .name
          # field. Match all of them.
          OWNER_LIVE=$(gc session list --state all --json 2>/dev/null | jq -r --arg o "$WORK_OWNER" '[.sessions[]? | select(((.alias // "") == $o) or ((.alias // "") | endswith($o)) or ((.session_name // "") == $o) or ((.id // "") == $o))] | length' 2>/dev/null)
          # No answer means the probe could not disprove a live owner — assume one.
          if [ "${OWNER_LIVE:-1}" != "0" ]; then
            WHY="already in_progress under live $WORK_OWNER"
            NOTE_LABEL="Duplicate dispatch refused"
            HOLD_LABEL="duplicate dispatch"
            ESCALATE_KEY=polecat-duplicate-dispatch
            ESCALATE_MESSAGE="Duplicate dispatch on $WORK_BEAD_ID: it is $WHY, and convoy $CONVOY_ID dispatched it again to ${GC_SESSION_NAME:-}. Held at load-context; no workspace was touched and nothing was closed. Two dispatches are live: decide which owns the bead, then re-offer that one."
          fi
        else
          # Open under a foreign assignee is a completed hand-off, not a live
          # conflict: the refinery handoff leaves the bead open, assigned to
          # the refinery, route cleared. A fresh or rework dispatch reaches
          # load-context with an empty assignee (routed by gc.routed_to, cleared
          # on re-dispatch), so a foreign one here means another dispatch
          # already carried the work past this point. Building it now rebuilds a
          # branch that already has a PR, so the liveness gate does not apply.
          WHY="already handed off (open, held by $WORK_OWNER); another dispatch carried it past this point"
        fi ;;
    esac
    [ -z "$WHY" ] && WHY="$MERGED" ;;
  *)
    # blocked, deferred, hooked, pinned: whoever parked the bead releases it,
    # and a release does not resume a held molecule, so a visit is what says
    # this one needs re-offering. A merge_result still reads as finished:
    # the PR is with the refinery.
    if [ -n "$MERGED" ]; then
      WHY="$MERGED"
    else
      WHY="parked (status $WORK_STATUS), so it is not this session's to build"
      NOTE_LABEL="Parked work bead; held for a human"
      HOLD_LABEL="parked work bead"
      ESCALATE_KEY=polecat-parked-work
      ESCALATE_MESSAGE="Work bead $WORK_BEAD_ID is $WORK_STATUS, and convoy $CONVOY_ID reached ${GC_SESSION_NAME:-} with it. A parked bead is not built, so its molecule is held at load-context; no workspace was touched and nothing was closed. Releasing the bead does not resume the molecule: once the bead is ready to build, re-offer this molecule."
    fi ;;
esac
[ -n "$WHY" ] || exit 0

# The note is the bead's own record of the refusal. The hold reason on the step
# carries the same text, so a note the store refuses is reported here and the
# hold still runs.
gc bd update "$WORK_BEAD_ID" --append-notes "$NOTE_LABEL: ${GC_SESSION_NAME:-} found $WORK_BEAD_ID $WHY." || echo "The refusal note did not land on $WORK_BEAD_ID; the hold reason on this step still records it." >&2
HOLD_ARGS=(--step mol-polecat-work.load-context --bead "$CLAIMED_STEP_BEAD_ID" --reason "$HOLD_LABEL: $WORK_BEAD_ID $WHY")
if [ -n "$ESCALATE_KEY" ]; then
  HOLD_ARGS+=(--subject "$WORK_BEAD_ID" --key "$ESCALATE_KEY" --message "$ESCALATE_MESSAGE")
fi
"$EHD" "${HOLD_ARGS[@]}"
exit 1
