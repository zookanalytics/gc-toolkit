#!/usr/bin/env bash
# refinery-land.sh — the refinery patrol's merge-push step: land the prepared
# head, or hand it to its PR.
#
#   refinery-land.sh --bead <id>
#
# The bead is the one this iteration prepared and gated, assigned to this
# refinery ($GC_AGENT), and the refinery's tree for it must hold its branch
# (refinery-lib.sh). One `gc formula show mol-refinery-patrol --rig $GC_RIG`
# read gives the step its formula vars, the rig's value winning over the
# default: default_merge_strategy and delete_merged_branches.
#
# The strategy is the bead's merge_strategy, else the default, with Gas City's
# values: `direct` and `mr`, and `pr` read as `mr`. A bead that would land
# direct on the rig's default branch, or that names an existing_pr, takes `mr`,
# so the default branch takes work only through a PR (docs/warrants.md). Any
# other strategy parks the bead behind the gate refinery-unsupported-strategy.
#
# A prepared head with no change against its target is no landing. When the
# target carries the commit the bead's direct_landing_sha stamp names, a direct
# landing an earlier patrol pushed is recorded on the direct path. Otherwise
# the bead is parked behind the gate refinery-false-completion, with
# merge_result=refused_false_completion, and never retried silently.
#
# direct lands through direct-merge-push.sh, which records merged and closes the
# bead, and deletes the branch when delete_merged_branches says so. A push it
# finds refused for branch protection promotes the bead to mr. mr runs
# refinery-publish.sh, which publishes the prepared head on its owner's PR and
# records the PR pending until the landing order verifies its merge, and closes
# a rework child handed back once its head is pushed.
#
# Every park files its human gate first, sets the merge_result, and keeps the
# bead with the refinery, so clearing the gate hands it back. A bead handed
# back still carries the park's merge_result, blocked or
# refused_false_completion, until its landing or its publication records the
# next one. The tree is removed once the step has done its part.
#
# Exit: 0 landed, published, or handed back
#       1 nothing landed, and the work stays with the refinery to retry; the
#         output says what landed, if anything
#       2 usage
#       4 the bead is parked behind a human gate
#       6 the branch or the target moved after the prep, so nothing landed;
#         the next pass prepares it again
set -uo pipefail

PROG="refinery-land"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }

usage() { echo "usage: $PROG --bead <id>" >&2; exit 2; }
BEAD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead) [ "$#" -ge 2 ] || usage; BEAD="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$BEAD" ] || usage

stop() { echo "$PROG: $1; the work stays with the refinery to retry" >&2; exit 1; }
teardown() { refinery_teardown "$HOME_DIR" "$BEAD" || echo "$PROG: the next prep removes the tree for $BEAD" >&2; }

HOME_DIR=$(refinery_home) || stop "the refinery's own worktree is unknown"
refinery_bead "$BEAD" || stop "$BEAD did not read"
[ -n "${GC_AGENT:-}" ] && [ "$(bead_field assignee)" = "$GC_AGENT" ] \
  || stop "$BEAD is assigned to $(bead_field assignee), not this refinery (${GC_AGENT:-GC_AGENT unset})"
BRANCH=$(bead_meta branch)
refinery_require "$HOME_DIR" "$BEAD" "$BRANCH" || stop "this iteration did not prepare $BEAD"
HEAD_OID="$PREP_HEAD"
DEFAULT_BRANCH=$(refinery_default_branch "$HOME_DIR") || stop "origin/HEAD names no default branch in $HOME_DIR"
TARGET=$(bead_meta target)
[ -n "$TARGET" ] || TARGET="$DEFAULT_BRANCH"

refinery_formula_vars || stop "the rig's formula vars did not read"

# park <key> <merge_result> <reason> <gate message>: the bead waits behind a
# human gate, still assigned to the refinery, and its tree is removed
# (refinery_park).
park() {
  refinery_park "$BEAD" "$1" "$2" "$3" "$4" "$HOME_DIR" || stop "the $1 gate on $BEAD did not land ($3)"
}
STRATEGY=$(bead_meta merge_strategy)
[ -n "$STRATEGY" ] || STRATEGY=$(refinery_formula_var default_merge_strategy)
[ -n "$STRATEGY" ] || STRATEGY=direct
[ "$STRATEGY" != pr ] || STRATEGY=mr
if [ "$STRATEGY" = direct ] && { [ "$TARGET" = "$DEFAULT_BRANCH" ] || [ -n "$(bead_meta existing_pr)" ]; }; then
  STRATEGY=mr
