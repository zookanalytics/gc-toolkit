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

# Hermeticity: the script also calls `gc hook` and `gc mail check`. If
# the host happens to have hook entries or mail for the fixture agent
# name, those segments leak into the assertion. Shim `gc` via PATH to
# a no-op stub for the duration of the run. The script's
# GC_SESSION_LIST_OVERRIDE branch bypasses `gc session list` directly,
# so the stub never needs to serve the fixture itself.
stub_dir=$(mktemp -d -t gc-toolkit-smoke-XXXXXXXX)
cat > "$stub_dir/gc" <<'EOF'
#!/bin/sh
# Stub gc for smoke tests: exit 0 with no output. The status-line
# script's session-list call is handled by GC_SESSION_LIST_OVERRIDE
# and never reaches this stub.
exit 0
EOF
chmod +x "$stub_dir/gc"

# The title cache (/tmp/gc-title-<slug>) is keyed by the agent slug.
# Clean before and after so a prior run can't poison the read and this
# run leaves no residue.
slug=$(printf '%s' "$agent" | sed 's|[./]|-|g')
cache="/tmp/gc-title-${slug}"
trap 'rm -rf "$stub_dir"; rm -f "$cache"' EXIT
rm -f "$cache"

actual=$(PATH="$stub_dir:$PATH" GC_SESSION_LIST_OVERRIDE="$fixture" \
    "$script" "$agent")

# Title is emitted as " <title>" (leading space, per script's Emit
# block). With the stubbed gc, hook and mail counts are 0, so hook_seg
# and mail_seg stay empty.
expected=" ${expected_title}"

if [ "$actual" = "$expected" ]; then
    exit 0
fi
printf 'expected: [%s]\n' "$expected"
printf 'actual:   [%s]\n' "$actual"
exit 1
