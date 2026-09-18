#!/usr/bin/env bash
# gc-proactive.sh — the proactive first-reaction engine (Bead-Universe Phase 4;
# v1 design specs/bead-universe/design-doc.md; reaction-bead model
# specs/tk-5n01ns/reaction-bead-first-reaction.md). A first reaction is inbox
# triage: read a freshly-filed bead once and dispose it (route to a pool, hold
# on an edge, file a visit, or supersede). A reaction is its OWN leased bead:
# `sling` FILES a reaction bead R that tracks the subject and routes R to the
# proactive pool, where a worker claims it, reads the subject, and disposes it.
# Exactly-once is the substrate's, keyed on R's identity — not a marker on the
# subject. This tool is the trigger layer:
#   demand [<pool>]      pool work_query — routed reaction beads, board-ranked
#   scan [--json|--sling] find movable-forward / opt-in subjects; --sling files
#                        a reaction bead at each, bounded by GC_PROACTIVE_SLING_CAP
#   sling <bead> [--nudge] [-n]  file a first reaction bead R tracking <bead>
#   deliverable          "would a routed bead be picked up?" — no when the
#                        city's agent roster says this pool cannot claim it
#                        (absent, suspended, or capped at zero), exit 0/1
# The pool's only throttle is its max_active_sessions
# (agents/proactive/agent.toml); routed reaction beads queue until a slot frees.
# GC_PROACTIVE_SLING_CAP is a different bound: how many one `scan --sling` sweep
# may file. Code a reaction routes still takes the codex-gated mr path — not on
# this router, but on the polecat pool the actionable exit routes the subject to
# (its GC_DEFAULT_MERGE_STRATEGY=mr).
# Tunables: GC_PROACTIVE_POOL / _SCAN_LIMIT / _SLING_CAP / _FIXTURE
# (test hook: canned ready/scan/agents/beads .json instead of gc calls).
set -euo pipefail

PROG="${0##*/}"

POOL_BASE="${GC_PROACTIVE_POOL:-gc-toolkit.proactive}"
SCAN_LIMIT="${GC_PROACTIVE_SCAN_LIMIT:-20}"
# What ONE --sling sweep may file. A first reaction can end in a route to the
# polecat pool, so an uncapped sweep is a queue of implementation sessions filed
# by one command. 5 is that pool's own max_active_sessions: a sweep never files
# more than the city can start working in one cycle.
SLING_CAP="${GC_PROACTIVE_SLING_CAP:-5}"
FIXTURE="${GC_PROACTIVE_FIXTURE:-}"
# The reaction sub-type stamped on R. One kind today; the key leaves room for
# others (a scheduled re-reaction) without a second dedup dimension.
REACTION_KIND="first-reaction"
# Set by cmd_sling to 1 when it skips a subject that already has an open
# reaction, else empty. cmd_scan's --sling loop reads it in-process to keep a
# skip from spending the cap; the `sling` CLI verb in main() translates it to
# RC_ALREADY_REACTED so a cross-process caller (gc-helm react, gc-visit-open)
# can tell the no-op from a dispatch and file its own visit rather than wait for
# a reaction that is already in flight.
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
# is rig-scoped and gc.routed_to is matched as an exact string, so a bare base
# is qualified from GC_RIG — failing CLOSED when GC_RIG is unset rather than
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
                die "cannot rig-qualify proactive target '$base': set GC_RIG or pass a <rig>/<base> target (the pool is rig-scoped — agents/proactive/agent.toml watches {{.Rig}}/gc-toolkit.proactive, and a bare gc.routed_to matches nobody)"
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

# rig_store_ref -> this rig's store ref (rig:<name>), stamped on a reaction bead
# so a worker and the dedup can name the subject's store. Empty when GC_RIG is
# unset; the subject and its reaction are same-store, so absence is not fatal.
rig_store_ref() {
    [ -n "${GC_RIG:-}" ] && printf 'rig:%s' "$GC_RIG"
    return 0
}

