#!/usr/bin/env bash
# Hermetic test for tools/gc-proactive.sh: the live-intake stand-down,
# the dispatch-path drop, the fail-closed-on-unset-GC_RIG sweep guard, and the
# scan's drop of a bead a live workflow already drives (INFLIGHT-*).
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
# A bead with a dispatch path (assets/scripts/dispatch-path.sh: a route or an
# arm) already has its dispatch decided, so a first reaction would only
# second-guess it:
#   (DISPATCH-DROP) scan_precision_filter drops a bead carrying any dispatch-path key
#   (ARMED-DROP)    …among them a full arm record and an arm capped at its failure cap
#   (DISPATCH-KEEP) …while a raw input, and a bead whose keys are blank, stay candidates
#   (ARMED-SWEEP)   a scan --sling sweep reacts to raw input and never to those beads
#   (BOTH-READS)    on the live read path, one sweep drops both a bead with a
#                   dispatch path and a bead a live workflow drives (INFLIGHT-*)
#
# gc-proactive.sh is a bash script (process substitution), so it is invoked via
# bash, not sh.
#
# The sling also refuses a bead a live workflow already drives (LIVE-*), and
# fails closed when it cannot read whether one does. The scan's drop and the
# sling guard read one definition of a live workflow, and AGREE-* holds each
# caller to it on one store state.
#
# A reaction's worker reads its subject and writes the disposition back to it,
# so the sling files nothing for a subject its own store does not prove present
# (SUBJECT-ABSENT, SUBJECT-UNPROVEN). A subject deleted after that proof fails
# the guards' reads closed rather than reading as untracked (SUBJECT-VANISHED).
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
# guards read beads.json, and a sling that passes the guards prints the reaction
# bead it would file rather than filing it.
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
hasnt "$OUT" "would file a reaction bead" "(SLING-SKIP) …nothing dispatched"

echo "# an unmarked bead still proceeds to the dispatch"
set +e
OUT="$(bash "$SCRIPT" sling tk-plain 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(SLING-GO) sling of an unmarked bead exits 0"
has "$OUT" "would file a reaction bead tracking tk-plain" "(SLING-GO) …and files a reaction bead (fixture dry line)"

echo "# sling refuses a bead the store does not hold"
set +e
OUT="$(bash "$SCRIPT" sling tk-nosuch 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(SUBJECT-ABSENT) sling of a bead beads.json does not list exits 1"
has "$OUT" "tk-nosuch is absent from the store its prefix names" "(SUBJECT-ABSENT) …saying why"
hasnt "$OUT" "would file a reaction bead" "(SUBJECT-ABSENT) …nothing dispatched"

# --- a bead with a dispatch path is not a scan candidate --------------------
# A route or an arm already decides a bead's dispatch. An armed bead is ready,
# unassigned and unrouted from its own blockers' close until the next
# deferred-dispatch reconcile pass, so the arm is all that sets it apart from
# raw input. tk-armed carries the record deferred-dispatch.sh arm writes.
# tk-capped is an arm the reconcile pass stopped retrying at its failure cap,
# which waits on the visit the cap filed. One more bead per dispatch-path key
# carries only that key. The keys are read from the shared definition, so a key
# added there is covered here with no edit to this file. tk-blank carries every
# key with a blank value, which names no queue and no sling target, so it is
# raw input like tk-raw. All pass every other clause (task type, a description,
# no reaction or work markers, top-level).
# shellcheck source=../assets/scripts/dispatch-path.sh
. "$HERE/../assets/scripts/dispatch-path.sh"
PATH_KEYS="$(jq -nr "$DISPATCH_PATH_JQ"'dispatch_path_keys[]')"
[ -n "$PATH_KEYS" ] && ok "(DISPATCH) the shared definition lists the dispatch-path keys" \
    || bad "(DISPATCH) the shared definition lists the dispatch-path keys (read back empty)"
