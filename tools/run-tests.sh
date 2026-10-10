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
#   -j, --jobs N       concurrent runs (default: $TEST_JOBS or half the cores)
#   -t, --timeout SECS per-run wall limit, 0 disables (default: $TEST_TIMEOUT or 900)
#       --retry N      serial re-runs for a run that failed in parallel
#                      (default: $TEST_RETRY or 1); --no-retry sets 0
#       --list         print what would run, one run per line, and exit
#   -q, --quiet        print only the summary and the failures
#
# With no PATH it runs every tracked *.test.sh. With PATHs it runs the affected
# subset, the tests a change to those paths can break:
#
#   - a *.test.sh runs itself, and a directory runs every *.test.sh beneath it;
#   - a script X.sh runs its sibling X.test.sh;
#   - a path runs every tracked *.test.sh that names it on a line that is not a
#     comment. The name is the path's basename, or, while another tracked file
#     ends in that, the basename with enough parent directories to tell them
#     apart;
#   - a path runs the sibling test of every tracked script that names it on a
#     line that is not a comment, because that script may run it in place;
#   - a tracked script that sources a path counts as changed along with it, so
#     every rule here applies to it in turn, and a library reaches every suite
#     of every script that sources it. A script sources a path when a `.` or
#     `source` command, or a `# shellcheck source=` directive, names it;
#   - every subset includes the tree-wide suites. A suite that scans the tree
#     can be broken by a file it never names, so it says so in its opening
#     comment block with the line
#
#       # run-tests-scope: tree
#
#     Any other scope is a usage error, in the full run as well.
#
# A test that reaches a file only through a path it builds at run time, or
# through a chain of scripts that run one another, is outside the subset, and
# only the full run covers it. `run-tests.sh $(git diff --name-only
# origin/main...HEAD)` runs the subset of a branch's change, and an empty
# subset is a clean pass rather than a failure.
#
# A file runs once, unless its opening comment block declares named parts:
#
#   # run-tests-parts: <part> [<part> ...]
#
# Such a file runs once per part, and each run has its own timeout, its own
# report line (FILE[PART]) and its own serial re-run, so a file whose sections
# together outlast one timeout stays one file. Each run gets
# RUN_TESTS_PART=<part> and RUN_TESTS_PARTS=<every declared part> in its
# environment, and the file executes only that part's sections (part() in
# assets/scripts/test-harness.sh). Run directly, with RUN_TESTS_PART unset, the
# file runs each part in order, each in a process of its own as here, and prints
# one tally summed over the parts (harness_run_parts in the same harness).
#
# Each file runs in its own process group with its output captured to a file,
# never a pipe. A file that leaves a background child behind (pr-facts.test.sh
# does) therefore cannot wedge the runner on a pipe that never reaches EOF, and
# the group is killed once the file's own process exits so the child cannot
# outlive the file that spawned it.
#
# The suite yields to whatever else the host runs, such as a city's agents and
# their bead calls. A file forks a stub for every gc and bd call it makes, so at
# one job per core a few suites running at once leave the rest of the host
# waiting for the CPU. The default is therefore half the cores, at least one.
# The count is the first one nproc, getconf or sysctl reports; stock macOS has
# no nproc. Every run of the parallel wave starts at a niceness 10 above the
# caller's, and at ionice's lowest best-effort level where ionice can set it;
# macOS has no ionice. A host with nothing else to serve, such as a CI runner,
# passes -j to use every core.
#
# Isolation still cannot stop a sibling from saturating the host, so a file can
# fail under -j for a reason that is not its own: an assertion reads a killed
# command's 143 where it expected a real exit. After the parallel wave each
# failed file is re-run serially, where no sibling competes with it. A file that
# then passes was a parallel-contention false failure and counts as a pass; only
# a file that fails serially too is a real failure. --no-retry (or --retry 0)
# reports the raw parallel result. A serial re-run keeps the caller's priority.
# It runs alone, so it cannot crowd the host, and a file the wave's lower
# priority slowed past its timeout is not slowed the same way again.
#
# Every file runs with commit and tag signing off, added after any
# GIT_CONFIG_COUNT entries the caller already exported. A test that commits
# does so in a throwaway repo, and on a host whose git config signs every
# commit each of those commits needs a reachable signing agent. No test may
# depend on one.
#
# Every file runs with TMPDIR set to the physical path of the caller's temp
# directory (/tmp when TMPDIR is unset), with no symlink in it and no trailing
# slash. A test builds the paths it expects from TMPDIR, while the scripts it
# tests print paths they resolve: `pwd` drops a doubled slash, `pwd -P` and git,
# which records a worktree by its physical path, resolve a symlink too. On macOS
# TMPDIR ends in a slash and sits under /var, a symlink to /private/var, so
# there a path built from it and the same path resolved compare unequal. A file
# run directly, outside the runner, gets the caller's TMPDIR as it is.
#
# Exit: 0 every file passed, or passed on a serial re-run, or the subset was
# empty; 1 one or more failed serially too; 2 a usage or enumeration error.

