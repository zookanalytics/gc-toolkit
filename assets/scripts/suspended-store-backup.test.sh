#!/usr/bin/env bash
# Hermetic test for assets/scripts/suspended-store-backup.sh, the pass that backs
# up the suspended rigs' stores that still take writes. A stub `gc` on PATH
# answers the rig list and stands in for each `gc bd ... backup sync`. flock and
# timeout are the real ones, because what the pass owes mol-dog-backup is how it
# holds a real lock. No live city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/suspended-store-backup.sh"
ORDER="$HERE/../../orders/suspended-store-backup.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-suspended-store-backup-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

unset GC_CITY_PATH GC_DOLT_BACKUP_LOCK_FILE GC_SUSPENDED_BACKUP_LOCK_WAIT GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS GC_RIG_LIST_TIMEOUT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

REAL_FLOCK="$(command -v flock)"
mkdir -p "$TMP/bin" "$TMP/city"
CITY="$(cd "$TMP/city" && pwd -P)"
export STUB_DIR="$TMP/stub"
LOCK="$TMP/backup-sync.lock"

# --- the stub gc -------------------------------------------------------------
# A sync records what it finds as it runs: whether it was handed the lock's
# descriptor, and whether the lock is held. $STUB_DIR/sync.<rig> names how that
# rig's sync ends.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
set -u
printf '%s\n' "$*" >> "$STUB_DIR/gc.log"
case "$*" in
  --city\ *\ rig\ list\ --json)
    if [ -f "$STUB_DIR/rigs.fail" ]; then
      echo "gc rig list: loading city.toml: permission denied" >&2
      exit 1
    fi
    cat "$STUB_DIR/rigs.json"
    ;;
  bd\ --city\ *\ --rig\ *\ backup\ sync)
    rig="$5"
    { : >&9; } 2>/dev/null && fd9=open || fd9=closed
    if ( exec 8>>"$STUB_LOCK"; flock -n 8 ) 2>/dev/null; then lock=free; else lock=held; fi
    holder=gone
    [ ! -f "$STUB_DIR/holder.up" ] || [ -f "$STUB_DIR/holder.done" ] || holder=live
    printf '%s fd9=%s lock=%s holder=%s\n' "$rig" "$fd9" "$lock" "$holder" >> "$STUB_DIR/synced"
    case "$(cat "$STUB_DIR/sync.$rig" 2>/dev/null || echo ok)" in
      ok) echo "Backup synced in 41ms" ;;
      fail)
        echo "gc bd: answering from the rig store"
        printf 'a warning gc printed first %.0s' $(seq 1 20) >&2
        echo >&2
        echo "first line of the failure" >&2
        echo "second line of the failure" >&2
        echo "backup sync failed: disk full" >&2
        exit 3
        ;;
      hang) exec sleep 30 ;;
      hang-child)
        sleep 30 >/dev/null 2>&1 &
        echo "$!" > "$STUB_DIR/child.pid"
        wait
        ;;
    esac
    ;;
  *) echo "stub gc: unexpected call: $*" >&2; exit 64 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# --- fixtures ----------------------------------------------------------------
reset() { rm -rf "${STUB_DIR:?}" "${CITY:?}/rigs" "$LOCK"; mkdir -p "$STUB_DIR"; export STUB_LOCK="$LOCK"; RIGS=""; }

# rig <name> <suspended> <hq> <config text> <registered: yes|no>
rig() {
  local root="$CITY/rigs/$1"
  mkdir -p "$root/.beads"
  [ "$4" = - ] || printf '%b' "$4" > "$root/.beads/config.yaml"
  [ "$5" = no ] || printf '{"backup_name":"default"}\n' > "$root/.beads/dolt-backup.json"
  RIGS="$RIGS${RIGS:+,}{\"name\":\"$1\",\"path\":\"$root\",\"hq\":$3,\"suspended\":$2}"
}
INHERITS='issue_prefix: x\ngc.endpoint_origin: inherited_city\ndolt.mode: server\n'
list_rigs() { printf '{"schema_version":"1","rigs":[%s]}\n' "$RIGS" > "$STUB_DIR/rigs.json"; }

