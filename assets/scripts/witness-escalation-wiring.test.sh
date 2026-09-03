#!/usr/bin/env bash
# Thin wiring check: the witness patrol's findings go through
# assets/scripts/patrol-finding.sh (one durable bead per situation key, which a
# proactive first reaction then disposes), and escalate.sh stays available for
# the emergency that needs a human now. A bare `gc mail send` in the formula is
# the escalation-storm surface coming back — there is no mayor mailbox to
# absorb it, and mail dedups nothing.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-witness-patrol.toml"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

grep -q 'patrol-finding\.sh' "$TOML" \
  && ok "witness patrol files findings through patrol-finding.sh" \
  || bad "witness patrol never references patrol-finding.sh"

grep -q -- '--key' "$TOML" \
  && ok "the calls carry --key (the dedup identity)" \
  || bad "patrol-finding.sh calls must carry --key"

# Every per-bead finding shares one key across beads, so --about is what keeps
# two stuck beads two findings instead of collapsing them into one.
for k in witness-salvage-refused witness-partial-release witness-refinery-queue \
         witness-crash-loop polecat-help; do
  if grep -A2 -- "--key $k" "$TOML" | grep -q -- '--about'; then
    ok "$k is scoped by --about, so two beads are two findings"
  else
    bad "$k names no --about; every bead with that key would be one finding"
  fi
done

# The emergency exit stays: a crash or a data loss is not a disposition.
grep -q 'escalate\.sh' "$TOML" \
  && ok "escalate.sh is still reachable for an emergency" \
  || bad "the emergency escalation path is gone"

if grep -n 'gc mail send' "$TOML"; then
  bad "formula still contains a bare 'gc mail send' — findings are beads now"
else
  ok "no bare 'gc mail send' anywhere in the formula"
fi

echo
echo "witness-escalation-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
