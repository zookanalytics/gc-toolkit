#!/usr/bin/env bash
# doctor/check-armed-dispatch-owed — an owed deferred dispatch is firing or
# surfaced. A bead armed with gc.dispatch_when_ready is slung by the
# deferred-dispatch reconcile order (orders/deferred-dispatch.toml, every 2m)
# once bd would let it dispatch. `arm` refuses a non-open bead and reconcile
# retires a closed or already-delivered one, so a healthy arm is short-lived:
# it waits on its own `blocks` blockers, then dispatches within a cadence of
# the last one closing.
#
# Two ways a dispatch stops firing SILENTLY, neither caught elsewhere:
#   * OWED-BUT-NOT-FIRING — the bead is open, its own `blocks` edges have all
#     closed, and it is not mid-dispatch, yet it has stayed armed well past the
#     reconcile cadence. Either the order is not running (check-cadence-live/I10
#     is the direct cause there, but a single owed arm makes the effect concrete)
#     or the dispatch is stuck. The is_blocked flag cascades DOWN parent-child
#     edges, so an armed epic child whose own blockers have closed is held out of
#     `bd list --ready` by its container's hold and appears in `bd blocked` under
#     the ANCESTOR's id, not its own — which is why check-blocked-work-armed
#     (unarmed blocked work, keyed on the bead's own blocked state) cannot see it.
#   * STRANDED — the bead is armed at a non-open status, which `bd list --ready`
#     never answers, so no blocker closing will ever dispatch it (a bead armed
#     while open, then held). reconcile prints this to its own log every pass, but
#     nothing surfaces it to a person.
#
# A capped arm (gc.dispatch_when_ready_fail_count at its cap) is NOT flagged: the
# reconcile pass already escalates it, so it is not silent.
#
# The remedy the finding names is a look at `deferred-dispatch.sh list` (which
# marks each arm waiting / dispatchable / stranded) and, if the dispatch is no
# longer wanted, `deferred-dispatch.sh disarm`.
#
# Read-only. Exit 0=OK 1=Warning. stdout: first line = message, then
# "  - detail" lines. Warn-only. An UNREADABLE probe warns (1), never passes —
# an unread store is not a clean one.

set -u

# A dispatch owed longer than this has missed multiple reconcile passes. Mirrors
# check-cadence-live's I10 floor, max(3×interval, 15m): the deferred-dispatch
# order runs every 2m, so 900s is more than seven passes — long past any normal
# window between a blocker closing and the next reconcile slinging.
OWED_WINDOW_SECONDS=900

K_ARM="gc.dispatch_when_ready"
K_SLUNG="gc.dispatch_when_ready_slung"
K_ARMED_AT="gc.dispatch_when_ready_armed_at"
K_FAILS="gc.dispatch_when_ready_fail_count"

# The retry cap, read exactly as deferred-dispatch.sh reads it (same env
# override, same non-numeric fallback): once an arm's sling failures reach it,
# the reconcile pass files a visit through escalate.sh and stops re-slinging, so
# a capped arm is already surfaced to a person — not a silent stall to re-report.
MAX_SLING_FAILURES="${GC_MAX_DISPATCH_SLING_FAILURES:-3}"
case "$MAX_SLING_FAILURES" in ''|*[!0-9]*) MAX_SLING_FAILURES=3 ;; esac

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

# Captured stderr from the batch dependency read below. bd drops an id it cannot
# resolve with a "(skipped)" warning on this stream and rc=0, so the file's
# contents are how we tell a complete read from one that missed a candidate.
dep_stderr=$(mktemp "${TMPDIR:-/tmp}/gctk-armed-dispatch-deperr.XXXXXX" 2>/dev/null) || dep_stderr="${TMPDIR:-/tmp}/gctk-armed-dispatch-deperr.$$"
trap 'rm -f "$dep_stderr"' EXIT

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)] | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether owed deferred dispatches are firing"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

