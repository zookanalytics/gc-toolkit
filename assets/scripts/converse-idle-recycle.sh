#!/usr/bin/env bash
# converse-idle-recycle.sh — reclaim the session slot of an AUTO-OPENED converse
# sitting the operator never attended.
#
# converse-reap ends a sitting whose visit has CLOSED; this ends the harder half
# it names out of scope — a sitting whose visit is still OPEN because the operator
# walked away before any sign-off (spec tk-2i4bde, tk-20rfkt). Idle time cannot
# tell that from a live hold, which is why converse carries idle_timeout="0"; the
# discriminator here is instead whether the operator ever ATTACHED. An auto-opened
# sitting is speculative until then — gc-visit-open guessed the operator wanted to
# talk — so it is recyclable UNTIL first attach and a normal held sitting after.
#
# The pack has only the LIVE `.attached` boolean from `gc session list`; there is
# no was-ever-attached history. So this pass IS the history: the first pass that
# sees a sitting attached stamps gc.auto_open_attended_at on its visit, promoting
# it to held for good; a later detach never makes it recyclable again. A sitting
# that ages past the recycle timeout without that stamp is reclaimed.
#
# Reclaim returns the visit to PARKED (session closed, visit reopened + unassigned,
# auto-open marks cleared, gc.routed_to=human kept) — the operator's topic stays on
# the board for a manual engage; only the speculative slot is freed. It is NOT a
# dismiss: the conversation was never had, so the visit is not closed.
#
# Two hard rules, both converse-reap's: never touch an ATTACHED sitting (the pack
# cannot see typed text, and draining a pane that has some is the operator's one
# hard no), and an unreadable probe reclaims NOTHING.
#
# Config (env, safe default, per-rig variation — Principle 2):
#   CONVERSE_AUTO_OPEN_RECYCLE_SECS  idle budget before reclaim (default 900).
#
# Usage:
#   converse-idle-recycle.sh            promote/reclaim, print one summary line
#   converse-idle-recycle.sh --dry-run  report the plan, change nothing
# Exit: 0 did the work or nothing to do · 1 the session listing was unreadable · 2 usage
# Caller: the converse-idle-recycle cooldown order.
set -uo pipefail

PROG="${0##*/}"
GC="${CONVERSE_IDLE_RECYCLE_GC:-gc}"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$PROG: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }

RECYCLE_SECS="${CONVERSE_AUTO_OPEN_RECYCLE_SECS:-900}"
case "$RECYCLE_SECS" in ''|*[!0-9]*) RECYCLE_SECS=900 ;; esac

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but LF
# go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting consumers
# downstream split jq's own @tsv.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
now_epoch() { date -u +%s; }
# iso_epoch <iso8601> — epoch seconds, or empty when it will not parse. An
# unparseable stamp is never treated as "old": the caller keeps on empty.
iso_epoch() { date -u -d "$1" +%s 2>/dev/null || printf ''; }

# db_for_bead <id> — the .beads path for the id's rig, resolved by prefix the way
# the board's write verbs do. This pass is city-scoped, so a write must be pinned
# to the visit's own store rather than trusting an up-walk from cwd.
RIGS_JSON=""
db_for_bead() {
    [ -n "$RIGS_JSON" ] || RIGS_JSON="$("$GC" rig list --json 2>/dev/null | scrub || printf '')"
    printf '%s' "$RIGS_JSON" \
        | jq -r --arg p "${1%%-*}" '((.rigs // []) | map(select((.prefix // "") == $p)) | .[0].path // "")' 2>/dev/null || printf ''
}

# Every session, every state. A non-object answer, or one without a .sessions
# array, is a listing we cannot trust — do nothing and say so with exit 1.
sessions_json="$("$GC" session list --state all --json 2>/dev/null)" || sessions_json=""
if ! printf '%s' "$sessions_json" | jq -e 'type=="object" and (.sessions|type=="array")' >/dev/null 2>&1; then
    echo "$PROG: could not read the session list — doing nothing" >&2
    exit 1
fi

