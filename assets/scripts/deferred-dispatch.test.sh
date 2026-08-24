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
#   * arm's fail-closed refusals — already dispatched, closed, no target;
#   * the dispatch arm: ready + armed -> exactly one `gc sling` with the
#     recorded target and pass-through args, then the record cleared;
#   * every arm that must NOT sling: still blocked, already routed (the
#     crash-between-sling-and-disarm case), assignee held, sling failed;
#   * the closed-bead retire arm;
#   * the FALSE-EMPTY-QUEUE guard — an unreadable listing exits non-zero
#     instead of printing a summary byte-identical to a healthy empty queue.
#     That fail-open is the exact class this script must not have: it is a
#     dispatcher, and a silent "nothing was owed" is how the hold went missing
#     in the first place;
#   * the QUIET PATH — an empty store still passes, so the guard above did not
#     strand the ordinary no-work case;
#   * a POSITIVE CONTROL over the shipped order file, so a passing suite cannot
#     mean the cadence that consumes these records was quietly un-shipped;
#   * doctor/check-deferred-dispatch-wired, both arms — the shipped pack passes,
#     and each way the two halves can come apart is caught. Those cases live
#     HERE rather than in a check-deferred-dispatch-wired.test.sh of their own:
#     this pack has no test discovery, suites are invoked by name, and one file
#     covering the whole mechanism is one a reviewer touching either half will
#     actually run.
#
# No live city, Dolt, network, gc or bd — only jq, stubs, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/deferred-dispatch.sh"
TMP="$(mktemp -d)"
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
# Minimal bd stub over $STORE. Understands only the calls the SUT makes.
set -u
STORE="${STUB_STORE:?}"
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
    # Selective failures. The feeder makes two DIFFERENT reads with different
    # consequences — the candidate listing (--ready) and the in-flight count
    # (--has-metadata-key ... --all) — and reading either as empty is its own
    # distinct bug. A single blunt STUB_BD_LIST_FAIL cannot tell them apart,
    # and the in-flight one is the dangerous half: read as 0 it does not
    # under-report, it hands the pass a full budget.
    if [ -n "${STUB_BD_FAIL_READY:-}" ] && [ "$ready" = "1" ]; then
      echo "bd: simulated ready-listing failure" >&2; exit 1
    fi
    if [ -n "${STUB_BD_FAIL_METAKEY:-}" ] && [ -n "$key" ] && [ "$ready" = "0" ]; then
      echo "bd: simulated metadata-key listing failure" >&2; exit 1
    fi
    jq -c --arg k "$key" --arg id "$id" --argjson ready "$ready" --argjson all "$all" '
      [ .[]
        | select($k == "" or (.metadata | has($k)))
        | select($id == "" or .id == $id)
        | select($all == 1 or .status != "closed")
        | select($ready == 0 or (._ready == true))
        | del(._ready) ]' "$STORE"
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
    tmp="$(mktemp)"
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
  *) echo "bd stub: unsupported '${1:-}'" >&2; exit 2 ;;
esac
STUB

cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = "sling" ]; then
    shift
    printf '%s\n' "$*" >> "${STUB_SLING_LOG:?}"
    exit "${STUB_SLING_RC:-0}"
fi
echo "gc stub: unsupported '${1:-}'" >&2; exit 2
STUB
chmod +x "$BIN/bd" "$BIN/gc"

export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/beads.json"
export STUB_SLING_LOG="$TMP/sling.log"
export BEADS_ACTOR="test-actor"
unset GC_AGENT GC_RIG 2>/dev/null || true

store() { printf '%s' "$1" > "$STUB_STORE"; : > "$STUB_SLING_LOG"; }
meta()  { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
notes() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STUB_STORE"; }
slings() { wc -l < "$STUB_SLING_LOG" | tr -d ' '; }

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

echo "# arm refusals"
store '[{"id":"b-2","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/pool"},"notes":"","_ready":true}]'
out="$("$SUT" arm b-2 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead already dispatched"
eq "$(meta b-2 gc.dispatch_when_ready)" "<absent>" "refused arm writes nothing"
has "$out" "already dispatched" "refusal names the reason"

store '[{"id":"b-3","status":"closed","assignee":"","metadata":{},"notes":"","_ready":false}]'
out="$("$SUT" arm b-3 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a closed bead"

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
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false}]'
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

store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/pool","gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an already-routed bead is NOT slung a second time"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the stale record is retired instead"
has "$out" "already-dispatched" "the retire names the reason"

store '[{"id":"b-1","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a closed armed bead is NOT slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "a closed armed bead's record is retired"
has "$out" "1 retired" "summary counts the retire"

