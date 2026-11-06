#!/usr/bin/env bash
# doctor/check-blocked-work-armed — blocked work carries a dispatch path. A
# LIVE, unassigned bead that is plainly work (not a review, step or workflow-
# topology bead, not a standing record, and not a merge anchor) and
# is held out of `bd ready` by an open `blocks` edge must ALSO carry a way to be
# dispatched once that edge clears: either `gc.routed_to` (a pool queue
# consumes it, and bd's readiness gates the offer until the blocker closes) or
# `gc.dispatch_when_ready` (armed, so the deferred-dispatch reconcile order
# slings it the moment bd reports it ready). Both keys come from the one
# definition of a dispatch path, assets/scripts/dispatch-path.sh, which this
# check sources. A blocked work bead with NEITHER is the "unrouted-and-remember"
# anti-pattern: when its blocker closes it becomes ready and no queue is offered
# it, so it waits on a person to notice and route it by hand.
#
# `gc.execution_routed_to` is NOT a dispatch path: it is execution provenance
# for workflow/control-dispatch flows, not a queue a worker or the pool-demand
# reconciler consumes (those read `gc.routed_to`; gascity's route-recovery lane
# restores `gc.routed_to` from the carried route only once a live workflow no
# longer drives the bead). But it is ALSO the shape of a work bead under a LIVE
# graph.v2 pour — open, unassigned, `gc.routed_to` retired by the pour, the exec
# stamp set — so flagging on a missing route alone would flag in-flight work, and
# the arm remedy would double-dispatch it. Liveness is consulted before a
# candidate is flagged: a bead a live run works (assets/scripts/run-lib.sh's map,
# which assets/scripts/liveness-sweep.sh reads too) is in-flight and exempt; only
# a bead no live run works is the stranded shape this reports. When a candidate
# carries the exec stamp and liveness cannot be confirmed, it is reported as
# unverifiable and never flagged, so an unreadable run is never turned into a
# double-dispatch.
#
# The other workflow-driven state that legitimately rests unrouted-and-unassigned
# is the merge anchor: a bead carrying a `merge_result` is driven by the merge
# cadence and offered by no pool queue (lifecycle/lifecycle.toml — the anchor
# state is status x merge_result), so it is exempt on that marker.
#
# A standing record (a task_kind assets/scripts/standing-kinds.sh lists) rests
# unrouted and unassigned by design too: nothing ever dispatches it, so a wait
# it sits behind owes it no dispatch path, and arming one would sling a
# held-by-design record to a pool the moment its blocker closed. It is exempt on
# its task_kind, read from that shared definition.
#
# So is a held bead (has_dispatch_hold, assets/scripts/dispatch-path.sh): it
# carries one of Gas City's hold labels, which say its next actor is not a
# worker. Intake holds new work for the operator's placement sitting with
# hold:mayor (docs/steering.md), and its dispatch is the route it gets once the
# sitting places it and the hold is lifted. Arming it would start work the
# operator has not placed, and the deferred-dispatch pass slings no held bead
# anyway. `bd blocked` prints a bead's labels, so the hold is read on the row the
# listing already gives.
#
# The remedy the finding names is arming — deferred-dispatch.sh arm, which is a
# safe universal substitute for a hand-held sling (docs/deferred-dispatch.md).
# The complement check is doctor/check-wait-is-an-edge (I1): that one asserts
# the wait IS an edge rather than prose; this one asserts an edged wait has
# somewhere to go. A bead can pass one and fail the other.
#
# Read-only. Exit 0=OK 1=Warning. stdout: first line = message, then
# "  - detail" lines. Warn-only: a standing backlog of unarmed blocked work
# exists, so this reports and never fails the sweep. An UNREADABLE probe warns
# (1), never passes — an unread store is not a clean one.

set -u

