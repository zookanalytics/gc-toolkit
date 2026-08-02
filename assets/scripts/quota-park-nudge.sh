#!/usr/bin/env bash
# quota-park-nudge — resume agents parked at a provider quota banner.
#
# Bug tk-al95k. When a provider quota window closes mid-turn, the agent's turn
# ENDS inside the block: the session stays alive (`state=active`, `running=true`
# — the controller's liveness view sees nothing wrong), sits at an idle prompt
# under the limit banner, and has no pending work and no timer of its own to
# drive it when the window reopens. Observed twice — Claude session limits
# (2026-07-22: 1h26m of dead time *after* the block expired, two rig witnesses,
# so per-rig orphan recovery was down in both) and Codex usage limits
# (2026-08-02: ~7h30m, two review polecats holding the gc-toolkit merge queue).
# Both times a single `gc session nudge` recovered every agent within 20s.
#
# So: poll every live session's pane and nudge the ones showing a limit banner.
#
# Two rules the recurrences taught us:
#
#   1. Not provider-specific. One defect, two providers — the signature set
#      covers both wordings and is overridable ($QUOTA_PARK_MATCH) for a
#      provider we have not met yet.
#   2. Never trust the stated reset time. The Codex banner said "Aug 8th"; the
#      limit actually reset on Aug 2. Sleeping until the parsed deadline would
#      have kept those agents parked six extra days. We poll and retry on a
#      backoff instead, so recovery tracks the ACTUAL reset, not the claimed
#      one — the cost of being early is one no-op nudge.
#
# A nudge is the only action taken. Killing a quota-parked agent is wrong: the
# session is alive and correct, a fresh one hits the same block, and the
# context is lost for nothing. This never files a warrant (see the same rule in
# the deacon/witness patrols, which is where seven were filed against two live
# agents during the 2026-08-02 recurrence).
#
# Runs as an exec order (no LLM, no agent, no wisp).
# See docs/quota-park-recovery.md.
set -euo pipefail

# Lines of pane to capture, and how many of those may hold the banner. A real
# park ends with the banner: below it there is only TUI chrome (prompt box,
# status line), 6-8 lines in both CLIs. Anything further up is history — an
# agent that *mentioned* a limit and kept working. The wider capture is what
# the busy check and the escalation excerpt read.
PEEK_LINES="${QUOTA_PARK_PEEK_LINES:-20}"
TAIL_LINES="${QUOTA_PARK_TAIL_LINES:-12}"

# Provider quota banners. Anchored on the durable phrase, not the apostrophe
# (Claude and Codex both render "You've" with a typographic ' that a C-locale
# `.` will not match) and not on the reset clause (whose format differs per
# provider and, per rule 2, lies anyway).
#   Claude: "You've hit your session limit · resets 10:10am (UTC)"
#           "/usage-credits to finish what you're working on."
#   Codex:  "You've hit your usage limit... try again at Aug 8th, 2026 7:56 PM"
#
# Held in a plain variable first: an ERE interval like {0,24} inside a
# ${VAR:-default} would close the expansion at its own brace and silently ship
# a truncated pattern.
DEFAULT_MATCH='(hit|reached|exceeded) your [a-z0-9 -]{0,24}limit|(session|usage|rate) limit (reached|exceeded)|/usage-credits|limit will reset at'
MATCH_RE="${QUOTA_PARK_MATCH:-$DEFAULT_MATCH}"

# Busy markers — an agent mid-turn is not parked, whatever its pane text says.
# Both Claude Code and Codex print "esc to interrupt" while working, which is
# also what keeps an agent *reading about* this bug from being flagged.
DEFAULT_BUSY='esc to interrupt|ctrl.{0,2}c to (stop|interrupt)'
BUSY_RE="${QUOTA_PARK_BUSY:-$DEFAULT_BUSY}"

