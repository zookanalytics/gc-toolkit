#!/usr/bin/env bash
# review-verdict.sh — the single definition of the approval rule: whether a pull
# request carries a standing approval from an account other than the city's, and
# whether a standing request for changes vetoes it.
#
# Sourced (never executed) by the readers that act on a PR's approval: merge.sh
# (the universal approval merge rule and the visit order that predicts it) and
# pr-facts.sh (the conflict arm brings a branch current only for an approved
# PR). One definition, no copies: review-verdict.test.sh fails when a reader
# stops sourcing this file or carries a rule of its own. The Go port of
# merge.sh (services/gctk) states the same rule natively, and merge.test.sh
# runs every approval case against both.
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
  # The standing approvals themselves, one review per approving account.
  def standing_approvals($self):
    [ latest_opinions($self)[] | select(.state == "APPROVED") ];
'
