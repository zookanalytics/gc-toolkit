#!/bin/sh
# tmux-spawn-scratch.sh — Spawn a scratch clone of the current pane's named agent.
# Usage: tmux-spawn-scratch.sh <config-dir>
#
# Bound to `prefix + a` ("ask") by tmux-bindings.sh. From inside a tmux
# session running a named-crew agent (mechanik, mayor, deacon, concierge,
# architect, ...), this opens a new window in the same session running an
# unregistered claude with the same persona prompt and working directory
# as the registered agent in pane :^.0.
#
# Scratch clones are NOT registered: no wisp, no mail/nudge delivery, no
# respawn lifecycle. They survive `gc session reset` (which only respawns
# pane :^.0) and die with `gc session kill` (whole session).
#
# A soft-guard fragment (template-fragments/scratch-clone-guard.md) is
# appended to the persona — it tells the scratch what is free to do, what
# to ask about, and what to avoid while the registered agent is mid-flight.
#
# The exclusion list refuses cloning of formula-driven (polecat, refinery,
# witness, dog) and lifecycle/internal (boot, control-dispatcher,
# consult-host) agents whose identity is not a stable named persona.
set -e

CONFIGDIR="$1"
[ -z "$CONFIGDIR" ] && { echo "tmux-spawn-scratch.sh: missing config-dir" >&2; exit 1; }

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# 1. Resolve the active session. Prefer the focused client's session
#    (the user who pressed prefix + a); fall back to the run-shell
#    context's session if no client is currently associated.
SESSION=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)
[ -z "$SESSION" ] && SESSION=$(gcmux display-message -p '#{session_name}')

# 2. Resolve the agent name. Prefer GC_AGENT from the session environment
#    (canonical rig.agent or city.agent form, the key gc prime expects).
#    Fall back to deriving from the session name suffix (gascity uses
#    `<rig>__<agent>` for tmux session names).
AGENT=$(gcmux show-environment -t "$SESSION" GC_AGENT 2>/dev/null | sed -n 's/^GC_AGENT=//p')
[ -z "$AGENT" ] && AGENT=$(printf '%s' "$SESSION" | sed 's/.*__//')

# Short label for the window name — last `.`-separated segment, so
# `gc-toolkit.mechanik` -> `mechanik`, `gastown.mayor` -> `mayor`.
SHORT_AGENT=$(printf '%s' "$AGENT" | sed 's/.*\.//')

# 3. Exclusion list — refuse for formula-driven and lifecycle/internal
#    agents. Default-allow so new named-crew additions get scratch
#    cloning automatically.
case "$AGENT" in
    *polecat*|*refinery*|*witness*|*dog*|*boot*|*control-dispatcher*|*consult-host*)
        gcmux display-message "Scratch clone not enabled for $AGENT (named crew only)"
        exit 0
        ;;
esac

# 4. Resolve the registered agent's cwd from pane :^.0 (first window,
#    first pane, regardless of base-index). Mirrors the convention used
#    by GetPaneWorkDir / GetPaneCommand in gascity's runtime/tmux.
CWD=$(gcmux display-message -t "$SESSION:^.0" -p '#{pane_current_path}' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$HOME"

# 5. Compose the scratch system prompt: persona + guard fragment, with
#    <agent-name> substituted in the guard. --strict makes gc prime fail
#    loudly on a typo'd agent name instead of returning a generic prompt.
GUARD_FRAGMENT="$CONFIGDIR/template-fragments/scratch-clone-guard.md"
[ -r "$GUARD_FRAGMENT" ] || {
    gcmux display-message "Scratch clone failed: missing $GUARD_FRAGMENT"
    exit 1
}

TMPFILE=$(mktemp)
gc prime --strict "$AGENT" > "$TMPFILE"
printf '\n\n' >> "$TMPFILE"
sed "s|<agent-name>|$AGENT|g" "$GUARD_FRAGMENT" >> "$TMPFILE"

# 6. Open a new window in the same session, in the registered agent's
#    cwd, running an unregistered claude with the composed system prompt.
#    GC_SCRATCH=1 marks the env so downstream tooling can detect the
#    scratch. The temp prompt file is removed once claude exits.
#
#    `tmux kill-pane` at the end is required because named-crew sessions
#    set `remain-on-exit on` (so the registered agent's pane can be
#    respawned in place). New windows inherit that option; without an
#    explicit kill, the scratch window would linger as `[Exited]` after
#    claude exits.
gcmux new-window -t "$SESSION" -c "$CWD" -n "scratch-$SHORT_AGENT" \
    "GC_SCRATCH=1 claude --bare --append-system-prompt-file '$TMPFILE' ; rm -f '$TMPFILE' ; tmux kill-pane"
