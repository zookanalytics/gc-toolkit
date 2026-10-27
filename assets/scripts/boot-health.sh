#!/usr/bin/env bash
# boot-health — is the deacon stuck? Mechanical reads, no LLM, no action.
# REPORT-ONLY BY DESIGN (2026-08-08 audit): nudging an idle deacon costs more
# than a boot cycle (~84k tokens), 4 of 5 nudges never landed (session fence
# mismatch on a fresh-wake session), and a failed nudge would let the shutdown
# dance kill a healthy deacon — the dog pool exists, but boot-health
# deliberately files no warrants. See orders/boot-health.toml.
# THE REPORT IS A FINDING, filed through patrol-finding.sh. It is not mail,
# because the operator reads the board and not the "human" mailbox, and a
# finding reaches the board through the first reaction that disposes it. One
# bead per deacon, keyed deacon-cold.<deacon>, carries every episode. A cold
# episode files or refreshes it. A fresh wisp that ends an episode which
# reported, or tried to, records the end on it (--cleared).
# PRECEDENCE: the patrol-wisp age measures WORK COMPLETED and wins;
# the pane (busy marker, movement hash with digits normalized out — timers
# advance on their own) is a FALLBACK, deciding only when the wisp ledger
# cannot be read. So the wisp is read first, and a fresh one ends the pass
# with no pane read at all; otherwise one peek both proves the deacon exists
# and supplies the pane facts.
set -euo pipefail

DEACON="${BOOT_HEALTH_DEACON:-gc-toolkit.deacon}"
# The rig whose store holds the finding: the one the deacon's own patrol files
# its findings in when no GC_RIG names another.
FINDING_RIG="${BOOT_HEALTH_RIG:-gc-toolkit}"
FINDING="${GC_PATROL_FINDING_TOOL:-$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/patrol-finding.sh}"
# The key names the situation, so each episode lands on the bead the first
# one filed for as long as that bead is live.
FINDING_KEY="deacon-cold.$(printf '%s' "$DEACON" | tr -c 'A-Za-z0-9._-' '-')"

# Thresholds. WISP_FRESH is ~2.6-3 observed deacon cycles of margin (a wisp is
# already event_timeout old when its cycle starts; max healthy age is a full
# cycle). COUPLED to mol-deacon-patrol's event_timeout — change one, re-derive
# the other, or this becomes a permanent false-positive generator.
WISP_FRESH="${BOOT_HEALTH_WISP_FRESH:-3600}"       # wisp newer than this = healthy
REPORT_AFTER="${BOOT_HEALTH_REPORT_AFTER:-1800}"   # cold this long = file the finding
REPORT_EVERY="${BOOT_HEALTH_REPORT_EVERY:-3600}"   # refresh it while the episode CONTINUES
PEEK_LINES="${BOOT_HEALTH_PEEK_LINES:-30}"

# Bounds on every gc call: `-k` adds the hard kill plain `timeout` lacks.
CALL_TIMEOUT="${BOOT_HEALTH_CALL_TIMEOUT:-15}"
KILL_AFTER="${BOOT_HEALTH_KILL_AFTER:-5}"
# The finding call makes several store reads and writes, and a first filing also
# slings its reaction, so it has its own, longer bound.
FILE_TIMEOUT="${BOOT_HEALTH_FILE_TIMEOUT:-150}"

# Busy markers: both CLIs print these while mid-turn. Held as one single-quoted
# literal, because a `}` inside ${VAR:-default} closes the expansion early.
DEFAULT_BUSY='esc to interrupt|ctrl.{0,2}c to (stop|interrupt)'
BUSY_RE="${BOOT_HEALTH_BUSY:-$DEFAULT_BUSY}"
# grep exits 2 on a pattern it rejects, and the busy test reads that as "not
# busy", so an override grep rejects gives way to the default markers.
BUSY_RC=0
grep -Eq -- "$BUSY_RE" </dev/null >/dev/null 2>&1 || BUSY_RC=$?
if [ "$BUSY_RC" -gt 1 ]; then
    echo "boot-health: BOOT_HEALTH_BUSY is not a valid ERE — using the default busy markers"
    BUSY_RE="$DEFAULT_BUSY"
fi

CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
DEFAULT_STATE_DIR="${CITY:+$CITY/.gc/runtime/packs/gc-toolkit}"

# The wisp ledger, pinned: `gc bd` ignores BEADS_DIR and an unpinned query
# reads the RIG ledger while patrol wisps live in the TOWN one.
WISP_DB="${BOOT_HEALTH_DB:-${CITY:+$CITY/.beads}}"
STATE_DIR="${BOOT_HEALTH_STATE_DIR:-${DEFAULT_STATE_DIR:-${TMPDIR:-/tmp}/gc}/boot-health}"
STATE="$STATE_DIR/state"
STATE_MAGIC='#boot-health-state-v2'