run() { # [VAR=value]...
  OUT="$(env PATH="$TMP/bin:$PATH" GC_CITY_PATH="$CITY" GC_DOLT_BACKUP_LOCK_FILE="$LOCK" GC_SUSPENDED_BACKUP_LOCK_WAIT=30 "$@" "$SUT" 2>&1)"; RC=$?
}
synced() { [ -f "$STUB_DIR/synced" ] && cut -d' ' -f1 "$STUB_DIR/synced" | tr '\n' ' ' | sed 's/ $//'; }
sync_calls() { grep -c ' backup sync$' "$STUB_DIR/gc.log" 2>/dev/null; }

# --- which stores a pass covers ----------------------------------------------
echo "# a pass covers each suspended rig whose store inherits the city's endpoint and has a registered destination"
reset
rig town true true "$INHERITS" yes
rig rig-a true false "$INHERITS" yes
rig rig-b false false "$INHERITS" yes
rig rig-c true false 'gc.endpoint_origin: explicit\n' yes
rig rig-d true false "$INHERITS" no
rig rig-e true false - yes
rig rig-f true false '# gc.endpoint_origin: explicit\ngc.endpoint_origin:   inherited_city  \ngc.endpoint_origin: explicit\n' yes
rig rig-g true false 'gc:\n  gc.endpoint_origin: inherited_city\n' yes
rig rig-h true false 'gc.endpoint_origin: "inherited_city"\n' yes
rig rig-i true false 'gc.endpoint_origin:\ngc.endpoint_origin: inherited_city\n' yes
list_rigs
run
eq "$RC" 0 "a pass whose syncs all succeed exits 0"
eq "$(synced)" "rig-a rig-f rig-i" "it syncs the covered stores, in the listing's order, and no other"
eq "$(sed -n 2p "$STUB_DIR/gc.log")" "bd --city $CITY --rig rig-a backup sync" "each through gc bd, naming the city and the rig"
eq "$(sed -n 1p "$STUB_DIR/gc.log")" "--city $CITY rig list --json" "the rig list names the city too"
has "$OUT" "rig-c: left alone, its endpoint origin is explicit" "a suspended rig with another origin is left alone, and the pass says why"
has "$OUT" "rig-d: left alone, it has no registered backup destination" "so is a store with no registered destination"
has "$OUT" "rig-e: left alone, its endpoint origin is not recorded" "and one whose config does not read"
has "$OUT" "rig-g: left alone" "an indented key is not the top-level line Gas City reads"
has "$OUT" 'rig-h: left alone, its endpoint origin is "inherited_city"' "and Gas City does not read a quoted value as an origin"
hasnt "$OUT" "rig-b" "a running rig is mol-dog-backup's, and goes unmentioned"
hasnt "$OUT" "town" "so does the city's own row, whatever it reports"
has "$OUT" "synced 3 of 3" "the summary counts what it covered"

echo "# a pass with nothing to cover"
reset
rig rig-b false false "$INHERITS" yes
rig rig-c true false 'gc.endpoint_origin: explicit\n' yes
list_rigs
run
eq "$RC" 0 "exits 0"
eq "$(sync_calls)" "0" "syncs nothing"
has "$OUT" "no suspended rig's store needs this backup" "and says so"
[ ! -e "$LOCK" ] && ok "and leaves the lock alone" || bad "and leaves the lock alone"

# --- the lock ----------------------------------------------------------------
echo "# a sync holds the lock, and the program it runs does not carry it"
reset
rig rig-a true false "$INHERITS" yes
list_rigs
run
eq "$(cat "$STUB_DIR/synced")" "rig-a fd9=closed lock=held holder=gone" "the lock is held during the sync, with its descriptor closed in the child"

echo "# the lock defaults to mol-dog-backup's own path"
reset
rig rig-a true false "$INHERITS" yes
list_rigs
export STUB_LOCK="$CITY/.gc/runtime/packs/dolt/backup-sync.lock"
OUT="$(env PATH="$TMP/bin:$PATH" GC_CITY_PATH="$CITY" GC_SUSPENDED_BACKUP_LOCK_WAIT=30 "$SUT" 2>&1)"; RC=$?
eq "$RC" 0 "a pass with no lock override runs"
eq "$(cat "$STUB_DIR/synced")" "rig-a fd9=closed lock=held holder=gone" "and holds <city>/.gc/runtime/packs/dolt/backup-sync.lock during the sync"
rm -rf "${CITY:?}/.gc"

