#!/usr/bin/env bash
# doctor/check-epic-closed-implies-ruled — I14: a closed epic was ruled. An epic
# closes by a recorded ruling on its hypothesis — persevere, pivot, or close —
# after a validation step, never as a side effect of its last unit merging
# (docs/epics.md). A CLOSED issue_type=epic carrying no epic_ruling therefore
# either auto-closed when its last child merged (the transition epics.md forbids)
# or was closed by hand without the ruling (error); epic-steward.sh and the
# finalize-gate clause guard the live paths, and this is the after-the-fact
# backstop for a bare `gc bd close` that reaches neither.
# One shape is out of scope: an epic carrying gc.superseded_by was retired into a
# successor by bead-rehome.sh, which IS an explicit terminal state (the same
# exemption check-closed-implies-landed makes) — a deliberate disposition, not a
# silent close.
# Read-only, ledger-only, offline-safe. Exit 0=OK 1=Warning 2=Error. stdout:
# first line = message, then "  - detail" lines. Probes bounded; an UNREADABLE
# store warns (1), never passes.

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

# `gc rig list` names the stores this check scans, and it can fail transiently:
# a momentary Dolt or lock blip returns a non-zero rc a later call clears. This
# check files an all-rigs BLOCKING finding when it cannot enumerate, so a single
# blip must not stand in for "stores unscannable" — retry a non-zero rc a bounded
# number of times, each attempt drawn from the same doctor budget. An rc of 0 is
# never retried: rc=0 with no rigs is a genuinely empty city.
RIGS_MAX_ATTEMPTS=3
rigs_attempt=0
while : ; do
    rigs_attempt=$((rigs_attempt + 1))
    rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
    [ "$rigs_rc" -eq 0 ] && break
    [ "$rigs_attempt" -ge "$RIGS_MAX_ATTEMPTS" ] && break
    budget_spent && break
    sleep 1
done
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether closed epics were ruled (I14)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths after $rigs_attempt attempt(s); there is no set of bead stores to scan."
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --type=epic --status closed \
        --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        # `--limit 0` lists every closed epic, and an empty store returns `[]`,
        # not empty output — so empty here is an unreadable probe, not "no epics".
        warnings+=("$label: could not list closed epics in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    # A closed epic is judged only once it has entered stewardship — i.e. carries
    # a recorded hypothesis. One closed without a hypothesis predates the model
    # (there is no ruling to expect of an epic the stewardship contract never
    # reached), so it is exempt, which also keeps this a forward regression
    # detector: a store of pre-stewardship epics reports clean.
    # bd returns an {"error":...} object when a query does not resolve
    # (bead-context.sh). Iterating it with `.[]?` would yield zero rows at exit 0
    # and report the store OK; `error` on a non-array aborts jq non-zero, caught
    # below as "NOT checked" — an all-clear is only a clean array.
    rows=$(printf '%s' "$raw" | scrub | jq -r '
        (if type != "array" then error("not an array") else .[] end)
        | select(((.status // "") | tostring) == "closed")
        | (.metadata // {}) as $m
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
        | ((($m.epic_ruling // "") | tostring)) as $ruling
        | ((($m.epic_hypothesis // "") | tostring)) as $hyp
        | ((($m["gc.superseded_by"] // "") | tostring)) as $disposed
        # "ruled" only for a ruling docs/epics.md defines (persevere|pivot|close);
        # an off-enum value — "pending", a typo — is not a ruling and reads as
        # unruled, the same enum the finalize gate and the steward enforce.
        | (if ($ruling == "persevere" or $ruling == "pivot" or $ruling == "close") then "ruled"
           elif $disposed != "" then "exempt-disposed"
           elif $hyp != "" then "unruled"
           else "exempt-legacy" end) as $verdict
        | [$verdict, $id] | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: closed-epic listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    n_disposed=0; n_legacy=0
    while IFS=$'\037' read -r kind id; do
        [ -n "$kind" ] || continue
        case "$kind" in
            unruled)
                errors+=("$label epic $id: CLOSED carrying a hypothesis but no epic_ruling — an epic closes by a recorded hypothesis ruling (persevere/pivot/close) after a validation step, never by its last unit merging (docs/epics.md). Reopen it to rule (\`lifecycle.sh reopen $id\` then record epic_ruling), or if it was retired into a successor, record that disposition (\`bead-rehome.sh --origin $id --successor <bead> --kind <kind>\`)") ;;
            exempt-disposed) n_disposed=$((n_disposed + 1)) ;;
            exempt-legacy)   n_legacy=$((n_legacy + 1)) ;;
        esac
    done <<< "$rows"
    if [ "$n_disposed" -gt 0 ]; then
        notes+=("$label: $n_disposed closed epic(s) carry gc.superseded_by (retired into a successor), so they were not judged")
    fi
    if [ "$n_legacy" -gt 0 ]; then
        notes+=("$label: $n_legacy closed epic(s) predate epic stewardship (no recorded hypothesis), so no ruling is expected of them")
    fi
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "closed-but-unruled epics (I14): ${#errors[@]} epic(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "epic-closed-implies-ruled holds with gaps (I14)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every closed epic carries a recorded hypothesis ruling or an explicit disposition"
detail ${notes[@]+"${notes[@]}"}
exit 0
