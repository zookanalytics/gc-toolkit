#!/usr/bin/env bash
# quota-park-nudge — resume agents parked at a provider quota banner
# (bug tk-al95k: a quota window closing mid-turn ends the agent's turn; the
# session stays state=active, idle under the banner, with nothing to wake it).
# Job: poll every live session's pane; nudge the ones showing a limit banner.
# A nudge is the ONLY action — never kill, never file a warrant. Two rules:
# the signature set is provider-agnostic (extend via $QUOTA_PARK_MATCH), and
# recovery never sleeps until the banner's stated reset time (a manual reset
# can land early; being early costs one no-op nudge, being late costs a day).
# Callers: the quota-park-nudge exec order (3m cadence); the deacon/witness
# patrols read the closed-field `--status` surface below INSTEAD of the pane.
# See docs/quota-park-recovery.md.
set -euo pipefail

# Pane lines captured, and the tail window that counts as the CURRENT screen
# (a real park ends with the banner; anything above the tail is history).
PEEK_LINES="${QUOTA_PARK_PEEK_LINES:-20}"
TAIL_LINES="${QUOTA_PARK_TAIL_LINES:-12}"

# Banner signatures — one ERE, alternatives per family (a new provider goes in
# $QUOTA_PARK_MATCH rather than a bare form):
#   family            anchor
#   possessive        (hit|reached|exceeded) your <quota-noun> limit
#   named-provider    (claude|codex|chatgpt|openai|anthropic|gemini|weekly|
#                     5-hour|plan) [...] limit (reached|exceeded)
#   usage-credits     /usage-credits
#   reset-clause      your <quota-noun> limit will reset
# Every alternative is anchored on something only a PROVIDER says — the
# possessive plus a quota NOUN (session/usage/weekly/...), never a bare
# "rate limit": a tool error ("Error: API rate limit exceeded", "Your API
# rate limit will reset at ...") must not read as a park (paid for three
# times). Word-counted gaps give the noun a left boundary. Held as ONE
# single-quoted literal: the suite reads this line out of the script, and an
# ERE interval inside ${VAR:-default} would close the expansion early.
DEFAULT_MATCH='(hit|reached|exceeded) your ([a-z0-9()./-]+ ){0,3}(session|usage|weekly|monthly|daily|hourly|5-hour|plan|subscription|quota|credit|message)s? limit|(claude|codex|chatgpt|openai|anthropic|gemini|weekly|5-hour|plan) (([a-z0-9()./-]+ ){0,3}(session|usage|weekly|monthly|daily|hourly|5-hour|plan|subscription|quota|credit|message)s? )?limit (reached|exceeded)|/usage-credits|your ([a-z0-9()./-]+ ){0,3}(session|usage|weekly|monthly|daily|hourly|5-hour|plan|subscription|quota|credit|message)s? limit will reset'
MATCH_RE="${QUOTA_PARK_MATCH:-$DEFAULT_MATCH}"

# Busy markers — an agent mid-turn is not parked (both CLIs print "esc to
# interrupt" while working).
DEFAULT_BUSY='esc to interrupt|ctrl.{0,2}c to (stop|interrupt)'
BUSY_RE="${QUOTA_PARK_BUSY:-$DEFAULT_BUSY}"

