#!/usr/bin/env bash
# claim-close — close the step this session is running.
#
#   claim-close.sh --step <ref> [--outcome <v>] [--dry-run]
#
# `gc hook current --id-only` names the bead this session last claimed with `gc
# hook --claim`, and this script writes to no other. A close is the one write
# that advances a workflow, so the bead must also show it is the step the caller
# is finishing, the way upstream's mol-do-work and mol-polecat-commit check it:
# its gc.step_ref is <ref>, and this session holds it. A close re-run after the
# claim moved on therefore refuses, rather than closing the next step unrun.
#
# <ref> is the step's gc.step_ref, such as mol-review.review. For a check loop's
# step it is the loop's name, such as self-review, whose claims carry
# self-review.iteration.<n>.
#
# A bead already closed is reported and exits 0, so a close whose call was
# interrupted can be run again. A plain routed bead with no steps, such as a
# dog's warrant, is refused like any other bead that is not <ref>.
#
# Callers: the close block of each formula step that runs this script, and the
# polecat doctrine for a step inherited from core, whose text names no close.
# exit: 0 closed or already closed · 1 not closed, and running it again can
# change that · 2 refused, nothing written
set -uo pipefail

PROG="claim-close"

usage() {
  cat >&2 <<'USAGE'
usage: claim-close.sh --step <ref> [--outcome <v>] [--dry-run]

  --step     the gc.step_ref of the step you are finishing, as `claim-context.sh`
             printed it, e.g. mol-review.review; a check loop's name, e.g.
             self-review, for one of its iterations
  --outcome  value for metadata gc.outcome, default pass
  --dry-run  report what would close; write nothing

env: GC_SESSION_ID names the session gc hook current reads. GC_ALIAS,
     GC_SESSION_ID, GC_SESSION_NAME and GC_AGENT are the names it may hold a
     claim under.

exit: 0 closed or already closed · 1 not closed, and running it again can change
      that · 2 refused, nothing written
USAGE
}

# `OPT="$2"; shift 2` hangs the parse loop when the option ends argv.
require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
}

STEP=""; OUTCOME="pass"; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --step)    require_value "$@"; STEP="$2";    shift 2 ;;
    --outcome) require_value "$@"; OUTCOME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 2 ;;
    *)         echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
case "$STEP" in
  ''|*[!A-Za-z0-9._-]*)
    echo "$PROG: --step must name a gc.step_ref, in [A-Za-z0-9._-] (got '$STEP'); nothing was closed" >&2
    exit 2 ;;
esac
case "$OUTCOME" in
  ''|*[!A-Za-z0-9._-]*)
    echo "$PROG: --outcome must be in [A-Za-z0-9._-] (got '$OUTCOME'); nothing was closed" >&2
    exit 2 ;;
esac

_bd_lib_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }

if ! ID=$(gc hook current --id-only </dev/null) || [ -z "$ID" ]; then
  echo "$PROG: gc hook current names no bead this session claimed, so $STEP is not closed. Claim it with gc hook --claim --json." >&2
  exit 1
fi
ROW=$(bd_json show "$ID")
if ! printf '%s' "$ROW" | jq -e --arg id "$ID" 'type == "array" and .[0].id == $id' >/dev/null 2>&1; then
  echo "$PROG: could not read $ID, the bead this session claimed, so $STEP is not closed" >&2
  exit 1
fi

REF=$(printf '%s' "$ROW" | jq -r '.[0].metadata["gc.step_ref"] // ""')
case "$REF" in
  "$STEP"|"$STEP".iteration.*) ;;
  *)
    echo "$PROG: this session's current claim is $ID (${REF:-not a formula step}), not $STEP, so nothing was closed. When you have not claimed $STEP yet, run gc hook --claim --json first." >&2
    exit 2 ;;
esac

STATUS=$(printf '%s' "$ROW" | jq -r '.[0].status // ""')
if [ "$STATUS" = closed ]; then
  echo "$PROG: $ID ($REF) is already closed"
  exit 0
fi
case "$STATUS" in
  open|in_progress) ;;
  *)
    echo "$PROG: $ID ($REF) is $STATUS, so nothing was closed" >&2
    exit 2 ;;
esac

ASSIGNEE=$(printf '%s' "$ROW" | jq -r '.[0].assignee // ""')
case "$ASSIGNEE" in
  "")
    echo "$PROG: $ID ($REF) has no assignee, so this session no longer holds it; nothing was closed" >&2
    exit 2 ;;
  "${GC_ALIAS:-}"|"${GC_SESSION_ID:-}"|"${GC_SESSION_NAME:-}"|"${GC_AGENT:-}") ;;
  *)
    echo "$PROG: $ID ($REF) is held by $ASSIGNEE, not this session; nothing was closed" >&2
    exit 2 ;;
esac

if [ "$DRY_RUN" = 1 ]; then
  echo "$PROG: DRY RUN: would close $ID ($REF) outcome=$OUTCOME"
  exit 0
fi
if ! gc bd update "$ID" --set-metadata "gc.outcome=$OUTCOME" --status=closed >/dev/null; then
  echo "$PROG: the close of $ID ($REF) did not land, so the step is still open" >&2
  exit 1
fi
echo "$PROG: closed $ID ($REF) outcome=$OUTCOME"
