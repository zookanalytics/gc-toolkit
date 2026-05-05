#!/bin/sh
# tmux-spawn-scratch.sh — Spawn a scratch clone of the current pane's named agent.
# Usage: tmux-spawn-scratch.sh <config-dir>
#
# Bound to `prefix + a` ("ask") by tmux-bindings.sh. From inside a tmux
# session running a named-crew agent (mechanik, mayor, deacon, concierge,
# architect, ...), this spawns an unregistered claude in a **sibling tmux
# session** named `<host-session>-scratch`, with the same persona prompt
# and working directory as the registered agent in pane :^.0 of the host.
#
# The sibling session is created on first use and reused for subsequent
# scratches from the same host (each new spawn opens another `scratch`
# window in the sibling). The operator's client is switched to the sibling
# so the new scratch is in front; jump back via `prefix + S`.
#
# Scratch clones are NOT registered: no wisp, no mail/nudge delivery, no
# respawn lifecycle, and the sibling session is unknown to the controller.
# They survive `gc session reset <host>` (which kills only the host tmux
# session — not the sibling) and `gc session kill <host>` (same — only the
# host is registered). Sibling teardown is automatic: when the last scratch
# window exits, tmux destroys the now-empty sibling session.
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
#    context's session if no client is currently associated. Track
#    whether a focused client exists — only then can we switch its view
#    to the sibling session at step 5.
SESSION=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)
HAS_CLIENT=1
[ -z "$SESSION" ] && { HAS_CLIENT=0; SESSION=$(gcmux display-message -p '#{session_name}'); }

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

# 5. Spawn the scratch in a sibling tmux session named
#    `<host-session>-scratch`, in the registered agent's cwd, running an
#    unregistered claude with the composed system prompt. GC_SCRATCH=1
#    marks the env so downstream tooling can detect the scratch. The temp
#    prompt file is removed once claude exits.
#
#    Sibling-session model: scratches must survive `gc session reset
#    <host>`, which destroys the entire host tmux session (not just pane
#    :^.0). Hosting scratches in a sibling — unknown to the controller —
#    decouples them from the host's lifecycle. The sibling is created on
#    first spawn and reused for subsequent ones; when the last scratch
#    window exits, tmux destroys the sibling automatically.
#
#    Window name is just `scratch`. Multiple scratches in the sibling
#    show as `scratch` `scratch` and are disambiguated by `prefix + w`
#    indices, matching the convention for the default `prefix + c`
#    (multiple `zsh` windows).
#
#    `--bare` is intentionally NOT used: it would skip OAuth/keychain auth,
#    which is the only auth path on this host. We also don't pass
#    `--settings <city>`, so the city's hooks (UserPromptSubmit drains
#    nudges, Stop injects, etc.) don't fire in the scratch — the scratch
#    must not pull mail/nudges that belong to the registered agent.
#
#    Sibling sessions are not touched by the controller's `setRemainOnExit`
#    (they aren't registered). Default tmux behavior leaves remain-on-exit
#    off so panes close cleanly. We still set it explicitly at pane scope
#    in case a server-wide override (`set -g remain-on-exit on`) is in
#    effect — the scratch window must close, not linger as `[Exited]`.
SIBLING="${SESSION}-scratch"
SCRATCH_CMD="GC_SCRATCH=1 claude --append-system-prompt-file '$TMPFILE' ; rm -f '$TMPFILE'"
if gcmux has-session -t "$SIBLING" 2>/dev/null; then
    PANE_ID=$(gcmux new-window -P -F '#{pane_id}' -t "$SIBLING" -c "$CWD" -n scratch \
        "$SCRATCH_CMD")
else
    PANE_ID=$(gcmux new-session -d -P -F '#{pane_id}' -s "$SIBLING" -c "$CWD" -n scratch \
        "$SCRATCH_CMD")
fi
gcmux set-option -p -t "$PANE_ID" remain-on-exit off

# 6. Switch the operator's client to the sibling so the new scratch is in
#    front. Only meaningful when this script was invoked by a focused
#    client (the run-shell from a key binding); on context-less
#    invocations we leave the spawn in place and let the operator reach
#    it via `prefix + S`.
if [ "$HAS_CLIENT" = 1 ]; then
    gcmux switch-client -t "$SIBLING" 2>/dev/null || true
fi
