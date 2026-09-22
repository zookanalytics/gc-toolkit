#!/usr/bin/env bash
# pr-visit-comment.sh — leave a reminder on a subject's PR that a visit
# happened. `engage` posts (or refreshes) a marked comment saying the visit is
# open; `close` edits that same comment in place to say it closed, with the
# sitting's summary. One comment per visit, found by a hidden marker keyed to
# the visit id.
#
# It is a reminder, so it never blocks the visit lifecycle: a missing gh, an
# unresolvable origin, a subject with no PR, or a gh call that errors all exit 0
# having done nothing. The subject carries the PR (pr_number / pr_url, written
# by pr-open.sh); a visit tracks the subject, and the subject's PR is where the
# comment lands.
#
# Usage:
#   pr-visit-comment.sh engage --visit <id> --subject <id> [--reason <text>]
#   pr-visit-comment.sh close  --visit <id> --subject <id> \
#       [--outcome <word>] [--summary <text>] [--actions <text>]
#
#   engage: upsert the marked comment into its "open" shape.
#   close:  edit the marked comment into its "closed" shape. UPDATE-ONLY — a
#           visit that never engaged has no comment, and close leaves the PR
#           alone. The reason is preserved from the comment engage wrote, so
#           close takes no --reason. --outcome/--summary/--actions default to the
#           visit's gc.outcome, gc.pr_visit_summary and gc.pr_visit_actions when
#           omitted, so a post-close caller need only name the visit and subject.
#           close refuses while the visit is still open, so it never says
#           "closed" ahead of the close.
set -u

PROG=pr-visit-comment

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
# The gh REST payloads escape newlines as \n and need no scrub, and the comment
# body must keep its newlines, so it is read UNSCRUBBED below.
# One line, trimmed: each comment field is a single line, which keeps the
# read-back of a preserved field (the reason, on close) exact.
oneline() { printf '%s' "${1:-}" | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ *//; s/ *$//'; }

MODE="${1:-}"
case "$MODE" in engage|close) shift ;; *) echo "$PROG: first argument must be 'engage' or 'close'" >&2; exit 2 ;; esac

VISIT=""; SUBJECT=""; REASON=""; OUTCOME=""; SUMMARY=""; ACTIONS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --visit)    shift; [ $# -gt 0 ] || { echo "$PROG: --visit needs a value" >&2; exit 2; }; VISIT="$1" ;;
    --subject)  shift; [ $# -gt 0 ] || { echo "$PROG: --subject needs a value" >&2; exit 2; }; SUBJECT="$1" ;;
    --reason)   shift; [ $# -gt 0 ] || { echo "$PROG: --reason needs a value" >&2; exit 2; }; REASON="$1" ;;
    --outcome)  shift; [ $# -gt 0 ] || { echo "$PROG: --outcome needs a value" >&2; exit 2; }; OUTCOME="$1" ;;
    --summary)  shift; [ $# -gt 0 ] || { echo "$PROG: --summary needs a value" >&2; exit 2; }; SUMMARY="$1" ;;
    --actions)  shift; [ $# -gt 0 ] || { echo "$PROG: --actions needs a value" >&2; exit 2; }; ACTIONS="$1" ;;
    -h|--help)  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "$PROG: unknown flag '$1'" >&2; exit 2 ;;
    *)  echo "$PROG: unexpected argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$VISIT" ]   || { echo "$PROG: --visit is required" >&2; exit 2; }
[ -n "$SUBJECT" ] || { echo "$PROG: --subject is required" >&2; exit 2; }

# From here on every exit is 0: a reminder must not break an engage or a close.
command -v gh >/dev/null 2>&1 || exit 0
command -v gc >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# The repository every gh call is pinned to — from the origin remote, never
# from gh's movable current repo. Same derivation pr-open.sh proves.
ORIGIN_HOST=""; ORIGIN_REPO=""; ORIGIN_REPO_Q=""
u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
[ -n "$ORIGIN_REPO" ] || { echo "$PROG: cannot resolve this checkout's origin repository; nothing posted" >&2; exit 0; }
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"

url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}
pr_url_canon() {
  printf '%s\n' "${1:-}" \
    | grep -Eo '[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+/pull/[0-9]+' | tail -1
}

# The subject's PR: pr_number, else the integer after /pull/ in pr_url. Same
# read converse-pr-conversation.sh uses.
SUBJ_JSON=$(gc bd show "$SUBJECT" --json 2>/dev/null | scrub)
PR=$(printf '%s' "$SUBJ_JSON" | jq -r '.[0].metadata as $m | ($m.pr_number // "" | tostring) as $n | if $n != "" then $n else (($m.pr_url // "") | split("/pull/") | if length > 1 then ((.[1] | capture("^(?<d>[0-9]+)") | .d) // "") else "" end) end' 2>/dev/null || true)
case "$PR" in ''|*[!0-9]*) exit 0 ;; esac   # no PR, or non-numeric — nothing to comment on

# Where a pr_url is recorded, the PR must live in our origin before we post.
PR_URL=$(printf '%s' "$SUBJ_JSON" | jq -r '.[0].metadata.pr_url // ""' 2>/dev/null || true)
if [ -n "$PR_URL" ]; then
  got=$(url_repo_q "$(pr_url_canon "$PR_URL")")
  if [ -n "$got" ] && [ "$got" != "$ORIGIN_REPO_Q" ]; then
    echo "$PROG: $SUBJECT PR#$PR lives in '$got', not '$ORIGIN_REPO_Q'; not ours — nothing posted" >&2
    exit 0
  fi
