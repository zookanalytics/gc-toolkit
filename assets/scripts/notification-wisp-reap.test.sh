#!/usr/bin/env bash
# Hermetic test for notification-wisp-reap.sh.
#
# The reap collapses the surplus copies of a repeated core "ESCALATION:
# <headline>" notice in the city store to one open notice.
#
# Runs the REAL notification-wisp-reap.sh with a stubbed `gc`
# (NOTIFICATION_WISP_REAP_GC) — no live city or store. The stub answers `bd list`
# from a fixture of open city-store wisps and `rig list` from a city_path env,
# and records every `bd close` to $CALLS. core mails these notices assigned to
# "human" (fixture field), and the store refuses a close by any other actor
# without --force, so the stub models that guard: a human-assigned notice is
# recorded as closed only when the call passes --force.
# Covered:
#   (ESC)      duplicate escalation copies collapse to the NEWEST, closing the rest
#   (ESCSOLO)  a lone escalation headline is kept
#   (SCOPE)    every other message, a "Human gate awaiting you" notice among
#              them, is untouched
#   (COUNTS)   the summary counts the copies closed and the headlines kept
#   (DRYRUN)   --dry-run names the plan and closes nothing
#   (RIGLIST)  with no --db, the city store resolves from `gc rig list`
#   (UNREADABLE-LIST) a store listing that is not an array aborts (exit 1), closes 0
#   (CLOSEFAIL) a copy that will not close is reported and left for next pass
#   (HUMANGUARD) the close is forced past the store's human-assignee guard
#   (DISKFULL) a failed mktemp for the enumeration aborts (exit 1), no summary
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

mkdir -p "$TMP/bin" "$TMP/city/.beads"
export CALLS="$TMP/calls"
export WISPS_FILE="$TMP/wisps.json"
export NOTIFICATION_WISP_REAP_GC="$TMP/bin/gc"
CITY_DB="$TMP/city/.beads"

# --- gc stub ------------------------------------------------------------------
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 ${2:-}" in
  "rig list")
    jq -n --arg c "${RIG_CITY_PATH:-}" '{city_path:$c, rigs:[]}' ;;
  "bd list")
    if [ -n "${LIST_BROKEN:-}" ]; then echo "gc bd: not json here"; exit 0; fi
    cat "$WISPS_FILE" ;;
  "bd close")
    id="$3"
    case " ${CLOSE_FAILS:-} " in *" $id "*) exit 1 ;; esac
    # The store refuses a close by an actor other than the bead's assignee.
    # These notices are mailed assigned to "human" and this sweep never runs as
    # human, so a human-assigned notice closes only when the call passes --force.
    assignee="$(jq -r --arg i "$id" '.[] | select(.id==$i) | .assignee // ""' "$WISPS_FILE" 2>/dev/null)"
    if [ "$assignee" = "human" ]; then
      case " $* " in
        *" --force "*) ;;
        *) echo "cannot close $id: assignee is \"human\", actor is \"gc-toolkit.mechanik\"; reclaim or use --force to override" >&2; exit 1 ;;
      esac
    fi
    echo "$*" >> "$CALLS"; exit 0 ;;
  *) echo "gc stub: unhandled: $*" >&2; exit 3 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# --- fixtures -----------------------------------------------------------------
# The open infra beads in the city store, one array as `bd list` returns.
cat > "$WISPS_FILE" <<'JSON'
[
  {"id":"hq-n-gate",           "issue_type":"message","status":"open","assignee":"human","title":"Human gate awaiting you: ra-g1"},
  {"id":"hq-esc-1",            "issue_type":"message","status":"open","assignee":"human","title":"ESCALATION: Reaper anomalies detected [MEDIUM]","created_at":"2026-09-20T00:00:00Z"},
  {"id":"hq-esc-2",            "issue_type":"message","status":"open","assignee":"human","title":"ESCALATION: Reaper anomalies detected [MEDIUM]","created_at":"2026-09-25T00:00:00Z"},
  {"id":"hq-esc-3",            "issue_type":"message","status":"open","assignee":"human","title":"ESCALATION: Reaper anomalies detected [MEDIUM]","created_at":"2026-09-29T00:00:00Z"},
  {"id":"hq-esc-solo",         "issue_type":"message","status":"open","assignee":"human","title":"ESCALATION: Different condition [LOW]","created_at":"2026-09-28T00:00:00Z"},
  {"id":"hq-boot",             "issue_type":"message","status":"open","assignee":"human","title":"BOOT_HEALTH: deacon cold"}
]
JSON

run() { : > "$CALLS"; env "$@" bash "$SUT" --db "$CITY_DB" 2>"$TMP/err"; }

