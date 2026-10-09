#!/bin/sh
# tmux-visit-prompt.sh — `prefix + a`: pick a rig, type a message, get a
# durable conversation. Usage: tmux-visit-prompt.sh <config-dir>
# Bound by tmux-bindings.sh (run-shell -b). A first popup picks the target rig,
# because the rig is the scope the report is filed against — defaulted to the
# pane's own rig, offering the non-hq rigs and tagging any that is suspended or
# not running. A suspended rig keeps its beads store, so a report filed there is
# recorded and triaged on resume; the hq store is withheld because it runs no
# reaction pool, though its bead ids stay valid subjects. The rig set is read
# from `gc rig list --json`, whose cost is the per-rig liveness probe, and is
# cached for GC_VISIT_RIG_CACHE_TTL seconds so a burst of presses opens the
# picker without re-paying that wait. A second popup then runs `gum write`
# (multi-line by design — command-prompt is single-line and its response is
# re-parsed as a tmux command); the submitted text goes through a
# per-press DRAFT FILE to gc-visit-open.sh, which mints the subject and queues
# the conversation, and the chosen rig reaches it as --rig. A bare bead id is an
# existing-bead request whose own rig is authoritative, so the chosen rig is
# dropped for one — the intake refuses --rig there. The draft is removed at
# exactly two moments —
# the intake CONFIRMS an id, or the file is provably empty — and every other
# path keeps it and names its path (this key's whole purpose is
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

# Seconds to cache the rig set. `gc rig list --json` costs a per-rig liveness
# probe, and asking the operator to pick a rig FIRST would pay it before the
# popup opens; caching it lets a burst of presses reuse one lookup. running and
# suspended can go stale within the window, but the intake validates the actual
# target, so the staleness is bounded and benign. 0 disables the cache.
RIG_CACHE_TTL="${GC_VISIT_RIG_CACHE_TTL:-900}"
case "$RIG_CACHE_TTL" in ''|*[!0-9]*) RIG_CACHE_TTL=900 ;; esac

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

# 3. Pick the target rig FIRST — the rig is the scope the report is filed
# against, so it is chosen before the message is typed. Default the
# board-context rig, override to any non-hq rig (Enter confirms the highlighted
# default). The hq/city-workspace store is dropped from the offer (see below):
# it runs no reaction pool, so a topic filed there would park with no session to
# engage it. A suspended or not-running rig is tagged, not withheld: gc rig
# suspend keeps its beads store, so a report filed there is recorded and triaged
# on resume, and the intake allows it. A broken or empty `gc rig list` skips the
# chooser and lets the intake apply its own default; an Esc cancels the whole
# press, and nothing is typed yet to keep.
#
# The rig set comes from `gc rig list --json`, whose cost is the per-rig
# liveness probe. It runs in the foreground before the message popup and outside
# the intake timeout below, so it is BOUNDED — a `gc rig list` wedged against a
# dead data plane falls to an empty list (chooser skipped) rather than stranding
# the operator at a rig-less prompt — and CACHED, so a burst of presses opens the
# picker without re-paying the probe. Only a valid, non-empty rig set is cached;
# a wedged or empty answer is never stored as the answer. The temp write uses
# $$ (not mktemp) so a concurrent press never reads a half-written cache.
RIG_LIST_JSON=""
RIG_CACHE_FILE="$DRAFT_DIR/rig-list.cache"
mkdir -p "$DRAFT_DIR" 2>/dev/null || true
if [ "$RIG_CACHE_TTL" -gt 0 ] && [ -f "$RIG_CACHE_FILE" ] \
   && [ -z "$(find "$RIG_CACHE_FILE" -mmin +"$(( (RIG_CACHE_TTL + 59) / 60 ))" 2>/dev/null)" ]; then
    RIG_LIST_JSON=$(cat "$RIG_CACHE_FILE" 2>/dev/null || true)
fi
if [ -z "$RIG_LIST_JSON" ]; then
    if command -v timeout >/dev/null 2>&1; then
        RIG_LIST_JSON=$(timeout "$INTAKE_TIMEOUT" gc rig list --json 2>/dev/null || true)
    else
        RIG_LIST_JSON=$(gc rig list --json 2>/dev/null || true)
    fi
    if [ "$RIG_CACHE_TTL" -gt 0 ] \
       && printf '%s' "$RIG_LIST_JSON" | jq -e '(.rigs | length) > 0' >/dev/null 2>&1; then
        if printf '%s' "$RIG_LIST_JSON" > "$RIG_CACHE_FILE.$$" 2>/dev/null; then
            mv -f "$RIG_CACHE_FILE.$$" "$RIG_CACHE_FILE" 2>/dev/null \
                || rm -f "$RIG_CACHE_FILE.$$" 2>/dev/null || true
        fi
    fi
fi
# The hq store is the city-level workspace, not a topic target: it runs no
# reaction pool, so a prefix+a topic filed there parks on the board with no
# session to engage it. Drop it from the chooser so it cannot be picked. Its
# prefix still marks its ids as bead refs below — an existing hq-store bead is a
# valid subject — and the intake backstops any other pool-less rig.
RIG_LIST=$(printf '%s' "$RIG_LIST_JSON" \
    | jq -r '.rigs[]? | select((.hq // false) | not) | .name' 2>/dev/null || true)
