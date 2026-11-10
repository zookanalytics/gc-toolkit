#!/bin/sh
# tmux-new-subject.sh — prefix+A: raise a brand-new topic and converse about it.
# Runs `gc-helm engage --new-subject` in the fresh tmux window the binding
# opened, where it opens the conversation form on a new topic: the question, the
# rig, the model and whether to attach on one screen. The sibling prefix+a files
# a bead for triage; this one starts a conversation.
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

# The form saves the question and starts its sitting, and attaches to the
# sitting once it starts unless its Attach field is off. Either way its last
# lines say what happened: engage's account of the sitting once the attach
# returns, or the form's note of what it saved or kept. So the window is held
# open for a keypress rather than closing over them. On a pipe (a hermetic test)
# the read returns at once and nothing blocks.
sh "$HELM" engage --new-subject || true
printf '\n[new-subject: done — press Enter to close this window] '
read -r _ || true
