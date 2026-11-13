#!/usr/bin/env bash
# doctor/check-state-space — I2: the anchor state space is closed.
# Per bead store: every open bead's merge_result value is a state declared in
# lifecycle/lifecycle.toml (built-in enum when the declaration is absent or
# unparseable) or a value of Gas Town's pending record; a closed-only state
# (merged, or the record's mr_merged) on an OPEN bead is an error; and
# an open bead in a declared detached state is held by nobody and offered to no
# pool. The merge cadence drives those states, so its assignee must be empty and
# its gc.routed_to must be empty or the declared park_route sentinel that no
# pool claims; any other value is a second driver racing the cadence. A detached
# anchor must also stay open: the cadence readers (pr-open, merge, pr-facts,
# gate-ensure) enumerate --status=open, so one claimed or held into any other
# live status drops out of every one of them until the claim resolves. The
# open-scoped scan misses that end-state for the same reason the cadence does, so
# a second probe reads the non-open live statuses to report it. No open bead
# carries a metadata key from the deleted healer-bookkeeping registry — those
# keys have no writer any more, so their presence means a retired repair pass is
# still writing state. Finally, no live bead carries a key the registry retired
# together with every reader (RETIRED_KEYS), whose presence is state nothing
# acts on any more.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: first line = message, then
# "  - detail" lines. Live probes are bounded; an UNREADABLE probe warns (1),
# never passes.

set -u

dir="${GC_PACK_DIR:-.}"

# The declared enum. "unanchored" (merge_result absent) has no stored value on
# the ordinary path, but a literal write of it is a declared state, not a drift.
BUILTIN_STATES="unanchored pre_open_gate pull_request merged abandoned retargeted blocked refused_false_completion"
BUILTIN_CLOSED="merged"
BUILTIN_DETACHED="pre_open_gate pull_request"
BUILTIN_PARK_ROUTE="human"
# The values Gas Town's pending record gives merge_result, kept outside the
# machine lifecycle.toml declares: services/gctk/pr/record spells them, and
# run.test.sh holds this copy to that file. mr_merged is the record's landed
# value, which only a closed bead carries. None is detached: the record keeps a
# bead assigned to the refinery, blocked while its PR waits on the merge.
RECORD_STATES="pull_request_pending pull_request_head_changed mr_merged pull_request_record_incomplete pull_request_reconcile_invalid pull_request_closed_unmerged pull_request_merged_unvalidated_head pull_request_merge_evidence_contradiction pull_request_legacy_closed_unverified pull_request_merged_close_refused"
RECORD_CLOSED="mr_merged"
lifecycle="$dir/lifecycle/lifecycle.toml"
toml_scalar() { # <file> <key> — the quoted string of the first `<key> = "..."`
    awk -v k="$2" '$0 ~ ("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\"") {
        sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }' "$1" 2>/dev/null
}
toml_array() { # <file> <key> — quoted strings of the first `<key> = [...]`
    awk -v k="$2" 'ok { print } $0 ~ ("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\\[") { ok = 1; print }' "$1" 2>/dev/null \
        | awk '{ print } /\]/ { exit }' | grep -o '"[^"]*"' | tr -d '"'
}
states=""; closed_states=""; detached_states=""; park_route=""
if [ -f "$lifecycle" ]; then
    states=$(toml_array "$lifecycle" "states")
    closed_states=$(toml_array "$lifecycle" "closed_states")
    detached_states=$(toml_array "$lifecycle" "detached_states")
    park_route=$(toml_scalar "$lifecycle" "park_route")
fi
[ -n "$states" ] || states=$(printf '%s\n' $BUILTIN_STATES)
[ -n "$closed_states" ] || closed_states=$(printf '%s\n' $BUILTIN_CLOSED)
[ -n "$detached_states" ] || detached_states=$(printf '%s\n' $BUILTIN_DETACHED)
[ -n "$park_route" ] || park_route="$BUILTIN_PARK_ROUTE"
states=$(printf '%s\n' $states $RECORD_STATES)
closed_states=$(printf '%s\n' $closed_states $RECORD_CLOSED)
states_json=$(printf '%s\n' "$states" | jq -R . | jq -cs 'map(select(. != ""))')
closed_json=$(printf '%s\n' "$closed_states" | jq -R . | jq -cs 'map(select(. != ""))')
detached_json=$(printf '%s\n' "$detached_states" | jq -R . | jq -cs 'map(select(. != ""))')
enum_str=$(printf '%s' "$states_json" | jq -r 'join(", ")')

