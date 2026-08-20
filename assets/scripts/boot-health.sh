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
#
# ON PRECEDENCE (tk-uz3de). The patrol-wisp age is the only signal here that
# measures WORK COMPLETED rather than the pane's appearance, so it wins. When
# the wisp ledger is readable, a stale or absent wisp opens a coldness episode
# even if the pane looks busy or is animating — because an expired-login session
# paints a busy, moving pane while completing no work, and the pane reads (busy
# marker, pane movement) used to exit "healthy" BEFORE the wisp was ever
# consulted. That false-negatived a 3h51m deacon stall across ~105 passes. The
# pane is now a FALLBACK, consulted only when the wisp cannot be read.
set -euo pipefail

DEACON="${BOOT_HEALTH_DEACON:-gc-toolkit.deacon}"
REPORT_TO="${BOOT_HEALTH_REPORT_TO:-mayor/}"

# Thresholds. WISP_FRESH is ~3 cycles of margin. Being wrong here only costs a
# mail, but a detector that cries wolf gets ignored, so the margin is generous
# by design.
#
# Raised 900 -> 3600 with mol-deacon-patrol's event_timeout 60 -> 600 (tk-2qa85).
# The bound that matters is the MAXIMUM AGE the live wisp reaches, not the cycle
# time: next-iteration pours the next wisp BEFORE the wait, so a wisp is already
# `event_timeout` old when the cycle it belongs to starts, and it stays live
# until the following pour. Max age is therefore a full cycle — wait + work.
# Sampled 2026-08-20 on the live deacon (consecutive live wisps, ignoring the
# leaked ones, which are not cycle markers): 679 s and 839 s at the old 60 s
# wait, i.e. ~620-780 s of work. At a 600 s wait that is ~1220-1380 s, so the
# old 900 s bar would have read a perfectly healthy deacon as cold on nearly
# every cycle. 3600 restores ~2.6-3 cycles of margin. Size this off the LONGER
# observed cycle: under-margining here mails the mayor, over-margining only
# delays a report the REPORT_AFTER dwell already delays.
#
# This threshold is coupled to that formula var: change one and re-derive the
# other, or this order becomes a permanent false-positive generator.
WISP_FRESH="${BOOT_HEALTH_WISP_FRESH:-3600}"       # wisp newer than this = healthy
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
# Read the pane and reduce it to two facts, but DECIDE nothing here. The old
# code exited "healthy" the instant the pane looked busy or had moved — before
# it ever asked whether any work had completed. That is the defect (tk-uz3de):
# an expired-login session paints a busy, animating pane while completing
# nothing. Precedence is inverted in step 3; the pane is now a FALLBACK.
PANE="$(gc_call gc session peek "$DEACON" --lines "$PEEK_LINES")"

# A here-string, never a `printf ... | grep -qiE` pipeline (tk-zfjg9): `grep -q`
# exits at its first match and SIGPIPEs the writer, which `pipefail` promotes to
# 141 — so a busy deacon reads as idle and the pass goes on to open a coldness
# episode against a session that is mid-turn. $PANE is PEEK_LINES of pane text,
# comfortably past the buffer size where the race starts to fire.
PANE_BUSY=0
if grep -qiE -- "$BUSY_RE" <<< "$PANE"; then PANE_BUSY=1; fi

# Digits are normalized out before hashing (see "ON HASHING THE PANE" above): a
# pane whose only change is a larger timer reads as static, while a cycling
# spinner glyph or a new action word reads as moved.
NEW_HASH="$(printf '%s' "$PANE" | tr -d '0-9' | cksum | awk '{print $1}')"
PANE_MOVED=0
if [ -n "$pane_hash" ] && [ "$NEW_HASH" != "$pane_hash" ]; then PANE_MOVED=1; fi

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

# --- 3. adjudicate: work-completion first, pane only as fallback -------------
# The wisp age measures WORK COMPLETED, not pixels painted, so when it can be
# read it is authoritative and the pane defers to it. This ordering is the fix
# for tk-uz3de: the pane reads used to run FIRST and exit healthy on a busy or
# advancing pane — exactly what an expired-login session paints while doing no
# work — so the stale-wisp signal below was never reached.

# (a) A FRESH wisp is the strongest healthy signal: a patrol completed inside
#     the freshness window. Healthy whatever the pane shows.
if [ -n "$WISP_AGE" ] && [ "$WISP_AGE" -lt "$WISP_FRESH" ]; then
    clear_state "$NEW_HASH"   # wisp young: cycling normally, whatever its status
    exit 0
fi

# (b) Ledger READ, wisp stale or absent: no patrol completed in the window. A
#     busy-looking or animating pane must NOT rescue this — "pane moving + no
#     work in 30m" is the wedged-runtime signature, not health. Fall through to
#     the coldness clock (step 4) REGARDLESS of the pane. This is the inversion.
# (c) Ledger NOT read — no store to pin, or no parseable answer. That is not
#     evidence about the deacon, and reporting coldness on evidence never
#     gathered is the cry-wolf failure this order exists to avoid. Fall back to
#     the pane exactly as the pre-inversion code did: a busy or advancing pane
#     reads as alive; a static one records movement and waits for a readable
#     pass.
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

# Report what was actually observed. Coldness is judged on the patrol-wisp
# signal (step 3), so the report LEADS with it. The pane no longer decides
# anything here, so it is reported as OBSERVED rather than assumed static: the
# old text hardcoded "no pane change" / "static" / "busy marker absent", every
# one of which is false for the wedge this fix exists to catch — an expired-login
# session paints a busy, moving pane while completing no work (tk-uz3de). The
# query constrains no status, so the summary names the wisp signal and asserts
# nothing this pass never asked.
AGE_TXT="no live patrol wisp"
[ -n "$WISP_AGE" ] && AGE_TXT="newest patrol wisp $((WISP_AGE / 60))m old (status ${WISP_STATUS:-unknown})"

# Two independent pane facts, each reported as observed — neither is the trigger.
# Digits are normalized out before the movement hash (see "ON HASHING THE PANE"),
# so a numeric-only change reads as static.
PANE_MOVE_TXT="static (digits normalized)"
[ "$PANE_MOVED" -eq 1 ] && PANE_MOVE_TXT="changing (digits normalized)"
PANE_BUSY_TXT="busy marker absent"
[ "$PANE_BUSY" -eq 1 ] && PANE_BUSY_TXT="busy marker present"

SUMMARY="$DEACON cold for $((COLD / 60))m — $AGE_TXT"

# Delivery is CHECKED, not assumed. `last_report` is what silences the next
# REPORT_EVERY (default 6h) window, so recording a send that never happened
# suppresses the only alert this order produces — and it does that during
# precisely the wedged-runtime incident the order exists to catch. Three
# outcomes, the same split quota-park-nudge draws around its escalation mail.
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
