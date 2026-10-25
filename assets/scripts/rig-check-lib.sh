#!/usr/bin/env bash
# rig-check-lib.sh — the single definition of whether a recorded fail of a rig
# check is judged pre-existing. Sourced, never executed.
#
# `gctk rig` records what a check's command did at a commit and never whose
# failure it is. rig-check-pre-existing.sh writes a caller's judgment that one
# recorded fail is red on the base too, as rig_check_pre_existing.<check> on a
# bead: the commit, the record it judged and the trackers that carry the
# failure. The judgment answers only while it holds the record a reader has in
# hand at that commit. A later run at the commit with another command or scope
# replaces the record, and its fail needs a judgment of its own.
#
# Readers: self-review-check.sh, on the work bead at the HEAD it checks.
# rig-check-lib.test.sh fails when a reader stops sourcing this file or defines
# the judgment itself.
#
# A caller sources it beside itself:
#   # shellcheck source=rig-check-lib.sh
#   . "$HERE/rig-check-lib.sh" || { echo "$PROG: cannot source rig-check-lib.sh" >&2; exit 1; }
# then applies the def to the bead's `show --json` array:
#   jq -r --arg k "rig_check_pre_existing.<check>" --arg c "<full sha>" --arg rec "<record>" \
#     "$PRE_EXISTING_JQ"' pre_existing($k; $c; $rec)'
# It prints "tracked by <ids>" when the mark holds <record> at <sha> and names a
# tracker, "another run" when the mark at <sha> names a tracker for a record
# other than <record>, and nothing when no mark answers at <sha>. <record> is
# the JSON the judgment was written against: what `gctk rig <check> --check`
# reads, or for setup and build, the self-review's note of them.

# shellcheck disable=SC2016,SC2034  # jq source, its $names are jq's; read by the scripts that source this file
PRE_EXISTING_JQ='
def pre_existing($k; $c; $rec):
  ($rec | fromjson? // null) as $r
  | .[0].metadata[$k] // empty
  | (if type == "string" then (fromjson? // empty) else . end)
  | select(type == "object" and .commit == $c and ((.trackers // []) | length) > 0)
  | if $r != null and .record == $r then "tracked by " + (.trackers | join(", ")) else "another run" end;
'
