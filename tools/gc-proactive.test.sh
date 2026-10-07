#!/usr/bin/env bash
# Hermetic test for tools/gc-proactive.sh: the live-intake stand-down,
# the fail-closed-on-unset-GC_RIG sweep guard, and the scan's drop of a bead a
# live workflow already drives (INFLIGHT-*).
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
#
# The sling also refuses a bead a live workflow already drives (LIVE-*), and
# fails closed when it cannot read whether one does.
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

# --- a bead a live workflow already drives is not offered -----------------
# roots.json and convoys.json stand in for the two reads scan_drop_inflight
# takes. tk-live is tracked by a convoy that a live workflow root names, so gc
# sling would refuse it. tk-done's convoy is named only by a closed root (its
# workflow ended), tk-orphan's convoy by no root at all, and tk-fresh has no
# convoy. Only tk-live leaves the page. tk-live is the oldest, so it ranks first,
# and with a cap of one the slot shows which bead the sweep spends it on.
cat > "$TMP/scan.json" <<'JSON'
[
  {"id":"tk-live",   "issue_type":"task", "description":"queued for a reaction", "title":"live",   "created_at":"2026-01-01T00:00:00Z", "metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.proactive"}},
  {"id":"tk-done",   "issue_type":"task", "description":"its workflow ended",    "title":"done",   "created_at":"2026-01-02T00:00:00Z", "metadata":{}},
  {"id":"tk-orphan", "issue_type":"task", "description":"its pour never landed", "title":"orphan", "created_at":"2026-01-03T00:00:00Z", "metadata":{}},
  {"id":"tk-fresh",  "issue_type":"task", "description":"never slung",           "title":"fresh",  "created_at":"2026-01-04T00:00:00Z", "metadata":{}}
]
JSON
cat > "$TMP/roots.json" <<'JSON'
[
  {"id":"tk-root-live", "status":"in_progress", "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cv-live"}},
  {"id":"tk-root-done", "status":"closed",      "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cv-done"}}
]
JSON
cat > "$TMP/convoys.json" <<'JSON'
[
  {"id":"tk-cv-live",   "issue_type":"convoy", "dependencies":[{"type":"tracks","depends_on_id":"tk-live"}]},
  {"id":"tk-cv-done",   "issue_type":"convoy", "dependencies":[{"type":"tracks","depends_on_id":"tk-done"}]},
  {"id":"tk-cv-orphan", "issue_type":"convoy", "dependencies":[{"type":"tracks","depends_on_id":"tk-orphan"}]}
]
JSON
cat > "$TMP/beads.json" <<'JSON'
{"tk-live": {"metadata":{}}, "tk-done": {"metadata":{}}, "tk-orphan": {"metadata":{}}, "tk-fresh": {"metadata":{}}}
JSON

echo "# scan drops a bead a live workflow already drives, keeps the rest"
OUT="$(bash "$SCRIPT" scan --json 2>"$TMP/scan.err")"
ERR="$(cat "$TMP/scan.err")"
IDS="$(printf '%s' "$OUT" | jq -r '.[].id' | sort | tr '\n' ' ')"
hasnt "$IDS" "tk-live" "(INFLIGHT-DROP) a bead tracked by a convoy a live root names is not a candidate"
has "$IDS" "tk-done" "(INFLIGHT-KEEP) …a bead whose workflow root is closed still is"
has "$IDS" "tk-orphan" "(INFLIGHT-KEEP) …so is a bead whose convoy no root names"
has "$IDS" "tk-fresh" "(INFLIGHT-KEEP) …and a bead no convoy tracks"
has "$ERR" "1 candidate(s) already have a live workflow" "(INFLIGHT-DROP) …and the sweep says how many it left out"

echo "# the sling slot goes to a bead with no live workflow"
OUT="$(GC_PROACTIVE_SLING_CAP=1 bash "$SCRIPT" scan --sling 2>&1)"
hasnt "$OUT" "at tk-live" "(INFLIGHT-SLING) the in-flight bead is never slung"
has "$OUT" "would sling mol-first-reaction at tk-done" "(INFLIGHT-SLING) …the cap's one slot goes to the next candidate"

echo "# an unreadable workflow read drops nothing"
printf 'not json' > "$TMP/roots.json"
IDS="$(bash "$SCRIPT" scan --json 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-live" "(INFLIGHT-FAILOPEN) with the roots unreadable, the bead stays a candidate (gc sling's own check still refuses it)"

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

