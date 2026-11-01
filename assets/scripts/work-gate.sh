#!/usr/bin/env bash
# work-gate — whether this run of mol-polecat-work may build its work bead, and
# with that answer, taking the work.
#
#   work-gate.sh --convoy <id> [--step <ref>] [--formula <f>]
#   work-gate.sh --bead <id>   [--step <ref>] [--formula <f>]
#
# Two dispatch surfaces can reach one work bead, this workflow and a direct pool
# route left on the bead. When both fire, two workers set up the same branch and
# one silently destroys the other's commits. So before the workspace is touched,
# the bead must be readable, not parked, not in flight under another live owner
# or in another live session's tree, not waiting on a blocker, and not finished.
#
# Every refusal ends the run through decline.sh, and they split by whether a
# person has a decision to make:
#   * nobody decides when the bead is finished (closed, handed off, or carrying
#     a merge_result) or another live run is building this same bead;
#   * nobody decides when the bead waits on open blockers, or a sibling on its
#     branch holds the tree. A sibling is different work that the other run is
#     not building, so this run must not simply end: the bead waits on it through
#     a blocks edge and an armed re-sling, as it waits on any blocker;
#   * a person decides when the bead is parked (nothing re-slings it when it is
#     released) or a tree no check could rule out. Clearing the second gate
#     re-slings the work;
#   * a bead the store does not have cannot be blocked, so it files a patrol
#     finding that names it.
# A store that does not answer is none of these: the step goes back to the pool.
#
# Owner liveness gates only the in-flight case. An idle pool worker between
# claims looks identical to an abandoned one, so an in_progress bead is a conflict
# only while `gc session list --state all` lists its owner, and a list that cannot
# be read proves nobody gone.
#
# This workflow never claims its work bead, so the assignee cannot show a run in
# flight. Core's work-holder.sh, reached through `gc core scripts-dir`, reads the
# record each run keeps (metadata.work_holder beside metadata.work_dir), and its
# --claim takes the work in the step that judged it free: one compare-and-set, so
# of two dispatches that read the work free, the second finds the first one's
# record. Blockers are read first, because a bead that must wait has no business
# taking the work or meeting a sibling's tree.
#
# exit: 0 this run builds the bead · 1 it does not, and decline.sh or the step's
# retry has what follows · 2 usage
set -uo pipefail

PROG="work-gate"

usage() {
  cat >&2 <<'USAGE'
usage: work-gate.sh --convoy <id> [--step <ref>] [--formula <f>]
       work-gate.sh --bead <id>   [--step <ref>] [--formula <f>]

  --convoy   the run's input convoy; its one tracked bead is the work
  --bead     the work bead, for a claimant with no poured workflow
  --step     the step this session holds; default mol-polecat-work.load-context
  --formula  the formula a re-sling pours; default mol-polecat-work

exit: 0 this run builds the bead · 1 it does not · 2 usage
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
}

CONVOY=""; BEAD=""; STEP="mol-polecat-work.load-context"; FORMULA="mol-polecat-work"
while [ $# -gt 0 ]; do
  case "$1" in
    --convoy)  require_value "$@"; CONVOY="$2";  shift 2 ;;
    --bead)    require_value "$@"; BEAD="$2";    shift 2 ;;
    --step)    require_value "$@"; STEP="$2";    shift 2 ;;
    --formula) require_value "$@"; FORMULA="$2"; shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *)         echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if { [ -n "$CONVOY" ] && [ -n "$BEAD" ]; } || { [ -z "$CONVOY" ] && [ -z "$BEAD" ]; }; then
  echo "$PROG: name the work with --convoy or --bead, not both" >&2
  usage
  exit 2
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=work-lib.sh
. "$SCRIPT_DIR/work-lib.sh"

DISPATCHED_BY="${CONVOY:+Convoy $CONVOY}"
DISPATCHED_BY="${DISPATCHED_BY:-A direct route}"
SELF="${GC_SESSION_NAME:-${GC_SESSION_ID:-this session}}"

note() { # <label> <what was found>
  gc bd update "$WORK_ID" --append-notes "$1: $SELF found $WORK_ID $2." </dev/null >/dev/null 2>&1 \
    || echo "$PROG: The refusal note did not land on $WORK_ID; the cancel reason on this step still records it." >&2
}

work_resolve "$CONVOY" "$BEAD"
case $? in
  0) ;;
  2)
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "input convoy $CONVOY does not have exactly one tracked member; the pour is malformed" \
      --subject "$CONVOY" --key polecat-malformed-convoy \
      --message "Input convoy $CONVOY does not have exactly one tracked member, so mol-polecat-work cannot derive its work bead; the pour is malformed. Its run is cancelled and nothing was touched. Sling the work again to pour a well-formed run, then clear this gate."
    exit 1 ;;
  *) work_outage "could not read input convoy $CONVOY" ;;
