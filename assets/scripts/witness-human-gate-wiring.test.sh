#!/usr/bin/env bash
# Thin wiring check: the witness patrol's findings go through
# assets/scripts/patrol-finding.sh (one durable bead per situation key, which a
# proactive first reaction then disposes), and assets/scripts/human-gate.sh
# stays available for the emergency that needs a person now, as a human gate on
# the bead it is about. A report with no bead that can wait is a finding. A bare
# `gc mail send` in the formula dedups nothing, and there is no mayor mailbox to
# absorb it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-witness-patrol.toml"
PROMPT="$ROOT/agents/witness/prompt.template.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }
[ -s "$PROMPT" ] || { echo "missing $PROMPT" >&2; exit 1; }

grep -q 'patrol-finding\.sh' "$TOML" \
  && ok "witness patrol files findings through patrol-finding.sh" \
  || bad "witness patrol never references patrol-finding.sh"

grep -q -- '--key' "$TOML" \
  && ok "the calls carry --key (the dedup identity)" \
  || bad "patrol-finding.sh calls must carry --key"

# Every per-bead finding shares one key across beads, so --about is what keeps
# two stuck beads two findings instead of collapsing them into one. And
# --distinct is what files the second: patrol-finding.sh refuses a new bead
# whose key a live finding in its scope already carries about another subject.
for k in witness-salvage-refused witness-partial-release \
         witness-crash-loop polecat-help; do
  if grep -A2 -- "--key $k" "$TOML" | grep -q -- '--about'; then
    ok "$k is scoped by --about, so two beads are two findings"
  else
    bad "$k names no --about; every bead with that key would be one finding"
  fi
  if grep -A2 -- "--key $k" "$TOML" | grep -q -- '--distinct'; then
    ok "$k passes --distinct, so a second bead's finding files while the first is live"
  else
    bad "$k omits --distinct; patrol-finding.sh refuses its second subject while the first is live"
  fi
done

# witness-refinery-queue is the deliberate exception. check-refinery's
# refinery-stuck-handoff block files it through human-gate.sh, not
# patrol-finding.sh: a handoff still assigned and unprepared past the stuck
# bound is a bead a person must look at now, not a routine observation the
# reaction triages. The gate blocks the handoff, and human-gate.sh keeps one open
# gate per bead and key, so two stuck handoffs are still two gates.
if grep -Eq 'human-gate\.sh" --subject "\$SID" --key witness-refinery-queue ' "$TOML"; then
  ok "witness-refinery-queue is a human gate on the stuck handoff, not a finding"
else
  bad "witness-refinery-queue is no longer a human-gate.sh gate on the stuck handoff"
fi

# The emergency exit stays: a crash or a data loss is not a disposition.
grep -q 'human-gate\.sh' "$TOML" \
  && ok "human-gate.sh is still reachable for an emergency" \
  || bad "the emergency path to a person is gone"

# A report nothing waits on, or about a bead the witness cannot block, is a
# patrol finding: the check-refinery monitor that cannot see its queue (the
# patrol's run is a wisp, which human-gate.sh refuses), an orphan whose work
# landed (the witness closes that bead next, and a gate on it would refuse the
# close), and an owner whose store cannot be named (a gate lands in its bead's
# store). None of them is filed as a human gate.
# A key filed per bead carries the bead after a dot (witness-unplaceable-owner.<bead>),
# so the match takes the key followed by a space or by `.<bead>`.
for k in witness-refinery-queue-unroutable witness-refinery-queue-unreadable \
         witness-orphan-work-landed witness-unplaceable-owner; do
  if grep -A1 -- 'patrol-finding\.sh.*--scope witness-findings --key *$' "$TOML" | grep -qE -- "^$k( |\.<bead> )" \
     || grep -q -- "patrol-finding\.sh\"* --scope witness-findings --key $k" "$TOML"; then
    ok "$k is filed as a patrol finding"
  else
    bad "$k is no longer filed through patrol-finding.sh"
  fi
  if grep -q -- "human-gate\.sh.*--key $k" "$TOML"; then
    bad "$k is filed as a human gate; nothing it names can wait on one"
  else
    ok "$k files no human gate"
  fi
done

# Mail that reports shared state or asks for an act the witness may not take is
# a request with no other record. Archived as chatter, it is lost. The
# check-inbox step makes the conversion a rule rather than a judgment, and
# notice-finding.test.sh executes the block that carries it.
INBOX=$(awk '/^id = "check-inbox"$/ {f=1} f && /^\[\[steps\]\]$/ {exit} f' "$TOML")
case "$INBOX" in
  *'A `NOTICE:` is never chatter.'*) ok "check-inbox rules that a NOTICE is never chatter" ;;
  *) bad "check-inbox no longer rules a NOTICE out of chatter, so archiving one unfiled is a judgment again" ;;
esac
case "$INBOX" in
  *'# >>> notice-finding'*) ok "check-inbox carries the notice-finding block" ;;
  *) bad "check-inbox lost the notice-finding block" ;;
esac
case "$INBOX" in
  *reaping*reconciling*) ok "a request for an act the witness may not take is filed like a NOTICE" ;;
  *) bad "check-inbox no longer names reap and reconcile requests as findings" ;;
esac
NOTICE_CALL=$(printf '%s\n' "$INBOX" | grep 'patrol-finding\.sh" --scope' || true)
case "$NOTICE_CALL" in
  *'--scope witness-findings'*'--key "$KEY"'*'--about'*) ok "notice-finding files a keyed, --about-scoped witness finding" ;;
  *) bad "notice-finding's patrol-finding.sh call must carry --scope witness-findings, --key and --about" ;;
esac

# The witness may not close another agent's beads, so the request to do it
# needs a route onward. The prompt carries that next to the ban itself.
if awk '/Close another agent.s step beads/ {f=NR} f && NR <= f + 4 && /reap/ {r=1} f && NR <= f + 4 && /notice-finding/ {n=1} END {exit !(r && n)}' "$PROMPT"; then
  ok "the witness prompt files a reap request as a finding, beside its ban on reaping"
else
  bad "the witness prompt's ban on closing another agent's beads no longer says where a reap request goes"
fi

if grep -n 'gc mail send' "$TOML"; then
  bad "formula still contains a bare 'gc mail send' — findings are beads now"
else
  ok "no bare 'gc mail send' anywhere in the formula"
fi

echo
echo "witness-human-gate-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
