#!/usr/bin/env bash
# Hermetic test for assets/scripts/bead-context.sh.
#
# The tool rebuilds a subject's opening context in one call, so the assertions
# target the contract that opening reads: subject core (A) with the anchor,
# first_reaction, origin and takeaway fields; context edges (D) — parent,
# relates-to (both the `relates-to` and older `related` spellings), and the
# reverse `tracks` visits — each with a count; the store that answered (E); and,
# each behind its opt-in flag, the frontier verdict over {ready, advancing,
# stuck} (B) and the direct-children epic-health snapshot (C). The advance enum,
# the cross-store fold, the fail-closed unknown, the status scope of the child
# listing, and the three `gc bd show --json` quirks each get a case.
#
# `gc` is stubbed over a file-per-bead ledger under each fake rig; a direct `bd`
# is the regression the stub fails on. No live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/bead-context.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bead-context-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# --- fake city --------------------------------------------------------------
R_TK="$TMP/rigs/gc-toolkit"; R_OR="$TMP/rigs/otherrig"; HQ="$TMP/hq"
mkdir -p "$TMP/bin" "$R_TK/.beads" "$R_OR/.beads" "$HQ/.beads"
cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"gc-toolkit","path":"$R_TK","prefix":"tk","hq":false},
  {"name":"otherrig","path":"$R_OR","prefix":"or","hq":false},
  {"name":"loomington","path":"$HQ","prefix":"lx","hq":true}
]}
JSON
export FAKE_RIGS="$TMP/rigs.json"
export FAKE_GC_LOG="$TMP/gc.log"; : > "$FAKE_GC_LOG"
export FAKE_BD_LOG="$TMP/bd.log"; : > "$FAKE_BD_LOG"
export STUB_ROOT="$TMP"
export STUB_PREFACE=""

bead() { cat > "$1/.beads/$2.json"; }   # bead <store-repo> <id>  (object on stdin)

# tk-anchor: a subject core (A) with every field the opening reads — anchor
# state, first_reaction, origin, a settled takeaway, task_kind and routing. Its
# edges (D) are the parent tk-epic, two relates deps in each spelling, and a
# reverse `tracks` visit (tk-visit, below). Its blocks are all closed — one
# same-store (embedded status), one FOREIGN in the otherrig store (no embedded
# status, the cross-store fold) — so its frontier verdict is ready. It also
# carries a description and notes; the read returns its title but never that body.
bead "$R_TK" tk-anchor <<'J'
{"id":"tk-anchor","title":"rich anchor","status":"open","issue_type":"task","priority":1,
 "assignee":"gc-toolkit/gc-toolkit.refinery","parent":"tk-epic",
 "description":"subject body prose the read must never surface",
 "notes":"## Current state\noperational notes the read must never surface",
 "metadata":{"task_kind":"rework","gc.routed_to":"","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat",
   "merge_result":"pull_request","pr_number":"9","branch":"polecat/tk-anchor","merged_target":"main","target":"main",
   "pr.machine":"progressing@a1b2c3@2026-09-02T22:00:00Z",
   "gc.first_reaction":"ruling","gc.first_reaction_at":"2026-09-02T22:23:04Z",
   "gc.first_reaction_reason":"scope and control flow unresolved","gc.first_reaction_target":"tk-frt",
   "gc.origin":"operator","gc.takeaway":"held pending the opening contract","gc.takeaway_settled":1},
 "dependencies":[
   {"id":"tk-epic","dependency_type":"parent-child","status":"open","title":"the parent epic"},
   {"id":"tk-c1","dependency_type":"blocks","status":"closed","title":"closed same-store blocker"},
   {"id":"or-far","dependency_type":"blocks","title":"foreign closed blocker"},
   {"id":"tk-rel","dependency_type":"relates-to","status":"open","title":"related work"},
   {"id":"tk-rel2","dependency_type":"related","status":"closed","title":"older-spelling related"}]}
J
bead "$R_TK" tk-c1  <<'J'
{"id":"tk-c1","title":"closed blocker","status":"closed","issue_type":"task","metadata":{}}
J
bead "$R_OR" or-far <<'J'
{"id":"or-far","title":"foreign closed blocker","status":"closed","issue_type":"task","metadata":{}}
J
# tk-visit tracks tk-anchor: the reverse edge that makes tk-anchor tracked-by it.
bead "$R_TK" tk-visit <<'J'
{"id":"tk-visit","title":"visit: tk-anchor","status":"closed","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-anchor","dependency_type":"tracks","status":"open"}]}
J

# Frontier verdict fixtures: one open unrouted blocker (stuck), one open
# pool-routed blocker (advancing), one open human-gated blocker (stuck).
bead "$R_TK" tk-stuck <<'J'
{"id":"tk-stuck","title":"held by an unrouted blocker","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-op","dependency_type":"blocks","status":"open","title":"open unrouted blocker"}]}
J
bead "$R_TK" tk-op <<'J'
{"id":"tk-op","title":"open unrouted blocker","status":"open","issue_type":"task","metadata":{}}
J
bead "$R_TK" tk-adv <<'J'
{"id":"tk-adv","title":"held by a routed blocker","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-routed","dependency_type":"blocks","status":"open","title":"routed blocker"}]}
J
bead "$R_TK" tk-routed <<'J'
{"id":"tk-routed","title":"routed blocker","status":"open","issue_type":"task",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead "$R_TK" tk-humangate <<'J'
{"id":"tk-humangate","title":"held by a human gate","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-hg","dependency_type":"blocks","status":"open","title":"human-gated blocker"}]}
J
bead "$R_TK" tk-hg <<'J'
{"id":"tk-hg","title":"human-gated blocker","status":"open","issue_type":"task",
 "metadata":{"gc.routed_to":"human"}}
J
# tk-inreview: held by a review bead the review cadence dispatched. The review
# bead's live route is CLEARED by the pour (gc.routed_to="") and its status is not
# in_progress, so it looks like an unrouted stuck blocker — but it is machine work
# the pool owns, so its advance is advancing, not stuck (tk-ikpyzn.5).
bead "$R_TK" tk-inreview <<'J'
{"id":"tk-inreview","title":"held by a review in flight","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-rev","dependency_type":"blocks","status":"open","title":"review branch -> main"}]}
J
bead "$R_TK" tk-rev <<'J'
{"id":"tk-rev","title":"review branch -> main","status":"open","issue_type":"task",
 "metadata":{"task_kind":"review","anchor_bead":"tk-inreview","gc.routed_to":"","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat-codex"}}
