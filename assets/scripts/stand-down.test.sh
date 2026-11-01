#!/usr/bin/env bash
# Hermetic test for assets/scripts/stand-down.sh, a person's ruling that work a
# human gate holds will not go on.
#
# The constraint: bd refuses to close a bead an open gate blocks, and answering
# the gate first makes the bead ready, which is what a deferred-dispatch arm waits
# for. So the suite gives the fake store what makes those two true, a `blocks` edge
# that holds a close and keeps a bead out of the ready listing, and runs the real
# stand-down.sh, deferred-dispatch.sh, gc-helm.sh, bead-rehome.sh and
# finalize-gate.sh over it.
#
# What is exercised here:
#   * the two orders a person would try by hand, as controls: a close first is
#     refused, and an answer first lets the next pass sling the work;
#   * the stand-down: the arm goes, then the gate is answered with the ruling, then
#     the bead closes pointed at that gate, and the next pass slings nothing;
#   * no moment to sling: a pass run after every write the stand-down makes, and a
#     pass already running when the stand-down lands between its reads, sling
#     nothing;
#   * the run beneath the bead ends before any gate is answered, and a run that
#     does not end stops the stand-down;
#   * a stop at each write leaves the bead unsent and names it, and a re-run
#     converges on the same close and the first answer;
#   * each refusal writes nothing: an open PR, no gate under the key, another open
#     gate, a gate a person is assigned, another live blocker, an open child, a gate
#     that also holds another open bead, a claim, an unreadable bead, a pointer to
#     other evidence, a review bead;
#   * --successor names other evidence, the ruling is one line headed `ruled:`, a
#     dry run writes nothing, and a closed bead is nothing to do;
#   * the clause a decline message carries is a command that runs.
#
# No live city, Dolt, network, gc or bd: a tmpdir, a `gc` stub over a JSON store, and
# the scripts themselves. specs/tk-utv2kaq/real-store-proof.sh runs the same shapes
# on the real bd by hand, because the test floor refuses it here.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/stand-down.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-stand-down-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }
[ -x "$ROOT/tools/test-floor/gc" ] || { echo "no test floor at tools/test-floor; not running" >&2; exit 2; }

unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/rig/.beads" "$TMP/state"

# --- the gc stub ---------------------------------------------------------------
# $STUB_STORE is an array of beads, each with a `_deps` array of the edges it
# carries ({id, dependency_type}). A live `blocks` target refuses a close and keeps
# the bead out of --ready, as bd does. STUB_FAIL is text: a bd call whose arguments
# carry it writes nothing and exits 1. STUB_LAND_AT is text and STUB_LAND a command:
# the first bd call whose arguments carry it runs the command first, a write that
# lands between two of a script's reads. STUB_PASS_AFTER_WRITES runs a reconcile
# pass after each write the stand-down makes. STUB_SHOW_FAILS_AFTER is text: once a
# bd call carrying it has run, every show fails.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
S="${STUB_STORE:?}"
case "${1:-}" in
  rig) cat "${STUB_RIGS:?}"; exit 0 ;;
  session) printf '{"sessions":[]}\n'; exit 0 ;;
  sling) shift; printf '%s\n' "$*" >> "${STUB_SLING_LOG:?}"; exit 0 ;;
  bd) shift ;;
  *) echo "gc stub: unsupported '$*'" >&2; exit 2 ;;
esac
actor="${BEADS_ACTOR:-}"
while :; do
  case "${1:-}" in
    --db) shift 2 ;;
    --actor) actor="${2:-}"; shift 2 ;;
    *) break ;;
  esac
done
printf 'bd %s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ -n "${STUB_FAIL:-}" ]; then
  case " $* " in *"$STUB_FAIL"*) echo "gc stub: refused: $*" >&2; exit 1 ;; esac
fi
if [ -n "${STUB_LAND_AT:-}" ] && [ ! -e "$S.landed" ]; then
  case " $* " in
    *"$STUB_LAND_AT"*) : > "$S.landed"; env -u STUB_LAND_AT -u STUB_LAND -u STUB_FAIL bash -c "$STUB_LAND" >>"$S.land.log" 2>&1 ;;
  esac
