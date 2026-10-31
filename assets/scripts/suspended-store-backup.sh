#!/usr/bin/env bash
# suspended-store-backup.sh — back up the suspended rigs' stores that still take
# writes.
#
# Gas City's mol-dog-backup order backs up every bead scope except a suspended
# rig's, because a bd call restarts the scope's retired proxy and Dolt, and
# nothing writes to the scope while it is suspended. A rig whose
# .beads/config.yaml sets gc.endpoint_origin: inherited_city meets neither. It has
# no Dolt of its own, the city's server keeps running, and sessions elsewhere keep
# filing and updating beads in its store.
#
# A pass covers every rig `gc rig list --json` reports as suspended whose store
# inherits the city's endpoint and has a registered backup destination
# (.beads/dolt-backup.json). It leaves alone a running rig, which mol-dog-backup
# covers, and a suspended rig with any other endpoint origin, whose store
# suspension may really have stopped.
#
# Only bd's sync writes .beads/dolt-backup-state.json, which the doctor's
# bd-backup-freshness check and the controller's retention watchdog read, so each
# store goes through `gc bd --city <city> --rig <rig> backup sync`.
#
# Each sync holds mol-dog-backup's lock, so the two orders never overlap on the
# Dolt server. The wait for it outlasts that order's run: both run every six
# hours, and a wait that gave up early could lose the lock on every cycle. The
# lock is released between stores, because mol-dog-backup waits only seconds for
# it (GC_DOLT_BACKUP_LOCK_WAIT_SECONDS, default 5) and then skips its whole cycle.
# A single sync slower than that wait can still make it skip one, and the backup
# alarms then flag the stores it covers.
#
# The alarms judge these stores as they judge any other, so a pass that stops
# working shows up as a stale store as well as in the order's outcome.
#
# Usage: suspended-store-backup.sh    (takes no arguments)
# Env: GC_CITY_PATH                      the city; an order run always has it
#      GC_DOLT_BACKUP_LOCK_FILE          mol-dog-backup's lock, read as that order
#                                        reads it (default
#                                        <city>/.gc/runtime/packs/dolt/backup-sync.lock)
#      GC_SUSPENDED_BACKUP_LOCK_WAIT     seconds to wait for the lock (default
#                                        1860, past mol-dog-backup's 1800s timeout).
#                                        A city that raises that timeout raises this.
#      GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS  seconds one sync may take, read as
#                                        mol-dog-backup reads it (default 120)
# Exit: 0 every covered store synced, or no store is covered · 1 a sync failed, or
#       the pass could not read the rig map or take the lock · 2 usage
# Caller: the suspended-store-backup exec order.
set -uo pipefail

PROG="suspended-store-backup"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# pass_child, which keeps the lock's descriptor from a program a sync starts.
# shellcheck source=bd-lib.sh
. "$HERE/bd-lib.sh" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }

[ "$#" -eq 0 ] || { echo "usage: $PROG.sh   (takes no arguments)" >&2; exit 2; }
[ -n "${GC_CITY_PATH:-}" ] || { echo "$PROG: GC_CITY_PATH is not set, so there is no city to back up" >&2; exit 2; }
cd -- "$GC_CITY_PATH" 2>/dev/null || { echo "$PROG: cannot enter the city at $GC_CITY_PATH" >&2; exit 2; }
CITY="$(pwd -P)"

: "${GC_SUSPENDED_BACKUP_LOCK_WAIT:=1860}"
: "${GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS:=120}"
for v in GC_SUSPENDED_BACKUP_LOCK_WAIT GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS; do
    case "${!v}" in
        '' | *[!0-9]*) echo "$PROG: $v='${!v}' is not a whole number of seconds above 0" >&2; exit 2 ;;
    esac
    [ "${!v}" -gt 0 ] || { echo "$PROG: $v='${!v}' is not a whole number of seconds above 0" >&2; exit 2; }
done
LOCK="${GC_DOLT_BACKUP_LOCK_FILE:-$CITY/.gc/runtime/packs/dolt/backup-sync.lock}"

command -v flock >/dev/null 2>&1 || {
    echo "$PROG: flock not found on PATH, so a sync could overlap mol-dog-backup's; nothing was synced" >&2
    exit 1
}

