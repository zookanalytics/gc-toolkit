#!/bin/sh
# gc-helm.sh — the cross-rig human-attention board plus the pick-a-row
# verb that files a visit on a bead. The operator reaches it
# via the prefix+b tmux board picker (tmux-pick-helm.sh) or by running
# this script directly; it is NOT a registered gc subcommand. Pack commands
# bind under the pack name (`gc <pack> <cmd>`), so there is no top-level
# helm command — invoke this script (or the picker), not `gc`.
#
# Usage:
#   gc-helm [board] [--json] [--limit=N] [--timeout=SECONDS] [--refresh]
#   gc-helm open  <bead-id> [--reason "..."] [--body "..."]  file a visit on the bead (converse holds it)
#   gc-helm takeaway <bead-id> "<text>" [--by …] [--release]  set the board-visible takeaway headline
#
#   board → the operator glances the ranked rows (with a held glyph,
#           a row cap, and a cache so the ~12s gather is paid once,
#           not every glance).
#   open  → pick a row; a VISIT is filed on the bead — a small child
#           bead in the subject's continuation group, routed to the
#           rig-qualified converse pool (the canonical gate-visit
#           lines, formulas/mol-visit.toml). Pool demand spawns a
#           converse session that rebuilds the subject's slice and
#           holds for the operator (cold), or the live group session
#           vacuums the visit (warm). One open visit per subject: if
#           one already exists, open prints its id instead of filing
#           a second. The SUBJECT MUST RESOLVE first — an id that no
#           rig ledger answers for exits 4 having filed nothing, so a
#           typo cannot manufacture a visit (and a converse session to
#           hold it) for a bead that does not exist.
#
# ── What is an anchor ────────────────────────────────────────────────
# FOUR kinds of OPEN top-level anchors are collected, cross-rig:
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
#                      carry no frontier (N/M = —).
#   • open/in-progress/assigned — counts over the open frontier.
#   • stranded       — decomposed (M>0) with open children, ZERO LIVE
#                      in-progress, AND no open visit: work exists but
#                      nothing is moving. An open visit counts as moving —
#                      the bead is worked via its held conversation,
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
#   • held           — visit presence: TRUE when an OPEN visit bead
#                      (task_kind=visit) carries this anchor's id in
#                      gc.continuation_group — a conversation about the
#                      anchor exists (a converse session holds it, or
#                      pool demand is about to spawn one). The glance
#                      answers "is a conversation open?" before you pick
#                      the row. A held anchor also stays out of the
#                      stranded/HIGH band.
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
#   HIGH      stranded frontier (decomposed, open, no LIVE in-progress, and
#             no open visit — incl. a frontier whose only in-progress
#             children have dead owners), OR an unowned non-machine convoy
#             (the orphan exception).
#   ELEVATED  a `decision` (human-gated); an otherwise-NORMAL anchor gone
#             stale (> STALE_DAYS days); OR a still-moving anchor that has a
#             dead-owner (stuck) in-progress child to recover.
#   NORMAL    active frontier (has LIVE in-progress work, OR an open visit —
#             a conversation is held).
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
# (one-line summary), `needs` (short hint), and `held` (visit presence).
# `--json` is the stable contract for downstream tooling (the tmux
# board picker reads it). There is no `live` (hot/warm/cold) host
# field — the visit/converse spine is the only conversation
# mechanism, and `held` is its one glyph fact.
#
# ── Row cap & cache (the board must scale) ───────────────────────────
# The gather hits every rig's Dolt and costs ~seconds; the visit gather
# rides in the same pass. So the EXPENSIVE GATHER (anchors + visits) is
# cached (default TTL GC_HELM_CACHE_TTL=45s) while ranking is recomputed
# every glance — a glance is sub-second on a warm cache, and both paths
# that change visit presence here (`open` files one; `takeaway` parks)
# bust the cache. `--refresh` (or `open`,
# which busts the cache) forces a fresh gather. Rows are
# CAPPED at GC_HELM_MAX_ROWS (default 50) by default so the board
# can never balloon to "every bead"; `--limit=N` overrides with an
# explicit N, and `--limit=0` means ALL (uncapped) for tooling.
#
# Exit codes:
#   0   board rendered / verb succeeded
#   2   usage error
#   3   missing dependency (jq / gc), could not enumerate rigs, or the
#       gather failed (nothing cached — a transient gather failure must
#       never be served as a "0 anchors" all-clear)
#   4   verb runtime failure (e.g. bead not found, visit filing failed)
#
# Test hook: GC_HELM_FIXTURE=<dir> — when set, the board reads
# canned data instead of Dolt/sessions: <dir>/anchors.ndjson (one anchor
# object per line, the gathered shape), <dir>/visits.json (a JSON array
# of subject ids with an open visit), and <dir>/sessions.json (the
# `gc session list --json` shape, for the child-owner liveness map).
# Keeps the render/rank/glyph assertions hermetic. Unset in normal use.

set -eu

PROG="gc-helm"

# ── Tunables ─────────────────────────────────────────────────────────
STALE_DAYS=14                                   # > this many days since update → staleness bump
XREF_CAP=5                                       # max cross-rig refs that count toward weight
MAX_ROWS="${GC_HELM_MAX_ROWS:-50}"          # default row cap (--limit=0 disables)
CACHE_TTL="${GC_HELM_CACHE_TTL:-45}"        # seconds the gather cache stays fresh
FIXTURE="${GC_HELM_FIXTURE:-}"              # test hook (see header)
# Fall back to defaults on a non-numeric override so `set -e` arithmetic
# (the cap + cache-age tests) can't crash the board on a bad env value.
case "$MAX_ROWS"  in ''|*[!0-9]*) MAX_ROWS=50 ;; esac
case "$CACHE_TTL" in ''|*[!0-9]*) CACHE_TTL=45 ;; esac

