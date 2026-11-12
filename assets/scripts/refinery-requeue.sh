#!/usr/bin/env bash
# refinery-requeue.sh — send work the refinery will not land back to the
# polecat pool, through `gc sling` on mol-polecat-work, with the reason the
# resumed worker starts from.
#
#   refinery-requeue.sh --bead <id> --reason <text> [--pool <name>]
#
# The bead is the one this iteration prepared: it must be assigned to this
# refinery ($GC_AGENT), and the refinery's tree for it must hold its branch
# (refinery-lib.sh), so a bead named from a stale variable gets no write. The
# work goes back one of two ways.
#
# A bead that records an open PR (merge_result=pull_request_head_changed), or a
# convoy, which gc sling would take as its run's input convoy rather than its
# work, keeps what it carries and comes back as a rework child: a task on the
# same branch, with task_kind=rework, anchor_bead, branch, target,
# rejection_reason, merge_strategy=mr and the PR as existing_pr. The child is
# filed whole: its work order, its edge joining it to the bead and its blocks
# edge onto the bead are all in the create, so no child exists without them. A
# create whose reply carries no id may still have landed, so the bead's
# children are read again for it. The child is then settled at its priority,
# because a pour copies the priority it finds, and slung. The bead stays open
# and assigned to the refinery, so the child's hand-back records the PR on it.
#
# A child that does not settle is not slung, and the run stops with the child
# unsent (refinery-lib.sh): it holds the bead, and no one works it. The
# refinery's next patrol sends it on. find-work counts an unsent child as no
# wait and no writer, so it takes the bead, and the bead's prep runs this
# requeue again, which finds the child on the branch.
#
# One worker per branch: when an open rework child of the bead is already on
# the branch, running or parked, the reason goes to that child's notes and
# nothing else is filed. An unsent child among them is sent on: its blocks edge
# onto the bead is written when it lacks one, as a child filed before the edge
# rode the create can, and it is settled, then slung. When that fails too, the
# run files a human gate keyed refinery-requeue-failed on the child, so the
# patrol stops taking the bead, and clearing the gate lets the next patrol send
# the child on.
#
# Any other bead, a rework child among them, goes back itself. One write,
# guarded on the assignee and status it read, reopens it unassigned with the
# rejection_reason and clears its claim route, its last pour's stamp and the
# session that last held it, so a run of the landing order that read it before writes nothing (bd's guard), and
# the next run clears a marker a dead publication left, as after a release. Its
# branch, target and existing_pr stay. A live workflow left on it is closed
# (gc workflow delete-source), and it is slung.
#
# A sling that fails arms a deferred dispatch, whose reconcile pass retries the
# pour. An arm that fails too files a human gate keyed refinery-requeue-failed.
#
# Exit: 0 sent back, or the reason reached the child already on the branch
#       1 the work did not go back; the output says why. The bead stays with
#         the refinery, and its next patrol retries the requeue, or sends on
#         the unsent child this run filed
#       2 usage
#       3 the bead left the refinery or changed status before the write, so
#         nothing was written
set -uo pipefail

PROG="refinery-requeue"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }

FORMULA="mol-polecat-work"
LIVE="open,in_progress,blocked,deferred,hooked,pinned"

usage() { echo "usage: $PROG --bead <id> --reason <text> [--pool <name>]" >&2; exit 2; }
BEAD=""; REASON=""; POOL="gc-toolkit.polecat"
while [ $# -gt 0 ]; do
  case "$1" in
    --bead|--reason|--pool)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 needs a value" >&2; usage; }
      case "$1" in --bead) BEAD="$2" ;; --reason) REASON="$2" ;; *) POOL="$2" ;; esac
      shift 2 ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$BEAD" ] && [ -n "$(printf '%s' "$REASON" | tr -d '[:space:]')" ] || usage

stop() { echo "$PROG: $1; nothing went back to the pool, and $BEAD stays with the refinery" >&2; exit 1; }
# unsent <child> <why>: stop with the child this run filed left unsent, for the
# refinery's next patrol to send on.
unsent() {
  echo "$PROG: rework child $1 was filed for $BEAD, but $2, so it is not slung. It holds $BEAD unsent, and the refinery's next patrol sends it on: find-work takes $BEAD, and its prep runs this requeue again" >&2
  exit 1
}
# said <refusal> <writer>: a write's refusal on one line, for a gate's message.
said() { printf '%s' "${1:-$2 gave no reason}" | tr -s '[:space:]' ' ' | sed 's/ $//'; }
# ask <child> <why>: an unsent child that could not be sent on again waits for a
# person, behind a human gate on it. The gate holds the child, so the patrol
# stops taking the bead, and once it is cleared the next patrol sends it on.
ask() {
  "$HERE/human-gate.sh" --subject "$1" --key refinery-requeue-failed --message "The refinery sent $BEAD's branch $BRANCH back to the pool as rework child $1 ($REASON), but $2, so no polecat is building it. Fix that, then clear this gate, and the refinery's next patrol sends $1 on. To send it on yourself instead: $HERE/queue-priority.sh settle $1, then gc sling $ROUTE $1 --on $FORMULA, then clear this gate." >/dev/null \
    || echo "$PROG: no refinery-requeue-failed gate landed on $1 either, so the refinery's next patrol tries to send it on again" >&2
  stop "rework child $1 was never sent on, and $2"
}