J
# tk-failclosed: a blocks dep whose store no rig carries and which bd could not
# embed a status for — unknown must fail closed to stuck, never read as landed.
bead "$R_TK" tk-failclosed <<'J'
{"id":"tk-failclosed","title":"fail-closed","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"zz-ghost","dependency_type":"blocks","title":"unplaceable blocker"}]}
J

# --- the transitive walk ----------------------------------------------------
# blk <store-repo> <id> <status> <metadata-json> [blocker...]: a bead whose only
# edges are open same-store blocks-deps (the status rides each edge, as a
# --brief-deps read embeds it) — or, for a blocker in another store, no status.
blk() {
  local repo="$1" id="$2" st="$3" md="$4"; shift 4
  local deps="" b
  for b in "$@"; do
    case "$b" in
      tk-*) deps="$deps${deps:+,}{\"id\":\"$b\",\"dependency_type\":\"blocks\",\"status\":\"open\",\"title\":\"$b\"}" ;;
      *)    deps="$deps${deps:+,}{\"id\":\"$b\",\"dependency_type\":\"blocks\",\"title\":\"$b\"}" ;;
    esac
  done
  printf '{"id":"%s","title":"%s","status":"%s","issue_type":"task","metadata":%s,"dependencies":[%s]}\n' \
    "$id" "$id" "$st" "$md" "$deps" > "$repo/.beads/$id.json"
}
POOL='{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}'
ARMED='{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"}'

# A routed blocker held by an orphan: one level reads it advancing, but nothing
# will ever pick up what it waits on, so it is stuck and names the orphan.
blk "$R_TK" tk-w-sub1 open '{}' tk-w-routed
blk "$R_TK" tk-w-routed open "$POOL" tk-w-orphan
blk "$R_TK" tk-w-orphan open '{}'
# An armed bead takes its blockers' verdict: moving blockers advance it ...
blk "$R_TK" tk-w-sub2 open '{}' tk-w-armed
blk "$R_TK" tk-w-armed open "$ARMED" tk-w-mover
blk "$R_TK" tk-w-mover open "$POOL"
# ... and a human gate beneath it makes it stuck, naming the gate.
blk "$R_TK" tk-w-sub3 open '{}' tk-w-armed2
blk "$R_TK" tk-w-armed2 open "$ARMED" tk-w-gate
blk "$R_TK" tk-w-gate open '{"gc.routed_to":"human"}'
# A cycle never drains: each routed bead waits on the other.
blk "$R_TK" tk-w-sub4 open '{}' tk-w-cyc-a
blk "$R_TK" tk-w-cyc-a open "$POOL" tk-w-cyc-b
blk "$R_TK" tk-w-cyc-b open "$POOL" tk-w-cyc-a
# A cross-store hop: the middle bead lives in otherrig, its orphan back in tk.
blk "$R_TK" tk-w-sub6 open '{}' or-w-mid
blk "$R_OR" or-w-mid open "$POOL" tk-w-far
blk "$R_TK" tk-w-far open '{}'
# A routed bead whose only blocker lives in another store: `gc bd show` leaves
# that edge out, so only its list row shows the orphan it waits on.
blk "$R_TK" tk-w-xs open '{}' tk-w-xmid
blk "$R_TK" tk-w-xmid open "$POOL" or-w-leaf
blk "$R_OR" or-w-leaf open '{}'
# A routed chain three deep, for the bead budget.
blk "$R_TK" tk-w-sub7 open '{}' tk-w-ch1
blk "$R_TK" tk-w-ch1 open "$POOL" tk-w-ch2
blk "$R_TK" tk-w-ch2 open "$POOL" tk-w-ch3
blk "$R_TK" tk-w-ch3 open "$POOL"
# A routed chain with a closed bead beside it: a closed row costs no budget.
blk "$R_TK" tk-w-cl open '{}' tk-w-cl1
blk "$R_TK" tk-w-cl1 open "$POOL" tk-w-clx tk-w-cl2
blk "$R_TK" tk-w-clx closed '{}'
blk "$R_TK" tk-w-cl2 open "$POOL" tk-w-cl3
blk "$R_TK" tk-w-cl3 open "$POOL"
# A routed blocker over four routed leaves: one level wider than a budget of
# three, so the read has to stop inside the level.
blk "$R_TK" tk-w-wide open '{}' tk-w-fan
blk "$R_TK" tk-w-fan open "$POOL" tk-w-f1 tk-w-f2 tk-w-f3 tk-w-f4
for i in 1 2 3 4; do blk "$R_TK" "tk-w-f$i" open "$POOL"; done
# The same fan with a closed leaf first: its row hands its share of the budget
# back, so the leaf the cut read left out is read next.
blk "$R_TK" tk-w-refund open '{}' tk-w-rfan
blk "$R_TK" tk-w-rfan open "$POOL" tk-w-rx tk-w-r1 tk-w-r2 tk-w-r3
blk "$R_TK" tk-w-rx closed '{}'
for i in 1 2 3; do blk "$R_TK" "tk-w-r$i" open "$POOL"; done
# Routed chains six and seven deep, for the depth bound: six levels are read.
blk "$R_TK" tk-w-six open '{}' tk-w-s1
for i in 1 2 3 4 5; do blk "$R_TK" "tk-w-s$i" open "$POOL" "tk-w-s$((i + 1))"; done
blk "$R_TK" tk-w-s6 open "$POOL"
blk "$R_TK" tk-w-seven open '{}' tk-w-v1
for i in 1 2 3 4 5 6; do blk "$R_TK" "tk-w-v$i" open "$POOL" "tk-w-v$((i + 1))"; done
blk "$R_TK" tk-w-v7 open "$POOL"
# A diamond: two routed blockers share one routed blocker, read once.
blk "$R_TK" tk-w-sub8 open '{}' tk-w-d1 tk-w-d2
blk "$R_TK" tk-w-d1 open "$POOL" tk-w-dshared
blk "$R_TK" tk-w-d2 open "$POOL" tk-w-dshared
blk "$R_TK" tk-w-dshared open "$POOL"
# A stuck bead stops the walk on its branch: what it waits on is never read.
blk "$R_TK" tk-w-sub9 open '{}' tk-w-stopper
blk "$R_TK" tk-w-stopper open '{}' tk-w-hidden
blk "$R_TK" tk-w-hidden open "$POOL"

