#!/usr/bin/env bash
# Hermetic test for notification-wisp-reap.sh.
#
# The reap closes city-store notification wisps that core mails and never
# retires: a "Human gate awaiting you: <gate>" notice once its gate is no longer
# open, and the surplus copies of a repeated "ESCALATION: <headline>" collapsed
# to one open notice.
#
# Runs the REAL notification-wisp-reap.sh with a stubbed `gc`
# (NOTIFICATION_WISP_REAP_GC) — no live city or store. The stub answers `bd list`
# from a fixture of open city-store wisps, `bd show <gate>` from a per-gate
# fixture (absent => the not-found error object, with the non-zero exit, that bd
# really returns when nothing resolves), `rig list` from a city_path env, and
# records every `bd close` to $CALLS.
# Covered:
#   (RESOLVED) a gate notice whose gate reads closed is closed
#   (GONE)     a gate notice whose gate no longer resolves is closed
#   (OPEN)     a gate notice whose gate is still open is kept
#   (CROSSRIG) a notice naming a foreign-rig gate is classified by that gate
#   (NONGATE)  a title id that resolves to a non-gate bead is left alone
#   (BADID)    a title tail that is not a bead id is left alone
#   (ESC)      duplicate escalation copies collapse to the NEWEST, closing the rest
#   (ESCSOLO)  a lone escalation headline is kept
#   (SCOPE)    a non-gate, non-escalation message (BOOT_HEALTH) is untouched
#   (COUNTS)   the summary counts closed / kept / skipped for both passes
#   (DRYRUN)   --dry-run names the plan and closes nothing
#   (RIGLIST)  with no --db, the city store resolves from `gc rig list`
#   (UNREADABLE-LIST) a store listing that is not an array aborts (exit 1), closes 0
#   (UNREADABLE-GATE) a gate read that is not JSON is skipped, never closed
#   (OTHERERR) a gate read that fails with a non not-found error is skipped
#   (CLOSEFAIL) a notice that will not close is reported and left for next pass
#   (DISKFULL-GATE) a failed mktemp for the gate enumeration aborts (exit 1), no summary
#   (DISKFULL-ESC)  a failed mktemp for the escalation enumeration aborts, no summary
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/notification-wisp-reap.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-notif-reap-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()  { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SUT" ] && ok "notification-wisp-reap.sh present" || { bad "SUT missing at $SUT"; exit 1; }
command -v jq >/dev/null 2>&1 || { bad "jq required for this test"; exit 1; }

mkdir -p "$TMP/bin" "$TMP/beads" "$TMP/city/.beads"
export CALLS="$TMP/calls"
export WISPS_FILE="$TMP/wisps.json"
export BEADS_DIR="$TMP/beads"
export NOTIFICATION_WISP_REAP_GC="$TMP/bin/gc"
CITY_DB="$TMP/city/.beads"

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "rig list")
    jq -n --arg c "${RIG_CITY_PATH:-}" '{city_path:$c, rigs:[]}' ;;
  "bd list")
    if [ -n "${LIST_BROKEN:-}" ]; then echo "gc bd: not json here"; exit 0; fi
    cat "$WISPS_FILE" ;;
  "bd show")
    gid="$3"
    # An unreadable probe: not JSON at all, exit 0.
    if [ "${GATE_BROKEN:-}" = "$gid" ]; then echo "gc bd: garbled >>>"; exit 0; fi
    # A failure that is NOT not-found (a store blip): valid JSON, non-zero exit,
    # no not-found signature. The reap must skip it, never close.
    if [ "${GATE_ERROR:-}" = "$gid" ]; then jq -n '{error:"store temporarily unavailable", schema_version:1}'; exit 1; fi
    if [ -f "$BEADS_DIR/$gid.json" ]; then cat "$BEADS_DIR/$gid.json"; exit 0; fi
    # Nothing resolved: bd prints the not-found object AND exits non-zero.
    jq -n '{error:"no issues found matching the provided IDs", schema_version:1}'; exit 1 ;;
  "bd close")
    id="$3"
    case " ${CLOSE_FAILS:-} " in *" $id "*) exit 1 ;; esac
    echo "$*" >> "$CALLS"; exit 0 ;;
  *) echo "gc stub: unhandled: $*" >&2; exit 3 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# --- fixtures -----------------------------------------------------------------
