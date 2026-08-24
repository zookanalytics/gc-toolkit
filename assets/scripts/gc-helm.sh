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
#   gc-helm closed [--since 24h] [--json] [--limit=N] [--timeout=SECONDS]
#   gc-helm open  <bead-id> [--reason "..."] [--body "..."]  file a visit on the bead (converse holds it)
#   gc-helm takeaway <bead-id> "<text>" [--by …] [--release]  set the board-visible takeaway headline (≤140 chars, ENFORCED)
#
#   board → the operator glances the ranked rows (with a held glyph,
#           a row cap, and a cache so the gather is paid once, not
#           every glance).
#   closed → what reached a disposition inside a window, and why —
#           the rows the open-only board drops when a sitting concludes.
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
# SIX kinds of OPEN anchors are collected, cross-rig. The first four are
# selected by the bead's issue TYPE (or convoy shape); the last two by its
# METADATA — see "Metadata-keyed kinds" below for why that distinction
# exists at all.
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
#   5. human      — any non-typed open bead carrying `gc.routed_to=human`.
#   6. parked     — any non-typed open bead carrying a `gc.takeaway`.
#
# ── Metadata-keyed kinds (5 and 6) ───────────────────────────────────
# The type-keyed gather is closed by construction: an ordinary task or bug
# the OPERATOR owns cannot appear on the board no matter its state or who
# it is waiting on. That is not merely a ranking miss — the board is the
# front door, so a subject absent from it is also unresumable: nothing
# prompts a return to it once the thread that produced it ends.
#
#   human   `gc.routed_to=human` is the city's durable "a human must act"
#           marker. Banded ELEVATED for a decision's reason: no agent will
#           take it, so it moves only when the operator moves it.
#
#           UNTIL IT IS ANSWERED. Both human-gated kinds are banded by what
#           they ARE, and what they are never changes while the bead is
#           open — so the row asked for the operator on the day it was filed
#           and went on asking after they answered it. On the 2026-08-23
#           board seven of 24 ELEVATED rows carried a `gc.takeaway`
#           recording their own ruling, one of them for thirty days, and
#           converse never closes a subject by contract, so nothing else
#           could ever retire them. A takeaway PLUS no outstanding
#           `--waiting-on` work stands the row DOWN to LOW, reading
#           "ruled — close or extend" (tk-b3rga). Same derivation as the
#           parked disposition below — per render, storing nothing — pointed
#           the other way, so a re-opened question stands back up by itself.
#           A ruled row that DECOMPOSED is banded by its roll-up instead:
#           "answered" is a claim about the bead, and open work under it
#           falsifies the claim, exactly as it does for a parked subject.
#   parked  a `gc.takeaway` means the conversation reached a conclusion.
#           Banded LOW — the opposite claim. It wants nothing; it only has
#           to stay FINDABLE, and the band floor keeps it from competing
#           with real attention items whatever its priority or age.
#           Resume with prefix+a, then the bead id.
#
#           EXCEPT when it has CHILDREN. Both metadata-keyed kinds roll up
#           their `parent-child` children like an epic does, and a parked
#           subject that decomposed is banded by that roll-up instead of by
#           the floor — the floor asserts "wants nothing", which is simply
#           false while open work hangs under it. This is the canonical
#           converse shape: a sitting files the work it routes as a CHILD of
#           the subject, and `bd` REFUSES a `blocks` edge from a parent to
#           its own descendant, so that work can never appear as a
#           `waiting_on` edge (tk-2cyxo). Before this, a decomposed subject
#           reported zero children and its open children — which reach the
#           board only through a parent's roll-up — vanished from every
#           surface (tk-a9k0l).
#
#           EXCEPT when it was waiting on something that has since landed.
#           A sitting that routes work out of a subject writes a `blocks`
#           edge to that work (`takeaway --waiting-on`), and the render
#           re-asks whether the blocker closed. All of them closed and the
#           row is no longer "wants nothing" — it is a disposition the
#           operator owes, so it is banded ELEVATED and says so. Without
#           that, "holding — awaiting X" and "nothing further needed here"
#           are the same row forever, and a finished topic sits on the
#           board until a sitting is spent rediscovering that it finished
#           (tk-2plde: 29 hours, one wasted sitting). DERIVED per render —
#           nothing is stored, so no state has to be cleared later.
#
# Both EXCLUDE the four typed kinds, so an epic or decision that happens to
# carry a marker stays its own kind instead of arriving twice. A bead
# carrying BOTH markers is emitted twice on purpose and the id-dedup below
# keeps the higher band — which is why the stand-down and the disposition
# promotion both key on human-gatedness rather than on the kind alone. Two
# rows for one bead, each with its own band, means the LOUDER derivation
# always wins; a quieting rule that reads only the kind would be undone by
# its own twin on every row it was written for.
#
# This mirrors the Go helm service's gather (services/helm/README.md,
# "Anchor kinds", tk-2v08m). THE TWO BOARDS ARE SEPARATE IMPLEMENTATIONS
# of one model and a fix landing on one does not reach the other — see
# docs/gascity-human-engagement.md, "Two helm boards".
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
#                      members and the metadata-keyed kinds' children from
#                      the anchor bead's deps
#                      (`bd show --include-dependents`). N/M and the
#                      frontier derive from the SAME child set, so a row
#                      cannot self-contradict. `gc convoy list` .progress
#                      is kept ONLY as a cross-check: any disagreement
#                      with the resolved set is surfaced as
#                      `progress_mismatch` in the JSON output. A row with
#                      no children at all carries no frontier (N/M = —):
#                      decisions always, and a `human`/`parked` bead that
#                      never decomposed.
#   • open/in-progress/assigned — counts over the open frontier.
#   • in flight      — a child is MOVING if EITHER (1) it is claimed
#                      (status=in_progress) and its OWNING session is live,
#                      or (2) a LIVE graph.v2 workflow covers it. Clause 2
#                      is not a refinement, it is most of the signal: a bead
#                      dispatched by `gc sling` keeps status=open and
#                      assignee=null for its whole life — in-flight state
#                      lives on the WORKFLOW (root bead + step beads), never
#                      on the work bead — so under clause 1 alone a polecat
#                      five minutes into an implementation is byte-for-byte
#                      identical to a bead nobody has ever touched, and its
#                      parent renders "stranded — assign or visit", an
#                      instruction to intervene in work already moving.
#                      The join is the canonical walk (root ->
#                      gc.input_convoy_id -> the convoy's SINGLE tracked
#                      member); a convoy resolving to any other count is a
#                      shape this does not understand and makes NO movement
#                      claim.
#                      LIVENESS IS LOAD-BEARING. Nothing finalizes a
#                      graph.v2 chain after its session drains, so completed
#                      workflows leave open husk roots behind and they pile
#                      up (18 open roots in one rig when this was written,
#                      17 dead). Joining on root EXISTENCE would flip every
#                      husk to "in flight" — trading a false stall for a
#                      false all-clear, the worse lie on a board whose job
#                      is to say what needs a human. Checked in two places:
#                      the gather resolves only live roots (bounding the
#                      convoy reads), and the render re-checks each session
#                      against the FRESH list, so a polecat that drained
#                      mid-cache stops counting at once.
#   • stranded       — decomposed (M>0) with open children, NOTHING in
#                      flight, AND no open visit: work exists but nothing is
#                      moving. An open visit counts as moving — the bead is
#                      worked via its held conversation. An in-progress
#                      child whose OWNING session is dead (state
#                      archived/closed/absent — keyed off .state, never
#                      .running, per the witness orphan-liveness rule) and
#                      which no live workflow covers does NOT count as
#                      moving: it is the canonical UNKNOWN-stuck case, so a
#                      frontier of only dead-owner children reads stranded,
#                      not active (PROBLEM 1).
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
#   HIGH      stranded frontier (decomposed, open, nothing in flight, and
#             no open visit — incl. a frontier whose only in-progress
#             children have dead owners), OR an unowned non-machine convoy
#             (the orphan exception).
#   ELEVATED  a `decision` (human-gated); a `human` bead (same reason); an
#             otherwise-NORMAL anchor gone stale (> STALE_DAYS days); OR a
#             still-moving anchor that has a dead-owner (stuck) in-progress
#             child to recover.
#   NORMAL    active frontier (work in flight, OR an open visit — a
#             conversation is held).
#   LOW       empty epic (0 children), complete convoy (all closed), or a
#             CHILDLESS `parked` bead (floored by band, never by score).
#             A parked bead that decomposed is banded by its children like
#             any other roll-up anchor — the floor claims it wants nothing,
#             which stops being true the moment open work hangs under it.
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
# `in_progress` stays the RAW status count (honestly 0 for a slung bead);
# `in_progress_live` is the moving count under both clauses, and
# `in_flight` / `in_flight_heads` name the part attributable to a live
# workflow, so the join can be audited without re-deriving it.
# `--json` is the stable contract for downstream tooling (the tmux
# board picker reads it). There is no `live` (hot/warm/cold) host
# field — the visit/converse spine is the only conversation
# mechanism, and `held` is its one glyph fact.
#
# ── Row cap & cache (the board must scale) ───────────────────────────
# The gather hits every rig's Dolt and costs ~6s on a five-rig city, so this
# script caches the RENDERED OUTPUT of each verb (default TTL
# GC_HELM_CACHE_TTL=45s) — a repeat glance is then a `tail` rather than a
# gather. helm-svc's own CLI path is deliberately uncached so `prefix+b` works
# when the sidecar is down; the cheap layer belongs here, at the only place
# that knows a glance is a repeat. Every write verb (`open` files a visit,
# `takeaway` parks one, `react` slings) busts the cache, so the operator never
# watches their own action have no effect. `--refresh` (or `--no-cache`)
# forces a fresh run.
#
# Rows are CAPPED at GC_HELM_MAX_ROWS (default 50) so the board can never
# balloon to "every bead"; `--limit=N` overrides with an explicit N, and
# `--limit=0` means ALL (uncapped) for tooling. `parked` rows draw on a
# SEPARATE budget, GC_HELM_MAX_PARKED (default 15), instead of competing for
# the same slots: they are band-floored to LOW and so sort last, and under one
# shared cap they would be the first rows trimmed — which would re-hide, on the
# operator's actual surface, exactly the beads the kind exists to surface.
# Both caps are applied by helm-svc, which reads those two variables out of the
# environment this script hands it.
#
# Exit codes:
#   0   board rendered / verb succeeded
#   2   usage error
#   3   missing dependency (jq / gc), no helm-svc binary and nothing cached
#       to replay, could not enumerate rigs, or the gather failed (nothing
#       cached — a transient gather failure must never be served as a
#       "0 anchors" all-clear). board and closed pass helm-svc's own exit
#       code straight through, and it uses the same three. The rig-enumeration
#       failures all share this code but deliberately NOT the message: a
#       timeout kill, gc exiting non-zero, an empty / unparseable /
#       wrong-shaped answer, and a legitimately rigless city each name
#       their own operator move, because the code alone cannot tell them
#       apart and for a non-CLI caller the code plus the sentence is the
#       whole signal (tk-lzdty).
#   4   verb runtime failure (e.g. bead not found, visit filing failed)
#
# Test hook: GC_HELM_FIXTURE=<dir> — when set, rig enumeration reads
# <dir>/rigs.json instead of asking `gc`, so the verb tests run against a
# canned rig set with no live city. Unset in normal use.
#
# It no longer feeds the board. It used to also supply anchors.ndjson,
# visits.json, inflight.json and sessions.json, because the board's whole
# render/rank/glyph path lived in this file and had to be driven from
# somewhere hermetic. That path is now helm-svc's, and so are its tests
# (services/helm/internal/board, cmd/helm-svc) — which exercise the model
# directly rather than through a canned copy of a gather.
#
# Board test hook: GC_HELM_SVC_BIN=<path> — the binary board and closed run.
# A test points it at a stub to assert what this script does AROUND helm-svc
# (which flags it forwards, what it caches, how it degrades) without needing a
# built binary or a live city.