# reaction_absent_guard — a first reaction happens once AT A TIME. Refuse to
# file a second reaction bead while one is still open for this subject. The
# dedup key is (subject + kind): an open/in-progress task_kind=reaction bead
# that names this subject either by its gc.reaction_subject stamp OR by a tracks
# edge R --tracks--> subject. R normally carries both — the stamp rides its
# create call, the edge is wired right after — but the two writes are not atomic,
# so the stamp can land empty or unreadable while the edge stands; the spec
# dedups on EITHER signal (specs/tk-5n01ns/reaction-bead-first-reaction.md).
# Returns non-zero when such a reaction is already open, so the caller skips
# filing another. A COMPLETED reaction has closed its bead, so a later
# re-reaction (the subject became eligible again) is not blocked — the dedup
# keys on OPEN reactions, not on history. An unreadable store is not proof of
# absence: the guard proceeds only when it can positively read that none is
# open, and fails CLOSED (refuses to file) when the edge lookup errors.
reaction_absent_guard() {
    local bead="$1" existing
    if [ -n "$FIXTURE" ]; then
        [ -f "$FIXTURE/beads.json" ] || return 0
        # Match on the gc.reaction_subject stamp OR a tracks edge to the subject
        # (fixture edge shape: dependency_type + depends_on_id, as the scan.json
        # fixtures carry them).
        existing="$(jq -r --arg s "$bead" '
            [ to_entries[] | (.value + {id: .key})
              | select(((.metadata["task_kind"] // "") == "reaction")
                       and (((.status // "open")) as $st | ($st == "open" or $st == "in_progress"))
                       and (((.metadata["gc.reaction_subject"] // "") == $s)
                            or ([ (.dependencies // [])[]
                                  | select(((.dependency_type // .type) // "") == "tracks")
                                  | .depends_on_id ] | index($s) != null)))
              | .id ] | .[0] // ""' "$FIXTURE/beads.json" 2>/dev/null || printf '')"
    else
        local db; db="$(rig_beads_db)"
        # (a) the primary link: the gc.reaction_subject stamp.
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        existing="$(gc bd list ${db:+--db "$db"} --status open,in_progress \
                        --metadata-field "gc.reaction_subject=$bead" --limit 0 --json 2>/dev/null \
            | jq -r 'if type=="array" then [ .[]? | select((.metadata["task_kind"] // "") == "reaction") | .id ] | .[0] // "" else "" end' 2>/dev/null || printf '')"
        # (b) the fallback link: a tracks edge R --tracks--> subject, for a
        # reaction whose stamp landed empty or unreadable. `gc bd dep list
        # --direction=up` names the beads that track this subject; keep the
        # open/in-progress reactions. A readable store answers definitively — a
        # JSON array (the dependents, possibly none), or a "no issue found" error
        # object when the subject has no bead at all (so nothing tracks it) — and
        # both let the sling proceed. Anything else (empty output or a non-JSON
        # error: an unreadable store) is not proof of absence, so fail CLOSED and
        # refuse rather than risk a duplicate.
        if [ -z "$existing" ]; then
            local up
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
            up="$(gc bd dep list "$bead" ${db:+--db "$db"} --direction=up --type=tracks --json 2>/dev/null || true)"
            if printf '%s' "$up" | jq -e 'type=="array"' >/dev/null 2>&1; then
                existing="$(printf '%s' "$up" | jq -r '[ .[]? | select(((.metadata["task_kind"] // "") == "reaction") and ((.status // "") as $st | ($st == "open" or $st == "in_progress"))) | .id ] | .[0] // ""' 2>/dev/null || printf '')"
            elif ! printf '%s' "$up" | jq -e 'type=="object" and ((.error // "") | test("no issue"; "i"))' >/dev/null 2>&1; then
                log "$PROG: sling: could not read the tracks-edge dedup for $bead (gc bd dep list --direction=up returned no usable answer) — refusing to file a possible duplicate. Retry when the store is readable."
                return 1
            fi
        fi
    fi
    [ -z "$existing" ] && return 0
    log "$PROG: sling: $bead already has an open first reaction ($existing) — not filing another. A first reaction happens once at a time; it reacts when the pool claims $existing."
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
# on stdin: topology ROOTS (gc.kind in workflow/scope/spec) AND formula STEP
# beads (gc.step_ref / gc.step_id / gc.root_bead_id). A root is routed only to
# name its run and a step advances its own molecule; gc hook --claim offers
# neither as a subject, so a query that counts one spawns a worker that claims
# nothing (a root) or reacts to a formula step as if it were an input (a step).
# The gc binary's default pool query applies the roots clause on its worker and
# count forms; this broadens it to steps for the proactive custom queries, which
# inline the same predicate in agents/proactive/agent.toml's work_query +
# scale_check — keep all three in sync.
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
                                      proactive reaction beads, board-ranked.
                                      Read-only.
       $PROG scan [--json] [--sling]  Find movable-forward / opt-in subjects;
                                      with --sling, file a reaction bead at each,
                                      at most $SLING_CAP per sweep
                                      (GC_PROACTIVE_SLING_CAP). Read-only
                                      without --sling.
       $PROG sling <bead> [--nudge] [-n|--dry-run]
                                      File a first-reaction bead R that tracks
                                      <bead> and route it to the proactive pool.
                                      Exit 0 filed, $RC_ALREADY_REACTED a
                                      reaction is already open (no-op), 1 error.
       $PROG deliverable [<pool-target>]
                                      Would work routed at that pool actually
                                      be PICKED UP? No when this city's agent
                                      roster says it cannot: absent, suspended,
                                      or capped at zero slots. Defaults to the
                                      proactive pool; any rig-qualified target
                                      answers. Exit 0 yes, 1 no; callers divert
                                      on no.

Budget: the pool cap (agents/proactive/agent.toml max_active_sessions) throttles
how many run at once; routed reaction beads queue until a slot frees. One
--sling sweep files at most $SLING_CAP reactions.
EOF
}

# ---------------------------------------------------------------------------
# deliverable [<pool-target>] — "if I route work there right now, will anything
# ever pick it up?" The default target is the proactive pool; the first
# reaction's actionable exit asks the same question about the pool it is about
# to hand a bead to."
# The queue is not the question: a routed bead waits at zero cost until a slot
# frees. What makes a route vanish is a pool that cannot claim it at all, and
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
            printf 'no: no agent is registered at %s in this city, so a routed reaction routes to nobody\n' "$target"
            return 1 ;;
        suspended)
            printf 'no: the pool at %s is suspended; a routed reaction would sit unclaimed until it resumes\n' "$target"
            return 1 ;;
        nocap)
            printf 'no: the pool at %s has no session slots (max_active_sessions is 0), so nothing can claim a routed reaction\n' "$target"
            return 1 ;;
        present)
            printf 'yes: %s is registered and unsuspended — its cap only queues a routed reaction, never drops it\n' "$target"
            return 0 ;;
        *)
            printf 'yes: could not read this city agent roster, so the pool is assumed live — an unreadable roster is not evidence that %s is gone\n' "$target"
            return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# demand — the proactive pool's work_query: the standard pool demand (ready,
# unassigned, routed-to-us beads), board-ranked. The reconciler runs this to
# decide whether to spawn a proactive worker. The routed beads are reaction
# beads now, not subjects.
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
    # Drop never-claimable graph-structural beads (see exclude_graph_structural)
    # so the demand mirror matches what gc hook --claim would offer, then rank by
    # board weight and slice to the worker page. The full routed set is read
    # (--limit 0) and structural beads dropped BEFORE the slice, so — like the
    # agent.toml work_query this mirrors — a page filled by structural beads
    # cannot bury a claimable reaction behind them and understate demand to zero.
    printf '%s' "$r" | exclude_graph_structural | board_rank | jq --argjson n "$SCAN_LIMIT" '.[0:$n]'
}

# ---------------------------------------------------------------------------
# scan — the PROCESS-SCAN trigger. Find raw INPUT beads "able to be updated":
# open, ready, unassigned, an allowlisted issue_type (GC_PROACTIVE_TYPES),
# top-level, and not already routed / machinery (so we never react to
# work-in-flight or to a reaction bead). Unions the explicit per-bead opt-in
# (gc.proactive=1) with the broader movable-forward scan, deduped and
# precision-filtered (see scan_candidates). Read-only unless --sling. The
# per-subject "a reaction is already open" dedup is at sling time, not here (see
# reaction_absent_guard).
# ---------------------------------------------------------------------------

# scan_precision_filter — from a candidate array on stdin, keep only raw
# top-level INPUT beads a fresh first reaction may target. Each clause drops a
# distinct non-input population:
#   - ALLOWLIST issue_type ($types, GC_PROACTIVE_TYPES) — drops convoy/epic/
#     step/molecule/spec/decision by omission.
#   - graph-structural beads (topology roots gc.kind in workflow/scope/spec,
#     and formula step beads gc.step_ref/gc.step_id/gc.root_bead_id) — a
#     workflow root is issue_type task, so the allowlist misses it; a step bead
#     is a task too. Reacting to either writes over a live molecule.
#   - task_kind=reaction — a reaction bead is this tool's own output, not an
#     input; it is also routed, so the route clause drops it too, but naming it
#     keeps a reaction from ever being a subject.
#   - task_kind=feedback-pattern — distiller-loop machinery, not an input.
#   - task_kind=review — a dispatched signoff lane, work-in-flight.
#   - durable work/lifecycle markers ($markers) — a review lane carries
#     check_name/anchor_bead; an implementation anchor carries branch/
#     merge_result/work_dir/pr_url/pr_number. An anchor is an issue_type
#     task/bug bead with no task_kind, so the allowlist and the task_kind
#     clauses both miss it, and its markers are the only signal that the work
#     is already in motion. Filing a reaction at either reacts to work-in-flight,
#     which the proactive scope forbids.
#   - gc.takeaway / gc.takeaway_by — a sitting has already RULED this bead.
#   - top-level only — a parent-child CHILD carries the edge in its own
#     .dependencies; a convoy's tracks edge lives on the convoy, so this
#     catches parented beads, not every convoy member.
# Plus a state predicate: not routed, has a description; deduped by id. A subject
# that already has an open reaction is NOT dropped here — that dedup needs a
# per-bead query (reaction_absent_guard at sling time), and a completed reaction
# has already routed/held/closed the subject, so this filter's route/marker
# clauses drop it then.
scan_precision_filter() {
    local types_json markers_json
    types_json="$(printf '%s' "$PROACTIVE_TYPES" | jq -R 'split(",") | map(select(length > 0))')"
    # Durable work/lifecycle markers that mark a bead as work-in-flight rather
    # than raw input. Kept as one list so the review-lane keys and the
    # implementation-anchor keys share a single source of truth.
    markers_json='["branch","merge_result","work_dir","pr_url","pr_number","check_name","anchor_bead"]'
    jq --argjson types "$types_json" --argjson markers "$markers_json" '
        map(select(
            ((.metadata["gc.routed_to"] // "") == "")
            and ((.description // "") != "")
            and ((.issue_type // "") as $it | ($types | index($it)) != null)
            and (((.metadata["gc.kind"] // "") | (. == "workflow" or . == "scope" or . == "spec")) | not)
            and ((.metadata["gc.step_ref"] // "") == "")
            and ((.metadata["gc.step_id"] // "") == "")
            and ((.metadata["gc.root_bead_id"] // "") == "")
            and ((.metadata["task_kind"] // "") != "reaction")
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
        # branch/PR anchors, structural beads), so bounding a query to the worker
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

    # --sling: file a reaction at each candidate, highest board weight first, and
    # stop at SLING_CAP. The cap is the throttle that matters now that a reaction
    # can end in a route to an implementation pool: without it one sweep files as
    # many downstream sessions as the scan found candidates. What it skips is
    # named, not silently dropped — the next sweep sees the same subjects, since
    # a subject only leaves the scan once a reaction has advanced it.
    local slung=0 skipped=0 reacted=0
    local ids
    ids="$(printf '%s' "$cands" | jq -r '.[].id')"
    local id
    for id in $ids; do
        if [ "$slung" -ge "$SLING_CAP" ]; then
            skipped=$(( skipped + 1 ))
            continue
        fi
        # Only a genuine dispatch spends the cap. cmd_sling skips a subject that
        # already has an open reaction as a no-op and flags it in SLING_SKIPPED —
        # a reaction filed after the scan selected it, or one still running.
        # Counting that skip is the cap-starvation bug: a subject with a live
        # reaction would spend the whole cap every sweep while no new reaction is
        # filed.
        if cmd_sling "$id"; then
            if [ -n "$SLING_SKIPPED" ]; then
                reacted=$(( reacted + 1 ))
            else
                slung=$(( slung + 1 ))
            fi
        fi
    done
    local note=""
    if [ "$reacted" -gt 0 ]; then note=" ($reacted already reacting, not counted)"; fi
    if [ "$skipped" -gt 0 ]; then
        log "scan --sling: filed $slung first reaction(s)$note; $skipped candidate(s) left for the next sweep (cap $SLING_CAP, GC_PROACTIVE_SLING_CAP)"
    else
        log "scan --sling: filed $slung first reaction(s)$note"
    fi
}

# ---------------------------------------------------------------------------
# sling — file a first-reaction bead R that tracks <bead> and route it to the
# proactive pool. R is a plain task; no formula is poured on it and the subject
# is not routed — the subject stays clean until R disposes it. R carries its own
# route, so the un-clearable-execution-route pain of pouring a workflow onto a
# bead that is not that workflow's work never arises.
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

    # A first reaction happens once at a time. If one is already open for this
    # subject, skip as an idempotent no-op rather than file a duplicate. cmd_sling
    # returns 0 either way and flags the skip out-of-band in SLING_SKIPPED: the
    # in-process cmd_scan --sling loop reads that flag to tell a skip from a
    # dispatch and not spend a cap slot on it, and the `sling` CLI verb in main()
    # reads it to exit RC_ALREADY_REACTED, the signal a cross-process caller
    # needs. The return stays 0 because a non-zero one cannot carry the
    # distinction here: caught in the loop's condition it would disable set -e for
    # this function, and returned to main it would read as the generic
    # fail-closed error, not the specific no-op.
    SLING_SKIPPED=""
    if ! reaction_absent_guard "$bead"; then
        SLING_SKIPPED=1
        return 0
    fi

    local target
    target="$(resolve_pool_target)"

    local store_ref subject_title
    store_ref="$(rig_store_ref)"
    # A short title for the reaction bead; the subject's own title, when
    # readable, orients a reader of the board and the reaction's own row.
    if [ -n "$FIXTURE" ]; then
        subject_title="$(jq -r --arg id "$bead" '.[$id].title // ""' "$FIXTURE/beads.json" 2>/dev/null || printf '')"
    else
        local db; db="$(rig_beads_db)"
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
        subject_title="$(gc bd show "$bead" ${db:+--db "$db"} --json 2>/dev/null \
            | jq -r 'if type=="array" then (.[0].title // "") else "" end' 2>/dev/null || printf '')"
    fi
    local title="react: $bead${subject_title:+ — $subject_title}"
    # bd caps a title at 500 bytes; keep the reaction title well under it.
    title="$(printf '%s' "$title" | cut -c1-200)"

    # R's markers ride the CREATE call, so R is born routed and tracking its
    # subject in one atomic write — no window where a half-made reaction sits
    # unrouted (orphaned) or unlinked. task_kind=reaction is the dedup and
    # pool-query key; gc.reaction_subject is the subject; gc.routed_to routes R
    # to the proactive pool.
    local meta
    meta="$(jq -nc --arg t "$target" --arg s "$bead" --arg ss "$store_ref" --arg k "$REACTION_KIND" '
        {"task_kind":"reaction","gc.reaction_kind":$k,"gc.reaction_subject":$s,"gc.routed_to":$t}
        + (if $ss != "" then {"gc.reaction_subject_store":$ss} else {} end)')"

    if [ -n "$dry" ]; then
        printf 'gc bd create -t task --title %q --metadata %q  # then: gc bd dep add <R> %s --type=tracks\n' "$title" "$meta" "$bead"
        return 0
    fi

    if [ -n "$FIXTURE" ]; then
        # The fixture hook stands in for every gc call in this tool: a --sling
        # sweep under test must exercise the loop and its cap without filing
        # anything into a live city.
        log "$PROG: (fixture) would file a reaction bead tracking $bead -> $target"
        printf 'gc bd create -t task --title %q --metadata %q\n' "$title" "$meta"
        printf 'gc bd dep add <R> %s --type=tracks\n' "$bead"
        return 0
    fi

    local db reaction
    db="$(rig_beads_db)"
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
    reaction="$(gc bd create ${db:+--db "$db"} -t task --title "$title" --metadata "$meta" \
        -d "First reaction to $bead: read it, write a first-reaction card, and dispose it (route / hold / visit / supersede) per agents/proactive/prompt.template.md. This bead is the reaction's own work unit; closing it records the reaction done." \
        --json 2>/dev/null | jq -r 'if type=="array" then (.[0].id // "") else (.id // "") end' 2>/dev/null || printf '')"
    [ -n "$reaction" ] && [ "$reaction" != "null" ] \
        || die "sling: could not file the reaction bead for $bead — nothing was routed"

    # The tracks edge records lineage; gc.reaction_subject is the primary link a
    # worker resolves, so a failed edge is not fatal (the stamp still names S).
    # tracks, NOT parent-child: a parent-child edge transmits the subject's
    # blocked state to R, making it unclaimable exactly where a reaction is owed.
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
    gc bd dep add "$reaction" "$bead" ${db:+--db "$db"} --type=tracks >/dev/null 2>&1 \
        || log "$PROG: sling: filed reaction $reaction but could not add the tracks edge to $bead; gc.reaction_subject still names it. Wire it by hand: gc bd dep add $reaction $bead --type=tracks"

    log "$PROG: filed first reaction $reaction tracking $bead -> $target"
    if [ -n "$nudge" ]; then
        gc session nudge "$target" "A first reaction ($reaction) is routed to you; claim it with gc hook --claim." >/dev/null 2>&1 || true
    fi
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
            # A subject that already has an open reaction is a no-op, not a
            # dispatch: surface it to a cross-process caller as RC_ALREADY_REACTED
            # so it files its own visit instead of waiting for a reaction that is
            # already in flight.
            if [ -n "$SLING_SKIPPED" ]; then exit "$RC_ALREADY_REACTED"; fi
            ;;
        deliverable) cmd_deliverable "$@" ;;
        *) die "unknown verb '$verb' (demand|scan|sling|deliverable; --help)" ;;
    esac
}

main "$@"
