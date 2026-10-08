#!/usr/bin/env bash
# Hermetic test for pool-slot-reap.sh.
#
# pool-slot-reap closes an asleep pool session bead that holds a pool slot with
# no runtime and no work once it has stayed asleep past the grace window: core
# frees a slot only for a fixed list of sleep reasons, so a session stopped by
# `gc session kill` (sleep_reason=killed) keeps its slot until its bead closes.
#
# Runs the REAL pool-slot-reap.sh with a stubbed `gc` (POOL_SLOT_REAP_GC) and a
# stubbed incident ledger (POOL_SLOT_REAP_LEDGER): no live city, sessions, or
# store. The stub answers `session list`, `rig list` and `config show` from
# fixture files, `bd show <id>` from a per-bead fixture (a `.second.json`
# fixture answers every read after the first, and a closed marker answers with
# the bead closed), and `bd list --db <store>` from a per-store fixture of rows
# filtered to the asked statuses, `[]` when there is none (a `.second.json`
# fixture answers the store's second read on). It records every
# `session close`, every work query and every config read; the ledger stub
# records each append.
# Covered:
#   (KILLED)    a killed pool session asleep past the grace window is closed and
#               recorded as one cleanup entry in the city ledger
#   (IDLE/DRIFT/DRAINED) a freeable or drain reason core left in place past the
#               window is closed the same way
#   (SETTLING)  a session asleep inside the grace window is kept
#   (FENCE)     a fresh kill-pending fence is inside the window and is kept
#   (WAKE)      an old sleep with a fresh wake request is kept
#   (HOLDS)     user-hold, wait-hold, quarantine, context-churn, rate_limit
#               sleeps and held_until / quarantined_until / wait_hold markers are
#               kept, and so is a pinned session
#   (NAMED/MANUAL/NOTPOOL) a configured named session, a session whose origin is
#               named (pool-managed or not), a manual session, and a session that
#               is not pool-managed are never closed
#   (AWAKE)     a persisted-awake bead the listing reads asleep is kept
#   (UNAGED)    a bead with no readable slept_at is kept
#   (WORK)      work open or in_progress under the id, session_name, alias, or a
#               prior alias, in any store, keeps the bead; a row with no assignee
#               matches no session
#   (STATUSES)  hooked work keeps the bead; blocked, deferred and pinned work
#               does not
#   (SLOTNAME)  work under the numbered slot name alone does not keep it
#   (SLOTALIAS) a slotted bead of an ordinary numbered pool (no namepool, a cap
#               other than 1 with no cap and a cap of 0 among them, a dir-less
#               template too) is closed when only its alias or a prior alias
#               holds work, and those are never searched; its id and
#               session_name still keep it
#   (STABLE)    a namepool member's alias (an overflow slot name included), a
#               canonical singleton's alias, the alias of a template matching
#               agents of both kinds or no agent, and the alias of an unslotted
#               bead all keep the bead
#   (CFGFAIL)   an agent config that cannot be read (garbled, not ok, no agent
#               table) or that fails core's validation leaves every alias an
#               owner and the pass running
#   (CFGCITY)   the config is read from the roster's city
#   (SESSIONROW) a session bead under the id is not work
#   (QUERY)     the work search reads each store once per search, for every row
#               in open, in_progress or hooked, brief, with --include-infra
#               --include-ephemeral --limit 0 and no assignee
#   (STOREFAIL) an unreadable store, or a work answer that is not rows, skips
#               the bead, never closes it
#   (CHANGED)   a second read that differs from the first keeps the bead
#   (SECONDSEARCH) work that appears in a store between the two searches keeps
#               the bead
#   (SCRUB)     a raw control byte inside a string in the session list, the
#               roster, the agent config, a bead read or a store answer is
#               scrubbed, not read as a failure
#   (ROWS)      active and closed rows are never candidates
#   (SHOWFAIL/NOTSESSION) an unreadable bead or a non-session bead is skipped
#   (CLOSEFAIL) a failed close is read again: one that left the bead open is
#               reported, not recorded, and left for the next pass; one whose
#               bead reads closed is counted and recorded
#   (CLOSETIMEOUT) a close cut off by its bound after the bead closed is counted
#               and recorded; one cut off before is left for the next pass, and
#               one that ignores SIGTERM is killed after the grace
#   (LEDGERFAIL) a close the ledger could not record exits 1 and names it
#   (DRYRUN)    --dry-run names the plan, closes nothing, records nothing
#   (LISTFAIL/ROSTERFAIL) an unreadable session list or rig roster exits 1 and
#               closes nothing
#   (NOCAND)    with no asleep row the pass exits 0 without reading the roster
#   (BUDGET)    candidates past the pass budget are deferred, not closed; no read
#               starts past the budget, but a close whose reads finished is never
#               cut off
#   (TIMEOUT)   the order's timeout sits above the budget plus one read and the
#               close tail
#   (KNOB)      a malformed knob is a usage error
#   (DISKPRESSURE) a failed temp-file enumeration exits 1 and closes nothing
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# POOL_SLOT_REAP_SUT overrides the script under test, so a case can be replayed
# against a mutated copy to confirm it discriminates.
SUT="${POOL_SLOT_REAP_SUT:-$HERE/pool-slot-reap.sh}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pool-slot-reap-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()  { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SUT" ] && ok "pool-slot-reap.sh present" || { bad "pool-slot-reap.sh missing at $SUT"; exit 1; }
command -v jq >/dev/null 2>&1 || { bad "jq required for this test"; exit 1; }

mkdir -p "$TMP/bin" "$TMP/beads" "$TMP/work" "$TMP/clock"
export SESSIONS_FILE="$TMP/sessions.json" ROSTER_FILE="$TMP/roster.json" CONFIG_FILE="$TMP/config.json"
export BEADS_DIR="$TMP/beads" WORK_DIR="$TMP/work" CLOCK_FILE="$TMP/clock/now"
export CALLS="$TMP/calls" QUERIES="$TMP/queries" LEDGER_CALLS="$TMP/ledger" CONFIG_CALLS="$TMP/config-calls"
export POOL_SLOT_REAP_GC="$TMP/bin/gc" POOL_SLOT_REAP_LEDGER="$TMP/bin/ledger"

