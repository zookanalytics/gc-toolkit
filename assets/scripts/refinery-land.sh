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
# finds refused for branch protection promotes the bead to mr. Once the landing
# is recorded, a PR open from the target that a bead holds at pull_request has
# its title and body brought current at the target's new tip, so the body names
# the bead that landed. A refresh that does not take prints a line, and the
# landing's exit stands. mr runs the new path's publication
# (refinery-publish.sh) when pending_through_merge is "true". Otherwise it keeps
# the old path. The PR the bead's owner records open from the branch into the
# target, the bead's own or, for a rework child handed back, its anchor's, has
# its title and body brought current, its handoff naming the gates its check set
# resolves to at the head: the check set this step stamps on a bead that owns
# its PR, or the anchor's. A recorded PR that does not read stops the step
# before the push, since whether it is open there is unknown. Then the head is
# pushed under the lease on the commit the prep read. A bead that owns its PR is
# parked for the merge cadence, at pull_request when it records a PR open from
# its branch, else at pre_open_gate, with merged_target and check_set, through
# lifecycle.sh. On either path a rework child handed back lands on its anchor's
# branch and closes with its work record. A convoy's rebuild child whose convoy
# is not open on its branch, is no bead in the store, or is open there with no
# merge_result and assigned to nobody, lands on neither path: it is parked
# behind the gate refinery-rebuild-convoy-not-open before anything is pushed
# (refinery-lib.sh's refinery_owner).
#
# Every park files its human gate first, sets the merge_result, and keeps the
# bead with the refinery, so clearing the gate hands it back. A bead handed
# back still carries the park's merge_result, blocked or
# refused_false_completion, and the lifecycle machine lets either leave only
# for unanchored. So a direct landing takes the bead to unanchored, through
# lifecycle.sh, before it records the bead merged, and the old path takes it
# there from whatever merge_result it carries before it parks it for the
# cadence. The tree is removed once the step has done its part.
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

refinery_formula_vars || stop "the rig's formula vars did not read"

