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
# Those patrols hold their warrant back on THIS script's verdict, never on the
# pane: `--status` below is the closed-field surface they read, and the reason
# a banner an agent printed itself cannot switch off its own recovery.
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

# How long this order's own findings stay authoritative. The sweep runs every
# 3m, so ten minutes is three missed cycles — past that, neither the heartbeat
# nor an episode record is treated as evidence any more. Only the `--status`
# surface reads this; the sweep itself has no use for it.
STALE_AFTER="${QUOTA_PARK_STALE_AFTER:-600}"

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

# This order's files that are NOT episode state: where the last pass stopped,
# that a pass ran at all, and which sessions it actually classified. Every name
# starts with a dot, which `safe_id` rejects — so no session can ever be given a
# state file that collides with one, and the week-old prune below (safe_id AND a
# state header) never touches them.
CURSOR_FILE="$STATE_DIR/.sweep-cursor"
HEARTBEAT_FILE="$STATE_DIR/.heartbeat"
COVERAGE_FILE="$STATE_DIR/.sweep-coverage"

NOW="$(date +%s)"

# Read one key out of a state file. Never `source` it — the file is keyed by a
# session id and lives in a shared runtime dir.
#
# Never through a symlink either. STATE_DIR is shared (and an override), so an
# entry planted there would otherwise have this order reading a file of somebody
# else's choosing and parsing it as its own episode state. A planted link reads
# as "no state", and the next write replaces the link itself rather than
# following it — see write_atomic.
state_get() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 0
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- || true
}

# True for a bare non-empty integer — everything read back out of a state file
# is fed to arithmetic, and `$(( ))` on garbage is fatal under `set -e`.
num() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }

# Replace a file in STATE_DIR with what arrives on stdin, atomically, and never
# by writing THROUGH whatever is already at the path.
#
# A plain `>` follows an existing symlink or FIFO. STATE_DIR is a shared runtime
# directory whose location is an override, and every path under it is named by a
# session id, so an entry planted there — by anything that can create a file
# beside our state — would have this order writing wherever it points, as the
# order's user, on every 3m sweep. A FIFO is worse than a wrong file: with no
# reader the open blocks, and the sweep hangs where it is meant to be bounded.
#
# `mktemp` creates the temp file O_EXCL (so the write itself cannot be
# redirected) and rename(2) replaces the destination ENTRY whatever type it is
# (so the replace cannot be either, and a planted link is destroyed rather than
# followed). The temp name is dot-prefixed and distinctive: `safe_id` rejects a
# leading dot, so a temp file left by a killed pass can never be read back as an
# episode, reported as a parked session, or pruned as one — the prune below
# collects them by name instead.
write_atomic() {
    local dest="$1" tmp
    tmp="$(mktemp "$STATE_DIR/.qpn-tmp.XXXXXX" 2>/dev/null)" || return 1
    if cat > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# One writer for an episode's state file, so the two paths that persist it —
# inside the backoff window, and after a delivery attempt — cannot drift in
# which counters they carry. Positional: path, first_seen, last_nudge, last_try,
# attempts, unconfirmed, escalated, last_seen, detector_class.
#
# The last two are what make this file readable as a CLASSIFICATION and not only
# as a retry ledger: `--status` answers the patrols out of them, and a record
# nothing has confirmed since `last_seen` is reported as unknown rather than as a
# park. Both are written on every pass that saw the session parked, so a state
# file is never older than the sweep that last looked.
write_state() {
    printf 'first_seen=%s\nlast_nudge=%s\nlast_try=%s\nattempts=%s\nunconfirmed=%s\nescalated=%s\nlast_seen=%s\ndetector_class=%s\n' \
        "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" | write_atomic "$1"
}

# True for a session id safe to use as a filename AND as a command argument. The
# id names a state file in a shared runtime directory, is pasted into the
# operator instruction in the escalation mail, and is passed to `gc session
# peek` / `gc session nudge`, so it must be a bare token: no separator, no
# dot-segment, nothing that can leave STATE_DIR, and nothing that can be read as
# an option. Runtime ids look like `lx-gsnfk`; an id that does not is not one,
# and a session we cannot name safely is one we skip rather than guess at.
# (`.*` rejects a leading dot, `*..*` any dot-segment, and `/` is absent from the
# allowed set — together that is every route out of the dir.)
#
# `-*` is the argument half, and quoting does not cover it: a shell-quoted
# argument is still parsed as an option by the command that receives it, so an
# id like `-n` or `--help` reaches `gc session nudge` as a flag rather than as a
# session. What that runs is the receiving CLI's business, not ours; refusing to
# hand it over is.
safe_id() { case "${1:-}" in '' | *[!A-Za-z0-9._-]* | .* | -* | *..*) return 1 ;; *) return 0 ;; esac }