echo "# reconcile keeps the record when the sling fails"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$(STUB_SLING_RC=7 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a failed sling makes the pass exit non-zero"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "a failed sling LEAVES the record armed for the next pass"
has "$out" "sling of b-1 -> rig/pool failed" "the failure names the bead and target"

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
 {"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_reason":"needs b-0"},"notes":"","_ready":false},
 {"id":"b-2","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/other"},"notes":"","_ready":true},
 {"id":"b-3","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":"","_ready":false},
 {"id":"b-4","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list exits 0"
has "$out" "b-1 -> rig/pool [waiting on a blocker] — needs b-0" "list shows a waiting arm with its reason"
has "$out" "b-2 -> rig/other [DISPATCHABLE NOW]" "list shows a dispatchable arm"
has "$out" "b-3 -> rig/pool [CLOSED" "list shows a closed arm"
hasnt "$out" "b-4" "list shows only armed beads"

# --- disarm ------------------------------------------------------------------
echo "# disarm"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_armed_by":"x","gc.dispatch_when_ready_armed_at":"t","gc.dispatch_when_ready_reason":"r"},"notes":"keep me","_ready":false}]'
out="$("$SUT" disarm b-1 --reason "superseded" 2>&1)"; rc=$?
eq "$rc" 0 "disarm exits 0"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "disarm clears the target"
eq "$(meta b-1 gc.dispatch_when_ready_args)" "<absent>" "disarm clears the args"
eq "$(meta b-1 gc.dispatch_when_ready_armed_by)" "<absent>" "disarm clears the actor"
eq "$(meta b-1 gc.dispatch_when_ready_armed_at)" "<absent>" "disarm clears the timestamp"
eq "$(meta b-1 gc.dispatch_when_ready_reason)" "<absent>" "disarm clears the reason"
has "$(notes b-1)" "keep me" "disarm appends to notes rather than replacing"
has "$(notes b-1)" "superseded" "disarm records why"


# --- THE FEEDER --------------------------------------------------------------
# The input half (tk-ku1uvv). Everything above this line was already true on
# 2026-08-24 and the queue still did not move: `arm` worked, `reconcile` worked,
# and NOTHING EVER CALLED ARM. 252 ready work beads sat unrouted, 51 of them
# over 30 days old, while `list` correctly reported an empty owed-queue. The
# machine ran; the hopper was empty.
#
# So the feeder is tested HERE, in the suite that already owns this mechanism,
# rather than in a dispatch-feeder.test.sh of its own: this pack has no test
# discovery, suites are invoked by name, and the feeder cannot be reasoned
# about apart from the arm it calls. Several cases below run the REAL
# deferred-dispatch.sh as the feeder's arm tool, which is the point — a feeder
# that stopped being a caller of `arm` would be a second dispatch path, and
# that is the one thing it must never become.
echo "# feeder"
FEEDER="$HERE/dispatch-feeder.sh"
[ -x "$FEEDER" ] || chmod +x "$FEEDER" 2>/dev/null
export DISPATCH_FEEDER_TARGET="rig/pool"

feed() { "$FEEDER" feed "$@" 2>&1; }
armedcount() { jq -r '[ .[] | select(.metadata["gc.dispatch_when_ready"] != null) ] | length' "$STUB_STORE"; }
# A plain candidate: ready, open, unassigned, no machinery markers.
cand() { printf '{"id":"%s","status":"open","assignee":"","issue_type":"%s","created_at":"%s","labels":[],"metadata":{},"notes":"","_ready":true}' "$1" "${3:-task}" "$2"; }

# --- FEEDOLDEST: the 31d+ tail drains, it does not starve ---------------------
# The whole reason the queue had a 123-day-old head is that nothing was working
# it. A feeder that took the newest ready bead, or the highest priority, would
# leave exactly the beads that motivated this file untouched forever.
store "[$(cand w-new 2026-08-20T00:00:00Z), $(cand w-old 2026-04-23T00:00:00Z bug), $(cand w-mid 2026-06-01T00:00:00Z)]"
out="$(feed)"; rc=$?
eq "$rc" 0 "FEEDOLDEST: a clean pass exits 0"
eq "$(meta w-old gc.dispatch_when_ready)" "rig/pool" "FEEDOLDEST: the OLDEST candidate is armed"
eq "$(meta w-mid gc.dispatch_when_ready)" "<absent>" "FEEDOLDEST: the middle one is not"
eq "$(meta w-new gc.dispatch_when_ready)" "<absent>" "FEEDOLDEST: the newest one is not"
has "$out" "armed w-old" "FEEDOLDEST: the pass says which bead it armed"

# --- FEEDARM: a caller of arm, never a second dispatch path -------------------
# Calling `gc sling` from the feeder would bypass BOTH fail-closed layers that
# already exist — arm's refusals (closed, already dispatched, no target) and
# reconcile's (held, already routed) — and re-implement a dispatcher that is
# already written and already tested above.
eq "$(slings)" "0" "FEEDARM: the feeder never slings — it arms, and reconcile slings"
eq "$(meta w-old gc.auto_armed_by)" "dispatch-feeder" "FEEDARM: the feeder stamps its own reservation marker"
has "$(meta w-old gc.auto_armed_at)" "T" "FEEDARM: and when it did so"
has "$(meta w-old gc.dispatch_when_ready_reason)" "auto-armed by dispatch-feeder" "FEEDARM: the arm records that a feeder placed it, not a human"
# ...and the record it wrote is one the SHIPPED reconcile pass actually performs.
# This is the end-to-end claim: feeder -> arm -> reconcile -> sling.
out="$("$SUT" reconcile 2>&1)"
eq "$(slings)" "1" "FEEDARM: reconcile slings the bead the feeder armed"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool w-old" "FEEDARM: to the target the feeder recorded"
eq "$(meta w-old gc.auto_armed_by)" "dispatch-feeder" "FEEDARM: reconcile clears the arm but LEAVES the feeder's marker — without it a dispatched bead would vanish from the cap"

# --- FEEDRESERVE: the cap counts committed work, not pending arms -------------
# The case that explains why the feeder keeps a marker of its own instead of
# counting gc.dispatch_when_ready. Reconcile CLEARS that key the instant it
# slings, so counting it would show every dispatched bead leaving the tally
# within one 2m tick and the cap would bind on nothing — the feeder would keep
# arming into a pool that is already full, which is the unbounded feeder this
# design exists to not be.
store "[{\"id\":\"w-gone\",\"status\":\"open\",\"assignee\":\"\",\"issue_type\":\"task\",\"created_at\":\"2026-01-01T00:00:00Z\",\"labels\":[],\"metadata\":{\"gc.auto_armed_by\":\"dispatch-feeder\",\"gc.routed_to\":\"rig/pool\"},\"notes\":\"\",\"_ready\":true}, $(cand w-next 2026-02-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=1 feed)"; rc=$?
eq "$rc" 0 "FEEDRESERVE: being at cap is not an error"
eq "$(meta w-next gc.dispatch_when_ready)" "<absent>" "FEEDRESERVE: a dispatched bead whose arm was already consumed STILL holds its slot"
has "$out" "at cap" "FEEDRESERVE: the pass says it is at cap"


# --- FEEDSTALL: a reservation is an ATTEMPT, not committed work -------------
# Reported P1 on review bead tk-ib2yl2. The two writes that place a bead in the
# pipeline — stamping the marker and calling arm — cannot be atomic, and the
# first cut counted the marker ALONE as committed work. A pass interrupted
# between them left a bead holding a slot forever: the budget gate returns
# before candidates are enumerated, so the reservation this file called
# "self-healing" was never revisited. At MAX_IN_FLIGHT=1 — the value the order
# file recommends for leaving room for hand-slung work — one interrupted pass
# wedged the feeder permanently, and it printed "at cap, arming nothing this
# pass" and exited 0 every tick while doing it. A silent stall that reports
# healthy is the failure this whole mechanism exists to end.
echo "# feeder: stranded reservations"
strand() { # a bead wearing the marker and NOTHING else — the crash state
    printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","created_at":"%s","labels":[],"metadata":{"gc.auto_armed_by":"dispatch-feeder","gc.auto_armed_at":"t"},"notes":"","_ready":true}' "$1" "$2"
}

store "[$(strand w-stranded 2026-01-01T00:00:00Z), $(cand w-next 2026-02-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=1 feed)"; rc=$?
eq "$rc" 0 "FEEDSTALL: a pass over a stranded reservation is not an error"
eq "$(meta w-stranded gc.dispatch_when_ready)" "rig/pool" "FEEDSTALL: the stranded reservation is RE-ARMED, not left holding a slot"
hasnt "$out" "at cap" "FEEDSTALL: and the pass does not report itself at cap"

# The stall was permanent, so one pass is not proof. Run it again: the re-armed
# bead now holds the only slot legitimately, and the pass says so.
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=1 feed)"
has "$out" "at cap" "FEEDSTALL: the NEXT pass is at cap, because the re-armed bead now genuinely holds it"
eq "$(meta w-next gc.dispatch_when_ready)" "<absent>" "FEEDSTALL: and the cap still binds — the fix did not simply disable it"

