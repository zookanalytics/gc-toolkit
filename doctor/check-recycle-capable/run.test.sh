#!/usr/bin/env bash
# Hermetic test for doctor/check-recycle-capable. gc and curl are stubbed; the
# defer-guard arm runs against a REAL git repo, because that arm parses git's
# porcelain output and ages real mtimes, and a stub would prove neither.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
epoch_stamp() { date -d "@$1" '+%Y%m%d%H%M.%S' 2>/dev/null || date -r "$1" '+%Y%m%d%H%M.%S'; }
age_file() { touch -t "$(epoch_stamp "$(($(date +%s) - $2))")" "$1"; }

mkdir -p "$TMP/bin" "$TMP/api" "$TMP/pack/overlays/cycle-recycle/.claude/hooks"
: > "$TMP/pack/overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh"

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$*" in
  "cities --json")    [ -n "${CITIES_RC:-}" ] && exit "$CITIES_RC"; cat "$CITIES_JSON" ;;
  *"status --json")   [ -n "${STATUS_RC:-}" ] && exit "$STATUS_RC"; cat "$STATUS_JSON" ;;
  *"rig list --json") [ -n "${RIGS_RC:-}" ] && exit "$RIGS_RC"; cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
# Serves the agent endpoint by fixture file; a missing fixture is curl -f's
# 404 exit, which is what an unreachable supervisor looks like to the hook.
cat > "$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
url=""; for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
printf '%s\n' "$url" >> "${CURL_LOG:-/dev/null}"
f="$API_DIR/$(printf '%s' "${url##*/agent/}" | tr '/' '_').json"
[ -s "$f" ] || exit 22
cat "$f"
CURL
chmod +x "$TMP/bin/gc" "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

cat > "$TMP/cities.json" <<EOF
{"cities":[{"name":"testcity","path":"$TMP/city"}]}
EOF
# alpha runs both patrol roles; the city-scope deacon has no rig prefix; the
# polecat proves the role self-gate; beta's are asleep and suspended.
cat > "$TMP/status.json" <<'EOF'
{"agents":[
 {"name":"gc-toolkit.refinery","qualified_name":"alpha/gc-toolkit.refinery","scope":"rig","running":true,"suspended":false},
 {"name":"gc-toolkit.witness","qualified_name":"alpha/gc-toolkit.witness","scope":"rig","running":true,"suspended":false},
 {"name":"gc-toolkit.deacon","qualified_name":"gc-toolkit.deacon","scope":"city","running":true,"suspended":false},
 {"name":"gc-toolkit.polecat-1","qualified_name":"alpha/gc-toolkit.polecat-1","scope":"rig","running":true,"suspended":false},
 {"name":"gc-toolkit.witness","qualified_name":"beta/gc-toolkit.witness","scope":"rig","running":false,"suspended":false},
 {"name":"gc-toolkit.refinery","qualified_name":"beta/gc-toolkit.refinery","scope":"rig","running":true,"suspended":true}]}
EOF
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/rigs/alpha","suspended":false},
         {"name":"beta","path":"$TMP/rigs/beta","suspended":false}]}
EOF

healthy_api() {
  for a in alpha_gc-toolkit.refinery alpha_gc-toolkit.witness gc-toolkit.deacon; do
    printf '{"name":"%s","running":true,"state":"working","input_tokens":41234}\n' "$a" > "$TMP/api/$a.json"
  done
}
healthy_api

mkdir -p "$TMP/rigs/alpha/.beads"
git -C "$TMP/rigs/alpha" init -q
git -C "$TMP/rigs/alpha" config user.email t@example.com
git -C "$TMP/rigs/alpha" config user.name Tester
printf 'dolt.mode: local\n' > "$TMP/rigs/alpha/.beads/config.yaml"
git -C "$TMP/rigs/alpha" add -A
git -C "$TMP/rigs/alpha" -c commit.gpgsign=false commit -qm init

run_check() {
  : > "$TMP/curl.log"
  GC_PACK_DIR="$TMP/pack" GC_CITY_PATH="$TMP/city" GC_API_URL="http://stub" \
  CITIES_JSON="${CITIES_JSON:-$TMP/cities.json}" STATUS_JSON="${STATUS_JSON:-$TMP/status.json}" \
  RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" \
  API_DIR="$TMP/api" CURL_LOG="$TMP/curl.log" bash "$CHECK" 2>&1
}

