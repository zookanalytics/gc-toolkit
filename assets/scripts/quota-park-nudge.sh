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

# Lines of pane to capture, and how many of those are the CURRENT screen. A real
# park ends with the banner: below it there is only TUI chrome (prompt box,
# status line), 6-8 lines in both CLIs. Anything further up is history — an
# agent that *mentioned* a limit and kept working, or a working indicator from a
# turn that has already ended. Every classification — banner, citation, busy —
# reads the tail window and nothing above it (see pane_tail). The capture stays
# wider than that window on purpose: it is the outer bound on what one peek
# costs, and it leaves TAIL_LINES room to be raised on a host with taller chrome
# without also having to raise PEEK_LINES.
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
# The possessive is not enough on its own, which is the THIRD time this class
# has been paid for: a tool error says "You have exceeded your API rate limit"
# and "Your API rate limit will reset at 18:00 UTC" — both possessive, both
# idle, neither a quota park, and both matched the bounded-gap form this
# replaces (reproduced during review). So the NOUN the limit is named with
# carries the anchor too: a provider block is on a session/usage/weekly/plan
# (etc.) limit, a tool error is on a *rate* limit. The gap between "your" and
# that noun is counted in WORDS rather than characters, which also gives the
# noun a left word boundary for free — a character run lets a whitelisted noun
# match the tail of an unrelated word.
#
# The named-provider alternative takes the same noun list, for the same reason
# in its own direction: `Error: OpenAI API rate limit exceeded` carries a
# provider name in front of an ordinary rate-limit error. The noun is optional
# there and only there, because the plan-period subjects (`weekly limit
# reached`) name the quota in the subject itself.
#
# The cost of the narrowing is a provider that says only "You've hit your
# limit", with no noun at all: that goes in $QUOTA_PARK_MATCH, or adds its noun
# to the three lists below. That is the deliberate trade — an unmatched banner
# costs one un-nudged park, a matched tool error costs a working session nudged
# on the recovery cadence forever.
#
# Held in a plain variable first: an ERE interval like {0,3} inside a
# ${VAR:-default} would close the expansion at its own brace and silently ship
# a truncated pattern. Kept as ONE single-quoted literal rather than composed
# from a noun variable, because the suite reads this line out of the script to
# assert the nudge text cannot match it; a composed pattern would extract as
# an unexpanded `$VAR` and that assertion would pass vacuously.
DEFAULT_MATCH='(hit|reached|exceeded) your ([a-z0-9()./-]+ ){0,3}(session|usage|weekly|monthly|daily|hourly|5-hour|plan|subscription|quota|credit|message)s? limit|(claude|codex|chatgpt|openai|anthropic|gemini|weekly|5-hour|plan) (([a-z0-9()./-]+ ){0,3}(session|usage|weekly|monthly|daily|hourly|5-hour|plan|subscription|quota|credit|message)s? )?limit (reached|exceeded)|/usage-credits|your ([a-z0-9()./-]+ ){0,3}(session|usage|weekly|monthly|daily|hourly|5-hour|plan|subscription|quota|credit|message)s? limit will reset'
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
#
# The two halves are anchored differently on purpose. A double quote is a
# citation marker ANYWHERE on the line: providers never print one, so its mere
# presence is proof the line is a report about a banner. The single quote,
# smart single quotes and the backtick cannot be treated that way — the
# apostrophe inside "You've" and "you're" is the same character, and rejecting
# it unanchored would drop every real Claude and Codex banner and switch this
# order off entirely. So they count only as an OPENING DELIMITER: at the start
# of the line, after leading whitespace and any blockquote marker. Found by
# review: `'You've hit your usage limit'` and the backtick-quoted form both
# survived the double-quote-only filter and read as parks, which is the same
# live false positive quoting was added for, in a different set of quotes.
# The typographic single quotes below are pattern DATA, not quoting: they are
# what a terminal renders a report's quotes as, and matching them is the whole
# point of this line. shellcheck reads them as a mistyped ASCII quote.
# shellcheck disable=SC1112
CITATION_RE='^[[:space:]]*(>|\||▎|│|┃)*[[:space:]]*('\''|‘|’|`)|^[[:space:]]*(>|\||▎|│|┃)|"|“|”'

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

# How long after CALL_TIMEOUT a call that ignored the timeout's SIGTERM gets
# before SIGKILL. `timeout N` on its own is a SOFT bound: it signals, then waits
# for a child that is free to ignore the signal — verified with `timeout 1 bash
# -c 'trap "" TERM; sleep 5'`, which ran the full 5s. A hung `gc` is exactly the
# process least likely to be in a state to handle a signal politely, so the
# bound that is supposed to keep one wedged call from stranding the sweep is
# precisely the one that can fail to. `timeout -k` adds the hard half; hosts
# whose timeout(1) lacks it say so once per pass (see BOUND_MODE below) rather
# than pretending to a bound they do not have.
KILL_AFTER="${QUOTA_PARK_KILL_AFTER:-5}"

CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
DEFAULT_STATE_DIR="${CITY:+$CITY/.gc/runtime}"
DEFAULT_STATE_DIR="${DEFAULT_STATE_DIR:-${TMPDIR:-/tmp}/gc}/quota-park"
STATE_DIR="${QUOTA_PARK_STATE_DIR:-$DEFAULT_STATE_DIR}"
# Recorded, NOT exited on. Every file this order reads or writes lives here, so
# a state dir it cannot create or write is the end of the sweep — but it is not
# the end of the `--status` contract, and the two used to be the same line: a
# bare `mkdir -p … || exit 0` ran before the `--status` branch below, so an
# unwritable or uncreatable state dir made the surface exit 0 with NO OUTPUT AT
# ALL. Reproduced during review with QUOTA_PARK_STATE_DIR pointed under a
# regular file. A patrol parsing that silence finds no `quota_park=` field to
# read; the closed-field surface exists precisely so there is always one, and
# `unknown` is the answer for "this order can vouch for nothing" — a broken
# state dir is the purest case of it. So the failure becomes a REASON the
# surface can name (state-dir-unavailable) rather than an absence the caller
# has to invent a default for.
#
# `-w` as well as the mkdir, because `mkdir -p` succeeds on a directory that
# already exists and says nothing about whether we may write in it: an existing
# but unwritable state dir fails every state write later, one silent file at a
# time, having reported a clean start.
STATE_DIR_OK=1
mkdir -p "$STATE_DIR" 2>/dev/null || STATE_DIR_OK=0
{ [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ]; } || STATE_DIR_OK=0

# This order's files that are NOT episode state: where the last pass stopped,
# that a pass ran at all, and which sessions it actually classified. Every name
# starts with a dot, which `safe_id` rejects — so no session can ever be given a
# state file that collides with one, and the week-old prune below (safe_id AND a
# state header) never touches them.
CURSOR_FILE="$STATE_DIR/.sweep-cursor"
HEARTBEAT_FILE="$STATE_DIR/.heartbeat"
COVERAGE_FILE="$STATE_DIR/.sweep-coverage"

NOW="$(date +%s)"

# The first line of every file this order writes, and the test every path that
# reads one applies before treating the file as its own.
#
# Ownership used to be inferred from SHAPE — a `first_seen=` header, a
# session-id-shaped name — and a shape is a guess, not a claim. A file that
# happens to look like ours is then read as ours, in both directions, and both
# were reproduced during review. Reading: a foreign file carrying plausible
# `first_seen`/`last_seen`/`detector_class` fields makes `--status` answer
# `quota_park=yes` for a session this order never classified — a warrant
# suppressed on evidence it did not produce. Deleting: the same weak test is
# what `owned_state_rm` and the week-old prune gate on, so a foreign file shaped
# like state is destroyed by a routine sweep, which is the "deletes only files it
# wrote" contract resting on a header anybody might have written.
#
# So the claim is made explicit and versioned instead. A file whose first line is
# not exactly this is not this order's, whatever it looks like inside: not read
# as an episode, not deleted, not pruned, not reported on. The version suffix is
# what will let a future format change be told apart from a foreign file rather
# than parsed as an older one of ours.
#
# What this is and is not. It is an ownership LABEL, not an authenticator, and it
# closes the collision class: an unrelated component's state, a stray name, a
# hand-edited leftover, a mis-set or shared QUOTA_PARK_STATE_DIR — every case
# that has actually been hit here. It cannot stop something that can WRITE to
# STATE_DIR from writing the marker too, and nothing at this layer can: such a
# writer runs as the same user this order does. The honest boundary is that an
# accident can no longer forge ownership and a forgery has to be deliberate.
STATE_MAGIC='#quota-park-nudge-state-v1'

# True for a file this order wrote: a regular file — never a symlink, directory,
# or FIFO — whose first line is the marker. Every read, delete, prune and report
# path goes through here, so no two of them can drift in what "ours" means.
owned_file() {
    local first=""
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    IFS= read -r first < "$1" 2>/dev/null || return 1
    [ "$first" = "$STATE_MAGIC" ]
}

