#!/usr/bin/env bash
# doctor/check-po-queue-only — the po receives nothing but its queue (I16 in
# docs/component-model.md).
#
# The po (agents/po) is the operator's prioritization partner, and it owns
# little. What it receives is the queue of new work no epic holds, the beads
# carrying Gas City's hold:mayor label in any spelling Gas City reads as the
# hold, which a sitting reads from `gc beads list`. Nothing at a writer keeps
# anything else away from it: an assignment, a mail and `gc sling <po> --on
# <formula>` each reach the seat whatever its config says, and any writer can
# set a label. So this check observes the invariant after the fact, one check
# for every path that leaves a record, and a new path shows up here within one
# sweep of its first use. A delivered nudge leaves no record, so no check sees
# one.
#
# It reports four things:
#   - A bead that no hold holds and that is routed to the po (gc.routed_to) or
#     assigned to one of its addresses, at any status but closed. A run's
#     steps are beads, so a run poured to the seat, which nothing refuses, is
#     named step by step under its root. A held bead reaches no seat, because
#     Gas City serves it to no hook, pool or route-restore sweep, and the queue
#     arms below judge it. A message bead is mail, which the next arm reads.
#   - Unread mail to the po, from any sender. `gc mail inbox <po>` reads the
#     seat's mailbox under every address Gas City resolves for it, and wakes
#     nothing. No sender is exempt: Gas City's warmup mail goes to `mayor`, not
#     to this seat, and a caller with no session identity, an exec order among
#     them, sends as `human`, as the operator does.
#   - A bead in the queue that is not new work: PR-finishing work of another
#     bead (anchor_bead) or a bead with a landing state (merge_result). A branch
#     alone does not count, because a run that ended can leave one on a bead the
#     po holds again.
#   - A bead in the queue that something already sends: an arm
#     (gc.dispatch_when_ready), an assignee, or a live run that works it
#     (assets/scripts/run-lib.sh). Each is a placement that stopped before its
#     lift, or a sling made while the bead was held, and `gc-helm.sh place`
#     finishes either. An arm for the validating closer (mol-validate-close) is
#     neither: the bead waits on another bead to land and is checked then, so
#     its hold is lifted, not placed (skills/waits/SKILL.md).
#
# The po's addresses are every identity Gas City serves its work under, which
# its session.AssigneeIdentities names: the session bead's id, its runtime
# session name, its configured identity, its alias, and each alias it had
# before. The qualified name `gc agent list` gives the agent named po is its
# configured identity and its alias. `gc session list --template <po>` gives
# each open session of the seat its id and its session name, and the po's
# mailbox read gives its earlier aliases. Neither read wakes the seat. A city
# that configures no po has no seat to reach, so only the queue is judged
# there.
#
# The queue's JSON is an array from the direct read and {"beads": [...],
# "_cache_age_s": n} through the supervisor API, and the check takes both. The
# queue is each open bead of that listing on which
# dispatch_hold_spellings("hold:mayor") finds a spelling, trimmed and in any
# case, as Gas City's hold reads it. `gc beads list --label` matches a label's
# exact text, so it would leave out a bead a person labeled `Hold:Mayor`, which
# Gas City holds all the same. A queued bead lives in the rig store its id's
# prefix names. A suspended rig's store is not read, because querying it would
# auto-start an orphan Dolt server.
#
# The rig map, the agent list and the queue are read at once, and the po's
# mailbox and sessions once the agent list names it. Each store is then
# scanned by its own background job, as many at a time as the fan-out cap
# allows: the beads routed to the po, the beads assigned to it, and, where the
# store holds queued beads, its live runs.
#
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. An unreadable probe warns (1), never passes.

set -u

