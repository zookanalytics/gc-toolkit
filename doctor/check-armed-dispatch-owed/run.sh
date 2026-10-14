#!/usr/bin/env bash
# doctor/check-armed-dispatch-owed — an owed deferred dispatch is firing or
# surfaced. A bead armed with gc.dispatch_when_ready is slung by the
# deferred-dispatch reconcile order (orders/deferred-dispatch.toml, a 5m cooldown)
# once nothing holds it. `arm` refuses a non-open bead and reconcile retires a
# closed or already-delivered one, so a healthy arm is short-lived: it waits
# while something holds it, then dispatches within a cadence of being armed or
# of the last hold releasing, whichever is later.
#
# Two ways a dispatch stops firing SILENTLY, neither caught elsewhere:
#   * OWED-BUT-NOT-FIRING — the bead is open, nothing holds it, and it is not
#     mid-dispatch, yet it has stayed armed well past the reconcile cadence.
#     Either the order is not running (check-cadence-live/I10 is the direct cause
#     there, but a single owed arm makes the effect concrete) or the dispatch is
#     stuck. A hold is the one reconcile slings on, assets/scripts/hold-lib.sh's:
#     an open `blocks` blocker on the bead or on a parent-child ancestor, a
#     demand gate on an ancestor aside. So an arm a park holds, by an edge of its
#     own or its epic's, is not owed: a park leaves the arm intact and its status
#     open, and the arm fires when the park releases. A bead in flight (a branch,
#     a merge_result or a rejection_reason) is held by its own blockers alone, so
#     its arm is owed under a parked epic, where reconcile slings it.
#     check-blocked-work-armed asks blocked work for a dispatch path and nothing
#     more, and an arm is one, so an arm that never fires is this check's to see.
#     `bd blocked` lists a bead its parent's hold reaches under the bead's own
#     id, naming the parent as its blocker, and that check skips it for the arm
#     alone.
#   * STRANDED — the bead is armed at a non-open status, which `bd list --ready`
#     never answers, so no blocker closing will ever dispatch it (a bead armed
#     while open, then set to another status). reconcile prints this to its own
#     log every pass, but nothing surfaces it to a person. A hold does not excuse
#     it: releasing the hold would not dispatch it either.
#
# A capped arm (gc.dispatch_when_ready_fail_count at its cap) is NOT flagged: the
# reconcile pass already escalates it, so it is not silent.
#
# The remedy the finding names is a look at `deferred-dispatch.sh list` (which
# marks each arm held / dispatchable / stranded) and, if the dispatch is no
# longer wanted, `deferred-dispatch.sh disarm`.
#
# Read-only. Exit 0=OK 1=Warning. stdout: first line = message, then
# "  - detail" lines. Warn-only. An UNREADABLE probe warns (1), never passes —
# an unread store is not a clean one.

set -u

# The owed window is the deferred-dispatch order's cadence window, from the one
# definition check-cadence-live (I10) also reads: max(3×interval, one trip of
# the order dispatch rotation). It is computed below, once the probes have their
# budget. Unsourceable, no arm's wait can be judged, so the check warns.
# shellcheck source=../../assets/scripts/order-cadence.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/order-cadence.sh" || {
    echo "cannot determine whether owed deferred dispatches are firing"
    printf '  - %s\n' "assets/scripts/order-cadence.sh could not be sourced from this pack, so the window an owed arm is judged by cannot be computed."
    exit 1
}
# The one definition of a hold, which reconcile also reads. Unsourceable, a held
# arm cannot be told from an owed one, so the check warns.
# shellcheck source=../../assets/scripts/hold-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/hold-lib.sh" || {
    echo "cannot determine whether owed deferred dispatches are firing"
    printf '  - %s\n' "assets/scripts/hold-lib.sh could not be sourced from this pack, so a held arm cannot be told from an owed one."
    exit 1
}

K_ARM="gc.dispatch_when_ready"
K_SLUNG="gc.dispatch_when_ready_slung"
K_ARMED_AT="gc.dispatch_when_ready_armed_at"
K_FAILS="gc.dispatch_when_ready_fail_count"

