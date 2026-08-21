#!/usr/bin/env bash
# deferred-dispatch.sh — a pending dispatch is a fact about the work, so it
# lives on the work bead.
#
# THE PROBLEM (tk-y0ygs). `gc sling` pours its formula immediately and takes no
# notice of the bead's `blocks` deps: the poured records carry `gc.root_bead_id`
# and one `tracks` edge to the workflow root, and NONE of them carries an edge
# to the work bead, so a `blocks` edge between two work beads is not on any path
# the read side walks (docs/gascity-routing-model.md, "A `blocks` dep between
# work beads does not hold a graph.v2 dispatch"). Sling a blocked bead and a
# polecat claims it within ~2 minutes.
#
# So sequencing was done by an agent REMEMBERING not to dispatch yet. That hold
# lived in one session's context and died with it: invisible to every other
# agent and to the operator, with no recovery path — if the holder died, the
# bead sat forever behind a `blocks` edge that nothing acted on, and nothing
# anywhere knew a dispatch was owed. The operator's words: "This someone or
# something needs to hold state outside of beads is a problem."
#
# THE FIX. Arm the dispatch onto the bead instead of holding it in your head:
#
#     deferred-dispatch.sh arm <bead> --target <agent> [--sling-arg X]... [--reason "..."]
#
# The intent becomes durable metadata on the work bead. This script's
# `reconcile` verb runs on a cooldown order (orders/deferred-dispatch.toml,
# scope="rig") and performs the sling once the bead is dispatchable. Nothing is
# held in an agent's context, the pending dispatch survives every session death,
# and `deferred-dispatch.sh list` answers "what dispatches are owed?" for anyone
# who asks.
#
# WHAT COUNTS AS DISPATCHABLE is not re-implemented here. `bd list --ready`
# applies beads' own readiness predicate — open, no active blocker of a blocking
# type (`blocks`/`waits-for`/`conditional-blocks`), not in_progress, blocked,
# deferred or hooked, and the parent-child blocked-flag cascade included. Asking
# bd rather than walking dependency rows is what keeps this from drifting away
# from the predicate every other reader uses.
#
# WHAT THIS IS NOT. It does not make `gc sling` itself dep-aware, and it does not
# give the poured step beads an edge to the work bead. Both of those live in the
# gc binary (gascity), not in this pack; the layer determination and what each
# would take is in specs/tk-y0ygs/layer-determination.md. This is the fix
# available at pack level, and it is the one that answers the operator's
# complaint directly: the state moves onto the bead.
#
# NOT set -e: per-bead, best-effort by contract. One bead that cannot be slung
# must not skip the beads after it, and the next cooldown retries. But a failure
# to ENUMERATE is different in kind and exits non-zero — see the loop below.
set -u

PROG="deferred-dispatch"

# --- the vocabulary ----------------------------------------------------------
# One key is the index AND the payload: `bd list --has-metadata-key` enumerates
# armed beads without needing to know any target in advance (--metadata-field
# can only match an exact value, which a per-bead target is not).
K_TARGET="gc.dispatch_when_ready"
K_ARGS="gc.dispatch_when_ready_args"
K_BY="gc.dispatch_when_ready_armed_by"
K_AT="gc.dispatch_when_ready_armed_at"
K_REASON="gc.dispatch_when_ready_reason"

BD_DB=""          # optional --db passthrough; otherwise BEADS_DIR pins the rig
DRY_RUN=0

# One EXIT trap owns every temp file. A RETURN trap per function is subtler
# than it looks and this script runs exactly one verb before exiting.
TMPFILES=()
cleanup() { [ "${#TMPFILES[@]}" -gt 0 ] && rm -f "${TMPFILES[@]}"; return 0; }
trap cleanup EXIT
mktemp_tracked() { local f; f="$(mktemp)" || return 1; TMPFILES+=("$f"); printf '%s' "$f"; }

