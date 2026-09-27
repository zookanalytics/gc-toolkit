#!/usr/bin/env bash
# doctor/check-armed-dispatch-owed — an owed deferred dispatch is firing or
# surfaced. A bead armed with gc.dispatch_when_ready is slung by the
# deferred-dispatch reconcile order (orders/deferred-dispatch.toml, every 2m)
# once bd would let it dispatch. `arm` refuses a non-open bead and reconcile
# retires a closed or already-delivered one, so a healthy arm is short-lived:
# it waits on its own `blocks` blockers, then dispatches within a cadence of
# the last one closing.
#
# Two ways a dispatch stops firing SILENTLY, neither caught elsewhere:
#   * OWED-BUT-NOT-FIRING — the bead is open, its own `blocks` edges have all
#     closed, and it is not mid-dispatch, yet it has stayed armed well past the
#     reconcile cadence. Either the order is not running (check-cadence-live/I10
#     is the direct cause there, but a single owed arm makes the effect concrete)
#     or the dispatch is stuck. The is_blocked flag cascades DOWN parent-child
#     edges, so an armed epic child whose own blockers have closed is held out of
#     `bd list --ready` by its container's hold and appears in `bd blocked` under
#     the ANCESTOR's id, not its own — which is why check-blocked-work-armed
#     (unarmed blocked work, keyed on the bead's own blocked state) cannot see it.
#   * STRANDED — the bead is armed at a non-open status, which `bd list --ready`
#     never answers, so no blocker closing will ever dispatch it (a bead armed
#     while open, then held). reconcile prints this to its own log every pass, but
#     nothing surfaces it to a person.
#
# A capped arm (gc.dispatch_when_ready_fail_count at its cap) is NOT flagged: the
# reconcile pass already escalates it, so it is not silent.
#
# The remedy the finding names is a look at `deferred-dispatch.sh list` (which
# marks each arm waiting / dispatchable / stranded) and, if the dispatch is no
# longer wanted, `deferred-dispatch.sh disarm`.
#
# Read-only. Exit 0=OK 1=Warning. stdout: first line = message, then
# "  - detail" lines. Warn-only. An UNREADABLE probe warns (1), never passes —
# an unread store is not a clean one.

set -u

# A dispatch owed longer than this has missed multiple reconcile passes. Mirrors
# check-cadence-live's I10 floor, max(3×interval, 15m): the deferred-dispatch
# order runs every 2m, so 900s is more than seven passes — long past any normal
# window between a blocker closing and the next reconcile slinging.
OWED_WINDOW_SECONDS=900

K_ARM="gc.dispatch_when_ready"
K_SLUNG="gc.dispatch_when_ready_slung"
K_ARMED_AT="gc.dispatch_when_ready_armed_at"

findings=(); warnings=(); notes=()
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

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)] | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether owed deferred dispatches are firing"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

