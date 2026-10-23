#!/usr/bin/env bash
# Thin wiring check: the polecat's two tiers for blocked work stay wired to the
# two things that can answer them. Mail carries a blocker to the witness, an
# agent peer that can resolve it; human-gate.sh files a human gate on the work
# bead, which spends a person. The patrol-scoped ban on bare `gc mail send`
# (see witness-human-gate-wiring.test.sh) does not reach the polecat: a patrol
# tops the agent tier with no peer to mail, a worker has one.
#
# A decline is not a blocker to mail, though: it cancels the run, so it must
# leave a tracked record first. This also pins that the decline path files a
# human gate and records the wait before run-cancel.sh runs, never bare mail
# behind a cancel, which would leave work nothing re-offers and no query
# returns. A decline is an event of its run, so its gate declares no quiet
# window.
#
# The sender half is useless without the receiver half, so this pins both: the
# doctrine that tells the polecat to mail HELP or NOTICE, and the witness patrol
# step that triages it.
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

CALLS=$(grep -n '"\$SCRIPTS/human-gate\.sh"' "$DOCTRINE")
[ -n "$CALLS" ] \
  && ok "doctrine keeps human-gate.sh for what no agent can answer" \
  || bad "doctrine lost the direct-to-person tier"

grep -q -- '--subject' "$DOCTRINE" && grep -q -- '--key' "$DOCTRINE" \
  && ok "human-gate.sh call carries --subject and --key (one gate per bead and key)" \
  || bad "human-gate.sh call must carry --subject and --key"

if grep -n 'escalate\.sh' "$DOCTRINE"; then
  bad "doctrine still names escalate.sh; the helper is human-gate.sh"
else
  ok "doctrine names the helper by its name, human-gate.sh"
fi

if printf '%s\n' "$CALLS" | grep -q -e '--quiet-window' -e 'GC_ESCALATE_VERDICT_WINDOW'; then
  bad "a doctrine call declares a quiet window; a decline is an event of its run, and a window would mute the next one"
else
  ok "no doctrine call declares a quiet window"
fi

# A decline files the gate FIRST, records the wait on the work bead next, and
# gates the cancel on both: human-gate.sh, then await-ruling.sh, then
# run-cancel.sh, within one block. A cancelled run therefore always leaves a
# tracked record a query returns, and never lands behind bare mail (mail reaches
# an agent peer, not the record).
if awk '/human-gate\.sh.*--key/{e=NR} /await-ruling\.sh.*--key/{if(e&&NR>e)a=NR} /run-cancel\.sh.*--step/{if(e&&a&&NR>a&&NR-e<=8)f=1} END{exit !f}' "$DOCTRINE"; then
  ok "the cancel is gated on a filed human gate and a recorded wait (human-gate, await-ruling, run-cancel)"
else
  bad "a decline must run human-gate.sh, then await-ruling.sh, then run-cancel.sh; a cancel behind bare mail leaves work nothing re-offers"
fi
if grep -q 'molecule-hold' "$DOCTRINE"; then
  bad "the doctrine still teaches molecule-hold.sh; a molecule's lifecycle is gascity's, so a decline cancels the run"
else
  ok "the doctrine teaches no molecule hold"
fi

# The witness answers HELP mail it can, and files the rest as a polecat-help
# finding whose first reaction puts it to a person when one is needed.
grep -q 'HELP' "$WITNESS" && grep -q -- '--key polecat-help' "$WITNESS" \
  && ok "witness patrol still triages HELP mail and files what it cannot answer as a finding" \
  || bad "witness patrol no longer receives what the doctrine tells polecats to send"

# A NOTICE reports a fact the sender does not own. The witness files every one
# as a finding, so a notice the doctrine sends always reaches a tracked record.
grep -q 'NOTICE:' "$DOCTRINE" && grep -q '# >>> notice-finding' "$WITNESS" \
  && ok "the doctrine's NOTICE: mail has a receiver that files it as a finding" \
  || bad "the doctrine sends NOTICE: mail that the witness patrol no longer files"

echo
echo "polecat-human-gate-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
