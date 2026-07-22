#!/usr/bin/env bash
# quiesce-completed-workflows — stop the pool (and the affine hand-back) from
# re-offering the dead step beads of a mol-polecat-work molecule whose inline
# execution has already finished (tk-p9ji9).
#
# Background. mol-polecat-work (graph.v2) materializes 7 step beads, but the
# polecat executes them INLINE in one session and no step closes its own bead.
# The step graph is chained (load-context blocks workspace-setup blocks ...), so
# while load-context stays open it is the ONLY ready step — and it still carries
# `gc.routed_to=<rig>/<prefix>polecat`. Open + ready + routed is exactly the
# pool's offer predicate, so every idle polecat is handed the same dead step,
# forever: ~1 wisp per 4-5 min for the entire human-approval wait on the PR. The
# molecule cannot finalize itself either, because under close-on-land its anchor
# stays OPEN until the refinery lands the PR.
#
# The witness has been containing this BY HAND, molecule by molecule (ten of them
# as of 2026-07-22). This pass is that containment, automated.
#
# TWO re-offer shapes, two different levers — clearing `gc.routed_to` alone fixes
# only the first (verified live: `gc hook <pool-agent>` returns open, UNASSIGNED,
# routed, ready beads only, so an assigned step never rides the pool path):
#
#   unassigned shape  assignee empty + gc.routed_to set
#                     -> the POOL offers it. Clearing gc.routed_to removes it.
#   assigned shape    assignee=<polecat session> + gc.session_affinity=require
#                     -> already invisible to the pool; it is handed back on the
#                        ASSIGNED-work path, keyed on the assignee. Clearing
#                        gc.routed_to here is a NO-OP; the assignee must go too.
#
# Both keys are cleared in ONE `gc bd update`. Order matters and a two-call
# sequence is unsafe: clearing the assignee first would briefly leave the bead
# open + unassigned + routed — the exact pool-offer shape — racing a fresh
# polecat into the husk we are trying to retire.
#
# WHAT THIS PASS NEVER DOES — closing a step bead is the footgun this bug exists
# to prevent. Closing load-context unblocks workspace-setup and walks the next
# polecat forward onto a branch that is ALREADY green-gated and PR'd; any push
# there moves the head, stales the anchor's `check.<gate>=green@<oid>` marker and
# BLOCKS the open PR from merging. There is deliberately no close path in this
# script. It also never touches the anchor, never touches `status`, and never
# touches the `workflow-finalize` step (routed to the control dispatcher — that
# is the path that finalizes the graph, and it must keep its route).
#
# Quiescing is containment, not finalization: the molecule is left stranded-but-
# quiet, which is what the witness's manual sweep achieves today. Finalizing the
# step graph at submit-and-exit time is the durable upstream fix (gascity core /
# gastown formula) and is deliberately out of scope here.
#
# NOT set -e: best-effort, must never abort the witness patrol. Any tool error
# skips that root and retries next patrol cycle.
set -uo pipefail

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) shift ;;
  esac
done