# The retry cap, read exactly as deferred-dispatch.sh reads it (same env
# override, same non-numeric fallback): once an arm's sling failures reach it,
# the reconcile pass files a visit through escalate.sh and stops re-slinging, so
# a capped arm is already surfaced to a person — not a silent stall to re-report.
MAX_SLING_FAILURES="${GC_MAX_DISPATCH_SLING_FAILURES:-3}"
case "$MAX_SLING_FAILURES" in ''|*[!0-9]*) MAX_SLING_FAILURES=3 ;; esac

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

# A ready arm is slung on the deferred-dispatch order's next pass, so an arm
# that has waited longer than that order's cadence window has waited through a
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

# The hold walk's seed and graph, rewritten for each store.
hold_dir=$(mktemp -d "${TMPDIR:-/tmp}/gctk-armed-dispatch-hold.XXXXXX" 2>/dev/null) \
    || { hold_dir="${TMPDIR:-/tmp}/gctk-armed-dispatch-hold.$$"; mkdir -p "$hold_dir"; }
trap 'rm -rf "$hold_dir"' EXIT
# The hold walk's reader (hold-lib.sh): the named beads in the store being
# scanned, at every status and of every class a listing hides by default, since
# a blocker can be a gate and an ancestor can be closed.
hold_db=""
hold_read() { run_bounded gc bd list --db "$hold_db" --id "$1" --all --include-gates --include-infra --include-templates --brief --json --limit 0 2>/dev/null; }

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)] | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether owed deferred dispatches are firing"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

