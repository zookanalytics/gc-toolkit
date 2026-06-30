#!/bin/sh
# gc-zortex.sh — the cross-rig human-attention board plus the pick-a-row
# launcher that lands you in a bead's conversation. The operator reaches it
# via the prefix+b tmux board picker (tmux-pick-zortex.sh) or by running
# this script directly; it is NOT a registered gc subcommand. Pack commands
# bind under the pack name (`gc <pack> <cmd>`), so there is no top-level
# zortex command — invoke this script (or the picker), not `gc`.
#
# Usage:
#   gc-zortex [board] [--json] [--limit=N] [--timeout=SECONDS] [--refresh]
#   gc-zortex open  <bead-id>                 land in the bead (resume-or-create its host)
#   gc-zortex flag  <bead-id> --reason "..."  raise this bead onto the board
#   gc-zortex clear <bead-id>                 lower it again (the handled row leaves)
#   gc-zortex takeaway <bead-id> "<text>" [--by …] [--release]  set the board-visible takeaway headline
#
# Phase 3 of the Bead-Universe Operating Model (epic tk-q4xaj; bead
# tk-qkags; design Key Component 4, Phase 3). The board (the default
# verb) is the evolved read-only ranking from PR #83; `open`/`flag`/
# `clear` are the new verbs that close the board→land→accept/redirect→
# leave loop:
#
#   flag  → a bead's LLM (or the operator) raises its own bead onto the
#           board by setting `gc.attention` — escalation inversion, the
#           dual of mailing the mayor.
#   board → the operator glances the ranked rows (now with a 4th anchor
#           kind — flagged beads — a liveness glyph, a row cap, and a
#           cache so the ~12s gather is paid once, not every glance).
#   open  → pick a row; the bead's resident host is resumed (hot) or
#           materialized (cold) and the operator lands in the
#           conversation, already primed with the bead's universe.
#   clear → the operator ratifies/redirects and the handled row leaves
#           the board (a shrinking queue).
#
# `open` is a thin front door over tools/gc-bead-host.sh (the Phase 1
# spawn-or-resume + durable bead<->session link) followed by
# `gc session attach` (the Phase-0/1 resume mechanism). It owns no new
# lifecycle — it assembles the proven primitives.
#
# ── What is an anchor ────────────────────────────────────────────────
# FIVE kinds of OPEN top-level anchors are collected, cross-rig:
#   1. epic       — every open `epic`-type bead (per-rig durable anchor).
#   2. convoy     — OWNED convoys that are NOT under an epic (floating
#                   "epic-improvisers"). MACHINE convoys are transient and
#                   excluded: `sling-*` AND the per-sling `input convoy
#                   for …` one-child wrappers.
#   3. unowned    — a NON-machine convoy that is NOT owned. Under the
#                   everything-is-owned law (work-bead-state-machine.md)
#                   every PR/branch/unit is owned by a bead, so an unowned
#                   non-machine convoy is the orphan EXCEPTION the observer
#                   must CATCH — surfaced HIGH, never silently dropped (the
#                   old `owned==true` filter hid exactly this case).
#   4. decision   — every open `decision`-type bead (human-gated; only a
#                   human can move it).
#   5. flagged    — any open bead with `metadata.gc.attention=1` (set by
#                   `gc-zortex flag`): a bead's LLM, or the operator,
#                   has explicitly raised it. Flagged rows float to the
#                   very top (their own FLAGGED band) — a hand was raised.
#
# Beads live in separate per-rig Dolt databases (lo/tk/sl/gc/su/…), so
# the board enumerates `gc rig list` and queries each rig's `.beads`
# directory by path via `gc bd --db`. `gc convoy list` already spans
# rigs, so it is used directly for the convoy gather. `--global` is NOT
# relied upon (it needs shared-server mode).
#
# ── Per-anchor deterministic frontier facts ──────────────────────────
#   • N/M            — children/members closed (N) of total (M). Epic
#                      children come from the `--parent` roll-up; convoy
#                      members from the convoy bead's tracks deps
#                      (`bd show --include-dependents`). N/M and the
#                      frontier derive from the SAME child set, so a row
#                      cannot self-contradict. `gc convoy list` .progress
#                      is kept ONLY as a cross-check: any disagreement
#                      with the resolved set is surfaced as
#                      `progress_mismatch` in the JSON output. Decisions
#                      and flagged beads carry no frontier (N/M = —).
#   • open/in-progress/assigned — counts over the open frontier.
#   • stranded       — decomposed (M>0) with open children, ZERO LIVE
#                      in-progress, AND no live host: work exists but
#                      nothing is moving. A live host counts as moving —
#                      the bead is worked via a resident 1:1 conversation,
#                      not via in-progress child polecats. An in-progress
#                      child whose OWNING session is dead (state
#                      archived/closed/absent — keyed off .state, never
#                      .running, per the witness orphan-liveness rule) does
#                      NOT count as moving: it is the canonical UNKNOWN-stuck
#                      case, so a frontier of only dead-owner children reads
#                      stranded, not active (PROBLEM 1).
#   • dead_owner     — count of in-progress children with a dead/absent
#                      owner. Surfaced as "stuck (dead owner)" and never
#                      masks a stall; the stuck ids ride into --json as
#                      dead_owner_heads.
#   • empty          — an epic/convoy with no children (M==0).
#   • complete       — M>0 but every child closed (0 open): awaiting
#                      graduation/close.
#   • live           — host liveness, joined from `gc session list` by the
#                      bead-id the host's alias encodes. A bead-host alias
#                      is pack-namespaced (<pack>.<bead-id>), so the leading
#                      "<pack>." is stripped and only bead-host template
#                      sessions are joined:
#                      "hot" (active session — open ATTACHES instantly),
#                      "warm" (suspended/asleep — open RESUMES the saved
#                      conversation), or "cold" (no host — open
#                      MATERIALIZES one). The glance answers "is anyone
#                      home?" before you pick the row. A live host also
#                      keeps the anchor out of the stranded/HIGH band.
#   • stale_days     — days since the anchor itself was last updated.
#   • cross_rig_refs — DETERMINISTIC prose scan of the anchor body for
#                      bead-ids belonging to OTHER rigs (cross-rig work
#                      is forced into prose today; formal cross-rig dep
#                      edges are rare). A stranded anchor that blocks
#                      another rig is more urgent, so refs add weight.
#
# ── Ranking heuristic (deterministic; documented) ────────────────────
# Each anchor gets a SEVERITY band, then rows sort by band, then by a
# weight PROXY, then by staleness:
#
#   FLAGGED   a bead explicitly raised onto the board (hand-raised).
#   HIGH      stranded frontier (decomposed, open, no LIVE in-progress, and
#             no live host — incl. a frontier whose only in-progress
#             children have dead owners), OR an unowned non-machine convoy
#             (the orphan exception).
#   ELEVATED  a `decision` (human-gated); an otherwise-NORMAL anchor gone
#             stale (> STALE_DAYS days); OR a still-moving anchor that has a
#             dead-owner (stuck) in-progress child to recover.
#   NORMAL    active frontier (has LIVE in-progress work, OR a live host —
#             someone is in the conversation).
#   LOW       empty epic (0 children) or complete convoy (all closed).
#
#   weight PROXY = M (subtree size)
#                + priority weight (P1→3, P2→2, P3→1, P4→0)
#                + cross-rig ref count (capped).
#
# The proxy is intentionally crude — subtree size + priority + cross-rig
# blast radius — NOT an LLM weight. Sort key is
# (severity_band, weight, stale_days) descending.
#
# ── Output ───────────────────────────────────────────────────────────
# Default: a human-readable ranked table + one-line legend.
# `--json`: a ranked JSON array; each element carries every fact above
# plus the computed `severity`, `weight`, `rank_score`, `frontier`
# (one-line summary), `needs` (short hint), and `live` (host state).
# `--json` is the stable contract for downstream tooling (the tmux
# board picker reads it). The array is additive-only — new fields
# (`live`, `host_session_name`, kind "flagged", severity "FLAGGED";
# `in_progress_live`, `in_progress_dead`, `dead_owner`, `dead_owner_heads`,
# `owned`, kind "unowned") were added without changing or removing any
# existing field.
#
# ── Row cap & cache (the board must scale) ───────────────────────────
# The gather hits every rig's Dolt and costs ~seconds; the liveness
# join is a single fast `gc session list`. So the EXPENSIVE GATHER is
# cached (default TTL GC_ZORTEX_CACHE_TTL=45s) while liveness +
# ranking are recomputed every glance — a glance is sub-second on a warm
# cache and the host state is never stale. `--refresh` (or `flag`/
# `clear`/`open`, which bust the cache) forces a fresh gather. Rows are
# CAPPED at GC_ZORTEX_MAX_ROWS (default 50) by default so the board
# can never balloon to "every bead"; `--limit=N` overrides with an
# explicit N, and `--limit=0` means ALL (uncapped) for tooling.
#
# Exit codes:
#   0   board rendered / verb succeeded
#   2   usage error
#   3   missing dependency (jq / gc) or could not enumerate rigs
#   4   verb runtime failure (e.g. bead not found, host spawn failed)
#
# Test hook: GC_ZORTEX_FIXTURE=<dir> — when set, the board reads
# canned data instead of Dolt/sessions: <dir>/anchors.ndjson (one anchor
# object per line, the gathered shape) and <dir>/sessions.json (the
# `gc session list --json` shape). Keeps the Phase 3 render/rank/glyph
# assertions hermetic. Unset in normal use.

