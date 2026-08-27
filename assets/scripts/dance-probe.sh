#!/usr/bin/env bash
# dance-probe.sh — one interrogation round of the shutdown dance; mechanical
# half only, the formula judges. Reads the quota-park --status surface FIRST
# (a parked session is never interrogated), then nudges the target with a
# challenge and polls its pane for movement/busy markers inside the round's
# bound (60/120/240s). Prints closed-field evidence lines and ONE final
# machine-readable line: verdict=alive|silent|parked|missing. Not one byte of
# pane text is emitted — panes are agent-controlled output.
#   dance-probe.sh --session <name> --round 1|2|3
# Env: DANCE_PROBE_WAIT_1/2/3 round bounds (60/120/240); DANCE_PROBE_POLL
# poll interval (10); DANCE_PROBE_PEEK_LINES (30); DANCE_PROBE_CALL_TIMEOUT
# per-gc-call bound (15); DANCE_PROBE_QPN quota-park status tool (default:
# sibling quota-park-nudge.sh).
# Callers: packs/gc-toolkit-city/formulas/mol-dog-shutdown-dance.toml;
# dance-probe.test.sh.
# Exit: 0 verdict printed (every verdict) · 2 usage error only.
set -u

usage() {
  cat >&2 <<'U'
usage: dance-probe.sh --session <name> --round 1|2|3
  --session  target session id/alias: [A-Za-z0-9._-], no leading . or -
  --round    interrogation round; selects the wait bound (60/120/240s)
U
}

SESSION=""; ROUND=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session) SESSION="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --round)   ROUND="${2:-}";   shift 2 || { usage; exit 2; } ;;
    -h|--help) usage; exit 2 ;;
    *) echo "dance-probe: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
# An id unsafe as a filename or argument is refused, never passed to gc.
case "$SESSION" in
  ''|*[!A-Za-z0-9._-]*|.*|-*|*..*) echo "dance-probe: --session must be a safe session id (got '${SESSION:-<empty>}')" >&2; exit 2 ;;
esac
case "$ROUND" in 1|2|3) : ;; *) echo "dance-probe: --round must be 1, 2 or 3 (got '${ROUND:-<empty>}')" >&2; exit 2 ;; esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QPN="${DANCE_PROBE_QPN:-$HERE/quota-park-nudge.sh}"
PEEK_LINES="${DANCE_PROBE_PEEK_LINES:-30}"
POLL="${DANCE_PROBE_POLL:-10}"
CALL_TIMEOUT="${DANCE_PROBE_CALL_TIMEOUT:-15}"
case "$ROUND" in
  1) WAIT="${DANCE_PROBE_WAIT_1:-60}" ;;
  2) WAIT="${DANCE_PROBE_WAIT_2:-120}" ;;
  3) WAIT="${DANCE_PROBE_WAIT_3:-240}" ;;
esac
# A garbage numeric override falls back to its default rather than breaking a
# bound arithmetic mid-round.
num() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac }
num "$WAIT" || { case "$ROUND" in 1) WAIT=60 ;; 2) WAIT=120 ;; 3) WAIT=240 ;; esac; }
num "$POLL" || POLL=10
[ "$POLL" -ge 1 ] || POLL=1
num "$PEEK_LINES" || PEEK_LINES=30
num "$CALL_TIMEOUT" || CALL_TIMEOUT=15

# Busy markers: both CLIs print these while mid-turn — mid-turn is alive.
BUSY_RE="${DANCE_PROBE_BUSY:-esc to interrupt|ctrl.{0,2}c to (stop|interrupt)}"

run_bounded() {
  if [ "$CALL_TIMEOUT" -gt 0 ] && command -v timeout >/dev/null 2>&1; then
    timeout "$CALL_TIMEOUT" "$@" </dev/null
  else
    "$@" </dev/null
  fi
}

WAITED=0
evidence() { printf 'evidence: %s\n' "$*"; }
verdict()  { printf 'verdict=%s round=%s session=%s waited=%s\n' "$1" "$ROUND" "$SESSION" "$WAITED"; exit 0; }

