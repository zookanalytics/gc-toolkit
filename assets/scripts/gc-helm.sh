#!/bin/sh
# gc-helm.sh — the helm WRITE verbs: takeaway, demand, dismiss, open, react.
# Job: write the operator-facing state the helm board renders. The board
# itself is `helm-svc board` (services/helm); this script renders nothing.
# Contract:
#   gc-helm open  <bead-id> [--reason "..."] [--body "..."]   file one visit (one open visit per subject)
#   gc-helm react <bead-id> [--reason "..."]                  sling a proactive first reaction
#   gc-helm takeaway <bead-id> "<text>" [--by ...] [--waiting-on <id>]... [--release [--route <rig>/<agent>]]
#   gc-helm demand <gated-bead> "<text>" [--kind ...] [--assignee ...] [--also-blocks <id>]...
#   gc-helm dismiss  <bead-id> [--reason "..."]               end the sitting and clear the row
# Callers: tmux-pick-helm.sh + gc-visit-open.sh (open), helm-svc POST
# /helm/open via GC_HELM_OPEN_TOOL (open — its stderr/stdout sentences are
# parsed by services/helm/internal/server, guarded by open_parity_test.go),
# converse and the proactive worker (takeaway), converse (demand), operators
# by hand.
# Exit codes: 0 ok, 2 usage, 3 environment (jq/gc missing, rigs
# unenumerable — each failure names its own operator move, tk-lzdty),
# 4 verb runtime failure (bead not found / unverifiable / filing failed /
# a --route or a takeaway disposition that will not stamp).

set -eu

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

PROG="gc-helm"
TAKEAWAY_MAX=140                            # hard cap on a takeaway headline, in CODEPOINTS
FIXTURE="${GC_HELM_FIXTURE:-}"              # test hook: <dir>/rigs.json replaces `gc rig list`

usage() {
    cat >&2 <<'EOF'
Usage:
  gc-helm open  <bead-id> [--reason "..."] [--body "..."]  file a visit on the bead (a converse session holds the conversation)
  gc-helm react <bead-id> [--reason "..."]  sling a first reaction (self-heals a takeaway-less row)
  gc-helm takeaway <bead-id> "<text>" [--by host|proactive|converse] [--waiting-on <bead-id>... | --no-wait] [--release [--route <rig>/<agent>]]  set the board-visible takeaway headline (≤140 chars, ENFORCED)
  gc-helm demand <gated-bead> "<text>" [--by ...] [--kind decision|task] [--assignee <who>] [--body "..."] [--also-blocks <bead-id>]...  file what a person owes as a bead and block the work on it
  gc-helm dismiss  <bead-id> [--reason "..."]  the operator is done with this subject: end its sitting and clear its DONE row

The board is `helm-svc board` (services/helm). This script carries only the
write verbs. open files a visit in the picked bead's continuation group (pool
demand spawns/vacuums a converse session); its --reason is the short title
tail and --body the brief the converse session reads at claim time. react
slings a proactive first reaction via tools/gc-proactive.sh (its --reason is
log-only operator intent). takeaway stamps gc.takeaway (+_at/+_by) in one
update; --release also reopens/unassigns/clears the route and quiesces the
released molecule's step beads and workflow root. On an anchor that is already
CLOSED the reopen would resurrect a landed disposition, so it is skipped and
only the quiesce runs; --route <rig>/<agent> releases it TO a pool instead of
back to the human, in the same write, and is refused on a closed anchor and on
a bead blocked by anything but its own demand, since the work is then on the
blocker and a pool has nothing to perform here; --waiting-on (repeatable)
records the wait as a `blocks` edge beside the prose so the board can re-ask
whether it landed. --no-wait is the other answer to the same question: this
sitting settled the subject and nothing is waiting on it. It stamps
gc.takeaway_settled, which lifecycle.toml [holds] reads to tell a settled
headline from one parking a bead on prose, and it contradicts --waiting-on.
Say neither and the headline is a hold that doctor/check-wait-is-an-edge
reports, which is the honest reading of a park nothing re-asks.

demand files what a person owes as its own bead, a SIBLING of the work, and
blocks that work on it with a `blocks` edge; it prints `demand <id> blocks
<gated>`, so a caller reads the id back with
`awk '/^demand /{print $2; exit}'`.

dismiss is the operator's one explicit act for "take this out of my view",
and both halves of it exist because the alternative is something leaving on
its own. It closes the subject's open visit, which is what holds a converse
sitting up now that nothing idle-reaps one; and it stamps gc.dismissed_at, so
the board drops the subject's row from the terminal DONE band a closed anchor
otherwise keeps for GC_HELM_DONE_WINDOW (default 7d). The close half stamps
gc.outcome=dismissed first, so the ended sitting is still one the board can
report, and a visit that will not take that stamp is left open rather than
closed unreadable; the close itself falls back to --force when the visit is
held under a session identity this actor cannot close under. A sitting the
verb could not account for aborts the row stamp: the row stays and the run
exits 4.
Idempotent: a subject with no visit and no row is already dismissed and says
so.
EOF
}

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 3; }
command -v gc >/dev/null 2>&1 || { echo "$PROG: gc is required" >&2; exit 3; }

# Portable timeout: GNU timeout, else gtimeout (macOS coreutils), else unbounded.
if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN=gtimeout
else TIMEOUT_BIN=""
fi
with_timeout() {
    _wt_secs="$1"; shift
    if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$_wt_secs" "$@"; else "$@"; fi
}

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# meta_now <bead> <key> — one metadata key as the store answers it right now,
# for reading a write back. A row that will not read answers empty, which every
# caller here treats the same as a value that did not land. $db is the caller's
# store pin; the verbs that pin by BEADS_DIR leave it unset.
meta_now() {
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd show "$1" ${db:+--db "$db"} --json 2>/dev/null | scrub \
        | jq -r --arg k "$2" 'if type == "array" then ((.[0].metadata // {})[$k] // "") else "" end' 2>/dev/null || printf ''
}

# normalize_headline <raw-text> <verb> — collapse whitespace runs, trim, and
# enforce the shared ≤TAKEAWAY_MAX cap; sets HEADLINE. One gate for two verbs:
# a demand bead's TITLE is the same board headline a takeaway stamp carries, so
# a cap enforced in only one of them is a cap the other renders past.
HEADLINE=""
normalize_headline() {
    HEADLINE=$(printf '%s' "$1" | tr -s '[:space:]' ' ')
    HEADLINE="${HEADLINE# }"; HEADLINE="${HEADLINE% }"
    [ -n "$HEADLINE" ] || { echo "$PROG: $2 needs \"<text>\" (the ≤${TAKEAWAY_MAX}-char one-line headline)" >&2; usage; exit 2; }
    # >>> takeaway-length-gate
    # REJECT over the cap, never truncate: only the author knows which clause
    # is the headline. Measured in CODEPOINTS — what both
    # renderers measure — with a shell-count fallback so the gate cannot
    # silently fail open on a broken jq.
    tlen=$(printf '%s' "$HEADLINE" | jq -Rsr 'length' 2>/dev/null || true)
    case "$tlen" in ''|*[!0-9]*) tlen=${#HEADLINE} ;; esac
    if [ "$tlen" -gt "$TAKEAWAY_MAX" ]; then
        echo "$PROG: $2: text is $tlen chars; the cap is $TAKEAWAY_MAX" >&2
        echo "$PROG: $2: it renders as the board's NEEDS cell — one line, read at a glance. Cut it to the single sentence the operator needs and put the rest in the bead's notes." >&2
        exit 2
    fi
    # <<< takeaway-length-gate
}

# Sibling tools: assets/scripts/ and tools/ are siblings under the pack root.
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROACTIVE_TOOL="${GC_PROACTIVE_TOOL:-$SCRIPT_DIR/../../tools/gc-proactive.sh}"

# Bust the retired bash board's gather cache so a straggler reader never
# serves a pre-write board for a whole TTL.
CACHE_DIR="${TMPDIR:-/tmp}/gc-helm-cache.$(id -u 2>/dev/null || echo 0)"
_city_key=$(printf '%s' "${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-default}}}" | cksum | cut -d' ' -f1)
CACHE_FILE="$CACHE_DIR/board2-$_city_key.ndjson"
bust_cache() { rm -f "$CACHE_FILE" 2>/dev/null || true; }

