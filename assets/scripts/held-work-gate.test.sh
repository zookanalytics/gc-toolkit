#!/usr/bin/env bash
# Hermetic test for assets/scripts/held-work-gate.sh, the gate a formula runs
# before it starts work on a subject, and for the formula blocks that call it.
#
# Covers:
#   (FREE)    a bead nothing holds goes on with nothing written, and so does one
#             whose blocker closed, and one whose epic waits only on a demand
#             gate, which deferred dispatch does not count as a hold either
#   (HELD)    a blocker of the bead's own, a park on its epic, a park two levels
#             up, and a demand gate on the bead itself each decline the run:
#             the route keys cleared with the pool recorded, a re-sling armed
#             --on the formula to the pool the pour ran on, a note naming the
#             hold, the run of the named step cancelled, then the drain
#   (FLIGHT)  a bead in flight under a parked epic goes on; one in flight with an
#             open blocker of its own is declined, as submit-and-exit meets it
#   (UNREAD)  a read that fails, and a blocker of its own the store does not
#             return, hold the bead; with no pool to arm to, a visit carries it
#   (CLOSED)  a closed bead's run is cancelled with no re-sling and no visit
#   (FAIL)    an arm that fails falls back to a visit, filed with escalate.sh's
#             verdict window off; with neither, nothing is cancelled or
#             drained; a cancel that fails is not drained
#   (WINDOW)  a person closed the bead's last visit moot an hour ago: the real
#             escalate.sh files nothing with its verdict window on, and the
#             gate's fallback files a fresh visit that is open when the run is
#             cancelled
#   (ARGS)    usage errors exit 2; each --sling-arg follows --on <formula> in
#             the arm and in the visit; --dry-run writes nothing
#   (WIRING)  each formula block calls the gate with its bead, formula, step and
#             args, and stops its step when the gate does not exit 0
#   (ROUND)   park, sling, unpark, built: the real deferred-dispatch.sh holds the
#             re-sling while the park stands, slings it once after the release,
#             and the cancelled root does not refuse that pour. A root left live
#             instead is refused, the way gascity refuses a second pour, which
#             is the control that shows the case discriminates.
#
# No live city, Dolt, network, gc or bd: only jq, stubs, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/held-work-gate.sh"
DD="$HERE/deferred-dispatch.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-held-work-gate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -x "$SUT" ] && ok "held-work-gate.sh is executable" || bad "held-work-gate.sh is executable"

