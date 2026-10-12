#!/usr/bin/env bash
# review-verdict.sh — the single definition of the approval rule: whether a pull
# request carries a standing approval from an account other than the city's, and
# whether a standing request for changes vetoes it.
#
# Sourced (never executed) by the readers that act on a PR's approval: merge.sh
# (the universal approval merge rule and the visit order that predicts it),
# pr-facts.sh (the conflict arm brings a branch current only for an approved
# PR), bring-current-guard.sh (an approval the ruling on a bring-current round
# lifts is dismissed) and approval-withdraw.sh (a validator ruling that a fresh
# whole-diff review is warranted withdraws it). One definition, no copies:
# review-verdict.test.sh fails when a reader stops sourcing this file or
# carries a rule of its own. The Go port of merge.sh (services/gctk) states the
# same rule natively, and merge.test.sh runs every approval case against both.
#
# The input is a list of reviews in the REST shape that
# `GET /repos/{owner}/{repo}/pulls/{n}/reviews` returns: `.user.login`,
# `.state`, `.submitted_at`, `.id`. Each account other than $self takes its
# latest APPROVED or CHANGES_REQUESTED review. A dismissed review is in neither
# state, so it drops out before the latest is taken: a dismissed approval does
# not count, and a dismissed CHANGES_REQUESTED does not hide its author's older
# approval. An approval stands across later pushes until it is dismissed, so it
# counts at whatever commit it was given.
#
# A ruling on a bring-current round can lift the approval (bring-current-guard.sh
# decide). The guard stamps the round's time on the anchor as
# bring_current_lifted_at before it dismisses anything, and the two-argument
# review_verdict takes that stamp: an approval submitted at or before it no
# longer approves, whether or not GitHub let the dismissal land, and one
# submitted after it saw the merged code. The stamp holds the latest round whose
# ruling lifted the approval, so a later round whose ruling keeps the approval
# leaves the line where it was.
#
# Usage follows the in-variable jq convention (visit-identity.sh): prepend the
# defs to a jq program over the review list, e.g.
#   jq -s --arg self "$SELF_LOGIN" "$REVIEW_VERDICT_DEF"' review_verdict($self)'
# No comment inside the program may carry an apostrophe: the program is one
# single-quoted shell word.
# shellcheck disable=SC2034  # read by the scripts that source this file
REVIEW_VERDICT_DEF='
  # Each other account, by its latest APPROVED or CHANGES_REQUESTED review.
  def latest_opinions($self):
    [ .[] | select((.user.login // "") != $self)
      | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED") ]
    | group_by(.user.login // "") | map(sort_by((.submitted_at // ""), (.id // 0)) | last);
  # {veto, approver}, each the first such login or empty. The PR is approved
  # when approver is set and veto is empty.
  def review_verdict($self):
    latest_opinions($self) as $latest
    | { veto: ([ $latest[] | select(.state == "CHANGES_REQUESTED") | (.user.login // "") ] | .[0] // ""),
        approver: ([ $latest[] | select(.state == "APPROVED") | (.user.login // "") ] | .[0] // "") };
  # Every approval not yet dismissed, from each account other than $self, and
  # not only the latest from each. This is the set a withdrawal dismisses. A
  # dismissed review drops out before the latest is taken, so an older approval
  # left standing would count again, and so would an approval behind a later
  # CHANGES_REQUESTED from the same account once that request is dismissed.
  def standing_approvals($self):
    [ .[] | select((.user.login // "") != $self) | select(.state == "APPROVED") ];
  # The approvals given strictly after the instant $since: each account other
  # than $self whose latest opinion is an approval submitted after $since.
  # $since is an instant in the form GitHub stamps, YYYY-MM-DDTHH:MM:SSZ, in
  # which instants order as strings. An approval its author has since replaced
  # with a CHANGES_REQUESTED is not one, and a $since in any other form names
  # none, so an instant that did not read never lets an approval count.
  def approvals_after($self; $since):
    if (($since | tostring) | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) then
      [ latest_opinions($self)[] | select(.state == "APPROVED")
        | select(((.submitted_at // "") | tostring) > $since) ]
    else [] end;
  # The approval rule with the line a lifted approval leaves: review_verdict,
  # except that when $lifted is set only an approval submitted after it
  # approves. $lifted is the anchor stamp bring_current_lifted_at, and empty
  # lifts nothing. lifted names the first account whose standing approval the
  # line set aside, when no approval is left to land the PR, so a hold can say
  # why it holds.
  def review_verdict($self; $lifted):
    review_verdict($self) as $v
    | if (($lifted // "") | tostring) == "" then $v + {lifted: ""}
      else ([ approvals_after($self; $lifted)[] | (.user.login // "") ] | .[0] // "") as $a
        | {veto: $v.veto, approver: $a, lifted: (if $a == "" then $v.approver else "" end)} end;
'
