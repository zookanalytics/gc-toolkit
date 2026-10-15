#!/usr/bin/env bash
# held-work-gate — end a run that would start work a hold holds, and arm the
# work to re-sling once nothing holds it.
#
#   held-work-gate.sh --bead <work-bead> --formula <formula> --step <formula.step-id>
#                     [--step-bead <id>] [--sling-arg <arg>]... [--dry-run]
#
# `gc sling --on` pours without reading any edge, so a bead that a park or a
# prerequisite holds still reaches a worker: slung by hand, accepted, or poured
# before the hold. bd's cascade cannot reach the run, because a workflow's root
# has no parent and its steps hang off the root by `tracks` edges. So a formula
# that starts work from a subject calls this gate before the first step that
# acts on the subject: mol-polecat-work's load-context, and mol-design-convoy's,
# whose next step pushes an integration branch. mol-polecat-work's
# submit-and-exit calls it again before the hand-off, for a blocker that landed
# on the bead while it was built.
#
# What holds a bead is hold-lib.sh's, the definition deferred dispatch reads
# too: an open `blocks` edge onto an open bead, on the bead or on one of its
# parent-child ancestors, where a demand gate on an ancestor does not count. A
# bead in flight, one that carries a branch, a merge_result or a
# rejection_reason, is held only by a blocker of its own. So work already begun
# under a parked epic finishes, and a rejected handoff's rebuild runs. The
# design's other sign of work in flight, a workflow poured for the bead that has
# passed load-context, is not read here: the run calling this gate has not
# passed it, and a second live run on the bead is the duplicate-dispatch gate's
# to refuse.
#
# A held bead is declined, in this order:
#   1. When the bead names the pool it was poured to, one update clears the
#      route keys a pour leaves, because deferred dispatch refuses to arm a
#      routed bead. The same update records the pool as resling_target, so a
#      re-run after a failed arm still finds it, and drops the session pins a
#      claim stamps, which gascity's detached-handoff orphan sweep would
#      otherwise turn back into a pool route on a bead with a branch.
#   2. Deferred dispatch is armed to re-sling the bead --on <formula>, with each
#      --sling-arg after it, to that pool. Its reconcile reads the same hold, so
#      the arm fires once nothing holds the bead: the park is released, or the
#      prerequisite closes. With no pool, or an arm that does not land, a visit
#      (escalate.sh, key polecat-blocked-work) asks a person for the re-sling.
#   3. A note on the work bead says what held it and which release landed.
#   4. run-cancel.sh ends the run through gascity's run cancel. A cancelled root
#      is closed, so it does not stand in the way of the re-sling's pour.
#   5. The session drains.
# Nothing is cancelled until the arm or the visit has landed, and nothing drains
# until the cancel has. A cancelled run with nothing recorded to re-sling it
# leaves work that nothing re-offers, and a drain after a cancel that failed
# leaves the run's step claimable. Either way the step stays claimed, so the
# worker it goes to next retries.
#
# A walk that cannot read holds the bead, as it holds an arm in deferred
# dispatch: the decline costs a cancelled run, and the arm fires on the first
# pass that reads nothing holding the bead. A closed bead has no work to start,
# so its run is cancelled with no re-sling and no visit.
#
# env: GC_DEFERRED_DISPATCH_TOOL, GC_ESCALATE_TOOL and GC_RUN_CANCEL_TOOL replace
#      the sibling scripts, and GC_BD_LIB and GC_HOLD_LIB the libraries.
# Callers: mol-polecat-work (load-context and submit-and-exit) and
#          mol-design-convoy (load-context).
# exit: 0 nothing holds the bead, so the run goes on · 1 the run is declined,
#       and drained once its cancel landed · 2 usage
set -uo pipefail

PROG="held-work-gate"

usage() {
  cat >&2 <<'USAGE'
usage: held-work-gate.sh --bead <work-bead> --formula <formula> --step <formula.step-id>
                         [--step-bead <id>] [--sling-arg <arg>]... [--dry-run]

  --bead       the work bead the run was poured for (required)
  --formula    the formula the re-sling pours, e.g. mol-polecat-work (required)
  --step       the gc.step_ref of the step this shell is executing, e.g.
               mol-polecat-work.load-context; a decline cancels its run
               (required)
  --step-bead  the bead_id `gc hook --claim --json` returned for that step, a
               hint run-cancel.sh uses only once it verifies
  --sling-arg  one more argument for the re-sling's `gc sling`, after
               --on <formula>; repeat it per argument, e.g. --sling-arg --var
               --sling-arg design_gated=false
  --dry-run    read and report what holds the bead; write, cancel and drain
               nothing

exit: 0 nothing holds the bead, so the run goes on · 1 the run is declined,
      and drained once its cancel landed · 2 usage
USAGE
}

