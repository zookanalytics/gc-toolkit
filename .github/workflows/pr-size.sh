#!/usr/bin/env bash
# pr-size.sh — keeps one comment on a gc-toolkit pull request current with the
# change's size: the section `tools/measure.sh --pr` prints from the merge base
# to the head, which rule 3 of docs/built-once-target.md asks each pull request
# to show. Below the size the comment shows the suite's time, the section
# suite-time.sh reads from the tests run at the head. pr-size.yml runs this
# after a push to a pull request or a change of the branch it merges into, and
# when one of its tests runs passes or fails. The workflow's header says what
# starts each run.
#
# The tool and the deletion plan it reads are the merge base's, never the
# head's, so a change cannot edit either to hide what it adds. The tool runs
# from the merge base's blob, and it reads the plan at the merge base itself.
# The head is read only as git objects, and nothing from it runs. A merge base
# that carries no tools/measure.sh has no size to show.
#
# The comment opens with this script's mark, by which the next run finds it,
# and then the no-review mark (docs/not-for-review.md), so the city never reads
# it as review feedback. It is posted through assets/scripts/pr-post.sh, and
# only a comment the Actions bot wrote is rewritten. When the merge base has no
# size to show, or the size cannot be measured, a comment an earlier head left
# is rewritten to say so, and none is posted where there was none. A suite time
# that cannot be read is said in the comment and changes no exit.
#
# A run measures the pull request as it stands when the run starts. It reads
# the head and the branch the pull request merges into from the pull request
# itself, never from the event that started the run, because pr-size.yml's
# runs need not start in the order of their events. It writes only while both
# are still as it read them, since a push or a change of that branch starts a
# run of its own. pr-size.yml's concurrency group keeps two runs of one pull
# request from writing at once.
#
# Usage: pr-size.sh --repo <host/owner/name> --pr <n>
#   It runs from inside a checkout that holds the branch the pull request
#   merges into as refs/remotes/origin/<branch>, and fetches the head from
#   origin when the checkout lacks it.
#
# Exit: 0 the comment is current, the merge base has no size to show, or the
# pull request moved while the run measured it; 1 the size could not be
# measured, or the pull request or its comments could not be read or written;
# 2 usage.
set -uo pipefail

PROG=pr-size
MARK='<!-- gc-toolkit:pr-size -->'
NO_REVIEW='<!-- gc:no-review -->'
AUTHOR='github-actions[bot]'
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_POST="$(cd "$HERE/../.." && pwd)/assets/scripts/pr-post.sh"

usage() { echo "usage: $PROG --repo <host/owner/name> --pr <n>" >&2; exit 2; }
REPO_Q="" PR=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --repo) REPO_Q=$2 ;;
    --pr) PR=$2 ;;
    *) usage ;;
  esac
  shift 2
