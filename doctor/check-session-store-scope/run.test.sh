#!/usr/bin/env bash
# Hermetic test for doctor/check-session-store-scope. Stub tmux, with a fixture
# /proc or a stub ps. Section 19 reads a real child process through the host's
# own reader, which stays hermetic because the process is one the suite starts.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-session-store-scope-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

CITY="$TMP/city"
mkdir -p "$TMP/bin" "$TMP/sessions" "$TMP/proc" "$CITY"

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/tmux" <<'TMUX'
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
      # A designated session reads slowly, so a probe run against the time still
      # left in the check budget is killed with 124 — the mid-scan exhaustion case.
      if [ -n "${STUB_SLOW_SESSION:-}" ] && [ "$3" = "$STUB_SLOW_SESSION" ]; then
          sleep "${STUB_SLOW_SECS:-30}"
      fi
      [ -f "$STUB_DIR/sessions/$3.env" ] || exit 1
      cat "$STUB_DIR/sessions/$3.env" ;;
  *) exit 1 ;;
esac
TMUX
chmod +x "$TMP/bin/tmux"

# Kept apart from the tmux stub, so section 19 can run the real ps beside it.
mkdir -p "$TMP/psbin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/psbin/ps" <<'PS'
# `ps -ww -o command= -p <pid>` prints the command line, and -E adds the
# environment after it, joined by spaces. A pid with no .cmd file has ended, and
# one with no .env file hides its environment. A .fullcmd file is the command
# line the -E read sees, for a pid that changes hands between the two reads.
flag=plain; pid=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -E) flag=-E ;;
        -p) pid="$2"; shift ;;
    esac
    shift
done
if [ "$pid" = "${STUB_PS_SLOW_PID:-}" ] && [ "${STUB_PS_SLOW_FLAG:-$flag}" = "$flag" ]; then
    sleep "${STUB_SLOW_SECS:-30}"
fi
[ -f "$STUB_DIR/ps/$pid.cmd" ] || exit 1
line=$(cat "$STUB_DIR/ps/$pid.cmd")
if [ "$flag" = -E ]; then
    [ ! -f "$STUB_DIR/ps/$pid.fullcmd" ] || line=$(cat "$STUB_DIR/ps/$pid.fullcmd")
    if [ -f "$STUB_DIR/ps/$pid.env" ]; then
        entries=$(LC_ALL=C tr '\n' ' ' < "$STUB_DIR/ps/$pid.env")
        line="$line ${entries% }"
    fi
fi
printf '%s\n' "$line"
PS
chmod +x "$TMP/psbin/ps"