# --- the sling guard refuses a bead a live workflow already drives ----------
# gc sling refuses a second live workflow of the same formula on a bead but pours
# one of another formula beside it, so a first reaction slung at a bead whose
# mol-polecat-work is still queued races that build. sling_live_workflow_guard
# joins the convoys tracking the bead (its "dependents" here, the rows
# `gc bd dep list --direction up -t tracks` returns) to the workflow roots
# (roots.json): a root is live until it closes, whatever gc.execution_routed_to
# the pour left on the bead. None of these beads carries a reaction marker.
#   tk-building     a convoy a live mol-polecat-work root names tracks it
#   tk-reacting     a convoy a live mol-first-reaction root names tracks it
#   tk-built        its root closed; the pour's gc.execution_routed_to remains
#   tk-retired      tracked only by a convoy no root names
#   tk-fresh        no convoy tracks it
#   tk-garbled      its tracking convoys cannot be read
cat > "$TMP/beads.json" <<'JSON'
{
  "tk-building": {"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"},
                  "dependents":[{"id":"tk-cv-building","issue_type":"convoy","status":"open","dependency_type":"tracks"}]},
  "tk-reacting": {"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.proactive"},
                  "dependents":[{"id":"tk-cv-reacting","issue_type":"convoy","status":"open","dependency_type":"tracks"}]},
  "tk-built":    {"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"},
                  "dependents":[{"id":"tk-cv-built","issue_type":"convoy","status":"open","dependency_type":"tracks"}]},
  "tk-retired":  {"metadata":{},
                  "dependents":[{"id":"tk-cv-retired","issue_type":"convoy","status":"closed","dependency_type":"tracks"}]},
  "tk-fresh":    {"metadata":{}},
  "tk-garbled":  {"metadata":{}, "dependents":"not a list"},
  "tk-reacted-building": {"metadata":{"gc.first_reaction":"actionable"},
                  "dependents":[{"id":"tk-cv-building","issue_type":"convoy","status":"open","dependency_type":"tracks"}]}
}
JSON
cat > "$TMP/roots.json" <<'JSON'
[
  {"id":"tk-root-building", "status":"in_progress", "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work",   "gc.input_convoy_id":"tk-cv-building"}},
  {"id":"tk-root-reacting", "status":"open",        "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction", "gc.input_convoy_id":"tk-cv-reacting"}},
  {"id":"tk-root-built",    "status":"closed",      "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work",   "gc.input_convoy_id":"tk-cv-built"}}
]
JSON

echo "# sling refuses a bead a queued build drives, naming its root"
set +e
OUT="$(bash "$SCRIPT" sling tk-building 2>&1)"; RC=$?
set -e
eq "$RC" 4 "(LIVE-SKIP) sling of a bead a live workflow drives exits RC_LIVE_WORKFLOW (4)"
has "$OUT" "tk-root-building (mol-polecat-work)" "(LIVE-SKIP) …naming the root and its formula"
hasnt "$OUT" "would sling" "(LIVE-SKIP) …nothing dispatched"

echo "# a live first reaction is a live workflow too"
set +e
OUT="$(bash "$SCRIPT" sling tk-reacting 2>&1)"; RC=$?
set -e
eq "$RC" 4 "(LIVE-SKIP) sling of a bead a live mol-first-reaction drives exits 4"
hasnt "$OUT" "would sling" "(LIVE-SKIP) …nothing dispatched"

echo "# a closed root frees the bead, whatever gc.execution_routed_to the pour left"
set +e
OUT="$(bash "$SCRIPT" sling tk-built 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-ENDED) sling of a bead whose workflow root closed exits 0"
has "$OUT" "would sling mol-first-reaction at tk-built" "(LIVE-ENDED) …and dispatches"

echo "# a convoy no root names, or no convoy at all, drives nothing"
set +e
OUT="$(bash "$SCRIPT" sling tk-retired 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-NONE) a convoy no live root names does not hold the bead"
set +e
OUT="$(bash "$SCRIPT" sling tk-fresh 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-NONE) …nor does having no convoy"
has "$OUT" "would sling mol-first-reaction at tk-fresh" "(LIVE-NONE) …which dispatches"

echo "# a reacted bead reports the reaction first, even when a workflow drives it"
set +e
OUT="$(bash "$SCRIPT" sling tk-reacted-building 2>&1)"; RC=$?
set -e
eq "$RC" 3 "(LIVE-ORDER) a reacted bead exits RC_ALREADY_REACTED (3), not 4"

