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

# Every `append <category>` any caller writes, through a resolved $LEDGER or
# straight through the path gc names.
appends_in() { grep -oE '(\$LEDGER(_SH)?|gc-deacon-ledger\.sh)" append [a-z]+' "$1" | awk '{print $NF}'; }

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
  && ok "the deacon is city-scoped, so no rig root names the pack and only gc can" \
  || bad "agents/deacon/agent.toml no longer declares scope = \"city\" — re-derive what these resolvers must find"

# gc names the pack for `gc gc-toolkit scripts-dir`, the binding this city
# imports the pack under. A fixture city also holds a copy of the script under
# rigs/gc-toolkit, where the deacon's old lookup found it, so a resolver that
# still looked there would answer with that copy instead.
PACK="$TMP/pack"; FIX="$TMP/city"
mkdir -p "$PACK/assets/scripts" "$FIX/rigs/gc-toolkit/assets/scripts" "$TMP/bin"
cp "$LEDGER" "$PACK/assets/scripts/"
cp "$LEDGER" "$FIX/rigs/gc-toolkit/assets/scripts/"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-} ${2:-}" = "gc-toolkit scripts-dir" ] && [ -n "${STUB_PACK:-}" ] || { echo "gc: unknown command \"${1:-}\"" >&2; exit 1; }
printf '%s/assets/scripts\n' "$STUB_PACK"
STUB
chmod +x "$TMP/bin/gc"
# resolve <file> [STUB_PACK]: $LEDGER after the file runs from a directory that
# is not a git repository, with the city path set and no rig root.
resolve() {
  (cd "$TMP" && env -u GC_RIG_ROOT PATH="$TMP/bin:$PATH" GC_CITY_PATH="$FIX" STUB_PACK="${2-$PACK}" \
     bash -c "set -u; . '$1'; printf '%s' \"\$LEDGER\"" 2>/dev/null)
}
RESOLVER_RE='^[[:space:]]*LEDGER="\$\(b='"'"'\{\{binding_prefix\}\}'"'"'; gc "\$\{b%\.\}" scripts-dir\)/gc-deacon-ledger\.sh" && \[ -x "\$LEDGER" \] \|\| LEDGER=""$'
RESOLVERS=$(grep -cE "$RESOLVER_RE" "$TOML")
[ "$RESOLVERS" -ge 4 ] \
  && ok "each append site carries its own resolver ($RESOLVERS found; steps are separate shells)" \
  || bad "only $RESOLVERS resolvers in the formula, but each step runs in its own shell"
# Leading indentation differs where a resolver sits inside a conditional, and
# stripping it changes nothing about what the line does.
BLOCK="$TMP/resolver.sh"
grep -E "$RESOLVER_RE" "$TOML" | sed 's/^[[:space:]]*//' | awk '!seen[$0]++' \
  | sed 's|{{binding_prefix}}|gc-toolkit.|g' > "$BLOCK"
eq "$(grep -c . "$BLOCK")" "1" "every resolver in the formula is the same line"
eq "$(resolve "$BLOCK")" "$PACK/assets/scripts/gc-deacon-ledger.sh" \
  "the formula's resolver finds the script in the pack gc names"
eq "$(resolve "$BLOCK" "$TMP/no-pack")" "" \
  "a pack without the script resolves nothing, though the city path holds a copy"

grep -q 'show --since' "$PROMPT" \
  && ok "the deacon reads the ledger at startup, which is what survives a recycle" \
  || bad "the deacon prompt never reads the ledger — a restarted deacon is back to the transcript"
# The startup boot line must not fire every cycle: a ledger that logs each
# recycle is the transcript again, the same signal-only rule next-iteration
# follows. It records only when the reconcile changed state — a stale wisp
# burned, or a fresh one poured because none was recoverable — so the append is
# guarded, never a bare line that runs on every restart.
grep -q 'append boot' "$PROMPT" \
  && ok "the prompt can record a restart that recovered state" \
  || bad "the prompt never appends a boot entry, so a recovery-on-restart leaves no record"
if grep -qE '^"[^"]*(LEDGER|gc-deacon-ledger\.sh)" append boot' "$PROMPT"; then
  bad "the boot append is a bare top-level line, so it runs on every restart — that is one ledger entry per recycle, the noise a signal-only ledger excludes"
else
  ok "the boot append is guarded, so a routine recycle records nothing"
fi
# Every ledger call the prompt makes names the path gc prints for the binding
# the prompt is rendered with; rendered for this city, it is the pack's own.
PCALLS=$(grep -oE '"\$\(gc [^)]*\)/gc-deacon-ledger\.sh"' "$PROMPT" | sort -u)
eq "$(printf '%s\n' "$PCALLS" | grep -c .)" "1" "the prompt calls the ledger through one form"
eq "$PCALLS" '"$(gc {{ .BindingName }} scripts-dir)/gc-deacon-ledger.sh"' "the prompt's ledger calls name the binding it is rendered with"
printf 'LEDGER=%s\n' "$(printf '%s' "$PCALLS" | sed 's|{{ .BindingName }}|gc-toolkit|g')" > "$TMP/prompt-resolver.sh"
eq "$(resolve "$TMP/prompt-resolver.sh")" "$PACK/assets/scripts/gc-deacon-ledger.sh" \
  "the prompt's startup call reaches the same script"

echo
echo "deacon-ledger-wiring.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
