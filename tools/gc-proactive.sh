#!/usr/bin/env bash
# gc-proactive.sh — the proactive first-reaction engine (Bead-Universe Phase 4;
# design specs/tk-1tfzr71.105/design.md). A first reaction is inbox triage: read
# a freshly-filed bead once and dispose it (route it to a pool, hold it on an
# edge, hand a confident no-op to a validating closer, or put it to the
# operator as a human gate). A reaction is a run of
# formulas/mol-first-reaction.toml slung on its subject S. The `sling` verb
# applies the refusals below, then runs
#   gc sling <rig>/gc-toolkit.proactive S --on mol-first-reaction
# whose pour routes the run's one step, react, to the proactive pool. Gas City's
# default work query offers that step to a worker, which reads S and disposes
# it. Gas City refuses a second live run of the formula on S, so a reaction
# happens once at a time. This tool is the trigger layer:
#   scan [--json|--sling] find the ready beads a first reaction may take;
#                        --sling slings a reaction at each until the sweep's
#                        deadline (GC_PROACTIVE_SWEEP_TIMEOUT)
#   sling <bead> [--nudge] [-n]  sling a first reaction on <bead> unless a
#                        refusal holds
#   sling <bead> --check --run <root>  the reaction's own first act: the same
#                        refusals, writing nothing, its own run passed over
#   deliverable [bead]   "would a routed bead be picked up?" — no when the
#                        city's agent roster says this pool cannot claim it
#                        (absent, suspended, or capped at zero), or when the
#                        named bead lives in a store the pool's rig does not
#                        own (cross-store route), exit 0/1
#   assignable <agent> [bead]  "would an assignment be offered?" — the same
#                        question for a named agent addressed by assignee,
#                        exit 0/1
# The pool's only throttle is its max_active_sessions
# (agents/proactive/agent.toml): a slung run waits for a slot at no cost. Code a
# reaction routes reaches main only through a PR, and not by anything this
# router does. The routed subject lands by its own target: the refinery sends a
# bead aimed at main through a PR, and a bead aimed at an integration branch
# reaches main in that branch's PR.
# Tunables: GC_PROACTIVE_POOL / _TYPES / _SWEEP_TIMEOUT / _FIXTURE (test hook:
# canned scan/beads/holds/agents/config/rigs/runs .json instead of gc calls).
set -euo pipefail

PROG="${0##*/}"

POOL_BASE="${GC_PROACTIVE_POOL:-gc-toolkit.proactive}"
FIXTURE="${GC_PROACTIVE_FIXTURE:-}"
# The formula a first reaction is a run of.
REACTION_FORMULA="mol-first-reaction"
# The situation key the reaction's own recommend and ruling exits file their
# human gate under (first-reaction-dispose.sh). A gate under it whose message
# names the asking run is that run's own, which --check passes over.
REACTION_GATE_KEY="first-reaction"
# The situation key of the gate sling files on a subject where Gas City left a
# pour of the formula unfinished.
UNFINISHED_GATE_KEY="first-reaction-unfinished-pour"
# How long one --sling sweep may take, from its start. Gas City ends an exec
# order at its timeout by signalling the order's whole process group, which
# would cut a pour short, so the scan order sets this in its [order.env] beside
# its own timeout. Seconds, or a number with an s, m or h suffix.
SWEEP_TIMEOUT="${GC_PROACTIVE_SWEEP_TIMEOUT:-300s}"
# Exit codes of the `sling` verb for a refusal, distinct from a sling (0), an
# error (1) and a usage error (2), so a caller can branch on the cause:
#   3 a first reaction already runs on the subject, or an open conversation
#     tracks it
#   4 a live run of another formula already works it
#   5 its next move is decided already: a route or an arm, a dispatch hold, an
#     assignee, a status other than open, an open human gate, or an unfinished
#     pour of the formula that a gate now asks a person to close
#   6 its kind takes no first reaction: a standing record, or a feedback
#     pattern, which the feedback distiller dispatches
RC_ALREADY_REACTED=3
RC_LIVE_WORKFLOW=4
RC_DISPATCH_PATH=5
RC_KIND=6
# The issue types a first reaction may target — an ALLOWLIST (fail-safe): a
# new bead type earns reactions only when added here deliberately. Tunable per
# rig via GC_PROACTIVE_TYPES without a code change. The default excludes the
# convoy, epic, step and molecule types (machinery or work-in-flight), decision
# (already a surfaced human choice) and spec (an output, not a raw input). A
# graph.v2 pour does not retype its steps as step, so a workflow root and most
# of its steps are issue_type task, which this list admits.
# scan_precision_filter drops them by gc.kind and by the step keys gc.step_ref,
# gc.step_id and gc.root_bead_id.
PROACTIVE_TYPES="${GC_PROACTIVE_TYPES:-task,bug,feature,spike}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The one definition of the standing kinds, shared with the liveness sweep and
# the doctor checks. Exposes $STANDING_KINDS_JQ, which scan_precision_filter and
# the sling's refusals apply.
# shellcheck source=../assets/scripts/standing-kinds.sh
. "$HERE/../assets/scripts/standing-kinds.sh" \
    || { printf '%s: cannot source assets/scripts/standing-kinds.sh from the pack\n' "$PROG" >&2; exit 1; }
# The one definition of a dispatch path and of a dispatch hold, shared with the
# doctor checks, gc-helm.sh and the liveness classifier. Exposes
# $DISPATCH_PATH_JQ, which scan_precision_filter and the sling's refusals apply.
# shellcheck source=../assets/scripts/dispatch-path.sh
. "$HERE/../assets/scripts/dispatch-path.sh" \
    || { printf '%s: cannot source assets/scripts/dispatch-path.sh from the pack\n' "$PROG" >&2; exit 1; }
# The one rule of which human gates still hold the bead they block, shared with
# every reader of a gate. Exposes $HUMAN_GATE_JQ, whose open_human_gate the
# sling applies to the waits `gctk bead holds` lists. This script's own die and
# scrub, defined below, replace the library's.
# shellcheck source=../assets/scripts/bd-lib.sh
. "$HERE/../assets/scripts/bd-lib.sh" \
    || { printf '%s: cannot source assets/scripts/bd-lib.sh from the pack\n' "$PROG" >&2; exit 1; }
# The one definition of a conversation's shape, shared with gc-helm.sh and the
# board. Exposes $CONVERSATION_JQ, by which the sling tells an open
# conversation about the subject from any other task that tracks it.
# shellcheck source=../assets/scripts/conversation.sh
. "$HERE/../assets/scripts/conversation.sh" \
    || { printf '%s: cannot source assets/scripts/conversation.sh from the pack\n' "$PROG" >&2; exit 1; }
# The one reader of a run's link to the bead it works, which the sling's
# live-run refusal and scan_drop_inflight ask. Under the fixture seam no store
# is read: its verbs answer from the fixture's runs.json, a JSON array of runs
# in run-lib.sh's shape, through the stub its readers' suites use, and a
# fixture with no runs.json holds no runs.
if [ -n "$FIXTURE" ]; then
    : "${GC_RUN_LIB:=$HERE/../assets/scripts/run-lib.stub.sh}"
    : "${RUN_LIB_STUB_RUNS:=$FIXTURE/runs.json}"
    export RUN_LIB_STUB_RUNS
