#!/usr/bin/env bash
# Hermetic test for the gc-helm `park` verb (docs/steering.md).
#
# WHAT park DOES: it holds everything under a bead that has not started by
# giving the bead one `blocks` edge. The text form files a gate of its own,
# titled with the text and described by --body, and the edge lands on it;
# --waiting-on lands the edge on an existing bead and files no gate. The edge is
# read back off the bead before the verb reports success.
#
# THE CONTRACT this pins:
#   - the text form files a plain gate in the bead's own store: issue_type=gate,
#     the text as its title, --body as its description, and no await type, no
#     gc.demand_for and no other metadata. The bead's edge onto it reads back.
#   - --waiting-on gives the bead an edge onto the named bead and files no gate.
#   - a re-run of the text form files no second gate: a gate in the text form's
#     shape that the bead already waits on under the same title is the park. A
#     same-title gate of another kind (a demand gate, a gate with an await type,
#     a gate carrying metadata) is not, and the park files a gate of its own.
#   - refused with nothing written: text over the 140-character cap, both forms
#     at once, neither form, --body beside --waiting-on, a bead in flight
#     (branch, merge_result, rejection_reason, or a workflow past load-context),
#     a closed bead, and a demand gate, closed bead, another store's bead, the
#     bead itself or one of its own parts as the bead to wait on. The demand
#     gate's refusal names the text form.
#   - a workflow still at load-context is not in flight, so its bead parks.
#   - an edge that never reads back fails the verb (exit 4) with the repair; a
#     create whose answer is lost is recovered from the edge it was born with.
#   - the summary names what the park holds and what it leaves running.
#
# It runs the REAL gc-helm.sh via `sh` (as shipped) against a stateful stub
# `gc`: a JSON store that `bd show`, `bd list`, `bd create` and `bd dep add`
# read and write in the shapes bd prints, so each assertion reads the store
# the verb left behind. The test floor sits beneath the stub.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
FLOOR="$(cd "$HERE/../../tools/test-floor" 2>/dev/null && pwd)" || FLOOR=""
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-park-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"
if [ -z "$FLOOR" ] || [ ! -x "$FLOOR/gc" ]; then
  echo "gc-helm-park.test.sh: no test floor at tools/test-floor; not running" >&2
  exit 2
fi

mkdir -p "$TMP/bin" "$TMP/rig-tk/.beads" "$TMP/rig-sl/.beads"

# --- gc stub ------------------------------------------------------------------
# The store is a JSON array of rows {id, status, issue_type, title, description,
# metadata, deps:[{on, type}]}; a row's deps are the edges it carries, so a
# parent-child edge sits on the child and a blocks edge on the bead that waits.
# Every call's argv is logged to $STUB_CALLS.
#   rig list         two rigs: tk at $STUB_RIG_TK and sl at $STUB_RIG_SL, each
#                    with a .beads dir, so the verb pins every call with --db.
#   bd show <id>     `bd show --json`: an array of one row whose dependencies are
#                    the targets' rows {id, dependency_type, status, title,
#                    issue_type}, plus metadata and await_type where the target
#                    carries them, as bd prints them; an unknown id is bd's error
#                    object, exit 1.
#   bd list          `bd list --json`: the rows whose status --status names,
#                    gates only with --include-gates, each edge
#                    {issue_id, depends_on_id, type}. STUB_LIST_FAIL fails it.
#   bd create        `--type --title --description --deps blocks:<id> --json`:
#                    lands the row and, in the same write, <id>'s blocks edge
#                    onto it, then answers {"id": ...}. The id's prefix is the
#                    pinned store's (STUB_CREATE_PREFIX overrides it). An
#                    unknown --deps target is refused with nothing written.
#                    STUB_CREATE_FAIL refuses the create; STUB_CREATE_GARBAGE
#                    lands it and answers with what no JSON reader parses;
#                    STUB_EDGE_DROP lands the row without its edge.
#   bd dep add a b   gives a an edge of -t's type onto b, once. bd refuses a
#                    bead waiting on its own descendant, and so does this.
#                    STUB_DEP_DROP answers 0 and writes nothing.
# Any other call is refused with exit 2, so a write the verb must not make
# fails loudly.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -u
S="${STUB_STORE:?}"
printf '%s\n' "$*" >> "${STUB_CALLS:?}"
sub="${1:-}"; shift || true
case "$sub" in
  rig)
    jq -n --arg tk "$STUB_RIG_TK" --arg sl "$STUB_RIG_SL" \
      '{rigs:[{name:"gc-toolkit", path:$tk, prefix:"tk"}, {name:"signal-loom", path:$sl, prefix:"sl"}]}'
    exit 0 ;;
  bd) : ;;
  *) echo "gc stub: unsupported '$sub'" >&2; exit 2 ;;
