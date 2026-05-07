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
# respawn lifecycle. They survive `gc handoff` (the routine restart
# path, which uses `respawn-pane` on :^.0 only — co-located scratch
# windows persist). They die with `gc session reset` and `gc session
# kill`, both of which destroy the whole tmux session. That's an
# accepted tradeoff: per the tk-my4za audit, `gc handoff` is the
# default for "restart the agent" and `gc session reset` is reserved
# for the rare case where destroying the whole process tree is
# genuinely intended.
#
# A soft-guard fragment (template-fragments/scratch-clone-guard.md) is
# appended to the persona — it tells the scratch what is free to do, what
# to ask about, and what to avoid while the registered agent is mid-flight.
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

# 3. Resolve the registered agent's cwd from pane :^.0 (first window,
#    first pane, regardless of base-index). Mirrors the convention used
#    by GetPaneWorkDir / GetPaneCommand in gascity's runtime/tmux.
CWD=$(gcmux display-message -t "$SESSION:^.0" -p '#{pane_current_path}' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$HOME"

# 4. Compose the scratch system prompt: persona + guard fragment, with
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

# 5. Open a new window in the same session, in the registered agent's
#    cwd, running an unregistered claude with the composed system prompt.
#    GC_SCRATCH=1 marks the env so downstream tooling can detect the
#    scratch. The temp prompt file is removed once claude exits.
#
#    Window name is just `scratch` (the session name already says which
#    agent is hosting). Multiple scratches in one session show as `scratch`
#    `scratch` and are disambiguated by `prefix + w` indices, matching the
#    convention for the default `prefix + c` (multiple `zsh` windows).
#
#    `--bare` is intentionally NOT used: it would skip OAuth/keychain auth,
#    which is the only auth path on this host. We also don't pass
#    `--settings <city>`, so the city's hooks (UserPromptSubmit drains
#    nudges, Stop injects, etc.) don't fire in the scratch — the scratch
#    must not pull mail/nudges that belong to the registered agent.
#
#    Named-crew sessions set `remain-on-exit on` so their primary pane
#    can be respawned in place by `gc handoff` (which uses tmux
#    `respawn-pane` on :^.0). New windows inherit that option; we
#    override it on the captured pane id so the scratch window closes
#    cleanly when claude exits instead of lingering as `[Exited]`.
PANE_ID=$(gcmux new-window -P -F '#{pane_id}' -t "$SESSION" -c "$CWD" -n scratch \
    "GC_SCRATCH=1 claude --append-system-prompt-file '$TMPFILE' ; rm -f '$TMPFILE'")
gcmux set-option -p -t "$PANE_ID" remain-on-exit off
