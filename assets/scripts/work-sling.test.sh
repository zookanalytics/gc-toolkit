#!/usr/bin/env bash
# Hermetic test for assets/scripts/work-sling.sh — the sling of a work bead, which
# gives a convoy that is its own work bead an input convoy that tracks it alone.
# Covers: the usage refusals; a sling that pours no formula, and one onto a bead
# that is not a convoy, a convoy with no branch or a closed convoy, each handed
# to gc sling as it stands; a pour onto a convoy that carries a branch made
# through an input convoy that tracks it alone, marked, at its priority and
# target, with the bead stamped the way gc sling stamps any bead it pours onto,
# and the run mol-polecat-work's own derivation finds working on the bead; a live
# run of the formula on the bead refused, and a closed run or one of another
# formula not; and every way it stops short, each leaving nothing slung and no
# convoy of its own open, except one a workflow root names. Over stores of their
# own: the convoy made in the bead's store and the sling naming its rig, from
# city scope with --db, from another rig with and without --db, and in the
# city's own store; the check for a live run read in the bead's store; and a
# --db no rig keeps or a prefix no rig carries refused. The lock: kept under the
# city root, or under the city's row in the rig list when the environment names
# no root, and refused with none, or with no flock; a held lock waited on, given
# up with nothing slung, or taken once released; no gc call handed its
# descriptor; and two calls interleaved at the check for a live run pouring
# once. The harness gc stub stands in for gc and its store, behind a router
# that gives it several stores.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-sling-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/work-sling.sh" "$HERE/bead-store.sh"
export GC_RIG="gc-toolkit"
ROUTE="gc-toolkit/gc-toolkit.polecat"

# The gc this suite runs is a router in front of the harness stub, gc-store.
# With STUB_STORE_TABLE unset it hands every call to the stub over the harness's
# one store. With it set, each line of that file is a store,
# "<name>|<path>|<prefix>|<rig or hq>|<beads file>|<deps file>", and each call
# goes to the store gc picks for it: the store a --db or --rig pin names; for a
# bd read or write of an id, the store its prefix names; for a convoy add,
# status or close, the store of the convoy's prefix; for a sling, the store of
# its bead's prefix; for a convoy create, its --rig, or the city's under
# --city-scope; otherwise GC_RIG's store, else the city's. A create mints its id
# with its store's prefix. STUB_BARRIER_DIR holds each read of the convoys that
# track a bead there, after recording its arrival, until a file named release
# appears in it. STUB_SLING_ROOTS has a sling that exits 0 leave in its store
# the live workflow root its pour makes. STUB_FD9_LOG records, for each call,
# whether it was handed fd 9.
mv "$BIN/gc" "$BIN/gc-store"
{ _stub_shebang; cat <<'ROUTER'; } > "$BIN/gc"
set -u
args=("$@")
if [ -n "${STUB_FD9_LOG:-}" ]; then
  if { : >&9; } 2>/dev/null; then fd9=open; else fd9=closed; fi
  printf '%s fd9=%s\n' "${1:-} ${2:-}" "$fd9" >> "$STUB_FD9_LOG"
fi
if [ -n "${STUB_BARRIER_DIR:-}" ] && [ "${1:-}" = bd ]; then
  case " $* " in
    *" dep list "*" tracks "*)
      : > "$STUB_BARRIER_DIR/arrived.$$"
      i=0; while [ ! -e "$STUB_BARRIER_DIR/release" ] && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done ;;
  esac
fi
target=""; bead=""; formula=""
if [ "${1:-}" = sling ]; then
  prev=""
  for a in "${args[@]:1}"; do
    case "$prev" in
      --on) formula="$a" ;;
      --rig) : ;;
      *) case "$a" in
           --on=*) formula="${a#--on=}" ;;
           -*) : ;;
           *) if [ -z "$target" ]; then target="$a"; elif [ -z "$bead" ]; then bead="$a"; fi ;;
         esac ;;
    esac
    prev="$a"
  done