# ── Rig enumeration ──────────────────────────────────────────────────
# Sets RIGS (JSON array of {name,path,prefix}); exits 3 with a per-cause
# sentence otherwise. Each failure names its own operator move because for a
# non-CLI caller (the web board's open button) the code plus the sentence is
# the whole signal (tk-lzdty).
RIGS=""
rigs_count() {
    # jq emits nothing on empty input; normalize so arithmetic never throws.
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
    # 30s, not a board-render budget: a one-shot verb that exits 3 having
    # filed nothing is the wrong trade for a slow answer (measured 2.6-8.4s).
    _er_secs="${GC_HELM_RIG_TIMEOUT:-30}"
    # Capture status AND stderr — they are the only things separating a
    # timeout kill, a wedged data plane, malformed output, and a rigless city.
    _er_errf=$(mktemp 2>/dev/null || printf '')
    _er_rc=0
    if [ -n "$_er_errf" ]; then
        rigs_raw=$(with_timeout "$_er_secs" gc rig list --json 2>"$_er_errf") || _er_rc=$?
        _er_why=$(tr '\n' ' ' < "$_er_errf" 2>/dev/null | cut -c1-300 | sed 's/  */ /g; s/^ *//; s/ *$//')
        rm -f "$_er_errf" 2>/dev/null || true
    else
        rigs_raw=$(with_timeout "$_er_secs" gc rig list --json 2>/dev/null) || _er_rc=$?
        _er_why=""
    fi

    if [ "$_er_rc" -ne 0 ]; then
        # 124 is the timeout kill, only meaningful when a timeout binary ran.
        if [ -n "$TIMEOUT_BIN" ] && [ "$_er_rc" -eq 124 ]; then
            echo "$PROG: could not enumerate rigs: 'gc rig list' did not answer within ${_er_secs}s and was killed. Raise the bound with GC_HELM_RIG_TIMEOUT=<seconds>, or check whether gc/Dolt is wedged. This command wrote nothing." >&2
        else
            echo "$PROG: could not enumerate rigs: 'gc rig list' exited ${_er_rc}${_er_why:+ — $_er_why}. That is the data plane, not this script — try 'gc doctor' and check Dolt. This command wrote nothing." >&2
        fi
        exit 3
    fi

    # gc exited 0, so the problem is what it printed. jq -e separates the
    # readings: 4 = no output at all, 5 = not JSON, 1 = wrong shape.
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
        # gc answered correctly: this city really has no rigs. Not a malfunction.
        echo "$PROG: no rigs in this city: 'gc rig list' answered normally with an empty rig set. Add one with 'gc rig add', or point GC_CITY at the intended city. This command wrote nothing." >&2
        exit 3
    fi
}

# rig_path_for_bead <bead-id> — rig repo path owning the bead, by id prefix.
rig_path_for_bead() {
    enumerate_rigs
    printf '%s' "$RIGS" | jq -r --arg p "${1%%-*}" '.[] | select(.prefix==$p) | .path' 2>/dev/null | head -n1
}

# rig_name_for_bead <bead-id> — rig NAME owning the bead, by id prefix.
rig_name_for_bead() {
    enumerate_rigs
    printf '%s' "$RIGS" | jq -r --arg p "${1%%-*}" '.[] | select(.prefix==$p) | .name' 2>/dev/null | head -n1
}