esac
verb="${1:-}"; shift || true
db=""; rest=()
while [ $# -gt 0 ]; do
  case "$1" in
    --db) shift; db="${1:-}" ;;
    --db=*) db="${1#--db=}" ;;
    *) rest+=("$1") ;;
  esac
  shift || true
done
set -- ${rest[@]+"${rest[@]}"}
case "$verb" in
  show)
    id="${1:-}"
    out=$(jq -c --arg id "$id" '
      . as $all
      | [ .[] | select(.id == $id)
          | [ .deps[]? | . as $d | $all[] | select(.id == $d.on)
              | {id, dependency_type: $d.type, status, title, issue_type}
                + (if (.metadata // {}) == {} then {} else {metadata} end)
                + (if (.await_type // "") == "" then {} else {await_type} end) ] as $deps
          | {id, status, issue_type, title, description,
             metadata: (if (.metadata // {}) == {} then null else .metadata end),
             parent: ([ .deps[]? | select(.type == "parent-child") | .on ] | first // null),
             dependencies: (if ($deps | length) == 0 then null else $deps end)} ]' "$S")
    if [ "$out" = "[]" ]; then
      printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'
      exit 1
    fi
    printf '%s\n' "$out" ;;
  list)
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "gc: simulated list failure" >&2; exit 1; }
    st=""; gates=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) st="${1#--status=}" ;;
        --status) shift; st="${1:-}" ;;
        --include-gates) gates=1 ;;
      esac
      shift || true
    done
    jq -c --arg st "$st" --argjson g "$gates" '
      [ .[] | .status as $s
        | select($st == "" or ((($st | split(",")) | index($s)) != null))
        | select($g == 1 or .issue_type != "gate")
        | . as $r
        | {id, status, issue_type, title, metadata: (.metadata // {}),
           dependencies: [ .deps[]? | {issue_id: $r.id, depends_on_id: .on, type} ]} ]' "$S" ;;
  create)
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo "gc: simulated create refusal" >&2; exit 1; }
    title=""; desc=""; typ="task"; deps=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --title=*) title="${1#--title=}" ;;
        --title) shift; title="${1:-}" ;;
        --description=*) desc="${1#--description=}" ;;
        --description|-d) shift; desc="${1:-}" ;;
        --type=*) typ="${1#--type=}" ;;
        --type|-t) shift; typ="${1:-}" ;;
        --deps=*) deps="${1#--deps=}" ;;
        --deps) shift; deps="${1:-}" ;;
        --json) : ;;
        *) echo "gc stub: create: unexpected argument '$1'" >&2; exit 2 ;;
      esac
      shift || true
    done
    pfx="${STUB_CREATE_PREFIX:-}"
    if [ -z "$pfx" ]; then case "$db" in */rig-sl/*) pfx=sl ;; *) pfx=tk ;; esac; fi
    n=$(jq '[ .[] | select(.issue_type == "gate") ] | length' "$S")
    nid="$pfx-g$((n + 1))"
    target=""
    case "$deps" in
      "") : ;;
      blocks:*) target="${deps#blocks:}" ;;
      *) echo "gc stub: create: unsupported --deps '$deps'" >&2; exit 2 ;;
    esac
    if [ -n "$target" ] && ! jq -e --arg t "$target" 'any(.[]; .id == $t)' "$S" >/dev/null; then
      echo "Error: resolving --deps target \"$target\": no issue found" >&2
      exit 1
    fi
    jq -c --arg id "$nid" --arg t "$title" --arg d "$desc" --arg ty "$typ" --arg bt "$target" --arg drop "${STUB_EDGE_DROP:-}" '
      . + [{id: $id, status: "open", issue_type: $ty, title: $t, description: $d, metadata: {}, deps: []}]
      | if $bt != "" and $drop == "" then map(if .id == $bt then .deps += [{on: $id, type: "blocks"}] else . end) else . end' \
      "$S" > "$S.tmp" && mv "$S.tmp" "$S"
    if [ -n "${STUB_CREATE_GARBAGE:-}" ]; then echo "not-json"; else jq -cn --arg id "$nid" --arg t "$title" '{id: $id, title: $t}'; fi ;;
  dep)
    case "${1:-}" in
      add)
        a="${2:-}"; b="${3:-}"; ty="blocks"; shift 3 || true
        while [ $# -gt 0 ]; do
          case "$1" in -t|--type) shift; ty="${1:-}" ;; --type=*) ty="${1#--type=}" ;; esac
          shift || true
        done
        [ -n "${STUB_DEP_DROP:-}" ] && exit 0
        if jq -e --arg a "$a" --arg b "$b" '
             . as $all
             | def under($p): [ $all[] | select(any(.deps[]?; .type == "parent-child" and .on == $p)) | .id ] as $k
                              | $k + ([ $k[] | under(.) ] | add // []);
               (under($a) | index($b)) != null' "$S" >/dev/null; then
          echo "Error: $a cannot depend on its own descendant $b" >&2
          exit 1
        fi
        jq -c --arg a "$a" --arg b "$b" --arg ty "$ty" \
          'map(if .id == $a and (any(.deps[]?; .on == $b) | not) then .deps += [{on: $b, type: $ty}] else . end)' \
          "$S" > "$S.tmp" && mv "$S.tmp" "$S" ;;
      *) echo "gc stub: unsupported 'bd dep ${1:-}'" >&2; exit 2 ;;
    esac ;;
  *) echo "gc stub: unsupported 'bd $verb'" >&2; exit 2 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# Hermetic: the store's environment is the stub's, no inherited GC_*/BEADS_*
