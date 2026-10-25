#!/usr/bin/env bash
# run-lib.stub.sh — run-lib.sh's verbs over a file of runs, for the suites of
# its readers. A suite points GC_RUN_LIB, the variable each reader sources
# run-lib.sh through, at this file, so the reader's own cases decide what it
# does with the runs it is given and none of them stubs the reads behind the
# runs. Sourced, never executed.
#
# GC_RUN_LIB names this file, and RUN_LIB_STUB_RUNS names a JSON array of runs
# in run-lib.sh's shape, every run the suite's store holds, closed ones
# included. Each verb answers from it the way run-lib.sh answers from a store:
#   runs <reader> <bead>   the runs whose bead is <bead>
#   subject <reader> <id>  the runs whose root or input convoy is <id>
#   map <reader> [all]     the live runs, or every run with `all`
# An unset name, or a file that does not exist, is a store with no runs.
# RUN_LIB_STUB_CMD, when set, names a command that prints that array instead,
# run at each call with the call's verb, reader and argument, for a suite whose
# store changes while a script runs (test-harness.sh derives it from its store)
# or whose reads see the store at different moments; a command that fails fails
# the call.
# RUN_LIB_STUB_FAIL lists the calls that fail as a failed read does, printing
# nothing and returning 1: `all`, a verb, or a verb and its argument as
# <verb>:<arg>, separated by spaces. Each call is appended to RUN_LIB_STUB_LOG,
# when it is set, as "<verb> <reader> <arg>", so a suite can check which store
# a reader asked. The reader must name a command the caller defines, as for
# run-lib.sh, or the verb is a usage error.
#
# $RUN_JQ is run-lib.sh's own, so a reader that applies its defs judges rows
# the way it does. run-lib.test.sh checks that, given every run of the
# fixture's store, this file answers each case of run-lib.fixture.json the way
# run-lib.sh does.

# run-lib.sh is read beside this file, which GC_RUN_LIB names. The hook a
# suite runs under sh sources it too, so it is found without BASH_SOURCE.
case "${GC_RUN_LIB:-}" in
    */*) _run_lib_stub_dir="${GC_RUN_LIB%/*}" ;;
    *) _run_lib_stub_dir=. ;;
esac
# shellcheck source=run-lib.sh
. "$_run_lib_stub_dir/run-lib.sh" || return 1

run_lib() {
    local verb="${1:-}" reader="${2:-}" arg="${3:-}" runs='[]' f
    [ -z "${RUN_LIB_STUB_LOG:-}" ] || printf '%s %s %s\n' "$verb" "$reader" "$arg" >> "$RUN_LIB_STUB_LOG"
    if [ -z "$reader" ] || ! type "$reader" >/dev/null 2>&1; then
        echo "run_lib: no reader given" >&2; return 2
    fi
    case "$verb" in
        runs|subject) [ -n "$arg" ] || { echo "run_lib $verb: no bead given" >&2; return 2; } ;;
        map) case "$arg" in ''|all) ;; *) echo "run_lib map: unknown scope '$arg'" >&2; return 2 ;; esac ;;
        *) echo "run_lib: unknown verb '$verb'" >&2; return 2 ;;
    esac
    for f in ${RUN_LIB_STUB_FAIL:-}; do
        case "$f" in all|"$verb"|"$verb:$arg") return 1 ;; esac
    done
    if [ -n "${RUN_LIB_STUB_CMD:-}" ]; then
        runs="$("$RUN_LIB_STUB_CMD" "$verb" "$reader" "$arg")" || return 1
    elif [ -n "${RUN_LIB_STUB_RUNS:-}" ] && [ -f "$RUN_LIB_STUB_RUNS" ]; then
        runs="$(cat "$RUN_LIB_STUB_RUNS")"
    fi
    printf '%s' "$runs" | jq -c --arg v "$verb" --arg a "$arg" '
        if $v == "runs" then map(select(.bead == $a))
        elif $v == "subject" then map(select(.root == $a or .convoy == $a))
        elif $a == "all" then .
        else map(select(.live)) end
        | sort_by(.root)'
}