# Anchor states that mean "the workflow's inline execution is DONE".
#
#   pre_open_gate  polecat handed off; codex is reviewing the BRANCH, no PR yet
#   pull_request   PR open, parked in the merge gate awaiting human approval
#   merged         PR landed; the anchor closes on the refinery's reconcile pass
#
# `merged` and a CLOSED anchor (handled separately below) are strictly-later
# lifecycle states than `pull_request`: if the steps are dead at pull_request they
# are dead afterwards too. A closed anchor is the safest case of all — the work
# bead itself is finished.
#
# The three merge_result values above are all stamped BY THE REFINERY, which is a
# beat behind the polecat's own hand-off. That leaves a window those predicates
# miss (tk-yxlqb): between the polecat's done sequence (push, reassign the anchor
# to the refinery) and the refinery's first stamp, the anchor reads
#
#     status=open   merge_result=<absent>   assignee=<rig>/<prefix>refinery
#
# — which looks "still live" while the molecule is already dead, so the husk keeps
# burning polecats for the whole window. Observed on tk-2l13a: ~17 minutes, two
# sessions consumed re-deriving "already done". A periodic pass that happens to run
# mid-window leaves the husk armed until the next cycle, so the window is not
# self-healing. The assignee closes it exactly: an anchor handed to the refinery is
# by definition past polecat work, stamped or not.
#
# Matching is on the assignee's final dotted component, after dropping the optional
# `<rig>/` qualifier — the live shapes are `<rig>/gc-toolkit.refinery` and
# `<rig>/gastown.refinery`, and a bare `refinery` is the un-prefixed binding. The
# match is deliberately anchored rather than a loose `*refinery*` substring: a false
# positive here quiesces a LIVE molecule (see the fail-closed note below), so only
# an assignee that IS a refinery may satisfy it.
is_terminal_anchor() {
  case "$1" in                       # $1 = anchor status
    closed) return 0 ;;
  esac
  case "$2" in                       # $2 = anchor metadata.merge_result
    pre_open_gate|pull_request|merged) return 0 ;;
  esac
  case "${3##*/}" in                 # $3 = anchor assignee, minus any <rig>/ prefix
    refinery|*.refinery) return 0 ;;
  esac
  return 1
}

STEPS=$(gc bd list --status=open,in_progress --json --limit=0 2>/dev/null)
[ -n "$STEPS" ] && [ "$STEPS" != "[]" ] \
  || { echo "quiesce-completed-workflows: no open work beads"; exit 0; }