set -uo pipefail

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "run-tests: not inside a git repository ($HERE)" >&2; exit 2; }

# half_the_cores — the default job count (see the header). A count no tool
# reports leaves the floor of one.
half_the_cores() {
  local n
  n="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$(( 10#$n / 2 ))
  [ "$n" -ge 1 ] || n=1
  printf '%s\n' "$n"
}

JOBS="${TEST_JOBS:-$(half_the_cores)}"
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

# The tracked suites whose opening comment block declares a scope (see the
# header), one "<path>\t<scope>" line each. The block ends at the first line
# that is neither a comment nor blank, so a fixture further down that writes a
# declaration of its own is not read as the file's. A tracked suite missing
# from the work tree is passed over: an awk that cannot open one file may stop
# before reading the rest.
scopes() {
  local -a files=()
  local t
  while IFS= read -r -d '' t; do
    [ -f "$ROOT/$t" ] && files+=("$t")
  done < <(git -C "$ROOT" ls-files -z '*.test.sh')
  [ "${#files[@]}" -gt 0 ] || return 0
  ( cd "$ROOT" && awk '
    FNR == 1 { body = 0 }
    body { next }
    /^#/ {
      if (sub(/^#[[:space:]]*run-tests-scope:[[:space:]]*/, "")) {
        sub(/[[:space:]]+$/, ""); print FILENAME "\t" $0; body = 1
      }
      next
    }
    /^[[:space:]]*$/ { next }
    { body = 1 }' "${files[@]}" )
}

# A scope other than tree is refused, in the full run too, so a misspelled
# declaration fails loudly instead of leaving its suite out of every subset.
declare -a TREE_WIDE=()
while IFS=$'\t' read -r rel scope; do
  [ -n "$rel" ] || continue
  [ "$scope" = tree ] || { echo "run-tests: $rel declares an unknown scope '$scope' (the one scope is 'tree')" >&2; exit 2; }
  TREE_WIDE+=("$rel")
done < <(scopes)

# tidy <var> <path> — set var to the path without "./" segments, doubled
# slashes or a trailing slash, so a file named two ways is matched and counted
# as one, and no path ends in an empty name.
tidy() {
  local p="$2"
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  while [ "${p//\/.\//\/}" != "$p" ]; do p="${p//\/.\//\/}"; done
  while [ "${p//\/\//\/}" != "$p" ]; do p="${p//\/\//\/}"; done
  [ "$p" = / ] || p="${p%/}"
  printf -v "$1" '%s' "$p"
}

# ERE alternation of the given names, each escaped to match literally.
names_ere() { printf '%s\n' "$@" | sed 's/[][\.*^$+?(){}|]/\\&/g' | paste -sd'|' -; }

# name_of <path> — what a test calls the file: its basename, widened by one
# parent directory at a time while another tracked file still ends in it.
name_of() {
  local p="$1" name="${1##*/}" rest t clash
  rest="${p%"$name"}"
  while :; do
    clash=0
    while IFS= read -r t; do
      { [ -z "$t" ] || [ "$t" = "$p" ]; } && continue
      case "$t" in "$name"|*/"$name") clash=1; break ;; esac
    done <<<"${BY_BASE["${p##*/}"]:-}"
    { [ "$clash" -eq 1 ] && [ -n "${rest%/}" ]; } || break
    rest="${rest%/}"; name="${rest##*/}/$name"; rest="${rest%"${rest##*/}"}"
  done
  printf '%s\n' "$name"
}

# sourcers_of <name>... — the tracked scripts, tests aside, that source one of
# the named files: a `.` or `source` command naming it, or a `# shellcheck
# source=` directive naming it. The command counts where a command starts, at
# the head of a line or after `if`, `then`, `;`, `&&` and the like, so the word
# "source" inside a message is not one. Only a script sources anything; in a
# document, "source" is a word.
sourcers_of() {
  local re
  re="$(names_ere "$@")"
  {
    git -C "$ROOT" grep -IE --no-color \
      "(^[[:space:]]*|[;&|({][[:space:]]*|^[[:space:]]*(if|elif|then|else|do|while|until|!)[[:space:]]+)(\.|source)[[:space:]]+(.*[^A-Za-z0-9._-])?($re)(\$|[^A-Za-z0-9_-])" \
      -- '*.sh' ':!*.test.sh' | grep -vE '^[^:]*:[[:space:]]*#' | cut -d: -f1
    git -C "$ROOT" grep -lIE --no-color \
      "^[[:space:]]*#[[:space:]]*shellcheck[[:space:]].*source=([^[:space:]]*/)?($re)([[:space:]]|\$)" \
      -- '*.sh' ':!*.test.sh'
  } | sort -u
}

# naming <pathspec>... -- <name>... — the tracked files the pathspecs select
# that name one of the files on a line that is not a comment.
naming() {
  local -a spec=()
  local re
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do spec+=("$1"); shift; done
  shift
  re="$(names_ere "$@")"
  git -C "$ROOT" grep -IE --no-color \
    "(^|[^A-Za-z0-9._-])($re)(\$|[^A-Za-z0-9_-])" -- "${spec[@]}" \
    | grep -vE '^[^:]*:[[:space:]]*#' | cut -d: -f1 | sort -u
}

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
    local f
    tidy f "$1"
    case "$f" in *.test.sh) ;; *) return 0 ;; esac
    [ -f "$f" ] || return 0
    [ -n "${seen[$f]:-}" ] && return 0
    seen[$f]=1; TESTS+=("$f")
  }
  # The changed files, as paths from the root: every PATH that is not a
  # directory, whether or not it still exists, since a deleted file breaks the
  # tests that name it.
  declare -a CHANGED=()
  declare -A IN=()
  for a in "${ARGS[@]}"; do
    tidy a "$a"
    case "$a" in /*) abs="$a" ;; *) abs="$ROOT/$a" ;; esac
    if [ -d "$abs" ]; then
      while IFS= read -r f; do add "$f"; done < <(find "$abs" -type f -name '*.test.sh')
    else
      rel="${abs#"$ROOT"/}"
      [ -n "${IN[$rel]:-}" ] || { IN[$rel]=1; CHANGED+=("$rel"); }
    fi
  done

  declare -A BY_BASE=()
  while IFS= read -r -d '' t; do
    BY_BASE["${t##*/}"]+="$t"$'\n'
  done < <(git -C "$ROOT" ls-files -z)

  # Whatever sources a changed file is changed along with it, and so is
  # whatever sources that.
  declare -a NAMES=() frontier=("${CHANGED[@]}")
  while [ "${#frontier[@]}" -gt 0 ]; do
    declare -a names=()
    for p in "${frontier[@]}"; do names+=("$(name_of "$p")"); done
    NAMES+=("${names[@]}")
    frontier=()
    while IFS= read -r c; do
      { [ -n "$c" ] && [ -z "${IN[$c]:-}" ]; } || continue
      IN[$c]=1; CHANGED+=("$c"); frontier+=("$c")
    done < <(sourcers_of "${names[@]}")
  done

  for p in "${CHANGED[@]}"; do
    case "$p" in /*) abs="$p" ;; *) abs="$ROOT/$p" ;; esac
    case "$abs" in
      *.test.sh) add "$abs" ;;
      *.sh)      add "${abs%.sh}.test.sh" ;;   # script -> its sibling test
    esac
  done
  if [ "${#NAMES[@]}" -gt 0 ]; then
    while IFS= read -r t; do add "$ROOT/$t"; done < <(naming '*.test.sh' -- "${NAMES[@]}")
    # A script that names a changed file may run it in place, under its own suite.
    while IFS= read -r s; do
      add "$ROOT/${s%.sh}.test.sh"
    done < <(naming '*.sh' ':!*.test.sh' -- "${NAMES[@]}")
  fi
  for t in "${TREE_WIDE[@]}"; do add "$ROOT/$t"; done
fi

# Front-load likely-slow files. The slowest file bounds the wall time, so it
# must start in the first wave; bigger source is a coarse but free proxy for a
# slower file when no timing record exists. Files are sorted even when they fit
# in one wave, because a file with parts can fill a wave on its own.
if [ "${#TESTS[@]}" -gt 1 ]; then
  mapfile -t TESTS < <(
    for t in "${TESTS[@]}"; do printf '%s\t%s\n' "$(wc -c <"$t" 2>/dev/null || echo 0)" "$t"; done \
      | sort -rn | cut -f2-
  )
fi

# The parts a file declares in its opening comment block (see the header), or
# nothing. The block ends at the first line that is neither a comment nor blank,
# so a heredoc further down that writes a fixture with its own declaration is
# not read as this file's.
parts_of() {
  awk '/^#/ { if (sub(/^# run-tests-parts:[[:space:]]*/, "")) { print; exit } next }
       /^[[:space:]]*$/ { next }
       { exit }' "$1"
}

