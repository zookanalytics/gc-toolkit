#!/usr/bin/env bash
# mechanik-prime-cap.test.sh — the mechanik's prime arrives whole however its
# session starts.
#
# gc delivers a prime as a session's first message when the controller starts
# the session, and as session-start hook context when it delivers no first
# message, as for a session an attach starts. Claude Code keeps a hook string of
# up to 10,000 characters inline and saves a longer one to a file, leaving the
# session a 2,000-character preview it is never asked to read past. So a
# mechanik whose prime outgrew that cap would open knowing only its first
# lines.
#
# The hook string is the prime with gc prime's header line before it and the
# unread-mail notice after it, and the live prime spells out the pack, city and
# home paths that the seed audit's render writes as short placeholders or
# leaves empty. ALLOWANCE covers those three for this city's paths and a
# notice of one or two messages. The render's inputs include the operator
# profile and the mechanik's learned conventions, which the learning distiller
# grows, so a promotion that pushes the prime over the cap fails here, at its
# own PR.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PROMPT="agents/mechanik/prompt.template.md"
RENDER="generated/seed-audit/agents/mechanik.md"
FRAGMENTS=(template-fragments/ask-for-work.template.md template-fragments/operator-profile.template.md template-fragments/learned-conventions-mechanik.template.md)
CAP=10000
ALLOWANCE=600

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

[ -f "$ROOT/$PROMPT" ] || { echo "missing $PROMPT" >&2; exit 1; }

# The fragments listed are the ones the prompt composes, so an edit to any of
# them runs this suite, and a fragment the prompt starts composing is weighed
# against the cap when it is added.
for f in "${FRAGMENTS[@]}"; do
  name="${f#template-fragments/}"; name="${name%.template.md}"
  if [ ! -f "$ROOT/$f" ]; then
    bad "the render's input $f exists" "missing: drop it from FRAGMENTS if the prompt no longer composes it"
  elif grep -q "template \"$name\"" "$ROOT/$PROMPT"; then
    ok "the mechanik's prompt composes $name"
  else
    bad "the mechanik's prompt composes $name" "the prompt no longer includes it, so drop it from FRAGMENTS"
  fi
done
listed=" ${FRAGMENTS[*]} "
for name in $(grep -oE '\{\{-? *template "[^"]+"' "$ROOT/$PROMPT" | sed -E 's/.*"([^"]+)"/\1/' | sort -u); do
  case "$listed" in
    *" template-fragments/$name.template.md "*) ok "$name is among the inputs this suite weighs" ;;
    *) bad "$name is among the inputs this suite weighs" "the prompt composes $name: weigh it against the cap and add it to FRAGMENTS" ;;
  esac
done

if [ ! -f "$ROOT/$RENDER" ]; then
  bad "the mechanik has a seed audit render" "missing $RENDER: run assets/scripts/render-seed-audit.sh"
else
  chars=$(LC_ALL=en_US.UTF-8 wc -m < "$ROOT/$RENDER" | tr -d ' ')
  limit=$((CAP - ALLOWANCE))
  if [ "$chars" -le "$limit" ]; then
    ok "the mechanik's prime is $chars characters, inside the $CAP-character session-start cap"
  else
    bad "the mechanik's prime fits the $CAP-character session-start cap" \
      "$RENDER is $chars characters, over $limit: move procedure into the skill that owns it, or retire an entry"
  fi
fi

printf '\nmechanik-prime-cap: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
