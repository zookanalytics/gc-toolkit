#!/bin/sh
# tmux-dismiss-sitting.sh — prefix+X: end the converse sitting in view. It is
# the keystroke for `gc-helm dismiss`, which, with no bead named, infers the
# sitting's subject from the caller's session identity and closes the open
# visit that holds the sitting up. While an open gate linked to the sitting is
# undecided, dismiss holds instead, and the key names the gate.
#
# Usage: tmux-dismiss-sitting.sh <config-dir> [--city-path <path>]
#
# Bound by tmux-bindings.sh behind confirm-before, as a backgrounded run-shell.
# It reads the session the key was pressed in, looks that session up in
# `gc session list`, and refuses unless it runs a converse template. Then it
# runs `gc-helm.sh dismiss` under the identity on that record (session name,
# id, alias), the identity a `!` command typed inside the sitting carries, so
# dismiss's own fail-closed inference picks the subject. The identity comes
# from the record, not from the job's environment. The record is what says
# whether this is a converse sitting, and a non-converse Gas City pane
# carries an identity of its own that dismiss would act on all the same.
#
# Nothing is typed into the pane. A keystroke sent there lands in whatever
# program holds it, including a reply half-typed into the converse composer.
#
# --city-path is baked in by tmux-bindings.sh at install time, so `gc` resolves
# the same city whichever pane the key is pressed in.
#
# Every outcome reaches the operator as a tmux message, and the script exits 0
# with nothing on stdout: run-shell lays a view pane over the thread the
# operator is reading whenever a job prints or exits non-zero.
set -u

CONFIGDIR="${1:-}"
[ $# -gt 0 ] && shift
CITY_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --city-path) CITY_PATH="${2:-}"; [ $# -gt 1 ] && shift; shift ;;
        *) shift ;;
    esac
done

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# Capture WHO pressed the key: the client the messages go to, and the session
# on its screen. The tmux session name is the Gas City session_name.
CLIENT=$(gcmux display-message -p '#{client_tty}' 2>/dev/null || true)
SESSION=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)
[ -n "$SESSION" ] || SESSION=$(gcmux display-message -p '#{session_name}' 2>/dev/null || true)

# say <duration-ms> <message> — the operator's only feedback channel. tmux
# expands formats in a message, and `#(...)` there runs a command, so every #
# is doubled: a session name or a gc diagnostic is shown, never expanded.
say() {
    _d="$1"; shift
    _m=$(printf '%s' "$*" | sed 's/#/##/g')
    # shellcheck disable=SC2086 # ${CLIENT:+…} deliberately expands to 0 or 2 words
    gcmux display-message ${CLIENT:+-c "$CLIENT"} -d "$_d" "$_m" >/dev/null 2>&1 || true
}

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

HELM="$CONFIGDIR/assets/scripts/gc-helm.sh"
if [ -z "$CONFIGDIR" ] || [ ! -f "$HELM" ]; then
    say 10000 "dismiss: gc-helm.sh not found under '${CONFIGDIR:-<no config dir>}' — nothing dismissed"
    exit 0
fi
if [ -z "$SESSION" ]; then
    say 10000 "dismiss: tmux did not say which session the key was pressed in — nothing dismissed"
    exit 0
fi

if [ -n "$CITY_PATH" ]; then
    export GC_CITY_PATH="$CITY_PATH"
    cd "$CITY_PATH" 2>/dev/null || true
fi

# The record behind this pane. A listing that did not answer is a fault, never
# a reading of "not a converse sitting", so it gets its own message. A closed
# record is a past session under the same name, not the pane on screen.
LIST=$(gc session list --state all --json 2>/dev/null | scrub)
if ! printf '%s' "$LIST" | jq -e 'type == "object" and ((.sessions // null) | type) == "array"' >/dev/null 2>&1; then
    say 10000 "dismiss: could not read 'gc session list' — nothing dismissed"
    exit 0