# steers the script, and the floor refuses any call no stub answers.
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
export PATH="$TMP/bin:$FLOOR:$PATH"
export TMPDIR="$TMP"
export STUB_STORE="$TMP/store.json" STUB_CALLS="$TMP/calls"
export STUB_RIG_TK="$TMP/rig-tk" STUB_RIG_SL="$TMP/rig-sl"

# The store every case starts from.
#   tk-epic          an epic; its members:
#     tk-epic.1      held
#     tk-epic.2      in flight: it carries a branch
#     tk-epic.3      armed
#     tk-done        closed, so not part of what the park holds
#     tk-feat        a feature, with members of its own:
#       tk-feat.1    held, two levels down
#       tk-feat.2    poured: its workflow tk-r1 waits at load-context
#       tk-feat.3    in flight: its workflow tk-r2 is past load-context
#   tk-solo          a loose task to park
#   tk-pr            in flight: merge_result=pull_request
#   tk-rej           in flight: a rejected handoff
#   tk-wf            in flight only through its workflow tk-r3, past load-context
#   tk-lc            not in flight: its workflow tk-r4 waits at load-context
#   tk-dg            a demand gate
#   tk-pg            another park's gate
#   tk-task          a task to wait on
#   tk-closed        a closed task
#   sl-x             a task in the signal-loom store
reset_store() {
  cat > "$STUB_STORE" <<'JSON'
[
 {"id":"tk-epic","status":"open","issue_type":"epic","title":"An epic","description":"","metadata":{},"deps":[]},
 {"id":"tk-epic.1","status":"open","issue_type":"task","title":"held member","description":"","metadata":{},"deps":[{"on":"tk-epic","type":"parent-child"}]},
 {"id":"tk-epic.2","status":"open","issue_type":"task","title":"member on a branch","description":"","metadata":{"branch":"polecat/tk-epic.2"},"deps":[{"on":"tk-epic","type":"parent-child"}]},
 {"id":"tk-epic.3","status":"open","issue_type":"task","title":"armed member","description":"","metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"},"deps":[{"on":"tk-epic","type":"parent-child"}]},
 {"id":"tk-done","status":"closed","issue_type":"task","title":"closed member","description":"","metadata":{},"deps":[{"on":"tk-epic","type":"parent-child"}]},
 {"id":"tk-feat","status":"open","issue_type":"feature","title":"a feature","description":"","metadata":{},"deps":[{"on":"tk-epic","type":"parent-child"}]},
 {"id":"tk-feat.1","status":"open","issue_type":"task","title":"held two down","description":"","metadata":{},"deps":[{"on":"tk-feat","type":"parent-child"}]},
 {"id":"tk-feat.2","status":"open","issue_type":"task","title":"poured, at load-context","description":"","metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"},"deps":[{"on":"tk-feat","type":"parent-child"}]},
 {"id":"tk-cv1","status":"open","issue_type":"convoy","title":"input convoy for tk-feat.2","description":"","metadata":{"gc.synthetic":"true"},"deps":[{"on":"tk-feat.2","type":"tracks"}]},
 {"id":"tk-r1","status":"open","issue_type":"task","title":"mol-polecat-work","description":"","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cv1"},"deps":[]},
 {"id":"tk-s1","status":"open","issue_type":"task","title":"Load context","description":"","metadata":{"gc.root_bead_id":"tk-r1","gc.step_ref":"mol-polecat-work.load-context"},"deps":[{"on":"tk-r1","type":"tracks"}]},
 {"id":"tk-feat.3","status":"open","issue_type":"task","title":"poured, past load-context","description":"","metadata":{},"deps":[{"on":"tk-feat","type":"parent-child"}]},
 {"id":"tk-cv2","status":"open","issue_type":"convoy","title":"input convoy for tk-feat.3","description":"","metadata":{"gc.synthetic":"true"},"deps":[{"on":"tk-feat.3","type":"tracks"}]},
 {"id":"tk-r2","status":"in_progress","issue_type":"task","title":"mol-polecat-work","description":"","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cv2"},"deps":[]},
 {"id":"tk-s2a","status":"closed","issue_type":"task","title":"Load context","description":"","metadata":{"gc.root_bead_id":"tk-r2","gc.step_ref":"mol-polecat-work.load-context"},"deps":[{"on":"tk-r2","type":"tracks"}]},
 {"id":"tk-s2b","status":"in_progress","issue_type":"task","title":"Implement","description":"","metadata":{"gc.root_bead_id":"tk-r2","gc.step_ref":"mol-polecat-work.implement"},"deps":[{"on":"tk-r2","type":"tracks"}]},
 {"id":"tk-solo","status":"open","issue_type":"task","title":"a loose task","description":"","metadata":{},"deps":[]},
 {"id":"tk-pr","status":"open","issue_type":"task","title":"an anchor with a PR","description":"","metadata":{"branch":"polecat/tk-pr","merge_result":"pull_request"},"deps":[]},
 {"id":"tk-rej","status":"open","issue_type":"task","title":"a rejected handoff","description":"","metadata":{"rejection_reason":"Conflicts with main"},"deps":[]},
 {"id":"tk-wf","status":"open","issue_type":"task","title":"poured, past load-context, no branch yet","description":"","metadata":{},"deps":[]},
 {"id":"tk-cv3","status":"open","issue_type":"convoy","title":"input convoy for tk-wf","description":"","metadata":{"gc.synthetic":"true"},"deps":[{"on":"tk-wf","type":"tracks"}]},
 {"id":"tk-r3","status":"in_progress","issue_type":"task","title":"mol-polecat-work","description":"","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cv3"},"deps":[]},
 {"id":"tk-s3","status":"open","issue_type":"task","title":"Set up worktree","description":"","metadata":{"gc.root_bead_id":"tk-r3","gc.step_ref":"mol-polecat-work.workspace-setup"},"deps":[{"on":"tk-r3","type":"tracks"}]},
 {"id":"tk-lc","status":"open","issue_type":"task","title":"poured, at load-context","description":"","metadata":{},"deps":[]},
 {"id":"tk-cv4","status":"open","issue_type":"convoy","title":"input convoy for tk-lc","description":"","metadata":{"gc.synthetic":"true"},"deps":[{"on":"tk-lc","type":"tracks"}]},
 {"id":"tk-r4","status":"open","issue_type":"task","title":"mol-polecat-work","description":"","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cv4"},"deps":[]},
 {"id":"tk-s4","status":"open","issue_type":"task","title":"Load context","description":"","metadata":{"gc.root_bead_id":"tk-r4","gc.step_ref":"mol-polecat-work.load-context"},"deps":[{"on":"tk-r4","type":"tracks"}]},
 {"id":"tk-dg","status":"open","issue_type":"gate","await_type":"human","title":"Rule on the loose task's scope","description":"","metadata":{"gc.demand_for":"tk-solo"},"deps":[]},
 {"id":"tk-pg","status":"open","issue_type":"gate","title":"Parked until the store answers in a second; close when it does","description":"","metadata":{},"deps":[]},
 {"id":"tk-task","status":"open","issue_type":"task","title":"Land the faster store","description":"","metadata":{},"deps":[]},
 {"id":"tk-closed","status":"closed","issue_type":"task","title":"already done","description":"","metadata":{},"deps":[]},
 {"id":"sl-x","status":"open","issue_type":"task","title":"a signal-loom task","description":"","metadata":{},"deps":[]}
]
JSON
}

