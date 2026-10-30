#!/usr/bin/env bash
# converse-reap.sh — end a converse sitting once its conversation is over.
#
# A sitting is a manual converse-<model> session that `gc-helm engage` starts
# under the alias of the conversation it holds: the conversation task's id, or
# its `c-` fallback when the runtime refuses the bare id as an alias. Gas City
# does not end a manual session when its work closes, so a sitting ends its own
# session as soon as its conversation closes, and `gc-helm dismiss` stops the
# session that held the conversation it closes. This pass is the backstop for a
# session that outlives its conversation anyway: a stop that did not take, a
# conversation some other path closed, or one a sitting cut short handed back
# to the operator's queue (docs/warrants.md, Converse reap).
#
# A converse session is settled, and closed here, when the conversation its
# alias names has closed, is gone, or is back in the operator's queue (assigned
# to `human` and open), whether or not an operator is attached to it. Viewing a
# sitting does not keep it open: a client attached to it exits when its session
# ends, because each converse template sets detach-on-destroy on its own tmux
# session. A conversation its sitting still holds is a live sitting, and is
# kept.
#
# Two sessions are never closed, each for --min-age, the reap's own interval.
# One is younger than that. engage starts a session before it binds the
# conversation to it, so a session that young holding the alias of a
# conversation still in the queue may be a sitting about to take it. The other's
# conversation was written less than that ago. A sitting's sign-off writes the
# close or the hand-back to the queue, and the sitting records its last
# hand-back on the conversation on its next tool call, which the operator's tab
# prints once the session ends. A dismiss records no hand-back, so the interval
# also bounds that wait.
#
# Fully mechanical: `gc session list` + one `gc bd show` per candidate session +
# `gc session close` for the settled ones. No agent, no formula, no pool.
#
# Bias: an unreadable probe reaps NOTHING. A session whose conversation cannot
# be read, whose alias names no bead id, whose bead is no conversation, or whose
# settled conversation's last write time does not read is left alone: the pass
# only ever ends a sitting it can prove is settled.
#
# Usage:
#   converse-reap.sh [--min-age <seconds>]            reap, print one summary line
#   converse-reap.sh [--min-age <seconds>] --dry-run  report the plan, close nothing
#   --min-age defaults to 300, the converse-reap order's interval.
# Exit: 0 reaped or nothing to do · 1 the session list could not be read or the
#       candidate set could not be enumerated · 2 usage
# Caller: the converse-reap cooldown order.
set -uo pipefail

PROG="${0##*/}"
DRY_RUN=0
MIN_AGE=300
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --min-age) shift; case "${1:-}" in ''|*[!0-9]*) echo "$PROG: --min-age needs a whole number of seconds" >&2; exit 2 ;; esac
                   MIN_AGE="$1" ;;
        -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
# The one definition of a conversation's shape. Exposes $CONVERSATION_JQ.
# shellcheck source=conversation.sh
. "$HERE/conversation.sh" || { echo "$PROG: cannot source conversation.sh from $HERE" >&2; exit 1; }

GC="${CONVERSE_REAP_GC:-gc}"

# Every session, every state. `gc bd show` resolves a bead across ledgers on its
# own, so the conversation lookup is store-agnostic and this pass reads the
# whole city. A non-object answer, or one without a .sessions array, is a
# listing we cannot trust — reap nothing and say so with exit 1.
sessions_json="$("$GC" session list --state all --json 2>/dev/null)" || sessions_json=""
if ! printf '%s' "$sessions_json" | jq -e 'type=="object" and (.sessions|type=="array")' >/dev/null 2>&1; then
    echo "$PROG: could not read the session list — reaping nothing" >&2
    exit 1
fi

