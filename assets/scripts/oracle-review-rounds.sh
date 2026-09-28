#!/bin/bash
# A deterministic goal oracle: the second-review rate in the gc-toolkit bead
# store, as a percentage, over a trailing window (docs/goal-keeper.md).
#
# This is a MEASUREMENT, not a gate. The old per-anchor review-round CAP was
# retired (specs/tk-p82tvo/round-cap-retirement.md); convergence is judged, not
# capped. This script only counts, so a goal can measure whether the rate is
# falling — it caps nothing and blocks no merge.
#
# The metric: of the work anchors that reached a terminal state in the window,
# the fraction that took two or more review rounds.
#
#   anchor terminal in window  status=closed, merge_result in
#                              {merged, abandoned, duplicate}, closed in window,
#                              and not itself a rework or merge bead.
#   a review round             a task_kind=review bead pointing at the anchor
#                              (anchor_bead) that carries BOTH review_branch and a
#                              signoff_verdict. Requiring both counts a genuine
#                              decided round and drops two things that are not
#                              rounds: validator approve-outcome beads (no
#                              review_branch) and pre-redesign commit-churn
#                              re-reads (no signoff_verdict). See
#                              specs/tk-ztapg/review-cycle-architecture.md.
#
# Prints the rate as a bare number on the last stdout line (the metric oracle
# contract). Diagnostics — the window, the counts, the histogram — go to stderr.
#
# Uses raw `bd`, never `gc bd`: the judge runs this inline in the control
# dispatcher where `gc`'s config load can be cold and die. Each call is marked
# `# raw-bd:` for the lint.
#
# Usage: oracle-review-rounds.sh [--window-days N] [--since YYYY-MM-DD] [--min-rounds K]
# exit: 0 printed a rate · 1 no terminal anchors in the window (cannot measure)
#       · 2 usage error or the store was unreadable
set -uo pipefail

PROG=oracle-review-rounds
err() { echo "$PROG: $*" >&2; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

WINDOW_DAYS=30
SINCE=""
MIN_ROUNDS=2

while [ $# -gt 0 ]; do
	case "$1" in
	--window-days) WINDOW_DAYS="${2:-}"; shift 2 || { err "missing value for --window-days"; exit 2; } ;;
	--since)       SINCE="${2:-}"; shift 2 || { err "missing value for --since"; exit 2; } ;;
	--min-rounds)  MIN_ROUNDS="${2:-}"; shift 2 || { err "missing value for --min-rounds"; exit 2; } ;;
	-h | --help)   err "usage: $PROG [--window-days N] [--since YYYY-MM-DD] [--min-rounds K]"; exit 2 ;;
	*)             err "unknown argument '$1'"; exit 2 ;;
	esac
done

case "$MIN_ROUNDS" in '' | *[!0-9]*) err "--min-rounds must be an integer"; exit 2 ;; esac

# Window cutoff: an explicit --since wins; otherwise today minus the window.
if [ -n "$SINCE" ]; then
	CUTOFF="$SINCE"
else
	case "$WINDOW_DAYS" in '' | *[!0-9]*) err "--window-days must be an integer"; exit 2 ;; esac
	CUTOFF=$(date -u -d "-${WINDOW_DAYS} days" +%Y-%m-%d 2>/dev/null \
		|| date -u -v-"${WINDOW_DAYS}"d +%Y-%m-%d 2>/dev/null)
fi
[ -n "$CUTOFF" ] || { err "could not compute the window cutoff date"; exit 2; }

# Terminal anchors closed in the window. --has-metadata-key narrows to beads that
# carry a merge_result at all; the jq then keeps only terminal, non-rework ones.
# raw-bd: gc bd loads the city config, which can be cold in the condition env
ANCHORS_JSON=$(bd list --has-metadata-key merge_result --status closed \
	--closed-after "$CUTOFF" --limit 0 --json 2>/dev/null | scrub)
case "$(printf '%s' "$ANCHORS_JSON" | jq -r 'type' 2>/dev/null)" in
array) ;;
*) err "could not read anchors from the store"; exit 2 ;;
esac
ANCHORS=$(printf '%s' "$ANCHORS_JSON" | jq -c '
	[ .[]
	  | select((.title|startswith("Rework branch"))|not)
	  | select((.title|startswith("Rework PR#"))|not)
	  | select((.title|startswith("Merge main into"))|not)
	  | select((.metadata.task_kind // "") != "rework")
	  | select(.metadata.merge_result as $m | ["merged","abandoned","duplicate"] | index($m))
	  | .id ]' 2>/dev/null)
[ -n "$ANCHORS" ] || { err "anchor filter produced no output"; exit 2; }

N=$(printf '%s' "$ANCHORS" | jq 'length')
if [ "$N" -eq 0 ]; then
	err "no terminal anchors closed since $CUTOFF; cannot measure the rate"
	exit 1
fi

# Decided review rounds, grouped by anchor. Require review_branch (a real
# dispatch, not a validator approve-outcome) AND signoff_verdict (a decided
# round, not churn).
# raw-bd: gc bd loads the city config, which can be cold in the condition env
REVIEWS_JSON=$(bd list --metadata-field task_kind=review \
	--status open,in_progress,closed,blocked,deferred --limit 0 --json 2>/dev/null | scrub)
case "$(printf '%s' "$REVIEWS_JSON" | jq -r 'type' 2>/dev/null)" in
array) ;;
*) err "could not read review beads from the store"; exit 2 ;;
esac
ROUNDS=$(printf '%s' "$REVIEWS_JSON" | jq -c '
	[ .[]
	  | select((.metadata.review_branch // "") != "")
	  | select((.metadata.signoff_verdict // "") != "")
	  | .metadata.anchor_bead // empty ]' 2>/dev/null)

# rate = anchors whose decided-round count >= MIN_ROUNDS, over N, as a percent
# with one decimal.
RESULT=$(jq -n \
	--argjson anchors "$ANCHORS" \
	--argjson rounds "$ROUNDS" \
	--argjson min "$MIN_ROUNDS" '
	($rounds | group_by(.) | map({(.[0]): length}) | add // {}) as $rc
	| ($anchors | length) as $n
	| ([ $anchors[] | select(($rc[.] // 0) >= $min) ] | length) as $k
	| { n: $n, k: $k,
	    rate: (if $n > 0 then (($k * 1000 / $n) | floor) / 10 else 0 end),
	    hist: ([ $anchors[] | ($rc[.] // 0) ] | group_by(.) | map({(.[0]|tostring): length}) | add // {}) }')

RATE=$(printf '%s' "$RESULT" | jq -r '.rate')
# One decimal always, so the metric reads consistently in the trail (jq prints a
# whole-number rate as "50", awk here normalizes it to "50.0").
RATE=$(awk -v r="$RATE" 'BEGIN{printf "%.1f", r}')
K=$(printf '%s' "$RESULT" | jq -r '.k')
HIST=$(printf '%s' "$RESULT" | jq -c '.hist')

err "window: closed-after $CUTOFF (min-rounds=$MIN_ROUNDS)"
err "terminal anchors: $N; with >=$MIN_ROUNDS decided rounds: $K"
err "decided-round histogram (rounds:anchors): $HIST"
err "second-review rate: ${RATE}%"

# The metric value, last line of stdout.
printf '%s\n' "$RATE"
