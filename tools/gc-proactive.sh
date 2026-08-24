#!/usr/bin/env bash
# gc-proactive.sh — the proactive-via-slung-mol engine (Bead-Universe Phase 4;
# v1 design specs/bead-universe/design-doc.md, still governing this tool).
# "Proactive" is NOT a resident loop: it is mol-first-reaction slung at a
# bead (read body → write a first-reaction CARD → file a visit) so the human
# arrives at advanced work. This tool is the budget-and-trigger layer:
#   demand [<pool>]      pool work_query — routed beads, or [] when auto-spawn
#                        is disabled (the default) or the city is at the cap
#   scan [--json|--sling] find movable-forward / opt-in beads; --sling reacts
#   sling <bead> [--nudge] [-n]  sling a first reaction (mr path, hard-refuses
#                        --merge direct — the security invariant)
#   cap · deliverable    clamp state; "would a sling be picked up?" (exit 0/1)
# Two clamps: the pool's own max_active_sessions (agents/proactive/agent.toml)
# and the city-wide GC_PROACTIVE_CITY_CAP shed. Tunables resolve env-first,
# then the pool's city config (helm-svc carries no env — tk-hscs0):
# GC_PROACTIVE_ENABLED / _POOL / _CITY_CAP / _MERGE / _SCAN_LIMIT / _FIXTURE
# (test hook: canned sessions/ready/scan/config .json instead of gc calls).
set -euo pipefail

PROG="${0##*/}"

POOL_BASE="${GC_PROACTIVE_POOL:-gc-toolkit.proactive}"
CITY_CAP_DEFAULT=20
# Provisional. `resolve_tunables` (run from main) fills whichever of these two
# the process env left unanswered from the proactive pool's resolved city
# config. Read them only after that call — never at load time.
CITY_CAP="${GC_PROACTIVE_CITY_CAP:-$CITY_CAP_DEFAULT}"
PROACTIVE_ENABLED="${GC_PROACTIVE_ENABLED:-}"
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

# ---------------------------------------------------------------------------
# Tunable resolution: process env first, then the pool's resolved city config
# (the same [agent.env] the reconciler injects), then the default. Needed
# because helm-svc — the caller that must ask deliverable — structurally
# carries no GC_PROACTIVE_* env (tk-hscs0). One config read at most, only for
# a tunable the env left unanswered; fails SOFT in every direction.
# ---------------------------------------------------------------------------

