#!/usr/bin/env bash
# suite-test-floor.sh — hardened learned rule: every *.test.sh sources
# tools/test-floor.sh, which puts the test floor at the front of PATH before
# the suite writes a stub.
#
# A suite's stubs live in its temp dir, which can go while a script under test
# still runs, and a PATH search that misses a stub finds the next directory on
# PATH. tools/test-floor.sh makes that the test floor, where gc, bd and gh
# refuse, whether tools/run-tests.sh runs the suite or a person does. Run
# directly, a suite that does not source it hands such a call the real gc,
# which reaches the live city from the working directory.
#
# A finding is a *.test.sh with no line that sources a path ending in
# /test-floor.sh, with `.` or `source` as the line's first word. A whole-line
# comment and a line inside a here-document's body quote the line rather than
# run it, so neither counts. Where the line sits is not checked: sourced after
# a stub directory went on PATH, the floor lands in front of the stubs and
# refuses every call they answer, which fails the suite in every run.
#
# A file tools/deletion-plan.tsv lists is not held to the rule. The plan
# retires it, so it gets no new work (AGENTS.md, "Code the deletion plan
# retires gets no new work"), and the bead that retires it carries the gap.
# The plan read is the one beside this detector's directory, and a file
# matches its row by physical path.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 a suite or the
# plan that could not be read, or a scan that failed.

set -uo pipefail

export LC_ALL=C

FIX='sources no tools/test-floor.sh, so run directly it has no test floor beneath its stubs, and a call a stub misses reaches the real gc; fix: . "$HERE/<path to tools>/test-floor.sh" || exit 2, right after HERE is set (docs/testing.md, "The test floor") (learned rule: suite-test-floor)'

case "${BASH_SOURCE[0]}" in
    */*) here="${BASH_SOURCE[0]%/*}" ;;
    *) here=. ;;
esac
root="$(cd "$here/../.." 2>/dev/null && pwd -P)" || {
    echo "suite-test-floor: cannot resolve the repository above $here, so no suite was checked"; exit 2; }

# The physical paths of the files the plan retires, each on a line of its own
# between newlines. A plan that is absent retires nothing.
retired=$'\n'
plan="$here/../deletion-plan.tsv"
if [ -e "$plan" ]; then
    if [ ! -r "$plan" ]; then
        echo "suite-test-floor: cannot read $plan, so no suite was checked"; exit 2
    fi
    while IFS=$'\t' read -r path _ || [ -n "$path" ]; do
        case "$path" in '' | '#'*) continue ;; esac
        retired+="$root/$path"$'\n'
    done < "$plan" || { echo "suite-test-floor: cannot read $plan, so no suite was checked"; exit 2; }
fi

# One line per suite: "<1 or 0> <path>", 1 when a line sources the floor. A
# here-document's body runs to the line that holds only its word, after leading
# tabs for `<<-`. `<<<` opens a here-string, not a body. A load that fails
# leaves an empty program, which awk runs as a scan that finds nothing in any
# suite, so it ends the run instead.
SCAN=$(cat <<'AWK'
FNR == 1 { if (file != "") R[file] = hit; file = FILENAME; hit = 0; hd = ""; strip = 0 }
hit { next }
{ line = $0; sub(/\r$/, "", line) }
hd != "" {
    if (strip) sub(/^\t+/, "", line)
    if (line == hd) hd = ""
    next
}
line ~ /^[ \t]*#/ { next }
line ~ /^[ \t]*(\.|source)[ \t]/ && line ~ /\/test-floor\.sh(["' \t;|&)]|$)/ { hit = 1; next }
{
    s = line
    while (match(s, /<<-?[ \t]*[\\"']?[A-Za-z_][A-Za-z0-9_-]*["']?/)) {
        pre = substr(s, 1, RSTART - 1)
        tok = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        if (pre ~ /<$/) continue
        strip = (tok ~ /^<<-/)
        sub(/^<<-?[ \t]*/, "", tok)
        gsub(/[\\"']/, "", tok)
        hd = tok
    }
}
END {
    if (file != "") R[file] = hit
    for (i = 1; i < ARGC; i++) {
        f = ARGV[i]
        if (f in seen) continue
        seen[f] = 1
        printf "%d %s\n", R[f] + 0, f
    }
}
AWK
) || { echo "suite-test-floor: could not load the suite scan, so no suite was checked"; exit 2; }

# awk reads an operand shaped like `name=value` as an assignment, so a relative
# path goes to it with a ./ prefix, which the report takes off again.
suites=()
unreadable=0
for f in "$@"; do
    case "$f" in *.test.sh) ;; *) continue ;; esac
    [ -f "$f" ] || continue
    case "$f" in */*) dir="${f%/*}" ;; *) dir=. ;; esac
    if abs="$(cd "$dir" 2>/dev/null && pwd -P)/${f##*/}"; then
        case "$retired" in *$'\n'"$abs"$'\n'*) continue ;; esac
    fi
    if [ ! -r "$f" ]; then
        echo "$f: cannot read it to check that it sources tools/test-floor.sh (suite-test-floor)"
        unreadable=1
        continue
    fi
    case "$f" in /*) suites+=("$f") ;; *) suites+=("./${f#./}") ;; esac
done

found=0
if [ "${#suites[@]}" -gt 0 ]; then
    if ! results="$(awk "$SCAN" "${suites[@]}")"; then
        echo "suite-test-floor: the suite scan failed, so no suite was checked"
        exit 2
    fi
    while read -r entered suite; do
        [ -n "$suite" ] || continue
        if [ "$entered" != 1 ]; then
            echo "${suite#./}:1: $FIX"
            found=1
        fi
    done <<< "$results"
fi

[ "$unreadable" -eq 0 ] || exit 2
[ "$found" -eq 0 ]
