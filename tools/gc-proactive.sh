#!/usr/bin/env bash
# gc-proactive.sh — the proactive-via-slung-mol engine. Phase 4 of the
# Bead-Universe Operating Model (specs/bead-universe/design-doc.md —
# Key Components 5-6, Phase 4).
#
# "Proactive" in v1 is NOT a resident loop. It is a `mol-first-reaction`
# slung at a bead: a cheap first reaction (read the body → articulate /
# research → write a first-reaction CARD to the bead notes → file a visit
# on the bead) so the human arrives at *advanced* work. This
# tool is the budget-and-trigger layer around that sling. It owns no new
# lifecycle — it assembles `gc sling`, `gc bd ready`, `gc session list`, and
# the Phase-3 Helm (assets/scripts/gc-helm.sh).
#
# ── The two triggers (operator refinement on tk-3d0uh) ───────────────
# The proactive trigger has TWO forms, and this tool serves both:
#
#   1. PER-BEAD / opt-in / board-initiated — `sling <bead>`: an operator,
#      the board picker, or a one-shot at create/decomposition routes a
#      single bead for a first reaction. Also covers `metadata.gc.proactive=1`
#      as a per-bead opt-in flag.
#   2. PROCESS-SCAN — `scan [--sling]`: a polecat-pool-shaped scan for beads
#      "able to be updated" (open, ready, unassigned, not yet reacted) that
#      applies a first reaction to each. Same "how do I move this forward?"
#      loop the polecat demand-scan runs, but it ADVANCES rather than
#      implements. NOT a resident loop — it is a process you run (operator,
#      a patrol/cron, or the pool's own demand probe).
#
# ── Default-disabled: auto-spawn is OFF unless opted in ──────────────
# `demand` (the work_query, mirrored here) emits [] unless GC_PROACTIVE_ENABLED
# is truthy — the conservative default. See the GC_PROACTIVE_ENABLED tunable.
#
# ── The budget (design Key Component 5; "budget sessions, not bytes") ─
# Two independent clamps, because proactive fan-out spends whole sessions
# against a fragile shared Dolt:
#
#   • POOL CAP — the dedicated proactive pool (agents/proactive/agent.toml)
#     is `max_active_sessions = 2`, so proactive can never starve impl work
#     (the impl polecat pool keeps its own 5 slots). That cap lives in the
#     agent config; this tool does not re-implement it.
#   • CITY-WIDE SESSION CAP — `demand` (the proactive pool's work_query)
#     SHEDS — emits `[]`, so the reconciler spawns nothing — when the count
#     of active city sessions is at/over GC_PROACTIVE_CITY_CAP (~8-16 band,
#     default 20). This is the design's "reconciler clamp": the reconciler
#     runs work_query to decide whether to spawn, and an empty result means
#     "no demand." Proactive is the FIRST thing to shed under session
#     pressure (design degraded mode "proactive sheds first") because only
#     the proactive pool's work_query consults this clamp — impl pools are
#     untouched.
#
# ── The security invariant (design Key Component 6) ──────────────────
# Any code-producing proactive output takes the codex-gated `mr` merge
# path, NEVER `direct`. `sling` bakes `--merge mr` in and HARD-REFUSES a
# `direct` override (set GC_PROACTIVE_MERGE=local for the local-only path;
# `direct` is rejected outright). The city already defaults
# default_merge_strategy="mr" (city.toml) — this tool makes the proactive
# path fail closed rather than relying on that default.
#
# Side effects: `scan` (without --sling) and `demand` are READ-ONLY.
# `scan --sling` and `sling` route work via `gc sling` (and may surface a
# bead). Nothing here closes or merges anything.
#
# Tunables (env):
#   GC_PROACTIVE_ENABLED       master switch for demand-driven AUTO-SPAWN.
#                              Default-disabled: unanswered ⇒ `demand` emits []
#                              (no auto-spawn). Truthy (1/true/yes/on) opts in.
#                              Gates auto-spawn ONLY — manual sling/scan ignore
#                              it. Resolved env-first, then from the target
#                              pool's city config — see "Tunable resolution".
#   GC_PROACTIVE_POOL          proactive pool agent name. A bare base name
#                              (default "gc-toolkit.proactive") is rig-
#                              qualified to "<GC_RIG>/<base>" — the form the
#                              rig-scoped pool is addressed by (agent.toml
#                              watches {{.Rig}}/gc-toolkit.proactive, and
#                              `gc sling` rejects a bare agent name). Pass an
#                              already-qualified "<rig>/<base>" to override.
#   GC_PROACTIVE_CITY_CAP      city-wide active-session ceiling for the
#                              shed clamp (default 20; operator-tunable in
#                              the design's 8-16 band). Resolved env-first,
#                              then from the target pool's city config — see
#                              "Tunable resolution".
#   GC_PROACTIVE_MERGE         merge strategy for slung output (default
#                              "mr"; "local" allowed; "direct" REFUSED).
#   GC_PROACTIVE_SCAN_LIMIT    max candidates scan/--sling considers
#                              (default 20).
#   GC_PROACTIVE_FIXTURE       test hook: a directory of canned data
#                              (sessions.json, ready.json, scan.json). When
#                              set, the tool reads these instead of calling
#                              gc/bd, so the gate fixture is hermetic. The
#                              one exception is `sling --dry-run`, which
#                              still shells out to `gc sling -n` so the gate
#                              can prove the real command shape; set
#                              GC_PROACTIVE_FIXTURE to make `sling` echo the
#                              resolved command instead (no gc call).

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

