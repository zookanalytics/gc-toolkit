#!/usr/bin/env bash
# deferred-dispatch.sh — a pending dispatch is a fact about the work, so it
# lives on the work bead, not in an agent's context. `gc sling` pours
# immediately and reads no `blocks` deps, so sequencing needs a durable hold:
#   arm <bead> --target <agent> [--sling-arg X]... [--reason "..."]
# records the intent as metadata; `reconcile` (orders/deferred-dispatch.toml,
# cooldown, scope="rig") performs the sling once the bead's own `blocks` edges
# have all closed. It reads `bd list --ready` as the fast path, and ALSO
# dispatches an open bead that bd holds unready only through a blocked or
# deferred ANCESTOR: the is_blocked flag cascades DOWN parent-child edges, so an
# armed epic child whose own blockers have closed never enters `bd --ready`
# while its container waits on a human gate — and the arm waits on the bead's
# own blockers, not its ancestors'. Status still gates: a non-open bead is a
# deliberate hold and is never dispatched. `list` answers "what dispatches are
# owed?"; `disarm` withdraws one.
#
# `arm` is the default move for a blocked follow-up you file or hold by hand:
# arm it instead of leaving it unrouted for someone to route once its blocker
# lands, and the reconcile pass routes it the moment bd reports it ready — so a
# sitting can queue everything and drain, with nothing left to remember. The
# bead resolves by id, so the arm lands from any seat, rig-scoped or not.
# Callers: agents sequencing dependent work; first-reaction-dispose.sh
# --then-route; the deferred-dispatch order. doctor/check-blocked-work-armed
# flags a blocked work bead that was never armed and carries no route.
#
# Per-bead best-effort (one bad bead never skips the rest; the next cooldown
# retries), but a failure to ENUMERATE exits non-zero — an unreadable queue
# must never read as an empty one.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

PROG="deferred-dispatch"

# One key is index AND payload: `bd list --has-metadata-key` enumerates armed
# beads without knowing any target in advance.
K_TARGET="gc.dispatch_when_ready"
K_ARGS="gc.dispatch_when_ready_args"
K_BY="gc.dispatch_when_ready_armed_by"
K_AT="gc.dispatch_when_ready_armed_at"
K_REASON="gc.dispatch_when_ready_reason"
# reconcile's own idempotency marker: a two-state record it stamps around its
# sling and clears by disarm. "slinging@<ts>" is written immediately before the
# sling and marks an attempt in flight but NOT proven; "slung@<ts>" replaces it
# the instant the sling returns success and marks the dispatch proven. Only a
# proven marker lets a later pass retire an arm without slinging again: a
# surviving "slinging@" is an attempt that never confirmed (a pass that died
# before or during its sling, or a failed sling whose rollback did not land), so
# recovery re-slings rather than retire an arm that may never have dispatched. A
# marker with no state prefix is read as proven, so an arm already mid-dispatch
# reads as done, not as a fresh attempt. Recovery keys on this one owned marker,
# never on the stamps a sling leaves (gc.routed_to for a plain pool sling,
# gc.execution_routed_to for an --on pour), which differ by delivery lane.
K_SLUNG="gc.dispatch_when_ready_slung"
SLUNG_TRYING="slinging@"   # value prefix: sling attempt in flight, not proven
SLUNG_DONE="slung@"        # value prefix: sling returned success, arm may retire

# `gc sling` mints an input convoy on every call, so a sling that never
# finalizes must not be re-attempted forever — that leaks one convoy per pass.
# This counter is the retry's memory: it lives on the bead, counts sling
# attempts, and once they reach the cap reconcile stops re-slinging and hands the
# bead to a person rather than minting convoy after convoy. It is cleared by
# disarm, so a proven dispatch resets the budget and clearing it by hand re-arms.
# Modeled on record-failure-cap.sh, the same pattern for merge.sh's record retry.
K_FAILS="gc.dispatch_when_ready_fail_count"
MAX_SLING_FAILURES="${GC_MAX_DISPATCH_SLING_FAILURES:-3}"
case "$MAX_SLING_FAILURES" in ''|*[!0-9]*) MAX_SLING_FAILURES=3 ;; esac

# The store, pinned: `gc bd` resolves its ledger from the invoking rig and
# ignores BEADS_DIR, so an unpinned read in the rig-scoped order env answers
# about whatever rig gc resolves rather than the one the pass is for.
# `--db` overrides it.
BD_DB="${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}"
DRY_RUN=0

