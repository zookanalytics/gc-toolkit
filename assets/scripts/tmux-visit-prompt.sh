#!/bin/sh
# tmux-visit-prompt.sh — `prefix + a`: type a message, get a durable
# conversation. Usage: tmux-visit-prompt.sh <config-dir>
# Bound by tmux-bindings.sh (run-shell -b). Opens a tmux popup running
# `gum write` (multi-line by design — command-prompt is single-line and its
# response is re-parsed as a tmux command, tk-7z8c6); the submitted text goes
# through a per-press DRAFT FILE to gc-visit-open.sh, which mints the subject
# and queues the conversation. A second popup then picks the target rig —
# defaulted to the pane's own rig, offering only live ones — and passes it as
# --rig; gc-visit-open.sh validates the choice and refuses a suspended rig, so a
# report can never vanish into a store nothing reads. The draft is removed at
# exactly two moments —
# the intake CONFIRMS an id, or the file is provably empty — and every other
# path keeps it and names its path (tk-w4dp4: this key's whole purpose is
# that a thought is never lost). Esc cannot be recovered: gum never emits an
# unsubmitted buffer, so every cancel says that it discarded. Drafts live
# outside /tmp by default and are reaped after GC_VISIT_DRAFT_KEEP_DAYS.
# The slow intake half is backgrounded; a status-line indicator carries the
# in-flight state and display-message carries the outcome.
set -eu

CONFIGDIR="${1:?missing config-dir}"

VISIT_OPEN="${GC_VISIT_OPEN_TOOL:-$CONFIGDIR/assets/scripts/gc-visit-open.sh}"

# Seconds to let the intake run before calling it stuck. See the bound below.
INTAKE_TIMEOUT="${GC_VISIT_INTAKE_TIMEOUT:-300}"

# Draft dir precedence: override/test seam, pack state dir, XDG state (real
# disk, not the shared tmpfs), /tmp last and announced.
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

# Drafts are reaped on a window of days, never on exit.
DRAFT_KEEP_DAYS="${GC_VISIT_DRAFT_KEEP_DAYS:-14}"

# Popup geometry: percentages scale with the client; the textarea fits a
# 24-row terminal under the border + gum chrome.
POPUP_W="${GC_VISIT_POPUP_WIDTH:-80%}"
POPUP_H="${GC_VISIT_POPUP_HEIGHT:-50%}"
INPUT_H="${GC_VISIT_INPUT_HEIGHT:-8}"

# gum's own hint line names the submit/newline keys; the header carries only
# what it omits.
POPUP_HEADER='visit topic — multi-line is fine; Esc discards'
POPUP_PLACEHOLDER="What's on your mind?"

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# sq — POSIX shell-quote for the popup's sh -c body (the MESSAGE itself
# never goes near it).
sq() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# 1. Capture WHO pressed the key now, while the client context exists — the
#    backgrounded half is detached and cannot recover it.
CLIENT=$(gcmux display-message -p '#{client_tty}' 2>/dev/null || true)
SESSION=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)
[ -n "$SESSION" ] || SESSION=$(gcmux display-message -p '#{session_name}' 2>/dev/null || true)
AGENT=""
CONTEXT_RIG=""
if [ -n "$SESSION" ]; then
    # gascity names tmux sessions `<rig>__<agent>`, so the suffix is the
    # fallback when the session environment carries no GC_AGENT.
    AGENT=$(gcmux show-environment -t "$SESSION" GC_AGENT 2>/dev/null | sed -n 's/^GC_AGENT=//p')
    [ -n "$AGENT" ] || AGENT=$(printf '%s' "$SESSION" | sed 's/.*__//')
    # The board context: the rig of the pane the key was pressed in, used as the
    # default report target below. Prefer the session environment's GC_RIG; fall
    # back to the `<rig>__<agent>` session-name prefix. Empty on a pane that
    # names no rig — the chooser then leaves the default to the intake.
    CONTEXT_RIG=$(gcmux show-environment -t "$SESSION" GC_RIG 2>/dev/null | sed -n 's/^GC_RIG=//p')
    if [ -z "$CONTEXT_RIG" ]; then
        case "$SESSION" in
            *__*) CONTEXT_RIG=$(printf '%s' "$SESSION" | sed 's/__.*//') ;;
        esac
    fi