# --- stubs -------------------------------------------------------------------
# $TMP/store.json is the store: an array of beads whose own edges sit in `_deps`
# as {id, dependency_type}. bd's readiness is computed the way bd computes it:
# an open bead with no open blocker on it or on any parent-child ancestor, a
# demand gate included, since bd does not tell one apart.
BIN="$TMP/bin"; mkdir -p "$BIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/bd" <<'STUB'
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
set -u
STORE="${STUB_STORE:?}"
while [ "${1:-}" = "--db" ]; do shift 2 || shift || true; done
READY_JQ='
  def live: (.status // "") as $s | $s != "closed" and $s != "pinned";
  def blocked($s; $seen):
    (._deps // []) as $d
    | ([ $d[] | select(.dependency_type == "blocks") | .id as $t | $s[] | select(.id == $t) | select(live) ] | length > 0)
      or ([ $d[] | select(.dependency_type == "parent-child") | .id as $p
            | select(($seen | index($p)) == null)
            | $s[] | select(.id == $p) | select(live) | blocked($s; $seen + [$p]) ] | any);
  def ready($s): (.status // "") == "open" and (blocked($s; [.id]) | not);'
case "${1:-}" in
  list)
    shift
    [ -z "${STUB_LIST_FAIL:-}" ] || { echo "bd: simulated listing failure" >&2; exit 1; }
    key=""; ready=0; all=0; gates=0; id=""; st=""; fields="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --has-metadata-key) shift; key="${1:-}" ;;
        --metadata-field) shift; fields="$(jq -c --arg kv "${1:-}" '. + {($kv | split("=")[0]): ($kv | split("=")[1:] | join("="))}' <<<"$fields")" ;;
        --status=*) st="${1#--status=}" ;;
        --id) shift; id="${1:-}" ;;
        --ready) ready=1 ;;
        --all) all=1 ;;
        --include-gates) gates=1 ;;
        *) : ;;
      esac
      shift || true
    done
    # A by-id read naming $STUB_LIST_FAIL_ID fails on its own, as one read of a
    # walk can while the others answer.
    case ",$id," in *",${STUB_LIST_FAIL_ID:-<none>},"*) echo "bd: simulated read failure" >&2; exit 1 ;; esac
    jq -c --arg k "$key" --arg id "$id" --argjson ready "$ready" --argjson all "$all" --argjson gates "$gates" \
        --arg st "$st" --argjson fields "$fields" "$READY_JQ"'
      . as $s
      | ($id | if . == "" then [] else split(",") end) as $ids
      | [ .[]
        | select($k == "" or ((.metadata // {}) | has($k)))
        | select(($ids | length) == 0 or (.id as $i | $ids | index($i)))
        | . as $b | select(all($fields | to_entries[]; (($b.metadata // {})[.key] // "") == .value))
        | if $st != "" then select(.status as $x | $st | split(",") | index($x))
          else select($all == 1 or .status != "closed") end
        | select($ready == 0 or ready($s))
        | select($gates == 1 or ($ids | length) > 0 or (.issue_type // "") != "gate")
        | . as $b
        | .dependencies = [ ($b._deps // [])[] | {issue_id: $b.id, depends_on_id: .id, type: .dependency_type} ]
        | del(._deps) ]' "$STORE"
    ;;
  show)
    out="$(jq -c --arg id "${2:-}" '. as $s | [ .[] | select(.id == $id)
      | .dependencies = [ (._deps // [])[] | .id as $t | {id: .id, dependency_type,
                          status: (([ $s[] | select(.id == $t) | .status ] | first) // "")} ]
      | del(._deps) ]' "$STORE")"
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      echo '{"error":"no issues found matching the provided IDs","schema_version":1}'
    else
      printf '%s\n' "$out"
    fi
    ;;
  update)
    shift
    [ -z "${STUB_UPDATE_FAIL:-}" ] || { echo "bd: simulated update failure" >&2; exit 1; }
    id="${1:-}"; shift || true
    sets=(); unsets=(); note=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; sets+=("${1:-}") ;;
        --unset-metadata) shift; unsets+=("${1:-}") ;;
        --append-notes) shift; note="${1:-}" ;;
        *) : ;;
      esac
      shift || true
    done
    for kv in ${sets[@]+"${sets[@]}"}; do
      jq -c --arg id "$id" --arg k "${kv%%=*}" --arg v "${kv#*=}" \
        'map(if .id == $id then .metadata = ((.metadata // {}) + {($k): $v}) else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
    done
    for k in ${unsets[@]+"${unsets[@]}"}; do
      jq -c --arg id "$id" --arg k "$k" 'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
    done
    if [ -n "$note" ]; then
      jq -c --arg id "$id" --arg n "$note" \
        'map(if .id == $id then .notes = ((.notes // "") + (if (.notes // "") == "" then "" else "\n" end) + $n) else . end)' \
        "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
    fi
    echo "updated $id"
    ;;
  dep)
    shift
    case "${1:-}" in
      list)
        jq -c --arg id "${2:-}" '. as $s | [ .[] | select(.id == $id) ] | .[0] as $b
          | [ ($b._deps // [])[] | select(.id as $t | $s | any(.[]; .id == $t)) ]' "$STORE" ;;
      add)
        t="blocks"; for a in "$@"; do case "$a" in --type=*) t="${a#--type=}" ;; esac; done
        jq -c --arg a "${2:-}" --arg b "${3:-}" --arg t "$t" \
          'map(if .id == $a then ._deps = ((._deps // []) + [{id: $b, dependency_type: $t}]) else . end)' \
          "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE" ;;
      *) echo "bd stub: unsupported 'dep ${1:-}'" >&2; exit 2 ;;
    esac
    ;;
  create)
    # An open task from --title and --metadata, answered by id, so the real
    # escalate.sh can file a visit into the store.
    shift; title=""; m="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="${1:-}" ;;
        --metadata) shift; m="${1:-}" ;;
        *) : ;;
      esac
      shift || true
    done
    new="tk-v$(jq 'length' "$STORE")"
    jq -c --arg id "$new" --arg t "$title" --argjson m "$m" \
      '. + [{id: $id, status: "open", issue_type: "task", title: $t, metadata: $m}]' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
    printf '{"id":"%s"}\n' "$new"
    ;;
  *) echo "bd stub: unsupported '${1:-}'" >&2; exit 2 ;;
esac
STUB

# gc: bd reaches the store stub; drain-ack and each update are logged in order;
# sling records its argv and pours a root, unless a root poured for the bead is
# still live, which it refuses with exit 3 the way gascity refuses a second
# pour over a bead that already has a live workflow.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
case "${1:-}" in
  bd)
    shift
    if [ "${1:-}" = update ]; then
      printf 'UPDATE\n' >> "${FAKE_LOG:-/dev/null}"
      printf '%s\n' "$*" >> "${FAKE_UPDATE:-/dev/null}"
    fi
    VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  runtime)
    [ "${2:-}" = drain-ack ] || { echo "gc stub: unsupported 'runtime ${2:-}'" >&2; exit 2; }
    printf 'DRAIN\n' >> "${FAKE_LOG:-/dev/null}"; exit 0 ;;
  sling)
    shift
    printf '%s\n' "$*" >> "${STUB_SLING_LOG:?}"
    bead="${2:-}"
    if jq -e --arg b "$bead" 'any(.[]; (.metadata["test.root_for"] // "") == $b and .status != "closed")' "${STUB_STORE:?}" >/dev/null; then
      echo "gc sling: bead $bead already has attached workflow" >&2; exit 3
    fi
    n="$(jq 'length' "$STUB_STORE")"
    jq -c --arg b "$bead" --arg r "tk-root$n" '. + [{id: $r, status: "in_progress", issue_type: "task", title: "mol-polecat-work",
        metadata: {"gc.kind": "workflow", "test.root_for": $b}}]' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
    exit 0 ;;
esac
echo "gc stub: unsupported '${1:-}'" >&2; exit 2
STUB

