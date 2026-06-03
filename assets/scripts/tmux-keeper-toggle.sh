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
# This script is the single owner of (a) keeper pin-state detection and (b)
# the pin/unpin action. tmux-pick-session.sh calls `state` to label its
# fixed menu entry and runs `toggle` when that entry is selected, so there
# is exactly one copy of the pin/unpin logic (no duplication across the two).
#
# Pin-state model
# ---------------
# "up" == the keeper session bead's `metadata.pin_awake` is true — the real
# durable pin, NOT tmux liveness. The two diverge: an on_demand keeper
# materializes for ANY durable wake reason (most commonly work on its
# hook), so a live pane does not imply a pin. Labelling from liveness (as
# this script originally did, tk-oe5bc3) showed "unpin" for a
# working-but-unpinned keeper, where toggling would tear down a hold the
# operator never placed — or no-op confusingly (tk-7qczss).
#
# pin_awake lives only on the keeper's session bead in HQ beads — neither
# the `gc session list --json` rows nor the picker's supervisor sessions
# API expose pin state (verified 2026-06-03) — so the read is a real
# gc/beads round-trip: ONE `gc session list --json` call to resolve the
# canonical session bead ID by Alias, then one `gc bd show <id>` for
# `metadata.pin_awake`. (If a future gc exposes pin state in the
# session-list row, fold the read back into that single call.) Both calls
# are wall-clock bounded so a slow or wedged beads backend cannot stall
# the caller: on any failure/timeout `state` reports "unknown" — the
# picker renders a neutral label instead of stalling or guessing, and
# `toggle` refuses to act rather than flip the wrong way. A keeper that
# has never been materialized has no session row and reads as "down"
# (unpinned). `…-adhoc-<id>` threads carry their own distinct aliases, so
# the exact Alias match keeps excluding them — only the canonical session
# is the front-door.
#
# Usage: tmux-keeper-toggle.sh [--city-path <path>] [state|toggle]
#   state    print "up" (pinned), "down" (unpinned), or "unknown" (beads
#            slow/unreachable — caller must not guess)
#   toggle   pin when down, unpin when up, refuse when unknown; confirm
#            via `tmux display-message` (default action when none given)
#
# Needs jq (to parse the gc JSON) and coreutils timeout(1) for the bounds;
# degrades to an unbounded read where timeout is missing (gc-bd-watch.sh
# already assumes timeout(1), so this is not a new dependency).
#
# Invoked from the picker menu with `run-shell -b` so a slow `gc session pin`
# can never freeze the tmux server (same pattern as tmux-spawn-thread.sh).
set -eu

# The keeper's QualifiedName (the alias shown in `gc session list`).
KEEPER_ALIAS="gascity/gascity-keeper.keeper"

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
# cwd walk-up (best effort). Used for the pin/unpin actions, which are
# deliberately NOT bounded — they do real work and run backgrounded.
gc_session() {
    if [ -n "$CITY_PATH" ]; then
        gc session "$@" --city "$CITY_PATH"
    else
        gc session "$@"
    fi
}

# bounded_gc <seconds> <gc args…> — a read-only gc call with the city
# threaded and a hard wall-clock bound. timeout(1) execs a binary, so the
# gc_session shell function can't sit under it; this inlines the same
# --city threading instead.
bounded_gc() {
    bound="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        # shellcheck disable=SC2086 # ${CITY_PATH:+…} expands to 0 or 2 fields
        timeout "$bound" gc "$@" ${CITY_PATH:+--city "$CITY_PATH"}
    else
        gc "$@" ${CITY_PATH:+--city "$CITY_PATH"}
    fi
}

# keeper_pin_state <per-call-bound-seconds> — print up | down | unknown.
# Two bounded gc calls, short-circuiting to "unknown" on the first
# failure, so a wedged backend costs at most one bound before the caller
# gets its answer. jq -r prints both the JSON boolean true and the string
# "true" as `true`, so the comparison below covers either representation
# of pin_awake; an absent field prints `null` and reads as unpinned.
keeper_pin_state() {
    bound="$1"
    rows=$(bounded_gc "$bound" session list --json 2>/dev/null) \
        || { printf 'unknown'; return 0; }
    id=$(printf '%s\n' "$rows" | jq -r --arg a "$KEEPER_ALIAS" \
        'first((.sessions // [])[] | select(.Alias==$a) | .ID) // empty' 2>/dev/null) \
        || { printf 'unknown'; return 0; }
    # No session row: the keeper has never been created — down/unpinned.
    [ -n "$id" ] || { printf 'down'; return 0; }
    pin=$(bounded_gc "$bound" bd show "$id" --json 2>/dev/null) \
        || { printf 'unknown'; return 0; }
    pin=$(printf '%s\n' "$pin" | jq -r \
        'if type=="array" then .[0] else . end | .metadata.pin_awake' 2>/dev/null) \
        || { printf 'unknown'; return 0; }
    if [ "$pin" = "true" ]; then printf 'up'; else printf 'down'; fi
}

if [ "$ACTION" = "state" ]; then
    # Picker render path: 3s per-call bound. Measured healthy-but-busy
    # latency is ~1.0-1.8s per call, so 2s would flip the label to the
    # neutral fallback on systems that are merely loaded; 3s keeps the
    # label truthful there while a wedged beads backend still costs the
    # picker only one bound (the read short-circuits to "unknown" on the
    # first failed call) before the neutral label renders.
    keeper_pin_state 3
    exit 0
fi

# toggle — flip the durable pin based on real pin state. Generous 10s
# per-call bound: this path runs backgrounded (`run-shell -b`), so staying
# usable under Dolt load beats answering fast. Report the outcome on the
# status line; surface pin/unpin failures (e.g. a hard suspend hold that
# pin can't clear) verbatim so the operator can act on them. When the pin
# state cannot be determined, do nothing — flipping blind could tear down
# a hold the operator placed, or pin what they meant to unpin.
case "$(keeper_pin_state 10)" in
up)
    if OUT=$(gc_session unpin "$KEEPER_ALIAS" 2>&1); then
        gcmux display-message -d 5000 "keeper unpinned — will drain when idle"
    else
        gcmux display-message -d 10000 "keeper unpin failed: $OUT"
    fi
    ;;
down)
    if OUT=$(gc_session pin "$KEEPER_ALIAS" 2>&1); then
        gcmux display-message -d 5000 "keeper pinned — holding it up"
    else
        gcmux display-message -d 10000 "keeper pin failed: $OUT"
    fi
    ;;
*)
    gcmux display-message -d 10000 "keeper pin state unknown (gc/beads slow or unreachable) — not toggling"
    ;;
esac
