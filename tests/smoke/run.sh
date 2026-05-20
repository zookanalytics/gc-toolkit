#!/bin/sh
# Smoke test runner for gc-toolkit consumer scripts.
#
# Discovers every *.test.sh in this directory and runs each as its own
# shell process. Per-test stdout/stderr is captured and printed indented
# under FAIL lines. Exits non-zero if any test failed.
set -u

here=$(cd "$(dirname "$0")" && pwd)
passed=0
failed=0
found=0

for test in "$here"/*.test.sh; do
    [ -f "$test" ] || continue
    found=1
    name=$(basename "$test")
    if output=$(sh "$test" 2>&1); then
        printf 'PASS %s\n' "$name"
        passed=$(( passed + 1 ))
    else
        printf 'FAIL %s\n' "$name"
        printf '%s\n' "$output" | sed 's/^/    /'
        failed=$(( failed + 1 ))
    fi
done

if [ "$found" -eq 0 ]; then
    echo "No tests found in $here" >&2
    exit 1
fi

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