# --- MAIN pass ----------------------------------------------------------------
OUT="$(run)"; RC=$?
CALLED="$(cat "$CALLS")"
eq "$RC" "0" "MAIN: exits 0"
has "$OUT" "closed 2 duplicate escalation notices" "COUNTS: 2 escalation copies closed"
has "$OUT" "kept 2 distinct" "COUNTS: 2 distinct escalation headlines kept"
has "$CALLED" "bd close hq-esc-1" "ESC: the older escalation copy is closed"
has "$CALLED" "bd close hq-esc-2" "ESC: the middle escalation copy is closed"
hasnt "$CALLED" "bd close hq-esc-3" "ESC: the NEWEST escalation copy is kept"
has "$CALLED" "superseded by hq-esc-3" "ESC: reason names the surviving newest copy"
hasnt "$CALLED" "bd close hq-esc-solo" "ESCSOLO: a lone escalation headline is kept"
hasnt "$CALLED" "bd close hq-boot" "SCOPE: a non-escalation message is untouched"
hasnt "$CALLED" "bd close hq-n-gate" "SCOPE: a gate notice is untouched"

# The notices core mails are assigned to "human"; the stub refuses this sweep's
# close without --force (see the gc stub). A close recorded above already proves
# --force was passed, but assert it at the close site so a dropped --force is
# caught here.
has "$(grep '^bd close hq-esc-1 ' "$CALLS")" " --force" "HUMANGUARD: the duplicate-escalation close is forced past the human-assignee guard"

# --- DRY RUN ------------------------------------------------------------------
: > "$CALLS"
OUT="$(bash "$SUT" --db "$CITY_DB" --dry-run 2>/dev/null)"; RC=$?
CALLED="$(cat "$CALLS")"
eq "$RC" "0" "DRYRUN: exits 0"
has "$OUT" "would close 2 duplicate escalation notices" "DRYRUN: names the escalation plan"
eq "$CALLED" "" "DRYRUN: closes nothing"

# --- RIG LIST resolution (no --db) --------------------------------------------
: > "$CALLS"
OUT="$(RIG_CITY_PATH="$TMP/city" bash "$SUT" 2>/dev/null)"; RC=$?
eq "$RC" "0" "RIGLIST: resolves the city store from gc rig list and runs"
has "$OUT" "closed 2 duplicate escalation notices" "RIGLIST: same classification via resolved store"

# --- UNREADABLE LIST (fail closed) --------------------------------------------
: > "$CALLS"
OUT="$(LIST_BROKEN=1 bash "$SUT" --db "$CITY_DB" 2>"$TMP/err")"; RC=$?
eq "$RC" "1" "UNREADABLE-LIST: aborts with exit 1"
eq "$(cat "$CALLS")" "" "UNREADABLE-LIST: closes nothing"
has "$(cat "$TMP/err")" "could not read the city store" "UNREADABLE-LIST: says why"

# --- CLOSE FAIL ---------------------------------------------------------------
: > "$CALLS"
OUT="$(CLOSE_FAILS="hq-esc-1" bash "$SUT" --db "$CITY_DB" 2>"$TMP/err")"; RC=$?
CALLED="$(cat "$CALLS")"
eq "$RC" "0" "CLOSEFAIL: the pass exits 0"
has "$(cat "$TMP/err")" "could not close duplicate escalation notice hq-esc-1" "CLOSEFAIL: the failure is reported"
has "$CALLED" "bd close hq-esc-2" "CLOSEFAIL: a failed close does not stop the pass"
has "$OUT" "closed 1 duplicate escalation notices" "CLOSEFAIL: the failed close is not counted closed"

# --- DISK PRESSURE (fail closed) ----------------------------------------------
# The pass enumerates through a checked `mktemp`; under a full disk that mktemp
# fails and the pass must abort loud, never fall through to an all-clear summary
# (the defect: a `<<<` here-string's temp file failed silently and ran the loop
# zero times). A mktemp shim first on PATH stands in for the full disk.
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

# The enumeration cannot get a temp file: the pass aborts non-zero, prints no
# summary (no forged empty-queue all-clear), closes nothing, and says why.
: > "$MKTEMP_CTR"
OUT="$(run PATH="$TMP/diskfull-bin:$PATH" MKTEMP_CTR="$MKTEMP_CTR" REAL_MKTEMP="$REAL_MKTEMP" MKTEMP_FAIL_ON=1)"; RC=$?
eq "$RC" "1" "DISKFULL: aborts with exit 1"
eq "$OUT" "" "DISKFULL: prints no summary"
eq "$(cat "$CALLS")" "" "DISKFULL: closes nothing"
has "$(cat "$TMP/err")" "could not create a temp file to enumerate escalation notices" "DISKFULL: the blackout is announced on stderr"

echo "notification-wisp-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