done
case "$PR" in ''|*[!0-9]*) usage ;; esac
case "$REPO_Q" in */*/*) ;; *) usage ;; esac
HOST=${REPO_Q%%/*} REPO=${REPO_Q#*/}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pr-size.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# pr_now: the pull request's head and the branch it merges into, with a space
# between, since a branch name holds no space. It fails when the read fails or
# lacks either.
pr_now() {
  local now
  now=$(gh api "repos/$REPO/pulls/$PR" --hostname "$HOST" | jq -r '"\(.head.sha // "") \(.base.ref // "")"') || return 1
  case "$now" in ' '*|*' ') return 1 ;; esac
  printf '%s' "$now"
}
NOW=$(pr_now) || { echo "$PROG: could not read PR#$PR's head and base, so nothing is posted" >&2; exit 1; }
HEAD=${NOW% *} BRANCH=${NOW#* }
BASE=refs/remotes/origin/$BRANCH

# A fork's head is on no branch the checkout fetched.
git cat-file -e "$HEAD^{commit}" 2>/dev/null \
  || git fetch --quiet --no-tags origin "$HEAD" 2>/dev/null || true

# 0 measured, into $TMP/section; 3 the merge base, MB, carries no tool; 1
# failed. A tool that fails returns 1 whatever its own exit, so 3 means only
# that the tool is missing.
MB=""
measure() {
  MB=$(git merge-base "$BASE" "$HEAD" 2>/dev/null) || return 1
  git cat-file -e "$MB:tools/measure.sh" 2>/dev/null || return 3
  git show "$MB:tools/measure.sh" > "$TMP/measure.sh" || return 1
  bash "$TMP/measure.sh" --pr "$MB" "$HEAD" > "$TMP/section" && [ -s "$TMP/section" ] || return 1
}
measure; RC=$?
[ "$RC" -ne 3 ] || echo "$PROG: the merge base of PR#$PR carries no tools/measure.sh, so it has no size to show"

SHORT=$(git rev-parse --short=12 "$HEAD" 2>/dev/null) || SHORT=${HEAD:0:12}
{
  printf '%s\n%s\n## Size\n\n' "$MARK" "$NO_REVIEW"
  if [ "$RC" -eq 0 ]; then
    cat "$TMP/section"
    printf '\nMeasured at head `%s`.\n' "$SHORT"
  elif [ "$RC" -eq 3 ]; then
    printf 'The size at head `%s` is not shown, because its merge base `%s` carries no `tools/measure.sh`.\n' \
      "$SHORT" "$(git rev-parse --short=12 "$MB")"
  else
    printf 'The size at head `%s` could not be measured.\n' "$SHORT"
    [ -z "${GITHUB_RUN_ID:-}" ] \
      || printf '\nThe run that tried: %s/%s/actions/runs/%s\n' "${GITHUB_SERVER_URL:-https://github.com}" "$REPO" "$GITHUB_RUN_ID"
  fi
  printf '\n## Suite time\n\n'
  if [ -n "$MB" ] && bash "$HERE/suite-time.sh" section --repo "$REPO_Q" --head "$HEAD" --merge-base "$MB" > "$TMP/time"; then
    cat "$TMP/time"
  else
    printf 'The suite'\''s time at head `%s` could not be read.\n' "$SHORT"
  fi
} > "$TMP/body"

# The pull request must still be as this run read it (see above).
AGAIN=$(pr_now) || { echo "$PROG: could not read PR#$PR's head and base again, so nothing is posted" >&2; exit 1; }
if [ "$AGAIN" != "$NOW" ]; then
  echo "$PROG: PR#$PR is now head ${AGAIN:0:12} into ${AGAIN#* }, so nothing is written for head $SHORT into $BRANCH"
  exit 0
fi

# The bot's own comment carrying the mark. A person's comment that quotes the
# mark is never rewritten.
COMMENTS=$(gh api --paginate "repos/$REPO/issues/$PR/comments" --hostname "$HOST") \
  && ID=$(printf '%s' "$COMMENTS" | jq -rs --arg m "$MARK" --arg a "$AUTHOR" \
       '[.[][]? | select(.user.login == $a and ((.body // "") | startswith($m)))] | first | .id // empty') \
  || { echo "$PROG: could not read PR#$PR's comments, so nothing is posted" >&2; exit 1; }

if [ -n "$ID" ]; then
  "$PR_POST" edit --repo "$REPO_Q" --comment "$ID" --body-file "$TMP/body" >/dev/null \
    || { echo "$PROG: could not rewrite comment $ID on PR#$PR" >&2; exit 1; }
  echo "$PROG: rewrote comment $ID on PR#$PR for head $SHORT"
elif [ "$RC" -eq 0 ]; then
  "$PR_POST" comment --repo "$REPO_Q" --pr "$PR" --body-file "$TMP/body" >/dev/null \
    || { echo "$PROG: could not post on PR#$PR" >&2; exit 1; }
  echo "$PROG: posted the size of PR#$PR at head $SHORT"
fi
[ "$RC" -ne 1 ] || { echo "$PROG: the size of PR#$PR at head $SHORT could not be measured" >&2; exit 1; }
