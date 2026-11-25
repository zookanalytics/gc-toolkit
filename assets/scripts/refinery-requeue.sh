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
# A bead that owns an open PR on the record (merge_result=
# pull_request_head_changed) keeps its PR, and its branch has one writer, the
# review run (specs/tk-1tfzr71.108/design.md, section 1), so the work goes to the
# run as an ask (`gctk review ask`) with the reason, in place of a rework child.
# The landing order pours a run only for a record pending at the PR's head,
# never for one open at a changed head, as this record is, so once the ask
# stands the PR is recorded pending at the head the prep read (`gctk pr
# record`), which the run then judges. The ask goes first because its blocks
# edge onto the bead is a wait the evaluator reads: no pass of the landing order
# finds that head pending, with the passed result an earlier run may have left
# there, and nothing asked of it, whenever this run stops. The ask's reason
# opens on a line naming the head, and a requeue of a head whose open ask opens
# on that line files no second ask, as when an earlier run stopped between the
# two writes. An ask that does not land writes nothing else, and the bead stays
# with the refinery for its next patrol, whose find-work takes a bead only asks
# hold. A record that does not land after the ask did leaves the ask holding the
# merge, and files a human gate keyed refinery-requeue-failed on the bead, which
# names the record to write by hand, because a bead an ask blocks is no ready
# work that brings the refinery back to it.
#
# One worker per branch: when an open rework child of such a bead is already on
# its branch, running or parked, one filed before the PR's branch had a review
# run to write it, the reason goes to that child's notes and nothing else is
# filed.
#
# Any other bead, a rework child among them, goes back itself. One write,
# guarded on the assignee and status it read, reopens it unassigned with the
# rejection_reason and clears its claim route, its last pour's stamp and the
# session that last held it, so a run of the landing order that read it before
# writes nothing (bd's guard). The same write clears the marker a dead
# publication left (pr_reconcile_pending), since the landing order works a
# marked bead assigned to nobody as a PR that waits, and the merge_result and
# blocked_reason that a park, or a record the landing order found half
# written, left on it, because the polecat's work gate refuses an open bead
# that carries a merge_result as finished work. Its branch, target and
# existing_pr stay, so the rework reuses the PR it may have. A live workflow
# left on it is closed (gc workflow delete-source), and it is slung.
#
# A sling that fails is armed instead (gctk bead arm), and the deferred-dispatch
# order pours the bead on its next pass once nothing holds it. An arm that fails
# files a human gate keyed refinery-requeue-failed, which asks a person to pour
# the work by hand.
#
# Exit: 0 sent back or armed to go back, sent to the review run as an ask, or
#         the reason reached the child already on the branch
#       1 the work did not go back; the output says why. The bead stays with
#         the refinery: its next patrol retries the requeue, and a
#         refinery-requeue-failed gate the run filed waits for a person
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
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin

FORMULA="mol-polecat-work"
LIVE="open,in_progress,blocked,deferred,hooked,pinned"

usage() { echo "usage: $PROG --bead <id> --reason <text> [--pool <name>]" >&2; exit 2; }
BEAD=""; REASON=""; POOL="polecat"
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
# said <refusal> <writer>: a write's refusal on one line, for a gate's message.
said() { printf '%s' "${1:-$2 gave no reason}" | tr -s '[:space:]' ' ' | sed 's/ $//'; }

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

# arm <bead> <why>: arm the dispatch this run could not make (gctk bead arm), so
# the deferred-dispatch order's next pass pours mol-polecat-work on <bead> for
# the pool once nothing holds it. An arm that fails asks a person, behind a
# refinery-requeue-failed gate on <bead>, to pour it by hand.
arm() {
  local hand="gc sling $ROUTE $1 --on $FORMULA"
  if "$GCTK" bead arm "$1" --target "$ROUTE" --on "$FORMULA" --reason "refinery requeue: $2" >&2; then
    echo "$PROG: $2; armed a deferred dispatch, which the deferred-dispatch order pours on its next pass" >&2
    return 0
  fi
  "$HERE/human-gate.sh" --subject "$1" --key refinery-requeue-failed --message "The refinery sent $1 back to the pool ($REASON), but $2 and no deferred dispatch could be armed, so no polecat is building it. Pour it by hand: $hand, then clear this gate." >/dev/null \
    || echo "$PROG: no refinery-requeue-failed gate landed on $1 either; pour it by hand: $hand" >&2
  return 1
}
# sling <bead>: pour mol-polecat-work on <bead> for the pool. A sling that fails
# is armed.
sling() {
  local rc
  gc sling ${GC_RIG:+--rig "$GC_RIG"} "$ROUTE" "$1" --on "$FORMULA" </dev/null >&2
  rc=$?
  [ "$rc" != 0 ] || return 0
  arm "$1" "gc sling of $1 exited $rc"
}

