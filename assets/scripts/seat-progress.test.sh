#!/usr/bin/env bash
# Hermetic test for seat-progress.sh: it files the no-progress finding only for
# the claim of a printing pool seat with no write for three hours since it last
# woke, files nothing for any other bead or on a failed read, and kills and
# routes nothing. Stubbed gc and patrol-finding.sh; no live city, Dolt or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/seat-progress.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-seat-progress-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

unset GC_RIG BEADS_DIR GC_BD_LIB
export GC_CITY_PATH="$TMP/city"
CITY_DB="$GC_CITY_PATH/.beads"
export STUB_CITY_DB="$CITY_DB"
export STUB_GC_LOG="$TMP/gc.log" STUB_FINDING_LOG="$TMP/finding.log"

# A gc that answers the four reads the script makes: the claim from the rig
# store, the session list, the session bead from the city store, and the
# newest-write query in each store. Every call is logged.
BIN="$TMP/bin"; mkdir -p "$BIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-}" = "session" ] && [ "${2:-}" = "list" ]; then
  [ -z "${STUB_SESSIONS_FAIL:-}" ] || { echo "gc: session list unavailable" >&2; exit 1; }
  printf '%s\n' "${STUB_SESSIONS:?}"; exit 0
fi
[ "${1:-}" = "bd" ] || { echo "unexpected gc invocation: $*" >&2; exit 99; }
shift
DB="rig"
if [ "${1:-}" = "--db" ]; then
  [ "${2:-}" = "${STUB_CITY_DB:?}" ] || { echo "unexpected store: ${2:-}" >&2; exit 99; }
  DB="city"; shift 2
fi
case "$DB ${1:-}" in
  "rig show")
    [ -z "${STUB_CLAIM_FAIL:-}" ] || { echo '{"error":"no issues found"}'; exit 1; }
    printf '%s\n' "${STUB_CLAIM:?}" ;;
  "city show")
    [ -z "${STUB_SESSION_BEAD_FAIL:-}" ] || { echo '{"error":"no issues found"}'; exit 1; }
    printf '%s\n' "${STUB_SESSION_BEAD:?}" ;;
  "rig sql")
    [ -z "${STUB_RIG_SQL_FAIL:-}" ] || { echo '{"error":"query error"}'; exit 1; }
    printf '%s\n' "${STUB_RIG_NEWEST:?}" ;;
  "city sql")
    [ -z "${STUB_CITY_SQL_FAIL:-}" ] || { echo '{"error":"query error"}'; exit 1; }
    printf '%s\n' "${STUB_CITY_NEWEST:?}" ;;
  *) echo "unexpected gc bd invocation: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"

# patrol-finding.sh's stand-in: one argument per line, so the test can read
# each flag's value exactly.
FINDING_STUB="$TMP/patrol-finding.sh"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$FINDING_STUB" <<'STUB'
for a in "$@"; do printf '%s\n' "$a"; done >> "${STUB_FINDING_LOG:?}"
[ "${STUB_FINDING_RC:-0}" -eq 0 ] || { echo "patrol-finding: could not file" >&2; exit "$STUB_FINDING_RC"; }
echo "patrol-finding: filed tk-find for the stub"
STUB
chmod +x "$FINDING_STUB"
export GC_PATROL_FINDING_TOOL="$FINDING_STUB"

NOW=$(date +%s)
# The fixture's values are exported once, so each case assigns them plainly.
export STUB_CLAIM STUB_SESSIONS STUB_SESSION_BEAD STUB_RIG_NEWEST STUB_CITY_NEWEST
ago() { jq -rn --argjson s "$(( NOW - $1 ))" '$s | todate'; }
H=3600

