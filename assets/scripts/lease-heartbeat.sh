#!/usr/bin/env bash
# lease-heartbeat.sh — keep the HOLDER's own claim lease in the future for the
# lifetime of a long command, so a live holder is never mistaken for a dead one.
#
#   lease-heartbeat.sh <bead-id> -- <command> [args...]
#
# A `gc hook --claim` stamps a lease with a fixed five-minute TTL; a long test
# run (the full suite is ~25m, a single file budgeted 15m) outlives it, and a
# live holder that lets its lease expire reads, to any lease consumer, exactly
# like a dead one. This runs <command> and, every LEASE_HEARTBEAT_INTERVAL
# seconds while it runs, refreshes <bead-id> with `gc bd heartbeat`. It exits
# with <command>'s status; a heartbeat that fails or stalls never fails the
# command — the lease is a best-effort liveness hint, not a gate.
#
# HOLDER-ONLY, BY DESIGN: `gc bd heartbeat` is owner-only, and only the holding
# session can refresh its own claim — heartbeatActorForOwnedClaim (gascity
# cmd/gc/cmd_bd.go) overrides the heartbeat actor to the bead's assignee only
# when that assignee is one of the CALLER's own GC_SESSION_* identities. A sweep
# from outside the session carries different identities and is refused, so this
# wraps the holder's own command rather than ticking from a central cadence.
# Heartbeats write only the dolt_ignored `leases` table, so they cost no Dolt
# commit however often they fire.
set -u

PROG=$(basename "$0")
usage() { echo "usage: $PROG <bead-id> -- <command> [args...]" >&2; exit 2; }

case "${1:-}" in -h|--help) echo "usage: $PROG <bead-id> -- <command> [args...]"; exit 0 ;; esac

BEAD="${1:-}"; [ -n "$BEAD" ] || usage; shift
[ "${1:-}" = "--" ] || usage; shift
[ "$#" -gt 0 ] || usage

# Cadence under the fixed five-minute TTL (120s leaves a >2x margin); POLL is how
# promptly the wrapper returns after the command exits. Both overridable, chiefly
# for the test; a non-numeric override falls back to the default rather than
# aborting the wrapped command.
INTERVAL="${LEASE_HEARTBEAT_INTERVAL:-120}"
POLL="${LEASE_HEARTBEAT_POLL:-5}"
HB_TIMEOUT="${LEASE_HEARTBEAT_HB_TIMEOUT:-15}"
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=120 ;; esac
case "$POLL" in ''|*[!0-9]*) POLL=5 ;; esac

# Bounded and silenced: a wedged store must not stall the wrapper after its
# command has finished, and a refusal (no lease, a lost claim) must not surface
# as a failure of the wrapped command.
heartbeat() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$HB_TIMEOUT" gc bd heartbeat "$BEAD" >/dev/null 2>&1 || true
    else
        gc bd heartbeat "$BEAD" >/dev/null 2>&1 || true
    fi
}

heartbeat   # fresh from the first second, before the command even starts

# Run the command in the background so this shell can tick alongside it; its
# stdout/stderr are inherited, so the holder still sees the command's output.
"$@" &
CMD_PID=$!
# A signalled wrapper tears its command down rather than orphaning a live run.
trap 'kill "$CMD_PID" 2>/dev/null' TERM INT HUP

# Poll on a short cadence so the wrapper returns promptly once the command
# exits, and heartbeat every INTERVAL seconds in between.
waited=0
while kill -0 "$CMD_PID" 2>/dev/null; do
    sleep "$POLL"
    waited=$((waited + POLL))
    if [ "$waited" -ge "$INTERVAL" ]; then
        kill -0 "$CMD_PID" 2>/dev/null && heartbeat
        waited=0
    fi
done

wait "$CMD_PID"
exit $?
