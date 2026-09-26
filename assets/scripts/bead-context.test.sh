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
# the cross-store fold, the fail-closed unknown, the closed-scope of the child
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
# tk-failclosed: a blocks dep whose store no rig carries and which bd could not
# embed a status for — unknown must fail closed to stuck, never read as landed.
bead "$R_TK" tk-failclosed <<'J'
{"id":"tk-failclosed","title":"fail-closed","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"zz-ghost","dependency_type":"blocks","title":"unplaceable blocker"}]}
J

# tk-epic: the horizon fixture. Its direct children (found by the reverse
# parent-child listing, never its own edges) cover every advance state: an open
# pool-routed and an in-progress child advance; an open unrouted (tk-anchor) and
# an open human-gated child are stuck; one done child is counted, never listed.
# The epic's own blocks are none, so its frontier verdict is ready.
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
# Stream a bead through `cat`, not `"$(cat)"`: command substitution drops a raw
# NUL (bash: "ignored null byte in input"), and the NUL is exactly the C0 byte
# real `gc bd show` can emit that the tool must survive. Brackets keep the array
# shape the tool discriminates on.
serve() { preface; printf '['; cat "$1"; printf ']\n'; exit 0; }
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
DB=""; SUB=""; SUB2=""; ID=""; PARENT=""; DIRECTION="down"; TYPE=""; STATUS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --db)          DB="$2"; shift 2 ;;
    --parent)      PARENT="$2"; shift 2 ;;
    --direction|--direction=*) case "$1" in *=*) DIRECTION="${1#*=}"; shift ;; *) DIRECTION="$2"; shift 2 ;; esac ;;
    -t|--type)     TYPE="$2"; shift 2 ;;
    -s|--status)   STATUS="$2"; shift 2 ;;
    --json|--brief-deps|--limit) [ "$1" = --limit ] && shift 2 || shift ;;
    show)          SUB=show; ID="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
    list)          [ -z "$SUB" ] && SUB=list || SUB2=list; shift ;;
    dep)           SUB=dep; shift ;;
    -*)            shift ;;
    *)             [ -z "$ID" ] && [ "$SUB" != show ] && ID="$1"; shift ;;
  esac
done

if [ "$SUB" = show ]; then
  [ -n "$ID" ] || { echo "gc bd: no id" >&2; exit 1; }
  if [ -n "$DB" ]; then [ -f "$DB/$ID.json" ] && serve "$DB/$ID.json"; miss "$ID"; fi
  for d in $(stores); do [ -f "$d/$ID.json" ] && serve "$d/$ID.json"; done
  miss "$ID"
fi

