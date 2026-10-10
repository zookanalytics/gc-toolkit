#!/usr/bin/env bash
# doctor/check-refinery-patrol-live — I14: a refinery whose queue holds work is
# cycling its patrol. The refinery agent runs mol-refinery-patrol as a loop of
# root-only wisps, one per iteration: find-work takes one bead from the
# refinery's queue, and the iteration pours its successor before it burns
# itself, so a refinery working through a queue renews its wisp once per bead.
# With the queue empty the session ends its turn and the wisp rests, so an old
# wisp alone is an idle refinery, not a stalled one. This is the agent half of
# the refinery; the refinery-reconcile order is the cadence half, and
# check-cadence-live asserts that one.
#
# Per refinery, STALLED (error) when both hold:
#   - its queue has held a bead past the bound (default 60m,
#     GC_DOCTOR_REFINERY_PATROL_STALL_MINUTES). The queue is the set find-work
#     selects from: open, assigned to the refinery, carrying metadata.branch,
#     not an epic, and with no merge_result, since a bead that carries one is a
#     gating anchor the cadence drives. A wait is aged by the bead's
#     updated_at, which any later write resets, so the age read is never longer
#     than the real wait;
#   - no mol-refinery-patrol wisp assigned to it was written within that
#     bound, or none exists. Every pour stamps a wisp's updated_at, so the
#     newest one dates the patrol's last movement.
# A queue whose oldest bead is younger than the bound is a note: a refinery
# idle past the bound has not yet had the bound to take work that just arrived.
#
# Refineries are the agents `gc status --json` lists whose qualified name ends
# in `.refinery`, each read from its own rig's store by --db. A suspended
# refinery or rig is a note, because querying a suspended rig's store would
# auto-start an orphan Dolt server.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

STALL_MINUTES="${GC_DOCTOR_REFINERY_PATROL_STALL_MINUTES:-60}"
case "$STALL_MINUTES" in *[!0-9]*|"") STALL_MINUTES=60 ;; esac
STALL=$((STALL_MINUTES * 60))
PATROL_TITLE="mol-refinery-patrol"
SEP=$'\037'

errors=(); warnings=(); notes=()
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
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

# A bead stamp as epoch seconds, or null when it does not parse.
EP='def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);'

city="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
status_json=$(run_bounded gc ${city:+--city "$city"} status --json 2>/dev/null)
if ! printf '%s' "$status_json" | scrub \
        | jq -e '(.agents | type) == "array" and (.rigs | type) == "array"' >/dev/null 2>&1; then
    echo "refinery patrol liveness undetermined (I14) — cannot read the city roster"
    detail "\`gc status --json\` returned no .agents and .rigs arrays (no answer inside the probe's slice of the budget, or schema drift); no refinery was checked, so a stalled patrol would not be visible."
    exit 1
fi