# How long ago this order last CLASSIFIED a session — reached a verdict on its
# pane — as opposed to merely having run a pass in which that session existed.
# Prints an age in seconds, or fails if there is no record. See write_coverage.
covered_age() {
    local ts
    [ -f "$COVERAGE_FILE" ] && [ ! -L "$COVERAGE_FILE" ] || return 1
    ts="$(awk -v id="$1" '$1 == id { print $2; exit }' "$COVERAGE_FILE" 2>/dev/null)" || return 1
    num "$ts" || return 1
    echo $((NOW - ts))
}

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

# Which family of banner matched, as a label from a CLOSED set. This is the only
# thing the escalation mail — or the `--status` surface the patrols read — says
# about what was on screen.
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
num_min "$STALE_AFTER"    1 || STALE_AFTER=600

# --- The status surface -----------------------------------------------------
#
#   quota-park-nudge.sh --status [<session-id>]
#
# What the patrols read INSTEAD of peeking a pane, and the reason this order can
# be allowed to hold a warrant back at all.
#
# The pane is agent-controlled output. A patrol step that says "peek the pane,
# and if you see a limit banner do not file a warrant" hands every agent an off
# switch for its own stuck-session recovery: print a provider-shaped line, sit
# idle, and the path that would have recovered the work stands down. The agents
# most likely to do that are the wedged and the compromised ones — precisely the
# two the warrant exists for. Pane text cannot be the thing that suppresses it.
#
# So the classification stays here, in a non-LLM helper, and reaches the patrols
# only as CLOSED fields: a yes/no/unknown, a label from detector_class's fixed
# set, a `reason` from a fixed set, and integers out of this script's own state
# files. Not one byte of pane text is emitted. A patrol never sees the screen and
# so cannot be talked into anything by it.
#
# `unknown` is the field that keeps this honest, and it is deliberately NOT
# folded into `no`. Everything reported here is evidence this order produced; if
# the order is not running — disabled, wedged before it could list sessions, no
# jq, a host without the pack — there is no evidence at all. Read as "not
# parked" that silence is right by accident; read as "parked" it would suppress
# warrants city-wide on the strength of a stopped clock. `unknown` says which
# one it is, and the patrol prose sends it down the normal warrant path.
#
# Consequently EVERY answer is conditional on evidence about THAT session, never
# merely on a pass having run:
#   yes     — an episode whose last sighting is within STALE_AFTER
#   no      — no episode, AND this order classified that session within
#             STALE_AFTER (the per-session coverage record, `.sweep-coverage`)
#   unknown — anything else, with `reason` saying which:
#               no-recent-sweep  the heartbeat is stale: no pass lately at all
#               not-swept        a pass ran but never reached this session —
#                                deferred by the budget, an unreadable pane, an
#                                id it refused, attached, or not in the list
#               stale-episode    an episode nothing has confirmed lately
#               unsafe-session-id  an id this order will not name a file with
#
# The `no` case is the one that has to be earned rather than inferred: a pass
# that runs out of SWEEP_BUDGET defers its whole tail without peeking it and
# still writes a fresh heartbeat, so "a sweep ran recently and there is no
# episode" is not the same statement as "that session is not parked".
status_line() {
    local id="$1" path="$STATE_DIR/$1"
    local first_seen last_seen attempts unconfirmed escalated dclass verdict age seen_age human
    local cov_age reason=-
    first_seen="$(state_get "$path" first_seen)";   num "$first_seen"  || first_seen=0
    last_seen="$(state_get "$path" last_seen)";     num "$last_seen"   || last_seen=0
    attempts="$(state_get "$path" attempts)";       num "$attempts"    || attempts=0
    unconfirmed="$(state_get "$path" unconfirmed)"; num "$unconfirmed" || unconfirmed=0
    # A 0/1 flag on the way out, and `unconfirmed` maps to 1. The third state is
    # real but it is this script's own bookkeeping: an escalation whose bound
    # expired must not be resent, and from that moment on this script BEHAVES as
    # though the human was mailed. The consumers — mol-deacon-patrol,
    # mol-witness-patrol, docs/quota-park-recovery.md — define only `escalated=1`
    # ("a human has been mailed; stop deferring in silence"), and nothing anywhere
    # defines `unconfirmed`. Publishing a value no consumer handles is how a park
    # that outlasts ESCALATE_AFTER keeps getting deferred down an undefined path
    # forever, so the surface answers in the vocabulary its readers have. The
    # distinction stays where it is acted on, in the state file.
    escalated="$(state_get "$path" escalated)"
    case "$escalated" in 1 | unconfirmed) escalated=1 ;; *) escalated=0 ;; esac
    # Constrained to the closed set on the way OUT as well as on the way in: a
    # state file written by an older version, or edited by hand, must not be able
    # to put arbitrary text on a line a patrol agent reads.
    dclass="$(state_get "$path" detector_class)"
    case "$dclass" in
        possessive-limit | named-provider-limit | usage-credits | provider-limit | custom-match) ;;
        *) dclass=unknown ;;
    esac
    age=-1;      [ "$first_seen" -gt 0 ] && age=$((NOW - first_seen))
    seen_age=-1; [ "$last_seen"  -gt 0 ] && seen_age=$((NOW - last_seen))
    human="-";   [ "$age" -ge 0 ] && human="$(duration "$age")"

    if [ "$HB_FRESH" != "1" ]; then
        verdict=unknown; reason=no-recent-sweep   # no recent pass: no evidence at all
    elif [ ! -f "$path" ] || [ -L "$path" ]; then
        # No episode for this session. That is only evidence of "not parked" if
        # this order actually LOOKED at the session recently, and a fresh
        # heartbeat does not say that: a pass that runs out of SWEEP_BUDGET
        # defers its whole tail WITHOUT peeking it and still writes a heartbeat
        # at the end. Read off the heartbeat alone, every deferred session
        # answers `no` — a verdict about a pane nobody read, handed to a patrol
        # as grounds to take the normal warrant path against a session this order
        # never inspected. Which is the failure it exists to prevent, arriving
        # through the surface that was meant to prevent it.
        #
        # So the not-parked answer is conditional on a per-session sighting, the
        # same way the parked answer is conditional on `last_seen`. One record
        # covers every way a session goes uninspected: budget-deferred, an
        # unreadable pane, an id the sweep refused, a session that is attached or
        # simply not in the active list.
        cov_age="$(covered_age "$id")" || cov_age=-1
        if [ "$cov_age" -ge 0 ] && [ "$cov_age" -lt "$STALE_AFTER" ]; then
            verdict=no                      # looked at it recently, no episode
        else
            verdict=unknown; reason=not-swept
        fi
    elif [ "$seen_age" -lt 0 ] || [ "$seen_age" -ge "$STALE_AFTER" ]; then
        verdict=unknown; reason=stale-episode  # an episode nothing has confirmed lately
    else
        verdict=yes
    fi
    printf 'session=%s quota_park=%s detector_class=%s age_s=%s parked_for=%s attempts=%s unconfirmed=%s escalated=%s last_seen_age=%s reason=%s\n' \
        "$id" "$verdict" "$dclass" "$age" "$human" "$attempts" "$unconfirmed" "$escalated" "$seen_age" "$reason"
}