# A QUOTED banner is a citation, not a banner (an agent reporting the outage).
# A double quote anywhere on the line marks a citation (providers never print
# one); single/smart quotes and backticks count only as an OPENING delimiter
# (the apostrophe in "You've" is the same character). Alternation, not a
# bracket expression: multibyte chars in [...] are a byte set under C locale.
# The typographic quotes below are pattern DATA, not quoting.
CITATION_RE='^[[:space:]]*(>|\||▎|│|┃)*[[:space:]]*('\''|‘|’|`)|^[[:space:]]*(>|\||▎|│|┃)|"|“|”'

# Retry pacing: first detection nudges immediately; later attempts back off
# to the cap so a multi-day block does not nudge every cycle.
BACKOFF_BASE="${QUOTA_PARK_BACKOFF_BASE:-120}"
BACKOFF_CAP="${QUOTA_PARK_BACKOFF_CAP:-900}"

# Tell a human once per episode if a block outlasts this (0 disables).
ESCALATE_AFTER="${QUOTA_PARK_ESCALATE_AFTER:-7200}"
ESCALATE_TO="${QUOTA_PARK_ESCALATE_TO:-mayor/}"

# How long this order's findings stay authoritative for `--status` (the sweep
# runs every 3m; ten minutes is three missed cycles).
STALE_AFTER="${QUOTA_PARK_STALE_AFTER:-600}"

# Aliases never nudged (ERE, matched against the session alias). Escape hatch.
EXCLUDE_RE="${QUOTA_PARK_EXCLUDE:-}"

# Wall-clock bounds: CALL_TIMEOUT bounds each gc call (a wedged peek must not
# strand the sessions behind it), SWEEP_BUDGET bounds the pass. 0 disables.
CALL_TIMEOUT="${QUOTA_PARK_CALL_TIMEOUT:-15}"
SWEEP_BUDGET="${QUOTA_PARK_SWEEP_BUDGET:-120}"

# SIGKILL delay after CALL_TIMEOUT: plain `timeout N` is a SOFT bound a child
# may ignore; `timeout -k` adds the hard half (see BOUND_MODE).
KILL_AFTER="${QUOTA_PARK_KILL_AFTER:-5}"

CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
DEFAULT_STATE_DIR="${CITY:+$CITY/.gc/runtime}"
DEFAULT_STATE_DIR="${DEFAULT_STATE_DIR:-${TMPDIR:-/tmp}/gc}/quota-park"
STATE_DIR="${QUOTA_PARK_STATE_DIR:-$DEFAULT_STATE_DIR}"
# Recorded, NOT exited on: an unavailable state dir must still leave the
# `--status` surface a field to answer (unknown/state-dir-unavailable), never
# silence. `-w` too — mkdir -p succeeds on an existing unwritable dir.
STATE_DIR_OK=1
mkdir -p "$STATE_DIR" 2>/dev/null || STATE_DIR_OK=0
{ [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ]; } || STATE_DIR_OK=0

# Non-episode files. Dot-prefixed on purpose: safe_id rejects a leading dot,
# so no session's state file can collide and the prune never touches them.
CURSOR_FILE="$STATE_DIR/.sweep-cursor"
HEARTBEAT_FILE="$STATE_DIR/.heartbeat"
COVERAGE_FILE="$STATE_DIR/.sweep-coverage"

NOW="$(date +%s)"

# Ownership marker: the first line of every file this order writes, and the
# test every read/delete/prune path applies before treating a file as its own
# — shape (a header, an id-like name) is a guess, and both directions of
# guessing wrong were reproduced (foreign state read as an episode; foreign
# files deleted by the prune). A label, not an authenticator: an accident
# cannot forge it, a forgery has to be deliberate.
STATE_MAGIC='#quota-park-nudge-state-v1'

# True for a file this order wrote: a regular non-symlink file whose first
# line is the marker. Every read, delete, prune and report path uses this.
owned_file() {
    local first=""
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    IFS= read -r first < "$1" 2>/dev/null || return 1
    [ "$first" = "$STATE_MAGIC" ]
}

# Read one key out of an OWNED state file (never source it; a file that fails
# owned_file — including a planted symlink — reads as "no state").
state_get() {
    owned_file "$1" || return 0
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- || true
}

# True for a bare non-empty integer — everything read back out of a state file
# is fed to arithmetic, and `$(( ))` on garbage is fatal under `set -e`.
num() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }

# True for a timestamp this order could have written: an integer, not in the
# FUTURE. A future last_try/first_seen/last_run each defeats a guard by
# arithmetic alone, in the direction that stops recovery; invalid falls back
# to the same default a missing field gets, which is the direction that
# recovers.
ts_valid() { num "${1:-}" && [ "$1" -le "$NOW" ]; }

# Replace a file in STATE_DIR atomically, never writing THROUGH what is there:
# mktemp is O_EXCL and rename(2) replaces the entry, so a planted symlink or
# FIFO is destroyed rather than followed (a FIFO would hang the sweep). A
# DIRECTORY is refused — `mv file dir` moves the file INSIDE and would swallow
# the episode while reporting success. Temp names are dot-prefixed and carry
# the pass timestamp so the prune can age them without stat(1).
write_atomic() {
    local dest="$1" tmp
    [ -d "$dest" ] && return 1
    tmp="$(mktemp "$STATE_DIR/.qpn-tmp.$NOW.XXXXXX" 2>/dev/null)" || return 1
    if cat > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# Write an OWNED file: the marker line, then stdin, atomically.
write_owned() {
    { printf '%s\n' "$STATE_MAGIC"; cat; } | write_atomic "$1"
}

# The one writer for an episode's state file. Positional: path, first_seen,
# last_nudge, last_try, attempts, unconfirmed, escalated, last_seen,
# detector_class — the last two make the file a CLASSIFICATION, not just a
# retry ledger.
write_state() {
    printf 'first_seen=%s\nlast_nudge=%s\nlast_try=%s\nattempts=%s\nunconfirmed=%s\nescalated=%s\nlast_seen=%s\ndetector_class=%s\n' \
        "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" | write_owned "$1"
}

# True for a session id safe as a filename AND a command argument: no
# separator, no dot-segment, no leading dot or dash (a quoted `-n` still
# reaches `gc session nudge` as a flag). A session we cannot name safely is
# skipped, not guessed at.
safe_id() { case "${1:-}" in '' | *[!A-Za-z0-9._-]* | .* | -* | *..*) return 1 ;; *) return 0 ;; esac }

# Delete an episode state file — only one this order actually wrote: directly
# in STATE_DIR, safe_id-named, carrying the marker. Anything else is somebody
# else's and is left alone (the session then answers unknown/foreign-state,
# the safe direction).
owned_state_rm() {
    local path="$1" base
    owned_file "$path" || return 0
    # Directly in STATE_DIR, which the doc above has always claimed and only the
    # callers enforced. Stated here it is also the prune's depth guard: nothing
    # below the top level is ever a candidate, whatever it is named or carries.
    [ "${path%/*}" = "$STATE_DIR" ] || return 0
    base="${path##*/}"
    safe_id "$base" || return 0
    rm -f "$path"
}

# Age in seconds since this order last CLASSIFIED a session (not merely ran a
# pass in which it existed); fails if there is no record. See write_coverage.
covered_age() {
    local ts
    owned_file "$COVERAGE_FILE" || return 1
    ts="$(awk -v id="$1" '$1 == id { print $2; exit }' "$COVERAGE_FILE" 2>/dev/null)" || return 1
    ts_valid "$ts" || return 1
    echo $((NOW - ts))
}

# Bound and flatten a display field before logging/mailing: alias and
# session_name are mutable, agent-reachable, and reach durable mayor mail.
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

# The CURRENT region of a pane: its tail window. Banner, citation and busy
# tests all read this and nothing above it — scrollback is history for every
# one of them (a stale "esc to interrupt" above a live banner is not busy).
pane_tail() {
    printf '%s\n' "$1" | tail -n "$TAIL_LINES"
}

# The lines a banner may legitimately sit on: the tail window minus citations
# — the park test and the detector class must read the same set.
banner_candidates() {
    pane_tail "$1" | grep -vE -- "$CITATION_RE" || true
}

# Which banner family matched, as a label from a CLOSED set — the only thing
# the escalation mail or `--status` ever says about the screen. The pane is
# untrusted agent output and mail is a durable authenticated channel, so not
# one byte of pane text is emitted; the label survives MATCH_RE overrides by
# being classified independently, over only the lines that matched.
detector_class() {
    local lines
    lines="$(banner_candidates "$1" | grep -Ei -- "$MATCH_RE" || true)"
    if [ -n "${QUOTA_PARK_MATCH:-}" ]; then
        echo "custom-match"
    # Here-strings, never `printf ... | grep -qEi` pipelines (tk-zfjg9): `grep -q`
    # exits at its first match and SIGPIPEs the writer, which `pipefail` promotes
    # to 141 — so a matched line reads as unmatched and the label falls through to
    # the generic form, decided by nothing but how much text followed the match.
    elif grep -qEi -- 'your [a-z0-9 -]{0,24}limit' <<< "$lines"; then
        echo "possessive-limit"
    elif grep -qEi -- '(claude|codex|chatgpt|openai|anthropic|gemini|weekly|5-hour|plan) [a-z0-9 -]{0,16}limit' <<< "$lines"; then
        echo "named-provider-limit"
    elif grep -qEi -- '/usage-credits' <<< "$lines"; then
        echo "usage-credits"
    else
        echo "provider-limit"
    fi
}

# Validate every numeric knob (a stray "15s" or empty override breaks a
# different guard silently in each case), with a FLOOR: zero is reserved as
# "disable" only for CALL_TIMEOUT / SWEEP_BUDGET / ESCALATE_AFTER; elsewhere
# it defeats recovery (TAIL_LINES=0 detects nothing) and falls back too.
num_min() { num "${1:-}" && [ "$1" -ge "$2" ]; }
num_min "$CALL_TIMEOUT"   0 || CALL_TIMEOUT=15
num_min "$SWEEP_BUDGET"   0 || SWEEP_BUDGET=120
# Floor 1: `timeout -k 0` silently restores the soft bound; turning the bound
# off is CALL_TIMEOUT=0's job.
num_min "$KILL_AFTER"     1 || KILL_AFTER=5
num_min "$ESCALATE_AFTER" 0 || ESCALATE_AFTER=7200
num_min "$BACKOFF_BASE"   1 || BACKOFF_BASE=120
num_min "$BACKOFF_CAP"    1 || BACKOFF_CAP=900
num_min "$PEEK_LINES"     1 || PEEK_LINES=20
num_min "$TAIL_LINES"     1 || TAIL_LINES=12
num_min "$STALE_AFTER"    1 || STALE_AFTER=600

# --- The status surface -------------------------------------------------------
#   quota-park-nudge.sh --status [<session-id>]
# What the patrols read INSTEAD of peeking a pane: pane text is agent output,
# so a "saw a banner, hold the warrant" rule would hand every agent an off
# switch for its own recovery. The classification stays here and reaches the
# patrols only as CLOSED fields — yes/no/unknown, a detector_class label, a
# reason from a fixed set, integers from this order's own state. `unknown` is
# NOT folded into `no`: with no recent evidence about THAT session the patrol
# takes its normal warrant path. reasons: no-recent-sweep, not-swept,
# stale-episode, unsafe-session-id, foreign-state, state-dir-unavailable.
# `no` has to be earned per session (the coverage record), because a
# budget-deferred pass writes a fresh heartbeat without peeking its tail.

# The no-evidence line, SAME shape as a full one — a short line is how a
# missing field silently becomes whatever default the reader assumed.
status_unknown() {
    printf 'session=%s quota_park=unknown detector_class=unknown age_s=-1 parked_for=- attempts=0 unconfirmed=0 escalated=0 last_seen_age=-1 reason=%s\n' \
        "$1" "$2"
}

status_line() {
    local id="$1" path="$STATE_DIR/$1"
    local first_seen last_seen attempts unconfirmed escalated dclass verdict age seen_age human
    local cov_age reason=-
    # Timestamps are validated as timestamps, not merely as integers: a
    # future-dated `last_seen` would otherwise pass `num`, make `seen_age`
    # negative, and publish a park nothing has confirmed as a live one. See
    # ts_valid.
    first_seen="$(state_get "$path" first_seen)";   ts_valid "$first_seen" || first_seen=0
    last_seen="$(state_get "$path" last_seen)";     ts_valid "$last_seen"  || last_seen=0
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
    elif [ -e "$path" ] || [ -L "$path" ]; then
        if owned_file "$path"; then
            if [ "$seen_age" -lt 0 ] || [ "$seen_age" -ge "$STALE_AFTER" ]; then
                verdict=unknown; reason=stale-episode  # an episode nothing has confirmed lately
            else
                verdict=yes
            fi
        else
            # Something is at this session's state path and it is not ours: a
            # foreign file, a directory, a planted symlink. It is NOT an episode
            # — reading one out of it is how a file this order never wrote gets
            # to answer `quota_park=yes` and suppress a warrant — and it is not
            # the clean "no episode here" case either, because this order cannot
            # remove it to complete that verdict (owned_state_rm leaves it, by
            # design). Its own reason, rather than the `stale-episode` this used
            # to fall through to, which says an episode exists and nothing has
            # confirmed it lately — neither half of which is true here.
            verdict=unknown; reason=foreign-state
        fi
    else
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
    fi
    printf 'session=%s quota_park=%s detector_class=%s age_s=%s parked_for=%s attempts=%s unconfirmed=%s escalated=%s last_seen_age=%s reason=%s\n' \
        "$id" "$verdict" "$dclass" "$age" "$human" "$attempts" "$unconfirmed" "$escalated" "$seen_age" "$reason"
}

status_report() {
    local want="${1:-}" hb path base
    # Nothing to read and nothing to enumerate: the heartbeat, the coverage
    # record and every episode live in a directory this pass could not create or
    # cannot write. Answered in the surface's own vocabulary rather than by
    # exiting silently — see STATE_DIR_OK above. The header is still printed, so
    # the shape a consumer parses does not change with the failure, and the
    # enumerating form (no id) gets the same single `session=-` line: an empty
    # enumeration would say "no episodes are being tracked", which is a claim
    # about the city, not about this order's ability to look.
    #
    # The id is still validated before it is echoed. This branch runs BEFORE the
    # `safe_id` gate further down, and the requested id is caller-supplied: a
    # patrol passes whatever the session list gave it, and session metadata is
    # mutable. An id this order would refuse to name a file with is one it will
    # not put on the surface either, whatever else has failed — the closed-field
    # contract does not lapse because the state dir did.
    if [ "$STATE_DIR_OK" != "1" ]; then
        printf 'heartbeat_age=-1\nheartbeat_fresh=0\nstale_after=%s\n' "$STALE_AFTER"
        if [ -n "$want" ] && safe_id "$want"; then
            status_unknown "$want" state-dir-unavailable
        else
            status_unknown - state-dir-unavailable
        fi
        return 0
    fi
    # ts_valid, not num: a heartbeat dated in the future would otherwise read as
    # fresh forever, and a fresh heartbeat is the precondition for every verdict
    # below — a stopped order would go on vouching for the whole city.
    hb="$(state_get "$HEARTBEAT_FILE" last_run)"; ts_valid "$hb" || hb=0
    HB_AGE=-1; [ "$hb" -gt 0 ] && HB_AGE=$((NOW - hb))
    HB_FRESH=0
    if [ "$hb" -gt 0 ] && [ "$HB_AGE" -lt "$STALE_AFTER" ]; then HB_FRESH=1; fi
    printf 'heartbeat_age=%s\nheartbeat_fresh=%s\nstale_after=%s\n' "$HB_AGE" "$HB_FRESH" "$STALE_AFTER"
    if [ -n "$want" ]; then
        # An id this order would refuse to write state for is one it will not read
        # state for either — same test, same reason, and the caller gets the same
        # `unknown` it gets for anything else this order cannot speak to.
        if ! safe_id "$want"; then
            status_unknown - unsafe-session-id
            return 0
        fi
        status_line "$want"
        return 0
    fi
    # No id: every episode this order is currently tracking. Same ownership test
    # the prune and the removal paths use, so a foreign file dropped in the
    # directory is not listed as a parked session — asked about BY id it answers
    # `unknown`/`foreign-state`, but it is not one of this order's episodes and
    # does not belong in an enumeration of them.
    for path in "$STATE_DIR"/*; do
        owned_file "$path" || continue
        base="${path##*/}"
        safe_id "$base" || continue
        status_line "$base"
    done
}

# Only --status is special; anything else falls through to a normal sweep.
if [ "${1:-}" = "--status" ]; then
    status_report "${2:-}"
    exit 0
fi

# The sweep genuinely cannot proceed without the state dir (every park would
# re-detect as new each cycle). Stop LOUDLY, exit 0 — nothing to do is not a
# crash.
if [ "$STATE_DIR_OK" != "1" ]; then
    echo "quota-park-nudge: state dir unavailable ($(sanitize_display "$STATE_DIR")) — no sweep this pass; --status reports unknown/state-dir-unavailable"
    exit 0
fi

# --- Pattern overrides, validated before the sweep uses them -------------------
# grep answers a malformed ERE with rc 2, which every test below reads as "no
# match": a bad QUOTA_PARK_MATCH would report every pane CLEAN (recovery off
# city-wide, silently); a bad BUSY nudges mid-turn; a bad EXCLUDE ignores the
# escape hatch. Each falls back to its own default, loudly, in the direction
# that keeps recovery working.
valid_ere() {
    local rc=0
    # Zero bytes of input by redirect, not by `printf '' |` (tk-zfjg9). Nothing
    # can SIGPIPE here — printf is finished before grep reads — but the pipe form
    # is the shape the doctor check bans outright, and an exception list is a
    # worse guard than a rule with none. `< /dev/null` is the same empty input:
    # no line ever matches, so rc is 1 for a valid ERE and 2 for a malformed one,
    # which is exactly what the caller reads.
    grep -Eq -- "${1:-}" </dev/null >/dev/null 2>&1 || rc=$?
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

# What bound this host can enforce, probed once (`-k` is GNU/uutils/busybox):
#   2 hard (timeout -k) · 1 soft (SIGTERM only) · 0 none (no timeout(1)).
BOUND_MODE=0
if command -v timeout >/dev/null 2>&1; then
    if timeout -k 1 1 true >/dev/null 2>&1; then BOUND_MODE=2; else BOUND_MODE=1; fi
fi

# Every gc call goes through here. Guarantees: (1) a bound, HARD where the
# host allows (a wedged gc is the process least likely to service SIGTERM);
# expiry is a non-zero rc (124, or 128+n when the kill lands) that falls into
# the caller's existing failure branch. (2) stdin CLOSED — the session loop
# reads its work list on fd 0, and a child that consumed it would silently
# truncate the sweep. No timeout(1) degrades to an unbounded call.
run_bounded() {
    if [ "$CALL_TIMEOUT" -le 0 ] || [ "$BOUND_MODE" -eq 0 ]; then
        "$@" </dev/null
    elif [ "$BOUND_MODE" -eq 2 ]; then
        timeout -k "$KILL_AFTER" "$CALL_TIMEOUT" "$@" </dev/null
    else
        timeout "$CALL_TIMEOUT" "$@" </dev/null
    fi
}

# Said once per pass on a soft-bound host: the summary's numbers are then a
# floor, not a full pass.
if [ "$CALL_TIMEOUT" -gt 0 ] && [ "$BOUND_MODE" -eq 1 ]; then
    echo "quota-park-nudge: this host's timeout(1) has no -k — call bounds are SIGTERM-only, so a gc call that ignores it is effectively unbounded"
fi

# True once the pass outran SWEEP_BUDGET (0 = none); checked per session so a
# slow sweep stops at a session boundary.
sweep_expired() {
    [ "$SWEEP_BUDGET" -gt 0 ] || return 1
    [ "$(( $(date +%s) - NOW ))" -ge "$SWEEP_BUDGET" ]
}

checked=0; parked=0; nudged=0; skipped=0; unreadable=0; rejected=0; unconfirmed_now=0
state_failed=0
last_attempted=""
covered_now=""

# Vouch for one session: this pass classified it AND the verdict is readable
# back out of the state dir (see write_state_vouched).
vouch() { covered_now="$covered_now$1 $NOW"$'\n'; }

# Persist an episode; vouch only if the write landed. A parked session whose
# state write failed must fall to unknown/not-swept, never publish as `no` —
# counted and logged, because silently uncovering a session looks identical
# to never having reached it.
write_state_vouched() {
    if write_state "$@"; then
        vouch "$id"
        return 0
    fi
    state_failed=$((state_failed + 1))
    echo "quota-park-nudge: state write FAILED for $alias ($id) — not vouched for; --status reports unknown until it succeeds"
    return 1
}

# That a pass RAN. Written only where a pass completed, so a disabled or
# wedged order's evidence goes stale rather than vouching city-wide.
write_heartbeat() {
    printf 'last_run=%s\nchecked=%s\nparked=%s\nnudged=%s\ndeferred=%s\n' \
        "$NOW" "$checked" "$parked" "$nudged" "$skipped" | write_owned "$HEARTBEAT_FILE" || true
}

# WHICH sessions a pass classified — the record `--status` needs before it
# may answer `no`. Merged, this pass first (wins the dedup), entries past
# STALE_AFTER dropped, so the file stays bounded by live-session count.
write_coverage() {
    local cutoff=$((NOW - STALE_AFTER)) prior=""
    if owned_file "$COVERAGE_FILE"; then
        prior="$(cat "$COVERAGE_FILE" 2>/dev/null || true)"
    fi
    # The marker line carried in from `prior` is dropped by the same filter that
    # drops any other malformed record (it is one field, not two) and written
    # back fresh by write_owned.
    printf '%s%s\n' "$covered_now" "$prior" \
        | awk -v cutoff="$cutoff" \
            'NF == 2 && $2 ~ /^[0-9]+$/ && $2 + 0 >= cutoff + 0 && !seen[$1]++ { print $1, $2 }' \
        | write_owned "$COVERAGE_FILE" || true
}

# Only live sessions. Keyed on .state, NEVER .running (null during controller
# churn — a filter on it drops exactly the live sessions). `attached` is
# skipped: a human is at that pane. @tsv, not interpolation: jq escapes
# tab/newline inside @tsv fields, so mutable session metadata cannot forge a
# row (an alias with a newline once wrote state outside STATE_DIR).
sessions=$(run_bounded gc session list --json 2>/dev/null \
    | jq -r '.sessions[]? | select(.state == "active" and (.attached // false) == false)
             | [.id, (.alias // .session_name // .id)] | @tsv' 2>/dev/null) || exit 0
# An empty list is a complete pass over nothing, not a failure.
[ -n "$sessions" ] || { write_heartbeat; echo "quota-park-nudge: 0 checked, 0 parked, 0 nudged"; exit 0; }

# Round-robin cursor: the list order is stable and each hung peek costs a
# CALL_TIMEOUT out of SWEEP_BUDGET, so a fixed start would pay the same slow
# prefix every pass and never reach the tail. Resume AFTER the last session
# the previous pass attempted; rotating past the end is the identity.
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
    # takes. Whether this pass may VOUCH for it — the record `--status` needs
    # before it answers `no` — is decided per branch: for a clean or excluded
    # session the verdict is "no episode" and removing the file completes it, so
    # the vouch goes with the removal; for a parked one the verdict lives IN the
    # state file, so it waits on that write landing (write_state_vouched).
    # Nothing is vouched before the unreadable branch above: a peek that failed
    # classified nothing.

    # Parked = a bare provider banner at the bottom of an idle pane. Busy,
    # cited, or scrolled-up all mean not parked. Clearing the state file is what
    # ends an episode: a recovered agent starts the next block from attempt 1.
    #
    # Both halves read the same current region (pane_tail): a busy marker up in
    # the scrollback is a finished turn, not a running one, and letting it veto
    # a live banner below it is how a genuinely parked session gets vouched for
    # as clean.
    #
    # Redirected from a process substitution, never `pane_tail ... | grep -qEi`
    # (tk-zfjg9). `grep -q` exits at its first match and SIGPIPEs the writer,
    # which `pipefail` promotes to the pipeline's status — and here that lands on
    # the FAIL-OPEN side: a 141 from the banner half negates to true, so a session
    # that IS parked has its state file removed and is vouched for as clean. A
    # process substitution keeps the writer's death out of the status entirely, so
    # only grep's own answer decides. A pane tail is exactly the payload size the
    # race needs.
    if grep -qEi -- "$BUSY_RE" < <(pane_tail "$pane") \
        || ! grep -qEi -- "$MATCH_RE" < <(banner_candidates "$pane"); then
        owned_state_rm "$state"
        vouch "$id"
        continue
    fi

    parked=$((parked + 1))
    # An excluded alias is one this order does not act on AT ALL: no nudge, and no
    # state file either, so `--status` reports it as `no` and the patrols fall
    # back to their own judgment instead of deferring to a recovery that was
    # switched off for this session. Counted as parked in the summary, because it
    # is — the escape hatch suppresses the action, not the observation.
    # Here-string, not a pipeline — see the tk-zfjg9 note on detector_class.
    if [ -n "$EXCLUDE_RE" ] && grep -qEi -- "$EXCLUDE_RE" <<< "$alias"; then
        # Any episode from BEFORE the exclusion goes with it. An alias can be
        # added to QUOTA_PARK_EXCLUDE while a park is already being tracked, and
        # a state file left behind then keeps answering for a session this order
        # has stopped acting on: `yes` while the last sighting is still fresh —
        # a patrol deferring its warrant to a recovery that is switched off for
        # exactly that session — and `unknown` afterwards. Neither is the
        # contract above. `no` is, and that needs the file gone.
        owned_state_rm "$state"
        vouch "$id"
        echo "quota-park-nudge: $alias parked (excluded, not nudged)"
        continue
    fi

    # Classified once per parked session, from the closed set, and persisted with
    # the episode: this is what the status surface hands a patrol, and — with the
    # escalation mail — the only thing anywhere outside this script that says
    # anything about what was on the screen.
    dclass="$(detector_class "$pane")"

    # Missing, non-numeric, or dated in the FUTURE reads back as "start of
    # episode" — a truncated state file (crash mid-write) must not abort the
    # sweep for every session after this one, and losing an episode's counters
    # only costs one nudge. A future timestamp is invalid for the reason
    # ts_valid gives: it cannot be a record of anything this order did, and each
    # of these fields defeats a different guard while it stands.
    first_seen="$(state_get "$state" first_seen)"; ts_valid "$first_seen" || first_seen="$NOW"
    last_nudge="$(state_get "$state" last_nudge)"; ts_valid "$last_nudge" || last_nudge=0
    attempts="$(state_get "$state" attempts)";     num "$attempts"   || attempts=0
    # Deliveries we could not confirm, kept apart from the ones we could: see
    # the nudge branches below. Absent from a state file an older version wrote,
    # which reads as zero — the same as a fresh episode.
    unconfirmed="$(state_get "$state" unconfirmed)"; num "$unconfirmed" || unconfirmed=0
    # Pacing keys on the last delivery ATTEMPT, not the last confirmed one.
    # Falls back to last_nudge so a state file from before this field existed
    # still paces on its confirmed nudge instead of reading as never-tried.
    last_try="$(state_get "$state" last_try)"; ts_valid "$last_try" || last_try="$last_nudge"
    # Normalized to the same closed set on the way IN that status_line applies on
    # the way out, because the escalation test below is `[ -z "$escalated" ]`:
    # only `1` (a mail we saw sent) and `unconfirmed` (one whose bound expired
    # mid-send) mean "already escalated", and ANY other non-empty value would
    # read as escalated and suppress the mail for the rest of the episode. A
    # persisted `escalated=0` is the obvious case — it says NOT escalated and
    # means the opposite — but so does any leftover from a hand edit or a
    # version that spelled the field differently. Suppressed silently, and for
    # exactly the multi-hour park the escalation exists to report.
    escalated="$(state_get "$state" escalated)"
    case "$escalated" in 1 | unconfirmed) ;; *) escalated="" ;; esac
    age=$((NOW - first_seen))
    tries=$((attempts + unconfirmed))

    if [ "$tries" -gt 0 ] && [ $((NOW - last_try)) -lt "$(backoff_for "$tries")" ]; then
        # Still blocked, still inside the backoff window — say nothing, wait. The
        # sighting is still recorded: a session nobody nudges this cycle is one
        # this pass nonetheless confirmed parked, and `--status` reads last_seen.
        write_state_vouched "$state" "$first_seen" "$last_nudge" "$last_try" "$attempts" "$unconfirmed" "$escalated" "$NOW" "$dclass" || true
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

    write_state_vouched "$state" "$first_seen" "$last_nudge" "$last_try" "$attempts" "$unconfirmed" "$escalated" "$NOW" "$dclass" || true
done <<< "$sessions"

# Where the next pass starts, and the record that this one ran. Written together,
# after the sweep: the cursor is only meaningful once the loop has decided how
# far it got, and a heartbeat written earlier would claim a pass that had not
# finished.
if [ -n "$last_attempted" ]; then
    printf 'session=%s\n' "$last_attempted" | write_owned "$CURSOR_FILE" || true
fi
write_coverage
write_heartbeat

# Prune: only files no cycle has touched in a week (sessions closed/renamed
# while parked), by the SAME ownership test as every removal path. Glob, not
# find; aged from the record inside, not mtime — POSIX everywhere. The two
# globs cover dotted names; owned_state_rm's STATE_DIR check is the depth
# guard.
PRUNE_AFTER=604800   # 7 days, in seconds

# Age of an owned episode file, from its own record (last_seen, else
# first_seen; neither = corrupt, reported ancient so it gets collected).
owned_state_age() {
    local ts
    ts="$(state_get "$1" last_seen)"
    ts_valid "$ts" || ts="$(state_get "$1" first_seen)"
    ts_valid "$ts" || { echo $((PRUNE_AFTER + 1)); return 0; }
    echo $((NOW - ts))
}

prune_stale_state() {
    local path base stamp
    for path in "$STATE_DIR"/* "$STATE_DIR"/.*; do
        # An unmatched glob arrives as its own literal pattern, and `.` / `..`
        # arrive from the second one; -f drops all three.
        [ -f "$path" ] && [ ! -L "$path" ] || continue
        base="${path##*/}"
        # This order's own abandoned temp files — a pass killed between `mktemp`
        # and the rename in write_atomic. Unmistakably ours by name, so they are
        # collected here rather than accumulating in the runtime directory
        # forever; `safe_id` would otherwise skip them for their leading dot,
        # which is the same property that keeps them out of `--status`. The name
        # carries the pass's own timestamp, so they age without a `stat`: a temp
        # file a CONCURRENT pass is writing right now must not be removed out
        # from under its rename, and one whose stamp is unreadable is left for a
        # later pass rather than guessed at.
        case "$base" in
            .qpn-tmp.*)
                stamp="${base#.qpn-tmp.}"; stamp="${stamp%%.*}"
                if ts_valid "$stamp" && [ "$((NOW - stamp))" -gt "$PRUNE_AFTER" ]; then
                    rm -f "$path"
                fi
                continue
                ;;
        esac
        owned_file "$path" || continue
        [ "$(owned_state_age "$path")" -gt "$PRUNE_AFTER" ] || continue
        owned_state_rm "$path"
    done
}
prune_stale_state

# Everything the sweep could not conclude is named in the summary — a short
# sweep must not read as a complete one.
unread=""
[ "$unreadable" -gt 0 ] && unread=", $unreadable unreadable"
unsafe=""
[ "$rejected" -gt 0 ] && unsafe=", $rejected rejected (unsafe session id)"
deferred=""
[ "$skipped" -gt 0 ] && deferred=", $skipped deferred (sweep budget ${SWEEP_BUDGET}s)"
unconf=""
[ "$unconfirmed_now" -gt 0 ] && unconf=", $unconfirmed_now unconfirmed (bound expired mid-delivery)"
# A session detected and acted on whose verdict did not persist. Named here for
# the same reason as the rest: it is coverage this pass did not achieve, and a
# sweep that could not record what it found must not read as one that found
# nothing.
statefail=""
[ "$state_failed" -gt 0 ] && statefail=", $state_failed state write failed (not vouched for)"
echo "quota-park-nudge: $checked checked, $parked parked, $nudged nudged$unconf$unread$unsafe$deferred$statefail"