# run_park <arg...> -> RC, OUT, ERR, CALLS; BEFORE/AFTER are the store's bytes.
run_park() {
  : > "$STUB_CALLS"
  BEFORE="$(cat "$STUB_STORE")"
  set +e
  OUT="$(sh "$SCRIPT" park "$@" 2>"$TMP/err")"; RC=$?
  set -e
  ERR="$(cat "$TMP/err")"
  CALLS="$(cat "$STUB_CALLS")"
  AFTER="$(cat "$STUB_STORE")"
}
# nothing_written <label>: no create or dep add was sent, and the store is as
# the case found it.
nothing_written() {
  if grep -qE '^bd (create|dep add|update|close)' <<< "$CALLS"; then
    bad "$1: a write was sent (calls: $CALLS)"
  else
    ok "$1: no write was sent"
  fi
  [ "$BEFORE" = "$AFTER" ] && ok "$1: the store is unchanged" || bad "$1: the store changed"
}
row() { jq -c --arg id "$1" '.[] | select(.id == $id)' "$STUB_STORE"; }
edges_of() { jq -r --arg id "$1" '.[] | select(.id == $id) | [ .deps[]? | select(.type == "blocks") | .on ] | join(" ")' "$STUB_STORE"; }
gate_count() { jq '[ .[] | select(.issue_type == "gate") ] | length' "$STUB_STORE"; }
# add_gate <id> <title> <await_type> <metadata-json>: an open gate in the store.
# add_edge <bead> <blocker>: <bead> waits on <blocker>.
add_gate() {
  jq -c --arg id "$1" --arg t "$2" --arg aw "$3" --argjson m "$4" \
    '. + [{id: $id, status: "open", issue_type: "gate", title: $t, description: "", metadata: $m, deps: []}
          + (if $aw == "" then {} else {await_type: $aw} end)]' \
    "$STUB_STORE" > "$STUB_STORE.tmp" && mv "$STUB_STORE.tmp" "$STUB_STORE"
}
add_edge() {
  jq -c --arg a "$1" --arg b "$2" 'map(if .id == $a then .deps += [{on: $b, type: "blocks"}] else . end)' \
    "$STUB_STORE" > "$STUB_STORE.tmp" && mv "$STUB_STORE.tmp" "$STUB_STORE"
}

