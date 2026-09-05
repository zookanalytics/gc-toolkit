#!/usr/bin/env bash
# Thin wiring check: every escalation in the dog shutdown dance goes through
# assets/scripts/escalate.sh, and every one of those calls is rig-bound.
# The dog pool is city-scoped, so GC_RIG is normally unset; escalate.sh's
# default converse pool then renders bare, matches no rig-scoped agent
# identity, and is refused before anything is filed. An unbound call in this
# formula is a stop path that promises a human-visible visit and files none.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/formulas/mol-dog-shutdown-dance.toml"
AGENT="$ROOT/agents/dog/agent.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-dog-escalation-wiring-test.XXXXXX")"; mkdir -p "$TMP/bin"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }
[ -s "$AGENT" ] || { echo "missing $AGENT" >&2; exit 1; }

# The premise the binding rests on. If the dog is ever re-scoped to a rig,
# GC_RIG arrives bound and the rest of this file needs rethinking, not muting.
grep -Eq '^scope[[:space:]]*=[[:space:]]*"city"' "$AGENT" \
  && ok "dog pool is city-scoped, so escalate.sh calls must name their rig" \
  || bad "agents/dog/agent.toml no longer declares scope = \"city\" — re-derive what these calls must bind"

grep -q 'escalate\.sh' "$TOML" \
  && ok "dog formula escalates through escalate.sh" \
  || bad "dog formula never references escalate.sh"

grep -q -- '--subject' "$TOML" && grep -q -- '--key' "$TOML" \
  && ok "escalate.sh calls carry --subject and --key (the dedup identity)" \
  || bad "escalate.sh calls must carry --subject and --key"

# A rig-qualified --pool is the other accepted form: escalate.sh adopts that
# pool's rig segment into GC_RIG for the whole run, so route and store agree.
UNBOUND=$(grep -n 'escalate\.sh' "$TOML" \
  | grep -v 'GC_RIG=' \
  | grep -Ev -- '--pool[[:space:]]+[A-Za-z0-9._-]+/' \
  | grep -E '\$SCRIPTS/escalate\.sh|escalate\.sh --')
if [ -n "$UNBOUND" ]; then
  bad "escalate.sh call sites with neither a GC_RIG binding nor a rig-qualified --pool:"
  printf '%s\n' "$UNBOUND" | sed 's/^/       /'
else
  ok "every escalate.sh call site is rig-bound or carries a rig-qualified --pool"
fi

# The binding is only as good as the value it carries. It comes from the
# warrant's STORE: a warrant is routed to a bare identity, so its route has no
# rig segment to read, and an ambient fallback names the caller's store rather
# than the subject's.
grep -q 'ESC_RIG="\$("\$SCRIPTS/escalation-rig.sh"' "$TOML" \
  && ok "the formula derives the escalation rig from the warrant's store" \
  || bad "no escalation-rig.sh derivation — GC_RIG= on a call site binds nothing without it"

grep -q 'ESC_RIG.*routed_to\|routed_to.*ESC_RIG\|warrant_route' "$TOML" \
  && bad "the escalation rig is derived from the warrant's route again — a bare route carries no rig segment" \
  || ok "the escalation rig is not derived from the warrant's route"

grep -q 'if \[ -z "\$ESC_RIG" \]' "$TOML" && grep -q 'if \[ -n "\$ESC_RIG" \]' "$TOML" \
  && ok "both stop paths guard on an unresolved rig instead of filing into a guessed store" \
  || bad "a stop path calls escalate.sh without checking that ESC_RIG resolved"

# The finding this whole file exists for, run rather than grepped: a warrant
# that lives outside gc-toolkit and carries a bare route must still resolve to
# its own store. The formula's own derivation line is extracted and executed
# against the real resolver, with only `gc rig list` stubbed.
BLOCK="$TMP/escalation-rig.block"
awk '/^# >>> escalation-rig$/{f=1;next} /^# <<< escalation-rig$/{f=0} f' "$TOML" > "$BLOCK"
if [ ! -s "$BLOCK" ]; then
  bad "no '# >>> escalation-rig' block in the formula to execute"
else
  ok "the formula's rig derivation is extractable as a marked block"
  cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
set -u
[ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ] || exit 0
printf '%s\n' '{"rigs":[{"name":"gc-toolkit","prefix":"tk","path":"/c/rigs/gc-toolkit"},
  {"name":"gascity","prefix":"gc","path":"/c/rigs/gascity"}]}'
STUB
  chmod +x "$TMP/bin/gc"
  derive() { # <warrant-id> -> the ESC_RIG the formula would bind
    env -u GC_RIG PATH="$TMP/bin:$PATH" SCRIPTS="$HERE" warrant_id="$1" \
      bash -c "set -u; . '$BLOCK' 2>/dev/null; printf '%s' \"\$ESC_RIG\""
  }
  GOT=$(derive gc-yxpj8)
  [ "$GOT" = "gascity" ] \
    && ok "a bare-routed warrant in the gascity store binds ESC_RIG=gascity" \
    || bad "a bare-routed warrant in the gascity store bound ESC_RIG='$GOT' (want 'gascity')"

  GOT=$(derive tk-3y6toq)
  [ "$GOT" = "gc-toolkit" ] \
    && ok "a gc-toolkit warrant binds ESC_RIG=gc-toolkit" \
    || bad "a gc-toolkit warrant bound ESC_RIG='$GOT' (want 'gc-toolkit')"

  GOT=$(derive zz-nostore)
  [ -z "$GOT" ] \
    && ok "a warrant whose store does not resolve binds nothing, so the guards fire" \
    || bad "an unresolvable warrant bound ESC_RIG='$GOT' (want empty)"
fi

if grep -n 'gc mail send' "$TOML"; then
  bad "formula still contains a bare 'gc mail send' — escalations are visits now"
else
  ok "no bare 'gc mail send' anywhere in the formula"
fi

echo
echo "dog-escalation-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