fi

# For a close, the summary, the actions, and the outcome word can be left to
# durable state: converse-signoff.sh stamps gc.pr_visit_summary and
# gc.pr_visit_actions on the visit before the close, and the visit's gc.outcome
# is the closing word. Reading them here lets the post-close writers
# (converse-settle's close step and converse-claim.sh's stranded-finish
# recovery) close the reminder without re-deriving the sitting. The same read
# refuses to mark the reminder closed while the visit is still open — a known
# non-closed status leaves the comment alone — because saying "closed" ahead of
# the close is the defect this waits on the close to avoid. An unreadable status
# is not proof of anything, so it proceeds: this is a best-effort reminder.
if [ "$MODE" = close ]; then
  VISIT_JSON=$(gc bd show "$VISIT" --json 2>/dev/null | scrub)
  VSTATUS=$(printf '%s' "$VISIT_JSON" | jq -r '.[0].status // ""' 2>/dev/null || true)
  case "$VSTATUS" in
    ""|closed) : ;;
    *) echo "$PROG: visit $VISIT reads '$VSTATUS', not closed; leaving its PR reminder open" >&2; exit 0 ;;
  esac
  [ -n "$OUTCOME" ] || OUTCOME=$(printf '%s' "$VISIT_JSON" | jq -r '.[0].metadata["gc.outcome"] // ""' 2>/dev/null || true)
  [ -n "$SUMMARY" ] || SUMMARY=$(printf '%s' "$VISIT_JSON" | jq -r '.[0].metadata["gc.pr_visit_summary"] // ""' 2>/dev/null || true)
  [ -n "$ACTIONS" ] || ACTIONS=$(printf '%s' "$VISIT_JSON" | jq -r '.[0].metadata["gc.pr_visit_actions"] // ""' 2>/dev/null || true)
fi

MARKER="<!-- gc:visit:$VISIT -->"

# The one comment carrying our marker, on the PR's issue-comment thread (what
# `gh pr comment` posts to). Unreadable is fail-safe: for close there is nothing
# to edit, and for engage we skip rather than risk a duplicate.
COMMENTS=$(gh api "repos/$ORIGIN_REPO/issues/$PR/comments" --paginate --hostname "$ORIGIN_HOST" 2>/dev/null) || COMMENTS=""
if [ -z "$COMMENTS" ]; then
  echo "$PROG: could not read PR#$PR comments; nothing posted" >&2
  exit 0
fi
MATCH=$(printf '%s' "$COMMENTS" | jq -c --arg m "$MARKER" '[ .[]? | select(((.body // "") | tostring) | contains($m)) ] | first // empty' 2>/dev/null || true)
COMMENT_ID=""; COMMENT_BODY=""
if [ -n "$MATCH" ]; then
  COMMENT_ID=$(printf '%s' "$MATCH" | jq -r '.id // ""' 2>/dev/null || true)
  COMMENT_BODY=$(printf '%s' "$MATCH" | jq -r '.body // ""' 2>/dev/null || true)
fi

REASON=$(oneline "$REASON")
OUTCOME=$(oneline "$OUTCOME")
SUMMARY=$(oneline "$SUMMARY")
ACTIONS=$(oneline "$ACTIONS")

if [ "$MODE" = close ]; then
  # UPDATE-ONLY: a visit that never engaged has no comment, and its close leaves
  # the PR alone.
  [ -n "$COMMENT_ID" ] || exit 0
  # Preserve the reason the engage wrote — one line, so this read-back is exact.
  REASON=$(printf '%s' "$COMMENT_BODY" | sed -n 's/^- Reason: //p' | head -1)
fi

# Compose the body. Both shapes carry the marker so the next call finds it.
BODY="$MARKER"$'\n'
if [ "$MODE" = engage ]; then
  BODY="$BODY### Visit $VISIT — open"$'\n'
else
  if [ -n "$OUTCOME" ]; then
    BODY="$BODY### Visit $VISIT — closed ($OUTCOME)"$'\n'
  else
    BODY="$BODY### Visit $VISIT — closed"$'\n'
  fi
fi
BODY="$BODY- Subject: $SUBJECT"$'\n'
[ -n "$REASON" ]  && BODY="$BODY- Reason: $REASON"$'\n'
if [ "$MODE" = close ]; then
  [ -n "$SUMMARY" ] && BODY="$BODY- Summary: $SUMMARY"$'\n'
  [ -n "$ACTIONS" ] && BODY="$BODY- Actions Taken: $ACTIONS"$'\n'
fi

if [ -n "$COMMENT_ID" ]; then
  if gh api --method PATCH "repos/$ORIGIN_REPO/issues/comments/$COMMENT_ID" --hostname "$ORIGIN_HOST" -f body="$BODY" >/dev/null 2>&1; then
    echo "$PROG: updated visit comment on PR#$PR ($MODE)"
  else
    echo "$PROG: could not update visit comment $COMMENT_ID on PR#$PR" >&2
  fi
else
  # No comment yet. engage creates one; close already returned above.
  if gh pr comment "$PR" --repo "$ORIGIN_REPO_Q" --body "$BODY" >/dev/null 2>&1; then
    echo "$PROG: posted visit comment on PR#$PR"
  else
    echo "$PROG: could not post visit comment on PR#$PR" >&2
  fi
fi
exit 0