TEXT="Parked while steer-by-epic lands; released when the operator unparks it at a priority"
BODY="The operator holds this epic so polecat capacity goes to steer-by-epic."

# --- (TEXT) the text form, as the positive control FIRST ----------------------
# A verb that refused everything would pass every refusal below while parking
# nothing, so prove the park lands before probing the refusals.
reset_store
run_park tk-epic "$TEXT" --body "$BODY"
eq "$RC" "0" "(TEXT) parking an epic with text and --body exits 0"
GATE="$(jq -r '[ .[] | select(.issue_type == "gate" and (.id | IN("tk-dg", "tk-pg") | not)) | .id ] | .[0] // ""' "$STUB_STORE")"
[ -n "$GATE" ] && ok "(TEXT) a gate was filed ($GATE)" || bad "(TEXT) no gate filed"
G="$(row "$GATE")"
eq "$(jq -r '.title' <<< "$G")" "$TEXT" "(TEXT) the gate is titled with the text"
eq "$(jq -r '.description' <<< "$G")" "$BODY" "(TEXT) the gate's description is --body"
eq "$(jq -r '.status' <<< "$G")" "open" "(TEXT) the gate is open"
eq "$(jq -c '.metadata' <<< "$G")" "{}" "(TEXT) the gate carries no metadata: no gc.demand_for, no takeaway or other [holds] marker"
eq "$(jq -r 'has("await_type")' <<< "$G")" "false" "(TEXT) the gate carries no await type"
eq "$(edges_of tk-epic)" "$GATE" "(TEXT) the epic's blocks edge lands on the gate"
grep -q "^bd create --type=gate --title=$TEXT --description=$BODY --deps blocks:tk-epic --db $STUB_RIG_TK/.beads --json" <<< "$CALLS" \
  && ok "(TEXT) the gate is born with its edge, in the bead's own store" || bad "(TEXT) create argv (calls: $CALLS)"
grep -q "^bd show tk-epic --db $STUB_RIG_TK/.beads --json" <<< "$(grep -A99 '^bd create' <<< "$CALLS")" \
  && ok "(TEXT) the edge is read back off the bead after the create" || bad "(TEXT) no read-back after the create (calls: $CALLS)"
has "$OUT" "park $GATE holds tk-epic: $TEXT" "(TEXT) prints park <gate> holds <bead>"
HELD="$(grep '^held, not started:' <<< "$OUT" || true)"
for b in tk-epic tk-epic.1 tk-feat tk-feat.1; do has "$HELD" " $b" "(TEXT) holds $b"; done
for b in tk-epic.2 tk-epic.3 tk-feat.2 tk-feat.3 tk-done; do hasnt "$HELD " " $b " "(TEXT) does not call $b held"; done
has "$OUT" "in flight, keeps running: " "(TEXT) names what stays in flight"
has "$OUT" "tk-epic.2 (branch polecat/tk-epic.2)" "(TEXT) a member on a branch stays in flight"
has "$OUT" "tk-feat.3 (workflow tk-r2 past load-context)" "(TEXT) a member whose workflow passed load-context stays in flight, two levels down"
has "$OUT" "armed, not held by this park: tk-epic.3" "(TEXT) an armed member is named as not held"
has "$OUT" "poured before the park, not held by it: tk-feat.2 (workflow tk-r1)" "(TEXT) a member poured and waiting at load-context is named as not held"
hasnt "$OUT" "tk-done" "(TEXT) a closed member is not part of the park"

# --- (AGAIN) re-running the same park files no second gate ---------------------
run_park tk-epic "$TEXT" --body "$BODY"
eq "$RC" "0" "(AGAIN) re-running the same park exits 0"
eq "$(gate_count)" "3" "(AGAIN) no second gate is filed"
has "$ERR" "already waits on the open gate $GATE" "(AGAIN) names the gate it already waits on"
grep -q '^bd create' <<< "$CALLS" && bad "(AGAIN) a create was sent (calls: $CALLS)" || ok "(AGAIN) no create was sent"