esac

work_read "$WORK_ID"
case $? in
  0) ;;
  3)
    WHY="unreadable (the store has no such bead)"
    note "Unreadable work bead; run cancelled for a person" "$WHY"
    if ! "$SCRIPT_DIR/patrol-finding.sh" --scope polecat-findings --key "polecat-unreadable-work.$WORK_ID" \
        --title "Work bead $WORK_ID could not be read at load-context" \
        --message "Could not read work bead $WORK_ID at load-context (the store has no such bead), so nothing proves it is safe to build. $DISPATCHED_BY dispatched it to $SELF. Its run is cancelled and no workspace was touched. Check that the bead exists and its store answers, then re-sling it."; then
      echo "$PROG: patrol-finding.sh recorded no finding; NOT cancelling or draining, so the next worker retries." >&2
      exit 1
    fi
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "unreadable work bead: $WORK_ID $WHY"
    exit 1 ;;
  *) work_outage "could not read work bead $WORK_ID" ;;
esac

STATUS=$(work_field .status)
OWNER=$(work_field .assignee)
MERGE_RESULT=$(work_meta merge_result)
MERGED=""
[ -z "$MERGE_RESULT" ] || MERGED="already carrying merge_result=$MERGE_RESULT; a PR or merge exists for this bead"

# A finished bead or a live duplicate: the note and the cancel say why, and
# nobody is asked anything.
refuse() { # <note label> <cancel label> <why>
  note "$1" "$3"
  "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "$2: $WORK_ID $3"
  exit 1
}
FINISHED_NOTE="Duplicate dispatch refused (work finished; run cancelled with nothing asked)"
FINISHED_CANCEL="duplicate dispatch (work finished)"
DUPLICATE_NOTE="Duplicate dispatch refused; run cancelled"

case "$STATUS" in
  closed)
    # A close that lands after the pour, such as a duplicate or a no-work close,
    # leaves the assignee empty and stamps no merge_result, so the reason carries
    # what the bead records about its close.
    [ -z "$MERGED" ] || refuse "$FINISHED_NOTE" "$FINISHED_CANCEL" "$MERGED"
    HOW=$(printf '%s' "$WORK_ROW" | jq -r '.[0] | [(.metadata["gc.superseded_by"] // "" | tostring | select(length > 0) | "superseded by " + .), (.metadata["gc.outcome"] // "" | tostring | select(length > 0) | "outcome " + .), (.close_reason // "" | tostring | gsub("[[:space:]]+"; " ") | select(length > 0) | "close reason: " + .[0:200])] | join("; ")')
    refuse "Closed before claim; run cancelled with nothing asked" "closed before claim" "already closed${HOW:+ ($HOW)}; its work is done or was ruled unnecessary" ;;
  open|in_progress)
    if [ -n "$OWNER" ] && ! work_is_self "$OWNER"; then
      if [ "$STATUS" = open ]; then
        # The refinery's handoff leaves the bead open under the refinery, route
        # cleared. A fresh or rework dispatch reaches here with no assignee.
        refuse "$FINISHED_NOTE" "$FINISHED_CANCEL" "already handed off (open, held by $OWNER); another dispatch carried it past this point"
      fi
      LISTED=$(work_owner_listed "$OWNER")
      [ "$LISTED" = 0 ] || refuse "$DUPLICATE_NOTE" "duplicate dispatch" "already in_progress under live $OWNER"
    fi
    [ -z "$MERGED" ] || refuse "$FINISHED_NOTE" "$FINISHED_CANCEL" "$MERGED" ;;
  *)
    # Whoever parked the bead releases it, and nothing re-slings it then. A
    # merge_result still reads as finished: the PR is with the refinery.
    [ -z "$MERGED" ] || refuse "$FINISHED_NOTE" "$FINISHED_CANCEL" "$MERGED"
    WHY="parked (status $STATUS), so it is not this session's to build"
    note "Parked work bead; run cancelled for a person" "$WHY"
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "parked work bead: $WORK_ID $WHY" \
      --subject "$WORK_ID" --key polecat-parked-work \
      --message "Work bead $WORK_ID is $STATUS. $DISPATCHED_BY reached $SELF with it. A parked bead is not built, so its run is cancelled and no workspace was touched. Nothing re-slings it when it is released: once it is ready to build, re-sling it with gc sling <pool> $WORK_ID --on $FORMULA."
    exit 1 ;;
esac

