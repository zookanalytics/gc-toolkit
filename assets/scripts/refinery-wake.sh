#!/usr/bin/env bash
# refinery-wake — re-prompt this rig's refinery when it sits idle at its
# prompt while a handoff waits in its find-work queue.
#
# The refinery cycles its patrol only while a turn runs. A turn can end with
# work still queued: the refinery ended it waiting on a gate in the
# background, or a step left the work with the refinery to retry. The session
# then sits idle at its prompt, and nothing types into it. The runtime defers
# the idle stop while a session holds assigned work, which a refinery with a
# queue always does, and a polecat's handoff nudge reaches it only when new
# work arrives. This pass is the missing wake.
#
# Per pass, for the rig the order runs in, it nudges only when all hold:
#   - the find-work queue (open, assigned to the refinery, carrying
#     metadata.branch, not an epic, no merge_result) holds a bead whose
#     updated_at is older than REFINERY_WAKE_AFTER. Any later write resets
#     updated_at, so the age read is never longer than the real wait;
#   - the refinery's session is active and not attached (a person at the pane
#     is left alone), and the pane has printed nothing for REFINERY_WAKE_IDLE
#     seconds. A working pane redraws its spinner every second, a running tool
#     call included, so a busy refinery is never nudged, and a pane whose last
#     output cannot be read is treated as busy;
#   - this stall, keyed on the oldest queued bead, has had fewer than
#     REFINERY_WAKE_MAX wakes, the last at least REFINERY_WAKE_BACKOFF ago.
# The nudge is the refinery's own nudge text from the resolved config, after a
# sentence saying why. A nudge is the only action: it never kills or restarts a
# session and writes no bead. A stall that outlasts its wakes is the I14 doctor
# check's (check-refinery-patrol-live) to report. The wake fires inside that
# check's bound, so an idle refinery resumes before the check calls it stalled.
#
# env: REFINERY_WAKE_AFTER         seconds a queued bead waits before a wake
#                                  (default 1800)
#      REFINERY_WAKE_IDLE          seconds of pane silence that read as idle
#                                  (default 300)
#      REFINERY_WAKE_BACKOFF       seconds between wakes for one stall
#                                  (default 900)
#      REFINERY_WAKE_MAX           wakes per stall (default 3)
#      REFINERY_WAKE_CALL_TIMEOUT  seconds each gc call may take (default 30)
#      REFINERY_WAKE_STATE_DIR     where the per-rig stall records live
#      REFINERY_WAKE_AGENT         the refinery's qualified name (default:
#                                  discovered from `gc agent list`)
# Output: one line saying what the pass found and did. Actions and failed
# reads are also appended to <state dir>/<rig>.log. Exit 0, or 2 on a usage
# error.
set -uo pipefail

PROG="refinery-wake"

# Rig identity comes from the order runner; guessing would nudge another rig's
# refinery.
RIG="${GC_RIG:-}"
if [ -z "$RIG" ]; then
  echo "$PROG: GC_RIG is unset — this runs as a scope=\"rig\" order and has no rig to watch" >&2
  exit 2
fi

num() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }
setting() { # <value> <default>: a value that is not a whole number takes the default
  if num "$1"; then printf '%s' "$1"; else printf '%s' "$2"; fi
}
WAKE_AFTER=$(setting "${REFINERY_WAKE_AFTER:-}" 1800)
IDLE=$(setting "${REFINERY_WAKE_IDLE:-}" 300)
BACKOFF=$(setting "${REFINERY_WAKE_BACKOFF:-}" 900)
MAX=$(setting "${REFINERY_WAKE_MAX:-}" 3)
CALL_TIMEOUT=$(setting "${REFINERY_WAKE_CALL_TIMEOUT:-}" 30)

RIG_KEY="$(printf '%s' "$RIG" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
case "$RIG_KEY" in '' | . | ..) RIG_KEY=rig ;; esac
STATE_DIR="${REFINERY_WAKE_STATE_DIR:-${GC_PACK_STATE_DIR:-${TMPDIR:-/tmp}/gc}/refinery-wake}"
STATE="$STATE_DIR/$RIG_KEY"
LOG="$STATE_DIR/$RIG_KEY.log"
LOG_KEEP=500
mkdir -p "$STATE_DIR" 2>/dev/null || true

NOW="$(date +%s)"

bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout "$CALL_TIMEOUT" "$@" </dev/null; else "$@" </dev/null; fi
}

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# Say what the pass did. A line worth keeping goes to the log too, trimmed to
# its last LOG_KEEP lines.
say() { echo "${PROG}[$RIG]: $1"; }
record() {
  say "$1"
  { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG"; } 2>/dev/null || return 0
  if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt $((LOG_KEEP * 2)) ]; then
    tail -n "$LOG_KEEP" "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
  fi
}

# RFC3339 at any offset, fractional seconds allowed, to epoch seconds; nothing
# when absent, zero-valued (Go renders an unset time as year 1) or unparseable.
EPOCH_DEF='def epoch:
  try (
    capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:[0-9]{2})$")
    | ((.d + "Z") | fromdateiso8601)
      - (if .z == "Z" then 0
         else ((.z[1:3] | tonumber) * 3600 + (.z[4:6] | tonumber) * 60)
              * (if .z[0:1] == "-" then -1 else 1 end)
         end)
    | floor | select(. > 0)
  ) catch empty;'

resolve_refinery() {
  local found
  found="$(bounded gc agent list --json 2>/dev/null \
    | jq -r --arg rig "$RIG" '.agents[]? | .qualified_name // empty
        | select(startswith($rig + "/")) | select(endswith("refinery"))' 2>/dev/null | head -1)"
  if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
  if [ -n "${GC_PACK_NAME:-}" ]; then printf '%s/%s.refinery' "$RIG" "$GC_PACK_NAME"; return 0; fi
  return 1
}
AGENT="${REFINERY_WAKE_AGENT:-$(resolve_refinery)}"
if [ -z "$AGENT" ]; then
  say "no refinery agent bound for this rig; nothing to wake"
  exit 0
fi

# The find-work queue, filtered as find-work filters it: oldest bead id, its
# wait in seconds, and the queue depth.
QUEUE_RAW=$(bounded gc bd list --rig "$RIG" --assignee "$AGENT" --status open \
  --exclude-type epic --has-metadata-key branch --limit 0 --json 2>/dev/null); RC=$?