set -eu

PROG="gc-helm"

# ── Tunables ─────────────────────────────────────────────────────────
# The board's own knobs — the staleness threshold, the cross-rig-ref cap, the
# row caps — are NOT here any more. They belong to the model, the model is
# services/helm, and a copy of them in this file would be a second set of
# numbers to keep equal (see the board/closed verbs below on why there is only
# one implementation now). GC_HELM_MAX_ROWS and GC_HELM_MAX_PARKED still work
# and are still 50/15 by default; they are read by helm-svc, which inherits
# this process's environment, so nothing has to forward them.
CACHE_TTL="${GC_HELM_CACHE_TTL:-45}"        # seconds a rendered board stays fresh
TAKEAWAY_MAX=140                            # hard cap on a takeaway headline, in CODEPOINTS
FIXTURE="${GC_HELM_FIXTURE:-}"              # test hook (see header)
# Fall back to the default on a non-numeric override so `set -e` arithmetic
# (the cache-age test) can't crash the board on a bad env value.
case "$CACHE_TTL" in ''|*[!0-9]*) CACHE_TTL=45 ;; esac

usage() {
    cat >&2 <<'EOF'
Usage:
  gc-helm [board] [--json] [--limit=N] [--timeout=SECONDS] [--refresh]
  gc-helm closed [--since 24h] [--json] [--limit=N] [--timeout=SECONDS]  what closed with a disposition, and why
  gc-helm open  <bead-id> [--reason "..."] [--body "..."]  file a visit on the bead (a converse session holds the conversation)
  gc-helm react <bead-id> [--reason "..."]  sling a first reaction (self-heals a takeaway-less row)
  gc-helm takeaway <bead-id> "<text>" [--by host|proactive|converse] [--waiting-on <bead-id>]... [--release]  set the board-visible takeaway headline (≤140 chars, ENFORCED)

The board (default verb) is a read-only cross-rig ranking of OPEN anchors
(epics, floating owned convoys, and decisions) by how much
they need a human's attention. Being open-only is what closed answers: a
subject whose sitting concluded LEAVES the board, and nothing afterwards says
what was decided. closed lists the visits that reached a disposition inside a
window, newest first, with the outcome stamped on the visit and the takeaway
stamped on its subject. It is a read over what sign-off already records, it
writes nothing, and it is PULL only — there is deliberately no cadence, order,
nudge or mail behind it.
board and closed are both THIN RENDERERS over the helm-svc binary, which is
the one implementation of each; this script gathers and ranks nothing. open
files a visit in the picked bead's
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
in one update. The 140-char cap is enforced, not advisory: a longer text is
REFUSED so the author cuts it, because only the author knows which clause is
the headline; the board clips anything already stored over it. With --release
it also reopens/unassigns/clears the route and marks the proactive reaction in
that same write (the proactive worker's one-call close). converse calls it
WITHOUT --release, twice per sitting: once when the hold begins and once at
sign-off, so a reaped thread still leaves a dated trace of what it was waiting
for (tk-bzm86).
--waiting-on <bead-id> (repeatable) records the same wait as a `blocks` EDGE
alongside the prose, so the board can re-ask whether it is still true. Pass it
for every bead a sitting routes work into. Without it the wait is a frozen
sentence: the row keeps saying "awaiting X" after X merges, stays LOW, and the
next sitting is spent rediscovering that the work landed (tk-2plde). With it,
the row promotes to "blocker landed — dispose or resume" as soon as the last
blocker closes.

  --json             Emit the ranked board as a JSON array (stable contract).
                     On closed, emits the disposition rows as a JSON array.
  --since DURATION   closed only: how far back to look (default 24h). Spelled
                     the way this pack spells durations — 30s, 90m, 24h, 7d, or
                     a bare integer meaning seconds.
  --limit=N          Show only the top N rows (0 = all/uncapped; default caps at 50).
  --timeout=SECONDS  Bound the WHOLE gather (default 120). It used to bound each
                     Dolt read at 10s; helm-svc gathers concurrently, so one
                     budget for the pass is the number that means something.
  --refresh          Bypass this script's rendered-output cache and re-run
                     helm-svc now. --no-cache is a synonym.
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
# Keyed by city path so distinct cities don't collide. One file per
# (verb, representation) slot — render1-<city>.board.table,
# render1-<city>.closed.json, and so on.
#
# Cache format: line 1 = the epoch the render was produced, lines 2.. = the
# rendered bytes verbatim. Line 1 rather than the file's mtime because stat(1)
# and find(1) spell mtime differently on GNU and BSD, and this runs on both.
#
# WHAT IS CACHED CHANGED WITH THE MODEL. Until the board moved to helm-svc
# this held a GATHER — anchors, the visit map, the in-flight map — and the
# ranking was recomputed on every glance. There is no gather here any more, so
# what is stored is the finished output of `helm-svc <verb>`. The name carries
# the format ("render1-"), so a cache written by any older layout — "board2-",
# "anchors-", "board-" — is never read rather than being parsed one line out
# of register.
CACHE_DIR="${TMPDIR:-/tmp}/gc-helm-cache.$(id -u 2>/dev/null || echo 0)"
_city_key=$(printf '%s' "${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-default}}}" | cksum | cut -d' ' -f1)

# bust_cache drops every rendered slot for this city. The write verbs call it
# because each of them changes what the next board would say — `open` files a
# visit (the held glyph and the row's frontier), `takeaway` sets the NEEDS
# sentence, `react` slings work — and a cache that outlived the write would
# show the operator their own action having no effect for a whole TTL.
#
# It globs rather than naming files: the slot set is (verb × representation),
# and a bust that knew only some of them would leave the others lying. A verb
# added later is covered without anyone remembering to come back here.
bust_cache() { rm -f "$CACHE_DIR/render1-$_city_key."* 2>/dev/null || true; }

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
    _er_secs="${TIMEOUT:-${GC_HELM_RIG_TIMEOUT:-30}}"
    # >>> rig-enumeration-taxonomy
    # KEEP THE EVIDENCE. This used to end in `|| true` with stderr sent to
    # /dev/null, so the one line below reported a timeout kill, a wedged data
    # plane, malformed output and a genuinely rigless city identically — and
    # `exit 3` carried no more information than the sentence did. Four
    # different operator moves (raise the bound / check Dolt / look at what gc
    # actually printed / add a rig) rendered as one string you could not act
    # on. On the CLI that is a bad message. Behind the web board's open button
    # (tk-66rwg) the exit code plus that one string is the ENTIRE signal the
    # browser gets, so all four render as the same dead end.
    #
    # The status and stderr are the only things that separate them, so capture
    # both rather than discarding them. mktemp failing is not worth aborting
    # over: fall back to the un-captured form and lose only the `why` clause.
    _er_errf=$(mktemp 2>/dev/null || printf '')
    _er_rc=0
    if [ -n "$_er_errf" ]; then
        rigs_raw=$(with_timeout "$_er_secs" gc rig list --json 2>"$_er_errf") || _er_rc=$?
        # One line, bounded: this is quoted into a message, not parsed.
        _er_why=$(tr '\n' ' ' < "$_er_errf" 2>/dev/null | cut -c1-300 | sed 's/  */ /g; s/^ *//; s/ *$//')
        rm -f "$_er_errf" 2>/dev/null || true
    else
        rigs_raw=$(with_timeout "$_er_secs" gc rig list --json 2>/dev/null) || _er_rc=$?
        _er_why=""
    fi

    if [ "$_er_rc" -ne 0 ]; then
        # 124 is the timeout kill, and it is only reachable when a timeout
        # binary exists — without one, with_timeout runs the command unbounded
        # and a 124 could only be gc's own exit status. Do not blame the bound
        # for something that was never applied.
        if [ -n "$TIMEOUT_BIN" ] && [ "$_er_rc" -eq 124 ]; then
            echo "$PROG: could not enumerate rigs: 'gc rig list' did not answer within ${_er_secs}s and was killed. Raise the bound with GC_HELM_RIG_TIMEOUT=<seconds>, or check whether gc/Dolt is wedged. This command wrote nothing." >&2
        else
            echo "$PROG: could not enumerate rigs: 'gc rig list' exited ${_er_rc}${_er_why:+ — $_er_why}. That is the data plane, not this script — try 'gc doctor' and check Dolt. This command wrote nothing." >&2
        fi
        exit 3
    fi

    # gc exited 0, so whatever is wrong is with what it PRINTED. jq -e reports
    # each of those separately in its own exit status: 4 = it produced no
    # output at all (empty input), 5 = the input would not parse as JSON,
    # 1 = it parsed but the shape is not the {"rigs":[…]} contract. Each is a
    # different operator move, so each gets its own sentence.
    _er_shape=0
    printf '%s' "$rigs_raw" | jq -e 'type=="object" and (.rigs|type)=="array"' >/dev/null 2>&1 || _er_shape=$?
    case "$_er_shape" in
        0) : ;;
        4) echo "$PROG: could not enumerate rigs: 'gc rig list --json' exited 0 but printed nothing. A silent empty answer usually means gc was killed or the city path is wrong — check GC_CITY and 'gc doctor'. This command wrote nothing." >&2
           exit 3 ;;
        5) echo "$PROG: could not enumerate rigs: 'gc rig list --json' printed something that is not JSON${_er_why:+ — $_er_why}. Run it by hand to see what it actually emitted (a stray log line on stdout is the usual cause). This command wrote nothing." >&2
           exit 3 ;;
        *) echo "$PROG: could not enumerate rigs: 'gc rig list --json' printed JSON with no '.rigs' array. That is a gc contract change, not a city problem — this script reads {\"rigs\":[{name,path,prefix}]}. This command wrote nothing." >&2
           exit 3 ;;
    esac

    RIGS=$(printf '%s' "$rigs_raw" | jq -c '[.rigs[]? | {name, path, prefix}]' 2>/dev/null || printf '[]')
    if [ "$(rigs_count)" -eq 0 ]; then
        # The one reading that is NOT a malfunction: gc answered correctly and
        # the answer is that this city has no rigs. Say that, so nobody goes
        # looking for a broken data plane. Still exit 3 — every caller needs a
        # rig to do anything — but the sentence has to name the real move.
        echo "$PROG: no rigs in this city: 'gc rig list' answered normally with an empty rig set. Add one with 'gc rig add', or point GC_CITY at the intended city. This command wrote nothing." >&2
        exit 3
    fi
    # <<< rig-enumeration-taxonomy
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
#
# --waiting-on <bead-id> (repeatable) writes the wait as a GRAPH EDGE beside the
# prose: this bead depends on <bead-id> by a `blocks` edge. It exists because a
# takeaway is a single frozen string, and "routed — tk-hgmob slung; nothing
# further needed here" goes on saying that after tk-hgmob merges. Nothing
# re-reads prose, so the subject parks at LOW forever and the next sitting is
# spent rediscovering that its work landed (tk-2plde: 29 hours on the board,
# one sitting burned). With the edge, the board re-asks the question on every
# render and promotes the row to "blocker landed — dispose or resume" the
# moment the work closes. The edge is the durable half; nothing about the
# render is stored, so there is no state to clear afterwards.
#
# The edge is added, never removed: this verb only ever says "also waiting on
# X". A wait that turns out to be wrong is unwired with `bd dep remove`, which
# is a correction and not something a takeaway stamp should do implicitly.
#
# Best-effort by construction. A `blocks` edge can only join two beads in ONE
# store, so a blocker in another rig cannot be wired at all; that, a typo, and
# a cycle all surface as a warning on stderr while the takeaway itself still
# lands. The stamp is the thing the operator is waiting on — a sitting must
# never fail to record its conclusion because a graph edge would not take.
cmd_takeaway() {
    bead=""; text=""; by="host"; release=""; npos=0
    waiting_ids=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --by=*)    by="${1#--by=}"; shift ;;
            --by)      shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --by requires a value" >&2; exit 2; }; by="$1"; shift ;;
            --waiting-on=*) waiting_ids="$waiting_ids ${1#--waiting-on=}"; shift ;;
            --waiting-on)   shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --waiting-on requires a bead id" >&2; exit 2; }
                            waiting_ids="$waiting_ids $1"; shift ;;
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
    [ -n "$text" ] || { echo "$PROG: takeaway needs \"<text>\" (the ≤${TAKEAWAY_MAX}-char one-line headline)" >&2; usage; exit 2; }

    # >>> takeaway-length-gate
    # The cap was DOCUMENTED and unenforced, and it ran 22-for-23 against: the
    # live board carried 23 takeaways averaging 597 chars (max 1876) and they
    # were 91% of all its NEEDS text (tk-9tbbk.1). NEEDS is the last column of a
    # terminal table, so a paragraph there is not a wide cell — it is one row
    # wrapping over the rest of the board. The prior remedy attempted was a
    # note-to-self in a bead's notes; the sitting that wrote it then stamped a
    # 200-char takeaway. Prose cannot enforce this. The gate has to.
    #
    # REJECT, never truncate. The writer knows which clause is the headline and
    # which is the detail; this script does not, and a silent trim would drop
    # the half the sitting most wanted read while still reporting success. The
    # detail belongs in the bead's notes or a first-reaction card — the
    # takeaway is the one line that has to survive a glance.
    #
    # Measured in CODEPOINTS, because that is what both renderers measure (jq
    # `length`/`rpad`, and helm-svc's []rune): an em dash costs three bytes and
    # one column, so a byte cap would refuse a headline that fits on the board.
    # jq is a hard dependency, checked at startup. Should it somehow answer
    # with a non-number, fall back to the shell's own count rather than let the
    # gate evaporate — a guard that fails open is the defect being fixed here.
    tlen=$(printf '%s' "$text" | jq -Rsr 'length' 2>/dev/null || true)
    case "$tlen" in ''|*[!0-9]*) tlen=${#text} ;; esac
    if [ "$tlen" -gt "$TAKEAWAY_MAX" ]; then
        echo "$PROG: takeaway: text is $tlen chars; the cap is $TAKEAWAY_MAX" >&2
        echo "$PROG: takeaway: it renders as the board's NEEDS cell — one line, read at a glance. Cut it to the single sentence the operator needs and put the rest in the bead's notes." >&2
        exit 2
    fi
    # <<< takeaway-length-gate

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
    # Wire the waits as edges, AFTER the stamp has landed. Order matters: the
    # takeaway is what the sitting owes the operator, so it is written first and
    # a failure here degrades to today's behaviour (prose only) rather than
    # losing the conclusion. `dep add <bead> <blocker>` reads its second
    # argument as the DEPENDS-ON id, so this says "<bead> is blocked by
    # <blocker>" and the row lands on <bead> — which is what the board reads.
    for _w in $waiting_ids; do
        [ -n "$_w" ] || continue
        if [ "$_w" = "$bead" ]; then
            echo "$PROG: takeaway: --waiting-on $_w is the bead itself; skipped" >&2
            continue
        fi
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        if gc bd dep add "$bead" "$_w" -t blocks ${db:+--db "$db"} >/dev/null 2>&1; then
            echo "waiting-on edge: $bead depends on $_w"
        else
            echo "$PROG: takeaway: could not wire --waiting-on $_w (same store? already wired? cycle?) — the takeaway text still stands, but the board cannot see this wait" >&2
        fi
    done
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

    # Already held? An open visit on this bead IS the conversation — filing a
    # second would split it. Print the existing visit and the same attach hint
    # instead.
    #
    # A visit records its subject TWICE — the gc.continuation_group stamp and
    # the tracks edge the gate-visit block files with it — and only the edge has
    # proved reliable: on su-ab9je (shutupandlisten, 2026-08-20, bead tk-d6ddn)
    # the stamp landed EMPTY while the edge carried the subject. This guard is
    # the operator's front door, so keying it on the stamp alone means
    # `gc-helm open` cheerfully files the duplicate the guard exists to prevent. Match on
    # EITHER recording. `gc bd list` renders the edge as .type + .depends_on_id
    # (`gc bd show` names the same edge .dependency_type + .id).
    #
    # The `$s != ""` arm is not redundant with the existence gate above: without
    # it an empty subject would match a visit whose stamp is empty, and the verb
    # would report an unrelated sitting as this bead's.
    existing=$(gc bd list --status=open,in_progress --json --limit=0 2>/dev/null \
        | jq -r --arg s "$bead" \
            '[ .[]? | select((.metadata.task_kind // "") == "visit")
               | select($s != ""
                        and (((.metadata["gc.continuation_group"] // "") == $s)
                             or ([ .dependencies[]?
                                   | select((.type // "") == "tracks")
                                   | select((.depends_on_id // "") == $s) ] | length > 0)))
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

# ── Verbs: board + closed (thin renderers over helm-svc) ─────────────
# There is ONE board, and it is `services/helm`. These two verbs gather
# nothing, rank nothing and derive nothing: they locate the helm-svc binary,
# hand it the caller's flags, and pass its bytes and its exit code back.
#
# WHY THE SHELL BOARD IS GONE. It was the second implementation of a model
# that already existed in Go, and a duplicate is a bug factory rather than a
# redundancy: the same defect had to be found and fixed twice, and twice it
# was not (`tk-2v08m`, `tk-fkeft`, and a standing caveat in
# docs/lifecycle-composition.md). The re-measurement that authorised this
# found one still open — the shell read a visit's subject from the `tracks`
# edge and Go read only the `gc.continuation_group` stamp, so the same
# conversation could show held on one board and unheld on the other; on
# gc-toolkit's last seven days that is 5 of 49 visits, and an anchor whose
# visit is missed is promoted to HIGH and reported as needing attention it is
# already getting. Deleting a renderer cannot fix a divergence; deleting the
# duplicate can, and did (the fix landed in internal/source/facts.go with
# this change).
#
# IT IS ALSO FASTER, which is the part that makes this a free trade rather
# than a principled loss. Measured 2026-08-24 on the live five-rig city,
# `--json --limit=0`: helm-svc 6.0 / 6.6 / 7.1s COLD against this script's
# 51.9s cold. The Go gather is concurrent and pays no `jq` fork per rig per
# query.
#
# WHAT STAYED HERE. `open`, `react` and `takeaway` are above and are
# untouched: they are WRITES, they have no Go counterpart, and helm-svc's one
# write route (POST /helm/open) is implemented by shelling out to this
# script's `open`. This file is now the write half of the surface and a thin
# reader in front of the read half.

# helm_svc_bin — the built binary, or nothing.
#
# The binary is built OUT OF BAND by assets/scripts/gc-helm-build.sh and cached
# under the helm service's state root; this resolves the same location that
# script publishes to, cheapest source first. It deliberately does NOT ask
# `gc service list` the way gc-helm-build.sh can afford to: this is the path a
# tmux keypress takes, and a subprocess round-trip per glance to rediscover a
# path that four env vars already name is a cost with no answer behind it.
#
# Prints nothing (rc 0) when there is no binary. Absence is a NORMAL state — a
# city that has never run the build order has none — so it is a value the
# caller handles, not an error thrown from a resolver.
helm_svc_bin() {
    if [ -n "${GC_HELM_SVC_BIN:-}" ]; then
        # An explicit override wins even when it is broken: silently falling
        # back to a different binary than the operator named is how you debug
        # the wrong thing for an hour.
        [ -x "$GC_HELM_SVC_BIN" ] && printf '%s' "$GC_HELM_SVC_BIN"
        return 0
    fi
    _hsb_svc="${GC_HELM_SERVICE_NAME:-helm}"
    _hsb_root="${GC_SERVICE_STATE_ROOT:-}"
    if [ -z "$_hsb_root" ]; then
        for _hsb_city in "${GC_CITY_ROOT:-}" "${GC_CITY_PATH:-}" "${GC_CITY:-}"; do
            [ -n "$_hsb_city" ] || continue
            [ -d "$_hsb_city/.gc/services" ] || continue
            _hsb_root="$_hsb_city/.gc/services/$_hsb_svc"
            break
        done
    fi
    if [ -z "$_hsb_root" ]; then
        # No env at all: walk up from this script, which is inside a rig
        # checkout under the city root. Covers a human running the tool
        # straight out of a clone.
        _hsb_probe="$SCRIPT_DIR"
        while [ -n "$_hsb_probe" ] && [ "$_hsb_probe" != "/" ]; do
            if [ -d "$_hsb_probe/.gc/services" ]; then
                _hsb_root="$_hsb_probe/.gc/services/$_hsb_svc"
                break
            fi
            _hsb_probe=$(dirname "$_hsb_probe")
        done
    fi
    [ -n "$_hsb_root" ] || return 0
    [ -x "$_hsb_root/bin/helm-svc" ] && printf '%s' "$_hsb_root/bin/helm-svc"
    return 0
}

# run_helm_svc <verb> <cache-slot> [args…] — the whole of both verbs.
#
# THE CACHE IS THIS SCRIPT'S, NOT THE SERVICE'S, and it caches RENDERED BYTES
# rather than a gather. helm-svc's CLI path is deliberately daemonless and
# uncached (see cmd/helm-svc/board.go): it pays the gather so that `prefix+b`
# works when the sidecar is down. That is the right trade for correctness and
# the wrong one for a keypress — the tmux picker re-opens the board on every
# glance, and 6s per glance is a different tool from 0.05s per glance. So the
# cheap layer lives at the only place that knows a glance is a repeat: here.
#
# Only rc=0 is cached. A failed gather must never be served for a TTL: "0
# anchors" and "we could not look" are opposite answers and only one of them
# means nothing needs you. That was this script's own rule when it did the
# gathering and it survives the move unchanged.
#
# THE SLOT IS KEYED BY THE WHOLE FORWARDED ARGV, not just by the verb. Every
# flag that reaches helm-svc changes the bytes it prints — `--json` picks a
# different representation entirely, `--limit` picks how many rows, `--since`
# picks which window — so a coarser key serves one caller's answer to another's
# question for a whole TTL. That is not a stale board, which at least says
# something true about an earlier moment; it is a WRONG one. The live case is
# concrete: tmux-pick-helm.sh runs `--json --limit=36`, and a `--limit=2` typed
# at a prompt 40 seconds earlier would silently give the picker two rows.
run_helm_svc() {
    _rhs_verb="$1"; shift
    _rhs_slot="$1"; shift

    _rhs_refresh=0
    # Rotate argv: pop from the front, push back what helm-svc should see.
    # The cache-control flags are OURS — helm-svc has no cache to bust — so
    # they are consumed here and never forwarded. Everything else, including
    # every validation decision, belongs to helm-svc: one flag parser for one
    # board is the entire point of this file getting shorter.
    _rhs_n=$#
    _rhs_i=0
    while [ "$_rhs_i" -lt "$_rhs_n" ]; do
        _rhs_a="$1"; shift; _rhs_i=$((_rhs_i + 1))
        case "$_rhs_a" in
            --refresh|--no-cache) _rhs_refresh=1 ;;
            # Answer help from THIS tool: helm-svc's own usage covers its
            # subcommand alone, and a caller typing `gc-helm --help` is asking
            # about open/react/takeaway too.
            -h|--help)            usage; exit 0 ;;
            *)                    set -- "$@" "$_rhs_a" ;;
        esac
    done
    # cksum over the forwarded argv, one line per argument so two spellings of
    # the same flag list cannot collide by concatenation ("--limit 3" vs
    # "--limit3"). The verb stays readable in the name so the cache directory
    # can be understood at a glance and bust_cache's glob stays obvious.
    _rhs_key=$(printf '%s\n' "$@" | cksum | cut -d' ' -f1)
    _rhs_cache="$CACHE_DIR/render1-$_city_key.$_rhs_slot.$_rhs_key"

    _rhs_now=$(date -u +%s)

    if [ "$_rhs_refresh" -eq 0 ] && [ -f "$_rhs_cache" ]; then
        _rhs_age=$(cache_age "$_rhs_cache" "$_rhs_now")
        if [ "$_rhs_age" -ge 0 ] && [ "$_rhs_age" -le "$CACHE_TTL" ]; then
            tail -n +2 "$_rhs_cache"
            return 0
        fi
    fi

    _rhs_bin=$(helm_svc_bin)
    if [ -z "$_rhs_bin" ]; then
        # DEGRADED, NOT DEAD. A missing binary is a build that has not run, not
        # a broken city, and the operator asking for the board is usually the
        # least able to do anything about it in that moment. A cached answer
        # with its age stated out loud beats no answer; the age goes to stderr
        # so it cannot corrupt the --json contract, and it is stated on EVERY
        # replay rather than only past some threshold, because the reader — not
        # this script — knows whether a nine-minute-old board is good enough.
        if [ -f "$_rhs_cache" ]; then
            _rhs_age=$(cache_age "$_rhs_cache" "$_rhs_now")
            echo "$PROG: helm-svc is not built — replaying a $_rhs_verb cached ${_rhs_age}s ago. Build it: assets/scripts/gc-helm-build.sh" >&2
            tail -n +2 "$_rhs_cache"
            return 0
        fi
        cat >&2 <<MSG
$PROG: the $_rhs_verb is served by helm-svc and no binary is built, so there is
nothing to render and nothing cached to replay.
  build now: assets/scripts/gc-helm-build.sh
  automatic: the 'helm-build' order (orders/helm-build.toml)
  override:  GC_HELM_SVC_BIN=/path/to/helm-svc
MSG
        exit 3
    fi

    _rhs_tmp=$(mktemp -d 2>/dev/null) || { echo "$PROG: could not allocate temp dir" >&2; exit 3; }
    trap 'rm -rf "$_rhs_tmp"' EXIT INT TERM HUP

    # stdout is captured so a failure renders NOTHING; stderr streams straight
    # through, so a PARTIAL-gather warning still reaches the operator live.
    if "$_rhs_bin" "$_rhs_verb" "$@" > "$_rhs_tmp/out"; then
        _rhs_rc=0
    else
        _rhs_rc=$?
    fi

    if [ "$_rhs_rc" -ne 0 ]; then
        rm -rf "$_rhs_tmp"
        trap - EXIT INT TERM HUP
        # helm-svc has already said what went wrong on stderr, and its exit
        # codes are this script's codes (0 ok / 2 usage / 3 gather) — so pass
        # the number through rather than translating it.
        exit "$_rhs_rc"
    fi

    cat "$_rhs_tmp/out"

    # Cache last: a write failure must not cost the caller the answer they
    # already have. Written through a temp + rename so a concurrent glance
    # never reads a half-written board.
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
    if [ -d "$CACHE_DIR" ]; then
        { printf '%s\n' "$_rhs_now"; cat "$_rhs_tmp/out"; } > "$_rhs_cache.tmp.$$" 2>/dev/null \
            && mv "$_rhs_cache.tmp.$$" "$_rhs_cache" 2>/dev/null || rm -f "$_rhs_cache.tmp.$$" 2>/dev/null || true
    fi

    rm -rf "$_rhs_tmp"
    trap - EXIT INT TERM HUP
    return 0
}

# cache_age <file> <now-epoch> — seconds since the cache line-1 stamp, or a
# NEGATIVE number when there is no usable stamp.
#
# Negative rather than "very large" so the caller's freshness test and its
# staleness message read the same value: a corrupt stamp must fail the
# `-le TTL` test, and a huge positive number would pass a `-ge 0` guard while
# claiming the board is from 1970.
cache_age() {
    _ca_ts=$(head -n1 "$1" 2>/dev/null || echo '')
    case "$_ca_ts" in ''|*[!0-9]*) printf '%s' -1; return 0 ;; esac
    printf '%s' "$(( $2 - _ca_ts ))"
}

cmd_board()  { run_helm_svc board  board  "$@"; }
cmd_closed() { run_helm_svc closed closed "$@"; }

# ── Dispatch ─────────────────────────────────────────────────────────
case "${1:-}" in
    open)          shift; cmd_open "$@" ;;
    react)         shift; cmd_react "$@" ;;
    takeaway)      shift; cmd_takeaway "$@" ;;
    board)         shift; cmd_board "$@" ;;
    closed)        shift; cmd_closed "$@" ;;
    -h|--help|help) usage; exit 0 ;;
    ''|-*)         cmd_board "$@" ;;          # no verb, or a board flag → board (back-compat)
    *)             echo "$PROG: unknown verb '$1' (try: board, closed, open, react, takeaway, help)" >&2; usage; exit 2 ;;
esac