HOME_DIR=$(refinery_home) || stop "the refinery's own worktree is unknown"
refinery_bead "$BEAD" || stop "$BEAD did not read"
[ -n "${GC_AGENT:-}" ] && [ "$(bead_field assignee)" = "$GC_AGENT" ] \
  || stop "$BEAD is assigned to $(bead_field assignee), not this refinery (${GC_AGENT:-GC_AGENT unset})"
BRANCH=$(bead_meta branch)
refinery_require "$HOME_DIR" "$BEAD" "$BRANCH" || stop "this iteration did not prepare $BEAD"
TARGET=$(bead_meta target)
[ -n "$TARGET" ] || TARGET=$(refinery_default_branch "$HOME_DIR") || TARGET=""
STATUS=$(bead_field status)
ROUTE=$("$HERE/pool-route.sh" "$POOL") || stop "the pool $POOL resolves to no route"

# sling <bead>: pour mol-polecat-work on <bead> for the pool. A sling that
# fails arms the reconcile pass's retry, and an arm that fails asks a person.
sling() {
  local rc
  gc sling ${GC_RIG:+--rig "$GC_RIG"} "$ROUTE" "$1" --on "$FORMULA" </dev/null >&2
  rc=$?
  [ "$rc" != 0 ] || return 0
  if "$HERE/deferred-dispatch.sh" arm "$1" --target "$ROUTE" --sling-arg --on --sling-arg "$FORMULA" \
       --reason "refinery requeue: gc sling of $1 exited $rc" >&2; then
    echo "$PROG: gc sling of $1 exited $rc; armed a deferred dispatch, whose reconcile pass retries the pour" >&2
    return 0
  fi
  "$HERE/human-gate.sh" --subject "$1" --key refinery-requeue-failed --message "The refinery sent $1 back to the pool ($REASON), but gc sling exited $rc and no deferred dispatch could be armed, so no polecat is building it. Pour it by hand: gc sling $ROUTE $1 --on $FORMULA, then clear this gate." >/dev/null \
    || echo "$PROG: no refinery-requeue-failed gate landed on $1 either; pour it by hand: gc sling $ROUTE $1 --on $FORMULA" >&2
  return 1
}

