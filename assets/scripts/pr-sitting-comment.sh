#!/usr/bin/env bash
# pr-sitting-comment.sh — the comment on a subject's PR that a visit is
# discussing it. `topic` posts (or refreshes) a marked comment naming what the
# visit discusses; `close` edits that same comment in place to say what it
# discussed and the action taken. One comment per conversation, found by a
# hidden marker keyed to the conversation task's id, <!-- gc:sitting:<task> -->.
#
# It is a reminder, so it never blocks a sitting: a missing gh, an unresolvable
# origin, a subject with no PR, or a gh call that errors all exit 0 having done
# nothing. The subject carries the PR (pr_number / pr_url, written by
# pr-open.sh); a conversation tracks the subject, and the subject's PR is where
# the comment lands.
#
# Usage:
#   pr-sitting-comment.sh topic --sitting <task> --subject <id> --topic <text>
#   pr-sitting-comment.sh close --sitting <task> --subject <id> \
#       --outcome <word> [--summary <text>]
#
#   topic: upsert the marked comment into its open shape, with <text> as the
#          topic under discussion. converse-prep's title step runs it with the
#          topic it titles the session with, after the premise re-check, so a
#          conversation that closes before then posts nothing.
#   close: edit the marked comment into its ended shape: the topic it carries,
#          the action <word> names, then <text>, the sitting's one-line
#          outcome. UPDATE-ONLY — a conversation whose sitting named no topic
#          has no comment, and close leaves the PR alone. Its callers run it
#          once their own write reads back: the sign-off once the conversation
#          is closed or handed back to the operator's queue, dismiss once it is
#          closed, and the premise re-check once it closes the conversation.
#          <word> is one of:
#            rework        the ruling sent the PR back for rework
#            retired       the ruling retired the PR
#            accepted      the ruling took the subject's recommendation
#            ruled         a ruling that did nothing to the PR
#            handed back   cut short, back in the operator's queue undecided
#            dismissed     the operator dismissed the visit
#            moot, benign  the premise re-check closed the conversation
set -u

PROG=pr-sitting-comment
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# The single writer of the city's PR posts: the reminder is posted and edited
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
# One line, trimmed: each comment field is a single line.
oneline() { printf '%s' "${1:-}" | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ *//; s/ *$//'; }

MODE="${1:-}"
case "$MODE" in topic|close) shift ;; *) echo "$PROG: first argument must be 'topic' or 'close'" >&2; exit 2 ;; esac

SITTING=""; SUBJECT=""; TOPIC=""; OUTCOME=""; SUMMARY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sitting)  shift; [ $# -gt 0 ] || { echo "$PROG: --sitting needs a value" >&2; exit 2; }; SITTING="$1" ;;
    --subject)  shift; [ $# -gt 0 ] || { echo "$PROG: --subject needs a value" >&2; exit 2; }; SUBJECT="$1" ;;
    --topic)    shift; [ $# -gt 0 ] || { echo "$PROG: --topic needs a value" >&2; exit 2; }; TOPIC="$1" ;;
    --outcome)  shift; [ $# -gt 0 ] || { echo "$PROG: --outcome needs a value" >&2; exit 2; }; OUTCOME="$1" ;;
    --summary)  shift; [ $# -gt 0 ] || { echo "$PROG: --summary needs a value" >&2; exit 2; }; SUMMARY="$1" ;;
    -h|--help)  sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "$PROG: unknown flag '$1'" >&2; exit 2 ;;
    *)  echo "$PROG: unexpected argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$SITTING" ] || { echo "$PROG: --sitting is required" >&2; exit 2; }
[ -n "$SUBJECT" ] || { echo "$PROG: --subject is required" >&2; exit 2; }
TOPIC=$(oneline "$TOPIC")
SUMMARY=$(oneline "$SUMMARY")
# The action is said in these words only, so no caller's text stands in for it.
ACTION=""
if [ "$MODE" = topic ]; then
  [ -n "$TOPIC" ] || { echo "$PROG: topic needs --topic <text>" >&2; exit 2; }
  [ -z "$OUTCOME$SUMMARY" ] || { echo "$PROG: topic takes no --outcome or --summary; close does" >&2; exit 2; }
else
  [ -z "$TOPIC" ] || { echo "$PROG: close takes no --topic: it shows the one the comment carries" >&2; exit 2; }
  case "$OUTCOME" in
    rework)            ACTION="sent back for rework" ;;
    retired)           ACTION="retired" ;;
    accepted)          ACTION="its recommended work started" ;;
    ruled|moot|benign) ACTION="none" ;;
    "handed back")     ACTION="none; the visit went back to the operator's queue undecided" ;;
    dismissed)         ACTION="none; the visit was dismissed" ;;
    "") echo "$PROG: close needs --outcome <word>" >&2; exit 2 ;;
    *)  echo "$PROG: unknown --outcome '$OUTCOME': it takes rework, retired, accepted, ruled, handed back, dismissed, moot or benign" >&2; exit 2 ;;
  esac
fi

# From here on every exit is 0: a reminder must not break a sitting's prep or its close.
command -v gh >/dev/null 2>&1 || exit 0
command -v gc >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# The repository every gh call is pinned to — resolved from the SUBJECT's rig
# origin, never gh's movable current repo, and never the caller's cwd: dismiss
# is launched from the board, outside any rig checkout, where a cwd origin
# lookup resolves nothing and the reminder would silently never post. The rig
# map maps the subject's id prefix to its repo path; cwd is the fallback for a
# caller that already runs inside the subject's rig (a sitting, or the
# converse sign-off).
ORIGIN_HOST=""; ORIGIN_REPO=""; ORIGIN_REPO_Q=""
RIG_MAP=$("$HERE/rig-map.sh")
REPO_DIR=$(printf '%s' "$RIG_MAP" \
  | jq -r --arg p "${SUBJECT%%-*}" '.rigs[]? | objects | select(.prefix == $p) | .path' 2>/dev/null | head -n1)
