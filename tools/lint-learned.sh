#!/usr/bin/env bash
# lint-learned.sh — runner for hardened learned-rule lints.
#
# Executes every executable in tools/lint-learned.d/ against the repository.
# Each detector encodes ONE hardened learned rule — a prose bullet from
# a learned-conventions fragment that graduated into executable form via a
# `prompt-update: harden` PR (specs/2026-08-learning-system/implementation-design.md
# §8). Wiring this runner into a rig's refinery `lint_command` is a PER-RIG
# OPERATOR DECISION, because refinery gates run on every bead — the pack ships
# the tool, never the wiring.
#
# Contract:
#   • FILE LIST — from argv when args are given; otherwise every tracked file
#     in the repository, from `git ls-files` at the top level. A detector
#     asserts an invariant the codebase either holds or does not, so it reads
#     the whole tree: scoping to a diff cannot make the codebase satisfy a
#     rule, it only decides who gets told. Paths that are not regular files
#     drop out. An empty list is a clean pass, not an error.
#   • DISPATCH — the runner passes the whole file list to each detector on
#     argv. Detectors get no stdin and no env contract beyond the argv list.
#   • DETECTOR EXIT CODES — 0 = clean; 1 = findings, printed on stdout as
#         <file>:<line>: <message>
#     one finding per line. Any other exit code is a detector ERROR (bug or
#     environment problem), reported distinctly and still failing the run —
#     a broken detector must never read as a green gate.
#   • RUNNER EXIT — non-zero iff any detector found anything or errored,
#     after a per-detector summary. 0 means every detector ran clean.
#   • Detectors must be CHEAP and DEPENDENCY-FREE (bash + POSIX userland):
#     a rig that opts in runs this inside a gate on every bead.
#
# Non-executables in lint-learned.d/ (README.md) are data, not detectors, and
# are skipped by the executable filter.

set -uo pipefail

tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detector_dir="$tools_dir/lint-learned.d"

if [ ! -d "$detector_dir" ]; then
    echo "lint-learned: no detector directory at $detector_dir — nothing to run" >&2
    exit 0
fi

# ── Assemble the file list ──────────────────────────────────────────────
files=()
if [ "$#" -gt 0 ]; then
    for f in "$@"; do
        [ -f "$f" ] && files+=("$f")
    done
else
    if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        # Exit 2, distinct from findings-exit-1: a tree the runner cannot
        # enumerate must never read as a green (or merely-findings) gate.
        echo "lint-learned: not inside a git repository — pass files on argv" >&2
        exit 2
    fi
    # Enumerate from the top level so findings carry repo-relative paths
    # whatever directory the caller invoked from.
    cd "$repo_root" || exit 2
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && files+=("$f")
    done < <(git ls-files)
fi

if [ "${#files[@]}" -eq 0 ]; then
    echo "lint-learned: no files to lint — clean"
    exit 0
fi

# ── Run every executable detector ───────────────────────────────────────
total_findings=0
failed_detectors=0
errored_detectors=0
ran=0
summary=()

for detector in "$detector_dir"/*; do
    if [ ! -f "$detector" ] || [ ! -x "$detector" ]; then continue; fi
    name="$(basename "$detector")"
    ran=$((ran + 1))

    output="$("$detector" "${files[@]}")" && ec=0 || ec=$?

    case "$ec" in
        0)
            summary+=("  $name: clean")
            ;;
        1)
            [ -n "$output" ] && printf '%s\n' "$output"
            count="$(printf '%s\n' "$output" | grep -c .)" || count=0
            total_findings=$((total_findings + count))
            failed_detectors=$((failed_detectors + 1))
            summary+=("  $name: $count finding(s)")
            ;;
        *)
            [ -n "$output" ] && printf '%s\n' "$output"
            errored_detectors=$((errored_detectors + 1))
            summary+=("  $name: ERROR (exit $ec) — detector broken, treated as failure")
            ;;
    esac
done

echo "lint-learned: ${#files[@]} file(s) against $ran detector(s)"
for line in ${summary[@]+"${summary[@]}"}; do echo "$line"; done

if [ "$ran" -eq 0 ]; then
    echo "lint-learned: no executable detectors in $detector_dir — clean (vacuously)"
    exit 0
fi
if [ "$errored_detectors" -gt 0 ] || [ "$failed_detectors" -gt 0 ]; then
    echo "lint-learned: FAIL — $total_findings finding(s) from $failed_detectors detector(s), $errored_detectors error(s)"
    exit 1
fi
echo "lint-learned: OK"
exit 0
