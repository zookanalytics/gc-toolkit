#!/usr/bin/env bash
# doctor/check-step-terminal — I8: every step bead reaches a terminal state.
# Per store, every OPEN bead carrying gc.root_bead_id is judged against its
# molecule root: root CLOSED past the settle grace = error, in two shapes
# because they are different defects — REOPENED (the step carries gc.outcome:
# it completed and was reset, and the pool re-offers it against a dead
# molecule) and NEVER-CLOSED (the molecule finalized around it, offer-able
# forever); root OPEN but the step untouched past the stall bound (default 48h,
# GC_DOCTOR_STEP_STALL_HOURS) = warning, the stalled-frontier signal; root
# resolving nowhere in this store = note (cross-store roots are legitimate).
#
# No root map is ever built. Open steps stream, and the roots they name are
# resolved in fixed-size batches that keep only what a verdict needs: the ids
# the store returned as CLOSED, and the ids it did not return at all. Both are
# defect sets, so a healthy store carries nothing from one batch to the next
# and findings are the only thing that grows. `--status closed` is the store's
# predicate rather than the script's, so a healthy batch answers with an empty
# list and no root body is read; the existence probe behind it is a count, and
# only a count short of its batch pays to name which ids are missing. Peak argv
# is one batch of ids, which is why neither the molecule count nor the open-step
# count can walk into an exec limit.
#
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
# Finalize closes the root seconds before its terminal step closes itself.
GRACE="${GC_DOCTOR_FINALIZED_STEP_GRACE:-300}"
STALL_HOURS="${GC_DOCTOR_STEP_STALL_HOURS:-48}"
case "$STALL_HOURS" in *[!0-9]*|"") STALL_HOURS=48 ;; esac
STALL=$((STALL_HOURS * 3600))
CHUNK="${GC_DOCTOR_ROOT_CHUNK:-100}"   # root ids per batch (argv bound)
case "$CHUNK" in *[!0-9]*|""|0) CHUNK=100 ;; esac
SEP=$'\037'
# Closes each stream so a reader can tell "the store said nothing" from "the
# probe died". jq emits a root id in field 1 and never this word.
END='__probe_rc__'

errors=(); warnings=(); notes=()
declare -A root_closed=() root_missing=()
declare -A f_count=() f_steps=() f_extra=()
batch=()

run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
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
step_list() {
    run_bounded gc bd list --db "$1" --status open --has-metadata-key gc.root_bead_id \
        --limit 0 --flat --brief --skip-labels --json 2>/dev/null
}
root_list() {   # db ids [extra filters...]
    local db="$1" ids="$2"; shift 2
    run_bounded gc bd list --db "$db" --id "$ids" --all --limit 0 \
        --flat --brief --skip-labels --json "$@" 2>/dev/null
}

# `.issues` typed as an array is the fail-closed hinge: bd answers an object
# carrying that array, so anything else — an error body, a truncated read —
# aborts jq rather than reading as an empty store.
JQ_ISSUES='(if type == "object" and (.issues | type) == "array" then .issues
            else error("unexpected list shape") end) | .[]? | select(type == "object")'
JQ_EPOCH='def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);'
JQ_META='def m($k): (((.metadata[$k] // "") | tostring)
            | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "") | gsub("[[:cntrl:]]"; " "));'

