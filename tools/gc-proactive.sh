#!/usr/bin/env bash
# gc-proactive.sh — the proactive-via-slung-mol engine (Bead-Universe Phase 4;
# v1 design specs/bead-universe/design-doc.md, still governing this tool).
# "Proactive" is NOT a resident loop: it is mol-first-reaction slung at a
# bead (read body → write a first-reaction CARD → file a visit) so the human
# arrives at advanced work. This tool is the trigger layer:
#   demand [<pool>]      pool work_query — routed beads, board-ranked
#   scan [--json|--sling] find movable-forward / opt-in beads; --sling reacts
#   sling <bead> [--nudge] [-n]  sling a first reaction (mr path, hard-refuses
#                        --merge direct — the security invariant)
#   deliverable          "would a sling be picked up?" — always yes now (kept
#                        for callers that branch on it, exit 0/1)
# The only throttle is the pool's max_active_sessions
# (agents/proactive/agent.toml); slung beads queue until a slot frees.
# Tunables: GC_PROACTIVE_POOL / _MERGE / _SCAN_LIMIT / _FIXTURE (test hook:
# canned ready/scan .json instead of gc calls).
set -euo pipefail

PROG="${0##*/}"

POOL_BASE="${GC_PROACTIVE_POOL:-gc-toolkit.proactive}"
MERGE="${GC_PROACTIVE_MERGE:-mr}"
SCAN_LIMIT="${GC_PROACTIVE_SCAN_LIMIT:-20}"
FIXTURE="${GC_PROACTIVE_FIXTURE:-}"
FORMULA="mol-first-reaction"

log()  { printf '%s\n' "$*" >&2; }
die()  { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }

# resolve_pool_target [override] -> the RIG-QUALIFIED pool target. The pool
# is rig-scoped and gc sling rejects a bare agent name, so a bare base is
# qualified from GC_RIG — failing CLOSED when GC_RIG is unset rather than
# emitting an unroutable name.
resolve_pool_target() {
    local base="${1:-}"
    [ -n "$base" ] || base="$POOL_BASE"
    case "$base" in
        */*) printf '%s' "$base" ;;                       # already <rig>/<base>
        *)
            if [ -n "${GC_RIG:-}" ]; then
                printf '%s/%s' "$GC_RIG" "$base"
            else
                die "cannot rig-qualify proactive target '$base': set GC_RIG or pass a <rig>/<base> target (the pool is rig-scoped — agents/proactive/agent.toml watches {{.Rig}}/gc-toolkit.proactive, and gc sling rejects a bare agent name)"
            fi
            ;;
    esac
}

# rig_beads_db -> this rig's .beads dir, to pin gc bd --db: an unpinned
# up-walk from a worktree (where .beads is gitignored) overshoots to the HQ
# ledger and demand comes back empty. Empty when unresolvable; callers fall
# back to a bare gc bd ready.
rig_beads_db() {
    [ -n "${GC_RIG:-}" ] || return 0
    local path
    path="$(gc rig list --json 2>/dev/null \
        | jq -r --arg n "$GC_RIG" '.rigs[]? | select(.name==$n) | .path' 2>/dev/null \
        | head -n1 || true)"
    [ -n "$path" ] && [ -d "$path/.beads" ] && printf '%s' "$path/.beads"
    return 0
}

# board_rank — re-rank (stdin JSON array) by the board's priority weight
# (prio_w = max(0, 4-p), null->1), oldest-first within a band. Mirrored
# inline in agents/proactive/agent.toml's work_query; keep the two in sync.
board_rank() {
    jq 'def prio_w($p): (if $p == null then 1 else ([0, 4 - $p] | max) end);
        sort_by(-(prio_w(.priority)), (.created_at // ""))'
}

usage() {
    cat <<EOF
Usage: $PROG demand [<pool-target>]   Pool work_query: emit the routed
                                      proactive beads, board-ranked. Read-only.
       $PROG scan [--json] [--sling]  Find movable-forward / opt-in beads; with
                                      --sling, sling a first reaction at each.
                                      Read-only without --sling.
       $PROG sling <bead> [--nudge] [-n|--dry-run]
                                      Sling mol-first-reaction at <bead> on the
                                      codex-gated mr path. Refuses --merge
                                      direct (the security invariant).
       $PROG deliverable              Would a slung first reaction actually be
                                      PICKED UP? Always yes (the pool is always
                                      on; its cap only queues work). Kept for
                                      callers that branch on the answer.

Budget: the pool cap (agents/proactive/agent.toml max_active_sessions) is the
only throttle; routed beads queue until a slot frees.
Security: proactive output is mr-only
(GC_PROACTIVE_MERGE=$MERGE; "direct" is refused).
EOF
}

# ---------------------------------------------------------------------------
# deliverable — "if I sling right now, will anything ever pick it up?"
# Always yes: the pool is always on, and its max_active_sessions cap only
# queues a routed bead, never drops it. Kept as a verb because callers
# (assets/scripts/gc-visit-open.sh) branch on the exit status.
# ---------------------------------------------------------------------------
cmd_deliverable() {
    printf 'yes: the proactive pool is always on — its cap (max_active_sessions, agents/proactive/agent.toml) only queues a slung reaction, never drops it\n'
    return 0
}

# ---------------------------------------------------------------------------
# demand — the proactive pool's work_query: the standard pool demand (ready,
# unassigned, routed-to-us beads), board-ranked. The reconciler runs this to
# decide whether to spawn a proactive worker.
# ---------------------------------------------------------------------------

cmd_demand() {
    local r='[]'
    if [ -n "$FIXTURE" ]; then
        if [ -f "$FIXTURE/ready.json" ]; then r="$(cat "$FIXTURE/ready.json")"; fi
    else
        # Standard pool demand: ready (deps closed), unassigned, not an epic,
        # routed to this proactive pool. The route is rig-qualified (see
        # resolve_pool_target) so it matches the gc.routed_to the pool's
        # agent.toml work_query writes. Mirrors the polecat probe, pinned to
        # the proactive target.
        local target db
        target="$(resolve_pool_target "${1:-}")"
        db="$(rig_beads_db)"
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
        r="$(gc bd ready ${db:+--db "$db"} --metadata-field "gc.routed_to=$target" --unassigned \
                --exclude-type=epic --json --sort oldest --limit="$SCAN_LIMIT" 2>/dev/null || true)"
        [ -n "$r" ] || r='[]'
    fi
    # Rank by board weight: spend the scarce proactive slots on the
    # highest-priority work first (oldest-first within a band), not whatever
    # bd-ready returned oldest-first across all priorities.
    printf '%s' "$r" | board_rank
}

# ---------------------------------------------------------------------------
# scan — the PROCESS-SCAN trigger. Find beads "able to be updated": open,
# ready, unassigned, not an epic, and not already reacted-to / hand-raised
# (so we never re-react). Unions the explicit per-bead opt-in (gc.proactive=1)
# with the broader movable-forward scan, deduped. Read-only unless --sling.
#
# Operator-driven by decision (tk-j81t84): no order schedules this verb. A
# cadence over it files one visit per candidate bead, which is the shape the
# P3 batching resolution rejected, and the work feeder owns this candidate
# query once it lands.
# ---------------------------------------------------------------------------

scan_candidates() {
    if [ -n "$FIXTURE" ]; then
        local raw='[]'
        if [ -f "$FIXTURE/scan.json" ]; then raw="$(cat "$FIXTURE/scan.json")"; fi
        printf '%s' "$raw" | board_rank
        return 0
    fi

    # (A) explicit opt-in: beads that asked for a first reaction. Pin --db so
    # the query hits this rig's ledger, not a cwd up-walk (see rig_beads_db).
    local optin movable db
    db="$(rig_beads_db)"
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
    optin="$(gc bd ready ${db:+--db "$db"} --metadata-field "gc.proactive=1" --unassigned \
                --exclude-type=epic --json --sort oldest --limit="$SCAN_LIMIT" 2>/dev/null || true)"
    [ -n "$optin" ] || optin='[]'

    # (B) movable-forward: any ready, unassigned, non-epic bead. We then drop
    # the ones already advanced (gc.proactive_reaction set) or already
    # routed somewhere — those are not "able to be updated" by a fresh
    # first reaction.
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
    movable="$(gc bd ready ${db:+--db "$db"} --unassigned --exclude-type=epic --json \
                --sort oldest --limit="$SCAN_LIMIT" 2>/dev/null || true)"
    [ -n "$movable" ] || movable='[]'

    # Union, drop already-handled, dedup, then rank by board weight so a
    # --sling sweep spends its limited headroom on the highest-priority
    # candidates first.
    jq -s '
        (.[0] + .[1])
        | map(select(
            ((.metadata["gc.proactive_reaction"] // "") == "")
            and ((.metadata["gc.routed_to"] // "") == "")
            and ((.description // "") != "")
          ))
        | unique_by(.id)
    ' <(printf '%s' "$optin") <(printf '%s' "$movable") | board_rank
}

cmd_scan() {
    local as_json="" do_sling=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --json)   as_json=1; shift ;;
            --sling)  do_sling=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "scan: unknown arg '$1'" ;;
        esac
    done

    local cands
    cands="$(scan_candidates)"

    if [ -z "$do_sling" ]; then
        if [ -n "$as_json" ]; then
            printf '%s' "$cands"
        else
            printf '%s' "$cands" | jq -r '
                if length == 0 then "scan: no movable-forward beads"
                else (.[] | "\(.id) · \(.title // "")") end'
        fi
        return 0
    fi

    # --sling: advance each candidate. The sweep is bounded by the scan's own
    # candidate limit (GC_PROACTIVE_SCAN_LIMIT); the pool cap queues the rest.
    local slung=0
    local ids
    ids="$(printf '%s' "$cands" | jq -r '.[].id')"
    local id
    for id in $ids; do
        if cmd_sling "$id"; then
            slung=$(( slung + 1 ))
        fi
    done
    log "scan --sling: slung $slung first reaction(s)"
}

# ---------------------------------------------------------------------------
# sling — route a first reaction at a bead on the mr path. The security
# invariant lives here: proactive output is mr-only; `direct` is refused.
# ---------------------------------------------------------------------------

cmd_sling() {
    local bead="" nudge="" dry=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --nudge)    nudge=1; shift ;;
            -n|--dry-run) dry=1; shift ;;
            -h|--help)  usage; exit 0 ;;
            -*) die "sling: unknown flag '$1'" ;;
            *) [ -z "$bead" ] || die "sling: takes one bead-id"; bead="$1"; shift ;;
        esac
    done
    [ -n "$bead" ] || { log "$PROG: sling needs <bead-id>"; usage; exit 2; }

    # THE SECURITY INVARIANT: proactive output never takes the direct path.
    case "$MERGE" in
        direct) die "security invariant: proactive output must take the codex-gated mr path, never --merge direct (GC_PROACTIVE_MERGE=direct refused)" ;;
        mr|local) : ;;
        *) die "sling: unknown merge strategy '$MERGE' (mr|local)" ;;
    esac

    local target
    target="$(resolve_pool_target)"

    # --on attaches the workflow to the existing bead and routes THAT bead;
    # --merge pins the path; --reassign hands a human-held bead over cleanly.
    #
    # --on is load-bearing: without it the pool inherits agent_defaults'
    # mol-polecat-work and pours the wrong formula.
    set -- "$target" "$bead" --on "$FORMULA" --merge "$MERGE" --reassign
    [ -n "$nudge" ] && set -- "$@" --nudge

    if [ -n "$dry" ]; then
        # Prove the command shape (the gate asserts --merge mr + the formula).
        printf 'gc sling %s --dry-run\n' "$*"
        if [ -z "$FIXTURE" ]; then
            gc sling "$@" --dry-run 2>&1 || true
        fi
        return 0
    fi

    log "$PROG: slinging $FORMULA at $bead (merge=$MERGE) -> $target"
    gc sling "$@"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
    [ $# -ge 1 ] || { usage; exit 2; }
    local verb="$1"; shift || true
    case "$verb" in
        -h|--help|help) usage; exit 0 ;;
        demand) cmd_demand "$@" ;;
        scan)   cmd_scan "$@" ;;
        sling)  cmd_sling "$@" ;;
        deliverable) cmd_deliverable ;;
        *) die "unknown verb '$verb' (demand|scan|sling|deliverable; --help)" ;;
    esac
}

main "$@"
