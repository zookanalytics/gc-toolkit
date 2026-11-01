#!/usr/bin/env bash
# rig-checks — run a rig's declared checks through `gctk rig` for one of
# mol-polecat-work's steps. setup and preflight run in the current directory, and
# self-review in the tree its work bead records.
#
#   rig-checks.sh setup <<'CHECKS'
#   setup=<command>
#   CHECKS
#   rig-checks.sh preflight <<'CHECKS'
#   typecheck=<command>
#   lint=<command>
#   test=<command>
#   CHECKS
#   rig-checks.sh self-review --bead <work-bead> <<'CHECKS'
#   setup=<command>
#   typecheck=<command>
#   lint=<command>
#   build=<command>
#   affected=<command>
#   test=<command>
#   CHECKS
#
# The step renders each command into a quoted here-document, which hands it over
# verbatim whatever quotes it carries, one line per check. `gctk rig` records each
# result against the commit it ran at, so a run already recorded there answers
# from its record and every polecat starting from one base shares one run.
#
# preflight and setup run what the rig declares and skip the rest. self-review
# publishes test, lint and typecheck to the work bead's rig_check.<check>, with a
# check the rig declares no command for recording a pass that ran nothing. setup
# and build record nothing, so on a clean tree their outcome at HEAD goes on the
# work bead as self_review_setup_build, which self-review-check.sh reads. Its test
# run is the affected subset when the rig declares one, else the full suite.
#
# Every declared check runs whatever the one before it answered, so the caller
# sees all of them at once.
#
# A shell that did not keep its directory starts in the session's home, and a pass
# recorded at that commit is no pass at the work's HEAD. So self-review enters the
# tree first, and a tree it cannot name runs nothing.
#
# exit: 0 every check passed · 1 a check failed · 4 a check could not say, which
# `gctk rig`'s line explains, and which outranks a fail, or self-review could not
# name its tree · 2 usage
set -uo pipefail

PROG="rig-checks"

usage() {
  cat >&2 <<'USAGE'
usage: rig-checks.sh setup|preflight <<'CHECKS'
       rig-checks.sh self-review --bead <work-bead> <<'CHECKS'
       <check>=<command>, one per line, on stdin
       CHECKS

exit: 0 every check passed · 1 a check failed · 4 a check could not say, or
      self-review could not name its tree · 2 usage
USAGE
}

MODE="${1:-}"
[ "$#" -eq 0 ] || shift
BEAD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead)
      [ "$#" -ge 2 ] || { echo "$PROG: --bead requires a value" >&2; usage; exit 2; }
      BEAD="$2"; shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
case "$MODE" in
  setup|preflight)
    [ -z "$BEAD" ] || { echo "$PROG: $MODE publishes nothing, so it takes no --bead" >&2; usage; exit 2; } ;;
  self-review)
    [ -n "$BEAD" ] || { echo "$PROG: self-review publishes to a work bead, so --bead is required" >&2; usage; exit 2; } ;;
  *) echo "$PROG: unknown mode '$MODE'" >&2; usage; exit 2 ;;
esac

SETUP_CMD=""; TYPECHECK_CMD=""; LINT_CMD=""; BUILD_CMD=""; AFFECTED_CMD=""; TEST_CMD=""
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  case "$line" in
    setup=*)     SETUP_CMD="${line#setup=}" ;;
    typecheck=*) TYPECHECK_CMD="${line#typecheck=}" ;;
    lint=*)      LINT_CMD="${line#lint=}" ;;
    build=*)     BUILD_CMD="${line#build=}" ;;
    affected=*)  AFFECTED_CMD="${line#affected=}" ;;
    test=*)      TEST_CMD="${line#test=}" ;;
    *) echo "$PROG: a line on stdin names no check: $line. A rig's command fits on one line." >&2; exit 2 ;;
  esac
done

# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=work-lib.sh
. "$SCRIPT_DIR/work-lib.sh"

enter_work_tree() {
  local dir
  work_read "$BEAD" || { echo "$PROG: could not read $BEAD, so the tree its checks run in is unknown, and no check ran" >&2; exit 4; }
  dir=$(work_meta work_dir)
  if [ -z "$dir" ] || ! cd "$dir" 2>/dev/null; then
    echo "$PROG: the work_dir $BEAD records is missing (${dir:-none recorded}), and no check ran" >&2
    exit 4
  fi
}

WORST=0
tally() { # <the exit a check answered>
  case "$1" in
    0) ;;
    4) WORST=4 ;;
    *) [ "$WORST" = 4 ] || WORST=1 ;;
  esac
}
check() { # <gctk rig args...>
  "$GCTK" rig "$@"
  tally $?
}

case "$MODE" in
  setup)
    [ -z "$SETUP_CMD" ] || check setup --command "$SETUP_CMD" ;;
  preflight)
    [ -z "$TYPECHECK_CMD" ] || check typecheck --command "$TYPECHECK_CMD"
    [ -z "$LINT_CMD" ] || check lint --command "$LINT_CMD"
    [ -z "$TEST_CMD" ] || check test --scope full --command "$TEST_CMD" ;;
  self-review)
    enter_work_tree
    PUB=(--publish-bead "$BEAD")
    SETUP=none
    if [ -n "$SETUP_CMD" ]; then
      if "$GCTK" rig setup --command "$SETUP_CMD"; then SETUP=pass; else SETUP=fail; tally 1; fi
    fi
    if [ -n "$TYPECHECK_CMD" ]; then check typecheck --command "$TYPECHECK_CMD" "${PUB[@]}"; else check typecheck --nothing-declared "${PUB[@]}"; fi
    if [ -n "$LINT_CMD" ]; then check lint --command "$LINT_CMD" "${PUB[@]}"; else check lint --nothing-declared "${PUB[@]}"; fi
    BUILD=none
    if [ -n "$BUILD_CMD" ]; then
      if "$GCTK" rig build --command "$BUILD_CMD"; then BUILD=pass; else BUILD=fail; tally 1; fi
    fi
    if [ -z "$(git status --porcelain)" ]; then
      gc bd update "$BEAD" --set-metadata "self_review_setup_build=$(jq -nc --arg c "$(git rev-parse HEAD)" --arg s "$SETUP" --arg b "$BUILD" --arg sc "$SETUP_CMD" --arg bc "$BUILD_CMD" '{commit: $c, setup: $s, build: $b, setup_command: $sc, build_command: $bc}')" </dev/null >/dev/null \
        || { echo "$PROG: the setup and build note did not land on $BEAD" >&2; tally 1; }
    fi
    if [ -n "$AFFECTED_CMD" ]; then check test --scope affected --command "$AFFECTED_CMD" "${PUB[@]}"
    elif [ -n "$TEST_CMD" ]; then check test --scope full --command "$TEST_CMD" "${PUB[@]}"
    else check test --nothing-declared "${PUB[@]}"; fi ;;
esac
exit "$WORST"