# Every shape that IS committed work must still hold its slot, or the fix would
# have traded a stall for an uncapped feeder. These are the three kinds of
# evidence, one case each.
store "[{\"id\":\"w-armed\",\"status\":\"open\",\"assignee\":\"\",\"issue_type\":\"task\",\"created_at\":\"2026-01-01T00:00:00Z\",\"labels\":[],\"metadata\":{\"gc.auto_armed_by\":\"dispatch-feeder\",\"gc.dispatch_when_ready\":\"rig/pool\"},\"notes\":\"\",\"_ready\":false}, $(cand w-next 2026-02-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=1 feed)"
eq "$(meta w-next gc.dispatch_when_ready)" "<absent>" "FEEDSTALL: an ARMED bead holds its slot"

store "[{\"id\":\"w-routed\",\"status\":\"open\",\"assignee\":\"\",\"issue_type\":\"task\",\"created_at\":\"2026-01-01T00:00:00Z\",\"labels\":[],\"metadata\":{\"gc.auto_armed_by\":\"dispatch-feeder\",\"gc.routed_to\":\"rig/pool\"},\"notes\":\"\",\"_ready\":true}, $(cand w-next 2026-02-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=1 feed)"
eq "$(meta w-next gc.dispatch_when_ready)" "<absent>" "FEEDSTALL: a DISPATCHED bead holds its slot (its arm was consumed by reconcile)"

store "[{\"id\":\"w-held\",\"status\":\"open\",\"assignee\":\"rig/gc-toolkit.refinery\",\"issue_type\":\"task\",\"created_at\":\"2026-01-01T00:00:00Z\",\"labels\":[],\"metadata\":{\"gc.auto_armed_by\":\"dispatch-feeder\"},\"notes\":\"\",\"_ready\":false}, $(cand w-next 2026-02-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=1 feed)"
eq "$(meta w-next gc.dispatch_when_ready)" "<absent>" "FEEDSTALL: a bead HELD BY AN ASSIGNEE holds its slot (handed on to the refinery)"

# The end-to-end shape of the incident: a real interrupted pass, not a
# hand-written fixture. Kill the arm so mark_reserved lands and the arm never
# does, then prove the next pass recovers on its own at MAX_IN_FLIGHT=1.
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
KILLARM="$TMP/killarm.sh"
printf '#!/usr/bin/env bash\nexit 9\n' > "$KILLARM"; chmod +x "$KILLARM"
DISPATCH_FEEDER_ARM_TOOL="$KILLARM" DISPATCH_FEEDER_MAX_IN_FLIGHT=1 feed >/dev/null 2>&1
# rollback releases the marker on a clean failure, so re-strand it by hand to
# model the case rollback cannot cover: the process dying outright.
"$BIN/bd" update w-1 --set-metadata gc.auto_armed_by=dispatch-feeder --set-metadata gc.auto_armed_at=t >/dev/null 2>&1
eq "$(meta w-1 gc.auto_armed_by)" "dispatch-feeder" "FEEDSTALL: (fixture) the bead is left mid-reservation, as a killed pass would leave it"
eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDSTALL: (fixture) with nothing armed"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=1 feed)"; rc=$?
eq "$rc" 0 "FEEDSTALL: the pass after a killed one succeeds"
eq "$(meta w-1 gc.dispatch_when_ready)" "rig/pool" "FEEDSTALL: and the killed pass's bead reaches the pipeline after all"