# --- 1. healthy and idle: silent ---------------------------------------------
OUT=$(run_check); RC=$?
eq "$RC" "0" "a numeric input_tokens and a clean rig tree is OK"
has "$OUT" "3 patrol agent(s)" "the three awake patrol agents were measured"
hasnt "$OUT" "defer guard true" "a clean tree raises no deferral note"
LOG=$(cat "$TMP/curl.log")
has "$LOG" "http://stub/v0/city/testcity/agent/alpha/gc-toolkit.refinery" "the probe is the hook's own URL shape"
hasnt "$LOG" "polecat" "a non-patrol agent is never probed"
hasnt "$LOG" "beta" "an asleep or suspended patrol agent is never probed"
has "$OUT" "beta/gc-toolkit.refinery: suspended" "the suspended agent is noted, not judged"

# --- 2. input_tokens ABSENT — the live failure -------------------------------
printf '{"name":"a","running":true,"state":"working"}\n' > "$TMP/api/alpha_gc-toolkit.refinery.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an absent input_tokens field is an ERROR, not a silent skip"
has "$OUT" "no input_tokens field" "the finding names the missing measurement"
has "$OUT" "alpha/gc-toolkit.refinery" "the finding names the agent"
has "$OUT" "http://stub/v0/city/testcity/agent/" "the finding names the endpoint"
has "$OUT" "200000" "the finding states why 0 can never cross the threshold"
hasnt "$OUT" "alpha/gc-toolkit.witness" "an agent whose endpoint is healthy is not implicated"

# --- 3. input_tokens present but non-numeric ---------------------------------
printf '{"name":"a","running":true,"input_tokens":"lots"}\n' > "$TMP/api/alpha_gc-toolkit.refinery.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a non-numeric input_tokens is an ERROR"
has "$OUT" "non-numeric input_tokens" "the finding names the shape of the bad value"
has "$OUT" "input_tokens=lots" "the finding quotes the value the hook would reject"

