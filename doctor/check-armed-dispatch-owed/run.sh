#!/usr/bin/env bash
# doctor/check-armed-dispatch-owed — an owed deferred dispatch is firing or
# surfaced. A bead armed with gc.dispatch_when_ready is slung by the
# deferred-dispatch reconcile order (orders/deferred-dispatch.toml, a 5m cooldown)
# once nothing holds it. `arm` refuses a non-open bead and reconcile retires a
# closed or already-delivered one, so a healthy arm is short-lived: it waits
# while something holds it, then dispatches within a cadence of being armed or
# of the last hold releasing, whichever is later.
#
# Two ways a dispatch stops firing SILENTLY, neither caught elsewhere:
#   * OWED-BUT-NOT-FIRING — the bead is open, nothing holds it, and it is not
#     mid-dispatch, yet it has stayed armed well past the reconcile cadence.
#     Either the order is not running (check-cadence-live/I10 is the direct cause
#     there, but a single owed arm makes the effect concrete) or the dispatch is
#     stuck. A hold is the one reconcile slings on, assets/scripts/hold-lib.sh's:
#     an open `blocks` blocker on the bead or on a parent-child ancestor, a
#     human gate on an ancestor aside. So an arm a park holds, by an edge of its
#     own or its epic's, is not owed: a park leaves the arm intact and its status
#     open, and the arm fires when the park releases. A bead in flight (a branch,
#     a merge_result or a rejection_reason) is held by its own blockers alone, so
#     its arm is owed under a parked epic, where reconcile slings it.
#     check-blocked-work-armed asks blocked work for a dispatch path and nothing
#     more, and an arm is one, so an arm that never fires is this check's to see.
#     `bd blocked` lists a bead its parent's hold reaches under the bead's own
#     id, naming the parent as its blocker, and that check skips it for the arm
#     alone.
#   * STRANDED — the bead is armed at a non-open status, which `bd list --ready`
#     never answers, so no blocker closing will ever dispatch it (a bead armed
#     while open, then set to another status). reconcile prints this to its own
#     log every pass, but nothing surfaces it to a person. A hold does not excuse
#     it: releasing the hold would not dispatch it either.
#
# A capped arm (gc.dispatch_when_ready_fail_count at its cap) is NOT flagged: the
# reconcile pass already escalates it, so it is not silent.
#
# The remedy the finding names is a look at `deferred-dispatch.sh list` (which
# marks each arm held / dispatchable / stranded) and, if the dispatch is no
# longer wanted, `deferred-dispatch.sh disarm`.
#
# Read-only. Exit 0=OK 1=Warning. stdout: first line = message, then
# "  - detail" lines. Warn-only. An UNREADABLE probe warns (1), never passes —
# an unread store is not a clean one.
#
# Cost. The whole check shares one doctor budget, and on a loaded host every gc
# probe takes seconds however little it reads. So the check overlaps its probes
# instead of chaining them. The rig and order registries are read at once, and
# each store is then scanned by its own background job, as many at a time as
# the fan-out cap allows. While the city has no more stores than the cap, the
# check costs the rig list plus its slowest store rather than the sum of every
# store. Inside a store's scan the reads run one after the other: the armed
# listing, then the hold walk's, a generation of ancestors at a time and then
# every blocker once. The listing's rows carry each bead's own dependency edges,
# so no store makes a dependency read. A read lands in a file, since a
# background job cannot hand its parent a variable.

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
# The one definition of a hold, which reconcile also reads. Unsourceable, a held
# arm cannot be told from an owed one, so the check warns.
# shellcheck source=../../assets/scripts/hold-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/hold-lib.sh" || {
    echo "cannot determine whether owed deferred dispatches are firing"
    printf '  - %s\n' "assets/scripts/hold-lib.sh could not be sourced from this pack, so a held arm cannot be told from an owed one."
    exit 1
}

K_ARM="gc.dispatch_when_ready"
K_SLUNG="gc.dispatch_when_ready_slung"
K_ARMED_AT="gc.dispatch_when_ready_armed_at"
K_FAILS="gc.dispatch_when_ready_fail_count"

# The retry cap, read exactly as deferred-dispatch.sh reads it (same env
# override, same non-numeric fallback): once an arm's sling failures reach it,
# the reconcile pass asks a person, with a human gate through human-gate.sh or a
# conversation on a bead with open children, and stops re-slinging, so a capped
# arm is already surfaced to a person — not a silent stall to re-report.
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