# The sibling scripts the gate calls. Each logs its verb in order and its argv
# where an assertion reads it, and exits as the case says. run-cancel closes the
# live root poured for $STUB_ROOT_OF, as gascity's run cancel closes the root,
# unless the case models a root the cancel leaves live. It also records the
# visits open when it ran. escalate.sh records the verdict window it was given.
cat > "$BIN/run-cancel.sh" <<'CANCEL'
#!/usr/bin/env bash
printf 'CANCEL\n' >> "${FAKE_LOG:?}"
printf '%s\n' "$*" >> "${FAKE_CANCEL:-/dev/null}"
jq -r '[ .[] | select((.metadata.task_kind // "") == "visit" and .status != "closed") | .id ] | join(" ")' \
  "$STUB_STORE" >> "${FAKE_CANCEL_SAW:-/dev/null}"
if [ -n "${STUB_ROOT_OF:-}" ] && [ -z "${FAKE_CANCEL_LEAVES_ROOT:-}" ]; then
  jq -c --arg b "$STUB_ROOT_OF" 'map(if (.metadata["test.root_for"] // "") == $b then .status = "closed" else . end)' \
    "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
fi
exit "${FAKE_CANCEL_RC:-0}"
CANCEL
cat > "$BIN/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf 'ESCALATE\n' >> "${FAKE_LOG:?}"
printf '%s\n' "$*" >> "${FAKE_ESC:-/dev/null}"
printf 'window=%s\n' "${GC_ESCALATE_VERDICT_WINDOW-unset}" >> "${FAKE_ESC_ENV:-/dev/null}"
exit "${FAKE_ESC_RC:-0}"
ESC
cat > "$BIN/dd-stub.sh" <<'ARM'
#!/usr/bin/env bash
printf 'ARM\n' >> "${FAKE_LOG:?}"
printf '%s\n' "$*" >> "${FAKE_ARM:-/dev/null}"
[ "${FAKE_ARM_RC:-0}" = 0 ] && echo "deferred-dispatch: armed ${2:-}"
exit "${FAKE_ARM_RC:-0}"
ARM
chmod +x "$BIN/bd" "$BIN/gc" "$BIN/run-cancel.sh" "$BIN/escalate.sh" "$BIN/dd-stub.sh"

export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/store.json" STUB_SLING_LOG="$TMP/sling.log"
export FAKE_LOG="$TMP/log" FAKE_UPDATE="$TMP/update" FAKE_CANCEL="$TMP/cancel" FAKE_CANCEL_SAW="$TMP/cancel-saw" FAKE_ESC="$TMP/esc" FAKE_ESC_ENV="$TMP/esc-env" FAKE_ARM="$TMP/arm"
export GC_RUN_CANCEL_TOOL="$BIN/run-cancel.sh" GC_ESCALATE_TOOL="$BIN/escalate.sh" GC_DEFERRED_DISPATCH_TOOL="$BIN/dd-stub.sh"
export BEADS_ACTOR="test-actor"
unset GC_AGENT GC_RIG GC_RIG_ROOT GC_PACK_DIR GC_CITY_PATH STUB_ROOT_OF 2>/dev/null || true

store() { printf '%s' "$1" > "$STUB_STORE"; }
meta()  { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
status_of() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .status) // "<absent>"' "$STUB_STORE"; }
notes() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STUB_STORE"; }
# gate <args...>: run the gate; RC, OUT and SEQ (the ordered verb log) after.
gate() {
  : > "$FAKE_LOG"; : > "$FAKE_UPDATE"; : > "$FAKE_CANCEL"; : > "$FAKE_CANCEL_SAW"; : > "$FAKE_ESC"; : > "$FAKE_ESC_ENV"; : > "$FAKE_ARM"
  RC=0; OUT="$("$SUT" "$@" 2>&1)" || RC=$?
  SEQ="$(tr '\n' ';' < "$FAKE_LOG")"
}
# lc <bead>: the gate as mol-polecat-work's load-context calls it.
lc() { gate --bead "$1" --formula mol-polecat-work --step mol-polecat-work.load-context --step-bead st-1 "${@:2}"; }

P="gc-toolkit/gc-toolkit.polecat"
POURED="{\"gc.execution_routed_to\":\"$P\"}"
EPIC='{"id":"tk-epic","status":"open","issue_type":"epic","title":"An epic","_deps":[{"id":"tk-park","dependency_type":"blocks"}]}'
PARK='{"id":"tk-park","status":"open","issue_type":"gate","title":"Parked until the operator unparks it"}'