# The open infra beads in the city store, one array as `bd list` returns.
cat > "$WISPS_FILE" <<'JSON'
[
  {"id":"lx-n-open",           "issue_type":"message","status":"open","title":"Human gate awaiting you: tk-gopen"},
  {"id":"lx-n-closed",         "issue_type":"message","status":"open","title":"Human gate awaiting you: tk-gclosed"},
  {"id":"lx-n-gone",           "issue_type":"message","status":"open","title":"Human gate awaiting you: tk-ggone"},
  {"id":"lx-n-nongate",        "issue_type":"message","status":"open","title":"Human gate awaiting you: tk-task"},
  {"id":"lx-n-badid",          "issue_type":"message","status":"open","title":"Human gate awaiting you: garbage here"},
  {"id":"lx-n-foreign-open",   "issue_type":"message","status":"open","title":"Human gate awaiting you: gc-gopen"},
  {"id":"lx-n-foreign-closed", "issue_type":"message","status":"open","title":"Human gate awaiting you: sl-gclosed"},
  {"id":"lx-esc-1",            "issue_type":"message","status":"open","title":"ESCALATION: Reaper anomalies detected [MEDIUM]","created_at":"2026-09-20T00:00:00Z"},
  {"id":"lx-esc-2",            "issue_type":"message","status":"open","title":"ESCALATION: Reaper anomalies detected [MEDIUM]","created_at":"2026-09-25T00:00:00Z"},
  {"id":"lx-esc-3",            "issue_type":"message","status":"open","title":"ESCALATION: Reaper anomalies detected [MEDIUM]","created_at":"2026-09-29T00:00:00Z"},
  {"id":"lx-esc-solo",         "issue_type":"message","status":"open","title":"ESCALATION: Different condition [LOW]","created_at":"2026-09-28T00:00:00Z"},
  {"id":"lx-boot",             "issue_type":"message","status":"open","title":"BOOT_HEALTH: deacon cold"}
]
JSON

# Per-gate fixtures, each the single-element array `bd show <id>` returns.
printf '[{"id":"tk-gopen","issue_type":"gate","status":"open"}]\n'      > "$BEADS_DIR/tk-gopen.json"
printf '[{"id":"tk-gclosed","issue_type":"gate","status":"closed"}]\n'  > "$BEADS_DIR/tk-gclosed.json"
printf '[{"id":"tk-task","issue_type":"task","status":"open"}]\n'       > "$BEADS_DIR/tk-task.json"
printf '[{"id":"gc-gopen","issue_type":"gate","status":"open"}]\n'      > "$BEADS_DIR/gc-gopen.json"
printf '[{"id":"sl-gclosed","issue_type":"gate","status":"closed"}]\n'  > "$BEADS_DIR/sl-gclosed.json"
# tk-ggone.json intentionally absent => the not-found signature.

run() { : > "$CALLS"; env "$@" bash "$SUT" --db "$CITY_DB" 2>"$TMP/err"; }

