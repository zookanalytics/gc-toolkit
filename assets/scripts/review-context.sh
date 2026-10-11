#!/usr/bin/env bash
# review-context — print what a correctness review holds a diff against beyond
# the diff itself: the PR page as it will be published, and the pack's
# work-quality standards and exemplars.
#
#   review-context.sh --review-bead <id> [--pack <dir>]
#
# THE PAGE. The PR's `## Summary` is the human-facing merge-decision surface.
# Post-open (the review bead carries pr_number) the page is read through the
# repository pinned from the bead's own pr_url, never a bare number against
# ambient gh context, where every repository has a PR with that number. An
# unparseable pr_url prints why and reads nothing. Pre-open there is no page
# yet: pr-open.sh will publish the anchor's metadata.pr_summary verbatim as
# `## Summary` once the check goes green, falling back to the dispatch
# description and then a placeholder when it is absent, so the anchor's title
# and pending summary are what get printed, and an absent summary says so.
#
# THE STANDARDS. Every work-quality fragment (work-quality-base holds the
# universal standards and each work-quality-<class> its class's), then the
# exemplar corpus, which carries the lessons that are a shape rather than a
# statement and which nothing injects into a prompt. Both come from this
# script's own pack checkout unless --pack names another. A checkout lagging
# the commit that added a fragment still prints the rest; a checkout with none
# says so, for the verdict's coverage line. The operator profile is not
# printed: it governs how a role addresses the operator, a property of an agent
# and not of a diff.
#
# Called by mol-review's review step.
# exit: 0 printed · 1 the page could not be read · 2 usage
set -uo pipefail

PROG="review-context"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

usage() { echo "usage: $PROG --review-bead <id> [--pack <dir>]" >&2; }

REVIEW_BEAD=""; PACK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --review-bead|--pack)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; usage; exit 2; }
      if [ "$1" = --review-bead ]; then REVIEW_BEAD="$2"; else PACK="$2"; fi
      shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ -n "$REVIEW_BEAD" ] || { echo "$PROG: --review-bead is required" >&2; usage; exit 2; }
[ -n "$PACK" ] || PACK="$(cd "$SCRIPTS_DIR/../.." && pwd)"

rc=0
M=$(gc bd show "$REVIEW_BEAD" --json 2>/dev/null | jq -c '.[0].metadata // {}' 2>/dev/null)
PR=$(printf '%s' "$M" | jq -r '.pr_number // empty' 2>/dev/null)
if [ -n "$PR" ]; then
  PR_URL=$(printf '%s' "$M" | jq -r '.pr_url // empty')
  PR_REPO_Q=$(printf '%s' "$PR_URL" | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p')
  echo "## The PR under review: #$PR"
  if [ -z "$PR_REPO_Q" ]; then
    echo "post-open review bead has no parseable pr_url ('$PR_URL'): not resolving PR#$PR from ambient gh context"
    rc=1
  elif ! gh pr view "$PR" --repo "$PR_REPO_Q" --json title,body -q '"Title: " + .title + "\n\n" + .body'; then
    echo "gh could not read PR#$PR in $PR_REPO_Q"
    rc=1
  fi
else
  ANCHOR=$(printf '%s' "$M" | jq -r '.anchor_bead // empty' 2>/dev/null)
  echo "## The PR as pr-open.sh will publish it (pre-open)"
  if [ -z "$ANCHOR" ]; then
    echo "the review bead names no anchor_bead, so there is no pending summary to read"
    rc=1
  else
    ROW=$(gc bd show "$ANCHOR" --json 2>/dev/null)
    echo "Anchor: $ANCHOR"
    echo "Title: $(printf '%s' "$ROW" | jq -r '.[0].title // empty' 2>/dev/null)"
    SUMMARY=$(printf '%s' "$ROW" | jq -r '.[0].metadata.pr_summary // empty' 2>/dev/null)
    if [ -n "$(printf '%s' "$SUMMARY" | tr -d '[:space:]')" ]; then
      printf '\n%s\n' "$SUMMARY"
    else
      echo "pr_summary: absent — pr-open.sh will publish the dispatch description in its place (locus: anchor $ANCHOR / pr_summary)"
    fi
  fi
fi

echo
echo "## Work-quality standards"
found=0
for f in "$PACK"/template-fragments/work-quality-*.template.md; do
  [ -r "$f" ] || continue
  cat "$f"
  found=1
done
[ "$found" = 1 ] || echo "work-quality fragments not found in $PACK; note that in the verdict's coverage line"
if [ -r "$PACK/template-fragments/learning-exemplars.template.md" ]; then
  echo
  echo "## Exemplars"
  cat "$PACK/template-fragments/learning-exemplars.template.md"
fi
exit "$rc"