now=$(now_epoch)
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    # A suspended rig's store is cold; querying it would auto-start an orphan
    # Dolt server, so it is skipped the way the sibling store checks skip it.
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    # Every armed bead in this store, all statuses (a stranded arm is non-open).
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --has-metadata-key "$K_ARM" --all --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
        warnings+=("$label: could not list armed beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$raw" | scrub | jq -r --arg slung "$K_SLUNG" --arg armed_at "$K_ARMED_AT" '
        .[]? | . as $b | ($b.metadata // {}) as $m
        | [ ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")),
            (($b.status // "") | tostring),
            (($b.assignee // "") | tostring | (. != "") | tostring),
            (($m[$slung] // "") | tostring | (. != "") | tostring),
            (($m["merge_result"] // "") | tostring | (. != "") | tostring),
            (($m[$armed_at] // "") | tostring) ]
        | @tsv' 2>/dev/null) || {
        warnings+=("$label: could not evaluate armed beads in $rig_path/.beads — this store was NOT checked")
        continue
    }
    [ -n "$rows" ] || continue

    while IFS=$'\t' read -r id status has_assignee has_slung has_mr armed_at; do
        [ -n "$id" ] || continue
        [ "$status" = "closed" ] && continue          # dispatch no longer owed
        [ "$has_mr" = "true" ] && continue            # delivered by another path; reconcile retires
        [ "$has_slung" = "true" ] && continue         # mid-dispatch or proven; reconcile handles it
        if [ "$status" != "open" ]; then
            findings+=("$label bead $id: armed for dispatch at status=$status, which \`bd list --ready\` never answers — no blocker closing can dispatch it. Clear the hold or disarm: deferred-dispatch.sh disarm $id")
            continue
        fi
        # reconcile HELDs an assigned bead (it will not sling over an assignee), so
        # it is not owed a dispatch — a handed-off or claimed bead with a stale arm,
        # a different concern from a stalled dispatch and not this check's finding.
        [ "$has_assignee" = "true" ] && continue
        # Open, unassigned, not mid-dispatch, not delivered: ask its OWN blockers —
        # this is the same question reconcile dispatches on, and the parent-child
        # is_blocked cascade means `bd ready`/`bd blocked` under this id would
        # answer about an ancestor, not the arm.
        deps=$(run_bounded gc bd dep list "$id" --db "$rig_path/.beads" --json 2>/dev/null)
        if ! printf '%s' "$deps" | jq -e 'type == "array"' >/dev/null 2>&1; then
            warnings+=("$label bead $id: could not read its dependency edges in $rig_path/.beads — NOT checked")
            continue
        fi
        open_blk=$(printf '%s' "$deps" | scrub | jq -r \
            '[ .[] | select(.dependency_type == "blocks") | select(.status != "closed") ] | length' 2>/dev/null)
        case "$open_blk" in ''|*[!0-9]*)
            warnings+=("$label bead $id: its dependency edges did not parse — NOT checked"); continue ;;
        esac
        [ "$open_blk" -eq 0 ] || continue             # still waiting on its own open blocker: correct
        # Dispatchable now. How long has it been owed? The latest own-blocker
        # close (ISO-8601 UTC sorts chronologically), else when it was armed.
        since=$(printf '%s' "$deps" | scrub | jq -r \
            '[ .[] | select(.dependency_type == "blocks") | .closed_at // empty ] | max // empty' 2>/dev/null)
        [ -n "$since" ] || since="$armed_at"
        since_epoch=$(iso_to_epoch "$since")
        # Cannot bound the age: skip rather than cry wolf — the next sweep sees a
        # readable timestamp, and a real stall persists to be caught then.
        [ -n "$since_epoch" ] || continue
        age=$(( now - since_epoch ))
        if [ "$age" -ge "$OWED_WINDOW_SECONDS" ]; then
            findings+=("$label bead $id: armed and its own \`blocks\` edges have all been closed for ${age}s (> ${OWED_WINDOW_SECONDS}s), but it has not dispatched. The deferred-dispatch reconcile order slings a ready arm within its 2m cadence, so a dispatch owed this long means that order is not firing (check-cadence-live/I10) or the dispatch is stuck. Look: deferred-dispatch.sh list; disarm if no longer wanted: deferred-dispatch.sh disarm $id")
        fi
    done <<< "$rows"
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every store was scanned — what follows is partial, and a store skipped for time is not a store that passed")
fi
if [ "${#findings[@]}" -ne 0 ] || [ "${#warnings[@]}" -ne 0 ]; then
    if [ "${#findings[@]}" -ne 0 ]; then
        echo "armed dispatches owed but not firing: ${#findings[@]} finding(s)"
        detail "${findings[@]}"
        detail ${warnings[@]+"${warnings[@]}"}
    else
        echo "armed-dispatch check ran partially"
        detail "${warnings[@]}"
    fi
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every armed deferred dispatch is waiting on its own blocker, mid-dispatch, or firing within cadence"
detail ${notes[@]+"${notes[@]}"}
exit 0