# --- (KIND) only a gate in the text form's shape is taken for the park ---------
# The bead already waits on a gate titled with the text. A plain gate, with no
# await type and no metadata, is the park. For each other kind the park files a
# gate of its own:
#   tk-dg   a demand gate: await_type=human and gc.demand_for
#   tk-hg   a human gate whose demand stamp has not landed: await_type=human
#   tk-mg   a gate another writer stamped: gc.blocker_key, no await type
KT="$(jq -r '.title' <<< "$(row tk-dg)")"
for k in tk-dg tk-hg tk-mg; do
  reset_store
  add_gate tk-hg "$KT" human '{}'
  add_gate tk-mg "$KT" "" '{"gc.blocker_key":"loose-task-scope"}'
  add_edge tk-solo "$k"
  run_park tk-solo "$KT"
  eq "$RC" "0" "(KIND) $k: parking under its title exits 0"
  hasnt "$ERR" "already waits on the open gate" "(KIND) $k: it is not taken for the park"
  G="$(jq -r '[ .[] | select(.issue_type == "gate" and (.id | IN("tk-dg", "tk-pg", "tk-hg", "tk-mg") | not)) | .id ] | .[0] // ""' "$STUB_STORE")"
  [ -n "$G" ] && ok "(KIND) $k: a gate of its own is filed ($G)" || bad "(KIND) $k: no gate of its own filed"
  eq "$(edges_of tk-solo)" "$k $G" "(KIND) $k: the bead waits on $k and on the park's own gate"
  has "$OUT" "park $G holds tk-solo: $KT" "(KIND) $k: the success line names the park's own gate"
done
reset_store
add_edge tk-solo tk-pg
PT="$(jq -r '.title' <<< "$(row tk-pg)")"
run_park tk-solo "$PT"
eq "$RC" "0" "(KIND) plain: parking under its title exits 0"
has "$ERR" "already waits on the open gate tk-pg" "(KIND) plain: a plain gate under the same title is the park"
grep -q '^bd create' <<< "$CALLS" && bad "(KIND) plain: a create was sent (calls: $CALLS)" || ok "(KIND) plain: no create was sent"
has "$OUT" "park tk-pg holds tk-solo: $PT" "(KIND) plain: the success line names the gate it waits on"

# --- (NOBODY) without --body the gate still says how to release it -------------
reset_store
run_park tk-solo "Parked until the faster store lands"
eq "$RC" "0" "(NOBODY) parking without --body exits 0"
G="$(jq -c '[ .[] | select(.issue_type == "gate" and (.id | IN("tk-dg", "tk-pg") | not)) ] | .[0]' "$STUB_STORE")"
has "$(jq -r '.description' <<< "$G")" "Closing this gate releases it" "(NOBODY) the default description says what releases the park"
eq "$(edges_of tk-solo)" "$(jq -r '.id' <<< "$G")" "(NOBODY) the bead's edge lands on its gate"
eq "$(grep -c '^held, not started: tk-solo$' <<< "$OUT")" "1" "(NOBODY) a bead with nothing under it holds itself"

# --- (WAIT) --waiting-on: an edge onto an existing bead, and no gate ----------
reset_store
run_park tk-solo --waiting-on tk-task
eq "$RC" "0" "(WAIT) parking behind an existing bead exits 0"
eq "$(edges_of tk-solo)" "tk-task" "(WAIT) the bead's blocks edge lands on the named bead"
eq "$(gate_count)" "2" "(WAIT) no gate is filed"
grep -q '^bd create' <<< "$CALLS" && bad "(WAIT) a create was sent (calls: $CALLS)" || ok "(WAIT) no create was sent"
grep -q "^bd dep add tk-solo tk-task -t blocks --db $STUB_RIG_TK/.beads" <<< "$CALLS" \
  && ok "(WAIT) the edge is written in the bead's own store" || bad "(WAIT) dep add argv (calls: $CALLS)"
has "$OUT" "park tk-task holds tk-solo: Land the faster store" "(WAIT) prints park <wait> holds <bead> with the wait's title"

reset_store
run_park tk-epic --waiting-on tk-pg
eq "$RC" "0" "(WAIT) naming another park's gate parks one more bead for the same reason"
eq "$(edges_of tk-epic)" "tk-pg" "(WAIT) the epic waits on the other park's gate"

# --- (CAP) the text is one line of at most 140 characters ---------------------
reset_store
T140="$(printf 'x%.0s' $(seq 1 140))"
run_park tk-solo "$T140"
eq "$RC" "0" "(CAP) text of exactly 140 characters is taken"
reset_store
run_park tk-solo "${T140}y"
eq "$RC" "2" "(CAP) text over 140 characters is refused (exit 2)"
has "$ERR" "the cap is 140" "(CAP) the refusal names the cap"
has "$ERR" "put the rest in --body" "(CAP) the refusal says where the rest goes"
nothing_written "(CAP)"
reset_store
run_park tk-solo "$(printf 'é%.0s' $(seq 1 140))"
eq "$RC" "0" "(CAP) the cap counts characters, not bytes"

