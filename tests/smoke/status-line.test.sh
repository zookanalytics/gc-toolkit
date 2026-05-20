#!/bin/sh
# Smoke test: assets/scripts/gc-toolkit-status-line.sh title slot.
#
# Feeds a snake_case session-list fixture via GC_SESSION_LIST_OVERRIDE
# and asserts that the script's title slot renders the fixture's title
# field. Would FAIL if the jq query reverted to the pre-PR-#37 shape
# (`.AgentName` / `.Title` with no `.sessions` unwrap) — the snake_case
# fixture would yield an empty title and the script would emit nothing.
set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../../assets/scripts/gc-toolkit-status-line.sh"
fixture="$here/fixtures/session-list.json"
agent="gc-toolkit.smoke-test-fixture"
expected_title="Smoke test fixture title"

# The title cache (/tmp/gc-title-<slug>) is keyed by the agent slug.
# Clean before and after so a prior run can't poison the read and this
# run leaves no residue.
slug=$(printf '%s' "$agent" | sed 's|[./]|-|g')
cache="/tmp/gc-title-${slug}"
trap 'rm -f "$cache"' EXIT
rm -f "$cache"

actual=$(GC_SESSION_LIST_OVERRIDE="$fixture" "$script" "$agent")

# Title is emitted as " <title>" (leading space, per script's Emit
# block). For the synthetic agent, gc hook and gc mail check return
# empty, so hook_seg and mail_seg stay empty.
expected=" ${expected_title}"

if [ "$actual" = "$expected" ]; then
    exit 0
fi
printf 'expected: [%s]\n' "$expected"
printf 'actual:   [%s]\n' "$actual"
exit 1
