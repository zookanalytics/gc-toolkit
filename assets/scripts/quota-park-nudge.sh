#!/usr/bin/env bash
# quota-park-nudge — resume agents parked at a provider quota banner
# (tk-al95k: a quota window closing mid-turn leaves the session state=active,
# idle under the banner, with nothing to wake it).
# Job: poll every live session's pane; nudge the ones showing a limit banner.
# A nudge is the ONLY action — never kill, never file a warrant. Signatures
# are provider-agnostic (extend via $QUOTA_PARK_MATCH); recovery polls rather
# than sleeping until the banner's stated reset (a manual reset lands early).
# Callers: the quota-park-nudge exec order (3m cadence); the deacon/witness
# patrols read the closed-field `--status` surface INSTEAD of the pane.
# See docs/quota-park-recovery.md.
set -euo pipefail

# Pane lines captured, and the tail window that counts as the CURRENT screen
# (a real park ends with the banner; anything above the tail is history).
PEEK_LINES="${QUOTA_PARK_PEEK_LINES:-20}"
TAIL_LINES="${QUOTA_PARK_TAIL_LINES:-12}"

# Banner signatures — one ERE, alternatives per family:
#   possessive      (hit|reached|exceeded) your <quota-noun> limit
#   named-provider  (claude|codex|chatgpt|openai|anthropic|gemini|weekly|
#                   5-hour|plan) [...] limit (reached|exceeded)
#   usage-credits   /usage-credits
#   reset-clause    your <quota-noun> limit will reset
# Every alternative anchors on something only a PROVIDER says — possessive +
# quota NOUN, never a bare "rate limit" (a tool error must not read as a
# park). New providers go in $QUOTA_PARK_MATCH. Held as ONE single-quoted
# literal: the suite reads this line out of the script, and an ERE interval
# inside ${VAR:-default} would close the expansion early.
DEFAULT_MATCH='(hit|reached|exceeded) your ([a-z0-9()./-]+ ){0,3}(session|usage|weekly|monthly|daily|hourly|5-hour|plan|subscription|quota|credit|message)s? limit|(claude|codex|chatgpt|openai|anthropic|gemini|weekly|5-hour|plan) (([a-z0-9()./-]+ ){0,3}(session|usage|weekly|monthly|daily|hourly|5-hour|plan|subscription|quota|credit|message)s? )?limit (reached|exceeded)|/usage-credits|your ([a-z0-9()./-]+ ){0,3}(session|usage|weekly|monthly|daily|hourly|5-hour|plan|subscription|quota|credit|message)s? limit will reset'
MATCH_RE="${QUOTA_PARK_MATCH:-$DEFAULT_MATCH}"

# Busy markers — an agent mid-turn is not parked (both CLIs print "esc to
# interrupt" while working).
DEFAULT_BUSY='esc to interrupt|ctrl.{0,2}c to (stop|interrupt)'
BUSY_RE="${QUOTA_PARK_BUSY:-$DEFAULT_BUSY}"

# A QUOTED banner is a citation, not a banner: a double quote anywhere marks
# one (providers never print any); single/smart quotes and backticks count
# only as an OPENING delimiter (the apostrophe in "You've" is that character).
# Alternation, not a bracket class (multibyte in [...] is a byte set under C).
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

# Ownership marker: first line of every file this order writes; every
# read/delete/prune path tests it before treating a file as its own (shape is
# a guess). A label, not an authenticator.
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

# Replace a file in STATE_DIR atomically, never writing THROUGH what is
# there (a planted symlink/FIFO is replaced, not followed); a DIRECTORY is
# refused — `mv file dir` would swallow the episode while reporting success.
# Temp names are dot-prefixed and carry the pass timestamp for the prune.
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
    # Here-strings, never pipes into grep -q (tk-zfjg9: SIGPIPE + pipefail
    # makes a matched line read unmatched).
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

# Validate every numeric knob (a stray "15s" breaks a different guard
# silently in each case); zero means "disable" only where documented.
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

