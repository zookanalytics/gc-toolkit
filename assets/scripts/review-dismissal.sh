#!/usr/bin/env bash
# review-dismissal.sh — the feedback a dismissal would retire before it is
# routed, and what the approval dismissers share. Sourced, never executed.
#
# A dismissal retires the inline comments the review carried (live_comments,
# in the definition of feedback that `pr-post.sh feedback-def` prints). A
# dismisser asks which comments a dismissal would retire before pr-facts.sh
# routes them (unrouted_comment_ids), so it never drops feedback nobody has
# read. REVIEW_DISMISSAL_DEF states that rule once. One definition, no copies:
# review-dismissal.test.sh fails when a reader stops sourcing this file or a
# file carries a rule of its own.
#
# The approval dismissers, approval-withdraw.sh and bring-current-guard.sh,
# also share how they name the PR they act on (pr_coords) and the approvals
# they dismiss (approval_phrase).
#
# Usage follows the in-variable jq convention (review-verdict.sh): prepend the
# defs to a jq program. unrouted_comment_ids reads live_comments and
# gc_feedback, which `pr-post.sh feedback-def` prints, so a program prepends
# that definition first:
#   jq -n "$CITY_OWN_DEF$REVIEW_DISMISSAL_DEF"'... unrouted_comment_ids(...) ...'
# No comment inside the program may carry an apostrophe: the program is one
# single-quoted shell word.
# shellcheck disable=SC2034  # read by the scripts that source this file
REVIEW_DISMISSAL_DEF='
  # The line at or below which pr-facts.sh has routed every inline comment, or
  # seen its thread answer it: the higher of the anchor metadata $m marks
  # pr_comment_watermark and pr_comment_answered. A mark that is not a whole
  # number reads as 0.
  def comment_routed_through($m):
    [ ($m.pr_comment_watermark // 0), ($m.pr_comment_answered // 0) ]
    | map(tostring | if test("^[0-9]+$") then tonumber else 0 end) | max;
  # The ids of the inline comments on input that dismissing the reviews $rids
  # would retire before the feedback loop routes them. Each is live, carried by
  # one of $rids, feedback (gc_feedback, dated by the anchor
  # pr_provenance_since), and above comment_routed_through($m), where $m is the
  # metadata of the anchor whose PR carries them.
  def unrouted_comment_ids($revs; $rids; $m; $self):
    comment_routed_through($m) as $mark
    | ((($m.pr_provenance_since // "") | tostring)) as $since
    | ([ $rids[] | tostring ]) as $want
    | [ live_comments($revs)[]
        | select(((.pull_request_review_id // "") | tostring) as $p | any($want[]; . == $p))
        | select(gc_feedback($self; $since))
        | select(((.id // 0) | tonumber) > $mark)
        | (.id // 0) ];
'

# pr_coords <pr-url> <pr-number> — the host and owner/repo of the pull request
# <pr-url> names, set into PR_HOST and PR_REPO. Returns 1, with both empty, when
# the url is not a pull request URL or names a number other than <pr-number>.
pr_coords() {
  PR_HOST=$(printf '%s' "$1" | sed -n 's#^https://\([^/]*\)/[^/]*/[^/]*/pull/[0-9][0-9]*.*#\1#p')
  PR_REPO=$(printf '%s' "$1" | sed -n 's#^https://[^/]*/\([^/]*/[^/]*\)/pull/[0-9][0-9]*.*#\1#p')
  if [ -z "$PR_HOST" ] || [ -z "$PR_REPO" ] \
     || [ "$(printf '%s' "$1" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p')" != "$2" ]; then
    PR_HOST=""; PR_REPO=""
    return 1
  fi
}

# approval_phrase <approvals-json> — the words a dismisser's messages name its
# approvals with, from the [{id, login}] list it dismisses. APPROVERS lists the
# logins once each ("a", "a and b", "a, b and c"). APPROVAL_NOUN and
# APPROVAL_VERB agree with how many approvals there are: "approval" and "is"
# for one, "approvals" and "are" for more, an account that approved twice
# counting twice.
approval_phrase() {
  APPROVERS=$(printf '%s' "$1" | jq -r '[ .[].login ] | unique | if length > 1 then (.[:-1] | join(", ")) + " and " + .[-1] else .[0] end')
  if [ "$(printf '%s' "$1" | jq 'length')" -gt 1 ]; then
    APPROVAL_NOUN="approvals"; APPROVAL_VERB="are"
  else
    APPROVAL_NOUN="approval"; APPROVAL_VERB="is"
  fi
}
