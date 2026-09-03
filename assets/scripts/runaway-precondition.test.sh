#!/usr/bin/env bash
# Hermetic test for assets/scripts/runaway-precondition.sh — the deacon
# patrol's runaway-polecat detector. A stubbed `gc` on PATH serves the session
# list, each session's last claim, the beads, and the pool demand answer, so
# every branch of the ladder is driven from fixtures: no live city, no bd, no
# session is ever nudged for real.
#
# Both directions are proved. The detector must stay silent on the resting
# state a healthy city is always in (open anchor, queued demand, a claim held
# under any of the three assignee shapes, a session mid-drain), and it must
# still fire on the precondition itself and escalate nudge -> warrant.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/runaway-precondition.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { if grep -qF -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (missing '$2' in: $1)"; fi; }
hasnt() { if grep -qF -- "$2" <<< "$1"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

# The ambient city must never be an input: every case names its own fixtures.
unset GC_CITY_PATH GC_CITY GC_CITY_ROOT GC_RIG GC_SESSION_ID 2>/dev/null || true

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_LOG:?}"
case "${1:-}" in
  session)
    case "${2:-}" in
      list)  cat "${STUB_SESSIONS:?}"; exit "${STUB_SESSION_LIST_RC:-0}" ;;
      nudge) printf '%s\n' "${3:-}" >> "${STUB_NUDGE_LOG:?}"; exit "${STUB_NUDGE_RC:-0}" ;;
    esac
    exit 0 ;;
  hook)
    if [ "${2:-}" = "current" ]; then
      # `gc hook current` reads the CALLING session from $GC_SESSION_ID.
      id="$(awk -v s="${GC_SESSION_ID:-}" '$1 == s { print $2 }' "${STUB_CLAIMS:?}")"
      [ -n "$id" ] || exit 1
      printf '%s\n' "$id"
      exit 0
    fi
    # Bare `gc hook <agent>`: exit 0 when the pool has an offer, 1 when empty.
    case "$(awk -v t="${2:-}" '$1 == t { print $2 }' "${STUB_DEMAND:?}")" in
      yes)  printf '[{"id":"queued"}]\n'; exit 0 ;;
      fail) exit 3 ;;
      *)    exit 1 ;;
    esac ;;
  bd)
    [ "${2:-}" = "list" ] || exit 0
    shift 2
    id=""; rig=""; want_status=""
    while [ $# -gt 0 ]; do
      case "$1" in
        # Spaced form only, exactly like the wrapper: it picks the store by
        # sniffing a bead id out of the spaced arguments, so `--id=<id>`
        # reaches a store that does not hold the bead and answers [].
        --id)      id="${2:-}"; shift 2 ;;
        --id=*)    id="__unrouted__"; shift ;;
        --rig=*)   rig="${1#--rig=}"; shift ;;
        --status=*) want_status="${1#--status=}"; shift ;;
        *)         shift ;;
      esac
    done
    if [ -n "$id" ]; then
      jq -c --arg id "$id" '[.[] | select(.id == $id)]' "${STUB_BEADS:?}"
    else
      # `index(.status)` would evaluate .status against the SPLIT ARRAY, not
      # the bead, and filter everything out; bind the row first.
      jq -c --arg rig "$rig" --arg st "$want_status" \
        '($st | split(",")) as $ss
         | [.[] | . as $b
                | select(($rig == "" or $b.rig == $rig)
                         and ($st == "" or ($ss | index($b.status) != null)))]' \
        "${STUB_BEADS:?}"
    fi
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"

export STUB_LOG="$TMP/gc.log" STUB_NUDGE_LOG="$TMP/nudge.log"
export STUB_SESSIONS="$TMP/sessions.json" STUB_BEADS="$TMP/beads.json"
export STUB_CLAIMS="$TMP/claims.txt" STUB_DEMAND="$TMP/demand.txt"
export STUB_NUDGE_RC=0 STUB_SESSION_LIST_RC=0
export RUNAWAY_CALL_TIMEOUT=0

