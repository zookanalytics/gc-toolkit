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

# The gc bd create stub lands a create the way real bd does: --metadata (a JSON
# value, its types kept), --status and --notes ride the one insert, and a
# --metadata that is not JSON is refused with nothing created. A stub that
# dropped the payload made a writer whose stamps ride the create look like one
# that stamps in a second write, so no suite could see a payload land at birth.
store '[]'
eq "$(gc bd create "born" -t task --metadata '{"task_kind":"review","n":1,"oid":"0123"}' --status=closed --notes "first note" --json | jq -r '.id')" \
  "new-1" "create answers the id it minted"
eq "$(bstatus new-1)" "closed" "--status rides the create"
eq "$(meta new-1 task_kind)" "review" "--metadata rides the create"
eq "$(jq -c '.[] | select(.id == "new-1") | .metadata.n' "$STUB_STORE")" '1' "…keeping its JSON types: a number stays a number"
eq "$(jq -c '.[] | select(.id == "new-1") | .metadata.oid' "$STUB_STORE")" '"0123"' "…and a JSON string stays a string"
eq "$(notes new-1)" "first note" "--notes rides the create"
gc bd create "plain" -t task --json >/dev/null
eq "$(bstatus new-2)" "open" "a create with no --status is open"
eq "$(jq -c '.[] | select(.id == "new-2") | .metadata' "$STUB_STORE")" '{}' "…and carries no metadata"
if gc bd create "bad" --metadata 'not json' --json >/dev/null 2>&1; then bad "an unparseable --metadata was accepted"; else ok "an unparseable --metadata is refused"; fi
eq "$(jq 'length' "$STUB_STORE")" "2" "…and creates nothing"
STUB_DROP_KEYS="new-3:status,oid" gc bd create "partial" --metadata '{"task_kind":"review","oid":"x"}' --status=closed --json >/dev/null
eq "$(bstatus new-3)" "open" "STUB_DROP_KEYS naming the minted id drops the create's status"
eq "$(meta new-3 oid)" "<absent>" "…and the named metadata keys"
eq "$(meta new-3 task_kind)" "review" "…and lands the rest"
if STUB_CREATE_FAIL=1 gc bd create "refused" --json >/dev/null 2>&1; then bad "STUB_CREATE_FAIL did not refuse the create"; else ok "STUB_CREATE_FAIL refuses the create"; fi
eq "$(jq 'length' "$STUB_STORE")" "3" "…and creates nothing"
if STUB_CREATE_GARBAGE=1 gc bd create "lost" --json | jq -e . >/dev/null 2>&1; then bad "STUB_CREATE_GARBAGE answered parseable JSON"; else ok "STUB_CREATE_GARBAGE answers a reply no JSON reader parses"; fi
eq "$(jq -r '.[] | select(.id == "new-4") | .title' "$STUB_STORE")" "lost" "…while the create still lands"

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