set -eu

PROG="gc-zortex"

# ── Tunables ─────────────────────────────────────────────────────────
STALE_DAYS=14                                   # > this many days since update → staleness bump
XREF_CAP=5                                       # max cross-rig refs that count toward weight
MAX_ROWS="${GC_ZORTEX_MAX_ROWS:-50}"          # default row cap (--limit=0 disables)
CACHE_TTL="${GC_ZORTEX_CACHE_TTL:-45}"        # seconds the gather cache stays fresh
FIXTURE="${GC_ZORTEX_FIXTURE:-}"              # test hook (see header)
# Fall back to defaults on a non-numeric override so `set -e` arithmetic
# (the cap + cache-age tests) can't crash the board on a bad env value.
case "$MAX_ROWS"  in ''|*[!0-9]*) MAX_ROWS=50 ;; esac
case "$CACHE_TTL" in ''|*[!0-9]*) CACHE_TTL=45 ;; esac

usage() {
    cat >&2 <<'EOF'
Usage:
  gc-zortex [board] [--json] [--limit=N] [--timeout=SECONDS] [--refresh]
  gc-zortex open  <bead-id>                 land in the bead (resume-or-create its host)
  gc-zortex flag  <bead-id> --reason "..."  raise this bead onto the board
  gc-zortex clear <bead-id>                 lower it again (the handled row leaves)
  gc-zortex react <bead-id> [--reason "..."]  sling a first reaction (self-heals a takeaway-less row)
  gc-zortex takeaway <bead-id> "<text>" [--by host|proactive] [--release]  set the board-visible takeaway headline

The board (default verb) is a read-only cross-rig ranking of OPEN anchors
(epics, floating owned convoys, decisions, and flagged beads) by how much
they need a human's attention. open/flag/clear close the
board→land→accept/redirect→leave loop; react slings a proactive first
reaction (via tools/gc-proactive.sh, on the codex-gated mr path) so a
takeaway-less row self-heals to an explanatory NEEDS on the next render.
takeaway writes that NEEDS headline directly — the thin writer the host and
proactive worker call to stamp gc.takeaway (+_at/+_by) in one update; with
--release it also reopens/unassigns/clears the route and marks the proactive
reaction in that same write (the proactive worker's one-call close).

  --json             Emit the ranked board as a JSON array (stable contract).
  --limit=N          Show only the top N rows (0 = all/uncapped; default caps at 50).
  --timeout=SECONDS  Per-query timeout bound for Dolt reads (default 10).
  --refresh          Bypass the gather cache and re-query every rig now.
  -h, --help         This help.
EOF
}

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 3; }
command -v gc >/dev/null 2>&1 || { echo "$PROG: gc is required" >&2; exit 3; }

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Resolve sibling tools regardless of where the pack is materialized:
# assets/scripts/ and tools/ are siblings under the pack root.
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
BEAD_HOST_TOOL="${GC_BEAD_HOST_TOOL:-$SCRIPT_DIR/../../tools/gc-bead-host.sh}"
PROACTIVE_TOOL="${GC_PROACTIVE_TOOL:-$SCRIPT_DIR/../../tools/gc-proactive.sh}"

# ── Cache location ───────────────────────────────────────────────────
# Keyed by city path so distinct cities don't collide. Cache format:
# line 1 = gather epoch, lines 2.. = anchors ndjson (portable: no stat(1)
# / find(1) mtime flags, which differ GNU vs BSD).
CACHE_DIR="${TMPDIR:-/tmp}/gc-zortex-cache.$(id -u 2>/dev/null || echo 0)"
_city_key=$(printf '%s' "${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-default}}}" | cksum | cut -d' ' -f1)
CACHE_FILE="$CACHE_DIR/anchors-$_city_key.ndjson"

bust_cache() { rm -f "$CACHE_FILE" 2>/dev/null || true; }

