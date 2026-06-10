#!/usr/bin/env bash
# Hermetic test for retry-graphql.sh.
#
# retry-graphql.sh wraps a command (e.g. `gh pr ready`) in bounded exponential
# backoff so a transient GitHub GraphQL failure self-heals instead of stranding
# a fully-reviewed PR in draft. The codex pre-publish gate keys off its exit
# status: 0 -> un-draft succeeded (no escalation); non-zero -> retry budget
# exhausted (escalate).
#
# This drives the REAL script (no awk-ing a helper out of markdown) against a
# fake command whose pass/fail point and call count we control via files. No
# live city, Dolt, network, or real gh.
#
# Scenarios (the Verify contract from tk-3yrll / tk-onq62):
#   A. transient blip — fails twice then succeeds -> stops at first success, exit 0
#   B. persistent     — every attempt fails       -> bounded at MAX_ATTEMPTS, exit 1
#   C. healthy        — succeeds on attempt 1      -> no needless retries, exit 0
# The bound is driven by GC_GRAPHQL_RETRY_MAX (set to 3, asserted as 3) so the
# "bounded at N" assertion is not itself a hardcoded 5.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/retry-graphql.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

# Drive the retry budget from the env var (the script's single source of truth)
# so the "bounded at N" assertions below are not themselves a hardcoded 5.
export GC_GRAPHQL_RETRY_MAX=3

# Stub `sleep` (no real backoff delay) and provide a fake mutation whose call
# count + pass point we control via files. Both live on PATH so the script —
# which runs `sleep` and the passed command as subprocesses — picks them up.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/sleep" <<'SH'
#!/bin/sh
exit 0
SH
CALLS="$TMP/calls"
cat > "$TMP/bin/fake-mutation" <<'SH'
#!/bin/sh
# Fails while the running call count is <= FAIL_UNTIL, then succeeds. The
# counter lives in a file so it survives across the script's subprocess calls.
n=$(( $(cat "$CALLS") + 1 ))
echo "$n" > "$CALLS"
[ "$n" -gt "$FAIL_UNTIL" ]
SH
chmod +x "$TMP/bin/sleep" "$TMP/bin/fake-mutation"
export PATH="$TMP/bin:$PATH"
export CALLS

# Run the real script against the fake command; echo its exit status (so a
# non-zero exit in scenario B doesn't trip the test's own `set -e`).
run() {
  rc=0
  "$SCRIPT" fake-mutation >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# --- Scenario A: transient blip — fails twice, then succeeds. ----------------
echo 0 > "$CALLS"; export FAIL_UNTIL=2
rc="$(run)"
eq "$rc" "0" "transient: exits 0 (succeeds after retries, no escalation)"
eq "$(cat "$CALLS")" "3" "transient: stops at first success (3 attempts)"

# --- Scenario B: persistent failure — every attempt fails. -------------------
echo 0 > "$CALLS"; export FAIL_UNTIL=999
rc="$(run)"
eq "$rc" "1" "persistent: exits non-zero after budget exhausted (escalates)"
eq "$(cat "$CALLS")" "3" "persistent: bounded at exactly MAX_ATTEMPTS (GC_GRAPHQL_RETRY_MAX=3)"

# --- Scenario C: healthy — succeeds on the first attempt. --------------------
echo 0 > "$CALLS"; export FAIL_UNTIL=0
rc="$(run)"
eq "$rc" "0" "healthy: exits 0 on first attempt"
eq "$(cat "$CALLS")" "1" "healthy: no needless retries (1 attempt)"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
