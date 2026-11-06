#!/usr/bin/env bash
# pr-sitting-comment.sh — the comment on a subject's PR that shows a visit. It
# is a view of the visit's own bead, the conversation, and every value it shows
# is that bead's value, word for word. One comment per conversation, found by a
# hidden marker keyed to the conversation's id, <!-- gc:sitting:<task> -->.
#
# While the conversation is open, the comment names the visit and the bead it
# is on, the conversation's id and its subject's, and its topic, which is the
# conversation's title. Once the conversation reads closed, those lines stay as
# they were, and the conclusion and the actions follow them. The conclusion is
# the hand-back last recorded on the conversation (gc.handback), the text the
# operator's tab prints when a sitting ends. The actions are the conversation's
# comments, oldest first, which the sitting, the sign-off and a dismiss write
# as they act. An empty one reads "none recorded" or "none".
#
# It is best effort and never blocks a visit: a missing tool, a caller outside
# a checkout of the subject's rig, a subject with no PR, a PR in another
# repository, or a read or a gh call that fails all exit 0, having changed
# nothing on the PR.
#
# Usage:
#   pr-sitting-comment.sh post --sitting <task> --topic <text>
#   pr-sitting-comment.sh refresh --sitting <task>
#
#   post:    draw the comment, posting it when the PR has none, once the
#            conversation's title reads <text>, the topic its sitting has just
#            written there. Until it reads back, the title is still the words
#            the conversation was opened with, so nothing is posted.
#            converse-prep's title step runs it after the premise re-check, so
#            a conversation that closes before then posts nothing.
#   refresh: draw the comment again after a write that changes what it shows,
#            and leave a PR alone when no comment carries this conversation's
#            marker. The sign-off, a dismiss and the premise re-check's close
#            run it once the conversation reads closed, and gc-helm.sh handback
#            once it records a hand-back on a closed conversation.
#
# The repository every gh call is pinned to is the origin of the checkout the
# caller runs in. A sitting runs in a worktree of its subject's rig, and dismiss
# runs this from the subject's rig checkout. A recorded pr_url must name that
# repository, so a PR the subject records on another repository is left alone.
set -u

PROG=pr-sitting-comment
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# The single writer of the city's PR posts: the comment is posted and edited
# through it so every shape of it carries the city's mark.
PR_POST="$HERE/pr-post.sh"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
# The gh REST payloads escape newlines as \n and need no scrub, and the comment
# body must keep its newlines, so it is read UNSCRUBBED below.
# One line, trimmed, for comparing a title with the topic a caller wrote there.
oneline() { printf '%s' "${1:-}" | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ *//; s/ *$//'; }

MODE="${1:-}"
case "$MODE" in post|refresh) shift ;; *) echo "$PROG: first argument must be 'post' or 'refresh'" >&2; exit 2 ;; esac

SITTING=""; TOPIC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sitting)  shift; [ $# -gt 0 ] || { echo "$PROG: --sitting needs a value" >&2; exit 2; }; SITTING="$1" ;;
    --topic)    shift; [ $# -gt 0 ] || { echo "$PROG: --topic needs a value" >&2; exit 2; }; TOPIC="$1" ;;
    -h|--help)  sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "$PROG: unknown flag '$1'" >&2; exit 2 ;;
    *)  echo "$PROG: unexpected argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$SITTING" ] || { echo "$PROG: --sitting is required" >&2; exit 2; }
TOPIC=$(oneline "$TOPIC")
if [ "$MODE" = post ]; then
  [ -n "$TOPIC" ] || { echo "$PROG: post needs --topic <text>, the topic just written as the conversation's title" >&2; exit 2; }
else
  [ -z "$TOPIC" ] || { echo "$PROG: refresh takes no --topic: the comment shows the conversation's title" >&2; exit 2; }
fi

# From here on every exit is 0: a comment must not break a sitting's prep or its close.
for t in gh gc jq git; do command -v "$t" >/dev/null 2>&1 || exit 0; done
# shellcheck source=conversation.sh
. "$HERE/conversation.sh" 2>/dev/null || { echo "$PROG: cannot source conversation.sh from $HERE; nothing posted" >&2; exit 0; }