jq -n --arg keys "$PATH_KEYS" '
  ($keys | split("\n") | map(select(length > 0))) as $k
  | [ {"id":"tk-raw",    "issue_type":"task", "description":"a raw input bead", "title":"raw input", "metadata":{}},
      {"id":"tk-armed",  "issue_type":"task", "description":"a blocked follow-up armed by hand", "title":"armed follow-up",
       "metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_armed_by":"gc-toolkit/gc-toolkit.mechanik","gc.dispatch_when_ready_armed_at":"2026-10-01T00:00:00Z","gc.dispatch_when_ready_reason":"waits for tk-blocker to land"}},
      {"id":"tk-capped", "issue_type":"task", "description":"an arm past its failure cap", "title":"capped arm",
       "metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_fail_count":3}},
      {"id":"tk-blank",  "issue_type":"task", "description":"dispatch-path keys left blank", "title":"blank keys",
       "metadata": ($k | map({key: ., value: " "}) | from_entries)} ]
    + [ $k[] | {"id": ("tk-path-" + .), "issue_type": "task", "description": "a bead with a dispatch path",
                "title": ("dispatch path " + .), "metadata": {(.): "gc-toolkit/gc-toolkit.polecat"}} ]' > "$TMP/scan.json"

echo "# scan_precision_filter drops a bead with a dispatch path, keeps raw input"
IDS="$(bash "$SCRIPT" scan --json 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-raw" "(DISPATCH-KEEP) a raw input beside the routed and armed beads is still a candidate"
has "$IDS" "tk-blank" "(DISPATCH-KEEP) …and so is a bead whose dispatch-path keys are blank"
for k in $PATH_KEYS; do
    hasnt "$IDS" "tk-path-$k" "(DISPATCH-DROP) a bead carrying $k is not a scan candidate"
done
hasnt "$IDS" "tk-armed" "(ARMED-DROP) an armed bead is not a scan candidate"
hasnt "$IDS" "tk-capped" "(ARMED-DROP) …nor an arm the reconcile pass stopped retrying"

# The store holds every bead the scan read, so the sling's subject gate finds
# each one the sweep reaches.
jq 'map({key: .id, value: {metadata: .metadata}}) | from_entries' "$TMP/scan.json" > "$TMP/beads.json"

echo "# a scan --sling sweep reacts to raw input and never to a bead with a dispatch path"
set +e
OUT="$(bash "$SCRIPT" scan --sling 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(ARMED-SWEEP) the sweep exits 0"
has "$OUT" "would file a reaction bead tracking tk-raw" "(ARMED-SWEEP) the sweep files a first reaction at the raw input"
hasnt "$OUT" "tk-armed" "(ARMED-SWEEP) …and none at the armed bead"
hasnt "$OUT" "tk-capped" "(ARMED-SWEEP) …nor at the capped arm"
for k in $PATH_KEYS; do
    hasnt "$OUT" "tk-path-$k" "(ARMED-SWEEP) …nor at the bead carrying $k"
done

# --- fail closed with no rig context --------------------------------------
# resolve_pool_target dies when GC_RIG is unset, so a sling has no pool to route
# to. The --sling sweep must abort ONCE, not surface that failure and attempt
# a reaction routed to an empty target per candidate. Two unmarked candidates make "once, not
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
hasnt "$OUT" "would file a reaction bead" "(SWEEP-FAILCLOSED) …no empty-target dispatch attempted"
NSET="$(printf '%s\n' "$OUT" | grep -c 'set GC_RIG' || true)"
eq "$NSET" 1 "(SWEEP-FAILCLOSED) …the set-GC_RIG guidance surfaces once, not per candidate"

echo "# a direct sling with no rig context also fails closed"
set +e
OUT="$(env -u GC_RIG bash "$SCRIPT" sling tk-a 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] && ok "(SLING-FAILCLOSED) sling exits non-zero when GC_RIG is unset" || bad "(SLING-FAILCLOSED) sling exited 0 with no rig context (got $RC)"
hasnt "$OUT" "would file a reaction bead" "(SLING-FAILCLOSED) …nothing dispatched"