# One compact row per live mol-polecat-work step bead. Built into a variable (not
# piped into the loop) so the loop runs in THIS shell and the counters survive.
ROWS=$(printf '%s' "$STEPS" | jq -c '
  .[]
  | select((.metadata["gc.step_ref"] // "") | startswith("mol-polecat-work."))
  | {
      id,
      step:     (.metadata["gc.step_ref"] // ""),
      root:     (.metadata["gc.root_bead_id"] // ""),
      routed:   (.metadata["gc.routed_to"] // ""),
      assignee: (.assignee // "")
    }' 2>/dev/null)
[ -n "$ROWS" ] \
  || { echo "quiesce-completed-workflows: no live mol-polecat-work steps"; exit 0; }

ROOTS=$(printf '%s\n' "$ROWS" | jq -r -s 'map(.root) | map(select(. != "")) | unique | .[]' 2>/dev/null)
[ -n "$ROOTS" ] \
  || { echo "quiesce-completed-workflows: no resolvable workflow roots"; exit 0; }

quiesced=0; roots_done=0; roots_live=0; already=0; unresolved=0

# Batched per ROOT, deliberately: a rig with several husks is ~6 `gc bd update`
# calls per root, and sweeping every bead in one flat pass has blown a 2-minute
# tool timeout in practice. Per-root batching also makes a partial pass coherent —
# a molecule is either quiesced or untouched, never half-swept.
while IFS= read -r root; do
  [ -n "${root:-}" ] || continue

  # Resolve the anchor the way the formula itself does: root -> input convoy ->
  # its single tracked member. mol-polecat-base requires exactly one member, so
  # anything else is a shape we do not understand.
  convoy=$(gc bd show "$root" --json 2>/dev/null \
    | jq -r '.[0].metadata["gc.input_convoy_id"] // empty' 2>/dev/null)
  anchor=""
  [ -n "$convoy" ] && anchor=$(gc convoy status "$convoy" --json 2>/dev/null \
    | jq -r 'if ((.children // []) | length) == 1 then (.children[0].id // empty) else empty end' 2>/dev/null)

  # FAIL CLOSED on an unresolved anchor. Quiescing a LIVE molecule would strip the
  # assignee off the steps a running polecat still has to claim, draining it
  # mid-implementation and stranding real work. An un-quiesced husk only wastes
  # wisps — the cheaper failure by far, and the witness still catches it by hand.
  if [ -z "$anchor" ]; then
    echo "quiesce-completed-workflows: root $root — anchor unresolved (convoy '${convoy:-none}'); skipped" >&2
    unresolved=$((unresolved + 1)); continue
  fi

  ainfo=$(gc bd show "$anchor" --json 2>/dev/null \
    | jq -r '.[0] | "\(.status // "")|\(.metadata.merge_result // "")|\(.assignee // "")"' 2>/dev/null)
  astatus=""; amerge=""; aassignee=""
  IFS='|' read -r astatus amerge aassignee <<< "$ainfo"
  # Every real bead carries a status, so an empty one means the READ failed (bead
  # gone, jq error, Dolt hiccup) rather than "an anchor with no status". Fail
  # closed on it, same as an unresolved anchor.
  if [ -z "$astatus" ]; then
    echo "quiesce-completed-workflows: root $root — anchor $anchor unreadable; skipped" >&2
    unresolved=$((unresolved + 1)); continue
  fi

  adesc="status=$astatus merge_result=${amerge:-none} assignee=${aassignee:-none}"
  if ! is_terminal_anchor "$astatus" "$amerge" "$aassignee"; then
    echo "quiesce-completed-workflows: root $root — anchor $anchor still live ($adesc); left alone"
    roots_live=$((roots_live + 1)); continue
  fi

  echo "quiesce-completed-workflows: root $root — anchor $anchor DONE ($adesc); quiescing steps"
  roots_done=$((roots_done + 1))

  while IFS= read -r row; do
    [ -n "${row:-}" ] || continue
    sid=$(printf '%s'   "$row" | jq -r '.id // empty')
    step=$(printf '%s'  "$row" | jq -r '.step // empty')
    routed=$(printf '%s' "$row" | jq -r '.routed // empty')
    who=$(printf '%s'   "$row" | jq -r '.assignee // empty')
    [ -n "$sid" ] || continue

    # NEVER touch the finalize step: it is routed to the control dispatcher, which
    # is the machinery that actually closes the graph out. De-routing it would
    # remove the molecule's only escape path. Guarded twice — by step id and by
    # route — because losing this one is unrecoverable without a hand repair.
    case "$step" in *.workflow-finalize) continue ;; esac
    case "$routed" in *control-dispatcher*) continue ;; esac

    # Idempotent: nothing left to clear means a previous pass (or the witness by
    # hand) already quiesced this step.
    if [ -z "$routed" ] && [ -z "$who" ]; then
      already=$((already + 1)); continue
    fi

    # Snapshot the prior values into the patrol log — this action is meant to be
    # reversible by hand, so the log has to say what was there.
    echo "  $sid ($step): routed='${routed:-none}' assignee='${who:-none}' -> cleared"
    if [ "$DRY_RUN" -eq 1 ]; then
      quiesced=$((quiesced + 1)); continue
    fi

    # Both keys in ONE update (see the header note on the two-call race). Only the
    # keys actually present are touched, so sibling metadata stays intact and the
    # bead's status is never rewritten.
    UPDATE_ARGS=("$sid")
    [ -n "$routed" ] && UPDATE_ARGS+=(--unset-metadata gc.routed_to)
    [ -n "$who" ]    && UPDATE_ARGS+=(--assignee "")
    if gc bd update "${UPDATE_ARGS[@]}" >/dev/null 2>&1; then
      quiesced=$((quiesced + 1))
    else
      echo "quiesce-completed-workflows: $sid update failed; retries next patrol" >&2
    fi
  done <<< "$(printf '%s\n' "$ROWS" | jq -c --arg r "$root" 'select(.root == $r)' 2>/dev/null)"
done <<< "$ROOTS"

MODE=""
[ "$DRY_RUN" -eq 1 ] && MODE="(dry-run) "
echo "quiesce-completed-workflows: ${MODE}${quiesced} steps quiesced across $roots_done completed workflow(s); $roots_live still live, $already already quiet, $unresolved unresolved"
exit 0
