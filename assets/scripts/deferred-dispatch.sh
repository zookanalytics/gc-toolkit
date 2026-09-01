#!/usr/bin/env bash
# deferred-dispatch.sh — a pending dispatch is a fact about the work, so it
# lives on the work bead, not in an agent's context. `gc sling` pours
# immediately and reads no `blocks` deps, so sequencing needs a durable hold:
#   arm <bead> --target <agent> [--sling-arg X]... [--reason "..."]
# records the intent as metadata; `reconcile` (orders/deferred-dispatch.toml,
# cooldown, scope="rig") performs the sling once `bd list --ready` — beads' own
# readiness predicate, never re-implemented here — reports the bead ready.
# `list` answers "what dispatches are owed?"; `disarm` withdraws one.
# Callers: agents sequencing dependent work; the deferred-dispatch order.
#
# Per-bead best-effort (one bad bead never skips the rest; the next cooldown
# retries), but a failure to ENUMERATE exits non-zero — an unreadable queue
# must never read as an empty one.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

PROG="deferred-dispatch"

# One key is index AND payload: `bd list --has-metadata-key` enumerates armed
# beads without knowing any target in advance.
K_TARGET="gc.dispatch_when_ready"
K_ARGS="gc.dispatch_when_ready_args"
K_BY="gc.dispatch_when_ready_armed_by"
K_AT="gc.dispatch_when_ready_armed_at"
K_REASON="gc.dispatch_when_ready_reason"

# The store, pinned: `gc bd` resolves its ledger from the invoking rig and
# ignores BEADS_DIR, so an unpinned read in the rig-scoped order env answers
# about whatever rig gc resolves rather than the one the pass is for.
# `--db` overrides it.
BD_DB="${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}"
DRY_RUN=0

TMPFILES=()
cleanup() { [ "${#TMPFILES[@]}" -gt 0 ] && rm -f "${TMPFILES[@]}"; return 0; }
trap cleanup EXIT
mktemp_tracked() { local f; f="$(mktemp)" || return 1; TMPFILES+=("$f"); printf '%s' "$f"; }

bd_() {
    if [ -n "$BD_DB" ]; then gc bd --db "$BD_DB" "$@"; else gc bd "$@"; fi
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

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

# `bd show --json` answers an array on a hit and an {"error":...} object on a
# miss, both at rc=0 — discriminate on type, not exit status.
show_bead() { # id -> single bead object on stdout, or nothing (rc 1)
    local id="$1" raw
    raw="$(bd_ show "$id" --json 2>/dev/null)" || return 1
    printf '%s' "$raw" | scrub | jq -c '
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

    # Arming already-dispatched work would queue a second pour behind the first.
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

    # Asked through the SAME query reconcile uses: bd refuses --ready with an
    # --id filter, and reusing the pass's query keeps hint and pass agreeing.
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

# Unreadable is not empty: every read is checked and any failure returns 1.
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
    armed_rows "$rows" || {
        echo "$PROG: reconcile: could not enumerate armed beads — NOT treating this as an empty queue" >&2
        return 1; }

    local expected processed=0 dispatched=0 retired=0 waiting=0 held=0 failed=0
    expected="$(wc -l < "$rows" | tr -d ' ')"

    local id status ready json target args_json assignee routed exec_routed rc
    while IFS=$'\t' read -r id status ready; do
        [ -n "${id:-}" ] || continue
        processed=$((processed + 1))

        # Armed and closed: retire the record, no dispatch is owed.
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

        # Already routed (a pass died between sling and disarm, or a hand
        # sling): retire the arm rather than pour a second workflow.
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

        # Held: slinging would take the bead away from its assignee.
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

    # A partial pass must not print a summary that reads like success.
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
