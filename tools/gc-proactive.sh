#!/usr/bin/env bash
# gc-proactive.sh — the proactive-via-slung-mol engine (Bead-Universe Phase 4;
# v1 design specs/bead-universe/design-doc.md, still governing this tool).
# "Proactive" is NOT a resident loop: it is mol-first-reaction slung at a
# bead (read body → write a first-reaction CARD → dispose: route it to a pool,
# hold it on an edge, or file a visit) so the human arrives at advanced work,
# and at fewer beads. This tool is the trigger layer:
#   demand [<pool>]      pool work_query — routed beads, board-ranked
#   scan [--json|--sling] find movable-forward / opt-in beads; --sling reacts,
#                        bounded by GC_PROACTIVE_SLING_CAP per sweep
#   sling <bead> [--nudge] [-n]  sling a first reaction (mr path, hard-refuses
#                        --merge direct — the security invariant)
#   deliverable          "would a sling be picked up?" — no when the city's
#                        agent roster says this pool cannot pick it up
#                        (absent, suspended, or capped at zero), exit 0/1
# The pool's only throttle is its max_active_sessions
# (agents/proactive/agent.toml); slung beads queue until a slot frees. That
# bounds how many reactions run at once. GC_PROACTIVE_SLING_CAP is a different
# bound: how many one `scan --sling` sweep may hand out.
# Tunables: GC_PROACTIVE_POOL / _MERGE / _SCAN_LIMIT / _SLING_CAP / _FIXTURE
# (test hook: canned ready/scan/agents .json instead of gc calls).
set -euo pipefail

PROG="${0##*/}"

POOL_BASE="${GC_PROACTIVE_POOL:-gc-toolkit.proactive}"
MERGE="${GC_PROACTIVE_MERGE:-mr}"
SCAN_LIMIT="${GC_PROACTIVE_SCAN_LIMIT:-20}"
# What ONE --sling sweep may hand out. A first reaction can end in a route to
# the polecat pool, so an uncapped sweep is a queue of implementation sessions
# filed by one command. 5 is that pool's own max_active_sessions: a sweep
# never hands out more than the city can start working in one cycle.
SLING_CAP="${GC_PROACTIVE_SLING_CAP:-5}"
FIXTURE="${GC_PROACTIVE_FIXTURE:-}"
FORMULA="mol-first-reaction"
# The issue types a first reaction may target — an ALLOWLIST (fail-safe): a
# new bead type earns reactions only when added here deliberately. Tunable per
# rig via GC_PROACTIVE_TYPES without a code change. The default excludes
# convoy/epic/step/molecule (machinery or work-in-flight), decision (already a
# surfaced human choice) and spec (an output, not a raw input).
PROACTIVE_TYPES="${GC_PROACTIVE_TYPES:-task,bug,feature,spike}"

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

# exclude_topology_roots — drop graph.v2 topology ROOTS (gc.kind in
# workflow/scope/spec) from a demand array on stdin. A root is routed only to
# name its run; gc hook --claim never offers it, so a query that counts one
# spawns a worker that claims nothing and drains. The gc binary's default pool
# query applies this exact clause on both its worker and count forms; this
# mirrors it for the proactive custom queries, which inline the same clause in
# agents/proactive/agent.toml's work_query + scale_check — keep all three in sync.
exclude_topology_roots() {
    jq 'map(select((.metadata["gc.kind"] // "" | (. == "workflow" or . == "scope" or . == "spec")) | not))'
}

usage() {
    cat <<EOF
Usage: $PROG demand [<pool-target>]   Pool work_query: emit the routed
                                      proactive beads, board-ranked. Read-only.
       $PROG scan [--json] [--sling]  Find movable-forward / opt-in beads; with
                                      --sling, sling a first reaction at each,
                                      at most $SLING_CAP per sweep
                                      (GC_PROACTIVE_SLING_CAP). Read-only
                                      without --sling.
       $PROG sling <bead> [--nudge] [-n|--dry-run]
                                      Sling mol-first-reaction at <bead> on the
                                      codex-gated mr path. Refuses --merge
                                      direct (the security invariant).
       $PROG deliverable [<pool-target>]
                                      Would work routed at that pool actually
                                      be PICKED UP? No when this city's agent
                                      roster says it cannot: absent, suspended,
                                      or capped at zero slots. Defaults to the
                                      proactive pool; any rig-qualified target
                                      answers. Exit 0 yes, 1 no; callers divert
                                      on no.

Budget: the pool cap (agents/proactive/agent.toml max_active_sessions) throttles
how many run at once; routed beads queue until a slot frees. One --sling sweep
hands out at most $SLING_CAP reactions.
Security: proactive output is mr-only
(GC_PROACTIVE_MERGE=$MERGE; "direct" is refused).
EOF
}

