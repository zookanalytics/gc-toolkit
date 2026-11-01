#!/usr/bin/env bash
# work-enter — a step of mol-polecat-work that a session claims part way through
# a run enters the run's worktree, recorded on the work bead.
#
#   work-enter.sh --convoy <id>|--bead <id> --step <ref>
#
# A session does not inherit the tree the last step ran in. A work bead closed
# while its run was mid-flight was withdrawn by whoever closed it, and Gas City's
# autoclose leaves a run with open steps alone, so this ends the run rather than
# let it go on. Otherwise it checks out the recorded branch. A self-review
# iteration also records the work bead as the root's gc.var.issue, which
# self-review-check.sh takes when the store is too degraded to read the run.
#
# It prints the bead's notes, because a coordinator may have appended a
# correction since the claim's read, and then the worktree's path as the last
# line, which the caller enters.
#
# exit: 0 entered · 1 stopped, and what follows was taken care of · 2 usage
set -uo pipefail

PROG="work-enter"

usage() {
  cat >&2 <<'USAGE'
usage: work-enter.sh --convoy <id>|--bead <id> --step <ref>

  --convoy  the run's input convoy; its one tracked bead is the work
  --bead    the work bead, for a claimant with no poured workflow
  --step    the step this session holds, e.g. self-review

exit: 0 entered · 1 stopped · 2 usage
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
}

CONVOY=""; BEAD=""; STEP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --convoy) require_value "$@"; CONVOY="$2"; shift 2 ;;
    --bead)   require_value "$@"; BEAD="$2";   shift 2 ;;
    --step)   require_value "$@"; STEP="$2";   shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *)        echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if { [ -n "$CONVOY" ] && [ -n "$BEAD" ]; } || { [ -z "$CONVOY" ] && [ -z "$BEAD" ]; } || [ -z "$STEP" ]; then
  echo "$PROG: name the work with --convoy or --bead, not both, and the step with --step" >&2
  usage
  exit 2
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=work-lib.sh
. "$SCRIPT_DIR/work-lib.sh"

work_resolve "$CONVOY" "$BEAD"
case $? in
  0) ;;
  2) echo "$PROG: input convoy $CONVOY does not have exactly one tracked member" >&2; exit 1 ;;
  *) work_outage "could not read input convoy $CONVOY" ;;
esac
work_read "$WORK_ID"
case $? in
  0) ;;
  3) echo "$PROG: the store has no bead $WORK_ID, so there is no tree to enter" >&2; exit 1 ;;
  *) work_outage "could not read work bead $WORK_ID" ;;
esac

if [ "$(work_field .status)" = closed ]; then
  "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "work bead $WORK_ID was closed while its run was mid-flight"
  exit 1
fi

WORKTREE=$(work_meta work_dir)
if [ -z "$WORKTREE" ] || ! cd "$WORKTREE" 2>/dev/null; then
  echo "$PROG: the work_dir $WORK_ID records is missing: ${WORKTREE:-none recorded}" >&2
  exit 1
fi
BRANCH=$(work_meta branch)
if [ -n "$BRANCH" ] && [ "$(git branch --show-current 2>/dev/null)" != "$BRANCH" ]; then
  git checkout "$BRANCH" >&2 || echo "$PROG: could not check out $BRANCH in $WORKTREE; the step's checks stop on the branch it is on" >&2
fi

case "$STEP" in
  self-review)
    ROOT=""
    if CLAIMED=$(gc hook current --id-only </dev/null 2>/dev/null) && [ -n "$CLAIMED" ]; then
      ROOT=$(bd_json show "$CLAIMED" | jq -r '.[0].metadata["gc.root_bead_id"] // empty' 2>/dev/null)
    fi
    [ -z "$ROOT" ] || gc bd update "$ROOT" --set-metadata "gc.var.issue=$WORK_ID" </dev/null >/dev/null \
      || echo "$PROG: NOTE: root $ROOT does not record gc.var.issue=$WORK_ID" >&2 ;;
esac

NOTES=$(work_field .notes)
if [ -n "$NOTES" ]; then
  echo "Notes on $WORK_ID:"
  printf '%s\n' "$NOTES"
fi
pwd