# >>> doctor-parallel-reads
# A check that overlaps its probes runs each one as a background job, and a job
# cannot hand its parent a variable, so every read lands in a file under one
# scratch tree. reads_init <check> makes that tree, sets WORK to it, and removes
# it when the check exits. It holds a file in the tree open on fd 9, because the
# host's scratch reaper removes any gctk-* tree that no process holds open. It
# returns non-zero when the tree cannot be made or held, and then nothing can be
# read.
reads_init() {
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-$1.XXXXXX" 2>/dev/null) || { WORK=""; return 1; }
    trap '[ -z "$WORK" ] || rm -rf "$WORK"' EXIT
    { exec 9>"$WORK/.hold"; } 2>/dev/null
}
# read_to <file> <probe...> runs one bounded probe with its stdout scrubbed into
# <file> and its stderr in <file>.err, and returns the probe's own exit status.
# err_of <file> prints the first non-blank line of that stderr, with control
# characters stripped and cut to 200 characters, so the warning for a failed
# read names why it failed and not only its rc. Before a `gc bd` list, ready,
# search or show runs bd, gc writes a line naming the store that answers it,
# whether or not the read then fails. That line never says why a read failed,
# so err_of passes over it.
read_to() {
    local f="$1"; shift
    run_bounded "$@" 2>"$f.err" | scrub >"$f"
    return "${PIPESTATUS[0]}"
}
err_of() {
    [ -s "$1.err" ] || return 0
    tr -d '\000-\010\013-\037' <"$1.err" 2>/dev/null \
        | grep -v '^gc bd: answering from the .* store$' | grep -m1 '[^[:space:]]' | cut -c1-200
}
# fanout <command...> starts <command> as a background job once fewer than
# FANOUT_CAP of the jobs fanout started are still running, so a check scans at
# most that many stores at once however many rigs the city lists. FANOUT_PID is
# the job it started. fanout_wait <pid> waits for one of those jobs and returns
# its exit status, which the cap keeps for a job it has already waited for. The
# cap waits only for fanout's own jobs, because a bare `wait -n` also returns
# for the check's other background reads, and the count of running jobs would
# drift. When `wait -n` reports no job, the cap waits for the oldest one, so
# each wait frees a slot. GC_DOCTOR_FANOUT overrides the cap, in jobs.
FANOUT_CAP="${GC_DOCTOR_FANOUT:-8}"
case "$FANOUT_CAP" in ''|*[!0-9]*) FANOUT_CAP=8 ;; esac
[ "$FANOUT_CAP" -ge 1 ] 2>/dev/null || FANOUT_CAP=8
fanout_live=(); declare -A fanout_rc=()
fanout_reaped() {
    local p keep=()
    fanout_rc["$1"]="$2"
    for p in ${fanout_live[@]+"${fanout_live[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
    fanout_live=(${keep[@]+"${keep[@]}"})
}
fanout() {
    local pid rc
    while [ "${#fanout_live[@]}" -ge "$FANOUT_CAP" ]; do
        pid=""; wait -n -p pid "${fanout_live[@]}"; rc=$?
        if [ -z "$pid" ]; then pid="${fanout_live[0]}"; wait "$pid"; rc=$?; fi
        fanout_reaped "$pid" "$rc"
    done
    "$@" &
    FANOUT_PID=$!
    fanout_live+=("$FANOUT_PID")
}
fanout_wait() {
    local rc
    if [ -n "${fanout_rc[$1]+set}" ]; then return "${fanout_rc[$1]}"; fi
    wait "$1"; rc=$?
    fanout_reaped "$1" "$rc"
    return "$rc"
}
# <<< doctor-parallel-reads
if ! reads_init check-armed-dispatch-owed; then
    echo "cannot determine whether owed deferred dispatches are firing"
    detail "could not create a scratch directory under ${TMPDIR:-/tmp}, which every probe reads into; no store was checked."
    exit 1
fi
# one_array <file> succeeds when <file> holds exactly one JSON array. Whitespace,
# an error object or two documents is an unread probe, never an empty answer.
one_array() { jq -e -s 'length == 1 and (.[0] | type) == "array"' "$1" >/dev/null 2>&1; }

# The hold walk's reader (hold-lib.sh): the named beads in the store being
# scanned, at every status and of every class a listing hides by default, since
# a blocker can be a gate and an ancestor can be closed. Each read lands in
# hold_file with its stderr beside it, so a walk that fails can say why. A
# store's scan sets both in its own job, so no two scans share them.
hold_db=""; hold_file=""
hold_read() {
    read_to "$hold_file" gc bd list --db "$hold_db" --id "$1" --all --include-gates --include-infra --include-templates --brief --json --limit 0 \
        && cat "$hold_file"
}

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
    rigs_err=$(err_of "$WORK/rigs.json")
    [ -n "$rigs_err" ] && detail "\`gc rig list\` stderr: $rigs_err"
    exit 1
fi

# One store's scan. A stranded arm goes to findings, and a store or bead it could
# not check goes to warnings, each in the words the report prints. A candidate
# nothing holds goes to owed as "<id>\037<seconds since>", and the report judges
# it against the owed window. The store's reads land in files named from the
# prefix $3.
scan_store() {
    local rig_name="$1" rig_path="$2"
    local label="${rig_name:-<city>}" listing="$3.armed.json"
    local rc err classified kind cid f3 cand_json hold_rows hold released unread_ids since_epoch released_epoch
    local -a cand_ids=()
    local -A armed_at_of=()
    # Every armed bead in this store, all statuses (a stranded arm is non-open).
    # --brief omits the free text and keeps the status, assignee, metadata and
    # dependency edges the scan and the hold walk read.
    read_to "$listing" gc bd list --db "$rig_path/.beads" --has-metadata-key "$K_ARM" --all --json --limit 0 --brief; rc=$?
    if [ "$rc" -ne 0 ] || ! one_array "$listing"; then
        err=$(err_of "$listing")
        warnings+=("$label: could not list armed beads in $rig_path/.beads (rc=$rc) — this store was NOT checked${err:+; \`gc bd list\` stderr: $err}")
        return
    fi
    # Classify every armed bead from this one listing. A stranded arm (armed at a
    # non-open status) is a finding on its own; the exemptions — closed, delivered
    # (merge_result), mid-dispatch (a slung marker), capped (the reconcile pass has
    # already escalated it), assigned (reconcile will not sling over a holder) —
    # need no further read. deferred-dispatch.sh's `list` classifies CAPPED ahead
    # of stranded and dispatchable, so the cap test precedes the status test here
    # too. Only an open, unassigned, live arm is a CANDIDATE whose blockers, on
    # it and on its ancestors, decide whether a dispatch is owed.
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

    # A stranded arm is a finding now; a candidate is collected for the hold walk
    # below, keeping its armed_at, the earliest its dispatch can be owed.
    while IFS=$'\t' read -r kind cid f3; do
        [ -n "$cid" ] || continue
        case "$kind" in
            stranded)   # f3 is the stranding status
                findings+=("$label bead $cid: armed for dispatch at status=$f3, which \`bd list --ready\` never answers — no blocker closing can dispatch it. Return it to open, or disarm: deferred-dispatch.sh disarm $cid") ;;
            candidate)  # f3 is armed_at
                cand_ids+=("$cid"); armed_at_of["$cid"]="$f3" ;;
        esac
    done <<< "$classified"
    [ "${#cand_ids[@]}" -gt 0 ] || return

    # A candidate is owed only when nothing holds it, by the predicate reconcile
    # slings on, and that predicate answers for the candidate's own blockers as
    # well as its ancestors'. The walk takes each candidate's own edges from its
    # row in this listing, then reads the ancestors a generation at a time and
    # every blocker once, so the store costs those few reads however many
    # candidates it holds. A candidate held by a blocker the walk read is not
    # owed. One whose only holds could not be read is NOT checked: an unread hold
    # is no released one, and no owed dispatch either.
    hold_db="$rig_path/.beads"; hold_file="$3.hold.json"
    cand_json=$(printf '%s\n' "${cand_ids[@]}" | jq -R . | jq -sc .)
    # The rows join on the unit separator, not a tab: `read` folds a run of tabs
    # into one, so an empty release time would hand the unread ids its field.
    hold_rows=""
    if jq -c --argjson c "$cand_json" '[ .[]? | select(.id as $i | $c | index($i)) ]' "$listing" > "$3.seed.json" 2>/dev/null \
       && hold_graph hold_read "$3.seed.json" "$3.graph.json"; then
        hold_rows=$(jq -r --slurpfile g "$3.graph.json" "$HOLD_JQ"'
            .[] | hold_holds($g[0]) as $h
            | [ (.id | tostring),
                (if any($h[]; .unread | not) then "held" elif ($h | length) > 0 then "unread" else "free" end),
                (hold_released_at($g[0]) // ""),
                ([ $h[] | select(.unread) | .by ] | join(" ")) ]
            | map(gsub("[[:cntrl:]]"; " ")) | join("\u001f")' "$3.seed.json" 2>/dev/null)
    fi
    if [ -z "$hold_rows" ]; then
        err=$(err_of "$hold_file")
        warnings+=("$label: could not read what holds ${#cand_ids[@]} armed bead(s) in $rig_path/.beads — they were NOT checked${err:+; \`gc bd list\` stderr: $err}")
        return
    fi

    while IFS=$'\037' read -r cid hold released unread_ids; do
        [ -n "$cid" ] || continue
        case "$hold" in
            held) continue ;;                         # a park or a prerequisite holds it: not owed
            unread) warnings+=("$label bead $cid: could not read [$unread_ids], which may hold it, in $rig_path/.beads — NOT checked"); continue ;;
        esac
        # Owed since the later of when it was armed and when the last hold on it
        # released (hold_released_at), so a hold that released before the arm
        # was recorded does not age it. An arm whose armed_at does not parse is
        # judged from the release alone.
        since_epoch=$(iso_to_epoch "${armed_at_of[$cid]}")
        released_epoch=$(iso_to_epoch "$released")
        if [ -n "$released_epoch" ] && { [ -z "$since_epoch" ] || [ "$released_epoch" -gt "$since_epoch" ]; }; then
            since_epoch="$released_epoch"
        fi
        # Cannot bound the age: skip rather than cry wolf — the next sweep sees a
        # readable timestamp, and a real stall persists to be caught then.
        [ -n "$since_epoch" ] || continue
        owed+=("$cid"$'\037'"$(( now - since_epoch ))")
    done <<< "$hold_rows"
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

