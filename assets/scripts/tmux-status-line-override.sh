#!/bin/sh
# tmux-status-line-override.sh — Replace status-left and status-right
# with gc-toolkit's customizations.
#
# Usage: tmux-status-line-override.sh <session> <agent> <config-dir>
#
# Runs from gc-toolkit's [global].session_live AFTER gastown's
# tmux-theme.sh. The pack-load order is documented in
# gascity/internal/config/pack.go:1450 ("Collect globals: included
# globals first, then this pack's own"), and runSessionLive iterates
# the merged slice in that order (runtime/tmux/adapter.go:824). The
# net effect: gastown sets the default theme (status-left = "$icon
# $AGENT" capped at 25 cells, status-right pointing at gastown's
# status-line.sh), then this script rewrites both halves:
#
#   status-right -> points at gc-toolkit-status-line.sh, which adds
#                   composable title and indicator slots.
#   status-left  -> "$icon $short ", where $short strips the
#                   "<pack>." prefix and the "-adhoc-<hex>" thread
#                   suffix from $AGENT so long thread names don't
#                   get truncated by the 25-cell length cap.
#
# Failure mode: best-effort. Errors are swallowed so a missing tmux
# server or absent session can't fail session bring-up.

SESSION="${1:?missing session}"
AGENT="${2:?missing agent}"
CONFIGDIR="${3:?missing config-dir}"

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# Point status-right at gc-toolkit's status-line script. Mirrors
# gastown's tmux-theme.sh format ("<script-output> %H:%M") so the
# time slot continues to appear in the same position.
gcmux set-option -t "$SESSION" status-right \
    "#($CONFIGDIR/assets/scripts/gc-toolkit-status-line.sh $AGENT) %H:%M" \
    2>/dev/null || true

# Replace status-left's "$icon $AGENT" with "$icon $short". The
# pack-prefix and "-adhoc-<hex>" thread suffix carry no useful
# information once the agent fits inside its tier theme, and they
# routinely push the left side past the 25-cell length cap (e.g.
# "gc-toolkit.mechanik-thread-adhoc-a36bc330b9" -> "Mechanik focu…").
# Two parameter expansions strip both:
#   gc-toolkit.mechanik                          -> mechanik
#   gc-toolkit.mechanik-thread-adhoc-a36bc330b9  -> mechanik-thread
#   gc-toolkit.polecat-1                         -> polecat-1
#   mayor                                        -> mayor (unchanged)
short="${AGENT##*.}"
short="${short%-adhoc-*}"

# Tier icon. Mirrors gastown's tmux-theme.sh exactly (rig / scope /
# pool / default) so the icon stays consistent with the bg/fg theme
# gastown already applied to this session.
case "$SESSION" in
    *--*)       icon="⛏" ;;
    *__*)       icon="🏛" ;;
    *-[0-9]*)   icon="🌊" ;;
    *)          icon="●" ;;
esac

gcmux set-option -t "$SESSION" status-left "$icon $short " \
    2>/dev/null || true

# Defensive sweep of stale slot files from crashed writers. /tmp
# survives session lifetime but accumulates across reboots; writers
# clean up via trap on EXIT, but a SIGKILL'd or aborted-during-setup
# writer can leave a file behind. 60-minute TTL is generous —
# in-flight spawns finish in seconds; an hour-old indicator is
# always stale.
find /tmp -maxdepth 1 \( -name 'gc-status-*.indicator' -o -name 'gc-title-*' \) \
    -mmin +60 -delete 2>/dev/null || true
