#!/usr/bin/env bash
# gc-proactive.sh — the proactive first-reaction trigger layer (Bead-Universe
# Phase 4; v1 design specs/bead-universe/design-doc.md, still governing this
# tool). "Proactive" is NOT a resident loop: `sling` routes a bead RAW to the
# proactive pool (gc.routed_to only, no formula), a pool worker claims it,
# reacts per its prompt (read body → write a first-reaction CARD → dispose:
# route it to a pool, hold it on an edge, file a visit, or close it as
# superseded), and drains — so the human arrives at advanced work, and at fewer
# beads. This tool is the trigger layer:
#   demand [<pool>]      pool work_query — routed beads, board-ranked
#   scan [--json|--sling] find movable-forward / opt-in beads; --sling routes,
#                        bounded by GC_PROACTIVE_SLING_CAP per sweep
#   sling <bead> [--nudge] [-n]  route a bead raw to the proactive pool for a
#                        first reaction
#   deliverable          "would a sling be picked up?" — no when the city's
#                        agent roster says this pool cannot pick it up
#                        (absent, suspended, or capped at zero), exit 0/1
# The pool's only throttle is its max_active_sessions
# (agents/proactive/agent.toml); slung beads queue until a slot frees. That
# bounds how many reactions run at once. GC_PROACTIVE_SLING_CAP is a different
# bound: how many one `scan --sling` sweep may hand out. Any code a reaction
# produces takes the codex-gated mr path — enforced by the pool env
# (GC_DEFAULT_MERGE_STRATEGY=mr) and the prompt, not by this router.
# Tunables: GC_PROACTIVE_POOL / _SCAN_LIMIT / _SLING_CAP / _FIXTURE
# (test hook: canned ready/scan/agents .json instead of gc calls).
set -euo pipefail

PROG="${0##*/}"

POOL_BASE="${GC_PROACTIVE_POOL:-gc-toolkit.proactive}"
SCAN_LIMIT="${GC_PROACTIVE_SCAN_LIMIT:-20}"
# What ONE --sling sweep may hand out. A first reaction can end in a route to
# the polecat pool, so an uncapped sweep is a queue of implementation sessions
# filed by one command. 5 is that pool's own max_active_sessions: a sweep
# never hands out more than the city can start working in one cycle.
SLING_CAP="${GC_PROACTIVE_SLING_CAP:-5}"
FIXTURE="${GC_PROACTIVE_FIXTURE:-}"
# Set by cmd_sling to 1 when it skips an already-reacted bead as a no-op, else
# empty. cmd_scan's --sling loop reads it in-process to keep a skip from
# spending the cap; the `sling` CLI verb in main() translates it to
# RC_ALREADY_REACTED so a cross-process caller (gc-helm react, gc-visit-open)
# can tell the no-op from a dispatch and file its own visit rather than wait for
# a reaction that never ran.
SLING_SKIPPED=""
# Exit code the `sling` CLI verb uses for that skip — distinct from a dispatch
# (0) and an error (1), so a caller that needs a NEW reaction can branch on it.
RC_ALREADY_REACTED=3
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

# sling_first_reaction_guard — a first reaction happens once, so refuse to
# route a bead for one when it already carries a completed reaction. Routing an
# already-reacted bead re-offers a done reaction to the pool, and a fresh worker
# re-derives the same disposition on a bead whose disposition already landed.
# gc.first_reaction is stamped by the dispose before it acts and is the record
# of that completed reaction. The subject is read from the fixture under test,
# live otherwise; an unreadable
# bead is not proof of a reaction, so it proceeds. Returns non-zero when the
# bead is already reacted, so the caller skips the sling.
sling_first_reaction_guard() {
    local bead="$1" meta fr
    if [ -n "$FIXTURE" ]; then
        [ -f "$FIXTURE/beads.json" ] || return 0
        meta="$(jq -c --arg id "$bead" '.[$id].metadata // {}' "$FIXTURE/beads.json" 2>/dev/null || printf '{}')"
    else
        local db; db="$(rig_beads_db)"
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        meta="$(gc bd show "$bead" ${db:+--db "$db"} --json 2>/dev/null \
            | jq -c 'if type=="array" then (.[0].metadata // {}) else {} end' 2>/dev/null || printf '{}')"
    fi
    fr="$(printf '%s' "$meta" | jq -r '."gc.first_reaction" // ""' 2>/dev/null || printf '')"
    [ -n "$fr" ] || return 0
    log "$PROG: sling: $bead already carries a first reaction (gc.first_reaction=$fr) — not re-routing. A first reaction happens once; routing an already-reacted bead re-offers a done reaction to the pool. Clear gc.first_reaction to re-react."
    return 1
}