# pool_config_env -> the target pool's resolved [agent.env] as JSON, or {}.
# Config keys agents by bare Name + rig Dir; strip the target's wrappers.
pool_config_env() {
    local target rig base raw out
    target=""
    # resolve_pool_target dies when unqualifiable; absorb it here.
    target="$(resolve_pool_target 2>/dev/null)" || target=""
    [ -n "$target" ] || { printf '{}'; return 0; }
    rig="${target%%/*}"
    base="${target##*/}"        # <binding>.<agent-base>, or already bare
    base="${base##*.}"          # the agent's own name, which is what config keys

    raw=""
    if [ -n "$FIXTURE" ]; then
        [ -f "$FIXTURE/config.json" ] || { printf '{}'; return 0; }
        raw="$(cat "$FIXTURE/config.json")"
    else
        raw="$(gc config show --json 2>/dev/null)" || raw=""
    fi
    [ -n "$raw" ] || { printf '{}'; return 0; }

    out=""
    out="$(printf '%s' "$raw" | jq -c --arg rig "$rig" --arg base "$base" \
        '[ (.config.Agents // [])[]
           | select((.Dir // "") == $rig and (.Name // "") == $base)
           | (.Env // {}) ] | (.[0] // {})' 2>/dev/null)" || out=""
    [ -n "$out" ] || out='{}'
    printf '%s' "$out"
}

# resolve_tunables — fill whichever of the two the process env left unset.
resolve_tunables() {
    if [ -n "$PROACTIVE_ENABLED" ] && [ -n "${GC_PROACTIVE_CITY_CAP:-}" ]; then
        return 0
    fi
    local env_json v
    env_json=""
    env_json="$(pool_config_env)" || env_json='{}'
    [ -n "$env_json" ] || env_json='{}'

    if [ -z "$PROACTIVE_ENABLED" ]; then
        v=""
        v="$(printf '%s' "$env_json" | jq -r '.GC_PROACTIVE_ENABLED // empty' 2>/dev/null)" || v=""
        if [ -n "$v" ]; then PROACTIVE_ENABLED="$v"; fi
    fi
    if [ -z "${GC_PROACTIVE_CITY_CAP:-}" ]; then
        v=""
        v="$(printf '%s' "$env_json" | jq -r '.GC_PROACTIVE_CITY_CAP // empty' 2>/dev/null)" || v=""
        case "$v" in
            ''|*[!0-9]*) : ;;      # unset, or not a bare number: keep the default
            *)           CITY_CAP="$v" ;;
        esac
    fi
    return 0
}

usage() {
    cat <<EOF
Usage: $PROG demand [<pool-target>]   Pool work_query: emit routed proactive
                                      beads, or [] when AUTO-SPAWN is disabled
                                      (the default) or the city is at the
                                      session cap (the shed clamp). Read-only.
       $PROG scan [--json] [--sling]  Find movable-forward / opt-in beads; with
                                      --sling, sling a first reaction at each
                                      (capped). Read-only without --sling.
       $PROG sling <bead> [--nudge] [-n|--dry-run]
                                      Sling mol-first-reaction at <bead> on the
                                      codex-gated mr path. Refuses --merge
                                      direct (the security invariant).
       $PROG cap                      Print the city-cap state (active/cap/shed).
       $PROG deliverable              Would a slung first reaction actually be
                                      PICKED UP? Prints the reason; exit 0 yes,
                                      1 no. Read-only. For callers that must
                                      fall back when it is no.

Budget: pool cap = agents/proactive/agent.toml max_active_sessions; city cap =
GC_PROACTIVE_CITY_CAP (default $CITY_CAP_DEFAULT, else the pool's city config).
Security: proactive output is mr-only
(GC_PROACTIVE_MERGE=$MERGE; "direct" is refused).
EOF
}

# ---------------------------------------------------------------------------
# Cap clamp — count active city sessions and decide whether proactive sheds.
# ---------------------------------------------------------------------------

# active_session_count -> number of active sessions city-wide.
active_session_count() {
    local raw
    if [ -n "$FIXTURE" ]; then
        [ -f "$FIXTURE/sessions.json" ] || { printf '0'; return 0; }
        raw="$(cat "$FIXTURE/sessions.json")"
    else
        raw="$(gc session list --json 2>/dev/null || printf '{"sessions":[]}')"
    fi
    printf '%s' "$raw" | jq '[(.sessions // [])[] | select(.state == "active")] | length' 2>/dev/null \
        || printf '0'
}

# at_cap -> exit 0 (true) if the city is at/over the cap, else exit 1.
at_cap() {
    local active
    active="$(active_session_count)"
    [ "$active" -ge "$CITY_CAP" ]
}

cmd_cap() {
    local active state
    active="$(active_session_count)"
    if [ "$active" -ge "$CITY_CAP" ]; then state="SHED (at/over cap)"; else state="ok"; fi
    printf 'city-active=%s cap=%s -> %s\n' "$active" "$CITY_CAP" "$state"
    [ "$active" -lt "$CITY_CAP" ]
}

# ---------------------------------------------------------------------------
# deliverable — "if I sling right now, will anything ever pick it up?"
# Sling is fire-and-forget and both clamps are outside it (a shed and a
# disabled pool both return 0), so a caller that needs the reaction's OUTPUT
# must ask BEFORE it slings. Reuses the same clamp reads, so a third caller
# cannot drift. Exit 0 yes; 1 no, stdout names which clamp said no.
# ---------------------------------------------------------------------------
cmd_deliverable() {
    if ! proactive_auto_enabled; then
        # Name the consulted pool; capture in two steps (die exits the
        # substitution subshell, so an inline fallback never runs).
        local why_target=""
        why_target="$(resolve_pool_target 2>/dev/null)" || why_target=""
        [ -n "$why_target" ] || why_target="the proactive pool, which could not be named because GC_RIG is unset"
        printf 'no: proactive auto-spawn is disabled (GC_PROACTIVE_ENABLED is unset or not truthy in this process env AND in the city config for %s) — a slung reaction would sit routed and unclaimed\n' \
            "$why_target"
        return 1
    fi
    if at_cap; then
        printf 'no: city at session cap (%s/%s) — proactive sheds first under session pressure\n' \
            "$(active_session_count)" "$CITY_CAP"
        return 1
    fi
    printf 'yes: proactive enabled and under the city cap (%s/%s)\n' \
        "$(active_session_count)" "$CITY_CAP"
    return 0
}

# ---------------------------------------------------------------------------
# demand — the proactive pool's work_query. The reconciler runs this to
# decide whether to spawn a proactive worker. We SHED (emit []) at the cap so
# proactive is the first thing to stop under session pressure; otherwise we
# emit the standard pool demand (ready, unassigned, routed-to-us beads).
# ---------------------------------------------------------------------------

# proactive_auto_enabled -> true iff auto-spawn is opted in (the RESOLVED
# tunable). Truthy set mirrored in agents/proactive/agent.toml's work_query
# and scale_check; keep the three in sync (gate-asserted).
proactive_auto_enabled() {
    case "$PROACTIVE_ENABLED" in
        1|true|yes|on) return 0 ;;
        *)             return 1 ;;
    esac
}

cmd_demand() {
    # Gate FIRST — before the shed clamp — so a disabled surface emits []
    # regardless of city load and pays no session/ready queries.
    if ! proactive_auto_enabled; then
        printf '[]'
        return 0
    fi

    # The shed clamp: at/over the city cap, there is NO proactive demand.
    if at_cap; then
        printf '[]'
        return 0
    fi

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

    # --sling: advance each candidate up to the remaining city headroom, so a
    # scan never blows past the cap in one sweep.
    local active headroom slung=0
    active="$(active_session_count)"
    headroom=$(( CITY_CAP - active ))
    if [ "$headroom" -le 0 ]; then
        log "scan --sling: city at cap ($active/$CITY_CAP) — proactive sheds, nothing slung"
        return 0
    fi

    local ids
    ids="$(printf '%s' "$cands" | jq -r '.[].id')"
    local id
    for id in $ids; do
        [ "$slung" -ge "$headroom" ] && { log "scan --sling: hit city headroom ($headroom), stopping"; break; }
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

    # The shed clamp also guards the single-bead sling: at the cap, refuse to
    # add another proactive session.
    if [ -z "$dry" ] && at_cap; then
        log "$PROG: sling: city at session cap ($(active_session_count)/$CITY_CAP) — proactive sheds, not slinging $bead"
        return 0
    fi

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
    esac
    # Every remaining verb consults at least one of the two clamps. Resolve both
    # once, here — after --help, which must stay free of a config read.
    resolve_tunables
    case "$verb" in
        demand) cmd_demand "$@" ;;
        scan)   cmd_scan "$@" ;;
        sling)  cmd_sling "$@" ;;
        cap)    cmd_cap ;;
        deliverable) cmd_deliverable ;;
        *) die "unknown verb '$verb' (demand|scan|sling|cap|deliverable; --help)" ;;
    esac
}

main "$@"
