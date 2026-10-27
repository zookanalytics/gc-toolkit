#!/usr/bin/env bash
# check-jq.test.sh — check-jq.sh passes a jq 1.8 or later, and fails by name on
# an older jq, on a jq whose version it cannot read, and when no jq is on PATH.
#
# Each case runs check-jq.sh with a PATH of one directory, holding a stub jq
# that prints the given --version line or no jq at all, so the jq it resolves
# is the case's and never the host's.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check-jq.sh"

[ -f "$SCRIPT" ] || { echo "check-jq.test.sh: cannot find check-jq.sh at $SCRIPT" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-jq-test.XXXXXX")" || { echo "check-jq.test.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

fail=0
note() { echo "check-jq.test.sh: FAIL — $1" >&2; fail=1; }

# run <case> <version line, or - for no jq on PATH>: runs check-jq.sh against
# the case's jq, leaving its exit code in RC and its output in OUT. A version
# line of "" makes a jq that prints nothing and exits 1, the way a binary the
# runner cannot execute fails.
run() {
    local dir="$TMP/$1"
    mkdir -p "$dir"
    if [ "$2" = "-" ]; then
        :
    elif [ -z "$2" ]; then
        printf '#!/bin/sh\nexit 1\n' > "$dir/jq"
    else
        # shellcheck disable=SC2016  # the $1 is the stub's own argument
        printf '#!/bin/sh\n[ "$1" = --version ] && echo %s\n' "$2" > "$dir/jq"
    fi
    [ ! -f "$dir/jq" ] || chmod +x "$dir/jq"
    OUT="$(PATH="$dir" "$BASH" "$SCRIPT" 2>&1)"
    RC=$?
}

# On a jq 1.8 or later, check-jq.sh exits 0, prints the jq it resolves with its
# version, and raises no error annotation.
for v in jq-1.8.0 jq-1.8.1 jq-1.8.2 jq-1.10.0 jq-2.0; do
    run "pass-$v" "$v"
    [ "$RC" -eq 0 ] || note "$v must pass, exited $RC: $OUT"
    case "$OUT" in *"$TMP/pass-$v/jq $v"*) ;; *) note "$v must print the jq it resolves and its version: $OUT" ;; esac
    case "$OUT" in *"::error::"*) note "$v must raise no error annotation: $OUT" ;; esac
done

# On an older jq, or one whose version it cannot read, check-jq.sh exits 1 with
# an error annotation that names jq, the version that jq reported, and the
# floor.
for v in jq-1.7.1 jq-1.7.1-apple jq-1.6 jq-1.5 jq-0.9 1.8.2 jq-1.x; do
    run "fail-$v" "$v"
    [ "$RC" -eq 1 ] || note "$v must fail with exit 1, exited $RC: $OUT"
    case "$OUT" in *"::error::jq at $TMP/fail-$v/jq reports '$v'; the suite needs jq 1.8 or later"*) ;; *) note "$v must fail by name: $OUT" ;; esac
done

run no-version ""
[ "$RC" -eq 1 ] || note "a jq that reports no version must fail with exit 1, exited $RC: $OUT"
case "$OUT" in *"::error::jq at $TMP/no-version/jq reports ''; the suite needs jq 1.8 or later"*) ;; *) note "a jq that reports no version must fail by name: $OUT" ;; esac

run no-jq -
[ "$RC" -eq 1 ] || note "no jq on PATH must fail with exit 1, exited $RC: $OUT"
case "$OUT" in *"::error::jq is not on PATH; the suite needs jq 1.8 or later"*) ;; *) note "no jq on PATH must fail by name: $OUT" ;; esac

if [ "$fail" -ne 0 ]; then
    echo "check-jq.test.sh: FAILED" >&2
    exit 1
fi
echo "check-jq.test.sh: OK"
