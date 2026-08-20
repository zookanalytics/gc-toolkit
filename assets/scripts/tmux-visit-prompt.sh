#!/bin/sh
# tmux-visit-prompt.sh — `prefix + a`: type a message, get a durable
# conversation. Usage: tmux-visit-prompt.sh <config-dir>
#
# Bound by tmux-bindings.sh with a plain `run-shell -b`. The key opens a tmux
# popup running `gum write`; the operator types whatever is on their mind — a
# phrase or five paragraphs — and submits, and this script hands that text to
# `gc-visit-open.sh` (tk-4ojka), which mints a subject bead carrying the
# message and either slings `mol-first-reaction` at it or files the visit
# directly. Either way the operator ends up with a routed conversation instead
# of a note they have to remember to act on. Esc cancels; a blank submit files
# nothing and says so.
#
# This key held the `-thread` spawner until tk-bn1oi. Threads are retired, so
# it was already dead — it could only flash "no <role>-thread template" — and
# the affordance it provided (one keystroke from "I need an agent on X" to an
# agent on X) is what converse never carried across. This is that affordance,
# on the same key, against the persistence converse actually has.
#
# ── Why the input surface is a popup and not `command-prompt` ────────
# tmux's bottom-bar `command-prompt` held this key for exactly one commit
# (tk-bn1oi, PR #393) and lost multi-line input in the process: it is
# SINGLE-LINE by construction, with no multi-line mode to configure, so the
# operator could file a sentence and nothing longer (tk-7z8c6). It also has to
# be defended against — the prompt substitutes the response into its template
# as TEXT and the result is then PARSED as a tmux command, so a `;` splits the
# message into a second command and a `"` unbalances the argument. The
# spawner before it shipped exactly that hazard and documented it as a known
# limitation (specs/tk-1zd25/design.md); tk-02v4g moved to a `gum` popup
# precisely to escape it.
#
# So the popup is not a new idea here — it is the one this key already had.
# gum reads /dev/tty in raw mode and prints the buffer on stdout, and the
# buffer reaches this script through a file: a process boundary, with no tmux
# format layer and no shell quoting layer anywhere near the text.
# Apostrophes, semicolons, quotation marks, `$`, `~`, backslashes and NEWLINES
# all round-trip verbatim.
#
# `write`, not `input`: `gum input` is gum's single-line primitive and is what
# tk-02v4g used, so restoring parity with the retired spawner would reproduce
# this same bug one layer down. `write` is the long-form primitive. Its submit
# and newline keys differ across gum versions, which is why `--show-help` is
# passed below and why no comment or placeholder here restates them: gum
# renders its own key hints inside the popup, and those cannot go stale.
#
# ── Why the topic file is per-invocation ─────────────────────────────
# `mktemp` per press, never one fixed slot. The `command-prompt` design parked
# the response in a paste buffer with a FIXED name, so press N+1 could
# overwrite what press N had not read yet — a silently lost topic, which is
# the one failure this channel exists to prevent. It bought that back by
# reading the buffer in the FOREGROUND, ordering presses through tmux's
# command queue. A file per press removes the collision instead of sequencing
# around it, so the whole hazard (and the foreground constraint it imposed) is
# structurally gone.
#
# The popup is also modal: while it is open the client's keys go to gum, so a
# second press cannot be typed until the first is submitted or cancelled — and
# a cancelled draft was never handed to anything. Two intakes still overlap
# where overlapping matters, because the slow half below is backgrounded: a
# submitted topic never delays the next press.
set -eu

CONFIGDIR="${1:?missing config-dir}"

VISIT_OPEN="${GC_VISIT_OPEN_TOOL:-$CONFIGDIR/assets/scripts/gc-visit-open.sh}"

# Seconds to let the intake run before calling it stuck. See the bound below.
INTAKE_TIMEOUT="${GC_VISIT_INTAKE_TIMEOUT:-300}"

# Popup geometry. Percentages so it scales with the client instead of
# overflowing a small one, and a height generous enough that the multi-line
# surface this bead exists to restore is visibly multi-line. The textarea is
# sized under the popup interior (2 rows of border + gum's header + gum's key
# hint line) so nothing is clipped on a standard 24-row terminal. Overridable
# for terminals this does not suit.
POPUP_W="${GC_VISIT_POPUP_WIDTH:-80%}"
POPUP_H="${GC_VISIT_POPUP_HEIGHT:-50%}"
INPUT_H="${GC_VISIT_INPUT_HEIGHT:-8}"

# What the popup says. gum's own hint line is authoritative for THIS gum's
# submit and newline keys, so the header carries only what that line omits:
# what the popup is for, and that Esc throws the draft away.
POPUP_HEADER='visit topic — multi-line is fine; Esc discards'
POPUP_PLACEHOLDER="What's on your mind?"

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# sq <string> — POSIX shell-quote $1 for embedding in the popup's command
# body. tmux runs that body through `sh -c`, so the file path and the prompt
# strings need shell quoting even though the MESSAGE never goes near it.
sq() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# 1. Resolve everything that depends on WHO pressed the key, here, while the
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

# say <duration-ms> <message> — the operator's only feedback channel. Every
# outcome goes through it: this handler is invoked backgrounded from tmux's
# point of view, and an intake path that fails invisibly is strictly worse
# than one that never existed.
say() {
    _d="$1"; shift
    # shellcheck disable=SC2086 # ${CLIENT:+…} deliberately expands to 0 or 2 words
    gcmux display-message ${CLIENT:+-c "$CLIENT"} -d "$_d" "$*" 2>/dev/null || true
}

