#!/bin/sh
# gc-helm.sh — the helm WRITE verbs: takeaway, open, react.
# Job: write the operator-facing state the helm board renders. The board
# itself is `helm-svc board` (services/helm); this script renders nothing.
# Contract:
#   gc-helm open  <bead-id> [--reason "..."] [--body "..."]   file one visit (one open visit per subject)
#   gc-helm react <bead-id> [--reason "..."]                  sling a proactive first reaction
#   gc-helm takeaway <bead-id> "<text>" [--by ...] [--waiting-on <id>]... [--release]
# Callers: tmux-pick-helm.sh + gc-visit-open.sh (open), helm-svc POST
# /helm/open via GC_HELM_OPEN_TOOL (open — its stderr/stdout sentences are
# parsed by services/helm/internal/server, guarded by open_parity_test.go),
# converse and the proactive worker (takeaway), operators by hand.
# Exit codes: 0 ok, 2 usage, 3 environment (jq/gc missing, rigs
# unenumerable — each failure names its own operator move, tk-lzdty),
# 4 verb runtime failure (bead not found / unverifiable / filing failed).

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
  gc-helm takeaway <bead-id> "<text>" [--by host|proactive|converse] [--waiting-on <bead-id>]... [--release]  set the board-visible takeaway headline (≤140 chars, ENFORCED)

The board is `helm-svc board` (services/helm). This script carries only the
write verbs. open files a visit in the picked bead's continuation group (pool
demand spawns/vacuums a converse session); its --reason is the short title
tail and --body the brief the converse session reads at claim time. react
slings a proactive first reaction via tools/gc-proactive.sh (its --reason is
log-only operator intent). takeaway stamps gc.takeaway (+_at/+_by) in one
update; --release also reopens/unassigns/clears the route and quiesces the
parked molecule's step beads; --waiting-on (repeatable) records the wait as a
`blocks` edge beside the prose so the board can re-ask whether it landed.
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