# status must NAME what holds each slot. "At cap" with nothing to point at is
# what made the stranded reservation invisible for as long as it lasted.
store "[{\"id\":\"w-routed\",\"status\":\"open\",\"assignee\":\"\",\"issue_type\":\"task\",\"created_at\":\"2026-01-01T00:00:00Z\",\"labels\":[],\"metadata\":{\"gc.auto_armed_by\":\"dispatch-feeder\",\"gc.routed_to\":\"rig/pool\"},\"notes\":\"\",\"_ready\":false}]"
out="$("$FEEDER" status 2>&1)"
has "$out" "w-routed" "FEEDSTALL: status names the bead holding the slot"
has "$out" "dispatched" "FEEDSTALL: and says what is holding it"

# --- FEEDCAP: the in-flight cap binds ----------------------------------------
store "[{\"id\":\"w-a\",\"status\":\"open\",\"assignee\":\"\",\"issue_type\":\"task\",\"created_at\":\"2026-01-01T00:00:00Z\",\"labels\":[],\"metadata\":{\"gc.auto_armed_by\":\"dispatch-feeder\",\"gc.dispatch_when_ready\":\"rig/pool\"},\"notes\":\"\",\"_ready\":false}, $(cand w-b 2026-02-01T00:00:00Z), $(cand w-c 2026-03-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=2 DISPATCH_FEEDER_MAX_PER_TICK=9 feed)"
eq "$(armedcount)" "2" "FEEDCAP: one slot free means exactly one NEW arm, whatever the per-tick cap allows (w-a's own arm is the other)"
eq "$(meta w-b gc.dispatch_when_ready)" "rig/pool" "FEEDCAP: and it is the oldest candidate"

# A CLOSED auto-armed bead is finished work and must free its slot, or the
# feeder arms once per rig and then stops forever.
store "[{\"id\":\"w-done\",\"status\":\"closed\",\"assignee\":\"\",\"issue_type\":\"task\",\"created_at\":\"2026-01-01T00:00:00Z\",\"labels\":[],\"metadata\":{\"gc.auto_armed_by\":\"dispatch-feeder\"},\"notes\":\"\",\"_ready\":false}, $(cand w-b 2026-02-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=1 feed)"
eq "$(meta w-b gc.dispatch_when_ready)" "rig/pool" "FEEDCAP: a CLOSED auto-armed bead releases its slot"

# --- FEEDTICK: the per-tick cap is a separate bound ---------------------------
# The backstop against a cold start emptying half a 252-deep queue into the
# pool in a single pass, even with the in-flight cap raised.
store "[$(cand w-1 2026-01-01T00:00:00Z), $(cand w-2 2026-02-01T00:00:00Z), $(cand w-3 2026-03-01T00:00:00Z), $(cand w-4 2026-04-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=99 DISPATCH_FEEDER_MAX_PER_TICK=2 feed)"
eq "$(armedcount)" "2" "FEEDTICK: at most MAX_PER_TICK arms per pass, however many slots are free"
eq "$(meta w-1 gc.dispatch_when_ready)" "rig/pool" "FEEDTICK: oldest first within the tick budget"
eq "$(meta w-2 gc.dispatch_when_ready)" "rig/pool" "FEEDTICK: then the next oldest"
eq "$(meta w-3 gc.dispatch_when_ready)" "<absent>" "FEEDTICK: and no further"

# --- FEEDOFF: the operator's off switch --------------------------------------
# Acceptance criterion from the bead: turning the flag off stops all
# auto-arming AND leaves hand-slung work unaffected.
store "[$(cand w-1 2026-01-01T00:00:00Z), {\"id\":\"w-hand\",\"status\":\"open\",\"assignee\":\"\",\"issue_type\":\"task\",\"created_at\":\"2026-02-01T00:00:00Z\",\"labels\":[],\"metadata\":{\"gc.dispatch_when_ready\":\"rig/other\",\"gc.dispatch_when_ready_args\":\"[]\"},\"notes\":\"\",\"_ready\":true}]"
out="$(DISPATCH_FEEDER_ENABLED=0 feed)"; rc=$?
eq "$rc" 0 "FEEDOFF: a disabled feeder is not an error"
eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDOFF: disabled arms nothing"
eq "$(meta w-hand gc.dispatch_when_ready)" "rig/other" "FEEDOFF: a hand-written arm is left completely alone"
has "$out" "disabled" "FEEDOFF: the pass says it is disabled rather than reporting an empty queue"
for v in false FALSE no off 0; do
    store "[$(cand w-1 2026-01-01T00:00:00Z)]"
    DISPATCH_FEEDER_ENABLED="$v" feed >/dev/null 2>&1
    eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDOFF: DISPATCH_FEEDER_ENABLED=$v also disables"
done
# ...and the mirror. Without these the refusal above could widen to swallow the
# on-values and every rig would go quiet with the flag apparently set to on.
for v in 1 true TRUE yes on; do
    store "[$(cand w-1 2026-01-01T00:00:00Z)]"
    DISPATCH_FEEDER_ENABLED="$v" feed >/dev/null 2>&1
    eq "$(meta w-1 gc.dispatch_when_ready)" "rig/pool" "FEEDOFF: DISPATCH_FEEDER_ENABLED=$v still ARMS"
done

