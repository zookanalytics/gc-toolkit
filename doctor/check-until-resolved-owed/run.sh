#!/usr/bin/env bash
# doctor/check-until-resolved-owed — a resolved-by disposition is firing or
# surfaced. A bead carrying an `until` edge means "X resolves me": when that
# target closes, the deferred-dispatch reconcile order (orders/deferred-dispatch.toml,
# a 5m cooldown) disposes the bead through bead-rehome, so a wait whose named cause has
# landed is closed with a successor pointer rather than re-entering triage. The
# pass disposes an OPEN, UNASSIGNED bead whose own `until` targets have all
# closed, so a healthy resolved-by edge is short-lived: it rests until its target
# closes, then is disposed within a cadence.
#
# The silent stall this catches, caught nowhere else: the bead is open and
# unassigned, every one of its `until` targets has closed, no open `blocks`
# blocker still holds it, yet it has stayed undisposed well past the reconcile
# cadence since it became owed. Either the order is not running
# (check-cadence-live/I10 is the direct cause, but a single owed disposition
# makes the effect concrete), its passes spend their budget before they reach
# the bead, or the close is stuck. The common stuck case is a legitimate hold:
# an OPEN visit on the bead holds its close (bead-rehome refuses rather than
# forcing it), and the remedy is to conclude that visit; the other is a
# resolve-by edge no longer wanted, removed with `gc bd dep remove`.
#
# A bead became owed at the latest of its `until` targets' closes, its `until`
# edges' creation, and its `blocks` blockers' closes, so an edge added to a
# target that closed days ago starts its wait when the edge is added. Which
# beads are owed, and the fresh read of one before it is reported, come from
# assets/scripts/until-resolved.sh, the file the reconcile pass decides and
# re-reads through, so this check reports what that pass does.
#
# ONLY `until` makes a bead owed. A `blocks` edge is sequencing — its target
# closing leaves the dependent fully owed — so it is never a disposal and a bead
# held by an open `blocks` blocker is correctly waiting, never flagged. A bead already assigned is
# a live worker's, and reconcile would not dispose over it; a non-open bead is a
# deliberate hold the pass leaves alone; neither is owed a disposition.
#
# A bead that carries live work is never disposed either, and the marks that
# say so come from assets/scripts/live-work.sh, read through until-resolved.sh
# as the pass reads it: an anchor with a PR, work slung to a pool, a kind
# another component closes, a convoy or an open child on its edges. Once such a
# bead has been owed past the window, it is reported as a decision for a
# person: remove the edge if the work is still wanted, or retire the work. That
# is not the order failing, so the finding says which it is.
#
# Read-only. Exit 0=OK 1=Warning. stdout: first line = message, then
# "  - detail" lines. Warn-only. An UNREADABLE probe warns (1), never passes —
# an unread store is not a clean one.

set -u

# Which beads are owed and what a fresh read finds on one, from the file the
# reconcile pass reads (it reads live work from live-work.sh). An unsourceable
# one warns: without it a bead the pass leaves alone would read as a disposition
# the order failed to make.
# shellcheck source=../../assets/scripts/until-resolved.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/until-resolved.sh" || {
    echo "cannot determine whether owed resolved-by dispositions are firing"
    printf '  - %s\n' "assets/scripts/until-resolved.sh, or the live-work.sh it reads, could not be sourced from this pack, so what the reconcile pass would dispose cannot be told."
    exit 1
}

# The owed window is the deferred-dispatch order's cadence window, from the one
# definition check-cadence-live (I10) also reads: max(3×interval, one trip of
# the order dispatch rotation). It is computed below, once the probes have their
# budget. Unsourceable, no disposition's wait can be judged, so the check warns.
# shellcheck source=../../assets/scripts/order-cadence.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/order-cadence.sh" || {
    echo "cannot determine whether owed resolved-by dispositions are firing"
    printf '  - %s\n' "assets/scripts/order-cadence.sh could not be sourced from this pack, so the window an owed disposition is judged by cannot be computed."
    exit 1
}

