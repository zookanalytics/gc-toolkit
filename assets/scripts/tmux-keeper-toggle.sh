#!/bin/sh
# tmux-keeper-toggle.sh — pin / unpin the gascity-keeper from the `S` picker.
# Usage: tmux-keeper-toggle.sh [--city-path <path>] [state|toggle]
#   state    print "up" (pinned) | "down" (unpinned) | "unknown" (beads slow
#            or unreachable — caller must not guess)
#   toggle   pin when down, unpin when up, refuse when unknown (default)
# The on_demand keeper has no pane when drained, so the picker needs this
# standalone surface; `gc session pin` is the durable hold (wake drains
# again, attach drops on detach). Single owner of pin-state detection AND
# the toggle, so the picker cannot drift from it. "up" is the session bead's
# metadata.pin_awake — the real durable pin, NOT tmux liveness (a keeper
# materialized by hooked work is up-but-unpinned, tk-oe5bc3/tk-7qczss); the
# read is one bounded `gc session list --json` (alias → bead id) plus one
# bounded `gc bd show`. Invoked with run-shell -b so a slow pin can never
# freeze tmux. Needs jq; degrades to unbounded reads without timeout(1).
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

# Socket-aware wrapper; bare tmux targets the server that ran us via $TMUX.
gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# gc session scoped to the baked-in city; pin/unpin are deliberately NOT
# bounded (real work, backgrounded).
gc_session() {
    if [ -n "$CITY_PATH" ]; then
        gc session "$@" --city "$CITY_PATH"
    else
        gc session "$@"
    fi
}

# bounded_gc <seconds> <gc args…> — a bounded read-only gc call (timeout
# execs a binary, so the shell function above cannot sit under it).
bounded_gc() {
    bound="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        # shellcheck disable=SC2086 # ${CITY_PATH:+…} expands to 0 or 2 fields
        timeout "$bound" gc "$@" ${CITY_PATH:+--city "$CITY_PATH"}
    else
        gc "$@" ${CITY_PATH:+--city "$CITY_PATH"}
    fi
}

# keeper_pin_state <bound-secs> — up | down | unknown; short-circuits to
# unknown on the first failed call. jq -r renders boolean and string true
# alike; absent prints null and reads as unpinned.
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
    # 3s per call: healthy-but-busy is ~1.0-1.8s, so 2s would go neutral
    # under mere load.
    keeper_pin_state 3
    exit 0
fi

# toggle — 10s per-call bound (backgrounded; usable under load beats fast).
# Failures are surfaced verbatim; unknown state does nothing — flipping
# blind could tear down a hold the operator placed.
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