BEAD=""; FORMULA=""; STEP=""; STEP_BEAD=""; DRY_RUN=0; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --bead|--formula|--step|--step-bead|--sling-arg)
      if [ "$#" -lt 2 ]; then echo "$PROG: $1 requires a value" >&2; usage; exit 2; fi
      case "$1" in
        --bead)      BEAD="$2" ;;
        --formula)   FORMULA="$2" ;;
        --step)      STEP="$2" ;;
        --step-bead) STEP_BEAD="$2" ;;
        --sling-arg) EXTRA+=(--sling-arg "$2") ;;
      esac
      shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if [ -z "$BEAD" ] || [ -z "$FORMULA" ] || [ -z "$STEP" ]; then
  echo "$PROG: --bead, --formula and --step are all required" >&2; usage; exit 2
fi
case "$BEAD$FORMULA$STEP" in
  *'{{'*|*'}}'*)
    echo "$PROG: an argument was passed unsubstituted ('$BEAD' '$FORMULA' '$STEP'); the pour did not render it" >&2; exit 2 ;;
  *[!A-Za-z0-9._-]*)
    echo "$PROG: --bead, --formula and --step must contain only [A-Za-z0-9._-]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" \
  || { echo "$PROG: cannot source bd-lib.sh beside this script; nothing was read, cancelled or drained" >&2; exit 1; }
# shellcheck source=hold-lib.sh
. "${GC_HOLD_LIB:-$SCRIPT_DIR/hold-lib.sh}" \
  || { echo "$PROG: cannot source hold-lib.sh beside this script; nothing was read, cancelled or drained" >&2; exit 1; }
ARM_TOOL="${GC_DEFERRED_DISPATCH_TOOL:-$SCRIPT_DIR/deferred-dispatch.sh}"
ESCALATE="${GC_ESCALATE_TOOL:-$SCRIPT_DIR/escalate.sh}"
RUN_CANCEL="${GC_RUN_CANCEL_TOOL:-$SCRIPT_DIR/run-cancel.sh}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-held-work-gate.XXXXXX")" \
  || { echo "$PROG: cannot make a scratch directory; nothing was read, cancelled or drained" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# The hold walk's reader (hold-lib.sh): the named beads at every status and of
# every class a listing hides by default, since a blocker can be a gate and an
# ancestor can be closed.
hwg_read() {
  bd_json list --id "$1" --all --include-gates --include-infra --include-templates --brief --limit 0
}

SEED="$TMP/seed.json"; GRAPH="$TMP/graph.json"
UNREAD=""; STATUS=""; FLIGHT=""; HOLD=""; POOL=""
if ! hwg_read "$BEAD" > "$TMP/row.json"; then
  UNREAD="the store did not answer a read of $BEAD"
elif ! jq -c --arg b "$BEAD" '[ .[]? | objects | select(((.id // "") | tostring) == $b) ]' "$TMP/row.json" > "$SEED" 2>/dev/null \
    || ! jq -e 'length == 1' "$SEED" >/dev/null 2>&1; then
  UNREAD="$BEAD did not read back as one bead"
