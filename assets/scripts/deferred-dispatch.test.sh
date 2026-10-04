#!/usr/bin/env bash
# Hermetic test for assets/scripts/deferred-dispatch.sh (tk-y0ygs).
#
# WHAT THE SCRIPT IS FOR. `gc sling` pours immediately and reads no `blocks`
# deps, so sequencing used to be an agent remembering not to dispatch yet — a
# hold with no home in the ledger, invisible to everyone and lost when the
# holder died. `arm` writes that pending dispatch onto the work bead; the
# `reconcile` pass performs it once bd itself reports the bead ready.
#
# What is exercised:
#   * arm writes the record and APPENDS to notes (a replacing write here would
#     destroy the dispatch note the arm is supposed to make legible);
#   * arm's fail-closed refusals — already routed, closed, no target;
#   * arm ACCEPTS a bead carrying only gc.execution_routed_to (execution
#     provenance, not a live queue): the shape doctor/check-blocked-work-armed
#     flags and names arming as the fix for, so refusing would be a dead end;
#   * the dispatch arm: ready + armed -> exactly one `gc sling` with the
#     recorded target and pass-through args, then the record cleared;
#   * the two-state gc.dispatch_when_ready_slung marker: a proven "slung@" marker
#     (or a bare-timestamp one) RETIRES the arm without a second sling, while an
#     unproven "slinging@" marker — a pass that died before confirming its sling —
#     is RE-SLUNG, so a crash mid-dispatch never silently loses the work; recovery
#     reads this one owned marker, not any lane-specific stamp, and the pre-sling
#     stamp is the unproven state so a crash there recovers as a re-sling;
#   * every OTHER arm that must NOT sling: still blocked, assignee held, sling
#     failed;
#   * the closed-bead retire arm;
#   * the CONVOY-LEAK guards — gc sling mints an input convoy per call, so an arm
#     that never finalizes must not be re-slung forever: an arm whose work
#     another path already delivered (a merge_result stamp) RETIRES without
#     slinging, and a sling that keeps failing is COUNTED, CAPPED, and escalated
#     once (keeping the arm, never a silent retire) instead of leaking one convoy
#     per pass; a proven dispatch clears the count so the budget resets;
#   * the FALSE-EMPTY-QUEUE guard — an unreadable listing exits non-zero
#     instead of printing a summary byte-identical to a healthy empty queue.
#     That fail-open is the exact class this script must not have: it is a
#     dispatcher, and a silent "nothing was owed" is how the hold went missing
#     in the first place;
#   * the QUIET PATH — an empty store still passes, so the guard above did not
#     strand the ordinary no-work case;
#   * the ARG_MAX guard — a large armed set still enumerates and dispatches. A
#     snapshot handed to jq as one argv value dies past the kernel per-argument
#     cap, which silently strands the whole backlog; the fixture is sized to
#     prove the old argv pass fails before asserting the SUT survives it;
#   * a POSITIVE CONTROL over the shipped order file, so a passing suite cannot
#     mean the cadence that consumes these records was quietly un-shipped;
#   * SCRATCH CLEANUP — every verb that stages a temp file leaves none behind.
#
# No live city, Dolt, network, gc or bd — only jq, stubs, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/deferred-dispatch.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-deferred-dispatch-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$SUT" ] || chmod +x "$SUT" 2>/dev/null

# --- stubs -------------------------------------------------------------------
# $TMP/beads.json is the store: an array of beads, each carrying an extra
# `_ready` flag standing in for bd's own readiness predicate. The script must
# ASK for readiness rather than compute it, so the stub answers and the test
# asserts the script honored the answer.
BIN="$TMP/bin"; mkdir -p "$BIN"

cat > "$BIN/bd" <<'STUB'
#!/usr/bin/env bash
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
# Minimal bd stub over $STORE. Understands only the calls the SUT makes.
set -u
STORE="${STUB_STORE:?}"
# Global flags precede the verb, as they do for real bd. The store is a single
# fixture file, so --db is consumed and discarded rather than honoured.
while [ "${1:-}" = "--db" ]; do shift 2 || shift || true; done
if [ -n "${STUB_BD_LIST_FAIL:-}" ] && [ "${1:-}" = "list" ]; then
    echo "bd: simulated listing failure" >&2; exit 1