# Candidate rows, one per line as <session-id>\t<conversation-id>: a converse
# template, not already closed, older than --min-age, and carrying an alias.
# engage qualifies the alias as <rig>/<binding>.<alias>, so the alias is the
# final dot-segment, and a `c-` fallback names the id after its prefix. A
# session with no alias was not engage-bound to a conversation and is none of
# our business, and one whose creation time does not read cannot prove its age.
candidates="$(printf '%s' "$sessions_json" | jq -r --argjson age "$MIN_AGE" '
    .sessions[]?
    | select(((.template // "") | test("converse")))
    | select((.closed // false) == false)
    | select((.alias // "") != "")
    | select(((.created_at // "") | tostring | sub("\\.[0-9]+"; "") | fromdateiso8601?) as $t
             | $t != null and $t <= (now - $age))
    | ((.alias) | sub("^.*\\."; "")) as $tail
    | [ .id, (if ($tail | test("^c-[a-z]+-[a-z0-9]+$")) then ($tail | ltrimstr("c-")) else $tail end) ]
    | @tsv')"

reaped=0; kept=0; settling=0; skipped=0
reaped_lines=""

# Drive the loop from a checked, producer-named temp file rather than a `<<<`
# here-string. bash backs `<<<` with an implicit temp file; under disk pressure
# that file cannot be created, the redirection fails with no `set -e` to catch
# it, the loop runs zero times, and the summary below prints a reaped-nothing
# all-clear byte-identical to a healthy empty queue. A checked mktemp, a checked
# write, and a processed-equals-expected assertion each abort non-zero instead,
# so the order wrapper retries next pass rather than trusting a forged all-clear.
# Reading from the file keeps the loop in this shell, so the counters survive.
ROWS="$(mktemp "${TMPDIR:-/tmp}/gctk-converse-reap.XXXXXX" 2>/dev/null)" || {
    echo "$PROG: could not create a temp file to enumerate converse sittings — reaping nothing" >&2
    exit 1
}
trap 'rm -f "$ROWS" 2>/dev/null' EXIT
printf '%s\n' "$candidates" > "$ROWS" || {
    echo "$PROG: could not write the converse-sitting enumeration — reaping nothing" >&2
    exit 1
}
expected="$(grep -c . "$ROWS" 2>/dev/null || true)"; case "$expected" in ''|*[!0-9]*) expected=0 ;; esac
processed=0

while IFS=$'\t' read -r sid cid; do
    [ -n "$sid" ] || continue
    processed=$((processed + 1))

    # The alias' final segment must look like a bead id, or the alias is not a
    # conversation reference this pass can resolve.
    if ! [[ "$cid" =~ ^[a-z]+-[a-z0-9]+$ ]]; then
        skipped=$((skipped + 1)); continue
    fi

    # Read the conversation, capturing stdout and exit status SEPARATELY:
    # `gc bd show` exits non-zero for an id that resolves to nothing yet still
    # prints the not-found object that proves the conversation is GONE, so
    # stdout must survive a non-zero exit for that signature to be classified.
    # An answer that is not JSON at all — empty, or a garbled/failed read —
    # carries nothing to classify and is an unreadable probe: never reap.
    show="$("$GC" bd show "$cid" --json 2>/dev/null)"; show_rc=$?
    if ! printf '%s' "$show" | jq -e . >/dev/null 2>&1; then
        skipped=$((skipped + 1)); continue
    fi

    # The bead whose id is exactly this conversation, whether bd answered with
    # an array or the single object it returns for one id. A `gc bd show` row
    # spells an edge {dependency_type, id}; the shape rule reads the `gc bd list`
    # spelling {type, depends_on_id}, so the row is respelled before it is read.
    row="$(printf '%s' "$show" | jq -c --arg c "$cid" '
        (if type=="array" then ([ .[] | select((.id // "") == $c) ] | first)
         elif (.id // "") == $c then .
         else null end)
        | if . == null then null
          else .dependencies = [ (.dependencies // [])[]? | objects
                 | {type: ((.type // .dependency_type) // ""), depends_on_id: ((.depends_on_id // .id) // "")} ]
          end')"

    verdict=keep
    if [ "$row" = "null" ] || [ -z "$row" ]; then
        # No bead resolved. GONE only when bd said so with its not-found
        # signature: a non-zero exit carrying an object whose .error names no
        # matching issue (a deleted or purged conversation). Any other unmatched
        # payload — a store blip, an unexpected error shape — we cannot
        # classify, so it is left alone, not reaped.
        if [ "$show_rc" -ne 0 ] && printf '%s' "$show" | jq -e 'type=="object" and ((.error // "") | test("no issues found"))' >/dev/null 2>&1; then
            verdict=gone
        else
            skipped=$((skipped + 1)); continue
        fi
    else
        if ! printf '%s' "$row" | jq -e "$CONVERSATION_JQ"'conversation' >/dev/null 2>&1; then
            # The alias resolves to something that is not a conversation, so
            # nothing proves this session's sitting is settled.
            skipped=$((skipped + 1)); continue
        fi
        status="$(printf '%s' "$row" | jq -r '(.status // "") | ascii_downcase')"
        assignee="$(printf '%s' "$row" | jq -r '(.assignee // "") | tostring')"
        if [ "$status" = "closed" ]; then
            verdict=closed
        elif [ "$assignee" = "human" ] && [ "$status" = "open" ]; then
            verdict=queued
        fi
    fi

    if [ "$verdict" = "keep" ]; then
        kept=$((kept + 1)); continue
    fi

    # A settled conversation written less than --min-age ago may still be taking
    # its sitting's last hand-back, so its session waits a pass.
    if [ "$verdict" != gone ]; then
        quiet="$(printf '%s' "$row" | jq -r --argjson age "$MIN_AGE" '
            [ .updated_at, .closed_at ] | map(select(. != null) | tostring | sub("\\.[0-9]+"; "") | fromdateiso8601?) | max
            | if . == null then "unread" elif . <= (now - $age) then "quiet" else "recent" end' 2>/dev/null)"
        case "$quiet" in
            quiet) ;;
            recent) settling=$((settling + 1)); continue ;;
            *) skipped=$((skipped + 1)); continue ;;
        esac
    fi

    # Record the per-session line only once the sitting is actually gone. A close
    # that FAILS is reported on stderr and counted skipped; it must NOT land in the
    # reaped list, which is the summary's account of the sittings this pass closed,
    # and the close is the one operation this order performs. A dry run closes
    # nothing, so there the line is the plan.
    if [ "$DRY_RUN" -eq 1 ]; then
        reaped=$((reaped + 1))
    elif "$GC" session close "$sid" >/dev/null 2>&1; then
        reaped=$((reaped + 1))
    else
        skipped=$((skipped + 1))
        echo "$PROG: could not close settled sitting $sid (conversation $cid $verdict) — left for the next pass" >&2
        continue
    fi
    reaped_lines="${reaped_lines}  ${sid} (conversation ${cid} ${verdict})
"
done < "$ROWS"
rm -f "$ROWS"

# A loop that read fewer rows than were enumerated did not see the whole queue.
# Treat a short read like a failed enumeration: reap nothing, abort non-zero,
# retry next pass; never print the all-clear on a partial pass.
[ "$processed" -eq "$expected" ] || {
    echo "$PROG: read $processed of $expected candidate rows — reaping nothing" >&2
    exit 1
}

verb="closed"; [ "$DRY_RUN" -eq 1 ] && verb="would close"
echo "$PROG: $verb $reaped settled converse sittings (conversation closed, gone or back in the queue), kept $kept held, kept $settling settled within the last ${MIN_AGE}s, skipped $skipped"
[ -n "$reaped_lines" ] && printf '%s' "$reaped_lines"
exit 0
