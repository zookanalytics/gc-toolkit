#!/usr/bin/env bash
# quota-park-nudge — resume agents parked at a provider quota banner.
#
# Bug tk-al95k. When a provider quota window closes mid-turn, the agent's turn
# ENDS inside the block: the session stays alive (`state=active` — the
# controller's liveness view sees nothing wrong), sits at an idle prompt under
# the limit banner, and has no pending work and no timer of its own to drive it
# when the window reopens. Observed twice — Claude session limits
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
#   2. Do not gate recovery on the stated reset time. Quota can come back by a
#      route no banner predicts: on 2026-08-02 the Codex banner said "Aug 8th"
#      and was probably right about the natural window, but the operator
#      triggered a manual reset on Aug 2 — sleeping until the parsed deadline
#      would have kept those agents parked six extra days (bead correction,
#      mayor, 2026-08-02T16:35Z). The banner time is a lower bound worth
#      knowing, never an authority, so this polls instead of scheduling. Being
#      early costs one no-op nudge; being late costs a day of throughput.
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
# the busy check reads.
PEEK_LINES="${QUOTA_PARK_PEEK_LINES:-20}"
TAIL_LINES="${QUOTA_PARK_TAIL_LINES:-12}"

# Provider quota banners. Anchored on the durable phrase, not the apostrophe
# (Claude and Codex both render "You've" with a typographic ' that a C-locale
# `.` will not match) and not on the reset clause (per-provider format, and
# per rule 2 nothing here acts on it).
#   Claude: "You've hit your session limit · resets 10:10am (UTC)"
#           "Claude usage limit reached · resets 3pm"
#           "/usage-credits to finish what you're working on."
#   Codex:  "You've hit your usage limit... try again at Aug 8th, 2026 7:56 PM"
#
# Every alternative is anchored to something only a PROVIDER says: the
# user-possessive "your … limit", or a named provider/plan in front of it. The
# subject is load-bearing — an earlier draft carried a bare
# `(session|usage|rate) limit (reached|exceeded)`, which mechanically matches an
# ordinary idle tool error like "Error: API rate limit exceeded". That pane is
# not a quota park, and nudging it on the recovery cadence is noise against a
# session that is working fine. A provider we have not met goes in
# $QUOTA_PARK_MATCH (or extends this list) rather than back into a bare form.
#
# The reset-clause alternative carries the same possessive anchor for the same
# reason, and it is the second time that lesson has been paid for: the bare
# `limit will reset at` it replaces survived the round that tightened the other
# subject-less alternative, and matched `Error: API rate limit will reset at
# 18:00 UTC.` on an idle pane — a working session, nudged every cycle. A
# provider saying it says "your … limit will reset at"; a tool error does not.
# Nothing here reads the time itself (rule 2 above) — the clause is only ever
# evidence that the line is a banner.
#
# Held in a plain variable first: an ERE interval like {0,24} inside a
# ${VAR:-default} would close the expansion at its own brace and silently ship
# a truncated pattern.
DEFAULT_MATCH='(hit|reached|exceeded) your [a-z0-9 -]{0,24}limit|(claude|codex|chatgpt|openai|anthropic|gemini|weekly|5-hour|plan) [a-z0-9 -]{0,16}limit (reached|exceeded)|/usage-credits|your [a-z0-9 -]{0,24}limit will reset'
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
# Alternation, not a bracket expression: a multibyte character inside [...] is
# a byte set under a C locale, and the order's env is not guaranteed to be
# UTF-8. Spelled out this way each marker matches as an exact sequence in both.
CITATION_RE='^[[:space:]]*(>|\||▎|│|┃)|"|“|”'

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

# Wall-clock bounds. The order runner applies no timeout of its own, and every
# probe here goes through the runtime (and, for the escalation, Dolt) — the two
# layers most likely to be wedged during the incidents this order exists to
# recover from. Unbounded, one hung `gc session peek` strands every session
# BEHIND it in the sweep: the parked agents we most need to reach are exactly
# the ones we would never inspect. CALL_TIMEOUT bounds each call so a wedged
# one is skipped rather than fatal; SWEEP_BUDGET bounds the whole pass so a
# city-sized session list of slow calls cannot overrun the next 3m cycle. 0
# disables either bound.
CALL_TIMEOUT="${QUOTA_PARK_CALL_TIMEOUT:-15}"
SWEEP_BUDGET="${QUOTA_PARK_SWEEP_BUDGET:-120}"

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

