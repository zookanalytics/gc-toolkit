#!/usr/bin/env bash
# doctor/check-routed-work-claimable — I3: routed and assigned work is
# claimable. Arm 1: an open, unassigned bead's gc.routed_to is byte-identical
# to a live agent identity or a sentinel — the pool offer is exact string
# equality (gascity hookClaimMatchesRoute), so a rig-unqualified or padded
# route is invisible to every pool. Arm 2: an open, ASSIGNED bead's assignee is
# held to the same test — assignment polls are the same exact-match contract.
# Arm 3: no scope="rig" order is registered with no rig bound (an unbound copy
# strands an unclaimable workflow root in the city store every fire). Arm 4:
# an open, unassigned, routed bead is reachable from the store it lives in — an
# address arms 1-2 accept still names nobody who can be OFFERED the bead. Two
# ways it is not: the route reads a different store than the bead lives in (a
# rig-scope pool queries only its own rig's store, so a cross-store route is
# offered by nobody however valid the address, even while the bead sits in its
# own store's `bd ready` — the shape gc sling refuses as CrossStoreRouteError),
# or the bead is in neither `bd ready` nor `bd blocked`, waiting where no queue
# reports it. A live graph.v2 molecule step (gc.step_id with a LIVE
# gc.root_bead_id — open or in_progress) is exempt: its molecule schedules it
# through session affinity, so it is in neither list by design, not stranded —
# an orphan step of a CLOSED molecule stays a finding, and a root whose liveness
# cannot be read warns, never passes.
# Each candidate the strand test reaches is re-read at report time, so one that
# closed between the listing and the report is dropped, not flagged from a stale
# snapshot.
# Values are compared AS STORED; normalization is a diagnostic, never a pass.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.
#
# Cost. The whole check shares one doctor budget, and most of a probe's latency
# is the gc wrapper starting up rather than the query it runs. So the check
# overlaps its probes instead of chaining them. The rig and order registries are
# read while the agent roster is. Each store is then scanned by its own
# background job, which reads its three listings at once, and the candidates it
# must re-read go out as one batch, read together with the molecule roots they
# may need. A listing lands in a file, never in a shell variable, because a
# whole-store listing held in a variable costs seconds per expansion. Every read
# asks only for what an arm judges: --brief omits the free text, and the ready
# read asks only for the unassigned, routed beads arm 4 looks up.

set -u

dir="${GC_PACK_DIR:-.}"
# Deliberate "a person must decide" markers; exact match only.
SENTINELS='["human"]'
# Types `bd ready` never returns (beads sqlbuild.ReadyWorkExcludeTypes + its
# default infra types); routing one is a different mistake from stranding it.
READY_EXCLUDES=" merge-request gate molecule rig agent role message "

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
# >>> probe-stderr-capture
# The gc probes below send stderr to $PROBE_ERR, not /dev/null, so a failure the
# check reports names the reason it failed instead of only its rc. An I3
# transient reported as "rc=1" alone is undiagnosable and recurs. Each probe's
# `2>"$PROBE_ERR"` truncates the file, so it never holds a prior probe's stderr.
# probe_err returns the first non-blank line, control characters stripped to keep
# it one line and length-capped. mktemp failing degrades to /dev/null (always
# empty), so probe_err yields nothing and every detail reads as before.
PROBE_ERR=$(mktemp "${TMPDIR:-/tmp}/gctk-check-routed-work-claimable.XXXXXX" 2>/dev/null) || PROBE_ERR=/dev/null
[ "$PROBE_ERR" = /dev/null ] || trap 'rm -f "$PROBE_ERR"' EXIT
probe_err() {
    [ -s "$PROBE_ERR" ] || return 0
    tr -d '\000-\010\013-\037' < "$PROBE_ERR" 2>/dev/null | grep -m1 '[^[:space:]]' | cut -c1-200
}
# <<< probe-stderr-capture

# The scratch every background read lands in. The descriptor held open on a file
# inside it keeps the tree held for the whole run, because the host's scratch
# reaper removes any gctk-* tree that no process holds open.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-routed-work-claimable-scan.XXXXXX" 2>/dev/null) || WORK=""
trap '[ -z "$WORK" ] || rm -rf "$WORK"; [ "$PROBE_ERR" = /dev/null ] || rm -f "$PROBE_ERR"' EXIT
if [ -z "$WORK" ] || ! { exec 9>"$WORK/.hold"; } 2>/dev/null; then
    echo "cannot determine whether routed/assigned work is claimable (I3)"
    detail "could not create a scratch directory under ${TMPDIR:-/tmp}, which every store scan reads into; no store was checked."
    exit 1
