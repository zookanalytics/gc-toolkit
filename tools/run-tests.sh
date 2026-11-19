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
#   run-tests.sh [-j N] [-t SECS] [--retry N|--no-retry] [--list] [-q]
#                [--seconds FILE] [--affected BASE | PATH ...]
#
#   -j, --jobs N       concurrent runs (default: $TEST_JOBS or half the cores)
#   -t, --timeout SECS end a run that writes nothing for SECS (below), 0 disables
#                      (default: $TEST_TIMEOUT or 900)
#       --retry N      serial re-runs for a run that failed in parallel
#                      (default: $TEST_RETRY or 1); --no-retry sets 0
#       --affected BASE
#                      run the subset of the change HEAD's commits make since
#                      BASE (below), for example --affected origin/main
#       --list         print what would run, one run per line, and exit
#   -q, --quiet        print only the summary and the failures
#       --seconds FILE write each run's seconds to FILE (below)
#
# With neither PATH nor --affected it runs every tracked *.test.sh. With PATHs
# it runs the affected subset, the tests a change to those paths can break:
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
#   - a path a Go program is compiled from runs the suites that compile the
#     program. A program is a main package of the repository's Go module that
#     a tracked script compiles, on a line outside a comment that runs
#     `go build` or `go run` on a ./<package> argument, which names the package
#     by the end of its path. It is compiled from go.mod and go.sum and, for
#     each package of the module it imports, its own included, from the files
#     in the package's directory, and below it when the package embeds files,
#     but the _test.go files. An embed pattern can match only files there, and
#     go's list of the files a package embeds cannot name one the change
#     deleted. A ./<package> the module no longer holds as a main
#     package, as when the change deletes or moves the whole package, is
#     reached by a changed path in a directory the argument names, by the end
#     of its path. A program go marks incomplete, because it or a package it
#     imports has an error, as when the change deletes a package the program
#     imports or every file one of their embed patterns matches, is reached by
#     any changed path, since go's list then cannot say what the program is
#     compiled from. A suite that compiles a reached program runs. Another
#     script that compiles one counts as changed, so every rule here applies
#     to it in turn, unless it compiles the program inside a function: then
#     the function's name, and the name of each function of the same script
#     that calls it in turn, are named as a changed file's name is, so the
#     suites that call them run. harness_init in assets/scripts/test-harness.sh
#     is such a caller, of the function that builds the fake gc. When go
#     cannot list the module's packages, a changed .go file, go.mod or go.sum
#     reaches every program;
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
# only the full run covers it.
#
# --affected BASE runs the subset of a branch's change, which it reads from
# git: the files that `git diff --name-only --no-renames BASE...HEAD` names.
# Those are the files HEAD's commits change since their merge base with BASE.
# A renamed file counts under its old path as well as its new one, because a
# suite that names the old path breaks. An uncommitted edit is not part of the
# change. When the change names no file, nothing runs, because a tree that
# matches its base can break no suite; the run prints one line saying so and
# exits 0. A BASE git cannot read is a usage error. A change handed over as
# PATHs, as in `run-tests.sh $(git diff --name-only origin/main...HEAD)`, runs
# every suite when it is empty, because an empty change expands to no PATH.
#
# A file runs once, unless its opening comment block declares named parts:
#
#   # run-tests-parts: <part> [<part> ...]
#
# Such a file runs once per part, and each run has its own report line
# (FILE[PART]) and its own serial re-run, so a long file runs on several cores
# at once and stays one file. Each run gets
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
# --seconds FILE keeps each run's time for a reader such as CI. The file is
# emptied before anything runs, and each run of the parallel wave adds one line
# to it as the run ends: "<run>\t<seconds>\t<status>". The run is named as its
# report line names it, the seconds are its wall time in whole seconds, and the
# status is PASS, FAIL[<exit>] or TIMEOUT. A serial re-run adds no line, so the
# seconds sum to the suite's test-seconds, its runs' wall times added up. A FILE
# that cannot be written is a usage error.
#
# The timeout ends a run that has hung, never one that is only slow. A suite
# writes a line for each assertion, and a loaded host makes a sound run take
# longer without making it go quiet, so the runner judges a run by its silence,
# not its length. A guard starts beside each run, in the run's process group,
# and reads the size of the run's log once a second. Once the log has not grown
# for the timeout, the guard writes a line saying so into the log and sends the
# group TERM, and KILL five seconds later if the run has not ended. The run is
# reported as TIMEOUT.
# The guard also ends its run once the runner is gone, so a stopped runner
# leaves no run behind. A run that hangs while it goes on writing, such as a
# loop that prints forever, is outside the guard's reach. The caller's own
# limit ends it, such as a CI job's timeout-minutes. -t 0 starts no guard.
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
# reports the raw parallel result. A serial re-run keeps the caller's priority,
# because it runs alone and cannot crowd the host.
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
# Every file runs with the test floor, tools/test-floor, at the front of PATH.
# A file that stubs gc, bd or gh puts its stub directory in front of that, so
# the floor sits between its stubs and the real binaries. When the stub
# directory goes while a script the file started still runs, a call that would
# have reached the real gc, and the live city it finds from the working
# directory, is refused there instead (tools/test-floor/refuse.sh). A file run
# directly gets the floor only through harness_init
# (assets/scripts/test-harness.sh).
#
# Every file runs with no GC_* or BEADS_* variable of the caller's. A city's
# session exports them, naming its city, rig, store and session, while CI sets
# none. A script under test that read one would reach the live city when a
# session runs the file, and the file's own stubs when CI does. The one value
# handed on is the gc binary GC_BIN names, as RUN_TESTS_GC_BIN, for a file that
# runs the real gc against a scratch city of its own. It goes under the
# runner's name, so no script under test finds the real gc through GC_BIN. A
# file run directly gets the caller's variables as they are, and a setting
# under either prefix that is meant for one file, such as
# GC_TMUX_TEST_WAIT_SECS, reaches it only then.
#
# A run with a file that sources the shared harness
# (assets/scripts/test-harness.sh) builds the compiled fake gc from this tree
# once, before the first file starts, and names it in RUN_TESTS_FAKE_GC, so
# such a file copies that build instead of making its own. When the build
# fails the runner says so and names none, and each such file then builds the
# fake itself and fails with the compiler's message. The runner is the only
# source of RUN_TESTS_FAKE_GC. A file run directly builds the fake itself.
#
# The runner needs bash 5.1 or later, both its own and the first on PATH, which
# starts each file.
#
# Exit: 0 every file passed, or passed on a serial re-run, or the subset was
# empty; 1 one or more failed serially too; 2 a usage or enumeration error,
# such as a BASE git cannot read, or no bash of 5.1 or later.

