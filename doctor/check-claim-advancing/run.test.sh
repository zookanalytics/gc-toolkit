#!/usr/bin/env bash
# Hermetic test for doctor/check-claim-advancing (I11). Stubs gc/bd only.
# Covers both directions the check has to get right: it fires on a claim whose
# holder cannot be advancing it (orphaned / dead / stalled), and it stays
# SILENT on a session that is genuinely working — including one that has held
# the same step for hours, which is ordinary for a long implementation step.
# Also covers identity matching on all three keys, the claim-age gate that
# keeps a pool recycle quiet, the cache-age degrade, and every fail-closed probe.
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

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/beta"

# Fixtures are written relative to real time because the check does its date
# arithmetic with jq's `now`.
NOW=$(date -u +%s)
ago() { date -u -d "@$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ; }

cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"},{"name":"beta","path":"$TMP/beta"}]}
EOF

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "session list") rc="${SESSIONS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$SESSIONS_JSON" ;;
  "rig list")     rc="${RIGS_RC:-0}";     [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
# The stub applies the same --status and --has-metadata-key filters the real bd
# applies server-side, so a fixture row the real tool would never return cannot
# reach the check here either.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
db=""; status=""; key=""; prev=""
for a in "$@"; do
  case "$prev" in
    --db) db="$a" ;;
    --status) status="$a" ;;
    --has-metadata-key) key="$a" ;;
  esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