fi
apply() { jq -c "$@" "$S" > "$S.n" && mv "$S.n" "$S"; }
wrote() {
  [ -n "${STUB_PASS_AFTER_WRITES:-}" ] || return 0
  [ -n "${STUB_IN_PASS:-}" ] && return 0
  STUB_IN_PASS=1 "${STUB_DEFERRED:?}" reconcile >>"$S.pass.log" 2>&1
  return 0
}
BLOCKERS='def live_blockers($s): [ (._deps // [])[] | select(.dependency_type == "blocks") | .id as $t
    | $s[] | select(.id == $t and ((.status // "open") != "closed") and ((.status // "open") != "pinned")) | .id ];'
verb="${1:-}"; shift || true
case "$verb" in
  show)
    id="${1:-}"
    if [ -n "${STUB_SHOW_FAILS_AFTER:-}" ] && grep -q -F -- "$STUB_SHOW_FAILS_AFTER" "$STUB_GC_LOG"; then
      echo '{"error":"simulated read failure","schema_version":1}'; exit 1
    fi
    out=$(jq -c --arg id "$id" '. as $s | [ .[] | select(.id == $id) | . as $b
        | .dependencies = [ ($b._deps // [])[] | . as $e | ($s | map(select(.id == $e.id)) | .[0]) as $t | select($t != null)
            | {id: $e.id, dependency_type: $e.dependency_type, issue_type: ($t.issue_type // "task"), status: ($t.status // "open")} ]
        | del(._deps) ]' "$S")
    if [ "$(printf '%s' "$out" | jq 'length')" = 0 ]; then
      echo '{"error":"no issues found matching the provided IDs","schema_version":1}'; exit 1
    fi
    printf '%s\n' "$out" ;;
  list)
    key=""; ready=0; all=0; gates=0; ids=""; st=""; parent=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --db) shift ;;
        --has-metadata-key) shift; key="${1:-}" ;;
        --id) shift; ids="${1:-}" ;;
        --ready) ready=1 ;;
        --all) all=1 ;;
        --include-gates) gates=1 ;;
        --parent) shift; parent="${1:-}" ;;
        --status) shift; st="${1:-}" ;;
        --status=*) st="${1#--status=}" ;;
      esac
      shift || true
    done
    jq -c --arg k "$key" --arg ids "$ids" --argjson ready "$ready" --argjson all "$all" --argjson gates "$gates" \
          --arg st "$st" --arg parent "$parent" "$BLOCKERS"'
      . as $s
      | ($ids | if . == "" then [] else split(",") end) as $want
      | ($st | if . == "" then [] else split(",") end) as $sts
      | [ .[]
          | select($k == "" or ((.metadata // {}) | has($k)))
          | select(($want | length) == 0 or (.id as $i | $want | index($i)))
          | select(if ($sts | length) > 0 then ((.status // "open") as $x | $sts | index($x)) != null else ($all == 1 or (.status // "open") != "closed") end)
          | select($gates == 1 or (.issue_type // "") != "gate")
          | select($parent == "" or (.parent // "") == $parent)
          | select($ready == 0 or ((.status // "open") == "open" and (live_blockers($s) | length) == 0))
          | . as $b
          | .dependencies = [ ($b._deps // [])[] | {issue_id: $b.id, depends_on_id: .id, type: .dependency_type} ]
          | del(._deps) ]' "$S" ;;
  update)
    id="${1:-}"; shift || true
    prog='.'; if_st="-"; if_who="-"; args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --db) shift ;;
        --set-metadata) shift; args+=("${1:-}"); prog="$prog | .metadata[(\$ARGS.positional[$((${#args[@]} - 1))] | split(\"=\")[0])] = (\$ARGS.positional[$((${#args[@]} - 1))] | split(\"=\")[1:] | join(\"=\"))" ;;
        --unset-metadata) shift; args+=("${1:-}"); prog="$prog | (.metadata |= del(.[\$ARGS.positional[$((${#args[@]} - 1))]]))" ;;
        --append-notes) shift; args+=("${1:-}"); prog="$prog | .notes = ((.notes // \"\") + \"\n\" + \$ARGS.positional[$((${#args[@]} - 1))])" ;;
        --status=*) args+=("${1#--status=}"); prog="$prog | .status = \$ARGS.positional[$((${#args[@]} - 1))]" ;;
        --assignee=*) args+=("${1#--assignee=}"); prog="$prog | .assignee = \$ARGS.positional[$((${#args[@]} - 1))]" ;;
        --if-status=*) if_st="${1#--if-status=}" ;;
        --if-assignee=*) if_who="${1#--if-assignee=}" ;;
      esac
      shift || true
    done
    cur=$(jq -r --arg id "$id" '(.[] | select(.id == $id) | [(.status // "open"), (.assignee // "")] | join("\u001f")) // empty' "$S")
    [ -n "$cur" ] || { echo "bd: no issue found matching $id" >&2; exit 1; }
    if { [ "$if_st" != "-" ] && [ "${cur%%$'\037'*}" != "$if_st" ]; } || { [ "$if_who" != "-" ] && [ "${cur#*$'\037'}" != "$if_who" ]; }; then
      echo "Error: precondition failed for $id" >&2; exit 13
    fi
    jq -c --arg id "$id" "map(if .id == \$id then ( $prog ) else . end)" "$S" --args -- ${args[@]+"${args[@]}"} > "$S.n" && mv "$S.n" "$S"
    wrote
    echo "updated $id" ;;
  close)
    id="${1:-}"; shift || true; reason=""
    while [ $# -gt 0 ]; do case "$1" in --reason) shift; reason="${1:-}" ;; esac; shift || true; done
    who=$(jq -r --arg id "$id" '(.[] | select(.id == $id) | .assignee // "") // ""' "$S")
    if [ -n "$who" ] && [ "$who" != "$actor" ]; then
      echo "Error: cannot close $id: assignee is \"$who\", actor is \"$actor\"; reclaim or use --force to override" >&2; exit 1
    fi
    blocked=$(jq -r --arg id "$id" "$BLOCKERS"'. as $s | [ .[] | select(.id == $id) | live_blockers($s)[] ] | join(", ")' "$S")
    if [ -n "$blocked" ]; then
      echo "Error: cannot close blocked issue: $id is blocked by [$blocked] (use --force to override)" >&2; exit 1
    fi
    apply --arg id "$id" --arg r "$reason" 'map(if .id == $id then .status = "closed" | .close_reason = $r else . end)'
    wrote ;;
  gate)
    [ "${1:-}" = resolve ] || { echo "gc stub: unsupported gate ${1:-}" >&2; exit 2; }
    id="${2:-}"; shift 2 || true; reason=""
    while [ $# -gt 0 ]; do case "$1" in --reason) shift; reason="${1:-}" ;; esac; shift || true; done
    # bd keeps the first answer and reports success either way.
    apply --arg id "$id" --arg r "$reason" 'map(if .id == $id and ((.status // "open") != "closed") then .status = "closed" | .close_reason = $r else . end)'
    wrote
    echo "Gate resolved: $id" ;;
  dep)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        id="${1:-}"; shift || true; dir=down; typ=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --db) shift ;;
            --direction=*) dir="${1#--direction=}" ;;
            --direction) shift; dir="${1:-}" ;;
            --type|-t) shift; typ="${1:-}" ;;
            --type=*) typ="${1#--type=}" ;;
          esac
          shift || true
        done
        jq -e --arg id "$id" 'any(.[]; .id == $id)' "$S" >/dev/null \
          || { printf '{"error":"not found: issue %s","schema_version":1}\n' "$id"; exit 1; }
        if [ "$dir" = up ]; then
          jq -c --arg id "$id" --arg t "$typ" '[ .[] | . as $b | ($b._deps // [])[] | select(.id == $id and ($t == "" or .dependency_type == $t))
              | ($b | del(._deps)) + {dependency_type: .dependency_type} ]' "$S"
        else
          jq -c --arg id "$id" --arg t "$typ" '. as $s | [ .[] | select(.id == $id) | (._deps // [])[] | select($t == "" or .dependency_type == $t) | . as $e
              | $s[] | select(.id == $e.id) | del(._deps) + {dependency_type: $e.dependency_type} ]' "$S"
        fi ;;
      remove)
        apply --arg a "${1:-}" --arg b "${2:-}" 'map(if .id == $a then ._deps = ((._deps // []) | map(select(.id != $b))) else . end)'
        wrote ;;
      *) echo "gc stub: unsupported dep $sub" >&2; exit 2 ;;
    esac ;;
  *) echo "gc stub: unsupported bd $verb" >&2; exit 2 ;;