fi
# Indicator slot contract: gc-toolkit-status-line.sh renders
# /tmp/gc-status-<slug>.indicator verbatim.
INDICATOR=""
[ -n "$AGENT" ] && INDICATOR="/tmp/gc-status-$(printf '%s' "$AGENT" | sed 's|[./]|-|g').indicator"

# say <duration-ms> <message> — the operator's only feedback channel.
say() {
    _d="$1"; shift
    # shellcheck disable=SC2086 # ${CLIENT:+…} deliberately expands to 0 or 2 words
    gcmux display-message ${CLIENT:+-c "$CLIENT"} -d "$_d" "$*" 2>/dev/null || true
}

# 2. Check both dependencies BEFORE the popup.
if [ ! -x "$VISIT_OPEN" ]; then
    say 10000 "gc visit: intake script missing or not executable at $VISIT_OPEN"
    exit 1
fi

# A missing gum would flash "command not found" in a closing popup.
if ! command -v gum >/dev/null 2>&1; then
    say 10000 "gc visit: 'gum' not on PATH; install with 'brew install gum'"
    exit 1
fi

# 3. Read the message. One file per press (see the header), kept unless it is
#    empty or the intake confirms an id.

# short <path> — ~-abbreviated; draft messages LEAD with the path because
# display-message truncates and the path is the recovery handle.
short() {
    case "${HOME:-}" in
        "") printf '%s' "$1" ;;
        *) case "$1" in
               "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
               *) printf '%s' "$1" ;;
           esac ;;
    esac
}

# keep_draft <ms> <reason> — preserve the file, lead with its path.
keep_draft() {
    say "$1" "DRAFT KEPT $(short "$DRAFT_FILE") — $2"
}

# drop_draft — remove it. Only ever called where there is provably nothing to
# lose (empty or whitespace-only) or where an id came back.
drop_draft() { rm -f "$DRAFT_FILE"; }

# Created before the popup (nowhere-to-write must be discovered before the
# paragraph). The fallback is a SUBDIRECTORY of the temp root, never the root
# itself: the reaper deletes draft-* in whatever this names, and the shared
# root would put other tools' files inside its reach.
if ! mkdir -p "$DRAFT_DIR" 2>/dev/null || ! [ -w "$DRAFT_DIR" ]; then
    DRAFT_DIR="${TMPDIR:-/tmp}/gc-visit-drafts"
    say 10000 "gc visit: draft dir is not writable — falling back to $(short "$DRAFT_DIR") for this press"
    mkdir -p "$DRAFT_DIR" 2>/dev/null || true
fi

# Reap recovered-long-ago drafts; scoped to this dir + the draft- prefix.
if command -v find >/dev/null 2>&1; then
    find "$DRAFT_DIR" -maxdepth 1 -type f -name 'draft-*' -mtime "+$DRAFT_KEEP_DAYS" -delete 2>/dev/null || true
fi

# mktemp guarded: unguarded under set -eu it dies silently before the popup
# (a live path — /tmp exhaustion recurs here). draft-<utc>-XXXXXX sorts
# newest-last and stays short enough for a truncated display-message.
DRAFT_FILE=""
if ! DRAFT_FILE=$(mktemp "$DRAFT_DIR/draft-$(date -u +%Y%m%d-%H%M%S)-XXXXXX" 2>/dev/null) \
   || [ -z "$DRAFT_FILE" ]; then
    say 10000 "gc visit: cannot create a draft file in $(short "$DRAFT_DIR") (disk full, or the directory is unwritable) — nothing was opened, so nothing was typed and lost"
    exit 1
fi

# A crash is exactly when the draft must survive; no EXIT trap — normal
# exits are decided explicitly, one path at a time.
trap 'keep_draft 10000 "gc visit interrupted"; exit 1' INT TERM HUP

TOPIC_FILE="$DRAFT_FILE"

POPUP_RC=0
# -c "$CLIENT": "current" is not reliably the presser on a multi-client
# server. stderr distinguishes a cancel from a popup that never opened.
# shellcheck disable=SC2086 # ${CLIENT:+…} deliberately expands to 0 or 2 words
POPUP_ERR=$(gcmux display-popup -E ${CLIENT:+-c "$CLIENT"} -w "$POPUP_W" -h "$POPUP_H" \
    "gum write --show-help --height $(sq "$INPUT_H") --header $(sq "$POPUP_HEADER") --placeholder $(sq "$POPUP_PLACEHOLDER") > $(sq "$TOPIC_FILE")" \
    2>&1) || POPUP_RC=$?