# session <name> <pid> — declares a session and its pane pid, in the one row
# `list-sessions -F` emits. Reads the session env on stdin; the pane env comes
# from pane().
session() {
    printf '%s\t%s\n' "$1" "$2" >> "$TMP/sessions.list"
    cat > "$TMP/sessions/$1.env"
}
pane() { mkdir -p "$TMP/proc/$1"; tr '\n' '\0' > "$TMP/proc/$1/environ"; }
# ps_pane <pid> <command line> — what ps shows for pid on a host with no proc
# filesystem. Reads the process's environment on stdin, one KEY=value per line.
ps_pane() { mkdir -p "$TMP/ps"; printf '%s\n' "$2" > "$TMP/ps/$1.cmd"; cat > "$TMP/ps/$1.env"; }
reset_fixture() {
    rm -rf "$TMP/sessions" "$TMP/proc" "$TMP/sessions.list" "$TMP/global.env"
    mkdir -p "$TMP/sessions" "$TMP/proc"
    : > "$TMP/sessions.list"
}
run() {
    PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" GC_DOCTOR_PROC_ROOT="$TMP/proc" \
        GC_CITY_PATH="$CITY" GC_CITY="" bash "$CHECK" 2>&1
}
# A host with no proc filesystem: the proc root is missing, and ps answers.
run_ps() {
    PATH="$TMP/psbin:$TMP/bin:$PATH" STUB_DIR="$TMP" GC_DOCTOR_PROC_ROOT="$TMP/no-proc" \
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

# --- 4b. a rig-scoped agent pointing at the CITY store -----------------------
# rig_named_by resolves only paths under <city>/rigs/, so a rig-scoped pane
# holding the city store — BEADS_DIR=<city>/.beads or GC_STORE_ROOT=<city> —
# resolved to empty and was skipped, passing rc=0. The city store is another
# store than this rig's, so it is a mismatch, not a path the check cannot place.
healthy
pane 200 <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/.beads
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a rig-scoped agent whose BEADS_DIR is the city bead store is an ERROR"
has "$OUT" "BEADS_DIR=$CITY/.beads" "the city bead store path is named"
has "$OUT" "the city store" "the finding says the value resolves to the city store"
has "$OUT" "gc session reset alpha/city.witness" "the finding carries the remedy"
healthy
pane 200 <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
GC_STORE_ROOT=$CITY
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a rig-scoped agent whose GC_STORE_ROOT is the city store root is an ERROR"
has "$OUT" "GC_STORE_ROOT=$CITY" "the city store root path is named"
# The no-other-rig fallback stays: a path the check cannot place against a rig
# without config is not a finding, only the known city store is.
healthy
pane 200 <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=/opt/external/store/.beads
EOF
OUT=$(run); RC=$?
eq "$RC" "0" "an unplaceable external store path is not a finding (the no-other-rig fallback holds)"

# --- 4c. the session env itself names another rig; the running pane does not --
# Arm 1 reads the pane process and Arm 2 reads the server global, so a wrong
# store scope SET in the session environment — what respawn-pane hands the next
# process — is caught by neither. The pane here still holds the right scope, so
# the finding is the session env's alone.
healthy
cat > "$TMP/sessions/alpha--city__witness.env" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=beta
GC_RIG_ROOT=$CITY/rigs/beta
BEADS_DIR=$CITY/rigs/beta/.beads
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a rig-scoped session whose session env names another rig is an ERROR"
has "$OUT" "alpha--city__witness is scoped to rig alpha" "the session is judged against its derived scope"
has "$OUT" "session environment sets GC_RIG=beta" "the wrong session-env value is named"
has "$OUT" "respawn-pane" "the finding names the path that would inherit it"
has "$OUT" "gc session reset alpha/city.witness" "the finding carries the remedy"
hasnt "$OUT" "running process holds GC_RIG=beta" "the still-correct pane is not the source of the finding"

# --- 4d. a correct session env is not flagged, even when the pane is wrong ----
# The session-env arm keys on the session's derived scope, not on the pane, so a
# session env that agrees with its scope stays silent while Arm 1 reports the
# pane. This pins the arm to session-env-set values and off the pane's.
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
eq "$RC" "2" "a wrong pane with a correct session env is still an ERROR (Arm 1)"
has "$OUT" "running process holds GC_RIG=beta" "Arm 1 reports the pane"
hasnt "$OUT" "session environment sets GC_RIG=beta" "a correct session env is not flagged by the session-env arm"

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

# --- 6. a pool member's rig comes from GC_TEMPLATE, not its session name ------
# A member of an unaliased pool carries no GC_ALIAS, and it is named
# <binding>__<agent>-<id> whichever rig imported its pack, so the name opens
# with the pack binding.
# Here a pack bound as "alpha", the name rig alpha also has, runs a polecat for
# rig beta. Only its GC_TEMPLATE, beta/alpha.polecat, names its rig, and the
# beta store keys it holds are its own.
healthy
session alpha__polecat-hq-wisp-1 300 <<EOF
GC_AGENT=hq-wisp-1
GC_TEMPLATE=beta/alpha.polecat
GC_CITY_PATH=$CITY
GC_RIG=beta
GC_RIG_ROOT=$CITY/rigs/beta
BEADS_DIR=$CITY/rigs/beta/.beads
EOF
pane 300 <<EOF
GC_AGENT=hq-wisp-1
GC_TEMPLATE=beta/alpha.polecat
GC_CITY_PATH=$CITY
GC_RIG=beta
GC_RIG_ROOT=$CITY/rigs/beta
BEADS_DIR=$CITY/rigs/beta/.beads
EOF
OUT=$(run); RC=$?
eq "$RC" "0" "a pool member of another rig, named for its pack, that holds its own rig's store keys passes"
has "$OUT" "3 agent session(s)" "the pool member is judged, not skipped"
has "$OUT" "3 read at the running process" "the pool member's running process is read"
hasnt "$OUT" "scoped to rig alpha" "the session name's pack binding is not read as its rig"

# --- 6b. a pool member whose pack shares its rig's name -----------------------
healthy
session alpha__polecat-hq-wisp-2 310 <<EOF
GC_AGENT=hq-wisp-2
GC_TEMPLATE=alpha/alpha.polecat
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
pane 310 <<EOF
GC_AGENT=hq-wisp-2
GC_TEMPLATE=alpha/alpha.polecat
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
OUT=$(run); RC=$?
eq "$RC" "0" "a pool member that agrees with its template's rig passes"
has "$OUT" "3 agent session(s)" "the pool member is judged, not skipped"

# --- 6c. GC_TEMPLATE still catches the leak the check exists for --------------
# A rig alpha template whose environment holds rig beta's GC_RIG is an ERROR,
# both in the running process and in the session environment a respawn gets.
healthy
session alpha__polecat-hq-wisp-3 320 <<EOF
GC_AGENT=hq-wisp-3
GC_TEMPLATE=alpha/alpha.polecat
GC_CITY_PATH=$CITY
GC_RIG=beta
EOF
pane 320 <<EOF
GC_AGENT=hq-wisp-3
GC_TEMPLATE=alpha/alpha.polecat
GC_CITY_PATH=$CITY
GC_RIG=beta
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a pool member whose environment holds another rig's GC_RIG than its template names is an ERROR"
has "$OUT" "alpha__polecat-hq-wisp-3 is scoped to rig alpha" "the rig came from GC_TEMPLATE"
has "$OUT" "running process holds GC_RIG=beta" "the running process's leak is named"
has "$OUT" "session environment sets GC_RIG=beta" "the session environment's leak is named"
has "$OUT" "gc session reset hq-wisp-3" "the finding carries the remedy"

# --- 6d. a leak the session name would hide -----------------------------------
# A polecat of rig beta whose environment holds rig alpha's store keys, where
# alpha is also its pack binding. Reading the rig off the name would call this
# session clean; its GC_TEMPLATE names rig beta, so it is an ERROR.
healthy
session alpha__polecat-hq-wisp-4 330 <<EOF
GC_AGENT=hq-wisp-4
GC_TEMPLATE=beta/alpha.polecat
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
pane 330 <<EOF
GC_AGENT=hq-wisp-4
GC_TEMPLATE=beta/alpha.polecat
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a pool member holding the store keys of the rig its name opens with, not its template's, is an ERROR"
has "$OUT" "alpha__polecat-hq-wisp-4 is scoped to rig beta" "the rig came from GC_TEMPLATE, not the name"
has "$OUT" "running process holds GC_RIG=alpha" "the wrong rig is named"
has "$OUT" "names rig alpha" "the path-valued keys resolve to the wrong rig"

# --- 6e. a city pool member: a bare template and no GC_RIG --------------------
# A city-scoped pool's template names no rig, <binding>.<agent>, so the session
# is city-scoped whatever its name opens with, and holding no GC_RIG is right.
healthy
session city__dog-hq-wisp-5 340 <<EOF
GC_AGENT=hq-wisp-5
GC_TEMPLATE=city.dog
GC_CITY_PATH=$CITY
-BEADS_DIR
EOF
pane 340 <<EOF
GC_AGENT=hq-wisp-5
GC_TEMPLATE=city.dog
GC_CITY_PATH=$CITY
EOF
OUT=$(run); RC=$?
eq "$RC" "0" "a city pool member with a bare template and no GC_RIG passes"
has "$OUT" "3 agent session(s)" "the city pool member is judged, not skipped"
hasnt "$OUT" "scoped to rig city" "the session name's pack binding is not read as a rig"

# --- 6f. a bare template is still judged as city-scoped -----------------------
healthy
session city__dog-hq-wisp-6 350 <<EOF
GC_AGENT=hq-wisp-6
GC_TEMPLATE=city.dog
GC_CITY_PATH=$CITY
-BEADS_DIR
EOF
pane 350 <<EOF
GC_AGENT=hq-wisp-6
GC_TEMPLATE=city.dog
GC_CITY_PATH=$CITY
GC_RIG=alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a city pool member whose running process holds a rig's store env is an ERROR"
has "$OUT" "city__dog-hq-wisp-6 is city-scoped" "the bare template made it city-scoped"
has "$OUT" "running process holds GC_RIG=alpha" "the leaked rig is named"

# --- 6g. no alias and no template: unverified, never guessed ------------------
# With neither key the session has no scope of its own to agree with. Its name
# is not read in their place, whatever form it takes, so the session is a
# WARNING that names it and never an error against a guessed rig.
healthy
session alpha--city__polecat-hq-wisp-7 360 <<EOF
GC_AGENT=hq-wisp-7
GC_CITY_PATH=$CITY
GC_RIG=beta
EOF
pane 360 <<EOF
GC_AGENT=hq-wisp-7
GC_CITY_PATH=$CITY
GC_RIG=beta
EOF
OUT=$(run); RC=$?
eq "$RC" "1" "a session carrying neither GC_ALIAS nor GC_TEMPLATE is a WARNING"
has "$OUT" "alpha--city__polecat-hq-wisp-7 carries GC_AGENT but neither GC_ALIAS nor GC_TEMPLATE" "the warning names the session and what it lacks"
has "$OUT" "UNVERIFIED" "the warning says the answer is unknown"
hasnt "$OUT" "alpha--city__polecat-hq-wisp-7 is scoped to rig" "no rig is read off the session name"
hasnt "$OUT" "OK:" "an unjudged session cannot reach the OK line"
healthy
printf 'GC_STORE_SCOPE=city\n' > "$TMP/global.env"
session city__polecat-hq-wisp-8 370 <<EOF
GC_AGENT=hq-wisp-8
GC_CITY_PATH=$CITY
EOF
OUT=$(run); RC=$?
eq "$RC" "1" "an unjudged session is still read for warm-respawn exposure"
has "$OUT" "city__polecat-hq-wisp-8 is of undetermined scope and its session environment neither sets nor removes GC_STORE_SCOPE" "the respawn arm runs on a session whose scope is unknown"

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

# --- 14. fail-CLOSED: a budget-truncated scan warns, never passes ------------
# run_bounded returns 124 once the whole-check budget is spent. The per-session
# read used to route every nonzero the way it routes a vanished session — a
# silent `continue` — so a scan that ran out of budget mid-list fell through to
# the OK line past sessions it never read. Here the first session reads fine and
# the second is still listed but its read is truncated by the budget; that second
# session is misconfigured (GC_RIG names beta on an alpha session), so the
# pre-fix check reached `exit 0` "OK: 1 agent session(s) agree" with a bad
# session unexamined. An unread still-listed session is UNVERIFIED, not clean.
healthy
cat > "$TMP/sessions/alpha--city__witness.env" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=beta
GC_RIG_ROOT=$CITY/rigs/beta
BEADS_DIR=$CITY/rigs/beta/.beads
EOF
OUT=$(PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_SLOW_SESSION=alpha--city__witness STUB_SLOW_SECS=30 \
    GC_DOCTOR_CHECK_TIMEOUT=8 GC_DOCTOR_PROC_ROOT="$TMP/proc" GC_CITY_PATH="$CITY" GC_CITY="" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "a scan truncated by the check budget warns, never passes"
has "$OUT" "UNVERIFIED" "the warning says the truncated scan left a session unverified"
has "$OUT" "budget" "the warning names the check budget as the cause"
has "$OUT" "alpha--city__witness" "the warning names the still-listed session it could not read"
hasnt "$OUT" "OK:" "a budget-truncated scan cannot reach the OK line"

# --- 15. a host with no proc filesystem reads the running process through ps --
# The proc root is missing, as on macOS, and the stub ps prints what ps -E prints
# there: the command line, then the environment, joined by spaces. Each case
# starts from a pair that agrees with itself, so a finding comes from the pane.
ps_healthy() {
    healthy
    rm -rf "${TMP:?}/proc" "${TMP:?}/ps"
    ps_pane 100 "/usr/local/bin/claude --session-id one" <<EOF
GC_AGENT=city.deacon
GC_ALIAS=city.deacon
GC_CITY_PATH=$CITY
EOF
    ps_pane 200 "/usr/local/bin/claude --session-id two" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
}
ps_healthy
OUT=$(run_ps); RC=$?
eq "$RC" "0" "with no proc filesystem, sessions that agree with themselves pass"
has "$OUT" "2 read at the running process" "ps read both running processes"
hasnt "$OUT" "unreadable" "no pane is reported unread"

# --- 15b. the leak the running-process arm exists for, read through ps --------
# The session environments are right, so the running process is the only place
# these show.
ps_healthy
ps_pane 200 "/usr/local/bin/claude --session-id two" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=beta
GC_RIG_ROOT=$CITY/rigs/beta
BEADS_DIR=$CITY/rigs/beta/.beads
EOF
OUT=$(run_ps); RC=$?
eq "$RC" "2" "a rig-scoped process holding another rig's store env is an ERROR through ps"
has "$OUT" "running process holds GC_RIG=beta" "the wrong rig is named"
has "$OUT" "BEADS_DIR=$CITY/rigs/beta/.beads, which names rig beta" "the path-valued key resolves to the wrong rig"
hasnt "$OUT" "session environment sets" "the correct session environment is not the finding"
ps_healthy
ps_pane 100 "/usr/local/bin/claude --session-id one" <<EOF
GC_AGENT=city.deacon
GC_ALIAS=city.deacon
GC_CITY_PATH=$CITY
GC_RIG=alpha
EOF
OUT=$(run_ps); RC=$?
eq "$RC" "2" "a city-scoped process holding a rig's GC_RIG is an ERROR through ps"
has "$OUT" "city__deacon is city-scoped but its running process holds GC_RIG=alpha" "the leaked scope key is named"

# --- 15c. words in the command line are not the environment -------------------
# An agent's arguments carry its prompt, and a prompt can spell out a store key.
# Read as the environment, this text would blame a clean city-scoped agent, and
# would hide that a rig-scoped one lost its GC_RIG.
ps_healthy
ps_pane 100 "/usr/local/bin/claude --append-system-prompt run with GC_RIG=beta BEADS_DIR=$CITY/rigs/beta/.beads GC_STORE_SCOPE=rig now" <<EOF
GC_AGENT=city.deacon
GC_ALIAS=city.deacon
GC_CITY_PATH=$CITY
EOF
OUT=$(run_ps); RC=$?
eq "$RC" "0" "store keys written in the command line are not read as the process's environment"
has "$OUT" "2 read at the running process" "the process with those words was still read"
ps_healthy
ps_pane 200 "/usr/local/bin/claude --append-system-prompt run with GC_RIG=alpha now" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
EOF
OUT=$(run_ps); RC=$?
eq "$RC" "2" "GC_RIG in the command line does not stand in for one the environment lacks"
has "$OUT" "running process holds no GC_RIG" "the missing key is reported"

# --- 15d. values are split on entries, not on spaces --------------------------
ps_healthy
ps_pane 200 "/usr/local/bin/claude --session-id two" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
EMPTY=
GC_RIG_ROOT=$CITY/rigs/beta/a checkout
GIT_SSH_COMMAND=ssh -o ServerAliveInterval=20 -o ServerAliveCountMax=90
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
OUT=$(run_ps); RC=$?
eq "$RC" "2" "a path value holding a space is still judged"
has "$OUT" "GC_RIG_ROOT=$CITY/rigs/beta/a checkout, which names rig beta" "the value reads whole, up to the next entry"
hasnt "$OUT" "BEADS_DIR" "the keys after a value with spaces or an empty value still read correctly"
ps_healthy
ps_pane 200 "/usr/local/bin/claude --session-id two" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
http_proxy=http://proxy.example:8080
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
OUT=$(run_ps); RC=$?
eq "$RC" "0" "a variable with a lowercase name still ends the value before it"

# --- 15e. a byte the locale cannot decode does not hide the store keys --------
# ps prints a value's bytes as they are, and BSD sed refuses one it cannot decode
# under a UTF-8 locale, which would read a healthy agent as holding no GC_RIG.
ps_healthy
ps_pane 200 "/usr/local/bin/claude --session-id tw$(printf '\377')o" <<EOF
RAW=a$(printf '\377')b
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
OUT=$(LC_ALL=en_US.UTF-8 run_ps); RC=$?
eq "$RC" "0" "a raw byte in an unrelated value leaves the store keys readable"
has "$OUT" "2 read at the running process" "the process holding the byte was read"

# --- 16. one unread pane among read ones is that session's own note -----------
# macOS hides the environment of its own binaries, so ps prints the command line
# and nothing after it. The first process has just ended, so ps fails on it.
ps_healthy
rm -f "${TMP:?}/ps/200.env"
OUT=$(run_ps); RC=$?
eq "$RC" "0" "a pane whose environment is hidden is a note, not a finding"
has "$OUT" "1 read at the running process" "the count separates sessions judged from panes read"
has "$OUT" "alpha--city__witness: pane process environment unreadable (pane_pid=200, ps -E)" "the note names the session and the reader"
ps_healthy
rm -f "${TMP:?}/ps/100.cmd" "${TMP:?}/ps/100.env"
OUT=$(run_ps); RC=$?
eq "$RC" "0" "a process that has ended is a note, not a finding"
has "$OUT" "city__deacon: pane process environment unreadable (pane_pid=100, ps -E)" "the ended process's session is named"
hasnt "$OUT" "no agent session's running process" "one unread pane does not call the arm blind"
ps_healthy
printf 'zsh\n' > "$TMP/ps/200.cmd"
rm -f "${TMP:?}/ps/200.env"
OUT=$(run_ps); RC=$?
eq "$RC" "0" "a bare command name with its environment hidden is a note, not a finding"
has "$OUT" "alpha--city__witness: pane process environment unreadable" "that session reads as unread"
hasnt "$OUT" "holds no GC_RIG" "the command name is not read as an environment"

# --- 16b. text after the command line that is no environment is unread --------
# A command line can change between the two reads. Judged as an environment, the
# leftover would read as a rig-scoped agent holding no GC_RIG, a false ERROR.
for leftover in 'more words of a longer command line' 'more words and a flag=value' '--flag=value' '2nd=value'; do
    ps_healthy
    printf '%s\n' "$leftover" > "$TMP/ps/200.env"
    OUT=$(run_ps); RC=$?
    eq "$RC" "0" "text after the command line that opens with no entry is not judged: $leftover"
    has "$OUT" "alpha--city__witness: pane process environment unreadable" "that session reads as unread: $leftover"
    hasnt "$OUT" "holds no GC_RIG" "no false finding comes of it: $leftover"
done
ps_healthy
printf '/usr/local/bin/other --pid-reused\n' > "$TMP/ps/200.fullcmd"
OUT=$(run_ps); RC=$?
eq "$RC" "0" "a pid that changed hands between the two reads is not judged"
has "$OUT" "alpha--city__witness: pane process environment unreadable" "that session reads as unread"
ps_healthy
printf 'word\n' > "$TMP/ps/200.env"
OUT=$(run_ps); RC=$?
eq "$RC" "0" "one word with no = after the command line is not judged"
hasnt "$OUT" "holds no GC_RIG" "no false finding comes of the word"

# --- 17. no pane read at all: one warning for the run, never the OK line ------
# With every pane unread the running-process arm has judged nothing, whichever
# reader failed. It says so once, however many sessions there are.
count_of() { local text="$1" n=0; while :; do case "$text" in *"$2"*) n=$((n + 1)); text="${text#*"$2"}" ;; *) break ;; esac; done; printf %s "$n"; }
ps_healthy
rm -f "${TMP:?}/ps/100.env" "${TMP:?}/ps/200.env"
OUT=$(run_ps); RC=$?
eq "$RC" "1" "no environment shown for any pane is a WARNING"
has "$OUT" "no agent session's running process could be read (2 tried, through ps -E)" "the warning says the arm judged nothing, and through what"
has "$OUT" "UNVERIFIED" "the warning says the answer is unknown"
eq "$(count_of "$OUT" "running process could be read")" "1" "the warning is said once for the run"
eq "$(count_of "$OUT" "pane process environment unreadable")" "0" "the per-session notes are not repeated beside it"
hasnt "$OUT" "OK:" "a blind running-process arm cannot reach the OK line"
ps_healthy
rm -rf "${TMP:?}/ps"
OUT=$(run_ps); RC=$?
eq "$RC" "1" "a ps that fails for every pane is a WARNING"
has "$OUT" "no agent session's running process could be read" "the warning is the same whichever way the read failed"
healthy
rm -rf "${TMP:?}/proc/100" "${TMP:?}/proc/200"
OUT=$(run); RC=$?
eq "$RC" "1" "no pane readable under the proc root is a WARNING"
has "$OUT" "no agent session's running process could be read (2 tried, through $TMP/proc)" "the warning names the proc root it read"
eq "$(count_of "$OUT" "pane process environment unreadable")" "0" "the proc reader rolls up the same way"
healthy
printf 'GC_STORE_SCOPE=city\n' > "$TMP/global.env"
rm -rf "${TMP:?}/proc/100" "${TMP:?}/proc/200"
OUT=$(run); RC=$?
eq "$RC" "1" "a blind arm stays a WARNING beside the respawn arm's"
has "$OUT" "no agent session's running process could be read" "the blind arm is still reported"
has "$OUT" "tmux set-environment -gu GC_STORE_SCOPE" "the respawn finding still ran"