usage() {
    cat >&2 <<'EOF'
Usage:
  gc-helm [board] [--json] [--limit=N] [--timeout=SECONDS] [--refresh]
  gc-helm open  <bead-id> [--reason "..."] [--body "..."]  file a visit on the bead (a converse session holds the conversation)
  gc-helm react <bead-id> [--reason "..."]  sling a first reaction (self-heals a takeaway-less row)
  gc-helm takeaway <bead-id> "<text>" [--by host|proactive|converse] [--release]  set the board-visible takeaway headline

The board (default verb) is a read-only cross-rig ranking of OPEN anchors
(epics, floating owned convoys, and decisions) by how much
they need a human's attention. open files a visit in the picked bead's
continuation group (pool demand spawns/vacuums a converse session —
attach via the sessions picker); react slings a proactive first
reaction (via tools/gc-proactive.sh, on the codex-gated mr path) so a
takeaway-less row self-heals to an explanatory NEEDS on the next render.
The two --reason flags differ: open's REPLACES what the visit says it is
for — --reason is the short title tail and --body the brief the converse
session reads at claim time (default: the board-pick wording) — while
react's is log-only operator intent.
takeaway writes that NEEDS headline directly — the thin writer the host, the
proactive worker, and the converse role call to stamp gc.takeaway (+_at/+_by)
in one update; with --release it also reopens/unassigns/clears the route and
marks the proactive reaction in that same write (the proactive worker's
one-call close). converse calls it WITHOUT --release, twice per sitting: once
when the hold begins and once at sign-off, so a reaped thread still leaves a
dated trace of what it was waiting for (tk-bzm86).

  --json             Emit the ranked board as a JSON array (stable contract).
  --limit=N          Show only the top N rows (0 = all/uncapped; default caps at 50).
  --timeout=SECONDS  Per-query timeout bound for Dolt reads (default 10).
  --refresh          Bypass the gather cache and re-query every rig now.
  -h, --help         This help.
EOF
}

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 3; }
command -v gc >/dev/null 2>&1 || { echo "$PROG: gc is required" >&2; exit 3; }

# ── Portable timeout ─────────────────────────────────────────────────
# GNU `timeout` does not exist on stock macOS, and Homebrew coreutils
# ships it as `gtimeout`. Resolve once at startup, then route EVERY
# bounded query through with_timeout: `timeout` if present, else
# `gtimeout`, else run the command with NO bound — degraded (a wedged
# Dolt can stall a glance) but working beats a board that is dead on
# the host. Never call `timeout` directly below.
if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN=gtimeout
else TIMEOUT_BIN=""
fi
# with_timeout <seconds> <cmd> [arg…]
with_timeout() {
    _wt_secs="$1"; shift
    if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$_wt_secs" "$@"; else "$@"; fi
}

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Resolve sibling tools regardless of where the pack is materialized:
# assets/scripts/ and tools/ are siblings under the pack root.
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROACTIVE_TOOL="${GC_PROACTIVE_TOOL:-$SCRIPT_DIR/../../tools/gc-proactive.sh}"

# ── Cache location ───────────────────────────────────────────────────
# Keyed by city path so distinct cities don't collide. Cache format:
# line 1 = gather epoch, line 2 = the visit map (one JSON array of
# subject ids with an open visit), lines 3.. = anchors ndjson (portable:
# no stat(1) / find(1) mtime flags, which differ GNU vs BSD). The file
# name carries the format ("board-"), so a stale v1 "anchors-" cache is
# simply never read.
CACHE_DIR="${TMPDIR:-/tmp}/gc-helm-cache.$(id -u 2>/dev/null || echo 0)"
_city_key=$(printf '%s' "${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-default}}}" | cksum | cut -d' ' -f1)
CACHE_FILE="$CACHE_DIR/board-$_city_key.ndjson"

bust_cache() { rm -f "$CACHE_FILE" 2>/dev/null || true; }

