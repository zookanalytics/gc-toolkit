#!/usr/bin/env bash
# boot-health — is the deacon stuck? Three mechanical reads, no LLM, no action.
#
# Bugs lx-llzfk (boot spin), lx-ody8m (blind wisp query). See
# orders/boot-health.toml for why this exists.
#
# REPORT-ONLY BY DESIGN. This order observes and mails; it never nudges the
# deacon and never files a warrant. That is not timidity, it is the measured
# conclusion of the 2026-08-08 audit:
#
#   * Nudging an idle deacon forces a full context reload — ~84k tokens,
#     MORE than one boot cycle. The remedy cost more per unit than the disease.
#   * 4 of boot's 5 nudges over 14 days never landed at all ("queued nudge
#     session fence mismatch"): the deacon is mode=always/wake_mode=fresh and
#     recycles every ~4.6 min, so the fence moves out from under a queued nudge.
#   * mol-shutdown-dance decides an agent is dead when it does not answer a
#     nudge with ALIVE. Against this target the NUDGE is what fails, so the
#     pardon path cannot fire and the dance would proceed to kill a healthy
#     deacon. Boot itself warned about that class of bogus warrant in tk-qdhnd
#     (2026-07-28, still open).
#
# So escalation waits on trustworthy nudge delivery. Until then a human in the
# loop is the correct escalation, and a mail costs nothing. Re-arming the
# warrant path is tracked separately — do not add it back here without first
# checking the nudge wisp reaches state != failed.
#
# ON HASHING THE PANE. Claude Code paints a post-turn duration ("✻ 2m") that
# advances on its own, so a byte-exact hash reports "changed" every cycle and
# the detector would never fire — failing safe, but useless. Digits are
# normalized out before hashing: real work writes new TEXT, not just larger
# numbers. A pane whose only change is numeric correctly reads as static.
set -euo pipefail

DEACON="${BOOT_HEALTH_DEACON:-gc-toolkit.deacon}"
REPORT_TO="${BOOT_HEALTH_REPORT_TO:-mayor/}"

# Thresholds. The deacon's exponential backoff caps at 300s and it cycles every
# ~4.6 min in practice, so WISP_FRESH is ~3 cycles of margin. Being wrong here
# only costs a mail, but a detector that cries wolf gets ignored.
WISP_FRESH="${BOOT_HEALTH_WISP_FRESH:-900}"        # wisp newer than this = healthy
REPORT_AFTER="${BOOT_HEALTH_REPORT_AFTER:-1800}"   # cold this long = mail once
REPORT_EVERY="${BOOT_HEALTH_REPORT_EVERY:-21600}"  # re-mail a CONTINUING episode
PEEK_LINES="${BOOT_HEALTH_PEEK_LINES:-30}"

# Every probe goes through the runtime or Dolt — the two layers most likely to
# be wedged during exactly the incident this order exists to catch. Unbounded,
# one hung `gc` call strands the pass. `-k` adds the hard kill: plain `timeout`
# only signals, and a wedged process is the one least able to answer politely.
CALL_TIMEOUT="${BOOT_HEALTH_CALL_TIMEOUT:-15}"
KILL_AFTER="${BOOT_HEALTH_KILL_AFTER:-5}"

BUSY_RE="${BOOT_HEALTH_BUSY:-esc to interrupt|ctrl.{0,2}c to (stop|interrupt)}"

CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
DEFAULT_STATE_DIR="${CITY:+$CITY/.gc/runtime/packs/gc-toolkit}"

# WHICH LEDGER the wisp query runs against, pinned explicitly — see step 2.
# `gc bd` resolves its store from the invoking rig and ignores BEADS_DIR, so an
# unpinned query reads the RIG ledger while the deacon's patrol wisps live in the
# TOWN one. Overridable so the hermetic test can pin a fake.
WISP_DB="${BOOT_HEALTH_DB:-${CITY:+$CITY/.beads}}"
STATE_DIR="${BOOT_HEALTH_STATE_DIR:-${DEFAULT_STATE_DIR:-${TMPDIR:-/tmp}/gc}/boot-health}"
STATE="$STATE_DIR/state"
STATE_MAGIC='#boot-health-state-v2'

NOW="$(date +%s)"

# Recorded, not fatal. No state means no memory across cycles, which degrades
# this to "never reports" rather than "reports every pass" — the safe direction.
STATE_OK=1
mkdir -p "$STATE_DIR" 2>/dev/null || STATE_OK=0
{ [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ]; } || STATE_OK=0

