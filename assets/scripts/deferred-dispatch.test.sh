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
        cp "$ROOT/orders/deferred-dispatch.toml" "$PK/orders/"
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
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
