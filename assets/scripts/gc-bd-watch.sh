#!/bin/sh
# gc-bd-watch.sh — emit meaningful bead-state updates as JSONL.
# Usage: gc-bd-watch <bead-id> [--timeout=DURATION]   (DURATION: timeout(1)
# style, default 24h). Spawned as a background process by an agent harness;
# each stdout line is one self-contained JSON object:
#   {"ts","bead","type":"watch_start","status"}
#   {"ts","bead","type":"status_change","from","to"}     <- match on this
#   {"ts","bead","type":"watch_reconnect","attempt","reason"}
#   {"ts","bead","type":"watch_end","reason"}
# watch_end reasons: closed · already_closed · timeout · killed ·
# startup_no_cursor · stream_ended_before_terminal · stream_error_<n>.
# Exit: 0 terminal · 1 startup/stream failure · 2 usage · 124 timeout ·
# 143 SIGTERM. Transient stream drops are retried with backoff, resuming
# from each event's .seq so nothing is missed; the reconnect budget resets
# on forward progress (tunables GC_BD_WATCH_MAX_RECONNECT /
# GC_BD_WATCH_BACKOFF_INITIAL). The wall-clock budget is fixed at startup —
# retries never extend it. bead.updated fires on every metadata write, so
# status_change is emitted only on a real status transition.
set -eu

usage() {
    cat >&2 <<'EOF'
Usage: gc-bd-watch <bead-id> [--timeout=DURATION]

Emits JSONL bead-state updates to stdout. Designed to run as a
background process whose stdout is observed by the spawning agent's
harness. DURATION is any value timeout(1) accepts (default 24h).
EOF
}

BEAD=""
TIMEOUT="24h"
while [ $# -gt 0 ]; do
    case "$1" in
        --timeout=*) TIMEOUT="${1#--timeout=}"; shift ;;
        --timeout)
            shift
            [ $# -gt 0 ] || { echo "gc-bd-watch: --timeout requires a value" >&2; usage; exit 2; }
            TIMEOUT="$1"; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "gc-bd-watch: unknown flag '$1'" >&2; usage; exit 2 ;;
        *)
            if [ -z "$BEAD" ]; then
                BEAD="$1"
            else
                echo "gc-bd-watch: unexpected argument '$1'" >&2; usage; exit 2
            fi
            shift ;;
    esac
done

[ -n "$BEAD" ] || { usage; exit 2; }

# Reconnect tunables; bad values fall back to defaults.
MAX_RECONNECT="${GC_BD_WATCH_MAX_RECONNECT:-5}"
BACKOFF_INITIAL="${GC_BD_WATCH_BACKOFF_INITIAL:-2}"
printf '%s' "$MAX_RECONNECT"   | grep -Eq '^[0-9]+$' || MAX_RECONNECT=5
printf '%s' "$BACKOFF_INITIAL" | grep -Eq '^[0-9]+$' || BACKOFF_INITIAL=2

# Convert a timeout(1)-style duration ("30s", "5m", "24h", "1d", or bare
# integer seconds) to integer seconds for deadline math.
duration_to_seconds() {
    awk -v d="$1" 'BEGIN {
        n = d
        sub(/[smhd]$/, "", n)
        if (d ~ /d$/)      print int(n * 86400)
        else if (d ~ /h$/) print int(n * 3600)
        else if (d ~ /m$/) print int(n * 60)
        else               print int(n)
    }'
}

now_ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

emit_start()  {
    jq -nc --arg ts "$(now_ts)" --arg bead "$BEAD" --arg status "$1" \
        '{ts:$ts,bead:$bead,type:"watch_start",status:$status}'
}
emit_change() {
    jq -nc --arg ts "$(now_ts)" --arg bead "$BEAD" --arg from "$1" --arg to "$2" \
        '{ts:$ts,bead:$bead,type:"status_change",from:$from,to:$to}'
}
emit_reconnect() {
    jq -nc --arg ts "$(now_ts)" --arg bead "$BEAD" --argjson attempt "$1" --arg reason "$2" \
        '{ts:$ts,bead:$bead,type:"watch_reconnect",attempt:$attempt,reason:$reason}'
}
emit_end()    {
    jq -nc --arg ts "$(now_ts)" --arg bead "$BEAD" --arg reason "$1" \
        '{ts:$ts,bead:$bead,type:"watch_end",reason:$reason}'
}

# Shared with the cleanup trap so it can tear down the producer.
FIFO=""
PRODUCER=""

cleanup() {
    if [ -n "$PRODUCER" ]; then
        kill "$PRODUCER" 2>/dev/null || true
        wait "$PRODUCER" 2>/dev/null || true
        PRODUCER=""
    fi
    if [ -n "$FIFO" ]; then
        rm -f "$FIFO"
        FIFO=""
    fi
}

on_kill() {
    emit_end killed || true
    exit 143
}
# EXIT runs cleanup unconditionally; cleanup() is idempotent.
trap cleanup EXIT
trap on_kill TERM INT HUP
# SIGPIPE ignored: a vanished consumer surfaces as jq's EPIPE write error,
# which set -e turns into an abnormal exit through the EXIT trap.
trap '' PIPE

# Cursor snapshot BEFORE the bd show: transitions racing startup are
# replayed from it.
CURSOR="$(gc events --seq 2>/dev/null || true)"

INIT="$(gc bd show "$BEAD" --json 2>/dev/null | jq -r '.[0].status // empty' 2>/dev/null || true)"
if [ -z "$INIT" ]; then
    echo "gc-bd-watch: bead '$BEAD' not found" >&2
    exit 1
fi

emit_start "$INIT"

