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
# One file per press, never one fixed slot. The `command-prompt` design parked
# the response in a paste buffer with a FIXED name, so press N+1 could
# overwrite what press N had not read yet — a silently lost topic, which is
# the one failure this channel exists to prevent. It bought that back by
# reading the buffer in the FOREGROUND, ordering presses through tmux's
# command queue. A file per press removes the collision instead of sequencing
# around it, so the whole hazard (and the foreground constraint it imposed) is
# structurally gone.
#
# ── Why the draft OUTLIVES the failure (tk-w4dp4) ────────────────────
# The file used to be an `mktemp` under /tmp with
# `trap 'rm -f' EXIT INT TERM HUP` armed over it, so EVERY exit destroyed the
# only copy of what the operator typed — success, cancel, blank, a failed
# intake, or a crash alike. For the one channel whose entire purpose is that a
# thought is never lost, deleting the payload before knowing it was durably
# filed is backwards, and it is what a lost topic actually looked like: popup
# opens, operator types a paragraph, the intake fails, the draft is gone, and
# the feedback is a flash or nothing at all.
#
# So the draft is now removed at exactly two kinds of moment, and nowhere else:
# when the intake CONFIRMS an id (a subject or a visit came back), and when
# there is provably nothing to lose (the file is empty or whitespace-only).
# Every other path — cancel with text in the buffer, popup failure, blank-but-
# unreadable, intake failure, intake success that named no id, a signal — KEEPS
# the file and names its path to the operator. An orphan draft is recoverable;
# a deleted one is the bug.
#
# It also lives outside /tmp by default. /tmp here is a tmpfs shared by the
# whole city, its pressure fluctuates, and a truncated write is one of the ways
# a paragraph disappears — see the draft-dir precedence below. The directory is
# stable and greppable rather than a random name, so "where did my text go" has
# one answer, and old drafts are reaped on a generous window so it cannot grow
# without bound.
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

# Where drafts live, in precedence order. GC_VISIT_DRAFT_DIR is the override
# (and the test seam). GC_PACK_STATE_DIR is the city+pack runtime dir the rest
# of this pack already keys durable state on, so a city that sets it keeps the
# drafts with everything else it owns. Otherwise XDG state — real disk, present
# for whoever's tmux server this is, and not the city's shared tmpfs. /tmp is
# the last resort and is announced when it is used, because it is the one that
# can lose the file to the pressure this whole change is about.
DRAFT_DIR="${GC_VISIT_DRAFT_DIR:-}"
if [ -z "$DRAFT_DIR" ]; then
    if [ -n "${GC_PACK_STATE_DIR:-}" ]; then
        DRAFT_DIR="$GC_PACK_STATE_DIR/visit-drafts"
    elif [ -n "${XDG_STATE_HOME:-}" ]; then
        DRAFT_DIR="$XDG_STATE_HOME/gc/visit-drafts"
    elif [ -n "${HOME:-}" ]; then
        DRAFT_DIR="$HOME/.local/state/gc/visit-drafts"
    else
        DRAFT_DIR="${TMPDIR:-/tmp}/gc-visit-drafts"
    fi
fi

# Preserved drafts are the operator's to recover, so they are reaped on a
# window measured in days rather than on exit. Generous by default: the cost of
# keeping one too long is a file, and the cost of reaping one too early is the
# thought this key exists to catch.
DRAFT_KEEP_DAYS="${GC_VISIT_DRAFT_KEEP_DAYS:-14}"

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

# 3. Read the message. One file per press (see the header), kept unless it is
#    empty or the intake confirms an id.

# short <path> — the path as the operator should read it. Every message that
# names a draft leads with it, because display-message truncates at the client
# width and the recovery handle is the half that must survive: a headline the
# operator can guess is worth less than the path they cannot.
short() {
    case "${HOME:-}" in
        "") printf '%s' "$1" ;;
        *) case "$1" in
               "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
               *) printf '%s' "$1" ;;
           esac ;;
    esac
}

# keep_draft <ms> <reason> — the whole point of this bead. Preserve the file
# and lead with its path. Called on every path that is not a confirmed filing.
keep_draft() {
    say "$1" "DRAFT KEPT $(short "$DRAFT_FILE") — $2"
}

# drop_draft — remove it. Only ever called where there is provably nothing to
# lose (empty or whitespace-only) or where an id came back.
drop_draft() { rm -f "$DRAFT_FILE"; }

# The directory is created before the popup for the same reason the dependency
# checks above are: discovering there is nowhere to write AFTER a paragraph has
# been typed wastes the thought. A failure here falls back to the temp dir
# rather than killing the key, and says so — that is the pressure this moved
# away from, so landing back on it is news rather than a detail.
if ! mkdir -p "$DRAFT_DIR" 2>/dev/null || ! [ -w "$DRAFT_DIR" ]; then
    say 10000 "gc visit: draft dir $(short "$DRAFT_DIR") is not writable — falling back to ${TMPDIR:-/tmp} for this press"
    DRAFT_DIR="${TMPDIR:-/tmp}"
    mkdir -p "$DRAFT_DIR" 2>/dev/null || true
fi

# Reap what the operator has had long enough to recover. Scoped to this one
# directory, non-recursively, and to the `draft-` prefix this script writes, so
# it cannot reach a file it does not own — which matters most on the /tmp
# fallback above, where the directory is shared with the rest of the city.
# Best-effort: a missing or different `find` must not cost a press.
if command -v find >/dev/null 2>&1; then
    find "$DRAFT_DIR" -maxdepth 1 -type f -name 'draft-*' -mtime "+$DRAFT_KEEP_DAYS" -delete 2>/dev/null || true