# ── Rig enumeration (shared by board + verb rig resolution) ───────────
# Sets RIGS (JSON array of {name,path,prefix}). Exits 3 if none.
RIGS=""
# Count of rigs in $RIGS, hardened: jq emits NOTHING (exit 0) on empty
# input, so testing its raw output with `[ … -eq 0 ]` compares an EMPTY
# string and throws (`[: : integer expression expected`) instead of taking
# the clean exit-3 path — normalize any non-numeric count to 0.
rigs_count() {
    _rc=$(printf '%s' "$RIGS" | jq 'length' 2>/dev/null || echo 0)
    case "$_rc" in ''|*[!0-9]*) _rc=0 ;; esac
    printf '%s' "$_rc"
}
enumerate_rigs() {
    [ -n "$RIGS" ] && return 0
    if [ -n "$FIXTURE" ] && [ -f "$FIXTURE/rigs.json" ]; then
        RIGS=$(jq -c '.' < "$FIXTURE/rigs.json" 2>/dev/null || printf '[]')
        [ "$(rigs_count)" -gt 0 ] && return 0
    fi
    # TIMEOUT is set ONLY by cmd_board's flag parser, so on the one-shot verbs
    # (open/react/takeaway) this falls through to the tunable below. That is
    # deliberate: 10s is a BOARD-RENDER budget — the board fires many queries
    # and would rather show a thin row than stall — but a one-shot operator
    # command that exits 3 having filed nothing is the wrong trade for the same
    # slow answer. Measured 2.6-8.4s for `gc rig list` in a loaded city
    # (2026-08-14), i.e. the old bound was marginal, and the failure it caused
    # is worst for gc-visit-open.sh's topic path: the subject bead is already
    # created by then, so a timeout here strands it visit-less.
    rigs_raw=$(with_timeout "${TIMEOUT:-${GC_HELM_RIG_TIMEOUT:-30}}" gc rig list --json 2>/dev/null || true)
    RIGS=$(printf '%s' "$rigs_raw" | jq -c '[.rigs[]? | {name, path, prefix}]' 2>/dev/null || printf '[]')
    if [ "$(rigs_count)" -eq 0 ]; then
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

# ── Release helper: quiesce a parked molecule's step beads ───────────
# `takeaway --release` parks a work bead — which is the ANCHOR of a
# mol-polecat-work molecule. The release bundle (in cmd_takeaway below) clears
# the ANCHOR's own route, but the molecule's STEP beads keep their own pins:
# gc.routed_to (the pool-offer lever), an assignee (the assigned-work hand-back
# lever), and gc.session_affinity=require. Any of these re-attracts a fresh
# polecat onto the parked husk, where it re-derives "nothing to do" and drains —
# one burned session per scale_check tick (tk-xypcy). The witness has been
# clearing these by hand; this folds that cleanup into the park itself. (Sibling
# tk-p9ji9 handles the completed-but-not-parked shape from the witness patrol:
# same reverse walk, different trigger, no terminal-state gate here because the
# operator's park IS the "this workflow is done" signal.)
#
# The anchor carries no pointer to its molecule, so we discover the linkage the
# way the formula resolves an anchor, walked in reverse: enumerate the live
# graph.v2 STEP beads (any formula — selected by contract, see the row filter),
# group by gc.root_bead_id, resolve each root's anchor (root ->
# gc.input_convoy_id -> the convoy's single tracked member), and quiesce ONLY
# the steps whose root resolves to THIS parked anchor.
#
# Guards (mirroring the sibling quiesce pass):
#   * FAIL CLOSED — a root whose anchor is unresolved, or resolves to a
#     different bead, is skipped untouched (never drain another, possibly-live,
#     molecule's steps out from under a running polecat).
#   * NEVER close a step or rewrite its status. Closing load-context unblocks
#     workspace-setup and walks a polecat forward onto an already green-gated,
#     PR'd branch; any push there stales the anchor's check.<gate> marker and
#     blocks the PR. There is deliberately no close/status-write path here.
#   * NEVER de-route the workflow-finalize step — its control-dispatcher route
#     is the molecule's only finalize path.
#   * All present re-attracting keys cleared in ONE update per step: a split
#     update would briefly leave the step open+unassigned+routed (the exact
#     pool-offer shape), racing a fresh polecat into the husk.
#
# ONE GUARD DELIBERATELY DOES NOT MIRROR THE SIBLING (tk-7g37t). That pass grew an
# arm for a root whose ROW IS ABSENT from the store: it quiesces such a molecule
# instead of skipping it, because a molecule that cannot be finalized by anything
# is dead by construction. That arm CANNOT be ported here, and the reason is
# structural rather than a matter of caution.
#
# The two functions ask different questions of the same resolution walk. The
# sibling asks a VERDICT — "is this molecule DONE?" — and an absent root answers
# it: dead, by construction. This one asks a MATCH — "does this molecule belong to
# the bead being parked?" — and an absent root leaves that unanswerable, not
# answered-yes. Step beads carry `gc.root_bead_id` and nothing else pointing
# upward: no convoy id, no anchor id (verified against the live husks of root
# tk-wea42). With the root row gone there is NO path from a step to its anchor, so
# an orphaned husk cannot be attributed to the parked bead — or to any other.
#
# Quiescing it anyway would silently widen `takeaway --release` from "clean up the
# molecule of the bead I just parked" into "sweep every orphaned husk in the rig",
# mutating husks of beads the operator never named and logging them under the one
# they did. That sweep already has an owner: quiesce-completed-workflows.sh runs on
# the witness patrol and retires absent-root husks there, so an orphan this
# function passes over is retired within a cycle rather than left forever. The
# in-scope case degrades the same way — a park whose OWN molecule lost its root
# quiesces nothing here and waits for the patrol — which is the honest bound on
# what an anchor-matched cleanup can do.
#
# The body is a subshell (`() ( … )`) with `set +e`, so it stays best-effort:
# no tool failure here can abort the park (the caller runs under `set -e`), and
# the `_`-locals never leak. $1 = parked anchor bead id. $2 = rig .beads db path
# (may be empty -> ambient BEADS_DIR).
# >>> quiesce-release-molecule-steps
quiesce_release_molecule_steps() (
    set +e
    _anchor="$1"; _db="$2"

    # shellcheck disable=SC2086  # ${_db:+--db "$_db"} expands to 0 or 2 space-free fields
    _steps=$(gc bd list --status=open,in_progress ${_db:+--db "$_db"} --json --limit=0 2>/dev/null || true)
    [ -n "$_steps" ] && [ "$_steps" != "[]" ] || exit 0

    # One compact JSON row per live graph.v2 step bead.
    #
    # SELECTED BY CONTRACT, NOT BY FORMULA NAME (tk-q5r65) — the same widening as
    # the sibling pass, and load-bearing for the same reason: the old
    # `startswith("mol-polecat-work.")` dropped every other graph.v2 formula's
    # steps here, before the anchor match below could have any say, so a park on
    # a mol-scoped-work anchor quiesced nothing and its husk kept burning
    # polecats. Widening hands the anchor match more candidates to refuse and
    # removes no guard: the `_ranchor = _anchor` test below is the fail-closed
    # gate, and a non-graph.v2 bead carries no `gc.step_ref` to be selected by.
    # The root requirement is belt-and-braces (as in the sibling pass): a step
    # without one is already excluded by the `_roots` reduction and could never
    # match the parked anchor anyway. It is stated here so the row set means
    # exactly "a graph.v2 step that could be anchor-matched", now that the
    # formula name no longer carries that rule.
    _rows=$(printf '%s' "$_steps" | jq -c '
        .[]
        | select((.metadata["gc.step_ref"] // "") != "")
        | select((.metadata["gc.root_bead_id"] // "") != "")
        | { id,
            step:     (.metadata["gc.step_ref"] // ""),
            root:     (.metadata["gc.root_bead_id"] // ""),
            routed:   (.metadata["gc.routed_to"] // ""),
            assignee: (.assignee // ""),
            affinity: (.metadata["gc.session_affinity"] // "") }' 2>/dev/null || true)
    [ -n "$_rows" ] || exit 0

    _roots=$(printf '%s\n' "$_rows" | jq -r -s 'map(.root) | map(select(. != "")) | unique | .[]' 2>/dev/null || true)
    [ -n "$_roots" ] || exit 0

    printf '%s\n' "$_roots" | while IFS= read -r _root; do
        [ -n "$_root" ] || continue

        # Resolve this root's anchor: root -> input convoy -> its single member.
        # An empty read here covers both a failed read and an ABSENT root row; the
        # header explains why this function skips the latter where the sibling pass
        # quiesces it (attribution to the parked bead is impossible without the
        # root, so the patrol pass owns those).
        _convoy=$(gc bd show "$_root" ${_db:+--db "$_db"} --json 2>/dev/null \
            | jq -r '.[0].metadata["gc.input_convoy_id"] // empty' 2>/dev/null || true)
        [ -n "$_convoy" ] || continue
        _ranchor=$(gc convoy status "$_convoy" --json 2>/dev/null \
            | jq -r 'if ((.children // []) | length) == 1 then (.children[0].id // empty) else empty end' 2>/dev/null || true)

        # FAIL CLOSED: act only on the molecule whose anchor IS the parked bead.
        [ -n "$_ranchor" ] && [ "$_ranchor" = "$_anchor" ] || continue

        printf '%s\n' "$_rows" | jq -c --arg r "$_root" 'select(.root == $r)' 2>/dev/null | while IFS= read -r _row; do
            [ -n "$_row" ] || continue
            _sid=$(printf '%s'      "$_row" | jq -r '.id // empty' 2>/dev/null || true)
            _step=$(printf '%s'     "$_row" | jq -r '.step // empty' 2>/dev/null || true)
            _routed=$(printf '%s'   "$_row" | jq -r '.routed // empty' 2>/dev/null || true)
            _who=$(printf '%s'      "$_row" | jq -r '.assignee // empty' 2>/dev/null || true)
            _affinity=$(printf '%s' "$_row" | jq -r '.affinity // empty' 2>/dev/null || true)
            [ -n "$_sid" ] || continue

            # Never de-route the finalize step (control-dispatcher escape path);
            # guard by step id AND by route in case one is renamed.
            case "$_step" in *.workflow-finalize) continue ;; esac
            case "$_routed" in *control-dispatcher*) continue ;; esac

            # Idempotent: already quiet -> nothing left to clear.
            [ -n "$_routed" ] || [ -n "$_who" ] || [ -n "$_affinity" ] || continue

            # Only the keys actually present are touched, all in ONE update.
            set --
            [ -n "$_routed" ]   && set -- "$@" --unset-metadata gc.routed_to
            [ -n "$_who" ]      && set -- "$@" --assignee ""
            [ -n "$_affinity" ] && set -- "$@" --unset-metadata gc.session_affinity
            # shellcheck disable=SC2086  # ${_db:+--db "$_db"} expands to 0 or 2 fields
            if gc bd update "$_sid" ${_db:+--db "$_db"} "$@" >/dev/null 2>&1; then
                echo "$PROG: takeaway: quiesced husk step $_sid ($_step) of parked $_anchor"
            else
                echo "$PROG: takeaway: could not quiesce step $_sid (retries via witness patrol)" >&2
            fi
        done
    done
    exit 0
)
# <<< quiesce-release-molecule-steps

# ── Verb: takeaway ───────────────────────────────────────────────────
# Write the board-visible takeaway headline — the thin writer a converse
# session and the proactive worker call instead of inlining the `gc bd update
# --set-metadata gc.takeaway=… gc.takeaway_at=… gc.takeaway_by=…` triple.
# Resolve the bead's rig db, stamp the three fields in ONE
# update, then bust the cache so the next board glance reflects the new
# headline (an improvement over the old inline form, which never busted it).
#
# --release folds the proactive reaction-release into the SAME update: alongside
# the takeaway stamp it ALSO marks the reaction + reopens + unassigns + clears
# the route (gc.proactive_reaction=1, --status=open, empty --assignee, empty
# gc.routed_to) in one Dolt write. The proactive worker / mol-first-reaction
# call `takeaway … --release` as their single closing step, replacing a takeaway
# stamp followed by a separate release `gc bd update`.
#
# That empty `--assignee` also clears any assigned-work wake reason, so
# `release` is the operator-facing "done with this bead" path: nothing keeps
# re-attracting a session onto the parked bead afterwards.
#
# When the released bead is the ANCHOR of a mol-polecat-work molecule, --release
# ALSO quiesces that molecule's step beads (quiesce_release_molecule_steps,
# above) so the park doesn't leave affine/routed steps that re-spawn a polecat
# onto the parked husk (tk-xypcy).
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

    # Provenance: host (default) or proactive; free-form.
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
    # On --release the anchor's own route was cleared above, but if this bead is
    # the anchor of a mol-polecat-work molecule its STEP beads keep their own
    # re-attracting pins (gc.routed_to / assignee / gc.session_affinity) and
    # would re-spawn a polecat onto the parked husk. Quiesce them in the same
    # park (tk-xypcy). Best-effort by construction — never fails the park.
    if [ -n "$release" ]; then
        quiesce_release_molecule_steps "$bead" "$db"
    fi
    echo "takeaway set on $bead (by $by)${release:+ [released]}: $text"
}

# ── Verb: open ───────────────────────────────────────────────────────
# The pick-a-row verb. Files a VISIT on the picked bead — the one
# conversation mechanism (specs/tk-h9pq5): a small child bead in the
# subject's continuation group, routed to the rig-qualified converse
# pool via the canonical gate-visit lines (formulas/mol-visit.toml).
# Pool demand spawns a converse session that rebuilds the subject's
# slice and holds for the operator (cold), or the live group session
# vacuums the visit (warm). One open visit per subject: if one already
# exists, print its id and the attach hint instead of filing a second.
# Opening busts the cache so the next board render shows the held glyph.
#
# `--reason <short>` and `--body <text>` override what the visit SAYS it is
# for. The default wording ("operator pick from the board") is true of the
# board picker and false of every other caller, and the visit body is not
# decoration: it is written at filing time and read at CLAIM time, often a day
# later, as the converse session's only statement of what the sitting is about
# (docs/gascity-human-engagement.md → "A visit body is written at FILING time
# and read at CLAIM time"). So a second front door reusing this verb — the
# operator-origin topic intake in assets/scripts/gc-visit-open.sh — passes its
# own blurb rather than filing a visit that misreports its own origin. Callers
# reuse the verb instead of copying the gate-visit block, which is why the
# override lives here and not in a second copy of the block.
#
# They are two knobs because the default is two: a SHORT title tail the
# operator scans in a list, and a LONGER brief the converse session reads. One
# flag driving both would either bloat every title or starve every brief.
cmd_open() {
    bead=""; open_reason=""; open_body=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason=*) open_reason="${1#--reason=}"; shift ;;
            --reason)   shift; [ $# -gt 0 ] || { echo "$PROG: open: --reason requires a value" >&2; exit 2; }
                        open_reason="$1"; shift ;;
            --body=*)   open_body="${1#--body=}"; shift ;;
            --body)     shift; [ $# -gt 0 ] || { echo "$PROG: open: --body requires a value" >&2; exit 2; }
                        open_body="$1"; shift ;;
            -h|--help)  usage; exit 0 ;;
            -*) echo "$PROG: open: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: open takes one bead-id" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done
    case "$bead" in "") echo "$PROG: open needs <bead-id>" >&2; usage; exit 2 ;; esac

    # Point bd at the bead's rig so the visit lands in the right per-rig
    # ledger even cross-rig (BEADS_DIR pins bd), and export the bead's
    # rig as GC_RIG so the gate-visit POOL line rig-qualifies the
    # converse pool (the exact-match read side needs the qualified name —
    # docs/gascity-routing-model.md). The bead's rig is authoritative,
    # so it overrides any ambient GC_RIG.
    path=$(rig_path_for_bead "$bead")
    [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"
    rig=$(rig_name_for_bead "$bead")
    [ -n "$rig" ] && export GC_RIG="$rig"

    # ── The subject must actually EXIST before anything is filed ──────
    # The rig resolution above maps the id PREFIX to a rig; nothing so far
    # confirms a bead by that id RESOLVES anywhere. So without this gate a
    # typo or a stale id files a REAL visit: routed to the rig converse
    # pool, carrying gc.continuation_group=<the typo>.
    # Pool demand then spawns a converse session whose prime step
    # (`gc bd show $SUBJECT`) can never resolve anything, and it holds a
    # conversation about a bead that does not exist. This is the operator
    # front door for the visit spine, so a fat-fingered id must fail here
    # rather than silently manufacture junk work and an agent to hold it.
    #
    # Fail CLOSED on every unhappy reading — not found, an unparseable
    # answer, a wedged data plane — because the only alternative is filing
    # a visit on an unverified subject, which is the bug itself. The three
    # readings get distinct messages: they need different operator moves
    # (fix the id / add the rig / check Dolt), and "bead not found" for a
    # Dolt outage would send the operator hunting a typo that isn't there.
    #
    # Exit 4 = verb runtime failure, the documented code for bead-not-found
    # (see "Exit codes" in the header).
    # >>> open-subject-exists
    subject_raw=$(gc bd show "$bead" --json 2>/dev/null || true)
    # `bd show` answers an ARRAY of beads when it resolves and a bare
    # `{"error": …}` OBJECT when it does not, so the shape is checked before
    # indexing: `.[]?` over that object iterates its VALUES (strings), and
    # `.id` on a string is a jq error, not a clean empty. Control chars in a
    # bead's notes break the parse outright, hence the `tr -d` (an invalid
    # `bd show --json` must not read as "missing"). The id is compared for
    # EQUALITY with what was typed: the visit is keyed by that literal
    # string (gc.continuation_group, the tracks edge), so a near-miss that
    # resolves to some other bead would file a visit nothing can resolve.
    #
    # Deliberately UNPINNED — do not "fix" this by threading `--db` in from
    # the prefix-resolved rig. `gc bd show <id>` resolves a bead by id across
    # the city's per-rig ledgers regardless of BEADS_DIR (verified against a
    # cross-rig subject with BEADS_DIR unset, and pointed at two different
    # wrong rigs). Pinning `--db` by PREFIX would instead make the existence
    # check inherit the prefix→rig assumption, turning any bead whose id
    # prefix does not match its home ledger into a false "bead not found" —
    # a real subject refused at the front door, which is worse than the bug
    # this gate closes. Verification must be at least as permissive as the
    # thing it guards.
    subject_clean=$(printf '%s' "$subject_raw" | tr -d '\000-\010\013\014\016-\037')
    subject=$(printf '%s' "$subject_clean" \
        | jq -r --arg b "$bead" \
            'if type == "array"
             then [ .[] | select(type == "object" and (.id // "") == $b) ] | first | (.id // empty)
             else empty end' 2>/dev/null || true)
    if [ -z "$subject" ]; then
        # Which unhappy reading is this? A NOT-FOUND answer is the specific
        # `{"error": "no issues found matching the provided IDs"}`; any OTHER
        # error on that channel (a refused Dolt connection, a schema-migration
        # write-block, an auth failure) means the read FAILED and the bead's
        # existence is simply unknown. Both file nothing, but they need
        # different operator moves, and reporting an outage as "bead not found"
        # sends the operator hunting a typo that is not there. Unrecognized
        # errors fall to "could not verify" on purpose: over-reporting doubt is
        # recoverable, asserting a bead is missing when it is not is not.
        probe_err=$(printf '%s' "$subject_clean" \
            | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null || true)
        case "$probe_err" in *"no issues found"*) probe_err="" ;; esac
        if [ -z "$rig" ]; then
            echo "$PROG: open: bead not found: '$bead' — its id prefix '${bead%%-*}' matches no rig in 'gc rig list'. No visit filed." >&2
        elif [ -z "$subject_raw" ] || [ -n "$probe_err" ]; then
            echo "$PROG: open: could not verify '$bead' — 'gc bd show' did not answer${probe_err:+ ($probe_err)} (data plane down?). No visit filed." >&2
        else
            echo "$PROG: open: bead not found: '$bead' — no rig ledger answers for that id. No visit filed." >&2
        fi
        exit 4
    fi
    # <<< open-subject-exists

    # Already held? An open visit in this bead's continuation group IS
    # the conversation — filing a second would split it. Print the
    # existing visit and the same attach hint instead.
    existing=$(gc bd list --status=open,in_progress --json --limit=0 2>/dev/null \
        | jq -r --arg s "$bead" \
            '[ .[]? | select((.metadata.task_kind // "") == "visit"
                            and (.metadata["gc.continuation_group"] // "") == $s)
               | .id ] | first // empty' 2>/dev/null || true)
    if [ -n "$existing" ]; then
        echo "$PROG: visit $existing is already open for $bead — a converse session holds it (or will spawn/vacuum it)."
        echo "       Attach via the sessions picker."
        return 0
    fi

    # What this sitting is FOR, in the caller's words (see --reason/--body
    # above). Both strings are resolved here, outside the marked block, so the
    # block itself stays a verbatim copy of the canonical form. A caller that
    # supplies only --reason gets it in both places rather than a stock body
    # contradicting a custom title.
    visit_tail="${open_reason:-operator pick from the board}"
    if [ -n "$open_body" ]; then
        visit_body="$open_body"
    elif [ -n "$open_reason" ]; then
        visit_body="$open_reason"
    else
        visit_body="Operator picked $bead off the helm board: rebuild the subject's slice, prep, hold for the operator."
    fi

    # File the visit — the canonical gate-visit lines (formulas/mol-visit.toml).
    # >>> gate-visit
    POOL="${GC_RIG:+$GC_RIG/}gc-toolkit.converse"
    VISIT=$(gc bd create -t task --title "visit: $bead — $visit_tail" \
        -d "$visit_body" \
        --json | jq -r '.id // .[0].id')
    [ -n "$VISIT" ] && [ "$VISIT" != "null" ] \
        || { echo "$PROG: open: could not create a visit bead for '$bead' (does it exist?)" >&2; exit 4; }
    gc bd update "$VISIT" --set-metadata "gc.routed_to=$POOL" \
        --set-metadata "gc.continuation_group=$bead" \
        --set-metadata "task_kind=visit"
    # --type=tracks, NOT parent-child: parent-child transmits the subject's blocked state to the visit, making it unclaimable
    gc bd dep add "$VISIT" "$bead" --type=tracks
    # <<< gate-visit
    bust_cache

    echo "$PROG: visit $VISIT filed on $bead (pool $POOL) — a converse session will spawn (cold) or vacuum it (warm)."
    echo "       Attach via the sessions picker."
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
    # right per-rig ledger even cross-rig (parity with open).
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
    VISITS_FILE="$TMP/visits.json"
    printf '[]\n' > "$VISITS_FILE"
    # Gather-failure marker. The gather loops run in pipeline
    # subshells, so a shell variable cannot carry "a query died" back up —
    # a marker FILE can. Any line in it means the gather is NOT trusted:
    # never cached, never rendered as a (false) quiet board.
    GATHER_ERR="$TMP/gather-failed"

    NOW_EPOCH=$(date -u +%s)
    NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Bounded gc wrapper: never let a slow/wedged Dolt query abort the board.
    gcq() { with_timeout "$TIMEOUT" gc "$@" 2>/dev/null || true; }
    as_array() {
        if printf '%s' "$1" | jq -e 'type=="array"' >/dev/null 2>&1; then printf '%s' "$1"; else printf '[]'; fi
    }
    # gather_mark <what>: record that a gather query came back empty/invalid
    # (the timeout/wedge/error shape) — see GATHER_ERR above.
    gather_mark() { printf '%s\n' "$1" >> "$GATHER_ERR" 2>/dev/null || true; }

    enumerate_rigs
    PREFIXES=$(printf '%s' "$RIGS" | jq -c '[.[].prefix]')
    RIGNAMES=$(printf '%s' "$RIGS" | jq -c '[.[].name]')
    rig_for_prefix() { printf '%s' "$RIGS" | jq -c --arg p "$1" '.[] | select(.prefix==$p)' 2>/dev/null | head -n1; }

    # ── Gather (cached: the expensive part) ──────────────────────────
    gathered_from_cache=0
    if [ -n "$FIXTURE" ]; then
        # Hermetic test path: anchors + visits come from the fixture, no Dolt.
        [ -f "$FIXTURE/anchors.ndjson" ] && cat "$FIXTURE/anchors.ndjson" > "$ANCHORS"
        [ -f "$FIXTURE/visits.json" ] && cat "$FIXTURE/visits.json" > "$VISITS_FILE"
    elif [ "$REFRESH" -eq 0 ] && [ -f "$CACHE_FILE" ]; then
        ts=$(head -n1 "$CACHE_FILE" 2>/dev/null || echo 0)
        case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
        if [ "$ts" -gt 0 ] && [ $((NOW_EPOCH - ts)) -le "$CACHE_TTL" ] && [ $((NOW_EPOCH - ts)) -ge 0 ]; then
            sed -n '2p' "$CACHE_FILE" > "$VISITS_FILE" 2>/dev/null || printf '[]\n' > "$VISITS_FILE"
            tail -n +3 "$CACHE_FILE" > "$ANCHORS" 2>/dev/null || : > "$ANCHORS"
            gathered_from_cache=1
        fi
    fi

    if [ -z "$FIXTURE" ] && [ "$gathered_from_cache" -eq 0 ]; then
        gather_anchors    # writes $ANCHORS
        gather_visits     # writes $VISITS_FILE (one JSON array line)
        # A failed gather is an ERROR, not an empty board. Caching it
        # would serve a false "0 anchors" all-clear for the whole TTL — on the
        # one surface whose job is to tell a human whether anything needs
        # them. Print an explicit line (distinct from the legitimate quiet-
        # board message), cache NOTHING, and exit 3.
        if [ -s "$GATHER_ERR" ]; then
            echo "$PROG: gather failed ($(sort -u "$GATHER_ERR" | head -n 5 | tr '\n' ' ' | sed 's/ $//')) — board not rendered, nothing cached; retry with --refresh or check gc/Dolt" >&2
            exit 3
        fi
        # Persist the gather under one timestamp (portable mtime).
        mkdir -p "$CACHE_DIR" 2>/dev/null || true
        if [ -d "$CACHE_DIR" ]; then
            { printf '%s\n' "$NOW_EPOCH"; cat "$VISITS_FILE"; cat "$ANCHORS"; } > "$CACHE_FILE.tmp.$$" 2>/dev/null \
                && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_FILE.tmp.$$" 2>/dev/null || true
        fi
    fi

    # ── Visit map (held glyph): subject ids with an open visit ────────
    # An anchor is HELD when an open visit bead (task_kind=visit) names
    # it in gc.continuation_group — the conversation exists (a converse
    # session holds it, or pool demand is about to spawn one). Gathered
    # with the anchors (gather_visits) and cached alongside them; both
    # verbs that change visit presence bust the cache.
    VISITS=$(cat "$VISITS_FILE" 2>/dev/null || printf '[]')
    printf '%s' "$VISITS" | jq -e 'type=="array"' >/dev/null 2>&1 || VISITS='[]'

    # ── Session list (for the child-owner liveness map below) ─────────
    if [ -n "$FIXTURE" ]; then
        sess_raw=$([ -f "$FIXTURE/sessions.json" ] && cat "$FIXTURE/sessions.json" || printf '{}')
    else
        sess_raw=$(gcq session list --state all --json)
    fi

    # ── Owner liveness join (child-owner state; PROBLEM 1) ────────────
    # A child bead's `assignee` is its OWNING session — the session_name a
    # polecat recorded when it claimed the bead (e.g.
    # gc-toolkit__polecat-lx-bj70b), or a routed alias. To tell whether an
    # in-progress child is actually being worked, we need its owner's session
    # state, so map EVERY session by BOTH its
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
def sevrank: {"HIGH":3,"ELEVATED":2,"NORMAL":1,"LOW":0}[.];
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
    | (if $a.source=="decision" then []
       else ( [ ($a.description // "")
                | scan("(?:" + ($others|join("|")) + ")-[a-z0-9]{3,8}") ]
              | map(select(. as $r | ($rignames | index($r)) == null and $r != $a.id))
              | unique ) end) as $xrefs
    # held: an open visit in this anchor'\''s continuation group exists
    | (($visits | index($a.id)) != null) as $held
    # severity band. A held anchor is active work via its conversation,
    # not via in-progress child polecats — so "0 in-progress" is NOT
    # stranded when a visit is open. Stranded/HIGH is reserved for a
    # decomposed anchor with open children, zero in-progress, AND no
    # open visit.
    | (if $a.source=="unowned" then "HIGH"
       elif $a.source=="decision" then "ELEVATED"
       elif $m==0 then "LOW"
       elif $open==0 then "LOW"
       elif ($open>0 and $inprog_live==0 and ($held|not)) then "HIGH"
       elif ($inprog_dead>0) then "ELEVATED"
       else "NORMAL" end) as $sev0
    | (if ($sev0=="NORMAL" and $stale > '"$STALE_DAYS"') then "ELEVATED" else $sev0 end) as $sev
    | ($m + prio_w($a.priority) + ([$xrefs|length, '"$XREF_CAP"'] | min)) as $weight
    # one-line frontier summary
    | (if $inprog_dead>0 then " · \($inprog_dead) stuck (dead owner)" else "" end) as $deadsfx
    | (if $a.source=="unowned" then "unowned convoy — no owning bead"
       elif $a.source=="decision" then "human-gated decision"
       elif $m==0 then "empty — no children"
       elif $open==0 then "all \($m) closed · 0 open"
       elif ($inprog_live==0 and $inprog_dead>0 and ($held|not)) then "\($open) open · \($inprog_dead) stuck (dead owner)"
       elif ($inprog_live==0 and $held) then ("\($open) open · in conversation" + $deadsfx)
       elif $inprog_live==0 then "\($open) open · 0 in-progress (stranded)"
       else "\($open) open · \($inprog_live) in-progress" + $deadsfx end) as $frontier
    # The LLM-authored takeaway (host or proactive), if any: the board-visible
    # headline of what this anchor concluded / what it needs. Collapse any
    # internal whitespace (a stray newline would break the table) and trim.
    | (($a.takeaway // "") | gsub("[[:space:]]+";" ") | gsub("^ | $";"")) as $takeaway
    # NEEDS is the one-glance answer for a human: the LLM takeaway sentence
    # when one exists, else a TERSE deterministic STATE phrase — never a
    # bead-id list. The mechanical heads/xref ids move to --json only
    # (open_heads, cross_rig_refs), so the human table stays explanatory and
    # cannot emit a raw/truncated bead-id.
    | (if ($takeaway|length) > 0 then $takeaway
       elif $a.source=="unowned" then "unowned — assign an owning bead"
       elif $a.source=="decision" then "operator decision"
       elif $m==0 then "no children — decompose or assign"
       elif $open==0 then (if $a.source=="convoy" then "all \($m) closed — graduate" else "all \($m) closed — close or extend" end)
       elif ($inprog_live==0 and $inprog_dead>0 and ($held|not)) then "dead owner — recover or reassign"
       elif ($inprog_live==0 and $held) then "open to join"
       elif $inprog_live==0 then "decomposed, idle — assign or visit"
       else (if $inprog_dead>0 then "in flight — \($inprog_dead) stuck, recover"
             else ("in flight" + (if $held then " (in conversation)" else "" end)) end) end) as $needs
    | {
        id:$a.id, rig:$a.rig, kind:$a.kind, title:$a.title,
        severity:$sev, weight:$weight, held:$held,
        n_closed:$closed, m_total:$m, open:$open, in_progress:$inprog, assigned:$assigned,
        in_progress_live:$inprog_live, in_progress_dead:$inprog_dead, dead_owner:($inprog_dead>0),
        owned:(if ($a|has("owned")) then $a.owned else null end),
        stranded:($m>0 and $open>0 and $inprog_live==0 and ($held|not)),
        empty:($m==0 and $a.source!="decision" and $a.source!="unowned"),
        complete:($m>0 and $open==0),
        progress_mismatch:$pmismatch,
        stale_days:$stale, priority:$a.priority, cross_rig_refs:$xrefs,
        open_heads:$open_ids, dead_owner_heads:$dead_owner_heads,
        takeaway:(if ($takeaway|length)>0 then $takeaway else null end),
        takeaway_at:(($a.takeaway_at // "") | if .=="" then null else . end),
        takeaway_by:(($a.takeaway_by // "") | if .=="" then null else . end),
        updated_at:$a.updated_at, frontier:$frontier, needs:$needs,
        rank_score: (($sev|sevrank)*1000000 + $weight*1000 + ([$stale,999]|min))
      }
  )
| sort_by(-.rank_score)
# A bead can be matched by two gathers at once. Dedup by id, keeping the
# FIRST (highest-ranked) row, so a doubly-matched anchor shows once, in
# its higher band.
| reduce .[] as $r ({ids:[], out:[]};
    if (.ids | index($r.id)) then .
    else {ids:(.ids + [$r.id]), out:(.out + [$r])} end) | .out
'
    FULL=$(jq -c -n --argjson prefixes "$PREFIXES" --argjson rignames "$RIGNAMES" \
        --argjson now "$NOW_EPOCH" --argjson visits "$VISITS" --argjson ownermap "$OWNER_MAP" \
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
    printf 'gc-helm — cross-rig human-attention board\n'
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
( (" "|rpad(2)) + ("SEV"|rpad(9)) + ("ID"|rpad(11)) + ("RIG"|rpad(13)) + ("KIND"|rpad(9)) + ("N/M"|rpad(7)) + ("FRONTIER"|rpad(36)) + "NEEDS" ),
( ("─"*1|rpad(2)) + ("─"*8|rpad(9)) + ("─"*10|rpad(11)) + ("─"*12|rpad(13)) + ("─"*8|rpad(9)) + ("─"*6|rpad(7)) + ("─"*35|rpad(36)) + ("─"*16) ),
( .[] | ((if .held then "●" else " " end)|rpad(2)) + ((.severity)|rpad(9)) + ((.id)|rpad(11)) + ((.rig)|rpad(13)) + ((.kind)|rpad(9))
        + ((if .kind=="decision" then "—" else "\(.n_closed)/\(.m_total)" end)|rpad(7))
        + ((.frontier)|rpad(36)) + (.needs) )
'
    printf '\nLegend: HIGH=stranded/unowned · ELEVATED=decision/stale/stuck · NORMAL=active · LOW=empty/complete\n'
    printf 'Held: ● an open visit holds this anchor'\''s conversation (attach via the sessions picker) · blank = none\n'
    printf 'open <id> to file a visit · react <id> to advance a takeaway-less row. Ranking is a deterministic proxy.\n'
}

# ── Anchor gather (the cached, Dolt-heavy part) ──────────────────────
# Appends one anchor object per line to $ANCHORS. Reads only. A query
# that comes back EMPTY/INVALID (timeout, wedged Dolt, gc error) is
# gather_mark'ed so the caller refuses to cache or render the result;
# a query that comes back VALID but empty is a legitimately
# quiet rig and is simply skipped.
gather_anchors() {
    printf '%s' "$RIGS" | jq -c '.[]' | while IFS= read -r rig; do
        name=$(printf '%s' "$rig" | jq -r '.name')
        path=$(printf '%s' "$rig" | jq -r '.path')
        prefix=$(printf '%s' "$rig" | jq -r '.prefix')
        beads="$path/.beads"
        [ -d "$beads" ] || continue

        # Epics: roll up children via --parent (all statuses, so closed count is real).
        epics_raw=$(gcq bd list --db "$beads" --type epic --status open --json)
        printf '%s' "$epics_raw" | jq -e 'type=="array"' >/dev/null 2>&1 || gather_mark "epics@$name"
        epics=$(as_array "$epics_raw")
        printf '%s' "$epics" | jq -c '.[]' | while IFS= read -r epic; do
            eid=$(printf '%s' "$epic" | jq -r '.id')
            ch_raw=$(gcq bd list --db "$beads" --parent "$eid" --status open,in_progress,closed,blocked,deferred --json)
            printf '%s' "$ch_raw" | jq -e 'type=="array"' >/dev/null 2>&1 || gather_mark "children@$eid"
            # Project to the three fields the render consumes BEFORE the value
            # crosses the argv boundary. $ch_raw carries every child's full
            # description and notes, and Linux caps a SINGLE argv string at
            # MAX_ARG_STRLEN (131072 B) independent of the much larger ARG_MAX —
            # so one bead's accumulated notes is enough to push --argjson past
            # the cap, at which point jq never execs at all. Feeding the bulk
            # through a PIPE (no argv limit) and passing only the projection
            # re-bases growth on child COUNT (~50 B/child) instead of unbounded
            # note volume.
            children=$(as_array "$ch_raw" | jq -c '[.[] | {id, status, assignee}]') \
                || gather_mark "children-project@$eid"
            children=$(as_array "$children")
            printf '%s' "$epic" | jq -c \
                --argjson ch "$children" --arg rig "$name" --arg prefix "$prefix" \
                '{id, title:(.title//""), kind:"epic", source:"epic", rig:$rig, prefix:$prefix,
                  priority:(.priority//3), updated_at:(.updated_at//""), description:(.description//""),
                  progress:null,
                  takeaway:(.metadata["gc.takeaway"] // ""),
                  takeaway_at:(.metadata["gc.takeaway_at"] // ""),
                  takeaway_by:(.metadata["gc.takeaway_by"] // ""),
                  children:$ch}' >> "$ANCHORS" || gather_mark "anchor@$eid"
        done

        # Decisions: human-gated; no child roll-up needed (rank is elevated regardless).
        decisions_raw=$(gcq bd list --db "$beads" --type decision --status open --json)
        printf '%s' "$decisions_raw" | jq -e 'type=="array"' >/dev/null 2>&1 || gather_mark "decisions@$name"
        decisions=$(as_array "$decisions_raw")
        printf '%s' "$decisions" | jq -c \
            --arg rig "$name" --arg prefix "$prefix" \
            '.[] | {id, title:(.title//""), kind:"decision", source:"decision", rig:$rig, prefix:$prefix,
                    priority:(.priority//3), updated_at:(.updated_at//""), description:(.description//""),
                    progress:null, children:[],
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
    convoys_raw=$(gcq convoy list --json)
    printf '%s' "$convoys_raw" | jq -e 'type=="object" or type=="array"' >/dev/null 2>&1 || gather_mark "convoy-list"
    convoys=$(printf '%s' "$convoys_raw" | jq -c '
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
        # Empty/invalid reply = the timeout/wedge shape → mark; a
        # VALID reply that just isn't a non-empty array is a legit skip.
        printf '%s' "$show" | jq -e '.' >/dev/null 2>&1 || { gather_mark "show@$cid"; continue; }
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

# ── Visit gather (rides the cached gather) ───────────────────────────
# Writes ONE JSON-array line to $VISITS_FILE: the unique subject ids
# carried by open visit beads (task_kind=visit, gc.continuation_group).
# Per-rig like the anchor gather; a rig whose query dies is
# gather_mark'ed (see gather_anchors). Both
# open AND in_progress count as "open" here — a claimed visit is a held
# conversation, not a finished one.
gather_visits() {
    : > "$TMP/visit-subjects.txt"
    printf '%s' "$RIGS" | jq -c '.[]' | while IFS= read -r rig; do
        path=$(printf '%s' "$rig" | jq -r '.path')
        beads="$path/.beads"
        [ -d "$beads" ] || continue
        v_raw=$(gcq bd list --db "$beads" --status open,in_progress --json --limit=0)
        printf '%s' "$v_raw" | jq -e 'type=="array"' >/dev/null 2>&1 || gather_mark "visits@$path"
        as_array "$v_raw" \
            | jq -r '.[] | select((.metadata.task_kind // "") == "visit")
                     | .metadata["gc.continuation_group"] // empty' >> "$TMP/visit-subjects.txt" 2>/dev/null || true
    done
    jq -R -s -c 'split("\n") | map(select(length > 0)) | unique' \
        < "$TMP/visit-subjects.txt" > "$VISITS_FILE" 2>/dev/null || printf '[]\n' > "$VISITS_FILE"
}

# ── Dispatch ─────────────────────────────────────────────────────────
case "${1:-}" in
    open)          shift; cmd_open "$@" ;;
    react)         shift; cmd_react "$@" ;;
    takeaway)      shift; cmd_takeaway "$@" ;;
    board)         shift; cmd_board "$@" ;;
    -h|--help|help) usage; exit 0 ;;
    ''|-*)         cmd_board "$@" ;;          # no verb, or a board flag → board (back-compat)
    *)             echo "$PROG: unknown verb '$1' (try: board, open, react, takeaway, help)" >&2; usage; exit 2 ;;
esac