if [ "$SUB" = list ] && [ -n "$PARENT" ]; then
  # Children of $PARENT, honoring --status. bd's default scope EXCLUDES closed,
  # so a caller that wants a done child in the count must ask for it: default
  # here to the non-closed set, and the tool must pass closed explicitly.
  [ -n "$STATUS" ] || STATUS="open,in_progress,blocked,deferred"
  preface; printf '['; first=1
  for d in $(stores); do
    for f in "$d"/*.json; do
      [ -f "$f" ] || continue
      row=$(cat "$f")
      printf '%s' "$row" | jq -e --arg p "$PARENT" '.parent == $p' >/dev/null 2>&1 || continue
      st=$(printf '%s' "$row" | jq -r '.status // ""')
      case ",$STATUS," in *",$st,"*) ;; *) continue ;; esac
      [ "$first" = 1 ] || printf ','; first=0
      printf '%s' "$row"
    done
  done
  printf ']\n'; exit 0
fi

if [ "$SUB" = dep ] && [ "$SUB2" = list ] && [ "$DIRECTION" = up ]; then
  # Reverse edges into $ID: beads whose dependencies name $ID, filtered by --type.
  preface; printf '['; first=1
  for d in $(stores); do
    for f in "$d"/*.json; do
      [ -f "$f" ] || continue
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
has "$(cat "$FAKE_GC_LOG")" "bd --db $R_OR/.beads show or-far" \
  "the cross-store blocker's status is read from the otherrig store it lives in"

JQF='.frontier.verdict'          runj tk-stuck --frontier; eq "$JQ" stuck "an open unrouted blocker is stuck, so the verdict is stuck"
JQF='.frontier.open[0].id'       runj tk-stuck --frontier; eq "$JQ" tk-op "  ... and the open blocker is named"
JQF='.frontier.open[0].advance'  runj tk-stuck --frontier; eq "$JQ" stuck "  ... advance=stuck"
JQF='.frontier.open[0].title'    runj tk-stuck --frontier; eq "$JQ" "open unrouted blocker" "  ... with its title"

JQF='.frontier.verdict'          runj tk-adv --frontier; eq "$JQ" advancing "an open pool-routed blocker is advancing"
JQF='.frontier.open[0].advance'  runj tk-adv --frontier; eq "$JQ" advancing "  ... advance=advancing"

JQF='.frontier.verdict'          runj tk-humangate --frontier; eq "$JQ" stuck "a blocker routed to the human gate is stuck, not advancing"
JQF='.frontier.open[0].advance'  runj tk-humangate --frontier; eq "$JQ" stuck "  ... advance=stuck for a human-routed blocker"

JQF='.frontier.open[0].advance'  runj tk-failclosed --frontier; eq "$JQ" stuck "an unplaceable blocker is unknown, so stuck (fail closed)"
JQF='.frontier.blockers.open'    runj tk-failclosed --frontier; eq "$JQ" 1     "  ... counted as an open blocker"
JQF='.frontier.verdict'          runj tk-failclosed --frontier; eq "$JQ" stuck "  ... so the verdict fails closed"

# --- C. Horizon (opt-in) ----------------------------------------------------
JQF='has("horizon")'                 runj tk-epic;            eq "$JQ" false "horizon is absent by default (opt-in)"
JQF='.horizon.children.total'        runj tk-epic --horizon;  eq "$JQ" 5 "every direct child is counted, closed included"
JQF='.horizon.children.open'         runj tk-epic --horizon;  eq "$JQ" 4 "  ... four are open"
JQF='.horizon.children.closed'       runj tk-epic --horizon;  eq "$JQ" 1 "  ... the done child is counted (the tool asked for closed explicitly)"
JQF='.horizon.children.advancing'    runj tk-epic --horizon;  eq "$JQ" 2 "  ... pool-routed and in-progress children advance"
JQF='.horizon.children.stuck'        runj tk-epic --horizon;  eq "$JQ" 2 "  ... unrouted and human-gated children are stuck"
JQF='.horizon.open | length'         runj tk-epic --horizon;  eq "$JQ" 4 "open children are listed; the done one is not"
JQF='[.horizon.open[].id] | index("tk-kid-done")' runj tk-epic --horizon; eq "$JQ" null "the done child is never in the open list"
JQF='[.horizon.open[]|select(.id=="tk-kid-pool")][0].advance' runj tk-epic --horizon; eq "$JQ" advancing "a pool-routed open child advances"
JQF='[.horizon.open[]|select(.id=="tk-kid-human")][0].advance' runj tk-epic --horizon; eq "$JQ" stuck "a human-gated open child is stuck"

# --- one call is enough: the opening's subject slice, verdict and snapshot --
# The done-condition: with both dimensions opted in, ONE invocation yields the
# subject slice, the readiness verdict and the epic-health snapshot — no forced
# follow-up read by the caller.
JQF='[.subject.id, .frontier.verdict, (.horizon.children.total|tostring)] | join("|")' \
  runj tk-epic --frontier --horizon
eq "$JQ" "tk-epic|ready|5" "one call returns subject slice, readiness verdict and epic-health snapshot together"

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
