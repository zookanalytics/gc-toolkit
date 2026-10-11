#!/usr/bin/env bash
# review-file-bug — file a bug for a review finding that is real but out of
# scope for the diff under review, unless a bug carrying the finding's token is
# already open.
#
#   review-file-bug.sh --token "<stable identifier>" --title "<one line: what is wrong>"
#                      --body "<what is wrong, why it matters, what would fix it>"
#                      --branch <reviewed branch> --oid <reviewed commit>
#
# A rework round produces a new commit and a fresh review of the same page, so
# the same out-of-scope finding comes round again; without a probe, each round
# files another bug. The token is the finding's location plus a short slug for
# what is wrong (`PR #<n> body / ## Summary: placeholder`, or `<path>: <slug>` in
# the tree), so the next reviewer who sees the same thing builds the same string.
# Location alone collides: a second finding at the same place reads as the first
# and is lost. The title carries the token in parentheses, which is where the
# probe looks.
#
# bd fails open (errors on stderr, empty stdout), so an unreadable list reads
# exactly like "no match" until its shape is checked. An unreadable probe files
# nothing, and neither does a create that returns no id; the printed line says
# which, for the verdict to name, and the next round re-probes.
#
# Prints the filed or already-open bug id, or "unfiled — <why>".
# Called by mol-review's review step.
# exit: 0 filed, or found open · 1 unfiled · 2 usage
set -uo pipefail

PROG="review-file-bug"

usage() {
  echo "usage: $PROG --token <id> --title <line> --body <text> --branch <branch> --oid <commit>" >&2
}

TOKEN=""; TITLE=""; BODY=""; BRANCH=""; OID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --token|--title|--body|--branch|--oid)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; usage; exit 2; }
      case "$1" in
        --token)  TOKEN="$2" ;;
        --title)  TITLE="$2" ;;
        --body)   BODY="$2" ;;
        --branch) BRANCH="$2" ;;
        --oid)    OID="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if [ -z "$TOKEN" ] || [ -z "$TITLE" ] || [ -z "$BODY" ] || [ -z "$BRANCH" ] || [ -z "$OID" ]; then
  echo "$PROG: --token, --title, --body, --branch and --oid are all required" >&2
  usage
  exit 2
fi

# No --status: the default already excludes closed, and a duplicate someone has
# claimed or that is blocked is still a duplicate.
DUP_JSON=$(gc bd list --type=bug --title-contains "$TOKEN" --json 2>/dev/null)
if ! printf '%s' "$DUP_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "unfiled — duplicate probe unreadable"
  exit 1
fi
FILED=$(printf '%s' "$DUP_JSON" | jq -r '.[0].id // empty')
if [ -n "$FILED" ]; then
  echo "$FILED"
  exit 0
fi
FILED_JSON=$(gc bd create --type=bug --priority=2 --title="$TITLE ($TOKEN)" -d "$BODY

Found reviewing $BRANCH at $OID; out of scope for that diff." --json)
FILED=$(printf '%s' "$FILED_JSON" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
if [ -z "$FILED" ]; then
  CREATE_ERR=$(printf '%s' "$FILED_JSON" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null)
  echo "unfiled — bd create returned no id${CREATE_ERR:+: $CREATE_ERR}"
  exit 1
fi
echo "$FILED"
