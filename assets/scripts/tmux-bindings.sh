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

# tq <string> — tmux-quote $1 for a command string tmux parses again, the way
# confirm-before parses the command it runs on y. Wraps in "..." with any
# internal \, " or $ backslash-escaped, so an sq-quoted body survives that
# parse intact.
tq() {
    printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"$]/\\&/g')"
}

# Capture the city path at install time. bind-key is server-wide, and a
# bound command runs with the tmux server's environment plus the pressed
# session's own, so $GC_CITY_PATH is set only when the key is pressed in a
# Gas City session's pane. Baking the path into the binding makes the API
# city lookup deterministic.
CITY_PATH="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"

gcmux bind-key S run-shell "$CONFIGDIR/assets/scripts/tmux-pick-session.sh --city-path $(sq "$CITY_PATH")"

# Helm — the sibling of prefix+S. prefix+S answers "what's running";
# prefix+b answers "what needs me": the operator's own queue, oldest first,
# rendered from `helm-svc board --json`. Pick a row and it engages that bead —
# `gc-helm engage` spawns a converse sitting on demand, which you attach from
# prefix+S. See tmux-pick-helm.sh.
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

# prefix+A — raise a brand-new topic and converse about it now. Capital A, the
# sibling of prefix+a: where prefix+a files a bead for triage, this one opens a
# conversation on a subject that has no bead yet. It runs `gc-helm engage
# --new-subject` in a NEW window rather than a `run-shell` popup, because engage
# is a real interactive prompt — rig, subject, model — and tmux's one-line
# command-prompt cannot carry a subject plus a menu. The city path is baked in
# for the same reason the pickers bake it: a key pressed outside a Gas City
# session's pane carries no city in its environment. See tmux-new-subject.sh.
gcmux bind-key A new-window "$(sq "$CONFIGDIR/assets/scripts/tmux-new-subject.sh") $(sq "$CONFIGDIR") --city-path $(sq "$CITY_PATH")"

# prefix+X — end the converse sitting in view: the keystroke for `gc-helm
# dismiss`. Capital X, the sibling of tmux's own prefix+x: that key asks before
# killing the pane, this one asks before ending the sitting the pane holds.
# confirm-before guards against a stray key, because a dismissed sitting's
# session is closed once the operator leaves it. The script refuses any pane
# that is not a converse sitting and never types into the pane. See
# tmux-dismiss-sitting.sh.
#
# confirm-before expands formats in its command and parses it again before
# running it, so the run-shell body is quoted for both layers, sh by sq and
# tmux by tq, and names no format. The script reads the pressed session itself.
gcmux bind-key X confirm-before -p "dismiss this converse sitting? (y/n)" \
    "run-shell -b $(tq "$(sq "$CONFIGDIR/assets/scripts/tmux-dismiss-sitting.sh") $(sq "$CONFIGDIR") --city-path $(sq "$CITY_PATH")")"
