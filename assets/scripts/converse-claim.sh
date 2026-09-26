#!/bin/sh
# converse-claim.sh — claim one turn FOR A CONTINUATION GROUP, put back
# anything that belongs to a different one (`gc hook --claim` has no group
# filter, so re-claim-within-the-group is claim-then-release until it grows
# one), and name a turn this session is ALREADY working so the caller neither
# restarts it nor ends it.
# Usage:
#   converse-claim.sh                 first claim of a session: any group
#   converse-claim.sh <current-group> re-claim: only this group is workable
#   converse-claim.sh --sh [group]    the verdict as eval-able assignments
# Output: one key=value line; exit status says what to do:
#   action=work   bead=<id> group=<g> [reason=unreleasable]    exit 0
#   action=hold   bead=<id> group=<g> reason=already-underway [adopted=<ids>] exit 3
#   action=finish bead=<id> group=<g> reason=outcome-stamped [adopted=<ids>] exit 4
#   action=drain  reason=no-work                               exit 1
#   action=drain  reason=out-of-group bead=<id> group=<g>      exit 1
# With --sh the same verdict prints as shell assignments to eval —
#   ACTION=<verb> VISIT=<bead> SUBJECT=<group> REASON=<reason>; the exit status
#   is unchanged and the verdict line still shows on stderr.
# On the HOLD verdict it ALSO prints, to stderr, a premise-gate diagnostic
# `premise-gate: BEGAN=<yes|unknown|recheck|no>`: existing_assignment cannot
# tell a sitting that reached its hold from a claim that died before step 2 ever
# re-checked the premise, so the mechanism that reads the trace a real hold
# leaves (gc.hold_demand on the visit) lives here. The stdout verdict is
# unchanged; BEGAN is the diagnostic the caller reads to pick its step-1 rule.
# The RELEASE is the load-bearing half: never drain on a turn not put back
# (a held visit waits for witness patrol otherwise), release the WHOLE claim
# (the vacuumed continuation_assigned siblings too), and when part of the set
# will not go back, work the first still-HELD turn instead of draining.
# The HOLD verdict is load-bearing for the opposite reason: it is the only
# answer that neither works a live sitting nor ends it. FINISH covers the one
# case a hold gets wrong: a sitting whose record is complete and whose close
# never ran looks exactly like a live one from the claim alone, so the outcome
# stamp is read off the bead and the close is completed here.
# Caller: the converse prompt's claim loop.
set -u

# The one definition of what subject a visit covers (its tracks-edge identity,
# gc.continuation_group stamp as fallback), shared with gc-helm.sh, converse-fold
# .sh and the sweeps. Exposes $VISIT_IDENTITY_JQ. The recovery below stays scoped
# to task_kind=visit — tracks is not a visit-only edge, so a non-visit must not
# borrow a group from it.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=visit-identity.sh
. "$HERE/visit-identity.sh" || { echo "converse-claim: cannot source visit-identity.sh from $HERE" >&2; exit 3; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# >>> eval-safe-quote
# --sh output is eval'd by the caller, and its ACTION/VISIT/SUBJECT/REASON carry
# claim- and metadata-derived data. Single-quote every emitted value so eval
# reads it as one literal string: a group like `g;rm -rf x` stays data, never
# shell syntax. An embedded single quote becomes the '\'' idiom.
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# <<< eval-safe-quote

PROG="converse-claim"

usage() {
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1-}" in
    -h|--help) usage; exit 0 ;;
esac

# --sh: emit the verdict as eval-able shell assignments rather than the default
# key=value line, so a caller can `eval "$(converse-claim.sh --sh "$SUBJECT")"`
# instead of parsing it. This runs the claim ONCE, in the default mode, and
# translates its one stdout line; the child's stderr (the BEGAN diagnostic and
# the group-recovery note) flows straight through, and the verdict is echoed
# there too so the caller still reads it. ACTION / VISIT / SUBJECT / REASON are
# the four the caller branches on; adopted stays on the verdict echo.
if [ "${1-}" = "--sh" ]; then
    shift
    _CG="${1-}"
    _OUT=$("$0" "$@")
    _RC=$?
    printf '%s: %s\n' "$PROG" "$_OUT" >&2
    _A=$(printf '%s' "$_OUT" | sed -n 's/.*action=\([^ ]*\).*/\1/p')
    _V=$(printf '%s' "$_OUT" | sed -n 's/.*bead=\([^ ]*\).*/\1/p')
    _G=$(printf '%s' "$_OUT" | sed -n 's/.*group=\([^ ]*\).*/\1/p')
    _R=$(printf '%s' "$_OUT" | sed -n 's/.*reason=\([^ ]*\).*/\1/p')
    # A finish names a sitting being disposed of, not entered, so its group is
    # not this thread's — keep the caller's group across it.
    [ "$_A" = "finish" ] && _G="$_CG"
    printf 'ACTION=%s\nVISIT=%s\nSUBJECT=%s\nREASON=%s\n' "$(shq "$_A")" "$(shq "$_V")" "$(shq "$_G")" "$(shq "$_R")"
    exit "$_RC"
