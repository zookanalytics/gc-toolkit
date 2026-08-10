#!/usr/bin/env bash
# quiesce-completed-workflows — stop the pool (and the affine hand-back) from
# re-offering the dead step beads of a graph.v2 molecule whose inline execution
# has already finished (tk-p9ji9).
#
# WHICH MOLECULES: every graph.v2 formula, identified by the contract below and
# not by name (tk-q5r65) — mol-polecat-work, mol-scoped-work, and whatever is
# poured next. The row filter is the membership test; see it below for why
# widening it removes no guard.
#
# Background. A graph.v2 formula (mol-polecat-work materializes 7 such steps)
# materializes step beads, but the polecat executes them INLINE in one session
# and no step closes its own bead.
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
#   AND THE ASSIGNEE HALF IS GATED ON IT (tk-d553m). Order alone only rules out
#   the pool-offer shape while the route clear SUCCEEDS. If it is refused and the
#   assignee clear runs anyway, that shape stops being a window and becomes the
#   step's resting state — strictly worse than the assigned+routed husk we found.
#   So a failed route clear skips the assignee clear: the step is left untouched
#   and counted failed, and the next patrol retries it whole.
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
#
# AND A FOURTH SHAPE, the longest-lived of them all (tk-rlm94): an anchor PARKED
# FOR A HUMAN DECISION — a refinery hold, a duplicate disposition, an escalation.
# It reads
#
#     status=blocked   merge_result=<absent>   assignee=<empty>   gc.routed_to=human
#
# and all three predicates above miss it, each for its own reason:
#
#   - `blocked` is not `closed`;
#   - merge_result was NEVER stamped, because the refinery held the bead BEFORE
#     dispatching a review or opening a PR (deliberately: reviewing a branch that
#     cannot land burns a signoff round). The tk-yxlqb assignee fallback was built
#     for exactly this "the refinery has not stamped yet" case, but it covers only
#     the beat BEFORE the stamp, not a hold that never reaches one;
#   - the assignee is EMPTY, because parking to a human clears it — the `*.refinery`
#     match needs the refinery to still HOLD the bead, and a held bead has been
#     handed onward.
#
# So the husk stayed armed, and unlike the earlier gaps — windows measured in
# minutes — this one lasts as long as a human takes to decide. Observed on root
# tk-i3noh / anchor tk-8d9u9: the same dead load-context step (tk-vgxlu) was
# re-offered five times in ~40 minutes, one fresh full-context polecat per session
# restart, each re-deriving "already done, take no action".
#
# CONJOINED, never bare `blocked`. That conjunction is what keeps this fail-closed,
# and the script's own warning is why: a false positive strips the assignee off
# steps a running polecat still has to claim and drains it mid-implementation. Bare
# `blocked` is reachable TRANSIENTLY by a live session — the escalation path sets
# blocked before it drains — whereas `blocked` + routed-to-human is only ever
# written by a pass that has already routed the work OFF the pool. `human` is
# matched exactly, the one spelling every writer uses (reconcile-merged-prs.sh,
# check-set-heal.sh, mol-refinery-patrol.toml); an unrecognized variant simply
# leaves the husk armed, which is the cheap failure.
#
# AND A FIFTH SHAPE, an anchor RE-CLAIMED BY ANOTHER SESSION (tk-nv3qr). When the
# refinery REJECTS a branch it clears the handoff and re-pools the anchor, and the
# next polecat claims it as a bare bead — exactly like the REQUEST_CHANGES rework
# path in the header (:56-63), it never re-walks this molecule's step graph. The
# anchor then reads
#
#     status=in_progress   merge_result=<absent>   assignee=<another polecat session>
#
# which satisfies none of the four predicates above: not closed, never re-stamped,
# not a refinery, and not parked for a human. So the husk stays armed for as long as
# the new owner holds the bead — and for the next owner after that, if it is rejected
# too. Observed on root tk-gonyp: its own load-context step was handed back to session
# lx-x3bt four minutes after lx-o9k2 claimed the anchor out of the pool.
#
# This clause and the park clause above were written in parallel against the same
# function. PR#272 (tk-rlm94) landed first and took $4 for gc.routed_to; this one
# was written against $4/$5 for the session pair and renumbered to $5/$6 when it was
# rebased onto that. Both are live and they are semantically independent — a
# re-claimed anchor is not parked (it is in_progress under a session, not blocked
# and routed off the pool), and a parked one is held by nobody at all.
#
# Those steps are dead by construction: `gc.session_affinity=require` binds them to
# the molecule's original session, and the work they describe now belongs to another
# one. No holder can ever advance them.
#
# BOTH conjuncts below are what keep this fail-closed, and neither is optional:
#
#   - the assignee must EQUAL the anchor's recorded session, which proves that
#     session is the CURRENT holder. `gc.session_name` is stamped at claim time and
#     is not cleared on release, so a bare "recorded session != molecule session"
#     test would also fire on a leftover from an earlier claim while the molecule's
#     own polecat is still running — stripping the assignee off steps that polecat
#     has yet to claim and draining it mid-implementation, the precise hazard the
#     fail-closed note below is about.
#   - all three values must be non-empty, so an anchor held under an agent or pool
#     name rather than a session name (no `gc.session_name` to compare) is left
#     alone rather than guessed at.
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
  case "$4" in                       # $4 = anchor metadata["gc.routed_to"]
    human) [ "$1" = blocked ] && return 0 ;;
  esac
  # $5 = anchor metadata.gc.session_name, $6 = this molecule's root gc.session_name
  if [ -n "$3" ] && [ -n "${5:-}" ] && [ -n "${6:-}" ] \
     && [ "$3" = "${5:-}" ] && [ "${5:-}" != "${6:-}" ]; then
    return 0
  fi
  return 1
}