if [ -n "$REPO_DIR" ] && [ -d "$REPO_DIR" ]; then
  u=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null | tr -d '[:space:]')
else
  u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
fi
# The url -> owner/repo derivation pr-open.sh uses.
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
[ -n "$ORIGIN_REPO" ] || { echo "$PROG: cannot resolve the subject's rig origin repository; nothing posted" >&2; exit 0; }
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

MARKER="<!-- gc:sitting:$SITTING -->"

# The one comment carrying our marker, on the PR's issue-comment thread (what
# `gh pr comment` posts to). Unreadable is fail-safe: for close there is nothing
# to edit, and for topic we skip rather than risk a duplicate.
COMMENTS=$(gh api "repos/$ORIGIN_REPO/issues/$PR/comments" --paginate --hostname "$ORIGIN_HOST" 2>/dev/null) || COMMENTS=""
if [ -z "$COMMENTS" ]; then
  echo "$PROG: could not read PR#$PR comments; nothing posted" >&2
  exit 0
fi
MATCH=$(printf '%s' "$COMMENTS" | jq -c --arg m "$MARKER" '[ .[]? | select(((.body // "") | tostring) | contains($m)) ] | first // empty' 2>/dev/null || true)
COMMENT_ID=""
if [ -n "$MATCH" ]; then
  COMMENT_ID=$(printf '%s' "$MATCH" | jq -r '.id // ""' 2>/dev/null || true)
fi

# UPDATE-ONLY: a conversation whose sitting named no topic has no comment, and
# its close leaves the PR alone.
[ "$MODE" = topic ] || [ -n "$COMMENT_ID" ] || exit 0

# A PR comment can be public and it stays, and no person reads this one before it
# posts. So nothing the operator typed reaches it: not the words that opened the
# conversation and not a dismiss's reason. The action is this script's own words.
# What a sitting wrote for it, the topic and the one-line outcome, goes on field
# by field, each printed here only once rig-mentions.sh clears it. A field the
# check lists, or cannot answer for, is left out, and the comment still says
# where the visit stands. The check judges for the subject's rig, whose PR this
# is, from the listing read above, so the check costs no second read of a
# listing that can take many seconds.
RIG_NAME=$(printf '%s' "$RIG_MAP" \
  | jq -r --arg p "${SUBJECT%%-*}" '.rigs[]? | objects | select(.prefix == $p) | .name' 2>/dev/null | head -n1)
cleared() { # <field> <text>
  [ -n "$2" ] || return 0
  local rc=0
  "$HERE/rig-mentions.sh" --rig "$RIG_NAME" --rig-map <(printf '%s' "$RIG_MAP") \
    --file <(printf '%s\n' "$2") >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) printf '%s' "$2" ;;
    1) echo "$PROG: left the $1 off the reminder on PR#$PR: it names another rig" >&2 ;;
    *) echo "$PROG: left the $1 off the reminder on PR#$PR: rig-mentions.sh could not answer (exit $rc)" >&2 ;;
  esac
}

# Compose the body. Both shapes carry the marker so the next call finds it.
BODY="$MARKER"$'\n'
if [ "$MODE" = topic ]; then
  TOPIC=$(cleared topic "$TOPIC")
  BODY="$BODY### Under discussion${TOPIC:+: $TOPIC}"$'\n'
  BODY="$BODY(visit $SITTING · updated with the action taken when it ends)"$'\n'
else
  # The topic the comment carries is the one its sitting named last, since the
  # title step posts each topic it names.
  OLD_BODY=$(printf '%s' "$MATCH" | jq -r '.body // ""' 2>/dev/null || true)
  TOPIC=$(printf '%s\n' "$OLD_BODY" | sed -n -e 's/^### Under discussion: //p' -e 's/^### Discussed: //p' | head -n1)
  TOPIC=$(cleared topic "$(oneline "$TOPIC")")
  SUMMARY=$(cleared summary "$SUMMARY")
  LINE="$ACTION${SUMMARY:+; $SUMMARY}"
  case "$LINE" in *[.!?]) ;; *) LINE="$LINE." ;; esac
  BODY="$BODY### Discussed${TOPIC:+: $TOPIC}"$'\n'
  BODY="${BODY}Action taken: $LINE"$'\n'
  BODY="$BODY(visit $SITTING)"$'\n'
fi

if [ -n "$COMMENT_ID" ]; then
  if "$PR_POST" edit --repo "$ORIGIN_REPO_Q" --comment "$COMMENT_ID" --body "$BODY" >/dev/null 2>&1; then
    echo "$PROG: updated sitting comment on PR#$PR ($MODE)"
  else
    echo "$PROG: could not update sitting comment $COMMENT_ID on PR#$PR" >&2
  fi
else
  # No comment yet. topic creates one; close already returned above.
  if "$PR_POST" comment --repo "$ORIGIN_REPO_Q" --pr "$PR" --body "$BODY" >/dev/null 2>&1; then
    echo "$PROG: posted sitting comment on PR#$PR"
  else
    echo "$PROG: could not post sitting comment on PR#$PR" >&2
  fi
fi
exit 0
