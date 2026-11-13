#!/usr/bin/env bash
# refinery-gate.sh — the refinery patrol's run-tests step: run the rig's checks
# on the prepared head as one detached job, and wait for it.
#
#   refinery-gate.sh start --bead <id> [--add <check> <command>]...
#   refinery-gate.sh wait
#
# A tool call is cut off at ten minutes, and a rig's gate can run longer, so
# the checks run as one detached job (detached-job.sh) whose record is the
# rig's <git common dir>/gc-refinery-gate, and `wait` waits for it in bounded
# foreground calls.
#
# start runs the checks in the refinery's tree for the bead, which must hold
# the bead's branch (refinery-lib.sh). It first stops a gate a previous session
# left running, since that gate reads the checks this call rewrites, and one
# that will not stop leaves everything as it is. The checks are the rig's
# setup_command, typecheck_command, lint_command and build_command, then
# test_command when run_tests is "true". A rig sets them under its
# [rigs.formula_vars], and the rig's value wins over the formula's default, an
# empty one included. The patrol is poured root-only, so nothing renders those
# vars into a step, and this call reads both from one
# `gc formula show mol-refinery-patrol --rig $GC_RIG --json`, so every session
# runs the same checks. --add gives a check for a rig that sets none, as its
# CLAUDE.md documents it: it runs only for such a rig, and a gate with no check
# never starts.
#
# Each check runs through `gctk rig`, with bash, in the tree, with stdin
# closed, and test, lint and typecheck are recorded against the prepared head;
# a run already recorded there answers from its record. A check's verdict is
# its command's exit status, and the checks after a failed one still run. Every
# check ends inside the two hours the wait allows. The job's log ends
# `GATE PASSED`, `GATE FAILED: <check:rc>...` or `GATE CUT SHORT: <check:rc>...`
# for a check that stopped short of a verdict. Its first line,
# `GATE AT <head>`, names the commit the checks ran at, and a start clears the
# failures refinery-pre-existing.sh tracked against the gate before it
# (refinery-lib.sh's refinery_gate_verdict reads both).
#
# wait blocks for up to about eight minutes and reports the job's state as
# detached-job.sh does, stopping a gate that has run two hours. Every stop gives
# gctk longer than the ten seconds it takes to stop a check's command.
#
# Exit, start: 0 the gate started · 1 nothing started, and the work stays with
#   the refinery to retry · 2 usage · 5 the rig sets no check commands: add the
#   quality gates its CLAUDE.md documents with --add and run start again
# Exit, wait: detached-job.sh wait's: 0 the gate finished and passed · 1 it
#   finished otherwise, stopped short, or the wait could not run, which the
#   report's state= and rc= tell apart · 3 still running: wait again
set -uo pipefail

PROG="refinery-gate"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=gctk-resolve.sh
. "$HERE/gctk-resolve.sh" || { echo "$PROG: cannot source gctk-resolve.sh beside this script" >&2; exit 1; }

JOB="$HERE/detached-job.sh"
usage() { echo "usage: $PROG start --bead <id> [--add <check> <command>]... | $PROG wait" >&2; exit 2; }
VERB="${1:-}"; [ $# -gt 0 ] && shift
stop() { echo "$PROG: $1; no gate started, and the work stays with the refinery to retry" >&2; exit 1; }

case "$VERB" in
  wait)
    [ $# -eq 0 ] || usage
    HOME_DIR=$(refinery_home) || { echo "$PROG: the refinery's own worktree is unknown, so the gate cannot be found; it keeps running" >&2; exit 1; }
    GATE=$(refinery_gate_dir "$HOME_DIR") || { echo "$PROG: no repository at $HOME_DIR; the gate keeps running" >&2; exit 1; }
    DETACHED_JOB_STOP_GRACE=20 exec "$JOB" wait "$GATE" --limit 7200 ;;
  start) ;;
  -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) usage ;;
esac

BEAD=""; ADDED=()
while [ $# -gt 0 ]; do
  case "$1" in
    --bead) [ "$#" -ge 2 ] || usage; BEAD="$2"; shift 2 ;;
    --add)
      [ "$#" -ge 3 ] || usage
      case "$2" in setup|typecheck|lint|build|test) ;; *) echo "$PROG: --add takes setup, typecheck, lint, build or test, not '$2'" >&2; usage ;; esac
      ADDED+=("$2" "$3"); shift 3 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$BEAD" ] || usage

