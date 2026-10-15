#!/usr/bin/env bash
# Hermetic test for queue-priority.sh and the gc-helm `priority` verb that runs
# its move (docs/steering.md, "Priority").
#
# THE CONTRACT this pins:
#   (SETTLE)    settle writes a bead's computed priority to the bead and to every
#               live workflow poured for it (input convoy, root, open steps) and
#               reads it back; a claimed bead or step is left as it is, and so is
#               a closed one; a bead that follows nothing keeps its own priority
#               and its workflows take it; --print computes and writes nothing; a
#               write that does not read back, an unreadable bead and a lock
#               held past the wait each exit 1.
#   (MOVE)      gc-helm.sh priority <bead> <P> sets a bead that follows nothing,
#               and --shift sets a bead that follows a parent or an anchor; the
#               move then writes every bead that follows it, held ones included,
#               their live workflows and their anchors' PR-finishing work, and
#               reads them back. A P-value on a member is refused naming the
#               shift that lands it there; a shift on a bead that follows
#               nothing, either form on a workflow's convoy, root or step, a
#               closed bead and malformed input are refused with nothing
#               written.
#   (RULES)     the done-when cases of the priority flow: shift -1 under a P1
#               epic queues at P0, then P1 once the epic moves to P2; under a P0
#               epic a feature at -1 stays P0 and a task under it at +1 is P1; two
#               parents follow the more urgent; a parked epic's members move too.
#   (FIXTURE)   settle on every bead and the move on every bead that follows
#               nothing leave priority-lib.fixture.json's store at the same
#               priorities, the ones its cases name.
#   (PASS)      reconcile reads the polecat queue and what each queued bead
#               follows, never the whole store, and settles a queued bead's
#               whole workflow in one pass after a raw edit on its epic; it skips
#               a tick while the lock is held, fails on a wedged lock or an
#               unreadable queue, writes nothing on --dry-run, and leaves what
#               its budget cannot cover for the next pass.
#   (CROSSING)  a pass that read the old priority before a move cannot write it
#               back after the move: the move waits for the pass's lock.
#   (ORDER)     orders/queue-priority.toml runs reconcile per rig every fifteen
#               minutes, its timeout above the pass budget and below the stall
#               bound.
#   (REGISTRY)  every metadata key the script writes is registered in
#               lifecycle/lifecycle.toml.
#
# It runs the REAL queue-priority.sh and gc-helm.sh against a stateful stub
# `gc`: a JSON store that `bd list`, `bd ready`, `bd dep list` and `bd update`
# read and write in the shapes bd prints, so each assertion reads the store the
# writers left behind. The test floor sits beneath the stub.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
QP="$HERE/queue-priority.sh"
HELM="$HERE/gc-helm.sh"
FX="$HERE/priority-lib.fixture.json"
FLOOR="$(cd "$HERE/../../tools/test-floor" 2>/dev/null && pwd)" || FLOOR=""
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-queue-priority-test.XXXXXX")"
HOLDERS=()
cleanup() { local p; for p in ${HOLDERS[@]+"${HOLDERS[@]}"}; do kill "$p" 2>/dev/null || true; done; rm -rf "$TMP"; }
trap cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$QP" ] && ok "queue-priority.sh present" || bad "queue-priority.sh missing at $QP"
if [ -z "$FLOOR" ] || [ ! -x "$FLOOR/gc" ]; then
  echo "queue-priority.test.sh: no test floor at tools/test-floor; not running" >&2
  exit 2
fi

mkdir -p "$TMP/bin" "$TMP/rig-tk/.beads"

# --- gc stub ------------------------------------------------------------------
# The store is a JSON array of rows in the shape `bd list --json` prints: {id,
# status, issue_type, priority, assignee, metadata, dependencies: [{issue_id,
# depends_on_id, type}]}. Every call's argv, less its --db pin, is logged to
# $STUB_CALLS.
#   rig list           one rig, tk, at $STUB_RIG_TK, with a .beads store.
#   bd list            --id (comma list), --all, --status, --metadata-field
#                      (repeatable, ANDed) and --has-metadata-key filter the
#                      store; with neither --all nor --status it leaves out
#                      closed and pinned beads, and without --include-gates
#                      every gate, as bd does. STUB_LIST_FAIL fails it.
#   bd ready           the open beads that no open blocker holds, on themselves
#                      or on a parent-child ancestor, filtered by
#                      --metadata-field and --unassigned, most urgent first.
#                      STUB_READY_FAIL fails it.
#   bd dep list <id> --direction up -t tracks
#                      the beads carrying a tracks edge onto <id>, at every
#                      status, in the row shape `dep list` prints.
#   bd update <id>...  --priority and --set-metadata on every id named, in one
#                      write; an unknown id refuses the whole call. bd types a
#                      --set-metadata value that reads as a JSON number, true or
#                      false, and so does this. STUB_UPDATE_FAIL refuses every
#                      update; STUB_DROP_PRIORITY answers 0 and writes no
#                      priority. STUB_GATE, in the environment of one caller,
#                      holds that caller's first priority write until the gate
#                      file is removed, touching <gate>.reached when it arrives.
# Any other call is refused with exit 2, so a call the scripts must not make
# fails loudly.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -u
S="${STUB_STORE:?}"
sub="${1:-}"; shift || true
case "$sub" in
  rig)
    printf 'rig %s\n' "$*" >> "${STUB_CALLS:?}"
    jq -n --arg tk "$STUB_RIG_TK" '{rigs:[{name:"gc-toolkit", path:$tk, prefix:"tk"}]}'
    exit 0 ;;
  bd) : ;;
  *) echo "gc stub: unsupported '$sub'" >&2; exit 2 ;;
esac
rest=()
while [ $# -gt 0 ]; do
  case "$1" in
    --db) shift ;;
    --db=*) : ;;
    *) rest+=("$1") ;;
  esac
  shift || true