# Keys deleted from the metadata registry along with their healer writers.
HEALER_RE='^(check_set_healed|merge_result_healed|reopened_not_landed|anchorless_flagged|close_failures|close_escalated|gate_verdict_condemned)$'
# Keys retired from the metadata registry together with every reader, what a
# live bead still carrying one leaves undone, and what to do about it. They are
# read on every live status, because a bead a session holds is in_progress, not
# open. The escalation keys are the visit-era helper's
# (specs/tk-0ur8r9p/design.md section 2): human-gate.sh writes none of them, so
# a carrier holds nothing back and means a retired writer is stamping again.
# gc.hold_demand and the gc.pr_visit_* pair are the visit-era sitting's
# (section 7): a hold files a human gate its conversation replies to, and the
# sign-off hands the reminder its text directly. gc.outcome_reason is the
# visit-era close's (section 10): a conversation's close reason carries that
# sentence, and the board's sittings card reads it there. From escalation_key
# on, the keys are the visit's and the legacy demand's own, and the finding
# keys that named a visit (section 10). The successor keys are the disposition's
# before bd's own edges carried it: a disposed bead closes with a duplicates or
# supersedes edge, so a live bead still carrying one is a close that never
# landed. gc.supersedes, the successor's inert back-pointer, is not among them.
# placement is intake's retired marker on new work it holds for placement.
# Intake holds that work with Gas City's hold:mayor label, and the po's queue
# reads only the label, so a live bead carrying the marker and no hold waits in
# no queue.
RETIRED_KEYS=(
    stall_root escalation_raised_by escalation.recurrences escalation.recurrence_last
    gc.hold_demand gc.pr_visit_summary gc.pr_visit_actions gc.outcome_reason
    escalation_key gc.demand_for gc.gate_visit gc.ruling gc.folded_into
    visit.recheck sweep.new_ids sweep.carried_ids sweep.pass_at
    finding.visit finding.ruling_visit
    gc.superseded_by gc.superseded_by_store superseded_by superseded_by_store
    duplicate_of duplicate_of_store
    placement
)
retired_consequence() { # <key> <value> <bead>
    local inert="so nothing writes or reads the key; it holds nothing back, and a live bead carrying it means a retired writer stamped it. Find that writer, then clear the key"
    case "$1" in
        stall_root) printf '%s' "a sitting that read it may have filed its hold's demand (a human gate that blocks $2) and takeaway on $2, and no sign-off reads the key back to discharge them. Discharge that by hand, then clear the key" ;;
        escalation_raised_by|escalation.recurrences|escalation.recurrence_last)
            printf '%s' "human-gate.sh neither redirects a wisp nor keeps a recurrence tally, $inert" ;;
        gc.hold_demand)
            printf '%s' "a converse hold files a human gate its conversation replies to, $inert" ;;
        gc.pr_visit_summary|gc.pr_visit_actions)
            printf '%s' "the sign-off hands the PR reminder its text directly, $inert" ;;
        gc.outcome_reason)
            printf '%s' "the board's sittings card reads a conversation's close reason, $inert" ;;
        escalation_key|gc.demand_for|gc.gate_visit|gc.ruling|gc.folded_into|visit.recheck|sweep.new_ids|sweep.carried_ids|sweep.pass_at|finding.visit|finding.ruling_visit)
            printf '%s' "the key belongs to visits and legacy demands, which human gates and conversations replace, $inert" ;;
        gc.superseded_by|superseded_by)
            printf '%s' "a disposition records its successor in a duplicates or supersedes edge and closes with it, so this one never closed and nothing will close it. Close it onto $2 through bead-rehome.sh with its kind, or clear the key" ;;
        duplicate_of)
            printf '%s' "a duplicate closes at once with a duplicates edge, and no sweep closes a parked one, so its close is owed. Close it with bead-rehome.sh --successor $2 --kind duplicate, or clear the key" ;;
        gc.superseded_by_store|superseded_by_store|duplicate_of_store)
            printf '%s' "the store half of a retired successor key, read beside it and nowhere else. Settle the bead's successor key first, then clear this one" ;;
        placement)
            printf '%s' "intake holds new work with Gas City's hold:mayor label and nothing writes this marker, so a retired writer stamped it. The po's queue reads only the label, so a bead carrying the marker and no hold:mayor waits in no queue. Unless a parent, a route, an arm, an assignee or a live run shows it placed, hold it with gc bd set-state $3 hold=mayor --reason \"<why it waits for placement>\", then clear the key" ;;
        *) printf '%s' "nothing reads it. Clear the key" ;;
    esac
}
retired_json=$(printf '%s\n' "${RETIRED_KEYS[@]}" | jq -R . | jq -cs .)

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

# rig-map.sh prints the map when the listing reads and only its reason when it
# does not, so one capture holds whichever came back.
RIG_MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/rig-map.sh"
rigs_raw=$(run_bounded "$RIG_MAP" 2>&1); rigs_rc=$?
# US-joined so a rig with an empty name still yields its path field intact.
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether the state space holds (I2)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    [ "$rigs_rc" -eq 0 ] || [ -z "$rigs_raw" ] || detail "$rigs_raw"
    exit 1
