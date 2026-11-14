#!/usr/bin/env bash
# refinery-find-work.sh — the refinery patrol's find-work step: name the one
# bead this iteration takes.
#
#   refinery-find-work.sh
#
# Gas Town's selection: the beads assigned to this refinery ($GC_AGENT), open
# or in progress, that carry a branch, epics left out, in this rig's store. A
# bead the publication left blocked on its PR's pending record is not open, so
# it is not listed. Then the pack's differences:
#
#   - A bead something holds waits until its waits land. What holds it is the
#     answer of `gctk bead holds`, the pack's one rule.
#   - One writer per branch. A bead is left while another open bead works on
#     its branch: any open bead on the branch but the one it names as its
#     anchor, unless that bead is waiting here too. Among the beads that wait
#     here, a rework child handed back is taken before its anchor, then the
#     highest priority, then the oldest.
#   - A rework child the requeue filed and never sent on (refinery-lib.sh)
#     works nothing. Once nothing holds it, it is neither a wait on its bead
#     nor a writer of the bead's branch, so the bead is taken as if the child
#     were not there, and the bead's prep sends the child on.
#
# A bead on the old path's cadence, merge_result pull_request or
# pre_open_gate, is the cadence's to drive, never this queue's, so it is named
# and left.
#
# stdout: the id of the bead to take, one line, and nothing else. What it
# leaves, and why, goes to stderr.
# Exit: 0 a bead was named · 1 a read did not answer, so nothing was taken: the
#       next patrol retries · 3 no bead to take
set -uo pipefail

PROG="refinery-find-work"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=gctk-resolve.sh
. "$HERE/gctk-resolve.sh" || { echo "$PROG: cannot source gctk-resolve.sh beside this script" >&2; exit 1; }

LIVE="open,in_progress,blocked,deferred,hooked,pinned"
case "${1:-}" in
  "") ;;
  -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "usage: $PROG" >&2; exit 2 ;;
esac
unread() { echo "$PROG: $1, so nothing is taken; the next patrol retries" >&2; exit 1; }

[ -n "${GC_AGENT:-}" ] || unread "GC_AGENT is empty, and an empty assignee filter is no filter"
ROWS=$(bd_json list ${GC_RIG:+--rig="$GC_RIG"} --assignee="$GC_AGENT" --status=open,in_progress \
  --exclude-type=epic --has-metadata-key=branch --limit=0) || unread "the beads assigned to $GC_AGENT did not list"
printf '%s' "$ROWS" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "the beads assigned to $GC_AGENT did not parse"

CADENCE=$(printf '%s' "$ROWS" | jq -r '[ .[] | select(((.metadata.merge_result // "") | tostring) as $m | $m == "pull_request" or $m == "pre_open_gate")
  | .id + "(" + .metadata.merge_result + ")" ] | join(" ")')
[ -z "$CADENCE" ] || echo "$PROG: leaving bead(s) the old path's cadence drives, which carry an assignee: $CADENCE" >&2
CANDS=$(printf '%s' "$ROWS" | jq -c '[ .[] | select(((.metadata.merge_result // "") | tostring) as $m | $m != "pull_request" and $m != "pre_open_gate") ]')
[ "$(printf '%s' "$CANDS" | jq 'length')" != 0 ] || exit 3

gctk=$(gctk_path) || unread "no gctk binary to read what holds the beads with"
# judge <rows> <holds>: each row with the answer `gctk bead holds` gave for it,
# as .holds. Nothing is printed unless every row has an answer.
judge() {
  { printf '%s\n' "$1"; printf '%s\n' "$2"; } | jq -sc '.[0] as $c | (.[1:] | map({key: .id, value: .}) | from_entries) as $h
    | if all($c[]; $h[.id] != null and $h[.id].error == null) then [ $c[] | . + {holds: $h[.id]} ] else empty end' 2>/dev/null
}
IDS=$(printf '%s' "$CANDS" | jq -r '.[].id')
# shellcheck disable=SC2086  # one argument per bead id
HOLDS=$("$gctk" bead holds $IDS </dev/null 2>/dev/null) || unread "gctk bead holds did not answer for every bead"
JUDGED=$(judge "$CANDS" "$HOLDS")
printf '%s' "$JUDGED" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "gctk bead holds did not answer for every bead"

# The open beads on each bead's branch, read once per branch.
BUSY='[]'
for BRANCH in $(printf '%s' "$JUDGED" | jq -r '[ .[].metadata.branch ] | unique | .[]'); do
  ON=$(bd_json list ${GC_RIG:+--rig="$GC_RIG"} --metadata-field "branch=$BRANCH" --status="$LIVE" --limit=0) \
    || unread "the open beads on $BRANCH did not list"
  printf '%s' "$ON" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "the open beads on $BRANCH did not parse"
  BUSY=$(printf '%s\n%s' "$BUSY" "$ON" | jq -sc '.[0] + .[1]')
