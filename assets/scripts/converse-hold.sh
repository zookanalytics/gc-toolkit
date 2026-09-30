#!/usr/bin/env bash
# converse-hold.sh — step 5 of the converse loop: on the way into a hold, stamp
# what the sitting is waiting for and leave the trace a resume needs, BEFORE the
# framing is posted.
#
# The operator owes an answer, and until it lands the sitting's subject must not
# finalize. That hold IS the open visit: the finalize gate
# (assets/scripts/finalize-gate.sh) refuses the subject's merge and close while a
# visit covers it through its non-blocking `tracks` edge, so the hold reaches no
# `blocks` edge and cascades onto no child. This leaves two records and gates on
# one of them:
#   1. the board-visible takeaway headline on the item (best-effort);
#   2. gc.hold_demand on THIS visit, the sole proof step 1's action=hold arm reads
#      to tell a real hold from a claim that died before step 2. The write is read
#      BACK off the visit and the caller must NOT frame unless it landed (exit 1),
#      because the write's own exit status cannot see a value that never persisted.
# Then, where the item is still unanchored, it transitions to `held` so the
# anchor readers drop it while a person owes an answer.
#
# This files NO demand bead and places NO `blocks` edge, on a leaf or a container
# alike: the demand's gating role is the finalize gate's now (tk-p8svsz), and its
# `blocks` edge cascaded down every parent-child leg of a container (tk-g6xcwi).
# gc-helm.sh's demand verb stays for the operator and the triage sweep; a converse
# hold no longer reaches for it.
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
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
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
[ -n "$HELM" ] || echo "NO TAKEAWAY WRITER on any candidate root — the open visit still holds the subject through the finalize gate, but the board carries no headline for it; say so in the thread before you wait"
"$HELM" takeaway "$ITEM" "holding — $NEED" --by converse
# This sitting has reached its hold. Stamp a began-trace on THIS visit before
# waiting: step 1's action=hold arm reads gc.hold_demand off the visit bead to
# tell a real hold from a claim that died before step 2, and the trace is
# attributable only because it lives on the visit rather than on the shared item.
# The value is the instant the hold began — a marker, not a bead id; step 1 tests
# only that it is present.
# >>> hold-demand-stamp-gate
# Step 1 trusts gc.hold_demand as the SOLE proof of a real hold, so this stamp is
# the resume trace and nothing re-derives it. A bare update piped to echo fails
# open two ways. An update can be refused, and an update can report success
# without persisting. Either one leaves the framing posted with no trace, and a
# later scrollback-less restart reads BEGAN=no and closes this engaged sitting at
# step 2 as a dead premise. Read the key back off the visit and refuse to frame
# unless it landed, because the write's own exit status cannot see a value that
# never persisted.
HOLD_MARK="held@$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gc bd update "$VISIT" --set-metadata "gc.hold_demand=$HOLD_MARK" \
  || echo "gc.hold_demand update returned non-zero on $VISIT — verifying by read-back before trusting it"
STAMPED=$(gc bd show "$VISIT" --json | scrub \
  | jq -r '.[0].metadata["gc.hold_demand"] // ""')
if [ "$STAMPED" != "$HOLD_MARK" ]; then
  echo "gc.hold_demand DID NOT PERSIST on $VISIT (found '${STAMPED:-<absent>}', want '$HOLD_MARK'). Without it a restart re-checks the premise and can close this hold as a dead premise. Do NOT post the framing."
  echo "Re-run this block until the read-back names the began-trace. If it cannot be made to persist, that failure is what the operator needs to hear: raise it in the thread and do not describe $ITEM as held."
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