set -uo pipefail

# The oldest bash the runner runs under (see the header). bash sets
# BASH_VERSINFO itself and never takes it from the environment.
case "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}" in
  [0-4].*|5.0)
    echo "run-tests: needs bash 5.1 or later, and $BASH is bash $BASH_VERSION, so nothing ran" >&2
    exit 2 ;;
esac

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
AFFECTED=""
AFFECTED_SET=0
SECONDS_FILE=""
SECONDS_SET=0
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
    --affected)    AFFECTED="${2:-}"; AFFECTED_SET=1; shift; [ $# -eq 0 ] || shift ;;
    --affected=*)  AFFECTED="${1#--affected=}"; AFFECTED_SET=1; shift ;;
    --list)        LIST_ONLY=1; shift ;;
    -q|--quiet)    QUIET=1; shift ;;
    --seconds)     SECONDS_FILE="${2:-}"; SECONDS_SET=1; shift; [ $# -eq 0 ] || shift ;;
    --seconds=*)   SECONDS_FILE="${1#--seconds=}"; SECONDS_SET=1; shift ;;
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
if [ "$SECONDS_SET" -eq 1 ]; then
  case "$SECONDS_FILE" in
    '') echo "run-tests: --seconds needs a file to write" >&2; exit 2 ;;
    -*) echo "run-tests: --seconds needs a file to write, not the option '$SECONDS_FILE'" >&2; exit 2 ;;
  esac
  { : >"$SECONDS_FILE"; } 2>/dev/null || { echo "run-tests: cannot write the --seconds file '$SECONDS_FILE'" >&2; exit 2; }
