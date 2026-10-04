#!/usr/bin/env bash
# formula-binding-prefix-default.test.sh — every formula that declares
# [vars.binding_prefix] must give it a non-empty default.
#
# binding_prefix is the agent-identity prefix (with trailing dot) that formulas
# splice into routing addresses: the refinery, the polecat pool, the dog. The
# pour supplies the var, so a POURED step renders the bound prefix. The default
# is reached only when an agent reconstructs a command from the .toml source,
# and an empty default then renders a bare role — <rig>/refinery, <rig>/polecat,
# a bare dog — an address no agent holds. The consumers find work by exact-match
# assignee, so a bead sent to a bare role is read by no one and nothing reports
# the strand.
#
# submit-branch-gate.test.sh checks this for mol-polecat-work alone. Several
# formulas build routing addresses from the same var, so the invariant is a
# class, not one file: this scans every formula under formulas/.
#
# Hermetic: reads the pack's own formula sources. No city, network, or build.
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

declared=0
for f in "$FORMULAS"/*.toml; do
  [ -e "$f" ] || continue
  # Detect the section independently of the default extraction, so a formula
  # that declares it but whose default the extractor cannot read fails loudly
  # rather than being skipped.
  grep -Eq '^\[vars\.binding_prefix\][[:blank:]]*$' "$f" || continue
  declared=$((declared + 1))
  name="${f##*/}"
  val="$(bp_default "$f")"
  if [ -n "$val" ]; then
    ok "$name: binding_prefix default is non-empty ($val)"
  else
    bad "$name: binding_prefix default is EMPTY or absent — a source-read renders a bare role (<rig>/refinery, <rig>/polecat, bare dog) that names no agent and strands silently"
  fi
done

# A scan that matched nothing is spelled the same as an all-clean scan, so this
# floor fails loudly rather than passing vacuously: the two formulas that
# originate the non-empty default (mol-polecat-work, mol-feedback-distiller)
# must both be seen.
[ "$declared" -ge 2 ] \
  && ok "scanned $declared formulas declaring [vars.binding_prefix]" \
  || bad "scanned only $declared formulas declaring [vars.binding_prefix]; the section matcher found too few, so the guard is not checking the class"

printf '\nformula-binding-prefix-default: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