# Every root id this store's open steps name, deduped. The trailer rides after
# the sort so it stays the last line the reader sees.
root_id_stream() {
    step_list "$1" | scrub | jq -r "$JQ_META $JQ_ISSUES
        | m(\"gc.root_bead_id\") | select(. != \"\")" 2>/dev/null | LC_ALL=C sort -u
    printf '%s%s%s\n' "$END" "$SEP" "${PIPESTATUS[*]}"
}

# One row per open step: root, step, whether it carries an outcome, whether it
# is past the stall bound, and the two values a finding quotes.
step_row_stream() {
    step_list "$1" | scrub | jq -r --argjson stall "$STALL" "$JQ_EPOCH $JQ_META $JQ_ISSUES
        | m(\"gc.root_bead_id\") as \$r
        | select(\$r != \"\")
        | (((.updated_at // .created_at // \"\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")) as \$ua
        | [ \$r,
            (((.id // \"?\") | tostring) | gsub(\"[[:cntrl:]]\"; \" \")),
            (if m(\"gc.outcome\") != \"\" then \"1\" else \"0\" end),
            (if (\$ua | ep) != null and (now - (\$ua | ep)) > \$stall then \"1\" else \"0\" end),
            \$ua,
            m(\"gc.root_store_ref\") ]
        | join(\"\u001f\")" 2>/dev/null
    printf '%s%s%s\n' "$END" "$SEP" "${PIPESTATUS[*]}"
}

# Every rc the pipeline reported must be 0; a stage that died leaves a partial
# reading, which must never be mistaken for a clean store.
stream_ok() { case "$1" in ""|*[!0-9\ ]*) return 1 ;; esac; case " $1 " in *" "[!0]*) return 1 ;; esac; return 0; }

# Resolve one batch of root ids into the two defect sets. Returns non-zero if
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
    while IFS="$SEP" read -r id ca fl; do
        [ -n "$id" ] || continue
        root_closed["$id"]="$fl$SEP$ca"
    done <<< "$out"

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
        while IFS= read -r id; do [ -n "$id" ] && present["$id"]=1; done <<< "$seen"
        for id in "${batch[@]}"; do
            [ -n "${present[$id]:-}" ] || root_missing["$id"]=1
        done
    fi
    batch=()
    return 0
}

# Group into one finding per (root, class): a molecule that stranded seven
# steps is ONE defect.
record() {  # class root step extra
    local key="$2$SEP$1"
    f_count["$key"]=$(( ${f_count["$key"]:-0} + 1 ))
    f_steps["$key"]="${f_steps["$key"]:-} $3"
    [ -n "${f_extra["$key"]:-}" ] || f_extra["$key"]="$4"
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

    unset -v root_closed root_missing f_count f_steps f_extra
    declare -A root_closed=() root_missing=() f_count=() f_steps=() f_extra=()
    batch=(); resolve_ok=1; probe_rc=""; seen_any=0

    while IFS= read -r line; do
        case "$line" in "$END$SEP"*) probe_rc="${line#"$END$SEP"}"; continue ;; esac
        [ -n "$line" ] || continue
        seen_any=1
        batch+=("$line")
        if [ "${#batch[@]}" -ge "$CHUNK" ]; then
            flush_batch "$db" || { resolve_ok=0; break; }
        fi
    done < <(root_id_stream "$db")

    # A batch that failed breaks the loop before the trailer is read, so the
    # resolution verdict is answered first — otherwise an unread trailer would
    # report the failure against the step listing, which was fine.
    if [ "$resolve_ok" -ne 1 ] || ! flush_batch "$db"; then
        warnings+=("$label: could not resolve molecule roots in $db — this store was NOT checked")
        continue
    fi
    if ! stream_ok "$probe_rc"; then
        warnings+=("$label: could not list open step beads in $db (rc=${probe_rc:-?}) — this store was NOT checked")
        continue
    fi
    [ "$seen_any" -eq 1 ] || continue

    probe_rc=""
    while IFS="$SEP" read -r rid sid oc stale ua ref; do
        case "$rid" in "$END") probe_rc="$sid"; continue ;; esac
        [ -n "$rid" ] || continue
        if [ -n "${root_missing[$rid]:-}" ]; then
            record orphan "$rid" "$sid" "$ref"
        elif [ -n "${root_closed[$rid]:-}" ]; then
            fl="${root_closed[$rid]%%"$SEP"*}"; ca="${root_closed[$rid]#*"$SEP"}"
            if   [ "$fl" = "settle" ]; then record settle   "$rid" "$sid" "$ca"
            elif [ "$oc" = "1" ];      then record reopened "$rid" "$sid" "$ca"
            else                            record stranded "$rid" "$sid" "$ca"; fi
        elif [ "$stale" = "1" ]; then
            record stall "$rid" "$sid" "$ua"
        fi
    done < <(step_row_stream "$db")

    if ! stream_ok "$probe_rc"; then
        warnings+=("$label: open-step/root join over $db could not be computed — this store was NOT checked")
        continue
    fi
    [ "${#f_count[@]}" -ne 0 ] || continue

    while IFS= read -r key; do
        [ -n "$key" ] || continue
        rid="${key%%"$SEP"*}"; cls="${key##*"$SEP"}"
        count="${f_count[$key]}"; ex="${f_extra[$key]:-}"
        sids=$(printf '%s\n' ${f_steps[$key]} | LC_ALL=C sort | paste -sd',' - | sed 's/,/, /g')
        case "$cls" in
            reopened) errors+=("$label: molecule $rid is CLOSED (closed_at=${ex:-<unset>}) yet $count step(s) are open AND already carry gc.outcome — $sids. They completed and were RESET; the pool re-offers each one against a dead molecule.") ;;
            stranded) errors+=("$label: molecule $rid is CLOSED (closed_at=${ex:-<unset>}) yet $count step(s) never closed — $sids. The molecule finalized around them; nothing can consume another pass, but the pool can still offer them.") ;;
            stall)    warnings+=("$label: molecule $rid is OPEN but $count of its open step(s) have not been touched in over ${STALL_HOURS}h — $sids (last update $ex). The frontier is stalled: nothing is claiming or advancing this workflow.") ;;
            settle)   notes+=("$label: molecule $rid closed within the ${GRACE}s settle window and still has $count open step(s) ($sids) — finalize in progress, not a strand") ;;
            orphan)   notes+=("$label: open step(s) $sids name root $rid, which resolves nowhere in $db (gc.root_store_ref=${ex:-<unset>}) — a cross-store root is legitimate, a deleted one is not; reported, not judged") ;;
        esac
    done < <(printf '%s\n' "${!f_count[@]}" | LC_ALL=C sort)
done <<< "$scopes"

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
echo "OK: no open step under a closed root, and no open frontier stalled past ${STALL_HOURS}h"
detail ${notes[@]+"${notes[@]}"}
exit 0