# ── Rig enumeration (shared by board + verb rig resolution) ───────────
# Sets RIGS (JSON array of {name,path,prefix}). Exits 3 if none.
RIGS=""
enumerate_rigs() {
    [ -n "$RIGS" ] && return 0
    if [ -n "$FIXTURE" ] && [ -f "$FIXTURE/rigs.json" ]; then
        RIGS=$(jq -c '.' < "$FIXTURE/rigs.json" 2>/dev/null || printf '[]')
        [ "$(printf '%s' "$RIGS" | jq 'length')" -gt 0 ] && return 0
    fi
    rigs_raw=$(timeout "${TIMEOUT:-10}" gc rig list --json 2>/dev/null || true)
    RIGS=$(printf '%s' "$rigs_raw" | jq -c '[.rigs[]? | {name, path, prefix}]' 2>/dev/null || printf '[]')
    if [ "$(printf '%s' "$RIGS" | jq 'length')" -eq 0 ]; then
        echo "$PROG: could not enumerate rigs (gc rig list returned nothing)" >&2
        exit 3
    fi
}

# rig_path_for_bead <bead-id> — the rig repo path owning the bead, by id
# prefix (chars before the first '-'); empty if no rig matches.
rig_path_for_bead() {
    enumerate_rigs
    printf '%s' "$RIGS" | jq -r --arg p "${1%%-*}" '.[] | select(.prefix==$p) | .path' 2>/dev/null | head -n1
}

# rig_name_for_bead <bead-id> — the rig NAME owning the bead, by id prefix;
# empty if no rig matches. Parallel to rig_path_for_bead but returns .name —
# the value gc-proactive.sh rig-qualifies its pool target from via GC_RIG.
rig_name_for_bead() {
    enumerate_rigs
    printf '%s' "$RIGS" | jq -r --arg p "${1%%-*}" '.[] | select(.prefix==$p) | .name' 2>/dev/null | head -n1
}

# ── Verb: flag ───────────────────────────────────────────────────────
# Raise a bead onto the board. `gc.attention=1` is the stable, exact-
# match-listable sentinel the board's 4th-anchor query filters on; the
# human-facing detail rides alongside in gc.attention_reason /
# gc.attention_at so the board can show WHY and HOW FRESH.
cmd_flag() {
    bead=""; reason=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason=*) reason="${1#--reason=}"; shift ;;
            --reason) shift; [ $# -gt 0 ] || { echo "$PROG: --reason requires a value" >&2; exit 2; }; reason="$1"; shift ;;
            -h|--help) usage; exit 0 ;;
            -*) echo "$PROG: flag: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: flag takes one bead-id" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done
    [ -n "$bead" ] || { echo "$PROG: flag needs <bead-id>" >&2; usage; exit 2; }
    [ -n "$reason" ] || { echo "$PROG: flag needs --reason \"...\" (why this needs a human)" >&2; exit 2; }

    path=$(rig_path_for_bead "$bead")
    db=""; [ -n "$path" ] && [ -d "$path/.beads" ] && db="$path/.beads"
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
    gc bd update "$bead" ${db:+--db "$db"} \
        --set-metadata "gc.attention=1" \
        --set-metadata "gc.attention_reason=$reason" \
        --set-metadata "gc.attention_at=$(iso_now)" >/dev/null 2>&1 \
        || { echo "$PROG: flag: could not update '$bead' (does it exist in rig '${path:-?}'?)" >&2; exit 4; }
    bust_cache
    echo "flagged $bead onto the Zortex board: $reason"
}

# ── Verb: clear ──────────────────────────────────────────────────────
# Lower a bead again — the handled row leaves the board (shrinking queue).
cmd_clear() {
    bead="${1:-}"
    case "$bead" in -h|--help) usage; exit 0 ;; "") echo "$PROG: clear needs <bead-id>" >&2; usage; exit 2 ;; esac
    path=$(rig_path_for_bead "$bead")
    db=""; [ -n "$path" ] && [ -d "$path/.beads" ] && db="$path/.beads"
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 fields
    gc bd update "$bead" ${db:+--db "$db"} \
        --unset-metadata "gc.attention" \
        --unset-metadata "gc.attention_reason" \
        --unset-metadata "gc.attention_at" >/dev/null 2>&1 \
        || { echo "$PROG: clear: could not update '$bead'" >&2; exit 4; }
    bust_cache
    echo "cleared $bead from the Zortex board"
}

# ── Verb: takeaway ───────────────────────────────────────────────────
# Write the board-visible takeaway headline — the thin writer the bead-host
# and proactive worker call instead of inlining the `gc bd update
# --set-metadata gc.takeaway=… gc.takeaway_at=… gc.takeaway_by=…` triple.
# Mirrors flag/clear: resolve the bead's rig db, stamp the three fields in ONE
# update, then bust the cache so the next board glance reflects the new
# headline (an improvement over the old inline form, which never busted it).
#
# --release folds the proactive reaction-release into the SAME update: alongside
# the takeaway stamp it ALSO marks the reaction + reopens + unassigns + clears
# the route (gc.proactive_reaction=1, --status=open, empty --assignee, empty
# gc.routed_to) in one Dolt write. The proactive worker / mol-first-reaction
# call `takeaway … --release` as their single closing step, replacing a takeaway
# stamp followed by a separate release `gc bd update`.
cmd_takeaway() {
    bead=""; text=""; by="host"; release=""; npos=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --by=*)    by="${1#--by=}"; shift ;;
            --by)      shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --by requires a value" >&2; exit 2; }; by="$1"; shift ;;
            --release) release=1; shift ;;
            -h|--help) usage; exit 0 ;;
            -*) echo "$PROG: takeaway: unknown flag '$1'" >&2; exit 2 ;;
            *)
                npos=$((npos + 1))
                case "$npos" in
                    1) bead="$1" ;;
                    2) text="$1" ;;
                    *) echo "$PROG: takeaway takes one <bead-id> and one \"<text>\"" >&2; exit 2 ;;
                esac
                shift ;;
        esac
    done
    [ -n "$bead" ] || { echo "$PROG: takeaway needs <bead-id>" >&2; usage; exit 2; }

    # Collapse internal whitespace runs (incl. stray newlines/tabs) to single
    # spaces and trim — the board render collapses too, but storing clean keeps
    # `gc bd show` legible. Do this BEFORE the empty check so whitespace-only
    # text is rejected as missing.
    text=$(printf '%s' "$text" | tr -s '[:space:]' ' ')
    text="${text# }"; text="${text% }"
    [ -n "$text" ] || { echo "$PROG: takeaway needs \"<text>\" (the ≤140-char one-line headline)" >&2; usage; exit 2; }

    # Provenance: host (default) or proactive; free-form like flag's --reason.
    [ -n "$by" ] || by="host"

    path=$(rig_path_for_bead "$bead")
    db=""; [ -n "$path" ] && [ -d "$path/.beads" ] && db="$path/.beads"

    # Build the update args with `set --` ($text/$by contain spaces, so an
    # unquoted ${var:+…} would word-split them). --release folds the proactive
    # reaction-release bundle into the SAME update so the takeaway stamp and the
    # release stay ONE Dolt write.
    set --
    set -- "$@" --set-metadata "gc.takeaway=$text" \
               --set-metadata "gc.takeaway_at=$(iso_now)" \
               --set-metadata "gc.takeaway_by=$by"
    [ -n "$release" ] && set -- "$@" --status=open --assignee= \
               --set-metadata "gc.routed_to=" --set-metadata "gc.proactive_reaction=1"
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd update "$bead" ${db:+--db "$db"} "$@" >/dev/null 2>&1 \
        || { echo "$PROG: takeaway: could not update '$bead' (does it exist in rig '${path:-?}'?)" >&2; exit 4; }
    bust_cache
    echo "takeaway set on $bead (by $by)${release:+ [released]}: $text"
}

