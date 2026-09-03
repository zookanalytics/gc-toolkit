#!/usr/bin/env bash
# doctor/check-gate-integrity — I6+I7 surface: gates are declared and their
# markers well-formed. Per store, every OPEN gating anchor (merge_result =
# pre_open_gate|pull_request) must declare a non-empty check_set — the "none"
# sentinel is the one legal opt-out; merge.sh reads empty as UNGATED, so an
# empty or absent declaration silently drops the gate (error). Every
# check.<g> marker (sidecar keys like check.<g>.reason excluded) must match
# the grammar green|fixable|exception@<40-hex oid> — a malformed marker is
# evidence bound to nothing (error). A green marker on an anchor with no
# branch metadata is a warning: the oid cannot be compared to any head.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE store warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"

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
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine gate integrity (I6/I7)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
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
    rows=$(printf '%s' "$raw" | scrub | jq -r '
        .[]? | (.metadata // {}) as $m
        | ((($m.merge_result // "") | tostring)) as $mr
        | select($mr == "pre_open_gate" or $mr == "pull_request")
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
        | ((($m.check_set // "") | tostring)) as $cs
        | ((($m.branch // "") | tostring)) as $br
        | ( (if $cs == "" then [["nocs", $id, $mr, ""]] else [] end)
          + [ $m | to_entries[]
              | select(.key | test("^check\\.[^.]+$"))
              | select((.value | type) == "string")
              | (.value | gsub("[[:cntrl:]]"; " ")) as $v
              | (if ($v | test("^(green|fixable|exception)@[0-9a-f]{40}$")) | not
                 then ["badmark", $id, .key, $v]
                 elif ($v | startswith("green@")) and $br == ""
                 then ["greennobranch", $id, .key, $v]
                 else empty end) ] )[]
        | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: anchor listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    while IFS=$'\037' read -r kind id k v; do
        [ -n "$kind" ] || continue
        case "$kind" in
            nocs)          errors+=("$label bead $id: gating anchor (merge_result=$k) declares NO check_set — merge.sh reads empty as ungated, so this PR can land with no review; stamp the declared default (gate-ensure.sh) or the explicit \"none\" opt-out") ;;
            badmark)       errors+=("$label bead $id: gate marker $k=\"$v\" does not match the grammar <green|fixable|exception>@<40-hex oid> — a marker bound to no commit is not evidence, and merge.sh cannot compare it to the live head") ;;
            greennobranch) warnings+=("$label bead $id: $k=\"$v\" is green but the anchor records NO branch — nothing can verify the oid against a live head, so the marker's evidence binding is unverifiable") ;;
        esac
    done <<< "$rows"
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "gate integrity violated (I6/I7): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "gate integrity holds with gaps (I6/I7)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every open gating anchor declares its check_set and every gate marker is well-formed"
detail ${notes[@]+"${notes[@]}"}
exit 0