fi
case "$STRATEGY" in
  direct|mr) ;;
  *) park refinery-unsupported-strategy blocked "merge_strategy=$STRATEGY is not one the refinery lands" \
       "$BEAD asks for merge_strategy=$STRATEGY, and the refinery lands only direct and mr, so it landed nothing. Set merge_strategy on $BEAD to direct or mr, then clear this gate: clearing it hands $BEAD back to the refinery." ;;
esac

git -C "$HOME_DIR" fetch --no-tags origin "+refs/heads/$TARGET:refs/remotes/origin/$TARGET" >/dev/null 2>&1 \
  || stop "origin/$TARGET did not fetch"
# branch_has_real_change: 0 when the prepared head changes something against
# its merge base with the target, 1 when it changes nothing, 2 when git could
# not tell, with BHRC_ERROR saying why. A tool error is never "no change".
branch_has_real_change() {
  local out base rc
  BHRC_ERROR=""
  out=$(git -C "$HOME_DIR" merge-base "refs/remotes/origin/$TARGET" "$HEAD_OID" 2>&1) \
    || { BHRC_ERROR="merge-base failed: $(printf '%s' "$out" | tr -s '[:space:]' ' ')"; return 2; }
  base=$(printf '%s' "$out" | tail -n 1)
  out=$(git -C "$HOME_DIR" diff --quiet "$base" "$HEAD_OID" 2>&1)
  rc=$?
  [ "$rc" != 0 ] || return 1
  [ "$rc" = 1 ] || { BHRC_ERROR="diff failed: $(printf '%s' "$out" | tr -s '[:space:]' ' ')"; return 2; }
  out=$(git -C "$HOME_DIR" rev-list --count "$base..$HEAD_OID" 2>&1) \
    || { BHRC_ERROR="rev-list failed: $(printf '%s' "$out" | tr -s '[:space:]' ' ')"; return 2; }
  [ "$(printf '%s' "$out" | tail -n 1)" -ge 1 ] || return 1
}
branch_has_real_change
case "$?" in
  0) ;;
  1)
    STAMP=$(bead_meta direct_landing_sha)
    if [ -n "$STAMP" ] && git -C "$HOME_DIR" merge-base --is-ancestor "$STAMP" "refs/remotes/origin/$TARGET" 2>/dev/null; then
      echo "$PROG: origin/$TARGET carries $STAMP, which a direct landing of $BEAD pushed without recording; taking the direct path to record it"
      STRATEGY=direct
    else
      park refinery-false-completion refused_false_completion "branch $BRANCH has no verified change against origin/$TARGET; refused close-as-merged" \
        "Branch $BRANCH of $BEAD introduces no verified change against origin/$TARGET, so the refinery refused to close it as landed and opened no PR. Inspect the branch: push the work it should carry, then clear this gate, which hands $BEAD back to the refinery; or drop the work: run $HERE/stand-down.sh $BEAD --key refinery-false-completion --ruling '<why>'."
    fi ;;
  *) stop "the zero-diff check of $HEAD_OID against origin/$TARGET could not run ($BHRC_ERROR), which says nothing about the branch" ;;
esac

if [ "$STRATEGY" = direct ]; then
  DIRECT=(--work "$BEAD" --branch "$BRANCH" --target "$TARGET")
  [ "$(refinery_formula_var delete_merged_branches)" != true ] || DIRECT+=(--delete-branch)
  "$HERE/direct-merge-push.sh" "${DIRECT[@]}"
  case "$?" in
    0) teardown; exit 0 ;;
    3) STRATEGY=mr ;;
    4) teardown; echo "$PROG: origin/$TARGET moved after $BEAD was prepared, so nothing landed; the next pass prepares it again"; exit 6 ;;
    *) stop "direct-merge-push.sh landed nothing it could record (its output above says what)" ;;
  esac
fi

"$HERE/refinery-publish.sh" --bead "$BEAD"
RC=$?
case "$RC" in 0|4|6) teardown; exit "$RC" ;; *) exit 1 ;; esac
