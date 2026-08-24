#!/usr/bin/env bash
# boot-health — is the deacon stuck? Three mechanical reads, no LLM, no action.
# REPORT-ONLY BY DESIGN (2026-08-08 audit): nudging an idle deacon costs more
# than a boot cycle (~84k tokens), 4 of 5 nudges never landed (session fence
# mismatch on a fresh-wake session), and a failed nudge would let
# mol-shutdown-dance kill a healthy deacon — so escalation is a mail to a
# human, once per episode. Bugs lx-llzfk, lx-ody8m; see orders/boot-health.toml.
# PRECEDENCE (tk-uz3de): the patrol-wisp age measures WORK COMPLETED and wins;
# the pane (busy marker, movement hash with digits normalized out — timers
# advance on their own) is a FALLBACK, consulted only when the wisp ledger
# cannot be read.
set -euo pipefail

DEACON="${BOOT_HEALTH_DEACON:-gc-toolkit.deacon}"
REPORT_TO="${BOOT_HEALTH_REPORT_TO:-mayor/}"

# Thresholds. WISP_FRESH is ~2.6-3 observed deacon cycles of margin (a wisp is
# already event_timeout old when its cycle starts; max healthy age is a full
# cycle). COUPLED to mol-deacon-patrol's event_timeout — change one, re-derive
# the other (tk-2qa85), or this becomes a permanent false-positive generator.
WISP_FRESH="${BOOT_HEALTH_WISP_FRESH:-3600}"       # wisp newer than this = healthy
REPORT_AFTER="${BOOT_HEALTH_REPORT_AFTER:-1800}"   # cold this long = mail once
REPORT_EVERY="${BOOT_HEALTH_REPORT_EVERY:-21600}"  # re-mail a CONTINUING episode
PEEK_LINES="${BOOT_HEALTH_PEEK_LINES:-30}"

# Bounds on every gc call: `-k` adds the hard kill plain `timeout` lacks.
CALL_TIMEOUT="${BOOT_HEALTH_CALL_TIMEOUT:-15}"
KILL_AFTER="${BOOT_HEALTH_KILL_AFTER:-5}"

BUSY_RE="${BOOT_HEALTH_BUSY:-esc to interrupt|ctrl.{0,2}c to (stop|interrupt)}"

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

# Bounded, exit status PRESERVED (124 timeout / 128+n killed) — the report
# step needs the distinction.
gc_call_rc() { timeout -k "$KILL_AFTER" "$CALL_TIMEOUT" "$@"; }

# The probe form: a failed read is an empty one (no evidence). Right for
# reads, WRONG for the mail — see the three-way split in step 5.
gc_call() { gc_call_rc "$@" 2>/dev/null || true; }

# --- state (a file not starting with $STATE_MAGIC is not ours) ---------------
pane_hash=""; cold_since=0; last_report=0
if [ "$STATE_OK" = "1" ] && [ -f "$STATE" ] && [ "$(head -n1 "$STATE" 2>/dev/null)" = "$STATE_MAGIC" ]; then
    while IFS='=' read -r k v; do
        case "$k" in
            pane_hash)   pane_hash="$v" ;;
            cold_since)  cold_since="${v:-0}" ;;
            last_report) last_report="${v:-0}" ;;
        esac
    done < <(tail -n +2 "$STATE" 2>/dev/null)
fi

