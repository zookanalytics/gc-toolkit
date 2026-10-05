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
# adds must be gone too, or the leak returns one release later. GC_NO_API is the
# one deliberate exception. harness_init sets it, rather than inheriting it, to
# pin the gctk read seam onto the stubbed gc the same way GCTK_BIN is pinned. The
# sweep excludes it by exact name, and the assertion below proves the pin took.
resid="$(compgen -v | grep -E '^(GC_|BEADS_)' | grep -vxF GC_NO_API || true)"
if [ -z "$resid" ]; then ok "no GC_/BEADS_ variable survives harness_init"; else bad "residual city vars: $resid"; fi
eq "${GC_NO_API:-}" "1" "harness_init pins GC_NO_API=1 so a gctk read hits the stub, not the live daemon"

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

# STUB_ENFORCE_CLOSE_OWNER mirrors real bd's close-ownership check: `bd close`
# refuses a bead assigned to another actor unless --force is passed, an
# unassigned bead or the actor's own closes plainly, and `bd update
# --status=closed` never runs the check. A caller that drops its --force passes
# against a stub that refuses nothing, so the refusal is pinned here, and so is
# the default: with the knob unset any actor closes, as every other suite expects.
store '[{"id":"tk-held","status":"in_progress","assignee":"lx-sitting","title":"h","notes":"","metadata":{}},{"id":"tk-free","status":"open","assignee":"","title":"f","notes":"","metadata":{}},{"id":"tk-mine","status":"open","assignee":"rig/refinery","title":"m","notes":"","metadata":{}},{"id":"tk-upd","status":"in_progress","assignee":"lx-sitting","title":"u","notes":"","metadata":{}},{"id":"tk-off","status":"in_progress","assignee":"lx-sitting","title":"o","notes":"","metadata":{}}]'
as_refinery() { STUB_ENFORCE_CLOSE_OWNER=1 BEADS_ACTOR=rig/refinery gc bd "$@" >/dev/null 2>&1; }
as_refinery close tk-held --reason r; rc=$?
eq "$rc" "1" "close: a bead assigned to another actor is refused without --force"
eq "$(bstatus tk-held)" "in_progress" "...and is left as it was"
as_refinery close tk-held --reason r --force
eq "$(bstatus tk-held)" "closed" "close --force overrides the ownership check"
as_refinery close tk-free --reason r
eq "$(bstatus tk-free)" "closed" "close: an unassigned bead closes for any actor"
as_refinery close tk-mine --reason r
eq "$(bstatus tk-mine)" "closed" "close: the actor's own bead closes without --force"
as_refinery update tk-upd --status=closed
eq "$(bstatus tk-upd)" "closed" "update --status=closed never runs the close verb's ownership check"
gc bd close tk-off --reason r >/dev/null 2>&1
eq "$(bstatus tk-off)" "closed" "with the knob unset, a plain close lands whoever holds the bead"

# The gc bd dep stub mirrors real bd's blocks orientation. Real `dep add
# <blocked> <blocker> --type blocks` makes the SECOND operand the blocker — the
# documented `dep add Y X` equals `dep X --blocks Y`. A stub that stored the add
# source-first lets a reversed dep-add read back as the intended edge and pass,
# so the orientation is pinned here.
store '[{"id":"tk-blk","status":"open","assignee":"","title":"b","notes":"","metadata":{}},{"id":"tk-kd","status":"open","assignee":"","title":"k","notes":"","metadata":{}}]'
down_blockers() { gc bd dep list "$1" --direction=down -t blocks --json | jq -r '.[].id' | tr '\n' ' '; }
: > "$STUB_DEPS"
gc bd dep add tk-kd tk-blk --type blocks
has " $(down_blockers tk-kd) " " tk-blk " "dep add <blocked> <blocker> --type blocks: the second operand is the blocker"
hasnt " $(down_blockers tk-blk) " " tk-kd " "...not the reverse — the first operand is the blocked, never a blocker"
: > "$STUB_DEPS"
gc bd dep tk-blk --blocks tk-kd
has " $(down_blockers tk-kd) " " tk-blk " "dep <blocker> --blocks <blocked> lands the same orientation as the dep add form"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
