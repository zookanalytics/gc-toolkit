#!/usr/bin/env bash
# Wiring check for the deacon incident ledger: the append sites exist where a
# non-routine action happens, they speak the vocabulary gc-deacon-ledger.sh
# accepts, and the path they call resolves for a city-scoped agent.
#
# The coupling is what needs a test. A category the script does not know is
# refused at runtime, so the entry is simply lost — and an append beside an
# escalation double-records the same incident, because escalate.sh already
# wrote that entry. Neither shows up as a failure anywhere.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-deacon-patrol.toml"
PROMPT="$ROOT/agents/deacon/prompt.template.md"
AGENT="$ROOT/agents/deacon/agent.toml"
LEDGER="$HERE/gc-deacon-ledger.sh"
ESCALATE="$HERE/escalate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-deacon-ledger-wiring-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

for f in "$TOML" "$PROMPT" "$AGENT" "$LEDGER" "$ESCALATE"; do
  [ -s "$f" ] || { echo "missing $f" >&2; exit 1; }
done

# The lines of one [[steps]] block, so an assertion names the step it is about
# rather than the whole file.
step_body() {
  awk -v want="$1" '
    /^id = "/ { cur = $0; sub(/^id = "/, "", cur); sub(/".*/, "", cur) }
    cur == want { print }
  ' "$TOML"
}

# Every category the script will accept, read from the script so the two
# cannot drift apart.
CATEGORIES=$(sed -n 's/^CATEGORIES="\(.*\)"$/\1/p' "$LEDGER")
[ -n "$CATEGORIES" ] \
  && ok "the accepted category set is readable from gc-deacon-ledger.sh: $CATEGORIES" \
  || bad "no CATEGORIES= line in gc-deacon-ledger.sh — this file cannot check the callers"

# Every `append <category>` any caller writes.
appends_in() { grep -oE '\$LEDGER(_SH)?" append [a-z]+' "$1" | awk '{print $NF}'; }

echo
echo "# the append sites are where a non-routine action happens"
for step in check-inbox orphan-process-cleanup dolt-health system-health; do
  if grep -q 'gc-deacon-ledger\.sh' < <(step_body "$step"); then
    ok "$step ledgers what it did"
  else
    bad "$step takes non-routine action and writes no ledger entry"
  fi
done
if grep -q 'gc-deacon-ledger\.sh' < <(step_body next-iteration); then
  bad "next-iteration appends to the ledger — it runs every cycle regardless of what was found, which is the noise a signal-only ledger excludes"
else
  ok "next-iteration appends nothing (it is the routine loop)"
fi

echo
echo "# the callers speak the vocabulary the script accepts"
for src in "$TOML" "$PROMPT" "$ESCALATE"; do
  name="${src##*/}"
  used=$(appends_in "$src" | sort -u)
  if [ -z "$used" ]; then
    bad "$name calls the ledger but no 'append <category>' could be read from it"
    continue
  fi
  unknown=""
  for c in $used; do
    case " $CATEGORIES " in *" $c "*) ;; *) unknown="$unknown $c" ;; esac
  done
  if [ -n "$unknown" ]; then
    bad "$name appends categories gc-deacon-ledger.sh refuses:$unknown"
  else
    ok "$name appends only accepted categories ($(printf '%s' "$used" | tr '\n' ' '))"
  fi
done

echo
echo "# escalate.sh owns the escalation entry, and owns it alone"
grep -q 'append escalation' "$ESCALATE" \
  && ok "escalate.sh writes the escalation entry itself" \
  || bad "escalate.sh no longer appends an escalation entry — every escalation is now unrecorded"
grep -q 'bead:\$VISIT' "$ESCALATE" \
  && ok "and points the entry at the visit it filed" \
  || bad "the escalation entry no longer carries the visit id, which is the only pointer to it"
