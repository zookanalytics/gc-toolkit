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
#   gc-helm takeaway <bead-id> "<text>" [--by …] [--release]  set the board-visible takeaway headline (≤140 chars, ENFORCED)
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
#                      SHAPE, NOT BAND, since tk-9tbbk.3. The flag still
#                      reports exactly this, but the band splits on WHO the
#                      row needs: an idle frontier with no dead owner and no
#                      authored takeaway wants a DISPATCH, which no operator
#                      performs, so it stands down to LOW (see the ranking
#                      heuristic below). A consumer asking "is there open
#                      work with nothing in it" still reads this field.
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
#             MINUS the dispatch stand-down (tk-9tbbk.3): a stranded row
#             with NO dead-owner child and NO authored takeaway is asking
#             for an assignment, which is a dispatcher action and not an
#             operator one, so it bands LOW and says "awaiting dispatch"
#             instead. Twelve of the fourteen HIGH rows on the 2026-08-23
#             board were that one derived sentence. What stays HIGH is what
#             a human can act on: a recovery, or a row somebody wrote a
#             NEEDS sentence for.
#   ELEVATED  a `decision` (human-gated); a `human` bead (same reason); an
#             otherwise-NORMAL anchor gone stale (> STALE_DAYS days); OR a
#             still-moving anchor that has a dead-owner (stuck) in-progress
#             child to recover.
#   NORMAL    active frontier (work in flight, OR an open visit — a
#             conversation is held).
#   LOW       empty epic (0 children), complete convoy (all closed), a
#             CHILDLESS `parked` bead (floored by band, never by score), an
#             ANSWERED human-gated row (the tk-b3rga stand-down), or a
#             decomposed row awaiting a dispatch (the tk-9tbbk.3 stand-down).
#             A parked bead that decomposed is banded by its children like
#             any other roll-up anchor — the floor claims it wants nothing,
#             which stops being true the moment open work hangs under it.
#             LOW is "wants nothing from YOU", not "hidden": these rows stay
#             in the ranked table, and only kind `parked` moves to the web
#             app quiet section.
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
# `parked` rows draw on a SEPARATE budget, GC_HELM_MAX_PARKED (default
# 15), instead of competing for the same slots: they are band-floored to
# LOW and so sort last, and under one shared cap they would be the first
# rows trimmed — which would re-hide, on the operator's actual surface,
# exactly the beads the kind exists to surface.
#
# Exit codes:
#   0   board rendered / verb succeeded
#   2   usage error
#   3   missing dependency (jq / gc), could not enumerate rigs, or the
#       gather failed (nothing cached — a transient gather failure must
#       never be served as a "0 anchors" all-clear). The rig-enumeration
#       failures all share this code but deliberately NOT the message: a
#       timeout kill, gc exiting non-zero, an empty / unparseable /
#       wrong-shaped answer, and a legitimately rigless city each name
#       their own operator move, because the code alone cannot tell them
#       apart and for a non-CLI caller the code plus the sentence is the
#       whole signal (tk-lzdty).
#   4   verb runtime failure (e.g. bead not found, visit filing failed)
#
# Test hook: GC_HELM_FIXTURE=<dir> — when set, the board reads
# canned data instead of Dolt/sessions: <dir>/anchors.ndjson (one anchor
# object per line, the gathered shape), <dir>/visits.json (a JSON array
# of subject ids with an open visit), <dir>/inflight.json (a JSON object,
# work-bead id -> the session names of the live workflows over it), and
# <dir>/sessions.json (the `gc session list --json` shape, for both
# liveness maps). Keeps the render/rank/glyph assertions hermetic, and is
# the only way to exercise the render's liveness re-check on its own —
# through the real gather a dead workflow is dropped before the render
# ever sees it, so each of the two liveness checks would mask the other.
# Unset in normal use.

set -eu

PROG="gc-helm"

# ── Tunables ─────────────────────────────────────────────────────────
STALE_DAYS=14                                   # > this many days since update → staleness bump
XREF_CAP=5                                       # max cross-rig refs that count toward weight
MAX_ROWS="${GC_HELM_MAX_ROWS:-50}"          # default row cap (--limit=0 disables)
MAX_PARKED="${GC_HELM_MAX_PARKED:-15}"      # separate budget for `parked` rows (see below)
CACHE_TTL="${GC_HELM_CACHE_TTL:-45}"        # seconds the gather cache stays fresh
TAKEAWAY_MAX=140                            # hard cap on a takeaway headline, in CODEPOINTS
FIXTURE="${GC_HELM_FIXTURE:-}"              # test hook (see header)
# Fall back to defaults on a non-numeric override so `set -e` arithmetic
# (the cap + cache-age tests) can't crash the board on a bad env value.
case "$MAX_ROWS"   in ''|*[!0-9]*) MAX_ROWS=50 ;; esac
case "$MAX_PARKED" in ''|*[!0-9]*) MAX_PARKED=15 ;; esac
case "$CACHE_TTL" in ''|*[!0-9]*) CACHE_TTL=45 ;; esac

