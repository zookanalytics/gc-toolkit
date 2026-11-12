#!/usr/bin/env bash
# refinery-publish.sh — the refinery's mr step on a rig on the new path
# (pending_through_merge): publish the prepared head on its PR and record the
# PR as pending until its merge is verified.
#
#   refinery-publish.sh --bead <id>
#
# The bead is the one this iteration prepared, assigned to this refinery
# ($GC_AGENT), and the refinery's tree for it must hold its branch
# (refinery-lib.sh). The PR is its owner's: the bead itself, or for a rework
# child handed back, the bead whose PR its work lands on (refinery_owner).
#
# The PR the step takes is one the owner records (existing_pr, else pr_url,
# else pr_number), or, when it records none, the PR open on GitHub from the
# branch into the target, which it adopts. GitHub keeps one open PR per branch
# and base, so one branch never gets a second. It takes a PR only when the
# city's account opened it: its author is the login the city's gh acts as
# (pr-post.sh acting-login), matched exactly. A PR another account opened is
# never edited or pushed onto, and no second PR is opened beside it: the bead
# is parked behind a human gate keyed refinery-pr-not-city-opened that names
# the PR and its author. A recorded PR that is not open, or not from the
# branch into the target in the rig's own repository, parks the bead behind
# the gate refinery-invalid-existing-pr. Each park sets merge_result=blocked and
# keeps the bead with the refinery, so clearing the gate hands it back. A step
# that cannot read the PR's author or the city's login takes no PR, and the
# next pass tries again.
#
# The title and body are composed by `gctk pr compose` from the owner, at the
# prepared head. On a PR the step takes, it edits the title and body first,
# then pushes the head, so a review started at that head reads the current
# body. With no PR open, it pushes the head and opens the PR as a draft with
# them. Every push goes under the lease on the commit the prep read on the
# branch (branch-push.sh), so a push someone made after the prep is never
# overwritten: the step stops, and the next pass prepares the branch again.
# The PR's ready transitions are the review loop's, so the step records no
# opened_as_draft.
#
# It then writes the owner's pending record with `gctk pr record`, which takes
# the store's record lock and writes nothing on an owner that closed or left the
# refinery first. Such an owner keeps its state, and the step names the PR in a
# note on it. A rework child handed back closes as landed on its branch, with
# its work record, once the head is pushed.
#
# Exit: 0 published and recorded, or published on an owner that refused the
#         record, which names the PR in its notes
#       1 nothing recorded, and the work stays with the refinery to retry; the
#         output says what landed, if anything
#       2 usage
#       4 the bead is parked behind a human gate
#       6 the branch moved after the prep, so nothing was pushed; the next pass
#         prepares it again
set -uo pipefail

PROG="refinery-publish"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=gctk-resolve.sh
. "$HERE/gctk-resolve.sh" || { echo "$PROG: cannot source gctk-resolve.sh beside this script" >&2; exit 1; }

PR_FIELDS="number,url,state,headRefName,baseRefName,headRepository,headRepositoryOwner,isCrossRepository,author,title,body"
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

HOME_DIR=$(refinery_home) || stop "the refinery's own worktree is unknown"
refinery_bead "$BEAD" || stop "$BEAD did not read"
[ -n "${GC_AGENT:-}" ] && [ "$(bead_field assignee)" = "$GC_AGENT" ] \
  || stop "$BEAD is assigned to $(bead_field assignee), not this refinery (${GC_AGENT:-GC_AGENT unset})"
BRANCH=$(bead_meta branch)
refinery_require "$HOME_DIR" "$BEAD" "$BRANCH" || stop "this iteration did not prepare $BEAD"
HEAD_OID="$PREP_HEAD"; READ="$PREP_READ"; TREE="$PREP_TREE"
TARGET=$(bead_meta target)
[ -n "$TARGET" ] || TARGET=$(refinery_default_branch "$HOME_DIR") || stop "$BEAD carries no target, and origin/HEAD names no default branch"
refinery_owner "$BEAD" "$BRANCH" || stop "the bead whose PR $BRANCH lands on cannot be told"
REPO=$(origin_repo "$HOME_DIR") || stop "the rig's origin is not a github.com repository"
gctk=$(gctk_path) || stop "no gctk binary to compose and record the PR with"
PR_POST="$HERE/pr-post.sh"