# One writer for an episode's state file, so the two paths that persist it —
# inside the backoff window, and after a delivery attempt — cannot drift in
# which counters they carry. Positional: path, first_seen, last_nudge, last_try,
# attempts, unconfirmed, escalated.
write_state() {
    printf 'first_seen=%s\nlast_nudge=%s\nlast_try=%s\nattempts=%s\nunconfirmed=%s\nescalated=%s\n' \
        "$2" "$3" "$4" "$5" "$6" "$7" > "$1"
}

# True for a session id safe to use as a filename. The id names a state file in
# a shared runtime directory and is pasted into the operator instruction in the
# escalation mail, so it must be a bare token: no separator, no dot-segment,
# nothing that can leave STATE_DIR. Runtime ids look like `lx-gsnfk`; an id that
# does not is not one, and a session we cannot name safely is one we skip rather
# than guess at. (`.*` rejects a leading dot, `*..*` any dot-segment, and `/` is
# absent from the allowed set — together that is every route out of the dir.)
safe_id() { case "${1:-}" in '' | *[!A-Za-z0-9._-]* | .* | *..*) return 1 ;; *) return 0 ;; esac }

# Bound and flatten a display field before it is logged or mailed. Session
# alias/session_name are mutable and agent-reachable, and they reach durable
# mayor mail — the same channel detector_class exists to keep pane text out of.
# Keeping the pane out while interpolating the alias raw just moves the hole one
# field over: an alias is enough room for a line of forged operator context.
# Allowlist to printable identifier characters, then truncate.
sanitize_display() {
    local s
    s="$(printf '%s' "${1:-}" | LC_ALL=C tr -c 'A-Za-z0-9._@:/ -' '?')"
    printf '%s' "${s:0:64}"
}

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

# The lines of a pane a banner may legitimately sit on: the tail window, minus
# citations. Both the park test and the detector class read the same set — a
# second copy of this filter chain would drift out of agreement with the test
# that decides whether a session is parked at all.
banner_candidates() {
    printf '%s\n' "$1" | tail -n "$TAIL_LINES" | grep -vE -- "$CITATION_RE" || true
}

# Which family of banner matched, as a label from a CLOSED set. This is the
# only thing the escalation mail says about what was on screen.
#
# The pane is untrusted. It holds whatever the agent printed, and an agent can
# print text shaped like an operator directive; mail is durable and the mayor
# reads it as an authenticated channel. An excerpt of the pane in the body
# therefore launders attacker-reachable text into that channel, which is what
# the earlier version of this escalation did by mailing the last 8 lines. The
# body now carries only alias, id, age, attempts, and this label — every one of
# them from the session list or this script's own state file, and the two that
# come from the session list are constrained before they are interpolated: the
# id by safe_id, the alias by sanitize_display. Session display metadata is
# mutable too, so keeping the pane out while pasting the alias raw would only
# move the hole into a shorter field.
#
# Deliberately coarse, and independent of DEFAULT_MATCH's exact alternatives:
# the label has to survive that pattern being extended or overridden, and
# falling through to the generic form costs a human nothing. What it must never
# do is emit a byte of pane text. Classified over only the lines that actually
# matched, so an unrelated line in the tail cannot pick the label.
detector_class() {
    local lines
    lines="$(banner_candidates "$1" | grep -Ei -- "$MATCH_RE" || true)"
    if [ -n "${QUOTA_PARK_MATCH:-}" ]; then
        echo "custom-match"
    elif printf '%s\n' "$lines" | grep -qEi -- 'your [a-z0-9 -]{0,24}limit'; then
        echo "possessive-limit"
    elif printf '%s\n' "$lines" | grep -qEi -- '(claude|codex|chatgpt|openai|anthropic|gemini|weekly|5-hour|plan) [a-z0-9 -]{0,16}limit'; then
        echo "named-provider-limit"
    elif printf '%s\n' "$lines" | grep -qEi -- '/usage-credits'; then
        echo "usage-credits"
    else
        echo "provider-limit"
    fi
}