esac
STUB

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/run-cancel" <<'STUB'
printf 'run-cancel %s\n' "$*" >> "${STUB_GC_LOG:?}"
[ -z "${STUB_RUN_CANCEL_FAILS:-}" ] || { echo "run-cancel: simulated failure" >&2; exit 1; }
exit 0
STUB
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/branch-end" <<'STUB'
printf 'branch-end %s\n' "$*" >> "${STUB_GC_LOG:?}"
exit 0
STUB
chmod +x "$BIN/gc" "$BIN/run-cancel" "$BIN/branch-end"
printf '{"rigs":[{"name":"tkrig","path":"%s","prefix":"tk"}]}\n' "$TMP/rig" > "$TMP/rigs.json"

export PATH="$BIN:$ROOT/tools/test-floor:$PATH"
export STUB_STORE="$TMP/beads.json" STUB_RIGS="$TMP/rigs.json" STUB_GC_LOG="$TMP/gc.log" STUB_SLING_LOG="$TMP/sling.log"
export STUB_DEFERRED="$HERE/deferred-dispatch.sh"
export BEADS_ACTOR=a-person GC_RUN_CANCEL_TOOL="$BIN/run-cancel" GC_BRANCH_END_TOOL="$BIN/branch-end"
export GC_RUN_LIB="$HERE/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$TMP/runs.json"
export DEFERRED_DISPATCH_STATE_DIR="$TMP/state" DEFERRED_DISPATCH_PASS_BUDGET_SECS=0

