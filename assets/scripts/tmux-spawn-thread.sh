#!/bin/sh
# tmux-spawn-thread.sh — Spawn a Role+Thread of the current pane's named agent.
# Usage: tmux-spawn-thread.sh <config-dir>
#
# Bound to `prefix + a` ("ask") by tmux-bindings.sh, which simply
# invokes this script with `run-shell -b`. The script handles input
# itself: it opens a tmux popup running `gum input`, the operator
# types a first-message seed and presses Enter to submit. Esc or a
# blank Enter spawns the thread without a seed (the message-less
# path is preserved).
#
# The slow part of the work (`gc session new` + creating->active
# poll + first-message nudge) is backgrounded inside the script so
# the operator's pane stays responsive after the popup closes.
# While the background runs, the operator's session shows a
# `[spawning ...]` / `[starting ...]` indicator in status-right so
# they don't stare at a blank pane. The original status-right
# value is captured before the indicator is set and restored on
# every exit path so Gas Town's session-scoped status format
# isn't wiped by an unset. The nudge runs AFTER `active` (with
# `--delivery=immediate`) to avoid the queued-nudge fence-mismatch
# that drops first-messages during bring-up. Final outcome (ready
# / stalled / error) surfaces via a 5- to 10-second
# `tmux display-message`.
#
# Threads are registered agents: they appear in `gc session list`,
# survive `gc session reset` of the canonical, and carry the full
# role persona. The canonical handles routed mail and routed work;
# threads are operator-spawned only.
#
# Idempotent role mapping:
#   mayor                          -> mayor-thread
#   mechanik                       -> mechanik-thread
#   mechanik-thread                -> mechanik-thread        (another instance, not -thread-thread)
#   mechanik-thread-1              -> mechanik-thread        (pool member -> sibling)
#   mechanik-thread-adhoc-<hex>    -> mechanik-thread        (ad-hoc explicit name -> sibling)
#   polecat-1                      -> polecat-thread         (no template -> soft fail)
#
# Input arrives via `gum input` inside a tmux `display-popup -E`,
# not tmux's `%%` substitution layer. gum reads /dev/tty in raw
# mode and returns the bytes verbatim, so apostrophes, embedded
# `"`, `\`, and other shell metacharacters all pass through cleanly
# with no quoting hazards. Single-line by design (Enter submits) —
# multi-line first messages remain out of scope. `gum` is expected
# on PATH (linuxbrew default install at
# `/home/linuxbrew/.linuxbrew/bin/gum`); if absent the script
# surfaces a clear install hint via display-message and exits
# rather than silently degrading.
set -eu

CONFIGDIR="${1:?missing config-dir}"

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
    gcmux display-message -d 10000 "thread spawn: cannot resolve current agent (no GC_AGENT, no parseable session name)"
    exit 1
fi

# 3. Derive the canonical role base from the qualified agent identity.
#    Strip everything up to and including the last "." (rig-prefix or
#    binding), then strip trailing "-adhoc-<hex>" (gascity-assigned
#    ad-hoc explicit name from `GenerateAdhocExplicitName`), trailing
#    "-<digits>" (pool member suffix), and trailing "-thread" (already
#    a thread). The adhoc strip must run first so an ad-hoc-spawned
#    thread (e.g. `mechanik-thread-adhoc-e045476bfb`) collapses to
#    `mechanik-thread` before the `-thread` strip reduces it to
#    `mechanik`. What remains is the role.
BARE=$(printf '%s' "$AGENT" | sed 's|.*\.||')
ROLE=$(printf '%s' "$BARE" \
    | sed -E 's/-adhoc-[a-f0-9]+$//' \
    | sed -E 's/-[0-9]+$//' \
    | sed -E 's/-thread$//')
THREAD_TEMPLATE="${ROLE}-thread"

# 4. Verify a <role>-thread template exists. `gc prime --strict` exits
#    non-zero for "agent not found in city config", which is exactly
#    the missing-template case we want to surface as a soft failure.
#    Bare-name resolution (gascity/cmd/gc/cmd_session.go:539) matches
#    against the agent's Name field regardless of scope, so this works
#    for both city- and rig-scoped thread templates as long as the
#    <role>-thread name is unique in the city's agent set.
if ! gc prime --strict "$THREAD_TEMPLATE" >/dev/null 2>&1; then
    gcmux display-message -d 10000 "thread spawn: no '$THREAD_TEMPLATE' template for role '$ROLE'"
    exit 0
fi

# 5a. Pre-check `gum` is on PATH before opening the popup. If the
#     binary is missing the popup's inner shell would render an
#     opaque "command not found" and close instantly; surface a
#     clear install hint instead.
if ! command -v gum >/dev/null 2>&1; then
    gcmux display-message -d 10000 "thread spawn: 'gum' not on PATH; install with 'brew install gum'"
    exit 0
fi

