#!/usr/bin/env bash
# converse-hold.sh — step 5 of the converse loop: on the way into a hold, stamp
# what the sitting is waiting for and leave the trace a resume needs, BEFORE the
# framing is posted.
#
# A hold IS a demand: the operator owes an answer before the conversation can
# conclude. So this files three things and gates on two of them:
#   1. the board-visible takeaway headline on the item (best-effort);
#   2. the demand bead — the human gate the conversation waits on. A conversation
#      about a PR anchor must NOT freeze the merge by default, so the demand gates
#      the VISIT: the conversation cannot conclude until the operator answers, and
#      the subject anchor keeps moving. Only a pre-PR (unanchored) item takes the
#      demand on itself, because its `held` marker needs that edge to stay a graph
#      state. If the demand does not land there is no hold yet, only a takeaway
#      that nothing re-asks, so the caller must NOT post the framing (exit 1);
#   3. gc.hold_demand on THIS visit, the sole proof step 1's action=hold arm
#      reads to tell a real hold from a claim that died before step 2. The write
#      is read BACK off the visit and the caller must NOT frame unless it landed
#      (exit 1), because the write's own exit status cannot see a value that
#      never persisted.
# Then, where the item is still unanchored, it transitions to `held` so the
# anchor readers drop it while a person owes an answer. To pause the merge of an
# anchored item a sitting passes --hold-merge, the opt-in that files a second
# demand on the anchor — the blocks edge the merge sweep already honors; by
# default it does not.
#
# The item is the visit's stall_root, else the subject; the writers (gc-helm.sh,
# lifecycle.sh) are SEARCHED for on the candidate roots, never assumed, because
# $GC_RIG_ROOT is the rig that imported this agent and may hold no assets/.
#
# Inputs:
#   $1           the one decision or input needed (≤140 chars); the takeaway
#                reads "holding — <this>" and the demand reads "<this>"
#   --hold-merge pause the PR merge too: file a SECOND demand on the anchor
#                ($ITEM), the opt-in merge hold. A no-op on an unanchored item,
#                whose single demand already gates it. Fails closed like the
#                conversation demand — if the merge hold does not land, exit 1.
#   VISIT        the visit bead reaching its hold (environment)
#   SUBJECT      its continuation group, the item fallback (environment)
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

# One positional (the need) plus the optional --hold-merge flag, in any order.
# The need is a sentence, never a flag, so the first non-flag argument is it.
HOLD_MERGE=""
NEED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --hold-merge) HOLD_MERGE=1 ;;
    *)            [ -n "$NEED" ] || NEED="$1" ;;
  esac
  shift
done
NEED="${NEED:-${HOLD_NEED:-}}"
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
# Resolve the lifecycle writer and read $ITEM's state up front: it decides what
# the conversation demand gates. An anchored item (a PR anchor) must not have its
# merge frozen, so the wait gates the VISIT and the anchor keeps moving. A pre-PR
# (unanchored) item takes the demand itself, because its `held` marker needs that
# edge.
LC=""
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/lifecycle.sh" ] && { LC="$cand/assets/scripts/lifecycle.sh"; break; }
done
STATE=""
[ -n "$LC" ] && STATE=$("$LC" state "$ITEM" 2>/dev/null)
# Gate the VISIT only when $ITEM is PROVABLY anchored — a readable PR-anchor state
# (on the merge track, or already merged), where a demand on the item would freeze
# a live merge or land on a closed bead. Every other state gates the ITEM, the
# fail-closed side: unanchored and the pre-PR off-ramps need the demand edge to
# stay blocked. A state that could not be read leaves STATE empty — lifecycle.sh
# prints nothing and exits non-zero on an unreadable or undeclared item, and a
# missing writer never sets it — so an empty STATE gates the ITEM and never
# silently frees a pre-PR hold to keep moving while a person owes an answer.
case "$STATE" in
  pre_open_gate|pull_request|merged) GATED="$VISIT" ;;
  *)                                 GATED="$ITEM" ;;
