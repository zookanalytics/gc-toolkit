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
# default: default_merge_strategy, delete_merged_branches, check_set and
# pending_through_merge, the switch that puts the rig on the new path.
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
# finds refused for branch protection promotes the bead to mr. mr runs the new
# path's publication (refinery-publish.sh) when pending_through_merge is
# "true". Otherwise it keeps the old path: the head is pushed under the lease
# on the commit the prep read, and the bead is parked for the merge cadence,
# at pull_request when it records a PR open from its branch, else at
# pre_open_gate, with merged_target and check_set, through lifecycle.sh. On
# either path a rework child handed back lands on its anchor's branch: the
# anchor's PR has its title and body brought current before the push, and the
# child closes with its work record.
#
# Every park files its human gate first, sets the merge_result, and keeps the
# bead with the refinery, so clearing the gate hands it back. The tree is
# removed once the step has done its part.
#
# Exit: 0 landed, published, parked for the cadence, or handed back
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
# shellcheck source=gctk-resolve.sh
. "$HERE/gctk-resolve.sh" || { echo "$PROG: cannot source gctk-resolve.sh beside this script" >&2; exit 1; }

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
HEAD_OID="$PREP_HEAD"; READ="$PREP_READ"; TREE="$PREP_TREE"
DEFAULT_BRANCH=$(refinery_default_branch "$HOME_DIR") || stop "origin/HEAD names no default branch in $HOME_DIR"
TARGET=$(bead_meta target)
[ -n "$TARGET" ] || TARGET="$DEFAULT_BRANCH"

[ -n "${GC_RIG:-}" ] || stop "GC_RIG is unset, so the rig's formula vars cannot be read"
VARS=$(gc formula show mol-refinery-patrol --rig "$GC_RIG" --json </dev/null 2>/dev/null) || VARS=""
printf '%s' "$VARS" | jq -e '.ok == true and (.vars | type == "array")' >/dev/null 2>&1 \
  || stop "the formula vars of rig '$GC_RIG' did not read (gc formula show --rig)"
var() {
  printf '%s' "$VARS" | jq -r --arg n "$1" '[.vars[] | select(.name == $n)][0]
    | if . == null then "" elif .rig_default != null then .rig_default else (.default // "") end'
}

# park <key> <merge_result> <reason> <gate message>
park() {
  "$HERE/human-gate.sh" --subject "$BEAD" --key "$1" --message "$4" >/dev/null \
    || stop "the $1 gate on $BEAD did not land ($3)"
  gc bd update "$BEAD" --if-assignee="$GC_AGENT" --set-metadata "merge_result=$2" --set-metadata "blocked_reason=$3" </dev/null >/dev/null \
    || echo "$PROG: the $1 gate holds $BEAD, but merge_result=$2 did not land on it" >&2
  teardown
  echo "$PROG: parked $BEAD behind its $1 gate: $3"
  exit 4
}

STRATEGY=$(bead_meta merge_strategy)
[ -n "$STRATEGY" ] || STRATEGY=$(var default_merge_strategy)
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
  [ "$(var delete_merged_branches)" != true ] || DIRECT+=(--delete-branch)
  "$HERE/direct-merge-push.sh" "${DIRECT[@]}"
  case "$?" in
    0) teardown; exit 0 ;;
    3) STRATEGY=mr ;;
    4) teardown; echo "$PROG: origin/$TARGET moved after $BEAD was prepared, so nothing landed; the next pass prepares it again"; exit 6 ;;
    *) stop "direct-merge-push.sh landed nothing it could record (its output above says what)" ;;
  esac
fi

if [ "$(var pending_through_merge)" = true ]; then
  "$HERE/refinery-publish.sh" --bead "$BEAD"
  RC=$?
  case "$RC" in 0|4|6) teardown; exit "$RC" ;; *) exit 1 ;; esac
fi