now=$(now_epoch)
declare -A armed_at_of=()
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
    # Classify every armed bead from this one listing. A stranded arm (armed at a
    # non-open status) is a finding on its own; the exemptions — closed, delivered
    # (merge_result), mid-dispatch (a slung marker), capped (the reconcile pass has
    # already escalated it), assigned (reconcile will not sling over a holder) —
    # need no further read. deferred-dispatch.sh's `list` classifies CAPPED ahead
    # of stranded and dispatchable, so the cap test precedes the status test here
    # too. Only an open, unassigned, live arm is a CANDIDATE whose blockers, on
    # it and on its ancestors, decide whether a dispatch is owed.
    classified=$(printf '%s' "$raw" | scrub | jq -r \
        --arg slung "$K_SLUNG" --arg armed_at "$K_ARMED_AT" --arg fails "$K_FAILS" \
        --argjson cap "$MAX_SLING_FAILURES" '
        .[]? | . as $b | ($b.metadata // {}) as $m
        | ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $id
        | (($b.status // "") | tostring) as $st
        | (($b.assignee // "") | tostring | . != "") as $assigned
        | (($m[$slung] // "") | tostring | . != "") as $slung_set
        | (($m["merge_result"] // "") | tostring | . != "") as $mr_set
        | (($m[$armed_at] // "") | tostring) as $armed_when
        | (($m[$fails] // "") | tostring) as $fails_raw
        | (if ($fails_raw | test("^[0-9]+$")) then ($fails_raw | tonumber) else 0 end) as $fails_n
        | if   $st == "closed"  then empty
          elif $mr_set          then empty
          elif $slung_set       then empty
          elif $fails_n >= $cap then empty
          elif $st != "open"    then "stranded\t\($id)\t\($st)"
          elif $assigned        then empty
          else                       "candidate\t\($id)\t\($armed_when)"
          end' 2>/dev/null) || {
        warnings+=("$label: could not evaluate armed beads in $rig_path/.beads — this store was NOT checked")
        continue
    }
    [ -n "$classified" ] || continue

    # A stranded arm is a finding now; a candidate is collected for the hold walk
    # below, keeping its armed_at, the earliest its dispatch can be owed.
    cand_ids=(); armed_at_of=()
    while IFS=$'\t' read -r kind cid f3; do
        [ -n "$cid" ] || continue
        case "$kind" in
            stranded)   # f3 is the stranding status
                findings+=("$label bead $cid: armed for dispatch at status=$f3, which \`bd list --ready\` never answers — no blocker closing can dispatch it. Return it to open, or disarm: deferred-dispatch.sh disarm $cid") ;;
            candidate)  # f3 is armed_at
                cand_ids+=("$cid"); armed_at_of["$cid"]="$f3" ;;
        esac
    done <<< "$classified"
    [ "${#cand_ids[@]}" -gt 0 ] || continue

    # A candidate is owed only when nothing holds it, by the predicate reconcile
    # slings on, and that predicate answers for the candidate's own blockers as
    # well as its ancestors'. The walk takes each candidate's own edges from its
    # row in this listing, then reads the ancestors a generation at a time and
    # every blocker once, so the store costs those few reads however many
    # candidates it holds. A candidate held by a blocker the walk read is not
    # owed. One whose only holds could not be read is NOT checked: an unread hold
    # is no released one, and no owed dispatch either.
    hold_db="$rig_path/.beads"
    cand_json=$(printf '%s\n' "${cand_ids[@]}" | jq -R . | jq -sc .)
    # The rows join on the unit separator, not a tab: `read` folds a run of tabs
    # into one, so an empty release time would hand the unread ids its field.
    hold_rows=""
    if printf '%s' "$raw" | scrub | jq -c --argjson c "$cand_json" '[ .[]? | select(.id as $i | $c | index($i)) ]' > "$hold_dir/seed.json" 2>/dev/null \
       && hold_graph hold_read "$hold_dir/seed.json" "$hold_dir/graph.json"; then
        hold_rows=$(jq -r --slurpfile g "$hold_dir/graph.json" "$HOLD_JQ"'
            .[] | hold_holds($g[0]) as $h
            | [ (.id | tostring),
                (if any($h[]; .unread | not) then "held" elif ($h | length) > 0 then "unread" else "free" end),
                (hold_released_at($g[0]) // ""),
                ([ $h[] | select(.unread) | .by ] | join(" ")) ]
            | map(gsub("[[:cntrl:]]"; " ")) | join("\u001f")' "$hold_dir/seed.json" 2>/dev/null)
    fi
    if [ -z "$hold_rows" ]; then
        warnings+=("$label: could not read what holds ${#cand_ids[@]} armed bead(s) in $rig_path/.beads — they were NOT checked")
        continue
    fi

    while IFS=$'\037' read -r cid hold released unread_ids; do
        [ -n "$cid" ] || continue
        case "$hold" in
            held) continue ;;                         # a park or a prerequisite holds it: not owed
            unread) warnings+=("$label bead $cid: could not read [$unread_ids], which may hold it, in $rig_path/.beads — NOT checked"); continue ;;
        esac
        # Owed since the later of when it was armed and when the last hold on it
        # released (hold_released_at), so a hold that released before the arm
        # was recorded does not age it. An arm whose armed_at does not parse is
        # judged from the release alone.
        since_epoch=$(iso_to_epoch "${armed_at_of[$cid]}")
        released_epoch=$(iso_to_epoch "$released")
        if [ -n "$released_epoch" ] && { [ -z "$since_epoch" ] || [ "$released_epoch" -gt "$since_epoch" ]; }; then
            since_epoch="$released_epoch"
        fi
        # Cannot bound the age: skip rather than cry wolf — the next sweep sees a
        # readable timestamp, and a real stall persists to be caught then.
        [ -n "$since_epoch" ] || continue
        age=$(( now - since_epoch ))
        if [ "$age" -ge "$OWED_WINDOW_SECONDS" ]; then
            findings+=("$label bead $cid: armed and nothing has held it for ${age}s (> ${OWED_WINDOW_SECONDS}s), but it has not dispatched. The deferred-dispatch reconcile order slings an arm nothing holds on its next pass, and ${OWED_WINDOW_SECONDS}s is that order's cadence window, so a dispatch owed this long means that order is not firing (check-cadence-live/I10) or the dispatch is stuck. Look: deferred-dispatch.sh list; disarm if no longer wanted: deferred-dispatch.sh disarm $cid")
        fi
    done <<< "$hold_rows"
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
echo "OK: every armed deferred dispatch is held by a blocker, mid-dispatch, or firing within cadence"
detail ${notes[@]+"${notes[@]}"}
exit 0
