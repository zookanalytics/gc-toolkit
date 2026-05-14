#!/bin/sh
# tmux-spawn-thread.sh — Spawn a Role+Thread of the current pane's named agent.
# Usage: tmux-spawn-thread.sh <config-dir>
#
# Bound to `prefix + a` ("ask") by tmux-bindings.sh. From inside a tmux
# session running an interactive named agent (mayor, mechanik), this
# opens a tmux popup asking for a first message, then spawns the
# corresponding <role>-thread as a registered city-scoped session.
# The first message is durably queued via `gc session nudge --delivery=queue`
# so the spawn call returns immediately; the supervisor-side dispatcher
# drains the queue into the new thread as soon as its provider is running.
#
# Threads are registered agents: they appear in `gc session list`,
# survive `gc session reset` of the canonical, and carry the full role
# persona. The canonical handles routed mail and routed work; threads
# are operator-spawned only.
#
# Idempotent role mapping:
#   mayor             -> mayor-thread
#   mechanik          -> mechanik-thread
#   mechanik-thread   -> mechanik-thread        (another instance, not -thread-thread)
#   mechanik-thread-1 -> mechanik-thread        (pool member -> sibling)
#   polecat-1         -> polecat-thread         (no template -> soft fail)
#
# Two-phase via popup re-invoke:
#   Phase 1 (no THREAD_SPAWN_MESSAGE_FILE): open display-popup running the
#     operator's $EDITOR on a tempfile; on save+quit the popup's shell
#     re-execs this script with THREAD_SPAWN_MESSAGE_FILE pointing at the
#     tempfile.
#   Phase 2 (THREAD_SPAWN_MESSAGE_FILE set): read the file (empty = cancel),
#     probe the template, spawn the session, nudge the first message.
#
# Why an editor rather than tmux command-prompt or in-popup `read`:
# command-prompt's %% substitution is textual with no shell quoting, so any
# quote/dollar/space in operator input would break the wrapping command.
# An in-popup `read -r` looked simpler but in practice the popup terminal's
# line discipline doesn't reliably deliver Enter to `read`, so the operator
# can't submit. An editor on a tempfile sidesteps both: multi-line is
# natural, submit is the editor's save+quit gesture, and a tempfile path
# survives env-var passing where a multi-line value would not.
set -eu

CONFIGDIR="${1:?missing config-dir}"
SCRIPT_PATH="$0"

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

# 5. Phase 1 — open the popup running ${EDITOR:-vi} on a tempfile, then
#    re-exec this script with THREAD_SPAWN_MESSAGE_FILE pointing at it.
#    We pass the script path and CONFIGDIR through the popup's shell at
#    outer-shell expansion time, so the popup's fresh shell can find them.
#    The popup is bordered + sized for multi-line drafting; the title
#    advertises the submit/cancel gestures.
if [ -z "${THREAD_SPAWN_MESSAGE_FILE:-}" ]; then
    TMPF=$(mktemp -t thread-spawn.XXXXXX)
    gcmux display-popup -E -w 100 -h 30 -T " first message to $THREAD_TEMPLATE — save+quit to send, exit empty to cancel " \
        "sh -c '${EDITOR:-vi} \"$TMPF\"; THREAD_SPAWN_MESSAGE_FILE=\"$TMPF\" \"$SCRIPT_PATH\" \"$CONFIGDIR\"'"
    exit 0
fi

# Phase 2 — operator has supplied a first-message tempfile path. Empty file
# means cancel; non-empty contents are the message body (multi-line OK).
if [ ! -s "$THREAD_SPAWN_MESSAGE_FILE" ]; then
    rm -f "$THREAD_SPAWN_MESSAGE_FILE"
    gcmux display-message "thread spawn cancelled: empty message"
    exit 0
fi
THREAD_SPAWN_MESSAGE=$(cat "$THREAD_SPAWN_MESSAGE_FILE")
rm -f "$THREAD_SPAWN_MESSAGE_FILE"

# 6. Spawn the thread session, no-attach so the operator can stay in
#    the originating pane. Errors surface via display-message — the
#    operator sees them in the status bar. We do NOT pass --alias: the
#    runtime would prefix it with the binding namespace (e.g.
#    "thread-abc" -> "<binding>.thread-abc"), and the un-prefixed value
#    would not resolve in the nudge below. The canonical session ID
#    returned by `gc session new` is what we route on.
if ! SPAWN_OUT=$(gc session new "$THREAD_TEMPLATE" --no-attach 2>&1); then
    gcmux display-message "thread spawn failed: $SPAWN_OUT"
    exit 1
fi

# 7. Parse the canonical session ID from the success line:
#    "Session <id> created from template <template> ..."
SESSION_ID=$(printf '%s\n' "$SPAWN_OUT" | sed -n 's/^Session \([^ ]*\) created.*/\1/p' | head -1)
if [ -z "$SESSION_ID" ]; then
    gcmux display-message "thread spawn: could not parse session id from gc output"
    exit 1
fi

# 8. Seed the first message. --delivery=queue durably enqueues the
#    nudge keyed on the canonical session ID and returns immediately,
#    so the popup closes and the operator gets their pane back without
#    waiting on claude cold-start (~20-30s). The supervisor-side
#    dispatcher scans open session beads each pass and delivers the
#    queued message as soon as the new thread's provider is running;
#    queue persistence is independent of session state, so a target
#    still in `creating` is fine.
if ! gc session nudge --delivery=queue "$SESSION_ID" "$THREAD_SPAWN_MESSAGE" >/dev/null 2>&1; then
    gcmux display-message "thread spawn: nudge to '$SESSION_ID' failed; session created but first message not delivered"
    exit 1
fi

gcmux display-message "spawned $THREAD_TEMPLATE ($SESSION_ID); use prefix+S to switch"