fi
if [ "$AFFECTED_SET" -eq 1 ]; then
  case "$AFFECTED" in
    '')    echo "run-tests: --affected needs a base, such as origin/main" >&2; exit 2 ;;
    -*)    echo "run-tests: --affected needs a base, such as origin/main, not the option '$AFFECTED'" >&2; exit 2 ;;
    *..*)  echo "run-tests: --affected takes a base, such as origin/main, not the range '$AFFECTED'" >&2; exit 2 ;;
  esac
  [ "${#ARGS[@]}" -eq 0 ] || { echo "run-tests: --affected reads the change from git, so it takes no PATH" >&2; exit 2; }
fi

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

# fn_rows <path> — each line of a tracked script that sits inside a function's
# body, as one "<function>\t<line number>\t<line>" row. A body starts at a line
# that names a function at its start, as NAME() or function NAME, and ends at
# the next line that starts with } or ), and a body that closes on the line
# that names it holds no other line. A here-document's lines are in no body,
# because what they hold is another script's text. A line this misreads, such
# as a "<<" inside quotes, can only leave a line outside every body, which
# counts its whole script as the one that compiles a program.
fn_rows() {
  awk '
    function heredoc(s,    i, rest) {
      while ((i = index(s, "<<")) > 0) {
        rest = substr(s, i + 2)
        if (substr(s, i - 1, 1) == "<" || substr(rest, 1, 1) == "<") { s = substr(rest, 2); continue }
        strip = (substr(rest, 1, 1) == "-")
        if (strip) rest = substr(rest, 2)
        sub(/^[[:space:]]*/, "", rest)
        if (match(rest, /^["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
          hd = substr(rest, RSTART, RLENGTH); gsub(/["\047]/, "", hd); return
        }
        s = rest
      }
    }
    hd != "" {
      line = $0
      if (strip) sub(/^\t+/, "", line)
      if (line == hd) hd = ""
      next
    }
    /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/ || /^function[[:space:]]+[A-Za-z_]/ {
      name = $0; sub(/^function[[:space:]]+/, "", name); sub(/[^A-Za-z0-9_].*$/, "", name)
      body = $0; sub(/^(function[[:space:]]+)?[A-Za-z0-9_]+[[:space:]]*(\(\))?[[:space:]]*/, "", body)
      cur = (body ~ /^[{(].*[})][[:space:]]*;?[[:space:]]*(#.*)?$/) ? "" : name
      heredoc($0)
      next
    }
    /^[})]/ { cur = "" }
    cur != "" { print cur "\t" NR "\t" $0 }
    { heredoc($0) }
  ' "$ROOT/$1"
}

# go_reach — the Go programs the change reaches, and what compiles them (see
# the header). A suite that compiles a reached program is added, another script
# that compiles one outside a function joins CHANGED, and a function that
# compiles one joins GO_NAMES, with every function of its script that calls it
# in turn.
declare -a GO_NAMES=()
declare -A GO_NAMED=() REACHED=()
GO_LISTED=1
GO_SHAPED=0
go_reach() {
  local -a builds=()
  local b file rest n text tok d p fn hit held mains=""
  local -A main_dir=()
  while IFS= read -r b; do builds+=("$b"); done < <(
    git -C "$ROOT" grep -nIE --no-color \
      '(^|[^A-Za-z0-9_.-])go[[:space:]]+(build|run)[[:space:]].*\./[A-Za-z0-9_]' -- '*.sh' \
      | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#')
  [ "${#builds[@]}" -gt 0 ] || return 0
  for p in "${CHANGED[@]}"; do
    case "$p" in *.go|go.mod|go.sum) GO_SHAPED=1 ;; esac
  done
  if [ -f "$ROOT/go.mod" ] && command -v go >/dev/null 2>&1 \
    && mains="$(cd "$ROOT" && go list -e -f '{{if eq .Name "main"}}{{.Dir}}{{end}}' ./... 2>/dev/null)"; then
    while IFS= read -r d; do
      case "$d" in "$ROOT"/*) main_dir["${d#"$ROOT"/}"]=1 ;; esac
    done < <(printf '%s\n' "$mains")
  else
    GO_LISTED=0
  fi
  for b in "${builds[@]}"; do
    file="${b%%:*}"; rest="${b#*:}"; n="${rest%%:*}"; text="${rest#*:}"
    hit=0
    while IFS= read -r tok; do
      tok="${tok#./}"; tok="${tok%/}"
      [ -n "$tok" ] || continue
      if [ "$GO_LISTED" -eq 0 ]; then
        [ "$GO_SHAPED" -eq 0 ] || hit=1
        continue
      fi
      held=0
      for d in "${!main_dir[@]}"; do
        case "$d" in
          "$tok"|*/"$tok") held=1; if program_reached "$d"; then hit=1; fi ;;
        esac
      done
      if [ "$held" -eq 0 ] && gone_reached "$tok"; then hit=1; fi
    done < <(printf '%s\n' "$text" \
      | sed -E 's/^(.*[^A-Za-z0-9_.-])?go[[:space:]]+(build|run)[[:space:]]//' \
      | grep -oE '(^|[[:space:]"'\''=(])\./[A-Za-z0-9_][A-Za-z0-9_./-]*' | sed -E 's/^[^.]*//')
    [ "$hit" -eq 1 ] || continue
    case "$file" in *.test.sh) add "$ROOT/$file"; continue ;; esac
    fn="$(fn_rows "$file" | awk -F'\t' -v n="$n" '$2 == n { print $1; exit }')"
    if [ -z "$fn" ]; then
      [ -n "${IN[$file]:-}" ] || { IN[$file]=1; CHANGED+=("$file"); }
    else
      go_callers "$file" "$fn"
    fi
  done
}

# program_reached <directory> — whether the change reaches the program whose
# main package is in the directory, a path from the root (see the header).
program_reached() {
  local d="$1" out line p pd
  local -A pkg_dirs=() embed_dirs=()
  if [ -z "${REACHED[$d]:-}" ]; then
    REACHED[$d]=0
    if out="$(cd "$ROOT" && go list -e -deps -f '{{if not .Standard}}D {{.Dir}}{{if .Incomplete}}{{"\n"}}I{{end}}{{if .EmbedPatterns}}{{"\n"}}E {{.Dir}}{{end}}{{end}}' "./$d" 2>/dev/null)"; then
      while IFS= read -r line; do
        case "$line" in
          I) REACHED[$d]=1 ;;
          "D $ROOT") pkg_dirs[.]=1 ;;
          "D $ROOT/"*) pkg_dirs["${line#"D $ROOT/"}"]=1 ;;
          "E $ROOT") embed_dirs[.]=1 ;;
          "E $ROOT/"*) embed_dirs["${line#"E $ROOT/"}"]=1 ;;
        esac
      done < <(printf '%s\n' "$out")
      for p in "${CHANGED[@]}"; do
        [ "${REACHED[$d]}" -eq 0 ] || break
        case "$p" in
          go.mod|go.sum) REACHED[$d]=1; break ;;
          *_test.go) continue ;;
        esac
        case "$p" in */*) pd="${p%/*}" ;; *) pd=. ;; esac
        if [ -n "${pkg_dirs[$pd]:-}" ]; then
          REACHED[$d]=1; break
        fi
        while [ -z "${embed_dirs[$pd]:-}" ]; do
          case "$pd" in .) continue 2 ;; */*) pd="${pd%/*}" ;; *) pd=. ;; esac
        done
        REACHED[$d]=1; break
      done
    elif [ "$GO_SHAPED" -eq 1 ]; then
      REACHED[$d]=1
    fi
  fi
  [ "${REACHED[$d]}" -eq 1 ]
}

