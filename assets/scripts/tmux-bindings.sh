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

# Helm — the sibling of prefix+S. prefix+S answers "what's running";
# prefix+b answers "what needs me": the operator's own queue, oldest first,
# rendered from `helm-svc board --json`. Pick a row and it files a VISIT on that
# bead, which a converse session holds for you. See tmux-pick-helm.sh.
gcmux bind-key b run-shell "$CONFIGDIR/assets/scripts/tmux-pick-helm.sh --city-path $(sq "$CITY_PATH")"

# prefix+B is the city overview — every anchor ranked together. It is a separate
# key rather than the same one because the two answer different questions, and
# only the queue answers the one a person presses a key to ask. Same script,
# same pick-a-row behavior, `--all` selects the wider set.
gcmux bind-key B run-shell "$CONFIGDIR/assets/scripts/tmux-pick-helm.sh --city-path $(sq "$CITY_PATH") --all"

# Operator-origin visit intake — type a message, get a durable, routed
# conversation on it. Input handling (a `gum write` popup) lives in the
# script; the key just runs it, which is the shape this binding had before
# threads were retired. `command-prompt` held it for exactly one commit
# (tk-bn1oi) and is SINGLE-LINE by construction, so the operator could file a
# sentence and nothing longer (tk-7z8c6). Restoring the popup restores the
# input surface without disturbing where the message goes.
#
# `-b` is not decoration: the popup is modal and stays open for as long as
# the operator is typing, and a foreground `run-shell` would hold tmux's
# command queue — the whole server — open for that entire time. Nothing is
# lost by backgrounding it now that the handler reads its message from a
# per-press draft file instead of one shared paste buffer, so presses never
# order against each other. That draft is also what
# survives a failed intake (tk-w4dp4). See tmux-visit-prompt.sh.
gcmux bind-key a run-shell -b "$(sq "$CONFIGDIR/assets/scripts/tmux-visit-prompt.sh") $(sq "$CONFIGDIR")"