# Every numeric knob is fed to `$(( ))`, to `[ -gt ]`, to `tail -n`, or to
# `timeout` itself, so a non-numeric override (a stray "15s", an empty string
# from a templated env) breaks quota recovery city-wide from a single typo in a
# tuning knob. Fall back to the default instead — validated here, in one place
# ahead of the sweep, because the failure is silent in a different way for each
# knob and none of them announce it:
#   BACKOFF_BASE/_CAP   -> `[: oops: integer expression expected` inside
#                          backoff_for, whose non-zero rc reads as "window
#                          elapsed" — backoff bypassed, every cycle nudges.
#   ESCALATE_AFTER      -> the `-gt 0` guard errors, i.e. reads as disabled: no
#                          human is ever told about a park that outlasts it.
#   PEEK_LINES/TAIL_LINES -> `tail -n x` errors, banner_candidates yields
#                          nothing, and NO session is ever detected as parked.
# An earlier version validated only the two bounds below, which is how
# QUOTA_PARK_BACKOFF_BASE=oops reached the arithmetic at all.
#
# Each knob also carries a FLOOR, because "is an integer" was never the whole
# contract: zero is a perfectly good integer that quietly defeats recovery
# everywhere it is not documented as an off switch. `TAIL_LINES=0` makes
# `tail -n 0` print nothing, so no session is ever detected as parked;
# `PEEK_LINES=0` empties every pane, which the sweep reads as unreadable;
# `BACKOFF_BASE=0` or `BACKOFF_CAP=0` collapses the retry window to zero and
# nudges every parked pane on every 3m sweep, forever. Zero is reserved as
# "disable" for exactly the three knobs the docs say it is — CALL_TIMEOUT
# (unbounded calls), SWEEP_BUDGET (no per-pass budget), ESCALATE_AFTER (never
# mail a human) — and those keep floor 0. Everywhere else it is a typo with the
# same blast radius as "oops", and is treated the same way.
num_min() { num "${1:-}" && [ "$1" -ge "$2" ]; }
num_min "$CALL_TIMEOUT"   0 || CALL_TIMEOUT=15
num_min "$SWEEP_BUDGET"   0 || SWEEP_BUDGET=120
num_min "$ESCALATE_AFTER" 0 || ESCALATE_AFTER=7200
num_min "$BACKOFF_BASE"   1 || BACKOFF_BASE=120
num_min "$BACKOFF_CAP"    1 || BACKOFF_CAP=900
num_min "$PEEK_LINES"     1 || PEEK_LINES=20
num_min "$TAIL_LINES"     1 || TAIL_LINES=12

# Every `gc` call goes through here. Two things it guarantees:
#
#   1. A bound (CALL_TIMEOUT). `timeout` exits 124 on expiry — a non-zero rc, so
#      a wedged call lands in the caller's existing failure branch (empty pane,
#      failed nudge) instead of hanging the sweep. Same idiom and env-override
#      shape as merge-skill.sh's run_bounded. No coreutils `timeout` (some macOS
#      hosts) degrades to an unbounded call rather than dropping the probe:
#      skipping every call would silently disable recovery on such a host.
#   2. stdin CLOSED. The session loop below reads its work list from a
#      here-string on fd 0; a child that inherited and consumed it would
#      truncate the sweep — sessions would vanish from the run rather than fail.
run_bounded() {
    if [ "$CALL_TIMEOUT" -gt 0 ] && command -v timeout >/dev/null 2>&1; then
        timeout "$CALL_TIMEOUT" "$@" </dev/null
    else
        "$@" </dev/null
    fi
}

# True once the pass has run longer than SWEEP_BUDGET (0 = no budget). Checked
# per session so a slow sweep stops at a session boundary, with its state files
# consistent, instead of overrunning into the next cycle.
sweep_expired() {
    [ "$SWEEP_BUDGET" -gt 0 ] || return 1
    [ "$(( $(date +%s) - NOW ))" -ge "$SWEEP_BUDGET" ]
}

