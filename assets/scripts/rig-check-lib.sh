#!/usr/bin/env bash
# rig-check-lib.sh — the single definition of whether a recorded fail of a rig
# check is judged pre-existing. Sourced, never executed.
#
# `gctk rig` records what a check's command did at a commit and never whose
# failure it is. rig-check-pre-existing.sh writes a caller's judgment that one
# recorded fail is red on the base too, as rig_check_pre_existing.<check> on a
# bead: the commit, the record it judged and the trackers that carry the
# failure. The judgment answers only while it holds the record a reader has in
# hand at that commit, and only while a tracker it names is live. A later run at
# the commit with another command or scope replaces the record, and its fail
# needs a judgment of its own. A tracker that closed no longer says the failure
# is red on the base. When its failure moved to a live bead, as a fold moves it,
# the fail is marked again against that bead. When no live bead carries it, as
# when the base's fix landed, the branch merges the base in.
#
# A tracker whose read fails is not live, because nothing shows it is, and it
# is reported as unread, never as closed: a reader honors no mark on a read
# that did not answer, and treats it as it treats any read it could not make.
#
# Readers: self-review-check.sh, on the work bead at the HEAD it checks, and
# review-evidence.sh, on the anchor at the commit a review reads. The writer
# refuses a tracker that is not live by pre_existing_tracker.
# rig-check-lib.test.sh fails when a reader stops sourcing this file or defines
# the judgment itself.
#
# A caller sources bd-lib.sh and then this file beside itself, because a
# tracker is read through bd-lib.sh's bd_carried_by, which reads through
# _bd_call:
#   # shellcheck source=bd-lib.sh
#   . "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh" >&2; exit 1; }
#   # shellcheck source=rig-check-lib.sh
#   . "$HERE/rig-check-lib.sh" || { echo "$PROG: cannot source rig-check-lib.sh" >&2; exit 1; }
# then judges a fail on the bead's `show --json` array:
#   pre_existing_judgment "<bead json>" <check> "<full sha>" "<record>"
# <record> is the JSON the judgment was written against: what `gctk rig <check>
# --check` reads, or for setup and build, the self-review's note of them. It
# prints one answer:
#   tracked by <ids>        the mark holds <record> at <sha>, and <ids> are the
#                           trackers it names that are live
#   another run             the mark at <sha> names a tracker for another record
#   no live tracker: <why>  the mark holds <record> at <sha>, but no tracker it
#                           names is live; <why> says, for each, what to do
#   unread: <why>           the mark holds <record> at <sha>, no tracker it
#                           names reads live, and at least one did not read
# and nothing when no mark answers at <sha>.

# shellcheck disable=SC2016,SC2034  # jq source, its $names are jq's; read by the scripts that source this file
PRE_EXISTING_JQ='
def pre_existing($k; $c; $rec):
  ($rec | fromjson? // null) as $r
  | .[0].metadata[$k] // empty
  | (if type == "string" then (fromjson? // empty) else . end)
  | select(type == "object" and .commit == $c and ((.trackers // []) | length) > 0)
  | if $r != null and .record == $r then "tracked by " + (.trackers | join(", ")) else "another run" end;
'

# pre_existing_tracker <tracker> — what a tracker a mark names says now, as one
# line: "live" while it is live, "closed: <what to do>" when it is not, and
# "unread: <tracker> did not read" when a read failed.
pre_existing_tracker() {
  local t="$1" c
  if ! c=$(bd_carried_by "$t"); then
    printf 'unread: %s did not read\n' "$t"
  elif [ "$c" = "$t" ]; then
    printf 'live\n'
  elif [ -n "$c" ]; then
    printf 'closed: %s has closed, and %s carries its failure now, so mark the fail against %s\n' "$t" "$c" "$c"
  else
    printf 'closed: %s is not live and no live bead carries its failure, so merge the base in\n' "$t"
  fi
}

# pre_existing_judgment <bead json> <check> <sha> <record> — the judgment of a
# recorded fail, as the header says.
pre_existing_judgment() {
  local pre t r live="" closed="" unread=""
  local -a ids=()
  pre=$(printf '%s' "$1" | jq -r --arg k "rig_check_pre_existing.$2" --arg c "$3" --arg rec "$4" \
    "$PRE_EXISTING_JQ"' pre_existing($k; $c; $rec)' 2>/dev/null)
  case "$pre" in
    "tracked by "*) ;;
    *) printf '%s' "$pre"; return 0 ;;
  esac
  IFS=', ' read -r -a ids <<< "${pre#tracked by }"
  for t in ${ids[@]+"${ids[@]}"}; do
    r=$(pre_existing_tracker "$t")
    case "$r" in
      live) live="$live${live:+, }$t" ;;
      unread:*) unread="$unread${unread:+; }${r#unread: }" ;;
      *) closed="$closed${closed:+; }${r#closed: }" ;;
    esac
  done
  if [ -n "$live" ]; then
    printf 'tracked by %s' "$live"
  elif [ -n "$unread" ]; then
    printf 'unread: %s' "$unread${closed:+; $closed}"
  else
    printf 'no live tracker: %s' "$closed"
  fi
}