# --- The status surface: quota-park-nudge.sh --status [<session-id>] ---------
# What the patrols read INSTEAD of peeking a pane (pane text is agent output;
# reading it directly would hand every agent an off switch for its own
# recovery). CLOSED fields only: yes/no/unknown, a detector_class label, a
# reason from {no-recent-sweep, not-swept, stale-episode, unsafe-session-id,
# foreign-state, state-dir-unavailable}, integers from this order's state.
# `unknown` is never folded into `no`, and `no` is earned per session (the
# coverage record) — a budget-deferred pass heartbeats without peeking.

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
    # Timestamps validated as timestamps (see ts_valid), not merely integers.
    first_seen="$(state_get "$path" first_seen)";   ts_valid "$first_seen" || first_seen=0
    last_seen="$(state_get "$path" last_seen)";     ts_valid "$last_seen"  || last_seen=0
    attempts="$(state_get "$path" attempts)";       num "$attempts"    || attempts=0
    unconfirmed="$(state_get "$path" unconfirmed)"; num "$unconfirmed" || unconfirmed=0
    # A 0/1 flag on the way out; `unconfirmed` maps to 1 — consumers define
    # only escalated=1, and the distinction stays in the state file.
    escalated="$(state_get "$path" escalated)"
    case "$escalated" in 1 | unconfirmed) escalated=1 ;; *) escalated=0 ;; esac
    # Constrained to the closed set on the way OUT too (hand edits, old versions).
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
            # Something not ours at this session's state path: not an episode, and not
            # the clean no-episode case either — its own reason.
            verdict=unknown; reason=foreign-state
        fi
    else
        # No episode. Only evidence of "not parked" if this order actually LOOKED
        # recently — a budget-deferred pass writes a fresh heartbeat without
        # peeking its tail, so `no` is conditional on the per-session coverage.
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
    # State dir unavailable: answer in the surface's own vocabulary, same
    # shape, id still validated before it is echoed (caller-supplied).
    if [ "$STATE_DIR_OK" != "1" ]; then
        printf 'heartbeat_age=-1\nheartbeat_fresh=0\nstale_after=%s\n' "$STALE_AFTER"
        if [ -n "$want" ] && safe_id "$want"; then
            status_unknown "$want" state-dir-unavailable
        else
            status_unknown - state-dir-unavailable
        fi
        return 0
    fi
    # ts_valid, not num: a future-dated heartbeat would read fresh forever.
    hb="$(state_get "$HEARTBEAT_FILE" last_run)"; ts_valid "$hb" || hb=0
    HB_AGE=-1; [ "$hb" -gt 0 ] && HB_AGE=$((NOW - hb))
    HB_FRESH=0
    if [ "$hb" -gt 0 ] && [ "$HB_AGE" -lt "$STALE_AFTER" ]; then HB_FRESH=1; fi
    printf 'heartbeat_age=%s\nheartbeat_fresh=%s\nstale_after=%s\n' "$HB_AGE" "$HB_FRESH" "$STALE_AFTER"
    if [ -n "$want" ]; then
        # An id this order refuses to write state for is not read either.
        if ! safe_id "$want"; then
            status_unknown - unsafe-session-id
            return 0
        fi
        status_line "$want"
        return 0
    fi
    # No id: enumerate owned episodes only (a foreign file is not one).
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
    # Empty input by redirect, never a pipe into grep -q (tk-zfjg9): rc 1 =
    # valid ERE, 2 = malformed.
    grep -Eq -- "${1:-}" </dev/null >/dev/null 2>&1 || rc=$?
    [ "$rc" -le 1 ]
}
if ! valid_ere "$MATCH_RE"; then
    echo "quota-park-nudge: QUOTA_PARK_MATCH is not a valid ERE — using the default detector"
    MATCH_RE="$DEFAULT_MATCH"
    # Fallen back, so detector_class must not label matches custom-match.
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