# 1. Parked short-circuit — ask the recovery order, never the pane. No helper
# or no output is unknown, never a verdict: the round proceeds.
if [ -x "$QPN" ]; then
  QPN_OUT="$(run_bounded "$QPN" --status "$SESSION" 2>/dev/null | grep -m1 "^session=" || true)"
  evidence "quota-park: ${QPN_OUT:-no-output}"
  case "$QPN_OUT" in *"quota_park=yes"*) verdict parked ;; esac
else
  evidence "quota-park: helper-unavailable ($QPN) — treated as unknown"
fi

# 2. Liveness in the session list. Absent/closed/archived = nothing to
# interrogate; an unreadable list proves nothing and the pane probe decides.
STATE="$(run_bounded gc session list --state=all --json 2>/dev/null \
  | jq -r --arg s "$SESSION" '[.sessions[]? | select(.id == $s or (.alias // "") == $s or (.session_name // "") == $s)][0].state // "absent"' 2>/dev/null)"
[ -n "$STATE" ] || STATE="unreadable"
evidence "session-state: $STATE"
case "$STATE" in absent|closed|archived) verdict missing ;; esac

# 3. Baseline pane hash, digits normalized out (timers advance on their own —
# same normalization boot-health.sh uses).
pane_hash() { printf '%s' "$1" | tr -d '0-9' | cksum | awk '{print $1}'; }
PRE_RC=0
PRE="$(run_bounded gc session peek "$SESSION" --lines "$PEEK_LINES" 2>/dev/null)" || PRE_RC=$?
PRE_HASH="$(pane_hash "$PRE")"
evidence "baseline-peek: rc=$PRE_RC"

# 4. Challenge. The text avoids every quota-park banner phrase — it lands in
# the pane the next probe reads.
CHALLENGE="DOG PROBE (round $ROUND of 3): a warrant names this session as possibly wedged. Any progress — a tool call, a bead update, new pane output — pardons you. If you are healthy, continue your work now."
NUDGE_RC=0
run_bounded gc session nudge --delivery immediate "$SESSION" "$CHALLENGE" >/dev/null 2>&1 || NUDGE_RC=$?
# Plain-form fallback only on a fast usage error (older gc); a timeout/signal
# may already have delivered and must not double-send.
if [ "$NUDGE_RC" -ne 0 ] && [ "$NUDGE_RC" -ne 124 ] && [ "$NUDGE_RC" -lt 128 ]; then
  NUDGE_RC=0
  run_bounded gc session nudge "$SESSION" "$CHALLENGE" >/dev/null 2>&1 || NUDGE_RC=$?
fi
evidence "nudge: rc=$NUDGE_RC"

# 5. Poll for life inside the bound. Life = busy marker in the current tail,
# or a digit-normalized pane change against the baseline.
START="$(date +%s)"
DEADLINE=$((START + WAIT))
ALIVE=""
while :; do
  NOW="$(date +%s)"; WAITED=$((NOW - START))
  CUR_RC=0
  CUR="$(run_bounded gc session peek "$SESSION" --lines "$PEEK_LINES" 2>/dev/null)" || CUR_RC=$?
  if [ "$CUR_RC" -eq 0 ] && [ -n "$CUR" ]; then
    if grep -qEi -- "$BUSY_RE" < <(printf '%s\n' "$CUR" | tail -n 12); then
      ALIVE="busy-marker"; break
    fi
    CUR_HASH="$(pane_hash "$CUR")"
    if [ "$PRE_RC" -eq 0 ] && [ "$CUR_HASH" != "$PRE_HASH" ]; then
      ALIVE="pane-movement"; break
    fi
    # A failed baseline is replaced by the first successful read; movement is
    # then judged against THAT, never against no evidence.
    if [ "$PRE_RC" -ne 0 ]; then PRE_RC=0; PRE_HASH="$CUR_HASH"; fi
  fi
  [ "$NOW" -ge "$DEADLINE" ] && break
  sleep "$POLL"
done

if [ -n "$ALIVE" ]; then
  evidence "life: $ALIVE"
  verdict alive
fi
evidence "life: none within ${WAIT}s bound"
verdict silent
