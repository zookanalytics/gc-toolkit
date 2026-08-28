#!/usr/bin/env bash
# Thin wiring check: every escalation in the dog shutdown dance goes through
# assets/scripts/escalate.sh, and every one of those calls is rig-bound.
# The dog pool is city-scoped, so GC_RIG is normally unset; escalate.sh's
# default converse pool then renders bare, matches no rig-scoped agent
# identity, and is refused before anything is filed. An unbound call in this
# formula is a stop path that promises a human-visible visit and files none.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-dog-shutdown-dance.toml"
AGENT="$ROOT/agents/dog/agent.toml"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }
[ -s "$AGENT" ] || { echo "missing $AGENT" >&2; exit 1; }

# The premise the binding rests on. If the dog is ever re-scoped to a rig,
# GC_RIG arrives bound and the rest of this file needs rethinking, not muting.
grep -Eq '^scope[[:space:]]*=[[:space:]]*"city"' "$AGENT" \
  && ok "dog pool is city-scoped, so escalate.sh calls must name their rig" \
  || bad "agents/dog/agent.toml no longer declares scope = \"city\" — re-derive what these calls must bind"

grep -q 'escalate\.sh' "$TOML" \
  && ok "dog formula escalates through escalate.sh" \
  || bad "dog formula never references escalate.sh"

grep -q -- '--subject' "$TOML" && grep -q -- '--key' "$TOML" \
  && ok "escalate.sh calls carry --subject and --key (the dedup identity)" \
  || bad "escalate.sh calls must carry --subject and --key"

# A rig-qualified --pool is the other accepted form: escalate.sh adopts that
# pool's rig segment into GC_RIG for the whole run, so route and store agree.
UNBOUND=$(grep -n 'escalate\.sh' "$TOML" \
  | grep -v 'GC_RIG=' \
  | grep -Ev -- '--pool[[:space:]]+[A-Za-z0-9._-]+/' \
  | grep -E '\$SCRIPTS/escalate\.sh|escalate\.sh --')
if [ -n "$UNBOUND" ]; then
  bad "escalate.sh call sites with neither a GC_RIG binding nor a rig-qualified --pool:"
  printf '%s\n' "$UNBOUND" | sed 's/^/       /'
else
  ok "every escalate.sh call site is rig-bound or carries a rig-qualified --pool"
fi

# The binding is only as good as the value it carries: a rig segment read off
# the warrant's own route, falling back to the ambient rig.
grep -q 'ESC_RIG=' "$TOML" \
  && ok "the formula derives the escalation rig into ESC_RIG" \
  || bad "no ESC_RIG derivation — GC_RIG= on a call site binds nothing without it"

if grep -n 'gc mail send' "$TOML"; then
  bad "formula still contains a bare 'gc mail send' — escalations are visits now"
else
  ok "no bare 'gc mail send' anywhere in the formula"
fi

echo
echo "dog-escalation-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