# park <key> <reason>: the bead waits behind a human gate, with
# merge_result=blocked, still assigned to the refinery, so clearing the gate
# hands it back. The gate is filed first, and a gate that does not land parks
# nothing.
park() {
  "$HERE/human-gate.sh" --subject "$BEAD" --key "$1" --message "$2" >/dev/null \
    || stop "the $1 gate on $BEAD did not land ($2)"
  gc bd update "$BEAD" --if-assignee="$GC_AGENT" --set-metadata merge_result=blocked --set-metadata "blocked_reason=$2" </dev/null >/dev/null \
    || echo "$PROG: the $1 gate holds $BEAD, but merge_result=blocked did not land on it" >&2
  echo "$PROG: parked $BEAD behind its $1 gate: $2"
  exit 4
}
owner_meta() { row_meta "$OWNER_ROW" "$1"; }
# pr_repo <url>: the owner/repo a PR's URL names.
pr_repo() { printf '%s' "$1" | sed -n 's#^https://github\.com/\([^/]*/[^/]*\)/pull/[0-9][0-9]*/*$#\1#p'; }
# take <row>: hold the PR a view or listing answered, in PR_* — 0 when it is
# open from the branch into the target in the rig's own repository, 1 with
# PR_WRONG saying what differs otherwise.
take() {
  PR_URL=$(printf '%s' "$1" | jq -r '.url // ""')
  PR_NUMBER=$(printf '%s' "$1" | jq -r '(.number // "") | tostring')
  PR_AUTHOR=$(printf '%s' "$1" | jq -r '(.author.login // "") | tostring')
  PR_TITLE=$(printf '%s' "$1" | jq -r '.title // ""')
  PR_BODY=$(printf '%s' "$1" | jq -r '.body // ""')
  local state head base hrepo cross
  state=$(printf '%s' "$1" | jq -r '.state // ""')
  head=$(printf '%s' "$1" | jq -r '.headRefName // ""')
  base=$(printf '%s' "$1" | jq -r '.baseRefName // ""')
  hrepo=$(printf '%s' "$1" | jq -r '((.headRepositoryOwner.login // "") + "/" + (.headRepository.name // ""))')
  cross=$(printf '%s' "$1" | jq -r '(.isCrossRepository // "") | tostring')
  PR_WRONG=""
  if [ "$(pr_repo "$PR_URL")" != "$REPO" ]; then PR_WRONG="is in $(pr_repo "$PR_URL"), not $REPO"
  elif [ "$state" != OPEN ]; then PR_WRONG="is ${state:-of no state}, not open"
  elif [ "$head" != "$BRANCH" ]; then PR_WRONG="is opened from $head, not $BRANCH"
  elif [ "$base" != "$TARGET" ]; then PR_WRONG="targets $base, not $TARGET"
  elif [ "$hrepo" != "$REPO" ] || [ "$cross" = true ]; then PR_WRONG="has its head in $hrepo, not $REPO"
  fi
  [ -z "$PR_WRONG" ]
}
# city_opened: 0 when the city's account opened the PR held in PR_*. A login
# that does not read takes no PR.
LOGIN=""
city_opened() {
  [ -n "$LOGIN" ] || LOGIN=$("$PR_POST" acting-login --host github.com 2>/dev/null) || LOGIN=""
  [ -n "$LOGIN" ] || stop "the login the city's gh acts as did not read, so no PR is taken"
  [ -n "$PR_AUTHOR" ] || stop "the author of PR #$PR_NUMBER did not read, so it is not taken"
  [ "$PR_AUTHOR" = "$LOGIN" ]
}
not_city_opened() {
  park refinery-pr-not-city-opened "PR #$PR_NUMBER ($PR_URL), open from $BRANCH into $TARGET, was opened by $PR_AUTHOR, not by the city's account $LOGIN, so the city takes it into no merge of its own: it edits nothing on it, pushes nothing onto its branch and opens no second PR beside it. Close that PR, then clear this gate, and the refinery opens the city's own; or stand $BEAD down instead: run $HERE/stand-down.sh $BEAD --key refinery-pr-not-city-opened --ruling '<why>'."
}

BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/refinery-publish.XXXXXX") || stop "cannot make a file for the PR's body"
PUBLISHED=$(mktemp "${TMPDIR:-/tmp}/refinery-publish.XXXXXX") || stop "cannot make a file for the PR's body"
ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/refinery-publish.XXXXXX") || stop "cannot make a file for gh's errors"
trap 'rm -f "$BODY_FILE" "$PUBLISHED" "$ERR_FILE"' EXIT

# The PR to take: the one the owner records, else the one open on the branch.
RECORDED=$(owner_meta existing_pr)
[ -n "$RECORDED" ] || RECORDED=$(owner_meta pr_url)
[ -n "$RECORDED" ] || RECORDED=$(owner_meta pr_number)
PR_URL=""
if [ -n "$RECORDED" ]; then
  # A URL names its own repository, which take() then checks; a bare number
  # is read in the rig's.
  VIEW_REPO=(--repo "$REPO")
  case "$RECORDED" in http://*|https://*) VIEW_REPO=() ;; esac
  if ! VIEW=$(gh pr view "$RECORDED" ${VIEW_REPO[@]+"${VIEW_REPO[@]}"} --json "$PR_FIELDS" </dev/null 2>"$ERR_FILE"); then
    VIEW=$(cat "$ERR_FILE")
    case "$VIEW" in
      *"Could not resolve to a PullRequest"*|*"no pull requests found"*|*"Not Found"*)
        park refinery-invalid-existing-pr "$OWNER records PR $RECORDED, which $REPO does not have. Give $OWNER the PR its branch $BRANCH is open on into $TARGET, or clear the record, then clear this gate." ;;
    esac
    stop "PR $RECORDED did not read: $(printf '%s' "$VIEW" | tr -s '[:space:]' ' ')"
  fi
  take "$VIEW" || park refinery-invalid-existing-pr "$OWNER records PR #$PR_NUMBER ($PR_URL), which $PR_WRONG, so it is not reused. Give $OWNER the PR its branch $BRANCH is open on into $TARGET, or clear the record, then clear this gate."
  city_opened || not_city_opened
else
  LIST=$(gh pr list --repo "$REPO" --head "$BRANCH" --base "$TARGET" --state open --json "$PR_FIELDS" --limit 10 </dev/null 2>/dev/null) \
    || stop "the PRs open from $BRANCH into $TARGET did not list"
  printf '%s' "$LIST" | jq -e 'type == "array"' >/dev/null 2>&1 || stop "the PRs open from $BRANCH into $TARGET did not parse"
  ROW=$(printf '%s' "$LIST" | jq -c --arg b "$BRANCH" '[ .[] | select(.headRefName == $b) ] | .[0] // empty')
  if [ -n "$ROW" ]; then
    take "$ROW" || stop "the PR open from $BRANCH, #$PR_NUMBER, $PR_WRONG"
    city_opened || not_city_opened
    echo "$PROG: adopting PR #$PR_NUMBER, open from $BRANCH into $TARGET, which the city's account opened and $OWNER does not record"
  fi
fi

# compose [--body-file <file>]: the title and body the owner says its PR
# should carry at the prepared head, in TITLE and BODY_FILE, and in MOVED
# whether a section of a published body moved.
compose() {
  local out
  out=$("$gctk" pr compose "$OWNER" --head "$HEAD_OID" --gates '' "$@" </dev/null) || return 1
  TITLE=$(printf '%s' "$out" | jq -r '.title // ""')
  MOVED=$(printf '%s' "$out" | jq -r 'if .summary == "written" or .branch_beads == "written" then "yes" else "" end')
  printf '%s' "$out" | jq -j '.body // ""' > "$BODY_FILE"
  [ -n "$TITLE" ] && [ -s "$BODY_FILE" ]
}
push() {
  local rc
  "$HERE/branch-push.sh" --repo "$TREE" --branch "$BRANCH" --head "$HEAD_OID" --from "$READ" >&2
  rc=$?
  case "$rc" in
    0) ;;
    3) echo "$PROG: $BRANCH moved on origin after the prep read $READ there, so nothing was pushed; the next pass prepares it again" >&2; exit 6 ;;
    *) stop "the push of $HEAD_OID onto $BRANCH did not land (branch-push.sh exit $rc)" ;;
  esac
}