# ── Verb: open ───────────────────────────────────────────────────────
# The pick-a-row launcher. Resume-or-create the bead's host (Phase 1
# tool), then attach. One keystroke from "I see the row" to "I'm in the
# advanced conversation." Opening busts the cache so the next board
# render reflects the now-hot row.
cmd_open() {
    bead="${1:-}"
    case "$bead" in -h|--help) usage; exit 0 ;; "") echo "$PROG: open needs <bead-id>" >&2; usage; exit 2 ;; esac
    [ -x "$BEAD_HOST_TOOL" ] || command -v gc-bead-host.sh >/dev/null 2>&1 \
        || { echo "$PROG: open: cannot find gc-bead-host.sh (looked at $BEAD_HOST_TOOL)" >&2; exit 4; }
    tool="$BEAD_HOST_TOOL"; [ -x "$tool" ] || tool="$(command -v gc-bead-host.sh)"

    # Point bd at the bead's rig so spawn-or-resume + the durable link
    # land in the right per-rig ledger even cross-rig (BEADS_DIR pins bd).
    path=$(rig_path_for_bead "$bead")
    [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"

    # Spawn-or-resume + write the durable bead<->session link (Phase 1).
    if ! "$tool" up "$bead"; then
        echo "$PROG: open: gc-bead-host.sh up '$bead' failed" >&2
        exit 4
    fi
    bust_cache

    # Land in it. A bead-host's real tmux session is named by its session_name
    # (`s-<session-id>`) — NOT the bead id and NOT the (rig-prefixed) alias. `up`
    # cached that name on the work bead as host_session_name (gc-bead-host.sh's
    # link step); read it back and switch to THAT. Fall back to the bead id only
    # if the cache is somehow unresolved.
    switch_target=$(gc bd show "$bead" --json 2>/dev/null \
        | jq -r '.[0].metadata.host_session_name // empty' 2>/dev/null || true)
    [ -n "$switch_target" ] || switch_target="$bead"

    echo "$PROG: host for $bead is up — landing..." >&2
    # "In a tmux" is NOT "in the GC tmux". Switch the client ONLY when the host
    # session lives on the tmux server we're attached to right now. On a separate
    # window (a different tmux server) that session isn't here and never will be:
    # a switch can't land, the old poll-everywhere path turned that into a 45s
    # hang, and forcing it would hijack an unrelated client on the other server.
    #
    # `up` returned only after the host reached a live/registered state
    # (gc-bead-host.sh blocks on it), so an IMMEDIATE has-session probe is
    # authoritative — no poll needed. Use bare tmux (honoring $TMUX, the CURRENT
    # server), never `-L $GC_TMUX_SOCKET`: the question is "is the host on the
    # server I'm on now?". Under the board picker's `run-shell`, $TMUX is the GC
    # city server (GC_TMUX_SOCKET is unset there), so the picker path lands.
    if [ -n "${TMUX:-}" ]; then
        if tmux has-session -t "$switch_target" 2>/dev/null; then
            # Same server (board picker / gc-tmux-shell) — land the client.
            tmux switch-client -t "$switch_target" || {
                echo "$PROG: host for $bead is up; could not switch the tmux client." >&2
                echo "       Switch yourself:  prefix+S  (or: tmux switch-client -t $switch_target)" >&2
            }
        else
            # Different tmux server (separate window) — bring-up done, report and
            # return promptly. No switch (would hijack), no poll (would hang).
            echo "$PROG: host for $bead is up (tmux session $switch_target on the gc tmux server)." >&2
            echo "       Land it:  prefix+S  (or, on the gc tmux: tmux switch-client -t $switch_target)" >&2
        fi
    else
        gc session attach "$bead" || {
            echo "$PROG: host for $bead is up; could not attach from this context." >&2
            echo "       Attach it yourself:  gc session attach $bead" >&2
        }
    fi
}

# ── Verb: react ──────────────────────────────────────────────────────
# The discoverable front-door for a proactive first reaction. A takeaway-
# less board row explains little; `react <id>` slings mol-first-reaction at
# the bead so a worker writes a first-reaction CARD and stamps gc.takeaway —
# cmd_board then self-heals that row to explanatory on the next render.
#
# THIN WRAPPER: it owns no sling logic. It reuses tools/gc-proactive.sh's
# `sling` verb verbatim, which bakes in the budget/cap clamp AND the codex-
# gated `mr` merge path (the epic's proactive-code security invariant) — so
# the front-door inherits those guarantees instead of re-deriving them.
cmd_react() {
    bead=""; reason=""; nudge=""; dry=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason=*) reason="${1#--reason=}"; shift ;;
            --reason) shift; [ $# -gt 0 ] || { echo "$PROG: react: --reason requires a value" >&2; exit 2; }; reason="$1"; shift ;;
            --nudge) nudge=1; shift ;;
            -n|--dry-run) dry=1; shift ;;
            -h|--help) usage; exit 0 ;;
            -*) echo "$PROG: react: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: react takes one bead-id" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done
    [ -n "$bead" ] || { echo "$PROG: react needs <bead-id>" >&2; usage; exit 2; }

    tool="$PROACTIVE_TOOL"
    [ -x "$tool" ] || tool="$(command -v gc-proactive.sh 2>/dev/null || true)"
    [ -n "$tool" ] && [ -x "$tool" ] \
        || { echo "$PROG: react: cannot find gc-proactive.sh (looked at $PROACTIVE_TOOL)" >&2; exit 4; }

    # Pin bd at the bead's rig so the sling's demand/route resolve in the
    # right per-rig ledger even cross-rig (parity with open/flag/clear).
    path=$(rig_path_for_bead "$bead")
    [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"

    # gc-proactive.sh rig-qualifies its pool target from GC_RIG and fails
    # CLOSED when it is unset; export the bead's rig so the sling resolves
    # <rig>/gc-toolkit.proactive even from a GC_RIG-less shell (the normal
    # operator path) or cross-rig. Gate on the NAME resolving — NOT on
    # $path/.beads existing (unlike BEADS_DIR above) — so a cross-rig react
    # still qualifies the target where the local .beads dir isn't present. The
    # bead's rig is authoritative, so this overrides any ambient GC_RIG: a tk-
    # bead's reaction routes to gc-toolkit's proactive pool regardless.
    rig=$(rig_name_for_bead "$bead")
    [ -n "$rig" ] && export GC_RIG="$rig"

    # The reason is operator intent for the log/trail. gc-proactive.sh sling
    # reads the bead BODY (it has no --reason; the first reaction's seed is the
    # body), so we surface the reason here and never forward it — forwarding an
    # unknown flag would make the sling error.
    [ -n "$reason" ] && echo "$PROG: react $bead — $reason" >&2

    # Reuse the existing sling verbatim; pass through --nudge / --dry-run.
    set -- sling "$bead"
    [ -n "$nudge" ] && set -- "$@" --nudge
    [ -n "$dry" ] && set -- "$@" --dry-run
    "$tool" "$@" || { echo "$PROG: react: gc-proactive.sh sling '$bead' failed" >&2; exit 4; }

    # Best-effort: the reaction (card + gc.takeaway) lands ASYNC in the slung
    # session, so this only clears the cache for the next glance; the gather's
    # TTL covers the window until the reaction actually writes.
    if [ -z "$dry" ]; then bust_cache; fi
}

