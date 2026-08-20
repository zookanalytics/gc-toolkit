#!/bin/sh
# tmux-visit-prompt.sh — `prefix + a`: type a message, get a durable
# conversation. Usage: tmux-visit-prompt.sh <config-dir>
#
# Bound by tmux-bindings.sh. The key opens tmux's bottom-bar
# `command-prompt`; the operator types whatever is on their mind and hits
# Enter, and this script hands that text to `gc-visit-open.sh` (tk-4ojka),
# which mints a subject bead carrying the message and either slings
# `mol-first-reaction` at it or files the visit directly. Either way the
# operator ends up with a routed conversation instead of a note they have to
# remember to act on. Esc cancels; a blank Enter files nothing and says so.
#
# This replaces the `-thread` spawner that held `prefix + a` until tk-bn1oi.
# Threads are retired, so that key was already dead — it could only flash
# "no <role>-thread template" — and the affordance it provided (one keystroke
# from "I need an agent on X" to an agent on X) is what converse never carried
# across. This is that affordance, on the same key, against the persistence
# converse actually has.
#
# ── The input path, and why it is not the obvious one ────────────────
# tmux's `command-prompt` substitutes the response into the template as TEXT
# and then PARSES the result as a tmux command. So the obvious binding —
# `run-shell 'handler "%%"'` — re-parses whatever the operator typed: a `;`
# splits it into a second tmux command, a `"` unbalances the argument, and
# the message is mangled or partially EXECUTED. The predecessor shipped
# exactly that and documented it as a known limitation
# (specs/tk-1zd25/design.md), then moved to a `gum input` popup to escape it.
#
# The response never becomes part of a command line here. tmux's `%%%`
# (like `%%`, but quotation marks escaped) puts it in a PASTE BUFFER, and
# this script reads the buffer back — a process boundary, so no shell or
# tmux quoting layer ever touches the text. Apostrophes, semicolons, quotes,
# `$`, `~` and backslashes all round-trip verbatim, with no `gum` dependency.
#
# ── Why the buffer read is in the foreground ─────────────────────────
# The buffer name is fixed, so two presses share one slot: if the read were
# backgrounded, a second press could overwrite the buffer before the first
# reader got to it and the first topic would be LOST — silently, which is
# the one failure this channel exists to prevent. tmux runs a client's key
# bindings through its command queue in order, so a FOREGROUND `run-shell`
# read is serialised against the next press's `set-buffer`. Everything after
# the read is backgrounded (see below), so the foreground half is only
# tmux-local calls and cannot freeze the server the way a slow `gc` call in
# the same position would (cf. tmux-keeper-toggle.sh, tmux-pick-session.sh).
set -eu

CONFIGDIR="${1:?missing config-dir}"

# The buffer the binding parks the operator's message in. Overridable so the
# test can run several handlers against one server without collisions.
BUF="${GC_VISIT_TOPIC_BUFFER:-gc-visit-topic}"

VISIT_OPEN="${GC_VISIT_OPEN_TOOL:-$CONFIGDIR/assets/scripts/gc-visit-open.sh}"

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# 1. Drain the topic buffer. First thing, before anything that can block —
#    see the header. Delete it too: a leftover buffer would be re-read as a
#    fresh topic by the next press that arrives with an empty response
#    (Esc never runs the template at all, so it would otherwise persist).
TOPIC=$(gcmux show-buffer -b "$BUF" 2>/dev/null || true)
gcmux delete-buffer -b "$BUF" 2>/dev/null || true

# 2. Resolve everything that depends on WHO pressed the key, here, while the
#    binding's client context still exists. The background half below is a
#    detached process: it has no current client and no current session, so
#    both the display-message target and the agent behind the status-line
#    indicator have to be captured now or not at all. Measured against a live
#    server: `#{client_tty}` and `#{client_session}` come back EMPTY from a
#    detached process, and `#{session_name}` answers with whichever session
#    tmux considers current — which on a city full of panes is not
#    necessarily the operator who pressed the key.
CLIENT=$(gcmux display-message -p '#{client_tty}' 2>/dev/null || true)
SESSION=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)
[ -n "$SESSION" ] || SESSION=$(gcmux display-message -p '#{session_name}' 2>/dev/null || true)
AGENT=""
if [ -n "$SESSION" ]; then
    # gascity names tmux sessions `<rig>__<agent>`, so the suffix is the
    # fallback when the session environment carries no GC_AGENT.
    AGENT=$(gcmux show-environment -t "$SESSION" GC_AGENT 2>/dev/null | sed -n 's/^GC_AGENT=//p')
    [ -n "$AGENT" ] || AGENT=$(printf '%s' "$SESSION" | sed 's/.*__//')