# --- FEEDEXCL: everything that must not be auto-slung ------------------------
# Each of these was measured in the live gc-toolkit ready listing on 2026-08-24
# (330 ready beads, 188 excluded). The step-bead case is the one that matters
# most: 67 of the 330 were formula STEP beads, and arming one pours a workflow
# onto a bead that is already inside a workflow.
store '[
 {"id":"x-epic","status":"open","assignee":"","issue_type":"epic","created_at":"2026-01-01T00:00:00Z","labels":[],"metadata":{},"notes":"","_ready":true},
 {"id":"x-convoy","status":"open","assignee":"","issue_type":"convoy","created_at":"2026-01-02T00:00:00Z","labels":[],"metadata":{},"notes":"","_ready":true},
 {"id":"x-spec","status":"open","assignee":"","issue_type":"spec","created_at":"2026-01-03T00:00:00Z","labels":[],"metadata":{},"notes":"","_ready":true},
 {"id":"x-step","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-04T00:00:00Z","labels":[],"metadata":{"gc.step_ref":"mol-polecat-work.implement"},"notes":"","_ready":true},
 {"id":"x-stepid","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-05T00:00:00Z","labels":[],"metadata":{"gc.step_id":"mol-polecat-work.implement"},"notes":"","_ready":true},
 {"id":"x-root","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-06T00:00:00Z","labels":[],"metadata":{"gc.root_bead_id":"r-1"},"notes":"","_ready":true},
 {"id":"x-kind","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-07T00:00:00Z","labels":[],"metadata":{"gc.kind":"scope-check"},"notes":"","_ready":true},
 {"id":"x-routed","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-08T00:00:00Z","labels":[],"metadata":{"gc.routed_to":"rig/pool"},"notes":"","_ready":true},
 {"id":"x-exec","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-09T00:00:00Z","labels":[],"metadata":{"gc.execution_routed_to":"rig/pool"},"notes":"","_ready":true},
 {"id":"x-armed","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-10T00:00:00Z","labels":[],"metadata":{"gc.dispatch_when_ready":"rig/other"},"notes":"","_ready":true},
 {"id":"x-takeaway","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-11T00:00:00Z","labels":[],"metadata":{"gc.takeaway":"next sitting"},"notes":"","_ready":true},
 {"id":"x-hold","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-12T00:00:00Z","labels":[],"metadata":{"triage.hold":"operator"},"notes":"","_ready":true},
 {"id":"x-assigned","status":"open","assignee":"rig/somebody","issue_type":"task","created_at":"2026-01-13T00:00:00Z","labels":[],"metadata":{},"notes":"","_ready":true},
 {"id":"x-kind2","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-14T00:00:00Z","labels":[],"metadata":{"task_kind":"review"},"notes":"","_ready":true},
 {"id":"x-kind3","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-15T00:00:00Z","labels":[],"metadata":{"task_kind":"invented-next-month"},"notes":"","_ready":true},
 {"id":"x-label","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-16T00:00:00Z","labels":["hold:mayor"],"metadata":{},"notes":"","_ready":true},
 {"id":"x-blocked","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-17T00:00:00Z","labels":[],"metadata":{},"notes":"","_ready":false},
 {"id":"y-ok","status":"open","assignee":"","issue_type":"task","created_at":"2026-01-18T00:00:00Z","labels":[],"metadata":{},"notes":"","_ready":true},
 {"id":"y-impl","status":"open","assignee":"","issue_type":"bug","created_at":"2026-01-19T00:00:00Z","labels":[],"metadata":{"task_kind":"implementation"},"notes":"","_ready":true}]'
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=9 DISPATCH_FEEDER_MAX_PER_TICK=9 feed)"
eq "$(armedcount)" "3" "FEEDEXCL: only the real candidates are armed (2 fresh + the pre-existing hand arm)"
eq "$(meta y-ok gc.dispatch_when_ready)" "rig/pool" "FEEDEXCL: ordinary ready work IS armed"
eq "$(meta y-impl gc.dispatch_when_ready)" "rig/pool" "FEEDEXCL: task_kind=implementation is ordinary work"
eq "$(meta x-armed gc.dispatch_when_ready)" "rig/other" "FEEDEXCL: an already-armed bead keeps its original target"
for x in x-epic x-convoy x-spec x-step x-stepid x-root x-kind x-routed x-exec x-takeaway x-hold x-assigned x-kind2 x-kind3 x-label x-blocked; do
    eq "$(meta $x gc.auto_armed_by)" "<absent>" "FEEDEXCL: $x is excluded"
done

# --- FEEDBLIND: an unreadable queue is not an empty queue ---------------------
# The failure this whole mechanism exists against, from the input side. A
# feeder that cannot see the queue and prints "0 armed" is indistinguishable
# from one with nothing to do — and "nothing was ready" being a lie nobody
# could detect is precisely how 252 beads aged out.
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(STUB_BD_FAIL_READY=1 feed)"; rc=$?
eq "$rc" 1 "FEEDBLIND: an unreadable candidate listing exits non-zero"
eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDBLIND: and arms nothing"
has "$out" "NOT treating this as an empty queue" "FEEDBLIND: and says it could not see"
hasnt "$out" "0 armed" "FEEDBLIND: and does NOT print a healthy-looking summary"

# --- FEEDCOUNT: an unreadable cap is not a free cap ---------------------------
# The dangerous half. An unreadable candidate listing under-delivers; an
# unreadable IN-FLIGHT count read as 0 hands the pass a full budget and blows
# the cap, which turns this file into the spend incident it was written to
# avoid. It must refuse, not proceed.
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(STUB_BD_FAIL_METAKEY=1 feed)"; rc=$?
eq "$rc" 1 "FEEDCOUNT: an unreadable in-flight count exits non-zero"
eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDCOUNT: and arms NOTHING — it is not read as 'zero in flight'"
has "$out" "blow the cap" "FEEDCOUNT: and says why refusing is the safe answer"

