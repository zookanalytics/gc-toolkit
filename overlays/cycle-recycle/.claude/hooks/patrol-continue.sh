#!/bin/sh
# patrol-continue.sh — the Stop hook of the deacon and the witness. A turn that
# ends between patrol cycles is handed back with the next cycle, so the patrol
# never idles.
#
# Each patrol is a loop of wisps, one cycle each: mol-deacon-patrol for the
# deacon and mol-witness-patrol for the witness. The loop lives in the
# conversation: next-iteration pours the next wisp and the session goes on to
# it. The model ends its turn after a cycle anyway, and nothing gives an ended
# turn another one: both are named sessions in mode "always", which no idle
# timeout stops, and the configured nudge is delivered once per session. So at
# every turn boundary this hook blocks the stop and hands the next cycle back
# (docs/patrol-continue.md).
#
# It lets the turn end, printing nothing, when:
#   * the agent is neither the deacon nor the witness. The refinery shares this
#     overlay, and it ends its turn when it runs out of work.
#   * a background task is still running. Its completion notification starts
#     the next turn, and a hand-back now would race the wait the task serves.
#   * the payload carries no session id or no readable task list.
#   * the session has stopped MAX_RAPID times in a row within MIN_TURN seconds
#     of a hand-back. A real cycle spends the formula's event_timeout (600s) in
#     its inter-cycle wait, so none of those turns ran a full cycle, and another
#     hand-back would only loop. The hook resets the session instead: the fresh
#     conversation starts from the role's prompt, whose startup reconcile
#     adopts the wisp the patrol left. While an operator is attached to the
#     pane the reset waits, because it would end the conversation under them.
#     The deacon's reset also goes ahead only once the hook has written its
#     recovery line to the incident ledger. A reset that fails or outlasts
#     RESET_BOUND hands the turn back after all, because no other turn is
#     coming.
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
RESET_BOUND=90  # seconds: inside the 120s the overlay's settings give this hook

# reset_session <target> — gc session reset, bounded where timeout exists. The
# harness ends the turn when it kills this hook, so a reset that hangs has to
# give up first.
reset_session() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$RESET_BOUND" gc session reset "$1" >&2
  else
    gc session reset "$1" >&2
  fi
}

# --- 1. Self-gate: the deacon and the witness --------------------------------
AGENT="${GC_AGENT:-}"
base="${AGENT##*/}"  # "gc-toolkit/gc-toolkit.witness" -> "gc-toolkit.witness"
role="${base##*.}"   # "gc-toolkit.deacon" -> "deacon"
case "$role" in
  deacon | witness) ;;
  *) exit 0 ;;
esac

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
prev_sid=""; prev_at=0; rapid=0; reset_failed=""
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
  WHY="$rapid turns in a row ended within ${MIN_TURN}s of a hand-back without a full patrol cycle"
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
  # The deacon's reset also waits for its recovery line in the incident
  # ledger, which the deacon's fresh conversation reads in place of the
  # transcript the reset ends. The line goes first because the reset can end
  # this process with the session. When the ledger script is missing or the
  # append fails, the turn ends with the count kept, as it does under an
  # attached operator, so the next rapid stop tries the line again. The
  # witness's prompt reads no ledger, so its reset writes no line.
  if [ "$role" = deacon ]; then
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
  fi
  printf '%s 0 0\n' "$SID" > "$STATE" 2>/dev/null || true
  echo "patrol-continue: $WHY; resetting the session" >&2
  RESET_TARGET="${GC_ALIAS:-${GC_SESSION_ID:-}}"
  if [ -z "$RESET_TARGET" ]; then
    echo "patrol-continue: neither GC_ALIAS nor GC_SESSION_ID names this session, so there is nothing to reset; handing the turn back" >&2
  elif reset_session "$RESET_TARGET"; then
    exit 0
  else
    echo "patrol-continue: gc session reset $RESET_TARGET failed or outlasted ${RESET_BOUND}s; handing the turn back" >&2
  fi
  # The reset needs the bead store and the controller, so an outage takes it
  # away while the patrol's cycles are failing fast. A turn that ended here would
  # get no other, so it goes back, and the next run of rapid stops tries again.
  reset_failed=1
  rapid=0
fi

printf '%s %s %s\n' "$SID" "$now" "$rapid" > "$STATE" 2>/dev/null \
  || echo "patrol-continue: could not write $STATE, so this hand-back is not counted" >&2

# The hand-back names the inter-cycle wait because a session that skipped it
# would otherwise go straight on to the next cycle, and the patrol would run at
# the model's pace instead of the formula's.
REASON="Patrol continues: a $role turn does not end between cycles, so this one is handed back. If next-iteration has poured your next wisp, finish its inter-cycle wait if you skipped it, then run the startup wisp reconcile from your prompt to adopt the wisp and work mol-$role-patrol from check-inbox. Otherwise finish the current cycle through next-iteration."
if [ "$rapid" -gt 0 ]; then
  REASON="$REASON The last hand-back ended within ${MIN_TURN}s, too soon for a cycle and its inter-cycle wait; run whichever of them has not run."
fi
if [ -n "$reset_failed" ]; then
  REASON="$REASON This hook could not reset the session, so the bead store or the controller may be down. If your bead commands are failing, run the inter-cycle wait before you retry the cycle."
fi
jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