# The fixture a case starts from: a polecat's claim, its pane printing, its
# session bead a pool seat that woke five hours ago, its newest write four
# hours old in the rig store and none in the city's.
reset() {
  STUB_CLAIM='[{"id":"tk-claim","status":"in_progress","assignee":"lx-wisp-seat1","metadata":{"gc.session_id":"lx-wisp-seat1"}}]'
  STUB_SESSIONS="{\"sessions\":[{\"id\":\"lx-wisp-seat1\",\"agent_name\":\"gc-toolkit/gc-toolkit.polecat-1\",\"state\":\"active\",\"last_active\":\"$(ago 5)\",\"created_at\":\"$(ago $((6 * H)))\"}]}"
  STUB_SESSION_BEAD="[{\"id\":\"lx-wisp-seat1\",\"metadata\":{\"pool_managed\":\"true\",\"last_woke_at\":\"$(ago $((5 * H)))\"}}]"
  STUB_RIG_NEWEST="[{\"newest\":\"$(ago $((4 * H)))\"}]"
  STUB_CITY_NEWEST='[{"newest":null}]'
  unset STUB_SESSIONS_FAIL STUB_CLAIM_FAIL STUB_SESSION_BEAD_FAIL STUB_RIG_SQL_FAIL STUB_CITY_SQL_FAIL STUB_FINDING_RC
}
run() {
  : > "$STUB_GC_LOG"; : > "$STUB_FINDING_LOG"
  OUT=$("$SCRIPT" "$@" 2>&1); RC=$?
  LOG=$(cat "$STUB_GC_LOG"); FILED=$(cat "$STUB_FINDING_LOG")
}
# The value that follows a flag in the finding's arguments.
arg() { printf '%s\n' "$FILED" | awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }'; }

echo "# a printing pool seat with no write for four hours is reported"
reset
run --bead tk-claim
eq "$RC" 0 "the judgment exits 0"
eq "$(arg --key)" "no-progress.lx-wisp-seat1" "keyed on the session"
eq "$(arg --about)" "tk-claim" "about the claim the seat holds"
eq "$(arg --scope)" "witness-findings" "in the witness's findings"
has "$FILED" "--distinct" "a per-session key passes --distinct, so another finding about the claim cannot refuse it"
has "$(arg --title)" "gc-toolkit/gc-toolkit.polecat-1" "the title names the seat"
has "$(arg --title)" "4 hours" "and how long it has written nothing"
MSG=$(printf '%s\n' "$FILED" | awk 'p { print } $0 == "--message" { p = 1 }')
has "$MSG" "lx-wisp-seat1" "the message names the session"
has "$MSG" "as lx-wisp-seat1 to this rig's store or the city's was at $(ago $((4 * H)))" "and its newest write, by the identity its writes carry"
has "$MSG" "gc session kill lx-wisp-seat1" "and the restart a person can choose"
has "$OUT" "reported lx-wisp-seat1" "the line says it reported the seat"
has "$LOG" "FROM events WHERE actor = 'lx-wisp-seat1'" "the query reads the events table by the claim's assignee"
has "$LOG" "FROM wisp_events WHERE actor = 'lx-wisp-seat1'" "and the wisp_events table"
has "$LOG" "bd --db $CITY_DB sql" "and the city store as well as the rig's"
hasnt "$LOG" "updated_at" "no record's updated_at is read"
hasnt "$LOG" "session kill" "it kills nothing"
hasnt "$LOG" "bd update" "and writes nothing itself"
hasnt "$LOG" "bd create" "and files nothing but through patrol-finding.sh"
hasnt "$FILED" "routed_to" "no route rides the finding"

echo "# a newer write in either store spares the seat"
reset
STUB_CITY_NEWEST="[{\"newest\":\"$(ago 600)\"}]"
run --bead tk-claim
eq "$FILED" "" "a write ten minutes ago in the city store spares it"
has "$OUT" "spared lx-wisp-seat1" "and the line says so"
eq "$RC" 0 "with exit 0"
reset
STUB_RIG_NEWEST="[{\"newest\":\"$(ago $((2 * H)))\"}]"
run --bead tk-claim
eq "$FILED" "" "a write two hours ago in the rig store spares it"
reset
STUB_RIG_NEWEST="[{\"newest\":\"$(ago 600 | sed 's/Z$/.123456Z/')\"}]"
run --bead tk-claim
eq "$FILED" "" "a write carrying fractional seconds is read as a write"
eq "$RC" 0 "and is no unreadable time"

echo "# a quiet pane is the controller's, so the seat is spared"
reset
STUB_SESSIONS="{\"sessions\":[{\"id\":\"lx-wisp-seat1\",\"state\":\"active\",\"last_active\":\"$(ago 300)\",\"created_at\":\"$(ago $((6 * H)))\"}]}"
run --bead tk-claim
eq "$FILED" "" "a pane quiet for five minutes is not filed"
has "$OUT" "the controller paces a quiet pool seat" "the line names who has it"
hasnt "$LOG" "sql" "and no store is queried for its writes"
reset
STUB_SESSIONS="{\"sessions\":[{\"id\":\"lx-wisp-seat1\",\"state\":\"asleep\",\"last_active\":\"\",\"created_at\":\"$(ago $((6 * H)))\"}]}"
run --bead tk-claim
eq "$FILED" "" "a session with no activity time is not filed"