# ── Release helper: quiesce a released molecule ──────────────────────
# A molecule whose anchor is out of play — parked by a stand-down, or closed by
# a fold that landed after the pour — keeps re-attracting the pins
# (gc.routed_to / assignee / session_affinity) that re-spawn a polecat onto the
# husk. That is why the walk is reachable on a closed anchor too. Both doors
# carry them: the graph.v2 STEP beads, and the gc.kind=workflow ROOT, which is
# only a tracker but is pool-routed in its own right. Walk both in reverse (a
# step through gc.root_bead_id, a root through itself, then on through the
# root's gc.input_convoy_id to the convoy's single tracked member) and clear
# the pins wherever that resolves to THIS anchor.
#
# Guards: fail closed on an unresolved or foreign anchor; NEVER close a bead or
# rewrite its status; never de-route workflow-finalize or a control-dispatcher
# route, which is the molecule's only escape path; never de-pin the bead the
# RELEASING session holds, which is live and not a husk; steps are selected by
# contract (gc.step_ref) and never by formula name; an absent root is the
# witness patrol's, not ours.
#
# The pins go in TWO updates, route first. beads refuses `--assignee ""` on an
# in_progress bead another session holds, and refuses the whole update along
# with it, so folding all three keys into one write loses the route pins on
# exactly the bead being re-offered. Clearing gc.routed_to alone already lifts
# a bead out of every pool claim predicate; the assignee is the one key that
# may legitimately have to wait for its holder. The order is load-bearing —
# reversed, the gap between the writes would leave the bead routed and
# unassigned, which is the pool-offer shape a fresh polecat races into. For the
# same reason the second write is skipped outright when the first one fails.
#
# Best-effort subshell. $1 = released anchor id, $2 = rig .beads path or "".
# >>> quiesce-release-molecule-steps
quiesce_release_molecule_steps() (
    set +e
    _anchor="$1"; _db="$2"

    # The spellings a bead's assignee can carry for THIS session — the same
    # three step-close.sh tries as the assignee.
    _me=$(printf '%s\n%s\n%s\n' "${GC_SESSION_NAME:-}" "${GC_SESSION_ID:-}" "${GC_ALIAS:-}" | grep -v '^$' || true)

    # shellcheck disable=SC2086  # ${_db:+--db "$_db"} expands to 0 or 2 space-free fields
    _steps=$(gc bd list --status=open,in_progress ${_db:+--db "$_db"} --json --limit=0 2>/dev/null || true)
    [ -n "$_steps" ] && [ "$_steps" != "[]" ] || exit 0

    # A root names no gc.root_bead_id and no gc.step_ref; it IS the root, and
    # its gc.step_id is the formula name, which is what the report says.
    _rows=$(printf '%s' "$_steps" | jq -c '
        .[]
        | . as $b
        | (($b.metadata["gc.kind"] // "") == "workflow") as $isroot
        | select($isroot
                 or ((($b.metadata["gc.step_ref"]     // "") != "")
                     and (($b.metadata["gc.root_bead_id"] // "") != "")))
        | { id:       $b.id,
            kind:     (if $isroot then "root" else "step" end),
            step:     (if $isroot then ($b.metadata["gc.step_id"]  // "")
                                  else ($b.metadata["gc.step_ref"] // "") end),
            root:     (if $isroot then $b.id
                                  else ($b.metadata["gc.root_bead_id"] // "") end),
            routed:   ($b.metadata["gc.routed_to"] // ""),
            assignee: ($b.assignee // ""),
            affinity: ($b.metadata["gc.session_affinity"] // "") }' 2>/dev/null || true)
    [ -n "$_rows" ] || exit 0

    _roots=$(printf '%s\n' "$_rows" | jq -r -s 'map(.root) | map(select(. != "")) | unique | .[]' 2>/dev/null || true)
    [ -n "$_roots" ] || exit 0

    printf '%s\n' "$_roots" | while IFS= read -r _root; do
        [ -n "$_root" ] || continue

        # Resolve this root's anchor; an empty read (failed OR absent root) skips.
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
            _kind=$(printf '%s'     "$_row" | jq -r '.kind // empty' 2>/dev/null || true)
            _step=$(printf '%s'     "$_row" | jq -r '.step // empty' 2>/dev/null || true)
            _routed=$(printf '%s'   "$_row" | jq -r '.routed // empty' 2>/dev/null || true)
            _who=$(printf '%s'      "$_row" | jq -r '.assignee // empty' 2>/dev/null || true)
            _affinity=$(printf '%s' "$_row" | jq -r '.affinity // empty' 2>/dev/null || true)
            [ -n "$_sid" ] || continue

            # Never de-route the finalize step (the molecule's only escape path).
            case "$_step" in *.workflow-finalize) continue ;; esac
            case "$_routed" in *control-dispatcher*) continue ;; esac

            # Never de-pin the bead this release is being performed FROM. The
            # quiesce exists to stop an ABANDONED molecule re-attracting spawns;
            # a bead the releasing session holds is the live one, not a husk,
            # and the session still owes its own step chain's close, so this
            # quiesce leaves it alone. With no identity in the environment
            # step-close.sh refuses to close anything at all, so there is no
            # case where the skip is needed and unavailable.
            if [ -n "$_who" ] && [ -n "$_me" ] && printf '%s\n' "$_me" | grep -qxF -- "$_who"; then
                echo "$PROG: takeaway: kept live $_kind $_sid ($_step) — this session holds it and still has to close it"
                continue
            fi

            # Idempotent: already quiet -> nothing left to clear.
            [ -n "$_routed" ] || [ -n "$_who" ] || [ -n "$_affinity" ] || continue

            _pins_ok=1
            set --
            [ -n "$_routed" ]   && set -- "$@" --unset-metadata gc.routed_to
            [ -n "$_affinity" ] && set -- "$@" --unset-metadata gc.session_affinity
            if [ $# -gt 0 ]; then
                # shellcheck disable=SC2086  # ${_db:+--db "$_db"} expands to 0 or 2 fields
                gc bd update "$_sid" ${_db:+--db "$_db"} "$@" >/dev/null 2>&1 || _pins_ok=0
            fi

            # The assignee clear is attempted only once the route is known to be
            # gone (landed, or never there). Unassigning a bead that is still
            # routed is what leaves the pool-offer shape behind, so a failed
            # pin write takes the second update down with it rather than
            # producing the state this whole order exists to avoid.
            _who_ok=1
            if [ -n "$_who" ] && [ "$_pins_ok" -eq 1 ]; then
                # shellcheck disable=SC2086  # ${_db:+--db "$_db"} expands to 0 or 2 fields
                gc bd update "$_sid" ${_db:+--db "$_db"} --assignee "" >/dev/null 2>&1 || _who_ok=0
            fi

            if [ "$_pins_ok" -eq 0 ]; then
                echo "$PROG: takeaway: could not quiesce $_kind $_sid (retries via witness patrol)" >&2
            elif [ "$_who_ok" -eq 0 ]; then
                echo "$PROG: takeaway: de-pinned husk $_kind $_sid ($_step) of $_anchor — assignee left to the session still holding it"
            else
                echo "$PROG: takeaway: quiesced husk $_kind $_sid ($_step) of $_anchor"
            fi
        done
    done
    exit 0
)
# <<< quiesce-release-molecule-steps

# ── Verb: takeaway ───────────────────────────────────────────────────
# Stamp gc.takeaway/_at/_by in ONE update, then bust the cache. --release adds
# two acts to that stamp: PARK the anchor, and QUIESCE the molecule beneath it.
#
# The park (reopen, unassign, stamp the route, gc.proactive_reaction=1) rides
# the same write as the headline, so a reaction that concludes "this is work"
# hands the bead on in the write that records the conclusion: either the whole
# disposition lands or none of it does. It applies to an anchor still standing.
# A closed anchor was disposed already, so it keeps that disposition and gets
# the quiesce alone.
#
# The quiesce de-pins every routed bead of the molecule, its graph.v2 workflow
# root as well as its steps: the root is a pool-routed door into the same work.
#
# --route names a pool to release TO. The target is rig-qualified or refused,
# because gc.routed_to is read by exact string and a bare agent name routes to
# nobody and sits forever; on a closed anchor the route is refused outright. It
# also names a bead that is itself the work, so a bead blocked by anything but
# its own demand is refused.
# --waiting-on records each wait as a `blocks` edge, best-effort: the stamp is
# what the sitting owes the operator, so a rejected edge only warns and never
# fails the verb. One wait is written as no edge: a LANDED rider — a bead that
# both rode the SUBJECT's own branch and has already put its work there, proven
# by a post-push state (closed, or handed off to the refinery). Its deliverable
# is in the subject's own head, so the subject's merge is what carries it, and
# an edge would gate that merge on work that merges WITH it — the blocker
# merge.sh's dep-edge lane holds on with no release, a PR wedged forever. Same
# branch WITHOUT that proof is not this case: metadata.branch is set at
# workspace-setup, before the wait pushes, so a still-open same-branch wait may
# not be on the branch yet, and its edge stands so the subject cannot merge past
# it. When EVERY named wait is a landed rider the headline records
# gc.takeaway_settled, the settled shape --no-wait writes, so no held marker is
# left edgeless for doctor/check-wait-is-an-edge. Every other wait keeps its edge.
#
# The headline says nothing about whether the subject is still waiting, and
# every sitting stamps one, so the disposition rides beside it in
# gc.takeaway_settled: "1" under --no-wait, empty otherwise. It is written with
# EVERY headline, never left to stand, because a stamp that outlived its
# sitting would answer for the next one — a settled sign-off would silence the
# park that followed it. lifecycle/lifecycle.toml [holds] settled_keys is where
# doctor/check-wait-is-an-edge reads the pairing.
cmd_takeaway() {
    bead=""; text=""; by="host"; release=""; route=""; npos=0
    waiting_ids=""; no_wait=""; subj_branch=""; real_waits=""; skipped_riders=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --by=*)    by="${1#--by=}"; shift ;;
            --by)      shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --by requires a value" >&2; exit 2; }; by="$1"; shift ;;
            --waiting-on=*) waiting_ids="$waiting_ids ${1#--waiting-on=}"; shift ;;
            --waiting-on)   shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --waiting-on requires a bead id" >&2; exit 2; }
                            waiting_ids="$waiting_ids $1"; shift ;;
            --no-wait) no_wait=1; shift ;;
            --release) release=1; shift ;;
            --route=*) route="${1#--route=}"; shift ;;
            --route)   shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --route requires a <rig>/<agent> target" >&2; exit 2; }; route="$1"; shift ;;
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

    # Two answers to one question, and they contradict: a named wait IS the
    # subject still waiting. Refused before anything is written, so what gets
    # repaired is the claim rather than the bead.
    if [ -n "$no_wait" ] && [ -n "$waiting_ids" ]; then
        echo "$PROG: takeaway: --no-wait contradicts --waiting-on$waiting_ids — one says nothing is waiting on $bead, the other names what is. Pass whichever is true. Nothing was written." >&2
        exit 2
    fi

    normalize_headline "$text" takeaway
    text="$HEADLINE"

    [ -n "$by" ] || by="host"

    # --route rides --release: a route stamped without the release would leave
    # the bead assigned to this session AND routed to a pool, which is the
    # half-state no reader can act on.
    if [ -n "$route" ]; then
        [ -n "$release" ] || { echo "$PROG: takeaway: --route needs --release (it names where the bead is released TO)" >&2; exit 2; }
        case "$route" in
            */*) : ;;
            *) echo "$PROG: takeaway: --route '$route' is not rig-qualified; gc.routed_to is matched as an exact string, so a bare agent name routes to nobody and the bead sits forever. Use <rig>/<agent>." >&2; exit 2 ;;
        esac
    fi

    path=$(rig_path_for_bead "$bead")
    db=""; [ -n "$path" ] && [ -d "$path/.beads" ] && db="$path/.beads"

    # --release is two acts welded into one flag: PARK the anchor (reopen,
    # unassign, stamp the route) and QUIESCE the molecule beneath it. The park
    # is correct for an anchor still standing and destructive for one already
    # disposed — a bead closed by a fold carries gc.superseded_by and a
    # close_reason naming its carrier, and `--status=open` there makes work
    # whose disposition landed visible as open in every reader of open beads.
    # The quiesce is the half a disposed anchor still needs: a fold that lands
    # AFTER the pour leaves the molecule routed either way, and welding the two
    # is what made that chain unreachable. So a closed anchor keeps its
    # disposition and still gets the walk.
    #
    # The status is read before anything is written, and an unreadable one
    # refuses the verb: a bead whose disposition cannot be proven is the one
    # case where reopening it costs the most.
    # >>> takeaway-release-closed-anchor
    release_park=""
    if [ -n "$release" ]; then
        release_park=1
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        anchor_json=$(gc bd show "$bead" ${db:+--db "$db"} --json 2>/dev/null | scrub)
        anchor_status=$(printf '%s' "$anchor_json" \
            | jq -r --arg b "$bead" \
                'if type == "array"
                 then [ .[] | select(type == "object" and (.id // "") == $b) ] | first | (.status // "")
                 else empty end' 2>/dev/null || true)
        if [ -z "$anchor_status" ]; then
            echo "$PROG: takeaway: could not read the status of '$bead' (does it exist in rig '${path:-?}'?). Refusing --release rather than reopen a bead whose disposition cannot be read. Nothing was written." >&2
            exit 4
        fi
        if [ "$anchor_status" = "closed" ]; then
            release_park=""
            superseded=$(printf '%s' "$anchor_json" \
                | jq -r --arg b "$bead" \
                    'if type == "array"
                     then [ .[] | select(type == "object" and (.id // "") == $b) ] | first | ((.metadata // {})["gc.superseded_by"] // "")
                     else empty end' 2>/dev/null || true)
            echo "$PROG: takeaway: $bead is closed${superseded:+, superseded by $superseded} — its disposition stands, so the release write is skipped (no reopen, no unassign, no route stamp). The molecule is still quiesced." >&2
        fi
    fi
    # <<< takeaway-release-closed-anchor

    # A pool route promises a claim some session can perform. A bead blocked by
    # anything other than its own demand has its method somewhere else: no pool
    # can see it until the blocker closes, and by then it is a record of work
    # that already happened, so each session that claims it re-derives that and
    # drains. A demand is the one blocker that leaves the route honest, because
    # answering it is what makes this bead the work — the demand verb stamps
    # gc.demand_for, so the two are told apart by that stamp and not by shape.
    # Refused before the write, so a re-run without --route still lands the
    # headline, and the route is all the refusal costs: the board gathers a
    # parked row on gc.takeaway and bands it disposition-due once its waits have
    # all closed, so the operator is asked either way. An unreadable probe
    # allows the route and says so. A bd that will not answer must not cost a
    # sitting its disposition, but a route stamped over an uninspected bead is
    # a weaker promise than one the guard cleared, and in silence the two read
    # alike. Unreadable covers the payload as well as the exit code: `dep list`
    # reports a bead it cannot resolve as a JSON error OBJECT on stdout, which
    # a filter that answers "" on anything but an array takes for no edges at
    # all. A cross-store edge is left out of the array entirely, invisible here
    # as it is to every other reader of this graph. A closed anchor is not this
    # refusal's case: its route is refused below on the disposition itself,
    # after the headline and the quiesce a folded anchor still needs have
    # landed.
    if [ -n "$route" ] && [ -n "$release_park" ]; then
        probe_read=1
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        blocked_by=$(gc bd dep list "$bead" ${db:+--db "$db"} --direction=down --json 2>/dev/null | scrub \
            | jq -er --arg b "$bead" 'if type == "array" then
                   [ .[] | select((.dependency_type // "") == "blocks")
                         | select((.status // "") != "closed")
                         | select(((.metadata // {})["gc.demand_for"] // "") != $b)
                         | .id ] | join(" ")
                 else error("not an edge array") end' 2>/dev/null) || probe_read=""
        if [ -z "$probe_read" ]; then
            blocked_by=""
            echo "$PROG: takeaway: could not read the blockers on $bead ('gc bd dep list' failed, or answered with something other than an edge array), so --route '$route' goes UNCHECKED. If this bead's work is really on a blocker, it reaches '$route' with no method to perform once that blocker closes. Re-run with --release alone to leave it at rest, or re-run this call once the store answers." >&2
        fi
        if [ -n "$blocked_by" ]; then
            echo "$PROG: takeaway: --route '$route' on $bead, which is blocked by $blocked_by. None of those is a demand on $bead, so the work is on them and this bead has no method a pool can perform: routed, it waits for them to close and is then offered to '$route' forever. Re-run with --release alone, which still lands the headline and the release and leaves the bead at rest. A bead that should reach a pool once its blocker clears is first-reaction-dispose.sh --disposition blocked --then-route '$route', which routes on the unblock instead of now." >&2
            exit 2
        fi
    fi

    # Partition --waiting-on into the waits a pool still owes and the LANDED
    # riders. A landed rider both rode <bead>'s OWN branch and has already put
    # its work there, so <bead>'s own merge is what carries it
    # (docs/gascity-human-engagement.md, "a settled sitting"): an edge would
    # gate <bead>'s merge on work that merges WITH it — the deadlock merge.sh's
    # dep-edge lane holds on with no release — while asserting a pending wait
    # that does not exist. Both halves are required. metadata.branch is set at
    # workspace-setup, before the wait implements, pushes or hands off, so
    # equality proves the wait MEANS to ride this branch, not that its work is
    # on it. The proof its work landed is a post-push state: the wait is closed
    # (merged), or its assignee is the refinery (the handoff submit-and-exit
    # writes only after it verifies the push). Absent the proof — a wait still
    # open under a pool, or a probe that will not read — the edge stands, so
    # <bead> cannot merge past work that has not landed. Only a landed rider is
    # dropped; if EVERY named wait is one, the sitting is settled with respect to
    # all of them, so no_wait is set and the headline stamps gc.takeaway_settled
    # the same way --no-wait does — which keeps doctor/check-wait-is-an-edge (I1)
    # satisfied without an edge to a wait that is not there.
    if [ -n "$waiting_ids" ]; then
        subj_branch=$(meta_now "$bead" branch)
        have_real=""
        for _w in $waiting_ids; do
            [ -n "$_w" ] || continue
            if [ "$_w" = "$bead" ]; then
                echo "$PROG: takeaway: --waiting-on $_w is the bead itself; skipped" >&2
                continue
            fi
            # Read the wait once: its branch says whether it rode <bead>'s
            # branch, its status and assignee whether its work is provably there.
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            _wrow=$(gc bd show "$_w" ${db:+--db "$db"} --json 2>/dev/null | scrub)
            _wbranch=$(printf '%s' "$_wrow" | jq -r 'if type == "array" then ((.[0].metadata // {}).branch // "") else "" end' 2>/dev/null)
            _wstatus=$(printf '%s' "$_wrow" | jq -r 'if type == "array" then (.[0].status // "") else "" end' 2>/dev/null)
            _wassignee=$(printf '%s' "$_wrow" | jq -r 'if type == "array" then (.[0].assignee // "") else "" end' 2>/dev/null)
            _rider=""
            if [ -n "$subj_branch" ] && [ "$_wbranch" = "$subj_branch" ]; then
                case "$_wstatus" in closed) _rider=1 ;; esac
                case "$_wassignee" in refinery|*.refinery|*/refinery) _rider=1 ;; esac
            fi
            if [ -n "$_rider" ]; then
                skipped_riders="$skipped_riders $_w"
                continue
            fi
            real_waits="$real_waits $_w"; have_real=1
        done
        if [ -n "$skipped_riders" ] && [ -z "$have_real" ]; then no_wait=1; fi
    fi

    # Build args with `set --` ($text/$by contain spaces); --release rides the
    # SAME update so stamp + release stay one Dolt write.
    set --
    set -- "$@" --set-metadata "gc.takeaway=$text" \
               --set-metadata "gc.takeaway_at=$(iso_now)" \
               --set-metadata "gc.takeaway_by=$by" \
               --set-metadata "gc.takeaway_settled=$no_wait"
    [ -n "$release_park" ] && set -- "$@" --status=open --assignee= \
               --set-metadata "gc.routed_to=$route" --set-metadata "gc.proactive_reaction=1"
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd update "$bead" ${db:+--db "$db"} "$@" >/dev/null 2>&1 \
        || { echo "$PROG: takeaway: could not update '$bead' (does it exist in rig '${path:-?}'?)" >&2; exit 4; }
    # A route that lands EMPTY is the worst outcome of all: the bead is open,
    # unassigned and routed to nobody, which no pool's exact-match query can
    # see. One `--set-metadata` pair in a multi-pair update can land
    # present-but-empty while its siblings land, so read this one back and
    # repair it. A repair that also misses is a verb failure, because --route
    # promises the pool can see the bead and a caller reading a zero exit as
    # "released to that pool" would be wrong. The writes that did land stay,
    # and the message names them, so the miss is repairable by hand.
    route_missed=""
    if [ -n "$route" ] && [ -n "$release_park" ]; then
        route_got=$(meta_now "$bead" gc.routed_to)
        if [ "$route_got" != "$route" ]; then
            echo "$PROG: takeaway: gc.routed_to on $bead read back as '$route_got', expected '$route' — repairing" >&2
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            gc bd update "$bead" ${db:+--db "$db"} --set-metadata "gc.routed_to=$route" >/dev/null 2>&1 || true
            route_got=$(meta_now "$bead" gc.routed_to)
            if [ "$route_got" = "$route" ]; then
                echo "$PROG: takeaway: the route repair landed on $bead" >&2
            else
                route_missed=1
            fi
        fi
    fi
    # The disposition is read back on the same terms, and for a sharper reason:
    # it is the one field of the stamp whose STALE value is a wrong answer
    # rather than a missing one. A park whose clear did not land keeps the
    # previous sitting's "settled", and doctor/check-wait-is-an-edge then reads
    # this bead as a wait somebody already discharged — the exact blindness the
    # pairing exists to remove, on the exact bead a person is owed an answer
    # about. A repair that also misses is a verb failure: a caller reading a
    # zero exit as "the disposition landed" would be wrong.
    settled_missed=""
    settled_got=$(meta_now "$bead" gc.takeaway_settled)
    if [ "$settled_got" != "$no_wait" ]; then
        echo "$PROG: takeaway: gc.takeaway_settled on $bead read back as '$settled_got', expected '$no_wait' — repairing" >&2
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        gc bd update "$bead" ${db:+--db "$db"} --set-metadata "gc.takeaway_settled=$no_wait" >/dev/null 2>&1 || true
        settled_got=$(meta_now "$bead" gc.takeaway_settled)
        if [ "$settled_got" = "$no_wait" ]; then
            echo "$PROG: takeaway: the disposition repair landed on $bead" >&2
        else
            settled_missed=1
            echo "$PROG: takeaway: $bead still reads gc.takeaway_settled='$settled_got', not '$no_wait' — the headline is stamped, but the disposition beside it is the one the sitting before it left, so the wait check answers for this bead from a stamp nobody wrote for it. Stamp it by hand: gc bd update $bead${db:+ --db $db} --set-metadata gc.takeaway_settled=$no_wait" >&2
        fi
    fi
    # Edges AFTER the stamp: a failure here degrades to prose-only, never
    # loses the conclusion. `dep add <bead> <blocker>` = "<bead> is blocked by
    # <blocker>", so the edge lands on <bead> — what the board reads. Only the
    # waits still owed reach here; landed riders were partitioned out above and
    # are reported after, so the reason each got no edge is on the log.
    for _w in $real_waits; do
        [ -n "$_w" ] || continue
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        if gc bd dep add "$bead" "$_w" -t blocks ${db:+--db "$db"} >/dev/null 2>&1; then
            echo "waiting-on edge: $bead depends on $_w"
        else
            echo "$PROG: takeaway: could not wire --waiting-on $_w (same store? already wired? cycle?) — the takeaway text still stands, but the board cannot see this wait" >&2
        fi
    done
    for _w in $skipped_riders; do
        echo "$PROG: takeaway: --waiting-on $_w is a landed rider on $bead's own branch ($subj_branch) — its work is already there, so $bead's merge is what lands it and no wait edge is written (an edge would gate $bead's merge on work that merges with it, with no release). The board re-asks this wait through $bead's own landing." >&2
    done
    bust_cache
    if [ -n "$release" ]; then
        quiesce_release_molecule_steps "$bead" "$db"
    fi
    if [ -n "$route_missed" ]; then
        echo "$PROG: takeaway: $bead is released but NOT routed to '$route' — it is open, unassigned and visible to no pool. The headline, the release and the edges are written; stamp the route by hand: gc bd update $bead${db:+ --db $db} --set-metadata gc.routed_to=$route" >&2
        exit 4
    fi
    # Reported at its read-back above; the exit waits until here so the edges
    # and the quiesce still run, the way the route miss does.
    if [ -n "$settled_missed" ]; then
        exit 4
    fi
    # A route asked for on a closed anchor is refused the same way a route that
    # would not stamp is: the useful writes stand, and the exit is non-zero so
    # no caller reads it as "released to that pool". Routing a disposed bead is
    # the resurrection in its purest form — the pool claims it and cuts a
    # branch for superseded work.
    if [ -n "$route" ] && [ -z "$release_park" ]; then
        echo "$PROG: takeaway: $bead is closed, so it was NOT routed to '$route' — a pool that claimed it would work a bead whose disposition landed. The headline and the quiesce are written. If the disposition is wrong, reopen the bead deliberately and re-run: gc bd update $bead${db:+ --db $db} --status=open" >&2
        exit 4
    fi
    rel_note=""
    if [ -n "$release" ]; then
        if [ -n "$release_park" ]; then rel_note=" [released${route:+ to $route}]"
        else rel_note=" [quiesced; anchor left closed]"; fi
    fi
    echo "takeaway set on $bead (by $by)$rel_note: $text"
}

# ── Verb: demand ─────────────────────────────────────────────────────
# What a person owes, filed as a bead the work is blocked by — the replacement
# for parking a subject on prose. A bead is either ready and therefore moving,
# or blocked on a named bead by an edge; there is no third state a person has
# to return and hand-clear.
#
# The demand is filed as a SIBLING of <gated-bead>: same parent, or parentless
# when the gated bead has none. That placement is not tidiness. beads REFUSES a
# `blocks` edge from a parent to its own descendant, because blocked status
# cascades and the descendant would inherit the block it is meant to lift, so a
# demand filed as a CHILD could never gate the thing it is about.
#
# The edge is the record here, not a garnish on it. `takeaway --waiting-on`
# writes its edge beside prose a human reads, so a rejected edge only warns;
# any requested edge that did not land leaves that work reading ready while a
# person still owes an answer, which is the exact failure this verb exists to
# remove. So it exits 4 unless every bead it was asked to gate reads back
# blocked. An --also-blocks target is held to the same terms as the gated bead,
# and every missing edge is named with its own repair command.
#
# One open demand per gated bead: a resumed sitting re-states the same question
# and gets the existing demand refreshed, never a second blocker for one wait.
cmd_demand() {
    gated=""; text=""; by="host"; kind="decision"; who=""; body=""; also=""; npos=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --by=*)          by="${1#--by=}"; shift ;;
            --by)            shift; [ $# -gt 0 ] || { echo "$PROG: demand: --by requires a value" >&2; exit 2; }; by="$1"; shift ;;
            --kind=*)        kind="${1#--kind=}"; shift ;;
            --kind)          shift; [ $# -gt 0 ] || { echo "$PROG: demand: --kind requires a value" >&2; exit 2; }; kind="$1"; shift ;;
            --assignee=*)    who="${1#--assignee=}"; shift ;;
            --assignee)      shift; [ $# -gt 0 ] || { echo "$PROG: demand: --assignee requires a value" >&2; exit 2; }; who="$1"; shift ;;
            --body=*)        body="${1#--body=}"; shift ;;
            --body)          shift; [ $# -gt 0 ] || { echo "$PROG: demand: --body requires a value" >&2; exit 2; }; body="$1"; shift ;;
            --also-blocks=*) also="$also ${1#--also-blocks=}"; shift ;;
            --also-blocks)   shift; [ $# -gt 0 ] || { echo "$PROG: demand: --also-blocks requires a bead id" >&2; exit 2; }
                             also="$also $1"; shift ;;
            -h|--help)       usage; exit 0 ;;
            -*) echo "$PROG: demand: unknown flag '$1'" >&2; exit 2 ;;
            *)
                npos=$((npos + 1))
                case "$npos" in
                    1) gated="$1" ;;
                    2) text="$1" ;;
                    *) echo "$PROG: demand takes one <gated-bead> and one \"<text>\"" >&2; exit 2 ;;
                esac
                shift ;;
        esac
    done
    [ -n "$gated" ] || { echo "$PROG: demand needs <gated-bead>" >&2; usage; exit 2; }
    normalize_headline "$text" demand
    text="$HEADLINE"
    case "$kind" in
        decision|task) ;;
        *) echo "$PROG: demand: --kind is 'decision' (a ruling) or 'task' (work only a person can do); got '$kind'" >&2; exit 2 ;;
    esac
    [ -n "$by" ] || by="host"
    [ -n "$body" ] || body="What a person owes, filed as a bead so the wait is a graph state rather than a comment. Closing this makes $gated ready, and the pool claims it."

    path=$(rig_path_for_bead "$gated")
    [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"
    prefix="${gated%%-*}"

    # >>> demand-sibling-shape
    # The gated bead must RESOLVE before anything is filed: a demand nothing
    # gates still reads as a question someone owes an answer to. `bd show`
    # answers an ARRAY on success and a bare {"error":…} OBJECT otherwise, and
    # control chars in notes break the parse.
    gated_raw=$(gc bd show "$gated" --json 2>/dev/null || true)
    gated_json=$(printf '%s' "$gated_raw" | scrub)
    gated_id=$(printf '%s' "$gated_json" | jq -r --arg b "$gated" \
        'if type == "array"
         then [ .[] | select(type == "object" and (.id // "") == $b) ] | first | (.id // empty)
         else empty end' 2>/dev/null || true)
    [ -n "$gated_id" ] \
        || { echo "$PROG: demand: '$gated' does not resolve in any rig ledger — nothing filed." >&2; exit 4; }
    # A parent-child edge is stored on the CHILD with the PARENT in the
    # depends-on slot, so the gated bead's own row is where its parent is read;
    # asking the parent for its children answers nothing.
    parent=$(printf '%s' "$gated_json" | jq -r \
        '[ .[0].dependencies[]?
           | select(((.dependency_type // .type // "") | tostring) == "parent-child")
           | ((.id // .depends_on_id // "") | tostring) ]
         | map(select(. != "")) | .[0] // ""' 2>/dev/null || true)
    # <<< demand-sibling-shape

    existing=$(gc bd list --status=open,in_progress --json --limit=0 2>/dev/null \
        | scrub \
        | jq -r --arg g "$gated" \
            '[ .[]? | select((.metadata["gc.demand_for"] // "") == $g) | .id ] | first // empty' 2>/dev/null || true)

    if [ -n "$existing" ]; then
        demand="$existing"
        set -- --title "$text" \
               --set-metadata "gc.takeaway=$text" \
               --set-metadata "gc.takeaway_at=$(iso_now)" \
               --set-metadata "gc.takeaway_by=$by" \
               --set-metadata "gc.takeaway_settled="
        [ -n "$who" ] && set -- "$@" --assignee "$who"
        gc bd update "$demand" "$@" >/dev/null 2>&1 \
            || { echo "$PROG: demand: could not refresh the open demand $demand on $gated" >&2; exit 4; }
        # A demand IS a wait on a person, so a settled disposition standing on
        # one is the wait check's blind spot at its worst: the bead nothing
        # re-asks is the bead this verb exists to file. The refresh clears the
        # key, and a clear that did not land is read back and repaired here. A
        # demand filed below carries no prior stamp, so its clear has nothing to
        # outlive.
        settled_got=$(meta_now "$demand" gc.takeaway_settled)
        if [ -n "$settled_got" ]; then
            gc bd update "$demand" --set-metadata "gc.takeaway_settled=" >/dev/null 2>&1 || true
            settled_got=$(meta_now "$demand" gc.takeaway_settled)
        fi
        if [ -n "$settled_got" ]; then
            echo "$PROG: demand: $demand reads gc.takeaway_settled='$settled_got' after the refresh — it is filed and it blocks $gated, but doctor/check-wait-is-an-edge reads it as a wait already discharged. Clear it by hand: gc bd update $demand --set-metadata gc.takeaway_settled=" >&2
            exit 4
        fi
        echo "$PROG: demand: refreshed the open demand $demand on $gated; no second bead filed" >&2
    else
        set -- -t "$kind" --title "$text" -d "$body"
        [ -n "$parent" ] && set -- "$@" --parent "$parent"
        demand=$(gc bd create "$@" --json 2>/dev/null \
            | scrub | jq -r '.id // .[0].id // empty' 2>/dev/null || true)
        # A create routed to the wrong ledger returns an id rather than an
        # error, and that id can never carry an edge to $gated — so the prefix
        # is checked, not assumed.
        case "$demand" in
            ""|null)     echo "$PROG: demand: bd create returned no id — nothing filed on $gated." >&2; exit 4 ;;
            "$prefix"-*) : ;;
            *)           echo "$PROG: demand: bd create filed $demand, whose prefix is not '$prefix' — it landed in another rig's ledger and can never gate $gated. Close it by hand and re-run from the rig that owns $gated." >&2; exit 4 ;;
        esac
        set -- --set-metadata "gc.takeaway=$text" \
               --set-metadata "gc.takeaway_at=$(iso_now)" \
               --set-metadata "gc.takeaway_by=$by" \
               --set-metadata "gc.takeaway_settled=" \
               --set-metadata "gc.demand_for=$gated" \
               --set-metadata "gc.routed_to=human"
        [ -n "$who" ] && set -- "$@" --assignee "$who"
        gc bd update "$demand" "$@" >/dev/null 2>&1 \
            || { echo "$PROG: demand: filed $demand but could not stamp it — it is not on the operator's queue yet. Re-run this command." >&2; exit 4; }
    fi

    # `dep add <gated> <demand>` reads "<gated> is blocked by <demand>", so the
    # row lands on the gated bead — the side that is waiting.
    for _w in $gated $also; do
        [ -n "$_w" ] || continue
        if [ "$_w" = "$demand" ]; then
            echo "$PROG: demand: --also-blocks $_w is the demand itself; skipped" >&2
            continue
        fi
        if gc bd dep add "$_w" "$demand" -t blocks >/dev/null 2>&1; then
            echo "blocks edge: $_w depends on $demand"
        else
            echo "$PROG: demand: could not wire $_w -> $demand (already wired, a cycle, another store, or $_w is an ancestor of the demand)" >&2
        fi
    done

    # Read every requested edge back off the bead that carries it. A `dep add`
    # that fails on an edge already present is indistinguishable from one that
    # wrote nothing, so its exit status settles neither; the row does. An
    # --also-blocks target is read back on the same terms as the gated bead:
    # an edge missing there leaves that work reading ready against a demand
    # that was supposed to gate it, which is what this verb exists to remove.
    unwired=""
    for _w in $gated $also; do
        [ -n "$_w" ] || continue
        if [ "$_w" = "$demand" ]; then continue; fi
        w_after=$(gc bd show "$_w" --json 2>/dev/null | scrub || true)
        have_edge=$(printf '%s' "$w_after" | jq -r --arg d "$demand" \
            '[ .[0].dependencies[]?
               | select(((.dependency_type // .type // "") | tostring) == "blocks")
               | ((.id // .depends_on_id // "") | tostring) ]
             | map(select(. == $d)) | length' 2>/dev/null || true)
        case "$have_edge" in ''|*[!0-9]*) have_edge=0 ;; esac
        if [ "$have_edge" -lt 1 ]; then unwired="$unwired $_w"; fi
    done
    if [ -n "$unwired" ]; then
        for _w in $unwired; do
            echo "$PROG: demand: $_w is NOT blocked by $demand — the edge did not land, so the work reads ready while a person owes an answer. Wire it by hand: gc bd dep add $_w $demand -t blocks" >&2
        done
        exit 4
    fi

    bust_cache
    echo "demand $demand blocks $gated (by $by, $kind): $text"
}

# ── Verb: open ───────────────────────────────────────────────────────
# File a VISIT on the bead — a small child bead in the subject's
# continuation group, routed to the rig-qualified converse pool (the
# canonical gate-visit lines, formulas/mol-visit.toml). One open visit per
# subject; the subject must RESOLVE first so a typo cannot manufacture a
# visit (tk-ujwvt). --reason is the short title tail, --body the brief the
# converse session reads at claim time — callers with their own origin
# (gc-visit-open.sh) pass both rather than misreporting the board wording.
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

    # Pin bd at the bead's rig (cross-rig filing) and export its rig as GC_RIG
    # so the gate-visit POOL line rig-qualifies the converse pool.
    path=$(rig_path_for_bead "$bead")
    [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"
    rig=$(rig_name_for_bead "$bead")
    [ -n "$rig" ] && export GC_RIG="$rig"

    # The subject must EXIST before anything is filed: fail CLOSED on every
    # unhappy reading — the alternative is filing a visit on an unverified
    # subject. Distinct messages: each reading needs a different operator move.
    # >>> open-subject-exists
    subject_raw=$(gc bd show "$bead" --json 2>/dev/null || true)
    # `bd show` answers an ARRAY on success, a bare {"error":…} OBJECT
    # otherwise; control chars in notes break the parse (must not read as
    # "missing"). Id compared for EQUALITY with what was typed. Deliberately
    # UNPINNED: `gc bd show <id>` resolves across ledgers regardless of
    # BEADS_DIR; pinning --db by prefix would false-refuse a real subject.
    subject_clean=$(printf '%s' "$subject_raw" | scrub)
    subject=$(printf '%s' "$subject_clean" \
        | jq -r --arg b "$bead" \
            'if type == "array"
             then [ .[] | select(type == "object" and (.id // "") == $b) ] | first | (.id // empty)
             else empty end' 2>/dev/null || true)
    if [ -z "$subject" ]; then
        # Not-found is the specific "no issues found" error; any OTHER error
        # means the read FAILED and existence is unknown — reporting an outage
        # as a typo sends the operator hunting one that is not there.
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

    # Already held? A visit records its subject twice — the
    # gc.continuation_group stamp and the tracks edge — and only the edge has
    # proved reliable (su-ab9je: the stamp landed empty), so match EITHER.
    # The $s != "" arm keeps an empty stamp from matching an empty subject.
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

    # What this sitting is FOR, in the caller's words; resolved outside the
    # marked block so the block stays a verbatim copy of the canonical form.
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
    # Read the group stamp back and repair it from the subject if it landed
    # empty: it can land present-but-empty while every sibling stamp in the
    # same update lands, and an empty group disables converse's group-scoped
    # re-claim fence. Repair and warn, never exit — this block files the one
    # visit for its scope, and on a persistent miss the tracks edge still
    # carries the subject for guards that read the union.
    GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
    if [ "$GROUP_GOT" != "$bead" ]; then
      echo "gate-visit: warning: gc.continuation_group on $VISIT read back as '$GROUP_GOT', expected '$bead' — repairing" >&2
      gc bd update "$VISIT" --set-metadata "gc.continuation_group=$bead" || true
      GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
      if [ "$GROUP_GOT" = "$bead" ]; then
        echo "gate-visit: the repair landed on $VISIT" >&2
      else
        echo "gate-visit: warning: the repair did not land on $VISIT — the tracks edge still carries the subject, and the live-visit guards read the union" >&2
      fi
    fi
    # <<< gate-visit
    bust_cache

    echo "$PROG: visit $VISIT filed on $bead (pool $POOL) — a converse session will spawn (cold) or vacuum it (warm)."
    echo "       Attach via the sessions picker."
}

# ── Verb: react ──────────────────────────────────────────────────────
# Thin wrapper over tools/gc-proactive.sh `sling` (which owns the
# budget/cap clamp and the codex-gated mr merge path): slings
# mol-first-reaction at the bead so a worker writes a first-reaction card
# and stamps gc.takeaway.
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

    # Pin bd at the bead's rig (parity with open).
    path=$(rig_path_for_bead "$bead")
    [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"

    # gc-proactive.sh rig-qualifies its pool target from GC_RIG and fails
    # closed when unset. Gate on the NAME resolving — not on $path/.beads
    # existing — so a cross-rig react still qualifies the target.
    rig=$(rig_name_for_bead "$bead")
    [ -n "$rig" ] && export GC_RIG="$rig"

    # The reason is log-only operator intent; gc-proactive.sh has no --reason.
    [ -n "$reason" ] && echo "$PROG: react $bead — $reason" >&2

    set -- sling "$bead"
    [ -n "$nudge" ] && set -- "$@" --nudge
    [ -n "$dry" ] && set -- "$@" --dry-run
    "$tool" "$@" || { echo "$PROG: react: gc-proactive.sh sling '$bead' failed" >&2; exit 4; }

    # The reaction lands async in the slung session; just clear the cache.
    if [ -z "$dry" ]; then bust_cache; fi
}

# ── Verb: dismiss ────────────────────────────────────────────────────
# The operator's explicit "I am done with this". Two writes, because two
# surfaces hold the subject in view and neither lets go on its own:
#
#   the SITTING — converse runs with no idle_timeout, so a held visit keeps
#   its pane up until something closes the visit. Closing it here is the only
#   act that ends a sitting the operator no longer wants.
#
#   the ROW — a closed anchor keeps its row in the DONE band. gc.dismissed_at
#   is what the gather reads to stop offering it on the operator's word. A row
#   also ages out once it has been closed longer than GC_HELM_DONE_WINDOW.
#
# Order is: visit half first, row stamp second, and the row stamp runs only if
# the visit half accounted for every sitting. Inside the visit half the outcome
# stamp precedes the close on the same rule. A row retired over a sitting that
# is still up is the failure this verb exists to prevent, and it is the quiet
# one: the operator sees a cleared row and no longer has anything to look for.
# Idempotent in both halves.
cmd_dismiss() {
    bead=""; dismiss_reason=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason=*) dismiss_reason="${1#--reason=}"; shift ;;
            --reason)   shift; [ $# -gt 0 ] || { echo "$PROG: dismiss: --reason requires a value" >&2; exit 2; }
                        dismiss_reason="$1"; shift ;;
            -h|--help)  usage; exit 0 ;;
            -*) echo "$PROG: dismiss: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: dismiss takes one bead-id" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done
    [ -n "$bead" ] || { echo "$PROG: dismiss needs <bead-id>" >&2; usage; exit 2; }

    path=$(rig_path_for_bead "$bead")
    db=""; [ -n "$path" ] && [ -d "$path/.beads" ] && db="$path/.beads"

    # The subject must resolve before anything is written. Same fail-closed
    # reading as `open`: a read that did not answer is not a missing bead, and
    # dismissing an unverified id would stamp a marker nothing ever clears.
    subject_clean=$(gc bd show "$bead" --json 2>/dev/null | scrub)
    subject=$(printf '%s' "$subject_clean" \
        | jq -r --arg b "$bead" \
            'if type == "array"
             then [ .[] | select(type == "object" and (.id // "") == $b) ] | first | (.id // empty)
             else empty end' 2>/dev/null || true)
    if [ -z "$subject" ]; then
        echo "$PROG: dismiss: could not verify '$bead' — 'gc bd show' returned no bead with that id. Nothing was written." >&2
        exit 4
    fi
    subject_status=$(printf '%s' "$subject_clean" \
        | jq -r --arg b "$bead" \
            'if type == "array"
             then [ .[] | select(type == "object" and (.id // "") == $b) ] | first | (.status // "")
             else empty end' 2>/dev/null || true)

    # Pin bd at the SUBJECT's rig for the visit lookup and close, the way
    # `open` does. `bd list` reads whatever BEADS_DIR names, which in an agent
    # session is that agent's own rig — so an unpinned lookup on a cross-rig
    # subject searches the wrong ledger, finds no visit, and reports a sitting
    # ended that is still holding its pane. (The `show` above is deliberately
    # left unpinned: it resolves across ledgers on its own.)
    [ -n "$db" ] && export BEADS_DIR="$db"

    # Every OPEN visit on the subject, matched on EITHER recording of it: the
    # gc.continuation_group stamp or the tracks edge. cmd_open matches the same
    # union for the same reason (the stamp has landed empty in the field), and
    # a dismiss that missed the visit would leave the sitting it was asked to
    # end still holding the pane.
    #
    # sitting_failed carries the visit half's verdict to the row half below. A
    # read that did not answer is not the same as a subject with no visit, so
    # it fails rather than falling through to the empty case.
    #
    # The shape gate is the load-bearing half of that. An exit code of 0 is not
    # an answer on its own: empty stdout and a bare `null` both leave the derive
    # filter below exiting 0 with no visits, which is indistinguishable from a
    # subject that has none. Only a JSON ARRAY is an answer, and an empty one is
    # the honest "no visits".
    sitting_failed=0
    visits=""
    if visits_json=$(gc bd list --status=open,in_progress --json --limit=0 2>/dev/null); then
        if printf '%s' "$visits_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
            visits=$(printf '%s' "$visits_json" \
                | jq -r --arg s "$bead" \
                    '[ .[] | select((.metadata.task_kind // "") == "visit")
                       | select($s != ""
                                and (((.metadata["gc.continuation_group"] // "") == $s)
                                     or ([ .dependencies[]?
                                           | select((.type // "") == "tracks")
                                           | select((.depends_on_id // "") == $s) ] | length > 0)))
                       | .id ] | .[]' 2>/dev/null) || {
                sitting_failed=1
                visits=""
                echo "$PROG: dismiss: could not read the visits on $bead — 'gc bd list' answered nothing this verb could parse" >&2
            }
        else
            sitting_failed=1
            echo "$PROG: dismiss: could not read the visits on $bead — 'gc bd list' exited 0 without a JSON array of beads" >&2
        fi
    else
        sitting_failed=1
        echo "$PROG: dismiss: could not read the visits on $bead — 'gc bd list' failed (rig '${path:-?}')" >&2
    fi

    # A held visit is ASSIGNED to the converse session sitting on it, and bd's
    # close-authority guard refuses a close by anyone else. That guard is
    # exactly what this verb overrides — the operator is the holder's audience,
    # not its peer — so the refusal escalates to --force rather than standing.
    # Plain close first, so an unclaimed visit never pays for the override and
    # the forced case is a line the operator can see. (`gc bd close` accepts
    # --force; `gc bd update` does not.)
    closed_n=0
    for _v in $visits; do
        [ -n "$_v" ] || continue
        _why="dismissed by the operator${dismiss_reason:+: $dismiss_reason}"
        # gc.outcome is what every reader of a finished sitting looks at:
        # services/helm/internal/source/facts.go projects it onto the board's
        # Sitting.Outcome, so a visit closed without one is a sitting the board
        # cannot report. It is a PRECONDITION of the close rather than a
        # best-effort write beside it, because the lookup above reads only OPEN
        # visits. Once the close lands, no re-run of this verb reaches that
        # visit again, and the missing outcome is permanent. A visit that will
        # not take the stamp therefore stays open and keeps its pane, which is
        # the reading this verb already gives a visit that will not close. The
        # stamp sits outside the force ladder below because a metadata update
        # does not go through bd's close-authority guard, so it lands on a visit
        # held by a session name this actor cannot close under. A zero exit is
        # not proof it landed either: one --set-metadata pair can read back empty
        # while the call still exits 0, the same store behaviour meta_now guards
        # against on the takeaway path. So the stamp is read back and repaired
        # once, and only a visit whose gc.outcome reads "dismissed" enters the
        # close ladder. The close is irreversible to this verb, so a silently
        # dropped stamp would otherwise close the visit into the unreportable
        # state this precondition exists to prevent.
        if ! gc bd update "$_v" --set-metadata "gc.outcome=dismissed" >/dev/null 2>&1; then
            sitting_failed=1
            echo "$PROG: dismiss: could not stamp gc.outcome on visit $_v; it was NOT closed, because a closed visit with no outcome is a sitting the board cannot report and no re-run can reach. Its sitting keeps the pane; re-run dismiss." >&2
            continue
        fi
        outcome_got=$(meta_now "$_v" gc.outcome)
        if [ "$outcome_got" != "dismissed" ]; then
            gc bd update "$_v" --set-metadata "gc.outcome=dismissed" >/dev/null 2>&1 || true
            outcome_got=$(meta_now "$_v" gc.outcome)
        fi
        if [ "$outcome_got" != "dismissed" ]; then
            sitting_failed=1
            echo "$PROG: dismiss: gc.outcome on visit $_v read back as '${outcome_got:-<empty>}', not 'dismissed'; it was NOT closed, because a closed visit with no outcome is a sitting the board cannot report and no re-run can reach. Its sitting keeps the pane; re-run dismiss." >&2
            continue
        fi
        if gc bd close "$_v" --reason "$_why" >/dev/null 2>&1; then
            closed_n=$((closed_n + 1))
            echo "$PROG: dismiss: closed visit $_v — the sitting on $bead ends"
        elif gc bd close "$_v" --reason "$_why" --force >/dev/null 2>&1; then
            closed_n=$((closed_n + 1))
            echo "$PROG: dismiss: closed visit $_v over its holder's claim — the sitting on $bead ends"
        else
            sitting_failed=1
            echo "$PROG: dismiss: could not close visit $_v; its sitting keeps the pane. Close it by hand: gc bd close $_v --force" >&2
        fi
    done

    # The row is the operator's only evidence that a sitting is still up, so it
    # may not be retired while one is. Nothing is written on this arm: a second
    # dismiss after the visit is dealt with does both halves.
    if [ "$sitting_failed" -ne 0 ]; then
        # Any visit that DID close changed the board's Held marker, so the
        # cache goes even though the row half did not run.
        bust_cache
        echo "$PROG: dismiss: $bead was NOT dismissed — the sitting is unaccounted for, so its row stays on the board. Nothing was stamped on the subject; each unfinished visit above says what it needs, and a re-run resumes from there." >&2
        exit 4
    fi

    set --
    set -- "$@" --set-metadata "gc.dismissed_at=$(iso_now)" \
               --set-metadata "gc.dismissed_by=${GC_SESSION_NAME:-operator}"
    [ -n "$dismiss_reason" ] && set -- "$@" --append-notes "Dismissed from the helm board: $dismiss_reason"
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    if gc bd update "$bead" ${db:+--db "$db"} "$@" >/dev/null 2>&1; then
        # Say which of the two things actually happened. The marker only
        # retires a DONE row, so on a bead that is still OPEN the row stays —
        # it is live work, and a verb that claimed to have cleared it would be
        # teaching the operator that dismiss hides things that still need them.
        if [ "$subject_status" = "closed" ]; then
            echo "$PROG: dismiss: $bead marked dismissed — it leaves the board's DONE band"
        else
            echo "$PROG: dismiss: $bead marked dismissed (status=${subject_status:-unknown}) — it is still open, so it keeps its live row; the marker retires the DONE row it gets once it closes"
        fi
    else
        echo "$PROG: dismiss: could not stamp gc.dismissed_at on '$bead' (rig '${path:-?}'); its row stays on the board" >&2
        exit 4
    fi
    bust_cache
    [ "$closed_n" -eq 0 ] && echo "$PROG: dismiss: no open visit on $bead — nothing was holding a sitting"
    return 0
}

# ── Dispatch ─────────────────────────────────────────────────────────
case "${1:-}" in
    open)          shift; cmd_open "$@" ;;
    react)         shift; cmd_react "$@" ;;
    takeaway)      shift; cmd_takeaway "$@" ;;
    demand)        shift; cmd_demand "$@" ;;
    dismiss)       shift; cmd_dismiss "$@" ;;
    board)         echo "$PROG: the board moved to 'helm-svc board' (services/helm); this script keeps only the write verbs" >&2; exit 2 ;;
    -h|--help|help) usage; exit 0 ;;
    *)             echo "$PROG: unknown verb '${1:-}' (try: open, react, takeaway, demand, dismiss, help; the board is 'helm-svc board')" >&2; usage; exit 2 ;;
esac