echo "# nothing holds the bead"
store "[{\"id\":\"tk-w\",\"status\":\"open\",\"title\":\"work\",\"metadata\":$POURED}]"
lc tk-w
eq "$RC|$SEQ" "0|" "(FREE) a bead nothing holds goes on, and nothing is written"
has "$OUT" "nothing holds tk-w" "(FREE) the gate says nothing holds it"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-done\",\"dependency_type\":\"blocks\"}]},
        {\"id\":\"tk-done\",\"status\":\"closed\",\"title\":\"landed\"}]"
lc tk-w
eq "$RC|$SEQ" "0|" "(FREE) a blocker that closed holds nothing"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-rel\",\"dependency_type\":\"relates-to\"}]},
        {\"id\":\"tk-rel\",\"status\":\"open\",\"title\":\"related\"}]"
lc tk-w
eq "$RC|$SEQ" "0|" "(FREE) a relates-to edge onto an open bead holds nothing"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-epic\",\"dependency_type\":\"parent-child\"}]},
        {\"id\":\"tk-epic\",\"status\":\"open\",\"issue_type\":\"epic\",\"_deps\":[{\"id\":\"tk-demand\",\"dependency_type\":\"blocks\"}]},
        {\"id\":\"tk-demand\",\"status\":\"open\",\"issue_type\":\"gate\",\"title\":\"Decide the epic\",\"metadata\":{\"gc.demand_for\":\"tk-epic\"}}]"
lc tk-w
eq "$RC|$SEQ" "0|" "(FREE) a demand gate on an ancestor is the operator's decision, not a hold"

echo "# a hold declines the run"
store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-pre\",\"dependency_type\":\"blocks\"}]},
        {\"id\":\"tk-pre\",\"status\":\"open\",\"title\":\"Land the prerequisite\"}]"
lc tk-w
eq "$RC|$SEQ" "1|UPDATE;ARM;UPDATE;CANCEL;DRAIN;" \
   "(HELD) a blocker of its own: clear, arm, note, cancel, drain, in that order"
has "$(head -1 "$FAKE_UPDATE")" "gc.routed_to= " "(HELD) the clear empties gc.routed_to"
has "$(head -1 "$FAKE_UPDATE")" "gc.execution_routed_to= " "(HELD) the clear empties gc.execution_routed_to"
for k in gc.deferred_routed_to gc.deferred_execution_routed_to gc.deferred_assignee; do
  has "$(head -1 "$FAKE_UPDATE")" "$k= " "(HELD) the clear empties $k"
done
has "$(head -1 "$FAKE_UPDATE")" "resling_target=$P" "(HELD) the clear records the pool as resling_target"
has "$(head -1 "$FAKE_UPDATE")" "--unset-metadata gc.session_id --unset-metadata gc.session_name" "(HELD) the clear drops the session pins"
eq "$(meta tk-w gc.execution_routed_to)|$(meta tk-w resling_target)" "|$P" "(HELD) the store reads the clear back"
has "$(cat "$FAKE_ARM")" "arm tk-w --target $P --sling-arg --on --sling-arg mol-polecat-work --reason" \
   "(HELD) the re-sling is armed --on the formula to the pool the pour ran on"
has "$(cat "$FAKE_ARM")" 'tk-pre "Land the prerequisite"' "(HELD) the arm's reason names the hold"
has "$(cat "$FAKE_CANCEL")" "--step mol-polecat-work.load-context --bead st-1 --reason" "(HELD) the run of the named step is cancelled"
has "$(cat "$FAKE_CANCEL")" "tk-pre" "(HELD) the cancel's reason names the blocker"
has "$(notes tk-w)" 'Held-work gate: mol-polecat-work.load-context declined tk-w, held by tk-pre "Land the prerequisite"' \
   "(HELD) the note names the step and the hold"
has "$(notes tk-w)" "is armed to $P" "(HELD) the note says the re-sling is armed"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-epic\",\"dependency_type\":\"parent-child\"}]},
        $EPIC, $PARK]"
lc tk-w
eq "$RC|$SEQ" "1|UPDATE;ARM;UPDATE;CANCEL;DRAIN;" "(HELD) a park on its epic declines the run"
has "$OUT" 'held by tk-park "Parked until the operator unparks it" on ancestor tk-epic' "(HELD) the gate names the park and the ancestor it sits on"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-feat\",\"dependency_type\":\"parent-child\"}]},
        {\"id\":\"tk-feat\",\"status\":\"open\",\"issue_type\":\"feature\",\"_deps\":[{\"id\":\"tk-epic\",\"dependency_type\":\"parent-child\"}]},
        $EPIC, $PARK]"
lc tk-w
eq "$RC|$SEQ" "1|UPDATE;ARM;UPDATE;CANCEL;DRAIN;" "(HELD) a park two levels up declines the run"
has "$OUT" "on ancestor tk-epic" "(HELD) the gate names the ancestor two levels up"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-demand\",\"dependency_type\":\"blocks\"}]},
        {\"id\":\"tk-demand\",\"status\":\"open\",\"issue_type\":\"gate\",\"title\":\"Decide this bead\",\"metadata\":{\"gc.demand_for\":\"tk-w\"}}]"
lc tk-w
eq "$RC|$SEQ" "1|UPDATE;ARM;UPDATE;CANCEL;DRAIN;" "(HELD) a demand gate on the bead itself holds it"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-open\",\"dependency_type\":\"blocks\"},{\"id\":\"tk-done\",\"dependency_type\":\"blocks\"}]},
        {\"id\":\"tk-open\",\"status\":\"open\",\"title\":\"still open\"},{\"id\":\"tk-done\",\"status\":\"closed\",\"title\":\"landed\"}]"
lc tk-w
eq "$RC" "1" "(HELD) of an open and a closed blocker, the open one declines the run"
has "$(cat "$FAKE_CANCEL")" "tk-open" "(HELD) the cancel names the open blocker"
hasnt "$(cat "$FAKE_CANCEL")" "tk-done" "(HELD) and not the closed one"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":{},\"_deps\":[{\"id\":\"tk-pre\",\"dependency_type\":\"blocks\"}]},
        {\"id\":\"tk-pre\",\"status\":\"open\",\"title\":\"Land the prerequisite\"}]"
lc tk-w
eq "$RC|$SEQ" "1|ESCALATE;UPDATE;CANCEL;DRAIN;" "(HELD) a bead that names no pool skips the arm, and a visit carries the re-sling"

echo "# work in flight"
store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":{\"gc.execution_routed_to\":\"$P\",\"rejection_reason\":\"Conflicts with main\",\"branch\":\"polecat/tk-w\"},
         \"_deps\":[{\"id\":\"tk-epic\",\"dependency_type\":\"parent-child\"}]}, $EPIC, $PARK]"
lc tk-w
eq "$RC|$SEQ" "0|" "(FLIGHT) a rejected handoff under a parked epic is rebuilt"
has "$OUT" "tk-w is in flight (rejection_reason set)" "(FLIGHT) the gate says why it is in flight"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":{\"gc.execution_routed_to\":\"$P\",\"branch\":\"polecat/tk-w\"},
         \"_deps\":[{\"id\":\"tk-epic\",\"dependency_type\":\"parent-child\"},{\"id\":\"tk-pre\",\"dependency_type\":\"blocks\"}]},
        $EPIC, $PARK, {\"id\":\"tk-pre\",\"status\":\"open\",\"title\":\"Land the prerequisite\"}]"
gate --bead tk-w --formula mol-polecat-work --step mol-polecat-work.submit-and-exit --step-bead st-5
eq "$RC|$SEQ" "1|UPDATE;ARM;UPDATE;CANCEL;DRAIN;" "(FLIGHT) at the hand-off, a blocker of its own declines the run"
has "$OUT" 'held by tk-pre "Land the prerequisite"' "(FLIGHT) only its own blocker is named"
hasnt "$OUT" "tk-park" "(FLIGHT) the park on its epic does not hold work in flight"
has "$(cat "$FAKE_CANCEL")" "--step mol-polecat-work.submit-and-exit --bead st-5" "(FLIGHT) the hand-off's run is the one cancelled"

echo "# a hold that does not read"
store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED}]"
STUB_LIST_FAIL=1 lc tk-w
eq "$RC|$SEQ" "1|ESCALATE;UPDATE;CANCEL;DRAIN;" "(UNREAD) a read that fails holds the bead, and with no pool read, a visit carries the re-sling"
has "$OUT" "an unreadable hold" "(UNREAD) the gate says the hold did not read"
eq "$(meta tk-w gc.execution_routed_to)" "$P" "(UNREAD) nothing is cleared when no arm is made"
has "$(cat "$FAKE_ESC")" "--subject tk-w --key polecat-blocked-work" "(UNREAD) the visit is filed on the work bead"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"sl-other\",\"dependency_type\":\"blocks\"}]}]"
lc tk-w
eq "$RC|$SEQ" "1|UPDATE;ARM;UPDATE;CANCEL;DRAIN;" "(UNREAD) a blocker of its own the store does not return holds the bead"
has "$OUT" "sl-other (unreadable)" "(UNREAD) the gate names the blocker it could not read"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-epic\",\"dependency_type\":\"parent-child\"}]}, $EPIC, $PARK]"
STUB_LIST_FAIL_ID=tk-epic lc tk-w
eq "$RC|$SEQ" "1|UPDATE;ARM;UPDATE;CANCEL;DRAIN;" "(UNREAD) a row that reads under an ancestor that does not is held, and armed to the pool its row names"
has "$OUT" "its blockers or ancestors did not read" "(UNREAD) the gate says the walk did not read"

echo "# a closed bead"
store "[{\"id\":\"tk-w\",\"status\":\"closed\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-epic\",\"dependency_type\":\"parent-child\"}]}, $EPIC, $PARK]"
STUB_LIST_FAIL_ID=tk-epic lc tk-w
eq "$RC|$SEQ" "1|UPDATE;CANCEL;DRAIN;" "(CLOSED) a closed bead is cancelled with no re-sling even when its walk does not read"
store "[{\"id\":\"tk-w\",\"status\":\"closed\",\"metadata\":$POURED}]"
lc tk-w
eq "$RC|$SEQ" "1|UPDATE;CANCEL;DRAIN;" "(CLOSED) a closed bead's run is cancelled with no re-sling and no visit"
has "$(cat "$FAKE_CANCEL")" "work bead tk-w is closed" "(CLOSED) the cancel says why"

echo "# a release that does not land"
HELD_STORE="[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-pre\",\"dependency_type\":\"blocks\"}]},
             {\"id\":\"tk-pre\",\"status\":\"open\",\"title\":\"Land the prerequisite\"}]"
store "$HELD_STORE"
FAKE_ARM_RC=1 lc tk-w
eq "$RC|$SEQ" "1|UPDATE;ARM;ESCALATE;UPDATE;CANCEL;DRAIN;" "(FAIL) an arm that fails falls back to a visit, then cancels and drains"
has "$(cat "$FAKE_ESC")" "gc sling $P tk-w --on mol-polecat-work" "(FAIL) the visit carries the re-sling to type"
eq "$(cat "$FAKE_ESC_ENV")" "window=0" "(FAIL) the visit is filed with escalate.sh's verdict window off"
has "$(notes tk-w)" "so a visit asks for one" "(FAIL) the note says a visit carries the re-sling"

store "$HELD_STORE"
FAKE_ARM_RC=1 FAKE_ESC_RC=1 lc tk-w
eq "$RC|$SEQ" "1|UPDATE;ARM;ESCALATE;" "(FAIL) neither arm nor visit: no cancel, no drain"
has "$OUT" "NOT cancelling or draining" "(FAIL) the gate says the step stays claimed"

store "$HELD_STORE"
FAKE_CANCEL_RC=1 lc tk-w
eq "$RC|$SEQ" "1|UPDATE;ARM;UPDATE;CANCEL;" "(FAIL) a cancel that fails is not drained"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":{\"resling_target\":\"$P\"},\"_deps\":[{\"id\":\"tk-pre\",\"dependency_type\":\"blocks\"}]},
        {\"id\":\"tk-pre\",\"status\":\"open\",\"title\":\"Land the prerequisite\"}]"
lc tk-w
has "$(cat "$FAKE_ARM")" "arm tk-w --target $P" "(FAIL) a re-run after a failed arm finds the pool in resling_target"

store "[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":{\"gc.execution_routed_to\":\"polecat\"},\"_deps\":[{\"id\":\"tk-pre\",\"dependency_type\":\"blocks\"}]},
        {\"id\":\"tk-pre\",\"status\":\"open\",\"title\":\"Land the prerequisite\"}]"
lc tk-w
eq "$SEQ" "ESCALATE;UPDATE;CANCEL;DRAIN;" "(FAIL) a pool that is not rig-qualified is no pool: a visit, and only the note written"
eq "$(meta tk-w gc.execution_routed_to)" "polecat" "(FAIL) with no arm made, the route keys are left as they were"

echo "# a visit a person closed moot, inside escalate.sh's verdict window"
# The real escalate.sh runs as the gate's fallback runs it. A person closed the
# bead's last polecat-blocked-work visit moot an hour ago. The subject's store
# is left unproven, so the visit files under GC_RIG, the store this stub serves.
open_visits() {
  jq -r '[ .[] | select((.metadata.escalation_key // "") == "polecat-blocked-work"
                        and (.metadata["gc.continuation_group"] // "") == "tk-w" and .status != "closed") | .id ] | join(" ")' "$STUB_STORE"
}
printf '#!/usr/bin/env bash\nexit 3\n' > "$BIN/escalation-rig"; chmod +x "$BIN/escalation-rig"
HOUR_AGO="$(date -u -r $(( $(date +%s) - 3600 )) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(( $(date +%s) - 3600 ))" +%Y-%m-%dT%H:%M:%SZ)"
MOOT_STORE="[{\"id\":\"tk-w\",\"status\":\"open\",\"metadata\":$POURED,\"_deps\":[{\"id\":\"tk-pre\",\"dependency_type\":\"blocks\"}]},
             {\"id\":\"tk-pre\",\"status\":\"open\",\"title\":\"Land the prerequisite\"},
             {\"id\":\"tk-v0\",\"status\":\"closed\",\"closed_at\":\"$HOUR_AGO\",\"issue_type\":\"task\",\"title\":\"visit: tk-w\",
              \"metadata\":{\"task_kind\":\"visit\",\"escalation_key\":\"polecat-blocked-work\",\"gc.continuation_group\":\"tk-w\",\"gc.routed_to\":\"human\",\"gc.outcome\":\"moot\"}}]"
store "$MOOT_STORE"
RRC=0; ROUT="$(GC_RIG=gc-toolkit GC_ESCALATION_RIG_TOOL="$BIN/escalation-rig" "$HERE/escalate.sh" \
  --subject tk-w --key polecat-blocked-work --message "Re-sling tk-w once nothing holds it" 2>&1)" || RRC=$?
eq "$RRC|$(open_visits)" "0|" "(WINDOW) control: inside the window, escalate.sh exits 0 and files no visit"
has "$ROUT" "was answered 'moot'" "(WINDOW) control: escalate.sh answers from the closed moot visit"

store "$MOOT_STORE"
GC_RIG=gc-toolkit GC_ESCALATION_RIG_TOOL="$BIN/escalation-rig" GC_ESCALATE_TOOL="$HERE/escalate.sh" FAKE_ARM_RC=1 lc tk-w
NEWV="$(open_visits)"
eq "$RC|$SEQ" "1|UPDATE;ARM;UPDATE;CANCEL;DRAIN;" "(WINDOW) an arm that fails with a moot visit closed inside the window: a visit, then the cancel and the drain"
case "$NEWV" in
  ""|*" "*|tk-v0) bad "(WINDOW) the gate files one fresh open visit (got '$NEWV')" ;;
  *) ok "(WINDOW) the gate files one fresh open visit ($NEWV)" ;;
esac
SAW="$(cat "$FAKE_CANCEL_SAW")"
if [ -n "$SAW" ] && [ "$SAW" = "$NEWV" ]; then ok "(WINDOW) the visit is open when the run is cancelled ($SAW)"
else bad "(WINDOW) the visit is open when the run is cancelled (open at the cancel: '$SAW', filed: '$NEWV')"; fi
has "$(notes tk-w)" "so a visit asks for one" "(WINDOW) the note says a visit carries the re-sling"

echo "# arguments"
gate --bead tk-w --formula mol-polecat-work
eq "$RC" "2" "(ARGS) --step is required"
gate --bead '{{issue}}' --formula mol-polecat-work --step mol-polecat-work.load-context
eq "$RC" "2" "(ARGS) an unrendered placeholder is refused"
gate --bead tk-w --formula mol-polecat-work --step mol-polecat-work.load-context --bogus
eq "$RC" "2" "(ARGS) an unknown argument is refused"

store "$HELD_STORE"
gate --bead tk-w --formula mol-design-convoy --step mol-design-convoy.load-context --sling-arg --var --sling-arg design_gated=false
has "$(cat "$FAKE_ARM")" "--sling-arg --on --sling-arg mol-design-convoy --sling-arg --var --sling-arg design_gated=false --reason" \
   "(ARGS) each --sling-arg follows --on <formula> in the arm"
store "$HELD_STORE"
FAKE_ARM_RC=1 gate --bead tk-w --formula mol-design-convoy --step mol-design-convoy.load-context --sling-arg --var --sling-arg design_gated=false
has "$(cat "$FAKE_ESC")" "--on mol-design-convoy --var design_gated=false" "(ARGS) the visit's re-sling carries the same arguments"

store "$HELD_STORE"
lc tk-w --dry-run
eq "$RC|$SEQ" "1|" "(ARGS) --dry-run on a held bead writes, cancels and drains nothing"
has "$OUT" "DRY RUN: tk-w is held by" "(ARGS) --dry-run reports the hold"
eq "$(meta tk-w gc.execution_routed_to)" "$P" "(ARGS) --dry-run leaves the route keys"

# --- the formula blocks ------------------------------------------------------
echo "# each formula block calls the gate"
extract() { # <toml> <marker>
  awk -v m="$2" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$1"
}
FAKEPACK="$TMP/pack"; mkdir -p "$FAKEPACK/assets/scripts"
cat > "$FAKEPACK/assets/scripts/held-work-gate.sh" <<'GATE'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${FAKE_GATE_ARGV:?}"
exit "${FAKE_GATE_RC:-0}"
GATE
chmod +x "$FAKEPACK/assets/scripts/held-work-gate.sh"
# wire <toml> <marker> <want-argv>: the block, extracted and run with the stub
# gate first in its search, passes the gate the argv wanted, and the step goes
# on only when the gate exits 0.
wire() {
  local toml="$ROOT/formulas/$1" m="$2" want="$3" block rc out
  block="$(extract "$toml" "$m" | sed 's/{{design_gated}}/false/g')"
  if [ -z "$block" ]; then bad "(WIRING) $m: no block between its markers in $1"; return; fi
  eq "$(grep -c "^# >>> $m\$" "$toml")" "1" "(WIRING) $m: exactly one region in $1"
  case "$block" in *\\*) bad "(WIRING) $m: carries a backslash, which a TOML triple-quoted string mangles" ;; *) ok "(WIRING) $m: backslash-free" ;; esac
  printf '%s\necho AFTER\n' "$block" > "$TMP/block.sh"
  bash -n "$TMP/block.sh" && ok "(WIRING) $m: valid bash" || bad "(WIRING) $m: valid bash"
  for rc in 0 1; do
    out="$(cd "$TMP" && GC_PACK_DIR="$FAKEPACK" FAKE_GATE_ARGV="$TMP/gate-argv" FAKE_GATE_RC="$rc" \
           WORK_BEAD_ID=tk-w SUBJECT=tk-s CLAIMED_STEP_BEAD_ID=st-1 bash "$TMP/block.sh" 2>&1)"
    eq "$(cat "$TMP/gate-argv")" "$want" "(WIRING) $m: the gate gets its bead, formula, step and args (gate exit $rc)"
    if [ "$rc" = 0 ]; then has "$out" "AFTER" "(WIRING) $m: the step goes on when the gate exits 0"
    else hasnt "$out" "AFTER" "(WIRING) $m: the step stops when the gate does not exit 0"; fi
  done
}
wire mol-polecat-work.toml load-context-blocked-work-decline \
  "--bead tk-w --formula mol-polecat-work --step mol-polecat-work.load-context --step-bead st-1"
wire mol-polecat-work.toml submit-held-work-decline \
  "--bead tk-w --formula mol-polecat-work --step mol-polecat-work.submit-and-exit --step-bead st-1"
wire mol-design-convoy.toml design-convoy-held-work-decline \
  "--bead tk-s --formula mol-design-convoy --step mol-design-convoy.load-context --step-bead st-1 --sling-arg --var --sling-arg design_gated=false"
# The design-convoy gate runs before any step acts on the subject: ahead of
# seed-convoy, which creates the convoy and pushes its branch.
DC="$ROOT/formulas/mol-design-convoy.toml"
gate_line="$(grep -n '^# >>> design-convoy-held-work-decline$' "$DC" | cut -d: -f1)"
seed_line="$(grep -n '^id = "seed-convoy"$' "$DC" | cut -d: -f1)"
[ -n "$gate_line" ] && [ -n "$seed_line" ] && [ "$gate_line" -lt "$seed_line" ] \
  && ok "(WIRING) mol-design-convoy declines a held subject before seed-convoy" \
  || bad "(WIRING) mol-design-convoy declines a held subject before seed-convoy (gate line '${gate_line}', seed-convoy line '${seed_line}')"
# The submit gate runs after the push and before the hand-off writes.
PW="$ROOT/formulas/mol-polecat-work.toml"
push_line="$(grep -n '^git push origin HEAD' "$PW" | cut -d: -f1)"
held_line="$(grep -n '^# >>> submit-held-work-decline$' "$PW" | cut -d: -f1)"
consume_line="$(grep -n '^# >>> submit-target-consume$' "$PW" | cut -d: -f1)"
[ -n "$push_line" ] && [ -n "$held_line" ] && [ -n "$consume_line" ] && [ "$push_line" -lt "$held_line" ] && [ "$held_line" -lt "$consume_line" ] \
  && ok "(WIRING) submit-and-exit reads the hold after the push and before the hand-off" \
  || bad "(WIRING) submit-and-exit reads the hold after the push and before the hand-off (push '${push_line}', gate '${held_line}', hand-off '${consume_line}')"

# --- the round trip ----------------------------------------------------------
# The real deferred-dispatch.sh arms and reconciles. Its pass lock lives in the
# tmpdir, and it runs unpaced and unpinned against the store stub.
echo "# park, sling, unpark, built"
export DEFERRED_DISPATCH_STATE_DIR="$TMP/dd-state" DEFERRED_DISPATCH_PASS_BUDGET_SECS=0
unset GC_PACK_STATE_DIR GC_ORDER_OUTCOME_FILE 2>/dev/null || true
if ! command -v flock >/dev/null 2>&1; then
  bad "(ROUND) flock is on PATH, which deferred-dispatch.sh's pass lock needs"
else
  reconcile() { : > "$STUB_SLING_LOG"; RC=0; OUT="$("$DD" reconcile 2>&1)" || RC=$?; }
  # round <leave-root>: a workflow poured for tk-w, then its epic parked, then
  # its load-context gate, then a pass under the park, then the unpark and a pass.
  round() {
    store "[{\"id\":\"tk-w\",\"status\":\"open\",\"issue_type\":\"task\",\"title\":\"work\",\"metadata\":$POURED,
             \"_deps\":[{\"id\":\"tk-epic\",\"dependency_type\":\"parent-child\"}]},
            {\"id\":\"tk-epic\",\"status\":\"open\",\"issue_type\":\"epic\",\"title\":\"An epic\"},
            {\"id\":\"tk-r1\",\"status\":\"in_progress\",\"issue_type\":\"task\",\"title\":\"mol-polecat-work\",
             \"metadata\":{\"gc.kind\":\"workflow\",\"test.root_for\":\"tk-w\"}}]"
    jq -c --argjson park "$PARK" 'map(if .id == "tk-epic" then ._deps = [{id: "tk-park", dependency_type: "blocks"}] else . end) + [$park]' \
      "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
    STUB_ROOT_OF=tk-w FAKE_CANCEL_LEAVES_ROOT="$1" GC_DEFERRED_DISPATCH_TOOL="$DD" lc tk-w
  }
  round ""
  eq "$RC|$(tr '\n' ';' < "$FAKE_LOG" | sed 's/UPDATE;//g')" "1|CANCEL;DRAIN;" \
     "(ROUND) the workflow poured before the park is declined at load-context"
  eq "$(meta tk-w gc.dispatch_when_ready)" "$P" "(ROUND) the real arm records the re-sling to the pool"
  eq "$(meta tk-w gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "(ROUND) the arm replays --on mol-polecat-work"
  eq "$(status_of tk-r1)" "closed" "(ROUND) the cancel closed the held root"
  reconcile
  eq "$RC|$(wc -l < "$STUB_SLING_LOG" | tr -d ' ')" "0|0" "(ROUND) a pass under the park slings nothing"
  has "$OUT" "HELD by tk-park" "(ROUND) the pass names the park that holds the arm"
  jq -c 'map(if .id == "tk-park" then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
  reconcile
  eq "$RC|$(cat "$STUB_SLING_LOG")" "0|$P tk-w --on mol-polecat-work" "(ROUND) the first pass after the unpark slings tk-w once"
  eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "(ROUND) the proven sling retires the arm"
  eq "$(jq '[ .[] | select((.metadata["test.root_for"] // "") == "tk-w" and .status != "closed") ] | length' "$STUB_STORE")" "1" \
     "(ROUND) the re-sling poured a fresh root past the cancelled one"
  lc tk-w
  eq "$RC|$SEQ" "0|" "(ROUND) the fresh pour's load-context finds nothing holding tk-w, so it is built"

  # The control: a root the decline leaves live, which a molecule held in
  # place was, makes the re-sling's pour fail after the unpark.
  round 1
  jq -c 'map(if .id == "tk-park" then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
  reconcile
  eq "$(cat "$STUB_SLING_LOG")" "$P tk-w --on mol-polecat-work" "(ROUND) control: the pass after the unpark tries the re-sling"
  eq "$(meta tk-w gc.dispatch_when_ready)" "$P" "(ROUND) control: a live root refuses the pour, so the arm stays"
  has "$OUT" "1 failed (of 1 armed)" "(ROUND) control: the pass counts the refused sling as failed"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