fi
# read_to <file> <probe...> runs one bounded probe with its stdout scrubbed into
# <file> and its stderr in <file>.err, and returns the probe's own exit status.
# Concurrent probes cannot share $PROBE_ERR, so every background read takes this
# shape, and err_of <file> is probe_err for that read.
read_to() {
    local f="$1"; shift
    run_bounded "$@" 2>"$f.err" | scrub >"$f"
    return "${PIPESTATUS[0]}"
}
err_of() { local PROBE_ERR="$1.err"; probe_err; }

# The rig and order registries are read in the background while the agent
# roster is read here.
read_to "$WORK/rigs.json" gc rig list --json </dev/null >/dev/null 2>&1 & rigs_pid=$!
read_to "$WORK/orders.json" gc order list --json </dev/null >/dev/null 2>&1 & orders_pid=$!

agents_raw=$(run_bounded gc agent list --json 2>"$PROBE_ERR"); agents_rc=$?; agents_err=$(probe_err)
identities=$(printf '%s' "$agents_raw" \
    | jq -c '[.agents[]? | (.qualified_name // "") | select(. != "")] | unique' 2>/dev/null)
if [ "$agents_rc" -ne 0 ] || [ -z "$identities" ] || [ "$identities" = "[]" ]; then
    echo "cannot determine whether routed/assigned work is claimable (I3)"
    detail "\`gc agent list --json\` failed (rc=$agents_rc) or listed no qualified identities; with no identity set every route looks dead."
    [ -n "$agents_err" ] && detail "\`gc agent list\` stderr: $agents_err"
    exit 1
fi
city_path=$(printf '%s' "$agents_raw" | jq -r '.city_path // ""' 2>/dev/null)

wait "$rigs_pid"; rigs_rc=$?; rigs_err=$(err_of "$WORK/rigs.json")
scopes=$(jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path] | join("\u001f")' "$WORK/rigs.json" 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether routed/assigned work is claimable (I3)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    [ -n "$rigs_err" ] && detail "\`gc rig list\` stderr: $rigs_err"
    exit 1
fi
# Rig name -> store path, so arm 4 can reach a molecule root's store from its
# gc.root_store_ref ("rig:<name>") when the root lives outside the store being
# scanned. Built once from the same rig list the scan iterates.
declare -A STORE_PATH=()
while IFS=$'\037' read -r _sn _sp; do [ -n "$_sp" ] && STORE_PATH["$_sn"]="$_sp"; done <<< "$scopes"

