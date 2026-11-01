#!/usr/bin/env bash
# Thin wiring check: the dog shutdown dance asks a person through a human gate
# on its warrant, filed with assets/scripts/human-gate.sh, and reports what
# nothing waits on as a patrol finding. The gate lands in the warrant's own
# store because `gc bd` runs a gate create in the store of the bead it blocks,
# so the dance derives no store for it. The malformed-warrant report is filed
# after the warrant closes refused, and a gate on a closed bead would hold
# nothing, so that report is a patrol finding that names the warrant. Its rig
# binding is patrol-finding-binding.test.sh's to pin.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-dog-shutdown-dance.toml"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

# A call, not the resolver's `[ -x "$SCRIPTS/human-gate.sh" ]` probe.
CALLS=$(grep -n '"\$SCRIPTS/human-gate\.sh"' "$TOML" | grep -v -- '-x "\$SCRIPTS/human-gate\.sh"')
[ -n "$CALLS" ] \
  && ok "the dance files its human gate through human-gate.sh" \
  || bad "the dance never calls human-gate.sh"

# Every gate the dance files blocks the warrant, the one bead the dance holds.
OFF=$(printf '%s\n' "$CALLS" | grep -v -- '--subject "\$warrant_id" --key' || true)
[ -z "$OFF" ] \
  && ok "every human-gate.sh call blocks the warrant under a --key" \
  || { bad "human-gate.sh calls whose subject is not the warrant:"; printf '%s\n' "$OFF" | sed 's/^/       /'; }

if grep -n -e 'escalation-rig' -e 'ESC_RIG' "$TOML"; then
  bad "the dance still derives a store for its gate; gc bd files the gate beside the warrant it blocks"
else
  ok "the dance derives no store for its gate"
fi


# The malformed path closes the warrant refused, then reports it.
MALFORMED=$(awk '/if \[ -z "\$target" \] \|\| \[ -z "\$reason" \]; then/ {f=1} f {print} f && /^fi$/ {exit}' "$TOML")
case "$MALFORMED" in
  *'--status=closed'*'patrol-finding.sh" --scope dog-findings --key "dog-malformed-warrant.$warrant_id"'*)
    ok "the malformed path closes the warrant, then files a patrol finding that names it" ;;
  *) bad "the malformed path no longer closes the warrant and then files its dog-malformed-warrant finding" ;;
esac
case "$MALFORMED" in
  *human-gate.sh*) bad "the malformed path files a human gate on a warrant it has closed" ;;
  *) ok "the malformed path files no human gate on the closed warrant" ;;
esac

if grep -n 'gc mail send' "$TOML"; then
  bad "formula still contains a bare 'gc mail send' — a person is asked through a human gate"
else
  ok "no bare 'gc mail send' anywhere in the formula"
fi

echo
echo "dog-human-gate-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