status_report() {
    local want="${1:-}" hb path base
    hb="$(state_get "$HEARTBEAT_FILE" last_run)"; num "$hb" || hb=0
    HB_AGE=-1; [ "$hb" -gt 0 ] && HB_AGE=$((NOW - hb))
    HB_FRESH=0
    if [ "$hb" -gt 0 ] && [ "$HB_AGE" -lt "$STALE_AFTER" ]; then HB_FRESH=1; fi
    printf 'heartbeat_age=%s\nheartbeat_fresh=%s\nstale_after=%s\n' "$HB_AGE" "$HB_FRESH" "$STALE_AFTER"
    if [ -n "$want" ]; then
        # An id this order would refuse to write state for is one it will not read
        # state for either — same test, same reason, and the caller gets the same
        # `unknown` it gets for anything else this order cannot speak to.
        if ! safe_id "$want"; then
            echo "session=- quota_park=unknown detector_class=unknown reason=unsafe-session-id"
            return 0
        fi
        status_line "$want"
        return 0
    fi
    # No id: every episode this order is currently tracking. Same filter the
    # prune uses, so a foreign file dropped in the directory is not reported as a
    # parked session.
    for path in "$STATE_DIR"/*; do
        [ -f "$path" ] || continue
        base="${path##*/}"
        safe_id "$base" || continue
        status_line "$base"
    done
}

