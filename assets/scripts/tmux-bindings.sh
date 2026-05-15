#!/bin/sh
# tmux-bindings.sh — Install Gas City tmux keybindings on the GC tmux socket.
# Usage: tmux-bindings.sh <config-dir>
#
# Called from pack.toml session_live, runs on every agent session start.
# bind-key is server-wide and idempotent; re-running just re-asserts.
set -e

CONFIGDIR="$1"
[ -z "$CONFIGDIR" ] && { echo "tmux-bindings.sh: missing config-dir" >&2; exit 1; }

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

gcmux bind-key S run-shell "$CONFIGDIR/assets/scripts/tmux-pick-session.sh"

# Spawn a thread of the current pane's role. Input handling (gum
# input in a tmux popup) lives in the script — see tmux-spawn-thread.sh.
gcmux bind-key a run-shell -b "$CONFIGDIR/assets/scripts/tmux-spawn-thread.sh $CONFIGDIR"