# Every unsuspended store's scan starts here, as many at once as the fan-out cap
# allows. A suspended rig's store is cold; querying it would auto-start an
# orphan Dolt server, so it is skipped the way the sibling store checks skip it.
now=$(now_epoch)
scan_pids=(); n=0
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    n=$((n + 1))
    [ "$suspended" = "true" ] && continue
    fanout scan_job "$rig_name" "$rig_path" "$WORK/$n" </dev/null >/dev/null 2>&1
    scan_pids+=("$FANOUT_PID")
done <<< "$scopes"

# A ready arm is slung on the deferred-dispatch order's next pass, so an arm
# that has waited longer than that order's cadence window has waited through a
# gap I10 would call a stopped order. The interval is the one this pack declares
# for the order, and the floor comes from the live registry and the city's
# dispatch budget.
city_root="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
dd_secs=$(cadence_order_interval "${GC_PACK_DIR:-.}/orders/deferred-dispatch.toml")
wait "$orders_pid"
orders_json=$(cat "$WORK/orders.json" 2>/dev/null); orders_err=$(err_of "$WORK/orders.json")
if [ -n "$(cadence_clock_registrations "$orders_json")" ]; then
    owed_floor=$(cadence_floor "$orders_json" "${city_root:+$city_root/city.toml}")
else
    owed_floor="$CADENCE_FLOOR_MIN"
    notes+=("the order registry (\`gc order list --json\`) did not read, so the owed window uses the ${CADENCE_FLOOR_MIN}s minimum floor, not one trip of the dispatch rotation${orders_err:+; \`gc order list\` stderr: $orders_err}")
fi
OWED_WINDOW_SECONDS=$(cadence_window "${dd_secs:-0}" "$owed_floor")

for pid in ${scan_pids[@]+"${scan_pids[@]}"}; do fanout_wait "$pid"; done

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
                findings+=("$label bead $cid: armed and nothing has held it for ${age}s (> ${OWED_WINDOW_SECONDS}s), but it has not dispatched. The deferred-dispatch reconcile order slings an arm nothing holds on its next pass, and ${OWED_WINDOW_SECONDS}s is that order's cadence window, so a dispatch owed this long means that order is not firing (check-cadence-live/I10) or the dispatch is stuck. Look: deferred-dispatch.sh list; disarm if no longer wanted: deferred-dispatch.sh disarm $cid") ;;
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
echo "OK: every armed deferred dispatch is held by a blocker, mid-dispatch, or firing within cadence"
detail ${notes[@]+"${notes[@]}"}
exit 0