# --- 17b. a blind arm does not soften an error another arm found --------------
healthy
rm -rf "${TMP:?}/proc/100" "${TMP:?}/proc/200"
cat > "$TMP/sessions/alpha--city__witness.env" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=beta
EOF
OUT=$(run); RC=$?
eq "$RC" "2" "a wrong session environment is still an ERROR while no pane reads"
has "$OUT" "session environment sets GC_RIG=beta" "the session-env finding is named"
has "$OUT" "no agent session's running process could be read" "the blind arm is reported beside it"

# --- 18. fail-CLOSED: a ps read the budget refuses warns, never passes ---------
# Both reads run under the check budget, so a 124 from either means this process
# was not read. It reports as the budget it is, not as a pane that cannot be read,
# which would let the scan reach the OK line past the misconfigured session.
ps_healthy
ps_pane 200 "/usr/local/bin/claude --session-id two" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=beta
EOF
OUT=$(STUB_PS_SLOW_PID=200 STUB_SLOW_SECS=30 GC_DOCTOR_CHECK_TIMEOUT=8 run_ps); RC=$?
eq "$RC" "1" "a ps read cut by the check budget warns, never passes"
has "$OUT" "hit the check budget before reading alpha--city__witness (rc=124)" "the warning names the budget and the session"
hasnt "$OUT" "OK:" "a budget-truncated ps read cannot reach the OK line"
hasnt "$OUT" "pane process environment unreadable" "a budget cut is not reported as an unreadable pane"
ps_healthy
OUT=$(STUB_PS_SLOW_PID=200 STUB_PS_SLOW_FLAG=-E STUB_SLOW_SECS=30 GC_DOCTOR_CHECK_TIMEOUT=8 run_ps); RC=$?
eq "$RC" "1" "the read of the environment cut by the budget warns too"
has "$OUT" "hit the check budget before reading alpha--city__witness (rc=124)" "the second read names the budget as well"