f="$STORES/$name.json"; [ -f "$f" ] || { printf '[]'; exit 0; }
jq -c --arg s "$status" --arg k "$key" '
  [ .[] | select($s == "" or (.status // "") == $s)
        | select($k == "" or (((.metadata // {}) | has($k)))) ]' "$f"
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

run_check() {
    SESSIONS_JSON="${SESSIONS_JSON:-$TMP/sessions.json}" RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" \
    bash "$CHECK" 2>&1
}
# claim <id> <assignee> <seconds-ago>
claim() { printf '{"id":"%s","status":"in_progress","assignee":"%s","metadata":{"gc.step_ref":"mol-review.pin","gc.claimed_at":"%s"}}' "$1" "$2" "$(ago "$3")"; }
store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.json"; }
clear_stores() { rm -f "$TMP/stores/"*.json; }
# sessions <json-rows...> — cache age 0 unless CACHE is set
sessions() { local IFS=,; printf '{"_cache_age_s":%s,"sessions":[%s]}' "${CACHE:-0}" "$*" > "$TMP/sessions.json"; }
# live <id> <session_name> <alias> <last_active-seconds-ago>
live() { printf '{"id":"%s","session_name":"%s","alias":"%s","state":"active","running":true,"last_active":"%s"}' "$1" "$2" "$3" "$(ago "$4")"; }

# --- 1. a holder that is running and producing output is SILENT -----------
# The acceptance case: a long implementation step held for six hours by a
# session that is still working must not be reported.
sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
store alpha "$(claim a-1 rig/pool.polecat 21600)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a working holder is silent however long it has held the step"
hasnt "$OUT" "a-1" "the working holder's step is not named"
clear_stores

# --- 2. a running holder that has produced nothing past the bound ---------
sessions "$(live lx-1 pool-1 rig/pool.polecat 14400)"
store alpha "$(claim a-1 rig/pool.polecat 14400)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a parked holder past the bound is an ERROR"
has "$OUT" "a-1" "the error names the step"
has "$OUT" "rig/pool.polecat" "the error names the holder"
has "$OUT" "no output for 240m" "the error reports how long the holder has been quiet"
clear_stores

# --- 3. identity matching on each of the three keys -----------------------
for key in lx-1 pool-1 rig/pool.polecat; do
    sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
    store alpha "$(claim a-1 "$key" 7200)"
    OUT=$(run_check); RC=$?
    eq "$RC" "0" "a claim stamped with $key resolves to its session"
    clear_stores
done

# --- 4. an assignee no session carries is ORPHANED ------------------------
sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
store alpha "$(claim a-1 rig/pool.gone 7200)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a claim held by no session is an ERROR"
has "$OUT" "names no session" "the error says the holder does not exist"
has "$OUT" "a-1" "the orphan error names the step"
clear_stores

# --- 5. a holder that is not running is DEAD ------------------------------
sessions '{"id":"lx-1","session_name":"pool-1","alias":"rig/pool.polecat","state":"asleep","running":false,"last_active":""}'
store alpha "$(claim a-1 rig/pool.polecat 7200)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a claim whose holder is not running is an ERROR"
has "$OUT" "state=asleep" "the error names the holder's state"
clear_stores

# --- 6. the claim-age gate keeps a pool recycle quiet ---------------------
# A claim younger than the bound is never judged, so an incarnation swap under
# a live claim does not read as a fault.
sessions "$(live lx-2 pool-1 rig/pool.polecat 30)"
store alpha "$(claim a-1 lx-1 60)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a claim younger than the bound is not judged"
clear_stores
# ...but the same orphaned claim IS reported once it is older than the bound.
store alpha "$(claim a-1 lx-1 7200)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "the same orphaned claim past the bound IS reported"
clear_stores

# --- 7. only formula steps in a claimed state are judged ------------------
sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
store alpha \
  '{"id":"a-nostep","status":"in_progress","assignee":"rig/pool.gone","metadata":{}}' \
  '{"id":"a-open","status":"open","assignee":"rig/pool.gone","metadata":{"gc.step_ref":"mol-review.pin","gc.claimed_at":"2020-01-01T00:00:00Z"}}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a non-step and an open step are both skipped"
hasnt "$OUT" "a-nostep" "a bead with no gc.step_ref is not judged"
hasnt "$OUT" "a-open" "an open step is not judged"
clear_stores

# --- 7b. in_progress with NO assignee is UNHELD ---------------------------
# Reachable by neither path: no holder, and bd ready skips it because its
# status is not open. Both sibling checks scan --status open and miss it.
sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
store alpha "$(printf '{"id":"a-unheld","status":"in_progress","assignee":"","updated_at":"%s","metadata":{"gc.step_ref":"mol-review.pin"}}' "$(ago 7200)")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an in_progress step with no assignee is an ERROR"
has "$OUT" "a-unheld" "the error names the unheld step"
has "$OUT" "NO assignee" "the error says nothing holds it"
has "$OUT" "not open" "the error says bd ready cannot offer it either"
clear_stores
# The release window (assignee cleared, status not yet open) is a separate
# write and must not be reported.
store alpha "$(printf '{"id":"a-unheld","status":"in_progress","assignee":"","updated_at":"%s","metadata":{"gc.step_ref":"mol-review.pin"}}' "$(ago 60)")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a just-released step inside the bound is not reported"
clear_stores

# --- 8. a stale session cache degrades the verdict to a warning -----------
CACHE=7200 sessions "$(live lx-1 pool-1 rig/pool.polecat 14400)"
store alpha "$(claim a-1 rig/pool.polecat 14400)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a session cache older than the bound degrades STALLED to a warning"
has "$OUT" "cache" "the warning says the observation was cache-limited"
clear_stores

# ORPHANED and DEAD are read out of the same roster, so a stale one degrades
# them too: an absent session may be a holder that started after the snapshot,
# and running:false may be a state its holder has since left.
CACHE=7200 sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
store alpha "$(claim a-1 rig/pool.gone 7200)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a stale cache degrades ORPHANED to a warning"
has "$OUT" "a-1" "the orphan warning still names the step"
has "$OUT" "names no session" "the orphan warning still says the holder was not found"
has "$OUT" "started after that snapshot" "the orphan warning says why it is not judged"
clear_stores

CACHE=7200 sessions '{"id":"lx-1","session_name":"pool-1","alias":"rig/pool.polecat","state":"asleep","running":false,"last_active":""}'
store alpha "$(claim a-1 rig/pool.polecat 7200)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a stale cache degrades DEAD to a warning"
has "$OUT" "state=asleep" "the dead warning still names the holder's state"
has "$OUT" "may be running now" "the dead warning says why it is not judged"
clear_stores

# UNHELD is read off the bead, not the roster, so a stale cache cannot soften it.
CACHE=7200 sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
store alpha "$(printf '{"id":"a-unheld","status":"in_progress","assignee":"","updated_at":"%s","metadata":{"gc.step_ref":"mol-review.pin"}}' "$(ago 7200)")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a stale cache does not degrade UNHELD"
has "$OUT" "NO assignee" "the unheld error survives a stale roster"
clear_stores
unset CACHE

# --- 9. the bound is configurable ----------------------------------------
sessions "$(live lx-1 pool-1 rig/pool.polecat 600)"
store alpha "$(claim a-1 rig/pool.polecat 600)"
OUT=$(GC_DOCTOR_CLAIM_STALL_MINUTES=5 run_check); RC=$?
eq "$RC" "2" "a 5m bound reports a holder quiet for 10m"
OUT=$(GC_DOCTOR_CLAIM_STALL_MINUTES=60 run_check); RC=$?
eq "$RC" "0" "a 60m bound does not"
OUT=$(GC_DOCTOR_CLAIM_STALL_MINUTES=notanumber run_check); RC=$?
eq "$RC" "0" "a non-numeric bound falls back to the 30m default rather than 0"
clear_stores

# --- 10. multiple stores are all scanned ---------------------------------
sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
store alpha "$(claim a-1 rig/pool.gone 7200)"
store beta  "$(claim b-1 rig/pool.gone 7200)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "findings in either store are errors"
has "$OUT" "alpha step a-1" "the alpha finding is labelled by rig"
has "$OUT" "beta step b-1" "the beta finding is labelled by rig"
clear_stores

# --- 11. a suspended rig is skipped, not queried -------------------------
cat > "$TMP/rigs-suspended.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
store alpha "$(claim a-1 rig/pool.gone 7200)"
OUT=$(RIGS_JSON="$TMP/rigs-suspended.json" run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped"
has "$OUT" "suspended" "the note says why it was skipped"
hasnt "$OUT" "a-1" "the suspended store's beads are not judged"
clear_stores

# --- 12. every probe fails closed ----------------------------------------
sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
store alpha "$(claim a-1 rig/pool.polecat 7200)"

OUT=$(SESSIONS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable session list WARNS, never passes"
has "$OUT" "cannot determine" "the warning says the check did not run"

OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list WARNS, never passes"

printf '{"_cache_age_s":0,"sessions":[]}' > "$TMP/sessions-empty.json"
OUT=$(SESSIONS_JSON="$TMP/sessions-empty.json" run_check); RC=$?
eq "$RC" "1" "an EMPTY session roster warns instead of orphaning every claim"
hasnt "$OUT" "names no session" "an empty roster does not mass-report orphans"

printf 'not json' > "$TMP/sessions-bad.json"
OUT=$(SESSIONS_JSON="$TMP/sessions-bad.json" run_check); RC=$?
eq "$RC" "1" "an unparseable session list WARNS"

OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store WARNS and says it was not checked"
has "$OUT" "NOT checked" "the warning names the unchecked store"
clear_stores

# --- 13. an unparseable last_active is reported, not judged --------------
sessions '{"id":"lx-1","session_name":"pool-1","alias":"rig/pool.polecat","state":"active","running":true,"last_active":"whenever"}'
store alpha "$(claim a-1 rig/pool.polecat 7200)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a holder whose last_active does not parse is a note, not an error"
has "$OUT" "reported, not judged" "the note says liveness could not be judged"
clear_stores

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
