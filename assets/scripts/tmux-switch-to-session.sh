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

# Wait for the session to register before switching to it. A freshly-created
# bead-host's cold start can exceed 10s (observed up to ~60s), so the budget is
# GC_TMUX_SWITCH_TIMEOUT seconds (default 45), polled every 0.25s. The old fixed
# ~10s budget abandoned slow cold starts (tk-8v5j0).
timeout_s="${GC_TMUX_SWITCH_TIMEOUT:-45}"
case "$timeout_s" in ''|*[!0-9]*) timeout_s=45 ;; esac
sleep_per=0.25
attempts=$(( timeout_s * 4 ))
i=0
while [ "$i" -lt "$attempts" ]; do
    if gcmux has-session -t "$SESSION" 2>/dev/null; then
        gcmux switch-client -t "$SESSION"
        exit 0
    fi
    i=$((i + 1))
    sleep "$sleep_per"
done

echo "tmux-switch-to-session.sh: session '$SESSION' did not register within ${timeout_s}s" >&2
exit 1