usage() {
    cat >&2 <<'EOF'
Usage:
  gc-helm [board] [--json] [--limit=N] [--timeout=SECONDS] [--refresh]
  gc-helm open  <bead-id> [--reason "..."] [--body "..."]  file a visit on the bead (a converse session holds the conversation)
  gc-helm react <bead-id> [--reason "..."]  sling a first reaction (self-heals a takeaway-less row)
  gc-helm takeaway <bead-id> "<text>" [--by host|proactive|converse] [--waiting-on <bead-id>]... [--release]  set the board-visible takeaway headline (≤140 chars, ENFORCED)

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
# subject ids with an open visit), line 3 = the in-flight map (one JSON
# object, work-bead id -> the session names of the live workflows over
# it), lines 4.. = anchors ndjson (portable: no stat(1) / find(1) mtime
# flags, which differ GNU vs BSD). The file name carries the format
# ("board2-"), so a stale cache written by an older layout — v1
# "anchors-", or "board-" without the in-flight line — is simply never
# read rather than being parsed one line out of register.
CACHE_DIR="${TMPDIR:-/tmp}/gc-helm-cache.$(id -u 2>/dev/null || echo 0)"
_city_key=$(printf '%s' "${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-default}}}" | cksum | cut -d' ' -f1)
CACHE_FILE="$CACHE_DIR/board2-$_city_key.ndjson"

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
    # the operator's front door, so keying it on the stamp alone means `gc helm
    # open` cheerfully files the duplicate the guard exists to prevent. Match on
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
    INFLIGHT_FILE="$TMP/inflight.json"
    printf '{}\n' > "$INFLIGHT_FILE"
    # Blocker id -> status, for the `waiting_on` edges. Resolved AFTER the
    # cache block and never stored in it (see resolve_waiting_status).
    WAITING_FILE="$TMP/waiting.json"
    printf '{}\n' > "$WAITING_FILE"
    # Per-rig open-bead snapshots, written once and read by three consumers
    # (visits, the metadata-keyed anchor kinds, the in-flight join). Kept as
    # FILES because a rig's open set carries every bead's description and
    # notes — the same payload the anchor gather must keep off argv.
    OPEN_DIR="$TMP/open"
    mkdir -p "$OPEN_DIR"
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

    # ── Session list ─────────────────────────────────────────────────
    # Fetched BEFORE the gather because two consumers need it: the
    # in-flight join (which resolves only the workflows whose session is
    # alive, so the gather's convoy reads stay bounded by live polecats
    # rather than by every husk in the store) and the owner-liveness map
    # below. Deliberately OUTSIDE the cache — session state is the one
    # fact that must be fresh on every glance, so a workflow whose polecat
    # died mid-TTL stops counting as movement immediately.
    if [ -n "$FIXTURE" ]; then
        sess_raw=$([ -f "$FIXTURE/sessions.json" ] && cat "$FIXTURE/sessions.json" || printf '{}')
    else
        sess_raw=$(gcq session list --state all --json)
    fi
    # Live session names+aliases, as a JSON array. Same liveness rule the
    # render applies to a child's owner: archived/closed = dead, absent
    # from the list entirely = dead. Never keys off .running (null for an
    # active session mid-churn).
    LIVE_SESSIONS=$(printf '%s' "$sess_raw" | jq -c '
        [ (.sessions // . // [])[]?
          | select(((.state // "") != "archived") and ((.state // "") != "closed"))
          | [ (.session_name // empty), (.alias // empty) ][] ]' 2>/dev/null || printf '[]')
    printf '%s' "$LIVE_SESSIONS" | jq -e 'type=="array"' >/dev/null 2>&1 || LIVE_SESSIONS='[]'

    # ── Gather (cached: the expensive part) ──────────────────────────
    gathered_from_cache=0
    if [ -n "$FIXTURE" ]; then
        # Hermetic test path: anchors + visits + in-flight come from the
        # fixture, no Dolt.
        [ -f "$FIXTURE/anchors.ndjson" ] && cat "$FIXTURE/anchors.ndjson" > "$ANCHORS"
        [ -f "$FIXTURE/visits.json" ] && cat "$FIXTURE/visits.json" > "$VISITS_FILE"
        [ -f "$FIXTURE/inflight.json" ] && cat "$FIXTURE/inflight.json" > "$INFLIGHT_FILE"
    elif [ "$REFRESH" -eq 0 ] && [ -f "$CACHE_FILE" ]; then
        ts=$(head -n1 "$CACHE_FILE" 2>/dev/null || echo 0)
        case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
        if [ "$ts" -gt 0 ] && [ $((NOW_EPOCH - ts)) -le "$CACHE_TTL" ] && [ $((NOW_EPOCH - ts)) -ge 0 ]; then
            sed -n '2p' "$CACHE_FILE" > "$VISITS_FILE" 2>/dev/null || printf '[]\n' > "$VISITS_FILE"
            sed -n '3p' "$CACHE_FILE" > "$INFLIGHT_FILE" 2>/dev/null || printf '{}\n' > "$INFLIGHT_FILE"
            tail -n +4 "$CACHE_FILE" > "$ANCHORS" 2>/dev/null || : > "$ANCHORS"
            gathered_from_cache=1
        fi
    fi

    if [ -z "$FIXTURE" ] && [ "$gathered_from_cache" -eq 0 ]; then
        gather_open_beads # writes $OPEN_DIR/<rig>.json (one query per rig)
        gather_anchors    # writes $ANCHORS
        gather_meta_anchors # appends the metadata-keyed kinds to $ANCHORS
        gather_visits     # writes $VISITS_FILE (one JSON array line)
        gather_inflight   # writes $INFLIGHT_FILE (one JSON object line)
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
            { printf '%s\n' "$NOW_EPOCH"; cat "$VISITS_FILE"; cat "$INFLIGHT_FILE"; cat "$ANCHORS"; } > "$CACHE_FILE.tmp.$$" 2>/dev/null \
                && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_FILE.tmp.$$" 2>/dev/null || true
        fi
    fi

    # ── Blocker liveness for the `waiting_on` edges ──────────────────
    # Outside the cache on purpose, and outside the gather-failure gate: see
    # resolve_waiting_status. Runs on the cached path too, because a cached
    # anchor's EDGES are still current even when its blocker's status is not.
    resolve_waiting_status
    WAITMAP=$(cat "$WAITING_FILE" 2>/dev/null || printf '{}')
    printf '%s' "$WAITMAP" | jq -e 'type=="object"' >/dev/null 2>&1 || WAITMAP='{}'

    # ── Visit map (held glyph): subject ids with an open visit ────────
    # An anchor is HELD when an open visit bead (task_kind=visit) names
    # it in gc.continuation_group — the conversation exists (a converse
    # session holds it, or pool demand is about to spawn one). Gathered
    # with the anchors (gather_visits) and cached alongside them; both
    # verbs that change visit presence bust the cache.
    VISITS=$(cat "$VISITS_FILE" 2>/dev/null || printf '[]')
    printf '%s' "$VISITS" | jq -e 'type=="array"' >/dev/null 2>&1 || VISITS='[]'

    # ── In-flight map (work bead -> live workflow sessions) ───────────
    # The fix for the false-stranded board. A work bead dispatched by
    # `gc sling` keeps status=open and assignee=null for its whole life —
    # graph.v2 carries the in-flight state on the WORKFLOW (root bead +
    # step beads), never on the work bead — so a child being actively
    # implemented is byte-for-byte identical, in bead state, to one nobody
    # has touched. Reading only child status makes the board call live work
    # "stranded, assign or visit". This map is the missing join; the render
    # re-checks each session against the FRESH session list, so a cached
    # entry whose polecat has since died stops counting immediately.
    INFLIGHT=$(cat "$INFLIGHT_FILE" 2>/dev/null || printf '{}')
    printf '%s' "$INFLIGHT" | jq -e 'type=="object"' >/dev/null 2>&1 || INFLIGHT='{}'

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
# Is a child bead covered by a LIVE graph.v2 workflow? `gc sling` leaves the
# work bead at status=open/assignee=null and puts the in-flight state on the
# workflow, so this is the only way a polecat mid-implementation is visible at
# all. Liveness is re-derived HERE, against the fresh session list, rather than
# trusted from the cached map: the gather can only record which workflows were
# live when it ran, and a polecat that drained since must stop counting at once
# — otherwise the fix would trade a false "stranded" for a false "in flight",
# which is the worse lie on a board whose job is to say what needs a human.
def wf_live($id):
    (($inflight[$id]) // []) as $names
    | if ($names|type) != "array" then false
      else any($names[]; owner_live(.)) end;

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
    # MOVING — a child demonstrably being worked, by EITHER mechanism:
    #   1. it is claimed (status=in_progress) and its owning session is live;
    #   2. a live workflow covers it (the sling case: the work bead itself
    #      never leaves status=open/assignee=null, so mechanism 1 can never
    #      see it — this is the whole false-stranded defect).
    # Unioned by id, so a child matched both ways is counted once.
    | [ $openset[] | select((.status=="in_progress" and owner_live(.assignee)) or wf_live(.id)) | .id ] as $live_heads
    | ($live_heads|length) as $inprog_live
    # STUCK — claimed, owner dead, and no live workflow standing behind it.
    # The workflow clause matters: a re-dispatched bead can carry a stale
    # assignee from the session that died while a live workflow works it now,
    # and calling that "dead owner" would be the same error in a new place.
    | [ $openset[] | select(.status=="in_progress" and (owner_live(.assignee)|not) and (wf_live(.id)|not)) | .id ] as $dead_owner_heads
    | ($dead_owner_heads|length) as $inprog_dead
    # How many movers are moving via a workflow rather than a claim — the
    # quantity the board was blind to. Surfaced in --json so the join can be
    # audited without re-deriving it.
    | [ $openset[] | select(wf_live(.id)) | .id ] as $inflight_heads
    | ($inflight_heads|length) as $inflight_n
    | ([$openset[]|select((.assignee // "") != "")]|length) as $assigned
    # Idle heads: unclaimed/unowned open children, MINUS anything a live
    # workflow is already carrying — those are not idle, they are in flight.
    | [ $openset[] | select((.assignee // "")=="" or .status!="in_progress")
                  | . as $c | select(($live_heads | index($c.id)) == null) | $c.id ] as $open_ids
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
    # ── Is the thing this subject was waiting on still open? ─────────
    # `waiting_on` is the set of ids this bead depends on by a `blocks` edge —
    # for a parked subject, the work a converse sitting routed out of it. The
    # board re-asks the question the takeaway string froze at dispatch time:
    # DERIVED here, never stored, so it needs nothing from the
    # never-clearing stored `blocked` status of tk-puh9d.
    #
    # A blocker counts as LANDED only on a positive `closed` from the fresh
    # $waitmap. An id the map cannot answer for — a store in another rig, an
    # `external:` reference, a query that timed out — reads as still open, so
    # the row keeps its pre-fix LOW band. Wrong in the quiet direction on
    # purpose: a missed promotion costs a glance, a false "go dispose of this"
    # invites closing a subject whose work is still in flight.
    | (($a.waiting_on // []) | if type=="array" then . else [] end) as $waiting
    | ([ $waiting[] | select((($waitmap[.] // "") | tostring) != "closed") ]) as $waiting_open
    # The LLM-authored takeaway (host or proactive), if any: the board-visible
    # headline of what this anchor concluded / what it needs. Collapse any
    # internal whitespace (a stray newline would break the table) and trim.
    # Bound BEFORE the bands because $ruled below reads it.
    | (($a.takeaway // "") | gsub("[[:space:]]+";" ") | gsub("^ | $";"")) as $takeaway
    # HUMAN-GATED: no agent will take this — it moves only when a human moves it.
    # The two kinds that say so by BEING what they are, plus the marker that says
    # so on an ordinary bead. The marker clause is not redundant with the kinds:
    # a bead carrying BOTH gc.routed_to=human and a gc.takeaway is emitted twice
    # on purpose, once per marker, and the id-dedup below keeps the HIGHER band —
    # so a rule that quiets the `human` row is undone by its `parked` twin unless
    # the twin is recognised as the same human-gated bead.
    | ((($a.routed_to // "") | tostring) == "human"
       or $a.source=="decision" or $a.source=="human") as $human_gated
    # DISPOSITION DUE: it was waiting on something, and every one of those has
    # landed. The row is no longer "wants nothing" — it wants a disposition.
    #
    # NOT for a human-gated subject, twin included. The promotion exists to lift a
    # row out of the parked LOW FLOOR where nobody would look at it again; a
    # human-gated bead was never in that floor, and $ruled below answers for the
    # same state at the volume the operator asked for. Both firing would put an
    # ELEVATED duplicate of every stood-down row back on the board.
    | ($a.source=="parked" and ($waiting|length) > 0 and ($waiting_open|length) == 0
       and (($human_gated)|not)) as $disposition_due
    # RULED — the STAND-DOWN state: a human-gated row that has already been
    # answered, and whose recorded waits have all landed.
    #
    # A decision or a human-routed bead is banded by what it IS, and what it is
    # never changes while the bead is open — so the row asked for the operator on
    # the day it was filed and went on asking after they answered it. Measured
    # 2026-08-23: seven ELEVATED rows on a 62-row board carried a takeaway
    # recording their own ruling, one of them (tk-z130v) for THIRTY DAYS. Nothing
    # else in the city re-reads a takeaway, and converse never closes a subject by
    # contract, so no other actor could ever retire them.
    #
    # Same shape as $disposition_due: derived per render from state the bead
    # already carries, storing nothing, so a re-opened question stands back up by
    # itself. The wait clause is what keeps it honest — a decision whose
    # `--waiting-on` work is still open has not finished being a decision.
    | ($human_gated and ($takeaway|length) > 0 and ($waiting_open|length) == 0) as $ruled
    # AWAITING DISPATCH — the stand-down one band up, and the same rule as
    # $ruled: band a row by WHO it needs, not by what it IS (tk-b3rga).
    #
    # An idle decomposed anchor bands HIGH, and HIGH says the operator must act.
    # But the phrase it renders in that band names its own actor, and that actor
    # is not the operator: "decomposed, idle — assign or visit". Assigning open
    # work to a pool is a DISPATCH — gc sling and the dispatching agents do it,
    # no human does it by hand. Measured 2026-08-23: twelve of the fourteen HIGH
    # rows on the live board carried that one byte-identical sentence, so 86% of
    # the loudest band was a single repeated request addressed to a machine
    # (tk-9tbbk.3, subject tk-jr8rw).
    #
    # The takeaway clause is what separates a mechanical constant from a
    # judgement: everywhere else here an authored takeaway WINS the NEEDS cell,
    # because somebody looked at the row and said what it wants, and quieting
    # one would overrule that. It holds the other two HIGH rows of that census
    # in place — sl-kg9z6, whose takeaway reports PRs held on the operator, and
    # tk-6v7nm, whose takeaway ends "the operator call" — both genuinely
    # operator-facing, and both keep their band.
    #
    # A dead-owner child is NOT undispatched: it was dispatched and the worker
    # fell over, which is a recovery, so it keeps its own phrase and its band.
    # And $held means the attention is already on the row — the clause the
    # stranded band has always carried.
    #
    # LOW cannot hide the one thing that would falsify the claim. An idle child
    # no agent will take carries gc.routed_to=human, and every such open bead is
    # gathered as a `human` anchor in its OWN right at ELEVATED, so it holds a
    # row on this board whatever the band of its parent. What a quiet parent
    # hides is exactly the work a dispatcher can take.
    | ($m > 0 and $open > 0 and $inprog_live == 0 and $inprog_dead == 0
       and ($held|not) and ($takeaway|length) == 0) as $awaiting_dispatch
    # severity band. A held anchor is active work via its conversation,
    # not via in-progress child polecats — so "0 in-progress" is NOT
    # stranded when a visit is open. Stranded/HIGH is reserved for a
    # decomposed anchor with open children, zero in-progress, AND no
    # open visit.
    # The metadata-keyed kinds are placed ahead of the count branches because
    # a CHILDLESS one has no roll-up to band on, and falling through would read
    # every such bead as an empty anchor. `human` is ELEVATED for the same
    # reason a decision is: gc.routed_to=human means no agent will take it.
    # Both stand DOWN once $ruled — the row was answered, and a recorded ruling
    # that keeps asking is the loudest kind of noise. A ruled row that DECOMPOSED
    # is banded by its roll-up instead, exactly as a decomposed parked subject is:
    # "answered" is a claim about the bead, and open work hanging under it
    # falsifies the claim (tk-a9k0l).
    # `parked` is LOW for the opposite reason — the conversation reached a
    # takeaway and wants nothing, it only has to stay FINDABLE, so the band
    # floor keeps it out of the contest with real attention items whatever its
    # priority or age.
    #
    # …but only while it HAS no children. The floor is a claim about the bead —
    # "wants nothing" — and open work hanging under it falsifies that claim, so
    # a decomposed parked subject is banded by its roll-up like any other
    # anchor: HIGH when its frontier is stranded, NORMAL when something is
    # moving, LOW again once every child has closed (via the $open==0 branch).
    # The children are how the canonical converse shape is visible at all: a
    # sitting files the work it routes as a CHILD of the subject, and `bd`
    # refuses a parent→descendant `blocks` edge, so $waiting is empty for
    # exactly the subjects that decomposed (tk-a9k0l, tk-2cyxo).
    | (if $a.source=="unowned" then "HIGH"
       elif ($ruled and $m==0) then "LOW"
       elif ((($ruled)|not) and ($a.source=="decision" or $a.source=="human")) then "ELEVATED"
       elif $disposition_due then "ELEVATED"
       elif ($a.source=="parked" and $m==0) then "LOW"
       elif $m==0 then "LOW"
       elif $open==0 then "LOW"
       # LOW, not NORMAL, for the reason $ruled is: NORMAL is stale-bumped past
       # STALE_DAYS, so a NORMAL stand-down would hold for two weeks and then
       # put the same rows back in the contest. Five of the nine rows measured
       # for tk-9tbbk.3 were already 12 days old or more.
       elif $awaiting_dispatch then "LOW"
       elif ($open>0 and $inprog_live==0 and ($held|not)) then "HIGH"
       elif ($inprog_dead>0) then "ELEVATED"
       else "NORMAL" end) as $sev0
    | (if ($sev0=="NORMAL" and $stale > '"$STALE_DAYS"') then "ELEVATED" else $sev0 end) as $sev
    | ($m + prio_w($a.priority) + ([$xrefs|length, '"$XREF_CAP"'] | min)) as $weight
    # one-line frontier summary
    | (if $inprog_dead>0 then " · \($inprog_dead) stuck (dead owner)" else "" end) as $deadsfx
    | (if $a.source=="unowned" then "unowned convoy — no owning bead"
       # Parallel to the parked phrase below, and for the same reason: the row is
       # reporting what it IS, because it has no roll-up to report instead. A
       # ruled row that decomposed skips this and reports its counts.
       elif ($ruled and $m==0) then "ruled — takeaway recorded"
       elif ((($ruled)|not) and $a.source=="decision") then "human-gated decision"
       elif ((($ruled)|not) and $a.source=="human") then "routed to the operator — no agent will take it"
       elif $disposition_due then "parked · blocker landed"
       elif ($a.source=="parked" and ($waiting_open|length) > 0)
            then "parked · waiting on \($waiting_open|length)"
       # A NAMED wait outranks the roll-up above: the sitting stated it, and
       # that is why this row is quiet. Below it, a parked subject that
       # decomposed reports its frontier through the same count phrases as
       # every other roll-up anchor, so the phrase explains the band it just
       # got from those counts.
       elif ($a.source=="parked" and $m==0)
            then "conversation parked — takeaway recorded"
       elif $m==0 then "empty — no children"
       elif $open==0 then "all \($m) closed · 0 open"
       elif ($inprog_live==0 and $inprog_dead>0 and ($held|not)) then "\($open) open · \($inprog_dead) stuck (dead owner)"
       elif ($inprog_live==0 and $held) then ("\($open) open · in conversation" + $deadsfx)
       # "(stranded)" is an alarm word, and it would contradict the band this row
       # just got. What is true of it is narrower, and short: FRONTIER is padded
       # to 36 columns and rpad truncates without a gutter.
       elif $awaiting_dispatch then "\($open) open · awaiting dispatch"
       elif $inprog_live==0 then "\($open) open · 0 in flight (stranded)"
       else "\($open) open · \($inprog_live) in flight" + $deadsfx end) as $frontier
    # NEEDS is the one-glance answer for a human: the LLM takeaway sentence
    # when one exists, else a TERSE deterministic STATE phrase — never a
    # bead-id list. The mechanical heads/xref ids move to --json only
    # (open_heads, cross_rig_refs), so the human table stays explanatory and
    # cannot emit a raw/truncated bead-id.
    | (if $disposition_due then "blocker landed — dispose or resume"
       # A ruled row spends its NEEDS on the DISPOSITION for the same reason, and
       # with the same trade. The takeaway is not stale here — it is the ruling —
       # but NEEDS answers "what does this row want from me", and what a ruled row
       # wants is to be closed or re-opened, not re-read. The ruling itself stays
       # on the wire in `takeaway`, where nothing truncates it; in this table it
       # was the longest cell in that column (n=20 over the 140-char cap on
       # the 2026-08-23 board, max 1343) and the least actionable.
       #
       # Only while the row has no roll-up. A ruled row with children reports the
       # takeaway and is banded by those children, so its two halves agree.
       elif ($ruled and $m==0) then "ruled — close or extend"
       elif ($takeaway|length) > 0 then $takeaway
       # Below here the takeaway is empty, so $ruled is false by construction and
       # the decision/human branches need no guard of their own.
       elif $a.source=="unowned" then "unowned — assign an owning bead"
       elif $a.source=="decision" then "operator decision"
       elif $a.source=="human" then "operator action"
       elif ($a.source=="parked" and $m==0) then "resume: prefix+a, then the bead id"
       elif $m==0 then "no children — decompose or assign"
       elif $open==0 then (if $a.source=="convoy" then "all \($m) closed — graduate" else "all \($m) closed — close or extend" end)
       elif ($inprog_live==0 and $inprog_dead>0 and ($held|not)) then "dead owner — recover or reassign"
       elif ($inprog_live==0 and $held) then "open to join"
       # NEEDS answers what this row wants from the reader, and for an idle row
       # with no takeaway the honest answer is nothing — what it wants is a
       # dispatch, which is not something the person reading this column does.
       elif $awaiting_dispatch then "awaiting dispatch — no operator action"
       # Reachable only for a row that is idle but does NOT stand down. The
       # takeaway short-circuit above owns every one of those today, so nothing
       # renders this; it is the fallback the frontier keeps in the same place.
       elif $inprog_live==0 then "decomposed, idle — assign or visit"
       else (if $inprog_dead>0 then "in flight — \($inprog_dead) stuck, recover"
             else ("in flight" + (if $held then " (in conversation)" else "" end)) end) end) as $needs
    | {
        id:$a.id, rig:$a.rig, kind:$a.kind, title:$a.title,
        severity:$sev, weight:$weight, held:$held,
        n_closed:$closed, m_total:$m, open:$open, in_progress:$inprog, assigned:$assigned,
        in_progress_live:$inprog_live, in_progress_dead:$inprog_dead, dead_owner:($inprog_dead>0),
        in_flight:$inflight_n, in_flight_heads:$inflight_heads,
        owned:(if ($a|has("owned")) then $a.owned else null end),
        stranded:($m>0 and $open>0 and $inprog_live==0 and ($held|not)),
        empty:($m==0 and $a.source!="decision" and $a.source!="unowned"
                    and $a.source!="human" and $a.source!="parked"),
        complete:($m>0 and $open==0),
        progress_mismatch:$pmismatch,
        stale_days:$stale, priority:$a.priority, cross_rig_refs:$xrefs,
        open_heads:$open_ids, dead_owner_heads:$dead_owner_heads,
        waiting_on:$waiting, waiting_on_open:$waiting_open,
        disposition_due:$disposition_due,
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
        --argjson inflight "$INFLIGHT" --argjson waitmap "$WAITMAP" \
        "$RENDER" < "$ANCHORS")
    TOTAL=$(printf '%s' "$FULL" | jq 'length')
    # ── Row cap, with a RESERVED budget for `parked` ─────────────────
    # A single rank-ordered cap would silently undo half of what the parked
    # kind is for. Parked is band-floored at LOW, so it sorts last by
    # construction, and the operator's own surface asks for 36 rows
    # (tmux-pick-helm.sh) against a board whose attention bands alone fill
    # most of that — so every parked row falls off the end, and a bead added
    # to the gather specifically so it could be FOUND is once again absent
    # from the board the operator actually reads.
    #
    # So the cap is split: attention rows keep the whole of --limit/MAX_ROWS
    # (their budget is not reduced by parked existing), and parked rows draw
    # on a separate MAX_PARKED. The two slices are re-merged by rank_score,
    # so the output stays one globally ranked array — `--json` is unchanged
    # in shape for the picker. `--limit=0` means ALL, both kinds.
    if [ "$EFFLIMIT" -gt 0 ]; then
        BOARD=$(printf '%s' "$FULL" | jq -c --argjson n "$EFFLIMIT" --argjson p "$MAX_PARKED" '
            ([.[] | select(.kind != "parked")] | .[0:$n])
          + ([.[] | select(.kind == "parked")] | .[0:$p])
          | sort_by(-.rank_score)')
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

    # >>> board-table-render
    printf '%s' "$BOARD" | jq -r --argjson needsw "$TAKEAWAY_MAX" '
def rpad($w): . as $s | ($s|tostring)[0:$w] as $t | $t + (($w - ($t|length)) as $g | if $g>0 then (" "*$g) else "" end);
# clip is the DISPLAY guard on the last column, and the ONLY place the board
# shortens something a human reads. NEEDS is prose and it is where the
# LLM-authored takeaway lands, so one 1876-char cell — a real one, on the live
# board — is not a wide column but a single row wrapping over every row below
# it. The cap is the same 140 the takeaway writer now enforces, so a conforming
# headline renders in FULL and this only ever fires on text that was stored
# before the gate existed or written around it. The ellipsis is deliberate: a
# clipped cell must say it was clipped, and `--json` still carries the whole
# string (both `needs` and `takeaway`) for anything that wants to read it.
#
# Prose only. It is NOT a general ellipsis policy: the mechanical heads and
# xref ids are --json-only by construction, so nothing in this column is an
# identifier, and clipping one would be the tk-mtuej defect one column over.
def clip($w): . as $s | if (($s|length) > $w) then (($s[0:$w-1]) + "…") else $s end;
# ID and RIG are sized to the widest value on THIS board (plus a gutter),
# never fixed: rpad truncates, and an identifier keeps its discriminator in
# the TAIL, so the old fixed 11 rendered sl-kg9z6.4.1, .2 and .9 as three
# identical "sl-kg9z6.4." cells — three anchors the operator could not tell
# apart (tk-mtuej). The floors keep a board of ordinary ids laid out as before.
# helm-svc board derives the same two widths (services/helm/cmd/helm-svc/board.go).
(([.[] | (.id|tostring|length)] + [10] | max) + 1) as $idw
| (([.[] | (.rig|tostring|length)] + [12] | max) + 1) as $rigw
| ( (" "|rpad(2)) + ("SEV"|rpad(9)) + ("ID"|rpad($idw)) + ("RIG"|rpad($rigw)) + ("KIND"|rpad(9)) + ("N/M"|rpad(7)) + ("FRONTIER"|rpad(36)) + "NEEDS" ),
( ("─"*1|rpad(2)) + ("─"*8|rpad(9)) + ("─"*($idw-1)|rpad($idw)) + ("─"*($rigw-1)|rpad($rigw)) + ("─"*8|rpad(9)) + ("─"*6|rpad(7)) + ("─"*35|rpad(36)) + ("─"*16) ),
( .[] | ((if .held then "●" else " " end)|rpad(2)) + ((.severity)|rpad(9)) + ((.id)|rpad($idw)) + ((.rig)|rpad($rigw)) + ((.kind)|rpad(9))
        # "—" means "this row has no roll-up", not "this KIND never has one":
        # a decision never does, and a human/parked bead does exactly when it
        # decomposed. Printing "—" over a real child set is what hid the open
        # children of a parked subject (tk-a9k0l).
        + ((if (.m_total==0 and (.kind=="decision" or .kind=="human" or .kind=="parked")) then "—"
            else "\(.n_closed)/\(.m_total)" end)|rpad(7))
        + ((.frontier)|rpad(36)) + ((.needs)|clip($needsw)) )
'
    # <<< board-table-render
    printf '\nLegend: HIGH=stranded/unowned · ELEVATED=open-decision/human/stale/stuck/blocker-landed · NORMAL=active · LOW=empty/complete/childless-parked/ruled\n'
    printf 'Kinds: epic/convoy/decision are roll-up anchors · human=routed to you · parked=a conversation with a takeaway (resume: prefix+a, then the id)\n'
    printf 'A parked row reading "blocker landed" was waiting on work that has since closed — it needs a disposition, not a re-read\n'
    printf 'A row reading "ruled" was answered and its routed work has landed — close or extend it; the ruling itself is in --json takeaway\n'
    printf 'A parked row with an N/M count decomposed into children and is banded by them — the takeaway is not the whole story there\n'
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

        # Decisions: human-gated; no child roll-up needed (it is banded by what
        # it IS). It does carry its `blocks` waiting edges, which are half of
        # the stand-down test ($ruled in the render): a decision whose
        # `--waiting-on` work is still open has not finished being a decision.
        decisions_raw=$(gcq bd list --db "$beads" --type decision --status open --json)
        printf '%s' "$decisions_raw" | jq -e 'type=="array"' >/dev/null 2>&1 || gather_mark "decisions@$name"
        decisions=$(as_array "$decisions_raw")
        printf '%s' "$decisions" | jq -c \
            --arg rig "$name" --arg prefix "$prefix" \
            '.[] | {id, title:(.title//""), kind:"decision", source:"decision", rig:$rig, prefix:$prefix,
                    priority:(.priority//3), updated_at:(.updated_at//""), description:(.description//""),
                    progress:null, children:[],
                    waiting_on:([ (.dependencies // [])[]
                                  | select(((.type // "") | tostring) == "blocks")
                                  | ((.depends_on_id // "") | tostring)
                                  | select(length > 0) ] | unique),
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

# ── Shared per-rig open-bead snapshot ────────────────────────────────
# ONE `bd list --status open,in_progress` per rig, written to
# $OPEN_DIR/<n>.json as {rig, prefix, beads:[…]}. Three consumers read it
# — gather_visits, gather_meta_anchors, gather_inflight — so widening the
# board from one of those queries to three costs no extra Dolt round
# trips. Kept on disk rather than in a variable: a rig's open set carries
# every bead's description and notes, the same payload gather_anchors
# takes care never to put on argv.
gather_open_beads() {
    _i=0
    printf '%s' "$RIGS" | jq -c '.[]' | while IFS= read -r rig; do
        _i=$((_i + 1))
        name=$(printf '%s' "$rig" | jq -r '.name')
        path=$(printf '%s' "$rig" | jq -r '.path')
        prefix=$(printf '%s' "$rig" | jq -r '.prefix')
        beads="$path/.beads"
        [ -d "$beads" ] || continue
        o_raw=$(gcq bd list --db "$beads" --status open,in_progress --json --limit=0)
        printf '%s' "$o_raw" | jq -e 'type=="array"' >/dev/null 2>&1 \
            || { gather_mark "open@$name"; continue; }
        printf '%s' "$o_raw" | jq -c --arg rig "$name" --arg prefix "$prefix" \
            '{rig:$rig, prefix:$prefix, beads:.}' > "$OPEN_DIR/$_i.json" 2>/dev/null \
            || gather_mark "open-wrap@$name"
    done
}

# ── Visit gather (rides the shared snapshot) ─────────────────────────
# Writes ONE JSON-array line to $VISITS_FILE: the unique subject ids
# carried by open visit beads (task_kind=visit). Both open AND in_progress
# count as "open" here — a claimed visit is a held conversation, not a
# finished one.
#
# A visit names its subject twice — the gc.continuation_group stamp and the
# tracks edge filed with it — and only the edge has proved reliable: on
# su-ab9je (shutupandlisten, 2026-08-20, bead tk-d6ddn) the stamp landed
# EMPTY while the tracks edge carried the subject. This set feeds $held in
# the render, which is what keeps an anchor already in conversation out of
# the stranded band; a missed subject bands it HIGH and asks the operator
# to open the visit that already exists. So take the union of both, and drop
# the empty stamp so an anchor can never match it by having no id to match.
# The same union guards the sweep (mol-liveness-sweep.toml) and its precheck.
gather_visits() {
    : > "$TMP/visit-subjects.txt"
    for f in "$OPEN_DIR"/*.json; do
        [ -f "$f" ] || continue
        jq -r '(.beads // [])[] | select((.metadata.task_kind // "") == "visit")
               | ((.metadata["gc.continuation_group"] // ""),
                  (.dependencies[]? | select((.type // "") == "tracks") | (.depends_on_id // "")))
               | select(. != "")' \
            < "$f" >> "$TMP/visit-subjects.txt" 2>/dev/null || true
    done
    jq -R -s -c 'split("\n") | map(select(length > 0)) | unique' \
        < "$TMP/visit-subjects.txt" > "$VISITS_FILE" 2>/dev/null || printf '[]\n' > "$VISITS_FILE"
}

# ── Metadata-keyed anchor kinds (rides the shared snapshot) ──────────
# Appends `human` and `parked` anchors to $ANCHORS. The three original
# kinds are selected by issue TYPE; these two by METADATA, which is the
# only way an ordinary task/bug the operator owns can reach the board at
# all — under the type-only gather it is not merely unranked, it is
# absent, and invisible also means unresumable.
#
#   human   gc.routed_to=human   the city's durable "a human must act"
#                                marker; no agent will take it.
#   parked  gc.takeaway present  a conversation that reached a takeaway.
#                                It wants nothing; it has to stay findable.
#
# `waiting_on` rides along: the ids this bead depends on by a `blocks` edge.
# A converse sitting that ROUTES work out of a subject writes that edge
# (`gc-helm takeaway … --waiting-on <bead>`), which is what turns "waiting on
# tk-hgmob" from prose inside the takeaway string into a fact the board can
# re-ask. Only the ids are gathered here; whether they have LANDED is resolved
# fresh on every render (resolve_waiting_status), never cached — a blocker
# that merged is exactly the fact a cached board would go on hiding.
#
# `children` rides along too, and this is the fix tk-a9k0l is about. These
# kinds used to hardcode `children:[]`, which is not a cheap approximation of
# the roll-up — it is a false statement of it. A plain (non-epic/convoy/
# decision) bead reaches the board ONLY through its parent's roll-up, so a
# parked subject that decomposed reported zero children AND deleted its own
# open children from every surface: the row said "wants nothing" while the work
# it was waiting for sat unassigned and unrouted, on no board at all (measured
# on tk-z9nln, 2026-08-22). The relation matters most for exactly this kind,
# because `bd` REFUSES a `blocks` edge from a parent to its own descendant, so
# the canonical converse shape — file the routed work as a CHILD of the subject
# — can never express its wait as a `waiting_on` edge (tk-2cyxo).
#
# ONE `bd show <every anchor id in this rig> --include-dependents` answers it
# for the whole rig, the same batching resolve_waiting_status uses: the ids ride
# argv at ~8 bytes each (bounded by ANCHOR count, far from MAX_ARG_STRLEN) and
# the reply, which carries whole beads, comes back through a pipe. Children are
# projected to {id,status,assignee} before crossing back over argv, for the
# reason gather_anchors spells out at length (tk-hgmob). Dependents are filtered
# to the `parent-child` edge: a convoy's `tracks` edge points at the same bead
# and is not a child.
#
# Both EXCLUDE the three typed kinds, so an epic or decision that happens
# to carry a marker stays its own kind instead of arriving twice. A bead
# carrying BOTH markers is emitted twice on purpose and the render's
# existing id-dedup keeps the higher band.
#
# This mirrors the Go helm service's gather (services/helm/README.md
# "Anchor kinds", tk-2v08m), which is the other implementation of this
# board — see docs/gascity-human-engagement.md on the divergence.
gather_meta_anchors() {
    for f in "$OPEN_DIR"/*.json; do
        [ -f "$f" ] || continue

        # Anchor ids first: the child read is one call over all of them.
        _mids=$(jq -r '
            (.beads // [])[]
            | select((.issue_type // "") as $t | (["epic","decision","convoy"] | index($t)) == null)
            | . as $b
            | ($b.metadata // {}) as $md
            | select(((($md["gc.routed_to"] // "") | tostring) == "human")
                     or ((($md["gc.takeaway"] // "") | tostring) | length) > 0)
            | $b.id' < "$f" 2>/dev/null | sort -u | tr '\n' ' ')

        _mkids='{}'
        if [ -n "$_mids" ]; then
            _mrig=$(jq -r '.rig // ""' < "$f" 2>/dev/null || printf '')
            _mdb=$(printf '%s' "$RIGS" | jq -r --arg n "$_mrig" \
                     'first(.[] | select(.name == $n) | .path) // ""' 2>/dev/null || printf '')
            if [ -n "$_mdb" ] && [ -d "$_mdb/.beads" ]; then
                # shellcheck disable=SC2086  # $_mids is a deliberate list of bare ids
                _mraw=$(gcq bd show $_mids --db "$_mdb/.beads" --include-dependents --json | tr -d '\000-\037')
                # Same shape rule resolve_waiting_status documents: `bd show`
                # answers with an ARRAY when any id resolves and a bare OBJECT
                # when none do, rc=0 either way. An anchor set that resolves to
                # nothing is the wedge/timeout shape here — every one of these
                # ids came out of this rig's own open-bead snapshot moments ago.
                if printf '%s' "$_mraw" | jq -e 'type=="array"' >/dev/null 2>&1; then
                    _mkids=$(printf '%s' "$_mraw" | jq -c '
                        [ .[]? | select(type == "object")
                          | {key: ((.id // "") | tostring),
                             value: [ (.dependents // [])[]
                                      | select(((.dependency_type // "") | tostring) == "parent-child")
                                      | {id, status, assignee} ]}
                          | select(.key != "") ] | from_entries' 2>/dev/null || printf '{}')
                else
                    gather_mark "meta-children@$_mrig"
                fi
            else
                gather_mark "meta-children-db@$_mrig"
            fi
        fi
        printf '%s' "$_mkids" | jq -e 'type=="object"' >/dev/null 2>&1 || _mkids='{}'

        jq -c --argjson kids "$_mkids" '
            .rig as $rig | .prefix as $prefix
            | (.beads // [])[]
            | select((.issue_type // "") as $t | (["epic","decision","convoy"] | index($t)) == null)
            | . as $b
            | ($b.metadata // {}) as $md
            | (($md["gc.routed_to"] // "") | tostring) as $routed
            | (($md["gc.takeaway"]  // "") | tostring) as $tk
            | ([ ($b.dependencies // [])[]
                 | select(((.type // "") | tostring) == "blocks")
                 | ((.depends_on_id // "") | tostring)
                 | select(length > 0) ] | unique) as $waiting
            | [ (if $routed == "human" then "human" else empty end),
                (if ($tk | length) > 0 then "parked" else empty end) ][]
            | . as $kind
            | {id:$b.id, title:($b.title // ""), kind:$kind, source:$kind,
               rig:$rig, prefix:$prefix, priority:($b.priority // 3),
               updated_at:($b.updated_at // ""), description:($b.description // ""),
               progress:null, children:(($kids[$b.id] // []) | if type=="array" then . else [] end),
               # Both kinds spend these now: `parked` through the disposition
               # derivation, `human` through the stand-down one ($ruled below).
               # The Go gather reads them for the same two, so the two boards
               # stay field-for-field identical.
               waiting_on:$waiting,
               # The marker itself, so the render can tell that a `parked` row
               # is the TWIN of a human-routed bead. A bead carrying BOTH
               # markers is emitted once per marker on purpose and the id-dedup
               # keeps the higher band — so without this the twin would keep a
               # band the stand-down just took off its sibling, and win.
               routed_to:$routed,
               takeaway:$tk,
               takeaway_at:(($md["gc.takeaway_at"] // "") | tostring),
               takeaway_by:(($md["gc.takeaway_by"] // "") | tostring)}' \
            < "$f" >> "$ANCHORS" 2>/dev/null || gather_mark "meta-anchors@$f"
    done
}

# ── Blocker liveness for `waiting_on` (deliberately NOT cached) ──────
# Writes ONE JSON-object line to $WAITING_FILE: blocker bead id -> its
# current status. The render calls a blocker LANDED only when this map
# says `closed`, so anything it cannot answer for reads as still-waiting.
#
# WHY IT IS SEPARATE FROM THE GATHER. The edge is structural and belongs with
# the anchors; whether the edge has been DISCHARGED is the fact the board
# exists to re-ask, and it is the fact a cache would freeze. A subject parked
# "holding — awaiting tk-hgmob" is indistinguishable, in stored state, from one
# whose blocker merged an hour ago; that is the whole defect (tk-2plde). Reading
# it live puts it in the same class as session liveness, which is likewise held
# outside the cache so a polecat that died mid-TTL stops counting at once.
#
# WHY IT IS FREE UNTIL THE EDGES EXIST. It reads $ANCHORS first and returns
# before touching a rig when no anchor carries a `waiting_on` id, so a city
# whose sittings have not yet written any edge pays nothing for this at all.
#
# COST WHEN THEY DO. One `bd show` per rig that has any, over the DISTINCT
# blocker ids of that rig's anchors — bounded by EDGE count at ~8 bytes an id,
# so it stays far from the MAX_ARG_STRLEN boundary the child payload crossed
# (tk-hgmob); the reply, which carries whole beads, comes back through a pipe.
#
# FAIL-CLOSED, AND SILENTLY. A rig that errors, times out or answers with a
# shape this cannot read simply contributes no entries, and its anchors keep
# reading as waiting — the pre-fix behaviour. That is the safe direction: a
# missed promotion costs a glance, a false "blocker landed" invites the
# operator to dispose of a subject whose work is still in flight. It does NOT
# gather_mark: this runs after the gather's fail-closed check, and a blocker
# status the board could not resolve is not grounds to refuse the whole board.
resolve_waiting_status() {
    _wids=$(jq -r '(.waiting_on // [])[]' < "$ANCHORS" 2>/dev/null | sort -u)
    [ -n "$_wids" ] || return 0
    _acc="$TMP/waiting-parts.ndjson"
    : > "$_acc"
    printf '%s' "$RIGS" | jq -c '.[]' | while IFS= read -r _rig; do
        _rname=$(printf '%s' "$_rig" | jq -r '.name')
        _rpath=$(printf '%s' "$_rig" | jq -r '.path')
        _rdb="$_rpath/.beads"
        [ -d "$_rdb" ] || continue
        _ids=$(jq -r --arg rig "$_rname" \
                  'select((.rig // "") == $rig) | (.waiting_on // [])[]' \
                  < "$ANCHORS" 2>/dev/null | sort -u | tr '\n' ' ')
        [ -n "$_ids" ] || continue
        # `bd show` answers with an ARRAY when any id resolves and a bare
        # OBJECT when none do, rc=0 either way, so the shape is tested rather
        # than assumed. Control characters in a bead's notes make the payload
        # invalid JSON for jq, hence the strip.
        # shellcheck disable=SC2086  # $_ids is a deliberate list of bare ids
        _raw=$(gcq bd show $_ids --db "$_rdb" --json | tr -d '\000-\037')
        printf '%s' "$_raw" | jq -c '
            if type == "array"
            then [ .[]? | select(type == "object")
                   | {key: ((.id // "") | tostring), value: ((.status // "") | tostring)}
                   | select(.key != "") ] | from_entries
            else {} end' >> "$_acc" 2>/dev/null || true
    done
    if [ -s "$_acc" ]; then
        jq -c -s 'add // {}' < "$_acc" > "$WAITING_FILE.tmp" 2>/dev/null \
            && mv "$WAITING_FILE.tmp" "$WAITING_FILE" 2>/dev/null \
            || rm -f "$WAITING_FILE.tmp" 2>/dev/null || true
    fi
}

# ── In-flight join (rides the shared snapshot) ───────────────────────
# Writes ONE JSON-object line to $INFLIGHT_FILE: work-bead id -> the
# session names of the live workflows over it.
#
# WHY THIS EXISTS. `gc sling` pours a graph.v2 molecule and routes its
# STEP beads; the work bead itself keeps status=open and assignee=null
# from dispatch until the refinery closes it. The in-flight state lives on
# the workflow, so a board that reads only child status sees a polecat
# five minutes into an implementation as a bead nobody has ever touched,
# and calls its parent "stranded — assign or visit".
#
# THE JOIN is the canonical one, the same walk quiesce-completed-workflows.sh
# uses: root -> gc.input_convoy_id -> the convoy's SINGLE tracked member.
# The one-member rule is a fail-closed gate, not an optimisation: a convoy
# resolving to any other count is a shape this does not understand, and the
# safe reading of "not understood" is "no claim about movement".
#
# LIVENESS FIRST, and it is what makes this safe. An open workflow root
# does NOT mean live work — nothing finalizes a graph.v2 chain after its
# session drains, so completed workflows leave husks behind and they
# accumulate (at this writing, 18 open roots in one rig, 17 of them dead).
# Joining on root existence alone would flip those husks to "in flight" and
# trade a false stall for a false all-clear — strictly the worse failure on
# a board whose job is to say what needs a human. So a root is resolved
# only when a session it is stamped with is live, which also bounds the
# convoy reads by the number of live polecats rather than by the husk pile.
# The session name is read from the root, falling back to its step beads:
# roots stamp `gc.session_name` at claim time, but not every root in the
# store carries one, and the steps do.
gather_inflight() {
    : > "$TMP/inflight-pairs.tsv"
    for f in "$OPEN_DIR"/*.json; do
        [ -f "$f" ] || continue
        jq -r --argjson live "$LIVE_SESSIONS" '
            (.beads // []) as $bs
            # root id -> session names stamped on its steps
            | ([ $bs[]
                 | select(((.metadata["gc.root_bead_id"] // "") | tostring) != "")
                 | {root: (.metadata["gc.root_bead_id"] | tostring),
                    sess: ((.metadata["gc.session_name"] // "") | tostring)} ]
               | map(select(.sess != ""))
               | group_by(.root)
               | map({key: .[0].root, value: (map(.sess) | unique)})
               | from_entries) as $stepsess
            | $bs[]
            | select(((.metadata["gc.input_convoy_id"] // "") | tostring) != "")
            | . as $r
            | ((($r.metadata["gc.session_name"] // "") | tostring)) as $rsess
            | ((([ (if $rsess != "" then $rsess else empty end) ]
                 + ($stepsess[$r.id] // [])) | unique)
               | map(select(. as $n | $live | index($n)))) as $livenames
            | select(($livenames | length) > 0)
            | "\($r.metadata["gc.input_convoy_id"] | tostring)\t\($livenames | join(","))"' \
            < "$f" >> "$TMP/inflight-pairs.tsv" 2>/dev/null || gather_mark "inflight-roots@$f"
    done

    : > "$TMP/inflight-map.tsv"
    # `gcq` reads from this loop's stdin unless told not to, and a child that
    # swallows the remaining lines would silently truncate the map to its first
    # entry — hence the explicit </dev/null.
    while IFS="$(printf '\t')" read -r _convoy _names; do
        [ -n "${_convoy:-}" ] || continue
        _anchor=$(gcq convoy status "$_convoy" --json </dev/null \
            | jq -r 'if ((.children // []) | length) == 1 then (.children[0].id // empty) else empty end' 2>/dev/null)
        [ -n "${_anchor:-}" ] || continue
        printf '%s\t%s\n' "$_anchor" "$_names" >> "$TMP/inflight-map.tsv"
    done < "$TMP/inflight-pairs.tsv"

    jq -R -s -c 'split("\n") | map(select(length > 0))
                 | map(split("\t") | {key: .[0], value: ((.[1] // "") | split(","))})
                 | group_by(.key)
                 | map({key: .[0].key, value: (map(.value) | add | unique)})
                 | from_entries' \
        < "$TMP/inflight-map.tsv" > "$INFLIGHT_FILE" 2>/dev/null || printf '{}\n' > "$INFLIGHT_FILE"
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