# --- the test's clock -----------------------------------------------------------
# A run with $TMP/clock first on PATH reads `date -u +%s` from CLOCK_FILE, so a
# stub can move the pass's clock forward instead of sleeping. Every other date
# call, and every run without the file, is the real date.
REAL_DATE="$(command -v date)"
cat > "$TMP/clock/date" <<CLOCK
#!/usr/bin/env bash
if [ "\$*" = "-u +%s" ] && [ -f "\${CLOCK_FILE:-}" ]; then cat "\$CLOCK_FILE"; else exec "$REAL_DATE" "\$@"; fi
CLOCK
chmod +x "$TMP/clock/date"

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
all="$*"
advance() { echo $(( $(cat "$CLOCK_FILE") + $1 )) > "$CLOCK_FILE"; }
case "$1 ${2:-}" in
  "session list")
    if [ -n "${LIST_BROKEN:-}" ]; then echo "gc: not json here"; exit 0; fi
    cat "$SESSIONS_FILE" ;;
  "rig list")
    printf 'rig list\n' >> "$CALLS"
    if [ -n "${ROSTER_BROKEN:-}" ]; then echo "gc: not json here"; exit 0; fi
    cat "$ROSTER_FILE" ;;
  "config show")
    printf '%s\n' "$all" >> "$CONFIG_CALLS"
    case "${CONFIG_BROKEN:-}" in
      garbled)  echo "gc: not json here"; exit 0 ;;
      notok)    jq -n '{ok: false, error: {code: "city_resolve_failed"}}'; exit 1 ;;
      noagents) jq -n '{ok: true, config: {}, validation: {ok: true}}'; exit 0 ;;
      invalid)  jq '.validation = {ok: false, errors: ["agent \"x\": invalid"]}' "$CONFIG_FILE"; exit 0 ;;
    esac
    cat "$CONFIG_FILE" ;;
  "bd show")
    id="$3"
    n="$(cat "$BEADS_DIR/$id.reads" 2>/dev/null || echo 0)"; n=$((n + 1))
    echo "$n" > "$BEADS_DIR/$id.reads"
    if [ "${SHOW_BROKEN:-}" = "$id" ]; then echo "gc bd: garbled >>>"; exit 0; fi
    if [ -f "$BEADS_DIR/$id.closed" ]; then jq '.[0].status = "closed"' "$BEADS_DIR/$id.json"; exit 0; fi
    if [ "$n" -ge 2 ] && [ -f "$BEADS_DIR/$id.second.json" ]; then cat "$BEADS_DIR/$id.second.json"; exit 0; fi
    if [ -f "$BEADS_DIR/$id.json" ]; then cat "$BEADS_DIR/$id.json"
    else jq -n '{error:"no issues found matching the provided IDs"}'; exit 1; fi ;;
  "bd list")
    shift 2; db=""; st=""
    while [ $# -gt 0 ]; do
      case "$1" in --db) db="$2"; shift ;; --status) st="$2"; shift ;; esac
      shift
    done
    printf '%s\n' "$all" >> "$QUERIES"
    case " ${STORE_BROKEN:-} " in *" $db "*) echo "gc bd: store unavailable"; exit 1 ;; esac
    key="$(printf '%s' "$db" | tr '/' '_')"
    n="$(cat "$WORK_DIR/$key.reads" 2>/dev/null || echo 0)"; n=$((n + 1))
    echo "$n" > "$WORK_DIR/$key.reads"
    # A slow store moves the clock on every read, or on its SLOW_READth read only.
    case " ${STORE_SLOW:-} " in
      *" $db "*) if [ -z "${SLOW_READ:-}" ] || [ "$n" = "$SLOW_READ" ]; then advance "$SLOW_S"; fi ;;
    esac
    f="$WORK_DIR/$key.json"
    if [ "$n" -ge 2 ] && [ -f "$WORK_DIR/$key.second.json" ]; then f="$WORK_DIR/$key.second.json"; fi
    [ -f "$f" ] || { echo '[]'; exit 0; }
    # A store answers only the rows in the asked statuses, as bd does. A fixture
    # that is not an array of rows stands for a malformed answer and is served raw.
    if jq -e 'type == "array" and all(.[]; type == "object")' "$f" >/dev/null 2>&1; then
      jq -c --arg st "$st" '[.[] | select(.status as $s | any($st | split(",") | .[]; . == $s))]' "$f"
    else
      cat "$f"
    fi ;;
  "session close")
    sid="$3"
    case " ${CLOSE_FAILS:-} " in *" $sid "*) exit 1 ;; esac
    case " ${CLOSE_FAILS_AFTER_COMMIT:-} " in *" $sid "*) touch "$BEADS_DIR/$sid.closed"; exit 1 ;; esac
    case " ${CLOSE_HANGS:-} " in *" $sid "*) exec sleep 30 ;; esac
    case " ${CLOSE_IGNORES_TERM:-} " in *" $sid "*) trap '' TERM; exec sleep 30 ;; esac
    printf 'close %s\n' "$sid" >> "$CALLS"
    case " ${CLOSE_COMMITS_THEN_HANGS:-} " in *" $sid "*) touch "$BEADS_DIR/$sid.closed"; exec sleep 30 ;; esac
    case " ${CLOSE_SLOW:-} " in *" $sid "*) advance "$SLOW_S" ;; esac
    exit 0 ;;
  *) echo "fake gc: unhandled: $*" >&2; exit 3 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# --- ledger stub --------------------------------------------------------------
cat > "$TMP/bin/ledger" <<'LEDGER'
#!/usr/bin/env bash
[ -n "${LEDGER_FAILS:-}" ] && exit 1
printf '%s|%s\n' "${GC_CITY_PATH:-}" "$*" >> "$LEDGER_CALLS"
LEDGER
chmod +x "$TMP/bin/ledger"

NOW="$(date -u +%s)"
at() { jq -nr --argjson t "$1" '$t | todate'; }  # epoch -> RFC3339 UTC
OLD="$(at $((NOW - 7200)))"      # asleep two hours: past the 900s window
OLDER="$(at $((NOW - 9000)))"
FRESH="$(at $((NOW - 60)))"      # asleep one minute: inside the window
TAB="$(printf '\t')"