# Identity -> the store PATH it actually reads, so arm 4 can tell a valid address
# that reads THIS store from one that reads another. A rig-scope agent reads its
# rig's store (the "<rig>/" prefix of its qualified name); a city-scope agent
# reads the city store. Any other scope is left unmapped, so the cross-store arm
# below makes a positive finding only where the target store is known.
declare -A ROUTE_STORE=()
while IFS=$'\037' read -r _qn _scope; do
    [ -n "$_qn" ] || continue
    case "$_scope" in
        rig)  case "$_qn" in */*) _rn="${_qn%%/*}"; [ -n "${STORE_PATH[$_rn]:-}" ] && ROUTE_STORE["$_qn"]="${STORE_PATH[$_rn]}" ;; esac ;;
        city) [ -n "$city_path" ] && ROUTE_STORE["$_qn"]="$city_path" ;;
    esac
done <<< "$(printf '%s' "$agents_raw" | jq -r '.agents[]?
    | [((.qualified_name // "") | gsub("[[:cntrl:]]"; " ")), ((.scope // "") | tostring)]
    | join("\u001f")' 2>/dev/null)"

# root_db <gc.root_store_ref> <step's store path> sets ROOT_DB to the .beads
# path a molecule root lives in. A "rig:<name>" ref naming a scanned rig is that
# rig's store; any other ref leaves the root in its step's own store.
root_db() {
    ROOT_DB="$2/.beads"
    case "$1" in
        rig:*) if [ -n "${STORE_PATH[${1#rig:}]:-}" ]; then ROOT_DB="${STORE_PATH[${1#rig:}]}/.beads"; fi ;;
    esac
}

# Arms 1, 2 and 4 over one store. Its reads land in files named from the prefix
# $3, and its findings go to the errors, warnings and notes arrays.
scan_store() {
    local rig_name="$1" rig_path="$2" out="$3"
    local label="${rig_name:-<city>}" qualifier="$rig_name"
    [ -n "$city_path" ] && [ "$rig_path" = "$city_path" ] && qualifier=""
    local list="$out.open.json" ready="$out.ready.json" blocked="$out.blocked.json"
    local -A addr_errors=() offerable=()
    local list_pid ready_pid blocked_pid rc list_err ready_rc ready_err blocked_rc blocked_err reach_err
    local rows key class id valjson fix cand offered oid
    # The three listings are read at once. --brief omits the free text
    # (description, notes and the like) and keeps the id, assignee, type,
    # parent, dependencies and metadata the arms read. A queue answer is only
    # ever looked up by a candidate's id, and every candidate is unassigned and
    # carries a gc.routed_to key, so the ready read asks for exactly those rows.
    # `bd blocked` takes no such filter.
    read_to "$list" gc bd list --db "$rig_path/.beads" --status open --json --limit 0 --brief & list_pid=$!
    read_to "$ready" gc bd ready --db "$rig_path/.beads" --json --limit 0 --brief --unassigned --has-metadata-key gc.routed_to & ready_pid=$!
    read_to "$blocked" gc bd blocked --db "$rig_path/.beads" --json & blocked_pid=$!
    wait "$list_pid"; rc=$?
    wait "$ready_pid"; ready_rc=$?
    wait "$blocked_pid"; blocked_rc=$?
    list_err=$(err_of "$list"); ready_err=$(err_of "$ready"); blocked_err=$(err_of "$blocked")
    if [ "$rc" -ne 0 ] || [ ! -s "$list" ]; then
        warnings+=("$label: could not list open beads in $rig_path/.beads (rc=$rc) — this store was NOT checked${list_err:+; \`gc bd list\` stderr: $list_err}")
        return
    fi
    rows=$(jq -r -s \
        --argjson ids "$identities" --argjson sent "$SENTINELS" --arg q "$qualifier" '
        def class($v):
          ($v | sub("^[[:space:][:cntrl:]]+"; "") | sub("[[:space:][:cntrl:]]+$"; "")) as $n
          | (if ($ids | index($v)) != null or ($sent | index($v)) != null then ["ok", ""]
             elif $n == "" then ["blank", ""]
             elif ($ids | index($n)) != null or ($sent | index($n)) != null then ["padded", $n]
             elif $q != "" and ($ids | index($q + "/" + $n)) != null then ["repair", $q + "/" + $n]
             elif ([$ids[] | select(endswith("/" + $n))] | length) > 0
               then ["ambiguous", ([$ids[] | select(endswith("/" + $n))] | join(", "))]
             else ["unknown", ""] end);
        # One JSON array, or the listing is unreadable: whitespace, an error
        # object or two documents must not pass as an empty store.
        if length == 1 and (.[0] | type) == "array" then .[0][] else error("not one JSON array") end
        | . as $b
        | ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $id
        | ((($b.assignee // "") | tostring)) as $as
        | ((($b.metadata // {})["gc.routed_to"] // "") | tostring) as $rt
        | ( (if $as == "" and $rt != ""
             then (class($rt) as $c | [["gc.routed_to", $rt, $c[0], $c[1]]]) else [] end)
          + (if $as != ""
             then (class($as) as $c | [["assignee", $as, $c[0], $c[1]]]) else [] end) )[]
        | select(.[2] != "ok")
        | [.[0], .[2], $id, (.[1] | tojson), .[3]] | join("\u001f")' "$list" 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: open-bead listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        return
    fi
    while IFS=$'\037' read -r key class id valjson fix; do
        [ -n "$key" ] || continue
        case "$class" in
            blank)     errors+=("$label bead $id: $key=$valjson is nothing but whitespace/control characters — it names no agent and is not the empty value that means \"none\"; clear it or set a live identity") ;;
            padded)    errors+=("$label bead $id: $key=$valjson names no agent — stripped of padding it would be \"$fix\", but matching is exact byte equality (the value is quoted as stored so the padding is visible); set $key=$fix") ;;
            repair)    errors+=("$label bead $id: $key=$valjson names no agent — it is the rig-unqualified form of $fix, matched by nothing; set $key=$fix") ;;
            ambiguous) errors+=("$label bead $id: $key=$valjson names no agent — it is the rig-unqualified form of $fix, none of which reads this store") ;;
            *)         notes+=("$label bead $id: $key=$valjson matches no live identity and no rig-qualified form of one — unreachable, but indistinguishable from an unknown sentinel; reported, not judged") ;;
        esac
        case "$class" in blank|padded|repair|ambiguous) addr_errors["$id"]=1 ;; esac
    done <<< "$rows"

    # Arm 4 — reachability. A valid address is not an offer: a pool offers what
    # `bd ready` returns, so a routed bead in neither `bd ready` nor `bd blocked`
    # is offered by nobody and shows its wait to nobody.
    cand=$(jq -r '
        .[]?
        | select(((.assignee // "") | tostring) == "")
        | select(((((.metadata // {})["gc.routed_to"]) // "") | tostring) != "")
        | [ (((.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")),
            ((.issue_type // "") | tostring),
            ((((.metadata // {})["gc.routed_to"]) // "") | tostring),
            ((.parent // "") | tostring),
            ([(.dependencies // [])[] | select(((.type // "") | tostring) == "blocks")
              | ((.depends_on_id // "") | tostring) | select(. != "")] | join(", ")),
            ((((.metadata // {})["gc.step_id"]) // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            ((((.metadata // {})["gc.root_bead_id"]) // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            ((((.metadata // {})["gc.root_store_ref"]) // "") | tostring | gsub("[[:cntrl:]]"; " "))
          ] | join("\u001f")' "$list" 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: routed beads in $rig_path/.beads could not be enumerated — this store was NOT checked for reachability")
        return
    fi
    # A store with no routed, unassigned bead gives this arm nothing to judge.
    [ -n "$cand" ] || return
    if [ "$ready_rc" -ne 0 ] || [ ! -s "$ready" ] || [ "$blocked_rc" -ne 0 ] || [ ! -s "$blocked" ]; then
        reach_err="$ready_err${ready_err:+${blocked_err:+; }}$blocked_err"
        warnings+=("$label: could not read \`bd ready\` (rc=$ready_rc) or \`bd blocked\` (rc=$blocked_rc) in $rig_path/.beads — routed work there was NOT checked for reachability${reach_err:+; stderr: $reach_err}")
        return
    fi
    offered=$(jq -r -n --slurpfile r "$ready" --slurpfile b "$blocked" '
        if [$r, $b] | all(length == 1 and (.[0] | type) == "array")
        then ($r[0][], $b[0][]) | (.id // empty) | tostring
        else error("not one JSON array each") end' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: the \`bd ready\`/\`bd blocked\` listings from $rig_path/.beads could not be parsed — routed work there was NOT checked for reachability")
        return
    fi
    while IFS= read -r oid; do
        [ -n "$oid" ] && offerable["$oid"]=1
    done <<< "$offered"

    # The candidates no pool visibly offers. The report below walks them in
    # listing order. The ones it judges by a re-read are collected first, with
    # the molecule roots their listed step markers name, so that every re-read
    # goes out at once.
    local -a pending=() reread=()
    local -A root_ids=() root_seen=()
    local btype route parent blockers lstep lroot lref xstore target_store rkey
    while IFS=$'\037' read -r id btype route parent blockers lstep lroot lref; do
        [ -n "$id" ] || continue
        [ -n "${addr_errors[$id]:-}" ] && continue
        # Cross-store reachability. A route can name a live identity (arm 1 passed
        # it) yet read a store that does not hold this bead: a rig-scope pool
        # queries only its own rig's store, so it never offers a bead that lives
        # elsewhere — even one sitting in its own store's `bd ready`. That in-store
        # `bd ready` membership is exactly what `offerable` records, so this test
        # precedes it: a cross-store route is not rescued by being offerable where
        # no routed-to pool reads. Positive finding only — a route whose store is
        # unknown (ROUTE_STORE unset) falls through to the offerable test below.
        xstore=""; target_store="${ROUTE_STORE[$route]:-}"
        [ -n "$target_store" ] && [ "$target_store" != "$rig_path" ] && xstore=1
        [ -z "$xstore" ] && [ -n "${offerable[$id]:-}" ] && continue
        pending+=("$id"$'\037'"$btype"$'\037'"$route"$'\037'"$parent"$'\037'"$blockers"$'\037'"$xstore")
        # A type `bd ready` never returns is reported without a re-read.
        case "$READY_EXCLUDES" in *" $btype "*) continue ;; esac
        reread+=("$id")
        [ -n "$lstep" ] && [ -n "$lroot" ] || continue
        root_db "$lref" "$rig_path"; rkey="$ROOT_DB"$'\037'"$lroot"
        [ -n "${root_seen[$rkey]:-}" ] && continue
        root_seen["$rkey"]=1; root_ids["$ROOT_DB"]+="$lroot"$'\n'
    done <<< "$cand"

    # The re-reads the live-molecule carve-out below rests on: one read of every
    # candidate it judges, and one read per store their molecule roots live in,
    # all at once, so a burst of in-flight steps costs one round of probes rather
    # than two per step. A step's root is the one its listed markers name; a
    # re-read that names a different root finds no status for it. `bd show`
    # answers a batch with the rows it found, exiting 0 when some resolved and 1
    # when none did. A candidate missing from the answer is an unreadable
    # re-read, and a root missing from it has no status.
    local -A cur_status=() cur_step=() cur_root=() cur_root_db=() root_status=() root_fail=()
    local -a rids=() root_dbs=() root_pids=()
    local reread_pid st sid rid rref db i root_rc root_err
    if [ "${#reread[@]}" -gt 0 ]; then
        read_to "$out.reread.json" gc bd show "${reread[@]}" --db "$rig_path/.beads" --json & reread_pid=$!
        i=0
        for db in "${!root_ids[@]}"; do
            mapfile -t rids <<< "${root_ids[$db]%$'\n'}"
            read_to "$out.roots.$i.json" gc bd show "${rids[@]}" --db "$db" --json & root_pids+=("$!")
            root_dbs+=("$db"); i=$((i + 1))
        done
        if wait "$reread_pid"; then
            while IFS=$'\037' read -r id st sid rid rref; do
                [ -n "$id" ] || continue
                cur_status["$id"]="$st"; cur_step["$id"]="$sid"; cur_root["$id"]="$rid"
                root_db "$rref" "$rig_path"; cur_root_db["$id"]="$ROOT_DB"
            done <<< "$(jq -r '.[]? | [
                    (((.id // "") | tostring) | gsub("[[:cntrl:]]"; " ")),
                    (((.status // "") | tostring) | gsub("[[:cntrl:]]"; " ")),
                    ((((.metadata // {})["gc.step_id"] // "") | tostring) | gsub("[[:cntrl:]]"; " ")),
                    ((((.metadata // {})["gc.root_bead_id"] // "") | tostring) | gsub("[[:cntrl:]]"; " ")),
                    ((((.metadata // {})["gc.root_store_ref"] // "") | tostring) | gsub("[[:cntrl:]]"; " "))
                ] | join("\u001f")' "$out.reread.json" 2>/dev/null)"
        fi
        for i in "${!root_dbs[@]}"; do
            db="${root_dbs[$i]}"
            wait "${root_pids[$i]}"; root_rc=$?
            if [ "$root_rc" -ne 0 ]; then
                root_err=$(err_of "$out.roots.$i.json")
                root_fail["$db"]="$root_rc"$'\037'"$root_err"
                continue
            fi
            while IFS=$'\037' read -r rid st; do
                [ -n "$rid" ] || continue
                rkey="$db"$'\037'"$rid"; root_status["$rkey"]="$st"
            done <<< "$(jq -r '.[]? | [
                    (((.id // "") | tostring) | gsub("[[:cntrl:]]"; " ")),
                    (((.status // "") | tostring) | gsub("[[:cntrl:]]"; " "))
                ] | join("\u001f")' "$out.roots.$i.json" 2>/dev/null)"
        done
    fi

    local row cur_st step_id root_id root_st stranded
    for row in ${pending[@]+"${pending[@]}"}; do
        IFS=$'\037' read -r id btype route parent blockers xstore <<< "$row"
        case "$READY_EXCLUDES" in
            *" $btype "*)
                notes+=("$label bead $id: gc.routed_to=\"$route\" is set on a $btype, a type \`bd ready\` never returns — in neither list by that type's design rather than by a stranded route; reported, not judged")
                continue ;;
        esac
        # >>> arm4-live-molecule-and-recheck
        # A strand verdict rests on the candidate being open NOW and not being a
        # live graph.v2 molecule step. The open-bead list above is a snapshot: a
        # bead that closed since is flagged from a ghost. And a molecule step
        # (gc.step_id + gc.root_bead_id) is routed, unassigned, and in neither
        # `bd ready` nor `bd blocked` BY DESIGN — its molecule schedules it
        # through session affinity, not the pool queues. Re-read the candidate
        # once: drop it if it is no longer open, exempt it if its molecule is
        # still live (root open or in_progress), and keep it as the genuine
        # strand it is — an orphan step of a CLOSED molecule stays an error. An
        # unreadable CANDIDATE re-read falls through to the snapshot verdict
        # (fail-closed to visibility, never a silent drop); an unreadable or
        # otherwise undetermined ROOT liveness warns, so the step neither passes
        # nor is flagged as a strand the check cannot prove.
        if [ -n "${cur_status[$id]+set}" ]; then
            cur_st="${cur_status[$id]}"
            if [ -n "$cur_st" ] && [ "$cur_st" != "open" ]; then
                notes+=("$label bead $id: gc.routed_to=\"$route\" was open when the store was listed but is $cur_st now — it closed between the listing and this report, so it is not stranded; reported, not judged")
                continue
            fi
            step_id="${cur_step[$id]}"; root_id="${cur_root[$id]}"
            if [ -n "$step_id" ] && [ -n "$root_id" ]; then
                db="${cur_root_db[$id]}"
                if [ -n "${root_fail[$db]+set}" ]; then
                    IFS=$'\037' read -r root_rc root_err <<< "${root_fail[$db]}"
                    # The root probe failed, so the molecule's liveness is unknown.
                    # An unreadable probe warns and never passes: exempting would let
                    # a real orphan through, and erroring would manufacture the very
                    # strand false positive this carve-out exists to prevent.
                    warnings+=("$label bead $id: gc.routed_to=\"$route\" is the graph.v2 step $step_id of molecule $root_id, whose liveness could not be read (\`gc bd show $root_id\` rc=$root_rc) — this step's reachability was NOT determined${root_err:+; stderr: $root_err}")
                    continue
                fi
                rkey="$db"$'\037'"$root_id"; root_st="${root_status[$rkey]:-}"
                case "$root_st" in
                    open|in_progress)
                        # A live molecule root (poured or running) schedules its steps
                        # through session affinity, so an in-flight step is absent
                        # from `bd ready` and `bd blocked` by design, not stranded.
                        notes+=("$label bead $id: gc.routed_to=\"$route\" is the graph.v2 step $step_id of molecule $root_id, which is $root_st — the molecule schedules its steps through session affinity, so an in-flight step is absent from \`bd ready\` and \`bd blocked\` by design, not stranded; reported, not judged")
                        continue ;;
                    closed)
                        errors+=("$label bead $id: gc.routed_to=\"$route\" is the graph.v2 step $step_id of molecule $root_id, which is closed — the molecule is done but this step is still open and routed, an orphaned step no session will resume; close it or re-pour the molecule")
                        continue ;;
                    *)
                        # The root read gave this root no status (a missing or
                        # cross-store-unresolvable root) or a status that is
                        # neither live nor closed: liveness is undetermined. Warn —
                        # never silently pass, and never flag a strand we cannot prove.
                        warnings+=("$label bead $id: gc.routed_to=\"$route\" is the graph.v2 step $step_id of molecule $root_id, whose molecule liveness is undetermined (root status=\"$root_st\") — this step's reachability was NOT determined")
                        continue ;;
                esac
            fi
        fi
        # <<< arm4-live-molecule-and-recheck
        if [ -n "$xstore" ]; then
            errors+=("$label bead $id: gc.routed_to=\"$route\" is a live identity, but its pool reads a different store than the one $id lives in ($label) — a rig-scope pool claims only beads in its own store, so this route is offered by nobody however valid the address, even while $id sits in $label's own \`bd ready\`. This is the cross-store route gc sling refuses as CrossStoreRouteError; route it at a pool whose store holds $id, or file the demand in the store that pool reads")
            continue
        fi
        stranded="$label bead $id: gc.routed_to=\"$route\" is set, but the bead is in neither \`bd ready\` nor \`bd blocked\` — no pool offers it and no queue shows it waiting"
        if [ -n "$parent" ]; then
            errors+=("$stranded; it has parent $parent, and a parent-child child inherits its ancestor's blocked flag and drops out of ready — a routed bead must be parentless, or slung so a parentless workflow root carries the demand")
        elif [ -n "$blockers" ]; then
            errors+=("$stranded; it depends on $blockers, which \`bd blocked\` does not name as an explaining wait — check the edge direction, since a child blocked BY the bead it exists to unblock never runs (d5cd6fb)")
        else
            errors+=("$stranded; it has no parent and no blocks edge, so its blocked flag names nothing to wait for")
        fi
    done
}

# One store's scan, run as a background job. It reports through "$3.msg":
# NUL-terminated records, each an E, W or N followed by the message, in the
# order the arms found them. The file appears only once the scan has finished,
# so a store with no .msg was not checked.
scan_job() {
    errors=(); warnings=(); notes=()
    scan_store "$@"
    local m
    { for m in ${errors[@]+"${errors[@]}"}; do printf 'E%s\0' "$m"; done
      for m in ${warnings[@]+"${warnings[@]}"}; do printf 'W%s\0' "$m"; done
      for m in ${notes[@]+"${notes[@]}"}; do printf 'N%s\0' "$m"; done
    } >"$3.part" && mv "$3.part" "$3.msg"
}

scan_pids=()
n=0
while IFS=$'\037' read -r rig_name rig_path; do
    [ -n "$rig_path" ] || continue
    n=$((n + 1))
    scan_job "$rig_name" "$rig_path" "$WORK/$n" </dev/null >/dev/null 2>&1 &
    scan_pids+=("$!")
done <<< "$scopes"
for pid in "${scan_pids[@]}"; do wait "$pid"; done

# The jobs' findings, merged in rig order however the jobs interleaved.
n=0
while IFS=$'\037' read -r rig_name rig_path; do
    [ -n "$rig_path" ] || continue
    n=$((n + 1))
    if [ ! -f "$WORK/$n.msg" ]; then
        warnings+=("${rig_name:-<city>}: the scan of $rig_path/.beads ended without reporting — this store was NOT checked")
        continue
    fi
    while IFS= read -r -d '' rec; do
        case "$rec" in
            E*) errors+=("${rec#E}") ;;
            W*) warnings+=("${rec#W}") ;;
            N*) notes+=("${rec#N}") ;;
        esac
    done <"$WORK/$n.msg"
done <<< "$scopes"

# Arm 3 — a live registration with no rig bound whose order declares scope="rig".
declares_rig_scope() { grep -qE '^[[:space:]]*scope[[:space:]]*=[[:space:]]*"rig"' "$1" 2>/dev/null; }
wait "$orders_pid"; orders_rc=$?; orders_err=$(err_of "$WORK/orders.json")
if [ "$orders_rc" -ne 0 ] || ! jq -e '(.orders | type) == "array"' "$WORK/orders.json" >/dev/null 2>&1; then
    warnings+=("could not read the order registry (\`gc order list --json\`, rc=$orders_rc) — the rig-scoped-order arm did not run, so an unbound rig-scoped order would not be visible here${orders_err:+; \`gc order list\` stderr: $orders_err}")
else
    while IFS=$'\t' read -r oname osrc; do
        [ -n "$oname" ] || continue
        if [ -n "$osrc" ] && [ -f "$osrc" ]; then
            declares_rig_scope "$osrc" \
                && errors+=("order $oname: registered with NO rig bound, but $osrc declares scope=\"rig\" — every fire strands an unclaimable workflow root in the city store")
        elif [ -f "$dir/orders/$oname.toml" ] && declares_rig_scope "$dir/orders/$oname.toml"; then
            errors+=("order $oname: registered with NO rig bound, and this pack ships orders/$oname.toml with scope=\"rig\" — every fire strands an unclaimable workflow root in the city store")
        elif [ -n "$osrc" ]; then
            notes+=("order $oname: registered with no rig bound; source $osrc is unreadable, so its declared scope is unknown — reported, not judged")
        fi
    done <<< "$(jq -r '.orders[]?
        | select(((.rig // "") | tostring) == "")
        | [(.name // ""), (.source // "")] | @tsv' "$WORK/orders.json" 2>/dev/null)"
fi

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "unreachable routed/assigned work or unbound rig-scoped orders (I3): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "routed/assigned-work reachability partially determined (I3)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every route and assignee on open work names a live agent identity whose store holds the bead, and every rig-scoped order is bound"
detail ${notes[@]+"${notes[@]}"}
exit 0
