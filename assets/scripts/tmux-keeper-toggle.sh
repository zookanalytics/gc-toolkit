#!/bin/sh
# tmux-keeper-toggle.sh — pin / unpin the gascity-keeper from the `S` picker.
# Companion: tmux-pick-session.sh (the picker that renders the toggle entry).
#
# Why this exists
# ---------------
# The gascity-keeper is the operator's single front-door for the forked
# upstream repos (gastownhall/gascity). It runs `on_demand` on purpose:
# whether it is up is itself useful signal — "up" means the operator is in
# upstream-engagement mode (a rebase/sync is hot), "down" means they are
# not. But on_demand carries a navigation cost: a drained keeper has no
# tmux pane, so it cannot be reached or revived through the picker's normal
# "switch to a live pane" flow. `gc session wake` does not hold it up (it
# drains again moments later — the "no-wake-reason" you see in the logs)
# and `attach` drops on detach. The durable primitive is `gc session pin`,
# which materializes the canonical session and holds it until
# `gc session unpin`.
#
# This script is the single owner of (a) keeper state-detection and (b) the
# pin/unpin action. tmux-pick-session.sh calls `state` to label its fixed
# menu entry and runs `toggle` when that entry is selected, so there is
# exactly one copy of the pin/unpin logic (no duplication across the two).
#
# State model
# -----------
# "up" == the canonical keeper tmux session is live on this server. That is
# the same `tmux list-sessions` view the picker already builds its rows
# from, it is exactly what the operator observes ("is the keeper a navigable
# pane?"), and it costs one local tmux call — no `gc`/beads round-trip
# (75-190ms idle, seconds under Dolt load) on every picker open, which would
# regress the picker's deliberately fast render path. A pin is what *keeps*
# an idle on_demand keeper materialized, so presence tracks the operator's
# normal "pin to bring up / unpin to let it drain" workflow. A `…-adhoc-<id>`
# thread spawned alongside the canonical does NOT count — only the canonical
# session is the front-door (whole-line match below excludes adhoc threads).
#
# Usage: tmux-keeper-toggle.sh [--city-path <path>] [state|toggle]
#   state    print "up" or "down" (for the picker label)
#   toggle   pin when down, unpin when up; confirm via `tmux display-message`
#            (default action when none is given)
#
# Invoked from the picker menu with `run-shell -b` so a slow `gc session pin`
# can never freeze the tmux server (same pattern as tmux-spawn-thread.sh).
set -eu

# The keeper's QualifiedName (the alias shown in `gc session list`). gc
# derives the tmux session name from it by mapping '/' -> '--' and '.' -> '__'
# (e.g. gascity--gascity-keeper__keeper).
KEEPER_ALIAS="gascity/gascity-keeper.keeper"
KEEPER_SESSION="$(printf '%s' "$KEEPER_ALIAS" | sed 's#/#--#g; s#\.#__#g')"

CITY_PATH=""
ACTION="toggle"
while [ $# -gt 0 ]; do
    case "$1" in
        --city-path) CITY_PATH="${2:-}"; shift 2 ;;
        state|toggle) ACTION="$1"; shift ;;
        *) shift ;;
    esac
done

# Same socket-aware wrapper the picker uses. Under `run-shell` GC_TMUX_SOCKET
# is usually unset, so this falls back to bare `tmux`, which targets the
# server that ran us via $TMUX — the correct city server in both the
# picker's `state` call and the menu's `toggle` invocation.
gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# `gc session` scoped to the picker's baked-in city. The binding fires from
# tmux's bare env (no GC_CITY), so --city makes resolution deterministic;
# when no city path was threaded through we let gc fall back to its own
# cwd walk-up (best effort).
gc_session() {
    if [ -n "$CITY_PATH" ]; then
        gc session "$@" --city "$CITY_PATH"
    else
        gc session "$@"
    fi
}

# Is the canonical keeper session materialized on this tmux server?
keeper_is_up() {
    gcmux list-sessions -F '#{session_name}' 2>/dev/null \
        | grep -Fxq "$KEEPER_SESSION"
}

if [ "$ACTION" = "state" ]; then
    if keeper_is_up; then printf 'up'; else printf 'down'; fi
    exit 0
fi

# toggle — flip the durable pin. Report the outcome on the status line;
# surface failures (e.g. a hard suspend hold that pin can't clear) verbatim
# so the operator can act on them.
if keeper_is_up; then
    if OUT=$(gc_session unpin "$KEEPER_ALIAS" 2>&1); then
        gcmux display-message -d 5000 "keeper unpinned — will drain when idle"
    else
        gcmux display-message -d 10000 "keeper unpin failed: $OUT"
    fi
else
    if OUT=$(gc_session pin "$KEEPER_ALIAS" 2>&1); then
        gcmux display-message -d 5000 "keeper pinned — bringing up…"
    else
        gcmux display-message -d 10000 "keeper pin failed: $OUT"
    fi
fi
