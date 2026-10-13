#!/usr/bin/env bash
# order-cadence.sh — the single definition of how long a clock-driven order may
# go without firing before a reader calls it stopped.
#
# The supervisor dispatches orders on its orders lane, not once per declared
# interval. Each lane pass fires at most orders.max_dispatches_per_tick
# clock-driven orders (cooldown, cron and event triggers) and resumes the
# rotation where the previous pass stopped. A pass spends budget only on an
# order it fires, so it walks past an order that is not due. An order whose
# interval is shorter than one trip around the rotation therefore fires once per
# trip, not once per interval, and a trip takes at most
#   ceil(clock-driven registrations / max_dispatches_per_tick)
# passes. The lane starts a pass when a controller tick wakes it and it has
# idled as long as its last pass ran, or one patrol interval after the last pass
# ended, so passes land further apart than the patrol interval by however long a
# pass runs, and that grows with store load. CADENCE_PASS_SPACING is the
# spacing a window allows each pass of the trip.
#
#   floor  = max(CADENCE_FLOOR_MIN, trip passes * CADENCE_PASS_SPACING)
#   window = max(3 * interval, floor)
#
# An order with a long interval keeps three intervals of slack, and a
# short-interval order gets the trip. The floor grows as orders are registered
# and shrinks as the budget is raised, so neither change needs an edit here. A
# reader that cannot read the registry uses CADENCE_FLOOR_MIN.
#
# Sourced (never executed) by doctor/check-cadence-live (I10), which calls an
# order stopped once it has not fired inside its window, and by
# doctor/check-armed-dispatch-owed, which calls a ready arm owed once it has
# waited out the deferred-dispatch order's window. One definition keeps the
# second from flagging a gap the first reads as healthy. order-cadence.test.sh
# fails when either reader stops sourcing this file or carries a window of its
# own.

CADENCE_FLOOR_MIN=1800
CADENCE_PASS_SPACING=120
# gascity's built-in orders.max_dispatches_per_tick. It also applies when the
# key is set to zero or less.
CADENCE_DEFAULT_BUDGET=4

# cadence_interval_secs <interval> — an order interval ("30s", "5m", "2h") in
# seconds, or nothing when it does not parse.
cadence_interval_secs() {
    local n="${1%[smh]}"
    case "$n" in ''|*[!0-9]*) return 0 ;; esac
    case "$1" in
        *s) printf '%s' "$n" ;;
        *m) printf '%s' "$(( n * 60 ))" ;;
        *h) printf '%s' "$(( n * 3600 ))" ;;
    esac
}

# cadence_budget <city.toml> — the per-pass dispatch budget: the [orders]
# max_dispatches_per_tick the file sets, or CADENCE_DEFAULT_BUDGET when it sets
# none, sets one that is not a positive integer, or does not read.
cadence_budget() {
    local v=""
    if [ -n "${1:-}" ] && [ -f "$1" ]; then
        v=$(awk '
            /^[[:space:]]*\[orders\][[:space:]]*(#.*)?$/ { sec = 1; next }
            /^[[:space:]]*\[/ { sec = 0 }
            sec && /^[[:space:]]*max_dispatches_per_tick[[:space:]]*=/ {
                v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]#].*$/, "", v); print v; exit
            }' "$1" 2>/dev/null)
    fi
    case "$v" in ''|*[!0-9]*) v=0 ;; esac
    [ "$v" -gt 0 ] || v="$CADENCE_DEFAULT_BUDGET"
    printf '%s' "$v"
}

# cadence_order_interval <order.toml> — the interval an order file declares
# under [order], in seconds, or nothing when it declares none or one that does
# not parse.
cadence_order_interval() {
    [ -f "${1:-}" ] || return 0
    cadence_interval_secs "$(awk '
        /^\[order\]/ { inb = 1; next }
        /^\[/        { inb = 0 }
        inb && /^interval[[:space:]]*=/ { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print v; exit }' "$1" 2>/dev/null)"
}

# cadence_clock_registrations <orders-json> — how many enabled clock-driven
# registrations `gc order list --json` names, or nothing when it has no .orders
# array.
cadence_clock_registrations() {
    printf '%s' "${1:-}" | jq -r '
        if (.orders | type) == "array" then
          [.orders[] | select(.enabled != false)
                     | select(.trigger == "cooldown" or .trigger == "cron" or .trigger == "event")] | length
        else empty end' 2>/dev/null
}

# cadence_floor_of <registrations> <budget> — the floor for that rotation.
cadence_floor_of() {
    local regs="${1:-0}" budget="${2:-}" floor
    case "$regs" in ''|*[!0-9]*) regs=0 ;; esac
    case "$budget" in ''|*[!0-9]*) budget=0 ;; esac
    [ "$budget" -gt 0 ] || budget="$CADENCE_DEFAULT_BUDGET"
    floor=$(( (regs + budget - 1) / budget * CADENCE_PASS_SPACING ))
    [ "$floor" -ge "$CADENCE_FLOOR_MIN" ] || floor="$CADENCE_FLOOR_MIN"
    printf '%s' "$floor"
}

# cadence_floor <orders-json> <city.toml> — the floor in seconds for the live
# registry and the city's budget. A registry with no .orders array yields
# CADENCE_FLOOR_MIN.
cadence_floor() {
    local regs
    regs=$(cadence_clock_registrations "${1:-}")
    case "$regs" in ''|*[!0-9]*) printf '%s' "$CADENCE_FLOOR_MIN"; return 0 ;; esac
    cadence_floor_of "$regs" "$(cadence_budget "${2:-}")"
}

# cadence_window <interval-secs> <floor> — max(3 * interval, floor).
cadence_window() {
    local w=$(( ${1:-0} * 3 ))
    [ "$w" -ge "${2:-$CADENCE_FLOOR_MIN}" ] || w="${2:-$CADENCE_FLOOR_MIN}"
    printf '%s' "$w"
}
