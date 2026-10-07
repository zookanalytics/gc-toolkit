#!/usr/bin/env bash
# notification-wisp-reap.sh — retire city-store notification wisps that no
# longer point at anything live.
#
# core's bootstrap pack mails two kinds of notice into the city (HQ) store and
# retires neither. On every human gate it opens it mails a "Human gate awaiting
# you: <gate>" message, and each time a monitored condition re-fires it mails a
# fresh "ESCALATION: <headline>" copy. Nothing closes a gate notice when its
# gate resolves, and each escalation cycle files a new copy rather than
# refreshing the standing one, so both accumulate without bound on the
# operator's board.
#
# This is the notification counterpart to the HQ-store marooned-work backstop:
# a periodic sweep of the city store that (1) closes a gate notice once the gate
# named in its title is no longer open, and (2) collapses the copies of one
# escalation headline to a single open notice. It does not change how core
# creates the notices — that is upstream — so it is a backstop.
#
# City scope: the notices live in the one city store but name gates in every
# rig, and `gc bd show` resolves a gate across ledgers on its own, so one pass
# reads the whole city. Resolve each gate one id at a time: a multi-id show is
# single-store and silently drops a foreign-rig id, which would read as "gone".
# The sweep is idempotent; a pass skipped or cut short by its budget costs only
# the reap the next pass takes instead.
#
# Bias: an unreadable probe reaps NOTHING. A gate notice whose gate cannot be
# read, or resolves to something that is not a gate, is left alone — the pass
# only ever closes a notice it can prove is stale.
#
# Usage:
#   notification-wisp-reap.sh            reap stale notices, print a summary
#   notification-wisp-reap.sh --dry-run  report the plan, close nothing
#   notification-wisp-reap.sh --db PATH  city store to sweep (default: the
#                                        city_path from `gc rig list`)
# Exit: 0 reaped or nothing to do · 1 the city store or an enumeration could not
#       be read · 2 usage
# Caller: the notification-wisp-reap cooldown order.
set -uo pipefail

PROG="${0##*/}"
DRY_RUN=0
CITY_DB=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --db) [ $# -ge 2 ] || { echo "$PROG: --db needs a path" >&2; exit 2; }; CITY_DB="$2"; shift ;;
        --db=*) CITY_DB="${1#--db=}" ;;
        -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }

GC="${NOTIFICATION_WISP_REAP_GC:-gc}"

# Resolve the city (HQ) store unless one was named. `gc rig list` reports the
# city path directly; its `.beads` dir is the store the notices live in.
if [ -z "$CITY_DB" ]; then
    rigs_json="$("$GC" rig list --json 2>/dev/null)" || rigs_json=""
    CITY_DB="$(printf '%s' "$rigs_json" | jq -r '(.city_path // "") | if . == "" then empty else . + "/.beads" end' 2>/dev/null)"
fi
[ -n "$CITY_DB" ] || { echo "$PROG: could not resolve the city store (pass --db <path>/.beads) — reaping nothing" >&2; exit 1; }

# Every open infra bead in the city store, read once and filtered per pass. A
# non-array answer is a store we cannot trust — reap nothing and say so.
wisps_json="$("$GC" bd list --db "$CITY_DB" --include-infra --status open --json --limit 0 2>/dev/null)" || wisps_json=""
if ! printf '%s' "$wisps_json" | jq -e 'type=="array"' >/dev/null 2>&1; then
    echo "$PROG: could not read the city store at $CITY_DB — reaping nothing" >&2
    exit 1
fi

closed_gate=0; kept_gate=0; skipped_gate=0
closed_esc=0
detail=""

# Both passes feed the single summary below, so each must read its whole
# enumeration or abort. A `<<<` here-string is backed by a $TMPDIR temp file;
# when that file cannot be created (a full disk) the redirection fails without
# `set -e` catching it, the loop runs zero times, and the all-zero summary is
# indistinguishable from a healthy empty queue. Each pass instead writes its
# enumeration to a checked temp file and reads it with `< FILE`, which keeps the
# loop in this shell so its counters survive, then asserts it processed every
# enumerated row before the summary prints.
GATE_FILE=""; ESC_FILE=""
trap 'rm -f "$GATE_FILE" "$ESC_FILE" 2>/dev/null' EXIT

