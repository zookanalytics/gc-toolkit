#!/usr/bin/env bash
# dolt-reclaim.sh — size-triggered reclaim of the managed Dolt stores.
#
# A Dolt store retains the chunks of every reachable commit, so a store that
# churns grows on disk even when its live rows do not. Scheduled
# `gc dolt compact` (no flags) only flattens a store once it passes a
# commit-count threshold (GC_DOLT_COMPACT_THRESHOLD_COMMITS, default 2000); a
# store flattened once drops below that count, then keeps accumulating on-disk
# chunk history — the chunk journal, newgen archive tables, and oldgen alike —
# that the scheduled pass skips from then on. The sanctioned recovery is
# `gc dolt compact --gc-only`, which runs `CALL DOLT_GC('--full')` regardless of
# commit count and rewrites the whole store — and nothing re-runs it on a
# cadence.
#
# This pass reads each store's on-disk noms SIZE, not its commit count, and
# runs `gc dolt compact --gc-only --only-db <db>` on every store whose noms is
# at or over GC_DOLT_RECLAIM_THRESHOLD_MIB. The default is the 2 GiB per-database
# line the gascity `dolt-noms-size` doctor check warns at, so a store is
# reclaimed when its own footprint reaches the size that check flags. Lower it
# to reclaim before the warning fires.
#
# It NEVER runs a bare flatten. A flatten rewrites commit history, may
# force-push a shared remote, and the bloat-recovery runbook names preconditions
# (stop writers, take a backup); auto-running it is the operator's call and
# stays manual. `--gc-only` keeps the managed server up and needs no stop, which
# is the pass the operator approved for this cadence. If the deployed
# `gc dolt compact` has no `--gc-only`, this pass refuses rather than fall back
# to the flatten.
#
# The order's interval is the only cooldown: the script holds no state, so a
# store that stays over the line is reclaimed once per interval and no more. A
# reclaim never starts while the data plane is unreachable or overloaded — a
# full GC is heavy, and piling it onto a degraded server is the amplifier this
# brake removes.
#
# Reclaim is reported as MEASURED before/after noms bytes, never as a count of
# stores touched: a `--gc-only` pass that frees nothing (a store whose size is
# live data, not dead chunks) reads the same as one that errored unless the
# bytes are measured.
#
# Usage:
#   dolt-reclaim.sh              reclaim every over-threshold store, print a summary
#   dolt-reclaim.sh --dry-run    report the plan, mutate nothing
# Env: GC_DOLT_RECLAIM_THRESHOLD_MIB  per-db noms size (MiB) that triggers a
#                                     reclaim (default 2048 = 2 GiB)
#      GC_DOLT_RECLAIM_BUDGET         seconds after which the pass stops starting
#                                     new reclaims and leaves the rest to the
#                                     next pass; a reclaim already running is not
#                                     interrupted (default 1200, 0 disables). Set
#                                     below the order timeout by at least one
#                                     store's GC, so the last reclaim started
#                                     finishes before the order's hard kill.
#      GC_DOLT_RECLAIM_HEALTH_TIMEOUT seconds bounding the pre-reclaim Dolt health
#                                     probe (default 20)
# Exit: 0 reclaimed, or nothing over the line · 1 a reclaim was attempted and
#       failed · 2 usage, or the pass could not run at all (no gc, no --gc-only,
#       no database list).
# Caller: the dolt-reclaim exec order. See docs/dolt-reclaim.md.
set -euo pipefail

PROG="${0##*/}"

usage() { sed -n '/^# Usage:/,/^# Caller:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h | --help) usage; exit 0 ;;
        *) echo "$PROG: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

THRESHOLD_MIB="${GC_DOLT_RECLAIM_THRESHOLD_MIB:-2048}"
BUDGET="${GC_DOLT_RECLAIM_BUDGET:-1200}"
HEALTH_TIMEOUT="${GC_DOLT_RECLAIM_HEALTH_TIMEOUT:-20}"
for v in THRESHOLD_MIB BUDGET HEALTH_TIMEOUT; do
    case "${!v}" in
        '' | *[!0-9]*) echo "$PROG: GC_DOLT_RECLAIM_$v must be a whole number" >&2; exit 2 ;;
    esac
