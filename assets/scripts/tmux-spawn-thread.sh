#!/bin/sh
# tmux-spawn-thread.sh — Spawn a Role+Thread of the current pane's named agent.
# Usage: tmux-spawn-thread.sh <config-dir>
#
# Bound to `prefix + a` ("ask") by tmux-bindings.sh, which wires it
# behind tmux's `command-prompt`. The operator gets a single-line
# bottom-bar prompt; on Enter, tmux stashes the input in a buffer
# named `gc-thread-msg` and invokes this script. Blank input is
# allowed — the thread spawns without a seed message in that case.
#
# The slow part of the work (`gc session new` + first-message nudge
# + creating->active poll) is backgrounded so command-prompt returns
# control to the operator's pane immediately. While the background
# runs, the operator's session shows a `[spawning ...]` / `[starting
# ...]` indicator in status-right so they don't stare at a blank
# pane. Final outcome (ready / stalled / error) surfaces via a 5- to
# 10-second `tmux display-message`.
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
# Quoting limitations: the binding stashes input via tmux
# `set-buffer "%%"`, whose tmux double-quote rules tolerate
# apostrophes ("let's", "I'm", "don't") but still break on a literal
# `"` or `\` in the prompt input. If you need either character in a
# first message, spawn without a seed (just press Enter at the
# prompt) and then send the real first message via
# `gc session nudge <session-id> "..."` — shell quoting there is
# yours to control. Multi-line input is out of scope (tmux
# command-prompt is single-row by design).
set -eu

CONFIGDIR="${1:?missing config-dir}"

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# 1. Read the first-message payload from the tmux buffer the binding
#    stashed it in, then delete the buffer so a follow-up spawn does
#    not inherit stale input. Missing/empty buffer means "no seed."
THREAD_SPAWN_MESSAGE=$(gcmux save-buffer -b gc-thread-msg - 2>/dev/null || true)
gcmux delete-buffer -b gc-thread-msg 2>/dev/null || true

# 2. Resolve the active session. Prefer the focused client's session
#    (the operator who pressed prefix + a); fall back to the run-shell
#    context's session if no client is currently associated.
SESSION=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)
[ -z "$SESSION" ] && SESSION=$(gcmux display-message -p '#{session_name}')

# 3. Resolve the agent name. Prefer GC_AGENT from the session
#    environment; fall back to deriving from the session name suffix
#    (gascity uses `<rig>__<agent>` for tmux session names).
AGENT=$(gcmux show-environment -t "$SESSION" GC_AGENT 2>/dev/null | sed -n 's/^GC_AGENT=//p')
[ -z "$AGENT" ] && AGENT=$(printf '%s' "$SESSION" | sed 's/.*__//')

if [ -z "$AGENT" ]; then
    gcmux display-message "thread spawn: cannot resolve current agent (no GC_AGENT, no parseable session name)"
    exit 1
fi

# 4. Derive the canonical role base from the qualified agent identity.
#    Strip everything up to and including the last "." (rig-prefix or
#    binding), then strip trailing "-<digits>" (pool member suffix) and
#    trailing "-thread" (already a thread). What remains is the role.
BARE=$(printf '%s' "$AGENT" | sed 's|.*\.||')
ROLE=$(printf '%s' "$BARE" | sed -E 's/-[0-9]+$//' | sed -E 's/-thread$//')
THREAD_TEMPLATE="${ROLE}-thread"

# 5. Verify a <role>-thread template exists. `gc prime --strict` exits
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

# 6. Background the slow path. `gc session new` does controller cold-
#    start, worktree setup, and session bead creation — ~15s. The
#    creating->active transition adds seconds-to-minutes after that
#    (reconciler pre_start fetches + rebases the worktree, then
#    starts the claude provider; once the provider is observed
#    running, state flips to `active`). If we run it inline, the
#    command-prompt's run-shell blocks the operator's pane until
#    that completes. Backgrounding lets command-prompt return
#    immediately; the operator gets their pane back sub-second.
#
#    While the background runs, we set status-right on the
#    operator's session so they see a persistent in-flight indicator
#    instead of silence — `[spawning <name>...]` during `gc session
#    new`, then `[starting <name>...]` while we poll for `active`.
#    The final outcome (ready / stalled / error) surfaces via a 5-
#    to 10-second `tmux display-message`.
#
#    We do NOT pass --alias to `gc session new`: the runtime would
#    prefix it with the binding namespace (e.g. "thread-abc" ->
#    "<binding>.thread-abc"), and the un-prefixed value would not
#    resolve in the nudge below. The canonical session ID returned
#    by `gc session new` is what we route on.
(
    # 6a. Spawn phase. The status-right indicator is session-scoped
    #     so the operator sees it across all panes/windows in their
    #     session. `2>/dev/null || true` swallows benign failures
    #     (older tmux, race with session close); the spawn itself is
    #     what matters.
    gcmux set-option -t "$SESSION" status-right "[spawning ${THREAD_TEMPLATE}...] " 2>/dev/null || true

    if ! SPAWN_OUT=$(gc session new "$THREAD_TEMPLATE" --no-attach 2>&1); then
        gcmux set-option -t "$SESSION" -u status-right 2>/dev/null || true
        gcmux display-message -d 10000 "thread spawn failed: $SPAWN_OUT"
        exit 1
    fi
    SESSION_ID=$(printf '%s\n' "$SPAWN_OUT" | sed -n 's/^Session \([^ ]*\) created.*/\1/p' | head -1)
    if [ -z "$SESSION_ID" ]; then
        gcmux set-option -t "$SESSION" -u status-right 2>/dev/null || true
        gcmux display-message -d 10000 "thread spawn: could not parse session id from gc output"
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
            gcmux set-option -t "$SESSION" -u status-right 2>/dev/null || true
            gcmux display-message -d 10000 "thread spawn: nudge to '$SESSION_ID' failed; session created but first message not delivered"
            exit 1
        fi
    fi

    # 6b. Start phase. The bead exists; the reconciler runs pre_start
    #     and then starts the provider. Poll `gc session list` every
    #     2s until state flips to `active`. 3-minute cap prevents a
    #     wedged reconciler from stranding the indicator forever.
    gcmux set-option -t "$SESSION" status-right "[starting ${THREAD_TEMPLATE}...] " 2>/dev/null || true

    STATE=""
    DEADLINE=$(( $(date +%s) + 180 ))
    while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        STATE=$(gc session list 2>/dev/null | awk -v id="$SESSION_ID" '$1 == id { print $3 }')
        [ "$STATE" = "active" ] && break
        sleep 2
    done

    gcmux set-option -t "$SESSION" -u status-right 2>/dev/null || true
    if [ "$STATE" = "active" ]; then
        gcmux display-message -d 5000 "thread ready: $THREAD_TEMPLATE ($SESSION_ID) — prefix+S to switch"
    else
        gcmux display-message -d 10000 "thread stalled in ${STATE:-unknown}: $SESSION_ID — check 'gc session list'"
    fi
) &