fi
# shellcheck source=../assets/scripts/run-lib.sh
. "${GC_RUN_LIB:-$HERE/../assets/scripts/run-lib.sh}" \
    || { printf '%s: cannot source assets/scripts/run-lib.sh from the pack\n' "$PROG" >&2; exit 1; }
# The gate sling files on an unfinished pour goes through the pack's one filer
# of a human gate.
HUMAN_GATE="${GC_HUMAN_GATE_TOOL:-$HERE/../assets/scripts/human-gate.sh}"
# `gctk bead holds` answers what holds the subject, from the binary the city
# builds.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin

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
# is rig-scoped and a step's route is matched as an exact string, so a bare
# base is qualified from GC_RIG — failing CLOSED when GC_RIG is unset rather
# than emitting an unroutable name.
resolve_pool_target() {
    local base="${1:-}"
    [ -n "$base" ] || base="$POOL_BASE"
    case "$base" in
        */*) printf '%s' "$base" ;;                       # already <rig>/<base>
        *)
            if [ -n "${GC_RIG:-}" ]; then
                printf '%s/%s' "$GC_RIG" "$base"
            else
                die "cannot rig-qualify proactive target '$base': set GC_RIG or pass a <rig>/<base> target (the pool is rig-scoped — agents/proactive/agent.toml serves {{.Rig}}/gc-toolkit.proactive, and a bare route matches nobody)"
            fi
            ;;
    esac
}

# The pack's one read of the rig map, which rig_beads_db, deliverable and
# assignable ask.
RIG_MAP="$HERE/../assets/scripts/rig-map.sh"

# rig_beads_db -> this rig's .beads dir, to pin every store read: an unpinned
# up-walk from a worktree (where .beads is gitignored) overshoots to the HQ
# ledger. Empty when unresolvable; the reads then go unpinned.
rig_beads_db() {
    [ -n "${GC_RIG:-}" ] || return 0
    local path
    path="$("$RIG_MAP" 2>/dev/null \
        | jq -r --arg n "$GC_RIG" '.rigs[]? | select(.name==$n) | .path' 2>/dev/null \
        | head -n1 || true)"
    [ -n "$path" ] && [ -d "$path/.beads" ] && printf '%s' "$path/.beads"
    return 0
}

# The store every read of this tool goes to: STORE_DB, which pin_store sets
# once from rig_beads_db, or the one the cwd resolves when that names none.
# run-lib.sh reads through it too.
STORE_DB=""
STORE_PINNED=""
pin_store() {
    [ -z "$STORE_PINNED" ] || return 0
    STORE_PINNED=1
    [ -n "$FIXTURE" ] || STORE_DB="$(rig_beads_db)"
}
proactive_bd() {
    # shellcheck disable=SC2086  # ${STORE_DB:+--db "$STORE_DB"} expands to 0 or 2 space-free fields
    gc bd "$@" ${STORE_DB:+--db "$STORE_DB"}
}

# store_rows <bd args...> — one read of the store, printed only when it is one
# JSON array, so a read that fails or answers anything else returns 1 and is
# never taken for an empty answer. The `gc bd:` notice a store can print on
# stdout is dropped before the scrub, while its newline still stands.
store_rows() {
    local raw
    raw="$(proactive_bd "$@" --json </dev/null 2>/dev/null | grep -a -vE '^gc bd:' | scrub)" || return 1
    printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    printf '%s' "$raw"
}

# fixture_rows — the fixture store, beads.json, as an array of rows each
# carrying its id. A fixture with no beads.json holds no beads.
fixture_rows() {
    if [ -f "$FIXTURE/beads.json" ]; then
        jq -c '[ to_entries[] | (.value + {id: .key}) ]' "$FIXTURE/beads.json"
    else
        printf '[]'
    fi
}

usage() {
    cat <<EOF
Usage: $PROG scan [--json] [--sling]  Find the ready beads a first reaction may
                                      take. With --sling, sling a first
                                      reaction at each, until the sweep's
                                      deadline (GC_PROACTIVE_SWEEP_TIMEOUT,
                                      default 300s) leaves less time than the
                                      slowest sling so far took; the rest wait
                                      for the next sweep. A rig whose pool
                                      cannot take a reaction (deliverable) is
                                      skipped with exit 0. Read-only without
                                      --sling. Exit 1, nothing slung, when the
                                      ready read or the filter fails.
       $PROG sling <bead> [--nudge] [-n|--dry-run]
                                      Sling a first reaction on <bead>: gc
                                      sling <rig>/$POOL_BASE <bead>
                                      --on $REACTION_FORMULA, unless a refusal
                                      holds. Exit 0 slung,
                                      $RC_ALREADY_REACTED a first reaction already
                                      runs or an open conversation tracks it,
                                      $RC_LIVE_WORKFLOW a live run of another formula
                                      works it, $RC_DISPATCH_PATH routed or armed,
                                      held, assigned, not open, waiting on a
                                      person's answer, or left with an
                                      unfinished pour (a gate now asks a
                                      person), $RC_KIND a standing record or a
                                      feedback pattern (each a refusal,
                                      nothing slung), 1 error, including a
                                      <bead> its store does not hold and a
                                      sling gc sling refuses.
       $PROG sling <bead> --check --run <root>
                                      The same refusals, as the first act of
                                      the reaction whose run is <root>: that
                                      run, and a first-reaction gate whose
                                      message names it, are passed over.
                                      Writes nothing. Exit 0 when <bead> takes
                                      the reaction, else the refusal's code.
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
       $PROG assignable <named-agent> [<bead>]
                                      Would a bead ASSIGNED to that agent be
                                      offered by its own hook? No when the
                                      roster has no agent by that exact name,
                                      it is suspended, it is a pool rather than
                                      a named session, or <bead> is named and
                                      lives in a store a rig-scoped agent's
                                      hook does not read. Exit 0 yes, 1 no.

Budget: the pool cap (agents/proactive/agent.toml max_active_sessions) throttles
how many reactions run at once; a slung run waits for a slot at no cost.
EOF
}

# ---------------------------------------------------------------------------
# deliverable [<pool-target>] [<bead>] — "if I route work there right now, will
# anything ever pick it up?" The default target is the proactive pool; the first
# reaction's actionable exit asks the same question about the pool it is about
# to hand a bead to, and a --sling sweep asks it before it reads the store.
# The queue is not the question: a routed bead waits at zero cost until a slot
# frees. Two things make a route vanish. A pool that cannot claim it at all,
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
# (assets/scripts/operator-intake.sh files a conversation on a no).
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
            riglist="$("$RIG_MAP" 2>/dev/null || true)"
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
        # Bounded: operator-intake asks this question while an operator waits at
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
# assignable <named-agent> [<bead>] — "if I hand work to this agent right now,
# will its own hook ever offer it?" The first reaction's actionable and blocked
# exits ask it before they hand a bead to a named agent (--assign,
# --then-assign). A plain named session's hook serves a bead assigned to it or
# routed to its own name (docs/gascity/routing-model.md, "The read side"), so a
# hand-off vanishes when no agent is registered under that exact name, when the
# agent is a pool rather than a named session (a pool's instances match their
# own identities, never the pool's name), or when its hook reads no store the
# bead lives in. A
# city-scoped agent's hook reads every rig's store; a rig-scoped one reads its
# own rig's store and the city's. A suspended agent leaves the bead sitting
# until it resumes.
#
# NO is a positive finding only, as for deliverable: a roster this cannot read
# answers yes, and a config or rig list this cannot read skips its arm.
# ---------------------------------------------------------------------------
cmd_assignable() {
    local target bead roster entry name dir scope suspended cfg named riglist bead_prefix rig_prefix hq_prefix
    target="${1:-}"
    bead="${2:-}"
    if [ -z "$target" ]; then
        printf 'no: name the agent to assign (assignable <named-agent> [<bead>])\n'
        return 1
    fi

    if [ -n "$FIXTURE" ]; then
        roster=""
        [ -f "$FIXTURE/agents.json" ] && roster="$(cat "$FIXTURE/agents.json")"
    elif command -v timeout >/dev/null 2>&1; then
        roster="$(timeout "${GC_PROACTIVE_ROSTER_TIMEOUT:-15}" gc agent list --json 2>/dev/null || true)"
    else
        roster="$(gc agent list --json 2>/dev/null || true)"
    fi
    # The agent's row as name, dir, scope and suspended, joined on US; empty when
    # the roster names no such agent, __unreadable__ when it carries no agent list.
    entry="__unreadable__"
    if [ -n "$roster" ]; then
        entry="$(printf '%s' "$roster" | jq -r --arg t "$target" '
            if ((.agents // null) | type) != "array" then error("no agent list") else
              .agents | map(select((.qualified_name // "") == $t)) | .[0] // empty
              | [(.name // ""), (.dir // ""), (.scope // ""), ((.suspended // false) | tostring)] | join("\u001f")
            end' 2>/dev/null)" \
            || entry="__unreadable__"
    fi
    case "$entry" in
        __unreadable__)
            printf 'yes: could not read this city agent roster, so %s is assumed assignable — an unreadable roster is not evidence that it is gone\n' "$target"
            return 0 ;;
        "")
            printf 'no: no agent is registered as %s in this city, so a bead assigned to it is offered to nobody (a named agent is addressed by its exact qualified name, e.g. gc-toolkit.mechanik)\n' "$target"
            return 1 ;;
    esac
    IFS=$'\037' read -r name dir scope suspended <<< "$entry"
    if [ "$suspended" = "true" ]; then
        printf 'no: %s is suspended, so a bead assigned to it sits unoffered until it resumes\n' "$target"
        return 1
    fi

    # Named-session arm. The merged config's NamedSessions lists every named
    # singleton by template and rig dir; an agent the list does not carry is a
    # pool. Only a list that reads as an array is evidence.
    if [ -n "$FIXTURE" ]; then
        cfg=""
        [ -f "$FIXTURE/config.json" ] && cfg="$(cat "$FIXTURE/config.json")"
    elif command -v timeout >/dev/null 2>&1; then
        cfg="$(timeout "${GC_PROACTIVE_ROSTER_TIMEOUT:-15}" gc config show --json 2>/dev/null || true)"
    else
        cfg="$(gc config show --json 2>/dev/null || true)"
    fi
    named=""
    if [ -n "$cfg" ]; then
        named="$(printf '%s' "$cfg" | jq -r --arg n "$name" --arg t "$target" --arg d "$dir" '
            (.config.NamedSessions // null) as $ns
            | if ($ns | type) == "array"
              then [$ns[] | select(((.Template // "") == $n or (.Template // "") == $t) and ((.Dir // "") == $d))] | length
              else "unknown" end' 2>/dev/null || true)"
    fi
    if [ "$named" = "0" ]; then
        printf 'no: %s is a pool, not a named session; its instances each match their own identity and never the pool name, so a bead assigned to it is offered to nobody (route a pool with --route)\n' "$target"
        return 1
    fi

    # Store arm. Only a rig-scoped agent can miss a store, and only when the
    # caller names the bead.
    if [ -n "$bead" ] && [ "$scope" != "city" ]; then
        if [ -n "$FIXTURE" ]; then
            riglist=""
            [ -f "$FIXTURE/rigs.json" ] && riglist="$(cat "$FIXTURE/rigs.json")"
        else
            riglist="$("$RIG_MAP" 2>/dev/null || true)"
        fi
        if [ -n "$riglist" ]; then
            bead_prefix="${bead%%-*}"
            rig_prefix="$(printf '%s' "$riglist" \
                | jq -r --arg n "$dir" '.rigs[]? | select((.name // "") == $n) | .prefix // ""' 2>/dev/null \
                | head -n1 || true)"
            hq_prefix="$(printf '%s' "$riglist" \
                | jq -r '.rigs[]? | select((.hq // false) == true) | .prefix // ""' 2>/dev/null \
                | head -n1 || true)"
            if [ -n "$rig_prefix" ] && [ "$bead_prefix" != "$rig_prefix" ] && [ "$bead_prefix" != "$hq_prefix" ]; then
                printf 'no: %s is scoped to rig %s, so its hook reads the %s- store and the city store, but %s lives in the %s- store and is never offered to it\n' \
                    "$target" "$dir" "$rig_prefix" "$bead" "$bead_prefix"
                return 1
            fi
        fi
    fi

    printf 'yes: %s is a registered, unsuspended named session%s\n' "$target" "${bead:+ whose hook reads the store $bead lives in}"
    return 0
}

# ---------------------------------------------------------------------------
# The refusals. A first reaction triages a bead nobody has decided on, so the
# sling refuses a subject whose next move is already someone's. Each read below
# answers one row of the design's refusal table, and the sling and the
# reaction's own first act (--check) apply the same ones, so one definition
# answers both ends. A read that fails is not proof that nothing holds the
# subject, so it fails the verb closed: nothing is slung.
# ---------------------------------------------------------------------------

# subject_row <bead> — the subject's one row, as `gc bd show --json` gives it.
# Only one JSON array holding one row whose id is <bead> exactly is an answer:
# bd answers an id as an exact-or-prefix match, and a read that fails, a bead
# the store does not hold and an empty answer all return 1.
subject_row() {
    local bead="$1"
    if [ -n "$FIXTURE" ]; then
        fixture_rows | jq -ce --arg id "$bead" '[ .[] | select(.id == $id) ] | if length == 1 then .[0] else error("absent") end' 2>/dev/null
        return
    fi
    proactive_bd show "$bead" --json </dev/null 2>/dev/null | grep -a -vE '^gc bd:' | scrub \
        | jq -cs --arg id "$bead" 'if length == 1 and (.[0] | type) == "array" and (.[0] | length) == 1
                  and ((.[0][0].id // "") | tostring) == $id
                then .[0][0] else error("unreadable") end' 2>/dev/null
}

# row_refusal <row> — the refusal the subject's own row carries, as its exit
# code, a tab and its reason, or nothing. Its kind first, since a standing
# record and a feedback pattern take no first reaction in any state; then its
# status, its assignee, its dispatch path and its dispatch hold. A dispatch
# path is a route a pool queue serves or a deferred-dispatch arm
# (has_dispatch_path), and each key is named on its own, so the reason can say
# which. A hold names the labels as the bead spells them.
row_refusal() {
    printf '%s' "$1" | jq -r "$STANDING_KINDS_JQ$DISPATCH_PATH_JQ"'
        (.metadata // {}) as $m
        | ((.status // "open") | tostring | ascii_downcase) as $st
        | ((.assignee // "") | tostring) as $as
        | if is_standing_kind then
            "6\tit is a standing record (task_kind=\($m.task_kind)), open by design, so a first reaction has no disposition to make on it"
          elif (($m.task_kind // "") | tostring) == "feedback-pattern" then
            "6\tit is a feedback pattern, which the feedback distiller dispatches"
          elif $st != "open" then
            "5\tits status is \($st), and a first reaction takes only an open bead"
          elif ($as | test("[^[:space:]]")) then
            "5\tit is assigned to \($as), whose next move it is"
          elif has_dispatch_path then
            "5\tit already has a dispatch path (\([ dispatch_path_keys[] as $k
                | select({metadata: {($k): $m[$k]}} | has_dispatch_path)
                | "\($k)=\($m[$k])" ] | join(", "))), so whoever routed or armed it already decided its dispatch"
          elif has_dispatch_hold then
            "5\tit is held (\([ dispatch_hold_labels[] as $h | dispatch_hold_spellings($h)[] ] | join(", "))): hold:mayor keeps it for the operator'"'"'s placement sitting, and hold:external for an actor outside this store"
          else empty end' 2>/dev/null
}

# subject_conversations <bead> — the open conversations about the bead, by
# conversation.sh's shape, as their ids on one line. An open conversation marks
# a live owner of the bead's first reaction: it puts the bead to the operator
# already, as gc-helm.sh engage --new-subject does for the subject it creates.
# The inverse tracks listing names the candidates, the open tasks that track the
# bead assigned to `human` or to the alias that names their own id. It proves
# only that each one tracks the bead, not that the bead is all it tracks, so the
# candidates' own rows are read with their edges, in one listing, and the
# shared rule decides, as gc-helm.sh's bead_conversations reads them. Returns 1
# when either read does not answer, or answers without a candidate's row.
subject_conversations() {
    local bead="$1" up ids own
    if [ -n "$FIXTURE" ]; then
        fixture_rows | jq -r --arg b "$bead" "$CONVERSATION_JQ"'
            [ .[] | select(((.status // "open") | tostring | ascii_downcase) != "closed")
              | select(conversation and conversation_subjects == [$b]) | .id ] | join(" ")'
        return
    fi
    up="$(store_rows dep list "$bead" --direction=up --type tracks)" || return 1
    ids="$(printf '%s' "$up" | jq -r "$CONVERSATION_JQ"'
        [ .[] | objects
          | select((.issue_type // "task") == "task")
          | select(((.status // "open") | tostring | ascii_downcase) != "closed")
          | select((((.assignee // "") | tostring) == "human") or conversation_alias)
          | (.id // "") | tostring | select(. != "") ] | unique | join(",")' 2>/dev/null)" || return 1
    [ -n "$ids" ] || return 0
    own="$(store_rows list --id "$ids" --all --limit 0)" || return 1
    printf '%s' "$own" | jq -r --arg b "$bead" --arg ids "$ids" "$CONVERSATION_JQ"'
        ($ids | split(",")) as $want
        | [ .[] | objects | select(((.id // "") | tostring) as $i | any($want[]; . == $i)) ] as $own
        | if ([ $own[] | .id ] | unique) != $want then error("a candidate row did not read")
          else [ $own[]
                 | select(((.status // "open") | tostring | ascii_downcase) != "closed")
                 | select(conversation and conversation_subjects == [$b]) | .id ] | join(" ")
          end' 2>/dev/null
}

# unfinished_pours <root>... — of the roots named, the ones whose pour Gas City
# left unfinished, as a JSON object of root to why. A root is an unfinished
# pour when it carries molecule_failed=true, or when it or a bead poured under it
# still carries the fence gc.instantiating, whatever their status: the rule
# gctk's deferred-dispatch start applies to its own pours (pours,
# services/gctk/arm/start.go). Such a root never finishes. The fence holds a
# bead's route back, marking the pour failed does not restore it, and Gas City
# counts the root as live until it closes, so gc sling refuses every later pour
# of the formula on the bead while it stands. A fenced bead is gate-typed, and
# a pour marked failed keeps that type, so both reads include gates. Two reads
# answer any number of roots: the open beads marked failed, and every bead
# still fenced. Returns 1 when either read fails.
unfinished_pours() {
    [ $# -gt 0 ] || { printf '{}'; return 0; }
    local failed fenced
    if [ -n "$FIXTURE" ]; then
        failed="$(fixture_rows | jq -c '[ .[] | select(((.metadata // {}).molecule_failed // "" | tostring) == "true")
                                             | select(((.status // "open") | tostring) != "closed") ]')" || return 1
        fenced="$(fixture_rows | jq -c '[ .[] | select(((.metadata // {})["gc.instantiating"] // "" | tostring) | test("[^[:space:]]")) ]')" || return 1
    else
        failed="$(store_rows list --metadata-field molecule_failed=true --include-gates --include-ephemeral --limit 0)" || return 1
        fenced="$(store_rows list --has-metadata-key gc.instantiating --all --include-gates --include-ephemeral --limit 0)" || return 1
    fi
    jq -cn --argjson failed "$failed" --argjson fenced "$fenced" --args '
        def key($k): ((.metadata // {})[$k] // "") | tostring;
        $ARGS.positional as $roots
        | [ $failed[] | select(key("molecule_failed") == "true") | (.id // "") | tostring ] as $f
        | [ $fenced[] | select(key("gc.instantiating") | test("[^[:space:]]")) ] as $fr
        | reduce $roots[] as $r ({};
            ([ (if ($f | index($r)) != null then "it carries molecule_failed=true" else empty end),
               (if any($fr[]; (.id // "") == $r) then "it is still fenced by gc.instantiating" else empty end),
               ([ $fr[] | select(key("gc.root_bead_id") == $r) | .id ] | unique
                | if length > 0 then "gc.instantiating still fences \(join(", ")) under it" else empty end) ]) as $why
            | if ($why | length) > 0 then . + {($r): ($why | join(", and "))} else . end)' "$@"
}

# subject_runs <bead> — the live runs that work the bead (run-lib.sh), each as
# {root, formula}, with a run of the formula whose pour Gas City left unfinished
# read as no run: it never finishes, and gc sling's own refusal names it when a
# sling meets it. Returns 1 when a read fails.
subject_runs() {
    local bead="$1" runs reaction_roots unfinished
    runs="$(run_lib runs proactive_bd "$bead")" || return 1
    reaction_roots="$(printf '%s' "$runs" | jq -r --arg f "$REACTION_FORMULA" '[ .[] | select(.live and .formula == $f) | .root ] | unique | .[]' 2>/dev/null)" || return 1
    # shellcheck disable=SC2086  # one root id per word
    unfinished="$(unfinished_pours $reaction_roots)" || return 1
    printf '%s' "$runs" | jq -c --argjson u "$unfinished" '[ .[] | select(.live) | select(($u[.root] // null) == null) | {root, formula} ] | unique_by(.root)' 2>/dev/null
}

# subject_holds <bead> — what holds the bead, as `gctk bead holds` prints its
# one line. A line that carries an error, or none, returns 1. Under the fixture
# the line is holds.json's entry for the bead, and a bead it does not list is
# clear.
subject_holds() {
    local bead="$1" line
    if [ -n "$FIXTURE" ]; then
        if [ -f "$FIXTURE/holds.json" ]; then
            jq -ce --arg id "$bead" '.[$id] // {id: $id, status: "clear", waits: []}' "$FIXTURE/holds.json" 2>/dev/null
        else
            jq -nc --arg id "$bead" '{id: $id, status: "clear", waits: []}'
        fi
        return
    fi
    [ -x "$GCTK" ] || return 1
    # shellcheck disable=SC2086  # ${STORE_DB:+--db "$STORE_DB"} expands to 0 or 2 space-free fields
    line="$("$GCTK" bead holds ${STORE_DB:+--db "$STORE_DB"} "$bead" </dev/null 2>/dev/null)" || return 1
    printf '%s' "$line" | jq -ce --arg id "$bead" 'select(type == "object" and .id == $id and (has("error") | not)) | select((.waits | type) == "array")' 2>/dev/null
}

# gate_rows <gate>... — the gates' own rows, as `gc bd show` gives them, which
# carry the key a gate was filed under (await_id) and its message
# (description). `show` reads a gate that `list` hides without
# --include-gates. Returns 1 unless every gate named reads back.
gate_rows() {
    local rows
    if [ -n "$FIXTURE" ]; then
        rows="$(fixture_rows)"
    else
        rows="$(proactive_bd show "$@" --json </dev/null 2>/dev/null | grep -a -vE '^gc bd:' | scrub)" || return 1
    fi
    printf '%s' "$rows" | jq -ce --args '
        $ARGS.positional as $want
        | if type != "array" then error("no answer") else
          [ .[] | objects | select(((.id // "") | tostring) as $i | any($want[]; . == $i)) ] as $got
          | if ([ $got[] | .id ] | unique) != ($want | unique) then error("a gate did not read") else $got end end' "$@" 2>/dev/null
}

# ---------------------------------------------------------------------------
# sling <bead> [--nudge] [-n|--dry-run]
# sling <bead> --check --run <root>
#
# Each refusal, the read it comes from, and its code:
#   - a standing record (standing-kinds.sh) or a feedback pattern
#     (task_kind=feedback-pattern), from the row: 6
#   - a status other than open, an assignee, a route or an arm, hold:mayor or
#     hold:external (dispatch-path.sh), from the row: 5
#   - an open conversation that tracks the bead (conversation.sh's shape),
#     from its tracks dependents: 3
#   - a live run of mol-first-reaction (run-lib.sh), or gc sling's own refusal
#     when two slings meet: 3
#   - a live run of another formula (run-lib.sh): 4
#   - an open human gate, from `gctk bead holds`: 5
#   - an unfinished pour of mol-first-reaction that gc sling's refusal names,
#     read from the root's marks after the sling: 5, once the gate that asks a
#     person to close it is filed
# Gas City's sling itself refuses a bead no store holds, a pool that does not
# read the bead's store and a target the city does not configure, each an
# error here.
#
# --check is the reaction's first act, as `sling <S> --check --run <root>`: it
# writes nothing, and passes over its own run and a first-reaction gate whose
# message names that run, so a reaction re-offered after it filed its gate
# resumes rather than stands down.
#
# The verb sets SLING_RC to 0 when it slung (or would, under --dry-run or
# --check) and to a refusal's code or 1 otherwise, and returns 0 either way:
# the --sling sweep reads SLING_RC in-process, and main exits with it. A return
# that carried the code would disable set -e inside a loop's condition, or
# read as the generic error.
# ---------------------------------------------------------------------------
SLING_RC=0
# The asking reaction's run under --check, empty for a sling.
CHECK_RUN=""

cmd_sling() {
    local bead="" nudge="" dry="" check="" run=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --nudge)      nudge=1; shift ;;
            -n|--dry-run) dry=1; shift ;;
            --check)      check=1; shift ;;
            --run)        shift; [ $# -gt 0 ] || { log "$PROG: sling: --run needs the root of the asking reaction's run"; exit 2; }; run="$1"; shift ;;
            --run=*)      run="${1#--run=}"; shift ;;
            -h|--help)    usage; exit 0 ;;
            -*) log "$PROG: sling: unknown flag '$1'"; exit 2 ;;
            *) [ -z "$bead" ] || { log "$PROG: sling takes one bead-id"; exit 2; }; bead="$1"; shift ;;
        esac
    done
    [ -n "$bead" ] || { log "$PROG: sling needs <bead-id>"; usage >&2; exit 2; }
    if [ -n "$check" ] && [ -z "$run" ]; then
        log "$PROG: sling: --check needs --run <root>, the run of the reaction that asks, so its own run is not taken for a second reaction"; exit 2
    fi
    if [ -n "$run" ] && [ -z "$check" ]; then
        log "$PROG: sling: --run names the asking reaction's run, which only --check reads"; exit 2
    fi
    if [ -n "$check" ] && [ -n "$nudge$dry" ]; then
        log "$PROG: sling: --check writes nothing, so it takes neither --nudge nor --dry-run"; exit 2
    fi
    sling_one "$bead" "$nudge" "$dry" "$run"
}

# refuse <code> <bead> <reason> — record a refusal and say why. A --check
# names the refusal alone, which the reaction that asked declines with.
refuse() {
    SLING_RC="$1"
    if [ -n "$CHECK_RUN" ]; then
        log "$PROG: sling: $2: $3."
    else
        log "$PROG: sling: $2: $3. No first reaction is slung."
    fi
}

# unanswered <text> — a read the verb could not take, which decides nothing:
# no sling, and under --check no refusal either, so the reaction asks again
# rather than declines.
unanswered() {
    SLING_RC=1
    if [ -n "$CHECK_RUN" ]; then
        log "$PROG: sling: $1 The check decides nothing; ask again once the store answers."
    else
        log "$PROG: sling: $1 No first reaction is slung."
    fi
}

# sling_one <bead> <nudge> <dry> <run> — the refusals, then the sling. <run>
# is non-empty for --check.
sling_one() {
    local bead="$1" nudge="$2" dry="$3" run="$4"
    local target="" row why convs runs live other holds gates own_gates
    SLING_RC=1
    CHECK_RUN="$run"
    if [ -z "$run" ]; then
        # resolve_pool_target dies on an unset GC_RIG with the "set GC_RIG or
        # pass <rig>/<base>" guidance; the subshell keeps that exit local, so a
        # sweep's loop goes on to its own summary.
        target="$(resolve_pool_target)" || return 0
    fi
    pin_store

    row="$(subject_row "$bead")" || {
        unanswered "cannot read $bead's own row: the store does not hold it, matches it only as a prefix of another id, or did not answer."
        return 0
    }
    why="$(row_refusal "$row")" || { unanswered "cannot judge $bead's row."; return 0; }
    if [ -n "$why" ]; then
        local tab=$'\t'
        refuse "${why%%"$tab"*}" "$bead" "${why#*"$tab"}"
        return 0
    fi

    convs="$(subject_conversations "$bead")" || {
        unanswered "cannot read whether an open conversation tracks $bead: its tracks dependents did not read."
        return 0
    }
    if [ -n "$convs" ]; then
        refuse "$RC_ALREADY_REACTED" "$bead" "an open conversation tracks it ($convs), which puts it to the operator already"
        return 0
    fi

    runs="$(subject_runs "$bead")" || {
        unanswered "cannot read the runs that work $bead, and a reaction that raced one could dispose of work in flight."
        return 0
    }
    live="$(printf '%s' "$runs" | jq -r --arg f "$REACTION_FORMULA" --arg own "$run" '[ .[] | select(.formula == $f and .root != $own) | .root ] | join(", ")')"
    if [ -n "$live" ]; then
        refuse "$RC_ALREADY_REACTED" "$bead" "a first reaction already runs on it ($live)"
        return 0
    fi
    other="$(printf '%s' "$runs" | jq -r --arg f "$REACTION_FORMULA" '[ .[] | select(.formula != $f) | "\(.root) (\(if .formula == "" then "unknown formula" else .formula end))" ] | join(", ")')"
    if [ -n "$other" ]; then
        refuse "$RC_LIVE_WORKFLOW" "$bead" "a live workflow already works it ($other), and a reaction would race work in flight"
        return 0
    fi

    holds="$(subject_holds "$bead")" || {
        unanswered "cannot read what holds $bead: gctk bead holds did not answer, and a person's answer may decide it."
        return 0
    }
    gates="$(printf '%s' "$holds" | jq -c "$HUMAN_GATE_JQ"'[ .waits[]? | objects | select(open_human_gate("")) ]')"
    if [ -n "$run" ] && [ "$gates" != "[]" ]; then
        # The asking reaction's own gate is one filed under the reaction's key
        # whose message names its run, as the recommend and ruling exits file it.
        local gate_ids
        gate_ids="$(printf '%s' "$gates" | jq -r '[ .[].id ] | unique | .[]')"
        # shellcheck disable=SC2086  # one gate id per word
        own_gates="$(gate_rows $gate_ids | jq -c --arg k "$REACTION_GATE_KEY" --arg run "$run" "$HUMAN_GATE_JQ"'
            [ .[] | select(open_human_gate($k))
              | select([ ((.description // "") | tostring) | scan("[A-Za-z0-9._-]+") | sub("[.]+$"; "") ] | index($run) != null)
              | .id ]')" || {
            unanswered "cannot read the human gates that hold $bead, to pass over its own run's."
            return 0
        }
        gates="$(printf '%s' "$gates" | jq -c --argjson own "$own_gates" '[ .[] | select(.id as $i | ($own | index($i)) == null) ]')"
    fi
    if [ "$gates" != "[]" ]; then
        refuse "$RC_DISPATCH_PATH" "$bead" "it waits on a person's answer ($(printf '%s' "$gates" | jq -r '[ .[] | "open human gate \(.id)\(if (.ancestor // "") != "" then " on \(.ancestor)" else "" end)" ] | join(", ")')), which decides what happens to it"
        return 0
    fi

    if [ -n "$run" ]; then
        log "$PROG: sling: $bead takes this first reaction (run $run): no refusal holds."
        SLING_RC=0
        return 0
    fi

    local -a cmd=(gc sling --rig "${target%%/*}" "$target" "$bead" --on "$REACTION_FORMULA")
    [ -z "$nudge" ] || cmd+=(--nudge)
    if [ -n "$dry" ]; then
        printf '%s\n' "${cmd[*]}"
        SLING_RC=0
        return 0
    fi
    if [ -n "$FIXTURE" ]; then
        # The fixture stands in for every gc call in this tool: a --sling sweep
        # under test exercises its loop without slinging into a live city.
        log "$PROG: (fixture) would sling a first reaction on $bead -> $target"
        printf '%s\n' "${cmd[*]}"
        SLING_RC=0
        return 0
    fi

    local out rc=0
    out="$("${cmd[@]}" </dev/null 2>&1)" || rc=$?
    [ -z "$out" ] || log "$out"
    case "$rc" in
        0)
            log "$PROG: slung a first reaction on $bead ($REACTION_FORMULA -> $target)"
            SLING_RC=0 ;;
        3) sling_conflict "$bead" "$out" ;;
        *) unanswered "gc sling refused or failed on $bead (exit $rc)." ;;
    esac
    return 0
}

# sling_conflict <bead> <output> — gc sling exited 3: a live workflow of the
# formula works the bead already, and its output names each root
# (printSourceWorkflowConflictLines in cmd/gc/cmd_sling.go). A root whose pour
# finished is a reaction that runs, the refusal passed through. When every
# root it names is an unfinished pour, nothing will finish them and every later
# sling meets them, so a human gate on the bead names each root and the command
# that closes it with its steps, the remedy gctk's deferred-dispatch start names
# for its own (askUnfinished, services/gctk/arm/start.go). Clearing the gate
# returns the bead to the scan.
sling_conflict() {
    local bead="$1" out="$2" roots unfinished msg gate
    roots="$(printf '%s\n' "$out" | awk -v pre="gc sling: source bead $bead already has live workflow(s): " '
        { sub(/^[ \t]+/, ""); if (index($0, pre) == 1) print substr($0, length(pre) + 1) }' \
        | tr ',' '\n' | tr -d '[:space:]' | sed '/^$/d' | sort -u | tr '\n' ' ')"
    roots="${roots% }"
    if [ -z "$roots" ]; then
        refuse "$RC_ALREADY_REACTED" "$bead" "gc sling refused a second live $REACTION_FORMULA run on it"
        return 0
    fi
    # shellcheck disable=SC2086  # one root id per word
    unfinished="$(unfinished_pours $roots)" || {
        unanswered "gc sling named live run(s) $roots on $bead, and whether their pours finished could not be read."
        return 0
    }
    # shellcheck disable=SC2086  # one root id per word
    if ! printf '%s' "$unfinished" | jq -e --args '. as $u | all($ARGS.positional[]; $u[.] != null)' $roots >/dev/null 2>&1; then
        refuse "$RC_ALREADY_REACTED" "$bead" "gc sling found a first reaction already running on it ($roots)"
        return 0
    fi
    msg="$(printf '%s' "$unfinished" | jq -r --arg b "$bead" --arg f "$REACTION_FORMULA" '
        [ to_entries[] | "\(.key) (\(.value))" ] as $parts
        | [ keys[] | "gc convoy delete \(.) --force" ] as $closes
        | "A first reaction cannot start on \($b): Gas City left a pour of \($f) unfinished.\n\n"
          + "Gas City left its pour of \($f) unfinished at \($parts | join("; ")). gc sling refuses another pour of \($f) on \($b) while such a root is open, and nothing finishes it. "
          + "Close each root and its steps (\($closes | join("; "))), then clear this gate, and the next sweep reacts to \($b)."')"
    gate="$("$HUMAN_GATE" --subject "$bead" --key "$UNFINISHED_GATE_KEY" --message "$msg")" || {
        unanswered "Gas City left an unfinished $REACTION_FORMULA pour on $bead ($roots), and the gate that asks a person to close it could not be filed."
        return 0
    }
    refuse "$RC_DISPATCH_PATH" "$bead" "Gas City left a pour of $REACTION_FORMULA unfinished on it ($roots), so gc sling refuses another; human gate ${gate:-?} asks a person to close it"
}

# ---------------------------------------------------------------------------
# scan — the PROCESS-SCAN trigger. Find raw INPUT beads a first reaction may
# take: open, ready, unassigned, an allowlisted issue_type (GC_PROACTIVE_TYPES),
# top-level, and not already routed, armed or held / machinery (so we never
# react to work-in-flight or to a reaction's own run). Read-only unless
# --sling. The refusals are read again at sling time for each bead, since its
# state can change while the sweep runs.
# ---------------------------------------------------------------------------

# scan_precision_filter — from a candidate array on stdin, keep only raw
# top-level INPUT beads a fresh first reaction may target, in the order read.
# Each clause drops a distinct non-input population:
#   - ALLOWLIST issue_type ($types, GC_PROACTIVE_TYPES) — drops the convoy/
#     epic/step/molecule/spec/decision types by omission.
#   - graph-structural beads (topology roots gc.kind in workflow/scope/spec,
#     and formula step beads gc.step_ref/gc.step_id/gc.root_bead_id) — a
#     workflow root is issue_type task, and so are most graph.v2 steps, so the
#     allowlist misses both. A graph.v2 step has no parent-child edge either: a
#     tracks edge, or gc.root_bead_id alone, ties it to its root, so the
#     top-level clause misses it too. Every step a pour mints carries
#     gc.step_ref, control steps such as workflow-finalize included. A step
#     advances only through its own molecule, so a first reaction has no
#     disposition to make on it, and reacting to a root or a step writes over a
#     live molecule. A first reaction's own root and step are among them.
#   - a standing kind (is_standing_kind, assets/scripts/standing-kinds.sh) — a
#     standing record is open and unrouted by design and never closes, so a
#     reaction has no disposition to make on it.
#   - task_kind=feedback-pattern — the feedback distiller decides every
#     pattern bd ready lists.
#   - task_kind=review — a dispatched signoff lane, work-in-flight.
#   - durable work/lifecycle markers ($markers) — a review lane carries
#     check_name/anchor_bead; an implementation anchor carries branch/
#     merge_result/work_dir/pr_url/pr_number. An anchor is an issue_type
#     task/bug bead with no task_kind, so the allowlist and the task_kind
#     clauses both miss it, and its markers are the only signal that the work
#     is already in motion. Reacting to either reacts to work-in-flight,
#     which the proactive scope forbids.
#   - gc.takeaway / gc.takeaway_by — the headline every exit of a first
#     reaction writes, and a sitting's ruling: the bead has been triaged. A
#     request can still ask for another reaction on it.
#   - top-level only — a parent-child CHILD carries the edge in its own
#     .dependencies, so no member of an epic is scanned. A convoy's tracks edge
#     lives on the convoy, so this catches parented beads, not every convoy
#     member.
#   - a dispatch path (has_dispatch_path, assets/scripts/dispatch-path.sh) — a
#     gc.routed_to a pool queue serves, or a gc.dispatch_when_ready arm the
#     deferred-dispatch order slings once the bead's own blockers close.
#     Whoever routed or armed the bead already decided its dispatch. An arm
#     the start stopped retrying at its failure cap is dropped too: that bead
#     waits on the human gate the cap filed, not on a first reaction. The
#     sling refuses the same beads, so a bead routed or armed after this read
#     still gets no reaction.
#   - a dispatch hold (has_dispatch_hold, assets/scripts/dispatch-path.sh) —
#     intake held it as new work for the operator's placement sitting
#     (docs/steering.md) with hold:mayor, so its next move is the sitting's, or
#     hold:external names an actor outside this store. The witness and the
#     feedback distiller file their beads held and unrouted, with no takeaway,
#     so no other clause drops them. The sling refuses a held bead too, so a
#     bead held after this read still gets no reaction. Once a write lifts the
#     hold, the other clauses judge the bead.
# Plus a state predicate: has a description.
scan_precision_filter() {
    local types_json markers_json
    types_json="$(printf '%s' "$PROACTIVE_TYPES" | jq -R 'split(",") | map(select(length > 0))')"
    # Durable work/lifecycle markers that mark a bead as work-in-flight rather
    # than raw input. Kept as one list so the review-lane keys and the
    # implementation-anchor keys share a single source of truth.
    markers_json='["branch","merge_result","work_dir","pr_url","pr_number","check_name","anchor_bead"]'
    jq --argjson types "$types_json" --argjson markers "$markers_json" "$STANDING_KINDS_JQ$DISPATCH_PATH_JQ"'
        map(select(
            (has_dispatch_path | not)
            and (has_dispatch_hold | not)
            and ((.description // "") != "")
            and ((.issue_type // "") as $it | ($types | index($it)) != null)
            and (((.metadata["gc.kind"] // "") | (. == "workflow" or . == "scope" or . == "spec")) | not)
            and ((.metadata["gc.step_ref"] // "") == "")
            and ((.metadata["gc.step_id"] // "") == "")
            and ((.metadata["gc.root_bead_id"] // "") == "")
            and (is_standing_kind | not)
            and ((.metadata["task_kind"] // "") != "feedback-pattern")
            and ((.metadata["task_kind"] // "") != "review")
            and ((.metadata["gc.takeaway"] // "") == "")
            and ((.metadata["gc.takeaway_by"] // "") == "")
            and (.metadata as $m | ($markers | any(.[]; ($m[.] // "") != "")) | not)
            and (([ .dependencies[]? | select((.dependency_type // .type) == "parent-child") ] | length) == 0)
          ))
    '
}

# scan_drop_inflight — from a candidate array on stdin, drop each bead a live
# run already works (run-lib.sh's map). A pour moves the bead's route to
# gc.execution_routed_to, which is not a dispatch path, so the dispatch-path
# clause above cannot see one. The sling refuses such a bead, so a page that
# offers it spends the sweep's time on the refusal's reads. A run of
# mol-first-reaction whose pour Gas City left unfinished is no run here, as in
# the sling's own read, so the sweep reaches its bead and the sling asks a
# person about it.
#
# The map is read once per sweep, and the sling reads the runs of each bead it
# is about to react to, so on one store state the two agree. A map that fails
# or does not parse drops nothing and logs that the sweep went unfiltered; the
# sling still refuses those beads. Unfinished pours that cannot be read leave
# every live reaction's bead out of the sweep, and the sweep says so.
scan_drop_inflight() {
    local cands runs roots unfinished inflight kept dropped
    cands="$(cat)"
    # The candidates come from the precision filter, which prints nothing when
    # it fails. Nothing is not an empty page, so refuse it rather than count it;
    # scan_candidates reports the failure.
    printf '%s' "$cands" | jq -se 'length == 1 and (.[0] | type) == "array"' >/dev/null 2>&1 || return 1
    if ! runs="$(run_lib map proactive_bd)" \
        || ! roots="$(printf '%s' "$runs" | jq -r --arg f "$REACTION_FORMULA" '[ .[] | select(.formula == $f) | .root ] | unique | .[]' 2>/dev/null)"; then
        log "$PROG: scan: could not read the live runs, so beads a live workflow drives are not filtered out of this sweep (the sling still refuses them)"
        printf '%s' "$cands"
        return 0
    fi
    # shellcheck disable=SC2086  # one root id per word
    if ! unfinished="$(unfinished_pours $roots)"; then
        log "$PROG: scan: could not read whether the live first reactions' pours finished, so their beads stay out of this sweep"
        unfinished='{}'
    fi
    inflight="$(printf '%s' "$runs" | jq -c --argjson u "$unfinished" '[ .[] | select(($u[.root] // null) == null) | .bead | select(. != "") ] | unique')"
    kept="$(printf '%s' "$cands" | jq -c --argjson skip "$inflight" \
        'map(select(.id as $i | ($skip | index($i)) == null))')"
    dropped=$(( $(printf '%s' "$cands" | jq 'length') - $(printf '%s' "$kept" | jq 'length') ))
    if [ "$dropped" -gt 0 ]; then
        log "$PROG: scan: $dropped candidate(s) already have a live workflow; not offered (the sling would refuse them)"
    fi
    printf '%s' "$kept"
}

# ready_read_failed <rc> <output> — log a gc bd ready read that exited
# non-zero, with the error text from the {"error": ...} object gc bd leaves on
# stdout when there is one. A failed read is not an empty ready set. Taken as
# one, it drops its beads from the sweep unseen, and a --sling sweep exits 0
# with nothing slung, the result a sweep with no work gives.
ready_read_failed() {
    local err
    err="$(printf '%s' "$2" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null || true)"
    log "$PROG: scan: the ready read failed (gc bd ready exit $1${err:+: $err}). A failed read is not an empty ready set, so the scan fails rather than report no candidates; retry once the store answers."
}

# scan_candidates — the scan's candidates, one JSON array, highest priority
# first. cmd_scan runs it in a command substitution, where set -e does not
# apply, so a step that fails returns non-zero here explicitly. A step that
# failed quietly would leave an empty array, which reads as nothing to react
# to. The whole ready set is read (--limit 0) and filtered with no page, so no
# bead the filter drops can bury one it keeps.
scan_candidates() {
    local ready rc=0 cands
    if [ -n "$FIXTURE" ]; then
        ready='[]'
        if [ -f "$FIXTURE/scan.json" ]; then ready="$(cat "$FIXTURE/scan.json")"; fi
    else
        # shellcheck disable=SC2086  # ${STORE_DB:+--db "$STORE_DB"} expands to 0 or 2 fields
        ready="$(gc bd ready ${STORE_DB:+--db "$STORE_DB"} --unassigned --exclude-type=epic --json \
                    --sort priority --limit 0 2>/dev/null)" || rc=$?
        [ "$rc" -eq 0 ] || { ready_read_failed "$rc" "$ready"; return 1; }
        # A read that exited 0 must still be one JSON array, [] when nothing is
        # ready; anything else, an empty read included, fails the scan.
        printf '%s' "$ready" | jq -e 'type == "array"' >/dev/null 2>&1 || {
            log "$PROG: scan: the ready read failed: gc bd ready printed something other than one JSON array"
            return 1
        }
    fi
    cands="$(printf '%s' "$ready" | scan_precision_filter | scan_drop_inflight)" || {
        log "$PROG: scan: the candidates could not be filtered, so the scan fails rather than report none"
        return 1
    }
    printf '%s' "$cands"
}

# sweep_seconds <duration> — a duration as whole seconds: a number, alone or
# with an s, m or h suffix, as an order's timeout is written. Returns 1 for
# anything else.
sweep_seconds() {
    local d="$1" n
    case "$d" in
        ''|*[!0-9smh]*) return 1 ;;
    esac
    n="${d%[smh]}"
    case "$n" in ''|*[!0-9]*) return 1 ;; esac
    case "$d" in
        *h) printf '%s' "$(( n * 3600 ))" ;;
        *m) printf '%s' "$(( n * 60 ))" ;;
        *)  printf '%s' "$(( n ))" ;;
    esac
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

    local deadline=0 verdict
    if [ -n "$do_sling" ]; then
        deadline="$(sweep_seconds "$SWEEP_TIMEOUT")" \
            || die "GC_PROACTIVE_SWEEP_TIMEOUT must be a duration in seconds, minutes or hours, such as 300s or 5m (got '$SWEEP_TIMEOUT')"
        # A sweep slings into this rig's proactive pool, so resolve that target
        # once and fail the whole sweep closed when it cannot. The subshell
        # keeps die's exit local, so the guidance shows a single time.
        ( resolve_pool_target >/dev/null ) || return 1
        # A rig whose pool cannot take a reaction (absent, suspended or capped
        # at zero) skips cleanly: the order ran and had nothing to do here.
        if ! verdict="$(cmd_deliverable)"; then
            log "scan --sling: no sweep this rig — $verdict"
            return 0
        fi
    fi

    pin_store
    local cands
    cands="$(scan_candidates)" || return 1

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

    # --sling: sling a reaction at each candidate in the order read, highest
    # priority first. The sweep has no cap: a slung run waits for a pool slot
    # at no cost. It has a deadline, since the order's timeout kills a pour in
    # progress, so it starts no sling once less time is left than the slowest
    # sling so far took, and the next sweep reads the rest. Time is read in
    # whole seconds from the script's start ($SECONDS), so each figure is taken
    # as its upper bound: a sling that read d seconds counts as d+1, and the
    # time used as the reading plus one. Only a sling counts as a dispatch; each
    # refusal is counted under its cause.
    local slung=0 reacting=0 driven=0 decided=0 kinded=0 failed=0 left=0 slowest=0
    local ids id t0 took
    ids="$(printf '%s' "$cands" | jq -r '.[].id')"
    for id in $ids; do
        if [ $(( deadline - SECONDS - 1 )) -lt "$slowest" ]; then
            left=$(( left + 1 ))
            continue
        fi
        t0=$SECONDS
        sling_one "$id" "" "" ""
        took=$(( SECONDS - t0 + 1 ))
        [ "$took" -le "$slowest" ] || slowest=$took
        case "$SLING_RC" in
            0)                     slung=$(( slung + 1 )) ;;
            "$RC_ALREADY_REACTED") reacting=$(( reacting + 1 )) ;;
            "$RC_LIVE_WORKFLOW")   driven=$(( driven + 1 )) ;;
            "$RC_DISPATCH_PATH")   decided=$(( decided + 1 )) ;;
            "$RC_KIND")            kinded=$(( kinded + 1 )) ;;
            *)                     failed=$(( failed + 1 )) ;;
        esac
    done
    local note=""
    [ "$reacting" -eq 0 ] || note="${note:+$note, }$reacting already reacting or in a conversation"
    [ "$driven" -eq 0 ] || note="${note:+$note, }$driven driven by a live workflow"
    [ "$decided" -eq 0 ] || note="${note:+$note, }$decided already routed, armed, held, assigned or waiting on a person"
    [ "$kinded" -eq 0 ] || note="${note:+$note, }$kinded a standing record or a feedback pattern"
    [ "$failed" -eq 0 ] || note="${note:+$note, }$failed not slung for an error"
    [ -z "$note" ] || note=" ($note)"
    if [ "$left" -gt 0 ]; then
        log "scan --sling: slung $slung first reaction(s)$note; $left candidate(s) left for the next sweep, since less of the sweep's ${deadline}s (GC_PROACTIVE_SWEEP_TIMEOUT) was left than its slowest sling took"
    else
        log "scan --sling: slung $slung first reaction(s)$note"
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
        scan)   cmd_scan "$@" ;;
        sling)
            cmd_sling "$@"
            exit "$SLING_RC"
            ;;
        deliverable) cmd_deliverable "$@" ;;
        assignable)  cmd_assignable "$@" ;;
        *) die "unknown verb '$verb' (scan|sling|deliverable|assignable; --help)" ;;
    esac
}

main "$@"
