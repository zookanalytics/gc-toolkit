#!/bin/sh
# tmux-spawn-thread.sh — Spawn a Role+Thread of the current pane's named agent.
# Usage: tmux-spawn-thread.sh <config-dir> [first-message]
#
# Bound to `prefix + a` ("ask") by tmux-bindings.sh, which wires it
# behind tmux's `command-prompt`. The operator gets a single-line
# bottom-bar prompt; on Enter, this script is invoked with the
# message as `$2`. Blank input is allowed — the thread spawns
# without a seed message in that case.
#
# The slow part of the work (`gc session new` + first-message nudge)
# is backgrounded so command-prompt returns control to the operator's
# pane immediately. Errors from the background subshell surface via
# `tmux display-message` at the status bar.
#
# Threads are registered agents: they appear in `gc session list`,
# survive `gc session reset` of the canonical, and carry the full
# role persona. The canonical handles routed mail and routed work;
# threads are operator-spawned only.
#
# Idempotent role mapping:
#   mayor             -> mayor-thread
#   mechanik          -> mechanik-thread
#   mechanik-thread   -> mechanik-thread        (another instance, not -thread-thread)
#   mechanik-thread-1 -> mechanik-thread        (pool member -> sibling)
#   polecat-1         -> polecat-thread         (no template -> soft fail)
#
# Limitation: tmux's command-prompt %% substitution is textual with
# no shell quoting. If the operator's input contains an unescaped
# `"` or `\`, the shell parse of the run-shell command will break.
# Multi-line input is also out of scope. For quote- and newline-safe
# input we'd need a tmux set-buffer + save-buffer chain (deferred
# follow-up).
set -eu

CONFIGDIR="${1:?missing config-dir}"
THREAD_SPAWN_MESSAGE="${2:-}"

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# 1. Resolve the active session. Prefer the focused client's session
#    (the operator who pressed prefix + a); fall back to the run-shell
#    context's session if no client is currently associated.
SESSION=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)
[ -z "$SESSION" ] && SESSION=$(gcmux display-message -p '#{session_name}')

# 2. Resolve the agent name. Prefer GC_AGENT from the session
#    environment; fall back to deriving from the session name suffix
#    (gascity uses `<rig>__<agent>` for tmux session names).
AGENT=$(gcmux show-environment -t "$SESSION" GC_AGENT 2>/dev/null | sed -n 's/^GC_AGENT=//p')
[ -z "$AGENT" ] && AGENT=$(printf '%s' "$SESSION" | sed 's/.*__//')

if [ -z "$AGENT" ]; then
    gcmux display-message "thread spawn: cannot resolve current agent (no GC_AGENT, no parseable session name)"
    exit 1
fi

# 3. Derive the canonical role base from the qualified agent identity.
#    Strip everything up to and including the last "." (rig-prefix or
#    binding), then strip trailing "-<digits>" (pool member suffix) and
#    trailing "-thread" (already a thread). What remains is the role.
BARE=$(printf '%s' "$AGENT" | sed 's|.*\.||')
ROLE=$(printf '%s' "$BARE" | sed -E 's/-[0-9]+$//' | sed -E 's/-thread$//')
THREAD_TEMPLATE="${ROLE}-thread"

# 4. Verify a <role>-thread template exists. `gc prime --strict` exits
#    non-zero for "agent not found in city config", which is exactly
#    the missing-template case we want to surface as a soft failure.
#    Bare-name resolution (gascity/cmd/gc/cmd_session.go:539) matches
#    against the agent's Name field regardless of scope, so this works
#    for both city- and rig-scoped thread templates as long as the
#    <role>-thread name is unique in the city's agent set.
if ! gc prime --strict "$THREAD_TEMPLATE" >/dev/null 2>&1; then
    gcmux display-message "thread spawn: no '$THREAD_TEMPLATE' template for role '$ROLE'"
    exit 0
fi

# 5. Background the slow path. `gc session new` does controller cold-
#    start, worktree setup, and session bead creation — ~15s. If we
#    run it inline, the command-prompt's run-shell blocks the
#    operator's pane until that completes. Backgrounding the spawn
#    lets command-prompt return immediately; the operator gets their
#    pane back sub-second. Errors surface asynchronously via
#    display-message. We do NOT pass --alias: the runtime would
#    prefix it with the binding namespace (e.g. "thread-abc" ->
#    "<binding>.thread-abc"), and the un-prefixed value would not
#    resolve in the nudge below. The canonical session ID returned
#    by `gc session new` is what we route on.
(
    if ! SPAWN_OUT=$(gc session new "$THREAD_TEMPLATE" --no-attach 2>&1); then
        gcmux display-message "thread spawn failed: $SPAWN_OUT"
        exit 1
    fi
    SESSION_ID=$(printf '%s\n' "$SPAWN_OUT" | sed -n 's/^Session \([^ ]*\) created.*/\1/p' | head -1)
    if [ -z "$SESSION_ID" ]; then
        gcmux display-message "thread spawn: could not parse session id from gc output"
        exit 1
    fi
    if [ -n "$THREAD_SPAWN_MESSAGE" ]; then
        # --delivery=queue durably enqueues the nudge keyed on the
        # canonical session ID and returns immediately, so the
        # background subshell exits without waiting on claude
        # cold-start. The supervisor-side dispatcher scans open
        # session beads each pass and delivers the queued message
        # as soon as the new thread's provider is running; queue
        # persistence is independent of session state, so a target
        # still in `creating` is fine.
        if ! gc session nudge --delivery=queue "$SESSION_ID" "$THREAD_SPAWN_MESSAGE" >/dev/null 2>&1; then
            gcmux display-message "thread spawn: nudge to '$SESSION_ID' failed; session created but first message not delivered"
            exit 1
        fi
        gcmux display-message "spawned $THREAD_TEMPLATE ($SESSION_ID); seeded; prefix+S to switch"
    else
        gcmux display-message "spawned $THREAD_TEMPLATE ($SESSION_ID); no seed; prefix+S to switch"
    fi
) &