# The endpoint origin as Gas City reads it from a scope's config: the first
# top-level gc.endpoint_origin line with a value.
endpoint_origin() {
    awk '/^gc\.endpoint_origin[[:space:]]*:/ {
        v = $0
        sub(/^[^:]*:[[:space:]]*/, "", v)
        sub(/[[:space:]]+$/, "", v)
        if (v != "") { print v; exit }
    }' "$1" 2>/dev/null
}

# rig-map.sh writes to stderr only when the listing did not read, and then names
# the reason.
MAP="$("$HERE/rig-map.sh" --city "$CITY" 2>&1)" || { printf '%s\n' "$MAP" >&2; exit 1; }
ROWS="$(printf '%s' "$MAP" | jq -r '.rigs[] | select((.hq // false) == false and .suspended == true) | .name, .path')" || {
    echo "$PROG: could not read the rig map: $MAP" >&2
    exit 1
}

COVERED=()
while IFS= read -r name && IFS= read -r root; do
    origin="$(endpoint_origin "$root/.beads/config.yaml")"
    if [ "$origin" != inherited_city ]; then
        echo "$PROG: $name: left alone, its endpoint origin is ${origin:-not recorded}"
    elif [ ! -f "$root/.beads/dolt-backup.json" ]; then
        echo "$PROG: $name: left alone, it has no registered backup destination"
    else
        COVERED+=("$name")
    fi
done < <(printf '%s\n' "$ROWS")

if [ "${#COVERED[@]}" -eq 0 ]; then
    echo "$PROG: no suspended rig's store needs this backup"
    exit 0
fi

mkdir -p "$(dirname -- "$LOCK")" 2>/dev/null
exec 9>>"$LOCK" || { echo "$PROG: cannot open the lock $LOCK; nothing was synced" >&2; exit 1; }

# A sync's output goes to a file, so the bound on the sync is all that can hold
# the pass: a program it leaves running could keep a pipe open for good.
LOG="$(mktemp "${TMPDIR:-/tmp}/$PROG.XXXXXX" 2>/dev/null)" || LOG=""
trap '[ -z "$LOG" ] || rm -f "$LOG"' EXIT

TO=""
for t in timeout gtimeout; do command -v "$t" >/dev/null 2>&1 && { TO="$t"; break; }; done

# With no --foreground, the bound signals the whole group it starts, which holds
# the bd that gc bd runs as a child.
sync_store() { # <rig>
    if [ -n "$TO" ]; then
        pass_child "$TO" -k 5 "$GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS" gc bd --city "$CITY" --rig "$1" backup sync </dev/null
    else
        pass_child gc bd --city "$CITY" --rig "$1" backup sync </dev/null
    fi
}

# The end of a failed sync's output, where bd names the reason, on one line. It
# reaches the order.failed event, whose tail is short.
output_tail() {
    [ -n "$LOG" ] || return 0
    LC_ALL=C tail -c 300 "$LOG" | LC_ALL=C tr -s '[:space:]' ' ' | LC_ALL=C sed -e 's/^ //' -e 's/ $//'
}

SYNCED=0
FAILED=()
LOCK_LOST=""
for rig in "${COVERED[@]}"; do
    if [ -z "$LOCK_LOST" ] && ! flock -w "$GC_SUSPENDED_BACKUP_LOCK_WAIT" 9; then
        LOCK_LOST=1
    fi
    if [ -n "$LOCK_LOST" ]; then
        FAILED+=("$rig: not synced, mol-dog-backup's lock stayed held past ${GC_SUSPENDED_BACKUP_LOCK_WAIT}s")
        continue
    fi
    rc=0
    sync_store "$rig" >"${LOG:-/dev/null}" 2>&1 || rc=$?
    flock -u 9
    case "$rc" in
        0)
            SYNCED=$((SYNCED + 1))
            echo "$PROG: $rig: synced"
            ;;
        124 | 137) FAILED+=("$rig: backup sync timed out after ${GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS}s") ;;
        *) FAILED+=("$rig: backup sync exited $rc: $(output_tail)") ;;
    esac
done

echo "$PROG: synced $SYNCED of ${#COVERED[@]}"
[ "${#FAILED[@]}" -gt 0 ] || exit 0
for f in "${FAILED[@]}"; do
    printf '%s: %s\n' "$PROG" "$f"
done
exit 1