# ---- Pass 1: stale gate notices ---------------------------------------------
# A "Human gate awaiting you: <gate>" notice names its gate by id in the title.
# The notice is stale once that gate is no longer open — resolved, closed, or
# gone. Read each gate across ledgers and close the notice only on a proof of
# staleness; anything unreadable is left for a later pass.
gate_candidates="$(printf '%s' "$wisps_json" | jq -r '
    .[]?
    | select((.issue_type // "") == "message")
    | select((.title // "") | startswith("Human gate awaiting you: "))
    | [ .id, ((.title) | sub("^Human gate awaiting you: "; "")) ]
    | @tsv')"; gate_rc=$?
if [ "$gate_rc" -ne 0 ]; then
    echo "$PROG: could not enumerate gate notices (jq exit $gate_rc) — a failed read is not an empty queue; reaping nothing" >&2
    exit 1
fi
GATE_FILE="$(mktemp "${TMPDIR:-/tmp}/gctk-notification-wisp-reap.XXXXXX" 2>/dev/null)" || {
    echo "$PROG: could not create a temp file to enumerate gate notices — reaping nothing (retries next pass)" >&2
    exit 1
}
printf '%s\n' "$gate_candidates" > "$GATE_FILE" || {
    echo "$PROG: could not write the gate-notice enumeration — reaping nothing (retries next pass)" >&2
    exit 1
}
gate_expected="$(grep -c . "$GATE_FILE" 2>/dev/null || true)"; case "$gate_expected" in ''|*[!0-9]*) gate_expected=0 ;; esac
gate_processed=0

while IFS=$'\t' read -r notice_id gate_id; do
    [ -n "$notice_id" ] || continue
    gate_processed=$((gate_processed + 1))

    # A title tail that is not a bead id is not a gate reference we can resolve.
    if ! [[ "$gate_id" =~ ^[a-z]+-[a-z0-9]+$ ]]; then
        skipped_gate=$((skipped_gate + 1)); continue
    fi

    # Read the gate, keeping stdout and exit status separate: `gc bd show` exits
    # non-zero for an id that resolves to nothing yet still prints the not-found
    # object that proves the gate is GONE, so stdout must survive a non-zero exit
    # for that signature to classify. Anything that is not JSON at all is an
    # unreadable probe — never reap.
    show="$("$GC" bd show "$gate_id" --json 2>/dev/null)"; show_rc=$?
    if ! printf '%s' "$show" | jq -e . >/dev/null 2>&1; then
        skipped_gate=$((skipped_gate + 1)); continue
    fi
    row="$(printf '%s' "$show" | jq -c --arg g "$gate_id" '
        if type=="array" then ([ .[] | select((.id // "") == $g) ] | first)
        elif (.id // "") == $g then .
        else null end')"

    verdict=""
    if [ "$row" = "null" ] || [ -z "$row" ]; then
        # No bead resolved. GONE only on bd's not-found signature: a non-zero
        # exit carrying an object whose .error names no matching issue. Any other
        # unmatched payload we cannot classify, so it is left alone.
        if [ "$show_rc" -ne 0 ] && printf '%s' "$show" | jq -e 'type=="object" and ((.error // "") | test("no issues found"))' >/dev/null 2>&1; then
            verdict=gone
        else
            skipped_gate=$((skipped_gate + 1)); continue
        fi
    else
        itype="$(printf '%s' "$row" | jq -r '.issue_type // ""')"
        status="$(printf '%s' "$row" | jq -r '.status // ""')"
        if [ "$itype" != "gate" ]; then
            # The title id resolves to something that is not a gate — cannot
            # prove this notice is stale.
            skipped_gate=$((skipped_gate + 1)); continue
        fi
        if [ "$status" = "open" ]; then
            kept_gate=$((kept_gate + 1)); continue
        fi
        verdict=resolved
    fi

    # verdict is gone|resolved -> the notice is stale. A close that FAILS is
    # reported and counted skipped; it must not read as reaped.
    if [ "$DRY_RUN" -eq 1 ]; then
        closed_gate=$((closed_gate + 1))
    elif "$GC" bd close "$notice_id" --db "$CITY_DB" --reason "human gate $gate_id $verdict; stale notification wisp retired (notification-wisp-reap)" >/dev/null 2>&1; then
        closed_gate=$((closed_gate + 1))
    else
        skipped_gate=$((skipped_gate + 1))
        echo "$PROG: could not close stale gate notice $notice_id (gate $gate_id $verdict) — left for the next pass" >&2
        continue
    fi
    detail="${detail}  gate-notice ${notice_id} -> ${verdict} (gate ${gate_id})
"
done < "$GATE_FILE"
[ "$gate_processed" -eq "$gate_expected" ] || {
    echo "$PROG: read the gate-notice enumeration short ($gate_processed of $gate_expected) — reaping nothing (retries next pass)" >&2
    exit 1
}

# ---- Pass 2: duplicate escalation notices -----------------------------------
# core files a fresh "ESCALATION: <headline>" copy each cycle instead of
# refreshing the standing one. The headline (the title) is the situation key,
# since these notices carry no metadata; collapse every open copy of one
# headline to the newest and close the rest.
esc_close="$(printf '%s' "$wisps_json" | jq -r '
    [ .[]? | select((.issue_type // "") == "message") | select((.title // "") | startswith("ESCALATION:")) ]
    | group_by(.title)[]
    | (sort_by(.created_at // "")) as $g
    | ($g | last) as $keep
    | $g[0:-1][]
    | [ .id, $keep.id ]
    | @tsv')"; esc_rc=$?
if [ "$esc_rc" -ne 0 ]; then
    echo "$PROG: could not enumerate escalation notices (jq exit $esc_rc) — a failed read is not an empty queue; reaping nothing" >&2
    exit 1
fi
ESC_FILE="$(mktemp "${TMPDIR:-/tmp}/gctk-notification-wisp-reap.XXXXXX" 2>/dev/null)" || {
    echo "$PROG: could not create a temp file to enumerate escalation notices — reaping nothing (retries next pass)" >&2
    exit 1
}
printf '%s\n' "$esc_close" > "$ESC_FILE" || {
    echo "$PROG: could not write the escalation enumeration — reaping nothing (retries next pass)" >&2
    exit 1
}
esc_expected="$(grep -c . "$ESC_FILE" 2>/dev/null || true)"; case "$esc_expected" in ''|*[!0-9]*) esc_expected=0 ;; esac
esc_processed=0

while IFS=$'\t' read -r dup_id keep_id; do
    [ -n "$dup_id" ] || continue
    esc_processed=$((esc_processed + 1))
    if [ "$DRY_RUN" -eq 1 ]; then
        closed_esc=$((closed_esc + 1))
    elif "$GC" bd close "$dup_id" --db "$CITY_DB" --reason "duplicate escalation notice; superseded by $keep_id (same situation); collapsed by notification-wisp-reap" >/dev/null 2>&1; then
        closed_esc=$((closed_esc + 1))
    else
        echo "$PROG: could not close duplicate escalation notice $dup_id (keep $keep_id) — left for the next pass" >&2
        continue
    fi
    detail="${detail}  escalation ${dup_id} -> duplicate of ${keep_id}
"
done < "$ESC_FILE"
[ "$esc_processed" -eq "$esc_expected" ] || {
    echo "$PROG: read the escalation enumeration short ($esc_processed of $esc_expected) — reaping nothing (retries next pass)" >&2
    exit 1
}

# Distinct escalation headlines that retain one open notice (from the pre-close
# snapshot: each surviving headline keeps exactly one).
kept_esc="$(printf '%s' "$wisps_json" | jq -r '
    [ .[]? | select((.issue_type // "") == "message") | select((.title // "") | startswith("ESCALATION:")) ]
    | group_by(.title) | length')"

verb="closed"; [ "$DRY_RUN" -eq 1 ] && verb="would close"
echo "$PROG: $verb $closed_gate stale gate notices (kept $kept_gate live, skipped $skipped_gate), $verb $closed_esc duplicate escalation notices (kept $kept_esc distinct)"
[ -n "$detail" ] && printf '%s' "$detail"
exit 0