# 5b. Read the first-message payload via `gum input` running in a
#     tmux popup. gum opens /dev/tty in raw mode, so any character
#     (apostrophes, embedded `"`, `\`, multi-byte) flows through
#     verbatim — no tmux `%%` substitution, no shell quoting
#     hazards. display-popup -E blocks until the popup closes
#     (Enter submits, Esc cancels, blank Enter = no seed); the
#     enclosing script is invoked with `run-shell -b`, so tmux
#     backgrounds the whole thing and the operator's pane stays
#     responsive throughout. Empty `THREAD_SPAWN_MESSAGE` selects
#     the no-seed path in the spawn phase below.
TMPFILE=$(mktemp -t gc-thread-msg.XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

gcmux display-popup -E -w 80% -h 5 \
    "gum input --prompt='thread msg > ' --placeholder='Enter to submit, Esc/blank = no seed' > '$TMPFILE'" \
    2>/dev/null || true

THREAD_SPAWN_MESSAGE=$(cat "$TMPFILE" 2>/dev/null || true)

# 6. Background the slow path. `gc session new` does controller cold-
#    start, worktree setup, and session bead creation — ~15s. The
#    creating->active transition adds seconds-to-minutes after that
#    (reconciler pre_start fetches + rebases the worktree, then
#    starts the claude provider; once the provider is observed
#    running, state flips to `active`). If we run it inline, the
#    operator stares at a closed-popup aftermath until everything
#    settles. Backgrounding lets the script's foreground exit
#    immediately after the popup closes; the subshell continues to
#    update status-right and surface display-message on completion.
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
    # Capture the operator session's existing status-right before
    # we overwrite it with our spawn indicator. Gas Town's
    # tmux-theme.sh sets status-right at SESSION scope to its
    # `#(status-line.sh ...) %H:%M` format; cleaning up with `-u
    # status-right` would unset the session value and revert to
    # the (empty) global, wiping the operator's status line. We
    # restore by re-setting the original value at every exit
    # path. `show-options -v` returns the raw value (no `name
    # "value"` wrapper), which round-trips cleanly back through
    # set-option. Empty captured value means no session-scope
    # value existed; in that case fall through to `-u` so we
    # don't pin an empty string in place of the global.
    ORIG_STATUS=$(gcmux show-options -t "$SESSION" -v status-right 2>/dev/null || true)

    restore_status_right() {
        if [ -n "$ORIG_STATUS" ]; then
            gcmux set-option -t "$SESSION" status-right "$ORIG_STATUS" 2>/dev/null || true
        else
            gcmux set-option -t "$SESSION" -u status-right 2>/dev/null || true
        fi
    }

    # 6a. Spawn phase. The status-right indicator is session-scoped
    #     so the operator sees it across all panes/windows in their
    #     session. `2>/dev/null || true` swallows benign failures
    #     (older tmux, race with session close); the spawn itself is
    #     what matters.
    gcmux set-option -t "$SESSION" status-right "[spawning ${THREAD_TEMPLATE}...] " 2>/dev/null || true

    if ! SPAWN_OUT=$(gc session new "$THREAD_TEMPLATE" --no-attach 2>&1); then
        restore_status_right
        gcmux display-message -d 10000 "thread spawn failed: $SPAWN_OUT"
        exit 1
    fi
    SESSION_ID=$(printf '%s\n' "$SPAWN_OUT" | sed -n 's/^Session \([^ ]*\) created.*/\1/p' | head -1)
    if [ -z "$SESSION_ID" ]; then
        restore_status_right
        gcmux display-message -d 10000 "thread spawn: could not parse session id from gc output"
        exit 1
    fi

    # 6b. Start phase. The bead exists; the reconciler runs pre_start
    #     and then starts the provider. Poll `gc session list` every
    #     2s until state flips to `active`. 10-minute cap is a safety
    #     net for a wedged reconciler: normal cold-start completes in
    #     30-60s, but slow cold-start (reconciler busy + first-thread
    #     claude pre-warm on an idle city) can run 5-7 min.
    gcmux set-option -t "$SESSION" status-right "[starting ${THREAD_TEMPLATE}...] " 2>/dev/null || true

    STATE=""
    DEADLINE=$(( $(date +%s) + 600 ))
    while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        STATE=$(gc session list 2>/dev/null | awk -v id="$SESSION_ID" '$1 == id { print $3 }')
        [ "$STATE" = "active" ] && break
        sleep 2
    done

    # 6c. Deliver the first-message nudge AFTER the session reaches
    #     active. --delivery=immediate avoids the queued-nudge fence
    #     mismatch (gascity-internal: queued items capture the
    #     target's continuationEpoch at enqueue time, but the epoch
    #     advances during session bring-up, so the dispatcher
    #     rejects the queued item when state flips to active). With
    #     immediate delivery the session is already running and
    #     there's no queue to revalidate. If the poll timed out
    #     before active, we don't nudge — the stall message tells
    #     the operator they can re-send manually via `gc session
    #     nudge <id> "..."`.
    if [ "$STATE" = "active" ] && [ -n "$THREAD_SPAWN_MESSAGE" ]; then
        if ! gc session nudge --delivery=immediate "$SESSION_ID" "$THREAD_SPAWN_MESSAGE" >/dev/null 2>&1; then
            restore_status_right
            gcmux display-message -d 10000 "thread spawn: nudge to '$SESSION_ID' failed; session active but first message not delivered"
            exit 1
        fi
    fi

    restore_status_right
    if [ "$STATE" = "active" ]; then
        gcmux display-message -d 5000 "thread ready: $THREAD_TEMPLATE ($SESSION_ID) — prefix+S to switch"
    else
        gcmux display-message -d 10000 "thread stalled in ${STATE:-unknown}: $SESSION_ID — check 'gc session list'"
    fi
) &
