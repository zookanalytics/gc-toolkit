#!/usr/bin/env bash
# mayor-prompt.test.sh — the commands the mayor's prime gives it run as
# written, each in a fresh shell, since a variable one tool call sets does not
# reach the next.
#
#   1. Every pack script the prime calls is found in the call itself, by
#      "$(gc <binding> scripts-dir)/<script>".
#
# Hermetic: reads the render the seed audit commits.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# The prompt and its render, named whole so that a change to either runs this
# suite (tools/run-tests.sh).
PROMPT="$ROOT/agents/mayor/prompt.template.md"
RENDER="$ROOT/generated/seed-audit/agents/mayor.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

[ -f "$PROMPT" ] && [ -f "$RENDER" ] || { echo "mayor-prompt: the prompt or its render is missing" >&2; exit 1; }

echo "── 1. each script call finds its script ──"
calls=$(grep -o -E '"[^"`]*/[A-Za-z0-9_-]+\.sh"' "$RENDER" || true)
[ -n "$calls" ] && ok "the prime calls pack scripts" \
  || bad "the prime calls pack scripts" "no quoted call to a .sh in $RENDER, so this suite reads nothing"
loose=$(printf '%s\n' "$calls" | grep -v -E '^"\$\(gc [A-Za-z0-9_.-]+ scripts-dir\)/[A-Za-z0-9_-]+\.sh"$' || true)
[ -z "$loose" ] && ok "every call resolves the scripts directory in the call itself" \
  || bad "every call resolves the scripts directory in the call itself" "$loose"

printf '\nmayor-prompt: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