# The retry cap hands a stuck dispatch to a person through escalate.sh (one open
# visit per bead, deduped on the key). Resolve it beside this script; the env
# override lets the hermetic test point it at a stub.
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ESCALATE="${GC_ESCALATE_TOOL:-$SCRIPTS_DIR/escalate.sh}"

TMPFILES=()
cleanup() { [ "${#TMPFILES[@]}" -gt 0 ] && rm -f "${TMPFILES[@]}"; return 0; }
trap cleanup EXIT
# Answers in $REPLY rather than on stdout, because a caller writing
# `f="$(mktemp_tracked)"` would run the append inside a command-substitution
# subshell: the registry the EXIT trap reads is the caller's, and the
# subshell's copy of it dies with the substitution, leaking every allocation.
mktemp_tracked() { REPLY="$(mktemp "${TMPDIR:-/tmp}/gctk-deferred-dispatch.XXXXXX")" || return 1; TMPFILES+=("$REPLY"); }

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
             reconcile, once bd reports the bead ready. This is the move for a
             blocked follow-up you file or hold by hand: arm it instead of
             leaving it unrouted for someone to route once its blocker lands,
             so you can queue everything and drain with nothing to remember.
             The bead must be open — reconcile dispatches from the --ready
             listing, which excludes every other status, so an arm on a held
             bead could never fire.
  disarm     Remove a pending dispatch. The bead is left otherwise untouched.
  list       Show every armed bead in this store and whether it is waiting,
             dispatchable now, or closed with a dispatch still owed.
  reconcile  One pass: sling every armed bead that is now ready, retire the arm
             on every armed bead that closed or that another path already
             delivered (a merge_result stamp), and — because each sling mints an
             input convoy — stop re-slinging and escalate a bead whose dispatch
             has failed to finalize MAX_SLING_FAILURES times rather than leak a
             convoy per pass. Driven by orders/deferred-dispatch.toml (cooldown,
             scope="rig").

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