fi
case "${1:-}" in
  list)
    shift
    key=""; ready=0; all=0; id=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --has-metadata-key) shift; key="${1:-}" ;;
        --id) shift; id="${1:-}" ;;
        --ready) ready=1 ;;
        --all) all=1 ;;
        *) : ;;
      esac
      shift || true
    done
    # Real bd refuses this combination outright:
    #   "validation failed: --ready cannot filter on IDFilter (--id); the
    #    blocker-aware ready query cannot be narrowed to specific ids"
    # The stub must refuse it too, or it will happily serve a query that can
    # only ever error against the live tool.
    if [ "$ready" = "1" ] && [ -n "$id" ]; then
      echo "Error: validation failed: --ready cannot filter on IDFilter (--id)" >&2; exit 1
    fi
    # `--id` takes a comma list (the bulk blocker-status read passes many). Real
    # `bd list --json` carries each bead's own outgoing edges under `.dependencies`
    # in the list-edge shape ({issue_id: self, depends_on_id: blocker, type}); the
    # SUT reads its candidates' blockers off that snapshot rather than a dep-list
    # per bead, so the stub must render `.dependencies` from the `_deps` fixture
    # field. A blocker's STATUS is NOT part of that edge shape — it is resolved by
    # a separate `bd list --id <blocker>`, so the blocker must be its own bead in
    # the store, exactly as it is live.
    jq -c --arg k "$key" --arg id "$id" --argjson ready "$ready" --argjson all "$all" '
      ($id | if . == "" then [] else split(",") end) as $ids
      | [ .[]
        | select($k == "" or (.metadata | has($k)))
        | select(($ids | length) == 0 or (.id as $i | $ids | index($i)))
        | select($all == 1 or .status != "closed")
        | select($ready == 0 or (._ready == true))
        | . as $b
        | .dependencies = [ ($b._deps // [])[] | {issue_id: $b.id, depends_on_id: .id, type: .dependency_type} ]
        | del(._ready) | del(._deps) ]' "$STORE"
    ;;
  show)
    id="${2:-}"
    out="$(jq -c --arg id "$id" '[ .[] | select(.id == $id) | del(._ready) ]' "$STORE")"
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      # bd answers an OBJECT, not an empty array, when nothing resolves.
      echo '{"error":"no issues found matching the provided IDs","schema_version":1}'
    else
      printf '%s\n' "$out"
    fi
    ;;
  update)
    shift
    id="${1:-}"; shift || true
    sets=(); unsets=(); note=""; note_mode=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; sets+=("${1:-}") ;;
        --unset-metadata) shift; unsets+=("${1:-}") ;;
        --append-notes) shift; note="${1:-}"; note_mode="append" ;;
        # Modelled deliberately: bd's --notes REPLACES. A stub that ignored it
        # would let a destructive-write regression pass the append assertions.
        --notes) shift; note="${1:-}"; note_mode="replace" ;;
        *) : ;;
      esac
      shift || true
    done
    tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-deferred-dispatch-test.XXXXXX")"
    cp "$STORE" "$tmp"
    for kv in ${sets[@]+"${sets[@]}"}; do
      k="${kv%%=*}"; v="${kv#*=}"
      jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
        'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    for k in ${unsets[@]+"${unsets[@]}"}; do
      jq -c --arg id "$id" --arg k "$k" \
        'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    if [ "$note_mode" = "append" ]; then
      jq -c --arg id "$id" --arg n "$note" \
        'map(if .id == $id then .notes = ((.notes // "") + (if (.notes // "") == "" then "" else "\n" end) + $n) else . end)' \
        "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    elif [ "$note_mode" = "replace" ]; then
      jq -c --arg id "$id" --arg n "$note" \
        'map(if .id == $id then .notes = $n else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    fi
    mv "$tmp" "$STORE"
    echo "updated $id"
    ;;
  dep)
    # Only `dep list <id> --json` is used (own_blocks_cleared). Real bd answers an
    # ARRAY of {id, dependency_type, status} — a bead's own outgoing edges — and an
    # ERROR OBJECT (not an array) for an unresolvable id, so the stub serves both
    # shapes to exercise the SUT's fail-closed array check.
    shift
    [ "${1:-}" = "list" ] || { echo "bd stub: unsupported 'dep ${1:-}'" >&2; exit 2; }
    shift; depid="${1:-}"
    if [ -n "${STUB_DEP_LIST_FAIL:-}" ] && [ "$STUB_DEP_LIST_FAIL" = "$depid" ]; then
      # A store that cannot answer the dep query: not an array. own_blocks_cleared
      # must fail closed on this and leave the bead armed, never sling on a guess.
      echo '{"error":"simulated dep-list failure","schema_version":1}'; exit 0
    fi
    if [ "$(jq -r --arg id "$depid" 'any(.[]; .id == $id)' "$STORE")" != "true" ]; then
      echo '{"error":"resolving '"$depid"': no issue found","schema_version":1}'
    else
      # _deps models the bead's own edges. Absent it, a not-ready bead stands in
      # for the common "waiting on its own open blocker" case and a ready one for
      # "no blockers left", so the pre-existing fixtures stay honest with no _deps.
      # When _deps IS set, real bd hides an edge whose target has no row in this
      # store (cross-repo/external): it warns on stderr and omits it from the
      # array, so `bd dep list <bead>` returns [] for a bead whose only blocker is
      # cross-store. Model that, so own_blocks_cleared reads such a bead as cleared
      # exactly as it does live — the misleading "no open blocker" hint this
      # finding is about.
      jq -c --arg id "$depid" '
        . as $store
        | [ .[] | select(.id == $id) ] | .[0] as $b
        | if ($b._deps == null) then
            (if ($b._ready // false) then [] else [{"id":"_synthetic_blocker","dependency_type":"blocks","status":"open"}] end)
          else
            [ $b._deps[] | select(.id as $t | ($store | any(.[]; .id == $t))) ]
          end' "$STORE"
    fi
    ;;
  *) echo "bd stub: unsupported '${1:-}'" >&2; exit 2 ;;
esac
STUB

cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = "bd" ]; then
    shift
    printf '%s\n' "$*" >> "${STUB_BD_LOG:-/dev/null}"
    VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@"