done

# A bead's unsent rework children (refinery-lib.sh) that nothing holds, as
# .unsent: no one works them, so they neither hold the bead nor work its
# branch, and the bead's prep sends them on.
SENDS=$(printf '%s\n%s' "$JUDGED" "$BUSY" | jq -sc "$REFINERY_UNSENT_JQ"'.[0] as $j
  | [ .[1][] | . as $k | ([ $j[] | select(. as $b | $k | refinery_unsent($b.id; (($b.metadata.branch // "") | tostring))) | .id ][0]) as $a
      | select($a != null) | {id: $k.id, anchor: $a} ] | unique_by(.id)' 2>/dev/null)
printf '%s' "$SENDS" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "the rework children on the beads' branches could not be weighed"
UNSENT='[]'
if [ "$(printf '%s' "$SENDS" | jq 'length')" != 0 ]; then
  KIDS=$(printf '%s' "$SENDS" | jq -r '.[].id')
  # shellcheck disable=SC2086  # one argument per bead id
  KHOLDS=$("$gctk" bead holds $KIDS </dev/null 2>/dev/null) \
    || unread "gctk bead holds did not answer for every unsent rework child"
  UNSENT=$(judge "$SENDS" "$KHOLDS" | jq -c '[ .[] | select(.holds.status == "clear") | {id, anchor} ]' 2>/dev/null)
  printf '%s' "$UNSENT" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "gctk bead holds did not answer for every unsent rework child"
fi
JUDGED=$(printf '%s\n%s' "$JUDGED" "$UNSENT" | jq -sc '.[1] as $u | [ .[0][] | .id as $id
  | ([ $u[] | select(.anchor == $id) | .id ]) as $mine
  | ([ (.holds.waits // [])[] | ((.id // "") | tostring) | select(. as $w | ($mine | index($w)) == null) ]) as $other
  | . + {unsent: $mine, held: (.holds.status != "clear" and (((.holds.waits // []) | length) == 0 or ($other | length) > 0)),
         waits_on: ($other[0] // "?")} ]' 2>/dev/null)
printf '%s' "$JUDGED" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "what holds the beads could not be weighed"
HELD=$(printf '%s' "$JUDGED" | jq -r '[ .[] | select(.held) | .id + " waits on " + .waits_on ] | join("; ")')
[ -z "$HELD" ] || echo "$PROG: leaving held bead(s) until what holds them lands: $HELD" >&2
CLEAR=$(printf '%s' "$JUDGED" | jq -c '[ .[] | select(.held | not) ]')

WAITING=$(printf '%s' "$JUDGED" | jq -c '[ .[].id ]')
# A writer of a bead's branch is any open bead on it but the bead itself, the
# one it names as its anchor and its unsent rework children, unless the bead
# waits here too.
RANKED=$(printf '%s\n%s\n%s' "$CLEAR" "$BUSY" "$WAITING" | jq -sc '
  .[0] as $clear | .[1] as $busy | .[2] as $waiting
  | [ $clear[] | . as $b
      | ((.metadata.anchor_bead // "") | tostring) as $anchor
      | ([ $busy[] | select(((.metadata.branch // "") | tostring) == (($b.metadata.branch // "") | tostring))
           | select(.id != $b.id and .id != $anchor)
           | select(.id as $i | ($b.unsent | index($i)) == null)
           | select(.id as $i | ($waiting | index($i)) == null) | .id ] | unique) as $writers
      | . + {writers: $writers,
             rank: (if ((.metadata.task_kind // "") | tostring) == "rework" and $anchor != "" then 0 else 1 end)} ]' 2>/dev/null)
printf '%s' "$RANKED" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "the beads on each branch could not be weighed"
BUSY_NOTE=$(printf '%s' "$RANKED" | jq -r '[ .[] | select(.writers | length > 0) | .id + " (" + (.writers | join(", ")) + " works its branch)" ] | join("; ")')
[ -z "$BUSY_NOTE" ] || echo "$PROG: leaving bead(s) whose branch another open bead works on: $BUSY_NOTE" >&2
WORK=$(printf '%s' "$RANKED" | jq -r '[ .[] | select(.writers | length == 0) ]
  | sort_by(.rank, (.priority // 2), (.created_at // .id)) | .[0].id // empty')
[ -n "$WORK" ] || exit 3
SEND_NOTE=$(printf '%s' "$RANKED" | jq -r --arg w "$WORK" '[ .[] | select(.id == $w and (.unsent | length) > 0) | .unsent | join(", ") ] | .[0] // empty')
[ -z "$SEND_NOTE" ] || echo "$PROG: $WORK's rework child $SEND_NOTE was filed and never sent on, and its prep sends it on" >&2
printf '%s\n' "$WORK"