# 2. Check both dependencies BEFORE the popup. Asking the operator to type a
#    paragraph and only then admitting there is nothing to file it with wastes
#    the one thing this key is supposed to protect.
if [ ! -x "$VISIT_OPEN" ]; then
    say 10000 "gc visit: intake script missing or not executable at $VISIT_OPEN"
    exit 1
fi

# Without this precheck a missing binary renders an opaque "command not
# found" inside a popup that then closes instantly. Surface the install hint
# instead (the linuxbrew default install is /home/linuxbrew/.linuxbrew/bin/gum).
if ! command -v gum >/dev/null 2>&1; then
    say 10000 "gc visit: 'gum' not on PATH; install with 'brew install gum'"
    exit 1
fi

# 3. Read the message. One file per press (see the header), removed on every
#    exit path so a crashed handler leaves nothing behind for the next one to
#    mistake for a fresh topic.
TOPIC_FILE=$(mktemp "${TMPDIR:-/tmp}/gc-visit-topic.XXXXXX")
trap 'rm -f "$TOPIC_FILE"' EXIT INT TERM HUP

POPUP_RC=0
# `-c "$CLIENT"`: on a server with several attached clients, "current" is not
# reliably the one that pressed the key — the same reason the capture above
# is in the foreground. stderr is captured rather than discarded because it
# is the only thing that distinguishes a cancel from a popup that never
# opened; see below.
# shellcheck disable=SC2086 # ${CLIENT:+…} deliberately expands to 0 or 2 words
POPUP_ERR=$(gcmux display-popup -E ${CLIENT:+-c "$CLIENT"} -w "$POPUP_W" -h "$POPUP_H" \
    "gum write --show-help --height $(sq "$INPUT_H") --header $(sq "$POPUP_HEADER") --placeholder $(sq "$POPUP_PLACEHOLDER") > $(sq "$TOPIC_FILE")" \
    2>&1) || POPUP_RC=$?

if [ "$POPUP_RC" -ne 0 ]; then
    # Two very different things exit non-zero here, and only one of them is a
    # decision the operator made:
    #   * Esc or ^C — gum exits non-zero and `display-popup -E` propagates it.
    #     A cancel is deliberate: no bead, no intake, and no message either.
    #     tmux writes nothing to stderr for it.
    #   * the popup never opened — no current client, a client too small for
    #     the geometry. tmux says so on stderr, and staying silent would make
    #     a key that is broken look exactly like one the operator changed
    #     their mind about.
    if [ -n "$POPUP_ERR" ]; then
        say 10000 "gc visit: could not open the input popup: $POPUP_ERR"
        exit 1
    fi
    exit 0
fi

TOPIC=$(cat "$TOPIC_FILE" 2>/dev/null || true)

# 4. A blank (or whitespace-only) submit is not an error and not a topic.
#    Say so rather than filing a bead with an empty title.
if [ -z "$(printf '%s' "$TOPIC" | tr -d '[:space:]')" ]; then
    say 3000 "gc visit: nothing typed — no bead filed"
    exit 0
fi

# 5. Background the slow half. `gc-visit-open.sh` enumerates rigs, creates
#    the subject bead and then files the visit (or slings the reaction) —
#    seconds, and up to GC_HELM_RIG_TIMEOUT on a busy city. The operator's
#    pane returns immediately; the status-line indicator slot carries the
#    in-flight state and a display-message carries the outcome.
#
#    stdout/stderr are closed against /dev/null so tmux's `run-shell` sees EOF
#    and returns at once — it waits on the job's pipes, not on the process
#    tree, and an inherited fd here would hold the key binding open for the
#    whole intake.
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
    # Bounded, because the whole point of this key is that nothing is lost:
    # `bd create` against a wedged data plane would otherwise leave the
    # indicator lit and the operator with no message at all — a hang is an
    # invisible failure, which is the one outcome an intake path must not
    # have. Degrades to unbounded where timeout(1) is missing, as
    # tmux-keeper-toggle.sh does. The default 300s is far past the slowest
    # healthy run (gc-visit-open bounds its own rig enumeration at
    # GC_HELM_RIG_TIMEOUT, default 30s) so it fires only on a genuinely stuck
    # call.
    RC=0
    if command -v timeout >/dev/null 2>&1; then
        OUT=$(timeout "$INTAKE_TIMEOUT" "$VISIT_OPEN" -- "$TOPIC" 2>&1) || RC=$?
    else
        OUT=$("$VISIT_OPEN" -- "$TOPIC" 2>&1) || RC=$?
    fi

    # Anchored at the start of a line, and on the reporting tool's own
    # prefix: an unanchored `.*subject ` would match those words inside an
    # echoed topic, and greedily pick the last one at that.
    SUBJECT=$(printf '%s\n' "$OUT" | sed -n 's/^[A-Za-z0-9_-]*: subject \([A-Za-z0-9][A-Za-z0-9_-]*\).*/\1/p' | head -1)
    VISIT=$(printf '%s\n' "$OUT" | sed -n 's/^[A-Za-z0-9_-]*: visit \([A-Za-z0-9][A-Za-z0-9_-]*\) filed .*/\1/p' | head -1)

    if [ "$RC" -ne 0 ]; then
        # Name the subject when one was already created: it survives the
        # failure, and knowing its id is the difference between retrying and
        # losing the thought.
        DETAIL=$(printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | tail -1)
        [ "$RC" -eq 124 ] && DETAIL="timed out after ${INTAKE_TIMEOUT}s. ${DETAIL:-no output}"
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
