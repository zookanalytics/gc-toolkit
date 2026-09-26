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
_close_rc=$?

# If this visit ever engaged, it left an "open" reminder on the subject's PR;
# once the close above lands, update it to say the visit closed. update-only, so
# a visit that never engaged (the common moot case) touches nothing. This is a
# different surface from the thread the header says stays silent, and it is
# best-effort — a failure here must not disturb a close that landed, and it must
# not mask the close's own exit code.
if [ "$_close_rc" -eq 0 ]; then
  PVC=""
  for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
    [ -x "$cand/assets/scripts/pr-visit-comment.sh" ] && { PVC="$cand/assets/scripts/pr-visit-comment.sh"; break; }
  done
  [ -n "$PVC" ] && "$PVC" close --visit "$VISIT" --subject "$SUBJECT" --outcome "$OUTCOME" --summary "$DETAIL" || true
fi
exit "$_close_rc"