# One run per file, or one per declared part. Each run carries its file and
# its part ("" for a file without parts); everything below indexes runs.
declare -a RUN_FILE=() RUN_PART=()
declare -A DECLARED=()
for t in "${TESTS[@]}"; do
  read -ra names <<<"$(parts_of "$t")"
  if [ "${#names[@]}" -eq 0 ]; then
    RUN_FILE+=("$t"); RUN_PART+=(""); continue
  fi
  declare -A named=()
  for p in "${names[@]}"; do
    case "$p" in
      *[!A-Za-z0-9_-]*) echo "run-tests: ${t#"$ROOT"/} declares a malformed part name '$p'" >&2; exit 2 ;;
    esac
    [ -z "${named[$p]:-}" ] || { echo "run-tests: ${t#"$ROOT"/} declares part '$p' twice" >&2; exit 2; }
    named[$p]=1
    RUN_FILE+=("$t"); RUN_PART+=("$p")
  done
  unset named
  DECLARED[$t]="${names[*]}"
done

label() { # <run-index> -> the file's path from the repo root, with [part] for a part
  local rel="${RUN_FILE[$1]#"$ROOT"/}"
  [ -z "${RUN_PART[$1]}" ] || rel="${rel}[${RUN_PART[$1]}]"
  printf '%s' "$rel"
}

