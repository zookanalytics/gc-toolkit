#!/usr/bin/env bash
# decline — end the work this session holds, having recorded what stops it: the
# human gate, then the wait, then the end of the run or the claim, then the drain.
#
#   decline.sh --step <ref> --reason "<text>"
#              [--subject <bead> --key <key> --message "<text>" [--formula <f>]]
#
# With no gate, nobody has a decision to make: the work is finished, or another
# run is building it. With --subject, --key and --message a person must rule, and
# the gate blocks <subject>. With --formula as well, the work goes on once they
# rule: <subject> waits on the gate and is armed to re-sling through <f>, and this
# call tells them so at the end of the message. A decline is an event of its run,
# so the gate declares no quiet window, and a situation a person answered moot or
# benign before is asked again.
#
# What this session holds is read before anything is written: the bead `gc hook
# current` names. A bead with a gc.step_ref is a step of a run, and the run ends
# through run-cancel.sh. A bead with none is a claim with no run, which a claimant
# with no poured workflow holds on the work bead itself, so nothing is cancelled.
# A gated decline of such a claim ends once the gate and the wait have landed,
# and await-ruling.sh has then released the claim. With no gate, the claim is
# handed back (hand-back.sh) in one write guarded on this session's claim, which
# also clears gc.routed_to: a release alone would leave the route offering the
# bead straight back to the pool, and each new claimant would refuse it again
# until the run building it finishes. gc.execution_routed_to stays, because
# await-ruling.sh re-slings from it. The write is read back before the drain. A
# bead already closed holds no claim, so nothing is handed back.
#
# The parts run in that order because an end with no record behind it leaves work
# nothing re-offers. A part that does not land stops the sequence and nothing after
# it runs, so the session does not drain. A step then stays claimed, and the next
# worker it goes to retries. A claim with no run stays with this session, which
# can run this again. Gas City's run cancel interrupts the session that holds the
# step, so this call can end as an interrupted tool call once the cancel has landed.
#
# Callers: mol-polecat-work's step scripts (work-lib.sh's callers).
# exit: 0 the work is ended and this session drained · 1 a part did not land ·
#       2 usage, nothing written
set -uo pipefail

PROG="decline"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: decline.sh --step <ref> --reason "<text>"
                  [--subject <bead> --key <key> --message "<text>" [--formula <f>]]

  --step     the gc.step_ref of the step this session holds
  --reason   why the run ends; run-cancel.sh records it on that step
  --subject  the bead the gate blocks, and the bead that waits on it
  --key      the gate's situation key
  --message  what the gate tells the person, and what they must do
  --formula  the formula a re-sling pours; with it the subject waits on the gate

exit: 0 ended and drained · 1 a part did not land · 2 usage, nothing written
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
}

STEP=""; REASON=""; SUBJECT=""; KEY=""; MESSAGE=""; FORMULA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --step)    require_value "$@"; STEP="$2";    shift 2 ;;
    --reason)  require_value "$@"; REASON="$2";  shift 2 ;;
    --subject) require_value "$@"; SUBJECT="$2"; shift 2 ;;
    --key)     require_value "$@"; KEY="$2";     shift 2 ;;
    --message) require_value "$@"; MESSAGE="$2"; shift 2 ;;
    --formula) require_value "$@"; FORMULA="$2"; shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *)         echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if [ -z "$STEP" ] || [ -z "$REASON" ]; then
  echo "$PROG: --step and --reason are both required" >&2
  usage
  exit 2
fi
if [ -n "$SUBJECT$KEY$MESSAGE" ] && { [ -z "$SUBJECT" ] || [ -z "$KEY" ] || [ -z "$MESSAGE" ]; }; then
  echo "$PROG: a gate needs --subject, --key and --message together" >&2
  usage
  exit 2
fi
if [ -n "$FORMULA" ] && [ -z "$SUBJECT" ]; then
  echo "$PROG: --formula needs a gate to wait on" >&2
  usage
  exit 2
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"

# claim_read <bead> -> "<status>|<assignee>|<gc.step_ref>|<gc.routed_to>", or
# nothing when the bead does not read.
claim_read() {
  gc bd show "$1" --json </dev/null 2>/dev/null | grep -a -vE '^gc bd:' | scrub | jq -r --arg id "$1" '
    if type == "array" and (.[0].id // "") == $id then
      .[0] | [(.status // ""), (.assignee // ""), (.metadata["gc.step_ref"] // ""), (.metadata["gc.routed_to"] // "")]
      | map(tostring) | join("|")
    else empty end' 2>/dev/null
}

# A claim with no run: what `gc hook current` names reads, and carries no
# gc.step_ref. Anything this cannot read is a step, whose cancel proves the run
# is this session's or refuses.
CLAIM=""; CLAIM_STATUS=""
HELD=$(gc hook current --id-only </dev/null 2>/dev/null) || HELD=""
if [ -n "$HELD" ]; then
  ROW=$(claim_read "$HELD")
  IFS='|' read -r ROW_STATUS _ ROW_STEP _ <<<"$ROW"
  if [ -n "$ROW" ] && [ -z "$ROW_STEP" ]; then
    CLAIM="$HELD"
    CLAIM_STATUS="$ROW_STATUS"
  fi
fi
if [ -n "$CLAIM" ]; then
  KEEP="NOT draining: $CLAIM is a claim with no run, so it stays with this session, which can run this again."
else
  KEEP="NOT cancelling or draining, so the next worker retries."
fi

if [ -n "$SUBJECT" ]; then
  [ -z "$FORMULA" ] || MESSAGE="$MESSAGE Then clear this gate: $SUBJECT waits on it, and clearing it re-slings $SUBJECT. To stand down instead, close $SUBJECT first."
  if ! "$SCRIPT_DIR/human-gate.sh" --subject "$SUBJECT" --key "$KEY" --message "$MESSAGE"; then
    echo "$PROG: human-gate.sh recorded no gate; $KEEP" >&2
    exit 1
  fi
  if [ -n "$FORMULA" ] && ! "$SCRIPT_DIR/await-ruling.sh" "$SUBJECT" --key "$KEY" --formula "$FORMULA"; then
    echo "$PROG: the wait did not land on $SUBJECT; $KEEP" >&2
    exit 1
  fi
fi

if [ -n "$CLAIM" ]; then
  if [ -z "$SUBJECT" ] && [ "$CLAIM_STATUS" != closed ]; then
    if ! "$SCRIPT_DIR/hand-back.sh" "$CLAIM" --set-metadata gc.routed_to="" >&2; then
      echo "$PROG: the claim on $CLAIM was not handed back; $KEEP" >&2
      exit 1
    fi
    IFS='|' read -r NOW_STATUS NOW_HOLDER _ NOW_ROUTE <<<"$(claim_read "$CLAIM")"
    if [ "$NOW_STATUS" != open ] || [ -n "$NOW_HOLDER" ] || [ -n "$NOW_ROUTE" ]; then
      echo "$PROG: the hand-back of $CLAIM did not read back: it shows status ${NOW_STATUS:-unreadable}, assignee ${NOW_HOLDER:-none} and gc.routed_to ${NOW_ROUTE:-none}; $KEEP" >&2
      exit 1
    fi
  fi
  gc runtime drain-ack
  exit 0
fi

if ! "$SCRIPT_DIR/run-cancel.sh" --step "$STEP" --reason "$REASON"; then
  echo "$PROG: run-cancel.sh did not end the run; NOT draining, so the next worker retries." >&2
  exit 1
fi
gc runtime drain-ack
exit 0