STEPS=$(gc bd list --status=open,in_progress --json --limit=0 2>/dev/null)
[ -n "$STEPS" ] && [ "$STEPS" != "[]" ] \
  || { echo "quiesce-completed-workflows: no open work beads"; exit 0; }

# One compact row per live graph.v2 step bead. Built into a variable (not piped
# into the loop) so the loop runs in THIS shell and the counters survive.
#
# SELECTED BY CONTRACT, NOT BY FORMULA NAME (tk-q5r65). This filter used to read
# `startswith("mol-polecat-work.")`, which made every OTHER graph.v2 formula
# invisible to the pass — dropped here, before any anchor verdict, so its husks
# appeared in neither list of the summary and re-offered their never-closed
# load-context step forever. That is the exact burn this script exists to stop,
# and the prefix meant it could not see it. Verified live on mol-scoped-work, a
# CORE pack formula: root tk-917ov's husk kept 28 live steps and consumed ~1
# fresh full-context polecat per session restart, sub-5-minute cadence, while
# `--dry-run` reported the root nowhere at all.
#
# The header's rationale is stated in CONTRACT terms — graph.v2 materializes step
# beads, the polecat executes them inline, no step closes its own bead, the chain
# leaves load-context open and routed — and every graph.v2 formula satisfies it
# identically. The prefix was an accident of which formula existed when the pass
# was written.
#
# WHAT KEEPS THIS SAFE is not the filter; it is the fail-closed anchor gate below
# (root -> gc.input_convoy_id -> the convoy's SINGLE tracked member -> readable
# status -> is_terminal_anchor). That gate already refuses everything it does not
# understand: no convoy, a convoy with any member count but one, an unreadable
# anchor, and a live anchor all skip the root untouched. Widening the row filter
# hands it more candidates to refuse; it removes no guard. A non-graph.v2 bead
# carries no `gc.step_ref` at all and is never a candidate in the first place, so
# the predicate below is the whole membership test.
#
# The root requirement is BELT-AND-BRACES, and deliberately so. It changes no
# behavior today: a step with no `gc.root_bead_id` is already excluded from ROOTS
# by that reduction's own `select(. != "")`, and the per-root row match below can
# never equal an empty root either. It is stated here so the row set means
# exactly one thing — "a graph.v2 step that could be anchor-verified" — rather
# than leaving that to be inferred from two downstream reductions. With the
# formula name no longer carrying the membership rule, this filter is where the
# rule should be legible.
ROWS=$(printf '%s' "$STEPS" | jq -c '
  .[]
  | select((.metadata["gc.step_ref"] // "") != "")
  | select((.metadata["gc.root_bead_id"] // "") != "")
  | {
      id,
      step:     (.metadata["gc.step_ref"] // ""),
      root:     (.metadata["gc.root_bead_id"] // ""),
      routed:   (.metadata["gc.routed_to"] // ""),
      assignee: (.assignee // "")
    }' 2>/dev/null)
[ -n "$ROWS" ] \
  || { echo "quiesce-completed-workflows: no live graph.v2 workflow steps"; exit 0; }

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
# tool timeout in practice. Per-root batching also keeps a partial pass coherent to
# read: one anchor verdict, then that root's step lines. It does NOT make a root
# atomic — a single step can land its route clear and still be refused the assignee
# clear, which counts as failed (not quiesced) so the next patrol resumes from
# whichever key is still set.
while IFS= read -r root; do
  [ -n "${root:-}" ] || continue

  # Resolve the anchor the way the formula itself does: root -> input convoy ->
  # its single tracked member. Both mol-polecat-base and mol-scoped-work require
  # exactly one member (each refuses to run otherwise), so anything else is a
  # shape we do not understand — and, with the row filter selecting by contract
  # rather than by formula name, this is also the gate that turns away a graph.v2
  # formula built on some other anchoring shape. Refusing it costs a husk that
  # stays noisy; guessing costs a live molecule drained mid-implementation.
  #
  # One read, two values: the convoy, and the session this molecule's steps are
  # bound to (`gc.session_affinity=require`). The session is what the re-claim
  # predicate compares the anchor's current holder against; an empty one simply
  # means the molecule was never claimed, and the predicate fails closed on it.
  rootinfo=$(gc bd show "$root" --json 2>/dev/null \
    | jq -r '.[0] | "\(.metadata["gc.input_convoy_id"] // "")|\(.metadata["gc.session_name"] // "")"' 2>/dev/null)
  convoy=""; rsession=""
  IFS='|' read -r convoy rsession <<< "$rootinfo"
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

  # ONE read, five fields. `gc.routed_to` rides along in the same call the first
  # three already come from (tk-rlm94), and `gc.session_name` alongside it
  # (tk-nv3qr) — the park predicate needs the one and the re-claim predicate needs
  # the other, and reading either separately would let the halves of one verdict
  # describe two different observations of the anchor.
  ainfo=$(gc bd show "$anchor" --json 2>/dev/null \
    | jq -r '.[0] | "\(.status // "")|\(.metadata.merge_result // "")|\(.assignee // "")|\(.metadata["gc.routed_to"] // "")|\(.metadata["gc.session_name"] // "")"' 2>/dev/null)
  astatus=""; amerge=""; aassignee=""; arouted=""; asession=""
  IFS='|' read -r astatus amerge aassignee arouted asession <<< "$ainfo"
  # Every real bead carries a status, so an empty one means the READ failed (bead
  # gone, jq error, Dolt hiccup) rather than "an anchor with no status". Fail
  # closed on it, same as an unresolved anchor.
  if [ -z "$astatus" ]; then
    echo "quiesce-completed-workflows: root $root — anchor $anchor unreadable; skipped" >&2
    unresolved=$((unresolved + 1)); continue
  fi

  # The session pair is appended only when it is actually recorded, so the log line
  # for the four older shapes is unchanged — but a re-claim verdict has to say WHICH
  # two sessions it compared, since that is the whole basis for the call and this
  # pass is meant to be reversible by hand.
  adesc="status=$astatus merge_result=${amerge:-none} assignee=${aassignee:-none} routed_to=${arouted:-none}"
  [ -z "$asession" ] || adesc="$adesc session=$asession"
  [ -z "$rsession" ] || adesc="$adesc molecule_session=$rsession"
  if ! is_terminal_anchor "$astatus" "$amerge" "$aassignee" "$arouted" "$asession" "$rsession"; then
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
    route_ok=1

    # Pool channel. No claim is involved, so this half needs no --force — but it
    # can still be refused by the store (a wedged write, a transient error), and
    # the half below is gated on whether it landed.
    if [ -n "$routed" ]; then
      if ! gc bd update "$sid" --unset-metadata gc.routed_to >/dev/null 2>&1; then
        echo "quiesce-completed-workflows: $sid route clear failed; retries next patrol" >&2
        step_ok=0; route_ok=0
      fi
    fi

    # Affine hand-back channel. Needs --force past the claim guard, hence bare bd.
    # GATED ON THE ROUTE CLEAR (tk-d553m): route-first is only a safety barrier
    # while the assignee clear cannot outlive a route that survived. Clear the
    # assignee on a step whose gc.routed_to is still set and the result is open +
    # unassigned + routed — the pool-offer shape the ordering exists to prevent,
    # and now a durable state rather than a momentary window. So a refused route
    # clear skips this half entirely: the step is left exactly as it was, already
    # counted failed above, and the next patrol retries both keys from a shape it
    # understands.
    if [ -n "$who" ] && [ "$route_ok" -eq 1 ]; then
      if [ -z "$BD_BIN" ] \
         || ! "$BD_BIN" update "$sid" --assignee "" --force >/dev/null 2>&1; then
        echo "quiesce-completed-workflows: $sid assignee clear failed; retries next patrol" >&2
        step_ok=0
      fi
    elif [ -n "$who" ]; then
      echo "quiesce-completed-workflows: $sid assignee clear skipped (route clear failed; clearing it now would leave the step open+unassigned+routed); retries next patrol" >&2
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