# qn, rig, rig path, refinery suspended, rig suspended, running ("unknown"
# when the roster does not say).
refineries=$(printf '%s' "$status_json" | scrub | jq -r '
    (reduce (.rigs[]? | select(type == "object")) as $r ({};
        . + {(($r.name // "") | tostring): $r})) as $rigs
    | .agents[]? | select(type == "object")
    | ((.qualified_name // "") | tostring) as $qn
    | select($qn | test("^[^/]+/"))
    | select(($qn | split("/") | last | split(".") | last) == "refinery")
    | ($qn | split("/") | first) as $rig
    | [$qn, $rig, (($rigs[$rig].path // "") | tostring),
       ((.suspended // false) | tostring),
       (($rigs[$rig].suspended // false) | tostring),
       (if has("running") then (.running | tostring) else "unknown" end)]
    | join("\u001f")' 2>/dev/null)
agent_count=$(printf '%s' "$status_json" | scrub | jq -r '.agents | length' 2>/dev/null)

if [ -z "$refineries" ]; then
    if [ "${agent_count:-0}" -gt 0 ] 2>/dev/null; then
        echo "refinery patrol liveness undetermined (I14) — no refinery in the roster"
        detail "none of the ${agent_count} agent(s) in \`gc status --json\` has a qualified name ending in .refinery; either this city runs no refinery or the roster's naming moved, and no patrol was read."
        exit 1
    fi
    echo "OK: the roster lists no agents, so there is no refinery patrol to check"
    exit 0
fi

while IFS="$SEP" read -r qn rig rig_path agent_suspended rig_suspended running; do
    [ -n "$qn" ] || continue
    if [ "$agent_suspended" = "true" ]; then
        notes+=("$qn: suspended, so its patrol is not expected to cycle")
        continue
    fi
    if [ "$rig_suspended" = "true" ]; then
        notes+=("$qn: skipped (rig $rig is suspended; querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    if [ -z "$rig_path" ]; then
        warnings+=("$qn: the roster gives no path for rig $rig, so its store was NOT checked")
        continue
    fi
    db="$rig_path/.beads"

    # The queue find-work selects from, filtered the same way.
    queue_raw=$(run_bounded gc bd list --db "$db" --assignee "$qn" --status open \
        --exclude-type epic --has-metadata-key branch --json --limit 0 2>/dev/null); rc=$?
    queue=$(printf '%s' "$queue_raw" | scrub | jq -r "$EP"'
        if type != "array" then error("not a list") else . end
        | [.[] | select(type == "object")
            | select(((.metadata.merge_result // "") | tostring) == "")
            | {id: ((.id // "?") | tostring), e: ((.updated_at // "") | ep)}] as $q
        | ([$q[] | select(.e != null)] | min_by(.e)) as $o
        | [($q | length), ($o.id // ""),
           (if $o == null then "" else ((now - $o.e) | floor) end)]
        | map(tostring) | join("\u001f")' 2>/dev/null)
    if [ "$rc" -ne 0 ] || [ -z "$queue" ]; then
        warnings+=("$qn: could not list its find-work queue in $db (rc=$rc), so this refinery was NOT checked")
        continue
    fi
    IFS="$SEP" read -r depth oldest_id oldest_age <<< "$queue"
    if [ "$depth" -eq 0 ]; then
        notes+=("$qn: find-work queue empty, so a resting patrol is idle")
        continue
    fi
    if [ -z "$oldest_age" ]; then
        warnings+=("$qn: $depth bead(s) in its find-work queue and none carries a readable updated_at, so the wait could not be aged")
        continue
    fi
    waited="$depth bead(s) wait in its find-work queue, the oldest ($oldest_id) for $((oldest_age / 60))m"
    if [ "$oldest_age" -lt "$STALL" ]; then
        notes+=("$qn: $waited, inside the ${STALL_MINUTES}m bound")
        continue
    fi

    wisp_raw=$(run_bounded gc bd list --db "$db" --assignee "$qn" --status open,in_progress \
        --type molecule --include-infra --json --limit 0 2>/dev/null); rc=$?
    wisp=$(printf '%s' "$wisp_raw" | scrub | jq -r --arg t "$PATROL_TITLE" "$EP"'
        if type != "array" then error("not a list") else . end
        | [.[] | select(type == "object") | select((.title // "") == $t)
            | {id: ((.id // "?") | tostring), s: ((.status // "?") | tostring),
               e: ((.updated_at // "") | ep)}] as $w
        | ([$w[] | select(.e != null)] | max_by(.e)) as $n
        | [($w | length), ($n.id // ""), ($n.s // ""),
           (if $n == null then "" else ((now - $n.e) | floor) end)]
        | map(tostring) | join("\u001f")' 2>/dev/null)
    if [ "$rc" -ne 0 ] || [ -z "$wisp" ]; then
        warnings+=("$qn: $waited, and its patrol wisps in $db could not be listed (rc=$rc), so its patrol was NOT checked")
        continue
    fi
    IFS="$SEP" read -r wisp_count wisp_id wisp_status wisp_age <<< "$wisp"

    case "$running" in
        true)  session=" gc status reports its session running; \`gc session peek $qn\` shows what it is doing instead of cycling." ;;
        false) session=" gc status reports no running session for it." ;;
        *)     session="" ;;
    esac
    stake="Nothing in that queue moves until the patrol cycles: no handoff is gated or landed, and no handed-back rework closes."
    if [ "$wisp_count" -eq 0 ]; then
        errors+=("$qn: STALLED. $waited, and no $PATROL_TITLE wisp is assigned to it, so its loop has dropped. $stake$session")
    elif [ -z "$wisp_age" ]; then
        warnings+=("$qn: $waited, and none of its $wisp_count patrol wisp(s) carries a readable updated_at, so whether the patrol moved is undetermined")
    elif [ "$wisp_age" -ge "$STALL" ]; then
        errors+=("$qn: STALLED. $waited, and its patrol wisp $wisp_id ($wisp_status) last moved $((wisp_age / 60))m ago, past the ${STALL_MINUTES}m bound. $stake$session")
    else
        notes+=("$qn: $waited; patrol wisp $wisp_id moved $((wisp_age / 60))m ago, so the patrol is cycling")
    fi
done <<< "$refineries"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi

if [ "${#errors[@]}" -ne 0 ]; then
    echo "refinery patrol not cycling (I14): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "refinery patrol liveness partially determined (I14)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every refinery whose find-work queue has held a bead past ${STALL_MINUTES}m has moved its patrol wisp within that bound"
detail ${notes[@]+"${notes[@]}"}
exit 0
