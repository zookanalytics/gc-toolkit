#!/usr/bin/env bash
# seat-prime-cap.test.sh — the prime of each seat the operator opens, the po and
# the mayor, arrives whole when a sitting starts.
#
# The operator's attach starts the seat, and a session that an attach starts
# takes its prime as session-start hook context. Claude Code keeps hook context
# of up to 10,000 characters inline and saves a longer one to a file, leaving
# the session a 2 KB preview, so a seat whose prime outgrew that cap would open
# a sitting knowing only its first lines. The seed audit's render of a seat is
# the prime gc delivers, less the one header line gc prime puts first. Its
# inputs include the operator profile, which the learning distiller grows, so a
# promotion that pushes a prime over the cap fails here, at its own PR.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# Each seat with its prompt and its render, named whole so that a change to
# either runs this suite (tools/run-tests.sh).
SEATS=(
  "po agents/po/prompt.template.md generated/seed-audit/agents/po.md"
  "mayor agents/mayor/prompt.template.md generated/seed-audit/agents/mayor.md"
)
FRAGMENTS=(template-fragments/ask-for-work.template.md template-fragments/operator-profile.template.md template-fragments/where-to-search.template.md)
CAP=10000
# gc prime's header names the city, the agent and the time, and the margin
# keeps a long city or rig name inside the cap.
HEADER_ALLOWANCE=200

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

for f in "${FRAGMENTS[@]}"; do
  [ -f "$ROOT/$f" ] && ok "the renders' input $f exists" \
    || bad "the renders' input $f exists" "missing: the seats' primes no longer compose it, so this suite's list is stale"
done

for row in "${SEATS[@]}"; do
  read -r seat prompt render <<<"$row"
  if [ ! -f "$ROOT/$prompt" ]; then
    bad "the $seat's prompt $prompt exists" "missing: the seat is gone, so drop it from SEATS"
    continue
  fi
  for f in "${FRAGMENTS[@]}"; do
    name="${f#template-fragments/}"; name="${name%.template.md}"
    grep -q "template \"$name\"" "$ROOT/$prompt" \
      && ok "the $seat's prompt composes $name" \
      || bad "the $seat's prompt composes $name" "the prompt no longer includes it, so this suite's list is stale"
  done
  if [ ! -f "$ROOT/$render" ]; then
    bad "the $seat has a seed audit render" "missing $render: run assets/scripts/render-seed-audit.sh"
    continue
  fi
  chars=$(LC_ALL=en_US.UTF-8 wc -m < "$ROOT/$render" | tr -d ' ')
  limit=$((CAP - HEADER_ALLOWANCE))
  if [ "$chars" -le "$limit" ]; then
    ok "the $seat's prime is $chars characters, inside the $CAP-character session-start cap"
  else
    bad "the $seat's prime fits the $CAP-character session-start cap" \
      "$render is $chars characters, over $limit: move procedure into a skill or drop a fragment"
  fi
done

printf '\nseat-prime-cap: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
