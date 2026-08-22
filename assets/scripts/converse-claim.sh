#!/bin/sh
# converse-claim.sh — claim one turn FOR A CONTINUATION GROUP, and put back
# anything that belongs to a different one (tk-msfmu).
#
# Usage:
#   converse-claim.sh                 first claim of a session: any group
#   converse-claim.sh <current-group> re-claim: only this group is workable
#   converse-claim.sh --help
#
# Output is ONE line of key=value pairs on stdout, and the exit status says
# what to do, so a caller can branch on either:
#
#   action=work  bead=<id> group=<g> [reason=unreleasable]   exit 0
#   action=drain reason=no-work                                exit 1
#   action=drain reason=out-of-group bead=<id> group=<g>       exit 1
#
# ── Why this exists ──────────────────────────────────────────────────
# `agents/converse/agent.toml` names `specs/tk-h9pq5/design-doc.md` as the
# design authority, and that document states the v2 loop in one sentence: the
# role "records the outcome on the subject bead, closes the turn, then
# RE-CLAIMS WITHIN THE GROUP and DRAINS WHEN THE GROUP IS DRY". The shipped
# prompt could not obey it, because `gc hook --claim` has no group filter —
# its whole option set is `--claim`, `--drain-ack`, `--inject`, `--json`. So
# "re-claim within the group" was not expressible with the tool the prompt
# calls its only source of work, and the prompt widened the contract instead:
# "a claim is authoritative even when it names a different subject than your
# last one".
#
# The cost of the widening is paid by the operator. On 2026-08-22 a sitting
# about the helm board UI (subject tk-3a176) ended correctly, and the same
# session then claimed an unrelated merge-skill visit and began prepping it in
# the SAME thread: "How'd we get here? I thought we were talking about the helm
# UI?" The sign-off had fired and was not enough, because a sign-off is
# announced only by the OUTGOING sitting, never by the incoming one.
#
# ── Why a claim-then-release, rather than a filter ───────────────────
# A group FILTER belongs in `gc hook --claim` and would remove the round trip
# entirely; that is the better fix and it lives in the gc binary, not in this
# pack. Until it exists, the only way to learn a turn's group is to claim it —
# the claim result is what carries `continuation_group`.
#
# That makes the RELEASE the load-bearing half. Draining on an out-of-group
# claim without releasing is worse than the bug it fixes: the claim has already
# assigned the turn to a session that is about to die, and the reconciler's
# reassign path refuses a held visit by design, so the turn waits for witness
# patrol or lease expiry. This script therefore never drains on a turn it did
# not successfully put back.
#
# ── The release, and why it is three writes ──────────────────────────
# bd's claim guard refuses `--assignee ""` on an `in_progress` bead — even when
# the holder is your own live session — and the refusal is atomic over the
# whole update, so batching the clears loses the ones that needed no claim at
# all (tk-z27pw). Verified against the running bd on 2026-08-22:
#
#   gc bd update <id> --status=open --assignee=""
#   -> cannot reassign <id>: held by "<session>" (in_progress)
#
# Split and ORDERED, the same clears need no `--force`:
#   1. unset the session pointers — metadata writes bypass the claim guard;
#   2. `--status=open`   — the guard keys on in_progress, so this opens the gate;
#   3. `--assignee=""`   — now permitted.
#
# `gc.routed_to` is deliberately left ALONE: it is the pool's offer predicate,
# and the released turn has to be offerable again. Clearing it would park the
# turn instead of returning it — the failure this script exists to avoid,
# reached by a different route. The session pointers are cleared FIRST so the
# instant the turn becomes offerable it no longer names a dead session.
#
# ── The release covers the whole claim, not just the named turn ──────
# One claim can assign MORE than one turn. `gc hook --claim` preassigns the
# claimed bead's continuation-group siblings onto the same session in the same
# call (`preassignHookContinuationGroup` in cmd/gc/cmd_hook_claim.go) and
# reports them back as `continuation_assigned`. Releasing only `.bead_id` left
# every vacuumed sibling `in_progress` on a session that was about to drain —
# the exact strand this script exists to prevent, reached by the door next to
# the one it was watching.
#
# Every id in that set is in the SAME group as the claimed turn — the preassign
# filters on it — so when the claimed turn is foreign, all of them are, and the
# whole set goes back. Absent the key (an older `gc`, or a claim that vacuumed
# nothing) the set is just the claimed bead, which is the previous behaviour.
#
# The set comes from the claim result rather than from a query for "everything
# assigned to this session", because the claim is the thing that did the
# assigning and names its own work exactly; a session-wide sweep would also
# catch turns from the session's OWN group, which are not this script's to
# return. The residual: if `gc` fails PART WAY through the preassign it exits
# non-zero having already assigned some siblings and prints no JSON, so no
# release list reaches us. That is an upstream partial failure this script
# cannot see; the group filter in `gc hook --claim` retires it along with the
# round trip.
#
# ── An unreleasable set names a turn still HELD ──────────────────
# When part of the set will not go back, the script works a turn instead of
# draining — and the turn it names has to be one this session still holds. That
# is NOT always the claimed one. The release runs the named turn first, so the
# ordinary vacuum failure is "the named turn released cleanly, a sibling stuck":
# naming `.bead_id` there would hand the sitting a bead this script had just
# reopened and unassigned, free for another session to claim concurrently, while
# the actually-held sibling sat assigned and unworked — a strand and a race from
# one line. The reported turn is therefore the FIRST that failed to release,
# which is still the claimed turn whenever the claimed turn is the stuck one.
#
# Residual: only one turn can be named, so if several stay held the others are
# reported on stderr but not worked. That is the same one-turn ceiling the
# single-bead design always had — the caller acts on one bead — and the stderr
# report is what makes the rest legible.
#
# ── What it does NOT own ─────────────────────────────────────────────
# Everything about the sitting itself. This is the claim boundary only: which
# turn this session may work, and how a turn it may not work gets back to the
# pool. What a sitting does once claimed stays in the converse prompt.
set -u