fi
if [ "${1:-}" = "sling" ]; then
    shift
    printf '%s\n' "$*" >> "${STUB_SLING_LOG:?}"
    # Record the slung marker AS IT STANDS at sling time, so a test can prove the
    # pass stamps the UNPROVEN state before it slings — a crash here must recover
    # as a re-sling, not a retire. After the shift, $1 is the target, $2 the bead.
    if [ -n "${STUB_SLING_MARKER_LOG:-}" ]; then
        jq -r --arg id "${2:-}" '(.[] | select(.id == $id) | .metadata["gc.dispatch_when_ready_slung"]) // "<absent>"' "${STUB_STORE:?}" >> "$STUB_SLING_MARKER_LOG"
    fi
    exit "${STUB_SLING_RC:-0}"
fi
echo "gc stub: unsupported '${1:-}'" >&2; exit 2
STUB
# escalate.sh stub: records each call (subject + key) so the retry-cap test can
# prove reconcile hands a stuck dispatch to a person exactly once, and answers
# like the real tool. Resolved by the SUT through GC_ESCALATE_TOOL.
cat > "$BIN/escalate.sh" <<'ESC'
#!/usr/bin/env bash
set -u
subject=""; key=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) shift; subject="${1:-}" ;;
    --key) shift; key="${1:-}" ;;
    --message) shift ;;
    *) : ;;
  esac
  shift || true
done
printf '%s\t%s\n' "$subject" "$key" >> "${ESC_CALLS:?}"
echo "escalate: filed visit tk-visit1 on $subject [$key]"
ESC
chmod +x "$BIN/bd" "$BIN/gc" "$BIN/escalate.sh"

export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/beads.json"
export STUB_SLING_LOG="$TMP/sling.log"
export ESC_CALLS="$TMP/escalate.log"
export GC_ESCALATE_TOOL="$BIN/escalate.sh"
export BEADS_ACTOR="test-actor"
unset GC_AGENT GC_RIG GC_RIG_ROOT 2>/dev/null || true

store() { printf '%s' "$1" > "$STUB_STORE"; : > "$STUB_SLING_LOG"; : > "$ESC_CALLS"; }
meta()  { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
notes() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STUB_STORE"; }
slings() { wc -l < "$STUB_SLING_LOG" | tr -d ' '; }
escalations() { wc -l < "$ESC_CALLS" | tr -d ' '; }

# --- ARM ---------------------------------------------------------------------
echo "# arm"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"mayor: dispatch after b-0 lands","_ready":false}]'
out="$("$SUT" arm b-1 --target rig/pool --reason "needs b-0" 2>&1)"; rc=$?
eq "$rc" 0 "arm exits 0"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "arm records the target"
eq "$(meta b-1 gc.dispatch_when_ready_args)" "[]" "arm records an empty arg list by default"
eq "$(meta b-1 gc.dispatch_when_ready_armed_by)" "test-actor" "arm records who armed it"
has "$(meta b-1 gc.dispatch_when_ready_armed_at)" "T" "arm records when"
eq "$(meta b-1 gc.dispatch_when_ready_reason)" "needs b-0" "arm records the reason"
has "$(notes b-1)" "mayor: dispatch after b-0 lands" "arm APPENDS to notes (prior note survives)"
has "$(notes b-1)" "dispatch armed by test-actor" "arm's own note is present"
has "$out" "armed b-1 -> rig/pool" "arm says what it did"

store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" arm b-1 --target rig/pool 2>&1)"
has "$out" "no open blocker right now" "arm on an unblocked bead warns it will dispatch immediately"

# The mirror case. It is what makes the hint above load-bearing: a hint that
# fires unconditionally says nothing, and a per-id readiness probe (which real
# bd refuses) would produce no hint in either direction.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":false}]'
out="$("$SUT" arm b-1 --target rig/pool 2>&1)"
hasnt "$out" "no open blocker right now" "arm on a BLOCKED bead does not claim it will dispatch immediately"

echo "# arm warns on a cross-store blocker it cannot resolve"
# bd resolves dependencies within one store, so a `blocks` edge to a bead in
# another rig (here sl-x, which has no row in this store) holds nothing: bd
# reports the bead ready (_ready) and own_blocks_cleared, reading the same store,
# sees no blocker. Without naming it, arm's own hint says "no open blocker right
# now" while the blocker is open — the contradiction this finding is about. arm
# must name the unresolvable blocker instead, the one place a human can redirect
# the sequencing.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true,"_deps":[{"id":"sl-x","dependency_type":"blocks","status":"open"}]}]'
out="$("$SUT" arm b-1 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm still records the dispatch on a cross-store-blocked bead"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the dispatch record is written"
has "$out" "sl-x" "arm names the unresolvable cross-store blocker"
has "$out" "no row in this store" "arm says why that blocker holds nothing here"
hasnt "$out" "no open blocker right now" "arm does NOT claim the cross-store-blocked bead is unblocked"

echo "# arm does not mistake an in-store blocker for a cross-store one"
# b-0 has a row in this store, so its edge resolves: no cross-store warning, and
# because the blocker is open the bead is correctly held, not announced ready.
store '[{"id":"b-0","status":"open","assignee":"","metadata":{},"notes":"","_ready":true},
        {"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks","status":"open"}]}]'
out="$("$SUT" arm b-1 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm exits 0 with an in-store blocker"
hasnt "$out" "no row in this store" "an in-store blocker triggers no cross-store warning"
hasnt "$out" "no open blocker right now" "and the in-store-blocked bead is not announced ready"