# A work bead as a declined run leaves it: open, unassigned, unrouted, armed to
# re-sling, with a `blocks` edge onto an open human gate under polecat-x.
fresh() {
  cat > "$STUB_STORE" <<'JSON'
[{"id":"tk-w","status":"open","assignee":"","issue_type":"task","notes":"","title":"the work",
  "metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]",
              "gc.dispatch_when_ready_reason":"waits on the ruling","resling_target":"rig/pool"},
  "_deps":[{"id":"tk-g","dependency_type":"blocks"}]},
 {"id":"tk-g","status":"open","assignee":"","issue_type":"gate","await_type":"human","await_id":"polecat-x",
  "title":"does this go on?","notes":"","metadata":{},"created_at":"2026-11-01T00:00:00Z"},
 {"id":"tk-conv","status":"open","assignee":"human","issue_type":"task","title":"a conversation","notes":"","metadata":{}}]
JSON
  rm -f "$STUB_STORE.landed" "$STUB_STORE.land.log" "$STUB_STORE.pass.log"
  : > "$STUB_GC_LOG"; : > "$STUB_SLING_LOG"
  printf '[]\n' > "$RUN_LIB_STUB_RUNS"
}
patch()  { jq -c "$1" "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"; }
field()  { jq -r --arg id "$1" --arg f "$2" '.[] | select(.id == $id) | .[$f] // ""' "$STUB_STORE"; }
meta()   { jq -r --arg id "$1" --arg k "$2" '.[] | select(.id == $id) | .metadata[$k] // "<absent>"' "$STUB_STORE"; }
slings() { wc -l < "$STUB_SLING_LOG" | tr -d ' '; }
run()    { OUT=$("$SCRIPT" "$@" 2>&1); RC=$?; }
pass()   { PASS_OUT=$("$HERE/deferred-dispatch.sh" reconcile 2>&1); PASS_RC=$?; }
line_of() { grep -n -F -- "$1" "$STUB_GC_LOG" | head -1 | cut -d: -f1; }
writes() { grep -c -E '^bd (update|close|gate resolve|dep remove)' "$STUB_GC_LOG" || true; }
refused() { # <label> <args...>: exit 1, the store as it was, nothing sent
  local label="$1"; shift
  local before="$TMP/before.json"
  cp "$STUB_STORE" "$before"
  run "$@"
  eq "$RC" 1 "$label: exit 1"
  if cmp -s "$before" "$STUB_STORE"; then ok "$label: nothing was written"; else bad "$label: the store changed"; fi
  has "$OUT" "Nothing was written." "$label: it says so"
  eq "$(writes)" 0 "$label: no write was tried"
}