fi

# `mktemp` guarded, because it was NOT. Unguarded under `set -eu` it kills the
# handler before the popup with no message at all, which from the operator's
# seat is indistinguishable from a key that does nothing — and /tmp exhaustion
# is a recurring failure class in this town, so it is a live path and not a
# theoretical one. `draft-` is the prefix the reaper above matches and the one
# to grep for; the UTC stamp sorts the directory newest-last; the X's are
# TRAILING because that is the only template shape every mktemp accepts. The
# whole name stays short so it survives a truncated display-message.
DRAFT_FILE=""
if ! DRAFT_FILE=$(mktemp "$DRAFT_DIR/draft-$(date -u +%Y%m%d-%H%M%S)-XXXXXX" 2>/dev/null) \
   || [ -z "$DRAFT_FILE" ]; then
    say 10000 "gc visit: cannot create a draft file in $(short "$DRAFT_DIR") (disk full, or the directory is unwritable) — nothing was opened, so nothing was typed and lost"
    exit 1
fi

# A signal is a crash, and a crash is exactly when the draft must survive. The
# old handler removed it here; this one reports where it is. Nothing is armed
# for EXIT: normal exits are decided explicitly below, one path at a time.
trap 'keep_draft 10000 "gc visit interrupted"; exit 1' INT TERM HUP

# The variable the rest of this script reads. TOPIC_FILE is retained as the
# name the popup redirect and the read-back use.
TOPIC_FILE="$DRAFT_FILE"

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
    #   * a cancel with TEXT still in the buffer, or gum dying for any other
    #     reason with nothing on stderr. Indistinguishable from a deliberate
    #     Esc at the tmux layer — but not on disk, which is where the answer
    #     is: an Esc on an empty buffer leaves an empty file, and anything
    #     that reached the file is content the operator would rather not
    #     retype. So the buffer decides whether this is silence or a report.
    if [ -n "$POPUP_ERR" ]; then
        if [ -s "$TOPIC_FILE" ]; then
            keep_draft 10000 "gc visit: could not open the input popup: $POPUP_ERR"
        else
            drop_draft
            say 10000 "gc visit: could not open the input popup: $POPUP_ERR"
        fi
        exit 1
    fi
    if [ -s "$TOPIC_FILE" ]; then
        keep_draft 10000 "gc visit: cancelled with text in the buffer — nothing was filed"
        exit 0
    fi
    drop_draft
    exit 0
fi

TOPIC=$(cat "$TOPIC_FILE" 2>/dev/null || true)

# 4. A blank (or whitespace-only) submit is not an error and not a topic.
#    Say so rather than filing a bead with an empty title.
#
#    This branch is ALSO where a truncated write lands: if the redirect wrote
#    nothing because the filesystem was full, a paragraph reaches here looking
#    exactly like an empty submit, and the two cannot be told apart from the
#    file alone. Nothing is preserved because there is nothing in the file to
#    preserve — but the message has to hold long enough to be read, and to say
#    which of the two it might have been. Three seconds was not that.
if [ -z "$(printf '%s' "$TOPIC" | tr -d '[:space:]')" ]; then
    drop_draft
    say 8000 "gc visit: nothing typed — no bead filed. (If you DID type something, the draft write failed: check space on $(short "$DRAFT_DIR").)"
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
#
#    The draft crosses into this half as a PATH, and only this half may remove
#    it: the parent exits the moment this is backgrounded, so an EXIT trap up
#    there would delete the file while the intake it belongs to is still
#    running — which is precisely the race that lost the reported topic.
(
    # The parent's draft trap is not this subshell's to run; POSIX resets
    # caught traps in a subshell, but INDICATOR being empty would otherwise
    # leave that dependent on the shell, and a draft removed by the wrong
    # handler is the bug. Reset explicitly, then arm the indicator's own.
    trap - INT TERM HUP
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
        # losing the thought. The draft survives too, and is named FIRST —
        # even with a subject bead, the typed text is what a retry needs.
        DETAIL=$(printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | tail -1)
        [ "$RC" -eq 124 ] && DETAIL="timed out after ${INTAKE_TIMEOUT}s. ${DETAIL:-no output}"
        keep_draft 10000 "gc visit FAILED (rc=$RC)${SUBJECT:+ — subject $SUBJECT exists}: $DETAIL"
        exit 1
    fi

    # rc=0 is not by itself proof the thought is durable: the id is. A run that
    # exits clean having named neither a subject nor a visit has told us
    # nothing about what survived, so it is treated as unconfirmed and the
    # draft is kept — the one direction that cannot lose the text.
    if printf '%s\n' "$OUT" | grep -q 'first reaction slung'; then
        drop_draft
        say 6000 "gc visit: subject ${SUBJECT:-?} — first reaction slung; it writes the card and files the visit"
    elif [ -n "$VISIT" ]; then
        drop_draft
        say 6000 "gc visit: subject ${SUBJECT:-?} — visit $VISIT filed · prefix+S to attach"
    elif [ -n "$SUBJECT" ]; then
        drop_draft
        say 6000 "gc visit: subject $SUBJECT — $(printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | tail -1)"
    else
        keep_draft 10000 "gc visit: intake exited 0 but named no subject or visit — nothing is confirmed filed: $(printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | tail -1)"
    fi
) >/dev/null 2>&1 &
