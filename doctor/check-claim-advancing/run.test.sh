#!/usr/bin/env bash
# Hermetic test for doctor/check-claim-advancing (I11). Stubs gc/bd only.
# Covers both directions the check has to get right: it fires on a claim whose
# holder cannot be advancing it (orphaned / dead / stalled), and it stays
# SILENT on a session that is genuinely working — including one that has held
# the same step for hours, which is ordinary for a long implementation step.
# Also covers identity matching on all three keys, the claim-age gate that
# keeps a pool recycle quiet, the cache-age degrade, and every fail-closed probe.
# Section 14 covers arm 2 — the step nobody ever claimed — in the same shape:
# it fires only when the routed pool has a running session holding nothing, and
# stays silent for a suspended pool, an empty one, a full one, and a queue that
# `bd ready` is not offering yet.
# Section 15 covers the hold: a step parked on purpose must leave both arms as
# a note recommending `blocked`, because the release hint the check exists to
# give is, for that step, an instruction to hand it back to the pool.
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
# For a value the check derives from elapsed time. Bounds are inclusive, and
# the span is what the fixture's age can drift by while the check runs.
between() { if [ "${1:-x}" -ge "$2" ] 2>/dev/null && [ "$1" -le "$3" ]; then ok "$4"; else bad "$4 (got '$1' want $2..$3)"; fi; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/beta"

# Fixtures are written relative to real time because the check does its date
# arithmetic with jq's `now`. Each age is read when its fixture is written: a
# single suite-start reference drifts by the suite's whole runtime, which is
# longer than the minute the check rounds an age down to, so an age landing on
# a minute boundary would read a minute older than it says.
ago() { date -u -d "$1 seconds ago" +%Y-%m-%dT%H:%M:%SZ; }

cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"},{"name":"beta","path":"$TMP/beta"}]}
EOF

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "session list") rc="${SESSIONS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$SESSIONS_JSON" ;;
  "rig list")     rc="${RIGS_RC:-0}";     [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "agent list")   rc="${AGENTS_RC:-0}";   [ "$rc" -eq 0 ] || exit "$rc"; cat "$AGENTS_JSON" ;;
  *) exit 0 ;;
esac
GC
# The stub applies the same --status, --id and --has-metadata-key filters the
# real bd applies server-side, so a fixture row the real tool would never
# return cannot reach the check here either — including the default that hides
# closed issues unless --all is passed, which is what the hold lookup relies on
# to see a root that has since been retired. The in-progress listing is
# deliberately NOT filtered on gc.step_ref: arm 2 counts a worker holding any
# bead as busy, so the check does that filtering itself and the fixtures prove it.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
db=""; status=""; key=""; ids=""; all=0; prev=""
for a in "$@"; do
  case "$prev" in
    --db) db="$a" ;;
    --status) status="$a" ;;
    --has-metadata-key) key="$a" ;;
    --id) ids="$a" ;;
  esac
  [ "$a" = "--all" ] && all=1
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
# The hold lookup is the only listing that asks by id, so failing it alone
# isolates the degrade from the arm listings that ran fine.
[ -n "$ids" ] && [ "$name" = "${BD_HOLD_FAIL_STORE:-}" ] && exit 3
# `bd ready` answers from a separate fixture: what a store HOLDS and what it
# OFFERS are different questions, and arm 2 turns on the difference.
if [ "$1" = "ready" ]; then
  [ "$name" = "${BD_READY_FAIL_STORE:-}" ] && exit 3
  r="$STORES/$name.ready.json"; [ -f "$r" ] || { printf '[]'; exit 0; }
  cat "$r"; exit 0