# gone_reached <package> — whether the change reaches a program whose main
# package the module no longer holds: a changed path in a directory the
# ./<package> argument names, by the end of its path (see the header).
gone_reached() {
  local p pd
  for p in "${CHANGED[@]}"; do
    case "$p" in */*) pd="${p%/*}" ;; *) pd=. ;; esac
    case "$pd" in "$1"|*/"$1") return 0 ;; esac
  done
  return 1
}

# go_callers <path> <function> — adds the function to GO_NAMES, and every
# function of the same script that calls it, and those functions' callers in
# turn. A call is the name on a line of the body that is not a comment.
go_callers() {
  local file="$1" f c rows
  local -a todo=("$2")
  rows="$(fn_rows "$file")"
  while [ "${#todo[@]}" -gt 0 ]; do
    f="${todo[0]}"; todo=("${todo[@]:1}")
    [ -z "${GO_NAMED[$f]:-}" ] || continue
    GO_NAMED[$f]=1; GO_NAMES+=("$f")
    while IFS= read -r c; do
      [ -n "$c" ] && todo+=("$c")
    done < <(printf '%s\n' "$rows" | awk -F'\t' -v f="$f" '
      { text = $0; sub(/^[^\t]*\t[^\t]*\t/, "", text) }
      $1 != f && text !~ /^[[:space:]]*#/ && text ~ ("(^|[^A-Za-z0-9_])" f "([^A-Za-z0-9_]|$)") { print $1 }' | sort -u)
  done
}

# The change --affected reads (see the header) becomes the PATHs. git writes the
# names NUL-separated, so a name with a space, or with a byte git would quote,
# arrives whole. A diff git cannot read fails the run, because read as an empty
# change it would pass without running anything.
if [ "$AFFECTED_SET" -eq 1 ]; then
  change_file="$(mktemp "${TMPDIR:-/tmp}/run-tests-change.XXXXXX")" || {
    echo "run-tests: mktemp failed" >&2; exit 2; }
  if ! git -C "$ROOT" diff --no-color --name-only --no-renames -z "${AFFECTED}...HEAD" -- >"$change_file"; then
    rm -f "$change_file"
    echo "run-tests: cannot read the change from $AFFECTED to HEAD (git diff ${AFFECTED}...HEAD failed)" >&2
    exit 2
  fi
  while IFS= read -r -d '' rel; do ARGS+=("$rel"); done <"$change_file"
  rm -f "$change_file"
  if [ "${#ARGS[@]}" -eq 0 ]; then
    [ "$LIST_ONLY" -eq 1 ] || echo "run-tests: ${AFFECTED}...HEAD changes no file — nothing to run"
    exit 0
  fi
fi

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

  # A script that compiles a Go program the change reaches is changed along
  # with it, or names the function that compiles it (see the header).
  go_reach

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
  NAMES+=("${GO_NAMES[@]}")

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

# The test floor every file runs above (see the header). A tree without it does
# not run, since nothing would stand between a file's stubs and the real gc.
[ -x "$ROOT/tools/test-floor/gc" ] || {
  echo "run-tests: no test floor at $ROOT/tools/test-floor; not running" >&2; exit 2; }
export PATH="$ROOT/tools/test-floor:$PATH"

# The bash every file starts with, held to the runner's own floor (see the
# header). spawn starts each file from ROOT, so the first bash on PATH is looked
# up from ROOT, and spawn starts each file with the full path found here, the
# file whose version this reads. type -P answers from the locations the shell
# remembers before it searches PATH, so the lookup forgets them first.
FILE_BASH="$(cd "$ROOT" && hash -r && type -P bash)" || {
  echo "run-tests: each file starts with the first bash on PATH, and PATH has no bash, so nothing ran" >&2
  exit 2; }
case "$FILE_BASH" in /*) ;; *) FILE_BASH="$ROOT/$FILE_BASH" ;; esac
file_bash_v="$("$FILE_BASH" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} $BASH_VERSION"' 2>/dev/null)"
case "$file_bash_v" in
  [0-4].*|5.0\ *)
    echo "run-tests: each file starts with the first bash on PATH, and $FILE_BASH is bash ${file_bash_v#* }, older than 5.1, so nothing ran" >&2
    exit 2 ;;
  [0-9]*.[0-9]*\ *) ;;
  *)
    echo "run-tests: each file starts with the first bash on PATH, and $FILE_BASH reports no bash version, so nothing ran" >&2
    exit 2 ;;
esac

# The caller's variables every file runs without, and the one value handed on
# (see the header). The runner is the only source of RUN_TESTS_GC_BIN, so one
# the caller exported is replaced.
if [ -n "${GC_BIN:-}" ]; then
  export RUN_TESTS_GC_BIN="$GC_BIN"
else
  unset RUN_TESTS_GC_BIN
fi
unset "${!GC_@}" "${!BEADS_@}"

LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/run-tests.XXXXXX")" || { echo "run-tests: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$LOGDIR"' EXIT

# The fake gc a file that sources the shared harness runs (see the header).
unset RUN_TESTS_FAKE_GC
if [ -d "$ROOT/services/gctk/internal/gcbd/fakegc" ] && grep -q -F test-harness.sh -- "${TESTS[@]}" 2>/dev/null; then
  if (cd "$ROOT/services/gctk" && go build -buildvcs=false -o "$LOGDIR/fake-gc" ./internal/gcbd/fakegc) >"$LOGDIR/fake-gc.log" 2>&1; then
    export RUN_TESTS_FAKE_GC="$LOGDIR/fake-gc"
  else
    echo "run-tests: the fake gc did not build, so each file that sources the shared harness builds its own: $(tail -3 "$LOGDIR/fake-gc.log" | tr '\n' ' ')" >&2
  fi
fi

total="${#RUN_FILE[@]}"
[ "$JOBS" -gt "$total" ] && JOBS="$total"
START="$SECONDS"
if [ "$TIMEOUT" -gt 0 ]; then
  guard_note="a run silent for ${TIMEOUT}s is ended"
else
  guard_note="no run is ended for silence"
fi
if [ "$QUIET" -eq 0 ]; then
  if [ "$total" -eq "${#TESTS[@]}" ]; then
    printf 'run-tests: %d files, %d parallel, %s\n' "$total" "$JOBS" "$guard_note"
  else
    printf 'run-tests: %d files as %d runs, %d parallel, %s\n' "${#TESTS[@]}" "$total" "$JOBS" "$guard_note"
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

# The guard beside a run (see the header). It sits in the run's process group,
# so it ignores the TERM it sends there, and the KILL that follows ends it with
# the run. Before it ends a run for silence it writes the run's hang mark, which
# the report reads as a TIMEOUT whatever status the signal leaves the run with.
# The mark is named for the run's pid, and the run clears it before its guard
# starts. No process is given a pid while a process group of that id lives, and
# each guard sits in its run's group, so once a run has cleared its mark no
# other run's guard can write it. Its output is the run's log. In any subshell
# $$ is the runner's pid.
guard() { # <run-pid> <log> <mark>
  local run="$1" log="$2" mark="$3" size grown="" since="$EPOCHSECONDS" i
  trap '' TERM
  while kill -0 "$run" 2>/dev/null; do
    kill -0 "$$" 2>/dev/null || break
    size="$(wc -c <"$log" 2>/dev/null)"
    # EPOCHSECONDS counts whole seconds, so a difference equal to the timeout
    # can be up to a second short of it.
    if [ "$size" != "$grown" ]; then
      grown="$size"; since="$EPOCHSECONDS"
    elif [ $((EPOCHSECONDS - since)) -gt "$TIMEOUT" ]; then
      : >"$mark"
      printf '\nrun-tests: nothing written for %ss, so the run has hung and is ended\n' "$TIMEOUT"
      break
    fi
    sleep 1
  done
  kill -0 "$run" 2>/dev/null || return 0
  kill -TERM -- "-$run" 2>/dev/null
  for i in 1 2 3 4 5; do
    sleep 1
    kill -0 "$run" 2>/dev/null || return 0
  done
  kill -KILL -- "-$run" 2>/dev/null
}

# Start one run in the background with FILE_BASH, its output to its log, and
# its guard beside it while the timeout is on. The run is the background job
# itself, so its pid leads its process group. A part's run is told which part
# it is and which parts its file declares; a run of a whole file gets neither,
# whatever the caller exported. Any words after the index are a command the run
# starts through, such as LOW_PRIORITY.
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
      # An async command's words expand after the fork, where BASHPID would
      # name the guard, so the run's pid is read before it.
      run_pid="$BASHPID"
      rm -f "$LOGDIR/$run_pid.hung"
      guard "$run_pid" "$log" "$LOGDIR/$run_pid.hung" &
    fi
    exec "$@" "$FILE_BASH" "$t"
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
  [ ! -e "$LOGDIR/$pid.hung" ] || rc=124
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
  [ -z "$SECONDS_FILE" ] || printf '%s\t%s\t%s\n' "$rel" "$dur" "$status" >>"$SECONDS_FILE"
  unset 'PID_IDX[$pid]' 'PID_START[$pid]'
}

# Re-run one run serially (no sibling jobs) at the caller's priority, reusing
# the same guard and process-group reap as the parallel path. Used after the
# parallel wave to tell a parallel-contention false failure from a real one.
rerun_serial() {
  local idx="$1" pid rc
  spawn "$idx"
  pid=$!
  wait "$pid"; rc=$?
  kill -- -"$pid" 2>/dev/null   # reap anything the file left in its group
  [ ! -e "$LOGDIR/$pid.hung" ] || rc=124
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