# park <key> <merge_result> <reason> <gate message>: the bead waits behind a
# human gate, still assigned to the refinery, and its tree is removed
# (refinery_park).
park() {
  refinery_park "$BEAD" "$1" "$2" "$3" "$4" "$HOME_DIR" || stop "the $1 gate on $BEAD did not land ($3)"
}
# unanchor: the bead leaves CURRENT, the merge_result it was read with, for
# unanchored, through lifecycle.sh, and CURRENT is cleared once it has.
LC="$HERE/lifecycle.sh"
CURRENT=$(bead_meta merge_result)
unanchor() {
  "$LC" transition "$BEAD" --to unanchored --expect "$CURRENT" --unset rejection_reason || return 1
  CURRENT=""
}
REPO=$(origin_repo "$HOME_DIR") || REPO=""
# owner_pr <head> <base>: the PR the owner records, PR_RECORDED, read from
# GitHub into PR_URL and PR_NUMBER and held in PR_ROW, when it is open from
# <head> into <base>. 0 when it is open there. 1 when the owner records no PR,
# or GitHub answers that the one it records is not open from <head> into
# <base>, or that the repository has no such PR, which refinery-publish.sh reads
# by the same words. 2 when the view did not answer, so whether the PR is open
# there is unknown.
owner_pr() {
  local err
  PR_URL=""; PR_NUMBER=""; PR_ROW=""
  PR_RECORDED=$(row_meta "$OWNER_ROW" existing_pr)
  [ -n "$PR_RECORDED" ] || PR_RECORDED=$(row_meta "$OWNER_ROW" pr_url)
  [ -n "$PR_RECORDED" ] || PR_RECORDED=$(row_meta "$OWNER_ROW" pr_number)
  [ -n "$PR_RECORDED" ] || return 1
  [ -n "$REPO" ] || return 2
  err=$(mktemp "${TMPDIR:-/tmp}/refinery-land.XXXXXX") || return 2
  if ! PR_ROW=$(gh pr view "$PR_RECORDED" --repo "$REPO" --json number,url,state,headRefName,baseRefName,title,body </dev/null 2>"$err"); then
    PR_ROW=""
    case "$(cat "$err")" in
      *"Could not resolve to a PullRequest"*|*"no pull requests found"*|*"Not Found"*) rm -f "$err"; return 1 ;;
    esac
    rm -f "$err"
    return 2
  fi
  rm -f "$err"
  printf '%s' "$PR_ROW" | jq -e 'type == "object" and (.state | type == "string")' >/dev/null 2>&1 || { PR_ROW=""; return 2; }
  printf '%s' "$PR_ROW" | jq -e --arg b "$1" --arg t "$2" '.state == "OPEN" and .headRefName == $b and .baseRefName == $t' >/dev/null 2>&1 || return 1
  PR_URL=$(printf '%s' "$PR_ROW" | jq -r '.url // ""')
  PR_NUMBER=$(printf '%s' "$PR_ROW" | jq -r '(.number // "") | tostring')
  [ -n "$PR_URL" ] && [ -n "$PR_NUMBER" ] || { PR_ROW=""; return 2; }
}
# refresh <check_set>: bring the open PR owner_pr read, in PR_ROW, current with
# the owner at HEAD_OID, its title and body. The body's handoff names the gates
# <check_set> resolves to at that head, resolved as pr-open.sh resolves them
# when it opens the PR, in the refinery's own repository, which holds the head.
# Non-zero, with a line on stderr, when the gates do not resolve, the title and
# body do not compose or the edit does not take. The mr path refreshes at the
# prepared head before it pushes and stops on a failure, so the head is never
# pushed under a stale body: once the owner waits at pull_request, no cadence
# pass edits its PR's title or body.
refresh() {
  local gctk gates out title live moved body published edit=() rc=0
  gctk=$(gctk_path) || { echo "$PROG: no gctk binary composes PR #$PR_NUMBER's title and body" >&2; return 1; }
  gates=$(cd "$HOME_DIR" && "$HERE/review-checks.sh" --resolve --check-set "$1" --through open-as-draft --with-phase --at "$HEAD_OID") \
    || { echo "$PROG: the gates of check set '$1' did not resolve at $HEAD_OID, so PR #$PR_NUMBER's body cannot name them" >&2; return 1; }
  published=$(mktemp "${TMPDIR:-/tmp}/refinery-land.XXXXXX") || return 1
  body=$(mktemp "${TMPDIR:-/tmp}/refinery-land.XXXXXX") || { rm -f "$published"; return 1; }
  printf '%s' "$PR_ROW" | jq -j '.body // ""' > "$published"
  if out=$("$gctk" pr compose "$OWNER" --head "$HEAD_OID" --gates "$gates" --body-file "$published" </dev/null); then
    title=$(printf '%s' "$out" | jq -r '.title // ""')
    moved=$(printf '%s' "$out" | jq -r 'if .summary == "written" or .branch_beads == "written" then "yes" else "" end')
    printf '%s' "$out" | jq -j '.body // ""' > "$body"
    live=$(printf '%s' "$PR_ROW" | jq -r '.title // ""')
    [ -z "$title" ] || [ "$(printf '%s' "$title" | tr -s '[:space:]' ' ')" = "$(printf '%s' "$live" | tr -s '[:space:]' ' ')" ] || edit+=(--title "$title")
    [ -z "$moved" ] || [ ! -s "$body" ] || edit+=(--body-file "$body")
    if [ "${#edit[@]}" -gt 0 ] && ! gh pr edit "$PR_NUMBER" --repo "$REPO" "${edit[@]}" </dev/null >/dev/null; then
      echo "$PROG: PR #$PR_NUMBER's title and body did not take" >&2
      rc=1
    fi
  else
    echo "$PROG: PR #$PR_NUMBER's title and body did not compose from $OWNER" >&2
    rc=1
  fi
  rm -f "$published" "$body"
  return "$rc"
}
# refresh_target_pr: once a direct landing is recorded, the PR open from TARGET
# that a bead holds at pull_request, which no later pass edits, is brought
# current with that bead at TARGET's new tip, so its body names the bead that
# landed. Its body can name the bead only once the landing records it merged,
# so the refresh runs after the push, and the landing stands whatever the
# refresh does: one that does not take prints a line, and the exit is the
# landing's. A bead the new path's pending record holds is not at pull_request:
# the landing order hands it back to the refinery once its PR's head moves, and
# the refinery composes its PR again.
refresh_target_pr() {
  local rows base
  rows=$(bd_json list ${GC_RIG:+--rig="$GC_RIG"} --metadata-field "branch=$TARGET" --metadata-field merge_result=pull_request \
    --status=open --limit=0) || rows=""
  if ! printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$PROG: the beads at pull_request on $TARGET did not list, so no PR open from it was brought current with $BEAD; the landing stands" >&2
    return 0
  fi
  OWNER=$(printf '%s' "$rows" | jq -r '[ .[] | select(((.metadata.anchor_bead // "") | tostring) as $a | $a == "" or $a == .id) ]
    | sort_by(.created_at // .id) | .[0].id // empty')
  [ -n "$OWNER" ] || return 0
  OWNER_ROW=$(printf '%s' "$rows" | jq -c --arg o "$OWNER" '[ .[] | select(.id == $o) ]')
  base=$(row_meta "$OWNER_ROW" merged_target)
  [ -n "$base" ] || base=$(row_meta "$OWNER_ROW" target)
  [ -n "$base" ] || base="$DEFAULT_BRANCH"
  owner_pr "$TARGET" "$base"
  case "$?" in
    0) ;;
    1) return 0 ;;
    *) echo "$PROG: PR $PR_RECORDED, which $OWNER records, did not read, so it was not brought current with $BEAD, which landed on $TARGET; the landing stands" >&2
       return 0 ;;
  esac
  if ! git -C "$HOME_DIR" fetch --no-tags origin "+refs/heads/$TARGET:refs/remotes/origin/$TARGET" >/dev/null 2>&1 \
     || ! HEAD_OID=$(git -C "$HOME_DIR" rev-parse --verify -q "refs/remotes/origin/$TARGET"); then
    echo "$PROG: origin/$TARGET did not read after $BEAD landed on it, so PR #$PR_NUMBER was not brought current; the landing stands" >&2
    return 0
  fi
  refresh "$(row_meta "$OWNER_ROW" check_set)" \
    || echo "$PROG: PR #$PR_NUMBER, open from $TARGET, does not name $BEAD, which landed on it; the landing stands" >&2
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
  # A bead handed back from a park leaves it for unanchored, the one state the
  # machine lets either park leave for, before the landing records it merged.
  case "$CURRENT" in
    blocked|refused_false_completion)
      unanchor || stop "$BEAD did not leave $CURRENT for its direct landing, so nothing landed" ;;
  esac
  DIRECT=(--work "$BEAD" --branch "$BRANCH" --target "$TARGET")
  [ "$(refinery_formula_var delete_merged_branches)" != true ] || DIRECT+=(--delete-branch)
  "$HERE/direct-merge-push.sh" "${DIRECT[@]}"
  case "$?" in
    0) refresh_target_pr; teardown; exit 0 ;;
    3) STRATEGY=mr ;;
    4) teardown; echo "$PROG: origin/$TARGET moved after $BEAD was prepared, so nothing landed; the next pass prepares it again"; exit 6 ;;
    *) stop "direct-merge-push.sh landed nothing it could record (its output above says what)" ;;
  esac
