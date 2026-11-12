#!/usr/bin/env bash
# standing-kinds.sh — the standing kinds as jq defs: the task_kind values whose
# bead is a standing record. A standing record is open, unrouted and unassigned
# by design, and it never closes. No worker claims it, a first reaction has no
# disposition to make on it, and a wait it sits behind owes it no dispatch path.
#
# The one definition of the list is services/gctk/standing/kinds.json, which
# names each kind and what its record is. This file reads it into the defs
# below, and gctk's standing package embeds the same file for the Go readers,
# among them the helm board's rig read, which leaves a standing record out of
# its rows.
#
# Sourced (never executed) by the shell readers that tell a standing record
# from work or input: the liveness sweep, its precheck and its claim-time
# re-check (liveness-sweep.sh, liveness-sweep-precheck.sh, liveness-recheck.sh),
# the proactive scan (tools/gc-proactive.sh), and the doctor checks
# check-blocked-work-armed and check-hq-marooned-work. The sweep and its
# precheck read the list through their shared classifier
# (liveness-classify.sh). One definition, no copies: a kind added to kinds.json
# is dropped by every one of them at once, and standing-kinds.test.sh fails when
# a reader stops reading the definition or carries a list of its own.
#
# Sourcing returns 1, naming the file, when kinds.json does not read as a
# non-empty object of kinds, each with text saying what its record is. A reader
# then stops rather than take every bead for work.
#
# Usage follows the in-variable jq convention: prepend the defs to a jq
# program, e.g.
#   jq "$STANDING_KINDS_JQ"' map(select(is_standing_kind | not)) '
# A program whose defs sit mid-body splices the variable in at that point
# instead, closing and reopening its single quotes around it.
_standing_kinds_file="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd)/services/gctk/standing/kinds.json"
if ! _standing_kinds_list="$(jq -ce '
    if type == "object" and length > 0
       and all(keys_unsorted[]; length > 0)
       and all(.[]; type == "string" and test("\\S"))
    then keys_unsorted
    else error("not the standing kinds")
    end' "$_standing_kinds_file" 2>/dev/null)"; then
  printf 'standing-kinds.sh: %s does not read as the standing kinds\n' "$_standing_kinds_file" >&2
  unset _standing_kinds_file _standing_kinds_list
  return 1
fi
# shellcheck disable=SC2034  # read by the scripts that source this file
STANDING_KINDS_JQ='
  # The task_kind values of a standing record, as kinds.json names them.
  def standing_kinds: '"$_standing_kinds_list"';
  # True when this bead is a standing record. Reads metadata.task_kind only.
  def is_standing_kind:
    ((((.metadata // {}).task_kind) // "") | tostring) as $k
    | (standing_kinds | index($k)) != null;
'
unset _standing_kinds_file _standing_kinds_list