# --- FEEDBADCAP: a cap that cannot be parsed is not a cap ---------------------
# The first thing anyone does with these knobs is lower them. A typo silently
# restoring the default would be indistinguishable from the override working.
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT=two feed)"; rc=$?
eq "$rc" 2 "FEEDBADCAP: a non-numeric in-flight cap is a usage error"
eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDBADCAP: and nothing is armed under an unparseable cap"
out="$(DISPATCH_FEEDER_MAX_PER_TICK=-1 feed)"; rc=$?
eq "$rc" 2 "FEEDBADCAP: a non-numeric per-tick cap is a usage error too"
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_TARGET= feed)"; rc=$?
eq "$rc" 2 "FEEDBADCAP: an empty target refuses rather than arming a dispatch with no destination"
eq "$(meta w-1 gc.auto_armed_by)" "<absent>" "FEEDBADCAP: and reserves nothing under an empty target"
# Every knob is read with ${VAR-default}, never ${VAR:-default}: the colon form
# silently restores the default on an explicitly-empty override, which reads
# exactly like the override working. These three cases are what keep it that
# way — under the colon form each of them passes as a no-op instead.
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_IN_FLIGHT= feed)"; rc=$?
eq "$rc" 2 "FEEDBADCAP: an EMPTY in-flight cap refuses instead of silently restoring the default"
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_MAX_PER_TICK= feed)"; rc=$?
eq "$rc" 2 "FEEDBADCAP: an EMPTY per-tick cap refuses too"
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_ENABLED=maybe feed)"; rc=$?
eq "$rc" 2 "FEEDBADCAP: an unrecognised enable flag refuses rather than guessing"
eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDBADCAP: and arms nothing while it is unreadable"
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_ENABLED= feed)"; rc=$?
eq "$rc" 2 "FEEDBADCAP: an EMPTY enable flag is not silently 'on'"

# --- FEEDROLLBACK: a failed arm releases the slot it reserved ----------------
# The reservation is written BEFORE the arm, so the cap can never leak. The
# price is that a refused arm must give the slot back, or a bead that is not
# ours holds capacity until it closes. `arm` refuses beads that were closed or
# dispatched between our listing and the call, so this path is ordinary, not
# exotic.
FAILARM="$TMP/failarm.sh"
printf '#!/usr/bin/env bash\nexit 9\n' > "$FAILARM"; chmod +x "$FAILARM"
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_ARM_TOOL="$FAILARM" feed)"; rc=$?
eq "$rc" 1 "FEEDROLLBACK: a failed arm makes the pass exit non-zero"
eq "$(meta w-1 gc.auto_armed_by)" "<absent>" "FEEDROLLBACK: the reserved slot is released"
eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDROLLBACK: and nothing is armed"
has "$out" "slot released" "FEEDROLLBACK: the release is reported"

# A refusal does NOT spend the budget — the next candidate is tried, because a
# refusal here is a race (arm refuses closed/in_progress/routed beads, all of
# which also drop out of the next ready listing) and not a durable state.
store "[$(cand w-1 2026-01-01T00:00:00Z), $(cand w-2 2026-02-01T00:00:00Z)]"
FLAKYARM="$TMP/flakyarm.sh"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = "w-1" ] && exit 9; done\nexec %s "$@"\n' "$SUT" > "$FLAKYARM"
chmod +x "$FLAKYARM"
out="$(DISPATCH_FEEDER_ARM_TOOL="$FLAKYARM" feed)"
eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDROLLBACK: the refused candidate is not armed"
eq "$(meta w-1 gc.auto_armed_by)" "<absent>" "FEEDROLLBACK: and gives its slot back"
eq "$(meta w-2 gc.dispatch_when_ready)" "rig/pool" "FEEDROLLBACK: a refusal does not spend the budget — the next candidate is still armed"

# ...but "try the next one" must be BOUNDED. A systemic failure (bd writes
# failing, a store read-only mid-migration) would otherwise have one pass
# attempt all 145 candidates at three writes each and run into the order
# timeout, so the pass is killed instead of reporting what it found.
store "[$(cand w-1 2026-01-01T00:00:00Z), $(cand w-2 2026-02-01T00:00:00Z), $(cand w-3 2026-03-01T00:00:00Z), $(cand w-4 2026-04-01T00:00:00Z), $(cand w-5 2026-05-01T00:00:00Z), $(cand w-6 2026-06-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_ARM_TOOL="$FAILARM" DISPATCH_FEEDER_MAX_IN_FLIGHT=9 DISPATCH_FEEDER_MAX_PER_TICK=9 feed)"; rc=$?
eq "$rc" 1 "FEEDROLLBACK: a wholly broken arm makes the pass exit non-zero"
has "$out" "consecutive failures" "FEEDROLLBACK: and stops rather than grinding the whole queue into the order timeout"
eq "$(printf '%s' "$out" | grep -c 'slot released')" "3" "FEEDROLLBACK: it stops after MAX_CONSEC_FAIL attempts, not after all six candidates"

store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(DISPATCH_FEEDER_ARM_TOOL="$TMP/nope.sh" feed)"; rc=$?
eq "$rc" 2 "FEEDROLLBACK: a missing arm tool refuses the whole pass"
eq "$(meta w-1 gc.auto_armed_by)" "<absent>" "FEEDROLLBACK: with no second dispatch path to fall back on"
has "$out" "no second dispatch path" "FEEDROLLBACK: and says so"

# --- FEEDQUIET: the guards above did not strand the ordinary case ------------
# Every refusal added above is a chance to break the empty-board pass, which is
# the pass that runs most of the time.
store '[{"id":"x-only","status":"open","assignee":"","issue_type":"epic","created_at":"2026-01-01T00:00:00Z","labels":[],"metadata":{},"notes":"","_ready":true}]'
out="$(feed)"; rc=$?
eq "$rc" 0 "FEEDQUIET: a store with no candidates still passes"
has "$out" "0 armed" "FEEDQUIET: and reports an honest empty pass"
eq "$(armedcount)" "0" "FEEDQUIET: and arms nothing"

store '[]'
out="$(feed)"; rc=$?
eq "$rc" 0 "FEEDQUIET: a completely empty store passes"