# Bounded, with the exit status PRESERVED. Expiry is a non-zero rc — 124 for the
# timeout, 128+n where the hard kill lands first (137 on the hosts tested) — so a
# caller can tell a call that wedged mid-flight from one that was refused
# outright. The report step needs that distinction; the probes do not.
gc_call_rc() { timeout -k "$KILL_AFTER" "$CALL_TIMEOUT" "$@"; }

# The probe form. Output IS the answer for a read, and a failed read is an empty
# one — which every caller below already treats as "no evidence" (absent pane, no
# wisps). Swallowing the status is right for a read and WRONG for the mail: the
# report is the only thing this order produces, so a send that failed must never
# be recorded as one that landed. See the three-way split in step 4.
gc_call() { gc_call_rc "$@" 2>/dev/null || true; }

# --- state ------------------------------------------------------------------
# A file whose first line is not exactly $STATE_MAGIC is not ours: not read,
# not written over. STATE_DIR sits in the shared city runtime tree.
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

# --- 1. pane -----------------------------------------------------------------
PANE="$(gc_call gc session peek "$DEACON" --lines "$PEEK_LINES")"

if printf '%s' "$PANE" | grep -qiE "$BUSY_RE"; then
    clear_state ""            # mid-turn: unambiguous, and cheapest to detect
    exit 0
fi

NEW_HASH="$(printf '%s' "$PANE" | tr -d '0-9' | cksum | awk '{print $1}')"
if [ -n "$pane_hash" ] && [ "$NEW_HASH" != "$pane_hash" ]; then
    clear_state "$NEW_HASH"   # pane advanced: producing output
    exit 0
fi

# --- 2. patrol wisp ----------------------------------------------------------
# TWO filters false-empty this query against a perfectly healthy deacon, and it
# has to survive both. An empty result is this detector's failure mode, so every
# clause here is chosen to widen, never to narrow.
#
#   * --include-infra is REQUIRED (lx-ody8m): patrol wisps are issue_type
#     molecule, which `bd list` excludes by default, so without it this query
#     returns [] on every pass even while the deacon holds a live wisp. Verified
#     2026-08-08: with the flag, lx-wisp-j4mqh; without it, 0 rows. That is the
#     defect that made boot's freshness signal dead for its entire service life.
#   * NO --status filter, equally REQUIRED: a just-poured wisp is `open` until
#     the deacon claims it, and the deacon burns the previous wisp BEFORE
#     claiming the next, so --status=in_progress reports [] across that window.
#     Reproduced against the live deacon 2026-08-09, mid-patrol both times:
#     05:01:45Z lx-wisp-tzmo in_progress; 05:06:25Z lx-wisp-222j OPEN, where
#     --status=in_progress returned [] and this form returned the row.
#     Dropping the filter does NOT drag in patrol history: `bd list` already
#     excludes closed rows unless you pass --all (checked against the live
#     store — two burned wisps, invisible here, visible with --all), so this
#     widens to live rows only.
#
# --type=molecule plus the title match keep the result to patrol wisps, and
# --limit=0 lifts the default 50-row cap so nothing else the deacon holds can
# crowd the wisp out — a capped query goes dead silently, under load only, which
# is exactly when this detector matters most.
#
# `status` is read off the row, never filtered on: `open` (poured, not yet
# claimed) and `in_progress` (claimed and cooking) are both healthy. `updated_at`
# is the freshness signal; status is context for the human reading the report.
#   * The STORE must be pinned, and that is a third false-empty from a third
#     direction. `gc bd` resolves its ledger from the invoking RIG and ignores
#     BEADS_DIR, so an unpinned query reads the rig ledger (tk-*) while the
#     deacon's patrol wisps live in the town ledger (lx-*) — [] on every pass,
#     from a query whose flags are all correct. Measured 2026-08-09T06:24Z
#     against the live city: unpinned -> [], `--db $CITY/.beads` -> lx-wisp-koog
#     in_progress. Until this was pinned the probe had never once seen a wisp,
#     and only the pane-changed signal kept the detector from crying wolf.
WISP_READ_OK=0
WISPS=""
if [ -n "$WISP_DB" ]; then
    WISPS="$(gc_call gc bd list --db "$WISP_DB" --assignee="$DEACON" --type=molecule \
        --include-infra --limit=0 --json | sed -n '/^[[{]/,$p')"
    # A well-formed array — even an EMPTY one — is an answer, and an empty answer
    # is real evidence that no wisp is live. No JSON at all is NOT: the call
    # failed, timed out, or was misdirected. Telling those apart is the whole
    # point, because they were previously identical and both read as "wedged".
    printf '%s' "$WISPS" | jq -e 'type == "array"' >/dev/null 2>&1 && WISP_READ_OK=1
fi

