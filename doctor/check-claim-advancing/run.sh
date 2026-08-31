#!/usr/bin/env bash
# doctor/check-claim-advancing — I11: a step a pool is meant to run is being
# run — either advanced by the session holding it, or claimed at all.
#
# A pool session reports active and running whether it is working or parked at
# an idle prompt, so a claimed step can sit untouched with every other alarm
# green. The discriminator is the HOLDER's clock, not the bead's:
# check-step-terminal's stall arm is bead-clocked at 48h and never looks at who
# holds the step, so it cannot see a holder that stopped hours ago.
#
# Arm 1 — CLAIMED. Per store, every in_progress bead carrying gc.step_ref whose
# claim is older than the stall bound is joined to its holder, matched on
# session id, session_name or alias — the three identities a claim can be
# stamped with. Claims younger than the bound are never judged, which is also
# what keeps a pool recycle (the holder's incarnation changes under a live
# claim) from reading as a fault.
#
#   UNHELD    the bead carries no assignee at all         -> error
#   ORPHANED  the assignee names no session at all        -> error
#   DEAD      the holding session is not running          -> error
#   STALLED   the holder runs, but its last_active is     -> error
#             older than the bound as well
#
# UNHELD is read off the bead alone. The other three are read out of the
# session roster, and `_cache_age_s` sits beside `sessions` rather than inside
# each one, so it ages the whole roster and not just `last_active`. Against a
# roster older than the bound, an absent session may be a holder that started
# after the snapshot, and `running: false` may be a state its holder has since
# left. So all three degrade to warnings there, and only UNHELD still reports
# as an error. `gc session list` exposes no uncached mode to fall back on.
#
# UNHELD is reachable by neither path: nothing holds it, and `bd ready` skips
# it because its status is not open. The two checks that would otherwise see it
# both scan --status open, so an in_progress step with no assignee is invisible
# to all of them. Clearing an assignee and setting a status are separate writes,
# so this state exists briefly during a legitimate release; the bound covers it.
#
# Arm 2 — UNCLAIMED. A claim is not the first thing that can fail to happen. A
# step poured, routed to a pool and never claimed by anybody stays `open`, so
# arm 1 does not see it, and gate-ensure's pour_spent reads any open step as
# "still driven" and declines the question by design. Per store, an open step
# that `bd ready` is offering, carrying a route, with no assignee and no
# gc.claimed_at ever stamped, untouched past the same bound, is judged against
# the agent its route names:
#
#   route names no agent      -> note   (an unreachable address is I3's finding)
#   the agent is suspended    -> note   (parked on purpose)
#   pool max is 0             -> note   (nothing is meant to claim it)
#   no running session        -> note   (scaled to zero; the demand probe's)
#   every session is busy     -> note   (a queue behind a full pool is backpressure)
#   a running session is free -> error  (an idle worker and an offered step)
#
# Only the last is a fault, and it is the one shape a backlog cannot explain.
# Occupancy counts a session holding ANY in-progress bead, not just a formula
# step, because a singleton agent's work usually is not one. That is why the
# in-progress listing is filtered for gc.step_ref here rather than server-side:
# arm 1 wants the steps, arm 2 wants everything, and one probe answers both.
# The roster supplies liveness here too, so a stale one degrades the error to a
# warning exactly as it does in arm 1.
#
# last_active is derived from tmux pane changes and is hardened upstream
# against self-inflation (gc's own nudge keystrokes do not ratchet it), so a
# working agent refreshes it and a parked one does not.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
STALL_MINUTES="${GC_DOCTOR_CLAIM_STALL_MINUTES:-30}"
case "$STALL_MINUTES" in *[!0-9]*|"") STALL_MINUTES=30 ;; esac
STALL=$((STALL_MINUTES * 60))
SEP=$'\037'

errors=(); warnings=(); notes=()
unclaimed=(); occupied_list=(); occupancy_partial=0
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

sessions_raw=$(run_bounded gc session list --json 2>/dev/null); sessions_rc=$?
sessions=$(printf '%s' "$sessions_raw" | scrub \
    | jq -c '[(.sessions // [])[]? | select(type == "object")]' 2>/dev/null)
if [ "$sessions_rc" -ne 0 ] || [ -z "$sessions" ]; then
    echo "cannot determine whether claimed steps are being advanced (I11)"
    detail "\`gc session list --json\` failed (rc=$sessions_rc) or could not be parsed; with no session set every claim would look orphaned."
    exit 1