echo "# arm does not announce 'no blocker' when the cross-store enumeration itself fails"
# own_blocks_unresolved_ids fails closed (non-zero) when its own `bd list --id`
# read fails, while dep list still reads the bead cleared (no in-store blocker,
# _ready true). cmd_arm must not collapse that enumeration failure into "no
# cross-store blocker": the check is unproven, so the immediate-dispatch hint
# must not stand on it. Without the three-state read, the buggy path prints the
# all-clear here, so the two trailing assertions discriminate the fix.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_BD_LIST_FAIL=1 "$SUT" arm b-1 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm still records the dispatch when the cross-store probe read fails"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the dispatch record is written"
hasnt "$out" "no open blocker right now" "arm does NOT announce an unblocked bead when the cross-store check could not be proven"
has "$out" "could not enumerate" "arm warns the cross-store check could not be proven"

echo "# arm accepts the doctor-flagged shape"
# gc.execution_routed_to is provenance, not a live queue, so a blocked bead
# carrying only it is the exact shape doctor/check-blocked-work-armed flags and
# names arming as the fix for. arm must accept it, or that remedy is a dead end.
store '[{"id":"b-2","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/pool"},"notes":"","_ready":false}]'
out="$("$SUT" arm b-2 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm accepts a blocked bead carrying only gc.execution_routed_to"
eq "$(meta b-2 gc.dispatch_when_ready)" "rig/pool" "arming the exec-routed-only bead records the dispatch"
has "$out" "armed b-2 -> rig/pool" "arm says what it did"

echo "# arm refusals"
# A real active route (gc.routed_to, what a pool queue consumes) still blocks
# arming: a second dispatch would queue behind the live one.
store '[{"id":"b-2r","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/pool"},"notes":"","_ready":true}]'
out="$("$SUT" arm b-2r --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead already routed (gc.routed_to)"
eq "$(meta b-2r gc.dispatch_when_ready)" "<absent>" "refused arm writes nothing"
has "$out" "already dispatched" "refusal names the reason"

# A gc.dispatch_when_ready_slung marker in either state means reconcile is
# mid-dispatch on this bead; re-arming over it would stack a second dispatch.
store '[{"id":"b-2s","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready_slung":"slinging@2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" arm b-2s --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead reconcile is mid-dispatch on (gc.dispatch_when_ready_slung)"
eq "$(meta b-2s gc.dispatch_when_ready)" "<absent>" "refused arm writes nothing"
has "$out" "already dispatched" "refusal names the reason"

store '[{"id":"b-3","status":"closed","assignee":"","metadata":{},"notes":"","_ready":false}]'
out="$("$SUT" arm b-3 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a closed bead"

# `bd list --ready` answers OPEN beads only — it excludes on status before it
# looks at deps at all. So a hold recorded on any other live status can never
# fire, and nothing re-derives status from the dep graph: the arm would sit in
# the queue reading as "waiting on a blocker" for as long as the hold stands.
for HELD in blocked deferred hooked pinned; do
  store '[{"id":"b-h","status":"'"$HELD"'","assignee":"","metadata":{},"notes":"","_ready":false}]'
  out="$("$SUT" arm b-h --target rig/pool 2>&1)"; rc=$?
  eq "$rc" 1 "arm refuses a $HELD bead"
  eq "$(meta b-h gc.dispatch_when_ready)" "<absent>" "a refused $HELD arm writes nothing"
  has "$out" "answers open beads only" "the $HELD refusal names the ready predicate"
done

store '[{"id":"b-4","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" arm b-4 2>&1)"; rc=$?
eq "$rc" 2 "arm without --target is a usage error"
eq "$(meta b-4 gc.dispatch_when_ready)" "<absent>" "arm without --target writes nothing"

out="$("$SUT" arm b-nope --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead that does not resolve (bd's object-shaped miss)"

# --- RECONCILE: the dispatch arm ---------------------------------------------
echo "# reconcile dispatches"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "reconcile exits 0 on a clean pass"
eq "$(slings)" "1" "reconcile slung exactly once"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1" "sling got the recorded target and bead"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the record is cleared after a successful dispatch"
has "$(notes b-1)" "dispatched to rig/pool" "the dispatch is recorded in notes"
has "$out" "1 dispatched" "summary counts the dispatch"

echo "# reconcile passes sling args through in order"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[\"--on\",\"mol-pr-from-issue\",\"--merge\",\"mr\"]"},"notes":"","_ready":true}]'
"$SUT" reconcile >/dev/null 2>&1
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1 --on mol-pr-from-issue --merge mr" "recorded sling args reach gc sling in order"

echo "# arm --sling-arg round-trips into the dispatch"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
"$SUT" arm b-1 --target rig/pool --sling-arg --on --sling-arg mol-pr-from-issue >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_args)" '["--on","mol-pr-from-issue"]' "arm encodes --sling-arg as a JSON array"
: > "$STUB_SLING_LOG"
"$SUT" reconcile >/dev/null 2>&1
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1 --on mol-pr-from-issue" "armed args survive the round trip"

# --- RECONCILE: every arm that must NOT sling --------------------------------
echo "# reconcile withholds"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a blocked armed bead is not an error"
eq "$(slings)" "0" "a blocked armed bead is NOT slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "a blocked armed bead keeps its record"
has "$out" "1 waiting" "summary counts it as waiting"