NOW="$(date -u +%s)"
ts() { date -u -d "@$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ; }   # <seconds ago>

reset() {
  : > "$STUB_LOG"; : > "$STUB_NUDGE_LOG"
  export RUNAWAY_STATE_DIR="$TMP/state"
  rm -rf "$RUNAWAY_STATE_DIR"
  unset RUNAWAY_GRACE_S RUNAWAY_NUDGE_WAIT_S RUNAWAY_IDLE_S RUNAWAY_ROLE_MATCH
  export STUB_NUDGE_RC=0
}

# One active gc-toolkit polecat seat, moving, plus a witness that must never be
# classified. Callers override the claim, the bead and the demand per case.
base_sessions() {
  cat > "$STUB_SESSIONS" <<JSON
{"sessions":[
 {"id":"lx-pole1","alias":null,"session_name":"gc-toolkit--gc-toolkit__polecat-1-pool",
  "template":"gc-toolkit/gc-toolkit.polecat","state":"active","rig":"gc-toolkit",
  "last_active":"$(ts 5)"},
 {"id":"lx-wit","alias":"gc-toolkit/gc-toolkit.witness","session_name":"gc-toolkit--gc-toolkit__witness",
  "template":"gc-toolkit/gc-toolkit.witness","state":"active","rig":"gc-toolkit",
  "last_active":"$(ts 5)"}
]}
JSON
}
claim()  { printf '%s %s\n' "$1" "$2" > "$STUB_CLAIMS"; }
demand() { printf '%s %s\n' "$1" "$2" > "$STUB_DEMAND"; }
bead()   { # <id> <status> <closed-seconds-ago|-> [assignee] [rig]
  local closed="null"
  [ "$3" = "-" ] || closed="\"$(ts "$3")\""
  cat > "$STUB_BEADS" <<JSON
[{"id":"$1","status":"$2","closed_at":$closed,"updated_at":"$(ts 30)",
  "assignee":$( [ -n "${4:-}" ] && printf '"%s"' "$4" || printf 'null' ),
  "rig":"${5:-gc-toolkit}"}]
JSON
}

line_for() { grep -F "session=$1 " <<< "$2"; }
field()    { sed -n "s/.*[[:space:]]$2=\([^[:space:]]*\).*/\1/p" <<< "$1"; }

echo "== resting states: the detector stays silent =="

reset; base_sessions; claim lx-pole1 tk-work; bead tk-work in_progress -
demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" verdict)" "clean" "open anchor is clean"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "anchor-open" "  ... and says why"
eq "$(grep -c . "$STUB_NUDGE_LOG")" "0" "  ... nothing nudged"
hasnt "$OUT" "session=lx-wit " "a non-polecat session is not classified"
has "$OUT" "sessions=1 flag=0 warrant=0 unknown=0 state_dir=ok" "summary counts the pass"

reset; base_sessions; claim lx-pole1 tk-work; bead tk-work closed 60
demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" verdict)" "grace" "a claim closed inside the grace window is a clean exit"
eq "$(grep -c . "$STUB_NUDGE_LOG")" "0" "  ... and is never nudged"

reset; base_sessions; claim lx-pole1 tk-work; bead tk-work closed 7200
demand gc-toolkit/gc-toolkit.polecat yes
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" verdict)" "clean" "queued demand is work it will claim"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "queued-demand" "  ... and says why"
eq "$(grep -c . "$STUB_NUDGE_LOG")" "0" "  ... nothing nudged"

# The assignee-shape footgun: a filter written for one shape reads FALSE CLEAN
# against the others, so all three must hold the session back.
for shape in lx-pole1 gc-toolkit--gc-toolkit__polecat-1-pool; do
  reset; base_sessions; claim lx-pole1 tk-work
  cat > "$STUB_BEADS" <<JSON
[{"id":"tk-work","status":"closed","closed_at":"$(ts 7200)","updated_at":"$(ts 7200)","assignee":null,"rig":"gc-toolkit"},
 {"id":"tk-held","status":"in_progress","closed_at":null,"updated_at":"$(ts 30)","assignee":"$shape","rig":"gc-toolkit"}]
JSON
  demand gc-toolkit/gc-toolkit.polecat no
  OUT="$("$SUT")"
  eq "$(field "$(line_for lx-pole1 "$OUT")" verdict)" "clean" "a claim held as '$shape' is not idle"
  eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "holds-tk-held" "  ... naming the bead it holds"
done

# The alias shape, on a named polecat rather than a pool seat.
reset
cat > "$STUB_SESSIONS" <<JSON
{"sessions":[{"id":"lx-cdx","alias":"gc-toolkit/gc-toolkit.ripley",
  "session_name":"gc-toolkit--gc-toolkit__ripley","template":"gc-toolkit/gc-toolkit.polecat-codex",
  "state":"active","rig":"gc-toolkit","last_active":"$(ts 5)"}]}
JSON
claim lx-cdx tk-verdict
cat > "$STUB_BEADS" <<JSON
[{"id":"tk-verdict","status":"closed","closed_at":"$(ts 7200)","updated_at":"$(ts 7200)","assignee":null,"rig":"gc-toolkit"},
 {"id":"tk-rev","status":"in_progress","closed_at":null,"updated_at":"$(ts 30)","assignee":"gc-toolkit/gc-toolkit.ripley","rig":"gc-toolkit"}]
JSON
demand gc-toolkit/gc-toolkit.polecat-codex no
OUT="$("$SUT")"
eq "$(field "$(line_for lx-cdx "$OUT")" reason)" "holds-tk-rev" "a claim held under the alias shape is not idle"

reset; base_sessions
sed -i "s|\"last_active\":\"$(ts 5)\"|\"last_active\":\"$(ts 4000)\"|" "$STUB_SESSIONS"
claim lx-pole1 tk-work; bead tk-work closed 7200
demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" verdict)" "clean" "a session that stopped moving belongs to the stale scans"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "not-moving" "  ... and says so"
eq "$(grep -c . "$STUB_NUDGE_LOG")" "0" "  ... and is never nudged"

reset; base_sessions; : > "$STUB_CLAIMS"; bead tk-work closed 7200
demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "no-claim-yet" "a seat that has claimed nothing is outside this rule"

reset
cat > "$STUB_SESSIONS" <<JSON
{"sessions":[{"id":"lx-gone","alias":null,"session_name":"gc-toolkit--gc-toolkit__polecat-1-pool",
  "template":"gc-toolkit/gc-toolkit.polecat","state":"asleep","rig":"gc-toolkit","last_active":"$(ts 5)"}]}
JSON
claim lx-gone tk-work; bead tk-work closed 7200; demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT")"
hasnt "$OUT" "session=lx-gone " "a session that is not active is not classified"

echo "== the precondition: nudge, then warrant =="

reset; base_sessions; claim lx-pole1 tk-work; bead tk-work closed 7200
demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT")"
L="$(line_for lx-pole1 "$OUT")"
eq "$(field "$L" verdict)" "flag" "closed claim + no demand + no held work is the precondition"
eq "$(field "$L" reason)" "nudged" "  ... and the first sighting nudges"
eq "$(field "$L" nudges)" "1" "  ... recording one nudge"
eq "$(field "$L" demand)" "no" "  ... carrying the demand answer"
eq "$(cat "$STUB_NUDGE_LOG")" "lx-pole1" "  ... to that session"
has "$OUT" "flag=1 warrant=0" "  ... and the summary counts it"
has "$(grep 'session nudge' "$STUB_LOG")" "gc runtime drain-ack" "  ... telling it what to do"

# Same state again, inside the nudge wait: no second nudge, no warrant yet.
: > "$STUB_NUDGE_LOG"
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "nudged-recently" "a second pass inside the wait does not re-nudge"
eq "$(grep -c . "$STUB_NUDGE_LOG")" "0" "  ... and sends nothing"
has "$OUT" "flag=1 warrant=0" "  ... and is not yet a warrant"

# Past the wait, still in the state: this is the pass that reports a warrant.
OUT="$(RUNAWAY_NUDGE_WAIT_S=0 "$SUT")"
L="$(line_for lx-pole1 "$OUT")"
eq "$(field "$L" verdict)" "warrant" "still flagged after the wait is warrantable"
eq "$(field "$L" reason)" "still-flagged-after-nudge" "  ... and says why"
has "$OUT" "flag=0 warrant=1" "  ... and the summary counts it"
hasnt "$(cat "$STUB_LOG")" "bd create" "  ... but the script never files the warrant itself"

# A session that recovers drops its record, so the ladder restarts from zero.
bead tk-work in_progress -
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" verdict)" "clean" "a recovered session reads clean"
bead tk-work closed 7200
: > "$STUB_NUDGE_LOG"
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "nudged" "  ... and its next finding starts at the nudge again"
eq "$(cat "$STUB_NUDGE_LOG")" "lx-pole1" "  ... with a fresh nudge"

echo "== a nudge that did not go out is not counted as one =="

reset; base_sessions; claim lx-pole1 tk-work; bead tk-work closed 7200
demand gc-toolkit/gc-toolkit.polecat no
OUT="$(STUB_NUDGE_RC=1 "$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "nudge-failed" "a failed nudge is reported as one"
eq "$(field "$(line_for lx-pole1 "$OUT")" nudges)" "0" "  ... and is not counted"
# ... so even past the wait, the next pass retries the nudge instead of
# counting down to a warrant nobody was warned about.
: > "$STUB_NUDGE_LOG"
OUT="$(RUNAWAY_NUDGE_WAIT_S=0 "$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "nudged" "  ... and the next pass retries it"
eq "$(cat "$STUB_NUDGE_LOG")" "lx-pole1" "  ... sending the nudge that never went"

echo "== unproven is never clean and never a warrant =="

reset; base_sessions; claim lx-pole1 tk-missing; printf '[]' > "$STUB_BEADS"
demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT")"
L="$(line_for lx-pole1 "$OUT")"
eq "$(field "$L" verdict)" "unknown" "an anchor that cannot be read is unknown"
eq "$(field "$L" reason)" "anchor-unreadable" "  ... and says why"
eq "$(grep -c . "$STUB_NUDGE_LOG")" "0" "  ... and is never nudged"
has "$OUT" "unknown=1" "  ... and the summary counts it"

reset; base_sessions; claim lx-pole1 tk-work; bead tk-work closed 7200
demand gc-toolkit/gc-toolkit.polecat fail
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "demand-unreadable" "an unreadable demand probe is unknown, not empty"
eq "$(grep -c . "$STUB_NUDGE_LOG")" "0" "  ... and is never nudged"

# A session with no rig names no store, so the held-work scan cannot run and
# the session cannot be proved idle. City-scoped sessions carry no rig field.
reset
cat > "$STUB_SESSIONS" <<JSON
{"sessions":[{"id":"lx-norig","alias":null,"session_name":"gc-toolkit__polecat-x",
  "template":"gc-toolkit.polecat","state":"active","rig":null,"last_active":"$(ts 5)"}]}
JSON
claim lx-norig tk-work; bead tk-work closed 7200; demand gc-toolkit.polecat no
OUT="$("$SUT")"
eq "$(field "$(line_for lx-norig "$OUT")" verdict)" "unknown" "a session with no rig cannot be proved idle"
eq "$(field "$(line_for lx-norig "$OUT")" reason)" "no-rig" "  ... and says why"
eq "$(grep -c . "$STUB_NUDGE_LOG")" "0" "  ... and is never nudged"

reset; base_sessions
sed -i "s|\"last_active\":\"$(ts 5)\"|\"last_active\":\"not-a-date\"|" "$STUB_SESSIONS"
claim lx-pole1 tk-work; bead tk-work closed 7200; demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" reason)" "unreadable-last-active" "an undateable session is unknown"

# The runtime stamps last_active from its own clock: a stamp from after the
# pass started is a session that just moved, not an unreadable one.
reset; base_sessions
sed -i "s|\"last_active\":\"$(ts 5)\"|\"last_active\":\"$(date -u -d "@$((NOW + 120))" +%Y-%m-%dT%H:%M:%SZ)\"|" "$STUB_SESSIONS"
claim lx-pole1 tk-work; bead tk-work closed 7200; demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" idle_s)" "0" "a last_active ahead of the clock reads as just-moved"
eq "$(field "$(line_for lx-pole1 "$OUT")" verdict)" "flag" "  ... and still reaches the precondition"

echo "== the anchor is read from the session's own rig =="

reset
cat > "$STUB_SESSIONS" <<JSON
{"sessions":[{"id":"lx-gas","alias":null,"session_name":"gascity--gc-toolkit__polecat-1-pool",
  "template":"gascity/gc-toolkit.polecat","state":"active","rig":"gascity","last_active":"$(ts 5)"}]}
JSON
claim lx-gas gc-anchor; bead gc-anchor closed 7200 "" gascity
demand gascity/gc-toolkit.polecat no
OUT="$("$SUT")"
eq "$(field "$(line_for lx-gas "$OUT")" verdict)" "flag" "a foreign-rig anchor resolves"
has "$(cat "$STUB_LOG")" "bd list --id gc-anchor" "  ... because --id is passed spaced, so the wrapper routes the store"
has "$(cat "$STUB_LOG")" "bd list --rig=gascity" "  ... and the held-work scan names the session's rig"

echo "== --dry-run reports without acting =="

reset; base_sessions; claim lx-pole1 tk-work; bead tk-work closed 7200
demand gc-toolkit/gc-toolkit.polecat no
OUT="$("$SUT" --dry-run)"
L="$(line_for lx-pole1 "$OUT")"
eq "$(field "$L" verdict)" "flag" "--dry-run still classifies the precondition"
eq "$(field "$L" reason)" "dry-run" "  ... marking that it did not act"
eq "$(grep -c . "$STUB_NUDGE_LOG")" "0" "  ... nudging nothing"
eq "$(ls -A "$RUNAWAY_STATE_DIR" | wc -l | tr -d ' ')" "0" "  ... and writing no state"

echo "== state dir: degraded, not silent =="

reset; base_sessions; claim lx-pole1 tk-work; bead tk-work closed 7200
demand gc-toolkit/gc-toolkit.polecat no
mkdir -p "$TMP/ro"; chmod 500 "$TMP/ro"
OUT="$(RUNAWAY_STATE_DIR="$TMP/ro/state" "$SUT")"
has "$OUT" "state_dir=unavailable" "an unwritable state dir is reported"
eq "$(field "$(line_for lx-pole1 "$OUT")" verdict)" "flag" "  ... and the finding still reports"
OUT="$(RUNAWAY_STATE_DIR="$TMP/ro/state" RUNAWAY_NUDGE_WAIT_S=0 "$SUT")"
eq "$(field "$(line_for lx-pole1 "$OUT")" verdict)" "flag" "  ... but with no memory it never escalates to a warrant"
chmod 700 "$TMP/ro"

echo "== state files: pruned when the session is gone, foreign files untouched =="

reset; base_sessions; claim lx-pole1 tk-work; bead tk-work closed 7200
demand gc-toolkit/gc-toolkit.polecat no
"$SUT" >/dev/null
eq "$( [ -f "$RUNAWAY_STATE_DIR/lx-pole1" ] && echo yes || echo no)" "yes" "a finding leaves a record"
printf 'not ours\n' > "$RUNAWAY_STATE_DIR/lx-someone-else"
cat > "$STUB_SESSIONS" <<JSON
{"sessions":[{"id":"lx-pole2","alias":null,"session_name":"gc-toolkit--gc-toolkit__polecat-2-pool",
  "template":"gc-toolkit/gc-toolkit.polecat","state":"active","rig":"gc-toolkit","last_active":"$(ts 5)"}]}
JSON
claim lx-pole2 tk-work; bead tk-work in_progress -
"$SUT" >/dev/null
eq "$( [ -f "$RUNAWAY_STATE_DIR/lx-pole1" ] && echo yes || echo no)" "no" "the record of a session that is gone is pruned"
eq "$( [ -f "$RUNAWAY_STATE_DIR/lx-someone-else" ] && echo yes || echo no)" "yes" "a file this script did not write is left alone"

echo "== the patrol actually runs it =="

# A detection rule with no caller is the gap this script was written to close:
# the deacon's context resets every cycle, so the only durable home for the
# rule is the formula that the next cycle reads.
TOML="$HERE/../../formulas/mol-deacon-patrol.toml"
if [ ! -s "$TOML" ]; then
  bad "missing $TOML"
else
  PATROL="$(cat "$TOML")"
  has "$PATROL" 'runaway-precondition.sh' "the deacon patrol runs the detector"
  has "$PATROL" 'verdict=warrant' "  ... and reads the verdict that owes a warrant"
  has "$PATROL" 'gc.routed_to":"{{binding_prefix}}dog"' "  ... whose disposal is the dog pool, not a kill"
fi

echo "== usage =="
"$SUT" --nonsense >/dev/null 2>&1; eq "$?" "2" "an unknown argument is a usage error"
"$SUT" --help >/dev/null 2>&1; eq "$?" "0" "--help is not"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
