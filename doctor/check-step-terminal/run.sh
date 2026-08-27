#!/usr/bin/env bash
# doctor/check-step-terminal — I8: every step bead reaches a terminal state.
# Per store, every OPEN bead carrying gc.root_bead_id is joined to its root:
# root CLOSED past the settle grace = error, in two shapes because they are
# different defects — REOPENED (the step carries gc.outcome: it completed and
# was reset, and the pool re-offers it against a dead molecule) and
# NEVER-CLOSED (the molecule finalized around it, offer-able forever); root
# OPEN but the step untouched past the stall bound (default 48h,
# GC_DOCTOR_STEP_STALL_HOURS) = warning, the stalled-frontier signal; root
# resolving nowhere in this store = note (cross-store roots are legitimate).
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
# Finalize closes the root seconds before its terminal step closes itself.
GRACE="${GC_DOCTOR_FINALIZED_STEP_GRACE:-300}"
STALL_HOURS="${GC_DOCTOR_STEP_STALL_HOURS:-48}"
case "$STALL_HOURS" in *[!0-9]*|"") STALL_HOURS=48 ;; esac
STALL=$((STALL_HOURS * 3600))
CHUNK="${GC_DOCTOR_ROOT_CHUNK:-100}"   # bd show batch size (argv bound)

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
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
    steps_raw=$(run_bounded bd list --db "$db" --status open --has-metadata-key gc.root_bead_id --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$steps_raw" ]; then
        warnings+=("$label: could not list open step beads in $db (rc=$rc) — this store was NOT checked")
        continue
    fi
    steps=$(printf '%s' "$steps_raw" | scrub)
    root_ids=$(printf '%s' "$steps" | jq -r '[ .[]? | (.metadata["gc.root_bead_id"] // "" | tostring)
          | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "") | select(. != "") ] | unique | .[]' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: open-step listing from $db could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$root_ids" ] || continue

    # Batched root resolution; an unreadable chunk aborts the store — a partial
    # root map would reclassify real strands as cross-store notes.
    roots_json='[]'; chunk_failed=""; chunk=()
    flush_chunk() {
        [ "${#chunk[@]}" -ne 0 ] || return 0
        local out merged
        out=$(run_bounded bd show --db "$db" "${chunk[@]}" --json 2>/dev/null) && [ -n "$out" ] || { chunk_failed=yes; return 1; }
        # `bd show` answers an ARRAY normally, an OBJECT when NO id resolves
        # (rc=0 either way); the object's ids surface as unresolved-root notes.
        merged=$(printf '%s' "$out" | scrub | jq -c --argjson a "$roots_json" '
            if type == "array" then $a + . elif type == "object" then $a
            else error("unexpected") end' 2>/dev/null)
        [ -n "$merged" ] || { chunk_failed=yes; return 1; }
        roots_json="$merged"; chunk=()
    }
    while IFS= read -r rid; do
        [ -n "$rid" ] || continue
        chunk+=("$rid"); [ "${#chunk[@]}" -ge "$CHUNK" ] && { flush_chunk || break; }
    done <<< "$root_ids"
    [ -n "$chunk_failed" ] || flush_chunk || true
    [ -z "$chunk_failed" ] || { warnings+=("$label: could not resolve molecule roots in $db — this store was NOT checked"); continue; }

    # One row per (root, class): a molecule that stranded seven steps is ONE defect.
    rows=$(printf '%s' "$steps" | jq -r --argjson roots "$roots_json" \
        --argjson grace "$GRACE" --argjson stall "$STALL" '
        def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);
        ($roots | map(select(type == "object" and ((.id // "") | tostring) != ""))
                | map({key: (.id | tostring), value: .}) | from_entries) as $R
        | [ .[]? | . as $s
            | ((($s.metadata["gc.root_bead_id"] // "") | tostring)
               | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) as $rid
            | select($rid != "")
            | ($R[$rid] // null) as $root
            | ((($s.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $sid
            | (if $root == null
               then {cls: "orphan", rid: $rid, sid: $sid,
                     ex: ((($s.metadata["gc.root_store_ref"] // "") | tostring) | gsub("[[:cntrl:]]"; " "))}
               elif (($root.status // "") | tostring) == "closed"
               then ((($root.closed_at // "") | tostring)) as $ca
                    | ($ca | ep) as $ce
                    | (if $ce != null and (now - $ce) >= 0 and (now - $ce) < $grace
                       then {cls: "settle", rid: $rid, sid: $sid, ex: $ca}
                       elif ((($s.metadata["gc.outcome"] // "") | tostring)
                             | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) != ""
                       then {cls: "reopened", rid: $rid, sid: $sid, ex: $ca}
                       else {cls: "stranded", rid: $rid, sid: $sid, ex: $ca} end)
               else ((($s.updated_at // $s.created_at // "") | tostring)) as $ua
                    | ($ua | ep) as $ue
                    | (if $ue != null and (now - $ue) > $stall
                       then {cls: "stall", rid: $rid, sid: $sid, ex: $ua}
                       else empty end)
               end) ]
        | group_by(.rid + "\u001f" + .cls) | .[]
        | [ .[0].cls, .[0].rid, (length | tostring), .[0].ex,
            ([.[].sid] | sort | join(", ")) ]
        | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: open-step/root join over $db could not be computed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    while IFS=$'\037' read -r cls rid count ex sids; do
        [ -n "$cls" ] || continue
        case "$cls" in
            reopened) errors+=("$label: molecule $rid is CLOSED (closed_at=${ex:-<unset>}) yet $count step(s) are open AND already carry gc.outcome — $sids. They completed and were RESET; the pool re-offers each one against a dead molecule.") ;;
            stranded) errors+=("$label: molecule $rid is CLOSED (closed_at=${ex:-<unset>}) yet $count step(s) never closed — $sids. The molecule finalized around them; nothing can consume another pass, but the pool can still offer them.") ;;
            stall)    warnings+=("$label: molecule $rid is OPEN but $count of its open step(s) have not been touched in over ${STALL_HOURS}h — $sids (last update $ex). The frontier is stalled: nothing is claiming or advancing this workflow.") ;;
            settle)   notes+=("$label: molecule $rid closed within the ${GRACE}s settle window and still has $count open step(s) ($sids) — finalize in progress, not a strand") ;;
            orphan)   notes+=("$label: open step(s) $sids name root $rid, which resolves nowhere in $db (gc.root_store_ref=${ex:-<unset>}) — a cross-store root is legitimate, a deleted one is not; reported, not judged") ;;
        esac
    done <<< "$rows"
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