# Read one key out of a state file. Never `source` it — the file is keyed by a
# session id and lives in a shared runtime dir.
#
# Only ever out of a file this order owns. STATE_DIR is shared (and an override),
# so anything else there is somebody else's, and parsing it as episode state is
# how a planted or coincidental file gets to drive this order's own decisions:
# the backoff window, the once-per-episode escalation flag, the verdict
# `--status` publishes. A file that fails `owned_file` — including a planted
# symlink — reads as "no state", and the next write replaces the entry itself
# rather than following it (see write_atomic).
state_get() {
    owned_file "$1" || return 0
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- || true
}

# True for a bare non-empty integer — everything read back out of a state file
# is fed to arithmetic, and `$(( ))` on garbage is fatal under `set -e`.
num() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }

# True for a timestamp this order could have written: an integer, and not in the
# FUTURE. Every timestamp persisted here is stamped from the running pass's own
# clock, so one ahead of that clock is not a record of something that happened —
# it is a corrupt field, a clock that went backwards, or a planted one. Being an
# integer was never the whole contract, because each of these defeats a guard by
# arithmetic alone, silently, and in the direction that stops recovery:
#   last_try    a future value keeps `NOW - last_try` negative, so the backoff
#               window never elapses and the parked session is never nudged
#               again — recovery off for that session until the wall clock
#               catches up, which for a typo'd year is never.
#   first_seen  keeps `age` negative, so ESCALATE_AFTER is never reached and no
#               human is told about a park that outlasts it. `--status` also
#               publishes the negative age as `age_s`.
#   last_run    a future heartbeat makes every subsequent `--status` read a
#               stopped order as a fresh one, which is warrant suppression on a
#               sweep that never ran.
# Invalid falls back to the same default a missing field gets — start of
# episode, never nudged, no heartbeat — which is the direction that recovers.
#
# The one cost lands on a host that can only bound calls softly (BOUND_MODE=1),
# where a pass can overrun into the next one: the older pass reads the newer
# pass's record as future-dated, discards it, and re-nudges a session that was
# just handled. That is one extra resume message on a host already warned about,
# and being early is the trade this order makes everywhere else too.
ts_valid() { num "${1:-}" && [ "$1" -le "$NOW" ]; }

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
# collects them by name instead, and reads the pass's timestamp out of that name
# so it can age them without asking the filesystem (`stat` spells mtime
# differently on GNU and BSD; `find -mtime` was the portability gap this closes).
#
# A DIRECTORY at the destination is the one type that must be refused rather
# than replaced, and refusing it is what makes the failure visible at all: `mv
# file dir` does not replace the directory, it moves the file INSIDE it (so does
# `mv file symlink-to-dir` — hence `-d`, which follows the link). Left to `mv`,
# a directory at a parked session's state path therefore SWALLOWS the episode
# while reporting success: the state lands at `$STATE_DIR/<id>/.qpn-tmp.XXXXXX`
# where nothing reads it, `--status` finds no episode, and the session that was
# just nudged is published as clean. Reproduced during review. A refusal here is
# what lets the caller withhold coverage and say so.
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

