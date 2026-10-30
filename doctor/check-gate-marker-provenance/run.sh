#!/usr/bin/env bash
# doctor/check-gate-marker-provenance — I7 (depth): a lane a merge path trusts as
# green stands on a verdict its writers actually produced.
#
# lane-state.sh, the derivation merge.sh, pr-open.sh and gate-ensure.sh read,
# stands a lane green on a CLOSED task_kind=review bead whose signoff_verdict is
# approve, whose reviewed_oid is non-empty, and whose gc.outcome is not
# superseded. It trusts those stamps; nothing else sweeps the store to prove them
# coherent. So per store, for every OPEN gating anchor (merge_result =
# pre_open_gate|pull_request), every closed approve review bead naming it
# (anchor_bead) that carries a reviewed_oid must record gc.outcome=recorded (a
# live backing) or superseded (retired). An approve carrying any other outcome —
# none at all, or a value no writer produces — STILL derives the lane green
# (lane-state.sh excludes only superseded) while standing on a verdict no writer
# recorded: that is the finding. signoff.sh (close_review) and review-outcome.sh
# (back-lane) co-stamp recorded with the approve; a supersede rewrites it to
# superseded; no writer pairs approve with a third value. The reviewed_oid clause
# matches lane-state.sh — a backing with no reviewed_oid derives no green there,
# so it is not a candidate here; the oid is required present, never compared to
# a head. A close with no signoff_verdict names no verdict — recorded is stamped
# on every close — so it backs no lane, and this audit, keyed on
# signoff_verdict, never fetches it. An operator's GitHub approval backs a lane
# without a bead, so it has no stamps here to audit.
#
# A bead whose own task_kind is review is not an anchor and is skipped. The
# check_set declaration is check-gate-integrity's half and is not restated here.
#
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE store warns (1), never passes.

set -u


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
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# The outcome-coherence audit for one store. Appends to the shared
# errors/warnings arrays; a soft failure returns, leaving the next store to run.
audit_outcomes() {
    local label="$1" rig_path="$2" raw="$3"
    local gating jrc vraw vrc bad id anchor lane oc
    # Live merge candidates: open gating anchors that are not themselves review
    # beads. A malformed approve backing only lands a merge while its anchor can
    # still merge, so a closed or abandoned anchor's outcome beads are out of
    # scope.
    gating=$(printf '%s' "$raw" | scrub | jq -c '[
        .[]? | (.metadata // {}) as $m
        | ((($m.merge_result // "") | tostring)) as $mr
        | select($mr == "pre_open_gate" or $mr == "pull_request")
        | select(((($m.task_kind // "") | tostring)) != "review")
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) ]' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ] || [ -z "$gating" ]; then
        warnings+=("$label: anchor listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        return
    fi
    [ "$(printf '%s' "$gating" | jq -r 'length' 2>/dev/null)" != "0" ] || return

    # Every closed review bead carrying a verdict. An approve backing always
    # carries signoff_verdict (both writers stamp it), so this key is the tight
    # candidate set; a close with no signoff_verdict lacks it and backs no lane,
    # so it is correctly never fetched. --status closed: only a closed bead backs a
    # lane, so an open one cannot be a malformed backing.
    vraw=$(run_bounded gc bd list --db "$rig_path/.beads" --status closed \
        --has-metadata-key signoff_verdict --json --limit 0 2>/dev/null); vrc=$?
    if [ "$vrc" -ne 0 ] || [ -z "$vraw" ]; then
        warnings+=("$label: could not read closed review outcomes in $rig_path/.beads (rc=$vrc) — this store was NOT checked")
        return
    fi
    bad=$(printf '%s' "$vraw" | scrub | jq -cr --argjson g "$gating" '
        ($g | map({(.): true}) | add // {}) as $set
        | .[]? | (.metadata // {}) as $m
        | select(((($m.task_kind // "") | tostring)) == "review")
        | select(((($m.signoff_verdict // "") | tostring)) == "approve")
        # reviewed_oid required: lane-state.sh derives no green from a local
        # backing without it, so a no-oid approve is no green risk to audit.
        | select(((($m.reviewed_oid // "") | tostring)) != "")
        | ((($m["gc.outcome"] // "") | tostring)) as $oc
        | select($oc != "recorded" and $oc != "superseded")
        | ((($m.anchor_bead // "") | tostring)) as $a
        | select(($set[$a] // false) == true)
        | [ ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")),
            ($a | gsub("[[:cntrl:]]"; " ")),
            (((($m.check_name // "") | tostring) | if . == "" then "correctness" else . end) | gsub("[[:cntrl:]]"; " ")),
            ($oc | gsub("[[:cntrl:]]"; " ")) ]
        | join("")' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ]; then
        warnings+=("$label: could not join review outcomes to anchors in $rig_path/.beads — this store was NOT checked")
        return
    fi
    while IFS=$'\037' read -r id anchor lane oc; do
        [ -n "$id" ] || continue
        errors+=("$label bead $id: approve outcome for lane $lane on anchor $anchor records gc.outcome=\"${oc:-<unset>}\", not recorded or superseded — lane-state.sh excludes only superseded, so this still derives $lane green and merge.sh will land the branch on an approve whose outcome no writer recorded")
    done <<< "$bad"
}

# rig-map.sh prints the map when the listing reads and only its reason when it
# does not, so one capture holds whichever came back.
RIG_MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/rig-map.sh"
rigs_raw=$(run_bounded "$RIG_MAP" 2>&1); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine gate provenance (I7)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    [ "$rigs_rc" -eq 0 ] || [ -z "$rigs_raw" ] || detail "$rigs_raw"
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi

    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --status open \
        --has-metadata-key merge_result --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list open anchors in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    audit_outcomes "$label" "$rig_path" "$raw"
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "gate provenance violated (I7): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "gate provenance holds with gaps (I7)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every approve outcome is coherent"
detail ${notes[@]+"${notes[@]}"}
exit 0
