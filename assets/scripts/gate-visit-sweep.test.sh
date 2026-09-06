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
#   * ONE VISIT PER GATE: a filed visit is recorded on the gate as
#     gc.gate_visit=<visit-id>, and a gate already carrying the stamp is never
#     re-offered (the churn guard: a closed sitting must not re-spawn every pass);
#   * the per-gate opt-out (gc.gate_visit=skip) suppresses that gate's visit,
#     and so does a typed non-string value (`false`) — read, never a jq abort;
#   * an ASSIGNED gate (a task a named person owes) gets no visit;
#   * a gate whose gated bead is NOT open gets no visit and is named on stderr;
#   * a visit already standing for the gated bead — matched by stall_root, which
#     `open` alone cannot see — is recorded on the gate without a second filing;
#   * a non-human gate (await_type != human) is left alone;
#   * the visit body tells converse how to resolve the gate;
#   * LOUD-FAIL: a visit that will not file exits non-zero, so the controller
#     logs it and the next sweep retries;
#   * the FALSE-EMPTY-QUEUE guard — an unreadable listing exits non-zero rather
#     than looking like a store with no gates;
#   * the PARTIAL-READ guard — a list that FAILS after printing a valid array
#     exits non-zero, not read as its (stale or empty) contents;
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

# gc stub: `gc bd list` answers the gate fixture when asked --include-gates and
# the live-bead fixture otherwise; `gc bd update` only logs. Every call logs
# its argv (so the test can prove --include-gates is passed and the stamp is
# written), and the gate list fails when told to.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GC_LOG"
case "$1 ${2:-}" in
  "bd list")
    case " $* " in
      *" --include-gates "*)
        [ -n "${STUB_LIST_FAIL:-}" ] && { echo "gc bd: simulated list failure" >&2; exit 1; }
        cat "$STUB_GATES"
        # A list that prints array-shaped stdout AND still fails: the sweep
        # must take THIS command's status, not the scrub it pipes into.
        [ -n "${STUB_LIST_RC:-}" ] && exit "$STUB_LIST_RC" ;;
      *) cat "$STUB_LIVE" ;;
    esac ;;
  "bd update") : ;;
esac
exit 0
STUB
chmod +x "$BIN/gc"

# HELM stub: stands in for gc-helm.sh. Logs every `open` call, answers with the
# real verb's success line (the sweep parses the visit id out of it), and fails
# the one whose subject is $HELM_FAIL_BEAD so the loud-fail path is exercised.
cat > "$BIN/helm-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HELM_LOG"
if [ -n "${HELM_FAIL_BEAD:-}" ]; then
  case " $* " in *" $HELM_FAIL_BEAD "*) exit 4 ;; esac
fi
echo "gc-helm: visit tk-v-$2 filed on $2 (pool x.converse) — a converse session will spawn (cold) or vacuum it (warm)."
exit 0
STUB
chmod +x "$BIN/helm-stub"