# --- a bead a live workflow already drives is not offered -----------------
# roots.json and convoys.json stand in for the two reads scan_drop_inflight
# takes. tk-live is tracked by a convoy that a live workflow root names, so the
# sling guard would refuse it. tk-done's convoy is named only by a closed root
# (its workflow ended), tk-orphan's convoy by no root at all, and tk-fresh has
# no convoy. Only tk-live leaves the page. tk-live is the oldest, so it ranks first,
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
hasnt "$OUT" "tracking tk-live" "(INFLIGHT-SLING) the in-flight bead is never reacted to"
has "$OUT" "would file a reaction bead tracking tk-done" "(INFLIGHT-SLING) …the cap's one slot goes to the next candidate"

echo "# an unreadable read drops nothing, and the sweep says so"
cp "$TMP/roots.json" "$TMP/roots.good"
printf 'not json' > "$TMP/roots.json"
IDS="$(bash "$SCRIPT" scan --json 2>"$TMP/scan.err" | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-live" "(INFLIGHT-FAILOPEN) with the roots unreadable, the bead stays a candidate (the sling guard still refuses it)"
has "$(cat "$TMP/scan.err")" "could not read the workflow roots or the open convoys" "(INFLIGHT-FAILOPEN) …and the sweep logs that it went unfiltered"
cp "$TMP/roots.good" "$TMP/roots.json"
printf '{"error":"database is locked"}' > "$TMP/convoys.json"
IDS="$(bash "$SCRIPT" scan --json 2>"$TMP/scan.err" | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-live" "(INFLIGHT-FAILOPEN) an unreadable convoy read keeps the bead too"
has "$(cat "$TMP/scan.err")" "could not read the workflow roots or the open convoys" "(INFLIGHT-FAILOPEN) …and logs it"
rm -f "$TMP/roots.json" "$TMP/roots.good" "$TMP/convoys.json"

# --- the scan's drop and the sling guard read one definition ----------------
# One store state, seen through each caller's reads. The scan reads roots.json
# and convoys.json, which holds the open convoys only. The guard reads each
# bead's "dependents" in beads.json, every convoy tracking it, closed ones
# included, and roots.json.
#   tk-ag-live      an open convoy a live workflow root names tracks it
#   tk-ag-ended     the root that names its convoy is closed
#   tk-ag-scope     a live bead names its convoy, but it is not a workflow root
#   tk-ag-closedcv  a live workflow root names its convoy, which is closed
#   tk-ag-none      no convoy tracks it
# The guard refuses tk-ag-live and tk-ag-closedcv. The scan drops tk-ag-live
# only: it cannot see the closed convoy, so it keeps a bead the guard refuses,
# and it drops nothing the guard would sling.
jq -n '[ "tk-ag-live", "tk-ag-ended", "tk-ag-scope", "tk-ag-closedcv", "tk-ag-none" ]
  | to_entries | map({id: .value, issue_type: "task", description: "a raw input bead", title: .value,
                      created_at: "2026-02-0\(.key + 1)T00:00:00Z", metadata: {}})' > "$TMP/scan.json"
cat > "$TMP/roots.json" <<'JSON'
[
  {"id":"tk-root-ag-live",     "status":"in_progress", "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work",   "gc.input_convoy_id":"tk-cv-ag-live"}},
  {"id":"tk-root-ag-ended",    "status":"closed",      "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work",   "gc.input_convoy_id":"tk-cv-ag-ended"}},
  {"id":"tk-root-ag-scope",    "status":"open",        "metadata":{"gc.kind":"scope",                                          "gc.input_convoy_id":"tk-cv-ag-scope"}},
  {"id":"tk-root-ag-closedcv", "status":"open",        "metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction", "gc.input_convoy_id":"tk-cv-ag-closedcv"}}
]
JSON
cat > "$TMP/convoys.json" <<'JSON'
[
  {"id":"tk-cv-ag-live",  "issue_type":"convoy", "status":"open", "dependencies":[{"type":"tracks","depends_on_id":"tk-ag-live"}]},
  {"id":"tk-cv-ag-ended", "issue_type":"convoy", "status":"open", "dependencies":[{"type":"tracks","depends_on_id":"tk-ag-ended"}]},
  {"id":"tk-cv-ag-scope", "issue_type":"convoy", "status":"open", "dependencies":[{"type":"tracks","depends_on_id":"tk-ag-scope"}]}
]
JSON
cat > "$TMP/beads.json" <<'JSON'
{
  "tk-ag-live":     {"metadata":{}, "dependents":[{"id":"tk-cv-ag-live",     "issue_type":"convoy","status":"open",  "dependency_type":"tracks"}]},
  "tk-ag-ended":    {"metadata":{}, "dependents":[{"id":"tk-cv-ag-ended",    "issue_type":"convoy","status":"open",  "dependency_type":"tracks"}]},
  "tk-ag-scope":    {"metadata":{}, "dependents":[{"id":"tk-cv-ag-scope",    "issue_type":"convoy","status":"open",  "dependency_type":"tracks"}]},
  "tk-ag-closedcv": {"metadata":{}, "dependents":[{"id":"tk-cv-ag-closedcv", "issue_type":"convoy","status":"closed","dependency_type":"tracks"}]},
  "tk-ag-none":     {"metadata":{}}
}
JSON

