#!/usr/bin/env bash
# molecule-hold — hand a decline from step text that names this script to
# run-cancel.sh.
#
#   molecule-hold.sh --step <formula.step-id> --reason "<text>" [--bead <id>] [--dry-run]
#
# A molecule keeps the step text it was poured with, and the scripts that text
# calls are read from the rig checkout when the step runs. Step text that names
# this script requires it to exist before it resolves the pack's scripts, and
# calls it to decline the work. Nothing here holds a molecule. The call goes to
# run-cancel.sh in its --step mode, which ends the run through gascity's run
# cancel and appends the reason to the step this session holds. The arguments
# and the exit codes are run-cancel.sh's --step mode, unchanged. Its --root,
# --ended and --db are refused here, so this name ends only the run of the step
# its caller holds.
#
# No formula, fragment or prompt names this script, and decline-wiring.test.sh
# holds them to that, so only a molecule carrying step text from an earlier
# version of its formula calls it. It goes once no open step bead names it.
#
# Callers: step text of mol-polecat-work, mol-validate and mol-rig-demo that
# names this script.
# exit: 0 the run is ended · 1 the run is not ended · 2 refused, nothing written
set -uo pipefail

PROG="molecule-hold"

# Resolved from $0 so a copy of this script runs against the copy beside it;
# overridable so a hermetic test can point it at a fixture.
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
RUN_CANCEL="${GC_RUN_CANCEL_TOOL:-$HERE/run-cancel.sh}"

usage() {
  cat >&2 <<'USAGE'
usage: molecule-hold.sh --step <formula.step-id> --reason "<text>" [--bead <id>] [--dry-run]

  The arguments of run-cancel.sh's --step mode, handed to it unchanged: the run
  of the step this session holds ends through gascity's run cancel.
USAGE
}

ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --step|--reason|--bead)
      if [ "$#" -lt 2 ]; then
        echo "$PROG: $1 requires a value" >&2
        usage
        exit 2
      fi
      ARGS+=("$1" "$2"); shift 2 ;;
    --dry-run) ARGS+=("$1"); shift ;;
    -h|--help) usage; exit 2 ;;
    *)         echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ ! -x "$RUN_CANCEL" ]; then
  echo "$PROG: run-cancel.sh is not executable at $RUN_CANCEL, so the run is not ended" >&2
  exit 1
fi
exec "$RUN_CANCEL" ${ARGS[@]+"${ARGS[@]}"}