# Only sessions the controller believes are alive. Keyed on `.state`, NEVER on
# `.running`: running is null for an active session during controller churn, so
# a `.running == true` filter drops exactly the live sessions it is meant to
# select — and a quota-parked one in that state would never be peeked at all.
# The same rule is already load-bearing in the helm's owner-liveness join
# (assets/scripts/gc-helm.sh, with a running:null case in
# tools/helm-surface-fixture.sh). `attached` is skipped: a human is looking at
# that pane and can act, and injecting keys under their cursor is rude.
#
# `@tsv`, not an interpolated "\(.id)\t\(.alias)": jq escapes tab, newline,
# carriage return and backslash inside @tsv fields, so one session is always
# exactly one record. Interpolated, they pass through raw and mutable session
# metadata can forge a row — an alias holding a newline followed by
# `../escaped-state` produced a second row whose "id" was that path, and the
# state file built from it was written outside STATE_DIR. Encoding here and
# validating with safe_id below are the two halves of that fix: the encoding
# stops a field from becoming a record, the validation stops a record from
# becoming a path.
sessions=$(run_bounded gc session list --json 2>/dev/null \
    | jq -r '.sessions[]? | select(.state == "active" and (.attached // false) == false)
             | [.id, (.alias // .session_name // .id)] | @tsv' 2>/dev/null) || exit 0
[ -n "$sessions" ] || { echo "quota-park-nudge: 0 checked, 0 parked, 0 nudged"; exit 0; }

checked=0; parked=0; nudged=0; skipped=0; unreadable=0; rejected=0; unconfirmed_now=0

while IFS=$'\t' read -r id alias; do
    [ -n "${id:-}" ] || continue
    # An id we cannot safely use as a filename is one we do not touch at all —
    # not peeked, not nudged, no state written. Counted, not silent: a session
    # this order refuses to inspect is a gap in city-wide coverage.
    if ! safe_id "$id"; then rejected=$((rejected + 1)); continue; fi
    # Out of budget: leave the rest for the next cycle (3m away) rather than
    # overlapping it. Counted so the summary says so instead of silently
    # reporting a short sweep as a complete one.
    if sweep_expired; then skipped=$((skipped + 1)); continue; fi
    # Everything downstream that prints, logs, or mails the alias uses this
    # bounded form; the raw field is not referenced again.
    alias="$(sanitize_display "${alias:-$id}")"
    state="$STATE_DIR/$id"
    checked=$((checked + 1))

    # A peek that fails, times out, or returns nothing tells us nothing about
    # the pane — and the not-parked branch below DELETES the episode state. Read
    # as "clean", a transient runtime failure resets the backoff and the
    # once-per-episode escalation flag, so a block that has run for six hours
    # looks freshly detected on the next cycle and starts nudging from attempt 1
    # again. Only a successful peek may end an episode. Leave the state alone
    # and try again in 3m.
    peek_rc=0
    pane=$(run_bounded gc session peek "$id" --lines "$PEEK_LINES" 2>/dev/null) || peek_rc=$?
    if [ "$peek_rc" -ne 0 ] || [ -z "$pane" ]; then
        unreadable=$((unreadable + 1))
        echo "quota-park-nudge: pane unreadable for $alias ($id) (peek rc=$peek_rc) — episode state kept"
        continue
    fi

    # Parked = a bare provider banner at the bottom of an idle pane. Busy,
    # cited, or scrolled-up all mean not parked. Clearing the state file is what
    # ends an episode: a recovered agent starts the next block from attempt 1.
    if printf '%s\n' "$pane" | grep -qEi -- "$BUSY_RE" \
        || ! banner_candidates "$pane" | grep -qEi -- "$MATCH_RE"; then
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
    # Deliveries we could not confirm, kept apart from the ones we could: see
    # the nudge branches below. Absent from a state file an older version wrote,
    # which reads as zero — the same as a fresh episode.
    unconfirmed="$(state_get "$state" unconfirmed)"; num "$unconfirmed" || unconfirmed=0
    # Pacing keys on the last delivery ATTEMPT, not the last confirmed one.
    # Falls back to last_nudge so a state file from before this field existed
    # still paces on its confirmed nudge instead of reading as never-tried.
    last_try="$(state_get "$state" last_try)"; num "$last_try" || last_try="$last_nudge"
    escalated="$(state_get "$state" escalated)"
    age=$((NOW - first_seen))
    tries=$((attempts + unconfirmed))

    if [ "$tries" -gt 0 ] && [ $((NOW - last_try)) -lt "$(backoff_for "$tries")" ]; then
        # Still blocked, still inside the backoff window — say nothing, wait.
        write_state "$state" "$first_seen" "$last_nudge" "$last_try" "$attempts" "$unconfirmed" "$escalated"
        continue
    fi

    # The nudge text deliberately avoids every phrase in MATCH_RE: it lands in
    # the same pane we read next cycle, and a self-matching message would keep
    # the episode alive forever after the agent recovered.
    msg="Provider block may have cleared after $(duration "$age") — resume: re-check your hook (gc hook --claim --json) or continue your patrol loop. If still blocked, ignore this; it repeats until you are back."
    # `--delivery immediate` because the default (wait-idle) hands the message
    # to the runtime's idle detector — the same layer that already believes a
    # parked session is fine. We read the pane; we know it is idle.
    nudge_rc=0
    run_bounded gc session nudge --delivery immediate "$id" "$msg" >/dev/null 2>&1 || nudge_rc=$?
    # Fall back to the plain form ONLY for the case the fallback exists for: an
    # older gc that rejects the flag, which fails fast with a usage error. A
    # bound that expired (`timeout` exits 124) or a signalled call (>=128) is
    # NOT that case — the runtime may already have accepted the first nudge and
    # simply not answered in time, so retrying delivers two resume messages into
    # one pane and leaves `attempts` undercounting what the agent received.
    # There, record a failed nudge and let the next cycle retry under the
    # backoff, which is the pacing we want for a still-blocked session anyway.
    if [ "$nudge_rc" -ne 0 ] && [ "$nudge_rc" -ne 124 ] && [ "$nudge_rc" -lt 128 ]; then
        nudge_rc=0
        run_bounded gc session nudge "$id" "$msg" >/dev/null 2>&1 || nudge_rc=$?
    fi
    if [ "$nudge_rc" -eq 0 ]; then
        nudged=$((nudged + 1))
        last_nudge="$NOW"; last_try="$NOW"
        attempts=$((attempts + 1))
        echo "quota-park-nudge: nudged $alias ($id), parked $(duration "$age"), attempt $((attempts + unconfirmed))"
    elif [ "$nudge_rc" -eq 124 ] || [ "$nudge_rc" -ge 128 ]; then
        # AMBIGUOUS, and paced as an attempt anyway. The bound expired (or the
        # call was signalled) on a nudge the runtime may already have accepted —
        # the same window the fallback above refuses to retry into. Refusing the
        # immediate retry but leaving the counters untouched only moves the
        # duplicate one cycle out: `attempts` stays 0, the backoff test below
        # reads the session as never nudged, and the next 3m pass sends a second
        # resume message into the same pane. So an unconfirmed delivery advances
        # the pacing (last_try, and the doubling exponent via `tries`) while
        # never claiming a delivery we did not see land — `attempts`, the count
        # the escalation reports to a human, still means "confirmed".
        unconfirmed=$((unconfirmed + 1))
        last_try="$NOW"
        unconfirmed_now=$((unconfirmed_now + 1))
        echo "quota-park-nudge: nudge UNCONFIRMED (rc=$nudge_rc) for $alias ($id), parked $(duration "$age"), paced as attempt $((attempts + unconfirmed))"
    else
        # A fast rejection: nothing was delivered, so nothing is paced. The next
        # cycle retries in 3m, which is what we want for a transient runtime
        # error — unlike the ambiguous case, a retry here cannot duplicate.
        echo "quota-park-nudge: nudge FAILED (rc=$nudge_rc) for $alias ($id), parked $(duration "$age")"
    fi

    unconf_note=""
    [ "$unconfirmed" -gt 0 ] && unconf_note=" (plus $unconfirmed unconfirmed)"
    if [ "$ESCALATE_AFTER" -gt 0 ] && [ "$escalated" != "1" ] && [ "$age" -ge "$ESCALATE_AFTER" ]; then
        # No pane text in the body — see detector_class. The label stands in for
        # the excerpt the earlier version mailed: it says which banner family
        # matched without quoting a pane the agent controls.
        run_bounded gc mail send "$ESCALATE_TO" -s "Quota-parked: $alias for $(duration "$age") [HIGH]" \
            -m "$alias ($id) has shown a provider limit banner for $(duration "$age") and has not resumed after $attempts nudge(s)$unconf_note.

Detector class: $(detector_class "$pane")

The session is alive and correct — do NOT file a warrant or kill it; a fresh
agent hits the same block and the parked one recovers by itself once the
window reopens. quota-park-nudge keeps retrying on a $((BACKOFF_CAP / 60))m cadence, so
no action is needed unless the block is unexpected (wrong account, wrong
plan, a provider outage misreported as a quota block).

The pane itself is deliberately not quoted here: it is untrusted agent output
and this mail is a durable artifact. Read it directly with: gc session peek $id" >/dev/null 2>&1 \
            && escalated=1 \
            || echo "quota-park-nudge: escalation mail FAILED for $alias ($id)"
    fi

    write_state "$state" "$first_seen" "$last_nudge" "$last_try" "$attempts" "$unconfirmed" "$escalated"
done <<< "$sessions"

# A recovered agent's state file is removed above, the moment its pane goes
# clean. This only sweeps files no cycle has touched in a week — sessions that
# were closed or renamed while parked.
#
# Narrow on purpose, because STATE_DIR is an override and its default sits
# inside the shared city runtime directory: a broad `find "$STATE_DIR" -type f
# -mtime +7 -delete` is a city-scoped order deleting week-old files it has never
# heard of, and a mis-set or shared QUOTA_PARK_STATE_DIR is all it takes to
# point that at somebody else's state. Three predicates keep it to our own
# files: DIRECTLY in STATE_DIR (`-maxdepth 1`, so a nested tree is never
# touched, whatever its age); named like the session ids we write (`safe_id`,
# the same test that decides which ids may name a file at all); and carrying a
# state file's own `first_seen=` header on line 1. Anything failing one of them
# is somebody else's file and is left alone. `-print0` because a name is not
# trusted to be one line — split on newlines, a hostile name becomes two paths
# and the second is a relative one.
#
# The header test reads line 1 directly rather than through `head | grep`: under
# `pipefail` a `grep -q` that matches can close the pipe first, and the SIGPIPE'd
# `head` then fails the whole pipeline — which would read as "not our file" and
# skip the delete on exactly the files this is meant to prune.
prune_stale_state() {
    local path base header
    while IFS= read -r -d '' path; do
        base="${path##*/}"
        safe_id "$base" || continue
        header=""
        IFS= read -r header < "$path" 2>/dev/null || true
        case "$header" in first_seen=*) ;; *) continue ;; esac
        rm -f "$path"
    done < <(find "$STATE_DIR" -maxdepth 1 -type f -mtime +7 -print0 2>/dev/null || true)
}
prune_stale_state

# Everything the sweep could not conclude is named in the summary rather than
# folded into "checked" — a short sweep must not read as a complete one.
unread=""
[ "$unreadable" -gt 0 ] && unread=", $unreadable unreadable"
unsafe=""
[ "$rejected" -gt 0 ] && unsafe=", $rejected rejected (unsafe session id)"
deferred=""
[ "$skipped" -gt 0 ] && deferred=", $skipped deferred (sweep budget ${SWEEP_BUDGET}s)"
unconf=""
[ "$unconfirmed_now" -gt 0 ] && unconf=", $unconfirmed_now unconfirmed (bound expired mid-delivery)"
echo "quota-park-nudge: $checked checked, $parked parked, $nudged nudged$unconf$unread$unsafe$deferred"
