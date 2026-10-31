#!/usr/bin/env bash
# witness-nudge — give a witness whose pane has gone quiet its next patrol turn.
#
# A witness's patrol loop lives in its conversation. When a turn ends, whether
# after a pass or partway through a cycle, the session sits at its prompt until
# something types into it. So each pass of the witness-nudge order reads the
# session list once and nudges every active witness with nobody attached whose
# pane has printed nothing, and which has had no nudge, for QUIET_SECS.
#
# A working pane animates a spinner, so it never reads as quiet, and a witness
# in its inter-cycle wait is left alone. A nudge is the only action. Nothing here
# resets a session, reads a bead or keeps state: the delivered nudge's own
# timestamp paces the next one.
#
# Exit 0 when the pass read every witness and every nudge it sent was accepted.
# Exit 1 when the session list or a row's time is unreadable, or a nudge failed.
# See docs/patrol-continue.md.
set -uo pipefail

# Longer than the inter-cycle wait mol-witness-patrol's next-iteration runs, so
# a witness that moved that wait to the background is not nudged out of it.
QUIET_SECS="${WITNESS_NUDGE_QUIET_SECS:-660}"
case "$QUIET_SECS" in
  '' | *[!0-9]* | 0)
    echo "witness-nudge: WITNESS_NUDGE_QUIET_SECS must be a positive number of seconds, got '$QUIET_SECS'" >&2
    exit 1 ;;
esac

if ! LIST=$(GC_NO_API=1 gc session list --json); then
  echo "witness-nudge: gc session list failed; nothing was nudged" >&2
  exit 1
fi

# One row per live witness with nobody attached. @tsv keeps a field from forging
# a row, and "-" keeps a field from being empty, because read folds adjacent tabs.
# -s makes an empty list an error: jq runs a plain filter zero times on empty input
# and exits 0, which would read as no witnesses. With -s, .sessions[] fails on
# anything that is not a list of sessions.
if ! ROWS=$(printf '%s' "$LIST" | jq -r -s '
  # RFC3339 at any offset to epoch seconds, or nothing when absent, unparseable
  # or zero-valued (Go renders an unset time as year 1).
  def epoch:
    try (
      capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:[0-9]{2})$")
      | ((.d + "Z") | fromdateiso8601)
        - (if .z == "Z" then 0
           else ((.z[1:3] | tonumber) * 3600 + (.z[4:6] | tonumber) * 60)
                * (if .z[0:1] == "-" then -1 else 1 end)
           end)
      | floor | select(. > 0)
    ) catch empty;
  .[0].sessions[]
  | select(.state == "active" and (.attached // false) == false)
  | select((.template // "") | test("(^|[/.])witness$"))
  | select((.id // "") | test("^[A-Za-z0-9]"))
  | [.id, ((.alias // "") | if . == "" then "-" else . end),
     ((.last_active | epoch) // "-"), ((.last_nudge_delivered_at | epoch) // "-")]
  | @tsv'); then
  echo "witness-nudge: gc session list printed no readable session list; nothing was nudged" >&2
  exit 1
fi

NOW=$(date +%s)
checked=0; nudged=0; rc=0
while IFS=$'\t' read -r id alias last_active last_nudge; do
  [ -n "$id" ] || continue
  checked=$((checked + 1))
  if [ "$last_active" = - ]; then
    echo "witness-nudge: $alias ($id) has no readable last_active; not nudged" >&2
    rc=1
    continue
  fi
  last="$last_active"
  if [ "$last_nudge" != - ] && [ "$last_nudge" -gt "$last" ]; then
    last="$last_nudge"
  fi
  quiet=$((NOW - last))
  [ "$quiet" -ge "$QUIET_SECS" ] || continue
  MSG="Your pane has been quiet for $((quiet / 60)) minutes, so no patrol cycle is running. Run the startup wisp reconcile from your prompt to adopt your patrol wisp, then work mol-witness-patrol from check-inbox."
  # --delivery immediate: the default wait-idle delivers live only to a provider
  # named exactly claude, and a patrol can run on a variant of it.
  if gc session nudge --delivery immediate "$id" "$MSG" >/dev/null </dev/null; then
    nudged=$((nudged + 1))
    echo "witness-nudge: nudged $alias ($id), quiet for ${quiet}s"
  else
    echo "witness-nudge: nudge of $alias ($id) failed" >&2
    rc=1
  fi
done <<< "$ROWS"

echo "witness-nudge: $checked checked, $nudged nudged"
exit "$rc"