echo "# only a pool seat is judged"
reset
STUB_SESSION_BEAD="[{\"id\":\"lx-wisp-seat1\",\"metadata\":{\"configured_named_session\":\"true\",\"last_woke_at\":\"$(ago $((5 * H)))\"}}]"
run --bead tk-claim
eq "$FILED" "" "a named session is not judged"
has "$OUT" "is not a pool seat" "and the line says why"
hasnt "$LOG" "sql" "and its writes are not read"
reset
STUB_SESSION_BEAD="[{\"id\":\"lx-wisp-seat1\",\"metadata\":{\"session_origin\":\"manual\",\"last_woke_at\":\"$(ago $((5 * H)))\"}}]"
run --bead tk-claim
eq "$FILED" "" "a manual session, such as a converse sitting, is not judged"

echo "# only a claim a session holds now is judged"
reset
STUB_CLAIM='[{"id":"tk-claim","status":"open","assignee":"lx-wisp-seat1","metadata":{"gc.session_id":"lx-wisp-seat1"}}]'
run --bead tk-claim
eq "$FILED" "" "an open bead is no claim"
hasnt "$LOG" "session list" "and the seat is not even read"
eq "$RC" 0 "with exit 0"
reset
STUB_CLAIM='[{"id":"tk-claim","status":"in_progress","assignee":"lx-wisp-seat1","metadata":{}}]'
run --bead tk-claim
eq "$FILED" "" "a bead naming no session is no claim"
has "$OUT" "is no claim a session holds" "and the line says so"
reset
STUB_CLAIM='[{"id":"tk-claim","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.polecat-1","metadata":{"gc.session_id":"lx-wisp-seat1"}}]'
run --bead tk-claim
eq "$FILED" "" "a claim assigned to a name the seat's writes do not carry is not judged"
hasnt "$LOG" "sql" "so no other identity's writes are read for it"
reset
STUB_SESSIONS='{"sessions":[{"id":"lx-wisp-other","state":"active"}]}'
run --bead tk-claim
eq "$FILED" "" "a session that is no longer open is not judged"
eq "$RC" 0 "with exit 0"

echo "# an aliased pool seat is judged on its alias, the identity its writes carry"
ALIASED="{\"sessions\":[{\"id\":\"lx-wisp-seat1\",\"alias\":\"gc-toolkit/gc-toolkit.hicks\",\"agent_name\":\"gc-toolkit/gc-toolkit.hicks\",\"state\":\"active\",\"last_active\":\"$(ago 5)\",\"created_at\":\"$(ago $((6 * H)))\"}]}"
reset
STUB_CLAIM='[{"id":"tk-claim","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.hicks","metadata":{"gc.session_id":"lx-wisp-seat1"}}]'
STUB_SESSIONS="$ALIASED"
run --bead tk-claim
has "$LOG" "actor = 'gc-toolkit/gc-toolkit.hicks'" "the query reads the alias's writes"
eq "$(arg --key)" "no-progress.lx-wisp-seat1" "and the finding is keyed on the session, not the alias"
reset
STUB_SESSIONS="$ALIASED"
run --bead tk-claim
eq "$FILED" "" "an aliased seat's claim assigned to its session id is not judged, since the seat writes as its alias"
hasnt "$LOG" "sql" "so no writes under the session id are read as the seat's"
eq "$RC" 0 "with exit 0"

