#!/usr/bin/env bash
# record-failure-cap.sh — bound the merged-record retry on one anchor.
#   record-failure-cap.sh <anchor-id> <pr-number> <merged-sha> <landing-branch>
#
# Landing a PR and recording it are two writes. When the second one fails, the
# anchor keeps merge_result=pull_request over a PR that is already on the target
# branch: it reads as a live gating anchor, the board shows it as one, and the
# merge cadence retries the record every pass. The retry is right for the common
# cause, a store that was busy for a tick. It is useless for a cause the next
# pass meets unchanged — a close bd refuses, an --expect the anchor no longer
# satisfies, a read-back that never agrees — and neither record arm carries any
# memory of the last pass, so an unclearable cause reprints one stderr line
# forever and reaches nobody.
#
# This is the memory. It counts consecutive failures on the anchor itself and
# hands the anchor to a person once the count reaches the cap. Both writers of
# the same repair call it — merge.sh's two record arms and pr-facts.sh's
# out-of-band record — so their attempts count against one budget rather than
# each keeping a private tally of a repair the other one also tried.
#
# The count is metadata-only on purpose. Every refusal being bounded here is a
# refusal of the transition's own write: the ownership check on its --status
# half, the --expect re-read, the post-write verification. None of those
# constrain a bare --set-metadata on the same bead, so the counter still lands
# in exactly the cases the cap exists for. A store that refuses this too fails
# the whole pass through its caller's record_failed count, which is the loud
# channel this one is not trying to duplicate.
#
# Callers: assets/scripts/merge.sh, assets/scripts/pr-facts.sh.
# Exit: always 0. A cap that cannot count must not be what fails a pass — the
# record failure it is counting has already been reported by the caller.
set -u

PROG="record-failure-cap"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ESCALATE="$SCRIPTS_DIR/escalate.sh"

# Consecutive failed records on one anchor before the retry stops being the
# whole answer.
MAX_RECORD_FAILURES="${GC_MAX_RECORD_FAILURES:-3}"
case "$MAX_RECORD_FAILURES" in ''|*[!0-9]*) MAX_RECORD_FAILURES=3 ;; esac

ID="${1:-}"; NUM="${2:-}"; SHA="${3:-}"; TARGET="${4:-}"
if [ -z "$ID" ]; then
  echo "$PROG: needs an anchor id" >&2
  exit 0
fi

PRIOR=$(gc bd show "$ID" --json 2>/dev/null | scrub \
  | jq -r '(.[0].metadata.merge_record_failures // "0") | tostring' 2>/dev/null)
case "$PRIOR" in ''|*[!0-9]*) PRIOR=0 ;; esac
N=$((PRIOR + 1))

gc bd update "$ID" --set-metadata "merge_record_failures=$N" >/dev/null 2>&1 \
  || echo "$PROG: WARN could not count the record failure on $ID; the cap cannot arm from this pass" >&2

[ "$N" -ge "$MAX_RECORD_FAILURES" ] || exit 0
echo "$PROG: $ID has now failed to record merged PR#$NUM $N times (cap $MAX_RECORD_FAILURES); escalating" >&2
[ -x "$ESCALATE" ] || exit 0

# One open visit per anchor and PR, however many passes the condition holds:
# escalate.sh dedups on the key and narrows that to the subject when the subject
# is durable, which an anchor is. The call is unconditional past the cap rather
# than fired once on the crossing, so a visit closed without repairing the
# anchor is re-filed on the next failure and one still open is left alone.
# First line is the visit headline.
"$ESCALATE" --subject "$ID" --key "merge-record-failed.$NUM" \
  --message "PR#$NUM landed on $TARGET at $SHA and anchor $ID still records merge_result=pull_request after $N failed records.

Landing and recording are two writes. The landing happened; the record has been
refused $N times with nothing landing in between, so the retry is not converging
on its own and no later pass will converge either. Until the record lands the
anchor reads as a live gating anchor over a merged PR: the board shows it
waiting, and every pass reprints the same line.

The refusal names what has to change. Perform the record by hand and read it:

  assets/scripts/lifecycle.sh transition $ID --to merged --expect pull_request --close --set merged_sha=$SHA --append-notes 'Merged to $TARGET at $SHA (recorded by hand)'

Clearing merge_record_failures on $ID re-arms this escalation." >/dev/null 2>&1 || true
exit 0
