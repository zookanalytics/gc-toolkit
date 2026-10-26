#!/usr/bin/env bash
# claim-context — the one read a session orients from after `gc hook --claim`:
# the claimed bead, the workflow it belongs to, and the state of the work bead
# that workflow was poured for, so the session starts the step without
# re-reading any of them.
#
#   claim-context.sh <bead-id> [--step]
#
# <bead-id> is the bead_id the claim returned. The output names that bead and
# its gc.step_ref, the workflow root with its formula and input convoy, and the
# work bead: its title, status, assignee, priority, type, metadata, notes and
# description. --step adds the claimed bead's own title and description, which
# for a formula step are its instructions, for a claim result with no
# step_reminder, as every result on the claimed tier is.
#
# The work bead is the input convoy's one tracked member. A claimed bead that
# belongs to no workflow is the work bead itself. A workflow with no input
# convoy, such as one an order pours, has no work bead, and a convoy that tracks
# more than one bead has no single one; the output says which, and lists the
# tracked beads.
#
# It reads the claimed bead and the input convoy, and nothing else unless a
# record lacks what it needs. The claimed bead's record carries its workflow
# root as a dependency, with the root's metadata, and the input convoy's record
# carries each tracked bead whole, notes included. A root missing from the
# claimed bead's record costs one more read.
#
# It only reads, and it reads to orient. A step's own blocks still read what
# they act on, and a premise read here is read again before an act on it.
#
# Callers: the polecat and polecat-codex prompts' claim contract
# (template-fragments/polecat-doctrine.template.md), which their nudges point at.
# exit: 0 printed · 1 a read failed, and what did read is printed with the read
# to make by hand · 2 usage
set -uo pipefail

PROG="claim-context"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }

usage() {
  cat >&2 <<'USAGE'
usage: claim-context.sh <bead-id> [--step]

Prints what a session orients on after gc hook --claim: the claimed bead and its
gc.step_ref, its workflow root, formula and input convoy, and the work bead's
title, status, assignee, priority, type, metadata, notes and description.
--step adds the claimed bead's own title and description, the step's
instructions, for a claim result that carries no step_reminder.
USAGE
}

BEAD=""; WANT_STEP=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --step)    WANT_STEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        usage; exit 2 ;;
    *)         [ -z "$BEAD" ] || { usage; exit 2; }; BEAD="$1"; shift ;;
  esac
done
[ -n "$BEAD" ] || { usage; exit 2; }

# show <id> -> that bead's record as one JSON object, empty when it does not
# read. The record is picked by id, so a read that answers for another bead
# reads as no record.
show() {
  bd_json show "$1" \
    | jq -c --arg id "$1" 'if type == "array" then (map(select(type == "object" and .id == $id)) | .[0] // empty) else empty end' 2>/dev/null
}

# get <record> <jq filter> -> the filter's raw output, empty when it fails.
get() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

# meta <record> <key> -> one metadata value as a string, empty when absent.
meta() { printf '%s' "$1" | jq -r --arg k "$2" '(.metadata[$k] // "") | tostring' 2>/dev/null; }

# instructions <record>: a bead's own title and description, in the shape gc
# renders a step_reminder.
instructions() {
  printf '%s' "$1" | jq -r '
    "Step instructions:", "",
    "## \(.title // "") (\(.id))", "",
    ((.description // "") | if . == "" then "(no description)" else . end)'
}

# work_bead <record>: everything the session orients on about the work bead.
work_bead() {
  printf '%s' "$1" | jq -r '
    def or_none: (. // "") | tostring | if . == "" then "none" else . end;
    "Work bead \(.id): \(.title // "")",
    "Status \(.status | or_none), assignee \(.assignee | or_none), priority \(if .priority == null then "none" else "P\(.priority)" end), type \(.issue_type | or_none).",
    "", "Metadata:"'
  if [ "$(get "$1" '(.metadata // {}) | length')" = 0 ]; then
    echo "(none)"
  else
    printf '%s' "$1" | jq -S '.metadata'
  fi
  printf '%s' "$1" | jq -r '
    def body: (. // "") | tostring | if . == "" then "(none)" else . end;
    "", "Notes:", (.notes | body), "", "Description:", (.description | body)'
}

CLAIMED=$(show "$BEAD")
if [ -z "$CLAIMED" ]; then
  echo "$PROG: $BEAD did not read. Read it with: gc bd show $BEAD --json" >&2
  exit 1
fi

ROOT_ID=$(meta "$CLAIMED" gc.root_bead_id)
STEP_REF=$(meta "$CLAIMED" gc.step_ref)
ROOT=""
if [ -n "$ROOT_ID" ]; then
  ROOT=$(printf '%s' "$CLAIMED" \
    | jq -c --arg r "$ROOT_ID" '[.dependencies[]? | select(type == "object" and .id == $r and (.metadata | type) == "object")][0] // empty' 2>/dev/null)
  [ -n "$ROOT" ] || ROOT=$(show "$ROOT_ID")
elif [ "$(meta "$CLAIMED" gc.kind)" = workflow ]; then
  ROOT_ID="$BEAD"; ROOT="$CLAIMED"
fi

# The claimed bead, then its instructions when asked for, then the workflow.
if [ -z "$ROOT_ID" ]; then
  echo "Claimed $BEAD ($(get "$CLAIMED" '.status // "unknown"')). It belongs to no workflow, so it is the work bead."
  echo
  work_bead "$CLAIMED"
  exit 0
fi
if [ "$ROOT_ID" = "$BEAD" ]; then
  echo "Claimed $BEAD ($(get "$CLAIMED" '.status // "unknown"')), the root of a workflow, whose work runs as its step beads."
else
  echo "Claimed $BEAD, step ${STEP_REF:-with no gc.step_ref} ($(get "$CLAIMED" '.status // "unknown"'))."
fi
if [ -n "$WANT_STEP" ] && [ "$ROOT_ID" != "$BEAD" ]; then
  echo
  instructions "$CLAIMED"
fi
echo
if [ -z "$ROOT" ]; then
  echo "Workflow $ROOT_ID did not read. Read it with: gc bd show $ROOT_ID --json"
  exit 1
fi
FORMULA=$(meta "$ROOT" gc.formula_name)
[ -n "$FORMULA" ] || FORMULA=$(get "$ROOT" '.title // ""')
CONVOY_ID=$(meta "$ROOT" gc.input_convoy_id)
if [ -z "$CONVOY_ID" ]; then
  echo "Workflow $ROOT_ID runs ${FORMULA:-an unnamed formula} with no input convoy, so it has no work bead. The step's instructions are the plan."
  exit 0
fi
echo "Workflow $ROOT_ID runs ${FORMULA:-an unnamed formula} over input convoy $CONVOY_ID."
echo

CONVOY=$(show "$CONVOY_ID")
if [ -z "$CONVOY" ]; then
  echo "Input convoy $CONVOY_ID did not read. Read it with: gc bd show $CONVOY_ID --json"
  exit 1
fi
TRACKED=$(get "$CONVOY" '[.dependencies[]? | select(type == "object" and .dependency_type == "tracks")] | tojson')
case "$(get "$TRACKED" 'length')" in
  1)
    work_bead "$(get "$TRACKED" '.[0] | tojson')" ;;
  0|"")
    echo "Input convoy $CONVOY_ID tracks no bead, so this workflow has no work bead." ;;
  *)
    echo "Input convoy $CONVOY_ID tracks more than one bead, so this workflow has no single work bead:"
    get "$TRACKED" '.[] | "  \(.id) (\(.status // "unknown")): \(.title // "")"' ;;
esac
exit 0
