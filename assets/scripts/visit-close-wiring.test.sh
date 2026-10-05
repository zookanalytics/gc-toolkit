#!/usr/bin/env bash
# Thin wiring check: every role that raises visits outside a sitting composes
# the visit-close fragment, and the commands that fragment teaches stay runnable
# against the two writers it names. A visit closed with a bare `gc bd close`
# records no gc.outcome, so the board reads the finished sitting as a dropped
# need and doctor/check-visit-outcome-recorded flags it. The fragment is what
# tells a role other than converse to close through escalate.sh --retract or
# visit-close.sh instead.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
FRAG="$ROOT/template-fragments/visit-close.template.md"
VC="$HERE/visit-close.sh"
ESC="$HERE/escalate.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

for f in "$FRAG" "$VC" "$ESC"; do
  [ -s "$f" ] || { echo "missing $f" >&2; exit 1; }
done

grep -qE '\{\{-? *define "visit-close" *-?\}\}' "$FRAG" \
  && ok "the fragment defines visit-close" \
  || bad "template-fragments/visit-close.template.md does not define \"visit-close\""

for role in witness deacon refinery proactive mechanik; do
  P="$ROOT/agents/$role/prompt.template.md"
  [ -s "$P" ] || { bad "missing $P"; continue; }
  if grep -qE '\{\{-? *template "visit-close" \. *-?\}\}' "$P"; then
    ok "$role composes visit-close"
  else
    bad "$role does not compose visit-close, so nothing tells it how to close a visit"
  fi
done

# What an agent runs is the fragment's fenced shell, not its prose, which names
# the bare close only to rule it out.
CODE=$(awk '/^```/ { inb = !inb; next } inb' "$FRAG")
[ -n "$CODE" ] || bad "the fragment carries no fenced shell"

if printf '%s\n' "$CODE" | grep -qE 'bd close|--status[= ]closed'; then
  bad "the fragment's shell runs a bare close"
else
  ok "the fragment's shell runs no bare close"
fi

# Every flag the fragment passes a writer is one that writer parses, so a
# renamed flag fails here rather than in an agent's hands.
check_flags() { # <writer> <script>
  local line f n=0
  line=$(printf '%s\n' "$CODE" | grep -F "\"\$SCRIPTS/$1\"")
  [ -n "$line" ] || { bad "the fragment no longer calls $1"; return; }
  for f in $(printf '%s\n' "$line" | grep -oE -- '--[a-z][a-z-]*' | sort -u); do
    n=$((n + 1))
    if grep -qE -- "^[[:space:]]*$f\)" "$2"; then
      ok "$1 parses $f"
    else
      bad "$1 does not parse $f, which the fragment passes it"
    fi
  done
  [ "$n" -gt 0 ] || bad "the fragment calls $1 with no flags"
}
check_flags visit-close.sh "$VC"
check_flags escalate.sh "$ESC"

printf '%s\n' "$CODE" | grep -F '"$SCRIPTS/escalate.sh"' | grep -q -- '--retract' \
  && ok "the escalation arm is a retract, not a filing" \
  || bad "the fragment's escalate.sh call does not pass --retract"

# The fragment tells agents that moot and benign mute a repeat escalation and
# no other word does; that is escalate.sh's verdict-window filter.
if grep -qF '(.outcome == "moot" or .outcome == "benign")' "$ESC"; then
  ok "escalate.sh's verdict window still mutes on moot and benign alone"
else
  bad "escalate.sh's verdict-window words changed; the fragment's word guidance is stale"
fi

echo
echo "visit-close-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
