#!/usr/bin/env bash
# Thin wiring check: every role that files human gates outside a sitting
# composes the human-gate-withdraw fragment, and the command that fragment
# teaches stays runnable against human-gate.sh. A gate closed with a bare
# `gc bd close` carries no resolve reason, so the board reads it as a need
# nobody met. The fragment is what tells a role other than converse to withdraw
# its own gate through human-gate.sh --retract, and to leave another role's gate
# for a person.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
FRAG="$ROOT/template-fragments/human-gate-withdraw.template.md"
HG="$HERE/human-gate.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

for f in "$FRAG" "$HG"; do
  [ -s "$f" ] || { echo "missing $f" >&2; exit 1; }
done

grep -qE '\{\{-? *define "human-gate-withdraw" *-?\}\}' "$FRAG" \
  && ok "the fragment defines human-gate-withdraw" \
  || bad "template-fragments/human-gate-withdraw.template.md does not define \"human-gate-withdraw\""

for role in witness deacon refinery proactive mechanik; do
  P="$ROOT/agents/$role/prompt.template.md"
  [ -s "$P" ] || { bad "missing $P"; continue; }
  if grep -qE '\{\{-? *template "human-gate-withdraw" \. *-?\}\}' "$P"; then
    ok "$role composes human-gate-withdraw"
  else
    bad "$role does not compose human-gate-withdraw, so nothing tells it how to withdraw its own gate"
  fi
done

# A prompt that still includes the fragment's old name renders nothing there,
# so its role loses the instruction without an error.
STALE=$(grep -lE '\{\{-? *template "visit-close"' "$ROOT"/agents/*/prompt.template.md "$ROOT"/template-fragments/*.template.md 2>/dev/null || true)
[ -z "$STALE" ] \
  && ok "no prompt or fragment includes the fragment by its old name" \
  || bad "these still include \"visit-close\": $STALE"

# What an agent runs is the fragment's fenced shell, not its prose, which names
# the bare close only to rule it out.
CODE=$(awk '/^```/ { inb = !inb; next } inb' "$FRAG")
[ -n "$CODE" ] || bad "the fragment carries no fenced shell"

if printf '%s\n' "$CODE" | grep -qE 'bd close|--status[= ]closed|gate resolve'; then
  bad "the fragment's shell closes or resolves a gate itself"
else
  ok "the fragment's shell runs no bare close or resolve"
fi

# Every flag the fragment passes human-gate.sh is one it parses, so a renamed
# flag fails here rather than in an agent's hands.
LINE=$(printf '%s\n' "$CODE" | grep -F '"$SCRIPTS/human-gate.sh"')
if [ -z "$LINE" ]; then
  bad "the fragment no longer calls human-gate.sh"
else
  N=0
  for f in $(printf '%s\n' "$LINE" | grep -oE -- '--[a-z][a-z-]*' | sort -u); do
    N=$((N + 1))
    if grep -qE -- "^[[:space:]]*$f\)" "$HG"; then
      ok "human-gate.sh parses $f"
    else
      bad "human-gate.sh does not parse $f, which the fragment passes it"
    fi
  done
  [ "$N" -gt 0 ] || bad "the fragment calls human-gate.sh with no flags"
  case "$LINE" in
    *--retract*) ok "the fragment's call is a withdrawal, not a filing" ;;
    *) bad "the fragment's human-gate.sh call does not pass --retract" ;;
  esac
fi

if grep -nE 'escalate\.sh|visit-close\.sh' "$FRAG"; then
  bad "the fragment names a retired writer"
else
  ok "the fragment names human-gate.sh alone"
fi

# What the fragment says the withdrawal does is what human-gate.sh's retract arm
# does: each open gate under the key is resolved with a moot: reason, and a gate
# a person already cleared keeps that person's answer.
RETRACT=$(sed -n '/^# >>> retract-moot/,/^# <<< retract-moot/p' "$HG")
case "$RETRACT" in
  *'REASON="moot: $MESSAGE"'*) ok "human-gate.sh's withdrawal resolves with a moot: reason" ;;
  *) bad "human-gate.sh's withdrawal no longer resolves with 'moot: <message>'; the fragment's guidance is stale" ;;
esac
case "$RETRACT" in
  *'its answer stands'*) ok "human-gate.sh's withdrawal keeps the answer of a gate a person already cleared" ;;
  *) bad "human-gate.sh's withdrawal no longer reports an earlier answer as standing; the fragment's guidance is stale" ;;
esac

# The fragment says a moot: reason starts a quiet period only where the call
# site declares one. That is human-gate.sh's window: off unless --quiet-window
# is given, and keyed on moot: and benign: answers alone.
grep -qF 'if [ -n "$QUIET_WINDOW" ] && [ "$QUIET_WINDOW" -gt 0 ]; then' "$HG" \
  && ok "human-gate.sh keeps a quiet period only for a call that declares one" \
  || bad "human-gate.sh's quiet window is no longer off by default; the fragment's guidance is stale"
grep -qF 'test("^(moot|benign):")' "$HG" \
  && ok "human-gate.sh's quiet window still answers to moot: and benign: alone" \
  || bad "human-gate.sh's quiet-window words changed; the fragment's guidance is stale"

echo
echo "human-gate-withdraw-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