fi

if [ "$(refinery_formula_var pending_through_merge)" = true ]; then
  "$HERE/refinery-publish.sh" --bead "$BEAD"
  RC=$?
  case "$RC" in 0|4|6) teardown; exit "$RC" ;; *) exit 1 ;; esac
fi

# The old path, while pending_through_merge is unset.
refinery_owner "$BEAD" "$BRANCH"
case "$?" in
  0) ;;
  3) park refinery-rebuild-convoy-not-open blocked "the rebuild of $(bead_meta anchor_bead) has no bead on $BRANCH to carry its PR" "$OWNER_REFUSED" ;;
  *) stop "the bead whose PR $BRANCH lands on cannot be told" ;;
esac
push() {
  "$HERE/branch-push.sh" --repo "$TREE" --branch "$BRANCH" --head "$HEAD_OID" --from "$READ" >&2
  case "$?" in
    0) ;;
    3) teardown; echo "$PROG: $BRANCH moved on origin after the prep read $READ there, so nothing was pushed; the next pass prepares it again"; exit 6 ;;
    *) stop "the push of $HEAD_OID onto $BRANCH did not land" ;;
  esac
}

if [ "$OWNER" != "$BEAD" ]; then
  owner_pr "$BRANCH" "$TARGET"
  case "$?" in
    0) refresh "$(row_meta "$OWNER_ROW" check_set)" \
         || stop "PR #$PR_NUMBER is not current with $OWNER, so the head is not pushed under a stale body" ;;
    1) ;;
    *) stop "PR $PR_RECORDED, which $OWNER records, did not read, so the head is not pushed under a title and body nobody brought current" ;;
  esac
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
CHECK_SET=$(refinery_formula_var check_set)
case "$(printf '%s' "$CHECK_SET" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:],')" in
  '') CHECK_SET=$(refinery_formula_var --default check_set) ;;
  none|off) CHECK_SET="none" ;;
esac
OWNS_PR=""
owner_pr "$BRANCH" "$TARGET"
case "$?" in
  0) OWNS_PR=1
     refresh "$CHECK_SET" || stop "PR #$PR_NUMBER is not current with $BEAD, so the head is not pushed under a stale body" ;;
  1) ;;
  *) stop "PR $PR_RECORDED, which $BEAD records, did not read, so the head is not pushed under a title and body nobody brought current" ;;
esac
push
if [ -n "$CURRENT" ]; then
  unanchor || stop "$HEAD_OID is on $BRANCH, but $BEAD did not leave $CURRENT for the merge cadence's gate"
fi
if [ -n "$OWNS_PR" ]; then
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