echo "# the clock starts no earlier than the seat last woke"
reset
STUB_RIG_NEWEST='[{"newest":null}]'
STUB_SESSION_BEAD="[{\"id\":\"lx-wisp-seat1\",\"metadata\":{\"pool_managed\":\"true\",\"last_woke_at\":\"$(ago $H)\"}}]"
run --bead tk-claim
eq "$FILED" "" "a seat that woke an hour ago and has written nothing is spared"
has "$OUT" "since it woke at" "and the line counts from its wake"
reset
STUB_RIG_NEWEST="[{\"newest\":\"$(ago $((6 * H)))\"}]"
STUB_SESSION_BEAD="[{\"id\":\"lx-wisp-seat1\",\"metadata\":{\"pool_managed\":\"true\",\"last_woke_at\":\"$(ago $H)\"}}]"
run --bead tk-claim
eq "$FILED" "" "an older write, such as one a predecessor made under a shared alias, never makes a seat restarted an hour ago look stuck"
reset
STUB_RIG_NEWEST='[{"newest":null}]'
run --bead tk-claim
eq "$(arg --key)" "no-progress.lx-wisp-seat1" "a seat that has written nothing since it woke five hours ago is reported"
has "$(printf '%s\n' "$FILED" | awk 'p { print } $0 == "--message" { p = 1 }')" "has written nothing as lx-wisp-seat1 to this rig's store or the city's since it woke at $(ago $((5 * H)))" "and the message says it has written nothing since its wake"
reset
STUB_RIG_NEWEST='[{"newest":null}]'
STUB_SESSION_BEAD='[{"id":"lx-wisp-seat1","metadata":{"pool_managed":"true"}}]'
STUB_SESSIONS="{\"sessions\":[{\"id\":\"lx-wisp-seat1\",\"state\":\"active\",\"last_active\":\"$(ago 5)\",\"created_at\":\"$(ago $H)\"}]}"
run --bead tk-claim
eq "$FILED" "" "with no wake time on the session bead, the session's start is the floor"

echo "# a read that fails judges nothing, so a failure never files"
reset
export STUB_RIG_SQL_FAIL=1
run --bead tk-claim
eq "$RC" 1 "a failed read of the rig store's writes exits 1"
eq "$FILED" "" "and files nothing"
has "$OUT" "nothing judged" "and the line says so"
reset
export STUB_CITY_SQL_FAIL=1
run --bead tk-claim
eq "$RC" 1 "a failed read of the city store's writes exits 1"
eq "$FILED" "" "and files nothing"
reset
STUB_CITY_NEWEST='{"newest":"2026-01-01T00:00:00Z"}'
run --bead tk-claim
eq "$RC" 1 "a result that is not one row is a failed read"
reset
STUB_RIG_NEWEST='[{"newest":"yesterday"}]'
run --bead tk-claim
eq "$RC" 1 "a time that does not parse is a failed read"
eq "$FILED" "" "and files nothing"
reset
export STUB_SESSIONS_FAIL=1
run --bead tk-claim
eq "$RC" 1 "an unreadable session list exits 1"
eq "$FILED" "" "and files nothing"
reset
STUB_SESSIONS='not json'
run --bead tk-claim
eq "$RC" 1 "a session list that does not parse exits 1"
reset
export STUB_SESSION_BEAD_FAIL=1
run --bead tk-claim
eq "$RC" 1 "an unreadable session bead exits 1"
eq "$FILED" "" "and files nothing"
reset
export STUB_CLAIM_FAIL=1
run --bead tk-claim
eq "$RC" 1 "an unreadable bead exits 1"
reset
( unset GC_CITY_PATH; "$SCRIPT" --bead tk-claim >/dev/null 2>&1 ); eq "$?" 1 "with no city path the city store cannot be read, so it exits 1"

echo "# an identity the query cannot hold is never put into it"
reset
STUB_CLAIM="[{\"id\":\"tk-claim\",\"status\":\"in_progress\",\"assignee\":\"gc-toolkit/x'y\",\"metadata\":{\"gc.session_id\":\"lx-wisp-seat1\"}}]"
STUB_SESSIONS="{\"sessions\":[{\"id\":\"lx-wisp-seat1\",\"alias\":\"gc-toolkit/x'y\",\"state\":\"active\",\"last_active\":\"$(ago 5)\",\"created_at\":\"$(ago $((6 * H)))\"}]}"
run --bead tk-claim
eq "$RC" 1 "an assignee carrying a quote exits 1"
hasnt "$LOG" "sql" "and reaches no query"
eq "$FILED" "" "and files nothing"

echo "# a filing that fails is reported, and the next call judges again"
reset
export STUB_FINDING_RC=1
run --bead tk-claim
eq "$RC" 1 "a failed filing exits 1"
has "$OUT" "patrol-finding.sh filed nothing for lx-wisp-seat1" "and the line says so"

echo "# usage"
reset
run
eq "$RC" 2 "no --bead is a usage error"
run --bead
eq "$RC" 2 "a --bead with no value is a usage error"
run --bead tk-claim --frobnicate
eq "$RC" 2 "an unknown argument is a usage error"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