# ---------------------------------------------------------------------------
# deliverable [<pool-target>] — "if I route work there right now, will anything
# ever pick it up?" The default target is the proactive pool; the first
# reaction's actionable exit asks the same question about the pool it is about
# to hand a bead to."
# The queue is not the question: a routed bead waits at zero cost until a slot
# frees. What makes a sling vanish is a pool that cannot claim it at all, and
# the city's own agent roster is where that shows: the pool is not registered
# in this city, it is suspended, or it is capped at zero slots.
#
# NO is a positive finding only. A roster this cannot read answers YES, because
# an unreadable roster is not evidence of an absent pool, and a false no
# silently retires the framing every caller diverts from
# (assets/scripts/gc-visit-open.sh files a bare visit on a no).
# ---------------------------------------------------------------------------
cmd_deliverable() {
    local target roster verdict
    target="$(resolve_pool_target "${1:-}" 2>/dev/null)" || {
        printf 'no: cannot rig-qualify the proactive pool target (set GC_RIG or pass <rig>/<base>) — a bare name routes to nobody\n'
        return 1
    }

    if [ -n "$FIXTURE" ]; then
        roster=""
        [ -f "$FIXTURE/agents.json" ] && roster="$(cat "$FIXTURE/agents.json")"
    elif command -v timeout >/dev/null 2>&1; then
        # Bounded: gc-visit-open asks this question while an operator waits at
        # a prompt, and a hung roster read must degrade to yes, not to a hang.
        roster="$(timeout "${GC_PROACTIVE_ROSTER_TIMEOUT:-15}" gc agent list --json 2>/dev/null || true)"
    else
        roster="$(gc agent list --json 2>/dev/null || true)"
    fi

    # jq answers one word: present | absent | suspended | nocap. Anything else
    # (empty roster, malformed JSON, no jq) leaves verdict empty = unreadable.
    verdict=""
    if [ -n "$roster" ]; then
        verdict="$(printf '%s' "$roster" | jq -r --arg t "$target" '
            (.agents // []) | map(select((.qualified_name // "") == $t)) as $m
            | if ($m | length) == 0 then "absent"
              elif ($m[0].suspended // false) then "suspended"
              elif ((($m[0].pool // {}).max // 1) < 1) then "nocap"
              else "present" end' 2>/dev/null || true)"
    fi

    case "$verdict" in
        absent)
            printf 'no: no agent is registered at %s in this city, so a slung reaction routes to nobody\n' "$target"
            return 1 ;;
        suspended)
            printf 'no: the pool at %s is suspended; a slung reaction would sit unclaimed until it resumes\n' "$target"
            return 1 ;;
        nocap)
            printf 'no: the pool at %s has no session slots (max_active_sessions is 0), so nothing can claim a slung reaction\n' "$target"
            return 1 ;;
        present)
            printf 'yes: %s is registered and unsuspended — its cap only queues a slung reaction, never drops it\n' "$target"
            return 0 ;;
        *)
            printf 'yes: could not read this city agent roster, so the pool is assumed live — an unreadable roster is not evidence that %s is gone\n' "$target"
            return 0 ;;
    esac
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
                --exclude-type=epic --json --limit 0 2>/dev/null || true)"
        [ -n "$r" ] || r='[]'
    fi
    # Drop never-claimable topology roots (see exclude_topology_roots) so the
    # demand mirror matches what gc hook --claim would offer, then rank by board
    # weight and slice to the worker page. The full routed set is read
    # (--limit 0) and roots dropped BEFORE the slice, so — like the agent.toml
    # work_query this mirrors — a page filled by topology roots cannot bury a
    # claimable step behind them and understate demand to zero. The scarce
    # proactive slots then spend on the highest-priority work first (oldest
    # within a band), not whatever bd-ready returned oldest across all bands.
    printf '%s' "$r" | exclude_topology_roots | board_rank | jq --argjson n "$SCAN_LIMIT" '.[0:$n]'
}

# ---------------------------------------------------------------------------
# scan — the PROCESS-SCAN trigger. Find raw INPUT beads "able to be updated":
# open, ready, unassigned, an allowlisted issue_type (GC_PROACTIVE_TYPES),
# top-level, and not already reacted-to / routed / machinery (so we never
# re-react and never react to work-in-flight). Unions the explicit per-bead
# opt-in (gc.proactive=1) with the broader movable-forward scan, deduped and
# precision-filtered (see scan_candidates). Read-only unless --sling.
# ---------------------------------------------------------------------------

