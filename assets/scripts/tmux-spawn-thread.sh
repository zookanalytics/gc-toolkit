#!/bin/sh
# tmux-spawn-thread.sh — Spawn a Role+Thread of the current pane's named agent.
# Usage: tmux-spawn-thread.sh <config-dir>
#
# Bound to `prefix + a` ("ask") by tmux-bindings.sh, which simply
# invokes this script with `run-shell -b`. The script handles input
# itself: it opens a tmux popup running `gum input`, the operator
# types a first-message seed and presses Enter to submit. Esc
# cancels the spawn entirely; a blank Enter spawns the thread
# without a seed (the message-less path is preserved).
#
# The slow part of the work (`gc session new` + creating->active
# poll + first-message nudge) is backgrounded inside the script so
# the operator's pane stays responsive after the popup closes.
# While the background runs, the operator's session shows a
# `[spawning ...]` / `[starting ...]` indicator in the status-line's
# indicator slot, via a single-line file at /tmp/gc-status-<slug>.indicator.
# gc-toolkit-status-line.sh picks the file up on every 5-second
# status refresh; we clear the file (rm -f via EXIT trap) when the
# spawn completes so the slot returns to empty. No tmux-option
# capture/restore: previous revisions overwrote status-right
# directly, which doesn't compose with other UI signals. The nudge
# runs AFTER `active` (with `--delivery=immediate`) to avoid the
# queued-nudge fence-mismatch that drops first-messages during
# bring-up. Final outcome (ready / stalled / error) surfaces via a
# 5- to 10-second `tmux display-message`.
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
#     hazards. display-popup -E propagates the inner gum exit code:
#     Enter returns 0 (with or without text); Esc returns 130. We
#     exit early on non-zero so Esc is a true cancel — no spawn,
#     no indicator file. Blank Enter falls through with an empty
#     THREAD_SPAWN_MESSAGE, selecting the no-seed path in the spawn
#     phase below. The enclosing script is invoked with `run-shell
#     -b`, so tmux backgrounds the whole thing and the operator's
#     pane stays responsive throughout.
TMPFILE=$(mktemp -t gc-thread-msg.XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

EXIT_CODE=0
gcmux display-popup -E -w 80% -h 5 \
    "gum input --prompt='thread msg > ' --placeholder='Enter to submit, Esc to cancel' > '$TMPFILE'" \
    2>/dev/null || EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
    exit 0
fi

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
#    While the background runs, we write a persistent in-flight
#    indicator to /tmp/gc-status-<slug>.indicator. The slug is the
#    operator's qualified agent name with [./] -> -. gc-toolkit's
#    status-line script reads that file on every 5-second status
#    refresh and renders the indicator in a dedicated slot, so
#    operators see `[spawning <name>...]` during `gc session new`
#    and `[starting <name>...]` while we poll for `active`. The
#    EXIT trap below clears the file on every exit path so the
#    slot returns to empty when the spawn completes — successful
#    or otherwise.
#
#    We do NOT pass --alias to `gc session new`: the runtime would
#    prefix it with the binding namespace (e.g. "thread-abc" ->
#    "<binding>.thread-abc"), and the un-prefixed value would not
#    resolve in the nudge below. The canonical session ID returned
#    by `gc session new` is what we route on.
(
    # Indicator slot — see gc-toolkit-status-line.sh for the
    # contract. The slug must match what the operator's status-line
    # script computes from its $AGENT arg (it normalizes the same
    # way), so the writer here and the reader there agree on the
    # /tmp path. Trap clears the file on every exit path; signals
    # in the background subshell still fire EXIT in POSIX sh.
    AGENT_SLUG=$(printf '%s' "$AGENT" | sed 's|[./]|-|g')
    INDICATOR="/tmp/gc-status-${AGENT_SLUG}.indicator"
    trap 'rm -f "$INDICATOR"' EXIT INT TERM HUP

    # 6a. Spawn phase. `2>/dev/null || true` on the write is
    #     defensive: /tmp is writable on every supported host, but
    #     a wedged disk shouldn't take the spawn down with it.
    #
    #     When the operator typed a first-message seed in the popup,
    #     pass it as --title-hint so gascity's title model auto-seeds
    #     a short title from that text (a literal short version is
    #     set immediately and refined in the background). When the
    #     popup was blank (Enter on an empty input), omit --title-hint
    #     and let gascity fall back to its default title (the agent
    #     name) — the operator can refine later via the /session-title
    #     skill. (Esc no longer reaches this block; it cancels at the
    #     popup exit-code check above.)
    #     Positional-arg shuffling preserves the quoted message
    #     through field-splitting; `set --` only touches the
    #     subshell's $@ (CONFIGDIR is already captured above).
    echo "[spawning ${THREAD_TEMPLATE}...]" > "$INDICATOR" 2>/dev/null || true

    set -- "$THREAD_TEMPLATE" --no-attach
    [ -n "$THREAD_SPAWN_MESSAGE" ] && set -- "$@" --title-hint "$THREAD_SPAWN_MESSAGE"
    if ! SPAWN_OUT=$(gc session new "$@" 2>&1); then
        gcmux display-message -d 10000 "thread spawn failed: $SPAWN_OUT"
        exit 1
    fi
    SESSION_ID=$(printf '%s\n' "$SPAWN_OUT" | sed -n 's/^Session \([^ ]*\) created.*/\1/p' | head -1)
    if [ -z "$SESSION_ID" ]; then
        gcmux display-message -d 10000 "thread spawn: could not parse session id from gc output"
        exit 1
    fi

    # 6b. Start phase. The bead exists; the reconciler runs pre_start
    #     and then starts the provider. Poll `gc session list` every
    #     2s until state flips to `active`. 10-minute cap is a safety
    #     net for a wedged reconciler: normal cold-start completes in
    #     30-60s, but slow cold-start (reconciler busy + first-thread
    #     claude pre-warm on an idle city) can run 5-7 min.
    echo "[starting ${THREAD_TEMPLATE}...]" > "$INDICATOR" 2>/dev/null || true

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
            gcmux display-message -d 10000 "thread spawn: nudge to '$SESSION_ID' failed; session active but first message not delivered"
            exit 1
        fi
    fi

    if [ "$STATE" = "active" ]; then
        gcmux display-message -d 5000 "thread ready: $THREAD_TEMPLATE ($SESSION_ID) — prefix+S to switch"
    else
        gcmux display-message -d 10000 "thread stalled in ${STATE:-unknown}: $SESSION_ID — check 'gc session list'"
    fi
    # EXIT trap clears $INDICATOR.
) &