# The armed-set snapshot armed_rows already read, reused instead of a `bd show`
# per bead. That per-bead read summed past the reconcile order's 120s budget once
# the armed set grew (with the per-bead dep-list, the other half of the same
# N+1), so a full pass was killed before it dispatched and owed arms silently
# starved. The snapshot carries every field a caller reads here (status,
# assignee, metadata), so nothing is lost but freshness, and the pass reads it
# consistently: the slung marker and the fail count are written only by this pass
# (the order is single-flight, rig-scoped), so the snapshot is authoritative for
# them; status was already read from the snapshot for the closed-retire; and
# merge_result and assignee are now read from it too, one pass staler than the
# prior fresh per-bead show. A bead delivered or claimed in the pass window is
# therefore acted on from the pass-start view — at worst one redundant sling
# before the next pass retires it from its own snapshot — and the fail-count cap
# bounds a redundant sling that never finalizes. The pass is now seconds, not
# minutes, so that window is small. The file is pre-scrubbed, so a raw C0 byte
# cannot abort the read.
bead_from_cache() { # all_json_file id -> single bead object on stdout, or nothing (rc 1)
    local f="$1" id="$2" out
    out="$(jq -c --arg id "$id" 'map(select(.id == $id)) | (.[0] // empty)' "$f" 2>/dev/null)" || return 1
    [ -n "$out" ] || return 1
    printf '%s' "$out"
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
    # gc.execution_routed_to is not such a dispatch: it is execution provenance
    # stamped on a workflow-driven bead, and no worker or pool-demand pass reads
    # it (they read gc.routed_to). A blocked bead carrying only it is the shape
    # doctor/check-blocked-work-armed flags and points at arming to fix, so
    # refusing on it would turn that remedy into a dead end.
    local status assignee routed slung
    status="$(printf '%s' "$json" | jq -r '.status // ""')"
    assignee="$(printf '%s' "$json" | jq -r '.assignee // ""')"
    routed="$(meta_of "$json" gc.routed_to)"
    slung="$(meta_of "$json" "$K_SLUNG")"
    if [ "$status" = "closed" ]; then
        echo "$PROG: arm: $bead is closed — nothing to dispatch" >&2; return 1
    fi
    # A gc.dispatch_when_ready_slung marker in either state means reconcile is
    # mid-dispatch on a prior arm: "slinging@" an attempt in flight, "slung@" one
    # it has proven and is about to retire. Re-arming over either stacks a second
    # dispatch, so refuse; disarm first if you truly mean to re-dispatch.
    if [ "$status" = "in_progress" ] || [ -n "$routed" ] || [ -n "$slung" ]; then
        echo "$PROG: arm: $bead is already dispatched (status=$status routed_to='$routed'${slung:+ slung_marker=$slung}) — disarm-then-rearm only if you mean to re-dispatch it" >&2
        return 1
    fi
    # `bd list --ready` answers OPEN beads only: it excludes by status before it
    # ever looks at deps, so a depless `blocked` bead is as unready as a gated
    # one. An arm recorded on any other live status can therefore never fire,
    # and nothing re-derives status from the dep graph — the hold is cleared by
    # whoever set it. Refusing here is the difference between a caller learning
    # that now and an arm that reads as "waiting on a blocker" forever.
    if [ "$status" != "open" ]; then
        echo "$PROG: arm: $bead is status=$status, and reconcile dispatches from 'bd list --ready', which answers open beads only — this arm could never fire. Clear the hold, then arm it." >&2
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

    # The hint asks the same in-store question reconcile dispatches on: are the
    # bead's own `blocks` edges all closed? The bead is open here (refused above
    # otherwise), so an all-clear means the next pass slings it whether or not a
    # blocked ancestor keeps it out of `bd --ready`. But bd resolves dependencies
    # within a single store, so a `blocks` edge to a bead in another rig holds
    # nothing here: own_blocks_cleared and `bd list --ready` both miss it, and the
    # next pass slings the arm while that blocker is still open. `bd list --id`
    # renders the raw edge even when its target has no in-store row, so name any
    # unresolvable blocker rather than let the "no open blocker" hint stand on it.
    # This is the one place a human is here to redirect the sequencing.
    #
    # own_blocks_unresolved_ids reports three outcomes and the hint turns on all
    # three. A non-zero rc means the bead's edges were not read: the cross-store
    # check is unproven, so the "no open blocker" all-clear must not stand on it,
    # any more than it may stand on a named cross-store blocker. A non-empty
    # stdout names an unresolvable blocker. An empty stdout with rc 0 is a proven
    # absence, the only outcome that earns the in-store all-clear.
    local unresolved="" unresolved_rc=0
    unresolved="$(own_blocks_unresolved_ids "$bead")" || unresolved_rc=$?
    if [ "$unresolved_rc" -ne 0 ]; then
        echo "$PROG: warning: $bead — could not enumerate its 'blocks' edges to check for a cross-store blocker, so whether reconcile will dispatch it with such a blocker still open is unproven. Check its blockers by hand if the ordering matters." >&2
    elif [ -n "$unresolved" ]; then
        echo "$PROG: warning: $bead has a 'blocks' edge to $unresolved, which has no row in this store. bd resolves dependencies within a single store, so this cross-rig or external blocker does not hold the arm: reconcile will dispatch $bead with $unresolved still open. Sequence it by hand if that ordering matters." >&2
    elif own_blocks_cleared "$bead"; then
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
        --unset-metadata "$K_SLUNG" \
        --unset-metadata "$K_FAILS" \
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

# The arm waits on the bead's OWN blockers, a narrower question than `bd list
# --ready`. `--ready` also excludes a bead held only by a blocked or deferred
# ANCESTOR, because the is_blocked flag cascades DOWN parent-child edges: an
# armed child of an epic that is itself blocked (e.g. on a human demand gate)
# never enters `bd --ready`, though its own work is ready the moment its own
# blockers close. So reconcile asks this question directly of a bead bd holds
# unready — is every one of its own `blocks` blockers closed? — and dispatches
# on a yes. Fail closed: an unreadable or non-array dep list returns non-zero, so
# the bead is left armed and retried, never slung on a guess. The parent-child
# edge is not a blocks edge and is ignored; the status gate lives in the caller.
own_blocks_cleared() { # id -> rc 0 if every own `blocks` edge is closed
    local id="$1" deps open_blk
    deps="$(bd_ dep list "$id" --json 2>/dev/null)" || return 1
    [ -n "$deps" ] || return 1
    printf '%s' "$deps" | scrub | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    open_blk="$(printf '%s' "$deps" | scrub | jq -r \
        '[ .[] | select(.dependency_type == "blocks") | select(.status != "closed") ] | length' 2>/dev/null)"
    case "$open_blk" in ''|*[!0-9]*) return 1 ;; esac
    [ "$open_blk" -eq 0 ]
}

