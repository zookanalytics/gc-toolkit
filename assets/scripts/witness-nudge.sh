#!/usr/bin/env bash
# witness-nudge — give a witness whose patrol pass stopped its next turn.
#
# A pass ends at mol-witness-patrol's next-iteration, which leaves the next wisp
# assigned and deferred an hour and ends the turn, so a witness between passes
# sits idle by design until the controller's reassignment restart runs the next
# one. A session that ends its turn short of that step still holds its patrol
# wisp in progress, and the controller gives no restart to a session holding
# in-progress work, so it sits at its prompt until something types into it. So
# each pass of the witness-nudge order reads the session list once and nudges
# every active witness with nobody attached whose pane has printed nothing, and
# which has had no nudge, for QUIET_SECS, and which holds a mol-witness-patrol
# wisp in progress. A witness that holds none is waiting out its next pass, and
# it is left alone.
#
# A working pane animates a spinner, so it never reads as quiet. A nudge is the
# only action. Nothing here resets a session or keeps state: the delivered
# nudge's own timestamp paces the next one. The rig map and a witness's wisps
# are read only for a witness already past the quiet bound.
#
# Exit 0 when the pass read every witness it had to and every nudge it sent was
# accepted. Exit 1 when the session list, a row's time or rig, the rig map or a
# witness's wisps are unreadable, or a nudge failed.
# See docs/patrol-continue.md.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A working pass animates its pane, so the bound sets only how soon a stopped
# pass is caught: at the order's 5m interval, 11 to 16 minutes after its pane
# went quiet.
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
     ((.rig // "") | if . == "" then "-" else . end),
     ((.last_active | epoch) // "-"), ((.last_nudge_delivered_at | epoch) // "-")]
  | @tsv'); then
  echo "witness-nudge: gc session list printed no readable session list; nothing was nudged" >&2
  exit 1
fi

# The rig map names the store each witness's patrol wisps live in. It is read
# once, and only when a witness is past the bound.
MAP=""; MAP_READ=0

NOW=$(date +%s)
checked=0; nudged=0; rc=0
while IFS=$'\t' read -r id alias rig last_active last_nudge; do
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
  # Only a witness holding its patrol wisp in progress has a pass that stopped.
  if [ "$alias" = - ] || [ "$rig" = - ]; then
    echo "witness-nudge: $id names no alias or rig, so its patrol wisps cannot be read; not nudged" >&2
    rc=1
    continue
  fi
  if [ "$MAP_READ" = 0 ]; then
    MAP_READ=1
    MAP=$("$HERE/rig-map.sh") || MAP=""
  fi
  if [ -z "$MAP" ]; then
    echo "witness-nudge: $alias ($id): the rig map did not read, so its patrol wisps cannot be; not nudged" >&2
    rc=1
    continue
  fi
  RIG_PATH=$(printf '%s' "$MAP" | jq -r --arg n "$rig" '[.rigs[]? | select(.name == $n) | .path // empty][0] // empty' 2>/dev/null)
  if [ -z "$RIG_PATH" ]; then
    echo "witness-nudge: $alias ($id): rig '$rig' is not in the rig map; not nudged" >&2
    rc=1
    continue
  fi
  STORE="$RIG_PATH/.beads"
  if ! HELD=$(gc bd --db "$STORE" list --status=in_progress --assignee="$alias" --type=molecule --include-infra --limit=0 --json </dev/null 2>/dev/null \
      | sed -n '/^[[{]/,$p' | jq -e 'if type == "array" then [.[] | select(.title == "mol-witness-patrol")] | length else error("not a list") end' 2>/dev/null); then
    echo "witness-nudge: $alias ($id): its patrol wisps did not read from $STORE; not nudged" >&2
    rc=1
    continue
  fi
  if [ "$HELD" = 0 ]; then
    echo "witness-nudge: $alias ($id) holds no patrol wisp in progress, so it is waiting out its next pass; not nudged"
    continue
  fi
  MSG="Your pane has been quiet for $((quiet / 60)) minutes with your patrol wisp still in progress, so your pass stopped. Run the startup wisp reconcile from your prompt to adopt your patrol wisp, then work mol-witness-patrol from check-inbox."
  # --delivery immediate: the default wait-idle queues what it cannot deliver now,
  # a queued nudge stamps no delivery, and each later pass would stack another.
  if gc session nudge --delivery immediate "$id" "$MSG" >/dev/null </dev/null; then
    nudged=$((nudged + 1))
    echo "witness-nudge: nudged $alias ($id), quiet for ${quiet}s with its pass in progress"
  else
    echo "witness-nudge: nudge of $alias ($id) failed" >&2
    rc=1
  fi
done <<< "$ROWS"

echo "witness-nudge: $checked checked, $nudged nudged"
exit "$rc"