findings=(); livework=(); warnings=(); notes=()
# >>> doctor-budget
# One deadline for the whole check, anchored at process start. `gc doctor
# --check-timeout` (default 60s) abandons an overrunning check and discards
# everything it had buffered, so a check that has not printed by then is never
# heard. A per-probe constant does not hold that line: the probes below run
# once per rig, so their ceilings sum. Each probe gets the time still left
# instead, capped at half the budget so one wedged store cannot eat the rest,
# and a probe that no longer fits is refused with 124 — `timeout`'s own expiry
# code, which every caller's "this store was NOT checked" arm already handles.
# GC_DOCTOR_CHECK_TIMEOUT overrides the default, in whole seconds. Nothing
# exports it: the runner passes GC_CITY_PATH and GC_PACK_DIR and no budget.
BUDGET_DEFAULT=60; BUDGET_RESERVE=5; BUDGET_MIN_PROBE=2
budget_now() { if [ -n "${EPOCHSECONDS:-}" ]; then printf %s "$EPOCHSECONDS"; else date +%s; fi; }
budget_init() {
    BUDGET_TOTAL="${GC_DOCTOR_CHECK_TIMEOUT:-$BUDGET_DEFAULT}"; BUDGET_TOTAL="${BUDGET_TOTAL%s}"
    case "$BUDGET_TOTAL" in ''|*[!0-9]*) BUDGET_TOTAL="$BUDGET_DEFAULT" ;; esac
    BUDGET_CAP=$(( BUDGET_TOTAL / 2 ))
    BUDGET_DEADLINE=$(( $(budget_now) - SECONDS + BUDGET_TOTAL - BUDGET_RESERVE ))
}
budget_slice() {
    local left=$(( BUDGET_DEADLINE - $(budget_now) ))
    [ "$left" -le "$BUDGET_CAP" ] || left="$BUDGET_CAP"
    [ "$left" -ge 0 ] || left=0
    printf %s "$left"
}
budget_spent() { [ "$(budget_slice)" -lt "$BUDGET_MIN_PROBE" ]; }
run_bounded() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@" </dev/null; else "$@" </dev/null; fi; }
# A probe fed from a pipe cannot borrow run_bounded's </dev/null.
run_piped() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi; }
budget_init
# <<< doctor-budget
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

now_epoch() { budget_now; }
# ISO-8601 UTC -> epoch seconds, or empty if it will not parse (GNU then BSD).
iso_to_epoch() {
    [ -n "$1" ] || { printf ''; return; }
    date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || printf ''
}

# A resolved bead is disposed on the deferred-dispatch order's next pass, so a
# disposition owed longer than that order's cadence window has waited through a
# gap I10 would call a stopped order. The interval is the one this pack declares
# for the order, and the floor comes from the live registry and the city's
# dispatch budget.
city_root="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
dd_secs=$(cadence_order_interval "${GC_PACK_DIR:-.}/orders/deferred-dispatch.toml")
orders_json=$(run_bounded gc order list --json 2>/dev/null)
if [ -n "$(cadence_clock_registrations "$orders_json")" ]; then
    owed_floor=$(cadence_floor "$orders_json" "${city_root:+$city_root/city.toml}")
else
    owed_floor="$CADENCE_FLOOR_MIN"
    notes+=("the order registry (\`gc order list --json\`) did not read, so the owed window uses the ${CADENCE_FLOOR_MIN}s minimum floor, not one trip of the dispatch rotation")
fi
OWED_WINDOW_SECONDS=$(cadence_window "${dd_secs:-0}" "$owed_floor")

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)] | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether owed resolved-by dispositions are firing"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