# The conversation's row: its title, status and hand-back, and its tracks edge,
# which names the subject. The listing row carries the edges in the shape the
# one definition of a conversation reads.
CONV_ROW=$(gc bd list --id "$SITTING" --all --json 2>/dev/null | grep -av '^gc bd:' | scrub \
  | jq -c --arg c "$SITTING" 'if type == "array" then (map(objects | select((.id // "") == $c)) | first // empty) else empty end' 2>/dev/null)
if [ -z "$CONV_ROW" ]; then
  echo "$PROG: could not read conversation $SITTING; nothing posted" >&2
  exit 0
fi
if ! printf '%s' "$CONV_ROW" | jq -e "$CONVERSATION_JQ"'conversation' >/dev/null 2>&1; then
  echo "$PROG: $SITTING is not a conversation (a task that tracks one bead); nothing posted" >&2
  exit 0
fi
SUBJECT=$(printf '%s' "$CONV_ROW" | jq -r "$CONVERSATION_JQ"'conversation_subjects[0]')
TITLE=$(printf '%s' "$CONV_ROW" | jq -r '(.title // "") | tostring | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "")')
CLOSED=""
[ "$(printf '%s' "$CONV_ROW" | jq -r '(.status // "") | tostring | ascii_downcase')" = closed ] && CLOSED=yes
if [ "$MODE" = post ] && [ "$(oneline "$TITLE")" != "$TOPIC" ]; then
  echo "$PROG: the title of $SITTING does not read back as the topic '$TOPIC', so it may still be the words the conversation was opened with; nothing posted" >&2
  exit 0
fi

# The subject's PR: pr_number, else the integer after /pull/ in pr_url. Same
# read converse-pr-conversation.sh uses.
SUBJ_JSON=$(gc bd show "$SUBJECT" --json 2>/dev/null | grep -av '^gc bd:' | scrub)
PR=$(printf '%s' "$SUBJ_JSON" | jq -r '.[0].metadata as $m | ($m.pr_number // "" | tostring) as $n | if $n != "" then $n else (($m.pr_url // "") | split("/pull/") | if length > 1 then ((.[1] | capture("^(?<d>[0-9]+)") | .d) // "") else "" end) end' 2>/dev/null || true)
case "$PR" in ''|*[!0-9]*) exit 0 ;; esac   # no PR, or non-numeric — nothing to comment on

# The url -> owner/repo derivation pr-open.sh uses, on the caller's checkout.
ORIGIN_HOST=""; ORIGIN_REPO=""
u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
[ -n "$ORIGIN_REPO" ] || { echo "$PROG: this checkout has no GitHub origin, so the repository of $SUBJECT's PR is unknown; nothing posted" >&2; exit 0; }
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"

