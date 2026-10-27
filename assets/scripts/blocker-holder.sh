#!/usr/bin/env bash
# blocker-holder.sh — whether an automated actor holds the live blockers an
# anchor's merge waits on. The writers of the anchor's machine verdict, the
# merge pass (gctk merge) and gate-ensure.sh, each ask this script when a live
# blocker holds the anchor, so they reach one answer. It prints one line:
#   actor <bead> <how>   an automated actor holds this live blocker, so the merge
#                        waits on work the city is doing (progressing)
#   stuck <bead>         no automated actor holds any live blocker, and this one
#                        is not routed to a person, so nothing the city runs
#                        will clear it (blocked, cause blocker)
#   none                 no live blocker, or only blockers routed to a person
#
# A live blocker is one whose status is open, in_progress, blocked, deferred,
# hooked or pinned, a missing status reading open. An automated actor holds it
# when any of these marks it:
#   - a route: gc.routed_to names a pool or an agent, anything but human;
#   - a claim: an assignee other than human. The refinery holds a rework handed
#     back to it this way until the rework lands on its branch;
#   - a live run working it (run-lib.sh). A graph.v2 pour leaves the bead it
#     works open, unassigned and unrouted, so its run is the only mark. The
#     gc.execution_routed_to stamp the pour leaves outlives the run, so it is no
#     mark.
# One actor is enough: any blocker an actor holds answers actor, before a stuck
# one is named. Routes and claims come from the one listing of blockers, and a
# blocker's runs are read only when it carries neither.
#
# Usage: blocker-holder.sh --anchor <id>
# Exit: 0 answered · 1 usage · 2 a read did not resolve, and nothing is printed,
# so a caller records no verdict on it.
set -u

PROG="blocker-holder"
_bh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=run-lib.sh
. "${GC_RUN_LIB:-$_bh_dir/run-lib.sh}" || { echo "$PROG: cannot source run-lib.sh beside this script" >&2; exit 2; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# The store every read here goes to: the ambient one, as the merge pass's own
# reads.
holder_bd() { gc bd "$@"; }

anchor=""
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { echo "$PROG: --anchor needs a value" >&2; exit 1; } ;;
    *) echo "$PROG: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -n "$anchor" ] || { echo "usage: blocker-holder.sh --anchor <id>" >&2; exit 1; }

raw=$(holder_bd dep list "$anchor" --direction=down -t blocks --json </dev/null 2>/dev/null) \
  || { echo "$PROG: could not read the blockers of $anchor" >&2; exit 2; }
rows=$(printf '%s\n' "$raw" | grep -a -vE '^gc bd:' | scrub)
printf '%s' "$rows" | jq -e 'type == "array" and all(.[]; type == "object")' >/dev/null 2>&1 \
  || { echo "$PROG: the blockers of $anchor did not read as a list" >&2; exit 2; }

# One line per live blocker not routed to a person: its id, a tab, then the
# route or claim that marks it, or nothing when neither does.
marks=$(printf '%s' "$rows" | jq -r --arg live "$LIVE_STATUSES" '
  ($live | split(",")) as $ls
  | .[]
  | ((.status // "open") | tostring | ascii_downcase) as $st
  | select($ls | index($st))
  | (((.metadata // {})["gc.routed_to"] // "") | tostring) as $r
  | ((.assignee // "") | tostring) as $a
  | select($r != "human")
  | [ ((.id // "") | tostring),
      (if $r != "" then "routed to " + $r
       elif $a != "" and $a != "human" then "claimed by " + $a
       else "" end) ]
  | map(gsub("[\t\n]"; " ")) | @tsv') \
  || { echo "$PROG: could not read the routes and claims of the blockers of $anchor" >&2; exit 2; }

while IFS=$'\t' read -r id how; do
  [ -n "$id" ] || continue
  if [ -n "$how" ]; then
    printf 'actor %s %s\n' "$id" "$how"
    exit 0
  fi
done <<<"$marks"

stuck=""
while IFS=$'\t' read -r id _; do
  [ -n "$id" ] || continue
  runs=$(run_lib runs holder_bd "$id") \
    || { echo "$PROG: could not read the runs that work $id" >&2; exit 2; }
  root=$(printf '%s' "$runs" | jq -r '[ .[] | select(.live) | .root ] | .[0] // empty' 2>/dev/null) \
    || { echo "$PROG: could not read the runs that work $id" >&2; exit 2; }
  if [ -n "$root" ]; then
    printf 'actor %s worked by run %s\n' "$id" "$root"
    exit 0
  fi
  [ -n "$stuck" ] || stuck="$id"
done <<<"$marks"

if [ -n "$stuck" ]; then
  printf 'stuck %s\n' "$stuck"
else
  echo none
fi
exit 0