bd_() {
    if [ -n "$BD_DB" ]; then bd --db "$BD_DB" "$@"; else bd "$@"; fi
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Who is arming. GC_AGENT is the agent address in a session; BEADS_ACTOR is what
# bd itself stamps. Either is more useful on the bead than "unknown".
actor() { printf '%s' "${GC_AGENT:-${BEADS_ACTOR:-${USER:-unknown}}}"; }

usage() {
    cat <<'EOF'
Usage:
  deferred-dispatch.sh arm <bead> --target <agent> [--sling-arg <arg>]... [--reason <text>] [--db <path>]
  deferred-dispatch.sh disarm <bead> [--reason <text>] [--db <path>]
  deferred-dispatch.sh list [--json] [--db <path>]
  deferred-dispatch.sh reconcile [--dry-run] [--db <path>]

Verbs:
  arm        Record a pending dispatch on <bead>. The sling happens later, from
             reconcile, once bd reports the bead ready. Use this instead of
             holding the dispatch in your context.
  disarm     Remove a pending dispatch. The bead is left otherwise untouched.
  list       Show every armed bead in this store and whether it is waiting,
             dispatchable now, or closed with a dispatch still owed.
  reconcile  One pass: sling every armed bead that is now ready, retire the arm
             on every armed bead that closed. Driven by
             orders/deferred-dispatch.toml (cooldown, scope="rig").

--sling-arg is repeatable and is passed through to `gc sling` verbatim after the
target and bead, e.g. --sling-arg --on --sling-arg mol-pr-from-issue.
EOF
}

# --- bd readers --------------------------------------------------------------
# `bd show <id> --json` answers an ARRAY when the id resolves and an OBJECT
# ({"error": ...}) when it does not — both at rc=0, so rc is not a discriminator
# and array-shaped jq throws on the miss. Discriminate on type.
show_bead() { # id -> single bead object on stdout, or nothing (rc 1)
    local id="$1" raw
    raw="$(bd_ show "$id" --json 2>/dev/null)" || return 1
    printf '%s' "$raw" | tr -d '\000-\010\013\014\016-\037' | jq -c '
        if type == "array" then (.[0] // empty)
        elif type == "object" then (if has("error") then empty else . end)
        else empty end' 2>/dev/null
}

meta_of() { # bead-json key -> value or empty
    printf '%s' "$1" | jq -r --arg k "$2" '(.metadata[$k] // "") | tostring' 2>/dev/null
}

# --- arm ---------------------------------------------------------------------
cmd_arm() {
    local bead="" target="" reason="" args=() a
    bead="${1:-}"; shift || true
    case "$bead" in ""|-*) echo "$PROG: arm requires a bead id" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --target) shift; target="${1:-}" ;;
            --reason) shift; reason="${1:-}" ;;
            --sling-arg) shift; args+=("${1:-}") ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: arm: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    [ -n "$target" ] || { echo "$PROG: arm requires --target <agent>" >&2; return 2; }

    local json
    json="$(show_bead "$bead")" || json=""
    [ -n "$json" ] || { echo "$PROG: arm: $bead does not resolve in this store" >&2; return 1; }

    # Refuse to arm work that is already in flight. Arming a dispatched bead
    # would queue a SECOND pour behind the first, which is the duplicate-dispatch
    # failure the load-context step exists to refuse.
    local status assignee routed exec_routed
    status="$(printf '%s' "$json" | jq -r '.status // ""')"
    assignee="$(printf '%s' "$json" | jq -r '.assignee // ""')"
    routed="$(meta_of "$json" gc.routed_to)"
    exec_routed="$(meta_of "$json" gc.execution_routed_to)"
    if [ "$status" = "closed" ]; then
        echo "$PROG: arm: $bead is closed — nothing to dispatch" >&2; return 1
    fi
    if [ "$status" = "in_progress" ] || [ -n "$routed" ] || [ -n "$exec_routed" ]; then
        echo "$PROG: arm: $bead is already dispatched (status=$status routed_to='$routed' execution_routed_to='$exec_routed') — disarm-then-rearm only if you mean to re-dispatch it" >&2
        return 1
    fi

    local args_json
    if [ "${#args[@]}" -gt 0 ]; then
        args_json="$(printf '%s\n' "${args[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" || args_json=""
        [ -n "$args_json" ] || { echo "$PROG: arm: could not encode --sling-arg values" >&2; return 1; }
    else
        args_json="[]"
    fi

    local note
    note="$PROG: dispatch armed by $(actor) at $(now_utc) — target=$target sling_args=$args_json${reason:+ reason=$reason}. It will be slung by the deferred-dispatch reconcile pass once bd reports this bead ready; nobody is holding it in context."
    bd_ update "$bead" \
        --set-metadata "$K_TARGET=$target" \
        --set-metadata "$K_ARGS=$args_json" \
        --set-metadata "$K_BY=$(actor)" \
        --set-metadata "$K_AT=$(now_utc)" \
        --set-metadata "$K_REASON=$reason" \
        --append-notes "$note" >/dev/null 2>&1 || {
            echo "$PROG: arm: failed to write the dispatch record onto $bead" >&2; return 1; }

    echo "$PROG: armed $bead -> $target${reason:+ ($reason)}"

    # An arm on an already-ready bead is legal and deliberate — it is what makes
    # `arm` a safe universal replacement for a hand-held `sling`. Say so, so the
    # caller is not surprised when it dispatches on the next pass.
    #
    # Asked through the SAME query the reconcile pass uses, not a per-id one:
    # `bd list --ready` refuses an `--id` filter outright ("--ready cannot
    # filter on IDFilter"), so a per-id readiness probe is not merely narrower,
    # it always errors. Reusing the pass's own query also means this hint and
    # the pass can never disagree. The metadata was written just above, so the
    # bead is in scope for it.
    local ready
    ready="$(bd_ list --has-metadata-key "$K_TARGET" --ready --json --limit 0 2>/dev/null \
        | jq -r --arg id "$bead" '[.[] | select(.id == $id) | .id][0] // ""' 2>/dev/null)"
    if [ "$ready" = "$bead" ]; then
        echo "$PROG: note: $bead has no open blocker right now — the next reconcile pass will dispatch it"
    fi
    if [ -n "$assignee" ]; then
        echo "$PROG: note: $bead carries assignee '$assignee' — reconcile will NOT sling over a held bead; clear it or disarm" >&2
    fi
    return 0
}

# --- disarm ------------------------------------------------------------------
disarm_bead() { # id reason -> rc
    local id="$1" reason="${2:-}"
    bd_ update "$id" \
        --unset-metadata "$K_TARGET" \
        --unset-metadata "$K_ARGS" \
        --unset-metadata "$K_BY" \
        --unset-metadata "$K_AT" \
        --unset-metadata "$K_REASON" \
        --append-notes "$PROG: dispatch record cleared at $(now_utc)${reason:+ — $reason}" >/dev/null 2>&1
}

cmd_disarm() {
    local bead="" reason=""
    bead="${1:-}"; shift || true
    case "$bead" in ""|-*) echo "$PROG: disarm requires a bead id" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason) shift; reason="${1:-}" ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: disarm: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    disarm_bead "$bead" "${reason:-disarmed by $(actor)}" || {
        echo "$PROG: disarm: failed to clear the dispatch record on $bead" >&2; return 1; }
    echo "$PROG: disarmed $bead"
}