# `gc sling --on` pours at once and reads no blocks edges, so a blocked bead
# reaches a polecat as an offered claim. The first open blocker carries the wait,
# and the others hold the bead out of bd ready the same way.
OPEN_BLOCKERS=$(printf '%s' "$WORK_ROW" | jq -r '[.[0].dependencies[]? | select((.dependency_type == "blocks") and (.status != "closed")) | .id] | join(" ")')
if [ -n "$OPEN_BLOCKERS" ]; then
  if "$SCRIPT_DIR/await-ruling.sh" "$WORK_ID" --blocked-by "${OPEN_BLOCKERS%% *}" --formula "$FORMULA"; then
    gc bd update "$WORK_ID" --append-notes "bd-ready guard: refused to build $WORK_ID at load-context; open blocks-blocker(s): $OPEN_BLOCKERS. Run cancelled; a re-sling is armed to fire once the blocker(s) close." </dev/null >/dev/null 2>&1 \
      || echo "$PROG: The refusal note did not land on $WORK_ID; the cancel reason on this step still records it." >&2
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "work bead $WORK_ID has open blocks-blocker(s) $OPEN_BLOCKERS; a re-sling is armed for when they close"
  else
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "work bead $WORK_ID has open blocks-blocker(s) $OPEN_BLOCKERS" \
      --subject "$WORK_ID" --key polecat-blocked-work \
      --message "Formula-slung $WORK_ID reached a polecat while blocked by open blocks-dep(s): $OPEN_BLOCKERS. Its run is cancelled and no workspace was touched. The re-sling could not be armed; re-sling this work once the blocker(s) close."
  fi
  exit 1
fi

WORK_DIR=$(work_meta work_dir)
HOLDER=$(work_meta work_holder)
BRANCH=$(work_meta branch)
TREE_RC=0
if CORE_SCRIPTS=$(gc core scripts-dir </dev/null 2>/dev/null) && [ -x "$CORE_SCRIPTS/work-holder.sh" ]; then
  TREE_FINDING=$("$CORE_SCRIPTS/work-holder.sh" --claim --bead "$WORK_ID" --work-dir "$WORK_DIR" --holder "$HOLDER" --branch "$BRANCH") || TREE_RC=$?
else
  TREE_RC=2
  TREE_FINDING="core's work-holder.sh could not be run, because gc core scripts-dir did not name a directory holding it, so a session holding the work's tree cannot be ruled out"
fi

case "$TREE_RC" in
  0)
    [ -z "$TREE_FINDING" ] || echo "$TREE_FINDING"
    exit 0 ;;
  1)
    # A live session holds the work. On this bead's own record that is another
    # run of this work. On a sibling's record it is different work on the branch.
    if work_read "$WORK_ID"; then HOLDER=$(work_meta work_holder); fi
    if [ -n "$HOLDER" ] && ! work_is_self "$HOLDER"; then
      refuse "$DUPLICATE_NOTE" "duplicate dispatch" "in flight in another session's tree: $TREE_FINDING"
    fi
    SIBLING=""
    if [ -n "$BRANCH" ]; then
      while IFS="$(printf '\t')" read -r ROW_ID ROW_HOLDER; do
        [ -n "$ROW_ID" ] && [ -n "$ROW_HOLDER" ] && ! work_is_self "$ROW_HOLDER" || continue
        if [ "$(work_owner_listed "$ROW_HOLDER")" != 0 ]; then
          SIBLING="$ROW_ID"
          break
        fi
      done <<ROWS
$(bd_json list --metadata-field "branch=$BRANCH" --limit 0 | jq -r --arg me "$WORK_ID" '.[]? | select(.id != $me) | [.id, (.metadata.work_holder // "")] | @tsv' 2>/dev/null)
ROWS
    fi
    if [ -n "$SIBLING" ] && "$SCRIPT_DIR/await-ruling.sh" "$WORK_ID" --blocked-by "$SIBLING" --formula "$FORMULA"; then
      gc bd update "$WORK_ID" --append-notes "Yielded behind sibling $SIBLING on $BRANCH, whose run holds the tree: $TREE_FINDING. A re-sling is armed for when it closes." </dev/null >/dev/null 2>&1 \
        || echo "$PROG: The note did not land on $WORK_ID; the cancel reason on this step still records it." >&2
      "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "work bead $WORK_ID waits on sibling $SIBLING, whose run holds $BRANCH; a re-sling is armed for when it closes"
      exit 1
    fi ;;
esac

# No check could rule a holder out, so a person looks at the tree.
WHY="possibly in flight in another session's tree: ${TREE_FINDING:-work-holder.sh exited $TREE_RC with no finding}"
note "$DUPLICATE_NOTE" "$WHY"
"$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "duplicate dispatch: $WORK_ID $WHY" \
  --subject "$WORK_ID" --key polecat-duplicate-dispatch --formula "$FORMULA" \
  --message "Possible duplicate dispatch on $WORK_ID: it is $WHY. $DISPATCHED_BY dispatched it to $SELF. Its run is cancelled and no workspace was touched. Check the tree: if a live run is using it, salvage its uncommitted and unpushed work and let that run own the bead. The next run builds only if no live run holds the tree."
exit 1
