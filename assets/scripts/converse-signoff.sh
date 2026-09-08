#!/usr/bin/env bash
# converse-signoff.sh — step 7 of the converse loop: write the durable trace a
# finished sitting owes to the item, and discharge the hold, BEFORE the sign-off
# is posted and the visit is closed.
#
# It stamps the closing takeaway on the item, reads it back, and discharges the
# demand the hold filed. One question decides the discharge: did the decision
# this hold waited on land here (--ruled yes) or not (--ruled no)?
#   --ruled yes: the operator ruled in this thread. The gate is RESOLVED (a
#     pre-gate demand is closed on the same terms), and where the item still
#     reads `held` it is released back to the pool that owns it.
#   --ruled no:  cut short, or the question outlived the sitting. The demand is
#     re-stated so the wait stays a graph state, and the item stays `held`.
# `held` is keyed to this sitting's outcome, not to the state read off the item,
# because the cut-short exit runs this same discharge on an item still waiting.
#
# What is waiting on the item is the caller's to state: one --waiting-on per
# bead it ROUTED work into, --no-wait when it settled the subject and nothing is
# waiting, and NEITHER where the subject is parked for a person. The writers
# (gc-helm.sh, lifecycle.sh) are SEARCHED for on the candidate roots.
#
# Usage:
#   converse-signoff.sh --visit <id> --outcome "<takeaway, ≤140 chars>" \
#     [--subject <id>] [--ruled yes|no] \
#     [--no-wait | --waiting-on <bead> ...] \
#     [--ruling "<one line>"] [--still-owed "<≤140 chars>"] [--route <pool|human>]
#   --outcome is required. --ruled defaults to `no`. --ruled yes requires
#   --ruling and --route; --ruled no requires --still-owed.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

VISIT=""
SUBJECT="${SUBJECT:-}"
OUTCOME=""
RULED=no
RULING=""
STILL_OWED=""
ROUTE=""
WAIT=()

die() { echo "converse-signoff: $1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --visit)      shift; [ $# -gt 0 ] || die "--visit needs a value"; VISIT="$1" ;;
    --subject)    shift; [ $# -gt 0 ] || die "--subject needs a value"; SUBJECT="$1" ;;
    --outcome)    shift; [ $# -gt 0 ] || die "--outcome needs a value"; OUTCOME="$1" ;;
    --ruled)      shift; [ $# -gt 0 ] || die "--ruled needs yes|no"; RULED="$1" ;;
    --ruling)     shift; [ $# -gt 0 ] || die "--ruling needs a value"; RULING="$1" ;;
    --still-owed) shift; [ $# -gt 0 ] || die "--still-owed needs a value"; STILL_OWED="$1" ;;
    --route)      shift; [ $# -gt 0 ] || die "--route needs a value"; ROUTE="$1" ;;
    --no-wait)    WAIT+=(--no-wait) ;;
    --waiting-on) shift; [ $# -gt 0 ] || die "--waiting-on needs a bead id"; WAIT+=(--waiting-on "$1") ;;
    -h|--help)    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            die "unknown argument '$1'" ;;
  esac
  shift
done

[ -n "$VISIT" ]   || die "--visit is required"
[ -n "$OUTCOME" ] || die "--outcome is required"
case "$RULED" in yes|no) ;; *) die "--ruled must be yes or no" ;; esac
if [ "$RULED" = yes ]; then
  [ -n "$RULING" ] || die "--ruled yes requires --ruling (the reason the gate resolves with)"
  [ -n "$ROUTE" ]  || die "--ruled yes requires --route (where the item is released to)"
else
  [ -n "$STILL_OWED" ] || die "--ruled no requires --still-owed (what the item still waits on)"
fi
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v gc >/dev/null 2>&1 || die "gc is required"

ITEM=$(gc bd show "$VISIT" --json \
  | scrub | jq -r '.[0].metadata.stall_root // ""')
ITEM="${ITEM:-$SUBJECT}"
HELM=""
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/gc-helm.sh" ] && { HELM="$cand/assets/scripts/gc-helm.sh"; break; }
done
[ -n "$HELM" ] || echo "NO TAKEAWAY WRITER on any candidate root — say so in the sign-off; the item carries no trace of this sitting"
# What is waiting on $ITEM now that this sitting is over. Three shapes,
# exactly one true, and this sitting is the last reader that can tell them
# apart: one --waiting-on per bead it ROUTED work into; --no-wait when it
# settled the subject and nothing is waiting; EMPTY only where the subject
# is parked for a person, which doctor/check-wait-is-an-edge reports as a
# wait nothing re-asks, because that is what it is.
# An ARRAY, not a string: this city runs zsh, which does not word-split an
# unquoted parameter, so a populated string arrives as ONE argument and the
# call dies with `unknown flag` on exactly the sittings the flag exists for.
# "${WAIT[@]}" expands to nothing when empty and to one argument per element
# otherwise, in both bash and zsh.
"$HELM" takeaway "$ITEM" "$OUTCOME" --by converse "${WAIT[@]}" \
  || echo "TAKEAWAY FAILED on $ITEM — re-run it before closing; nothing below records this sitting"
# Read the takeaway back on the ITEM. The gc.outcome check below proves the
# VISIT stamp and says nothing about the item, so a takeaway that died still
# closes clean — the unstamped close this block exists to prevent, one bead
# over.
gc bd show "$ITEM" --json | scrub \
  | jq -e '.[0].metadata["gc.takeaway"] // empty' >/dev/null \
  || echo "NO TAKEAWAY ON $ITEM — do not close until it lands"
# Discharge the hold. One question decides both halves — did the decision
# this sitting waited on land here? — so both read the same switch.
# --include-gates: the demand is a human gate, hidden from `bd list` by
# default, so the discharge would otherwise never find it.
DEMAND=$(gc bd list --status=open,in_progress --include-gates --json --limit=0 | scrub \
  | jq -r --arg i "$ITEM" '[ .[]? | select((.metadata["gc.demand_for"] // "") == $i)
                             | select((.assignee // "") == "") | .id ] | first // empty')
if [ -n "$DEMAND" ] && [ "$RULED" = yes ]; then
  # SETTLED — the operator ruled in this thread. Resolving the gate lifts
  # the block and $ITEM goes back to the pool. A demand filed before
  # demands were gates (issue_type=decision) is refused by `gate resolve`
  # ("is not a gate issue"), so it is closed on the same terms instead.
  gc bd gate resolve "$DEMAND" --reason "$RULING" \
    || gc bd close "$DEMAND" --reason "$RULING"
elif [ -n "$DEMAND" ]; then
  # STILL OWED — cut short, or the question outlived the sitting. The
  # demand stays open, re-stated, so the wait stays a graph state.
  "$HELM" demand "$ITEM" "$STILL_OWED" --by converse
fi
# `held` is cleared by a ruling, not by a sitting ending. The cut-short exit
# runs this same block on an item still waiting, so the release is keyed to
# this sitting's outcome rather than to the state read off the item. Erring
# toward the hold leaves a bead visibly routed to a person; erring the other
# way restores the untraceable wait this state exists to end.
LC=""
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/lifecycle.sh" ] && { LC="$cand/assets/scripts/lifecycle.sh"; break; }
done
if [ "$RULED" = yes ] && [ -n "$LC" ] && [ "$("$LC" state "$ITEM" 2>/dev/null)" = "held" ]; then
  "$LC" transition "$ITEM" --to unanchored --route "$ROUTE" \
    || echo "RELEASE FROM held FAILED on $ITEM — it still reads as waiting on a person"
fi