fi

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

REASON=$(printf '%s' "$CLAIM" | jq -r '.reason // ""' 2>/dev/null || printf '')
GROUP=$(printf '%s' "$CLAIM" | jq -r '.continuation_group // ""' 2>/dev/null || printf '')

# One read of the claimed bead answers both questions the claim result cannot:
# the continuation group its stamp may have dropped, and whether the turn is
# already carrying a final outcome. A read that fails leaves this empty, and
# both derivations below then give the answer they give for a recording that
# is simply absent.
BEAD_JSON=$(gc bd show "$BEAD" --json 2>/dev/null | scrub)

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
    GROUP=$(printf '%s' "$BEAD_JSON" \
        | jq -r "$VISIT_IDENTITY_JQ"'if type == "array" then (.[0] // {}) else {} end
                 | select(((.metadata // {}).task_kind // "") == "visit")
                 | visit_subject' 2>/dev/null || printf '')
    [ -n "$GROUP" ] && echo "$PROG: the claim reported no continuation group for $BEAD; recovered '$GROUP' from its tracks edge" >&2
fi

# A turn already in_progress under this session's identity is a sitting
# UNDERWAY, not an offer to accept or refuse. `gc hook --claim` reports that
# case as reason=existing_assignment and runs no claim CAS
# (hookClaimExistingAssignment, cmd/gc/cmd_hook_claim.go), so the sitting's
# status and assignee stand as the turn that opened it left them. A turn the
# claim actually started reports `claimed` or `ready_assignment`, so the two
# are distinct on the wire, and no argument from the caller is needed to tell
# them apart.
#
# Adoption is not free of writes. The result path that reports the reason also
# re-stamps the session identity on the visit (gc.session_id, gc.session_name,
# gc.work_branch, and gc.claimed_at when it is absent), which is how a respawn
# becomes the recorded holder of a hold it inherited. It also pre-assigns open
# same-group siblings, but only when the visit carries gc.root_bead_id
# alongside the group, and names them in continuation_assigned; molecule
# instantiation stamps that root and filing a visit does not, so on a visit the
# set arrives empty. Those siblings are later turns of the sitting's own group,
# so the hold reports them and keeps them: putting a turn of the conversation
# being held back in the pool is the same destruction by a third door.
#
# Neither other verdict is safe on a live sitting: `work` sends the caller back
# through a visit loop that ends at the close, and `drain` acks a stop while
# the operator may still be reading the thread.
#
# This precedes the group guard because the guard's remedy is the release, and
# releasing a turn mid-sitting is the same destruction by the other door. A
# turn only reaches in_progress under this identity because an earlier turn of
# this session decided to work it, so the guard has had its say.
#
# A hold is wrong for one shape of that claim, and it is the shape a sitting
# ends in. A visit records its ending in writes that are not atomic: the
# prompt posts the sign-off, then stamps gc.outcome, reads it back, and
# closes. Every path that stamps the field closes immediately after it
# (the fold in step 1, the moot/benign exit in step 2, the sign-off path in
# step 7), so a visit still open while carrying one is a sitting whose record
# is complete and whose close did not run. Held, it is offered back to its own
# session for as long as the pool has demand, and the close never runs. The
# item keeps whatever headline it has: the hold stamped one when the sitting
# began, and a closing takeaway that failed on the way out is not recovered
# here.
#
# Keyed on task_kind=visit for the reason the group recovery is: gc.outcome is
# a general key — a dog warrant and a graph.v2 step both carry it — and closing
# some other bead the pool handed this role would be destruction. Keyed on
# existing_assignment because that is the claim shape the strand produces: the
# visit stays in_progress under the identity that stamped it. A stamped visit
# arriving as a FRESH claim means something else reopened it, which is a
# different question than this arm answers.
OUTCOME=$(printf '%s' "$BEAD_JSON" \
    | jq -r 'if type == "array" then (.[0] // {}) else {} end
             | select(((.metadata // {}).task_kind // "") == "visit")
             | (((.metadata // {})["gc.outcome"]) // "") | tostring' 2>/dev/null || printf '')

# finish_close <bead-id> <outcome> — close a visit whose record is complete.
# bd's close-authority guard compares the assignee against an actor derived
# from the session name and refuses the two renderings of one identity, so a
# refusal escalates to --force the way gc-helm.sh's dismiss does; the holder
# being overridden here is this session. The READ decides, not either exit
# status — a close that reported success and left the visit open is the strand
# again, one door over.
finish_close() {
    _why="stranded after gc.outcome=$2 was stamped; close completed by $PROG"
    gc bd close "$1" --reason "$_why" >/dev/null 2>&1 \
        || gc bd close "$1" --reason "$_why" --force >/dev/null 2>&1
    gc bd show "$1" --json 2>/dev/null | scrub \
        | jq -e 'if type == "array" then ((.[0].status // "") == "closed") else false end' \
          >/dev/null 2>&1
}

if [ "$REASON" = "existing_assignment" ]; then
    ADOPTED=$(printf '%s' "$CLAIM" | jq -r '
        (.continuation_assigned // [])
        | map(select(type == "string" and . != ""))
        | join(",")' 2>/dev/null || printf '')
    if [ -n "$OUTCOME" ]; then
        if finish_close "$BEAD" "$OUTCOME"; then
            echo "$PROG: $BEAD carried gc.outcome=$OUTCOME with no close; closed it here" >&2
        else
            # Still a finish: sending the caller back to waiting on a
            # sitting that is over is the defect itself, and the caller's own
            # close is the backstop for whatever refused here.
            echo "$PROG: $BEAD carries gc.outcome=$OUTCOME and would not close; close it by hand: gc bd close $BEAD --force" >&2
        fi
        echo "action=finish bead=$BEAD group=$GROUP reason=outcome-stamped${ADOPTED:+ adopted=$ADOPTED}"
        exit 4
    fi
    # A hold covers two claim shapes existing_assignment cannot tell apart: a
    # sitting that reached its hold, and a claim that died before step 2 ever
    # re-checked the premise. The trace only a real hold leaves is gc.hold_demand,
    # which step 5 stamps on THIS visit before it waits; it is attributable
    # because it lives on the visit, so a sibling holding the same item cannot
    # forge it. Absence is three answers, not one: a visit bead that will not read
    # is UNKNOWN and must not license a close; no key but an open demand still on
    # the item is a hold that predates the key or a sibling's on the shared item
    # (RECHECK); only a clean read with no key and no open item demand is a claim
    # that plainly never began (NO). The yes/unknown/recheck/no RULES are the
    # caller's; this reports the reading.
    if ! printf '%s' "$BEAD_JSON" | jq -e 'type == "array" and ((.[0].id // "") != "")' >/dev/null 2>&1; then
        BEGAN=unknown
    elif printf '%s' "$BEAD_JSON" | jq -e '(.[0].metadata["gc.hold_demand"] // "") != ""' >/dev/null 2>&1; then
        BEGAN=yes
    else
        HD_ITEM=$(printf '%s' "$BEAD_JSON" | jq -r '.[0].metadata.stall_root // ""' 2>/dev/null || printf '')
        HD_ITEM="${HD_ITEM:-$GROUP}"
        # --include-gates: a demand can be a human gate (issue_type=gate), which
        # `bd list` hides by default; without it an open gate-demand on the item
        # reads as absent, and a hold with no gc.hold_demand is then misjudged NO
        # (a dead pre-step-2 claim) when it is a live wait the caller must RECHECK.
        HD_LIST=$(gc bd list --status=open,in_progress --include-gates --json --limit=0 2>/dev/null | scrub)
        if printf '%s' "$HD_LIST" | jq -e --arg i "$HD_ITEM" 'type == "array" and any(.[]?; (.metadata["gc.demand_for"] // "") == $i)' >/dev/null 2>&1; then
            BEGAN=recheck
        elif printf '%s' "$HD_LIST" | jq -e 'type == "array"' >/dev/null 2>&1; then
            BEGAN=no
        else
            BEGAN=recheck
        fi
    fi
    echo "premise-gate: BEGAN=$BEGAN" >&2
    echo "action=hold bead=$BEAD group=$GROUP reason=already-underway${ADOPTED:+ adopted=$ADOPTED}"
    exit 3
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