fi
if [ -n "${STUB_STORE_TABLE:-}" ]; then
  T="$STUB_STORE_TABLE"
  by_name() { awk -F'|' -v n="$1" '$1 == n { print; exit }' "$T"; }
  by_id()   { awk -F'|' -v id="$1" 'index(id, $3 "-") == 1 { print; exit }' "$T"; }
  city()    { awk -F'|' '$4 == "hq" { print; exit }' "$T"; }
  by_db() {
    local want n p
    want=$(cd "$1" 2>/dev/null && pwd -P) || return 0
    while IFS='|' read -r n p _; do
      [ "$(cd "$p/.beads" 2>/dev/null && pwd -P)" = "$want" ] && { by_name "$n"; return 0; }
    done < "$T"
  }
  ambient() { if [ -n "${GC_RIG:-}" ]; then by_name "$GC_RIG"; else city; fi; }
  row=""
  case "${1:-}" in
    bd)
      i=1; pinned=0
      while [ "$i" -lt "${#args[@]}" ]; do
        case "${args[$i]}" in
          --db)  row=$(by_db "${args[$((i + 1))]:-}"); pinned=1; i=$((i + 2)) ;;
          --rig) row=$(by_name "${args[$((i + 1))]:-}"); pinned=1; i=$((i + 2)) ;;
          *) break ;;
        esac
      done
      if [ "$pinned" = 0 ]; then
        case "${args[$i]:-}" in
          show|update|close|dep)
            for t in "${args[@]:$((i + 1))}"; do
              case "$t" in -*) continue ;; esac
              row=$(by_id "$t"); [ -n "$row" ] && break
            done ;;
        esac
        [ -n "$row" ] || row=$(ambient)
      fi ;;
    convoy)
      case "${2:-}" in
        create)
          row=$(ambient); prev=""
          for a in "${args[@]:2}"; do
            [ "$prev" = "--rig" ] && row=$(by_name "$a")
            [ "$a" = "--city-scope" ] && row=$(city)
            prev="$a"
          done ;;
        *) row=$(by_id "${3:-}") ;;
      esac ;;
    sling) row=$(by_id "$bead") ;;
    *) row=$(ambient) ;;
  esac
  [ -n "$row" ] || { echo "gc: no store answers '$*'" >&2; exit 1; }
  IFS='|' read -r _ _ prefix _ beads deps <<< "$row"
  export STUB_STORE="$beads" STUB_DEPS="$deps" STUB_MINT_PREFIX="$prefix"
fi
"$(dirname "$0")/gc-store" "$@"; rc=$?
if [ "$rc" = 0 ] && [ "${1:-}" = sling ] && [ -n "${STUB_SLING_ROOTS:-}" ] && [ -n "$bead" ]; then
  tmp="${STUB_STORE%/*}/.gc-router.$$"
  jq -c --arg c "$bead" --arg f "$formula" '. + [{id: ("wf-" + ((length + 1) | tostring)), status: "open", issue_type: "task", title: $f,
      metadata: {"gc.kind": "workflow", "gc.formula_name": $f, "gc.input_convoy_id": $c}}]' "$STUB_STORE" > "$tmp" && mv "$tmp" "$STUB_STORE"
fi
exit "$rc"
ROUTER
chmod +x "$BIN/gc"

# The rig roster: the city's own store and two rigs, each store in <path>/.beads.
# The anchor's rig keeps the harness's own store files, which the helpers below
# read. The lock is kept under the city root the environment names, which is
# not the city's row in the roster, so a lock under that row is the fallback's.
mkdir -p "$TMP/city/.beads" "$TMP/rigs/gc-toolkit/.beads" "$TMP/rigs/other/.beads" "$TMP/city-env"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"town","path":"$TMP/city","prefix":"ct","hq":true},
         {"name":"gc-toolkit","path":"$TMP/rigs/gc-toolkit","prefix":"tk","hq":false},
         {"name":"other","path":"$TMP/rigs/other","prefix":"ot","hq":false}]}