fi
f="$STORES/$name.json"; [ -f "$f" ] || { printf '[]'; exit 0; }
jq -c --arg s "$status" --arg k "$key" --arg ids "$ids" --argjson all "$all" '
  ($ids | split(",") | map(select(. != ""))) as $I
  | [ .[] | ((.id // "") | tostring) as $bid
          | select($s == "" or (.status // "") == $s)
          | select($k == "" or (((.metadata // {}) | has($k))))
          | select(($I | length) == 0 or (($I | index($bid)) != null))
          | select($all == 1 or $s != "" or (.status // "") != "closed") ]' "$f"
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

run_check() {
    SESSIONS_JSON="${SESSIONS_JSON:-$TMP/sessions.json}" RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" \
    AGENTS_JSON="${AGENTS_JSON:-$TMP/agents.json}" \
    bash "$CHECK" 2>&1
}
# claim <id> <assignee> <seconds-ago>
claim() { printf '{"id":"%s","status":"in_progress","assignee":"%s","metadata":{"gc.step_ref":"mol-review.pin","gc.claimed_at":"%s"}}' "$1" "$2" "$(ago "$3")"; }
store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.json"; }
clear_stores() { rm -f "$TMP/stores/"*.json; }
# sessions <json-rows...> — cache age 0 unless CACHE is set
sessions() { local IFS=,; printf '{"_cache_age_s":%s,"sessions":[%s]}' "${CACHE:-0}" "$*" > "$TMP/sessions.json"; }
# live <id> <session_name> <alias> <last_active-seconds-ago> [template]
# `template` is the field that ties a session to the agent it runs. A pool
# member's alias is empty, so it is the only join arm 2 can use.
live() { printf '{"id":"%s","session_name":"%s","alias":"%s","state":"active","running":true,"last_active":"%s","template":"%s"}' "$1" "$2" "$3" "$(ago "$4")" "${5:-}"; }
# ready <store> <json-rows...> — what `bd ready` offers from that store
ready() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.ready.json"; }
# openstep <id> <route> <seconds-ago> — open, routed, unassigned, never claimed
openstep() { printf '{"id":"%s","status":"open","assignee":"","updated_at":"%s","metadata":{"gc.step_ref":"mol-review.pin","gc.routed_to":"%s"}}' "$1" "$(ago "$3")" "$2"; }
# unheld <id> <seconds-ago> [extra-metadata-json] — in_progress, no assignee
unheld() { printf '{"id":"%s","status":"in_progress","assignee":"","updated_at":"%s","metadata":{"gc.step_ref":"mol-review.pin"%s}}' "$1" "$(ago "$2")" "${3:+,$3}"; }
# openstep_md <id> <route> <seconds-ago> <extra-metadata-json>
openstep_md() { printf '{"id":"%s","status":"open","assignee":"","updated_at":"%s","metadata":{"gc.step_ref":"mol-review.pin","gc.routed_to":"%s",%s}}' "$1" "$(ago "$3")" "$2" "$4"; }
# root <id> <status> <metadata-json> — the molecule root a step names. Neither
# arm's listing returns it; only the hold lookup, which asks for it by id.
root() { printf '{"id":"%s","status":"%s","assignee":"","metadata":%s}' "$1" "$2" "$3"; }
# agent <qualified_name> <suspended> <pool-max>
agent() { printf '{"qualified_name":"%s","suspended":%s,"pool":{"min":0,"max":%s}}' "$1" "$2" "$3"; }
agents() { local IFS=,; printf '{"agents":[%s]}' "$*" > "$TMP/agents.json"; }
# The default registry every arm-1 case runs against.
agents "$(agent rig/pool.polecat false 2)"

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

# --- 14. arm 2: the step nobody ever claimed ------------------------------
# The acceptance case: a step `bd ready` is offering, routed to a pool that has
# a running session holding nothing, unclaimed past the bound. An idle worker
# and an offered step that have not met is the one shape a backlog cannot
# explain.
agents "$(agent rig/pool.polecat false 2)"
sessions "$(live lx-1 pool-1 "" 30 rig/pool.polecat)"
store alpha "$(openstep a-u1 rig/pool.polecat 7200)"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "an offered step nobody has ever claimed is an ERROR"
has "$OUT" "a-u1" "the error names the step"
has "$OUT" "rig/pool.polecat" "the error names the route"
has "$OUT" "NEVER claimed for 120m" "the error says how long it went unclaimed"
has "$OUT" "1 of 1 running session(s) holding nothing" "the error reports the pool's session state"
has "$OUT" "pool-1" "the error names the free session"
clear_stores

# A step inside the bound is a pour that has not been picked up YET.
store alpha "$(openstep a-u1 rig/pool.polecat 60)"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a freshly poured step inside the bound is silent"
clear_stores

# `bd ready` is the offer. A step the queue is not offering is waiting on its
# predecessor by design — every downstream step of every live molecule is in
# exactly this state, so judging it would report the whole city.
store alpha "$(openstep a-u1 rig/pool.polecat 7200)"
ready alpha '{"id":"a-other"}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open step bd ready is not offering is silent"
hasnt "$OUT" "a-u1" "the blocked step is not named"
clear_stores

# An assignee means something owns it — the continuation group a pool claim
# pre-assigns looks exactly like this.
store alpha "$(printf '{"id":"a-u1","status":"open","assignee":"pool-1","updated_at":"%s","metadata":{"gc.step_ref":"mol-review.pin","gc.routed_to":"rig/pool.polecat"}}' "$(ago 7200)")"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open step that already has an assignee is not never-claimed"
clear_stores

# gc.claimed_at means it HAS been claimed once. A re-offered husk is
# check-step-terminal's REOPENED finding, not this one.
store alpha "$(printf '{"id":"a-u1","status":"open","assignee":"","updated_at":"%s","metadata":{"gc.step_ref":"mol-review.pin","gc.routed_to":"rig/pool.polecat","gc.claimed_at":"%s"}}' "$(ago 7200)" "$(ago 9000)")"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a step that carries gc.claimed_at is not never-claimed"
clear_stores

# --- 14b. the silence properties, one pool state at a time ----------------
store alpha "$(openstep a-u1 rig/pool.polecat 7200)"
ready alpha '{"id":"a-u1"}'

agents "$(agent rig/pool.polecat true 2)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a step routed to a SUSPENDED agent is silent"
has "$OUT" "suspended" "the note says the agent is suspended"

agents "$(agent rig/pool.polecat false 0)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a step routed to an agent with no sessions configured is silent"
has "$OUT" "pool max 0" "the note says nothing is meant to claim it"

# A pool scaled to zero with a queue behind it is the demand probe's business.
agents "$(agent rig/pool.polecat false 2)"
sessions "$(live lx-1 pool-1 "" 30 rig/other.agent)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a step routed to a pool with no running session is silent"
has "$OUT" "no running session" "the note says the pool is empty"

# A route nothing answers is I3's finding, and reporting it here too would
# double-report one defect.
sessions "$(live lx-1 pool-1 "" 30 rig/pool.polecat)"
agents "$(agent rig/other.agent false 2)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a route that names no agent is left to I3"
has "$OUT" "names no agent" "the note says the address is unreachable"
has "$OUT" "I3" "the note hands the finding to the check that owns it"
clear_stores

# --- 14c. a full pool is backpressure, not starvation ---------------------
# The live shape this had to get right: both polecats running, both holding a
# step, two more work beads queued. That is a queue, not a strand.
agents "$(agent rig/pool.polecat false 2)"
sessions "$(live lx-1 pool-1 "" 30 rig/pool.polecat)"
store alpha "$(openstep a-u1 rig/pool.polecat 7200)" "$(claim a-busy pool-1 60)"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a queue behind a pool whose every session is busy is silent"
has "$OUT" "backpressure" "the note says why it is not a fault"
clear_stores

# Occupancy is a city-wide question: a pool worker is busy in whichever store
# its claim happens to live in, which is not the store holding the strand.
store alpha "$(openstep a-u1 rig/pool.polecat 7200)"
ready alpha '{"id":"a-u1"}'
store beta "$(claim b-busy pool-1 60)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a worker busy in another store still counts as busy"
clear_stores

# The codex-polecat shape: alias names the persona, template names the pool,
# and the claim is stamped with the alias.
agents "$(agent rig/pool.codex false 2)"
sessions "$(live lx-1 sess-hicks rig/pool.hicks 30 rig/pool.codex)"
store alpha "$(openstep a-u1 rig/pool.codex 7200)" "$(claim a-busy rig/pool.hicks 60)"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a session busy under its ALIAS is not counted free"
clear_stores
# ...and the same session idle IS the finding, joined by template alone.
store alpha "$(openstep a-u1 rig/pool.codex 7200)"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "the pool is found by template even when no alias matches the route"
has "$OUT" "sess-hicks" "the error names the idle session"
clear_stores

# A singleton agent's work is usually not a formula step, which is why
# occupancy reads every in-progress bead rather than only the ones arm 1 judges.
store alpha "$(openstep a-u1 rig/pool.polecat 7200)" \
  '{"id":"a-anchor","status":"in_progress","assignee":"pool-1","metadata":{}}'
ready alpha '{"id":"a-u1"}'
agents "$(agent rig/pool.polecat false 2)"
sessions "$(live lx-1 pool-1 "" 30 rig/pool.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a session holding a NON-step bead is not counted free"
has "$OUT" "backpressure" "the non-step holder makes the pool read as full"
clear_stores

# A session names itself with whichever identity it has. Naming one is a pipe
# away from rebinding `.` to a string, which aborts the whole pool join and
# silently downgrades every strand to "no running session".
agents "$(agent rig/pool.polecat false 2)"
sessions '{"id":"lx-1","session_name":"","alias":"rig/pool.only-alias","state":"active","running":true,"last_active":"'"$(ago 30)"'","template":"rig/pool.polecat"}'
store alpha "$(openstep a-u1 rig/pool.polecat 7200)"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a session with no session_name still resolves its pool"
has "$OUT" "rig/pool.only-alias" "the error names it by the identity it does have"
has "$OUT" "1 of 1 running session(s) holding nothing" "the pool join survived the empty session_name"
clear_stores

# --- 14d. gc.execution_routed_to is the fallback route --------------------
agents "$(agent rig/pool.polecat false 2)"
sessions "$(live lx-1 pool-1 "" 30 rig/pool.polecat)"
store alpha "$(printf '{"id":"a-u1","status":"open","assignee":"","updated_at":"%s","metadata":{"gc.step_ref":"mol-review.pin","gc.execution_routed_to":"rig/pool.polecat"}}' "$(ago 7200)")"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a step routed only by gc.execution_routed_to is judged"
has "$OUT" "rig/pool.polecat" "the fallback route is the one reported"
clear_stores

# --- 14e. the bound is the same one, and configurable ---------------------
store alpha "$(openstep a-u1 rig/pool.polecat 600)"
ready alpha '{"id":"a-u1"}'
OUT=$(GC_DOCTOR_CLAIM_STALL_MINUTES=5 run_check); RC=$?
eq "$RC" "2" "a 5m bound reports a step offered 10m ago"
OUT=$(GC_DOCTOR_CLAIM_STALL_MINUTES=60 run_check); RC=$?
eq "$RC" "0" "a 60m bound does not"
clear_stores

# --- 14f. arm 2 degrades and fails closed ---------------------------------
store alpha "$(openstep a-u1 rig/pool.polecat 7200)"
ready alpha '{"id":"a-u1"}'

# Liveness comes from the same roster arm 1 uses, so a stale one softens this
# verdict too: those sessions may have exited or taken work since.
CACHE=7200 sessions "$(live lx-1 pool-1 "" 30 rig/pool.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a session cache older than the bound degrades the finding to a warning"
has "$OUT" "a-u1" "the warning still names the step"
has "$OUT" "cache" "the warning says the observation was cache-limited"
unset CACHE
sessions "$(live lx-1 pool-1 "" 30 rig/pool.polecat)"

OUT=$(AGENTS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable agent list WARNS, never passes"
has "$OUT" "never-claimed arm did NOT run" "the warning says the arm was skipped, not clean"
hasnt "$OUT" "a-u1" "no verdict is reached on the step without the registry"

printf 'not json' > "$TMP/agents-bad.json"
OUT=$(AGENTS_JSON="$TMP/agents-bad.json" run_check); RC=$?
eq "$RC" "1" "an unparseable agent list WARNS"

OUT=$(BD_READY_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable \`bd ready\` WARNS and says the store was not checked"
has "$OUT" "NOT checked" "the warning names the unchecked store"
clear_stores
agents "$(agent rig/pool.polecat false 2)"

# --- 15. a step held on purpose leaves both arms ---------------------------
# The shape this exists to stop: the release hint applied to a parked step puts
# it back at `open` while it still carries its pool route, and the pool claims
# it. A hold is a non-empty gc.takeaway or hold_reason.
sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"
agents "$(agent rig/pool.polecat false 2)"

store alpha "$(unheld a-held 7200 '"gc.takeaway":"parked pending a ruling"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a step carrying gc.takeaway is not UNHELD"
has "$OUT" "held on purpose" "the note says the step is parked, not stranded"
has "$OUT" "status=blocked" "the note names the resting state a pool cannot reach"
hasnt "$OUT" "status=open" "the note never recommends the state that hands it to the pool"
hasnt "$OUT" "release it" "the release hint is withheld from a held step"
clear_stores

store alpha "$(unheld a-held 7200 '"hold_reason":"awaiting the sitting"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "hold_reason holds exactly as gc.takeaway does"
has "$OUT" "held on purpose" "the hold_reason note is emitted"
clear_stores

# An EMPTY marker is a hold that was CLEARED, which is the state a released
# step is left in — reading it as a hold would silence the check forever.
store alpha "$(unheld a-held 7200 '"gc.takeaway":""')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an EMPTY gc.takeaway is a cleared hold, not a hold"
has "$OUT" "NO assignee" "the cleared-hold step is still reported UNHELD"
clear_stores

# The live shape: the park was expressed on the ROOT and the step kept only its
# route, so the step read as stranded to a check that looked at it alone.
store alpha "$(unheld a-held 7200 '"gc.root_bead_id":"r-1"')" \
             "$(root r-1 blocked '{"gc.routed_to":"human","gc.takeaway":"held for a ruling"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a step whose ROOT carries the hold is not UNHELD"
has "$OUT" "held on purpose" "the root's hold reaches the step"
hasnt "$OUT" "status=open" "the release hint is withheld on the root's authority"
clear_stores

# A hold outlives the root's close: a husk step under a retired root is the one
# that must not be handed back, so the lookup asks with --all.
store alpha "$(unheld a-held 7200 '"gc.root_bead_id":"r-1"')" \
             "$(root r-1 closed '{"gc.takeaway":"retired under a ruling"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a hold on a CLOSED root still holds"
has "$OUT" "held on purpose" "the closed root is reached by the --all lookup"
clear_stores

# The direction the check was built for is untouched.
store alpha "$(unheld a-strand 7200 '"gc.root_bead_id":"r-1"')" \
             "$(root r-1 open '{}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a step with no hold marker anywhere is still UNHELD"
has "$OUT" "release it (status=open)" "the stranded step still gets the release hint"
hasnt "$OUT" "held on purpose" "a stranded step is not reported as held"
clear_stores

# ORPHANED reaches the same exit: its remedy is the same release.
store alpha "$(printf '{"id":"a-orph","status":"in_progress","assignee":"rig/pool.gone","metadata":{"gc.step_ref":"mol-review.pin","gc.claimed_at":"%s","gc.takeaway":"parked"}}' "$(ago 7200)")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a held step whose assignee names no session is a note, not ORPHANED"
hasnt "$OUT" "names no session" "the orphan error is withheld from a held step"
clear_stores

# --- 15b. arm 2: a held step must not be offered to the pool ---------------
# Worse than arm 1: this step is `open`, routed and offered, so the advice the
# check would otherwise give is what causes the claim.
sessions "$(live lx-1 pool-1 "" 30 rig/pool.polecat)"
store alpha "$(openstep_md a-u1 rig/pool.polecat 7200 '"gc.takeaway":"parked pending a ruling"')"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "an offered step carrying a hold is not the never-claimed ERROR"
has "$OUT" "held on purpose" "the held step is reported as a note"
hasnt "$OUT" "nudge the pool" "the pool is never nudged at a held step"
clear_stores

store alpha "$(openstep_md a-u1 rig/pool.polecat 7200 '"gc.root_bead_id":"r-1"')" \
             "$(root r-1 blocked '{"gc.takeaway":"held for a ruling"}')"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "an offered step whose ROOT is held is not the never-claimed ERROR"
has "$OUT" "held on purpose" "the root's hold reaches arm 2 too"
clear_stores

# ...and an offered step with no hold is still the finding.
store alpha "$(openstep_md a-u1 rig/pool.polecat 7200 '"gc.root_bead_id":"r-1"')" \
             "$(root r-1 open '{}')"
ready alpha '{"id":"a-u1"}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "an offered step with no hold anywhere is still an ERROR"
has "$OUT" "NEVER claimed" "the never-claimed error survives the hold lookup"
clear_stores

# --- 15c. an unreadable root is not a licence to release -------------------
# A hold that cannot be seen must not be released, so the step goes unjudged
# and the run WARNS rather than passing or erroring.
store alpha "$(unheld a-held 7200 '"gc.root_bead_id":"r-1"')"
OUT=$(BD_HOLD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable root lookup WARNS, never errors"
has "$OUT" "NOT judged" "the warning says the step was not judged"
hasnt "$OUT" "status=open" "no release hint is given against an unreadable root"
clear_stores

# A step that names no root at all is judged anyway: there was nothing to read.
store alpha "$(unheld a-strand 7200)"
OUT=$(BD_HOLD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "2" "a step naming no root is still judged when the lookup fails"
has "$OUT" "NO assignee" "the rootless stranded step is still UNHELD"
clear_stores

# Arm 2 degrades the same way, and for the sharper reason: the advice it would
# otherwise give is the claim itself.
sessions "$(live lx-1 pool-1 "" 30 rig/pool.polecat)"
store alpha "$(openstep_md a-u1 rig/pool.polecat 7200 '"gc.root_bead_id":"r-1"')"
ready alpha '{"id":"a-u1"}'
OUT=$(BD_HOLD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable root leaves arm 2 a warning, not the never-claimed error"
has "$OUT" "NOT judged" "the arm 2 warning says the step was not judged"
hasnt "$OUT" "nudge the pool" "the pool is not nudged against an unreadable root"
clear_stores
sessions "$(live lx-1 pool-1 rig/pool.polecat 30)"

# --- 15d. a hold belongs to its own store ----------------------------------
# Bead ids are per-store, so a root that holds in one store says nothing about
# the same id in another; carrying the answer over would silence a real strand.
store alpha "$(unheld a-held 7200 '"gc.root_bead_id":"r-1"')" \
            "$(root r-1 blocked '{"gc.takeaway":"held for a ruling"}')"
store beta  "$(unheld b-strand 7200 '"gc.root_bead_id":"r-1"')" \
            "$(root r-1 open '{}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a hold in one store does not reach the same id in another"
has "$OUT" "beta step b-strand" "the other store's strand is still reported"
has "$OUT" "alpha: 1 step(s) held on purpose" "and the held step is still a note"
clear_stores

# --- 15e. the notes are per store, not per bead ----------------------------
# A held cohort is one decision; a line each would bury the real findings.
store alpha "$(unheld a-h1 7200 '"gc.takeaway":"parked"')" \
            "$(unheld a-h2 9000 '"gc.takeaway":"parked"')" \
            "$(unheld a-h3 3600 '"gc.takeaway":"parked"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a cohort of held steps is silent"
has "$OUT" "3 step(s) held on purpose" "the note counts the cohort"
# The age is floored to the minute and can only grow while the check runs, so
# the oldest fixture is pinned from below rather than to its exact minute.
AGE=$(printf '%s' "$OUT" | sed -n 's/.*held on purpose.*up to \([0-9]*\)m.*/\1/p')
between "$AGE" 150 159 "the note reports the oldest of them"
eq "$(printf '%s' "$OUT" | grep -c 'held on purpose')" "1" "one line for the whole cohort"
clear_stores

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