# Gas City's hold test and the link from a run to the bead it works, each from
# its one definition. An unsourceable one warns: without the first a held bead
# cannot be told from a bead that reaches the po, and without the second a live
# run working a queued bead cannot be found.
# shellcheck source=../../assets/scripts/dispatch-path.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/dispatch-path.sh" || {
    echo "cannot determine whether the po receives only its queue"
    printf '  - %s\n' "assets/scripts/dispatch-path.sh could not be sourced from this pack, so a held bead cannot be told from a bead that reaches the po."
    exit 1
}
# shellcheck source=../../assets/scripts/run-lib.sh
. "${GC_RUN_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/run-lib.sh}" || {
    echo "cannot determine whether the po receives only its queue"
    printf '  - %s\n' "assets/scripts/run-lib.sh could not be sourced from this pack, so a live run working a queued bead cannot be found."
    exit 1
}

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
if ! reads_init check-po-queue-only; then
    echo "cannot determine whether the po receives only its queue"
    detail "could not create a scratch directory under ${TMPDIR:-/tmp}, which every probe reads into; nothing was checked."
    exit 1
fi
# one_array <file> succeeds when <file> holds exactly one JSON array. Whitespace,
# an error object or two documents is an unread probe, never an empty answer.
one_array() { jq -e -s 'length == 1 and (.[0] | type) == "array"' "$1" >/dev/null 2>&1; }

# --- The rig map, the seat and the queue, read at once ----------------------
# rig-map.sh reads the rig map, and names on stderr why it did not.
RIG_MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/rig-map.sh"
read_to "$WORK/rigs.json" "$RIG_MAP" </dev/null >/dev/null 2>&1 & rigs_pid=$!
read_to "$WORK/agents.json" gc agent list --json </dev/null >/dev/null 2>&1 & agents_pid=$!
read_to "$WORK/queue.json" gc beads list --format=json </dev/null >/dev/null 2>&1 & queue_pid=$!

# The po: each agent whose qualified name ends in the name po, and its address
# that qualified name, which is what a route to it carries.
wait "$agents_pid"; agents_rc=$?
po_list=(); agents_ok=0
if [ "$agents_rc" -eq 0 ] && jq -e '(.agents | type) == "array"' "$WORK/agents.json" >/dev/null 2>&1; then
    agents_ok=1
    while IFS= read -r qn; do
        [ -n "$qn" ] && po_list+=("$qn")
    done <<< "$(jq -r '[ .agents[] | objects | ((.qualified_name // "") | tostring)
        | select(. != "" and (split("/") | last | split(".") | last) == "po") ] | unique | .[]' "$WORK/agents.json" 2>/dev/null)"
else
    err=$(err_of "$WORK/agents.json")
    warnings+=("could not read \`gc agent list --json\` (rc=$agents_rc), so the po's address is unknown: no store was searched for a route or an assignment to it, and its mail was NOT read${err:+; stderr: $err}")
fi
if [ "$agents_ok" = 1 ] && [ "${#po_list[@]}" -eq 0 ]; then
    notes+=("no agent named po is configured in this city, so no route, assignment or mail can reach one; only the queue was judged")
fi

# Each po's mailbox and sessions, read in the background while the rig map and
# the queue finish.
inbox_pids=(); sessions_pids=(); i=0
for qn in ${po_list[@]+"${po_list[@]}"}; do
    i=$((i + 1))
    read_to "$WORK/inbox.$i.json" gc mail inbox "$qn" --json </dev/null >/dev/null 2>&1 & inbox_pids+=("$!")
    read_to "$WORK/sessions.$i.json" gc session list --template "$qn" --json </dev/null >/dev/null 2>&1 & sessions_pids+=("$!")
done

