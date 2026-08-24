#!/usr/bin/env bash
# Thin wiring check: every escalation in the witness patrol goes through
# assets/scripts/escalate.sh (one open visit per situation key). A bare
# `gc mail send` in the formula is the escalation-storm surface coming back —
# there is no mayor mailbox to absorb it, and mail dedups nothing.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-witness-patrol.toml"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

grep -q 'escalate\.sh' "$TOML" \
  && ok "witness patrol escalates through escalate.sh" \
  || bad "witness patrol never references escalate.sh"

grep -q -- '--subject' "$TOML" && grep -q -- '--key' "$TOML" \
  && ok "escalate.sh calls carry --subject and --key (the dedup identity)" \
  || bad "escalate.sh calls must carry --subject and --key"

if grep -n 'gc mail send' "$TOML"; then
  bad "formula still contains a bare 'gc mail send' — escalations are visits now"
else
  ok "no bare 'gc mail send' anywhere in the formula"
fi

echo
echo "witness-escalation-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
