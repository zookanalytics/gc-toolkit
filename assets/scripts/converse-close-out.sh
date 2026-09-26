#!/usr/bin/env bash
# converse-close-out.sh — the step-2 silent close, for a visit whose premise
# died before anyone claimed it (moot) or holds but needs no human (benign). It
# records the reading as the visit's board-visible outcome reason and closes the
# visit through the shared guarded close (visit-close.sh); nothing is posted and
# no takeaway is stamped, because a takeaway is the subject's headline of what it
# NEEDS, and a visit that needs nobody spends the attention this exit saves.
#
# Inputs:
#   $1       outcome word: moot | benign
#   $2       the reading: the premise, and what is true instead
#   VISIT    the visit bead being closed (environment)
#   SUBJECT  the subject the reading also lands on (environment)
set -u

OUTCOME="${1:-}"
DETAIL="${2:-}"
VISIT="${VISIT:-}"
SUBJECT="${SUBJECT:-}"

[ -n "$VISIT" ]   || { echo "converse-close-out: \$VISIT is required" >&2; exit 2; }
[ -n "$SUBJECT" ] || { echo "converse-close-out: \$SUBJECT is required" >&2; exit 2; }
[ -n "$OUTCOME" ] || { echo "converse-close-out: an outcome word (moot|benign) is required (arg 1)" >&2; exit 2; }
[ -n "$DETAIL" ]  || { echo "converse-close-out: a reading (the premise, and what is true instead) is required (arg 2)" >&2; exit 2; }

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SELF_DIR/visit-close.sh" \
  --visit "$VISIT" --subject "$SUBJECT" --outcome "$OUTCOME" --reason "$DETAIL"
