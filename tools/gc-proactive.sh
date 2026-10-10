#!/usr/bin/env bash
# gc-proactive.sh — the proactive-via-slung-mol engine (Bead-Universe Phase 4;
# v1 design specs/bead-universe/design-doc.md, still governing this tool).
# "Proactive" is NOT a resident loop: it is mol-first-reaction slung at a
# bead (read body → write a first-reaction CARD → dispose: route it to a pool,
# hold it on an edge, or put it to the operator as a human gate) so the human
# arrives at advanced work, and at fewer beads. This tool is the trigger layer:
#   demand [<pool>]      pool work_query — routed beads, board-ranked
#   scan [--json|--sling] find movable-forward / opt-in beads; --sling reacts,
#                        bounded by GC_PROACTIVE_SLING_CAP per sweep
#   sling <bead> [--nudge] [-n]  sling a first reaction (mr path, hard-refuses
#                        --merge direct — the security invariant)
#   deliverable [bead]   "would a sling be picked up?" — no when the city's
#                        agent roster says this pool cannot pick it up
#                        (absent, suspended, or capped at zero), or when the
#                        named bead lives in a store the pool's rig does not
#                        own (cross-store route), exit 0/1
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
# Set by cmd_sling when it skips a bead as a no-op, else empty: "reacted" when
# the bead already carries a first reaction, "dispatch-path" when it already has
# a route or an arm, "live-workflow" when a live workflow already drives it.
# cmd_scan's --sling loop reads it in-process to keep a skip from spending the
# cap; the `sling` CLI verb in main() translates it to RC_ALREADY_REACTED,
# RC_DISPATCH_PATH or RC_LIVE_WORKFLOW so a cross-process caller (gc-helm react,
# gc-visit-open) can tell the no-op from a dispatch, name its cause, and file its
# own visit rather than wait for a reaction that never ran.
SLING_SKIPPED=""
# Exit codes the `sling` CLI verb uses for those skips — distinct from a
# dispatch (0) and an error (1), so a caller that needs a NEW reaction can
# branch on them.
RC_ALREADY_REACTED=3
RC_LIVE_WORKFLOW=4
RC_DISPATCH_PATH=5
# The issue types a first reaction may target — an ALLOWLIST (fail-safe): a
# new bead type earns reactions only when added here deliberately. Tunable per
# rig via GC_PROACTIVE_TYPES without a code change. The default excludes the
# convoy, epic, step and molecule types (machinery or work-in-flight), decision
# (already a surfaced human choice) and spec (an output, not a raw input). A
# graph.v2 pour does not retype its steps as step, so a workflow root and most
# of its steps are issue_type task, which this list admits.
# scan_precision_filter drops them by gc.kind and gc.step_ref.
PROACTIVE_TYPES="${GC_PROACTIVE_TYPES:-task,bug,feature,spike}"
# The one definition of the standing kinds, shared with the liveness sweep and
# the doctor checks. Exposes $STANDING_KINDS_JQ, which scan_precision_filter
# applies.
# shellcheck source=../assets/scripts/standing-kinds.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../assets/scripts/standing-kinds.sh" \
    || { printf '%s: cannot source assets/scripts/standing-kinds.sh from the pack\n' "$PROG" >&2; exit 1; }
# The one definition of a dispatch path, shared with the doctor checks. Exposes
# $DISPATCH_PATH_JQ, which scan_precision_filter applies.
# shellcheck source=../assets/scripts/dispatch-path.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../assets/scripts/dispatch-path.sh" \
    || { printf '%s: cannot source assets/scripts/dispatch-path.sh from the pack\n' "$PROG" >&2; exit 1; }

