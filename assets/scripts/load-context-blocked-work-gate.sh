#!/usr/bin/env bash
# load-context-blocked-work-gate — refuse to build a work bead that an open
# `blocks` dependency still gates, and arm its re-dispatch for when the blocker
# closes.
#
#   load-context-blocked-work-gate.sh --bead <work-bead> [--step-bead <claimed step bead>]
#
# `gc sling <target> <bead> --on <formula>` pours the formula immediately and
# reads no `blocks` deps. Under a graph.v2 dispatch the routed record is the
# freshly minted workflow root, not the work bead, so a `blocks` edge on the work
# bead gates nothing and a blocked bead reaches a polecat as an offered claim
# (docs/gascity-routing-model.md). Raw pool routing does not have this problem:
# there the work bead itself is the routed unit and `bd ready` withholds it while
# a blocker is open. This gate is the pack-level safety net for the formula-sling
# path.
#
# On an open blocker the gate records a note on the work bead, clears its
# delivery keys, arms a deferred re-dispatch to the pool the pour was executing
# on, replaying `--on mol-polecat-work`, and holds the molecule at load-context.
#
# `arm` keys on gc.routed_to, so clearing gc.routed_to is what makes the bead
# armable. `reconcile` keys idempotency on its own gc.dispatch_when_ready_slung
# marker, not on gc.execution_routed_to, so the re-dispatch slings when the
# blocker closes whether or not that stamp is set; it is cleared alongside so the
# bead does not advertise a finished pour's pool. Status stays open and the
# assignee empty from the pour, so neither is written and no claim-guard rollback
# is possible. The open blocker keeps the bead out of `bd ready` throughout, so
# clearing the route opens no pool window.
#
# Escalation is the fallback only when the arm cannot be recorded. The drain is
# conditional on a recorded release path (the arm or the visit) AND a landed
# hold: a blocked, de-routed molecule with no way back is a silent stall, and a
# hold that did not fully land leaves the molecule claimable.
#
# env: GC_DEFERRED_DISPATCH_TOOL and GC_ESCALATE_HOLD_DRAIN_TOOL replace the
#      sibling scripts.
# exit: 0 no open blocker · 1 refused (held and drained when the hold landed)
#       · 2 usage
set -uo pipefail

PROG="load-context-blocked-work-gate"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ARM_TOOL="${GC_DEFERRED_DISPATCH_TOOL:-$SCRIPTS_DIR/deferred-dispatch.sh}"
EHD="${GC_ESCALATE_HOLD_DRAIN_TOOL:-$SCRIPTS_DIR/escalate-hold-drain.sh}"

usage() {
  echo "usage: $PROG --bead <work-bead> [--step-bead <claimed step bead>]" >&2
}

WORK_BEAD_ID=""; CLAIMED_STEP_BEAD_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead|--step-bead)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; usage; exit 2; }
      if [ "$1" = --bead ]; then WORK_BEAD_ID="$2"; else CLAIMED_STEP_BEAD_ID="$2"; fi
      shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ -n "$WORK_BEAD_ID" ] || { echo "$PROG: --bead is required" >&2; usage; exit 2; }

WORK_BEAD_JSON=$(gc bd show "$WORK_BEAD_ID" --json 2>/dev/null)
OPEN_BLOCKERS=$(printf '%s' "$WORK_BEAD_JSON" | jq -r '[.[0].dependencies[]? | select((.dependency_type == "blocks") and (.status != "closed")) | .id] | join(" ")' 2>/dev/null)
[ -n "$OPEN_BLOCKERS" ] || exit 0

POOL=$(printf '%s' "$WORK_BEAD_JSON" | jq -r '.[0].metadata["gc.execution_routed_to"] // .[0].metadata["gc.routed_to"] // empty' 2>/dev/null)
gc bd update "$WORK_BEAD_ID" --append-notes "bd-ready guard: refused to build $WORK_BEAD_ID at load-context; open blocks-blocker(s): $OPEN_BLOCKERS. Molecule held; re-dispatch armed to '$POOL' to fire once the blocker(s) close."
gc bd update "$WORK_BEAD_ID" --set-metadata gc.routed_to="" --set-metadata gc.deferred_routed_to="" --set-metadata gc.execution_routed_to="" --set-metadata gc.deferred_execution_routed_to="" --set-metadata gc.deferred_assignee=""
HOLD_ARGS=(--step mol-polecat-work.load-context --bead "$CLAIMED_STEP_BEAD_ID" --reason "work bead $WORK_BEAD_ID has open blocks-blocker(s) $OPEN_BLOCKERS; re-dispatch armed to re-offer when they close")
if [ -z "$POOL" ] || [ ! -x "$ARM_TOOL" ] || ! "$ARM_TOOL" arm "$WORK_BEAD_ID" --target "$POOL" --sling-arg --on --sling-arg mol-polecat-work --reason "bd-ready guard: blocked by $OPEN_BLOCKERS"; then
  HOLD_ARGS+=(--subject "$WORK_BEAD_ID" --key polecat-blocked-work --message "Formula-slung $WORK_BEAD_ID reached a polecat while blocked by open blocks-dep(s): $OPEN_BLOCKERS. Held at load-context; no workspace was touched and nothing was closed. Auto re-dispatch could not be armed (target='$POOL'); re-offer this work once the blocker(s) close.")
fi
"$EHD" "${HOLD_ARGS[@]}"
exit 1
