#!/usr/bin/env bash
# converse-reap.sh — end a converse sitting once its VISIT has closed.
#
# Converse is spawn-on-engagement (tk-4abhrt): `gc-helm engage` spawns a manual
# converse-<model> session (origin=manual) bound to a visit, and the session's
# --alias IS that visit id. A manual session is exempt from every pool backstop,
# so nothing in the runtime cycles it. Both endings the config names — the
# agent's sign-off and the operator's `gc-helm dismiss` — close the VISIT on the
# belief that closing the visit ends the sitting. It does not: the manual session
# outlives its closed visit, holding a max_active_sessions slot (default 2) and,
# when the operator has walked away, leaving a closed visit beside a live pane.
# This pass is the reap those two endings assume.
#
# A converse session whose visit is CLOSED (or gone) is settled: the hold it
# protected is over, so there is nothing left to protect. Close the session.
#
# The one visit this pass will NOT reap under is one still OPEN — that is a live
# hold — and the one session it will not reap is one an operator is ATTACHED to.
# The pack cannot see a half-typed reply in the composer (that needs the
# runtime's InputAreaState, gc-ze774), and the operator's standing ruling is that
# draining a pane with typed text is a hard no. Attachment is the only signal the
# pack has for "someone is at this pane", so an attached sitting is left for its
# own sign-off or a dismiss even when its visit already reads closed. The
# unattached settled sittings — the leaked slots — are what this reaps. Ending a
# sitting whose visit is still OPEN (the operator walked away before any sign-off)
# is the harder case, deferred to tk-20rfkt; this pass never touches it.
#
# Fully mechanical: `gc session list` + one `gc bd show` per converse session +
# `gc session close` for the settled ones. No agent, no formula, no pool.
#
# Bias: an unreadable probe reaps NOTHING. A session whose visit cannot be read,
# whose alias is not a bead id, or whose bound bead is not a visit is left alone —
# the pass only ever ends a sitting it can prove is settled.
#
# Usage:
#   converse-reap.sh            reap settled sittings, print one summary line
#   converse-reap.sh --dry-run  report the plan, close nothing
# Exit: 0 reaped or nothing to do · 1 the session listing was unreadable · 2 usage
# Caller: the converse-reap cooldown order. See specs/tk-2i4bde/converse-reap.md.
set -uo pipefail

PROG="${0##*/}"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$PROG: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }

GC="${CONVERSE_REAP_GC:-gc}"

# Every session, every state. `gc bd show` resolves a bead across ledgers on its
# own, so the visit lookup is store-agnostic and this pass reads the whole city.
# A non-object answer, or one without a .sessions array, is a listing we cannot
# trust — reap nothing and say so with exit 1.
sessions_json="$("$GC" session list --state all --json 2>/dev/null)" || sessions_json=""
if ! printf '%s' "$sessions_json" | jq -e 'type=="object" and (.sessions|type=="array")' >/dev/null 2>&1; then
    echo "$PROG: could not read the session list — reaping nothing" >&2
    exit 1
fi

# Candidate rows, one per line as <session-id>\t<visit-id>: a converse template,
# not already closed, NOT attached, and carrying an alias. engage sets the alias
# to the visit id, qualified as <rig>/<pack>.<visit-id>, so the id is the final
# dot-segment. A session with no alias was not engage-bound to a visit and is
# none of our business.
candidates="$(printf '%s' "$sessions_json" | jq -r '
    .sessions[]?
    | select(((.template // "") | test("converse")))
    | select((.closed // false) == false)
    | select((.attached // false) == false)
    | select((.alias // "") != "")
    | [ .id, ((.alias) | sub("^.*\\."; "")) ]
    | @tsv')"

reaped=0; kept=0; skipped=0
reaped_lines=""

while IFS=$'\t' read -r sid vid; do
    [ -n "$sid" ] || continue

    # The alias' final segment must look like a bead id, or the alias is not a
    # visit reference this pass can resolve.
    if ! [[ "$vid" =~ ^[a-z]+-[a-z0-9]+$ ]]; then
        skipped=$((skipped + 1)); continue
    fi

    # Read the visit. An empty answer, a non-JSON answer, or a command failure is
    # an unreadable probe: never a reason to reap.
    show="$("$GC" bd show "$vid" --json 2>/dev/null)" || show=""
    if ! printf '%s' "$show" | jq -e . >/dev/null 2>&1; then
        skipped=$((skipped + 1)); continue
    fi

    # The bead whose id is exactly this visit, whether bd answered with an array
    # (one or more matches) or the single object it returns when nothing matched.
    # empty => bd answered and there is no such bead: the visit is GONE.
    row="$(printf '%s' "$show" | jq -c --arg v "$vid" '
        if type=="array" then ([ .[] | select((.id // "") == $v) ] | first)
        elif (.id // "") == $v then .
        else null end')"

    verdict=keep
    if [ "$row" = "null" ] || [ -z "$row" ]; then
        verdict=gone
    else
        kind="$(printf '%s' "$row" | jq -r '(.metadata.task_kind) // ""')"
        status="$(printf '%s' "$row" | jq -r '.status // ""')"
        if [ "$kind" != "visit" ]; then
            # The alias resolves to something that is not a visit — cannot prove
            # this session's sitting is settled.
            skipped=$((skipped + 1)); continue
        fi
        [ "$status" = "closed" ] && verdict=closed
    fi

    if [ "$verdict" = "keep" ]; then
        kept=$((kept + 1)); continue
    fi

    reaped_lines="${reaped_lines}  ${sid} (visit ${vid} ${verdict})
"
    if [ "$DRY_RUN" -eq 1 ]; then
        reaped=$((reaped + 1)); continue
    fi
    if "$GC" session close "$sid" >/dev/null 2>&1; then
        reaped=$((reaped + 1))
    else
        # The close is the whole job; a session that would not close is left for
        # the next pass, and reported so a standing failure is visible.
        skipped=$((skipped + 1))
        echo "$PROG: could not close settled sitting $sid (visit $vid $verdict) — left for the next pass" >&2
    fi
done <<< "$candidates"

verb="closed"; [ "$DRY_RUN" -eq 1 ] && verb="would close"
echo "$PROG: $verb $reaped settled converse sittings (visit closed or gone), kept $kept held, skipped $skipped"
[ -n "$reaped_lines" ] && printf '%s' "$reaped_lines"
exit 0
