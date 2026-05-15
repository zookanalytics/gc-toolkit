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

# Stash the prompt input in a tmux buffer (tmux's own quoting rules,
# not shell) so apostrophes in common contractions like "let's" parse
# cleanly instead of breaking the shell-quoted run-shell argument.
# The spawn script reads + deletes the buffer.
gcmux bind-key a command-prompt -p "thread msg (Enter; blank = no seed):" \
    "{ set-buffer -b gc-thread-msg \"%%\" ; run-shell '$CONFIGDIR/assets/scripts/tmux-spawn-thread.sh $CONFIGDIR' }"