echo "# the scan drops a subset of what the sling guard refuses"
DROPPED="$(bash "$SCRIPT" scan --json 2>/dev/null \
    | jq -r --slurpfile all "$TMP/scan.json" '[ $all[0][].id ] - [ .[].id ] | join(" ")')"
REFUSED=""
for b in tk-ag-live tk-ag-ended tk-ag-scope tk-ag-closedcv tk-ag-none; do
    set +e
    bash "$SCRIPT" sling "$b" >/dev/null 2>&1; RC=$?
    set -e
    if [ "$RC" -eq 4 ]; then REFUSED="${REFUSED:+$REFUSED }$b"; fi
done
eq "$DROPPED" "tk-ag-live" "(AGREE-SCAN) the scan drops only the bead an open convoy ties to a live workflow root"
eq "$REFUSED" "tk-ag-live tk-ag-closedcv" "(AGREE-GUARD) the guard refuses that bead and the one a closed convoy ties to a live workflow root"
rm -f "$TMP/roots.json" "$TMP/convoys.json"

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
# A reaction bead is no workflow on its subject, so nothing in the filing itself
# notices a queued mol-polecat-work on the subject, and a first reaction filed at
# a bead whose build is still queued races that build. sling_live_workflow_guard
# joins the convoys tracking the bead (its "dependents" here, the rows
# `gc bd dep list --direction up -t tracks` returns) to the workflow roots
# (roots.json): a root is live until it closes, whatever gc.execution_routed_to
# the pour left on the bead. No open reaction bead tracks any of them but
# tk-reacted-building.
#   tk-building     a convoy a live mol-polecat-work root names tracks it
#   tk-reacting     a convoy a live pre-cutover mol-first-reaction root names
#                   tracks it
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
  "tk-reacted-building": {"metadata":{},
                  "dependents":[{"id":"tk-cv-building","issue_type":"convoy","status":"open","dependency_type":"tracks"}]},
  "tk-r-reacted-building": {"status":"open","metadata":{"task_kind":"reaction","gc.reaction_subject":"tk-reacted-building"}}
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
hasnt "$OUT" "would file a reaction bead" "(LIVE-SKIP) …nothing dispatched"

echo "# a live pre-cutover first-reaction molecule is a live workflow too"
set +e
OUT="$(bash "$SCRIPT" sling tk-reacting 2>&1)"; RC=$?
set -e
eq "$RC" 4 "(LIVE-SKIP) sling of a bead a live mol-first-reaction molecule drives exits 4"
hasnt "$OUT" "would file a reaction bead" "(LIVE-SKIP) …nothing dispatched"

echo "# a closed root frees the bead, whatever gc.execution_routed_to the pour left"
set +e
OUT="$(bash "$SCRIPT" sling tk-built 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-ENDED) sling of a bead whose workflow root closed exits 0"
has "$OUT" "would file a reaction bead tracking tk-built" "(LIVE-ENDED) …and files a reaction"