# resolve_pool_target [override] -> the RIG-QUALIFIED pool target.
# The proactive pool is rig-scoped: agents/proactive/agent.toml watches
# `{{.Rig}}/gc-toolkit.proactive` and `gc sling` only resolves agents by their
# qualified `<rig>/<base>` name (a bare base is an unknown agent), so both the
# sling target and the `gc.routed_to` demand filter MUST carry the rig prefix.
# We DERIVE it from GC_RIG (matching the done-sequence's
# ${GC_RIG:+$GC_RIG/}gc-toolkit.refinery idiom). If the configured target is
# already qualified (contains '/'), it is used verbatim; otherwise we fail
# CLOSED when GC_RIG is unset rather than silently emitting an unroutable bare
# name — the bug this guards against.
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

# rig_beads_db -> this rig's `.beads` dir, to pin `gc bd --db` for parity with
# the Helm (assets/scripts/gc-helm.sh resolves the rig path from
# `gc rig list`/GC_RIG, then `$path/.beads`). We pin --db because bare `bd` (and
# `gc bd` without --db) resolves `.beads` by walking UP from cwd — but the
# proactive work_dir is a git worktree where `.beads` is gitignored, so the
# up-walk overshoots to the HQ `lx` ledger (the wrong store) and demand comes
# back empty. Echoes the path, or nothing when it cannot resolve (no GC_RIG, or
# no `.beads` at the path); callers then fall back to a bare `gc bd ready`, which
# still routes through GasCity (gc resolves the rig from GC_RIG/cwd) rather than
# the `bd` binary. Only reached on the live path (the FIXTURE branches return
# first), so the gate stays hermetic.
rig_beads_db() {
    [ -n "${GC_RIG:-}" ] || return 0
    local path
    path="$(gc rig list --json 2>/dev/null \
        | jq -r --arg n "$GC_RIG" '.rigs[]? | select(.name==$n) | .path' 2>/dev/null \
        | head -n1 || true)"
    [ -n "$path" ] && [ -d "$path/.beads" ] && printf '%s' "$path/.beads"
    return 0
}

