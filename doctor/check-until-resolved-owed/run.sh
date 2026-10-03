#!/usr/bin/env bash
# doctor/check-until-resolved-owed — a resolved-by disposition is firing or
# surfaced. A bead carrying an `until` edge means "X resolves me": when that
# target closes, the deferred-dispatch reconcile order (orders/deferred-dispatch.toml,
# every 2m) disposes the bead through bead-rehome, so a wait whose named cause has
# landed is closed with a successor pointer rather than re-entering triage. The
# pass disposes an OPEN, UNASSIGNED bead whose own `until` targets have all
# closed, so a healthy resolved-by edge is short-lived: it rests until its target
# closes, then is disposed within a cadence.
#
# The silent stall this catches, caught nowhere else: the bead is open and
# unassigned, every one of its `until` targets has closed, no open `blocks`
# blocker still holds it, yet it has stayed undisposed well past the reconcile
# cadence. Either the order is not running (check-cadence-live/I10 is the direct
# cause, but a single owed disposition makes the effect concrete) or the close is
# stuck. The common stuck case is a legitimate hold: an OPEN visit on the bead
# holds its close (bead-rehome refuses rather than forcing it), and the remedy is
# to conclude that visit; the other is a resolve-by edge no longer wanted, removed
# with `gc bd dep remove`.
#
# ONLY `until` is read. A `blocks` edge is sequencing — its target closing leaves
# the dependent fully owed — so it is never a disposal and a bead held by an open
# `blocks` blocker is correctly waiting, never flagged. A bead already assigned is
# a live worker's, and reconcile would not dispose over it; a non-open bead is a
# deliberate hold the pass leaves alone; neither is owed a disposition.
#
# Read-only. Exit 0=OK 1=Warning. stdout: first line = message, then
# "  - detail" lines. Warn-only. An UNREADABLE probe warns (1), never passes —
# an unread store is not a clean one.

set -u

# A disposition owed longer than this has missed multiple reconcile passes.
# Mirrors check-cadence-live's I10 floor, max(3×interval, 15m): the
# deferred-dispatch order runs every 2m, so 900s is more than seven passes — long
# past any normal window between a target closing and the next reconcile disposing.
OWED_WINDOW_SECONDS=900

UNTIL_TYPE="until"

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
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

now_epoch() { budget_now; }
# ISO-8601 UTC -> epoch seconds, or empty if it will not parse (GNU then BSD).
iso_to_epoch() {
    [ -n "$1" ] || { printf ''; return; }
    date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || printf ''
}

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)] | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether owed resolved-by dispositions are firing"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

