#!/usr/bin/env bash
# Every shipped escalate.sh call site owned by a CITY-scoped agent must name
# the rig it files into. escalate.sh qualifies its default converse pool with
# GC_RIG: a rig-scoped agent gets a routable address that way, but a
# city-scoped one runs with GC_RIG unset and is left with a bare name no live
# pool holds. The route gate then refuses before filing, so an unbound call
# site is a recipe that promises a human-visible visit and produces none.
#
# A prompt is a durable control channel, so a runnable recipe in one counts
# exactly as much as a formula step.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# The owning agent of a surface: an agent prompt owns itself, and a formula
# named mol-<agent>-* is that agent's recipe. Anything else has no single
# owner to read a scope from and is left to its own wiring test.
owner_of() {
  local x
  case "${1#"$ROOT"/}" in
    agents/*/prompt.template.md) x="${1#*/agents/}"; printf '%s' "${x%%/*}" ;;
    formulas/mol-*.toml)         x="$(basename "$1" .toml)"; x="${x#mol-}"; printf '%s' "${x%%-*}" ;;
  esac
}

scope_of() { # agent name -> declared scope, empty when the agent is not shipped
  local toml="$ROOT/agents/$1/agent.toml"
  [ -s "$toml" ] || return 0
  sed -n 's/^scope[[:space:]]*=[[:space:]]*"\([a-z]*\)".*/\1/p' "$toml" | head -n 1
}

# Only runnable invocations: a call through $SCRIPTS, or the bare name with
# its flags. A path test (`[ -x .../escalate.sh ]`) and a prose mention that
# names no flags are neither.
invocations() { grep -n -E '\$SCRIPTS/escalate\.sh|(^|[^-/[:alnum:]])escalate\.sh[[:space:]]+--' "$1"; }
bound() { printf '%s' "$1" | grep -qE 'GC_RIG=|--pool[[:space:]]+[A-Za-z0-9._-]+/'; }

EXAMINED=0
for f in "$ROOT"/agents/*/prompt.template.md "$ROOT"/formulas/mol-*.toml; do
  [ -s "$f" ] || continue
  agent="$(owner_of "$f")"; [ -n "$agent" ] || continue
  [ "$(scope_of "$agent")" = "city" ] || continue
  lines="$(invocations "$f")"; [ -n "$lines" ] || continue
  rel="${f#"$ROOT"/}"
  unbound=""
  while IFS= read -r line; do
    bound "$line" || unbound="${unbound}${line}"$'\n'
  done <<< "$lines"
  EXAMINED=$((EXAMINED + 1))
  if [ -n "$unbound" ]; then
    bad "$rel ($agent is city-scoped) has escalate.sh call sites with no rig binding:"
    printf '%s' "$unbound" | sed 's/^/       /'
  else
    ok "$rel: every escalate.sh call site names its rig ($agent is city-scoped)"
  fi
done

# A scan that examined nothing passes for the wrong reason. The city-scoped
# escalating surfaces are the population this file exists to cover.
[ "$EXAMINED" -ge 2 ] \
  && ok "the scan reached $EXAMINED city-scoped escalating surfaces" \
  || bad "the scan reached only $EXAMINED city-scoped escalating surface(s) — the filter stopped matching, it did not get clean"

echo
echo "escalation-binding: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
