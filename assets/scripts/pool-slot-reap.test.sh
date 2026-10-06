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
# store. The stub answers `session list` and `rig list` from fixture files,
# `bd show <id>` from a per-bead fixture (a `.second.json` fixture answers every
# read after the first), and `bd list --db <store> --assignee <who>` from a
# per-(store, assignee) fixture, `[]` when there is none. It records every
# `session close` and every work query; the ledger stub records each append.
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
#   (NAMED/MANUAL/NOTPOOL) a configured named session, a manual session, and a
#               session that is not pool-managed are never closed
#   (AWAKE)     a persisted-awake bead the listing reads asleep is kept
#   (UNAGED)    a bead with no readable slept_at is kept
#   (WORK)      work open or in_progress under the id, session_name, alias, or a
#               prior alias, in any store, keeps the bead
#   (SLOTNAME)  work under the numbered slot name alone does not keep it
#   (SESSIONROW) a session bead under the id is not work
#   (QUERY)     the work query asks every store for open,in_progress with
#               --include-infra --include-ephemeral --limit 0
#   (STOREFAIL) an unreadable store, or a work answer that is not rows, skips
#               the bead, never closes it
#   (CHANGED)   a second read that differs from the first keeps the bead
#   (ROWS)      active and closed rows are never candidates
#   (SHOWFAIL/NOTSESSION) an unreadable bead or a non-session bead is skipped
#   (CLOSEFAIL) a failed close is reported, not recorded, and left for next pass
#   (LEDGERFAIL) a close the ledger could not record exits 1 and names it
#   (DRYRUN)    --dry-run names the plan, closes nothing, records nothing
#   (LISTFAIL/ROSTERFAIL) an unreadable session list or rig roster exits 1 and
#               closes nothing
#   (NOCAND)    with no asleep row the pass exits 0 without reading the roster
#   (BUDGET)    candidates past the pass budget are deferred, not closed
#   (KNOB)      a malformed knob is a usage error
#   (DISKPRESSURE) a failed temp-file enumeration exits 1 and closes nothing
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