# ── Verb: board (default) ────────────────────────────────────────────
cmd_board() {
    JSON=0; LIMIT=""; TIMEOUT=10; REFRESH=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) JSON=1; shift ;;
            --limit=*) LIMIT="${1#--limit=}"; shift ;;
            --limit) shift; [ $# -gt 0 ] || { echo "$PROG: --limit requires a value" >&2; usage; exit 2; }; LIMIT="$1"; shift ;;
            --timeout=*) TIMEOUT="${1#--timeout=}"; shift ;;
            --timeout) shift; [ $# -gt 0 ] || { echo "$PROG: --timeout requires a value" >&2; usage; exit 2; }; TIMEOUT="$1"; shift ;;
            --refresh|--no-cache) REFRESH=1; shift ;;
            -h|--help) usage; exit 0 ;;
            --) shift; break ;;
            -*) echo "$PROG: unknown flag '$1'" >&2; usage; exit 2 ;;
            *) echo "$PROG: unexpected argument '$1'" >&2; usage; exit 2 ;;
        esac
    done
    case "$LIMIT" in ""|*[!0-9]*) [ -z "$LIMIT" ] || { echo "$PROG: --limit must be a non-negative integer" >&2; exit 2; } ;; esac
    case "$TIMEOUT" in *[!0-9]*) echo "$PROG: --timeout must be a non-negative integer (seconds)" >&2; exit 2 ;; esac

    # Effective cap: explicit --limit wins (0 = uncapped); else default cap.
    if [ -n "$LIMIT" ]; then EFFLIMIT="$LIMIT"; else EFFLIMIT="$MAX_ROWS"; fi

    TMP=$(mktemp -d 2>/dev/null) || { echo "$PROG: could not allocate temp dir" >&2; exit 3; }
    trap 'rm -rf "$TMP"' EXIT INT TERM HUP
    ANCHORS="$TMP/anchors.ndjson"
    : > "$ANCHORS"

    NOW_EPOCH=$(date -u +%s)
    NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Bounded gc wrapper: never let a slow/wedged Dolt query abort the board.
    gcq() { timeout "$TIMEOUT" gc "$@" 2>/dev/null || true; }
    as_array() {
        if printf '%s' "$1" | jq -e 'type=="array"' >/dev/null 2>&1; then printf '%s' "$1"; else printf '[]'; fi
    }

    enumerate_rigs
    PREFIXES=$(printf '%s' "$RIGS" | jq -c '[.[].prefix]')
    RIGNAMES=$(printf '%s' "$RIGS" | jq -c '[.[].name]')
    rig_for_prefix() { printf '%s' "$RIGS" | jq -c --arg p "$1" '.[] | select(.prefix==$p)' 2>/dev/null | head -n1; }

    # ── Gather (cached: the expensive part) ──────────────────────────
    gathered_from_cache=0
    if [ -n "$FIXTURE" ]; then
        # Hermetic test path: anchors come from the fixture, no Dolt.
        [ -f "$FIXTURE/anchors.ndjson" ] && cat "$FIXTURE/anchors.ndjson" > "$ANCHORS"
    elif [ "$REFRESH" -eq 0 ] && [ -f "$CACHE_FILE" ]; then
        ts=$(head -n1 "$CACHE_FILE" 2>/dev/null || echo 0)
        case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
        if [ "$ts" -gt 0 ] && [ $((NOW_EPOCH - ts)) -le "$CACHE_TTL" ] && [ $((NOW_EPOCH - ts)) -ge 0 ]; then
            tail -n +2 "$CACHE_FILE" > "$ANCHORS" 2>/dev/null || : > "$ANCHORS"
            gathered_from_cache=1
        fi
    fi

    if [ -z "$FIXTURE" ] && [ "$gathered_from_cache" -eq 0 ]; then
        gather_anchors    # writes $ANCHORS
        # Persist the gather under one timestamp (portable mtime).
        mkdir -p "$CACHE_DIR" 2>/dev/null || true
        if [ -d "$CACHE_DIR" ]; then
            { printf '%s\n' "$NOW_EPOCH"; cat "$ANCHORS"; } > "$CACHE_FILE.tmp.$$" 2>/dev/null \
                && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_FILE.tmp.$$" 2>/dev/null || true
        fi
    fi

    # ── Liveness join (always fresh: one cheap session-list call) ─────
    # A bead-host's session alias is pack-namespaced — <pack>.<bead-id>
    # (e.g. gc-toolkit.tk-q4xaj) — so key the map by the bead-id the alias
    # encodes: strip the leading "<pack>." segment, restricted to bead-host
    # template sessions. This mirrors gc-bead-host.sh's own reverse-
    # resolution (template ~ "bead-host"); a foreign session (the refinery,
    # a crew) is excluded and never marks an anchor live. An alias with no
    # dot is used as-is (sub leaves a non-matching string unchanged). Map
    # bead-id -> host state.
    if [ -n "$FIXTURE" ]; then
        sess_raw=$([ -f "$FIXTURE/sessions.json" ] && cat "$FIXTURE/sessions.json" || printf '{}')
    else
        sess_raw=$(gcq session list --state all --json)
    fi
    SESS_MAP=$(printf '%s' "$sess_raw" | jq -c '
        [ (.sessions // . // [])[]?
          | select((.alias // "") != "")
          | select((.template // "") | test("bead-host"))
          | {key:((.alias) | sub("^[^.]+\\.";"")),
             value:{state:(.state//""), running:(.running//false), attached:(.attached//false)}} ]
        | from_entries' 2>/dev/null || printf '{}')

    # ── Owner liveness join (child-owner state; PROBLEM 1) ────────────
    # A child bead's `assignee` is its OWNING session — the session_name a
    # polecat recorded when it claimed the bead (e.g.
    # gc-toolkit__polecat-lx-bj70b), or a routed alias. To tell whether an
    # in-progress child is actually being worked, we need its owner's session
    # state, so map EVERY session (not just bead-hosts) by BOTH its
    # session_name AND its alias -> state. The render keys off .state, never
    # .running (which is null for an active session mid-churn and would
    # false-flag a live polecat as a dead owner); an owner is dead when its
    # state is archived/closed OR it is absent from the list entirely.
    OWNER_MAP=$(printf '%s' "$sess_raw" | jq -c '
        [ (.sessions // . // [])[]?
          | (.state // "") as $st
          | [ (.session_name // empty), (.alias // empty) ][]
          | {key:., value:$st} ]
        | from_entries' 2>/dev/null || printf '{}')

    # ── Compute facts, rank, render (single jq pass) ──────────────────
    RENDER='
def sevrank: {"FLAGGED":4,"HIGH":3,"ELEVATED":2,"NORMAL":1,"LOW":0}[.];
def prio_w($p): (if $p==null then 1 else ([0, 4 - $p] | max) end);
def epoch($s): ($s | if . == null or . == "" then null
                     else (sub("\\.[0-9]+";"") | sub("Z$";"") )
                          | (try (. + "Z" | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) catch null) end);
# Is a child bead'\''s owning session alive? Keyed off .state per the witness
# orphan-liveness rule: archived/closed/absent = dead owner (an orphaned
# in-progress bead — the canonical UNKNOWN-stuck case). An empty assignee is
# treated as no live owner. Never consults .running (null during churn).
def owner_live($assignee):
    ($assignee // "") as $a
    | if $a == "" then false
      else ($ownermap[$a] // null) as $st
           | if $st == null then false
             elif ($st == "archived" or $st == "closed") then false
             else true end
      end;

[ inputs ]
| map(
    . as $a
    | ($a.children // []) as $ch
    | ($ch|length) as $m
    | ([$ch[]|select(.status=="closed")]|length) as $closed
    | (if $a.progress == null then false
       else (($a.progress.total // -1) != $m or ($a.progress.closed // -1) != $closed) end) as $pmismatch
    | [$ch[] | select(.status != "closed")] as $openset
    | ($openset|length) as $open
    | ([$ch[]|select(.status=="in_progress")]|length) as $inprog
    # in-progress work only counts as MOVING when its owner is live; an
    # in-progress child with a dead/absent owner is stuck, not active.
    | ([$ch[]|select(.status=="in_progress" and owner_live(.assignee))]|length) as $inprog_live
    | ($inprog - $inprog_live) as $inprog_dead
    | [ $ch[] | select(.status=="in_progress" and (owner_live(.assignee)|not)) | .id ] as $dead_owner_heads
    | ([$openset[]|select((.assignee // "") != "")]|length) as $assigned
    | [ $openset[] | select((.assignee // "")=="" or .status!="in_progress") | .id ] as $open_ids
    | (epoch($a.updated_at)) as $upd
    | (if $upd==null then 0 else ((($now - $upd) / 86400) | floor) end) as $stale
    | ($prefixes - [$a.prefix]) as $others
    | (if ($a.source=="decision" or $a.source=="flagged") then []
       else ( [ ($a.description // "")
                | scan("(?:" + ($others|join("|")) + ")-[a-z0-9]{3,8}") ]
              | map(select(. as $r | ($rignames | index($r)) == null and $r != $a.id))
              | unique ) end) as $xrefs
    # host liveness, joined by the bead-id the host alias encodes
    # (SESS_MAP already stripped the pack prefix, bead-host sessions only)
    | ($sessmap[$a.id] // null) as $host
    | (if $host==null then "cold"
       elif ($host.state=="active" or $host.running==true) then "hot"
       else "warm" end) as $live
    # severity band. A live host (hot/warm) is active work via a 1:1
    # resident conversation, not via in-progress child polecats — so
    # "0 in-progress" is NOT stranded when someone is home. Stranded/HIGH
    # is reserved for a decomposed anchor with open children, zero
    # in-progress, AND no live host.
    | (if $a.source=="flagged" then "FLAGGED"
       elif $a.source=="unowned" then "HIGH"
       elif $a.source=="decision" then "ELEVATED"
       elif $m==0 then "LOW"
       elif $open==0 then "LOW"
       elif ($open>0 and $inprog_live==0 and $live=="cold") then "HIGH"
       elif ($inprog_dead>0) then "ELEVATED"
       else "NORMAL" end) as $sev0
    | (if ($sev0=="NORMAL" and $stale > '"$STALE_DAYS"') then "ELEVATED" else $sev0 end) as $sev
    | ($m + prio_w($a.priority) + ([$xrefs|length, '"$XREF_CAP"'] | min)) as $weight
    # one-line frontier summary
    | (if $inprog_dead>0 then " · \($inprog_dead) stuck (dead owner)" else "" end) as $deadsfx
    | (if $a.source=="flagged" then ("flagged: " + (($a.reason // "needs a human")[0:26]))
       elif $a.source=="unowned" then "unowned convoy — no owning bead"
       elif $a.source=="decision" then "human-gated decision"
       elif $m==0 then "empty — no children"
       elif $open==0 then "all \($m) closed · 0 open"
       elif ($inprog_live==0 and $inprog_dead>0 and $live=="cold") then "\($open) open · \($inprog_dead) stuck (dead owner)"
       elif ($inprog_live==0 and $live=="hot") then ("\($open) open · in conversation" + $deadsfx)
       elif ($inprog_live==0 and $live=="warm") then ("\($open) open · host asleep" + $deadsfx)
       elif $inprog_live==0 then "\($open) open · 0 in-progress (stranded)"
       else "\($open) open · \($inprog_live) in-progress" + $deadsfx end) as $frontier
    # The LLM-authored takeaway (host or proactive), if any: the board-visible
    # headline of what this anchor concluded / what it needs. Collapse any
    # internal whitespace (a stray newline would break the table) and trim.
    | (($a.takeaway // "") | gsub("[[:space:]]+";" ") | gsub("^ | $";"")) as $takeaway
    | (if $live=="hot" then "host live" elif $live=="warm" then "host asleep" else "no host" end) as $hostnote
    # NEEDS is the one-glance answer for a human: the LLM takeaway sentence
    # when one exists, else a TERSE deterministic STATE phrase — never a
    # bead-id list. The mechanical heads/xref ids move to --json only
    # (open_heads, cross_rig_refs), so the human table stays explanatory and
    # cannot emit a raw/truncated bead-id.
    | (if ($takeaway|length) > 0 then $takeaway
       elif $a.source=="unowned" then "unowned — assign an owning bead"
       elif $a.source=="flagged" then ("open & ratify" + (if $live=="cold" then "" else " (" + $live + ")" end))
       elif $a.source=="decision" then "operator decision"
       elif $m==0 then ("no children, " + $hostnote + " — " + (if $live=="cold" then "needs an owner" else "decompose or assign" end))
       elif $open==0 then (if $a.source=="convoy" then "all \($m) closed — graduate" else "all \($m) closed — close or extend" end)
       elif ($inprog_live==0 and $inprog_dead>0 and $live=="cold") then "dead owner — recover or reassign"
       elif ($inprog_live==0 and $live=="hot") then "open to join"
       elif ($inprog_live==0 and $live=="warm") then "open to resume"
       elif $inprog_live==0 then "decomposed, idle — assign or host"
       else (if $inprog_dead>0 then "in flight — \($inprog_dead) stuck, recover"
             else ("in flight" + (if $live=="cold" then "" else " (" + $hostnote + ")" end)) end) end) as $needs
    | {
        id:$a.id, rig:$a.rig, kind:$a.kind, title:$a.title,
        severity:$sev, weight:$weight, live:$live,
        n_closed:$closed, m_total:$m, open:$open, in_progress:$inprog, assigned:$assigned,
        in_progress_live:$inprog_live, in_progress_dead:$inprog_dead, dead_owner:($inprog_dead>0),
        owned:(if ($a|has("owned")) then $a.owned else null end),
        stranded:($m>0 and $open>0 and $inprog_live==0 and $live=="cold"),
        empty:($m==0 and $a.source!="decision" and $a.source!="flagged" and $a.source!="unowned"),
        complete:($m>0 and $open==0),
        progress_mismatch:$pmismatch,
        stale_days:$stale, priority:$a.priority, cross_rig_refs:$xrefs,
        open_heads:$open_ids, dead_owner_heads:$dead_owner_heads,
        takeaway:(if ($takeaway|length)>0 then $takeaway else null end),
        takeaway_at:(($a.takeaway_at // "") | if .=="" then null else . end),
        takeaway_by:(($a.takeaway_by // "") | if .=="" then null else . end),
        reason:($a.reason // null), flagged_at:($a.flagged_at // null),
        updated_at:$a.updated_at, frontier:$frontier, needs:$needs,
        rank_score: (($sev|sevrank)*1000000 + $weight*1000 + ([$stale,999]|min))
      }
  )
| sort_by(-.rank_score)
# A bead can be matched by two gathers at once — e.g. an epic that was
# also flagged (gc.attention=1). Dedup by id, keeping the FIRST (highest-
# ranked) row, so a flagged epic shows once, in its FLAGGED band.
| reduce .[] as $r ({ids:[], out:[]};
    if (.ids | index($r.id)) then .
    else {ids:(.ids + [$r.id]), out:(.out + [$r])} end) | .out
'
    FULL=$(jq -c -n --argjson prefixes "$PREFIXES" --argjson rignames "$RIGNAMES" \
        --argjson now "$NOW_EPOCH" --argjson sessmap "$SESS_MAP" --argjson ownermap "$OWNER_MAP" \
        "$RENDER" < "$ANCHORS")
    TOTAL=$(printf '%s' "$FULL" | jq 'length')
    if [ "$EFFLIMIT" -gt 0 ]; then
        BOARD=$(printf '%s' "$FULL" | jq -c --argjson n "$EFFLIMIT" '.[0:$n]')
    else
        BOARD=$(printf '%s' "$FULL" | jq -c '.')
    fi
    SHOWN=$(printf '%s' "$BOARD" | jq 'length')

    if [ "$JSON" -eq 1 ]; then
        printf '%s\n' "$BOARD" | jq '.'
        return 0
    fi

    # ── Human-readable table ─────────────────────────────────────────
    RIGCOUNT=$(printf '%s' "$RIGS" | jq 'length')
    src="live"; [ "$gathered_from_cache" -eq 1 ] && src="cached ${CACHE_TTL}s"
    printf 'gc-zortex — cross-rig human-attention board\n'
    if [ "$SHOWN" -lt "$TOTAL" ]; then
        printf '%s · %s rigs · showing %s of %s anchors (%s)\n\n' "$NOW_ISO" "$RIGCOUNT" "$SHOWN" "$TOTAL" "$src"
    else
        printf '%s · %s rigs · %s anchors (%s)\n\n' "$NOW_ISO" "$RIGCOUNT" "$TOTAL" "$src"
    fi

    if [ "$TOTAL" -eq 0 ]; then
        printf 'No open anchors need attention. (Nothing floats.)\n'
        return 0
    fi

    printf '%s' "$BOARD" | jq -r '
def rpad($w): . as $s | ($s|tostring)[0:$w] as $t | $t + (($w - ($t|length)) as $g | if $g>0 then (" "*$g) else "" end);
def glyph: {"hot":"●","warm":"◐","cold":"·"}[.] // "·";
( (" "|rpad(2)) + ("SEV"|rpad(9)) + ("ID"|rpad(11)) + ("RIG"|rpad(13)) + ("KIND"|rpad(9)) + ("N/M"|rpad(7)) + ("FRONTIER"|rpad(36)) + "NEEDS" ),
( ("─"*1|rpad(2)) + ("─"*8|rpad(9)) + ("─"*10|rpad(11)) + ("─"*12|rpad(13)) + ("─"*8|rpad(9)) + ("─"*6|rpad(7)) + ("─"*35|rpad(36)) + ("─"*16) ),
( .[] | ((.live|glyph)|rpad(2)) + ((.severity)|rpad(9)) + ((.id)|rpad(11)) + ((.rig)|rpad(13)) + ((.kind)|rpad(9))
        + ((if (.kind=="decision" or .kind=="flagged") then "—" else "\(.n_closed)/\(.m_total)" end)|rpad(7))
        + ((.frontier)|rpad(36)) + (.needs) )
'
    printf '\nLegend: FLAGGED=hand-raised · HIGH=stranded/unowned · ELEVATED=decision/stale/stuck · NORMAL=active · LOW=empty/complete\n'
    printf 'Liveness: ● hot (open attaches) · ◐ warm (open resumes) · · cold (open materializes)\n'
    printf 'open <id> to land · flag <id> --reason to raise · clear <id> to lower · react <id> to advance a takeaway-less row. Ranking is a deterministic proxy.\n'
}

# ── Anchor gather (the cached, Dolt-heavy part) ──────────────────────
# Appends one anchor object per line to $ANCHORS. Reads only; a rig that
# errors or is empty is skipped, never aborts the board.
gather_anchors() {
    printf '%s' "$RIGS" | jq -c '.[]' | while IFS= read -r rig; do
        name=$(printf '%s' "$rig" | jq -r '.name')
        path=$(printf '%s' "$rig" | jq -r '.path')
        prefix=$(printf '%s' "$rig" | jq -r '.prefix')
        beads="$path/.beads"
        [ -d "$beads" ] || continue

        # Epics: roll up children via --parent (all statuses, so closed count is real).
        epics=$(as_array "$(gcq bd list --db "$beads" --type epic --status open --json)")
        printf '%s' "$epics" | jq -c '.[]' | while IFS= read -r epic; do
            eid=$(printf '%s' "$epic" | jq -r '.id')
            children=$(as_array "$(gcq bd list --db "$beads" --parent "$eid" --status open,in_progress,closed,blocked,deferred --json)")
            printf '%s' "$epic" | jq -c \
                --argjson ch "$children" --arg rig "$name" --arg prefix "$prefix" \
                '{id, title:(.title//""), kind:"epic", source:"epic", rig:$rig, prefix:$prefix,
                  priority:(.priority//3), updated_at:(.updated_at//""), description:(.description//""),
                  progress:null,
                  takeaway:(.metadata["gc.takeaway"] // ""),
                  takeaway_at:(.metadata["gc.takeaway_at"] // ""),
                  takeaway_by:(.metadata["gc.takeaway_by"] // ""),
                  children:[$ch[] | {id, status, assignee}]}' >> "$ANCHORS"
        done

        # Decisions: human-gated; no child roll-up needed (rank is elevated regardless).
        decisions=$(as_array "$(gcq bd list --db "$beads" --type decision --status open --json)")
        printf '%s' "$decisions" | jq -c \
            --arg rig "$name" --arg prefix "$prefix" \
            '.[] | {id, title:(.title//""), kind:"decision", source:"decision", rig:$rig, prefix:$prefix,
                    priority:(.priority//3), updated_at:(.updated_at//""), description:(.description//""),
                    progress:null, children:[],
                    takeaway:(.metadata["gc.takeaway"] // ""),
                    takeaway_at:(.metadata["gc.takeaway_at"] // ""),
                    takeaway_by:(.metadata["gc.takeaway_by"] // "")}' >> "$ANCHORS"

        # Flagged: any open/in-progress/blocked bead a host or operator raised
        # by setting the gc.attention=1 sentinel. The reason/at ride alongside.
        flagged=$(as_array "$(gcq bd list --db "$beads" --metadata-field "gc.attention=1" --status open,in_progress,blocked --json)")
        printf '%s' "$flagged" | jq -c \
            --arg rig "$name" --arg prefix "$prefix" \
            '.[] | {id, title:(.title//""), kind:"flagged", source:"flagged", rig:$rig, prefix:$prefix,
                    priority:(.priority//3), updated_at:(.updated_at//""),
                    description:(.description//""), progress:null, children:[],
                    reason:(.metadata["gc.attention_reason"] // ""),
                    flagged_at:(.metadata["gc.attention_at"] // ""),
                    takeaway:(.metadata["gc.takeaway"] // ""),
                    takeaway_at:(.metadata["gc.takeaway_at"] // ""),
                    takeaway_by:(.metadata["gc.takeaway_by"] // "")}' >> "$ANCHORS"
    done

    # Floating convoys (cross-rig). `gc convoy list` already aggregates across
    # rigs. Drop MACHINE convoys — `sling-*` AND the per-sling `input convoy
    # for …` one-child wrappers, both transient/auto — then keep the rest,
    # resolve each to its rig, and confirm it is floating (parent == null).
    # An OWNED convoy is a floating epic-improviser anchor (kind "convoy"); a
    # NON-machine convoy that is NOT owned is the orphan EXCEPTION (kind
    # "unowned") the observer SURFACES instead of dropping — under the
    # everything-is-owned law every PR/unit is owned by a bead, so an unowned
    # non-machine convoy is exactly what the observer must catch (PROBLEM 2).
    # (Old behavior `select(.owned==true)` silently hid that exception and let
    # the new `input convoy for …` machine kind through only by accident.)
    convoys=$(printf '%s' "$(gcq convoy list --json)" | jq -c '
        [ .convoys[]?
          | select((.title // "") | startswith("sling-") | not)
          | select((.title // "") | startswith("input convoy for") | not) ]' 2>/dev/null || printf '[]')
    printf '%s' "$convoys" | jq -c '.[]' | while IFS= read -r convoy; do
        cid=$(printf '%s' "$convoy" | jq -r '.id')
        cprefix=${cid%%-*}
        rig=$(rig_for_prefix "$cprefix")
        [ -n "$rig" ] || continue
        name=$(printf '%s' "$rig" | jq -r '.name')
        path=$(printf '%s' "$rig" | jq -r '.path')
        beads="$path/.beads"
        [ -d "$beads" ] || continue

        show=$(gcq bd show "$cid" --db "$beads" --include-dependents --json)
        printf '%s' "$show" | jq -e 'type=="array" and length>0' >/dev/null 2>&1 || continue
        parent=$(printf '%s' "$show" | jq -r '.[0].parent // empty')
        [ -z "$parent" ] || continue

        # owned → floating epic-improviser (kind "convoy"); unowned non-machine
        # → the orphan exception (kind "unowned"). Carry the bool so the render
        # ranks the exception HIGH instead of letting it pass as a normal row.
        owned=$(printf '%s' "$convoy" | jq -r 'if .owned==true then "true" else "false" end')
        printf '%s' "$show" | jq -c \
            --argjson cv "$convoy" --arg rig "$name" --arg prefix "$cprefix" --argjson owned "$owned" \
            '.[0] as $b
             | (if $owned then "convoy" else "unowned" end) as $kind
             | {id:$cv.id, title:($cv.title//$b.title//""), kind:$kind, source:$kind, owned:$owned,
                rig:$rig, prefix:$prefix, priority:($b.priority//3),
                updated_at:($b.updated_at//""), description:($b.description//""),
                progress:($cv.progress // null),
                takeaway:($b.metadata["gc.takeaway"] // ""),
                takeaway_at:($b.metadata["gc.takeaway_at"] // ""),
                takeaway_by:($b.metadata["gc.takeaway_by"] // ""),
                children:[($b.dependents // [])[] | {id, status, assignee}]}' >> "$ANCHORS"
    done
}

# ── Dispatch ─────────────────────────────────────────────────────────
case "${1:-}" in
    open)          shift; cmd_open "$@" ;;
    flag)          shift; cmd_flag "$@" ;;
    clear|unflag)  shift; cmd_clear "$@" ;;
    react)         shift; cmd_react "$@" ;;
    takeaway)      shift; cmd_takeaway "$@" ;;
    board)         shift; cmd_board "$@" ;;
    -h|--help|help) usage; exit 0 ;;
    ''|-*)         cmd_board "$@" ;;          # no verb, or a board flag → board (back-compat)
    *)             echo "$PROG: unknown verb '$1' (try: board, open, flag, clear, react, takeaway, help)" >&2; usage; exit 2 ;;
esac
