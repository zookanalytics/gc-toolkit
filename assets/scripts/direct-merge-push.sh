#!/usr/bin/env bash
# direct-merge-push — the refinery's direct-mode landing: merge the prepared
# head onto its target in a throwaway worktree, push, verify the remote ref, and
# record + close the bead through one lifecycle transition.
#
#   direct-merge-push.sh --work <bead> --target <target-branch>
#
# The prepared head is the detached prep worktree's HEAD, which the rebase step
# staged at <rig git dir>/gc-refinery-prep. The merge runs in its own detached
# worktree off origin/<target>, because the real target branch may be checked
# out in the rig's canonical worktree. Every git call names its repository with
# -C, and the rig root resolves from GC_RIG_ROOT or the roster, never from the
# cwd: a session whose cwd sits in another repository would otherwise merge and
# push there. An unresolvable rig fails closed before any scratch exists.
#
# A push that lands is verified against the refreshed origin/<target> before
# any bead state moves. A push rejected for branch protection (GH006, GH013,
# "protected branch", "Changes must be made through a pull request", "approving
# review", "Cannot update this protected ref") promotes the bead to
# merge_strategy=pr and exits 3, and the caller takes the mr path: the prep
# worktree is untouched and still holds the prepared head for the PR push. Any
# other failure drains and exits 1, leaving the work with the refinery.
#
# The merge worktree and its scratch directory are removed on every exit.
#
# Called by mol-refinery-patrol's merge-push step.
# env: GC_RIG_ROOT, GC_RIG; GC_LIFECYCLE_TOOL replaces the sibling lifecycle.sh.
# exit: 0 merged, pushed, verified and closed · 1 failed (drained) · 2 usage
#       · 3 promoted to merge_strategy=pr (take the mr path)
# Errexit only, as the block this was ran: the rig-root lookup below is the one
# every refinery block copies verbatim, and it reads GC_RIG bare.
set -e

PROG="direct-merge-push"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LC="${GC_LIFECYCLE_TOOL:-$SCRIPTS_DIR/lifecycle.sh}"

usage() { echo "usage: $PROG --work <bead> --target <target-branch>" >&2; }

WORK=""; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --work|--target)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; usage; exit 2; }
      if [ "$1" = --work ]; then WORK="$2"; else TARGET="$2"; fi
      shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if [ -z "$WORK" ] || [ -z "$TARGET" ]; then
  echo "$PROG: --work and --target are required" >&2
  usage
  exit 2
fi

RIG_ROOT="${GC_RIG_ROOT:-}"
[ -n "$RIG_ROOT" ] || RIG_ROOT=$(gc rig list --json | jq -r --arg r "$GC_RIG" '.rigs[] | select(.name == $r) | .path')
[ -n "$RIG_ROOT" ] || { echo "cannot resolve the rig root (GC_RIG_ROOT unset, GC_RIG='$GC_RIG' matched no rig in the roster); leaving the work with the refinery to retry"; gc runtime drain-ack; exit 1; }
PREP_WT="$(git -C "$RIG_ROOT" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"
MERGE_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/gascity-refinery-merge.XXXXXX")
MERGE_WT="$MERGE_PARENT/target"
# $PUSH_ERR is allocated further down but torn down here: every arm that reads
# it exits without reaching a removal of its own.
PUSH_ERR=""
merge_scratch_rm() { git -C "$RIG_ROOT" worktree remove --force "$MERGE_WT" >/dev/null 2>&1 || true; rm -rf "$MERGE_PARENT"; [ -n "$PUSH_ERR" ] && rm -f "$PUSH_ERR"; return 0; }
trap merge_scratch_rm EXIT; trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
git -C "$RIG_ROOT" fetch origin "+refs/heads/${TARGET}:refs/remotes/origin/${TARGET}"
TEMP_SHA=$(git -C "$PREP_WT" rev-parse HEAD)
git -C "$RIG_ROOT" worktree add --detach "$MERGE_WT" "origin/$TARGET"
git -C "$MERGE_WT" merge --ff-only "$TEMP_SHA"
MERGED_SHA=$(git -C "$MERGE_WT" rev-parse HEAD)
PUSH_ERR=$(mktemp "${TMPDIR:-/tmp}/gctk-refinery-patrol.XXXXXX")
if git -C "$MERGE_WT" push origin "HEAD:$TARGET" 2>"$PUSH_ERR"; then
  git -C "$RIG_ROOT" fetch origin "+refs/heads/${TARGET}:refs/remotes/origin/${TARGET}"
  REMOTE=$(git -C "$RIG_ROOT" rev-parse "origin/$TARGET")
  if [ "$MERGED_SHA" != "$REMOTE" ]; then
    echo "PUSH FAILED — origin/$TARGET is $REMOTE, want $MERGED_SHA. STOP; do not mutate bead state."
    gc runtime drain-ack; exit 1
  fi
  "$LC" transition "$WORK" --to merged --close --set merged_sha="$MERGED_SHA" --set merged_target="$TARGET" --unset rejection_reason --append-notes "Merged to $TARGET at $(git -C "$MERGE_WT" rev-parse --short HEAD)"
else
  case "$(cat "$PUSH_ERR")" in
    *GH006*|*GH013*|*"protected branch"*|*"refusing to allow"*|*"Changes must be made through a pull request"*|*"approving review"*|*"Cannot update this protected ref"*)
      echo "Direct push to '$TARGET' rejected (protected branch). Auto-promoting to merge_strategy=pr."
      gc bd update "$WORK" --set-metadata merge_strategy=pr
      exit 3 ;;
    *) echo "Push failed: $(cat "$PUSH_ERR"). STOP. Debug and retry; do NOT continue."; gc runtime drain-ack; exit 1 ;;
  esac
fi