# --- (FORMS) a park takes one form or the other -------------------------------
reset_store
run_park tk-solo "Parked for a reason" --waiting-on tk-task
eq "$RC" "2" "(FORMS) both forms at once are refused (exit 2)"
has "$ERR" "a park takes one" "(FORMS) the refusal says a park takes one form"
nothing_written "(FORMS) both"
run_park tk-solo
eq "$RC" "2" "(FORMS) neither form is refused (exit 2)"
has "$ERR" "--waiting-on <bead-id>" "(FORMS) the refusal names both forms"
nothing_written "(FORMS) neither"
run_park tk-solo --waiting-on tk-task --body "detail"
eq "$RC" "2" "(FORMS) --body beside --waiting-on is refused (exit 2)"
nothing_written "(FORMS) body with wait"
run_park tk-solo --waiting-on tk-task --waiting-on tk-pg
eq "$RC" "2" "(FORMS) a second --waiting-on is refused (exit 2)"
nothing_written "(FORMS) two waits"
run_park
eq "$RC" "2" "(FORMS) no bead is a usage error (exit 2)"

# --- (FLIGHT) a bead in flight is refused -------------------------------------
reset_store
run_park tk-pr "Parked for a reason"
eq "$RC" "2" "(FLIGHT) a bead carrying merge_result is refused (exit 2)"
has "$ERR" "in flight (merge_result=pull_request)" "(FLIGHT) the refusal names merge_result"
has "$ERR" "merge.sh holds an anchor's merge" "(FLIGHT) the refusal says why"
nothing_written "(FLIGHT) merge_result"
run_park tk-epic.2 "Parked for a reason"
eq "$RC" "2" "(FLIGHT) a bead carrying a branch is refused (exit 2)"
has "$ERR" "in flight (branch polecat/tk-epic.2)" "(FLIGHT) the refusal names the branch"
has "$ERR" "Park tk-epic instead" "(FLIGHT) the refusal names the parent to park instead"
nothing_written "(FLIGHT) branch"
run_park tk-rej --waiting-on tk-task
eq "$RC" "2" "(FLIGHT) a bead carrying rejection_reason is refused, in the --waiting-on form too"
has "$ERR" "rejection_reason set" "(FLIGHT) the refusal names the rejection"
nothing_written "(FLIGHT) rejection_reason"
run_park tk-wf "Parked for a reason"
eq "$RC" "2" "(FLIGHT) a bead whose workflow passed load-context is refused (exit 2)"
has "$ERR" "workflow tk-r3 past load-context" "(FLIGHT) the refusal names the workflow"
nothing_written "(FLIGHT) workflow"
run_park tk-lc "Parked for a reason"
eq "$RC" "0" "(FLIGHT) a bead whose workflow waits at load-context is not in flight, and parks"
[ -n "$(edges_of tk-lc)" ] && ok "(FLIGHT) its edge landed" || bad "(FLIGHT) no edge on tk-lc"

# --- (DEMAND) a demand gate is refused as the bead to wait on ------------------
reset_store
run_park tk-solo --waiting-on tk-dg
eq "$RC" "2" "(DEMAND) a demand gate named by --waiting-on is refused (exit 2)"
has "$ERR" "is a demand gate (gc.demand_for=tk-solo)" "(DEMAND) the refusal names the demand gate"
has "$ERR" "park tk-solo \"<why it is parked and what releases it>\"" "(DEMAND) the refusal names the text form"
nothing_written "(DEMAND)"

# --- (WAITS) a bead to wait on that would hold nothing ------------------------
reset_store
run_park tk-solo --waiting-on tk-solo
eq "$RC" "2" "(WAITS) waiting on itself is refused (exit 2)"
nothing_written "(WAITS) itself"
run_park tk-solo --waiting-on tk-closed
eq "$RC" "2" "(WAITS) waiting on a closed bead is refused (exit 2)"
has "$ERR" "holds nothing" "(WAITS) the refusal says the edge would hold nothing"
nothing_written "(WAITS) closed"
run_park tk-solo --waiting-on sl-x
eq "$RC" "2" "(WAITS) waiting on another store's bead is refused (exit 2)"
has "$ERR" "another store" "(WAITS) the refusal names the store"
nothing_written "(WAITS) another store"
run_park tk-epic --waiting-on tk-feat.1
eq "$RC" "2" "(WAITS) waiting on one of its own parts is refused (exit 2)"
has "$ERR" "is under tk-epic" "(WAITS) the refusal says the wait is under the bead"
nothing_written "(WAITS) own part"
run_park tk-solo --waiting-on tk-nope
eq "$RC" "4" "(WAITS) a wait that does not resolve fails (exit 4)"
nothing_written "(WAITS) unresolved"

