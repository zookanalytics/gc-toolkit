#!/usr/bin/env bash
# doctor/check-root-advancing — I13: a workflow root that has started is still
# advancing, or is reachable by something that can advance it.
#
# A graph.v2 molecule runs its continuation-group steps INLINE in one pool
# session, and those step beads carry no owner and no route by construction. A
# pool session recycles routinely, so a drain landing mid-molecule leaves the
# forward steps open, unowned and unrouted. With no owner the witness's
# orphan-recovery skips them (it keys on an assignee), and with no route no pool
# is ever offered them, so the molecule advances no further and its
# workflow-finalize waits forever under the control-dispatcher. Nothing else
# fires on it: I8 is scoped to CLOSED roots, I11 to CLAIMED or ROUTED steps, and
# every recovery pass needs either an owner or a route this one has neither of.
#
# A root is reported STRANDED only when all four hold, because each of the four
# is a distinct healthy shape this must not report:
#
#   SILENT       nothing in the molecule — root or any member, in ANY status —
#                has been written within the stall bound. A close is the
#                molecule advancing and is routinely its most recent write, so
#                the bound is measured over the closed members too.
#   UNHELD       no live session stands behind it: neither the root's
#                gc.session_name nor any member's assignee, gc.session_id or
#                gc.session_name is in the running roster. A held molecule is
#                somebody's work, however long its step takes.
#   STARTED      the graph has closed at least one step, so it demonstrably
#                moved and then stopped — a molecule that never closed a step is
#                indistinguishable from an inline husk and reporting it would
#                report most of the rig — AND its work has not landed (its input
#                convoy is still open; a convoy closes when its one work bead
#                closes on land, so a closed convoy is finished work).
#   UNCLAIMABLE  its executable frontier — the members `bd ready` offers, minus
#                the inert topology kinds (workflow, scope, spec) poured
#                alongside real steps — is non-empty AND every frontier member
#                is unassigned AND unrouted (neither gc.routed_to nor
#                gc.execution_routed_to). A routed or owned frontier is
#                reachable: a pool has demand it has not gotten to, or a session
#                holds it; an empty frontier is a blocker naming the wait in the
#                graph. A member carrying an execution route is what the
#                recovery fix stamps to re-offer a strand, so a stamped molecule
#                reads as reachable here and drops out.
#
# Held on purpose is a note, not a finding: a non-empty gc.takeaway or
# hold_reason on the root or any member is an operator parking it, and the
# resting state it names is `status=blocked`, which `bd ready` never offers.
#
# Fail-safe toward silence. Every unestablished fact reports nothing rather than
# guessing, because each input misread turns a healthy molecule into a false
# escalation: an unread roster makes every molecule look unheld, an unread
# frontier makes it look unclaimable, and an unread convoy cannot prove the work
# unlanded. The roster read declines the whole run; a per-store or per-candidate
# read that fails warns and leaves that store or candidate unjudged.
#
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

