#!/usr/bin/env bash
# test-harness.test.sh — the harness's own contract: harness_init hands a suite
# a clean environment. These suites run from a tree inside a live city, whose
# session exports GC_* and BEADS_* (the rig, the city path, the actor, the bead
# under work). A leaked GC_RIG turns into a `--rig <rig>` in a logged sling argv,
# so an inherited value would settle a hermetic assertion on the operator's shell
# rather than on the code. harness_init clears both namespaces so no suite has to.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-test-harness-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"

# Seed the environment a polecat/agent session exports, plus a port binary path
# a suite builds before sourcing the harness (the lifecycle.test.sh pattern:
# GCTK_BUILT is set pre-init because the stub git must not answer the Go build).
export GC_RIG=gc-toolkit GC_CITY_PATH=/live/city GC_CITY=loomington
export GC_AGENT=rig/gc-toolkit.polecat GC_SESSION_NAME=live-sess GC_SESSION_ID=lx-live
export GC_TRIGGER_BEAD_ID=tk-live GC_RIG_ROOT=/live/rigs/gc-toolkit
export BEADS_DIR=/live/beads BEADS_ACTOR=live-actor
GCTK_BUILT="$TMP/gctk"

# Capture the seed before harness_init runs — it is the call under test AND it
# resets PASS/FAIL, so every assertion has to come after it. The captures let a
# post-init assertion prove the seed was really set, so "cleared" is a real
# transition and not a variable that was never there.
SEED_GC_RIG="${GC_RIG:-}"; SEED_BEADS_DIR="${BEADS_DIR:-}"

harness_init

# The seed took, so the clears below discriminate.
eq "$SEED_GC_RIG"   "gc-toolkit"  "seed: GC_RIG was set before harness_init"
eq "$SEED_BEADS_DIR" "/live/beads" "seed: BEADS_DIR was set before harness_init"

# harness_init cleared every live-city variable it was handed.
for v in GC_RIG GC_CITY_PATH GC_CITY GC_AGENT GC_SESSION_NAME GC_SESSION_ID \
         GC_TRIGGER_BEAD_ID GC_RIG_ROOT BEADS_DIR BEADS_ACTOR; do
  if [ -z "${!v:-}" ]; then ok "harness_init cleared $v"; else bad "harness_init left $v=[${!v}]"; fi
done

# The whole namespace, not just the names above: a variable a future city release
# adds must be gone too, or the leak returns one release later.
resid="$(compgen -v | grep -E '^(GC_|BEADS_)' || true)"
if [ -z "$resid" ]; then ok "no GC_/BEADS_ variable survives harness_init"; else bad "residual city vars: $resid"; fi

# GCTK_* is out of scope: the port pin stays, and a pre-init build path is not
# collateral — a blanket GC* unset would have taken GCTK_BUILT with it.
eq "$GCTK_BIN"   "none"       "harness_init pins GCTK_BIN=none"
eq "$GCTK_BUILT" "$TMP/gctk"  "harness_init preserves a pre-init GCTK_BUILT"

# The hermetic stub environment is still installed.
case "$STUB_STORE" in "$TMP"/*) ok "STUB_STORE points into TMP" ;; *) bad "STUB_STORE not under TMP: $STUB_STORE" ;; esac
case ":$PATH:" in *":$TMP/bin:"*) ok "stub bin is on PATH" ;; *) bad "stub bin not on PATH" ;; esac
[ -x "$TMP/bin/gc" ] && ok "stub gc installed" || bad "stub gc missing"

# A suite that WANTS a rig sets it after harness_init returns.
export GC_RIG=myrig
eq "$GC_RIG" "myrig" "a rig exported after harness_init is honored"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
