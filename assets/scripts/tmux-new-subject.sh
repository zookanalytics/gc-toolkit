#!/bin/sh
# tmux-new-subject.sh — prefix+A: raise a brand-new topic and converse about it
# now. Runs `gc-helm engage --new-subject` as a REAL interactive prompt (rig,
# subject, model) in the fresh tmux window the binding opened. tmux's one-line
# command-prompt cannot carry a subject line plus a menu, so the prompt needs a
# full terminal; the sibling prefix+a files a bead for triage, this one opens a
# conversation.
#
# Usage: tmux-new-subject.sh <config-dir> [--city-path <path>]
#
# --city-path is baked in by tmux-bindings.sh at install time: a key pressed
# outside a Gas City session's pane carries no city in its environment, so `gc`
# would otherwise have no city to resolve rigs against or file the subject in.
set -e

CONFIGDIR="${1:-}"
[ -n "$CONFIGDIR" ] || { echo "tmux-new-subject.sh: missing config-dir" >&2; exit 1; }
shift

CITY_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --city-path) CITY_PATH="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done
[ -n "$CITY_PATH" ] && export GC_CITY_PATH="$CITY_PATH"

HELM="$CONFIGDIR/assets/scripts/gc-helm.sh"
[ -f "$HELM" ] || { echo "tmux-new-subject.sh: gc-helm.sh not found at $HELM" >&2; exit 1; }

# --no-attach spawns and binds the sitting without taking over this window — the
# operator cycles to it from prefix+S, the way they work. engage prints the
# spawn summary (or any refusal) on exit, so hold the window open for a keypress
# rather than let it close over the one line that says what happened. On a pipe
# (a hermetic test) the read returns at once and nothing blocks.
sh "$HELM" engage --new-subject --no-attach || true
printf '\n[new-subject: done — press Enter to close this window] '
read -r _ || true
