#!/bin/sh
# gc-bd-watch.sh — emit meaningful bead-state updates as JSONL.
#
# Usage: gc-bd-watch <bead-id> [--timeout=DURATION]
#
# Designed to be spawned as a background process by an agent's
# harness. Each stdout line is a self-contained JSON object; consumers
# parse line-by-line and match on `"type":"status_change"` (or the
# desired target status, e.g. `"to":"closed"`) to wake on real
# transitions.
#
# Claude Code example:
#   Bash(command: "<this script> <bead>", run_in_background: true)
#   Monitor that bash id for "status_change" lines
#
# DURATION accepts any value timeout(1) understands (e.g. 30s, 5m, 24h).
# Default: 24h. The watcher exits as soon as the bead reaches a terminal
# status (closed), the timeout fires, or the harness kills the process.
#
# Output grammar (one JSON object per line):
#   {"ts":"<rfc3339>","bead":"<id>","type":"watch_start","status":"<initial>"}
#   {"ts":"<rfc3339>","bead":"<id>","type":"status_change","from":"<prior>","to":"<new>"}
#   {"ts":"<rfc3339>","bead":"<id>","type":"watch_reconnect","attempt":<n>,"reason":"<retry-reason>"}
#   {"ts":"<rfc3339>","bead":"<id>","type":"watch_end","reason":"<reason>"}
#
# watch_end reasons:
#   closed                        — bead reached terminal status (closed)
#   already_closed                — bead was already closed at startup
#   timeout                       — timeout(1) wrapper fired or the total deadline expired
#   killed                        — TERM/INT/HUP received
#   startup_no_cursor             — gc events --seq did not return a usable cursor
#   stream_ended_before_terminal  — event stream closed cleanly before the bead reached a terminal status (after exhausting reconnects)
#   stream_error_<n>              — gc events --follow exited non-zero (n = exit code, after exhausting reconnects)
#
# Exit codes:
#   0   terminal status reached (closed, already_closed)
#   1   bead not found / startup error (incl. startup_no_cursor) / stream_ended_before_terminal / stream_error_<n>
#   2   usage error
#   124 timeout fired (also emits watch_end reason=timeout)
#   143 SIGTERM received (also emits watch_end reason=killed)
#
# Stream-error resilience. `gc events --follow` can drop for transient
# reasons (Dolt hiccup, connection blip, internal cursor issue) without
# the bead itself being terminal. The watcher wraps producer + consumer
# in a retry loop, advancing the resume cursor from each event's `.seq`
# so transitions emitted during the hiccup are replayed on reconnect.
# Each retry emits one `watch_reconnect` line and sleeps with exponential
# backoff before respawning. The reconnect budget resets whenever the
# stream makes forward progress (new `.seq`).
#
# Tunables (env vars):
#   GC_BD_WATCH_MAX_RECONNECT     — max consecutive failed reconnects before giving up (default 5)
#   GC_BD_WATCH_BACKOFF_INITIAL   — initial sleep between reconnects, in seconds; doubles per attempt (default 2)
#
# The total wall-clock budget is fixed at startup from --timeout — retries
# do NOT reset it. Per-attempt timeouts are computed against the original
# deadline, so an N-hour watch followed by reconnects is still bounded
# by the original N hours.
#
# Noise filtering. `bead.updated` fires on every metadata write, label
# change, and cache-reconcile pass — not just status changes. The script
# tracks the prior status in-process and emits `status_change` only on a
# real transition. Consumers' line-matches stay cheap.

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

# Reconnect tunables. Validated below — bad values fall back to defaults
# rather than fail at first arithmetic use, so a typo'd env var can't
# silently kill a long watch.
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

# State shared with the cleanup trap so signal handlers can tear down the
# producer cleanly without leaking a zombie `gc events --follow` process.
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
# EXIT runs cleanup unconditionally so a broken stdout consumer, a `set -e`
# trip on a failing jq write, or any other unexpected exit path still tears
# down the producer + FIFO. cleanup() is idempotent.
trap cleanup EXIT
trap on_kill TERM INT HUP
# SIGPIPE: ignore. Stdout is the notification channel; if the consumer
# disappears, jq's writes will fail with EPIPE rather than killing the
# process via signal. set -e then exits the script and the EXIT trap
# cleans up. The exit code will be non-zero (jq's write-error code),
# which is the right signal: the watch ended abnormally.
trap '' PIPE

