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

# sq <string> — POSIX shell-quote $1 for safe embedding in a sh -c body.
# Wraps in '...' with any internal ' broken out as '\''. The captured
# city path is interpolated into the bound run-shell body; without
# sh-level quoting, whitespace or shell metacharacters in the path
# would silently mis-route the picker's API call.
sq() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Capture the city path at install time. bind-key is server-wide and
# the binding fires from tmux's env (which doesn't carry Gas City's
# session env), so the picker can't rely on $GC_CITY_PATH being set
# when the user later presses the key. Baking the path into the
# binding makes the API city lookup deterministic.
CITY_PATH="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"

gcmux bind-key S run-shell "$CONFIGDIR/assets/scripts/tmux-pick-session.sh --city-path $(sq "$CITY_PATH")"

# Helm — the sibling of prefix+S. prefix+S answers "what's
# running"; prefix+b answers "what needs me": a ranked cross-rig board of
# OPEN anchors (epics, floating convoys, decisions, flagged beads). Pick a
# row and it resumes-or-materializes that bead's resident host and lands
# you in the conversation. Phase 3 of the Bead-Universe Operating Model
# (bead tk-qkags; design Key Component 4). See tmux-pick-helm.sh.
gcmux bind-key b run-shell "$CONFIGDIR/assets/scripts/tmux-pick-helm.sh --city-path $(sq "$CITY_PATH")"

# Operator-origin visit intake — type a message, get a durable, routed
# conversation on it. `command-prompt` opens the bottom-bar prompt; `%%%`
# parks the response in a paste buffer (escaping quotation marks) instead of
# splicing it into a command line, and tmux-visit-prompt.sh reads the buffer
# back. That indirection is load-bearing: the response is substituted as TEXT
# and the result is then PARSED as a tmux command, so a `;` or a `"` in a
# message spliced directly into `run-shell` mangles it — or executes part of
# it. Via the buffer the message crosses a process boundary untouched. The
# handler runs FOREGROUND so the fixed buffer name is serialised against the
# next press (a backgrounded read can lose a topic to the press behind it);
# it backgrounds the slow half itself. See tmux-visit-prompt.sh.
gcmux bind-key a command-prompt -p "visit topic: " \
    "set-buffer -b gc-visit-topic -- \"%%%\" ; run-shell \"$(sq "$CONFIGDIR/assets/scripts/tmux-visit-prompt.sh") $(sq "$CONFIGDIR")\""