store '[{"id":"b-1","status":"open","assignee":"someone/else","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a ready bead someone holds is NOT slung out from under them"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the held bead keeps its record"
has "$out" "HELD b-1" "the hold is reported, not silent"

# The two-state gc.dispatch_when_ready_slung marker. reconcile stamps it around
# its own sling: "slinging@<ts>" before (attempt in flight, unproven) and
# "slung@<ts>" once the sling returns success (proven). Recovery reads THIS one
# marker, not whatever stamp a given lane happened to leave (a plain pool sling
# shows as gc.routed_to, an --on pour as gc.execution_routed_to).

# Proven ("slung@"): the sling ran and the pass died before disarming — RETIRE,
# do not replay.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_slung":"slung@2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a proven (slung@) marker is NOT slung a second time"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the proven arm is retired instead"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "retiring clears the slung marker too"
has "$out" "already-dispatched" "the retire names the reason"

# Unproven ("slinging@"): a pass stamped the attempt and died before or during
# the sling, or a failed sling could not roll the marker back. The dispatch is
# NOT proven, so it must be RE-SLUNG, not retired — retiring here is the silent
# lost dispatch the two states exist to prevent, and one the blocked-work doctor
# check cannot catch because the blocker has lifted and the bead reads ready.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_slung":"slinging@2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "recovering an unconfirmed sling is a clean pass"
eq "$(slings)" "1" "an unproven (slinging@) marker is RE-SLUNG, not retired"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1" "the re-attempt reaches sling with the recorded target"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the record is cleared after the recovered dispatch"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "a completed dispatch leaves no slung marker behind"
has "$out" "1 dispatched" "summary counts the recovered dispatch"

# A bare-timestamp marker (no state prefix) is read as proven, so an arm already
# mid-dispatch when the two states arrived retires rather than re-slinging.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_slung":"2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a bare-timestamp (unprefixed) marker is read as proven and NOT re-slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the unprefixed marker retires the arm"
has "$out" "already-dispatched" "the retire names the reason"

# The pre-sling stamp is the UNPROVEN state: reconcile must write "slinging@"
# BEFORE it slings, or a crash mid-sling would recover as a retire and lose the
# dispatch. The sling stub records the marker as it stands at sling time.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
: > "$TMP/marker-at-sling.log"
STUB_SLING_MARKER_LOG="$TMP/marker-at-sling.log" "$SUT" reconcile >/dev/null 2>&1
has "$(cat "$TMP/marker-at-sling.log")" "slinging@" "reconcile stamps the unproven slinging@ marker BEFORE it slings"

# The marker is lane-agnostic: an --on arm proven slung retires on the same
# marker, with no argv inspection and no execution-route read, so it is not
# replayed into the graph.v2 live-workflow refusal.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/pool","gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]","gc.dispatch_when_ready_slung":"slung@2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an --on arm proven slung is NOT re-slung, exec route notwithstanding"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the proven --on arm is retired"
has "$out" "already-dispatched" "the retire names the reason"

# gc.execution_routed_to alone is NOT a dispatch reconcile reads: a bead armed
# while carrying only it (its workflow gone) is the doctor-flagged shape, and the
# arm remedy only works if reconcile SLINGS it when ready. No slung marker, so it
# dispatches — the exec-route provenance is ignored, not mistaken for a dispatch.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/old","gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "1" "an armed bead carrying only gc.execution_routed_to is slung, not retired"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1" "the exec-routed-only bead reaches sling with its recorded target"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the record is cleared after the dispatch"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "a completed dispatch leaves no slung marker behind"
has "$out" "1 dispatched" "summary counts the dispatch, not a retire"

# A fresh --on arm (no slung marker, pour not yet run) slings like any arm, and
# its recorded args reach gc sling in order.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "1" "a fresh --on arm with no slung marker is slung, not retired"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1 --on mol-polecat-work" "the not-yet-poured --on arm reaches sling with its recorded args"
has "$out" "1 dispatched" "summary counts the dispatch"

store '[{"id":"b-1","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a closed armed bead is NOT slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "a closed armed bead's record is retired"
has "$out" "1 retired" "summary counts the retire"

# --- RECONCILE: the parent-cascade fix (tk-so8clv) ---------------------------
# An armed OPEN bead whose own `blocks` edges have all closed is dispatchable
# even when `bd list --ready` excludes it: the is_blocked flag cascades DOWN
# parent-child edges, so an epic child under a container held on a human gate
# never enters --ready though its own work is ready. reconcile asks the bead's
# OWN blockers, not bd's claimability, and slings.
echo "# reconcile dispatches an arm held out of bd --ready only by an ancestor cascade"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"},{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "dispatching a cascade-held arm is a clean pass"
eq "$(slings)" "1" "an arm whose own blocks edges are all closed is slung though bd --ready excludes it"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1" "the cascade-held arm reaches sling with its recorded target"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the record is cleared after the dispatch"
has "$out" "unready only through a blocked/deferred ancestor" "reconcile names why it dispatched a not-ready bead"
has "$out" "1 dispatched" "summary counts the dispatch, not a wait"

