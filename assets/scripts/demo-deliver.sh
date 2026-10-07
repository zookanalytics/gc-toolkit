#!/usr/bin/env bash
# demo-deliver.sh — attach a produced demo artifact to its PR, inline and
# uncommitted, so a captured demo is delivered rather than left as a local file.
#
# `gh pr comment <pr> --attach <file>` (gh >= 2.99.0) uploads the file to
# GitHub's user-attachments CDN and renders it inline — a video becomes a player
# — with no browser step. A user-attachments URL is the only inline-playable
# path: a committed file, a release asset, or an external URL renders as a link.
# So a demo whose deliverable is "on the PR, not in the tree" is exactly this
# call, and it is bot-work on our own PR, not an operator send.
#
# This is the delivery seam the demo:capture skill and the rig-demo mol call once
# the engine has produced an MP4. It FAILS CLOSED: a missing or too-old gh, an
# unresolvable origin, a foreign PR, or a gh call that errors all exit non-zero,
# because a delivery that quietly does nothing is the silent local file this
# exists to prevent.
#
# A gh call inside a script is invisible to gh-origin-guard, so this resolves and
# pins the origin itself — the way pr-open.sh and pr-visit-comment.sh do — and
# refuses a PR that does not live in our own rig origin.
#
# Usage:
#   demo-deliver.sh --file <path> --pr <number|url> [--body <text>]
#   demo-deliver.sh --file <path> --subject <bead> [--body <text>]
#
#   --file     the produced artifact to attach (must exist and be non-empty).
#   --pr       the PR to attach to: a number (resolved against our origin) or a
#              full PR URL (which must live in our origin).
#   --subject  a bead whose pr_number / pr_url names the PR, when --pr is absent.
#   --body     comment text; the player is appended after it. A factual default
#              is used when omitted.
#
# Exit: 0 delivered, 2 bad arguments, 1 anything that stopped the delivery.
set -u

PROG=demo-deliver
# The single writer of the city's PR posts: the delivery comment goes through it
# so it carries the city's mark and is never read back as feedback.
PR_POST="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/pr-post.sh"

usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

FILE=""; PR=""; SUBJECT=""; BODY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file)    shift; [ $# -gt 0 ] || { echo "$PROG: --file needs a value" >&2; exit 2; }; FILE="$1" ;;
    --pr)      shift; [ $# -gt 0 ] || { echo "$PROG: --pr needs a value" >&2; exit 2; }; PR="$1" ;;
    --subject) shift; [ $# -gt 0 ] || { echo "$PROG: --subject needs a value" >&2; exit 2; }; SUBJECT="$1" ;;
    --body)    shift; [ $# -gt 0 ] || { echo "$PROG: --body needs a value" >&2; exit 2; }; BODY="$1" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$PROG: unknown flag '$1'" >&2; usage >&2; exit 2 ;;
    *)  echo "$PROG: unexpected argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# --- the artifact must exist and carry bytes -----------------------------
[ -n "$FILE" ] || { echo "$PROG: --file is required" >&2; usage >&2; exit 2; }
[ -f "$FILE" ] || { echo "$PROG: --file '$FILE' does not exist" >&2; exit 1; }
[ -s "$FILE" ] || { echo "$PROG: --file '$FILE' is empty" >&2; exit 1; }

# --- gh, at the version --attach shipped in ------------------------------
command -v gh >/dev/null 2>&1 || { echo "$PROG: gh not found; gh >= 2.99.0 is required for 'gh pr comment --attach'. doctor/check-demo-toolchain names this gap." >&2; exit 1; }
GHVER=$(gh --version 2>/dev/null | sed -n 's/^gh version \([0-9][0-9.]*\).*/\1/p' | head -1)
GHMAJOR=${GHVER%%.*}; GHREST=${GHVER#*.}; GHMINOR=${GHREST%%.*}
case "$GHMAJOR" in ''|*[!0-9]*) GHMAJOR=0 ;; esac
case "$GHMINOR" in ''|*[!0-9]*) GHMINOR=0 ;; esac
if [ "$GHMAJOR" -lt 2 ] || { [ "$GHMAJOR" -eq 2 ] && [ "$GHMINOR" -lt 99 ]; }; then
  echo "$PROG: gh ${GHVER:-unknown} is below 2.99.0; 'gh pr comment --attach' (inline delivery) is unavailable. Upgrade gh." >&2
  exit 1