# Where a pr_url is recorded, the PR must live in that origin before we post.
PR_URL=$(printf '%s' "$SUBJ_JSON" | jq -r '.[0].metadata.pr_url // ""' 2>/dev/null || true)
if [ -n "$PR_URL" ]; then
  got=$(printf '%s\n' "$PR_URL" | grep -Eo '[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+/pull/[0-9]+' | tail -1 \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p')
  if [ -n "$got" ] && [ "$got" != "$ORIGIN_REPO_Q" ]; then
    echo "$PROG: $SUBJECT PR#$PR lives in '$got', not '$ORIGIN_REPO_Q'; nothing posted" >&2
    exit 0
  fi
fi

# The actions are the conversation's comments, shown only once it has closed. A
# listing that does not read could hide one, so the comment stays as it is.
ACTIONS='[]'
if [ -n "$CLOSED" ]; then
  ACTIONS=$(gc bd comments "$SITTING" --json 2>/dev/null | grep -av '^gc bd:' | scrub \
    | jq -c 'if type == "array" then [ .[] | objects ] elif . == null then [] else error("unread") end' 2>/dev/null) || ACTIONS=""
  if [ -z "$ACTIONS" ]; then
    echo "$PROG: could not read the comments on $SITTING, which are its actions; the comment on PR#$PR is left as it is" >&2
    exit 0
  fi
fi

# Compose the body. Both shapes carry the marker so the next call finds it, and
# the ended shape keeps every line of the open one and adds to them.
MARKER="<!-- gc:sitting:$SITTING -->"
BODY="$MARKER"$'\n'"### Visit $SITTING on $SUBJECT"$'\n'"Topic: $TITLE"$'\n'
if [ -n "$CLOSED" ]; then
  ENDED=$(printf '%s' "$CONV_ROW" | jq -r --argjson acts "$ACTIONS" '
    (((.metadata // {})["gc.handback"] // "") | tostring | sub("\\s+$"; "")) as $h
    | [ $acts | sort_by(.created_at // "")[] | (.text // "") | tostring | sub("\\s+$"; "") | select(test("\\S")) ] as $a
    | (if ($h | test("\\S"))
       then "Conclusion:\n" + ($h | split("\n") | map(sub("\\s+$"; "") | if . == "" then ">" else "> " + . end) | join("\n"))
       else "Conclusion: none recorded" end)
      + "\n\n"
      + (if ($a | length) == 0 then "Actions: none"
         else "Actions:\n" + ($a | map("- " + (split("\n") | map(sub("\\s+$"; "")) | join("\n  "))) | join("\n")) end)' 2>/dev/null)
  if [ -z "$ENDED" ]; then
    echo "$PROG: could not compose the conclusion and actions of $SITTING; the comment on PR#$PR is left as it is" >&2
    exit 0
  fi
  BODY="$BODY"$'\n'"$ENDED"$'\n'
fi

# The one comment carrying our marker, on the PR's issue-comment thread (what
# `gh pr comment` posts to). Unreadable is fail-safe: refresh has nothing to
# edit, and post skips rather than risk a duplicate.
COMMENTS=$(gh api "repos/$ORIGIN_REPO/issues/$PR/comments" --paginate --hostname "$ORIGIN_HOST" 2>/dev/null) || COMMENTS=""
if [ -z "$COMMENTS" ]; then
  echo "$PROG: could not read PR#$PR comments; nothing posted" >&2
  exit 0
fi
MATCH=$(printf '%s' "$COMMENTS" | jq -c --arg m "$MARKER" '[ .[]? | select(((.body // "") | tostring) | contains($m)) ] | first // empty' 2>/dev/null || true)
COMMENT_ID=""
[ -z "$MATCH" ] || COMMENT_ID=$(printf '%s' "$MATCH" | jq -r '.id // ""' 2>/dev/null || true)

if [ -z "$COMMENT_ID" ]; then
  # refresh is update-only: a conversation whose sitting never named its topic
  # has no comment, and the PR is left alone.
  [ "$MODE" = post ] || exit 0
  if "$PR_POST" comment --repo "$ORIGIN_REPO_Q" --pr "$PR" --body "$BODY" >/dev/null 2>&1; then
    echo "$PROG: posted the comment for $SITTING on PR#$PR"
  else
    echo "$PROG: could not post the comment for $SITTING on PR#$PR" >&2
  fi
  exit 0
fi

# An edit that would change nothing is skipped, so a redraw after a write the
# comment does not show leaves no edit behind.
if printf '%s' "$MATCH" | jq -e --arg b "$BODY" '
    def bare: tostring | sub("\\s*<!-- gc:city -->\\s*$"; "") | sub("\\s+$"; "");
    ((.body // "") | bare) == ($b | bare)' >/dev/null 2>&1; then
  echo "$PROG: the comment for $SITTING on PR#$PR already shows its bead"
  exit 0
fi
if "$PR_POST" edit --repo "$ORIGIN_REPO_Q" --comment "$COMMENT_ID" --body "$BODY" >/dev/null 2>&1; then
  echo "$PROG: updated the comment for $SITTING on PR#$PR"
else
  echo "$PROG: could not update comment $COMMENT_ID for $SITTING on PR#$PR" >&2
fi
exit 0
