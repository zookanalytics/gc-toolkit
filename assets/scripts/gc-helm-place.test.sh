#!/usr/bin/env bash
# Hermetic test for the gc-helm `place` verb (docs/steering.md#placing-a-bead).
#
# WHAT place DOES: it places a bead held for placement, one carrying Gas
# City's hold:mayor label. It clears any route, gives the bead its parent
# (--under, after removing a relates-to link between the two) or none
# (--standalone), moves --shift, settles the priority, dispatches, and then
# lifts the hold with a note in one write, reading each write back.
#
# THE CONTRACT this pins:
#   - a free bead is slung, once, to the polecat pool of its rig unless --route
#     names another, on --on when given, in its rig's store; the sling comes
#     after the parent, the shift and the settle, and before the lift. The
#     lift removes every spelling of hold:mayor and appends the note.
#   - a bead a blocker holds, on itself or on a parent above it (a park on the
#     epic), is armed instead of slung, the formula riding the arm, and its
#     hold is lifted; nothing is slung.
#   - a route a doctor --fix wrote is cleared before the dispatch.
#   - refused with nothing written: a closed bead, PR-finishing work, a bead
#     with no hold:mayor and no dispatch, a bead hold:external also holds, a
#     status other than open, --standalone on a bead with a parent, a parent
#     that is closed or not in the bead's store, and a bead an arm already
#     sends to another pool or on another formula. A bead with no hold that a
#     live run or an arm shows dispatched is reported as placed.
#   - a sling that fails leaves the hold on, and so does an arm that fails.
#   - a stop at any write, then a second run, ends with one run and no hold:
#     the second run dispatches nothing once a live run works the bead or the
#     first run's arm stands, even when the park that held it has closed
#     since, and a sling that exits 3 counts as dispatched.
#
# It runs the REAL gc-helm.sh via `sh` (as shipped), with the real
# resolve-route.sh, run-lib.sh, dispatch-path.sh, bd-lib.sh and hold-lib.sh,
# against a stateful stub `gc`: a JSON store that `bd show`, `bd list`,
# `bd dep list`, `bd dep unrelate`, `bd update` and `sling` read and write in
# the shapes bd and gc print. The priority writer and the arm are stubs that
# log and write the keys their real counterparts write. The test floor sits
# beneath the stubs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
FLOOR="$(cd "$HERE/../../tools/test-floor" 2>/dev/null && pwd)" || FLOOR=""
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-place-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"
if [ -z "$FLOOR" ] || [ ! -x "$FLOOR/gc" ]; then
  echo "gc-helm-place.test.sh: no test floor at tools/test-floor; not running" >&2
  exit 2
fi

mkdir -p "$TMP/bin" "$TMP/rig-tk/.beads"

