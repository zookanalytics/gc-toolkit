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
# The two keys are cleared in TWO SEPARATE calls, ROUTE FIRST, then the assignee
# (tk-z27pw). Every part of that shape is load-bearing:
#
#   WHY NOT ONE CALL. bd's claim guard refuses `--assignee ""` on an in_progress
#   step still held by a live session. Batched into a single `gc bd update`, that
#   rejection rolls the WHOLE update back — so `gc.routed_to` is not cleared
#   either, even though unsetting routing alone needs no claim at all. The step
#   stays fully re-offerable, the pass logs "update failed; retries next patrol"
#   every cycle forever, and (before this fix) still exited 0. Splitting the calls
#   means the half that can always land, always lands.
#
#   WHY ROUTE FIRST. The race the single-call design guarded against is real, but
#   it is an ORDER hazard, not a call-count one: clearing the assignee first leaves
#   the bead briefly open + unassigned + routed — the exact pool-offer shape —
#   racing a fresh polecat into the husk we are retiring. Clearing the route first
#   inverts that. The intermediate state is open + assigned + unrouted, which is
#   invisible to the pool, and the assigned hand-back it still rides is simply the
#   state the bead was already in. The window exposes nothing new.
#
#   WHY --force ON THE ASSIGNEE. We only reach this point when is_terminal_anchor()
#   says the anchor is DONE — i.e. the step graph is SPENT. A REQUEST_CHANGES
#   verdict dispatches rework as a STANDALONE bead (no `gc.step_ref`) sourced from
#   the review bead; it never re-walks the molecule's step graph. So no holder can
#   resume a step of a terminal molecule: the claim is abandoned in exactly the
#   sense --force is reserved for, even while the holding session is alive and
#   looks busy (it is busy re-deriving "already done"). That terminal-anchor check
#   IS the gate on --force — never use it where that gate has not already passed.
#
#   WHY BARE `bd` FOR THAT ONE CALL. `gc bd` rejects --force in its bead-ID safety
#   pre-check ("cannot safely verify bead IDs (unrecognized flag in args)") and
#   exits 1, so through the wrapper the clear can never land at all. Bare `bd` is
#   the same binary on the same store — it honors the BEADS_DIR the agent env
#   already pins. The pre-check the wrapper adds guards substring resolution of a
#   PARTIAL id; every id here comes verbatim from `gc bd list`, so it is exact.
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
# NOT set -e: best-effort, must never abort the witness patrol mid-pass. Any tool
# error skips that root and retries next patrol cycle.
#
# But the pass EXITS NON-ZERO when any step update failed (tk-z27pw). Every root
# is still attempted first — the exit code is a verdict on the whole pass, not an
# abort. A blanket exit 0 over failed writes is what hid this bug for a day: the
# script printed "-> cleared" for three steps, then "0 steps quiesced", and still
# reported success. The patrol's call site already treats a non-zero exit as
# non-fatal ("pass failed (non-fatal); retries next cycle"), so telling the truth
# costs the patrol nothing.
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
is_terminal_anchor() {
  case "$1" in                       # $1 = anchor status
    closed) return 0 ;;
  esac
  case "$2" in                       # $2 = anchor metadata.merge_result
    pre_open_gate|pull_request|merged) return 0 ;;
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

quiesced=0; roots_done=0; roots_live=0; already=0; unresolved=0; failed=0

# The assignee half needs `bd ... --force`, which `gc bd` refuses (see header).
# Resolve the binary once, so a rig without `bd` on PATH says so plainly instead
# of surfacing as N opaque per-step failures.
BD_BIN=$(command -v bd 2>/dev/null || true)
[ -n "$BD_BIN" ] || echo "quiesce-completed-workflows: bd not on PATH; assigned-shape steps cannot be cleared (gc bd refuses --force)" >&2

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
    | jq -r '.[0] | "\(.status // "")|\(.metadata.merge_result // "")"' 2>/dev/null)
  if [ -z "$ainfo" ] || [ "$ainfo" = "|" ]; then
    echo "quiesce-completed-workflows: root $root — anchor $anchor unreadable; skipped" >&2
    unresolved=$((unresolved + 1)); continue
  fi
  astatus=${ainfo%%|*}; amerge=${ainfo##*|}

  if ! is_terminal_anchor "$astatus" "$amerge"; then
    echo "quiesce-completed-workflows: root $root — anchor $anchor still live (status=$astatus merge_result=${amerge:-none}); left alone"
    roots_live=$((roots_live + 1)); continue
  fi

  echo "quiesce-completed-workflows: root $root — anchor $anchor DONE (status=$astatus merge_result=${amerge:-none}); quiescing steps"
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
    # reversible by hand, so the log has to say what was there. It says "clearing",
    # not "cleared": the writes below can still be refused, and a line that claims
    # the past tense before the fact is half of what made this pass lie.
    echo "  $sid ($step): routed='${routed:-none}' assignee='${who:-none}' -> clearing"
    if [ "$DRY_RUN" -eq 1 ]; then
      quiesced=$((quiesced + 1)); continue
    fi

    # TWO calls, route first — see the header on order, on --force, and on why a
    # single batched update cannot work. Only the keys actually present are
    # touched, so sibling metadata stays intact and status is never rewritten.
    # Each half is tracked separately: a step whose route cleared but whose
    # assignee did not is a PARTIAL clear, and counts as a failure, not a success.
    step_ok=1

    # Pool channel. No claim is involved, so this half always lands.
    if [ -n "$routed" ]; then
      if ! gc bd update "$sid" --unset-metadata gc.routed_to >/dev/null 2>&1; then
        echo "quiesce-completed-workflows: $sid route clear failed; retries next patrol" >&2
        step_ok=0
      fi
    fi

    # Affine hand-back channel. Needs --force past the claim guard, hence bare bd.
    if [ -n "$who" ]; then
      if [ -z "$BD_BIN" ] \
         || ! "$BD_BIN" update "$sid" --assignee "" --force >/dev/null 2>&1; then
        echo "quiesce-completed-workflows: $sid assignee clear failed; retries next patrol" >&2
        step_ok=0
      fi
    fi

    if [ "$step_ok" -eq 1 ]; then
      quiesced=$((quiesced + 1))
    else
      failed=$((failed + 1))
    fi
  done <<< "$(printf '%s\n' "$ROWS" | jq -c --arg r "$root" 'select(.root == $r)' 2>/dev/null)"
done <<< "$ROOTS"

MODE=""
[ "$DRY_RUN" -eq 1 ] && MODE="(dry-run) "
echo "quiesce-completed-workflows: ${MODE}${quiesced} steps quiesced across $roots_done completed workflow(s); $roots_live still live, $already already quiet, $unresolved unresolved, $failed failed"

# Failed WRITES make the pass dishonest if swallowed; an unresolved anchor does
# not — that one is a deliberate fail-closed skip, already reported, and correct.
# So only $failed decides the exit code.
[ "$failed" -eq 0 ] || exit 1
exit 0
