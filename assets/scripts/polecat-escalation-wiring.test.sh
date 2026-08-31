#!/usr/bin/env bash
# Thin wiring check: the polecat's two escalation tiers stay wired to the two
# things that can answer them. Mail carries a blocker to the witness, an agent
# peer that can resolve it; escalate.sh files a visit, which spends a human.
# The patrol-scoped ban on bare `gc mail send` (see witness-escalation-wiring
# .test.sh) does not reach the polecat: a patrol tops the agent tier with no
# peer to mail, a worker has one.
#
# The sender half is useless without the receiver half, so this pins both: the
# doctrine that tells the polecat to mail HELP, and the witness patrol step
# that triages it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
DOCTRINE="$ROOT/template-fragments/polecat-doctrine.template.md"
WITNESS="$ROOT/formulas/mol-witness-patrol.toml"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$DOCTRINE" ] || { echo "missing $DOCTRINE" >&2; exit 1; }
[ -s "$WITNESS" ]  || { echo "missing $WITNESS" >&2; exit 1; }

grep -qF 'gc mail send "${GC_RIG:+$GC_RIG/}{{ .BindingPrefix }}witness"' "$DOCTRINE" \
  && ok "doctrine mails the blocker to the binding-qualified witness address" \
  || bad "doctrine's witness address must carry the rig and binding prefixes; a bare <rig>/witness names no configured agent"

grep -q 'HELP:' "$DOCTRINE" \
  && ok "doctrine names the HELP: subject prefix the witness triages on" \
  || bad "doctrine dropped the HELP: prefix; witness triage keys on it"

if grep -qi 'mail budget is zero' "$DOCTRINE"; then
  bad "doctrine bans mail again — that routes worker blockers to a human"
else
  ok "doctrine does not ban mail outright"
fi

grep -q 'escalate\.sh' "$DOCTRINE" \
  && ok "doctrine keeps escalate.sh for what no agent can answer" \
  || bad "doctrine lost the direct-to-human tier"

grep -q -- '--subject' "$DOCTRINE" && grep -q -- '--key' "$DOCTRINE" \
  && ok "escalate.sh call carries --subject and --key (the dedup identity)" \
  || bad "escalate.sh call must carry --subject and --key"

grep -q 'HELP' "$WITNESS" && grep -q 'escalate\.sh' "$WITNESS" \
  && ok "witness patrol still triages HELP mail and promotes it to a visit" \
  || bad "witness patrol no longer receives what the doctrine tells polecats to send"

echo
echo "polecat-escalation-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
