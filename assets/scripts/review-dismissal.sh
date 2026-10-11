#!/usr/bin/env bash
# review-dismissal.sh — what dismissing a pull request review retires. Sourced,
# never executed.
#
# A dismissal drops the review out of the approval rule (review-verdict.sh),
# and it retires the inline comments the review carried. GitHub keeps those
# comments on /pulls/N/comments, but they stop counting as feedback.
# REVIEW_DISMISSAL_DEF states that second rule once, for every reader of the
# comment space. pr-facts.sh reads only the comments no dismissal has retired
# (live_comments) before it counts or routes any feedback. A dismisser asks
# which comments a dismissal would retire before pr-facts.sh routes them
# (unrouted_comment_ids), so it never drops feedback nobody has read. One
# definition, no copies: review-dismissal.test.sh fails when a reader stops
# sourcing this file or carries a rule of its own.
#
# Usage follows the in-variable jq convention (review-verdict.sh): prepend the
# defs to a jq program. unrouted_comment_ids reads gc_city_own, the city's-own
# rule pr-post.sh prints with `pr-post.sh own-def`, so a program prepends that
# definition first:
#   jq -n "$CITY_OWN_DEF$REVIEW_DISMISSAL_DEF"'... live_comments($revs) ...'
# No comment inside the program may carry an apostrophe: the program is one
# single-quoted shell word.
# shellcheck disable=SC2034  # read by the scripts that source this file
REVIEW_DISMISSAL_DEF='
  # The inline comments on input that no dismissal has retired, given the
  # review list $revs. A dismissal is the only thing that retires a comment. A
  # comment naming no review, or naming one $revs does not carry, is standalone
  # and stays. Each kept comment is stamped with its review submission instant
  # as gc_review_submitted_at, the instant gc_city_own dates an inline comment
  # by: a comment drafted in a pending review is published when the review is
  # submitted, so a review drafted before the provenance cutover and submitted
  # after it reads as feedback whole.
  def live_comments($revs):
    ([ $revs[]
       | select(((.state // "") | tostring) == "DISMISSED")
       | ((.id // 0) | tostring) ]) as $retired
    | ([ $revs[]
         | select(((.submitted_at // "") | tostring) != "")
         | { key: ((.id // 0) | tostring), value: ((.submitted_at) | tostring) } ]
       | from_entries) as $submitted
    | [ .[]
        | (((.pull_request_review_id // "") | tostring)) as $parent
        | select(($retired | index($parent)) == null)
        | if ($submitted[$parent] // "") != ""
          then . + { gc_review_submitted_at: $submitted[$parent] } else . end ];
  # The line at or below which pr-facts.sh has routed every inline comment, or
  # seen its thread answer it: the higher of the anchor metadata $m marks
  # pr_comment_watermark and pr_comment_answered. A mark that is not a whole
  # number reads as 0.
  def comment_routed_through($m):
    [ ($m.pr_comment_watermark // 0), ($m.pr_comment_answered // 0) ]
    | map(tostring | if test("^[0-9]+$") then tonumber else 0 end) | max;
  # The ids of the inline comments on input that dismissing the reviews $rids
  # would retire before the feedback loop routes them. Each is live, carried by
  # one of $rids, feedback rather than the city own post (gc_city_own, dated by
  # the anchor pr_provenance_since), and above comment_routed_through($m), where
  # $m is the metadata of the anchor whose PR carries them.
  def unrouted_comment_ids($revs; $rids; $m; $self):
    comment_routed_through($m) as $mark
    | ((($m.pr_provenance_since // "") | tostring)) as $since
    | ([ $rids[] | tostring ]) as $want
    | [ live_comments($revs)[]
        | select(((.pull_request_review_id // "") | tostring) as $p | any($want[]; . == $p))
        | select(gc_city_own($self; $since) | not)
        | select(((.id // 0) | tonumber) > $mark)
        | (.id // 0) ];
'

