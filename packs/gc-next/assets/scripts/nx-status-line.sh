#!/bin/sh
# nx-status-line.sh — gc-next's single-writer status bar. (Brand: one
# script owns the whole bar — theme, composable title slot, indicator
# slot, %H:%M — no base theme to override; spec §2.)
#
# GATED during staging (spec §1): inert unless GC_NX_STATUS=1, so a city
# loading gc-toolkit and gc-next together never has two writers of
# status-right. The gate is removed at cutover stage 5.
#
# Usage: nx-status-line.sh <session> <agent> <config-dir>
set -eu

case "${GC_NX_STATUS:-}" in
  1|true|yes|on) : ;;
  *) exit 0 ;;
esac

SESSION="${1:?session}"
AGENT="${2:?agent}"
CONFIG_DIR="${3:?config-dir}"

command -v tmux >/dev/null 2>&1 || exit 0

# Whole-bar ownership: tier-tinted left status carries the agent, right
# status carries the composable title + indicator slots and the clock.
# Slots are plain tmux user options so any tool can fill them:
#   @nx_title      — the session's current focus (self-rename shape)
#   @nx_indicator  — a short glyph slot (hold, gating, chain state)
tmux set-option -t "$SESSION" status-style "bg=colour236,fg=colour250" 2>/dev/null || exit 0
tmux set-option -t "$SESSION" status-left " #S ${AGENT:+· $AGENT }" 2>/dev/null || true
tmux set-option -t "$SESSION" status-right "#{@nx_indicator} #{@nx_title} %H:%M " 2>/dev/null || true
exit 0