if [ "$(bead_meta merge_result)" = pull_request_head_changed ]; then
  PR=$(bead_meta existing_pr)
  [ -n "$PR" ] || PR=$(bead_meta pr_url)
  KIDS=$(bd_json list --metadata-field "anchor_bead=$BEAD" --status="$LIVE" --limit=0) \
    && printf '%s' "$KIDS" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || stop "the open beads that name $BEAD as their anchor did not read"
  CHILD=$(printf '%s' "$KIDS" | jq -r --arg b "$BRANCH" '[ .[] | select((.metadata.task_kind // "") == "rework" and (.metadata.branch // "") == $b) ] | sort_by(.created_at // .id) | .[0].id // empty')
  if [ -n "$CHILD" ]; then
    gc bd update "$CHILD" --append-notes "Refinery, on $BEAD's branch $BRANCH: $REASON. This child is the rework on the branch, so nothing else is filed for it." </dev/null >/dev/null \
      || stop "the reason did not reach $CHILD, the rework child already on $BRANCH"
    echo "$PROG: $CHILD is the rework on $BEAD's branch $BRANCH, so the reason went to its notes: $REASON"
    exit 0
  fi
  [ -n "$PR" ] || stop "$BEAD owns an open PR on the record but names none (existing_pr and pr_url are empty)"
  # The ask goes first and the record second (see the header).
  LINE="The refinery sent $PREP_READ back:"
  ON=$(bd_json list --metadata-field "branch=$BRANCH" --status=open --limit=0) \
    && printf '%s' "$ON" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || stop "the open beads on $BRANCH did not read, so whether an ask for $PREP_READ already stands is unknown"
  ASK=$(printf '%s' "$ON" | jq -r --arg b "$BRANCH" --arg l "$LINE" "$REFINERY_ASK_JQ"'[ .[] | select(refinery_ask($b))
    | select(((.description // "") | split("\n") | .[0]) == $l) ] | sort_by(.created_at // .id) | .[0].id // empty')
  if [ -n "$ASK" ]; then
    echo "$PROG: ask $ASK, which an earlier requeue of $PREP_READ filed, is open on $BRANCH, so no second is filed" >&2
  else
    ARC=0
    AOUT=$("$GCTK" review ask "$BEAD" --reason "$LINE
$REASON" </dev/null 2>&1) || ARC=$?
    [ "$ARC" = 0 ] || stop "the ask that sends $BRANCH to $BEAD's review run did not land ($(said "$AOUT" "gctk review ask")), so $PR is not recorded pending at $PREP_READ"
    ASK=$(printf '%s\n' "$AOUT" | tail -n 1 | cut -d' ' -f1)
    [ -n "$ASK" ] || stop "gctk review ask named no ask on $BEAD, so $PR is not recorded pending at $PREP_READ"
  fi
  RRC=0
  ROUT=$(GC_RIG_ROOT="$HOME_DIR" "$GCTK" pr record "$BEAD" --pr "$PR" --head "$PREP_READ" --target "$TARGET" \
    --refinery "$GC_AGENT" </dev/null 2>&1) || RRC=$?
  case "$RRC" in
    0) ;;
    3) echo "$PROG: $BEAD changed after it was read, so it was left as it is, and ask $ASK holds its merge: $(said "$ROUT" "gctk pr record")" >&2
       exit 3 ;;
    *) HAND="GC_RIG_ROOT=$(printf '%q' "$HOME_DIR") $GCTK pr record $BEAD --pr $PR --head $PREP_READ --target $TARGET --refinery $GC_AGENT"
       "$HERE/human-gate.sh" --subject "$BEAD" --key refinery-requeue-failed --message "The refinery filed ask $ASK to send $BEAD's branch $BRANCH back to its review run ($REASON), but recording $PR as pending at $PREP_READ did not land ($(said "$ROUT" "gctk pr record")). The ask holds the merge, no run takes it until the record names that head, and a bead an ask blocks is no ready work that brings the refinery back. Record it by hand: $HAND, then clear this gate." >/dev/null \
         || echo "$PROG: no refinery-requeue-failed gate landed on $BEAD either; record it by hand: $HAND" >&2
       stop "ask $ASK holds $BEAD's merge, and the record of $PR as pending at $PREP_READ did not land ($(said "$ROUT" "gctk pr record")), so a refinery-requeue-failed gate asks a person to write it" ;;
  esac
  echo "$PROG: $BEAD keeps its PR $PR, recorded pending at $PREP_READ, and the review run the landing order pours takes its ask $ASK: $REASON"
  exit 0
fi

case "$STATUS" in open|in_progress) ;; *) stop "$BEAD is $STATUS, not open or in progress" ;; esac
# bd exits 13 when a guard no longer holds, having written nothing; any other
# failure is the store's, which says nothing about where the bead went.
RC=0
OUT=$(gc bd update "$BEAD" --if-assignee="$GC_AGENT" --if-status="$STATUS" --status=open --assignee="" \
  --set-metadata "rejection_reason=$REASON" --unset-metadata merge_result --unset-metadata blocked_reason \
  --unset-metadata pr_reconcile_pending --unset-metadata gc.routed_to --unset-metadata gc.execution_routed_to \
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