# The narrowing guard: an OPEN own blocker still withholds. Only the bead's own
# blocks edges gate the arm, so a parent-child edge closing must never be
# mistaken for the thing the arm actually waits on.
echo "# reconcile still withholds an arm whose OWN blocker is open"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"},{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an arm with an open OWN blocker is NOT slung even if its parent-child edge is closed"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the still-blocked arm keeps its record"
has "$out" "1 waiting" "summary counts it as waiting"

# Fail closed: a blocker whose status cannot be resolved must leave an
# otherwise-dispatchable arm armed, never slung on a guess. The blocker bead is
# absent from the store, so the bulk status read (bd list --id) silently drops
# it — an unread blocker must not read as a released one.
echo "# an unresolvable own blocker fails closed (arm stays waiting)"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"b-0-missing","dependency_type":"blocks"}]}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an unresolvable own blocker leaves the otherwise-dispatchable arm un-slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the arm keeps its record when its own blocker cannot be resolved"
has "$out" "1 waiting" "an unresolved blocker counts as waiting, not dispatched"

# list surfaces the cascade-held state distinctly from a plain wait.
echo "# list labels a cascade-held arm as dispatchable"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" list 2>&1)"
has "$out" "DISPATCHABLE NOW (own blockers clear" "list flags the cascade-held arm as dispatchable, not waiting"

