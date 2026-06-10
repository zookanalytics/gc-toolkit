#!/usr/bin/env bash
# Hermetic test for the retry_graphql() helper in
# template-fragments/polecat-non-impl-done.template.md.
#
# The codex pre-publish review gate un-drafts an approved PR with
# `gh pr ready` — a GitHub GraphQL mutation (markPullRequestReadyForReview)
# that can transiently fail (a flaky 401 / timeout / 5xx) and strand a
# fully-reviewed PR in draft. retry_graphql wraps such mutations in bounded
# backoff so a self-healing blip no longer escalates, while a genuinely
# persistent failure still does.
#
# This test extracts the helper straight from the fragment (single source of
# truth — if the fragment changes shape, this fails loudly) and exercises it
# against a fake command. No live city, Dolt, network, or real `gh`.
#
# Asserts the Verify contract from tk-3yrll:
#   - retry-then-succeed: the un-draft eventually wins -> no escalation
#   - retry-exhausted:    every attempt fails          -> escalation
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAGMENT="$HERE/polecat-non-impl-done.template.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

# --- Extract retry_graphql() from the fragment (single source of truth). ------
awk '/^retry_graphql\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$FRAGMENT" \
  > "$TMP/retry_graphql.sh"
[ -s "$TMP/retry_graphql.sh" ] \
  || { echo "FAIL - could not extract retry_graphql() from fragment"; exit 1; }

# Stub sleep so the backoff doesn't slow the test, then load the helper.
sleep() { :; }
# shellcheck disable=SC1091
. "$TMP/retry_graphql.sh"

# --- Fake mutation: fails the first FAIL_UNTIL calls, then succeeds. ----------
# The call counter lives in a file so it survives the command-substitution
# subshell that run_arm executes in.
CALLS_FILE="$TMP/calls"
FAIL_UNTIL=0
fake_gh() {
  _fk_n=$(( $(cat "$CALLS_FILE") + 1 ))
  echo "$_fk_n" > "$CALLS_FILE"
  [ "$_fk_n" -gt "$FAIL_UNTIL" ]   # non-zero (fail) while n <= FAIL_UNTIL
}

# Mirror the fragment's APPROVE|COMMENT arm: success -> un-draft (no escalate);
# failure after the retry budget -> escalate.
run_arm() {
  if retry_graphql fake_gh; then echo UNDRAFT_OK; else echo ESCALATE; fi
}

# --- Scenario A: transient blip — fails twice, then succeeds. -----------------
echo 0 > "$CALLS_FILE"; FAIL_UNTIL=2
out="$(run_arm 2>"$TMP/stderr")"
eq "$out" "UNDRAFT_OK" "retry-then-succeed: un-drafts, no escalation"
eq "$(cat "$CALLS_FILE")" "3" "retry-then-succeed: stops at first success (3 attempts)"

# --- Scenario B: persistent failure — every attempt fails. -------------------
echo 0 > "$CALLS_FILE"; FAIL_UNTIL=999
out="$(run_arm 2>"$TMP/stderr")"
eq "$out" "ESCALATE" "retry-exhausted: escalates"
eq "$(cat "$CALLS_FILE")" "5" "retry-exhausted: bounded at exactly 5 attempts"

# --- Scenario C: healthy — succeeds on the first attempt. --------------------
echo 0 > "$CALLS_FILE"; FAIL_UNTIL=0
out="$(run_arm 2>"$TMP/stderr")"
eq "$out" "UNDRAFT_OK" "healthy: un-drafts on first attempt"
eq "$(cat "$CALLS_FILE")" "1" "healthy: no needless retries (1 attempt)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