now=$(now_epoch)
declare -A until_of=(); declare -A blocks_of=()
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    # A suspended rig's store is cold; querying it would auto-start an orphan
    # Dolt server, so it is skipped the way the sibling store checks skip it.
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    # Every OPEN bead in this store, with its own outgoing edges. An `until` edge
    # carries no metadata key to scope on, so there is no narrower listing than
    # the open set; --brief drops the free-form text the scan does not read while
    # keeping status, assignee and the dependency edges.
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --brief --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
        warnings+=("$label: could not list open beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    # A candidate is an OPEN, UNASSIGNED bead carrying at least one `until` edge.
    # Its row carries its own outgoing edges under `.dependencies` in the list-edge
    # shape ({depends_on_id, type}), so the until targets and any `blocks` blockers
    # are read off this one listing, no per-bead dep call. Emits one line per
    # candidate: id, comma-joined until-target ids, comma-joined blocks-blocker ids.
    classified=$(printf '%s' "$raw" | scrub | jq -r --arg ut "$UNTIL_TYPE" '
        .[]? | . as $b
        | ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $id
        | (($b.status // "") | tostring) as $st
        | (($b.assignee // "") | tostring) as $as
        | [ ($b.dependencies // [])[] | select(.type == $ut) | .depends_on_id ] as $u
        | select($st == "open" and $as == "" and ($u | length) > 0)
        | [ ($b.dependencies // [])[] | select(.type == "blocks") | .depends_on_id ] as $blk
        | "\($id)\t\($u | unique | join(","))\t\($blk | unique | join(","))"' 2>/dev/null) || {
        warnings+=("$label: could not evaluate open beads in $rig_path/.beads — this store was NOT checked")
        continue
    }
    [ -n "$classified" ] || continue

    # Collect every referenced id — until targets and blocks blockers alike — and
    # resolve their statuses in ONE listing. --all so a CLOSED target is visible
    # (the close is what releases the disposition); the include-* flags so a
    # gate/infra/template target is not hidden and read as unresolved; --id silently
    # drops an id with no row, so a referenced id still absent from the result is
    # treated as unresolved below (its candidate is NOT checked), never as closed.
    cand_ids=(); until_of=(); blocks_of=()
    while IFS=$'\t' read -r cid utargets blockers; do
        [ -n "$cid" ] || continue
        cand_ids+=("$cid"); until_of["$cid"]="$utargets"; blocks_of["$cid"]="$blockers"
    done <<< "$classified"
    [ "${#cand_ids[@]}" -gt 0 ] || continue

    all_ref_ids=$(printf '%s\n' "${until_of[@]}" "${blocks_of[@]}" | tr ',' '\n' | grep . | sort -u | paste -sd, -)
    statuses='[]'
    if [ -n "$all_ref_ids" ]; then
        st_raw=$(run_bounded gc bd list --db "$rig_path/.beads" --id "$all_ref_ids" --all --include-gates --include-infra --include-templates --brief --json --limit 0 2>/dev/null); src=$?
        if [ "$src" -ne 0 ] || ! printf '%s' "$st_raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
            warnings+=("$label: could not read until-target/blocker statuses for ${#cand_ids[@]} candidate(s) in $rig_path/.beads (rc=$src) — this store was NOT checked")
            continue
        fi
        statuses=$(printf '%s' "$st_raw" | scrub | jq -c '[ .[]? | {id, status, closed_at: (.closed_at // "")} ]' 2>/dev/null)
        [ -n "$statuses" ] || statuses='[]'
    fi
    smap=$(printf '%s' "$statuses" | jq -c 'map({key: .id, value: .}) | from_entries' 2>/dev/null)
    [ -n "$smap" ] || smap='{}'

    for cid in "${cand_ids[@]}"; do
        utargets="${until_of[$cid]}"; blockers="${blocks_of[$cid]}"
        # Decide per candidate in jq: an until target or blocks blocker missing from
        # the status map is unresolved (NOT checked, fail closed); every until target
        # must be closed and no `blocks` blocker still open for a disposition to be
        # owed, and the owed-since is the latest until-target close.
        decision=$(jq -rn --argjson m "$smap" --arg u "$utargets" --arg b "$blockers" '
            ($u | split(",") | map(select(length > 0))) as $us
            | (if $b == "" then [] else ($b | split(",") | map(select(length > 0))) end) as $bs
            | ([ ($us + $bs)[] | select($m[.] == null) ]) as $missing
            | if ($missing | length) > 0 then "unchecked\t\($missing | join(" "))"
              else
                ([ $us[] | select($m[.].status != "closed") ] | length) as $open_u
                | ([ $bs[] | select($m[.].status != "closed") ] | length) as $open_b
                | ([ $us[] | $m[.].closed_at | select(. != "") ] | max) as $latest
                | "ready\t\($open_u)\t\($open_b)\t\($latest // "")"
              end' 2>/dev/null)
        if [ -z "$decision" ]; then
            warnings+=("$label bead $cid: could not evaluate its until/blocker statuses in $rig_path/.beads — NOT checked")
            continue
        fi
        kind=$(printf '%s' "$decision" | cut -f1)
        if [ "$kind" = "unchecked" ]; then
            miss=$(printf '%s' "$decision" | cut -f2)
            warnings+=("$label bead $cid: could not resolve its until target(s)/blocker(s) [$miss] in $rig_path/.beads — NOT checked")
            continue
        fi
        open_u=$(printf '%s' "$decision" | cut -f2)
        open_b=$(printf '%s' "$decision" | cut -f3)
        latest=$(printf '%s' "$decision" | cut -f4)
        [ "$open_u" -eq 0 ] || continue   # still waiting on an until target to close: correct
        [ "$open_b" -eq 0 ] || continue   # held by its own open `blocks` blocker: correctly waiting, not a disposition
        since_epoch=$(iso_to_epoch "$latest")
        # Cannot bound the age: skip rather than cry wolf — the next sweep sees a
        # readable timestamp, and a real stall persists to be caught then.
        [ -n "$since_epoch" ] || continue
        age=$(( now - since_epoch ))
        if [ "$age" -ge "$OWED_WINDOW_SECONDS" ]; then
            findings+=("$label bead $cid: its \`until\` resolved-by target(s) [$utargets] have been closed for ${age}s (> ${OWED_WINDOW_SECONDS}s), but it has not been disposed. The deferred-dispatch reconcile pass disposes a resolved \`until\` bead within its 2m cadence, so a disposition owed this long means that order is not firing (check-cadence-live/I10) or the close is stuck — commonly an open visit on $cid holds it (conclude the visit), or the resolve-by edge is no longer wanted (remove it: gc bd dep remove $cid <target>)")
        fi
    done
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every store was scanned — what follows is partial, and a store skipped for time is not a store that passed")
fi
if [ "${#findings[@]}" -ne 0 ] || [ "${#warnings[@]}" -ne 0 ]; then
    if [ "${#findings[@]}" -ne 0 ]; then
        echo "resolved-by dispositions owed but not firing: ${#findings[@]} finding(s)"
        detail "${findings[@]}"
        detail ${warnings[@]+"${warnings[@]}"}
    else
        echo "until-resolved-owed check ran partially"
        detail "${warnings[@]}"
    fi
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every resolved-by (\`until\`) bead is waiting on its target, held by its own blocker, or disposed within cadence"
detail ${notes[@]+"${notes[@]}"}
exit 0