# A *quoted* banner is a citation, not a banner. Found live on the first run of
# this script: a bead-host had reported the Codex outage to the operator and
# gone idle with `▎ "You've hit your usage limit… try again at Aug 8th"` still
# on screen. Providers print their banner bare — never inside quotes, never
# under a blockquote marker — so dropping such lines costs nothing and takes
# out the whole class of agents that *write about* a quota block.
CITATION_RE='^[[:space:]]*[>▎│┃|]|["“”]'

# Retry pacing. First detection nudges immediately (an early reset is the case
# we are optimizing for); subsequent attempts back off to the cap so a genuine
# multi-day block does not nudge every cycle forever.
BACKOFF_BASE="${QUOTA_PARK_BACKOFF_BASE:-120}"
BACKOFF_CAP="${QUOTA_PARK_BACKOFF_CAP:-900}"

# Tell a human once per episode if a block outlasts this (0 disables). Deduped
# by state file: one mail per park, never one per cycle.
ESCALATE_AFTER="${QUOTA_PARK_ESCALATE_AFTER:-7200}"
ESCALATE_TO="${QUOTA_PARK_ESCALATE_TO:-mayor/}"

# Aliases never nudged (ERE, matched against the session alias). Escape hatch.
EXCLUDE_RE="${QUOTA_PARK_EXCLUDE:-}"

CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
DEFAULT_STATE_DIR="${CITY:+$CITY/.gc/runtime}"
DEFAULT_STATE_DIR="${DEFAULT_STATE_DIR:-${TMPDIR:-/tmp}/gc}/quota-park"
STATE_DIR="${QUOTA_PARK_STATE_DIR:-$DEFAULT_STATE_DIR}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

NOW="$(date +%s)"

# Read one key out of a state file. Never `source` it — the file is keyed by a
# session id and lives in a shared runtime dir.
state_get() {
    [ -f "$1" ] || return 0
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- || true
}

# True for a bare non-empty integer — everything read back out of a state file
# is fed to arithmetic, and `$(( ))` on garbage is fatal under `set -e`.
num() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }

# Seconds to wait after the Nth nudge: BASE doubled per attempt, capped.
backoff_for() {
    local n="$1" delay="$BACKOFF_BASE"
    while [ "$n" -gt 1 ] && [ "$delay" -lt "$BACKOFF_CAP" ]; do
        delay=$((delay * 2)); n=$((n - 1))
    done
    [ "$delay" -gt "$BACKOFF_CAP" ] && delay="$BACKOFF_CAP"
    echo "$delay"
}

# Human-readable duration for the log line and the escalation body.
duration() {
    local s="$1"
    if [ "$s" -lt 3600 ]; then echo "$((s / 60))m"; else echo "$((s / 3600))h$(( (s % 3600) / 60 ))m"; fi
}

