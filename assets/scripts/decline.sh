#!/usr/bin/env bash
# decline — end the run this session is executing, having recorded what stops
# it: the human gate, then the wait, then the run's cancel, then the drain.
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
# The parts run in that order because a cancelled run with no record behind it
# leaves work nothing re-offers. A part that does not land stops the sequence and
# nothing after it runs, so the step stays claimed and the next worker it goes to
# retries. Gas City's run cancel interrupts the session that holds the step, so
# this call can end as an interrupted tool call once the cancel has landed.
#
# Callers: mol-polecat-work's step scripts (work-lib.sh's callers).
# exit: 0 the run is ended and this session drained · 1 a part did not land ·
#       2 usage, nothing written
set -uo pipefail

PROG="decline"

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

if [ -n "$SUBJECT" ]; then
  [ -z "$FORMULA" ] || MESSAGE="$MESSAGE Then clear this gate: $SUBJECT waits on it, and clearing it re-slings $SUBJECT. To stand down instead, close $SUBJECT first."
  if ! "$SCRIPT_DIR/human-gate.sh" --subject "$SUBJECT" --key "$KEY" --message "$MESSAGE"; then
    echo "$PROG: human-gate.sh recorded no gate; NOT cancelling or draining, so the next worker retries." >&2
    exit 1
  fi
  if [ -n "$FORMULA" ] && ! "$SCRIPT_DIR/await-ruling.sh" "$SUBJECT" --key "$KEY" --formula "$FORMULA"; then
    echo "$PROG: the wait did not land on $SUBJECT; NOT cancelling or draining, so the next worker retries." >&2
    exit 1
  fi
fi
if ! "$SCRIPT_DIR/run-cancel.sh" --step "$STEP" --reason "$REASON"; then
  echo "$PROG: run-cancel.sh did not end the run; NOT draining, so the next worker retries." >&2
  exit 1
fi
gc runtime drain-ack
exit 0
