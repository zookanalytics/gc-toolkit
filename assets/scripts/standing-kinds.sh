#!/usr/bin/env bash
# standing-kinds.sh — the single definition of the standing kinds: the
# task_kind values whose bead is a standing record. A standing record is open,
# unrouted and unassigned by design, and it never closes. No worker claims it,
# a first reaction has no disposition to make on it, and a wait it sits behind
# owes it no dispatch path.
#
# Sourced (never executed) by the readers that tell a standing record from
# work or input: the liveness sweep and its claim-time re-check
# (liveness-sweep.sh, liveness-recheck.sh), the proactive scan
# (tools/gc-proactive.sh), and the doctor checks check-blocked-work-armed and
# check-hq-marooned-work. One definition, no copies: a kind added here is
# dropped by every one of them at once, and standing-kinds.test.sh fails when a
# reader stops sourcing this file or carries a list of its own.
#
# Usage follows the in-variable jq convention (visit-identity.sh): prepend the
# defs to a jq program, e.g.
#   jq "$STANDING_KINDS_JQ"' map(select(is_standing_kind | not)) '
# A program whose defs sit mid-body splices the variable in at that point
# instead, closing and reopening its single quotes around it.
STANDING_KINDS_JQ='
  # The task_kind values of a standing record.
  def standing_kinds: [
    "triage-subject",    # a triage bucket visits hang on (escalate.sh, liveness-sweep.sh)
    "feedback-pattern"   # a learning-loop pattern record (mol-feedback-distiller.toml)
  ];
  # True when this bead is a standing record. Reads metadata.task_kind only.
  def is_standing_kind:
    ((((.metadata // {}).task_kind) // "") | tostring) as $k
    | (standing_kinds | index($k)) != null;
'