CHOSEN_RIG=""
if [ -n "$RIG_LIST" ]; then
    # The context rig leads the list so gum highlights it and Enter confirms it,
    # then the rest follow. When it is the only rig the tail is empty and grep
    # exits 1 — a legitimate result that must not trip set -e and kill the
    # script before the operator can type the report.
    RIG_CHOICES="$RIG_LIST"
    if [ -n "$CONTEXT_RIG" ] && printf '%s\n' "$RIG_LIST" | grep -qxF -- "$CONTEXT_RIG"; then
        RIG_CHOICES=$(printf '%s\n' "$CONTEXT_RIG"; printf '%s\n' "$RIG_LIST" | grep -vxF -- "$CONTEXT_RIG" || true)
    fi
    # A paused rig stays in the list, tagged so the choice is informed; the tag
    # is a display suffix stripped off the selection before it reaches --rig.
    RIG_ARGS=""
    for _r in $RIG_CHOICES; do
        _tag=$(printf '%s' "$RIG_LIST_JSON" | jq -r --arg n "$_r" \
            '.rigs[]? | select(.name==$n) | if .suspended==true then " (suspended)" elif .running==false then " (not running)" else "" end' 2>/dev/null | head -n1)
        RIG_ARGS="$RIG_ARGS $(sq "$_r$_tag")"
    done
    # A dedicated temp file: the rig is chosen before the draft exists, so the
    # popup body writes the selection where the parent reads it back. A refused
    # mktemp skips the chooser (the intake keeps its default) rather than aborting
    # the press — the draft-file guard below is the one that reports and exits.
    RIG_FILE=$(mktemp "${TMPDIR:-/tmp}/gc-visit-rig-XXXXXX" 2>/dev/null || printf '')
    if [ -n "$RIG_FILE" ]; then
        CHOOSE_RC=0
        # shellcheck disable=SC2086 # ${CLIENT:+…} and the pre-quoted $RIG_ARGS both expand deliberately
        CHOOSE_ERR=$(gcmux display-popup -E ${CLIENT:+-c "$CLIENT"} -w "$POPUP_W" -h "$POPUP_H" \
            "gum choose --header $(sq 'File this report into which rig? (Enter confirms the highlighted default)')$RIG_ARGS > $(sq "$RIG_FILE")" \
            2>&1) || CHOOSE_RC=$?
        if [ "$CHOOSE_RC" -ne 0 ]; then
            # Esc/cancel, or a popup that never opened: nothing is typed yet, so
            # the whole press is cancelled cleanly and there is no draft to keep.
            rm -f "$RIG_FILE"
            say 4000 "gc visit: cancelled at rig selection${CHOOSE_ERR:+ ($CHOOSE_ERR)} — nothing filed (nothing was typed yet)"
            exit 0
        fi
        # The label carried a tag for a paused rig; a rig name has no spaces, so
        # the first field is the name the intake wants.
        CHOSEN_RIG=$(cut -d' ' -f1 "$RIG_FILE" 2>/dev/null | tr -d '[:space:]' || true)
        rm -f "$RIG_FILE"
    fi
fi

# 4. Read the message. One file per press (see the header), kept unless it is
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

# 5. A blank submit is not an error and not a topic. A truncated write (full
#    filesystem) lands here too and cannot be told apart, so the message says
#    which of the two it might have been.
if [ -z "$(printf '%s' "$TOPIC" | tr -d '[:space:]')" ]; then
    drop_draft
    say 8000 "gc visit: nothing typed — no bead filed. (If you DID type something, the draft write failed: check space on $(short "$DRAFT_DIR").)"
    exit 0
fi

# 6. A bare bead id is an existing-bead request, not a new report, and the rig
# was already chosen above without knowing that. gc-visit-open.sh resolves a
# bead id against the bead's OWN rig and REFUSES --rig for it (exit 2), so the
# chosen rig must be DROPPED — otherwise a bead id filed through this key fails
# whenever the city has live rigs. Mirror the intake's bead-vs-topic gate:
# id-shaped (nothing outside [A-Za-z0-9_-], no leading '-', at least one '-')
# AND the prefix before the first '-' names a rig in this enumeration. Match
# every rig, not just the non-hq ones the picker offered — the intake resolves
# an id against all rigs, so a suspended or hq rig's prefix still marks its ids
# as beads. An id-shaped topic whose prefix names no rig stays a topic and keeps
# the chosen rig.
case "$TOPIC" in
    *[!a-zA-Z0-9_-]*|-*) : ;;
    *-*)
        if printf '%s' "$RIG_LIST_JSON" \
            | jq -e --arg p "${TOPIC%%-*}" 'any(.rigs[]?; .prefix == $p)' >/dev/null 2>&1; then
            CHOSEN_RIG=""
        fi ;;
esac

# 7. Background the slow half (seconds, up to GC_HELM_RIG_TIMEOUT). stdout/
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