else
  STATUS="$(jq -r '(.[0].status // "") | tostring' "$SEED" 2>/dev/null)"
  FLIGHT="$(jq -r "$HOLD_JQ"'.[0] | hold_flight_why' "$SEED" 2>/dev/null)"
  # The pool the last pour ran on, else a route, else an arm or a re-sling an
  # earlier decline recorded, the order await-ruling.sh reads them in.
  POOL="$(jq -r '(.[0].metadata // {}) | if type == "object"
      then [ .["gc.execution_routed_to"], .["gc.routed_to"], .["gc.dispatch_when_ready"], .["resling_target"] ]
           | map(select(. != null) | tostring | select(. != "")) | .[0] // ""
      else "" end' "$SEED" 2>/dev/null)"
  case "$POOL" in */*) ;; *) POOL="" ;; esac
  if ! hold_graph hwg_read "$SEED" "$GRAPH"; then
    UNREAD="its blockers or ancestors did not read"
  elif ! HOLD="$(jq -r --slurpfile g "$GRAPH" "$HOLD_JQ"'.[0] | hold_summary($g[0])' "$SEED" 2>/dev/null)"; then
    UNREAD="what holds $BEAD did not evaluate"
  fi
fi
[ -z "$UNREAD" ] || HOLD="an unreadable hold ($UNREAD)"

# cancel_and_drain <reason> — end the run of $STEP, then drain. Exits 1 either
# way; a cancel that did not land leaves the step claimed and does not drain.
cancel_and_drain() {
  if "$RUN_CANCEL" --step "$STEP" --bead "$STEP_BEAD" --reason "$1" </dev/null; then
    gc runtime drain-ack </dev/null || echo "$PROG: the run is cancelled, but drain-ack failed; end this session" >&2
    exit 1
  fi
  echo "$PROG: run-cancel.sh did not end the run; NOT draining, so the next worker retries" >&2
  exit 1
}

if [ "$STATUS" = closed ]; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "$PROG: DRY RUN: $BEAD is closed; a decline would cancel the run of $STEP with no re-sling"
    exit 1
  fi
  gc bd update "$BEAD" --append-notes "Held-work gate: $STEP found $BEAD closed, so its run has no work to start. The run is cancelled, with no re-sling." </dev/null >/dev/null 2>&1 \
    || echo "$PROG: the note did not land on $BEAD; the cancel reason on the step still records it" >&2
  cancel_and_drain "work bead $BEAD is closed, so its run has no work to start"
fi

if [ -z "$HOLD" ]; then
  if [ -n "$FLIGHT" ]; then
    echo "$PROG: $BEAD is in flight ($FLIGHT), so only a blocker of its own holds it, and none is open; the run goes on"
  else
    echo "$PROG: nothing holds $BEAD; the run goes on"
  fi
  exit 0
fi

if [ "$DRY_RUN" = 1 ]; then
  echo "$PROG: DRY RUN: $BEAD is held by $HOLD; a decline would arm a re-sling --on $FORMULA to ${POOL:-no pool, so a visit instead}, cancel the run of $STEP and drain"
  exit 1
fi

# The re-sling's arguments as a person would type them, for the visit.
SLING_TEXT="--on $FORMULA"; i=1
while [ "$i" -lt "${#EXTRA[@]}" ]; do SLING_TEXT="$SLING_TEXT ${EXTRA[$i]}"; i=$((i + 2)); done

RELEASE=""; ARM_OUT=""
if [ -n "$POOL" ] && [ -x "$ARM_TOOL" ]; then
  gc bd update "$BEAD" --set-metadata gc.routed_to= --set-metadata gc.deferred_routed_to= \
      --set-metadata gc.execution_routed_to= --set-metadata gc.deferred_execution_routed_to= \
      --set-metadata gc.deferred_assignee= --set-metadata "resling_target=$POOL" \
      --unset-metadata gc.session_id --unset-metadata gc.session_name </dev/null >/dev/null 2>&1 \
    || echo "$PROG: the route keys on $BEAD did not clear; deferred dispatch refuses to arm a routed bead" >&2
  if ARM_OUT="$("$ARM_TOOL" arm "$BEAD" --target "$POOL" --sling-arg --on --sling-arg "$FORMULA" ${EXTRA[@]+"${EXTRA[@]}"} \
       --reason "held-work gate: $STEP declined it, held by $HOLD" </dev/null 2>&1)"; then
    printf '%s\n' "$ARM_OUT"
    RELEASE="a re-sling $SLING_TEXT is armed to $POOL, which deferred dispatch fires once nothing holds $BEAD"
  else
    printf '%s\n' "$ARM_OUT" >&2
  fi
fi
if [ -z "$RELEASE" ] && "$ESCALATE" --subject "$BEAD" --key polecat-blocked-work --message "$BEAD reached $STEP while held by $HOLD, so its run is cancelled. The re-sling could not be armed (pool '${POOL:-none}'). Once nothing holds $BEAD, re-sling it: gc sling ${POOL:-<pool>} $BEAD $SLING_TEXT" </dev/null; then
  RELEASE="no re-sling could be armed (pool '${POOL:-none}'), so a visit asks for one"
fi
if [ -z "$RELEASE" ]; then
  echo "$PROG: neither the re-sling arm nor a visit landed for $BEAD; NOT cancelling or draining, so the next worker retries" >&2
  exit 1
fi

gc bd update "$BEAD" --append-notes "Held-work gate: $STEP declined $BEAD, held by $HOLD. The run is cancelled, and $RELEASE." </dev/null >/dev/null 2>&1 \
  || echo "$PROG: the note did not land on $BEAD; the cancel reason on the step still records it" >&2
echo "$PROG: declined $BEAD at $STEP, held by $HOLD; $RELEASE"
cancel_and_drain "held-work gate: $BEAD is held by $HOLD; $RELEASE"
