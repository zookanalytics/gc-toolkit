#!/usr/bin/env bash
# Hermetic test for tools/gc-proactive.sh: the live-intake stand-down
# and the fail-closed-on-unset-GC_RIG sweep guard.
#
# A live operator intake — gc-helm engage --new-subject — creates the subject
# MARKED gc.reaction_owned=1, files the ONE visit, and spawns the sitting
# itself. The proactive worker must stand down so a sweep does not file a SECOND
# visit for a conversation already under way. Two gates are covered here, both
# exercised through the fixture seam (GC_PROACTIVE_FIXTURE), so no live city,
# Dolt, or gc is needed:
#   (SCAN-DROP)  scan_precision_filter drops a marked bead from the candidate set
#   (SCAN-KEEP)  …while an unmarked raw input bead is still a candidate
#   (SLING-SKIP) sling refuses a marked bead as a no-op (exit RC_ALREADY_REACTED)
#                and names gc.reaction_owned, filing nothing
#   (SLING-GO)   …while an unmarked bead proceeds to the dispatch
# A standing record (a task_kind assets/scripts/standing-kinds.sh lists) is open,
# unrouted and unassigned by design and never closes, so a first reaction has no
# disposition to make on it:
#   (STANDING-DROP) scan_precision_filter drops a bead of every standing kind
#   (STANDING-KEEP) …while a raw input beside them is still a candidate
#
# gc-proactive.sh is a bash script (process substitution), so it is invoked via
# bash, not sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-proactive.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-proactive-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-proactive.sh present" || bad "gc-proactive.sh missing at $SCRIPT"

# A fixture dir short-circuits every gc call: scan reads scan.json, the sling
# guard reads beads.json, and a sling that passes the guard prints a dry line
# rather than dispatching.
export GC_PROACTIVE_FIXTURE="$TMP"

# gc-proactive.sh rig-qualifies its pool target from GC_RIG (resolve_pool_target
# is a pure string join, not a gc call) and fails closed when it is unset. The
# fixture replaces gc, not that rig context, so pin GC_RIG here: left to the
# ambient city it reads green locally and fails the SLING-GO dispatch on the bare
# CI runner, which has no GC_RIG.
export GC_RIG=gc-toolkit

# scan.json: one raw input bead (tk-plain) and one live-intake subject
# (tk-intake, marked). Both otherwise pass the precision filter (task type, has a
# description, unrouted, no reaction/takeaway markers, top-level).
cat > "$TMP/scan.json" <<'JSON'
[
  {"id":"tk-plain",  "issue_type":"task", "description":"a raw input bead",      "title":"plain input",     "metadata":{}},
  {"id":"tk-intake", "issue_type":"task", "description":"a live intake subject", "title":"intake subject",  "metadata":{"gc.reaction_owned":"1","gc.origin":"operator"}}
]
JSON

echo "# scan_precision_filter drops a live-intake subject, keeps a raw input"
IDS="$(bash "$SCRIPT" scan --json 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-plain"  "(SCAN-KEEP) an unmarked raw input bead is still a candidate"
hasnt "$IDS" "tk-intake" "(SCAN-DROP) a marked live-intake subject is dropped from the scan"

# One bead per standing kind, each passing every other clause (task type, a
# description, unrouted, unmarked, top-level), beside one raw input. The kinds
# are read from the shared definition, so a kind added there is covered here
# with no edit to this file.
# shellcheck source=../assets/scripts/standing-kinds.sh
. "$HERE/../assets/scripts/standing-kinds.sh"
KINDS="$(jq -nr "$STANDING_KINDS_JQ"'standing_kinds[]')"
[ -n "$KINDS" ] && ok "(STANDING) the shared definition lists the standing kinds" \
    || bad "(STANDING) the shared definition lists the standing kinds (read back empty)"
jq -n --arg kinds "$KINDS" '
  [{"id":"tk-raw", "issue_type":"task", "description":"a raw input bead", "title":"raw input", "metadata":{}}]
  + [ $kinds | split("\n")[] | select(length > 0)
      | {"id": ("tk-standing-" + .), "issue_type": "task", "description": "a standing record",
         "title": ("standing " + .), "metadata": {"task_kind": .}} ]' > "$TMP/scan.json"

echo "# scan_precision_filter drops every standing kind, keeps a raw input"
IDS="$(bash "$SCRIPT" scan --json 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-raw" "(STANDING-KEEP) a raw input beside the standing records is still a candidate"
for k in $KINDS; do
    hasnt "$IDS" "tk-standing-$k" "(STANDING-DROP) a task_kind=$k standing record is not a scan candidate"
done

# beads.json: the metadata the sling guard reads per bead.
cat > "$TMP/beads.json" <<'JSON'
{
  "tk-intake": {"metadata":{"gc.reaction_owned":"1","gc.origin":"operator"}},
  "tk-plain":  {"metadata":{}}
}
JSON