EOF
export STUB_RIGS_JSON="$TMP/rigs.json"
export GC_CITY_PATH="$TMP/city-env"
LOCKF="$GC_CITY_PATH/.gc/runtime/packs/gc-toolkit/work-sling/gc-toolkit/tk-g.lock"
TABLE="$TMP/stores.txt"
printf '%s\n' "town|$TMP/city|ct|hq|$TMP/city/.beads/beads.json|$TMP/city/.beads/deps.txt" \
  "gc-toolkit|$TMP/rigs/gc-toolkit|tk|rig|$STUB_STORE|$STUB_DEPS" \
  "other|$TMP/rigs/other|ot|rig|$TMP/rigs/other/.beads/beads.json|$TMP/rigs/other/.beads/deps.txt" > "$TABLE"

# mol-polecat-work takes the one bead its input convoy tracks as its work bead.
# The derivation is read from the formula, so this suite follows it.
DERIVE=$(grep -m 1 -o "jq -r 'if (.children | length) == 1 then [^']*'" "$HERE/../../formulas/mol-polecat-work.toml" | sed "s/^jq -r '//; s/'\$//")
has "$DERIVE" ".children[0].id" "mol-polecat-work's work-bead derivation was read from the formula"
work_bead_of() { gc convoy status "$1" --json 2>/dev/null | jq -r "$DERIVE" 2>/dev/null; }