# --- enumeration -------------------------------------------------------------
# A could-not-enumerate failure must never read as an empty queue. Every read
# here is checked and every failure exits non-zero; the caller (an order) logs
# the failure and the next cooldown retries.
armed_rows() { # writes "<id>\t<status>\t<ready 0|1>" to $1
    local out="$1" all ready_ids
    all="$(bd_ list --has-metadata-key "$K_TARGET" --all --json --limit 0 2>/dev/null)" || return 1
    [ -n "$all" ] || return 1
    printf '%s' "$all" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1

    ready_ids="$(bd_ list --has-metadata-key "$K_TARGET" --ready --json --limit 0 2>/dev/null)" || return 1
    [ -n "$ready_ids" ] || return 1
    printf '%s' "$ready_ids" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1

    printf '%s' "$all" | jq -r --argjson r "$ready_ids" '
        ($r | map(.id)) as $ready
        | .[] | [ .id, (.status // ""), (if (.id as $i | $ready | index($i)) then "1" else "0" end) ]
        | @tsv' > "$out" 2>/dev/null || return 1
    return 0
}

cmd_list() {
    local as_json=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) as_json=1 ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: list: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    local rows; rows="$(mktemp_tracked)" || { echo "$PROG: list: mktemp failed" >&2; return 1; }
    armed_rows "$rows" || { echo "$PROG: list: could not enumerate armed beads" >&2; return 1; }

    if [ "$as_json" = 1 ]; then
        bd_ list --has-metadata-key "$K_TARGET" --all --json --limit 0 2>/dev/null
        return 0
    fi

    local n=0 id status ready json target reason state
    while IFS=$'\t' read -r id status ready; do
        [ -n "${id:-}" ] || continue
        n=$((n + 1))
        json="$(show_bead "$id")" || json=""
        target=""; reason=""
        if [ -n "$json" ]; then
            target="$(meta_of "$json" "$K_TARGET")"
            reason="$(meta_of "$json" "$K_REASON")"
        fi
        if [ "$status" = "closed" ]; then state="CLOSED (dispatch no longer owed)"
        elif [ "$ready" = "1" ]; then state="DISPATCHABLE NOW"
        else state="waiting on a blocker"; fi
        printf '%s -> %s [%s]%s\n' "$id" "${target:-?}" "$state" "${reason:+ — $reason}"
    done < "$rows"
    [ "$n" -gt 0 ] || echo "$PROG: no pending dispatches in this store"
    return 0
}

# --- reconcile ---------------------------------------------------------------
sling_bead() { # id target args_json -> rc
    local id="$1" target="$2" args_json="$3" a
    local -a extra=()
    if [ "$args_json" != "[]" ] && [ -n "$args_json" ]; then
        printf '%s' "$args_json" | jq -e 'type == "array"' >/dev/null 2>&1 || return 3
        local argf; argf="$(mktemp_tracked)" || return 3
        printf '%s' "$args_json" | jq -r '.[]' > "$argf" 2>/dev/null || return 3
        while IFS= read -r a; do [ -n "$a" ] && extra+=("$a"); done < "$argf"
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "$PROG: DRY-RUN would sling: gc sling ${GC_RIG:+--rig $GC_RIG }$target $id ${extra[*]:-}"
        return 0
    fi
    if [ -n "${GC_RIG:-}" ]; then
        gc sling --rig "$GC_RIG" "$target" "$id" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1
    else
        gc sling "$target" "$id" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1
    fi
}

cmd_reconcile() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: reconcile: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done

    local rows; rows="$(mktemp_tracked)" || { echo "$PROG: reconcile: mktemp failed" >&2; return 1; }
    # Enumeration failure is NOT an empty queue. Exit non-zero so the order logs
    # it; a silent zero here would read exactly like "nothing was owed".
    armed_rows "$rows" || {
        echo "$PROG: reconcile: could not enumerate armed beads — NOT treating this as an empty queue" >&2
        return 1; }

    local expected processed=0 dispatched=0 retired=0 waiting=0 held=0 failed=0
    expected="$(wc -l < "$rows" | tr -d ' ')"

    local id status ready json target args_json assignee routed exec_routed rc
    while IFS=$'\t' read -r id status ready; do
        [ -n "${id:-}" ] || continue
        processed=$((processed + 1))

        # Armed and closed: the work is done or was disposed of. Retire the
        # record so a closed bead does not carry a dispatch nobody owes.
        if [ "$status" = "closed" ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "$PROG: DRY-RUN would retire arm on closed $id"
            elif disarm_bead "$id" "bead closed with a dispatch still armed; no dispatch owed"; then
                echo "$PROG: retired arm on closed $id"
            else
                echo "$PROG: WARN could not retire arm on closed $id" >&2; failed=$((failed + 1)); continue
            fi
            retired=$((retired + 1)); continue
        fi

        if [ "$ready" != "1" ]; then waiting=$((waiting + 1)); continue; fi

        json="$(show_bead "$id")" || json=""
        if [ -z "$json" ]; then
            echo "$PROG: WARN $id enumerated but does not resolve — leaving armed" >&2
            failed=$((failed + 1)); continue
        fi
        target="$(meta_of "$json" "$K_TARGET")"
        args_json="$(meta_of "$json" "$K_ARGS")"
        assignee="$(printf '%s' "$json" | jq -r '.assignee // ""')"
        routed="$(meta_of "$json" gc.routed_to)"
        exec_routed="$(meta_of "$json" gc.execution_routed_to)"
        [ -n "$args_json" ] || args_json="[]"

        if [ -z "$target" ]; then
            echo "$PROG: WARN $id is armed with an empty target — leaving it for a human" >&2
            failed=$((failed + 1)); continue
        fi

        # Already dispatched. Either a previous pass slung it and died before
        # clearing the record, or somebody slung it by hand. Retire the arm
        # rather than pouring a second workflow onto the same bead.
        if [ -n "$routed" ] || [ -n "$exec_routed" ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "$PROG: DRY-RUN would retire arm on already-dispatched $id"
            elif disarm_bead "$id" "already dispatched (routed_to='$routed' execution_routed_to='$exec_routed'); arm retired without a second sling"; then
                echo "$PROG: retired arm on already-dispatched $id"
            else
                echo "$PROG: WARN could not retire arm on already-dispatched $id" >&2; failed=$((failed + 1)); continue
            fi
            retired=$((retired + 1)); continue
        fi

        # Somebody holds it. Slinging would take the bead away from them. The
        # arm stays, visible in `list` and here, rather than being resolved by
        # a writer that cannot know whether the holder still wants it.
        if [ -n "$assignee" ]; then
            echo "$PROG: HELD $id is ready but assigned to '$assignee' — not slinging; disarm or clear the assignee" >&2
            held=$((held + 1)); continue
        fi

        sling_bead "$id" "$target" "$args_json"; rc=$?
        if [ "$rc" = 3 ]; then
            echo "$PROG: WARN $id has a malformed $K_ARGS ('$args_json') — leaving armed" >&2
            failed=$((failed + 1)); continue
        fi
        if [ "$rc" != 0 ]; then
            echo "$PROG: WARN sling of $id -> $target failed (rc=$rc) — leaving armed, retrying next pass" >&2
            failed=$((failed + 1)); continue
        fi
        if [ "$DRY_RUN" = 1 ]; then dispatched=$((dispatched + 1)); continue; fi

        # Sling first, disarm second. If we die between the two, the next pass
        # sees gc.routed_to/gc.execution_routed_to set and retires the arm
        # instead of slinging again.
        if disarm_bead "$id" "dispatched to $target by the deferred-dispatch reconcile pass"; then
            echo "$PROG: dispatched $id -> $target"
        else
            echo "$PROG: WARN $id was slung to $target but the arm could not be cleared — the next pass will retire it" >&2
        fi
        dispatched=$((dispatched + 1))
    done < "$rows"

    # A loop that ran fewer times than the queue held is the same blackout as an
    # unreadable queue, and it must not print a summary that reads like success.
    if [ "$processed" != "$expected" ]; then
        echo "$PROG: reconcile: enumerated $expected armed bead(s) but processed $processed — aborting rather than reporting a partial pass as complete" >&2
        return 1
    fi
    echo "$PROG: $dispatched dispatched, $retired retired, $waiting waiting, $held held, $failed failed (of $expected armed)"
    [ "$failed" = 0 ]
}

# --- main --------------------------------------------------------------------
verb="${1:-}"; shift || true
case "$verb" in
    arm)       cmd_arm "$@" ;;
    disarm)    cmd_disarm "$@" ;;
    list)      cmd_list "$@" ;;
    reconcile) cmd_reconcile "$@" ;;
    -h|--help|help|"") usage; [ -n "$verb" ] && exit 0 || exit 2 ;;
    *) echo "$PROG: unknown verb '$verb'" >&2; usage >&2; exit 2 ;;
esac
