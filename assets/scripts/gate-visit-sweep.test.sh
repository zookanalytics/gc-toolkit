#!/usr/bin/env bash
# Hermetic test for assets/scripts/gate-visit-sweep.sh.
#
# WHAT THE SCRIPT IS FOR. A human gate is the pack's escalation STATE; the visit
# is its RESOLUTION. This sweep files one converse visit on the bead each open
# human gate blocks, in one place, so the visit-on-gate rule and its operator
# control do not have to live in every gate producer.
#
# What is exercised:
#   * a visit is filed on the GATED bead (gc.demand_for), not on the gate;
#   * the enumerating `gc bd list` passes --include-gates — gates are hidden by
#     default, so without it the sweep sees nothing;
#   * the per-gate opt-out (gc.gate_visit=skip) suppresses that gate's visit;
#   * a non-human gate (await_type != human) is left alone;
#   * the visit body tells converse how to resolve the gate;
#   * LOUD-FAIL: a visit that will not file exits non-zero, so the controller
#     logs it and the next sweep retries;
#   * the FALSE-EMPTY-QUEUE guard — an unreadable listing exits non-zero rather
#     than looking like a store with no gates;
#   * the QUIET PATH — an empty store passes and files nothing;
#   * a POSITIVE CONTROL over the shipped order file, so a passing suite cannot
#     mean the cadence that runs this script was quietly un-shipped.
#
# No live city, Dolt, network, gc or bd — only jq, stubs, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/gate-visit-sweep.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }
nonzero() { if [ "$1" -ne 0 ]; then ok "$2"; else bad "$2 (exit was 0)"; fi; }
zero()    { if [ "$1" -eq 0 ]; then ok "$2"; else bad "$2 (exit was $1)"; fi; }

[ -x "$SUT" ] || chmod +x "$SUT" 2>/dev/null

BIN="$TMP/bin"; mkdir -p "$BIN"
GC_LOG="$TMP/gclog"; HELM_LOG="$TMP/helmlog"

# gc stub: only `gc bd list` is called. It logs its argv (so the test can prove
# --include-gates is passed) and prints the fixture, or fails when told to.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GC_LOG"
case "$1 ${2:-}" in
  "bd list")
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "gc bd: simulated list failure" >&2; exit 1; }
    cat "$STUB_GATES" ;;
esac
exit 0
STUB
chmod +x "$BIN/gc"

# HELM stub: stands in for gc-helm.sh. Logs every `open` call, and fails the one
# whose subject is $HELM_FAIL_BEAD so the loud-fail path can be exercised.
cat > "$BIN/helm-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HELM_LOG"
if [ -n "${HELM_FAIL_BEAD:-}" ]; then
  case " $* " in *" $HELM_FAIL_BEAD "*) exit 4 ;; esac
fi
exit 0
STUB
chmod +x "$BIN/helm-stub"

# Fixture: g1 is the happy case; g2 is opted out; g3 is a non-human (timer)
# gate; g4 carries no gated bead. Real bd would drop g4 for --has-metadata-key,
# but the sweep's own jq must drop it too, so the stub returns it deliberately.
cat > "$TMP/gates.json" <<'JSON'
[
 {"id":"tk-g1","issue_type":"gate","await_type":"human","status":"open","title":"pick the backend","metadata":{"gc.demand_for":"tk-w1"}},
 {"id":"tk-g2","issue_type":"gate","await_type":"human","status":"open","title":"suppressed","metadata":{"gc.demand_for":"tk-w2","gc.gate_visit":"skip"}},
 {"id":"tk-g3","issue_type":"gate","await_type":"timer","status":"open","title":"a timer gate","metadata":{"gc.demand_for":"tk-w3"}},
 {"id":"tk-g4","issue_type":"gate","await_type":"human","status":"open","title":"no gated bead","metadata":{}}
]
JSON
printf '[]\n' > "$TMP/empty.json"

STUB_LIST_FAIL=""; HELM_FAIL_BEAD=""
run() { # run <gates-file>
  : > "$GC_LOG"; : > "$HELM_LOG"; RC=0
  OUT="$(PATH="$BIN:$PATH" GC_HELM_TOOL="$BIN/helm-stub" GC_LOG="$GC_LOG" HELM_LOG="$HELM_LOG" \
         STUB_GATES="$1" STUB_LIST_FAIL="$STUB_LIST_FAIL" HELM_FAIL_BEAD="$HELM_FAIL_BEAD" \
         bash "$SUT" 2>"$TMP/err")" || RC=$?
  ERR="$(cat "$TMP/err")"
}

# ── happy path ───────────────────────────────────────────────────────────────
run "$TMP/gates.json"
zero "$RC" "(RC) a readable store with eligible gates exits 0"
has  "$(cat "$HELM_LOG")" "open tk-w1" "(VISIT) the gated bead of a human gate gets a visit"
hasnt "$(cat "$HELM_LOG")" "open tk-g1" "(SUBJECT) the visit is on the gated bead, never the gate itself"
hasnt "$(cat "$HELM_LOG")" "open tk-w2" "(OPTOUT) gc.gate_visit=skip suppresses that gate's visit"
hasnt "$(cat "$HELM_LOG")" "open tk-w3" "(NONHUMAN) a non-human gate is left alone"
hasnt "$(cat "$HELM_LOG")" "open tk-w4" "(NODEMAND) a gate with no gated bead files nothing"
has  "$(cat "$GC_LOG")" "--include-gates" "(INCLUDEGATES) the enumeration un-hides gate beads"
has  "$(cat "$HELM_LOG")" "gc bd gate resolve tk-g1" "(BODY) the visit body says how to resolve the gate"

# ── loud-fail: a visit that will not file must surface ────────────────────────
HELM_FAIL_BEAD="tk-w1"; run "$TMP/gates.json"; HELM_FAIL_BEAD=""
nonzero "$RC" "(LOUDFAIL) a failed visit filing exits non-zero"
has "$ERR" "FAILED to file a visit on tk-w1" "(LOUDFAIL) …and names the gated bead it could not reach"

# ── false-empty-queue guard: an unreadable listing is not an empty one ────────
STUB_LIST_FAIL=1; run "$TMP/gates.json"; STUB_LIST_FAIL=""
nonzero "$RC" "(ENUMFAIL) an unreadable gate listing exits non-zero"
hasnt "$(cat "$HELM_LOG")" "open " "(ENUMFAIL) …and files nothing on an unreadable store"

# ── quiet path: an empty store passes and files nothing ───────────────────────
run "$TMP/empty.json"
zero "$RC" "(QUIET) an empty store exits 0"
hasnt "$(cat "$HELM_LOG")" "open " "(QUIET) …and files no visit"

# ── positive control over the shipped order ──────────────────────────────────
ORDER="$ROOT/orders/gate-visit-sweep.toml"
if [ -f "$ORDER" ]; then
  ok "(ORDER) the cadence order file is shipped"
  has "$(cat "$ORDER")" "assets/scripts/gate-visit-sweep.sh" "(ORDER) …and runs this script"
  has "$(cat "$ORDER")" 'trigger = "cooldown"' "(ORDER) …on a cooldown"
  has "$(cat "$ORDER")" 'scope = "rig"' "(ORDER) …rig-scoped"
else
  bad "(ORDER) orders/gate-visit-sweep.toml is missing — the script would never run"
fi

echo "gate-visit-sweep: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
