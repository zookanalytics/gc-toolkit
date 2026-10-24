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
# The store has no transactions, so the repool is a sequence, each step proved
# before the next relies on it:
#   1. The bead is read, and one lifecycle transition to unanchored clears its
#      assignee, its claim route and the last pour's gc.execution_routed_to,
#      records the rejection_reason, and carries a live pr_url over as
#      existing_pr so the rework reuses the PR. It lands before the pour,
#      because load-context reads a bead that still carries a merge_result, or
#      an open bead assigned to anyone else, as finished work and holds it, and
#      the rebuild resumes the branch by the reason it reads. It also lands
#      before the pool route is proved: the bead is out of the refinery's queue
#      either way, and whatever later finishes the repool finds the reason on it.
#   2. The pool route is proved (pool-route.sh) and must be rig-qualified. A
#      polecat pool is rig-scoped, so its pour stamps the rig-qualified
#      identity, and a bare name, which pool-route.sh returns unverified when
#      GC_RIG is unset and the live agent set cannot be read, never reads back.
#   3. The bead is slung to the route on mol-polecat-work through
#      work-sling.sh, which gives a convoy that is its own work bead, such as a
#      graduation's anchor, an input convoy that tracks it alone, so the run
#      works on the bead whatever its type. The pour is proved by
#      gc.execution_routed_to reading back as the route. Step 1 cleared it, so
#      only a pour made since can have written it: this one, or one that
#      work-sling.sh let another call make first while this call waited on the
#      bead's lock. work-sling.sh then refuses this call (exit 3), and the
#      stamp that pour left proves the rebuild all the same.
# A pour that does not read back may still have started, so the writer never
# stamps a bare route: a partial pour plus a pool claim double-dispatches the
# work. When the sling failed, the writer arms a deferred dispatch, whose
# reconcile pass retries the pour and files a visit once the retries reach their
# cap. When the sling exited 0, the pour launched and only its stamp, or the read
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
WORK_SLING="$SCRIPTS_DIR/work-sling.sh"
ESCALATE="$SCRIPTS_DIR/escalate.sh"
WORK_FORMULA="mol-polecat-work"
ESCALATE_KEY="rejection-repool-failed"

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
SETS=(--set "rejection_reason=$REASON")
[ -n "$PR_URL" ] && SETS+=(--set "existing_pr=$PR_URL")
# The route clear is explicit because unanchored is not a detached state, and
# lifecycle.sh clears a route unasked only on entry to one. reopen-source keeps
# the route the bead carried, or writes its gc.run_target over it. A pool route
# left there lets the pool claim the bead beside the pour, and
# deferred-dispatch.sh refuses to arm a bead that carries any route.
"$LIFECYCLE" transition "$WORK" --to unanchored --assignee "" --route "" \
  --unset gc.execution_routed_to "${SETS[@]}" >&2
LC_RC=$?
[ "$LC_RC" = 0 ] \
  || stop_short "its lifecycle transition did not land or did not verify (lifecycle.sh exit $LC_RC)" \
       "read the bead, then re-run assets/scripts/rejection-repool.sh on it with the rejection reason this visit names"

ROUTE=$("$POOL_ROUTE" "$POOL_NAME") \
  || stop_short "no live pool claims '$POOL_NAME'" \
       "dispatch the rebuild to a polecat pool that does: assets/scripts/work-sling.sh $WORK --target <pool> -- --on $WORK_FORMULA"
case "$ROUTE" in
  */*) ;;
  *) stop_short "the only route pool-route.sh could name is the bare '$ROUTE', which addresses no rig's pool, so no pour to it could be proved" \
       "dispatch the rebuild to the rig-qualified pool: assets/scripts/work-sling.sh $WORK --target <rig>/$POOL_NAME -- --on $WORK_FORMULA" ;;
esac

"$WORK_SLING" "$WORK" --target "$ROUTE" -- --on "$WORK_FORMULA" >&2
SLING_RC=$?
if [ "$(row_meta "$(bd_json show "$WORK")" gc.execution_routed_to)" = "$ROUTE" ]; then
  warn "repooled $WORK: $WORK_FORMULA poured for $ROUTE"
  exit 0
fi
[ "$SLING_RC" != 0 ] \
  || stop_short "gc.execution_routed_to did not read back as $ROUTE after gc sling exited 0, so the pour may be running, and no retry was armed because one could pour the work twice" \
       "check that no $WORK_FORMULA workflow is live on it, then dispatch the rebuild: assets/scripts/work-sling.sh $WORK --target $ROUTE -- --on $WORK_FORMULA"
if "$DEFERRED" arm "$WORK" --target "$ROUTE" --sling-arg --on --sling-arg "$WORK_FORMULA" \
     --reason "refinery rejection: the rebuild's sling failed (exit $SLING_RC)" >&2; then
  warn "$WORK: its sling exited $SLING_RC and its $WORK_FORMULA pour did not read back; armed a deferred dispatch, whose reconcile pass retries the pour"
  exit 2
fi
stop_short "its sling failed (exit $SLING_RC) and the deferred dispatch did not arm" \
  "check that no $WORK_FORMULA workflow is live on it, then dispatch the rebuild: assets/scripts/work-sling.sh $WORK --target $ROUTE -- --on $WORK_FORMULA"