# scan_precision_filter — from a candidate array on stdin, keep only raw
# top-level INPUT beads a fresh first reaction may target. Each clause drops a
# distinct non-input population:
#   - ALLOWLIST issue_type ($types, GC_PROACTIVE_TYPES) — drops convoy/epic/
#     step/molecule/spec/decision by omission.
#   - topology roots (gc.kind in workflow/scope/spec) — a workflow root is
#     issue_type task, so the allowlist misses it; drop it explicitly.
#   - task_kind=feedback-pattern — distiller-loop machinery, not an input.
#   - task_kind=review — a dispatched signoff lane, work-in-flight.
#   - durable work/lifecycle markers ($markers) — a review lane carries
#     check_name/anchor_bead; an implementation anchor carries branch/
#     merge_result/work_dir/pr_url/pr_number. An anchor is an issue_type
#     task/bug bead with no task_kind, so the allowlist and the task_kind
#     clauses both miss it, and its markers are the only signal that the work
#     is already in motion. Slinging a first reaction at either reassigns
#     work-in-flight, which the proactive scope forbids.
#   - gc.takeaway / gc.takeaway_by — a sitting has already RULED this bead.
#   - top-level only — a parent-child CHILD carries the edge in its own
#     .dependencies; a convoy's tracks edge lives on the convoy, so this
#     catches parented beads, not every convoy member.
# Plus the state predicate shared with the live queries (not already reacted,
# not routed, has a description). Deduped by id.
scan_precision_filter() {
    local types_json markers_json
    types_json="$(printf '%s' "$PROACTIVE_TYPES" | jq -R 'split(",") | map(select(length > 0))')"
    # Durable work/lifecycle markers that mark a bead as work-in-flight rather
    # than raw input. Kept as one list so the review-lane keys and the
    # implementation-anchor keys share a single source of truth.
    markers_json='["branch","merge_result","work_dir","pr_url","pr_number","check_name","anchor_bead"]'
    jq --argjson types "$types_json" --argjson markers "$markers_json" '
        map(select(
            ((.metadata["gc.proactive_reaction"] // "") == "")
            and ((.metadata["gc.routed_to"] // "") == "")
            and ((.description // "") != "")
            and ((.issue_type // "") as $it | ($types | index($it)) != null)
            and (((.metadata["gc.kind"] // "") | (. == "workflow" or . == "scope" or . == "spec")) | not)
            and ((.metadata["task_kind"] // "") != "feedback-pattern")
            and ((.metadata["task_kind"] // "") != "review")
            and ((.metadata["gc.takeaway"] // "") == "")
            and ((.metadata["gc.takeaway_by"] // "") == "")
            and (.metadata as $m | ($markers | any(.[]; ($m[.] // "") != "")) | not)
            and (([ .dependencies[]? | select((.dependency_type // .type) == "parent-child") ] | length) == 0)
          ))
        | unique_by(.id)
    '
}

scan_candidates() {
    if [ -n "$FIXTURE" ]; then
        local raw='[]'
        if [ -f "$FIXTURE/scan.json" ]; then raw="$(cat "$FIXTURE/scan.json")"; fi
        printf '%s' "$raw" | scan_precision_filter | board_rank
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

    # (B) movable-forward: any ready, unassigned, non-epic bead. The precision
    # filter below drops the ones a fresh first reaction must not touch.
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
    movable="$(gc bd ready ${db:+--db "$db"} --unassigned --exclude-type=epic --json \
                --sort oldest --limit="$SCAN_LIMIT" 2>/dev/null || true)"
    [ -n "$movable" ] || movable='[]'

    # Union the two sources, apply the shared precision filter, then rank by
    # board weight so a --sling sweep spends its limited headroom on the
    # highest-priority candidates first.
    jq -s '(.[0] + .[1])' <(printf '%s' "$optin") <(printf '%s' "$movable") \
        | scan_precision_filter | board_rank
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

    case "$SLING_CAP" in
        ''|*[!0-9]*) die "GC_PROACTIVE_SLING_CAP must be a non-negative integer (got '$SLING_CAP')" ;;
    esac

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

    # --sling: advance each candidate, highest board weight first, and stop at
    # SLING_CAP. The cap is the throttle that matters now that a reaction can
    # end in a route to an implementation pool: without it one sweep files as
    # many downstream sessions as the scan found candidates. What it skips is
    # named, not silently dropped — the next sweep sees the same beads, since
    # a candidate only leaves the scan once a reaction has advanced it.
    local slung=0 skipped=0
    local ids
    ids="$(printf '%s' "$cands" | jq -r '.[].id')"
    local id
    for id in $ids; do
        if [ "$slung" -ge "$SLING_CAP" ]; then
            skipped=$(( skipped + 1 ))
            continue
        fi
        if cmd_sling "$id"; then
            slung=$(( slung + 1 ))
        fi
    done
    if [ "$skipped" -gt 0 ]; then
        log "scan --sling: slung $slung first reaction(s); $skipped candidate(s) left for the next sweep (cap $SLING_CAP, GC_PROACTIVE_SLING_CAP)"
    else
        log "scan --sling: slung $slung first reaction(s)"
    fi
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

    if [ -n "$FIXTURE" ]; then
        # The fixture hook stands in for every gc call in this tool, including
        # this one: a --sling sweep under test must exercise the loop and its
        # cap without dispatching anything into a live city.
        log "$PROG: (fixture) would sling $FORMULA at $bead (merge=$MERGE) -> $target"
        printf 'gc sling %s\n' "$*"
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
        deliverable) cmd_deliverable "$@" ;;
        *) die "unknown verb '$verb' (demand|scan|sling|deliverable; --help)" ;;
    esac
}

main "$@"
