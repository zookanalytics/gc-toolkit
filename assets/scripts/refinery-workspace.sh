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
# Usage:
#   refinery-workspace.sh stage [--rig-root <dir>] --branch <branch>
#       remove any prep worktree an earlier iteration left, then add one
#       detached at origin/<branch>
#   refinery-workspace.sh teardown [--rig-root <dir>]
#       remove the prep worktree
#   refinery-workspace.sh checks [--rig-root <dir>]
#       leave the gate's checks directory empty, creating it when absent
#
# <dir> is the rig's checkout. Without --rig-root it is GC_RIG_ROOT, else the
# roster entry for GC_RIG, the lookup the patrol's blocks make. Every git call
# names the repository with -C, so the caller's cwd plays no part. The prep
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
# Exit: 0 done · 1 stage could not add the worktree, teardown left it behind,
#       or checks could not empty the directory · 2 usage, or no rig root git
#       can read
# Callers: formulas/mol-refinery-patrol.toml. Its rebase step stages, its
# run-tests step empties the checks, and its rebase conflict arm,
# handle-failures' branch-caused arm and both merge-push paths tear down.
set -uo pipefail

PROG="${0##*/}"
usage() {
  {
    echo "usage: $PROG stage [--rig-root <dir>] --branch <branch>"
    echo "       $PROG teardown [--rig-root <dir>]"
    echo "       $PROG checks [--rig-root <dir>]"
  } >&2
  exit 2
}

SUB="${1:-}"
case "$SUB" in
  stage|teardown|checks) shift ;;
  *) usage ;;
esac
RIG_ROOT=""; BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rig-root|--branch)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      if [ "$1" = --rig-root ]; then RIG_ROOT="$2"; else BRANCH="$2"; fi
      shift 2 ;;
    *) usage ;;
  esac
done
if [ "$SUB" = stage ]; then [ -n "$BRANCH" ] || usage; else [ -z "$BRANCH" ] || usage; fi

[ -n "$RIG_ROOT" ] || RIG_ROOT="${GC_RIG_ROOT:-}"
[ -n "$RIG_ROOT" ] || RIG_ROOT=$(gc rig list --json 2>/dev/null | jq -r --arg r "${GC_RIG:-}" '.rigs[] | select(.name == $r) | .path' 2>/dev/null)
[ -n "$RIG_ROOT" ] || { echo "$PROG: cannot resolve the rig root (no --rig-root, GC_RIG_ROOT unset, GC_RIG='${GC_RIG:-}' matched no rig in the roster)" >&2; exit 2; }
COMMON=$(git -C "$RIG_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
case "$COMMON" in
  /*) ;;
  *) echo "$PROG: $RIG_ROOT is no git repository" >&2; exit 2 ;;
esac
PREP="$COMMON/gc-refinery-prep"
CHECKS="$COMMON/gc-refinery-gate/checks"

gone() { [ ! -e "$1" ] && [ ! -L "$1" ]; }

case "$SUB" in
  stage)
    git -C "$RIG_ROOT" worktree remove --force --force "$PREP" >/dev/null 2>&1 || true
    git -C "$RIG_ROOT" worktree add -f -f --detach "$PREP" "origin/$BRANCH" \
      || { echo "$PROG: could not add the prep worktree $PREP at origin/$BRANCH" >&2; exit 1; }
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