echo "# a convoy no root names, or no convoy at all, drives nothing"
set +e
OUT="$(bash "$SCRIPT" sling tk-retired 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-NONE) a convoy no live root names does not hold the bead"
set +e
OUT="$(bash "$SCRIPT" sling tk-fresh 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-NONE) …nor does having no convoy"
has "$OUT" "would file a reaction bead tracking tk-fresh" "(LIVE-NONE) …which files a reaction"

echo "# a bead with an open reaction reports the reaction first, even when a workflow drives it"
set +e
OUT="$(bash "$SCRIPT" sling tk-reacted-building 2>&1)"; RC=$?
set -e
eq "$RC" 3 "(LIVE-ORDER) a bead an open reaction tracks exits RC_ALREADY_REACTED (3), not 4"
has "$OUT" "already has an open first reaction (tk-r-reacted-building)" "(LIVE-ORDER) …naming the open reaction"

# Two candidates, the driven one oldest so it ranks first: with a cap of one,
# the slot shows whether its skip was counted. convoys.json, the scan's convoy
# read, holds no convoy for tk-building. That is the view a sweep has when the
# pour that drives the bead lands after the scan's reads, so the scan offers
# the bead. The guard's read at sling time finds tk-cv-building, which a live
# root names, and refuses it.
cat > "$TMP/scan.json" <<'JSON'
[
  {"id":"tk-building", "issue_type":"task", "description":"queued for a polecat", "title":"building", "created_at":"2026-01-01T00:00:00Z", "metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-fresh",    "issue_type":"task", "description":"never reacted to",     "title":"fresh",    "created_at":"2026-01-02T00:00:00Z", "metadata":{}}
]
JSON
printf '[]' > "$TMP/convoys.json"
echo "# a sweep skips a driven bead without spending a cap slot on it"
OUT="$(GC_PROACTIVE_SLING_CAP=1 bash "$SCRIPT" scan --sling 2>&1)"
hasnt "$OUT" "already have a live workflow" "(LIVE-SWEEP) the scan, whose reads predate the pour, offers the driven bead"
hasnt "$OUT" "tracking tk-building" "(LIVE-SWEEP) the driven bead is never reacted to"
has "$OUT" "would file a reaction bead tracking tk-fresh" "(LIVE-SWEEP) …the cap's one slot goes to the next candidate"
has "$OUT" "1 driven by a live workflow, not counted" "(LIVE-SWEEP) …and the sweep names the uncounted skip"

echo "# a read that fails is not proof that no workflow drives the bead"
set +e
OUT="$(bash "$SCRIPT" sling tk-garbled 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(LIVE-FAILCLOSED) unreadable tracking convoys fail the sling closed (exit 1)"
has "$OUT" "cannot tell whether a live workflow already drives tk-garbled" "(LIVE-FAILCLOSED) …saying why"
hasnt "$OUT" "would file a reaction bead" "(LIVE-FAILCLOSED) …nothing dispatched"
printf 'not json' > "$TMP/roots.json"
set +e
OUT="$(bash "$SCRIPT" sling tk-building 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(LIVE-FAILCLOSED) unreadable roots fail the sling closed for a tracked bead"
hasnt "$OUT" "would file a reaction bead" "(LIVE-FAILCLOSED) …nothing dispatched"
set +e
OUT="$(bash "$SCRIPT" sling tk-fresh 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-FAILCLOSED) a bead no convoy tracks needs no roots read, so it still proceeds"
rm -f "$TMP/roots.json" "$TMP/convoys.json"

