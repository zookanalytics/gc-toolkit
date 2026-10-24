#!/usr/bin/env bash
# rejection-repool.sh — the refinery's rejection: hands a work bead it will not
# land back to the polecat pool as a fresh mol-polecat-work pour, never as a
# route on the bead itself.
#   rejection-repool.sh <work-bead> --reason <rejection_reason> [--pool <pool-name>]
# --pool defaults to gc-toolkit.polecat. Callers: formulas/mol-refinery-patrol.toml,
# from the rebase step's conflict arm and the handle-failures step's
# branch-caused arm. Both run `gc workflow reopen-source` first, which leaves
# the bead open with no assignee, out of the refinery's queue.
# Stdout is one line: the bead's row as read before any write (the scrubbed
# `gc bd show --json` array), which the handle-failures arm's branch decision
# reads instead of a read of its own. Of the fields that decision reads, the
# release writes only existing_pr, and only from a pr_url the decision already
# counts. Stdout is empty when the bead could not be read.
#
# A pour, because the work bead is a member of its epic and bd's blocked flag
# cascades down parent-child edges: a bead routed back to the pool is withheld
# from `bd ready` while any ancestor waits on an open blocker, so a park on the
# epic would strand work already built. A poured workflow's root has no parent
# and its steps hang off it by tracks edges, so no cascade reaches the rebuild
# (specs/tk-rl8gz4b.2/steer-by-epic.md, section 1).
#
# A convoy is never the bead poured. gc sling takes a convoy target as the
# run's own input convoy, so that run works on the beads the convoy tracks, and
# mol-polecat-work takes the one bead its input convoy tracks as its work bead.
# A graduation's anchor is such a convoy (convoy-graduate.sh). So a convoy's
# rebuild is poured onto its rebuild child, an ordinary task that resumes the
# convoy's branch, lands on its target and blocks it. gc sling gives the child
# what it gives any bead it pours onto: a one-bead input convoy, a launch lock
# and a refusal of a second live run of the formula, both keyed by the child,
# and the child's gc.execution_routed_to stamp. The refinery's merge-push
# anchors the convoy once the child's work lands on the branch. A convoy has one
# live rebuild child, so a repool that finds it adopts it, and every retry
# slings that same bead (specs/tk-rl8gz4b.26/gas-city-search.md).
#
# The store has no transactions, so the repool is a sequence, each step proved
# before the next relies on it:
#   1. The bead is read, and one lifecycle transition to unanchored clears its
#      assignee, its claim route and the last pour's gc.execution_routed_to. A
#      bead that is not a convoy is the bead poured, and the same write records
#      the rejection_reason and carries a live pr_url over as existing_pr, which
#      the rework reuses. It lands before the pour, because load-context reads a
#      bead that still carries a merge_result, or an open bead assigned to anyone
#      else, as finished work and holds it, and the rebuild resumes the branch by
#      the reason it reads. It also lands before the pool route is proved: the
#      bead is out of the refinery's queue either way, and whatever later
#      finishes the repool finds the reason on the work bead, or for a convoy in
#      the visit that stops the repool short.
#   2. The pool route is proved (pool-route.sh) and must be rig-qualified. A
#      polecat pool is rig-scoped, so its pour stamps the rig-qualified
#      identity, and a bare name, which pool-route.sh returns unverified when
#      GC_RIG is unset and the live agent set cannot be read, never reads back.
#   3. For a convoy, its rebuild child is found among its live children: a
#      task_kind=rework child on the convoy's branch that carries no review or
#      ruling source key, which only rework-child.sh's children carry. One
#      already dispatched is reported and left alone, and one armed is left to
#      the deferred dispatch that pours it. With none, the child is filed
#      whole: its work order (task_kind, anchor_bead, branch, target,
#      rejection_reason, merge_strategy=mr, and existing_pr from a live pr_url)
#      and the PR-finishing shift ride the create, with its blocks edge and its
#      anchor edge onto the convoy. The child is then settled at its priority,
#      because the pour copies the priority it finds.
#   4. `gc sling <route> <bead> --on mol-polecat-work` for the bead poured,
#      proved by gc.execution_routed_to reading back on it as the route. Step 1
#      cleared it on the work bead, and a rebuild child is poured only while it
#      carries none, so only this pour can have written it.
# A pour that does not read back may still have started, so the writer never
# stamps a bare route: a partial pour plus a pool claim double-dispatches the
# work. When gc sling itself failed, the writer arms a deferred dispatch, whose
# reconcile pass retries the pour and files a visit once the retries reach their
# cap. When gc sling exited 0, the pour launched and only its stamp, or the read
# of it, is missing. That reconcile keys its retry on its own marker and on
# merge_result, never on gc.execution_routed_to, so a retry would pour the work
# a second time. That stop files a visit instead, like every other way the
# repool stops short, and each visit names what finishes the repool.
# Exit: 0 the pour is proved · 1 usage, nothing done · 2 the repool stopped
#   short, and an armed dispatch or a visit carries the bead · 3 the repool
#   stopped short and nothing could be recorded
set -uo pipefail

SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || { echo "rejection-repool: cannot source bd-lib.sh beside this script" >&2; exit 3; }
LIFECYCLE="$SCRIPTS_DIR/lifecycle.sh"
POOL_ROUTE="$SCRIPTS_DIR/pool-route.sh"
DEFERRED="$SCRIPTS_DIR/deferred-dispatch.sh"
ESCALATE="$SCRIPTS_DIR/escalate.sh"
QUEUE_PRIORITY="${GC_QUEUE_PRIORITY_TOOL:-$SCRIPTS_DIR/queue-priority.sh}"
WORK_FORMULA="mol-polecat-work"
ESCALATE_KEY="rejection-repool-failed"
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

warn()  { echo "rejection-repool: $*" >&2; }
usage() { warn "$1"; exit 1; }

WORK=""; REASON=""; POOL_NAME="gc-toolkit.polecat"
need() { [ "$2" -gt 1 ] || usage "$1 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --reason)  need "$1" $#; REASON="$2"; shift ;;
    --pool)    need "$1" $#; POOL_NAME="$2"; shift ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        usage "unknown argument '$1'" ;;
    *)         [ -z "$WORK" ] || usage "one work bead per call, not '$WORK' and '$1'"; WORK="$1" ;;
  esac
  shift
done
[ -n "$WORK" ]      || usage "the work bead id is required"
[ -n "$REASON" ]    || usage "--reason is required: the rejection_reason the rebuild starts from"
[ -n "$POOL_NAME" ] || usage "--pool needs a pool name"
command -v jq >/dev/null 2>&1 || { warn "jq is required; $WORK not repooled"; exit 3; }

REASON_HEAD=$(printf '%s' "$REASON" | head -n 1 | cut -c1-200)

# stop_short <why> <what finishes it> — the visit that carries a repool this run
# could not finish. The bead is out of the refinery's queue, so a run that ends
# without one leaves nothing that dispatches it or asks a person to.
stop_short() {
  if "$ESCALATE" --subject "$WORK" --key "$ESCALATE_KEY" \
       --message "A rejected handoff may never be rebuilt: the refinery sent it back to the polecats, but $1. To finish the hand-back, $2. (Work bead $WORK; rejection reason: $REASON_HEAD)" >&2; then
    warn "$WORK not repooled: $1; filed a visit ($ESCALATE_KEY) to finish it"
    exit 2
  fi
  warn "$WORK not repooled: $1, and the visit did not land either, so NOTHING dispatches $WORK. To finish it by hand, $2."
  exit 3
}

ROW=$(bd_json show "$WORK")
printf '%s' "$ROW" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
  || stop_short "it could not be read (gc bd show returned no bead)" \
       "re-run assets/scripts/rejection-repool.sh on it with the rejection reason this visit names once its store answers"