NOW="$(date +%s)"

# Recorded, not fatal: no state degrades to "never reports" (safe direction).
STATE_OK=1
mkdir -p "$STATE_DIR" 2>/dev/null || STATE_OK=0
{ [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ]; } || STATE_OK=0

# save_state removes its staging file on either failure. A signal landing
# mid-write reaches neither branch, and nothing else prunes .bh-tmp.*.
BH_TMP=""
trap 'rm -f "$BH_TMP" 2>/dev/null' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

# Bounded, exit status preserved (124 timeout / 128+n killed). CALL_TIMEOUT=0
# disables the bound (as `timeout 0` already means no limit) and drops a timeout
# fork per call: the hermetic test sets it for its instant-return reads.
# FILE_TIMEOUT=0 does the same for the finding call.
if [ "$CALL_TIMEOUT" = "0" ]; then
  gc_call_rc() { "$@"; }
else
  gc_call_rc() { timeout -k "$KILL_AFTER" "$CALL_TIMEOUT" "$@"; }
fi
if [ "$FILE_TIMEOUT" = "0" ]; then
  finding_call_rc() { "$FINDING" "$@"; }
else
  finding_call_rc() { timeout -k "$KILL_AFTER" "$FILE_TIMEOUT" "$FINDING" "$@"; }
fi

# The probe form: a failed read is an empty one (no evidence). Right for
# reads, wrong for the finding, whose exit status decides the pacing (step 7).
gc_call() { gc_call_rc "$@" 2>/dev/null || true; }

iso_of() { jq -rn --argjson s "$1" '$s | todateiso8601' 2>/dev/null; }

# --- state (a file not starting with $STATE_MAGIC is not ours) ---------------
# clear_owed=1 says the finding may hold an episode whose end it does not yet
# record: one that filed it and has ended, or one whose filing is not confirmed.
pane_hash=""; cold_since=0; last_report=0; clear_owed=0
if [ "$STATE_OK" = "1" ] && [ -f "$STATE" ] && [ "$(head -n1 "$STATE" 2>/dev/null)" = "$STATE_MAGIC" ]; then
    while IFS='=' read -r k v; do
        case "$k" in
            pane_hash)   pane_hash="$v" ;;
            cold_since)  cold_since="${v:-0}" ;;
            last_report) last_report="${v:-0}" ;;
            clear_owed)  clear_owed="${v:-0}" ;;
        esac
    done < <(tail -n +2 "$STATE" 2>/dev/null)
fi

save_state() {
    [ "$STATE_OK" = "1" ] || return 0
    local tmp
    tmp="$(mktemp "$STATE_DIR/.bh-tmp.XXXXXX" 2>/dev/null)" || return 0
    BH_TMP="$tmp"
    # shellcheck disable=SC2015  # not if-then-else: the rm is the cleanup path
    # for EITHER failure (write or install), which is exactly what is wanted.
    {
        printf '%s\n' "$STATE_MAGIC"
        printf 'pane_hash=%s\n'   "$pane_hash"
        printf 'cold_since=%s\n'  "$cold_since"
        printf 'last_report=%s\n' "$last_report"
        printf 'clear_owed=%s\n'  "$clear_owed"
    } > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    BH_TMP=""
}

# Recovery closes the episode: next coldness is a NEW episode and reports again.
# An episode that filed the finding owes it the record that the episode ended.
# Only a fresh wisp writes that record (step 2), so it stays owed until then.
clear_state() {
    if [ "$last_report" -gt 0 ]; then clear_owed=1; fi
    pane_hash="$1"; cold_since=0; last_report=0; save_state
}

# record_cleared — record on the finding that the episode has ended. Returns 0
# when the record landed, or when no live finding was left to take it.
record_cleared() {
    local msg out rc=0
    msg="$DEACON is patrolling again: newest patrol wisp updated $(iso_of "$WISP_T") (status ${WISP_STATUS:-unknown}), inside the ${WISP_FRESH}s freshness gate"
    if [ "$cold_since" -gt 0 ]; then msg="$msg; cold since $(iso_of "$cold_since")"; fi
    out="$(finding_call_rc --key "$FINDING_KEY" --scope boot-health --rig "$FINDING_RIG" \
        --cleared --message "$msg." 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "boot-health: recorded the end of the cold episode on the finding"
        printf '%s\n' "$out"
        return 0
    fi
    echo "boot-health: the end of the cold episode is NOT recorded (rc=$rc); the next fresh pass retries"
    printf '%s\n' "$out"
    return 1
}