# --- the orders by hand ---------------------------------------------------------
fresh
OUT=$(gc bd close tk-w --reason "standing down" 2>&1); RC=$?
eq "$RC" 1 "control: closing the bead first is refused"
has "$OUT" "cannot close blocked issue" "control: …because the open gate blocks it"
eq "$(field tk-w status)" open "control: …and it stays open"
fresh
gc bd gate resolve tk-g --reason "ruled: do not go on" >/dev/null 2>&1
pass
eq "$(slings)" 1 "control: answering the gate first lets the next pass sling the work"

# --- the stand-down -------------------------------------------------------------
fresh
patch 'map(if .id == "tk-w" then .metadata += {"gc.execution_routed_to":"rig/pool","gc.routed_to":"rig/pool","gc.session_id":"s-1","gc.session_name":"n-1"} else . end)'
run tk-w --key polecat-x --ruling "the branch is wrong and nobody needs this"
eq "$RC" 0 "a stand-down exits 0"
eq "$(field tk-w status)" closed "the work closes"
has "$(field tk-w close_reason)" "not needed, per tk-g in rig:tkrig" "…as not needed, per the gate"
has "$(field tk-w close_reason)" "the branch is wrong and nobody needs this" "…with the ruling in its reason"
eq "$(meta tk-w gc.superseded_by)" tk-g "…pointed at the gate"
eq "$(meta tk-w gc.work_outcome)" no-op "…recording that nothing shipped"
eq "$(field tk-g status)" closed "the gate closes"
eq "$(field tk-g close_reason)" "ruled: the branch is wrong and nobody needs this" "…with the ruling as its answer"
for k in gc.dispatch_when_ready gc.dispatch_when_ready_args gc.dispatch_when_ready_reason; do
  eq "$(meta tk-w "$k")" "<absent>" "the arm is gone: $k"
done
for k in gc.routed_to gc.session_id gc.session_name gc.execution_routed_to; do
  case "$(meta tk-w "$k")" in ""|"<absent>") ok "the dispatch path is gone: $k" ;; *) bad "the dispatch path is gone: $k (reads $(meta tk-w "$k"))" ;; esac
done
DISARM=$(line_of "--unset-metadata gc.dispatch_when_ready ")
ANSWER=$(line_of "gate resolve tk-g")
CLOSE=$(line_of "close tk-w")
if [ -n "$DISARM" ] && [ -n "$ANSWER" ] && [ -n "$CLOSE" ] && [ "$DISARM" -lt "$ANSWER" ] && [ "$ANSWER" -lt "$CLOSE" ]; then
  ok "the arm goes first, then the answer, then the close"
else
  bad "the arm goes first, then the answer, then the close (lines ${DISARM:-none}, ${ANSWER:-none}, ${CLOSE:-none})"
fi
pass
eq "$PASS_RC" 0 "the next pass is clean"
eq "$(slings)" 0 "…and slings nothing"
WRITES_BEFORE=$(writes)
run tk-w --key polecat-x --ruling "again"
eq "$RC" 0 "a second run exits 0"
has "$OUT" "already closed" "…and says there is nothing to do"
eq "$(writes)" "$WRITES_BEFORE" "…and writes nothing"
eq "$(field tk-g close_reason)" "ruled: the branch is wrong and nobody needs this" "…and the first answer stands"

fresh
STUB_PASS_AFTER_WRITES=1 run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "with a pass after every write, the stand-down still lands"
eq "$(slings)" 0 "…and none of those passes slings the work"
[ -s "$STUB_STORE.pass.log" ] && ok "…and the passes did run" || bad "…and the passes did run"

fresh
STUB_LAND_AT="--ready" STUB_LAND="$SCRIPT tk-w --key polecat-x --ruling 'stop while the pass runs'" pass
eq "$(field tk-w status)" closed "a stand-down that lands between a pass's listing and its hold read closes the work"
eq "$(slings)" 0 "…and that pass does not sling it"
has "$PASS_OUT" "withdrawn tk-w" "…and says why"

# --- the run beneath the bead ----------------------------------------------------
fresh
printf '[{"root":"r-1","bead":"tk-w","live":true,"convoy":"c-1"}]\n' > "$RUN_LIB_STUB_RUNS"
run tk-w --key polecat-x --ruling "stop the run"
eq "$RC" 0 "a bead with a live run stands down"
CANCEL=$(line_of "run-cancel --root r-1")
ANSWER=$(line_of "gate resolve tk-g")
if [ -n "$CANCEL" ] && [ -n "$ANSWER" ] && [ "$CANCEL" -lt "$ANSWER" ]; then
  ok "…and its run ends before the gate is answered"