HOME_DIR=$(refinery_home) || stop "the refinery's own worktree is unknown"
refinery_bead "$BEAD" || stop "$BEAD did not read"
refinery_require "$HOME_DIR" "$BEAD" "$(bead_meta branch)" || stop "this iteration did not prepare $BEAD"
GATE=$(refinery_gate_dir "$HOME_DIR") || stop "no repository at $HOME_DIR"
gctk=$(gctk_path) || stop "no gctk binary to run the checks through"

if ! OUT=$(DETACHED_JOB_STOP_GRACE=20 "$JOB" stop "$GATE" 2>&1); then
  printf '%s\n' "$OUT" >&2
  stop "the gate a previous session left running in $GATE did not stop, so its checks are not rewritten under it"
fi
mkdir -p "$GATE/checks" || stop "cannot make $GATE/checks"
for OLD in "$GATE"/checks/* "$GATE/tracked"; do
  [ -e "$OLD" ] || continue
  rm -f "$OLD" || stop "cannot clear $OLD"
done

# One read serves every check. An unreadable answer would look like a rig with
# no checks, so it runs nothing.
refinery_formula_vars || stop "the rig's check commands did not read"
CHECKS=0
add_check() { # <check> <command>
  CHECKS=$((CHECKS + 1))
  printf '%s' "$2" > "$GATE/checks/$(printf '%02d' "$CHECKS")-$1" || stop "cannot write the $1 check into $GATE/checks"
  echo "$PROG: ${1}_command = $2"
}
RUN_TESTS=$(refinery_formula_var run_tests)
for CHECK in setup typecheck lint build test; do
  if [ "$CHECK" = test ] && [ "$RUN_TESTS" != true ]; then
    echo "$PROG: test_command skipped (run_tests=${RUN_TESTS})"
    continue
  fi
  CMD=$(refinery_formula_var "${CHECK}_command")
  [ -n "$CMD" ] || continue
  add_check "$CHECK" "$CMD"
done
if [ "$CHECKS" -eq 0 ]; then
  if [ "${#ADDED[@]}" -eq 0 ]; then
    echo "$PROG: rig $GC_RIG sets no check commands, so no gate started; give the quality gates its CLAUDE.md documents with --add <check> '<command>' and run start again" >&2
    exit 5
  fi
  i=0
  while [ "$i" -lt "${#ADDED[@]}" ]; do
    add_check "${ADDED[$i]}" "${ADDED[$((i + 1))]}"
    i=$((i + 2))
  done
elif [ "${#ADDED[@]}" -gt 0 ]; then
  echo "$PROG: rig $GC_RIG sets its own check commands, so the --add checks do not run"
fi

cat > "$GATE/gate.sh" <<'GATE' || stop "cannot write $GATE/gate.sh"
cd "$1" || exit 2
gctk="$3"
echo "GATE AT $(git rev-parse --verify -q HEAD)"
# Every check ends this many seconds into the gate, inside the two hours its
# wait allows, so the wait never stops gctk in the middle of a stop of its own.
deadline=7080
failed=""
stopped=""
# check <check>: run the command on stdin through gctk rig and note its exit
# when it is not a pass: 1 a fail, any other a run that says nothing about the
# code.
check() {
  local cmd rc left
  cmd=$(cat)
  echo "== $1"
  left=$((deadline - SECONDS))
  if [ "$left" -lt 60 ]; then
    echo "no time left in the gate's bound to run $1"
    stopped="$stopped $1:timeout"
    return
  fi
  if [ "$1" = test ]; then
    "$gctk" rig test --scope full --command "$cmd" --timeout "${left}s" </dev/null
  else
    "$gctk" rig "$1" --command "$cmd" --timeout "${left}s" </dev/null
  fi
  rc=$?
  case "$rc" in
    0) ;;
    1) failed="$failed $1:1" ;;
    *) stopped="$stopped $1:$rc" ;;
  esac
}
for f in "$2"/*; do
  [ -f "$f" ] || continue
  name=${f##*/}
  check "${name#*-}" < "$f"
done
[ -z "$stopped" ] || { echo "GATE CUT SHORT:$stopped${failed:+ (failed:$failed)}"; exit 4; }
[ -z "$failed" ] || { echo "GATE FAILED:$failed"; exit 1; }
echo "GATE PASSED"
GATE
"$JOB" start "$GATE" -- bash "$GATE/gate.sh" "$PREP_TREE" "$GATE/checks" "$gctk" || stop "the gate did not start"
echo "$PROG: the gate for $BEAD runs in $PREP_TREE; wait for it with: $PROG wait"
