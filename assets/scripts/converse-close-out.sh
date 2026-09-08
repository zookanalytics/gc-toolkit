#!/usr/bin/env bash
# converse-close-out.sh — the step-2 silent close, for a visit whose premise
# died before anyone claimed it (moot) or holds but needs no human (benign).
# It appends the reading to the subject's notes, stamps the outcome on the
# visit, and closes the visit. Nothing is posted and no takeaway is stamped:
# a takeaway is the subject's headline of what it NEEDS, and a visit that needs
# nobody spends the attention this exit saves.
#
# Inputs:
#   $1       outcome word: moot | benign
#   $2       the reading: the premise, and what is true instead
#   VISIT    the visit bead being closed (environment)
#   SUBJECT  the subject the note lands on (environment)
set -u

OUTCOME="${1:-}"
DETAIL="${2:-}"
VISIT="${VISIT:-}"
SUBJECT="${SUBJECT:-}"

[ -n "$VISIT" ]   || { echo "converse-close-out: \$VISIT is required" >&2; exit 2; }
[ -n "$SUBJECT" ] || { echo "converse-close-out: \$SUBJECT is required" >&2; exit 2; }
[ -n "$OUTCOME" ] || { echo "converse-close-out: an outcome word (moot|benign) is required (arg 1)" >&2; exit 2; }
[ -n "$DETAIL" ]  || { echo "converse-close-out: a reading (the premise, and what is true instead) is required (arg 2)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "converse-close-out: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "converse-close-out: gc is required" >&2; exit 2; }

gc bd update "$SUBJECT" --append-notes "visit $VISIT closed $OUTCOME: $DETAIL"
gc bd update "$VISIT" --set-metadata "gc.outcome=$OUTCOME"
gc bd show "$VISIT" --json | jq -e '.[0].metadata["gc.outcome"] // empty' >/dev/null
gc bd close "$VISIT"