# --- MAIN pass ----------------------------------------------------------------
OUT="$(run)"; RC=$?
CALLED="$(cat "$CALLS")"
eq "$RC" "0" "MAIN: exits 0"
has "$OUT" "closed 3 stale gate notices" "COUNTS: 3 stale gate notices closed"
has "$OUT" "kept 2 live" "COUNTS: 2 live gate notices kept"
has "$OUT" "skipped 2" "COUNTS: 2 gate notices skipped (non-gate + bad id)"
has "$OUT" "closed 2 duplicate escalation notices" "COUNTS: 2 escalation copies closed"
has "$OUT" "kept 2 distinct" "COUNTS: 2 distinct escalation headlines kept"
has "$CALLED" "bd close lx-n-closed" "RESOLVED: a resolved-gate notice is closed"
has "$CALLED" "human gate tk-gclosed resolved" "RESOLVED: reason names the resolved gate"
has "$CALLED" "bd close lx-n-gone" "GONE: a gone-gate notice is closed"
has "$CALLED" "human gate tk-ggone gone" "GONE: reason names the gone gate"
has "$CALLED" "bd close lx-n-foreign-closed" "CROSSRIG: a foreign-rig resolved gate closes its notice"
hasnt "$CALLED" "bd close lx-n-open" "OPEN: a live-gate notice is kept"
hasnt "$CALLED" "bd close lx-n-foreign-open" "CROSSRIG: a foreign-rig OPEN gate keeps its notice"
hasnt "$CALLED" "bd close lx-n-nongate" "NONGATE: a non-gate title id is left alone"
hasnt "$CALLED" "bd close lx-n-badid" "BADID: a non-bead-id title tail is left alone"
has "$CALLED" "bd close lx-esc-1" "ESC: the older escalation copy is closed"
has "$CALLED" "bd close lx-esc-2" "ESC: the middle escalation copy is closed"
hasnt "$CALLED" "bd close lx-esc-3" "ESC: the NEWEST escalation copy is kept"
has "$CALLED" "superseded by lx-esc-3" "ESC: reason names the surviving newest copy"
hasnt "$CALLED" "bd close lx-esc-solo" "ESCSOLO: a lone escalation headline is kept"
hasnt "$CALLED" "bd close lx-boot" "SCOPE: a non-gate/non-escalation message is untouched"

# --- DRY RUN ------------------------------------------------------------------
: > "$CALLS"
OUT="$(bash "$SUT" --db "$CITY_DB" --dry-run 2>/dev/null)"; RC=$?
CALLED="$(cat "$CALLS")"
eq "$RC" "0" "DRYRUN: exits 0"
has "$OUT" "would close 3 stale gate notices" "DRYRUN: names the gate plan"
has "$OUT" "would close 2 duplicate escalation notices" "DRYRUN: names the escalation plan"
eq "$CALLED" "" "DRYRUN: closes nothing"

# --- RIG LIST resolution (no --db) --------------------------------------------
: > "$CALLS"
OUT="$(RIG_CITY_PATH="$TMP/city" bash "$SUT" 2>/dev/null)"; RC=$?
eq "$RC" "0" "RIGLIST: resolves the city store from gc rig list and runs"
has "$OUT" "closed 3 stale gate notices" "RIGLIST: same classification via resolved store"

# --- UNREADABLE LIST (fail closed) --------------------------------------------
: > "$CALLS"
OUT="$(LIST_BROKEN=1 bash "$SUT" --db "$CITY_DB" 2>"$TMP/err")"; RC=$?
eq "$RC" "1" "UNREADABLE-LIST: aborts with exit 1"
eq "$(cat "$CALLS")" "" "UNREADABLE-LIST: closes nothing"
has "$(cat "$TMP/err")" "could not read the city store" "UNREADABLE-LIST: says why"

# --- UNREADABLE GATE (fail safe) ----------------------------------------------
: > "$CALLS"
OUT="$(GATE_BROKEN=tk-gclosed bash "$SUT" --db "$CITY_DB" 2>/dev/null)"; RC=$?
CALLED="$(cat "$CALLS")"
eq "$RC" "0" "UNREADABLE-GATE: exits 0"
hasnt "$CALLED" "bd close lx-n-closed" "UNREADABLE-GATE: an unreadable gate is NOT closed"
has "$OUT" "closed 2 stale gate notices" "UNREADABLE-GATE: the unreadable one drops from the closed count"

