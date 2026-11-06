#!/usr/bin/env bash
# Hermetic test for doctor/check-state-space (I2). Stub gc/bd; no live city.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-state-space-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/pack/lifecycle"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":false}]}
EOF
cat > "$TMP/pack/lifecycle/lifecycle.toml" <<'EOF'
[machine]
states = [
  "unanchored",
  "pre_open_gate",
  "pull_request",
  "merged",
  "abandoned",
]
closed_states = ["merged"]
detached_states = ["pre_open_gate"]
park_route = "parked-with-a-person"
EOF

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
# >>> control-char-scrub
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
# Honor the filters the check relies on: --db, --status (comma list),
# --has-metadata-key, and --include-gates, without which bd leaves gate rows
# out. A stub that ignored --status would let an in_progress fixture reach the
# --status=open scan, so the detached-CLAIMED probe (which reads only the
# non-open statuses) could never be told apart from the open scan, and dropping
# the --status flag from either query would still pass this test.
db=""; status=""; haskey=""; gates=""; prev=""
for a in "$@"; do
  case "$prev" in
    --db) db="$a" ;;
    --status) status="$a" ;;
    --has-metadata-key) haskey="$a" ;;
  esac
  [ "$a" = "--include-gates" ] && gates=1
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
# BD_FAIL_STATUS fails only the listing of exactly that --status list that no
# metadata key narrows, so one probe can be made unreadable while the others
# still read.
[ -n "${BD_FAIL_STATUS:-}" ] && [ "$status" = "$BD_FAIL_STATUS" ] && [ -z "$haskey" ] && exit 3
f="$STORES/$name.json"; [ -f "$f" ] || { printf '[]'; exit 0; }
# scrub first: a fixture may carry raw control bytes (the check's own guard),
# and real bd filters structured rows in the store, so its filter never sees
# them. An unparseable fixture makes jq exit non-zero, which the check reads as
# an unreadable store, exactly as a real bd failure would.
scrub < "$f" | jq -c --arg status "$status" --arg haskey "$haskey" --arg gates "$gates" '
  ($status | if . == "" then null else split(",") end) as $st
  | map(select($st == null or ((.status // "open") as $bst | ($st | index($bst)) != null)))
  | map(select($haskey == "" or ((.metadata // {}) | has($haskey))))
  | map(select($gates != "" or (.issue_type // "") != "gate"))'
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"
run_check() { RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1; }
store() { printf '%s' "$1" > "$TMP/stores/alpha.json"; }

# --- 1. clean store -----------------------------------------------------
store '[{"id":"a-1","status":"open","metadata":{"merge_result":"pull_request"}},
        {"id":"a-2","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "declared states on open beads pass"
has "$OUT" "OK:" "the pass message is the OK line"

# --- 2. undeclared merge_result -----------------------------------------
store '[{"id":"a-3","status":"open","metadata":{"merge_result":"exploded"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "an undeclared merge_result value is an ERROR"
has "$OUT" "a-3" "the finding names the bead"
has "$OUT" "exploded" "the finding quotes the unknown value"
has "$OUT" "pre_open_gate" "the finding lists the declared enum (read from lifecycle.toml)"
hasnt "$OUT" "refused_false_completion" "the enum came from lifecycle.toml, not the builtin fallback"

# --- 3. closed-only state on an OPEN bead --------------------------------
store '[{"id":"a-4","status":"open","metadata":{"merge_result":"merged"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "merge_result=merged on an OPEN bead is an ERROR"
has "$OUT" "a-4" "it names the bead"
has "$OUT" "closed-only" "it says why merged is illegal while open"

# --- 4. deleted healer-bookkeeping keys ----------------------------------
store '[{"id":"a-5","status":"open","metadata":{"check_set_healed":"1"}},
        {"id":"a-6","status":"open","metadata":{"stranded_branch_flagged":"x"}},
        {"id":"a-7","status":"open","metadata":{"stale_gate_seen":"y"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "deleted healer keys are ERRORs"
has "$OUT" "a-5" "the exact-name key is flagged"
has "$OUT" "a-6" "the stranded_branch_* prefix is flagged"
has "$OUT" "a-7" "the stale_gate_* prefix is flagged"

# --- 5. empty merge_result reads as absent -------------------------------
store '[{"id":"a-8","status":"open","metadata":{"merge_result":""}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "an empty merge_result is the absent (unanchored) value, not a finding"

# --- 6. builtin fallback when lifecycle.toml is missing -------------------
store '[{"id":"a-9","status":"open","metadata":{"merge_result":"refused_false_completion"}}]'
OUT=$(GC_PACK_DIR="$TMP/nopack" RIGS_JSON="$TMP/rigs.json" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "with no lifecycle.toml the builtin enum accepts the plan's states"

# --- 7. fail-CLOSED arms --------------------------------------------------
store '[]'
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped, not clean"
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"

# --- 8. control characters in a payload do not cost the store -------------
# A raw TAB, a raw C0 byte, and a raw LF (bd's unescaped-newline bug) — each is
# invalid inside a JSON string and each must be scrubbed, or the whole store
# degrades to "NOT checked" and hides every finding in it.
printf '[{"id":"a-10","status":"open","metadata":{"merge_result":"bogus"},"notes":"tab\there\001and a\nraw newline"}]' \
    > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a payload carrying raw control characters still yields the finding"
has "$OUT" "a-10" "the finding survives the control characters"

# --- 9. suspended rigs are skipped with a note ----------------------------
cat > "$TMP/rigs-susp.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
store '[{"id":"a-11","status":"open","metadata":{"merge_result":"bogus"}}]'
OUT=$(RIGS_JSON="$TMP/rigs-susp.json" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a suspended rig is skipped rather than probed"
has "$OUT" "suspended" "the skip is noted, not silent"

# --- 10. a detached state is neither routed nor held ----------------------
store '[{"id":"a-12","status":"open","assignee":"","metadata":{"merge_result":"pre_open_gate","gc.routed_to":"alpha/gc-toolkit.polecat"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a route on a detached state is an ERROR"
has "$OUT" "a-12" "it names the bead"
has "$OUT" "alpha/gc-toolkit.polecat" "it quotes the route that made it pool demand"
has "$OUT" "detached_states" "it names the declaration the bead violates"

store '[{"id":"a-13","status":"open","assignee":"alpha/gc-toolkit.polecat-1","metadata":{"merge_result":"pre_open_gate"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "an assignee on a detached state is an ERROR"
has "$OUT" "alpha/gc-toolkit.polecat-1" "it quotes the holder"

store '[{"id":"a-14","status":"open","assignee":"alpha/holder","metadata":{"merge_result":"pre_open_gate","gc.routed_to":"alpha/pool"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "both fields set is an ERROR"
eq "$(printf '%s' "$OUT" | grep -c 'a-14')" "2" "each violated field is reported separately"

store '[{"id":"a-15","status":"open","assignee":"","metadata":{"merge_result":"abandoned","gc.routed_to":"human"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a route on a NON-detached state is the declared routing, not a finding"

# The park sentinel is a rest, not an offer: signoff.sh routes a round-capped
# anchor there and it stays parked across the flip to pull_request.
store '[{"id":"a-17","status":"open","assignee":"","metadata":{"merge_result":"pre_open_gate","gc.routed_to":"parked-with-a-person"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "the declared park_route on a detached state is not a finding"
store '[{"id":"a-18","status":"open","assignee":"","metadata":{"merge_result":"pre_open_gate","gc.routed_to":"human"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a value that is NOT the declared park_route still is (the sentinel is read, not assumed)"

# --- 11. the detached set is read from lifecycle.toml ---------------------
# The fixture declares pre_open_gate alone; the builtin fallback also carries
# pull_request. One bead separates a read declaration from the fallback.
store '[{"id":"a-16","status":"open","assignee":"","metadata":{"merge_result":"pull_request","gc.routed_to":"alpha/pool"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a state lifecycle.toml does NOT declare detached is not held to the rule"
OUT=$(GC_PACK_DIR="$TMP/nopack" RIGS_JSON="$TMP/rigs.json" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "the same bead IS a finding under the builtin detached set"
has "$OUT" "a-16" "the fallback arm names the bead"

# --- 12. a detached anchor claimed into a non-open status ------------------
# The open scan and every cadence reader enumerate --status=open, so this bead
# is invisible to all of them; the non-open backstop probe is what reports it.
store '[{"id":"a-19","status":"in_progress","assignee":"","metadata":{"merge_result":"pre_open_gate"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "an in_progress detached anchor is an ERROR"
has "$OUT" "a-19" "it names the claimed anchor the open scan cannot see"
has "$OUT" "status=in_progress" "it names the status that hid it"
has "$OUT" "dropped out of the pipeline" "it explains the cadence invisibility"

# blocked is equally invisible: the invariant is status=open, not merely
# not-in_progress. (pre_open_gate is the detached state the fixture's
# lifecycle.toml declares.)
store '[{"id":"a-21","status":"blocked","assignee":"","metadata":{"merge_result":"pre_open_gate"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a detached anchor held at status=blocked is flagged too"
has "$OUT" "status=blocked" "the finding names the holding status"

# An OPEN detached anchor at rest is the correct state; the non-open probe must
# not re-report it. --has-metadata-key merge_result with no --status returns every
# non-closed status, open included, so the probe's --status scoping is what keeps
# the open resting state (already covered by the open scan) off the non-open
# findings. Drop --status from the probe and this case flips to a false
# status=open, not open finding.
store '[{"id":"a-22","status":"open","assignee":"","metadata":{"merge_result":"pre_open_gate"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open detached anchor at rest is not re-flagged by the non-open probe"

# --- 13. ordinary in-flight work is NOT a detached-state finding -----------
# A polecat's own work bead is in_progress and carries branch but no
# merge_result; the --has-metadata-key filter keeps the backstop off it, so an
# empty assignee is never read as an orphan here.
store '[{"id":"a-20","status":"in_progress","assignee":"","metadata":{"branch":"polecat/x"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "an in_progress bead with no merge_result is ordinary work, not a finding"

# --- 14. disk pressure must not forge an all-clear ------------------------
# bash backs a `<<<` here-string with a temp file; under disk pressure that file
# cannot be staged, the redirection fails silently (the check is set -u, not
# set -e), and the loop runs zero times — so the pre-fix check read a non-empty
# store as empty and printed the OK line. The fix stages every enumeration
# through a checked `mktemp -d`, so a failing `mktemp` aborts the run non-clean.
# A failing `mktemp` command is a NO-OP on the pre-fix `<<<` (bash's here-string
# temp is internal, never the mktemp command), which is exactly what makes this
# case fail against the pre-fix script and so proves it discriminates.
store '[{"id":"a-dp","status":"open","metadata":{"merge_result":"exploded"}}]'
# Mirror: with a working mktemp the fixture yields its finding, so the
# disk-pressure assertions below are not vacuously satisfied by an empty store.
OUT=$(run_check); RC=$?
eq "$RC" "2" "mirror: the fixture reports its finding when mktemp works"
has "$OUT" "a-dp" "mirror: the finding names the bead"
# Now fail every mktemp — the hermetic stand-in for a full /tmp — and re-run.
cat > "$TMP/bin/mktemp" <<'MK'
#!/usr/bin/env bash
echo "mktemp: stubbed disk-pressure failure" >&2
exit 1
MK
chmod +x "$TMP/bin/mktemp"
OUT=$(run_check); RC=$?
rm -f "$TMP/bin/mktemp"
eq "$RC" "1" "a temp-file failure warns (1) — it neither passes (0) nor errors (2)"
has "$OUT" "not an all-clear" "it says the run could not scan, not that the state space holds"
hasnt "$OUT" "OK:" "it does not forge the clean all-clear line"
hasnt "$OUT" "a-dp" "the store is not reported clean — the run is non-clean, not a false pass"

# --- 15. a live bead still carrying a retired key ------------------------
# stall_root was retired with every reader. A bead a session holds is
# in_progress, so the probe reads every live status, not only the open ones the
# healer-key scan reads.
store '[{"id":"a-r1","status":"in_progress","metadata":{"task_kind":"visit","stall_root":"root-x"}},
        {"id":"a-r2","status":"closed","metadata":{"task_kind":"visit","stall_root":"root-y"}},
        {"id":"a-r3","status":"open","metadata":{"task_kind":"visit","stall_root":""}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a live bead carrying the retired stall_root key is an ERROR"
has "$OUT" "a-r1" "it names the in_progress visit, which an open-only scan would miss"
has "$OUT" "a human gate that blocks root-x" "it names the bead a hold under the key would have gated"
has "$OUT" "gc bd update a-r1 --unset-metadata stall_root" "it gives the clearing command"
hasnt "$OUT" "a-r2" "a closed bead carrying it is history, not a finding"
hasnt "$OUT" "a-r3" "an empty value is a cleared key, not a finding"
has "$OUT" "Discharge that by hand, then clear the key" "a key whose residue leaves work undone says to discharge it first"
# The visit-era helper's escalation keys have no writer and no reader. A live
# bead carrying one holds nothing back: the finding says a retired writer is
# back and asks for no discharge.
store '[{"id":"a-r5","status":"open","metadata":{"escalation.recurrences":"3"}},
        {"id":"a-r6","status":"in_progress","metadata":{"escalation_raised_by":"tk-wisp-x"}},
        {"id":"a-r7","status":"closed","metadata":{"escalation.recurrence_last":"2026-10-01T00:00:00Z"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a live bead carrying a retired escalation key is an ERROR"
has "$OUT" "gc bd update a-r5 --unset-metadata escalation.recurrences" "it names the open carrier and gives the clearing command"
has "$OUT" "gc bd update a-r6 --unset-metadata escalation_raised_by" "…and the in_progress one"
has "$OUT" "a retired writer stamped it" "…and says what its presence means"
hasnt "$OUT" "a-r7" "a closed bead carrying one is history, not a finding"
# The visit-era sitting's keys and the visit-era close's gc.outcome_reason have
# no writer and no reader, so a live bead carrying one holds nothing back.
store '[{"id":"a-r8","status":"in_progress","metadata":{"task_kind":"visit","gc.hold_demand":"tk-dem1"}},
        {"id":"a-r9","status":"open","metadata":{"gc.pr_visit_summary":"we shipped it"}},
        {"id":"a-r10","status":"closed","metadata":{"gc.pr_visit_actions":"routed tk-w"}},
        {"id":"a-r11","status":"in_progress","metadata":{"task_kind":"visit","gc.outcome_reason":"settled the plan"}},
        {"id":"a-r12","status":"closed","metadata":{"task_kind":"visit","gc.outcome_reason":"settled the plan"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a live bead carrying a retired converse key is an ERROR"
has "$OUT" "gc bd update a-r8 --unset-metadata gc.hold_demand" "it names the held visit and the clearing command"
has "$OUT" "a converse hold files a human gate its conversation replies to" "…and says what a hold files instead"
has "$OUT" "gc bd update a-r9 --unset-metadata gc.pr_visit_summary" "…and the reminder stash on an open bead"
hasnt "$OUT" "a-r10" "a closed visit carrying the stash is history, not a finding"
has "$OUT" "gc bd update a-r11 --unset-metadata gc.outcome_reason" "…and the outcome reason on a live visit"
has "$OUT" "the board's sittings card reads a conversation's close reason" "…and says where the close's sentence is read"
hasnt "$OUT" "a-r12" "a closed visit carrying its outcome reason is history, not a finding"
hasnt "$OUT" "migration" "no finding sends a person to a migration"
# The visit's and the legacy demand's own keys, and the finding keys that named
# a visit, have no writer and no reader either. Each one on a live bead is a
# finding, whichever live status the bead is in, and the same key on a closed
# bead is history.
RK_VISIT="escalation_key gc.demand_for gc.gate_visit gc.ruling gc.folded_into visit.recheck sweep.new_ids sweep.carried_ids sweep.pass_at finding.visit finding.ruling_visit"
LIVE_ST=(open in_progress blocked deferred hooked pinned)
rows=""; n=0
for k in $RK_VISIT; do
  n=$((n + 1))
  rows="$rows$(jq -nc --arg id "a-k$n" --arg st "${LIVE_ST[$(( (n - 1) % 6 ))]}" --arg k "$k" '{id: $id, status: $st, metadata: {($k): "x"}}'),"
  rows="$rows$(jq -nc --arg id "a-c$n" --arg k "$k" '{id: $id, status: "closed", metadata: {($k): "x"}}'),"
done
store "[${rows%,}]"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a live bead carrying a key of the visit or the legacy demand is an ERROR"
n=0
for k in $RK_VISIT; do
  n=$((n + 1))
  has "$OUT" "gc bd update a-k$n --unset-metadata $k" "…$k on a bead in status ${LIVE_ST[$(( (n - 1) % 6 ))]} is named with its clearing command"
  hasnt "$OUT" "a-c$n " "…and $k on a closed bead is history"
done
has "$OUT" "which human gates and conversations replace" "…and the finding says what replaces the key"
# One bead carrying two retired keys is named once for each.
store '[{"id":"a-r13","status":"blocked","metadata":{"escalation_key":"k","visit.recheck":"liveness-recheck.sh"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bead carrying two retired keys is an ERROR"
has "$OUT" "gc bd update a-r13 --unset-metadata escalation_key" "…named for the first key"
has "$OUT" "gc bd update a-r13 --unset-metadata visit.recheck" "…and for the second"
# A legacy demand's keys sit on a gate, and bd lists no gate without
# --include-gates, so both listings the probe reads take it.
store '[{"id":"a-g1","status":"open","issue_type":"gate","await_type":"human","metadata":{"gc.demand_for":"a-w1"}},
        {"id":"a-g2","status":"blocked","issue_type":"gate","await_type":"human","metadata":{"gc.gate_visit":"filed"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a live gate carrying a retired key is an ERROR"
has "$OUT" "gc bd update a-g1 --unset-metadata gc.demand_for" "…an open gate is named"
has "$OUT" "gc bd update a-g2 --unset-metadata gc.gate_visit" "…and a gate in another live status"
# The probe reads the other live statuses in one listing; when that listing
# does not read, the check warns rather than passing, and names no carrier.
store '[{"id":"a-r4","status":"open","metadata":{}},
        {"id":"a-r14","status":"in_progress","metadata":{"gc.ruling":"ship it"}}]'
OUT=$(BD_FAIL_STATUS=in_progress,blocked,deferred,hooked,pinned run_check); RC=$?
eq "$RC" "1" "an unreadable retired-key probe warns, never passes"
has "$OUT" "retired-key check did NOT run" "the warning says the probe did not run"
hasnt "$OUT" "a-r14" "…and it names no carrier it could not read"

echo
echo "check-state-space: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