PROG="converse-claim"

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1-}" in
    -h|--help) usage; exit 0 ;;
esac

CURRENT_GROUP="${1-}"

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "$PROG: gc is required" >&2; exit 2; }

# `gc hook` writes its JSON to stdout and its config warnings to stderr, so the
# payload is clean without filtering. Control characters can still ride in on a
# bead's own text and would make the object unparseable, hence the strip.
CLAIM=$(gc hook --claim --json 2>/dev/null | tr -d '\000-\037')

BEAD=$(printf '%s' "$CLAIM" | jq -r '.bead_id // ""' 2>/dev/null || printf '')
if [ -z "$BEAD" ]; then
    # No work, or a claim that did not come back as a readable result. Both
    # mean the same thing to the caller and neither leaves anything held.
    echo "action=drain reason=no-work"
    exit 1
fi

GROUP=$(printf '%s' "$CLAIM" | jq -r '.continuation_group // ""' 2>/dev/null || printf '')

# Work it when the groups match, when this is the session's first claim, or
# when either side has no group to compare. The unknown cases resolve to WORK
# on purpose: releasing a turn this session cannot prove is foreign would be a
# strand dressed as a fix, and the pre-existing behaviour is the safe fallback.
if [ -z "$CURRENT_GROUP" ] || [ -z "$GROUP" ] || [ "$GROUP" = "$CURRENT_GROUP" ]; then
    echo "action=work bead=$BEAD group=$GROUP"
    exit 0
fi

# Foreign group. Put back everything this claim assigned, then drain — header.

# release_turn <bead-id> — the three ordered writes, then the read-back that
# decides. Every write is attempted even after one fails, so a bead is never
# left half-cleared, and a failed write is sticky: the read must ALSO agree
# before a turn counts as returned.
release_turn() {
    _id="$1"
    _ok=1
    gc bd update "$_id" --unset-metadata gc.session_id --unset-metadata gc.session_name >/dev/null 2>&1 || _ok=0
    gc bd update "$_id" --status=open >/dev/null 2>&1 || _ok=0
    gc bd update "$_id" --assignee="" >/dev/null 2>&1 || _ok=0

    # Trust the read, not the writes: a partial release still holds the turn.
    STATE=$(gc bd show "$_id" --json 2>/dev/null | tr -d '\000-\037' \
            | jq -r 'if type=="array" then "\(.[0].status // "")|\(.[0].assignee // "")" else "|" end' 2>/dev/null || printf '')
    case "$STATE" in
        "open|") ;;                   # back in the pool
        *)       _ok=0 ;;
    esac
    [ "$_ok" = "1" ]
}

# The claimed turn FIRST, then every sibling the same claim vacuumed onto this
# session. Order preserved and duplicates dropped, so the claimed bead is still
# the first thing put back even when `gc` also names it in the sibling list.
RELEASE_IDS=$(printf '%s' "$CLAIM" | jq -r '
    ([.bead_id // empty] + (.continuation_assigned // []))
    | map(select(type == "string" and . != ""))
    | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)
    | .[]' 2>/dev/null || printf '')
# A claim we could not re-read is still a claim: fall back to the turn we know.
[ -z "$RELEASE_IDS" ] && RELEASE_IDS="$BEAD"

RELEASED=1
UNRELEASED=""
# The turn to NAME if the set does not all go back. It must be one this session
# still HOLDS, which is not always the claimed one: the loop releases the named
# turn first, so a clean release there followed by a stuck sibling would other-
# wise emit a bead that is already open and unassigned. First failure wins, and
# because the named turn is tried first that is still `$BEAD` whenever `$BEAD`
# itself is stuck — the single-turn behaviour is unchanged.
HELD_TURN=""
for _turn in $RELEASE_IDS; do
    if ! release_turn "$_turn"; then
        RELEASED=0
        [ -z "$HELD_TURN" ] && HELD_TURN="$_turn"
        UNRELEASED="${UNRELEASED:+$UNRELEASED }$_turn(${STATE:-unreadable})"
    fi
done

if [ "$RELEASED" = "0" ]; then
    # Could not put it all back. Working a still-held turn out of group is a
    # legible surprise the sitting can open by naming; draining now would
    # strand whatever is still held, which is the silent one nobody sees.
    echo "$PROG: could not release $UNRELEASED back to the pool; working $HELD_TURN rather than stranding it" >&2
    echo "action=work bead=$HELD_TURN group=$GROUP reason=unreleasable"
    exit 0
fi

echo "action=drain reason=out-of-group bead=$BEAD group=$GROUP"
exit 1