# Only `--status` is special; anything else falls through to a normal sweep,
# which is what the order runner invokes with no arguments at all.
if [ "${1:-}" = "--status" ]; then
    status_report "${2:-}"
    exit 0
fi

# --- Pattern overrides, validated before the sweep uses them ----------------
#
# The numeric knobs above are validated for the same reason these are, but a bad
# ERE fails in a nastier direction: `grep` answers a malformed pattern with rc 2,
# and every test below reads a non-zero rc as "did not match". So
# `QUOTA_PARK_MATCH='('` does not disable the detector loudly — it reports every
# pane in the city as CLEAN, which deletes the episode state of every session
# genuinely parked and leaves `--status` answering `no` for all of them. One
# malformed character in a tuning knob, and quota recovery is silently off
# city-wide while the summary line reports a healthy sweep. (Reproduced during
# review: `QUOTA_PARK_MATCH='('` → `0 parked`, `quota_park=no` on a parked pane.)
#
# The other two fail the same way in their own direction: a malformed BUSY
# pattern matches nothing, so every busy pane reads as idle and gets nudged
# mid-turn; a malformed EXCLUDE pattern matches nothing, so the operator's escape
# hatch is silently ignored. Each falls back to its own default and says so — the
# fallback is chosen so that recovery keeps working, never so that a typo can
# switch it off. That is also why an unusable EXCLUDE falls back to "no
# exclusions" rather than to "exclude everything": the cost of the first is one
# unwanted nudge per backoff window on one session, the cost of the second is the
# whole city unrecovered.
valid_ere() {
    local rc=0
    printf '' | grep -Eq -- "${1:-}" >/dev/null 2>&1 || rc=$?
    [ "$rc" -le 1 ]
}
if ! valid_ere "$MATCH_RE"; then
    echo "quota-park-nudge: QUOTA_PARK_MATCH is not a valid ERE — using the default detector"
    MATCH_RE="$DEFAULT_MATCH"
    # detector_class labels a match `custom-match` from the presence of the
    # override; having fallen back, we are not using one.
    unset QUOTA_PARK_MATCH
