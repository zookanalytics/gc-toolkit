#!/usr/bin/env bash
# zero-diff-guard — refuse to land a prepared branch that changes nothing
# against its target.
#
#   zero-diff-guard.sh --work <bead> --branch <branch> --target <target-branch>
#
# A close-as-merged, or a PR for a branch that merges to a no-op, is a false
# completion. The prepared head is the detached prep worktree's HEAD, which the
# rebase step staged at <rig git dir>/gc-refinery-prep. It introduces a real
# change when it differs from its merge-base with origin/<target> and carries
# at least one commit past it. A head that does not, and one the check cannot
# compute, are both refused: a tool error is a suspect, never a pass. A refusal
# parks the bead at refused_false_completion, routed to a human, files the
# escalation, and drains; it is never silently retried.
#
# The rig root resolves from GC_RIG_ROOT or the roster, never from the cwd, with
# the lookup every refinery block copies verbatim.
#
# Called by mol-refinery-patrol's merge-push step, in both merge modes.
# env: GC_RIG_ROOT, GC_RIG; GC_LIFECYCLE_TOOL and GC_ESCALATE_TOOL replace the
#      sibling scripts.
# exit: 0 the branch changes something · 1 refused (parked, escalated, drained)
#       · 2 usage
set -e

PROG="zero-diff-guard"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LC="${GC_LIFECYCLE_TOOL:-$SCRIPTS_DIR/lifecycle.sh}"
ESCALATE="${GC_ESCALATE_TOOL:-$SCRIPTS_DIR/escalate.sh}"

usage() { echo "usage: $PROG --work <bead> --branch <branch> --target <target-branch>" >&2; }

WORK=""; BRANCH=""; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --work|--branch|--target)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; usage; exit 2; }
      case "$1" in
        --work)   WORK="$2" ;;
        --branch) BRANCH="$2" ;;
        --target) TARGET="$2" ;;
      esac
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

# branch_has_real_change <target-ref> <head> — 0 the head changes something
# past its merge-base with the target; 1 it is empty; 2 it could not be computed.
branch_has_real_change() {
  local base rc=0
  base=$(git -C "$RIG_ROOT" merge-base "$1" "$2" 2>/dev/null) || return 2
  git -C "$RIG_ROOT" diff --quiet "$base" "$2" || rc=$?
  case "$rc" in 0) return 1 ;; 1) : ;; *) return 2 ;; esac
  [ "$(git -C "$RIG_ROOT" rev-list --count "$base..$2" 2>/dev/null || echo 0)" -ge 1 ] || return 1
  return 0
}

PREP_SHA=$(git -C "$PREP_WT" rev-parse HEAD 2>/dev/null || echo "")
if [ -n "$PREP_SHA" ] && branch_has_real_change "origin/$TARGET" "$PREP_SHA"; then
  exit 0
fi
"$LC" transition "$WORK" --to refused_false_completion --assignee "" --route human --set false_completion_suspected="branch $BRANCH no verified change vs origin/$TARGET; refused merge-close" --takeaway "the branch has no verified change against its target — refused close-as-merged; inspect the branch or drop the bead" || echo "$PROG: lifecycle.sh did not park $WORK; the escalation below still files" >&2
"$ESCALATE" --subject "$WORK" --key refinery-false-completion --message "Branch $BRANCH introduces no verified change vs origin/$TARGET; refused close-as-merged. Bead parked for a human; never silently retried." || true
gc runtime drain-ack
exit 1