# Merge anchors read their recorded merge axis, not their empty route.
blk "$R_TK" tk-w-anchors open '{}' tk-a-approval tk-a-progress tk-a-preopen tk-a-approved \
  tk-a-hold tk-a-wedged tk-a-blocked tk-a-stale tk-a-noaxis tk-a-heldstate
AX='@h1@2026-10-01T00:00:00Z'
blk "$R_TK" tk-a-approval open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"settled$AX\",\"pr_posture\":\"review_required$AX\"}"
blk "$R_TK" tk-a-progress open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"progressing$AX\",\"pr_posture\":\"changes_requested$AX\"}"
blk "$R_TK" tk-a-preopen open "{\"merge_result\":\"pre_open_gate\",\"pr.machine\":\"settled$AX\"}"
blk "$R_TK" tk-a-approved open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"settled$AX\",\"pr_posture\":\"approved$AX\"}"
blk "$R_TK" tk-a-hold open "{\"merge_result\":\"pre_open_gate\",\"merge_hold\":\"true\",\"pr.machine\":\"settled$AX\"}"
blk "$R_TK" tk-a-wedged open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"wedged-exception$AX\"}"
blk "$R_TK" tk-a-blocked open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"blocked$AX\"}"
blk "$R_TK" tk-a-stale open "{\"merge_result\":\"pull_request\",\"pr.machine\":\"settled$AX\",\"pr_posture\":\"review_required@h0@2026-09-30T00:00:00Z\"}"
blk "$R_TK" tk-a-noaxis open '{"merge_result":"pre_open_gate"}'
blk "$R_TK" tk-a-heldstate open '{"merge_result":"held","gc.routed_to":"human","gc.takeaway":"waits on a ruling"}'

# A bead's own state, one rule per blocker.
blk "$R_TK" tk-w-kinds open '{}' tk-k-blocked tk-k-validation tk-k-finding tk-k-needsyou \
  tk-k-refinery tk-k-capped tk-k-hooked tk-k-deferred tk-k-gate
blk "$R_TK" tk-k-blocked blocked "$POOL"
blk "$R_TK" tk-k-validation open '{"task_kind":"validation","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}'
blk "$R_TK" tk-k-finding open '{"task_kind":"finding","finding.disposition":"must-fix"}'
blk "$R_TK" tk-k-needsyou open '{"task_kind":"finding","finding.disposition":"needs-you"}'
blk "$R_TK" tk-k-capped open '{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat","gc.dispatch_when_ready_fail_count":"3"}'
blk "$R_TK" tk-k-hooked hooked '{}'
blk "$R_TK" tk-k-deferred deferred "$POOL"
bead "$R_TK" tk-k-gate <<'J'
{"id":"tk-k-gate","title":"held by ruling","status":"open","issue_type":"gate",
 "metadata":{"gc.routed_to":"human","gc.demand_for":"tk-w-kinds"}}
J
bead "$R_TK" tk-k-refinery <<'J'
{"id":"tk-k-refinery","title":"handed to the refinery","status":"open","issue_type":"task",
 "assignee":"gc-toolkit/gc-toolkit.refinery","metadata":{"gc.routed_to":""}}
J
bead "$R_TK" tk-w-decides <<'J'
{"id":"tk-w-decides","title":"held by a decision","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-k-decision","dependency_type":"blocks","status":"open","title":"a ruling"}]}
J
bead "$R_TK" tk-k-decision <<'J'
{"id":"tk-k-decision","title":"a ruling","status":"open","issue_type":"decision","metadata":{}}
J

# tk-epic: the horizon fixture. Its direct children (found by the reverse
# parent-child listing, never its own edges) cover every advance state: an open
# pool-routed and an in-progress child advance, as do tk-anchor — a merge anchor
# whose recorded machine axis is progressing — and tk-kid-rework, a rework bead
# whose pour cleared its route, machine work rather than a human gate. An open
# human-gated child is stuck, and so is tk-kid-armed: armed, so it takes its
# blocker's verdict, and its blocker is the human gate tk-hg. Three children sit
# in statuses a default or --status listing can leave out: a hooked child
# advances, a pinned one is a hold whatever its route, and one in a status its
# store adds is unknown to the classifier, so it fails closed. One done child is
# counted, never listed. The epic's own blocks are none, so its frontier verdict
# is ready. The plain unrouted-stuck case is covered by tk-stuck in the frontier
# section above, off the same shared classifier.
bead "$R_TK" tk-epic <<'J'
{"id":"tk-epic","title":"the epic","status":"open","issue_type":"epic","priority":2,
 "metadata":{},
 "dependencies":[{"id":"tk-relE","dependency_type":"related","status":"open","title":"related epic"}]}
