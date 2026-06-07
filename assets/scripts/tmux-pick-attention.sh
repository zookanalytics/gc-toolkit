#!/bin/sh
# tmux-pick-attention.sh — Gas City attention-board picker (pick-a-row → land).
#
# Usage: tmux-pick-attention.sh [--city-path <path>]
#
# The board half of the bead-universe loop, bound to a sibling of the
# live-session picker (prefix+S stays "what's running"; this is "what
# needs me"). Phase 3 of the Bead-Universe Operating Model (bead
# tk-qkags; design Key Component 4, Interface "board loop").
#
# Reads the ranked board from `gc-attention.sh --json` (cached, so a
# glance is sub-second) and renders it as a tmux display-menu. Picking a
# row runs `gc-attention.sh open <bead>`, which resumes-or-materializes
# that bead's resident host and lands the operator in the conversation —
# one keystroke from "I see the row" to "I'm in the advanced universe."
#
# Liveness drives how a row opens, using the `live` field the board
# already computes (alias==bead-id join over `gc session list`):
#   ● hot   — host is live: open in the FOREGROUND, an instant reattach.
#   ◐ warm  — host suspended: open in the BACKGROUND (run-shell -b) so the
#   · cold  — no host yet:    seconds-long resume/materialize never freezes
#                             the tmux server; the host's status indicator
#                             shows it coming up, then it lands.
#
# --city-path is the absolute path of the city this binding belongs to —
# baked in by tmux-bindings.sh at install time so `gc`'s city discovery
# is deterministic even though the key fires from tmux's bare env (the
# same rationale as tmux-pick-session.sh).
set -e

CITY_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --city-path) CITY_PATH="${2:-}"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }
TAB="$(printf '\t')"

# sq <string> — POSIX shell-quote $1 for safe embedding in a sh -c body
# (same helper as tmux-pick-session.sh). The script + city paths are
# interpolated into the bound run-shell body; without sh-level quoting a
# path with whitespace or shell metacharacters would mis-route the open.
sq() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

SCRIPT="$(readlink -f "$0" 2>/dev/null || echo "$0")"
ATTN="$(dirname "$SCRIPT")/gc-attention.sh"
[ -x "$ATTN" ] || { gcmux display-message -d 4000 "attention: gc-attention.sh not found"; exit 0; }

# Make `gc`'s city discovery deterministic from tmux's bare env: export
# the baked city path and cd into it so `gc rig/convoy/session list`
# (and the open path's `gc session new`) resolve the right city.
if [ -n "$CITY_PATH" ]; then
    export GC_CITY_PATH="$CITY_PATH"
    cd "$CITY_PATH" 2>/dev/null || true
fi

# Cap at the hotkey alphabet (a-z0-9 = 36) so every row is one keystroke.
BOARD=$(sh "$ATTN" --json --limit=36 2>/dev/null || printf '[]')
COUNT=$(printf '%s' "$BOARD" | jq 'length' 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

if [ "$COUNT" -eq 0 ]; then
    gcmux display-message -d 4000 "attention board: nothing needs you. (Nothing floats.)"
    exit 0
fi

# Per-row command prefix: cd into the city so the open path resolves it.
CMD_PREFIX=""
[ -n "$CITY_PATH" ] && CMD_PREFIX="cd $(sq "$CITY_PATH") && "
SQ_ATTN=$(sq "$ATTN")

# One TSV row per anchor: live, severity, id, rig, title, frontier. (The
# severity band already carries the kind signal — FLAGGED vs HIGH/etc.)
ROWS=$(printf '%s' "$BOARD" | jq -r '
    .[] | [(.live//"cold"), (.severity//"?"), .id, (.rig//"?"),
           ((.title//"")[0:38]), ((.frontier//"")[0:34])] | @tsv')

HOTKEYS="abcdefghijklmnopqrstuvwxyz0123456789"
set --
i=1
while IFS="$TAB" read -r live sev id rig title frontier; do
    [ -n "$id" ] || continue
    case "$live" in
        hot)  glyph="●" ;;
        warm) glyph="◐" ;;
        *)    glyph="·" ;;
    esac
    label=$(printf '  %s %-8s %-11s [%s] %s — %s  ' "$glyph" "$sev" "$id" "$rig" "$title" "$frontier")

    # Hot host: foreground reattach (instant). Warm/cold: background the
    # resume/materialize so a slow cold-start can't freeze the server.
    if [ "$live" = "hot" ]; then runflag=""; else runflag="-b"; fi
    cmd="run-shell $runflag \"${CMD_PREFIX}${SQ_ATTN} open ${id}\""

    if [ "$i" -le ${#HOTKEYS} ]; then
        key=$(printf '%s' "$HOTKEYS" | cut -c"$i")
    else
        key=""
    fi
    set -- "$@" "$label" "$key" "$cmd"
    i=$((i + 1))
done <<ROWS_EOF
$ROWS
ROWS_EOF

# Trailing action: refresh the board (re-gather, bypassing the cache).
set -- "$@" "" "" ""
set -- "$@" "  [ refresh ]  " "r" "run-shell -b \"${CMD_PREFIX}${SQ_ATTN} board --refresh >/dev/null 2>&1\""

gcmux display-menu -T " Attention — what needs you " -x C -y C -- "$@"