if grep -q 'append escalation' "$TOML"; then
  bad "the formula appends an escalation entry too — escalate.sh already wrote one, so the incident is recorded twice"
else
  ok "the formula appends no escalation entry beside escalate.sh's"
fi
# The gate is what keeps every other agent's escalations out of the deacon's
# ledger. Its premise is that the deacon is a distinct role in $GC_AGENT.
grep -q 'LEDGER_ROLE" = deacon' "$ESCALATE" \
  && ok "the escalate.sh append is gated to the deacon" \
  || bad "escalate.sh appends for every caller — a polecat's escalation is not a deacon shift record"

echo
echo "# the path a city-scoped agent calls actually resolves"
grep -Eq '^scope[[:space:]]*=[[:space:]]*"city"' "$AGENT" \
  && ok "the deacon is city-scoped, so GC_RIG_ROOT is unset and the resolver's last candidate is the load-bearing one" \
  || bad "agents/deacon/agent.toml no longer declares scope = \"city\" — re-derive what these resolvers must find"

# Run the shipped resolver against a fixture city laid out the way a rig is,
# from a directory that is NOT a git repository, so only the city-path
# candidate can answer — which is the deacon's real situation.
FIX="$TMP/city"
mkdir -p "$FIX/rigs/gc-toolkit/assets/scripts"
cp "$LEDGER" "$FIX/rigs/gc-toolkit/assets/scripts/"
RESOLVERS=$(grep -cE '^[[:space:]]*LEDGER=""; for c in ' "$TOML")
[ "$RESOLVERS" -ge 4 ] \
  && ok "each append site carries its own resolver ($RESOLVERS found; steps are separate shells)" \
  || bad "only $RESOLVERS resolvers in the formula, but each step runs in its own shell"
# Dedupe in place, never by sorting: these three lines only run in the order
# they are written. Leading indentation differs where a resolver sits inside a
# conditional, and stripping it changes nothing about what the block does.
BLOCK="$TMP/resolver.sh"
grep -A2 -E '^[[:space:]]*LEDGER=""; for c in ' "$TOML" | grep -v '^--$' \
  | sed 's/^[[:space:]]*//' | awk '!seen[$0]++' > "$BLOCK"
UNIQUE=$(grep -c '^LEDGER=""' "$BLOCK")
eq "$UNIQUE" "1" "every resolver in the formula is the same three lines"
GOT=$(cd "$TMP" && env -u GC_RIG_ROOT GC_CITY_PATH="$FIX" bash -c "set -u; . '$BLOCK'; printf '%s' \"\$LEDGER\"" 2>/dev/null)
eq "$GOT" "$FIX/rigs/gc-toolkit/assets/scripts/gc-deacon-ledger.sh" \
  "the formula's resolver finds the script from the city path alone"

grep -q 'show --since' "$PROMPT" \
  && ok "the deacon reads the ledger at startup, which is what survives a recycle" \
  || bad "the deacon prompt never reads the ledger — a restarted deacon is back to the transcript"
grep -q 'append boot' "$PROMPT" \
  && ok "and records the restart itself" \
  || bad "a restart leaves no ledger entry, so a recycle loop is invisible in the record"
PBLOCK="$TMP/prompt-resolver.sh"
awk '/^LEDGER=""$/{f=1} f{print} /^done$/{if (f) exit}' "$PROMPT" > "$PBLOCK"
if [ -s "$PBLOCK" ]; then
  GOT=$(cd "$TMP" && env -u GC_RIG_ROOT GC_CITY_PATH="$FIX" bash -c "set -u; . '$PBLOCK'; printf '%s' \"\$LEDGER\"" 2>/dev/null)
  eq "$GOT" "$FIX/rigs/gc-toolkit/assets/scripts/gc-deacon-ledger.sh" \
    "the prompt's startup resolver finds the same script"
else
  bad "no resolver loop in the deacon prompt to execute"
fi

echo
echo "deacon-ledger-wiring.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
