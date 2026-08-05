#!/bin/sh
# nx-worktree-setup.sh — idempotent per-worker worktree provisioning for
# the wright/lander/outrider pools. (Brand: every pool worker builds in
# its own worktree, never in the rig checkout.)
#
# Usage: nx-worktree-setup.sh <rig-root> <work-dir> <agent-base> [--sync]
#
# Carried in intent from the live pack's worktree-setup.sh (see
# PORTS.md); this staging version provisions the minimal shape — a
# detached worktree per agent base off the rig's default branch —
# and hard-fails loudly rather than half-provisioning.
set -eu

RIG_ROOT="${1:?rig-root}"
WORK_DIR="${2:?work-dir}"
AGENT_BASE="${3:?agent-base}"
SYNC="${4:-}"

[ -d "$RIG_ROOT/.git" ] || { echo "nx-worktree-setup: $RIG_ROOT is not a git checkout" >&2; exit 1; }

if [ ! -d "$WORK_DIR/.git" ] && [ ! -f "$WORK_DIR/.git" ]; then
  mkdir -p "$(dirname "$WORK_DIR")"
  DEFAULT_BRANCH="$(git -C "$RIG_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
  git -C "$RIG_ROOT" worktree add --detach "$WORK_DIR" "origin/$DEFAULT_BRANCH" 2>/dev/null \
    || git -C "$RIG_ROOT" worktree add --detach "$WORK_DIR" "$DEFAULT_BRANCH"
fi

if [ "$SYNC" = "--sync" ]; then
  git -C "$RIG_ROOT" fetch origin --prune 2>/dev/null || echo "nx-worktree-setup: fetch failed (offline?); continuing on local refs" >&2
fi

echo "nx-worktree-setup: $AGENT_BASE ready at $WORK_DIR"
