#!/usr/bin/env bash
# refinery-workspace.sh — the refinery's two directories under a rig's git dir:
# the prep worktree a branch is staged in, and the checks directory the
# patrol's gate reads.
#
# mol-refinery-patrol stages the branch under prep in a detached worktree at
# <rig git dir>/gc-refinery-prep, and runs its gate as a detached job whose
# record is <rig git dir>/gc-refinery-gate, running each regular file in that
# record's checks/ directory as one check. Both paths are rebuilt here from the
# rig root, so no caller names a path to remove. The patrol's steps remove
# these through this script, so no block of the patrol an agent runs removes
# anything itself: Claude Code refuses a call whose shell -c script runs rm
# when it cannot check the removal, and only a person can approve that, which a
# refinery session has no way to ask.
#
# Every iteration stages one bead's branch in the same prep worktree, and
# whatever later acts on the prepared head acts for the bead staged there. So
# stage records in the prep worktree which bead and branch it staged, and held
# prints them: the patrol's merge-push step takes the bead and branch it acts
# for from held, never from the agent's shell, so a WORK or BRANCH left over
# from another bead cannot steer a push or a record. verify checks a bead, and
# a branch when given, against the record, for a caller that is handed them.
# The record is a file in the worktree's own git dir,
# <rig git dir>/worktrees/<name>/gc-refinery-staged: git removes it with the
# worktree, so a later worktree at the path never inherits it, and nothing that
# reads the worktree's files sees it.
#
# Usage:
#   refinery-workspace.sh stage [--rig-root <dir>] --branch <branch> --work <bead>
#       remove any prep worktree an earlier iteration left, then add one
#       detached at origin/<branch>, recording that it holds <branch> for <bead>
#   refinery-workspace.sh held [--rig-root <dir>]
#       print the bead, then the branch, that the prep worktree records it was
#       staged for, one per line
#   refinery-workspace.sh verify [--rig-root <dir>] --work <bead> [--branch <branch>]
#       succeed when the prep worktree records that it holds <bead>'s
#       staging, of <branch> when that is given
#   refinery-workspace.sh teardown [--rig-root <dir>]
#       remove the prep worktree
#   refinery-workspace.sh checks [--rig-root <dir>]
#       leave the gate's checks directory empty, creating it when absent
#
# <dir> is the rig's checkout. Without --rig-root it is the one rig-root.sh
# beside this script resolves, the lookup the patrol's blocks make. Every git
# call names the repository with -C, so the caller's cwd plays no part. The prep
# worktree is detached, so staging and teardown create and delete no branch,
# and the rig root's HEAD never moves.
#
# A `worktree add` killed partway leaves its worktree locked, and git refuses
# a locked worktree a single --force. So both remove the prep worktree with
# --force given twice, and stage adds it with -f given twice, which git needs
# to reuse the path of a locked worktree whose directory holds no .git file,
# one the removal cannot clear. A directory git does not know as a worktree is
# left alone: teardown says it is still there, and stage's add fails and says
# so. Neither prunes. A prune reaches every worktree of the rig, and at the
# prep path it changes no stage's outcome: it skips a locked worktree, and where
# it drops a registration, the add meets the same directory it meets without
# the prune.
#
# Exit: 0 done, and for held and verify, the prep worktree records a staging,
#       for verify that bead's · 1 stage could not add the worktree or record
#       what it holds, held or verify found no record or no worktree at the
#       prep path, verify found another bead or branch, teardown left it
#       behind, or checks could not empty the directory · 2 usage, or no rig
#       root git can read
# Callers: formulas/mol-refinery-patrol.toml and direct-merge-push.sh. The
# patrol's rebase step stages. Its merge-push step reads held first, and tears
# down when there is no record to read. direct-merge-push.sh verifies the bead
# and branch it is handed before it lands. The patrol's run-tests step empties
# the checks, and its rebase conflict arm, handle-failures' branch-caused arm
# and both merge-push paths tear down.
set -uo pipefail

PROG="${0##*/}"
usage() {
  {
    echo "usage: $PROG stage [--rig-root <dir>] --branch <branch> --work <bead>"
    echo "       $PROG held [--rig-root <dir>]"
    echo "       $PROG verify [--rig-root <dir>] --work <bead> [--branch <branch>]"
    echo "       $PROG teardown [--rig-root <dir>]"
    echo "       $PROG checks [--rig-root <dir>]"
  } >&2
  exit 2
}

SUB="${1:-}"
case "$SUB" in
  stage|held|verify|teardown|checks) shift ;;
  *) usage ;;
esac
RIG_ROOT=""; BRANCH=""; WORK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rig-root|--branch|--work)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in
        --rig-root) RIG_ROOT="$2" ;;
        --branch)   BRANCH="$2" ;;
        *)          WORK="$2" ;;
      esac
      shift 2 ;;
    *) usage ;;
  esac