# The fixture seam replaces every gc read the scan's drop and the sling guards
# take, so it cannot catch a wrong flag on them. Drive the live path against a
# stub gc that answers each read only in its exact shape and fails anything
# else. The subject gate runs the real bead-store.sh, which asks the store the
# id's prefix names by path. The stub's rig list maps tk to a path with no
# .beads directory, so bead-store.sh asks `gc bd --db <path>/.beads show` while
# rig_beads_db pins nothing and the tool's own reads keep their unpinned shapes.
# The gate is the one read that classifies a not-found. Every later read answers
# only with an array, so a not-found there, a subject deleted after the gate,
# fails the sling closed like any other failed read. The
# roots read and the convoy read each carry a raw control byte in a title, as a
# live store can, so the drop works only when both reads are scrubbed. Setting
# STUB_CONVOYS=locked fails the convoy read, and STUB_ROOTS=locked the roots
# read. STUB_STATE names a directory the stub keeps call state in.
STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/gc" <<'SH'
#!/bin/sh
case "$*" in
  "rig list --json") printf '{"rigs":[{"name":"gc-toolkit","prefix":"tk","path":"/nonexistent/gc-toolkit"}]}' ;;
  "bd --db /nonexistent/gc-toolkit/.beads show tk-live-missing --json")
      printf '{"error":"no issues found matching the provided IDs","schema_version":1}'
      printf 'Issue tk-live-missing not found\n' >&2; exit 1 ;;
  "bd --db /nonexistent/gc-toolkit/.beads show tk-live-partial --json")
      printf '[{"id":"tk-live-partial-twin","metadata":{}}]' ;;
  "bd --db /nonexistent/gc-toolkit/.beads show "*" --json") printf '[{"id":"%s","metadata":{}}]' "$5" ;;
  "bd show "*" --json") printf '[{"id":"%s","metadata":{}}]' "$3" ;;
  "bd list --status open,in_progress --metadata-field gc.reaction_subject="*" --limit 0 --json") printf '[]' ;;
  "bd dep list tk-live-driven --direction up -t tracks --json")
      printf '[{"id":"tk-cv-live","issue_type":"convoy","status":"open","dependency_type":"tracks"}]' ;;
  "bd dep list tk-live-free --direction up -t tracks --json") printf '[]' ;;
  "bd dep list tk-live-partial --direction up -t tracks --json") printf '[]' ;;
  "bd dep list tk-live-vanished --direction up -t tracks --json")
      printf '{"error":"resolving tk-live-vanished: no issue found matching \\"tk-live-vanished\\""}'; exit 1 ;;
  "bd dep list tk-live-gone-late --direction up -t tracks --json")
      # Present for the dedup's read, deleted before the live-workflow guard's.
      if [ -f "$STUB_STATE/gone-late" ]; then
          printf '{"error":"resolving tk-live-gone-late: no issue found matching \\"tk-live-gone-late\\""}'; exit 1
      fi
      : > "$STUB_STATE/gone-late"; printf '[]' ;;
  "bd list --has-metadata-key gc.input_convoy_id --include-ephemeral --brief --json --limit 0")
      if [ "${STUB_ROOTS:-}" = locked ]; then printf '{"error":"database is locked"}'; exit 1; fi
      printf '[{"id":"tk-root-live","status":"in_progress","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"tk-cv-live"}},'
      printf '{"id":"tk-root-scan","status":"open","title":"reaction root\001","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-first-reaction","gc.input_convoy_id":"tk-cv-scan"}}]' ;;
  "bd ready --metadata-field gc.proactive=1 --unassigned --exclude-type=epic --json --sort oldest --limit 0") printf '[]' ;;
  "bd ready --unassigned --exclude-type=epic --json --sort oldest --limit 0")
      printf '[{"id":"tk-scan-driven","issue_type":"task","description":"queued for a reaction","title":"driven","created_at":"2026-01-01T00:00:00Z","metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.proactive"}},'
      printf '{"id":"tk-scan-free","issue_type":"task","description":"never slung","title":"free","created_at":"2026-01-02T00:00:00Z","metadata":{}}]' ;;
  "bd list --type=convoy --json --limit 0")
      if [ "${STUB_CONVOYS:-}" = locked ]; then printf '{"error":"database is locked"}'; exit 1; fi
      printf '[{"id":"tk-cv-scan","issue_type":"convoy","status":"open","title":"input convoy for tk-scan-driven\001","dependencies":[{"issue_id":"tk-cv-scan","depends_on_id":"tk-scan-driven","type":"tracks"}]}]' ;;
  *) printf '{"error":"database is locked"}'; exit 1 ;;