J
bead "$R_TK" tk-kid-pool <<'J'
{"id":"tk-kid-pool","title":"routed child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead "$R_TK" tk-kid-prog <<'J'
{"id":"tk-kid-prog","title":"in-progress child","status":"in_progress","issue_type":"task","parent":"tk-epic","metadata":{}}
J
bead "$R_TK" tk-kid-human <<'J'
{"id":"tk-kid-human","title":"human-gated child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"human"}}
J
bead "$R_TK" tk-kid-done <<'J'
{"id":"tk-kid-done","title":"done child","status":"closed","issue_type":"task","parent":"tk-epic","metadata":{}}
J
bead "$R_TK" tk-kid-rework <<'J'
{"id":"tk-kid-rework","title":"rework child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"task_kind":"rework","gc.routed_to":""}}
J
bead "$R_TK" tk-kid-armed <<'J'
{"id":"tk-kid-armed","title":"armed child","status":"open","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"},
 "dependencies":[{"id":"tk-hg","dependency_type":"blocks","status":"open","title":"human-gated blocker"}]}
J
bead "$R_TK" tk-kid-hooked <<'J'
{"id":"tk-kid-hooked","title":"hooked child","status":"hooked","issue_type":"task","parent":"tk-epic","metadata":{}}
J
bead "$R_TK" tk-kid-pinned <<'J'
{"id":"tk-kid-pinned","title":"pinned child","status":"pinned","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J
bead "$R_TK" tk-kid-custom <<'J'
{"id":"tk-kid-custom","title":"custom-status child","status":"in_review","issue_type":"task","parent":"tk-epic",
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
J

# lx-city lives in the HQ store, which no --rig value names — only --db reaches.
bead "$HQ" lx-city <<'J'
{"id":"lx-city","title":"city bead","status":"open","issue_type":"task","metadata":{}}
J

# tk-ctrl carries a raw C0 byte (SOH \001) in its notes, the payload real bd
# emits that aborts a naive jq; scrub must remove it. tk-nul carries a raw NUL
# (\000), the C0 byte that also trips grep's binary heuristic: the notice-strip
# must run in text mode (grep -a) or grep drops the whole payload.
printf '{"id":"tk-ctrl","title":"ctl\001note","status":"open","issue_type":"task","metadata":{}}\n' \
  > "$R_TK/.beads/tk-ctrl.json"
printf '{"id":"tk-nul","title":"nul","status":"open","issue_type":"task","notes":"a\000b","metadata":{}}\n' \
  > "$R_TK/.beads/tk-nul.json"

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# Only the surface bead-context.sh touches: rig list; bd show; bd list --parent
# (children); bd dep list --direction=up --type tracks (reverse trackers). Every
# call is logged so the test can prove which store was asked, not just what came
# back.
set -u
printf '%s\n' "$*" >> "$FAKE_GC_LOG"
preface() { [ -n "${STUB_PREFACE:-}" ] && echo 'gc bd: answering from the rig "fake" store'; }
miss() { printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; echo "Issue $1 not found" >&2; exit 1; }
# Real `gc bd show` leaves out an edge whose far end lives in another store; a
# fixture writes such an edge with no status, so show drops every status-less
# edge. A fixture jq cannot parse — one carrying a raw C0 byte — streams through
# `cat`, not `"$(cat)"`: command substitution drops a raw NUL (bash: "ignored null
# byte in input"), and the NUL is exactly the byte real `gc bd show` can emit that
# the tool must survive. Brackets keep the array shape the tool discriminates on.
serve() {
  preface; printf '['
  local first=1 f out
  for f in "$@"; do
    [ "$first" = 1 ] || printf ','; first=0
    if out=$(jq -c '.dependencies = [(.dependencies // [])[] | select(.status != null)]' "$f" 2>/dev/null); then
      printf '%s' "$out"
    else
      cat "$f"
    fi
  done
  printf ']\n'; exit 0
}
# A list row renders every edge, another store's included, in the shape real
# `gc bd list` emits: {issue_id, depends_on_id, type}, no embedded status.
listrow() { jq -c '.id as $i | .dependencies = [(.dependencies // [])[] | {issue_id: $i, depends_on_id: .id, type: .dependency_type}]'; }
# The stores a query scans: the one --db pins, else every rig plus HQ. Files are
# read one at a time: real bd returns clean list/dep rows, and reading each alone
# means a contaminated show-only fixture (tk-nul, tk-ctrl) — never a child or
# tracker — is skipped by its own jq guard rather than aborting a whole-directory
# slurp. Command substitution drops the raw NUL on the way in.
stores() { if [ -n "$DB" ]; then printf '%s\n' "$DB"; else printf '%s\n' "$STUB_ROOT"/rigs/*/.beads "$STUB_ROOT"/hq/.beads; fi; }
case "${1:-} ${2:-}" in
  "rig list") preface; cat "$FAKE_RIGS"; exit 0 ;;
esac
[ "${1:-}" = bd ] || { echo "gc: unsupported ($*)" >&2; exit 1; }
shift
DB=""; SUB=""; SUB2=""; ID=""; IDS=(); LIST_IDS=""; GATES=""; PARENT=""; DIRECTION="down"; TYPE=""; STATUS=""; ALL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --db)          DB="$2"; shift 2 ;;
    --parent)      PARENT="$2"; shift 2 ;;
    --all)         ALL=1; shift ;;
    --id)          LIST_IDS="$2"; shift 2 ;;
    --include-gates) GATES=1; shift ;;
    --direction|--direction=*) case "$1" in *=*) DIRECTION="${1#*=}"; shift ;; *) DIRECTION="$2"; shift 2 ;; esac ;;
    -t|--type)     TYPE="$2"; shift 2 ;;
    -s|--status)   STATUS="$2"; shift 2 ;;
    --json|--brief-deps|--limit) [ "$1" = --limit ] && shift 2 || shift ;;
    show)          SUB=show; shift ;;
    list)          [ -z "$SUB" ] && SUB=list || SUB2=list; shift ;;
    dep)           SUB=dep; shift ;;
    -*)            shift ;;
    *)             if [ "$SUB" = show ]; then IDS+=("$1"); elif [ -z "$ID" ]; then ID="$1"; fi; shift ;;
  esac
done

if [ "$SUB" = show ]; then
  [ "${#IDS[@]}" -gt 0 ] || { echo "gc bd: no id" >&2; exit 1; }
  FOUND=()
  for id in "${IDS[@]}"; do
    hit=""
    for d in $(stores); do [ -f "$d/$id.json" ] && { hit="$d/$id.json"; break; }; done
    if [ -n "$hit" ]; then FOUND+=("$hit"); else echo "Issue $id not found" >&2; fi
  done
  [ "${#FOUND[@]}" -gt 0 ] || miss "${IDS[0]}"
  serve "${FOUND[@]}"
fi

if [ "$SUB" = list ] && [ -n "$LIST_IDS" ]; then
  # Rows by id, any status (the tool passes --all); like real bd, a missing id is
  # left out rather than reported, and a gate is hidden without --include-gates.
  IFS=, read -r -a WANT <<< "$LIST_IDS"
  preface; printf '['; first=1
  for id in "${WANT[@]}"; do
    hit=""
    for d in $(stores); do [ -f "$d/$id.json" ] && { hit="$d/$id.json"; break; }; done
    [ -n "$hit" ] || continue
    r=$(listrow < "$hit" 2>/dev/null) && [ -n "$r" ] || continue
    [ -n "$GATES" ] || ! printf '%s' "$r" | jq -e '.issue_type == "gate"' >/dev/null 2>&1 || continue
    [ "$first" = 1 ] || printf ','; first=0
    printf '%s' "$r"
  done
  printf ']\n'; exit 0
fi

if [ "$SUB" = list ] && [ -n "$PARENT" ]; then
  # Children of $PARENT, scoped as real bd scopes them: --all returns every
  # status, a store's own included; --status returns only the statuses it names;
  # with neither, bd's default returns every built-in status but closed and
  # pinned. So a caller that wants every child counted must pass --all.
  if [ -z "$ALL" ] && [ -z "$STATUS" ]; then STATUS="open,in_progress,blocked,deferred,hooked"; fi
  preface; printf '['; first=1
  for d in $(stores); do
    # One grep per store narrows the files to those naming the parent; jq decides.
    for f in $(grep -laF "\"$PARENT\"" "$d"/*.json 2>/dev/null); do
      row=$(cat "$f")
      printf '%s' "$row" | jq -e --arg p "$PARENT" '.parent == $p' >/dev/null 2>&1 || continue
      st=$(printf '%s' "$row" | jq -r '.status // ""')
      if [ -z "$ALL" ]; then case ",$STATUS," in *",$st,"*) ;; *) continue ;; esac; fi
      [ "$first" = 1 ] || printf ','; first=0
      printf '%s' "$row" | listrow
    done
  done
  printf ']\n'; exit 0
fi

if [ "$SUB" = dep ] && [ "$SUB2" = list ] && [ "$DIRECTION" = up ]; then
  # Reverse edges into $ID: beads whose dependencies name $ID, filtered by --type.
  preface; printf '['; first=1
  for d in $(stores); do
    # One grep per store narrows the files to those naming the id; jq decides.
    for f in $(grep -laF "\"$ID\"" "$d"/*.json 2>/dev/null); do
      row=$(cat "$f")
      printf '%s' "$row" | jq -e --arg s "$ID" --arg t "$TYPE" \
        'any(.dependencies[]?; .id == $s and ($t == "" or .dependency_type == $t))' >/dev/null 2>&1 || continue
      [ "$first" = 1 ] || printf ','; first=0
      printf '%s' "$row"
    done
  done
  printf ']\n'; exit 0
fi

echo "gc bd: unsupported ($SUB $SUB2)" >&2; exit 1
GC

cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The tool reaches every store through `gc bd`; a direct `bd` is the regression
# this stub exists to fail on. It records the call so one assertion reads the
# whole run.
printf '%s\n' "$*" >> "$FAKE_BD_LOG"
echo "stub bd: called directly instead of through gc bd" >&2
exit 127
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH"

run()  { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }
runj() { run "$@" --json; JQ=$(printf '%s' "$OUT" | jq -r "$JQF" 2>/dev/null); }
# Bounded variant for a call that could spin before a fix: a wedged SUT surfaces
# as timeout's rc 124 (a test failure) instead of hanging the whole suite.
runb() { OUT=$(timeout 10 "$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }

# --- A. Subject core --------------------------------------------------------
run tk-anchor
eq "$RC" 0 "a resolvable bead reports (rc)"
has "$OUT" "Title       rich anchor"             "  ... the subject's own title"
has "$OUT" "Status      open"                    "  ... status"
has "$OUT" "Type        task"                    "  ... type from issue_type"
has "$OUT" "Task kind   rework"                  "  ... task_kind"
has "$OUT" "Store       gc-toolkit"              "  ... store resolved from the id prefix"
has "$OUT" "Origin      operator"                "  ... gc.origin"
has "$OUT" "First react ruling → tk-frt"         "  ... first_reaction with its target"
has "$OUT" "[settled]"                           "  ... a settled takeaway is marked"
has "$(cat "$FAKE_GC_LOG")" "show tk-anchor --brief-deps" \
  "  ... via a --brief-deps read, so a hub bead's dependency bodies are never fetched"

JQF='.subject.title'                  runj tk-anchor; eq "$JQ" "rich anchor" "subject.title — section A returns the subject's own title"
JQF='.subject.status'                 runj tk-anchor; eq "$JQ" open        "subject.status"
JQF='.subject.priority'               runj tk-anchor; eq "$JQ" 1           "subject.priority (top-level)"
JQF='.subject.task_kind'              runj tk-anchor; eq "$JQ" rework      "subject.task_kind"
JQF='.subject.routed_to'              runj tk-anchor; eq "$JQ" ""          "subject.routed_to preserves the empty (cleared) route"
JQF='.subject.execution_routed_to'    runj tk-anchor; eq "$JQ" gc-toolkit/gc-toolkit.polecat "subject.execution_routed_to"
JQF='.subject.anchor.merge_result'    runj tk-anchor; eq "$JQ" pull_request "anchor.merge_result present when the bead carries one"
JQF='.subject.anchor.pr_number'       runj tk-anchor; eq "$JQ" 9           "anchor.pr_number"
JQF='.subject.anchor.branch'          runj tk-anchor; eq "$JQ" polecat/tk-anchor "anchor.branch"
JQF='.subject.anchor.merged_target'   runj tk-anchor; eq "$JQ" main        "anchor.merged_target"
JQF='.subject.first_reaction.reaction' runj tk-anchor; eq "$JQ" ruling     "first_reaction.reaction"
JQF='.subject.first_reaction.target'  runj tk-anchor; eq "$JQ" tk-frt      "first_reaction.target"
JQF='.subject.origin'                 runj tk-anchor; eq "$JQ" operator    "subject.origin"
JQF='.subject.takeaway_settled'       runj tk-anchor; eq "$JQ" 1           "subject.takeaway_settled returned as the field it is"
# A bead with no merge_result carries a null anchor, not a fabricated one.
JQF='.subject.anchor'                 runj tk-epic;   eq "$JQ" null        "anchor is null when the bead is not an anchor"

# --- D. Context edges -------------------------------------------------------
JQF='.edges.parent.id'                runj tk-anchor; eq "$JQ" tk-epic     "edges.parent resolved from .parent"
JQF='.edges.parent.title'             runj tk-anchor; eq "$JQ" "the parent epic" "  ... with the parent's title from the edge"
JQF='.edges.counts.parent'            runj tk-anchor; eq "$JQ" 1           "edges.counts.parent"
JQF='.edges.relates_to | length'      runj tk-anchor; eq "$JQ" 2           "both relates spellings — relates-to AND related — are the relates class"
JQF='[.edges.relates_to[].id]|sort|join(",")' runj tk-anchor; eq "$JQ" tk-rel,tk-rel2 "  ... and both are named"
JQF='.edges.tracked_by | length'      runj tk-anchor; eq "$JQ" 1           "tracked-by is read from the reverse tracks edge"
JQF='.edges.tracked_by[0].id'         runj tk-anchor; eq "$JQ" tk-visit    "  ... naming the tracking visit"
has "$(cat "$FAKE_GC_LOG")" "dep list tk-anchor --direction=up --type tracks" \
  "  ... via a reverse dep-list, since the subject carries no tracked-by edge itself"

# --- B. Frontier (opt-in) ---------------------------------------------------
# Default output carries no frontier; it is added only on --frontier.
JQF='has("frontier")'  runj tk-anchor;             eq "$JQ" false "frontier is absent by default (opt-in)"
JQF='.frontier.verdict' runj tk-anchor --frontier; eq "$JQ" ready "all blocks-blockers closed (one cross-store) reads ready"
JQF='.frontier.blockers.closed' runj tk-anchor --frontier; eq "$JQ" 2 "both closed blockers — same-store and cross-store — are counted"
JQF='.frontier.blockers.open'   runj tk-anchor --frontier; eq "$JQ" 0 "no open blocker"
JQF='.frontier.open | length'   runj tk-anchor --frontier; eq "$JQ" 0 "closed blockers are counted, never listed"
has "$(cat "$FAKE_GC_LOG")" "bd --db $R_OR/.beads list --id or-far" \
  "the cross-store blocker's status is read from the otherrig store it lives in"

JQF='.frontier.verdict'          runj tk-stuck --frontier; eq "$JQ" stuck "an open unrouted blocker is stuck, so the verdict is stuck"
JQF='.frontier.open[0].id'       runj tk-stuck --frontier; eq "$JQ" tk-op "  ... and the open blocker is named"
JQF='.frontier.open[0].advance'  runj tk-stuck --frontier; eq "$JQ" stuck "  ... advance=stuck"
JQF='.frontier.open[0].title'    runj tk-stuck --frontier; eq "$JQ" "open unrouted blocker" "  ... with its title"

JQF='.frontier.verdict'          runj tk-adv --frontier; eq "$JQ" advancing "an open pool-routed blocker is advancing"
JQF='.frontier.open[0].advance'  runj tk-adv --frontier; eq "$JQ" advancing "  ... advance=advancing"

JQF='.frontier.verdict'          runj tk-humangate --frontier; eq "$JQ" stuck "a blocker routed to the human gate is stuck, not advancing"
JQF='.frontier.open[0].advance'  runj tk-humangate --frontier; eq "$JQ" stuck "  ... advance=stuck for a human-routed blocker"

JQF='.frontier.open[0].advance'  runj tk-inreview --frontier; eq "$JQ" advancing "a review bead with a pour-cleared route is machine work, so advancing not stuck"
JQF='.frontier.verdict'          runj tk-inreview --frontier; eq "$JQ" advancing "  ... so a subject held only by a review in flight is advancing, not stuck"

JQF='.frontier.open[0].advance'  runj tk-failclosed --frontier; eq "$JQ" stuck "an unplaceable blocker is unknown, so stuck (fail closed)"
JQF='.frontier.blockers.open'    runj tk-failclosed --frontier; eq "$JQ" 1     "  ... counted as an open blocker"
JQF='.frontier.verdict'          runj tk-failclosed --frontier; eq "$JQ" stuck "  ... so the verdict fails closed"
JQF='.frontier.open[0].stuck_on | "\(.id) \(.why)"' runj tk-failclosed --frontier
eq "$JQ" "zz-ghost unknown" "  ... and names itself unknown"

# --- B2. The transitive walk --------------------------------------------------
# One run per subject; each assertion queries that run's output.
jr()  { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }
blkr() { jr "[.frontier.open[] | select(.id == \"$1\")][0] | \"\(.advance) \(.stuck_on.id // \"-\") \(.stuck_on.why // \"-\")\""; }
logcount() { grep -c -- "$1" "$FAKE_GC_LOG" | tr -d ' '; }

run tk-w-sub1 --frontier --json
eq "$(jr .frontier.verdict)" stuck "a routed blocker held by an orphan is stuck: the walk looks past one level"
eq "$(blkr tk-w-routed)" "stuck tk-w-orphan unrouted" "  ... and stuck_on names the orphan beneath it, unrouted"

run tk-w-sub2 --frontier --json
eq "$(jr .frontier.verdict)" advancing "an armed blocker whose own blocker moves is advancing"
eq "$(blkr tk-w-armed)" "advancing - -" "  ... it takes its blocker's verdict, and carries no stuck_on"

run tk-w-sub3 --frontier --json
eq "$(jr .frontier.verdict)" stuck "an armed blocker behind a human gate is stuck"
eq "$(blkr tk-w-armed2)" "stuck tk-w-gate human" "  ... naming the gate, so it reads apart from an orphan"

run tk-w-sub4 --frontier --json
eq "$(jr .frontier.verdict)" stuck "a cycle of routed beads never drains, so it is stuck"
eq "$(jr '.frontier.open[0].stuck_on.why')" cycle "  ... why=cycle"
case "$(jr '.frontier.open[0].stuck_on.id')" in
  tk-w-cyc-a|tk-w-cyc-b) ok "  ... naming a bead on the cycle" ;;
  *) bad "  ... naming a bead on the cycle (got '$(jr '.frontier.open[0].stuck_on.id')')" ;;
esac

: > "$FAKE_GC_LOG"
run tk-w-sub6 --frontier --json
eq "$(jr .frontier.blockers.open)" 1 "a subject's only blocker, in another store, is counted though its show row leaves the edge out"
eq "$(blkr or-w-mid)" "stuck tk-w-far unrouted" "a cross-store hop: the walk crosses into otherrig and back"
has "$(cat "$FAKE_GC_LOG")" "bd --db $R_OR/.beads list --id or-w-mid" "  ... reading the middle bead from the store it lives in"
has "$(cat "$FAKE_GC_LOG")" "bd --db $R_TK/.beads list --id tk-w-far" "  ... and the orphan beneath it from its own"

run tk-w-xs --frontier --json
eq "$(blkr tk-w-xmid)" "stuck or-w-leaf unrouted" "a walked bead's blocker in another store is read off its list row"

run tk-w-sub7 --frontier --json
eq "$(jr .frontier.verdict)" advancing "a routed chain three deep advances under the default budget"
run tk-w-sub7 --frontier --walk-budget 1 --json
eq "$(blkr tk-w-ch1)" "stuck tk-w-ch3 budget" "a walk out of budget reads stuck, naming the bead it could not read"
eq "$(jr .frontier.blockers.open)" 1 "  ... the subject's own blocker is read whatever the budget"

run tk-w-cl --frontier --walk-budget 2 --json
eq "$(jr .frontier.verdict)" advancing "the budget counts open beads met: a closed row beside the chain costs nothing"

run tk-w-wide --frontier --walk-budget 4 --json
eq "$(jr .frontier.verdict)" advancing "a level exactly as wide as the budget is read in full"
: > "$FAKE_GC_LOG"
run tk-w-wide --frontier --walk-budget 3 --json
eq "$(blkr tk-w-fan)" "stuck tk-w-f4 budget" "a level wider than the budget has left reads stuck, naming the blocker past the budget"
eq "$(logcount 'list --id tk-w-f1,tk-w-f2,tk-w-f3 ')" 1 "  ... the batch asks for only the three beads the budget covers"
eq "$(logcount 'list --id.*tk-w-f4')" 0 "  ... and the fourth is never read"
: > "$FAKE_GC_LOG"
run tk-w-refund --frontier --walk-budget 3 --json
eq "$(jr .frontier.verdict)" advancing "a closed row in a read the budget cut short hands its share of the budget back"
eq "$(logcount 'list --id tk-w-r3 ')" 1 "  ... so the leaf the cut read left out is read next"

run tk-w-six --frontier --json
eq "$(jr .frontier.verdict)" advancing "a routed chain six deep is read to its end"
run tk-w-seven --frontier --json
eq "$(blkr tk-w-v1)" "stuck tk-w-v7 budget" "  ... a seventh level is past the depth bound, so it reads stuck"

: > "$FAKE_GC_LOG"
run tk-w-sub8 --frontier --json
eq "$(jr .frontier.verdict)" advancing "a diamond of routed beads advances"
eq "$(logcount 'list --id.*tk-w-dshared')" 1 "  ... and the shared blocker is read once"
eq "$(logcount 'list --id tk-w-sub8,tk-w-d1,tk-w-d2 ')" 1 \
  "  ... the subject's blockers in one batched read of their store, the subject's own list row riding it"

: > "$FAKE_GC_LOG"
run tk-w-sub9 --frontier --json
eq "$(blkr tk-w-stopper)" "stuck tk-w-stopper unrouted" "a stuck blocker names itself"
eq "$(logcount 'list --id.*tk-w-hidden')" 0 "  ... and the walk never reads what a stuck bead waits on"

# Merge anchors: the recorded merge axis, not the route the merge cadence clears.
: > "$FAKE_GC_LOG"
run tk-w-anchors --frontier --json
eq "$(blkr tk-a-approval)" "stuck tk-a-approval approval" "a settled PR waiting on review is stuck on the operator's approval"
eq "$(blkr tk-a-progress)" "advancing - -" "a progressing anchor advances, a requested change being worked"
eq "$(blkr tk-a-preopen)" "advancing - -" "a settled anchor before its PR opens advances: the PR-open pass publishes it"
eq "$(blkr tk-a-approved)" "advancing - -" "a settled, approved PR advances to the merge pass"
eq "$(blkr tk-a-hold)" "stuck tk-a-hold merge-hold" "an operator merge hold is stuck"
eq "$(blkr tk-a-wedged)" "stuck tk-a-wedged wedged" "a wedged anchor is stuck"
eq "$(blkr tk-a-blocked)" "stuck tk-a-blocked merge-blocked" "an anchor its machine axis records blocked is stuck"
eq "$(blkr tk-a-stale)" "stuck tk-a-stale unread" "a posture read at another head than the axis is unread, so stuck"
eq "$(blkr tk-a-noaxis)" "stuck tk-a-noaxis unread" "an anchor with no recorded axis is unread, so stuck"
eq "$(blkr tk-a-heldstate)" "stuck tk-a-heldstate human" "an anchor parked in a human state is stuck on a person"
eq "$(logcount 'list --id')" 1 "  ... ten same-store blockers cost one read"

# A bead's own state, one rule per blocker.
run tk-w-kinds --frontier --json
eq "$(blkr tk-k-blocked)" "stuck tk-k-blocked held" "a routed bead whose status is blocked is held, not advancing"
eq "$(blkr tk-k-deferred)" "stuck tk-k-deferred held" "a deferred bead is held"
eq "$(blkr tk-k-validation)" "advancing - -" "a validation pass with a pour-cleared route is machine work"
eq "$(blkr tk-k-finding)" "advancing - -" "a must-fix finding is machine work the review cycle owns"
eq "$(blkr tk-k-needsyou)" "stuck tk-k-needsyou human" "a finding that needs the operator is stuck on a person"
eq "$(blkr tk-k-refinery)" "advancing - -" "an open bead assigned to the refinery is in its queue"
eq "$(blkr tk-k-capped)" "stuck tk-k-capped capped" "an armed dispatch at its sling-failure cap is stuck"
eq "$(blkr tk-k-hooked)" "advancing - -" "a hooked bead is held by an agent, so advancing"
eq "$(blkr tk-k-gate)" "stuck tk-k-gate human" "a gate bead, which a bare listing hides, is read and stuck on a person"

run tk-w-decides --frontier --json
eq "$(blkr tk-k-decision)" "stuck tk-k-decision human" "a decision is a person's to make"

run tk-w-sub3 --frontier
has "$OUT" "tk-w-armed2  tk-w-armed2 (open, stuck on tk-w-gate: human)" "the human block names the stuck leaf and why"
run tk-w-sub9 --frontier
has "$OUT" "(open, stuck: unrouted)" "  ... and a blocker that stops itself as just why"

# --- C. Horizon (opt-in) ----------------------------------------------------
JQF='has("horizon")'                 runj tk-epic;            eq "$JQ" false "horizon is absent by default (opt-in)"
JQF='.horizon.children.total'        runj tk-epic --horizon;  eq "$JQ" 10 "every direct child is counted, in any status"
JQF='.horizon.children.open'         runj tk-epic --horizon;  eq "$JQ" 9 "  ... nine are open"
JQF='.horizon.children.closed'       runj tk-epic --horizon;  eq "$JQ" 1 "  ... the done child is counted (the listing asks for every status)"
JQF='.horizon.children.advancing'    runj tk-epic --horizon;  eq "$JQ" 5 "  ... pool-routed, in-progress, hooked, a progressing anchor and a pour-cleared rework child advance"
JQF='.horizon.children.stuck'        runj tk-epic --horizon;  eq "$JQ" 4 "  ... the human-gated, armed-behind-the-gate, pinned and custom-status children are stuck"
JQF='.horizon.open | length'         runj tk-epic --horizon;  eq "$JQ" 9 "open children are listed; the done one is not"
JQF='[.horizon.open[].id] | index("tk-kid-done")' runj tk-epic --horizon; eq "$JQ" null "the done child is never in the open list"
JQF='[.horizon.open[]|select(.id=="tk-kid-pool")][0].advance' runj tk-epic --horizon; eq "$JQ" advancing "a pool-routed open child advances"
JQF='[.horizon.open[]|select(.id=="tk-kid-human")][0].advance' runj tk-epic --horizon; eq "$JQ" stuck "a human-gated open child is stuck"
: > "$FAKE_GC_LOG"; run tk-epic --horizon --json
kid() { jr "[.horizon.open[] | select(.id == \"$1\")][0] | \"\(.advance) \(.stuck_on.id // \"-\") \(.stuck_on.why // \"-\")\""; }
eq "$(kid tk-kid-human)" "stuck tk-kid-human human" "  ... and names itself as the gate"
eq "$(kid tk-kid-rework)" "advancing - -" "a pour-cleared rework child advances, with no stuck_on"
eq "$(kid tk-kid-armed)" "stuck tk-hg human" "an armed child takes its blocker's verdict: behind a human gate it is stuck, naming the gate"
eq "$(kid tk-kid-hooked)" "advancing - -" "a hooked child is listed and advances: an agent holds it"
eq "$(kid tk-kid-pinned)" "stuck tk-kid-pinned held" "a pinned child is listed and stuck on its hold, though it carries a route"
eq "$(kid tk-kid-custom)" "stuck tk-kid-custom held" "a child in a status its store adds is listed, and fails closed as held"
eq "$(jr '[.horizon.open[] | select(.id == "tk-kid-custom")][0].status')" in_review "  ... reporting the status as the store holds it"
eq "$(logcount 'list --id.*tk-hg')" 1 "  ... read through the listing's list-shaped edge"
eq "$(logcount 'list --id.*tk-kid-')" 0 "  ... while the children themselves cost no read: the listing carries their rows"
eq "$(jr '[.horizon.open[] | select(.advance == "advancing") | has("stuck_on")] | any')" false \
  "an advancing child carries no stuck_on key"

# --- one call is enough: the opening's subject slice, verdict and snapshot --
# The done-condition: with both dimensions opted in, ONE invocation yields the
# subject slice, the readiness verdict and the epic-health snapshot — no forced
# follow-up read by the caller.
JQF='[.subject.id, .frontier.verdict, (.horizon.children.total|tostring)] | join("|")' \
  runj tk-epic --frontier --horizon
eq "$JQ" "tk-epic|ready|10" "one call returns subject slice, readiness verdict and epic-health snapshot together"

# --- E. Store pinning, and the object-vs-array shape ------------------------
run tk-missing
eq "$RC" 4 "a not-found id (\`{\"error\":…}\` object) is reported, not parsed as a bead"
has "$ERR" "did not resolve to a bead" "  ... with a diagnostic"

run lx-city --db "$HQ/.beads"
eq "$RC" 0 "--db reaches the HQ store, which no --rig value names"
has "$OUT" "Store       loomington" "  ... and the rig is recovered from the db path"

JQF='.subject.status'  runj or-far --store rig:otherrig
eq "$JQ" closed "--store rig:<name> pins the read to that rig's store"

# --- the stdout notice line, and control bytes, do not break the read -------
STUB_PREFACE=1 run tk-anchor
eq "$RC" 0 "a leading \`gc bd:\` notice line does not break the read (rc)"
has "$OUT" "Status      open" "  ... and the bead still renders"
STUB_PREFACE=""

run tk-ctrl
eq "$RC" 0 "a raw C0 byte in notes is scrubbed before jq, not fatal"
has "$OUT" "Status      open" "  ... and the bead renders"
run tk-nul
eq "$RC" 0 "a raw NUL in notes does not switch the notice-strip to binary and drop the payload"
has "$OUT" "Status      open" "  ... and the bead still renders"

# --- usage ------------------------------------------------------------------
run;                       eq "$RC" 2 "no id is a usage error"
run tk-anchor extra-id;    eq "$RC" 2 "a second id is a usage error"
run tk-anchor --store nope;eq "$RC" 2 "a --store that is not rig:<name> is a usage error"
run --nope tk-anchor;      eq "$RC" 2 "an unknown flag is a usage error"
runb tk-anchor --store;    eq "$RC" 2 "a --store with no value is a usage error, not a hang"
has "$ERR" "needs a value" "  ... with a diagnostic"
runb tk-anchor --db;       eq "$RC" 2 "a --db with no value is a usage error, not a hang"
runb tk-anchor --walk-budget;   eq "$RC" 2 "a --walk-budget with no value is a usage error, not a hang"
run tk-anchor --walk-budget 0;  eq "$RC" 2 "a zero --walk-budget is a usage error"
run tk-anchor --walk-budget x;  eq "$RC" 2 "a non-numeric --walk-budget is a usage error"

# --- the raw-bd regression guard: no probe ever bypassed gc bd --------------
eq "$(wc -l < "$FAKE_BD_LOG" | tr -d ' ')" "0" \
  "no store was reached through a direct \`bd\` at any point in the run"

# --- the omit clause: no body of any bead is ever returned ------------------
run tk-anchor --frontier --horizon --json
eq "$(printf '%s' "$OUT" | jq -r '[paths|join(".")]|map(select(test("description|notes|comment";"i")))|length')" "0" \
  "no description, notes or comment field appears anywhere in the JSON"

echo
echo "bead-context: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