if [ "$POPUP_RC" -ne 0 ]; then
    # Non-zero here is a cancel (tmux stderr empty) or a popup that never
    # opened (tmux says so on stderr). The buffer cannot disambiguate: gum
    # writes the buffer only on SUBMIT, so a cancel after five paragraphs
    # leaves a zero-byte file (measured through a real pty; no gum flag
    # changes it). Every cancel therefore SAYS it discarded — a silent cancel
    # is indistinguishable from a broken key. The keep_draft branch stays for
    # any path that does reach the file on a non-zero exit.
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
    say 4000 "gc visit: cancelled — nothing filed (Esc discards the draft; gum cannot hand back an unsubmitted buffer)"
    exit 0
fi

TOPIC=$(cat "$TOPIC_FILE" 2>/dev/null || true)

# 4. A blank submit is not an error and not a topic. A truncated write (full
#    filesystem) lands here too and cannot be told apart, so the message says
#    which of the two it might have been.
if [ -z "$(printf '%s' "$TOPIC" | tr -d '[:space:]')" ]; then
    drop_draft
    say 8000 "gc visit: nothing typed — no bead filed. (If you DID type something, the draft write failed: check space on $(short "$DRAFT_DIR").)"
    exit 0
fi

# 4b. Pick the target rig — default the board-context rig, override to any LIVE
# one (prefix+a → confirm). Suspended / not-running rigs are left out: a report
# filed there vanishes into a store nothing gathers, and the intake refuses one
# regardless. A broken or empty `gc rig list` skips the chooser and lets the
# intake apply its own default; an Esc keeps the draft, like the message popup.
# Withheld entirely for a bead id: gc-visit-open.sh treats an id-shaped argument
# whose prefix names a rig as an existing bead — the bead's own rig is
# authoritative and the intake refuses --rig for it — so offering a rig here
# would fail the bare-bead-id request this key supports (the `--` note below).
CHOSEN_RIG=""
# Bounded: this enumeration runs in the foreground before the message is filed
# and outside the intake timeout below, so a `gc rig list` wedged against a dead
# data plane would strand the operator at a chooser-less prompt — report typed,
# no indicator lit, no message. A timeout, a non-zero exit, or unparseable output
# all fall to an empty list, which skips the chooser and leaves the intake on its
# own default, the same as a genuinely empty list.
if command -v timeout >/dev/null 2>&1; then
    RIG_LIST_JSON=$(timeout "$INTAKE_TIMEOUT" gc rig list --json 2>/dev/null || true)
else
    RIG_LIST_JSON=$(gc rig list --json 2>/dev/null || true)
fi
# Bead id or new topic? Mirror gc-visit-open.sh's bead-vs-topic gate: id-shaped
# (nothing outside [A-Za-z0-9_-], no leading '-', at least one '-') AND the
# prefix before the first '-' names a rig in this enumeration. Match every rig,
# not just the live ones the picker offers — the intake resolves an id against
# all rigs, so a suspended rig's prefix still marks its ids as beads.
TOPIC_IS_BEADREF=""
case "$TOPIC" in
    *[!a-zA-Z0-9_-]*|-*) : ;;
    *-*)
        if printf '%s' "$RIG_LIST_JSON" \
            | jq -e --arg p "${TOPIC%%-*}" 'any(.rigs[]?; .prefix == $p)' >/dev/null 2>&1; then
            TOPIC_IS_BEADREF=1
        fi ;;
esac
RIG_LIST=$(printf '%s' "$RIG_LIST_JSON" \
    | jq -r '.rigs[]? | select((.suspended != true) and (.running != false)) | .name' 2>/dev/null || true)