printf '%s\n' "$ROW"
PR_URL=$(row_meta "$ROW" pr_url)
IS_CONVOY=""
[ "$(printf '%s' "$ROW" | jq -r '.[0].issue_type // empty' 2>/dev/null)" = convoy ] && IS_CONVOY=1
# What a person runs to dispatch the rebuild to <pool> by hand: the work bead's
# sling, or for a convoy a re-run of this script, which pours its rebuild child.
by_hand() { # <pool>
  if [ -n "$IS_CONVOY" ]; then
    printf 'assets/scripts/rejection-repool.sh %s --pool %s --reason "<the rejection reason this visit names>"' "$WORK" "${1#*/}"
  else
    printf 'gc sling %s %s --on %s' "$1" "$WORK" "$WORK_FORMULA"
  fi
}
SETS=()
if [ -z "$IS_CONVOY" ]; then
  SETS=(--set "rejection_reason=$REASON")
  [ -n "$PR_URL" ] && SETS+=(--set "existing_pr=$PR_URL")
fi
# The route clear is explicit because unanchored is not a detached state, and
# lifecycle.sh clears a route unasked only on entry to one. reopen-source keeps
# the route the bead carried, or writes its gc.run_target over it. A pool route
# left there lets the pool claim the bead beside the pour, and
# deferred-dispatch.sh refuses to arm a bead that carries any route.
"$LIFECYCLE" transition "$WORK" --to unanchored --assignee "" --route "" \
  --unset gc.execution_routed_to ${SETS[@]+"${SETS[@]}"} >&2
LC_RC=$?
[ "$LC_RC" = 0 ] \
  || stop_short "its lifecycle transition did not land or did not verify (lifecycle.sh exit $LC_RC)" \
       "read the bead, then re-run assets/scripts/rejection-repool.sh on it with the rejection reason this visit names"

ROUTE=$("$POOL_ROUTE" "$POOL_NAME") \
  || stop_short "no live pool claims '$POOL_NAME'" \
       "dispatch the rebuild to a polecat pool that does: $(by_hand '<pool>')"
