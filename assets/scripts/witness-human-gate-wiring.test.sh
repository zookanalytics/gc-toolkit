#!/usr/bin/env bash
# Thin wiring check: the witness's findings go through
# assets/scripts/patrol-finding.sh (one durable bead per situation key, which a
# proactive first reaction then disposes), and assets/scripts/human-gate.sh
# stays available for the emergency that needs a person now, as a human gate on
# the bead it is about. A report with no bead that can wait is a finding. The
# prompt carries no `gc mail send`, because the po's mailbox is not an
# escalation channel.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
PROMPT="$ROOT/agents/witness/prompt.template.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$PROMPT" ] || { echo "missing $PROMPT" >&2; exit 1; }

# A blocker the witness cannot clear is a finding about the sender's bead.
# --about keeps two blocked polecats two findings instead of collapsing them
# into one, and --distinct files the second: patrol-finding.sh refuses a new
# bead whose key a live finding in its scope already carries about another
# subject.
HELP_CALL=$(grep 'patrol-finding\.sh" --scope witness-findings --key polecat-help ' "$PROMPT" || true)
case "$HELP_CALL" in
  *'--about '*'--distinct'*) ok "polecat-help is filed through patrol-finding.sh, scoped by --about and --distinct" ;;
  *) bad "the prompt's polecat-help finding must go through patrol-finding.sh with --about and --distinct" ;;
esac

# The emergency exit stays: a crash or a data loss is not a disposition.
grep -q 'human-gate\.sh" --subject <bead> --key ' "$PROMPT" \
  && ok "human-gate.sh is still reachable for an emergency" \
  || bad "the emergency path to a person is gone"

# Mail that reports shared state or asks for an act the witness may not take is
# a request with no other record. Archived as chatter, it is lost. The prompt
# makes the conversion a rule rather than a judgment, and gctk's mail finding
# tests hold the call that carries it.
grep -q 'is never chatter' "$PROMPT" \
  && ok "the prompt rules that a NOTICE is never chatter" \
  || bad "the prompt no longer rules a NOTICE out of chatter, so archiving one unfiled is a judgment again"
grep -q '"$GCTK" mail finding <mail id> --key <situation-key>' "$PROMPT" \
  && ok "a NOTICE becomes a finding through gctk mail finding" \
  || bad "the prompt lost the call that files a NOTICE as a finding"
grep -q 'reaping' "$PROMPT" && grep -q 'reconciling' "$PROMPT" \
  && ok "a request for an act the witness may not take is filed like a NOTICE" \
  || bad "the prompt no longer names reap and reconcile requests as findings"

# The witness may not close another agent's beads, so the request to do it
# needs a route onward. The prompt carries that next to the ban itself.
if awk '/Close another agent.s step beads/ {f=NR} f && NR <= f + 4 && /reap/ {r=1} f && NR <= f + 4 && /finding/ {n=1} END {exit !(r && n)}' "$PROMPT"; then
  ok "the witness prompt files a reap request as a finding, beside its ban on reaping"
else
  bad "the witness prompt's ban on closing another agent's beads no longer says where a reap request goes"
fi

if grep -n 'gc mail send' "$PROMPT"; then
  bad "the prompt contains a bare 'gc mail send': findings are beads"
else
  ok "no bare 'gc mail send' anywhere in the prompt"
fi

echo
echo "witness-human-gate-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