# A flock on PATH ahead of the real one logs each call and, before a wait, whether
# anyone holds the lock at that moment.
mkdir -p "$TMP/flockshim"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/flockshim/flock" <<'SHIM'
case "$1" in
  -w)
    if ( exec 8>>"$STUB_LOCK"; "$REAL_FLOCK" -n 8 ) 2>/dev/null; then state=free; else state=held; fi
    printf '%s %s\n' "$*" "$state" >> "$STUB_DIR/flock.log"
    ;;
  -u) printf '%s\n' "$*" >> "$STUB_DIR/flock.log" ;;
esac
exec "$REAL_FLOCK" "$@"
SHIM
chmod +x "$TMP/flockshim/flock"
export REAL_FLOCK

echo "# the lock is released between stores, so mol-dog-backup's short wait can win it"
reset
rig rig-a true false "$INHERITS" yes
rig rig-f true false "$INHERITS" yes
list_rigs
OUT="$(env PATH="$TMP/flockshim:$TMP/bin:$PATH" GC_CITY_PATH="$CITY" GC_DOLT_BACKUP_LOCK_FILE="$LOCK" GC_SUSPENDED_BACKUP_LOCK_WAIT=30 "$SUT" 2>&1)"; RC=$?
eq "$RC" 0 "a pass under the logging flock runs"
eq "$(tr '\n' '|' < "$STUB_DIR/flock.log")" "-w 30 9 free|-u 9|-w 30 9 free|-u 9|" "each store takes the lock and gives it back, and the next finds it free"