# Two candidates, the driven one oldest so it ranks first: with a cap of one,
# the slot shows whether its skip was counted.
cat > "$TMP/scan.json" <<'JSON'
[
  {"id":"tk-building", "issue_type":"task", "description":"queued for a polecat", "title":"building", "created_at":"2026-01-01T00:00:00Z", "metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-fresh",    "issue_type":"task", "description":"never slung",          "title":"fresh",    "created_at":"2026-01-02T00:00:00Z", "metadata":{}}
]
JSON
echo "# a sweep skips a driven bead without spending a cap slot on it"
OUT="$(GC_PROACTIVE_SLING_CAP=1 bash "$SCRIPT" scan --sling 2>&1)"
hasnt "$OUT" "would sling mol-first-reaction at tk-building" "(LIVE-SWEEP) the driven bead is never slung"
has "$OUT" "would sling mol-first-reaction at tk-fresh" "(LIVE-SWEEP) …the cap's one slot goes to the next candidate"
has "$OUT" "1 driven by a live workflow, not counted" "(LIVE-SWEEP) …and the sweep names the uncounted skip"

echo "# a read that fails is not proof that no workflow drives the bead"
set +e
OUT="$(bash "$SCRIPT" sling tk-garbled 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(LIVE-FAILCLOSED) unreadable tracking convoys fail the sling closed (exit 1)"
has "$OUT" "cannot tell whether a live workflow already drives tk-garbled" "(LIVE-FAILCLOSED) …saying why"
hasnt "$OUT" "would sling" "(LIVE-FAILCLOSED) …nothing dispatched"
printf 'not json' > "$TMP/roots.json"
set +e
OUT="$(bash "$SCRIPT" sling tk-building 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(LIVE-FAILCLOSED) unreadable roots fail the sling closed for a tracked bead"
hasnt "$OUT" "would sling" "(LIVE-FAILCLOSED) …nothing dispatched"
set +e
OUT="$(bash "$SCRIPT" sling tk-fresh 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-FAILCLOSED) a bead no convoy tracks needs no roots read, so it still proceeds"
rm -f "$TMP/roots.json"

# The fixture seam replaces the guard's two gc reads, so it cannot catch a wrong
# flag on them. Drive the live path against a stub gc that answers each read
# only in its exact shape and fails anything else. bd's not-found error is an
# answer (no workflow drives a bead that does not exist); any other failed read
# is not, so the sling fails closed on it.
STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/gc" <<'SH'
#!/bin/sh
case "$*" in
  "rig list --json") printf '{"rigs":[]}' ;;
  "bd show "*" --json") printf '[{"id":"%s","metadata":{}}]' "$3" ;;
  "bd dep list tk-live-driven --direction up -t tracks --json")
      printf '[{"id":"tk-cv-live","issue_type":"convoy","status":"open","dependency_type":"tracks"}]' ;;
  "bd dep list tk-live-free --direction up -t tracks --json") printf '[]' ;;
  "bd dep list tk-live-missing --direction up -t tracks --json")
      printf '{"error":"resolving tk-live-missing: no issue found matching \\"tk-live-missing\\""}'; exit 1 ;;
  "bd list --has-metadata-key gc.input_convoy_id --include-ephemeral --brief --json --limit 0")
      printf '[{"id":"tk-root-live","status":"in_progress","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"tk-cv-live"}}]' ;;
  "sling "*) printf 'stub gc sling %s\n' "$*" ;;
  *) printf '{"error":"database is locked"}'; exit 1 ;;
esac
SH
chmod +x "$STUB/gc"
live_sling() { env -u GC_PROACTIVE_FIXTURE PATH="$STUB:$PATH" bash "$SCRIPT" sling "$1" --dry-run 2>&1; }

echo "# the live reads: a live root names a convoy that tracks the bead"
set +e
OUT="$(live_sling tk-live-driven)"; RC=$?
set -e
eq "$RC" 4 "(LIVE-READS) the live path refuses a bead a live root drives (exit 4)"
has "$OUT" "tk-root-live (mol-polecat-work)" "(LIVE-READS) …naming the root"
hasnt "$OUT" "stub gc sling" "(LIVE-READS) …and never reaches gc sling"
set +e
OUT="$(live_sling tk-live-free)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-READS) a bead no convoy tracks proceeds"
has "$OUT" "stub gc sling" "(LIVE-READS) …to the dry-run sling"
set +e
OUT="$(live_sling tk-live-missing)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-READS) a bead bd does not know proceeds, so gc sling names it missing"
has "$OUT" "stub gc sling" "(LIVE-READS) …to the dry-run sling"
set +e
OUT="$(live_sling tk-live-broken)"; RC=$?
set -e
eq "$RC" 1 "(LIVE-READS) any other failed read fails the sling closed (exit 1)"
has "$OUT" "cannot tell whether a live workflow already drives tk-live-broken" "(LIVE-READS) …saying why"
hasnt "$OUT" "stub gc sling" "(LIVE-READS) …and never reaches gc sling"

echo
echo "gc-proactive stand-down: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