fi
# Indicator slot contract: gc-toolkit-status-line.sh renders the verbatim
# contents of /tmp/gc-status-<slug>.indicator on every 5s refresh, where
# <slug> is the qualified agent name with [./] -> -.
INDICATOR=""
[ -n "$AGENT" ] && INDICATOR="/tmp/gc-status-$(printf '%s' "$AGENT" | sed 's|[./]|-|g').indicator"

# say <duration-ms> <message> — the operator's only feedback channel. Both
# outcomes go through it: this handler is invoked backgrounded from tmux's
# point of view once it forks, and an intake path that fails invisibly is
# strictly worse than one that never existed.
say() {
    _d="$1"; shift
    # shellcheck disable=SC2086 # ${CLIENT:+…} deliberately expands to 0 or 2 words
    gcmux display-message ${CLIENT:+-c "$CLIENT"} -d "$_d" "$*" 2>/dev/null || true
}

# 3. A blank (or whitespace-only) Enter is not an error and not a topic.
#    Say so rather than filing a bead with an empty title.
if [ -z "$(printf '%s' "$TOPIC" | tr -d '[:space:]')" ]; then
    say 3000 "gc visit: nothing typed — no bead filed"
    exit 0
fi

if [ ! -x "$VISIT_OPEN" ]; then
    say 10000 "gc visit: intake script missing or not executable at $VISIT_OPEN"
    exit 1
fi

# 4. Background the slow half. `gc-visit-open.sh` enumerates rigs, creates
#    the subject bead and then files the visit (or slings the reaction) —
#    seconds, and up to GC_HELM_RIG_TIMEOUT on a busy city. The operator's
#    pane returns immediately; the status-line indicator slot carries the
#    in-flight state and a display-message carries the outcome.
#
#    stdout/stderr are closed against /dev/null so tmux's foreground
#    `run-shell` sees EOF and returns at once — it waits on the job's pipes,
#    not on the process tree, and an inherited fd here would hold the key
#    binding open for the whole intake.
(
    # Trap clears the indicator on every exit path so the slot empties when
    # the intake finishes, however it finishes.
    if [ -n "$INDICATOR" ]; then
        trap 'rm -f "$INDICATOR"' EXIT INT TERM HUP
        echo "[opening visit...]" > "$INDICATOR" 2>/dev/null || true
    fi

    # `--` because a message may legitimately begin with "-" and must not be
    # read as a flag. The topic is NOT forced with --topic: gc-visit-open
    # resolves a bare bead id against the live rig prefixes and opens a
    # conversation on that bead, which is a real thing to want from this key.
    # A prefix-shaped string no ledger answers for fails loudly there rather
    # than becoming a bead literally titled "tk-abc12".
    RC=0
    OUT=$("$VISIT_OPEN" -- "$TOPIC" 2>&1) || RC=$?

    SUBJECT=$(printf '%s\n' "$OUT" | sed -n 's/.*subject \([A-Za-z0-9][A-Za-z0-9_-]*\).*/\1/p' | head -1)
    VISIT=$(printf '%s\n' "$OUT" | sed -n 's/.*visit \([A-Za-z0-9][A-Za-z0-9_-]*\) filed.*/\1/p' | head -1)

    if [ "$RC" -ne 0 ]; then
        # Name the subject when one was already created: it survives the
        # failure, and knowing its id is the difference between retrying and
        # losing the thought.
        DETAIL=$(printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | tail -1)
        say 10000 "gc visit FAILED (rc=$RC)${SUBJECT:+ — subject $SUBJECT exists}: $DETAIL"
        exit 1
    fi

    if printf '%s\n' "$OUT" | grep -q 'first reaction slung'; then
        say 6000 "gc visit: subject ${SUBJECT:-?} — first reaction slung; it writes the card and files the visit"
    elif [ -n "$VISIT" ]; then
        say 6000 "gc visit: subject ${SUBJECT:-?} — visit $VISIT filed · prefix+S to attach"
    else
        say 6000 "gc visit: ${SUBJECT:+subject $SUBJECT — }$(printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | tail -1)"
    fi
) >/dev/null 2>&1 &