echo "# the wait outlasts a run that holds the lock"
reset
rig rig-a true false "$INHERITS" yes
list_rigs
( exec 8>>"$LOCK"; flock 8; : > "$STUB_DIR/holder.up"; sleep 2; : > "$STUB_DIR/holder.done" ) >/dev/null 2>&1 &
HOLDER=$!
i=0; while [ ! -f "$STUB_DIR/holder.up" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done
run
wait "$HOLDER" 2>/dev/null
eq "$RC" 0 "the pass waits for the holder rather than skipping"
eq "$(cat "$STUB_DIR/synced")" "rig-a fd9=closed lock=held holder=gone" "and syncs only once the holder has finished"

echo "# a lock that stays held past the wait"
reset
rig rig-a true false "$INHERITS" yes
rig rig-f true false "$INHERITS" yes
list_rigs
( exec 8>>"$LOCK"; flock 8; : > "$STUB_DIR/holder.up"; until [ -f "$STUB_DIR/holder.release" ]; do sleep 0.05; done ) >/dev/null 2>&1 &
HOLDER=$!
i=0; while [ ! -f "$STUB_DIR/holder.up" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done
OUT="$(env PATH="$TMP/flockshim:$TMP/bin:$PATH" GC_CITY_PATH="$CITY" GC_DOLT_BACKUP_LOCK_FILE="$LOCK" GC_SUSPENDED_BACKUP_LOCK_WAIT=1 "$SUT" 2>&1)"; RC=$?
: > "$STUB_DIR/holder.release"
wait "$HOLDER" 2>/dev/null
eq "$RC" 1 "fails the pass, so it shows in the order's outcome"
eq "$(sync_calls)" "0" "syncs nothing, since no sync may run without the lock"
has "$OUT" "rig-a: not synced, mol-dog-backup's lock stayed held past 1s" "names the first store"
has "$OUT" "rig-f: not synced, mol-dog-backup's lock stayed held past 1s" "and the one that never got a turn"
eq "$(grep -c '^-w ' "$STUB_DIR/flock.log")" "1" "and waits once, so a wedged lock cannot spend the order's timeout store by store"

echo "# no flock at all"
reset
rig rig-a true false "$INHERITS" yes
list_rigs
mkdir -p "$TMP/noflock"
for c in bash dirname; do ln -sf "$(command -v "$c")" "$TMP/noflock/$c"; done
OUT="$(env PATH="$TMP/noflock:$TMP/bin" GC_CITY_PATH="$CITY" GC_DOLT_BACKUP_LOCK_FILE="$LOCK" "$(command -v bash)" "$SUT" 2>&1)"; RC=$?
eq "$RC" 1 "a pass that cannot lock fails"
has "$OUT" "flock not found" "and names what is missing"
[ ! -f "$STUB_DIR/gc.log" ] && ok "before any gc call" || bad "before any gc call"

# --- a failed sync -----------------------------------------------------------
echo "# a failed sync shows in the outcome, and the remaining rigs still get their turn"
reset
rig rig-a true false "$INHERITS" yes
rig rig-f true false "$INHERITS" yes
list_rigs
echo fail > "$STUB_DIR/sync.rig-a"
run
eq "$RC" 1 "a pass with a failed sync exits 1"
eq "$(synced)" "rig-a rig-f" "the next store still syncs"
has "$OUT" "rig-f: synced" "and reads as synced"
has "$OUT" "synced 1 of 2" "the summary counts only the sync that worked"
LAST="$(printf '%s\n' "$OUT" | tail -n 1)"
has "$LAST" "rig-a: backup sync exited 3: " "the failure ends the output, where the order.failed event's tail keeps it"
has "$LAST" "backup sync failed: disk full" "with the reason the sync gave"
has "$LAST" "second line of the failure backup sync failed" "squeezed onto one line"
hasnt "$LAST" "answering from the rig store" "and only the end of what it printed, past the noise before it"
eq "$(printf '%s\n' "$OUT" | grep -c 'rig-a: backup sync exited 3')" "1" "named once"
[ "${#LAST}" -le 400 ] && ok "a line short enough for that tail" || bad "a line short enough for that tail (${#LAST} chars)"

echo "# a sync that hangs is bounded, and the remaining rigs still get their turn"
reset
rig rig-a true false "$INHERITS" yes
rig rig-f true false "$INHERITS" yes
list_rigs
echo hang > "$STUB_DIR/sync.rig-a"
run GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS=1
eq "$RC" 1 "a pass with a hung sync exits 1"
eq "$(synced)" "rig-a rig-f" "the next store still syncs"
has "$OUT" "rig-a: backup sync timed out after 1s" "the hang is named as one"

echo "# the bound reaches the bd that gc bd runs as a child"
reset
rig rig-a true false "$INHERITS" yes
list_rigs
echo hang-child > "$STUB_DIR/sync.rig-a"
run GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS=1
eq "$RC" 1 "the pass fails"
CHILD="$(cat "$STUB_DIR/child.pid" 2>/dev/null)"
i=0; while [ -n "$CHILD" ] && kill -0 "$CHILD" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
if [ -n "$CHILD" ] && kill -0 "$CHILD" 2>/dev/null; then
  bad "the child of the bounded sync is gone"
  kill "$CHILD" 2>/dev/null
else
  [ -n "$CHILD" ] && ok "the child of the bounded sync is gone" || bad "the stub recorded no child"
fi

echo "# no bound to be had: the sync still runs, under the order's own timeout"
reset
rig rig-a true false "$INHERITS" yes
list_rigs
mkdir -p "$TMP/nobound"
for c in bash dirname jq awk flock mkdir mktemp rm tail tr cut sed cat; do ln -sf "$(command -v "$c")" "$TMP/nobound/$c"; done
OUT="$(env PATH="$TMP/nobound:$TMP/bin" GC_CITY_PATH="$CITY" GC_DOLT_BACKUP_LOCK_FILE="$LOCK" GC_SUSPENDED_BACKUP_LOCK_WAIT=30 "$(command -v bash)" "$SUT" 2>&1)"; RC=$?
eq "$RC" 0 "a host with no timeout command still backs up"
eq "$(cat "$STUB_DIR/synced")" "rig-a fd9=closed lock=held holder=gone" "under the lock, without its descriptor"

# --- a pass that cannot start ------------------------------------------------
echo "# the rig list does not read"
reset
rig rig-a true false "$INHERITS" yes
list_rigs
: > "$STUB_DIR/rigs.fail"
run
eq "$RC" 1 "a pass with no rig list fails, so a store it could not reach cannot read as covered"
has "$OUT" "permission denied" "naming the reason gc gave"
eq "$(sync_calls)" "0" "and syncs nothing"

echo "# the rig map does not parse"
reset
rig rig-a true false "$INHERITS" yes
list_rigs
mkdir -p "$TMP/badjq"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/badjq/jq" <<'JQ'
case "$*" in *.suspended*) exit 5 ;; esac
exec "$REAL_JQ" "$@"
JQ
chmod +x "$TMP/badjq/jq"
OUT="$(env REAL_JQ="$(command -v jq)" PATH="$TMP/badjq:$TMP/bin:$PATH" GC_CITY_PATH="$CITY" GC_DOLT_BACKUP_LOCK_FILE="$LOCK" GC_SUSPENDED_BACKUP_LOCK_WAIT=30 "$SUT" 2>&1)"; RC=$?
eq "$RC" 1 "a pass that cannot read its rig list fails, rather than read as nothing to do"
has "$OUT" "could not read the rig map" "and says so"
eq "$(sync_calls)" "0" "and syncs nothing"

echo "# the lock cannot be opened"
reset
rig rig-a true false "$INHERITS" yes
list_rigs
: > "$TMP/not-a-dir"
OUT="$(env PATH="$TMP/bin:$PATH" GC_CITY_PATH="$CITY" GC_DOLT_BACKUP_LOCK_FILE="$TMP/not-a-dir/backup-sync.lock" GC_SUSPENDED_BACKUP_LOCK_WAIT=30 "$SUT" 2>&1)"; RC=$?
eq "$RC" 1 "a pass with no lock fails"
has "$OUT" "cannot open the lock" "and says so"
eq "$(sync_calls)" "0" "and syncs nothing"

echo "# usage"
reset
list_rigs
OUT="$(env PATH="$TMP/bin:$PATH" "$SUT" 2>&1)"; RC=$?
eq "$RC" 2 "no city in the environment is a usage error"
has "$OUT" "GC_CITY_PATH is not set" "and says which"
OUT="$(env PATH="$TMP/bin:$PATH" GC_CITY_PATH="$TMP/no-such-city" "$SUT" 2>&1)"; RC=$?
eq "$RC" 2 "a city that is not there is one too"
OUT="$(env PATH="$TMP/bin:$PATH" GC_CITY_PATH="$CITY" "$SUT" extra 2>&1)"; RC=$?
eq "$RC" 2 "an argument is one too"
for bad_value in abc 0 00 ""; do
  run GC_SUSPENDED_BACKUP_LOCK_WAIT="$bad_value"
  if [ -z "$bad_value" ]; then
    eq "$RC" 0 "an empty lock wait takes the default"
  else
    eq "$RC" 2 "a lock wait of '$bad_value' is refused"
    has "$OUT" "GC_SUSPENDED_BACKUP_LOCK_WAIT='$bad_value'" "naming the setting"
  fi
  run GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS="$bad_value"
  if [ -z "$bad_value" ]; then
    eq "$RC" 0 "an empty sync bound takes the default"
  else
    eq "$RC" 2 "a sync bound of '$bad_value' is refused"
    has "$OUT" "GC_DOLT_BACKUP_SYNC_TIMEOUT_SECS='$bad_value'" "naming the setting"
  fi
done

# --- the order ---------------------------------------------------------------
echo "# the order runs the pass at city scope on mol-dog-backup's cadence"
ORDER_TEXT="$(sed 's/#.*//' "$ORDER")"
has "$ORDER_TEXT" 'scope = "city"' "at city scope"
has "$ORDER_TEXT" 'trigger = "cooldown"' "on a cooldown"
has "$ORDER_TEXT" 'interval = "6h"' "of six hours"
has "$ORDER_TEXT" 'exec = "$PACK_DIR/assets/scripts/suspended-store-backup.sh"' "running this script"
hasnt "$ORDER_TEXT" 'idempotent' "and never fires past a timed-out open-work gate, because the pass writes"
TIMEOUT_SECS="$(printf '%s\n' "$ORDER_TEXT" | sed -n 's/^timeout = "\([0-9]*\)s"$/\1/p')"
DEFAULT_WAIT="$(sed -n 's/^: "${GC_SUSPENDED_BACKUP_LOCK_WAIT:=\([0-9]*\)}"$/\1/p' "$SUT")"
[ "${DEFAULT_WAIT:-0}" -gt 1800 ] && ok "the default wait outlasts mol-dog-backup's 1800s timeout" || bad "the default wait outlasts mol-dog-backup's 1800s timeout (got '$DEFAULT_WAIT')"
[ "${TIMEOUT_SECS:-0}" -gt "${DEFAULT_WAIT:-0}" ] && ok "the order's timeout leaves room for syncs past that wait" || bad "the order's timeout leaves room for syncs past that wait (got '$TIMEOUT_SECS' over '$DEFAULT_WAIT')"

echo
echo "suspended-store-backup.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