if [ "$INIT" = "closed" ]; then
    emit_end already_closed
    exit 0
fi

# Fail loud on a missing cursor: without --after the stream starts at head
# and silently misses the startup window.
if ! printf '%s' "$CURSOR" | grep -Eq '^[0-9]+$'; then
    echo "gc-bd-watch: gc events --seq did not return a usable cursor; aborting" >&2
    emit_end startup_no_cursor
    exit 1
fi

PRIOR="$INIT"

# Wall-clock deadline; per-attempt timeouts are computed against it.
TIMEOUT_SECS="$(duration_to_seconds "$TIMEOUT")"
if ! printf '%s' "$TIMEOUT_SECS" | grep -Eq '^[0-9]+$' || [ "$TIMEOUT_SECS" -le 0 ]; then
    echo "gc-bd-watch: could not parse --timeout=$TIMEOUT into seconds" >&2
    exit 2
fi
DEADLINE_TS=$(( $(date +%s) + TIMEOUT_SECS ))

# Retry loop: one producer + fifo per attempt; respawn at the last seen
# seq after a drop.
LAST_CURSOR="$CURSOR"
ATTEMPTS=0
BACKOFF="$BACKOFF_INITIAL"
EXIT_REASON=""

while : ; do
    NOW=$(date +%s)
    REMAINING=$(( DEADLINE_TS - NOW ))
    if [ "$REMAINING" -le 0 ]; then
        EXIT_REASON="timeout"
        break
    fi

    # Fresh fifo per attempt: no straggling writes from a killed producer.
    FIFO=$(mktemp -u -t gc-bd-watch.XXXXXX) || {
        echo "gc-bd-watch: failed to allocate fifo path" >&2
        exit 1
    }
    mkfifo "$FIFO"

    # --type isn't repeatable; filter type in the loop (payload-match
    # already narrows to one bead).
    timeout "${REMAINING}s" gc events --follow --after "$LAST_CURSOR" --payload-match "bead.id=$BEAD" \
        > "$FIFO" 2>/dev/null &
    PRODUCER=$!

    # read returns non-zero on EOF = producer exited.
    ATTEMPT_REASON=""
    while IFS= read -r LINE; do
        [ -n "$LINE" ] || continue
        # Advance the cursor on every event; forward progress resets the
        # reconnect budget.
        SEQ="$(printf '%s\n' "$LINE" | jq -r '.seq // empty' 2>/dev/null || true)"
        if [ -n "$SEQ" ] && printf '%s' "$SEQ" | grep -Eq '^[0-9]+$' && [ "$SEQ" != "$LAST_CURSOR" ]; then
            LAST_CURSOR="$SEQ"
            ATTEMPTS=0
            BACKOFF="$BACKOFF_INITIAL"
        fi
        TYPE="$(printf '%s\n' "$LINE" | jq -r '.type // empty' 2>/dev/null || true)"
        case "$TYPE" in
            bead.updated|bead.closed) ;;
            *) continue ;;
        esac
        NEW="$(printf '%s\n' "$LINE" | jq -r '.payload.bead.status // empty' 2>/dev/null || true)"
        [ -n "$NEW" ] || continue
        [ "$NEW" = "$PRIOR" ] && continue
        emit_change "$PRIOR" "$NEW"
        PRIOR="$NEW"
        if [ "$NEW" = "closed" ]; then
            ATTEMPT_REASON="closed"
            break
        fi
    done <"$FIFO"

    # Teardown: reap PRODUCER before clearing it (or the EXIT trap leaks
    # the follow process). EOF = producer already exited, wait classifies
    # it; a terminal event = producer still alive, kill then reap.
    if [ -z "$ATTEMPT_REASON" ]; then
        PRODUCER_EXIT=0
        wait "$PRODUCER" 2>/dev/null || PRODUCER_EXIT=$?
        case "$PRODUCER_EXIT" in
            124) ATTEMPT_REASON="timeout" ;;
            0)   ATTEMPT_REASON="stream_ended_before_terminal" ;;
            *)   ATTEMPT_REASON="stream_error_$PRODUCER_EXIT" ;;
        esac
    else
        kill "$PRODUCER" 2>/dev/null || true
        wait "$PRODUCER" 2>/dev/null || true
    fi
    PRODUCER=""
    rm -f "$FIFO"
    FIFO=""

    case "$ATTEMPT_REASON" in
        closed)
            EXIT_REASON="closed"
            break
            ;;
        timeout)
            # The per-attempt bound IS the remaining global budget.
            EXIT_REASON="timeout"
            break
            ;;
        stream_error_*|stream_ended_before_terminal)
            ATTEMPTS=$(( ATTEMPTS + 1 ))
            if [ "$ATTEMPTS" -ge "$MAX_RECONNECT" ]; then
                # Persistent failure keeps the per-attempt reason.
                EXIT_REASON="$ATTEMPT_REASON"
                break
            fi
            emit_reconnect "$ATTEMPTS" "$ATTEMPT_REASON"
            # Don't sleep past the deadline.
            NOW=$(date +%s)
            REMAINING=$(( DEADLINE_TS - NOW ))
            if [ "$REMAINING" -le 0 ]; then
                EXIT_REASON="timeout"
                break
            fi
            SLEEP_TIME="$BACKOFF"
            [ "$SLEEP_TIME" -gt "$REMAINING" ] && SLEEP_TIME="$REMAINING"
            sleep "$SLEEP_TIME"
            BACKOFF=$(( BACKOFF * 2 ))
            ;;
    esac
done

emit_end "$EXIT_REASON"

case "$EXIT_REASON" in
    closed)  exit 0 ;;
    timeout) exit 124 ;;
    *)       exit 1 ;;
esac