else
  bad "…and its run ends before the gate is answered (lines ${CANCEL:-none}, ${ANSWER:-none})"
fi
fresh
printf '[{"root":"r-1","bead":"tk-w","live":true,"convoy":"c-1"}]\n' > "$RUN_LIB_STUB_RUNS"
STUB_RUN_CANCEL_FAILS=1 run tk-w --key polecat-x --ruling "stop the run"
eq "$RC" 1 "a run that does not end stops the stand-down"
eq "$(field tk-g status)" open "…with the gate unanswered"
eq "$(field tk-w status)" open "…and the work open"

# --- a stop at each write, then a re-run ------------------------------------------
stop_case() { # <label> <text the stub refuses> <gate status after> <arm after>
  fresh
  STUB_FAIL="$2" run tk-w --key polecat-x --ruling "stop"
  eq "$RC" 1 "stop at $1: exit 1"
  has "$OUT" "Re-run this command" "stop at $1: it names the way on"
  eq "$(field tk-g status)" "$3" "stop at $1: the gate reads $3"
  case "$4" in
    armed) eq "$(meta tk-w gc.dispatch_when_ready)" rig/pool "stop at $1: the arm stands" ;;
    gone)  eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "stop at $1: the arm is gone" ;;
  esac
  [ "$4" = armed ] || { pass; eq "$(slings)" 0 "stop at $1: a pass sends nothing"; }
  run tk-w --key polecat-x --ruling "stop"
  eq "$RC" 0 "stop at $1: a re-run exits 0"
  eq "$(field tk-w status)" closed "stop at $1: a re-run closes the work"
  eq "$(field tk-g close_reason)" "ruled: stop" "stop at $1: the gate carries the ruling"
  eq "$(meta tk-w gc.superseded_by)" tk-g "stop at $1: the pointer names the gate"
  eq "$(slings)" 0 "stop at $1: nothing was sent"
}
fresh
STUB_SHOW_FAILS_AFTER="--unset-metadata gc.dispatch_when_ready " run tk-w --key polecat-x --ruling "stop"
eq "$RC" 1 "an arm whose removal does not read back stops the stand-down"
eq "$(field tk-g status)" open "…with the gate unanswered"
eq "$(field tk-w status)" open "…and the work open"
stop_case "the disarm" "--unset-metadata gc.dispatch_when_ready " open armed
stop_case "the release" "gc.takeaway=" open gone
stop_case "the answer" "gate resolve" open gone
stop_case "the close" "close tk-w" closed gone

# --- refusals --------------------------------------------------------------------
fresh; patch 'map(if .id == "tk-w" then .metadata.merge_result = "pull_request" else . end)'
refused "an open PR" tk-w --key polecat-x --ruling "x"
has "$OUT" "pr-dispose.sh" "an open PR: it names the writer that retires one"
fresh
refused "no gate under the key" tk-w --key another-key --ruling "x"
has "$OUT" "no human gate under another-key" "no gate under the key: it says so"
fresh; patch '. + [{"id":"tk-g2","status":"open","assignee":"","issue_type":"gate","await_type":"human","await_id":"another-question","title":"another question","metadata":{}}]
  | map(if .id == "tk-w" then ._deps += [{"id":"tk-g2","dependency_type":"blocks"}] else . end)'
refused "another open gate" tk-w --key polecat-x --ruling "x"
has "$OUT" "tk-g2" "another open gate: it names the gate"
fresh; patch 'map(if .id == "tk-g" then .assignee = "a-person-owes-it" else . end)'
refused "a gate a person is assigned" tk-w --key polecat-x --ruling "x"
fresh; patch '. + [{"id":"tk-p","status":"open","assignee":"","issue_type":"task","title":"prerequisite","metadata":{}}]
  | map(if .id == "tk-w" then ._deps += [{"id":"tk-p","dependency_type":"blocks"}] else . end)'