# The old path, while pending_through_merge is unset.
refinery_owner "$BEAD" "$BRANCH" || stop "the bead whose PR $BRANCH lands on cannot be told"
REPO=$(origin_repo "$HOME_DIR") || REPO=""
# owner_pr: the PR the owner records, read from GitHub into PR_URL and
# PR_NUMBER and held in PR_ROW, when it is open from the branch into the target.
owner_pr() {
  local recorded
  PR_URL=""; PR_NUMBER=""; PR_ROW=""
  recorded=$(row_meta "$OWNER_ROW" existing_pr)
  [ -n "$recorded" ] || recorded=$(row_meta "$OWNER_ROW" pr_url)
  [ -n "$recorded" ] || recorded=$(row_meta "$OWNER_ROW" pr_number)
  [ -n "$recorded" ] && [ -n "$REPO" ] || return 1
  PR_ROW=$(gh pr view "$recorded" --repo "$REPO" --json number,url,state,headRefName,baseRefName,title,body </dev/null 2>/dev/null) || return 1
  printf '%s' "$PR_ROW" | jq -e --arg b "$BRANCH" --arg t "$TARGET" '.state == "OPEN" and .headRefName == $b and .baseRefName == $t' >/dev/null 2>&1 || return 1
  PR_URL=$(printf '%s' "$PR_ROW" | jq -r '.url // ""')
  PR_NUMBER=$(printf '%s' "$PR_ROW" | jq -r '(.number // "") | tostring')
  [ -n "$PR_URL" ] && [ -n "$PR_NUMBER" ]
}
# refresh: bring the owner's open PR's title and body current with the owner at
# the prepared head, before the head is pushed.
refresh() {
  local gctk out title moved body published edit=()
  owner_pr || return 0
  gctk=$(gctk_path) || { echo "$PROG: no gctk binary, so PR #$PR_NUMBER's title and body stay as they are" >&2; return 0; }
  published=$(mktemp "${TMPDIR:-/tmp}/refinery-land.XXXXXX") || return 0
  body=$(mktemp "${TMPDIR:-/tmp}/refinery-land.XXXXXX") || { rm -f "$published"; return 0; }
  printf '%s' "$PR_ROW" | jq -j '.body // ""' > "$published"
  if out=$("$gctk" pr compose "$OWNER" --head "$HEAD_OID" --gates '' --body-file "$published" </dev/null); then
    title=$(printf '%s' "$out" | jq -r '.title // ""')
    moved=$(printf '%s' "$out" | jq -r 'if .summary == "written" or .branch_beads == "written" then "yes" else "" end')
    printf '%s' "$out" | jq -j '.body // ""' > "$body"
    [ -z "$title" ] || [ "$(printf '%s' "$title" | tr -s '[:space:]' ' ')" = "$(printf '%s' "$PR_ROW" | jq -r '.title // ""' | tr -s '[:space:]' ' ')" ] || edit+=(--title "$title")
    [ -z "$moved" ] || [ ! -s "$body" ] || edit+=(--body-file "$body")
    if [ "${#edit[@]}" -gt 0 ] && ! gh pr edit "$PR_NUMBER" --repo "$REPO" "${edit[@]}" </dev/null >/dev/null; then
      echo "$PROG: PR #$PR_NUMBER's title and body did not take; the head is pushed, and the next round brings them current" >&2
    fi
  else
    echo "$PROG: PR #$PR_NUMBER's title and body did not compose from $OWNER; they stay as they are" >&2
  fi
  rm -f "$published" "$body"
}
push() {
  "$HERE/branch-push.sh" --repo "$TREE" --branch "$BRANCH" --head "$HEAD_OID" --from "$READ" >&2
  case "$?" in
    0) ;;
    3) teardown; echo "$PROG: $BRANCH moved on origin after the prep read $READ there, so nothing was pushed; the next pass prepares it again"; exit 6 ;;
    *) stop "the push of $HEAD_OID onto $BRANCH did not land" ;;
  esac
}

if [ "$OWNER" != "$BEAD" ]; then
  refresh
  push
  gc bd update "$OWNER" --append-notes "Rework $BEAD landed on $BRANCH at $HEAD_OID." </dev/null >/dev/null \
    || echo "$PROG: the note that $BEAD landed did not reach $OWNER; the landing stands" >&2
  gc bd update "$BEAD" --if-assignee="$GC_AGENT" --status=closed --unset-metadata merge_result --unset-metadata rejection_reason \
    --set-metadata gc.work_outcome=shipped --set-metadata "gc.work_commit=$HEAD_OID" --set-metadata "gc.work_branch=$BRANCH" \
    --append-notes "Rework landed on $BRANCH at $HEAD_OID; $OWNER carries its PR." </dev/null >/dev/null \
    || stop "the rework landed on $BRANCH at $HEAD_OID, but $BEAD did not close; the next pass finds nothing to push and closes it"
  teardown
  echo "$PROG: closed $BEAD, landed on $BRANCH at $HEAD_OID for $OWNER"
  exit 0
fi

# An empty check set never un-gates a PR: it recovers the declared default.
# The none sentinel is stamped as itself.
CHECK_SET=$(var check_set)
case "$(printf '%s' "$CHECK_SET" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:],')" in
  '') CHECK_SET=$(printf '%s' "$VARS" | jq -r '[.vars[] | select(.name == "check_set")][0].default // ""') ;;
  none|off) CHECK_SET="none" ;;
esac
push
LC="$HERE/lifecycle.sh"
CURRENT=$(bead_meta merge_result)
if [ -n "$CURRENT" ]; then
  "$LC" transition "$BEAD" --to unanchored --expect "$CURRENT" --unset rejection_reason \
    || stop "$HEAD_OID is on $BRANCH, but $BEAD did not leave $CURRENT for the merge cadence's gate"
fi
if owner_pr; then
  "$LC" transition "$BEAD" --to pull_request --assignee "" --route "" --set "pr_url=$PR_URL" --set "pr_number=$PR_NUMBER" \
    --set "merged_target=$TARGET" --set "check_set=$CHECK_SET" --unset rejection_reason \
    || stop "$HEAD_OID is on $BRANCH, but $BEAD did not move to pull_request"
  echo "$PROG: $BEAD waits at pull_request on PR #$PR_NUMBER for the merge cadence"
else
  "$LC" transition "$BEAD" --to pre_open_gate --assignee "" --route "" --set "merged_target=$TARGET" \
    --set "check_set=$CHECK_SET" --unset rejection_reason \
    || stop "$HEAD_OID is on $BRANCH, but $BEAD did not move to pre_open_gate"
  echo "$PROG: $BEAD waits at pre_open_gate for the merge cadence to open its PR"
fi
teardown
exit 0