now=$(now_epoch)
declare -A armed_at_of=()
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    # A suspended rig's store is cold; querying it would auto-start an orphan
    # Dolt server, so it is skipped the way the sibling store checks skip it.
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    # Every armed bead in this store, all statuses (a stranded arm is non-open).
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --has-metadata-key "$K_ARM" --all --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
        warnings+=("$label: could not list armed beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    # Classify every armed bead from this one listing. A stranded arm (armed at a
    # non-open status) is a finding on its own; the exemptions — closed, delivered
    # (merge_result), mid-dispatch (a slung marker), capped (the reconcile pass has
    # already escalated it), assigned (reconcile will not sling over a holder) —
    # need no further read. deferred-dispatch.sh's `list` classifies CAPPED ahead
    # of stranded and dispatchable, so the cap test precedes the status test here
    # too. Only an open, unassigned, live arm is a CANDIDATE whose own blockers
    # decide whether a dispatch is owed.
    classified=$(printf '%s' "$raw" | scrub | jq -r \
        --arg slung "$K_SLUNG" --arg armed_at "$K_ARMED_AT" --arg fails "$K_FAILS" \
        --argjson cap "$MAX_SLING_FAILURES" '
        .[]? | . as $b | ($b.metadata // {}) as $m
        | ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $id
        | (($b.status // "") | tostring) as $st
        | (($b.assignee // "") | tostring | . != "") as $assigned
        | (($m[$slung] // "") | tostring | . != "") as $slung_set
        | (($m["merge_result"] // "") | tostring | . != "") as $mr_set
        | (($m[$armed_at] // "") | tostring) as $armed_when
        | (($m[$fails] // "") | tostring) as $fails_raw
        | (if ($fails_raw | test("^[0-9]+$")) then ($fails_raw | tonumber) else 0 end) as $fails_n
        | if   $st == "closed"  then empty
          elif $mr_set          then empty
          elif $slung_set       then empty
          elif $fails_n >= $cap then empty
          elif $st != "open"    then "stranded\t\($id)\t\($st)"
          elif $assigned        then empty
          else                       "candidate\t\($id)\t\($armed_when)"
          end' 2>/dev/null) || {
        warnings+=("$label: could not evaluate armed beads in $rig_path/.beads — this store was NOT checked")
        continue
    }
    [ -n "$classified" ] || continue

    # A stranded arm is a finding now; a candidate is collected for the bulk dep
    # read below, keeping its armed_at as the fallback owed-since.
    cand_ids=(); armed_at_of=()
    while IFS=$'\t' read -r kind cid f3; do
        [ -n "$cid" ] || continue
        case "$kind" in
            stranded)   # f3 is the stranding status
                findings+=("$label bead $cid: armed for dispatch at status=$f3, which \`bd list --ready\` never answers — no blocker closing can dispatch it. Clear the hold or disarm: deferred-dispatch.sh disarm $cid") ;;
            candidate)  # f3 is armed_at, the fallback owed-since
                cand_ids+=("$cid"); armed_at_of["$cid"]="$f3" ;;
        esac
    done <<< "$classified"
    [ "${#cand_ids[@]}" -gt 0 ] || continue

    # ONE dependency read for the whole candidate set. `bd dep list` takes many
    # ids in a single call, so the store costs one query instead of one per
    # candidate — the per-bead call summed past the doctor budget at scale. The
    # default `down` direction makes each edge candidate blocked-by blocker; the
    # extraction below reads that off whichever shape bd returns for the id count.
    edges_raw=$(run_bounded gc bd dep list "${cand_ids[@]}" --db "$rig_path/.beads" --json 2>"$dep_stderr"); erc=$?
    if [ "$erc" -ne 0 ] || ! printf '%s' "$edges_raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
        warnings+=("$label: could not batch-read dependency edges for ${#cand_ids[@]} armed bead(s) in $rig_path/.beads (rc=$erc) — this store was NOT checked")
        continue
    fi
    # bd resolves each requested id independently: one it cannot find is DROPPED
    # from the array with rc=0 and a per-id "(skipped)" warning on stderr — it
    # does not poison the batch. A dropped candidate would reach the join below
    # with no edges, indistinguishable from a candidate that genuinely has no
    # blockers, so an old armed_at would read as a firm owed finding instead of
    # "NOT checked". A read that resolves every requested id is silent (under
    # --db there is no rig-resolution preface), so any stderr means at least one
    # candidate's blockers went unread and the edge set is incomplete — degrade
    # the whole store to not-checked, as the sibling read failures above do.
    if [ -s "$dep_stderr" ]; then
        warnings+=("$label: batch dependency read did not resolve every one of ${#cand_ids[@]} armed bead(s) in $rig_path/.beads (\`bd dep list\` warned: $(tr '[:cntrl:]' ' ' < "$dep_stderr")) — this store was NOT checked")
        continue
    fi
    # `bd dep list` returns one of two shapes, and the join below reads only the
    # first: two or more ids give a flat edge array ({issue_id, depends_on_id,
    # type}), a lone id gives the annotated dependency beads instead ({id,
    # dependency_type}, the subject implicit). A store with a single candidate —
    # the common case — hits the single-id shape, so both are normalized to
    # {issue_id, depends_on_id} here. Reading the single-id beads with the flat
    # selector drops every edge, and a candidate still waiting on an open blocker
    # then reads as zero-blocker and owed — the same false finding the stderr
    # guard above prevents for a dropped id. A non-empty result in neither shape
    # is an unread probe: fail closed like the sibling reads.
    edges_scrubbed=$(printf '%s' "$edges_raw" | scrub)
    shape=$(printf '%s' "$edges_scrubbed" | jq -r '
        if   length == 0                      then "empty"
        elif all(.[]; has("issue_id"))        then "flat"
        elif all(.[]; has("dependency_type")) then "beads"
        else                                       "unknown" end' 2>/dev/null)
    case "$shape" in
        empty|flat) edges=$(printf '%s' "$edges_scrubbed" | jq -c '[ .[]? | select(.type == "blocks") | {issue_id, depends_on_id} ]' 2>/dev/null) ;;
        beads)      edges=$(printf '%s' "$edges_scrubbed" | jq -c --arg only "${cand_ids[0]}" '[ .[]? | select(.dependency_type == "blocks") | {issue_id: $only, depends_on_id: .id} ]' 2>/dev/null) ;;
        *)          warnings+=("$label: could not recognize the \`bd dep list\` output shape for ${#cand_ids[@]} armed bead(s) in $rig_path/.beads — this store was NOT checked"); continue ;;
    esac
    [ -n "$edges" ] || edges='[]'

    # Resolve the blockers' statuses in one more listing: every distinct blocker
    # id, read with --all so closed blockers (the dispatch-releasing ones) are
    # included and --brief to drop free-form text the join does not read. A blocks
    # edge can name a blocker of ANY type, and a gate/infra/template blocker is
    # common (a graduation gate blocking a convoy child, for one); bd list hides
    # those classes unless asked, and a hidden blocker would drop from the result
    # and read as unresolved, so all three include flags are passed. --id silently
    # drops an id with no row, so a blocker still absent from the result is treated
    # as unresolved below (its candidate is NOT checked), never as closed — an
    # unread blocker must not read as a released one.
    blocker_ids=$(printf '%s' "$edges" | jq -r '[ .[].depends_on_id ] | unique | join(",")' 2>/dev/null)
    blockers='[]'
    if [ -n "$blocker_ids" ]; then
        blk_raw=$(run_bounded gc bd list --db "$rig_path/.beads" --id "$blocker_ids" --all --include-gates --include-infra --include-templates --brief --json --limit 0 2>/dev/null); brc=$?
        if [ "$brc" -ne 0 ] || ! printf '%s' "$blk_raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
            warnings+=("$label: could not read blocker statuses for ${#cand_ids[@]} armed bead(s) in $rig_path/.beads (rc=$brc) — this store was NOT checked")
            continue
        fi
        blockers=$(printf '%s' "$blk_raw" | scrub | jq -c '[ .[]? | {id, status, closed_at: (.closed_at // "")} ]' 2>/dev/null)
        [ -n "$blockers" ] || blockers='[]'
    fi

    # Join per candidate: count its still-open blockers, and take the latest
    # blocker close (ISO-8601 UTC sorts chronologically) as the owed-since. jq
    # does the set join; the age arithmetic below stays in bash, so the dual
    # GNU/BSD date parse and the "unparseable timestamp -> skip" fallback are
    # unchanged from the per-bead version. jq emits one line per candidate, so an
    # empty result with candidates present is a jq failure — fail closed.
    cand_json=$(printf '%s\n' "${cand_ids[@]}" | jq -R . | jq -sc .)
    joined=$(jq -rn --argjson edges "$edges" --argjson blockers "$blockers" --argjson cands "$cand_json" '
        ($blockers | map({key: .id, value: .}) | from_entries) as $bmap
        | $cands[] | . as $cid
        | [ $edges[] | select(.issue_id == $cid) | .depends_on_id ] as $blks
        | [ $blks[] | select($bmap[.] == null) ] as $missing
        | if ($missing | length) > 0 then "unchecked\t\($cid)\t\($missing | join(" "))"
          else
            ([ $blks[] | select($bmap[.].status != "closed") ] | length) as $open_blk
            | ([ $blks[] | $bmap[.].closed_at | select(. != "") ] | max) as $latest
            | "ready\t\($cid)\t\($open_blk)\t\($latest // "")"
          end' 2>/dev/null)
    if [ -z "$joined" ]; then
        warnings+=("$label: could not evaluate blocker join for ${#cand_ids[@]} armed bead(s) in $rig_path/.beads — this store was NOT checked")
        continue
    fi

    while IFS=$'\t' read -r kind cid f3 f4; do
        [ -n "$cid" ] || continue
        if [ "$kind" = "unchecked" ]; then            # f3 lists the unreadable blocker ids
            warnings+=("$label bead $cid: could not resolve its blocker(s) [$f3] in $rig_path/.beads — NOT checked")
            continue
        fi
        # kind == ready: f3 = still-open blocker count, f4 = latest blocker close
        [ "$f3" -eq 0 ] || continue                   # still waiting on its own open blocker: correct
        since="$f4"; [ -n "$since" ] || since="${armed_at_of[$cid]}"
        since_epoch=$(iso_to_epoch "$since")
        # Cannot bound the age: skip rather than cry wolf — the next sweep sees a
        # readable timestamp, and a real stall persists to be caught then.
        [ -n "$since_epoch" ] || continue
        age=$(( now - since_epoch ))
        if [ "$age" -ge "$OWED_WINDOW_SECONDS" ]; then
            findings+=("$label bead $cid: armed and its own \`blocks\` edges have all been closed for ${age}s (> ${OWED_WINDOW_SECONDS}s), but it has not dispatched. The deferred-dispatch reconcile order slings a ready arm within its 2m cadence, so a dispatch owed this long means that order is not firing (check-cadence-live/I10) or the dispatch is stuck. Look: deferred-dispatch.sh list; disarm if no longer wanted: deferred-dispatch.sh disarm $cid")
        fi
    done <<< "$joined"
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every store was scanned — what follows is partial, and a store skipped for time is not a store that passed")
fi
if [ "${#findings[@]}" -ne 0 ] || [ "${#warnings[@]}" -ne 0 ]; then
    if [ "${#findings[@]}" -ne 0 ]; then
        echo "armed dispatches owed but not firing: ${#findings[@]} finding(s)"
        detail "${findings[@]}"
        detail ${warnings[@]+"${warnings[@]}"}
    else
        echo "armed-dispatch check ran partially"
        detail "${warnings[@]}"
    fi
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every armed deferred dispatch is waiting on its own blocker, mid-dispatch, or firing within cadence"
detail ${notes[@]+"${notes[@]}"}
exit 0
