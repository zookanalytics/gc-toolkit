#!/usr/bin/env bash
# refinery-find-work.sh — the refinery patrol's find-work step: name the one
# bead this iteration takes.
#
#   refinery-find-work.sh
#
# Gas Town's selection: the beads assigned to this refinery ($GC_AGENT), open
# or in progress, that carry a branch, epics left out, in this rig's store. A
# bead whose PR waits on the pending record is blocked and assigned to nobody,
# so it is not listed, and the landing order assigns it to this refinery again
# when the PR moves to a head the refinery has not validated. Then the pack's
# differences:
#
#   - A bead something holds waits until its waits land. What holds it is the
#     answer of `gctk bead holds`, the pack's one rule.
#   - One writer per branch. A bead is left while another open bead works on
#     its branch: any open bead on the branch but the one it names as its
#     anchor, unless that bead is waiting here too, or it waits on the bead and
#     nobody writes it now. Such a bead cannot start before the bead closes.
#     Whether someone writes it is the build pool's own test, the one
#     work-setup.sh waits behind a sibling by (work_writing in work-lib.sh): a
#     live run works it, or a listed session holds its in_progress claim.
#     Among the beads that wait here, a rework child handed back is taken
#     before its anchor, then the highest priority, then the oldest.
#   - A rework child the requeue filed and never sent on (refinery-lib.sh)
#     works nothing. Once nothing holds it, it is neither a wait on its bead
#     nor a writer of the bead's branch, so the bead is taken as if the child
#     were not there, and the bead's prep sends the child on.
#   - An ask on the bead's PR (refinery-lib.sh) is the review run's work, never
#     the refinery's. It is neither a wait on the bead nor a writer of its
#     branch, so the bead is taken as if the ask were not there.
#   - A conversation on the bead's PR (conversation.sh) holds the PR's merge and
#     nothing else, through the landing order's evaluator. It is neither a wait
#     on the bead here nor a writer of its branch, so the bead is taken as if
#     the conversation were not there, whether it waits in the operator's
#     queue, a sitting holds it or its sitting stays.
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
# shellcheck source=work-lib.sh
. "$HERE/work-lib.sh" || { echo "$PROG: cannot source work-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=conversation.sh
. "$HERE/conversation.sh" || { echo "$PROG: cannot source conversation.sh beside this script" >&2; exit 1; }
# shellcheck source=run-lib.sh
. "${GC_RUN_LIB:-$HERE/run-lib.sh}" || { echo "$PROG: cannot source run-lib.sh beside this script" >&2; exit 1; }

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
# The conversations among what holds the beads (conversation.sh), as CONVS: a
# conversation holds its PR's merge and nothing else, so it neither holds the
# bead here nor works its branch. The beads waited on are read once, by id.
CONVS='[]'
WAITED=$(printf '%s' "$JUDGED" | jq -r '[ .[] | select(.holds.status != "clear") | (.holds.waits // [])[]
  | ((.id // "") | tostring) | select(. != "") ] | unique | join(",")')
if [ -n "$WAITED" ]; then
  WROWS=$(bd_json list ${GC_RIG:+--rig="$GC_RIG"} --id "$WAITED" --all --limit=0) || unread "the beads that hold the beads did not list"
  CONVS=$(printf '%s' "$WROWS" | jq -c "$CONVERSATION_JQ"'[ .[] | objects | select(conversation) | .id ]' 2>/dev/null)
  printf '%s' "$CONVS" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "the beads that hold the beads did not parse"
fi
# A bead's asks (refinery-lib.sh), as .asks: the review run's work, so they
# neither hold the bead nor work its branch.
JUDGED=$(printf '%s\n%s\n%s\n%s' "$JUDGED" "$UNSENT" "$BUSY" "$CONVS" | jq -sc "$REFINERY_ASK_JQ"'.[1] as $u | .[2] as $busy | .[3] as $convs | [ .[0][] | .id as $id
  | ((.metadata.branch // "") | tostring) as $b
  | ([ $u[] | select(.anchor == $id) | .id ]) as $mine
  | ([ $busy[] | select(.id != $id) | select(refinery_ask($b)) | .id ] | unique) as $asks
  | ([ (.holds.waits // [])[] | ((.id // "") | tostring) | select(. as $w | (($mine + $asks + $convs) | index($w)) == null) ]) as $other
  | . + {unsent: $mine, asks: $asks, held: (.holds.status != "clear" and (((.holds.waits // []) | length) == 0 or ($other | length) > 0)),
         waits_on: ($other[0] // "?")} ]' 2>/dev/null)
printf '%s' "$JUDGED" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "what holds the beads could not be weighed"
HELD=$(printf '%s' "$JUDGED" | jq -r '[ .[] | select(.held) | .id + " waits on " + .waits_on ] | join("; ")')
[ -z "$HELD" ] || echo "$PROG: leaving held bead(s) until what holds them lands: $HELD" >&2
CLEAR=$(printf '%s' "$JUDGED" | jq -c '[ .[] | select(.held | not) ]')

WAITING=$(printf '%s' "$JUDGED" | jq -c '[ .[].id ]')
# The other open beads on each bead's branch, as .others: all but the bead
# itself, the one it names as its anchor, its unsent rework children, its asks
# and the beads that wait here too. Each is a writer of the branch unless it
# waits on the bead and nobody writes it now.
OTHERS=$(printf '%s\n%s\n%s' "$CLEAR" "$BUSY" "$WAITING" | jq -sc '
  .[0] as $clear | .[1] as $busy | .[2] as $waiting
  | [ $clear[] | . as $b
      | ((.metadata.anchor_bead // "") | tostring) as $anchor
      | . + {others: ([ $busy[] | select(((.metadata.branch // "") | tostring) == (($b.metadata.branch // "") | tostring))
           | select(.id != $b.id and .id != $anchor)
           | select(.id as $i | (($b.unsent + $b.asks) | index($i)) == null)
           | select(.id as $i | ($waiting | index($i)) == null) | .id ] | unique)} ]' 2>/dev/null)
printf '%s' "$OTHERS" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "the beads on each branch could not be weighed"

# What each of those beads waits on, by `gctk bead holds`, as SIB_WAITS: each
# one's id to the ids of what holds it. Each that waits on a bead whose branch
# it is on is asked whether someone writes it now (work_writing), and the ones
# nobody writes are IDLE.
SIB_WAITS='{}'; IDLE='[]'
SIBS=$(printf '%s' "$OTHERS" | jq -r '[ .[].others[] ] | unique | .[]')
if [ -n "$SIBS" ]; then
  SROWS=$(printf '%s' "$BUSY" | jq -c --arg ids "$SIBS" '($ids | split("\n")) as $want | [ .[] | select(.id as $i | $want | index($i)) ] | unique_by(.id)' 2>/dev/null)
  printf '%s' "$SROWS" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "the other beads on the branches could not be weighed"
  # shellcheck disable=SC2086  # one argument per bead id
  SHOLDS=$("$gctk" bead holds $SIBS </dev/null 2>/dev/null) \
    || unread "gctk bead holds did not answer for every other bead on the branches"
  SIB_WAITS=$(judge "$SROWS" "$SHOLDS" | jq -c 'map({key: .id, value: [ (.holds.waits // [])[] | ((.id // "") | tostring) ]}) | from_entries' 2>/dev/null)
  printf '%s' "$SIB_WAITS" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || unread "gctk bead holds did not answer for every other bead on the branches"
  WAITERS=$(printf '%s\n%s\n%s' "$OTHERS" "$SROWS" "$SIB_WAITS" | jq -sr '.[2] as $w
    | ([ .[0][] | .id as $b | .others[] | select((($w[.] // []) | index($b)) != null) ] | unique) as $ids
    | .[1][] | select(.id as $i | $ids | index($i)) | [.id, ((.status // "open") | tostring), ((.assignee // "") | tostring)] | @tsv' 2>/dev/null) \
    || unread "the beads that wait on another could not be weighed"
  QUIET=""
  while IFS="$(printf '\t')" read -r id status assignee; do
    [ -n "$id" ] || continue
    work_writing "$id" "$status" "$assignee"
    case $? in
      0) ;;
      1) QUIET="$QUIET $id" ;;
      *) unread "the runs that work $id did not read" ;;
    esac
  done <<ROWS
$WAITERS
ROWS
  IDLE=$(printf '%s\n' "$QUIET" | jq -Rc 'split(" ") | map(select(. != ""))')
fi
# A bead's writers are its others, but one that waits on it and is IDLE.
RANKED=$(printf '%s\n%s\n%s' "$OTHERS" "$SIB_WAITS" "$IDLE" | jq -sc '
  .[0] as $others | .[1] as $waits | .[2] as $idle
  | [ $others[] | .id as $b
      | . + {writers: [ .others[] | select(. as $o
                          | ((($waits[$o] // []) | index($b)) != null and ($idle | index($o)) != null) | not) ],
             rank: (if ((.metadata.task_kind // "") | tostring) == "rework" and ((.metadata.anchor_bead // "") | tostring) != "" then 0 else 1 end)} ]' 2>/dev/null)
printf '%s' "$RANKED" | jq -e 'type == "array"' >/dev/null 2>&1 || unread "the beads on each branch could not be weighed"
BUSY_NOTE=$(printf '%s' "$RANKED" | jq -r '[ .[] | select(.writers | length > 0) | .id + " (" + (.writers | join(", ")) + " works its branch)" ] | join("; ")')
[ -z "$BUSY_NOTE" ] || echo "$PROG: leaving bead(s) whose branch another open bead works on: $BUSY_NOTE" >&2
WORK=$(printf '%s' "$RANKED" | jq -r '[ .[] | select(.writers | length == 0) ]
  | sort_by(.rank, (.priority // 2), (.created_at // .id)) | .[0].id // empty')
[ -n "$WORK" ] || exit 3
SEND_NOTE=$(printf '%s' "$RANKED" | jq -r --arg w "$WORK" '[ .[] | select(.id == $w and (.unsent | length) > 0) | .unsent | join(", ") ] | .[0] // empty')
[ -z "$SEND_NOTE" ] || echo "$PROG: $WORK's rework child $SEND_NOTE was filed and never sent on, and its prep sends it on" >&2
printf '%s\n' "$WORK"