# board_rank — re-rank (stdin JSON array) by the board's priority weight
# (prio_w = max(0, 4-p), null->1), oldest-first within a band. Mirrored
# inline in agents/proactive/agent.toml's work_query; keep the two in sync.
board_rank() {
    jq 'def prio_w($p): (if $p == null then 1 else ([0, 4 - $p] | max) end);
        sort_by(-(prio_w(.priority)), (.created_at // ""))'
}

# exclude_graph_structural — drop graph.v2 STRUCTURAL beads from a demand array
# on stdin: topology ROOTS (gc.kind in workflow/scope/spec) and formula STEP
# beads (any of gc.step_ref/gc.step_id/gc.root_bead_id set). Neither is a raw
# subject a first reaction may claim: a root is routed only to name its run and
# gc hook --claim never offers it, and a step advances its own workflow by
# closing its own bead, so reacting to it as a subject derails a live molecule.
# A query that counts either spawns a worker that claims nothing (root) or
# hijacks a formula step (step). The gc binary's default pool query drops the
# roots on both its worker and count forms; this broadens it to the steps and
# mirrors both for the proactive custom queries, which inline the same clause in
# agents/proactive/agent.toml's work_query + scale_check and in
# scan_precision_filter — keep all four in sync.
exclude_graph_structural() {
    jq 'map(select((
            ((.metadata["gc.kind"] // "") | (. == "workflow" or . == "scope" or . == "spec"))
            or ((.metadata["gc.step_ref"] // "") != "")
            or ((.metadata["gc.step_id"] // "") != "")
            or ((.metadata["gc.root_bead_id"] // "") != "")
          ) | not))'
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
                                      Route <bead> raw (gc.routed_to, no formula)
                                      to the proactive pool for a first reaction.
                                      Exit 0 routed, $RC_ALREADY_REACTED already
                                      reacted (no-op, nothing routed), 1 error.
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
Security: any code a reaction produces takes the codex-gated mr path, enforced
by the pool env (GC_DEFAULT_MERGE_STRATEGY=mr) and the prompt, not by this router.
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
    # Drop never-claimable graph.v2 structural beads — topology roots and
    # formula steps (see exclude_graph_structural) — so the demand mirror
    # matches what gc hook --claim would offer, then rank by board weight and
    # slice to the worker page. The full routed set is read (--limit 0) and the
    # structural beads dropped BEFORE the slice, so — like the agent.toml
    # work_query this mirrors — a page filled by them cannot bury a claimable
    # subject behind them and understate demand to zero. The scarce proactive
    # slots then spend on the highest-priority work first (oldest within a
    # band), not whatever bd-ready returned oldest across all bands.
    printf '%s' "$r" | exclude_graph_structural | board_rank | jq --argjson n "$SCAN_LIMIT" '.[0:$n]'
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
#   - graph.v2 structural beads — topology roots (gc.kind in workflow/scope/
#     spec) AND formula step beads (gc.step_ref/gc.step_id/gc.root_bead_id set).
#     Both are issue_type task, so the allowlist misses them; a root is routed
#     only to name its run and a step advances its own workflow by closing its
#     own bead, so a first reaction must claim neither. Drop them explicitly.
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
# Plus a state predicate: not already reacted, not routed, has a description;
# deduped by id. "Not already reacted" drops the gc.first_reaction a completed
# reaction leaves — the same marker sling_first_reaction_guard refuses, so a
# reacted bead is dropped here and never reaches the sling loop to spend a cap
# slot.
scan_precision_filter() {
    local types_json markers_json
    types_json="$(printf '%s' "$PROACTIVE_TYPES" | jq -R 'split(",") | map(select(length > 0))')"
    # Durable work/lifecycle markers that mark a bead as work-in-flight rather
    # than raw input. Kept as one list so the review-lane keys and the
    # implementation-anchor keys share a single source of truth.
    markers_json='["branch","merge_result","work_dir","pr_url","pr_number","check_name","anchor_bead"]'
    jq --argjson types "$types_json" --argjson markers "$markers_json" '
        map(select(
            ((.metadata["gc.first_reaction"] // "") == "")
            and ((.metadata["gc.routed_to"] // "") == "")
            and ((.description // "") != "")
            and ((.issue_type // "") as $it | ($types | index($it)) != null)
            and ((
                ((.metadata["gc.kind"] // "") | (. == "workflow" or . == "scope" or . == "spec"))
                or ((.metadata["gc.step_ref"] // "") != "")
                or ((.metadata["gc.step_id"] // "") != "")
                or ((.metadata["gc.root_bead_id"] // "") != "")
              ) | not)
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
    local ranked
    if [ -n "$FIXTURE" ]; then
        local raw='[]'
        if [ -f "$FIXTURE/scan.json" ]; then raw="$(cat "$FIXTURE/scan.json")"; fi
        ranked="$(printf '%s' "$raw" | scan_precision_filter | board_rank)"
    else
        # (A) explicit opt-in: beads that asked for a first reaction. Pin --db so
        # the query hits this rig's ledger, not a cwd up-walk (see rig_beads_db).
        local optin movable db
        db="$(rig_beads_db)"
        # Read the FULL opt-in and movable sets (--limit 0), not a page.
        # scan_precision_filter drops work-in-flight beads (review lanes,
        # branch/PR anchors, topology roots), so bounding a query to the worker
        # page BEFORE the filter lets a page of now-dropped rows bury a raw input
        # past the bound — the union filters to empty while a real candidate sits
        # at row N+1. Read all, filter, rank, then slice (below), the same
        # filter-before-bound the demand mirror uses.
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
        optin="$(gc bd ready ${db:+--db "$db"} --metadata-field "gc.proactive=1" --unassigned \
                    --exclude-type=epic --json --sort oldest --limit 0 2>/dev/null || true)"
        [ -n "$optin" ] || optin='[]'

        # (B) movable-forward: any ready, unassigned, non-epic bead. The precision
        # filter below drops the ones a fresh first reaction must not touch.
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
        movable="$(gc bd ready ${db:+--db "$db"} --unassigned --exclude-type=epic --json \
                    --sort oldest --limit 0 2>/dev/null || true)"
        [ -n "$movable" ] || movable='[]'

        # Union the two sources, apply the shared precision filter, then rank by
        # board weight.
        ranked="$(jq -s '(.[0] + .[1])' <(printf '%s' "$optin") <(printf '%s' "$movable") \
            | scan_precision_filter | board_rank)"
    fi

    # Slice to the worker page (SCAN_LIMIT, 0 = unbounded) AFTER the filter and
    # rank, so the bound falls on real candidates and a --sling sweep spends its
    # limited headroom on the highest-priority ones first.
    printf '%s' "$ranked" | jq --argjson n "$SCAN_LIMIT" 'if $n == 0 then . else .[0:$n] end'
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
    local slung=0 skipped=0 reacted=0
    local ids
    ids="$(printf '%s' "$cands" | jq -r '.[].id')"
    local id
    for id in $ids; do
        if [ "$slung" -ge "$SLING_CAP" ]; then
            skipped=$(( skipped + 1 ))
            continue
        fi
        # Only a genuine dispatch spends the cap. cmd_sling skips an
        # already-reacted bead as a no-op and flags it in SLING_SKIPPED — a
        # reaction that landed after the scan selected it, since
        # scan_precision_filter drops the rest. Counting that skip is the
        # cap-starvation bug: stale reacted records would spend the whole cap
        # every sweep while no new reaction is slung.
        if cmd_sling "$id"; then
            if [ -n "$SLING_SKIPPED" ]; then
                reacted=$(( reacted + 1 ))
            else
                slung=$(( slung + 1 ))
            fi
        fi
    done
    local note=""
    if [ "$reacted" -gt 0 ]; then note=" ($reacted already reacted, not counted)"; fi
    if [ "$skipped" -gt 0 ]; then
        log "scan --sling: slung $slung first reaction(s)$note; $skipped candidate(s) left for the next sweep (cap $SLING_CAP, GC_PROACTIVE_SLING_CAP)"
    else
        log "scan --sling: slung $slung first reaction(s)$note"
    fi
}

# ---------------------------------------------------------------------------
# sling — route a bead RAW to the proactive pool for a first reaction: Lane 1,
# gc.routed_to only, no formula. The reaction's own mr-only invariant lives in
# the pool env and the prompt, not here (this router pins no merge path).
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

    # A first reaction happens once. Routing an already-reacted bead re-offers a
    # done reaction (see sling_first_reaction_guard), so skip it as an idempotent
    # no-op rather than clobber a live dispatch. cmd_sling returns 0 either way
    # and flags the skip out-of-band in SLING_SKIPPED: the in-process cmd_scan
    # --sling loop reads that flag to tell a skip from a dispatch and not spend a
    # cap slot on it, and the `sling` CLI verb in main() reads it to exit
    # RC_ALREADY_REACTED, the signal a cross-process caller needs. The return
    # stays 0 because a non-zero one cannot carry the distinction here: caught in
    # the loop's condition it would disable set -e for this function, and
    # returned to main it would read as the generic fail-closed error, not the
    # specific no-op.
    SLING_SKIPPED=""
    if ! sling_first_reaction_guard "$bead"; then
        SLING_SKIPPED=1
        return 0
    fi

    local target
    target="$(resolve_pool_target)"

    # --no-formula is load-bearing: the city's default_sling_formula is
    # mol-polecat-work, so a bare sling would POUR that formula instead of
    # leaving the bead a raw routed claim the reaction prompt reads. --reassign
    # clears any human assignee so the pool's --unassigned query can see it.
    set -- "$target" "$bead" --no-formula --reassign
    [ -n "$nudge" ] && set -- "$@" --nudge

    if [ -n "$dry" ]; then
        # Prove the command shape (the gate asserts --no-formula, no --on/--merge).
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
        log "$PROG: (fixture) would route $bead raw -> $target"
        printf 'gc sling %s\n' "$*"
        return 0
    fi

    log "$PROG: routing $bead raw -> $target"
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
        sling)
            cmd_sling "$@"
            # A skipped already-reacted bead is a no-op, not a dispatch: surface
            # it to a cross-process caller as RC_ALREADY_REACTED so it files its
            # own visit instead of waiting for a reaction that never ran.
            if [ -n "$SLING_SKIPPED" ]; then exit "$RC_ALREADY_REACTED"; fi
            ;;
        deliverable) cmd_deliverable "$@" ;;
        *) die "unknown verb '$verb' (demand|scan|sling|deliverable; --help)" ;;
    esac
}

main "$@"
