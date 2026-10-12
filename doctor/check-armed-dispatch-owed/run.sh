#!/usr/bin/env bash
# doctor/check-armed-dispatch-owed — an owed deferred dispatch is firing or
# surfaced. A bead armed with gc.dispatch_when_ready is slung by the
# deferred-dispatch reconcile order (orders/deferred-dispatch.toml, a 5m cooldown)
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
#
# Cost. The whole check shares one doctor budget, and on a loaded host every gc
# probe takes seconds however little it reads. So the check overlaps its probes
# instead of chaining them. The rig and order registries are read at once, and
# each store is then scanned by its own background job, so the check costs the
# rig list plus its slowest store rather than the sum of every store. A store's
# scan makes at most two reads, one after the other: its armed beads, then the
# blockers their `blocks` edges name. The armed listing carries each bead's own
# dependency edges, so no store makes a dependency read. A read lands in a file,
# since a background job cannot hand its parent a variable.

set -u

# The owed window is the deferred-dispatch order's cadence window, from the one
# definition check-cadence-live (I10) also reads: max(3×interval, one trip of
# the order dispatch rotation). It is computed below, once the probes have their
# budget. Unsourceable, no arm's wait can be judged, so the check warns.
# shellcheck source=../../assets/scripts/order-cadence.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/order-cadence.sh" || {
    echo "cannot determine whether owed deferred dispatches are firing"
    printf '  - %s\n' "assets/scripts/order-cadence.sh could not be sourced from this pack, so the window an owed arm is judged by cannot be computed."
    exit 1
}

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

# The scratch every probe reads into. The descriptor held open on a file inside
# it keeps the tree held for the whole run, because the host's scratch reaper
# removes any gctk-* tree that no process holds open.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-armed-dispatch-owed.XXXXXX" 2>/dev/null) || WORK=""
trap '[ -z "$WORK" ] || rm -rf "$WORK"' EXIT
if [ -z "$WORK" ] || ! { exec 9>"$WORK/.hold"; } 2>/dev/null; then
    echo "cannot determine whether owed deferred dispatches are firing"
    detail "could not create a scratch directory under ${TMPDIR:-/tmp}, which every probe reads into; no store was checked."
    exit 1
fi
# read_to <file> <probe...> runs one bounded probe with its stdout scrubbed into
# <file>, and returns the probe's own exit status.
read_to() {
    local f="$1"; shift
    run_bounded "$@" 2>/dev/null | scrub >"$f"
    return "${PIPESTATUS[0]}"
}
# one_array <file> succeeds when <file> holds exactly one JSON array. Whitespace,
# an error object or two documents is an unread probe, never an empty answer.
one_array() { jq -e -s 'length == 1 and (.[0] | type) == "array"' "$1" >/dev/null 2>&1; }

# The rig and order registries are read at once, in the background. The store
# scans wait only on the rig list; the order registry is needed only once their
# reports are judged.
read_to "$WORK/rigs.json" gc rig list --json </dev/null >/dev/null 2>&1 & rigs_pid=$!
read_to "$WORK/orders.json" gc order list --json </dev/null >/dev/null 2>&1 & orders_pid=$!

wait "$rigs_pid"; rigs_rc=$?
scopes=$(jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)] | join("\u001f")' "$WORK/rigs.json" 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether owed deferred dispatches are firing"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

