#!/usr/bin/env bash
# run-tests.sh — run the pack's *.test.sh suite in parallel and aggregate the
# result into a single exit code.
#
# The suite is ~100 hermetic *.test.sh files: each self-locates its script under
# test, stubs gc/bd, works in its own mktemp dir, and exits nonzero when any
# assertion fails. Run one at a time the suite is ~25 minutes; run concurrently
# it costs about the slowest single file. That is the difference between a suite
# a gate can afford to run and one it cannot.
#
# Usage:
#   run-tests.sh [-j N] [-t SECS] [--list] [-q] [PATH ...]
#
#   -j, --jobs N       concurrent files (default: $TEST_JOBS or nproc)
#   -t, --timeout SECS per-file wall limit, 0 disables (default: $TEST_TIMEOUT or 900)
#       --list         print the files that would run, one per line, and exit
#   -q, --quiet        print only the summary and the failures
#
# With no PATH it runs every tracked *.test.sh. With PATHs it runs the affected
# subset: a *.test.sh runs directly, a script X.sh maps to its sibling
# X.test.sh, a directory expands to the *.test.sh beneath it, and a path with no
# sibling test is skipped. So `run-tests.sh $(git diff --name-only
# origin/main...HEAD)` runs exactly the tests the change can reach, and an
# empty subset is a clean pass rather than a failure.
#
# Each file runs in its own process group with its output captured to a file,
# never a pipe. A file that leaves a background child behind (pr-facts.test.sh
# does) therefore cannot wedge the runner on a pipe that never reaches EOF, and
# the group is killed once the file's own process exits so the child cannot
# outlive the file that spawned it.
#
# Exit: 0 every file passed (or the subset was empty); 1 one or more failed or
# timed out; 2 a usage or enumeration error.

set -uo pipefail

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "run-tests: not inside a git repository ($HERE)" >&2; exit 2; }

JOBS="${TEST_JOBS:-$(nproc 2>/dev/null || echo 4)}"
TIMEOUT="${TEST_TIMEOUT:-900}"
LIST_ONLY=0
QUIET=0
declare -a ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -j|--jobs)     JOBS="${2:-}"; shift 2 ;;
    -j*)           JOBS="${1#-j}"; shift ;;
    --jobs=*)      JOBS="${1#--jobs=}"; shift ;;
    -t|--timeout)  TIMEOUT="${2:-}"; shift 2 ;;
    -t*)           TIMEOUT="${1#-t}"; shift ;;
    --timeout=*)   TIMEOUT="${1#--timeout=}"; shift ;;
    --list)        LIST_ONLY=1; shift ;;
    -q|--quiet)    QUIET=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; while [ $# -gt 0 ]; do ARGS+=("$1"); shift; done ;;
    -*)            echo "run-tests: unknown option '$1'" >&2; exit 2 ;;
    *)             ARGS+=("$1"); shift ;;
  esac
done

case "$JOBS" in ''|*[!0-9]*) echo "run-tests: --jobs must be a positive integer" >&2; exit 2 ;; esac
case "$TIMEOUT" in ''|*[!0-9]*) echo "run-tests: --timeout must be a non-negative integer (0 disables)" >&2; exit 2 ;; esac
[ "$JOBS" -ge 1 ] || JOBS=1

# Resolve the set of *.test.sh files to run.
declare -a TESTS=()
if [ "${#ARGS[@]}" -eq 0 ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] && TESTS+=("$ROOT/$rel")
  done < <(git -C "$ROOT" ls-files '*.test.sh')
  if [ "${#TESTS[@]}" -eq 0 ]; then
    echo "run-tests: no *.test.sh tracked under $ROOT" >&2; exit 2
  fi