# --- the N+1 fix: a full pass costs a bounded number of bd reads --------------
# The stall this script's finding named: own_blocks_cleared ran a `bd dep list`
# per waiting arm and the reconcile loop ran a `bd show` per candidate, so a full
# pass scaled with the armed set and overran the reconcile order's 120s budget —
# the pass was killed before it dispatched, and an owed arm silently starved. A
# pass must now resolve every candidate's own blockers and read every candidate's
# fields WITHOUT a per-bead call: blocker ids come off the snapshot's own edges,
# one listing resolves their statuses, and each bead's fields come from the cached
# snapshot. This proves the whole set dispatches in reads that do not scale with
# the number of arms.
echo "# reconcile resolves the whole candidate set without a per-bead read"
export STUB_BD_LOG="$TMP/bd-bulk.log"
store '[
 {"id":"a-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"blk-1","dependency_type":"blocks"}]},
 {"id":"a-2","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"blk-2","dependency_type":"blocks"}]},
 {"id":"a-3","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"blk-3","dependency_type":"blocks"}]},
 {"id":"a-4","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"blk-4","dependency_type":"blocks"}]},
 {"id":"blk-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"blk-2","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"blk-3","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"blk-4","status":"closed","assignee":"","metadata":{},"notes":""}]'
: > "$STUB_BD_LOG"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a bulk pass over four cascade-held arms is a clean pass"
eq "$(slings)" "4" "all four arms whose own blockers are closed dispatch in one pass"
eq "$(grep -c '^dep list' "$STUB_BD_LOG")" "0" "reconcile makes NO per-bead dep-list call — the N+1 is gone"
eq "$(grep -c '^show' "$STUB_BD_LOG")" "0" "reconcile makes NO per-bead show call — fields come from the cached snapshot"
eq "$(grep -c '^list' "$STUB_BD_LOG")" "3" "the whole set costs three list reads (all + ready + one blocker-status batch), not one per bead"
unset STUB_BD_LOG

# --- the ARG_MAX fix: a large armed set enumerates, never dies on argv --------
# armed_rows used to hand the whole --ready snapshot to jq as a single --argjson
# value. That snapshot carries one row per armed bead, and a single argv
# argument past the kernel's per-argument size cap (128 KiB on Linux) aborts jq
# with "argument list too long" — so once the armed backlog held a few dozen
# full-body rows EVERY enumeration failed and nothing dispatched. The snapshots
# now reach jq over stdin, which has no such cap. The fixture is sized so the
# old argv pass provably dies (the positive control below), then the SUT must
# still enumerate and dispatch the whole set. The stub ignores --brief, so it
# feeds the SUT full-body rows — the payload the stdin path has to survive.
echo "# a large armed set enumerates and dispatches (no argv size cap)"
big_store="$(jq -nc '[ range(0;40)
  | {id:("big-\(.)"), status:"open", assignee:"",
     metadata:{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},
     notes:("x" * 8000), _ready:true} ]')"
store "$big_store"
ready_payload="$(gc bd list --has-metadata-key gc.dispatch_when_ready --ready --json --limit 0)"
if jq -n --argjson r "$ready_payload" '1' >/dev/null 2>&1; then
  bad "scale fixture too small: the --ready snapshot fits in one argv value, so it cannot exercise the cap"
else
  ok "scale fixture exceeds the kernel per-argument cap (the pre-fix --argjson pass dies here)"
fi
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list enumerates a large armed set without an argv failure"
hasnt "$out" "could not enumerate" "a large armed set does not read as 'could not enumerate'"
eq "$(printf '%s\n' "$out" | grep -c ' -> rig/pool ')" "40" "list reports every bead in the large armed set"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "reconcile completes a pass over a large armed set"
eq "$(slings)" "40" "reconcile dispatches every ready arm in the large set"

echo "# reconcile keeps the record when the sling fails"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$(STUB_SLING_RC=7 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a failed sling makes the pass exit non-zero"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "a failed sling LEAVES the record armed for the next pass"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "a failed sling rolls the slung marker back so the arm retries, not retires"
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "1" "a failed sling records one attempt against the retry cap"
has "$out" "sling of b-1 -> rig/pool failed" "the failure names the bead and target"

# --- the convoy-leak fix: already-delivered retire, and a capped retry ---------
# Each gc sling mints an input convoy, so an arm that never finalizes must not be
# re-slung forever. Two guards stop it: an arm whose work another path already
# delivered (a merge_result stamp) retires without slinging, and a sling that
# keeps failing is capped and escalated rather than leaking a convoy per pass.

echo "# reconcile retires an arm whose work another path already delivered"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","merge_result":"pull_request"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "retiring an already-delivered arm is a clean pass"
eq "$(slings)" "0" "an already-delivered bead is NOT slung — no redundant convoy"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the already-delivered arm is retired, not left to re-sling every pass"
has "$(notes b-1)" "work already delivered (merge_result=pull_request)" "the retire names the delivery it deferred to"
has "$out" "already-delivered b-1" "the retire is reported, not silent"
has "$out" "1 retired" "summary counts the delivered retire"

echo "# repeated non-finalizing slings are capped and escalated, not leaked one convoy per pass"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
STUB_SLING_RC=7 "$SUT" reconcile >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "1" "failing pass 1 counts one attempt"
STUB_SLING_RC=7 "$SUT" reconcile >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "2" "failing pass 2 counts a second attempt"
STUB_SLING_RC=7 "$SUT" reconcile >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "3" "failing pass 3 reaches the cap"
eq "$(escalations)" "0" "no escalation while still under the cap"
before=$(slings)
: > "$ESC_CALLS"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "$before" "a capped bead is NOT re-slung — the convoy-per-pass leak stops"
eq "$(escalations)" "1" "a capped bead is handed to a person exactly once"
eq "$(head -1 "$ESC_CALLS" | cut -f2)" "deferred-dispatch-sling-failed.b-1" "the escalation is keyed per bead, so repeated passes dedup to one visit"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "a capped bead keeps its arm for the person, never a silent retire"
has "$out" "CAPPED b-1" "the cap is reported"

echo "# a proven dispatch clears the accumulated fail count, resetting the budget"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_fail_count":"2"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "1" "a bead one short of the cap is still slung"
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "<absent>" "a proven dispatch clears the fail count so a later arm starts fresh"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "and the arm is retired"
has "$out" "1 dispatched" "summary counts the dispatch"

echo "# reconcile refuses a malformed arg list"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"not-json"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a malformed arg list does not produce a sling"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "a malformed arg list leaves the record for a human"
has "$out" "malformed" "the malformed record is reported"

# --- the false-empty-queue guard ---------------------------------------------
# This is the failure this script must not have. A dispatcher that cannot read
# its queue and prints "0 dispatched" is indistinguishable from one with nothing
# owed — which is exactly how a pending dispatch went missing before this
# existed. It must exit non-zero and say it could not see.
echo "# unreadable queue is not an empty queue"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$(STUB_BD_LIST_FAIL=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "an unreadable listing exits non-zero"
hasnt "$out" "0 dispatched, 0 retired" "an unreadable listing does NOT print a healthy-looking summary"
has "$out" "could not enumerate" "an unreadable listing says so"
eq "$(slings)" "0" "an unreadable listing slings nothing"

out="$(STUB_BD_LIST_FAIL=1 "$SUT" list 2>&1)"; rc=$?
eq "$rc" 1 "list also fails loudly on an unreadable store"

# --- the quiet path still passes ---------------------------------------------
# Tightening the guard above must not strand the ordinary no-work case.
echo "# quiet path"
store '[{"id":"b-9","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a store with nothing armed still passes"
has "$out" "0 dispatched" "and reports an honest empty pass"
eq "$(slings)" "0" "and slings nothing"
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list on a store with nothing armed passes"
has "$out" "no pending dispatches" "list says the queue is empty"

# --- list -------------------------------------------------------------------
echo "# list"
store '[
 {"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_reason":"needs b-0"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""},
 {"id":"b-2","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/other"},"notes":"","_ready":true},
 {"id":"b-3","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":"","_ready":false},
 {"id":"b-6","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","merge_result":"pull_request"},"notes":"","_ready":true},
 {"id":"b-7","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_fail_count":"3"},"notes":"","_ready":true},
 {"id":"b-4","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list exits 0"
has "$out" "b-1 -> rig/pool [waiting on a blocker] — needs b-0" "list shows a waiting arm with its reason"
has "$out" "b-2 -> rig/other [DISPATCHABLE NOW]" "list shows a dispatchable arm"
has "$out" "b-3 -> rig/pool [CLOSED" "list shows a closed arm"
has "$out" "b-6 -> rig/pool [DELIVERED — merge_result=pull_request" "list flags an already-delivered arm (will retire, not sling)"
has "$out" "b-7 -> rig/pool [CAPPED — 3 sling failures" "list flags a capped arm as needing a person"
hasnt "$out" "b-4" "list shows only armed beads"

# A held bead and a gated bead are both "not ready", and conflating them is
# what hides a dead arm: the gated one dispatches when its blocker closes, the
# held one never dispatches at all.
store '[
 {"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""},
 {"id":"b-5","status":"blocked","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":"","_ready":false}]'
out="$("$SUT" list 2>&1)"
has "$out" "b-5 -> rig/pool [STRANDED — status=blocked is never --ready]" "list names a stranded arm"
has "$out" "b-1 -> rig/pool [waiting on a blocker]" "an open arm is still just waiting"

echo "# reconcile names a stranded arm every pass"
# The arm outlives every session that could remember it, so a silent `waiting`
# count is how it stays lost. Reported on stderr and counted in the summary.
store '[{"id":"b-5","status":"blocked","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "reconcile exits 0 with a stranded arm (nothing failed)"
eq "$(slings)" "0" "a stranded arm is never slung"
has "$out" "STRANDED b-5" "reconcile names the stranded bead"
has "$out" "status=blocked" "and the status that strands it"
has "$out" "1 stranded" "the summary counts it apart from waiting"
eq "$(meta b-5 gc.dispatch_when_ready)" "rig/pool" "the record is kept, not retired — the hold may clear"

store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
has "$out" "1 waiting, 0 stranded" "an open gated arm counts as waiting, not stranded"
hasnt "$out" "STRANDED" "and is not reported as stranded"

# --- disarm ------------------------------------------------------------------
echo "# disarm"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_armed_by":"x","gc.dispatch_when_ready_armed_at":"t","gc.dispatch_when_ready_reason":"r","gc.dispatch_when_ready_slung":"t2"},"notes":"keep me","_ready":false}]'
out="$("$SUT" disarm b-1 --reason "superseded" 2>&1)"; rc=$?
eq "$rc" 0 "disarm exits 0"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "disarm clears the target"
eq "$(meta b-1 gc.dispatch_when_ready_args)" "<absent>" "disarm clears the args"
eq "$(meta b-1 gc.dispatch_when_ready_armed_by)" "<absent>" "disarm clears the actor"
eq "$(meta b-1 gc.dispatch_when_ready_armed_at)" "<absent>" "disarm clears the timestamp"
eq "$(meta b-1 gc.dispatch_when_ready_reason)" "<absent>" "disarm clears the reason"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "disarm clears the slung marker"
has "$(notes b-1)" "keep me" "disarm appends to notes rather than replacing"
has "$(notes b-1)" "superseded" "disarm records why"

# --- the store the reads are pinned to ---------------------------------------
# `gc bd` resolves its ledger from the invoking rig and ignores BEADS_DIR, so a
# rig-scoped pass that does not pin --db reads whatever rig gc resolves.
echo "# store pinning"
export STUB_BD_LOG="$TMP/bd.log"
store '[{"id":"p-1","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":""}]'

: > "$STUB_BD_LOG"
(GC_RIG_ROOT="$TMP/rigroot" "$SUT" reconcile >/dev/null 2>&1)
has "$(cat "$STUB_BD_LOG")" "--db $TMP/rigroot/.beads" "GC_RIG_ROOT pins the reads to that rig's store"

: > "$STUB_BD_LOG"
("$SUT" reconcile >/dev/null 2>&1)
hasnt "$(cat "$STUB_BD_LOG")" "--db" "with no GC_RIG_ROOT and no --db, nothing is pinned"

: > "$STUB_BD_LOG"
(GC_RIG_ROOT="$TMP/rigroot" "$SUT" reconcile --db "$TMP/explicit/.beads" >/dev/null 2>&1)
has "$(cat "$STUB_BD_LOG")" "--db $TMP/explicit/.beads" "an explicit --db overrides GC_RIG_ROOT"
hasnt "$(cat "$STUB_BD_LOG")" "--db $TMP/rigroot/.beads" "and the rig-root default is not also passed"
unset STUB_BD_LOG

# --- positive control over the shipped cadence -------------------------------
# The arm is only half the mechanism: without the order nothing consumes these
# records and the hold is stranded one layer down instead of in an agent's head.
echo "# shipped order"
ORDER="$ROOT/orders/deferred-dispatch.toml"
[ -s "$ORDER" ] && ok "orders/deferred-dispatch.toml ships" || bad "orders/deferred-dispatch.toml is missing"
o="$(cat "$ORDER" 2>/dev/null)"
has "$o" 'trigger = "cooldown"' "the order is cooldown-triggered"
has "$o" 'scope = "rig"' "the order is rig-scoped (one store per registration)"
has "$o" 'deferred-dispatch.sh reconcile' "the order runs this script's reconcile verb"
if grep -qE '^[[:space:]]*no_work_gate' "$ORDER"; then
    bad "the order does not opt out of the single-flight gate (no_work_gate is set)"
else
    ok "the order does not opt out of the single-flight gate"
fi

# ── scratch cleanup ─────────────────────────────────────────────────────────
# The EXIT trap reads a registry the allocations append to. Appending from a
# command substitution mutates a subshell's copy and the trap then removes
# nothing, so the cleanup has to be asserted on disk rather than read off the
# presence of a trap line.
SCRATCH="$TMP/scratch"
mkdir -p "$SCRATCH"
TMPDIR="$SCRATCH" "$SUT" list                >/dev/null 2>&1
TMPDIR="$SCRATCH" "$SUT" list --json         >/dev/null 2>&1
TMPDIR="$SCRATCH" "$SUT" reconcile           >/dev/null 2>&1
TMPDIR="$SCRATCH" "$SUT" reconcile --dry-run >/dev/null 2>&1
LEFT=$(find "$SCRATCH" -maxdepth 1 -name 'gctk-deferred-dispatch.*' 2>/dev/null | wc -l)
eq "$LEFT" "0" "no verb leaves a staging file behind in TMPDIR"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