# ── Release helper: quiesce a parked molecule's step beads ───────────
# A parked molecule's STEP beads keep re-attracting pins (gc.routed_to /
# assignee / session_affinity) that re-spawn a polecat onto the husk
# (tk-xypcy). Walk live graph.v2 steps in reverse (step -> gc.root_bead_id
# -> root's gc.input_convoy_id -> the convoy's single tracked member) and
# clear the pins on exactly the steps whose root resolves to THIS anchor.
# Guards: fail closed on an unresolved/other anchor; NEVER close a step or
# rewrite its status; never de-route workflow-finalize; all pins in ONE
# update per step; selected by contract (gc.step_ref), never formula name
# (tk-q5r65); an absent root is the witness patrol's, not ours. Best-effort
# subshell. $1 = parked anchor id, $2 = rig .beads path or "".
# >>> quiesce-release-molecule-steps
quiesce_release_molecule_steps() (
    set +e
    _anchor="$1"; _db="$2"

    # shellcheck disable=SC2086  # ${_db:+--db "$_db"} expands to 0 or 2 space-free fields
    _steps=$(gc bd list --status=open,in_progress ${_db:+--db "$_db"} --json --limit=0 2>/dev/null || true)
    [ -n "$_steps" ] && [ "$_steps" != "[]" ] || exit 0

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
            _step=$(printf '%s'     "$_row" | jq -r '.step // empty' 2>/dev/null || true)
            _routed=$(printf '%s'   "$_row" | jq -r '.routed // empty' 2>/dev/null || true)
            _who=$(printf '%s'      "$_row" | jq -r '.assignee // empty' 2>/dev/null || true)
            _affinity=$(printf '%s' "$_row" | jq -r '.affinity // empty' 2>/dev/null || true)
            [ -n "$_sid" ] || continue

            # Never de-route the finalize step (the molecule's only escape path).
            case "$_step" in *.workflow-finalize) continue ;; esac
            case "$_routed" in *control-dispatcher*) continue ;; esac

            # Idempotent: already quiet -> nothing left to clear.
            [ -n "$_routed" ] || [ -n "$_who" ] || [ -n "$_affinity" ] || continue

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
# Stamp gc.takeaway/_at/_by in ONE update, then bust the cache. --release
# folds the proactive reaction-release (reopen, unassign, clear route,
# gc.proactive_reaction=1) into the same write and quiesces the parked
# molecule's steps. --waiting-on records each wait as a `blocks` edge —
# best-effort: the stamp is what the sitting owes the operator, so a
# rejected edge only warns and never fails the verb (tk-2plde).
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

    # Collapse whitespace runs and trim BEFORE the empty check and the cap.
    text=$(printf '%s' "$text" | tr -s '[:space:]' ' ')
    text="${text# }"; text="${text% }"
    [ -n "$text" ] || { echo "$PROG: takeaway needs \"<text>\" (the ≤${TAKEAWAY_MAX}-char one-line headline)" >&2; usage; exit 2; }

    # >>> takeaway-length-gate
    # REJECT over the cap, never truncate: only the author knows which clause
    # is the headline (tk-9tbbk.1). Measured in CODEPOINTS — what both
    # renderers measure — with a shell-count fallback so the gate cannot
    # silently fail open on a broken jq.
    tlen=$(printf '%s' "$text" | jq -Rsr 'length' 2>/dev/null || true)
    case "$tlen" in ''|*[!0-9]*) tlen=${#text} ;; esac
    if [ "$tlen" -gt "$TAKEAWAY_MAX" ]; then
        echo "$PROG: takeaway: text is $tlen chars; the cap is $TAKEAWAY_MAX" >&2
        echo "$PROG: takeaway: it renders as the board's NEEDS cell — one line, read at a glance. Cut it to the single sentence the operator needs and put the rest in the bead's notes." >&2
        exit 2
    fi
    # <<< takeaway-length-gate

    [ -n "$by" ] || by="host"

    path=$(rig_path_for_bead "$bead")
    db=""; [ -n "$path" ] && [ -d "$path/.beads" ] && db="$path/.beads"

    # Build args with `set --` ($text/$by contain spaces); --release rides the
    # SAME update so stamp + release stay one Dolt write.
    set --
    set -- "$@" --set-metadata "gc.takeaway=$text" \
               --set-metadata "gc.takeaway_at=$(iso_now)" \
               --set-metadata "gc.takeaway_by=$by"
    [ -n "$release" ] && set -- "$@" --status=open --assignee= \
               --set-metadata "gc.routed_to=" --set-metadata "gc.proactive_reaction=1"
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd update "$bead" ${db:+--db "$db"} "$@" >/dev/null 2>&1 \
        || { echo "$PROG: takeaway: could not update '$bead' (does it exist in rig '${path:-?}'?)" >&2; exit 4; }
    # Edges AFTER the stamp: a failure here degrades to prose-only, never
    # loses the conclusion. `dep add <bead> <blocker>` = "<bead> is blocked by
    # <blocker>", so the edge lands on <bead> — what the board reads.
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
    if [ -n "$release" ]; then
        quiesce_release_molecule_steps "$bead" "$db"
    fi
    echo "takeaway set on $bead (by $by)${release:+ [released]}: $text"
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
    # re-claim fence (tk-ax6y4, tk-msfmu). Repair and warn, never exit — this
    # block files the one visit for its scope, and on a persistent miss the
    # tracks edge still carries the subject for guards that read the union
    # (tk-d6ddn).
    GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
    if [ "$GROUP_GOT" != "$bead" ]; then
      echo "gate-visit: warning: gc.continuation_group on $VISIT read back as '$GROUP_GOT', expected '$bead' — repairing (tk-ax6y4)" >&2
      gc bd update "$VISIT" --set-metadata "gc.continuation_group=$bead" || true
      GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
      if [ "$GROUP_GOT" = "$bead" ]; then
        echo "gate-visit: the repair landed on $VISIT" >&2
      else
        echo "gate-visit: warning: the repair did not land on $VISIT — the tracks edge still carries the subject, and the live-visit guards read the union (tk-d6ddn)" >&2
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

# ── Dispatch ─────────────────────────────────────────────────────────
case "${1:-}" in
    open)          shift; cmd_open "$@" ;;
    react)         shift; cmd_react "$@" ;;
    takeaway)      shift; cmd_takeaway "$@" ;;
    board)         echo "$PROG: the board moved to 'helm-svc board' (services/helm); this script keeps only the write verbs" >&2; exit 2 ;;
    -h|--help|help) usage; exit 0 ;;
    *)             echo "$PROG: unknown verb '${1:-}' (try: open, react, takeaway, help; the board is 'helm-svc board')" >&2; usage; exit 2 ;;
esac
