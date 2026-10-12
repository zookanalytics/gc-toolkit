#!/usr/bin/env bash
# live-work.sh — what makes a bead live work, which no automated disposal may
# close. A pass that closes a bead on a fact about another bead is right only
# when nothing else is acting on the bead, is about to, or owns its close. Each
# of those leaves a mark on the bead or on its edges:
#   - held: a status other than open, an assignee, a bound session;
#   - dispatched: a pool route, a deferred-dispatch arm or its sling marker, a
#     formula pour, a deferred route, a claim;
#   - worked: a branch, a worktree, a commit, a review round, a landing target,
#     a PR, a landing state, an outcome;
#   - owned by another closer: any task_kind (review, visit, rework, finding,
#     validation, a standing record, ...), a molecule step or workflow root, a
#     demand, a duplicate diagnosis, or an issue type that is not plain work (an
#     epic closes on its own ruling, and a convoy or a decision is not work);
#   - parked: a hold_reason or a rebase_hold, somebody's judgement in progress;
#   - structural: a convoy tracks it or parents it (a pour, or a planned batch),
#     or a child under it is still open.
# A bead with none of them is a pure wait, and only that may be disposed.
# Every mark refuses on presence, so a mark a reader cannot read is a refusal:
# an issue type outside the plain-work list refuses, and so does an unreadable
# list of dependents.
#
# Sourced (never executed) by the until consumer in deferred-dispatch.sh, which
# disposes a bead its `until` targets resolved and leaves every bead with a mark
# alone, and by doctor/check-until-resolved-owed, which reports such a bead as a
# decision for a person rather than as a disposal the order failed to make. One
# definition, no copies: a mark added here is honoured by both at once, and
# live-work.test.sh fails when either stops sourcing this file or a file
# defines these keys of its own.
#
# Usage follows the in-variable jq convention (standing-kinds.sh): prepend the
# defs to a jq program, e.g.
#   jq -r "$LIVE_WORK_JQ"' live_work_reasons | join("; ") '
# A program built in a double-quoted string expands the variable in place.
# shellcheck disable=SC2034  # read by the scripts that source this file
LIVE_WORK_JQ='
  # The metadata keys whose non-blank value marks live work.
  def live_work_keys: [
    # held: a session bound to the bead
    "gc.session_id", "gc.session_name",
    # dispatched: a queue, an arm or its sling, a pour, a deferred route, a claim
    "gc.routed_to", "gc.dispatch_when_ready", "gc.dispatch_when_ready_slung",
    "gc.execution_routed_to", "gc.deferred_routed_to",
    "gc.deferred_execution_routed_to", "gc.deferred_assignee",
    "gc.claimed_at", "gc.work_branch",
    # worked: a branch, a worktree, a commit, a review round, a landing target,
    # a PR, a landing state, an outcome
    "branch", "work_dir", "gc.work_dir", "gc.work_commit",
    "self_review_passed_sha", "prepare_mode", "rejection_reason", "target",
    "pr_number", "pr_url", "existing_pr", "merge_result", "merged_target",
    "gc.work_outcome", "work_outcome",
    # owned by another closer: a review cycle, a molecule, a demand, a
    # duplicate diagnosis
    "task_kind", "anchor_bead", "source_review_bead", "source_review",
    "source_ruling_bead", "gc.kind", "gc.root_bead_id", "gc.step_ref",
    "gc.step_id", "gc.formula_contract", "gc.input_convoy_id",
    "gc.demand_for", "duplicate_of",
    # parked: a judgement somebody has in progress
    "hold_reason", "rebase_hold"
  ];
  # The issue types of plain work, the ones doctor/check-blocked-work-armed
  # names as what a pool claims and works. An allowlist: a type it has never
  # heard of, a container (epic) or a question for a person (decision) is closed
  # by its own owner.
  def live_work_plain_types: ["task", "bug", "feature", "chore", "spike"];
  # One "<what>=<value>" per mark this bead row carries, empty when it carries
  # none. Reads the row `bd list --json` or `bd show --json` returns: status,
  # assignee, issue_type and metadata.
  def live_work_reasons:
    def nonblank: (. // "") | tostring | test("[^[:space:]]");
    def short: tostring | gsub("[[:cntrl:]]"; " ")
      | if length > 80 then .[0:77] + "..." else . end;
    (if (.metadata | type) == "object" then .metadata else {} end) as $m
    | ((.status // "") | tostring | ascii_downcase) as $st
    | ((.issue_type // "") | tostring | ascii_downcase) as $ty
    | [ (if $st != "open" then "status=" + ($st | short) else empty end),
        (if (.assignee | nonblank) then "assignee=" + (.assignee | short) else empty end),
        (if (live_work_plain_types | index($ty)) == null then "issue_type=" + ($ty | short) else empty end),
        (live_work_keys[] as $k | $m[$k] | select(nonblank) | $k + "=" + short) ];
  # One mark per edge that makes this bead live work, empty when none. Input:
  # the row `bd show --json` returns, whose .dependencies carry the issue_type
  # and status of each target. $up: what `bd dep list <id> --direction=up
  # --json` returns, the beads that depend on this one. `bd show` leaves a convoy
  # tracks edge out of its dependents, so they are read from $up, and anything
  # but an array there is unreadable, which refuses.
  def live_work_edge_reasons($up):
    if ($up | type) != "array" then ["dependents=unreadable"]
    else
      [ $up[] | objects
          | select(((.issue_type // "") | tostring) == "convoy")
          | "tracked by convoy " + ((.id // "?") | tostring) + " (" + ((.status // "?") | tostring) + ")" ]
      + [ $up[] | objects
          | select(((.dependency_type // .type // "") | tostring) == "parent-child")
          | select(((.status // "") | tostring | ascii_downcase) != "closed")
          | "open child " + ((.id // "?") | tostring) ]
      + [ (.dependencies | if type == "array" then .[] else empty end) | objects
          | select(((.dependency_type // .type // "") | tostring) == "parent-child")
          | select(((.issue_type // "") | tostring) == "convoy")
          | "child of convoy " + ((.id // "?") | tostring) ]
    end;
'