if [ "$LIST_ONLY" -eq 1 ]; then
  for i in "${!RUN_FILE[@]}"; do label "$i"; echo; done
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

# The physical temp directory every file runs with (see the header).
tmp_real="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)" || {
  echo "run-tests: cannot resolve the temp directory '${TMPDIR:-/tmp}'" >&2; exit 2; }
export TMPDIR="$tmp_real"

LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/run-tests.XXXXXX")" || { echo "run-tests: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$LOGDIR"' EXIT

total="${#RUN_FILE[@]}"
[ "$JOBS" -gt "$total" ] && JOBS="$total"
START="$SECONDS"
if [ "$QUIET" -eq 0 ]; then
  if [ "$total" -eq "${#TESTS[@]}" ]; then
    printf 'run-tests: %d files, %d parallel, timeout %ss\n' "$total" "$JOBS" "$TIMEOUT"
  else
    printf 'run-tests: %d files as %d runs, %d parallel, timeout %ss\n' "${#TESTS[@]}" "$total" "$JOBS" "$TIMEOUT"
  fi
fi

# Monitor mode places each background job in its own process group, so
# `kill -- -<leader-pid>` reaps a job's whole tree — including any child it
# leaked — without touching the runner's own group.
set -m

declare -A PID_IDX=() PID_START=()
PASS=0; FAIL=0
declare -a FAILED=()
done_n=0; next=0; inflight=0

# The command every run of the parallel wave starts through (see the header).
# ionice is tried once here, so a kernel or sandbox that refuses the class drops
# it instead of failing every run.
declare -a LOW_PRIORITY=(nice -n 10)
if ionice -c 2 -n 7 true >/dev/null 2>&1; then
  LOW_PRIORITY+=(ionice -c 2 -n 7)
fi

# Start one run in the background, under the timeout, its output to its log. A
# part's run is told which part it is and which parts its file declares; a run
# of a whole file gets neither, whatever the caller exported. Any words after
# the index are a command the run starts through, such as LOW_PRIORITY.
spawn() { # <run-index> [<command>...]
  local t="${RUN_FILE[$1]}" part="${RUN_PART[$1]}" log="$LOGDIR/$1.log"
  shift
  (
    cd "$ROOT" || exit 2
    if [ -n "$part" ]; then
      export RUN_TESTS_PART="$part" RUN_TESTS_PARTS="${DECLARED[$t]}"
    else
      unset RUN_TESTS_PART RUN_TESTS_PARTS
    fi
    if [ "$TIMEOUT" -gt 0 ]; then
      exec "$@" timeout -k 5 -s TERM "$TIMEOUT" bash "$t"
    else
      exec "$@" bash "$t"
    fi
  ) >"$log" 2>&1 &
}

launch() {
  local idx="$1" pid
  spawn "$idx" "${LOW_PRIORITY[@]}"
  pid=$!
  PID_IDX[$pid]="$idx"; PID_START[$pid]="$SECONDS"
}

finish() {
  local pid="$1" rc="$2" idx dur rel status
  idx="${PID_IDX[$pid]}"
  kill -- -"$pid" 2>/dev/null   # reap anything the file left running in its group
  dur=$(( SECONDS - PID_START[$pid] ))
  rel="$(label "$idx")"
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

# Re-run one run serially (no sibling jobs) at the caller's priority, reusing
# the same timeout and process-group reap as the parallel path. Used after the
# parallel wave to tell a parallel-contention false failure from a real one.
rerun_serial() {
  local idx="$1" pid rc
  spawn "$idx"
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
    rel="$(label "$idx")"
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
    rel="$(label "$idx")"
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