esac
# The "holding — …" headline is a gc.takeaway hold marker (lifecycle.toml
# [holds]), so it must sit on the SAME bead the demand's blocks edge lands on,
# or doctor/check-wait-is-an-edge reports it UNEDGED. That bead is $GATED: the
# visit for a PR anchor (whose merge keeps moving, so the anchor must read as
# holding nothing), the item otherwise. Stamping the anchor would both strand an
# unedged marker and tell the board the anchor is holding while its merge runs.
"$HELM" takeaway "$GATED" "holding — $NEED" --by converse
# A hold IS a demand: the operator owes an answer before the conversation can
# conclude. File it as a bead and let the edge carry the wait — on the VISIT for
# a proven PR anchor, on $ITEM otherwise (the fail-closed default resolved above).
# >>> hold-demand-gate
# A pipeline answers its LAST command's status, so the demand call stays
# unpiped and its status is read on its own line. That exit is the only
# signal that the bead or the edge did not land, and any filter placed
# downstream of the call answers with its own success instead.
DEMAND_OUT=$("$HELM" demand "$GATED" "$NEED" \
               --by converse)
DEMAND_RC=$?
DEMAND=$(printf '%s\n' "$DEMAND_OUT" | awk '/^demand /{print $2; exit}')
if [ "$DEMAND_RC" -ne 0 ] || [ -z "$DEMAND" ]; then
  echo "NO DEMAND FILED on $GATED (status $DEMAND_RC). Nothing here is a hold yet, only a takeaway that nothing re-asks. Do NOT post the framing."
  echo "The verb printed its reason on stderr, and the repair command when an edge did not land. Repair it, then re-run this block until it names a demand id."
  echo "If it cannot be repaired, that failure is what the operator needs to hear. Raise it in the thread, and do not describe $ITEM as held."
  exit 1
fi
# When the demand gates the VISIT, the visit is itself the sitting that resolves
# it, so record it as the gate's visit now. Without this stamp gate-visit-sweep
# finds no visit covering the visit bead (a visit never covers itself) and files
# a redundant one. Best-effort: the hold is already real.
if [ "$GATED" = "$VISIT" ]; then
  gc bd update "$DEMAND" --set-metadata "gc.gate_visit=$VISIT" \
    || echo "could not stamp gc.gate_visit=$VISIT on $DEMAND — gate-visit-sweep may file a redundant visit; stamp it by hand: gc bd update $DEMAND --set-metadata gc.gate_visit=$VISIT"
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
# >>> hold-merge-opt-in
# --hold-merge pauses the PR merge. The conversation demand above gates the
# VISIT, so by default the anchor keeps moving; this files the SECOND demand, on
# $ITEM (the anchor), the blocks edge merge.sh / pr-facts.sh / pre-open-rebase.sh
# honor via gc.demand_for=<anchor>. The step-7 sign-off discharges it by finding
# the demand on $ITEM, so it needs no other marker. It is meaningful only when
# the conversation gated the visit: on an unanchored item the single demand
# already gates the item, so the flag is a no-op. Same fail-closed discipline as
# the conversation demand — a requested merge hold that did not land must not be
# framed as held.
if [ -n "$HOLD_MERGE" ] && [ "$GATED" = "$VISIT" ]; then
  MERGE_OUT=$("$HELM" demand "$ITEM" "$NEED" --by converse)
  MERGE_RC=$?
  MERGE_DEMAND=$(printf '%s\n' "$MERGE_OUT" | awk '/^demand /{print $2; exit}')
  if [ "$MERGE_RC" -ne 0 ] || [ -z "$MERGE_DEMAND" ]; then
    echo "NO MERGE-HOLD DEMAND FILED on $ITEM (status $MERGE_RC). --hold-merge was asked for, so the conversation wait stands but the MERGE is NOT held."
    echo "The verb printed its reason and repair command on stderr. Repair it, then re-run; or raise it in the thread and do NOT describe the merge as held."
    exit 1
  fi
fi
# <<< hold-merge-opt-in
if [ -z "$LC" ]; then echo "NO LIFECYCLE WRITER on any candidate root — the demand gates the item and keeps it blocked, but no 'held' lifecycle marker is recorded"
elif [ "$STATE" = "unanchored" ]; then
  "$LC" transition "$GATED" --to held --route human \
    || echo "HELD TRANSITION FAILED on $GATED — the hold is prose-only; re-run it before you wait"
fi
