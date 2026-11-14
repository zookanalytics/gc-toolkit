#!/usr/bin/env bash
# po-prime-cap.test.sh — the po's prime arrives whole when a sitting starts.
#
# The operator's attach starts the po, and a session that an attach starts takes
# its prime as session-start hook context. Claude Code keeps hook context of up
# to 10,000 characters inline and saves a longer one to a file, leaving the
# session a 2 KB preview, so a po whose prime outgrew that cap would open a
# sitting knowing only its first lines. The seed audit's render of the po is the
# prime gc delivers, less the one header line gc prime puts first. Its inputs
# include the operator profile, which the learning distiller grows, so a
# promotion that pushes the prime over the cap fails here, at its own PR.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
RENDER="generated/seed-audit/agents/po.md"
INPUTS=(agents/po/prompt.template.md template-fragments/ask-for-work.template.md template-fragments/operator-profile.template.md template-fragments/where-to-search.template.md)
CAP=10000
# gc prime's header names the city, the agent and the time, and the margin
# keeps a long city or rig name inside the cap.
HEADER_ALLOWANCE=200

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

for f in "${INPUTS[@]}"; do
  [ -f "$ROOT/$f" ] && ok "the render's input $f exists" \
    || bad "the render's input $f exists" "missing: the po's prime no longer composes it, so this suite's list is stale"
done
for f in "${INPUTS[@]:1}"; do
  name="${f#template-fragments/}"; name="${name%.template.md}"
  grep -q "template \"$name\"" "$ROOT/agents/po/prompt.template.md" \
    && ok "the po's prompt composes $name" \
    || bad "the po's prompt composes $name" "the prompt no longer includes it, so drop it from INPUTS"
done

if [ ! -f "$ROOT/$RENDER" ]; then
  bad "the po has a seed audit render" "missing $RENDER: run assets/scripts/render-seed-audit.sh"
else
  chars=$(LC_ALL=en_US.UTF-8 wc -m < "$ROOT/$RENDER" | tr -d ' ')
  limit=$((CAP - HEADER_ALLOWANCE))
  if [ "$chars" -le "$limit" ]; then
    ok "the po's prime is $chars characters, inside the $CAP-character session-start cap"
  else
    bad "the po's prime fits the $CAP-character session-start cap" \
      "$RENDER is $chars characters, over $limit: move procedure into the backlog-refinement skill or drop a fragment"
  fi
fi

printf '\npo-prime-cap: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