# Snapshot the current event-stream cursor BEFORE reading the bead. Any
# status transitions that race between the bd show below and the follow
# stream are replayed from this cursor, so the watcher does not silently
# miss a transition that happened during startup.
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

# Cursor is the replay anchor for transitions that race against the
# `gc bd show` above. Between the `gc events --seq` and the bd show,
# the bead can transition; without `--after`, the follow stream starts
# at the current head and silently misses anything that happened in
# that startup window — exactly the lost-notification shape this
# watcher exists to prevent. Fail loud on a missing cursor rather than
# ship a watcher that can miss the window it was created for.
if ! printf '%s' "$CURSOR" | grep -Eq '^[0-9]+$'; then
    echo "gc-bd-watch: gc events --seq did not return a usable cursor; aborting" >&2
    emit_end startup_no_cursor
    exit 1
fi

PRIOR="$INIT"

# Wall-clock deadline. The per-attempt timeout is recomputed against this
# deadline each retry, so retries do not extend the total budget.
TIMEOUT_SECS="$(duration_to_seconds "$TIMEOUT")"
if ! printf '%s' "$TIMEOUT_SECS" | grep -Eq '^[0-9]+$' || [ "$TIMEOUT_SECS" -le 0 ]; then
    echo "gc-bd-watch: could not parse --timeout=$TIMEOUT into seconds" >&2
    exit 2
fi
DEADLINE_TS=$(( $(date +%s) + TIMEOUT_SECS ))

# Retry loop. Each iteration spawns one producer + drains its fifo. If
# the producer dies before the bead reaches a terminal status, we emit
# a `watch_reconnect` event, sleep with exponential backoff, and respawn
# at the most recently observed `seq` so transitions emitted during the
# hiccup are replayed. The attempts budget resets whenever the stream
# makes forward progress (cursor advances).
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

    # Per-attempt fifo. A fresh fifo per attempt avoids any chance of
    # straggling writes from the prior (killed) producer being read as
    # the next attempt's first line.
    FIFO=$(mktemp -u -t gc-bd-watch.XXXXXX) || {
        echo "gc-bd-watch: failed to allocate fifo path" >&2
        exit 1
    }
    mkfifo "$FIFO"

    # --type isn't repeatable; subscribe to all events for this bead and
    # filter type in the loop. The payload-match restricts to one bead-id,
    # so the stream is already narrow.
    timeout "${REMAINING}s" gc events --follow --after "$LAST_CURSOR" --payload-match "bead.id=$BEAD" \
        > "$FIFO" 2>/dev/null &
    PRODUCER=$!

    # Consume from the fifo. `read` returns non-zero on EOF, which is how
    # we detect the producer (or its wrapping timeout) exited.
    ATTEMPT_REASON=""
    while IFS= read -r LINE; do
        [ -n "$LINE" ] || continue
        # Advance the resume cursor on every event we see. Reset the
        # reconnect budget on real forward progress — five consecutive
        # failures with no event in between is the persistent-outage
        # signal we want to catch; a hiccup mid-watch is not.
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

    # Per-attempt teardown. Capture producer exit status before clearing
    # PRODUCER so the EXIT trap doesn't double-wait on a reaped pid.
    # `|| PRODUCER_EXIT=$?` keeps set -e from short-circuiting on non-zero
    # wait status — we explicitly want to inspect it.
    if [ -z "$ATTEMPT_REASON" ]; then
        PRODUCER_EXIT=0
        wait "$PRODUCER" 2>/dev/null || PRODUCER_EXIT=$?
        case "$PRODUCER_EXIT" in
            124) ATTEMPT_REASON="timeout" ;;
            0)   ATTEMPT_REASON="stream_ended_before_terminal" ;;
            *)   ATTEMPT_REASON="stream_error_$PRODUCER_EXIT" ;;
        esac
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
            # Per-attempt timeout is set to the remaining global budget,
            # so 124 here means the whole watch timed out.
            EXIT_REASON="timeout"
            break
            ;;
        stream_error_*|stream_ended_before_terminal)
            ATTEMPTS=$(( ATTEMPTS + 1 ))
            if [ "$ATTEMPTS" -ge "$MAX_RECONNECT" ]; then
                # Persistent failure: preserve the existing terminal
                # reasons so consumers keying on `stream_error_<n>` keep
                # working.
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