store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$("$FEEDER" status 2>&1)"; rc=$?
eq "$rc" 0 "FEEDQUIET: status exits 0"
has "$out" "1 candidate(s) ready" "FEEDQUIET: status reports the queue depth"
has "$out" "0 auto-armed bead(s) in flight" "FEEDQUIET: status reports the cap accounting"
eq "$(meta w-1 gc.auto_armed_by)" "<absent>" "FEEDQUIET: status writes nothing"
out="$(STUB_BD_FAIL_METAKEY=1 "$FEEDER" status 2>&1)"; rc=$?
eq "$rc" 1 "FEEDQUIET: status also fails loudly on an unreadable store"

# --- FEEDDRY: --dry-run reports without writing ------------------------------
store "[$(cand w-1 2026-01-01T00:00:00Z)]"
out="$(feed --dry-run)"; rc=$?
eq "$rc" 0 "FEEDDRY: dry-run exits 0"
has "$out" "DRY-RUN would arm w-1" "FEEDDRY: dry-run names what it would arm"
eq "$(meta w-1 gc.auto_armed_by)" "<absent>" "FEEDDRY: dry-run reserves nothing"
eq "$(meta w-1 gc.dispatch_when_ready)" "<absent>" "FEEDDRY: dry-run arms nothing"

# --- positive control over the shipped feeder cadence ------------------------
# The script is only half of the input side: without the order nothing calls it
# and the hopper stays empty, which is the exact state this bead measured.
echo "# shipped feeder order"
FORDER="$ROOT/orders/dispatch-feeder.toml"
[ -s "$FORDER" ] && ok "orders/dispatch-feeder.toml ships" || bad "orders/dispatch-feeder.toml is missing"
fo="$(cat "$FORDER" 2>/dev/null)"
has "$fo" 'trigger = "cooldown"' "the feeder order is cooldown-triggered"
has "$fo" 'scope = "rig"' "the feeder order is rig-scoped (its in-flight cap is a PER-RIG cap)"
has "$fo" 'dispatch-feeder.sh feed' "the feeder order runs the feed verb"
has "$fo" 'DISPATCH_FEEDER_MAX_IN_FLIGHT' "the in-flight cap is declared in [order.env] where an operator can override it"
has "$fo" 'DISPATCH_FEEDER_ENABLED' "the enable flag is declared in [order.env]"
if grep -qE '^[[:space:]]*(no_work_gate|idempotent)' "$FORDER"; then
    bad "the feeder order opts out of single-flight (no_work_gate/idempotent) — two concurrent passes would each spend the same budget"
else
    ok "the feeder order does not opt out of single-flight"
fi

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

# --- doctor/check-deferred-dispatch-wired ------------------------------------
# The check exists because the failure it guards is silent: `arm` succeeds
# whether or not anything consumes the record. A check that only ever says OK
# would be worth nothing, so every way the halves come apart is exercised.
echo "# doctor check"
CHECK="$ROOT/doctor/check-deferred-dispatch-wired/run.sh"
if [ ! -s "$CHECK" ]; then
    bad "doctor/check-deferred-dispatch-wired/run.sh is missing"
