#!/usr/bin/env bash
# Hermetic test for doctor/check-session-store-scope. Stub tmux + fixture /proc.
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

CITY="$TMP/city"
mkdir -p "$TMP/bin" "$TMP/sessions" "$TMP/proc" "$CITY"

cat > "$TMP/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
while [ "${1:-}" = "-L" ]; do shift 2; done
case "${1:-}" in
  list-sessions)
      rc="${STUB_LIST_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"
      cat "$STUB_DIR/sessions.list" 2>/dev/null ;;
  show-environment)
      if [ "${2:-}" = "-g" ]; then
          rc="${STUB_GLOBAL_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"
          cat "$STUB_DIR/global.env" 2>/dev/null; exit 0
      fi
      [ "${2:-}" = "-t" ] || exit 1
      [ -f "$STUB_DIR/sessions/$3.env" ] || exit 1
      cat "$STUB_DIR/sessions/$3.env" ;;
  *) exit 1 ;;
esac
TMUX
chmod +x "$TMP/bin/tmux"

# session <name> <pid> — declares a session and its pane pid, in the one row
# `list-sessions -F` emits. Reads the session env on stdin; the pane env comes
# from pane().
session() {
    printf '%s\t%s\n' "$1" "$2" >> "$TMP/sessions.list"
    cat > "$TMP/sessions/$1.env"
}
pane() { mkdir -p "$TMP/proc/$1"; tr '\n' '\0' > "$TMP/proc/$1/environ"; }
reset_fixture() {
    rm -rf "$TMP/sessions" "$TMP/proc" "$TMP/sessions.list" "$TMP/global.env"
    mkdir -p "$TMP/sessions" "$TMP/proc"
    : > "$TMP/sessions.list"
}
run() {
    PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" GC_DOCTOR_PROC_ROOT="$TMP/proc" \
        GC_CITY_PATH="$CITY" GC_CITY="" bash "$CHECK" 2>&1
}

# A healthy pair: one city-scoped agent, one scoped to rig "alpha".
healthy() {
    reset_fixture
    session city__deacon 100 <<EOF
GC_AGENT=city.deacon
GC_ALIAS=city.deacon
GC_CITY_PATH=$CITY
-BEADS_DIR
EOF
    pane 100 <<EOF
GC_AGENT=city.deacon
GC_ALIAS=city.deacon
GC_CITY_PATH=$CITY
EOF
    session alpha--city__witness 200 <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
    pane 200 <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
}

# --- 1. environment the check cannot read is a note, never a finding ---------
# A PATH carrying every tool the check uses EXCEPT tmux, so "tmux is absent" is
# the only thing that differs from the runs below.
mkdir -p "$TMP/nomux"
for t in sed grep tr head timeout; do
    src=$(command -v "$t") && ln -sf "$src" "$TMP/nomux/$t"