now=$(now_epoch)
# The store under scan, for the reader until-resolved.sh is handed: every read
# pinned to it and bounded by what is left of the budget.
RIG_DB=""
rig_bd() { run_bounded gc bd --db "$RIG_DB" "$@"; }
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    # A suspended rig's store is cold; querying it would auto-start an orphan
    # Dolt server, so it is skipped the way the sibling store checks skip it.
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    RIG_DB="$rig_path/.beads"
    # One listing of the store and one status read of every bead the
    # candidates' edges name, decided per candidate as the pass decides it.
    scan_rc=0
    rows=$(until_scan rig_bd) || scan_rc=$?
    case "$scan_rc" in
        0) ;;
        2) warnings+=("$label: could not read until-target/blocker statuses in $RIG_DB — this store was NOT checked"); continue ;;
        *) warnings+=("$label: could not list open beads in $RIG_DB — this store was NOT checked"); continue ;;
    esac
    [ -n "$rows" ] || continue

    while IFS=$'\t' read -r cid state succ since utargets _ detail marks; do
        [ -n "$cid" ] || continue
        case "$state" in
            owed) ;;
            unresolved)
                warnings+=("$label bead $cid: could not resolve its until target(s)/blocker(s) [$detail] in $RIG_DB — NOT checked")
                continue ;;
            *) continue ;;   # an until target still open, or held by its own open `blocks` blocker: correctly waiting
        esac
        since_epoch=$(iso_to_epoch "$since")
        # Cannot bound the age: skip rather than cry wolf — the next sweep sees a
        # readable timestamp, and a real stall persists to be caught then.
        [ -n "$since_epoch" ] || continue
        age=$(( now - since_epoch ))
        [ "$age" -ge "$OWED_WINDOW_SECONDS" ] || continue
        # A clean row still needs the fresh read the pass makes before a close:
        # a convoy tracking the bead or an open child under it is live work no
        # row field shows, and an edge removed or a blocker added since the
        # listing means the pass would not dispose it either.
        if [ "$marks" = "-" ]; then
            if ! fresh=$(until_fresh rig_bd "$cid" "$succ") || [ -z "$fresh" ]; then
                warnings+=("$label bead $cid: could not read it and its dependents in $RIG_DB, so live work on its edges cannot be ruled out — NOT checked")
                continue
            fi
            case "${fresh%%$'\t'*}" in
                clear) ;;
                live) marks="${fresh#*$'\t'}" ;;
                *) continue ;;   # gone, waiting or blocked at the fresh read: not owed now
            esac
        fi
        if [ "$marks" != "-" ]; then
            livework+=("$label bead $cid: its \`until\` resolved-by target(s) [$utargets] have been closed, and it has been owed for ${age}s, but it carries live work ($marks), which the deferred-dispatch reconcile pass never disposes. A person decides: if the work is still wanted, remove the resolve-by edge (gc bd dep remove $cid <target>); if the target's close made it moot, retire the work and dispose $cid by ruling")
        else
            findings+=("$label bead $cid: its \`until\` resolved-by target(s) [$utargets] have been closed, and it has been owed for ${age}s (> ${OWED_WINDOW_SECONDS}s), but it has not been disposed. The deferred-dispatch reconcile pass disposes an owed \`until\` bead on its next pass, and ${OWED_WINDOW_SECONDS}s is that order's cadence window, so a disposition owed this long means that order is not firing (check-cadence-live/I10), its passes spend their budget before they reach $cid, or the close is stuck — commonly an open visit on $cid holds it (conclude the visit), or the resolve-by edge is no longer wanted (remove it: gc bd dep remove $cid <target>)")
        fi
    done <<< "$rows"
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every store was scanned — what follows is partial, and a store skipped for time is not a store that passed")
fi
if [ "${#findings[@]}" -ne 0 ] || [ "${#livework[@]}" -ne 0 ] || [ "${#warnings[@]}" -ne 0 ]; then
    if [ "${#findings[@]}" -ne 0 ]; then
        echo "resolved-by dispositions owed but not firing: ${#findings[@]} finding(s)"
        detail "${findings[@]}"
        detail ${livework[@]+"${livework[@]}"}
        detail ${warnings[@]+"${warnings[@]}"}
    elif [ "${#livework[@]}" -ne 0 ]; then
        echo "resolved-by beads left open because they carry live work: ${#livework[@]} bead(s) need a person's decision"
        detail "${livework[@]}"
        detail ${warnings[@]+"${warnings[@]}"}
    else
        echo "until-resolved-owed check ran partially"
        detail "${warnings[@]}"
    fi
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every resolved-by (\`until\`) bead is waiting on its target, held by its own blocker, or disposed within cadence"
detail ${notes[@]+"${notes[@]}"}
exit 0
