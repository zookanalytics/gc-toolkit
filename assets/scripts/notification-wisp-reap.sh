#!/usr/bin/env bash
# notification-wisp-reap.sh — collapse the copies of a repeated core
# "ESCALATION: <headline>" notice in the city store to one open notice.
#
# core's bootstrap pack mails a fresh "ESCALATION: <headline>" message into the
# city (HQ) store each time a monitored condition re-fires, rather than
# refreshing the standing one, so the copies accumulate without bound on the
# operator's board. This periodic sweep of the city store closes every open
# copy of one headline but the newest. It does not change how core creates the
# notices — that is upstream — so it is a backstop, the notification
# counterpart to the HQ-store marooned-work backstop.
#
# City scope: the notices live in the one city store. The sweep is idempotent;
# a pass skipped or cut short by its budget costs only the reap the next pass
# takes instead.
#
# Usage:
#   notification-wisp-reap.sh            reap duplicate notices, print a summary
#   notification-wisp-reap.sh --dry-run  report the plan, close nothing
#   notification-wisp-reap.sh --db PATH  city store to sweep (default: the
#                                        city_path from `gc rig list`)
# Exit: 0 reaped or nothing to do · 1 the city store or the enumeration could
#       not be read · 2 usage
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
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# Every open infra bead in the city store, read once. A non-array answer is a
# store we cannot trust — reap nothing and say so.
wisps_json="$("$GC" bd list --db "$CITY_DB" --include-infra --status open --json --limit 0 2>/dev/null)" || wisps_json=""
if ! printf '%s' "$wisps_json" | jq -e 'type=="array"' >/dev/null 2>&1; then
    echo "$PROG: could not read the city store at $CITY_DB — reaping nothing" >&2
    exit 1
fi

closed_esc=0
detail=""

# The pass feeds the summary below, so it must read its whole enumeration or
# abort. A `<<<` here-string is backed by a $TMPDIR temp file; when that file
# cannot be created (a full disk) the redirection fails without `set -e`
# catching it, the loop runs zero times, and the all-zero summary is
# indistinguishable from a healthy empty queue. The pass instead writes its
# enumeration to a checked temp file and reads it with `< FILE`, which keeps the
# loop in this shell so its counters survive, then asserts it processed every
# enumerated row before the summary prints.
ESC_FILE=""
trap 'rm -f "$ESC_FILE" 2>/dev/null' EXIT

# ---- Duplicate escalation notices ---------------------------------------------
# The headline (the title) is the situation key, since these notices carry no
# metadata; collapse every open copy of one headline to the newest and close
# the rest.
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
    # These copies are assigned to "human" for the operator's board, so --force
    # past the store's assignee guard; only a proven duplicate is closed here.
    if [ "$DRY_RUN" -eq 1 ]; then
        closed_esc=$((closed_esc + 1))
    elif "$GC" bd close "$dup_id" --db "$CITY_DB" --force --reason "duplicate escalation notice; superseded by $keep_id (same situation); collapsed by notification-wisp-reap" >/dev/null 2>&1; then
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
echo "$PROG: $verb $closed_esc duplicate escalation notices (kept $kept_esc distinct)"
[ -n "$detail" ] && printf '%s' "$detail"
exit 0
