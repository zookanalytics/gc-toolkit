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

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
# >>> control-char-scrub
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
# Honor the three filters the check relies on: --db, --status (comma list) and
# --has-metadata-key. A stub that ignored --status would let an in_progress
# fixture reach the --status=open scan, so the detached-CLAIMED probe (which
# reads only the non-open statuses) could never be told apart from the open scan,
# and dropping the --status flag from either query would still pass this test.
db=""; status=""; haskey=""; prev=""
for a in "$@"; do
  case "$prev" in
    --db) db="$a" ;;
    --status) status="$a" ;;
    --has-metadata-key) haskey="$a" ;;
  esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
# BD_FAIL_KEY fails only the listing narrowed to that metadata key, so one probe
# can be made unreadable while the others still read.
[ -n "${BD_FAIL_KEY:-}" ] && [ "$haskey" = "$BD_FAIL_KEY" ] && exit 3
f="$STORES/$name.json"; [ -f "$f" ] || { printf '[]'; exit 0; }
# scrub first: a fixture may carry raw control bytes (the check's own guard),
# and real bd filters structured rows in the store, so its filter never sees
# them. An unparseable fixture makes jq exit non-zero, which the check reads as
# an unreadable store, exactly as a real bd failure would.
scrub < "$f" | jq -c --arg status "$status" --arg haskey "$haskey" '
  ($status | if . == "" then null else split(",") end) as $st
  | map(select($st == null or ((.status // "open") as $bst | ($st | index($bst)) != null)))
  | map(select($haskey == "" or ((.metadata // {}) | has($haskey))))'
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
# stall_root was retired with every reader. A visit carrying it is in_progress
# while a sitting holds it, so the probe reads every live status, not only the
# open ones the healer-key scan reads.
store '[{"id":"a-r1","status":"in_progress","metadata":{"task_kind":"visit","stall_root":"root-x"}},
        {"id":"a-r2","status":"closed","metadata":{"task_kind":"visit","stall_root":"root-y"}},
        {"id":"a-r3","status":"open","metadata":{"task_kind":"visit","stall_root":""}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a live bead carrying the retired stall_root key is an ERROR"
has "$OUT" "a-r1" "it names the in_progress visit, which an open-only scan would miss"
has "$OUT" "gc.demand_for=root-x" "it names the bead a hold under the key would have gated"
has "$OUT" "gc bd update a-r1 --unset-metadata stall_root" "it gives the clearing command"
hasnt "$OUT" "a-r2" "a closed bead carrying it is history, not a finding"
hasnt "$OUT" "a-r3" "an empty value is a cleared key, not a finding"
store '[{"id":"a-r4","status":"open","metadata":{}}]'
OUT=$(BD_FAIL_KEY=stall_root run_check); RC=$?
eq "$RC" "1" "an unreadable retired-key probe warns, never passes"
has "$OUT" "retired-key check did NOT run" "the warning says the probe did not run"

echo
echo "check-state-space: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