# Gate fixture: g1 is the happy case; g2 is opted out; g3 is a non-human
# (timer) gate; g4 carries no gated bead (real bd would drop it for
# --has-metadata-key, but the sweep's own jq must drop it too, so the stub
# returns it deliberately); g5 is assigned to a person; g6 already carries a
# visit stamp; g7 gates a bead that is NOT in the live set; g8's gated bead is
# already under a live sitting whose visit names it only as stall_root; g9
# carries a typed (boolean) opt-out.
cat > "$TMP/gates.json" <<'JSON'
[
 {"id":"tk-g1","issue_type":"gate","await_type":"human","status":"open","title":"pick the backend","metadata":{"gc.demand_for":"tk-w1"}},
 {"id":"tk-g2","issue_type":"gate","await_type":"human","status":"open","title":"suppressed","metadata":{"gc.demand_for":"tk-w2","gc.gate_visit":"skip"}},
 {"id":"tk-g3","issue_type":"gate","await_type":"timer","status":"open","title":"a timer gate","metadata":{"gc.demand_for":"tk-w3"}},
 {"id":"tk-g4","issue_type":"gate","await_type":"human","status":"open","title":"no gated bead","metadata":{}},
 {"id":"tk-g5","issue_type":"gate","await_type":"human","status":"open","title":"sign the contract","assignee":"zook","metadata":{"gc.demand_for":"tk-w5","gc.demand_kind":"task"}},
 {"id":"tk-g6","issue_type":"gate","await_type":"human","status":"open","title":"already visited","metadata":{"gc.demand_for":"tk-w6","gc.gate_visit":"tk-v-old"}},
 {"id":"tk-g7","issue_type":"gate","await_type":"human","status":"open","title":"work already closed","metadata":{"gc.demand_for":"tk-w7"}},
 {"id":"tk-g8","issue_type":"gate","await_type":"human","status":"open","title":"held by a live sitting","metadata":{"gc.demand_for":"tk-w8"}},
 {"id":"tk-g9","issue_type":"gate","await_type":"human","status":"open","title":"typed opt-out","metadata":{"gc.demand_for":"tk-w9","gc.gate_visit":false}}
]
JSON
# Live fixture: every gated bead except tk-w7, plus the sitting on tk-run whose
# visit names tk-w8 as its stall_root.
cat > "$TMP/live.json" <<'JSON'
[
 {"id":"tk-w1","status":"open"},{"id":"tk-w2","status":"open"},{"id":"tk-w3","status":"open"},
 {"id":"tk-w5","status":"open"},{"id":"tk-w6","status":"open"},{"id":"tk-w8","status":"open"},
 {"id":"tk-w9","status":"open"},{"id":"tk-run","status":"open"},
 {"id":"tk-vis8","status":"in_progress","metadata":{"task_kind":"visit","gc.continuation_group":"tk-run","stall_root":"tk-w8"},
  "dependencies":[{"type":"tracks","depends_on_id":"tk-run"}]}
]
JSON
printf '[]\n' > "$TMP/empty.json"

STUB_LIST_FAIL=""; STUB_LIST_RC=""; HELM_FAIL_BEAD=""; STUB_LIVE="$TMP/live.json"
run() { # run <gates-file>
  : > "$GC_LOG"; : > "$HELM_LOG"; RC=0
  OUT="$(PATH="$BIN:$PATH" GC_HELM_TOOL="$BIN/helm-stub" GC_LOG="$GC_LOG" HELM_LOG="$HELM_LOG" \
         STUB_GATES="$1" STUB_LIVE="$STUB_LIVE" STUB_LIST_FAIL="$STUB_LIST_FAIL" STUB_LIST_RC="$STUB_LIST_RC" HELM_FAIL_BEAD="$HELM_FAIL_BEAD" \
         bash "$SUT" 2>"$TMP/err")" || RC=$?
  ERR="$(cat "$TMP/err")"
}