# --- gc stub ------------------------------------------------------------------
# The store is a JSON array of rows {id, status, issue_type, title, assignee,
# priority, labels, metadata, notes, deps:[{on, type}]}; a row's deps are the
# edges it carries, so a parent-child edge sits on the child, a blocks edge on
# the bead that waits and a tracks edge on the convoy. Every call's argv is
# logged to $STUB_CALLS, and --db is accepted anywhere in a bd call.
#   rig ...          one rig, gc-toolkit at $STUB_RIG_TK, prefix tk.
#   agent list       the polecat pool gc-toolkit/gc-toolkit.polecat.
#   bd show <id>     an array of one row, with labels, metadata, parent and the
#                    targets of its edges as {id, dependency_type, status,
#                    title, issue_type}; an unknown id is bd's error, exit 1.
#   bd list          rows, filtered by --id <csv> and --metadata-field k=v,
#                    each edge {issue_id, depends_on_id, type}.
#   bd dep list <id> --direction=up rows whose edge of -t's type lands on <id>,
#                    --direction=down the targets of <id>'s own edges.
#   bd dep unrelate a b  removes the relates-to edges between a and b, both
#                    ways. STUB_UNRELATE_DROP answers 0 and writes nothing.
#   bd update <id>   --set-metadata, --unset-metadata, --parent (which replaces
#                    the parent edge), --add-label, --remove-label (by exact
#                    text), --append-notes, --priority, --status, --assignee.
#                    STUB_UPDATE_FAIL_ON=<flag> refuses an update carrying that
#                    flag with nothing written.
#   sling            [--rig R] <target> <bead> [--on F]: pours a run of F
#                    (mol-polecat-work when no --on) as Gas City does, a convoy
#                    tracking the bead and a workflow root naming the convoy
#                    and the formula, and stamps gc.execution_routed_to on the
#                    bead. It exits 3 when a live root of F already works the
#                    bead. STUB_SLING_RC exits with that code and writes
#                    nothing.
# Any other call is refused with exit 2.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -u
S="${STUB_STORE:?}"
printf '%s\n' "$*" >> "${STUB_CALLS:?}"
save() { jq -c "$@" "$S" > "$S.tmp" && mv "$S.tmp" "$S"; }
sub="${1:-}"; shift || true
case "$sub" in
  rig)
    jq -n --arg tk "$STUB_RIG_TK" '{rigs:[{name:"gc-toolkit", path:$tk, prefix:"tk"}]}'
    exit 0 ;;
  agent)
    printf '%s\n' '{"agents":[{"name":"polecat","qualified_name":"gc-toolkit/gc-toolkit.polecat","dir":"gc-toolkit","scope":"rig"}]}'
    exit 0 ;;
  sling)
    [ -n "${STUB_SLING_RC:-}" ] && { echo "gc: simulated sling failure" >&2; exit "$STUB_SLING_RC"; }
    target=""; bead=""; f="mol-polecat-work"
    while [ $# -gt 0 ]; do
      case "$1" in
        --rig|--title|--var) shift ;;
        --on) shift; f="${1:-}" ;;
        --*) : ;;
        *) if [ -z "$target" ]; then target="$1"; elif [ -z "$bead" ]; then bead="$1"; fi ;;
      esac
      shift || true
    done
    if jq -e --arg b "$bead" --arg f "$f" '
         . as $all
         | [ $all[] | select(.issue_type == "convoy" and any(.deps[]?; .type == "tracks" and .on == $b)) | .id ] as $cv
         | any($all[]; (.metadata["gc.kind"] // "") == "workflow" and .status != "closed"
                       and (.metadata["gc.formula_name"] // "") == $f
                       and ((.metadata["gc.input_convoy_id"] // "") as $c | $cv | index($c)) != null)' "$S" >/dev/null; then
      echo "gc sling: $bead already has a live $f workflow" >&2
      exit 3
    fi
    n=$(jq '[ .[] | select((.metadata["gc.kind"] // "") == "workflow") ] | length' "$S")
    n=$((n + 1))
    save --arg b "$bead" --arg t "$target" --arg f "$f" --arg cv "tk-cv$n" --arg wf "tk-wf$n" '
      map(if .id == $b then (.metadata |= (del(.["gc.routed_to"]) | .["gc.execution_routed_to"] = $t))
                            | .poured_priority = (.priority // 2)
          else . end)
      + [{id: $cv, status: "open", issue_type: "convoy", title: ("input convoy for " + $b), labels: [], metadata: {"gc.synthetic": "true"}, deps: [{on: $b, type: "tracks"}]},
         {id: $wf, status: "in_progress", issue_type: "task", title: $f, labels: [], metadata: {"gc.kind": "workflow", "gc.input_convoy_id": $cv, "gc.formula_name": $f}, deps: []}]'
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
verb="${1:-}"; shift || true
LISTROW='. as $r | {id, status, issue_type, title, priority, labels: (.labels // []), metadata: (.metadata // {}),
           dependencies: [ .deps[]? | {issue_id: $r.id, depends_on_id: .on, type} ]}
          + (if (.assignee // "") == "" then {} else {assignee} end)'
case "$verb" in
  show)
    id="${1:-}"
    out=$(jq -c --arg id "$id" '
      . as $all
      | [ .[] | select(.id == $id)
          | [ .deps[]? | . as $d | $all[] | select(.id == $d.on)
              | {id, dependency_type: $d.type, status, title, issue_type} ] as $deps
          | {id, status, issue_type, title, priority,
             labels: (if (.labels // []) == [] then null else .labels end),
             metadata: (if (.metadata // {}) == {} then null else .metadata end),
             parent: ([ .deps[]? | select(.type == "parent-child") | .on ] | first // null),
             dependencies: (if ($deps | length) == 0 then null else $deps end)}
            + (if (.assignee // "") == "" then {} else {assignee} end) ]' "$S")
    if [ "$out" = "[]" ]; then
      printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'
      exit 1
    fi
    printf '%s\n' "$out" ;;
  list)
    ids=""; mk=""; mv=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --id) shift; ids="${1:-}" ;;
        --metadata-field) shift; mk="${1%%=*}"; mv="${1#*=}" ;;
      esac
      shift || true
    done
    jq -c --arg ids "$ids" --arg mk "$mk" --arg mv "$mv" "
      [ .[] | select(\$ids == \"\" or (.id as \$i | \$ids | split(\",\") | index(\$i)) != null)
            | select(\$mk == \"\" or ((.metadata[\$mk] // \"\") | tostring) == \$mv)
            | $LISTROW ]" "$S" ;;
  dep)
    case "${1:-}" in
      list)
        id="${2:-}"; dir="down"; ty=""; shift 2 || true
        while [ $# -gt 0 ]; do
          case "$1" in
            --direction=*) dir="${1#--direction=}" ;;
            -t|--type) shift; ty="${1:-}" ;;
            --type=*) ty="${1#--type=}" ;;
          esac
          shift || true
        done
        if [ "$dir" = up ]; then
          jq -c --arg id "$id" --arg ty "$ty" '
            [ .[] | . as $r | .deps[]? | select(.on == $id and ($ty == "" or .type == $ty))
              | ($r | {id, issue_type, status, title, metadata: (.metadata // {})}) + {dependency_type: .type} ]' "$S"
        else
          jq -c --arg id "$id" --arg ty "$ty" '
            . as $all | [ .[] | select(.id == $id) | .deps[]? | select($ty == "" or .type == $ty) | . as $d
              | $all[] | select(.id == $d.on) | {id, issue_type, status, title} + {dependency_type: $d.type} ]' "$S"
        fi ;;
      unrelate)
        a="${2:-}"; b="${3:-}"
        [ -n "${STUB_UNRELATE_DROP:-}" ] && exit 0
        save --arg a "$a" --arg b "$b" '
          map(if .id == $a then .deps |= map(select(.type != "relates-to" or .on != $b))
              elif .id == $b then .deps |= map(select(.type != "relates-to" or .on != $a))
              else . end)' ;;
      *) echo "gc stub: unsupported 'bd dep ${1:-}'" >&2; exit 2 ;;
    esac ;;
  update)
    id="${1:-}"; shift || true
    jq -e --arg id "$id" 'any(.[]; .id == $id)' "$S" >/dev/null \
      || { echo "Error: no issue found matching \"$id\"" >&2; exit 1; }
    if [ -n "${STUB_UPDATE_FAIL_ON:-}" ]; then
      for a in "$@"; do
        case "$a" in "$STUB_UPDATE_FAIL_ON"|"$STUB_UPDATE_FAIL_ON"=*) echo "gc: simulated update failure on $a" >&2; exit 1 ;; esac
      done
    fi
    prog='.'; args=(--arg id "$id"); k=0
    while [ $# -gt 0 ]; do
      k=$((k + 1))
      case "$1" in
        --set-metadata) shift; args+=(--arg "k$k" "${1%%=*}" --arg "v$k" "${1#*=}"); prog="$prog | .metadata[\$k$k] = \$v$k" ;;
        --unset-metadata) shift; args+=(--arg "k$k" "${1:-}"); prog="$prog | .metadata |= del(.[\$k$k])" ;;
        --parent) shift; args+=(--arg "v$k" "${1-}"); prog="$prog | .deps = ([ .deps[]? | select(.type != \"parent-child\") ] + (if \$v$k == \"\" then [] else [{on: \$v$k, type: \"parent-child\"}] end))" ;;
        --parent=*) args+=(--arg "v$k" "${1#--parent=}"); prog="$prog | .deps = ([ .deps[]? | select(.type != \"parent-child\") ] + [{on: \$v$k, type: \"parent-child\"}])" ;;
        --add-label) shift; args+=(--arg "v$k" "${1:-}"); prog="$prog | .labels = ((.labels // []) + [\$v$k] | unique)" ;;
        --remove-label) shift; args+=(--arg "v$k" "${1:-}"); prog="$prog | .labels = [ (.labels // [])[] | select(. != \$v$k) ]" ;;
        --append-notes) shift; args+=(--arg "v$k" "${1:-}"); prog="$prog | .notes = (if (.notes // \"\") == \"\" then \$v$k else .notes + \"\\n\" + \$v$k end)" ;;
        --priority|-p) shift; args+=(--argjson "v$k" "${1:-2}"); prog="$prog | .priority = \$v$k" ;;
        --status=*) args+=(--arg "v$k" "${1#--status=}"); prog="$prog | .status = \$v$k" ;;
        --assignee=*) args+=(--arg "v$k" "${1#--assignee=}"); prog="$prog | .assignee = \$v$k" ;;
        --json) : ;;
        *) echo "gc stub: update: unexpected argument '$1'" >&2; exit 2 ;;
      esac
      shift || true
    done
    save "${args[@]}" "map(if .id == \$id then ($prog) else . end)" ;;
  *) echo "gc stub: unsupported 'bd $verb'" >&2; exit 2 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# --- the priority writer and the arm ----------------------------------------
