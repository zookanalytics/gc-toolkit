#!/usr/bin/env bash
# Hermetic test for doctor/check-routed-work-claimable (I3). Stub gc/bd only.
# Covers: exact-equality route classification (repair / candidates / padded /
# blank / unknown), the sentinel and empty exemptions, the widened assignee
# arm, the folded rig-scoped-order arm, and every fail-closed probe.
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

CITY="$TMP/testcity"
mkdir -p "$TMP/bin" "$TMP/stores" "$CITY" "$TMP/alpha" "$TMP/beta" "$TMP/pack/orders"

cat > "$TMP/agents.json" <<EOF
{"city_path":"$CITY","agents":[
  {"qualified_name":"alpha/pack.polecat"},
  {"qualified_name":"beta/pack.polecat"},
  {"qualified_name":"alpha/pack.refinery"},
  {"qualified_name":"pack.mayor"}]}
EOF
cat > "$TMP/rigs.json" <<EOF
{"rigs":[
  {"name":"testcity","path":"$CITY"},
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"}]}
EOF
printf '{"orders":[]}' > "$TMP/orders.json"

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "agent list") rc="${AGENTS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$AGENTS_JSON" ;;
  "rig list")   rc="${RIGS_RC:-0}";   [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "order list") rc="${ORDERS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$ORDERS_JSON" ;;
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
run_check() {
    AGENTS_JSON="${AGENTS_JSON:-$TMP/agents.json}" RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" \
    ORDERS_JSON="${ORDERS_JSON:-$TMP/orders.json}" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1
}
routed() { printf '{"id":"%s","status":"open","metadata":{"gc.routed_to":"%s"}}' "$1" "$2"; }
assigned() { printf '{"id":"%s","status":"open","assignee":"%s","metadata":{}}' "$1" "$2"; }
store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.json"; }
clear_stores() { rm -f "$TMP/stores/"*.json; }

# --- 1. rig-unqualified route: error, repair named ------------------------
store alpha "$(routed a-1 pack.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a rig-unqualified pool route is an ERROR"
has "$OUT" "a-1" "the error names the bead"
has "$OUT" "gc.routed_to=alpha/pack.polecat" "the error names the exact repair"
clear_stores

# --- 2. city store: candidates listed, no repair guessed ------------------
store testcity "$(routed c-1 pack.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bare rig-pool route in the CITY store is an ERROR"
has "$OUT" "alpha/pack.polecat, beta/pack.polecat" "it lists every candidate"
hasnt "$OUT" "set gc.routed_to" "it does not guess a repair it cannot know"
clear_stores

# --- 3. exempt shapes ------------------------------------------------------
store alpha "$(routed a-2 alpha/pack.refinery)" "$(routed a-3 pack.mayor)" \
            "$(routed a-4 human)" "$(routed a-5 '')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "exact identity / bare-but-live city identity / human sentinel / empty route all pass"
hasnt "$OUT" "a-2" "the working route is not a finding"
hasnt "$OUT" "a-4" "the human sentinel is not a finding"
clear_stores

# --- 4. padded and blank routes (compared AS STORED) -----------------------
store alpha "$(routed p-1 ' alpha/pack.refinery ')" "$(routed p-2 '   ')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a whitespace-padded live identity is an ERROR, not an OK"
has "$OUT" '" alpha/pack.refinery "' "the stored bytes are quoted so the padding is visible"
has "$OUT" "set gc.routed_to=alpha/pack.refinery" "the de-padded repair is named"
has "$OUT" "p-2" "a whitespace-only route is an ERROR, not a cleared route"
clear_stores

# --- 5. unknown route: note, not verdict -----------------------------------
store alpha "$(routed u-1 not-an-agent-at-all)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an unrecognizable route does not fail the check"
has "$OUT" "reported, not judged" "it is still reported in the details"
clear_stores

# --- 6. the WIDENED assignee arm --------------------------------------------
store alpha "$(assigned s-1 alpha/pack.refinery)" "$(assigned s-2 human)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a live-identity assignee and the human sentinel pass"
store alpha "$(assigned s-3 pack.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a rig-unqualified ASSIGNEE on an open bead is an ERROR"
has "$OUT" "assignee=" "the finding names the assignee field, not the route"
has "$OUT" "set assignee=alpha/pack.polecat" "the repair is the qualified assignee"
store alpha "$(assigned s-4 someone-external)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an assignee resembling nothing is a note, not a verdict"
has "$OUT" "s-4" "the unjudgeable assignee is still reported"
clear_stores

# --- 7. the folded rig-scoped-order arm -------------------------------------
printf 'scope = "rig"\n' > "$TMP/pack/orders/sweeper.toml"
cat > "$TMP/orders-unbound.json" <<EOF
{"orders":[{"name":"sweeper","rig":"","source":"$TMP/pack/orders/sweeper.toml"}]}
EOF
OUT=$(ORDERS_JSON="$TMP/orders-unbound.json" run_check); RC=$?
eq "$RC" "2" "a scope=rig order registered with no rig bound is an ERROR"
has "$OUT" "sweeper" "the unbound order is named"
cat > "$TMP/orders-city.json" <<EOF
{"orders":[{"name":"citywide","rig":"","source":"$TMP/pack/orders/citywide.toml"}]}
EOF
printf 'scope = "city"\n' > "$TMP/pack/orders/citywide.toml"
OUT=$(ORDERS_JSON="$TMP/orders-city.json" run_check); RC=$?
eq "$RC" "0" "a scope=city order with no rig is the point of city scope"

# --- 8. fail-CLOSED arms -----------------------------------------------------
OUT=$(AGENTS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc agent list\` warns (with no identity set every route looks dead)"
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped, not clean"
OUT=$(ORDERS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable order registry warns (the arm did not run)"

# --- 9. an ERROR outranks a WARNING -----------------------------------------
store beta "$(routed b-1 pack.polecat)"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "2" "a finding plus an unreadable store still exits ERROR"
has "$OUT" "b-1" "the finding survives alongside the warning"
clear_stores

# --- 10. clean pass -----------------------------------------------------------
OUT=$(run_check); RC=$?
eq "$RC" "0" "empty stores are OK"
has "$OUT" "OK:" "the pass message is the OK line"

echo
echo "check-routed-work-claimable: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