# --- OTHER ERROR gate (fail safe) ---------------------------------------------
: > "$CALLS"
OUT="$(GATE_ERROR=tk-gclosed bash "$SUT" --db "$CITY_DB" 2>/dev/null)"; RC=$?
CALLED="$(cat "$CALLS")"
eq "$RC" "0" "OTHERERR: exits 0"
hasnt "$CALLED" "bd close lx-n-closed" "OTHERERR: a non not-found error is NOT read as gone"

# --- CLOSE FAIL ---------------------------------------------------------------
: > "$CALLS"
OUT="$(CLOSE_FAILS="lx-n-closed" bash "$SUT" --db "$CITY_DB" 2>"$TMP/err")"; RC=$?
CALLED="$(cat "$CALLS")"
eq "$RC" "0" "CLOSEFAIL: the pass exits 0"
has "$(cat "$TMP/err")" "could not close stale gate notice lx-n-closed" "CLOSEFAIL: the failure is reported"
has "$CALLED" "bd close lx-n-gone" "CLOSEFAIL: a failed close does not stop the pass"
has "$OUT" "closed 2 stale gate notices" "CLOSEFAIL: the failed close is not counted closed"
has "$OUT" "skipped 3" "CLOSEFAIL: the failed close is counted skipped"

# --- DISK PRESSURE (fail closed) ----------------------------------------------
# Each pass enumerates through a checked `mktemp`; under a full disk that mktemp
# fails and the pass must abort loud, never fall through to an all-clear summary
# (the defect: a `<<<` here-string's temp file failed silently and ran the loop
# zero times). A mktemp shim first on PATH stands in for the full disk. It is
# captured against the real mktemp so the calls it does not fail still return a
# file, and it fails the MKTEMP_FAIL_ON-th call so either pass can be singled
# out: call 1 is the gate enumeration, call 2 the escalation enumeration.
REAL_MKTEMP="$(command -v mktemp)"
mkdir -p "$TMP/diskfull-bin"
cat > "$TMP/diskfull-bin/mktemp" <<'MKTEMP'
#!/usr/bin/env bash
n=$(( $(cat "$MKTEMP_CTR" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$MKTEMP_CTR"
if [ "$n" = "${MKTEMP_FAIL_ON:-0}" ]; then echo "mktemp: Disk quota exceeded" >&2; exit 1; fi
exec "$REAL_MKTEMP" "$@"
MKTEMP
chmod +x "$TMP/diskfull-bin/mktemp"
MKTEMP_CTR="$TMP/mktemp.ctr"

# Pass 1's enumeration cannot get a temp file: the pass aborts non-zero, prints
# no summary (no forged empty-queue all-clear), closes nothing, and says why.
: > "$MKTEMP_CTR"
OUT="$(run PATH="$TMP/diskfull-bin:$PATH" MKTEMP_CTR="$MKTEMP_CTR" REAL_MKTEMP="$REAL_MKTEMP" MKTEMP_FAIL_ON=1)"; RC=$?
eq "$RC" "1" "DISKFULL-GATE: aborts with exit 1"
eq "$OUT" "" "DISKFULL-GATE: prints no summary"
eq "$(cat "$CALLS")" "" "DISKFULL-GATE: closes nothing"
has "$(cat "$TMP/err")" "could not create a temp file to enumerate gate notices" "DISKFULL-GATE: the blackout is announced on stderr"

# Pass 2's enumeration cannot get a temp file (the gate pass got one): the pass
# still aborts non-zero with no summary, so a disk-pressure blackout on EITHER
# loop can never read as an empty queue.
: > "$MKTEMP_CTR"
OUT="$(run PATH="$TMP/diskfull-bin:$PATH" MKTEMP_CTR="$MKTEMP_CTR" REAL_MKTEMP="$REAL_MKTEMP" MKTEMP_FAIL_ON=2)"; RC=$?
eq "$RC" "1" "DISKFULL-ESC: aborts with exit 1"
eq "$OUT" "" "DISKFULL-ESC: prints no summary"
has "$(cat "$TMP/err")" "could not create a temp file to enumerate escalation notices" "DISKFULL-ESC: the blackout is announced on stderr"

echo "notification-wisp-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