save_state() {
    [ "$STATE_OK" = "1" ] || return 0
    local tmp
    tmp="$(mktemp "$STATE_DIR/.bh-tmp.XXXXXX" 2>/dev/null)" || return 0
    # shellcheck disable=SC2015  # not if-then-else: the rm is the cleanup path
    # for EITHER failure (write or install), which is exactly what is wanted.
    {
        printf '%s\n' "$STATE_MAGIC"
        printf 'pane_hash=%s\n'   "$pane_hash"
        printf 'cold_since=%s\n'  "$cold_since"
        printf 'last_report=%s\n' "$last_report"
    } > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

# Recovery closes the episode: next coldness is a NEW episode and reports again.
clear_state() { pane_hash="$1"; cold_since=0; last_report=0; save_state; }

# --- 0. does the deacon exist? ----------------------------------------------
# If not, the controller restarts it. Not our question.
PANE1="$(gc_call gc session peek "$DEACON" --lines 1)"
[ -n "$PANE1" ] || exit 0

# --- 1. pane: reduce to two facts, DECIDE nothing here (see step 3) ----------
PANE="$(gc_call gc session peek "$DEACON" --lines "$PEEK_LINES")"

# Here-string, never a pipe into grep -q (tk-zfjg9: SIGPIPE + pipefail reads
# a busy deacon as idle).
PANE_BUSY=0
if grep -qiE -- "$BUSY_RE" <<< "$PANE"; then PANE_BUSY=1; fi

# Digits normalized out before hashing: a bigger timer is not movement.
NEW_HASH="$(printf '%s' "$PANE" | tr -d '0-9' | cksum | awk '{print $1}')"
PANE_MOVED=0
if [ -n "$pane_hash" ] && [ "$NEW_HASH" != "$pane_hash" ]; then PANE_MOVED=1; fi

# --- 2. patrol wisp ----------------------------------------------------------
# Three ways this query false-empties against a healthy deacon, all closed:
# --include-infra is REQUIRED (patrol wisps are issue_type=molecule, excluded
# by default — lx-ody8m); NO --status filter (a just-poured wisp is `open`;
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
            T="$(date -d "$NEWEST" +%s 2>/dev/null || echo "")"
            [ -n "$T" ] && WISP_AGE=$((NOW - T))
        fi
    fi
fi

# --- 3. adjudicate: work-completion first, pane only as fallback -------------
# (a) a FRESH wisp = healthy, whatever the pane shows (the tk-uz3de fix).
if [ -n "$WISP_AGE" ] && [ "$WISP_AGE" -lt "$WISP_FRESH" ]; then
    clear_state "$NEW_HASH"   # wisp young: cycling normally, whatever its status
    exit 0
fi

# (b) ledger READ, wisp stale/absent: a busy pane must NOT rescue this —
#     "pane moving + no work" is the wedged-runtime signature; fall through.
# (c) ledger NOT read: no evidence about the deacon — fall back to the pane.
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

# --- 4. cold -----------------------------------------------------------------
# Ledger read, wisp stale or absent, pane overridden. Start (or continue) the
# clock. A first cold pass only records — one observation is not evidence.
pane_hash="$NEW_HASH"
[ "$cold_since" -eq 0 ] && { cold_since="$NOW"; save_state; exit 0; }
COLD=$((NOW - cold_since))
[ "$COLD" -ge "$REPORT_AFTER" ] || { save_state; exit 0; }

# --- 5. report ---------------------------------------------------------------
# Once per episode, then at REPORT_EVERY while it persists, so a genuine wedge
# does not go silent after one mail and a flapping deacon does not spam.
DUE=0
[ "$last_report" -eq 0 ] && DUE=1
[ "$last_report" -gt 0 ] && [ $((NOW - last_report)) -ge "$REPORT_EVERY" ] && DUE=1
[ "$DUE" -eq 1 ] || { save_state; exit 0; }

# Report what was OBSERVED, leading with the wisp signal (the trigger); the
# pane facts are context, never the trigger.
AGE_TXT="no live patrol wisp"
[ -n "$WISP_AGE" ] && AGE_TXT="newest patrol wisp $((WISP_AGE / 60))m old (status ${WISP_STATUS:-unknown})"

PANE_MOVE_TXT="static (digits normalized)"
[ "$PANE_MOVED" -eq 1 ] && PANE_MOVE_TXT="changing (digits normalized)"
PANE_BUSY_TXT="busy marker absent"
[ "$PANE_BUSY" -eq 1 ] && PANE_BUSY_TXT="busy marker present"

SUMMARY="$DEACON cold for $((COLD / 60))m — $AGE_TXT"

# Delivery is CHECKED, not assumed: last_report silences the next window, so
# a send that never happened must not be recorded. Same three-way split as
# quota-park-nudge's escalation mail.
MAIL_RC=0
gc_call_rc gc mail send "$REPORT_TO" -s "BOOT_HEALTH: $SUMMARY" -m "boot-health (exec order, no LLM) has seen no patrol progress from $DEACON for $((COLD / 60)) minutes.

Coldness is judged on the patrol-wisp signal — work COMPLETED — not on the pane.
The wisp ledger is readable and its newest patrol wisp is stale or absent past
the freshness gate. The pane does not decide this: an expired-login session
paints a busy, moving pane while completing no work, so the pane line below is
context, not the trigger (tk-uz3de).

  patrol wisp     $AGE_TXT
  freshness gate  ${WISP_FRESH}s
  cold since      $(date -u -d "@$cold_since" '+%Y-%m-%dT%H:%M:%SZ')
  pane            $PANE_MOVE_TXT; $PANE_BUSY_TXT

This order does NOT nudge or file warrants. Escalation is deliberately a human
decision until nudge delivery to always/wake_mode=fresh sessions is trustworthy
— 4 of 5 nudges to this session failed on 'queued nudge session fence
mismatch', which would also disable mol-shutdown-dance's pardon path and let it
kill a healthy deacon. See lx-llzfk and tk-qdhnd.

To inspect (the wisp query carries no --status on purpose — a poured-but-
unclaimed wisp is 'open', and filtering on in_progress reports [] against a
deacon that is patrolling normally):
  gc session peek $DEACON --lines 50
  gc bd list --assignee=$DEACON --type=molecule --include-infra --limit=0 --json \\
    | jq '[.[] | select(.title == \"mol-deacon-patrol\") | {id, status, updated_at}]'" >/dev/null 2>&1 || MAIL_RC=$?

# save_state runs on every branch; only last_report is conditional.
if [ "$MAIL_RC" -eq 0 ]; then
    # Confirmed: seen to completion. Pace the next report off it.
    last_report="$NOW"
    save_state
    echo "boot-health: reported to $REPORT_TO — $SUMMARY"
elif [ "$MAIL_RC" -eq 124 ] || [ "$MAIL_RC" -ge 128 ]; then
    # AMBIGUOUS: paced as sent — mail is durable and a retry would duplicate.
    last_report="$NOW"
    save_state
    echo "boot-health: report UNCONFIRMED (rc=$MAIL_RC) to $REPORT_TO — paced as sent, not resent this episode — $SUMMARY"
else
    # Fast rejection: nothing delivered, nothing paced; retries next pass.
    save_state
    echo "boot-health: report FAILED (rc=$MAIL_RC) to $REPORT_TO — retries next cycle — $SUMMARY"
fi