# --- 18b. a long prompt does not spend the check budget ------------------------
# An agent's arguments carry its whole prompt. Cutting that text off by pattern
# takes bash a time that grows with the square of its length, and the budget then
# runs out before the next session is read.
ps_healthy
LONG_PROMPT=$(printf 'word GC_RIG=beta %.0s' $(seq 1 15000))
ps_pane 100 "/usr/local/bin/claude --append-system-prompt $LONG_PROMPT" <<EOF
GC_AGENT=city.deacon
GC_ALIAS=city.deacon
GC_CITY_PATH=$CITY
EOF
OUT=$(GC_DOCTOR_CHECK_TIMEOUT=25 run_ps); RC=$?
eq "$RC" "0" "a very long command line leaves the budget for the sessions after it"
has "$OUT" "2 read at the running process" "the process with the long command line and the one after it were both read"

# --- 19. the real reader against a real process -------------------------------
# Every case above stands in for the platform. Here the proc root is the default
# and ps is the real one, so each platform runs the read it uses in production:
# /proc on Linux, ps -E on macOS. The process is `timeout` because macOS hides the
# environment of its own binaries, and there this one comes from Homebrew's
# coreutils. It holds its whole environment from env -i, and its argument spells
# out a store key, which only ps prints beside the environment.
REAL_TIMEOUT=$(command -v timeout); REAL_SLEEP=$(command -v sleep)
start_real_process() {
    env -i "$@" "$REAL_TIMEOUT" 60 /bin/sh -c "exec $REAL_SLEEP 60" GC_RIG=spelled-out </dev/null >/dev/null 2>&1 &
    REAL_PID=$!
    local i=0
    while [ "$i" -lt 100 ]; do
        case "$(ps -ww -o command= -p "$REAL_PID" 2>/dev/null)" in "$REAL_TIMEOUT 60 "*) return 0 ;; esac
        sleep 0.1; i=$((i + 1))
    done
    return 1
}
stop_real_process() { kill "$REAL_PID" 2>/dev/null; wait "$REAL_PID" 2>/dev/null; }
run_real() {
    env -u GC_DOCTOR_PROC_ROOT PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" \
        GC_CITY_PATH="$CITY" GC_CITY="" bash "$CHECK" 2>&1
}
real_session() {
    reset_fixture
    session alpha--city__witness "$REAL_PID" <<EOF
GC_AGENT=alpha/city.witness
GC_ALIAS=alpha/city.witness
GC_CITY_PATH=$CITY
GC_RIG=alpha
GC_RIG_ROOT=$CITY/rigs/alpha
BEADS_DIR=$CITY/rigs/alpha/.beads
EOF
}
if start_real_process GC_AGENT=alpha/city.witness GC_ALIAS=alpha/city.witness "GC_CITY_PATH=$CITY" GC_RIG=alpha "GC_RIG_ROOT=$CITY/rigs/alpha" "BEADS_DIR=$CITY/rigs/alpha/.beads"; then
    real_session
    OUT=$(run_real); RC=$?
    eq "$RC" "0" "a real process that agrees with its session passes"
    has "$OUT" "1 read at the running process" "the real process's environment was read"
else
    bad "the real process started (a clean one)"
fi
stop_real_process
if start_real_process GC_AGENT=alpha/city.witness GC_ALIAS=alpha/city.witness "GC_CITY_PATH=$CITY" GC_RIG=beta "GC_RIG_ROOT=$CITY/rigs/beta" "BEADS_DIR=$CITY/rigs/beta/.beads"; then
    real_session
    OUT=$(run_real); RC=$?
    eq "$RC" "2" "a real process holding another rig's store env is an ERROR its session env does not show"
    has "$OUT" "running process holds GC_RIG=beta" "the real process's own value is named"
    hasnt "$OUT" "GC_RIG=spelled-out" "its argument is not read as its environment"
    hasnt "$OUT" "session environment sets" "the correct session environment is not the finding"
else
    bad "the real process started (a leaking one)"
fi
stop_real_process

echo
echo "check-session-store-scope: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