if [ -z "$TOPIC_IS_BEADREF" ] && [ -n "$RIG_LIST" ]; then
    # The context rig leads the list so gum highlights it and Enter confirms it.
    RIG_CHOICES="$RIG_LIST"
    if [ -n "$CONTEXT_RIG" ] && printf '%s\n' "$RIG_LIST" | grep -qxF -- "$CONTEXT_RIG"; then
        RIG_CHOICES=$(printf '%s\n' "$CONTEXT_RIG"; printf '%s\n' "$RIG_LIST" | grep -vxF -- "$CONTEXT_RIG")
    fi
    RIG_ARGS=""
    for _r in $RIG_CHOICES; do RIG_ARGS="$RIG_ARGS $(sq "$_r")"; done
    RIG_FILE="$DRAFT_FILE.rig"
    CHOOSE_RC=0
    # shellcheck disable=SC2086 # ${CLIENT:+…} and the pre-quoted $RIG_ARGS both expand deliberately
    CHOOSE_ERR=$(gcmux display-popup -E ${CLIENT:+-c "$CLIENT"} -w "$POPUP_W" -h "$POPUP_H" \
        "gum choose --header $(sq 'File this report into which rig? (Enter confirms the highlighted default)')$RIG_ARGS > $(sq "$RIG_FILE")" \
        2>&1) || CHOOSE_RC=$?
    if [ "$CHOOSE_RC" -ne 0 ]; then
        # Esc/cancel, or a popup that never opened: the message is already typed,
        # so keep the draft and name it — the same contract as the message popup.
        rm -f "$RIG_FILE"
        keep_draft 10000 "gc visit: rig not chosen${CHOOSE_ERR:+ ($CHOOSE_ERR)} — nothing filed"
        exit 0
    fi
    CHOSEN_RIG=$(tr -d '[:space:]' < "$RIG_FILE" 2>/dev/null || true)
    rm -f "$RIG_FILE"
fi

# 5. Background the slow half (seconds, up to GC_HELM_RIG_TIMEOUT). stdout/
#    stderr closed so run-shell sees EOF at once (it waits on pipes, not the
#    process tree). Only this half may remove the draft — the parent exits
#    immediately.
(
    # Reset the parent's draft trap explicitly (a draft removed by the
    # wrong handler is the bug), then arm the indicator's own.
    trap - INT TERM HUP
    # Cleared on every exit path.
    if [ -n "$INDICATOR" ]; then
        trap 'rm -f "$INDICATOR"' EXIT INT TERM HUP
        echo "[opening visit...]" > "$INDICATOR" 2>/dev/null || true
    fi

    # `--` (a message may begin with "-"); NOT --topic (a bare bead id from
    # this key is a real request). Bounded: a hang against a wedged data
    # plane would leave the indicator lit and no message at all.
    # ${CHOSEN_RIG:+--rig "$CHOSEN_RIG"} passes the chosen rig only when one was
    # picked; empty leaves the intake on its own default. A rig name is a bare
    # identifier, so the unquoted expansion splits into exactly `--rig <name>`.
    RC=0
    if command -v timeout >/dev/null 2>&1; then
        # shellcheck disable=SC2086 # ${CHOSEN_RIG:+…} deliberately expands to 0 or 2 words
        OUT=$(timeout "$INTAKE_TIMEOUT" "$VISIT_OPEN" ${CHOSEN_RIG:+--rig "$CHOSEN_RIG"} -- "$TOPIC" 2>&1) || RC=$?
    else
        # shellcheck disable=SC2086 # ${CHOSEN_RIG:+…} deliberately expands to 0 or 2 words
        OUT=$("$VISIT_OPEN" ${CHOSEN_RIG:+--rig "$CHOSEN_RIG"} -- "$TOPIC" 2>&1) || RC=$?
    fi

    # Anchored on the reporting tool's own line prefix — an unanchored match
    # would find these words inside an echoed topic.
    SUBJECT=$(printf '%s\n' "$OUT" | sed -n 's/^[A-Za-z0-9_-]*: subject \([A-Za-z0-9][A-Za-z0-9_-]*\).*/\1/p' | head -1)
    VISIT=$(printf '%s\n' "$OUT" | sed -n 's/^[A-Za-z0-9_-]*: visit \([A-Za-z0-9][A-Za-z0-9_-]*\) filed .*/\1/p' | head -1)

    if [ "$RC" -ne 0 ]; then
        # Name the surviving subject when one was created; the draft is
        # named FIRST — the typed text is what a retry needs.
        DETAIL=$(printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | tail -1)
        [ "$RC" -eq 124 ] && DETAIL="timed out after ${INTAKE_TIMEOUT}s. ${DETAIL:-no output}"
        keep_draft 10000 "gc visit FAILED (rc=$RC)${SUBJECT:+ — subject $SUBJECT exists}: $DETAIL"
        exit 1
    fi

    # rc=0 alone is not proof of durability: the id is. No id = unconfirmed,
    # draft kept.
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