# A `blocks` edge whose target has no row in the bead's own store — a cross-rig
# or external blocker. bd resolves dependencies within a single store, so `bd dep
# list` leaves such an edge out of its array (warning on stderr), as do `bd
# show`'s resolved `dependencies` and `bd list --ready`; own_blocks_cleared never
# sees it. `bd list --id` still renders the raw edge. This names the difference:
# the ids the bead's raw `blocks` edges point at that `bd dep list` does not
# resolve. Both reads name only the bead's own id, so `gc bd` answers both from
# the store that holds the bead whether or not --db pins one. A read naming a
# blocker id would not be safe unpinned: `gc bd` routes it to the store that
# holds the blocker, which finds the row and reports a cross-store blocker as
# present. `bd dep list` resolves an in-store gate blocker that a default listing
# hides, so such a blocker is not mistaken for a missing one. Echoes the ids
# comma-joined, or nothing. Returns non-zero when either read fails or the
# listing carries no row for the bead, so an edge set that was never read cannot
# pass for "no cross-store blocker".
own_blocks_unresolved_ids() { # id -> "<blocker-id>[,<blocker-id>...]" on stdout
    local id="$1" edges raw_ids deps
    edges="$(bd_ list --id "$id" --brief --json 2>/dev/null)" || return 1
    printf '%s' "$edges" | scrub | jq -e --arg id "$id" 'type == "array" and any(.[]; .id == $id)' >/dev/null 2>&1 || return 1
    raw_ids="$(printf '%s' "$edges" | scrub | jq -c --arg id "$id" '
        [ .[] | select(.id == $id) | (.dependencies // [])[]
          | select(.type == "blocks") | .depends_on_id ]
        | unique' 2>/dev/null)" || return 1
    [ -n "$raw_ids" ] || return 1
    [ "$raw_ids" != "[]" ] || return 0
    deps="$(bd_ dep list "$id" --json 2>/dev/null)" || return 1
    printf '%s' "$deps" | scrub | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    printf '%s' "$deps" | scrub | jq -r --argjson raw "$raw_ids" '
        [ .[] | select(.dependency_type == "blocks") | .id ] as $resolved
        | $raw
        | map(select(. as $b | ($resolved | index($b)) | not))
        | join(",")' 2>/dev/null
}

# The own-blockers-clear gate (the second-chance dispatch gate), resolved for a
# whole candidate set in a BOUNDED number of reads rather than a `bd dep list`
# per bead. The per-bead form summed past the reconcile order's 120s budget as
# the armed set grew, so a full pass was killed before it dispatched and owed
# arms silently starved — the N+1 this replaces. The blocker ids come off the
# snapshot's OWN dependency edges (`bd list --json` already carries them in the
# list-edge shape, so no dep-list call is needed and the single-id-vs-batch shape
# flip of `bd dep list` never arises), and ONE listing resolves their statuses.
# Fail closed per candidate: a blocker whose row cannot be read leaves its
# candidate not-cleared (0), exactly as the per-bead probe's non-array return
# did, so the arm stays armed and the next pass retries rather than slinging on a
# guess. The status LISTING failing outright returns non-zero, degrading the
# whole pass to "could not enumerate" the way a failed --all read does.
resolve_own_cleared() { # all_json  cand_id...  ->  "<id>\t<0|1>" per candidate
    local all="$1"; shift
    [ "$#" -gt 0 ] || return 0
    local cand_json blocker_ids blk_raw blockers
    cand_json="$(printf '%s\n' "$@" | jq -R . | jq -sc .)" || return 1
    # Distinct `blocks` blockers of every candidate, read off the snapshot's own
    # edges (list-edge shape: {issue_id: self, depends_on_id: blocker, type}).
    blocker_ids="$(printf '%s' "$all" | scrub | jq -r --argjson c "$cand_json" '
        [ .[] | select(.id as $i | ($c | index($i)))
          | (.dependencies // [])[] | select(.type == "blocks") | .depends_on_id ]
        | unique | join(",")' 2>/dev/null)" || return 1
    blockers='[]'
    if [ -n "$blocker_ids" ]; then
        # A `blocks` blocker can be any bead class, and gate/infra/template
        # blockers are common (a graduation gate blocking a convoy child); bd list
        # hides those classes unless asked, so a hidden blocker would drop and
        # read as unresolved. --id also silently drops an id with no row, so a
        # blocker still absent from the join below is treated as unresolved (its
        # candidate stays not-cleared), never as closed — an unread blocker must
        # not read as a released one.
        blk_raw="$(bd_ list --id "$blocker_ids" --all --include-gates --include-infra --include-templates --brief --json --limit 0 2>/dev/null)" || return 1
        printf '%s' "$blk_raw" | scrub | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
        blockers="$(printf '%s' "$blk_raw" | scrub | jq -c '[ .[]? | {id, status} ]' 2>/dev/null)" || return 1
        [ -n "$blockers" ] || blockers='[]'
    fi
    # Join per candidate: cleared (1) iff it has no `blocks` blocker whose status
    # is unresolved or not closed.
    printf '%s' "$all" | scrub | jq -r --argjson c "$cand_json" --argjson bl "$blockers" '
        ($bl | map({key: .id, value: .status}) | from_entries) as $smap
        | .[] | select(.id as $i | ($c | index($i))) | .id as $id
        | [ (.dependencies // [])[] | select(.type == "blocks") | .depends_on_id ] as $blks
        | (if   ([ $blks[] | select($smap[.] == null)     ] | length) > 0 then 0
           elif ([ $blks[] | select($smap[.] != "closed") ] | length) > 0 then 0
           else 1 end) as $cleared
        | "\($id)\t\($cleared)"' 2>/dev/null
}

# Unreadable is not empty: every enumeration read is checked and any failure
# returns 1. The fourth column, own_cleared, is the second-chance dispatch gate:
# 1 for an OPEN bead that bd holds unready but whose own `blocks` edges have all
# closed (held only by an ancestor cascade). A bd-ready bead needs no probe and a
# non-open one is a hold, so the probe runs only on the open-but-unready rows —
# resolved for all of them at once by resolve_own_cleared. The snapshot is cached
# to all_out so the list and reconcile loops read each bead's fields from it
# instead of a `bd show` per bead.
armed_rows() { # rows_out all_out : "<id>\t<status>\t<bd_ready 0|1>\t<own_cleared 0|1>" per bead; caches the snapshot to all_out
    local out="$1" all_out="$2" all ready_ids base id status ready cand_ids=() cleared_map=""
    # --brief on both reads: this function and its cache consumers use only id,
    # status, assignee, metadata and dependency edges, all of which --brief
    # keeps; it drops only the free-form text that makes a row heavy on the
    # shared store.
    all="$(bd_ list --has-metadata-key "$K_TARGET" --all --brief --json --limit 0 2>/dev/null)" || return 1
    [ -n "$all" ] || return 1
    printf '%s' "$all" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1

    ready_ids="$(bd_ list --has-metadata-key "$K_TARGET" --ready --brief --json --limit 0 2>/dev/null)" || return 1
    [ -n "$ready_ids" ] || return 1
    printf '%s' "$ready_ids" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1

    printf '%s' "$all" | scrub > "$all_out" || return 1

    # Both snapshots grow with the armed set, and a single --argjson value past
    # the kernel per-argument size cap fails the whole enumeration. Both reach
    # jq over stdin instead: `input` is the ready snapshot, `inputs` the --all
    # snapshot.
    base="$( { printf '%s' "$ready_ids"; printf '\n'; printf '%s' "$all"; } | jq -rn '
        (input | map(.id)) as $ready
        | inputs | .[]
        | [ .id, (.status // ""), (if (.id as $i | $ready | index($i)) then "1" else "0" end) ]
        | @tsv' 2>/dev/null)" || return 1

    while IFS=$'\t' read -r id status ready; do
        [ -n "$id" ] || continue
        [ "$ready" != "1" ] && [ "$status" = "open" ] && cand_ids+=("$id")
    done <<< "$base"

    if [ "${#cand_ids[@]}" -gt 0 ]; then
        cleared_map="$(resolve_own_cleared "$all" "${cand_ids[@]}")" || return 1
    fi

    # Join the own_cleared answers back onto the base rows in one awk pass
    # (in-memory, no bd read): a candidate absent from the map defaults to 0.
    awk -F'\t' '
        NR==FNR { if ($1 != "") cl[$1] = $2; next }
        $1 != "" { printf "%s\t%s\t%s\t%s\n", $1, $2, $3, (($1 in cl) ? cl[$1] : 0) }
    ' <(printf '%s\n' "$cleared_map") <(printf '%s\n' "$base") > "$out" || return 1
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
    local rows all_cache
    mktemp_tracked || { echo "$PROG: list: mktemp failed" >&2; return 1; }; rows="$REPLY"
    mktemp_tracked || { echo "$PROG: list: mktemp failed" >&2; return 1; }; all_cache="$REPLY"
    armed_rows "$rows" "$all_cache" || { echo "$PROG: list: could not enumerate armed beads" >&2; return 1; }

    if [ "$as_json" = 1 ]; then
        bd_ list --has-metadata-key "$K_TARGET" --all --json --limit 0 2>/dev/null
        return 0
    fi

    local n=0 id status ready owncleared json target reason slung state mr fails
    while IFS=$'\t' read -r id status ready owncleared; do
        [ -n "${id:-}" ] || continue
        n=$((n + 1))
        json="$(bead_from_cache "$all_cache" "$id")" || json=""
        target=""; reason=""; slung=""; mr=""; fails=0
        if [ -n "$json" ]; then
            target="$(meta_of "$json" "$K_TARGET")"
            reason="$(meta_of "$json" "$K_REASON")"
            slung="$(meta_of "$json" "$K_SLUNG")"
            mr="$(meta_of "$json" merge_result)"
            fails="$(meta_of "$json" "$K_FAILS")"; case "$fails" in ''|*[!0-9]*) fails=0 ;; esac
        fi
        # Not-ready splits three ways, and conflating them is what hides a dead
        # arm: an OPEN bead with an open own-blocker is waiting on something that
        # can clear; an OPEN bead whose own blockers have all closed is
        # dispatchable now and held out of `bd --ready` only by an ancestor
        # cascade (reconcile slings it anyway); any other live status is excluded
        # by `--ready` on the status itself, so no blocker closing will make it
        # dispatchable.
        if [ "$status" = "closed" ]; then state="CLOSED (dispatch no longer owed)"
        elif [ -n "$mr" ]; then state="DELIVERED — merge_result=$mr (arm retires next pass, no sling)"
        elif [ -n "$slung" ]; then
            case "$slung" in
                "$SLUNG_TRYING"*) state="dispatch in flight (attempt not yet confirmed)" ;;
                *)                state="dispatched (arm pending retirement)" ;;
            esac
        elif [ "$fails" -ge "$MAX_SLING_FAILURES" ]; then state="CAPPED — $fails sling failures, escalated; disarm or clear $K_FAILS"
        elif [ "$ready" = "1" ]; then state="DISPATCHABLE NOW"
        elif [ "$owncleared" = "1" ]; then state="DISPATCHABLE NOW (own blockers clear; held out of bd --ready only by a blocked/deferred ancestor)"
        elif [ "$status" != "open" ]; then state="STRANDED — status=$status is never --ready"
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
        local argf; mktemp_tracked || return 3; argf="$REPLY"
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

    local rows all_cache
    mktemp_tracked || { echo "$PROG: reconcile: mktemp failed" >&2; return 1; }; rows="$REPLY"
    mktemp_tracked || { echo "$PROG: reconcile: mktemp failed" >&2; return 1; }; all_cache="$REPLY"
    armed_rows "$rows" "$all_cache" || {
        echo "$PROG: reconcile: could not enumerate armed beads — NOT treating this as an empty queue" >&2
        return 1; }

    local expected processed=0 dispatched=0 retired=0 waiting=0 stranded=0 held=0 capped=0 failed=0
    expected="$(wc -l < "$rows" | tr -d ' ')"

    local id status ready owncleared json target args_json assignee slung rc merge_result fails
    while IFS=$'\t' read -r id status ready owncleared; do
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

        json="$(bead_from_cache "$all_cache" "$id")" || json=""
        if [ -z "$json" ]; then
            echo "$PROG: WARN $id enumerated but does not resolve — leaving armed" >&2
            failed=$((failed + 1)); continue
        fi

        # A surviving gc.dispatch_when_ready_slung marker means a prior pass was
        # mid-dispatch and died before it could disarm; its state decides what to
        # do. It is the ONE signal recovery reads: a plain pool sling and an --on
        # pour leave different stamps (gc.routed_to vs gc.execution_routed_to), and
        # in a default-formula city a bare `gc sling` is itself an --on-less pour,
        # so no stamp a sling leaves is a reliable "already ran" across every lane.
        # Read it before the ready gate: a dispatched bead may no longer report
        # ready, and a proven-but-stranded marker must still retire.
        slung="$(meta_of "$json" "$K_SLUNG")"
        case "$slung" in
            "")
                : # not mid-dispatch; fall through to the ready gate and sling
                ;;
            "$SLUNG_TRYING"*)
                # Attempt in flight but never confirmed: the pass died before or
                # during its sling, or a failed sling could not roll the marker
                # back. The dispatch is NOT proven, so retiring the arm here is the
                # silent lost dispatch this two-state marker exists to prevent —
                # and one doctor/check-blocked-work-armed cannot catch, because the
                # blocker has lifted and the bead is ready, not blocked. Clear the
                # unproven stamp and fall through to re-attempt the sling.
                if [ "$DRY_RUN" = 1 ]; then
                    echo "$PROG: DRY-RUN would re-attempt an unconfirmed sling on $id (marker=$slung)"
                elif bd_ update "$id" --unset-metadata "$K_SLUNG" >/dev/null 2>&1; then
                    echo "$PROG: re-attempting $id — a prior pass stamped '$slung' and never confirmed the sling"
                else
                    echo "$PROG: WARN could not clear the unconfirmed $K_SLUNG on $id — leaving armed" >&2
                    failed=$((failed + 1)); continue
                fi
                ;;
            *)
                # "slung@<ts>" (a proven dispatch), or any marker without the
                # "slinging@" prefix: the sling ran and the pass died before it
                # could disarm. Retire the arm — a second sling would double up.
                if [ "$DRY_RUN" = 1 ]; then
                    echo "$PROG: DRY-RUN would retire arm on already-dispatched $id"
                elif disarm_bead "$id" "already dispatched (reconcile confirmed the sling at $slung, then died before disarming); arm retired without a second sling"; then
                    echo "$PROG: retired arm on already-dispatched $id"
                else
                    echo "$PROG: WARN could not retire arm on already-dispatched $id" >&2; failed=$((failed + 1)); continue
                fi
                retired=$((retired + 1)); continue
                ;;
        esac

        # Already delivered: the bead carries a refinery delivery stamp (an open
        # PR, the pre-open gate, a merge), so the work this arm would pour has
        # already been produced by another path since the arm was recorded.
        # Re-slinging pours a redundant molecule and mints an input convoy with
        # it every pass — the common cause of a sling that never finalizes on an
        # already-delivered bead. Retire the arm the way a proven slung@ marker
        # does; there is no dispatch to lose, only one to stop repeating.
        merge_result="$(meta_of "$json" merge_result)"
        if [ -n "$merge_result" ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "$PROG: DRY-RUN would retire arm on already-delivered $id (merge_result=$merge_result)"
            elif disarm_bead "$id" "work already delivered (merge_result=$merge_result) by another path since the arm was recorded; arm retired without slinging a redundant molecule"; then
                echo "$PROG: retired arm on already-delivered $id (merge_result=$merge_result)"
            else
                echo "$PROG: WARN could not retire arm on already-delivered $id" >&2; failed=$((failed + 1)); continue
            fi
            retired=$((retired + 1)); continue
        fi

        # Not dispatchable. `bd --ready` (fast path) and own_cleared (an open
        # bead whose own blockers have all closed, held out of ready only by an
        # ancestor cascade) are the two ways in; without either, an open bead is
        # waiting on its own open blocker and the next pass re-asks, while any
        # other live status is excluded by `--ready` on the status itself, so
        # waiting for it is waiting for something no blocker closing can deliver.
        # Say so every pass — the arm outlives every session that could remember
        # it, and a silent `waiting` count is how it stays lost.
        if [ "$ready" != "1" ] && [ "$owncleared" != "1" ]; then
            if [ "$status" != "open" ]; then
                echo "$PROG: STRANDED $id is armed at status=$status, which 'bd list --ready' never answers — clear the hold or disarm; no blocker closing will dispatch it" >&2
                stranded=$((stranded + 1))
            else
                waiting=$((waiting + 1))
            fi
            continue
        fi
        target="$(meta_of "$json" "$K_TARGET")"
        args_json="$(meta_of "$json" "$K_ARGS")"
        assignee="$(printf '%s' "$json" | jq -r '.assignee // ""')"
        [ -n "$args_json" ] || args_json="[]"

        if [ -z "$target" ]; then
            echo "$PROG: WARN $id is armed with an empty target — leaving it for a human" >&2
            failed=$((failed + 1)); continue
        fi

        # Held: slinging would take the bead away from its assignee.
        if [ -n "$assignee" ]; then
            echo "$PROG: HELD $id is ready but assigned to '$assignee' — not slinging; disarm or clear the assignee" >&2
            held=$((held + 1)); continue
        fi

        # The retry has a budget. Each sling attempt mints an input convoy, so a
        # dispatch that never finalizes must stop re-slinging before it leaks one
        # convoy per pass. The counter (bumped in the stamp write below) is the
        # memory a bare rollback erases. At the cap, escalate once (escalate.sh
        # dedups on the key) and leave the arm — never retire an unproven
        # dispatch — so a person decides rather than reconcile looping forever.
        fails="$(meta_of "$json" "$K_FAILS")"
        case "$fails" in ''|*[!0-9]*) fails=0 ;; esac
        if [ "$fails" -ge "$MAX_SLING_FAILURES" ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "$PROG: DRY-RUN would escalate capped $id ($fails failed attempts, cap $MAX_SLING_FAILURES) instead of re-slinging"
            else
                echo "$PROG: CAPPED $id has failed to dispatch $fails times (cap $MAX_SLING_FAILURES) — not re-slinging; escalating and leaving the arm for a person" >&2
                if [ -x "$ESCALATE" ]; then
                    "$ESCALATE" --subject "$id" --key "deferred-dispatch-sling-failed.$id" \
                      --message "deferred-dispatch reconcile has failed to sling armed bead $id to '$target' $fails times (cap $MAX_SLING_FAILURES), minting an input convoy on each attempt. The retry is not converging on its own — a common cause is work already delivered by another path after the arm was recorded, or a target that refuses the pour. Investigate, then disarm the bead ($SCRIPTS_DIR/deferred-dispatch.sh disarm $id), or clear gc.dispatch_when_ready_fail_count on $id to re-arm the retry." >/dev/null 2>&1 || true
                else
                    echo "$PROG: WARN escalate tool '$ESCALATE' not executable — capped $id has no visit; disarm or clear its fail count by hand" >&2
                fi
            fi
            capped=$((capped + 1)); continue
        fi

        # Its own blockers are clear but bd held it unready through a blocked or
        # deferred ancestor (the parent-child cascade) — say why a not-ready bead
        # is being slung, so the pass log is legible.
        if [ "$ready" != "1" ]; then
            echo "$PROG: $id has no open blocks edge of its own; bd holds it unready only through a blocked/deferred ancestor — dispatching"
        fi

        # Stamp the marker in its unproven "slinging@" state, THEN sling. Dying
        # between the two leaves an unconfirmed marker, which the next pass
        # re-slings rather than retires — so a death here costs a retry, never a
        # silently lost dispatch. A sling that fails rolls the marker back so the
        # arm retries next pass. Recovery stays keyed on this one owned marker, not
        # on whichever stamp a given lane happened to leave. The same write bumps
        # the attempt counter the cap reads: an attempt is counted the moment it
        # is about to be made, so a failure or a death both leave the count raised
        # and disarm (on the eventual proven dispatch) clears it.
        if [ "$DRY_RUN" != 1 ]; then
            bd_ update "$id" --set-metadata "$K_SLUNG=$SLUNG_TRYING$(now_utc)" --set-metadata "$K_FAILS=$((fails + 1))" >/dev/null 2>&1 || {
                echo "$PROG: WARN could not stamp $K_SLUNG on $id — leaving armed, not slinging" >&2
                failed=$((failed + 1)); continue; }
        fi

        sling_bead "$id" "$target" "$args_json"; rc=$?
        if [ "$rc" != 0 ]; then
            [ "$DRY_RUN" = 1 ] || bd_ update "$id" --unset-metadata "$K_SLUNG" >/dev/null 2>&1 || true
            if [ "$rc" = 3 ]; then
                echo "$PROG: WARN $id has a malformed $K_ARGS ('$args_json') — leaving armed" >&2
            else
                echo "$PROG: WARN sling of $id -> $target failed (rc=$rc) — leaving armed, retrying next pass" >&2
            fi
            failed=$((failed + 1)); continue
        fi
        if [ "$DRY_RUN" = 1 ]; then dispatched=$((dispatched + 1)); continue; fi

        # Sling returned success: promote the marker to its proven "slung@" state
        # before clearing the record, so a death in the narrow window before disarm
        # recovers as a retire, not a second sling. disarm then clears the whole
        # record, the marker included; if this promotion write is lost, disarm
        # still clears it on this pass, and only a death before disarm falls back to
        # a re-sling next pass.
        bd_ update "$id" --set-metadata "$K_SLUNG=$SLUNG_DONE$(now_utc)" >/dev/null 2>&1 || true
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
    echo "$PROG: $dispatched dispatched, $retired retired, $waiting waiting, $stranded stranded, $held held, $capped capped, $failed failed (of $expected armed)"
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
