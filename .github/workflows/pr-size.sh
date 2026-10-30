#!/usr/bin/env bash
# pr-size.sh — keeps one comment on a gc-toolkit pull request current with the
# change's size: the section `tools/measure.sh --pr` prints from the merge base
# to the head, which rule 3 of docs/built-once-target.md asks each pull request
# to show. pr-size.yml runs it on each push to a pull request.
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
# is rewritten to say so, and none is posted where there was none.
#
# Usage: pr-size.sh --repo <host/owner/name> --pr <n> --base <commit> --head <commit>
#   --base is the tip of the branch the pull request merges into. It runs from
#   inside a checkout that holds --base, and fetches --head from origin when
#   the checkout lacks it.
#
# Exit: 0 the comment is current, or the merge base has no size to show; 1 the
# size could not be measured, or the comments could not be read or written;
# 2 usage.
set -uo pipefail

PROG=pr-size
MARK='<!-- gc-toolkit:pr-size -->'
NO_REVIEW='<!-- gc:no-review -->'
AUTHOR='github-actions[bot]'
PR_POST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/pr-post.sh"

usage() { echo "usage: $PROG --repo <host/owner/name> --pr <n> --base <commit> --head <commit>" >&2; exit 2; }
REPO_Q="" PR="" BASE="" HEAD=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --repo) REPO_Q=$2 ;;
    --pr) PR=$2 ;;
    --base) BASE=$2 ;;
    --head) HEAD=$2 ;;
    *) usage ;;
  esac
  shift 2
done
case "$PR" in ''|*[!0-9]*) usage ;; esac
case "$REPO_Q" in */*/*) ;; *) usage ;; esac
[ -n "$BASE" ] && [ -n "$HEAD" ] || usage
HOST=${REPO_Q%%/*} REPO=${REPO_Q#*/}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pr-size.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

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
} > "$TMP/body"

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