KIND=$(bead_field issue_type)
[ -n "$KIND" ] || KIND=$(bead_field type)
if [ "$(bead_meta merge_result)" = pull_request_head_changed ] || [ "$KIND" = convoy ]; then
  PR=$(bead_meta existing_pr)
  [ -n "$PR" ] || PR=$(bead_meta pr_url)
  # kids: the live beads that name the bead as their anchor, in KIDS.
  kids() {
    KIDS=$(bd_json list --metadata-field "anchor_bead=$BEAD" --status="$LIVE" --limit=0) \
      && printf '%s' "$KIDS" | jq -e 'type == "array"' >/dev/null 2>&1
  }
  kids || stop "the open beads that name $BEAD as their anchor did not read"
  CHILD=$(printf '%s' "$KIDS" | jq -r --arg b "$BRANCH" '[ .[] | select((.metadata.task_kind // "") == "rework" and (.metadata.branch // "") == $b) ] | sort_by(.created_at // .id) | .[0].id // empty')
  if [ -n "$CHILD" ]; then
    gc bd update "$CHILD" --append-notes "Refinery, on $BEAD's branch $BRANCH: $REASON. This child is the rework on the branch, so nothing else is filed for it." </dev/null >/dev/null \
      || stop "the reason did not reach $CHILD, the rework child already on $BRANCH"
    if printf '%s' "$KIDS" | jq -e --arg c "$CHILD" --arg a "$BEAD" --arg b "$BRANCH" "$REFINERY_UNSENT_JQ"'any(.[]; .id == $c and refinery_unsent($a; $b))' >/dev/null 2>&1; then
      # An unsent child is made whole before its sling: its blocks edge onto
      # the bead, which a child filed before the edge rode the create can lack,
      # and its priority. A failure here asks a person.
      # bd refuses a second edge on a pair, so an add it refuses is read again.
      # The refusal of each write is kept for the gate that asks a person.
      blocks_bead() { bd_json dep list "$BEAD" --direction=down -t blocks | jq -e --arg c "$1" 'type == "array" and any(.[]; .id == $c)' >/dev/null 2>&1; }
      if ! blocks_bead "$CHILD"; then
        ERR=$(gc bd dep "$CHILD" --blocks "$BEAD" </dev/null 2>&1 >/dev/null) || blocks_bead "$CHILD" \
          || ask "$CHILD" "its blocks edge onto $BEAD did not land ($(said "$ERR" bd)), and that edge is what holds $BEAD for its rework"
      fi
      { ERR=$(pr_finishing_settle "$CHILD" 2>&1 1>&3); } 3>&2 \
        || ask "$CHILD" "it did not settle at its priority ($(said "$ERR" queue-priority.sh)), and a pour copies the priority it finds"
      sling "$CHILD" || exit 1
      echo "$PROG: $CHILD, the rework child on $BRANCH, was filed and never sent on, so it was settled and slung to $ROUTE"
    fi
    echo "$PROG: $CHILD is the rework on $BEAD's branch $BRANCH, so the reason went to its notes: $REASON"
    exit 0
  fi
  ORDER=$(jq -nc --arg a "$BEAD" --arg b "$BRANCH" --arg t "$TARGET" --arg r "$REASON" --arg p "$PR" \
    '{task_kind: "rework", anchor_bead: $a, branch: $b, target: $t, rejection_reason: $r, merge_strategy: "mr"}
     + (if $p == "" then {} else {existing_pr: $p} end)')
  IDENTITY=$(pr_finishing_birth "$ORDER") || stop "the rework child's work order did not build"
  SHORT=$(printf '%s' "$REASON" | head -n 1 | cut -c1-80)
  CHILD=$(bd_create_child "$BEAD" "Rework $BRANCH for $BEAD: $SHORT" -t task --metadata "$IDENTITY" --deps "blocks:$BEAD" --json </dev/null 2>/dev/null \
    | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
  if [ -z "$CHILD" ]; then
    # A create whose reply was lost can still have landed whole, and no rework
    # child was on the branch before it, so an unsent one there now is its.
    kids || stop "the rework child's create returned no id, and the beads that name $BEAD as their anchor did not read again. A child it did file is unsent, and the refinery's next patrol sends it on"
    CHILD=$(printf '%s' "$KIDS" | jq -r --arg a "$BEAD" --arg b "$BRANCH" "$REFINERY_UNSENT_JQ"'[ .[] | select(refinery_unsent($a; $b)) ] | sort_by(.created_at // .id) | .[0].id // empty')
    [ -n "$CHILD" ] || stop "the rework child's create returned no id, and no unsent rework child of $BEAD is on $BRANCH, so none was filed"
    echo "$PROG: the rework child's create returned no id; $CHILD is the unsent rework child it filed on $BRANCH" >&2
  fi
  pr_finishing_settle "$CHILD" >&2 || unsent "$CHILD" "it did not settle at its priority, and a pour copies the priority it finds"
  sling "$CHILD" || exit 1
  echo "$PROG: $BEAD keeps its PR${PR:+ $PR}, and its rework child $CHILD went to $ROUTE: $REASON"
  exit 0
fi

case "$STATUS" in open|in_progress) ;; *) stop "$BEAD is $STATUS, not open or in progress" ;; esac
# bd exits 13 when a guard no longer holds, having written nothing; any other
# failure is the store's, which says nothing about where the bead went.
RC=0
OUT=$(gc bd update "$BEAD" --if-assignee="$GC_AGENT" --if-status="$STATUS" --status=open --assignee="" \
  --set-metadata "rejection_reason=$REASON" --unset-metadata gc.routed_to --unset-metadata gc.execution_routed_to \
  --unset-metadata gc.session_id --unset-metadata gc.session_name </dev/null 2>&1) || RC=$?
case "$RC" in
  0) ;;
  13) echo "$PROG: $BEAD changed after it was read (no longer $STATUS and assigned to $GC_AGENT), so it was left as it is: $(printf '%s' "$OUT" | tr -s '[:space:]' ' ')" >&2
      exit 3 ;;
  *) stop "the write that sends $BEAD back exited $RC, a failure of the store rather than a change to $BEAD: $(printf '%s' "$OUT" | tr -s '[:space:]' ' ')" ;;
esac
gc workflow delete-source "$BEAD" --apply </dev/null >&2 \
  || echo "$PROG: gc workflow delete-source $BEAD did not finish; a workflow still live on it makes the sling below refuse" >&2
sling "$BEAD" || exit 1
echo "$PROG: $BEAD went back to $ROUTE, unassigned: $REASON"
exit 0