# queue-priority: `settle <bead>` writes the bead's priority, its parent's plus
# its shift within P0-P4, or its own when it has none, bd's default 2 when
# unset; `move <bead> --shift n` refuses a bead with no parent (exit 2) and
# otherwise writes priority_shift, then settles. STUB_QP_FAIL=settle|move
# fails that verb with nothing written.
cat > "$TMP/bin/queue-priority" <<'QP'
#!/usr/bin/env bash
set -u
S="${STUB_STORE:?}"
printf 'queue-priority %s\n' "$*" >> "${STUB_CALLS:?}"
verb="${1:-}"; bead="${2:-}"
[ "${STUB_QP_FAIL:-}" = "$verb" ] && { echo "queue-priority: simulated $verb failure" >&2; exit 1; }
settle() {
  jq -c --arg b "$1" '
    . as $all
    | map(if .id == $b then
            ([ .deps[]? | select(.type == "parent-child") | .on ] | first // "") as $p
            | if $p == "" then .priority = (.priority // 2)
              else (([ $all[] | select(.id == $p) | (.priority // 2) ] | first // 2)
                    + ((.metadata.priority_shift // "0") | tonumber)) as $n
                   | .priority = (if $n < 0 then 0 elif $n > 4 then 4 else $n end) end
          else . end)' "$S" > "$S.tmp" && mv "$S.tmp" "$S"
}
case "$verb" in
  settle) settle "$bead" ;;
  move)
    n=""; shift 2
    while [ $# -gt 0 ]; do case "$1" in --shift) shift; n="${1:-}" ;; esac; shift || true; done
    jq -e --arg b "$bead" 'any(.[]; .id == $b and any(.deps[]?; .type == "parent-child"))' "$S" >/dev/null \
      || { echo "queue-priority: move: $bead follows nothing, so a shift has nothing to shift from" >&2; exit 2; }
    jq -c --arg b "$bead" --arg n "${n#+}" 'map(if .id == $b then .metadata.priority_shift = $n else . end)' "$S" > "$S.tmp" && mv "$S.tmp" "$S"
    settle "$bead" ;;
  *) echo "queue-priority stub: unsupported '$verb'" >&2; exit 2 ;;
esac
QP
chmod +x "$TMP/bin/queue-priority"

# deferred-dispatch: `arm <bead> --target T [--sling-arg X]... [--reason R]
# [--db D]`, the flags the real arm parses. Like the real one it refuses a
# routed bead and one whose status is not open, and otherwise writes the arm's
# keys. STUB_ARM_FAIL refuses with nothing written.
cat > "$TMP/bin/deferred-dispatch" <<'DD'
#!/usr/bin/env bash
set -u
S="${STUB_STORE:?}"
printf 'deferred-dispatch %s\n' "$*" >> "${STUB_CALLS:?}"
[ "${1:-}" = arm ] || { echo "deferred-dispatch stub: unsupported '${1:-}'" >&2; exit 2; }
bead="${2:-}"; shift 2
target=""; reason=""; sargs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --target) shift; target="${1:-}" ;;
    --reason) shift; reason="${1:-}" ;;
    --sling-arg) shift; sargs+=("${1:-}") ;;
    --db) shift ;;
    *) echo "deferred-dispatch: arm: unknown flag '$1'" >&2; exit 2 ;;
  esac
  shift || true
done
[ -n "${STUB_ARM_FAIL:-}" ] && { echo "deferred-dispatch: simulated arm failure" >&2; exit 1; }
jq -e --arg b "$bead" 'any(.[]; .id == $b and .status == "open" and ((.metadata["gc.routed_to"] // "") == ""))' "$S" >/dev/null \
  || { echo "deferred-dispatch: arm: $bead is routed or not open" >&2; exit 1; }
aj=$(printf '%s\n' ${sargs[@]+"${sargs[@]}"} | jq -Rsc 'split("\n") | map(select(length > 0))')
jq -c --arg b "$bead" --arg t "$target" --arg r "$reason" --argjson a "$aj" '
  map(if .id == $b then .metadata["gc.dispatch_when_ready"] = $t
                        | .metadata["gc.dispatch_when_ready_args"] = ($a | tojson)
                        | .metadata["gc.dispatch_when_ready_reason"] = $r else . end)' "$S" > "$S.tmp" && mv "$S.tmp" "$S"
echo "deferred-dispatch: armed $bead -> $target"
DD
chmod +x "$TMP/bin/deferred-dispatch"

# Hermetic: the store's environment is the stub's, no inherited GC_*/BEADS_*
# steers the script, and the floor refuses any call no stub answers.
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
export PATH="$TMP/bin:$FLOOR:$PATH"
export TMPDIR="$TMP"
export STUB_STORE="$TMP/store.json" STUB_CALLS="$TMP/calls" STUB_RIG_TK="$TMP/rig-tk"
export GC_QUEUE_PRIORITY_TOOL="$TMP/bin/queue-priority"
export GC_DEFERRED_DISPATCH_TOOL="$TMP/bin/deferred-dispatch"

# The store every case starts from.
#   tk-epic     an open epic at P1
#   tk-parked   an epic at P2, parked: it waits on the open gate tk-pg
#   tk-pg       the park's gate
#   tk-gone     a closed epic
#   tk-new      held, loose, related to tk-epic both ways
#   tk-fixed    held, carrying the route mayor a doctor --fix writes
#   tk-case     held under another spelling of the label
#   tk-wait     held, waiting on the open task tk-task by its own blocks edge
#   tk-task     an open task
#   tk-ext      held, and also held by hold:external
#   tk-def      held, and deferred
#   tk-member   held, with the parent tk-epic already
#   tk-pr       held PR-finishing work of tk-anchor
#   tk-anchor   an anchor
#   tk-done     held, and closed
#   tk-raw      open, no hold, no dispatch
#   tk-armed    no hold, armed
#   tk-ran      no hold, a live run (tk-wf9 over tk-cv9) works it
reset_store() {
  cat > "$STUB_STORE" <<'JSON'
[
 {"id":"tk-epic","status":"open","issue_type":"epic","title":"An epic","priority":1,"labels":[],"metadata":{},"deps":[]},
 {"id":"tk-parked","status":"open","issue_type":"epic","title":"A parked epic","priority":2,"labels":[],"metadata":{},"deps":[{"on":"tk-pg","type":"blocks"}]},
 {"id":"tk-pg","status":"open","issue_type":"gate","title":"Parked until the store is faster; close to release","labels":[],"metadata":{},"deps":[]},
 {"id":"tk-gone","status":"closed","issue_type":"epic","title":"A closed epic","priority":1,"labels":[],"metadata":{},"deps":[]},
 {"id":"tk-new","status":"open","issue_type":"task","title":"new work","priority":3,"labels":["hold:mayor"],"metadata":{},"deps":[{"on":"tk-epic","type":"relates-to"}]},
 {"id":"tk-fixed","status":"open","issue_type":"task","title":"routed by a fix","priority":2,"labels":["hold:mayor"],"metadata":{"gc.routed_to":"mayor"},"deps":[]},
 {"id":"tk-case","status":"open","issue_type":"bug","title":"held under another spelling","priority":2,"labels":["learning","Hold:Mayor"],"metadata":{},"deps":[]},
 {"id":"tk-wait","status":"open","issue_type":"task","title":"waits on a task","priority":2,"labels":["hold:mayor"],"metadata":{},"deps":[{"on":"tk-task","type":"blocks"}]},
 {"id":"tk-task","status":"open","issue_type":"task","title":"Land the faster store","priority":2,"labels":[],"metadata":{},"deps":[]},
 {"id":"tk-ext","status":"open","issue_type":"task","title":"held two ways","priority":2,"labels":["hold:mayor","hold:external"],"metadata":{},"deps":[]},
 {"id":"tk-def","status":"deferred","issue_type":"task","title":"held and deferred","priority":2,"labels":["hold:mayor"],"metadata":{},"deps":[]},
 {"id":"tk-member","status":"open","issue_type":"task","title":"held member","priority":1,"labels":["hold:mayor"],"metadata":{},"deps":[{"on":"tk-epic","type":"parent-child"}]},
 {"id":"tk-pr","status":"open","issue_type":"task","title":"a rework","priority":1,"labels":["hold:mayor"],"metadata":{"anchor_bead":"tk-anchor"},"deps":[]},
 {"id":"tk-anchor","status":"open","issue_type":"task","title":"an anchor","priority":1,"labels":[],"metadata":{},"deps":[]},
 {"id":"tk-done","status":"closed","issue_type":"task","title":"held, then closed","priority":2,"labels":["hold:mayor"],"metadata":{},"deps":[]},
 {"id":"tk-raw","status":"open","issue_type":"task","title":"raw input","priority":2,"labels":[],"metadata":{},"deps":[]},
 {"id":"tk-armed","status":"open","issue_type":"task","title":"placed and armed","priority":2,"labels":[],"metadata":{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"},"deps":[]},
 {"id":"tk-ran","status":"open","issue_type":"task","title":"placed, and running","priority":2,"labels":[],"metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"},"deps":[]},
 {"id":"tk-cv9","status":"open","issue_type":"convoy","title":"input convoy for tk-ran","labels":[],"metadata":{"gc.synthetic":"true"},"deps":[{"on":"tk-ran","type":"tracks"}]},
 {"id":"tk-wf9","status":"in_progress","issue_type":"task","title":"mol-polecat-work","labels":[],"metadata":{"gc.kind":"workflow","gc.input_convoy_id":"tk-cv9","gc.formula_name":"mol-polecat-work"},"deps":[]}
]
JSON
}

# run_place <arg...> -> RC, OUT, ERR, CALLS; BEFORE/AFTER are the store's bytes.
run_place() {
  : > "$STUB_CALLS"
  BEFORE="$(cat "$STUB_STORE")"
  RC=0
  OUT="$(sh "$SCRIPT" place "$@" 2>"$TMP/err")" || RC=$?
  ERR="$(cat "$TMP/err")"
  CALLS="$(cat "$STUB_CALLS")"
  AFTER="$(cat "$STUB_STORE")"
}
row()    { jq -c --arg id "$1" '.[] | select(.id == $id)' "$STUB_STORE"; }
labels() { row "$1" | jq -r '(.labels // []) | join(",")'; }
meta()   { row "$1" | jq -r --arg k "$2" '(.metadata // {})[$k] // ""'; }
parent() { row "$1" | jq -r '[ .deps[]? | select(.type == "parent-child") | .on ] | join(",")'; }
runs()   { jq -r --arg b "$1" '. as $all | [ $all[] | select(.issue_type == "convoy" and any(.deps[]?; .type == "tracks" and .on == $b)) | .id ] as $cv
             | [ $all[] | select((.metadata["gc.kind"] // "") == "workflow" and ((.metadata["gc.input_convoy_id"] // "") as $c | $cv | index($c)) != null) ] | length' "$STUB_STORE"; }
# line_of <pattern> — the line of the last run's call log that first matches.
line_of() { printf "%s\n" "$CALLS" | grep -n -F -- "$1" | head -n1 | cut -d: -f1 || true; }
before() { local a b; a="$(line_of "$1")"; b="$(line_of "$2")"
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "$3"; else bad "$3 ('$1' at line ${a:-none}, '$2' at line ${b:-none})"; fi; }
unchanged() { [ "$BEFORE" = "$AFTER" ] && ok "$1" || bad "$1 (the store changed)"; }
called() { if grep -q -F -- "$1" <<< "$CALLS"; then ok "$2"; else bad "$2 (no call carries '$1')"; fi; }

echo "# a free bead placed under an epic: unrelate, parent, settle, sling, lift"
reset_store
run_place tk-new --under tk-epic
eq "$RC" "0" "(UNDER) placing a held bead under an open epic exits 0"
eq "$(parent tk-new)" "tk-epic" "(UNDER) the bead's parent is the epic"
eq "$(row tk-new | jq -r '[ .deps[]? | select(.type == "relates-to") ] | length')" "0" "(UNDER) the relates-to link to the epic is gone"
eq "$(row tk-epic | jq -r '[ .deps[]? | select(.type == "relates-to") ] | length')" "0" "(UNDER) and so is the epic's side of it"
eq "$(labels tk-new)" "" "(UNDER) the hold is lifted"
eq "$(runs tk-new)" "1" "(UNDER) one run works the bead"
eq "$(meta tk-new gc.execution_routed_to)" "gc-toolkit/gc-toolkit.polecat" "(UNDER) slung to the polecat pool of its rig"
eq "$(row tk-new | jq -r '.poured_priority')" "1" "(UNDER) the pour copied the epic's priority, settled before the sling"
called "sling --rig gc-toolkit gc-toolkit/gc-toolkit.polecat tk-new" "(UNDER) the sling names the bead's rig and its pool"
hasnt "$CALLS" "--on" "(UNDER) with no --on the sling leaves the formula to the pool's default"
before "bd dep unrelate tk-new tk-epic" "--parent tk-epic" "(ORDER) the relates-to link goes before the parent"
before "--parent tk-epic" "queue-priority settle tk-new" "(ORDER) the parent lands before the settle"
before "queue-priority settle tk-new" "sling " "(ORDER) the settle comes before the sling"
before "sling " "--remove-label hold:mayor" "(ORDER) the sling comes before the lift"
called "--remove-label hold:mayor --append-notes Placed at" "(LIFT) the lift and its note ride one write"
has "$(row tk-new | jq -r '.notes')" "under tk-epic at P1: slung to gc-toolkit/gc-toolkit.polecat" "(LIFT) the note says where it was placed and how it was sent"
has "$OUT" "place: tk-new placed under tk-epic at P1: slung to gc-toolkit/gc-toolkit.polecat; hold:mayor lifted" "(UNDER) the summary names the placement"

echo "# --shift, --route and --on"
reset_store
run_place tk-new --under tk-epic --shift +1 --route gc-toolkit/gc-toolkit.crew --on mol-design
eq "$RC" "0" "(FLAGS) placing with --shift, --route and --on exits 0"
eq "$(meta tk-new priority_shift)" "1" "(FLAGS) the shift is written through queue-priority.sh move"
eq "$(row tk-new | jq -r '.poured_priority')" "2" "(FLAGS) the pour copied the epic's priority plus the shift"
before "--parent tk-epic" "queue-priority move tk-new --shift +1" "(FLAGS) the shift moves once the parent is set"
before "queue-priority move tk-new --shift +1" "queue-priority settle tk-new" "(FLAGS) and before the settle"
has "$CALLS" "sling --rig gc-toolkit gc-toolkit/gc-toolkit.crew tk-new --on mol-design" "(FLAGS) the sling goes to --route on --on"
eq "$(labels tk-new)" "" "(FLAGS) the hold is lifted"

echo "# standalone, a fix's route, and another spelling of the label"
reset_store
run_place tk-fixed --standalone
eq "$RC" "0" "(STANDALONE) placing a held bead with no parent exits 0"
eq "$(parent tk-fixed)" "" "(STANDALONE) the bead has no parent"
eq "$(meta tk-fixed gc.routed_to)" "" "(STANDALONE) the route mayor is gone"
before "--unset-metadata gc.routed_to" "sling " "(STANDALONE) the fix's route is cleared before the dispatch"
eq "$(labels tk-fixed)" "" "(STANDALONE) the hold is lifted"
has "$OUT" "placed with no parent at P2" "(STANDALONE) the summary says it has no parent"
reset_store
run_place tk-case --standalone
eq "$RC" "0" "(SPELLING) a bead held as Hold:Mayor is placed"
eq "$(labels tk-case)" "learning" "(SPELLING) its spelling of the hold is removed, and its other labels stay"

echo "# a bead a blocker holds is armed, not slung"
reset_store
run_place tk-new --under tk-parked --on mol-polecat-work
eq "$RC" "0" "(PARKED) placing under a parked epic exits 0"
eq "$(runs tk-new)" "0" "(PARKED) nothing is poured"
hasnt "$CALLS" "sling " "(PARKED) nothing is slung"
eq "$(meta tk-new gc.dispatch_when_ready)" "gc-toolkit/gc-toolkit.polecat" "(PARKED) the bead is armed for the polecat pool"
eq "$(meta tk-new gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "(PARKED) the formula rides the arm"
has "$(meta tk-new gc.dispatch_when_ready_reason)" "tk-pg" "(PARKED) the arm names the park that holds it"
eq "$(labels tk-new)" "" "(PARKED) the hold is lifted"
before "deferred-dispatch arm tk-new" "--remove-label hold:mayor" "(PARKED) the arm comes before the lift"
has "$OUT" "armed for gc-toolkit/gc-toolkit.polecat on mol-polecat-work, held by tk-pg" "(PARKED) the summary names the hold"
reset_store
run_place tk-wait --standalone
eq "$RC" "0" "(BLOCKED) placing a bead with an open blocker of its own exits 0"
hasnt "$CALLS" "sling " "(BLOCKED) it is not slung"
eq "$(meta tk-wait gc.dispatch_when_ready)" "gc-toolkit/gc-toolkit.polecat" "(BLOCKED) it is armed"
eq "$(labels tk-wait)" "" "(BLOCKED) its hold is lifted"
reset_store
run_place tk-fixed --under tk-parked
eq "$RC" "0" "(PARKED) a bead a fix routed is armed under a park once its route is cleared"
eq "$(meta tk-fixed gc.routed_to)" "" "(PARKED) its route is gone"
eq "$(meta tk-fixed gc.dispatch_when_ready)" "gc-toolkit/gc-toolkit.polecat" "(PARKED) and it is armed"

echo "# refused with nothing written"
refused() { # <rc> <msg-fragment> <label> <args...>
  local want="$1" frag="$2" label="$3"; shift 3
  reset_store
  run_place "$@"
  eq "$RC" "$want" "(REFUSE) $label exits $want"
  has "$ERR" "$frag" "(REFUSE) $label says why"
  unchanged "(REFUSE) $label writes nothing"
  hasnt "$CALLS" "sling " "(REFUSE) $label slings nothing"
}
refused 2 "is closed" "a closed bead" tk-done --standalone
refused 2 "PR-finishing work of tk-anchor" "PR-finishing work" tk-pr --standalone
refused 2 "carries no hold:mayor" "a bead with no hold and no dispatch" tk-raw --standalone
refused 2 "also carries hold:external" "a bead hold:external also holds" tk-ext --standalone
refused 2 "is deferred" "a deferred bead" tk-def --standalone
refused 2 "it has one, tk-epic" "--standalone on a bead with a parent" tk-member --standalone
refused 2 "tk-gone is closed" "a closed parent" tk-new --under tk-gone
refused 4 "does not resolve in rig gc-toolkit" "a parent no store row answers" tk-new --under tk-nowhere
refused 4 "does not resolve" "a bead no store row answers" tk-nowhere --standalone
refused 4 "no rig's store holds" "a bead in no rig" zz-1 --standalone

echo "# already placed"
reset_store
run_place tk-ran --standalone
eq "$RC" "0" "(PLACED) a bead with no hold that a live run works exits 0"
has "$OUT" "already placed (live run tk-wf9)" "(PLACED) and is reported as placed"
unchanged "(PLACED) with nothing written"
reset_store
run_place tk-armed --standalone
eq "$RC" "0" "(PLACED) a bead with no hold that an arm dispatches exits 0"
has "$OUT" "already placed (armed for gc-toolkit/gc-toolkit.polecat)" "(PLACED) and is reported as placed"
unchanged "(PLACED) armed, with nothing written"

echo "# a dispatch that fails leaves the hold on"
reset_store
STUB_SLING_RC=1 run_place tk-new --under tk-epic
eq "$RC" "4" "(SLING-FAIL) a sling that fails exits 4"
eq "$(labels tk-new)" "hold:mayor" "(SLING-FAIL) the hold stays on"
has "$ERR" "its hold stays on" "(SLING-FAIL) and the message says so"
has "$ERR" "gc-helm place tk-new --under tk-epic" "(SLING-FAIL) with the command that finishes it"
run_place tk-new --under tk-epic
eq "$RC" "0" "(SLING-FAIL) a second run finishes the placement"
eq "$(runs tk-new)" "1" "(SLING-FAIL) with one run"
eq "$(labels tk-new)" "" "(SLING-FAIL) and no hold"
reset_store
STUB_ARM_FAIL=1 run_place tk-new --under tk-parked
eq "$RC" "4" "(ARM-FAIL) an arm that fails exits 4"
eq "$(labels tk-new)" "hold:mayor" "(ARM-FAIL) the hold stays on"
run_place tk-new --under tk-parked
eq "$RC" "0" "(ARM-FAIL) a second run arms it"
eq "$(labels tk-new)" "" "(ARM-FAIL) and lifts the hold"

echo "# a stop at any write, then a second run: one run, no hold"
stop_then_finish() { # <label> <env assignment> <args...>
  local label="$1" fault="$2"; shift 2
  reset_store
  : > "$STUB_CALLS"
  RC=0; env "$fault" sh "$SCRIPT" place "$@" >/dev/null 2>"$TMP/err" || RC=$?
  eq "$RC" "4" "(STOP) a stop at $label exits 4"
  eq "$(labels tk-new)" "hold:mayor" "(STOP) a stop at $label leaves the hold on"
  run_place "$@"
  eq "$RC" "0" "(STOP) after a stop at $label, a second run exits 0"
  eq "$(labels tk-new)" "" "(STOP) after a stop at $label, the hold is lifted"
  eq "$(parent tk-new)" "tk-epic" "(STOP) after a stop at $label, the parent is set"
  eq "$(runs tk-new)" "1" "(STOP) after a stop at $label, one run works the bead"
}
stop_then_finish "the unrelate" STUB_UNRELATE_DROP=1 tk-new --under tk-epic
stop_then_finish "the parent" STUB_UPDATE_FAIL_ON=--parent tk-new --under tk-epic
stop_then_finish "the shift" STUB_QP_FAIL=move tk-new --under tk-epic --shift -1
stop_then_finish "the settle" STUB_QP_FAIL=settle tk-new --under tk-epic
stop_then_finish "the lift" STUB_UPDATE_FAIL_ON=--remove-label tk-new --under tk-epic
reset_store
(export STUB_UPDATE_FAIL_ON=--remove-label; sh "$SCRIPT" place tk-new --under tk-epic >/dev/null 2>&1) || true
run_place tk-new --under tk-epic
hasnt "$CALLS" "sling " "(STOP) after a stop at the lift, the second run slings nothing, since a live run works the bead"
has "$OUT" "already dispatched (live run tk-wf" "(STOP) and says the earlier dispatch stands"
reset_store
(export STUB_UPDATE_FAIL_ON=--unset-metadata; sh "$SCRIPT" place tk-fixed --standalone >/dev/null 2>&1) && bad "(STOP) a route clear that fails exits non-zero" || ok "(STOP) a route clear that fails exits non-zero"
eq "$(labels tk-fixed)" "hold:mayor" "(STOP) a route clear that fails leaves the hold on"
run_place tk-fixed --standalone
eq "$RC" "0" "(STOP) after a failed route clear, a second run finishes"
eq "$(runs tk-fixed)" "1" "(STOP) with one run"
reset_store
(export STUB_UPDATE_FAIL_ON=--remove-label; sh "$SCRIPT" place tk-new --under tk-parked >/dev/null 2>&1) || true
run_place tk-new --under tk-parked
eq "$RC" "0" "(STOP) after a stop at an armed bead's lift, a second run finishes"
eq "$(labels tk-new)" "" "(STOP) its hold is lifted"
hasnt "$CALLS" "sling " "(STOP) and nothing is slung"
hasnt "$CALLS" "deferred-dispatch arm" "(STOP) and the first run's arm is kept, not written again"
# The park closes between the stop and the second run: the first run's arm is
# the dispatch, which the deferred-dispatch pass slings once the hold is gone,
# so a sling beside it would start a second run when it fires.
reset_store
(export STUB_UPDATE_FAIL_ON=--remove-label; sh "$SCRIPT" place tk-new --under tk-parked >/dev/null 2>&1) || true
jq -c 'map(if .id == "tk-pg" then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.tmp" && mv "$STUB_STORE.tmp" "$STUB_STORE"
run_place tk-new --under tk-parked
eq "$RC" "0" "(STOP-FREED) after a stop at an armed bead's lift and its park's close, a second run finishes"
hasnt "$CALLS" "sling " "(STOP-FREED) …slinging nothing beside the arm"
hasnt "$CALLS" "deferred-dispatch arm" "(STOP-FREED) …and arming nothing again"
eq "$(meta tk-new gc.dispatch_when_ready)" "gc-toolkit/gc-toolkit.polecat" "(STOP-FREED) …keeping the arm, which the pass slings once the hold is gone"
eq "$(labels tk-new)" "" "(STOP-FREED) …and lifting the hold"
has "$OUT" "already armed for gc-toolkit/gc-toolkit.polecat" "(STOP-FREED) …and says the arm stands"

echo "# an arm that would send the bead elsewhere is refused"
# arm_new <target> <args-json> — tk-new armed the way deferred-dispatch.sh arm
# stores it, the sling args as a JSON string.
arm_new() {
  jq -c --arg t "$1" --arg a "$2" 'map(if .id == "tk-new" then .metadata["gc.dispatch_when_ready"] = $t | .metadata["gc.dispatch_when_ready_args"] = $a else . end)' \
    "$STUB_STORE" > "$STUB_STORE.tmp" && mv "$STUB_STORE.tmp" "$STUB_STORE"
}
reset_store; arm_new gc-toolkit/gc-toolkit.other '[]'
run_place tk-new --under tk-epic
eq "$RC" "2" "(ARMED-ELSEWHERE) a bead armed for another pool exits 2"
has "$ERR" "already armed for gc-toolkit/gc-toolkit.other" "(ARMED-ELSEWHERE) …naming the arm"
has "$ERR" "disarm tk-new" "(ARMED-ELSEWHERE) …and the disarm that frees it"
unchanged "(ARMED-ELSEWHERE) …with nothing written"
hasnt "$CALLS" "sling " "(ARMED-ELSEWHERE) …and nothing slung"
reset_store; arm_new gc-toolkit/gc-toolkit.polecat '[]'
run_place tk-new --under tk-epic --on mol-polecat-report
eq "$RC" "2" "(ARMED-ELSEWHERE) a bead armed on another formula exits 2"
unchanged "(ARMED-ELSEWHERE) …with nothing written"
reset_store; arm_new gc-toolkit/gc-toolkit.polecat '["--on","mol-polecat-work"]'
run_place tk-new --under tk-epic --on mol-polecat-work
eq "$RC" "0" "(ARMED-SAME) a bead armed where this placement sends it exits 0"
hasnt "$CALLS" "sling " "(ARMED-SAME) …slinging nothing beside the arm"
eq "$(labels tk-new)" "" "(ARMED-SAME) …and lifting the hold"

echo "# a sling that exits 3 counts as dispatched"
reset_store
STUB_SLING_RC=3 run_place tk-new --under tk-epic
eq "$RC" "0" "(LIVE) a sling refused because a live run works the bead exits 0"
eq "$(labels tk-new)" "" "(LIVE) and the hold is lifted"
has "$OUT" "a live run already works it" "(LIVE) the summary says a live run works it"

echo
echo "gc-helm-place: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