# --- 4. a null value reads as no measurement ---------------------------------
printf '{"name":"a","running":true,"input_tokens":null}\n' > "$TMP/api/alpha_gc-toolkit.refinery.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "input_tokens:null is an ERROR — \`// 0\` makes it read as 0 tokens"
has "$OUT" "no input_tokens field" "a null value is reported as no measurement"

# --- 5. the endpoint itself unreachable: warn, never pass --------------------
rm -f "$TMP/api/alpha_gc-toolkit.refinery.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unreachable endpoint warns — the field's presence is undetermined"
has "$OUT" "returned nothing" "the warning says the probe came back empty"
healthy_api

# --- 6. a body that is not a JSON object -------------------------------------
printf '<html>502 Bad Gateway</html>\n' > "$TMP/api/alpha_gc-toolkit.refinery.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable body warns — it is not evidence the field was removed"
has "$OUT" "could not read as a JSON object" "the warning says the body could not be read"
hasnt "$OUT" "no input_tokens field" "and does not accuse the endpoint of dropping the field"
healthy_api

# --- 7. the city path resolves to no city name -------------------------------
printf '{"cities":[{"name":"other","path":"/somewhere/else"}]}\n' > "$TMP/cities-miss.json"
OUT=$(CITIES_JSON="$TMP/cities-miss.json" run_check); RC=$?
eq "$RC" "2" "a city path that resolves to no name is an ERROR"
has "$OUT" "exits before measuring" "the finding states the hook's own silent exit"

# --- 8. fail-CLOSED on unreadable rosters ------------------------------------
OUT=$(CITIES_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable city roster warns, never passes"
OUT=$(STATUS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable agent roster warns, never passes"
has "$OUT" "neither arm below ran" "the warning says nothing was asserted"
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable rig roster warns — a latched guard would be invisible"
has "$OUT" "defer-guard arm did not run" "the warning names the arm that was skipped"

# --- 9. a roster that carries agents but no patrol role ----------------------
# `expected` is the same filter as `rows`, so a total enumeration loss agrees
# with itself; only the roster's own size tells it from a city that runs none.
cat > "$TMP/status-norole.json" <<'EOF'
{"agents":[{"name":"gc-toolkit.polecat-1","qualified_name":"alpha/gc-toolkit.polecat-1","scope":"rig","running":true,"suspended":false}]}
EOF
OUT=$(STATUS_JSON="$TMP/status-norole.json" run_check); RC=$?
eq "$RC" "1" "a roster with agents but no patrol role warns, never reports OK"
has "$OUT" "roster's naming moved" "the warning names the drift it cannot rule out"
printf '{"agents":[]}\n' > "$TMP/status-empty.json"
OUT=$(STATUS_JSON="$TMP/status-empty.json" run_check); RC=$?
eq "$RC" "0" "a city that runs no agent at all measures nothing and stays silent"

# --- 10. LATCHED defer guard — the other live failure ------------------------
printf 'dolt.mode: server\n' > "$TMP/rigs/alpha/.beads/config.yaml"
age_file "$TMP/rigs/alpha/.beads/config.yaml" $((23 * 86400))
OUT=$(run_check); RC=$?
eq "$RC" "2" "a tracked file dirty past the bound is an ERROR, not a deferral"
has "$OUT" ".beads/config.yaml" "the finding names the file that latched the guard"
has "$OUT" "23d" "the finding states how long the guard has been true"
has "$OUT" "rig alpha" "the finding names the rig whose refinery is stuck"
has "$OUT" "24h bound" "the finding states the bound it crossed"

# --- 11. the bound is configurable -------------------------------------------
OUT=$(GC_DOCTOR_RECYCLE_LATCH_HOURS=$((30 * 24)) run_check); RC=$?
eq "$RC" "0" "a bound wider than the age reads the same tree as a git op in flight"
has "$OUT" "inside the 720h bound" "the override is the bound the note reports"

# --- 12. a TRANSIENT dirty tree is not a latch -------------------------------
touch "$TMP/rigs/alpha/.beads/config.yaml"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a freshly dirtied tree is a git op in flight, not a latch"
has "$OUT" "defer guard true" "the transient deferral is noted"
hasnt "$OUT" "cannot fire" "and it is not a finding"
git -C "$TMP/rigs/alpha" checkout -q -- .beads/config.yaml

# --- 13. an in-flight git-op marker is recognised ----------------------------
: > "$TMP/rigs/alpha/.git/MERGE_HEAD"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a fresh merge marker defers normally"
has "$OUT" "MERGE_HEAD (git-op in progress)" "the marker is named as the guard's source"
age_file "$TMP/rigs/alpha/.git/MERGE_HEAD" $((3 * 86400))
OUT=$(run_check); RC=$?
eq "$RC" "2" "a merge marker older than the bound is a latch, not an op in flight"
has "$OUT" "MERGE_HEAD" "the stale marker is named"
rm -f "$TMP/rigs/alpha/.git/MERGE_HEAD"

# --- 14. untracked files never latch the guard -------------------------------
# The hook passes --untracked-files=no, so scratch must not read as a git op.
echo scratch > "$TMP/rigs/alpha/scratch.tmp"
age_file "$TMP/rigs/alpha/scratch.tmp" $((40 * 86400))
OUT=$(run_check); RC=$?
eq "$RC" "0" "an untracked file is scratch, not a defer guard"
hasnt "$OUT" "scratch.tmp" "and it is named in no finding"
rm -f "$TMP/rigs/alpha/scratch.tmp"

# --- 15. a rig with no refinery is not read ----------------------------------
cat > "$TMP/status-nowork.json" <<'EOF'
{"agents":[{"name":"gc-toolkit.witness","qualified_name":"alpha/gc-toolkit.witness","scope":"rig","running":true,"suspended":false}]}
EOF
printf 'dolt.mode: server\n' > "$TMP/rigs/alpha/.beads/config.yaml"
age_file "$TMP/rigs/alpha/.beads/config.yaml" $((23 * 86400))
OUT=$(STATUS_JSON="$TMP/status-nowork.json" run_check); RC=$?
eq "$RC" "0" "the guard is refinery-only — a witness-only rig is not read"
hasnt "$OUT" "config.yaml" "no dirty-tree finding is raised for it"
git -C "$TMP/rigs/alpha" checkout -q -- .beads/config.yaml

# --- 16. a pack that ships no hook has nothing to assert ---------------------
mkdir -p "$TMP/emptypack"
OUT=$(GC_PACK_DIR="$TMP/emptypack" GC_CITY_PATH="$TMP/city" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a pack with no cycle-recycle overlay is OK"
has "$OUT" "ships no cycle-recycle hook" "and says why it asserted nothing"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