# ── happy path ───────────────────────────────────────────────────────────────
run "$TMP/gates.json"
zero "$RC" "(RC) a readable store with eligible gates exits 0"
has  "$(cat "$HELM_LOG")" "open tk-w1" "(VISIT) the gated bead of a human gate gets a visit"
hasnt "$(cat "$HELM_LOG")" "open tk-g1" "(SUBJECT) the visit is on the gated bead, never the gate itself"
hasnt "$(cat "$HELM_LOG")" "open tk-w2" "(OPTOUT) gc.gate_visit=skip suppresses that gate's visit"
hasnt "$(cat "$HELM_LOG")" "open tk-w9" "(OPTOUT) …and a typed (boolean) opt-out is read as handled, not a jq abort"
hasnt "$(cat "$HELM_LOG")" "open tk-w3" "(NONHUMAN) a non-human gate is left alone"
hasnt "$(cat "$HELM_LOG")" "open tk-w4" "(NODEMAND) a gate with no gated bead files nothing"
hasnt "$(cat "$HELM_LOG")" "open tk-w5" "(ASSIGNED) a gate assigned to a person gets no visit — theirs to close"
hasnt "$(cat "$HELM_LOG")" "open tk-w6" "(ONESHOT) a gate already stamped gc.gate_visit is never re-offered"
hasnt "$(cat "$HELM_LOG")" "open tk-w7" "(CLOSEDWORK) a gate whose gated bead is not open files nothing"
has  "$ERR" "tk-g7 blocks tk-w7, which is not open" "(CLOSEDWORK) …and names the gate that outlived its work"
hasnt "$(cat "$HELM_LOG")" "open tk-w8" "(HELD) a gated bead already under a sitting (by stall_root) gets no second visit"
has  "$(cat "$GC_LOG")" "bd update tk-g8 --set-metadata gc.gate_visit=tk-vis8" "(HELD) …and that sitting's visit is recorded on the gate"
has  "$(cat "$GC_LOG")" "bd update tk-g1 --set-metadata gc.gate_visit=tk-v-tk-w1" "(STAMP) the filed visit's id is recorded on its gate"
hasnt "$(cat "$GC_LOG")" "bd update tk-g2" "(STAMP) an opted-out gate is not touched"
hasnt "$(cat "$GC_LOG")" "bd update tk-g7" "(STAMP) a gate on closed work is not stamped — it stays visible until resolved"
has  "$(cat "$GC_LOG")" "--include-gates" "(INCLUDEGATES) the enumeration un-hides gate beads"
has  "$(cat "$HELM_LOG")" "gc bd gate resolve tk-g1" "(BODY) the visit body says how to resolve the gate"
has  "$OUT" "filed 1 visit(s); 1 gate(s) already under a visit; 1 gate(s) on closed work" "(SUMMARY) the pass reports what it did, by kind"

# ── loud-fail: a visit that will not file must surface ────────────────────────
HELM_FAIL_BEAD="tk-w1"; run "$TMP/gates.json"; HELM_FAIL_BEAD=""
nonzero "$RC" "(LOUDFAIL) a failed visit filing exits non-zero"
has "$ERR" "FAILED to file a visit on tk-w1" "(LOUDFAIL) …and names the gated bead it could not reach"
hasnt "$(cat "$GC_LOG")" "bd update tk-g1" "(LOUDFAIL) …and the gate is NOT stamped, so the next sweep retries it"

# ── false-empty-queue guard: an unreadable listing is not an empty one ────────
STUB_LIST_FAIL=1; run "$TMP/gates.json"; STUB_LIST_FAIL=""
nonzero "$RC" "(ENUMFAIL) an unreadable gate listing exits non-zero"
hasnt "$(cat "$HELM_LOG")" "open " "(ENUMFAIL) …and files nothing on an unreadable store"

# ── partial-read guard: a non-zero list that still prints JSON is unreadable ──
# Bash takes a pipeline's status from its last stage, so `gc bd list | scrub`
# would mask a list that failed AFTER printing a valid array. The stub returns
# the eligible-gates fixture AND exits non-zero: a regression files a visit on
# tk-w1 and exits 0, so this case discriminates the pipe from the fixed split.
STUB_LIST_RC=7; run "$TMP/gates.json"; STUB_LIST_RC=""
nonzero "$RC" "(PARTIALREAD) a non-zero list that still printed JSON exits non-zero"
hasnt "$(cat "$HELM_LOG")" "open " "(PARTIALREAD) …and files nothing on an untrustworthy listing"
has "$ERR" "store unreadable" "(PARTIALREAD) …and reports the store unreadable"

# ── an unreadable LIVE listing is the same guard: nothing is filed ─────────────
STUB_LIVE="$TMP/nonexistent.json"; run "$TMP/gates.json"; STUB_LIVE="$TMP/live.json"
nonzero "$RC" "(LIVEFAIL) an unreadable live-bead listing exits non-zero"
hasnt "$(cat "$HELM_LOG")" "open " "(LIVEFAIL) …and files nothing"

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