# board_rank — re-rank a JSON array of beads (stdin) by the Helm's
# PRIORITY weight so the scarce proactive slots (pool max 2 + city cap) go to
# the highest-weight work, not merely the oldest. We reuse the board's priority
# component verbatim — assets/scripts/gc-helm.sh prio_w = max(0, 4 - p),
# i.e. P0->4 … P4->0, null->1 — and keep oldest-first as the in-band tiebreaker
# so a priority band still drains fairly. The board's other two weight terms
# (subtree size + cross-rig refs) are deliberately OMITTED: each needs a query
# per bead, too costly for a work_query/scan that runs against the shared Dolt.
# This same ranking is mirrored inline in agents/proactive/agent.toml's
# work_query (the real reconciler clamp); keep the two in sync.
board_rank() {
    jq 'def prio_w($p): (if $p == null then 1 else ([0, 4 - $p] | max) end);
        sort_by(-(prio_w(.priority)), (.created_at // ""))'
}

# ---------------------------------------------------------------------------
# Tunable resolution — the process env first, then the pool's CITY CONFIG.
# ---------------------------------------------------------------------------
# GC_PROACTIVE_ENABLED and GC_PROACTIVE_CITY_CAP are declared in city.toml on
# the proactive pool itself ([[rigs.overrides]] agent = "proactive", then
# [rigs.overrides.env]). The reconciler reads them from there and injects them
# into work_query/scale_check and into the pool's own sessions — so every
# CONSUMER of the decision sees them. Nothing else does.
#
# The decision is made on the PRODUCER side, in a process that gets no such
# injection. `deliverable` is called by assets/scripts/gc-visit-open.sh, whose
# primary caller is the helm service (services/helm/internal/server/open.go);
# helm-svc's process env carries no GC_PROACTIVE_* and structurally cannot — a
# [[service]] block has no env field at all (gascity internal/config/service.go:
# ServiceProcessConfig is {Command, HealthPath}). Reading the env alone made the
# gate answer "disabled" to the one caller that has to ask, so every visit the
# board opened was filed with no framing card, for as long as the switch was on
# (tk-hscs0).
#
# So resolve each tunable the way the reconciler effectively does:
#
#   1. the PROCESS ENV when set — an explicit operator override, and what an
#      already-injected caller (a proactive session, work_query) carries;
#   2. otherwise the RESOLVED CITY CONFIG for the pool this run targets — the
#      same [agent.env] the reconciler injects from;
#   3. otherwise the built-in default.
#
# Step 2 costs one `gc config show --json` (~0.3s), taken at most once per run
# and only for a tunable the env left unanswered, so an injected caller pays
# nothing. It fails SOFT in every direction: an unreachable city, an
# unparsable document, an unknown pool, or a non-numeric cap all leave the
# env/default answer standing, which is exactly the pre-existing behavior.

# pool_config_env -> the target pool's resolved [agent.env] as a JSON object,
# or `{}` when it cannot be read. In fixture mode the raw `gc config show
# --json` document is read from $GC_PROACTIVE_FIXTURE/config.json (absent = no
# config layer at all), so the target derivation and the extraction below are
# the SAME code the live path runs — the fixture stubs the source, not the
# logic.
#
# The config keys an agent by its own bare name plus the rig dir it belongs to
# (Name = "proactive", Dir = "<rig>"), while the pool TARGET is the qualified
# import form "<rig>/<binding>.<agent-base>". Strip both wrappers to look it up.
pool_config_env() {
    local target rig base raw out
    target=""
    # resolve_pool_target `die`s when it cannot rig-qualify. That is fatal for a
    # sling and merely unanswerable here, so absorb it in the subshell and fall
    # back to "no config layer".
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

# resolve_tunables — fill PROACTIVE_ENABLED / CITY_CAP from the pool's city
# config for whichever of the two the process env did not answer. Exactly one
# config read, or none at all when the env answered both.
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
# ---------------------------------------------------------------------------
# `sling` is fire-and-forget: it routes a bead to the proactive pool and the
# REACTION happens later, in a session the reconciler decides to spawn. Both
# clamps that decide that spawn are OUTSIDE the sling, and neither reports back:
#
#   * at the city cap, `sling` itself logs "proactive sheds" and returns 0 —
#     success and no-op are the same exit status; and
#   * with auto-spawn disabled (the DEFAULT — GC_PROACTIVE_ENABLED unset), the
#     sling succeeds outright and the bead simply sits routed forever, because
#     work_query/scale_check both emit "no demand" and nothing is ever spawned.
#
# So a caller that depends on the reaction's OUTPUT — notably the visit
# assets/scripts/gc-visit-open.sh hands the operator, which mol-first-reaction's
# advance-and-drain step is what actually files — cannot learn from `sling`
# whether it got anything. It must ask BEFORE it slings and take its own path
# when the answer is no. That is the whole job of this verb.
#
# It re-uses `proactive_auto_enabled` and `at_cap` rather than restating either
# clamp, so the third caller cannot drift from the two copies that already have
# to be kept in sync (this file and agents/proactive/agent.toml).
#
# Read-only. Exit 0 = a slung reaction will be picked up; 1 = it will not, and
# stdout names which clamp said no (the two need different operator moves:
# set GC_PROACTIVE_ENABLED, versus wait for city load to fall).
cmd_deliverable() {
    if ! proactive_auto_enabled; then
        printf 'no: proactive auto-spawn is disabled (GC_PROACTIVE_ENABLED is unset or not truthy in this process env AND in %s'"'"'s city config) — a slung reaction would sit routed and unclaimed\n' \
            "$(resolve_pool_target 2>/dev/null || printf 'the proactive pool')"
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

# proactive_auto_enabled -> true iff auto-spawn is opted in. Reads the RESOLVED
# tunable (env, else the pool's city config — see "Tunable resolution"), never
# the raw env, so the answer does not depend on which process asks.
#
# The truthy set is mirrored inline in agents/proactive/agent.toml's work_query
# and scale_check (the real reconciler clamp); keep the three in sync
# (gate-asserted). Those two copies read the env directly and correctly: the
# reconciler injects the pool's [agent.env] into them, so the env IS the config
# there. This resolution exists for every caller that gets no such injection.
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

    # Build the sling argv. The target is rig-qualified (resolve_pool_target)
    # so `gc sling` resolves the rig-scoped pool agent rather than rejecting a
    # bare name; --on attaches the mol-first-reaction workflow to the existing
    # bead and routes THAT bead to the pool (the pool's work_query selects on
    # the bead's gc.routed_to, not on the workflow root); --merge pins the
    # path; --reassign hands a human-held bead to the pool cleanly.
    #
    # --on is load-bearing and must not be dropped: the proactive pool declares
    # no default_sling_formula of its own and inherits agent_defaults'
    # "mol-polecat-work", so a plain sling would pour the wrong formula.
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