# Only sessions the controller believes are alive. `attached` is skipped: a
# human is looking at that pane and can act, and injecting keys under their
# cursor is rude.
sessions=$(gc session list --json 2>/dev/null \
    | jq -r '.sessions[]? | select(.running == true and .state == "active" and (.attached // false) == false)
             | "\(.id)\t\(.alias // .session_name // .id)"' 2>/dev/null) || exit 0
[ -n "$sessions" ] || { echo "quota-park-nudge: 0 checked, 0 parked, 0 nudged"; exit 0; }

checked=0; parked=0; nudged=0

while IFS=$'\t' read -r id alias; do
    [ -n "${id:-}" ] || continue
    state="$STATE_DIR/$id"
    checked=$((checked + 1))

    pane=$(gc session peek "$id" --lines "$PEEK_LINES" 2>/dev/null) || pane=""

    # Parked = a bare provider banner at the bottom of an idle pane. Busy,
    # quiet, unreadable, cited, or scrolled-up all mean not parked. Clearing
    # the state file is what ends an episode: a recovered agent starts the
    # next block from attempt 1.
    if [ -z "$pane" ] || printf '%s\n' "$pane" | grep -qEi -- "$BUSY_RE" \
        || ! printf '%s\n' "$pane" | tail -n "$TAIL_LINES" \
            | grep -vE -- "$CITATION_RE" | grep -qEi -- "$MATCH_RE"; then
        rm -f "$state"
        continue
    fi

    parked=$((parked + 1))
    if [ -n "$EXCLUDE_RE" ] && printf '%s' "$alias" | grep -qEi -- "$EXCLUDE_RE"; then
        echo "quota-park-nudge: $alias parked (excluded, not nudged)"
        continue
    fi

    # Missing or non-numeric reads back as "start of episode" — a truncated
    # state file (crash mid-write) must not abort the sweep for every session
    # after this one, and losing an episode's counters only costs one nudge.
    first_seen="$(state_get "$state" first_seen)"; num "$first_seen" || first_seen="$NOW"
    last_nudge="$(state_get "$state" last_nudge)"; num "$last_nudge" || last_nudge=0
    attempts="$(state_get "$state" attempts)";     num "$attempts"   || attempts=0
    escalated="$(state_get "$state" escalated)"
    age=$((NOW - first_seen))

    if [ "$attempts" -gt 0 ] && [ $((NOW - last_nudge)) -lt "$(backoff_for "$attempts")" ]; then
        # Still blocked, still inside the backoff window — say nothing, wait.
        printf 'first_seen=%s\nlast_nudge=%s\nattempts=%s\nescalated=%s\n' \
            "$first_seen" "$last_nudge" "$attempts" "$escalated" > "$state"
        continue
    fi

    # The nudge text deliberately avoids every phrase in MATCH_RE: it lands in
    # the same pane we read next cycle, and a self-matching message would keep
    # the episode alive forever after the agent recovered.
    msg="Provider block may have cleared after $(duration "$age") — resume: re-check your hook (gc hook --claim --json) or continue your patrol loop. If still blocked, ignore this; it repeats until you are back."
    # `--delivery immediate` because the default (wait-idle) hands the message
    # to the runtime's idle detector — the same layer that already believes a
    # parked session is fine. We read the pane; we know it is idle. Fall back
    # to the plain form so an older gc without the flag still recovers.
    if gc session nudge --delivery immediate "$id" "$msg" >/dev/null 2>&1 \
        || gc session nudge "$id" "$msg" >/dev/null 2>&1; then
        nudged=$((nudged + 1))
        last_nudge="$NOW"
        attempts=$((attempts + 1))
        echo "quota-park-nudge: nudged $alias ($id), parked $(duration "$age"), attempt $attempts"
    else
        echo "quota-park-nudge: nudge FAILED for $alias ($id), parked $(duration "$age")"
    fi

    if [ "$ESCALATE_AFTER" -gt 0 ] && [ "$escalated" != "1" ] && [ "$age" -ge "$ESCALATE_AFTER" ]; then
        gc mail send "$ESCALATE_TO" -s "Quota-parked: $alias for $(duration "$age") [HIGH]" \
            -m "$alias ($id) has shown a provider limit banner for $(duration "$age") and has not resumed after $attempts nudge(s).

The session is alive and correct — do NOT file a warrant or kill it; a fresh
agent hits the same block and the parked one recovers by itself once the
window reopens. quota-park-nudge keeps retrying on a $((BACKOFF_CAP / 60))m cadence, so
no action is needed unless the block is unexpected (wrong account, wrong
plan, a provider outage misreported as a quota block).

Pane tail:
$(printf '%s\n' "$pane" | tail -8)" >/dev/null 2>&1 \
            && escalated=1 \
            || echo "quota-park-nudge: escalation mail FAILED for $alias ($id)"
    fi

    printf 'first_seen=%s\nlast_nudge=%s\nattempts=%s\nescalated=%s\n' \
        "$first_seen" "$last_nudge" "$attempts" "$escalated" > "$state"
done <<< "$sessions"

# A recovered agent's state file is removed above, the moment its pane goes
# clean. This only sweeps files no cycle has touched in a week — sessions that
# were closed or renamed while parked.
find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null || true

echo "quota-park-nudge: $checked checked, $parked parked, $nudged nudged"