esac
SH
chmod +x "$STUB/gc"
live_sling() { env -u GC_PROACTIVE_FIXTURE PATH="$STUB:$PATH" "${@:2}" bash "$SCRIPT" sling "$1" --dry-run 2>&1; }
live_scan() { env -u GC_PROACTIVE_FIXTURE PATH="$STUB:$PATH" "$@" bash "$SCRIPT" scan --json 2>"$TMP/scan.err"; }

echo "# the scan's live reads: the roots and the open convoys, each scrubbed"
IDS="$(live_scan | jq -r '.[].id' | sort | tr '\n' ' ')"
ERR="$(cat "$TMP/scan.err")"
hasnt "$IDS" "tk-scan-driven" "(INFLIGHT-READS) the live path drops a bead an open convoy ties to a live workflow root"
has "$IDS" "tk-scan-free" "(INFLIGHT-READS) …keeps a bead no convoy tracks"
has "$ERR" "1 candidate(s) already have a live workflow" "(INFLIGHT-READS) …and counts the one it left out"
hasnt "$ERR" "could not read" "(INFLIGHT-READS) …with both reads parsed, raw control bytes and all"
IDS="$(live_scan STUB_CONVOYS=locked | jq -r '.[].id' | sort | tr '\n' ' ')"
ERR="$(cat "$TMP/scan.err")"
has "$IDS" "tk-scan-driven" "(INFLIGHT-READS) with the convoy read failing, the driven bead stays a candidate"
has "$ERR" "could not read the workflow roots or the open convoys" "(INFLIGHT-READS) …and the sweep logs that it went unfiltered"

# Both drops in one sweep, on the live read path. Each fixture case above
# exercises one drop, and the live case above feeds no bead with a dispatch path.
# Here the movable-forward ready read returns one bead per dispatch-path key, read
# from the shared definition, beside tk-scan-driven, which the stub's convoy read
# ties to a live workflow root, and tk-scan-free, which has neither. A second stub
# answers that read and passes every other call to the first.
jq -n --arg keys "$PATH_KEYS" '
  [ {"id":"tk-scan-driven", "issue_type":"task", "description":"queued for a reaction", "title":"driven",
     "created_at":"2026-01-01T00:00:00Z", "metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.proactive"}},
    {"id":"tk-scan-free", "issue_type":"task", "description":"never slung", "title":"free",
     "created_at":"2026-01-02T00:00:00Z", "metadata":{}} ]
  + [ $keys | split("\n")[] | select(length > 0)
      | {"id": ("tk-scan-path-" + .), "issue_type": "task", "description": "a bead with a dispatch path",
         "title": ("dispatch path " + .), "created_at": "2026-01-03T00:00:00Z",
         "metadata": {(.): "gc-toolkit/gc-toolkit.polecat"}} ]' > "$TMP/ready-both.json"
BOTH="$TMP/stub-both"
mkdir -p "$BOTH"
cat > "$BOTH/gc" <<SH
#!/bin/sh
case "\$*" in
  "bd ready --unassigned --exclude-type=epic --json --sort oldest --limit 0") cat "$TMP/ready-both.json" ;;
  *) exec "$STUB/gc" "\$@" ;;
esac
SH
chmod +x "$BOTH/gc"

echo "# the live path drops a bead with a dispatch path and a bead a live workflow drives in one sweep"
IDS="$(env -u GC_PROACTIVE_FIXTURE PATH="$BOTH:$PATH" bash "$SCRIPT" scan --json 2>"$TMP/scan.err" | jq -r '.[].id' | sort | tr '\n' ' ')"
for k in $PATH_KEYS; do
    hasnt "$IDS" "tk-scan-path-$k" "(BOTH-READS) the live path drops the bead carrying $k"
done
hasnt "$IDS" "tk-scan-driven" "(BOTH-READS) …and, in the same sweep, the bead a live workflow drives"
has "$IDS" "tk-scan-free" "(BOTH-READS) …and keeps the bead with neither"