done
set -- ${rest[@]+"${rest[@]}"}
printf 'bd %s\n' "$*" >> "${STUB_CALLS:?}"
verb="${1:-}"; shift || true
LIVE='def live: ((.status // "") != "closed" and (.status // "") != "pinned");'
mf_json() { printf '%s\n' "$@" | jq -Rsc 'split("\n") | map(select(length > 0) | capture("^(?<k>[^=]+)=(?<v>.*)$"))'; }
case "$verb" in
  list)
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "gc: simulated list failure" >&2; exit 1; }
    ids=""; all=0; st=""; hk=""; gates=0; mf=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --id) shift; ids="${1:-}" ;;
        --id=*) ids="${1#--id=}" ;;
        --all) all=1 ;;
        --status) shift; st="${1:-}" ;;
        --status=*) st="${1#--status=}" ;;
        --metadata-field) shift; mf+=("${1:-}") ;;
        --metadata-field=*) mf+=("${1#--metadata-field=}") ;;
        --has-metadata-key) shift; hk="${1:-}" ;;
        --include-gates) gates=1 ;;
        --brief|--json|--include-infra|--include-templates) : ;;
        --limit) shift ;;
        --limit=*) : ;;
        *) echo "gc stub: list: unexpected argument '$1'" >&2; exit 2 ;;
      esac
      shift || true
    done
    jq -c --arg ids "$ids" --argjson all "$all" --arg st "$st" --arg hk "$hk" --argjson gates "$gates" \
      --argjson mf "$(mf_json ${mf[@]+"${mf[@]}"})" "$LIVE"'
      [ .[]
        | select($ids == "" or (.id as $i | ($ids | split(",")) | index($i)))
        | select(if $st != "" then (.status as $s | ($st | split(",")) | index($s))
                 elif $all == 1 then true else live end)
        | select(. as $r | all($mf[]; (($r.metadata // {})[.k] // "" | tostring) == .v))
        | select($hk == "" or ((.metadata // {}) | has($hk)))
        | select($gates == 1 or .issue_type != "gate") ]' "$S" ;;
  ready)
    [ -n "${STUB_READY_FAIL:-}" ] && { echo "gc: simulated ready failure" >&2; exit 1; }
    un=0; mf=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --metadata-field) shift; mf+=("${1:-}") ;;
        --metadata-field=*) mf+=("${1#--metadata-field=}") ;;
        --unassigned) un=1 ;;
        --json) : ;;
        --limit) shift ;;
        --limit=*) : ;;
        *) echo "gc stub: ready: unexpected argument '$1'" >&2; exit 2 ;;
      esac
      shift || true
    done
    jq -c --argjson un "$un" --argjson mf "$(mf_json ${mf[@]+"${mf[@]}"})" "$LIVE"'
      . as $all | (map({key: .id, value: .}) | from_entries) as $by
      | def blocked($id; $seen):
          ($by[$id] // null) as $r
          | if $r == null or ($r | live | not) then false
            else (any(($r.dependencies // [])[]; .type == "blocks" and (($by[.depends_on_id] // null) | . != null and live)))
                 or any(($r.dependencies // [])[] | select(.type == "parent-child") | .depends_on_id
                        | select(. as $p | $seen | index($p) | not); blocked(.; $seen + [.])) end;
        [ $all[] | select(.status == "open")
          | select(blocked(.id; [.id]) | not)
          | select($un == 0 or ((.assignee // "") == ""))
          | select(. as $r | all($mf[]; (($r.metadata // {})[.k] // "" | tostring) == .v)) ]
        | sort_by(.priority, .id)' "$S" ;;
  dep)
    [ "${1:-}" = list ] || { echo "gc stub: unsupported 'bd dep ${1:-}'" >&2; exit 2; }
    id="${2:-}"; shift 2 || true
    while [ $# -gt 0 ]; do
      case "$1" in
        --direction) shift; [ "${1:-}" = up ] || { echo "gc stub: dep list: only --direction up" >&2; exit 2; } ;;
        -t|--type) shift; [ "${1:-}" = tracks ] || { echo "gc stub: dep list: only -t tracks" >&2; exit 2; } ;;
        --json) : ;;
        *) echo "gc stub: dep list: unexpected argument '$1'" >&2; exit 2 ;;
      esac
      shift || true
    done
    jq -e --arg id "$id" 'any(.[]; .id == $id)' "$S" >/dev/null || { echo "Error: no issue found matching \"$id\"" >&2; exit 1; }
    jq -c --arg id "$id" '[ .[] | select(any((.dependencies // [])[]; .type == "tracks" and .depends_on_id == $id))
      | {id, issue_type, status, priority, metadata: (.metadata // {}), dependency_type: "tracks"} ]' "$S" ;;
  update)
    ids=(); pr=""; sets=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --priority) shift; pr="${1:-}" ;;
        --priority=*) pr="${1#--priority=}" ;;
        --set-metadata) shift; sets+=("${1:-}") ;;
        --set-metadata=*) sets+=("${1#--set-metadata=}") ;;
        -*) echo "gc stub: update: unexpected argument '$1'" >&2; exit 2 ;;
        *) ids+=("$1") ;;
      esac
      shift || true
    done
    [ -n "${STUB_UPDATE_FAIL:-}" ] && { echo "gc: simulated update refusal" >&2; exit 1; }
    idj="$(printf '%s\n' "${ids[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
    jq -e --argjson ids "$idj" '. as $s | all($ids[]; . as $i | any($s[]; .id == $i))' "$S" >/dev/null \
      || { echo "Error: no issue found matching one of ${ids[*]}" >&2; exit 1; }
    if [ -n "$pr" ] && [ -n "${STUB_GATE:-}" ] && [ -f "$STUB_GATE" ]; then
      : > "$STUB_GATE.reached"
      n=0; while [ -f "$STUB_GATE" ] && [ "$n" -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
    fi
    [ -n "${STUB_DROP_PRIORITY:-}" ] && pr=""
    setj="$(printf '%s\n' ${sets[@]+"${sets[@]}"} | jq -Rsc 'split("\n") | map(select(length > 0) | capture("^(?<k>[^=]+)=(?<v>.*)$")
      | .v |= (if test("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$") then tonumber
               elif . == "true" then true elif . == "false" then false else . end))')"
    jq -c --argjson ids "$idj" --arg pr "$pr" --argjson sets "$setj" '
      map(if (.id as $i | $ids | index($i)) then
            (if $pr != "" then .priority = ($pr | tonumber) else . end)
            | .metadata = (reduce $sets[] as $kv ((.metadata // {}); .[$kv.k] = $kv.v))
          else . end)' "$S" > "$S.tmp.$$" && mv "$S.tmp.$$" "$S" ;;
  *) echo "gc stub: unsupported 'bd $verb'" >&2; exit 2 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# Hermetic: the store's environment is the stub's, no inherited GC_*/BEADS_*
# steers the scripts, and the floor refuses any call no stub answers.
unset "${!GC_@}" "${!BEADS_@}" "${!QUEUE_PRIORITY_@}" 2>/dev/null || true
export PATH="$TMP/bin:$FLOOR:$PATH"
export TMPDIR="$TMP"
export STUB_STORE="$TMP/store.json" STUB_CALLS="$TMP/calls" STUB_RIG_TK="$TMP/rig-tk"
DB="$TMP/rig-tk/.beads"
POOL="gc-toolkit/gc-toolkit.polecat"

# run <cmd...> -> RC, OUT, ERR; CALLS is the stub's argv log for the run.
run() {
  : > "$STUB_CALLS"
  "$@" > "$TMP/out" 2> "$TMP/err"; RC=$?
  OUT="$(cat "$TMP/out")"; ERR="$(cat "$TMP/err")"; CALLS="$(cat "$STUB_CALLS")"
}
qp() { run "$QP" "$@"; }
helm() { run sh "$HELM" "$@"; }
prio() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .priority) // "<absent>"' "$STUB_STORE"; }
meta() { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | (.metadata // {})[$k]) // "<absent>" | tostring' "$STUB_STORE"; }
updates() { printf '%s\n' "$CALLS" | grep -c '^bd update' || true; }
set_prio() { jq -c --arg id "$1" --argjson p "$2" 'map(if .id == $id then .priority = $p else . end)' "$STUB_STORE" > "$STUB_STORE.tmp" && mv "$STUB_STORE.tmp" "$STUB_STORE"; }

# The store most cases start from. Stored priorities of beads that follow
# something are stale on purpose.
#   tk-e1     epic P1
#     tk-w1     member, stale P2; its workflow: tk-cv1 (input convoy), tk-r1
#               (root, in_progress), tk-s1a (queued step), tk-s1b (a later step
#               a blocks edge holds), tk-s1c (a claimed step), tk-s1d (closed)
#     tk-w2     member at shift -1
#     tk-wh     member held by the gate tk-g1, stale P3
#     tk-wc     claimed member, stale P3
#     tk-an     an anchor; its PR-finishing work tk-rw (shift -1, with the
#               workflow tk-cvrw / tk-rrw / tk-srw) and tk-rv (no shift)
#   tk-e0     epic P0
#     tk-f0     feature at shift -1
#       tk-t0   task at shift +1
#   tk-e3     epic P3
#   tk-two    member of tk-e3 and tk-e1, at shift +1
#   tk-solo   follows nothing, P3; its workflow tk-cvs / tk-rs / tk-ss sits at P2
#   tk-g1     a park gate
reset_store() {
  cat > "$STUB_STORE" <<'JSON'
[
 {"id":"tk-e1","status":"open","issue_type":"epic","priority":1,"metadata":{},"dependencies":[]},
 {"id":"tk-w1","status":"open","issue_type":"task","priority":2,"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"},
  "dependencies":[{"issue_id":"tk-w1","depends_on_id":"tk-e1","type":"parent-child"}]},
 {"id":"tk-cv1","status":"open","issue_type":"convoy","priority":2,"metadata":{"gc.synthetic":"true"},
  "dependencies":[{"issue_id":"tk-cv1","depends_on_id":"tk-w1","type":"tracks"}]},
 {"id":"tk-r1","status":"in_progress","issue_type":"task","priority":2,"metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cv1","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"},"dependencies":[]},
 {"id":"tk-s1a","status":"open","issue_type":"task","priority":2,"metadata":{"gc.root_bead_id":"tk-r1","gc.step_ref":"mol-polecat-work.implement","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"},
  "dependencies":[{"issue_id":"tk-s1a","depends_on_id":"tk-r1","type":"tracks"}]},
 {"id":"tk-s1b","status":"open","issue_type":"task","priority":2,"metadata":{"gc.root_bead_id":"tk-r1","gc.step_ref":"mol-polecat-work.submit-and-exit","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"},
  "dependencies":[{"issue_id":"tk-s1b","depends_on_id":"tk-s1a","type":"blocks"}]},
 {"id":"tk-s1c","status":"in_progress","issue_type":"task","priority":2,"assignee":"polecat-1","metadata":{"gc.root_bead_id":"tk-r1","gc.step_ref":"mol-polecat-work.load-context","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"},"dependencies":[]},
 {"id":"tk-s1d","status":"closed","issue_type":"task","priority":2,"metadata":{"gc.root_bead_id":"tk-r1","gc.step_ref":"mol-polecat-work.workspace-setup"},"dependencies":[]},
 {"id":"tk-w2","status":"open","issue_type":"task","priority":2,"metadata":{"priority_shift":"-1"},
  "dependencies":[{"issue_id":"tk-w2","depends_on_id":"tk-e1","type":"parent-child"}]},
 {"id":"tk-wh","status":"open","issue_type":"task","priority":3,"metadata":{},
  "dependencies":[{"issue_id":"tk-wh","depends_on_id":"tk-e1","type":"parent-child"},{"issue_id":"tk-wh","depends_on_id":"tk-g1","type":"blocks"}]},
 {"id":"tk-g1","status":"open","issue_type":"gate","priority":2,"metadata":{},"dependencies":[]},
 {"id":"tk-wc","status":"in_progress","issue_type":"task","priority":3,"assignee":"polecat-2","metadata":{},
  "dependencies":[{"issue_id":"tk-wc","depends_on_id":"tk-e1","type":"parent-child"}]},
 {"id":"tk-an","status":"open","issue_type":"task","priority":2,"metadata":{"branch":"polecat/tk-an","merge_result":"pull_request"},
  "dependencies":[{"issue_id":"tk-an","depends_on_id":"tk-e1","type":"parent-child"}]},
 {"id":"tk-rw","status":"open","issue_type":"task","priority":2,"metadata":{"anchor_bead":"tk-an","task_kind":"rework","priority_shift":"-1"},
  "dependencies":[{"issue_id":"tk-rw","depends_on_id":"tk-an","type":"blocks"}]},
 {"id":"tk-cvrw","status":"open","issue_type":"convoy","priority":2,"metadata":{"gc.synthetic":"true"},
  "dependencies":[{"issue_id":"tk-cvrw","depends_on_id":"tk-rw","type":"tracks"}]},
 {"id":"tk-rrw","status":"in_progress","issue_type":"task","priority":2,"metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cvrw"},"dependencies":[]},
 {"id":"tk-srw","status":"open","issue_type":"task","priority":2,"metadata":{"gc.root_bead_id":"tk-rrw","gc.step_ref":"mol-polecat-work.implement","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"},"dependencies":[]},
 {"id":"tk-rv","status":"open","issue_type":"task","priority":0,"metadata":{"anchor_bead":"tk-an","task_kind":"review"},"dependencies":[]},
 {"id":"tk-e0","status":"open","issue_type":"epic","priority":0,"metadata":{},"dependencies":[]},
 {"id":"tk-f0","status":"open","issue_type":"feature","priority":2,"metadata":{"priority_shift":"-1"},
  "dependencies":[{"issue_id":"tk-f0","depends_on_id":"tk-e0","type":"parent-child"}]},
 {"id":"tk-t0","status":"open","issue_type":"task","priority":2,"metadata":{"priority_shift":"+1"},
  "dependencies":[{"issue_id":"tk-t0","depends_on_id":"tk-f0","type":"parent-child"}]},
 {"id":"tk-e3","status":"open","issue_type":"epic","priority":3,"metadata":{},"dependencies":[]},
 {"id":"tk-two","status":"open","issue_type":"task","priority":4,"metadata":{"priority_shift":"+1"},
  "dependencies":[{"issue_id":"tk-two","depends_on_id":"tk-e3","type":"parent-child"},{"issue_id":"tk-two","depends_on_id":"tk-e1","type":"parent-child"}]},
 {"id":"tk-solo","status":"open","issue_type":"bug","priority":3,"metadata":{},"dependencies":[]},
 {"id":"tk-cvs","status":"open","issue_type":"convoy","priority":2,"metadata":{"gc.synthetic":"true"},
  "dependencies":[{"issue_id":"tk-cvs","depends_on_id":"tk-solo","type":"tracks"}]},
 {"id":"tk-rs","status":"in_progress","issue_type":"task","priority":2,"metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cvs"},"dependencies":[]},
 {"id":"tk-ss","status":"open","issue_type":"task","priority":2,"metadata":{"gc.root_bead_id":"tk-rs","gc.step_ref":"mol-polecat-work.implement","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"},"dependencies":[]}
]
JSON
}

echo "# settle"
reset_store
qp settle tk-w2 --print
eq "$RC" 0 "(SETTLE) --print exits 0"
eq "$OUT" "0" "(SETTLE) --print: a member at shift -1 under a P1 epic is P0"
eq "$(updates)" 0 "(SETTLE) --print writes nothing"
[ ! -e "$DB/queue-priority.lock" ] && ok "(SETTLE) --print takes no lock" || bad "(SETTLE) --print takes no lock"

reset_store
qp settle tk-w1
eq "$RC" 0 "(SETTLE) settle exits 0"
has "$OUT" "settled tk-w1 at P1: parent tk-e1 P1, shift 0" "(SETTLE) settle names the priority and how it was derived"
for b in tk-w1 tk-cv1 tk-r1 tk-s1a tk-s1b; do
  eq "$(prio "$b")" 1 "(SETTLE) $b, the member or a bead of its live workflow, is written P1"
done
eq "$(prio tk-s1c)" 2 "(SETTLE) a claimed step is left as it is"
eq "$(prio tk-s1d)" 2 "(SETTLE) a closed step is left as it is"
eq "$(prio tk-e1)" 1 "(SETTLE) the epic it follows is not written"
eq "$(awk '{print $3}' "$DB/queue-priority.holder" 2>/dev/null)" "settle" "(SETTLE) settle takes the lock beside the store"
qp settle tk-w1
eq "$(updates)" 0 "(SETTLE) a settled bead settles again with no write"
has "$OUT" "nothing to write" "(SETTLE) and says there was nothing to write"

reset_store
qp settle tk-solo
eq "$RC" 0 "(SETTLE) settle on a bead that follows nothing exits 0"
eq "$(prio tk-solo)" 3 "(SETTLE) a bead that follows nothing keeps its own priority"
for b in tk-cvs tk-rs tk-ss; do eq "$(prio "$b")" 3 "(SETTLE) $b of its workflow takes it"; done

reset_store
qp settle tk-wc
eq "$RC" 0 "(SETTLE) settle on a claimed member exits 0"
eq "$(prio tk-wc)" 3 "(SETTLE) a claimed member is not rewritten"
has "$OUT" "claimed, left as it is: tk-wc (in_progress)" "(SETTLE) and settle says so"

reset_store
STUB_DROP_PRIORITY=1 qp settle tk-w1
eq "$RC" 1 "(SETTLE) a write that does not read back exits 1"
has "$ERR" "tk-w1 reads P2, not P1" "(SETTLE) naming the bead that did not take the write"

reset_store
jq -c 'map(if .id == "tk-w2" then .metadata.priority_shift = "soon" else . end)' "$STUB_STORE" > "$STUB_STORE.tmp" && mv "$STUB_STORE.tmp" "$STUB_STORE"
qp settle tk-w2
eq "$RC" 1 "(SETTLE) a bead whose priority cannot be computed exits 1"
has "$ERR" 'priority_shift is "soon"' "(SETTLE) naming why"
eq "$(updates)" 0 "(SETTLE) and writes nothing"
qp settle tk-w2 --print
eq "$RC" 1 "(SETTLE) --print on it exits 1 too"
eq "$OUT" "" "(SETTLE) and prints no priority"

reset_store
qp settle tk-nope --print
eq "$RC" 1 "(SETTLE) a bead the store does not hold exits 1"
has "$ERR" "tk-nope does not resolve" "(SETTLE) and says so"
STUB_LIST_FAIL=1 qp settle tk-w1 --print
eq "$RC" 1 "(SETTLE) a store that does not answer exits 1"
has "$ERR" "could not read tk-w1" "(SETTLE) and says it could not read, not that the bead is missing"

# A lock another writer holds past the wait: settle gives up and writes nothing.
reset_store
( exec flock -o -x "$DB/queue-priority.lock" sleep 30 ) </dev/null >/dev/null 2>&1 &
HOLDERS+=("$!")
n=0; until ! flock -n "$DB/queue-priority.lock" true 2>/dev/null || [ "$n" -ge 50 ]; do sleep 0.1; n=$((n + 1)); done
QUEUE_PRIORITY_LOCK_WAIT_SECS=1 qp settle tk-w1
eq "$RC" 1 "(SETTLE) a lock held past the wait exits 1"
has "$ERR" "could not take the priority lock" "(SETTLE) naming the lock"
eq "$(updates)" 0 "(SETTLE) and writes nothing"
eq "$(prio tk-w1)" 2 "(SETTLE) the bead keeps its old priority"
qp settle tk-w1 --print
eq "$RC" 0 "(SETTLE) --print does not wait for the lock"
kill "${HOLDERS[-1]}" 2>/dev/null; wait "${HOLDERS[-1]}" 2>/dev/null

echo "# the priority move"
reset_store
helm priority tk-e1 P2
eq "$RC" 0 "(MOVE) gc-helm.sh priority on an epic exits 0"
has "$OUT" "priority tk-e1 P2, set directly" "(MOVE) it names the new priority"
eq "$(prio tk-e1)" 2 "(MOVE) the epic takes the P-value"
eq "$(prio tk-w1)" 2 "(MOVE) a member with no shift follows it"
eq "$(prio tk-w2)" 1 "(RULES) a member at shift -1 queues at P1 once its epic moves to P2"
for b in tk-cv1 tk-r1 tk-s1a tk-s1b; do eq "$(prio "$b")" 2 "(MOVE) $b, of a member's live workflow, is re-ranked"; done
eq "$(prio tk-s1c)" 2 "(MOVE) a claimed step is left as it is"
eq "$(prio tk-wh)" 2 "(RULES) a held member takes the new priority while its hold holds it"
eq "$(prio tk-wc)" 3 "(MOVE) a claimed member is not rewritten"
has "$OUT" "claimed, left as they are: tk-wc (in_progress, P2 once released)" "(MOVE) and the move names it"
eq "$(prio tk-an)" 2 "(MOVE) an anchor among the members moves"
eq "$(prio tk-rw)" 1 "(MOVE) its PR-finishing work follows, shift and all"
for b in tk-cvrw tk-rrw tk-srw; do eq "$(prio "$b")" 1 "(MOVE) $b, of that work's live workflow, is re-ranked"; done
eq "$(prio tk-rv)" 2 "(MOVE) PR-finishing work with no shift takes the anchor's priority"
eq "$(prio tk-two)" 3 "(RULES) a member of two epics follows the more urgent, plus its shift"
eq "$(prio tk-e0)" 0 "(MOVE) another epic is not touched"
eq "$(prio tk-solo)" 3 "(MOVE) a bead that follows nothing elsewhere is not touched"
eq "$(awk '{print $3}' "$DB/queue-priority.holder" 2>/dev/null)" "move" "(MOVE) the move takes the lock beside the store"
hasnt "$CALLS" "bd update tk-wc" "(MOVE) no write names the claimed member"

reset_store
qp settle tk-w2 --print; eq "$OUT" "0" "(RULES) a member at shift -1 under a P1 epic queues at P0"
qp settle tk-f0 --print; eq "$OUT" "0" "(RULES) under a P0 epic, a feature at shift -1 stays at P0"
qp settle tk-t0 --print; eq "$OUT" "1" "(RULES) and a task under it at shift +1 queues at P1"
qp settle tk-two --print; eq "$OUT" "2" "(RULES) a bead with two parents queues at the more urgent one's priority plus its shift"

reset_store
helm priority tk-w1 P3
eq "$RC" 2 "(MOVE) a P-value on a member is refused (exit 2)"
has "$ERR" "P3 is --shift +2: gc-helm.sh priority tk-w1 --shift +2" "(MOVE) the refusal names the shift that lands it there"
eq "$(updates)" 0 "(MOVE) and nothing is written"
helm priority tk-w2 P1
has "$ERR" "P1 is --shift 0" "(MOVE) a refusal at the epic's own level names shift 0"
helm priority tk-w1 --shift +2
eq "$RC" 0 "(MOVE) --shift on a member exits 0"
eq "$(meta tk-w1 priority_shift)" "2" "(MOVE) the shift is written"
eq "$(prio tk-w1)" 3 "(MOVE) and the member is P3"
for b in tk-cv1 tk-r1 tk-s1a tk-s1b; do eq "$(prio "$b")" 3 "(MOVE) $b, of its workflow, follows"; done
eq "$(prio tk-w2)" 2 "(MOVE) a sibling is not touched"
helm priority tk-w1 --shift -9
eq "$(prio tk-w1)" 0 "(MOVE) a shift past P0 stops at P0"
eq "$(meta tk-w1 priority_shift)" "-9" "(MOVE) and keeps the shift as written"

reset_store
helm priority tk-e1 --shift -1
eq "$RC" 2 "(MOVE) a shift on a bead that follows nothing is refused"
has "$ERR" "tk-e1 follows nothing, so it has no shift" "(MOVE) and says so"
for b in tk-s1a tk-r1 tk-cv1; do
  helm priority "$b" P0
  eq "$RC" 2 "(MOVE) a P-value on $b, part of a workflow, is refused"
  has "$ERR" "part of the workflow poured for tk-w1" "(MOVE) naming the bead it was poured for"
done
helm priority tk-s1a --shift -1
eq "$RC" 2 "(MOVE) a shift on a workflow step is refused"
eq "$(updates)" 0 "(MOVE) and nothing is written"
jq -c 'map(if .id == "tk-e3" then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.tmp" && mv "$STUB_STORE.tmp" "$STUB_STORE"
helm priority tk-e3 P1
eq "$RC" 2 "(MOVE) a closed bead is refused"
has "$ERR" "tk-e3 is closed" "(MOVE) and says so"
helm priority tk-g1 P0
eq "$RC" 0 "(MOVE) a live bead of a class the listing hides, a gate, takes a P-value"
eq "$(prio tk-g1)" 0 "(MOVE) and is written"
helm priority tk-e1 P7;         eq "$RC" 2 "(MOVE) a priority past P4 is refused"
helm priority tk-e1 --shift up; eq "$RC" 2 "(MOVE) a shift that is not a number is refused"
helm priority tk-e1 P1 --shift -1; eq "$RC" 2 "(MOVE) both forms at once are refused"
helm priority tk-e1;            eq "$RC" 2 "(MOVE) neither form is refused"
helm priority;                  eq "$RC" 2 "(MOVE) no bead is refused"
helm priority zz-e1 P1
eq "$RC" 4 "(MOVE) a bead in no rig's store exits 4"
eq "$(updates)" 0 "(MOVE) none of these wrote anything"

reset_store
STUB_LIST_FAIL=1 helm priority tk-e1 P0
eq "$RC" 4 "(MOVE) a store that does not answer exits 4"
has "$ERR" "could not list the store" "(MOVE) and says so"
eq "$(updates)" 0 "(MOVE) with nothing written"

reset_store
helm priority tk-e1 P0 --dry-run
eq "$RC" 0 "(MOVE) --dry-run exits 0"
has "$OUT" "tk-w1 P2->P0" "(MOVE) --dry-run names what it would write"
eq "$(updates)" 0 "(MOVE) --dry-run writes nothing"
eq "$(prio tk-e1)" 1 "(MOVE) and leaves the epic as it is"

reset_store
STUB_DROP_PRIORITY=1 helm priority tk-e1 P0
eq "$RC" 4 "(MOVE) a move whose writes do not read back exits 4"
has "$ERR" "did not all settle" "(MOVE) and says so"

# A park on the epic: its members are out of every queue, and the move still
# reaches them, so each is at its priority when the park is released.
reset_store
jq -c '. + [{"id":"tk-park","status":"open","issue_type":"gate","priority":2,"metadata":{},"dependencies":[]}]
  | map(if .id == "tk-e1" then .dependencies += [{"issue_id":"tk-e1","depends_on_id":"tk-park","type":"blocks"}] else . end)' \
  "$STUB_STORE" > "$STUB_STORE.tmp" && mv "$STUB_STORE.tmp" "$STUB_STORE"
helm priority tk-e1 P0
eq "$RC" 0 "(RULES) a move on a parked epic exits 0"
eq "$(prio tk-w1)" 0 "(RULES) a parked epic's member takes the new priority while the park holds it"
eq "$(prio tk-s1a)" 0 "(RULES) and so does its workflow"
eq "$(prio tk-w2)" 0 "(RULES) a member at shift -1 under a P0 epic stays at P0"

echo "# a shared fixture: settle and the move agree"
# priority-lib.fixture.json's store, every id given this rig's prefix, without
# the beads its cases call unreadable. Two copies: on one, every bead that
# follows nothing is moved to its own priority, which re-ranks everything that
# follows it; on the other, every bead is settled.
errs="$(jq -c '[ .cases[] | select(has("error")) | .bead ] + ["cyc-b"]' "$FX")"
jq -c --argjson errs "$errs" '
  [ .beads[] | .id ] as $ids
  | [ .beads[] | select(.id as $i | $errs | index($i) | not) ]
  | walk(if type == "string" then (. as $v | if ($ids | index($v)) then "tk-" + $v else $v end) else . end)' "$FX" > "$TMP/fx-store.json"
cp "$TMP/fx-store.json" "$STUB_STORE"
# The beads that follow nothing, as the function says, each at its own priority.
roots="$(bash -c '. "$1" && jq -r "$PRIORITY_JQ"'"'"'(map({key: .id, value: .}) | from_entries) as $g
  | .[] | select(.status != "closed" and .status != "pinned")
  | select((priority_of($g) | .kind) == "none") | "\(.id) \(.priority)"'"'"' "$2"' _ "$HERE/priority-lib.sh" "$TMP/fx-store.json")"
[ -n "$roots" ] && ok "(FIXTURE) the beads that follow nothing are found" || bad "(FIXTURE) the beads that follow nothing are found"
move_rc=0
while read -r b p; do
  [ -n "$b" ] || continue
  helm priority "$b" "P$p"; [ "$RC" = 0 ] || { move_rc=1; echo "    move of $b exited $RC: $ERR"; }
done <<< "$roots"
eq "$move_rc" 0 "(FIXTURE) every move over the fixture exits 0"
cp "$STUB_STORE" "$TMP/fx-moved.json"
cp "$TMP/fx-store.json" "$STUB_STORE"
settle_rc=0
for b in $(jq -r '.[] | select(.status != "closed" and .status != "pinned") | .id' "$TMP/fx-store.json"); do
  qp settle "$b"; [ "$RC" = 0 ] || { settle_rc=1; echo "    settle of $b exited $RC: $ERR"; }
done
eq "$settle_rc" 0 "(FIXTURE) every settle over the fixture exits 0"
eq "$(jq -c '[ .[] | {id, priority} ] | sort_by(.id)' "$STUB_STORE")" \
   "$(jq -c '[ .[] | {id, priority} ] | sort_by(.id)' "$TMP/fx-moved.json")" \
   "(FIXTURE) settle and the move give every bead of the shared fixture the same priority"
want="$(jq -c --slurpfile s "$TMP/fx-store.json" '
  [ .cases[] | select(has("priority")) | ("tk-" + .bead) as $id
    | ($s[0][] | select(.id == $id)) as $row
    | select($row.status != "in_progress" or (($row.metadata // {})["gc.kind"] // "") == "workflow")
    | {id: $id, priority} ] | sort_by(.id)' "$FX")"
got="$(jq -c --argjson want "$want" '[ .[] | select(.id as $i | $want | map(.id) | index($i)) | {id, priority} ] | sort_by(.id)' "$STUB_STORE")"
eq "$got" "$want" "(FIXTURE) at the priorities the fixture's cases name"
eq "$(prio tk-m-claimed)" 3 "(FIXTURE) the claimed member keeps its stored priority under both"

echo "# the reconcile pass"
reset_store
# The settled state, then a raw priority edit on the epic no writer sees.
qp settle tk-w1; qp settle tk-w2; qp settle tk-solo
set_prio tk-e1 0
qp reconcile --db "$DB" --pool "$POOL"
eq "$RC" 0 "(PASS) a pass exits 0"
for b in tk-w1 tk-cv1 tk-r1 tk-s1a tk-s1b; do
  eq "$(prio "$b")" 0 "(PASS) a raw edit on the epic reaches $b in one pass"
done
eq "$(prio tk-s1c)" 2 "(PASS) a claimed step is left as it is"
eq "$(printf '%s\n' "$CALLS" | grep -c '^bd ready')" 1 "(PASS) the pass reads the queue once"
has "$CALLS" "bd ready --metadata-field gc.routed_to=$POOL --unassigned --json --limit 0" "(PASS) the queue is what bd ready offers the pool, unassigned"
store_wide="$(printf '%s\n' "$CALLS" | grep '^bd list' | grep -v -e '--id ' -e '--metadata-field ' || true)"
eq "$store_wide" "" "(PASS) the pass reads only the queue and what it follows, never the whole store"
has "$OUT" "settled tk-w1 at P0: parent tk-e1 P0, shift 0 (queued tk-s1a was P1)" "(PASS) the pass names what it settled and why"

qp reconcile --db "$DB" --pool "$POOL"
eq "$(updates)" 0 "(PASS) a queue at its priorities writes nothing"
has "$OUT" "0 at a stale priority" "(PASS) and says so"

# The queued PR-finishing step and the step of a bead that follows nothing.
reset_store
qp reconcile --db "$DB" --pool "$POOL"
eq "$(prio tk-srw)" 0 "(PASS) a queued step of PR-finishing work follows its anchor, shift and all"
eq "$(prio tk-ss)" 3 "(PASS) a queued step of a bead that follows nothing takes that bead's priority"
eq "$(prio tk-solo)" 3 "(PASS) and that bead keeps its own"

reset_store
GC_RIG=gc-toolkit GC_RIG_ROOT="$TMP/rig-tk" qp reconcile
eq "$RC" 0 "(PASS) the order's environment names the store and the pool"
eq "$(prio tk-s1a)" 1 "(PASS) and the pass settles the queue from it"
has "$CALLS" "gc.routed_to=gc-toolkit/gc-toolkit.polecat" "(PASS) reading the rig's polecat pool"

reset_store
qp reconcile --db "$DB" --pool "$POOL" --dry-run
eq "$RC" 0 "(PASS) --dry-run exits 0"
has "$OUT" "DRY-RUN would settle tk-w1 at P1" "(PASS) --dry-run names what it would settle"
eq "$(updates)" 0 "(PASS) --dry-run writes nothing"

reset_store
QUEUE_PRIORITY_PASS_BUDGET_SECS=1 QUEUE_PRIORITY_SETTLE_ALLOWANCE_SECS=5 GC_ORDER_OUTCOME_FILE="$TMP/outcome.json" \
  qp reconcile --db "$DB" --pool "$POOL"
eq "$RC" 0 "(PASS) a pass whose budget covers no settle exits 0"
eq "$(updates)" 0 "(PASS) and writes nothing"
has "$OUT" "left 3 bead(s) for the next pass" "(PASS) naming what it left"
eq "$(jq -r '.outcome' "$TMP/outcome.json" 2>/dev/null)" "partial" "(PASS) and declares the pass partial"

reset_store
STUB_READY_FAIL=1 qp reconcile --db "$DB" --pool "$POOL"
eq "$RC" 1 "(PASS) an unreadable queue fails the pass"
has "$ERR" "NOT treating it as empty" "(PASS) and is never read as an empty one"

reset_store
jq -c 'map(if .id == "tk-rw" then .metadata.priority_shift = "soon" else . end)' "$STUB_STORE" > "$STUB_STORE.tmp" && mv "$STUB_STORE.tmp" "$STUB_STORE"
qp reconcile --db "$DB" --pool "$POOL"
eq "$RC" 1 "(PASS) a queued bead whose priority cannot be computed fails the pass"
has "$ERR" "the priority of queued tk-srw cannot be computed" "(PASS) naming it"
eq "$(prio tk-s1a)" 1 "(PASS) and the rest of the queue still settles"

qp reconcile --db "$DB"
eq "$RC" 2 "(PASS) a pass with no pool is refused"
qp reconcile --pool "$POOL"
eq "$RC" 2 "(PASS) a pass with no store is refused"

# The lock held by another writer: the pass skips its tick and writes nothing.
reset_store
: > "$DB/queue-priority.lock"
( exec flock -o -x "$DB/queue-priority.lock" sleep 30 ) </dev/null >/dev/null 2>&1 &
HOLDERS+=("$!")
n=0; until ! flock -n "$DB/queue-priority.lock" true 2>/dev/null || [ "$n" -ge 50 ]; do sleep 0.1; n=$((n + 1)); done
printf '%s %s move\n' "${HOLDERS[-1]}" "$(date -u +%s)" > "$DB/queue-priority.holder"
GC_ORDER_OUTCOME_FILE="$TMP/outcome.json" qp reconcile --db "$DB" --pool "$POOL"
eq "$RC" 0 "(PASS) a pass that finds the lock held exits 0"
has "$OUT" "skipping this tick" "(PASS) and skips its tick"
eq "$(printf '%s\n' "$CALLS" | grep -c '^bd ' || true)" 0 "(PASS) reading nothing"
eq "$(jq -r '.outcome' "$TMP/outcome.json" 2>/dev/null)" "skipped" "(PASS) and declares the tick skipped"
printf '%s %s move\n' "${HOLDERS[-1]}" "$(( $(date -u +%s) - 1000 ))" > "$DB/queue-priority.holder"
qp reconcile --db "$DB" --pool "$POOL"
eq "$RC" 1 "(PASS) a lock held past the stall bound fails the pass"
has "$ERR" "held past 900s" "(PASS) naming the wedge"
kill "${HOLDERS[-1]}" 2>/dev/null; wait "${HOLDERS[-1]}" 2>/dev/null

echo "# a pass that crosses a move"
# The pass reads the queue with the epic at P1 and is held at its first write.
# A move to P0 starts while it is held. The move must wait for the pass's lock,
# so the pass's P1 lands first and the move's P0 lands over it, never the other
# way round.
reset_store
export STUB_GATE_FILE="$TMP/gate"
: > "$STUB_GATE_FILE"; rm -f "$STUB_GATE_FILE.reached"
STUB_GATE="$STUB_GATE_FILE" "$QP" reconcile --db "$DB" --pool "$POOL" > "$TMP/pass.out" 2>&1 &
pass_pid=$!
n=0; until [ -e "$STUB_GATE_FILE.reached" ] || [ "$n" -ge 100 ]; do sleep 0.1; n=$((n + 1)); done
[ -e "$STUB_GATE_FILE.reached" ] && ok "(CROSSING) the pass reaches its first write" || bad "(CROSSING) the pass reaches its first write"
sh "$HELM" priority tk-e1 P0 > "$TMP/move.out" 2>&1 &
move_pid=$!
sleep 1
eq "$(prio tk-e1)" 1 "(CROSSING) the move waits while the pass holds the lock"
rm -f "$STUB_GATE_FILE"
wait "$pass_pid"; pass_rc=$?
wait "$move_pid"; move_rc=$?
eq "$pass_rc" 0 "(CROSSING) the pass finishes"
eq "$move_rc" 0 "(CROSSING) the move finishes after it"
for b in tk-e1 tk-w1 tk-cv1 tk-r1 tk-s1a tk-s1b; do
  eq "$(prio "$b")" 0 "(CROSSING) $b ends at the move's priority, not the one the pass read"
done
unset STUB_GATE_FILE

echo "# the order"
ORDER="$ROOT/orders/queue-priority.toml"
[ -f "$ORDER" ] && ok "(ORDER) orders/queue-priority.toml exists" || bad "(ORDER) orders/queue-priority.toml exists"
okey() { sed -n "s/^$1 *= *\"\\(.*\\)\"/\\1/p" "$ORDER" | head -n1; }
eq "$(okey trigger)" "cooldown" "(ORDER) it is a cooldown order"
eq "$(okey interval)" "15m" "(ORDER) every fifteen minutes"
eq "$(okey scope)" "rig" "(ORDER) one pass per rig"
eq "$(okey exec)" '$PACK_DIR/assets/scripts/queue-priority.sh reconcile' "(ORDER) running the pass"
timeout_s="$(okey timeout | sed 's/s$//')"
budget="$(sed -n 's/^PASS_BUDGET_SECS="${QUEUE_PRIORITY_PASS_BUDGET_SECS:-\([0-9]*\)}"$/\1/p' "$QP")"
allow="$(sed -n 's/^SETTLE_ALLOWANCE_SECS="${QUEUE_PRIORITY_SETTLE_ALLOWANCE_SECS:-\([0-9]*\)}"$/\1/p' "$QP")"
stall="$(sed -n 's/^LOCK_STALL_SECS="${QUEUE_PRIORITY_LOCK_STALL_SECS:-\([0-9]*\)}"$/\1/p' "$QP")"
if [ -n "$timeout_s" ] && [ -n "$budget" ] && [ -n "$allow" ] && [ -n "$stall" ]; then
  [ $((budget + allow)) -le "$timeout_s" ] && ok "(ORDER) the last settle a pass starts ends inside the order's timeout" \
    || bad "(ORDER) the last settle a pass starts ends inside the order's timeout (budget $budget + allowance $allow > timeout $timeout_s)"
  [ "$stall" -gt "$timeout_s" ] && ok "(ORDER) the stall bound sits above the timeout, so a running pass never reads as wedged" \
    || bad "(ORDER) the stall bound sits above the timeout (stall $stall, timeout $timeout_s)"
else
  bad "(ORDER) the timeout, budget, allowance and stall bound all read (got '$timeout_s' '$budget' '$allow' '$stall')"
fi

echo "# the registry"
REGISTERED="$(sed -n '/^# The metadata-key registry/,$p' "$ROOT/lifecycle/lifecycle.toml" | sed 's/#.*//' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)"
WRITTEN="$(grep -hoE -- '--set-metadata "?[A-Za-z_][A-Za-z0-9_.]*=' "$QP" | sed -E 's/^--set-metadata "?//; s/=$//' | sort -u)"
[ -n "$WRITTEN" ] && ok "(REGISTRY) metadata-key writes extracted" || bad "(REGISTRY) no metadata-key writes found in queue-priority.sh"
eq "$(printf '%s\n' "$WRITTEN" | grep -Fxv -f <(printf '%s\n' "$REGISTERED") | tr '\n' ' ' | sed 's/ *$//')" "" \
   "(REGISTRY) every metadata key queue-priority.sh writes is registered in lifecycle.toml"

echo
echo "queue-priority: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