QUEUE=$(printf '%s' "$QUEUE_RAW" | scrub | jq -r --argjson now "$NOW" "$EPOCH_DEF"'
  if type != "array" then error("not a list") else . end
  | [.[] | select(type == "object")
      | select(((.metadata.merge_result // "") | tostring) == "")
      | {id: ((.id // "") | tostring), e: ((.updated_at // "") | tostring | epoch)}
      | select(.id != "")] as $q
  | ([$q[] | select(.e != null)] | min_by(.e)) as $o
  | [($q | length), ($o.id // ""), (if $o == null then "" else ([$now - $o.e, 0] | max) end)]
  | map(tostring) | join(" ")' 2>/dev/null)
if [ "$RC" -ne 0 ] || [ -z "$QUEUE" ]; then
  record "could not read the find-work queue of $AGENT (rc=$RC); nothing done this pass"
  exit 0
fi
read -r DEPTH OLDEST WAITED <<< "$QUEUE"
if [ "$DEPTH" = 0 ]; then
  rm -f "$STATE"
  say "find-work queue of $AGENT is empty; nothing to wake"
  exit 0
fi
if ! num "${WAITED:-}"; then
  say "$DEPTH bead(s) queued for $AGENT and none carries a readable updated_at; nothing done"
  exit 0
fi
if [ "$WAITED" -lt "$WAKE_AFTER" ]; then
  say "$OLDEST, the oldest of $DEPTH queued bead(s), has waited $((WAITED / 60))m, inside the $((WAKE_AFTER / 60))m bound"
  exit 0
fi

# The refinery's live session, and how long its pane has been quiet, read
# against the clock when the list arrives: a busy pane's last output is that
# moment, later than this pass's start.
SESS_RAW=$(bounded gc session list --json 2>/dev/null); RC=$?
SESS=$(printf '%s' "$SESS_RAW" | scrub | jq -r --arg a "$AGENT" "$EPOCH_DEF"'
  if (.sessions | type) != "array" then error("no sessions") else . end
  | [.sessions[] | select(type == "object")
      | select(((.agent_name // "") == $a) or ((.alias // "") == $a))
      | select((.state // "") == "active" and (.closed // false) != true)]
  | if length == 0 then "none"
    else .[0] | [(.id // ""), ((.attached // false) | tostring),
                 (((.last_active // "") | tostring | epoch) as $e
                  | if $e == null then "" else ([(now | floor) - $e, 0] | max) end)]
         | map(tostring) | join(" ")
    end' 2>/dev/null)
if [ "$RC" -ne 0 ] || [ -z "$SESS" ]; then
  record "could not read the session list (rc=$RC); $OLDEST has waited $((WAITED / 60))m; nothing done this pass"
  exit 0
fi
if [ "$SESS" = none ]; then
  say "$OLDEST has waited $((WAITED / 60))m and $AGENT has no active session; nothing to nudge"
  exit 0
fi
read -r SID ATTACHED QUIET <<< "$SESS"
if [ -z "$SID" ]; then
  record "the active session of $AGENT carries no id; nothing done this pass"
  exit 0
fi
if [ "$ATTACHED" = true ]; then
  say "$OLDEST has waited $((WAITED / 60))m and a person is attached to $SID; left alone"
  exit 0
fi
if ! num "${QUIET:-}"; then
  say "$OLDEST has waited $((WAITED / 60))m and $SID's last output cannot be read; treated as busy"
  exit 0
fi
if [ "$QUIET" -lt "$IDLE" ]; then
  say "$OLDEST has waited $((WAITED / 60))m and $SID printed ${QUIET}s ago; busy, left alone"
  exit 0
fi

# One stall per oldest bead: a different oldest bead is a new stall.
state_get() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" 2>/dev/null | head -1; }
WAKES=0; LAST=0
if [ "$(state_get bead)" = "$OLDEST" ]; then
  WAKES=$(state_get wakes); num "$WAKES" || WAKES=0
  LAST=$(state_get last); num "$LAST" || LAST=0
fi
if [ "$WAKES" -ge "$MAX" ]; then
  say "gave up on $OLDEST after $WAKES wake(s); it has waited $((WAITED / 60))m, and check-refinery-patrol-live reports the stall"
  exit 0
fi
if [ "$WAKES" -gt 0 ] && [ $((NOW - LAST)) -lt "$BACKOFF" ]; then
  say "backing off: wake $WAKES of $MAX for $OLDEST was $(( (NOW - LAST) / 60 ))m ago"
  exit 0
fi

# The refinery's own nudge, read from the resolved config so an override
# reaches it too.
BASE="${AGENT##*/}"
BASE="${BASE##*.}"
NUDGE=$(bounded gc config show --json 2>/dev/null | scrub | jq -r --arg rig "$RIG" --arg n "$BASE" '
  [.config.Agents[]? | select(((.Dir // "") == $rig) and ((.Name // "") == $n)) | (.Nudge // "")
   | select(. != "")] | .[0] // empty' 2>/dev/null)
[ -n "$NUDGE" ] || NUDGE="Run gc prime, then the startup wisp reconcile; process the merge queue."
MSG="Your merge queue has held $OLDEST for $((WAITED / 60))m while this session sat idle at its prompt. $NUDGE"

write_state() {
  printf 'bead=%s\nwakes=%s\nlast=%s\n' "$OLDEST" "$1" "$NOW" > "$STATE.tmp" 2>/dev/null \
    && mv -f "$STATE.tmp" "$STATE" 2>/dev/null
}
NUDGE_RC=0
bounded gc session nudge --delivery immediate "$SID" "$MSG" >/dev/null 2>&1 || NUDGE_RC=$?
if [ "$NUDGE_RC" -eq 0 ]; then
  write_state $((WAKES + 1))
  record "nudged $SID (wake $((WAKES + 1)) of $MAX): $OLDEST has waited $((WAITED / 60))m while the pane sat quiet for $((QUIET / 60))m"
elif [ "$NUDGE_RC" -eq 124 ] || [ "$NUDGE_RC" -ge 128 ]; then
  # The nudge may have landed before the cut-off; count it, so a retry cannot
  # type the wake twice.
  write_state $((WAKES + 1))
  record "nudge to $SID UNCONFIRMED (rc=$NUDGE_RC), counted as wake $((WAKES + 1)) of $MAX for $OLDEST"
else
  record "nudge to $SID FAILED (rc=$NUDGE_RC) for $OLDEST; the next pass retries"
fi
exit 0
