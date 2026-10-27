#!/bin/sh
# patrol-continue.sh — the deacon's Stop hook. A turn that ends between patrol
# cycles is handed back with the next cycle, so the patrol never idles.
#
# The deacon's patrol is a loop of mol-deacon-patrol wisps, one cycle each, and
# the loop lives in the conversation: next-iteration pours the next wisp and
# the session goes on to it. The model ends its turn after a cycle anyway, and
# nothing gives an ended turn another one: the deacon is a named session in
# mode "always", which no idle timeout stops, and its configured nudge is
# delivered once per session. So at every turn boundary this hook blocks the
# stop and hands the next cycle back (docs/patrol-continue.md).
#
# It lets the turn end, printing nothing, when:
#   * the agent is not the deacon. The witness and the refinery share this
#     overlay, and the refinery ends its turn when it runs out of work.
#   * a background task is still running. Its completion notification starts
#     the next turn, and a hand-back now would race the wait the task serves.
#   * the payload carries no session id or no readable task list.
#   * the deacon has stopped MAX_RAPID times in a row within MIN_TURN seconds of
#     a hand-back. A real cycle spends the formula's event_timeout (600s) in
#     its inter-cycle wait, so those turns ran no cycle, and another hand-back
#     would only loop. The hook resets the session instead: the fresh
#     conversation starts from the deacon's prompt, whose startup reconcile
#     adopts the wisp the patrol left. While an operator is attached to the
#     pane the reset waits, because it would end the conversation under them.
#     It also goes ahead only once the hook has written its recovery line to
#     the incident ledger.
#
# Invariants:
#   * ALWAYS exit 0. A block rides the JSON decision on stdout, never the exit
#     code, so a hook that fails lets the turn end instead of wedging it.
#   * stdout carries the block decision and nothing else. Diagnostics go to
#     stderr.
#   * NEVER prompt the operator (heartbeat-no-consent-ui).
#   * A hand-back reads no store: the payload and one state file per session
#     decide it.

set -u
export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"

MIN_TURN=300  # seconds: half the 600s inter-cycle wait every real cycle spends
MAX_RAPID=3   # consecutive stops within MIN_TURN of a hand-back before the reset

# --- 1. Self-gate: the deacon only -------------------------------------------
AGENT="${GC_AGENT:-}"
base="${AGENT##*/}"  # "gc-toolkit/gc-toolkit.witness" -> "gc-toolkit.witness"
role="${base##*.}"   # "gc-toolkit.deacon" -> "deacon"
[ "$role" = deacon ] || exit 0

# --- 2. Read the turn from the hook payload ----------------------------------
[ -t 0 ] && exit 0  # no payload (invoked by hand)
if ! command -v jq >/dev/null 2>&1; then
  echo "patrol-continue: jq is not on PATH; letting the turn end" >&2
  exit 0
fi
PAYLOAD=$(cat 2>/dev/null)
SID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null)
# An absent task list (a client that sends none) reads as no task running; a
# list that is not an array is unreadable.
RUNNING=$(printf '%s' "$PAYLOAD" | jq -r 'if ((.background_tasks // []) | type) == "array" then [(.background_tasks // [])[] | select((.status // "") == "running")] | length else "unreadable" end' 2>/dev/null)
case "$SID" in
  '' | *[!A-Za-z0-9-]*)
    echo "patrol-continue: the payload names no session id; letting the turn end" >&2
    exit 0 ;;
esac
case "$RUNNING" in
  '' | *[!0-9]*)
    echo "patrol-continue: the payload's background task list is unreadable; letting the turn end" >&2
    exit 0 ;;
esac

# --- 3. A running background task resumes the session itself -----------------
[ "$RUNNING" -eq 0 ] || exit 0

# --- 4. Loop guard: count stops that came too soon after a hand-back ---------
# One file per session bead, holding the conversation it counts for, the time
# of the last hand-back and the rapid stops since. A new conversation starts
# the count over.
STATE="${TMPDIR:-/tmp}/gc-patrol-continue.${GC_SESSION_ID:-$SID}"
now=$(date +%s)
prev_sid=""; prev_at=0; rapid=0
if [ -r "$STATE" ]; then
  read -r prev_sid prev_at rapid < "$STATE" || true
