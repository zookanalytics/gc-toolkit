#!/usr/bin/env bash
# converse-parent.sh — read a subject's OWN parent, so everything a sitting
# files lands as a SIBLING of the subject rather than a child. beads refuses a
# `blocks` edge from a parent to its own descendant, so a demand or work bead
# filed under the subject could never gate it; giving it the subject's parent
# (or no parent, when the subject has none) is what lets the edge carry the
# wait. A parent-child edge is stored on the child, so it is read off the
# subject. Prints the parent id, or an empty line when the subject has none.
#
# Input (environment, or positional fallback):
#   SUBJECT  the subject bead ($1)
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

SUBJECT="${SUBJECT:-${1:-}}"

[ -n "$SUBJECT" ] || { echo "converse-parent: a subject id is required (\$SUBJECT or arg 1)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "converse-parent: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "converse-parent: gc is required" >&2; exit 2; }

PARENT=$(gc bd show "$SUBJECT" --json | scrub | jq -r '
  [ .[0].dependencies[]?
    | select(((.dependency_type // .type // "") | tostring) == "parent-child")
    | ((.id // .depends_on_id // "") | tostring) ] | map(select(. != "")) | .[0] // ""')
printf '%s\n' "$PARENT"