mkdir -p "$TMP/bin" "$TMP/beads" "$TMP/work"
export SESSIONS_FILE="$TMP/sessions.json" ROSTER_FILE="$TMP/roster.json"
export BEADS_DIR="$TMP/beads" WORK_DIR="$TMP/work"
export CALLS="$TMP/calls" QUERIES="$TMP/queries" LEDGER_CALLS="$TMP/ledger"
export POOL_SLOT_REAP_GC="$TMP/bin/gc" POOL_SLOT_REAP_LEDGER="$TMP/bin/ledger"

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
all="$*"
case "$1 ${2:-}" in
  "session list")
    if [ -n "${LIST_BROKEN:-}" ]; then echo "gc: not json here"; exit 0; fi
    cat "$SESSIONS_FILE" ;;
  "rig list")
    printf 'rig list\n' >> "$CALLS"
    if [ -n "${ROSTER_BROKEN:-}" ]; then echo "gc: not json here"; exit 0; fi
    cat "$ROSTER_FILE" ;;
  "bd show")
    id="$3"
    n="$(cat "$BEADS_DIR/$id.reads" 2>/dev/null || echo 0)"; n=$((n + 1))
    echo "$n" > "$BEADS_DIR/$id.reads"
    if [ "${SHOW_BROKEN:-}" = "$id" ]; then echo "gc bd: garbled >>>"; exit 0; fi
    if [ "$n" -ge 2 ] && [ -f "$BEADS_DIR/$id.second.json" ]; then cat "$BEADS_DIR/$id.second.json"; exit 0; fi
    if [ -f "$BEADS_DIR/$id.json" ]; then cat "$BEADS_DIR/$id.json"
    else jq -n '{error:"no issues found matching the provided IDs"}'; exit 1; fi ;;
  "bd list")
    shift 2; db=""; who=""
    while [ $# -gt 0 ]; do
      case "$1" in --db) db="$2"; shift ;; --assignee) who="$2"; shift ;; esac
      shift
    done
    printf '%s\n' "$all" >> "$QUERIES"
    case " ${STORE_BROKEN:-} " in *" $db "*) echo "gc bd: store unavailable"; exit 1 ;; esac
    f="$WORK_DIR/$(printf '%s' "$db" | tr '/' '_')__$(printf '%s' "$who" | tr '/' '_').json"
    if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
  "session close")
    sid="$3"
    case " ${CLOSE_FAILS:-} " in *" $sid "*) exit 1 ;; esac
    printf 'close %s\n' "$sid" >> "$CALLS"; exit 0 ;;
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
work() { # <store> <assignee> <bead-id> [issue_type]
  local f
  f="$WORK_DIR/$(printf '%s' "$1" | tr '/' '_')__$(printf '%s' "$2" | tr '/' '_').json"
  jq -n --arg id "$3" --arg t "${4:-task}" '[{id: $id, issue_type: $t, status: "in_progress"}]' > "$f"
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
  : > "$CALLS"; : > "$QUERIES"; : > "$LEDGER_CALLS"
  rm -f "$BEADS_DIR"/* "$WORK_DIR"/*
  jq -n '{city_path: "/city", rigs: [{name: "city", path: "/city", hq: true},
                                     {name: "a", path: "/city/rigs/a"},
                                     {name: "b", path: "/city/rigs/b"}]}' > "$ROSTER_FILE"
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
pool_bead s-manual    '{"session_origin":"manual","pool_managed":""}'
pool_bead s-notpool   '{"session_origin":"named","pool_managed":""}'
pool_bead s-awake     '{"state":"awake","sleep_reason":""}'
pool_bead s-unaged    '{"slept_at":""}'
pool_bead s-work-id
pool_bead s-work-name
pool_bead s-work-alias '{"alias":"rig/pack.polecat"}'
pool_bead s-work-hist  '{"alias_history":"old/one,rig/old-alias"}'
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
work /city/rigs/a/.beads rig/pack.polecat-2         tk-slot-only
work /city/.beads        s-sessrow                  lx-wisp-self session

ALL_ASLEEP=(s-killed s-idle s-drift s-drained s-settling s-fence s-wake s-oldwake
  s-userhold s-waithold s-quar s-churn s-rate s-helduntil s-quntil s-waitmark s-pinned
  s-named s-manual s-notpool s-awake s-unaged s-work-id s-work-name s-work-alias
  s-work-hist s-slotname s-sessrow s-changed s-moved s-task s-garbled s-gone)
specs=()
for id in "${ALL_ASLEEP[@]}"; do specs+=("$id:asleep:false"); done
sessions "${specs[@]}" s-active:active:false s-closedrow:asleep:true
pool_bead s-active
pool_bead s-closedrow

SHOW_BROKEN=s-garbled run
eq "$RC" "0" "a normal pass exits 0"

for id in s-killed s-idle s-drift s-drained s-oldwake s-slotname s-sessrow; do
  has "$CLOSED" "close $id" "$id is closed"
done
for id in s-settling s-fence s-wake s-userhold s-waithold s-quar s-churn s-rate s-helduntil \
          s-quntil s-waitmark s-pinned s-named s-manual s-notpool s-awake s-unaged s-work-id \
          s-work-name s-work-alias s-work-hist s-changed s-moved s-task s-garbled s-gone \
          s-active s-closedrow; do
  hasnt "$CLOSED"$'\n' "close $id"$'\n' "$id is not closed"
done
eq "$(grep -c '^close ' "$CALLS")" "7" "exactly the seven ghosts are closed"

LEDGER_OUT="$(cat "$LEDGER_CALLS")"
eq "$(grep -c . "$LEDGER_CALLS")" "7" "every close is one ledger entry"
has "$LEDGER_OUT" "/city|append cleanup pool-slot-reap closed s-killed rig/pack.polecat-2 (sleep_reason=killed, asleep since $OLD): no runtime, no assigned work bead:s-killed" \
  "the ledger entry is a cleanup in the city store naming the bead, its slot, why it slept, and the bead ref"
has "$LEDGER_OUT" "closed s-idle rig/pack.polecat-2 (sleep_reason=idle" "an idle ghost's entry names its reason"

has "$OUT" "closed 7, kept 23, skipped 3, deferred 0 of the asleep sessions" "the summary counts closed / kept / skipped / deferred"
has "$OUT" "  s-killed rig/pack.polecat-2 (sleep_reason=killed, asleep since $OLD): no runtime, no assigned work" "the summary lists each close"
has "$OUT" "s-settling rig/pack.polecat-2 kept: settling" "a session inside the window is reported as settling"
has "$OUT" "s-userhold rig/pack.polecat-2 kept: held (user-hold)" "a held session is reported as held"
has "$OUT" "s-helduntil rig/pack.polecat-2 kept: held (hold marker set)" "a hold marker is reported as held"
has "$OUT" "s-pinned rig/pack.polecat-2 kept: pinned awake" "a pinned session is reported as pinned"
has "$OUT" "s-named rig/pack.polecat-2 kept: named session" "a named session is reported as named"
has "$OUT" "s-manual rig/pack.polecat-2 kept: manual session" "a manual session is reported as manual"
has "$OUT" "s-notpool rig/pack.polecat-2 kept: not pool-managed" "a non-pool session is reported as not pool-managed"
has "$OUT" "s-awake rig/pack.polecat-2 kept: persisted state awake" "a persisted-awake bead is reported by its state"
has "$OUT" "s-unaged rig/pack.polecat-2 kept: unaged" "a bead with no slept_at is reported unaged"
has "$OUT" "s-work-id rig/pack.polecat-2 kept: work tk-held-1 is assigned to it" "work under the id is named"
has "$OUT" "s-work-name rig/pack.polecat-2 kept: work lx-held-2 is assigned to it" "work under the session_name is named"
has "$OUT" "s-work-alias rig/pack.polecat-2 kept: work gc-held-3 is assigned to it" "work under the alias is named"
has "$OUT" "s-work-hist rig/pack.polecat-2 kept: work tk-held-4 is assigned to it" "work under a prior alias is named"
has "$OUT" "s-changed rig/pack.polecat-2 kept: its lifecycle changed during the pass" "a wake landing between the reads keeps the bead"
has "$OUT" "s-moved rig/pack.polecat-2 kept: its lifecycle changed during the pass" "a changed fingerprint keeps the bead even when both reads are eligible"
has "$OUT" "s-task rig/pack.polecat-2 skipped: not a session bead" "a non-session bead is skipped"
has "$OUT" "s-garbled - skipped" "an unreadable bead read is skipped"
has "$OUT" "s-gone - skipped" "a bead that no longer resolves is skipped"
hasnt "$OUT" "s-active" "an active row is never a candidate"
hasnt "$OUT" "s-closedrow" "a closed row is never a candidate"

# (QUERY) the work search: every store, open+in_progress, ephemeral rows included.
Q="$(cat "$QUERIES")"
for store in /city/.beads /city/rigs/a/.beads /city/rigs/b/.beads; do
  has "$Q" "--db $store --assignee s-killed " "the work search asks $store"
done
has "$(grep -- '--assignee s-killed ' "$QUERIES" | head -1)" "--status open,in_progress --limit 0 --include-infra --include-ephemeral --json" \
  "the work query reads open and in_progress, every row, ephemeral included"
hasnt "$Q" "--assignee rig/pack.polecat-2 " "the numbered slot name is never searched as an owner"
has "$Q" "--assignee rig__polecat-s-killed " "the session_name is searched"
has "$Q" "--assignee old/one " "every prior alias is searched"

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
printf '["not a row"]' > "$WORK_DIR/$(printf '%s' /city/.beads | tr '/' '_')__s-killed.json"
run
eq "$CLOSED" "rig list" "a work answer that is not rows closes nothing"
has "$OUT" "s-killed rig/pack.polecat-2 skipped: assigned work could not be read" "a malformed work answer is a skip"

# --- (CLOSEFAIL) ----------------------------------------------------------------
reset_world
pool_bead s-a; pool_bead s-b
sessions s-a:asleep:false s-b:asleep:false
CLOSE_FAILS=s-a run
eq "$RC" "0" "a failed close does not fail the pass"
has "$CLOSED" "close s-b" "the other ghost still closes"
has "$ERR" "could not close s-a" "the failed close is reported on stderr"
has "$OUT" "s-a rig/pack.polecat-2 skipped: gc session close failed" "the failed close is counted skipped"
hasnt "$(cat "$LEDGER_CALLS")" "bead:s-a" "a failed close is never recorded as closed"

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