else
    ok "doctor/check-deferred-dispatch-wired ships"
    [ -x "$CHECK" ] || chmod +x "$CHECK" 2>/dev/null

    # The shipped pack is the positive control.
    GC_PACK_DIR="$ROOT" "$CHECK" >/dev/null 2>&1
    eq "$?" 0 "the check passes against the shipped pack"

    PK="$TMP/pk"
    mkpack() { # rebuild a minimal pack that mirrors the shipped one
        rm -rf "$PK"; mkdir -p "$PK/assets/scripts" "$PK/orders" "$PK/doctor"
        cp -r "$ROOT/doctor/check-deferred-dispatch-wired" "$PK/doctor/"
        cp "$ROOT/assets/scripts/deferred-dispatch.sh" "$PK/assets/scripts/"
        cp "$ROOT/assets/scripts/dispatch-feeder.sh" "$PK/assets/scripts/"
        cp "$ROOT/assets/scripts/deferred-dispatch.test.sh" "$PK/assets/scripts/"
        cp "$ROOT/orders/deferred-dispatch.toml" "$PK/orders/"
        cp "$ROOT/orders/dispatch-feeder.toml" "$PK/orders/"
    }
    check_rc() { GC_PACK_DIR="$PK" "$PK/doctor/check-deferred-dispatch-wired/run.sh" >/dev/null 2>&1; echo $?; }

    mkpack; eq "$(check_rc)" 0 "the fixture pack is a valid control before mutation"

    mkpack; rm -f "$PK/orders/deferred-dispatch.toml"
    eq "$(check_rc)" 2 "ERROR when the order is missing (arm records nobody performs)"

    mkpack; sed -i 's|deferred-dispatch.sh reconcile|deferred-dispatch.sh list|' "$PK/orders/deferred-dispatch.toml"
    eq "$(check_rc)" 2 "ERROR when exec runs a verb other than reconcile"

    mkpack; sed -i 's|assets/scripts/deferred-dispatch.sh reconcile|assets/scripts/renamed.sh reconcile|' "$PK/orders/deferred-dispatch.toml"
    eq "$(check_rc)" 2 "ERROR when the exec path drifts off the shipped script"

    mkpack; chmod -x "$PK/assets/scripts/deferred-dispatch.sh"
    eq "$(check_rc)" 2 "ERROR when the script is not executable"

    mkpack; sed -i 's|^timeout = \"120s\"|timeout = \"900s\"|' "$PK/orders/deferred-dispatch.toml"
    eq "$(check_rc)" 2 "ERROR when timeout is not below order-tracking-sweep's 10m stale-after"

    mkpack; printf 'no_work_gate = true\n' >> "$PK/orders/deferred-dispatch.toml"
    eq "$(check_rc)" 2 "ERROR when no_work_gate opts the order out of single-flight"

    mkpack; sed -i 's|--ready|--READYX|g' "$PK/assets/scripts/deferred-dispatch.sh"
    eq "$(check_rc)" 2 "ERROR when readiness stops being asked of bd"

    mkpack; sed -i 's|^    reconcile) cmd_reconcile|    reconcileX) cmd_reconcile|' "$PK/assets/scripts/deferred-dispatch.sh"
    eq "$(check_rc)" 2 "ERROR when the reconcile verb is gone"

    mkpack; sed -i 's|^scope = \"rig\"|scope = \"city\"|' "$PK/orders/deferred-dispatch.toml"
    eq "$(check_rc)" 2 "ERROR when the order stops being rig-scoped"

    # --- and the same, for the FEEDER half ---------------------------------
    # Each mutation below is a way the input side comes apart while every other
    # part of the mechanism keeps reporting healthy — which is precisely the
    # state tk-ku1uvv measured: arm worked, reconcile worked, 252 beads aged
    # out. A guard that has never been seen to fire is not a guard.
    mkpack; rm -f "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when the feeder script is missing (arm/reconcile with an empty hopper)"

    mkpack; rm -f "$PK/orders/dispatch-feeder.toml"
    eq "$(check_rc)" 2 "ERROR when the feeder order is missing (nothing calls the feeder)"

    mkpack; chmod -x "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when the feeder script is not executable"

    mkpack; sed -i 's|dispatch-feeder.sh feed|dispatch-feeder.sh status|' "$PK/orders/dispatch-feeder.toml"
    eq "$(check_rc)" 2 "ERROR when the feeder order runs a verb other than feed"

    mkpack; sed -i 's|assets/scripts/dispatch-feeder.sh feed|assets/scripts/renamed.sh feed|' "$PK/orders/dispatch-feeder.toml"
    eq "$(check_rc)" 2 "ERROR when the feeder exec path drifts off the shipped script"

    mkpack; sed -i 's|^scope = \"rig\"|scope = \"city\"|' "$PK/orders/dispatch-feeder.toml"
    eq "$(check_rc)" 2 "ERROR when the feeder order stops being rig-scoped (one budget across every store)"

    mkpack; sed -i 's|^timeout = \"180s\"|timeout = \"900s\"|' "$PK/orders/dispatch-feeder.toml"
    eq "$(check_rc)" 2 "ERROR when the feeder timeout is not below order-tracking-sweep's stale-after"

    mkpack; printf 'idempotent = true\n' >> "$PK/orders/dispatch-feeder.toml"
    eq "$(check_rc)" 2 "ERROR when the feeder order opts out of single-flight (two passes, one budget spent twice)"

    mkpack; sed -i 's|^DISPATCH_FEEDER_MAX_IN_FLIGHT|# DISPATCH_FEEDER_MAX_IN_FLIGHT|' "$PK/orders/dispatch-feeder.toml"
    eq "$(check_rc)" 2 "ERROR when the in-flight cap is no longer declared where city.toml can override it"

    mkpack; sed -i 's|^\[order.env\]|[order.notenv]|' "$PK/orders/dispatch-feeder.toml"
    eq "$(check_rc)" 2 "ERROR when [order.env] is gone (tuning tooling spend becomes a pack change)"

    # The defining constraint, from both directions.
    mkpack; sed -i 's|"$ARM_TOOL" arm |gc sling |' "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when the feeder slings directly instead of arming (a second dispatch path)"

    # ...and the check must survive the script EXPLAINING that constraint. The
    # first cut of this guard grepped the whole file and failed the correct
    # script on its own header comment.
    mkpack; printf '\n# Note: calling gc sling from here would bypass both fail-closed layers.\n' >> "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 0 "OK when 'gc sling' appears only in a comment — the guard reads code, not prose"

    mkpack; sed -i 's|sort_by((.created_at|sort_by((.priority|' "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when candidates stop being ordered oldest-first (the 31d+ tail starves)"

    mkpack; sed -i 's|--ready|--READYX|g' "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when the feeder stops asking bd for readiness"

    mkpack; sed -i 's|gc.auto_armed_by|gc.dispatch_when_ready|g' "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when the cap counts the arm key reconcile clears instead of the feeder's own marker"

    # ...and the other direction: the marker ALONE must not count either. A pass
    # interrupted between the marker write and the arm otherwise holds a slot
    # forever, and the stall is silent — "at cap", exit 0, every tick (tk-ib2yl2).
    # The substitution hits only the COUNTING predicate: the status helper spells
    # the same key without the trailing paren.
    mkpack; sed -i 's|gc\.dispatch_when_ready"\] // "") != "")|gc.other_key"] // "") != "")|' "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when the in-flight count drops its commitment-evidence test (a stranded reservation would hold a slot forever)"

    mkpack; sed -i 's|DISPATCH_FEEDER_MAX_IN_FLIGHT|UNCAPPED|g' "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when the in-flight cap is gone from the script"

    mkpack; sed -i 's|NOT treating this as an empty queue|no work|' "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when an unreadable candidate listing stops failing loudly"

    mkpack; sed -i 's|blow the cap|proceed anyway|' "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when an unreadable in-flight count stops refusing"

    mkpack; sed -i 's|^    feed)   cmd_feed|    feedX)   cmd_feed|' "$PK/assets/scripts/dispatch-feeder.sh"
    eq "$(check_rc)" 2 "ERROR when the feed verb is gone"

    mkpack; sed -i 's|FEEDOLDEST|XXOLDEST|g' "$PK/assets/scripts/deferred-dispatch.test.sh"
    eq "$(check_rc)" 2 "ERROR when the oldest-first regression case is dropped"

    mkpack; sed -i 's|FEEDCOUNT|XXCOUNT|g' "$PK/assets/scripts/deferred-dispatch.test.sh"
    eq "$(check_rc)" 2 "ERROR when the unreadable-cap regression case is dropped"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
