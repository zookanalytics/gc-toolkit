#!/usr/bin/env bash
# doctor/check-step-terminal — I8: every step bead reaches a terminal state.
# Per store, every non-terminal bead carrying gc.root_bead_id is judged against
# its molecule root.
#
# Under a root CLOSED past the settle grace, the verdict turns on whether the
# pool can still hand the step out. A step is offerable when its own status is
# open and every blocking dependency has closed. That is an error, in two
# shapes because they are different defects: REOPENED carries gc.outcome, so it
# completed and was reset, and the pool re-offers it against a dead molecule;
# NEVER-CLOSED never completed and the molecule finalized around it. A step
# that is parked, or that still waits on a live blocker, is inert. Nothing can
# offer it, so it is a note.
#
# Offerability is measured, not assumed, and the listing therefore selects open
# AND blocked. A chain quiesced at its frontier parks that frontier at
# status=blocked, so a selector narrowed back to open alone would drop the
# parked row and then report the dep-blocked steps sitting behind it — the ones
# whose blocker it had just discarded.
#
# Under a root that is OPEN, a step untouched past the stall bound (default 48h,
# GC_DOCTOR_STEP_STALL_HOURS) is a warning, the stalled-frontier signal. A
# parked step is not a frontier and raises none. A root resolving nowhere in
# this store is a note; cross-store roots are legitimate.
#
# Nothing store-sized is ever held. The step listing is consumed as a
# stream of parse events, so no whole-document value exists here, and the rows
# are judged in fixed-size windows: a window's distinct roots are resolved, its
# rows classified, and the window dropped before the next one is read. Dedupe
# is per window, so a molecule whose steps straddle two windows is probed
# twice — repeated bounded work traded for a bounded working set. Roots resolve
# through `--status closed` plus a `bd count` existence probe, both
# defect-shaped: a healthy window answers with an empty list and a full count,
# and no root body is read. Blocker statuses resolve by the same id-scoped
# lookup, and only for the rows a closed root already condemns, so a store with
# nothing stranded never asks for one. Peak argv is one window of ids, peak
# memory is one window of rows, and findings are the only structure that grows,
# so neither the molecule count nor the step count can walk into an exec limit.
# `bd list --offset` is proxied-server-only, so the listing cannot be split at
# the CLI; consuming it as events is what bounds this reader instead.
#
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

# Finalize closes the root seconds before its terminal step closes itself.
GRACE="${GC_DOCTOR_FINALIZED_STEP_GRACE:-300}"
STALL_HOURS="${GC_DOCTOR_STEP_STALL_HOURS:-48}"
case "$STALL_HOURS" in *[!0-9]*|"") STALL_HOURS=48 ;; esac
STALL=$((STALL_HOURS * 3600))
CHUNK="${GC_DOCTOR_ROOT_CHUNK:-100}"   # step rows per window (argv + memory bound)
case "$CHUNK" in *[!0-9]*|""|0) CHUNK=100 ;; esac
SEP=$'\037'
# Closes the stream so a reader can tell "the store said nothing" from "the
# probe died". jq emits a root id in field 1 and never this word.
END='__probe_rc__'

errors=(); warnings=(); notes=()
declare -A root_closed=() root_missing=() window_seen=() blocker_live=()
declare -A f_count=() f_steps=() f_extra=()
batch=()
w_root=(); w_step=(); w_oc=(); w_stale=(); w_ua=(); w_ref=(); w_status=(); w_dep=()

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

# The two listings, projected to what a verdict reads. --flat is the shape that
# carries closed_at; --brief and --skip-labels keep descriptions and labels off
# the wire, so a row costs tens of bytes rather than a whole bead.
step_list() {   # db [extra flags...]
    local db="$1"; shift
    run_bounded gc bd list --db "$db" --status open,blocked --has-metadata-key gc.root_bead_id \
        --flat --brief --skip-labels --json "$@" 2>/dev/null
}
root_list() {   # db ids [extra filters...]
    local db="$1" ids="$2"; shift 2
    run_bounded gc bd list --db "$db" --id "$ids" --all --limit 0 \
        --flat --brief --skip-labels --json "$@" 2>/dev/null
}

# `.issues` typed as an array is the fail-closed hinge on a payload small enough
# to judge whole: bd answers an object carrying that array, so anything else —
# an error body, a truncated read — aborts jq rather than reading as an empty
# store.
JQ_ISSUES='(if type == "object" and (.issues | type) == "array" then .issues
            else error("unexpected list shape") end) | .[]? | select(type == "object")'
JQ_EPOCH='def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);'
JQ_META='def m($k): (((.metadata[$k] // "") | tostring)
            | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "") | gsub("[[:cntrl:]]"; " "));'