fi

# A `<<<` here-string is backed by a temp file in $TMPDIR; under disk pressure
# that file cannot be created, the redirection fails silently (this check is
# set -u, not set -e), and the loop it feeds runs zero times — a non-empty set
# read as empty, which this check would otherwise report as a clean all-clear.
# Each enumeration below is staged into a file under this checked, templated temp
# dir and read with a plain `< "$file"`, which keeps the loop in the current
# shell so the finding arrays survive it; a staging failure is loud, never a
# forged all-clear. The dir and its files die with this process.
ENUM_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-state-space.XXXXXX" 2>/dev/null) || {
    echo "cannot determine whether the state space holds (I2)"
    detail "could not create a temp directory to stage the store enumerations (mktemp -d failed — e.g. /tmp under disk pressure); nothing was scanned, so this run is not an all-clear"
    exit 1
}
trap 'rm -rf "$ENUM_TMP" 2>/dev/null' EXIT
if ! printf '%s\n' "$scopes" > "$ENUM_TMP/scopes"; then
    echo "cannot determine whether the state space holds (I2)"
    detail "could not stage the store enumeration (temp-file write failed — e.g. /tmp under disk pressure); nothing was scanned, so this run is not an all-clear"
    exit 1
fi
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --status open --include-gates --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list open beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$raw" | scrub | jq -r \
        --argjson states "$states_json" --argjson closed "$closed_json" \
        --argjson detached "$detached_json" --arg park "$park_route" --arg hre "$HEALER_RE" '
        def clean: tostring | gsub("[[:cntrl:]]"; " ");
        .[]? | . as $b | ($b.metadata // {}) as $m
        | (($b.id // "?") | clean) as $id
        | (($b.assignee // "") | clean) as $as
        | (($m["gc.routed_to"] // "") | clean) as $rt
        | ( (if ($m | has("merge_result")) then
               ((($m.merge_result // "") | tostring)) as $mr
               | (if $mr == "" then []
                  elif ($states | index($mr)) == null then [["badmr", $id, $mr, ""]]
                  elif ($closed | index($mr)) != null then [["openclosed", $id, $mr, ""]]
                  elif ($detached | index($mr)) != null then
                    ((if $rt == "" or $rt == $park then [] else [["detachedroute", $id, $mr, $rt]] end)
                     + (if $as == "" then [] else [["detachedassignee", $id, $mr, $as]] end))
                  else [] end)
             else [] end)
            + [ $m | keys[]
                | select(test($hre) or startswith("stranded_branch_") or startswith("stale_gate_"))
                | ["healer", $id, ., ""] ] )[]
        | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: open-bead listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi

    # A detached anchor that has been claimed or held into a non-open live status
    # is invisible to the open-scoped scan above AND to every cadence reader
    # (pr-open, merge, pr-facts, gate-ensure), all of which enumerate
    # --status=open — so it stalls in the pipeline unseen until the claim
    # resolves. Read the non-open live statuses, narrowed to merge_result-bearing
    # beads, so this end-state has a reader. A live claim is not overwritten here;
    # it is surfaced, the same escalate-not-overwrite the cadence itself keeps.
    craw=$(run_bounded gc bd list --db "$rig_path/.beads" \
        --status in_progress,blocked,deferred,hooked,pinned \
        --has-metadata-key merge_result --json --limit 0 2>/dev/null); crc=$?
    if [ "$crc" -ne 0 ] || [ -z "$craw" ]; then
        warnings+=("$label: could not list claimed/held anchors in $rig_path/.beads (rc=$crc) — the detached-state claim check did NOT run for this store")
    else
        crows=$(printf '%s' "$craw" | scrub | jq -r --argjson detached "$detached_json" '
            def clean: tostring | gsub("[[:cntrl:]]"; " ");
            .[]? | . as $b | ($b.metadata // {}) as $m
            | (($b.id // "?") | clean) as $id
            | (($b.status // "") | clean) as $st
            | (($m.merge_result // "") | tostring) as $mr
            | select(($detached | index($mr)) != null)
            | [$id, $mr, $st] | join("\u001f")' 2>/dev/null)
        if [ $? -ne 0 ]; then
            warnings+=("$label: claimed/held anchor listing from $rig_path/.beads could not be parsed — the detached-state claim check did NOT run for this store")
        elif [ -n "$crows" ]; then
            if printf '%s\n' "$crows" > "$ENUM_TMP/crows"; then
                while IFS=$'\037' read -r id mr st; do
                    [ -n "$id" ] || continue
                    errors+=("$label bead $id: merge_result=$mr is a detached state (lifecycle/lifecycle.toml detached_states) but the bead is status=$st, not open — a detached anchor rests open so the merge cadence can drive it, and every cadence reader (pr-open, merge, pr-facts, gate-ensure) enumerates --status=open, so this claimed/held anchor has dropped out of the pipeline unseen until the claim resolves")
                done < "$ENUM_TMP/crows"
            else
                warnings+=("$label: could not stage the detached-state claim enumeration (temp-file write failed — e.g. /tmp under disk pressure) — the detached-state claim check did NOT run for this store")
            fi
        fi
    fi

    # The retired keys are read from the open listing above and from one listing
    # of the other live statuses, so the probe count stays the same however many
    # keys retire. Both listings take --include-gates: bd lists no gate without
    # it, and a legacy demand's keys sit on a gate.
    lraw=$(run_bounded gc bd list --db "$rig_path/.beads" \
        --status in_progress,blocked,deferred,hooked,pinned --include-gates --json --limit 0 2>/dev/null); lrc=$?
    if [ "$lrc" -ne 0 ] || [ -z "$lraw" ]; then
        warnings+=("$label: could not list the beads in a live status other than open in $rig_path/.beads (rc=$lrc) — the retired-key check did NOT run for this store")
    elif ! rrows=$({ printf '%s' "$raw" | scrub; printf '%s' "$lraw" | scrub; } | jq -rs --argjson keys "$retired_json" '
            def clean: tostring | gsub("[[:cntrl:]]"; " ");
            (map(.[]?) | .[]) as $b | ($b.metadata // {}) as $m
            | $keys[] as $k | ($m[$k] // "" | clean) as $v
            | select($v != "")
            | [(($b.id // "?") | clean), (($b.status // "") | clean), $k, $v] | join("\u001f")' 2>/dev/null); then
        warnings+=("$label: the live-bead listing from $rig_path/.beads could not be parsed for retired keys — the retired-key check did NOT run for this store")
    elif [ -n "$rrows" ]; then
        if printf '%s\n' "$rrows" > "$ENUM_TMP/retired"; then
            while IFS=$'\037' read -r id st rk val; do
                [ -n "$id" ] || continue
                errors+=("$label bead $id (status=$st): carries the retired key $rk=\"$val\" — lifecycle/lifecycle.toml retired it with every reader: $(retired_consequence "$rk" "$val" "$id"): gc bd update $id --unset-metadata $rk")
            done < "$ENUM_TMP/retired"
        else
            warnings+=("$label: could not stage the retired-key enumeration (temp-file write failed — e.g. /tmp under disk pressure) — the retired-key check did NOT run for this store")
        fi
    fi

    [ -n "$rows" ] || continue
    if ! printf '%s\n' "$rows" > "$ENUM_TMP/rows"; then
        warnings+=("$label: could not stage the state-space enumeration (temp-file write failed — e.g. /tmp under disk pressure) — this store was NOT checked")
        continue
    fi
    while IFS=$'\037' read -r kind id val extra; do
        [ -n "$kind" ] || continue
        case "$kind" in
            badmr)      errors+=("$label bead $id: merge_result=\"$val\" is not a declared state ($enum_str) — an unknown state has no handler and every reader defaults differently on it; surface it with human-gate.sh, never invent a reading") ;;
            openclosed) errors+=("$label bead $id: OPEN with merge_result=$val — a closed-only state on an open bead means the close half of the transition was lost or a landed anchor was reopened") ;;
            detachedroute)    errors+=("$label bead $id: merge_result=$val carries gc.routed_to=\"$extra\" — $val is a detached state (lifecycle/lifecycle.toml detached_states), driven by the merge cadence and offered to no pool, so any route but the \"$park_route\" park is demand for work already in the merge queue; the claim it invites moves the anchor out of \`--status=open\`, where merge.sh and pr-facts.sh both stop seeing it") ;;
            detachedassignee) errors+=("$label bead $id: merge_result=$val carries assignee=\"$extra\" — $val is a detached state (lifecycle/lifecycle.toml detached_states) and rests unheld; a holder here is a second driver racing the cadence on one anchor") ;;
            healer)     errors+=("$label bead $id: carries deleted healer-bookkeeping key \"$val\" — lifecycle/lifecycle.toml removed it with its writer, so something retired is still writing state") ;;
        esac
    done < "$ENUM_TMP/rows"
done < "$ENUM_TMP/scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "state space violated (I2): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "state space partially determined (I2)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every open bead's merge_result is a declared state, every detached-state anchor is open and rests unheld and offered to no pool, no deleted healer key survives, and no live bead carries a retired key"
detail ${notes[@]+"${notes[@]}"}
exit 0