# A graduation's anchor: a convoy carrying the branch and target
# convoy-graduate.sh stamps, tracking the three members it landed. $1 adds to
# the store, $2 to its metadata.
anchor() { # [extra-rows] [extra-metadata-fields]
  store "[{\"id\":\"tk-g\",\"status\":\"open\",\"assignee\":\"\",\"title\":\"g\",\"issue_type\":\"convoy\",\"priority\":1,\"metadata\":{\"branch\":\"integration/tk-g\",\"target\":\"main\",\"graduation\":true${2:-}}},
          {\"id\":\"tk-m1\",\"status\":\"closed\",\"title\":\"m1\",\"metadata\":{}},
          {\"id\":\"tk-m2\",\"status\":\"closed\",\"title\":\"m2\",\"metadata\":{}},
          {\"id\":\"tk-m3\",\"status\":\"closed\",\"title\":\"m3\",\"metadata\":{}}${1:-}]"
  : > "$STUB_DEPS"
  local m
  for m in tk-m1 tk-m2 tk-m3; do printf 'tk-g|tracks|%s\n' "$m" >> "$STUB_DEPS"; done
}
# The city's store and the other rig's, each holding one bead of its own.
others() {
  echo '[{"id":"ct-x","status":"open","title":"x","metadata":{}}]' > "$TMP/city/.beads/beads.json"; : > "$TMP/city/.beads/deps.txt"
  echo '[{"id":"ot-x","status":"open","title":"x","metadata":{}}]' > "$TMP/rigs/other/.beads/beads.json"; : > "$TMP/rigs/other/.beads/deps.txt"
}
reset() {
  : > "$STUB_GC_LOG"
  export STUB_SLING_FAIL="" STUB_UPDATE_FAIL="" STUB_SHOW_FAIL="" STUB_DROP_KEYS="" STUB_DEP_PARTIAL=""
  export STUB_CONVOY_CREATE_FAIL="" STUB_CONVOY_ADD_FAIL=""
  unset STUB_STORE_TABLE STUB_BARRIER_DIR STUB_SLING_ROOTS STUB_FD9_LOG
}
# $out is stderr and stdout together.
run() { "$SD/work-sling.sh" "$@" > "$TMP/stdout" 2> "$TMP/stderr"; rc=$?; out=$(cat "$TMP/stderr" "$TMP/stdout"); }
slung() { grep '^sling ' "$STUB_GC_LOG" || true; }
slings() { grep -c '^sling ' "$STUB_GC_LOG" || true; }
convoys() { jq -r '[.[] | select((.issue_type // "") == "convoy" and .id != "tk-g") | .id] | join(" ")' "$STUB_STORE"; }
open_convoys() { jq -r '[.[] | select((.issue_type // "") == "convoy" and .id != "tk-g" and .status != "closed") | .id] | join(" ")' "$STUB_STORE"; }
ids_in() { jq -r '[.[].id] | join(" ")' "$1"; }

echo "# usage refusals do nothing"
reset; anchor
run --target "$ROUTE";                eq "$rc" 1 "no bead -> exit 1"
run tk-g;                             eq "$rc" 1 "no --target -> exit 1"
run tk-g --target "$ROUTE" --bogus;   eq "$rc" 1 "an unknown flag -> exit 1"
run tk-g tk-x --target "$ROUTE";      eq "$rc" 1 "two beads -> exit 1"
eq "$(wc -l < "$STUB_GC_LOG" | tr -d ' ')" "0" "a usage refusal runs no gc"

echo "# a sling that pours no formula is gc sling's own"
reset; anchor
run tk-g --target "$ROUTE" -- --merge mr
eq "$rc" 0 "it exits as gc sling does"
eq "$(cat "$STUB_GC_LOG")" "sling --rig gc-toolkit $ROUTE tk-g --merge mr" "one gc call: the sling, its args in order, and no read of the bead"
eq "$(convoys)" "" "no input convoy is made"
reset; anchor
STUB_SLING_FAIL=1 run tk-g --target "$ROUTE"
eq "$rc" 1 "a failed plain sling exits with gc sling's code"

echo "# a pour onto a bead that is not a convoy is gc sling's own"
reset
store '[{"id":"tk-w","status":"open","assignee":"","title":"w","issue_type":"task","metadata":{"branch":"polecat/tk-w"}}]'; : > "$STUB_DEPS"
run tk-w --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "it exits 0"
eq "$(slung)" "sling --rig gc-toolkit $ROUTE tk-w --on mol-polecat-work" "slung onto the bead itself, which gc sling gives its own input convoy"
eq "$(convoys)" "" "no input convoy is made here"

echo "# a pour onto a convoy that carries no branch is onto its members"
reset
store '[{"id":"tk-c","status":"open","assignee":"","title":"c","issue_type":"convoy","metadata":{"target":"integration/tk-c"}}]'; : > "$STUB_DEPS"
run tk-c --target "$ROUTE" -- --on mol-polecat-work
eq "$(slung)" "sling --rig gc-toolkit $ROUTE tk-c --on mol-polecat-work" "an integration convoy not yet graduated is slung as it stands"
eq "$(convoys)" "tk-c" "no input convoy is made for it"

echo "# a pour onto a closed convoy goes to gc sling, which refuses it"
reset; anchor
jq -c 'map(if .id == "tk-g" then .status = "closed" else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$(slung)" "sling --rig gc-toolkit $ROUTE tk-g --on mol-polecat-work" "a closed anchor is slung as it stands"
eq "$(convoys)" "" "no input convoy is made for a closed anchor"

echo "# a pour onto a convoy that is its own work goes through an input convoy that tracks it alone"
reset; anchor
eq "$(work_bead_of tk-g)" "" "poured as it stands, the run would find no one work bead"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "it exits 0"
icv="$(convoys)"
eq "$icv" "new-5" "one input convoy is made"
eq "$(slung)" "sling --rig gc-toolkit $ROUTE $icv --on mol-polecat-work" "the pour is onto the input convoy, to the target, with its args"
has "$(cat "$STUB_GC_LOG")" "convoy create input convoy for tk-g --rig gc-toolkit --target main --json" "the convoy is made in the anchor's store, with the anchor's target"
has "$(cat "$STUB_GC_LOG")" "convoy add $icv tk-g --rig gc-toolkit" "and then tracks the anchor"
has "$(cat "$STUB_GC_LOG")" "bd --db $TMP/rigs/gc-toolkit/.beads dep list tk-g --direction=up -t tracks --json" "the check for a live run reads the anchor's store"
eq "$(work_bead_of "$icv")" "tk-g" "the run it pours works on the anchor"
eq "$(jq -r --arg id "$icv" '.[] | select(.id == $id) | [.title, .priority, .metadata["gc.synthetic"], .metadata.target] | map(tostring) | join(" | ")' "$STUB_STORE")" \
  "input convoy for tk-g | 1 | true | main" "titled and marked as gc sling makes one, at the anchor's priority and target"
eq "$(meta tk-g gc.execution_routed_to)" "$ROUTE" "the anchor carries the gc.execution_routed_to the pour left on its convoy"
eq "$(meta "$icv" gc.execution_routed_to)" "$ROUTE" "the convoy keeps its own"
has "$out" "slung tk-g to $ROUTE through input convoy $icv" "the run says what it slung"
reset; anchor
run tk-g --target "$ROUTE" -- --on=mol-polecat-work
eq "$(work_bead_of "$(convoys)")" "tk-g" "the --on=<formula> form is a pour too"

echo "# an anchor that names no target gives its input convoy none"
reset; anchor
jq -c 'map(if .id == "tk-g" then (.metadata |= del(.target)) else . end)' "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "it exits 0"
eq "$(meta "$(convoys)" target)" "<absent>" "the input convoy carries no target"

echo "# a live run of the formula on the anchor is not poured again"
# The input convoy an earlier pour made, and its root.
earlier='{"id":"tk-icv0","status":"open","title":"input convoy for tk-g","issue_type":"convoy","metadata":{"gc.synthetic":"true"}}'
live_root='{"id":"tk-r0","status":"in_progress","title":"mol-polecat-work","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"tk-icv0"}}'
reset; anchor ",$earlier,$live_root"
printf 'tk-icv0|tracks|tk-g\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 3 "a live run -> exit 3, as gc sling refuses one"
eq "$(slings)" "0" "nothing is slung"
eq "$(convoys)" "tk-icv0" "no second input convoy is made"
has "$out" "mol-polecat-work already runs on tk-g (root tk-r0, over input convoy tk-icv0)" "the refusal names the live run"
reset; anchor ",$earlier,{\"id\":\"tk-r0\",\"status\":\"closed\",\"title\":\"mol-polecat-work\",\"metadata\":{\"gc.kind\":\"workflow\",\"gc.formula_name\":\"mol-polecat-work\",\"gc.input_convoy_id\":\"tk-icv0\"}}"
printf 'tk-icv0|tracks|tk-g\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "a closed run is no conflict"
eq "$(slings)" "1" "it is poured again"
reset; anchor ",$earlier,{\"id\":\"tk-r0\",\"status\":\"open\",\"title\":\"mol-review\",\"metadata\":{\"gc.kind\":\"workflow\",\"gc.formula_name\":\"mol-review\",\"gc.input_convoy_id\":\"tk-icv0\"}}"
printf 'tk-icv0|tracks|tk-g\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "a live run of another formula is no conflict"
eq "$(slings)" "1" "it is poured"
reset; anchor ',{"id":"tk-own","status":"open","title":"own","issue_type":"convoy","metadata":{}},{"id":"tk-r1","status":"open","title":"mol-polecat-work","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"tk-own"}}'
printf 'tk-own|tracks|tk-g\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "a run over a convoy that is not an input convoy (no gc.synthetic) is no conflict, as gc sling counts only its own"
eq "$(slings)" "1" "it is poured"

echo "# it stops short, slinging nothing, when what it relies on does not hold"
reset; anchor
export STUB_SHOW_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "an unreadable bead -> exit 2"
eq "$(slings)" "0" "nothing slung"
has "$out" "could not read tk-g" "the run names the unreadable bead"
reset; anchor
export STUB_DEP_PARTIAL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "an unreadable set of trackers -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(convoys)" "" "no input convoy is made"
reset; anchor
export STUB_CONVOY_CREATE_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "a refused convoy create -> exit 2"
eq "$(slings)" "0" "nothing slung"
reset; anchor
export STUB_CONVOY_ADD_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "a refused track of the anchor -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(open_convoys)" "" "the convoy it made is closed again"
has "$out" "could not track tk-g" "the run names the refused track"
# The convoy about to be made already tracks another bead, so it reads back
# tracking more than the anchor: the store holds four beads, so it is new-5.
reset; anchor
printf 'new-5|tracks|tk-m1\n' >> "$STUB_DEPS"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "an input convoy that does not read back tracking the anchor alone -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(open_convoys)" "" "the convoy it made is closed again"
has "$out" "not tk-g alone" "the run says what the convoy tracks"
reset; anchor
export STUB_UPDATE_FAIL="new-5"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "a mark that does not land -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(open_convoys)" "" "the convoy it made is closed again"

echo "# a failed sling leaves no input convoy open, unless a root names it"
reset; anchor
export STUB_SLING_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 1 "it exits with gc sling's code"
eq "$(open_convoys)" "" "the convoy no root names is closed"
eq "$(meta tk-g gc.execution_routed_to)" "<absent>" "the anchor is not stamped"
# A root that names the convoy about to be made: the store holds five beads, so
# the convoy is new-6.
reset; anchor ',{"id":"tk-r2","status":"open","title":"mol-polecat-work","metadata":{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"new-6"}}'
export STUB_SLING_FAIL=1
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 1 "it exits with gc sling's code"
eq "$(open_convoys)" "new-6" "a convoy a root names is left open"

echo "# a pour whose stamp did not land leaves the anchor unstamped"
reset; anchor
export STUB_DROP_KEYS="new-5:gc.execution_routed_to"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "the sling exited 0, so it exits 0"
eq "$(meta tk-g gc.execution_routed_to)" "<absent>" "the anchor carries no stamp the pour did not leave"
has "$out" "left no gc.execution_routed_to" "the run says so"

echo "# the input convoy is made in the anchor's store, whichever store the caller runs in"
# From city scope: GC_RIG unset, so a convoy made with no rig would land in the
# city's store, while --db pins the reads to the anchor's.
reset; anchor; others; export STUB_STORE_TABLE="$TABLE"
GC_RIG="" run tk-g --target "$ROUTE" --db "$TMP/rigs/gc-toolkit/.beads" -- --on mol-polecat-work
eq "$rc" 0 "a call from city scope, pinned to the anchor's store, pours"
icv="$(convoys)"
eq "$icv" "tk-5" "its input convoy is made in the anchor's store"
eq "$(ids_in "$TMP/city/.beads/beads.json")" "ct-x" "nothing is made in the city's store"
has "$(cat "$STUB_GC_LOG")" "convoy create input convoy for tk-g --rig gc-toolkit --target main --json" "the create names the anchor's rig"
eq "$(slung)" "sling --rig gc-toolkit $ROUTE $icv --on mol-polecat-work" "and so does the sling"
eq "$(work_bead_of "$icv")" "tk-g" "the run it pours works on the anchor"
eq "$(meta tk-g gc.execution_routed_to)" "$ROUTE" "the anchor carries the stamp the pour left"
# From another rig: GC_RIG names it, with no --db, then with one.
reset; anchor; others; export STUB_STORE_TABLE="$TABLE"
GC_RIG="other" run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "a call from another rig pours"
eq "$(convoys)" "tk-5" "its input convoy is made in the anchor's store, not GC_RIG's"
eq "$(ids_in "$TMP/rigs/other/.beads/beads.json")" "ot-x" "nothing is made in GC_RIG's store"
eq "$(slung)" "sling --rig gc-toolkit $ROUTE tk-5 --on mol-polecat-work" "the sling names the anchor's rig, not GC_RIG"
eq "$(work_bead_of tk-5)" "tk-g" "the run it pours works on the anchor"
reset; anchor; others; export STUB_STORE_TABLE="$TABLE"
GC_RIG="other" run tk-g --target "$ROUTE" --db "$TMP/rigs/gc-toolkit/.beads" -- --on mol-polecat-work
eq "$rc" 0 "a call from another rig pinned to the anchor's store pours"
eq "$(convoys)" "tk-5" "its input convoy is made in the anchor's store"
eq "$(ids_in "$TMP/rigs/other/.beads/beads.json")" "ot-x" "nothing is made in GC_RIG's store"
# The check for a live run reads the anchor's store too, where the earlier
# pour's convoy and root are, not GC_RIG's.
reset; anchor ",$earlier,$live_root"; others; export STUB_STORE_TABLE="$TABLE"
printf 'tk-icv0|tracks|tk-g\n' >> "$STUB_DEPS"
GC_RIG="other" run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 3 "a live run in the anchor's store is found from another rig"
eq "$(slings)" "0" "nothing is slung"
# An anchor in the city's own store, which no --rig names.
reset; others; export STUB_STORE_TABLE="$TABLE"
echo '[{"id":"ct-g","status":"open","assignee":"","title":"g","issue_type":"convoy","priority":2,"metadata":{"branch":"integration/ct-g","target":"main"}},{"id":"ct-m1","status":"closed","title":"m1","metadata":{}}]' > "$TMP/city/.beads/beads.json"
printf 'ct-g|tracks|ct-m1\n' > "$TMP/city/.beads/deps.txt"
run ct-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "an anchor in the city's store pours"
eq "$(jq -r '[.[] | select((.issue_type // "") == "convoy" and .id != "ct-g") | .id] | join(" ")' "$TMP/city/.beads/beads.json")" "ct-3" "its input convoy is made in the city's store"
has "$(cat "$STUB_GC_LOG")" "convoy create input convoy for ct-g --city-scope --target main --json" "made at city scope"
eq "$(slung)" "sling $ROUTE ct-3 --on mol-polecat-work" "the sling names no rig"
eq "$(work_bead_of ct-3)" "ct-g" "the run it pours works on the anchor"
eq "$(ids_in "$TMP/rigs/other/.beads/beads.json")" "ot-x" "nothing is made in a rig's store"

echo "# a store it cannot name is refused, with nothing slung"
reset; anchor
mkdir -p "$TMP/stray/.beads"
run tk-g --target "$ROUTE" --db "$TMP/stray/.beads" -- --on mol-polecat-work
eq "$rc" 2 "a --db no rig keeps its store at -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(convoys)" "" "no input convoy is made"
has "$out" "no rig in gc rig list keeps its store at $TMP/stray/.beads" "the run names the store"
reset
store '[{"id":"zz-g","status":"open","assignee":"","title":"g","issue_type":"convoy","metadata":{"branch":"integration/zz-g"}}]'; : > "$STUB_DEPS"
run zz-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "a bead whose prefix no rig carries -> exit 2"
eq "$(slings)" "0" "nothing slung"
has "$out" "no rig carries the prefix 'zz'" "bead-store.sh's reason reaches the caller"
has "$out" "no store in gc rig list is named for zz-g" "and the run says what it could not name"

echo "# the lock on the anchor is kept under the city root, one file per store and bead"
reset; anchor; rm -f "$LOCKF"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "it exits 0"
if [ -f "$LOCKF" ]; then ok "the lock is a file under the city root the environment names, for the store and the bead"; else bad "no lock file at $LOCKF"; fi
reset; anchor; rm -rf "$TMP/city/.gc"
GC_CITY_PATH="" run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "with no city root in the environment it pours"
if [ -f "$TMP/city/.gc/runtime/packs/gc-toolkit/work-sling/gc-toolkit/tk-g.lock" ]; then
  ok "the lock is kept under the city's row in the rig list"
else
  bad "no lock under the city's row in the rig list"
fi
reset; anchor
jq -c '.rigs |= map(select(.hq != true))' "$TMP/rigs.json" > "$TMP/rigs-nocity.json"
GC_CITY_PATH="" STUB_RIGS_JSON="$TMP/rigs-nocity.json" run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "no city root anywhere -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(convoys)" "" "no input convoy is made"
has "$out" "no city root" "the run names what it lacks"
# Permissions cannot hide flock from `command -v`, which skips a non-executable
# hit and keeps searching PATH, so this PATH carries the stubs and every tool
# the call reaches for, and no flock.
reset; anchor
NOFLOCK="$TMP/noflock"; mkdir -p "$NOFLOCK"
for c in bash dirname tr cat jq grep sed awk head cut mkdir mktemp mv rm wc sleep timeout; do
  p="$(PATH="${PATH#"$BIN":}" command -v "$c" 2>/dev/null)" && ln -sf "$p" "$NOFLOCK/$c"
done
PATH="$BIN:$NOFLOCK" run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "no flock on PATH -> exit 2"
eq "$(slings)" "0" "nothing slung"
has "$out" "flock is not on PATH" "the run names the missing tool"

echo "# a call that finds the lock held waits for it, and gives up slinging nothing"
reset; anchor
rm -f "$TMP/held" "$TMP/let-go"; mkdir -p "${LOCKF%/*}"
( exec 8>>"$LOCKF"; flock -n 8 || exit 1; : > "$TMP/held"; i=0; while [ ! -e "$TMP/let-go" ] && [ "$i" -lt 600 ]; do sleep 0.05; i=$((i + 1)); done ) &
holder=$!
i=0; while [ ! -e "$TMP/held" ] && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
WORK_SLING_LOCK_WAIT_SECS=1 run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 2 "a lock still held after the wait -> exit 2"
eq "$(slings)" "0" "nothing slung"
eq "$(convoys)" "" "no input convoy is made"
hasnt "$(cat "$STUB_GC_LOG")" "dep list" "the check for a live run is not read without the lock"
has "$out" "still held after 1s" "the run says it gave up on the lock"
reset; anchor
( sleep 1; : > "$TMP/let-go" ) &
WORK_SLING_LOCK_WAIT_SECS=30 run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "a lock let go within the wait is taken, and the call pours"
has "$out" "waiting up to 30s" "the run says it waited"
eq "$(slings)" "1" "one pour"
wait "$holder" 2>/dev/null

echo "# no gc call is handed the lock's descriptor"
reset; anchor
export STUB_FD9_LOG="$TMP/fd9.log"; : > "$STUB_FD9_LOG"
run tk-g --target "$ROUTE" -- --on mol-polecat-work
eq "$rc" 0 "it exits 0"
has "$(cat "$STUB_FD9_LOG")" "sling" "the log records the sling"
eq "$(grep -c 'fd9=open' "$STUB_FD9_LOG")" "0" "every gc call runs with fd 9 closed, so nothing it leaves running holds the lock"

echo "# two calls on one anchor, interleaved at the check for a live run, pour once"
reset; anchor
BARRIER="$TMP/barrier"; rm -rf "$BARRIER"; mkdir -p "$BARRIER"
export STUB_BARRIER_DIR="$BARRIER" STUB_SLING_ROOTS=1
arrivals() { find "$BARRIER" -name 'arrived.*' | wc -l | tr -d ' '; }
"$SD/work-sling.sh" tk-g --target "$ROUTE" -- --on mol-polecat-work > "$TMP/first.out" 2>&1 &
first=$!
i=0; while [ "$(arrivals)" -lt 1 ] && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
eq "$(arrivals)" "1" "the first call reaches its check for a live run and is held there"
"$SD/work-sling.sh" tk-g --target "$ROUTE" -- --on mol-polecat-work > "$TMP/second.out" 2>&1 &
second=$!
# The second call is let go only once it is seen either waiting on the lock or
# at its own check, so both orders are decided by what it did, not by a sleep.
i=0
while ! grep -q 'waiting up to' "$TMP/second.out" 2>/dev/null && [ "$(arrivals)" -lt 2 ] && [ "$i" -lt 400 ]; do
  sleep 0.05; i=$((i + 1))
done
has "$(cat "$TMP/second.out")" "another call holds the lock on tk-g" "the second call waits on the first call's lock"
eq "$(arrivals)" "1" "and does not reach its own check while the first holds the lock"
: > "$BARRIER/release"
wait "$first"; first_rc=$?
wait "$second"; second_rc=$?
eq "$first_rc" "0" "the first call pours"
eq "$second_rc" "3" "the second, let in after it, finds the first call's run and refuses"
eq "$(slings)" "1" "one pour"
eq "$(convoys)" "new-5" "one input convoy"
eq "$(jq -r '[.[] | select((.metadata["gc.kind"] // "") == "workflow" and .status != "closed" and .metadata["gc.formula_name"] == "mol-polecat-work")] | length' "$STUB_STORE")" "1" \
  "one live run of the formula works on the anchor"
has "$(cat "$TMP/second.out")" "mol-polecat-work already runs on tk-g" "the refusal names the run the first call made"
reset

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