refused "another live blocker" tk-w --key polecat-x --ruling "x"
has "$OUT" "tk-p" "another live blocker: it names it"
fresh; patch '. + [{"id":"tk-c","status":"open","assignee":"","issue_type":"task","title":"child","parent":"tk-w","metadata":{}}]'
refused "an open child" tk-w --key polecat-x --ruling "x"
has "$OUT" "tk-c" "an open child: it names it"
fresh; patch '. + [{"id":"tk-o","status":"open","assignee":"","issue_type":"task","title":"another bead","metadata":{},"_deps":[{"id":"tk-g","dependency_type":"blocks"}]}]'
refused "a gate that also holds another open bead" tk-w --key polecat-x --ruling "x"
has "$OUT" "also holds tk-o" "a gate that also holds another open bead: it names it"
fresh; patch 'map(if .id == "tk-w" then .assignee = "someone" | .status = "in_progress" else . end)'
refused "a claim" tk-w --key polecat-x --ruling "x"
has "$OUT" "someone" "a claim: it names the holder"
fresh; patch 'map(if .id == "tk-w" then .metadata["gc.superseded_by"] = "tk-conv" | .metadata["gc.superseded_by_store"] = "rig:tkrig" else . end)'
refused "a pointer to other evidence" tk-w --key polecat-x --ruling "x" --successor tk-g
fresh; patch 'map(if .id == "tk-w" then .metadata.task_kind = "review" else . end)'
refused "a review bead" tk-w --key polecat-x --ruling "x"
fresh
refused "an unreadable bead" tk-absent --key polecat-x --ruling "x"
fresh
cp "$STUB_STORE" "$TMP/before.json"
STUB_FAIL="--direction=up" run tk-w --key polecat-x --ruling "x"
eq "$RC" 1 "what the gate holds does not read: exit 1"
cmp -s "$TMP/before.json" "$STUB_STORE" && ok "what the gate holds does not read: nothing was written" || bad "what the gate holds does not read: the store changed"
fresh; patch '. + [{"id":"tk-o","status":"closed","assignee":"","issue_type":"task","title":"landed","metadata":{},"_deps":[{"id":"tk-g","dependency_type":"blocks"}]}]'
run tk-w --key polecat-x --ruling "x"
eq "$RC" 0 "a gate that holds only a closed bead besides this one is no refusal"

# --- evidence, wording, dry run ---------------------------------------------------
fresh
run tk-w --key polecat-x --ruling "the operator ruled this out" --successor tk-conv
eq "$RC" 0 "--successor names other evidence"
eq "$(meta tk-w gc.superseded_by)" tk-conv "…and the pointer names it"
eq "$(field tk-g close_reason)" "ruled: the operator ruled this out" "…and the gate still carries the ruling"
fresh
refused "a successor that does not exist" tk-w --key polecat-x --ruling "x" --successor tk-nobody

fresh
STUB_FAIL="close tk-w" run tk-w --key polecat-x --ruling "stop" --successor tk-conv
eq "$RC" 1 "a close refused after --successor stamped its pointer stops"
run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "a re-run with no --successor closes"
eq "$(meta tk-w gc.superseded_by)" tk-conv "…keeping the evidence the first run named"

fresh; patch '. + [{"id":"tk-g2","status":"open","assignee":"","issue_type":"gate","await_type":"human","await_id":"polecat-x","title":"a twin","metadata":{},"created_at":"2026-11-01T00:00:01Z"}]
  | map(if .id == "tk-w" then ._deps += [{"id":"tk-g2","dependency_type":"blocks"}] else . end)'
run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "twin gates under the key do not stop a stand-down"
eq "$(field tk-g close_reason)|$(field tk-g2 close_reason)" "ruled: stop|ruled: stop" "…and each carries the ruling"
eq "$(meta tk-w gc.superseded_by)" tk-g "…and the pointer names the first"

fresh; patch 'map(if .id == "tk-g" then .status = "closed" | .close_reason = "ruled: an earlier answer" else . end)
  | map(if .id == "tk-w" then .metadata |= del(.["gc.dispatch_when_ready"]) else . end)'
run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "a gate already answered still names the evidence"
eq "$(meta tk-w gc.superseded_by)" tk-g "…in the pointer"
eq "$(field tk-g close_reason)" "ruled: an earlier answer" "…and its answer stands"

