#!/usr/bin/env bash
# Thin wiring check: the deacon patrol's two sweeps — the doctor sweep and the
# Dolt backup sweep — file findings through assets/scripts/patrol-finding.sh
# (one durable bead per situation key, which a proactive first reaction then
# disposes). A bare `gc mail send` in the formula is the escalation-storm
# surface coming back — there is no mayor mailbox to absorb it, and mail dedups
# nothing.
#
# The measured failure this guards: escalate.sh's dedup window is one OPEN
# visit, and a converse sitting closes each visit before the next sweep runs,
# so `doctor-sweep-failed` filed 14 visits in one day under an identical key.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-deacon-patrol.toml"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

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
# check's finding into one bead.
grep -q -- '--key "doctor-<check-name>"' "$TOML" \
  && ok "the doctor sweep keys each finding by its check name" \
  || bad "the doctor sweep must key per check, not once for the whole sweep"

# The doctor sweep's FAILED path — failed, exceeded, blocked, an unnamed state,
# or a non-zero runner RC — carries no payload to filter, so it never reaches
# the per-check filer above. It is the doctor-sweep-failed key the header
# describes: routed through escalate.sh it filed a fresh visit every cycle. It
# must file ONE deduped finding instead.
grep -q -- 'patrol-finding\.sh" --scope deacon-findings --key doctor-sweep-failed' "$TOML" \
  && ok "the failed doctor-sweep path files a finding under --key doctor-sweep-failed" \
  || bad "the failed doctor-sweep path must file a finding (--key doctor-sweep-failed), not escalate a visit"

grep -q -- '--key dolt-backup-<db>' "$TOML" \
  && ok "the backup sweep keys each finding by its database" \
  || bad "the backup sweep must key per database, not once for the whole sweep"

# The standing triage subject existed only to give escalate.sh a durable
# subject for its visit. The finding bead is its own subject now, and keeping
# the old creation block would file a bead nothing writes to.
if grep -q 'triage.scope=deacon-findings' "$TOML"; then
  bad "the standing deacon-findings triage subject is still created; the finding bead is the subject now"
else
  ok "no standing triage subject — the finding bead is its own durable subject"
fi

if grep -n 'gc mail send' "$TOML"; then
  bad "formula still contains a bare 'gc mail send' — findings are beads now"
else
  ok "no bare 'gc mail send' anywhere in the formula"
fi

echo
echo "deacon-escalation-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