done
[ "$THRESHOLD_MIB" -gt 0 ] || { echo "$PROG: GC_DOLT_RECLAIM_THRESHOLD_MIB must be positive" >&2; exit 2; }
# du reports in KiB; keep the comparison in KiB so no multiplication overflows.
THRESHOLD_KB=$(( THRESHOLD_MIB * 1024 ))

GC="$(command -v gc 2>/dev/null || true)"
[ -n "$GC" ] || { echo "$PROG: gc is not on PATH — cannot reclaim" >&2; exit 2; }

# Resolve the city. A hand run carries it in the environment; the cooldown-order
# supervisor that runs this on a cadence does NOT (city-scoped exec gets a bare
# env), so env-only resolution would silently find no databases every tick. Try
# the env chain first — so an operator's probe hits the city they meant — then
# fall back to `gc service list`, which reads the running services and reports
# their city. Fail loud if neither answers rather than reclaim the wrong city or
# none.
CITY_PATH="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
if [ -z "$CITY_PATH" ]; then
    CITY_PATH="$("$GC" service list --json 2>/dev/null | jq -r '.city_path // empty' 2>/dev/null || true)"
fi
[ -n "$CITY_PATH" ] || { echo "$PROG: cannot resolve the city (GC_CITY_PATH unset and 'gc service list' reported no city_path)" >&2; exit 2; }

# compact and health reject a --city flag (only `gc dolt list` honors it), so
# the resolved city reaches every leaf through the environment. Export it once
# to hold a single city across the whole pass.
export GC_CITY_PATH="$CITY_PATH"

# Refuse unless the deployed compact offers --gc-only. Falling back to a bare
# `gc dolt compact` would run the flatten this cadence must never auto-run, so a
# stale dolt pack is a hard stop, not a downgrade. Capture the help and match it
# with a pipe-free `case`: `--help | grep -q` lets grep close the pipe on its
# first match, SIGPIPE the writer, and — under `set -o pipefail` — return 141
# for a match that succeeded, which would read as "flag absent" at random.
COMPACT_HELP="$("$GC" dolt compact --help 2>&1 || true)"
case "$COMPACT_HELP" in
    *--gc-only*) ;;
    *) echo "$PROG: the deployed 'gc dolt compact' has no --gc-only flag (stale dolt pack); refusing to run a bare flatten" >&2
       exit 2 ;;
esac

# Managed databases as name<TAB>path. `gc dolt list` prints that TSV; keep only
# rows whose second field is an absolute path, so a stray warning line cannot be
# read as a database named after its own prose.
DB_TSV="$("$GC" dolt list 2>/dev/null | awk -F'\t' 'NF >= 2 && $2 ~ /^\// { print $1 "\t" $2 }' || true)"
if [ -z "$DB_TSV" ]; then
    echo "$PROG: 'gc dolt list' returned no databases — nothing to reclaim" >&2
    exit 2
fi

# Disk usage of a directory in KiB, or empty when it cannot be read (an absent
# noms dir, a store being written under the walk). du walks a live tree, so a
# vanished entry is an expected non-zero exit, not a reason to abandon the pass.
noms_kb() { du -sk "$1" 2>/dev/null | awk 'NR == 1 { print $1 }' || true; }
gib() { awk -v kb="$1" 'BEGIN { printf "%.2f", kb * 1024 / 1073741824 }'; }

# First pass: measure every store and collect the ones at or over the line.
# Printed in full so the order log carries the size of every store each cycle,
# not only the ones reclaimed — that is the record that shows a store climbing.
OVER=""           # name<TAB>noms_path<TAB>kb per over-threshold store
echo "$PROG: threshold ${THRESHOLD_MIB} MiB ($(gib "$THRESHOLD_KB") GiB) per database"
while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    noms="${path%/}/.dolt/noms"
    if [ ! -d "$noms" ]; then
        echo "  - $name: no noms directory at $noms — skipped"
        continue
    fi
    kb="$(noms_kb "$noms")"; kb="${kb:-0}"
    if [ "$kb" -ge "$THRESHOLD_KB" ]; then
        echo "  - $name: $(gib "$kb") GiB — OVER the line"
        OVER="$OVER$name	$noms	$kb
"
    else
        echo "  - $name: $(gib "$kb") GiB"
    fi
done <<< "$DB_TSV"

if [ -z "$OVER" ]; then
    echo "$PROG: no store is over the ${THRESHOLD_MIB} MiB line — nothing to reclaim"
    exit 0
fi