# Candidate rows as <sid>\t<vid>\t<attached>. Unlike converse-reap this does NOT
# filter on .attached: an attached sitting is promoted, an unattached one may be
# reclaimed, so both are carried and the loop branches. engage qualifies the alias
# as <rig>/<pack>.<visit-id>, so the visit id is the final dot-segment.
candidates="$(printf '%s' "$sessions_json" | jq -r '
    .sessions[]?
    | select(((.template // "") | test("converse")))
    | select((.closed // false) == false)
    | select((.alias // "") != "")
    | [ .id, ((.alias) | sub("^.*\\."; "")), ((.attached // false) | tostring) ]
    | @tsv')"

NOW=$(now_epoch)
promoted=0; recycled=0; kept=0; skipped=0
recycled_lines=""

while IFS=$'\t' read -r sid vid attached; do
    [ -n "$sid" ] || continue
    # The alias' final segment must look like a bead id, or it is not a visit
    # reference this pass can resolve.
    if ! [[ "$vid" =~ ^[a-z]+-[a-z0-9]+$ ]]; then
        skipped=$((skipped + 1)); continue
    fi

    db=$(db_for_bead "$vid")
    db_args=""; [ -n "$db" ] && [ -d "$db/.beads" ] && db_args="--db $db/.beads"

    # Read the visit; an answer that is not JSON is an unreadable probe — skip.
    # shellcheck disable=SC2086  # $db_args expands to 0 or 2 space-free fields
    show="$("$GC" bd show "$vid" $db_args --json 2>/dev/null)"
    if ! printf '%s' "$show" | jq -e . >/dev/null 2>&1; then
        skipped=$((skipped + 1)); continue
    fi
    row="$(printf '%s' "$show" | scrub | jq -c --arg v "$vid" '
        if type=="array" then ([ .[] | select((.id // "") == $v) ] | first)
        elif (.id // "") == $v then .
        else null end')"
    if [ "$row" = "null" ] || [ -z "$row" ]; then
        # Gone or unresolved: converse-reap reclaims the closed/gone case; leave it.
        skipped=$((skipped + 1)); continue
    fi

    kind="$(printf '%s' "$row" | jq -r '(.metadata.task_kind) // ""')"
    status="$(printf '%s' "$row" | jq -r '.status // ""')"
    auto_opened="$(printf '%s' "$row" | jq -r '(.metadata["gc.auto_opened"]) // ""')"
    attended_at="$(printf '%s' "$row" | jq -r '(.metadata["gc.auto_open_attended_at"]) // ""')"
    opened_at="$(printf '%s' "$row" | jq -r '(.metadata["gc.auto_opened_at"]) // ""')"

    # Only auto-opened, still-live visits are ours. A non-visit alias, a visit that
    # was not auto-opened (a manual engage or a board pick), or a closed/gone one
    # (converse-reap's) is none of our business.
    if [ "$kind" != "visit" ] || [ "$auto_opened" != "1" ]; then
        skipped=$((skipped + 1)); continue
    fi
    case "$status" in open|in_progress) ;; *) skipped=$((skipped + 1)); continue ;; esac

    # Attached now: the operator is here. Promote on first sight (stamp the history
    # the runtime does not keep) and never reclaim — the hard no.
    if [ "$attached" = "true" ]; then
        if [ -z "$attended_at" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                promoted=$((promoted + 1))
            # shellcheck disable=SC2086
            elif "$GC" bd update "$vid" $db_args --set-metadata "gc.auto_open_attended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1; then
                promoted=$((promoted + 1))
            else
                skipped=$((skipped + 1))
                echo "$PROG: could not promote attended sitting $sid (visit $vid) — retried next pass" >&2
            fi
        else
            kept=$((kept + 1))
        fi
        continue
    fi

    # Unattached. Already promoted (attended once) => a normal held sitting; leave it.
    if [ -n "$attended_at" ]; then
        kept=$((kept + 1)); continue
    fi

    # Never attended: reclaim once it has aged past the budget. An unparseable or
    # missing open-stamp is never treated as old — keep and let a human sort it.
    started=$(iso_epoch "$opened_at")
    if [ -z "$started" ]; then
        kept=$((kept + 1)); continue
    fi
    age=$((NOW - started))
    if [ "$age" -lt "$RECYCLE_SECS" ]; then
        kept=$((kept + 1)); continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        recycled=$((recycled + 1))
        recycled_lines="${recycled_lines}  ${sid} (visit ${vid}, idle ${age}s)
"
        continue
    fi

    # Close the session (free the slot), then return the visit to parked. The three
    # bead writes are the ordered release converse-claim proved: bd refuses
    # --assignee "" on an in_progress bead, and metadata writes bypass that guard,
    # so unset the session pointers and auto-open marks, reopen, then unassign.
    # gc.routed_to is left as "human" on purpose — that is the board predicate, so
    # the topic stays pickable. Trust the read-back, not the writes.
    if ! "$GC" session close "$sid" >/dev/null 2>&1; then
        skipped=$((skipped + 1))
        echo "$PROG: could not close idle sitting $sid (visit $vid) — left for the next pass" >&2
        continue
    fi
    # shellcheck disable=SC2086  # $db_args expands to 0 or 2 space-free fields
    "$GC" bd update "$vid" $db_args \
        --unset-metadata gc.session_id --unset-metadata gc.session_name \
        --unset-metadata gc.auto_opened --unset-metadata gc.auto_opened_at \
        --set-metadata "gc.auto_open_recycled_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    "$GC" bd update "$vid" $db_args --status=open >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    "$GC" bd update "$vid" $db_args --assignee="" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    parked=$("$GC" bd show "$vid" $db_args --json 2>/dev/null | scrub \
        | jq -r 'if type=="array" then "\(.[0].status // "")|\(.[0].assignee // "")" else "|" end' 2>/dev/null || printf '')
    case "$parked" in
        "open|") : ;;
        *) echo "$PROG: closed sitting $sid but visit $vid did not fully re-park (read '$parked'); a held or liveness pass will finish it" >&2 ;;
    esac
    recycled=$((recycled + 1))
    recycled_lines="${recycled_lines}  ${sid} (visit ${vid}, idle ${age}s)
"
done <<< "$candidates"

verb="recycled"; [ "$DRY_RUN" -eq 1 ] && verb="would recycle"
echo "$PROG: $verb $recycled idle auto-opened sittings (budget ${RECYCLE_SECS}s), promoted $promoted attended, kept $kept, skipped $skipped"
[ -n "$recycled_lines" ] && printf '%s' "$recycled_lines"
exit 0