# The stores: name, path, the prefix its bead ids carry, and whether its rig is
# suspended.
wait "$rigs_pid"; rigs_rc=$?
scopes=$(jq -r '.rigs[]? | objects | select((.path // "") != "")
    | [((.name // "") | tostring | gsub("[[:cntrl:]]"; " ")), (.path | tostring),
       ((.prefix // "") | tostring | gsub("[[:cntrl:]]"; " ")), ((.suspended // false) | tostring)]
    | join("\u001f")' "$WORK/rigs.json" 2>/dev/null)
rigs_ok=1
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    rigs_ok=0; scopes=""
    err=$(err_of "$WORK/rigs.json")
    warnings+=("\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths, so no store was searched for a route or an assignment to the po, and no run working a queued bead was read${err:+; $err}")
fi
# Each store by the prefix its ids carry. A prefix two rigs carry names neither,
# so a bead carrying it is left unplaced rather than read in the wrong store.
STORES_JSON=$(jq -c '[ .rigs[]? | objects | select((.path // "") != "" and ((.prefix // "") | tostring) != "")
        | {key: (.prefix | tostring), value: {label: ((.name // "") | tostring | gsub("[[:cntrl:]]"; " ")),
                                              db: ((.path | tostring) + "/.beads"),
                                              suspended: ((.suspended // false) == true)}} ]
    | group_by(.key) | map(select(length == 1) | .[0]) | from_entries' "$WORK/rigs.json" 2>/dev/null)
[ "$rigs_ok" = 1 ] && [ -n "$STORES_JSON" ] || STORES_JSON='{}'

# The queue, in either shape `gc beads list` prints it: the beads that carry
# hold:mayor in some spelling. An unread queue leaves no queued bead to judge,
# and says so.
wait "$queue_pid"; queue_rc=$?
if [ "$queue_rc" -ne 0 ] || ! jq -c -s "$DISPATCH_PATH_JQ"'if length != 1 then error("not one document") else .[0] end
        | if type == "array" then . elif type == "object" and (.beads | type) == "array" then .beads
          else error("neither queue shape") end
        | [ .[] | objects | select(dispatch_hold_spellings("hold:mayor") | length > 0) ]' "$WORK/queue.json" > "$WORK/queued.json" 2>/dev/null; then
    err=$(err_of "$WORK/queue.json")
    warnings+=("could not read the po's queue, \`gc beads list --format=json\` (rc=$queue_rc), so no held bead was checked${err:+; stderr: $err}")
    printf '[]' > "$WORK/queued.json"
fi

# --- The mailbox: unread mail is a finding, and its addresses are the po's ---
# The addresses an assignment to the po carries: its qualified name, the id and
# the session name of each open session of the seat, and each address its
# mailbox resolves to, the aliases it had before among them.
addrs=(${po_list[@]+"${po_list[@]}"}); i=0
for qn in ${po_list[@]+"${po_list[@]}"}; do
    i=$((i + 1)); f="$WORK/sessions.$i.json"
    wait "${sessions_pids[$((i - 1))]}"; rc=$?
    if [ "$rc" -ne 0 ] || ! jq -e '(.sessions | type) == "array"' "$f" >/dev/null 2>&1; then
        err=$(err_of "$f")
        warnings+=("could not read the po's sessions, \`gc session list --template $qn --json\` (rc=$rc), so no store was searched for an assignment to a session's runtime name${err:+; stderr: $err}")
    else
        while IFS= read -r a; do
            [ -n "$a" ] && addrs+=("$a")
        done <<< "$(jq -r '.sessions[] | objects | (.id, .session_name, .alias) | strings' "$f" 2>/dev/null)"
    fi
    f="$WORK/inbox.$i.json"
    wait "${inbox_pids[$((i - 1))]}"; rc=$?
    if [ "$rc" -ne 0 ] || ! jq -e '(.messages == null or (.messages | type) == "array")
            and ((.recipients // []) | type) == "array"' "$f" >/dev/null 2>&1; then
        err=$(err_of "$f")
        warnings+=("could not read the po's mailbox, \`gc mail inbox $qn --json\` (rc=$rc), so its unread mail was NOT checked, and no store was searched for an assignment to an alias the seat had before${err:+; stderr: $err}")
        continue
    fi
    while IFS= read -r m; do
        [ -n "$m" ] && findings+=("$m")
    done <<< "$(jq -r --arg po "$qn" '(.messages // [])[] | objects
        | ((.id // "?") | tostring) as $id | ((.from // "?") | tostring) as $from
        | "unread mail \($id) to the po (\($po)) from \($from): \"\((.subject // "") | tostring)\". The po takes no work by mail."
          + (if $from == "human" then " A sender of human is any caller with no session identity, an exec order among them, as well as the operator." else "" end)
          + " Tell the sender where its request goes, then archive the message: gc mail archive \($id)"
        | gsub("[[:cntrl:]]"; " ")' "$f" 2>/dev/null)"
    while IFS= read -r a; do
        [ -n "$a" ] && addrs+=("$a")
    done <<< "$(jq -r '(.recipients // [])[] | strings' "$f" 2>/dev/null)"
done
# One query reads every address. An address carrying a character the query
# language does not take inside quotes is left out, and named.
ASSIGNEE_EXPR=""; PO_QNS='[]'; PO_ADDRS='[]'
if [ "${#po_list[@]}" -gt 0 ]; then
    PO_QNS=$(printf '%s\n' "${po_list[@]}" | jq -R . | jq -sc 'unique')
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        case "$a" in
            *[!A-Za-z0-9._:/@+-]*) warnings+=("the po's address '$a' carries a character an assignee query cannot quote, so no store was searched for an assignment to it"); continue ;;
        esac
        ASSIGNEE_EXPR="${ASSIGNEE_EXPR:+$ASSIGNEE_EXPR OR }assignee=\"$a\""
        PO_ADDRS=$(jq -c --arg a "$a" '. + [$a] | unique' <<< "$PO_ADDRS")
    done <<< "$(printf '%s\n' "${addrs[@]}" | LC_ALL=C sort -u)"
fi

# --- One store's scan -------------------------------------------------------
# The beads in this store that reach the po: routed to one of its qualified
# names or assigned to one of its addresses, held by no hold, and not mail.
# A step or a root is grouped under its run, so a run poured to the seat is one
# finding that names each of its beads.
REACH_JQ="$RUN_JQ$DISPATCH_PATH_JQ"'
    def nonblank: (. // "") | tostring | test("[^[:space:]]");
    [ .[] | arrays | .[] | objects ] | unique_by(.id)
    | map(select(((.issue_type // "") | tostring) != "message" and (has_dispatch_hold | not)))
    | map(. as $b | (if (.metadata | type) == "object" then .metadata else {} end) as $m
        | ((.id // "?") | tostring) as $id
        | (($m["gc.routed_to"] // "") | tostring) as $rt
        | ((.assignee // "") | tostring) as $as
        | { id: $id,
            what: (if ($m["gc.step_ref"] | nonblank) then ($m["gc.step_ref"] | tostring)
                   elif run_is_root then "the root"
                   else (((.status // "") | tostring) + " " + ((.issue_type // "") | tostring)) end),
            root: (if ($m["gc.root_bead_id"] | nonblank) then ($m["gc.root_bead_id"] | tostring)
                   elif run_is_root then $id else "" end),
            how: ([ (if $rt != "" and ($qns | index($rt)) != null then "routed to " + $rt else empty end),
                    (if $as != "" and ($addrs | index($as)) != null then "assigned to " + $as else empty end) ]
                  | join(" and ")) })
    | map(select(.how != "") | map_values(gsub("[[:cntrl:]]"; " ")))
    | (map(select(.root == ""))[]
        | "B\(.id)\u001f\(.what)\u001f\(.how)"),
      (map(select(.root != "")) | group_by(.root)[]
        | "R\(.[0].root)\u001f" + (map(.id + " (" + .what + ", " + .how + ")") | join(", ")))'
# The reader run-lib.sh reads the store being scanned through.
store_db=""
store_bd() { run_bounded gc bd "$@" --db "$store_db"; }

scan_store() {
    local label="$1" db="$2" base="$3"
    local rc err qn n=0 reads=() line kind id rest what how queued runs
    store_db="$db"
    if [ "${#po_list[@]}" -gt 0 ]; then
        for qn in "${po_list[@]}"; do
            n=$((n + 1))
            read_to "$base.routed.$n.json" gc bd list --db "$db" --metadata-field "gc.routed_to=$qn" \
                --include-ephemeral --include-infra --include-gates --brief --json --limit 0; rc=$?
            if [ "$rc" -ne 0 ] || ! one_array "$base.routed.$n.json"; then
                err=$(err_of "$base.routed.$n.json")
                warnings+=("$label: could not list the beads routed to $qn in $db (rc=$rc), so this store was NOT searched for them${err:+; \`gc bd list\` stderr: $err}")
            else
                reads+=("$base.routed.$n.json")
            fi
        done
        if [ -n "$ASSIGNEE_EXPR" ]; then
            read_to "$base.assigned.json" gc bd query --db "$db" "$ASSIGNEE_EXPR" --json --limit 0; rc=$?
            if [ "$rc" -ne 0 ] || ! one_array "$base.assigned.json"; then
                err=$(err_of "$base.assigned.json")
                warnings+=("$label: could not query the beads assigned to the po in $db (rc=$rc), so this store was NOT searched for them${err:+; \`gc bd query\` stderr: $err}")
            else
                reads+=("$base.assigned.json")
            fi
        fi
        if [ "${#reads[@]}" -gt 0 ]; then
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                kind="${line:0:1}"; IFS=$'\037' read -r id rest <<< "${line:1}"
                case "$kind" in
                    R) findings+=("$label: run $id sends the po work: $rest. The po takes no work from a run, and nothing refuses \`gc sling <po> --on <formula>\`. Cancel the run, assets/scripts/run-cancel.sh --root $id --reason \"<why>\" --db $db, and send the bead it works to the agent whose work it is") ;;
                    B) IFS=$'\037' read -r what how <<< "$rest"
                       findings+=("$label bead $id ($what): $how, outside the po's queue. Route or assign it to the agent whose work it is, or hold it for the po with no assignee: gc bd set-state $id hold=mayor --reason \"<why it waits for placement>\" --db $db") ;;
                esac
            done <<< "$(jq -r -s --argjson qns "$PO_QNS" --argjson addrs "$PO_ADDRS" "$REACH_JQ" "${reads[@]}" 2>/dev/null)"
        fi
    fi
    # The queue's beads in this store, and the live runs that work them.
    queued=$(jq -r --argjson stores "$STORES_JSON" --arg db "$db" '[ .[] | ((.id // "") | tostring)
        | select((($stores[split("-")[0]] // null) | if . == null then "" else .db end) == $db) ] | join(" ")' "$WORK/queued.json" 2>/dev/null)
    [ -n "$queued" ] || return 0
    if ! runs=$(run_lib map store_bd); then
        warnings+=("$label: could not read the live runs in $db, so whether a run works queued bead(s) $queued was NOT checked")
        return 0
    fi
    while IFS= read -r line; do
        [ -n "$line" ] && findings+=("$line")
    done <<< "$(printf '%s' "$runs" | jq -r --arg q " $queued " '.[] | objects
        | ((.bead // "") | tostring) as $id
        | select(.live == true and $id != "" and ($q | contains(" " + $id + " ")))
        | "queued bead \($id) is worked by live run \((.root // "?") | tostring)\(((.formula // "") | tostring) as $f | if $f == "" then "" else " (" + $f + ")" end): it was slung while held. Finish its placement with gc-helm.sh place \($id) --under <parent> or --standalone, which lifts the hold without a second run"
        | gsub("[[:cntrl:]]"; " ")' 2>/dev/null)"
}

# One store's scan, run as a background job. It reports through "$3.msg":
# NUL-terminated records, each an F (a finding) or a W (a warning) followed by
# its text, in the order the scan found them. The file appears only once the
# scan has finished, so a store with no .msg was not checked.
scan_job() {
    findings=(); warnings=()
    scan_store "$@"
    local m
    { for m in ${findings[@]+"${findings[@]}"}; do printf 'F%s\0' "$m"; done
      for m in ${warnings[@]+"${warnings[@]}"}; do printf 'W%s\0' "$m"; done
    } >"$3.part" && mv "$3.part" "$3.msg"
}

# Every unsuspended store's scan starts here. A scan reads nothing from a store
# when no po is configured and the store holds no queued bead.
scan_pids=(); n=0
while IFS=$'\037' read -r rig_name rig_path pfx suspended; do
    [ -n "$rig_path" ] || continue
    n=$((n + 1))
    [ "$suspended" = "true" ] && continue
    fanout scan_job "${rig_name:-<city>}" "$rig_path/.beads" "$WORK/$n" </dev/null >/dev/null 2>&1
    scan_pids+=("$FANOUT_PID")
done <<< "$scopes"

# --- The queue: a held bead that is not new work, or that something sends ---
# Judged from the queue's own rows, so these need no store read.
while IFS= read -r line; do
    [ -n "$line" ] && findings+=("$line")
done <<< "$(jq -r --argjson stores "$STORES_JSON" "$DISPATCH_PATH_JQ"'
    def nonblank: (. // "") | tostring | test("[^[:space:]]");
    def arm_args: if type == "string" then (if test("[^[:space:]]") then (fromjson? // [.]) else [] end)
                  elif type == "array" then . else [] end;
    .[] | (if (.metadata | type) == "object" then .metadata else {} end) as $m
    | ((.id // "?") | tostring) as $id
    | (($stores[$id | split("-")[0]] // null) | if . == null then "" else " --db " + .db end) as $dbf
    | "gc bd update \($id)\([dispatch_hold_spellings("hold:mayor")[] | " --remove-label " + .] | add // "")\($dbf)" as $lift
    | (if ($m.anchor_bead | nonblank) then
         "queued bead \($id) carries anchor_bead=\($m.anchor_bead | tostring): it is PR-finishing work of that bead, not new work, and place refuses it. Lift its hold by removing each spelling of it the bead carries, \($lift), and correct the writer that held it"
       else empty end),
      (if ($m.merge_result | nonblank) then
         "queued bead \($id) carries a landing state, merge_result=\($m.merge_result | tostring), so it is not new work. Lift its hold by removing each spelling of it the bead carries, \($lift), and correct the writer that held it"
       else empty end),
      (if ($m["gc.dispatch_when_ready"] | nonblank) then
         (if ($m["gc.dispatch_when_ready_args"] | arm_args | any(.[]; tostring | test("(^|=)mol-validate-close$"))) then
            "queued bead \($id) is armed for its validating closer (mol-validate-close) on \($m["gc.dispatch_when_ready"] | tostring): it waits on another bead to land and is checked then, so it is not new work to place, and while it is held the closer never runs. Lift its hold by removing each spelling of it the bead carries, \($lift), and keep the arm"
          else
            "queued bead \($id) is armed for dispatch to \($m["gc.dispatch_when_ready"] | tostring): a placement that stopped before its lift, or an arm set while it was held. Finish its placement with gc-helm.sh place \($id) --under <parent> or --standalone, which lifts the hold without dispatching again, or disarm it: deferred-dispatch.sh disarm \($id)"
          end)
       else empty end),
      (if (.assignee | nonblank) then
         "queued bead \($id) is assigned to \(.assignee | tostring), and Gas City serves a held bead to no assignee. Finish its placement with gc-helm.sh place \($id) --under <parent> or --standalone, which lifts the hold without dispatching again, or clear the assignee"
       else empty end)
    | gsub("[[:cntrl:]]"; " ")' "$WORK/queued.json" 2>/dev/null)"

# A queued bead whose prefix names no one store, or whose store is not read,
# cannot have its runs read.
if [ "$rigs_ok" = 1 ]; then
    unplaced=$(jq -r --argjson stores "$STORES_JSON" '[ .[] | ((.id // "") | tostring)
        | select(. != "" and ($stores[split("-")[0]] // null) == null) ] | join(" ")' "$WORK/queued.json" 2>/dev/null)
    [ -z "$unplaced" ] || warnings+=("queued bead(s) $unplaced carry an id prefix no single rig in the rig map has, so whether a live run works them was NOT checked")
fi

for pid in ${scan_pids[@]+"${scan_pids[@]}"}; do fanout_wait "$pid"; done

# The scans' reports, merged in rig order however the jobs interleaved, so one
# state of the stores always produces the same report.
n=0
while IFS=$'\037' read -r rig_name rig_path pfx suspended; do
    [ -n "$rig_path" ] || continue
    n=$((n + 1))
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        held_here=$(jq -r --arg p "$pfx" '[ .[] | ((.id // "") | tostring) | select(split("-")[0] == $p) ] | join(" ")' "$WORK/queued.json" 2>/dev/null)
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)${held_here:+; the runs of its queued bead(s) $held_here were not read}")
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
        esac
    done <"$WORK/$n.msg"
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
queued_n=$(jq -r 'length' "$WORK/queued.json" 2>/dev/null)
if [ "${#findings[@]}" -ne 0 ]; then
    echo "the po receives more than its queue: ${#findings[@]} finding(s)"
    detail "${findings[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "po queue-only check partially determined"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: the po receives nothing but its queue (${#po_list[@]} po seat(s) read; ${queued_n:-0} queued bead(s), each new work that nothing has sent)"
detail ${notes[@]+"${notes[@]}"}
exit 0