case "$ROUTE" in
  */*) ;;
  *) stop_short "the only route pool-route.sh could name is the bare '$ROUTE', which addresses no rig's pool, so no pour to it could be proved" \
       "dispatch the rebuild to the rig-qualified pool: $(by_hand "<rig>/$POOL_NAME")" ;;
esac

POUR="$WORK"
if [ -n "$IS_CONVOY" ]; then
  RERUN="re-run assets/scripts/rejection-repool.sh on it with the rejection reason this visit names"
  BRANCH=$(row_meta "$ROW" branch)
  TARGET=$(row_meta "$ROW" target)
  [ -n "$BRANCH" ] && [ -n "$TARGET" ] \
    || stop_short "it is a convoy, whose rebuild child resumes its branch and lands on its target, and it names no branch or no target" \
         "record both on it, then $RERUN"
  KIDS=$(bd_list --metadata-field "anchor_bead=$WORK" --status="$LIVE_STATUSES") \
    || stop_short "its live children could not be read, so a rebuild child it already has cannot be told from none" \
         "$RERUN once its store answers"
  POUR=$(printf '%s' "$KIDS" | jq -r --arg a "$WORK" --arg b "$BRANCH" '
    [ .[]? | (.metadata // {}) as $m
      | select((($m.task_kind // "") | tostring) == "rework"
               and (($m.anchor_bead // "") | tostring) == $a
               and (($m.branch // "") | tostring) == $b
               and (($m.source_review_bead // "") | tostring) == ""
               and (($m.source_ruling_bead // "") | tostring) == "") ]
    | sort_by(.created_at // .id)
    | ((map(select(((.metadata["gc.execution_routed_to"] // "") | tostring) != "")) | .[0]) // .[0])
    | .id // empty' 2>/dev/null)
  ORDER=$(jq -nc --arg a "$WORK" --arg b "$BRANCH" --arg t "$TARGET" --arg r "$REASON" --arg pr "$PR_URL" \
    '{task_kind: "rework", anchor_bead: $a, branch: $b, target: $t, rejection_reason: $r, merge_strategy: "mr"}
     + (if $pr == "" then {} else {existing_pr: $pr} end)')
  if [ -z "$POUR" ]; then
    # The child is found by its role marker on the branch (task_kind,
    # anchor_bead, branch), so a create that cannot read back carrying those
    # keys files nothing. Its blocks edge and its anchor edge ride the create.
    POUR=$(bd_create --select task_kind,anchor_bead,branch --child-of "$WORK" "$(pr_finishing_birth "$ORDER")" \
      "Rebuild $BRANCH after the refinery's rejection" -t task --deps "blocks:$WORK")
    CREATE_RC=$?
    [ -n "$POUR" ] \
      || stop_short "its rebuild child could not be filed (bd_create exit $CREATE_RC)" "$RERUN"
    [ "$CREATE_RC" = 0 ] \
      || stop_short "its rebuild child $POUR was filed but its work order did not read back whole" \
           "$RERUN, which adopts $POUR and completes its work order"
    warn "$WORK is a convoy, so its rebuild is poured onto the rebuild child $POUR filed for it"
  else
    ADOPT_ROW=$(bd_json show "$POUR")
    ADOPT_ROUTE=$(row_meta "$ADOPT_ROW" gc.execution_routed_to)
    if [ -n "$ADOPT_ROUTE" ]; then
      warn "repooled $WORK: its rebuild child $POUR is already dispatched to $ADOPT_ROUTE, and a second pour would double its rebuild"
      exit 0
    fi
    # The reconcile retires an arm only by its own sling, so a child poured
    # here while armed would be poured again once its arm fires.
    ADOPT_ARM=$(row_meta "$ADOPT_ROW" gc.dispatch_when_ready)
    if [ -n "$ADOPT_ARM" ]; then
      warn "$WORK: its rebuild child $POUR is armed for $ADOPT_ARM, and the deferred-dispatch reconcile pass pours it; nothing poured here"
      exit 2
    fi
    bd_meta_ensure "$POUR" "$ORDER" >/dev/null \
      || stop_short "its rebuild child $POUR did not read back carrying its whole work order" \
           "$RERUN, which adopts $POUR and completes its work order"
    warn "$WORK is a convoy, so its rebuild is poured onto its rebuild child $POUR, which a prior repool filed"
  fi
  "$QUEUE_PRIORITY" settle "$POUR" >&2 \
    || stop_short "its rebuild child $POUR did not settle at its priority, and a pour copies the priority it finds" \
         "$RERUN, which adopts $POUR"
fi

# CHILD names a convoy's rebuild child, and ON is what a message says the pour
# went onto.
CHILD=""; ON="it"
[ "$POUR" = "$WORK" ] || { CHILD="$POUR"; ON="its rebuild child $POUR"; }
gc sling ${GC_RIG:+--rig "$GC_RIG"} "$ROUTE" "$POUR" --on "$WORK_FORMULA" >&2
SLING_RC=$?
if [ "$(row_meta "$(bd_json show "$POUR")" gc.execution_routed_to)" = "$ROUTE" ]; then
  warn "repooled $WORK: $WORK_FORMULA poured${CHILD:+ onto its rebuild child $CHILD} for $ROUTE"
  exit 0
fi
[ "$SLING_RC" != 0 ] \
  || stop_short "gc.execution_routed_to did not read back as $ROUTE${CHILD:+ on its rebuild child $CHILD} after gc sling exited 0, so the pour may be running, and no retry was armed because one could pour the work twice" \
       "check that no $WORK_FORMULA workflow is live on $ON, then dispatch the rebuild: gc sling $ROUTE $POUR --on $WORK_FORMULA"
if "$DEFERRED" arm "$POUR" --target "$ROUTE" --sling-arg --on --sling-arg "$WORK_FORMULA" \
     --reason "refinery rejection: the rebuild's gc sling failed (exit $SLING_RC)" >&2; then
  warn "$WORK: gc sling${CHILD:+ of its rebuild child $CHILD} exited $SLING_RC and its $WORK_FORMULA pour did not read back; armed a deferred dispatch${CHILD:+ on $CHILD}, whose reconcile pass retries the pour"
  exit 2
fi
stop_short "its gc sling${CHILD:+ of its rebuild child $CHILD} failed (exit $SLING_RC) and the deferred dispatch did not arm" \
  "check that no $WORK_FORMULA workflow is live on $ON, then dispatch the rebuild: gc sling $ROUTE $POUR --on $WORK_FORMULA"