# --- (BEAD) the bead to park ---------------------------------------------------
reset_store
run_park tk-closed "Parked for a reason"
eq "$RC" "2" "(BEAD) a closed bead is refused (exit 2)"
nothing_written "(BEAD) closed"
run_park tk-nope "Parked for a reason"
eq "$RC" "4" "(BEAD) a bead that does not resolve fails (exit 4)"
nothing_written "(BEAD) unresolved"

# --- (LIST) a store that does not list cannot prove the bead is not in flight --
reset_store
STUB_LIST_FAIL=1 run_park tk-solo "Parked for a reason"
eq "$RC" "4" "(LIST) an unreadable listing fails closed (exit 4)"
has "$ERR" "could not list" "(LIST) the refusal names the listing"
nothing_written "(LIST)"

# --- (READBACK) an edge that does not land is a failure ------------------------
reset_store
STUB_EDGE_DROP=1 run_park tk-solo "Parked for a reason"
eq "$RC" "0" "(READBACK) a gate born without its edge is repaired by one dep add"
G="$(jq -r '[ .[] | select(.issue_type == "gate" and (.id | IN("tk-dg", "tk-pg") | not)) | .id ] | .[0]' "$STUB_STORE")"
eq "$(edges_of tk-solo)" "$G" "(READBACK) the repaired edge reads back"
reset_store
STUB_EDGE_DROP=1 STUB_DEP_DROP=1 run_park tk-solo "Parked for a reason"
eq "$RC" "4" "(READBACK) an edge that never reads back fails (exit 4)"
has "$ERR" "is NOT blocked by" "(READBACK) the failure says the bead is not held"
has "$ERR" "gc bd dep add tk-solo" "(READBACK) the failure names the repair"
has "$ERR" "gc bd close" "(READBACK) the failure names the close of a gate that holds nothing"
hasnt "$OUT" "park " "(READBACK) no success line is printed"
reset_store
STUB_DEP_DROP=1 run_park tk-solo --waiting-on tk-task
eq "$RC" "4" "(READBACK) a --waiting-on edge that never reads back fails (exit 4)"
hasnt "$ERR" "gc bd close" "(READBACK) --waiting-on names no gate to close"

# --- (RECOVER) a create whose answer is lost is recovered from its edge --------
reset_store
STUB_CREATE_GARBAGE=1 run_park tk-solo "Parked for a reason"
eq "$RC" "0" "(RECOVER) a create that landed with an unreadable answer exits 0"
G="$(edges_of tk-solo)"
has "$OUT" "park $G holds tk-solo" "(RECOVER) the gate is found by the edge it was born with"
eq "$(gate_count)" "3" "(RECOVER) exactly one gate was filed"
reset_store
STUB_CREATE_FAIL=1 run_park tk-solo "Parked for a reason"
eq "$RC" "4" "(RECOVER) a refused create fails (exit 4)"
has "$ERR" "nothing holds tk-solo" "(RECOVER) the failure says nothing holds the bead"

# --- (LEDGER) a gate that lands in another store is reported -------------------
reset_store
STUB_CREATE_PREFIX=lx run_park tk-solo "Parked for a reason"
eq "$RC" "4" "(LEDGER) a gate filed under another store's prefix fails (exit 4)"
has "$ERR" "landed in another rig's store" "(LEDGER) the failure names the stray gate"

# --- (STORE) the gate goes to the bead's own store ------------------------------
reset_store
run_park sl-x "Parked until the signal-loom pack update lands"
eq "$RC" "0" "(STORE) parking a bead in another rig exits 0"
grep -q "^bd create .* --db $STUB_RIG_SL/.beads --json" <<< "$CALLS" \
  && ok "(STORE) the gate is filed in that rig's store" || bad "(STORE) create pinned to the bead's store (calls: $CALLS)"
case "$(edges_of sl-x)" in sl-*) ok "(STORE) the gate carries that store's prefix" ;; *) bad "(STORE) gate prefix (edges: $(edges_of sl-x))" ;; esac

# --- (WIRING) the verb is reachable and documented ----------------------------
grep -qE '^[[:space:]]*park\)[[:space:]]*shift; cmd_park' "$SCRIPT" \
  && ok "(WIRING) park is in the dispatch case" || bad "(WIRING) park dispatch case missing"
grep -q 'gc-helm park <bead-id> "<text>"' "$SCRIPT" \
  && ok "(WIRING) the text form is in the usage block" || bad "(WIRING) text form usage line missing"
grep -q 'gc-helm park <bead-id> --waiting-on <bead-id>' "$SCRIPT" \
  && ok "(WIRING) the --waiting-on form is in the usage block" || bad "(WIRING) --waiting-on usage line missing"
grep -qE 'try:.*park.*help' "$SCRIPT" \
  && ok "(WIRING) park is in the unknown-verb hint" || bad "(WIRING) park hint missing"

echo
echo "gc-helm-park.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