fi
case "$prev_at" in '' | *[!0-9]*) prev_at=0 ;; esac
case "$rapid" in '' | *[!0-9]*) rapid=0 ;; esac
[ "$prev_sid" = "$SID" ] || { prev_at=0; rapid=0; }
if [ "$prev_at" -gt 0 ] && [ $((now - prev_at)) -lt "$MIN_TURN" ]; then
  rapid=$((rapid + 1))
else
  rapid=0
fi

if [ "$rapid" -ge "$MAX_RAPID" ]; then
  WHY="$rapid turns in a row ended within ${MIN_TURN}s of a hand-back without a patrol cycle"
  # A reset ends the conversation, so it waits while an operator is attached to
  # watch or work the pane, and an attachment it cannot read counts as one, as
  # in cycle-recycle.sh. The turn ends and the state file keeps its count, so
  # the next rapid stop with nobody attached takes the reset.
  if [ -n "${TMUX:-}" ]; then
    attached=$(tmux display-message -p '#{session_attached}' 2>/dev/null || true)
    case "$attached" in
      0) : ;;
      '' | *[!0-9]*)
        echo "patrol-continue: $WHY; the attachment state is unknown, so the reset waits and the turn ends" >&2
        exit 0 ;;
      *)
        echo "patrol-continue: $WHY; $attached client(s) attached, so the reset waits and the turn ends" >&2
        exit 0 ;;
    esac
  fi
  # The reset also waits for its recovery line in the incident ledger, which
  # the fresh conversation reads in place of the transcript the reset ends. The
  # line goes first because the reset can end this process with the session.
  # When the ledger script is missing or the append fails, the turn ends with
  # the count kept, as it does under an attached operator, so the next rapid
  # stop tries the line again.
  LEDGER=""
  for C in "${GC_RIG_ROOT:-}" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
    [ -x "$C/assets/scripts/gc-deacon-ledger.sh" ] && { LEDGER="$C/assets/scripts/gc-deacon-ledger.sh"; break; }
  done
  if [ -z "$LEDGER" ]; then
    echo "patrol-continue: $WHY; gc-deacon-ledger.sh not found, so the reset waits for its recovery line and the turn ends" >&2
    exit 0
  fi
  if ! "$LEDGER" append recovery "patrol-continue reset the session: $WHY (${GC_SESSION_NAME:-$SID})" - >&2; then
    echo "patrol-continue: $WHY; the recovery line did not reach the ledger, so the reset waits and the turn ends" >&2
    exit 0
  fi
  printf '%s 0 0\n' "$SID" > "$STATE" 2>/dev/null || true
  echo "patrol-continue: $WHY; resetting the session" >&2
  RESET_TARGET="${GC_ALIAS:-${GC_SESSION_ID:-}}"
  if [ -z "$RESET_TARGET" ]; then
    echo "patrol-continue: neither GC_ALIAS nor GC_SESSION_ID names this session; nothing to reset" >&2
  elif ! gc session reset "$RESET_TARGET" >&2; then
    echo "patrol-continue: gc session reset $RESET_TARGET failed; the turn ends" >&2
  fi
  exit 0
fi

printf '%s %s %s\n' "$SID" "$now" "$rapid" > "$STATE" 2>/dev/null \
  || echo "patrol-continue: could not write $STATE, so this hand-back is not counted" >&2

REASON="Patrol continues: a deacon turn does not end between cycles, so this one is handed back. If next-iteration has poured your next wisp, run the startup wisp reconcile from your prompt to adopt it, then work mol-deacon-patrol from check-inbox. Otherwise finish the current cycle through next-iteration."
if [ "$rapid" -gt 0 ]; then
  REASON="$REASON The last hand-back ended within ${MIN_TURN}s with no cycle run; run the cycle's steps now."
fi
jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