if [ -n "$PR_URL" ]; then
  printf '%s' "$PR_BODY" > "$PUBLISHED"
  compose --body-file "$PUBLISHED" || stop "the title and body of PR #$PR_NUMBER did not compose from $OWNER"
  EDIT=()
  [ "$(printf '%s' "$TITLE" | tr -s '[:space:]' ' ')" = "$(printf '%s' "$PR_TITLE" | tr -s '[:space:]' ' ')" ] || EDIT+=(--title "$TITLE")
  [ -z "$MOVED" ] || EDIT+=(--body-file "$BODY_FILE")
  if [ "${#EDIT[@]}" -gt 0 ]; then
    gh pr edit "$PR_NUMBER" --repo "$REPO" "${EDIT[@]}" </dev/null >/dev/null \
      || stop "the title and body of PR #$PR_NUMBER did not take, so the head is not pushed under a stale body"
  fi
  push
else
  compose || stop "the title and body of $OWNER's PR did not compose"
  push
  if ! CREATED=$(gh pr create --repo "$REPO" --base "$TARGET" --head "$BRANCH" --draft --title "$TITLE" --body-file "$BODY_FILE" </dev/null 2>/dev/null); then
    # A create that fails can still have opened the PR, or another writer
    # opened one first: the branch's open PR is read again before anything
    # else, and only one the city's account opened is taken.
    LIST=$(gh pr list --repo "$REPO" --head "$BRANCH" --base "$TARGET" --state open --json "$PR_FIELDS" --limit 10 </dev/null 2>/dev/null) || LIST=""
    ROW=$(printf '%s' "$LIST" | jq -c --arg b "$BRANCH" '[ .[]? | select(.headRefName == $b) ] | .[0] // empty' 2>/dev/null)
    [ -n "$ROW" ] || stop "$HEAD_OID is on $BRANCH, but no PR from it into $TARGET opened; the next pass opens one"
    take "$ROW" || stop "the PR open from $BRANCH, #$PR_NUMBER, $PR_WRONG"
    city_opened || not_city_opened
    CREATED="$PR_URL"
  fi
  PR_URL=$(printf '%s' "$CREATED" | grep -Eo 'https://github\.com/[^[:space:]]+/pull/[0-9]+' | tail -n 1)
  [ "$(pr_repo "$PR_URL")" = "$REPO" ] || stop "the PR create answered '$CREATED', which is no PR in $REPO"
  echo "$PROG: opened $PR_URL as a draft from $BRANCH into $TARGET for $OWNER"
fi

GC_RIG_ROOT="$HOME_DIR" "$gctk" pr record "$OWNER" --pr "$PR_URL" --head "$HEAD_OID" --target "$TARGET" --refinery "$GC_AGENT" </dev/null
RC=$?
case "$RC" in
  0) echo "$PROG: $OWNER records $PR_URL as pending at $HEAD_OID until its merge is verified on $TARGET" ;;
  3) gc bd update "$OWNER" --append-notes "Refinery: published $PR_URL from $BRANCH at $HEAD_OID, but $OWNER was closed or no longer the refinery's when the pending record was written, so it has none, and the landing order does not read the PR. It stays open until someone retires it." </dev/null >/dev/null \
       || echo "$PROG: the note naming $PR_URL did not land on $OWNER" >&2
     echo "$PROG: $OWNER refused the record (closed, or no longer the refinery's), so its notes name $PR_URL" ;;
  *) stop "$HEAD_OID is on $BRANCH and $PR_URL is open, but its pending record on $OWNER did not land (gctk pr record exit $RC); the next pass takes the PR and records it" ;;
esac

if [ "$OWNER" != "$BEAD" ]; then
  gc bd update "$BEAD" --if-assignee="$GC_AGENT" --status=closed --unset-metadata merge_result --unset-metadata rejection_reason \
    --set-metadata gc.work_outcome=shipped --set-metadata "gc.work_commit=$HEAD_OID" --set-metadata "gc.work_branch=$BRANCH" \
    --append-notes "Rework landed on $BRANCH at $HEAD_OID; $OWNER carries its PR, $PR_URL." </dev/null >/dev/null \
    || stop "the rework landed on $BRANCH at $HEAD_OID, but $BEAD did not close; the next pass finds nothing to push and closes it"
  echo "$PROG: closed $BEAD, landed on $BRANCH at $HEAD_OID for $OWNER"
fi
exit 0