# One row per non-terminal step, unconditionally: root, step, whether it carries
# an outcome, whether it is past the stall bound, the two values a finding
# quotes, and the two an offerability verdict reads — the step's own status and
# the ids it is blocked by. Only `blocks` edges count; a step tracks its root
# through an edge of its own, and reading that one as a blocker would make every
# step in the store look held. A blank root names no molecule and is dropped by
# the reader rather than here, so the row count stays the count of non-terminal
# steps — which is what tells an unreadable listing apart from an empty store.
# Rows are rebuilt one at a time out of the parse-event stream, so the reader's
# cost is a row and never the listing.
step_row_stream() {
    step_list "$1" --limit 0 | scrub | jq -rn --stream --argjson stall "$STALL" "$JQ_EPOCH $JQ_META
        fromstream(2 | truncate_stream(inputs | select(.[0][0] == \"issues\")))
        | select(type == \"object\")
        | m(\"gc.root_bead_id\") as \$r
        | (((.updated_at // .created_at // \"\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")) as \$ua
        | [ \$r,
            (((.id // \"?\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")),
            (if m(\"gc.outcome\") != \"\" then \"1\" else \"0\" end),
            (if (\$ua | ep) != null and (now - (\$ua | ep)) > \$stall then \"1\" else \"0\" end),
            \$ua,
            m(\"gc.root_store_ref\"),
            (((.status // \"\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")),
            ([ .dependencies[]? | select(((.type // \"\") | tostring) == \"blocks\")
               | ((.depends_on_id // \"\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")
               | select(. != \"\") ] | join(\",\")) ]
        | join(\"\u001f\")" 2>/dev/null
    printf '%s%s%s\n' "$END" "$SEP" "${PIPESTATUS[*]}"
}

# An event stream cannot assert the listing's shape: an error body and a store
# with nothing selectable both yield no rows. So a store that produced none is
# asked again for a single row, a payload small enough to judge whole.
# 0 = non-terminal steps exist, 1 = none, 2 = unreadable.
steps_exist() {   # db
    local raw n
    raw=$(step_list "$1" --limit 1) || return 2
    n=$(printf '%s' "$raw" | scrub | jq -r 'if type == "object" and (.issues | type) == "array"
        then (.issues | length) else error("unexpected list shape") end' 2>/dev/null) || return 2
    case "$n" in ""|*[!0-9]*) return 2 ;; esac
    [ "$n" -eq 0 ] && return 1
    return 0
}

# Every rc the pipeline reported must be 0; a stage that died leaves a partial
# reading, which must never be mistaken for a clean store.
stream_ok() { case "$1" in ""|*[!0-9\ ]*) return 1 ;; esac; case " $1 " in *" "[!0]*) return 1 ;; esac; return 0; }

# Resolve one window's root ids into the two defect sets. Returns non-zero if
# any probe failed: a partial answer would reclassify real strands as notes.
flush_batch() {
    local db="$1" ids n raw out id ca fl cnt seen
    n="${#batch[@]}"
    [ "$n" -ne 0 ] || return 0
    ids=$( IFS=,; printf '%s' "${batch[*]}" )

    raw=$(root_list "$db" "$ids" --status closed) || return 1
    [ -n "$raw" ] || return 1
    out=$(printf '%s' "$raw" | scrub | jq -r --argjson grace "$GRACE" "$JQ_EPOCH $JQ_ISSUES
        | (((.id // \"\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")) as \$id
        | select(\$id != \"\")
        | (((.closed_at // \"\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")) as \$ca
        | (\$ca | ep) as \$ce
        | [ \$id, \$ca,
            (if \$ce != null and (now - \$ce) >= 0 and (now - \$ce) < \$grace
             then \"settle\" else \"old\" end) ]
        | join(\"\u001f\")" 2>/dev/null) || return 1
    # A pipe, not a here-string: bash backs `<<<` with a temp file, and a
    # window's legitimately empty reply is indistinguishable from one that
    # could not be staged. Process substitution keeps the loop in this shell
    # either way, so the defect sets it fills still survive it.
    while IFS="$SEP" read -r id ca fl; do
        [ -n "$id" ] || continue
        root_closed["$id"]="$fl$SEP$ca"
    done < <(printf '%s\n' "$out")

    # Existence, as a count first: `bd list --id` drops an id it cannot resolve
    # and still exits 0, so an absent row reads exactly like a healthy root
    # until the two id sets are compared. A full count means nothing is missing
    # and the comparison is not worth reading rows for.
    cnt=$(run_bounded gc bd count --db "$db" --id "$ids" 2>/dev/null) || return 1
    cnt="${cnt//[[:space:]]/}"
    case "$cnt" in *[!0-9]*|"") return 1 ;; esac
    if [ "$cnt" -lt "$n" ]; then
        raw=$(root_list "$db" "$ids") || return 1
        [ -n "$raw" ] || return 1
        seen=$(printf '%s' "$raw" | scrub | jq -r "$JQ_ISSUES
            | ((.id // \"\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \") | select(. != \"\")" 2>/dev/null) || return 1
        local -A present=()
        while IFS= read -r id; do [ -n "$id" ] && present["$id"]=1; done < <(printf '%s\n' "$seen")
        for id in "${batch[@]}"; do
            [ -n "${present[$id]:-}" ] || root_missing["$id"]=1
        done
    fi
    batch=()
    return 0
}

# Which of this window's blocking dependencies are still live. Asked only about
# rows a closed root already condemns, and never inside its settle grace, so a
# healthy store never reaches the probe. A blocker can be any bead, not only a
# sibling step, so the store is asked rather than the window: a step waiting on
# an ordinary open bead is held just as firmly as one waiting on its own chain.
# An id that resolves nowhere stays out of the set — a dependency that no longer
# exists holds nothing, and reporting its step is the conservative reading.
resolve_blockers() {   # db
    local db="$1" i n rid ids raw out id st dep
    n="${#w_root[@]}"
    local -A want=()
    i=0
    while [ "$i" -lt "$n" ]; do
        rid="${w_root[$i]}"
        if [ -z "${root_missing[$rid]:-}" ] && [ -n "${root_closed[$rid]:-}" ] \
           && [ "${root_closed[$rid]%%"$SEP"*}" != "settle" ]; then
            for dep in ${w_dep[$i]//,/ }; do want["$dep"]=1; done
        fi
        i=$((i + 1))
    done
    [ "${#want[@]}" -ne 0 ] || return 0
    ids=$( IFS=,; printf '%s' "${!want[*]}" )
    raw=$(root_list "$db" "$ids") || return 1
    [ -n "$raw" ] || return 1
    out=$(printf '%s' "$raw" | scrub | jq -r "$JQ_ISSUES
        | [ (((.id // \"\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")),
            (((.status // \"\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")) ]
        | join(\"\u001f\")" 2>/dev/null) || return 1
    while IFS="$SEP" read -r id st; do
        [ -n "$id" ] || continue
        [ "$st" = "closed" ] || blocker_live["$id"]=1
    done < <(printf '%s\n' "$out")
    return 0
}

# A step the pool can still hand out: open in its own right, with nothing live
# left to wait on. Everything else is residue that no pass can reach, and a
# finding that calls it loose spends a human on a chain that cannot move.
offerable() {   # window index
    local i="$1" dep
    [ "${w_status[$i]}" = "open" ] || return 1
    for dep in ${w_dep[$i]//,/ }; do
        [ -z "${blocker_live[$dep]:-}" ] || return 1
    done
    return 0
}

# Group into one finding per (root, class): a molecule that stranded seven
# steps is ONE defect. Windows are a reading device, not a grouping one — a
# molecule whose steps land in two of them still writes one key.
record() {  # class root step extra
    local key="$2$SEP$1"
    f_count["$key"]=$(( ${f_count["$key"]:-0} + 1 ))
    f_steps["$key"]="${f_steps["$key"]:-} $3"
    [ -n "${f_extra["$key"]:-}" ] || f_extra["$key"]="$4"
}

# Resolve this window's roots, judge its rows, drop it. The two root sets are
# scoped to the window for the same reason the rows are: neither may carry
# store-sized state into the next one.
classify_window() {   # db
    local db="$1" i n rid fl ca
    n="${#w_root[@]}"
    [ "$n" -ne 0 ] || return 0
    unset -v root_closed root_missing window_seen blocker_live
    declare -gA root_closed=() root_missing=() window_seen=() blocker_live=()
    flush_batch "$db" || return 1
    resolve_blockers "$db" || return 1
    i=0
    while [ "$i" -lt "$n" ]; do
        rid="${w_root[$i]}"
        if [ -n "${root_missing[$rid]:-}" ]; then
            record orphan "$rid" "${w_step[$i]}" "${w_ref[$i]}"
        elif [ -n "${root_closed[$rid]:-}" ]; then
            fl="${root_closed[$rid]%%"$SEP"*}"; ca="${root_closed[$rid]#*"$SEP"}"
            if   [ "$fl" = "settle" ];    then record settle   "$rid" "${w_step[$i]}" "$ca"
            elif ! offerable "$i";        then record inert    "$rid" "${w_step[$i]}" "$ca"
            elif [ "${w_oc[$i]}" = "1" ]; then record reopened "$rid" "${w_step[$i]}" "$ca"
            else                               record stranded "$rid" "${w_step[$i]}" "$ca"; fi
        elif [ "${w_stale[$i]}" = "1" ] && [ "${w_status[$i]}" = "open" ]; then
            record stall "$rid" "${w_step[$i]}" "${w_ua[$i]}"
        fi
        i=$((i + 1))
    done
    w_root=(); w_step=(); w_oc=(); w_stale=(); w_ua=(); w_ref=(); w_status=(); w_dep=()
    return 0
}

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether step beads reach terminal states (I8)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    db="$rig_path/.beads"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi

    unset -v root_closed root_missing window_seen blocker_live f_count f_steps f_extra
    declare -A root_closed=() root_missing=() window_seen=() blocker_live=()
    declare -A f_count=() f_steps=() f_extra=()
    batch=(); w_root=(); w_step=(); w_oc=(); w_stale=(); w_ua=(); w_ref=()
    w_status=(); w_dep=()
    resolve_ok=1; probe_rc=""; seen_any=0

    while IFS="$SEP" read -r rid sid oc stale ua ref st dep; do
        case "$rid" in "$END") probe_rc="$sid"; continue ;; esac
        [ -n "$sid" ] || continue
        seen_any=1
        [ -n "$rid" ] || continue
        w_root+=("$rid"); w_step+=("$sid"); w_oc+=("$oc")
        w_stale+=("$stale"); w_ua+=("$ua"); w_ref+=("$ref")
        w_status+=("$st"); w_dep+=("$dep")
        if [ -z "${window_seen[$rid]:-}" ]; then window_seen["$rid"]=1; batch+=("$rid"); fi
        if [ "${#w_root[@]}" -ge "$CHUNK" ]; then
            classify_window "$db" || { resolve_ok=0; break; }
        fi
    done < <(step_row_stream "$db")

    # A window that failed breaks the loop before the trailer is read, so the
    # resolution verdict is answered first — otherwise an unread trailer would
    # report the failure against the step listing, which was fine.
    if [ "$resolve_ok" -ne 1 ] || ! classify_window "$db"; then
        warnings+=("$label: could not resolve molecule roots or step blockers in $db — this store was NOT checked")
        continue
    fi
    if ! stream_ok "$probe_rc"; then
        warnings+=("$label: could not list step beads in $db (rc=${probe_rc:-?}) — this store was NOT checked")
        continue
    fi
    if [ "$seen_any" -eq 0 ]; then
        steps_exist "$db"; exists_rc=$?
        if [ "$exists_rc" -eq 2 ]; then
            warnings+=("$label: could not confirm whether $db holds any non-terminal step bead — this store was NOT checked")
        elif [ "$exists_rc" -eq 0 ]; then
            warnings+=("$label: $db holds step beads the listing did not yield — this store was NOT checked")
        fi
        continue
    fi
    [ "${#f_count[@]}" -ne 0 ] || continue

    while IFS= read -r key; do
        [ -n "$key" ] || continue
        rid="${key%%"$SEP"*}"; cls="${key##*"$SEP"}"
        count="${f_count[$key]}"; ex="${f_extra[$key]:-}"
        sids=$(printf '%s\n' ${f_steps[$key]} | LC_ALL=C sort | paste -sd',' - | sed 's/,/, /g')
        case "$cls" in
            reopened) errors+=("$label: molecule $rid is CLOSED (closed_at=${ex:-<unset>}) yet $count step(s) are offerable AND already carry gc.outcome — $sids. They completed and were RESET; the pool re-offers each one against a dead molecule.") ;;
            stranded) errors+=("$label: molecule $rid is CLOSED (closed_at=${ex:-<unset>}) yet $count step(s) never closed — $sids. The molecule finalized around them; each is open with every blocker closed, so the pool can still offer them.") ;;
            inert)    notes+=("$label: molecule $rid is CLOSED (closed_at=${ex:-<unset>}) with $count non-terminal step(s) — $sids. Each is parked or waiting on a live blocker, so no pool can offer them: residue to sweep, not a strand.") ;;
            stall)    warnings+=("$label: molecule $rid is OPEN but $count of its open step(s) have not been touched in over ${STALL_HOURS}h — $sids (last update $ex). The frontier is stalled: nothing is claiming or advancing this workflow.") ;;
            settle)   notes+=("$label: molecule $rid closed within the ${GRACE}s settle window and still has $count non-terminal step(s) ($sids) — finalize in progress, not a strand") ;;
            orphan)   notes+=("$label: non-terminal step(s) $sids name root $rid, which resolves nowhere in $db (gc.root_store_ref=${ex:-<unset>}) — a cross-store root is legitimate, a deleted one is not; reported, not judged") ;;
        esac
    done < <(printf '%s\n' "${!f_count[@]}" | LC_ALL=C sort)
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "non-terminal step beads under closed molecules (I8): ${#errors[@]} molecule(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "step-terminal holds with gaps or stalled frontiers (I8)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: no offerable step under a closed root, and no open frontier stalled past ${STALL_HOURS}h"
detail ${notes[@]+"${notes[@]}"}
exit 0