# The issue types a pool claims and works, so blocked, unrouted and unarmed is
# this anti-pattern only for these. Gas City's pool serves the beads routed or
# assigned to it, and leaves out epic even then. This check reads beads nobody
# routed, and its remedy arms one to be slung, so it names what IS work and
# leaves every other type alone:
#   - epic: Gas City's routed pool-demand query passes --exclude-type=epic
#     (PoolDemandServeRulesForQuery), and gc sling refuses an epic. Its
#     children are the routed work.
#   - milestone: bd describes it as marking the completion of related issues,
#     with no work of its own.
#   - decision: a person settles it. bd defines it as an architecture decision
#     record, and the pack's own agents file one as a question for a person,
#     so arming one would sling a person's question to a polecat.
#   - the bookkeeping types `bd ready` or Gas City's Ready() leaves out (gate,
#     molecule, merge-request, convoy, step, session, message, ...), and the
#     records Gas City and bd keep that neither leaves out (spec, convergence,
#     event).
#   - a type this list has never heard of, such as one a rig adds. A list of
#     the types that are not work would admit every type it forgot.
# doctor.toml names the same set.
WORK_TYPES=" bug feature task chore spike story "

# The standing kinds, from the one definition shared with the liveness sweep and
# the proactive scan. Exposes $STANDING_KINDS_JQ. An unsourceable one warns:
# without it a standing record would read as stranded work and draw the arm
# remedy.
# shellcheck source=../../assets/scripts/standing-kinds.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/standing-kinds.sh" || {
    echo "cannot determine whether blocked work carries a dispatch path"
    printf '  - %s\n' "assets/scripts/standing-kinds.sh could not be sourced from this pack, so a standing record cannot be told from stranded work."
    exit 1
}
# What counts as a dispatch path and a dispatch hold, from the one definition
# shared with the proactive scan, check-step-terminal and deferred-dispatch.sh.
# Exposes $DISPATCH_PATH_JQ. An unsourceable one warns: without it no bead can be
# told to have a dispatch path or a hold.
# shellcheck source=../../assets/scripts/dispatch-path.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/dispatch-path.sh" || {
    echo "cannot determine whether blocked work carries a dispatch path"
    printf '  - %s\n' "assets/scripts/dispatch-path.sh could not be sourced from this pack, so a routed or armed bead cannot be told from stranded work."
    exit 1
}
# The one reader of a run's link to the bead it works. An unsourceable one
# warns: without it a bead a live run works would read as stranded work and draw
# the arm remedy.
# shellcheck source=../../assets/scripts/run-lib.sh
. "${GC_RUN_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/run-lib.sh}" || {
    echo "cannot determine whether blocked work carries a dispatch path"
    printf '  - %s\n' "assets/scripts/run-lib.sh could not be sourced from this pack, so a bead a live run works cannot be told from stranded work."
    exit 1
}

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
# The reader run-lib.sh reads the store of the rig being scanned through.
rig_bd() { run_bounded gc bd "$@" --db "$rig_path/.beads"; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# rig-map.sh prints the map when the listing reads and only its reason when it
# does not, so one capture holds whichever came back.
RIG_MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/rig-map.sh"
rigs_raw=$(run_bounded "$RIG_MAP" 2>&1); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)] | join("")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether blocked work carries a dispatch path"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    [ "$rigs_rc" -eq 0 ] || [ -z "$rigs_raw" ] || detail "$rigs_raw"
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    # A suspended rig's store is cold; `gc bd blocked --db` on it would auto-start
    # an orphan Dolt server just to answer, so it is skipped the way the sibling
    # store checks skip it (doctor/check-state-space).
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    # `bd blocked` returns exactly the beads held out of ready by an open
    # blocker, so the edge is a fact of the listing and needs no re-derivation.
    # Every listing here is scrubbed before jq first reads it, its type check
    # included: one raw control byte in a title would otherwise fail the whole
    # listing, and the store or the candidates it vouches for would go unjudged.
    raw=$(run_bounded gc bd blocked --db "$rig_path/.beads" --json 2>/dev/null); rc=$?
    raw=$(printf '%s' "$raw" | scrub)
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        # An empty array is a real answer (no blocked beads); a non-zero probe
        # or empty payload is not, and must not read as a clean store.
        if [ "$rc" -eq 0 ] && printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
            :
        else
            warnings+=("$label: could not list blocked beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
            continue
        fi
    fi
    printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || {
        warnings+=("$label: \`gc bd blocked --json\` for $rig_path/.beads did not answer a JSON array — this store was NOT checked")
        continue
    }
    # The predicate, entirely on the listing's own fields: plainly work
    # (unassigned; not review/standing/step/workflow-topology; not a merge
    # anchor; an allowlisted work issue_type, which a gate is not), carrying no
    # dispatch path (has_dispatch_path: no route and no arm), AND not held
    # (has_dispatch_hold: no hold label).
    cand=$(printf '%s' "$raw" | jq -r --arg allow "$WORK_TYPES" "$STANDING_KINDS_JQ$DISPATCH_PATH_JQ"'
        .[]? | . as $b
        | ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $id
        | ($b.metadata // {}) as $m
        | select(($b.assignee // "") == "")
        | select(($m["task_kind"] // "") != "review")
        | select(($b | is_standing_kind) | not)
        | select(($m["gc.step_ref"] // "") == "")
        | select(($m["gc.kind"] // "") == "")
        | select(($m["merge_result"] // "") == "")
        | select($allow | contains(" " + (($b.issue_type // "") | tostring) + " "))
        | select(($b | has_dispatch_path) | not)
        | select(($b | has_dispatch_hold) | not)
        | [ $id,
            (($b.issue_type // "?") | tostring | gsub("[[:cntrl:]]"; " ")),
            (if (($m["gc.execution_routed_to"] // "") != "") then "1" else "0" end),
            (($b.title // "") | tostring | gsub("[[:cntrl:]]"; " ") | .[0:70]) ]
        | @tsv' 2>/dev/null) || {
        warnings+=("$label: could not evaluate blocked beads in $rig_path/.beads — this store was NOT checked")
        continue
    }
    [ -n "$cand" ] || continue

    # Candidates exist, so resolve which of them a LIVE run already works. A
    # slung work bead carries no worker stamp of its own; coverage is a live run
    # that works the bead (run-lib.sh's map), the resolution liveness-sweep.sh
    # uses. Computed only when there is something to filter, and left unconfirmed
    # ($liveness_ok=0) when the runs cannot be read, so a candidate carrying the
    # exec stamp is warned rather than flagged when coverage cannot be confirmed.
    worked=" "; liveness_ok=1
    if runs=$(run_lib map rig_bd); then
        while IFS= read -r m; do [ -n "$m" ] && worked="$worked$m "; done \
            <<< "$(printf '%s' "$runs" | jq -r '.[] | .bead | select(. != "")' 2>/dev/null)"
    else
        liveness_ok=0           # the runs could not be read: cannot confirm any coverage
    fi

    while IFS=$'\t' read -r id btype has_exec title; do
        [ -n "$id" ] || continue
        case "$worked" in *" $id "*) continue ;; esac   # a live run works it
        if [ "$has_exec" = "1" ] && [ "$liveness_ok" != "1" ]; then
            warnings+=("$label bead $id [$btype]: blocked and carries gc.execution_routed_to, but whether a live run works it could not be confirmed in $rig_path/.beads — NOT flagged, because arming a bead a live workflow still drives would double-dispatch it. Verify by hand whether a live run works it; if not, arm it ($title)")
            continue
        fi
        findings+=("$label bead $id [$btype]: blocked with no gc.routed_to and no gc.dispatch_when_ready — when its blocker closes it becomes ready and no pool is offered it. Arm it so it auto-resumes: deferred-dispatch.sh arm $id --target <rig>/<agent> --reason \"waits for <blocker>\" ($title)")
    done <<< "$cand"
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every store was scanned — what follows is partial, and a store skipped for time is not a store that passed")
fi
if [ "${#findings[@]}" -ne 0 ] || [ "${#warnings[@]}" -ne 0 ]; then
    if [ "${#findings[@]}" -ne 0 ]; then
        echo "blocked work with no dispatch path — it will strand when its blocker closes: ${#findings[@]} finding(s)"
        detail "${findings[@]}"
        detail ${warnings[@]+"${warnings[@]}"}
    else
        echo "blocked-work dispatch-path check ran partially"
        detail "${warnings[@]}"
    fi
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every blocked plainly-work bead carries a route or is armed for deferred dispatch"
detail ${notes[@]+"${notes[@]}"}
exit 0