done
healthy
OUT=$(PATH="$TMP/nomux" STUB_DIR="$TMP" GC_DOCTOR_PROC_ROOT="$TMP/proc" GC_CITY_PATH="$CITY" GC_CITY="" "$BASH" "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "no tmux on PATH is a note, not a finding"
has "$OUT" "not verifiable here" "the note says the answer is unknown, not clean"
healthy
OUT=$(PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" GC_DOCTOR_PROC_ROOT="$TMP/proc" GC_CITY_PATH="" GC_CITY="" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "outside a city the check is a note"
has "$OUT" "no city in scope" "the note names what is missing"

# --- 2. the happy path passes, and says what it read ------------------------
OUT=$(run); RC=$?
eq "$RC" "0" "a city-scoped and a rig-scoped session that agree with themselves pass"
has "$OUT" "2 agent session(s)" "the pass message counts the sessions it judged"
has "$OUT" "2 read at the running process" "the pass message counts the panes it actually read"

# --- 3. the reported symptom: a rig's store env on a city-scoped agent -------
healthy
pane 100 <<EOF
GC_AGENT=city.deacon
GC_ALIAS=city.deacon
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_BEADS_PREFIX=al
BEADS_DIR=$CITY/rigs/alpha/.beads
GC_STORE_SCOPE=rig
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a city-scoped agent holding a rig's store env is an ERROR"
has "$OUT" "city__deacon" "the polluted session is named"
has "$OUT" "GC_RIG=alpha" "the leaked scope key and value are named"
has "$OUT" "BEADS_DIR=$CITY/rigs/alpha/.beads" "the rig-rooted store path is named"
has "$OUT" "GC_STORE_SCOPE=rig" "the leaked store scope is named"
has "$OUT" "gc session reset city.deacon" "the finding carries the remedy"

# --- 4. the other half: a rig-scoped agent reading a DIFFERENT rig -----------
healthy
pane 200 <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=beta
GC_RIG_ROOT=$CITY/rigs/beta
BEADS_DIR=$CITY/rigs/beta/.beads
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a rig-scoped agent holding another rig's store env is an ERROR"
has "$OUT" "GC_RIG=beta" "the wrong rig is named"
has "$OUT" "names rig beta" "the path-valued keys resolve to the wrong rig"

# --- 5. a rig-scoped agent that lost its scope entirely ----------------------
healthy
pane 200 <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a rig-scoped agent holding no GC_RIG is an ERROR"
has "$OUT" "holds no GC_RIG" "the finding says the scope is missing, not wrong"
has "$OUT" "rig alpha" "the scope it should have had is named"

# --- 6. pool members carry no GC_ALIAS; the session name carries the rig -----
healthy
session alpha--city__polecat-1-pool 300 <<EOF
GC_AGENT=alpha--city__polecat-1-pool
GC_CITY_PATH=$CITY
GC_RIG=alpha
EOF
pane 300 <<EOF
GC_AGENT=alpha--city__polecat-1-pool
GC_CITY_PATH=$CITY
GC_RIG=beta
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "an aliasless pool member takes its rig from the session name"
has "$OUT" "alpha--city__polecat-1-pool" "the pool session is named"
has "$OUT" "scoped to rig alpha" "the rig came from the session-name prefix"

# --- 7. warm-respawn exposure: the server holds a key the session leaves open -
healthy
printf 'GC_RIG=alpha\n' > "$TMP/global.env"
OUT=$(run); RC=$?
eq "$RC" "1" "a store key on the tmux server that a city-scoped session neither sets nor removes is a WARNING"
has "$OUT" "city__deacon" "the exposed session is named"
has "$OUT" "respawn-pane" "the warning names the path that would inherit it"
has "$OUT" "tmux set-environment -gu GC_RIG" "the warning carries the remedy"
hasnt "$OUT" "alpha--city__witness is scoped to rig alpha" "a rig-scoped session that sets GC_RIG shadows the server's value and is not exposed for it"

# --- 7b. warm-respawn on a RIG-scoped session: a key it does not shadow ------
# The pre-open review's finding: a rig-scoped session sets GC_RIG, GC_RIG_ROOT
# and BEADS_DIR but never GC_STORE_SCOPE, so a server global for that key still
# reaches its respawn. Skipping rig-scoped sessions wholesale read rc=0 here.
healthy
printf 'GC_STORE_SCOPE=city\n' > "$TMP/global.env"
OUT=$(run); RC=$?
eq "$RC" "1" "a store key on the server that a RIG-scoped session neither sets nor removes is a WARNING"
has "$OUT" "alpha--city__witness is scoped to rig alpha" "the rig-scoped session is evaluated, not skipped"
has "$OUT" "GC_STORE_SCOPE=city" "the leaked store-scope key and value are named"
has "$OUT" "tmux set-environment -gu GC_STORE_SCOPE" "the warning carries the server-clear remedy"

# --- 8. the withholding marker is what clears it (the fix's own effect) ------
healthy
printf 'GC_RIG=alpha\n' > "$TMP/global.env"
cat > "$TMP/sessions/city__deacon.env" <<EOF
GC_AGENT=city.deacon
GC_ALIAS=city.deacon
GC_CITY_PATH=$CITY
-BEADS_DIR
-GC_RIG
EOF
OUT=$(run); RC=$?
eq "$RC" "0" "a session env marking the key removed is not exposed to the respawn"
healthy
printf 'BEADS_DIR=%s/rigs/alpha/.beads\n' "$CITY" > "$TMP/global.env"
OUT=$(run); RC=$?
eq "$RC" "0" "BEADS_DIR is already marked removed on a city-scoped session, so the server's value cannot reach it"

# --- 9. sessions that are not this city's agents are out of scope ------------
healthy
session other__deacon 400 <<EOF
GC_AGENT=other.deacon
GC_ALIAS=other.deacon
GC_CITY_PATH=$TMP/elsewhere
GC_RIG=alpha
EOF
pane 400 <<EOF
GC_AGENT=other.deacon
GC_RIG=alpha
EOF
session plain-shell 500 <<'EOF'
SHELL=/bin/bash
EOF
pane 500 <<'EOF'
SHELL=/bin/bash
EOF
OUT=$(run); RC=$?
eq "$RC" "0" "another city's session and a non-agent session are both skipped"
has "$OUT" "2 agent session(s)" "neither is counted as judged"

# --- 10. an unread pane is a note, and the pass message says so -------------
healthy
rm -rf "$TMP/proc/200"
OUT=$(run); RC=$?
eq "$RC" "0" "an unreadable pane process is a note, not a finding"
has "$OUT" "1 read at the running process" "the count separates sessions judged from panes read"
has "$OUT" "environment unreadable" "the note says which session went unread"

# --- 11. a session that ends mid-scan is not a finding -----------------------
healthy
printf 'vanished\n' >> "$TMP/sessions.list"
OUT=$(run); RC=$?
eq "$RC" "0" "a session listed but gone by the time it is read is skipped"

# --- 12. fail-CLOSED: an unreadable session list warns, never passes ---------
healthy
OUT=$(PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_LIST_RC=1 GC_DOCTOR_PROC_ROOT="$TMP/proc" GC_CITY_PATH="$CITY" GC_CITY="" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "an unlistable tmux server warns, never passes"
has "$OUT" "UNVERIFIED" "the warning says the answer is unknown"

# --- 13. fail-CLOSED: an unreadable global environment warns, never passes ----
# Arm 2 reads only the server's global environment. If that probe fails after
# list-sessions succeeds, every key looks absent and the arm would pass in
# silence; on an otherwise-healthy fixture the aggregate must still warn.
healthy
OUT=$(PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_GLOBAL_RC=9 GC_DOCTOR_PROC_ROOT="$TMP/proc" GC_CITY_PATH="$CITY" GC_CITY="" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "an unreadable tmux global environment warns, never passes"
has "$OUT" "warm-respawn inheritance UNVERIFIED" "the warning names the arm it could not verify"
hasnt "$OUT" "agree with their own store scope" "a failed global probe cannot reach the OK line"

echo
echo "check-session-store-scope: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
