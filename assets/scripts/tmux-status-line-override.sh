#!/bin/sh
# tmux-status-line-override.sh — SET the full gc-toolkit status bar.
#
# Usage: tmux-status-line-override.sh <session> <agent> <config-dir>
#
# Runs from [global].session_live on every agent session start. Standalone:
# no upstream theme runs first (the gastown import is gone), so this sets
# everything the bar needs — lengths, style, interval, and both halves:
#   status-left  -> "$icon $short " ($short strips the "<pack>." prefix and
#                   the "-adhoc-<hex>" suffix so the 25-cell cap never
#                   truncates a real name)
#   status-right -> "#(<gc-toolkit-status-line.sh> <agent> <city-path>) %H:%M"
# The city path is baked in at install time: tmux interpolates #() from its
# own env, which does not carry the Gas City session env.
# Failure mode: best-effort — errors are swallowed so a missing tmux server
# or absent session cannot fail session bring-up.

SESSION="${1:?missing session}"
AGENT="${2:?missing agent}"
CONFIGDIR="${3:?missing config-dir}"

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# sq <string> — POSIX shell-quote for safe embedding in the #() body.
sq() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

CITY_PATH="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"

# Tier icon + bar colour, keyed on the session-name shape (rig worktree /
# scoped / pool member / singleton).
case "$SESSION" in
    *--*)       icon="⛏"; style="bg=colour130,fg=colour231" ;;
    *__*)       icon="🏛"; style="bg=colour61,fg=colour231" ;;
    *-[0-9]*)   icon="🌊"; style="bg=colour24,fg=colour231" ;;
    *)          icon="●"; style="bg=colour238,fg=colour250" ;;
esac

short="${AGENT##*.}"
short="${short%-adhoc-*}"

# The full bar. status-right-length 80 is what gc-toolkit-status-line.sh's
# byte budget (BUDGET=72 plus " %H:%M") is sized against; status-interval 30
# keeps the per-pane hook/mail/curl probes to ~2/minute (it is a MAX — tmux
# still re-evaluates #() on every redraw, which is why the helper caches).
gcmux set-option -t "$SESSION" status on 2>/dev/null || true
gcmux set-option -t "$SESSION" status-style "$style" 2>/dev/null || true
gcmux set-option -t "$SESSION" status-left-length 25 2>/dev/null || true
gcmux set-option -t "$SESSION" status-right-length 80 2>/dev/null || true
gcmux set-option -t "$SESSION" status-left "$icon $short " 2>/dev/null || true
gcmux set-option -t "$SESSION" status-right \
    "#($CONFIGDIR/assets/scripts/gc-toolkit-status-line.sh $AGENT $(sq "$CITY_PATH")) %H:%M" \
    2>/dev/null || true
gcmux set-option -t "$SESSION" status-interval 30 2>/dev/null || true

# Sweep stale indicator files from crashed writers (writers clean up via
# trap on EXIT; a SIGKILL'd one leaves its file behind).
find /tmp -maxdepth 1 \( -name 'gc-status-*.indicator' -o -name 'gc-title-*' \) \
    -mmin +60 -delete 2>/dev/null || true