fi
if ! valid_ere "$BUSY_RE"; then
    echo "quota-park-nudge: QUOTA_PARK_BUSY is not a valid ERE — using the default busy markers"
    BUSY_RE="$DEFAULT_BUSY"
fi
if [ -n "$EXCLUDE_RE" ] && ! valid_ere "$EXCLUDE_RE"; then
    echo "quota-park-nudge: QUOTA_PARK_EXCLUDE is not a valid ERE — no aliases are excluded this pass"
    EXCLUDE_RE=""
fi

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

checked=0; parked=0; nudged=0; skipped=0; unreadable=0; rejected=0; unconfirmed_now=0
last_attempted=""
covered_now=""

# That a pass RAN, and what it saw. This is what makes the status surface
# refusable: warrant suppression in the patrols is conditional on a recent sweep,
# so an order that is disabled, wedged, or absent from a host cannot hold a
# warrant back by leaving old evidence lying around. Written only where a pass
# actually completed — every early exit below (a session list that failed, no
# jq, an unwritable state dir) leaves the previous heartbeat to go stale, which
# is exactly what a patrol reads as `unknown`.
write_heartbeat() {
    printf 'last_run=%s\nchecked=%s\nparked=%s\nnudged=%s\ndeferred=%s\n' \
        "$NOW" "$checked" "$parked" "$nudged" "$skipped" | write_atomic "$HEARTBEAT_FILE" || true
}

# WHICH sessions a pass classified, which is a different fact from that a pass
# ran, and the one `--status` needs before it may answer `no` for a session with
# no episode. A pass is not a census: the sweep is round-robin under a budget, so
# a session can be deferred, unreadable, refused, attached, or absent from the
# list — uninspected, every one of them, on a pass that completes and writes a
# perfectly fresh heartbeat.
#
# Merged rather than overwritten, because a classification stays evidence for
# STALE_AFTER: this pass's records go in first so they win the dedup, and
# anything past the cutoff is dropped, which keeps the file bounded by the number
# of live sessions instead of growing forever. Atomic and dot-prefixed for the
# same reasons as the heartbeat.
write_coverage() {
    local cutoff=$((NOW - STALE_AFTER)) prior=""
    if [ -f "$COVERAGE_FILE" ] && [ ! -L "$COVERAGE_FILE" ]; then
        prior="$(cat "$COVERAGE_FILE" 2>/dev/null || true)"
    fi
    printf '%s%s\n' "$covered_now" "$prior" \
        | awk -v cutoff="$cutoff" \
            'NF == 2 && $2 ~ /^[0-9]+$/ && $2 + 0 >= cutoff + 0 && !seen[$1]++ { print $1, $2 }' \
        | write_atomic "$COVERAGE_FILE" || true
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
# An empty list is a complete pass over nothing, not a failure: the list came
# back and parsed, there was simply nothing sweepable in it. It gets a heartbeat
# — every session then reports `no` (no episode), which is true.
[ -n "$sessions" ] || { write_heartbeat; echo "quota-park-nudge: 0 checked, 0 parked, 0 nudged"; exit 0; }

# Where to start. `gc session list` returns a stable order and every peek that
# hangs costs a whole CALL_TIMEOUT out of SWEEP_BUDGET, so a fixed starting point
# means a prefix of slow sessions is paid for FIRST on every pass — eight of them
# at the defaults (8 × 15s = the 120s budget) and the sweep never reaches the
# rest. Not once: every cycle, the same prefix, the same deferral. The sessions
# behind it are then never inspected at all, which is the one outcome this order
# exists to prevent — a genuinely parked agent going unrecovered while the city
# logs a healthy 3m sweep over it.
#
# So the cursor records the last session a pass attempted and the next pass
# resumes AFTER it, round-robin. An unreadable prefix ends up at the back of the
# next pass's order and cannot consume it twice. A pass that gets through the
# whole list leaves the cursor on the final record, and rotating past the last
# record is the identity — the steady state is the plain order, unchanged.
cursor="$(state_get "$CURSOR_FILE" session)"
safe_id "$cursor" || cursor=""
if [ -n "$cursor" ]; then
    # Matched against the id FIELD, never as a substring: ids can be prefixes of
    # one another and the alias column holds arbitrary text. `-v` is safe here
    # because safe_id has already excluded the backslash that awk's own variable
    # assignment would otherwise re-interpret.
    cursor_at="$(printf '%s\n' "$sessions" | awk -F'\t' -v c="$cursor" '$1 == c { print NR; exit }')"
    session_count="$(printf '%s\n' "$sessions" | awk 'END { print NR }')"
    if num "$cursor_at" && num "$session_count" && [ "$cursor_at" -lt "$session_count" ]; then
        sessions="$(printf '%s\n' "$sessions" | tail -n +"$((cursor_at + 1))"
                    printf '%s\n' "$sessions" | head -n "$cursor_at")"
    fi