# A reclaim is a full GC; refuse to pile one onto a data plane that is already
# unreachable or overloaded, judged off the same server.reachable / 5000ms
# latency the deacon patrol uses. A broken or absent probe is unproven, never a
# reason to skip: the reclaim only proceeds when the plane is proven healthy
# enough OR the probe could not answer at all, and the heavy case this guards
# — a server answering slowly — is the one the probe does detect.
dolt_degraded() { # echoes a reason and returns 0 when degraded
    local out reachable latency rc=0
    # `|| rc=$?` keeps the failing probe from aborting the script under `set -e`
    # and captures timeout's 124 or the command's own code.
    out="$(timeout "$HEALTH_TIMEOUT" "$GC" dolt health --json 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 124 ]; then
        printf 'health probe exceeded %ss; data plane too slow to answer' "$HEALTH_TIMEOUT"; return 0
    fi
    [ "$rc" -eq 0 ] || return 1
    # Read reachable raw: jq's `//` treats false like null and would swallow the
    # very reachable:false this looks for.
    reachable="$(printf '%s' "$out" | jq -r '.server.reachable' 2>/dev/null || true)"
    [ "$reachable" = "false" ] && { printf 'Dolt server unreachable'; return 0; }
    latency="$(printf '%s' "$out" | jq -r '.server.latency_ms // empty' 2>/dev/null || true)"
    case "$latency" in
        '' | *[!0-9]*) return 1 ;;
        *) [ "$latency" -gt 5000 ] && { printf 'Dolt server latency %sms over 5000ms' "$latency"; return 0; } ;;
    esac
    return 1
}

if [ "$DRY_RUN" -eq 0 ] && DEGRADED="$(dolt_degraded)"; then
    echo "$PROG: deferred — $DEGRADED; the next pass reclaims once the data plane recovers"
    exit 0
fi

# Reclaim each over-threshold store. The budget stops the pass from STARTING a
# new reclaim once it is spent; a reclaim already running is never interrupted,
# because a GC killed mid-rewrite is exactly what leaves a store quarantined.
START="$(date +%s)"
over_budget() { [ "$BUDGET" -gt 0 ] && [ "$(( $(date +%s) - START ))" -ge "$BUDGET" ]; }

succeeded=0; failed=0; deferred=0
freed_kb=0
while IFS=$'\t' read -r name noms kb; do
    [ -n "$name" ] || continue
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "$PROG: DRY RUN — would run 'gc dolt compact --gc-only --only-db $name' ($(gib "$kb") GiB)"
        continue
    fi
    if over_budget; then
        echo "$PROG: $name deferred — ${BUDGET}s budget spent; the next pass takes it"
        deferred=$(( deferred + 1 ))
        continue
    fi
    # Re-check the data plane before every compact, not only once before the
    # loop: a --gc-only pass is a full GC and can leave the server slow or
    # unreachable, and the contract is that a reclaim never STARTS on a degraded
    # plane. Defer this store to the next pass; a later store still proceeds if
    # the plane has recovered by its turn.
    if DEGRADED="$(dolt_degraded)"; then
        echo "$PROG: $name deferred — $DEGRADED; the next pass reclaims once the data plane recovers"
        deferred=$(( deferred + 1 ))
        continue
    fi
    before="$(noms_kb "$noms")"; before="${before:-$kb}"
    rc=0
    "$GC" dolt compact --gc-only --only-db "$name" || rc=$?
    after="$(noms_kb "$noms")"; after="${after:-$before}"
    if [ "$rc" -eq 0 ]; then
        succeeded=$(( succeeded + 1 ))
        delta=$(( before - after )); [ "$delta" -ge 0 ] || delta=0
        freed_kb=$(( freed_kb + delta ))
        echo "$PROG: $name reclaimed $(gib "$delta") GiB ($(gib "$before") -> $(gib "$after") GiB)"
    else
        failed=$(( failed + 1 ))
        echo "$PROG: $name FAILED — 'gc dolt compact --gc-only --only-db $name' exited $rc ($(gib "$before") GiB, unchanged); it may be quarantined or need an operator" >&2
    fi
done <<< "$OVER"

if [ "$DRY_RUN" -eq 1 ]; then
    exit 0
fi

printf '%s: freed %s GiB — %d reclaimed, %d failed, %d deferred\n' \
    "$PROG" "$(gib "$freed_kb")" "$succeeded" "$failed" "$deferred"

[ "$failed" -eq 0 ]
