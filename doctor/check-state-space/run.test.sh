#!/usr/bin/env bash
# Hermetic test for doctor/check-state-space (I2). Stub gc/bd; no live city.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
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
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
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
printf '[{"id":"a-10","status":"open","metadata":{"merge_result":"bogus"},"notes":"tab\there\001etc"}]' \
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

echo
echo "check-state-space: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
