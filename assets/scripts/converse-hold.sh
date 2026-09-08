#!/usr/bin/env bash
# converse-hold.sh — step 5 of the converse loop: on the way into a hold, stamp
# what the sitting is waiting for and leave the trace a resume needs, BEFORE the
# framing is posted.
#
# A hold IS a demand: the operator owes an answer, and until it lands the item
# cannot move. So this files three things and gates on two of them:
#   1. the board-visible takeaway headline on the item (best-effort);
#   2. the demand bead — the human gate the item's work blocks on. If it does
#      not land there is no hold yet, only a takeaway that nothing re-asks, so
#      the caller must NOT post the framing (exit 1);
#   3. gc.hold_demand on THIS visit, the sole proof step 1's action=hold arm
#      reads to tell a real hold from a claim that died before step 2. The write
#      is read BACK off the visit and the caller must NOT frame unless it landed
#      (exit 1), because the write's own exit status cannot see a value that
#      never persisted.
# Then, where the item is still unanchored, it transitions to `held` so the
# anchor readers drop it while a person owes an answer.
#
# The item is the visit's stall_root, else the subject; the writers (gc-helm.sh,
# lifecycle.sh) are SEARCHED for on the candidate roots, never assumed, because
# $GC_RIG_ROOT is the rig that imported this agent and may hold no assets/.
#
# Inputs:
#   $1       the one decision or input needed (≤140 chars); the takeaway reads
#            "holding — <this>" and the demand reads "<this>"
#   VISIT    the visit bead reaching its hold (environment)
#   SUBJECT  its continuation group, the item fallback (environment)
# Exit: 0 the hold is real and stamped — post the framing; 1 a gate failed —
# do NOT post the framing, raise the failure in the thread; 2 usage.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

NEED="${1:-${HOLD_NEED:-}}"
VISIT="${VISIT:-}"
SUBJECT="${SUBJECT:-}"

[ -n "$VISIT" ] || { echo "converse-hold: \$VISIT is required" >&2; exit 2; }
[ -n "$NEED" ]  || { echo "converse-hold: the one decision or input needed is required (arg 1)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "converse-hold: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "converse-hold: gc is required" >&2; exit 2; }

ITEM=$(gc bd show "$VISIT" --json \
  | scrub | jq -r '.[0].metadata.stall_root // ""')
ITEM="${ITEM:-$SUBJECT}"
HELM=""
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/gc-helm.sh" ] && { HELM="$cand/assets/scripts/gc-helm.sh"; break; }
done
[ -n "$HELM" ] || echo "NO TAKEAWAY WRITER on any candidate root — say so in the thread before you wait; this hold will leave no trace"
"$HELM" takeaway "$ITEM" "holding — $NEED" --by converse
# A hold IS a demand: the operator owes an answer, and until it lands
# $ITEM cannot move. File it as a bead and let the edge carry the wait.
# >>> hold-demand-gate
# A pipeline answers its LAST command's status, so the demand call stays
# unpiped and its status is read on its own line. That exit is the only
# signal that the bead or the edge did not land, and any filter placed
# downstream of the call answers with its own success instead.
DEMAND_OUT=$("$HELM" demand "$ITEM" "$NEED" \
               --by converse)
DEMAND_RC=$?
DEMAND=$(printf '%s\n' "$DEMAND_OUT" | awk '/^demand /{print $2; exit}')
if [ "$DEMAND_RC" -ne 0 ] || [ -z "$DEMAND" ]; then
  echo "NO DEMAND FILED on $ITEM (status $DEMAND_RC). Nothing here is a hold yet, only a takeaway that nothing re-asks. Do NOT post the framing."
  echo "The verb printed its reason on stderr, and the repair command when an edge did not land. Repair it, then re-run this block until it names a demand id."
  echo "If it cannot be repaired, that failure is what the operator needs to hear. Raise it in the thread, and do not describe $ITEM as held."
  exit 1
fi
# <<< hold-demand-gate
# The demand exists, so this sitting has genuinely reached its hold. Stamp
# its id on THIS visit before waiting: step 1's action=hold arm reads
# gc.hold_demand off the visit bead to tell a real hold from a claim that
# died before step 2, and the key is attributable only because it lives on
# the visit rather than on the shared item.
# >>> hold-demand-stamp-gate
# Step 1 trusts gc.hold_demand as the SOLE proof of a real hold, so this
# stamp is the resume trace and nothing re-derives it. A bare update piped to
# echo fails open two ways. An update can be refused, and an update can report
# success without persisting. Either one leaves the framing posted with no
# trace, and a later scrollback-less restart reads BEGAN=no and closes this
# engaged sitting at step 2 as a dead premise. Read the key back off the visit
# and refuse to frame unless it landed, because the write's own exit status
# cannot see a value that never persisted.
gc bd update "$VISIT" --set-metadata "gc.hold_demand=$DEMAND" \
  || echo "gc.hold_demand update returned non-zero on $VISIT — verifying by read-back before trusting it"
STAMPED=$(gc bd show "$VISIT" --json | scrub \
  | jq -r '.[0].metadata["gc.hold_demand"] // ""')
if [ "$STAMPED" != "$DEMAND" ]; then
  echo "gc.hold_demand DID NOT PERSIST on $VISIT (found '${STAMPED:-<absent>}', want '$DEMAND'). Without it a restart re-checks the premise and can close this hold as a dead premise. Do NOT post the framing."
  echo "Re-run this block until the read-back names the demand. If it cannot be made to persist, that failure is what the operator needs to hear: raise it in the thread and do not describe $ITEM as held."
  exit 1
fi
# <<< hold-demand-stamp-gate
LC=""
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/lifecycle.sh" ] && { LC="$cand/assets/scripts/lifecycle.sh"; break; }
done
if [ -z "$LC" ]; then echo "NO LIFECYCLE WRITER on any candidate root — this hold records prose and no state"
elif [ "$("$LC" state "$ITEM" 2>/dev/null)" = "unanchored" ]; then
  "$LC" transition "$ITEM" --to held --route human \
    || echo "HELD TRANSITION FAILED on $ITEM — the hold is prose-only; re-run it before you wait"
fi
