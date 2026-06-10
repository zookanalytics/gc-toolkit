#!/bin/sh
# tmux-switch-to-session.sh — Switch the active tmux client to a session.
# Usage: tmux-switch-to-session.sh <session-alias>
#
# Switches the currently-attached client into the named session so the
# conversation begins immediately in the same client. Called after a
# spawn-or-resume (`gc session new … --no-attach` or equivalent tooling),
# which returns once the runtime accepts the request — but the tmux
# session may not exist for a short window after. Blocks until the target
# session registers (cold-start latency); fails if it does not appear
# within the wait budget.
#
# Honors $GC_TMUX_SOCKET so the call lands on the Gas City tmux server
# rather than the default user server.
set -e

SESSION="$1"
[ -z "$SESSION" ] && { echo "tmux-switch-to-session.sh: missing session alias" >&2; exit 1; }

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# Wait up to ~10s for the session to register before switching to it.
attempts=40
sleep_per=0.25
i=0
while [ "$i" -lt "$attempts" ]; do
    if gcmux has-session -t "$SESSION" 2>/dev/null; then
        gcmux switch-client -t "$SESSION"
        exit 0
    fi
    i=$((i + 1))
    sleep "$sleep_per"
done

echo "tmux-switch-to-session.sh: session '$SESSION' did not register within 10s" >&2
exit 1
