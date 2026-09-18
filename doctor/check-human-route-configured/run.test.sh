#!/usr/bin/env bash
# Hermetic test for doctor/check-human-route-configured. Stubs gc; no city, no
# network. The stub emits a fixture `gc agent list --json` roster so each case
# exercises one branch of the check.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-human-route-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/city"

# Stub gc: `gc [--city X] agent list --json` prints $ROSTER_FILE (or exits
# $ROSTER_RC when nonzero); everything else is a no-op success.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
while [ "${1:-}" = "--city" ]; do shift 2; done
case "$1 $2" in
  "agent list") rc="${ROSTER_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$ROSTER_FILE" ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# Rosters, in gc agent list --json shape (.agents[].qualified_name, .pool.max).
cat > "$TMP/human-0.json" <<'EOF'
{"agents":[
  {"qualified_name":"gc-toolkit.polecat","pool":{"min":0,"max":4}},
  {"qualified_name":"human","pool":{"min":0,"max":0}}
]}
EOF
cat > "$TMP/no-human.json" <<'EOF'
{"agents":[
  {"qualified_name":"gc-toolkit.polecat","pool":{"min":0,"max":4}},
  {"qualified_name":"gc-toolkit.refinery","pool":{"min":0,"max":1}}
]}
EOF
cat > "$TMP/human-2.json" <<'EOF'
{"agents":[{"qualified_name":"human","pool":{"min":0,"max":2}}]}
EOF
cat > "$TMP/human-nopool.json" <<'EOF'
{"agents":[{"qualified_name":"human"}]}
EOF
: > "$TMP/empty.json"

run_check() { PATH="$TMP/bin:$PATH" ROSTER_FILE="$1" ROSTER_RC="${2:-0}" \
    GC_PACK_DIR="$TMP" GC_CITY_PATH="$TMP/city" bash "$CHECK" 2>&1; }

# --- 1. happy path: bare human present with max_active_sessions=0 -------------
OUT=$(run_check "$TMP/human-0.json"); RC=$?
eq "$RC" "0" "a bare human agent with max_active_sessions=0 passes"
has "$OUT" "OK:" "the pass message is the OK line"
has "$OUT" "resolves" "the pass names the resolved route"

# --- 2. the bare human agent is absent ----------------------------------------
OUT=$(run_check "$TMP/no-human.json"); RC=$?
eq "$RC" "1" "no bare human agent warns"
has "$OUT" "stale-routed-config" "the finding it prevents is named"
has "$OUT" 'name = "human"' "the exact stanza is shown"
has "$OUT" "max_active_sessions = 0" "the load-bearing field is shown"
has "$OUT" "assets/scripts/ensure-human-route-agent.sh" "the writer is named as the remedy"

# --- 3. present but able to spawn (max_active_sessions != 0) -------------------
OUT=$(run_check "$TMP/human-2.json"); RC=$?
eq "$RC" "1" "a human agent that can spawn a pool warns"
has "$OUT" "max_active_sessions=2" "the offending cap is reported"
has "$OUT" "spawn" "the warning is about the phantom pool, not the route"

# --- 4. present but max_active_sessions unset (also spawns) --------------------
OUT=$(run_check "$TMP/human-nopool.json"); RC=$?
eq "$RC" "1" "a human agent with no cap warns (unset lets it spawn)"
has "$OUT" "max_active_sessions=unset" "an absent cap reads as unset, not as 0"

# --- 5. no city in scope: a note, not a finding -------------------------------
OUT=$(PATH="$TMP/bin:$PATH" GC_CITY_PATH="" GC_CITY="" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "outside a city the check passes with a note"
has "$OUT" "not verifiable here" "it says why it could not check"

# --- 6. gc could not answer: fail CLOSED to a warning -------------------------
OUT=$(run_check "$TMP/human-0.json" 1); RC=$?
eq "$RC" "1" "a roster read that errors warns, never passes"
has "$OUT" "UNVERIFIED" "the warning says the answer is unknown"

# --- 7. gc answered empty: also UNVERIFIED ------------------------------------
OUT=$(run_check "$TMP/empty.json"); RC=$?
eq "$RC" "1" "an empty roster warns, never passes"
has "$OUT" "UNVERIFIED" "the warning says the answer is unknown"

echo
echo "check-human-route-configured: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
