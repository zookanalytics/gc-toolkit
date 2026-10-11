#!/usr/bin/env bash
# first-reaction-guard — the two stand-downs mol-first-reaction's
# advance-and-drain checks before it runs any exit.
#
#   first-reaction-guard.sh --convoy <input-convoy>
#
# REACTION OWNED. A subject raised by `gc-helm engage --new-subject` carries
# gc.reaction_owned=1, set in its create write. That engage created the subject,
# filed its ONE visit and spawned the sitting itself, so a first reaction would
# only put the subject to the operator a second time. The proactive scan drops a
# marked bead and the sling guard refuses it, so a reaction normally never gets
# here for one; this is the backstop for a direct pour. The engage IS the
# reaction: record it with gc.proactive_reaction=1 so no later scan re-reacts,
# then consume the one-shot marker, gated on a read-back-proven stamp so the bead
# can never be left carrying NEITHER marker (the state the next scan reads as
# unreacted and re-visits).
#
# ALREADY REACTED. A completed reaction carries gc.proactive_reaction=1, stamped
# by the release the dispose performs. When a first session disposed and drained
# before closing the step, the graph re-offers the step to a second session on a
# bead whose reaction has landed, and running an exit again would re-release a
# bead a worker may already hold. first-reaction-dispose.sh refuses that
# re-dispose too, but the guard closes the step and drains without trying. A run
# that died before the stamp landed is not a landed reaction: its re-run resumes,
# and `gc-helm.sh demand` refreshes the gate the first run filed rather than
# filing another.
#
# Either stand-down closes the advance-and-drain step and drains, then exits 3,
# so a command that chains an exit after this script stops there.
#
# Called by mol-first-reaction's advance-and-drain step.
# exit: 0 no stand-down applies; run the card's exit · 3 stood down: the step is
#       closed and the session drained · 1 the work bead could not be derived
#       · 2 usage

PROG="first-reaction-guard"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
CONVOY_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --convoy) [ "$#" -ge 2 ] || { echo "$PROG: --convoy requires a value" >&2; exit 2; }; CONVOY_ID="$2"; shift 2 ;;
    *) echo "usage: $PROG --convoy <input-convoy>" >&2; exit 2 ;;
  esac
done
[ -n "$CONVOY_ID" ] || { echo "usage: $PROG --convoy <input-convoy>" >&2; exit 2; }

CONVOY_STATUS=$(gc convoy status "$CONVOY_ID" --json)
WORK_BEAD_ID=$(printf '%s' "$CONVOY_STATUS" | jq -r 'if (.children | length) == 1 then .children[0].id else empty end')
[ -n "$WORK_BEAD_ID" ] || { echo "mol-first-reaction needs an input convoy with exactly one tracked member" >&2; exit 1; }
REACTION_OWNED=$(gc bd show "$WORK_BEAD_ID" --json | scrub | jq -r 'if type=="array" then ((.[0].metadata // {})["gc.reaction_owned"] // "") else "" end' 2>/dev/null || printf '')
if [ "$REACTION_OWNED" = "1" ]; then
  echo "REACTION OWNED: $WORK_BEAD_ID carries gc.reaction_owned=1 — gc-helm engage --new-subject created it, filed its one visit, and spawned the sitting. Running no exit and filing no visit; recording the reaction and draining."
# >>> live-intake-consume
  REACTED=""
  if gc bd update "$WORK_BEAD_ID" --set-metadata "gc.proactive_reaction=1" >/dev/null 2>&1; then
    REACTED=$(gc bd show "$WORK_BEAD_ID" --json | tr -d '[:cntrl:]' | jq -r 'if type=="array" then ((.[0].metadata // {})["gc.proactive_reaction"] // "") else "" end' 2>/dev/null || printf '')
  fi
  if [ "$REACTED" = "1" ]; then
    # Proof is on the bead — consume the one-shot marker, reading it back.
    gc bd update "$WORK_BEAD_ID" --unset-metadata gc.reaction_owned >/dev/null 2>&1 || true
    REACTION_OWNED_LEFT=$(gc bd show "$WORK_BEAD_ID" --json | tr -d '[:cntrl:]' | jq -r 'if type=="array" then ((.[0].metadata // {})["gc.reaction_owned"] // "") else "unknown" end' 2>/dev/null || printf 'unknown')
    [ "$REACTION_OWNED_LEFT" = "1" ] && echo "note: gc.reaction_owned did not clear on $WORK_BEAD_ID (still armed) — left as-is; the scan drop and gc.proactive_reaction both keep a sweep off it" >&2
  else
    # The stamp is not proven on the bead, so DO NOT unset the marker —
    # leaving it armed keeps scan_precision_filter's drop over the bead, so no
    # second visit is filed even without the permanent proof.
    echo "warning: could not confirm gc.proactive_reaction=1 on $WORK_BEAD_ID; left gc.reaction_owned armed so scan_precision_filter's drop still keeps a sweep off it" >&2
  fi
# <<< live-intake-consume
  SC=""; for c in "${GC_PACK_DIR:-}" "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
    [ -x "$c/assets/scripts/step-close.sh" ] && { SC="$c/assets/scripts/step-close.sh"; break; }
  done
  "${SC:?step-close.sh not found in the pack}" --step mol-first-reaction.advance-and-drain --outcome pass
  gc runtime drain-ack
  exit 3
fi

# The guard below is the region its test runs on its own, so it derives the bead
# and resolves step-close.sh itself, and ends its own run with exit 0; the
# command substitution keeps that exit from ending this script.
GUARD_OUT=$(
# >>> advance-and-drain-reacted-guard
CONVOY_STATUS=$(gc convoy status "$CONVOY_ID" --json)
WORK_BEAD_ID=$(printf '%s' "$CONVOY_STATUS" | jq -r 'if (.children | length) == 1 then .children[0].id else empty end')
[ -n "$WORK_BEAD_ID" ] || { echo "mol-first-reaction needs an input convoy with exactly one tracked member" >&2; exit 1; }
# gc.proactive_reaction reads back as the number 1 or the string "1", so it is
# compared as a string.
REACTED=$(gc bd show "$WORK_BEAD_ID" --json | tr -d '[:cntrl:]' | jq -r '(((.[0].metadata // {})["gc.proactive_reaction"] // "") | tostring) == "1"' 2>/dev/null || printf 'false')
if [ "$REACTED" = "true" ]; then
  echo "ALREADY REACTED: $WORK_BEAD_ID carries gc.proactive_reaction=1 — the reaction has landed. Running no exit and filing no visit; closing this step and draining."
  SC=""; for c in "${GC_PACK_DIR:-}" "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
    [ -x "$c/assets/scripts/step-close.sh" ] && { SC="$c/assets/scripts/step-close.sh"; break; }
  done
  "${SC:?step-close.sh not found in the pack; close this step bead by the id the claim returned, never by the inherited one (tk-niu2f)}" --step mol-first-reaction.advance-and-drain --outcome pass
  gc runtime drain-ack
  exit 0
fi
# <<< advance-and-drain-reacted-guard
)
[ -n "$GUARD_OUT" ] && printf '%s\n' "$GUARD_OUT"
case "$GUARD_OUT" in *"ALREADY REACTED:"*) exit 3 ;; esac
exit 0