fi

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
    # Attempted, as far as the cursor is concerned, from here — before the peek,
    # not after it. The peek is the call that hangs, and a session whose peek ate
    # the rest of the budget is precisely the one the next pass must start after.
    last_attempted="$id"
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

    # The pane was read, so this session gets a verdict below whichever branch it
    # takes — and this pass can therefore vouch for it. Recorded for `--status`,
    # which may only answer `no` for a session it can show was actually looked
    # at; see write_coverage. Deliberately AFTER the unreadable branch: a peek
    # that failed classified nothing.
    covered_now="$covered_now$id $NOW"$'\n'

    # Parked = a bare provider banner at the bottom of an idle pane. Busy,
    # cited, or scrolled-up all mean not parked. Clearing the state file is what
    # ends an episode: a recovered agent starts the next block from attempt 1.
    if printf '%s\n' "$pane" | grep -qEi -- "$BUSY_RE" \
        || ! banner_candidates "$pane" | grep -qEi -- "$MATCH_RE"; then
        rm -f "$state"
        continue
    fi

    parked=$((parked + 1))
    # An excluded alias is one this order does not act on AT ALL: no nudge, and no
    # state file either, so `--status` reports it as `no` and the patrols fall
    # back to their own judgment instead of deferring to a recovery that was
    # switched off for this session. Counted as parked in the summary, because it
    # is — the escape hatch suppresses the action, not the observation.
    if [ -n "$EXCLUDE_RE" ] && printf '%s' "$alias" | grep -qEi -- "$EXCLUDE_RE"; then
        # Any episode from BEFORE the exclusion goes with it. An alias can be
        # added to QUOTA_PARK_EXCLUDE while a park is already being tracked, and
        # a state file left behind then keeps answering for a session this order
        # has stopped acting on: `yes` while the last sighting is still fresh —
        # a patrol deferring its warrant to a recovery that is switched off for
        # exactly that session — and `unknown` afterwards. Neither is the
        # contract above. `no` is, and that needs the file gone.
        rm -f "$state"
        echo "quota-park-nudge: $alias parked (excluded, not nudged)"
        continue
    fi

    # Classified once per parked session, from the closed set, and persisted with
    # the episode: this is what the status surface hands a patrol, and — with the
    # escalation mail — the only thing anywhere outside this script that says
    # anything about what was on the screen.
    dclass="$(detector_class "$pane")"

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
        # Still blocked, still inside the backoff window — say nothing, wait. The
        # sighting is still recorded: a session nobody nudges this cycle is one
        # this pass nonetheless confirmed parked, and `--status` reads last_seen.
        write_state "$state" "$first_seen" "$last_nudge" "$last_try" "$attempts" "$unconfirmed" "$escalated" "$NOW" "$dclass"
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
    # Any escalation marker at all suppresses the next one — `1` for a delivery we
    # saw complete, `unconfirmed` for one whose bound expired mid-send. Not
    # `!= "1"`: that reads an unconfirmed escalation as never sent and mails the
    # mayor again for the same park.
    if [ "$ESCALATE_AFTER" -gt 0 ] && [ -z "$escalated" ] && [ "$age" -ge "$ESCALATE_AFTER" ]; then
        # No pane text in the body — see detector_class. The label stands in for
        # the excerpt the earlier version mailed: it says which banner family
        # matched without quoting a pane the agent controls.
        mail_rc=0
        run_bounded gc mail send "$ESCALATE_TO" -s "Possible quota park: $alias for $(duration "$age") [HIGH]" \
            -m "$alias ($id) has shown a provider limit banner for $(duration "$age") and has not resumed after $attempts nudge(s)$unconf_note.