# One store's scan. A stranded arm goes to findings, and a store or bead it could
# not check goes to warnings, each in the words the report prints. A candidate
# whose own blockers have all closed goes to owed as "<id>\037<seconds since>",
# and the report judges it against the owed window. The store's reads land in
# files named from the prefix $3.
scan_store() {
    local rig_name="$1" rig_path="$2"
    local label="${rig_name:-<city>}" listing="$3.armed.json" blk_file="$3.blockers.json"
    local rc brc classified kind cid f3 f4 cand_json rows blocker_ids blockers joined since since_epoch
    local -a cand_ids=()
    local -A armed_at_of=()
    # Every armed bead in this store, all statuses (a stranded arm is non-open).
    # --brief omits the free text and keeps the status, assignee, metadata and
    # dependency edges the scan reads.
    read_to "$listing" gc bd list --db "$rig_path/.beads" --has-metadata-key "$K_ARM" --all --json --limit 0 --brief; rc=$?
    if [ "$rc" -ne 0 ] || ! one_array "$listing"; then
        warnings+=("$label: could not list armed beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        return
    fi
    # Classify every armed bead from this one listing. A stranded arm (armed at a
    # non-open status) is a finding on its own; the exemptions — closed, delivered
    # (merge_result), mid-dispatch (a slung marker), capped (the reconcile pass has
    # already escalated it), assigned (reconcile will not sling over a holder) —
    # need no further read. deferred-dispatch.sh's `list` classifies CAPPED ahead
    # of stranded and dispatchable, so the cap test precedes the status test here
    # too. Only an open, unassigned, live arm is a CANDIDATE whose own blockers
    # decide whether a dispatch is owed.
    classified=$(jq -r \
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
          end' "$listing" 2>/dev/null) || {
        warnings+=("$label: could not evaluate armed beads in $rig_path/.beads — this store was NOT checked")
        return
    }
    [ -n "$classified" ] || return

    # A stranded arm is a finding now; a candidate is collected for the blocker
    # read below, keeping its armed_at as the fallback owed-since.
    while IFS=$'\t' read -r kind cid f3; do
        [ -n "$cid" ] || continue
        case "$kind" in
            stranded)   # f3 is the stranding status
                findings+=("$label bead $cid: armed for dispatch at status=$f3, which \`bd list --ready\` never answers — no blocker closing can dispatch it. Clear the hold or disarm: deferred-dispatch.sh disarm $cid") ;;
            candidate)  # f3 is armed_at, the fallback owed-since
                cand_ids+=("$cid"); armed_at_of["$cid"]="$f3" ;;
        esac
    done <<< "$classified"
    [ "${#cand_ids[@]}" -gt 0 ] || return

    # A candidate's own `blocks` blockers come from its row in the listing:
    # `bd list` carries every dependency edge of each bead it lists, as the
    # {issue_id, depends_on_id, type} records a batch `bd dep list` returns, so
    # the store makes no dependency read. The row also counts its `blocks` edges
    # (dependency_count) apart from that list. A row that names fewer `blocks`
    # blockers than it counts, or that carries no count, was not read in full,
    # and its candidate is NOT checked: judged on the blockers it does name, a
    # candidate still waiting on an open one would read as owed.
    cand_json=$(printf '%s\n' "${cand_ids[@]}" | jq -R . | jq -sc .)
    rows=$(jq -c --argjson c "$cand_json" '[ .[]?
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
        | select($c | index($id))
        | [ (.dependencies // [])[]? | objects | select(.type == "blocks")
            | ((.depends_on_id // "") | tostring) | select(. != "") ] as $blks
        | {id: $id, blocks: $blks, named: ($blks | length),
           counted: (.dependency_count | if type == "number" then tostring else "none" end),
           complete: ((.dependency_count | type) == "number" and .dependency_count == ($blks | length))} ]' "$listing" 2>/dev/null)
    if [ -z "$rows" ]; then
        warnings+=("$label: could not evaluate blocker join for ${#cand_ids[@]} armed bead(s) in $rig_path/.beads — this store was NOT checked")
        return
    fi

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
    blocker_ids=$(printf '%s' "$rows" | jq -r '[ .[] | select(.complete) | .blocks[] ] | unique | join(",")' 2>/dev/null)
    blockers='[]'
    if [ -n "$blocker_ids" ]; then
        read_to "$blk_file" gc bd list --db "$rig_path/.beads" --id "$blocker_ids" --all --include-gates --include-infra --include-templates --brief --json --limit 0; brc=$?
        if [ "$brc" -ne 0 ] || ! one_array "$blk_file"; then
            warnings+=("$label: could not read blocker statuses for ${#cand_ids[@]} armed bead(s) in $rig_path/.beads (rc=$brc) — this store was NOT checked")
            return
        fi
        blockers=$(jq -c '[ .[]? | {id, status, closed_at: (.closed_at // "")} ]' "$blk_file" 2>/dev/null)
        [ -n "$blockers" ] || blockers='[]'
    fi

    # Join per candidate: count its still-open blockers, and take the latest
    # blocker close (ISO-8601 UTC sorts chronologically) as the owed-since. jq
    # does the set join; the age arithmetic below stays in bash, so the dual
    # GNU/BSD date parse and the "unparseable timestamp -> skip" fallback are
    # unchanged from the per-bead version. jq emits one line per candidate, so an
    # empty result with candidates present is a jq failure — fail closed.
    joined=$(jq -rn --argjson rows "$rows" --argjson blockers "$blockers" '
        ($blockers | map({key: .id, value: .}) | from_entries) as $bmap
        | $rows[] | .id as $cid
        | if (.complete | not) then "partial\t\($cid)\t\(.named)\t\(.counted)"
          else
            .blocks as $blks
            | [ $blks[] | select($bmap[.] == null) ] as $missing
            | if ($missing | length) > 0 then "unchecked\t\($cid)\t\($missing | join(" "))"
              else
                ([ $blks[] | select($bmap[.].status != "closed") ] | length) as $open_blk
                | ([ $blks[] | $bmap[.].closed_at | select(. != "") ] | max) as $latest
                | "ready\t\($cid)\t\($open_blk)\t\($latest // "")"
              end
          end' 2>/dev/null)
    if [ -z "$joined" ]; then
        warnings+=("$label: could not evaluate blocker join for ${#cand_ids[@]} armed bead(s) in $rig_path/.beads — this store was NOT checked")
        return
    fi

    while IFS=$'\t' read -r kind cid f3 f4; do
        [ -n "$cid" ] || continue
        case "$kind" in
            partial)    # f3 = the blockers its row names, f4 = the `blocks` edges it counts
                warnings+=("$label bead $cid: its row in the listing of $rig_path/.beads names $f3 \`blocks\` blocker(s) but counts $f4, so its blockers were not all read — NOT checked")
                continue ;;
            unchecked)  # f3 lists the unreadable blocker ids
                warnings+=("$label bead $cid: could not resolve its blocker(s) [$f3] in $rig_path/.beads — NOT checked")
                continue ;;
        esac
        # kind == ready: f3 = still-open blocker count, f4 = latest blocker close
        [ "$f3" -eq 0 ] || continue                   # still waiting on its own open blocker: correct
        since="$f4"; [ -n "$since" ] || since="${armed_at_of[$cid]}"
        since_epoch=$(iso_to_epoch "$since")
        # Cannot bound the age: skip rather than cry wolf — the next sweep sees a
        # readable timestamp, and a real stall persists to be caught then.
        [ -n "$since_epoch" ] || continue
        owed+=("$cid"$'\037'"$(( now - since_epoch ))")
    done <<< "$joined"
}

# One store's scan, run as a background job. It reports through "$3.msg":
# NUL-terminated records, each an F (a finding), a W (a warning) or an A (an
# owed entry) followed by its text, each kind in the order the scan found it.
# The file appears only once the scan has finished, so a store with no .msg was
# not checked.
scan_job() {
    findings=(); warnings=(); owed=()
    scan_store "$@"
    local m
    { for m in ${findings[@]+"${findings[@]}"}; do printf 'F%s\0' "$m"; done
      for m in ${warnings[@]+"${warnings[@]}"}; do printf 'W%s\0' "$m"; done
      for m in ${owed[@]+"${owed[@]}"}; do printf 'A%s\0' "$m"; done
    } >"$3.part" && mv "$3.part" "$3.msg"
}

# Every unsuspended store's scan starts here, and they all run at once. A
# suspended rig's store is cold; querying it would auto-start an orphan Dolt
# server, so it is skipped the way the sibling store checks skip it.
now=$(now_epoch)
scan_pids=(); n=0
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    n=$((n + 1))
    [ "$suspended" = "true" ] && continue
    scan_job "$rig_name" "$rig_path" "$WORK/$n" </dev/null >/dev/null 2>&1 &
    scan_pids+=("$!")
done <<< "$scopes"

# A ready arm is slung on the deferred-dispatch order's next pass, so an arm
# that has waited longer than that order's cadence window has waited through a
# gap I10 would call a stopped order. The interval is the one this pack declares
# for the order, and the floor comes from the live registry and the city's
# dispatch budget.
city_root="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
dd_secs=$(cadence_order_interval "${GC_PACK_DIR:-.}/orders/deferred-dispatch.toml")
wait "$orders_pid"
orders_json=$(cat "$WORK/orders.json" 2>/dev/null)
if [ -n "$(cadence_clock_registrations "$orders_json")" ]; then
    owed_floor=$(cadence_floor "$orders_json" "${city_root:+$city_root/city.toml}")
else
    owed_floor="$CADENCE_FLOOR_MIN"
    notes+=("the order registry (\`gc order list --json\`) did not read, so the owed window uses the ${CADENCE_FLOOR_MIN}s minimum floor, not one trip of the dispatch rotation")
fi
OWED_WINDOW_SECONDS=$(cadence_window "${dd_secs:-0}" "$owed_floor")

for pid in ${scan_pids[@]+"${scan_pids[@]}"}; do wait "$pid"; done

# The scans' reports, merged in rig order however the jobs interleaved, so one
# state of the stores always produces the same report. An owed entry is a
# finding once its wait has reached the window.
n=0
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    n=$((n + 1))
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    if [ ! -f "$WORK/$n.msg" ]; then
        warnings+=("$label: the scan of $rig_path/.beads ended without reporting — this store was NOT checked")
        continue
    fi
    while IFS= read -r -d '' rec; do
        case "$rec" in
            F*) findings+=("${rec#F}") ;;
            W*) warnings+=("${rec#W}") ;;
            A*) IFS=$'\037' read -r cid age <<< "${rec#A}"
                [ "$age" -ge "$OWED_WINDOW_SECONDS" ] || continue
                findings+=("$label bead $cid: armed and its own \`blocks\` edges have all been closed for ${age}s (> ${OWED_WINDOW_SECONDS}s), but it has not dispatched. The deferred-dispatch reconcile order slings a ready arm on its next pass, and ${OWED_WINDOW_SECONDS}s is that order's cadence window, so a dispatch owed this long means that order is not firing (check-cadence-live/I10) or the dispatch is stuck. Look: deferred-dispatch.sh list; disarm if no longer wanted: deferred-dispatch.sh disarm $cid") ;;
        esac
    done <"$WORK/$n.msg"
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