fi
ROWS=$(printf '%s' "$LIST" | jq -c --arg s "$SESSION" '
    [ .sessions[] | objects
      | select((.session_name // "") == $s)
      | select((.closed // false) != true) ]' 2>/dev/null) || ROWS="[]"
COUNT=$(printf '%s' "$ROWS" | jq 'length' 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
if [ "$COUNT" -eq 0 ]; then
    say 8000 "dismiss: '$SESSION' is not a live Gas City session — nothing dismissed"
    exit 0
fi
if [ "$COUNT" -gt 1 ]; then
    say 10000 "dismiss: $COUNT live sessions are named '$SESSION'; refusing to guess which — nothing dismissed"
    exit 0
fi
field() { printf '%s' "$ROWS" | jq -r --arg k "$1" '.[0][$k] // "" | tostring' 2>/dev/null || true; }

# A converse sitting runs a converse template: the pack's base converse agent
# or one of its per-model variants, under any rig.
TEMPLATE=$(field template)
case "${TEMPLATE##*/}" in
    gc-toolkit.converse|gc-toolkit.converse-*) ;;
    *)
        say 8000 "dismiss: '$SESSION' is not a converse sitting (template '${TEMPLATE:-none}') — nothing dismissed"
        exit 0 ;;
esac

ERR=$(mktemp "${TMPDIR:-/tmp}/gctk-tmux-dismiss.XXXXXX" 2>/dev/null) || ERR=""
[ -n "$ERR" ] && trap 'rm -f "$ERR"' EXIT

say 30000 "dismiss: ending this converse sitting…"

# The sitting's own identity and rig, and no store pin: BEADS_DIR is unset in a
# converse session, so dismiss resolves the store from the rig the way a `!`
# command typed in the sitting would.
unset BEADS_DIR
RC=0
OUT=$(GC_SESSION_NAME="$(field session_name)" GC_SESSION_ID="$(field id)" \
    GC_ALIAS="$(field alias)" GC_RIG="$(field rig)" \
    sh "$HELM" dismiss --json 2>"${ERR:-/dev/null}") || RC=$?

# Exit 5 with the held object on stdout is dismiss holding for a gate decision:
# closing the sitting would orphan an open linked gate, so nothing was closed.
# A decision takes a ruling, which a keystroke cannot carry, so the message
# names each gate and the flags of the dismiss that decides it. The refusal
# below would show only dismiss's last stderr line, which names no gate.
if [ "$RC" -eq 5 ] && printf '%s' "$OUT" | jq -e '.held_for_gate_decision == true' >/dev/null 2>&1; then
    SUBJECT=$(printf '%s' "$OUT" | jq -r '.subject // ""' 2>/dev/null || true)
    GATES=$(printf '%s' "$OUT" | jq -r '
        [ .gates[]?
          | ((.demand // "") | gsub("[[:cntrl:]]+"; " ")) as $d
          | "\(.id // "?") (blocks \(.blocks // "?")) \"\(if $d == "" then "<no headline>" else $d end)\"" ]
        | join("; ")' 2>/dev/null || true)
    say 15000 "dismiss: NOT dismissed — ${SUBJECT:-?} carries open linked gate(s) a dismiss would orphan: ${GATES:-?}. Decide each, then re-run dismiss in the sitting with --resolve-gate <gate> --ruling \"<decision>\" to settle it or --leave-gate <gate> to leave it open"
    exit 0
fi

if [ "$RC" -ne 0 ]; then
    WHY=""
    [ -n "$ERR" ] && WHY=$(grep -v '^[[:space:]]*$' "$ERR" 2>/dev/null | tail -n 1)
    [ -n "$WHY" ] || WHY="gc-helm dismiss exited $RC with no diagnostic"
    say 10000 "dismiss: NOT dismissed — $WHY"
    exit 0
fi

SUBJECT=$(printf '%s' "$OUT" | jq -r '.subject // ""' 2>/dev/null || true)
VISITS=$(printf '%s' "$OUT" | jq -r '[.matched[]?.id] | join(" ")' 2>/dev/null || true)
CLOSED=$(printf '%s' "$OUT" | jq -r '.closed // 0' 2>/dev/null || echo 0)
case "$CLOSED" in ''|*[!0-9]*) CLOSED=0 ;; esac
if [ "$CLOSED" -gt 0 ]; then
    say 6000 "dismiss: the sitting on ${SUBJECT:-?} is over (visit ${VISITS:-?} closed); its session closes after you leave it"
else
    say 6000 "dismiss: no open visit on ${SUBJECT:-?} — nothing was holding a sitting"
fi
exit 0
