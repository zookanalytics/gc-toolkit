#!/usr/bin/env bash
# doctor/check-blocked-work-armed — blocked work carries a dispatch path. A
# LIVE, unassigned bead that is plainly work (not a review, step, workflow-
# topology, or demand bead, and not a merge anchor) and is held out of
# `bd ready` by an open `blocks` edge must ALSO carry a way to be dispatched
# once that edge clears: either `gc.routed_to` (a pool queue consumes it, and
# bd's readiness gates the offer until the blocker closes) or
# `gc.dispatch_when_ready` (armed, so the deferred-dispatch reconcile order
# slings it the moment bd reports it ready). A blocked work bead with NEITHER
# is the "unrouted-and-remember" anti-pattern: when its blocker closes it
# becomes ready and no queue is offered it, so it waits on a person to notice
# and route it by hand.
#
# `gc.execution_routed_to` is NOT a dispatch path: it is execution provenance
# for workflow/control-dispatch flows, not a queue a worker or the pool-demand
# reconciler consumes (those read `gc.routed_to`; gascity's route-recovery lane
# restores `gc.routed_to` from the carried route only once a live workflow no
# longer drives the bead). A blocked bead carrying only it, with no real route
# and no arm, is flagged. The workflow-driven state that legitimately rests
# unrouted and unassigned is the merge anchor: a bead carrying a `merge_result`
# is driven by the merge cadence and offered by no pool queue
# (lifecycle/lifecycle.toml — the anchor state is status x merge_result), so it
# is exempt on that marker.
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

# The issue types a pool claims and works — so blocked-and-unrouted-and-unarmed
# is this anti-pattern only for these. An allowlist, not the complement of an
# exclude set: `bd` accepts many types this check must never flag as pool work,
# and enumerating them to exclude is a list that silently admits every type it
# forgets. `bd ready`'s own infra/topology exclusions (merge-request, gate,
# molecule, rig, agent, role, message, session, convoy, issue-type step, spec,
# event, convergence, ...), `decision` (a person answers it, not a pool — arming
# it would sling a human's question at a polecat), the container types (`epic`,
# `milestone`, `story`, whose leaf children are the routed work), and any custom
# type a rig adds are all not-pool-work by naming what IS. A type this check has
# never heard of is left alone rather than mistaken for work. doctor.toml names
# the same set.
WORK_TYPES=" bug feature task chore spike "

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
budget_init
# <<< doctor-budget
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path] | join("")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether blocked work carries a dispatch path"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    # `bd blocked` returns exactly the beads held out of ready by an open
    # blocker, so the edge is a fact of the listing and needs no re-derivation.
    raw=$(run_bounded gc bd blocked --db "$rig_path/.beads" --json 2>/dev/null); rc=$?
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
    # (unassigned; not review/step/workflow-topology/demand; not a merge anchor;
    # an allowlisted work issue_type), AND carrying no route, AND not armed.
    cand=$(printf '%s' "$raw" | scrub | jq -r --arg allow "$WORK_TYPES" '
        .[]? | . as $b
        | ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $id
        | ($b.metadata // {}) as $m
        | select(($b.assignee // "") == "")
        | select(($m["task_kind"] // "") != "review")
        | select(($m["gc.step_ref"] // "") == "")
        | select(($m["gc.kind"] // "") == "")
        | select(($m["gc.demand_for"] // "") == "")
        | select(($m["merge_result"] // "") == "")
        | select($allow | contains(" " + (($b.issue_type // "") | tostring) + " "))
        | select(($m["gc.routed_to"] // "") == "")
        | select(($m["gc.dispatch_when_ready"] // "") == "")
        | [ $id,
            (($b.issue_type // "?") | tostring | gsub("[[:cntrl:]]"; " ")),
            (($b.title // "") | tostring | gsub("[[:cntrl:]]"; " ") | .[0:70]) ]
        | @tsv' 2>/dev/null) || {
        warnings+=("$label: could not evaluate blocked beads in $rig_path/.beads — this store was NOT checked")
        continue
    }
    [ -n "$cand" ] || continue
    while IFS=$'\t' read -r id btype title; do
        [ -n "$id" ] || continue
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