# Write a file this order OWNS: the marker line, then stdin, atomically. Every
# persisted file goes through here — episode state, cursor, heartbeat, coverage —
# so none of them can be written without the claim that lets it be read back, and
# a file that predates the marker (or was planted to look like one) is replaced
# rather than merged with.
write_owned() {
    { printf '%s\n' "$STATE_MAGIC"; cat; } | write_atomic "$1"
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
        "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" | write_owned "$1"
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

# Delete an episode state file — but only one this order actually wrote.
#
# Every path that ends an episode deletes a file in a directory this order does
# not own: STATE_DIR defaults inside the shared city runtime dir and is an
# override besides, and a session id is not a rare shape for a filename. A plain
# `rm -f "$STATE_DIR/$id"` therefore deletes whatever happens to sit at that
# name — reproduced during review with an unrelated regular file at
# `$STATE_DIR/lx-clean`, destroyed by a clean sweep. The narrow ownership model
# the week-old prune already documents has to hold on the every-3-minutes paths
# too, and this is that test in one place so the three callers cannot drift:
# directly in STATE_DIR, a regular file and not a symlink, named like the ids we
# write (`safe_id`), and carrying this order's own marker line (`owned_file`).
#
# Anything failing one of them is somebody else's file and is left alone. That
# is deliberately not free: a foreign file at a live session's path keeps
# `--status` answering `unknown` for it rather than `no`, since there is a file
# there this order cannot read as an episode. Unknown is the safe direction —
# the patrols fall back to their own judgment — and it is the honest one.
#
# The ownership test is `owned_file`'s marker, not the `first_seen=` header this
# used to accept. A header is a shape, and shape is guessable: an unrelated
# file that opens with that line — another component's key/value state, an
# editor backup of one of ours — was deleted by a routine sweep on the strength
# of it. See STATE_MAGIC.
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

# How long ago this order last CLASSIFIED a session — reached a verdict on its
# pane — as opposed to merely having run a pass in which that session existed.
# Prints an age in seconds, or fails if there is no record. See write_coverage.
covered_age() {
    local ts
    owned_file "$COVERAGE_FILE" || return 1
    ts="$(awk -v id="$1" '$1 == id { print $2; exit }' "$COVERAGE_FILE" 2>/dev/null)" || return 1
    ts_valid "$ts" || return 1
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

# The CURRENT region of a pane: its tail window. Everything that classifies a
# pane reads this and nothing above it — the busy test directly, the banner test
# and the detector class through banner_candidates below.
#
# One function because the two tests have to agree on which lines are "now".
# They did not: the busy marker was matched against the whole capture while the
# banner was matched against the tail, so a pane holding an old `esc to
# interrupt` up in its scrollback and a live quota banner at the bottom read as
# BUSY — not parked, episode deleted, and `--status` vouching `no` for a session
# that is genuinely blocked (reproduced during review). Scrollback is history for
# the busy marker exactly as it is for the banner: both CLIs print their working
# indicator in the live status line at the bottom of the screen, so a copy
# further up is the record of a turn that has already ended.
pane_tail() {
    printf '%s\n' "$1" | tail -n "$TAIL_LINES"
}

# The lines of a pane a banner may legitimately sit on: the tail window, minus
# citations. Both the park test and the detector class read the same set — a
# second copy of this filter chain would drift out of agreement with the test
# that decides whether a session is parked at all.
banner_candidates() {
    pane_tail "$1" | grep -vE -- "$CITATION_RE" || true
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
# Floor 1, same rule as the other knobs that do not document zero as an off
# switch. `timeout -k 0` is accepted rather than rejected — it simply disables
# the kill escalation — so a zero here silently restores the soft bound this
# knob exists to close, on the one path where a wedged call strands the sweep.
# Turning the bound off entirely is CALL_TIMEOUT=0's job, and it says so.
num_min "$KILL_AFTER"     1 || KILL_AFTER=5
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
#               foreign-state    something is at that session's state path that
#                                this order did not write, so there is no episode
#                                to read and no clean path to report either
#               state-dir-unavailable  the state directory could not be created
#                                or cannot be written, so this order holds no
#                                evidence about ANY session and cannot record any
#
# The `no` case is the one that has to be earned rather than inferred: a pass
# that runs out of SWEEP_BUDGET defers its whole tail without peeking it and
# still writes a fresh heartbeat, so "a sweep ran recently and there is no
# episode" is not the same statement as "that session is not parked".

# A full closed-field line for a session this order can say nothing about, every
# field at its no-evidence value. The surface has to answer in the SAME shape
# whether or not it has state to read: a consumer that greps one field out of a
# status line must not have to handle a short line as a special case, and a
# short line is how a missing field silently becomes whatever default the reader
# assumed. `-` for the id where there is not even a session to name.
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

# Only `--status` is special; anything else falls through to a normal sweep,
# which is what the order runner invokes with no arguments at all.
if [ "${1:-}" = "--status" ]; then
    status_report "${2:-}"
    exit 0
fi

# The sweep, unlike the surface above, genuinely cannot proceed without the
# state directory: with nowhere to write an episode every park would be
# re-detected as new, nudged on every cycle, and escalated forever. It stops —
# but it stops LOUDLY, in the order runner's log, which is the half the silent
# `|| exit 0` never had. Still exit 0: the pass had nothing to do, which is not
# the same as the order crashing, and a non-zero rc here would read as one.
# The path is bounded through sanitize_display like every other value this
# script prints, since it arrives from the environment.
if [ "$STATE_DIR_OK" != "1" ]; then
    echo "quota-park-nudge: state dir unavailable ($(sanitize_display "$STATE_DIR")) — no sweep this pass; --status reports unknown/state-dir-unavailable"
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

# What kind of bound this host can actually enforce, resolved once:
#   2  hard — `timeout -k`: SIGTERM at CALL_TIMEOUT, SIGKILL KILL_AFTER later
#   1  soft — `timeout` only: SIGTERM, then wait for a child free to ignore it
#   0  none — no timeout(1) at all (some macOS hosts)
#
# Probed rather than assumed: `-k` is GNU/uutils/busybox, but this order runs
# wherever the pack does and an unsupported flag would fail EVERY bounded call
# with a usage error — every pane unreadable, recovery silently off. `true` is
# the cheapest possible probe and the bounds are 1s it never reaches.
BOUND_MODE=0
if command -v timeout >/dev/null 2>&1; then
    if timeout -k 1 1 true >/dev/null 2>&1; then BOUND_MODE=2; else BOUND_MODE=1; fi
fi

# Every `gc` call goes through here. Two things it guarantees:
#
#   1. A bound (CALL_TIMEOUT), and where the host allows it, a HARD one. Plain
#      `timeout` sends SIGTERM and then waits — indefinitely, if the child
#      ignores it (`timeout 1 bash -c 'trap "" TERM; sleep 4'` runs the full 4s).
#      A `gc` call wedged in the runtime or in Dolt is the process least likely
#      to service a signal promptly, so the bound most relied on to stop one
#      wedged call stranding the sweep is the one likeliest to be ignored. `-k`
#      adds the SIGKILL nothing can ignore. Either way expiry is a non-zero rc —
#      124 for the timeout, 128+n where the kill lands first (137 on the hosts
#      tested) — so a wedged call falls into the caller's existing failure branch
#      (empty pane, failed nudge). Both are already handled as the ambiguous
#      case by the nudge and escalation branches below, which is what they are:
#      the call may have been accepted before it stopped answering. Same idiom
#      and env-override shape as merge-skill.sh's run_bounded. No coreutils
#      `timeout` degrades to an unbounded call rather than dropping the probe:
#      skipping every call would silently disable recovery on such a host.
#   2. stdin CLOSED. The session loop below reads its work list from a
#      here-string on fd 0; a child that inherited and consumed it would
#      truncate the sweep — sessions would vanish from the run rather than fail.
run_bounded() {
    if [ "$CALL_TIMEOUT" -le 0 ] || [ "$BOUND_MODE" -eq 0 ]; then
        "$@" </dev/null
    elif [ "$BOUND_MODE" -eq 2 ]; then
        timeout -k "$KILL_AFTER" "$CALL_TIMEOUT" "$@" </dev/null
    else
        timeout "$CALL_TIMEOUT" "$@" </dev/null
    fi
}

# Said out loud, once per pass, on a host that can only bound softly: the sweep
# still runs and still recovers agents, but a `gc` call that ignores SIGTERM can
# hold it past its budget, and the summary line's numbers are then a floor
# rather than a full pass. An operator reading a short sweep deserves to know
# which of the two it was. Deliberately after the `--status` exit above: the
# patrols read that surface every cycle and this is not their problem.
if [ "$CALL_TIMEOUT" -gt 0 ] && [ "$BOUND_MODE" -eq 1 ]; then
    echo "quota-park-nudge: this host's timeout(1) has no -k — call bounds are SIGTERM-only, so a gc call that ignores it is effectively unbounded"
fi

# True once the pass has run longer than SWEEP_BUDGET (0 = no budget). Checked
# per session so a slow sweep stops at a session boundary, with its state files
# consistent, instead of overrunning into the next cycle.
sweep_expired() {
    [ "$SWEEP_BUDGET" -gt 0 ] || return 1
    [ "$(( $(date +%s) - NOW ))" -ge "$SWEEP_BUDGET" ]
}

checked=0; parked=0; nudged=0; skipped=0; unreadable=0; rejected=0; unconfirmed_now=0
state_failed=0
last_attempted=""
covered_now=""

# Vouch for one session: this pass reached it, classified it, and its verdict is
# readable back out of the state directory. That last clause is the whole point
# — see write_state_vouched.
vouch() { covered_now="$covered_now$1 $NOW"$'\n'; }

# Persist an episode, and vouch for the session only if the write landed.
#
# Coverage used to be recorded as soon as the pane was read, which conflates two
# different facts: that this pass CLASSIFIED a session, and that the
# classification is still there to be read. For a parked session the state file
# IS the verdict — `--status` answers `yes` out of it — so a write that fails
# leaves a session that was detected, nudged, and then published as `no`, on the
# strength of a coverage line saying we looked. Reproduced during review with a
# directory at `$STATE_DIR/<id>`: swept, nudged, `quota_park=no reason=-`. A
# parked agent reported clean is precisely the answer that sends a patrol down
# the warrant path this order exists to hold back.
#
# So a failed write withholds the vouch instead, and `--status` falls to
# `unknown` / `not-swept` — the same answer any other uninspected session gets,
# in a vocabulary the patrols already handle. Counted and logged, because
# silently uncovering a session looks identical to never having reached it.
write_state_vouched() {
    if write_state "$@"; then
        vouch "$id"
        return 0
    fi
    state_failed=$((state_failed + 1))
    echo "quota-park-nudge: state write FAILED for $alias ($id) — not vouched for; --status reports unknown until it succeeds"
    return 1
}

# That a pass RAN, and what it saw. This is what makes the status surface
# refusable: warrant suppression in the patrols is conditional on a recent sweep,
# so an order that is disabled, wedged, or absent from a host cannot hold a
# warrant back by leaving old evidence lying around. Written only where a pass
# actually completed — every early exit below (a session list that failed, no
# jq, an unwritable state dir) leaves the previous heartbeat to go stale, which
# is exactly what a patrol reads as `unknown`.
write_heartbeat() {
    printf 'last_run=%s\nchecked=%s\nparked=%s\nnudged=%s\ndeferred=%s\n' \
        "$NOW" "$checked" "$parked" "$nudged" "$skipped" | write_owned "$HEARTBEAT_FILE" || true
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
    if pane_tail "$pane" | grep -qEi -- "$BUSY_RE" \
        || ! banner_candidates "$pane" | grep -qEi -- "$MATCH_RE"; then
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
    if [ -n "$EXCLUDE_RE" ] && printf '%s' "$alias" | grep -qEi -- "$EXCLUDE_RE"; then
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

# A recovered agent's state file is removed above, the moment its pane goes
# clean. This only sweeps files no cycle has touched in a week — sessions that
# were closed or renamed while parked.
#
# Narrow on purpose, because STATE_DIR is an override and its default sits
# inside the shared city runtime directory: a broad `find "$STATE_DIR" -type f
# -mtime +7 -delete` is a city-scoped order deleting week-old files it has never
# heard of, and a mis-set or shared QUOTA_PARK_STATE_DIR is all it takes to
# point that at somebody else's state. The ownership test is `owned_state_rm`'s
# — a regular non-symlink file, directly in STATE_DIR, named like the session ids
# we write, carrying this order's own marker line — and it is the same one the
# two every-cycle removal paths use, so no path can drift into deleting more
# than the others. Anything failing it is somebody else's file and is left alone,
# including this order's OWN `.sweep-cursor` and `.heartbeat`, whose leading dot
# puts them outside safe_id on purpose.
#
# Iterated with a glob rather than `find`, and aged from the record rather than
# from mtime, so the whole thing is POSIX shell. `find -maxdepth`/`-print0` are
# GNU/BSD extensions and `stat` spells mtime differently on each — this order
# degrades carefully everywhere else (BOUND_MODE probes for `timeout -k` rather
# than assuming it), and the cleanup path had no reason to be the one piece that
# needs GNU. The two globs cover the dotted names too, since `*` alone skips
# them; `owned_state_rm`'s STATE_DIR check is the depth guard `-maxdepth 1` was,
# and a glob never descends anyway. A hostile filename is just one more element
# here — there is no line-splitting to be confused by, which is what `-print0`
# was defending.
PRUNE_AFTER=604800   # 7 days, in seconds

# Age of an episode file this order owns, from the record inside it: the last
# time a sweep confirmed the session parked, or failing that when the episode
# began. A file of ours with neither is one no sweep can have written — every
# write is atomic and complete — so it is corrupt or hand-made, and reported as
# ancient to be collected rather than left to sit forever.
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
# A session detected and acted on whose verdict did not persist. Named here for
# the same reason as the rest: it is coverage this pass did not achieve, and a
# sweep that could not record what it found must not read as one that found
# nothing.
statefail=""
[ "$state_failed" -gt 0 ] && statefail=", $state_failed state write failed (not vouched for)"
echo "quota-park-nudge: $checked checked, $parked parked, $nudged nudged$unconf$unread$unsafe$deferred$statefail"
