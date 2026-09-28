#!/usr/bin/env bash
# Tests for goal-canonical.sh: the shared contract serializer must be stable,
# key-order-independent, and blind to non-contract metadata — those are the
# properties the tamper-evident snapshot depends on.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/goal-canonical.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

run() { printf '%s' "$1" | "$SUT"; }

# Key order in the input does not change the output.
A=$(run '[{"metadata":{"goal.statement":"s","goal.oracle.kind":"metric","goal.oracle.threshold":"40","goal.budget.max_iterations":"6"}}]')
B=$(run '[{"metadata":{"goal.budget.max_iterations":"6","goal.oracle.threshold":"40","goal.oracle.kind":"metric","goal.statement":"s"}}]')
eq "$A" "$B" "key-order-independent"

# Non-contract metadata is ignored: adding unrelated keys does not change output.
C=$(run '[{"metadata":{"goal.statement":"s","goal.oracle.kind":"metric","goal.oracle.threshold":"40","goal.budget.max_iterations":"6","goal.trail":"[{\"attempt\":1}]","goal.status":"armed","gc.routed_to":"pool"}}]')
eq "$A" "$C" "ignores non-contract metadata (trail/status/gc.*)"

# A contract change DOES change the output.
D=$(run '[{"metadata":{"goal.statement":"s","goal.oracle.kind":"metric","goal.oracle.threshold":"30","goal.budget.max_iterations":"6"}}]')
[ "$A" != "$D" ] && ok "threshold change changes the snapshot" || bad "threshold change changes the snapshot"

# Empty metadata yields a well-formed empty contract, not an error.
E=$(run '[{"metadata":{}}]')
eq "$(printf '%s' "$E" | jq -r '.statement')" "" "empty metadata -> empty statement"
eq "$(printf '%s' "$E" | jq -r 'type')" "object" "empty metadata -> object"

# Non-array input is rejected with exit 2.
set +e
printf '%s' '{"not":"an array"}' | "$SUT" >/dev/null 2>&1
rc=$?
set -e
eq "$rc" "2" "non-array input exits 2"

# Output is a single line (canonical, -c).
LINES=$(run '[{"metadata":{"goal.statement":"s","goal.budget.max_iterations":"6"}}]' | wc -l | tr -d ' ')
eq "$LINES" "1" "output is one line"

echo "---"
echo "canonical: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