# --- 1. patrol wisp ----------------------------------------------------------
# Three ways this query false-empties against a healthy deacon, all closed:
# --include-infra is REQUIRED (patrol wisps are issue_type=molecule, excluded
# by default); NO --status filter (a just-poured wisp is `open`;
# in_progress reports [] across the burn window; bd list already excludes
# closed rows); the STORE is pinned via --db (see WISP_DB). --limit=0 lifts
# the 50-row cap. `status` is read off the row, never filtered on.
WISP_READ_OK=0
WISPS=""
if [ -n "$WISP_DB" ]; then
    WISPS="$(gc_call gc bd list --db "$WISP_DB" --assignee="$DEACON" --type=molecule \
        --include-infra --limit=0 --json | sed -n '/^[[{]/,$p')"
    # An array (even empty) is an answer; no JSON at all is a failed read.
    printf '%s' "$WISPS" | jq -e 'type == "array"' >/dev/null 2>&1 && WISP_READ_OK=1
fi

WISP_AGE=""
WISP_STATUS=""
WISP_T=""
if [ -n "$WISPS" ]; then
    # Newest row by updated_at, carrying both fields.
    WISP_ROW="$(printf '%s' "$WISPS" | jq -r '
        [ .[]? | select((.title // "") == "mol-deacon-patrol") ]
        | sort_by(.updated_at // "") | last
        | if . == null then empty
          else ((.updated_at // "") + "\t" + (.status // "")) end' 2>/dev/null || true)"
    if [ -n "$WISP_ROW" ]; then
        NEWEST="${WISP_ROW%%$'\t'*}"
        WISP_STATUS="${WISP_ROW#*$'\t'}"
        if [ -n "$NEWEST" ]; then
            # jq reads this UTC form the same on every host; date(1) needs -d
            # on GNU and -j -f on BSD.
            T="$(jq -rn --arg t "$NEWEST" '$t | fromdateiso8601' 2>/dev/null)" || T=""
            [ -n "$T" ] && WISP_AGE=$((NOW - T)) && WISP_T="$T"
        fi
    fi
fi

# --- 2. a FRESH wisp = healthy, whatever the pane would show -----------------
# Read no pane: work completed is the answer, and no pane fact can change it.
# The stored pane hash goes with the episode, so the next pane read starts a
# new movement baseline. Work completed is also the one proof that the deacon
# is patrolling again, so this is the pass that records the end of an episode
# that reported, or tried to (step 7). A record that does not land stays owed
# to the next fresh pass.
if [ -n "$WISP_AGE" ] && [ "$WISP_AGE" -lt "$WISP_FRESH" ]; then
    if [ "$last_report" -gt 0 ]; then clear_owed=1; last_report=0; fi
    if [ "$clear_owed" = "1" ] && record_cleared; then clear_owed=0; fi
    clear_state ""            # wisp young: cycling normally, whatever its status
    exit 0
fi

# --- 3. does the deacon exist? The pane read is the answer -------------------
# An empty read means no deacon, and the controller restarts it — not our
# question; a failed read is an empty one, so it reads the same.
PANE="$(gc_call gc session peek "$DEACON" --lines "$PEEK_LINES")"
[ -n "$PANE" ] || exit 0

# --- 4. pane: reduce to two facts, DECIDE nothing here (see step 5) ----------
# Here-string, never a pipe into grep -q (SIGPIPE + pipefail reads
# a busy deacon as idle).
PANE_BUSY=0
if grep -qiE -- "$BUSY_RE" <<< "$PANE"; then PANE_BUSY=1; fi

# Digits normalized out before hashing: a bigger timer is not movement.
NEW_HASH="$(printf '%s' "$PANE" | tr -d '0-9' | cksum | awk '{print $1}')"
PANE_MOVED=0
if [ -n "$pane_hash" ] && [ "$NEW_HASH" != "$pane_hash" ]; then PANE_MOVED=1; fi

# --- 5. adjudicate a wisp that is not fresh: pane only as fallback -----------
# (a) ledger READ, wisp stale/absent: a busy pane must NOT rescue this —
#     "pane moving + no work" is the wedged-runtime signature; fall through.
# (b) ledger NOT read: no evidence about the deacon — fall back to the pane.
if [ "$WISP_READ_OK" -eq 0 ]; then
    if [ "$PANE_BUSY" -eq 1 ]; then
        clear_state ""            # mid-turn: unambiguous, and cheapest to detect
        exit 0
    fi
    if [ "$PANE_MOVED" -eq 1 ]; then
        clear_state "$NEW_HASH"   # pane advanced: producing output
        exit 0
    fi
    pane_hash="$NEW_HASH"         # static + unreadable: track movement, wait
    save_state
    exit 0
fi

# --- 6. cold -----------------------------------------------------------------
# Ledger read, wisp stale or absent, pane overridden. Start (or continue) the
# clock. A first cold pass only records — one observation is not evidence.
pane_hash="$NEW_HASH"
[ "$cold_since" -eq 0 ] && { cold_since="$NOW"; save_state; exit 0; }
COLD=$((NOW - cold_since))
[ "$COLD" -ge "$REPORT_AFTER" ] || { save_state; exit 0; }

# --- 7. report ---------------------------------------------------------------
# Once per episode, then at REPORT_EVERY while it persists, so the finding's
# finding.last_seen keeps up with a genuine wedge and a flapping deacon does
# not churn the bead.
DUE=0
[ "$last_report" -eq 0 ] && DUE=1
[ "$last_report" -gt 0 ] && [ $((NOW - last_report)) -ge "$REPORT_EVERY" ] && DUE=1
[ "$DUE" -eq 1 ] || { save_state; exit 0; }

# Report what was OBSERVED, leading with the wisp signal (the trigger); the
# pane facts are context, never the trigger. The text names instants, not
# ages, so a refresh inside one episode repeats it and the finding counts a
# recurrence without a note. A new episode or a change in the pane facts
# changes the text.
AGE_TXT="no live patrol wisp"
[ -n "$WISP_T" ] && AGE_TXT="newest patrol wisp updated $(iso_of "$WISP_T") (status ${WISP_STATUS:-unknown})"

PANE_MOVE_TXT="static"
[ "$PANE_MOVED" -eq 1 ] && PANE_MOVE_TXT="changing"
PANE_BUSY_TXT="busy marker absent"
[ "$PANE_BUSY" -eq 1 ] && PANE_BUSY_TXT="busy marker present"

COLD_ISO="$(iso_of "$cold_since")"
SUMMARY="$DEACON cold since $COLD_ISO: $AGE_TXT, past the ${WISP_FRESH}s freshness gate; pane $PANE_MOVE_TXT, $PANE_BUSY_TXT"
TITLE="$DEACON went cold: no patrol completed within boot-health's freshness gate"
MESSAGE="$SUMMARY.

boot-health, an exec order with no LLM, has seen no patrol progress from
$DEACON since $COLD_ISO. It judges coldness on the patrol-wisp signal, which
records work COMPLETED: the wisp ledger is readable, and its newest patrol wisp
is stale or absent past the freshness gate. The pane does not decide this. An
expired-login session paints a busy, moving pane while completing no work, so
the pane line below is context, not the trigger.

  patrol wisp     $AGE_TXT
  freshness gate  ${WISP_FRESH}s
  cold since      $COLD_ISO
  pane            $PANE_MOVE_TXT (digits normalized); $PANE_BUSY_TXT

boot-health does not nudge the deacon and files no warrants. Nudge delivery to
this fresh-wake session is unreliable, and a failed nudge would let the
shutdown dance kill a healthy deacon, so what to do about a cold deacon is a
decision for a person or a reaction. boot-health refreshes this finding while
the episode lasts, and records on it when a fresh patrol wisp shows the deacon
patrolling again.

To inspect (the wisp query carries no --status on purpose: a poured-but-unclaimed
wisp is 'open', and filtering on in_progress reports [] against a deacon that is
patrolling normally):
  gc session peek $DEACON --lines 50
  gc bd list --db $WISP_DB --assignee=$DEACON --type=molecule --include-infra --limit=0 --json \\
    | jq '[.[] | select(.title == \"mol-deacon-patrol\") | {id, status, updated_at}]'"

# The key dedups a filing, so a call that failed or timed out is retried on the
# next pass rather than paced: only a confirmed one sets last_report, which
# silences the next REPORT_EVERY window. A call that is not confirmed may still
# have written the finding, because the filer writes the bead before steps that
# can fail or outlast the bound, such as reading its key back or slinging its
# first reaction. So the end of the episode is owed, and saved, before the
# call. It then stays owed when the call fails or times out, and when this pass
# is killed during it. If the call wrote nothing, the record a fresh pass makes
# is still true, because the deacon is patrolling again: it lands on a live bead
# the key already holds, or finds none and records nothing. A confirmed report
# hands the debt to last_report, so it settles clear_owed, and with it any clear
# an earlier episode still owed, because the finding is live again.
clear_owed=1; save_state
FILE_RC=0
FILE_OUT="$(finding_call_rc --key "$FINDING_KEY" --scope boot-health --rig "$FINDING_RIG" \
    --priority 1 --title "$TITLE" --message "$MESSAGE" 2>&1)" || FILE_RC=$?
if [ "$FILE_RC" -eq 0 ]; then
    last_report="$NOW"; clear_owed=0
    save_state
    echo "boot-health: reported — $SUMMARY"
else
    echo "boot-health: report FAILED (rc=$FILE_RC) — retries next pass — $SUMMARY"
fi
if [ -n "$FILE_OUT" ]; then printf '%s\n' "$FILE_OUT"; fi