WISP_AGE=""
WISP_STATUS=""
if [ -n "$WISPS" ]; then
    # One row — newest by updated_at — carrying both fields, so the status
    # reported is the status of the timestamp being judged.
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

if [ -n "$WISP_AGE" ] && [ "$WISP_AGE" -lt "$WISP_FRESH" ]; then
    clear_state "$NEW_HASH"   # wisp young: cycling normally, whatever its status
    exit 0
fi

# The probe could not be READ — no ledger to pin, or no parseable answer from
# one. That is not evidence about the deacon, and reporting it as coldness is
# the cry-wolf failure this order exists to avoid: a detector that reports on
# evidence it never gathered gets ignored, which costs more than no detector.
# Record the pane so movement is still tracked, and wait for a readable pass.
if [ "$WISP_READ_OK" -eq 0 ]; then
    pane_hash="$NEW_HASH"
    save_state
    exit 0
fi

# --- 3. cold -----------------------------------------------------------------
# Pane static, no busy marker, wisp stale or absent. Start (or continue) the
# clock. A first cold pass only records — one observation is not evidence.
pane_hash="$NEW_HASH"
[ "$cold_since" -eq 0 ] && { cold_since="$NOW"; save_state; exit 0; }
COLD=$((NOW - cold_since))
[ "$COLD" -ge "$REPORT_AFTER" ] || { save_state; exit 0; }

# --- 4. report ---------------------------------------------------------------
# Once per episode, then at REPORT_EVERY while it persists, so a genuine wedge
# does not go silent after one mail and a flapping deacon does not spam.
DUE=0
[ "$last_report" -eq 0 ] && DUE=1
[ "$last_report" -gt 0 ] && [ $((NOW - last_report)) -ge "$REPORT_EVERY" ] && DUE=1
[ "$DUE" -eq 1 ] || { save_state; exit 0; }

# Report what was actually observed. The query constrains no status, so saying
# "no in_progress wisp" would assert something this pass never asked.
AGE_TXT="no live patrol wisp"
[ -n "$WISP_AGE" ] && AGE_TXT="newest patrol wisp $((WISP_AGE / 60))m old (status ${WISP_STATUS:-unknown})"

SUMMARY="$DEACON cold for $((COLD / 60))m — no pane change, $AGE_TXT"

# Delivery is CHECKED, not assumed. `last_report` is what silences the next
# REPORT_EVERY (default 6h) window, so recording a send that never happened
# suppresses the only alert this order produces — and it does that during
# precisely the wedged-runtime incident the order exists to catch. Three
# outcomes, the same split quota-park-nudge draws around its escalation mail.
MAIL_RC=0
gc_call_rc gc mail send "$REPORT_TO" -s "BOOT_HEALTH: $SUMMARY" -m "boot-health (exec order, no LLM) has seen $DEACON static for $((COLD / 60)) minutes.

  pane            unchanged since $(date -u -d "@$cold_since" '+%Y-%m-%dT%H:%M:%SZ') (digits normalized)
  busy marker     absent
  patrol wisp     $AGE_TXT
  freshness gate  ${WISP_FRESH}s

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

# `save_state` runs on every branch regardless: pane_hash and cold_since are the
# episode's memory and are already updated by step 3. Only `last_report` — the
# pacing clock — is conditional, because only it claims a mail went out.
if [ "$MAIL_RC" -eq 0 ]; then
    # Confirmed: seen to completion. Pace the next report off it.
    last_report="$NOW"
    save_state
    echo "boot-health: reported to $REPORT_TO — $SUMMARY"
elif [ "$MAIL_RC" -eq 124 ] || [ "$MAIL_RC" -ge 128 ]; then
    # AMBIGUOUS, and deliberately paced as sent. `gc mail send` writes durable
    # mail through Dolt, so a bound that expires after the write commits leaves a
    # mail in the recipient's inbox that this script never heard about. Retrying
    # would send a second one for the same episode, during exactly the slow-
    # runtime incident this order has to tolerate. Recorded, and said out loud as
    # unconfirmed so the operator knows the pacing rests on a guess.
    last_report="$NOW"
    save_state
    echo "boot-health: report UNCONFIRMED (rc=$MAIL_RC) to $REPORT_TO — paced as sent, not resent this episode — $SUMMARY"
else
    # A fast rejection: nothing was delivered, so nothing is paced. `last_report`
    # is left exactly as it was, which keeps this episode DUE and retries on the
    # next 2m pass — and unlike the ambiguous case, that retry cannot duplicate.
    save_state
    echo "boot-health: report FAILED (rc=$MAIL_RC) to $REPORT_TO — retries next cycle — $SUMMARY"
fi
