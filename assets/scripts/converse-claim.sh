#!/bin/sh
# converse-claim.sh — claim one turn FOR A CONTINUATION GROUP, and put back
# anything that belongs to a different one (tk-msfmu; `gc hook --claim` has no
# group filter, so re-claim-within-the-group is claim-then-release until it
# grows one).
# Usage:
#   converse-claim.sh                 first claim of a session: any group
#   converse-claim.sh <current-group> re-claim: only this group is workable
# Output: one key=value line; exit status says what to do:
#   action=work  bead=<id> group=<g> [reason=unreleasable]     exit 0
#   action=drain reason=no-work                                exit 1
#   action=drain reason=out-of-group bead=<id> group=<g>       exit 1
# The RELEASE is the load-bearing half: never drain on a turn not put back
# (a held visit waits for witness patrol otherwise), release the WHOLE claim
# (the vacuumed continuation_assigned siblings too), and when part of the set
# will not go back, work the first still-HELD turn instead of draining.
# Caller: the converse prompt's claim loop.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

PROG="converse-claim"

usage() {
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1-}" in
    -h|--help) usage; exit 0 ;;
esac

CURRENT_GROUP="${1-}"

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "$PROG: gc is required" >&2; exit 2; }

CLAIM=$(gc hook --claim --json 2>/dev/null | scrub)

BEAD=$(printf '%s' "$CLAIM" | jq -r '.bead_id // ""' 2>/dev/null || printf '')
if [ -z "$BEAD" ]; then
    # No work, or an unreadable claim result: neither leaves anything held.
    echo "action=drain reason=no-work"
    exit 1
fi

GROUP=$(printf '%s' "$CLAIM" | jq -r '.continuation_group // ""' 2>/dev/null || printf '')

# The claim reports the gc.continuation_group STAMP, and the stamp lands empty
# on a minority of visits while the `tracks` edge filed alongside it still
# carries the subject (tk-tu5g3; su-ab9je is the edge holding where the stamp
# did not). Left empty, the deliberate cannot-prove-foreign fallback below
# silently disables this guard for exactly the turn it exists to catch — an
# unrelated visit vacuumed onto a live sitting (tk-msfmu) — so recover the
# group from the edge first. Scoped to task_kind=visit on purpose: `tracks` is
# not a visit-only edge (a convoy tracks its members), and inventing a group
# for a non-visit would release a turn this session was entitled to work. A
# visit carrying neither recording still resolves to the fallback below; the
# writer-side loss (tk-ax6y4) is repaired where the visit is filed.
if [ -z "$GROUP" ]; then
    GROUP=$(gc bd show "$BEAD" --json 2>/dev/null | scrub \
        | jq -r 'if type == "array" then (.[0] // {}) else {} end
                 | select(((.metadata // {}).task_kind // "") == "visit")
                 | [ ((.dependencies // [])[]?
                       | select((((.type // .dependency_type // "") | tostring)) == "tracks")
                       | ((.depends_on_id // .id // "") | tostring)) ]
                 | map(select(. != "")) | .[0] // ""' 2>/dev/null || printf '')
    [ -n "$GROUP" ] && echo "$PROG: the claim reported no continuation group for $BEAD; recovered '$GROUP' from its tracks edge" >&2
fi

# Work on a match, a first claim, or no group to compare — the unknown cases
# resolve to WORK on purpose (releasing an unproven-foreign turn is a strand
# dressed as a fix).
if [ -z "$CURRENT_GROUP" ] || [ -z "$GROUP" ] || [ "$GROUP" = "$CURRENT_GROUP" ]; then
    echo "action=work bead=$BEAD group=$GROUP"
    exit 0
fi

# Foreign group: put back everything this claim assigned, then drain.

# release_turn <bead-id> — three ORDERED writes (bd's claim guard refuses
# --assignee "" on an in_progress bead, and metadata writes bypass it, so:
# unset session pointers, --status=open, then --assignee="" — tk-z27pw), then
# the read-back that decides. gc.routed_to is deliberately left alone: it is
# the pool's offer predicate, and clearing it would park the turn. Every
# write is attempted even after one fails; the READ must also agree.
release_turn() {
    _id="$1"
    _ok=1
    gc bd update "$_id" --unset-metadata gc.session_id --unset-metadata gc.session_name >/dev/null 2>&1 || _ok=0
    gc bd update "$_id" --status=open >/dev/null 2>&1 || _ok=0
    gc bd update "$_id" --assignee="" >/dev/null 2>&1 || _ok=0

    # Trust the read, not the writes: a partial release still holds the turn.
    STATE=$(gc bd show "$_id" --json 2>/dev/null | scrub \
            | jq -r 'if type=="array" then "\(.[0].status // "")|\(.[0].assignee // "")" else "|" end' 2>/dev/null || printf '')
    case "$STATE" in
        "open|") ;;                   # back in the pool
        *)       _ok=0 ;;
    esac
    [ "$_ok" = "1" ]
}

# The claimed turn FIRST, then every vacuumed sibling; order preserved,
# duplicates dropped.
RELEASE_IDS=$(printf '%s' "$CLAIM" | jq -r '
    ([.bead_id // empty] + (.continuation_assigned // []))
    | map(select(type == "string" and . != ""))
    | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)
    | .[]' 2>/dev/null || printf '')
# A claim we could not re-read is still a claim: fall back to the turn we know.
[ -z "$RELEASE_IDS" ] && RELEASE_IDS="$BEAD"

RELEASED=1
UNRELEASED=""
# The turn to NAME must be one this session still HOLDS — the first release
# failure, which is the claimed turn whenever the claimed turn is the stuck
# one (naming an already-released bead would be a strand and a race).
HELD_TURN=""
for _turn in $RELEASE_IDS; do
    if ! release_turn "$_turn"; then
        RELEASED=0
        [ -z "$HELD_TURN" ] && HELD_TURN="$_turn"
        UNRELEASED="${UNRELEASED:+$UNRELEASED }$_turn(${STATE:-unreadable})"
    fi
done

if [ "$RELEASED" = "0" ]; then
    # Working a still-held turn out of group is a legible surprise; draining
    # now would strand it silently.
    echo "$PROG: could not release $UNRELEASED back to the pool; working $HELD_TURN rather than stranding it" >&2
    echo "action=work bead=$HELD_TURN group=$GROUP reason=unreleasable"
    exit 0
fi

echo "action=drain reason=out-of-group bead=$BEAD group=$GROUP"
exit 1
