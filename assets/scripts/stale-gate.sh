#!/usr/bin/env bash
# stale-gate.sh — the single definition of the stale-PR gate: the situation key
# its visit is filed under, which visits that key names, and the premise that
# decides whether an anchor's idle PR still owes the visit.
#
# liveness-sweep.sh files the visit on an anchor whose PR stopped moving, and
# retracts it once the premise is gone. liveness-sweep-precheck.sh runs that
# pass while an open visit may owe a retraction. merge.sh excepts an unengaged
# visit under the key from the finalize gate, because landing the PR is one of
# the answers the visit asks for. All three source this file. gctk merge, the
# Go port of merge.sh, cannot source a shell file, so it runs this one as
# `stale-gate.sh key`. One definition, no copies: stale-gate.test.sh fails when
# one of those readers stops reading this file or names the key itself.
#
# Sourced, it defines STALE_GATE_KEY and STALE_GATE_JQ and runs nothing.
# Executed as `stale-gate.sh key`, it prints the key.
#
# STALE_GATE_JQ follows the in-variable jq convention (visit-identity.sh):
# prepend or splice its defs into a jq program, e.g.
#   jq "$STALE_GATE_JQ"' [ .[] | select(unengaged_stale_gate_visit) | .id ]'
# The defs read no jq variable, so a program that splices them binds nothing
# for them. No comment inside the program may carry an apostrophe: the program
# is one single-quoted shell word.

# The situation key the stale-gate visit is filed and retracted under, in the
# charset escalate.sh and finalize-gate.sh accept for a key.
STALE_GATE_KEY="anchor-stale"

# shellcheck disable=SC2034  # read by the scripts that source this file
STALE_GATE_JQ='
  # An open stale-gate visit nobody is engaged in: no assignee and no bound
  # session (gc.session_name), the engagement test of the helm board. A visit
  # someone engaged is theirs to conclude. Its subject is the anchor its
  # gc.continuation_group stamp names.
  def unengaged_stale_gate_visit:
    ((.metadata.task_kind // "") | tostring) == "visit"
    and ((.status // "open") | tostring) == "open"
    and ((.metadata.escalation_key // "") | tostring) == "'"$STALE_GATE_KEY"'"
    and ((.assignee // "") | tostring) == ""
    and ((.metadata["gc.session_name"] // "") | tostring) == "";
  # An anchor -> the review posture pr-facts.sh records on it (pr_posture), when
  # the merge cadence settled the anchor (pr.machine) at the head that posture
  # was read at, and "" otherwise. merge.sh records settled only once every lane
  # is green and no review, fix or blocker is in flight, and a posture read at
  # another head says nothing about the live one. That is how the helm board
  # reads a settled row (prApproval and prOwed in
  # services/helm/internal/board/derive.go).
  def settled_posture:
    ((.metadata["pr.machine"] // "") | tostring | split("@")) as $m
    | ((.metadata.pr_posture // "") | tostring | split("@")) as $p
    | if ($m | length) == 3 and ($p | length) == 3
         and $m[0] == "settled" and $m[1] != "" and $m[1] == $p[1]
      then $p[0] else "" end;
  # The settled posture is approved. That answers the land-it disposition of
  # the visit: nothing else is in flight, and merge.sh does not hold an approved
  # PR on an unengaged visit. An approved PR the cadence has not settled still
  # has something in flight or holding it, so it keeps its visit.
  def pr_approved: settled_posture == "approved";
  # The settled posture still owes an approval or a re-review, so the PR waits
  # on the review of the operator, whose review queue already names the wait.
  # The premise re-check of converse closes a visit raised on it as benign.
  def review_owed:
    settled_posture as $s
    | (["review_required", "changes_requested", "commented", "none"] | index($s)) != null;
'

# Executable entry. A sourced load stops above with the definitions in place.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        key) printf '%s\n' "$STALE_GATE_KEY" ;;
        *) echo "usage: stale-gate.sh key" >&2; exit 2 ;;
    esac
fi
