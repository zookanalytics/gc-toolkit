#!/usr/bin/env bash
# formula-binding-prefix-default.test.sh — every formula that declares
# [vars.binding_prefix] must give it a non-empty default.
#
# binding_prefix is the agent-identity prefix (with trailing dot) that formulas
# splice into routing addresses: the refinery, the polecat pool, the dog. A pour
# that supplies the var renders the bound prefix. The default is reached
# whenever the var is not supplied, by a pour that omits it or by an agent that
# reconstructs a command from the .toml source. An empty default then renders a
# bare role (<rig>/refinery, <rig>/polecat, a bare dog), an address no agent
# holds. Each consumer matches its address exactly, the refinery on assignee and
# a pool on route, so a bead sent to a bare role is read by no one and nothing
# reports the strand.
#
# submit-branch-gate.test.sh checks this for mol-polecat-work alone. Several
# formulas build routing addresses from the same var, so the invariant is a
# class, not one file: this scans every formula under formulas/, and every
# formula that splices {{binding_prefix}} must declare it in the form the scan
# reads.
#
# Hermetic: reads the pack's own formula sources. No city, network, or build.
#
# run-tests-scope: tree
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FORMULAS="$ROOT/formulas"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -d "$FORMULAS" ] || { echo "formulas dir not found: $FORMULAS" >&2; exit 2; }

# The value declared on the `default` line under [vars.binding_prefix], or empty
# when the section carries no default line. [[:blank:]] (space or tab, portably)
# avoids the GNU-only \t the host grep/awk would mis-read.
bp_default() {
  awk '
    /^\[vars\.binding_prefix\][[:blank:]]*$/ {f=1; next}
    f && /^\[/                                {exit}
    f && /^default[[:blank:]]*=/ {
      sub(/^default[[:blank:]]*=[[:blank:]]*"/, ""); sub(/"[[:blank:]]*$/, ""); print; exit
    }
  ' "$1"
}

declared=0; splicers=0
for f in "$FORMULAS"/*.toml; do
  [ -e "$f" ] || continue
  name="${f##*/}"
  # A formula that splices the token is in the class whether or not the section
  # matcher sees its declaration. One it misses would otherwise drop out of the
  # scan unchecked, so it fails here instead of being skipped.
  splices=0
  if grep -qF '{{binding_prefix}}' "$f"; then splices=1; splicers=$((splicers + 1)); fi
  # Detect the section independently of the default extraction, so a formula
  # that declares it but whose default the extractor cannot read fails loudly
  # rather than being skipped.
  if ! grep -Eq '^\[vars\.binding_prefix\][[:blank:]]*$' "$f"; then
    if [ "$splices" = "1" ]; then
      bad "$name: splices {{binding_prefix}} but declares no [vars.binding_prefix] section this scan reads, so its default goes unchecked"
    fi
    continue
  fi
  declared=$((declared + 1))
  val="$(bp_default "$f")"
  if [ -n "$val" ]; then
    ok "$name: binding_prefix default is non-empty ($val)"
  else
    bad "$name: binding_prefix default is EMPTY or absent — wherever the var is not supplied it renders a bare role (<rig>/refinery, <rig>/polecat, bare dog) that names no agent and strands silently"
  fi
done

# A scan that matched nothing is spelled the same as an all-clean scan, so this
# floor fails loudly rather than passing vacuously when neither matcher finds a
# single formula.
if [ "$declared" -ge 1 ] && [ "$splicers" -ge 1 ]; then
  ok "scanned $declared formulas declaring [vars.binding_prefix]; $splicers splice {{binding_prefix}}"
else
  bad "found $declared formulas declaring [vars.binding_prefix] and $splicers splicing {{binding_prefix}}; a matcher found none, so the guard is not checking the class"
fi

printf '\nformula-binding-prefix-default: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
