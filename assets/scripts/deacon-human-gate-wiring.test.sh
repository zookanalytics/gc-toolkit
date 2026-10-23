#!/usr/bin/env bash
# Thin wiring check: the deacon patrol's two sweeps — the doctor sweep and the
# Dolt backup sweep — file findings through assets/scripts/patrol-finding.sh
# (one durable bead per situation key, which a proactive first reaction then
# disposes), and the deacon's emergency is a human gate filed with
# assets/scripts/human-gate.sh on the bead it is about. A bare `gc mail send`
# in the formula dedups nothing, and there is no mayor mailbox to absorb it.
#
# A sweep re-detects its failure every cycle. A finding stays one bead per key
# while it lives and counts each recurrence, where a human gate is one per key
# only while it is open, so a sweep filed as a gate would ask again every cycle
# once a person answered the last one.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-deacon-patrol.toml"
PROMPT="$ROOT/agents/deacon/prompt.template.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }
[ -s "$PROMPT" ] || { echo "missing $PROMPT" >&2; exit 1; }

grep -q 'patrol-finding\.sh' "$TOML" \
  && ok "deacon patrol files findings through patrol-finding.sh" \
  || bad "deacon patrol never references patrol-finding.sh"

# Every filing path resolves the writer and calls it: the Dolt backup sweep,
# the doctor sweep's per-check findings, and the doctor sweep's FAILED path.
N_CALLS=$(grep -c 'patrol-finding\.sh" --scope deacon-findings' "$TOML")
if [ "$N_CALLS" -ge 3 ]; then
  ok "all three filing paths call patrol-finding.sh ($N_CALLS call sites)"
else
  bad "expected filing calls for the backup sweep, the per-check finding, and the failed sweep; found $N_CALLS"
fi

grep -q -- '--key' "$TOML" \
  && ok "the calls carry --key (the dedup identity)" \
  || bad "patrol-finding.sh calls must carry --key"

# The doctor sweep's key varies per check; a single shared key would fold every
# check's finding into one bead. --check derives that per-check key from the
# check's own name, so it is not hand-typed and cannot vary by how the name is
# rendered.
grep -qF -- '--scope deacon-findings --check "$CHECK"' "$TOML" \
  && ok "the doctor sweep derives each finding's key from its check name (--check)" \
  || bad "the doctor sweep must derive the key per check via --check, not a hand-typed placeholder"

# The doctor sweep's FAILED path — failed, exceeded, blocked, an unnamed state,
# or a non-zero runner RC — carries no payload to filter, so it never reaches
# the per-check filer above. It files ONE deduped finding under its own key.
grep -q -- 'patrol-finding\.sh" --scope deacon-findings --key doctor-sweep-failed' "$TOML" \
  && ok "the failed doctor-sweep path files a finding under --key doctor-sweep-failed" \
  || bad "the failed doctor-sweep path must file a finding (--key doctor-sweep-failed), not a human gate"

grep -q -- '--key dolt-backup-<db>' "$TOML" \
  && ok "the backup sweep keys each finding by its database" \
  || bad "the backup sweep must key per database, not once for the whole sweep"

# The finding bead is its own subject, so the patrol creates no standing triage
# subject: one would be a bead nothing writes to.
if grep -q 'triage.scope=deacon-findings' "$TOML"; then
  bad "the standing deacon-findings triage subject is still created; the finding bead is the subject"
else
  ok "no standing triage subject — the finding bead is its own durable subject"
fi

if grep -n 'gc mail send' "$TOML"; then
  bad "formula still contains a bare 'gc mail send' — findings are beads"
else
  ok "no bare 'gc mail send' anywhere in the formula"
fi

# The patrol and the prompt name the helper by its name. The prompt's emergency
# calls it directly on the bead it is about: `gc bd` files the gate in that
# bead's store, so no store is derived first and no pool is named.
for F in "$TOML" "$PROMPT"; do
  if grep -n 'escalate\.sh' "$F"; then
    bad "${F#"$ROOT"/} still names escalate.sh; the helper is human-gate.sh"
  else
    ok "${F#"$ROOT"/} names the helper by its name, human-gate.sh"
  fi
done
EMERGENCY=$(grep -n '"\$SCRIPTS/human-gate\.sh"' "$PROMPT")
case "$EMERGENCY" in
  *'--subject <bead> --key <situation-key>'*) ok "the deacon's emergency files a human gate on the bead it is about" ;;
  *) bad "the deacon prompt's emergency no longer calls human-gate.sh --subject <bead> --key <situation-key>" ;;
esac
if grep -n -e 'escalation-rig' -e 'ESC_RIG' -e '--pool' "$PROMPT"; then
  bad "the deacon prompt derives a store or names a pool for its human gate; gc bd files the gate beside the bead it blocks"
else
  ok "the deacon prompt derives no store and names no pool for its human gate"
fi

echo
echo "deacon-human-gate-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
