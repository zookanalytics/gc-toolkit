#!/usr/bin/env bash
# escalate-hold-drain — decline the step this shell is executing: record the
# release path, hold the molecule, and drain, each only after the one before it
# landed.
#
#   escalate-hold-drain.sh --step <formula.step-id> --reason "<text>" [--bead <id>]
#                          [--subject <bead-id> --key <situation-key> --message "<text>"]
#
# A refusal that drains without closing its step must leave the step blocked
# and the molecule de-routed, or the pool re-offers the step to a fresh worker
# every cycle. A de-routed molecule with nothing tracking it is a silent strand,
# so the visit that a human can claim is filed first. The order is:
#
#   1. escalate.sh files (or finds) the one open visit for --subject and --key.
#      Without --key there is no visit to file: the caller either has no decision
#      for a human (a finished bead) or recorded its own release path, such as an
#      armed deferred dispatch.
#   2. molecule-hold.sh sets the step blocked and clears the molecule's routes.
#   3. `gc runtime drain-ack` ends the session.
#
# A failed escalation holds and drains nothing, so the step stays claimable and
# the next worker retries the escalation. A hold that did not fully land drains
# nothing, because something in the molecule is still claimable and a drain
# hands it to a fresh worker that re-derives the same refusal.
#
# Callers: the mol-polecat-work gate scripts (load-context-duplicate-dispatch-gate.sh,
# load-context-blocked-work-gate.sh, submit-and-exit.sh) and the formula blocks that
# decline a step.
#
# env: GC_ESCALATE_TOOL and GC_MOLECULE_HOLD_TOOL replace the sibling scripts.
# exit: 0 held and drained · 2 usage · 3 no release path recorded, nothing held
#       · 4 the hold did not fully land, not drained · other: drain-ack's own code
set -uo pipefail

PROG="escalate-hold-drain"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ESCALATE="${GC_ESCALATE_TOOL:-$SCRIPTS_DIR/escalate.sh}"
HOLD="${GC_MOLECULE_HOLD_TOOL:-$SCRIPTS_DIR/molecule-hold.sh}"

usage() {
  cat >&2 <<'USAGE'
usage: escalate-hold-drain.sh --step <formula.step-id> --reason "<text>" [--bead <id>]
                              [--subject <bead-id> --key <situation-key> --message "<text>"]

  --step     the held step's gc.step_ref, passed to molecule-hold.sh (required)
  --reason   the hold reason, passed to molecule-hold.sh (required)
  --bead     the claimed step bead id, passed to molecule-hold.sh as its hint
  --subject, --key, --message
             the visit escalate.sh files before the hold; all three or none
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
}

STEP=""; REASON=""; HINT=""; SUBJECT=""; KEY=""; MESSAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --step)    require_value "$@"; STEP="$2";    shift 2 ;;
    --reason)  require_value "$@"; REASON="$2";  shift 2 ;;
    --bead)    require_value "$@"; HINT="$2";    shift 2 ;;
    --subject) require_value "$@"; SUBJECT="$2"; shift 2 ;;
    --key)     require_value "$@"; KEY="$2";     shift 2 ;;
    --message) require_value "$@"; MESSAGE="$2"; shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *)         echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$STEP" ] || [ -z "$REASON" ]; then
  echo "$PROG: --step and --reason are required" >&2
  usage
  exit 2
fi
if [ -n "$SUBJECT$KEY$MESSAGE" ] && { [ -z "$SUBJECT" ] || [ -z "$KEY" ] || [ -z "$MESSAGE" ]; }; then
  echo "$PROG: --subject, --key and --message go together; a visit needs all three" >&2
  usage
  exit 2
fi

if [ -n "$KEY" ] && ! "$ESCALATE" --subject "$SUBJECT" --key "$KEY" --message "$MESSAGE"; then
  echo "escalate.sh could not record a release path (no visit filed and none open); NOT holding or draining, so the step stays claimable and visible and the next worker retries the escalation, rather than parking a blocked molecule no human is asked about." >&2
  exit 3
fi
if ! "$HOLD" --step "$STEP" --bead "$HINT" --reason "$REASON"; then
  echo "molecule-hold did not fully land; NOT draining. Something in this molecule is still claimable, and a drain here hands it to a fresh polecat that re-derives the same refusal." >&2
  exit 4
fi
gc runtime drain-ack