Detector class: $dclass

This is a POSSIBLE quota park, not a proven one. The only evidence is a pattern
match on that session's own pane, which is agent-controlled output: a wedged —
or prompt-injected — agent can print a provider-shaped line and sit idle, and it
looks exactly like this from here. Treat it as a reason to CHECK, never as proof
that the session is healthy.

If it is a real park, the session is alive and correct and nudging is the whole
treatment: killing it discards live context and a fresh agent hits the same
block. quota-park-nudge keeps retrying on a $((BACKOFF_CAP / 60))m cadence, so no action is
needed unless the block itself is unexpected (wrong account, wrong plan, a
provider outage misreported as a quota block). If it is NOT a real park, the
normal stuck-session path applies and nothing in this mail should hold it back.

The pane itself is deliberately not quoted here: it is untrusted agent output
and this mail is a durable artifact. Read it directly with: gc session peek $id" >/dev/null 2>&1 || mail_rc=$?
        if [ "$mail_rc" -eq 0 ]; then
            escalated=1
        elif [ "$mail_rc" -eq 124 ] || [ "$mail_rc" -ge 128 ]; then
            # AMBIGUOUS, and recorded as sent — the same rule the nudge branch
            # above follows, for the same reason and one layer deeper. `gc mail
            # send` writes durable mail through Dolt, so a bound that expires
            # after the write is committed leaves a mail in the mayor's inbox that
            # this script never heard about. Left empty, the next eligible pass
            # sends a second one for the same episode, and it does that during
            # exactly the slow-runtime incident this order is meant to tolerate.
            # `unconfirmed` says both things at once: something may well have been
            # delivered, and we did not see it land.
            escalated=unconfirmed
            echo "quota-park-nudge: escalation mail UNCONFIRMED (rc=$mail_rc) for $alias ($id) — not resent this episode"
        else
            # A fast rejection, delivered nothing. Retried next cycle, and it
            # cannot duplicate — again mirroring the nudge branch.
            echo "quota-park-nudge: escalation mail FAILED (rc=$mail_rc) for $alias ($id) — retries next cycle"
        fi
    fi

    write_state "$state" "$first_seen" "$last_nudge" "$last_try" "$attempts" "$unconfirmed" "$escalated" "$NOW" "$dclass"
done <<< "$sessions"

# Where the next pass starts, and the record that this one ran. Written together,
# after the sweep: the cursor is only meaningful once the loop has decided how
# far it got, and a heartbeat written earlier would claim a pass that had not
# finished.
if [ -n "$last_attempted" ]; then
    printf 'session=%s\n' "$last_attempted" | write_atomic "$CURSOR_FILE" || true
fi
write_coverage
write_heartbeat

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
# is somebody else's file and is left alone — including this order's OWN
# `.sweep-cursor` and `.heartbeat`, whose leading dot puts them outside safe_id
# on purpose. `-print0` because a name is not
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
        # This order's own abandoned temp files — a pass killed between `mktemp`
        # and the rename in write_atomic. Unmistakably ours by name, so they are
        # collected here rather than accumulating in the runtime directory
        # forever; `safe_id` would otherwise skip them for their leading dot,
        # which is the same property that keeps them out of `--status`.
        case "$base" in .qpn-tmp.*) rm -f "$path"; continue ;; esac
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