log()  { printf '%s\n' "$*" >&2; }
die()  { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

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
# re-start mol-first-reaction on a bead that already carries one. On an
# already-reacted bead first-reaction-dispose.sh refuses the second dispose, so a
# second reaction disposes of nothing, and what it does to the route the first
# disposition set depends on the gc that starts it. mol-first-reaction declares
# retain_input_routes. A gc that reads the key leaves that route live, so its
# pool can hand the bead to a worker while the second reaction runs. A gc that
# does not retires the route and puts nothing in its place, leaving the bead
# disposed-looking but offered to no pool. gc.first_reaction is stamped by the
# dispose before it acts, gc.proactive_reaction by the release; either proves a
# completed reaction. The subject is read from the fixture under test, live
# otherwise; an unreadable bead is not proof of a reaction, so it proceeds.
# Returns non-zero when the bead is already reacted, so the caller skips the
# sling.
sling_first_reaction_guard() {
    local bead="$1" meta fr pr ro detail
    if [ -n "$FIXTURE" ]; then
        [ -f "$FIXTURE/beads.json" ] || return 0
        meta="$(jq -c --arg id "$bead" '.[$id].metadata // {}' "$FIXTURE/beads.json" 2>/dev/null || printf '{}')"
    else
        local db; db="$(rig_beads_db)"
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        meta="$(gc bd show "$bead" ${db:+--db "$db"} --json 2>/dev/null \
            | jq -c 'if type=="array" then (.[0].metadata // {}) else {} end' 2>/dev/null || printf '{}')"
    fi
    # A live operator intake (gc-helm engage --new-subject) marks the subject
    # gc.reaction_owned=1 and handles it end-to-end — it has already filed the
    # one visit and spawned the sitting. Refuse to sling a first reaction that
    # would only file a SECOND visit for a conversation already under way.
    ro="$(printf '%s' "$meta" | jq -r '."gc.reaction_owned" // ""' 2>/dev/null || printf '')"
    if [ "$ro" = "1" ]; then
        log "$PROG: sling: $bead carries gc.reaction_owned=1 — a live operator intake is handling it end-to-end and has filed its one visit. Not slinging a first reaction that would file a second."
        return 1
    fi
    fr="$(printf '%s' "$meta" | jq -r '."gc.first_reaction" // ""' 2>/dev/null || printf '')"
    pr="$(printf '%s' "$meta" | jq -r '."gc.proactive_reaction" // ""' 2>/dev/null || printf '')"
    [ -n "$fr" ] || [ "$pr" = "1" ] || return 0
    detail="gc.first_reaction=${fr:-<unset>}, gc.proactive_reaction=${pr:-<unset>}"
    log "$PROG: sling: $bead already carries a first reaction ($detail) — not re-slinging. A first reaction happens once: a second one disposes of nothing, and it either leaves the bead's route live beside it or retires that route and leaves the bead offered to no pool. Clear the reaction marker to re-react."
    return 1
}

# sling_dispatch_path_guard — a first reaction never second-guesses a dispatch
# someone already decided, so refuse to start mol-first-reaction on a bead that
# has a dispatch path (has_dispatch_path, assets/scripts/dispatch-path.sh): a
# route or a deferred-dispatch arm. scan_precision_filter keeps such a bead out
# of every sweep; this guard holds the same line for a bead named directly, the
# way gc-helm react and gc-visit-open reach the sling. mol-first-reaction
# declares retain_input_routes, so a gc that reads the key leaves a route live
# when the reaction starts. The pool that serves the route could then hand the
# bead to a worker mid-reaction, and the disposition's release would reopen and
# unassign it under that worker. An arm is no safer: the deferred-dispatch
# reconcile pass slings it without reading any reaction.
#
# Returns 0 when the bead has no dispatch path, 1 when it has one, and 2 when its
# metadata cannot be read. A failed read is not proof that it has none, so the
# caller fails closed on 2. bd's not-found error is an answer: a bead that does
# not exist has no dispatch path, and gc sling names it missing. The read comes
# from the fixture under test (beads.json), live otherwise.
sling_dispatch_path_guard() {
    local bead="$1" shown="" meta paths
    local unreadable="$PROG: sling: cannot tell whether $bead already has a dispatch path (its metadata could not be read) — not slinging. A reaction to a routed or armed bead races the dispatch already decided for it; retry once the store answers."
    if [ -n "$FIXTURE" ]; then
        [ -f "$FIXTURE/beads.json" ] || return 0
        meta="$(jq -c --arg id "$bead" '.[$id].metadata // {}' "$FIXTURE/beads.json" 2>/dev/null)" \
            || { log "$unreadable"; return 2; }
    else
        local db; db="$(rig_beads_db)"
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        shown="$(gc bd show "$bead" ${db:+--db "$db"} --json 2>/dev/null)" || {
            if printf '%s' "$shown" | jq -e 'type == "object" and ((.error // "") | test("no issues? found"))' >/dev/null 2>&1; then
                return 0
            fi
            log "$unreadable"; return 2
        }
        meta="$(printf '%s' "$shown" | scrub \
            | jq -c 'if type == "array" and length == 1 then (.[0].metadata // {}) else error("unreadable") end' 2>/dev/null)" \
            || { log "$unreadable"; return 2; }
    fi
    # Each key is asked on its own through the shared predicate, so the log can
    # name the path it found without a second definition of one.
    paths="$(printf '%s' "$meta" | jq -r "$DISPATCH_PATH_JQ"'
        . as $m | [ dispatch_path_keys[] as $k
                    | select({metadata: {($k): $m[$k]}} | has_dispatch_path)
                    | "\($k)=\($m[$k])" ] | join(", ")' 2>/dev/null)" \
        || { log "$unreadable"; return 2; }
    [ -n "$paths" ] || return 0
    log "$PROG: sling: $bead already has a dispatch path ($paths) — not slinging a first reaction. Whoever routed or armed it already decided its dispatch, and a reaction would race the pool or the arm that serves it. File the visit directly, or react once that route or arm is cleared."
    return 1
}

# LIVE_WORKFLOW_JQ — the one definition of "a live workflow drives this bead",
# read by scan_drop_inflight and sling_live_workflow_guard. A convoy-first pour
# (gc sling <target> <bead> --on <formula>) links its root to the bead only
# through the root's gc.input_convoy_id, which names a convoy that tracks the
# bead. A root is live until it closes. Liveness decides, never
# gc.execution_routed_to: the pour stamps that key on the bead and it outlives
# the workflow, so keying on it would keep holding a bead whose workflow is
# gone. The definitions:
#   one_array      the rows of one slurped read. Anything but one JSON array is
#                  an error, an empty read included.
#   tracks_edge    a dependency row of type tracks, in either shape bd prints:
#                  dependency_type on a `bd dep list` row, type on a row of a
#                  `bd list` bead's dependencies.
#   live_drivers($roots; $edges)
#                  the {bead, root} pairs in which a live workflow root names the
#                  convoy of a {convoy, bead} tracks edge. root reads
#                  "<id> (<formula>)".
# Each caller takes its own reads, fresh, and keeps its own stance on a read
# that fails.
LIVE_WORKFLOW_JQ='
def one_array: if length == 1 and (.[0] | type) == "array" then .[0] else error("unreadable") end;
def tracks_edge: ((.dependency_type // .type) // "") == "tracks";
def live_drivers($roots; $edges):
  [ $roots[]
    | select((.status // "") != "closed")
    | select((.metadata["gc.kind"] // "") == "workflow")
    | {convoy: (.metadata["gc.input_convoy_id"] // ""),
       root: "\(.id) (\(.metadata["gc.formula_name"] // "unknown formula"))"}
    | select(.convoy != "") ] as $live
  | [ $edges[] as $e | $live[] | select(.convoy == $e.convoy) | {bead: $e.bead, root} ];
'

# workflow_roots_read [db] — the one read of the workflow roots: every bead that
# names an input convoy, ephemeral wisps included, without its free-form text,
# scrubbed for jq. Non-zero when the read fails. Callers pass the result to jq
# through --slurpfile, not --argjson: the list can outgrow the kernel's 128 KiB
# limit on one argument.
workflow_roots_read() {
    local db="${1:-}"
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd list ${db:+--db "$db"} --has-metadata-key gc.input_convoy_id \
        --include-ephemeral --brief --json --limit 0 2>/dev/null | scrub
}

# sling_live_workflow_guard — a first reaction never races a live workflow, so
# refuse to start mol-first-reaction on a bead one already drives
# (LIVE_WORKFLOW_JQ). gc sling refuses a second live workflow of the SAME
# formula on a bead but treats a different formula as concurrent work, so it
# pours a reaction beside a queued mol-polecat-work. The scan's work-in-flight
# markers (branch, work_dir) land only at that polecat's workspace-setup, so
# until then nothing else stops the reaction, and its disposition can route,
# hold or close the bead while the polecat builds it.
#
# The guard takes its reads for each bead it is about to sling, never from the
# scan's reads at the start of the sweep, because a pour can land while the
# sweep runs: the deferred-dispatch order slings an armed bead once its
# blockers close, and anyone can run gc sling. It reads the convoys tracking the
# bead, of every status, and the workflow roots.
#
# Returns 0 when no live workflow drives the bead, 1 when one does, and 2 when
# a read fails. A failed read is not proof that none does, so the caller fails
# closed on 2. Every convoy-first pour leaves a convoy tracking its bead, so the
# roots are read only for a bead that has one. The reads come from the fixture
# under test (the bead's "dependents" in beads.json, and roots.json), live
# otherwise.
sling_live_workflow_guard() {
    local bead="$1" tracks convoys roots live db=""
    local unreadable="$PROG: sling: cannot tell whether a live workflow already drives $bead (its tracking convoys or the workflow roots could not be read) — not slinging. A reaction that raced one could dispose of work in flight; retry once the store answers."
    if [ -n "$FIXTURE" ]; then
        tracks='[]'
        if [ -f "$FIXTURE/beads.json" ]; then
            tracks="$(jq -c --arg id "$bead" '.[$id].dependents // []' "$FIXTURE/beads.json" 2>/dev/null)" || tracks=''
        fi
    else
        db="$(rig_beads_db)"
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        tracks="$(gc bd dep list "$bead" ${db:+--db "$db"} --direction up -t tracks --json 2>/dev/null)" || {
            # bd's not-found error is an answer: no workflow drives a bead that
            # does not exist, and gc sling names it missing. Any other failure
            # leaves the question open.
            if printf '%s' "$tracks" | jq -e 'type == "object" and ((.error // "") | test("no issues? found"))' >/dev/null 2>&1; then
                return 0
            fi
            tracks=''
        }
    fi
    convoys="$(printf '%s' "$tracks" | jq -cs "$LIVE_WORKFLOW_JQ"'
        one_array | [ .[] | select(tracks_edge) | .id ]' 2>/dev/null)" || { log "$unreadable"; return 2; }
    [ "$convoys" != "[]" ] || return 0

    if [ -n "$FIXTURE" ]; then
        roots='[]'
        if [ -f "$FIXTURE/roots.json" ]; then roots="$(cat "$FIXTURE/roots.json")"; fi
    else
        roots="$(workflow_roots_read "$db")" || roots=''
    fi
    live="$(jq -rn --arg bead "$bead" --argjson convoys "$convoys" --slurpfile r <(printf '%s' "$roots") "$LIVE_WORKFLOW_JQ"'
        live_drivers($r | one_array; [ $convoys[] | {convoy: ., bead: $bead} ])
        | map(.root) | unique | join(", ")' 2>/dev/null)" || { log "$unreadable"; return 2; }
    [ -n "$live" ] || return 0
    log "$PROG: sling: $bead is already driven by live workflow(s) $live — not slinging a first reaction. A reaction would race work in flight: its disposition can route, hold or close the bead while that workflow runs. React once the workflow's root closes."
    return 1
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
                                      direct (the security invariant). Exit 0
                                      slung, $RC_ALREADY_REACTED already reacted,
                                      $RC_DISPATCH_PATH already routed or armed,
                                      $RC_LIVE_WORKFLOW already driven by a live
                                      workflow (each a no-op, nothing slung), 1
                                      error.
       $PROG deliverable [<pool-target>] [<bead>]
                                      Would work routed at that pool actually
                                      be PICKED UP? No when this city's agent
                                      roster says it cannot (absent, suspended,
                                      or capped at zero slots), or when <bead>
                                      is named and the target's rig does not own
                                      the bead's store (a rig-scope pool never
                                      claims another store's bead). Defaults to
                                      the proactive pool; any rig-qualified
                                      target answers. Exit 0 yes, 1 no; callers
                                      divert on no.

Budget: the pool cap (agents/proactive/agent.toml max_active_sessions) throttles
how many run at once; routed beads queue until a slot frees. One --sling sweep
hands out at most $SLING_CAP reactions.
Security: proactive output is mr-only
(GC_PROACTIVE_MERGE=$MERGE; "direct" is refused).
EOF
}

# ---------------------------------------------------------------------------
# deliverable [<pool-target>] [<bead>] — "if I route work there right now, will
# anything ever pick it up?" The default target is the proactive pool; the first
# reaction's actionable exit asks the same question about the pool it is about
# to hand a bead to."
# The queue is not the question: a routed bead waits at zero cost until a slot
# frees. Two things make a sling vanish. A pool that cannot claim it at all,
# which the city's own agent roster shows: the pool is not registered in this
# city, it is suspended, or it is capped at zero slots. And a pool that reads a
# different store than the bead lives in: a rig-scope pool only ever claims
# beads in its own rig's store, so a route whose rig does not own the bead's id
# prefix is offered by nobody, the shape `gc sling` refuses as
# CrossStoreRouteError. The store check is answerable only when the caller names
# the bead, so it is skipped when <bead> is absent.
#
# NO is a positive finding only. A roster or rig list this cannot read answers
# YES, because an unreadable one is not evidence of an absent or wrong-store
# pool, and a false no silently retires the framing every caller diverts from
# (assets/scripts/gc-visit-open.sh files a bare visit on a no).
# ---------------------------------------------------------------------------
cmd_deliverable() {
    local target bead roster verdict riglist bead_prefix target_rig target_prefix bead_rig
    target="$(resolve_pool_target "${1:-}" 2>/dev/null)" || {
        printf 'no: cannot rig-qualify the proactive pool target (set GC_RIG or pass <rig>/<base>) — a bare name routes to nobody\n'
        return 1
    }
    bead="${2:-}"

    # Store-ownership arm. A rig-scope pool reads only its own rig's store, so a
    # bead whose id prefix that rig does not own is open, unassigned and offered
    # to nobody — the pool's find-work queries its store and never sees it. Refuse
    # it here, before the route is written, the way `gc sling` refuses it at the
    # sling (CrossStoreRouteError). Positive finding only: an unreadable rig list,
    # or a rig or prefix this cannot resolve, falls through to the roster arm.
    if [ -n "$bead" ]; then
        if [ -n "$FIXTURE" ]; then
            riglist=""
            [ -f "$FIXTURE/rigs.json" ] && riglist="$(cat "$FIXTURE/rigs.json")"
        else
            riglist="$(gc rig list --json 2>/dev/null || true)"
        fi
        if [ -n "$riglist" ]; then
            bead_prefix="${bead%%-*}"
            target_rig="${target%%/*}"
            target_prefix="$(printf '%s' "$riglist" \
                | jq -r --arg n "$target_rig" '.rigs[]? | select((.name // "") == $n) | .prefix // ""' 2>/dev/null \
                | head -n1 || true)"
            if [ -n "$target_prefix" ] && [ "$target_prefix" != "$bead_prefix" ]; then
                bead_rig="$(printf '%s' "$riglist" \
                    | jq -r --arg p "$bead_prefix" '.rigs[]? | select((.prefix // "") == $p) | .name // ""' 2>/dev/null \
                    | head -n1 || true)"
                printf 'no: %s reads the %s store (prefix %s-) but %s lives in the %s store (prefix %s-) — a rig-scope pool only ever claims beads in its own store, so a reaction routed there is open, unassigned and offered to nobody (cross-store route; gc sling refuses this as CrossStoreRouteError)\n' \
                    "$target" "$target_rig" "$target_prefix" "$bead" "${bead_rig:-<no rig owns prefix $bead_prefix->}" "$bead_prefix"
                return 1
            fi
        fi
    fi

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
        # resolve_pool_target dies (with the "set GC_RIG or pass <rig>/<base>"
        # guidance) on an unset GC_RIG; fail the demand query closed rather than
        # query with an empty route that matches nothing.
        target="$(resolve_pool_target "${1:-}")" || return 1
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
# top-level, and not already reacted-to / routed or armed / machinery (so we
# never re-react and never react to work-in-flight). Unions the explicit per-bead
# opt-in (gc.proactive=1) with the broader movable-forward scan, deduped and
# precision-filtered (see scan_candidates). Read-only unless --sling.
# ---------------------------------------------------------------------------

# scan_precision_filter — from a candidate array on stdin, keep only raw
# top-level INPUT beads a fresh first reaction may target. Each clause drops a
# distinct non-input population:
#   - ALLOWLIST issue_type ($types, GC_PROACTIVE_TYPES) — drops the convoy/
#     epic/step/molecule/spec/decision types by omission.
#   - topology roots (gc.kind in workflow/scope/spec) — a workflow root is
#     issue_type task, so the allowlist misses it; drop it explicitly.
#   - molecule steps (gc.step_ref) — most graph.v2 steps are issue_type task
#     too, and a graph.v2 step has no parent-child edge: a tracks edge, or
#     gc.root_bead_id alone, ties it to its root. So neither the allowlist nor
#     the top-level clause drops it. Every step a pour mints carries
#     gc.step_ref, control steps such as workflow-finalize included. A step
#     advances only through its own molecule, so a first reaction has no
#     disposition to make on it.
#   - a standing kind (is_standing_kind, assets/scripts/standing-kinds.sh) — a
#     standing record is open and unrouted by design and never closes, so a
#     reaction has no disposition to make on it.
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
# Plus a state predicate: not already reacted, no dispatch path, has a
# description; deduped by id. "Not already reacted" drops EITHER marker a
# completed reaction leaves — gc.proactive_reaction (the release) and
# gc.first_reaction (the dispose) — the same pair sling_first_reaction_guard
# refuses, so a reacted bead is dropped here and never reaches the sling loop
# to spend a cap slot.
#   - gc.reaction_owned — a live owner already owns reacting to this bead, so an
#     autonomous first reaction would duplicate it. An operator engage (gc-helm
#     engage --new-subject) is the setter today: it creates the subject marked,
#     files the ONE visit, and spawns the sitting itself. The marker is set in
#     the create write, so the scan never sees the subject unmarked; dropping it
#     here keeps a sweep from filing a SECOND visit for a conversation that
#     already has one. sling_first_reaction_guard refuses it too, and
#     mol-first-reaction consumes it if a direct pour reaches one.
#   - a dispatch path (has_dispatch_path, assets/scripts/dispatch-path.sh) — a
#     gc.routed_to a pool queue serves, or a gc.dispatch_when_ready arm the
#     deferred-dispatch order slings once the bead's own blockers close.
#     Whoever routed or armed the bead already decided its dispatch. The
#     reconcile pass reads no reaction marker and no route before it slings, so
#     a reaction to an armed bead only second-guesses the arm and can leave the
#     bead dispatched twice. An arm reconcile has stopped retrying at its
#     failure cap is dropped too: that bead waits on the visit the cap
#     escalated, not on a first reaction. sling_dispatch_path_guard refuses the
#     same beads, so one routed or armed after this read is still never slung.
scan_precision_filter() {
    local types_json markers_json
    types_json="$(printf '%s' "$PROACTIVE_TYPES" | jq -R 'split(",") | map(select(length > 0))')"
    # Durable work/lifecycle markers that mark a bead as work-in-flight rather
    # than raw input. Kept as one list so the review-lane keys and the
    # implementation-anchor keys share a single source of truth.
    markers_json='["branch","merge_result","work_dir","pr_url","pr_number","check_name","anchor_bead"]'
    jq --argjson types "$types_json" --argjson markers "$markers_json" "$STANDING_KINDS_JQ$DISPATCH_PATH_JQ"'
        map(select(
            ((.metadata["gc.proactive_reaction"] // "") == "")
            and ((.metadata["gc.first_reaction"] // "") == "")
            and ((.metadata["gc.reaction_owned"] // "") == "")
            and (has_dispatch_path | not)
            and ((.description // "") != "")
            and ((.issue_type // "") as $it | ($types | index($it)) != null)
            and (((.metadata["gc.kind"] // "") | (. == "workflow" or . == "scope" or . == "spec")) | not)
            and ((.metadata["gc.step_ref"] // "") == "")
            and (is_standing_kind | not)
            and ((.metadata["task_kind"] // "") != "review")
            and ((.metadata["gc.takeaway"] // "") == "")
            and ((.metadata["gc.takeaway_by"] // "") == "")
            and (.metadata as $m | ($markers | any(.[]; ($m[.] // "") != "")) | not)
            and (([ .dependencies[]? | select((.dependency_type // .type) == "parent-child") ] | length) == 0)
          ))
        | unique_by(.id)
    '
}

# scan_drop_inflight — from a candidate array on stdin, drop each bead a live
# workflow already drives (LIVE_WORKFLOW_JQ). A pour moves the bead's route to
# gc.execution_routed_to, which is not a dispatch path, so the dispatch-path
# clause above cannot see one.
# sling_live_workflow_guard refuses to sling such a bead, and a refusal spends
# none of SLING_CAP, so a page that offers these beads holds fewer beads a sweep
# can sling, and the sweep spends its time on the guard's reads before it
# reaches the beads below them.
#
# Both reads here are taken once per sweep: the workflow roots, and the open
# convoys with the beads each one tracks. Listing closed convoys as well would
# read every convoy the store has ever held. The guard's per-bead read covers
# closed convoys too, so on the same store state the drop can keep a bead the
# guard refuses but never drops one the guard would sling. A read that fails or
# does not parse drops nothing and logs that the sweep went unfiltered. The
# sling guard still refuses those beads.
scan_drop_inflight() {
    local cands roots convoys inflight kept dropped db
    cands="$(cat)"
    if [ -n "$FIXTURE" ]; then
        roots='[]'; convoys='[]'
        if [ -f "$FIXTURE/roots.json" ]; then roots="$(cat "$FIXTURE/roots.json")"; fi
        if [ -f "$FIXTURE/convoys.json" ]; then convoys="$(cat "$FIXTURE/convoys.json")"; fi
    else
        db="$(rig_beads_db)"
        roots="$(workflow_roots_read "$db")" || roots=''
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
        convoys="$(gc bd list ${db:+--db "$db"} --type=convoy --json --limit 0 2>/dev/null | scrub)" || convoys=''
    fi
    inflight="$(jq -cn --slurpfile r <(printf '%s' "$roots") --slurpfile c <(printf '%s' "$convoys") "$LIVE_WORKFLOW_JQ"'
        [ ($c | one_array)[] | .id as $cv | .dependencies[]? | select(tracks_edge)
          | {convoy: $cv, bead: (.depends_on_id // "")} | select(.bead != "") ] as $edges
        | live_drivers($r | one_array; $edges) | map(.bead) | unique' 2>/dev/null)" || {
        log "$PROG: scan: could not read the workflow roots or the open convoys, so beads a live workflow drives are not filtered out of this sweep (the sling guard still refuses them)"
        printf '%s' "$cands"
        return 0
    }
    kept="$(printf '%s' "$cands" | jq -c --argjson skip "$inflight" \
        'map(select(.id as $i | ($skip | index($i)) == null))')"
    dropped=$(( $(printf '%s' "$cands" | jq 'length') - $(printf '%s' "$kept" | jq 'length') ))
    if [ "$dropped" -gt 0 ]; then
        log "$PROG: scan: $dropped candidate(s) already have a live workflow; not offered (the sling guard would refuse them)"
    fi
    printf '%s' "$kept"
}

scan_candidates() {
    local ranked
    if [ -n "$FIXTURE" ]; then
        local raw='[]'
        if [ -f "$FIXTURE/scan.json" ]; then raw="$(cat "$FIXTURE/scan.json")"; fi
        ranked="$(printf '%s' "$raw" | scan_precision_filter | scan_drop_inflight | board_rank)"
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

        # Union the two sources, apply the shared precision filter, drop the
        # beads a workflow is already driving, then rank by board weight.
        ranked="$(jq -s '(.[0] + .[1])' <(printf '%s' "$optin") <(printf '%s' "$movable") \
            | scan_precision_filter | scan_drop_inflight | board_rank)"
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

    # A --sling sweep routes to the proactive pool, so resolve that target ONCE
    # up front and fail the whole sweep closed when it cannot. resolve_pool_target
    # dies on an unset GC_RIG; the per-bead cmd_sling re-resolves inside the loop's
    # condition below, where set -e is disabled and that die cannot abort — so
    # without this gate an unset GC_RIG surfaces the guidance once per candidate
    # and then attempts `gc sling "" <bead>` each time. The subshell keeps die's
    # exit local, so the guidance shows a single time; `|| return 1` stops the sweep.
    if [ -n "$do_sling" ]; then
        ( resolve_pool_target >/dev/null ) || return 1
    fi

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
    local slung=0 skipped=0 reacted=0 routed=0 driven=0
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
        # scan_precision_filter drops the rest. It skips a bead routed or armed
        # since the scan's read, and a bead a live workflow drives, the same way.
        # Counting any skip is the cap-starvation bug: beads that need no
        # reaction would spend the whole cap every sweep while no new reaction
        # is slung.
        if cmd_sling "$id"; then
            case "$SLING_SKIPPED" in
                reacted)       reacted=$(( reacted + 1 )) ;;
                dispatch-path) routed=$(( routed + 1 )) ;;
                live-workflow) driven=$(( driven + 1 )) ;;
                *)             slung=$(( slung + 1 )) ;;
            esac
        fi
    done
    local note="" uncounted=""
    if [ "$reacted" -gt 0 ]; then uncounted="$reacted already reacted"; fi
    if [ "$routed" -gt 0 ]; then uncounted="${uncounted:+$uncounted, }$routed already routed or armed"; fi
    if [ "$driven" -gt 0 ]; then uncounted="${uncounted:+$uncounted, }$driven driven by a live workflow"; fi
    if [ -n "$uncounted" ]; then note=" ($uncounted, not counted)"; fi
    if [ "$skipped" -gt 0 ]; then
        log "scan --sling: slung $slung first reaction(s)$note; $skipped candidate(s) left for the next sweep (cap $SLING_CAP, GC_PROACTIVE_SLING_CAP)"
    else
        log "scan --sling: slung $slung first reaction(s)$note"
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

    # A first reaction happens once (see sling_first_reaction_guard), so skip
    # an already-reacted bead as an idempotent no-op rather than clobber a live
    # dispatch. A reaction never second-guesses a dispatch already decided (see
    # sling_dispatch_path_guard) and never races a live workflow (see
    # sling_live_workflow_guard), so skip those beads the same way. cmd_sling
    # returns 0 for each skip and flags it out-of-band in SLING_SKIPPED: the
    # in-process cmd_scan --sling loop reads that flag to tell a skip from a
    # dispatch and not spend a cap slot on it, and the `sling` CLI verb in
    # main() reads it to exit with the skip's own code, the signal a
    # cross-process caller needs. The return stays 0 because a non-zero one
    # cannot carry the distinction here: caught in the loop's condition it would
    # disable set -e for this function, and returned to main it would read as
    # the generic fail-closed error, not the specific no-op. A dispatch-path or
    # live-workflow read that fails is that error: it returns 1 and nothing is
    # slung.
    SLING_SKIPPED=""
    if ! sling_first_reaction_guard "$bead"; then
        SLING_SKIPPED="reacted"
        return 0
    fi
    local pathed=0
    sling_dispatch_path_guard "$bead" || pathed=$?
    case "$pathed" in
        0) ;;
        1) SLING_SKIPPED="dispatch-path"; return 0 ;;
        *) return 1 ;;
    esac
    local live=0
    sling_live_workflow_guard "$bead" || live=$?
    case "$live" in
        0) ;;
        1) SLING_SKIPPED="live-workflow"; return 0 ;;
        *) return 1 ;;
    esac

    local target
    # resolve_pool_target emits the "set GC_RIG or pass <rig>/<base>" guidance and
    # dies on an unset GC_RIG. Fail closed rather than sling an empty target that
    # routes to nobody — this guards both a direct `sling` (where set -e would
    # abort) and the cmd_scan loop's condition (where set -e is disabled, so the
    # guard, not set -e, is what refuses the empty target).
    target="$(resolve_pool_target)" || return 1

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
        sling)
            cmd_sling "$@"
            # A skipped bead is a no-op, not a dispatch: surface it to a
            # cross-process caller under the exit code of its cause, so it files
            # its own visit instead of waiting for a reaction that never ran.
            case "$SLING_SKIPPED" in
                reacted)       exit "$RC_ALREADY_REACTED" ;;
                dispatch-path) exit "$RC_DISPATCH_PATH" ;;
                live-workflow) exit "$RC_LIVE_WORKFLOW" ;;
            esac
            ;;
        deliverable) cmd_deliverable "$@" ;;
        *) die "unknown verb '$verb' (demand|scan|sling|deliverable; --help)" ;;
    esac
}

main "$@"
