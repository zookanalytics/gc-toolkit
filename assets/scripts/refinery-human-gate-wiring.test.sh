#!/usr/bin/env bash
# Thin wiring check: every human gate the refinery patrol files goes through
# assets/scripts/human-gate.sh (one open gate per bead and situation key), and
# the condition it reports with no bead of its own, a session started with an
# empty GC_AGENT, is a patrol finding: human-gate.sh refuses a session id. A
# bare `gc mail send` in the formula dedups nothing, and there is no mayor
# mailbox to absorb it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

# A call, not the resolver's `[ -x "$SCRIPTS/human-gate.sh" ]` probe.
CALLS=$(grep -n '"\$SCRIPTS/human-gate\.sh"' "$TOML" | grep -v -- '-x "\$SCRIPTS/human-gate\.sh"')
[ -n "$CALLS" ] \
  && ok "refinery patrol files human gates through human-gate.sh" \
  || bad "refinery patrol never calls human-gate.sh"

MISSING=$(printf '%s\n' "$CALLS" | grep -v -- '--subject' || true)
MISSING="$MISSING$(printf '%s\n' "$CALLS" | grep -v -- '--key' || true)"
[ -z "$MISSING" ] \
  && ok "every human-gate.sh call carries --subject and --key (one gate per bead and key)" \
  || { bad "human-gate.sh calls missing --subject or --key:"; printf '%s\n' "$MISSING" | sed 's/^/       /'; }


# The empty-identity check runs before the refinery has any bead in hand, and
# the only id it holds names a session, so its report is a patrol finding.
IDENT=$(awk '/^title = "Validate canonical agent identity"$/ {f=1} f && /^\[\[steps\]\]$/ {exit} f' "$TOML")
case "$IDENT" in
  *'patrol-finding.sh" --scope refinery-findings --key refinery-empty-identity'*)
    ok "the empty-identity check files a patrol finding" ;;
  *) bad "the empty-identity check no longer files a refinery-empty-identity patrol finding" ;;
esac
case "$IDENT" in
  *human-gate.sh*) bad "the empty-identity check files a human gate; the session id it holds names no bead that can wait" ;;
  *) ok "the empty-identity check files no human gate on a session" ;;
esac

if grep -n 'gc mail send' "$TOML"; then
  bad "formula still contains a bare 'gc mail send' — a person is asked through a human gate"
else
  ok "no bare 'gc mail send' anywhere in the formula"
fi

echo
echo "refinery-human-gate-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