echo "# sling refuses a marked bead as a no-op, naming the marker"
set +e
OUT="$(bash "$SCRIPT" sling tk-intake 2>&1)"; RC=$?
set -e
eq "$RC" 3 "(SLING-SKIP) sling of a marked bead exits RC_ALREADY_REACTED (3)"
has "$OUT" "gc.reaction_owned=1" "(SLING-SKIP) …naming the marker"
has "$OUT" "file a second" "(SLING-SKIP) …and why (a second visit)"
hasnt "$OUT" "would sling" "(SLING-SKIP) …nothing dispatched"

echo "# an unmarked bead still proceeds to the dispatch"
set +e
OUT="$(bash "$SCRIPT" sling tk-plain 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(SLING-GO) sling of an unmarked bead exits 0"
has "$OUT" "would sling" "(SLING-GO) …and dispatches (fixture dry line)"

# --- fail closed with no rig context --------------------------------------
# resolve_pool_target dies when GC_RIG is unset, so a sling has no pool to route
# to. The --sling sweep must abort ONCE, not surface that failure and attempt
# `gc sling "" <bead>` per candidate. Two unmarked candidates make "once, not
# per-bead" observable; env -u GC_RIG drops, for just this invocation, the rig
# context the harness pinned above.
cat > "$TMP/scan.json" <<'JSON'
[
  {"id":"tk-a", "issue_type":"task", "description":"raw input a", "title":"a", "metadata":{}},
  {"id":"tk-b", "issue_type":"task", "description":"raw input b", "title":"b", "metadata":{}}
]
JSON
cat > "$TMP/beads.json" <<'JSON'
{"tk-a": {"metadata":{}}, "tk-b": {"metadata":{}}}
JSON

echo "# scan --sling with no rig context aborts the whole sweep once"
set +e
OUT="$(env -u GC_RIG bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] && ok "(SWEEP-FAILCLOSED) scan --sling exits non-zero when GC_RIG is unset" || bad "(SWEEP-FAILCLOSED) scan --sling exited 0 with no rig context (got $RC)"
hasnt "$OUT" "would sling" "(SWEEP-FAILCLOSED) …no empty-target dispatch attempted"
NSET="$(printf '%s\n' "$OUT" | grep -c 'set GC_RIG' || true)"
eq "$NSET" 1 "(SWEEP-FAILCLOSED) …the set-GC_RIG guidance surfaces once, not per candidate"

echo "# a direct sling with no rig context also fails closed"
set +e
OUT="$(env -u GC_RIG bash "$SCRIPT" sling tk-a 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] && ok "(SLING-FAILCLOSED) sling exits non-zero when GC_RIG is unset" || bad "(SLING-FAILCLOSED) sling exited 0 with no rig context (got $RC)"
hasnt "$OUT" "would sling" "(SLING-FAILCLOSED) …nothing dispatched"

# --- deliverable: the store-ownership arm -----------------------------------
# A rig-scope pool only claims beads in its own store, so `deliverable <target>
# <bead>` answers no when the target's rig does not own the bead's id prefix (the
# cross-store route gc sling refuses as CrossStoreRouteError), and falls through
# to the roster check when they agree. The fixture seam feeds rigs.json/agents.json
# instead of `gc rig list` / `gc agent list`.
cat > "$TMP/rigs.json" <<'JSON'
{"rigs":[
  {"name":"gc-toolkit","prefix":"tk","path":"/x/gc-toolkit"},
  {"name":"gascity","prefix":"gc","path":"/x/gascity"},
  {"name":"loomington","prefix":"lx","path":"/x/loomington"}]}
JSON
cat > "$TMP/agents.json" <<'JSON'
{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]}
JSON

echo "# deliverable refuses a cross-store route, by rig prefix"
set +e
OUT="$(bash "$SCRIPT" deliverable gascity/gc-toolkit.polecat tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(XSTORE-NO) a tk- bead routed at a gascity pool is refused"
has "$OUT" "cross-store" "(XSTORE-NO) …naming the dimension"
has "$OUT" "CrossStoreRouteError" "(XSTORE-NO) …tying it to the sling guard it mirrors"

set +e
OUT="$(bash "$SCRIPT" deliverable gc-toolkit/gc-toolkit.converse lx-300fe 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(XSTORE-CITY) a city-store (lx-) bead routed at a rig pool is refused"

echo "# deliverable falls through to the roster when target and bead share a store"
set +e
OUT="$(bash "$SCRIPT" deliverable gc-toolkit/gc-toolkit.polecat tk-82he4j 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(XSTORE-SAME) a tk- bead routed at a gc-toolkit pool passes the store arm"
has "$OUT" "yes" "(XSTORE-SAME) …and the roster arm answers yes for a present pool"

echo "# the store arm is skipped without a bead argument (backward compatible)"
set +e
OUT="$(bash "$SCRIPT" deliverable gc-toolkit/gc-toolkit.polecat 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(XSTORE-NOBEAD) with no bead named, only the roster arm runs"

echo "# an unreadable rig list is not evidence of a cross-store route (positive finding only)"
rm -f "$TMP/rigs.json"
set +e
OUT="$(bash "$SCRIPT" deliverable gascity/gc-toolkit.polecat tk-82he4j 2>&1)"; RC=$?
set -e
hasnt "$OUT" "cross-store" "(XSTORE-UNREADABLE) with no rig list, the store arm does not fire"

echo
echo "gc-proactive stand-down: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
