#!/usr/bin/env bash
# visit-close.sh — the one guarded close for a converse visit. Every visit-close
# path funnels through here so nothing reaches `bd close` without recording BOTH
# what a reader groups by (gc.outcome, a word) and what a reader reads
# (gc.outcome_reason, a one-line sentence). The board projects gc.outcome as the
# sitting's OUTCOME and gc.outcome_reason as its HEADLINE when the sitting left
# no takeaway, so a moot/benign/folded dedup close reads as a decision rather
# than a dropped need (services/helm/internal/source/facts.go, and
# board.Sitting.Headline in services/helm/internal/board/model.go).
#
# The stamp precedes and gates the close. A metadata write bypasses bd's
# close-authority guard, so it lands even on a visit this actor cannot close
# under, and it is read back first because a --set-metadata pair can exit 0
# having written nothing. Once the visit is closed no re-run reaches it, so a
# dropped stamp is permanent; both stamps must read back or the visit stays open.
#
# Usage:
#   visit-close.sh --visit <id> --outcome <word> --reason <one-line> \
#     [--subject <id>] [--force]
#   --outcome is the one-word class the sitting closed on (moot|benign|folded|
#   dismissed|the word a held sitting signs off with). --reason is the sentence
#   naming why. --subject, when given, also appends the reading to its notes.
#   --force closes over a holder's claim, for an actor closing a visit it does
#   not own (the operator's dismiss).
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

VISIT=""; OUTCOME=""; REASON=""; SUBJECT=""; FORCE=0
die() { echo "visit-close: $1" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --visit)   shift; [ $# -gt 0 ] || die "--visit needs a value"; VISIT="$1" ;;
    --outcome) shift; [ $# -gt 0 ] || die "--outcome needs a value"; OUTCOME="$1" ;;
    --reason)  shift; [ $# -gt 0 ] || die "--reason needs a value"; REASON="$1" ;;
    --subject) shift; [ $# -gt 0 ] || die "--subject needs a value"; SUBJECT="$1" ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown argument '$1'" ;;
  esac
  shift
done

[ -n "$VISIT" ]   || die "--visit is required"
[ -n "$OUTCOME" ] || die "--outcome is required (the one-word class the sitting closed on)"
[ -n "$REASON" ]  || die "--reason is required (the one-line sentence naming why it closed)"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v gc >/dev/null 2>&1 || die "gc is required"

# meta_now <bead> <key> — the live value of one metadata key, or empty.
meta_now() {
  gc bd show "$1" --json 2>/dev/null | scrub \
    | jq -r --arg k "$2" 'if type=="array" then (.[0].metadata[$k] // "") else "" end' 2>/dev/null
}

# The reading also lands on the subject's notes when one is named, the way the
# moot/benign close has always recorded it, so the subject carries the trace too.
if [ -n "$SUBJECT" ]; then
  gc bd update "$SUBJECT" --append-notes "visit $VISIT closed $OUTCOME: $REASON" >/dev/null 2>&1 \
    || echo "visit-close: could not append the reading to $SUBJECT — continuing to the visit stamp" >&2
fi

# Stamp both keys, then read both back, repairing once. A store can exit 0 on a
# --set-metadata that wrote nothing, so the readback is the proof.
gc bd update "$VISIT" --set-metadata "gc.outcome=$OUTCOME" --set-metadata "gc.outcome_reason=$REASON" >/dev/null 2>&1 || true
if [ "$(meta_now "$VISIT" gc.outcome)" != "$OUTCOME" ] || [ "$(meta_now "$VISIT" gc.outcome_reason)" != "$REASON" ]; then
  gc bd update "$VISIT" --set-metadata "gc.outcome=$OUTCOME" --set-metadata "gc.outcome_reason=$REASON" >/dev/null 2>&1 || true
fi
GOT_O=$(meta_now "$VISIT" gc.outcome)
GOT_R=$(meta_now "$VISIT" gc.outcome_reason)
if [ "$GOT_O" != "$OUTCOME" ] || [ "$GOT_R" != "$REASON" ]; then
  echo "visit-close: the outcome stamps did not read back on $VISIT (gc.outcome='$GOT_O', gc.outcome_reason='$GOT_R'); NOT closing — a closed visit with no recorded outcome is a sitting the board cannot report and no re-run can reach. Re-run visit-close." >&2
  exit 3
fi

# Close last, with the reason as the bead's close_reason too (the ledger reads
# that even though the board does not). A holder's own close needs no --force;
# an actor closing a visit it does not own passes --force, plain close first so
# an unclaimed visit never pays for the override.
CLOSE_REASON="$OUTCOME: $REASON"
if [ "$FORCE" -eq 1 ]; then
  gc bd close "$VISIT" --reason "$CLOSE_REASON" >/dev/null 2>&1 \
    || gc bd close "$VISIT" --reason "$CLOSE_REASON" --force >/dev/null 2>&1
else
  gc bd close "$VISIT" --reason "$CLOSE_REASON" >/dev/null 2>&1
fi

# A close that reported success but left the visit open is the strand this helper
# exists to prevent, so the status is read back.
ST=$(gc bd show "$VISIT" --json 2>/dev/null | scrub \
  | jq -r 'if type=="array" then (.[0].status // "") else "" end' 2>/dev/null)
if [ "$ST" != "closed" ]; then
  echo "visit-close: $VISIT carries gc.outcome=$OUTCOME but did not close (status='${ST:-unread}'); close it by hand: gc bd close $VISIT${FORCE:+ --force}" >&2
  exit 4
fi