else
  declare -A seen=()
  add() {
    local f="$1"
    case "$f" in *.test.sh) ;; *) return 0 ;; esac
    [ -f "$f" ] || return 0
    [ -n "${seen[$f]:-}" ] && return 0
    seen[$f]=1; TESTS+=("$f")
  }
  for a in "${ARGS[@]}"; do
    case "$a" in /*) abs="$a" ;; *) abs="$ROOT/$a" ;; esac
    if [ -d "$abs" ]; then
      while IFS= read -r f; do add "$f"; done < <(find "$abs" -type f -name '*.test.sh')
    else
      case "$abs" in
        *.test.sh) add "$abs" ;;
        *.sh)      add "${abs%.sh}.test.sh" ;;   # script -> its sibling test
      esac
    fi
  done
fi

# Front-load likely-slow files. The slowest file bounds the wall time, so it
# must start in the first wave; bigger source is a coarse but free proxy for a
# slower file when no timing record exists.
if [ "${#TESTS[@]}" -gt "$JOBS" ]; then
  mapfile -t TESTS < <(
    for t in "${TESTS[@]}"; do printf '%s\t%s\n' "$(wc -c <"$t" 2>/dev/null || echo 0)" "$t"; done \
      | sort -rn | cut -f2-
  )
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  for t in "${TESTS[@]}"; do echo "${t#"$ROOT"/}"; done
  exit 0
fi

if [ "${#TESTS[@]}" -eq 0 ]; then
  echo "run-tests: no matching *.test.sh for the given paths — nothing to run"
  exit 0
fi

LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/run-tests.XXXXXX")" || { echo "run-tests: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$LOGDIR"' EXIT

total="${#TESTS[@]}"
[ "$JOBS" -gt "$total" ] && JOBS="$total"
START="$SECONDS"
[ "$QUIET" -eq 0 ] && printf 'run-tests: %d files, %d parallel, timeout %ss\n' "$total" "$JOBS" "$TIMEOUT"

# Monitor mode places each background job in its own process group, so
# `kill -- -<leader-pid>` reaps a job's whole tree — including any child it
# leaked — without touching the runner's own group.
set -m

declare -A PID_IDX=() PID_START=()
PASS=0; FAIL=0
declare -a FAILED=()
done_n=0; next=0; inflight=0

launch() {
  local idx="$1" t="${TESTS[$1]}" log="$LOGDIR/$1.log" pid
  if [ "$TIMEOUT" -gt 0 ]; then
    ( cd "$ROOT" && exec timeout -k 5 -s TERM "$TIMEOUT" bash "$t" ) >"$log" 2>&1 &
  else
    ( cd "$ROOT" && exec bash "$t" ) >"$log" 2>&1 &
  fi
  pid=$!
  PID_IDX[$pid]="$idx"; PID_START[$pid]="$SECONDS"
}

finish() {
  local pid="$1" rc="$2" idx dur rel status
  idx="${PID_IDX[$pid]}"
  kill -- -"$pid" 2>/dev/null   # reap anything the file left running in its group
  dur=$(( SECONDS - PID_START[$pid] ))
  rel="${TESTS[$idx]#"$ROOT"/}"
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1)); status="PASS"
  else
    FAIL=$((FAIL + 1)); FAILED+=("$idx")
    if [ "$rc" -eq 124 ]; then status="TIMEOUT"; else status="FAIL[$rc]"; fi
  fi
  if [ "$QUIET" -eq 0 ] || [ "$rc" -ne 0 ]; then
    printf '  %-10s %s (%ds)\n' "$status" "$rel" "$dur"
  fi
  unset 'PID_IDX[$pid]' 'PID_START[$pid]'
}

while [ "$done_n" -lt "$total" ]; do
  while [ "$inflight" -lt "$JOBS" ] && [ "$next" -lt "$total" ]; do
    launch "$next"; next=$((next + 1)); inflight=$((inflight + 1))
  done
  rpid=""
  wait -n -p rpid; rc=$?
  if [ -n "$rpid" ] && [ -n "${PID_IDX[$rpid]:-}" ]; then
    finish "$rpid" "$rc"
    inflight=$((inflight - 1)); done_n=$((done_n + 1))
  fi
done

if [ "$FAIL" -gt 0 ]; then
  printf '\n===== %d failed =====\n' "$FAIL"
  for idx in "${FAILED[@]}"; do
    rel="${TESTS[$idx]#"$ROOT"/}"
    printf '\n----- %s -----\n' "$rel"
    lines=$(wc -l <"$LOGDIR/$idx.log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 200 ]; then
      printf '(showing last 200 of %s lines)\n' "$lines"
      tail -n 200 "$LOGDIR/$idx.log"
    else
      cat "$LOGDIR/$idx.log"
    fi
  done
fi

printf '\nrun-tests: %d passed, %d failed, %d total in %ds\n' "$PASS" "$FAIL" "$total" "$((SECONDS - START))"
[ "$FAIL" -eq 0 ]
