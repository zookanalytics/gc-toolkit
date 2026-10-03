#!/usr/bin/env bash
# converse-signoff.sh — step 7 of the converse loop: write the durable trace a
# finished sitting owes to the item, and discharge the hold, BEFORE the sign-off
# is posted and the visit is closed.
#
# It stamps the closing takeaway on the item, reads it back, and discharges the
# demands the hold filed. A conversation wait gates the VISIT, an explicit merge
# hold gates the anchor; a sitting may have filed either or both, and each is
# discharged. One question decides each discharge: did the decision this hold
# waited on land here (--ruled yes) or not (--ruled no)?
#   --ruled yes: the operator ruled in this thread. Each gate is RESOLVED (a
#     pre-gate demand is closed on the same terms), and where the item still
#     reads `held` it is released back to the pool that owns it.
#   --ruled no:  cut short, or the question outlived the sitting. The wait is
#     consolidated onto the ITEM — a demand gating the VISIT is closed and
#     re-stated there — so it outlives the visit's close, the liveness sweep
#     (keyed on gc.demand_for=<item>) re-offers the next sitting, and on a PR
#     anchor the merge waits; a pre-PR item stays `held`.
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
#     [--ruling "<one line>"] [--still-owed "<≤140 chars>"] [--route <rig>/<agent>|human]
#   --outcome is required. --ruled defaults to `no`. --ruled yes requires
#   --ruling and --route; --ruled no requires --still-owed.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
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
# Discharge the hold. A conversation wait gates the VISIT (the default — a
# conversation does not freeze its subject) and an explicit merge hold gates the
# ITEM; a sitting may have filed either or both. --include-gates: a demand is a
# human gate, hidden from `bd list` by default, so the discharge would otherwise
# never find it.
DEMANDS_JSON=$(gc bd list --status=open,in_progress --include-gates --json --limit=0 | scrub)
# The open, unassigned demand gating a given bead, or empty. An empty target
# would match every bead that carries no gc.demand_for at all, so the caller
# guards against passing one.
demand_on() {
  [ -n "$1" ] || { printf ''; return; }
  printf '%s' "$DEMANDS_JSON" \
    | jq -r --arg i "$1" '[ .[]? | select((.metadata["gc.demand_for"] // "") == $i)
                           | select((.assignee // "") == "") | .id ] | first // empty'
}
if [ "$RULED" = yes ]; then
  # SETTLED — the operator ruled in this thread. Resolve each gate where it
  # sits: the visit demand lets the conversation conclude, the anchor demand
  # releases the merge. A demand filed before demands were gates
  # (issue_type=decision) is refused by `gate resolve` ("is not a gate issue"),
  # so it is closed on the same terms instead.
  for GATED in "$VISIT" "$ITEM"; do
    DEMAND=$(demand_on "$GATED")
    [ -n "$DEMAND" ] || continue
    gc bd gate resolve "$DEMAND" --reason "$RULING" \
      || gc bd close "$DEMAND" --reason "$RULING"
    # A demand's board sentence (gc.takeaway) is the QUESTION it was filed with,
    # and the ruling is the answer. Left only in the gate's close reason, which no
    # board reads, the closed demand lingers on the DONE band still asking and a
    # glance re-engages a settled decision. The takeaway verb overwrites it with the
    # ruling; --no-wait is what stamps gc.takeaway_settled, the settled mark only
    # that verb writes, so every board surface reads the answer as a discharged
    # wait. Run AFTER the close, so the demand never sits open-but-settled — the
    # shape doctor/check-wait-is-an-edge reads as a wait already discharged while it
    # still blocks. The verb's stamp is a plain metadata write, so it lands on the
    # closed demand; if it does not, the renderer still suppresses the stale question.
    "$HELM" takeaway "$DEMAND" "$RULING" --by converse --no-wait \
      || echo "COULD NOT STAMP THE RULING on $DEMAND — the board may still show its question; run: $HELM takeaway $DEMAND \"$RULING\" --by converse --no-wait"
  done
else
  # STILL OWED — cut short, or the question outlived the sitting. The wait must
  # persist on the ITEM, not on the VISIT: the liveness return trip keys on
  # gc.demand_for=<item>, so a demand there re-offers the next sitting, and on a
  # PR anchor it also freezes the merge — a sitting that abandoned an unresolved
  # question is the one case the merge should wait. A demand gating the VISIT
  # cannot carry that wait: the visit is this sitting's record and converse-settle
  # closes it next, stranding any demand left on it as a gate on closed work that
  # gate-visit-sweep names on stderr forever and `gate resolve` readies nothing.
  # So move it — close the visit demand, re-state the wait on the ITEM (idempotent:
  # one open demand per gated bead, so an anchor already holding the opt-in merge
  # demand is simply refreshed). A sitting that filed NO demand re-states none:
  # the discharge records only the waits the hold actually took.
  VD=""
  [ "$VISIT" != "$ITEM" ] && VD=$(demand_on "$VISIT")
  ID=$(demand_on "$ITEM")
  if [ -n "$VD" ]; then
    gc bd gate resolve "$VD" --reason "cut short; wait re-stated on $ITEM" \
      || gc bd close "$VD" --reason "cut short; wait re-stated on $ITEM"
    # Settle its board question so the closed demand does not linger asking;
    # the live wait now rides the ITEM demand below.
    "$HELM" takeaway "$VD" "cut short; wait moved to $ITEM" --by converse --no-wait \
      || echo "COULD NOT STAMP the moved-wait note on $VD — the board may still show its question"
  fi
  if [ -n "$VD" ] || [ -n "$ID" ]; then
    "$HELM" demand "$ITEM" "$STILL_OWED" --by converse
  fi
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

# Stash what the visit's PR-reminder close will say, for the writer that runs
# AFTER the visit is actually closed: converse-settle's close step on a normal
# sign-off, or converse-claim.sh's stranded-finish recovery. This script is the
# PRE-close durable trace, so posting "closed" here would run before the close
# lands — a death, a failed outcome stamp, or a failed close between here and
# there would leave the PR saying the visit closed while it is still open and
# holding the merge. The takeaway is the Summary; Actions Taken is what the
# sitting did: the work it routed, the ruling it reached, or what is still owed.
# The stamp lands even though this session still holds the visit, because a
# metadata write bypasses the claim guard.
routed=""
i=0
while [ "$i" -lt "${#WAIT[@]}" ]; do
  [ "${WAIT[$i]}" = "--waiting-on" ] && { i=$((i + 1)); routed="${routed:+$routed, }${WAIT[$i]}"; }
  i=$((i + 1))
done
SIGNOFF_ACTIONS=""
[ -n "$routed" ] && SIGNOFF_ACTIONS="routed work to $routed"
if [ "$RULED" = yes ]; then
  SIGNOFF_ACTIONS="${SIGNOFF_ACTIONS:+$SIGNOFF_ACTIONS; }ruling: $RULING (released to $ROUTE)"
elif [ -n "$STILL_OWED" ]; then
  SIGNOFF_ACTIONS="${SIGNOFF_ACTIONS:+$SIGNOFF_ACTIONS; }still owed: $STILL_OWED"
fi
gc bd update "$VISIT" \
  --set-metadata "gc.pr_visit_summary=$OUTCOME" \
  --set-metadata "gc.pr_visit_actions=$SIGNOFF_ACTIONS" \
  || echo "COULD NOT STASH the PR-reminder close text on $VISIT; its PR comment may stay 'open' after the visit closes"