fi
# An empty roster is a real state (a stopped city), but it cannot distinguish a
# held claim from an abandoned one, so it is reported rather than judged.
if [ "$sessions" = "[]" ]; then
    echo "cannot determine whether claimed steps are being advanced (I11)"
    detail "\`gc session list --json\` listed no sessions; every claim would classify as ORPHANED against an empty roster."
    exit 1
fi
cache_age=$(printf '%s' "$sessions_raw" | scrub \
    | jq -r '(._cache_age_s // 0) | if type == "number" then floor else 0 end' 2>/dev/null)
case "${cache_age:-}" in *[!0-9]*|"") cache_age=0 ;; esac
stale_roster=0
[ "$cache_age" -gt "$STALL" ] && stale_roster=1

# Arm 2 needs the agent registry: an unclaimed step is judged against the pool
# its route names, and a suspended or session-less pool has to stay quiet.
agents_raw=$(run_bounded gc agent list --json 2>/dev/null); agents_rc=$?
agents=$(printf '%s' "$agents_raw" | scrub | jq -c '[.agents[]? | select(type == "object")
    | ((.qualified_name // "") | tostring) as $n | select($n != "")
    | {name: $n,
       state: (if ((.suspended // false) | tostring) == "true" then "suspended"
               elif (.pool | type) != "object" then "nopool"
               elif ((.pool.max // 0) | if type == "number" then . else 0 end) == 0 then "nopool"
               else "pool" end)}]' 2>/dev/null)
unclaimed_ok=1
if [ "$agents_rc" -ne 0 ] || [ -z "$agents" ] || [ "$agents" = "[]" ]; then
    unclaimed_ok=0
    warnings+=("\`gc agent list --json\` failed (rc=$agents_rc) or listed no agents — the never-claimed arm did NOT run, so a routed step nothing has ever claimed is not covered by this run")
fi

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether claimed steps are being advanced (I11)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

while IFS="$SEP" read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    db="$rig_path/.beads"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    claims_raw=$(run_bounded bd list --db "$db" --status in_progress --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$claims_raw" ]; then
        warnings+=("$label: could not list in-progress beads in $db (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$claims_raw" | scrub | jq -r \
        --argjson sess "$sessions" --argjson stall "$STALL" --argjson cache "$cache_age" '
        def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);
        def trim: (tostring) | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "");
        # One session is reachable under every identity a claim may carry.
        ( reduce ($sess[]? | select(type == "object")) as $s ({};
            reduce ((([$s.id, $s.session_name, $s.alias] | map(tostring)
                      | map(select(. != ""))))[]) as $k (.; .[$k] = $s)) ) as $S
        | ($cache > $stall) as $stale
        | [ .[]? | . as $b
            | (($b.metadata // {})["gc.step_ref"] // "" | trim) as $ref
            | select($ref != "")
            | (($b.assignee // "") | trim) as $as
            | ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $bid
            | (($b.metadata // {})["gc.claimed_at"] // $b.updated_at // $b.created_at // "" | trim) as $ca
            | ($ca | ep) as $ce
            | select($ce != null and (now - $ce) > $stall)
            | ((now - $ce) / 60 | floor) as $held
            | ($S[$as] // null) as $s
            | (if $as == ""
               then {cls: "unheld", bid: $bid, as: "", held: $held, ex: ""}
               elif $s == null
               then {cls: (if $stale then "orphaned_cached" else "orphaned" end),
                     bid: $bid, as: $as, held: $held, ex: ""}
               elif (($s.running // false) | tostring) != "true"
               then {cls: (if $stale then "dead_cached" else "dead" end),
                     bid: $bid, as: $as, held: $held,
                     ex: (($s.state // "unknown") | tostring | gsub("[[:cntrl:]]"; " "))}
               else (($s.last_active // "") | trim) as $la
                    | ($la | ep) as $le
                    | (if $le == null
                       then {cls: "unknown", bid: $bid, as: $as, held: $held, ex: $la}
                       elif (now - $le) > $stall
                       then {cls: (if $stale then "stalled_cached" else "stalled" end),
                             bid: $bid, as: $as, held: $held,
                             ex: (((now - $le) / 60 | floor) | tostring)}
                       else empty end)
               end) ]
        | .[] | [.cls, .bid, .as, (.held | tostring), .ex] | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: in-progress listing from $db could not be parsed — this store was NOT checked")
        continue
    fi
    if [ -n "$rows" ]; then
        while IFS="$SEP" read -r cls bid as held ex; do
            [ -n "$cls" ] || continue
            case "$cls" in
                unheld)   errors+=("$label step $bid: in_progress for ${held}m with NO assignee. Nothing holds it, and \`bd ready\` cannot offer it either because its status is not open, so it is reachable by neither path; release it (status=open) so a pool can re-offer it.") ;;
                orphaned) errors+=("$label step $bid: claimed ${held}m ago by \"$as\", which names no session — id, session_name and alias were all tried. Nothing holds this step and nothing will advance it; release it (status=open, assignee=\"\") so a pool can re-offer it.") ;;
                dead)     errors+=("$label step $bid: claimed ${held}m ago by \"$as\", whose session is not running (state=$ex). The claim outlived its holder; release it so a pool can re-offer it.") ;;
                stalled)  errors+=("$label step $bid: claimed ${held}m ago by \"$as\", which is running but has produced no output for ${ex}m. A holder quiet past the ${STALL_MINUTES}m bound is parked, not working; nudge it to deliver the step it holds, or release the claim.") ;;
                orphaned_cached) warnings+=("$label step $bid: claimed ${held}m ago by \"$as\", which names no session — but \`gc session list\` answered from a ${cache_age}s cache, itself older than the ${STALL_MINUTES}m bound, so the holder may have started after that snapshot. Re-run once the cache is fresh.") ;;
                dead_cached) warnings+=("$label step $bid: claimed ${held}m ago by \"$as\", whose session read as not running (state=$ex) — but \`gc session list\` answered from a ${cache_age}s cache, itself older than the ${STALL_MINUTES}m bound, so the holder may be running now. Re-run once the cache is fresh.") ;;
                stalled_cached) warnings+=("$label step $bid: claimed ${held}m ago by \"$as\", last output ${ex}m ago — but \`gc session list\` answered from a ${cache_age}s cache, itself older than the ${STALL_MINUTES}m bound, so the holder may have produced output since. Re-run once the cache is fresh.") ;;
                unknown)  notes+=("$label step $bid: claimed ${held}m ago by \"$as\", whose last_active is \"$ex\" and does not parse as a timestamp — liveness could not be judged for this holder; reported, not judged") ;;
            esac
        done <<< "$rows"
    fi

    [ "$unclaimed_ok" -eq 1 ] || continue

    # Occupancy: every identity holding work of ANY kind in this store, read
    # off the listing arm 1 already fetched.
    held_ids=$(printf '%s' "$claims_raw" | scrub | jq -r '.[]? | ((.assignee // "") | tostring)
        | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "") | select(. != "")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        occupancy_partial=1
        warnings+=("$label: the assignees in $db could not be read — a worker busy in this store reads as free, so never-claimed findings are reported as warnings rather than errors")
    elif [ -n "$held_ids" ]; then
        while IFS= read -r h; do
            [ -n "$h" ] && occupied_list+=("$h")
        done <<< "$held_ids"
    fi

    open_raw=$(run_bounded bd list --db "$db" --status open --has-metadata-key gc.step_ref --json --limit 0 2>/dev/null); open_rc=$?
    if [ "$open_rc" -ne 0 ] || [ -z "$open_raw" ]; then
        warnings+=("$label: could not list open step beads in $db (rc=$open_rc) — never-claimed steps there were NOT checked")
        continue
    fi
    urows=$(printf '%s' "$open_raw" | scrub | jq -r --argjson stall "$STALL" '
        def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);
        def trim: (tostring) | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "");
        .[]? | . as $b
        | (($b.metadata // {})) as $m
        | (($m["gc.step_ref"] // "") | trim) as $ref
        | select($ref != "")
        | (($b.id // "") | tostring) as $raw
        | select($raw != "")
        # Any assignee at all means something owns it; a blank-but-present one
        # is an address fault I3 reports, not an unclaimed step.
        | select((($b.assignee // "") | tostring) == "")
        | select((($m["gc.claimed_at"] // "") | tostring) == "")
        # Routes are compared as stored, so a padded one falls through to the
        # no-such-agent note rather than being silently repaired here.
        | (($m["gc.routed_to"] // "") | tostring) as $rt
        | (($m["gc.execution_routed_to"] // "") | tostring) as $ert
        | (if $rt != "" then $rt else $ert end) as $route
        | select($route != "")
        | ((($b.updated_at // $b.created_at // "") | trim) | ep) as $ue
        | select($ue != null and (now - $ue) > $stall)
        | [ ($raw | gsub("[[:cntrl:]]"; " ")), ($route | gsub("[[:cntrl:]]"; " ")),
            ($ref | gsub("[[:cntrl:]]"; " ")),
            (((now - $ue) / 60 | floor) | tostring) ]
        | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: the open step listing from $db could not be parsed — never-claimed steps there were NOT checked")
        continue
    fi
    [ -n "$urows" ] || continue

    # A route is an address, not an offer: a pool claims what `bd ready`
    # returns, so a step the queue is not offering is waiting on its
    # predecessor by design and is nobody's fault yet. Probed only once a store
    # has a candidate, because most stores have none and the offer list is the
    # expensive half.
    ready_raw=$(run_bounded bd ready --db "$db" --json --limit 0 2>/dev/null); ready_rc=$?
    ready_ids=""
    if [ "$ready_rc" -eq 0 ] && [ -n "$ready_raw" ]; then
        ready_ids=$(printf '%s' "$ready_raw" | scrub | jq -r '.[]? | (.id // empty) | tostring' 2>/dev/null)
        ready_rc=$?
    fi
    if [ "$ready_rc" -ne 0 ]; then
        warnings+=("$label: could not read \`bd ready\` in $db (rc=$ready_rc) — never-claimed steps there were NOT checked")
        continue
    fi
    unset -v offerable; declare -A offerable=()
    while IFS= read -r oid; do
        [ -n "$oid" ] && offerable["$oid"]=1
    done <<< "$ready_ids"
    while IFS="$SEP" read -r uid urest; do
        [ -n "$uid" ] || continue
        [ -n "${offerable[$uid]:-}" ] || continue
        unclaimed+=("${label}${SEP}${uid}${SEP}${urest}")
    done <<< "$urows"
done <<< "$scopes"

# Arm 2's verdict. Deferred to here because occupancy is a city-wide question:
# a pool's workers are busy in whichever store their claim happens to live in.
if [ "${#unclaimed[@]}" -ne 0 ]; then
    occupied_json=$(printf '%s\n' ${occupied_list[@]+"${occupied_list[@]}"} \
        | jq -R -s -c 'split("\n") | map(select(. != "")) | unique' 2>/dev/null)
    if [ -z "$occupied_json" ]; then
        occupied_json='[]'
        occupancy_partial=1
        warnings+=("the set of identities already holding work could not be assembled — every session reads as free, so never-claimed findings are reported as warnings rather than errors")
    fi
    declare -A agent_state=()
    while IFS="$SEP" read -r aname astate; do
        [ -n "$aname" ] || continue
        agent_state["$aname"]="$astate"
    done <<< "$(printf '%s' "$agents" | jq -r '.[] | [.name, .state] | join("\u001f")' 2>/dev/null)"

    # One row per route that has running sessions: how many, how many of those
    # hold nothing, and which. `template` is the only field that ties a pool
    # worker back to the agent it runs — a pool member's alias is empty, and a
    # codex polecat's alias names the persona rather than the pool.
    declare -A pool_total=() pool_free=() pool_names=()
    while IFS="$SEP" read -r ptmpl ptotal pfree pnames; do
        [ -n "$ptmpl" ] || continue
        pool_total["$ptmpl"]="$ptotal"; pool_free["$ptmpl"]="$pfree"; pool_names["$ptmpl"]="$pnames"
    done <<< "$(printf '%s' "$sessions" | jq -r --argjson occ "$occupied_json" '
        (reduce ($occ[]? | tostring) as $o ({}; .[$o] = 1)) as $O
        | [ .[] | select(((.running // false) | tostring) == "true")
            | ((.template // "") | tostring) as $t | select($t != "")
            | { t: $t,
                free: (if ($O[((.id // "") | tostring)] != null
                           or $O[((.session_name // "") | tostring)] != null
                           or $O[((.alias // "") | tostring)] != null) then 0 else 1 end),
                nm: ([(.session_name // ""), (.alias // ""), (.id // "")]
                      | map(tostring) | map(select(. != ""))
                      | ((.[0] // "?") | gsub("[[:cntrl:]]"; " "))) } ]
        | group_by(.t)[]
        | [ .[0].t, (length | tostring), ([.[] | select(.free == 1)] | length | tostring),
            ([.[] | select(.free == 1) | .nm] | join(", ")) ]
        | join("\u001f")' 2>/dev/null)"

    declare -A quiet_count=() quiet_age=()
    # One note per (store, route, reason), not per bead: a queue behind a full
    # pool is the ordinary state of a busy city, and a line each would bury the
    # findings that have to be read.
    quiet() {
        local key="${1}${SEP}${2}${SEP}${3}"
        quiet_count["$key"]=$(( ${quiet_count["$key"]:-0} + 1 ))
        [ "${quiet_age["$key"]:-0}" -lt "$4" ] && quiet_age["$key"]="$4"
        return 0
    }
    while IFS="$SEP" read -r label bid route ref age; do
        [ -n "$bid" ] || continue
        case "$age" in *[!0-9]*|"") age=0 ;; esac
        case "${agent_state[$route]:-unknown}" in
            suspended)
                quiet "$label" "$route" "it is suspended, so work waiting on it is parked on purpose" "$age" ;;
            nopool)
                quiet "$label" "$route" "it has no sessions configured (pool max 0), so nothing is meant to claim them" "$age" ;;
            pool)
                total="${pool_total[$route]:-0}"
                free="${pool_free[$route]:-0}"
                if [ "$total" = "0" ]; then
                    quiet "$label" "$route" "it has no running session — a pool scaled to zero with a queue behind it is the demand probe's business, not a stalled claim" "$age"
                elif [ "$free" = "0" ]; then
                    quiet "$label" "$route" "its $total running session(s) are all holding work already — a queue behind a full pool is backpressure, not starvation" "$age"
                elif [ "$stale_roster" = "1" ]; then
                    warnings+=("$label step $bid ($ref): offered by \`bd ready\` and never claimed for ${age}m while \"$route\" appeared to have $free of $total running session(s) holding nothing — but \`gc session list\` answered from a ${cache_age}s cache, itself older than the ${STALL_MINUTES}m bound, so those sessions may have exited or taken work since. Re-run once the cache is fresh.")
                elif [ "$occupancy_partial" = "1" ]; then
                    warnings+=("$label step $bid ($ref): offered by \`bd ready\` and never claimed for ${age}m while \"$route\" has $free of $total running session(s) reading as free (${pool_names[$route]:-}) — but at least one store's in-progress beads could not be read, so a busy worker may be counted among them. Re-run once every store answers.")
                else
                    errors+=("$label step $bid ($ref): offered by \`bd ready\` and NEVER claimed for ${age}m — no assignee, no gc.claimed_at — while its route \"$route\" has $free of $total running session(s) holding nothing (${pool_names[$route]:-}). An idle worker and an offered step have not met; nudge the pool so it calls \`gc hook --claim\`, or re-sling the molecule root.")
                fi ;;
            *)
                quiet "$label" "$route" "it names no agent — an address nothing answers is check-routed-work-claimable's finding (I3), not this one" "$age" ;;
        esac
    done <<< "$(printf '%s\n' "${unclaimed[@]}")"
    if [ "${#quiet_count[@]}" -ne 0 ]; then
        while IFS="$SEP" read -r qlabel qroute qreason; do
            [ -n "$qlabel$qroute" ] || continue
            qkey="${qlabel}${SEP}${qroute}${SEP}${qreason}"
            notes+=("$qlabel: ${quiet_count[$qkey]} step(s) offered and unclaimed for up to ${quiet_age[$qkey]}m, routed to \"$qroute\" — $qreason; reported, not judged")
        done <<< "$(printf '%s\n' "${!quiet_count[@]}" | LC_ALL=C sort)"
    fi
fi

if [ "${#errors[@]}" -ne 0 ]; then
    echo "steps nothing is running (I11): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "claim-advancing partially determined (I11)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every step claimed longer than ${STALL_MINUTES}m is held by a running session that is still producing output, and every step offered that long is waiting on a pool that is suspended, empty or busy"
detail ${notes[@]+"${notes[@]}"}
exit 0