fresh
STUB_LAND_AT="gate resolve" STUB_LAND="jq -c 'map(if .id == \"tk-g\" then .status = \"closed\" | .close_reason = \"ruled: go on\" else . end)' '$STUB_STORE' > '$STUB_STORE.x' && mv '$STUB_STORE.x' '$STUB_STORE'" run tk-w --key polecat-x --ruling "stop"
eq "$RC" 0 "another answer that reaches the gate first does not stop the close"
has "$OUT" "another answer reached gate tk-g first" "…and it is reported"
eq "$(field tk-g close_reason)" "ruled: go on" "…and stands"

fresh
run tk-w --key polecat-x --ruling "ruled: already headed"
eq "$(field tk-g close_reason)" "ruled: already headed" "a ruling already headed ruled: is not headed twice"
fresh
run tk-w --key polecat-x --ruling "over
two lines"
eq "$(field tk-g close_reason)" "ruled: over two lines" "a ruling is one line"

fresh; patch 'map(if .id == "tk-w" then .metadata = {} else . end)'
run tk-w --key polecat-x --ruling "no arm here"
eq "$RC" 0 "a bead with no arm stands down"
eq "$(line_of "--unset-metadata gc.dispatch_when_ready ")" "" "…with no disarm to run"
fresh; patch 'map(if .id == "tk-w" then .metadata = {"gc.notify_when_ready":"an-agent"} else . end)'
run tk-w --key polecat-x --ruling "no notice either"
eq "$(meta tk-w gc.notify_when_ready)" "<absent>" "a notice owed goes with the arm"
fresh; patch 'map(if .id == "tk-w" then .metadata.merge_result = "held" | .metadata["gc.routed_to"] = "human" else . end)'
run tk-w --key polecat-x --ruling "from a held sitting"
eq "$RC" 0 "a subject a sitting's hold left at held stands down, for the sign-off to release"
eq "$(field tk-w status)" closed "…and closes"
eq "$(meta tk-w gc.routed_to)" "" "…with its person route cleared"
fresh; patch 'map(if .id == "tk-w" then .metadata.branch = "polecat/tk-w" else . end)'
run tk-w --key polecat-x --ruling "drop the branch"
has "$(cat "$STUB_GC_LOG")" "branch-end --rig tkrig --branch polecat/tk-w" "the bead's branch ends with the close"

fresh
cp "$STUB_STORE" "$TMP/before.json"
run tk-w --key polecat-x --ruling "x" --dry-run
eq "$RC" 0 "a dry run exits 0"
has "$OUT" "DRY RUN" "…and says so"
has "$OUT" "tk-g" "…and names the evidence"
cmp -s "$TMP/before.json" "$STUB_STORE" && ok "…and writes nothing" || bad "…and writes nothing"

# --- usage -------------------------------------------------------------------------
fresh
for args in "tk-w --ruling x" "tk-w --key k" "--key k --ruling x" "tk-w --key k --ruling x --what" "tk-w --key --ruling x" "tk-w --key k --ruling x extra"; do
  # shellcheck disable=SC2086  # each row is the argv it spells
  run $args
  eq "$RC" 2 "usage: '$args'"
done
run 'tk w' --key k --ruling x
eq "$RC" 2 "usage: an id with a space is refused"
eq "$(writes)" 0 "usage errors write nothing"
if grep -q -e '--set-metadata' "$SCRIPT"; then bad "the script writes a metadata key of its own"; else ok "the script writes no metadata key of its own"; fi

# --- the clause a decline message carries ------------------------------------------
# Each message names the command with its own key, and that text runs as written.
CLAUSE=$(grep -o -e 'run \$SCRIPTS/stand-down\.sh \$WORK_BEAD_ID --key polecat-branch-divergence --ruling '"'"'<why>'"'" "$ROOT/formulas/mol-polecat-work.toml" | head -1)
[ -n "$CLAUSE" ] && ok "the formula carries the clause" || bad "the formula carries the clause"
fresh; patch 'map(if .id == "tk-g" then .await_id = "polecat-branch-divergence" else . end)'
OUT=$(SCRIPTS="$HERE" WORK_BEAD_ID=tk-w bash -c "${CLAUSE#run }" 2>&1); RC=$?
eq "$RC" 0 "the clause runs as written"
eq "$(field tk-w status)" closed "…and closes the work"
eq "$(field tk-g close_reason)" "ruled: <why>" "…and answers the gate"

echo
echo "stand-down: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
