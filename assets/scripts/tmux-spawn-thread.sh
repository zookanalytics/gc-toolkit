#!/bin/sh
# tmux-spawn-thread.sh — Spawn a Role+Thread of the current pane's named agent.
# Usage: tmux-spawn-thread.sh <config-dir>
#
# Bound to `prefix + a` ("ask") by tmux-bindings.sh. From inside a tmux
# session running an interactive named agent (mayor, mechanik), this
# opens a tmux popup asking for a first message, then spawns the
# corresponding <role>-thread as a registered city-scoped session.
# The first message is delivered via `gc session nudge --delivery=wait-idle`
# the moment the new thread is idle and ready to receive input.
#
# Threads are registered agents (unlike scratch clones): they appear in
# `gc session list`, survive `gc session reset` of the canonical, and
# carry the full role persona. The canonical handles routed mail and
# routed work; threads are operator-spawned only.
#
# Idempotent role mapping:
#   mayor             -> mayor-thread
#   mechanik          -> mechanik-thread
#   mechanik-thread   -> mechanik-thread        (another instance, not -thread-thread)
#   mechanik-thread-1 -> mechanik-thread        (pool member -> sibling)
#   polecat-1         -> polecat-thread         (no template -> soft fail)
#
# Two-phase via popup re-invoke:
#   Phase 1 (no THREAD_SPAWN_MESSAGE): open display-popup; the popup's
#     shell reads operator input via `read -r` (safe for any characters)
#     and re-execs this script with THREAD_SPAWN_MESSAGE in the env.
#   Phase 2 (THREAD_SPAWN_MESSAGE set): probe the template, spawn the
#     session, nudge the first message.
#
# Why a popup rather than tmux command-prompt: command-prompt's %%
# substitution is textual with no shell quoting, so any quote/dollar/space
# in operator input would break the wrapping command. The popup gives a
# real shell where `read -r` captures the input as a single safe string.
set -eu

CONFIGDIR="${1:?missing config-dir}"
SCRIPT_PATH="$0"

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# 1. Resolve the active session. Prefer the focused client's session
#    (the operator who pressed prefix + a); fall back to the run-shell
#    context's session if no client is currently associated. Mirrors
#    tmux-spawn-scratch.sh.
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

# 5. Phase 1 — open the popup to capture a first message, then re-exec
#    this script with THREAD_SPAWN_MESSAGE set. We pass the script path
#    and CONFIGDIR through the popup's shell command line at outer-shell
#    expansion time, so the popup's fresh shell can find them.
if [ -z "${THREAD_SPAWN_MESSAGE:-}" ]; then
    gcmux display-popup -E -B -w 80 -h 5 \
        "sh -c 'printf \"first message to $THREAD_TEMPLATE: \"; IFS= read -r msg; [ -z \"\$msg\" ] && exit 0; THREAD_SPAWN_MESSAGE=\"\$msg\" \"$SCRIPT_PATH\" \"$CONFIGDIR\"'"
    exit 0
fi

# Phase 2 — operator has supplied a first message.

# 6. Generate a short alias for the new thread session. "thread-<6 hex>"
#    gives ~16M of namespace, plenty for parallel threads in one
#    operator session. The runtime promotes it to a workspace-unique
#    handle.
RAND=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')
ALIAS="thread-${RAND}"

# 7. Spawn the thread session, no-attach so the operator can stay in
#    the originating pane. Errors surface via display-message — the
#    operator sees them in the status bar.
if ! ERR=$(gc session new "$THREAD_TEMPLATE" --alias "$ALIAS" --no-attach 2>&1); then
    gcmux display-message "thread spawn failed: $ERR"
    exit 1
fi

# 8. Seed the first message. --delivery=wait-idle waits for the new
#    session's provider to report ready before injecting input, so the
#    message is not lost to a still-initializing terminal.
if ! gc session nudge --delivery=wait-idle "$ALIAS" "$THREAD_SPAWN_MESSAGE" >/dev/null 2>&1; then
    gcmux display-message "thread spawn: nudge to '$ALIAS' failed; session created but first message not delivered"
    exit 1
fi

gcmux display-message "spawned $THREAD_TEMPLATE (alias $ALIAS); use prefix+S to switch"