# Every gc call goes through here: (1) a bound, HARD (`timeout -k`) where
# the host allows — expiry is a non-zero rc (124 / 128+n) handled by the
# caller's failure branch; (2) stdin CLOSED — the session loop reads its work
# list on fd 0. No timeout(1) degrades to an unbounded call.
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
    # The carried-in marker line is one field, so the filter drops it.
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
    # Matched against the id FIELD, never as a substring.
    cursor_at="$(printf '%s\n' "$sessions" | awk -F'\t' -v c="$cursor" '$1 == c { print NR; exit }')"
    session_count="$(printf '%s\n' "$sessions" | awk 'END { print NR }')"
    if num "$cursor_at" && num "$session_count" && [ "$cursor_at" -lt "$session_count" ]; then
        sessions="$(printf '%s\n' "$sessions" | tail -n +"$((cursor_at + 1))"
                    printf '%s\n' "$sessions" | head -n "$cursor_at")"
    fi
fi

while IFS=$'\t' read -r id alias; do
    [ -n "${id:-}" ] || continue
    # An id we cannot safely name is not touched at all; counted, not silent.
    if ! safe_id "$id"; then rejected=$((rejected + 1)); continue; fi
    # Out of budget: defer the rest to the next cycle, counted.
    if sweep_expired; then skipped=$((skipped + 1)); continue; fi
    # Cursor-attempted BEFORE the peek — the peek is the call that hangs.
    last_attempted="$id"
    # Every downstream print/log/mail uses the bounded alias.
    alias="$(sanitize_display "${alias:-$id}")"
    state="$STATE_DIR/$id"
    checked=$((checked + 1))

    # A failed/empty peek proves nothing, and the clean branch DELETES the
    # episode — only a successful peek may end one. Keep state; retry in 3m.
    peek_rc=0
    pane=$(run_bounded gc session peek "$id" --lines "$PEEK_LINES" 2>/dev/null) || peek_rc=$?
    if [ "$peek_rc" -ne 0 ] || [ -z "$pane" ]; then
        unreadable=$((unreadable + 1))
        echo "quota-park-nudge: pane unreadable for $alias ($id) (peek rc=$peek_rc) — episode state kept"
        continue
    fi

    # Pane read: a verdict follows. Whether this pass may VOUCH is per branch.

    # Parked = a bare banner in the tail of an idle pane; busy/cited/scrolled-up
    # are not parked, and clearing the state file is what ends an episode.
    # Process substitutions, never pipes into grep -q (tk-zfjg9): a SIGPIPE'd
    # writer under pipefail would land on the FAIL-OPEN side here.
    if grep -qEi -- "$BUSY_RE" < <(pane_tail "$pane") \
        || ! grep -qEi -- "$MATCH_RE" < <(banner_candidates "$pane"); then
        owned_state_rm "$state"
        vouch "$id"
        continue
    fi

    parked=$((parked + 1))
    # Excluded alias: observed (counted parked) but not acted on — no nudge and
    # no state file, so --status answers `no` and the patrols use their own
    # judgment. An episode from BEFORE the exclusion goes with it.
    if [ -n "$EXCLUDE_RE" ] && grep -qEi -- "$EXCLUDE_RE" <<< "$alias"; then
        owned_state_rm "$state"
        vouch "$id"
        echo "quota-park-nudge: $alias parked (excluded, not nudged)"
        continue
    fi

    # Classified once per parked session, from the closed set.
    dclass="$(detector_class "$pane")"

    # Missing/garbage/future fields read back as start-of-episode defaults — a
    # truncated state file must not abort the sweep, and each future timestamp
    # defeats a different guard (see ts_valid).
    first_seen="$(state_get "$state" first_seen)"; ts_valid "$first_seen" || first_seen="$NOW"
    last_nudge="$(state_get "$state" last_nudge)"; ts_valid "$last_nudge" || last_nudge=0
    attempts="$(state_get "$state" attempts)";     num "$attempts"   || attempts=0
    # Deliveries we could not confirm, kept apart from confirmed ones.
    unconfirmed="$(state_get "$state" unconfirmed)"; num "$unconfirmed" || unconfirmed=0
    # Pacing keys on the last delivery ATTEMPT; falls back to last_nudge.
    last_try="$(state_get "$state" last_try)"; ts_valid "$last_try" || last_try="$last_nudge"
    # Normalized on the way IN: only `1` and `unconfirmed` mean escalated —
    # any other leftover value would silently suppress the mail forever.
    escalated="$(state_get "$state" escalated)"
    case "$escalated" in 1 | unconfirmed) ;; *) escalated="" ;; esac
    age=$((NOW - first_seen))
    tries=$((attempts + unconfirmed))

    if [ "$tries" -gt 0 ] && [ $((NOW - last_try)) -lt "$(backoff_for "$tries")" ]; then
        # Inside the backoff window: say nothing, but still record the sighting.
        write_state_vouched "$state" "$first_seen" "$last_nudge" "$last_try" "$attempts" "$unconfirmed" "$escalated" "$NOW" "$dclass" || true
        continue
    fi

    # The nudge text deliberately avoids every phrase in MATCH_RE: it lands in
    # the pane we read next cycle.
    msg="Provider block may have cleared after $(duration "$age") — resume: re-check your hook (gc hook --claim --json) or continue your patrol loop. If still blocked, ignore this; it repeats until you are back."
    # --delivery immediate: the default idle detector already believes a parked
    # session is fine.
    nudge_rc=0
    run_bounded gc session nudge --delivery immediate "$id" "$msg" >/dev/null 2>&1 || nudge_rc=$?
    # Fall back to the plain form ONLY on a fast usage error (older gc). A
    # timeout/signal is NOT that case — the nudge may already have landed, and
    # a retry would deliver two resume messages.
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
        # AMBIGUOUS: paced as an attempt (advances last_try and the backoff
        # exponent) without claiming a delivery we did not see land.
        unconfirmed=$((unconfirmed + 1))
        last_try="$NOW"
        unconfirmed_now=$((unconfirmed_now + 1))
        echo "quota-park-nudge: nudge UNCONFIRMED (rc=$nudge_rc) for $alias ($id), parked $(duration "$age"), paced as attempt $((attempts + unconfirmed))"
    else
        # Fast rejection: nothing delivered, nothing paced; retry in 3m.
        echo "quota-park-nudge: nudge FAILED (rc=$nudge_rc) for $alias ($id), parked $(duration "$age")"
    fi

    unconf_note=""
    [ "$unconfirmed" -gt 0 ] && unconf_note=" (plus $unconfirmed unconfirmed)"
    # Any escalation marker suppresses the next one (1 or unconfirmed).
    if [ "$ESCALATE_AFTER" -gt 0 ] && [ -z "$escalated" ] && [ "$age" -ge "$ESCALATE_AFTER" ]; then
        # No pane text in the body — see detector_class.
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
            # AMBIGUOUS: recorded as sent — mail is durable, and a bound expiring
            # after the Dolt commit would otherwise mail the mayor twice per park.
            escalated=unconfirmed
            echo "quota-park-nudge: escalation mail UNCONFIRMED (rc=$mail_rc) for $alias ($id) — not resent this episode"
        else
            # Fast rejection: retried next cycle; cannot duplicate.
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
        # -f drops the unmatched-glob literal and . / .. from the second glob.
        [ -f "$path" ] && [ ! -L "$path" ] || continue
        base="${path##*/}"
        # This order's own abandoned temp files (a pass killed mid-write), aged
        # from the timestamp in the name; a concurrent pass's fresh temp survives.
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
# Coverage this pass did not achieve is named too.
statefail=""
[ "$state_failed" -gt 0 ] && statefail=", $state_failed state write failed (not vouched for)"
echo "quota-park-nudge: $checked checked, $parked parked, $nudged nudged$unconf$unread$unsafe$deferred$statefail"