echo "# the live reads: a live root names a convoy that tracks the bead"
set +e
OUT="$(live_sling tk-live-driven)"; RC=$?
set -e
eq "$RC" 4 "(LIVE-READS) the live path refuses a bead a live root drives (exit 4)"
has "$OUT" "tk-root-live (mol-polecat-work)" "(LIVE-READS) …naming the root"
hasnt "$OUT" "gc bd create" "(LIVE-READS) …and files no reaction"
set +e
OUT="$(live_sling tk-live-free)"; RC=$?
set -e
eq "$RC" 0 "(LIVE-READS) a bead no convoy tracks proceeds"
has "$OUT" "gc bd create -t task" "(LIVE-READS) …to the dry-run filing"
hasnt "$OUT" "bead-store:" "(SUBJECT-PRESENT) …past a subject gate that stays quiet on a pass"
set +e
OUT="$(live_sling tk-live-broken)"; RC=$?
set -e
eq "$RC" 1 "(LIVE-READS) any other failed read fails the sling closed (exit 1)"
has "$OUT" "could not read the tracks-edge dedup for tk-live-broken" "(LIVE-READS) …at the dedup, which reads the trackers first, saying why"
hasnt "$OUT" "gc bd create" "(LIVE-READS) …and files no reaction"
set +e
OUT="$(live_sling tk-live-driven STUB_ROOTS=locked)"; RC=$?
set -e
eq "$RC" 1 "(LIVE-READS) a roots read that fails for a tracked bead fails the sling closed (exit 1)"
has "$OUT" "cannot tell whether a live workflow already drives tk-live-driven" "(LIVE-READS) …at the live-workflow guard, saying why"
hasnt "$OUT" "gc bd create" "(LIVE-READS) …and files no reaction"

echo "# the subject gate: a reaction is filed only for a subject its own store proves present"
set +e
OUT="$(live_sling tk-live-missing)"; RC=$?
set -e
eq "$RC" 1 "(SUBJECT-ABSENT) a subject its store proves absent fails the sling closed (exit 1)"
has "$OUT" "tk-live-missing is absent from the store its prefix names" "(SUBJECT-ABSENT) …saying why"
hasnt "$OUT" "tracks-edge dedup" "(SUBJECT-ABSENT) …before any guard reads the subject"
hasnt "$OUT" "gc bd create" "(SUBJECT-ABSENT) …and files no reaction"
# bd answers an id as an exact-or-prefix match, so tk-live-partial reads back as
# tk-live-partial-twin, and every later read would let it through.
set +e
OUT="$(live_sling tk-live-partial)"; RC=$?
set -e
eq "$RC" 1 "(SUBJECT-UNPROVEN) an id its store matches only as a prefix of another bead fails the sling closed (exit 1)"
has "$OUT" "cannot prove tk-live-partial exists" "(SUBJECT-UNPROVEN) …saying why"
hasnt "$OUT" "gc bd create" "(SUBJECT-UNPROVEN) …and files no reaction"

echo "# a not-found after the gate is a subject deleted since, and fails closed like any failed read"
set +e
OUT="$(live_sling tk-live-vanished)"; RC=$?
set -e
eq "$RC" 1 "(SUBJECT-VANISHED) a not-found at the dedup fails the sling closed (exit 1)"
has "$OUT" "could not read the tracks-edge dedup for tk-live-vanished" "(SUBJECT-VANISHED) …at the dedup, saying why"
hasnt "$OUT" "gc bd create" "(SUBJECT-VANISHED) …and files no reaction"
mkdir -p "$TMP/stub-state"
set +e
OUT="$(live_sling tk-live-gone-late STUB_STATE="$TMP/stub-state")"; RC=$?
set -e
eq "$RC" 1 "(SUBJECT-VANISHED) a not-found at the live-workflow guard fails the sling closed (exit 1)"
has "$OUT" "cannot tell whether a live workflow already drives tk-live-gone-late" "(SUBJECT-VANISHED) …at that guard, saying why"
hasnt "$OUT" "gc bd create" "(SUBJECT-VANISHED) …and files no reaction"

echo
echo "gc-proactive stand-down: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
