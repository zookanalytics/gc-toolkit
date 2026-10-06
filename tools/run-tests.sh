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
#   run-tests.sh [-j N] [-t SECS] [--retry N|--no-retry] [--list] [-q] [PATH ...]
#
#   -j, --jobs N       concurrent files (default: $TEST_JOBS or nproc)
#   -t, --timeout SECS per-file wall limit, 0 disables (default: $TEST_TIMEOUT or 900)
#       --retry N      serial re-runs for a file that failed in parallel
#                      (default: $TEST_RETRY or 1); --no-retry sets 0
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
# Isolation still cannot stop a sibling from saturating the host, so a file can
# fail under -j for a reason that is not its own: an assertion reads a killed
# command's 143 where it expected a real exit. After the parallel wave each
# failed file is re-run serially, where no sibling competes with it. A file that
# then passes was a parallel-contention false failure and counts as a pass; only
# a file that fails serially too is a real failure. --no-retry (or --retry 0)
# reports the raw parallel result.
#
# Every file runs with commit and tag signing off, added after any
# GIT_CONFIG_COUNT entries the caller already exported. A test that commits
# does so in a throwaway repo, and on a host whose git config signs every
# commit each of those commits needs a reachable signing agent. No test may
# depend on one.
#
# Exit: 0 every file passed, or passed on a serial re-run, or the subset was
# empty; 1 one or more failed serially too; 2 a usage or enumeration error.

set -uo pipefail

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "run-tests: not inside a git repository ($HERE)" >&2; exit 2; }

JOBS="${TEST_JOBS:-$(nproc 2>/dev/null || echo 4)}"
TIMEOUT="${TEST_TIMEOUT:-900}"
RETRY="${TEST_RETRY:-1}"
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
    --retry)       RETRY="${2:-}"; shift 2 ;;
    --retry=*)     RETRY="${1#--retry=}"; shift ;;
    --no-retry)    RETRY=0; shift ;;
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
case "$RETRY" in ''|*[!0-9]*) echo "run-tests: --retry must be a non-negative integer (0 disables)" >&2; exit 2 ;; esac
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

# Signing off for every file (see the header). The entries go after the
# caller's own, so a GIT_CONFIG_COUNT the caller exported still applies. A count
# that is not a number is replaced, since git refuses to run with it.
case "${GIT_CONFIG_COUNT:-}" in
  ''|*[!0-9]*) cfg_n=0 ;;
  *)           cfg_n=$((10#$GIT_CONFIG_COUNT)) ;;
esac
export "GIT_CONFIG_KEY_$cfg_n=commit.gpgsign" "GIT_CONFIG_VALUE_$cfg_n=false" \
       "GIT_CONFIG_KEY_$((cfg_n + 1))=tag.gpgsign" "GIT_CONFIG_VALUE_$((cfg_n + 1))=false" \
       "GIT_CONFIG_COUNT=$((cfg_n + 2))"

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

# Re-run one file serially (no sibling jobs), reusing the same timeout and
# process-group reap as the parallel path. Used after the parallel wave to tell
# a parallel-contention false failure from a real one.
rerun_serial() {
  local idx="$1" t="${TESTS[$idx]}" log="$LOGDIR/$idx.log" pid rc
  if [ "$TIMEOUT" -gt 0 ]; then
    ( cd "$ROOT" && exec timeout -k 5 -s TERM "$TIMEOUT" bash "$t" ) >"$log" 2>&1 &
  else
    ( cd "$ROOT" && exec bash "$t" ) >"$log" 2>&1 &
  fi
  pid=$!
  wait "$pid"; rc=$?
  kill -- -"$pid" 2>/dev/null   # reap anything the file left in its group
  return "$rc"
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
  elif [ "$rc" -eq 127 ]; then
    # wait -n reports no child though a job is in flight — a job that failed to
    # fork. Fail closed and stop rather than spin waiting for one that will
    # never arrive.
    echo "run-tests: $inflight in-flight job(s) unaccountable (failed fork?); failing closed" >&2
    FAIL=$((FAIL + inflight)); done_n=$((done_n + inflight)); inflight=0
  fi
done

# A file that failed under -j may be a parallel-contention false failure rather
# than a defect: a sibling saturated the host, or a cross-group signal killed a
# command it spawned, so an assertion read a 143 where it expected a real exit.
# Re-run each failed file serially, where nothing competes with it. One that
# passes alone is reclassified a pass; one that fails alone too is real, and its
# serial log overwrites the parallel one as the authority the report prints.
RECOVERED=0
if [ "$RETRY" -gt 0 ] && [ "${#FAILED[@]}" -gt 0 ]; then
  [ "$QUIET" -eq 0 ] && printf '\nrun-tests: %d failed under -j%s; re-running serially to rule out parallel contention\n' "${#FAILED[@]}" "$JOBS"
  declare -a STILL_FAILED=()
  for idx in "${FAILED[@]}"; do
    rel="${TESTS[$idx]#"$ROOT"/}"
    attempt=0; rc=1
    while [ "$attempt" -lt "$RETRY" ]; do
      attempt=$((attempt + 1))
      rerun_serial "$idx"; rc=$?
      [ "$rc" -eq 0 ] && break
    done
    if [ "$rc" -eq 0 ]; then
      RECOVERED=$((RECOVERED + 1)); PASS=$((PASS + 1)); FAIL=$((FAIL - 1))
      [ "$QUIET" -eq 0 ] && printf '  %-10s %s (recovered serially after %d attempt(s))\n' "RETRY-OK" "$rel" "$attempt"
    else
      STILL_FAILED+=("$idx")
      if [ "$rc" -eq 124 ]; then status="TIMEOUT"; else status="FAIL[$rc]"; fi
      printf '  %-10s %s (failed serially too)\n' "$status" "$rel"
    fi
  done
  FAILED=()
  [ "${#STILL_FAILED[@]}" -gt 0 ] && FAILED=("${STILL_FAILED[@]}")
fi

if [ "$FAIL" -gt 0 ]; then
  printf '\n===== %d failed =====\n' "$FAIL"
  for idx in "${FAILED[@]}"; do
    rel="${TESTS[$idx]#"$ROOT"/}"
    log="$LOGDIR/$idx.log"
    printf '\n----- %s -----\n' "$rel"
    lines=$(wc -l <"$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 200 ]; then
      # A failing assertion can sit anywhere in a long log, so surface the
      # framework's FAIL markers before the tail — a plain tail of an "ok"-heavy
      # file hides the one line that matters.
      printf '(%s lines; failing markers, then tail)\n' "$lines"
      grep -nE 'FAIL|not ok|✗' "$log" | head -40
      printf '  --- tail ---\n'
      tail -n 25 "$log"
    else
      cat "$log"
    fi
  done
fi

if [ "$RECOVERED" -gt 0 ]; then
  printf '\nrun-tests: %d passed (%d recovered on serial re-run), %d failed, %d total in %ds\n' "$PASS" "$RECOVERED" "$FAIL" "$total" "$((SECONDS - START))"
else
  printf '\nrun-tests: %d passed, %d failed, %d total in %ds\n' "$PASS" "$FAIL" "$total" "$((SECONDS - START))"
fi
[ "$FAIL" -eq 0 ]