# A pool session bead. Metadata defaults to a killed polecat in slot <n>; extra
# keys in the second argument override or add to it.
pool_bead() { # <id> [metadata-overrides-json] [issue_type] [status]
  jq -n --arg id "$1" --argjson o "${2:-{\}}" --arg t "${3:-session}" --arg s "${4:-open}" \
     --arg old "$OLD" '
    [{id: $id, issue_type: $t, status: $s,
      metadata: ({session_origin: "ephemeral", pool_managed: "true", state: "asleep",
                  sleep_reason: "killed", slept_at: $old,
                  session_name: ("rig__polecat-" + $id), agent_name: "rig/pack.polecat-2",
                  template: "rig/pack.polecat"} + $o)}]' > "$BEADS_DIR/$1.json"
}
second_read() { # <id> <metadata-overrides-json>: what every read after the first sees
  jq --argjson o "$2" '.[0].metadata += $o' "$BEADS_DIR/$1.json" > "$BEADS_DIR/$1.second.json"
}
store_file() { printf '%s/%s.json' "$WORK_DIR" "$(printf '%s' "$1" | tr '/' '_')"; }
work() { # <store> <assignee> <bead-id> [issue_type] [status]: a row in the store's answer
  local f; f="$(store_file "$1")"
  [ -f "$f" ] || echo '[]' > "$f"
  jq --arg who "$2" --arg id "$3" --arg t "${4:-task}" --arg s "${5:-in_progress}" \
     '. + [{id: $id, issue_type: $t, status: $s, assignee: $who}]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
unassigned_work() { # <store> <bead-id>: a row with an empty assignee and one with none
  local f; f="$(store_file "$1")"
  [ -f "$f" ] || echo '[]' > "$f"
  jq --arg id "$2" '. + [{id: ($id + "-empty"), issue_type: "task", status: "open", assignee: ""},
                         {id: ($id + "-none"), issue_type: "task", status: "open"}]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
work_later() { # <store> <assignee> <bead-id>: a row the store answers from its second read on
  local f s; f="$(store_file "$1")"; s="${f%.json}.second.json"
  [ -f "$s" ] || { if [ -f "$f" ]; then cp "$f" "$s"; else echo '[]' > "$s"; fi; }
  jq --arg who "$2" --arg id "$3" '. + [{id: $id, issue_type: "task", status: "in_progress", assignee: $who}]' \
     "$s" > "$s.tmp" && mv "$s.tmp" "$s"
}
with_raw_tab() { # <file>: put a raw TAB inside the first "title" string
  sed "s/TABHERE/a${TAB}b/" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
sessions() { # <id:state:closed>...
  local spec first=1
  { printf '{"sessions":['
    for spec in "$@"; do
      [ "$first" -eq 1 ] || printf ','; first=0
      IFS=: read -r id st cl <<< "$spec"
      printf '{"id":"%s","state":"%s","closed":%s,"template":"rig/pack.polecat"}' "$id" "$st" "$cl"
    done
    printf ']}'; } > "$SESSIONS_FILE"
}
reset_world() {
  : > "$CALLS"; : > "$QUERIES"; : > "$LEDGER_CALLS"; : > "$CONFIG_CALLS"
  rm -f "$BEADS_DIR"/* "$WORK_DIR"/*
  jq -n '{city_path: "/city", rigs: [{name: "city", path: "/city", hq: true},
                                     {name: "a", path: "/city/rigs/a"},
                                     {name: "b", path: "/city/rigs/b"}]}' > "$ROSTER_FILE"
  # The configured agents, in `gc config show --json`'s shape: polecat,
  # unbounded (no cap), zero (cap 0) and the city-scoped dog are ordinary
  # numbered pools, as core reads them; crew and crew-list are namepools (by
  # file, by list); solo is a canonical singleton; twin is the same dir and name
  # under two bindings, one of each kind.
  jq -n '{ok: true, validation: {ok: true, warnings: [], errors: []}, config: {Agents: [
    {Dir: "rig", Name: "polecat",   Namepool: "", NamepoolNames: null, MaxActiveSessions: 4},
    {Dir: "rig", Name: "unbounded", Namepool: "", NamepoolNames: null, MaxActiveSessions: null},
    {Dir: "rig", Name: "zero",      Namepool: "", NamepoolNames: null, MaxActiveSessions: 0},
    {Name: "dog",                   Namepool: "", NamepoolNames: null, MaxActiveSessions: 2},
    {Dir: "rig", Name: "crew",      Namepool: "/pack/namepool.txt", NamepoolNames: null, MaxActiveSessions: 4},
    {Dir: "rig", Name: "crew-list", Namepool: "", NamepoolNames: ["max"], MaxActiveSessions: 4},
    {Dir: "rig", Name: "solo",      Namepool: "", NamepoolNames: null, MaxActiveSessions: 1},
    {Dir: "rig", Name: "twin",      Namepool: "", NamepoolNames: null, MaxActiveSessions: 3},
    {Dir: "rig", Name: "twin",      Namepool: "/pack/namepool.txt", NamepoolNames: ["ripley"], MaxActiveSessions: 3}
  ]}}' > "$CONFIG_FILE"
}
run() { OUT="$(bash "$SUT" "$@" 2>"$TMP/stderr")"; RC=$?; ERR="$(cat "$TMP/stderr")"; CLOSED="$(cat "$CALLS")"; }

# --- the main pass ------------------------------------------------------------
reset_world
pool_bead s-killed
pool_bead s-idle      '{"sleep_reason":"idle"}'
pool_bead s-drift     '{"sleep_reason":"config-drift"}'
pool_bead s-drained   '{"state":"drained","sleep_reason":"drained"}'
pool_bead s-settling  "{\"slept_at\":\"$FRESH\"}"
pool_bead s-fence     "{\"slept_at\":\"$FRESH\",\"state_reason\":\"kill-pending\"}"
pool_bead s-wake      "{\"wake_request\":\"explicit\",\"wake_requested_at\":\"$FRESH\"}"
pool_bead s-oldwake   "{\"slept_at\":\"$OLDER\",\"wake_request\":\"explicit\",\"wake_requested_at\":\"$OLD\"}"
pool_bead s-userhold  '{"sleep_reason":"user-hold"}'
pool_bead s-waithold  '{"sleep_reason":"wait-hold"}'
pool_bead s-quar      '{"sleep_reason":"quarantine"}'
pool_bead s-churn     '{"sleep_reason":"context-churn"}'
pool_bead s-rate      '{"sleep_reason":"rate_limit"}'
pool_bead s-helduntil "{\"held_until\":\"$FRESH\"}"
pool_bead s-quntil    "{\"quarantined_until\":\"$FRESH\"}"
pool_bead s-waitmark  '{"wait_hold":"w-1"}'
pool_bead s-pinned    '{"pin_awake":"true"}'
pool_bead s-named     '{"configured_named_session":"true","configured_named_identity":"rig/pack.refinery"}'
pool_bead s-origin-named '{"session_origin":"named","pool_slot":"1"}'
pool_bead s-manual    '{"session_origin":"manual","pool_managed":""}'
pool_bead s-notpool   '{"session_origin":"","pool_managed":""}'
pool_bead s-awake     '{"state":"awake","sleep_reason":""}'
pool_bead s-unaged    '{"slept_at":""}'
pool_bead s-work-id
pool_bead s-work-name
pool_bead s-work-alias '{"alias":"rig/pack.polecat"}'
pool_bead s-work-hist  '{"alias_history":"old/one,rig/old-alias"}'
pool_bead s-hookwork
pool_bead s-pinwork
pool_bead s-blockwork
pool_bead s-deferwork
pool_bead s-slotname
pool_bead s-sessrow
pool_bead s-changed
second_read s-changed "{\"wake_request\":\"explicit\",\"wake_requested_at\":\"$FRESH\"}"
pool_bead s-moved
second_read s-moved "{\"slept_at\":\"$OLDER\"}"
pool_bead s-task '{}' task
pool_bead s-garbled
work /city/rigs/a/.beads s-work-id                 tk-held-1
work /city/.beads        rig__polecat-s-work-name   lx-held-2
work /city/rigs/b/.beads rig/pack.polecat           gc-held-3
work /city/rigs/a/.beads rig/old-alias              tk-held-4
work /city/rigs/b/.beads s-hookwork                 gc-hooked hooked  hooked
work /city/rigs/a/.beads rig__polecat-s-pinwork     tk-pinned task    pinned
work /city/rigs/a/.beads s-blockwork                tk-blocked task   blocked
work /city/.beads        s-deferwork                lx-deferred task  deferred
work /city/rigs/a/.beads rig/pack.polecat-2         tk-slot-only
unassigned_work /city/.beads        tk-unowned
unassigned_work /city/rigs/b/.beads gc-unowned
work /city/.beads        s-sessrow                  lx-wisp-self session

ALL_ASLEEP=(s-killed s-idle s-drift s-drained s-settling s-fence s-wake s-oldwake
  s-userhold s-waithold s-quar s-churn s-rate s-helduntil s-quntil s-waitmark s-pinned
  s-named s-origin-named s-manual s-notpool s-awake s-unaged s-work-id s-work-name
  s-work-alias s-work-hist s-hookwork s-pinwork s-blockwork s-deferwork s-slotname
  s-sessrow s-changed s-moved s-task s-garbled s-gone)
specs=()
for id in "${ALL_ASLEEP[@]}"; do specs+=("$id:asleep:false"); done
sessions "${specs[@]}" s-active:active:false s-closedrow:asleep:true
pool_bead s-active
pool_bead s-closedrow

SHOW_BROKEN=s-garbled run
eq "$RC" "0" "a normal pass exits 0"

for id in s-killed s-idle s-drift s-drained s-oldwake s-pinwork s-blockwork s-deferwork s-slotname \
          s-sessrow; do
  has "$CLOSED" "close $id" "$id is closed"
done
for id in s-settling s-fence s-wake s-userhold s-waithold s-quar s-churn s-rate s-helduntil \
          s-quntil s-waitmark s-pinned s-named s-origin-named s-manual s-notpool s-awake s-unaged \
          s-work-id s-work-name s-work-alias s-work-hist s-hookwork s-changed s-moved \
          s-task s-garbled s-gone s-active s-closedrow; do
  hasnt "$CLOSED"$'\n' "close $id"$'\n' "$id is not closed"
done
eq "$(grep -c '^close ' "$CALLS")" "10" "exactly the ten ghosts are closed"

LEDGER_OUT="$(cat "$LEDGER_CALLS")"
eq "$(grep -c . "$LEDGER_CALLS")" "10" "every close is one ledger entry"
has "$LEDGER_OUT" "/city|append cleanup pool-slot-reap closed s-killed rig/pack.polecat-2 (sleep_reason=killed, asleep since $OLD): no runtime, no assigned work bead:s-killed" \
  "the ledger entry is a cleanup in the city store naming the bead, its slot, why it slept, and the bead ref"
has "$LEDGER_OUT" "closed s-idle rig/pack.polecat-2 (sleep_reason=idle" "an idle ghost's entry names its reason"

has "$OUT" "closed 10, kept 25, skipped 3, deferred 0 of the asleep sessions" "the summary counts closed / kept / skipped / deferred"
has "$OUT" "  s-killed rig/pack.polecat-2 (sleep_reason=killed, asleep since $OLD): no runtime, no assigned work" "the summary lists each close"
has "$OUT" "s-settling rig/pack.polecat-2 kept: settling" "a session inside the window is reported as settling"
has "$OUT" "s-userhold rig/pack.polecat-2 kept: held (user-hold)" "a held session is reported as held"
has "$OUT" "s-helduntil rig/pack.polecat-2 kept: held (hold marker set)" "a hold marker is reported as held"
has "$OUT" "s-pinned rig/pack.polecat-2 kept: pinned awake" "a pinned session is reported as pinned"
has "$OUT" "s-named rig/pack.polecat-2 kept: named session" "a named session is reported as named"
has "$OUT" "s-origin-named rig/pack.polecat-2 kept: named session" \
  "a session whose origin is named is kept as named, though it reads pool-managed and slotted"
has "$OUT" "s-manual rig/pack.polecat-2 kept: manual session" "a manual session is reported as manual"
has "$OUT" "s-notpool rig/pack.polecat-2 kept: not pool-managed" "a non-pool session is reported as not pool-managed"
has "$OUT" "s-awake rig/pack.polecat-2 kept: persisted state awake" "a persisted-awake bead is reported by its state"
has "$OUT" "s-unaged rig/pack.polecat-2 kept: unaged" "a bead with no slept_at is reported unaged"
has "$OUT" "s-work-id rig/pack.polecat-2 kept: work tk-held-1 is assigned to it" "work under the id is named"
has "$OUT" "s-work-name rig/pack.polecat-2 kept: work lx-held-2 is assigned to it" "work under the session_name is named"
has "$OUT" "s-work-alias rig/pack.polecat-2 kept: work gc-held-3 is assigned to it" "work under the alias is named"
has "$OUT" "s-work-hist rig/pack.polecat-2 kept: work tk-held-4 is assigned to it" "work under a prior alias is named"
has "$OUT" "s-hookwork rig/pack.polecat-2 kept: work gc-hooked is assigned to it" "hooked work keeps the bead"
hasnt "$OUT" "s-pinwork rig/pack.polecat-2 kept" "pinned work does not keep the bead"
has "$OUT" "s-changed rig/pack.polecat-2 kept: its lifecycle changed during the pass" "a wake landing between the reads keeps the bead"
has "$OUT" "s-moved rig/pack.polecat-2 kept: its lifecycle changed during the pass" "a changed fingerprint keeps the bead even when both reads are eligible"
has "$OUT" "s-task rig/pack.polecat-2 skipped: not a session bead" "a non-session bead is skipped"
has "$OUT" "s-garbled - skipped" "an unreadable bead read is skipped"
has "$OUT" "s-gone - skipped" "a bead that no longer resolves is skipped"
hasnt "$OUT" "s-active" "an active row is never a candidate"
hasnt "$OUT" "s-closedrow" "a closed row is never a candidate"

# (QUERY) the work search: one read per store, every live-work row, no assignee.
Q="$(cat "$QUERIES")"
for store in /city/.beads /city/rigs/a/.beads /city/rigs/b/.beads; do
  has "$Q" "--db $store " "the work search asks $store"
done
has "$(head -1 "$QUERIES")" "--status open,in_progress,hooked --brief --limit 0 --include-infra --include-ephemeral --json" \
  "the work query reads open, in_progress and hooked rows, brief, every row, ephemeral included"
hasnt "$Q" "--assignee" "the work query names no assignee; the identities are matched on the rows"

# (CFGCITY) the agent config is read once, from the city the roster names.
eq "$(grep -c . "$CONFIG_CALLS")" "1" "the agent config is read once per pass"
has "$(cat "$CONFIG_CALLS")" "config show --json --city /city" "the agent config is read from the roster's city"
hasnt "$ERR" "could not read a valid agent config" "a readable, valid config raises no warning"

# (QUERY) one eligible candidate costs one read per store for each of its two
# searches, however many identities it has.
reset_world
pool_bead s-a '{"alias":"rig/pack.polecat","alias_history":"old/one,old/two"}'
sessions s-a:asleep:false
run
has "$CLOSED" "close s-a" "a candidate with six identities and no work is closed"
eq "$(grep -c '^bd list ' "$QUERIES")" "6" "its two work searches read each of the three stores once each"

# --- (SLOTALIAS / STABLE) which aliases name the session ------------------------
# Every bead here is asleep past the window with work under its alias or a prior
# alias only, except s-slot-id and s-slot-name, whose work is under their id and
# session_name. Whether that alias is searched turns on the pool its configured
# agent runs, not on its shape: s-slot-alias, s-solo, s-np-over and s-twin all
# carry <template>-<slot>.
reset_world
pool_bead s-slot-alias '{"pool_slot":"2","alias":"rig/pack.polecat-2"}'
pool_bead s-slot-hist  '{"pool_slot":"3","agent_name":"rig/pack.polecat-3","alias":"","alias_history":"rig/pack.polecat-1,rig/pack.polecat-3"}'
pool_bead s-citydog    '{"pool_slot":"1","template":"pack.dog","agent_name":"pack.dog-1","alias":"pack.dog-1"}'
pool_bead s-slot-id    '{"pool_slot":"5","agent_name":"rig/pack.polecat-5","alias":"rig/pack.polecat-5"}'
pool_bead s-slot-name  '{"pool_slot":"6","agent_name":"rig/pack.polecat-6","alias":"rig/pack.polecat-6"}'
pool_bead s-unbounded  '{"pool_slot":"2","template":"rig/pack.unbounded","agent_name":"rig/pack.unbounded-2","alias":"rig/pack.unbounded-2"}'
pool_bead s-zero       '{"pool_slot":"2","template":"rig/pack.zero","agent_name":"rig/pack.zero-2","alias":"rig/pack.zero-2"}'
pool_bead s-np-alias   '{"pool_slot":"1","template":"rig/pack.crew","agent_name":"rig/pack.furiosa","alias":"rig/pack.furiosa"}'
pool_bead s-np-over    '{"pool_slot":"3","template":"rig/pack.crew","agent_name":"rig/pack.crew-3","alias":"rig/pack.crew-3"}'
pool_bead s-np-list    '{"pool_slot":"2","template":"rig/pack.crew-list","agent_name":"rig/pack.crew-list-2","alias":"rig/pack.crew-list-2"}'
pool_bead s-solo       '{"pool_slot":"1","template":"rig/pack.solo","agent_name":"rig/pack.solo-1","alias":"rig/pack.solo-1"}'
pool_bead s-twin       '{"pool_slot":"2","template":"rig/pack.twin","agent_name":"rig/pack.twin-2","alias":"rig/pack.twin-2"}'
pool_bead s-unknown    '{"pool_slot":"2","template":"rig/pack.gone","agent_name":"rig/pack.gone-2","alias":"rig/pack.gone-2"}'
pool_bead s-noslot     '{"agent_name":"rig/pack.polecat-4","alias":"rig/pack.polecat-4"}'
work /city/rigs/a/.beads rig/pack.polecat-2    tk-slot-alias
work /city/rigs/b/.beads rig/pack.polecat-1    tk-slot-hist
work /city/.beads        pack.dog-1            tk-citydog
work /city/rigs/a/.beads s-slot-id             tk-held-id
work /city/rigs/b/.beads rig__polecat-s-slot-name tk-held-name
work /city/.beads        rig/pack.unbounded-2  tk-unbounded
work /city/rigs/b/.beads rig/pack.zero-2       tk-zero
work /city/rigs/a/.beads rig/pack.furiosa      tk-np-alias
work /city/rigs/b/.beads rig/pack.crew-3       tk-np-over
work /city/.beads        rig/pack.crew-list-2  tk-np-list
work /city/rigs/a/.beads rig/pack.solo-1       tk-solo
work /city/rigs/a/.beads rig/pack.twin-2       tk-twin
work /city/rigs/b/.beads rig/pack.gone-2       tk-unknown
work /city/rigs/a/.beads rig/pack.polecat-4    tk-noslot
SLOT_CASES=(s-slot-alias s-slot-hist s-citydog s-slot-id s-slot-name s-unbounded s-zero
  s-np-alias s-np-over s-np-list s-solo s-twin s-unknown s-noslot)
specs=()
for id in "${SLOT_CASES[@]}"; do specs+=("$id:asleep:false"); done
sessions "${specs[@]}"
run
eq "$RC" "0" "the alias pass exits 0"
for id in s-slot-alias s-slot-hist s-citydog s-unbounded s-zero; do
  has "$CLOSED" "close $id" "$id, whose only work is under its slot alias, is closed"
done
for id in s-slot-id s-slot-name s-np-alias s-np-over s-np-list s-solo s-twin s-unknown s-noslot; do
  hasnt "$CLOSED"$'\n' "close $id"$'\n' "$id is not closed"
done
eq "$(grep -c '^close ' "$CALLS")" "5" "exactly the five numbered-pool beads are closed"
has "$OUT" "closed 5, kept 9, skipped 0, deferred 0" "the alias pass counts five closed and nine kept"
has "$OUT" "s-slot-id rig/pack.polecat-5 kept: work tk-held-id is assigned to it" "a numbered-pool bead's id still keeps it"
has "$OUT" "s-slot-name rig/pack.polecat-6 kept: work tk-held-name is assigned to it" "a numbered-pool bead's session_name still keeps it"
has "$OUT" "s-np-alias rig/pack.furiosa kept: work tk-np-alias is assigned to it" "a namepool name keeps its bead"
has "$OUT" "s-np-over rig/pack.crew-3 kept: work tk-np-over is assigned to it" "a namepool overflow slot name keeps its bead"
has "$OUT" "s-np-list rig/pack.crew-list-2 kept: work tk-np-list is assigned to it" "a namepool given as a name list keeps its bead"
has "$OUT" "s-solo rig/pack.solo-1 kept: work tk-solo is assigned to it" "a canonical singleton's alias keeps its bead"
has "$OUT" "s-twin rig/pack.twin-2 kept: work tk-twin is assigned to it" "a template matching agents of both kinds keeps its alias"
has "$OUT" "s-unknown rig/pack.gone-2 kept: work tk-unknown is assigned to it" "a template matching no agent keeps its alias"
has "$OUT" "s-noslot rig/pack.polecat-4 kept: work tk-noslot is assigned to it" "an unslotted bead's alias keeps it"

# --- (CFGFAIL) an unreadable agent config leaves every alias an owner -----------
for mode in garbled notok noagents invalid; do
  reset_world
  pool_bead s-slot-alias '{"pool_slot":"2","alias":"rig/pack.polecat-2"}'
  pool_bead s-clean
  work /city/rigs/a/.beads rig/pack.polecat-2 tk-slot-alias
  sessions s-slot-alias:asleep:false s-clean:asleep:false
  CONFIG_BROKEN=$mode run
  eq "$RC" "0" "a $mode config does not fail the pass"
  has "$OUT" "s-slot-alias rig/pack.polecat-2 kept: work tk-slot-alias is assigned to it" \
    "with a $mode config the slot alias is still searched as an owner"
  has "$CLOSED" "close s-clean" "with a $mode config a bead with no work under any identity still closes"
  has "$ERR" "could not read a valid agent config" "a $mode config is named on stderr"
done

# --- (STOREFAIL) an unreadable store skips the bead -----------------------------
reset_world
pool_bead s-killed
sessions s-killed:asleep:false
STORE_BROKEN=/city/rigs/b/.beads run
eq "$RC" "0" "an unreadable store does not fail the pass"
eq "$CLOSED" "rig list" "an unreadable store closes nothing"
has "$OUT" "s-killed rig/pack.polecat-2 skipped: assigned work could not be read" "the skip names the unreadable work read"
eq "$(cat "$LEDGER_CALLS")" "" "nothing is recorded when nothing closes"

# A work answer that is an array but not of rows cannot be read as empty either.
reset_world
pool_bead s-killed
sessions s-killed:asleep:false
printf '["not a row"]' > "$(store_file /city/.beads)"
run
eq "$CLOSED" "rig list" "a work answer that is not rows closes nothing"
has "$OUT" "s-killed rig/pack.polecat-2 skipped: assigned work could not be read" "a malformed work answer is a skip"

# --- (SECONDSEARCH) work assigned between the two searches keeps the bead -------
reset_world
pool_bead s-killed
sessions s-killed:asleep:false
work_later /city/rigs/b/.beads s-killed tk-late
run
eq "$CLOSED" "rig list" "work that appears after the first search closes nothing"
has "$OUT" "s-killed rig/pack.polecat-2 kept: work tk-late is assigned to it on the second search" \
  "the second search names the work it found"

# --- (SCRUB) a raw control byte inside a string is scrubbed, not a failure -------
reset_world
pool_bead s-a; pool_bead s-b
sessions s-a:asleep:false s-b:asleep:false
jq '.sessions[0].title = "TABHERE"' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
jq '.rigs[0].title = "TABHERE"' "$ROSTER_FILE" > "$ROSTER_FILE.tmp" && mv "$ROSTER_FILE.tmp" "$ROSTER_FILE"
jq '.config.Agents[0].Title = "TABHERE"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
jq '.[0].title = "TABHERE"' "$BEADS_DIR/s-a.json" > "$BEADS_DIR/s-a.tmp" && mv "$BEADS_DIR/s-a.tmp" "$BEADS_DIR/s-a.json"
work /city/rigs/a/.beads s-b tk-held-b
jq '.[0].title = "TABHERE"' "$(store_file /city/rigs/a/.beads)" > "$TMP/store.tmp" && mv "$TMP/store.tmp" "$(store_file /city/rigs/a/.beads)"
for f in "$SESSIONS_FILE" "$ROSTER_FILE" "$CONFIG_FILE" "$BEADS_DIR/s-a.json" "$(store_file /city/rigs/a/.beads)"; do
  with_raw_tab "$f"
done
if jq . "$SESSIONS_FILE" >/dev/null 2>&1; then bad "the scrub fixture carries a raw TAB jq rejects"; else ok "the scrub fixture carries a raw TAB jq rejects"; fi
run
eq "$RC" "0" "a raw TAB in the session list, roster and config does not fail the pass"
hasnt "$ERR" "could not read a valid agent config" "a raw TAB in the agent config is scrubbed"
has "$CLOSED" "close s-a" "a raw TAB in the bead read is scrubbed and the ghost closes"
has "$OUT" "s-b rig/pack.polecat-2 kept: work tk-held-b is assigned to it" "a raw TAB in a store answer is scrubbed and its work still keeps the bead"

# --- (CLOSEFAIL) ----------------------------------------------------------------
reset_world
pool_bead s-a; pool_bead s-b; pool_bead s-c
sessions s-a:asleep:false s-b:asleep:false s-c:asleep:false
CLOSE_FAILS=s-a CLOSE_FAILS_AFTER_COMMIT=s-c run
eq "$RC" "0" "a failed close does not fail the pass"
has "$CLOSED" "close s-b" "the other ghost still closes"
has "$ERR" "could not close s-a" "the failed close is reported on stderr"
has "$OUT" "s-a rig/pack.polecat-2 skipped: gc session close failed (exit 1)" "the failed close is counted skipped"
hasnt "$(cat "$LEDGER_CALLS")" "bead:s-a" "a failed close that left the bead open is never recorded as closed"
eq "$(cat "$BEADS_DIR/s-a.reads")" "3" "a failed close is settled by one more read"
has "$(cat "$LEDGER_CALLS")" "pool-slot-reap closed s-c rig/pack.polecat-2 (sleep_reason=killed, asleep since $OLD): no runtime, no assigned work; the close call exited 1 after the bead closed bead:s-c" \
  "a failed close whose bead reads closed is recorded, and says how its call ended"
has "$OUT" "closed 2, kept 0, skipped 1" "a failed close whose bead reads closed counts closed"

# --- (CLOSETIMEOUT) a close cut off by its bound --------------------------------
if command -v timeout >/dev/null 2>&1; then
  reset_world
  pool_bead s-a; pool_bead s-b
  sessions s-a:asleep:false s-b:asleep:false
  POOL_SLOT_REAP_CALL_TIMEOUT_S=2 CLOSE_COMMITS_THEN_HANGS=s-a CLOSE_HANGS=s-b run
  eq "$RC" "0" "a timed-out close does not fail the pass"
  has "$OUT" "closed 1, kept 0, skipped 1" "the close that committed counts closed and the one that did not counts skipped"
  has "$(cat "$LEDGER_CALLS")" "pool-slot-reap closed s-a rig/pack.polecat-2 (sleep_reason=killed, asleep since $OLD): no runtime, no assigned work; the close call timed out after the bead closed bead:s-a" \
    "a close cut off after the bead closed is recorded, and says its call timed out"
  hasnt "$(cat "$LEDGER_CALLS")" "bead:s-b" "a close cut off before the bead closed is not recorded"
  has "$OUT" "s-b rig/pack.polecat-2 skipped: gc session close failed (exit 124); left for the next pass" \
    "a close cut off before the bead closed is left for the next pass"
  eq "$(cat "$BEADS_DIR/s-b.reads")" "3" "a timed-out close is settled by one more read"

  # A close that ignores SIGTERM is killed after the grace, not waited on.
  if timeout -k 1 1 true >/dev/null 2>&1; then
    reset_world
    pool_bead s-c
    sessions s-c:asleep:false
    POOL_SLOT_REAP_CALL_TIMEOUT_S=2 CLOSE_IGNORES_TERM=s-c run
    has "$OUT" "s-c rig/pack.polecat-2 skipped: gc session close failed (exit 137); left for the next pass" \
      "a close that ignores SIGTERM is killed after the grace and left for the next pass"
  else
    echo "skip - SIGKILL grace case (this timeout(1) takes no -k)"
  fi
else
  echo "skip - close timeout cases (no timeout(1) on this host)"
fi

# --- (LEDGERFAIL) ---------------------------------------------------------------
reset_world
pool_bead s-a
sessions s-a:asleep:false
LEDGER_FAILS=1 run
eq "$RC" "1" "a close the ledger could not record exits 1"
has "$CLOSED" "close s-a" "the close itself still happens"
has "$ERR" "closed s-a but could not record it in the incident ledger" "stderr names the unrecorded close"

# --- (DRYRUN) -------------------------------------------------------------------
reset_world
pool_bead s-a; pool_bead s-b '{"sleep_reason":"user-hold"}'
sessions s-a:asleep:false s-b:asleep:false
run --dry-run
eq "$RC" "0" "a dry run exits 0"
eq "$CLOSED" "rig list" "a dry run closes nothing"
eq "$(cat "$LEDGER_CALLS")" "" "a dry run records nothing"
has "$OUT" "would close 1, kept 1" "a dry run counts the plan"
has "$OUT" "  s-a rig/pack.polecat-2 (sleep_reason=killed" "a dry run names what it would close"

# --- (LISTFAIL / ROSTERFAIL) ----------------------------------------------------
reset_world
pool_bead s-a; sessions s-a:asleep:false
LIST_BROKEN=1 run
eq "$RC" "1" "an unreadable session list exits 1"
eq "$CLOSED" "" "an unreadable session list closes nothing"
has "$ERR" "could not read the session list" "the listing failure is named"

reset_world
pool_bead s-a; sessions s-a:asleep:false
ROSTER_BROKEN=1 run
eq "$RC" "1" "an unreadable rig roster exits 1"
eq "$CLOSED" "rig list" "an unreadable rig roster closes nothing"
has "$ERR" "could not read the rig roster" "the roster failure is named"

# --- (NOCAND) -------------------------------------------------------------------
reset_world
pool_bead s-a; sessions s-a:active:false
run
eq "$RC" "0" "a pass with no asleep row exits 0"
eq "$CLOSED" "" "with no asleep row the roster is never read and nothing closes"
has "$OUT" "closed 0, kept 0, skipped 0, deferred 0" "the empty pass prints a zero summary"

# --- (BUDGET) -------------------------------------------------------------------
reset_world
pool_bead s-a; pool_bead s-b
sessions s-a:asleep:false s-b:asleep:false
POOL_SLOT_REAP_BUDGET_S=0 run
eq "$RC" "0" "a spent budget exits 0"
eq "$CLOSED" "rig list" "candidates past the budget are not closed"
has "$OUT" "deferred 2" "candidates past the budget are deferred"
has "$OUT" "s-a - deferred: the pass budget" "a deferred candidate says why"

# No read starts past the budget: a store read that outlasts it defers the
# candidate before the next store is asked. The stub moves the clock.
reset_world
pool_bead s-a
sessions s-a:asleep:false
date -u +%s > "$CLOCK_FILE"
PATH="$TMP/clock:$PATH" SLOW_S=100 STORE_SLOW=/city/rigs/a/.beads POOL_SLOT_REAP_BUDGET_S=50 run
rm -f "$CLOCK_FILE"
eq "$CLOSED" "rig list" "a candidate whose work search outlasts the budget is not closed"
has "$OUT" "s-a rig/pack.polecat-2 deferred: the pass budget (50s) ran out during its work search" \
  "a work search the budget cut off defers the candidate"
has "$(cat "$QUERIES")" "--db /city/rigs/a/.beads " "the store read that outlasted the budget was asked"
hasnt "$(cat "$QUERIES")" "--db /city/rigs/b/.beads " "no store read starts once the budget is spent"

# A candidate whose reads all finished is never cut off. Its close runs though
# the last store read of its second search spent the budget, its ledger entry
# runs though the close did, and only the next candidate is deferred.
reset_world
pool_bead s-a; pool_bead s-b
sessions s-a:asleep:false s-b:asleep:false
date -u +%s > "$CLOCK_FILE"
PATH="$TMP/clock:$PATH" SLOW_S=100 STORE_SLOW=/city/rigs/b/.beads SLOW_READ=2 POOL_SLOT_REAP_BUDGET_S=50 run
rm -f "$CLOCK_FILE"
has "$CLOSED" "close s-a" "a candidate whose last read spent the budget is still closed"
has "$(cat "$LEDGER_CALLS")" "bead:s-a" "a candidate whose last read spent the budget is recorded"
has "$OUT" "closed 1, kept 0, skipped 0, deferred 1" "only the candidate after it is deferred"

reset_world
pool_bead s-a; pool_bead s-b
sessions s-a:asleep:false s-b:asleep:false
date -u +%s > "$CLOCK_FILE"
PATH="$TMP/clock:$PATH" SLOW_S=100 CLOSE_SLOW=s-a POOL_SLOT_REAP_BUDGET_S=50 run
rm -f "$CLOCK_FILE"
has "$CLOSED" "close s-a" "a close that runs past the budget completes"
has "$(cat "$LEDGER_CALLS")" "bead:s-a" "a close that runs past the budget is recorded"
has "$OUT" "closed 1, kept 0, skipped 0, deferred 1" "only the candidate after the slow close is deferred"

# --- (TIMEOUT) the order's timeout covers the pass's worst case -----------------
# No read starts past the budget, so a pass ends within the budget plus one read
# that started just before it ran out, plus the last candidate's close tail: the
# close, the read that settles a failed close, and the ledger append. Each
# call is bounded at CALL_TIMEOUT_S plus the SIGKILL grace.
ORDER="$ROOT/orders/pool-slot-reap.toml"
budget="$(sed -n 's/^BUDGET_S="\${POOL_SLOT_REAP_BUDGET_S:-\([0-9][0-9]*\)}"$/\1/p' "$SUT")"
callt="$(sed -n 's/^CALL_TIMEOUT_S="\${POOL_SLOT_REAP_CALL_TIMEOUT_S:-\([0-9][0-9]*\)}"$/\1/p' "$SUT")"
killa="$(sed -n 's/^KILL_AFTER_S=\([0-9][0-9]*\)$/\1/p' "$SUT")"
otimeout="$(sed -n 's/^timeout = "\([0-9][0-9]*\)s"$/\1/p' "$ORDER" 2>/dev/null)"
if [ -n "$budget" ] && [ -n "$callt" ] && [ -n "$killa" ] && [ -n "$otimeout" ]; then
  worst=$(( budget + 4 * (callt + killa) ))
  [ "$otimeout" -gt "$worst" ] \
    && ok "the order's ${otimeout}s timeout sits above the pass's ${worst}s worst case" \
    || bad "the order's ${otimeout}s timeout sits above the pass's ${worst}s worst case"
else
  bad "the budget, call bound and order timeout are readable (budget='$budget' call='$callt' kill='$killa' order='$otimeout')"
fi

# --- (GRACE) the window is a knob ----------------------------------------------
reset_world
pool_bead s-a "{\"slept_at\":\"$FRESH\"}"
sessions s-a:asleep:false
POOL_SLOT_REAP_GRACE_S=30 run
has "$CLOSED" "close s-a" "a shorter grace window closes a session asleep longer than it"

# --- (KNOB) ---------------------------------------------------------------------
reset_world
POOL_SLOT_REAP_GRACE_S=15m run
eq "$RC" "2" "a malformed grace knob is a usage error"
run --bogus
eq "$RC" "2" "an unknown argument is a usage error"

# --- (DISKPRESSURE) -------------------------------------------------------------
reset_world
pool_bead s-a; sessions s-a:asleep:false
TMPDIR="$TMP/no-such-dir" run
eq "$RC" "1" "a failed temp-file enumeration exits 1"
eq "$CLOSED" "rig list" "a failed temp-file enumeration closes nothing"
hasnt "$OUT" "closed 0" "a failed enumeration prints no all-clear summary"

echo
echo "pool-slot-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
