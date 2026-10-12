#!/usr/bin/env bash
# placement.sh — the single definition of a bead that waits for placement.
# Intake holds new work for the operator's placement sitting (docs/steering.md):
# a first reaction's actionable exit, the witness's pack-defect bug and the
# feedback distiller's beads mark such a bead placement=pending and leave it
# unrouted. It waits until the sitting places it under an epic or routes it on
# its own. A bead with a parent is placed, and so is one with a dispatch path
# (dispatch-path.sh), an assignee, or a live pour (gc.execution_routed_to), so
# any of those ends the wait whether or not the marker was cleared.
#
# Sourced (never executed) by the readers that ask whether a bead is in the
# sitting's queue: gc-helm.sh unplaced, which lists the queue; the liveness
# classifier (liveness-classify.sh), which names the wait so the sweep does not
# report it as an unnamed one; and the doctor check check-blocked-work-armed,
# which owes such a bead no arm. One definition, no copies: a placed shape added
# here is read by every one of them at once, and placement.test.sh fails when a
# reader stops sourcing this file or tests the marker itself.
#
# Usage follows the in-variable jq convention (dispatch-path.sh). The predicate
# asks has_dispatch_path, so prepend $DISPATCH_PATH_JQ first, e.g.
#   jq "$DISPATCH_PATH_JQ$PLACEMENT_JQ"' map(select(awaiting_placement)) '
# It reads a bead in either shape bd prints: `bd show` names a parent edge
# {id, dependency_type}, and `bd list` and `bd ready` name it
# {depends_on_id, type}.
# shellcheck disable=SC2034  # read by the scripts that source this file
PLACEMENT_JQ='
  # The marker value intake writes on a bead it holds for placement.
  def placement_pending: "pending";
  # True when this bead waits for the placement sitting: it carries the marker,
  # and nothing has placed it since.
  def awaiting_placement:
    (.metadata // {}) as $m
    | ((($m.placement // "") | tostring) == placement_pending)
      and ((.parent // "") == "")
      and ([ .dependencies[]? | select(((.dependency_type // .type) // "") == "parent-child") ] | length) == 0
      and (has_dispatch_path | not)
      and ((.assignee // "") == "")
      and (($m["gc.execution_routed_to"] // "") == "");
'