fi
command -v git >/dev/null 2>&1 || { echo "$PROG: git not found" >&2; exit 1; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# --- the repository we may write to: our own rig origin ------------------
# From the subject's rig when a --subject names one, else this rig's root, else
# the caller's cwd — the same name->path->origin derivation pr-visit-comment.sh
# uses. The origin is pinned on every gh write below.
REPO_DIR=""
if [ -n "$SUBJECT" ] && command -v gc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  REPO_DIR=$(gc rig list --json 2>/dev/null | scrub \
    | jq -r --arg p "${SUBJECT%%-*}" '.rigs[]? | objects | select(.prefix == $p) | .path' 2>/dev/null | head -n1)
fi
{ [ -n "$REPO_DIR" ] && [ -d "$REPO_DIR" ]; } || REPO_DIR="${GC_RIG_ROOT:-}"
if [ -n "$REPO_DIR" ] && [ -d "$REPO_DIR" ]; then
  u=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null | tr -d '[:space:]')
else
  u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
fi
ORIGIN_HOST=""; ORIGIN_REPO=""
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
[ -n "$ORIGIN_REPO" ] || { echo "$PROG: cannot resolve our rig origin repository; refusing to attach (fail closed)" >&2; exit 1; }
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"

# --- resolve the PR: --pr (number or url), else --subject's pr binding ----
url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}
pr_url_canon() {
  printf '%s\n' "${1:-}" \
    | grep -Eo '[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+/pull/[0-9]+' | tail -1
}

PR_URL=""
if [ -z "$PR" ] && [ -n "$SUBJECT" ] && command -v gc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  SUBJ_JSON=$(gc bd show "$SUBJECT" --json 2>/dev/null | scrub)
  PR=$(printf '%s' "$SUBJ_JSON" | jq -r '.[0].metadata as $m | ($m.pr_number // "" | tostring) as $n | if $n != "" then $n else (($m.pr_url // "") | split("/pull/") | if length > 1 then ((.[1] | capture("^(?<d>[0-9]+)") | .d) // "") else "" end) end' 2>/dev/null || true)
  PR_URL=$(printf '%s' "$SUBJ_JSON" | jq -r '.[0].metadata.pr_url // ""' 2>/dev/null || true)
fi
[ -n "$PR" ] || { echo "$PROG: no PR given and none resolvable (need --pr, or --subject with a pr_number/pr_url)" >&2; exit 1; }

# A PR URL — passed on --pr or read from the subject — must live in our origin.
case "$PR" in *://*|*/pull/*) PR_URL="$PR" ;; esac
if [ -n "$PR_URL" ]; then
  got=$(url_repo_q "$(pr_url_canon "$PR_URL")")
  if [ -n "$got" ] && [ "$got" != "$ORIGIN_REPO_Q" ]; then
    echo "$PROG: PR '$PR_URL' lives in '$got', not our origin '$ORIGIN_REPO_Q'; refusing to attach" >&2
    exit 1
  fi
fi
# Reduce a URL to its number; we pin --repo, so a bare number is unambiguous.
case "$PR" in *://*|*/pull/*) PR=$(printf '%s' "$PR" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p') ;; esac
case "$PR" in ''|*[!0-9]*) echo "$PROG: could not reduce the PR reference to a number" >&2; exit 1 ;; esac

# --- deliver: attach inline to the PR ------------------------------------
[ -n "$BODY" ] || BODY="Demo capture for this PR — inline and uncommitted (uploaded to GitHub user-attachments, not the repo tree)."

# The player is appended after the body; a video takes no alt text, so the bare
# path is attached. gh uploads to user-attachments and then posts the comment,
# exiting non-zero if the upload or the post fails — the fail-closed signal.
OUT=$("$PR_POST" comment --repo "$ORIGIN_REPO_Q" --pr "$PR" --body "$BODY" --attach "$FILE" 2>&1)
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "$PROG: 'gh pr comment --attach' failed (rc=$RC) for PR#$PR on $ORIGIN_REPO_Q:" >&2
  printf '%s\n' "$OUT" >&2
  exit 1
fi
printf '%s\n' "$OUT"
echo "$PROG: delivered $FILE to PR#$PR on $ORIGIN_REPO_Q"
exit 0