done
case "$SUB" in
  stage)  [ -n "$BRANCH" ] && [ -n "$WORK" ] || usage ;;
  verify) [ -n "$WORK" ] || usage ;;
  *)      [ -z "$BRANCH" ] && [ -z "$WORK" ] || usage ;;
esac

SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
[ -n "$RIG_ROOT" ] || RIG_ROOT=$("$SCRIPTS_DIR/rig-root.sh")
[ -n "$RIG_ROOT" ] || { echo "$PROG: cannot resolve the rig root (no --rig-root, and rig-root.sh resolved none)" >&2; exit 2; }
COMMON=$(git -C "$RIG_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
case "$COMMON" in
  /*) ;;
  *) echo "$PROG: $RIG_ROOT is no git repository" >&2; exit 2 ;;
esac
PREP="$COMMON/gc-refinery-prep"
CHECKS="$COMMON/gc-refinery-gate/checks"

gone() { [ ! -e "$1" ] && [ ! -L "$1" ]; }
# record_file: the record's path in the prep worktree's own git dir, in REC.
# Non-zero when nothing at the prep path is a linked worktree: git resolves a
# directory inside the rig's git dir that is no worktree to that git dir
# itself, which is the common one.
record_file() {
  local dirs gitdir common
  dirs=$(git -C "$PREP" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null) || return 1
  { IFS= read -r gitdir; IFS= read -r common; } <<<"$dirs"
  [ -n "$gitdir" ] && [ "$gitdir" != "$common" ] || return 1
  REC="$gitdir/gc-refinery-staged"
}
# recorded <work|branch>: what the record names, empty when it names nothing.
recorded() { git -C "$PREP" config --file "$REC" --get "staged.$1" 2>/dev/null; }
# read_record [<what the caller asks it to show>]: the record's bead and branch,
# in HELD_WORK and HELD_BRANCH. Non-zero, saying why, when no prep worktree is
# staged or its record does not name both.
read_record() {
  record_file || { echo "$PROG: no prep worktree is staged at $PREP" >&2; return 1; }
  HELD_WORK=$(recorded work)
  HELD_BRANCH=$(recorded branch)
  [ -n "$HELD_WORK" ] && [ -n "$HELD_BRANCH" ] && return 0
  echo "$PROG: the prep worktree at $PREP records no bead and branch${1:+, so nothing shows it holds $1}" >&2
  return 1
}

case "$SUB" in
  stage)
    git -C "$RIG_ROOT" worktree remove --force --force "$PREP" >/dev/null 2>&1 || true
    git -C "$RIG_ROOT" worktree add -f -f --detach "$PREP" "origin/$BRANCH" \
      || { echo "$PROG: could not add the prep worktree $PREP at origin/$BRANCH" >&2; exit 1; }
    # A worktree with no record holds nothing any block will act for, so a
    # record that does not read back fails the stage as a failed add does.
    if ! { record_file && git -C "$PREP" config --file "$REC" staged.work "$WORK" \
         && git -C "$PREP" config --file "$REC" staged.branch "$BRANCH" \
         && [ "$(recorded work)" = "$WORK" ] && [ "$(recorded branch)" = "$BRANCH" ]; }; then
      echo "$PROG: added the prep worktree $PREP at origin/$BRANCH, but could not record that it holds $BRANCH for $WORK" >&2
      exit 1
    fi
    ;;
  held)
    read_record || exit 1
    printf '%s\n%s\n' "$HELD_WORK" "$HELD_BRANCH"
    ;;
  verify)
    read_record "${BRANCH:+$BRANCH for }$WORK" || exit 1
    if [ "$HELD_WORK" != "$WORK" ] || { [ -n "$BRANCH" ] && [ "$HELD_BRANCH" != "$BRANCH" ]; }; then
      echo "$PROG: the prep worktree holds $HELD_BRANCH for $HELD_WORK, not ${BRANCH:+$BRANCH for }$WORK" >&2
      exit 1
    fi
    ;;
  teardown)
    git -C "$RIG_ROOT" worktree remove --force --force "$PREP" >/dev/null 2>&1 || true
    gone "$PREP" || { echo "$PROG: the prep worktree $PREP is still there" >&2; exit 1; }
    ;;
  checks)
    # Every regular file left here would run as a check of the next gate, so
    # the directory is replaced whole and then proved empty.
    rm -rf -- "${CHECKS:?}" 2>/dev/null
    mkdir -p -- "$CHECKS" 2>/dev/null
    if [ ! -d "$CHECKS" ] || [ -L "$CHECKS" ] || [ ! -r "$CHECKS" ] || [ ! -w "$CHECKS" ] || [ -n "$(ls -A -- "$CHECKS" 2>/dev/null)" ]; then
      echo "$PROG: could not empty $CHECKS" >&2
      exit 1
    fi
    ;;
esac
exit 0
