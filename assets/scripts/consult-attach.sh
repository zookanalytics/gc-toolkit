#!/bin/sh
# consult-attach.sh — Switch the active tmux client to a consult-host session.
# Usage: consult-attach.sh <session-alias>
#
# Called by concierge after spawning a consult-host session
# (`gc session new consult-host --alias consult-<bead> --no-attach`).
# Switches the currently-attached overseer client into the new session
# so the conversation begins immediately. Blocks until the target tmux
# session registers (cold-start latency); fails if it does not appear
# within the wait budget.
#
# Honors $GC_TMUX_SOCKET so the call lands on the Gas City tmux server
# rather than the default user server.
set -e

SESSION="$1"
[ -z "$SESSION" ] && { echo "consult-attach.sh: missing session alias" >&2; exit 1; }

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# Wait up to ~10s for the session to register. `gc session new --no-attach`
# returns once the runtime has accepted the request, but the tmux session
# may not exist for a short window after.
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

echo "consult-attach.sh: session '$SESSION' did not register within 10s" >&2
exit 1
