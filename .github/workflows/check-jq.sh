#!/usr/bin/env bash
# check-jq.sh — fails by name when the jq on PATH is older than 1.8.
#
# On the host, Homebrew's jq comes first on PATH, and it is jq 1.8. jq 1.8
# compiles programs that jq 1.7 rejects, such as a bare `if … end` or a
# `reduce …` followed by `as`, `[i]` or `.key`, so on an older jq the suite
# fails code the host runs. Each job in tests.yml runs this before the suite.
#
# It prints the jq it resolves and the version that jq reports.
# Exit: 0 the jq on PATH is 1.8 or later; 1 no jq is on PATH, or the one there
# reports a version older than 1.8 or none this can read. Each failure prints
# a GitHub Actions error annotation that names jq.
set -uo pipefail

p="$(command -v jq)" || { echo "::error::jq is not on PATH; the suite needs jq 1.8 or later"; exit 1; }
v="$("$p" --version 2>/dev/null)" || v=""
echo "jq: $p ${v:-(no version)}"
re='^jq-([0-9]+)\.([0-9]+)'
if [[ "$v" =~ $re ]]; then
    major=$((10#${BASH_REMATCH[1]}))
    minor=$((10#${BASH_REMATCH[2]}))
    if [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 8 ]; }; then
        exit 0
    fi
fi
echo "::error::jq at $p reports '$v'; the suite needs jq 1.8 or later"
exit 1