STALL_MINUTES="${GC_DOCTOR_ROOT_STALL_MINUTES:-120}"
case "$STALL_MINUTES" in *[!0-9]*|"") STALL_MINUTES=120 ;; esac
STALL=$((STALL_MINUTES * 60))
SEP=$'\037'
# What a hold looks like, spliced into the root and member reads so the two
# cannot drift. `$m` is the bead's own metadata; an EMPTY value is a hold that
# was CLEARED, which is the state a released bead is left in.
HELD='((($m["gc.takeaway"] // "") | tostring) != "")
      or ((($m["hold_reason"] // "") | tostring) != "")'

errors=(); warnings=(); notes=()
declare -A held_count=() held_age=()
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

# One held note per store, not per molecule: a parked cohort is one decision,
# and a line each would bury the findings that have to be read.
held_note() {
    local key="$1" age="$2"
    case "$age" in *[!0-9]*|"") age=0 ;; esac
    held_count["$key"]=$(( ${held_count["$key"]:-0} + 1 ))
    [ "${held_age["$key"]:-0}" -lt "$age" ] && held_age["$key"]="$age"
    return 0
}

sessions_raw=$(run_bounded gc session list --json 2>/dev/null); sessions_rc=$?
sessions=$(printf '%s' "$sessions_raw" | scrub \
    | jq -c '[(.sessions // [])[]? | select(type == "object")]' 2>/dev/null)
if [ "$sessions_rc" -ne 0 ] || [ -z "$sessions" ]; then
    echo "cannot determine whether started workflow roots are advancing (I13)"
    detail "\`gc session list --json\` failed (rc=$sessions_rc) or could not be parsed; with no session set every molecule would look unheld."
    exit 1
fi
# An empty roster is a real state (a stopped city), but it cannot tell a held
# molecule from an abandoned one, so it is reported rather than judged.
if [ "$sessions" = "[]" ]; then
    echo "cannot determine whether started workflow roots are advancing (I13)"
    detail "\`gc session list --json\` listed no sessions; every molecule would classify as UNHELD against an empty roster."
    exit 1
fi
# Liveness is read from `.state` (a session is live iff state == "active"), the
# field both `gc session list --json` schemas carry. If the roster carries
# neither `state` nor `running` on any session, its schema has drifted past what
# liveness can be read from, and judging every session against the absent field
# would classify them all dead and every molecule unheld. Decline instead.
if ! printf '%s' "$sessions" | jq -e 'any(.[]?; has("state") or has("running"))' >/dev/null 2>&1; then
    echo "cannot determine whether started workflow roots are advancing (I13)"
    detail "\`gc session list --json\` returned sessions carrying neither a \`state\` nor a \`running\` field; the roster schema has drifted and liveness cannot be read. Judging every session against the absent field would classify them all dead and every molecule unheld, so this run declines rather than emit those false alarms."
    exit 1
fi
# One live identity set, keyed on every name a bead may carry an owner under.
declare -A LIVE=()
while IFS= read -r ident; do
    [ -n "$ident" ] && LIVE["$ident"]=1
done <<< "$(printf '%s' "$sessions" | jq -r '.[] | select(((.state // "") | tostring) == "active")
    | [.id, .session_name, .alias] | map(select((. // "") != "")) | .[]
    | tostring | gsub("[[:cntrl:]]"; " ")' 2>/dev/null)"

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether started workflow roots are advancing (I13)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

NOW=$(budget_now)

while IFS="$SEP" read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    db="$rig_path/.beads"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi

    roots_raw=$(run_bounded gc bd list --db "$db" --status open,in_progress --metadata-field gc.kind=workflow --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$roots_raw" ]; then
        warnings+=("$label: could not list workflow roots in $db (rc=$rc) — this store was NOT checked")
        continue
    fi
    root_rows=$(printf '%s' "$roots_raw" | scrub | jq -r '
        def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);
        .[]? | . as $r | ($r.metadata // {}) as $m
        | (($m["gc.input_convoy_id"] // "") | tostring | gsub("[[:cntrl:]]"; " ")) as $cv
        | select($cv != "")
        | [ (($r.id // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            (($m["gc.session_name"] // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            $cv,
            ((($r.updated_at // $r.created_at // "") | ep) // 0 | tostring),
            (if '"$HELD"' then "1" else "0" end),
            (($m["gc.formula_name"] // "") | tostring | gsub("[[:cntrl:]]"; " ")) ]
        | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: workflow-root listing from $db could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$root_rows" ] || continue

    steps_raw=$(run_bounded gc bd list --db "$db" --status open,in_progress,blocked --has-metadata-key gc.root_bead_id --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$steps_raw" ]; then
        warnings+=("$label: could not list step beads in $db (rc=$rc) — this store's workflow roots were NOT checked")
        continue
    fi
    step_rows=$(printf '%s' "$steps_raw" | scrub | jq -r '
        def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);
        .[]? | . as $b | ($b.metadata // {}) as $m
        | (($m["gc.root_bead_id"] // "") | tostring | gsub("[[:cntrl:]]"; " ")) as $root
        | select($root != "")
        | [ $root,
            (($b.id // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            (($b.status // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            (($b.assignee // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            (($m["gc.session_id"] // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            (($m["gc.session_name"] // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            (($m["gc.routed_to"] // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            (($m["gc.execution_routed_to"] // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            (($m["gc.kind"] // "") | tostring | gsub("[[:cntrl:]]"; " ")),
            ((($b.updated_at // $b.created_at // "") | ep) // 0 | tostring),
            (if '"$HELD"' then "1" else "0" end) ]
        | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: step listing from $db could not be parsed — this store's workflow roots were NOT checked")
        continue
    fi

    ready_raw=$(run_bounded gc bd ready --db "$db" --json --limit 0 2>/dev/null); ready_rc=$?
    if [ "$ready_rc" -ne 0 ] || [ -z "$ready_raw" ]; then
        warnings+=("$label: could not read \`bd ready\` in $db (rc=$ready_rc) — this store's workflow roots were NOT checked")
        continue
    fi
    declare -A READY=()
    while IFS= read -r rid; do
        [ -n "$rid" ] && READY["$rid"]=1
    done <<< "$(printf '%s' "$ready_raw" | scrub | jq -r '.[]? | (.id // empty) | tostring | gsub("[[:cntrl:]]"; " ")' 2>/dev/null)"

    # Group the members under their root.
    declare -A MEMBERS=() MSTATUS=() MASSIGNEE=() MSID=() MSNAME=() MROUTED=() MEXEC=() MKIND=() MUPD=() MHELD=()
    while IFS="$SEP" read -r root id status as sid sname routed erouted kind upd held; do
        [ -n "$root" ] && [ -n "$id" ] || continue
        MEMBERS["$root"]="${MEMBERS[$root]:-} $id"
        MSTATUS["$id"]="$status"; MASSIGNEE["$id"]="$as"; MSID["$id"]="$sid"; MSNAME["$id"]="$sname"
        MROUTED["$id"]="$routed"; MEXEC["$id"]="$erouted"; MKIND["$id"]="$kind"; MUPD["$id"]="$upd"; MHELD["$id"]="$held"
    done <<< "$step_rows"

    # Candidates that clear the in-memory gates, carried into the probe phase.
    survivors=()
    declare -A S_CONVOY=() S_LT=() S_FRONTIER=() S_SNAME=() S_FORMULA=()
    while IFS="$SEP" read -r root sname convoy rupd rheld formula; do
        [ -n "$root" ] || continue

        # SILENT (cheap half): last-touch over the root and its non-closed
        # members. A recent write means the molecule is still moving.
        lt="$rupd"; case "$lt" in *[!0-9]*|"") lt=0 ;; esac
        for m in ${MEMBERS[$root]:-}; do
            mu="${MUPD[$m]:-0}"; case "$mu" in *[!0-9]*|"") mu=0 ;; esac
            [ "$mu" -gt "$lt" ] && lt="$mu"
        done
        [ "$lt" -gt 0 ] || continue          # no parseable time: silence unestablished
        [ $((NOW - lt)) -gt "$STALL" ] || continue

        # UNHELD: any live session behind the root or a member exempts it.
        [ -n "${LIVE[$sname]:-}" ] && continue
        alive=0
        for m in ${MEMBERS[$root]:-}; do
            for who in "${MASSIGNEE[$m]:-}" "${MSID[$m]:-}" "${MSNAME[$m]:-}"; do
                [ -n "$who" ] && [ -n "${LIVE[$who]:-}" ] && { alive=1; break; }
            done
            [ "$alive" = "1" ] && break
        done
        [ "$alive" = "1" ] && continue

        # Held on purpose: a parked molecule is a note, not a finding.
        onpurpose="$rheld"
        if [ "$onpurpose" != "1" ]; then
            for m in ${MEMBERS[$root]:-}; do
                [ "${MHELD[$m]:-0}" = "1" ] && { onpurpose=1; break; }
            done
        fi
        if [ "$onpurpose" = "1" ]; then
            held_note "$label" "$(( (NOW - lt) / 60 ))"
            continue
        fi

        # UNCLAIMABLE: the executable frontier, and whether any of it is reachable.
        frontier=""; reachable=0
        for m in ${MEMBERS[$root]:-}; do
            [ -n "${READY[$m]:-}" ] || continue
            case "${MKIND[$m]:-}" in workflow|scope|spec) continue ;; esac  # inert topology
            frontier="${frontier}${m} "
            if [ -n "${MASSIGNEE[$m]:-}" ] || [ -n "${MROUTED[$m]:-}" ] || [ -n "${MEXEC[$m]:-}" ]; then
                reachable=1
            fi
        done
        [ -n "$frontier" ] || continue       # empty frontier: a blocker names the wait
        [ "$reachable" = "0" ] || continue    # routed or owned: reachable

        survivors+=("$root")
        S_CONVOY["$root"]="$convoy"; S_LT["$root"]="$lt"; S_FRONTIER["$root"]="${frontier% }"
        S_SNAME["$root"]="$sname"; S_FORMULA["$root"]="$formula"
    done <<< "$root_rows"

    if [ "${#survivors[@]}" -ne 0 ]; then
        # Landed check, batched: a survivor's input convoy is closed once its one
        # work bead closes on land. An unreadable convoy cannot prove the work
        # unlanded, so those survivors go unjudged rather than reported.
        cids=""
        for root in "${survivors[@]}"; do cids="${cids}${S_CONVOY[$root]},"; done
        declare -A CSTATUS=()
        convoy_ok=1
        convoy_raw=$(run_bounded gc bd list --db "$db" --id "${cids%,}" --all --json --limit 0 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$convoy_raw" ]; then
            convoy_ok=0
        else
            while IFS="$SEP" read -r cid cstatus; do
                [ -n "$cid" ] && CSTATUS["$cid"]="$cstatus"
            done <<< "$(printf '%s' "$convoy_raw" | scrub | jq -r '.[]? | select(type == "object")
                | [ (((.id // "") | tostring) | gsub("[[:cntrl:]]"; " ")),
                    (((.status // "") | tostring) | gsub("[[:cntrl:]]"; " ")) ] | join("\u001f")' 2>/dev/null)"
        fi

        for root in "${survivors[@]}"; do
            convoy="${S_CONVOY[$root]}"
            if [ "$convoy_ok" != "1" ] || [ -z "${CSTATUS[$convoy]:-}" ]; then
                warnings+=("$label root $root: its input convoy $convoy could not be read, so 'work not landed' is unproven — NOT judged")
                continue
            fi
            [ "${CSTATUS[$convoy]}" = "closed" ] && continue   # work landed

            # STARTED and SILENT (full): the closed members, read per survivor.
            closed_raw=$(run_bounded gc bd list --db "$db" --metadata-field gc.root_bead_id="$root" --status closed --json --limit 0 2>/dev/null)
            if [ $? -ne 0 ] || [ -z "$closed_raw" ]; then
                warnings+=("$label root $root: its closed steps could not be read, so 'started' and full silence are unproven — NOT judged")
                continue
            fi
            read -r closed_count closed_lt <<< "$(printf '%s' "$closed_raw" | scrub | jq -r '
                def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);
                [ .[]? | select(type == "object") ] as $c
                | [ ($c | length),
                    ([ $c[] | ((.updated_at // .created_at // "") | ep) // 0 ] | max // 0) ]
                | join(" ")' 2>/dev/null)"
            case "$closed_count" in *[!0-9]*|"") closed_count=0 ;; esac
            case "$closed_lt" in *[!0-9]*|"") closed_lt=0 ;; esac

            lt="${S_LT[$root]}"; [ "$closed_lt" -gt "$lt" ] && lt="$closed_lt"
            [ $((NOW - lt)) -gt "$STALL" ] || continue     # a step closed recently: still advancing
            [ "$closed_count" -gt 0 ] || continue          # never started: an inline husk, not a strand

            mins=$(( (NOW - lt) / 60 ))
            owner="${S_SNAME[$root]:-}"; [ -n "$owner" ] || owner="(no session recorded on the root)"
            fr="${S_FRONTIER[$root]}"; fr_n=$(printf '%s\n' $fr | grep -c .)
            errors+=("$label root $root (${S_FORMULA[$root]:-?}): STRANDED — silent ${mins}m, its session \"$owner\" is gone, $closed_count step(s) closed, work bead not landed (convoy $convoy open), and its executable frontier is unreachable: $fr_n step(s) [$(echo $fr | tr ' ' ',')] open, unassigned AND unrouted, so no pool can be offered them and the witness's orphan recovery, which keys on an assignee, cannot reach them. Give the frontier a route so it re-offers, or dispose the molecule.")
        done
        unset -v CSTATUS
    fi

    unset -v READY MEMBERS MSTATUS MASSIGNEE MSID MSNAME MROUTED MEXEC MKIND MUPD MHELD
    unset -v S_CONVOY S_LT S_FRONTIER S_SNAME S_FORMULA
done <<< "$scopes"

if [ "${#held_count[@]}" -ne 0 ]; then
    while IFS= read -r hlabel; do
        [ -n "$hlabel" ] || continue
        notes+=("$hlabel: ${held_count[$hlabel]} started, session-less molecule(s) held on purpose — gc.takeaway or hold_reason on the root or a member — silent up to ${held_age[$hlabel]}m; reported, not judged")
    done <<< "$(printf '%s\n' "${!held_count[@]}" | LC_ALL=C sort)"
fi

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and a store skipped for time is not a store that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "workflow roots stranded mid-flight (I13): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "root-advancing partially determined (I13)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every started workflow root whose session is gone and whose work has not landed either advanced within ${STALL_MINUTES}m or keeps a routed/owned frontier a pool or recovery can still reach"
detail ${notes[@]+"${notes[@]}"}
exit 0
