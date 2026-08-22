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

# Foreign group. Put it back before draining — see the header.
RELEASED=1
gc bd update "$BEAD" --unset-metadata gc.session_id --unset-metadata gc.session_name >/dev/null 2>&1 || RELEASED=0
gc bd update "$BEAD" --status=open >/dev/null 2>&1 || RELEASED=0
gc bd update "$BEAD" --assignee="" >/dev/null 2>&1 || RELEASED=0

# Trust the read, not the writes: a partial release still holds the turn.
STATE=$(gc bd show "$BEAD" --json 2>/dev/null | tr -d '\000-\037' \
        | jq -r 'if type=="array" then "\(.[0].status // "")|\(.[0].assignee // "")" else "|" end' 2>/dev/null || printf '')
case "$STATE" in
    "open|") ;;                       # back in the pool
    *)       RELEASED=0 ;;
esac

if [ "$RELEASED" = "0" ]; then
    # Could not put it back. Working it out of group is a legible surprise the
    # sitting can open by naming; stranding it is a silent one nobody sees.
    echo "$PROG: could not release $BEAD back to the pool (state: ${STATE:-unreadable}); working it rather than stranding it" >&2
    echo "action=work bead=$BEAD group=$GROUP reason=unreleasable"
    exit 0
fi

echo "action=drain reason=out-of-group bead=$BEAD group=$GROUP"
exit 1
